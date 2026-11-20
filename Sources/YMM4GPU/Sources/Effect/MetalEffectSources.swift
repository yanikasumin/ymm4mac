#if os(macOS)
import Foundation
import Metal
import YMM4Core

/// エフェクトアイテムの Source。本家 EffectSource に対応する
/// （MAC-0035、監査 AUD-01）。
///
/// 本家 EffectSource は FrameBufferSource のサブクラスだが、基底
/// コンストラクタへ FrameBufferItem として **null** を渡す特殊性がある
/// （B-1）。その帰結は3点で、いずれも基底クラスのフック既定値そのまま:
/// - ClearBackground = false（合成側は前回の蓄積を引き継ぐ）
/// - 背景 Flood は不透明な黒（IsAlphaEnabled の分岐に入らない）
/// - 切り抜き境界は画面サイズちょうど（フレーム外拡張をしない）
/// 蓄積画像の実体化（Flood → SourceOver → Crop）は基底
/// MetalFrameBufferSourceBase が担い、こちらは DrawingEffect を
/// マスク適用型（MetalEffectItemDrawingEffect）へ差し替えるだけである。
public final class MetalEffectSource: MetalFrameBufferSourceBase {
    public init(devices: MetalGraphicsDevices, item: EffectItem) {
        let context = devices.makeContext()
        super.init(
            context: context,
            drawingEffect: MetalEffectItemDrawingEffect(context: context, item: item)
        )
    }
}

/// エフェクトアイテムの描画エフェクト。本家 EffectItemDrawingEffect
/// （＋ Primitive.Mask）に対応する（MAC-0035）。
///
/// 役割は「蓄積画像へ図形パラメータの形状マスクを適用する」ことで、
/// 通常の映像エフェクト列はアイテム側の連鎖（EffectedItemSource）が
/// この前段で適用する。本家の構成は:
/// 1. 図形パラメータから図形画像を生成する（CreateShapeSource）。
///    こちらでは MetalShapeSource と同じ SDF ラスタライズを共有する。
/// 2. 図形画像へ DrawDescription の変換（回転・位置・カメラ・透視）を
///    適用して平面上へ実体化する（Mask の Transform3D 段）。
/// 3. マスクを GaussianBlur（item.Blur）でぼかし、反転（InvertMask）と
///    不透明度を ColorMatrix で適用する。不透明度は
///    DrawDescription.Opacity × フェード係数（item.FadeIn / FadeOut を
///    アイテム内位置・長さから本家式で再計算する。本家の初期
///    DrawDescription にも同じ係数が入るため、本家では二重に効く。
///    実コードどおり再現する）。
/// 4. AlphaMask で入力（蓄積画像）へマスクのアルファを乗算する。
///    2〜4 は warp パスの mode 6（調整つきアルファマスク）へ畳むが、
///    ぼかしだけは本家どおりマスク側へ先に適用する。
/// 戻す DrawDescription は入力のまま（本家は CameraFinalizer 適用後の
/// 説明を返す。こちらでは EffectedOutput が先に cameraFinalizer を
/// 通すため、ここでは無変更で一致する）。不透明度はマスク側へ
/// 焼き込むため、登録する実体の opacity は 1 とする。
///
/// 平面分割用の幾何（PlaneSplitGeometryProviding）は本家
/// IBoundsQuadProvider に対応し、ワールド変換（透視を含まない）と
/// マスク図形の境界を返す。
/// 当たり判定用の四隅（BoundsQuadProviding）も本家 IBoundsQuadProvider
/// に対応する独自四隅であり、マスク図形の境界へマスク変換（透視を
/// 含む）を適用したものを返す（providesCustomBoundsQuad は true）。
///
/// 未対応: 型付きでない図形パラメータ（生保持）はラスタライズできず、
/// マスクは全面透明になる（本家では図形プラグインが描く。Mac には
/// 図形プラグインが無いための制限。台帳に記録）。
public final class MetalEffectItemDrawingEffect: DrawingEffectProcessor,
    PlaneSplitGeometryProviding, BoundsQuadProviding
{
    private let context: MetalGraphicsContext
    private let item: EffectItem
    /// 描画ヘルパ（Metal 処理器の基底が持つ実体化パスを再利用する。
    /// 連鎖へは参加せず、renderTransformed / renderGaussianBlurred /
    /// renderWarp だけを使う）。
    private let renderHelper: MetalEffectProcessor
    private var inputReference: ImageReference?
    private let outputReference = ImageReference(label: "effect-item-drawing")
    private var hasUpdated = false

    /// ラスタライズ済み図形のキャッシュ（図形 Source と同じキー）。
    private var cachedShapeKey: MetalShapeSource.RenderKey?
    private var cachedShapeTexture: MTLTexture?

    /// 平面分割用: 直近の更新で使ったワールド変換（透視なし）と、
    /// 変換前のマスク図形の境界。未更新・図形なしでは nil。
    private var lastWorldTransform: Matrix4x4 = .identity
    private var lastShapeBounds: RectF?
    /// 当たり判定用の四隅用: 直近の更新で使ったマスク変換（透視を
    /// 含む）。本家 Mask.GetBoundsQuad が CreateTransformMatrix
    /// （透視を含む）を使うことに対応する。
    private var lastMaskTransform: Matrix4x4 = .identity

    public init(context: MetalGraphicsContext, item: EffectItem) {
        self.context = context
        self.item = item
        self.renderHelper = MetalEffectProcessor(context: context)
    }

    // MARK: - DrawingEffectProcessor

    public var output: ImageReference? {
        hasUpdated ? outputReference : nil
    }

    public func setInput(_ image: ImageReference?) {
        inputReference = image
    }

    public func clearInput() {
        inputReference = nil
    }

    @discardableResult
    public func update(_ description: EffectDescription) throws -> DrawDescription {
        let drawDescription = description.drawDescription
        hasUpdated = true
        lastShapeBounds = nil
        guard let inputReference,
              let input = context.devices.image(for: inputReference)
        else {
            // 入力が無い場合は 1×1 透明を出す（本家の空出力に相当）。
            register(MetalImage(
                texture: context.devices.transparentTexture,
                bounds: RectF(left: 0, top: 0, right: 1, bottom: 1)
            ))
            return drawDescription
        }

        let (frame, length, fps) = renderHelper.evaluationContext(description)

        // フェード係数とマスク不透明度（本家 EffectItemDrawingEffect の
        // 式どおり。下限クランプは本家にも無い）。
        let positionSeconds = description.itemDescription.itemPosition.time
        let durationSeconds = description.itemDescription.itemDuration.time
        let fadeInFactor = item.fadeIn == 0
            ? 1 : min(1, positionSeconds / item.fadeIn)
        let fadeOutFactor = item.fadeOut == 0
            ? 1 : min(1, (durationSeconds - positionSeconds) / item.fadeOut)
        let maskOpacity = drawDescription.opacity * min(fadeInFactor, fadeOutFactor)

        // マスク変換（本家 Mask.CreateTransformMatrix: 回転Z → 回転Y
        // （符号反転）→ 回転X（符号反転）→ 平行移動 → カメラ → 透視）。
        let worldTransform = Matrix4x4.createRotationZ(.pi * drawDescription.rotation.z / 180)
            * Matrix4x4.createRotationY(.pi * (0 - drawDescription.rotation.y) / 180)
            * Matrix4x4.createRotationX(.pi * (0 - drawDescription.rotation.x) / 180)
            * Matrix4x4.createTranslation(drawDescription.draw)
            * drawDescription.camera
        lastWorldTransform = worldTransform
        let perspective = Matrix4x4(
            m11: 1, m12: 0, m13: 0, m14: 0,
            m21: 0, m22: 1, m23: 0, m24: 0,
            m31: 0, m32: 0, m33: 1, m34: -0.001,
            m41: 0, m42: 0, m43: 0, m44: 1
        )
        let maskTransform = worldTransform * perspective
        lastMaskTransform = maskTransform

        // 図形画像（中心原点の境界つき）。型付きでないパラメータは
        // ラスタライズできないため、マスク全面透明として扱う。
        guard let shapeImage = shapeImage(frame: frame, length: length, fps: fps) else {
            register(MetalImage(
                texture: context.devices.transparentTexture,
                bounds: input.bounds,
                texturePlaneRect: input.bounds
            ))
            return drawDescription
        }
        lastShapeBounds = shapeImage.bounds

        // マスクの切り抜き境界（本家 Mask.Update）: 反転時は入力の境界
        // （反転マスクは入力全体を覆う）、通常時は変換後の図形の境界。
        let transformedBounds = MetalDrawingEffect.boundingRect(
            of: shapeImage.bounds, transformedBy: maskTransform
        )
        let maskBounds = item.invertMask ? input.bounds : transformedBounds

        // 図形を変換して平面上へ実体化し、マスク側だけをぼかす
        // （本家の Composite → Crop → GaussianBlur の畳み込み）。
        var mask = try renderHelper.renderTransformed(
            input: shapeImage,
            matrix: maskTransform,
            outputBounds: maskBounds,
            interpolation: .linear
        )
        let blur = item.blur.value(atFrame: frame, length: length, fps: fps)
        if blur > 0 {
            mask = try renderHelper.renderGaussianBlurred(
                input: mask, sigma: blur, hardBorder: false
            )
        }

        // 反転と不透明度を適用したマスクで入力を切り抜く（warp mode 6）。
        let result = try renderHelper.renderWarp(
            input: input,
            mask: mask,
            outputBounds: input.bounds,
            mode: 6,
            param0: SIMD4<Float>(
                item.invertMask ? 1 : 0, Float(maskOpacity), 0, 0
            )
        )
        register(result)
        return drawDescription
    }

    public func dispose() {
        renderHelper.dispose()
        context.devices.unregister(outputReference)
        inputReference = nil
        cachedShapeTexture = nil
        cachedShapeKey = nil
    }

    // MARK: - PlaneSplitGeometryProviding

    /// ワールド変換そのもの（本家 Mask の GetBoundsQuad が使う行列の
    /// うち透視を除いた部分。MetalDrawingEffect と同じ規約）。
    public var worldTransform3D: Matrix4x4 {
        lastWorldTransform
    }

    /// 変換前の入力境界 = マスク図形の境界（本家 GetBoundsQuad が
    /// マスク画像の局所境界を使うことに対応）。未更新・図形なしでは nil。
    public func transform3DInputBounds() -> RectF? {
        hasUpdated ? lastShapeBounds : nil
    }

    // MARK: - BoundsQuadProviding

    /// 独自四隅を持つ（本家 IBoundsQuadProvider への適合に相当）。
    public var providesCustomBoundsQuad: Bool { true }

    /// マスク図形の境界へマスク変換（透視を含む）を適用した四隅。
    /// 本家 Mask.GetBoundsQuad の妥当性規則: 図形の境界が非有限・
    /// 絶対値 2.1474836e9 以上・空なら nil。変換後の同次座標 w が
    /// 0.001 以下または非有限、w 除算後の座標が非有限なら nil。
    /// 四隅の符号つき面積（shoelace 和）が非有限または絶対値 1e-6
    /// 未満（潰れた四角形）でも nil。未更新・図形なしも nil。
    public func boundsQuad() -> [Vector2]? {
        guard hasUpdated, let bounds = lastShapeBounds else { return nil }
        let limit = 2.1474836e9
        guard bounds.left.isFinite, bounds.top.isFinite,
              bounds.right.isFinite, bounds.bottom.isFinite,
              abs(bounds.left) < limit, abs(bounds.top) < limit,
              abs(bounds.right) < limit, abs(bounds.bottom) < limit,
              bounds.right > bounds.left, bounds.bottom > bounds.top
        else { return nil }
        let corners = [
            Vector3(x: bounds.left, y: bounds.top, z: 0),
            Vector3(x: bounds.right, y: bounds.top, z: 0),
            Vector3(x: bounds.right, y: bounds.bottom, z: 0),
            Vector3(x: bounds.left, y: bounds.bottom, z: 0),
        ]
        var quad: [Vector2] = []
        quad.reserveCapacity(4)
        for corner in corners {
            let v = lastMaskTransform.transform(
                x: corner.x, y: corner.y, z: corner.z, w: 1
            )
            guard v.w > 0.001, v.w.isFinite else { return nil }
            let x = v.x / v.w
            let y = v.y / v.w
            guard x.isFinite, y.isFinite else { return nil }
            quad.append(Vector2(x: x, y: y))
        }
        var signedArea = 0.0
        for i in quad.indices {
            let a = quad[i]
            let b = quad[(i + 1) % quad.count]
            signedArea += a.x * b.y - a.y * b.x
        }
        guard signedArea.isFinite, abs(signedArea) >= 1e-6 else { return nil }
        return quad
    }

    // MARK: - 内部

    private func register(_ image: MetalImage) {
        context.devices.register(outputReference, image: image)
    }

    /// 図形パラメータを評価して図形画像（テクスチャ＋中心原点の境界）を
    /// 得る。評価キーが変わらない間はラスタライズ結果を使い回す
    /// （MetalShapeSource と同じ方針）。
    private func shapeImage(frame: Int, length: Int, fps: Int) -> MetalImage? {
        guard case .rectangle(let parameter) = item.shapeParameter else {
            return nil
        }
        let size = MetalShapeSource.evaluateSize(
            parameter: parameter, frame: frame, length: length, fps: fps
        )
        let key = MetalShapeSource.RenderKey(
            width: size.width, height: size.height,
            round: parameter.round.value(atFrame: frame, length: length, fps: fps),
            strokeThickness: parameter.strokeThickness.value(
                atFrame: frame, length: length, fps: fps
            ),
            fill: MetalShapeSource.fill(
                for: parameter, width: size.width, height: size.height,
                frame: frame, length: length, fps: fps
            )
        )
        if cachedShapeKey != key {
            cachedShapeKey = key
            cachedShapeTexture = MetalShapeSource.rasterize(context: context, key: key)
        }
        guard let texture = cachedShapeTexture else { return nil }
        return MetalImage(
            texture: texture,
            bounds: RectF(
                left: -size.width / 2, top: -size.height / 2,
                right: size.width / 2, bottom: size.height / 2
            )
        )
    }
}
#endif
