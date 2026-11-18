#if os(macOS)
import CryptoKit
import Foundation
import XCTest
@testable import YMM4GPU
import YMM4Core

/// VoiceItem 音声供給（Issue #51）の検証。
///
/// フィクスチャは 48kHz / 16bit / ステレオ / 2400 フレームの WAV
/// （L: 440Hz サイン波・振幅 0.5、R: 同・振幅 0.25）を、Python の
/// brotli（Google 公式実装、RFC 7932）で圧縮したもの。本家の
/// `VoiceCache` は .NET の `BrotliStream` が書いた raw Brotli
/// ストリームであり、形式が同じであることの担保をこのフィクスチャ
/// で取る（.NET 実データでの検証は、本家生成の実キャッシュを持つ
/// ファイルが手元に無いため未実施）。
final class VoiceAudioProviderTests: XCTestCase {

    /// 圧縮フィクスチャ（base64、2946 バイト）。
    private let fixtureCompressedBase64 = """
        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
        Q4ocSbKkyZMoU6pcybKl6/UUANoC
        """

    /// フィクスチャ WAV 全体（9644 バイト）の SHA-256。
    private let fixtureWAVSHA256 =
        "c9810e8b60564997562ddd1fecc6c3fb925b45ffe8cb22c158e1ce996ad3eee5"

    private var fixtureCompressed: Data {
        Data(base64Encoded: fixtureCompressedBase64, options: [.ignoreUnknownCharacters])!
    }

    private var fixtureWAV: Data {
        BrotliDecompression.decompress(fixtureCompressed)!
    }

    private func makeResolver() -> VoicePCMProviderResolver {
        VoicePCMProviderResolver(
            providerFactory: AVFoundationPCMProviderFactory(baseDirectory: nil)
        )
    }

    // MARK: - Brotli 解凍

    func testBrotliDecompressesReferenceStream() {
        let decompressed = BrotliDecompression.decompress(fixtureCompressed)
        XCTAssertNotNil(decompressed)
        XCTAssertEqual(decompressed?.count, 9644)
        let digest = SHA256.hash(data: decompressed ?? Data())
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, fixtureWAVSHA256)
    }

    func testBrotliDecompressRejectsGarbage() {
        XCTAssertNil(BrotliDecompression.decompress(Data([0xFF, 0x00, 0x13, 0x37, 0x42])))
        XCTAssertNil(BrotliDecompression.decompress(Data()))
    }

    // MARK: - VoiceCache からの供給

    func testVoiceCacheSuppliesDecodedPCM() {
        let item = VoiceItem()
        item.voiceCache = fixtureCompressed

        let provider = makeResolver().provider(for: item)
        XCTAssertNotNil(provider)
        XCTAssertEqual(provider?.hz, 48_000)
        // 2400 フレーム / 48kHz = 0.05 秒 = 500,000 ticks
        XCTAssertEqual(provider?.duration.ticks, 500_000)

        var buffer = [Float](repeating: 0, count: 4800)
        let read = provider?.read(into: &buffer, offset: 0, count: 4800) ?? 0
        XCTAssertEqual(read, 4800)
        // フレーム 100 の PCM16 は L=-8191, R=-4095（生成時の実測）。
        // AVFoundation の 16bit→float 変換は /32768。
        XCTAssertEqual(buffer[200], -0.249969, accuracy: 1e-4)
        XCTAssertEqual(buffer[201], -0.124969, accuracy: 1e-4)
        // フレーム 1000 は L=14188, R=7094
        XCTAssertEqual(buffer[2000], 0.432983, accuracy: 1e-4)
        XCTAssertEqual(buffer[2001], 0.216492, accuracy: 1e-4)
    }

    func testBrokenVoiceCacheIsSilent() {
        let item = VoiceItem()
        item.voiceCache = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertNil(makeResolver().provider(for: item))
    }

    // MARK: - カスタム音声ファイルからの供給

    func testCustomVoiceFileSuppliesDecodedPCM() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ymm4-voice-test-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        try fixtureWAV.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let item = VoiceItem()
        item.hatsuon = fileURL.path
        let provider = makeResolver().provider(for: item)
        XCTAssertNotNil(provider)
        XCTAssertEqual(provider?.hz, 48_000)
        var buffer = [Float](repeating: 0, count: 4800)
        let read = provider?.read(into: &buffer, offset: 0, count: 4800) ?? 0
        XCTAssertEqual(read, 4800)
        XCTAssertEqual(buffer[200], -0.249969, accuracy: 1e-4)
    }

    // MARK: - 供給なし（本家で生成前に相当）

    func testVoiceItemWithoutCacheOrCustomVoiceIsSilent() {
        let item = VoiceItem()
        item.hatsuon = "てすと"
        XCTAssertNil(makeResolver().provider(for: item))

        let empty = VoiceItem()
        XCTAssertNil(makeResolver().provider(for: empty))
    }

    // MARK: - カスタム音声の判定（本家 IsCustomVoice）

    func testCustomVoicePathDetection() {
        XCTAssertTrue(VoicePCMProviderResolver.isCustomVoicePath("/Users/someone/voice.wav"))
        XCTAssertTrue(VoicePCMProviderResolver.isCustomVoicePath("file:///Users/someone/voice.mp3"))
        XCTAssertTrue(VoicePCMProviderResolver.isCustomVoicePath("C:\\voice\\line1.wav"))
        XCTAssertTrue(VoicePCMProviderResolver.isCustomVoicePath("/movie/clip.mp4"))
        // 発音記号列（読み仮名）はカスタム音声ではない
        XCTAssertFalse(VoicePCMProviderResolver.isCustomVoicePath("てすと"))
        XCTAssertFalse(VoicePCMProviderResolver.isCustomVoicePath(""))
        // 音声分類でない拡張子はカスタム音声ではない
        XCTAssertFalse(VoicePCMProviderResolver.isCustomVoicePath("/Users/someone/image.png"))
        XCTAssertFalse(VoicePCMProviderResolver.isCustomVoicePath("/Users/someone/memo.txt"))
        // 相対パスは本家でも絶対 URI にならず対象外
        XCTAssertFalse(VoicePCMProviderResolver.isCustomVoicePath("voice/line1.wav"))
    }

    // MARK: - 形式推定

    func testDetectedFileExtension() {
        XCTAssertEqual(
            VoicePCMProviderResolver.detectedFileExtension(for: fixtureWAV), "wav"
        )
        XCTAssertEqual(
            VoicePCMProviderResolver.detectedFileExtension(
                for: Data([0x49, 0x44, 0x33, 0x04, 0x00])), "mp3"
        )
        XCTAssertEqual(
            VoicePCMProviderResolver.detectedFileExtension(
                for: Data([0x4F, 0x67, 0x67, 0x53, 0x00])), "ogg"
        )
        XCTAssertEqual(
            VoicePCMProviderResolver.detectedFileExtension(
                for: Data([0x66, 0x4C, 0x61, 0x43, 0x00])), "flac"
        )
        XCTAssertEqual(
            VoicePCMProviderResolver.detectedFileExtension(
                for: Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])), "m4a"
        )
        XCTAssertEqual(
            VoicePCMProviderResolver.detectedFileExtension(for: Data([0x01, 0x02])), "tmp"
        )
    }

    // MARK: - ミキサー経由（書き出し・再生の共通経路）

    func testVoiceFlowsThroughTimelineMixer() {
        let pcmFactory = AVFoundationPCMProviderFactory(baseDirectory: nil)
        let factory = AudioSourceFactory(
            providerFactory: pcmFactory,
            voiceProviderResolver: VoicePCMProviderResolver(
                providerFactory: pcmFactory
            ).makeResolver()
        )
        let voice = VoiceItem()
        voice.frame = 0
        voice.length = 30
        voice.volume = Animation(defaultValue: 100, minValue: 0, maxValue: 10_000)
        voice.voiceCache = fixtureCompressed

        let timeline = Timeline()
        var info = VideoInfo()
        info.fps = 30
        info.hz = 48_000
        timeline.videoInfo = info
        timeline.items = [voice]
        timeline.refreshTimelineLengthAndMaxLayer()

        let mixer = TimelineAudioMixer(timeline: timeline, factory: factory)
        // アイテム区間（1秒 = 96,000 サンプル）を読む。キャッシュ音声は
        // 0.05 秒分しか無いため、前半に音があり後半は無音になる。
        var buffer = [Float](repeating: 0, count: 96_000)
        let read = mixer.read(into: &buffer, offset: 0, count: 96_000)
        XCTAssertEqual(read, 96_000)
        // フレーム 100 相当（サンプル 200）はサイン波の値が現れる。
        XCTAssertEqual(buffer[200], -0.249969, accuracy: 0.01)
        // 音声の終端（0.05 秒 = サンプル 4800）より後は無音。
        XCTAssertEqual(buffer[48_000], 0, accuracy: 1e-6)
        XCTAssertEqual(buffer[95_999], 0, accuracy: 1e-6)
    }
}
#endif
