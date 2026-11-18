import AVFoundation
import Foundation

// TRIM55 診断: 素材の資産・トラックの時間範囲と、AVAssetReader が
// 実際に返すサンプルバッファの提示時刻（PTS）の関係を実測する。
// 使い方: diag <素材ファイルのパス> [シーク秒]

let path = CommandLine.arguments[1]
let seekSeconds = CommandLine.arguments.count >= 3
    ? Double(CommandLine.arguments[2])! : 0.0
let asset = AVURLAsset(url: URL(fileURLWithPath: path))

func fmt(_ time: CMTime) -> String {
    time.isValid ? String(format: "%.6f", time.seconds) : "invalid"
}

let semaphore = DispatchSemaphore(value: 0)
// トップレベルコードは MainActor 上で動くため、通常の Task は
// メインスレッドへ戻ろうとしてセマフォ待ちとデッドロックする。
// detached で協調プール側へ逃がす。
Task.detached {
    defer { semaphore.signal() }
    do {
        let assetDuration = try await asset.load(.duration)
        print("asset.duration=\(fmt(assetDuration))")
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            print("no audio track")
            return
        }
        let trackRange = try await track.load(.timeRange)
        print("track.timeRange start=\(fmt(trackRange.start)) duration=\(fmt(trackRange.duration)) end=\(fmt(CMTimeAdd(trackRange.start, trackRange.duration)))")
        let segments = try await track.load(.segments)
        for (index, segment) in segments.enumerated() {
            print("segment[\(index)] source start=\(fmt(segment.timeMapping.source.start)) duration=\(fmt(segment.timeMapping.source.duration)) target start=\(fmt(segment.timeMapping.target.start)) duration=\(fmt(segment.timeMapping.target.duration)) empty=\(segment.isEmpty)")
        }

        // リーダーをトラック範囲の先頭から作り、最初の数バッファの
        // PTS とサンプル数を出す。
        func probe(readerStart: CMTime, label: String) {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 2,
            ])
            output.alwaysCopiesSampleData = true
            guard let reader = try? AVAssetReader(asset: asset) else {
                print("\(label): reader creation failed")
                return
            }
            let end = CMTimeAdd(trackRange.start, trackRange.duration)
            if readerStart < end {
                reader.timeRange = CMTimeRange(start: readerStart, end: end)
            }
            reader.add(output)
            guard reader.startReading() else {
                print("\(label): startReading failed status=\(reader.status.rawValue) error=\(String(describing: reader.error))")
                return
            }
            var count = 0
            var totalSamples: Int64 = 0
            var firstPTS = ""
            var lastPTS = ""
            var firstBufferInfo = ""
            while let buffer = output.copyNextSampleBuffer() {
                let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
                let n = CMSampleBufferGetNumSamples(buffer)
                if count == 0 {
                    firstPTS = fmt(pts)
                    // 最初のバッファ内の最初の非無音フレーム位置。
                    if let block = CMSampleBufferGetDataBuffer(buffer) {
                        let length = CMBlockBufferGetDataLength(block)
                        var samples = [Float](repeating: 0, count: length / 4)
                        _ = samples.withUnsafeMutableBytes { destination in
                            CMBlockBufferCopyDataBytes(
                                block, atOffset: 0, dataLength: length,
                                destination: destination.baseAddress!
                            )
                        }
                        var firstAudible = -1
                        for index in 0..<(samples.count / 2) {
                            if abs(samples[index * 2]) > 0.01 || abs(samples[index * 2 + 1]) > 0.01 {
                                firstAudible = index
                                break
                            }
                        }
                        firstBufferInfo = " firstBufferFrames=\(n) firstAudibleInBuffer=\(firstAudible)"
                    }
                }
                lastPTS = fmt(pts)
                totalSamples += Int64(n)
                count += 1
                if count > 100000 { break }
            }
            print("\(label): buffers=\(count) totalSamples=\(totalSamples) firstPTS=\(firstPTS) lastPTS=\(lastPTS) status=\(reader.status.rawValue)\(firstBufferInfo)")
        }

        probe(readerStart: trackRange.start, label: "from trackRange.start")
        if seekSeconds > 0 {
            let target = CMTimeAdd(
                trackRange.start,
                CMTime(seconds: seekSeconds, preferredTimescale: 48000)
            )
            probe(readerStart: target, label: "from start+\(seekSeconds)s")
        }
        if CommandLine.arguments.count >= 4 {
            // プリロール検証: readerStart から読み始め、PTS が
            // landTarget に達したバッファの内容（先頭の非無音位置）
            // を出す。本家方式（前から読んで時刻で着地する）で
            // デコーダ遅延の補正が効くかを見る。
            let landTarget = Double(CommandLine.arguments[3])!
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 2,
            ])
            output.alwaysCopiesSampleData = true
            if let reader = try? AVAssetReader(asset: asset) {
                let start = CMTimeAdd(
                    trackRange.start,
                    CMTime(seconds: seekSeconds, preferredTimescale: 48000)
                )
                let end = CMTimeAdd(trackRange.start, trackRange.duration)
                if start < end {
                    reader.timeRange = CMTimeRange(start: start, end: end)
                }
                reader.add(output)
                if reader.startReading() {
                    var report = "preroll: no buffer reached target"
                    while let buffer = output.copyNextSampleBuffer() {
                        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
                        let n = CMSampleBufferGetNumSamples(buffer)
                        if pts.seconds + Double(n) / 48000.0 > landTarget {
                            var atTarget: Float = -1
                            var peakAround: Float = -1
                            if let block = CMSampleBufferGetDataBuffer(buffer) {
                                let length = CMBlockBufferGetDataLength(block)
                                var samples = [Float](repeating: 0, count: length / 4)
                                _ = samples.withUnsafeMutableBytes { destination in
                                    CMBlockBufferCopyDataBytes(
                                        block, atOffset: 0, dataLength: length,
                                        destination: destination.baseAddress!
                                    )
                                }
                                let targetFrame = Int((landTarget - pts.seconds) * 48000)
                                if targetFrame >= 0, (targetFrame + 1) * 2 <= samples.count {
                                    atTarget = abs(samples[targetFrame * 2])
                                    var peak: Float = 0
                                    let lo = max(0, targetFrame - 2)
                                    let hi = min(samples.count / 2, targetFrame + 32)
                                    for index in lo..<hi {
                                        peak = max(peak, abs(samples[index * 2]))
                                    }
                                    peakAround = peak
                                }
                            }
                            report = "preroll: buffer PTS=\(fmt(pts)) frames=\(n) valueAtTarget=\(atTarget) peak[target-2, target+32)=\(peakAround)"
                            break
                        }
                    }
                    print(report)
                }
            }
        }
    } catch {
        print("error: \(error)")
    }
}
semaphore.wait()
