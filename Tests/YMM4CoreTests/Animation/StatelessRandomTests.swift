import XCTest
@testable import YMM4Core

final class StatelessRandomTests: XCTestCase {
    // 期待値は本家の生成方式（Mix 方式）を独立に計算したもの。
    // キーに本家の GetHashCode() が含まれる経路については、具体値の
    // 対応付けが未確定のため、ここでは生成方式そのものの一致だけを見る。

    func testGetDoubleKnownVectors() {
        XCTAssertEqual(StatelessRandom.getDouble(keys: [0]), 0.7150832890380876, accuracy: 1e-12)
        XCTAssertEqual(StatelessRandom.getDouble(keys: [1]), 0.03298025340509503, accuracy: 1e-12)
        XCTAssertEqual(StatelessRandom.getDouble(keys: [0, 30]), 0.6724544805420507, accuracy: 1e-12)
        XCTAssertEqual(StatelessRandom.getDouble(keys: [7, 0, 3, 0]), 0.8371521752340596, accuracy: 1e-12)
    }

    func testGetFloatKnownVector() {
        XCTAssertEqual(StatelessRandom.getFloat(keys: [0]), 0.7150832414627075, accuracy: 1e-6)
    }

    func testRangeAndDeterminism() {
        for seed: Int64 in [-2, -1, 0, 1, 2, 12345] {
            for frame: Int64 in [0, 1, 2, 3, 100] {
                let value = StatelessRandom.getDouble(keys: [seed, frame])
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertLessThan(value, 1)
                XCTAssertEqual(value, StatelessRandom.getDouble(keys: [seed, frame]))
            }
        }
    }
}
