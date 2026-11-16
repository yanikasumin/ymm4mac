import Foundation

/// 音量・パン・フェードの適用。本家 `VolumePanEffect` に対応する。
///
/// 意味論（本家どおり）:
/// - 音量とパンはサンプルペアごとに評価する。評価の引数は
///   「位置（サンプル）・全長（サンプル）・FPS = Hz × 2」で、本家の
///   `Animation.GetValue(Position + i, Duration, Hz * 2)` をそのまま
///   既存の `Animation.value(atFrame:length:fps:)` へ写したもの。
/// - フェード係数は `min(1, 経過秒 / fadeIn)` と
///   `min(1, 残り秒 / fadeOut)` の小さい方（フェード指定 0 の側は 1）。
///   時刻は位置から換算した秒。
/// - 利得は `volume / 100 × フェード係数`。パンは線形則で、
///   左 = 利得 × (1 - max(0, pan))、右 = 利得 × (1 + min(0, pan))
///   （pan は -1..1）。
/// - 音量が「なし（定数）」かつ先頭値 0 の場合はミュートとして、
///   長さ 0・読み取り 0 になる（本家の最適化を意味論として再現）。
/// - 全長（tmpDuration）はシーク時に確定する。本家はシーク前の
///   読み取りでは 0 のまま評価するが、実際の経路は必ずシークが
///   先行するため、ここでも同じ前提に立つ。
public final class VolumePanStream: SimpleAudioEffectProcessorBase {
    /// アイテムの長さ（時刻）。
    public let itemDuration: TimeSpanValue
    /// 音量アニメーション（%）。
    public let volume: Animation
    /// パンアニメーション（-100..100）。
    public let pan: Animation
    /// フェードイン（秒）。
    public let fadeIn: Double
    /// フェードアウト（秒）。
    public let fadeOut: Double

    private var evaluatedDuration: Int = 0

    public init(
        itemDuration: TimeSpanValue, volume: Animation, pan: Animation,
        fadeIn: Double, fadeOut: Double
    ) {
        self.itemDuration = itemDuration
        self.volume = volume
        self.pan = pan
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        super.init()
    }

    /// 本家 `IsMute`。
    public var isMute: Bool {
        volume.animationType == .none && volume.firstValue == 0
    }

    public override var duration: Int {
        if isMute { return 0 }
        return timeToPosition(itemDuration.ticks)
    }

    override func seekImpl(_ position: Int) {
        if !isMute {
            super.seekImpl(position)
            evaluatedDuration = duration
        }
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        if isMute { return 0 }
        return super.readImpl(&buffer, offset: offset, count: count)
    }

    override func process(_ buffer: inout [Float], offset: Int, count: Int) {
        if isMute { return }
        let durationSeconds = Double(positionToTimeTicks(evaluatedDuration)) / 10_000_000
        let evaluationFps = hz * 2
        var index = 0
        while index < count {
            let samplePosition = position + index
            let seconds = Double(positionToTimeTicks(samplePosition)) / 10_000_000
            let fadeInFactor = fadeIn == 0 ? 1.0 : min(1.0, seconds / fadeIn)
            let fadeOutFactor = fadeOut == 0
                ? 1.0
                : min(1.0, (durationSeconds - seconds) / fadeOut)
            let fadeFactor = min(fadeInFactor, fadeOutFactor)
            let gain = Float(
                volume.value(atFrame: samplePosition, length: evaluatedDuration, fps: evaluationFps)
                    / 100.0 * fadeFactor
            )
            let panValue = Float(
                pan.value(atFrame: samplePosition, length: evaluatedDuration, fps: evaluationFps)
                    / 100.0
            )
            buffer[offset + index] *= gain * (1 - max(0, panValue))
            if index + 1 < count {
                buffer[offset + index + 1] *= gain * (1 + min(0, panValue))
            }
            index += 2
        }
    }
}
