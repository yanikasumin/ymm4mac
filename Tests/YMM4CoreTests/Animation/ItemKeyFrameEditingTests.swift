import XCTest

@testable import YMM4Core

/// アイテム単位のキーフレーム編集（値列の連動）の試験。
///
/// 編集 UI が使う `BaseItem` の操作を検証する。位置だけを差し替える
/// 経路では値列がずれて曲線が変わるため、追加・削除・全削除・移動の
/// それぞれで値列との整合を確認する。対象アニメーションは
/// `BaseItem.playbackRate2`（基底クラス自身のアニメーション）。
final class ItemKeyFrameEditingTests: XCTestCase {
    /// 直線移動 0→100、長さ 20 のアイテムを作る。
    private func makeItem() -> BaseItem {
        let item = BaseItem()
        item.length = 20
        item.playbackRate2.animationType = .linear
        item.playbackRate2.values = [AnimationValue(0), AnimationValue(100)]
        return item
    }

    private func values(of item: BaseItem) -> [Double] {
        item.playbackRate2.values.map(\.value)
    }

    private func evaluated(_ item: BaseItem, at frame: Int) -> Double {
        item.playbackRate2.value(atFrame: frame, length: item.length, fps: 30)
    }

    /// 追加では、その位置での現在値が値列へ挿入され、曲線は変わらない。
    func testInsertPreservesCurve() {
        let item = makeItem()
        let before = (0..<20).map { evaluated(item, at: $0) }
        XCTAssertTrue(item.insertKeyFrame(at: 10))
        XCTAssertEqual(item.keyFrames.frames, [10])
        XCTAssertEqual(values(of: item), [0, 50, 100])
        let after = (0..<20).map { evaluated(item, at: $0) }
        // 曲線は同一だが、区間が分かれることで評価の演算順が変わり
        // 1 ulp 程度の差が出るため、精度つきで比較する。
        for (b, a) in zip(before, after) {
            XCTAssertEqual(b, a, accuracy: 1e-9)
        }
    }

    /// 重複と範囲外は追加できない。
    func testInsertRejectsDuplicateAndOutOfRange() {
        let item = makeItem()
        XCTAssertTrue(item.insertKeyFrame(at: 10))
        XCTAssertFalse(item.insertKeyFrame(at: 10))
        XCTAssertFalse(item.insertKeyFrame(at: 20))
        XCTAssertFalse(item.insertKeyFrame(at: -1))
        XCTAssertEqual(values(of: item), [0, 50, 100])
    }

    /// 削除では対応する値が取り除かれ、元の値列へ戻る。
    func testRemoveRestoresValues() {
        let item = makeItem()
        XCTAssertTrue(item.insertKeyFrame(at: 10))
        XCTAssertTrue(item.removeKeyFrame(at: 10))
        XCTAssertEqual(item.keyFrames.frames, [])
        XCTAssertEqual(values(of: item), [0, 100])
        XCTAssertFalse(item.removeKeyFrame(at: 10))
    }

    /// 全削除では値列が開始値と終了値だけに畳まれる。
    func testRemoveAllCollapsesToFirstAndLast() {
        let item = makeItem()
        item.playbackRate2.values = [
            AnimationValue(0), AnimationValue(30),
            AnimationValue(70), AnimationValue(100),
        ]
        item.setKeyFrames(KeyFrames(frames: [5, 12]))
        item.removeAllKeyFrames()
        XCTAssertEqual(item.keyFrames.frames, [])
        XCTAssertEqual(values(of: item), [0, 100])
    }

    /// 移動は隣を越えない範囲へ丸められ、値は動かない。
    func testMoveClampsBetweenNeighbors() {
        let item = makeItem()
        item.playbackRate2.values = [
            AnimationValue(0), AnimationValue(30),
            AnimationValue(70), AnimationValue(100),
        ]
        item.setKeyFrames(KeyFrames(frames: [5, 12]))
        XCTAssertTrue(item.moveKeyFrame(from: 5, to: 20))
        XCTAssertEqual(item.keyFrames.frames, [11, 12])
        XCTAssertEqual(values(of: item), [0, 30, 70, 100])
        // 隣へ接している位置からは動けない（丸めた先が元の位置になる）。
        XCTAssertFalse(item.moveKeyFrame(from: 12, to: 0))
        XCTAssertEqual(item.keyFrames.frames, [11, 12])
    }

    /// 区間の特定と区間値の書き換え。
    func testSegmentValueEditing() {
        let item = makeItem()
        XCTAssertTrue(item.insertKeyFrame(at: 10))
        let animation = item.playbackRate2
        XCTAssertEqual(animation.segmentIndex(atFrame: 0), 0)
        XCTAssertEqual(animation.segmentIndex(atFrame: 9), 0)
        XCTAssertEqual(animation.segmentIndex(atFrame: 10), 1)
        XCTAssertEqual(animation.segmentIndex(atFrame: 19), 1)
        item.playbackRate2.setValue(80, atSegment: 1)
        XCTAssertEqual(values(of: item), [0, 80, 100])
        XCTAssertEqual(evaluated(item, at: 10), 80)
    }

    /// アイテム長より後方にキーフレームがある不整合データでは、
    /// 移動範囲の下限が上限を超えるため移動を成立させない
    /// （R20-114-03 の QA05）。
    func testMoveRejectsInconsistentFramesBeyondLength() {
        let item = makeItem()
        item.length = 9
        item.keyFrames = KeyFrames(frames: [8, 10])
        XCTAssertFalse(item.moveKeyFrame(from: 10, to: 0))
        XCTAssertEqual(item.keyFrames.frames, [8, 10])
    }

    /// キーフレーム非対応の型では、位置だけが増えて値は変わらない。
    func testInsertWithNonSupportedTypeKeepsValues() {
        let item = makeItem()
        item.playbackRate2.animationType = .movementAmount
        XCTAssertTrue(item.insertKeyFrame(at: 10))
        XCTAssertEqual(item.keyFrames.frames, [10])
        XCTAssertEqual(values(of: item), [0, 100])
    }
}
