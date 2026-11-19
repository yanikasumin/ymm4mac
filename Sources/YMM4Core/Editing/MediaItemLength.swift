import Foundation

/// メディア情報取得（I/O 供給層）の結果。
///
/// 再生時間は素材そのものの長さ（本家の `OriginalContentLength` に
/// 相当し、エコー尾を含まない）。画像は長さを持たない（本家
/// `ImageItem.ContentLength` は常に 0）ため duration は 0 で、
/// 寸法だけが入る。寸法は情報表示用で、アイテムには保存しない
/// （本家も寸法をアイテムに保持しない）。
public struct MediaFileInfo: Equatable, Sendable {
    /// 素材の再生時間（提示区間）。
    public var duration: TimeSpanValue
    /// 映像・画像の幅（ピクセル）。音声では nil。
    public var width: Int?
    /// 映像・画像の高さ（ピクセル）。音声では nil。
    public var height: Int?

    public init(duration: TimeSpanValue, width: Int? = nil, height: Int? = nil) {
        self.duration = duration
        self.width = width
        self.height = height
    }
}

extension BaseItem {
    /// 素材が決まらない場合の既定の長さ（フレーム）。
    ///
    /// 本家 `ResetLength` のフォールバック値であり、既定アイテム
    /// （`DefaultItems`）の Length の初期値でもある（全種 300）。
    public static var defaultItemLength: Int { 300 }

    /// エコーの尾の長さ。本家 `GetEchoLength`:
    /// `EchoEffect.AdditionalDuration × (再生速度の先頭値 / 100)`。
    /// エコーを持たないアイテム、無効時は 0。
    public var echoTailLength: TimeSpanValue {
        guard let audio = self as? any AudioItemProperties, audio.echoIsEnabled else {
            return .zero
        }
        let additional = EchoAudioStream.additionalDuration(
            interval: TimeSpanValue(seconds: audio.echoInterval),
            attenuation: audio.echoAttenuation / 100
        )
        return TimeSpanValue(seconds: additional.seconds * (playbackRate2.firstValue / 100))
    }

    /// 取得済みのメディア情報を記録する（配置の調整層の入口）。
    ///
    /// `originalContentLength` へ素材そのものの長さを、
    /// `contentLength` へエコー尾を含む長さを入れる（本家では
    /// `ContentLength` の取得時に都度計算されるものを、こちらは
    /// 記録時点のエコー設定で確定させる）。画像アイテムは本家でも
    /// 長さを持たないため何もしない。
    ///
    /// 素材そのものの長さが 0 の場合は、本家が `ContentLength` を
    /// エコー設定にかかわらず 0 とする規則（VideoItem.cs /
    /// AudioItem.cs の取得経路）に従い、エコー尾を加えない
    /// （FE-R15-001）。
    public func recordMediaInfo(_ info: MediaFileInfo) {
        switch self {
        case is VideoItem, is AudioItem:
            originalContentLength = info.duration
            contentLength = info.duration == .zero
                ? .zero
                : info.duration + echoTailLength
        default:
            break
        }
    }

    /// 再生速度を適用した素材の消費時間。本家
    /// `GetContentLengthAppliedPlaybackRate`。
    ///
    /// 定数レートでは `(ContentLength - ContentOffset) / |レート|`
    /// （% 換算）。非定数レートでは積分テーブルで素材が尽きる時刻を
    /// 探す（その際の表の長さと FPS はアイテム自身の現在値を使う。
    /// 本家も `item.Length` と `VideoFPS` を使う）。
    public func contentLengthAppliedPlaybackRate() -> TimeSpanValue {
        if contentLength == .zero {
            return .zero
        }
        let rateMap = PlaybackRateMap(rate: playbackRate2)
        if !rateMap.isConstant {
            return rateMap.findContentExhaustedTime(
                itemLength: length, fps: videoFPS,
                contentOffset: contentOffset, contentLength: contentLength
            ) ?? .zero
        }
        let firstValue = playbackRate2.firstValue
        if firstValue == 0 {
            return .zero
        }
        let scaled = max(0, (contentLength - contentOffset).seconds)
            / abs(firstValue) * 100
        // 本家は OverflowException を捕捉して 5 秒へ倒す。こちらでも
        // tick へ変換できない規模の値は同じ既定へ倒す。
        guard scaled.isFinite, scaled < 9.0e11 else {
            return TimeSpanValue(seconds: 5)
        }
        return TimeSpanValue(seconds: scaled)
    }

    /// 長さを素材の長さから決め直す。本家 `ItemEx.ResetLength`。
    ///
    /// - Parameter fps: フレーム換算に使う FPS（配置先タイムラインの
    ///   値。本家は引数の `VideoInfo` の FPS を使う）。
    /// - Parameter resetContentOffset: true なら `ContentOffset` を
    ///   0 へ戻してから決める（新規追加とファイル差し替えの経路）。
    /// 素材の長さが 0、または定数レートが 0 の場合は既定の長さ
    /// （300 フレーム）になる。
    public func resetLength(fps: Int, resetContentOffset: Bool = false) {
        if resetContentOffset {
            contentOffset = .zero
        }
        let rateMap = PlaybackRateMap(rate: playbackRate2)
        if contentLength != .zero,
           playbackRate2.firstValue != 0 || !rateMap.isConstant {
            length = max(
                1,
                FrameTime.frame(from: contentLengthAppliedPlaybackRate().seconds, fps: fps)
            )
        } else {
            length = Self.defaultItemLength
        }
    }

    /// ファイル差し替え時の長さ調整。本家アイテムエディタの編集終了
    /// 処理（`ItemEditorViewModel.EditingValue.EndEdit`）のうち、
    /// ファイル変更に対応する分岐。
    ///
    /// 素材そのものの長さが変わっていれば、利用者が設定した
    /// トリムは引き継がず、オフセットを 0 へ戻して長さを決め直す。
    /// 変わっていなければ（同じファイルの選び直し等）長さには
    /// 触らない。呼び出し側は、パスとメディア情報を新しい値へ
    /// 更新してから、変更前の `originalContentLength` を渡す。
    ///
    /// - Returns: 長さを決め直したら true。
    @discardableResult
    public func adjustLengthAfterFileChange(
        previousOriginalContentLength: TimeSpanValue, fps: Int
    ) -> Bool {
        guard originalContentLength != previousOriginalContentLength else {
            return false
        }
        resetLength(fps: fps, resetContentOffset: true)
        return true
    }
}
