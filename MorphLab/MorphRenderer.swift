//
//  MorphRenderer.swift
//  Per-triangle warp + cross-dissolve via Metal, rendering into CVPixelBuffer.
//

import UIKit
import Metal
import CoreVideo

final class MorphRenderer {

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var textureCache: CVMetalTextureCache!

    private(set) var lastPreview: UIImage?

    struct Vertex {
        var pos: SIMD2<Float>
        var uvA: SIMD2<Float>
        var uvB: SIMD2<Float>
    }

    struct Uniforms {
        var canvasSize: SIMD2<Float>
        var t: Float
        var _pad: Float = 0
    }

    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            fatalError("Metal unavailable")
        }
        self.device = device
        self.queue = queue

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: MorphRenderer.shaderSource, options: nil)
        } catch {
            fatalError("Shader compile failed: \(error)")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "morph_vertex")!
        desc.fragmentFunction = library.makeFunction(name: "morph_fragment")!
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float2; vd.attributes[0].offset = 0;  vd.attributes[0].bufferIndex = 0
        vd.attributes[1].format = .float2; vd.attributes[1].offset = 8;  vd.attributes[1].bufferIndex = 0
        vd.attributes[2].format = .float2; vd.attributes[2].offset = 16; vd.attributes[2].bufferIndex = 0
        vd.layouts[0].stride = MemoryLayout<Vertex>.stride
        desc.vertexDescriptor = vd

        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Pipeline creation failed: \(error)")
        }

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        self.sampler = device.makeSamplerState(descriptor: sd)!

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    func makeTexture(from image: UIImage) -> MTLTexture? {
        texture(from: image)
    }

    func renderFrame(imageA: UIImage,
                     imageB: UIImage,
                     pointsA: [CGPoint],
                     pointsB: [CGPoint],
                     triangles: [(Int, Int, Int)],
                     t: CGFloat,
                     size: CGSize) -> CVPixelBuffer? {

        guard let texA = texture(from: imageA),
              let texB = texture(from: imageB) else { return nil }
        return renderFrame(texA: texA, texB: texB,
                           pointsA: pointsA, pointsB: pointsB,
                           triangles: triangles, t: t, size: size)
    }

    func renderFrame(texA: MTLTexture,
                     texB: MTLTexture,
                     pointsA: [CGPoint],
                     pointsB: [CGPoint],
                     triangles: [(Int, Int, Int)],
                     t: CGFloat,
                     size: CGSize) -> CVPixelBuffer? {

        var verts: [Vertex] = []
        verts.reserveCapacity(triangles.count * 3)
        let w = Float(size.width), h = Float(size.height)

        for (ia, ib, ic) in triangles {
            for idx in [ia, ib, ic] {
                let pa = pointsA[idx]
                let pb = pointsB[idx]
                let pmx = Float(pa.x) * (1 - Float(t)) + Float(pb.x) * Float(t)
                let pmy = Float(pa.y) * (1 - Float(t)) + Float(pb.y) * Float(t)
                verts.append(Vertex(
                    pos: SIMD2<Float>(pmx, pmy),
                    uvA: SIMD2<Float>(Float(pa.x) / w, Float(pa.y) / h),
                    uvB: SIMD2<Float>(Float(pb.x) / w, Float(pb.y) / h)
                ))
            }
        }
        guard !verts.isEmpty else { return nil }
        let vbuf = device.makeBuffer(bytes: verts,
                                     length: verts.count * MemoryLayout<Vertex>.stride,
                                     options: [])!

        var uniforms = Uniforms(canvasSize: SIMD2<Float>(w, h), t: Float(t))
        let ubuf = device.makeBuffer(bytes: &uniforms,
                                     length: MemoryLayout<Uniforms>.stride,
                                     options: [])!

        guard let (pb, outTex) = makePixelBufferAndTexture(size: size) else { return nil }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = outTex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        rpd.colorAttachments[0].storeAction = .store

        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return nil }

        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(vbuf, offset: 0, index: 0)
        enc.setVertexBuffer(ubuf, offset: 0, index: 1)
        enc.setFragmentBuffer(ubuf, offset: 0, index: 0)
        enc.setFragmentTexture(texA, index: 0)
        enc.setFragmentTexture(texB, index: 1)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        if let cgImg = cgImage(from: pb) {
            self.lastPreview = UIImage(cgImage: cgImg)
        }
        return pb
    }

    private func texture(from image: UIImage) -> MTLTexture? {
        guard let src = image.cgImage else { return nil }
        let w = src.width, h = src.height
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue |
                         CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: bitmapInfo),
              let data = ctx.data else { return nil }
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        tex.replace(region: MTLRegion(origin: .init(),
                                      size: .init(width: w, height: h, depth: 1)),
                    mipmapLevel: 0, withBytes: data, bytesPerRow: w * 4)
        return tex
    }

    private func makePixelBufferAndTexture(size: CGSize) -> (CVPixelBuffer, MTLTexture)? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width), Int(size.height),
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary, &pb)
        guard status == kCVReturnSuccess, let pixelBuffer = pb else { return nil }

        var cvTex: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .bgra8Unorm, Int(size.width), Int(size.height), 0, &cvTex
        )
        guard let cvTexture = cvTex,
              let metalTex = CVMetalTextureGetTexture(cvTexture) else { return nil }
        return (pixelBuffer, metalTex)
    }

    private func cgImage(from pb: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pb)
        return CIContext(options: nil).createCGImage(ci, from: ci.extent)
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float2 pos  [[attribute(0)]];
        float2 uvA  [[attribute(1)]];
        float2 uvB  [[attribute(2)]];
    };
    struct VertexOut {
        float4 position [[position]];
        float2 uvA;
        float2 uvB;
    };
    struct Uniforms {
        float2 canvasSize;
        float t;
        float _pad;
    };

    vertex VertexOut morph_vertex(VertexIn in [[stage_in]],
                                   constant Uniforms &u [[buffer(1)]]) {
        VertexOut out;
        float2 ndc;
        ndc.x = (in.pos.x / u.canvasSize.x) * 2.0 - 1.0;
        ndc.y = 1.0 - (in.pos.y / u.canvasSize.y) * 2.0;
        out.position = float4(ndc, 0.0, 1.0);
        out.uvA = in.uvA;
        out.uvB = in.uvB;
        return out;
    }

    fragment float4 morph_fragment(VertexOut in [[stage_in]],
                                    constant Uniforms &u [[buffer(0)]],
                                    texture2d<float> texA [[texture(0)]],
                                    texture2d<float> texB [[texture(1)]],
                                    sampler samp [[sampler(0)]]) {
        float4 ca = texA.sample(samp, in.uvA);
        float4 cb = texB.sample(samp, in.uvB);
        return mix(ca, cb, u.t);
    }
    """
}
