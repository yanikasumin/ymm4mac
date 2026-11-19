import XCTest
@testable import YMM4Core

/// テスト用のフェイク音声プロセス。決められた絶対時刻のチャンク列を
/// 順に返し、終端で nil を返す。シーク目標より手前のチャンクは
/// 工場側で落とす（ffmpeg の入力シークの読み捨てを模す）。
final class FakeAudioProcess: FFmpegAudioProcess, @unchecked Sendable {
    struct ChunkSpec {
        var startSeconds: Double
        /// インターリーブ済みサンプル列（2ch）。
        var samples: [Float]
    }

    let chunks: [ChunkSpec]
    var exitStatusValue: Int32? = 0
    var errorText = ""
    private var index = 0
    private(set) var terminated = false

    init(chunks: [ChunkSpec]) {
        self.chunks = chunks
    }

    func readNextChunk() throws -> (data: Data, startSeconds: Double)? {
        guard index < chunks.count else { return nil }
        let spec = chunks[index]
        index += 1
        let data = spec.samples.withUnsafeBytes { raw in Data(raw) }
        return (data, spec.startSeconds)
    }

    var producedSampleCount: Int {
        chunks[..<index].reduce(0) { $0 + $1.samples.count / 2 }
    }

    var exitStatus: Int32? { exitStatusValue }
    var collectedStandardError: String { errorText }

    func terminate() { terminated = true }
}

/// フェイクプロセスの生成を記録する工場。シーク目標がある場合は
/// 目標より手前で終わるチャンクを落としてからプロセスを作る。
final class FakeAudioProcessFactory: FFmpegAudioProcessFactory, @unchecked Sendable {
    private(set) var requests: [FFmpegAudioProcessRequest] = []
    var allChunks: [FakeAudioProcess.ChunkSpec] = []
    var exitStatusValue: Int32? = 0
    var errorText = ""

    func makeProcess(request: FFmpegAudioProcessRequest) throws -> any FFmpegAudioProcess {
        requests.append(request)
        var chunks = allChunks
        if let target = request.seekTargetSeconds {
            chunks = chunks.filter { spec in
                let frames = spec.samples.count / 2
                // チャンクの長さはテスト素材では一律 0.1 秒（10フレーム
                // @100Hz）前提。目標を含むチャンクは残す。
                return spec.startSeconds + 0.1 > target - 0.0001
            }
        }
        let process = FakeAudioProcess(chunks: chunks)
        process.exitStatusValue = exitStatusValue
        process.errorText = errorText
        return process
    }
}

/// FFmpeg PCM 供給の意味論テスト（Issue #70 段階3）。
/// サンプリングレート 100Hz・提示開始 10.0 秒・長さ 2 秒（200
/// フレーム）の素材を模し、フレーム番号をそのままサンプル値にした
/// チャンク列で位置の正確さを見る。
final class FFmpegPCMProviderTests: XCTestCase {
    private let hz = 100
    private let presentationStart = 10.0
    private let frameCount = 200

    /// 論理フレーム列 [from, to) を 10 フレームずつのチャンクにする。
    /// サンプル値は論理フレーム番号（両チャンネル同値）。
    private func makeChunks(from: Int = 0, to: Int = 200) -> [FakeAudioProcess.ChunkSpec] {
        var chunks: [FakeAudioProcess.ChunkSpec] = []
        var frame = from
        while frame < to {
            let count = min(10, to - frame)
            var samples: [Float] = []
            for offset in 0..<count {
                samples.append(Float(frame + offset))
                samples.append(Float(frame + offset))
            }
            chunks.append(FakeAudioProcess.ChunkSpec(
                startSeconds: presentationStart + Double(frame) / Double(hz),
                samples: samples
            ))
            frame += count
        }
        return chunks
    }

    private func makeProvider(
        factory: FakeAudioProcessFactory,
        registry: MediaAvailabilityRegistry? = nil,
        presentationStartSeconds: Double? = 10.0,
        durationSeconds: Double? = 2.0,
        ringBufferSeconds: Double = 5.0,
        forwardPullThresholdSeconds: Double = 0.5,
        seekPrerollSeconds: Double = 0.2
    ) -> FFmpegPCMProvider {
        FFmpegPCMProvider(
            filePath: "/dev/audio.mkv",
            ffmpegPath: "/dev/ffmpeg",
            audioStreamIndex: 1,
            sampleRate: hz,
            presentationStartSeconds: presentationStartSeconds,
            durationSeconds: durationSeconds,
            usesOutputSeek: false,
            processFactory: factory,
            registry: registry,
            ringBufferSeconds: ringBufferSeconds,
            forwardPullThresholdSeconds: forwardPullThresholdSeconds,
            seekPrerollSeconds: seekPrerollSeconds
        )
    }

    /// フレーム数だけ読み、得られた要素列を返す。
    private func readFrames(_ provider: FFmpegPCMProvider, frames: Int) -> [Float] {
        var buffer = [Float](repeating: -999, count: frames * 2)
        let produced = provider.read(into: &buffer, offset: 0, count: buffer.count)
        return Array(buffer[..<produced])
    }

    /// 要素列が論理フレーム列 [from, to) の値と一致するか。
    private func assertValues(
        _ elements: [Float], from: Int, to: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(elements.count, (to - from) * 2, file: file, line: line)
        for frame in from..<to {
            let base = (frame - from) * 2
            guard base + 1 < elements.count else { break }
            XCTAssertEqual(elements[base], Float(frame), "frame \(frame) L", file: file, line: line)
            XCTAssertEqual(elements[base + 1], Float(frame), "frame \(frame) R", file: file, line: line)
        }
    }

    // MARK: - 逐次読みと位置

    func testSequentialReadPositions() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks()
        let provider = makeProvider(factory: factory)

        assertValues(readFrames(provider, frames: 30), from: 0, to: 30)
        assertValues(readFrames(provider, frames: 20), from: 30, to: 50)
        XCTAssertEqual(factory.requests.count, 1)
        XCTAssertNil(factory.requests[0].seekTargetSeconds)
    }

    func testNegativePositionIsSilence() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks()
        let provider = makeProvider(factory: factory)

        provider.seek(toTime: TimeSpanValue(seconds: -0.5))
        let elements = readFrames(provider, frames: 60)
        XCTAssertEqual(elements.count, 120)
        for index in 0..<100 {
            XCTAssertEqual(elements[index], 0, "negative region index \(index)")
        }
        assertValues(Array(elements[100...]), from: 0, to: 10)
    }

    func testGapIsFilledWithSilence() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks(from: 0, to: 10) + makeChunks(from: 30, to: 40)
        let provider = makeProvider(factory: factory, durationSeconds: 0.4)

        let elements = readFrames(provider, frames: 40)
        XCTAssertEqual(elements.count, 80)
        assertValues(Array(elements[0..<20]), from: 0, to: 10)
        for index in 20..<60 {
            XCTAssertEqual(elements[index], 0, "gap index \(index)")
        }
        assertValues(Array(elements[60..<80]), from: 30, to: 40)
    }

    func testChunkBeforeLogicalZeroIsTrimmed() {
        let factory = FakeAudioProcessFactory()
        // 提示開始より 0.1 秒（10フレーム）手前から始まるチャンク列。
        var chunks: [FakeAudioProcess.ChunkSpec] = []
        var samples: [Float] = []
        for frame in -10..<10 {
            samples.append(Float(frame))
            samples.append(Float(frame))
        }
        chunks.append(FakeAudioProcess.ChunkSpec(
            startSeconds: presentationStart - 0.1, samples: samples
        ))
        chunks += makeChunks(from: 10, to: 30)
        factory.allChunks = chunks
        let provider = makeProvider(factory: factory, durationSeconds: 0.3)

        assertValues(readFrames(provider, frames: 10), from: 0, to: 10)
    }

    func testPresentationStartAdoptedFromFirstChunk() {
        let factory = FakeAudioProcessFactory()
        var chunks: [FakeAudioProcess.ChunkSpec] = []
        var frame = 0
        while frame < 20 {
            var samples: [Float] = []
            for offset in 0..<10 {
                samples.append(Float(frame + offset))
                samples.append(Float(frame + offset))
            }
            chunks.append(FakeAudioProcess.ChunkSpec(
                startSeconds: 7.5 + Double(frame) / Double(hz), samples: samples
            ))
            frame += 10
        }
        factory.allChunks = chunks
        let provider = makeProvider(
            factory: factory, presentationStartSeconds: nil, durationSeconds: nil
        )
        XCTAssertEqual(provider.duration, .zero)
        assertValues(readFrames(provider, frames: 20), from: 0, to: 20)
    }

    // MARK: - EOF

    func testEndOfStreamReturnsShortThenZero() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks()
        let provider = makeProvider(factory: factory)

        let elements = readFrames(provider, frames: 250)
        XCTAssertEqual(elements.count, frameCount * 2)
        assertValues(elements, from: 0, to: 200)
        XCTAssertEqual(readFrames(provider, frames: 10).count, 0)
    }

    // MARK: - シーク

    func testSeekWithinRingDoesNotRestart() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks()
        let provider = makeProvider(factory: factory, ringBufferSeconds: 0.6)

        _ = readFrames(provider, frames: 100)
        provider.seek(toTime: TimeSpanValue(seconds: 0.5))
        XCTAssertEqual(factory.requests.count, 1)
        XCTAssertEqual(provider.processRestartCount, 0)
        assertValues(readFrames(provider, frames: 10), from: 50, to: 60)
    }

    func testSeekBehindRingRestarts() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks()
        let provider = makeProvider(factory: factory, ringBufferSeconds: 0.6)

        _ = readFrames(provider, frames: 100)
        provider.seek(toTime: TimeSpanValue(seconds: 0.1))
        XCTAssertEqual(factory.requests.count, 2)
        XCTAssertEqual(provider.processRestartCount, 1)
        // 目標 0.1 秒 - プリロール 0.2 秒 → 先頭から（シークなし）。
        XCTAssertNil(factory.requests[1].seekTargetSeconds)
        assertValues(readFrames(provider, frames: 10), from: 10, to: 20)
    }

    func testForwardPullWithinThresholdDoesNotRestart() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks()
        let provider = makeProvider(factory: factory)

        provider.seek(toTime: TimeSpanValue(seconds: 0.3))
        XCTAssertEqual(factory.requests.count, 1)
        XCTAssertEqual(provider.processRestartCount, 0)
        assertValues(readFrames(provider, frames: 10), from: 30, to: 40)
    }

    func testFarSeekRestartsWithPreroll() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks()
        let provider = makeProvider(factory: factory)

        _ = readFrames(provider, frames: 10)
        provider.seek(toTime: TimeSpanValue(seconds: 1.5))
        XCTAssertEqual(factory.requests.count, 2)
        XCTAssertEqual(provider.processRestartCount, 1)
        // 目標 1.5 秒 - プリロール 0.2 秒 = 論理 1.3 秒 → 絶対 11.3 秒。
        XCTAssertEqual(factory.requests[1].seekTargetSeconds ?? -1, 11.3, accuracy: 0.0001)
        assertValues(readFrames(provider, frames: 10), from: 150, to: 160)
    }

    func testSeekBeyondEndReturnsZero() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks()
        let provider = makeProvider(factory: factory)

        _ = readFrames(provider, frames: 200)
        provider.seek(toTime: TimeSpanValue(seconds: 3.0))
        XCTAssertEqual(readFrames(provider, frames: 10).count, 0)
    }

    // MARK: - 失敗の判定と台帳

    private func failedKind(
        _ registry: MediaAvailabilityRegistry
    ) -> MediaAvailabilityFailureKind? {
        guard case .failed(let failure) = registry.state(
            for: MediaMaterialKey(filePath: "/dev/audio.mkv")
        ) else { return nil }
        return failure.kind
    }

    func testDecodeErrorInStandardErrorFails() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks(from: 0, to: 50)
        factory.errorText = "[aac @ 0x123] Error while decoding stream #0:0: Invalid data found when processing input"
        let registry = MediaAvailabilityRegistry()
        let provider = makeProvider(factory: factory, registry: registry)

        _ = readFrames(provider, frames: 200)
        XCTAssertEqual(failedKind(registry), .midStreamFailure)
    }

    func testZeroProductionFailsAsUnsupported() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = []
        let registry = MediaAvailabilityRegistry()
        let provider = makeProvider(factory: factory, registry: registry)

        XCTAssertEqual(readFrames(provider, frames: 10).count, 0)
        XCTAssertEqual(failedKind(registry), .unsupportedOrDecodeFailed)
    }

    func testNonZeroExitFails() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks(from: 0, to: 50)
        factory.exitStatusValue = 1
        let registry = MediaAvailabilityRegistry()
        let provider = makeProvider(factory: factory, registry: registry)

        _ = readFrames(provider, frames: 200)
        XCTAssertEqual(failedKind(registry), .midStreamFailure)
    }

    func testShortfallWithinToleranceDoesNotFail() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks(from: 0, to: 195)
        let registry = MediaAvailabilityRegistry()
        let provider = makeProvider(factory: factory, registry: registry)

        let elements = readFrames(provider, frames: 250)
        XCTAssertEqual(elements.count, 195 * 2)
        XCTAssertNil(failedKind(registry))
    }

    func testShortfallBeyondToleranceFails() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks(from: 0, to: 50)
        let registry = MediaAvailabilityRegistry()
        let provider = makeProvider(factory: factory, registry: registry)

        _ = readFrames(provider, frames: 200)
        XCTAssertEqual(failedKind(registry), .midStreamFailure)
    }

    func testBufferedChunksRemainReadableAfterFailure() {
        let factory = FakeAudioProcessFactory()
        factory.allChunks = makeChunks(from: 0, to: 50)
        factory.errorText = "Error while decoding stream"
        let registry = MediaAvailabilityRegistry()
        let provider = makeProvider(factory: factory, registry: registry)

        _ = readFrames(provider, frames: 200)
        XCTAssertEqual(failedKind(registry), .midStreamFailure)
        provider.seek(toTime: TimeSpanValue(seconds: 0.1))
        assertValues(readFrames(provider, frames: 10), from: 10, to: 20)
    }
}
