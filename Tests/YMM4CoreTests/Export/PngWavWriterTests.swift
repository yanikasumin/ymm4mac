import XCTest
@testable import YMM4Core

// MARK: - WAV ライター

final class WavFileWriterTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wav-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func readHeader(_ url: URL) throws -> (fields: [String: UInt32], payload: [Float]) {
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count % 4, 0)
        func ascii(_ range: Range<Int>) -> String {
            String(bytes: data[range], encoding: .ascii) ?? ""
        }
        func u32(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
            }
        }
        func u16(_ offset: Int) -> UInt32 {
            UInt32(data.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian
            })
        }
        XCTAssertEqual(ascii(0..<4), "RIFF")
        XCTAssertEqual(ascii(8..<12), "WAVE")
        XCTAssertEqual(ascii(12..<16), "fmt ")
        XCTAssertEqual(ascii(36..<40), "data")
        let fields: [String: UInt32] = [
            "riffSize": u32(4),
            "fmtSize": u32(16),
            "format": u16(20),
            "channels": u16(22),
            "hz": u32(24),
            "byteRate": u32(28),
            "blockAlign": u16(32),
            "depth": u16(34),
            "dataSize": u32(40),
        ]
        var payload: [Float] = []
        let dataSize = Int(u32(40))
        XCTAssertEqual(data.count, 44 + dataSize)
        payload.reserveCapacity(dataSize / 4)
        for offset in stride(from: 44, to: 44 + dataSize, by: 4) {
            let bits = data.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian
            }
            payload.append(Float(bitPattern: bits))
        }
        return (fields, payload)
    }

    func testHeaderAndPayloadFloat32() throws {
        let url = directory.appendingPathComponent("a.wav")
        let writer = try WavFileWriter(
            filePath: url.path, hz: 48_000, channels: 2, depth: 32,
            formatID: WavFileWriter.formatIEEEFloat
        )
        let samples: [Float] = [0.5, -0.25, 1.0, -1.0, 0.0, 0.125]
        try writer.write(samples)
        try writer.finalize()

        let (fields, payload) = try readHeader(url)
        XCTAssertEqual(fields["format"], 3)
        XCTAssertEqual(fields["channels"], 2)
        XCTAssertEqual(fields["hz"], 48_000)
        XCTAssertEqual(fields["byteRate"], 48_000 * 2 * 4)
        XCTAssertEqual(fields["blockAlign"], 8)
        XCTAssertEqual(fields["depth"], 32)
        XCTAssertEqual(fields["fmtSize"], 16)
        XCTAssertEqual(fields["dataSize"], UInt32(samples.count * 4))
        // RIFF サイズ = ファイルサイズ − 8。
        XCTAssertEqual(fields["riffSize"], UInt32(44 + samples.count * 4 - 8))
        XCTAssertEqual(payload.map(\.bitPattern), samples.map(\.bitPattern))
    }

    /// 残量の式は本家どおり `(上限 − 位置) / depth`。位置には
    /// ヘッダ 44 バイトが含まれ、depth はビット数（32）で割る。
    func testRemainingWritableSampleCountFormula() throws {
        let url = directory.appendingPathComponent("b.wav")
        let writer = try WavFileWriter(
            filePath: url.path, hz: 48_000, channels: 2, depth: 32,
            formatID: WavFileWriter.formatIEEEFloat, byteLimit: 2044
        )
        XCTAssertEqual(writer.remainingWritableSampleCount, (2044 - 44) / 32)
        try writer.write([Float](repeating: 0, count: 100))
        XCTAssertEqual(writer.remainingWritableSampleCount, (2044 - 444) / 32)
        try writer.finalize()
    }
}

// MARK: - PngWav ライター

final class PngWavFileWriterTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pngwav-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func videoInfo() -> VideoInfo {
        VideoInfo(fps: 30, hz: 48_000, width: 4, height: 3)
    }

    func testSupportedStreamsFollowSettings() throws {
        let both = try PngWavFileWriter(
            directoryPath: directory.path, fileName: "x", videoInfo: videoInfo()
        )
        XCTAssertEqual(both.supportedStreams, [.video, .audio])
        let pngOnly = try PngWavFileWriter(
            directoryPath: directory.path, fileName: "x", videoInfo: videoInfo(),
            isWavOutputEnabled: false
        )
        XCTAssertEqual(pngOnly.supportedStreams, [.video])
        let wavOnly = try PngWavFileWriter(
            directoryPath: directory.path, fileName: "x", videoInfo: videoInfo(),
            isPngOutputEnabled: false
        )
        XCTAssertEqual(wavOnly.supportedStreams, [.audio])
    }

    func testDisabledStreamWriteThrows() throws {
        let writer = try PngWavFileWriter(
            directoryPath: directory.path, fileName: "x", videoInfo: videoInfo(),
            isPngOutputEnabled: false, isWavOutputEnabled: false
        )
        XCTAssertThrowsError(
            try writer.writeVideoFrame(ExportVideoFrameBuffer(byteCount: 4 * 3 * 4))
        )
        XCTAssertThrowsError(try writer.writeAudioSamples([0, 0]))
        XCTAssertFalse(writer.producesOutputFile)
    }

    /// PNG の連番命名と、デコードした画素が入力 BGRA の R/B 入れ替えと
    /// 一致すること（無損失）を検証する。
    func testPNGFilesAreNumberedAndLossless() throws {
        let writer = try PngWavFileWriter(
            directoryPath: directory.path, fileName: "proj", videoInfo: videoInfo()
        )
        // 4×3 の決定的な画素パターン（BGRA、Premultiplied 前提の生値）。
        var bgra = [UInt8]()
        for i in 0..<(4 * 3 * 4) {
            bgra.append(UInt8((i * 37 + 11) % 256))
        }
        let buffer = ExportVideoFrameBuffer(byteCount: bgra.count)
        buffer.bytes = bgra
        try writer.writeVideoFrame(buffer)
        try writer.writeVideoFrame(buffer)
        try writer.finalize()

        for index in 0..<2 {
            let url = directory.appendingPathComponent("proj_\(index).png")
            let data = try Data(contentsOf: url)
            let decoded = try PNGTestDecoder.decode(data)
            XCTAssertEqual(decoded.width, 4)
            XCTAssertEqual(decoded.height, 3)
            XCTAssertEqual(decoded.pixelsPerMeter, 3780)
            var expectedRGBA = [UInt8]()
            for i in stride(from: 0, to: bgra.count, by: 4) {
                expectedRGBA.append(contentsOf: [bgra[i + 2], bgra[i + 1], bgra[i], bgra[i + 3]])
            }
            XCTAssertEqual(decoded.rgba, expectedRGBA)
        }
    }

    /// 大きめのグラデーションでも往復が無損失であること
    /// （LZ77 の一致・複数フィルタ・複数ブロックを踏む）。
    func testPNGLargerImageRoundTrip() throws {
        let width = 37
        let height = 23
        var bgra = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                bgra.append(contentsOf: [
                    UInt8((x * 7 + y * 3) % 256), UInt8((x + y * 5) % 256),
                    UInt8((x * x + y) % 256), 255,
                ])
            }
        }
        let data = PNGEncoder.encode(bgra: bgra, width: width, height: height)
        let decoded = try PNGTestDecoder.decode(data)
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        var expectedRGBA = [UInt8]()
        for i in stride(from: 0, to: bgra.count, by: 4) {
            expectedRGBA.append(contentsOf: [bgra[i + 2], bgra[i + 1], bgra[i], bgra[i + 3]])
        }
        XCTAssertEqual(decoded.rgba, expectedRGBA)
    }

    /// WAV の自動分割: 上限を小さく差し替えると、残量不足の時点で
    /// 次の連番ファイルへ切り替わり、サンプル総数は保存される。
    func testWAVSplitsWhenRemainingRunsOut() throws {
        // 上限 2044: 初期残量 (2044−44)/32 = 62 < 100 なので、
        // 100 サンプル書くたびに次のファイルへ切り替わる。
        let writer = try PngWavFileWriter(
            directoryPath: directory.path, fileName: "seg", videoInfo: videoInfo(),
            wavByteLimit: 2044
        )
        for _ in 0..<3 {
            try writer.writeAudioSamples([Float](repeating: 0.25, count: 100))
        }
        try writer.finalize()

        for index in 0..<3 {
            let url = directory.appendingPathComponent("seg_\(index).wav")
            let data = try Data(contentsOf: url)
            XCTAssertEqual(data.count, 44 + 100 * 4)
            let dataSize = data.withUnsafeBytes { raw in
                raw.loadUnaligned(fromByteOffset: 40, as: UInt32.self).littleEndian
            }
            XCTAssertEqual(dataSize, 400)
        }
        let extra = directory.appendingPathComponent("seg_3.wav")
        XCTAssertFalse(FileManager.default.fileExists(atPath: extra.path))
    }

    func testWAVSingleFileWithoutSplit() throws {
        let writer = try PngWavFileWriter(
            directoryPath: directory.path, fileName: "one", videoInfo: videoInfo()
        )
        for _ in 0..<3 {
            try writer.writeAudioSamples([Float](repeating: -0.5, count: 100))
        }
        try writer.finalize()
        let url = directory.appendingPathComponent("one_0.wav")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 44 + 300 * 4)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("one_1.wav").path
            )
        )
    }

    /// セッション経由の完了条件: 30 フレーム（30 fps / 48000 Hz）を
    /// 書き出すと PNG が 30 枚、WAV の長さがちょうど 1 秒になる。
    func testSessionEndToEndFrameAndAudioCounts() throws {
        let info = VideoInfo(fps: 30, hz: 48_000, width: 64, height: 64)
        let writer = try PngWavFileWriter(
            directoryPath: directory.path, fileName: "proj", videoInfo: info
        )
        let session = ExportSession(writer: writer)
        let outcome = session.run(
            configuration: ExportSession.Configuration(
                outputPath: directory.path, videoInfo: info, frameRange: 0..<30
            ),
            videoProvider: PatternVideoProvider(),
            audioProvider: CountingAudioProvider(hz: 48_000, fps: 30)
        )
        XCTAssertEqual(outcome.completion, .completed)
        XCTAssertEqual(outcome.framesWritten, 30)
        XCTAssertTrue(outcome.outputProduced)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let pngs = files.filter { $0.hasSuffix(".png") }.sorted()
        XCTAssertEqual(pngs.count, 30)
        XCTAssertTrue(pngs.contains("proj_0.png"))
        XCTAssertTrue(pngs.contains("proj_29.png"))

        let wav = try Data(
            contentsOf: directory.appendingPathComponent("proj_0.wav")
        )
        let dataSize = wav.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: 40, as: UInt32.self).littleEndian
        }
        // 1 秒 = 48000 サンプル/チャンネル × 2ch × 4 バイト。
        XCTAssertEqual(Int(dataSize), 48_000 * 2 * 4)
    }

    /// 接頭辞の検証（R10-01）: パス区切り・親ディレクトリ参照・空白のみは
    /// ファイル生成の境界で拒否する。
    func testInvalidFileNameIsRejected() {
        for invalid in ["../other", "a/b", "a\\b", "..", ".", "   ", ""] {
            XCTAssertThrowsError(
                try PngWavFileWriter(
                    directoryPath: directory.path, fileName: invalid,
                    videoInfo: videoInfo()
                ),
                "接頭辞 \(invalid.debugDescription) は拒否されるべき"
            )
        }
        XCTAssertTrue(PngWavFileWriter.isValidFileName("proj"))
        XCTAssertTrue(PngWavFileWriter.isValidFileName("プロジェクト 1"))
    }

    /// 既存ファイルの保護（R10-01）: 同名の連番ファイルが残っている出力先は
    /// 開始前に拒否し、既存ファイルには触れない。有効なストリームの
    /// 拡張子だけが衝突対象になる。
    func testExistingSequenceFileIsRefused() throws {
        let existing = directory.appendingPathComponent("proj_0.png")
        try Data([1, 2, 3]).write(to: existing)

        XCTAssertThrowsError(
            try PngWavFileWriter(
                directoryPath: directory.path, fileName: "proj",
                videoInfo: videoInfo()
            )
        )
        // WAV のみ有効な場合は PNG の残存は衝突にならない。
        let wavOnly = try PngWavFileWriter(
            directoryPath: directory.path, fileName: "proj",
            videoInfo: videoInfo(), isPngOutputEnabled: false
        )
        XCTAssertEqual(wavOnly.supportedStreams, [.audio])
        // 既存ファイルは無傷。
        XCTAssertEqual(try Data(contentsOf: existing), Data([1, 2, 3]))
    }
}

private final class PatternVideoProvider: VideoFrameProviding {
    func fillFrame(_ frame: Int, into buffer: ExportVideoFrameBuffer) throws {
        for i in buffer.bytes.indices {
            buffer.bytes[i] = UInt8((i + frame * 13) % 256)
        }
    }
}

private final class CountingAudioProvider: AudioFrameProviding {
    let hz: Int
    let fps: Int

    init(hz: Int, fps: Int) {
        self.hz = hz
        self.fps = fps
    }

    func audioSamples(forFrame frame: Int) throws -> [Float] {
        let count = ExportAudioSampleCount.count(forFrame: frame, hz: hz, fps: fps)
        return [Float](repeating: 0, count: count)
    }
}

// MARK: - テスト専用 PNG デコーダ

/// エンコーダの出力を独立に検証するための最小デコーダ。
/// チャンク構造と CRC、pHYs、zlib（固定ハフマン＋無圧縮ブロック）の
/// 展開、フィルタ解除を行い、RGBA 画素列へ戻す。
private enum PNGTestDecoder {
    struct Decoded {
        var width: Int
        var height: Int
        var pixelsPerMeter: UInt32
        var rgba: [UInt8]
    }

    enum DecodeError: Error {
        case invalid(String)
    }

    static func decode(_ data: Data) throws -> Decoded {
        let bytes = [UInt8](data)
        guard bytes.count > 8, Array(bytes[0..<8]) == [137, 80, 78, 71, 13, 10, 26, 10]
        else { throw DecodeError.invalid("signature") }

        var width = 0
        var height = 0
        var pixelsPerMeter: UInt32 = 0
        var idat = [UInt8]()
        var offset = 8
        var sawIEND = false
        while offset + 8 <= bytes.count {
            let length = Int(bigEndian32(bytes, offset))
            let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            let chunkData = Array(bytes[(offset + 8)..<(offset + 8 + length)])
            let storedCRC = bigEndian32(bytes, offset + 8 + length)
            var crcInput = Array(bytes[(offset + 4)..<(offset + 8)])
            crcInput.append(contentsOf: chunkData)
            guard crc32(crcInput) == storedCRC else {
                throw DecodeError.invalid("CRC mismatch in \(type)")
            }
            switch type {
            case "IHDR":
                width = Int(bigEndian32(chunkData, 0))
                height = Int(bigEndian32(chunkData, 4))
                guard chunkData[8] == 8, chunkData[9] == 6 else {
                    throw DecodeError.invalid("IHDR format")
                }
            case "pHYs":
                pixelsPerMeter = bigEndian32(chunkData, 0)
                guard bigEndian32(chunkData, 4) == pixelsPerMeter, chunkData[8] == 1 else {
                    throw DecodeError.invalid("pHYs")
                }
            case "IDAT":
                idat.append(contentsOf: chunkData)
            case "IEND":
                sawIEND = true
            default:
                break
            }
            offset += 12 + length
            if sawIEND { break }
        }
        guard sawIEND, width > 0, height > 0 else {
            throw DecodeError.invalid("missing chunks")
        }

        let raw = try inflate(zlib: idat, expectedCount: (width * 4 + 1) * height)
        // フィルタ解除（bytesPerPixel = 4）。
        let rowBytes = width * 4
        var rgba = [UInt8]()
        rgba.reserveCapacity(rowBytes * height)
        var previous = [UInt8](repeating: 0, count: rowBytes)
        for row in 0..<height {
            let base = row * (rowBytes + 1)
            let filter = raw[base]
            let line = Array(raw[(base + 1)..<(base + 1 + rowBytes)])
            var reconstructed = [UInt8](repeating: 0, count: rowBytes)
            for i in 0..<rowBytes {
                let left = i >= 4 ? Int(reconstructed[i - 4]) : 0
                let up = Int(previous[i])
                let upLeft = i >= 4 ? Int(previous[i - 4]) : 0
                let predictor: Int
                switch filter {
                case 0: predictor = 0
                case 1: predictor = left
                case 2: predictor = up
                case 3: predictor = (left + up) / 2
                case 4: predictor = paeth(left, up, upLeft)
                default: throw DecodeError.invalid("filter \(filter)")
                }
                reconstructed[i] = UInt8(truncatingIfNeeded: Int(line[i]) + predictor)
            }
            rgba.append(contentsOf: reconstructed)
            previous = reconstructed
        }
        return Decoded(
            width: width, height: height, pixelsPerMeter: pixelsPerMeter, rgba: rgba
        )
    }

    private static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a)
        let pb = abs(p - b)
        let pc = abs(p - c)
        if pa <= pb && pa <= pc { return a }
        if pb <= pc { return b }
        return c
    }

    private static func bigEndian32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    /// テスト側で独立に実装した CRC-32（ビット単位）。
    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return (b << 16) | a
    }

    // MARK: inflate（固定ハフマン＋無圧縮ブロック）

    private struct BitReader {
        let bytes: [UInt8]
        var byteIndex = 0
        var bitIndex = 0

        mutating func readBit() -> Int {
            let bit = (Int(bytes[byteIndex]) >> bitIndex) & 1
            bitIndex += 1
            if bitIndex == 8 {
                bitIndex = 0
                byteIndex += 1
            }
            return bit
        }

        mutating func readBits(_ count: Int) -> Int {
            var value = 0
            for i in 0..<count {
                value |= readBit() << i
            }
            return value
        }

        mutating func alignToByte() {
            if bitIndex != 0 {
                bitIndex = 0
                byteIndex += 1
            }
        }
    }

    private struct Huffman {
        /// キー = (符号長 << 32) | 符号値（符号は最上位ビットから読む）。
        let table: [UInt64: Int]

        init(lengths: [Int]) {
            var table: [UInt64: Int] = [:]
            var code = 0
            let maxLength = lengths.max() ?? 0
            var nextCode = [Int](repeating: 0, count: maxLength + 2)
            var counts = [Int](repeating: 0, count: maxLength + 1)
            for length in lengths where length > 0 { counts[length] += 1 }
            for bits in 1...maxLength {
                code = (code + counts[bits - 1]) << 1
                nextCode[bits] = code
            }
            for (symbol, length) in lengths.enumerated() where length > 0 {
                table[(UInt64(length) << 32) | UInt64(nextCode[length])] = symbol
                nextCode[length] += 1
            }
            self.table = table
        }

        func decode(reader: inout BitReader) -> Int? {
            var code = 0
            var length = 0
            while length < 15 {
                code = (code << 1) | reader.readBit()
                length += 1
                if let symbol = table[(UInt64(length) << 32) | UInt64(code)] {
                    return symbol
                }
            }
            return nil
        }
    }

    private static func inflate(zlib: [UInt8], expectedCount: Int) throws -> [UInt8] {
        guard zlib.count >= 6, zlib[0] == 0x78, zlib[1] == 0x9C else {
            throw DecodeError.invalid("zlib header")
        }
        var reader = BitReader(bytes: Array(zlib[2...]))
        var output = [UInt8]()
        output.reserveCapacity(expectedCount)

        let literalLengths: [Int] =
            [Int](repeating: 8, count: 144) + [Int](repeating: 9, count: 112)
            + [Int](repeating: 7, count: 24) + [Int](repeating: 8, count: 8)
        let distanceLengths = [Int](repeating: 5, count: 30)
        let literals = Huffman(lengths: literalLengths)
        let distances = Huffman(lengths: distanceLengths)
        let lengthBases = [
            3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
            35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
        ]
        let lengthExtras = [
            0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
            3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
        ]
        let distanceBases = [
            1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
            257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
            8193, 12289, 16385, 24577,
        ]
        let distanceExtras = [
            0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
            7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
        ]

        var isFinal = false
        while !isFinal {
            isFinal = reader.readBit() == 1
            let type = reader.readBits(2)
            switch type {
            case 0:
                reader.alignToByte()
                let length = Int(reader.bytes[reader.byteIndex])
                    | Int(reader.bytes[reader.byteIndex + 1]) << 8
                reader.byteIndex += 4
                for _ in 0..<length {
                    output.append(reader.bytes[reader.byteIndex])
                    reader.byteIndex += 1
                }
            case 1:
                loop: while true {
                    guard let symbol = literals.decode(reader: &reader) else {
                        throw DecodeError.invalid("literal decode")
                    }
                    switch symbol {
                    case 0..<256:
                        output.append(UInt8(symbol))
                    case 256:
                        break loop
                    case 257...285:
                        let index = symbol - 257
                        let length = lengthBases[index]
                            + (lengthExtras[index] > 0
                                ? reader.readBits(lengthExtras[index]) : 0)
                        guard let distanceSymbol = distances.decode(reader: &reader),
                              distanceSymbol < 30
                        else { throw DecodeError.invalid("distance decode") }
                        let distance = distanceBases[distanceSymbol]
                            + (distanceExtras[distanceSymbol] > 0
                                ? reader.readBits(distanceExtras[distanceSymbol]) : 0)
                        guard distance <= output.count else {
                            throw DecodeError.invalid("distance too far")
                        }
                        for _ in 0..<length {
                            output.append(output[output.count - distance])
                        }
                    default:
                        throw DecodeError.invalid("symbol \(symbol)")
                    }
                }
            default:
                throw DecodeError.invalid("block type \(type)")
            }
        }

        // 末尾の Adler-32 を検証する（バイト境界へ揃えてから読む）。
        reader.alignToByte()
        let storedAdler = bigEndian32(reader.bytes, reader.byteIndex)
        guard storedAdler == adler32(output) else {
            throw DecodeError.invalid("adler mismatch")
        }
        guard output.count == expectedCount else {
            throw DecodeError.invalid("decompressed size \(output.count) != \(expectedCount)")
        }
        return output
    }
}
