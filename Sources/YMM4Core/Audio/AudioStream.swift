import Foundation

/// 音声ストリームの基底。本家 `AudioStreamBase` に対応する。
///
/// 本家の契約（実コードで確認）:
/// - チャンネル数は 2、サンプルは float 32bit・2ch インターリーブで固定。
/// - `Position` の単位はインターリーブ済み float サンプル数。
/// - `Read` は内部読み取りを1回だけ呼び、戻り値の分だけ `Position` を進める
///   （不足分をループで埋めるのは LoopEffect 等の各処理器の責務）。
/// - `Seek(long)` は `Position` を設定してから内部シークを呼ぶ。
/// - 時刻⇔位置の換算は `time * 2 * Hz / 10^7`（tick 単位）で、位置は
///   偶数（フレーム境界）へ切り捨てる。`PositionToTime` は整数除算の
///   商と剰余を別々に tick 化して足す。
///
/// 読み取り先バッファの約束（本家の呼び出し側の慣行）: `read` は生成した
/// サンプル数だけを書き込み、無音区間を自ら 0 で埋めるとは限らない
/// （例: 負位置のプレフィックス、TimelineSource の加算）。呼び出し側は
/// 対象区間を 0 初期化してから読むこと。区間を明示的に消す処理器
/// （SegmentGate 等）は本家どおり自前で 0 埋めする。
///
/// 本家は IDisposable で所有を管理するが、ここでは Swift の参照所有
/// （チェーンは入力を強参照で保持する）で代替する。
public class AudioStream {
    /// チャンネル数（固定）。本家 `AudioStreamBase.Channel`。
    public static let channelCount = 2

    /// 現在の読み取り位置（インターリーブ済みサンプル数）。
    /// `seek` と `read` の戻りでのみ進む。
    public private(set) var position: Int = 0

    /// サンプリングレート（Hz）。サブクラスが上書きする。
    public var hz: Int { 0 }

    /// 全長（インターリーブ済みサンプル数）。無制限は `Int.max`。
    /// サブクラスが上書きする。
    public var duration: Int { 0 }

    public init() {}

    /// 位置を設定してシークする。本家 `Seek(long)`。
    public func seek(to newPosition: Int) {
        position = newPosition
        seekImpl(newPosition)
    }

    /// 時刻でシークする。本家 `Seek(TimeSpan)`。
    public func seek(toTime time: TimeSpanValue) {
        seek(to: timeToPosition(time.ticks))
    }

    /// バッファへ読み取る。本家 `Read`。
    ///
    /// - Returns: 実際に生成したサンプル数（要求より少ないことがある）。
    @discardableResult
    public func read(into buffer: inout [Float], offset: Int, count: Int) -> Int {
        let readCount = readImpl(&buffer, offset: offset, count: count)
        position += readCount
        return readCount
    }

    /// 内部読み取り。サブクラスが上書きする。
    /// 呼び出し時点の `position` はこの読み取りの開始位置。
    func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int { 0 }

    /// 内部シーク。サブクラスが上書きする。
    func seekImpl(_ position: Int) {}

    // MARK: - 時刻⇔位置の換算（本家 AudioStreamBase の式をそのまま再現）

    /// tick から位置を求める。本家 `TimeToPosition`。
    public func timeToPosition(_ ticks: Int64) -> Int {
        let num = ticks * Int64(AudioStream.channelCount * hz) / 10_000_000
        return Int(num - num % 2)
    }

    /// 位置から tick を求める。本家 `PositionToTime`（飽和処理は除く）。
    public func positionToTimeTicks(_ position: Int) -> Int64 {
        let channelHz = Int64(AudioStream.channelCount * hz)
        guard channelHz > 0 else { return 0 }
        let value = Int64(position)
        let quotient = value / channelHz
        let remainder = value % channelHz
        return quotient * 10_000_000 + remainder * 10_000_000 / channelHz
    }

    /// フレーム数から tick を求める。本家 `FrameTime.FrameToTime`。
    /// 丸めは AwayFromZero、粒度は 100ns。
    static func frameToTicks(frame: Int, fps: Int) -> Int64 {
        guard fps > 0 else { return 0 }
        return Int64(
            (Double(frame) * 10_000_000 / Double(fps)).rounded(.toNearestOrAwayFromZero)
        )
    }
}

/// ストリームを最後まで（または枯れるまで）読み切る。
/// 本家 `SegmentGateEffect.ReadFully` に対応する。
func readFully(_ stream: AudioStream, into buffer: inout [Float], offset: Int, count: Int) -> Int {
    var total = 0
    while total < count {
        let readCount = stream.read(into: &buffer, offset: offset + total, count: count - total)
        if readCount <= 0 { break }
        total += readCount
    }
    return total
}

/// 入力ストリームのフレーム列へのランダムアクセス窓。
///
/// リサンプラ系の処理器が線形補間などで前後のフレームを引くために使う。
/// 順次読み取りではチャンク単位で先読みし、シーク時は必要位置から
/// 読み直す。入力の範囲外（負位置・終端以降）は無音として返す。
/// 入力が短い読み取りを返した位置を終端として記録し、それ以降への
/// アクセスでは再読み取りしない。
final class InputFrameWindow {
    private let input: AudioStream
    private var samples: [Float] = []
    private var startFrame: Int = 0
    private var validFrames: Int = 0
    private var endFrame: Int?

    private static let chunkFrames = 8192

    init(input: AudioStream) {
        self.input = input
    }

    /// 蓄えた内容を捨てる（シーク時に呼ぶ）。
    func invalidate() {
        validFrames = 0
        endFrame = nil
    }

    /// 指定フレームの (L, R)。範囲外は (0, 0)。
    func frame(at index: Int) -> (left: Float, right: Float) {
        if index < 0 { return (0, 0) }
        if let endFrame, index >= endFrame { return (0, 0) }
        if index < startFrame || index >= startFrame + validFrames {
            refill(from: index)
            if index < startFrame || index >= startFrame + validFrames {
                return (0, 0)
            }
        }
        let offset = (index - startFrame) * 2
        return (samples[offset], samples[offset + 1])
    }

    private func refill(from frame: Int) {
        startFrame = frame
        if samples.count < InputFrameWindow.chunkFrames * 2 {
            samples = [Float](repeating: 0, count: InputFrameWindow.chunkFrames * 2)
        } else {
            for index in samples.indices { samples[index] = 0 }
        }
        input.seek(to: frame * 2)
        let readCount = input.read(
            into: &samples, offset: 0, count: InputFrameWindow.chunkFrames * 2
        )
        validFrames = readCount / 2
        if readCount < InputFrameWindow.chunkFrames * 2 {
            endFrame = startFrame + validFrames
        }
    }
}
