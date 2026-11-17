import Foundation

/// 意味論をモデル化しない型付きオブジェクトの保存表現。
///
/// エフェクトやプラグイン固有パラメータなど、インタフェース型で保持される
/// 値は $type 名を含む生 JSON をそのまま保持し、保存時に書き戻す。
/// 読み込み時には本家同様に `RenamedTypeResolver` の移行を $type へ適用する
/// （本家は移行先の型として読み込むため、再保存時は移行先の名前になる）。
public struct PreservedObject: Equatable, Sendable {
    /// 生 JSON（通常は $type を含むオブジェクト）。
    public var value: JSONValue

    public init(_ value: JSONValue) {
        self.value = value
    }

    /// $type の値（無ければ nil）。
    public var typeName: String? {
        value.field("$type")?.stringValue
    }

    /// 本家の型移行を $type へ適用した複製を返す。
    public func applyingTypeMigration() -> PreservedObject {
        guard let typeName,
              case .object(var fields) = value else {
            return self
        }
        let resolved = RenamedTypeResolver.resolveTypeName(typeName)
        guard resolved != typeName else { return self }
        for index in fields.indices where fields[index].key == "$type" {
            fields[index].value = .string(resolved)
        }
        return PreservedObject(.object(fields))
    }
}
