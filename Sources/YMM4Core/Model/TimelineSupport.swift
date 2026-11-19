import Foundation

/// レイヤーごとの設定。本家 `LayerSetting`（レコード）に対応する。
public struct LayerSetting: Equatable, Sendable {
    public var layer: Int
    public var label: String?
    public var color: Color
    public var isHidden: Bool
    public var volume: Double

    public init(
        layer: Int, label: String? = nil, color: Color = .transparent,
        isHidden: Bool = false, volume: Double = 100
    ) {
        self.layer = layer
        self.label = label
        self.color = color
        self.isHidden = isHidden
        self.volume = volume
    }

    func encodeToJSONValue() -> JSONValue {
        .object([
            (key: "Layer", value: .number(layer)),
            (key: "Label", value: label.map(JSONValue.string) ?? .null),
            (key: "Color", value: .string(color.honkeString)),
            (key: "IsHidden", value: .bool(isHidden)),
            (key: "Volume", value: .number(volume)),
        ])
    }

    static func decode(from value: JSONValue) -> LayerSetting? {
        guard value.objectFields != nil else { return nil }
        var setting = LayerSetting(layer: 0)
        setting.layer = CodecSupport.int(value.field("Layer"), default: 0)
        if let labelValue = value.field("Label"), labelValue != .null {
            setting.label = labelValue.stringValue
        }
        setting.color = CodecSupport.color(value.field("Color"), default: .transparent)
        setting.isHidden = CodecSupport.bool(value.field("IsHidden"), default: false)
        setting.volume = CodecSupport.double(value.field("Volume"), default: 100)
        return setting
    }
}

/// レイヤー設定の集合。本家 `LayerSettings` に対応する。
///
/// 保存されるのは `Items` のみ。挿入は本家 `Insert` の意味論どおり、
/// 指定レイヤー以上の既存設定を1つずつ後ろへずらしてから末尾へ追加する。
public final class LayerSettings {
    public var items: [LayerSetting] = []

    public init() {}

    /// 指定レイヤーの設定（無ければ既定値で新規作成したもの）。
    public func setting(forLayer layer: Int) -> LayerSetting {
        items.first(where: { $0.layer == layer }) ?? LayerSetting(layer: layer)
    }

    /// 本家 `Insert`。指定レイヤー以上の設定を後ろへずらし、末尾へ追加する。
    public func insert(_ setting: LayerSetting) {
        var result = items.filter { $0.layer < setting.layer }
        result += items.filter { $0.layer >= setting.layer }.map { existing in
            var shifted = existing
            shifted.layer += 1
            return shifted
        }
        result.append(setting)
        items = result
    }

    func encodeToJSONValue() -> JSONValue {
        .object([
            (key: "Items", value: .array(items.map { $0.encodeToJSONValue() })),
        ])
    }

    static func decode(from value: JSONValue) -> LayerSettings {
        let settings = LayerSettings()
        if let elements = value.field("Items")?.arrayValue {
            settings.items = elements.compactMap { LayerSetting.decode(from: $0) }
        }
        return settings
    }
}

/// タイムラインの補助線設定。本家 `TimelineVerticalLine` に対応する。
///
/// 線そのもの（`Line`）はインタフェース型のため生 JSON で保持する。
/// `LineType` を変えると線は種類ごとの既定インスタンスへ差し替わる
/// （本家の setter の挙動）。ただし差し替えは種別が実際に変わる場合
/// だけに限る — 本家の setter は無条件に差し替えるが、同じ種別への
/// 代入で差し替えると、読み込んだ線オブジェクトの未知フィールドが
/// 失われるため、往復保全を優先する（FE-R35-132-02）。
public struct TimelineVerticalLine: Sendable {
    /// 補助線が有効か。
    public var isEnabled: Bool = false
    /// 開始フレーム。
    public var startFrame: Int = 0
    /// 線（$type を含む生 JSON）。
    public var line: PreservedObject = TimelineVerticalLine.defaultLine(for: .bpm)
    /// グループ番号（本家の既定は 4）。
    public var group: Int = 4
    /// モデル化していないプロパティの保存先。
    public var additionalFields: [(key: String, value: JSONValue)] = []

    public init() {}

    /// 線の種類。現在の `Line` の $type から判定する。
    public var lineType: VerticalLineType {
        get {
            guard let typeName = line.typeName else { return .bpm }
            if typeName.hasPrefix("YukkuriMovieMaker.Project.VerticalFrameLine") { return .frame }
            if typeName.hasPrefix("YukkuriMovieMaker.Project.VerticalTimeLine") { return .time }
            return .bpm
        }
        set {
            // 種別が変わる場合だけ差し替える（FE-R35-132-02）。
            guard newValue != lineType else { return }
            line = Self.defaultLine(for: newValue)
        }
    }

    /// 種類ごとの既定の線（本家の各クラスのフィールド初期値どおり）。
    public static func defaultLine(for type: VerticalLineType) -> PreservedObject {
        let assembly = "YukkuriMovieMaker.Plugin"
        switch type {
        case .frame:
            return PreservedObject(.object([
                (key: "$type", value: .string("YukkuriMovieMaker.Project.VerticalFrameLine, \(assembly)")),
                (key: "Frame", value: .number(30)),
            ]))
        case .time:
            return PreservedObject(.object([
                (key: "$type", value: .string("YukkuriMovieMaker.Project.VerticalTimeLine, \(assembly)")),
                (key: "Span", value: .string("00:00:00.5000000")),
            ]))
        default:
            return PreservedObject(.object([
                (key: "$type", value: .string("YukkuriMovieMaker.Project.VerticalBPMLine, \(assembly)")),
                (key: "BPM", value: .number(100.0)),
            ]))
        }
    }

    func encodeToJSONValue() -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            (key: "IsEnabled", value: .bool(isEnabled)),
            (key: "StartFrame", value: .number(startFrame)),
            (key: "LineType", value: .string(lineType.honkeName)),
            (key: "Line", value: line.value),
            (key: "Group", value: .number(group)),
        ]
        fields += additionalFields
        return .object(fields)
    }

    static func decode(from value: JSONValue) -> TimelineVerticalLine {
        var verticalLine = TimelineVerticalLine()
        guard let fields = value.objectFields else { return verticalLine }
        for (key, fieldValue) in fields {
            switch key {
            case "IsEnabled":
                verticalLine.isEnabled = CodecSupport.bool(fieldValue, default: false)
            case "StartFrame":
                verticalLine.startFrame = CodecSupport.int(fieldValue, default: 0)
            case "LineType":
                // 本家の setter は線を既定インスタンスへ差し替える。
                // 続く Line キーが実際の線で上書きする（本家の復元順と同じ）。
                if let name = fieldValue.stringValue {
                    verticalLine.lineType = VerticalLineType(honkeName: name)
                }
            case "Line":
                if let preserved = CodecSupport.preservedObject(fieldValue) {
                    verticalLine.line = preserved
                }
            case "Group":
                verticalLine.group = CodecSupport.int(fieldValue, default: 4)
            default:
                verticalLine.additionalFields.append((key: key, value: fieldValue))
            }
        }
        return verticalLine
    }
}

extension TimelineVerticalLine {
    // MARK: - 線のパラメータ（保持 JSON の読み書き）

    /// 保持している線オブジェクトのフィールドを読む。
    private func lineField(_ key: String) -> JSONValue? {
        line.value.field(key)
    }

    /// 保持している線オブジェクトのフィールドを書き換える。
    /// $type や他のフィールドはそのまま残す（往復保全）。
    private mutating func setLineField(_ key: String, _ newValue: JSONValue) {
        guard case .object(var fields) = line.value else { return }
        if let index = fields.firstIndex(where: { $0.key == key }) {
            fields[index].value = newValue
        } else {
            fields.append((key: key, value: newValue))
        }
        line = PreservedObject(.object(fields))
    }

    /// BPM（種別が BPM のときのみ意味を持つ。本家 VerticalBPMLine.BPM）。
    public var bpm: Double {
        get {
            guard lineType == .bpm else { return 100 }
            return lineField("BPM")?.doubleValue ?? 100
        }
        set {
            guard lineType == .bpm else { return }
            setLineField("BPM", .number(newValue))
        }
    }

    /// フレーム間隔（種別が Frame のときのみ意味を持つ。
    /// 本家 VerticalFrameLine.Frame）。
    public var frameInterval: Int {
        get {
            guard lineType == .frame else { return 30 }
            return lineField("Frame")?.intValue ?? 30
        }
        set {
            guard lineType == .frame else { return }
            setLineField("Frame", .number(newValue))
        }
    }

    /// 時間間隔（tick = 100ns。種別が Time のときのみ意味を持つ。
    /// 本家 VerticalTimeLine.Span。保持形式は .NET の TimeSpan 文字列）。
    public var spanTicks: Int64 {
        get {
            guard lineType == .time else { return 5_000_000 }
            guard let text = lineField("Span")?.stringValue,
                  let ticks = Self.ticks(fromTimeSpanString: text)
            else { return 5_000_000 }
            return ticks
        }
        set {
            guard lineType == .time else { return }
            setLineField("Span", .string(Self.timeSpanString(fromTicks: newValue)))
        }
    }

    // MARK: - .NET TimeSpan 文字列との変換

    /// .NET の TimeSpan 文字列（"c" 形式: [-][d.]hh:mm:ss[.fffffff]）を
    /// tick へ変換する。UI の入力便宜として "mm:ss" と裸の秒数も受ける
    /// （裸の数値は .NET の TimeSpan.Parse では日数扱いだが、ここでは
    /// 秒として解釈する。保存時は常に正規形式で書き戻す）。
    public static func ticks(fromTimeSpanString text: String) -> Int64? {
        var body = text.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        var sign: Int64 = 1
        if body.hasPrefix("-") {
            sign = -1
            body.removeFirst()
        } else if body.hasPrefix("+") {
            body.removeFirst()
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        var days: Int64 = 0
        var hours: Int64 = 0
        var minutes: Int64 = 0
        var secondsText: Substring
        func intPart(_ s: Substring) -> Int64? {
            guard !s.isEmpty, s.allSatisfy({ $0.isNumber }) else { return nil }
            return Int64(s)
        }
        switch parts.count {
        case 3:
            // 先頭要素は "hh" または "d.hh"。
            let head = parts[0]
            if let dot = head.firstIndex(of: ".") {
                guard let d = intPart(head[..<dot]),
                      let h = intPart(head[head.index(after: dot)...])
                else { return nil }
                days = d
                hours = h
            } else {
                guard let h = intPart(head) else { return nil }
                hours = h
            }
            guard let m = intPart(parts[1]) else { return nil }
            minutes = m
            secondsText = parts[2]
        case 2:
            guard let m = intPart(parts[0]) else { return nil }
            minutes = m
            secondsText = parts[1]
        case 1:
            secondsText = parts[0]
        default:
            return nil
        }
        var seconds: Int64 = 0
        var fractionTicks: Int64 = 0
        if let dot = secondsText.firstIndex(of: ".") {
            guard let s = intPart(secondsText[..<dot]) else { return nil }
            seconds = s
            let frac = secondsText[secondsText.index(after: dot)...]
            guard !frac.isEmpty, frac.count <= 7,
                  frac.allSatisfy({ $0.isNumber })
            else { return nil }
            var padded = String(frac)
            while padded.count < 7 { padded += "0" }
            guard let f = Int64(padded) else { return nil }
            fractionTicks = f
        } else {
            guard let s = intPart(secondsText) else { return nil }
            seconds = s
        }
        // 合成と tick 換算はオーバーフローを検査して行う。各要素が
        // Int64 に収まっていても、合計や換算結果が収まらない入力が
        // あり、通常の整数演算では実行時トラップになる（利用者の
        // 任意入力からアプリが異常終了し得る。FE-R35-132-01）。
        // 表現できない入力は nil を返し、シート側のエラー表示へ戻す。
        func term(_ value: Int64, _ factor: Int64) -> Int64? {
            let result = value.multipliedReportingOverflow(by: factor)
            return result.overflow ? nil : result.partialValue
        }
        func sum(_ lhs: Int64, _ rhs: Int64) -> Int64? {
            let result = lhs.addingReportingOverflow(rhs)
            return result.overflow ? nil : result.partialValue
        }
        guard let daySeconds = term(days, 86_400),
              let hourSeconds = term(hours, 3_600),
              let minuteSeconds = term(minutes, 60),
              let partial = sum(daySeconds, hourSeconds),
              let partial2 = sum(partial, minuteSeconds),
              let totalSeconds = sum(partial2, seconds),
              let totalTicks = term(totalSeconds, 10_000_000),
              let magnitude = sum(totalTicks, fractionTicks)
        else { return nil }
        return sign * magnitude
    }

    /// tick を .NET の TimeSpan 文字列（"c" 形式）へ変換する。
    /// 小数部がある場合は7桁ちょうどで出す（本家の保存例
    /// "00:00:00.5000000" と同じ形）。
    public static func timeSpanString(fromTicks ticks: Int64) -> String {
        let sign = ticks < 0 ? "-" : ""
        // abs は Int64.min でトラップするため、符号なしの大きさ
        // （magnitude）で割り算を行う（FE-R35-132-01）。
        let absolute = ticks.magnitude
        let totalSeconds = absolute / 10_000_000
        let fraction = absolute % 10_000_000
        let days = totalSeconds / 86_400
        let hours = (totalSeconds / 3_600) % 24
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        func two(_ v: UInt64) -> String { v < 10 ? "0\(v)" : "\(v)" }
        var result = sign
        if days > 0 { result += "\(days)." }
        result += "\(two(hours)):\(two(minutes)):\(two(seconds))"
        if fraction != 0 {
            var frac = "\(fraction)"
            while frac.count < 7 { frac = "0" + frac }
            result += ".\(frac)"
        }
        return result
    }

    // MARK: - 線の位置計算（本家 GetLineFrames / UpdateLines）

    /// 線の列挙パラメータ（列挙開始位置から導いた通し番号の起点、
    /// 通し番号→フレームの変換、通し番号1つ当たりの理論上の
    /// フレーム間隔）。種別が無効・間隔不正なら nil。
    ///
    /// `framesPerIndex` は種別パラメータから直接導く丸め前の間隔で、
    /// `frameAt` の丸め結果から逆算した値ではない。高 BPM のように
    /// 複数の通し番号が同一フレームへ丸められる条件では、丸め後の
    /// 最初の異なるフレーム間隔（1フレーム）は理論間隔（1フレーム
    /// 未満）より大きく見え、間引き係数の根拠に使うと係数が過小に
    /// なる（FE-R36-132-01）。
    private func lineSequence(
        videoInfo: VideoInfo, enumerateFrom: Int
    ) -> (startIndex: Int, frameAt: (Int) -> Int, framesPerIndex: Double)? {
        let fps = videoInfo.fps
        switch lineType {
        case .frame:
            let interval = frameInterval
            guard interval > 0 else { return nil }
            return (
                startIndex: (enumerateFrom - startFrame) / interval,
                frameAt: { $0 * interval + startFrame },
                framesPerIndex: Double(interval)
            )
        case .bpm:
            let value = bpm
            guard value > 0, fps > 0 else { return nil }
            let beats = FrameTime.time(fromFrame: enumerateFrom - startFrame, fps: fps)
                * value / 60
            return (
                startIndex: Int(beats.rounded(.down)),
                frameAt: { FrameTime.frame(from: Double($0) * 60 / value, fps: fps) + startFrame },
                framesPerIndex: 60 * Double(fps) / value
            )
        case .time:
            let ticks = spanTicks
            guard ticks > 0, fps > 0 else { return nil }
            let spanSeconds = Double(ticks) / 10_000_000
            let spans = FrameTime.time(fromFrame: enumerateFrom - startFrame, fps: fps)
                / spanSeconds
            return (
                startIndex: Int(spans.rounded(.down)),
                frameAt: { FrameTime.frame(from: spanSeconds * Double($0), fps: fps) + startFrame },
                framesPerIndex: spanSeconds * Double(fps)
            )
        case .unknown:
            return nil
        }
    }

    /// 線を引くフレームと、その通し番号（グループ判定用）。
    /// 本家 IVerticalLine.GetLineFrames の意味論: 列挙開始位置から
    /// 導いた通し番号を起点に無限に列挙し、フレーム 0 は除き、
    /// `throughFrame` を超えたら止める。
    public func lineFrames(
        videoInfo: VideoInfo, enumerateFrom: Int, throughFrame: Int
    ) -> [(index: Int, frame: Int)] {
        guard let sequence = lineSequence(
            videoInfo: videoInfo, enumerateFrom: enumerateFrom
        ) else { return [] }
        var result: [(index: Int, frame: Int)] = []
        var index = sequence.startIndex
        // 本家は無限列挙だが、異常値で暴走しないよう上限を置く。
        // 丸めで同じフレームが続く場合は、本家では同じ位置へ重ねて
        // 描かれるだけなので、連続する重複は1本にまとめる。
        for _ in 0..<100_000 {
            let frame = sequence.frameAt(index)
            if frame > throughFrame { break }
            if frame != 0, result.last?.frame != frame {
                result.append((index: index, frame: frame))
            }
            index += 1
        }
        return result
    }

    /// 実際に表示する線（本家 TimelineVerticalLinesViewModel.UpdateLines
    /// の間引きまで含む）。線の間隔が 10px 未満なら、グループ数の
    /// 冪で通し番号を間引く（グループが1以下なら全て消える）。
    /// サブ線はグループで割り切れない通し番号の線。
    ///
    /// 列挙方式（FE-R35-132-03）: 間引き後の表示間隔を先に決め、
    /// 選ばれる通し番号だけを列挙する。以前は候補を最大100,000本
    /// 列挙してから間引いていたため、広域表示（低倍率）では候補の
    /// 列挙が可視範囲の途中で打ち切られ、右側に線が生成されなかった。
    /// この方式では列挙量が実際の表示線数に見合う量になる。
    ///
    /// 間引き係数の根拠（FE-R36-132-01）: 係数は、丸め後の先頭2本の
    /// 実間隔ではなく、通し番号1つ当たりの理論上のフレーム間隔
    /// （`lineSequence` の `framesPerIndex`）から決める。丸め後の
    /// 実間隔は、複数の通し番号が同一フレームへ丸められる条件
    /// （高 BPM・極短い時間間隔）で理論間隔より大きく出るため、
    /// 係数が過小になり、間引き後も線が過密になっていた。
    ///
    /// 生成手順（FE-R37-132-01）: 表示線は、理論間隔で選んだ
    /// 通し番号から直接生成する。以前は生成前に「先頭2本の異なる
    /// 線」を探索し、2本未満なら探索結果をそのまま返す短絡判定が
    /// あったが、この探索は通し番号を最大100,000個まで1つずつ
    /// 進めるため、理論間隔が極端に小さい条件（時間間隔100nsでは
    /// 100,000個進めても約0.3フレーム）では2本目に到達できず、
    /// 実際には線が存在するのに空を返していた。範囲内に線が
    /// 無いかどうかは、選択後の列挙結果が空かで判断する。
    public func displayLines(
        videoInfo: VideoInfo, enumerateFrom: Int, throughFrame: Int,
        pxPerFrame: Double
    ) -> [(frame: Int, isSubLine: Bool)] {
        guard isEnabled else { return [] }
        guard let sequence = lineSequence(
            videoInfo: videoInfo, enumerateFrom: enumerateFrom
        ) else { return [] }
        func isSub(_ index: Int) -> Bool {
            group != 0 && index % group != 0
        }
        // 間引き係数は理論間隔から決める（FE-R36-132-01）。
        let spacing = sequence.framesPerIndex * pxPerFrame
        guard spacing > 0 else { return [] }
        var divisor = 1
        if spacing < 10 {
            guard group > 1 else { return [] }
            let n = Int((log(10 / spacing) / log(Double(group))).rounded(.up))
            if n > 0 {
                for _ in 0..<n {
                    // 理論間隔が極端に小さいと必要な冪が大きくなる。
                    // 1ステップで可視範囲をはるかに超える大きさに
                    // なれば、それ以上掛けても結果は変わらないため、
                    // オーバーフローする手前で打ち切る。
                    let (next, overflow) = divisor
                        .multipliedReportingOverflow(by: group)
                    if overflow { break }
                    divisor = next
                }
            }
        }
        // 選ばれる通し番号（divisor で割り切れるもの）だけを、
        // 列挙開始位置以降の最初の該当番号から列挙する。
        var result: [(frame: Int, isSubLine: Bool)] = []
        var selected = sequence.startIndex
        if divisor > 1 {
            selected += (divisor - selected % divisor) % divisor
        }
        while true {
            let frame = sequence.frameAt(selected)
            if frame > throughFrame { break }
            if frame != 0, result.last?.frame != frame {
                result.append((frame: frame, isSubLine: isSub(selected)))
            }
            selected += divisor
        }
        return result
    }
}

/// ツールの保存状態。本家 `SerializableToolState`（レコード）に対応する。
public struct SerializableToolState: Equatable, Sendable {
    public var title: String
    public var savedState: String?

    public init(title: String, savedState: String? = nil) {
        self.title = title
        self.savedState = savedState
    }

    func encodeToJSONValue() -> JSONValue {
        .object([
            (key: "Title", value: .string(title)),
            (key: "SavedState", value: savedState.map(JSONValue.string) ?? .null),
        ])
    }

    static func decode(from value: JSONValue) -> SerializableToolState? {
        guard value.objectFields != nil else { return nil }
        var state = SerializableToolState(title: "")
        state.title = CodecSupport.string(value.field("Title"), default: "")
        if let savedValue = value.field("SavedState"), savedValue != .null {
            state.savedState = savedValue.stringValue
        }
        return state
    }
}
