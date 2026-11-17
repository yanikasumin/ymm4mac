import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// FFmpeg プロセスライター（本家 `FFmpegVideoFileWriter` の方式再現）。
///
/// 音声と映像を別々の ffmpeg プロセスで別ファイルへ書き、finalize で
/// `-c copy` の mux プロセスを起動して最終ファイルにする（W6-4.1）。
/// 音声プロセスは初期化時に起動し、映像プロセスは最初のフレームで
/// 遅延起動する。映像はコーデックに応じて NV12（色空間メタデータ付き）
/// または BGRA（メタデータなし）で標準入力へ流す（W6-4.1.3 / W6-5.3）。
///
/// プロセス起動は `ExportProcessRunning` の差し替え点に分離し、
/// コマンド生成は `FFmpegArguments` の純粋関数に寄せてある。
/// 実 ffmpeg の実行自体はこの芯のテスト対象に含めない。
///
/// 本家との意図的な差分:
/// - 本家は映像書き込みを内部キューで非同期化し、例外は保持して
///   次回書き込み時または Dispose で再送出する。ここでは書き込みを
///   同期化し、その場でも例外を投げるが、保持と finalize での再送出、
///   mux を実行しない点は本家どおり維持する。
/// - 本家に終了コードの明示検査はない（W6-4.1.6）。Mac 版では
///   W6-C8 に従い、終了コードと stderr の検査を writer の責務に含める。

// MARK: - プロセス起動の差し替え点

/// 起動済みプロセスのハンドル。
public protocol ExportProcessHandle: AnyObject {
    /// 標準入力へ書き込む。失敗したら例外。
    func writeToStandardInput(_ data: Data) throws
    /// 標準入力を閉じる（書き込み終了の合図）。
    func closeStandardInput()
    /// 終了を待ち、終了コードと標準エラーの全文を返す。
    func waitForExit() -> (terminationStatus: Int32, standardError: String)
    /// プロセスを強制終了する（書き込み失敗時の後始末）。
    func terminate()
}

/// プロセス起動の抽象。実体は `FoundationProcessRunner`。
public protocol ExportProcessRunning {
    func launch(executablePath: String, arguments: [String]) throws -> ExportProcessHandle
}

// MARK: - stderr のエラー分類（W6-7.4）

/// ffmpeg の stderr 文言から、利用者に提示できる失敗種別へ寄せる分類器。
/// 本家 `TryGetEncodeSettingsErrorMessage` の部分一致表を再現する
/// （大文字小文字を区別しない）。一致した場合は「原因が特定でき、
/// 利用者の対処で解消しうる」エラーとして分類し、一致しなければ
/// 原因不明として扱う。出力の成否とは別の軸である（EX17-08）。
public enum FFmpegErrorClassifier {
    private static let table: [(patterns: [String], message: String)] = [
        (["no space left on device"], "ストレージの空き容量が不足しています"),
        (["permission denied"], "ファイルへのアクセス権限がありません"),
        (
            ["unknown encoder", "error selecting an encoder", "encoder not found"],
            "指定されたエンコーダーが見つかりません"
        ),
        (
            ["codec not currently supported in container", "could not find tag for codec"],
            "コーデックとコンテナの組み合わせが対応していません"
        ),
        (["not widely supported"], "ピクセルフォーマットがコンテナで広くサポートされていません"),
        (["paramvalidationext"], "解像度が大きすぎます"),
        (
            ["unrecognized option", "option not found", "error parsing options"],
            "FFmpeg オプションが不正です"
        ),
        (
            ["error submitting video frame to the encoder", "device failed"],
            "ハードウェアエンコーダーでエラーが発生しました"
        ),
    ]

    public static func classify(standardError: String, fallbackMessage: String) -> ExportError {
        let lowered = standardError.lowercased()
        for entry in table where entry.patterns.contains(where: { lowered.contains($0) }) {
            return ExportError(cause: .actionable, message: entry.message)
        }
        return ExportError(cause: .unresolvable, message: fallbackMessage)
    }
}

// MARK: - NV12 変換

/// BGRA → NV12（BT.709 / リミテッドレンジ）の純粋関数変換。
///
/// 本家は D3D11 Video Processor で変換しており、係数と丸めの
/// 画素単位一致は未検証（W6-U09）。ここでは BT.709 の標準係数で
/// 変換する。色差は 2×2 平均でサブサンプリングする。
public enum NV12Conversion {
    public static func convert(bgra: [UInt8], width: Int, height: Int) -> [UInt8] {
        guard width > 0, height > 0 else { return [] }
        var output = [UInt8](repeating: 0, count: width * height * 3 / 2)

        func pixel(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double) {
            let clampedX = min(max(x, 0), width - 1)
            let clampedY = min(max(y, 0), height - 1)
            let offset = (clampedY * width + clampedX) * 4
            guard offset + 2 < bgra.count else { return (0, 0, 0) }
            return (
                r: Double(bgra[offset + 2]),
                g: Double(bgra[offset + 1]),
                b: Double(bgra[offset])
            )
        }
        func clamp(_ value: Double) -> UInt8 {
            UInt8(min(255, max(0, value.rounded())))
        }

        for y in 0..<height {
            for x in 0..<width {
                let p = pixel(x, y)
                let luma = 16 + (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b) * (219.0 / 255.0)
                output[y * width + x] = clamp(luma)
            }
        }
        let uvBase = width * height
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                var r = 0.0
                var g = 0.0
                var b = 0.0
                for dy in 0..<2 {
                    for dx in 0..<2 {
                        let p = pixel(x + dx, y + dy)
                        r += p.r
                        g += p.g
                        b += p.b
                    }
                }
                r /= 4
                g /= 4
                b /= 4
                let u = 128 + (-0.1146 * r - 0.3854 * g + 0.5 * b) * (224.0 / 255.0)
                let v = 128 + (0.5 * r - 0.4542 * g - 0.0458 * b) * (224.0 / 255.0)
                let uvOffset = uvBase + (y / 2) * width + x
                if uvOffset < output.count { output[uvOffset] = clamp(u) }
                if uvOffset + 1 < output.count { output[uvOffset + 1] = clamp(v) }
            }
        }
        return output
    }
}

// MARK: - ライター本体

public final class FFmpegProcessWriter: VideoFileWriting {
    /// 開始時に確定した設定スナップショット。
    public let settings: FFmpegExportSettings
    /// 最終出力パス。
    public let outputPath: String

    private let runner: ExportProcessRunning
    private let executablePath: String
    private let layout: FFmpegOutputLayout
    private let useNV12: Bool

    private var audioProcess: ExportProcessHandle?
    private var videoProcess: ExportProcessHandle?
    private var videoStarted = false
    private var storedWriteError: ExportError?
    private var finalized = false

    /// 申告は常に映像＋音声。設定による内部無効化（`-f null`）では
    /// 変えない（W6-C2）。
    public var supportedStreams: VideoWriterSupportedStreams { [.video, .audio] }

    /// 成果物ファイルが生成されるかどうか。音声・映像の両方が
    /// `-f null` の構成ではどちらのプロセスも最終ファイルへ書かず、
    /// mux も行われないため false（EX17-07）。片方だけの無効化では
    /// 残る側が最終ファイルへ直接書くため true。
    public var producesOutputFile: Bool {
        !(layout.skipsAudioProcess && layout.skipsVideo)
    }

    /// この writer は CPU の BGRA バッファを受ける。GPU フレームの
    /// 直接受け取りは申告しない。
    public var isGPUFrameSupported: Bool { false }

    /// 音声プロセスを起動して書き出しを開始する（本家のコンストラクタ）。
    public init(
        settings: FFmpegExportSettings,
        outputPath: String,
        runner: ExportProcessRunning = FoundationProcessRunner(),
        executablePath: String = "ffmpeg"
    ) throws {
        self.settings = settings
        self.outputPath = outputPath
        self.runner = runner
        self.executablePath = executablePath
        let audioArguments = FFmpegArguments.audioArgs(settings: settings)
        let videoArguments = FFmpegArguments.videoArgs(settings: settings)
        layout = FFmpegOutputLayout.resolve(
            outputPath: outputPath, audioArgs: audioArguments, videoArgs: videoArguments
        )
        let codec = videoArguments["c:v"] ?? "h264"
        useNV12 = FFmpegArguments.isYUVCodec(codec)
        if !layout.skipsAudioProcess {
            do {
                audioProcess = try runner.launch(
                    executablePath: executablePath,
                    arguments: FFmpegArguments.audioProcessArguments(
                        settings: settings, layout: layout
                    )
                )
            } catch {
                throw ExportError(
                    cause: .unresolvable,
                    message: "音声エンコードプロセスの起動に失敗しました",
                    underlying: error
                )
            }
        }
    }

    /// 音声サンプルを f32le バイト列として音声プロセスへ書く。
    /// 音声プロセスが無い（単独出力モード）場合は何もしない（本家どおり）。
    public func writeAudioSamples(_ samples: [Float]) throws {
        guard let audioProcess else { return }
        var data = Data()
        data.reserveCapacity(samples.count * 4)
        for sample in samples {
            var littleEndian = sample.bitPattern.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        do {
            try audioProcess.writeToStandardInput(data)
        } catch {
            throw ExportError(
                cause: .unresolvable,
                message: "音声の書き込みに失敗しました",
                underlying: error
            )
        }
    }

    /// 映像フレームを書く。初回に映像プロセスを遅延起動する。
    /// バッファは借用であり、このメソッドの中でバイト列へ変換して
    /// 書き切る（復帰後の参照は保持しない — W6-C4）。
    public func writeVideoFrame(_ frame: ExportVideoFrameBuffer) throws {
        if layout.skipsVideo { return }
        if let storedWriteError { throw storedWriteError }
        do {
            if !videoStarted {
                videoProcess = try runner.launch(
                    executablePath: executablePath,
                    arguments: FFmpegArguments.videoProcessArguments(
                        settings: settings, layout: layout, useNV12: useNV12
                    )
                )
                videoStarted = true
            }
            guard let videoProcess else { return }
            let data: Data
            if useNV12 {
                data = Data(
                    NV12Conversion.convert(
                        bgra: frame.bytes, width: settings.width, height: settings.height
                    )
                )
            } else {
                data = Data(frame.bytes)
            }
            try videoProcess.writeToStandardInput(data)
        } catch {
            // 本家は書き込み例外を保持し、プロセスを止めて、
            // 次回書き込みまたは finalize で再送出する。
            let wrapped = (error as? ExportError) ?? ExportError(
                cause: .unresolvable,
                message: "映像の書き込みに失敗しました",
                underlying: error
            )
            storedWriteError = wrapped
            videoProcess?.terminate()
            throw wrapped
        }
    }

    /// 終了手続き。本家の Dispose の順序を再現する:
    /// 入力を閉じて両プロセスの終了を待つ → 保持した書き込み例外が
    /// あれば mux せずに投げる → 終了コードを検査する（W6-C8 の追加）
    /// → mux → 一時ファイルを消す。
    public func finalize() throws {
        guard !finalized else { return }
        finalized = true

        var videoStatus: Int32 = 0
        var videoError = ""
        if let videoProcess {
            videoProcess.closeStandardInput()
            let result = videoProcess.waitForExit()
            videoStatus = result.terminationStatus
            videoError = result.standardError
        }
        var audioStatus: Int32 = 0
        var audioError = ""
        if let audioProcess {
            audioProcess.closeStandardInput()
            let result = audioProcess.waitForExit()
            audioStatus = result.terminationStatus
            audioError = result.standardError
        }

        if let storedWriteError {
            throw storedWriteError
        }
        if audioProcess != nil, audioStatus != 0 {
            throw FFmpegErrorClassifier.classify(
                standardError: audioError,
                fallbackMessage: "音声エンコードが終了コード \(audioStatus) で失敗しました"
            )
        }
        if videoProcess != nil, videoStatus != 0 {
            throw FFmpegErrorClassifier.classify(
                standardError: videoError,
                fallbackMessage: "映像エンコードが終了コード \(videoStatus) で失敗しました"
            )
        }

        guard layout.hasTempFiles else { return }
        let muxProcess: ExportProcessHandle
        do {
            muxProcess = try runner.launch(
                executablePath: executablePath,
                arguments: FFmpegArguments.muxProcessArguments(
                    layout: layout, outputPath: outputPath
                )
            )
        } catch {
            throw ExportError(
                cause: .unresolvable,
                message: "mux プロセスの起動に失敗しました",
                underlying: error
            )
        }
        muxProcess.closeStandardInput()
        let muxResult = muxProcess.waitForExit()
        if muxResult.terminationStatus != 0 {
            throw FFmpegErrorClassifier.classify(
                standardError: muxResult.standardError,
                fallbackMessage: "mux が終了コード \(muxResult.terminationStatus) で失敗しました"
            )
        }
        try? FileManager.default.removeItem(atPath: layout.audioTargetPath)
        try? FileManager.default.removeItem(atPath: layout.videoTargetPath)
    }
}

// MARK: - 実プロセス起動（薄い層）

/// Foundation.Process による実プロセス起動。
/// テストでは使わず、フェイクに差し替える。
public final class FoundationProcessRunner: ExportProcessRunning {
    public init() {}

    public func launch(executablePath: String, arguments: [String]) throws -> ExportProcessHandle {
        // パイプ破断で SIGPIPE に殺されないよう、無視設定を一度だけ入れる。
        signal(SIGPIPE, SIG_IGN)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.resolvePath(executablePath))
        process.arguments = arguments
        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        return FoundationProcessHandle(
            process: process, inputPipe: inputPipe, errorPipe: errorPipe
        )
    }

    /// "/" を含まない名前は PATH から解決する（本家は PATH 前提の "ffmpeg"）。
    private static func resolvePath(_ name: String) -> String {
        if name.contains("/") { return name }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return name
    }
}

/// stderr の読み取りは専用の非同期ブロックが担い、結果は DispatchGroup の
/// 完了後にだけ読む。書き込みと終了待ちは呼び出し側スレッドに限定されるため、
/// Sendable は unchecked で宣言する。
private final class FoundationProcessHandle: ExportProcessHandle, @unchecked Sendable {
    private let process: Process
    private let inputPipe: Pipe
    private let errorPipe: Pipe
    private let errorGroup = DispatchGroup()
    private var errorData = Data()
    private var inputClosed = false

    init(process: Process, inputPipe: Pipe, errorPipe: Pipe) {
        self.process = process
        self.inputPipe = inputPipe
        self.errorPipe = errorPipe
        errorGroup.enter()
        DispatchQueue.global().async { [self] in
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            errorGroup.leave()
        }
    }

    func writeToStandardInput(_ data: Data) throws {
        let descriptor = inputPipe.fileHandleForWriting.fileDescriptor
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var written = 0
            while written < raw.count {
                let result = write(descriptor, base + written, raw.count - written)
                if result < 0 {
                    throw NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(errno),
                        userInfo: [NSLocalizedDescriptionKey: "標準入力への書き込みに失敗しました"]
                    )
                }
                written += result
            }
        }
    }

    func closeStandardInput() {
        guard !inputClosed else { return }
        inputClosed = true
        try? inputPipe.fileHandleForWriting.close()
    }

    func waitForExit() -> (terminationStatus: Int32, standardError: String) {
        process.waitUntilExit()
        closeStandardInput()
        errorGroup.wait()
        return (
            process.terminationStatus,
            String(data: errorData, encoding: .utf8) ?? ""
        )
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}
