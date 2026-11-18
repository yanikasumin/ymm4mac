import Foundation

/// 口パク音量の包絡計算。本家 LipSyncEnvelope（Player.Audio）の規則を
/// 同期計算として写したもの。本家は非同期セッションへ逐次公開するが、
/// 値の意味論は同一である:
///
/// - 窓の長さ（インターリーブ済みサンプル数）= Hz × smooth / fps × 2
///   （整数演算、本家と同じ順序）。上限 16,777,216 を超えたら失敗。
/// - フレーム i の窓は [Hz × (i − (smooth+1)/2) / fps × 2, +窓長)
///   で、窓の中心がフレーム位置に来る。範囲外は 0 として数える
///   （分母は常に窓長）。
/// - 値は窓内の二乗和の平均の平方根（RMS）。
/// - 結果はフレーム 0...frameCount の frameCount+1 件。
///
/// 本家は対象音声を 48kHz へリサンプルしてから計算する。こちらは
/// 供給元のレートをそのまま使う（窓は時刻で定義されるため、レートは
/// 粒度にだけ影響する）。
public enum LipSyncEnvelopeCalculator {
    /// 包絡を計算する。引数が不正な場合と、音声が読めない場合
    /// （本家の Fail 相当）は nil。
    public static func calculate(
        provider: PCMProvider, fps: Int, smooth: Int, frameCount: Int
    ) -> [Double]? {
        guard fps > 0, frameCount >= 0, smooth >= 0 else { return nil }
        let hz = provider.hz
        guard hz > 0 else { return nil }
        let window = hz * smooth / fps * 2
        guard window > 0, window <= 16_777_216 else { return nil }

        provider.seek(toTime: .zero)

        // 窓内の二乗和を保持するリングバッファ。
        var ring = [Float](repeating: 0, count: window)
        var ringRead = 0
        var ringCount = 0
        var sumOfSquares: Double = 0
        var readPosition: Int64 = 0
        var queueStart: Int64 = 0
        var reachedEnd = false
        var buffer = [Float](repeating: 0, count: 16_384)

        func dropOldest() {
            sumOfSquares -= Double(ring[ringRead])
            ringRead = (ringRead + 1) % window
            ringCount -= 1
            queueStart += 1
        }

        var values: [Double] = []
        values.reserveCapacity(frameCount + 1)
        for frame in 0...frameCount {
            let windowStart = Int64(hz) * Int64(frame - (smooth + 1) / 2) / Int64(fps) * 2
            let windowEnd = windowStart + Int64(window)
            let dropTarget = max(Int64(0), windowStart)
            while queueStart < dropTarget, ringCount > 0 {
                dropOldest()
            }
            if ringCount == 0 {
                queueStart = readPosition
            }
            while !reachedEnd, readPosition < windowEnd {
                let count = min(buffer.count, Int(windowEnd - readPosition))
                let read = provider.read(into: &buffer, offset: 0, count: count)
                if read <= 0 {
                    reachedEnd = true
                    break
                }
                for j in 0..<read {
                    let square = buffer[j] * buffer[j]
                    if ringCount == window {
                        dropOldest()
                    }
                    let writeIndex = (ringRead + ringCount) % window
                    ring[writeIndex] = square
                    ringCount += 1
                    sumOfSquares += Double(square)
                }
                readPosition += Int64(read)
            }
            values.append((max(0, sumOfSquares) / Double(window)).squareRoot())
        }
        // 本家: 何も読めなかったのに長さがある音声は失敗扱い。
        if readPosition == 0, provider.duration.ticks > 0 {
            return nil
        }
        return values
    }
}
