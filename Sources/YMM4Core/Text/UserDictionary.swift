import Foundation

/// ユーザー辞書。本家 `UserDictionary`（設定シングルトン）に対応する。
///
/// 3種類の置換リストを持つ:
/// - `asteriskWordSets`: 表示テキストへの置換（伏せ字等。描画の前処理で適用）
/// - `wordSets`: 読み変換の前段で適用する読み替え
/// - `pronouncingSets`: 読み変換の後段で適用する発音調整
///
/// 本家ではプロジェクトファイルではなくアプリ設定として、設定ディレクトリ
/// 配下の `UserDictionary` 用 JSON ファイルに保存される。JSON のキー名は
/// 本家の保存形式（プロパティ名そのまま）に合わせる。
public struct UserDictionary: Equatable, Sendable {
    public var asteriskWordSets: [WordSet]
    public var wordSets: [WordSet]
    public var pronouncingSets: [WordSet]

    /// 本家の既定内容（初期状態）。
    public static let `default` = UserDictionary()

    public init() {
        asteriskWordSets = Self.defaultAsteriskWordSets
        wordSets = Self.defaultWordSets
        pronouncingSets = Self.defaultPronouncingSets
    }

    public init(
        asteriskWordSets: [WordSet], wordSets: [WordSet],
        pronouncingSets: [WordSet]
    ) {
        self.asteriskWordSets = asteriskWordSets
        self.wordSets = wordSets
        self.pronouncingSets = pronouncingSets
    }

    // MARK: - 本家設定 JSON との往復

    public func encodeToJSONValue() -> JSONValue {
        .object([
            (key: "AsteriskWordSets", value: .array(asteriskWordSets.map { $0.encodeToJSONValue() })),
            (key: "WordSets", value: .array(wordSets.map { $0.encodeToJSONValue() })),
            (key: "PronouncingSets", value: .array(pronouncingSets.map { $0.encodeToJSONValue() })),
        ])
    }

    /// 設定 JSON から復元する。欠けているリストは本家どおり既定値で補う
    /// （本家 `Initialize` は null のリストへ既定値を入れる）。
    public static func decode(from value: JSONValue) -> UserDictionary {
        var dictionary = UserDictionary()
        if let elements = value.field("AsteriskWordSets")?.arrayValue {
            dictionary.asteriskWordSets = elements.compactMap { WordSet.decode(from: $0) }
        }
        if let elements = value.field("WordSets")?.arrayValue {
            dictionary.wordSets = elements.compactMap { WordSet.decode(from: $0) }
        }
        if let elements = value.field("PronouncingSets")?.arrayValue {
            dictionary.pronouncingSets = elements.compactMap { WordSet.decode(from: $0) }
        }
        return dictionary
    }

    public func serializedJSON() -> String {
        encodeToJSONValue().serialized()
    }

    public static func parse(json: String) -> UserDictionary? {
        var parser = JSONParser(text: json)
        guard let value = try? parser.parse() else { return nil }
        return decode(from: value)
    }
}

extension WordSet {
    func encodeToJSONValue() -> JSONValue {
        .object([
            (key: "IsEnabled", value: .bool(isEnabled)),
            (key: "From", value: .string(from)),
            (key: "To", value: .string(to)),
            (key: "IsRegex", value: .bool(isRegex)),
            (key: "IgnoreCase", value: .bool(ignoreCase)),
            (key: "Description", value: description.map(JSONValue.string) ?? .null),
        ])
    }

    static func decode(from value: JSONValue) -> WordSet? {
        guard value.objectFields != nil else { return nil }
        return WordSet(
            from: CodecSupport.string(value.field("From"), default: ""),
            to: CodecSupport.string(value.field("To"), default: ""),
            description: value.field("Description")?.stringValue,
            isRegex: CodecSupport.bool(value.field("IsRegex"), default: false),
            ignoreCase: CodecSupport.bool(value.field("IgnoreCase"), default: true),
            isEnabled: CodecSupport.bool(value.field("IsEnabled"), default: true)
        )
    }
}
