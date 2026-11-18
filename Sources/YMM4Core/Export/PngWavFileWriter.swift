import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// PngWav ライター（本家 `PngWavFileWriter` の仕様再現）。
///
/// 出力先フォルダへ PNG 連番＋WAV を書き出す（本家は OutputPathMode =
/// Directory）。本家コードから裏取りした仕様:
///
/// - PNG は `{FileName}_{連番}.png`、連番は 0 始まりでフレームごとに
///   1 つ進む。画素は BGRA / Premultiplied、96 dpi 宣言
///   （`PngWavFileWriter.cs` WriteVideoCore）。
/// - WAV は float 32bit / 2ch（`WavFileWriter` の formatID = 3）。
///   現在のファイルの書き込み可能サンプル数が渡されたサンプル数に
///   足りなくなると、次の `{FileName}_{連番}.wav` へ自動分割する
///   （連番は 0 始まり）。
/// - 受け取れるストリームは設定で決まる: PNG 出力 ON なら映像、
///   WAV 出力 ON なら音声（本家 SupportedStreams）。
/// - ファイル系の失敗（容量不足・使用中・アクセス不可）は、本家が
///   HResult から警告へ変換していたのに倣い、利用者の対処で解消
///   しうるエラー（`ExportError.Cause.actionable`）へ寄せる
///   （W6-7.4 の分類と同じ文言を使う）。
///
/// 借用契約（W6-C4）: 映像バッファはメソッド復帰までに PNG へ
/// 変換し切る。音声配列は呼び出しごとに所有権が移る前提で、
/// その場で書き切る。
public final class PngWavFileWriter: VideoFileWriting {
    /// 出力先フォルダ。
    public let directoryPath: String
    /// ファイル名の接頭辞（本家設定の FileName）。
    public let fileName: String
    /// 映像情報（寸法・Hz の源泉）。
    public let videoInfo: VideoInfo
    public let isPngOutputEnabled: Bool
    public let isWavOutputEnabled: Bool

    private let wavByteLimit: Int
    private var pngFileIndex = 0
    private var wavFileIndex = 0
    private var wavWriter: WavFileWriter?
    private var finalized = false

    public var supportedStreams: VideoWriterSupportedStreams {
        var streams: VideoWriterSupportedStreams = []
        if isPngOutputEnabled { streams.insert(.video) }
        if isWavOutputEnabled { streams.insert(.audio) }
        return streams
    }

    /// この writer は CPU の BGRA バッファを受ける。GPU フレームの
    /// 直接受け取りは申告しない。
    public var isGPUFrameSupported: Bool { false }

    /// 成果物は単一ファイルではなくフォルダ内の連番ファイル群だが、
    /// セッションの「成果物が生成されたか」の判定では、どちらかの
    /// ストリームが有効なら生成されたものとして扱う。
    public var producesOutputFile: Bool {
        isPngOutputEnabled || isWavOutputEnabled
    }

    /// - Parameter wavByteLimit: WAV 分割の上限バイト数。本家は
    ///   `WavFileWriter` 内の `Int32.max` 固定であり、既定値はそれと
    ///   同じ。差し替えは分割挙動のテストのための差し替え点。
    public init(
        directoryPath: String,
        fileName: String,
        videoInfo: VideoInfo,
        isPngOutputEnabled: Bool = true,
        isWavOutputEnabled: Bool = true,
        wavByteLimit: Int = Int(Int32.max)
    ) throws {
        self.directoryPath = directoryPath
        self.fileName = fileName
        self.videoInfo = videoInfo
        self.isPngOutputEnabled = isPngOutputEnabled
        self.isWavOutputEnabled = isWavOutputEnabled
        self.wavByteLimit = wavByteLimit
        do {
            try FileManager.default.createDirectory(
                atPath: directoryPath, withIntermediateDirectories: true
            )
        } catch {
            throw Self.convertFileError(error, context: "出力フォルダを作成できませんでした")
        }
    }

    /// 映像フレームを PNG として 1 ファイル書き出す。
    public func writeVideoFrame(_ frame: ExportVideoFrameBuffer) throws {
        guard isPngOutputEnabled else {
            throw ExportError(
                cause: .unresolvable,
                message: "PNG 出力が無効なのに映像フレームが渡されました"
            )
        }
        let path = "\(directoryPath)/\(fileName)_\(pngFileIndex).png"
        pngFileIndex += 1
        let data = PNGEncoder.encode(
            bgra: frame.bytes, width: videoInfo.width, height: videoInfo.height
        )
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            throw Self.convertFileError(error, context: "PNG ファイルを書き出せませんでした")
        }
    }

    /// 音声サンプルを現在の WAV ファイルへ書く。残量が足りなければ
    /// 次の連番ファイルへ切り替える（本家 WriteAudioCore の順序どおり、
    /// 判定は書き込み前に行い、1 回の呼び出し分を途中で割らない）。
    public func writeAudioSamples(_ samples: [Float]) throws {
        guard isWavOutputEnabled else {
            throw ExportError(
                cause: .unresolvable,
                message: "WAV 出力が無効なのに音声サンプルが渡されました"
            )
        }
        do {
            if wavWriter == nil
                || (wavWriter?.remainingWritableSampleCount ?? 0) < samples.count {
                try wavWriter?.finalize()
                wavWriter = try WavFileWriter(
                    filePath: "\(directoryPath)/\(fileName)_\(wavFileIndex).wav",
                    hz: videoInfo.hz,
                    channels: 2,
                    depth: 32,
                    formatID: WavFileWriter.formatIEEEFloat,
                    byteLimit: wavByteLimit
                )
                wavFileIndex += 1
            }
            try wavWriter?.write(samples)
        } catch let error as ExportError {
            throw error
        } catch {
            throw Self.convertFileError(error, context: "WAV ファイルを書き出せませんでした")
        }
    }

    /// 現在の WAV ファイルを確定する（サイズ欄の埋め直しとクローズ）。
    public func finalize() throws {
        guard !finalized else { return }
        finalized = true
        do {
            try wavWriter?.finalize()
        } catch {
            throw Self.convertFileError(error, context: "WAV ファイルを確定できませんでした")
        }
        wavWriter = nil
    }

    // MARK: - ファイルエラーの分類（本家 TryConvertFileException 相当）

    /// ファイル系エラーを、利用者へ提示できる形へ寄せる。容量不足・
    /// アクセス不可・使用中は対処可能な原因として分類し、それ以外は
    /// 下位エラーを保持したまま対処不能として包む。
    static func convertFileError(_ error: Error, context: String) -> ExportError {
        let nsError = error as NSError
        var posixCode: Int32? = nil
        if nsError.domain == NSPOSIXErrorDomain {
            posixCode = Int32(nsError.code)
        } else if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteOutOfSpaceError:
                posixCode = ENOSPC
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                posixCode = EACCES
            default:
                break
            }
        }
        switch posixCode {
        case ENOSPC:
            return ExportError(
                cause: .actionable,
                message: "ストレージの空き容量が不足しています",
                underlying: error
            )
        case EACCES, EPERM:
            return ExportError(
                cause: .actionable,
                message: "ファイルへのアクセス権限がありません",
                underlying: error
            )
        case EBUSY, ETXTBSY:
            return ExportError(
                cause: .actionable,
                message: "ファイルが他のプロセスに使用されています",
                underlying: error
            )
        default:
            return ExportError(cause: .unresolvable, message: context, underlying: error)
        }
    }
}
