//
//  VideoExporter.swift
//  AVAssetWriter video export, plus post-process audio muxing via AVMutableComposition.
//

import AVFoundation
import CoreVideo

final class VideoExporter {

    private let url: URL
    private let size: CGSize
    private let fps: Int32
    private var writer: AVAssetWriter!
    private var input: AVAssetWriterInput!
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor!

    init(url: URL, size: CGSize, fps: Int32) {
        self.url = url
        self.size = size
        self.fps = fps
    }

    func start() throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let pbAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pbAttrs
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
    }

    func append(pixelBuffer: CVPixelBuffer, frameIndex: Int) {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.005)
        }
        let pts = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
        adaptor.append(pixelBuffer, withPresentationTime: pts)
    }

    func finish(completion: @escaping (Bool, Error?) -> Void) {
        input.markAsFinished()
        let w = writer!
        writer.finishWriting {
            completion(w.status == .completed, w.error)
        }
    }
}

/// Muxes an audio track (from any audio or video asset URL) onto a silent video file,
/// producing a new mp4. Audio is trimmed or looped to match video duration.
enum AudioMuxer {

    enum MuxError: Error {
        case noVideoTrack
        case exportFailed(String?)
    }

    static func mux(videoURL: URL,
                    audioURL: URL,
                    outputURL: URL,
                    completion: @escaping (Result<URL, Error>) -> Void) {
        let composition = AVMutableComposition()
        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)

        Task {
            do {
                guard let srcVideo = try await videoAsset.loadTracks(withMediaType: .video).first else {
                    completion(.failure(MuxError.noVideoTrack))
                    return
                }
                let videoDuration = try await videoAsset.load(.duration)
                let videoRange = CMTimeRange(start: .zero, duration: videoDuration)

                guard let compVideo = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid) else { return }
                try compVideo.insertTimeRange(videoRange, of: srcVideo, at: .zero)
                compVideo.preferredTransform = try await srcVideo.load(.preferredTransform)

                if let srcAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
                   let compAudio = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid) {

                    let audioDuration = try await audioAsset.load(.duration)
                    // Loop audio if shorter than video
                    var cursor: CMTime = .zero
                    while cursor < videoDuration {
                        let remaining = CMTimeSubtract(videoDuration, cursor)
                        let chunkDur = CMTimeMinimum(audioDuration, remaining)
                        let range = CMTimeRange(start: .zero, duration: chunkDur)
                        try compAudio.insertTimeRange(range, of: srcAudio, at: cursor)
                        cursor = CMTimeAdd(cursor, chunkDur)
                    }
                }

                try? FileManager.default.removeItem(at: outputURL)
                guard let exporter = AVAssetExportSession(
                    asset: composition,
                    presetName: AVAssetExportPresetHighestQuality) else {
                    completion(.failure(MuxError.exportFailed("no exporter")))
                    return
                }
                exporter.outputURL = outputURL
                exporter.outputFileType = .mp4
                exporter.shouldOptimizeForNetworkUse = true

                await exporter.export()
                if exporter.status == .completed {
                    completion(.success(outputURL))
                } else {
                    completion(.failure(MuxError.exportFailed(exporter.error?.localizedDescription)))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}
