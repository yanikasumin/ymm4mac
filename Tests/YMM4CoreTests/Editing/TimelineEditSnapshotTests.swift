import XCTest
@testable import YMM4Core

/// FE-R20-126-01: `TimelineEditSnapshot` の差分コマンドの適用で、
/// タイムラインの長さ・最大レイヤーのキャッシュが壊れないことの検証。
///
/// 受け入れ観点: 移動／両端リサイズ／削除＋後続移動の各往復について、
/// Undo・Redo の適用後に `timeline.length == computeCurrentLength()`
/// かつ `timeline.maxLayer == computeCurrentMaxLayer()` が保たれる。
/// 変更の実行はアプリ層の確定経路と同じく、変更直後に
/// `refreshTimelineLengthAndMaxLayer()` でキャッシュを実状態へ
/// 合わせてから記録する（ドラッグ確定・メニュー操作の実経路）。
final class TimelineEditSnapshotTests: XCTestCase {

    private func makeItem(frame: Int, layer: Int, length: Int) -> TextItem {
        let item = TextItem()
        item.frame = frame
        item.layer = layer
        item.length = length
        return item
    }

    private func assertCacheConsistent(
        _ timeline: Timeline,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            timeline.length, timeline.computeCurrentLength(),
            "length キャッシュが実状態と乖離している", file: file, line: line)
        XCTAssertEqual(
            timeline.maxLayer, timeline.computeCurrentMaxLayer(),
            "maxLayer キャッシュが実状態と乖離している", file: file, line: line)
    }

    /// 監査の再現そのもの: Frame=60, Length=30（長さ90）のアイテムを
    /// Frame=0 へ移動確定し、Undo で戻したときに長さが 90 へ戻る。
    func testMoveUndoRedoKeepsLengthCacheConsistent() {
        let timeline = Timeline()
        let item = makeItem(frame: 60, layer: 0, length: 30)
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.length, 90)

        let recorder = EditRecorder()
        recorder.recordTimelineChange(timeline: timeline) {
            item.frame = 0
            timeline.refreshTimelineLengthAndMaxLayer()
        }
        XCTAssertEqual(timeline.length, 30)

        XCTAssertTrue(recorder.coordinator.undo())
        XCTAssertEqual(item.frame, 60)
        XCTAssertEqual(timeline.length, 90)
        assertCacheConsistent(timeline)

        XCTAssertTrue(recorder.coordinator.redo())
        XCTAssertEqual(item.frame, 0)
        XCTAssertEqual(timeline.length, 30)
        assertCacheConsistent(timeline)
    }

    /// レイヤーをまたぐ移動では maxLayer のキャッシュも往復する。
    func testLayerMoveUndoRedoKeepsMaxLayerCacheConsistent() {
        let timeline = Timeline()
        let item = makeItem(frame: 0, layer: 0, length: 30)
        timeline.items = [item]
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.maxLayer, 0)

        let recorder = EditRecorder()
        recorder.recordTimelineChange(timeline: timeline) {
            item.layer = 3
            timeline.refreshTimelineLengthAndMaxLayer()
        }
        XCTAssertEqual(timeline.maxLayer, 3)

        XCTAssertTrue(recorder.coordinator.undo())
        XCTAssertEqual(item.layer, 0)
        XCTAssertEqual(timeline.maxLayer, 0)
        assertCacheConsistent(timeline)

        XCTAssertTrue(recorder.coordinator.redo())
        XCTAssertEqual(item.layer, 3)
        XCTAssertEqual(timeline.maxLayer, 3)
        assertCacheConsistent(timeline)
    }

    /// 末尾リサイズ（長さ変更）: 終端が縮む往復でキャッシュが追随する。
    func testResizeFootUndoRedoKeepsLengthCacheConsistent() {
        let timeline = Timeline()
        let head = makeItem(frame: 0, layer: 0, length: 30)
        let tail = makeItem(frame: 60, layer: 0, length: 30)
        timeline.items = [head, tail]
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.length, 90)

        let recorder = EditRecorder()
        recorder.recordTimelineChange(timeline: timeline) {
            tail.length = 10
            timeline.refreshTimelineLengthAndMaxLayer()
        }
        XCTAssertEqual(timeline.length, 70)

        XCTAssertTrue(recorder.coordinator.undo())
        XCTAssertEqual(tail.length, 30)
        XCTAssertEqual(timeline.length, 90)
        assertCacheConsistent(timeline)

        XCTAssertTrue(recorder.coordinator.redo())
        XCTAssertEqual(tail.length, 10)
        XCTAssertEqual(timeline.length, 70)
        assertCacheConsistent(timeline)
    }

    /// 先頭リサイズ（開始フレームと長さが対で変わる）: 終端を保った
    /// 往復でも、フレームと長さの両コマンド適用後にキャッシュが
    /// 実状態と一致する。
    func testResizeHeadUndoRedoKeepsLengthCacheConsistent() {
        let timeline = Timeline()
        let head = makeItem(frame: 0, layer: 0, length: 30)
        let tail = makeItem(frame: 60, layer: 0, length: 30)
        timeline.items = [head, tail]
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.length, 90)

        let recorder = EditRecorder()
        recorder.recordTimelineChange(timeline: timeline) {
            tail.frame = 30
            tail.length = 60
            timeline.refreshTimelineLengthAndMaxLayer()
        }
        XCTAssertEqual(timeline.length, 90)

        XCTAssertTrue(recorder.coordinator.undo())
        XCTAssertEqual(tail.frame, 60)
        XCTAssertEqual(tail.length, 30)
        assertCacheConsistent(timeline)

        XCTAssertTrue(recorder.coordinator.redo())
        XCTAssertEqual(tail.frame, 30)
        XCTAssertEqual(tail.length, 60)
        assertCacheConsistent(timeline)
    }

    /// FE-R20-126-04: レイヤー削除の Undo が操作全体（アイテム列・
    /// レイヤー番号の付け替え・レイヤー設定）を復元する。変更の実行は
    /// アプリ層 `deleteLayer` と同じ手順（対象レイヤーのアイテム削除、
    /// 上のレイヤーを詰める、設定の除去と付け替え）を再現する。
    func testLayerDeletionUndoRestoresLayerSettings() {
        let timeline = Timeline()
        let onLayer1 = makeItem(frame: 0, layer: 1, length: 30)
        let onLayer2 = makeItem(frame: 0, layer: 2, length: 30)
        timeline.items = [onLayer1, onLayer2]
        let originalSettings = [
            LayerSetting(layer: 0, label: "土台"),
            LayerSetting(
                layer: 1, label: "消える層",
                color: Color(alpha: 255, red: 10, green: 20, blue: 30),
                isHidden: true),
            LayerSetting(layer: 2, label: "上の層"),
        ]
        timeline.layerSettings.items = originalSettings
        timeline.refreshTimelineLengthAndMaxLayer()

        let recorder = EditRecorder()
        recorder.recordTimelineChange(timeline: timeline) {
            // TimelineContextMenus.deleteLayer と同じ手順。
            timeline.deleteItems([onLayer1])
            for item in timeline.items where item.layer > 1 {
                item.layer -= 1
            }
            timeline.layerSettings.items.removeAll { $0.layer == 1 }
            for index in timeline.layerSettings.items.indices
            where timeline.layerSettings.items[index].layer > 1 {
                timeline.layerSettings.items[index].layer -= 1
            }
            timeline.refreshTimelineLengthAndMaxLayer()
        }
        XCTAssertEqual(timeline.items.count, 1)
        XCTAssertEqual(onLayer2.layer, 1)
        XCTAssertEqual(
            timeline.layerSettings.items.map { $0.label }, ["土台", "上の層"])
        XCTAssertEqual(
            timeline.layerSettings.items.map { $0.layer }, [0, 1])

        XCTAssertTrue(recorder.coordinator.undo())
        XCTAssertEqual(timeline.items.count, 2)
        XCTAssertTrue(timeline.items.contains { $0 === onLayer1 })
        XCTAssertEqual(onLayer1.layer, 1)
        XCTAssertEqual(onLayer2.layer, 2)
        XCTAssertEqual(timeline.layerSettings.items, originalSettings)
        assertCacheConsistent(timeline)

        XCTAssertTrue(recorder.coordinator.redo())
        XCTAssertEqual(timeline.items.count, 1)
        XCTAssertEqual(onLayer2.layer, 1)
        XCTAssertEqual(
            timeline.layerSettings.items.map { $0.label }, ["土台", "上の層"])
        assertCacheConsistent(timeline)
    }

    /// 削除＋後続アイテムの移動（削除して詰める相当）: メンバーシップと
    /// 配置値が混在する往復で、順序・値・キャッシュが全て戻る。
    func testDeleteAndMoveUndoRedoKeepsCacheConsistent() {
        let timeline = Timeline()
        let first = makeItem(frame: 0, layer: 0, length: 30)
        let second = makeItem(frame: 60, layer: 0, length: 30)
        timeline.items = [first, second]
        timeline.refreshTimelineLengthAndMaxLayer()
        XCTAssertEqual(timeline.length, 90)

        let recorder = EditRecorder()
        recorder.recordTimelineChange(timeline: timeline) {
            timeline.items = [second]
            second.frame = 30
            timeline.refreshTimelineLengthAndMaxLayer()
        }
        XCTAssertEqual(timeline.length, 60)

        XCTAssertTrue(recorder.coordinator.undo())
        XCTAssertEqual(timeline.items.count, 2)
        XCTAssertTrue(timeline.items[0] === first)
        XCTAssertTrue(timeline.items[1] === second)
        XCTAssertEqual(second.frame, 60)
        XCTAssertEqual(timeline.length, 90)
        assertCacheConsistent(timeline)

        XCTAssertTrue(recorder.coordinator.redo())
        XCTAssertEqual(timeline.items.count, 1)
        XCTAssertTrue(timeline.items[0] === second)
        XCTAssertEqual(second.frame, 30)
        XCTAssertEqual(timeline.length, 60)
        assertCacheConsistent(timeline)
    }
}
