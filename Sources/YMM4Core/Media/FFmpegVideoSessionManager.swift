import Foundation

/// セッション管理者のパラメータ（Issue #70 段階2）。
/// 値はいずれも実測に基づく暫定値であり、出所は各項目に記す。
public struct FFmpegVideoManagerParameters: Sendable {
    /// 同時に生きるデコードプロセスの上限。実測では同時4本で
    /// BGRA 転送が頭打ちになり（合算 約3.2〜3.5GB/s）、4K×4本
    /// では実時間を割った。2 は実測と整合する暫定値（設計判断）。
    public var maxConcurrentProcesses: Int
    /// アイドル破棄までの時間（秒）。設計判断の「数秒」を
    /// パラメータ化したもの。再利用率と起動コストの実測で
    /// 見直す前提。
    public var idleTimeoutSeconds: Double
    /// フレームキャッシュのメモリ上限（バイト）。プロセス側の
    /// RSS 実測（1080p 約243MB / 4K 約891MB）とは別に、供給側で
    /// 保持するデコード済みフレームの上限として置く暫定値。
    public var frameCacheByteLimit: Int
    /// 素材ごとに保持するセッション数の上限。超えたら最も長く
    /// 使われていないものから落とす（ハンドルは次回供給時に
    /// セッションを作り直す）。
    public var maxSessionsPerMaterial: Int
    /// 読み進め／再生成の損益分岐（秒）。セッション設定の同名
    /// 項目の出所を参照。
    public var skipAheadThresholdSeconds: Double
    /// シークの手前余裕（秒）。セッション設定の同名項目参照。
    public var seekPrerollSeconds: Double

    public init(
        maxConcurrentProcesses: Int = 2,
        idleTimeoutSeconds: Double = 5,
        frameCacheByteLimit: Int = 256 * 1024 * 1024,
        maxSessionsPerMaterial: Int = 4,
        skipAheadThresholdSeconds: Double = 2.0,
        seekPrerollSeconds: Double = 1.0
    ) {
        self.maxConcurrentProcesses = maxConcurrentProcesses
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.frameCacheByteLimit = frameCacheByteLimit
        self.maxSessionsPerMaterial = maxSessionsPerMaterial
        self.skipAheadThresholdSeconds = skipAheadThresholdSeconds
        self.seekPrerollSeconds = seekPrerollSeconds
    }
}

/// 管理者経由の供給の失敗。
public enum FFmpegVideoManagerError: Error, Sendable {
    /// FFmpeg が解決できていない。
    case ffmpegUnavailable
    /// ファイルが存在しない。
    case fileNotFound(path: String)
    /// 素材が失敗として確定し、以降の要求は即座に失敗する
    /// （素材の差し替え＝レジストリの reset が起点になる）。
    case materialFailed(MediaAvailabilityFailure)
    /// プロセスが異常終了した。次の要求で1回だけ再生成を試み、
    /// 再び異常終了したら `materialFailed` に確定する。
    case decodeFailed(MediaDecodeEvidence)
    /// 要求が世代の進行で破棄された（失敗ではない）。
    case superseded
}

/// 映像デコードの管理者（プロジェクト単位）。
///
/// 担うもの: プローブ結果の共有、フレームキャッシュ（メモリ
/// 上限つき）、時刻表、セッションの生成とプロセス枠の管理、
/// 異常終了の再試行方針（1回だけ再生成し、繰り返せば失敗に
/// 確定させる）、利用可否（`MediaAvailabilityRegistry`）の駆動。
/// 共有は素材単位の情報までとし、デコードセッション（再生位置）
/// はハンドルごとに所有させる（設計判断）。
public final class FFmpegVideoSessionManager: @unchecked Sendable {
    private let resolution: FFmpegBinaryResolution
    private let registry: MediaAvailabilityRegistry
    private let prober: FFmpegProber
    private let processFactory: any FFmpegVideoProcessFactory
    private let parameters: FFmpegVideoManagerParameters
    private let fileExists: @Sendable (String) -> Bool
    private let now: @Sendable () -> Date
    private let slotGate: FFmpegProcessSlotGate

    private let lock = NSLock()
    private var materials: [MediaMaterialKey: MaterialState] = [:]
    private var cache: [CacheKey: FFmpegVideoFrame] = [:]
    private var cacheOrder: [CacheKey] = []
    private var cacheBytes = 0
    private var idleTimer: DispatchSourceTimer?

    private struct CacheKey: Hashable {
        var material: MediaMaterialKey
        var startTicks: Int64
    }

    private final class MaterialState {
        var probeResult: MediaProbeResult?
        var blockedFailure: MediaAvailabilityFailure?
        var abnormalStreak = 0
        var hasEverBeenAvailable = false
        /// 異常な終端の証拠で失敗に記録済み。以後は供給が成功しても
        /// 利用可へ自動で戻さない（回復は素材差し替え時の reset）。
        var failureLatched = false
        var knownStarts: [Double] = []
        var sessions: [UUID: FFmpegVideoDecodeSession] = [:]
        var handleSessions: [UUID: UUID] = [:]
        var sessionLastUsedAt: [UUID: Date] = [:]
    }

    public init(
        resolution: FFmpegBinaryResolution,
        registry: MediaAvailabilityRegistry,
        prober: FFmpegProber = FFmpegProber(),
        processFactory: any FFmpegVideoProcessFactory = FoundationFFmpegVideoProcessFactory(),
        parameters: FFmpegVideoManagerParameters = FFmpegVideoManagerParameters(),
        fileExists: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        },
        now: @escaping @Sendable () -> Date = { Date() },
        startsIdleTimer: Bool = true
    ) {
        self.resolution = resolution
        self.registry = registry
        self.prober = prober
        self.processFactory = processFactory
        self.parameters = parameters
        self.fileExists = fileExists
        self.now = now
        self.slotGate = FFmpegProcessSlotGate(
            capacity: parameters.maxConcurrentProcesses, now: now
        )
        if startsIdleTimer {
            let timer = DispatchSource.makeTimerSource(
                queue: DispatchQueue.global(qos: .utility)
            )
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in
                self?.sweepIdleSessions()
            }
            timer.resume()
            idleTimer = timer
        }
    }

    deinit {
        idleTimer?.cancel()
    }

    // MARK: ハンドル

    /// 素材のデコードセッション（再生位置）を得る。失敗は
    /// ハンドルの供給時に表面化する。
    public func acquireSession(for key: MediaMaterialKey) -> FFmpegVideoSessionHandle {
        FFmpegVideoSessionHandle(manager: self, materialKey: key, handleID: UUID())
    }

    /// 素材のプローブ情報を返す（GPU 供給が長さ・開始位置を
    /// 先に知るために使う）。プローブの成否は利用可否へ記録する。
    public func probeInfo(for key: MediaMaterialKey) throws -> MediaProbeResult {
        try ensureProbe(for: key)
    }

    // MARK: 供給（ハンドルからの内部経路）

    func serveFrame(
        handleID: UUID, key: MediaMaterialKey, time: TimeSpanValue
    ) throws -> FFmpegVideoFrame {
        lock.lock()
        let state = materialState(for: key)
        if let blocked = state.blockedFailure {
            lock.unlock()
            throw FFmpegVideoManagerError.materialFailed(blocked)
        }
        // フレームキャッシュ（終了時刻が確定したフレームのみ）。
        if let cached = cachedFrame(for: key, at: time) {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let probe = try ensureProbe(for: key)
        let session = try resolveSession(handleID: handleID, key: key, state: state, probe: probe)
        do {
            let frame = try session.frame(at: time)
            handleServeSuccess(key: key, state: state, session: session)
            return frame
        } catch let error as FFmpegVideoSessionError {
            switch error {
            case .superseded:
                throw FFmpegVideoManagerError.superseded
            case .abnormalTermination(let evidence):
                throw handleAbnormalTermination(key: key, state: state, evidence: evidence)
            }
        }
    }

    func releaseHandle(handleID: UUID, key: MediaMaterialKey) {
        lock.lock()
        if let state = materials[key], let sessionID = state.handleSessions[handleID] {
            state.sessionLastUsedAt[sessionID] = now()
            slotGate.touch(id: sessionID)
        }
        lock.unlock()
    }

    func invalidateHandle(handleID: UUID, key: MediaMaterialKey) {
        lock.lock()
        let session = materials[key]
            .flatMap { $0.handleSessions[handleID] }
            .flatMap { materials[key]?.sessions[$0] }
        lock.unlock()
        session?.invalidate()
    }

    /// 素材の記録を捨てる（プロジェクト差し替え時など）。
    /// セッションは無効化し、キャッシュと時刻表も消す。
    public func removeMaterial(for key: MediaMaterialKey) {
        lock.lock()
        let state = materials.removeValue(forKey: key)
        let cacheKeys = cache.keys.filter { $0.material == key }
        for cacheKey in cacheKeys {
            if let frame = cache.removeValue(forKey: cacheKey) {
                cacheBytes -= frame.byteCount
            }
        }
        cacheOrder.removeAll { $0.material == key }
        lock.unlock()
        if let state {
            for session in state.sessions.values {
                session.invalidate()
                slotGate.unregister(id: session.id)
            }
        }
    }

    /// 管理者の終了: 全プロセスを止め、枠の待ちを起こす。
    public func shutdown() {
        idleTimer?.cancel()
        idleTimer = nil
        lock.lock()
        let sessions = materials.values.flatMap { $0.sessions.values }
        lock.unlock()
        for session in sessions {
            session.invalidate()
        }
        slotGate.invalidateAll()
    }

    /// アイドル破棄の実施（タイマとテストから呼ぶ）。
    public func sweepIdleSessions() {
        slotGate.sweepIdle(idleTimeoutSeconds: parameters.idleTimeoutSeconds)
    }

    /// テスト・診断用: 現在生きているプロセス数。
    public var liveProcessCount: Int { slotGate.liveProcessCount }

    // MARK: プローブ

    private func materialState(for key: MediaMaterialKey) -> MaterialState {
        if let state = materials[key] { return state }
        let state = MaterialState()
        materials[key] = state
        return state
    }

    private func ensureProbe(for key: MediaMaterialKey) throws -> MediaProbeResult {
        lock.lock()
        let state = materialState(for: key)
        if let blocked = state.blockedFailure {
            lock.unlock()
            throw FFmpegVideoManagerError.materialFailed(blocked)
        }
        if let probe = state.probeResult {
            lock.unlock()
            return probe
        }
        lock.unlock()

        if registry.state(for: key) == .notAttempted {
            registry.beginLoading(for: key)
        }
        guard resolution.ffmpeg != nil, let ffprobe = resolution.ffprobe else {
            let failure = MediaAvailabilityFailure(
                kind: .ffmpegUnavailable,
                detail: "FFmpeg が解決できていないため素材を開けません。",
                occurredAt: now()
            )
            lock.lock()
            state.blockedFailure = failure
            lock.unlock()
            registry.markFailed(for: key, failure: failure)
            throw FFmpegVideoManagerError.ffmpegUnavailable
        }
        guard fileExists(key.filePath) else {
            let failure = MediaAvailabilityFailure(
                kind: .fileNotFound,
                detail: "ファイルが存在しません: \(key.filePath)",
                occurredAt: now()
            )
            lock.lock()
            state.blockedFailure = failure
            lock.unlock()
            registry.markFailed(for: key, failure: failure)
            throw FFmpegVideoManagerError.fileNotFound(path: key.filePath)
        }
        let probe: MediaProbeResult
        do {
            probe = try prober.probe(path: key.filePath, ffprobePath: ffprobe.path)
        } catch {
            let failure = MediaAvailabilityFailure(
                kind: .unsupportedOrDecodeFailed,
                detail: "ffprobe で素材を解析できませんでした: \(error)",
                occurredAt: now()
            )
            lock.lock()
            state.blockedFailure = failure
            lock.unlock()
            registry.markFailed(for: key, failure: failure)
            throw FFmpegVideoManagerError.materialFailed(failure)
        }
        guard let video = probe.primaryVideoStream,
              let width = video.width, let height = video.height,
              width > 0, height > 0 else {
            let failure = MediaAvailabilityFailure(
                kind: .unsupportedOrDecodeFailed,
                detail: "映像ストリームが無いか、寸法が取得できません。",
                occurredAt: now()
            )
            lock.lock()
            state.blockedFailure = failure
            lock.unlock()
            registry.markFailed(for: key, failure: failure)
            throw FFmpegVideoManagerError.materialFailed(failure)
        }
        lock.lock()
        state.probeResult = probe
        lock.unlock()
        return probe
    }

    // MARK: セッション解決

    private func resolveSession(
        handleID: UUID, key: MediaMaterialKey, state: MaterialState, probe: MediaProbeResult
    ) throws -> FFmpegVideoDecodeSession {
        lock.lock()
        defer { lock.unlock() }
        if let sessionID = state.handleSessions[handleID],
           let session = state.sessions[sessionID] {
            state.sessionLastUsedAt[sessionID] = now()
            return session
        }
        // セッション数の上限: 最も長く使われていないものを落とす。
        if state.sessions.count >= parameters.maxSessionsPerMaterial,
           let oldest = state.sessionLastUsedAt.min(by: { $0.value < $1.value })?.key,
           let dropped = state.sessions.removeValue(forKey: oldest) {
            state.sessionLastUsedAt.removeValue(forKey: oldest)
            for (handle, session) in state.handleSessions where session == oldest {
                state.handleSessions.removeValue(forKey: handle)
            }
            dropped.invalidate()
            slotGate.unregister(id: oldest)
        }
        guard let ffmpeg = resolution.ffmpeg,
              let video = probe.primaryVideoStream else {
            // ensureProbe で先に弾かれているはず。
            throw FFmpegVideoManagerError.ffmpegUnavailable
        }
        let frameRate = video.averageFrameRate
        let configuration = FFmpegVideoSessionConfiguration(
            materialKey: key,
            filePath: key.filePath,
            ffmpegPath: ffmpeg.path,
            videoStreamIndex: video.index,
            width: video.width ?? 0,
            height: video.height ?? 0,
            usesOutputSeek: (probe.formatName ?? "").contains("mpegts"),
            materialStartSeconds: video.startTimeSeconds ?? probe.startTimeSeconds ?? 0,
            materialDurationSeconds: probe.duration?.seconds,
            nominalFrameDurationSeconds: frameRate.map { 1.0 / $0 } ?? (1.0 / 30.0),
            expectedFrameCount: expectedFrameCount(probe: probe),
            skipAheadThresholdSeconds: parameters.skipAheadThresholdSeconds,
            seekPrerollSeconds: parameters.seekPrerollSeconds
        )
        let session = FFmpegVideoDecodeSession(
            configuration: configuration,
            processFactory: processFactory,
            slotGate: slotGate
        )
        session.observer = self
        state.sessions[session.id] = session
        state.handleSessions[handleID] = session.id
        state.sessionLastUsedAt[session.id] = now()
        slotGate.register(id: session.id, session: session)
        return session
    }

    private func expectedFrameCount(probe: MediaProbeResult) -> Int? {
        guard let duration = probe.duration,
              let frameRate = probe.primaryVideoStream?.averageFrameRate,
              frameRate > 0
        else { return nil }
        return Int((duration.seconds * frameRate).rounded())
    }

    // MARK: 結果の記録

    private func handleServeSuccess(
        key: MediaMaterialKey, state: MaterialState, session: FFmpegVideoDecodeSession
    ) {
        lock.lock()
        state.abnormalStreak = 0
        state.hasEverBeenAvailable = true
        let latched = state.failureLatched
        lock.unlock()
        let evidence = session.takePendingEvidence()
        if let evidence, !evidence.failureIndicators.isEmpty {
            // 供給できたが終端が異常だった（打ち切られた素材等）。
            // 途中失敗として記録し、以後は利用可へ自動で戻さない。
            // 供給自体は止めない。
            lock.lock()
            state.failureLatched = true
            lock.unlock()
            registry.markFailed(
                for: key,
                failure: MediaAvailabilityFailure(
                    kind: .midStreamFailure,
                    detail: failureDetail(from: evidence),
                    occurredAt: now()
                ),
                evidence: evidence
            )
            return
        }
        if latched {
            if let evidence {
                registry.recordEvidence(evidence, for: key)
            }
            return
        }
        if registry.state(for: key) != .available {
            registry.markAvailable(for: key, evidence: evidence)
        } else if let evidence {
            registry.recordEvidence(evidence, for: key)
        }
    }

    private func handleAbnormalTermination(
        key: MediaMaterialKey, state: MaterialState, evidence: MediaDecodeEvidence
    ) -> FFmpegVideoManagerError {
        lock.lock()
        state.abnormalStreak += 1
        let streak = state.abnormalStreak
        let everAvailable = state.hasEverBeenAvailable
        lock.unlock()
        if streak >= 2 {
            let failure = MediaAvailabilityFailure(
                kind: everAvailable ? .midStreamFailure : .unsupportedOrDecodeFailed,
                detail: failureDetail(from: evidence),
                occurredAt: now()
            )
            lock.lock()
            state.blockedFailure = failure
            state.failureLatched = true
            lock.unlock()
            registry.markFailed(for: key, failure: failure, evidence: evidence)
            return .materialFailed(failure)
        }
        return .decodeFailed(evidence)
    }

    private func failureDetail(from evidence: MediaDecodeEvidence) -> String {
        var parts = ["FFmpeg デコードが異常終了しました"]
        if let status = evidence.exitStatus {
            parts.append("終了コード \(status)")
        }
        if let produced = evidence.producedFrameCount {
            if let expected = evidence.expectedFrameCount {
                parts.append("生成フレーム数 \(produced)/\(expected)")
            } else {
                parts.append("生成フレーム数 \(produced)")
            }
        }
        let indicators = evidence.failureIndicators.map(\.rawValue)
        if !indicators.isEmpty {
            parts.append("兆候: \(indicators.joined(separator: ", "))")
        }
        return parts.joined(separator: "、")
    }

    // MARK: フレームキャッシュ

    private func cachedFrame(for key: MediaMaterialKey, at time: TimeSpanValue) -> FFmpegVideoFrame? {
        // 開始時刻が要求以下で最大の候補を確認する。
        var best: FFmpegVideoFrame?
        for (cacheKey, frame) in cache where cacheKey.material == key {
            if frame.presentationStart <= time,
               best == nil || frame.presentationStart > best!.presentationStart {
                best = frame
            }
        }
        guard let best, best.contains(time) else { return nil }
        let cacheKey = CacheKey(material: key, startTicks: best.presentationStart.ticks)
        if let index = cacheOrder.firstIndex(of: cacheKey) {
            cacheOrder.remove(at: index)
            cacheOrder.append(cacheKey)
        }
        return best
    }

    private func storeInCache(_ frame: FFmpegVideoFrame, for key: MediaMaterialKey) {
        let cacheKey = CacheKey(material: key, startTicks: frame.presentationStart.ticks)
        if let existing = cache[cacheKey] {
            cacheBytes -= existing.byteCount
            if let index = cacheOrder.firstIndex(of: cacheKey) {
                cacheOrder.remove(at: index)
            }
        }
        cache[cacheKey] = frame
        cacheBytes += frame.byteCount
        cacheOrder.append(cacheKey)
        // 上限を超えた分は古いものから落とす。ただし今入れた
        // フレーム自体が上限より大きい場合は保持できない。
        while cacheBytes > parameters.frameCacheByteLimit, let oldest = cacheOrder.first {
            if oldest == cacheKey { break }
            cacheOrder.removeFirst()
            if let removed = cache.removeValue(forKey: oldest) {
                cacheBytes -= removed.byteCount
            }
        }
        if cacheBytes > parameters.frameCacheByteLimit, cache[cacheKey] != nil {
            cache.removeValue(forKey: cacheKey)
            cacheBytes -= frame.byteCount
            cacheOrder.removeAll { $0 == cacheKey }
        }
    }
}

// MARK: - 観測（時刻表とキャッシュへの記録）

extension FFmpegVideoSessionManager: FFmpegVideoSessionObserver {
    public func videoSession(
        _ session: FFmpegVideoDecodeSession,
        didReadFrame frame: FFmpegVideoFrame, endIsFinal: Bool
    ) {
        let key = session.configuration.materialKey
        lock.lock()
        let state = materialState(for: key)
        let start = frame.presentationStart.seconds
        if !state.knownStarts.contains(start) {
            state.knownStarts.append(start)
            state.knownStarts.sort()
        }
        if endIsFinal {
            storeInCache(frame, for: key)
        }
        state.sessionLastUsedAt[session.id] = now()
        lock.unlock()
        slotGate.touch(id: session.id)
    }

    public func videoSession(
        _ session: FFmpegVideoDecodeSession,
        knownFrameStartAtOrBefore time: TimeSpanValue
    ) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let state = materials[session.configuration.materialKey] else { return nil }
        var result: Double?
        for start in state.knownStarts {
            if start <= time.seconds + FFmpegVideoProcessArguments.pairingEpsilonSeconds {
                result = start
            } else {
                break
            }
        }
        return result
    }
}

// MARK: - ハンドル

/// デコードセッション（再生位置）の借り手。
/// 供給は同期で、失敗は `FFmpegVideoManagerError` で返る。
public final class FFmpegVideoSessionHandle: @unchecked Sendable {
    public let materialKey: MediaMaterialKey
    private let handleID: UUID
    private weak var manager: FFmpegVideoSessionManager?

    init(manager: FFmpegVideoSessionManager, materialKey: MediaMaterialKey, handleID: UUID) {
        self.manager = manager
        self.materialKey = materialKey
        self.handleID = handleID
    }

    /// 指定時刻（絶対提示時刻）を含むフレームを返す。
    public func frame(at time: TimeSpanValue) throws -> FFmpegVideoFrame {
        guard let manager else {
            throw FFmpegVideoManagerError.superseded
        }
        return try manager.serveFrame(handleID: handleID, key: materialKey, time: time)
    }

    /// 借り手が当面使わないことを伝える。プロセスはアイドル
    /// 破棄の対象として残る（即座には止めない）。
    public func release() {
        manager?.releaseHandle(handleID: handleID, key: materialKey)
    }

    /// この再生位置のセッションを無効化する（素材差し替え時等）。
    public func invalidate() {
        manager?.invalidateHandle(handleID: handleID, key: materialKey)
    }
}
