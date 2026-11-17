import Foundation

/// 未知の $type で読み飛ばされたアイテムの記録。
public struct YmmpSkippedItem: Sendable {
    /// タイムラインのインデックス（旧形式の単一 Timeline は -1）。
    public var timelineIndex: Int
    /// タイムライン内での要素インデックス。
    public var itemIndex: Int
    /// 解決できなかった $type（$type 自体が無い場合は nil）。
    public var typeName: String?

    public init(timelineIndex: Int, itemIndex: Int, typeName: String?) {
        self.timelineIndex = timelineIndex
        self.itemIndex = itemIndex
        self.typeName = typeName
    }
}

/// .ymmp 読み込み時の診断情報。
///
/// 本家は $type の解決エラーを握り潰して読み飛ばす。ここでも同じ挙動に
/// しつつ、何が読み飛ばされたか・どの型名が移行されたかを呼び出し側が
/// 取得できる形で返す。
public struct YmmpLoadDiagnostics: Sendable {
    /// 未知の $type で読み飛ばされたアイテム。
    public var skippedItems: [YmmpSkippedItem] = []
    /// アイテムの $type について RenamedTypeResolver で移行された型名
    /// （移行前 → 移行後）。エフェクト等の入れ子オブジェクトの移行は
    /// 保持オブジェクト側で適用されるが、ここには記録されない。
    public var migratedTypeNames: [(from: String, to: String)] = []

    public init() {}
}

/// .ymmp 互換層のエラー。
public enum YmmpError: Error, Sendable, Equatable {
    /// JSON として不正。
    case invalidJSON(String)
    /// ルートがオブジェクトでない。
    case rootNotObject
    /// YMM3 の XML 形式（本形式では扱わない）。
    case legacyXMLFormat
    /// 保存時の再読込検証に失敗した。
    case verificationFailed(String)
}

/// .ymmp の読み込み・保存。本家 `YukkuriMovieMaker.Json.Json` に対応する。
///
/// 設定は本家どおり: TypeNameHandling.Auto、Simple アセンブリ形式、
/// StringEnumConverter、SerializationBinder = RenamedTypeResolver、
/// UTF-8、改行なしの1行 JSON。保存は「一時ファイルへ書き出し →
/// 再読込して検証 → 本ファイルへコピー」という本家の手順を踏む。
public enum YmmpCodec {
    // MARK: - 読み込み

    /// JSON テキストからプロジェクトを読み込む。
    public static func decode(_ text: String) throws -> (project: Project, diagnostics: YmmpLoadDiagnostics) {
        let trimmed = text.drop(while: { $0 == "\u{FEFF}" || $0.isWhitespace })
        if trimmed.hasPrefix("<") {
            throw YmmpError.legacyXMLFormat
        }
        var parser = JSONParser(text: String(trimmed))
        let root: JSONValue
        do {
            root = try parser.parse()
        } catch let error as JSONParseError {
            throw YmmpError.invalidJSON("\(error.message) (offset \(error.offset))")
        }
        guard let fields = root.objectFields else {
            throw YmmpError.rootNotObject
        }
        var diagnostics = YmmpLoadDiagnostics()
        let project = Project()
        var legacyTimeline: Timeline?
        for (key, value) in fields {
            switch key {
            case "FilePath":
                project.filePath = value == .null ? nil : value.stringValue
            case "SelectedTimelineIndex":
                project.selectedTimelineIndex = CodecSupport.int(value, default: 0)
            case "Timelines":
                if let elements = value.arrayValue {
                    for (index, element) in elements.enumerated() {
                        if let timeline = decodeTimeline(element, timelineIndex: index, diagnostics: &diagnostics) {
                            project.timelines.append(timeline)
                        }
                    }
                }
            case "Characters":
                if let elements = value.arrayValue {
                    project.characters = elements.compactMap { Character.decode(from: $0) }
                }
            case "CollapsedGroups":
                if let elements = value.arrayValue {
                    project.collapsedGroups = elements.compactMap { $0.stringValue }
                }
            case "LayoutXml":
                project.layoutXml = CodecSupport.string(value, default: "")
            case "ToolStates":
                if value == .null {
                    project.toolStates = nil
                } else if let stateFields = value.objectFields {
                    var states: [(key: String, value: SerializableToolState)] = []
                    var allDecoded = true
                    for (stateKey, stateValue) in stateFields {
                        if let state = SerializableToolState.decode(from: stateValue) {
                            states.append((key: stateKey, value: state))
                        } else {
                            allDecoded = false
                            break
                        }
                    }
                    if allDecoded {
                        project.toolStates = states
                    } else {
                        // 復元できない要素がある場合は丸ごと追加フィールドで保持する
                        project.additionalFields.append((key: key, value: value))
                    }
                }
            case "Timeline":
                // 旧 API（読み込み専用）
                legacyTimeline = decodeTimeline(value, timelineIndex: -1, diagnostics: &diagnostics)
            default:
                project.additionalFields.append((key: key, value: value))
            }
        }
        project.loadOldTimeline(legacyTimeline: legacyTimeline)
        resolveCharacterReferences(in: project)
        return (project, diagnostics)
    }

    /// キャラクター参照の解決。本家では VoiceItem / TachieItem /
    /// TachieFaceItem の `Character` は [JsonIgnore] の実行時参照であり、
    /// 保存されるのは `CharacterName` だけである（VoiceItem.cs の
    /// Character プロパティが [JsonIgnore]、CharacterName だけが保存対象）。
    /// そのため本家ファイルのアイテムには "Character" オブジェクトが
    /// 存在せず、デコード直後は参照が未解決のままになる。読み込みの
    /// 最後に、プロジェクトのキャラクター一覧から名前で引いて参照を
    /// 張り直す（MAC-0014 のレビュー制約）。名前が一致するキャラクターが
    /// 無い場合は、デコード済みの参照（移行期の自前ファイルが埋め込む
    /// 複製）をそのまま残す。
    private static func resolveCharacterReferences(in project: Project) {
        guard !project.characters.isEmpty else { return }
        func resolve(_ characterName: String) -> Character? {
            guard !characterName.isEmpty else { return nil }
            return project.characters.first { $0.name == characterName }
        }
        for timeline in project.timelines {
            for item in timeline.items {
                switch item {
                case let voice as VoiceItem:
                    if let resolved = resolve(voice.characterName) {
                        voice.character = resolved
                    }
                case let tachie as TachieItem:
                    if let resolved = resolve(tachie.characterName) {
                        tachie.character = resolved
                    }
                case let face as TachieFaceItem:
                    if let resolved = resolve(face.characterName) {
                        face.character = resolved
                    }
                default:
                    break
                }
            }
        }
    }

    /// ファイルからプロジェクトを読み込む。
    ///
    /// 本家（StreamReader + Newtonsoft）は BOM から文字コードを判定する
    /// ため、UTF-16（LE / BE）の BOM があればそちらで復号する。
    /// 既定は UTF-8（BOM の除去は decode 側で行う）。
    public static func load(fromFile path: String) throws -> (project: Project, diagnostics: YmmpLoadDiagnostics) {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let bytes = [UInt8](data.prefix(2))
        if bytes == [0xFF, 0xFE] || bytes == [0xFE, 0xFF],
           let text = String(data: data, encoding: .utf16) {
            return try decode(text)
        }
        return try decode(String(decoding: data, as: UTF8.self))
    }

    // MARK: - 保存

    /// プロジェクトを JSON テキスト（1行）へ書き出す。
    public static func encode(_ project: Project) -> String {
        encodeProject(project).serialized()
    }

    /// 本家の保存手順でファイルへ保存する。
    ///
    /// 一時ファイルへ書き出し、再読込して検証できたら本ファイルへ
    /// コピーする（ディレクトリが無ければ作る）。
    public static func save(_ project: Project, toFile path: String) throws {
        let text = encode(project)
        let fileManager = FileManager.default
        let temporaryPath = fileManager.temporaryDirectory
            .appendingPathComponent("ymm4mac-\(UUID().uuidString).ymmp").path
        try text.write(toFile: temporaryPath, atomically: false, encoding: .utf8)
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: temporaryPath))
            _ = try decode(String(decoding: data, as: UTF8.self))
        } catch {
            try? fileManager.removeItem(atPath: temporaryPath)
            throw YmmpError.verificationFailed("\(error)")
        }
        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
        try fileManager.copyItem(atPath: temporaryPath, toPath: path)
        try? fileManager.removeItem(atPath: temporaryPath)
    }

    // MARK: - プロジェクト／タイムラインの変換

    static func encodeProject(_ project: Project) -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "FilePath", value: project.filePath.map(JSONValue.string) ?? .null),
            (key: "SelectedTimelineIndex", value: .number(project.selectedTimelineIndex)),
            (key: "Timelines", value: .array(project.timelines.map { encodeTimeline($0) })),
            (key: "Characters", value: .array(project.characters.map { $0.encodeToJSONValue() })),
            (key: "CollapsedGroups", value: .array(project.collapsedGroups.map { .string($0) })),
            (key: "LayoutXml", value: .string(project.layoutXml)),
            (key: "ToolStates", value: project.toolStates.map { states in
                .object(states.map { (key: $0.key, value: $0.value.encodeToJSONValue()) })
            } ?? .null),
        ]
        fields += project.additionalFields
        return .object(fields)
    }

    static func encodeTimeline(_ timeline: Timeline) -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "ID", value: .string(timeline.id.uuidString.lowercased())),
            (key: "Name", value: .string(timeline.name)),
            (key: "VideoInfo", value: encodeVideoInfo(timeline.videoInfo)),
            (key: "VerticalLine", value: timeline.verticalLine.encodeToJSONValue()),
            (key: "Items", value: .array(timeline.items.map { encodeItem($0) })),
            (key: "LayerSettings", value: timeline.layerSettings.encodeToJSONValue()),
            (key: "CurrentFrame", value: .number(timeline.currentFrame)),
            (key: "Length", value: .number(timeline.length)),
            (key: "MaxLayer", value: .number(timeline.maxLayer)),
        ]
        fields += timeline.additionalFields
        return .object(fields)
    }

    static func decodeTimeline(
        _ value: JSONValue, timelineIndex: Int, diagnostics: inout YmmpLoadDiagnostics
    ) -> Timeline? {
        guard let fields = value.objectFields else { return nil }
        let timeline = Timeline()
        var restoredLength: Int?
        var restoredMaxLayer: Int?
        for (key, fieldValue) in fields {
            switch key {
            case "ID":
                timeline.id = CodecSupport.uuid(fieldValue, default: timeline.id)
            case "Name":
                timeline.name = CodecSupport.string(fieldValue, default: timeline.name)
            case "VideoInfo":
                timeline.videoInfo = decodeVideoInfo(fieldValue)
            case "VerticalLine":
                timeline.verticalLine = TimelineVerticalLine.decode(from: fieldValue)
            case "Items":
                if let elements = fieldValue.arrayValue {
                    for (index, element) in elements.enumerated() {
                        if let item = decodeItem(
                            element, timelineIndex: timelineIndex, itemIndex: index,
                            diagnostics: &diagnostics
                        ) {
                            timeline.items.append(item)
                        }
                    }
                }
            case "LayerSettings":
                timeline.layerSettings = LayerSettings.decode(from: fieldValue)
            case "CurrentFrame":
                timeline.currentFrame = CodecSupport.int(fieldValue, default: 0)
            case "Length":
                restoredLength = fieldValue.intValue
            case "MaxLayer":
                restoredMaxLayer = fieldValue.intValue
            default:
                timeline.additionalFields.append((key: key, value: fieldValue))
            }
        }
        // 本家は private setter 経由でキャッシュも復元する。キーが無い
        // 場合は現在のアイテム集合から再計算した値を使う。
        timeline.restoreCachedLength(
            restoredLength ?? timeline.computeCurrentLength(),
            maxLayer: restoredMaxLayer ?? timeline.computeCurrentMaxLayer()
        )
        // タイムラインへ配置されたアイテムには VideoInfo の FPS が注入される
        for item in timeline.items {
            item.setFPS(timeline.videoInfo.fps)
        }
        return timeline
    }

    static func encodeVideoInfo(_ videoInfo: VideoInfo) -> JSONValue {
        .object([
            (key: "FPS", value: .number(videoInfo.fps)),
            (key: "Hz", value: .number(videoInfo.hz)),
            (key: "Width", value: .number(videoInfo.width)),
            (key: "Height", value: .number(videoInfo.height)),
            (key: "BackgroundColor", value: .string(videoInfo.backgroundColor.honkeString)),
        ])
    }

    static func decodeVideoInfo(_ value: JSONValue) -> VideoInfo {
        var videoInfo = VideoInfo()
        videoInfo.fps = CodecSupport.int(value.field("FPS"), default: videoInfo.fps)
        videoInfo.hz = CodecSupport.int(value.field("Hz"), default: videoInfo.hz)
        videoInfo.width = CodecSupport.int(value.field("Width"), default: videoInfo.width)
        videoInfo.height = CodecSupport.int(value.field("Height"), default: videoInfo.height)
        videoInfo.backgroundColor = CodecSupport.color(
            value.field("BackgroundColor"), default: videoInfo.backgroundColor
        )
        return videoInfo
    }

    // MARK: - アイテムの変換

    /// $type 名からアイテムを生成する（本家の13クラス）。
    static func createItem(typeName: String) -> BaseItem? {
        switch typeName {
        case AudioItem.typeName: return AudioItem()
        case VideoItem.typeName: return VideoItem()
        case VoiceItem.typeName: return VoiceItem()
        case TextItem.typeName: return TextItem()
        case ImageItem.typeName: return ImageItem()
        case ShapeItem.typeName: return ShapeItem()
        case EffectItem.typeName: return EffectItem()
        case GroupItem.typeName: return GroupItem()
        case SceneItem.typeName: return SceneItem()
        case FrameBufferItem.typeName: return FrameBufferItem()
        case TachieItem.typeName: return TachieItem()
        case TachieFaceItem.typeName: return TachieFaceItem()
        case TransitionItem.typeName: return TransitionItem()
        default: return nil
        }
    }

    static func encodeItem(_ item: BaseItem) -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "$type", value: .string(type(of: item).typeName)),
        ]
        fields += item.encodeKnownFields()
        fields += item.additionalFields
        return .object(fields)
    }

    /// アイテムを読み込む。未知の $type は本家同様に握り潰して読み飛ばし、
    /// 診断情報へ記録する。
    static func decodeItem(
        _ value: JSONValue, timelineIndex: Int, itemIndex: Int,
        diagnostics: inout YmmpLoadDiagnostics
    ) -> BaseItem? {
        guard let fields = value.objectFields else {
            diagnostics.skippedItems.append(
                YmmpSkippedItem(timelineIndex: timelineIndex, itemIndex: itemIndex, typeName: nil)
            )
            return nil
        }
        let typeName = value.field("$type")?.stringValue
        guard let typeName else {
            diagnostics.skippedItems.append(
                YmmpSkippedItem(timelineIndex: timelineIndex, itemIndex: itemIndex, typeName: nil)
            )
            return nil
        }
        let resolved = RenamedTypeResolver.resolveTypeName(typeName)
        if resolved != typeName {
            diagnostics.migratedTypeNames.append((from: typeName, to: resolved))
        }
        guard let item = createItem(typeName: resolved) else {
            diagnostics.skippedItems.append(
                YmmpSkippedItem(timelineIndex: timelineIndex, itemIndex: itemIndex, typeName: typeName)
            )
            return nil
        }
        for (key, fieldValue) in fields where key != "$type" {
            if !item.decodeKnownField(key, fieldValue) {
                item.additionalFields.append((key: key, value: fieldValue))
            }
        }
        item.refreshAnimationContext()
        return item
    }
}

public extension BaseItem {
    /// JSON 往復による複製。本家 `GetClone`（複製後に FPS を再注入する）。
    func cloned() -> BaseItem {
        var diagnostics = YmmpLoadDiagnostics()
        guard let copy = YmmpCodec.decodeItem(
            YmmpCodec.encodeItem(self), timelineIndex: -1, itemIndex: -1,
            diagnostics: &diagnostics
        ) else {
            fatalError("自前で書き出したアイテムを読み戻せませんでした")
        }
        copy.setFPS(videoFPS)
        return copy
    }
}
