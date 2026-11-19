import Foundation
import XCTest
@testable import YMM4Core

/// 破棄時バックアップ（本家 MainModel.CreateBackup）の試験。
/// 保存先は一時ディレクトリへ差し替えて検証する。
final class ProjectBackupStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ProjectBackupStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ymm4-backup-test-\(UUID().uuidString)", isDirectory: true)
        store = ProjectBackupStore(directoryURL: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// テスト用のプロジェクト（シーン2つ、片方にアイテム1件）。
    private func makeProject() -> Project {
        let project = Project()
        let first = Timeline()
        first.name = "シーン1"
        first.items.append(TextItem())
        let second = Timeline()
        second.name = "シーン2"
        project.timelines = [first, second]
        project.selectedTimelineIndex = 1
        return project
    }

    /// ファイル名が本家の形式（yyyy-MM-dd HH-mm-ss-f 元名.ymmp）に
    /// 従う。f は秒の小数第1位。
    func testBackupFileNameMatchesHonkeFormat() {
        let date = Date(timeIntervalSince1970: 1_763_000_000.35)
        let name = ProjectBackupStore.backupFileName(
            sourceFileName: "sample.ymmp", date: date)
        let c = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond],
            from: date)
        let expected = String(
            format: "%04d-%02d-%02d %02d-%02d-%02d-%d sample.ymmp",
            c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!,
            c.nanosecond! / 100_000_000)
        XCTAssertEqual(name, expected)
    }

    /// 元ファイル名が無ければ基名は「無題」（本家
    /// Texts.DefaultProjectFileName の実文字列）。
    func testBackupFileNameWithoutSourceUsesDefaultBaseName() {
        let name = ProjectBackupStore.backupFileName(
            sourceFileName: nil, date: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(name.hasSuffix(" 無題.ymmp"), name)
    }

    /// 元ファイル名はパスで渡されてもファイル名部分だけが基名になる
    /// （本家は ProjectFilePath の GetFileNameWithoutExtension）。
    func testBackupFileNameStripsDirectoryAndExtension() {
        let name = ProjectBackupStore.backupFileName(
            sourceFileName: "/some/dir/movie.ymmp",
            date: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(name.hasSuffix(" movie.ymmp"), name)
    }

    /// バックアップが作られ、内容が破棄時点のプロジェクトと一致する
    /// （読み直してシーン構成・選択シーンが同じ）。FilePath は本家と
    /// 同じくバックアップファイル自身を指す。
    func testCreateBackupWritesLoadableProjectMatchingSource() throws {
        let project = makeProject()
        let url = try XCTUnwrap(
            store.createBackup(of: project, sourceFileName: "sample.ymmp"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.deletingLastPathComponent().path, directory.path)

        let (loaded, _) = try YmmpCodec.load(fromFile: url.path)
        XCTAssertEqual(loaded.timelines.count, 2)
        XCTAssertEqual(loaded.timelines[0].name, "シーン1")
        XCTAssertEqual(loaded.timelines[0].items.count, 1)
        XCTAssertEqual(loaded.timelines[1].name, "シーン2")
        XCTAssertEqual(loaded.selectedTimelineIndex, 1)
        XCTAssertEqual(loaded.filePath, url.path)
    }

    /// ライブモデルの FilePath はバックアップ作成で書き換わらない
    /// （書き出しは写しに対して行うため）。
    func testCreateBackupDoesNotMutateSourceProject() throws {
        let project = makeProject()
        project.filePath = "/original/movie.ymmp"
        _ = try XCTUnwrap(
            store.createBackup(of: project, sourceFileName: "movie.ymmp"))
        XCTAssertEqual(project.filePath, "/original/movie.ymmp")
    }

    /// 保持世代数（15）を超えた分は、更新日時の古い順に消える。
    func testPruneKeepsNewestFifteen() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<18 {
            let url = directory.appendingPathComponent("backup-\(i).ymmp")
            try Data().write(to: url)
            try fileManager.setAttributes(
                [.modificationDate: base.addingTimeInterval(Double(i) * 3600)],
                ofItemAtPath: url.path)
        }
        store.pruneBackups()
        let remaining = try fileManager.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(remaining.count, ProjectBackupStore.retentionLimit)
        // 最も古い3件（0,1,2）が消え、3〜17 が残る。
        for i in 0..<3 {
            XCTAssertFalse(remaining.contains("backup-\(i).ymmp"))
        }
        for i in 3..<18 {
            XCTAssertTrue(remaining.contains("backup-\(i).ymmp"))
        }
    }

    /// バックアップの作成に失敗しても例外にならず nil が返る
    /// （失敗が破棄を妨げないための契約）。保存先の親がファイルで
    /// あるパスはディレクトリを作れず必ず失敗する。
    func testCreateBackupFailureReturnsNil() throws {
        let blocker = directory.appendingPathComponent("blocker")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        try Data().write(to: blocker)
        let badStore = ProjectBackupStore(
            directoryURL: blocker.appendingPathComponent(
                "Backup", isDirectory: true))
        XCTAssertNil(
            badStore.createBackup(of: makeProject(), sourceFileName: "x.ymmp"))
    }
}
