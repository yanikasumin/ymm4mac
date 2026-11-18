import AVFoundation
import CoreGraphics
import Foundation

// TRIM55 映像診断: 提示開始オフセットのある動画について、
// 映像トラックのセグメント構造と、AVAssetImageGenerator が
// 提示時刻で引いたフレームの内容（色）を実測する。
// 使い方: vdiag <動画ファイル>
// 素材は「前半 1 秒 = 赤、後半 1 秒 = 青」が正解。

let path = CommandLine.arguments[1]
let asset = AVURLAsset(url: URL(fileURLWithPath: path))

func fmt(_ time: CMTime) -> String {
    time.isValid ? String(format: "%.6f", time.seconds) : "invalid"
}

let semaphore = DispatchSemaphore(value: 0)
Task.detached {
    defer { semaphore.signal() }
    do {
        let assetDuration = try await asset.load(.duration)
        print("asset.duration=\(fmt(assetDuration))")
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            print("no video track")
            return
        }
        let trackRange = try await track.load(.timeRange)
        print("track.timeRange start=\(fmt(trackRange.start)) duration=\(fmt(trackRange.duration))")
        for (index, segment) in try await track.load(.segments).enumerated() {
            print("segment[\(index)] source start=\(fmt(segment.timeMapping.source.start)) duration=\(fmt(segment.timeMapping.source.duration)) target start=\(fmt(segment.timeMapping.target.start)) duration=\(fmt(segment.timeMapping.target.duration)) empty=\(segment.isEmpty)")
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for seconds in [0.5, 1.5, 2.5, 3.5] {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            do {
                let result = try await generator.image(at: time)
                let image = result.image
                // 中心ピクセルの色を読む。
                var pixel = [UInt8](repeating: 0, count: 4)
                let context = CGContext(
                    data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )!
                context.draw(image, in: CGRect(x: -32, y: -32, width: 64, height: 64))
                print("at \(seconds)s: actual=\(fmt(result.actualTime)) rgba=(\(pixel[0]),\(pixel[1]),\(pixel[2]),\(pixel[3]))")
            } catch {
                print("at \(seconds)s: error \(error)")
            }
        }
    } catch {
        print("error: \(error)")
    }
}
semaphore.wait()
