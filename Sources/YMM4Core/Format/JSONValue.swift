import Foundation

/// 順序を保持する JSON 値。
///
/// .ymmp 互換層の基盤。本家の保存形式（Newtonsoft.Json）はオブジェクトの
/// キー順序をそのまま書き出すため、往復保全には順序保持が必須になる。
/// 数値は元のリテラル文字列を保持し、書き戻し時に一字一句そのまま出す
/// （モデル側が生成する数値は `number(_:)` ファクトリで Newtonsoft 形式に
/// 整形する）。`Foundation.JSONSerialization` はキー順序も数値リテラルも
/// 保持しないため、パーサとシリアライザを自前で持つ。
public enum JSONValue: Sendable {
    case null
    case bool(Bool)
    /// 数値リテラル（原文のまま保持する）。
    case numberLiteral(String)
    case string(String)
    case array([JSONValue])
    /// キー順序を保持するオブジェクト。
    case object([(key: String, value: JSONValue)])
}

extension JSONValue: Equatable {
    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            return true
        case (.bool(let a), .bool(let b)):
            return a == b
        case (.numberLiteral(let a), .numberLiteral(let b)):
            return a == b
        case (.string(let a), .string(let b)):
            return a == b
        case (.array(let a), .array(let b)):
            return a == b
        case (.object(let a), .object(let b)):
            guard a.count == b.count else { return false }
            for (lhsField, rhsField) in zip(a, b) {
                if lhsField.key != rhsField.key || lhsField.value != rhsField.value {
                    return false
                }
            }
            return true
        default:
            return false
        }
    }
}

public extension JSONValue {
    /// 整数を Newtonsoft 形式のリテラルで保持する。
    static func number(_ value: Int) -> JSONValue {
        .numberLiteral(String(value))
    }

    /// 浮動小数点数を Newtonsoft 形式のリテラルで保持する。
    ///
    /// Newtonsoft は Double を最短往復形式（"R" 形式）で書く。積分値は
    /// "100.0" のように小数部を残す。Swift の `String(describing:)` も
    /// 最短往復形式であり、指数表記の 'E' の大文字化だけ合わせる。
    static func number(_ value: Double) -> JSONValue {
        .numberLiteral(newtonsoftDoubleLiteral(value))
    }

    /// Float を Newtonsoft 形式のリテラルで保持する（float の最短往復形式）。
    static func number(_ value: Float) -> JSONValue {
        .numberLiteral(newtonsoftFloatLiteral(value))
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectFields: [(key: String, value: JSONValue)]? {
        if case .object(let fields) = self { return fields }
        return nil
    }

    /// 数値としての値。リテラルが整数形式なら整数として、そうでなければ
    /// Double として解釈する。
    var doubleValue: Double? {
        if case .numberLiteral(let literal) = self {
            return Double(literal)
        }
        return nil
    }

    /// 整数としての値。"5.0" のような積分値の浮動小数点リテラルも許容する
    /// （Newtonsoft は積分値の実数トークンを int プロパティへ変換できる）。
    var intValue: Int? {
        guard case .numberLiteral(let literal) = self else { return nil }
        if let value = Int(literal) { return value }
        if let double = Double(literal), double.rounded() == double,
           double >= Double(Int.min), double <= Double(Int.max) {
            return Int(double)
        }
        return nil
    }

    /// オブジェクトのキー検索（最初の一致）。
    func field(_ key: String) -> JSONValue? {
        guard case .object(let fields) = self else { return nil }
        return fields.first(where: { $0.key == key })?.value
    }

    /// JSON テキストへシリアライズする。
    ///
    /// 文字列のエスケープは Newtonsoft の既定（StringEscapeHandling.Default）
    /// に合わせ、制御文字・引用符・バックスラッシュのみをエスケープし、
    /// 非 ASCII は UTF-8 のまま出す。
    func serialized() -> String {
        var output = ""
        write(into: &output)
        return output
    }

    private func write(into output: inout String) {
        switch self {
        case .null:
            output += "null"
        case .bool(let value):
            output += value ? "true" : "false"
        case .numberLiteral(let literal):
            output += literal
        case .string(let value):
            Self.writeEscaped(value, into: &output)
        case .array(let elements):
            output += "["
            for (index, element) in elements.enumerated() {
                if index > 0 { output += "," }
                element.write(into: &output)
            }
            output += "]"
        case .object(let fields):
            output += "{"
            for (index, field) in fields.enumerated() {
                if index > 0 { output += "," }
                Self.writeEscaped(field.key, into: &output)
                output += ":"
                field.value.write(into: &output)
            }
            output += "}"
        }
    }

    private static func writeEscaped(_ value: String, into output: inout String) {
        output += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                output += "\\\""
            case "\\":
                output += "\\\\"
            case "\n":
                output += "\\n"
            case "\r":
                output += "\\r"
            case "\t":
                output += "\\t"
            default:
                if scalar.value < 0x20 {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        output += "\""
    }
}

/// Newtonsoft の Double 書き出し形式（最短往復、指数は 'E' 大文字）。
func newtonsoftDoubleLiteral(_ value: Double) -> String {
    if value.isNaN || value.isInfinite {
        // Newtonsoft の既定では NaN / Infinity は JSON として不正な文字列表現に
        // なる。モデル層の値では到達しない前提で 0.0 に落とす。
        return "0.0"
    }
    var text = String(describing: value)
    if let eIndex = text.firstIndex(of: "e") {
        let mantissa = text[..<eIndex]
        var exponent = text[text.index(after: eIndex)...]
        // Swift は "1e+20" のように符号付きで出す。Newtonsoft も符号付きだが
        // 先行ゼロは付けないため、そのまま 'E' へ置換するだけで一致する。
        if exponent.first == "+" {
            exponent = exponent.dropFirst()
            text = "\(mantissa)E+\(exponent)"
        } else {
            text = "\(mantissa)E\(exponent)"
        }
    }
    return text
}

/// Newtonsoft の Float 書き出し形式（float 精度の最短往復）。
func newtonsoftFloatLiteral(_ value: Float) -> String {
    if value.isNaN || value.isInfinite {
        return "0.0"
    }
    var text = String(describing: value)
    if let eIndex = text.firstIndex(of: "e") {
        let mantissa = text[..<eIndex]
        var exponent = text[text.index(after: eIndex)...]
        if exponent.first == "+" {
            exponent = exponent.dropFirst()
            text = "\(mantissa)E+\(exponent)"
        } else {
            text = "\(mantissa)E\(exponent)"
        }
    }
    return text
}

/// JSON パースエラー。
public struct JSONParseError: Error, Sendable {
    public var message: String
    public var offset: Int

    public init(message: String, offset: Int) {
        self.message = message
        self.offset = offset
    }
}

/// 順序と数値リテラルを保持する JSON パーサ。
public struct JSONParser {
    private let bytes: [UInt8]
    private var position: Int = 0

    public init(text: String) {
        bytes = Array(text.utf8)
    }

    /// テキスト全体を1つの JSON 値としてパースする。末尾の空白以外が
    /// 残っている場合はエラー。
    public mutating func parse() throws -> JSONValue {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        guard position == bytes.count else {
            throw JSONParseError(message: "末尾に余分な文字があります", offset: position)
        }
        return value
    }

    private mutating func skipWhitespace() {
        while position < bytes.count {
            switch bytes[position] {
            case 0x20, 0x09, 0x0A, 0x0D:
                position += 1
            default:
                return
            }
        }
    }

    private mutating func parseValue() throws -> JSONValue {
        guard position < bytes.count else {
            throw JSONParseError(message: "値がありません", offset: position)
        }
        switch bytes[position] {
        case 0x7B: // {
            return try parseObject()
        case 0x5B: // [
            return try parseArray()
        case 0x22: // "
            return .string(try parseString())
        case 0x74: // t
            try expectLiteral("true")
            return .bool(true)
        case 0x66: // f
            try expectLiteral("false")
            return .bool(false)
        case 0x6E: // n
            try expectLiteral("null")
            return .null
        default:
            return try parseNumber()
        }
    }

    private mutating func expectLiteral(_ literal: String) throws {
        for byte in literal.utf8 {
            guard position < bytes.count, bytes[position] == byte else {
                throw JSONParseError(message: "リテラル '\(literal)' が不正です", offset: position)
            }
            position += 1
        }
    }

    private mutating func parseObject() throws -> JSONValue {
        position += 1 // {
        var fields: [(key: String, value: JSONValue)] = []
        skipWhitespace()
        if position < bytes.count, bytes[position] == 0x7D { // }
            position += 1
            return .object(fields)
        }
        while true {
            skipWhitespace()
            guard position < bytes.count, bytes[position] == 0x22 else {
                throw JSONParseError(message: "オブジェクトのキーが文字列ではありません", offset: position)
            }
            let key = try parseString()
            skipWhitespace()
            guard position < bytes.count, bytes[position] == 0x3A else { // :
                throw JSONParseError(message: "':' がありません", offset: position)
            }
            position += 1
            skipWhitespace()
            let value = try parseValue()
            fields.append((key: key, value: value))
            skipWhitespace()
            guard position < bytes.count else {
                throw JSONParseError(message: "オブジェクトが閉じていません", offset: position)
            }
            if bytes[position] == 0x2C { // ,
                position += 1
                continue
            }
            if bytes[position] == 0x7D { // }
                position += 1
                return .object(fields)
            }
            throw JSONParseError(message: "',' または '}' がありません", offset: position)
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        position += 1 // [
        var elements: [JSONValue] = []
        skipWhitespace()
        if position < bytes.count, bytes[position] == 0x5D { // ]
            position += 1
            return .array(elements)
        }
        while true {
            skipWhitespace()
            elements.append(try parseValue())
            skipWhitespace()
            guard position < bytes.count else {
                throw JSONParseError(message: "配列が閉じていません", offset: position)
            }
            if bytes[position] == 0x2C { // ,
                position += 1
                continue
            }
            if bytes[position] == 0x5D { // ]
                position += 1
                return .array(elements)
            }
            throw JSONParseError(message: "',' または ']' がありません", offset: position)
        }
    }

    private mutating func parseString() throws -> String {
        position += 1 // "
        var output: [UInt8] = []
        while position < bytes.count {
            let byte = bytes[position]
            if byte == 0x22 { // "
                position += 1
                return String(decoding: output, as: UTF8.self)
            }
            if byte == 0x5C { // backslash
                position += 1
                guard position < bytes.count else { break }
                let escape = bytes[position]
                position += 1
                switch escape {
                case 0x22: output.append(0x22)
                case 0x5C: output.append(0x5C)
                case 0x2F: output.append(0x2F)
                case 0x62: output.append(0x08) // \b
                case 0x66: output.append(0x0C) // \f
                case 0x6E: output.append(0x0A) // \n
                case 0x72: output.append(0x0D) // \r
                case 0x74: output.append(0x09) // \t
                case 0x75: // \uXXXX
                    let scalar = try parseUnicodeEscape()
                    output.append(contentsOf: String(scalar).utf8)
                default:
                    throw JSONParseError(message: "不正なエスケープです", offset: position - 1)
                }
                continue
            }
            output.append(byte)
            position += 1
        }
        throw JSONParseError(message: "文字列が閉じていません", offset: position)
    }

    private mutating func parseUnicodeEscape() throws -> Unicode.Scalar {
        let first = try parseHex4()
        if (0xD800...0xDBFF).contains(first) {
            // サロゲートペア。下位サロゲートが続く場合だけ結合し、
            // 続かない場合は置換文字にする（Newtonsoft は壊れた文字列を
            // 作るが、Swift の String では表現できないため）。
            if position + 1 < bytes.count, bytes[position] == 0x5C, bytes[position + 1] == 0x75 {
                position += 2
                let second = try parseHex4()
                if (0xDC00...0xDFFF).contains(second) {
                    let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                    if let scalar = Unicode.Scalar(combined) {
                        return scalar
                    }
                }
                return Unicode.Scalar(0xFFFD)!
            }
            return Unicode.Scalar(0xFFFD)!
        }
        if (0xDC00...0xDFFF).contains(first) {
            return Unicode.Scalar(0xFFFD)!
        }
        guard let scalar = Unicode.Scalar(first) else {
            return Unicode.Scalar(0xFFFD)!
        }
        return scalar
    }

    private mutating func parseHex4() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard position < bytes.count else {
                throw JSONParseError(message: "\\u エスケープが不足しています", offset: position)
            }
            let byte = bytes[position]
            let digit: UInt32
            switch byte {
            case 0x30...0x39: digit = UInt32(byte - 0x30)
            case 0x61...0x66: digit = UInt32(byte - 0x61) + 10
            case 0x41...0x46: digit = UInt32(byte - 0x41) + 10
            default:
                throw JSONParseError(message: "\\u エスケープが16進数ではありません", offset: position)
            }
            value = value * 16 + digit
            position += 1
        }
        return value
    }

    private mutating func parseNumber() throws -> JSONValue {
        let start = position
        while position < bytes.count {
            switch bytes[position] {
            case 0x2D, 0x2B, 0x2E, 0x30...0x39, 0x65, 0x45: // - + . 0-9 e E
                position += 1
            default:
                guard position > start else {
                    throw JSONParseError(message: "値の形式が不正です", offset: position)
                }
                return .numberLiteral(String(decoding: bytes[start..<position], as: UTF8.self))
            }
        }
        guard position > start else {
            throw JSONParseError(message: "値の形式が不正です", offset: position)
        }
        return .numberLiteral(String(decoding: bytes[start..<position], as: UTF8.self))
    }
}
