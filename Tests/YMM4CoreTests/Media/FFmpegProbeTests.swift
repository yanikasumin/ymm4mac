import XCTest
@testable import YMM4Core

/// プローブのテスト。フィクスチャは着工前実測の素材に対する
/// ffprobe 9.0.2 の実出力から、関係フィールドへ絞ったもの
/// （構造と値の形式は実出力どおり）。
final class FFmpegProbeParseTests: XCTestCase {
    /// CFR 動画のみの MP4（実測素材 cfr30.mp4）。
    private let mp4JSON = """
        {
          "streams": [
            {
              "index": 0, "codec_name": "h264", "codec_type": "video",
              "width": 320, "height": 180,
              "r_frame_rate": "30/1", "avg_frame_rate": "30/1",
              "start_time": "0.000000", "duration": "6.000000",
              "disposition": {"default": 1, "attached_pic": 0}
            }
          ],
          "format": {
            "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
            "start_time": "0.000000", "duration": "6.000000"
          }
        }
        """

    /// 開始オフセット付き TS（実測素材 offset35.ts）。format と
    /// ストリームの両方に開始時刻 4.9 が出る。
    private let tsOffsetJSON = """
        {
          "streams": [
            {
              "index": 0, "codec_name": "h264", "codec_type": "video",
              "width": 320, "height": 180,
              "r_frame_rate": "30/1", "avg_frame_rate": "30/1",
              "start_time": "4.900000", "duration": "6.000333",
              "disposition": {"default": 0, "attached_pic": 0}
            }
          ],
          "format": {
            "format_name": "mpegts",
            "start_time": "4.900000", "duration": "6.000333"
          }
        }
        """

    /// VFR の MKV（実測素材 vfr.mkv）。ストリームに duration が無い。
    private let vfrMkvJSON = """
        {
          "streams": [
            {
              "index": 0, "codec_name": "h264", "codec_type": "video",
              "width": 320, "height": 180,
              "r_frame_rate": "60/1", "avg_frame_rate": "60/1",
              "start_time": "0.000000",
              "disposition": {"default": 1, "attached_pic": 0}
            }
          ],
          "format": {
            "format_name": "matroska,webm",
            "start_time": "0.000000", "duration": "7.000000"
          }
        }
        """

    /// 音声のみの WAV（実測素材 imp48.wav）。format に start_time が
    /// 無く、avg_frame_rate は "0/0"、sample_rate は文字列。
    private let wavJSON = """
        {
          "streams": [
            {
              "index": 0, "codec_name": "pcm_s16le", "codec_type": "audio",
              "sample_rate": "48000", "channels": 1,
              "r_frame_rate": "0/0", "avg_frame_rate": "0/0",
              "duration": "3.000000",
              "disposition": {"default": 0, "attached_pic": 0}
            }
          ],
          "format": { "format_name": "wav", "duration": "3.000000" }
        }
        """

    func testParseMP4Video() throws {
        let result = try FFmpegProbe.parse(jsonData: Data(mp4JSON.utf8))
        XCTAssertEqual(result.formatName, "mov,mp4,m4a,3gp,3g2,mj2")
        XCTAssertEqual(result.startTimeSeconds, 0)
        XCTAssertEqual(result.duration, TimeSpanValue(seconds: 6.0))
        XCTAssertTrue(result.hasVideo)
        XCTAssertFalse(result.hasAudio)
        let video = try XCTUnwrap(result.primaryVideoStream)
        XCTAssertEqual(video.codecName, "h264")
        XCTAssertEqual(video.width, 320)
        XCTAssertEqual(video.height, 180)
        XCTAssertEqual(video.averageFrameRate, 30)
        XCTAssertFalse(video.isAttachedPicture)
        let info = try XCTUnwrap(result.makeMediaFileInfo())
        XCTAssertEqual(info.duration, TimeSpanValue(seconds: 6.0))
        XCTAssertEqual(info.width, 320)
        XCTAssertEqual(info.height, 180)
    }

    func testParseTSWithStartOffset() throws {
        let result = try FFmpegProbe.parse(jsonData: Data(tsOffsetJSON.utf8))
        XCTAssertEqual(result.formatName, "mpegts")
        XCTAssertEqual(result.startTimeSeconds, 4.9)
        XCTAssertEqual(result.duration?.ticks, 60_003_330)
        let video = try XCTUnwrap(result.primaryVideoStream)
        XCTAssertEqual(video.startTimeSeconds, 4.9)
    }

    func testParseVFRMkvWithoutStreamDuration() throws {
        let result = try FFmpegProbe.parse(jsonData: Data(vfrMkvJSON.utf8))
        XCTAssertEqual(result.duration, TimeSpanValue(seconds: 7.0))
        let video = try XCTUnwrap(result.primaryVideoStream)
        XCTAssertNil(video.durationSeconds)
        XCTAssertEqual(video.averageFrameRate, 60)
    }

    func testParseAudioOnlyWav() throws {
        let result = try FFmpegProbe.parse(jsonData: Data(wavJSON.utf8))
        XCTAssertFalse(result.hasVideo)
        XCTAssertTrue(result.hasAudio)
        XCTAssertNil(result.startTimeSeconds)
        let audio = try XCTUnwrap(result.primaryAudioStream)
        XCTAssertEqual(audio.codecName, "pcm_s16le")
        XCTAssertEqual(audio.sampleRate, 48000)
        XCTAssertEqual(audio.channels, 1)
        XCTAssertNil(audio.averageFrameRate)
        let info = try XCTUnwrap(result.makeMediaFileInfo())
        XCTAssertEqual(info.duration, TimeSpanValue(seconds: 3.0))
        XCTAssertNil(info.width)
        XCTAssertNil(info.height)
    }

    func testDurationFallsBackToStreamEnd() throws {
        // format の duration が "N/A" の場合はストリーム側から決める。
        let json = """
            {
              "streams": [
                {
                  "index": 0, "codec_name": "h264", "codec_type": "video",
                  "width": 640, "height": 360,
                  "avg_frame_rate": "30/1",
                  "start_time": "1.000000", "duration": "5.000000",
                  "disposition": {"default": 1, "attached_pic": 0}
                }
              ],
              "format": { "format_name": "mpegts", "duration": "N/A" }
            }
            """
        let result = try FFmpegProbe.parse(jsonData: Data(json.utf8))
        // 終端 6.0 − 開始の最小 1.0 = 5.0 秒。
        XCTAssertEqual(result.duration, TimeSpanValue(seconds: 5.0))
    }

    func testDurationUndeterminedIsNilNotZero() throws {
        // format にもストリームにも duration が無い場合は未確定。
        // 0 秒として確定させないことが本単位の契約。
        let json = """
            {
              "streams": [
                {
                  "index": 0, "codec_name": "h264", "codec_type": "video",
                  "width": 640, "height": 360, "avg_frame_rate": "30/1",
                  "disposition": {"default": 1, "attached_pic": 0}
                }
              ],
              "format": { "format_name": "matroska,webm" }
            }
            """
        let result = try FFmpegProbe.parse(jsonData: Data(json.utf8))
        XCTAssertNil(result.duration)
        XCTAssertNil(result.makeMediaFileInfo())
        XCTAssertTrue(result.hasVideo)
    }

    func testAttachedPictureIsNotPrimaryVideo() throws {
        let json = """
            {
              "streams": [
                {
                  "index": 0, "codec_name": "aac", "codec_type": "audio",
                  "sample_rate": "44100", "channels": 2, "duration": "10.000000",
                  "disposition": {"default": 1, "attached_pic": 0}
                },
                {
                  "index": 1, "codec_name": "mjpeg", "codec_type": "video",
                  "width": 500, "height": 500, "avg_frame_rate": "90000/1",
                  "duration": "10.000000",
                  "disposition": {"default": 0, "attached_pic": 1}
                }
              ],
              "format": { "format_name": "mp3", "duration": "10.000000" }
            }
            """
        let result = try FFmpegProbe.parse(jsonData: Data(json.utf8))
        let primary = try XCTUnwrap(result.primaryVideoStream)
        XCTAssertTrue(primary.isAttachedPicture)
        // 寸法は主映像（= 添付画像しか無いのでそれ）から取る。
        XCTAssertEqual(result.makeMediaFileInfo()?.width, 500)
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try FFmpegProbe.parse(jsonData: Data("not json".utf8))) { error in
            XCTAssertEqual(error as? FFmpegProbeError, .invalidOutput)
        }
        XCTAssertThrowsError(try FFmpegProbe.parse(jsonData: Data("[]".utf8))) { error in
            XCTAssertEqual(error as? FFmpegProbeError, .invalidOutput)
        }
    }

    func testProbeArguments() {
        XCTAssertEqual(
            FFmpegProbe.probeArguments(path: "/media/a.mkv"),
            ["-v", "error", "-show_format", "-show_streams", "-of", "json", "/media/a.mkv"]
        )
    }
}

// MARK: - プローブ実行（フェイクの実行層）

private final class FakeProbeRunner: ProcessOutputRunning, @unchecked Sendable {
    var output: ProcessOutput?
    var launchError: Error?
    private(set) var calls: [(path: String, arguments: [String])] = []

    func run(executablePath: String, arguments: [String]) throws -> ProcessOutput {
        calls.append((executablePath, arguments))
        if let launchError { throw launchError }
        guard let output else { throw NSError(domain: "FakeProbeRunner", code: 1) }
        return output
    }
}

final class FFmpegProberTests: XCTestCase {
    private let minimalJSON = """
        {"streams": [], "format": {"format_name": "wav", "duration": "1.000000"}}
        """

    func testProbeSuccess() throws {
        let runner = FakeProbeRunner()
        runner.output = ProcessOutput(
            terminationStatus: 0, standardOutput: Data(minimalJSON.utf8), standardError: Data()
        )
        let result = try FFmpegProber(runner: runner).probe(path: "/media/a.wav", ffprobePath: "/dev/ffprobe")
        XCTAssertEqual(result.formatName, "wav")
        XCTAssertEqual(runner.calls.first?.path, "/dev/ffprobe")
        XCTAssertEqual(
            runner.calls.first?.arguments,
            FFmpegProbe.probeArguments(path: "/media/a.wav")
        )
    }

    func testProbeNonZeroExit() {
        let runner = FakeProbeRunner()
        runner.output = ProcessOutput(
            terminationStatus: 1, standardOutput: Data(),
            standardError: Data("/media/x.mkv: Invalid data found when processing input".utf8)
        )
        XCTAssertThrowsError(
            try FFmpegProber(runner: runner).probe(path: "/media/x.mkv", ffprobePath: "/dev/ffprobe")
        ) { error in
            guard case .nonZeroExit(let status, let standardError) = error as? FFmpegProbeError
            else { return XCTFail("nonZeroExit を期待した: \(error)") }
            XCTAssertEqual(status, 1)
            XCTAssertTrue(standardError.contains("Invalid data"))
        }
    }

    func testProbeNotResolved() {
        let runner = FakeProbeRunner()
        let resolution = FFmpegBinaryResolution(ffmpeg: nil, ffprobe: nil)
        XCTAssertThrowsError(
            try FFmpegProber(runner: runner).probe(path: "/media/a.wav", resolution: resolution)
        ) { error in
            XCTAssertEqual(error as? FFmpegProbeError, .ffprobeNotResolved)
        }
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testProbeLaunchFailure() {
        struct StubError: Error {}
        let runner = FakeProbeRunner()
        runner.launchError = StubError()
        XCTAssertThrowsError(
            try FFmpegProber(runner: runner).probe(path: "/media/a.wav", ffprobePath: "/dev/ffprobe")
        ) { error in
            guard case .launchFailed = error as? FFmpegProbeError else {
                return XCTFail("launchFailed を期待した: \(error)")
            }
        }
    }
}
