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
///
/// エイリアス測定の是正（QA24-01、2026-11-17）: 旧試験は 48kHz
/// 標本化の入力に 30k / 26k / 40kHz の正弦波を使っており、それらの
/// 音は標本列の生成時点で 18k / 22k / 8kHz へ折り返し済みだった
/// （入力ナイキスト 24kHz 超え）。実効入力は全て出力ナイキストの
/// 内側にあり、折り返し防止フィルタの阻止帯域は一度も試されて
/// いなかった。旧測定に基づく値（-113.4 dB 等）は無効として撤回
/// 済み（経緯と新実測は AUDIO-FIDELITY-PLAN §3.1.1）。現行の
/// エイリアス試験は、入力ナイキストの内側かつ出力ナイキストの
/// 外側の妨害波を入れ、出力側の折り返し先の成分を測る。
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
        // QA24-01 是正後の測定系: 妨害波は入力ナイキスト (24kHz) の
        // 内側かつ出力ナイキスト (22.05kHz) の外側に置き、出力の
        // |f - 44.1k| への折り返し成分を測る。
        // 遮断周波数 (22.05kHz) からの距離で帯域の性格が変わる。
        // 窓長は片側 48 零点 × scale (48k/44.1k ≈ 1.088) ≈ 片側 52
        // フレームしかなく、遷移帯は ±1.4kHz 級の幅を持つ:
        // 22.5kHz は遷移帯の内側、23kHz は遷移帯の途中、23.5k /
        // 23.9kHz は阻止帯域の点である。
        // 実測（2026-11-17、是正後の測定系）: 22.5kHz → -16.7 dB、
        // 23kHz → -41.6 dB、23.5kHz → -78.6 dB、23.9kHz →
        // -75.3 dB。阻止帯域の床は -75 dB 級であり、23.5kHz の値は
        // サイドローブのリプルの山に当たったもので床ではない。
        // 暫定ガードは各実測に余裕を持たせた値であり、正式な
        // 合格値は未決定（計画書 §3.1）。
        for (frequency, alias, guardDB) in [
            (22_500.0, 21_600.0, -10.0),
            (23_000.0, 21_100.0, -35.0),
            (23_500.0, 20_600.0, -70.0),
            (23_900.0, 20_200.0, -65.0),
        ] {
            let output = resampleSinc(frequency: frequency, inHz: 48_000, outHz: 44_100, seconds: 3)
            let level = levelDB(output, hz: 44_100, frequency: alias)
            print("alias down 48k->44.1k f=\(Int(frequency)) spur@\(Int(alias)) = \(level) dB")
            XCTAssertLessThanOrEqual(level, guardDB, "f=\(frequency) の折り返し抑制が不足: \(level) dB")
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

    // MARK: - エイリアス抑制（96k → 48k ダウンサンプル、2:1）

    func testDownsampleAliasSuppression2to1() {
        // 入力ナイキスト 48kHz、出力ナイキスト 24kHz。妨害波はその
        // 中間（25k / 26k / 30k / 40kHz）に置き、出力の |f - 48k|
        // への折り返し成分を測る。25kHz は遮断周波数 (24kHz) の
        // 1kHz 上で遷移帯の点、他は阻止帯域の点。
        // 実測（2026-11-17、是正後の測定系）: 25kHz → -39.4 dB、
        // 26kHz → -75.3 dB、30kHz → -99.9 dB、40kHz → -124.1 dB。
        // 暫定ガードは各実測に余裕を持たせた値であり、正式な
        // 合格値は未決定（計画書 §3.1）。
        for (frequency, alias, guardDB) in [
            (25_000.0, 23_000.0, -30.0),
            (26_000.0, 22_000.0, -65.0),
            (30_000.0, 18_000.0, -90.0),
            (40_000.0, 8_000.0, -110.0),
        ] {
            let output = resampleSinc(frequency: frequency, inHz: 96_000, outHz: 48_000, seconds: 3)
            let level = levelDB(output, hz: 48_000, frequency: alias)
            print("alias down 96k->48k f=\(Int(frequency)) spur@\(Int(alias)) = \(level) dB")
            XCTAssertLessThanOrEqual(level, guardDB, "f=\(frequency) の折り返し抑制が不足: \(level) dB")
        }
        // 通過帯域側の利得も同時に確認する。
        for frequency in [1_000.0, 10_000.0, 20_000.0] {
            let output = resampleSinc(frequency: frequency, inHz: 96_000, outHz: 48_000, seconds: 3)
            let gain = levelDB(output, hz: 48_000, frequency: frequency)
            print("passband down 96k->48k f=\(Int(frequency)) gain=\(gain) dB")
            // 0.1 dB は回帰検出用の暫定ガード。
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

        // エイリアス比較は QA24-01 是正後の測定系（入力ナイキスト内・
        // 出力ナイキスト超えの妨害波で折り返し先を測る）で両方式を
        // 測る。旧系（30kHz 入力→14.1kHz 測定）は入力時点で折り返し
        // 済みの音を測っており、折り返し抑制の比較として無効。
        let sincAlias = levelDB(
            resampleSinc(frequency: 23_000, inHz: 48_000, outHz: 44_100, seconds: 3),
            hz: 44_100, frequency: 21_100
        )
        let linearAlias = levelDB(
            resampleLinear(frequency: 23_000, inHz: 48_000, outHz: 44_100, seconds: 3),
            hz: 44_100, frequency: 21_100
        )
        print("alias comparison 48k->44.1k f=23000 spur@21100: sinc=\(sincAlias) dB, linear=\(linearAlias) dB")
        // 実測の改善量は 34.5 dB（sinc -41.6 dB / 線形 -7.1 dB、
        // 2026-11-17）。23kHz が sinc 側の遷移帯にかかるため、
        // イメージ比較と同じ 40 dB の改善はこの点では成立しない。
        // 30 dB は実測に余裕を持たせた暫定ガード（正式な合格値は
        // 未決定）。
        XCTAssertLessThanOrEqual(
            sincAlias, linearAlias - 30,
            "sinc の折り返し抑制が線形補間より 30dB 以上良くない: sinc=\(sincAlias), linear=\(linearAlias)"
        )

        // 2:1 ダウンサンプルでも同じ比較を固定する。線形補間は
        // 整数比では補間位置が常に入力標本と一致して恒等写像に
        // なるため、折り返しは ≈0 dB（無濾波の間引きと等価）。
        // 実測の改善量は 99.9 dB（sinc -99.9 dB / 線形 ≈0 dB、
        // 2026-11-17）。
        let sincAlias2to1 = levelDB(
            resampleSinc(frequency: 30_000, inHz: 96_000, outHz: 48_000, seconds: 3),
            hz: 48_000, frequency: 18_000
        )
        let linearAlias2to1 = levelDB(
            resampleLinear(frequency: 30_000, inHz: 96_000, outHz: 48_000, seconds: 3),
            hz: 48_000, frequency: 18_000
        )
        print("alias comparison 96k->48k f=30000 spur@18000: sinc=\(sincAlias2to1) dB, linear=\(linearAlias2to1) dB")
        XCTAssertLessThanOrEqual(
            sincAlias2to1, linearAlias2to1 - 40,
            "sinc の折り返し抑制が線形補間より 40dB 以上良くない: sinc=\(sincAlias2to1), linear=\(linearAlias2to1)"
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
