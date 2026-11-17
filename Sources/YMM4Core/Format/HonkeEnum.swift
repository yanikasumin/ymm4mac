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
