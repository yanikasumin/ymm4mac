#if os(macOS)
import AVFoundation
import Foundation
import YMM4Core

/// 再生速度の変更方式。本家 `AudioPlayerPlaybackRateMode` に対応する。
/// 設定の既定（`GetAudioPlayerPlaybackRateMode`）は TimeStretching。
public enum PlaybackRateMode: Sendable {
    /// リサンプリング（速度と一緒にピッチも変わる）。
    case resampling
    /// タイムストレッチ（ピッチを維持する）。
    case timeStretching
}

/// 実時間再生エンジン（音声マスタークロック）。
/// 本家 `TimelineAudioPlayer`（＋内部の `AudioPlayer`）に対応する。
///
/// 方式（本家どおり）:
/// - 音声が主時計。音声プレイヤーの消費位置を 33ms 間隔で確認し、
///   表示位置 = 開始位置 + 音声側の消費位置（タイムライン長で制限）。
///   位置の変化は `timeline.currentFrame` へ同期する。
/// - 音量はポーリングのたびに即時反映する（ミュート時は 0）。
/// - 速度が変わったらプレイヤーを作り直し、現在位置から再シーク
///   して再開する。
/// - 終端に達したら停止する。リピート有効時は開始位置へ戻り、
///   通常の再生開始経路（`play`）で再開する。一時停止時は位置が
///   開始位置へ戻るだけで、再開はしない。
/// - プレイヤー層のシークは再生中は無効。再生中のシークは
///   「一時停止 → シーク」の手順を踏み、設定既定（SeekBehavior =
///   Pause）のため再開しない。
///
/// Mac 側の対応付け:
/// - プレイヤーは AVAudioPlayerNode。消費位置は playerTime の
///   サンプル時刻で得る。これはソースサンプル単位で進むため、
///   本家の `GetPositionTimeSpan() * PlaybackRate`（デバイス時間 ×
///   速度 = ソース時間）と等価になる。
/// - 速度変更は後段の AVAudioUnitVarispeed（リサンプリング） /
///   AVAudioUnitTimePitch（タイムストレッチ）で行う。本家は速度が
///   1.0 でない場合だけ方式プロバイダを挿入するため、ここでも
///   1.0 のときは速度ノードを挟まない。
/// - 音量は出力段（mainMixerNode）で掛ける。本家はソース側の
///   VolumeSampleProvider で掛けるが、レベルメーターはどちらでも
///   音量適用前のソースを測るため、表示値の意味は変わらない。
/// - 供給は 1 秒単位のチャンクを専用キューで生成し、最大 2 つ先行
///   してスケジュールする。状態変更（停止・シーク・作り直し）は
///   世代カウンタで古いチャンクを無効化する。無効化は生成側の
///   読み取り前に判定し、古い世代は供給元を一切読まない（供給元は
///   逐次読みのため、シーク後に古い世代が読むと新しい世代の先頭が
///   その分だけ欠落する）。
///
/// 所有権: 供給元（ミキサーと工場）とエンジン一式はこのクラスが
/// 保持する。`dispose` で全て解放する。
/// スレッド規約（`@unchecked Sendable` の根拠）: 状態の読み書きと
/// 通知は全てメインスレッド／メインキューで行う。メイン以外から
/// 触るのはチャンク生成キューからの供給読み取りだけで、供給元への
/// アクセスは `sourceAccessLock` で直列化し、世代カウンタで
/// 陳腐化した生成結果を捨てる。
public final class RealtimePlaybackEngine: @unchecked Sendable {
    /// 対象タイムライン。
    public let timeline: Timeline
    /// 音声供給（ミキサー＋レベルメーター）。
    public let source: PlaybackAudioSource

    /// レベルメーターへの短縮参照。
    public var levelMeter: SoundLevelMeter { source.levelMeter }

    /// 現在の表示位置。
    public private(set) var position: TimeSpanValue
    /// 現在の再生が始まった位置。
    public private(set) var startPosition: TimeSpanValue
    /// 再生中かどうか。
    public private(set) var isPlaying = false

    /// 再生速度（倍率）。本家は百分率（100 = x1.0）で保持するが、
    /// ここでは UI のコンボ値と同じ倍率で保持する。
    public var playbackRate: Double = 1.0
    /// 速度変更方式（既定は本家設定の既定どおりタイムストレッチ）。
    public var playbackRateMode: PlaybackRateMode = .timeStretching
    /// 音量（0–100、本家の Volume と同じ単位）。
    public var volume: Double = 100
    /// ミュート。
    public var isMuted = false
    /// リピート再生（本家 IsRepeatPlayEnabled、既定 false）。
    public var isRepeatEnabled = false

    /// 位置が変化したときの通知（メインキュー）。
    public var onPositionChanged: ((TimeSpanValue) -> Void)?
    /// 再生状態が変化したときの通知（メインキュー）。
    public var onPlayingStateChanged: ((Bool) -> Void)?
    /// 再生開始に失敗したときの通知（メインキュー）。
    public var onStartFailed: ((PlaybackStartError) -> Void)?
    /// 直近の再生開始失敗。開始が成功すると nil に戻る。
    public private(set) var lastStartError: PlaybackStartError?

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var rateNode: AVAudioUnit?
    private var pollTimer: DispatchSourceTimer?
    private var appliedRate: Double = 1.0
    private var appliedRateMode: PlaybackRateMode = .timeStretching

    private let chunkQueue = DispatchQueue(
        label: "ymm4.playback.chunking", qos: .userInitiated
    )
    /// 供給元へのアクセスの直列化。チャンク生成（生成キュー）と
    /// シーク（メインスレッド）が同じミキサーを同時に触らないため。
    private let sourceAccessLock = NSLock()
    private let generationLock = NSLock()
    private var generation: Int = 0
    /// スケジュール済み（未再生）チャンク数。
    private var scheduledChunkCount = 0
    /// 次に生成するチャンクの先頭位置（ソースサンプル数）。
    private var nextChunkSamplePosition: Int = 0
    private var isDisposed = false

    /// 1 チャンクの長さ（フレーム数 = 1 秒分）。
    private var chunkFrames: Int { timeline.videoInfo.hz }
    /// 先行スケジュールの上限（本家の供給窓と同じ 2 秒分）。
    private let maxScheduledChunks = 2

    public init(timeline: Timeline, source: PlaybackAudioSource) {
        self.timeline = timeline
        self.source = source
        let initial = FrameTime.time(fromFrame: timeline.currentFrame, fps: timeline.videoInfo.fps)
        self.position = TimeSpanValue(seconds: initial)
        self.startPosition = self.position
    }

    // MARK: - 位置の換算

    /// タイムライン長の時刻（表示位置の上限）。
    public var maxPosition: TimeSpanValue {
        TimeSpanValue(seconds: FrameTime.time(
            fromFrame: timeline.length, fps: timeline.videoInfo.fps
        ))
    }

    /// 現在位置のフレーム。
    public var currentFrame: Int {
        FrameTime.frame(from: position.seconds, fps: timeline.videoInfo.fps)
    }

    /// プレイヤーの消費フレーム数から表示位置を求める純粋計算。
    ///
    /// 本家: Position = StartPosition + CurrentPosition、
    /// CurrentPosition = デバイス消費時間 × 速度（= ソース消費時間）。
    /// Mac では消費フレーム数（playerTime のサンプル時刻）を Hz で
    /// 割ったものがソース消費時間になる。結果はタイムライン長で
    /// 制限する。
    public static func position(
        startPosition: TimeSpanValue,
        consumedSamples: Int64,
        hz: Int,
        maxPosition: TimeSpanValue
    ) -> TimeSpanValue {
        guard hz > 0 else { return startPosition }
        let elapsed = TimeSpanValue(
            ticks: consumedSamples * TimeSpanValue.ticksPerSecond / Int64(hz)
        )
        let candidate = startPosition + elapsed
        return candidate > maxPosition ? maxPosition : candidate
    }

    // MARK: - 再生制御

    /// 再生を開始する。本家 `StartAudioTask`。
    /// 既に再生中なら何もしない。
    public func play() {
        guard !isDisposed, !isPlaying, timeline.videoInfo.hz > 0 else { return }
        startPosition = position
        seekSource(toTime: startPosition)
        nextChunkSamplePosition = sourcePositionInSamples(startPosition)
        buildEngineAndStart()
    }

    /// 供給元のシークを直列化して行う。
    private func seekSource(toTime time: TimeSpanValue) {
        sourceAccessLock.lock()
        source.seek(toTime: time)
        sourceAccessLock.unlock()
    }

    /// 一時停止する。本家 `EndAudioTask`。
    /// リピート有効時は位置が開始位置へ戻る（本家の実挙動）。
    public func pause() {
        guard !isDisposed else { return }
        endPlayback()
        if isRepeatEnabled {
            position = startPosition
        }
        timeline.currentFrame = currentFrame
        notifyPosition()
    }

    /// 再生と一時停止を切り替える。本家 `TogglePlayAsync`。
    public func togglePlay() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// 停止する（位置を先頭へ戻す）。本家 `StopAsync`:
    /// 再生中なら一時停止し、その後 0 へシークする。
    public func stop() {
        guard !isDisposed else { return }
        if isPlaying {
            endPlayback()
        }
        seek(toTime: .zero)
    }

    /// シークする。本家プレイヤー層 `SeekAsync` の規則で、再生中は
    /// 一時停止してからシークし、再開しない（設定既定の Pause）。
    /// 停止中はそのまま位置だけを移す。
    public func seek(toFrame frame: Int) {
        let clamped = min(max(frame, 0), timeline.length)
        seek(toTime: TimeSpanValue(seconds: FrameTime.time(
            fromFrame: clamped, fps: timeline.videoInfo.fps
        )))
    }

    /// 時刻へのシーク。負値は 0 に丸める（本家どおり）。
    /// 供給元も同じ位置へ移す（再生開始時の再シークと二重になるが、
    /// 停止中のメーター先読みと位置の意味を一致させるため）。
    public func seek(toTime time: TimeSpanValue) {
        guard !isDisposed else { return }
        if isPlaying {
            endPlayback()
        }
        let clamped = time < .zero ? .zero : (time > maxPosition ? maxPosition : time)
        position = clamped
        seekSource(toTime: clamped)
        timeline.currentFrame = currentFrame
        notifyPosition()
    }

    /// 全てを解放する。
    public func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        endPlayback()
        onPositionChanged = nil
        onPlayingStateChanged = nil
        onStartFailed = nil
    }

    // MARK: - エンジンの構築と停止

    /// ノードグラフを構築し、初期チャンクを積んで再生を始める。
    /// 速度変更による作り直しでも同じ経路を使う。
    private func buildEngineAndStart() {
        teardownEngine()
        let audioEngine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        audioEngine.attach(player)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(timeline.videoInfo.hz),
            channels: AVAudioChannelCount(AudioStream.channelCount),
            interleaved: false
        )!
        var connectFrom: AVAudioNode = player
        if playbackRate != 1.0 {
            let node: AVAudioUnit
            switch playbackRateMode {
            case .resampling:
                // AVAudioUnitVarispeed の rate 範囲は 0.25–4.0。
                // 範囲外はノード側で丸められる（本家の MFT リサンプラ
                // にはこの上限が無い。差異として台帳に記録する）。
                let varispeed = AVAudioUnitVarispeed()
                varispeed.rate = Float(min(max(playbackRate, 0.25), 4.0))
                node = varispeed
            case .timeStretching:
                // AVAudioUnitTimePitch の rate 範囲は 1/32–32 で、
                // UI の速度域（0.25–8.0）を全て覆う。
                let timePitch = AVAudioUnitTimePitch()
                timePitch.rate = Float(min(max(playbackRate, 1.0 / 32), 32))
                node = timePitch
            }
            audioEngine.attach(node)
            audioEngine.connect(player, to: node, format: format)
            connectFrom = node
            rateNode = node
        } else {
            rateNode = nil
        }
        audioEngine.connect(connectFrom, to: audioEngine.mainMixerNode, format: format)
        applyVolume(to: audioEngine)
        do {
            try audioEngine.start()
        } catch {
            // 開始失敗は握りつぶさず、型付きの失敗として通知する
            // （Metal 初期化診断と同じ契約。R6-03）。
            teardownEngine()
            let failure = PlaybackStartError.engineStartFailed(
                underlying: String(describing: error)
            )
            lastStartError = failure
            onStartFailed?(failure)
            return
        }
        lastStartError = nil
        engine = audioEngine
        playerNode = player
        appliedRate = playbackRate
        appliedRateMode = playbackRateMode
        scheduledChunkCount = 0
        isPlaying = true
        onPlayingStateChanged?(true)
        player.play()
        fillSchedule()
        startPolling()
    }

    /// 再生を終える共通処理（ポーリング停止とエンジン破棄）。
    private func endPlayback() {
        stopPolling()
        bumpGeneration()
        teardownEngine()
        if isPlaying {
            isPlaying = false
            onPlayingStateChanged?(false)
        }
    }

    private func teardownEngine() {
        if let playerNode {
            playerNode.stop()
        }
        engine?.stop()
        engine = nil
        playerNode = nil
        rateNode = nil
        scheduledChunkCount = 0
    }

    private func applyVolume(to audioEngine: AVAudioEngine) {
        audioEngine.mainMixerNode.outputVolume = Float(
            isMuted ? 0 : min(max(volume, 0), 100) / 100
        )
    }

    // MARK: - チャンクのスケジューリング

    private func sourcePositionInSamples(_ time: TimeSpanValue) -> Int {
        let hz = timeline.videoInfo.hz
        guard hz > 0 else { return 0 }
        return Int(time.ticks * Int64(hz) / TimeSpanValue.ticksPerSecond)
            * AudioStream.channelCount
    }

    private var maxPositionInSamples: Int {
        sourcePositionInSamples(maxPosition)
    }

    /// スケジュール済みが上限未満なら、不足分を生成キューへ積む。
    private func fillSchedule() {
        guard isPlaying, playerNode != nil else { return }
        while scheduledChunkCount < maxScheduledChunks {
            // 終端を超えるチャンクは積まない（終端の停止判定は
            // ポーリング側が行う）。
            if nextChunkSamplePosition >= maxPositionInSamples { return }
            scheduledChunkCount += 1
            let chunkStart = nextChunkSamplePosition
            nextChunkSamplePosition += chunkFrames * AudioStream.channelCount
            let expectedGeneration = currentGeneration
            chunkQueue.async { [weak self] in
                guard let self else { return }
                let buffer = self.renderChunk(
                    startingAtSamples: chunkStart,
                    expectedGeneration: expectedGeneration
                )
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.currentGeneration == expectedGeneration,
                          self.isPlaying,
                          let buffer,
                          let playerNode = self.playerNode else {
                        // 世代が同じまま失敗したときだけ予約を取り消す
                        // （世代が変わっていれば台数は作り直し側で
                        // 数え直されている）。
                        if self.currentGeneration == expectedGeneration {
                            self.scheduledChunkCount -= 1
                        }
                        return
                    }
                    playerNode.scheduleBuffer(buffer, at: nil, options: []) {
                        DispatchQueue.main.async { [weak self] in
                            guard let self,
                                  self.currentGeneration == expectedGeneration
                            else { return }
                            self.scheduledChunkCount -= 1
                            self.fillSchedule()
                        }
                    }
                }
            }
        }
    }

    /// 1 チャンク分（1 秒）を供給元から読み、PCM バッファ化する。
    /// 生成キューで呼ばれる。供給元は終端以降も無音を返すため、
    /// バッファは常に満杯になる。
    ///
    /// 世代の確認は供給ロックの保持中に行う。供給元は逐次読みで
    /// 現在位置から消費するため、シーク後に古い世代のタスクが読むと
    /// 新しい世代の先頭がその分だけ欠落する。シーク（`seekSource`）
    /// も同じロックを取るので、ロック保持中の「確認→読み取り」は
    /// シークに対して不可分になり、古い世代は供給元を一切読まない。
    ///
    /// バッファ形式は非インターリーブ Float32。AVAudioEngine の
    /// 接続はインターリーブ形式を受け付けない（実機で接続例外を
    /// 確認済み）ため、供給元のインターリーブ列をここで
    /// チャンネル別に振り分ける。
    private func renderChunk(
        startingAtSamples start: Int, expectedGeneration: Int
    ) -> AVAudioPCMBuffer? {
        let hz = timeline.videoInfo.hz
        guard hz > 0 else { return nil }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(hz),
            channels: AVAudioChannelCount(AudioStream.channelCount),
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkFrames)
        ) else { return nil }
        var samples = [Float](
            repeating: 0, count: chunkFrames * AudioStream.channelCount
        )
        sourceAccessLock.lock()
        guard currentGeneration == expectedGeneration else {
            sourceAccessLock.unlock()
            return nil
        }
        source.read(into: &samples, offset: 0, count: samples.count)
        sourceAccessLock.unlock()
        buffer.frameLength = AVAudioFrameCount(chunkFrames)
        if let channelData = buffer.floatChannelData {
            let left = channelData[0]
            let right = channelData[1]
            for frame in 0..<chunkFrames {
                left[frame] = samples[frame * 2]
                right[frame] = samples[frame * 2 + 1]
            }
        }
        return buffer
    }

    private var currentGeneration: Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation
    }

    private func bumpGeneration() {
        generationLock.lock()
        generation += 1
        generationLock.unlock()
    }

    // MARK: - ポーリング（33ms）

    private func startPolling() {
        stopPolling()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(33), repeating: .milliseconds(33))
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    /// 本家 positionTask の 1 回分。音量の即時反映、速度変更の検出と
    /// 作り直し、位置の更新と終端判定を行う。
    private func poll() {
        guard isPlaying, playerNode != nil, let engine else { return }
        // 音量はポーリングのたびに即時反映する（本家どおり）。
        applyVolume(to: engine)
        // 速度が変わっていたら、現在位置から作り直す（本家どおり）。
        // 世代の更新はシークより先に行う。古い世代のチャンク生成が
        // シーク後の供給位置を消費しないため（renderChunk の世代
        // 確認は供給ロック保持中に行われ、シークと不可分）。
        if playbackRate != appliedRate || playbackRateMode != appliedRateMode {
            let current = computePosition() ?? position
            position = current
            startPosition = current
            bumpGeneration()
            seekSource(toTime: current)
            nextChunkSamplePosition = sourcePositionInSamples(current)
            buildEngineAndStart()
            return
        }
        guard let updated = computePosition() else { return }
        position = updated
        timeline.currentFrame = currentFrame
        levelMeter.setCurrentPosition(updated, isDecayed: true)
        notifyPosition()
        if updated >= maxPosition {
            endPlayback()
            if isRepeatEnabled {
                // リピート: 開始位置へ戻し、通常の再生開始経路で
                // 再開する。供給の再シーク、プレイヤーの再構築、
                // メーターの位置合わせは play の経路に委ねる。
                // 開始位置が終端そのものの場合、再開しても即座に
                // 終端へ戻るだけなので再開しない。
                position = startPosition
                timeline.currentFrame = currentFrame
                notifyPosition()
                if startPosition < maxPosition {
                    play()
                }
            }
        }
    }

    /// プレイヤーの消費位置から表示位置を求める。
    /// playerTime がまだ得られない間は nil（位置を据え置く）。
    ///
    /// 消費の基準点は再生開始時点。playerTime のサンプル時刻は
    /// ノードの再生開始から累積するフレーム数なので、開始位置に
    /// そのまま加える。最初に時刻を取得できた時点を開始とみなす
    /// 方式は、その時点までの消費（実測で約 0.25 秒）を切り捨てて
    /// 位置が定常的に遅れるため採らない（実測根拠は台帳）。
    private func computePosition() -> TimeSpanValue? {
        guard let playerNode,
              let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else { return nil }
        return Self.position(
            startPosition: startPosition,
            consumedSamples: playerTime.sampleTime,
            hz: timeline.videoInfo.hz,
            maxPosition: maxPosition
        )
    }

    private func notifyPosition() {
        onPositionChanged?(position)
    }
}
#endif
