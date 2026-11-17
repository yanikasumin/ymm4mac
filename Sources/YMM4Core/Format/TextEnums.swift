import Foundation

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
