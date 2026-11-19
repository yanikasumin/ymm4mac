import XCTest
@testable import YMM4Core

/// シーン削除の確認判定と削除操作（本家 MainViewModel.DeleteSceneAsync
/// の規則）の試験。確認ダイアログ自体はアプリ層のため、ここでは
/// 「確認が要るか」と「確認の有無で削除が成立するか」を固定する。
final class ProjectSceneDeletionTests: XCTestCase {
    /// アイテム件数を指定してシーン群を持つプロジェクトを作る。
    private func makeProject(itemCounts: [Int]) -> Project {
        let project = Project()
        project.timelines = itemCounts.map { count in
            let timeline = Timeline()
            for _ in 0..<count {
                timeline.items.append(TextItem())
            }
            return timeline
        }
        return project
    }

    /// 空のシーンは確認なし（本家は Items.IsEmpty なら即削除）。
    func testEmptySceneDoesNotRequireConfirmation() {
        let project = makeProject(itemCounts: [0, 1])
        XCTAssertFalse(project.timelineDeletionRequiresConfirmation(at: 0))
    }

    /// アイテムが1件でもあるシーンは確認が要る。
    func testSceneWithItemsRequiresConfirmation() {
        let project = makeProject(itemCounts: [0, 1])
        XCTAssertTrue(project.timelineDeletionRequiresConfirmation(at: 1))
    }

    /// 範囲外のインデックスは確認不要（削除自体が成立しない）。
    func testInvalidIndexDoesNotRequireConfirmation() {
        let project = makeProject(itemCounts: [1])
        XCTAssertFalse(project.timelineDeletionRequiresConfirmation(at: 5))
        XCTAssertFalse(project.timelineDeletionRequiresConfirmation(at: -1))
    }

    /// アイテムのあるシーンは、未確認（＝確認でキャンセル）では
    /// 削除されない。
    func testRemoveUnconfirmedSceneWithItemsKeepsScene() {
        let project = makeProject(itemCounts: [1, 0])
        XCTAssertFalse(project.removeTimeline(at: 0, confirmed: false))
        XCTAssertEqual(project.timelines.count, 2)
    }

    /// アイテムのあるシーンも、確認済みなら削除される。
    func testRemoveConfirmedSceneWithItemsDeletes() {
        let project = makeProject(itemCounts: [1, 0])
        XCTAssertTrue(project.removeTimeline(at: 0, confirmed: true))
        XCTAssertEqual(project.timelines.count, 1)
        XCTAssertTrue(project.timelines[0].items.isEmpty)
    }

    /// 空のシーンは未確認でも削除できる（確認自体が出ない経路）。
    func testRemoveEmptySceneWithoutConfirmationDeletes() {
        let project = makeProject(itemCounts: [1, 0])
        XCTAssertTrue(project.removeTimeline(at: 1, confirmed: false))
        XCTAssertEqual(project.timelines.count, 1)
        XCTAssertEqual(project.timelines[0].items.count, 1)
    }

    /// 最後の1つは、確認済みでも削除できない。
    func testRemoveLastSceneIsRejected() {
        let project = makeProject(itemCounts: [1])
        XCTAssertFalse(project.removeTimeline(at: 0, confirmed: true))
        XCTAssertEqual(project.timelines.count, 1)
    }

    /// 範囲外のインデックスは削除できない。
    func testRemoveInvalidIndexIsRejected() {
        let project = makeProject(itemCounts: [0, 0])
        XCTAssertFalse(project.removeTimeline(at: 2, confirmed: true))
        XCTAssertEqual(project.timelines.count, 2)
    }
}
