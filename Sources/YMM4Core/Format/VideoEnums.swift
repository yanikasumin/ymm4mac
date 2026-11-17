import Foundation

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
