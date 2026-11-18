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
///
/// 保存の責務分離（R18-03 / R18-04）: `update` はメモリ上の辞書と
/// 版数を即時に差し替え、ディスクへの永続化だけを 0.3 秒の静穏期間
/// で集約する（キー入力ごとの同期書き込みを避ける）。保存の成否は
/// `lastSaveError` と `onSaveResult` で外へ伝え、失敗が成功と区別
/// できない状態にしない。`save()` は同期保存（確定用）。
///
/// 書き出し中の固定（R18-05）: `pin()` の間、`current` と
/// `generation` は固定時点の辞書と版数を返し続ける。書き出し側が
/// 開始時に固定することで、長時間の書き出し中に辞書を編集しても
/// 出力の前半と後半で辞書が変わらない。固定中にプレビュー側が
/// 辞書を読む場合も固定された辞書になる（書き出し中は編集結果の
/// 反映が書き出し終了まで遅れる、という割り切り）。
public final class UserDictionaryStore: @unchecked Sendable {
    /// プロセス共有の保存先（本家の設定シングルトンと同じ形）。
    public static let shared = UserDictionaryStore()

    private let lock = NSLock()
    private var stored: UserDictionary
    private var storedGeneration: Int = 0
    private var pinned: (dictionary: UserDictionary, generation: Int)?
    private var pinCount = 0
    private var storedLastSaveError: String?
    private let saveQueue = DispatchQueue(
        label: "jp.ymm4mac.user-dictionary-store.save"
    )
    private var pendingSave: DispatchWorkItem?

    /// 保存結果の通知（成功 true）。編集画面が表示中に失敗を出す
    /// ために使う。メインスレッド以外から呼ばれることがある。
    public var onSaveResult: ((Bool) -> Void)?

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

    /// 現在の辞書。固定中は固定時点の辞書。
    public var current: UserDictionary {
        lock.lock()
        defer { lock.unlock() }
        return pinned?.dictionary ?? stored
    }

    /// 辞書の版数（起動直後は 0、編集ごとに +1）。固定中は固定時点
    /// の版数。
    public var generation: Int {
        lock.lock()
        defer { lock.unlock() }
        return pinned?.generation ?? storedGeneration
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
            self?.save()
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

    /// 現在の辞書を保存ファイルへ同期的に書く。書き込みは一時
    /// ファイル経由の原子的な置き換えで行う（本家の非原子的な保存で
    /// ファイルが壊れる欠陥は持ち込まない）。
    ///
    /// - Returns: 保存できたら true。失敗したら false で、
    ///   `lastSaveError` に理由が残り、`onSaveResult` にも伝わる。
    ///   失敗してもメモリ上の辞書は保たれる（再試行で保存できる）。
    @discardableResult
    public func save() -> Bool {
        // 保存対象は固定の有無によらず最新の辞書（固定は読み取り側の
        // 意味論であり、保存を旧辞書へ巻き戻さない）。
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
        lock.unlock()
        onSaveResult?(succeeded)
        return succeeded
    }

    /// 現在の辞書と版数を固定する（書き出し開始時）。固定中は
    /// `update` で辞書が変わっても `current` は固定時点のまま。
    /// 入れ子に呼ばれた場合は最初の固定が優先される。
    public func pin() {
        lock.lock()
        if pinCount == 0 {
            pinned = (stored, storedGeneration)
        }
        pinCount += 1
        lock.unlock()
    }

    /// 固定を解除する（書き出し終了時）。`pin()` と対で呼ぶ。
    public func unpin() {
        lock.lock()
        pinCount = max(0, pinCount - 1)
        if pinCount == 0 {
            pinned = nil
        }
        lock.unlock()
    }
}
