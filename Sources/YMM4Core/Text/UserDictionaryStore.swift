import Foundation

/// ユーザー辞書の設定層（TEXT60 の設定層。本家 `UserDictionary` の
/// 設定シングルトンとしての側面に対応する）。
///
/// 本家は辞書をプロジェクトファイルではなくアプリ設定として、設定
/// ディレクトリ配下の JSON ファイルへ保存する。Mac 版では保存先を
/// アプリバンドルの外（Application Support 配下の `YMM4Mac`
/// フォルダ、`UserDictionary.json`）に置く。ファイルが無い・壊れて
/// いる場合は本家の初期状態（既定辞書）で起動し、読み込み失敗で
/// アプリを止めない。
///
/// `generation` は辞書の版数で、編集のたびに増える。描画側
/// （MetalTextSources のキャッシュキー）がこれを見て、辞書変更後の
/// 再ラスタライズを判断する。
public final class UserDictionaryStore: @unchecked Sendable {
    /// プロセス共有の保存先（本家の設定シングルトンと同じ形）。
    public static let shared = UserDictionaryStore()

    private let lock = NSLock()
    private var stored: UserDictionary
    private var storedGeneration: Int = 0

    /// 保存ファイルの URL。テスト等では差し替えられる。
    public let fileURL: URL

    /// 既定の保存先: Application Support/YMM4Mac/UserDictionary.json。
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("YMM4Mac", isDirectory: true)
            .appendingPathComponent("UserDictionary.json")
    }

    public init(fileURL: URL = UserDictionaryStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.stored = UserDictionary()
    }

    /// 現在の辞書。
    public var current: UserDictionary {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    /// 辞書の版数（起動直後は 0、編集ごとに +1）。
    public var generation: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedGeneration
    }

    /// 保存ファイルから読み込む。無い・壊れている場合は既定辞書の
    /// まま（本家の初期化と同じく、欠けたリストは既定で補われる）。
    public func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8),
              let parsed = UserDictionary.parse(json: text) else {
            return
        }
        lock.lock()
        stored = parsed
        storedGeneration += 1
        lock.unlock()
    }

    /// 辞書を差し替えて保存する。版数が増え、描画側のキャッシュは
    /// 次回描画で新しい辞書を使う。
    public func update(_ dictionary: UserDictionary) {
        lock.lock()
        stored = dictionary
        storedGeneration += 1
        lock.unlock()
        save()
    }

    /// 現在の辞書を保存ファイルへ書く。書き込みは一時ファイル経由の
    /// 原子的な置き換えで行う（本家の非原子的な保存でファイルが壊れる
    /// 欠陥は持ち込まない）。失敗しても例外にせず、現在の辞書は
    /// メモリ上に保たれる。
    public func save() {
        let text = current.serializedJSON()
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let temporary = directory.appendingPathComponent(
            "UserDictionary.json.tmp-\(UUID().uuidString)"
        )
        do {
            try text.write(to: temporary, atomically: false, encoding: .utf8)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: fileURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
        }
    }
}
