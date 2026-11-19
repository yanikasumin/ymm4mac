import Foundation

/// FFmpeg 音声デコードプロセスへの要求（Issue #70 段階3）。
///
/// 映像側（`FFmpegVideoProcessRequest`）と対をなす音声版。stdout は
/// 32bit float・ステレオ・インターリーブ（f32le、`-ac 2` で変換）の
/// 生バイト列で、フレーム（サンプル対）の時刻は stderr の `ashowinfo`
/// 行から得る。`-copyts` で提示タイムスタンプを保持するため、
/// ashowinfo の `pts_time` は素材の絶対提示時刻になる。
public struct FFmpegAudioProcessRequest: Sendable {
    public var executablePath: String
    public var filePath: String
    /// 対象の音声ストリームの絶対インデックス（`-map 0:<index>`）。
    public var audioStreamIndex: Int
    /// シーク目標（絶対提示時刻、秒）。nil なら素材先頭から。
    public var seekTargetSeconds: Double?
    /// true なら出力シーク（入力の後ろに `-ss`）、false なら入力シーク。
    /// TS コンテナは入力シークが不安定（実測）なため出力シークにする
    /// （映像側と同じ規則）。
    public var usesOutputSeek: Bool

    public init(
        executablePath: String, filePath: String, audioStreamIndex: Int,
        seekTargetSeconds: Double?, usesOutputSeek: Bool
    ) {
        self.executablePath = executablePath
        self.filePath = filePath
        self.audioStreamIndex = audioStreamIndex
        self.seekTargetSeconds = seekTargetSeconds
        self.usesOutputSeek = usesOutputSeek
    }
}

/// 音声デコードプロセスの起動引数（純粋関数。テストで固定する）。
public enum FFmpegAudioProcessArguments {
    public static func arguments(for request: FFmpegAudioProcessRequest) -> [String] {
        var arguments = ["-v", "info", "-nostdin"]
        let seekArguments: [String] = request.seekTargetSeconds.map {
            ["-ss", String(format: "%.6f", $0)]
        } ?? []
        if request.usesOutputSeek {
            arguments += ["-copyts", "-i", request.filePath] + seekArguments
        } else {
            arguments += seekArguments + ["-copyts", "-i", request.filePath]
        }
        arguments += [
            "-map", "0:\(request.audioStreamIndex)",
            "-af", "ashowinfo",
            "-ac", "2",
            "-vn", "-sn", "-dn",
            "-f", "f32le", "-",
        ]
        return arguments
    }
}

/// ashowinfo の1フレーム分の時刻・サンプル数項目。
public struct FFmpegAshowinfoEntry: Equatable, Sendable {
    /// 表示開始時刻（秒。絶対提示時刻）。
    public var startSeconds: Double
    /// このフレームのサンプル数（チャンネルあたり）。
    public var sampleCount: Int

    public init(startSeconds: Double, sampleCount: Int) {
        self.startSeconds = startSeconds
        self.sampleCount = sampleCount
    }
}

/// ashowinfo のログ行の解析（純粋関数）。
///
/// 実測（ffmpeg 9.0.2）で確定した形式:
/// `[Parsed_ashowinfo_0 @ 0x...] n:0 pts:1105 pts_time:0.0230208
///   fmt:fltp channels:2 chlayout:stereo rate:48000 nb_samples:47 ...`
/// `pts_time` は小数表示で、末尾の 0 は省略される（`pts_time:0` もある）。
public enum FFmpegAshowinfoParser {
    /// 行が ashowinfo のフレーム行（pts_time と nb_samples を含む）か。
    /// 証拠用の stderr 抜粋からフレーム行を除外する判定にも使う。
    public static func isFrameEntryLine(_ line: String) -> Bool {
        line.contains("ashowinfo") && line.contains("pts_time:") && line.contains("nb_samples:")
    }

    /// フレーム行から時刻と サンプル数を取り出す。フレーム行でなければ nil。
    public static func parseEntry(fromLine line: String) -> FFmpegAshowinfoEntry? {
        guard isFrameEntryLine(line),
              let start = numberAfterMarker("pts_time:", in: line),
              let count = numberAfterMarker("nb_samples:", in: line)
        else { return nil }
        return FFmpegAshowinfoEntry(startSeconds: start, sampleCount: Int(count))
    }

    private static func numberAfterMarker(_ marker: String, in line: String) -> Double? {
        guard let range = line.range(of: marker) else { return nil }
        var token = ""
        for character in line[range.upperBound...] {
            if character == " " || character == "\t" { break }
            token.append(character)
        }
        guard !token.isEmpty else { return nil }
        return Double(token)
    }
}

/// 音声デコードプロセスの失敗。
public enum FFmpegAudioProcessError: Error {
    /// 要求したバイト数の途中で stdout が終端した（プロセスの異常終了）。
    case stdoutEndedMidChunk
}

/// 実行中の音声デコードプロセスが満たす契約。
///
/// `readNextChunk()` は ashowinfo の項目と stdout のバイト列を対応付け、
/// (データ, 開始時刻) を順に返す。終端では nil を返す（終了状態と
/// stderr の回収もこの時点で完了する）。単一スレッドからの逐次読みを
/// 前提とする（PCMProvider の読み取り前提と同じ）。
public protocol FFmpegAudioProcess: AnyObject {
    /// 次のチャンクを読む。終端なら nil。
    /// データは float32 ステレオインターリーブで、長さは
    /// 項目のサンプル数 × 2ch × 4 バイト（最終チャンクのみ端数が
    /// ありうる）。
    func readNextChunk() throws -> (data: Data, startSeconds: Double)?
    /// これまでにプロセスが生成した総サンプル数（チャンネルあたり）。
    var producedSampleCount: Int { get }
    /// プロセスの終了コード。終了していなければ nil。
    var exitStatus: Int32? { get }
    /// 回収した標準エラー出力（ashowinfo のフレーム行を除く）。
    var collectedStandardError: String { get }
    /// プロセスを終了させる（読み捨て・破棄時）。
    func terminate()
}

/// 音声デコードプロセスの生成口。テストでフェイクへ差し替える。
public protocol FFmpegAudioProcessFactory: Sendable {
    func makeProcess(request: FFmpegAudioProcessRequest) throws -> any FFmpegAudioProcess
}

/// 標準の音声プロセス生成（Foundation.Process で実バイナリを起動する）。
public struct FFmpegAudioProcessRunner: FFmpegAudioProcessFactory {
    public init() {}

    public func makeProcess(request: FFmpegAudioProcessRequest) throws -> any FFmpegAudioProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.executablePath)
        process.arguments = FFmpegAudioProcessArguments.arguments(for: request)
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.standardInput = FileHandle.nullDevice
        try process.run()
        return FFmpegAudioProcessHandle(
            process: process,
            outputHandle: standardOutput.fileHandleForReading,
            errorHandle: standardError.fileHandleForReading,
            seekTargetSeconds: request.seekTargetSeconds
        )
    }
}

/// 実プロセスのラッパ。stderr は別スレッドで読み続け、ashowinfo の
/// 項目キューと証拠テキストへ振り分ける（映像側と同じ方式:
/// `availableData` で都度読む。`read(upToCount:)` は指定バイト数が
/// 揃うか終端まで待つため、stderr の滞留が stdout を止める循環
/// 停滞を起こす — 段階2の実バグ）。
final class FFmpegAudioProcessHandle: FFmpegAudioProcess, @unchecked Sendable {
    /// 目標よりこの秒数以上手前の項目は読み捨てる（入力シーク時の
    /// 混入・出力シーク時の先行フレーム対策。映像側と同じ値）。
    private static let seekEpsilonSeconds = 0.0001

    private let process: Process
    private let outputHandle: FileHandle
    private let seekTargetSeconds: Double?

    private let condition = NSCondition()
    private var entries: [FFmpegAshowinfoEntry] = []
    private var standardErrorFinished = false
    private var standardErrorText = ""
    private var producedSamples = 0
    private var exitStatusValue: Int32?
    private var didReap = false
    private var isTerminated = false

    init(
        process: Process, outputHandle: FileHandle, errorHandle: FileHandle,
        seekTargetSeconds: Double?
    ) {
        self.process = process
        self.outputHandle = outputHandle
        self.seekTargetSeconds = seekTargetSeconds

        Thread.detachNewThread { [weak self] in
            self?.drainStandardError(from: errorHandle)
        }
    }

    // MARK: - stderr の回収

    private func drainStandardError(from handle: FileHandle) {
        var pendingLine = ""
        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            guard let text = String(data: data, encoding: .utf8) else { continue }
            pendingLine += text
            while let newline = pendingLine.firstIndex(of: "\n") {
                let line = String(pendingLine[..<newline])
                pendingLine = String(pendingLine[pendingLine.index(after: newline)...])
                consumeLine(line)
            }
        }
        if !pendingLine.isEmpty { consumeLine(pendingLine) }
        condition.lock()
        standardErrorFinished = true
        condition.broadcast()
        condition.unlock()
    }

    private func consumeLine(_ line: String) {
        if let entry = FFmpegAshowinfoParser.parseEntry(fromLine: line) {
            condition.lock()
            entries.append(entry)
            condition.broadcast()
            condition.unlock()
            return
        }
        condition.lock()
        // 証拠テキストは末尾だけ保持する（上限は映像側と同じ 64KB）。
        if standardErrorText.count > 65_536 {
            standardErrorText = String(standardErrorText.suffix(32_768))
        }
        standardErrorText += line + "\n"
        condition.unlock()
    }

    // MARK: - チャンク読み取り

    func readNextChunk() throws -> (data: Data, startSeconds: Double)? {
        guard let entry = nextEntry() else {
            reap()
            return nil
        }
        let byteCount = entry.sampleCount * 2 * MemoryLayout<Float>.size
        var data = Data()
        data.reserveCapacity(byteCount)
        while data.count < byteCount {
            let piece: Data
            do {
                piece = try outputHandle.read(
                    upToCount: byteCount - data.count
                ) ?? Data()
            } catch {
                if data.isEmpty {
                    reap()
                    return nil
                }
                reap()
                throw FFmpegAudioProcessError.stdoutEndedMidChunk
            }
            if piece.isEmpty {
                if data.isEmpty {
                    reap()
                    return nil
                }
                // チャンク途中の終端は異常（プロセスの途中終了）。
                reap()
                throw FFmpegAudioProcessError.stdoutEndedMidChunk
            }
            data.append(piece)
        }
        condition.lock()
        producedSamples += entry.sampleCount
        condition.unlock()
        return (data, entry.startSeconds)
    }

    /// 目標時刻以降の最初の項目を待って取り出す。目標より手前の項目は
    /// 対応するバイト列ごと読み捨てる（出力シークでは ashowinfo が
    /// 目標手前のフレームも報告するため）。
    private func nextEntry() -> FFmpegAshowinfoEntry? {
        while true {
            condition.lock()
            while entries.isEmpty && !standardErrorFinished {
                condition.wait()
            }
            guard !entries.isEmpty else {
                condition.unlock()
                return nil
            }
            let entry = entries.removeFirst()
            condition.unlock()
            if let target = seekTargetSeconds,
               entry.startSeconds < target - Self.seekEpsilonSeconds {
                // 手前フレームのバイト列を読み捨てて次の項目へ。
                let byteCount = entry.sampleCount * 2 * MemoryLayout<Float>.size
                var remaining = byteCount
                while remaining > 0 {
                    let piece = (try? outputHandle.read(upToCount: remaining)) ?? Data()
                    if piece.isEmpty { return nil }
                    remaining -= piece.count
                }
                condition.lock()
                producedSamples += entry.sampleCount
                condition.unlock()
                continue
            }
            return entry
        }
    }

    // MARK: - 終端処理

    var producedSampleCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return producedSamples
    }

    var exitStatus: Int32? {
        condition.lock()
        defer { condition.unlock() }
        return exitStatusValue
    }

    var collectedStandardError: String {
        condition.lock()
        defer { condition.unlock() }
        return standardErrorText
    }

    func terminate() {
        condition.lock()
        let alreadyTerminated = isTerminated
        isTerminated = true
        condition.unlock()
        if !alreadyTerminated {
            // 読み側を閉じると、stdout のパイプ詰まりで書き込み待ちに
            // なっている ffmpeg が書き込みエラーで終了する。SIGTERM は
            // パイプ詰まり中には処理されない（実測で確認: 3秒待っても
            // 終了しなかった）ため、こちらが確実な止め方になる。
            try? outputHandle.close()
            if process.isRunning {
                process.terminate()
            }
        }
        reap()
    }

    /// プロセスの終了を待ち、終了コードを確定させる（二重に呼ばれても
    /// 安全）。stderr の回収スレッドが終わるまで待つことで、終了直前の
    /// 項目・証拠を取りこぼさない。
    private func reap() {
        condition.lock()
        if didReap {
            condition.unlock()
            return
        }
        didReap = true
        condition.unlock()

        condition.lock()
        while !standardErrorFinished {
            condition.wait()
        }
        condition.unlock()
        process.waitUntilExit()
        condition.lock()
        exitStatusValue = process.terminationStatus
        condition.unlock()
    }
}
