import XCTest

@testable import YMM4Core

/// リサンプラ生成コア（帯域制限補間）の品質実測。
///
/// AUDIO-FIDELITY-PLAN §3.1 の測定系を実装したもの。正弦波を変換し、
/// 通過帯域の利得とイメージ／エイリアス成分のレベルを、ちょうど
/// 1 秒の定常区間に対する厳密周波数の DFT で測る（分析対象の
/// 周波数はすべて整数 Hz で、1 秒区間に整数周期が収まるため、
/// 基本波とスプリアスの相互漏れは生じない）。
///
/// 閾値について: 計画書 §3.1 のとおり正式な合格値は ChatGPT
/// レビューとオーナー承認で決めるものであり、ここに置く閾値は
/// 実測値に余裕を持たせた「回帰検出用の暫定ガード」である。
/// 対照として旧方式（線形補間）も同じ測定系で測り、改善量を固定する。
final class AudioResamplerQualityTests: XCTestCase {

    // MARK: - 測定系

    private let amplitude: Float = 0.5

    private func sineProvider(frequency: Double, hz: Int, seconds: Double) -> InMemoryPCMProvider {
        let frames = Int(Double(hz) * seconds)
        var samples = [Float](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            let value = amplitude * Float(sin(2 * Double.pi * frequency * Double(frame) / Double(hz)))
            samples[frame * 2] = value
            samples[frame * 2 + 1] = value
        }
        return InMemoryPCMProvider(samples: samples, hz: hz)
    }

    /// ResamplerStream で全長を変換し、左チャンネルのフレーム列を返す。
    private func resampleSinc(frequency: Double, inHz: Int, outHz: Int, seconds: Double) -> [Float] {
        let stream = ResamplerStream(toHz: outHz)
        stream.input = FileAudioStream(
            provider: sineProvider(frequency: frequency, hz: inHz, seconds: seconds)
        )
        stream.seek(to: 0)
        var interleaved = [Float](repeating: 0, count: stream.duration)
        let read = stream.read(into: &interleaved, offset: 0, count: stream.duration)
        XCTAssertEqual(read, stream.duration)
        return stride(from: 0, to: read, by: 2).map { interleaved[$0] }
    }

    /// 旧方式（線形補間）の対照実装。位置写像は現行契約と同じ
    /// （出力フレーム j → 素材位置 j × inHz/outHz、範囲外は無音）。
    private func resampleLinear(frequency: Double, inHz: Int, outHz: Int, seconds: Double) -> [Float] {
        let inputFrames = Int(Double(inHz) * seconds)
        var input = [Float](repeating: 0, count: inputFrames)
        for frame in 0..<inputFrames {
            input[frame] = amplitude * Float(sin(2 * Double.pi * frequency * Double(frame) / Double(inHz)))
        }
        let scaled = Int(Double(inputFrames * 2) * (Double(outHz) / Double(inHz)))
        let outFrames = (scaled - scaled % 2) / 2
        let ratio = Double(inHz) / Double(outHz)
        var output = [Float](repeating: 0, count: outFrames)
        for frame in 0..<outFrames {
            let sourcePosition = Double(frame) * ratio
            let lower = Int(sourcePosition.rounded(.down))
            let fraction = Float(sourcePosition - Double(lower))
            let first: Float = (lower >= 0 && lower < inputFrames) ? input[lower] : 0
            let second: Float = (lower + 1 >= 0 && lower + 1 < inputFrames) ? input[lower + 1] : 0
            output[frame] = first + (second - first) * fraction
        }
        return output
    }

    /// ちょうど 1 秒の定常区間（2 秒目）について、厳密周波数の
    /// 振幅を dB で返す（基準は入力振幅 amplitude = 0 dB）。
    private func levelDB(_ frames: [Float], hz: Int, frequency: Double) -> Double {
        let start = hz
        let count = hz
        guard frames.count >= start + count else { return -Double.infinity }
        var real = 0.0
        var imaginary = 0.0
        for index in 0..<count {
            let angle = -2 * Double.pi * frequency * Double(index) / Double(hz)
            real += Double(frames[start + index]) * cos(angle)
            imaginary += Double(frames[start + index]) * sin(angle)
        }
        let magnitude = 2 * (real * real + imaginary * imaginary).squareRoot() / Double(count)
        return 20 * log10(magnitude / Double(amplitude))
    }

    // MARK: - 通過帯域の平坦さ（44.1k → 48k アップサンプル）

    func testUpsamplePassbandFlatness() {
        for frequency in [1_000.0, 5_000.0, 10_000.0, 15_000.0, 18_000.0, 20_000.0] {
            let output = resampleSinc(frequency: frequency, inHz: 44_100, outHz: 48_000, seconds: 3)
            let gain = levelDB(output, hz: 48_000, frequency: frequency)
            print("passband up f=\(Int(frequency)) gain=\(gain) dB")
            // 実測は全点で |gain| <= 0.002 dB。0.1 dB は回帰検出用の暫定ガード。
            XCTAssertLessThanOrEqual(abs(gain), 0.1, "f=\(frequency) の通過利得が大きい: \(gain) dB")
        }
    }

    // MARK: - イメージ抑制（44.1k → 48k）

    func testUpsampleImageSuppression() {
        // -80 dB は暫定ガード。実測の最悪値は 20kHz イメージの
        // -88.7 dB（帯域端で遷移帯に最も近い点）。
        // 20kHz のイメージは 44.1k - 20k = 24.1kHz に現れる。
        let output20k = resampleSinc(frequency: 20_000, inHz: 44_100, outHz: 48_000, seconds: 3)
        let image20k = levelDB(output20k, hz: 48_000, frequency: 24_100)
        print("image up f=20000 spur@24100 = \(image20k) dB")
        XCTAssertLessThanOrEqual(image20k, -80, "20kHz のイメージ抑制が不足: \(image20k) dB")

        // 10kHz のイメージは 34.1kHz。
        let output10k = resampleSinc(frequency: 10_000, inHz: 44_100, outHz: 48_000, seconds: 3)
        let image10k = levelDB(output10k, hz: 48_000, frequency: 34_100)
        print("image up f=10000 spur@34100 = \(image10k) dB")
        XCTAssertLessThanOrEqual(image10k, -80, "10kHz のイメージ抑制が不足: \(image10k) dB")
    }

    // MARK: - エイリアス抑制（48k → 44.1k ダウンサンプル）

    func testDownsampleAliasSuppression() {
        // -80 dB は暫定ガード。実測の最悪値は 26kHz 折り返しの
        // -105.3 dB。
        // 出力ナイキスト (22.05kHz) 超えの成分は |f - 44.1k| へ折り返す。
        for (frequency, alias) in [(30_000.0, 14_100.0), (26_000.0, 18_100.0), (40_000.0, 4_100.0)] {
            let output = resampleSinc(frequency: frequency, inHz: 48_000, outHz: 44_100, seconds: 3)
            let level = levelDB(output, hz: 44_100, frequency: alias)
            print("alias down f=\(Int(frequency)) spur@\(Int(alias)) = \(level) dB")
            XCTAssertLessThanOrEqual(level, -80, "f=\(frequency) の折り返し抑制が不足: \(level) dB")
        }
        // 通過帯域側の利得も同時に確認する。
        for frequency in [1_000.0, 10_000.0, 20_000.0] {
            let output = resampleSinc(frequency: frequency, inHz: 48_000, outHz: 44_100, seconds: 3)
            let gain = levelDB(output, hz: 44_100, frequency: frequency)
            print("passband down f=\(Int(frequency)) gain=\(gain) dB")
            // 実測は全点で |gain| <= 0.002 dB。0.1 dB は回帰検出用の暫定ガード。
            XCTAssertLessThanOrEqual(abs(gain), 0.1, "f=\(frequency) の通過利得が大きい: \(gain) dB")
        }
    }

    // MARK: - 線形補間との比較（改善量の固定）

    func testSincSuppressesImagesBetterThanLinear() {
        let sincImage = levelDB(
            resampleSinc(frequency: 20_000, inHz: 44_100, outHz: 48_000, seconds: 3),
            hz: 48_000, frequency: 24_100
        )
        let linearImage = levelDB(
            resampleLinear(frequency: 20_000, inHz: 44_100, outHz: 48_000, seconds: 3),
            hz: 48_000, frequency: 24_100
        )
        print("image comparison: sinc=\(sincImage) dB, linear=\(linearImage) dB")
        XCTAssertLessThanOrEqual(
            sincImage, linearImage - 40,
            "sinc のイメージ抑制が線形補間より 40dB 以上良くない: sinc=\(sincImage), linear=\(linearImage)"
        )

        let sincAlias = levelDB(
            resampleSinc(frequency: 30_000, inHz: 48_000, outHz: 44_100, seconds: 3),
            hz: 44_100, frequency: 14_100
        )
        let linearAlias = levelDB(
            resampleLinear(frequency: 30_000, inHz: 48_000, outHz: 44_100, seconds: 3),
            hz: 44_100, frequency: 14_100
        )
        print("alias comparison: sinc=\(sincAlias) dB, linear=\(linearAlias) dB")
        XCTAssertLessThanOrEqual(
            sincAlias, linearAlias - 40,
            "sinc の折り返し抑制が線形補間より 40dB 以上良くない: sinc=\(sincAlias), linear=\(linearAlias)"
        )
    }

    // MARK: - 位置精度（インパルスのピーク位置、計画書 §3.2）

    func testImpulsePeakPositionIsPreserved() {
        let impulseFrame = 100_000
        let totalFrames = impulseFrame + 44_100
        var samples = [Float](repeating: 0, count: totalFrames * 2)
        samples[impulseFrame * 2] = 1
        samples[impulseFrame * 2 + 1] = 1
        let stream = ResamplerStream(toHz: 48_000)
        stream.input = FileAudioStream(
            provider: InMemoryPCMProvider(samples: samples, hz: 44_100)
        )
        stream.seek(to: 0)
        var interleaved = [Float](repeating: 0, count: stream.duration)
        let read = stream.read(into: &interleaved, offset: 0, count: stream.duration)
        XCTAssertEqual(read, stream.duration)
        var peakFrame = -1
        var peakValue: Float = 0
        for frame in 0..<(read / 2) where abs(interleaved[frame * 2]) > peakValue {
            peakValue = abs(interleaved[frame * 2])
            peakFrame = frame
        }
        let expected = Int((Double(impulseFrame) * 48_000.0 / 44_100.0).rounded())
        XCTAssertEqual(peakFrame, expected, "インパルスのピーク位置が式どおりでない")
    }

    // MARK: - 処理コストの目安（合否判定なし、実測の記録用）

    func testConversionCost() {
        for (inHz, outHz) in [(48_000, 44_100), (44_100, 48_000)] {
            let stream = ResamplerStream(toHz: outHz)
            stream.input = FileAudioStream(
                provider: sineProvider(frequency: 1_000, hz: inHz, seconds: 30)
            )
            stream.seek(to: 0)
            var interleaved = [Float](repeating: 0, count: stream.duration)
            let start = Date()
            let read = stream.read(into: &interleaved, offset: 0, count: stream.duration)
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertEqual(read, stream.duration)
            let audioSeconds = Double(read / 2) / Double(outHz)
            print(
                "cost \(inHz)->\(outHz): \(elapsed)s for \(audioSeconds)s of audio"
                    + " (realtime x\(audioSeconds / elapsed))"
            )
        }
    }
}
