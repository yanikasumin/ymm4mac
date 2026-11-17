import Foundation

/// 色（ARGB 各 8bit）。
///
/// 本家は WPF の `Color` をモデルの値として使う。ここではモデル層が必要とする
/// 最小限の値型として再現する。シリアライズ形式の詳細は互換層の仕様確定後に合わせる。
public struct Color: Equatable, Sendable {
    public var alpha: UInt8
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(alpha: UInt8, red: UInt8, green: UInt8, blue: UInt8) {
        self.alpha = alpha
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// 透明色。本家の `Colors.Transparent`（#00FFFFFF）に一致する。
    public static let transparent = Color(alpha: 0, red: 255, green: 255, blue: 255)
}
