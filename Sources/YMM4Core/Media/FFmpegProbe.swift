import Foundation

/// ffprobe による素材プローブ（Issue #70 段階1）。
///
/// プローブは「コンテナとストリームの素性」を返すだけで、
/// **プローブ成功はデコード成功を意味しない**（設計判断）。
/// 利用可否の確定は、デコード段階が初回フレーム／初回読み取りまで
/// 確認して `MediaAvailabilityRegistry` へ記録する。
///
/// Duration が取れない場合は 0 と同一視せず `nil`（未確定）で表す。
/// MPEG-TS 等では format の duration が欠ける・不正確なことがある
/// ため、その場合はストリーム側の値から決める規則にしている。

// MARK: - プローブ結果の型

/// ストリーム1件の素性。
public struct MediaProbeStream: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case video
        case audio
        case subtitle
        case data
        case attachment
        case other
    }

    /// ストリームのインデックス（ffprobe の `index`）。
    public var index: Int
    public var kind: Kind
    /// コーデック名（例: "h264", "aac"）。取れなければ nil。
    public var codecName: String?
    /// 映像の幅・高さ。映像以外・不明では nil。
    public var width: Int?
    public var height: Int?
    /// 平均フレームレート。`avg_frame_rate`（"0/0" は nil）で、
    /// 取れなければ `r_frame_rate` へ倒す。音声では通常 nil。
    public var averageFrameRate: Double?
    /// 音声のサンプリングレート・チャンネル数。音声以外では nil。
    public var sampleRate: Int?
    public var channels: Int?
    /// ストリームの開始時刻（秒）。取れなければ nil。
    public var startTimeSeconds: Double?
    /// ストリームの長さ（秒）。コンテナによっては欠ける（MKV 等）。
    public var durationSeconds: Double?
    /// カバーアート等の添付画像か（disposition.attached_pic）。
    public var isAttachedPicture: Bool

    public init(
        index: Int, kind: Kind, codecName: String?,
        width: Int?, height: Int?, averageFrameRate: Double?,
        sampleRate: Int?, channels: Int?,
        startTimeSeconds: Double?, durationSeconds: Double?,
        isAttachedPicture: Bool
    ) {
        self.index = index
        self.kind = kind
        self.codecName = codecName
        self.width = width
        self.height = height
        self.averageFrameRate = averageFrameRate
        self.sampleRate = sampleRate
        self.channels = channels
        self.startTimeSeconds = startTimeSeconds
        self.durationSeconds = durationSeconds
        self.isAttachedPicture = isAttachedPicture
    }
}

/// プローブ結果一式。
public struct MediaProbeResult: Equatable, Sendable {
    /// コンテナ形式名（ffprobe の `format_name`。例: "mov,mp4,..."、
    /// "matroska,webm"）。取れなければ nil。
    public var formatName: String?
    /// コンテナの開始時刻（秒）。取れなければ nil。
    public var startTimeSeconds: Double?
    /// 素材の長さ。**取れない場合は nil（未確定）**であり、0 秒の
    /// 素材とは区別する。
    public var duration: TimeSpanValue?
    public var streams: [MediaProbeStream]

    public init(
        formatName: String?, startTimeSeconds: Double?,
        duration: TimeSpanValue?, streams: [MediaProbeStream]
    ) {
        self.formatName = formatName
        self.startTimeSeconds = startTimeSeconds
        self.duration = duration
        self.streams = streams
    }

    public var videoStreams: [MediaProbeStream] { streams.filter { $0.kind == .video } }
    public var audioStreams: [MediaProbeStream] { streams.filter { $0.kind == .audio } }
    public var hasVideo: Bool { !videoStreams.isEmpty }
    public var hasAudio: Bool { !audioStreams.isEmpty }

    /// 主映像ストリーム: 添付画像でない最初の映像。無ければ
    /// 最初の映像（添付画像のみの場合）。
    public var primaryVideoStream: MediaProbeStream? {
        videoStreams.first(where: { !$0.isAttachedPicture }) ?? videoStreams.first
    }

    /// 主音声ストリーム（最初の音声）。
    public var primaryAudioStream: MediaProbeStream? { audioStreams.first }

    /// 既存の長さ決定経路（`MediaFileInfoFetcher` → `recordMediaInfo`）
    /// と同じ結果型への変換。Duration が未確定の場合は nil を返し、
    /// 「長さ不明」を 0 秒として確定させない。寸法は主映像
    /// ストリームから取る（音声のみでは nil）。
    public func makeMediaFileInfo() -> MediaFileInfo? {
        guard let duration else { return nil }
        let video = primaryVideoStream
        return MediaFileInfo(duration: duration, width: video?.width, height: video?.height)
    }
}

// MARK: - プローブの失敗

public enum FFmpegProbeError: Error, Equatable, Sendable {
    /// ffprobe が解決できていない。
    case ffprobeNotResolved
    /// 起動自体に失敗した（例外の説明文）。
    case launchFailed(String)
    /// 終了コードが 0 でない。
    case nonZeroExit(status: Int32, standardError: String)
    /// JSON として解釈できなかった。
    case invalidOutput
}

// MARK: - JSON 解析（純粋関数）

public enum FFmpegProbe {
    /// ffprobe の引数。JSON で format と streams を取る。
    public static func probeArguments(path: String) -> [String] {
        [
            "-v", "error",
            "-show_format", "-show_streams",
            "-of", "json",
            path,
        ]
    }

    /// ffprobe の JSON 出力を解析する。ffprobe の出力はフィールドに
    /// よって数値・文字列の揺れがある（duration は文字列、width は
    /// 数値、欠落フィールドも多い）ため、防御的に読む。
    public static func parse(jsonData: Data) throws -> MediaProbeResult {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: jsonData)
        } catch {
            throw FFmpegProbeError.invalidOutput
        }
        guard let root = object as? [String: Any] else {
            throw FFmpegProbeError.invalidOutput
        }
        let format = root["format"] as? [String: Any]
        let streamObjects = (root["streams"] as? [[String: Any]]) ?? []
        let streams = streamObjects.map(parseStream)

        let formatStart = format.flatMap { doubleValue($0["start_time"]) }
        let duration = resolveDuration(format: format, streams: streams, formatStart: formatStart)
        return MediaProbeResult(
            formatName: format?["format_name"] as? String,
            startTimeSeconds: formatStart,
            duration: duration,
            streams: streams
        )
    }

    /// Duration の決定規則:
    /// 1. format の duration が読めればそれを使う。
    /// 2. 読めなければ、ストリームの（開始時刻＋長さ）の最大値から
    ///    素材の開始時刻（format の開始、無ければストリーム開始の
    ///    最小値）を引いたものを長さとする。
    /// 3. どちらも無ければ未確定（nil）。
    private static func resolveDuration(
        format: [String: Any]?, streams: [MediaProbeStream], formatStart: Double?
    ) -> TimeSpanValue? {
        if let format, let seconds = doubleValue(format["duration"]), seconds >= 0 {
            return TimeSpanValue(seconds: seconds)
        }
        let ends = streams.compactMap { stream -> Double? in
            guard let duration = stream.durationSeconds else { return nil }
            return (stream.startTimeSeconds ?? 0) + duration
        }
        guard let maxEnd = ends.max() else { return nil }
        let base = formatStart ?? streams.compactMap(\.startTimeSeconds).min() ?? 0
        let seconds = maxEnd - base
        return seconds >= 0 ? TimeSpanValue(seconds: seconds) : nil
    }

    private static func parseStream(_ object: [String: Any]) -> MediaProbeStream {
        let kind: MediaProbeStream.Kind
        switch object["codec_type"] as? String {
        case "video": kind = .video
        case "audio": kind = .audio
        case "subtitle": kind = .subtitle
        case "data": kind = .data
        case "attachment": kind = .attachment
        default: kind = .other
        }
        let disposition = object["disposition"] as? [String: Any]
        return MediaProbeStream(
            index: intValue(object["index"]) ?? 0,
            kind: kind,
            codecName: object["codec_name"] as? String,
            width: intValue(object["width"]),
            height: intValue(object["height"]),
            averageFrameRate: frameRate(object["avg_frame_rate"]) ?? frameRate(object["r_frame_rate"]),
            sampleRate: intValue(object["sample_rate"]),
            channels: intValue(object["channels"]),
            startTimeSeconds: doubleValue(object["start_time"]),
            durationSeconds: doubleValue(object["duration"]),
            isAttachedPicture: intValue(disposition?["attached_pic"]) == 1
        )
    }

    /// "30000/1001" 形式のフレームレートを読む。"0/0" は nil。
    private static func frameRate(_ value: Any?) -> Double? {
        guard let text = value as? String else { return nil }
        let parts = text.split(separator: "/")
        if parts.count == 1, let single = Double(parts[0]), single > 0 {
            return single
        }
        guard parts.count == 2,
              let numerator = Double(parts[0]),
              let denominator = Double(parts[1]),
              denominator != 0
        else { return nil }
        let rate = numerator / denominator
        return rate > 0 ? rate : nil
    }

    /// 数値でも文字列でも来るフィールドを Double で読む。
    /// "N/A" 等の読めない文字列は nil。
    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let text as String:
            return Double(text)
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text) ?? Double(text).map { Int($0) }
        default:
            return nil
        }
    }
}

// MARK: - プローブ実行

/// ffprobe を実行してプローブ結果を返す実行部。
/// プロセス実行は `ProcessOutputRunning` の差し替え点越しに行う。
public struct FFmpegProber: Sendable {
    private let runner: any ProcessOutputRunning

    public init(runner: any ProcessOutputRunning = FoundationProcessOutputRunner()) {
        self.runner = runner
    }

    /// 解決結果から ffprobe を使ってプローブする。
    public func probe(path: String, resolution: FFmpegBinaryResolution) throws -> MediaProbeResult {
        guard let ffprobe = resolution.ffprobe else {
            throw FFmpegProbeError.ffprobeNotResolved
        }
        return try probe(path: path, ffprobePath: ffprobe.path)
    }

    /// ffprobe のパスを直接指定してプローブする。
    public func probe(path: String, ffprobePath: String) throws -> MediaProbeResult {
        let output: ProcessOutput
        do {
            output = try runner.run(
                executablePath: ffprobePath,
                arguments: FFmpegProbe.probeArguments(path: path)
            )
        } catch {
            throw FFmpegProbeError.launchFailed(String(describing: error))
        }
        guard output.terminationStatus == 0 else {
            throw FFmpegProbeError.nonZeroExit(
                status: output.terminationStatus,
                standardError: output.standardErrorText
            )
        }
        return try FFmpegProbe.parse(jsonData: output.standardOutput)
    }
}
