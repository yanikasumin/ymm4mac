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
/// 入力は本家と同じく、アイテムのエフェクトチェーンを通した音声
/// （再生速度・ContentOffset を反映し、音量制御・エコー・音声
/// エフェクトは除く）を 48kHz で供給する。供給の組み立てはホスト
/// 側の責務で、計算自体はストリームのレートに対して中立である
/// （R20-116-01）。
public enum LipSyncEnvelopeCalculator {
    /// 包絡を計算する。引数が不正な場合と、音声が読めない場合
    /// （本家の Fail 相当）は nil。窓長の計算で整数が溢れた場合も
    /// 本家の checked 演算の失敗に合わせて nil（R20-116-06）。
    public static func calculate(
        stream: AudioStream, fps: Int, smooth: Int, frameCount: Int
    ) -> [Double]? {
        guard fps > 0, frameCount >= 0, smooth >= 0 else { return nil }
        let hz = stream.hz
        guard hz > 0 else { return nil }
        let (hzTimesSmooth, overflowA) = hz.multipliedReportingOverflow(by: smooth)
        let (window, overflowB) = (hzTimesSmooth / fps)
            .multipliedReportingOverflow(by: 2)
        guard !overflowA, !overflowB, window > 0, window <= 16_777_216 else {
            return nil
        }
        // 窓の開始位置の計算（(smooth + 1) / 2 と Int64 の乗算）でも
        // 溢れ得るため、ループ前に両端の開始位置で検査する
        // （R21-116-01）。
        let (smoothPlusOne, overflowC) = smooth.addingReportingOverflow(1)
        guard !overflowC else { return nil }
        let centerOffset = (smoothPlusOne) / 2
        func windowStartIsSafe(_ frame: Int) -> Bool {
            let (product, overflow) = Int64(hz).multipliedReportingOverflow(
                by: Int64(frame - centerOffset)
            )
            return !overflow
        }
        guard windowStartIsSafe(0), windowStartIsSafe(frameCount) else {
            return nil
        }

        stream.seek(toTime: .zero)

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
                let read = stream.read(into: &buffer, offset: 0, count: count)
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
        if readPosition == 0, stream.duration > 0 {
            return nil
        }
        return values
    }
}
