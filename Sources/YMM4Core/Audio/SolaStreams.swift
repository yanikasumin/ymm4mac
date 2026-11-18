import Foundation

/// SOLA 方式の定数再生速度（ピッチ保持の時間伸縮）。本家
/// `SolaTimeStretchEffect` ＋ `PlaybackRateSolaTimeStretchEffect`
/// （Player.Audio.Effects）に対応する。処理芯は `SoundTouchProcessor`
/// （本家が同梱する SoundTouch.Net と同じ仕様の再実装）。
///
/// 意味論（本家どおり）:
/// - 長さは `Input.Duration / tempo`（切り捨て）。入力が無制限の
///   ときは無制限のまま（本家 `PlaybackRateSolaTimeStretchEffect`
///   の上書き）。偶数への切り捨ては本家のこの経路には無い。
/// - シークは位置 × tempo を切り捨てて入力へ転送し、プロセッサを
///   初期化し直す（テンポ・音程・チャンネル数・サンプルレートの
///   再設定までが本家の `seek` の内容）。
/// - 読み取りはプロセッサの出力を優先し、枯れたら入力を 1 秒
///   （Hz × 2 サンプル）ずつ供給する。入力が尽きたらフラッシュ
///   して残りを吐き出す。
public final class SolaTimeStretchStream: AudioEffectProcessorBase {
    /// テンポ（1.0 = 等速）。
    public let tempo: Double
    /// 音程（再生速度用途では 1.0）。
    public let pitch: Double
    private let processor = SoundTouchProcessor()
    private var inputBlock: [Float] = []
    private var isEndOfStream = false
    private var configuredHz = 0

    public init(tempo: Double, pitch: Double = 1.0) {
        self.tempo = tempo
        self.pitch = pitch
        super.init()
    }

    public override var duration: Int {
        guard let input else { return 0 }
        if input.duration == Int.max { return Int.max }
        return Int(Double(input.duration) / tempo)
    }

    override func seekImpl(_ position: Int) {
        guard let input else { return }
        input.seek(to: Int(Double(position) * tempo))
        isEndOfStream = false
        configureProcessor()
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        guard let input else { return 0 }
        if configuredHz != input.hz {
            configureProcessor()
        }
        var written = 0
        while written < count {
            let received = processor.receiveSamples(
                into: &buffer, offset: offset + written, maxFrames: (count - written) / 2
            )
            if received > 0 {
                written += received * 2
                continue
            }
            if isEndOfStream { break }
            if inputBlock.isEmpty { break }
            let readCount = input.read(into: &inputBlock, offset: 0, count: inputBlock.count)
            if readCount > 0 {
                processor.putSamples(inputBlock, frameCount: readCount / 2)
            } else {
                isEndOfStream = true
                processor.flush()
            }
        }
        return written
    }

    /// 本家 `seek` 内のプロセッサ再設定（初期化＋パラメータ設定）。
    private func configureProcessor() {
        guard let input else { return }
        if inputBlock.count != input.hz * 2 {
            inputBlock = [Float](repeating: 0, count: input.hz * 2)
        }
        processor.clear()
        processor.tempo = tempo
        processor.pitch = pitch
        processor.sampleRate = input.hz
        configuredHz = input.hz
    }
}

/// 可変再生速度のピッチ補正。本家 `VariableSolaPitchCorrectionEffect`
/// （Player.Audio.Effects）に対応する。前段の
/// `VariablePlaybackRateStream`（線形補間で速度だけを変え、音程も
/// 一緒に変わる）の後段に置き、音程だけを元へ戻す。長さは変えない。
///
/// 意味論（本家どおり）:
/// - 長さは入力のまま。読み取りは残り長さで打ち切り、偶数へ調整。
/// - 入力を 1/50 秒（Hz × 2 / 50 サンプル、最低 2、偶数へ調整）
///   ずつ読み、各ブロックの中央時刻における速度から
///   `pitch = min(1 / |rate|, 4)` を求めてプロセッサへ設定してから
///   そのブロックを供給する。
/// - シークは位置をそのまま入力へ転送し、プロセッサを初期化する
///   （テンポ 1・音程 1・サンプルレート再設定）。
public final class VariableSolaPitchCorrectionStream: AudioEffectProcessorBase {
    /// 速度カーブ（既存実装 `PlaybackRateMap` を共用）。
    public let rateMap: PlaybackRateMap
    /// アイテムの長さ（フレーム）。
    public let itemLength: Int
    /// プロジェクトの FPS。
    public let fps: Int

    private let processor = SoundTouchProcessor()
    private var inputBlock: [Float] = []
    private var isEndOfStream = false
    /// 入力から読み終えたサンプル数（本家 `inputPosition`）。
    private var inputPosition = 0
    private var cachedTable: PlaybackRateMap.Table?
    private var configuredHz = 0

    public init(rateMap: PlaybackRateMap, itemLength: Int, fps: Int) {
        self.rateMap = rateMap
        self.itemLength = itemLength
        self.fps = fps
        super.init()
    }

    private var table: PlaybackRateMap.Table {
        if let cachedTable { return cachedTable }
        let built = rateMap.table(itemLength: itemLength, fps: fps)
        cachedTable = built
        return built
    }

    /// 速度（%）に対する補正音程。本家 `GetPitch`。
    /// 速度の絶対値が 0.001 以下・非有限なら 1、逆数の上限は 4。
    static func pitch(forRatePercent ratePercent: Double) -> Double {
        let magnitude = abs(ratePercent / 100.0)
        if !magnitude.isFinite || magnitude <= 0.001 {
            return 1.0
        }
        let inverse = 1.0 / magnitude
        if !inverse.isFinite {
            return 1.0
        }
        return min(inverse, 4.0)
    }

    override func seekImpl(_ position: Int) {
        guard let input else { return }
        input.seek(to: position)
        inputPosition = position
        isEndOfStream = false
        configureProcessor()
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        guard let input else { return 0 }
        if configuredHz != input.hz {
            configureProcessor()
        }
        var count = count
        if duration != Int.max {
            count = min(count, max(0, duration - position))
        }
        count -= count % 2
        var written = 0
        while written < count {
            let received = processor.receiveSamples(
                into: &buffer, offset: offset + written, maxFrames: (count - written) / 2
            )
            if received > 0 {
                written += received * 2
                continue
            }
            if isEndOfStream { break }
            if inputBlock.isEmpty { break }
            var blockCount = input.read(into: &inputBlock, offset: 0, count: inputBlock.count)
            blockCount -= blockCount % 2
            if blockCount <= 0 {
                isEndOfStream = true
                processor.flush()
                continue
            }
            let centerTicks = positionToTimeTicks(inputPosition + blockCount / 2)
            processor.pitch = Self.pitch(forRatePercent: table.getRate(timeTicks: centerTicks))
            processor.putSamples(inputBlock, frameCount: blockCount / 2)
            inputPosition += blockCount
        }
        return written
    }

    /// 本家 `seek` 内のプロセッサ再設定（初期化＋パラメータ設定）と
    /// 入力ブロック長の決定。
    private func configureProcessor() {
        guard let input else { return }
        var blockSamples = max(2, input.hz * 2 / 50)
        blockSamples -= blockSamples % 2
        if inputBlock.count != blockSamples {
            inputBlock = [Float](repeating: 0, count: blockSamples)
        }
        processor.clear()
        processor.sampleRate = input.hz
        processor.tempo = 1.0
        processor.pitch = 1.0
        configuredHz = input.hz
    }
}
