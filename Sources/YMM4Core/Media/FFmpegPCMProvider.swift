import Foundation

/// FFmpeg デコードプロセスで `PCMProvider` 契約を実装する供給
/// （Issue #70 段階3）。
///
/// 方式: 素材ごとに ffmpeg プロセスを1本持ち、前方へ逐次デコードする
/// （`FFmpegAudioProcess`）。ashowinfo の提示タイムスタンプと stdout の
/// バイト列を対応付けるため、チャンクの論理位置（提示開始位置を 0 と
/// するサンプル位置）はサンプル精度で確定する。実測（段階2前計測・
/// 音声14ケース）で ffmpeg の遅延補償によりインパルス位置のズレが
/// 0サンプルだったため、追加のサンプル補正は入れない。
///
/// シークの橋渡し:
/// - 保持済みチャンクの範囲内への移動は位置付け直しだけ（再生成なし）。
/// - 生成済み終端より少し先（`forwardPullThresholdSeconds` 以内）は
///   読み進めて吸収する。
/// - それ以外はプロセスを再生成し、目標の `seekPrerollSeconds` 手前
///   からデコードし直す。再生成回数は `processRestartCount` で数える
///   （設計上の主要な性能指標）。
/// - 保持済みチャンクは読み取り位置より `ringBufferSeconds` 以上
///   手前のものを捨てる（後方シーク吸収用のリングバッファ）。
///
/// 時刻の正規化: 論理0 = 提示開始位置（プローブの開始時刻。取れない
/// 場合は最初にデコードされたチャンクの提示時刻を採用する）。
/// 論理0より手前のサンプルは切り捨て、負の読み取り位置は無音として
/// 数える（AVFoundation 側のストリーミング供給と同じ意味論）。
///
/// EOF: プロセス終端で終了コード・stderr・生成量を期待量（プローブ
/// の長さ×サンプリングレート）と照合し、失敗なら
/// `MediaAvailabilityRegistry` へ記録する。プローブの長さは推定の
/// 場合がある（MP3 等）ため、不足の判定には許容量
/// （1秒分と期待量の5%の大きい方）を置く。失敗確定後は新規の生成が
/// 止まり、保持済みチャンクだけが読み取れる（理由は台帳側に残る）。
///
/// 読み取りは単一スレッドからの逐次呼び出しを前提とする
/// （`AVFoundationStreamingPCMProvider` と同じ前提）。
public final class FFmpegPCMProvider: PCMProvider, @unchecked Sendable {
    /// デコード済みチャンク（論理サンプル位置つき）。
    private struct Chunk {
        var startSample: Int
        var data: Data
        var frameCount: Int { data.count / (2 * MemoryLayout<Float>.size) }
        var endSample: Int { startSample + frameCount }
    }

    private enum State {
        case active
        case finished
        case failed
    }

    public let hz: Int
    public let duration: TimeSpanValue

    private let filePath: String
    private let ffmpegPath: String
    private let audioStreamIndex: Int
    private let usesOutputSeek: Bool
    private let processFactory: any FFmpegAudioProcessFactory
    private let registry: MediaAvailabilityRegistry?
    private let materialKey: MediaMaterialKey
    private let expectedFrameCount: Int?
    private let ringCapacityFrames: Int
    private let forwardPullFrames: Int
    private let prerollFrames: Int

    /// 提示開始位置（絶対提示時刻、秒）。プローブで取れなかった場合は
    /// 最初のチャンクで採用するため nil になりうる。
    private var presentationStartSeconds: Double?
    private var chunks: [Chunk] = []
    private var nextSample = 0
    /// 保持中チャンクの終端（論理位置）。チャンクが無い場合は次に
    /// 生成が始まる見込み位置。
    private var producedEnd = 0
    private var totalProducedFrames = 0
    private var process: (any FFmpegAudioProcess)?
    private var processStarted = false
    private var state: State = .active
    /// プロセスを再生成した回数（初回起動は含まない）。
    public private(set) var processRestartCount = 0

    /// - Parameters:
    ///   - presentationStartSeconds: 提示開始位置（絶対提示時刻）。
    ///     nil なら最初のチャンクの提示時刻を採用する。
    ///   - durationSeconds: 素材の長さ（プローブ由来）。nil なら長さ
    ///     不定として `duration` は .zero（契約上 nil を表せないため。
    ///     FileAudioStream 側は長さ0を無音として扱う）。
    ///   - ringBufferSeconds: 後方シーク吸収のために保持する秒数
    ///     （暫定値。根拠は台帳参照）。
    ///   - forwardPullThresholdSeconds: 読み進めで吸収する前方移動の
    ///     上限（暫定値。映像側の実測ブレークイーブンに基づく）。
    ///   - seekPrerollSeconds: 再生成時に目標より手前から始める秒数
    ///     （暫定値。映像側と同じ）。
    public init(
        filePath: String,
        ffmpegPath: String,
        audioStreamIndex: Int,
        sampleRate: Int,
        presentationStartSeconds: Double?,
        durationSeconds: Double?,
        usesOutputSeek: Bool,
        processFactory: any FFmpegAudioProcessFactory = FFmpegAudioProcessRunner(),
        registry: MediaAvailabilityRegistry? = nil,
        materialKey: MediaMaterialKey? = nil,
        ringBufferSeconds: Double = 5.0,
        forwardPullThresholdSeconds: Double = 2.0,
        seekPrerollSeconds: Double = 1.0
    ) {
        self.filePath = filePath
        self.ffmpegPath = ffmpegPath
        self.audioStreamIndex = audioStreamIndex
        self.hz = sampleRate
        self.presentationStartSeconds = presentationStartSeconds
        self.duration = durationSeconds.map { TimeSpanValue(seconds: $0) } ?? .zero
        self.expectedFrameCount = durationSeconds.map {
            Int(($0 * Double(sampleRate)).rounded())
        }
        self.usesOutputSeek = usesOutputSeek
        self.processFactory = processFactory
        self.registry = registry
        self.materialKey = materialKey ?? MediaMaterialKey(filePath: filePath)
        self.ringCapacityFrames = Int((ringBufferSeconds * Double(sampleRate)).rounded())
        self.forwardPullFrames = Int(
            (forwardPullThresholdSeconds * Double(sampleRate)).rounded()
        )
        self.prerollFrames = Int((seekPrerollSeconds * Double(sampleRate)).rounded())
    }

    deinit {
        process?.terminate()
    }

    // MARK: - PCMProvider

    public func seek(toTime time: TimeSpanValue) {
        let target = Int(
            (time.seconds * Double(hz)).rounded(.toNearestOrAwayFromZero)
        )
        if state == .failed {
            // 失敗確定後は保持済みチャンクの範囲内だけ位置付け直せる。
            let oldestRetained = chunks.first?.startSample ?? producedEnd
            if target >= oldestRetained && target <= producedEnd {
                nextSample = target
            }
            return
        }
        let oldestRetained = chunks.first?.startSample ?? producedEnd
        if target >= oldestRetained && target <= producedEnd {
            // 保持範囲内: 位置付け直しだけ。
            nextSample = target
            return
        }
        if state == .finished && target > producedEnd {
            // 終端より先は再生成しても得られない。
            nextSample = target
            return
        }
        if target > producedEnd && target - producedEnd <= forwardPullFrames {
            // 少し先: 読み進めて吸収する。
            while producedEnd < target && pullNextChunk() {}
            nextSample = target
            dropConsumedChunks()
            return
        }
        restartProcess(fromLogicalFrame: target)
        nextSample = target
    }

    public func read(
        into buffer: inout [Float], offset: Int, count: Int
    ) -> Int {
        // 失敗確定後も保持済みチャンクは読み取れる（新規の生成だけが
        // 止まる）。映像側が終端フレームで答え続けるのと同じ考え方。
        // count は float 要素数（2ch インターリーブ）。フレーム単位で
        // 処理するため、要素数はフレーム境界へ切り下げる（呼び出し側
        // は常にフレーム倍数を要求する）。
        guard count > 0 else { return 0 }
        var requestedFrames = count / 2
        var written = 0
        var writeIndex = offset

        // 素材開始前の負位置は無音として数える（他供給と同じ意味論）。
        if nextSample < 0 {
            let silenceFrames = min(-nextSample, requestedFrames)
            if silenceFrames > 0 {
                for index in 0..<(silenceFrames * 2) {
                    buffer[writeIndex + index] = 0
                }
                writeIndex += silenceFrames * 2
                written += silenceFrames * 2
                nextSample += silenceFrames
                requestedFrames -= silenceFrames
            }
        }

        var framesWritten = 0
        while framesWritten < requestedFrames {
            guard let chunk = chunks.first(where: { $0.endSample > nextSample }) else {
                guard pullNextChunk() else { break }
                continue
            }
            if chunk.startSample > nextSample {
                // チャンク間の欠落は無音で埋める。
                let gapFrames = min(chunk.startSample - nextSample, requestedFrames - framesWritten)
                for index in 0..<(gapFrames * 2) {
                    buffer[writeIndex + index] = 0
                }
                writeIndex += gapFrames * 2
                written += gapFrames * 2
                framesWritten += gapFrames
                nextSample += gapFrames
                continue
            }
            let startInChunk = nextSample - chunk.startSample
            let copyFrames = min(
                chunk.frameCount - startInChunk, requestedFrames - framesWritten
            )
            let baseElement = startInChunk * 2
            chunk.data.withUnsafeBytes { raw in
                let floats = raw.bindMemory(to: Float.self)
                for index in 0..<(copyFrames * 2) {
                    buffer[writeIndex + index] = floats[baseElement + index]
                }
            }
            writeIndex += copyFrames * 2
            written += copyFrames * 2
            framesWritten += copyFrames
            nextSample += copyFrames
        }
        dropConsumedChunks()
        return written
    }

    /// 失敗を外側から確定させる（Factory の初回読み取り検証用）。
    /// プロセスを止め、台帳へ記録する。
    public func recordExternalFailure(kind: MediaAvailabilityFailureKind, detail: String) {
        guard state != .failed else { return }
        state = .failed
        process?.terminate()
        process = nil
        registry?.markFailed(
            for: materialKey,
            failure: MediaAvailabilityFailure(
                kind: kind, detail: detail, occurredAt: Date()
            ),
            evidence: MediaDecodeEvidence(
                producedFrameCount: totalProducedFrames,
                expectedFrameCount: expectedFrameCount
            )
        )
    }

    // MARK: - プロセス管理

    /// 次のチャンクをプロセスから引いて保持列へ足す。終端なら false。
    private func pullNextChunk() -> Bool {
        guard state != .failed else { return false }
        while true {
            if !processStarted {
                startProcess(fromLogicalFrame: max(nextSample, 0), isRestart: false)
                if state == .failed { return false }
            }
            guard let process else {
                finishAtEndOfStream()
                return false
            }
            let pulled: (data: Data, startSeconds: Double)?
            do {
                pulled = try process.readNextChunk()
            } catch {
                finishAtEndOfStream()
                return false
            }
            guard let pulled else {
                finishAtEndOfStream()
                return false
            }
            if presentationStartSeconds == nil {
                presentationStartSeconds = pulled.startSeconds
            }
            let start = presentationStartSeconds ?? pulled.startSeconds
            var logicalStart = Int(
                ((pulled.startSeconds - start) * Double(hz)).rounded()
            )
            var data = pulled.data
            if logicalStart < 0 {
                // 論理0より手前のサンプル（符号器のプライミング等）は
                // 切り捨てる。チャンク全体が手前なら読み飛ばす。
                let trimFrames = min(-logicalStart, data.count / (2 * MemoryLayout<Float>.size))
                data = data.subdata(
                    in: (trimFrames * 2 * MemoryLayout<Float>.size)..<data.count
                )
                logicalStart += trimFrames
                if data.isEmpty { continue }
            }
            let chunk = Chunk(startSample: logicalStart, data: data)
            chunks.append(chunk)
            producedEnd = max(producedEnd, chunk.endSample)
            totalProducedFrames += chunk.frameCount
            return true
        }
    }

    /// プロセスを再生成して目標位置の手前からデコードし直す。
    private func restartProcess(fromLogicalFrame target: Int) {
        let seekLogical = max(0, target - prerollFrames)
        startProcess(fromLogicalFrame: seekLogical, isRestart: true)
    }

    private func startProcess(fromLogicalFrame logicalFrame: Int, isRestart: Bool) {
        process?.terminate()
        process = nil
        chunks.removeAll()
        totalProducedFrames = 0
        if isRestart && processStarted {
            processRestartCount += 1
        }
        processStarted = true
        state = .active

        // 提示開始位置が未確定ならシークせず先頭から始める（最初の
        // チャンクで開始位置を採用する）。その場合の生成は先頭から。
        var seekTargetSeconds: Double?
        if logicalFrame > 0, let start = presentationStartSeconds {
            seekTargetSeconds = start + Double(logicalFrame) / Double(hz)
        }
        producedEnd = seekTargetSeconds == nil ? 0 : logicalFrame
        let request = FFmpegAudioProcessRequest(
            executablePath: ffmpegPath,
            filePath: filePath,
            audioStreamIndex: audioStreamIndex,
            seekTargetSeconds: seekTargetSeconds,
            usesOutputSeek: usesOutputSeek
        )
        do {
            process = try processFactory.makeProcess(request: request)
        } catch {
            state = .failed
            registry?.markFailed(
                for: materialKey,
                failure: MediaAvailabilityFailure(
                    kind: .unsupportedOrDecodeFailed,
                    detail: "ffmpeg プロセスを起動できませんでした: \(error)",
                    occurredAt: Date()
                ),
                evidence: MediaDecodeEvidence(
                    producedFrameCount: 0,
                    expectedFrameCount: expectedFrameCount
                )
            )
        }
    }

    /// 保持範囲より手前のチャンクを捨てる（リングバッファ）。
    private func dropConsumedChunks() {
        let threshold = nextSample - ringCapacityFrames
        while let first = chunks.first, first.endSample <= threshold {
            chunks.removeFirst()
        }
    }

    // MARK: - 終端の判定

    /// プロセス終端時の処理。証拠を期待量と照合し、失敗なら台帳へ
    /// 記録して失敗状態へ移る。
    private func finishAtEndOfStream() {
        guard state == .active else { return }
        state = .finished
        guard let process else { return }
        let excerpt = process.collectedStandardError
        let evidence = MediaDecodeEvidence(
            exitStatus: process.exitStatus,
            producedFrameCount: totalProducedFrames,
            expectedFrameCount: expectedFrameCount,
            standardErrorExcerpt: excerpt.isEmpty ? nil : String(excerpt.prefix(1000))
        )
        if isFailure(evidence: evidence) {
            state = .failed
            registry?.markFailed(
                for: materialKey,
                failure: MediaAvailabilityFailure(
                    kind: totalProducedFrames > 0
                        ? .midStreamFailure : .unsupportedOrDecodeFailed,
                    detail: failureDetail(evidence: evidence),
                    occurredAt: Date()
                ),
                evidence: evidence
            )
        }
    }

    /// 失敗判定（供給側の判断。証拠の `failureIndicators` は素材の
    /// 厳密な不足も兆候に含むため、ここでは許容量を置いて判定する）。
    private func isFailure(evidence: MediaDecodeEvidence) -> Bool {
        if let status = evidence.exitStatus, status != 0 { return true }
        if evidence.failureIndicators.contains(.standardErrorReportsDecodeError) {
            return true
        }
        if let expected = expectedFrameCount, expected > 0 {
            let produced = totalProducedFrames
            if produced == 0 { return true }
            // プローブの長さは推定の場合があるため、不足が許容量を
            // 超えた場合だけ失敗とする。
            let tolerance = max(hz, expected / 20)
            if expected - produced > tolerance { return true }
        }
        return false
    }

    private func failureDetail(evidence: MediaDecodeEvidence) -> String {
        if let status = evidence.exitStatus, status != 0 {
            return "ffmpeg が終了コード \(status) で終了しました"
        }
        if evidence.failureIndicators.contains(.standardErrorReportsDecodeError) {
            return "ffmpeg の標準エラーに復号エラーが含まれます"
        }
        return "期待したサンプル数を得られませんでした（生成 \(totalProducedFrames) / 期待 \(expectedFrameCount ?? 0)）"
    }
}
