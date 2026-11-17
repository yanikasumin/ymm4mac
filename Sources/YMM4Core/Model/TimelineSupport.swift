import Foundation

/// レイヤーごとの設定。本家 `LayerSetting`（レコード）に対応する。
public struct LayerSetting: Equatable, Sendable {
    public var layer: Int
    public var label: String?
    public var color: Color
    public var isHidden: Bool
    public var volume: Double

    public init(
        layer: Int, label: String? = nil, color: Color = .transparent,
        isHidden: Bool = false, volume: Double = 100
    ) {
        self.layer = layer
        self.label = label
        self.color = color
        self.isHidden = isHidden
        self.volume = volume
    }

    func encodeToJSONValue() -> JSONValue {
        .object([
            (key: "Layer", value: .number(layer)),
            (key: "Label", value: label.map(JSONValue.string) ?? .null),
            (key: "Color", value: .string(color.honkeString)),
            (key: "IsHidden", value: .bool(isHidden)),
            (key: "Volume", value: .number(volume)),
        ])
    }

    static func decode(from value: JSONValue) -> LayerSetting? {
        guard value.objectFields != nil else { return nil }
        var setting = LayerSetting(layer: 0)
        setting.layer = CodecSupport.int(value.field("Layer"), default: 0)
        if let labelValue = value.field("Label"), labelValue != .null {
            setting.label = labelValue.stringValue
        }
        setting.color = CodecSupport.color(value.field("Color"), default: .transparent)
        setting.isHidden = CodecSupport.bool(value.field("IsHidden"), default: false)
        setting.volume = CodecSupport.double(value.field("Volume"), default: 100)
        return setting
    }
}

/// レイヤー設定の集合。本家 `LayerSettings` に対応する。
///
/// 保存されるのは `Items` のみ。挿入は本家 `Insert` の意味論どおり、
/// 指定レイヤー以上の既存設定を1つずつ後ろへずらしてから末尾へ追加する。
public final class LayerSettings {
    public var items: [LayerSetting] = []

    public init() {}

    /// 指定レイヤーの設定（無ければ既定値で新規作成したもの）。
    public func setting(forLayer layer: Int) -> LayerSetting {
        items.first(where: { $0.layer == layer }) ?? LayerSetting(layer: layer)
    }

    /// 本家 `Insert`。指定レイヤー以上の設定を後ろへずらし、末尾へ追加する。
    public func insert(_ setting: LayerSetting) {
        var result = items.filter { $0.layer < setting.layer }
        result += items.filter { $0.layer >= setting.layer }.map { existing in
            var shifted = existing
            shifted.layer += 1
            return shifted
        }
        result.append(setting)
        items = result
    }

    func encodeToJSONValue() -> JSONValue {
        .object([
            (key: "Items", value: .array(items.map { $0.encodeToJSONValue() })),
        ])
    }

    static func decode(from value: JSONValue) -> LayerSettings {
        let settings = LayerSettings()
        if let elements = value.field("Items")?.arrayValue {
            settings.items = elements.compactMap { LayerSetting.decode(from: $0) }
        }
        return settings
    }
}

/// タイムラインの補助線設定。本家 `TimelineVerticalLine` に対応する。
///
/// 線そのもの（`Line`）はインタフェース型のため生 JSON で保持する。
/// `LineType` を変えると線は種類ごとの既定インスタンスへ差し替わる
/// （本家の setter の挙動）。
public struct TimelineVerticalLine: Sendable {
    /// 補助線が有効か。
    public var isEnabled: Bool = false
    /// 開始フレーム。
    public var startFrame: Int = 0
    /// 線（$type を含む生 JSON）。
    public var line: PreservedObject = TimelineVerticalLine.defaultLine(for: .bpm)
    /// グループ番号（本家の既定は 4）。
    public var group: Int = 4
    /// モデル化していないプロパティの保存先。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    /// 線の種類。現在の `Line` の $type から判定する。
    public var lineType: VerticalLineType {
        get {
            guard let typeName = line.typeName else { return .bpm }
            if typeName.hasPrefix("YukkuriMovieMaker.Project.VerticalFrameLine") { return .frame }
            if typeName.hasPrefix("YukkuriMovieMaker.Project.VerticalTimeLine") { return .time }
            return .bpm
        }
        set {
            line = Self.defaultLine(for: newValue)
        }
    }

    /// 種類ごとの既定の線（本家の各クラスのフィールド初期値どおり）。
    public static func defaultLine(for type: VerticalLineType) -> PreservedObject {
        let assembly = "YukkuriMovieMaker.Plugin"
        switch type {
        case .frame:
            return PreservedObject(.object([
                (key: "$type", value: .string("YukkuriMovieMaker.Project.VerticalFrameLine, \(assembly)")),
                (key: "Frame", value: .number(30)),
            ]))
        case .time:
            return PreservedObject(.object([
                (key: "$type", value: .string("YukkuriMovieMaker.Project.VerticalTimeLine, \(assembly)")),
                (key: "Span", value: .string("00:00:00.5000000")),
            ]))
        default:
            return PreservedObject(.object([
                (key: "$type", value: .string("YukkuriMovieMaker.Project.VerticalBPMLine, \(assembly)")),
                (key: "BPM", value: .number(100.0)),
            ]))
        }
    }

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "IsEnabled", value: .bool(isEnabled)),
            (key: "StartFrame", value: .number(startFrame)),
            (key: "LineType", value: .string(lineType.honkeName)),
            (key: "Line", value: line.value),
            (key: "Group", value: .number(group)),
        ]
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> TimelineVerticalLine {
        var verticalLine = TimelineVerticalLine()
        guard let fields = value.objectFields else { return verticalLine }
        for (key, fieldValue) in fields {
            switch key {
            case "IsEnabled":
                verticalLine.isEnabled = CodecSupport.bool(fieldValue, default: false)
            case "StartFrame":
                verticalLine.startFrame = CodecSupport.int(fieldValue, default: 0)
            case "LineType":
                // 本家の setter は線を既定インスタンスへ差し替える。
                // 続く Line キーが実際の線で上書きする（本家の復元順と同じ）。
                if let name = fieldValue.stringValue {
                    verticalLine.lineType = VerticalLineType(honkeName: name)
                }
            case "Line":
                if let preserved = CodecSupport.preservedObject(fieldValue) {
                    verticalLine.line = preserved
                }
            case "Group":
                verticalLine.group = CodecSupport.int(fieldValue, default: 4)
            default:
                verticalLine.additionalFields.append((key: key, value: fieldValue))
            }
        }
        return verticalLine
    }
}

/// ツールの保存状態。本家 `SerializableToolState`（レコード）に対応する。
public struct SerializableToolState: Equatable, Sendable {
    public var title: String
    public var savedState: String?

    public init(title: String, savedState: String? = nil) {
        self.title = title
        self.savedState = savedState
    }

    func encodeToJSONValue() -> JSONValue {
        .object([
            (key: "Title", value: .string(title)),
            (key: "SavedState", value: savedState.map(JSONValue.string) ?? .null),
        ])
    }

    static func decode(from value: JSONValue) -> SerializableToolState? {
        guard value.objectFields != nil else { return nil }
        var state = SerializableToolState(title: "")
        state.title = CodecSupport.string(value.field("Title"), default: "")
        if let savedValue = value.field("SavedState"), savedValue != .null {
            state.savedState = savedValue.stringValue
        }
        return state
    }
}
