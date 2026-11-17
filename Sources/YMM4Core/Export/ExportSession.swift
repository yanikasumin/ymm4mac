import Foundation

/// 書き出しセッションの状態機械と、呼び出し側と writer の間の契約。
///
/// 本家 `VideoFileWriter.CreateFileAsync` の呼び出し側ループの意味論を
/// 再現する（仕様第6章 §2 / §7）:
/// - 映像フレームバッファは書き出し全体を通して単一配列が再利用される
///   （借用契約 W6-C4）。writer はメソッド復帰までにコピーを完了する
///   義務を負い、復帰後にバッファへ触れてはならない。
/// - 音声はフレームごとに新しい配列が渡される（所有権は writer 側へ移る）。
/// - キャンセルはフレーム先頭で判定され、ループを抜けても付随ファイル
///   生成と finalize は走る。映像・音声の受け渡しで例外が出た場合は
///   付随ファイル生成を飛ばし、finalize だけが走る（W6-3.10 / W6-7.3）。
/// - finalize（本家の Dispose 相当）は成功・失敗・キャンセルの
///   いずれでも正確に1回呼ばれる。ファイルの確定は finalize の
///   内部で行われる（W6-C3）。

// MARK: - エラー

/// 書き出しのエラー。重大度で「警告」と「致命的」を区別する
/// （第6章 W6-C2 / W6-C8: 本家は例外型で区別していたものを、
/// Mac 版では値として保持する）。
public struct ExportError: Error, Sendable {
    public enum Severity: Sendable {
        /// 本体は確定するが、付随処理や後処理に失敗した。
        case warning
        /// 書き出し自体が失敗した。
        case fatal
    }

    public var severity: Severity
    public var message: String
    /// 原因となった下位エラーの説明（本家の InnerException の連鎖保持に相当）。
    public var underlyingDescription: String?

    public init(severity: Severity, message: String, underlying: Error? = nil) {
        self.severity = severity
        self.message = message
        self.underlyingDescription = underlying.map { String(describing: $0) }
    }

    /// 任意のエラーを致命的エラーとして包む。既に ExportError ならそのまま。
    static func wrapping(_ error: Error) -> ExportError {
        if let exportError = error as? ExportError { return exportError }
        return ExportError(
            severity: .fatal,
            message: String(describing: error),
            underlying: error
        )
    }
}

// MARK: - writer 契約

/// writer が受け取れるストリームの申告（本家 IVideoFileWriter /
/// IVideoFileWriter2 の階層に相当）。
///
/// 注意: 申告は「インターフェースとして受け取れるか」であり、
/// 設定によって内部的に無効化される場合（例: FFmpeg の `-f null`）は
/// 申告値を変えない（W6-C2 の区別）。
public struct VideoWriterSupportedStreams: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let video = VideoWriterSupportedStreams(rawValue: 1 << 0)
    public static let audio = VideoWriterSupportedStreams(rawValue: 1 << 1)
}

/// 書き出し writer の契約。
public protocol VideoFileWriting: AnyObject {
    /// 受け取れるストリームの申告。
    var supportedStreams: VideoWriterSupportedStreams { get }
    /// GPU フレームを直接受け取れるかの申告。本家 IVideoFileWriter3 の
    /// 動的申告（W6-5.5）と同じく、呼び出し側はフレームごとに評価する。
    /// この芯は CPU バッファ経路のみを扱うため、通常は false。
    var isGPUFrameSupported: Bool { get }
    /// 映像フレームを1枚受け取る。バッファは借用であり、
    /// 復帰までにコピーを完了しなければならない（W6-C4）。
    func writeVideoFrame(_ frame: ExportVideoFrameBuffer) throws
    /// 音声サンプル（float32 / 2ch インターリーブ）を受け取る。
    /// 配列はフレームごとの新規確保で、所有権は writer へ移る。
    func writeAudioSamples(_ samples: [Float]) throws
    /// 終了手続き（本家の Dispose に集約された確定処理）。
    /// セッションから正確に1回だけ呼ばれる。
    func finalize() throws
}

// MARK: - バッファとプロバイダ

/// 書き出し全体で再利用される単一の映像フレームバッファ（借用契約）。
///
/// 本家は `byte[Width * Height * 4]`（BGRA）を1つだけ確保し、
/// 全フレームでレンダラが書き込み writer が読み戻す（W6-3.3）。
/// プロバイダは渡されたバッファへ描画し、writer は復帰までに
/// コピーを完了する。バッファの同一性自体が契約の一部。
public final class ExportVideoFrameBuffer {
    /// BGRA 画素列。長さは幅 × 高さ × 4。
    public var bytes: [UInt8]

    public init(byteCount: Int) {
        bytes = [UInt8](repeating: 0, count: byteCount)
    }
}

/// 映像フレームの供給者。フレーム番号ごとに借用バッファへ描画する。
public protocol VideoFrameProviding {
    func fillFrame(_ frame: Int, into buffer: ExportVideoFrameBuffer) throws
}

/// 音声フレームの供給者。フレームごとに新規配列を返す。
/// 1フレームの件数は `ExportAudioSampleCount` の累積式に従う。
public protocol AudioFrameProviding {
    func audioSamples(forFrame frame: Int) throws -> [Float]
}

/// フレームごとの音声サンプル件数（インターリーブ合計）。
///
/// 本家の累積式: フレーム i の開始位置は `(i * Hz) / FPS`（チャンネル
/// あたり、整数除算）を先に求め、件数は隣接する開始位置の差 × 2。
/// FPS で割り切れない Hz でも端数がフレーム間に正しく配分される。
public enum ExportAudioSampleCount {
    /// フレーム開始位置（チャンネルあたりの累積サンプル数）。
    public static func cumulativePosition(frame: Int, hz: Int, fps: Int) -> Int {
        (frame * hz) / fps
    }

    /// フレーム1枚分のインターリーブ済みサンプル件数。
    public static func count(forFrame frame: Int, hz: Int, fps: Int) -> Int {
        (cumulativePosition(frame: frame + 1, hz: hz, fps: fps)
            - cumulativePosition(frame: frame, hz: hz, fps: fps)) * 2
    }
}

// MARK: - 結果

/// 書き出しの完了種別（W6-C2: Writer 内部の無効化とは別の、
/// セッション全体の結果状態）。
public enum ExportCompletion: Sendable {
    case completed
    case failed
    case cancelled
}

/// 書き出しセッションの結果。
public struct ExportOutcome: Sendable {
    public var completion: ExportCompletion
    /// 映像・音声の受け渡しまで完了したフレーム数。
    public var framesWritten: Int
    /// finalize が呼ばれたかどうか（成功したかとは別）。
    public var finalizeInvoked: Bool
    /// finalize が成功し出力が確定したかどうか（W6-C3）。
    public var outputProduced: Bool
    /// 付随ファイル生成が行われ成功したかどうか。
    public var accompanyingFilesProduced: Bool
    /// 主たる失敗（致命的エラー）。
    public var error: ExportError?
    /// 本体は確定したが付随処理等で起きた警告。
    public var warning: ExportError?
}

// MARK: - セッション

/// 書き出しセッション。1インスタンスにつき1回だけ実行できる。
public final class ExportSession {
    /// セッション設定。値は開始時点のスナップショットとして扱う。
    public struct Configuration {
        /// 最終出力パス。
        public var outputPath: String
        /// 映像情報（寸法・FPS・Hz の源泉）。
        public var videoInfo: VideoInfo
        /// 書き出すフレーム範囲（`ExportRange.normalized` で正規化済みの想定）。
        public var frameRange: Range<Int>
        /// 付随ファイル生成（チャプター・サムネイル等）のフック。
        /// 正常終了とキャンセル時にのみ呼ばれ、失敗は警告になる（W6-7.2）。
        public var accompanyingFiles: (@Sendable (String) throws -> Void)?

        public init(
            outputPath: String,
            videoInfo: VideoInfo,
            frameRange: Range<Int>,
            accompanyingFiles: (@Sendable (String) throws -> Void)? = nil
        ) {
            self.outputPath = outputPath
            self.videoInfo = videoInfo
            self.frameRange = frameRange
            self.accompanyingFiles = accompanyingFiles
        }
    }

    private let writer: VideoFileWriting
    private var hasRun = false

    public init(writer: VideoFileWriting) {
        self.writer = writer
    }

    /// 書き出しを実行する。例外は投げず、結果は `ExportOutcome` で返す。
    ///
    /// - Parameters:
    ///   - videoProvider: 映像供給者。writer が映像を申告しない場合や
    ///     nil の場合は呼ばれない。
    ///   - audioProvider: 音声供給者。同上。
    ///   - isCancelled: フレーム先頭で評価されるキャンセル判定。
    public func run(
        configuration: Configuration,
        videoProvider: VideoFrameProviding?,
        audioProvider: AudioFrameProviding?,
        isCancelled: @escaping () -> Bool = { false }
    ) -> ExportOutcome {
        guard !hasRun else {
            return ExportOutcome(
                completion: .failed,
                framesWritten: 0,
                finalizeInvoked: false,
                outputProduced: false,
                accompanyingFilesProduced: false,
                error: ExportError(
                    severity: .fatal,
                    message: "ExportSession は1回だけ実行できます"
                ),
                warning: nil
            )
        }
        hasRun = true

        var completion: ExportCompletion = .completed
        var framesWritten = 0
        var primaryError: ExportError?
        var warning: ExportError?
        var accompanyingProduced = false

        let supportsVideo = writer.supportedStreams.contains(.video)
        let supportsAudio = writer.supportedStreams.contains(.audio)
        let frameBuffer: ExportVideoFrameBuffer? =
            (supportsVideo && videoProvider != nil)
                ? ExportVideoFrameBuffer(
                    byteCount: configuration.videoInfo.width * configuration.videoInfo.height * 4
                )
                : nil

        // フレームループ（本家は映像・音声を並行タスクで送るが、
        // 意味論としてはフレーム単位の完了待ちであり直列と等価）。
        frameLoop: for frame in configuration.frameRange {
            if isCancelled() {
                completion = .cancelled
                break frameLoop
            }
            do {
                if let frameBuffer, let videoProvider {
                    try videoProvider.fillFrame(frame, into: frameBuffer)
                    try writer.writeVideoFrame(frameBuffer)
                }
                if supportsAudio, let audioProvider {
                    let samples = try audioProvider.audioSamples(forFrame: frame)
                    try writer.writeAudioSamples(samples)
                }
                framesWritten += 1
            } catch {
                primaryError = ExportError.wrapping(error)
                completion = .failed
                break frameLoop
            }
        }

        // 付随ファイル生成は正常終了とキャンセルのときだけ走り、
        // 失敗しても本体の確定は妨げない（W6-3.10 / W6-7.2 / W6-7.3）。
        if completion != .failed, let accompanying = configuration.accompanyingFiles {
            do {
                try accompanying(configuration.outputPath)
                accompanyingProduced = true
            } catch {
                var wrapped = ExportError.wrapping(error)
                wrapped.severity = .warning
                warning = wrapped
            }
        }

        // finalize は結果によらず必ず1回走る（本家の finally 節の Dispose）。
        var outputProduced = false
        do {
            try writer.finalize()
            outputProduced = true
        } catch {
            let wrapped = ExportError.wrapping(error)
            if primaryError == nil {
                primaryError = wrapped
                completion = .failed
            } else if warning == nil {
                var asWarning = wrapped
                asWarning.severity = .warning
                warning = asWarning
            }
        }

        return ExportOutcome(
            completion: completion,
            framesWritten: framesWritten,
            finalizeInvoked: true,
            outputProduced: outputProduced,
            accompanyingFilesProduced: accompanyingProduced,
            error: primaryError,
            warning: warning
        )
    }
}
