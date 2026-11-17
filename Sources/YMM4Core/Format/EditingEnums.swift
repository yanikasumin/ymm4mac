import Foundation

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
