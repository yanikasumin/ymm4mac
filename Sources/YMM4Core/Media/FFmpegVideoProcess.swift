import Foundation

/// FFmpeg 映像デコードプロセスの起動要求と引数生成（Issue #70 段階2）。
///
/// 実測（ffmpeg 9.0.2、着工前実測 系統2）で確定した規則:
/// - `-copyts` を常に付け、提示タイムスタンプを素材の絶対時刻の
///   まま保持する（付けないと開始オフセットが 0 へ読み替えられ、
///   シーク時は目標からの相対値になって対応が崩れる）。
/// - シークの切り捨て規則は入力・出力とも「pts < 目標のフレームは
///   捨て、pts ≧ 目標を残す」。区間途中の目標では、その区間を含む
///   フレームが捨てられる（実測の「+1フレーム」挙動の正体）。
///   そのため呼び出し側（セッション）は目標より手前から開始し、
///   pts 基準で選ぶ。
/// - TS は入力シークが信頼できないため出力シークを使う。出力
///   シークでは、捨てられるフレームも showinfo 行は出力される
///   （実測: 出力 88 フレームに対し showinfo 180 行）。そのため
///   対応付けは「目標以上の pts の項目だけを数える」規則で
///   入力・出力を統一する。

/// シークの方式。コンテナで切り替える（TS は出力シーク）。
public enum FFmpegVideoSeekStyle: String, Equatable, Sendable {
    /// `-ss` を入力の前に置く（通常のコンテナ）。
    case input
    /// `-ss` を入力の後に置く（TS。入力シークが信頼できないため）。
    case output
}

/// プロセス1回の起動要求。
public struct FFmpegVideoProcessRequest: Equatable, Sendable {
    public var ffmpegPath: String
    public var filePath: String
    /// 対象の映像ストリームのインデックス（プローブの主映像）。
    public var videoStreamIndex: Int
    /// BGRA 1フレームのバイト数（幅×高さ×4）。
    public var frameByteCount: Int
    /// シーク目標（秒、絶対提示時刻）。nil なら先頭から（`-ss` を
    /// 付けない）。
    public var seekTargetSeconds: Double?
    public var seekStyle: FFmpegVideoSeekStyle
    /// フレームの時刻項目を待つ上限（秒）。項目と画素の対応が
    /// 取れなくなった場合に無期限に待たないための上限。
    public var entryWaitTimeoutSeconds: Double

    public init(
        ffmpegPath: String, filePath: String, videoStreamIndex: Int,
        frameByteCount: Int, seekTargetSeconds: Double?,
        seekStyle: FFmpegVideoSeekStyle, entryWaitTimeoutSeconds: Double = 10
    ) {
        self.ffmpegPath = ffmpegPath
        self.filePath = filePath
        self.videoStreamIndex = videoStreamIndex
        self.frameByteCount = frameByteCount
        self.seekTargetSeconds = seekTargetSeconds
        self.seekStyle = seekStyle
        self.entryWaitTimeoutSeconds = entryWaitTimeoutSeconds
    }
}

/// 起動要求から ffmpeg の引数列を作る純粋関数。
public enum FFmpegVideoProcessArguments {
    /// showinfo の pts_time 表示精度（1µs）とフレーム間隔の実態に
    /// 基づく対応付けの許容誤差（秒）。目標未満の項目を除外する
    /// 際、表示の丸めで目標ちょうどのフレームを落とさないために使う。
    public static let pairingEpsilonSeconds = 0.0001

    public static func arguments(for request: FFmpegVideoProcessRequest) -> [String] {
        var arguments = ["-v", "info"]
        let seekArguments: [String] = request.seekTargetSeconds.map {
            ["-ss", secondsText($0), "-copyts"]
        } ?? ["-copyts"]
        switch request.seekStyle {
        case .input:
            arguments += seekArguments
            arguments += ["-i", request.filePath]
        case .output:
            arguments += ["-i", request.filePath]
            arguments += seekArguments
        }
        arguments += [
            "-map", "0:\(request.videoStreamIndex)",
            "-vf", "showinfo",
            "-fps_mode", "passthrough",
            "-an", "-sn", "-dn",
            "-pix_fmt", "bgra",
            "-f", "rawvideo",
            "-",
        ]
        return arguments
    }

    /// 秒を ffmpeg が解釈できる小数文字列にする（小数6桁まで）。
    static func secondsText(_ seconds: Double) -> String {
        String(format: "%.6f", seconds)
    }
}

// MARK: - プロセスの抽象

public enum FFmpegVideoProcessError: Error, Equatable, Sendable {
    /// 起動自体に失敗した（例外の説明文）。
    case launchFailed(String)
    /// 時刻項目が上限時間内に得られず、画素との対応が取れない。
    case frameTimeUnavailable
    /// フレームの途中で出力が終わった。
    case truncatedFrame
}

/// デコードプロセス1個の抽象。テストではフェイクへ差し替える。
///
/// 画素（標準出力）と時刻項目（標準エラーの showinfo 行）は別々の
/// 経路で届くが、順序は一致する。実装は「時刻項目を待ってから
/// 画素を読む」順で対応付ける（項目は画素より先にフィルタを
/// 通過するため、この順なら詰まらない）。
public protocol FFmpegVideoProcess: AnyObject, Sendable {
    /// 次のフレームを読む。表示開始時刻（秒、絶対提示時刻）つき。
    /// ストリーム終端では nil（正常・異常の区別は終了コードと
    /// 収集済み標準エラーで判断する）。
    func readNextFrame() throws -> (pixelData: Data, startSeconds: Double)?
    /// このプロセスが生成したフレーム数。
    var producedFrameCount: Int { get }
    /// プロセスが終了し、終了コードが確定していればその値。
    var exitStatus: Int32? { get }
    /// 収集済みの標準エラー（showinfo 行を除く。証拠の材料）。
    var collectedStandardError: String { get }
    /// プロセスを終了させる。ブロック中の読み取りは終端として
    /// 返る。
    func terminate()
}

/// プロセス生成の差し替え点。
public protocol FFmpegVideoProcessFactory: Sendable {
    func makeProcess(request: FFmpegVideoProcessRequest) throws -> any FFmpegVideoProcess
}

public struct FoundationFFmpegVideoProcessFactory: FFmpegVideoProcessFactory {
    public init() {}

    public func makeProcess(request: FFmpegVideoProcessRequest) throws -> any FFmpegVideoProcess {
        try FFmpegVideoProcessRunner(request: request)
    }
}

// MARK: - 実プロセス

/// Foundation.Process によるデコードプロセスの実体。
///
/// 所有: プロセスと両パイプは本クラスが所有し、`terminate()` か
/// 終端の検出で解放する。標準エラーは専用スレッドが継続的に
/// 回収し（パイプ詰まり防止）、showinfo の時刻項目をキューへ、
/// それ以外の行を証拠用のバッファへ振り分ける。
final class FFmpegVideoProcessRunner: FFmpegVideoProcess, @unchecked Sendable {
    private let request: FFmpegVideoProcessRequest
    private let process: Process
    private let outputHandle: FileHandle

    private let condition = NSCondition()
    private var timeEntries: [FFmpegShowinfoTimeEntry] = []
    private var entriesExhausted = false
    private var errorText = ""
    private var reapedExitStatus: Int32?
    private var outputFinished = false
    private(set) var producedFrameCount = 0

    init(request: FFmpegVideoProcessRequest) throws {
        self.request = request
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.ffmpegPath)
        process.arguments = FFmpegVideoProcessArguments.arguments(for: request)
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        self.process = process
        self.outputHandle = outputPipe.fileHandleForReading
        do {
            try process.run()
        } catch {
            throw FFmpegVideoProcessError.launchFailed(String(describing: error))
        }
        startErrorDrain(handle: errorPipe.fileHandleForReading)
    }

    // MARK: 標準エラーの回収

    private func startErrorDrain(handle: FileHandle) {
        let thread = Thread { [weak self] in
            var lineBuffer = Data()
            while true {
                let chunk: Data
                do {
                    chunk = try handle.read(upToCount: 32 * 1024) ?? Data()
                } catch {
                    break
                }
                if chunk.isEmpty { break }
                lineBuffer.append(chunk)
                while let newline = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = lineBuffer.subdata(in: 0..<newline)
                    lineBuffer.removeSubrange(0...newline)
                    self?.consumeErrorLine(
                        String(data: lineData, encoding: .utf8) ?? ""
                    )
                }
            }
            if !lineBuffer.isEmpty {
                self?.consumeErrorLine(
                    String(data: lineBuffer, encoding: .utf8) ?? ""
                )
            }
            self?.markEntriesExhausted()
        }
        thread.name = "FFmpegVideoProcessRunner.stderr"
        thread.start()
    }

    private func consumeErrorLine(_ line: String) {
        if let entry = FFmpegShowinfoParser.parseTimeEntry(fromLine: line) {
            // 対応付け: シーク目標以上の項目だけを数える（出力
            // シークで捨てられたフレームの項目を読み飛ばす）。
            // 目標が無い（先頭から）場合は全項目が対象。
            if let target = request.seekTargetSeconds,
               entry.startSeconds < target - FFmpegVideoProcessArguments.pairingEpsilonSeconds {
                return
            }
            condition.lock()
            timeEntries.append(entry)
            condition.signal()
            condition.unlock()
            return
        }
        // showinfo の設定行など、フレーム行でないフィルタ出力は
        // 証拠に混ぜない。
        if line.contains("showinfo") { return }
        condition.lock()
        // 証拠用は末尾を保持する（失敗時のエラーは末尾に出る）。
        errorText += line + "\n"
        if errorText.count > 64 * 1024 {
            errorText = String(errorText.suffix(64 * 1024))
        }
        condition.unlock()
    }

    private func markEntriesExhausted() {
        condition.lock()
        entriesExhausted = true
        condition.broadcast()
        condition.unlock()
    }

    // MARK: フレーム読み取り

    func readNextFrame() throws -> (pixelData: Data, startSeconds: Double)? {
        condition.lock()
        let alreadyFinished = outputFinished
        condition.unlock()
        if alreadyFinished { return nil }

        guard let entry = try waitForNextEntry() else {
            // 時刻項目がもう来ない。画素側も終端かを確認して終える。
            finishOutput()
            return nil
        }
        var data = Data()
        data.reserveCapacity(request.frameByteCount)
        while data.count < request.frameByteCount {
            let chunk: Data
            do {
                chunk = try outputHandle.read(
                    upToCount: request.frameByteCount - data.count
                ) ?? Data()
            } catch {
                if data.isEmpty {
                    finishOutput()
                    return nil
                }
                throw FFmpegVideoProcessError.truncatedFrame
            }
            if chunk.isEmpty {
                if data.isEmpty {
                    finishOutput()
                    return nil
                }
                throw FFmpegVideoProcessError.truncatedFrame
            }
            data.append(chunk)
        }
        producedFrameCount += 1
        return (data, entry.startSeconds)
    }

    /// 次の時刻項目を待つ。項目が枯渇していれば nil、上限時間を
    /// 超えたら例外（画素との対応が取れない状態）。
    private func waitForNextEntry() throws -> FFmpegShowinfoTimeEntry? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(request.entryWaitTimeoutSeconds)
        while timeEntries.isEmpty {
            if entriesExhausted { return nil }
            if !condition.wait(until: deadline),
               timeEntries.isEmpty, !entriesExhausted {
                throw FFmpegVideoProcessError.frameTimeUnavailable
            }
        }
        return timeEntries.removeFirst()
    }

    /// 終端処理: プロセスの終了を回収し、終了コードを確定させる。
    private func finishOutput() {
        condition.lock()
        if outputFinished {
            condition.unlock()
            return
        }
        outputFinished = true
        condition.unlock()
        if process.isRunning {
            // 出力が閉じた後もプロセスが残る場合は終了を促す
            // （通常は出力の終端＝プロセス終了）。
            process.terminate()
        }
        process.waitUntilExit()
        condition.lock()
        reapedExitStatus = process.terminationStatus
        condition.unlock()
    }

    var exitStatus: Int32? {
        condition.lock()
        defer { condition.unlock() }
        if let reapedExitStatus { return reapedExitStatus }
        return process.isRunning ? nil : process.terminationStatus
    }

    var collectedStandardError: String {
        condition.lock()
        defer { condition.unlock() }
        return errorText
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}
