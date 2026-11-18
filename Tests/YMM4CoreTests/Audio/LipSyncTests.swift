import XCTest

@testable import YMM4Core

/// 口パク（LipSync）の試験。包絡計算（本家 LipSyncEnvelope の規則）と
/// 口形時系列の評価（本家 GetLipSyncFrames / GetMouthShape）を検証する。
final class LipSyncTests: XCTestCase {
    // MARK: 包絡

    /// 無音は全フレーム 0。
    func testEnvelopeOfSilenceIsZero() {
        let provider = InMemoryPCMProvider(
            samples: [Float](repeating: 0, count: 48_000 * 2), hz: 48_000
        )
        let values = LipSyncEnvelopeCalculator.calculate(
            provider: provider, fps: 30, smooth: 4, frameCount: 10
        )
        XCTAssertEqual(values?.count, 11)
        XCTAssertTrue(values?.allSatisfy { $0 == 0 } ?? false)
    }

    /// 一定振幅 0.5 の音は、窓が満たされる位置で RMS = 0.5 になる。
    /// 窓の左端（フレーム 0）では窓の半分だけが音の範囲内なので
    /// sqrt(0.5) 倍になる（窓の中心がフレーム位置に来る規則）。
    func testEnvelopeOfConstantAmplitude() throws {
        let provider = InMemoryPCMProvider(
            samples: [Float](repeating: 0.5, count: 48_000 * 2), hz: 48_000
        )
        let values = try XCTUnwrap(LipSyncEnvelopeCalculator.calculate(
            provider: provider, fps: 30, smooth: 4, frameCount: 10
        ))
        // フレーム 2 以降は窓が全て音の範囲内。
        XCTAssertEqual(values[2], 0.5, accuracy: 1e-6)
        XCTAssertEqual(values[10], 0.5, accuracy: 1e-6)
        // フレーム 0 は窓の半分（6400/12800 サンプル）だけ範囲内。
        XCTAssertEqual(values[0], 0.5 * (0.5).squareRoot(), accuracy: 1e-6)
    }

    /// インパルスは窓の中にある間だけ現れ、窓を出ると消える。
    func testEnvelopeOfImpulse() throws {
        var samples = [Float](repeating: 0, count: 48_000 * 2)
        samples[0] = 1
        let provider = InMemoryPCMProvider(samples: samples, hz: 48_000)
        let values = try XCTUnwrap(LipSyncEnvelopeCalculator.calculate(
            provider: provider, fps: 30, smooth: 4, frameCount: 10
        ))
        // 窓長 12800 サンプル。フレーム 2 の窓は [0, 12800) で含む。
        XCTAssertEqual(values[2], (1.0 / 12_800).squareRoot(), accuracy: 1e-9)
        // フレーム 5 の窓は [9600, 22400) で含まない。
        XCTAssertEqual(values[5], 0)
    }

    /// 不正な引数は nil（本家の Fail 相当）。
    func testEnvelopeRejectsInvalidArguments() {
        let provider = InMemoryPCMProvider(samples: [0, 0], hz: 48_000)
        XCTAssertNil(LipSyncEnvelopeCalculator.calculate(
            provider: provider, fps: 0, smooth: 4, frameCount: 10
        ))
        XCTAssertNil(LipSyncEnvelopeCalculator.calculate(
            provider: provider, fps: 30, smooth: 0, frameCount: 10
        ))
    }

    // MARK: 口形時系列

    private func makeVoiceItem(framesJSON: String) -> VoiceItem {
        let item = VoiceItem()
        var parser = JSONParser(text: framesJSON)
        item.lipSyncFrames = (try? parser.parse()) ?? .array([])
        return item
    }

    /// 時系列の評価: その時刻以前の最後の要素の口形になる。
    func testShapeEvaluation() {
        let item = makeVoiceItem(framesJSON: """
            [
              {"Time": "00:00:00", "Shape": "A"},
              {"Time": "00:00:00.5000000", "Shape": "I"},
              {"Time": "00:00:01", "Shape": "Silent"}
            ]
            """)
        XCTAssertEqual(item.lipSyncShape(atFrame: 0, fps: 30), .a)
        XCTAssertEqual(item.lipSyncShape(atFrame: 14, fps: 30), .a)
        XCTAssertEqual(item.lipSyncShape(atFrame: 15, fps: 30), .i)
        XCTAssertEqual(item.lipSyncShape(atFrame: 29, fps: 30), .i)
        XCTAssertEqual(item.lipSyncShape(atFrame: 30, fps: 30), .silent)
    }

    /// 数値形式の Shape も復号できる（本家の列挙順）。
    func testShapeDecodesNumericForm() {
        let item = makeVoiceItem(framesJSON: """
            [{"Time": "00:00:00", "Shape": 5}]
            """)
        XCTAssertEqual(item.lipSyncShape(atFrame: 0, fps: 30), .o)
    }

    /// 時系列が無ければ常に .silent。
    func testShapeWithoutFramesIsSilent() {
        let item = VoiceItem()
        XCTAssertEqual(item.lipSyncShape(atFrame: 10, fps: 30), .silent)
    }
}
