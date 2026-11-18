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
    /// と同じく、その時刻以前の最後の時系列要素の口形を返し、要素が
    /// 無ければ .silent。
    public func lipSyncShape(atFrame frame: Int, fps: Int) -> MouthShapeValue {
        guard fps > 0, frame >= 0 else { return .silent }
        let ticks = Int64(frame) * 10_000_000 / Int64(fps)
        var result = MouthShapeValue.silent
        for entry in evaluatedLipSyncFrames {
            if entry.time.ticks <= ticks {
                result = entry.shape
            } else {
                break
            }
        }
        return result
    }
}
