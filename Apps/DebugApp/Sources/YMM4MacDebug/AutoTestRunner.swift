import AppKit
import Foundation
import YMM4Core
import YMM4GPU

/// 全自動テストの画面側の状態（MAC-0038）。
/// 測定本体は `AutoTestJob` がバックグラウンドで実行し、結果は
/// ここへ MainActor 経由で戻る。レポートファイルへの書き出しも
/// ジョブ側で行い、画面はその写しを表示するだけにする。
@MainActor
final class AutoTestState: ObservableObject {
    @Published var isRunning = false
    @Published var report: AutoTestReport?
    @Published var reportFilePath: String?
    @Published var errorMessage: String?

    /// 測定対象のプロジェクトを解決して実行する。
    /// - 開いているプロジェクト（ファイルから読み込んだもの）があればそれ
    /// - 無ければ同梱サンプル（Apps/DebugApp/Sample/sample.ymmp）
    /// - サンプルも読めなければ、開いている（空の）プロジェクトで測る
    /// 測定は書き出しと同じ専有スナップショットに対して行い、測定中の
    /// 画面編集と競合させない（AUD-07 と同じ方針）。
    func run(workspace: WorkspaceState, trigger: String) {
        guard !isRunning else { return }

        let target: (
            project: Project, source: String, path: String?, baseDirectory: URL?
        )
        if let url = workspace.sourceURL {
            target = (
                workspace.project, "open", url.path,
                url.deletingLastPathComponent()
            )
        } else if let sampleURL = Self.sampleProjectURL(),
                  let (loaded, _) = try? YmmpCodec.load(fromFile: sampleURL.path) {
            target = (
                loaded, "sample", sampleURL.path,
                sampleURL.deletingLastPathComponent()
            )
        } else {
            target = (workspace.project, "open", nil, nil)
        }

        guard let timeline = target.project.timelines.first else {
            errorMessage = "測定対象のタイムラインがありません"
            return
        }

        let jobTimelines: [Timeline]
        let jobTimeline: Timeline
        let snapshotUsed: Bool
        if let snapshot = try? target.project.makeExportSnapshot(of: timeline) {
            jobTimelines = snapshot.timelines
            jobTimeline = snapshot.timeline
            snapshotUsed = true
        } else {
            jobTimelines = target.project.timelines
            jobTimeline = timeline
            snapshotUsed = false
        }

        let job = AutoTestJob(
            timeline: jobTimeline,
            timelines: jobTimelines,
            baseDirectory: target.baseDirectory,
            projectSource: target.source,
            projectPath: target.path,
            snapshotUsed: snapshotUsed,
            trigger: trigger
        )
        isRunning = true
        errorMessage = nil
        Task.detached {
            let (finishedReport, writtenURL) = job.execute()
            await MainActor.run {
                self.isRunning = false
                self.report = finishedReport
                self.reportFilePath = writtenURL?.path
                if AutoTestEnvironment.exitAfterRun {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    /// 同梱サンプルの場所（このソースファイルからの相対位置で解決する。
    /// デバッグアプリはソースツリーと一緒に動く前提）。
    private static func sampleProjectURL() -> URL? {
        let here = URL(fileURLWithPath: #filePath)
        let appDirectory = here
            .deletingLastPathComponent()  // YMM4MacDebug/
            .deletingLastPathComponent()  // Sources/
            .deletingLastPathComponent()  // DebugApp/
        let sample = appDirectory.appendingPathComponent("Sample/sample.ymmp")
        return FileManager.default.fileExists(atPath: sample.path) ? sample : nil
    }
}

/// 全自動テストの測定ジョブ。保持するモデルは開始時点のスナップショット
/// であり、単一のバックグラウンドスレッドからのみ触れるため
/// unchecked とする（ExportJob と同じ形態）。
final class AutoTestJob: @unchecked Sendable {
    private let timeline: Timeline
    private let timelines: [Timeline]
    private let baseDirectory: URL?
    private let projectSource: String
    private let projectPath: String?
    private let snapshotUsed: Bool
    private let trigger: String

    init(
        timeline: Timeline, timelines: [Timeline], baseDirectory: URL?,
        projectSource: String, projectPath: String?, snapshotUsed: Bool,
        trigger: String
    ) {
        self.timeline = timeline
        self.timelines = timelines
        self.baseDirectory = baseDirectory
        self.projectSource = projectSource
        self.projectPath = projectPath
        self.snapshotUsed = snapshotUsed
        self.trigger = trigger
    }

    private static var buildConfiguration: String {
        #if DEBUG
            return "debug"
        #else
            return "release"
        #endif
    }

    private func now() -> Double {
        ProcessInfo.processInfo.systemUptime
    }

    func execute() -> (AutoTestReport, URL?) {
        var notes: [String] = [
            "素材ファイルが存在しないアイテムは透明フォールバックで合成される"
                + "（本家の実素材はこの Mac 上に無いため、デコード費用は含まれない）"
        ]
        if Self.buildConfiguration == "debug" {
            notes.append(
                "debug（未最適化）ビルドの測定。CPU 処理の実時間比は release "
                    + "ビルドと大きく異なるため、性能比較は release のレポートで行うこと"
            )
        }
        if !snapshotUsed {
            notes.append(
                "スナップショット生成に失敗したため、開いているモデルを直接測定した"
            )
        }

        let info = timeline.videoInfo
        var report = AutoTestReport(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            trigger: trigger,
            buildConfiguration: Self.buildConfiguration,
            machine: AutoTestEnvironment.machineInfo(),
            project: AutoTestReport.ProjectInfo(
                source: projectSource,
                path: projectPath,
                timelineIndex: 0,
                width: info.width,
                height: info.height,
                fps: info.fps,
                hz: info.hz,
                lengthFrames: timeline.length,
                itemCount: timeline.items.count,
                snapshotUsed: snapshotUsed
            ),
            startupSeconds: AutoTestEnvironment.startupSeconds,
            memoryResidentMB: 0,
            memoryFootprintMB: 0,
            notes: notes
        )

        let gpuResults = measureCompositionAndSeek()
        report.composition = gpuResults.composition
        report.seek = gpuResults.seek
        report.audio = measureAudio()
        report.export = measureExport()

        let memory = AutoTestEnvironment.currentMemoryBytes()
        report.memoryResidentMB = Double(memory.resident) / 1_048_576
        report.memoryFootprintMB = Double(memory.footprint) / 1_048_576

        let written = Self.writeReport(report)
        return (report, written)
    }

    // MARK: - レポート書き出し

    /// レポートを固定パスへ書く（日時つき＋ latest.json の併用）。
    /// 測定値の正本はこのファイルであり、文書へは転記しない。
    private static func writeReport(_ report: AutoTestReport) -> URL? {
        do {
            try AutoTestEnvironment.prepareReportDirectory()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let stamped = AutoTestEnvironment.reportDirectory
                .appendingPathComponent(
                    "report-\(formatter.string(from: Date())).json"
                )
            try data.write(to: stamped, options: .atomic)
            try data.write(
                to: AutoTestEnvironment.reportDirectory
                    .appendingPathComponent("latest.json"),
                options: .atomic
            )
            return stamped
        } catch {
            return nil
        }
    }

    // MARK: - 合成・シーク

    /// プレビューと同じ合成セッション（PreviewBox と同じ生成手順を
    /// ここでも組み立て、update のみ／読み戻し込みを分けて測れるように
    /// したもの）。経路の実体（デバイス・文脈・供給元・合成器）は
    /// プレビューと同一である。
    private final class CompositionSession {
        let devices: MetalGraphicsDevices
        let context: MetalGraphicsContext
        let composer: TimelineComposer
        let videoInfo: VideoInfo

        init?(timeline: Timeline, timelines: [Timeline], baseDirectory: URL?) {
            guard let devices = MetalGraphicsDevices() else { return nil }
            self.devices = devices
            self.videoInfo = timeline.videoInfo
            self.context = devices.makeContext(
                targetSize: PixelSize(
                    width: videoInfo.width, height: videoInfo.height
                )
            )
            let effectProvider = MetalEffectPairProvider(devices: devices)
            let provider = MetalSourceProvider(
                devices: devices, baseDirectory: baseDirectory,
                sceneResolver: { id in timelines.first { $0.id == id } },
                timeline: timeline,
                effectProvider: effectProvider
            )
            self.composer = TimelineComposer(
                scene: TimelineScene(timeline: timeline),
                targetFactory: context,
                sourceProvider: provider.source(for:),
                effectProvider: effectProvider,
                alphaMaskFactory: MetalAlphaMaskEffectFactory(context: context)
            )
        }

        func update(frame: Int) throws {
            context.targetSize = PixelSize(
                width: videoInfo.width, height: videoInfo.height
            )
            let seconds = FrameTime.time(fromFrame: frame, fps: videoInfo.fps)
            try composer.update(
                time: TimeSpanValue(seconds: seconds), usage: .paused
            )
        }

        /// 合成結果を CGImage へ読み戻す（プレビューの表示経路）。
        func readback() -> Bool {
            guard let output = composer.output else { return false }
            return devices.makeCGImage(from: output) != nil
        }

        func dispose() {
            composer.dispose()
        }
    }

    private func measureCompositionAndSeek()
        -> (composition: AutoTestReport.CompositionResult,
            seek: AutoTestReport.SeekResult)
    {
        var composition = AutoTestReport.CompositionResult()
        var seek = AutoTestReport.SeekResult()
        guard let session = CompositionSession(
            timeline: timeline, timelines: timelines,
            baseDirectory: baseDirectory
        ) else {
            composition.error = "Metal デバイスを初期化できませんでした"
            seek.error = composition.error
            return (composition, seek)
        }
        defer { session.dispose() }

        let length = max(timeline.length, 1)

        // ウォームアップ（シェーダコンパイル等は初回に寄るため数えない）。
        _ = try? session.update(frame: 0)
        _ = session.readback()

        // 合成時間: タイムライン全体から最大30フレームを等間隔に取る。
        let sampleCount = min(30, length)
        let strideLength = max(1, length / sampleCount)
        var frames: [Int] = []
        var frame = 0
        while frame < length, frames.count < sampleCount {
            frames.append(frame)
            frame += strideLength
        }
        if frames.last != length - 1 {
            frames.append(length - 1)
        }
        composition.frames = frames

        var updateMs: [Double] = []
        var totalMs: [Double] = []
        for target in frames {
            let start = now()
            do {
                try session.update(frame: target)
            } catch {
                composition.error = "フレーム \(target) の合成に失敗: \(error)"
                break
            }
            let afterUpdate = now()
            _ = session.readback()
            let afterReadback = now()
            updateMs.append((afterUpdate - start) * 1000)
            totalMs.append((afterReadback - start) * 1000)
        }
        if composition.error == nil {
            composition.updateOnlyMs = Self.distribution(updateMs)
            composition.updateAndReadbackMs = Self.distribution(totalMs)
            if let readback = composition.updateAndReadbackMs {
                composition.p95WithinBudget = readback.p95 <= composition.budgetMs
            }
        }

        // シーク応答: 非連続な位置へ順に飛び、描画が返るまでを測る。
        let candidates = [
            length / 2, 0, length - 1, length / 4, (3 * length) / 4,
            min(10, length - 1), length / 3,
        ]
        var targets: [Int] = []
        for candidate in candidates where !targets.contains(candidate) {
            targets.append(candidate)
        }
        seek.targetFrames = targets
        for target in targets {
            let start = now()
            do {
                try session.update(frame: target)
            } catch {
                seek.error = "フレーム \(target) へのシークに失敗: \(error)"
                break
            }
            _ = session.readback()
            seek.responseMs.append((now() - start) * 1000)
        }
        if seek.error == nil, !seek.responseMs.isEmpty {
            seek.averageMs =
                seek.responseMs.reduce(0, +) / Double(seek.responseMs.count)
            seek.maxMs = seek.responseMs.max()
        }
        return (composition, seek)
    }

    private static func distribution(
        _ values: [Double]
    ) -> AutoTestReport.Distribution? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let p95Index = min(
            sorted.count - 1,
            max(0, Int((0.95 * Double(sorted.count)).rounded(.up)) - 1)
        )
        return AutoTestReport.Distribution(
            average: values.reduce(0, +) / Double(values.count),
            p95: sorted[p95Index],
            max: sorted[sorted.count - 1]
        )
    }

    // MARK: - 音声

    private func makeAudioFactory() -> AudioSourceFactory {
        AudioSourceFactory(
            providerFactory: AVFoundationPCMProviderFactory(
                baseDirectory: baseDirectory
            ),
            sceneTimelineResolver: { [timelines] id in
                timelines.first { $0.id == id }
            }
        )
    }

    private func measureAudio() -> AutoTestReport.AudioResult {
        AutoTestReport.AudioResult(
            timelineMix: measureTimelineMix(),
            resampler44100To48000: resamplerBenchmark(
                inHz: 44_100, outHz: 48_000
            ),
            resampler48000To44100: resamplerBenchmark(
                inHz: 48_000, outHz: 44_100
            )
        )
    }

    /// タイムライン全体ミックスのオフライン処理速度（先頭最大10秒）。
    private func measureTimelineMix() -> AutoTestReport.Throughput {
        var result = AutoTestReport.Throughput()
        let mixer = TimelineAudioMixer(
            timeline: timeline, factory: makeAudioFactory()
        )
        let hz = timeline.videoInfo.hz
        let targetSamples = min(mixer.duration, 10 * hz * 2)
        guard targetSamples > 0, hz > 0 else {
            result.error = "ミックス対象の長さが0です"
            return result
        }
        var buffer = [Float](repeating: 0, count: 8192)
        var remaining = targetSamples
        let start = now()
        while remaining > 0 {
            let read = mixer.read(
                into: &buffer, offset: 0, count: min(buffer.count, remaining)
            )
            if read <= 0 { break }
            remaining -= read
        }
        let elapsed = now() - start
        let readSeconds = Double(targetSamples - remaining) / Double(hz * 2)
        result.materialSeconds = readSeconds
        result.elapsedSeconds = elapsed
        result.realtimeRatio = elapsed > 0 ? readSeconds / elapsed : 0
        return result
    }

    /// リサンプラ単体のスループット（Kaiser 正式形）。
    /// 1kHz 正弦波・10秒を読み切るまでの時間から実時間比を出す。
    /// 素材を長くしても比率は変わらないため、未最適化ビルドでも
    /// 終わる長さに抑えている（それでも debug では分単位かかりうる。
    /// 性能の正本は release ビルドのレポートとする）。
    private func resamplerBenchmark(
        inHz: Int, outHz: Int, seconds: Double = 10
    ) -> AutoTestReport.Throughput {
        var result = AutoTestReport.Throughput()
        let frameCount = Int(Double(inHz) * seconds)
        var samples: [Float] = []
        samples.reserveCapacity(frameCount * 2)
        for frameIndex in 0..<frameCount {
            let value = Float(
                0.5 * sin(
                    2 * Double.pi * 1000 * Double(frameIndex) / Double(inHz)
                )
            )
            samples.append(value)
            samples.append(value)
        }
        let stream = ResamplerStream(toHz: outHz)
        stream.input = FileAudioStream(
            provider: InMemoryPCMProvider(samples: samples, hz: inHz)
        )
        stream.seek(to: 0)
        var buffer = [Float](repeating: 0, count: 16_384)
        var produced = 0
        let start = now()
        while true {
            let read = stream.read(
                into: &buffer, offset: 0, count: buffer.count
            )
            if read <= 0 { break }
            produced += read
            if stream.duration > 0, produced >= stream.duration { break }
        }
        let elapsed = now() - start
        result.materialSeconds = seconds
        result.elapsedSeconds = elapsed
        result.realtimeRatio = elapsed > 0 ? seconds / elapsed : 0
        return result
    }

    // MARK: - 書き出し

    /// 固定区間（先頭最大180フレーム）の書き出し速度。
    /// TimelineExporter のファサードと同じ供給側・セッション構成を、
    /// 範囲だけ区切って実行する（本番の書き出し経路そのもの）。
    private func measureExport() -> AutoTestReport.ExportResult {
        var result = AutoTestReport.ExportResult()
        let length = timeline.length
        guard length > 0 else {
            result.error = "タイムラインの長さが0です"
            return result
        }
        let frameCount = min(180, length)
        result.rangeStart = 0
        result.frameCount = frameCount
        let ffmpeg = Self.resolveFFmpegPath()
        result.ffmpegPath = ffmpeg
        let outputURL = AutoTestEnvironment.reportDirectory
            .appendingPathComponent("autotest-export.mp4")
        try? AutoTestEnvironment.prepareReportDirectory()

        let preparationStart = now()
        guard let videoProvider = MetalExportVideoProvider(
            timeline: timeline, timelines: timelines,
            baseDirectory: baseDirectory
        ) else {
            result.error = "Metal デバイスを初期化できませんでした"
            return result
        }
        defer { videoProvider.dispose() }
        let audioProvider = TimelineExportAudioProvider(
            timeline: timeline, factory: makeAudioFactory()
        )
        result.preparationSeconds = now() - preparationStart

        let settings = FFmpegExportSettings(
            videoInfo: timeline.videoInfo, length: frameCount
        )
        do {
            let writer = try FFmpegProcessWriter(
                settings: settings, outputPath: outputURL.path,
                executablePath: ffmpeg
            )
            let session = ExportSession(writer: writer)
            let runStart = now()
            let outcome = session.run(
                configuration: ExportSession.Configuration(
                    outputPath: outputURL.path,
                    videoInfo: timeline.videoInfo,
                    frameRange: 0..<frameCount
                ),
                videoProvider: videoProvider,
                audioProvider: audioProvider
            )
            result.runSeconds = now() - runStart
            result.framesWritten = outcome.framesWritten
            result.completion = "\(outcome.completion)"
            result.framesPerSecond = result.runSeconds > 0
                ? Double(outcome.framesWritten) / result.runSeconds : 0
            if outcome.completion == .failed {
                result.error = outcome.error?.message ?? "書き出しが失敗しました"
            }
        } catch {
            result.error = "ffmpeg を起動できませんでした: \(error)"
        }
        if let attributes = try? FileManager.default.attributesOfItem(
            atPath: outputURL.path
        ), let size = attributes[.size] as? Int {
            result.outputBytes = size
        }
        try? FileManager.default.removeItem(at: outputURL)
        return result
    }

    private static func resolveFFmpegPath() -> String {
        for candidate in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return "ffmpeg"
    }
}
