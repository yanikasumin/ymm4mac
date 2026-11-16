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
public final class MetalDrawingEffect: DrawingEffectProcessor, PlaneSplitGeometryProviding {
    private let context: MetalGraphicsContext
    private var inputImage: ImageReference?
    private let outputReference = ImageReference(label: "drawing-effect")

    private var hasUpdated = false
    private var isEmpty = false
    private var zoomTransform: Matrix4x4 = .identity
    private var worldTransform: Matrix4x4 = .identity

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

        if !isEmpty,
           let inputImage,
           let input = context.devices.image(for: inputImage) {
            // 入力自身の変換 → ズーム → ワールド → 透視、の順に合成する。
            let combined = input.transform * zoomTransform * worldTransform * perspective
            context.devices.register(
                outputReference,
                image: MetalImage(
                    texture: input.texture,
                    bounds: input.bounds,
                    transform: combined,
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

    /// 矩形の四隅を変換（w 除算つき）した外接矩形。
    static func boundingRect(of rect: RectF, transformedBy matrix: Matrix4x4) -> RectF {
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
