import Foundation

/// 拡大縮小時の補間方式。本家 Vortice.Direct2D1 の InterpolationMode
/// （D2D1_INTERPOLATION_MODE の定義順）に対応する。実際の補間は GPU 実行層が
/// この値を解釈する。
public enum InterpolationMode: Sendable {
    case nearestNeighbor
    case linear
    case cubic
    case multiSampleLinear
    case anisotropic
    case highQualityCubic
}

/// ビルボードの方式。本家 BillboardMode に対応する。
public enum BillboardMode: Sendable {
    case none
    case spherical
    case cylindrical
}

/// 操作点どうしの接続種別。本家 VideoControllerPointConnection に対応する。
public enum VideoControllerPointConnection: Sendable {
    case none
    case line
    case loop
}

/// 操作点の形状。本家 VideoControllerPointShape に対応する。
public enum VideoControllerPointShape: Sendable {
    case none
    case circle
    case smallCircle
    case point
    case pointSquare
    case pointTriangle
    case pointPlus
    case pointCross
    case triangle
    case square
}

/// エディタ操作点（モーショントラッキング等のアンカー）。本家 ControllerPoint
/// に対応する。ドラッグ等の対話コールバックは編集 UI 層の関心であり、
/// 合成契約の範囲外としてここには含めない。
public struct ControllerPoint: Equatable, Sendable {
    /// アイテム座標系での位置。
    public var position: Vector3
    public var shape: VideoControllerPointShape
    public var isSelected: Bool

    public init(
        position: Vector3,
        shape: VideoControllerPointShape = .circle,
        isSelected: Bool = false
    ) {
        self.position = position
        self.shape = shape
        self.isSelected = isSelected
    }
}

/// 操作点の列。本家 VideoController に対応する。
public class VideoController {
    public var points: [ControllerPoint]
    public var connection: VideoControllerPointConnection

    public init(points: [ControllerPoint], connection: VideoControllerPointConnection = .none) {
        self.points = points
        self.connection = connection
    }
}

/// エフェクトに属する操作点の列。本家 VideoEffectController に対応する。
/// Owner はエフェクト定義への不透明な参照（実体はプラグイン／保持オブジェ
/// クト側にあり、この層では同一性だけを保持する）。
public final class VideoEffectController: VideoController {
    public let owner: AnyObject

    public init(
        owner: AnyObject,
        points: [ControllerPoint],
        connection: VideoControllerPointConnection = .none
    ) {
        self.owner = owner
        super.init(points: points, connection: connection)
    }
}

/// 1つの出力に対する描画変換。本家 DrawDescription（レコード）に対応する
/// 値型。DrawingEffect の Update が評価時点の値を確定し、合成側はこの値で
/// 描画順序（Z）と変換を決める（技術仕様 第4章・第5章）。
///
/// 本家の CustomValues（型と名前をキーにした異種辞書）は、Swift の値型では
/// 等価な表現がないため本段階では含めない（台帳に記録）。
public struct DrawDescription {
    /// 描画位置（X / Y / Z）。
    public var draw: Vector3
    /// 回転・拡縮の中心。
    public var centerPoint: Vector2
    /// 拡縮率（X / Y、1 = 等倍）。
    public var zoom: Vector2
    /// 回転（X / Y / Z、度）。
    public var rotation: Vector3
    /// カメラ行列。
    public var camera: Matrix4x4
    /// 拡大縮小の補間方式。
    public var zoomInterpolationMode: InterpolationMode
    /// 不透明度（0.0〜1.0 の評価値。アイテムの Opacity とフェードから
    /// EffectedItemSource 側が算出する）。
    public var opacity: Double
    /// 左右反転。
    public var invert: Bool
    /// この出力に付随するエフェクト操作点。
    public var controllers: [VideoEffectController]
    /// 透視の距離（未設定なら nil）。
    public var perspectiveDistance: Double?
    /// ビルボード方式。
    public var billboard: BillboardMode

    public init(
        draw: Vector3 = .zero,
        centerPoint: Vector2 = .zero,
        zoom: Vector2 = Vector2(x: 1, y: 1),
        rotation: Vector3 = .zero,
        camera: Matrix4x4 = .identity,
        zoomInterpolationMode: InterpolationMode = .cubic,
        opacity: Double = 0,
        invert: Bool = false,
        controllers: [VideoEffectController] = [],
        perspectiveDistance: Double? = nil,
        billboard: BillboardMode = .none
    ) {
        self.draw = draw
        self.centerPoint = centerPoint
        self.zoom = zoom
        self.rotation = rotation
        self.camera = camera
        self.zoomInterpolationMode = zoomInterpolationMode
        self.opacity = opacity
        self.invert = invert
        self.controllers = controllers
        self.perspectiveDistance = perspectiveDistance
        self.billboard = billboard
    }

    /// 描画位置の XY 成分（本家 DrawPoint）。
    public var drawPoint: Vector2 {
        Vector2(x: draw.x, y: draw.y)
    }

    /// 出力が無い場合の既定値。本家 EffectedItemSource.CreateEmptyDrawDescription
    /// と同じ（位置 0、拡縮 1、回転 0、単位カメラ、不透明度 0、補間 Cubic）。
    public static var empty: DrawDescription {
        DrawDescription()
    }
}
