//
//  VideoKeyframeExtractor.swift
//  Pulls N evenly-spaced frames from a video asset. Morphing chains them end to end
//  to produce a smooth Michael-Jackson-style face sequence.
//

import AVFoundation
import UIKit

enum VideoKeyframeExtractor {

    /// Extract `count` frames evenly distributed across the asset's duration.
    /// Returns UIImages in playback order.
    static func extractFrames(from url: URL, count: Int) async throws -> [UIImage] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0, count > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1080, height: 1080)

        var times: [NSValue] = []
        for i in 0..<count {
            // Avoid the very edges — first/last frame often has fade/black
            let f = (Double(i) + 0.5) / Double(count)
            let t = CMTime(seconds: totalSeconds * f, preferredTimescale: 600)
            times.append(NSValue(time: t))
        }

        var results: [(CMTime, UIImage)] = []
        for value in times {
            let time = value.timeValue
            do {
                let cg = try generator.copyCGImage(at: time, actualTime: nil)
                results.append((time, UIImage(cgImage: cg)))
            } catch {
                continue
            }
        }
        // Preserve playback order
        results.sort { CMTimeCompare($0.0, $1.0) < 0 }
        return results.map(\.1)
    }
}
