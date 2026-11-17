import XCTest
@testable import YMM4Core

// 音声系テストの共有部品。
//
// W1（構造整理）で、AudioPipelineTests / AudioDriftTests /
// AudioSampleAccuracyTests / ExportAudioProviderTests の各ファイルに
// 私用定義されていた同一の供給元ファクトリと構築ヘルパをここへ集約した。
// 各ファイル固有の構築（makeTimeline のようにシグネチャが異なるもの）は
// 集約せず、各ファイルに残してある。

// MARK: - テスト用の供給元

/// パスから PCMProvider を引く辞書式ファクトリ。
final class MapPCMProviderFactory: PCMProviderFactory {
    var providers: [String: PCMProvider] = [:]

    func createProvider(filePath: String?, audioTrackIndex: Int) -> PCMProvider? {
        guard let filePath else { return nil }
        return providers[filePath]
    }
}

/// 一定値で埋めたメモリ上の素材。
func constantProvider(
    _ value: Float, frames: Int, hz: Int = 48_000
) -> InMemoryPCMProvider {
    InMemoryPCMProvider(
        samples: [Float](repeating: value, count: frames * 2), hz: hz
    )
}

/// フレーム番号 + offset を値にしたランプ波形（L = R = フレーム番号 + offset）。
/// offset を付けると無音（0）と内容の区別がつく。
/// 出力サンプルの値から「いま何フレーム目の素材が鳴っているか」を
/// 直接読み取れるため、内容位置のドリフト測定にも使う。
/// Float32 で整数を正確に表せるのは 2^24 フレームまでで、それを超える
/// 測定点では表現誤差（ulp）が最大で 1 フレーム程度乗る。許容幅は
/// その分を見込んで設定し、ドリフトの有無は「偏差の時間変化」で判定する。
func rampProvider(frames: Int, hz: Int, offset: Float = 0) -> InMemoryPCMProvider {
    var samples: [Float] = []
    samples.reserveCapacity(frames * 2)
    for frame in 0..<frames {
        samples.append(Float(frame) + offset)
        samples.append(Float(frame) + offset)
    }
    return InMemoryPCMProvider(samples: samples, hz: hz)
}

// MARK: - アイテム構築ヘルパ

/// 値が時間で変化しないアニメーション。
func constantAnimation(_ value: Double) -> Animation {
    Animation(
        defaultValue: value, minValue: -100_000, maxValue: 100_000,
        animationType: .none, values: [AnimationValue(value)]
    )
}

func makeAudioItem(
    filePath: String, frame: Int = 0, length: Int = 30, layer: Int = 0,
    volume: Double = 100
) -> AudioItem {
    let item = AudioItem()
    item.frame = frame
    item.length = length
    item.layer = layer
    item.filePath = filePath
    item.volume = constantAnimation(volume)
    item.pan = constantAnimation(0)
    return item
}
