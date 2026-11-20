#if os(macOS)
import Foundation
import Metal
import YMM4Core

/// アイテム変形の Metal 実装。本家 DrawingEffect に対応する。
///
/// 本家は AffineTransform2D（ズーム）→ Crop → Transform3D（ワールド変換
/// ＋透視）→ ColorMatrix（不透明度）のエフェクト連鎖だが、こちらは中間
/// テクスチャを作らず、入力の実体へ「ズーム変換 × ワールド変換 × 透視」
/// の合成変換と不透明度を記録した実体を出力として登録する（遅延評価）。
/// 可視結果は、ズーム 0・不透明度 0 のとき入力を空に差し替える本家の
/// 分岐まで含めて一致させる（その場合の出力は 1×1 透明）。
/// 平面分割用の幾何情報（PlaneSplitGeometryProviding）も本家どおり、
/// ワールド変換そのものと、ズーム適用後の入力境界を返す。
/// 当たり判定用の四隅（BoundsQuadProviding）は本家 TransformBoundsQuad
/// に対応し、入力境界の四隅へ合成変換（透視を含む）を適用したものを
/// 返す（独自四隅ではないため providesCustomBoundsQuad は false）。
public final class MetalDrawingEffect: DrawingEffectProcessor, PlaneSplitGeometryProviding,
    BoundsQuadProviding
{
    private let context: MetalGraphicsContext
    private var inputImage: ImageReference?
    private let outputReference = ImageReference(label: "drawing-effect")

    private var hasUpdated = false
    private var isEmpty = false
    private var zoomTransform: Matrix4x4 = .identity
    private var worldTransform: Matrix4x4 = .identity

    /// 当たり判定用の四隅（boundsQuad）の材料: 直近の更新で解決した
    /// 入力の境界と、出力実体へ登録したのと同じ合成変換（入力自身の
    /// 変換 → ズーム → ワールド → 透視）。入力が引けない更新では nil。
    private var lastInputBounds: RectF?
    private var lastCombinedTransform: Matrix4x4 = .identity

    public init(context: MetalGraphicsContext) {
        self.context = context
    }

    // MARK: - DrawingEffectProcessor

    /// 現在の出力。初回 Update の前は nil（本家では生成直後から出力が
    /// 存在するが、消費者は Update 後にしか読まない）。
    public var output: ImageReference? {
        hasUpdated ? outputReference : nil
    }

    public func setInput(_ image: ImageReference?) {
        inputImage = image
    }

    public func clearInput() {
        inputImage = nil
    }

    @discardableResult
    public func update(_ description: EffectDescription) throws -> DrawDescription {
        let drawDescription = description.drawDescription

        // ズーム段: 反転（中心まわりの x 反転）→ ズーム拡縮。本家の
        // AffineTransform2D の行列合成（行ベクトル規約で左から適用）。
        let invertScale = Matrix4x4.createScale(
            x: drawDescription.invert ? -1 : 1, y: 1, z: 1,
            center: Vector3(
                x: drawDescription.centerPoint.x,
                y: drawDescription.centerPoint.y, z: 0
            )
        )
        let zoomScale = Matrix4x4.createScale(
            x: drawDescription.zoom.x, y: drawDescription.zoom.y, z: 1,
            center: .zero
        )
        zoomTransform = invertScale * zoomScale

        // ワールド段: 本家 CreateWorldMatrix（回転Z → 回転Y（符号反転）
        // → 回転X（符号反転）→ 平行移動 → カメラ）。
        worldTransform = Matrix4x4.createRotationZ(.pi * drawDescription.rotation.z / 180)
            * Matrix4x4.createRotationY(.pi * (0 - drawDescription.rotation.y) / 180)
            * Matrix4x4.createRotationX(.pi * (0 - drawDescription.rotation.x) / 180)
            * Matrix4x4.createTranslation(drawDescription.draw)
            * drawDescription.camera

        // 透視段: 本家 Transform3D が内部で掛ける M34 = -0.001。
        let perspective = Matrix4x4(
            m11: 1, m12: 0, m13: 0, m14: 0,
            m21: 0, m22: 1, m23: 0, m24: 0,
            m31: 0, m32: 0, m33: 1, m34: -0.001,
            m41: 0, m42: 0, m43: 0, m44: 1
        )

        isEmpty = drawDescription.zoom.x == 0
            || drawDescription.zoom.y == 0
            || drawDescription.opacity == 0
        hasUpdated = true

        // 当たり判定用の四隅の材料は、出力の登録内容（空判定）によらず
        // 入力が引ける時点で確定させる。本家 TransformBoundsQuad は
        // 不透明度や空判定を見ず、入力境界と確定変換だけで決まる。
        let input = inputImage.flatMap { context.devices.image(for: $0) }
        if let input {
            lastInputBounds = input.bounds
            // 入力自身の変換 → ズーム → ワールド → 透視、の順に合成する。
            lastCombinedTransform = input.transform * zoomTransform * worldTransform * perspective
        } else {
            lastInputBounds = nil
            lastCombinedTransform = .identity
        }

        if !isEmpty, let input {
            context.devices.register(
                outputReference,
                image: MetalImage(
                    texture: input.texture,
                    bounds: input.bounds,
                    texturePlaneRect: input.texturePlaneRect,
                    planeOffset: input.planeOffset,
                    transform: lastCombinedTransform,
                    opacity: drawDescription.opacity,
                    interpolation: drawDescription.zoomInterpolationMode
                )
            )
        } else {
            // 空の場合（および入力が無い場合）は 1×1 透明を出す。
            context.devices.register(
                outputReference,
                image: MetalImage(
                    texture: context.devices.transparentTexture,
                    bounds: RectF(left: 0, top: 0, right: 1, bottom: 1),
                    opacity: 0
                )
            )
        }
        // 本家 DrawingEffect.Update は説明の DrawDescription をそのまま返す。
        return drawDescription
    }

    public func dispose() {
        context.devices.unregister(outputReference)
        inputImage = nil
    }

    // MARK: - PlaneSplitGeometryProviding

    /// ワールド変換そのもの（本家 WorldTransform3D。ズーム・透視を含まない）。
    public var worldTransform3D: Matrix4x4 {
        worldTransform
    }

    /// 変換前（Transform3D の入力側）の境界。本家 GetTransform3DInputBounds
    /// と同じく、未更新・空のときは nil。入力境界へ入力自身の変換と
    /// ズーム変換を適用した外接矩形を返す（本家の Crop 出力境界に相当）。
    public func transform3DInputBounds() -> RectF? {
        guard hasUpdated, !isEmpty,
              let inputImage,
              let input = context.devices.image(for: inputImage)
        else { return nil }
        return Self.boundingRect(of: input.bounds, transformedBy: input.transform * zoomTransform)
    }

    // MARK: - BoundsQuadProviding

    /// 独自四隅ではない（本家では通常の DrawingEffect は
    /// IBoundsQuadProvider ではない）。
    public var providesCustomBoundsQuad: Bool { false }

    /// 入力境界の四隅へ合成変換を適用した四隅。本家
    /// TransformBoundsQuad の妥当性規則: 変換後の同次座標 w が 0 以下、
    /// または w 除算後の x / y が非有限なら nil。未更新・入力なしも nil。
    public func boundsQuad() -> [Vector2]? {
        guard hasUpdated, let bounds = lastInputBounds else { return nil }
        let corners = [
            Vector3(x: bounds.left, y: bounds.top, z: 0),
            Vector3(x: bounds.right, y: bounds.top, z: 0),
            Vector3(x: bounds.right, y: bounds.bottom, z: 0),
            Vector3(x: bounds.left, y: bounds.bottom, z: 0),
        ]
        var quad: [Vector2] = []
        quad.reserveCapacity(4)
        for corner in corners {
            let v = lastCombinedTransform.transform(
                x: corner.x, y: corner.y, z: corner.z, w: 1
            )
            guard v.w > 0 else { return nil }
            let x = v.x / v.w
            let y = v.y / v.w
            guard x.isFinite, y.isFinite else { return nil }
            quad.append(Vector2(x: x, y: y))
        }
        return quad
    }

    /// 矩形の四隅を変換（w 除算つき）した外接矩形。
    /// プレビューの当たり判定用データ（FE-R1-023-A）が登録済み画像の
    /// 実描画矩形を求めるためにも使うため公開する。
    public static func boundingRect(of rect: RectF, transformedBy matrix: Matrix4x4) -> RectF {
        let corners = [
            Vector3(x: rect.left, y: rect.top, z: 0),
            Vector3(x: rect.right, y: rect.top, z: 0),
            Vector3(x: rect.right, y: rect.bottom, z: 0),
            Vector3(x: rect.left, y: rect.bottom, z: 0),
        ]
        var result: RectF?
        for corner in corners {
            let point = matrix.transform(corner)
            let next = RectF(left: point.x, top: point.y, right: point.x, bottom: point.y)
            result = result?.union(next) ?? next
        }
        return result ?? rect
    }
}
#endif
