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
/// セル寸法になる（実測）。第1段では矩形のみを実装し、他の形状
/// （Circle / Triangle / Hexagon / Delaunay / Voronoi）は素通しとする。
/// セルの色はセル内テクセルの平均（本家カスタムシェーダの .cso は
/// 解析範囲に無く、平均か中心サンプルかは未確定。台帳に記録）。
public final class MetalMosaicProcessor: MetalEffectProcessor {
    private let definition: MosaicEffectDefinition

    public init(context: MetalGraphicsContext, definition: MosaicEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        guard let size = rectangleCellSize(description: description) else {
            // 矩形以外の形状は第1段では未対応（素通し）。
            return input
        }
        // 本体は基底の共通ヘルパ（第2段のイン／アウトモザイクと共有）。
        return try renderRectangleMosaic(input: input, cellSize: size)
    }

    /// 矩形モザイクのセル寸法を取り出す。パラメータが矩形でなければ nil。
    ///
    /// パラメータは生保持（PreservedObject）のため、Size の Animation は
    /// ここで JSON から直接復元する（CodecSupport は Core 内部のため）。
    /// キーフレーム文脈は型付きパラメータでないため伝播しない（既存の
    /// 定義層の制約と同じ。台帳に記録）。
    private func rectangleCellSize(description: EffectDescription) -> Double? {
        guard let parameter = definition.mosaicParameter else {
            // パラメータ欠落時は本家の既定（RectangleMosaicParameter、
            // Size 既定 10）に従う。
            return 10
        }
        guard let typeName = parameter.typeName,
              typeName.hasPrefix(
                "YukkuriMovieMaker.Project.Effects.MosaicParameters.RectangleMosaicParameter")
        else {
            return nil
        }
        var animation = Animation(defaultValue: 10, minValue: 0, maxValue: 2000)
        if case .object(let fields) = parameter.value,
           let sizeValue = fields.first(where: { $0.key == "Size" })?.value {
            Self.decodeAnimationSubset(sizeValue, into: &animation)
        }
        let (frame, length, fps) = evaluationContext(description)
        let value = animation.value(atFrame: frame, length: length, fps: fps)
        // 本家カスタム効果の setter のクランプ（実測: 1〜5000）。
        return min(5000, max(1, value))
    }

    /// Animation の保存形式のうち、値列・種類・Span と旧互換の
    /// From / To だけを復元する（ベジェは対象外）。
    private static func decodeAnimationSubset(_ value: JSONValue, into animation: inout Animation) {
        guard case .object(let fields) = value else { return }
        for (key, fieldValue) in fields {
            switch key {
            case "Values":
                if case .array(let elements) = fieldValue {
                    animation.values = elements.map { element in
                        if let number = Self.number(of: element) {
                            return AnimationValue(number)
                        }
                        if case .object(let elementFields) = element,
                           let valueField = elementFields.first(where: { $0.key == "Value" })?.value,
                           let number = Self.number(of: valueField) {
                            return AnimationValue(number)
                        }
                        return AnimationValue(0)
                    }
                }
            case "Span":
                if let number = Self.number(of: fieldValue) {
                    animation.span = number
                }
            case "AnimationType":
                if case .string(let name) = fieldValue,
                   let type = AnimationType(honkeName: name) {
                    animation.animationType = type
                } else if let number = Self.number(of: fieldValue),
                          let type = AnimationType(rawValue: Int(number)) {
                    animation.animationType = type
                }
            case "From":
                let number = Self.number(of: fieldValue) ?? 0
                if animation.values.isEmpty {
                    animation.values = [AnimationValue(number)]
                } else {
                    animation.values[0] = AnimationValue(number)
                }
            case "To":
                let number = Self.number(of: fieldValue) ?? 0
                if animation.values.isEmpty {
                    animation.values = [AnimationValue(0)]
                }
                if animation.values.count == 1 {
                    animation.values.append(AnimationValue(number))
                } else {
                    animation.values[1] = AnimationValue(number)
                }
            default:
                break
            }
        }
    }

    private static func number(of value: JSONValue) -> Double? {
        switch value {
        case .numberLiteral(let literal):
            return Double(literal)
        case .string(let text):
            return Double(text)
        default:
            return nil
        }
    }
}
#endif
