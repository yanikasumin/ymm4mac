import Foundation

/// 本家形式への変換拡張の置き場。
///
/// `Color` と `AnimationType` の本家文字列形式への変換を持つ。
/// 値型（`TimeSpanValue`／`PreservedObject`／`RenamedTypeResolver`）は
/// それぞれのファイルへ分離した。

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
