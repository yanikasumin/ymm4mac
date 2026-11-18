import Foundation

/// 口形。本家 MouthShape（Plugin.Voice）に対応する。
public enum MouthShapeValue: String, Equatable, Sendable {
    case silent
    case a
    case i
    case u
    case e
    case o

    /// 本家の列挙順（Silent=0, A=1, I=2, U=3, E=4, O=5）からの復号。
    public init?(honkeRawValue: Int) {
        switch honkeRawValue {
        case 0: self = .silent
        case 1: self = .a
        case 2: self = .i
        case 3: self = .u
        case 4: self = .e
        case 5: self = .o
        default: return nil
        }
    }

    /// 本家の名前（"Silent" / "A" / ...）からの復号。大文字小文字は
    /// 区別しない。不明な名前は .silent（本家の lab 読み取りの
    /// 既定と同じ倒し方）。
    public init(honkeName: String) {
        switch honkeName.lowercased() {
        case "a": self = .a
        case "i": self = .i
        case "u": self = .u
        case "e": self = .e
        case "o": self = .o
        default: self = .silent
        }
    }
}

/// 口形の時系列1件。本家 LipSyncFrame（Commons）に対応する。
public struct LipSyncFrameValue: Equatable, Sendable {
    /// 声の先頭からの時刻。
    public var time: TimeSpanValue
    public var shape: MouthShapeValue

    public init(time: TimeSpanValue, shape: MouthShapeValue) {
        self.time = time
        self.shape = shape
    }

    /// 保存形式（{Time, Shape} のオブジェクト）から復号する。
    /// Shape は名前文字列と数値の両形式を受ける。
    public static func decode(from value: JSONValue) -> LipSyncFrameValue? {
        guard let timeValue = value.field("Time") else { return nil }
        let time = CodecSupport.timeSpan(timeValue, default: .zero)
        let shape: MouthShapeValue
        if let shapeValue = value.field("Shape") {
            if let name = shapeValue.stringValue {
                shape = MouthShapeValue(honkeName: name)
            } else if let number = shapeValue.doubleValue {
                shape = MouthShapeValue(honkeRawValue: Int(number)) ?? .silent
            } else {
                shape = .silent
            }
        } else {
            shape = .silent
        }
        return LipSyncFrameValue(time: time, shape: shape)
    }

    /// 保存形式の配列から復号する。
    public static func decodeList(from value: JSONValue) -> [LipSyncFrameValue] {
        value.arrayValue?.compactMap { decode(from: $0) } ?? []
    }
}

extension VoiceItem {
    /// 評価用の口形時系列。本家 GetLipSyncFrames と同じく、発音情報
    /// （Pronounce）側に時系列があればそちらを優先し、無ければ
    /// アイテム自身の `LipSyncFrames` を使う。どちらも生 JSON のまま
    /// 保持されているため、評価のたびに復号する（保存形式は変えない）。
    public var evaluatedLipSyncFrames: [LipSyncFrameValue] {
        // 本家は Pronounce 側に LipSyncFrames があれば（空でも）そちらを
        // 採用するため、配列として存在するかを優先の条件にする。
        if let pronounce,
           let framesValue = pronounce.value.field("LipSyncFrames"),
           framesValue.arrayValue != nil {
            return LipSyncFrameValue.decodeList(from: framesValue)
        }
        return LipSyncFrameValue.decodeList(from: lipSyncFrames)
    }

    /// 声の中の位置（フレーム）での口形。本家 TachieSource.GetMouthShape
    /// の規則どおり、アイテム内時刻を素材側の時刻へ変換してから、
    /// その時刻以前の最後の時系列要素の口形を返す（要素が無ければ
    /// .silent）:
    ///
    /// - 時刻変換は再生速度と ContentOffset を反映する。定数速度では
    ///   本家の GetMouthShape の式（(アイテム内時刻 + ContentOffset)
    ///   × 速度 / 100）を、可変速度では PlaybackRateMap の積分を使う
    ///   （R20-116-02）。
    /// - 変換結果が負なら、アイテム長の時刻から差し引いた位置を使う
    ///   （本家の負速度の折り返し）。
    /// - フレーム→tick の換算は本家 FrameTime.FrameToTime と同じ
    ///   AwayFromZero の丸め（R20-116-03）。
    /// - 時系列は整列を前提にせず、条件を満たす最後の要素を選ぶ
    ///   （本家 LastOrDefault と同じ。R20-116-04）。
    public func lipSyncShape(atFrame frame: Int, fps: Int) -> MouthShapeValue {
        guard fps > 0, frame >= 0 else { return .silent }
        let itemTicks = AudioStream.frameToTicks(frame: frame, fps: fps)
        let rateMap = PlaybackRateMap(rate: playbackRate2)
        var sourceTicks: Int64
        if rateMap.isConstant {
            sourceTicks = Int64(
                Double(itemTicks + contentOffset.ticks) * rateMap.firstRate / 100.0
            )
        } else {
            sourceTicks = rateMap.getSourceTime(
                time: TimeSpanValue(ticks: itemTicks),
                itemLength: length, fps: fps,
                contentOffset: contentOffset, contentLength: contentLength
            ).ticks
        }
        if sourceTicks < 0 {
            sourceTicks = AudioStream.frameToTicks(frame: length, fps: fps) - sourceTicks
        }
        var result = MouthShapeValue.silent
        for entry in evaluatedLipSyncFrames where entry.time.ticks <= sourceTicks {
            result = entry.shape
        }
        return result
    }
}
