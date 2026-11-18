import XCTest
@testable import YMM4Core

/// SOLA 音高補正（Issue #53）の検証。
///
/// 測定方法: 正弦波素材を処理器・チェーンへ通し、出力の
/// (a) 総フレーム数が本家式（定数速度: 入力 / tempo、可変補正: 入力と同数）
///     と一致すること、
/// (b) 定常区間の基本周波数をゼロ交差で推定し、速度を変えても
///     音程が保たれること（リサンプリング方式では音程が速度比で
///     動くことと対比する）
/// を確認する。位置・長さの式は従来の処理器と同じ土台（AudioStream の
/// position 進行）を使うため、累積ずれは (a) の総数で担保する。
final class SolaPitchCorrectionTests: XCTestCase {

    // MARK: - 測定部品

    /// 正弦波の素材（L = R）。
    private func sineProvider(
        frequency: Double, seconds: Double, hz: Int = 48_000
    ) -> InMemoryPCMProvider {
        let frames = Int(seconds * Double(hz))
        var samples: [Float] = []
        samples.reserveCapacity(frames * 2)
        for frame in 0..<frames {
            let value = Float(sin(2.0 * Double.pi * frequency * Double(frame) / Double(hz)))
            samples.append(value)
            samples.append(value)
        }
        return InMemoryPCMProvider(samples: samples, hz: hz)
    }

    /// ゼロ交差による基本周波数推定（フレーム区間 [start, end)）。
    private func estimateFrequency(
        _ samples: [Float], from startFrame: Int, to endFrame: Int, hz: Int = 48_000
    ) -> Double {
        var crossings = 0
        var previous = samples[startFrame * 2]
        for frame in (startFrame + 1)..<endFrame {
            let value = samples[frame * 2]
            if previous < 0 && value >= 0 {
                crossings += 1
            }
            previous = value
        }
        return Double(crossings) * Double(hz) / Double(endFrame - startFrame)
    }

    /// ストリームを最後まで読み切って全サンプルを返す。
    private func readAll(_ stream: AudioStream, chunkSamples: Int = 96_000) -> [Float] {
        var result: [Float] = []
        var buffer = [Float](repeating: 0, count: chunkSamples)
        while true {
            let read = stream.read(into: &buffer, offset: 0, count: chunkSamples)
            if read <= 0 { break }
            result.append(contentsOf: buffer[0..<read])
            if read < chunkSamples { break }
        }
        return result
    }

    // MARK: - 定数速度（SolaTimeStretchStream）

    func testFixedSolaDoubleSpeedPreservesPitchAndHalvesLength() {
        let stream = SolaTimeStretchStream(tempo: 2.0)
        stream.input = FileAudioStream(
            provider: sineProvider(frequency: 440, seconds: 2)
        )
        XCTAssertEqual(stream.duration, 96_000)
        stream.seek(to: 0)
        let output = readAll(stream)
        // 総フレーム数は入力の半分（本家: フラッシュで期待出力数に一致）。
        XCTAssertEqual(output.count / 2, 48_000)
        // 定常区間の音程は 440Hz のまま（リサンプリングなら 880Hz）。
        let estimated = estimateFrequency(output, from: 8_000, to: 40_000)
        XCTAssertEqual(estimated, 440, accuracy: 10)
    }

    func testFixedSolaHalfSpeedPreservesPitchAndDoublesLength() {
        let stream = SolaTimeStretchStream(tempo: 0.5)
        stream.input = FileAudioStream(
            provider: sineProvider(frequency: 440, seconds: 1)
        )
        XCTAssertEqual(stream.duration, 192_000)
        stream.seek(to: 0)
        let output = readAll(stream)
        XCTAssertEqual(output.count / 2, 96_000)
        let estimated = estimateFrequency(output, from: 16_000, to: 80_000)
        XCTAssertEqual(estimated, 440, accuracy: 10)
    }

    func testFixedSolaSeekResetsAndKeepsPitch() {
        let stream = SolaTimeStretchStream(tempo: 2.0)
        stream.input = FileAudioStream(
            provider: sineProvider(frequency: 440, seconds: 2)
        )
        stream.seek(to: 24_000)
        let output = readAll(stream)
        // 残りは (192000 − 24000×2) / 2 = 72000 サンプル = 36000 フレーム。
        XCTAssertEqual(output.count / 2, 36_000)
        let estimated = estimateFrequency(output, from: 8_000, to: 28_000)
        XCTAssertEqual(estimated, 440, accuracy: 10)
    }

    func testResamplingStreamShiftsPitchForContrast() {
        // 対比: 従来のリサンプリング方式では音程が速度比で動く。
        // この処理器はチェーン側で打ち切られる前提で、自身では
        // 終端を返さないため、読み取りは有限量に限る。
        let stream = PlaybackRateStream(rate: 2.0)
        stream.input = FileAudioStream(
            provider: sineProvider(frequency: 440, seconds: 2)
        )
        stream.seek(to: 0)
        var output = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(stream.read(into: &output, offset: 0, count: 96_000), 96_000)
        let estimated = estimateFrequency(output, from: 8_000, to: 40_000)
        XCTAssertEqual(estimated, 880, accuracy: 20)
    }

    // MARK: - GetPitch（本家 VariableSolaPitchCorrectionEffect.GetPitch）

    func testPitchCorrectionValues() {
        XCTAssertEqual(VariableSolaPitchCorrectionStream.pitch(forRatePercent: 100), 1.0)
        XCTAssertEqual(VariableSolaPitchCorrectionStream.pitch(forRatePercent: 200), 0.5)
        XCTAssertEqual(VariableSolaPitchCorrectionStream.pitch(forRatePercent: 50), 2.0)
        XCTAssertEqual(VariableSolaPitchCorrectionStream.pitch(forRatePercent: 25), 4.0)
        // 上限 4 でクランプ。
        XCTAssertEqual(VariableSolaPitchCorrectionStream.pitch(forRatePercent: 10), 4.0)
        // 負の速度は絶対値で扱う。
        XCTAssertEqual(VariableSolaPitchCorrectionStream.pitch(forRatePercent: -200), 0.5)
        // 0・極小は補正なし。
        XCTAssertEqual(VariableSolaPitchCorrectionStream.pitch(forRatePercent: 0), 1.0)
        XCTAssertEqual(VariableSolaPitchCorrectionStream.pitch(forRatePercent: 0.05), 1.0)
    }

    // MARK: - 可変速度の補正（VariableSolaPitchCorrectionStream 単体）

    func testVariableCorrectionKeepsLengthAndPitch() {
        // 前段の可変速度（2 倍速・線形補間）を再現する入力として、
        // 可変処理器そのものをつなぐ。
        let map = PlaybackRateMap(
            rate: Animation(
                defaultValue: 200, minValue: -100_000, maxValue: 100_000,
                animationType: .linear,
                values: [AnimationValue(200), AnimationValue(200)]
            )
        )
        let variable = VariablePlaybackRateStream(
            rateMap: map, itemLength: 60, fps: 30,
            contentOffset: .zero, isLooped: false
        )
        variable.input = FileAudioStream(
            provider: sineProvider(frequency: 440, seconds: 2)
        )
        let correction = VariableSolaPitchCorrectionStream(
            rateMap: map, itemLength: 60, fps: 30
        )
        correction.input = variable
        // 補正段は長さを変えない（本家: Duration = Input.Duration）。
        XCTAssertEqual(correction.duration, variable.duration)
        correction.seek(to: 0)
        let output = readAll(correction)
        XCTAssertEqual(output.count, correction.duration)
        // 素材は 1 秒（アイテム時刻）で尽きる。定常区間の音程は 440Hz。
        let estimated = estimateFrequency(output, from: 12_000, to: 40_000)
        XCTAssertEqual(estimated, 440, accuracy: 15)
    }

    // MARK: - チェーン接続（EffectedAudioItemSource）

    func testChainUsesSolaWhenModeIsSola() {
        let factory = MapPCMProviderFactory()
        factory.providers["s"] = sineProvider(frequency: 440, seconds: 2)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "s", length: 60)
        item.playbackRate = 200
        item.playbackRateAudioProcessingMode = .sola
        let stream = sourceFactory.effectedStream(for: item, hz: 48_000, fps: 30)!
        stream.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 96_000), 96_000)
        // アイテム長 2 秒のうち素材は 1 秒で尽きるため、前半で測る。
        let estimated = estimateFrequency(buffer, from: 8_000, to: 40_000)
        XCTAssertEqual(estimated, 440, accuracy: 10)
    }

    func testChainResamplingModeShiftsPitch() {
        let factory = MapPCMProviderFactory()
        factory.providers["s"] = sineProvider(frequency: 440, seconds: 2)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "s", length: 60)
        item.playbackRate = 200
        item.playbackRateAudioProcessingMode = .resampling
        let stream = sourceFactory.effectedStream(for: item, hz: 48_000, fps: 30)!
        stream.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 96_000), 96_000)
        let estimated = estimateFrequency(buffer, from: 8_000, to: 40_000)
        XCTAssertEqual(estimated, 880, accuracy: 20)
    }

    func testChainVariableSolaCorrectsPitch() {
        let factory = MapPCMProviderFactory()
        factory.providers["s"] = sineProvider(frequency: 440, seconds: 2)
        let sourceFactory = AudioSourceFactory(providerFactory: factory)
        let item = makeAudioItem(filePath: "s", length: 60)
        item.playbackRate2 = Animation(
            defaultValue: 200, minValue: -100_000, maxValue: 100_000,
            animationType: .linear,
            values: [AnimationValue(200), AnimationValue(200)]
        )
        item.playbackRateAudioProcessingMode = .sola
        let stream = sourceFactory.effectedStream(for: item, hz: 48_000, fps: 30)!
        stream.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 96_000)
        XCTAssertEqual(stream.read(into: &buffer, offset: 0, count: 96_000), 96_000)
        let estimated = estimateFrequency(buffer, from: 12_000, to: 40_000)
        XCTAssertEqual(estimated, 440, accuracy: 15)
    }
}
