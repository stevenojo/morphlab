//
//  Delaunay.swift
//  Bowyer-Watson triangulation returning index triples into the input points array.
//

import CoreGraphics

enum Delaunay {

    private struct Triangle: Hashable {
        let a: Int, b: Int, c: Int
        init(_ a: Int, _ b: Int, _ c: Int) {
            let s = [a, b, c].sorted()
            self.a = s[0]; self.b = s[1]; self.c = s[2]
        }
    }

    private struct Edge: Hashable {
        let a: Int, b: Int
        init(_ a: Int, _ b: Int) {
            if a < b { self.a = a; self.b = b } else { self.a = b; self.b = a }
        }
    }

    static func triangulate(points: [CGPoint], canvas: CGSize) -> [(Int, Int, Int)] {
        guard points.count >= 3 else { return [] }

        let margin = max(canvas.width, canvas.height) * 4
        let st0 = CGPoint(x: -margin, y: -margin)
        let st1 = CGPoint(x: canvas.width + margin, y: -margin)
        let st2 = CGPoint(x: canvas.width / 2, y: canvas.height + margin)

        var working = points
        let st0Idx = working.count; working.append(st0)
        let st1Idx = working.count; working.append(st1)
        let st2Idx = working.count; working.append(st2)

        var triangles: Set<Triangle> = [Triangle(st0Idx, st1Idx, st2Idx)]

        for i in 0..<points.count {
            let p = working[i]
            var bad: [Triangle] = []
            for tri in triangles where circumcircleContains(tri: tri, points: working, p: p) {
                bad.append(tri)
            }

            var edgeCount: [Edge: Int] = [:]
            for tri in bad {
                for e in [Edge(tri.a, tri.b), Edge(tri.b, tri.c), Edge(tri.c, tri.a)] {
                    edgeCount[e, default: 0] += 1
                }
            }
            let boundary = edgeCount.filter { $0.value == 1 }.map { $0.key }

            for tri in bad { triangles.remove(tri) }
            for e in boundary { triangles.insert(Triangle(e.a, e.b, i)) }
        }

        return triangles.compactMap { tri in
            guard tri.a < points.count, tri.b < points.count, tri.c < points.count else { return nil }
            return (tri.a, tri.b, tri.c)
        }
    }

    private static func circumcircleContains(tri: Triangle,
                                              points: [CGPoint],
                                              p: CGPoint) -> Bool {
        let a = points[tri.a], b = points[tri.b], c = points[tri.c]
        let ax = a.x - p.x, ay = a.y - p.y
        let bx = b.x - p.x, by = b.y - p.y
        let cx = c.x - p.x, cy = c.y - p.y

        let d = (ax*ax + ay*ay) * (bx*cy - cx*by)
              - (bx*bx + by*by) * (ax*cy - cx*ay)
              + (cx*cx + cy*cy) * (ax*by - bx*ay)

        let orient = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        return (orient > 0) ? (d > 0) : (d < 0)
    }
}
