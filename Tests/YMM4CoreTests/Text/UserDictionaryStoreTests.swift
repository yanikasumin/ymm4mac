import Foundation
import XCTest

@testable import YMM4Core

/// TEXT60 の設定層（UserDictionaryStore）の試験。
/// 保存先は一時ディレクトリへ差し替えて検証する。
final class UserDictionaryStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ymm4-dict-test-\(UUID().uuidString)", isDirectory: true)
        fileURL = directory.appendingPathComponent("UserDictionary.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// ファイルが無ければ既定辞書で起動する。
    func testMissingFileStartsWithDefault() {
        let store = UserDictionaryStore(fileURL: fileURL)
        store.load()
        XCTAssertEqual(store.current, UserDictionary())
        XCTAssertEqual(store.generation, 0)
    }

    /// 更新すると保存され、新しいストアが読み直せる。版数も増える。
    /// 永続化は集約されるため、確定（flush）してから検証する。
    func testUpdatePersistsAndBumpsGeneration() {
        let store = UserDictionaryStore(fileURL: fileURL)
        var edited = UserDictionary()
        edited.asteriskWordSets = [
            WordSet(from: "秘密", to: "＊＊", description: "試験", isEnabled: true)
        ]
        edited.wordSets = []
        store.update(edited)
        XCTAssertEqual(store.generation, 1)
        store.flushPendingSave()
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let reloaded = UserDictionaryStore(fileURL: fileURL)
        reloaded.load()
        XCTAssertEqual(reloaded.current, edited)
        XCTAssertEqual(reloaded.generation, 1)
    }

    /// 2回目の更新は置き換え（replaceItemAt）の経路を通り、最新値が
    /// 復元される（R18-03 の QA: 初回保存だけでは置き換え経路が
    /// 検証できない）。
    func testSecondUpdateReplacesFile() {
        let store = UserDictionaryStore(fileURL: fileURL)
        var first = UserDictionary()
        first.wordSets = []
        first.asteriskWordSets = [
            WordSet(from: "一", to: "１", description: "", isEnabled: true)
        ]
        store.update(first)
        store.flushPendingSave()

        var second = first
        second.asteriskWordSets = [
            WordSet(from: "二", to: "２", description: "", isEnabled: true)
        ]
        store.update(second)
        store.flushPendingSave()
        XCTAssertNil(store.lastSaveError)

        let reloaded = UserDictionaryStore(fileURL: fileURL)
        reloaded.load()
        XCTAssertEqual(reloaded.current, second)
    }

    /// 保存できない場合は失敗が表へ出る（成功と区別できる。R18-03）。
    /// 保存先の親を通常ファイルにして、ディレクトリ作成を失敗させる。
    func testSaveFailureIsSurfaced() throws {
        let blocker = directory.appendingPathComponent("blocker")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try "x".write(to: blocker, atomically: true, encoding: .utf8)
        let badURL = blocker.appendingPathComponent("UserDictionary.json")
        let store = UserDictionaryStore(fileURL: badURL)
        store.update(UserDictionary())
        XCTAssertFalse(store.save())
        XCTAssertNotNil(store.lastSaveError)
        // メモリ上の辞書は保たれる。
        XCTAssertEqual(store.current, UserDictionary())
    }

    /// 取得済みの組は、その後の更新の影響を受けない（D19-01:
    /// 書き出しジョブは開始時点の辞書を使い続ける）。ストア側は
    /// 固定されず、最新の辞書を返し続ける。
    func testSnapshotIsUnaffectedByLaterUpdates() {
        let store = UserDictionaryStore(fileURL: fileURL)
        let snapshot = store.snapshot()
        var edited = UserDictionary()
        edited.wordSets = []
        store.update(edited)
        XCTAssertEqual(snapshot.dictionary, UserDictionary())
        XCTAssertEqual(snapshot.generation, 0)
        XCTAssertEqual(store.current, edited)
        XCTAssertEqual(store.generation, 1)
        store.flushPendingSave()
    }

    /// 集約保存の予約直後に確定保存を呼んでも、最終的にファイルへ
    /// 残るのは最新の辞書である（D19-02: 保存経路の直列化）。
    /// 順序を入れ替えた場合も同じ。
    func testFlushAfterUpdateKeepsLatestDictionary() throws {
        let store = UserDictionaryStore(fileURL: fileURL)
        var first = UserDictionary()
        first.wordSets = []
        store.update(first)
        var second = UserDictionary()
        second.asteriskWordSets = []
        store.update(second)
        store.flushPendingSave()
        let reloaded = UserDictionaryStore(fileURL: fileURL)
        reloaded.load()
        XCTAssertEqual(reloaded.current, second)
    }

    /// 壊れたファイルは既定辞書へ倒れ、例外にならない。
    func testCorruptFileFallsBackToDefault() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try "{ not json".write(to: fileURL, atomically: true, encoding: .utf8)
        let store = UserDictionaryStore(fileURL: fileURL)
        store.load()
        XCTAssertEqual(store.current, UserDictionary())
    }

    /// 保存 JSON のキー名は本家の保存形式（プロパティ名そのまま）。
    func testSavedJSONUsesHonkeKeys() throws {
        let store = UserDictionaryStore(fileURL: fileURL)
        store.update(UserDictionary())
        store.flushPendingSave()
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"AsteriskWordSets\""))
        XCTAssertTrue(text.contains("\"WordSets\""))
        XCTAssertTrue(text.contains("\"PronouncingSets\""))
    }
}
