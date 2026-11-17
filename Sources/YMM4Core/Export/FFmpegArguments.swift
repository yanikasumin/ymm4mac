import Foundation

/// FFmpeg 引数の生成（純粋関数群）。
///
/// 本家 `FFmpegVideoFileWriterSettings` の引数解決を再現する:
/// 基礎項目（ビットレート等）→ ユーザーオプション文字列の辞書化 →
/// キー・値の正規化 → 不足分の既定補完、という順序と、各段階の癖
/// （kb 換算の端数処理、キー別名の統合）まで含めて写す。
/// プロセス起動は行わない。実プロセスへの受け渡しは
/// `FFmpegProcessWriter` の薄い層が担う。

// MARK: - 順序付き引数辞書

/// 挿入順序を保持するキー・値辞書。本家の .NET `Dictionary` の
/// 列挙順（追加順）と、既存キーへの代入が位置を保つ振る舞いに対応する。
public struct FFmpegArgumentDictionary: Equatable, Sendable {
    public private(set) var entries: [(key: String, value: String)] = []

    public init() {}

    public static func == (lhs: FFmpegArgumentDictionary, rhs: FFmpegArgumentDictionary) -> Bool {
        guard lhs.entries.count == rhs.entries.count else { return false }
        return zip(lhs.entries, rhs.entries).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }

    public subscript(key: String) -> String? {
        get { entries.first(where: { $0.key == key })?.value }
        set {
            if let newValue {
                if let index = entries.firstIndex(where: { $0.key == key }) {
                    entries[index].value = newValue
                } else {
                    entries.append((key, newValue))
                }
            } else {
                entries.removeAll(where: { $0.key == key })
            }
        }
    }

    public func contains(_ key: String) -> Bool {
        entries.contains(where: { $0.key == key })
    }

    /// 本家 `ArgsDictionaryToString`。値が空なら `-key` のみ、
    /// それ以外は `-key value` を空白で連結する。
    public var argumentString: String {
        entries
            .map { $0.value.isEmpty ? "-\($0.key)" : "-\($0.key) \($0.value)" }
            .joined(separator: " ")
    }

    /// プロセスの argv へ渡すトークン列。値は（空白を含んでも）1要素とする。
    public var argumentTokens: [String] {
        entries.flatMap { entry in
            entry.value.isEmpty ? ["-\(entry.key)"] : ["-\(entry.key)", entry.value]
        }
    }
}

// MARK: - 引数解決

public enum FFmpegArguments {
    /// 本家 `CreateAudioArgsDictionary`。
    public static func audioArgs(settings: FFmpegExportSettings) -> FFmpegArgumentDictionary {
        var base = FFmpegArgumentDictionary()
        if settings.audioBitRate != .none {
            base["b:a"] = "\(settings.audioBitRate.rawValue)k"
        }
        var result = optionsToDictionary(base: base, options: settings.audioOptions, type: "a")
        if !result.contains("c:a") { result["c:a"] = "aac" }
        if !result.contains("f") { result["f"] = "mp4" }
        if !result.contains("loglevel") { result["loglevel"] = "warning" }
        return result
    }

    /// 本家 `CreateVideoArgsDictionary`。
    public static func videoArgs(settings: FFmpegExportSettings) -> FFmpegArgumentDictionary {
        var base = FFmpegArgumentDictionary()
        if settings.videoBitRateMode != .none {
            switch settings.videoBitRateControlMode {
            case .cbr:
                base["b:v"] = "\(settings.videoBitRate)k"
            case .quality:
                let crf = (Double(100 - settings.videoQuality) / 100.0 * 51.0)
                    .rounded(.toNearestOrEven)
                base["crf:v"] = String(Int(crf))
            }
        }
        var result = optionsToDictionary(base: base, options: settings.videoOptions, type: "v")
        if !result.contains("c:v") { result["c:v"] = "h264" }
        if !result.contains("f") { result["f"] = "mp4" }
        if !result.contains("loglevel") { result["loglevel"] = "warning" }
        return result
    }

    /// 本家 `ResolvedVideoArgsString` に対応する解決済み映像引数。
    ///
    /// 本家はここで `FFmpegHardwareEncoder.Apply`（DXGI 列挙と試し
    /// エンコードによるハードウェアエンコーダ解決）を挟む。解決処理は
    /// プラットフォーム依存の実プロセス実行を伴うため、この芯では
    /// 差し替え点として未適用とし、ソフトウェア前提の引数をそのまま返す。
    public static func resolvedVideoArgs(settings: FFmpegExportSettings) -> FFmpegArgumentDictionary {
        videoArgs(settings: settings)
    }

    /// 本家 `OptionsToDictionary`。オプション文字列を " -" で分割し、
    /// 各断片の先頭トークンをキー、残りを値として辞書へ重ね、
    /// 最後にキー・値を正規化する。
    static func optionsToDictionary(
        base: FFmpegArgumentDictionary, options: String, type: String
    ) -> FFmpegArgumentDictionary {
        var dictionary = base
        if !options.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for part in options.components(separatedBy: " -") {
                let trimmed = part
                    .drop(while: { $0 == "-" })
                    .trimmingCharacters(in: .whitespaces)
                let tokens = trimmed.components(separatedBy: " ")
                guard let key = tokens.first, !key.isEmpty else { continue }
                let value = tokens.dropFirst().joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                dictionary[key] = value
            }
        }
        return normalize(dictionary, type: type)
    }

    /// 本家 `NormalizeArgsDictionary`。キー正規化の結果が衝突した場合は
    /// 後の値が勝ち、位置は最初の出現位置に残る（順序付き辞書の代入規則）。
    static func normalize(
        _ dictionary: FFmpegArgumentDictionary, type: String
    ) -> FFmpegArgumentDictionary {
        var result = FFmpegArgumentDictionary()
        for entry in dictionary.entries {
            let key = normalizeKey(entry.key, type: type)
            result[key] = normalizeValue(key: key, value: entry.value)
        }
        return result
    }

    /// 本家 `NormalizeArgKey` の対応表。
    static func normalizeKey(_ key: String, type: String) -> String {
        switch key {
        case "crf": return "crf:\(type)"
        case "b": return "b:\(type)"
        case "aq": return "q:a"
        case "qscale:v": return "q:v"
        case "qscale:a": return "q:a"
        case "qscale": return "q:\(type)"
        case "q": return "q:\(type)"
        case "codec:v": return "c:v"
        case "codec:a": return "c:a"
        case "acodec": return "c:a"
        case "vcodec": return "c:v"
        case "codec": return "c:\(type)"
        case "c": return "c:\(type)"
        case "vframes": return "frames:v"
        case "aframes": return "frames:a"
        case "frames": return "frames:\(type)"
        case "vf": return "filter:v"
        case "af": return "filter:a"
        case "filter": return "filter:\(type)"
        case "vtag": return "tag:v"
        case "atag": return "tag:a"
        case "tag": return "tag:\(type)"
        default: return key
        }
    }

    /// 本家 `NormalizeArgValue`。対象は正規化後の `b:a` / `b:v` のみ。
    static func normalizeValue(key: String, value: String) -> String {
        guard key == "b:a" || key == "b:v" else { return value }
        return normalizeKbString(value)
    }

    /// 本家 `NormalizeKbString` の逐語再現。
    ///
    /// 末尾の "b"（ビット換算フラグ ×8）と "i"（1024 進）の剥がし方、
    /// "i" でない場合にビットフラグが取り消される癖、k/m/g サフィックスの
    /// 1000 進換算、数値として読めない場合は元の文字列を返す点まで含む。
    static func normalizeKbString(_ value: String) -> String {
        let original = value
        var text = value.lowercased()
        var isBits = false
        if text.last == "b" {
            isBits = true
            text.removeLast()
        }
        let base: Double
        if text.last == "i" {
            base = 1024
            text.removeLast()
        } else {
            base = 1000
            isBits = false
        }
        var power = 0
        if let last = text.last {
            switch last {
            case "k": power = 1
            case "m": power = 2
            case "g": power = 3
            default: power = 0
            }
            if power != 0 { text.removeLast() }
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let number = Int(trimmed) else { return original }
        let result = Double((isBits ? 8 : 1) * number) * pow(base, Double(power))
        if result == result.rounded(), abs(result) < 9.0e15 {
            return String(Int(result))
        }
        return String(result)
    }
}

// MARK: - コーデック判定と出力レイアウト

public extension FFmpegArguments {
    /// 本家 `IsYuvCodec`。NV12 化を試みるコーデック名かどうか。
    /// コーデック名に 264 / 265 / hevc / av1 / vp9 / vp8 を含む場合に真。
    static func isYUVCodec(_ codec: String) -> Bool {
        let lowered = codec.lowercased()
        return lowered.contains("264") || lowered.contains("265")
            || lowered.contains("hevc") || lowered.contains("av1")
            || lowered.contains("vp9") || lowered.contains("vp8")
    }
}

/// 一時ファイルと単独出力モードの解決結果（本家コンストラクタの判定）。
public struct FFmpegOutputLayout: Equatable, Sendable {
    /// 音声プロセスの書き込み先（通常は `{file}.audio.tmp`）。
    public var audioTargetPath: String
    /// 映像プロセスの書き込み先（通常は `{file}.video.tmp`）。
    public var videoTargetPath: String
    /// 一時ファイルを使い Dispose で mux するかどうか。
    public var hasTempFiles: Bool
    /// 音声引数に `-f null` があり音声プロセスを起動しないかどうか。
    public var skipsAudioProcess: Bool
    /// 映像引数に `-f null` があり映像を受け取らないかどうか。
    public var skipsVideo: Bool

    /// 本家の判定: 音声側 `f == "null"` なら音声プロセスなし、
    /// 映像側 `f == "null"` なら映像なし。どちらかが単独出力の場合は
    /// 一時ファイルを使わず最終ファイルへ直接書く（W6-4.1.7）。
    /// これは SupportedStreams の申告とは別の「Writer 内部の無効化」
    /// であり、申告値は変えない（W6-C2）。
    public static func resolve(
        outputPath: String,
        audioArgs: FFmpegArgumentDictionary,
        videoArgs: FFmpegArgumentDictionary
    ) -> FFmpegOutputLayout {
        let skipsAudio = audioArgs["f"] == "null"
        let skipsVideo = videoArgs["f"] == "null"
        let hasTempFiles = !skipsAudio && !skipsVideo
        return FFmpegOutputLayout(
            audioTargetPath: hasTempFiles ? outputPath + ".audio.tmp" : outputPath,
            videoTargetPath: hasTempFiles ? outputPath + ".video.tmp" : outputPath,
            hasTempFiles: hasTempFiles,
            skipsAudioProcess: skipsAudio,
            skipsVideo: skipsVideo
        )
    }
}

// MARK: - プロセス引数（コマンドライン生成）

public extension FFmpegArguments {
    /// 音声プロセスの引数（本家コンストラクタの組み立て）。
    /// 標準入力から f32le / 2ch の生 PCM を受ける。
    static func audioProcessArguments(
        settings: FFmpegExportSettings, layout: FFmpegOutputLayout
    ) -> [String] {
        ["-f", "f32le", "-ar", "\(settings.hz)", "-ac", "2", "-i", "-"]
            + audioArgs(settings: settings).argumentTokens
            + ["-y", layout.audioTargetPath]
    }

    /// 映像プロセスの引数（本家 `EnsureVideoStarted` の組み立て）。
    ///
    /// NV12 経路では入力に色空間メタデータ（bt709 / tv レンジ）を
    /// 宣言し、BGRA 経路では色メタデータを一切付けない。
    /// この非対称は本家の確定仕様（W6-4.1.3 / W6-5.3）であり、
    /// 意図的に維持する。
    static func videoProcessArguments(
        settings: FFmpegExportSettings, layout: FFmpegOutputLayout, useNV12: Bool
    ) -> [String] {
        let inputPart: [String]
        if useNV12 {
            inputPart = [
                "-f", "rawvideo", "-pix_fmt", "nv12",
                "-colorspace", "bt709", "-color_primaries", "bt709",
                "-color_trc", "bt709", "-color_range", "tv",
                "-s", "\(settings.width)x\(settings.height)",
                "-r", "\(settings.fps)", "-i", "-",
            ]
        } else {
            inputPart = [
                "-f", "rawvideo", "-pix_fmt", "bgra",
                "-s", "\(settings.width)x\(settings.height)",
                "-r", "\(settings.fps)", "-i", "-",
            ]
        }
        return inputPart
            + resolvedVideoArgs(settings: settings).argumentTokens
            + ["-y", layout.videoTargetPath]
    }

    /// mux プロセスの引数（本家 Dispose の組み立て）。無再エンコード結合。
    static func muxProcessArguments(layout: FFmpegOutputLayout, outputPath: String) -> [String] {
        [
            "-i", layout.audioTargetPath,
            "-i", layout.videoTargetPath,
            "-c", "copy", "-loglevel", "warning",
            "-y", outputPath,
        ]
    }
}
