import Foundation

/// WAV（RIFF）ファイルへの逐次書き出し。本家 `WavFileWriter`
/// （YukkuriMovieMaker.Commons）の形式仕様を再現する:
///
/// - ヘッダは 44 バイト固定（fmt チャンク 16 バイト、追加チャンクなし）。
///   生成時点では RIFF サイズと data サイズに 0 を書き、確定時
///   （`finalize()`）に実位置から埋め直す（RIFF サイズ = 位置 − 8、
///   data サイズ = 位置 − 44）。
/// - 書き込み可能サンプル数の残量は
///   `(上限バイト数 − 現在位置) / depth` で数える。本家の上限は
///   `int.MaxValue`（RIFF のサイズ欄が 32 ビットであるため）で、
///   depth はビット数（32）そのもので割る本家の式をそのまま使う。
///   上限は初期化引数で差し替え可能にしてあるが、これは分割挙動を
///   テスト可能にするための差し替え点であり、既定値は本家どおり。
///
/// 所有権: ファイルハンドルはこのインスタンスが所有し、`finalize()`
/// で閉じる。`finalize()` を呼ばずに破棄された場合は deinit で
/// 最善努力の確定を行う（サイズ欄が 0 のまま残ることを防ぐ）。
public final class WavFileWriter {
    /// WAVE フォーマットタグ: PCM。
    public static let formatPCM = 1
    /// WAVE フォーマットタグ: IEEE float。
    public static let formatIEEEFloat = 3

    private let handle: FileHandle
    private let depth: Int
    private let byteLimit: Int
    /// ここまでに書き込んだバイト数（ヘッダ 44 バイトを含む）。
    private var position: Int = 0
    private var finalized = false

    /// ファイルを生成し、サイズ欄 0 のヘッダを書く。
    ///
    /// - Parameters:
    ///   - hz: サンプリングレート。
    ///   - channels: チャンネル数。
    ///   - depth: 1 サンプルあたりのビット数（16 または 32 を想定）。
    ///   - formatID: WAVE フォーマットタグ（`formatPCM` / `formatIEEEFloat`）。
    ///   - byteLimit: ファイル位置の上限。残量計算の基準であり、
    ///     既定は本家どおり `Int32.max`。
    public init(
        filePath: String,
        hz: Int,
        channels: Int,
        depth: Int,
        formatID: Int,
        byteLimit: Int = Int(Int32.max)
    ) throws {
        self.depth = depth
        self.byteLimit = byteLimit
        _ = FileManager.default.createFile(atPath: filePath, contents: nil)
        handle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))

        var header = Data()
        header.reserveCapacity(44)
        header.append(contentsOf: Array("RIFF".utf8))
        header.appendLittleEndian(UInt32(0))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        header.appendLittleEndian(UInt32(16))
        header.appendLittleEndian(UInt16(formatID))
        header.appendLittleEndian(UInt16(channels))
        header.appendLittleEndian(UInt32(hz))
        header.appendLittleEndian(UInt32(hz * channels * depth / 8))
        header.appendLittleEndian(UInt16(depth / 8 * channels))
        header.appendLittleEndian(UInt16(depth))
        header.append(contentsOf: Array("data".utf8))
        header.appendLittleEndian(UInt32(0))
        try handle.write(contentsOf: header)
        position = header.count
    }

    /// 書き込み可能サンプル数の残量（本家の式どおり:
    /// `(上限 − 現在位置) / depth`。depth はビット数）。
    public var remainingWritableSampleCount: Int {
        (byteLimit - position) / depth
    }

    /// float サンプル列（リトルエンディアン）をそのまま書く。
    public func write(_ samples: [Float]) throws {
        var data = Data()
        data.reserveCapacity(samples.count * 4)
        for sample in samples {
            var bits = sample.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        try write(data)
    }

    /// 16 ビットサンプル列（リトルエンディアン）をそのまま書く。
    public func write(_ samples: [Int16]) throws {
        var data = Data()
        data.reserveCapacity(samples.count * 2)
        for sample in samples {
            var bits = UInt16(bitPattern: sample).littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        try write(data)
    }

    /// バイト列をそのまま書く。
    public func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
        position += data.count
    }

    /// サイズ欄を実位置で埋め直してファイルを閉じる。2 回目以降は
    /// 何もしない。
    public func finalize() throws {
        guard !finalized else { return }
        finalized = true
        try handle.seek(toOffset: 4)
        var riffSize = UInt32(position - 8).littleEndian
        try withUnsafeBytes(of: &riffSize) { try handle.write(contentsOf: Data($0)) }
        try handle.seek(toOffset: 40)
        var dataSize = UInt32(position - 44).littleEndian
        try withUnsafeBytes(of: &dataSize) { try handle.write(contentsOf: Data($0)) }
        try handle.close()
    }

    deinit {
        if !finalized {
            try? finalize()
        }
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }
}
