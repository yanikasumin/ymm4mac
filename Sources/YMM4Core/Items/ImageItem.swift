import Foundation

/// 画像アイテム。本家 `ImageItem` に対応する。
public final class ImageItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.ImageItem, YukkuriMovieMaker"
    }

    /// ファイルパス（未指定は空文字列）。
    public var filePath: String? = ""

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "FilePath", value: filePath.map(JSONValue.string) ?? .null),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "FilePath":
            filePath = value == .null ? nil : CodecSupport.string(value, default: filePath ?? "")
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }
}
