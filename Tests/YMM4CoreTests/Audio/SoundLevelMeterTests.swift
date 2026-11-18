import XCTest
@testable import YMM4Core

/// サウンドレベルメーター（Issue #52）の検証。
///
/// 期待値は本家 `SoundLevelMeter` の計算式から導いた理論値であり、
/// 本家実機との比較試験ではない。ピークと RMS は式が単純なため
/// 理論値と厳密に照合する。ラウドネスは K 特性フィルタを含むため、
/// 無音で −60 に張り付くことと、信号で下限を離れることの範囲検証に
/// 留める。
final class SoundLevelMeterTests: XCTestCase {
    private let hz = 48_000

    /// 1 秒分（hz × 2 サンプル）の定数信号。L と R で振幅を変えられる。
    private func constantSecond(left: Float, right: Float) -> [Float] {
        var samples = [Float](repeating: 0, count: hz * 2)
        for frame in 0..<hz {
            samples[frame * 2] = left
            samples[frame * 2 + 1] = right
        }
        return samples
    }

    private func silenceSecond() -> [Float] {
        [Float](repeating: 0, count: hz * 2)
    }

    func testSilenceStaysAtFloor() {
        let meter = SoundLevelMeter()
        meter.seek(to: .zero, hz: hz)
        meter.process(silenceSecond())
        meter.setCurrentPosition(TimeSpanValue(seconds: 1), isDecayed: true)
        XCTAssertEqual(meter.left.current.peak, -60)
        XCTAssertEqual(meter.left.current.rms, -60)
        XCTAssertEqual(meter.right.current.peak, -60)
        XCTAssertEqual(meter.loudness.current.peak, -60)
        XCTAssertEqual(meter.left.hold.peak, -60)
    }

    func testPeakMatchesTheory() {
        let meter = SoundLevelMeter()
        meter.seek(to: .zero, hz: hz)
        meter.process(constantSecond(left: 0.5, right: 0.25))
        meter.setCurrentPosition(TimeSpanValue(seconds: 1), isDecayed: false)
        // 20 * log10(0.5) = -6.0206, 20 * log10(0.25) = -12.0412
        XCTAssertEqual(meter.left.current.peak, -6.0206, accuracy: 0.001)
        XCTAssertEqual(meter.right.current.peak, -12.0412, accuracy: 0.001)
        XCTAssertEqual(meter.left.hold.peak, -6.0206, accuracy: 0.001)
    }

    func testPeakBelowThresholdIsFloored() {
        let meter = SoundLevelMeter()
        meter.seek(to: .zero, hz: hz)
        // 0.0005 < 0.001（本家の下限しきい値）なので −60 に丸められる。
        meter.process(constantSecond(left: 0.0005, right: 0.0005))
        meter.setCurrentPosition(TimeSpanValue(seconds: 1), isDecayed: false)
        XCTAssertEqual(meter.left.current.peak, -60)
    }

    func testRMSUsesSixSegmentWindowIncludingPreviousTail() {
        let meter = SoundLevelMeter()
        meter.seek(to: .zero, hz: hz)
        // 1 秒目は無音、2 秒目が定数 0.5。2 秒目の先頭区間の RMS 窓は
        // 「前回末尾 5 区間（無音）＋今回先頭 1 区間」が本家の規則。
        // 位置 1 秒ちょうどの区間値を取り出すため、2 秒目の最初の
        // 区間が現在値になるよう位置を指定する。
        meter.process(silenceSecond())
        meter.process(constantSecond(left: 0.5, right: 0.5))
        // 区間は 1/60 秒単位。2 秒目の先頭区間の位置は 1 秒 = 96000
        // サンプル。その区間の値が現在値になるのは、位置がその区間
        // 以上・次の区間未満のとき。1 秒 + 1/60 秒の直前を指定する。
        let segment = 1.0 / 60.0
        meter.setCurrentPosition(
            TimeSpanValue(seconds: 1 + segment * 0.5), isDecayed: false
        )
        // RMS = sqrt((0 * 5 + 0.25 * 1) / 6) → 20*log10(0.2041) = -13.80
        let expected = 20 * log10((0.25 / 6.0).squareRoot())
        XCTAssertEqual(meter.left.current.rms, expected, accuracy: 0.01)
        // ピークは区間そのものの値なので 0.5 の理論値。
        XCTAssertEqual(meter.left.current.peak, -6.0206, accuracy: 0.001)
    }

    func testRMSConvergesToSignalLevelAfterWindowFills() {
        let meter = SoundLevelMeter()
        meter.seek(to: .zero, hz: hz)
        meter.process(constantSecond(left: 0.5, right: 0.5))
        meter.process(constantSecond(left: 0.5, right: 0.5))
        // 2 秒目の末尾区間では窓（自区間開始から 6 区間）が全て信号で
        // 埋まるため、RMS は信号レベルそのものになる。
        meter.setCurrentPosition(TimeSpanValue(seconds: 2), isDecayed: false)
        XCTAssertEqual(meter.left.current.rms, -6.0206, accuracy: 0.001)
    }

    func testPeakDecaysByHalfDecibelPerUpdate() {
        let meter = SoundLevelMeter()
        meter.seek(to: .zero, hz: hz)
        meter.process(constantSecond(left: 0.5, right: 0.5))
        meter.setCurrentPosition(TimeSpanValue(seconds: 1), isDecayed: true)
        XCTAssertEqual(meter.left.current.peak, -6.0206, accuracy: 0.001)
        // 無音を流し続けると、表示ピークは更新のたびに 0.5 dB 下がる。
        meter.process(silenceSecond())
        meter.setCurrentPosition(TimeSpanValue(seconds: 2), isDecayed: true)
        XCTAssertEqual(meter.left.current.peak, -6.5206, accuracy: 0.001)
        meter.process(silenceSecond())
        meter.setCurrentPosition(TimeSpanValue(seconds: 3), isDecayed: true)
        XCTAssertEqual(meter.left.current.peak, -7.0206, accuracy: 0.001)
        // ホールドは 10 秒以内はピークを保持する。
        XCTAssertEqual(meter.left.hold.peak, -6.0206, accuracy: 0.001)
    }

    func testHoldExpiresAfterTenSeconds() {
        let meter = SoundLevelMeter()
        meter.seek(to: .zero, hz: hz)
        meter.process(constantSecond(left: 0.5, right: 0.5))
        meter.setCurrentPosition(TimeSpanValue(seconds: 1), isDecayed: true)
        XCTAssertEqual(meter.left.hold.peak, -6.0206, accuracy: 0.001)
        // 11 秒ぶん無音を流すと、ホールド位置 +10 秒を超えた区間で
        // ホールドが無音側の値へ更新される。
        for second in 0..<11 {
            meter.process(silenceSecond())
            meter.setCurrentPosition(
                TimeSpanValue(seconds: Double(second + 2)), isDecayed: true
            )
        }
        XCTAssertEqual(meter.left.hold.peak, -60)
    }

    func testSeekKeepsCurrentButClearsHold() {
        let meter = SoundLevelMeter()
        meter.seek(to: .zero, hz: hz)
        meter.process(constantSecond(left: 0.5, right: 0.5))
        meter.setCurrentPosition(TimeSpanValue(seconds: 1), isDecayed: false)
        XCTAssertEqual(meter.left.hold.peak, -6.0206, accuracy: 0.001)
        meter.seek(to: TimeSpanValue(seconds: 30), hz: hz)
        // 本家 Seek は現在値を保持し、ホールドだけをリセットする。
        XCTAssertEqual(meter.left.current.peak, -6.0206, accuracy: 0.001)
        XCTAssertEqual(meter.left.hold.peak, -60)
    }

    func testLoudnessLeavesFloorForSignalAndReturnsForSilence() {
        let meter = SoundLevelMeter()
        meter.seek(to: .zero, hz: hz)
        // 440 Hz サイン波（振幅 0.5）を 3 秒分流す。ブロックは 0.4 秒
        // 単位で進むため、数ブロック分の値が蓄積される。
        var samples: [Float] = []
        samples.reserveCapacity(hz * 2)
        for frame in 0..<hz {
            let value = Float(0.5 * sin(2 * Double.pi * 440 * Double(frame) / Double(hz)))
            samples.append(value)
            samples.append(value)
        }
        for _ in 0..<3 {
            meter.process(samples)
        }
        meter.setCurrentPosition(TimeSpanValue(seconds: 3), isDecayed: false)
        let loudness = meter.loudness.current
        XCTAssertGreaterThan(loudness.peak, -60)
        XCTAssertGreaterThan(loudness.rms, -60)
        // 0.5 振幅のサイン波の BS.1770 ラウドネスは概ね -10 前後。
        // フィルタ定数の厳密な一致は本家比較試験の範囲なので、
        // ここでは非常識な値でないことだけを見る。
        XCTAssertLessThan(loudness.peak, 0)
        XCTAssertEqual(loudness.peak, loudness.rms, accuracy: 6)
    }

    func testDisabledMetersDoNotAccumulate() {
        let meter = SoundLevelMeter()
        meter.isSoundLevelMeterEnabled = false
        meter.isLoudnessMeterEnabled = false
        meter.seek(to: .zero, hz: hz)
        meter.process(constantSecond(left: 0.5, right: 0.5))
        meter.setCurrentPosition(TimeSpanValue(seconds: 1), isDecayed: false)
        XCTAssertEqual(meter.left.current.peak, -60)
        XCTAssertEqual(meter.loudness.current.peak, -60)
    }
}
