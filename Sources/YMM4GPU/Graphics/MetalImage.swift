#if os(macOS)
import CoreGraphics
import Foundation
import Metal
import YMM4Core

/// Metal 側の画像実体。MAC-0009 の `ImageReference`（不透明なトークン）に
/// 対する実体の組であり、デバイス単位の登録表でトークンと結び付ける。
///
/// 本家 ID2D1Image は「無限平面上の画像」であり、内容は平面座標の境界
/// （bounds）を持ち、描画時に変換（transform）が適用される。こちらも
/// 同じ3点（テクスチャ・境界・変換）を保持し、DrawingEffect 相当の変換は
/// 中間テクスチャを作らず変換の記録として合成する（遅延評価）。
/// 座標系は本家どおり、原点 = 画面中心・x 右・y 下・単位ピクセル。
///
/// 境界とテクスチャの平面範囲は分けて持つ。本家の画像は無限平面上の
/// 存在であり、局所境界（GetImageLocalBounds）は内容のある範囲を指し、
/// テクスチャの広がりとは一致しない（コマンドリストの内容境界など）。
/// こちらでも、描画先（コマンドリスト相当）の内容境界はテクスチャが
/// 張る平面範囲（texturePlaneRect）より小さくなりうる。描画時の UV は
/// texturePlaneRect から求める。通常の画像（素材・生成テクスチャ）では
/// 両者は一致する。
public struct MetalImage {
    /// ピクセルの実体。属性は本家どおり BGRA 8bit / Premultiplied を基本とする
    /// （IMG-06: 合成コアに色管理は無い）。
    public var texture: MTLTexture
    /// transform 適用前の、平面座標における内容の境界。
    public var bounds: RectF
    /// テクスチャが張る平面範囲（UV (0,0) が左上、(1,1) が右下に対応）。
    /// 既定は bounds と同じ。
    public var texturePlaneRect: RectF
    /// ローカル座標（bounds の座標系）からテクスチャ平面座標へのずれ。
    /// 通常は (0, 0) で両者は一致する。合成グループの出力のように、
    /// 内容を平行移動してから1つの画像として扱う場合にだけ非ゼロになる
    /// （ローカル点 + planeOffset が、その画素がテクスチャ平面上で
    /// 置かれている位置）。
    public var planeOffset: Vector2
    /// 描画時に境界へ適用する変換（透視の M34 = -0.001 を含む 4×4）。
    public var transform: Matrix4x4
    /// 不透明度（0.0〜1.0）。Premultiplied の全成分へ乗算する（本家の
    /// ColorMatrix によるアルファ拡縮と等価）。
    public var opacity: Double
    /// 拡大縮小の補間方式。
    public var interpolation: InterpolationMode

    public init(
        texture: MTLTexture,
        bounds: RectF,
        texturePlaneRect: RectF? = nil,
        planeOffset: Vector2 = .zero,
        transform: Matrix4x4 = .identity,
        opacity: Double = 1,
        interpolation: InterpolationMode = .linear
    ) {
        self.texture = texture
        self.bounds = bounds
        self.texturePlaneRect = texturePlaneRect ?? bounds
        self.planeOffset = planeOffset
        self.transform = transform
        self.opacity = opacity
        self.interpolation = interpolation
    }

    /// ローカル座標の点をテクスチャ UV へ写す（planeOffset を加えてから
    /// texturePlaneRect 基準で写す）。
    public func uv(forLocalX x: Double, y: Double) -> SIMD2<Float> {
        uv(forPlaneX: x + planeOffset.x, y: y + planeOffset.y)
    }

    /// 平面座標の点をテクスチャ UV へ写す（texturePlaneRect 基準）。
    public func uv(forPlaneX x: Double, y: Double) -> SIMD2<Float> {
        let width = texturePlaneRect.right - texturePlaneRect.left
        let height = texturePlaneRect.bottom - texturePlaneRect.top
        guard width != 0, height != 0 else { return SIMD2(0, 0) }
        return SIMD2(
            Float((x - texturePlaneRect.left) / width),
            Float((y - texturePlaneRect.top) / height)
        )
    }
}

#endif
