import Foundation

/// GPU 処理系エフェクトの暫定処理器（GPU 処理器は未実装）。
///
/// 定義層だけが型付けされた GPU 系エフェクトがエフェクト連鎖へ供給された
/// 場合に使う。入力をそのまま素通しし、`DrawDescription` も無変換で返す。
/// 本家の GPU 処理（画像そのものの加工）は行われないため、この処理器を
/// 返す定義は「描画結果が本家と異なる」ことが型の上で明示される。
/// GPU 処理器（Metal）が実装された定義から順に差し替えられる。
public final class GPUEffectPassthroughProcessor: DrawDescriptionEffectProcessor {
    public override init() {
        super.init()
    }
}

/// GPU 処理系エフェクト定義の共通基盤。
///
/// パラメータの型付け（定義層）のみを行い、処理器は暫定の素通し
/// （`GPUEffectPassthroughProcessor`）を返す。入出場系・ランダム系・
/// 反復系の GPU エフェクトは本家の中間基底（`InOutEffectDefinitionBase`
/// 等）を継承するため、この基盤ではなく各中間基底の側で
/// `createProcessor()` を暫定処理器へ差し替える。
open class GPUEffectDefinitionBase: VideoEffectDefinitionBase {
    public override func createProcessor() -> any VideoEffectProcessor {
        GPUEffectPassthroughProcessor()
    }
}

// MARK: - GPU 系エフェクトで使う列挙型（保存はメンバ名文字列）

/// 自動ズームの方向。本家 `AutomaticZoomMode`
/// （UpDown = 3, UpOnly = 1, DownOnly = 2）。
public enum AutomaticZoomMode: HonkeEnum {
    case upDown
    case upOnly
    case downOnly
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .upDown: return "UpDown"
        case .upOnly: return "UpOnly"
        case .downOnly: return "DownOnly"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "UpDown": self = .upDown
        case "UpOnly": self = .upOnly
        case "DownOnly": self = .downOnly
        default: self = .unknown(name)
        }
    }
}

/// 自動ズームの対象。本家 `AutomaticZoomTarget`
/// （WidthHeight = 3, WidthOnly = 1, HeightOnly = 2）。
public enum AutomaticZoomTarget: HonkeEnum {
    case widthHeight
    case widthOnly
    case heightOnly
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .widthHeight: return "WidthHeight"
        case .widthOnly: return "WidthOnly"
        case .heightOnly: return "HeightOnly"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "WidthHeight": self = .widthHeight
        case "WidthOnly": self = .widthOnly
        case "HeightOnly": self = .heightOnly
        default: self = .unknown(name)
        }
    }
}

/// 中心位置（横）。本家 `CenterPointHorizontal`（宣言順に Origin から）。
public enum CenterPointHorizontal: HonkeEnum {
    case origin
    case left
    case center
    case right
    case custom
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .origin: return "Origin"
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        case .custom: return "Custom"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Origin": self = .origin
        case "Left": self = .left
        case "Center": self = .center
        case "Right": self = .right
        case "Custom": self = .custom
        default: self = .unknown(name)
        }
    }
}

/// 中心位置（縦）。本家 `CenterPointVertical`（宣言順に Origin から）。
public enum CenterPointVertical: HonkeEnum {
    case origin
    case top
    case center
    case bottom
    case custom
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .origin: return "Origin"
        case .top: return "Top"
        case .center: return "Center"
        case .bottom: return "Bottom"
        case .custom: return "Custom"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Origin": self = .origin
        case "Top": self = .top
        case "Center": self = .center
        case "Bottom": self = .bottom
        case "Custom": self = .custom
        default: self = .unknown(name)
        }
    }
}

/// 中心位置の旧形式。本家 `CenterPointMode`。
///
/// 現行形式では `Horizontal` / `Vertical` の組に分解される。set 専用の
/// 旧互換プロパティ `Mode` の読み込み変換だけに使う（保存はされない）。
public enum CenterPointMode: HonkeEnum {
    case custom
    case leftTop
    case centerTop
    case rightTop
    case leftCenter
    case centerCenter
    case rightCenter
    case leftBottom
    case centerBottom
    case rightBottom
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .custom: return "Custom"
        case .leftTop: return "LeftTop"
        case .centerTop: return "CenterTop"
        case .rightTop: return "RightTop"
        case .leftCenter: return "LeftCenter"
        case .centerCenter: return "CenterCenter"
        case .rightCenter: return "RightCenter"
        case .leftBottom: return "LeftBottom"
        case .centerBottom: return "CenterBottom"
        case .rightBottom: return "RightBottom"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Custom": self = .custom
        case "LeftTop": self = .leftTop
        case "CenterTop": self = .centerTop
        case "RightTop": self = .rightTop
        case "LeftCenter": self = .leftCenter
        case "CenterCenter": self = .centerCenter
        case "RightCenter": self = .rightCenter
        case "LeftBottom": self = .leftBottom
        case "CenterBottom": self = .centerBottom
        case "RightBottom": self = .rightBottom
        default: self = .unknown(name)
        }
    }
}

/// クロマキーの距離計算。本家 `ChromakeyDistanceMode`（宣言順）。
public enum ChromakeyDistanceMode: HonkeEnum {
    case rgb
    case yuv
    case yuvIgnoreLuma
    case ciede2000
    case colorDifference
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .rgb: return "RGB"
        case .yuv: return "YUV"
        case .yuvIgnoreLuma: return "YUVIgnoreLuma"
        case .ciede2000: return "CIEDE2000"
        case .colorDifference: return "ColorDifference"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "RGB": self = .rgb
        case "YUV": self = .yuv
        case "YUVIgnoreLuma": self = .yuvIgnoreLuma
        case "CIEDE2000": self = .ciede2000
        case "ColorDifference": self = .colorDifference
        default: self = .unknown(name)
        }
    }
}

/// ディスプレイスメントマップの変形方式。本家
/// `DisplacementMapTransformMode`（宣言順 Move / Scale / Rotate）。
public enum DisplacementMapTransformMode: HonkeEnum {
    case move
    case scale
    case rotate
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .move: return "Move"
        case .scale: return "Scale"
        case .rotate: return "Rotate"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Move": self = .move
        case "Scale": self = .scale
        case "Rotate": self = .rotate
        default: self = .unknown(name)
        }
    }
}

/// グラデーションの形状。本家 `GradientType`
/// （Linear = 0, Round = 1, Convex = 3）。
public enum GradientType: HonkeEnum {
    case linear
    case round
    case convex
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .linear: return "Linear"
        case .round: return "Round"
        case .convex: return "Convex"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Linear": self = .linear
        case "Round": self = .round
        case "Convex": self = .convex
        default: self = .unknown(name)
        }
    }
}

/// グラデーションの延長方式。本家 `ExtendMode`（宣言順）。
public enum ExtendMode: HonkeEnum {
    case clamp
    case wrap
    case mirror
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .clamp: return "Clamp"
        case .wrap: return "Wrap"
        case .mirror: return "Mirror"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Clamp": self = .clamp
        case "Wrap": self = .wrap
        case "Mirror": self = .mirror
        default: self = .unknown(name)
        }
    }
}

/// ハーフトーンの配置。本家 `HalfToneLayout`（宣言順）。
public enum HalfToneLayout: HonkeEnum {
    case triangle
    case rectangle
    case rhombus
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .triangle: return "Triangle"
        case .rectangle: return "Rectangle"
        case .rhombus: return "Rhombus"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Triangle": self = .triangle
        case "Rectangle": self = .rectangle
        case "Rhombus": self = .rhombus
        default: self = .unknown(name)
        }
    }
}

/// モルフォロジーの方式。本家 `MorphologyEffectMode`（宣言順）。
public enum MorphologyEffectMode: HonkeEnum {
    case erode
    case dilate
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .erode: return "Erode"
        case .dilate: return "Dilate"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Erode": self = .erode
        case "Dilate": self = .dilate
        default: self = .unknown(name)
        }
    }
}

/// モザイクの形状。本家 `MosaicType`（宣言順）。
public enum MosaicType: HonkeEnum {
    case circle
    case triangle
    case rectangle
    case hexagon
    case delaunay
    case voronoi
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .circle: return "Circle"
        case .triangle: return "Triangle"
        case .rectangle: return "Rectangle"
        case .hexagon: return "Hexagon"
        case .delaunay: return "Delaunay"
        case .voronoi: return "Voronoi"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Circle": self = .circle
        case "Triangle": self = .triangle
        case "Rectangle": self = .rectangle
        case "Hexagon": self = .hexagon
        case "Delaunay": self = .delaunay
        case "Voronoi": self = .voronoi
        default: self = .unknown(name)
        }
    }
}

/// ノイズの生成方式。本家 `NoiseType`
/// （Fractal = 0, Random = 3, Block = 100, Perlin = 101, Cellular = 102,
/// Voronoi = 103, Simplex = 104, Curl = 105, Marble = 106, Flow = 107）。
public enum NoiseType: HonkeEnum {
    case fractal
    case random
    case block
    case perlin
    case cellular
    case voronoi
    case simplex
    case curl
    case marble
    case flow
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .fractal: return "Fractal"
        case .random: return "Random"
        case .block: return "Block"
        case .perlin: return "Perlin"
        case .cellular: return "Cellular"
        case .voronoi: return "Voronoi"
        case .simplex: return "Simplex"
        case .curl: return "Curl"
        case .marble: return "Marble"
        case .flow: return "Flow"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Fractal": self = .fractal
        case "Random": self = .random
        case "Block": self = .block
        case "Perlin": self = .perlin
        case "Cellular": self = .cellular
        case "Voronoi": self = .voronoi
        case "Simplex": self = .simplex
        case "Curl": self = .curl
        case "Marble": self = .marble
        case "Flow": self = .flow
        default: self = .unknown(name)
        }
    }
}

/// 枠線の種類。本家 `FrameLineType`（宣言順）。
public enum FrameLineType: HonkeEnum {
    case all
    case top
    case bottom
    case left
    case right
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .all: return "All"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "All": self = .all
        case "Top": self = .top
        case "Bottom": self = .bottom
        case "Left": self = .left
        case "Right": self = .right
        default: self = .unknown(name)
        }
    }
}

/// 描画の配置。本家 `RenderPlacement`（Front = 0, Back = 1）。
public enum RenderPlacement: HonkeEnum {
    case front
    case back
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .front: return "Front"
        case .back: return "Back"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Front": self = .front
        case "Back": self = .back
        default: self = .unknown(name)
        }
    }
}

/// 傾斜の中心点。本家 `SkewCenterPoint`（宣言順）。
public enum SkewCenterPoint: HonkeEnum {
    case center
    case top
    case bottom
    case left
    case right
    case custom
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .center: return "Center"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        case .custom: return "Custom"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Center": self = .center
        case "Top": self = .top
        case "Bottom": self = .bottom
        case "Left": self = .left
        case "Right": self = .right
        case "Custom": self = .custom
        default: self = .unknown(name)
        }
    }
}

/// 起き上がりの基準線。本家 `InOutGetUpEffect.BaseLine`（宣言順）。
public enum InOutGetUpBaseLine: HonkeEnum {
    case top
    case bottom
    case left
    case right
    case centerX
    case centerY
    case trueCenterX
    case trueCenterY
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        case .centerX: return "CenterX"
        case .centerY: return "CenterY"
        case .trueCenterX: return "TrueCenterX"
        case .trueCenterY: return "TrueCenterY"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Top": self = .top
        case "Bottom": self = .bottom
        case "Left": self = .left
        case "Right": self = .right
        case "CenterX": self = .centerX
        case "CenterY": self = .centerY
        case "TrueCenterX": self = .trueCenterX
        case "TrueCenterY": self = .trueCenterY
        default: self = .unknown(name)
        }
    }
}

/// 起き上がりの方向。本家 `InOutGetUpEffect.GetUpDirection`（宣言順）。
public enum InOutGetUpDirection: HonkeEnum {
    case back
    case front
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .back: return "Back"
        case .front: return "Front"
        case .unknown(let name): return name
        }
    }

    public init(honkeName name: String) {
        switch name {
        case "Back": self = .back
        case "Front": self = .front
        default: self = .unknown(name)
        }
    }
}
