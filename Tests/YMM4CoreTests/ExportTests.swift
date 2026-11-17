import XCTest
@testable import YMM4Core

// MARK: - 引数生成

final class FFmpegArgumentsTests: XCTestCase {
    private func defaultSettings() -> FFmpegExportSettings {
        FFmpegExportSettings(width: 1920, height: 1080, fps: 30, hz: 48_000, length: 300)
    }

    func testDefaultAudioArgsString() {
        let args = FFmpegArguments.audioArgs(settings: defaultSettings())
        XCTAssertEqual(args.argumentString, "-b:a 192000 -c:a aac -f mp4 -loglevel warning")
    }

    func testDefaultVideoArgsStringCBR() {
        let args = FFmpegArguments.videoArgs(settings: defaultSettings())
        XCTAssertEqual(args.argumentString, "-b:v 10000000 -c:v h264 -f mp4 -loglevel warning")
    }

    func testVideoArgsQualityMode() {
        var settings = defaultSettings()
        settings.videoBitRateControlMode = .quality
        settings.videoQuality = 55
        let args = FFmpegArguments.videoArgs(settings: settings)
        XCTAssertEqual(args.argumentString, "-crf:v 23 -c:v h264 -f mp4 -loglevel warning")
    }

    func testVideoArgsBitRateModeNone() {
        var settings = defaultSettings()
        settings.videoBitRateMode = .none
        let args = FFmpegArguments.videoArgs(settings: settings)
        XCTAssertEqual(args.argumentString, "-c:v h264 -f mp4 -loglevel warning")
    }

    func testAudioArgsBitRateNone() {
        var settings = defaultSettings()
        settings.audioBitRate = .none
        let args = FFmpegArguments.audioArgs(settings: settings)
        XCTAssertEqual(args.argumentString, "-c:a aac -f mp4 -loglevel warning")
    }

    func testUserOptionsOverrideKeepsPosition() {
        var settings = defaultSettings()
        settings.videoOptions = "-c:v libx264 -b 5000"
        let args = FFmpegArguments.videoArgs(settings: settings)
        // b:v は基礎項目の位置のまま値だけ差し替わる
        XCTAssertEqual(args.argumentString, "-b:v 5000 -c:v libx264 -f mp4 -loglevel warning")
    }

    func testKeyNormalizationAliases() {
        var settings = defaultSettings()
        settings.videoOptions = "-codec:v libvpx -qscale 5"
        let args = FFmpegArguments.videoArgs(settings: settings)
        XCTAssertEqual(
            args.argumentString,
            "-b:v 10000000 -c:v libvpx -q:v 5 -f mp4 -loglevel warning"
        )
    }

    func testNormalizeKbString() {
        XCTAssertEqual(FFmpegArguments.normalizeKbString("192k"), "192000")
        XCTAssertEqual(FFmpegArguments.normalizeKbString("2M"), "2000000")
        XCTAssertEqual(FFmpegArguments.normalizeKbString("100kib"), "819200")
        // "i" でないためビット換算フラグが取り消される癖
        XCTAssertEqual(FFmpegArguments.normalizeKbString("100kb"), "100000")
        XCTAssertEqual(FFmpegArguments.normalizeKbString("5000"), "5000")
        XCTAssertEqual(FFmpegArguments.normalizeKbString("abc"), "abc")
    }

    func testSettingsFromVideoInfo() {
        let settings = FFmpegExportSettings(
            videoInfo: VideoInfo(fps: 60, hz: 44_100, width: 1280, height: 720), length: 42
        )
        XCTAssertEqual(settings.fps, 60)
        XCTAssertEqual(settings.hz, 44_100)
        XCTAssertEqual(settings.width, 1280)
        XCTAssertEqual(settings.height, 720)
        XCTAssertEqual(settings.length, 42)
        XCTAssertEqual(settings.videoBitRate, 10_000)
        XCTAssertEqual(settings.videoQuality, 55)
        XCTAssertEqual(settings.audioBitRate, .kb192)
    }
}

// MARK: - プロセス引数とレイアウト

final class FFmpegCommandTests: XCTestCase {
    private func defaultSettings() -> FFmpegExportSettings {
        FFmpegExportSettings(width: 1920, height: 1080, fps: 30, hz: 48_000, length: 300)
    }

    private func defaultLayout() -> FFmpegOutputLayout {
        let settings = defaultSettings()
        return FFmpegOutputLayout.resolve(
            outputPath: "/tmp/out.mp4",
            audioArgs: FFmpegArguments.audioArgs(settings: settings),
            videoArgs: FFmpegArguments.videoArgs(settings: settings)
        )
    }

    func testDefaultLayoutUsesTempFiles() {
        let layout = defaultLayout()
        XCTAssertTrue(layout.hasTempFiles)
        XCTAssertFalse(layout.skipsAudioProcess)
        XCTAssertFalse(layout.skipsVideo)
        XCTAssertEqual(layout.audioTargetPath, "/tmp/out.mp4.audio.tmp")
        XCTAssertEqual(layout.videoTargetPath, "/tmp/out.mp4.video.tmp")
    }

    func testAudioProcessArguments() {
        let settings = defaultSettings()
        XCTAssertEqual(
            FFmpegArguments.audioProcessArguments(settings: settings, layout: defaultLayout()),
            [
                "-f", "f32le", "-ar", "48000", "-ac", "2", "-i", "-",
                "-b:a", "192000", "-c:a", "aac", "-f", "mp4", "-loglevel", "warning",
                "-y", "/tmp/out.mp4.audio.tmp",
            ]
        )
    }

    func testVideoProcessArgumentsNV12DeclaresColor() {
        let settings = defaultSettings()
        XCTAssertEqual(
            FFmpegArguments.videoProcessArguments(
                settings: settings, layout: defaultLayout(), useNV12: true
            ),
            [
                "-f", "rawvideo", "-pix_fmt", "nv12",
                "-colorspace", "bt709", "-color_primaries", "bt709",
                "-color_trc", "bt709", "-color_range", "tv",
                "-s", "1920x1080", "-r", "30", "-i", "-",
                "-b:v", "10000000", "-c:v", "h264", "-f", "mp4", "-loglevel", "warning",
                "-y", "/tmp/out.mp4.video.tmp",
            ]
        )
    }

    func testVideoProcessArgumentsBGRAHasNoColorMetadata() {
        var settings = defaultSettings()
        settings.videoOptions = "-c:v prores"
        let layout = FFmpegOutputLayout.resolve(
            outputPath: "/tmp/out.mp4",
            audioArgs: FFmpegArguments.audioArgs(settings: settings),
            videoArgs: FFmpegArguments.videoArgs(settings: settings)
        )
        let arguments = FFmpegArguments.videoProcessArguments(
            settings: settings, layout: layout, useNV12: false
        )
        XCTAssertEqual(
            arguments,
            [
                "-f", "rawvideo", "-pix_fmt", "bgra",
                "-s", "1920x1080", "-r", "30", "-i", "-",
                "-b:v", "10000000", "-c:v", "prores", "-f", "mp4", "-loglevel", "warning",
                "-y", "/tmp/out.mp4.video.tmp",
            ]
        )
        XCTAssertFalse(arguments.contains("-colorspace"))
    }

    func testMuxProcessArguments() {
        XCTAssertEqual(
            FFmpegArguments.muxProcessArguments(layout: defaultLayout(), outputPath: "/tmp/out.mp4"),
            [
                "-i", "/tmp/out.mp4.audio.tmp",
                "-i", "/tmp/out.mp4.video.tmp",
                "-c", "copy", "-loglevel", "warning",
                "-y", "/tmp/out.mp4",
            ]
        )
    }

    func testLayoutSkipVideoPreset() {
        // MP3 プリセット相当: 映像側が -f null
        var settings = defaultSettings()
        settings.audioOptions = "-c mp3 -f mp3"
        settings.videoOptions = "-f null"
        let layout = FFmpegOutputLayout.resolve(
            outputPath: "/tmp/out.mp3",
            audioArgs: FFmpegArguments.audioArgs(settings: settings),
            videoArgs: FFmpegArguments.videoArgs(settings: settings)
        )
        XCTAssertTrue(layout.skipsVideo)
        XCTAssertFalse(layout.skipsAudioProcess)
        XCTAssertFalse(layout.hasTempFiles)
        XCTAssertEqual(layout.audioTargetPath, "/tmp/out.mp3")
    }

    func testLayoutSkipAudioPreset() {
        // GIF プリセット相当: 音声側が -f null
        var settings = defaultSettings()
        settings.audioOptions = "-f null"
        let layout = FFmpegOutputLayout.resolve(
            outputPath: "/tmp/out.gif",
            audioArgs: FFmpegArguments.audioArgs(settings: settings),
            videoArgs: FFmpegArguments.videoArgs(settings: settings)
        )
        XCTAssertTrue(layout.skipsAudioProcess)
        XCTAssertFalse(layout.hasTempFiles)
        XCTAssertEqual(layout.videoTargetPath, "/tmp/out.gif")
    }

    func testIsYUVCodec() {
        XCTAssertTrue(FFmpegArguments.isYUVCodec("h264"))
        XCTAssertTrue(FFmpegArguments.isYUVCodec("libx265"))
        XCTAssertTrue(FFmpegArguments.isYUVCodec("hevc"))
        XCTAssertTrue(FFmpegArguments.isYUVCodec("libsvtav1"))
        XCTAssertTrue(FFmpegArguments.isYUVCodec("vp9"))
        XCTAssertFalse(FFmpegArguments.isYUVCodec("prores"))
        XCTAssertFalse(FFmpegArguments.isYUVCodec("gif"))
    }
}

// MARK: - 範囲とサンプル件数

final class ExportRangeAndCountTests: XCTestCase {
    func testRangeNormalization() {
        XCTAssertEqual(ExportRange.normalized(from: 10, to: 50, timelineLength: 40), 10..<40)
        XCTAssertEqual(ExportRange.normalized(from: 50, to: 10, timelineLength: 40), 10..<40)
        XCTAssertEqual(ExportRange.normalized(from: -5, to: 3, timelineLength: 100), 0..<3)
        XCTAssertEqual(ExportRange.normalized(from: 0, to: 10, timelineLength: 0), 0..<0)
    }

    func testSampleCountsDistributeRemainder() {
        // Hz=11025, FPS=30: 累積式で端数がフレーム間に配分される
        let counts = (0..<4).map {
            ExportAudioSampleCount.count(forFrame: $0, hz: 11_025, fps: 30)
        }
        XCTAssertEqual(counts, [734, 736, 734, 736])
    }

    func testSampleCountsEvenDivision() {
        let counts = (0..<3).map {
            ExportAudioSampleCount.count(forFrame: $0, hz: 48_000, fps: 30)
        }
        XCTAssertEqual(counts, [3200, 3200, 3200])
    }
}

// MARK: - ラウドネス

final class LoudnessAnalysisTests: XCTestCase {
    private func constantChunks(amplitude: Float, count: Int = 3, length: Int = 3200)
        -> [LoudnessAnalysis.FrameChunk]
    {
        (0..<count).map { _ in
            LoudnessAnalysis.FrameChunk(
                samples: [Float](repeating: amplitude, count: length), readCount: length
            )
        }
    }

    private func silenceChunks(count: Int = 30) -> [LoudnessAnalysis.FrameChunk] {
        constantChunks(amplitude: 0, count: count)
    }

    func testSilenceDownOnly() {
        let result = LoudnessAnalysis.analyze(
            chunks: silenceChunks(),
            loudness: LoudnessNormalizationSettings(mode: .downOnly),
            compressor: CompressorSettings(),
            hz: 48_000
        )
        XCTAssertTrue(result.analysisPerformed)
        XCTAssertEqual(result.averageLoudness, -60, accuracy: 0.01)
        // fix = min(0, -15 - (-60)) = 0 なので倍率は 1
        XCTAssertEqual(result.volumeRate, 1, accuracy: 0.0001)
    }

    func testSilenceBothBoostsToTarget() {
        let result = LoudnessAnalysis.analyze(
            chunks: silenceChunks(),
            loudness: LoudnessNormalizationSettings(mode: .both),
            compressor: CompressorSettings(),
            hz: 48_000
        )
        XCTAssertEqual(result.loudnessFix, 45, accuracy: 0.01)
        XCTAssertEqual(result.volumeRate, 177.83, accuracy: 1.0)
    }

    func testDisabledCustomSkipsAnalysis() {
        let result = LoudnessAnalysis.analyze(
            chunks: constantChunks(amplitude: 2.0),
            loudness: LoudnessNormalizationSettings(mode: .disabled),
            compressor: CompressorSettings(ratioMode: .custom, ratio: 2.5),
            hz: 48_000
        )
        XCTAssertFalse(result.analysisPerformed)
        XCTAssertEqual(result.compressorRate, 2.5, accuracy: 0.0001)
        XCTAssertEqual(result.volumeRate, 1, accuracy: 0.0001)
    }

    func testDisabledDisabledDoesNothing() {
        let result = LoudnessAnalysis.analyze(
            chunks: constantChunks(amplitude: 2.0),
            loudness: LoudnessNormalizationSettings(mode: .disabled),
            compressor: CompressorSettings(ratioMode: .disabled),
            hz: 48_000
        )
        XCTAssertFalse(result.analysisPerformed)
        XCTAssertEqual(result.compressorRate, 1, accuracy: 0.0001)
    }

    func testDownMaximumVolumeBelowZeroDbIsUnity() {
        let result = LoudnessAnalysis.analyze(
            chunks: constantChunks(amplitude: 0.5),
            loudness: LoudnessNormalizationSettings(mode: .downMaximumVolume),
            compressor: CompressorSettings(),
            hz: 48_000
        )
        // ピーク -6.02 dB は max(peakDb, 0) で 0 扱いになり倍率 1
        XCTAssertEqual(result.volumeRate, 1, accuracy: 0.0001)
    }

    func testDownMaximumVolumeAboveZeroDb() {
        let result = LoudnessAnalysis.analyze(
            chunks: constantChunks(amplitude: 2.0),
            loudness: LoudnessNormalizationSettings(mode: .downMaximumVolume),
            compressor: CompressorSettings(),
            hz: 48_000
        )
        XCTAssertEqual(result.volumeRate, 0.5, accuracy: 0.01)
    }

    func testUpDownMaximumVolumeBoosts() {
        let result = LoudnessAnalysis.analyze(
            chunks: constantChunks(amplitude: 0.5),
            loudness: LoudnessNormalizationSettings(mode: .upDownMaximumVolume),
            compressor: CompressorSettings(),
            hz: 48_000
        )
        XCTAssertEqual(result.volumeRate, 2.0, accuracy: 0.01)
    }

    func testPeakModesNeverReachAutoCompressor() {
        // 本家の if / else-if 構造の回帰: モード 3/4 では Auto 分岐に
        // 到達せず compressorRate は初期値 1 のまま
        let result = LoudnessAnalysis.analyze(
            chunks: constantChunks(amplitude: 2.0),
            loudness: LoudnessNormalizationSettings(mode: .downMaximumVolume),
            compressor: CompressorSettings(ratioMode: .auto),
            hz: 48_000
        )
        XCTAssertEqual(result.compressorRate, 1, accuracy: 0.0001)
        XCTAssertEqual(result.volumeRate, 0.5, accuracy: 0.01)
    }

    func testAutoCompressorRateFromPeak() {
        let result = LoudnessAnalysis.analyze(
            chunks: constantChunks(amplitude: 2.0),
            loudness: LoudnessNormalizationSettings(mode: .disabled),
            compressor: CompressorSettings(ratioMode: .auto),
            hz: 48_000
        )
        // (6.0206 - (-18)) / (-0.2 - (-18)) = 24.0206 / 17.8
        XCTAssertEqual(result.compressorRate, 1.3495, accuracy: 0.01)
    }

    func testAutoCompressorBelowLimitIsUnity() {
        let result = LoudnessAnalysis.analyze(
            chunks: constantChunks(amplitude: 0.5),
            loudness: LoudnessNormalizationSettings(mode: .disabled),
            compressor: CompressorSettings(ratioMode: .auto),
            hz: 48_000
        )
        XCTAssertEqual(result.compressorRate, 1, accuracy: 0.0001)
    }

    func testPeakIgnoresUnreadTail() {
        // readCount の範囲外にあるピークはピーク測定に入らない (W6-6.3)
        var samples = [Float](repeating: 0, count: 3200)
        samples[2000] = 2.0
        let result = LoudnessAnalysis.analyze(
            chunks: [LoudnessAnalysis.FrameChunk(samples: samples, readCount: 1600)],
            loudness: LoudnessNormalizationSettings(mode: .downMaximumVolume),
            compressor: CompressorSettings(),
            hz: 48_000
        )
        XCTAssertEqual(result.volumeRate, 1, accuracy: 0.0001)
    }

    private func sineChunks(amplitude: Float, seconds: Int, hz: Int = 48_000)
        -> [LoudnessAnalysis.FrameChunk]
    {
        var samples: [Float] = []
        samples.reserveCapacity(seconds * hz * 2)
        for frame in 0..<(seconds * hz) {
            let value = amplitude * sinf(2 * Float.pi * 1000 * Float(frame) / Float(hz))
            samples.append(value)
            samples.append(value)
        }
        let stream = FileAudioStream(
            provider: InMemoryPCMProvider(samples: samples, hz: hz)
        )
        return LoudnessAnalysis.makeChunks(from: stream, frameCount: seconds * 30, hz: hz, fps: 30)
    }

    func testAnalyzerLoudnessIsLinearInDb() {
        let loud = LoudnessAnalysis.analyze(
            chunks: sineChunks(amplitude: 1.0, seconds: 3),
            loudness: LoudnessNormalizationSettings(mode: .both),
            compressor: CompressorSettings(ratioMode: .disabled),
            hz: 48_000
        )
        let quiet = LoudnessAnalysis.analyze(
            chunks: sineChunks(amplitude: 0.1, seconds: 3),
            loudness: LoudnessNormalizationSettings(mode: .both),
            compressor: CompressorSettings(ratioMode: .disabled),
            hz: 48_000
        )
        XCTAssertEqual(
            loud.averageLoudness - quiet.averageLoudness, 20, accuracy: 1.5
        )
    }

    func testRelativeGateExcludesSilence() {
        // 大音量 1 秒 + 無音 3 秒。相対ゲートで無音ブロックが落ち、
        // 統合値は大音量部分に寄る
        var chunks = sineChunks(amplitude: 1.0, seconds: 1)
        chunks += LoudnessAnalysis.makeChunks(
            from: FileAudioStream(
                provider: InMemoryPCMProvider(
                    samples: [Float](repeating: 0, count: 48_000 * 2 * 3), hz: 48_000
                )
            ),
            frameCount: 90, hz: 48_000, fps: 30
        )
        let result = LoudnessAnalysis.analyze(
            chunks: chunks,
            loudness: LoudnessNormalizationSettings(mode: .both),
            compressor: CompressorSettings(ratioMode: .disabled),
            hz: 48_000
        )
        XCTAssertGreaterThan(result.averageLoudness, -8)
        XCTAssertLessThan(result.averageLoudness, 0)
    }

    func testMakeChunksUsesFixedLengthWithZeroPadding() {
        // 素材が 1 フレーム分に満たない場合も配列長は固定で尾部は 0
        let stream = FileAudioStream(
            provider: InMemoryPCMProvider(
                samples: [Float](repeating: 0.5, count: 1000), hz: 48_000
            )
        )
        let chunks = LoudnessAnalysis.makeChunks(from: stream, frameCount: 2, hz: 48_000, fps: 30)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].samples.count, 3200)
        XCTAssertEqual(chunks[0].readCount, 1000)
        XCTAssertEqual(chunks[0].samples[999], 0.5)
        XCTAssertEqual(chunks[0].samples[1000], 0)
        XCTAssertEqual(chunks[1].readCount, 0)
    }

    // MARK: - 解析計画とストリーミング（MAC-0030、EX17-05 / EX17-06）

    private final class CountingProvider: PCMProvider {
        private let base: InMemoryPCMProvider
        private(set) var readCalls = 0

        init(samples: [Float], hz: Int) {
            base = InMemoryPCMProvider(samples: samples, hz: hz)
        }

        var hz: Int { base.hz }
        var duration: TimeSpanValue { base.duration }

        func seek(toTime time: TimeSpanValue) {
            base.seek(toTime: time)
        }

        func read(into buffer: inout [Float], offset: Int, count: Int) -> Int {
            readCalls += 1
            return base.read(into: &buffer, offset: offset, count: count)
        }
    }

    func testAnalysisPlanSkipsReadingForDisabledCombinations() {
        // 本家 W6-6.1: Loudness=Disabled かつ Compressor=Disabled /
        // Custom では音声を読み直さない
        let disabledCustom = LoudnessAnalysis.plan(
            loudness: LoudnessNormalizationSettings(mode: .disabled),
            compressor: CompressorSettings(ratioMode: .custom, ratio: 2.5)
        )
        XCTAssertFalse(disabledCustom.requiresReading)
        XCTAssertEqual(disabledCustom.compressorRate, 2.5, accuracy: 0.0001)

        let disabledDisabled = LoudnessAnalysis.plan(
            loudness: LoudnessNormalizationSettings(mode: .disabled),
            compressor: CompressorSettings(ratioMode: .disabled)
        )
        XCTAssertFalse(disabledDisabled.requiresReading)
        XCTAssertEqual(disabledDisabled.compressorRate, 1, accuracy: 0.0001)

        let disabledAuto = LoudnessAnalysis.plan(
            loudness: LoudnessNormalizationSettings(mode: .disabled),
            compressor: CompressorSettings(ratioMode: .auto)
        )
        XCTAssertTrue(disabledAuto.requiresReading)

        let peakMode = LoudnessAnalysis.plan(
            loudness: LoudnessNormalizationSettings(mode: .downMaximumVolume),
            compressor: CompressorSettings(ratioMode: .disabled)
        )
        XCTAssertTrue(peakMode.requiresReading)
    }

    func testStreamingAnalyzeDoesNotReadWhenPlanSkips() {
        let provider = CountingProvider(
            samples: [Float](repeating: 0.5, count: 48_000 * 2), hz: 48_000
        )
        let stream = FileAudioStream(provider: provider)
        let result = LoudnessAnalysis.analyze(
            stream: stream, frameCount: 30,
            loudness: LoudnessNormalizationSettings(mode: .disabled),
            compressor: CompressorSettings(ratioMode: .custom, ratio: 2.5),
            hz: 48_000, fps: 30
        )
        XCTAssertEqual(provider.readCalls, 0)
        XCTAssertFalse(result.analysisPerformed)
        XCTAssertEqual(result.compressorRate, 2.5, accuracy: 0.0001)
        XCTAssertEqual(result.volumeRate, 1, accuracy: 0.0001)
    }

    func testStreamingAnalysisMatchesChunkAnalysis() {
        // ストリーミング版とチャンク列版（テスト補助）で、ピーク・
        // LKFS・倍率が一致すること
        func sineSamples() -> [Float] {
            var samples: [Float] = []
            samples.reserveCapacity(3 * 48_000 * 2)
            for frame in 0..<(3 * 48_000) {
                let value = 0.8 * sinf(2 * Float.pi * 1000 * Float(frame) / 48_000)
                samples.append(value)
                samples.append(value)
            }
            return samples
        }
        let configurations: [(LoudnessNormalizationSettings, CompressorSettings)] = [
            (
                LoudnessNormalizationSettings(mode: .both),
                CompressorSettings(ratioMode: .disabled)
            ),
            (
                LoudnessNormalizationSettings(mode: .downMaximumVolume),
                CompressorSettings(ratioMode: .auto)
            ),
            (
                LoudnessNormalizationSettings(mode: .disabled),
                CompressorSettings(ratioMode: .auto)
            ),
        ]
        for (loudness, compressor) in configurations {
            let chunkResult = LoudnessAnalysis.analyze(
                chunks: LoudnessAnalysis.makeChunks(
                    from: FileAudioStream(
                        provider: InMemoryPCMProvider(samples: sineSamples(), hz: 48_000)
                    ),
                    frameCount: 90, hz: 48_000, fps: 30
                ),
                loudness: loudness, compressor: compressor, hz: 48_000
            )
            let streamResult = LoudnessAnalysis.analyze(
                stream: FileAudioStream(
                    provider: InMemoryPCMProvider(samples: sineSamples(), hz: 48_000)
                ),
                frameCount: 90,
                loudness: loudness, compressor: compressor, hz: 48_000, fps: 30
            )
            XCTAssertEqual(streamResult.analysisPerformed, chunkResult.analysisPerformed)
            XCTAssertEqual(streamResult.peakDb, chunkResult.peakDb, accuracy: 0.0001)
            XCTAssertEqual(
                streamResult.averageLoudness, chunkResult.averageLoudness, accuracy: 0.0001
            )
            XCTAssertEqual(streamResult.volumeRate, chunkResult.volumeRate, accuracy: 0.0001)
            XCTAssertEqual(
                streamResult.compressorRate, chunkResult.compressorRate, accuracy: 0.0001
            )
            XCTAssertEqual(streamResult.loudnessFix, chunkResult.loudnessFix, accuracy: 0.0001)
        }
    }
}

// MARK: - DynamicsProcessor

final class DynamicsProcessorTests: XCTestCase {
    private func constantStream(_ value: Float, frames: Int) -> FileAudioStream {
        FileAudioStream(
            provider: InMemoryPCMProvider(
                samples: [Float](repeating: value, count: frames * 2), hz: 48_000
            )
        )
    }

    func testRatioOneFastPathMultipliesExactly() {
        let processor = DynamicsProcessorStream(
            input: constantStream(0.25, frames: 48_000),
            volume: 2, threshold: -18, ratio: 1,
            attack: 0.006, release: 0.06, isLookAheadEnabled: true
        )
        var buffer = [Float](repeating: 0, count: 100)
        let read = processor.read(into: &buffer, offset: 0, count: 100)
        XCTAssertEqual(read, 100)
        for value in buffer {
            XCTAssertEqual(value, 0.5, accuracy: 0.0001)
        }
    }

    func testSeekResetsFastPath() {
        let processor = DynamicsProcessorStream(
            input: constantStream(0.25, frames: 48_000),
            volume: 2, threshold: -18, ratio: 1,
            attack: 0.006, release: 0.06, isLookAheadEnabled: true
        )
        var buffer = [Float](repeating: 0, count: 100)
        _ = processor.read(into: &buffer, offset: 0, count: 100)
        processor.seek(to: 0)
        var second = [Float](repeating: 0, count: 100)
        let read = processor.read(into: &second, offset: 0, count: 100)
        XCTAssertEqual(read, 100)
        XCTAssertEqual(second[0], 0.5, accuracy: 0.0001)
    }

    func testCompressorSilenceStaysSilence() {
        let processor = DynamicsProcessorStream(
            input: constantStream(0, frames: 48_000),
            volume: 1, threshold: -18, ratio: 4,
            attack: 0.006, release: 0.06, isLookAheadEnabled: true
        )
        var buffer = [Float](repeating: 1, count: 1000)
        let read = processor.read(into: &buffer, offset: 0, count: 1000)
        XCTAssertEqual(read, 1000)
        for value in buffer {
            XCTAssertEqual(value, 0, accuracy: 0.0001)
        }
    }

    func testCompressorReducesSteadyLoudSignal() {
        let processor = DynamicsProcessorStream(
            input: constantStream(2.0, frames: 48_000),
            volume: 1, threshold: -18, ratio: 4,
            attack: 0.006, release: 0.06, isLookAheadEnabled: true
        )
        var buffer = [Float](repeating: 0, count: 3200)
        var total = 0
        while total < 48_000 {
            let read = processor.read(into: &buffer, offset: 0, count: 3200)
            if read <= 0 { break }
            total += read
        }
        XCTAssertEqual(total, 48_000)
        // 定常状態では利得が下がり、入力 2.0 より十分小さい値に収まる
        let tail = buffer.suffix(200)
        for value in tail {
            XCTAssertLessThan(abs(value), 0.6)
            XCTAssertGreaterThan(abs(value), 0.05)
        }
    }
}

// MARK: - セッション状態機械

private enum FakeFailure: Error {
    case boom
}

private final class FakeWriter: VideoFileWriting {
    var supportedStreams: VideoWriterSupportedStreams
    var isGPUFrameSupported = false
    var producesOutputFileValue = true
    var producesOutputFile: Bool { producesOutputFileValue }
    var videoBufferIdentifiers: [ObjectIdentifier] = []
    var audioCounts: [Int] = []
    var finalizeCount = 0
    var throwOnVideoCall: Int?
    var throwOnAudioCall: Int?
    var finalizeError: Error?

    init(supportedStreams: VideoWriterSupportedStreams = [.video, .audio]) {
        self.supportedStreams = supportedStreams
    }

    func writeVideoFrame(_ frame: ExportVideoFrameBuffer) throws {
        if throwOnVideoCall == videoBufferIdentifiers.count { throw FakeFailure.boom }
        videoBufferIdentifiers.append(ObjectIdentifier(frame))
    }

    func writeAudioSamples(_ samples: [Float]) throws {
        if throwOnAudioCall == audioCounts.count { throw FakeFailure.boom }
        audioCounts.append(samples.count)
    }

    func finalize() throws {
        finalizeCount += 1
        if let finalizeError { throw finalizeError }
    }
}

private final class FakeVideoProvider: VideoFrameProviding {
    var fillCount = 0
    var bufferIdentifiers: [ObjectIdentifier] = []
    var bufferByteCount = 0
    var throwOnFrame: Int?

    func fillFrame(_ frame: Int, into buffer: ExportVideoFrameBuffer) throws {
        if throwOnFrame == frame { throw FakeFailure.boom }
        fillCount += 1
        bufferIdentifiers.append(ObjectIdentifier(buffer))
        bufferByteCount = buffer.bytes.count
    }
}

private final class FakeAudioProvider: AudioFrameProviding {
    let hz: Int
    let fps: Int
    var requestedFrames: [Int] = []
    var throwOnFrame: Int?

    init(hz: Int, fps: Int) {
        self.hz = hz
        self.fps = fps
    }

    func audioSamples(forFrame frame: Int) throws -> [Float] {
        if throwOnFrame == frame { throw FakeFailure.boom }
        requestedFrames.append(frame)
        let count = ExportAudioSampleCount.count(forFrame: frame, hz: hz, fps: fps)
        return [Float](repeating: 0, count: count)
    }
}

private final class FlagBox: @unchecked Sendable {
    var value = false
}

final class ExportSessionTests: XCTestCase {
    private func configuration(
        frames: Int = 5, accompanying: (@Sendable (String) throws -> Void)? = nil
    ) -> ExportSession.Configuration {
        ExportSession.Configuration(
            outputPath: "/tmp/out.mp4",
            videoInfo: VideoInfo(fps: 30, hz: 11_025, width: 64, height: 64),
            frameRange: 0..<frames,
            accompanyingFiles: accompanying
        )
    }

    func testNormalCompletion() {
        let writer = FakeWriter()
        let video = FakeVideoProvider()
        let audio = FakeAudioProvider(hz: 11_025, fps: 30)
        let flag = FlagBox()
        let session = ExportSession(writer: writer)
        let outcome = session.run(
            configuration: configuration(accompanying: { _ in flag.value = true }),
            videoProvider: video,
            audioProvider: audio
        )
        XCTAssertEqual(outcome.completion, .completed)
        XCTAssertEqual(outcome.framesWritten, 5)
        XCTAssertTrue(outcome.finalizeInvoked)
        XCTAssertTrue(outcome.outputProduced)
        XCTAssertTrue(outcome.accompanyingFilesProduced)
        XCTAssertTrue(flag.value)
        XCTAssertEqual(writer.finalizeCount, 1)
        // 借用バッファは全フレームで同一インスタンス
        XCTAssertEqual(Set(video.bufferIdentifiers).count, 1)
        XCTAssertEqual(Set(writer.videoBufferIdentifiers).count, 1)
        XCTAssertEqual(video.bufferIdentifiers, writer.videoBufferIdentifiers)
        XCTAssertEqual(video.bufferByteCount, 64 * 64 * 4)
        // 音声は累積式どおりの件数でフレームごとに渡る
        XCTAssertEqual(writer.audioCounts, [734, 736, 734, 736, 734])
    }

    func testCancellationStillFinalizesAndProducesAccompanying() {
        let writer = FakeWriter()
        let flag = FlagBox()
        let session = ExportSession(writer: writer)
        var checks = 0
        let outcome = session.run(
            configuration: configuration(accompanying: { _ in flag.value = true }),
            videoProvider: FakeVideoProvider(),
            audioProvider: FakeAudioProvider(hz: 11_025, fps: 30),
            isCancelled: {
                checks += 1
                return checks > 3
            }
        )
        XCTAssertEqual(outcome.completion, .cancelled)
        XCTAssertEqual(outcome.framesWritten, 3)
        XCTAssertTrue(outcome.finalizeInvoked)
        XCTAssertTrue(outcome.outputProduced)
        XCTAssertTrue(outcome.accompanyingFilesProduced)
        XCTAssertEqual(writer.finalizeCount, 1)
    }

    func testProviderFailureSkipsAccompanyingButFinalizes() {
        let writer = FakeWriter()
        let video = FakeVideoProvider()
        video.throwOnFrame = 2
        let flag = FlagBox()
        let session = ExportSession(writer: writer)
        let outcome = session.run(
            configuration: configuration(accompanying: { _ in flag.value = true }),
            videoProvider: video,
            audioProvider: FakeAudioProvider(hz: 11_025, fps: 30)
        )
        XCTAssertEqual(outcome.completion, .failed)
        XCTAssertEqual(outcome.framesWritten, 2)
        XCTAssertTrue(outcome.finalizeInvoked)
        XCTAssertFalse(outcome.accompanyingFilesProduced)
        XCTAssertFalse(flag.value)
        XCTAssertNotNil(outcome.error)
        XCTAssertEqual(writer.finalizeCount, 1)
    }

    func testWriterFailureFinalizesOnce() {
        let writer = FakeWriter()
        writer.throwOnAudioCall = 1
        let session = ExportSession(writer: writer)
        let outcome = session.run(
            configuration: configuration(),
            videoProvider: FakeVideoProvider(),
            audioProvider: FakeAudioProvider(hz: 11_025, fps: 30)
        )
        XCTAssertEqual(outcome.completion, .failed)
        XCTAssertEqual(outcome.framesWritten, 1)
        XCTAssertEqual(writer.finalizeCount, 1)
    }

    func testFinalizeFailureIsReported() {
        let writer = FakeWriter()
        writer.finalizeError = FakeFailure.boom
        let session = ExportSession(writer: writer)
        let outcome = session.run(
            configuration: configuration(),
            videoProvider: FakeVideoProvider(),
            audioProvider: FakeAudioProvider(hz: 11_025, fps: 30)
        )
        XCTAssertEqual(outcome.completion, .failed)
        XCTAssertTrue(outcome.finalizeInvoked)
        XCTAssertFalse(outcome.outputProduced)
        XCTAssertNotNil(outcome.error)
    }

    func testAccompanyingFailureBecomesWarning() {
        let writer = FakeWriter()
        let session = ExportSession(writer: writer)
        let outcome = session.run(
            configuration: configuration(accompanying: { _ in throw FakeFailure.boom }),
            videoProvider: FakeVideoProvider(),
            audioProvider: FakeAudioProvider(hz: 11_025, fps: 30)
        )
        XCTAssertEqual(outcome.completion, .completed)
        XCTAssertTrue(outcome.outputProduced)
        XCTAssertFalse(outcome.accompanyingFilesProduced)
        XCTAssertNil(outcome.error)
        XCTAssertNotNil(outcome.warning)
        // 副次的かどうかは置き場所で表し、原因分類は包んだまま保持する（EX17-08）
        XCTAssertEqual(outcome.warning?.cause, .unresolvable)
    }

    func testFinalizeSuccessWithoutOutputFileIsDistinguished() {
        // 両ストリーム無効の writer: finalize は成功するが成果物は無い。
        // 「確定処理成功」と「成果物あり」を区別する（EX17-07）。
        let writer = FakeWriter()
        writer.producesOutputFileValue = false
        let session = ExportSession(writer: writer)
        let outcome = session.run(
            configuration: configuration(),
            videoProvider: FakeVideoProvider(),
            audioProvider: FakeAudioProvider(hz: 11_025, fps: 30)
        )
        XCTAssertEqual(outcome.completion, .completed)
        XCTAssertTrue(outcome.finalizeInvoked)
        XCTAssertTrue(outcome.finalizeSucceeded)
        XCTAssertFalse(outcome.outputProduced)
        XCTAssertNil(outcome.error)
    }

    func testActionableFinalizeErrorStillFails() {
        // 原因が対処可能でも finalize の失敗は書き出しの失敗である。
        // 対処可能性と成否は別の軸（EX17-08。是正前はこの組み合わせが
        // 「警告」として返っていた）。
        let writer = FakeWriter()
        writer.finalizeError = ExportError(
            cause: .actionable, message: "ストレージの空き容量が不足しています"
        )
        let session = ExportSession(writer: writer)
        let outcome = session.run(
            configuration: configuration(),
            videoProvider: FakeVideoProvider(),
            audioProvider: FakeAudioProvider(hz: 11_025, fps: 30)
        )
        XCTAssertEqual(outcome.completion, .failed)
        XCTAssertTrue(outcome.finalizeInvoked)
        XCTAssertFalse(outcome.finalizeSucceeded)
        XCTAssertFalse(outcome.outputProduced)
        XCTAssertEqual(outcome.error?.cause, .actionable)
    }

    func testAudioOnlyWriterNeverCallsVideoProvider() {
        let writer = FakeWriter(supportedStreams: [.audio])
        let video = FakeVideoProvider()
        let session = ExportSession(writer: writer)
        let outcome = session.run(
            configuration: configuration(),
            videoProvider: video,
            audioProvider: FakeAudioProvider(hz: 11_025, fps: 30)
        )
        XCTAssertEqual(outcome.completion, .completed)
        XCTAssertEqual(video.fillCount, 0)
        XCTAssertEqual(writer.audioCounts.count, 5)
    }

    func testSecondRunIsRejectedWithoutFinalize() {
        let writer = FakeWriter()
        let session = ExportSession(writer: writer)
        _ = session.run(
            configuration: configuration(),
            videoProvider: FakeVideoProvider(),
            audioProvider: FakeAudioProvider(hz: 11_025, fps: 30)
        )
        let second = session.run(
            configuration: configuration(),
            videoProvider: FakeVideoProvider(),
            audioProvider: FakeAudioProvider(hz: 11_025, fps: 30)
        )
        XCTAssertEqual(second.completion, .failed)
        XCTAssertFalse(second.finalizeInvoked)
        XCTAssertEqual(writer.finalizeCount, 1)
    }
}

// MARK: - FFmpeg プロセスライター（フェイクプロセス）

private final class EventLog: @unchecked Sendable {
    var events: [String] = []
}

private final class FakeProcessHandle: ExportProcessHandle {
    let label: String
    let log: EventLog
    var writtenData: [Data] = []
    var writeError: Error?
    var exitStatus: Int32 = 0
    var stderrText = ""
    var terminated = false

    init(label: String, log: EventLog) {
        self.label = label
        self.log = log
    }

    func writeToStandardInput(_ data: Data) throws {
        if let writeError { throw writeError }
        writtenData.append(data)
    }

    func closeStandardInput() {
        log.events.append("\(label).close")
    }

    func waitForExit() -> (terminationStatus: Int32, standardError: String) {
        log.events.append("\(label).wait")
        return (exitStatus, stderrText)
    }

    func terminate() {
        terminated = true
    }
}

private final class FakeProcessRunner: ExportProcessRunning {
    let log = EventLog()
    var launches: [(path: String, arguments: [String])] = []
    var handles: [FakeProcessHandle] = []
    var onLaunch: ((Int, FakeProcessHandle) -> Void)?
    var launchError: Error?

    func launch(executablePath: String, arguments: [String]) throws -> ExportProcessHandle {
        if let launchError { throw launchError }
        let index = launches.count
        launches.append((executablePath, arguments))
        let labels = ["audio", "video", "mux"]
        let handle = FakeProcessHandle(
            label: index < labels.count ? labels[index] : "p\(index)", log: log
        )
        handles.append(handle)
        log.events.append("launch.\(index)")
        onLaunch?(index, handle)
        return handle
    }
}

final class FFmpegProcessWriterTests: XCTestCase {
    private func smallSettings() -> FFmpegExportSettings {
        FFmpegExportSettings(width: 64, height: 64, fps: 30, hz: 48_000, length: 10)
    }

    func testInitLaunchesAudioProcessWithExactArguments() throws {
        let runner = FakeProcessRunner()
        _ = try FFmpegProcessWriter(
            settings: smallSettings(), outputPath: "/tmp/ymm4test/out.mp4", runner: runner
        )
        XCTAssertEqual(runner.launches.count, 1)
        XCTAssertEqual(runner.launches[0].path, "ffmpeg")
        XCTAssertEqual(
            runner.launches[0].arguments,
            [
                "-f", "f32le", "-ar", "48000", "-ac", "2", "-i", "-",
                "-b:a", "192000", "-c:a", "aac", "-f", "mp4", "-loglevel", "warning",
                "-y", "/tmp/ymm4test/out.mp4.audio.tmp",
            ]
        )
    }

    func testVideoProcessLaunchesLazilyWithNV12Arguments() throws {
        let runner = FakeProcessRunner()
        let writer = try FFmpegProcessWriter(
            settings: smallSettings(), outputPath: "/tmp/ymm4test/out.mp4", runner: runner
        )
        let frame = ExportVideoFrameBuffer(byteCount: 64 * 64 * 4)
        try writer.writeVideoFrame(frame)
        try writer.writeVideoFrame(frame)
        XCTAssertEqual(runner.launches.count, 2)
        XCTAssertEqual(
            runner.launches[1].arguments,
            [
                "-f", "rawvideo", "-pix_fmt", "nv12",
                "-colorspace", "bt709", "-color_primaries", "bt709",
                "-color_trc", "bt709", "-color_range", "tv",
                "-s", "64x64", "-r", "30", "-i", "-",
                "-b:v", "10000000", "-c:v", "h264", "-f", "mp4", "-loglevel", "warning",
                "-y", "/tmp/ymm4test/out.mp4.video.tmp",
            ]
        )
        // NV12 のデータ量は 64*64*3/2
        XCTAssertEqual(runner.handles[1].writtenData.count, 2)
        XCTAssertEqual(runner.handles[1].writtenData[0].count, 64 * 64 * 3 / 2)
    }

    func testAudioSamplesAreWrittenAsLittleEndianFloats() throws {
        let runner = FakeProcessRunner()
        let writer = try FFmpegProcessWriter(
            settings: smallSettings(), outputPath: "/tmp/ymm4test/out.mp4", runner: runner
        )
        try writer.writeAudioSamples([1.0, -1.0, 0.5])
        XCTAssertEqual(
            runner.handles[0].writtenData,
            [Data([0, 0, 0x80, 0x3F, 0, 0, 0x80, 0xBF, 0, 0, 0, 0x3F])]
        )
    }

    func testFinalizeOrderAndMux() throws {
        let runner = FakeProcessRunner()
        let writer = try FFmpegProcessWriter(
            settings: smallSettings(), outputPath: "/tmp/ymm4test/out.mp4", runner: runner
        )
        try writer.writeVideoFrame(ExportVideoFrameBuffer(byteCount: 64 * 64 * 4))
        try writer.finalize()
        XCTAssertEqual(
            runner.log.events,
            [
                "launch.0", "launch.1",
                "video.close", "video.wait",
                "audio.close", "audio.wait",
                "launch.2", "mux.close", "mux.wait",
            ]
        )
        XCTAssertEqual(
            runner.launches[2].arguments,
            [
                "-i", "/tmp/ymm4test/out.mp4.audio.tmp",
                "-i", "/tmp/ymm4test/out.mp4.video.tmp",
                "-c", "copy", "-loglevel", "warning",
                "-y", "/tmp/ymm4test/out.mp4",
            ]
        )
    }

    func testStoredWriteErrorPreventsMux() throws {
        let runner = FakeProcessRunner()
        runner.onLaunch = { index, handle in
            if index == 1 { handle.writeError = FakeFailure.boom }
        }
        let writer = try FFmpegProcessWriter(
            settings: smallSettings(), outputPath: "/tmp/ymm4test/out.mp4", runner: runner
        )
        let frame = ExportVideoFrameBuffer(byteCount: 64 * 64 * 4)
        XCTAssertThrowsError(try writer.writeVideoFrame(frame))
        XCTAssertTrue(runner.handles[1].terminated)
        XCTAssertThrowsError(try writer.finalize()) { error in
            XCTAssertTrue(error is ExportError)
        }
        XCTAssertEqual(runner.launches.count, 2)
    }

    func testExitCodeFailureIsClassifiedFromStderr() throws {
        let runner = FakeProcessRunner()
        runner.onLaunch = { index, handle in
            if index == 1 {
                handle.exitStatus = 1
                handle.stderrText = "Error: No space left on device"
            }
        }
        let writer = try FFmpegProcessWriter(
            settings: smallSettings(), outputPath: "/tmp/ymm4test/out.mp4", runner: runner
        )
        try writer.writeVideoFrame(ExportVideoFrameBuffer(byteCount: 64 * 64 * 4))
        XCTAssertThrowsError(try writer.finalize()) { error in
            let exportError = error as? ExportError
            XCTAssertEqual(exportError?.cause, .actionable)
            XCTAssertTrue(exportError?.message.contains("空き容量") ?? false)
        }
        // mux は起動しない
        XCTAssertEqual(runner.launches.count, 2)
    }

    func testSkipVideoPresetWritesAudioDirectlyToOutput() throws {
        var settings = smallSettings()
        settings.audioOptions = "-c mp3 -f mp3"
        settings.videoOptions = "-f null"
        let runner = FakeProcessRunner()
        let writer = try FFmpegProcessWriter(
            settings: settings, outputPath: "/tmp/ymm4test/out.mp3", runner: runner
        )
        XCTAssertEqual(runner.launches.count, 1)
        XCTAssertEqual(runner.launches[0].arguments.last, "/tmp/ymm4test/out.mp3")
        // 映像は受け取らない（プロセスも起動しない）
        try writer.writeVideoFrame(ExportVideoFrameBuffer(byteCount: 64 * 64 * 4))
        XCTAssertEqual(runner.launches.count, 1)
        try writer.finalize()
        XCTAssertEqual(runner.launches.count, 1)
    }

    func testBothStreamsNullProducesNoOutputFile() throws {
        // 音声・映像とも -f null: 申告は不変だが成果物は生じない（EX17-07）
        var settings = smallSettings()
        settings.audioOptions = "-f null"
        settings.videoOptions = "-f null"
        let runner = FakeProcessRunner()
        let writer = try FFmpegProcessWriter(
            settings: settings, outputPath: "/tmp/ymm4test/out.mp4", runner: runner
        )
        XCTAssertTrue(writer.supportedStreams.contains(.video))
        XCTAssertTrue(writer.supportedStreams.contains(.audio))
        XCTAssertFalse(writer.producesOutputFile)
        // 音声プロセスは起動せず、映像も受け取らない
        XCTAssertEqual(runner.launches.count, 0)
        try writer.writeAudioSamples([0.1, 0.2])
        try writer.writeVideoFrame(ExportVideoFrameBuffer(byteCount: 64 * 64 * 4))
        // finalize は成功する（例外なし）が mux も起動しない
        try writer.finalize()
        XCTAssertEqual(runner.launches.count, 0)
    }

    func testClassifierTable() {
        let cases: [(String, String)] = [
            ("Permission denied", "権限"),
            ("Unknown encoder 'foo'", "エンコーダー"),
            ("Could not find tag for codec", "コンテナ"),
            ("Unrecognized option 'x'", "オプション"),
            ("device failed", "ハードウェア"),
        ]
        for (stderr, fragment) in cases {
            let error = FFmpegErrorClassifier.classify(
                standardError: stderr, fallbackMessage: "fallback"
            )
            XCTAssertEqual(error.cause, .actionable, stderr)
            XCTAssertTrue(error.message.contains(fragment), stderr)
        }
        let unknown = FFmpegErrorClassifier.classify(
            standardError: "something else", fallbackMessage: "fallback"
        )
        XCTAssertEqual(unknown.cause, .unresolvable)
        XCTAssertEqual(unknown.message, "fallback")
    }
}

// MARK: - NV12 変換

final class NV12ConversionTests: XCTestCase {
    private func solidFrame(b: UInt8, g: UInt8, r: UInt8) -> [UInt8] {
        var frame: [UInt8] = []
        for _ in 0..<4 {
            frame.append(contentsOf: [b, g, r, 255])
        }
        return frame
    }

    func testWhiteAndBlack() {
        let white = NV12Conversion.convert(bgra: solidFrame(b: 255, g: 255, r: 255), width: 2, height: 2)
        XCTAssertEqual(white.count, 2 * 2 * 3 / 2)
        XCTAssertEqual(white[0], 235)
        XCTAssertEqual(white[4], 128)
        XCTAssertEqual(white[5], 128)

        let black = NV12Conversion.convert(bgra: solidFrame(b: 0, g: 0, r: 0), width: 2, height: 2)
        XCTAssertEqual(black[0], 16)
        XCTAssertEqual(black[4], 128)
        XCTAssertEqual(black[5], 128)
    }

    func testPureRed() {
        let red = NV12Conversion.convert(bgra: solidFrame(b: 0, g: 0, r: 255), width: 2, height: 2)
        XCTAssertEqual(Int(red[0]), 63, accuracy: 1)
        XCTAssertEqual(Int(red[4]), 102, accuracy: 1)
        XCTAssertEqual(Int(red[5]), 240, accuracy: 1)
    }
}
