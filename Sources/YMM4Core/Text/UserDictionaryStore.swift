import Foundation

/// 辞書と版数の不変な組（書き出しジョブが開始時点で取得し、その
/// ジョブのテキスト描画へ渡すための値）。
public struct UserDictionarySnapshot: Sendable {
    public var dictionary: UserDictionary
    public var generation: Int

    public init(dictionary: UserDictionary, generation: Int) {
        self.dictionary = dictionary
        self.generation = generation
    }
}

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
///
/// 保存の責務分離（R18-03 / R18-04、D19-02）: `update` はメモリ上の
/// 辞書と版数を即時に差し替え、ディスクへの永続化だけを 0.3 秒の
/// 静穏期間で集約する（キー入力ごとの同期書き込みを避ける）。保存の
/// 成否は `lastSaveError` と `onSaveResult` で外へ伝え、失敗が成功と
/// 区別できない状態にしない。保存の実行経路は専用の直列キュー1本に
/// 統合されており、集約保存と明示的な保存確定が競合しても、古い
/// 辞書の書き込みが新しい辞書を後から上書きすることはない（保存は
/// 実行時点の最新状態を書く）。
///
/// 書き出し中の辞書の一貫性（R18-05、D19-01）: 書き出し側は開始時に
/// `snapshot()` で辞書と版数の不変な組を取得し、そのジョブの描画系
/// へ渡す。ストア自体は固定しないため、プレビューは常に最新の辞書
/// を読み、複数の書き出しジョブが重なっても各ジョブは自分の開始
/// 時点の辞書を使う。
public final class UserDictionaryStore: @unchecked Sendable {
    /// プロセス共有の保存先（本家の設定シングルトンと同じ形）。
    public static let shared = UserDictionaryStore()

    private let lock = NSLock()
    private var stored: UserDictionary
    private var storedGeneration: Int = 0
    private var storedLastSaveError: String?
    private var storedOnSaveResult: ((Bool) -> Void)?
    private let saveQueue = DispatchQueue(
        label: "jp.ymm4mac.user-dictionary-store.save"
    )
    private let saveQueueKey = DispatchSpecificKey<Void>()
    private var pendingSave: DispatchWorkItem?

    /// 保存結果の通知（成功 true）。編集画面が表示中に失敗を出す
    /// ために使う。保存キューから呼ばれることがある。
    public var onSaveResult: ((Bool) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedOnSaveResult
        }
        set {
            lock.lock()
            storedOnSaveResult = newValue
            lock.unlock()
        }
    }

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
        saveQueue.setSpecific(key: saveQueueKey, value: ())
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

    /// 現在の辞書と版数の不変な組（書き出しジョブ用）。
    public func snapshot() -> UserDictionarySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return UserDictionarySnapshot(
            dictionary: stored, generation: storedGeneration
        )
    }

    /// 直近の保存の失敗理由。成功していれば nil。
    public var lastSaveError: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedLastSaveError
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

    /// 辞書を差し替える。メモリ上の辞書と版数は即時に変わり、描画側
    /// のキャッシュは次回描画で新しい辞書を使う。永続化は静穏期間
    /// （0.3 秒）の後に集約して行う。
    public func update(_ dictionary: UserDictionary) {
        lock.lock()
        stored = dictionary
        storedGeneration += 1
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performSave()
        }
        pendingSave = work
        lock.unlock()
        saveQueue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// 保留中の永続化を即時に確定する（編集画面を閉じるとき・
    /// アプリ終了時）。
    public func flushPendingSave() {
        lock.lock()
        let pending = pendingSave
        pendingSave = nil
        lock.unlock()
        pending?.cancel()
        save()
    }

    /// 現在の辞書を保存ファイルへ同期的に書く。実行は保存専用の
    /// 直列キューへ統合されるため、集約保存と競合しない。
    ///
    /// - Returns: 保存できたら true。失敗したら false で、
    ///   `lastSaveError` に理由が残り、`onSaveResult` にも伝わる。
    ///   失敗してもメモリ上の辞書は保たれる（再試行で保存できる）。
    @discardableResult
    public func save() -> Bool {
        if DispatchQueue.getSpecific(key: saveQueueKey) != nil {
            return performSave()
        }
        return saveQueue.sync { performSave() }
    }

    /// 保存の実体。保存キュー上でのみ呼ぶこと。実行時点の最新の
    /// 辞書を書くため、直列化された順序どおりに最後の状態が残る。
    /// 書き込みは一時ファイル経由の原子的な置き換えで行う（本家の
    /// 非原子的な保存でファイルが壊れる欠陥は持ち込まない）。
    @discardableResult
    private func performSave() -> Bool {
        lock.lock()
        let text = stored.serializedJSON()
        lock.unlock()
        let directory = fileURL.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(
            "UserDictionary.json.tmp-\(UUID().uuidString)"
        )
        let succeeded: Bool
        var failureReason: String?
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try text.write(to: temporary, atomically: false, encoding: .utf8)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(
                    fileURL, withItemAt: temporary
                )
            } else {
                try FileManager.default.moveItem(at: temporary, to: fileURL)
            }
            succeeded = true
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            succeeded = false
            failureReason = error.localizedDescription
        }
        lock.lock()
        storedLastSaveError = failureReason
        let callback = storedOnSaveResult
        lock.unlock()
        callback?(succeeded)
        return succeeded
    }
}
