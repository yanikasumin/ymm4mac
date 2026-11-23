import Foundation

/// ティック値へ実数倍率を掛ける。本家の `TimeSpan` の実数倍に
/// 相当する。丸めは Mac 側の慣例（端数は絶対値側へ）にそろえる
/// （本家との差は 1 ティック未満で、フレーム単位の判定には
/// 影響しない）。
private func scaledTicks(_ value: TimeSpanValue, by factor: Double) -> TimeSpanValue {
    TimeSpanValue(
        ticks: Int64((Double(value.ticks) * factor).rounded(.toNearestOrAwayFromZero))
    )
}

extension BaseItem {
    /// 基底形の区切り（本家 `BaseItem.ContentSeparations`）。
    ///
    /// 定数レートでは単一の区切り
    /// `-ContentOffset + ContentLength × 先頭値` を返す。本家は
    /// 先頭値（% の数値そのもの。100% なら 100）をそのまま掛けて
    /// おり、動画・音声の定数形（|速度| で割り戻す形）とは次元が
    /// 異なるが、本家の実コードがそうなっているため意図的に
    /// そのまま写す（本家 BaseItem.cs の定数分岐）。
    ///
    /// 非定数レートでは、素材が尽きる時刻（`FindContentExhaustedTime`）
    /// があればそれが唯一の区切りで、素材長がゼロなら区切りは無い。
    func baseContentSeparations() -> AnySequence<TimeSpanValue> {
        let rateMap = PlaybackRateMap(rate: playbackRate2)
        if rateMap.isConstant {
            let separation = scaledTicks(contentLength, by: rateMap.firstRate) - contentOffset
            return AnySequence([separation])
        }
        guard contentLength > .zero,
              let exhausted = rateMap.findContentExhaustedTime(
                  itemLength: length, fps: videoFPS,
                  contentOffset: contentOffset, contentLength: contentLength)
        else { return AnySequence([]) }
        return AnySequence([exhausted])
    }

    /// 動画・音声共通の区切り（本家 `VideoItem.ContentSeparations` /
    /// `AudioItem.ContentSeparations` の上書き形。両者は同一の式）。
    ///
    /// 本体の素材長には尾なしの値（Mac 側の `originalContentLength`）
    /// を使い、入口のガードだけが尾込みの素材長（`contentLength`）
    /// で判定する（本家もプロパティ `ContentLength` でガードし、
    /// 本体はフィールドの生値を読む）。列挙は遅延であり、ループ時
    /// の定数形は無限に続くため、消費側は必要な範囲で打ち切る。
    ///
    /// エコーの値は引数で受ける。通常はアイテムの現在値を渡すが、
    /// エコー設定変更の長さ追随（`refreshContentLengthAfterEchoSettingsChange`）
    /// は、変更前のエコー値で区切りを再構成して判定するために
    /// 変更前の値を渡す。
    func mediaContentSeparations(
        isLooped: Bool,
        echoIsEnabled: Bool,
        echoInterval: Double,
        echoAttenuation: Double
    ) -> AnySequence<TimeSpanValue> {
        // 入口は尾込みの素材長がゼロのときだけ止める（本家
        // VideoItem.cs / AudioItem.cs は `ContentLength == TimeSpan.Zero`
        // で yield break）。尾は符号つきの先頭値で比例するため、
        // 逆再生＋エコーでは尾込み長が負になり得て、その場合も
        // 本家は本体の区切りを返す（FE-R43-136-03）。
        guard contentLength != .zero else { return AnySequence([]) }
        let rateMap = PlaybackRateMap(rate: playbackRate2)
        // エコーの追加時間（本家 `EchoEffect.AdditionalDuration`）。
        // 減衰率は本家どおり % から割合へ直して渡す。
        let echoAdditionalDuration = EchoAudioStream.additionalDuration(
            interval: TimeSpanValue(seconds: echoInterval),
            attenuation: echoAttenuation / 100
        )
        if rateMap.isConstant {
            // 定数形。速度 0 では区切りは生まれない（本家は
            // ゼロ除算を避けて yield break する）。
            guard rateMap.firstRate != 0 else { return AnySequence([]) }
            // 列挙の入力はプロパティ取得時点の現在値で固定する
            // （本家は列挙時点のライブ参照だが、消費側は即時
            // 列挙のみであり差は出ない）。
            let rawContentLength = originalContentLength
            let offset = contentOffset
            let firstRate = rateMap.firstRate
            return AnySequence {
                MediaConstantSeparationsIterator(
                    rawContentLength: rawContentLength,
                    contentOffset: offset,
                    firstRate: firstRate,
                    isLooped: isLooped,
                    echoIsEnabled: echoIsEnabled,
                    echoAdditionalDuration: echoAdditionalDuration
                )
            }
        }
        // 非定数形。素材本体が無ければ横切も尽きる時刻も生まれず、
        // エコーの区切りだけが残り得る。本体側のイテレータは
        // 列挙のたびに新しく生成する（生成済みのイテレータを
        // クロージャで共有すると、再列挙で結果が失われる。
        // 本家の IEnumerable は列挙ごとに独立。本家との意味論の
        // 一致として FE-R43-136-02）。
        let rawContentLength = originalContentLength
        let itemLength = length
        let fps = videoFPS
        let offset = contentOffset
        return AnySequence {
            let contentPart: AnyIterator<TimeSpanValue>
            if rawContentLength <= .zero {
                contentPart = AnyIterator { nil }
            } else if isLooped {
                contentPart = AnyIterator(
                    rateMap.enumerateContentBoundaryCrossings(
                        itemLength: itemLength, fps: fps,
                        contentOffset: offset, contentLength: rawContentLength
                    ).makeIterator()
                )
            } else if let exhausted = rateMap.findContentExhaustedTime(
                itemLength: itemLength, fps: fps,
                contentOffset: offset, contentLength: rawContentLength
            ) {
                contentPart = AnyIterator([exhausted].makeIterator())
            } else {
                contentPart = AnyIterator { nil }
            }
            return MediaNonConstantSeparationsIterator(
                contentIterator: contentPart,
                echoIsEnabled: echoIsEnabled,
                echoAdditionalDuration: echoAdditionalDuration
            )
        }
    }

    /// アイテムの長さの終端が、いずれかの区切りの ±1 フレーム
    /// 以内にあるか。
    ///
    /// 本家 `ItemEditorViewModel.EditingValue` が編集開始時に捕捉
    /// する `isLengthOnSeparator` の判定そのもの: 区切りを
    /// フレームへ換算し、`Length + 1` 以下の間だけ走査して
    /// `|frame − Length| ≤ 1` を探す。編集終了時調整の分岐 (2)
    /// の発火条件（基点への捕捉は
    /// `capturePlaybackRateEditBaseline`、エコー変更時の追随は
    /// `refreshContentLengthAfterEchoSettingsChange` が使う）。
    public func isLengthEndOnContentSeparator(fps: Int) -> Bool {
        isLengthEndOnContentSeparator(fps: fps, separations: contentSeparations)
    }

    /// 区切りの列を差し替えた終端判定。エコー設定変更の追随が、
    /// 変更前の状態で構成した区切りに対して判定するために使う。
    func isLengthEndOnContentSeparator(
        fps: Int, separations: AnySequence<TimeSpanValue>
    ) -> Bool {
        let limit = length + 1
        for separation in separations {
            let frame = FrameTime.frame(from: separation.seconds, fps: fps)
            if frame > limit { break }
            if abs(frame - length) <= 1 { return true }
        }
        return false
    }
}

/// 動画・音声の定数形の区切りの遅延列挙。
///
/// 本体は `(素材長 × (i+1) − オフセット) / |速度| × 100` を
/// 繰り返し回数だけ（ループ時は無制限）生み、その後にエコーの
/// 区切りを1つ生む。エコーの区切りは、最後に生んだ本体の位置へ
/// `GetEchoLength / |速度| × 100` を加えた位置（本体が1つも
/// 生まれなかった場合はゼロ起点）。`GetEchoLength` は符号つきの
/// 先頭値で比例するため、逆再生ではエコー分が負になり、その
/// 場合は生まれない（本家の `> TimeSpan.Zero` 判定）。
private struct MediaConstantSeparationsIterator: IteratorProtocol {
    let rawContentLength: TimeSpanValue
    let contentOffset: TimeSpanValue
    let firstRate: Double
    let isLooped: Bool
    let echoIsEnabled: Bool
    let echoAdditionalDuration: TimeSpanValue

    private var index = 0
    private var lastYielded: TimeSpanValue = .zero
    private var didFinishEcho = false

    init(
        rawContentLength: TimeSpanValue,
        contentOffset: TimeSpanValue,
        firstRate: Double,
        isLooped: Bool,
        echoIsEnabled: Bool,
        echoAdditionalDuration: TimeSpanValue
    ) {
        self.rawContentLength = rawContentLength
        self.contentOffset = contentOffset
        self.firstRate = firstRate
        self.isLooped = isLooped
        self.echoIsEnabled = echoIsEnabled
        self.echoAdditionalDuration = echoAdditionalDuration
    }

    mutating func next() -> TimeSpanValue? {
        if rawContentLength > .zero, isLooped || index == 0 {
            let scaled = (Double(rawContentLength.ticks) * Double(index + 1)
                - Double(contentOffset.ticks)) / abs(firstRate) * 100
            let value = TimeSpanValue(
                ticks: Int64(scaled.rounded(.toNearestOrAwayFromZero))
            )
            index += 1
            lastYielded = value
            return value
        }
        guard !didFinishEcho else { return nil }
        didFinishEcho = true
        let echoLength = Double(echoAdditionalDuration.ticks) * (firstRate / 100)
        let scaledTail = echoLength / abs(firstRate) * 100
        guard echoIsEnabled, scaledTail > 0 else { return nil }
        return lastYielded + TimeSpanValue(
            ticks: Int64(scaledTail.rounded(.toNearestOrAwayFromZero))
        )
    }
}

/// 動画・音声の非定数形の区切りの遅延列挙。
///
/// 本体（ループ時は境界の横切列挙、非ループ時は素材が尽きる
/// 時刻）をすべて生んだ後に、エコーの区切りを1つ生む。エコーの
/// 区切りは、最後に生んだ本体の位置（無ければゼロ）へエコーの
/// 追加時間をそのまま加えた位置（本家はこの分岐では速度で
/// 割り戻さない）。
private struct MediaNonConstantSeparationsIterator: IteratorProtocol {
    var contentIterator: AnyIterator<TimeSpanValue>
    let echoIsEnabled: Bool
    let echoAdditionalDuration: TimeSpanValue

    private var last: TimeSpanValue = .zero
    private var contentFinished = false
    private var didFinishEcho = false

    init(
        contentIterator: AnyIterator<TimeSpanValue>,
        echoIsEnabled: Bool,
        echoAdditionalDuration: TimeSpanValue
    ) {
        self.contentIterator = contentIterator
        self.echoIsEnabled = echoIsEnabled
        self.echoAdditionalDuration = echoAdditionalDuration
    }

    mutating func next() -> TimeSpanValue? {
        if !contentFinished {
            if let value = contentIterator.next() {
                last = value
                return value
            }
            contentFinished = true
        }
        guard !didFinishEcho else { return nil }
        didFinishEcho = true
        guard echoIsEnabled, echoAdditionalDuration > .zero else { return nil }
        return last + echoAdditionalDuration
    }
}
