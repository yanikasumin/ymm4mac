import Foundation

/// 本家の StringEnumConverter 対象 enum の共通形。
///
/// JSON では C# メンバ名の文字列として保存される。未知の名前（将来の本家で
/// 追加されたメンバ等）は `unknown` として名前を保持し、そのまま書き戻す
/// （データ保全のため。モデル上の意味は持たない）。
public protocol HonkeEnum: Equatable, Sendable {
    /// C# メンバ名。
    var honkeName: String { get }
    /// C# メンバ名から復元する（未知の名前は unknown として保持する）。
    init(honkeName: String)
}

/// 合成方法。本家 `Blend`（数値は本家定義どおり）。
public enum Blend: HonkeEnum {
    case normal        // Normal = 0
    case add           // Add = 1
    case subtract      // Subtract = 2
    case multiply      // Multiply = 3
    case screen        // Screen = 4
    case overlay       // Overlay = 5
    case lighter       // Lighter = 6
    case darker        // Darker = 7
    case luminosity    // Luminosity = 8
    case color         // Color = 9
    case linearBurn    // LinearBurn = 10
    case linearLight   // LinearLight = 11
    case difference    // Difference = 12
    case colorBurn     // ColorBurn = 101
    case darkerColor   // DarkerColor = 102
    case colorDodge    // ColorDodge = 103
    case linearDodge   // LinearDodge = 104
    case lighterColor  // LighterColor = 105
    case softLight     // SoftLight = 106
    case hardLight     // HardLight = 107
    case vividLight    // VividLight = 108
    case pinLight      // PinLight = 109
    case hardMix       // HardMix = 110
    case exclusion     // Exclusion = 111
    case hue           // Hue = 112
    case saturation    // Saturation = 113
    case dissolve      // Dissolve = 114
    case division      // Division = 115
    case destinationOver // DestinationOver = 116
    case destinationOut  // DestinationOut = 117
    case sourceAtop    // SourceAtop = 118
    case xor           // XOR = 119
    case maskInvert    // MaskInvert = 120
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .normal: return "Normal"
        case .add: return "Add"
        case .subtract: return "Subtract"
        case .multiply: return "Multiply"
        case .screen: return "Screen"
        case .overlay: return "Overlay"
        case .lighter: return "Lighter"
        case .darker: return "Darker"
        case .luminosity: return "Luminosity"
        case .color: return "Color"
        case .linearBurn: return "LinearBurn"
        case .linearLight: return "LinearLight"
        case .difference: return "Difference"
        case .colorBurn: return "ColorBurn"
        case .darkerColor: return "DarkerColor"
        case .colorDodge: return "ColorDodge"
        case .linearDodge: return "LinearDodge"
        case .lighterColor: return "LighterColor"
        case .softLight: return "SoftLight"
        case .hardLight: return "HardLight"
        case .vividLight: return "VividLight"
        case .pinLight: return "PinLight"
        case .hardMix: return "HardMix"
        case .exclusion: return "Exclusion"
        case .hue: return "Hue"
        case .saturation: return "Saturation"
        case .dissolve: return "Dissolve"
        case .division: return "Division"
        case .destinationOver: return "DestinationOver"
        case .destinationOut: return "DestinationOut"
        case .sourceAtop: return "SourceAtop"
        case .xor: return "XOR"
        case .maskInvert: return "MaskInvert"
        case .unknown(let name): return name
        }
    }

    public init(honkeName: String) {
        switch honkeName {
        case "Normal": self = .normal
        case "Add": self = .add
        case "Subtract": self = .subtract
        case "Multiply": self = .multiply
        case "Screen": self = .screen
        case "Overlay": self = .overlay
        case "Lighter": self = .lighter
        case "Darker": self = .darker
        case "Luminosity": self = .luminosity
        case "Color": self = .color
        case "LinearBurn": self = .linearBurn
        case "LinearLight": self = .linearLight
        case "Difference": self = .difference
        case "ColorBurn": self = .colorBurn
        case "DarkerColor": self = .darkerColor
        case "ColorDodge": self = .colorDodge
        case "LinearDodge": self = .linearDodge
        case "LighterColor": self = .lighterColor
        case "SoftLight": self = .softLight
        case "HardLight": self = .hardLight
        case "VividLight": self = .vividLight
        case "PinLight": self = .pinLight
        case "HardMix": self = .hardMix
        case "Exclusion": self = .exclusion
        case "Hue": self = .hue
        case "Saturation": self = .saturation
        case "Dissolve": self = .dissolve
        case "Division": self = .division
        case "DestinationOver": self = .destinationOver
        case "DestinationOut": self = .destinationOut
        case "SourceAtop": self = .sourceAtop
        case "XOR": self = .xor
        case "MaskInvert": self = .maskInvert
        default: self = .unknown(honkeName)
        }
    }
}

/// テキストの折り返し。本家 `WordWrap`（0 のメンバは存在しない）。
public enum WordWrap: HonkeEnum {
    case noWrap     // NoWrap = 1
    case wholeWord  // WholeWord = 3
    case character  // Character = 4
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .noWrap: return "NoWrap"
        case .wholeWord: return "WholeWord"
        case .character: return "Character"
        case .unknown(let name): return name
        }
    }

    public init(honkeName: String) {
        switch honkeName {
        case "NoWrap": self = .noWrap
        case "WholeWord": self = .wholeWord
        case "Character": self = .character
        default: self = .unknown(honkeName)
        }
    }
}

/// テキストの装飾スタイル。本家 `Style`。
public enum TextStyle: HonkeEnum {
    case normal           // Normal
    case shadow           // Shadow
    case shadowLight      // ShadowLight
    case border           // Border
    case borderLight      // BorderLight
    case sharpBorder      // SharpBorder
    case sharpBorderLight // SharpBorderLight
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .normal: return "Normal"
        case .shadow: return "Shadow"
        case .shadowLight: return "ShadowLight"
        case .border: return "Border"
        case .borderLight: return "BorderLight"
        case .sharpBorder: return "SharpBorder"
        case .sharpBorderLight: return "SharpBorderLight"
        case .unknown(let name): return name
        }
    }

    public init(honkeName: String) {
        switch honkeName {
        case "Normal": self = .normal
        case "Shadow": self = .shadow
        case "ShadowLight": self = .shadowLight
        case "Border": self = .border
        case "BorderLight": self = .borderLight
        case "SharpBorder": self = .sharpBorder
        case "SharpBorderLight": self = .sharpBorderLight
        default: self = .unknown(honkeName)
        }
    }
}

/// テキストの基準点。本家 `BasePoint`（18メンバ）。
public enum BasePoint: HonkeEnum {
    case leftTop, centerTop, rightTop
    case leftCenter, centerCenter, rightCenter
    case leftBottom, centerBottom, rightBottom
    case vTopRight, vCenterRight, vBottomRight
    case vTopCenter, vCenterCenter, vBottomCenter
    case vTopLeft, vCenterLeft, vBottomLeft
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .leftTop: return "LeftTop"
        case .centerTop: return "CenterTop"
        case .rightTop: return "RightTop"
        case .leftCenter: return "LeftCenter"
        case .centerCenter: return "CenterCenter"
        case .rightCenter: return "RightCenter"
        case .leftBottom: return "LeftBottom"
        case .centerBottom: return "CenterBottom"
        case .rightBottom: return "RightBottom"
        case .vTopRight: return "VTopRight"
        case .vCenterRight: return "VCenterRight"
        case .vBottomRight: return "VBottomRight"
        case .vTopCenter: return "VTopCenter"
        case .vCenterCenter: return "VCenterCenter"
        case .vBottomCenter: return "VBottomCenter"
        case .vTopLeft: return "VTopLeft"
        case .vCenterLeft: return "VCenterLeft"
        case .vBottomLeft: return "VBottomLeft"
        case .unknown(let name): return name
        }
    }

    public init(honkeName: String) {
        switch honkeName {
        case "LeftTop": self = .leftTop
        case "CenterTop": self = .centerTop
        case "RightTop": self = .rightTop
        case "LeftCenter": self = .leftCenter
        case "CenterCenter": self = .centerCenter
        case "RightCenter": self = .rightCenter
        case "LeftBottom": self = .leftBottom
        case "CenterBottom": self = .centerBottom
        case "RightBottom": self = .rightBottom
        case "VTopRight": self = .vTopRight
        case "VCenterRight": self = .vCenterRight
        case "VBottomRight": self = .vBottomRight
        case "VTopCenter": self = .vTopCenter
        case "VCenterCenter": self = .vCenterCenter
        case "VBottomCenter": self = .vBottomCenter
        case "VTopLeft": self = .vTopLeft
        case "VCenterLeft": self = .vCenterLeft
        case "VBottomLeft": self = .vBottomLeft
        default: self = .unknown(honkeName)
        }
    }
}

/// タイプライター表示の方向。本家 `TypewriterAnimationDirection`。
public enum TypewriterAnimationDirection: HonkeEnum {
    case fromFirst  // FromFirst
    case fromLast   // FromLast
    case random     // Random
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .fromFirst: return "FromFirst"
        case .fromLast: return "FromLast"
        case .random: return "Random"
        case .unknown(let name): return name
        }
    }

    public init(honkeName: String) {
        switch honkeName {
        case "FromFirst": self = .fromFirst
        case "FromLast": self = .fromLast
        case "Random": self = .random
        default: self = .unknown(honkeName)
        }
    }
}

/// 字幕の表示方法。本家 `JimakuVisibility`。
public enum JimakuVisibility: HonkeEnum {
    case useCharacterSetting  // UseCharacterSetting
    case visible              // Visible
    case hidden               // Hidden
    case custom               // Custom
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .useCharacterSetting: return "UseCharacterSetting"
        case .visible: return "Visible"
        case .hidden: return "Hidden"
        case .custom: return "Custom"
        case .unknown(let name): return name
        }
    }

    public init(honkeName: String) {
        switch honkeName {
        case "UseCharacterSetting": self = .useCharacterSetting
        case "Visible": self = .visible
        case "Hidden": self = .hidden
        case "Custom": self = .custom
        default: self = .unknown(honkeName)
        }
    }
}

/// 再生速度変更時の音声処理。本家 `PlaybackRateAudioProcessingMode`。
public enum PlaybackRateAudioProcessingMode: HonkeEnum {
    case resampling  // Resampling
    case sola        // Sola
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .resampling: return "Resampling"
        case .sola: return "Sola"
        case .unknown(let name): return name
        }
    }

    public init(honkeName: String) {
        switch honkeName {
        case "Resampling": self = .resampling
        case "Sola": self = .sola
        default: self = .unknown(honkeName)
        }
    }
}

/// グループアイテムの合成中心。本家 `GroupItemCompositeCenter`。
public enum GroupItemCompositeCenter: HonkeEnum {
    case screenCenter  // ScreenCenter
    case imageCenter   // ImageCenter
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .screenCenter: return "ScreenCenter"
        case .imageCenter: return "ImageCenter"
        case .unknown(let name): return name
        }
    }

    public init(honkeName: String) {
        switch honkeName {
        case "ScreenCenter": self = .screenCenter
        case "ImageCenter": self = .imageCenter
        default: self = .unknown(honkeName)
        }
    }
}

/// タイムライン補助線の種類。本家 `VerticalLineType`（宣言順は BPM, Frame, Time）。
public enum VerticalLineType: HonkeEnum {
    case bpm    // BPM = 0
    case frame  // Frame = 1
    case time   // Time = 2
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .bpm: return "BPM"
        case .frame: return "Frame"
        case .time: return "Time"
        case .unknown(let name): return name
        }
    }

    public init(honkeName: String) {
        switch honkeName {
        case "BPM": self = .bpm
        case "Frame": self = .frame
        case "Time": self = .time
        default: self = .unknown(honkeName)
        }
    }
}

/// アイテム分割後の選択方法。本家 `ItemSplitSelectionMode`
/// （None = 0, LeftOnly = 1, RightOnly = 2, Center = 3, Both = 4）。
public enum ItemSplitSelectionMode: Sendable {
    case none
    case leftOnly
    case rightOnly
    case center
    case both
}

/// 長さ変更時に隣接アイテムへ影響を与える方法。本家 `NeighborAffectMode`
/// （Default = 0, None = 1, Stretch = 2）。
///
/// `default` は設定上の値で、本家の ViewModel が設定と修飾キーから
/// `none` / `stretch` のどちらかへ解決してから Timeline へ渡す。
/// Timeline の長さ変更メソッドへ `default` が渡るのは伸長方向だけであり、
/// 本家はその場合に例外になる（到達不能な分岐として扱う）。
public enum NeighborAffectMode: HonkeEnum {
    case `default`  // Default = 0
    case none       // None = 1
    case stretch    // Stretch = 2
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .default: return "Default"
        case .none: return "None"
        case .stretch: return "Stretch"
        case .unknown(let name): return name
        }
    }

    public init(honkeName: String) {
        switch honkeName {
        case "Default": self = .default
        case "None": self = .none
        case "Stretch": self = .stretch
        default: self = .unknown(honkeName)
        }
    }
}

/// 図形パラメータのサイズ指定方法。本家 `SizeMode`
/// （`YukkuriMovieMaker.Project.Items.SizeMode`、SizeAspect = 0,
/// WidthHeight = 1）。
public enum SizeMode: HonkeEnum {
    case sizeAspect   // SizeAspect = 0
    case widthHeight  // WidthHeight = 1
    case unknown(String)

    public var honkeName: String {
        switch self {
        case .sizeAspect: return "SizeAspect"
        case .widthHeight: return "WidthHeight"
        case .unknown(let name): return name
        }
    }

    public init(honkeName: String) {
        switch honkeName {
        case "SizeAspect": self = .sizeAspect
        case "WidthHeight": self = .widthHeight
        default: self = .unknown(honkeName)
        }
    }
}
