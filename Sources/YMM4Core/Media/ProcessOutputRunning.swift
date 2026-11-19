import Foundation

/// 子プロセスを起動し、標準出力・標準エラーを全て回収してから戻る
/// 一括実行の抽象（Issue #70 段階1）。
///
/// 書き出し側の `ExportProcessRunning` は標準入力へストリーミングで
/// 流し込むための別契約であり、こちらは「短いコマンドを1回実行して
/// 出力全文を得る」用途（バージョン確認、ffprobe のプローブ）に使う。
/// テストではフェイクへ差し替える。
public protocol ProcessOutputRunning: Sendable {
    /// プロセスを起動して終了まで待ち、出力を回収する。
    /// 起動自体に失敗した場合は例外を投げる。
    func run(executablePath: String, arguments: [String]) throws -> ProcessOutput
}

/// 一括実行の結果。
public struct ProcessOutput: Equatable, Sendable {
    public var terminationStatus: Int32
    public var standardOutput: Data
    public var standardError: Data

    public init(terminationStatus: Int32, standardOutput: Data, standardError: Data) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var standardOutputText: String {
        String(data: standardOutput, encoding: .utf8) ?? ""
    }

    public var standardErrorText: String {
        String(data: standardError, encoding: .utf8) ?? ""
    }
}

/// Foundation.Process による一括実行の実体。
///
/// 標準出力と標準エラーは別々の読み取りで並行に回収する（片方の
/// パイプが満杯のまま他方を読み切る構成だと、出力の大きいコマンド
/// で詰まるため）。標準入力は null デバイスへつなぎ、対話待ちで
/// 止まることを防ぐ。
public struct FoundationProcessOutputRunner: ProcessOutputRunning {
    public init() {}

    public func run(executablePath: String, arguments: [String]) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()

        // 両パイプを並行に読み切ってから終了を待つ。
        let group = DispatchGroup()
        var outputData = Data()
        var errorData = Data()
        group.enter()
        DispatchQueue.global().async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.wait()
        process.waitUntilExit()
        return ProcessOutput(
            terminationStatus: process.terminationStatus,
            standardOutput: outputData,
            standardError: errorData
        )
    }
}
