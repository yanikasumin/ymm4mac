import Foundation

/// PNG エンコーダ（純粋 Swift 実装）。本家 PngWav ライターが WIC へ
/// 宣言する出力条件を再現する: BGRA / Premultiplied の画素を
/// RGBA（カラータイプ 6、ビット深度 8）として書き、解像度は
/// 96 dpi（pHYs チャンク、メートルあたり 3780 画素）で宣言する。
///
/// 圧縮は zlib 形式（RFC 1950）＋ DEFLATE 固定ハフマン（RFC 1951）。
/// 行ごとに PNG フィルタ 5 種を評価し、フィルタ後バイト列を符号付き
/// として見た絶対値和が最小のものを選ぶ（一般的な最小絶対差ヒューリ
/// スティクス）。画素値は無損失で保持される。
public enum PNGEncoder {
    /// 96 dpi をメートルあたり画素数へ換算した値（96 / 0.0254 ≒ 3780）。
    public static let pixelsPerMeterFor96Dpi: UInt32 = 3780

    /// BGRA（Premultiplied）画素列を PNG データへ変換する。
    /// `bgra` の長さは `width * height * 4` でなければならない。
    public static func encode(bgra: [UInt8], width: Int, height: Int) -> Data {
        precondition(width > 0 && height > 0 && bgra.count == width * height * 4)

        // BGRA → RGBA へ並べ替える（値は Premultiplied のまま保持）。
        var rgba = [UInt8](repeating: 0, count: bgra.count)
        for i in stride(from: 0, to: bgra.count, by: 4) {
            rgba[i] = bgra[i + 2]
            rgba[i + 1] = bgra[i + 1]
            rgba[i + 2] = bgra[i]
            rgba[i + 3] = bgra[i + 3]
        }

        let filtered = applyFilters(rgba: rgba, width: width, height: height)
        let compressed = zlibCompress(filtered)

        var png = Data()
        png.append(contentsOf: [137, 80, 78, 71, 13, 10, 26, 10] as [UInt8])

        var ihdr = Data()
        ihdr.appendBigEndian(UInt32(width))
        ihdr.appendBigEndian(UInt32(height))
        ihdr.append(contentsOf: [8, 6, 0, 0, 0] as [UInt8])  // 深度8 / RGBA / 圧縮0 / フィルタ0 / 非インターレース
        appendChunk(to: &png, type: "IHDR", data: ihdr)

        var phys = Data()
        phys.appendBigEndian(pixelsPerMeterFor96Dpi)
        phys.appendBigEndian(pixelsPerMeterFor96Dpi)
        phys.append(contentsOf: [1] as [UInt8])  // 単位 = メートル
        appendChunk(to: &png, type: "pHYs", data: phys)

        // IDAT は適当な大きさに分割してよい（デコーダは連結して読む）。
        var offset = 0
        while offset < compressed.count {
            let end = min(offset + 65_536, compressed.count)
            appendChunk(to: &png, type: "IDAT", data: compressed[offset..<end])
            offset = end
        }
        appendChunk(to: &png, type: "IEND", data: Data())
        return png
    }

    // MARK: - チャンク

    private static func appendChunk(to png: inout Data, type: String, data: Data) {
        png.appendBigEndian(UInt32(data.count))
        let typeBytes = Array(type.utf8)
        png.append(contentsOf: typeBytes)
        png.append(data)
        var crcInput = Data(typeBytes)
        crcInput.append(data)
        png.appendBigEndian(crc32(crcInput))
    }

    /// PNG の CRC-32（多項式 0xEDB88320、初期値・最終 XOR とも全ビット 1）。
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    // MARK: - 行フィルタ

    /// 行ごとに最適なフィルタを選び、フィルタ種別バイト付きの
    /// スキャンライン列を返す。bytesPerPixel = 4（RGBA）。
    private static func applyFilters(rgba: [UInt8], width: Int, height: Int) -> [UInt8] {
        let rowBytes = width * 4
        var output = [UInt8]()
        output.reserveCapacity((rowBytes + 1) * height)
        var previousRow: [UInt8]? = nil
        for row in 0..<height {
            let current = Array(rgba[(row * rowBytes)..<((row + 1) * rowBytes)])
            var bestType: UInt8 = 0
            var bestData: [UInt8] = current
            var bestScore = Int.max
            for type in UInt8(0)...UInt8(4) {
                let filtered = filterRow(
                    type: type, current: current, previous: previousRow, bytesPerPixel: 4
                )
                var score = 0
                for byte in filtered {
                    score += abs(Int(Int8(bitPattern: byte)))
                }
                if score < bestScore {
                    bestScore = score
                    bestType = type
                    bestData = filtered
                }
            }
            output.append(bestType)
            output.append(contentsOf: bestData)
            previousRow = current
        }
        return output
    }

    private static func filterRow(
        type: UInt8, current: [UInt8], previous: [UInt8]?, bytesPerPixel: Int
    ) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: current.count)
        for i in 0..<current.count {
            let left: Int = i >= bytesPerPixel ? Int(current[i - bytesPerPixel]) : 0
            let up: Int = previous.map { Int($0[i]) } ?? 0
            let upLeft: Int = (previous != nil && i >= bytesPerPixel)
                ? Int(previous![i - bytesPerPixel]) : 0
            let predictor: Int
            switch type {
            case 0: predictor = 0
            case 1: predictor = left
            case 2: predictor = up
            case 3: predictor = (left + up) / 2
            case 4: predictor = paeth(left, up, upLeft)
            default: predictor = 0
            }
            result[i] = UInt8(truncatingIfNeeded: Int(current[i]) - predictor)
        }
        return result
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

    // MARK: - zlib / DEFLATE（固定ハフマン）

    /// zlib 形式で圧縮する（ヘッダ 0x78 0x9C、末尾は Adler-32）。
    static func zlibCompress(_ input: [UInt8]) -> Data {
        var writer = DeflateBitWriter()
        writer.writeZlibHeader()
        let blockSize = 65_536
        var offset = 0
        if input.isEmpty {
            writer.writeBlock(input: [], isFinal: true)
        }
        while offset < input.count {
            let end = min(offset + blockSize, input.count)
            writer.writeBlock(
                input: Array(input[offset..<end]), isFinal: end == input.count
            )
            offset = end
        }
        writer.writeAdler32(input)
        return writer.data
    }

    /// Adler-32（RFC 1950）。Swift の Int は 64 ビットのため、
    /// 剰余は適当な間隔で取れば十分。
    static func adler32(_ input: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        var index = 0
        while index < input.count {
            let end = min(index + 8192, input.count)
            for i in index..<end {
                a += UInt32(input[i])
                b += a
            }
            a %= 65_521
            b %= 65_521
            index = end
        }
        return (b << 16) | a
    }
}

// MARK: - DEFLATE ビット書き出し

/// DEFLATE のビット列は「バイト内では下位ビットから詰める」が、
/// ハフマン符号は「符号の最上位ビットから送る」ため、符号を
/// ビット反転してから下位ビット詰めで書く。
private struct DeflateBitWriter {
    private(set) var data = Data()
    private var bitBuffer: UInt32 = 0
    private var bitCount: Int = 0

    mutating func writeZlibHeader() {
        data.append(contentsOf: [0x78, 0x9C] as [UInt8])
    }

    mutating func writeAdler32(_ input: [UInt8]) {
        alignToByte()
        data.appendBigEndian(PNGEncoder.adler32(input))
    }

    private mutating func writeBits(_ value: UInt32, count: Int) {
        bitBuffer |= value << bitCount
        bitCount += count
        while bitCount >= 8 {
            data.append(UInt8(bitBuffer & 0xFF))
            bitBuffer >>= 8
            bitCount -= 8
        }
    }

    private mutating func alignToByte() {
        if bitCount > 0 {
            data.append(UInt8(bitBuffer & 0xFF))
            bitBuffer = 0
            bitCount = 0
        }
    }

    private mutating func writeHuffmanCode(_ code: UInt32, length: Int) {
        // 符号をビット反転してから書く（DEFLATE の符号送出順）。
        var reversed: UInt32 = 0
        var remaining = code
        for _ in 0..<length {
            reversed = (reversed << 1) | (remaining & 1)
            remaining >>= 1
        }
        writeBits(reversed, count: length)
    }

    private mutating func writeLiteral(_ byte: UInt8) {
        let value = UInt32(byte)
        if value < 144 {
            writeHuffmanCode(0x30 + value, length: 8)
        } else {
            writeHuffmanCode(0x190 + (value - 144), length: 9)
        }
    }

    private mutating func writeLengthSymbol(_ length: Int) {
        // 長さ符号 257...285 の基底値と追加ビット数（RFC 1951 §3.2.5）。
        let bases = [
            3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
            35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
        ]
        let extras = [
            0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
            3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
        ]
        var index = bases.count - 1
        while bases[index] > length { index -= 1 }
        let symbol = 257 + index
        if symbol < 280 {
            writeHuffmanCode(UInt32(symbol - 256), length: 7)
        } else {
            writeHuffmanCode(0xC0 + UInt32(symbol - 280), length: 8)
        }
        if extras[index] > 0 {
            writeBits(UInt32(length - bases[index]), count: extras[index])
        }
    }

    private mutating func writeDistanceSymbol(_ distance: Int) {
        let bases = [
            1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
            257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
            8193, 12289, 16385, 24577,
        ]
        let extras = [
            0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
            7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
        ]
        var index = bases.count - 1
        while bases[index] > distance { index -= 1 }
        // 固定ハフマンでは距離符号は全て 5 ビット。
        writeHuffmanCode(UInt32(index), length: 5)
        if extras[index] > 0 {
            writeBits(UInt32(distance - bases[index]), count: extras[index])
        }
    }

    /// 固定ハフマンブロックを 1 つ書く。LZ77 は 3 バイトハッシュの
    /// 連鎖で最長一致を探す貪欲法（最大連鎖 64、ウィンドウ 32768）。
    mutating func writeBlock(input: [UInt8], isFinal: Bool) {
        writeBits(isFinal ? 1 : 0, count: 1)
        writeBits(0b01, count: 2)  // BTYPE = 固定ハフマン

        let count = input.count
        // ハッシュ表: キー → 直近の位置。連鎖は prev 配列で辿る。
        var head = [Int32](repeating: -1, count: 1 << 15)
        var prev = [Int32](repeating: -1, count: count)

        func hash(_ position: Int) -> Int {
            let v = UInt32(input[position]) << 16
                | UInt32(input[position + 1]) << 8
                | UInt32(input[position + 2])
            return Int((v &* 0x9E37_79B1) >> 17) & 0x7FFF
        }

        var position = 0
        while position < count {
            var bestLength = 0
            var bestDistance = 0
            if position + 3 <= count {
                var candidate = head[hash(position)]
                var chain = 0
                while candidate >= 0 && chain < 64 {
                    let distance = position - Int(candidate)
                    if distance > 32_768 { break }
                    // 末尾の 1 バイトが違えば最長一致にはならない。
                    let maxLength = min(count - position, 258)
                    if input[Int(candidate) + bestLength] == input[position + bestLength] {
                        var length = 0
                        while length < maxLength
                            && input[Int(candidate) + length] == input[position + length] {
                            length += 1
                        }
                        if length >= 3 && length > bestLength {
                            bestLength = length
                            bestDistance = distance
                            if length >= maxLength { break }
                        }
                    }
                    candidate = prev[Int(candidate)]
                    chain += 1
                }
            }
            if bestLength >= 3 {
                writeLengthSymbol(bestLength)
                writeDistanceSymbol(bestDistance)
                // 一致区間の位置もハッシュ表へ登録する（圧縮率のため）。
                let end = position + bestLength
                while position < end {
                    if position + 3 <= count {
                        let h = hash(position)
                        prev[position] = head[h]
                        head[h] = Int32(position)
                    }
                    position += 1
                }
            } else {
                writeLiteral(input[position])
                if position + 3 <= count {
                    let h = hash(position)
                    prev[position] = head[h]
                    head[h] = Int32(position)
                }
                position += 1
            }
        }
        // ブロック終端符号 256（7 ビットの 0）。
        writeHuffmanCode(0, length: 7)
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
