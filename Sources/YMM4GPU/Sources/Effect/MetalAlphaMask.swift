#if os(macOS)
import Foundation
import Metal
import YMM4Core

/// クリッピング（IsClippingWithObjectAbove）の実効マスクの Metal 実装
/// （MAC-0035、監査 AUD-03）。本家 D2D AlphaMask 効果に対応する。
///
/// 順序の設計（B-2(ii)）: 本家は効果グラフの遅延評価により、出力が
/// 公開された後（描画段）で SetAlphaMask により入力1（マスク画像）が
/// 設定されても最終描画へ反映される。こちらは実体化のタイミングで
/// 同じ意味論を作る:
/// - `output` は固定の参照トークンを返し、実体の登録は入力が揃った
///   時点で行う。消費者は描画時に登録表を引くため、後から差し替えた
///   実体がそのまま最終出力になる。
/// - 入力0（本体）は EffectedItemSource の更新内で設定され、この時点
///   では入力1が未設定のため「マスクなし = 全面透明」を登録する
///   （D2D で未設定入力が透明として扱われることに対応）。
/// - 入力1は合成器の描画段で設定され、その場で再実体化して登録を
///   差し替える。描画はその後に行われるため、公開済みの出力へ
///   正しく反映される。
/// 入力は合成器の描画先画像（変換なし・不透明度1・平面写像のみ）で
/// あることが呼び出し経路から保証される（EffectedItemSource の出力は
/// 常にその形であり、「直前の画像」も同じ）。warp パス（mode 3 = 素の
/// アルファマスク）で平面座標によりサンプルする。
public final class MetalAlphaMaskEffect: AlphaMaskEffect {
    private let context: MetalGraphicsContext
    /// 描画ヘルパ（Metal 処理器の基底が持つ warp パスを再利用する。
    /// 連鎖へは参加しない）。
    private let renderHelper: MetalEffectProcessor
    /// 失敗の報告先（描画セッションの診断収集先）。未設定なら報告しない。
    private let diagnostics: RenderDiagnosticsCollector?
    private var input0: ImageReference?
    private var input1: ImageReference?
    private let outputReference = ImageReference(label: "alpha-mask")
    private var isDisposed = false

    public init(
        context: MetalGraphicsContext,
        diagnostics: RenderDiagnosticsCollector? = nil
    ) {
        self.context = context
        self.renderHelper = MetalEffectProcessor(context: context)
        self.diagnostics = diagnostics
    }

    /// マスク適用後の出力。実体の登録は入力設定のたびに行われ、
    /// 未実体化の間は登録が無い（= 何も描かれない）。
    public var output: ImageReference? {
        outputReference
    }

    public func setInput(_ index: Int, _ image: ImageReference?) {
        if index == 0 {
            input0 = image
        } else if index == 1 {
            input1 = image
        } else {
            return
        }
        materialize()
    }

    public func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        renderHelper.dispose()
        context.devices.unregister(outputReference)
        input0 = nil
        input1 = nil
    }

    // MARK: - 内部

    /// 現在の入力から出力実体を作り直して登録する。GPU 実行が失敗した
    /// 場合は、不完全な画像（マスク未適用の本体）を正しい出力として
    /// 公開せず、透明を登録する（この境界は例外を投げられないため、
    /// MAC-0021 の「不完全な画像を公開しない」方針をこの形で守る）。
    private func materialize() {
        guard !isDisposed else { return }
        guard let input0,
              let source = context.devices.image(for: input0)
        else {
            context.devices.unregister(outputReference)
            return
        }
        guard let input1 else {
            // マスク未設定 = 全面透明（本家で未設定入力が透明として
            // 扱われることに対応）。
            registerTransparent(bounds: source.bounds)
            return
        }
        if context.devices.image(for: input1) == nil, input1.role == .floodSubstitute {
            // 「直前の画像」が無い場合に合成器が渡す Flood 代替トークンは、
            // 本家 TimelineSource がコンストラクタで作る不透明な白の
            // Flood 出力に対応する（B-2(i)）。素性はラベルではなく役割で
            // 識別する（ラベルはデバッグ専用で意味論に使わない）。
            // 実体が未登録であることも条件に含める: 役割はトークンの
            // 素性、未登録は実体が無いことの確認であり、役割が違う。
            // 全面不透明な白のマスクに
            // よる AlphaMask は恒等変換（出力 = 入力そのもの）である
            // ため、本体画像をそのまま出力として登録する。1×1 の白
            // テクスチャを経由する形は、サンプラの境界処理で全面が
            // 減衰するため採らない。
            context.devices.register(outputReference, image: source)
            return
        }
        guard let mask = context.devices.image(for: input1) else {
            registerTransparent(bounds: source.bounds)
            return
        }
        do {
            let result = try renderHelper.renderWarp(
                input: source,
                mask: mask,
                outputBounds: source.bounds,
                mode: 3
            )
            context.devices.register(outputReference, image: result)
        } catch {
            // 透明フォールバック自体は維持するが、失敗を無言にしない:
            // この境界は例外を投げられない（setInput は非 throwing）
            // ため、型付きの出来事としてセッションの収集先へ報告し、
            // 表示側が利用者へ知らせる（R6-06）。
            diagnostics?.record(
                kind: "alphaMaskWarp",
                message: "クリッピングのマスク合成に失敗しました: \(error)"
            )
            registerTransparent(bounds: source.bounds)
        }
    }

    private func registerTransparent(bounds: RectF) {
        context.devices.register(
            outputReference,
            image: MetalImage(
                texture: context.devices.transparentTexture,
                bounds: bounds,
                texturePlaneRect: bounds
            )
        )
    }
}

/// クリッピングマスクの生成者（本番実装）。合成器の生成経路ごとに、
/// その合成器が使う文脈へ束縛して生成する。診断収集先は、同じ描画
/// セッションの全ての生成者が同じインスタンスを共有する（内部
/// 合成器で発生した失敗も外側のセッションへ届くようにするため）。
public final class MetalAlphaMaskEffectFactory: AlphaMaskEffectFactory {
    private let context: MetalGraphicsContext
    private let diagnostics: RenderDiagnosticsCollector?

    public init(
        context: MetalGraphicsContext,
        diagnostics: RenderDiagnosticsCollector? = nil
    ) {
        self.context = context
        self.diagnostics = diagnostics
    }

    public func makeAlphaMaskEffect() -> any AlphaMaskEffect {
        MetalAlphaMaskEffect(context: context, diagnostics: diagnostics)
    }
}
#endif
