import Foundation

/// .ymmp 互換層の内部共通処理。
///
/// 各モデル型のデコード／エンコードが共有する、プリミティブ値と
/// 保存オブジェクトの取り出しを持つ。`Animation` の JSON 形状の変換は
/// AnimationCodecSupport.swift の拡張が持つ。
enum CodecSupport {
    // MARK: - プリミティブ値の取り出し

    static func int(_ value: JSONValue?, default defaultValue: Int) -> Int {
        value?.intValue ?? defaultValue
    }

    static func double(_ value: JSONValue?, default defaultValue: Double) -> Double {
        value?.doubleValue ?? defaultValue
    }

    static func bool(_ value: JSONValue?, default defaultValue: Bool) -> Bool {
        value?.boolValue ?? defaultValue
    }

    static func string(_ value: JSONValue?, default defaultValue: String) -> String {
        value?.stringValue ?? defaultValue
    }

    static func timeSpan(_ value: JSONValue?, default defaultValue: TimeSpanValue) -> TimeSpanValue {
        guard let text = value?.stringValue, let parsed = TimeSpanValue(honkeString: text) else {
            return defaultValue
        }
        return parsed
    }

    static func color(_ value: JSONValue?, default defaultValue: Color) -> Color {
        guard let text = value?.stringValue, let parsed = Color(honkeString: text) else {
            return defaultValue
        }
        return parsed
    }

    static func enumeration<T: HonkeEnum>(_ value: JSONValue?, default defaultValue: T) -> T {
        guard let name = value?.stringValue else { return defaultValue }
        return T(honkeName: name)
    }

    static func uuid(_ value: JSONValue?, default defaultValue: UUID) -> UUID {
        guard let text = value?.stringValue, let parsed = UUID(uuidString: text) else {
            return defaultValue
        }
        return parsed
    }

    // MARK: - 保存オブジェクト（エフェクト等の生保持）

    /// インタフェース型の値を生 JSON として取り出す。null は nil。
    /// 本家の型移行（RenamedTypeResolver）を $type へ適用する。
    static func preservedObject(_ value: JSONValue?) -> PreservedObject? {
        guard let value, value != .null else { return nil }
        return PreservedObject(value).applyingTypeMigration()
    }

    /// インタフェース型の配列を生 JSON のまま取り出す。
    static func preservedList(_ value: JSONValue?) -> [PreservedObject] {
        guard let elements = value?.arrayValue else { return [] }
        return elements.map { PreservedObject($0).applyingTypeMigration() }
    }
}
