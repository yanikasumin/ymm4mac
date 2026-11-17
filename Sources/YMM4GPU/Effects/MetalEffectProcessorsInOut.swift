#if os(macOS)
import Foundation
import Metal
import YMM4Core

// MARK: - イン／アウト系

/// イン／アウト縁ぼかし。本家 `InOutBorderBlurEffect`。
/// BorderBlur プリミティブを σ = GetEasingValue(Value → 0) で使う。
/// この経路では σ の最小寸法クランプは無い（実コードで確認。
/// 通常の縁ぼかしとの違い）。
public final class MetalInOutBorderBlurProcessor: MetalEffectProcessor {
    private let definition: InOutBorderBlurEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutBorderBlurEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let sigma = inOutEasingValue(definition, description, from: definition.value, to: 0)
        let mask = try renderGaussianBlurred(input: input, sigma: sigma, hardBorder: false)
        return try renderWarp(
            input: input, mask: mask, outputBounds: input.bounds, mode: 0,
            param0: SIMD4<Float>(1, 0, 0, 0)
        )
    }
}

/// イン／アウトぼかし。本家 `InOutGaussianBlurEffect`（D2D 組み込み
/// GaussianBlur、σ = GetEasingValue(Value → 0)）。BorderMode は
/// 未設定のため Soft とする（本家の GaussianBlurEffect の既定
/// IsHardBorderMode = false と同じ扱い。記録）。
public final class MetalInOutGaussianBlurProcessor: MetalEffectProcessor {
    private let definition: InOutGaussianBlurEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutGaussianBlurEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let sigma = inOutEasingValue(definition, description, from: definition.value, to: 0)
        return try renderGaussianBlurred(input: input, sigma: sigma, hardBorder: false)
    }
}

/// イン／アウトモザイク。本家 `InOutMosaicEffect`。
/// セル寸法 = max(1, GetEasingValue(Value → 1))、形状はカスタム効果の
/// 既定（矩形）。第1段の矩形モザイク本体を共有する。
public final class MetalInOutMosaicProcessor: MetalEffectProcessor {
    private let definition: InOutMosaicEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutMosaicEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let size = max(1, inOutEasingValue(definition, description, from: definition.value, to: 1))
        return try renderRectangleMosaic(input: input, cellSize: size)
    }
}

/// イン／アウト画像外から移動。本家 `InOutMoveFromOutsideImageEffect`。
/// Flood（透明）へ平行移動した入力を重ね、元の境界で Crop する構成。
/// ずらし量は方向（左 = (−幅, 0) 等）を GetEasingValue(→ 0) で
/// 補間したもの。こちらでは元の境界を出力境界とする平行移動の
/// 焼き込みに畳む（結果は等しい）。
public final class MetalInOutMoveFromOutsideImageProcessor: MetalEffectProcessor {
    private let definition: InOutMoveFromOutsideImageEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutMoveFromOutsideImageEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let width = input.bounds.right - input.bounds.left
        let height = input.bounds.bottom - input.bounds.top
        let offset: (x: Double, y: Double)
        switch definition.value {
        case .left: offset = (-width, 0)
        case .right: offset = (width, 0)
        case .top: offset = (0, -height)
        case .bottom: offset = (0, height)
        case .unknown: offset = (-width, 0)
        }
        let appliedX = inOutEasingValue(definition, description, from: offset.x, to: 0)
        let appliedY = inOutEasingValue(definition, description, from: offset.y, to: 0)
        guard appliedX != 0 || appliedY != 0 else { return input }
        let matrix = Matrix4x4.createTranslation(x: appliedX, y: appliedY, z: 0)
        return try renderTransformed(
            input: input, matrix: matrix, outputBounds: input.bounds,
            interpolation: input.interpolation
        )
    }
}

/// イン／アウト回転。本家 `InOutRotateEffect`。Rotate と同じ構造で、
/// 角度は GetEasingValue(ValueX/Y/Z → 0)（double 値）。
public final class MetalInOutRotateProcessor: MetalEffectProcessor {
    private let definition: InOutRotateEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutRotateEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    private func angles(_ description: EffectDescription) -> (x: Double, y: Double, z: Double) {
        (
            x: inOutEasingValue(definition, description, from: definition.valueX, to: 0),
            y: inOutEasingValue(definition, description, from: definition.valueY, to: 0),
            z: inOutEasingValue(definition, description, from: definition.valueZ, to: 0)
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

/// イン／アウト傾斜。本家 `InOutSkewEffect`。Skew と同じ構造で、
/// 角度・中心は GetEasingValue(→ 0) の double 値。
public final class MetalInOutSkewProcessor: MetalEffectProcessor {
    private let definition: InOutSkewEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutSkewEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let center = skewCenter(
            mode: definition.centerPoint,
            centerX: definition.centerX, centerY: definition.centerY,
            bounds: input.bounds
        )
        return try bakeSkew(
            input: input, description: description,
            angleX: inOutEasingValue(definition, description, from: definition.angleX, to: 0),
            angleY: inOutEasingValue(definition, description, from: definition.angleY, to: 0),
            center: center
        )
    }
}

/// イン／アウト起き上がり。本家 `InOutGetUpEffect`（実コードで検証）。
/// 角度 = GetEasingValue(90 → 0)。基線点 v は入力のワールド境界
/// （こちらではプレーンな入力の境界と同一視する。解釈として記録）
/// から Base で決まり、3D の場合は境界を Zoom で拡縮してから求める。
/// 回転ベクトル r は Base で決まり、Direction = Front で符号反転する。
/// 画像行列は両分岐とも Scale(Zoom) が先頭に付く:
/// - 3D: Scale(Zoom) · 平行移動(−v)。戻りは Draw += v、Rotation −= r、
///   Zoom = (1,1)。
/// - 非3D: Scale(Zoom) · [平行移動(−v・Zoom) · Rz(r.z) · Ry(r.y) ·
///   Rx(r.x) · 透視 · 平行移動(+v・Zoom)]。戻りは Zoom = (1,1) のみ。
/// 本家の回転は Rotate と違い Y / X とも符号反転しない（実コード）。
/// チェーン中間の Crop（SafeTransform3DHelper）は1パスの焼き込みに
/// 畳む（内部実装の違い）。
public final class MetalInOutGetUpProcessor: MetalEffectProcessor {
    private let definition: InOutGetUpEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutGetUpEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    /// 基線点と回転ベクトル（本家 Update の switch の写し）。
    private func baseline(
        _ description: EffectDescription, bounds: RectF
    ) -> (point: Vector2, rotation: Vector3) {
        let angle = inOutEasingValue(definition, description, from: 90, to: 0)
        let centerX = (bounds.left + bounds.right) / 2
        let centerY = (bounds.top + bounds.bottom) / 2
        let point: Vector2
        let rotation: Vector3
        switch definition.base {
        case .top:
            point = Vector2(x: 0, y: bounds.top)
            rotation = Vector3(x: -angle, y: 0, z: 0)
        case .bottom, .unknown:
            point = Vector2(x: 0, y: bounds.bottom)
            rotation = Vector3(x: angle, y: 0, z: 0)
        case .left:
            point = Vector2(x: bounds.left, y: 0)
            rotation = Vector3(x: 0, y: angle, z: 0)
        case .right:
            point = Vector2(x: bounds.right, y: 0)
            rotation = Vector3(x: 0, y: -angle, z: 0)
        case .centerX:
            point = .zero
            rotation = Vector3(x: angle, y: 0, z: 0)
        case .centerY:
            point = .zero
            rotation = Vector3(x: 0, y: angle, z: 0)
        case .trueCenterX:
            point = Vector2(x: centerX, y: centerY)
            rotation = Vector3(x: angle, y: 0, z: 0)
        case .trueCenterY:
            point = Vector2(x: centerX, y: centerY)
            rotation = Vector3(x: 0, y: angle, z: 0)
        }
        if definition.direction == .front {
            return (point, Vector3(x: -rotation.x, y: -rotation.y, z: -rotation.z))
        }
        return (point, rotation)
    }

    /// 3D 分岐では境界を Zoom で拡縮してから基線を求める（本家どおり）。
    private func effectiveBounds(
        _ description: EffectDescription, input: MetalImage
    ) -> RectF {
        guard definition.is3D else { return input.bounds }
        let zoom = description.drawDescription.zoom
        return RectF(
            left: input.bounds.left * zoom.x, top: input.bounds.top * zoom.y,
            right: input.bounds.right * zoom.x, bottom: input.bounds.bottom * zoom.y
        )
    }

    override func render(input: MetalImage, description: EffectDescription) throws -> MetalImage? {
        let zoom = description.drawDescription.zoom
        let bounds = effectiveBounds(description, input: input)
        let (point, rotation) = baseline(description, bounds: bounds)
        let scale = Matrix4x4.createScale(x: zoom.x, y: zoom.y, z: 1, center: .zero)
        let matrix: Matrix4x4
        if definition.is3D {
            matrix = scale * Matrix4x4.createTranslation(
                x: -point.x, y: -point.y, z: 0
            )
        } else {
            let inner = Matrix4x4.createTranslation(x: -point.x * zoom.x, y: -point.y * zoom.y, z: 0)
                * Matrix4x4.createRotationZ(rotation.z * Double.pi / 180)
                * Matrix4x4.createRotationY(rotation.y * Double.pi / 180)
                * Matrix4x4.createRotationX(rotation.x * Double.pi / 180)
                * perspectiveMatrix
                * Matrix4x4.createTranslation(x: point.x * zoom.x, y: point.y * zoom.y, z: 0)
            matrix = scale * inner
        }
        guard !isIdentity(matrix) else { return input }
        let outputBounds = MetalDrawingEffect.boundingRect(of: input.bounds, transformedBy: matrix)
        return try renderTransformed(
            input: input, matrix: matrix, outputBounds: outputBounds,
            interpolation: description.drawDescription.zoomInterpolationMode
        )
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        var result = description.drawDescription
        result.zoom = Vector2(x: 1, y: 1)
        guard definition.is3D, let input else { return result }
        let bounds = effectiveBounds(description, input: input)
        let (point, rotation) = baseline(description, bounds: bounds)
        result.draw = Vector3(
            x: result.draw.x + point.x, y: result.draw.y + point.y, z: result.draw.z
        )
        result.rotation = Vector3(
            x: result.rotation.x - rotation.x,
            y: result.rotation.y - rotation.y,
            z: result.rotation.z - rotation.z
        )
        return result
    }
}

/// イン／アウトジャンプ。本家 `InOutJumpEffect`（DrawDescription のみの
/// 変更。実コードで検証）。イン／アウトの進行率から逆算した時刻を
/// 専用の Jump 変形（インターバル位相が先行する形）へ渡す。
public final class MetalInOutJumpProcessor: MetalEffectProcessor {
    private let definition: InOutJumpEffectDefinition

    public init(context: MetalGraphicsContext, definition: InOutJumpEffectDefinition) {
        self.definition = definition
        super.init(context: context)
    }

    override func modifiedDrawDescription(
        _ description: EffectDescription, input: MetalImage?
    ) -> DrawDescription {
        let dd = description.drawDescription
        let durationSeconds = description.itemDescription.itemDuration.time
        let positionSeconds = description.itemDescription.itemPosition.time
        let effectTime = definition.effectTimeSeconds
        let inRate = (definition.isInEffect && effectTime > 0)
            ? min(max(positionSeconds / effectTime, 0), 1)
            : 1
        let outRate = (definition.isOutEffect && effectTime > 0)
            ? min(max((durationSeconds - positionSeconds) / effectTime, 0), 1)
            : 1
        let num3 = 1 - min(inRate, outRate)
        let height = input.map { $0.bounds.bottom - $0.bounds.top } ?? 0
        let zoomY = dd.zoom.y
        var isReversed = false
        if positionSeconds < effectTime && inRate < outRate {
            isReversed = definition.isInReverse
        } else if durationSeconds - effectTime < positionSeconds && outRate < inRate {
            isReversed = definition.isOutReverse
        }
        return Self.jump(
            dd,
            height: height,
            jumpHeight: zoomY <= 0 ? 0 : definition.jumpHeight / zoomY,
            stretch: height * definition.stretch / 100,
            period: definition.period,
            distortion: height / 2 * definition.distortion / 100,
            interval: definition.interval,
            toX: definition.x,
            toY: definition.y,
            isReversed: isReversed,
            time: effectTime * num3,
            totalTime: effectTime
        )
    }

    /// 本家 InOutJumpEffect.Jump の式（実コードの写し。通常の Jump と
    /// 位相の組み立てが異なる: num4 = clamp(num3 − interval, 0, period)、
    /// num8 はインターバル内では歪み、それ以外では跳躍）。
    static func jump(
        _ dd: DrawDescription,
        height: Double,
        jumpHeight: Double,
        stretch: Double,
        period: Double,
        distortion: Double,
        interval: Double,
        toX: Double,
        toY: Double,
        isReversed: Bool,
        time: Double,
        totalTime: Double
    ) -> DrawDescription {
        let zoomY = dd.zoom.y
        let num = (period + interval == 0) ? 0 : totalTime / (period + interval)
        let num2 = (period + interval != 0) ? Int(time / (period + interval)) : 0
        let num3 = time - (period + interval) * Double(num2)
        let num4 = min(max(num3 - interval, 0), period)
        let num5 = (period == 0) ? 0 : num4 / period
        let num7 = (interval == 0) ? 0 : num3 / interval
        let num8 = (num3 < interval)
            ? -distortion * sin(num7 * Double.pi)
            : jumpHeight * sin(num5 * Double.pi)
        let num9 = (height == 0) ? 1 : (height + min(num8 * 2, stretch)) / height
        let num10 = (num9 == 0) ? 1 : 1 / num9
        let num11 = (num == 0) ? 0 : toX / num
        let num12 = (num == 0) ? 0 : toY / num
        let num13 = num11 * (Double(num2) + num5)
        let num14 = num12 * (Double(num2) + num5)
        var result = dd
        result.draw = Vector3(
            x: dd.draw.x + num13,
            y: dd.draw.y + num14 - num8 * zoomY,
            z: dd.draw.z
        )
        result.zoom = Vector2(
            x: dd.zoom.x * num10 * (isReversed ? -1 : 1),
            y: dd.zoom.y * num9
        )
        return result
    }
}

#endif
