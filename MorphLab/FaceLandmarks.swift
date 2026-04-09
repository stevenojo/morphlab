//
//  FaceLandmarks.swift
//  Vision landmark detection + synthetic forehead anchors.
//

import UIKit
import Vision

enum FaceLandmarks {

    /// Detects the largest face, returns landmark points in image pixel space (UIKit y-down),
    /// including synthetic forehead anchors extrapolated from the eyebrows.
    static func detect(in image: UIImage) -> [CGPoint]? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return nil }

        guard let observations = request.results as? [VNFaceObservation],
              let face = observations.max(by: { $0.boundingBox.area < $1.boundingBox.area }),
              let landmarks = face.landmarks else { return nil }

        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)
        let bb = face.boundingBox

        func convert(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            guard let region else { return [] }
            return region.normalizedPoints.map { p in
                let x = bb.origin.x * imageW + p.x * bb.size.width * imageW
                let yUp = bb.origin.y * imageH + p.y * bb.size.height * imageH
                return CGPoint(x: x, y: imageH - yUp)
            }
        }

        let contour    = convert(landmarks.faceContour)
        let leftEye    = convert(landmarks.leftEye)
        let rightEye   = convert(landmarks.rightEye)
        let leftBrow   = convert(landmarks.leftEyebrow)
        let rightBrow  = convert(landmarks.rightEyebrow)
        let nose       = convert(landmarks.nose)
        let noseCrest  = convert(landmarks.noseCrest)
        let medianLine = convert(landmarks.medianLine)
        let outerLips  = convert(landmarks.outerLips)
        let innerLips  = convert(landmarks.innerLips)

        var points: [CGPoint] = []
        points += contour
        points += leftEye
        points += rightEye
        points += leftBrow
        points += rightBrow
        points += nose
        points += noseCrest
        points += medianLine
        points += outerLips
        points += innerLips

        // Synthetic forehead anchors — Vision stops at the hairline which makes the
        // top of the head "pop" during a morph. Extrapolate upward from the brows.
        points += foreheadAnchors(leftBrow: leftBrow,
                                  rightBrow: rightBrow,
                                  contour: contour,
                                  nose: nose,
                                  imageSize: CGSize(width: imageW, height: imageH))

        return dedupe(points)
    }

    /// Build 5 synthetic points across the forehead by projecting eyebrow positions
    /// upward by a fraction of the eye-to-chin distance.
    private static func foreheadAnchors(leftBrow: [CGPoint],
                                         rightBrow: [CGPoint],
                                         contour: [CGPoint],
                                         nose: [CGPoint],
                                         imageSize: CGSize) -> [CGPoint] {
        guard !leftBrow.isEmpty, !rightBrow.isEmpty, !contour.isEmpty else { return [] }

        // Average brow line
        let allBrows = leftBrow + rightBrow
        let browY = allBrows.map(\.y).reduce(0, +) / CGFloat(allBrows.count)

        // Chin = lowest contour point
        let chinY = contour.map(\.y).max() ?? browY
        let faceHeight = chinY - browY
        guard faceHeight > 0 else { return [] }

        // Forehead ~55% of face height above brow line (empirical, matches typical anatomy)
        let foreheadY = max(0, browY - faceHeight * 0.55)

        // Span across widest contour points at brow height
        let minX = contour.map(\.x).min() ?? 0
        let maxX = contour.map(\.x).max() ?? imageSize.width
        let width = maxX - minX

        // Place 5 points in an arc — center slightly higher than the sides
        var result: [CGPoint] = []
        let count = 5
        for i in 0..<count {
            let f = CGFloat(i) / CGFloat(count - 1)          // 0...1
            let x = minX + width * f
            let arc = sin(f * .pi) * faceHeight * 0.05        // slight dome
            let y = max(0, foreheadY - arc)
            result.append(CGPoint(x: x, y: y))
        }
        return result
    }

    /// Canvas boundary anchors so edges stay still during the warp.
    static func boundaryAnchors(for size: CGSize) -> [CGPoint] {
        let w = size.width, h = size.height
        return [
            CGPoint(x: 0, y: 0),     CGPoint(x: w/4, y: 0),   CGPoint(x: w/2, y: 0),
            CGPoint(x: 3*w/4, y: 0), CGPoint(x: w, y: 0),
            CGPoint(x: w, y: h/2),
            CGPoint(x: w, y: h),     CGPoint(x: 3*w/4, y: h), CGPoint(x: w/2, y: h),
            CGPoint(x: w/4, y: h),   CGPoint(x: 0, y: h),
            CGPoint(x: 0, y: h/2)
        ]
    }

    private static func dedupe(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for p in points where !result.contains(where: { hypot($0.x - p.x, $0.y - p.y) < 1.0 }) {
            result.append(p)
        }
        return result
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
