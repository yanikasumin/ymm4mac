import Foundation

/// タイムラインアイテムの共通基底。本家 `BaseItem` に対応する。
///
/// 本家は参照型（クラス）であり、追加・移動の各操作は「コミット前の
/// 入力アイテム自体の書き換え」を含むため、ここでもクラスとして実装する。
/// アイテムが持つ全 `Animation` へは、キーフレーム集合・長さ・基準 FPS の
/// 文脈を所有アイテムから伝播させる（本家の `SetKeyFrames` /
/// `SetAnimationParameters` に相当）。伝播は `forEachAnimation` の
/// オーバーライドで列挙する。
public class BaseItem {
    /// .ymmp の $type 名（アセンブリ修飾名）。サブクラスが上書きする。
    public class var typeName: String { "" }

    /// グループ番号（0 は無グループ）。
    public var group: Int = 0
    /// 開始フレーム。
    public var frame: Int = 0
    /// レイヤー。
    public var layer: Int = 0
    /// アイテム単位で共有されるキーフレーム位置。
    public var keyFrames: KeyFrames = KeyFrames() {
        didSet { propagateKeyFrames() }
    }
    /// 長さ（フレーム）。
    public var length: Int = 1 {
        didSet { propagateAnimationParameters() }
    }
    /// 再生速度アニメーション。本家 `PlaybackRate2`。
    ///
    /// エコーの尾は先頭値で比例するため、先頭値が変わったら素材長
    /// （エコー尾込み）を再計算する（FE-R27-129-02）。本家は
    /// `ContentLength` の取得のたびに現在の速度で計算するため、
    /// 保持値の追随点をこのプロパティの書き込みへ集約する。
    /// `Animation` は値型であり、直接の変更・記述子経由・
    /// Undo/Redo の適用・デコードのいずれの書き込みもこの setter
    /// を通る。先頭値が変わらない書き込み（キーフレームや文脈の
    /// 伝播等）では再計算しない。再計算の規則自体は
    /// `refreshContentLengthForEchoSettings`（FE-R15-006）に一元化
    /// されている。
    public var playbackRate2: Animation = Animation(defaultValue: 100, minValue: -100_000, maxValue: 100_000) {
        didSet {
            if oldValue.firstValue != playbackRate2.firstValue {
                refreshContentLengthForEchoSettings()
            }
        }
    }
    /// 素材の開始位置オフセット。
    public var contentOffset: TimeSpanValue = .zero
    /// 備考。
    public var remark: String = ""
    /// ロックされているか。
    public var isLocked: Bool = false
    /// 非表示か。
    public var isHidden: Bool = false

    /// モデル化していないプロパティの保存先（読み込み順を保持）。
    /// 保存時にそのまま書き戻す。データ保全のための仕組みであり、
    /// 意味論は持たない。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    /// 評価・分割の基準 FPS（保存対象外。タイムラインから注入される）。
    public var videoFPS: Int = 30
    /// 素材の長さ（保存対象外。本家ではファイルから求める）。
    public var contentLength: TimeSpanValue = .zero
    /// 素材本来の長さ（保存対象外）。
    public var originalContentLength: TimeSpanValue = .zero

    public init() {
        refreshAnimationContext()
    }

    /// 再生速度（%）。本家 `PlaybackRate`（PlaybackRate2 の先頭値への転送）。
    public var playbackRate: Double {
        get { playbackRate2.firstValue }
        set { playbackRate2.setFirstValue(newValue) }
    }

    /// 表示ラベル。本家 `Label`（備考があれば " / 備考" を付ける）。
    public var label: String {
        if remark.isEmpty { return "" }
        return " / " + remark.replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }

    /// 説明文。本家 `Description`。
    public var description: String {
        " / " + remark
    }

    // MARK: - アニメーション文脈の伝播

    /// 所有する全 `Animation` へ処理を適用する。サブクラスは override して
    /// 自分の `Animation` を追加する（必ず super を呼ぶこと）。
    public func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&playbackRate2)
    }

    private func propagateKeyFrames() {
        let keyFrames = self.keyFrames
        forEachAnimation { $0.setKeyFrames(keyFrames) }
    }

    private func propagateAnimationParameters() {
        let length = self.length
        let fps = self.videoFPS
        forEachAnimation { $0.setAnimationParameters(length: length, videoFPS: fps) }
    }

    /// 文脈（キーフレーム・長さ・基準 FPS）を全 `Animation` へ再伝播する。
    public func refreshAnimationContext() {
        propagateKeyFrames()
        propagateAnimationParameters()
    }

    /// 基準 FPS を設定する。本家 `SetFPS`。
    public func setFPS(_ fps: Int) {
        videoFPS = fps
        propagateAnimationParameters()
    }

    /// キーフレーム集合を差し替える（伝播は didSet 経由）。
    public func setKeyFrames(_ keyFrames: KeyFrames) {
        self.keyFrames = keyFrames
    }

    // MARK: - キーフレーム編集（値列の連動つき）

    /// キーフレームを追加する。全 `Animation` へ連動させ、対応する
    /// 値（追加位置での現在値）を値列へ挿入するため、追加前後で
    /// 曲線は変わらない。位置だけを差し替える `setKeyFrames` では
    /// 値列がずれて曲線が変わるため、編集 UI からはこちらを使う。
    ///
    /// - Returns: 追加したら true（範囲外・重複は false）。
    @discardableResult
    public func insertKeyFrame(at frame: Int) -> Bool {
        guard frame >= 0, frame < length, !keyFrames.contains(frame) else {
            return false
        }
        forEachAnimation { $0.insertKeyFrame(at: frame) }
        var updated = keyFrames
        updated.insert(frame)
        keyFrames = updated
        return true
    }

    /// キーフレームを削除する。全 `Animation` へ連動させ、対応する
    /// 値を値列から取り除く。
    ///
    /// - Returns: 削除したら true。
    @discardableResult
    public func removeKeyFrame(at frame: Int) -> Bool {
        guard keyFrames.contains(frame) else { return false }
        forEachAnimation { $0.removeKeyFrame(at: frame) }
        var updated = keyFrames
        updated.remove(frame)
        keyFrames = updated
        return true
    }

    /// 全キーフレームを削除する。全 `Animation` の値列は開始値と
    /// 終了値だけに畳まれる。
    ///
    /// - Returns: 実際に削除・畳み込みが起きたら true。キーフレーム
    ///   が無いアイテムでは false（無変更の操作を編集として扱わ
    ///   ないための判定。FE-R33-131-02）。
    @discardableResult
    public func removeAllKeyFrames() -> Bool {
        var changed = !keyFrames.frames.isEmpty
        forEachAnimation { animation in
            if animation.removeAllKeyFrames() {
                changed = true
            }
        }
        keyFrames = KeyFrames()
        return changed
    }

    /// キーフレームの位置だけを動かす（隣を越えない範囲へ丸める）。
    /// 値はインデックス対応のため動かさない。
    ///
    /// - Returns: 実際に動いたら true。
    @discardableResult
    public func moveKeyFrame(from source: Int, to target: Int) -> Bool {
        guard let index = keyFrames.index(of: source) else { return false }
        let lower = index > 0 ? keyFrames.frames[index - 1] + 1 : 0
        let upper = index + 1 < keyFrames.frames.count
            ? keyFrames.frames[index + 1] - 1 : length - 1
        // アイテム長より後方にキーフレームがある不整合データでは
        // 下限が上限を超える。その場合はアイテム側とアニメーション
        // 側で丸め先が食い違うため、移動を成立させない
        // （R20-114-03。Animation 側の防御と対）。
        guard lower <= upper else { return false }
        let clamped = min(max(target, lower), upper)
        guard clamped != source else { return false }
        forEachAnimation { $0.moveKeyFrame(from: source, to: clamped) }
        var frames = keyFrames.frames
        frames[index] = clamped
        keyFrames = KeyFrames(frames: frames)
        return true
    }

    // MARK: - 位置関係（本家 ItemEx）

    /// フレームを含むか（半開区間 [frame, frame+length)）。
    public func contains(frame target: Int) -> Bool {
        frame <= target && target < frame + length
    }

    /// 区間 [targetFrame, targetFrame+targetLength) と重なるか。
    ///
    /// 本家の条件式は変形されているが、長さ 1 以上の区間では半開区間の
    /// 重なりと等価であることを場合分けで確認した。
    public func intersectsWith(frame targetFrame: Int, length targetLength: Int) -> Bool {
        targetFrame < frame + length && frame < targetFrame + targetLength
    }

    /// 他のアイテムと重なるか。
    public func intersectsWith(_ other: BaseItem) -> Bool {
        intersectsWith(frame: other.frame, length: other.length)
    }

    // MARK: - 編集操作

    /// 編集終了時の長さ調整。本家 `EndEditAsync` のモデル部分。
    /// 最後のキーフレーム + 1 より短くはならない。
    public func endEdit() {
        length = max((keyFrames.frames.last ?? 0) + 1, length)
    }

    /// 分割へのキーフレーム連動（左側を残す）。
    ///
    /// 値の再構築はキーフレーム集合を更新する前に行う（評価は切断前の
    /// 状態で行われるため）。本家 `KeyFrames.RemovesRight` とその
    /// 変更イベントへの `Animation` の反応に相当する。
    public func applyKeyFramesRemovesRight(_ frame: Int) {
        let removedCount = keyFrames.removedCountByRemovingRight(frame)
        forEachAnimation { $0.applyKeyFramesRemovesRight(cutFrame: frame, removedCount: removedCount) }
        keyFrames = keyFrames.removingRight(frame)
    }

    /// 分割へのキーフレーム連動（右側を残す）。本家 `KeyFrames.RemovesLeft`。
    public func applyKeyFramesRemovesLeft(_ frame: Int) {
        let removedCount = keyFrames.removedCountByRemovingLeft(frame)
        forEachAnimation { $0.applyKeyFramesRemovesLeft(cutFrame: frame, removedCount: removedCount) }
        keyFrames = keyFrames.removingLeft(frame)
    }

    /// 指定位置で分割する。本家 `BaseItem.Split(relativeFrame)`。
    ///
    /// 左右とも複製から作る。右側の `ContentOffset` は再生速度が定数なら
    /// 切断位置までの消費分を加算し、非定数なら積分テーブルから求めた
    /// 素材時刻で置き換える（開始レートが負なら反転して測る）。
    public func split(atRelativeFrame relativeFrame: Int) -> (left: BaseItem, right: BaseItem) {
        let left = cloned()
        let right = cloned()
        left.applyKeyFramesRemovesRight(relativeFrame)
        left.length = relativeFrame
        right.applyKeyFramesRemovesLeft(relativeFrame)
        right.frame += relativeFrame
        right.length -= relativeFrame

        let frameTicks = Int64(
            (Double(relativeFrame) * 10_000_000 / Double(videoFPS)).rounded(.awayFromZero)
        )
        let rateMap = PlaybackRateMap(rate: playbackRate2)
        if rateMap.isConstant {
            let scaled = (Double(frameTicks) * abs(playbackRate2.firstValue) / 100.0)
                .rounded(.awayFromZero)
            right.contentOffset = right.contentOffset + TimeSpanValue(ticks: Int64(scaled))
        } else {
            let sourceTime = rateMap.getSourceTime(
                time: TimeSpanValue(ticks: frameTicks),
                itemLength: length, fps: videoFPS,
                contentOffset: contentOffset, contentLength: contentLength
            )
            let rateValue = playbackRate2.value(atFrame: relativeFrame, length: length, fps: videoFPS)
            right.contentOffset = rateValue >= 0 ? sourceTime : contentLength - sourceTime
        }
        return (left, right)
    }

    // MARK: - .ymmp 互換層との接続

    /// 既知プロパティを本家の宣言順に書き出す（$type と追加フィールドは
    /// 互換層が付ける）。サブクラスは override して super の結果へ自分の
    /// プロパティを続ける。
    public func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "Group", value: .number(group)),
            (key: "Frame", value: .number(frame)),
            (key: "Layer", value: .number(layer)),
            (key: "KeyFrames", value: CodecSupport.encodeKeyFrames(keyFrames)),
            (key: "Length", value: .number(length)),
            (key: "PlaybackRate", value: .number(playbackRate)),
            (key: "PlaybackRate2", value: CodecSupport.encodeAnimation(playbackRate2)),
            (key: "ContentOffset", value: .string(contentOffset.honkeString)),
            (key: "Remark", value: .string(remark)),
            (key: "IsLocked", value: .bool(isLocked)),
            (key: "IsHidden", value: .bool(isHidden)),
        ]
    }

    /// 既知プロパティを読み込む。処理したら true、未知のキーなら false
    /// （互換層が追加フィールドとして保持する）。
    public func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "Group":
            group = CodecSupport.int(value, default: group)
        case "Frame":
            frame = CodecSupport.int(value, default: frame)
        case "Layer":
            layer = CodecSupport.int(value, default: layer)
        case "KeyFrames":
            if let decoded = CodecSupport.decodeKeyFrames(value) {
                keyFrames = decoded
            }
        case "Length":
            length = CodecSupport.int(value, default: length)
        case "PlaybackRate":
            playbackRate = CodecSupport.double(value, default: playbackRate)
        case "PlaybackRate2":
            CodecSupport.decodeAnimation(value, into: &playbackRate2)
        case "ContentOffset":
            contentOffset = CodecSupport.timeSpan(value, default: contentOffset)
        case "Remark":
            remark = CodecSupport.string(value, default: remark)
        case "IsLocked":
            isLocked = CodecSupport.bool(value, default: isLocked)
        case "IsHidden":
            isHidden = CodecSupport.bool(value, default: isHidden)
        default:
            return false
        }
        return true
    }
}

/// 映像を持つアイテムの基底。本家 `VisualItem` に対応する。
public class VisualItem: BaseItem {
    /// X 座標。
    public var x: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// Y 座標。
    public var y: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// Z 座標。
    public var z: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// 不透明度（%）。
    public var opacity: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100)
    /// 拡大率（%）。
    public var zoom: Animation = Animation(defaultValue: 100, minValue: 0, maxValue: 100_000)
    /// 回転角。
    public var rotation: Animation = Animation(defaultValue: 0, minValue: -100_000, maxValue: 100_000)
    /// フェードイン（秒）。
    public var fadeIn: Double = 0
    /// フェードアウト（秒）。
    public var fadeOut: Double = 0
    /// 合成方法。
    public var blend: Blend = .normal
    /// 反転するか。
    public var isInverted: Bool = false
    /// 1つ上のオブジェクトで切り抜くか。
    public var isClippingWithObjectAbove: Bool = false
    /// 常に手前に表示するか。
    public var isAlwaysOnTop: Bool = false
    /// Z オーダーを有効にするか。
    public var isZOrderEnabled: Bool = false
    /// 映像エフェクト（意味論はモデル化せず生 JSON で保持）。
    public var videoEffects: [PreservedObject] = []

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        super.forEachAnimation(body)
        body(&x)
        body(&y)
        body(&z)
        body(&opacity)
        body(&zoom)
        body(&rotation)
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        super.encodeKnownFields() + [
            (key: "X", value: CodecSupport.encodeAnimation(x)),
            (key: "Y", value: CodecSupport.encodeAnimation(y)),
            (key: "Z", value: CodecSupport.encodeAnimation(z)),
            (key: "Opacity", value: CodecSupport.encodeAnimation(opacity)),
            (key: "Zoom", value: CodecSupport.encodeAnimation(zoom)),
            (key: "Rotation", value: CodecSupport.encodeAnimation(rotation)),
            (key: "FadeIn", value: .number(fadeIn)),
            (key: "FadeOut", value: .number(fadeOut)),
            (key: "Blend", value: .string(blend.honkeName)),
            (key: "IsInverted", value: .bool(isInverted)),
            (key: "IsClippingWithObjectAbove", value: .bool(isClippingWithObjectAbove)),
            (key: "IsAlwaysOnTop", value: .bool(isAlwaysOnTop)),
            (key: "IsZOrderEnabled", value: .bool(isZOrderEnabled)),
            (key: "VideoEffects", value: .array(videoEffects.map { $0.value })),
        ]
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "X":
            CodecSupport.decodeAnimation(value, into: &x)
        case "Y":
            CodecSupport.decodeAnimation(value, into: &y)
        case "Z":
            CodecSupport.decodeAnimation(value, into: &z)
        case "Opacity":
            CodecSupport.decodeAnimation(value, into: &opacity)
        case "Zoom":
            CodecSupport.decodeAnimation(value, into: &zoom)
        case "Rotation":
            CodecSupport.decodeAnimation(value, into: &rotation)
        case "FadeIn":
            fadeIn = CodecSupport.double(value, default: fadeIn)
        case "FadeOut":
            fadeOut = CodecSupport.double(value, default: fadeOut)
        case "Blend":
            blend = CodecSupport.enumeration(value, default: blend)
        case "IsInverted":
            isInverted = CodecSupport.bool(value, default: isInverted)
        case "IsClippingWithObjectAbove":
            isClippingWithObjectAbove = CodecSupport.bool(value, default: isClippingWithObjectAbove)
        case "IsAlwaysOnTop":
            isAlwaysOnTop = CodecSupport.bool(value, default: isAlwaysOnTop)
        case "IsZOrderEnabled":
            isZOrderEnabled = CodecSupport.bool(value, default: isZOrderEnabled)
        case "VideoEffects":
            videoEffects = CodecSupport.preservedList(value)
        default:
            return super.decodeKnownField(key, value)
        }
        return true
    }
}

/// 映像プロパティ一式。本家 `IVideoItem` に対応する。
///
/// 本家で IVideoItem を実装するのは VisualItem の系譜と VoiceItem /
/// TransitionItem であり、TachieFaceItem は実装しない（IFaceItem のみ）。
/// 適合はこの範囲に一致させること（MAC-0011 で是正）。
/// プロパティの意味と既定値は本家 IVideoItem の定義どおり:
/// X / Y / Z / Opacity / Zoom / Rotation は Animation、
/// FadeIn / FadeOut は秒（double）、Blend は合成方法、
/// IsClippingWithObjectAbove だけが本家では set 可能。
/// VideoEffects は意味論をモデル化せず PreservedObject の生保持とする
/// （既存方針）。
public protocol VideoItemProperties: AnyObject {
    /// X 座標。
    var x: Animation { get }
    /// Y 座標。
    var y: Animation { get }
    /// Z 座標。
    var z: Animation { get }
    /// 不透明度（%）。
    var opacity: Animation { get }
    /// 拡大率（%）。
    var zoom: Animation { get }
    /// 回転角。
    var rotation: Animation { get }
    /// フェードイン（秒）。
    var fadeIn: Double { get }
    /// フェードアウト（秒）。
    var fadeOut: Double { get }
    /// 合成方法。
    var blend: Blend { get }
    /// 反転するか。
    var isInverted: Bool { get }
    /// 1つ上のオブジェクトで切り抜くか。
    var isClippingWithObjectAbove: Bool { get }
    /// 常に手前に表示するか。
    var isAlwaysOnTop: Bool { get }
    /// Z オーダーを有効にするか。
    var isZOrderEnabled: Bool { get }
    /// 映像エフェクト（生 JSON で保持）。
    var videoEffects: [PreservedObject] { get }
}

extension VisualItem: VideoItemProperties {}
