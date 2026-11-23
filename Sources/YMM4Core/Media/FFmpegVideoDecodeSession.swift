import Foundation

/// 映像デコードセッションの設定（Issue #70 段階2）。
///
/// 時刻はすべて素材の絶対提示時刻（コンテナの開始オフセットを
/// 含む）で扱う。論理時刻への読み替えは消費側（GPU 供給）の責務。
public struct FFmpegVideoSessionConfiguration: Sendable {
    public var materialKey: MediaMaterialKey
    /// 開くファイルのパス（呼び出し側で解決済みのもの）。
    public var filePath: String
    public var ffmpegPath: String
    /// プローブの主映像ストリームのインデックス。
    public var videoStreamIndex: Int
    public var width: Int
    public var height: Int
    /// TS コンテナか（出力シークへの分岐。実測で入力シークが
    /// 信頼できないことが確定している）。
    public var usesOutputSeek: Bool
    /// 素材の提示開始位置（秒、絶対時刻）。
    public var materialStartSeconds: Double
    /// 素材の長さ（秒）。プローブで未確定なら nil。
    public var materialDurationSeconds: Double?
    /// 公称フレーム長（秒）。フレームの表示終了時刻の暫定値と、
    /// 最終フレームの終了時刻の推定に使う。
    public var nominalFrameDurationSeconds: Double
    /// 期待フレーム数（プローブの長さ×フレームレートからの見積もり。
    /// 証拠の照合用。不明なら nil）。
    public var expectedFrameCount: Int?
    /// 読み進め（C_continue）と再生成（C_restart）の損益分岐を
    /// 時刻差で表したパラメータ（秒）。前方移動がこれ以下なら
    /// 読み進め、これを超えたらプロセスを張り替える。
    /// 出所: 着工前実測の損益分岐は前方 1.6〜2.5 秒（720p、
    /// C_restart 中央値 79〜126ms ÷ 読み進め単価 約50ms/秒）。
    /// 実測時は Mac が高負荷（load average 10.6〜17.8）だったため
    /// 絶対値は割り引く必要があり、通常負荷での再計測までは
    /// 実測範囲の中央付近に置く暫定値とする。解像度が上がると
    /// 読み進め単価も上がるため、この値は解像度非依存ではない。
    public var skipAheadThresholdSeconds: Double
    /// プロセス開始位置を要求時刻より手前に置く余裕（秒）。
    /// ffmpeg のシークは「pts < 目標」を捨てるため、目標ちょうど
    /// から始めると要求時刻を含むフレームを失う。これを避ける
    /// ための余裕であり、性能の閾値ではない。前提は「この余裕
    /// より長いフレームは無い」ことで、破れた場合は余裕を広げて
    /// 再試行する（`maxPrerollEscalations`）。
    public var seekPrerollSeconds: Double
    /// 手前余裕の拡大の上限回数。
    public var maxPrerollEscalations: Int
    /// フレームの時刻項目を待つ上限（秒）。
    public var entryWaitTimeoutSeconds: Double

    public init(
        materialKey: MediaMaterialKey, filePath: String, ffmpegPath: String,
        videoStreamIndex: Int, width: Int, height: Int, usesOutputSeek: Bool,
        materialStartSeconds: Double, materialDurationSeconds: Double?,
        nominalFrameDurationSeconds: Double, expectedFrameCount: Int?,
        skipAheadThresholdSeconds: Double = 2.0,
        seekPrerollSeconds: Double = 1.0,
        maxPrerollEscalations: Int = 3,
        entryWaitTimeoutSeconds: Double = 10
    ) {
        self.materialKey = materialKey
        self.filePath = filePath
        self.ffmpegPath = ffmpegPath
        self.videoStreamIndex = videoStreamIndex
        self.width = width
        self.height = height
        self.usesOutputSeek = usesOutputSeek
        self.materialStartSeconds = materialStartSeconds
        self.materialDurationSeconds = materialDurationSeconds
        self.nominalFrameDurationSeconds = nominalFrameDurationSeconds
        self.expectedFrameCount = expectedFrameCount
        self.skipAheadThresholdSeconds = skipAheadThresholdSeconds
        self.seekPrerollSeconds = seekPrerollSeconds
        self.maxPrerollEscalations = maxPrerollEscalations
        self.entryWaitTimeoutSeconds = entryWaitTimeoutSeconds
    }

    /// 素材終端の絶対時刻。長さ未確定なら nil。
    public var materialEndSeconds: Double? {
        materialDurationSeconds.map { materialStartSeconds + $0 }
    }

    /// BGRA 1フレームのバイト数。
    public var frameByteCount: Int { width * height * 4 }
}

/// セッションの失敗。
public enum FFmpegVideoSessionError: Error, Equatable, Sendable {
    /// 世代が進んだ（無効化・退避）ため、この要求は破棄された。
    /// 失敗ではないので、利用可否の記録対象にしない。
    case superseded
    /// プロセスが異常終了し、要求したフレームを供給できない。
    /// 証拠（終了コード・生成フレーム数・標準エラーの兆候）つき。
    case abnormalTermination(MediaDecodeEvidence)
}

/// セッションがフレームを読んだことの通知先（管理者が時刻表と
/// フレームキャッシュへ記録する）。
public protocol FFmpegVideoSessionObserver: AnyObject, Sendable {
    /// フレームが読まれた。`endIsFinal` が false の間の表示終了
    /// 時刻は暫定（開始＋公称フレーム長）であり、確定した時点で
    /// 同じ開始時刻のフレームが再通知される。
    func videoSession(
        _ session: FFmpegVideoDecodeSession,
        didReadFrame frame: FFmpegVideoFrame, endIsFinal: Bool
    )

    /// 時刻表に記録済みの、指定時刻以下で最大のフレーム開始時刻
    /// （秒、絶対提示時刻）。無ければ nil。シーク目標を正確な
    /// フレーム開始位置へ合わせるために使う（pts ちょうどの
    /// シークではそのフレームが残ることが実測で確定している）。
    func videoSession(
        _ session: FFmpegVideoDecodeSession,
        knownFrameStartAtOrBefore time: TimeSpanValue
    ) -> Double?
}

public extension FFmpegVideoSessionObserver {
    func videoSession(
        _ session: FFmpegVideoDecodeSession,
        knownFrameStartAtOrBefore time: TimeSpanValue
    ) -> Double? { nil }
}

// MARK: - プロセス枠のゲート

/// 同時に生きるデコードプロセス数の上限を管理するゲート。
///
/// 実測では同時 4 本で BGRA 転送が頭打ちになり（合算 約3.2〜3.5
/// GB/s、4K×4 では実時間を割る）、プロセスの RSS は 1080p で
/// 約243MB・4K で約891MB に達した。同時実行数の初期値 2 は
/// 実測と整合する暫定値（設計判断）。
/// 枠が足りない場合は、使用中でないセッションのうち最も長く
/// 使われていないもののプロセスを退避させる。使用中しかない
/// 場合は解放を待つ。
final class FFmpegProcessSlotGate: @unchecked Sendable {
    private struct Entry {
        weak var session: FFmpegVideoDecodeSession?
        var holdsSlot = false
        var lastUsedAt: Date
    }

    private let condition = NSCondition()
    private var entries: [UUID: Entry] = [:]
    private var invalidated = false
    let capacity: Int
    private let now: @Sendable () -> Date

    init(capacity: Int, now: @escaping @Sendable () -> Date) {
        self.capacity = max(1, capacity)
        self.now = now
    }

    func register(id: UUID, session: FFmpegVideoDecodeSession) {
        condition.lock()
        entries[id] = Entry(session: session, lastUsedAt: now())
        condition.unlock()
    }

    func unregister(id: UUID) {
        condition.lock()
        entries.removeValue(forKey: id)
        condition.broadcast()
        condition.unlock()
    }

    func touch(id: UUID) {
        condition.lock()
        entries[id]?.lastUsedAt = now()
        condition.unlock()
    }

    /// プロセス開始の枠を確保する。必要なら退避させ、それでも
    /// 空かなければ解放されるまで待つ。ゲートが無効化されていたら
    /// `superseded` を投げる。
    func acquire(id: UUID) throws {
        while true {
            condition.lock()
            if invalidated {
                condition.unlock()
                throw FFmpegVideoSessionError.superseded
            }
            // 解放されずに消えたセッションの枠は回収する。
            for (entryID, entry) in entries where entry.session == nil && entry.holdsSlot {
                entries[entryID]?.holdsSlot = false
            }
            let holders = entries.filter { $0.value.holdsSlot }
            if holders.count < capacity || entries[id]?.holdsSlot == true {
                entries[id]?.holdsSlot = true
                entries[id]?.lastUsedAt = now()
                condition.unlock()
                return
            }
            // 退避候補: 枠を持ち、使用中でなく、最も古いもの。
            let victim = holders
                .filter { $0.key != id }
                .sorted { $0.value.lastUsedAt < $1.value.lastUsedAt }
                .first(where: { $0.value.session?.isServing == false })
            condition.unlock()
            if let victim, let session = victim.value.session {
                // 退避はゲートのロックの外で行う（退避先の解放が
                // このロックを取るため）。
                _ = session.evictProcess()
                continue
            }
            if victim == nil {
                condition.lock()
                if !invalidated {
                    condition.wait()
                }
                condition.unlock()
            }
        }
    }

    /// 枠を解放する（プロセスの終了・破棄時にセッションが呼ぶ）。
    func release(id: UUID) {
        condition.lock()
        entries[id]?.holdsSlot = false
        condition.broadcast()
        condition.unlock()
    }

    /// アイドル破棄: 制限時間を超えて使われていないプロセスを
    /// 退避させる。管理者が定期的に、テストが手動で呼ぶ。
    func sweepIdle(idleTimeoutSeconds: Double) {
        let reference = now()
        condition.lock()
        for (entryID, entry) in entries where entry.session == nil && entry.holdsSlot {
            entries[entryID]?.holdsSlot = false
        }
        let candidates = entries.filter {
            $0.value.holdsSlot
                && reference.timeIntervalSince($0.value.lastUsedAt) > idleTimeoutSeconds
        }.map { $0.value.session }
        condition.unlock()
        for case let session? in candidates {
            _ = session.evictProcess()
        }
    }

    /// 全体を無効化し、待ちを全て起こす（管理者の終了時）。
    func invalidateAll() {
        condition.lock()
        invalidated = true
        condition.broadcast()
        condition.unlock()
    }

    /// テスト・診断用: 現在枠を持っているセッション数。
    var liveProcessCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return entries.values.filter { $0.holdsSlot }.count
    }
}

// MARK: - セッション

/// 映像デコードセッション（再生位置ごとに1つ）。
///
/// ffmpeg 子プロセスから BGRA を前方ストリーミングで受け、
/// 要求時刻を含むフレームを pts 基準で選んで返す。フレームの
/// 表示終了時刻は次のフレームの開始時刻で決める（showinfo の
/// duration は実測で実際と食い違う場合があったため使わない）。
///
/// 所有: プロセスは本セッションが所有し、終了・退避・無効化で
/// 確実に破棄する。要求は直列化され（要求ロック）、無効化だけは
/// 要求の途中でも割り込める（世代を進め、プロセスを終了させる
/// ことでブロック中の読み取りを起こし、`superseded` に倒す）。
public final class FFmpegVideoDecodeSession: @unchecked Sendable {
    public let id: UUID
    public let configuration: FFmpegVideoSessionConfiguration
    private let processFactory: any FFmpegVideoProcessFactory
    private let slotGate: FFmpegProcessSlotGate

    public weak var observer: (any FFmpegVideoSessionObserver)?

    private let requestLock = NSLock()
    private let stateLock = NSLock()
    private var process: (any FFmpegVideoProcess)?
    /// 現在のプロセスのシーク目標（nil は先頭から）。
    private var processSeekTargetSeconds: Double?
    /// 最後に読んだフレーム（表示終了時刻は暫定）。
    private var lastReadFrame: FFmpegVideoFrame?
    /// 終了時刻が確定した直近のフレーム。
    private var lastFinalizedFrame: FFmpegVideoFrame?
    /// 現在のプロセスが終端に達したか。
    private var streamEnded = false
    /// 終端で確定した最終フレーム。
    private var endOfStreamFrame: FFmpegVideoFrame?
    private var generation = 0
    private var serving = false
    /// 終端したプロセスの証拠（消費側が取り出すまで保持）。
    private var pendingEvidence: MediaDecodeEvidence?

    /// 生成は管理者（同じモジュール内）が担う。プロセス枠ゲートは
    /// 内部型のため、初期化子も内部に留める。
    init(
        id: UUID = UUID(),
        configuration: FFmpegVideoSessionConfiguration,
        processFactory: any FFmpegVideoProcessFactory,
        slotGate: FFmpegProcessSlotGate
    ) {
        self.id = id
        self.configuration = configuration
        self.processFactory = processFactory
        self.slotGate = slotGate
    }

    deinit {
        process?.terminate()
    }

    /// 要求を処理中か（ゲートの退避判定用）。
    var isServing: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return serving
    }

    /// 終端したプロセスの証拠を取り出す（取り出すと消える）。
    /// 管理者が供給の成否に応じて利用可否を記録するために使う。
    public func takePendingEvidence() -> MediaDecodeEvidence? {
        stateLock.lock()
        defer { stateLock.unlock() }
        let evidence = pendingEvidence
        pendingEvidence = nil
        return evidence
    }

    // MARK: フレーム供給

    /// 指定時刻（絶対提示時刻）を含むフレームを返す。
    public func frame(at time: TimeSpanValue) throws -> FFmpegVideoFrame {
        requestLock.lock()
        defer { requestLock.unlock() }
        stateLock.lock()
        serving = true
        let requestGeneration = generation
        stateLock.unlock()
        defer {
            stateLock.lock()
            serving = false
            stateLock.unlock()
        }
        slotGate.touch(id: id)
        return try serve(time: time, requestGeneration: requestGeneration)
    }

    private func serve(time: TimeSpanValue, requestGeneration: Int) throws -> FFmpegVideoFrame {
        // 素材開始より前は先頭フレームへ寄せる（AVFoundation 経路の
        // 負時刻の扱いと同じ）。
        let time = max(time, TimeSpanValue(seconds: configuration.materialStartSeconds))

        // 保持中のフレームで答えられる場合。
        stateLock.lock()
        let finalized = lastFinalizedFrame
        let ended = streamEnded
        let eosFrame = endOfStreamFrame
        stateLock.unlock()
        if let finalized, finalized.contains(time) {
            return finalized
        }
        if ended, let eosFrame, time >= eosFrame.presentationStart {
            return eosFrame
        }

        var preroll = configuration.seekPrerollSeconds
        var escalations = 0
        var needsStart = try shouldStartProcess(for: time)
        while true {
            if needsStart {
                try startProcess(for: time, preroll: preroll, requestGeneration: requestGeneration)
                needsStart = false
            }
            // 読み進める。
            while true {
                stateLock.lock()
                let currentLastRead = lastReadFrame
                let currentFinalized = lastFinalizedFrame
                stateLock.unlock()
                if let currentFinalized, currentFinalized.contains(time) {
                    return currentFinalized
                }
                if let currentLastRead {
                    if time < currentLastRead.presentationStart {
                        // このプロセスの到達範囲より前。ただし
                        // 開始直後の1枚目が要求より後なら、シークで
                        // 含むフレームが捨てられた可能性がある。
                        if isFirstFrameOfCurrentProcess(currentLastRead) {
                            if escalations < configuration.maxPrerollEscalations {
                                escalations += 1
                                preroll *= 4
                                needsStart = true
                                break
                            }
                            // 拡大しても届かない場合は、得られる
                            // 最も早いフレームを返す（記録に残す）。
                            return currentLastRead
                        }
                        needsStart = true
                        break
                    }
                    if time == currentLastRead.presentationStart {
                        // 開始ちょうどはこのフレーム。終了時刻の
                        // 確定には次のフレームが要るため読み進める。
                    }
                }
                let outcome = try readNextFrame(requestGeneration: requestGeneration)
                switch outcome {
                case .frame:
                    continue
                case .endOfStream:
                    return try frameAfterEndOfStream(time: time)
                }
            }
        }
    }

    /// 現在のプロセスで要求へ読み進められるか、張り替えが要るか。
    private func shouldStartProcess(for time: TimeSpanValue) throws -> Bool {
        stateLock.lock()
        let currentProcess = process
        let seekTarget = processSeekTargetSeconds
        let lastRead = lastReadFrame
        let ended = streamEnded
        stateLock.unlock()
        guard let currentProcess else { return true }
        _ = currentProcess
        if ended { return true }
        // このプロセスの開始位置より前は届かない。
        if let seekTarget, time.seconds < seekTarget { return true }
        if let lastRead {
            // 既に読み過ぎている（後方への要求）。
            if time < lastRead.presentationStart { return true }
            // 前方への大きな移動は張り替えが安い。
            if time.seconds - lastRead.presentationStart.seconds
                > configuration.skipAheadThresholdSeconds {
                return true
            }
        }
        return false
    }

    /// 現在のプロセスで最初に読んだフレームか。
    private func isFirstFrameOfCurrentProcess(_ frame: FFmpegVideoFrame) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return lastFinalizedFrame == nil && lastReadFrame?.presentationStart == frame.presentationStart
    }

    // MARK: プロセスの開始と終了

    private func startProcess(
        for time: TimeSpanValue, preroll: Double, requestGeneration: Int
    ) throws {
        tearDownProcessLocked()
        try slotGate.acquire(id: id)
        let target = seekTarget(for: time, preroll: preroll)
        let request = FFmpegVideoProcessRequest(
            ffmpegPath: configuration.ffmpegPath,
            filePath: configuration.filePath,
            videoStreamIndex: configuration.videoStreamIndex,
            frameByteCount: configuration.frameByteCount,
            seekTargetSeconds: target,
            seekStyle: configuration.usesOutputSeek ? .output : .input,
            entryWaitTimeoutSeconds: configuration.entryWaitTimeoutSeconds
        )
        let newProcess: any FFmpegVideoProcess
        do {
            newProcess = try processFactory.makeProcess(request: request)
        } catch {
            slotGate.release(id: id)
            throw FFmpegVideoSessionError.abnormalTermination(
                MediaDecodeEvidence(
                    exitStatus: nil, producedFrameCount: 0,
                    expectedFrameCount: configuration.expectedFrameCount,
                    standardErrorExcerpt: String(describing: error)
                )
            )
        }
        stateLock.lock()
        if generation != requestGeneration {
            stateLock.unlock()
            newProcess.terminate()
            slotGate.release(id: id)
            throw FFmpegVideoSessionError.superseded
        }
        process = newProcess
        processSeekTargetSeconds = target
        lastReadFrame = nil
        lastFinalizedFrame = nil
        streamEnded = false
        endOfStreamFrame = nil
        // 前のプロセスの証拠は、そのプロセスの異常終了として
        // 例外経由で既に渡っている。新しいプロセスの供給結果へ
        // 混入させないため、開始時に消す。
        pendingEvidence = nil
        stateLock.unlock()
    }

    /// シーク目標の決定: 時刻表（観測側経由で管理者から引く）に
    /// 要求以下で最大の開始時刻があればそれ（pts ちょうどの
    /// シークはそのフレームが残ることが実測で確定している）。
    /// 無ければ要求時刻から手前余裕を引いた位置。素材開始以下に
    /// なれば nil（先頭から）。
    private func seekTarget(for time: TimeSpanValue, preroll: Double) -> Double? {
        var candidate = time.seconds - preroll
        if let known = observer?.videoSession(self, knownFrameStartAtOrBefore: time) {
            candidate = max(candidate, known)
        }
        if candidate <= configuration.materialStartSeconds {
            return nil
        }
        return candidate
    }

    /// プロセスを破棄し、枠を解放する（状態は呼び出し側で整える）。
    private func tearDownProcessLocked() {
        stateLock.lock()
        let oldProcess = process
        process = nil
        processSeekTargetSeconds = nil
        stateLock.unlock()
        if oldProcess != nil {
            oldProcess?.terminate()
            slotGate.release(id: id)
        }
    }

    /// ゲートからの退避。使用中でなければプロセスを破棄する。
    @discardableResult
    func evictProcess() -> Bool {
        stateLock.lock()
        if serving || process == nil {
            stateLock.unlock()
            return false
        }
        let oldProcess = process
        process = nil
        processSeekTargetSeconds = nil
        lastReadFrame = nil
        lastFinalizedFrame = nil
        streamEnded = false
        endOfStreamFrame = nil
        stateLock.unlock()
        oldProcess?.terminate()
        slotGate.release(id: id)
        return true
    }

    /// 無効化: 世代を進め、進行中の要求を `superseded` に倒す。
    public func invalidate() {
        stateLock.lock()
        generation += 1
        let oldProcess = process
        process = nil
        processSeekTargetSeconds = nil
        lastReadFrame = nil
        lastFinalizedFrame = nil
        streamEnded = false
        endOfStreamFrame = nil
        stateLock.unlock()
        if oldProcess != nil {
            oldProcess?.terminate()
            slotGate.release(id: id)
        }
    }

    // MARK: 読み進め

    private enum ReadOutcome {
        case frame
        case endOfStream
    }

    /// プロセスから次のフレームを読み、保持状態を進める。
    /// 前のフレームはこの時点で表示終了時刻が確定する。
    private func readNextFrame(requestGeneration: Int) throws -> ReadOutcome {
        stateLock.lock()
        let currentProcess = process
        stateLock.unlock()
        guard let currentProcess else {
            throw FFmpegVideoSessionError.superseded
        }
        let result: (pixelData: Data, startSeconds: Double)?
        do {
            result = try currentProcess.readNextFrame()
        } catch {
            // 読み取り自体の失敗（途中で切れた等）は異常終了として
            // 証拠化する。
            let evidence = buildEvidence(process: currentProcess)
            finishProcessRun(process: currentProcess)
            throw FFmpegVideoSessionError.abnormalTermination(evidence)
        }
        // 世代とプロセスの同一性を確認する（無効化・退避されていたら
        // このフレームは破棄する）。
        stateLock.lock()
        let stillCurrent = generation == requestGeneration && process === currentProcess
        stateLock.unlock()
        guard stillCurrent else {
            throw FFmpegVideoSessionError.superseded
        }
        guard let result else {
            // 終端。証拠を作り、異常かどうかは呼び出し側の
            // frameAfterEndOfStream で判定する。
            let evidence = buildEvidence(process: currentProcess)
            stateLock.lock()
            pendingEvidence = evidence
            streamEnded = true
            // 最終フレームの終了時刻を確定させる。
            var finalFrame: FFmpegVideoFrame?
            if let last = lastReadFrame {
                var finalized = last
                finalized.presentationEnd = TimeSpanValue(
                    seconds: configuration.materialEndSeconds
                        ?? (last.presentationStart.seconds
                            + configuration.nominalFrameDurationSeconds)
                )
                finalFrame = finalized
                endOfStreamFrame = finalized
                lastReadFrame = finalized
            }
            stateLock.unlock()
            if let finalFrame {
                observer?.videoSession(self, didReadFrame: finalFrame, endIsFinal: true)
            }
            finishProcessRun(process: currentProcess, keepState: true)
            return .endOfStream
        }
        let start = TimeSpanValue(seconds: result.startSeconds)
        let newFrame = FFmpegVideoFrame(
            pixelData: result.pixelData,
            width: configuration.width,
            height: configuration.height,
            presentationStart: start,
            presentationEnd: start + TimeSpanValue(
                seconds: configuration.nominalFrameDurationSeconds
            )
        )
        stateLock.lock()
        let previous = lastReadFrame
        if let previous {
            var finalized = previous
            finalized.presentationEnd = start
            lastFinalizedFrame = finalized
            lastReadFrame = newFrame
            stateLock.unlock()
            observer?.videoSession(self, didReadFrame: finalized, endIsFinal: true)
            observer?.videoSession(self, didReadFrame: newFrame, endIsFinal: false)
        } else {
            lastReadFrame = newFrame
            stateLock.unlock()
            observer?.videoSession(self, didReadFrame: newFrame, endIsFinal: false)
        }
        return .frame
    }

    /// 終端後に要求へ答える。最終フレームで答えられる場合は
    /// それを返し、異常な終端で答えられない場合は例外にする。
    private func frameAfterEndOfStream(time: TimeSpanValue) throws -> FFmpegVideoFrame {
        stateLock.lock()
        let eosFrame = endOfStreamFrame
        let evidence = pendingEvidence
        stateLock.unlock()
        if let eosFrame, time >= eosFrame.presentationStart {
            // 最終フレームで答えられる。終端が異常だった場合の
            // 記録は管理者が証拠（takePendingEvidence）で行う。
            return eosFrame
        }
        // 要求へ届かない終端は異常終了として扱う（打ち切られた
        // 素材で、プローブの長さの範囲内なのにフレームが無い等）。
        throw FFmpegVideoSessionError.abnormalTermination(
            evidence ?? MediaDecodeEvidence(
                producedFrameCount: 0,
                expectedFrameCount: configuration.expectedFrameCount
            )
        )
    }

    /// 終端したプロセスの証拠を作る。
    private func buildEvidence(process: any FFmpegVideoProcess) -> MediaDecodeEvidence {
        let excerpt = process.collectedStandardError
        return MediaDecodeEvidence(
            exitStatus: process.exitStatus,
            producedFrameCount: process.producedFrameCount,
            expectedFrameCount: configuration.expectedFrameCount,
            standardErrorExcerpt: excerpt.isEmpty ? nil : String(excerpt.prefix(1000))
        )
    }

    /// プロセスの終了処理: 状態から外し、枠を解放する。
    /// `keepState` の場合は保持フレームを残す（終端フォールバック用）。
    /// 異常終了の経路ではプロセスが生き残っている場合があるため、
    /// ここで確実に終了させる（正常な終端では終了済みで無害）。
    private func finishProcessRun(
        process: any FFmpegVideoProcess, keepState: Bool = false
    ) {
        stateLock.lock()
        let detached = self.process === process
        if detached {
            self.process = nil
            processSeekTargetSeconds = nil
            if !keepState {
                lastReadFrame = nil
                lastFinalizedFrame = nil
                streamEnded = false
                endOfStreamFrame = nil
            }
        }
        stateLock.unlock()
        if detached {
            process.terminate()
            slotGate.release(id: id)
        }
    }
}
