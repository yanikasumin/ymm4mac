import Foundation

/// アイテム単位のエフェクトチェーンを通した音声ストリーム。
/// 本家 `EffectedItemSource`（Player.Audio）に対応する。
///
/// チェーンの接続順（本家どおり）:
/// 1. NegativeSeekable（常時）
/// 2. 速度が可変なら VariablePlaybackRate。定数なら、負速度で Reverse、
///    ループ有効で Loop、ContentOffset があれば ContentOffset
/// 3. Echo（有効な場合）
/// 4. 速度 >100% かつソース Hz < 20000 のとき Resampler（倍率）
/// 5. 定数速度 != 100% のとき PlaybackRate（SOLA は差し替え点として
///    リサンプリング方式で代替）
/// 6. VoiceItem のみ Upsampler（方式が MediaFoundation 以外の場合）
/// 7. Resampler（タイムライン Hz。Hz = 0 のときは挿入しない）
/// 8. ユーザー指定 AudioEffects（有効なもののみ、供給元経由）
/// 9. VolumePan（noVolumeControl 時は除く）
/// 10. Resampler（タイムライン Hz）
///
/// 読み取りはアイテムの長さ（タイムライン Hz 換算）で打ち切られ、
/// 負位置の分は無音として数える（バッファには書かない）。
/// シークは 0 未満を 0 に丸めてチェーンへ転送する。
public final class EffectedAudioItemSource: AudioStream {
    private let effected: AudioStream
    private let itemDurationSamples: Int

    public override var hz: Int { effected.hz }
    public override var duration: Int { effected.duration }

    public init(
        item: BaseItem,
        audio: any AudioItemProperties,
        rawSource: AudioStream,
        hz: Int,
        fps: Int,
        options: AudioChainOptions = AudioChainOptions(),
        effectProvider: any AudioEffectProvider = EmptyAudioEffectProvider()
    ) {
        let itemDuration = TimeSpanValue(
            ticks: AudioStream.frameToTicks(frame: item.length, fps: fps)
        )
        var processors: [AudioEffectProcessorBase] = [NegativeSeekableAudioStream()]

        let rateMap = PlaybackRateMap(rate: item.playbackRate2)
        let firstRate = rateMap.firstRate
        if !rateMap.isConstant {
            processors.append(
                VariablePlaybackRateStream(
                    rateMap: rateMap,
                    itemLength: item.length,
                    fps: fps,
                    contentOffset: item.contentOffset,
                    isLooped: audio.isLooped
                )
            )
            // SOLA の場合は本家では VariableSolaPitchCorrectionEffect が
            // 続く。差し替え点として未実装（台帳に記録）。
        } else {
            if firstRate < 0 {
                processors.append(ReverseAudioStream())
            }
            if audio.isLooped {
                processors.append(LoopAudioStream(isEnabled: true))
            }
            if item.contentOffset != .zero {
                processors.append(ContentOffsetAudioStream(contentOffset: item.contentOffset))
            }
        }
        if !options.noEcho, audio.echoIsEnabled, audio.echoInterval > 0, audio.echoAttenuation > 0 {
            processors.append(
                EchoAudioStream(
                    interval: TimeSpanValue(seconds: audio.echoInterval),
                    attenuation: audio.echoAttenuation / 100
                )
            )
        }
        if rateMap.isConstant, firstRate > 100, rawSource.hz < 20_000 {
            processors.append(ResamplerStream(byRate: max(1, firstRate / 100)))
        }
        if rateMap.isConstant, firstRate != 100 {
            // 本家は SOLA 方式なら PlaybackRateSolaTimeStretchEffect を
            // 使う。差し替え点として、ここでは方式によらず
            // リサンプリング方式（PlaybackRateStream）で代替する。
            processors.append(PlaybackRateStream(rate: abs(firstRate) / 100))
        }
        if item is VoiceItem, hz != 0 {
            switch options.voiceUpsampling {
            case .mediaFoundation:
                break
            case .linear:
                processors.append(
                    UpsamplerStream(targetHz: hz, kernel: LinearInterpolationKernel())
                )
            case .cubic:
                processors.append(
                    UpsamplerStream(targetHz: hz, kernel: CubicInterpolationKernel())
                )
            }
        }
        if hz != 0 {
            processors.append(ResamplerStream(toHz: hz))
        }
        if !options.noEffect {
            processors += effectProvider.processors(
                for: audio.audioEffects, duration: itemDuration, fps: fps
            )
        }
        if !options.noVolumeControl {
            processors.append(
                VolumePanStream(
                    itemDuration: itemDuration,
                    volume: audio.volume,
                    pan: audio.pan,
                    fadeIn: audio.audioFadeIn,
                    fadeOut: audio.audioFadeOut
                )
            )
        }
        if hz != 0 {
            processors.append(ResamplerStream(toHz: hz))
        }

        var current: AudioStream = rawSource
        for processor in processors {
            processor.input = current
            current = processor
        }
        effected = current
        itemDurationSamples = Int(Double(current.hz) * itemDuration.seconds) * 2
        super.init()
    }

    override func seekImpl(_ position: Int) {
        effected.seek(to: max(0, position))
    }

    override func readImpl(_ buffer: inout [Float], offset: Int, count: Int) -> Int {
        var skipped = 0
        var readOffset = offset
        var readCount = count
        if position < 0 {
            skipped = min(count, -position)
            readCount -= skipped
            readOffset += skipped
        }
        var remaining = itemDurationSamples - position - skipped
        remaining -= remaining % 2
        readCount = max(0, min(remaining, readCount))
        return effected.read(into: &buffer, offset: readOffset, count: readCount) + skipped
    }
}

/// アイテムから原音ストリームとチェーン適用済みストリームを生成する工場。
///
/// 本家の `IAudioItem.CreateAudioSource(Scene)` と
/// `EffectedItemSource` の生成経路に対応する。ファイルデコード
/// （PCM プロバイダ）とシーン解決は差し替え点として注入する。
public final class AudioSourceFactory {
    /// ファイルデコードの供給元。
    public var providerFactory: any PCMProviderFactory
    /// SceneItem の参照先タイムラインの解決（シーン = タイムライン）。
    public var sceneTimelineResolver: (UUID) -> Timeline?
    /// VoiceItem の PCM 供給元。本家では生成済み一時ファイルまたは
    /// カスタム音声ファイルを通常のファイル経路で開くが、モデル層は
    /// パスを保持しないため、ここを差し替え点とする。nil は無音。
    public var voiceProviderResolver: (VoiceItem) -> PCMProvider?
    /// チェーン構築の既定オプション。
    public var chainOptions: AudioChainOptions
    /// ユーザー音声エフェクトの供給元。
    public var effectProvider: any AudioEffectProvider

    public init(
        providerFactory: any PCMProviderFactory,
        sceneTimelineResolver: @escaping (UUID) -> Timeline? = { _ in nil },
        voiceProviderResolver: @escaping (VoiceItem) -> PCMProvider? = { _ in nil },
        chainOptions: AudioChainOptions = AudioChainOptions(),
        effectProvider: any AudioEffectProvider = EmptyAudioEffectProvider()
    ) {
        self.providerFactory = providerFactory
        self.sceneTimelineResolver = sceneTimelineResolver
        self.voiceProviderResolver = voiceProviderResolver
        self.chainOptions = chainOptions
        self.effectProvider = effectProvider
    }

    /// アイテムの原音ストリーム（チェーン適用前）。
    /// 音声を持たないアイテムでは無音ストリームを返す。
    public func rawStream(for item: BaseItem) -> AudioStream {
        switch item {
        case let audioItem as AudioItem:
            return FileAudioStream(
                provider: providerFactory.createProvider(
                    filePath: audioItem.filePath,
                    audioTrackIndex: audioItem.audioTrackIndex
                )
            )
        case let videoItem as VideoItem:
            return FileAudioStream(
                provider: providerFactory.createProvider(
                    filePath: videoItem.filePath,
                    audioTrackIndex: videoItem.audioTrackIndex
                )
            )
        case let voiceItem as VoiceItem:
            return FileAudioStream(provider: voiceProviderResolver(voiceItem))
        case let sceneItem as SceneItem:
            if let timeline = sceneTimelineResolver(sceneItem.sceneId) {
                return makeTimelineMixer(for: timeline)
            }
            return FileAudioStream(provider: nil)
        default:
            return FileAudioStream(provider: nil)
        }
    }

    /// チェーン適用済みのアイテムストリームを生成する。
    public func effectedStream(
        for item: BaseItem, hz: Int, fps: Int, options: AudioChainOptions? = nil
    ) -> EffectedAudioItemSource? {
        guard let audio = item as? any AudioItemProperties else { return nil }
        return EffectedAudioItemSource(
            item: item,
            audio: audio,
            rawSource: rawStream(for: item),
            hz: hz,
            fps: fps,
            options: options ?? chainOptions,
            effectProvider: effectProvider
        )
    }

    /// 入れ子タイムライン用のミキサーを生成する。
    public func makeTimelineMixer(for timeline: Timeline) -> TimelineAudioMixer {
        TimelineAudioMixer(timeline: timeline, factory: self)
    }
}
