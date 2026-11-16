import Foundation

/// アイテム変形を適用する描画エフェクト。本家 IVideoEffectProcessor のうち、
/// Source 契約に関わる面だけを切り出したもの。エフェクト連鎖の実行
/// （EffectedItemSource 相当）は次段の責務であり、ここでは入力設定と
/// DrawDescription の確定という境界だけを定める。
///
/// 所有権（第1章 IMG-03 で確定）: SetInput は入力の所有権を移さない。
/// ClearInput は、設定されていた入力を破棄しない。
public protocol DrawingEffectProcessor: AnyObject {
    /// 現在の出力（入力未設定・未更新なら nil もありうる）。
    var output: ImageReference? { get }
    /// 入力を設定する。所有権は移らない。
    func setInput(_ image: ImageReference?)
    /// 入力を解除する。解除された入力は破棄されない。
    func clearInput()
    /// 説明に基づいて出力を更新し、確定した描画変換を返す。
    @discardableResult
    func update(_ description: EffectDescription) -> DrawDescription
    /// 自身が所有する資源を解放する。
    func dispose()
}

/// Source の出力1件。本家 ISourceOutput（IDrawable を継承）に対応する。
///
/// **Draw メソッドは存在しない**（第3章で確定）。描画は消費者が Output を
/// エフェクト連鎖へ流すことで行われる。
/// TimeOffset / DurationOffset が非ゼロになるのはテキスト系の文字分割・
/// ルビ出力のみで、通常は .zero。
/// 所有者は生成した Source であり、消費者は Dispose しない（第3章）。
public protocol SourceOutput: AnyObject {
    /// この出力の素の画像（エフェクト未適用）への参照。
    var output: ImageReference { get }
    /// アイテム変形を適用する描画エフェクト（内部の一時出力では nil の
    /// 場合がある）。
    var drawingEffect: DrawingEffectProcessor? { get }
    /// 描画位置への加算オフセット。
    var drawingOffset: Vector2 { get }
    /// 回転・拡大の中心。
    var center: Vector2 { get }
    /// この出力が担当するアイテム内時間窓のずれ（開始側）。
    var timeOffset: TimeSpanValue { get }
    /// この出力が担当するアイテム内時間窓のずれ（長さ側）。
    var durationOffset: TimeSpanValue { get }
    /// 所有者（生成した Source）が差し替え・破棄時に呼ぶ。消費者は呼ばない。
    func dispose()
}

/// 本家 SourceOutput に対応する具象実装。プロパティは生成時に固定される。
///
/// 所有権は本家 dontDispose の反転で表す:
/// - `dontDispose == false`（既定）: DrawingEffect を所有し、Dispose で
///   ClearInput の後に破棄する。
/// - `dontDispose == true`: 画像・DrawingEffect とも借用し、Dispose で
///   破棄しない（所有者は生成した Source 側）。
/// 画像参照（ImageReference）は不透明なトークンで実体を持たないため、
/// この層では画像自体の解放操作は存在しない（実体の解放は GPU 実行層）。
public final class StandardSourceOutput: SourceOutput {
    public let output: ImageReference
    public let drawingEffect: DrawingEffectProcessor?
    public let drawingOffset: Vector2
    public let center: Vector2
    public let timeOffset: TimeSpanValue
    public let durationOffset: TimeSpanValue

    private let ownsDrawingEffect: Bool
    private var isDisposed = false

    public init(
        output: ImageReference,
        drawingEffect: DrawingEffectProcessor?,
        drawingOffset: Vector2 = .zero,
        center: Vector2 = .zero,
        timeOffset: TimeSpanValue = .zero,
        durationOffset: TimeSpanValue = .zero,
        dontDispose: Bool = false
    ) {
        self.output = output
        self.drawingEffect = drawingEffect
        self.drawingOffset = drawingOffset
        self.center = center
        self.timeOffset = timeOffset
        self.durationOffset = durationOffset
        self.ownsDrawingEffect = !dontDispose && drawingEffect != nil
    }

    public func dispose() {
        if isDisposed { return }
        isDisposed = true
        if ownsDrawingEffect {
            // 本家 SourceOutput.Dispose(bool) と同じ順序（ClearInput → 破棄）。
            drawingEffect?.clearInput()
            drawingEffect?.dispose()
        }
    }
}

/// 素材から出力を生成する単位。本家 ISource に対応する。
///
/// メンバは Controllers / Outputs / Update の3つ＋破棄のみ（第3章で確定）。
/// - Update は逐次進行命令ではなく、シーク・再評価を前提とする同期処理。
///   消費者は Update の後に Outputs を読む。
/// - Outputs の要素は次の Update で破棄・差し替えされうる。保持できるのは
///   同一処理単位の中だけ（IMG-05）。
/// - Update 前の Outputs の状態は実装依存（未確定事項として台帳に記録）。
public protocol Source: AnyObject {
    /// エディタ操作点。通常は空で、非空を返しうるのは図形系のみ。
    var controllers: [VideoController] { get }
    /// 現在の出力集合。
    var outputs: [any SourceOutput] { get }
    /// 説明に基づいて出力を最新化する。
    func update(_ description: TimelineItemSourceDescription)
    /// 自身が所有する資源（Context・出力・素材資源）を解放する。
    func dispose()
}

/// FrameBuffer 用の拡張契約。本家 IFrameBufferSource に対応する。
/// 他の Source と呼び出し規約が根本的に異なり、Input と FrameSize は
/// 合成側（TimelineSource 相当）が合成フェーズで外部から設定する。
public protocol FrameBufferSource: Source {
    /// 合成済みの蓄積画像（借用。所有権は移らない）。
    var input: ImageReference? { get set }
    /// フレームのサイズ。
    var frameSize: PixelSize { get set }
    /// 背景をクリアするか（false なら前回の蓄積を引き継ぐ）。
    var clearBackground: Bool { get }
}
