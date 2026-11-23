import Foundation

/// FFmpeg デコードセッションが供給する映像フレーム1枚（Issue #70 段階2）。
///
/// 画素は 8bit BGRA（行のパディングなし、幅×4 バイト/行）。
/// 時刻は素材の絶対提示時刻（コンテナの開始オフセットを含む。
/// `-copyts` で保持した提示タイムスタンプそのもの）であり、
/// 論理時刻（提示開始位置を 0 とする読み替え）は消費側の責務とする
/// （本家・AVFoundation 経路と同じ分担）。
public struct FFmpegVideoFrame: Sendable {
    /// BGRA 画素データ。大きさは width × height × 4 バイト。
    public var pixelData: Data
    public var width: Int
    public var height: Int
    /// 表示開始時刻（絶対提示時刻）。
    public var presentationStart: TimeSpanValue
    /// 表示終了時刻（絶対提示時刻）。原則として次のフレームの開始
    /// 時刻であり、最終フレームでは素材終端（無ければ開始＋公称
    /// フレーム長）になる。
    public var presentationEnd: TimeSpanValue

    public init(
        pixelData: Data, width: Int, height: Int,
        presentationStart: TimeSpanValue, presentationEnd: TimeSpanValue
    ) {
        self.pixelData = pixelData
        self.width = width
        self.height = height
        self.presentationStart = presentationStart
        self.presentationEnd = presentationEnd
    }

    /// 画素データのバイト数（キャッシュのメモリ上限の計算に使う）。
    public var byteCount: Int { pixelData.count }

    /// 指定時刻（絶対提示時刻）がこのフレームの表示区間
    /// [開始, 終了) に含まれるか。
    public func contains(_ time: TimeSpanValue) -> Bool {
        presentationStart <= time && time < presentationEnd
    }
}

// MARK: - showinfo の時刻項目

/// ffmpeg の `showinfo` フィルタが出力するフレームごとの時刻項目。
///
/// rawvideo のバイト列には提示タイムスタンプが含まれないため、
/// 時刻は showinfo のログ行（標準エラー）から得る。実測
/// （ffmpeg 9.0.2）で確定した形式:
/// `[Parsed_showinfo_0 @ 0x...] n:   0 pts:   3500 pts_time:3.5
///   duration:   33 duration_time:0.033   fmt:...`
/// `pts_time` は小数6桁までの表示（末尾の 0 は省略される）。
///
/// 注意: `duration_time` はコンテナに記録されたフレーム長であり、
/// 実測の VFR 素材では全フレーム一律の値（16ms）になって実際と
/// 食い違った。そのため表示終了時刻には使わず、次のフレームの
/// 開始時刻で決める。ここでは材料として保持だけする。
public struct FFmpegShowinfoTimeEntry: Equatable, Sendable {
    /// 表示開始時刻（秒。絶対提示時刻）。
    public var startSeconds: Double
    /// コンテナ記録のフレーム長（秒）。取れなければ nil。
    /// 表示終了時刻の決定には使わない（上記の注意参照）。
    public var durationSeconds: Double?

    public init(startSeconds: Double, durationSeconds: Double?) {
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
    }
}

/// showinfo のログ行の解析（純粋関数）。
public enum FFmpegShowinfoParser {
    /// 行が showinfo のフレーム行（pts_time を含む）か。
    /// プロセスの標準エラーから証拠用の抜粋を作る際、フレーム行を
    /// 除外する判定にも使う。
    public static func isFrameTimeLine(_ line: String) -> Bool {
        line.contains("showinfo") && line.contains("pts_time:")
    }

    /// フレーム行から時刻項目を取り出す。フレーム行でなければ nil。
    public static func parseTimeEntry(fromLine line: String) -> FFmpegShowinfoTimeEntry? {
        guard isFrameTimeLine(line),
              let start = numberAfterMarker("pts_time:", in: line)
        else { return nil }
        return FFmpegShowinfoTimeEntry(
            startSeconds: start,
            durationSeconds: numberAfterMarker("duration_time:", in: line)
        )
    }

    /// "marker" の直後にある数値トークンを読む。数値として読める
    /// 文字（符号・数字・小数点・指数部）だけを辿る。
    private static func numberAfterMarker(_ marker: String, in line: String) -> Double? {
        guard let range = line.range(of: marker) else { return nil }
        var token = ""
        for character in line[range.upperBound...] {
            if character == " " || character == "\t" { break }
            token.append(character)
        }
        guard !token.isEmpty else { return nil }
        return Double(token)
    }
}
