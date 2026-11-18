#if os(macOS)
import Compression
import Foundation
import YMM4Core

/// VoiceItem の音声供給（Issue #51）。
///
/// 本家の供給経路（`VoiceItem.cs` 実コードで確認）:
/// - `CreateAudioSource(Scene)` は `AudioSource(FilePath, 0)` を返し、
///   通常のファイルデコード経路（`AudioFileSourceFactory`）で開く。
/// - `FilePath`（保存対象外の計算プロパティ）は
///   `voiceFile?.FullName ?? customVoiceFilePath`。
///   `voiceFile` は音声合成エンジンが生成した一時ファイル、または
///   `VoiceCache` から復元した一時ファイル。`VoiceCache` は音声ファイル
///   全体を Brotli 圧縮して .ymmp 内に base64 で保持したもの
///   （`CreateVoiceCacheAsync` / `CreateVoiceFileFromCacheAsync`）。
///   `customVoiceFilePath` は、発音記号列（Hatsuon）がカスタム音声
///   ファイルのパスである場合にそのパス自体が入る
///   （`IsCustomVoice` で判定し、`CreateVoiceFileAsync` が設定する）。
///
/// Mac 版には音声合成エンジンが無いため、エンジン生成そのものは
/// 対象外とし、プロジェクトに既に存在する音声（VoiceCache と
/// カスタム音声ファイル）を、本家と同じく通常のファイルデコード
/// 経路（`PCMProviderFactory`）へ供給する接続を実装する。
/// どちらも無い VoiceItem は本家で生成前に相当し、無音になる。
public final class VoicePCMProviderResolver {
    private let providerFactory: any PCMProviderFactory

    public init(providerFactory: any PCMProviderFactory) {
        self.providerFactory = providerFactory
    }

    /// VoiceItem の PCM 供給元を解決する。供給できる音声が無ければ nil
    /// （呼び出し側の `FileAudioStream` が無音へ倒す）。
    ///
    /// 解決順は本家 `CreateVoiceFileAsync` の分岐順に合わせる:
    /// カスタム音声 → VoiceCache の順（本家では両者は排他で、カスタム
    /// 音声のときはキャッシュを生成・使用しない）。
    public func provider(for item: VoiceItem) -> PCMProvider? {
        if Self.isCustomVoicePath(item.hatsuon) {
            return providerFactory.createProvider(
                filePath: item.hatsuon, audioTrackIndex: 0
            )
        }
        if let cache = item.voiceCache, !cache.isEmpty,
           let fileData = BrotliDecompression.decompress(cache) {
            return providerFromTemporaryFile(data: fileData)
        }
        return nil
    }

    /// `AudioSourceFactory.voiceProviderResolver` へ渡すクロージャ。
    /// クロージャが resolver 自身を保持する。
    public func makeResolver() -> (VoiceItem) -> PCMProvider? {
        { [self] item in provider(for: item) }
    }

    /// 解凍済みの音声ファイルデータを一時ファイル経由でデコードする。
    ///
    /// 本家は拡張子を持たない一時ファイル（`TemporaryFile` の既定は
    /// "tmp"）に書き出して MediaFoundation の内容判定で開くが、
    /// AVFoundation は拡張子から形式を推定するため開けない（実測:
    /// 中身が WAV の .tmp ファイルは "Cannot Open" になる）。Mac 版の
    /// 適応として、先頭バイトから形式を推定して拡張子を付ける。
    ///
    /// 所有権: 一時ファイルはこのメソッドの中だけで使い、デコードが
    /// 終われば削除する。これは現行の `PCMProviderFactory` 実装
    /// （`AVFoundationPCMProviderFactory`）がファイルを全体デコード
    /// してメモリ上の供給元を返す方式であることに依存する。
    private func providerFromTemporaryFile(data: Data) -> PCMProvider? {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ymm4-voice-\(UUID().uuidString)")
            .appendingPathExtension(Self.detectedFileExtension(for: data))
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: fileURL) }
        return providerFactory.createProvider(
            filePath: fileURL.path, audioTrackIndex: 0
        )
    }

    /// 音声ファイルの先頭バイトから形式を推定し、拡張子を返す。
    /// 推定できない場合は "tmp"（開けなければ無音に倒れる）。
    static func detectedFileExtension(for data: Data) -> String {
        func hasMagic(_ magic: [UInt8], at offset: Int = 0) -> Bool {
            guard data.count >= offset + magic.count else { return false }
            return data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return false }
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                for index in magic.indices where bytes[offset + index] != magic[index] {
                    return false
                }
                return true
            }
        }
        // RIFF ("RIFF"...."WAVE")
        if hasMagic([0x52, 0x49, 0x46, 0x46]), hasMagic([0x57, 0x41, 0x56, 0x45], at: 8) {
            return "wav"
        }
        // ID3 タグ、または MPEG オーディオのフレーム同期 (0xFF 0xEx)
        if hasMagic([0x49, 0x44, 0x33])
            || (data.count >= 2 && data[0] == 0xFF && (data[1] & 0xE0) == 0xE0) {
            return "mp3"
        }
        // Ogg コンテナ ("OggS")
        if hasMagic([0x4F, 0x67, 0x67, 0x53]) {
            return "ogg"
        }
        // FLAC ("fLaC")
        if hasMagic([0x66, 0x4C, 0x61, 0x43]) {
            return "flac"
        }
        // ISO BMFF ("ftyp" がオフセット 4)
        if hasMagic([0x66, 0x74, 0x79, 0x70], at: 4) {
            return "m4a"
        }
        // AIFF ("FORM")
        if hasMagic([0x46, 0x4F, 0x52, 0x4D]) {
            return "aiff"
        }
        return "tmp"
    }

    /// 本家 `VoiceItem.IsCustomVoice` の再現: 発音記号列が絶対ファイル
    /// パスとして解釈でき、拡張子が音声分類に含まれる場合にカスタム
    /// 音声とみなす。
    ///
    /// 本家は `Uri.TryCreate(hatsuon, UriKind.Absolute)` の `IsFile` で
    /// 判定するため、Windows のドライブパス（`C:\...`）もファイル
    /// パスとして成立する。Mac 上ではその実体が存在しないため、判定を
    /// 通過してもデコード側が nil を返して無音になる（他の Windows
    /// パス素材と同じ扱い）。
    static func isCustomVoicePath(_ hatsuon: String) -> Bool {
        guard !hatsuon.isEmpty else { return false }
        let isAbsoluteFile: Bool
        if let url = URL(string: hatsuon), url.isFileURL {
            isAbsoluteFile = true
        } else if hatsuon.hasPrefix("/") {
            isAbsoluteFile = true
        } else if hatsuon.count >= 2,
                  hatsuon[hatsuon.index(after: hatsuon.startIndex)] == ":",
                  hatsuon.first?.isLetter == true {
            // Windows ドライブパス（C:\... / C:/...）
            isAbsoluteFile = true
        } else {
            isAbsoluteFile = false
        }
        guard isAbsoluteFile else { return false }
        let pathExtension = (hatsuon as NSString).pathExtension.lowercased()
        return audioFileExtensions.contains(pathExtension)
    }

    /// 本家のファイル拡張子分類（`FileExtensions.GetDefaultExtentions`）
    /// で「音声」に分類される拡張子。音声分類は動画コンテナ全種を
    /// 含む（動画ファイルの音声だけを使うため）。根拠は解析側
    /// MEDIA-IO-FACTS §8.2。
    static let audioFileExtensions: Set<String> = [
        // 動画コンテナ
        "mp4", "avi", "wmv", "3g2", "3gp", "3gp2", "3gpp", "m4v", "mov",
        "qt", "m2ts", "m2t", "mts", "ts", "mkv", "mpg", "mpeg", "webm",
        "gif", "webp",
        // 音声
        "mp3", "wav", "wma", "m4a", "mka", "aac", "adts", "flac", "ogg",
        "mid", "midi",
    ]
}

/// Brotli 解凍。`VoiceCache` は .NET の `BrotliStream` が書いた
/// raw Brotli ストリーム（RFC 7932）であり、Compression
/// フレームワークの `COMPRESSION_BROTLI` で解凍できる
/// （Google 公式実装で圧縮したデータとの相互運用を実測で確認済み）。
/// 失敗時は nil。
enum BrotliDecompression {
    static func decompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPointer.deallocate() }
        guard compression_stream_init(
            streamPointer, COMPRESSION_STREAM_DECODE, COMPRESSION_BROTLI
        ) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(streamPointer) }

        var output = Data()
        let chunkSize = 64 * 1024
        var destinationBuffer = [UInt8](repeating: 0, count: chunkSize)

        return data.withUnsafeBytes { (sourceRaw: UnsafeRawBufferPointer) -> Data? in
            guard let sourceBase = sourceRaw.baseAddress else { return nil }
            streamPointer.pointee.src_ptr = sourceBase.assumingMemoryBound(to: UInt8.self)
            streamPointer.pointee.src_size = data.count
            while true {
                let status: compression_status = destinationBuffer
                    .withUnsafeMutableBufferPointer { destination in
                        streamPointer.pointee.dst_ptr = destination.baseAddress!
                        streamPointer.pointee.dst_size = chunkSize
                        // 入力を全て渡し終えたら finalize して残りを
                        // 吐き出させる。
                        let flags: Int32 = streamPointer.pointee.src_size == 0
                            ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
                        return compression_stream_process(streamPointer, flags)
                    }
                let produced = chunkSize - streamPointer.pointee.dst_size
                if produced > 0 {
                    output.append(contentsOf: destinationBuffer[0..<produced])
                }
                switch status {
                case COMPRESSION_STATUS_END:
                    return output
                case COMPRESSION_STATUS_OK:
                    continue
                default:
                    return nil
                }
            }
        }
    }
}
#endif
