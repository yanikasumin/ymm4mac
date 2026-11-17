import Foundation

/// フレームバッファアイテム。本家 `FrameBufferItem` に対応する。
public final class FrameBufferItem: VisualItem {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Items.FrameBufferItem, YukkuriMovieMaker"
    }

    /// 背景をクリアするか。
    public var clearBackground: Bool = false
    /// アルファを有効にするか。
    public var isAlphaEnabled: Bool = false
    /// フレーム外の描画を有効にするか。
    public var isFrameOutImageRenderingEnabled: Bool = false

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "ClearBackground", value: .bool(clearBackground)),
            (key: "IsAlphaEnabled", value: .bool(isAlphaEnabled)),
            (key: "IsFrameOutImageRenderingEnabled", value: .bool(isFrameOutImageRenderingEnabled)),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "ClearBackground":
            clearBackground = CodecSupport.bool(value, default: clearBackground)
        case "IsAlphaEnabled":
            isAlphaEnabled = CodecSupport.bool(value, default: isAlphaEnabled)
        case "IsFrameOutImageRenderingEnabled":
            isFrameOutImageRenderingEnabled = CodecSupport.bool(value, default: isFrameOutImageRenderingEnabled)
        default:
            return super.decodeKnownField(key, value)
        }
        return true
    }
}
