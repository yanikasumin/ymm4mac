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
    /// `originalContentLength` へ素材そのものの長さを入れ、
    /// `contentLength` は `refreshContentLengthForEchoSettings` で
    /// 現在のエコー設定から計算する。本家では `ContentLength` が
    /// 取得時に都度計算されるため、こちらも記録の一時点では
    /// 終わらせず、エコー設定の書き込みに追随させる（FE-R15-006）。
    /// 画像アイテムは本家でも長さを持たないため何もしない。
    public func recordMediaInfo(_ info: MediaFileInfo) {
        switch self {
        case is VideoItem, is AudioItem:
            originalContentLength = info.duration
            refreshContentLengthForEchoSettings()
        default:
            break
        }
    }

    /// 素材長（エコー尾込み）を現在のエコー設定で計算し直す
    /// （FE-R15-006）。
    ///
    /// 本家は `ContentLength` の取得のたびに、ファイルの再生時間へ
    /// 現在のエコー設定の尾を加える（VideoItem.cs / AudioItem.cs の
    /// `ContentLength` 取得経路。エコープロパティの setter は
    /// `ContentLength` の変更通知を出す）。こちらは保持値のため、
    /// 動画・音声アイテムのエコープロパティの書き込み（didSet）から
    /// この再計算を呼んで追随させる。規則は記録時と同一: 素材その
    /// ものの長さが 0 の場合は、本家が `ContentLength` をエコー設定
    /// にかかわらず 0 とする規則に従い、エコー尾を加えない
    /// （FE-R15-001）。
    ///
    /// 長さ（`length`）自体はここでは変えない。長さの追随は
    /// 分岐 (2) の役割であり、エコープロパティの書き込み経路では
    /// `refreshContentLengthAfterEchoSettingsChange` がこの再計算と
    /// 組み合わせて担い、再生速度の編集セッションでは適用層
    /// `finishPlaybackRateEdit` が担う。素材情報の記録
    /// （`recordMediaInfo`）と再生速度の書き込みは分岐 (1)・(3)
    /// の管轄であるため、ここでは再計算だけを行う。
    public func refreshContentLengthForEchoSettings() {
        switch self {
        case is VideoItem, is AudioItem:
            contentLength = originalContentLength == .zero
                ? .zero
                : originalContentLength + echoTailLength
        default:
            break
        }
    }

    /// エコー設定の書き込みに対する素材長の再計算と長さの追随
    /// （FE-R15-006 の残件。編集終了時調整の分岐 (2) のモデル層形）。
    ///
    /// 本家では、エコーを含むアイテム編集はエディタのセッション
    /// として行われ、終了時に分岐 (2)（素材長が変わり、かつ編集
    /// 開始時点で長さの終端が区切り上にあれば `ResetLength` で
    /// 決め直し）が適用される。Mac 側にはエコー設定のインスペクタ
    /// 記述子が無く（モデル＋保存のみで、記述子の追加は本単位の
    /// 範囲外）、編集セッションが存在しないため、書き込みのたびに
    /// 「変更前の終端判定 → 再計算 → 条件を満たせば決め直し」を
    /// 1回の変更として適用する形に置き換える（Mac 側の適応。
    /// 実装台帳 FE-CONTENTSEP に記録）。
    ///
    /// 終端判定は変更前の状態で行う必要があるため、区切りは
    /// 変更前のエコー値で再構成する（引数）。呼び出し時点では
    /// 素材長・素材本来の長さ・速度・長さ・オフセットはいずれも
    /// 変更前の値であり、書き込み済みなのは対象のエコー値だけ
    /// である。決め直しの FPS はアイテムへ注入済みの `videoFPS`
    /// を使う（基点捕捉と同じ前提）。
    ///
    /// - Parameter isLooped: 書き込み時点のループ設定（区切りの
    ///   形の入力。ループ設定自体の書き込みは追随の対象外）。
    /// - Parameter previousEchoIsEnabled: 変更前のエコー有効。
    /// - Parameter previousEchoInterval: 変更前のエコー間隔（秒）。
    /// - Parameter previousEchoAttenuation: 変更前のエコー減衰（%）。
    public func refreshContentLengthAfterEchoSettingsChange(
        isLooped: Bool,
        previousEchoIsEnabled: Bool,
        previousEchoInterval: Double,
        previousEchoAttenuation: Double
    ) {
        let previousContentLength = contentLength
        let separationsBeforeChange = mediaContentSeparations(
            isLooped: isLooped,
            echoIsEnabled: previousEchoIsEnabled,
            echoInterval: previousEchoInterval,
            echoAttenuation: previousEchoAttenuation
        )
        let wasLengthEndOnSeparator = isLengthEndOnContentSeparator(
            fps: videoFPS, separations: separationsBeforeChange)
        refreshContentLengthForEchoSettings()
        guard contentLength != previousContentLength,
              wasLengthEndOnSeparator else { return }
        resetLength(fps: videoFPS)
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

    /// 編集終了時の再生速度変更に対する長さ調整（FE-R15-004 の
    /// 分岐 (3)）。本家アイテムエディタの編集終了処理
    /// （`ItemEditorViewModel.EditingValue.EndEdit`）のうち、再生
    /// 速度に対応する分岐。
    ///
    /// 編集前後とも再生速度が定数（アニメーション種別「なし」）で
    /// 先頭値が変わった場合に、素材の消費量を保つよう長さを比率で
    /// 換算する。消費量は「長さ × |旧速度| / 100」（旧速度が 0 の
    /// 場合は長さそのもの。本家の特殊分岐）で、新しい長さは
    /// 「消費量 / |新速度| × 100」の小数部を切り捨てた値。新速度が
    /// 0 の場合は長さを換算しない。換算結果が 1 未満なら既定の
    /// 長さ（300 フレーム）へ倒す。速度の符号が反転した場合は、
    /// 素材の終端側から見た再生位置を保つようオフセットを
    /// 付け替える: `ContentLength − (ContentOffset + 新しい長さを
    /// 時間換算した値 × |旧速度| / 100)`（時間換算は
    /// `VideoInfo.GetTimeFrom` = `FrameTime` のフレーム→時間）。
    ///
    /// 本家の分岐は else-if 連鎖で、分岐 (1)（素材そのものの長さが
    /// 変わった場合の決め直し）が優先する。ファイル変更の経路は
    /// `adjustLengthAfterFileChange` が分岐 (1) を担うため、こちらは
    /// 素材そのものの長さが変わっていない編集（速度だけの変更）で
    /// 呼ぶこと。分岐 (2)（素材長が変わり、かつ長さの終端が区切り
    /// 上にある場合の決め直し）は、適用層
    /// `finishPlaybackRateEdit` がこの分岐より先に判定する。
    ///
    /// - Parameter previousFirstValue: 編集開始時点の再生速度の
    ///   先頭値（%）。
    /// - Parameter previousIsConstant: 編集開始時点で再生速度が
    ///   定数だったか。
    /// - Parameter fps: オフセット付け替えの時間換算に使う FPS
    ///   （所属タイムラインの値。本家は `timeline.VideoInfo`）。
    /// - Returns: 長さまたはオフセットを変えたら true（呼び出し側
    ///   はタイムライン長のキャッシュ再計算の判断に使う。
    ///   FE-R16-001）。
    @discardableResult
    public func adjustLengthAfterPlaybackRateChange(
        previousFirstValue: Double, previousIsConstant: Bool, fps: Int
    ) -> Bool {
        guard previousIsConstant,
              playbackRate2.animationType == .none else { return false }
        let newFirstValue = playbackRate2.firstValue
        guard newFirstValue != previousFirstValue else { return false }
        let oldLength = length
        let oldContentOffset = contentOffset
        if newFirstValue != 0 {
            let consumed = previousFirstValue == 0
                ? Double(length)
                : Double(length) * abs(previousFirstValue) / 100
            // 本家は double から int へのキャスト（0 方向への
            // 切り捨て）。消費量・長さは負にならないため床と一致する。
            let scaled = consumed / abs(newFirstValue) * 100
            // 極小の新速度では換算結果が整数の表現範囲を超え、
            // Swift の Int 変換が実行時トラップになる。有限で
            // 範囲内に収まる場合だけ変換し、範囲外は 1 未満の
            // 場合と同じ既定の長さへ倒す（Mac 側の安全策。
            // FE-R27-129-05。本家の範囲外キャストの結果とは
            // 照合していない）。
            length = scaled.isFinite && scaled < Double(Int.max)
                ? Int(scaled)
                : Self.defaultItemLength
        }
        if length < 1 {
            length = Self.defaultItemLength
        }
        if (previousFirstValue < 0) != (newFirstValue < 0) {
            let lengthTime = TimeSpanValue(
                seconds: FrameTime.time(fromFrame: length, fps: fps)
            )
            let scaled = TimeSpanValue(
                ticks: Int64(
                    Double(lengthTime.ticks) * abs(previousFirstValue) / 100
                )
            )
            contentOffset = contentLength - (contentOffset + scaled)
        }
        return length != oldLength || contentOffset != oldContentOffset
    }

    /// 編集セッション開始時点の基点を捕捉する（FE-R15-004）。
    ///
    /// 基点の所有は呼び出し側（アプリ層の行のセッション状態）へ
    /// 移り、寿命はセッションと一致させる。捕捉し直しや後続
    /// セッションへの持ち越しはしない（FE-R27-129-03）。
    ///
    /// 分岐 (2) の判定に使う「長さの終端が区切り上にあるか」も
    /// ここで捕捉する。本家 `EditingValue` はタイムラインの FPS
    /// で判定するが、こちらはアイテムへ注入済みの `videoFPS`
    /// （所属タイムラインの FPS と一致する運用であり、
    /// `contentLengthAppliedPlaybackRate` も同じ前提に立つ）を使う。
    public func capturePlaybackRateEditBaseline() -> PlaybackRateEditBaseline {
        PlaybackRateEditBaseline(
            firstValue: playbackRate2.firstValue,
            isConstant: playbackRate2.animationType == .none,
            contentLength: contentLength,
            originalContentLength: originalContentLength,
            isLengthEndOnSeparator: isLengthEndOnContentSeparator(fps: videoFPS))
    }

    /// 編集終了時の長さ調整の適用（FE-R15-004 の編集終了時調整の
    /// 適用層）。分岐の優先をここで一元的に決める:
    ///
    /// - 分岐 (1): 素材本来の長さが基点から変わっていれば、編集の
    ///   途中でファイルが差し替わり、ファイル変更の経路
    ///   （`adjustLengthAfterFileChange`）が既に長さを決め直して
    ///   いるため、後続の分岐を重ねて実行しない（FE-R27-129-04。
    ///   本家は else-if 連鎖で分岐が排他）。
    /// - 分岐 (2): 素材長が基点から変わり、かつ編集開始時点で
    ///   長さの終端が区切り（`contentSeparations`）の ±1 フレーム
    ///   以内にあった場合は、`resetLength` で長さを素材長へ
    ///   決め直す（オフセットは付け替えない。本家 `EndEdit` の
    ///   第2分岐。終端が区切り上にあったかは基点の
    ///   `isLengthEndOnSeparator` が保持する）。
    /// - 分岐 (3): `adjustLengthAfterPlaybackRateChange` による
    ///   比率再計算。
    ///
    /// - Parameter baseline: 編集セッション開始時点の基点
    ///   （`capturePlaybackRateEditBaseline`）。
    /// - Parameter fps: 長さの決め直しとオフセット付け替えの
    ///   時間換算に使う FPS。
    /// - Returns: 長さまたはオフセットを変えたら true。
    @discardableResult
    public func finishPlaybackRateEdit(
        baseline: PlaybackRateEditBaseline, fps: Int
    ) -> Bool {
        guard originalContentLength == baseline.originalContentLength
        else { return false }
        if contentLength != baseline.contentLength,
           baseline.isLengthEndOnSeparator {
            let oldLength = length
            let oldContentOffset = contentOffset
            resetLength(fps: fps)
            return length != oldLength || contentOffset != oldContentOffset
        }
        return adjustLengthAfterPlaybackRateChange(
            previousFirstValue: baseline.firstValue,
            previousIsConstant: baseline.isConstant,
            fps: fps)
    }
}

/// 再生速度の編集セッションの基点（FE-R27-129-03 / 04）。
///
/// 本家 `EditingValue` が編集開始時（BeginEdit）に捕捉する値の
/// うち、編集終了時調整の分岐判定に要るもの。旧再生速度の先頭値
/// と定数かどうかは分岐 (3) の入力であり、素材本来の長さは
/// 分岐 (1) の成立判定（編集の途中でのファイル差し替えの検出）
/// に、素材長と区切り上の終端判定は分岐 (2) の判定に使う
/// （本家も `OldContentLength` / `OldOriginalContentLength` と
/// `isLengthOnSeparator` を保持する。監査 Round 27 の補足）。
public struct PlaybackRateEditBaseline: Equatable, Sendable {
    /// 編集開始時点の再生速度の先頭値（%）。
    public var firstValue: Double
    /// 編集開始時点で再生速度が定数（アニメーション種別
    /// 「なし」）だったか。
    public var isConstant: Bool
    /// 編集開始時点の素材長（エコー尾込み）。
    public var contentLength: TimeSpanValue
    /// 編集開始時点の素材本来の長さ（エコー尾なし）。
    public var originalContentLength: TimeSpanValue
    /// 編集開始時点で、アイテムの長さの終端が区切り
    /// （`contentSeparations`）の ±1 フレーム以内にあったか
    /// （本家 `EditingValue.isLengthOnSeparator`）。分岐 (2) の
    /// 発火条件。直接構築する場合の既定は false（分岐 (2) を
    /// 発火させない側）。
    public var isLengthEndOnSeparator: Bool

    public init(
        firstValue: Double, isConstant: Bool,
        contentLength: TimeSpanValue, originalContentLength: TimeSpanValue,
        isLengthEndOnSeparator: Bool = false
    ) {
        self.firstValue = firstValue
        self.isConstant = isConstant
        self.contentLength = contentLength
        self.originalContentLength = originalContentLength
        self.isLengthEndOnSeparator = isLengthEndOnSeparator
    }
}
