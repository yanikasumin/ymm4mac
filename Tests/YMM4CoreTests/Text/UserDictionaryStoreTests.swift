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
    func testUpdatePersistsAndBumpsGeneration() {
        let store = UserDictionaryStore(fileURL: fileURL)
        var edited = UserDictionary()
        edited.asteriskWordSets = [
            WordSet(from: "秘密", to: "＊＊", description: "試験", isEnabled: true)
        ]
        edited.wordSets = []
        store.update(edited)
        XCTAssertEqual(store.generation, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let reloaded = UserDictionaryStore(fileURL: fileURL)
        reloaded.load()
        XCTAssertEqual(reloaded.current, edited)
        XCTAssertEqual(reloaded.generation, 1)
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
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"AsteriskWordSets\""))
        XCTAssertTrue(text.contains("\"WordSets\""))
        XCTAssertTrue(text.contains("\"PronouncingSets\""))
    }
}
