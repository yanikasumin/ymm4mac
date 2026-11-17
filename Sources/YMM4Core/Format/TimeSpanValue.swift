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
