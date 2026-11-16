import Foundation

/// .NET の `TimeSpan` に対応する値（100ns tick 単位）。
///
/// .ymmp では Newtonsoft が "c" 形式の文字列（例: "00:00:05.5000000"、
/// 1日以上は "1.12:00:00"）で書き出す。秒の Double で保持すると往復で
/// 欠落するため、tick の整数で保持する。
public struct TimeSpanValue: Equatable, Sendable, Comparable {
    /// 100ns 単位の tick 数。
    public var ticks: Int64

    public static let zero = TimeSpanValue(ticks: 0)
    /// 1秒あたりの tick 数。
    public static let ticksPerSecond: Int64 = 10_000_000

    public init(ticks: Int64) {
        self.ticks = ticks
    }

    public init(seconds: Double) {
        ticks = Int64((seconds * Double(Self.ticksPerSecond)).rounded(.awayFromZero))
    }

    public var seconds: Double {
        Double(ticks) / Double(Self.ticksPerSecond)
    }

    public static func + (lhs: TimeSpanValue, rhs: TimeSpanValue) -> TimeSpanValue {
        TimeSpanValue(ticks: lhs.ticks + rhs.ticks)
    }

    public static func - (lhs: TimeSpanValue, rhs: TimeSpanValue) -> TimeSpanValue {
        TimeSpanValue(ticks: lhs.ticks - rhs.ticks)
    }

    public static func < (lhs: TimeSpanValue, rhs: TimeSpanValue) -> Bool {
        lhs.ticks < rhs.ticks
    }

    /// .NET の "c" 形式文字列。
    public var honkeString: String {
        let negative = ticks < 0
        var remaining = negative ? -ticks : ticks
        let days = remaining / 864_000_000_000
        remaining %= 864_000_000_000
        let hours = remaining / 36_000_000_000
        remaining %= 36_000_000_000
        let minutes = remaining / 600_000_000
        remaining %= 600_000_000
        let secondsPart = remaining / Self.ticksPerSecond
        let fraction = remaining % Self.ticksPerSecond

        var text = negative ? "-" : ""
        if days > 0 {
            text += "\(days)."
        }
        text += String(format: "%02d:%02d:%02d", hours, minutes, secondsPart)
        if fraction != 0 {
            text += String(format: ".%07d", fraction)
        }
        return text
    }

    /// "c" 形式（および小数桁が短い変形）をパースする。不正なら nil。
    public init?(honkeString: String) {
        var text = honkeString
        var negative = false
        if text.hasPrefix("-") {
            negative = true
            text.removeFirst()
        } else if text.hasPrefix("+") {
            text.removeFirst()
        }
        // [days.]hh:mm:ss[.fraction]
        // 小数部は最後の "." の後ろに ":" を含まない部分、日数は最初の
        // "." の前にある数値部分で判別する。
        var days: Int64 = 0
        var fractionTicks: Int64 = 0
        var mainPart = text[...]
        if let lastDot = mainPart.lastIndex(of: "."),
           !mainPart[mainPart.index(after: lastDot)...].contains(":") {
            guard let fraction = Self.parseFraction(mainPart[mainPart.index(after: lastDot)...]) else {
                return nil
            }
            fractionTicks = fraction
            mainPart = mainPart[..<lastDot]
        }
        if let firstDot = mainPart.firstIndex(of: ".") {
            guard let parsedDays = Int64(mainPart[..<firstDot]) else { return nil }
            days = parsedDays
            mainPart = mainPart[mainPart.index(after: firstDot)...]
        }
        let hms = mainPart.split(separator: ":", omittingEmptySubsequences: false)
        guard hms.count == 3,
              let hours = Int64(hms[0]),
              let minutes = Int64(hms[1]),
              let secondsPart = Int64(hms[2]) else {
            return nil
        }
        var total = days * 864_000_000_000
        total += hours * 36_000_000_000
        total += minutes * 600_000_000
        total += secondsPart * Self.ticksPerSecond
        total += fractionTicks
        ticks = negative ? -total : total
    }

    private static func parseFraction(_ text: Substring) -> Int64? {
        guard !text.isEmpty, text.count <= 7, text.allSatisfy({ $0.isNumber }) else {
            return nil
        }
        var digits = String(text)
        while digits.count < 7 {
            digits += "0"
        }
        return Int64(digits)
    }
}

public extension Color {
    /// WPF `Color` の TypeConverter 表現 "#AARRGGBB"。
    var honkeString: String {
        let hex = Array("0123456789ABCDEF")
        func byteText(_ byte: UInt8) -> String {
            String([hex[Int(byte >> 4)], hex[Int(byte & 0x0F)]])
        }
        return "#" + byteText(alpha) + byteText(red) + byteText(green) + byteText(blue)
    }

    /// "#AARRGGBB" / "#RRGGBB" をパースする。不正なら nil。
    init?(honkeString: String) {
        var text = honkeString
        guard text.hasPrefix("#") else { return nil }
        text.removeFirst()
        func byte(from pair: Substring) -> UInt8? {
            UInt8(pair, radix: 16)
        }
        let chars = Array(text)
        if chars.count == 8 {
            guard let a = byte(from: text.prefix(2)),
                  let r = byte(from: text.dropFirst(2).prefix(2)),
                  let g = byte(from: text.dropFirst(4).prefix(2)),
                  let b = byte(from: text.dropFirst(6).prefix(2)) else {
                return nil
            }
            self.init(alpha: a, red: r, green: g, blue: b)
        } else if chars.count == 6 {
            guard let r = byte(from: text.prefix(2)),
                  let g = byte(from: text.dropFirst(2).prefix(2)),
                  let b = byte(from: text.dropFirst(4).prefix(2)) else {
                return nil
            }
            self.init(alpha: 255, red: r, green: g, blue: b)
        } else {
            return nil
        }
        _ = chars
    }

    /// 本家の `Colors.White`（#FFFFFFFF）。
    static let white = Color(alpha: 255, red: 255, green: 255, blue: 255)
    /// 本家の `Colors.Black`（#FF000000）。
    static let black = Color(alpha: 255, red: 0, green: 0, blue: 0)
    /// 本家の `Colors.Red`（#FFFF0000）。
    static let red = Color(alpha: 255, red: 255, green: 0, blue: 0)
}

/// 本家 `RenamedTypeResolver` の再現。
///
/// $type のアセンブリ修飾名を受け取り、改名・移行先の名前に解決する。
/// 規則は本家コードそのままで、(1) コミュニティエフェクト11件の
/// 名前空間・アセンブリ移行、(2) OutlineLiteEffect → OutlineEffect の
/// 本家リネーム1件、の2種類だけが存在する。
public enum RenamedTypeResolver {
    private static let communityEffects = [
        "Binarization", "CircularBlur", "ColorCorrection", "ColorShift",
        "InnerOutline", "LongShadow", "Ripple", "SpiralTransform",
        "StripeGlitchNoise", "ThreeDimensional", "Wave",
    ]
    private static let communityEffectNamespace = "YukkuriMovieMaker.Plugin.Community.Effect.Video"
    private static let communityEffectAssembly = "YukkuriMovieMaker.Plugin.Community"
    private static let ymmVideoEffectNamespace = "YukkuriMovieMaker.Project.Effects"
    private static let ymmAssembly = "YukkuriMovieMaker"

    public static func resolveTypeName(_ assemblyQualifiedName: String) -> String {
        let parts = assemblyQualifiedName.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return assemblyQualifiedName }
        let fullName = String(parts[0])
        let assembly = parts[1].trimmingCharacters(in: .whitespaces)
        guard assembly == ymmAssembly else { return assemblyQualifiedName }
        for name in communityEffects
        where fullName == "\(ymmVideoEffectNamespace).\(name)Effect" {
            return "\(communityEffectNamespace).\(name).\(name)Effect, \(communityEffectAssembly)"
        }
        if fullName == "\(ymmVideoEffectNamespace).OutlineLiteEffect" {
            return "\(ymmVideoEffectNamespace).OutlineEffect, \(ymmAssembly)"
        }
        return assemblyQualifiedName
    }
}

/// 意味論をモデル化しない型付きオブジェクトの保存表現。
///
/// エフェクトやプラグイン固有パラメータなど、インタフェース型で保持される
/// 値は $type 名を含む生 JSON をそのまま保持し、保存時に書き戻す。
/// 読み込み時には本家同様に `RenamedTypeResolver` の移行を $type へ適用する
/// （本家は移行先の型として読み込むため、再保存時は移行先の名前になる）。
public struct PreservedObject: Equatable, Sendable {
    /// 生 JSON（通常は $type を含むオブジェクト）。
    public var value: JSONValue

    public init(_ value: JSONValue) {
        self.value = value
    }

    /// $type の値（無ければ nil）。
    public var typeName: String? {
        value.field("$type")?.stringValue
    }

    /// 本家の型移行を $type へ適用した複製を返す。
    public func applyingTypeMigration() -> PreservedObject {
        guard let typeName,
              case .object(var fields) = value else {
            return self
        }
        let resolved = RenamedTypeResolver.resolveTypeName(typeName)
        guard resolved != typeName else { return self }
        for index in fields.indices where fields[index].key == "$type" {
            fields[index].value = .string(resolved)
        }
        return PreservedObject(.object(fields))
    }
}

public extension AnimationType {
    /// StringEnumConverter が書き出す C# メンバ名。
    ///
    /// 基本型は日本語名、イージング系は "科_モード[_Int]"、ベジェは
    /// "Linear_Bezier" / "Interpolation_Bezier"。
    var honkeName: String {
        switch self {
        case .none: return "なし"
        case .linear: return "直線移動"
        case .instant: return "瞬間移動"
        case .movementAmount: return "移動量指定"
        case .random: return "ランダム移動"
        case .repetitive: return "反復移動"
        case .interpolation: return "補間移動"
        case .accelerationDeceleration: return "加減速移動"
        case .linearBezier: return "Linear_Bezier"
        case .interpolationBezier: return "Interpolation_Bezier"
        default:
            // イージング系: rawValue = 科(100..109) * 100 + モード(1..8)
            let familyNames = [
                100: "Quad", 101: "Cubic", 102: "Quart", 103: "Quint", 104: "Sine",
                105: "Circ", 106: "Expo", 107: "Back", 108: "Elastic", 109: "Bounce",
            ]
            let modeNames = [
                1: "In", 2: "Out", 3: "InOut", 4: "OutIn",
                5: "In_Int", 6: "Out_Int", 7: "InOut_Int", 8: "OutIn_Int",
            ]
            let family = rawValue / 100
            let mode = rawValue % 100
            if let familyName = familyNames[family], let modeName = modeNames[mode] {
                return "\(familyName)_\(modeName)"
            }
            return "なし"
        }
    }

    /// C# メンバ名から復元する。未知の名前は nil。
    init?(honkeName: String) {
        if let type = Self.nameTable[honkeName] {
            self = type
            return
        }
        return nil
    }

    private static let nameTable: [String: AnimationType] = {
        var table: [String: AnimationType] = [:]
        let baseRawValues = [0, 1, 3, 5, 6, 8, 15, 103, 100_000, 100_001]
        for rawValue in baseRawValues {
            if let type = AnimationType(rawValue: rawValue) {
                table[type.honkeName] = type
            }
        }
        for family in 100...109 {
            for mode in 1...8 {
                if let type = AnimationType(rawValue: family * 100 + mode) {
                    table[type.honkeName] = type
                }
            }
        }
        return table
    }()
}
