import Foundation

/// FFmpeg 系ツールのバイナリ解決（Issue #70 段階1）。
///
/// 読み込み（デコード・プローブ）と書き出しで共用する解決層。
/// 検索順は設計判断どおり:
/// (1) アプリ同梱バイナリ → (2) 明示設定のパス →
/// (3) 開発環境の既知パス（/opt/homebrew/bin 等）→ (4) PATH。
/// 実行可能でない候補は「無い」ものとして次へ進む（利用可否の
/// 最終判定はバージョン検証 `FFmpegToolchainVerifier` が担う）。
///
/// 既存の書き出し経路（`FFmpegProcessWriter` の `executablePath`、
/// `TimelineExporter` の `ffmpegPath`）はパス文字列を受け取る形の
/// ため、本解決層の結果をそのまま渡せる。既存の呼び出し箇所の
/// 移行は段階的に行う（本単位では挙動を変えない）。

// MARK: - 解決結果

/// バイナリがどこから解決されたか。
public enum FFmpegToolSource: String, Equatable, Sendable {
    /// アプリのバンドル内に同梱されたバイナリ。
    case bundled
    /// 利用者・設定が明示したパス。
    case configured
    /// 開発環境の既知パス（Homebrew 等）。
    case development
    /// 環境変数 PATH からの検索。
    case environmentPath
}

/// 解決されたツール1件。
public struct ResolvedFFmpegTool: Equatable, Sendable {
    /// ツール名（"ffmpeg" / "ffprobe"）。
    public var toolName: String
    /// 実行ファイルの絶対パス。
    public var path: String
    /// 解決元。
    public var source: FFmpegToolSource

    public init(toolName: String, path: String, source: FFmpegToolSource) {
        self.toolName = toolName
        self.path = path
        self.source = source
    }
}

/// ffmpeg / ffprobe の解決結果一式。片方だけ解決されることもある。
public struct FFmpegBinaryResolution: Equatable, Sendable {
    public var ffmpeg: ResolvedFFmpegTool?
    public var ffprobe: ResolvedFFmpegTool?

    public init(ffmpeg: ResolvedFFmpegTool?, ffprobe: ResolvedFFmpegTool?) {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
    }

    /// 両方が解決されているか。
    public var isComplete: Bool { ffmpeg != nil && ffprobe != nil }
}

// MARK: - 解決層

public struct FFmpegBinaryResolver: Sendable {
    public static let ffmpegToolName = "ffmpeg"
    public static let ffprobeToolName = "ffprobe"

    /// (1) アプリ同梱バイナリを探すディレクトリ列。
    public var bundledDirectories: [String]
    /// (2) ツール名 → 明示パスの対応。
    public var configuredPaths: [String: String]
    /// (3) 開発環境の既知ディレクトリ列。
    public var developmentDirectories: [String]
    /// (4) PATH の値（":" 区切り）。nil なら PATH 検索を行わない。
    public var environmentPathValue: String?

    private let isExecutable: @Sendable (String) -> Bool

    public init(
        bundledDirectories: [String] = FFmpegBinaryResolver.defaultBundledDirectories(),
        configuredPaths: [String: String] = [:],
        developmentDirectories: [String] = ["/opt/homebrew/bin", "/usr/local/bin"],
        environmentPathValue: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: @escaping @Sendable (String) -> Bool = {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    ) {
        self.bundledDirectories = bundledDirectories
        self.configuredPaths = configuredPaths
        self.developmentDirectories = developmentDirectories
        self.environmentPathValue = environmentPathValue
        self.isExecutable = isExecutable
    }

    /// 既定の同梱候補: 実行ファイルのあるディレクトリ、その
    /// `Helpers` サブディレクトリ、リソースディレクトリ。
    /// 製品バンドルへの同梱配置が決まったら、この候補が土台になる。
    public static func defaultBundledDirectories() -> [String] {
        var directories: [String] = []
        if let executableURL = Bundle.main.executableURL {
            let directory = executableURL.deletingLastPathComponent()
            directories.append(directory.path)
            directories.append(directory.appendingPathComponent("Helpers").path)
        }
        if let resourceURL = Bundle.main.resourceURL {
            directories.append(resourceURL.path)
        }
        return directories
    }

    /// ツール名で1件を解決する。見つからなければ nil。
    public func resolve(tool name: String) -> ResolvedFFmpegTool? {
        for directory in bundledDirectories {
            let candidate = (directory as NSString).appendingPathComponent(name)
            if isExecutable(candidate) {
                return ResolvedFFmpegTool(toolName: name, path: candidate, source: .bundled)
            }
        }
        if let configured = configuredPaths[name], isExecutable(configured) {
            return ResolvedFFmpegTool(toolName: name, path: configured, source: .configured)
        }
        for directory in developmentDirectories {
            let candidate = (directory as NSString).appendingPathComponent(name)
            if isExecutable(candidate) {
                return ResolvedFFmpegTool(toolName: name, path: candidate, source: .development)
            }
        }
        if let pathValue = environmentPathValue {
            for directory in pathValue.split(separator: ":") where !directory.isEmpty {
                let candidate = (String(directory) as NSString).appendingPathComponent(name)
                if isExecutable(candidate) {
                    return ResolvedFFmpegTool(
                        toolName: name, path: candidate, source: .environmentPath
                    )
                }
            }
        }
        return nil
    }

    /// ffmpeg と ffprobe の両方を解決する。
    public func resolveAll() -> FFmpegBinaryResolution {
        FFmpegBinaryResolution(
            ffmpeg: resolve(tool: Self.ffmpegToolName),
            ffprobe: resolve(tool: Self.ffprobeToolName)
        )
    }
}

// MARK: - バージョン検証（起動時検証）

/// `-version` 先頭行から取り出したバージョン情報。
public struct FFmpegToolVersion: Equatable, Sendable {
    public var toolName: String
    /// 実行ファイルの絶対パス。
    public var path: String
    /// 版数文字列（例: "9.0.2"）。
    public var version: String
    /// バナー先頭行の全文。
    public var bannerLine: String

    public init(toolName: String, path: String, version: String, bannerLine: String) {
        self.toolName = toolName
        self.path = path
        self.version = version
        self.bannerLine = bannerLine
    }

    /// バナー先頭行（"<tool> version <版数> ..."）から版数を取る。
    /// 形式が合わなければ nil。
    public static func versionToken(fromBannerLine line: String, toolName: String) -> String? {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard tokens.count >= 3, tokens[0] == Substring(toolName), tokens[1] == "version"
        else { return nil }
        return String(tokens[2])
    }
}

/// ツール1件の検証が失敗した理由。
public enum FFmpegToolVerificationFailure: Equatable, Sendable {
    /// 解決できていない。
    case notResolved
    /// 起動自体に失敗した（例外の説明文）。
    case launchFailed(String)
    /// 終了コードが 0 でない。
    case nonZeroExit(Int32)
    /// バナーから版数を読み取れなかった。
    case unparsableVersionOutput
}

/// ツール1件の検証結果。
public struct FFmpegToolVerification: Equatable, Sendable {
    public var toolName: String
    public var resolvedPath: String?
    public var version: FFmpegToolVersion?
    public var failure: FFmpegToolVerificationFailure?

    public init(
        toolName: String,
        resolvedPath: String?,
        version: FFmpegToolVersion?,
        failure: FFmpegToolVerificationFailure?
    ) {
        self.toolName = toolName
        self.resolvedPath = resolvedPath
        self.version = version
        self.failure = failure
    }

    /// 起動して版数が取れているか。
    public var isUsable: Bool { version != nil }
}

/// ffmpeg / ffprobe の組合せ検証結果。
public struct FFmpegToolchainVerification: Equatable, Sendable {
    public var ffmpeg: FFmpegToolVerification
    public var ffprobe: FFmpegToolVerification

    public init(ffmpeg: FFmpegToolVerification, ffprobe: FFmpegToolVerification) {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
    }

    /// 組合せとして使えるか（両方の版数が取れていること）。
    public var isUsable: Bool { ffmpeg.isUsable && ffprobe.isUsable }
}

/// 解決済みバイナリを実際に起動し、`-version` の版数が取れること
/// までを確認する起動時検証。
public struct FFmpegToolchainVerifier: Sendable {
    private let runner: any ProcessOutputRunning

    public init(runner: any ProcessOutputRunning = FoundationProcessOutputRunner()) {
        self.runner = runner
    }

    public func verify(resolution: FFmpegBinaryResolution) -> FFmpegToolchainVerification {
        FFmpegToolchainVerification(
            ffmpeg: verify(tool: resolution.ffmpeg, toolName: FFmpegBinaryResolver.ffmpegToolName),
            ffprobe: verify(tool: resolution.ffprobe, toolName: FFmpegBinaryResolver.ffprobeToolName)
        )
    }

    private func verify(tool: ResolvedFFmpegTool?, toolName: String) -> FFmpegToolVerification {
        guard let tool else {
            return FFmpegToolVerification(
                toolName: toolName, resolvedPath: nil, version: nil, failure: .notResolved
            )
        }
        do {
            let output = try runner.run(executablePath: tool.path, arguments: ["-version"])
            guard output.terminationStatus == 0 else {
                return FFmpegToolVerification(
                    toolName: tool.toolName, resolvedPath: tool.path, version: nil,
                    failure: .nonZeroExit(output.terminationStatus)
                )
            }
            let firstLine = output.standardOutputText
                .split(separator: "\n", omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
            guard let token = FFmpegToolVersion.versionToken(
                fromBannerLine: firstLine, toolName: tool.toolName
            ) else {
                return FFmpegToolVerification(
                    toolName: tool.toolName, resolvedPath: tool.path, version: nil,
                    failure: .unparsableVersionOutput
                )
            }
            return FFmpegToolVerification(
                toolName: tool.toolName, resolvedPath: tool.path,
                version: FFmpegToolVersion(
                    toolName: tool.toolName, path: tool.path,
                    version: token, bannerLine: firstLine
                ),
                failure: nil
            )
        } catch {
            return FFmpegToolVerification(
                toolName: tool.toolName, resolvedPath: tool.path, version: nil,
                failure: .launchFailed(String(describing: error))
            )
        }
    }
}
