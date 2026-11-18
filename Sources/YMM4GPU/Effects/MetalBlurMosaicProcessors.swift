#if os(macOS)
import Foundation
import Metal
import YMM4Core

// MARK: - ガウスぼかし

/// ガウスぼかし。本家 `GaussianBlurEffect`（D2D 組み込み GaussianBlur）。
/// StandardDeviation = Blur の値そのもの（実測）、Optimization = Quality、
/// BorderMode は IsHardBorderMode で Hard / Soft を切り替える（実測）。
///
/// 実装は分離型の2パス。大きな σ では作業テクスチャを縮小してから
/// ぼかす（σ を作業解像度で 6 以下に収める）。これは D2D の Quality
/// 最適化の内部方式とは異なるが、ガウスぼかしの可視結果を保つための
/// 標準的な近似である（台帳に記録）。カーネルは ±3σ で打ち切る。
/// Soft 境界では出力境界が 3σ だけ広がり、範囲外は透明として読む。
/// Hard 境界では出力境界は入力と同じで、範囲外は鏡像として読む。
public final class MetalGaussianBlurProcessor: MetalEffectProcessor {
    private let definition: GaussianBlurEffectDefinition

    public init(context: MetalGraphicsContext, definition: GaussianBlurEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let (frame, length, fps) = evaluationContext(description)
        let sigma = definition.blur.value(atFrame: frame, length: length, fps: fps)
        // 本体は基底の共通ヘルパ（第2段の縁ぼかし・角丸・影と共有）。
        return try renderGaussianBlurred(
            input: input, sigma: sigma, hardBorder: definition.isHardBorderMode
        )
    }
}

// MARK: - モザイク

/// モザイク。本家 `MosaicEffect`。
///
/// 本家は形状パラメータ（MosaicParameter）が効果実体を決める。既定は
/// RectangleMosaicParameter で、その Size（Animation、既定 10）が
/// セル寸法になる（実測）。Size の評価は型付きパラメータの通常の
/// アニメーション評価経路（ベジェ・キーフレーム文脈を含む）で行い、
/// 本家カスタム効果の setter のクランプ（実測: 1〜5000）を適用する。
///
/// 矩形はセル内テクセルの平均（第1段の共通ヘルパ。第2段の
/// イン／アウトモザイクと共有）。他の5形状は本家カスタムシェーダの
/// 逆アセンブルから抽出した「代表点サンプル」方式で、Warp の
/// mode 7〜11 が担う。矩形の本家シェーダはセル内5点サンプルの平均
/// であり、現行の平均方式とは結果が異なる（既存の差分として台帳に
/// 記録。本 Issue の対象外）。
/// 未知の形状パラメータ（生保持）は従来どおり素通しとする。
public final class MetalMosaicProcessor: MetalEffectProcessor {
    private let definition: MosaicEffectDefinition

    public init(context: MetalGraphicsContext, definition: MosaicEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        guard let parameter = definition.mosaicParameter else {
            // パラメータ欠落時は本家の既定（RectangleMosaicParameter、
            // Size 既定 10）に従う。
            return try renderRectangleMosaic(input: input, cellSize: 10)
        }
        switch parameter {
        case .preserved:
            // 型付き化していない形状パラメータは素通し。
            return input
        case .sized(let sized):
            let (frame, length, fps) = evaluationContext(description)
            let size = min(
                5000, max(1, sized.size.value(atFrame: frame, length: length, fps: fps))
            )
            switch sized.shape {
            case .rectangle:
                return try renderRectangleMosaic(input: input, cellSize: size)
            case .circle:
                return try renderShapeMosaic(input: input, mode: 7, size: size)
            case .triangle:
                return try renderShapeMosaic(input: input, mode: 8, size: size)
            case .hexagon:
                return try renderShapeMosaic(input: input, mode: 9, size: size)
            case .voronoi:
                return try renderShapeMosaic(input: input, mode: 10, size: size, seed: seed)
            case .delaunay:
                return try renderShapeMosaic(input: input, mode: 11, size: size, seed: seed)
            case .unknown:
                return input
            }
        }
    }

    /// Voronoi / Delaunay の seed。本家はパラメータ生成時に
    /// `Seed = GetHashCode()`（.NET オブジェクト同一性ハッシュ、本家
    /// 実行ごとに非決定的で保存もされない）を渡す。こちらでは定義の
    /// `randomSeed`（本家 GetHashCode の代替シード。現状は 0 固定で、
    /// 対応付けは未解決事項）を使う。
    private var seed: Float {
        Float(definition.randomSeed)
    }

    private func renderShapeMosaic(
        input: MetalImage, mode: UInt32, size: Double, seed: Float = 0
    ) throws -> MetalImage {
        try renderWarp(
            input: input, mask: nil, outputBounds: input.bounds, mode: mode,
            param0: SIMD4<Float>(Float(size), seed, 0, 0)
        )
    }
}
#endif
