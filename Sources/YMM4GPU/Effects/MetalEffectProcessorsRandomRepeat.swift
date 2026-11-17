#if os(macOS)
import Foundation
import Metal
import YMM4Core

// MARK: - ランダム／反復系

/// ランダム回転。本家 `RandomRotateEffect`。
/// 角度 = パラメータ値 × 乱数率 − パラメータ値 / 2（パラメータ ID は
/// X = 0, Y = 1, Z = 2）。以降は Rotate と同じ構造。
public final class MetalRandomRotateProcessor: MetalEffectProcessor {
    private let definition: RandomRotateEffectDefinition

    public init(context: MetalGraphicsContext, definition: RandomRotateEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    private func angles(_ description: EffectDescription) -> (x: Double, y: Double, z: Double) {
        func angle(_ animation: Animation, id: Int64) -> Double {
            let value = evaluate(animation, description)
            return value * randomRate(definition, description, parameterID: id) - value / 2
        }
        return (
            x: angle(definition.x, id: 0),
            y: angle(definition.y, id: 1),
            z: angle(definition.z, id: 2)
        )
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let angle = angles(description)
        return try bakeRotation(
            input: input, description: description,
            angleX: angle.x, angleY: angle.y, angleZ: angle.z,
            is3D: definition.is3D
        )
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        let angle = angles(description)
        return rotationDrawDescription(
            description, angleX: angle.x, angleY: angle.y, angleZ: angle.z,
            is3D: definition.is3D
        )
    }
}

/// ランダム傾斜。本家 `RandomSkewEffect`。
/// 角度 = パラメータ値 × 乱数率 − パラメータ値 / 2（ID は X = 0,
/// Y = 1）。中心は Skew と同じ。
public final class MetalRandomSkewProcessor: MetalEffectProcessor {
    private let definition: RandomSkewEffectDefinition

    public init(context: MetalGraphicsContext, definition: RandomSkewEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let valueX = evaluate(definition.angleX, description)
        let valueY = evaluate(definition.angleY, description)
        let center = skewCenter(
            mode: definition.centerPoint,
            centerX: evaluate(definition.centerX, description),
            centerY: evaluate(definition.centerY, description),
            bounds: input.bounds
        )
        return try bakeSkew(
            input: input, description: description,
            angleX: valueX * randomRate(definition, description, parameterID: 0) - valueX / 2,
            angleY: valueY * randomRate(definition, description, parameterID: 1) - valueY / 2,
            center: center
        )
    }
}

/// 反復回転。本家 `RepeatRotateEffect`。
/// 角度 = 反復イージング値 (0 → パラメータ値)。以降は Rotate と同じ。
public final class MetalRepeatRotateProcessor: MetalEffectProcessor {
    private let definition: RepeatRotateEffectDefinition

    public init(context: MetalGraphicsContext, definition: RepeatRotateEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    private func angles(_ description: EffectDescription) -> (x: Double, y: Double, z: Double) {
        (
            x: repeatEasingValue(definition, description, from: 0, to: evaluate(definition.x, description)),
            y: repeatEasingValue(definition, description, from: 0, to: evaluate(definition.y, description)),
            z: repeatEasingValue(definition, description, from: 0, to: evaluate(definition.z, description))
        )
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let angle = angles(description)
        return try bakeRotation(
            input: input, description: description,
            angleX: angle.x, angleY: angle.y, angleZ: angle.z,
            is3D: definition.is3D
        )
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        let angle = angles(description)
        return rotationDrawDescription(
            description, angleX: angle.x, angleY: angle.y, angleZ: angle.z,
            is3D: definition.is3D
        )
    }
}

/// 反復傾斜。本家 `RepeatSkewEffect`。
/// 角度 = 反復イージング値 (0 → パラメータ値)。中心は Skew と同じ。
public final class MetalRepeatSkewProcessor: MetalEffectProcessor {
    private let definition: RepeatSkewEffectDefinition

    public init(context: MetalGraphicsContext, definition: RepeatSkewEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let center = skewCenter(
            mode: definition.centerPoint,
            centerX: evaluate(definition.centerX, description),
            centerY: evaluate(definition.centerY, description),
            bounds: input.bounds
        )
        return try bakeSkew(
            input: input, description: description,
            angleX: repeatEasingValue(
                definition, description, from: 0, to: evaluate(definition.angleX, description)
            ),
            angleY: repeatEasingValue(
                definition, description, from: 0, to: evaluate(definition.angleY, description)
            ),
            center: center
        )
    }
}
#endif
