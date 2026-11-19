#if os(macOS)
import Foundation
import YMM4Core

/// 音声デコーダ選択を担う合成 Factory（Issue #70 段階3）。
///
/// 選択順は AVFoundation → FFmpeg。判定は拡張子やトラック有無では
/// なく「実際に開けて初回読み取りができること」で行う: AVFoundation
/// が供給を返しても、長さが正なのに初回読み取りで何も得られなければ
/// （メタ情報だけ取れて復号できない素材）、FFmpeg 側へ落とす。
/// AVFoundation で従来開けていた素材は試行を通過して従来どおり
/// AVFoundation が選ばれるため、挙動は変わらない。
public final class CompositePCMProviderFactory: PCMProviderFactory {
    private let primary: any PCMProviderFactory
    private let fallback: any PCMProviderFactory

    public init(
        primary: any PCMProviderFactory,
        fallback: any PCMProviderFactory
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    public func createProvider(
        filePath: String?, audioTrackIndex: Int
    ) -> PCMProvider? {
        if let provider = primary.createProvider(
            filePath: filePath, audioTrackIndex: audioTrackIndex
        ) {
            if provider.duration <= .zero {
                // 復号すべき内容が無い（空の素材）なら試行は不要。
                return provider
            }
            // 初回読み取りの試行: 1秒分読んで何か得られるか。
            // 無音区間も供給側は読み取り量として数えるため、
            // 先頭が無音の正常な素材を誤判定することはない。
            provider.seek(toTime: .zero)
            var scratch = [Float](repeating: 0, count: provider.hz * 2)
            let produced = provider.read(
                into: &scratch, offset: 0, count: scratch.count
            )
            if produced > 0 {
                provider.seek(toTime: .zero)
                return provider
            }
            // メタ情報だけ取れて復号できない素材は FFmpeg へ落とす。
        }
        return fallback.createProvider(
            filePath: filePath, audioTrackIndex: audioTrackIndex
        )
    }
}
#endif
