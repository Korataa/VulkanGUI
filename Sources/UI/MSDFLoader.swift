import Foundation
import Core
import Math
import Graphics
import Cstb_image

struct MSDFLoader {
    private struct AtlasJSON: Decodable {
        struct AtlasMeta: Decodable {
            let type: String?
            let size: Float
            let width: Int
            let height: Int
            let distanceRange: Float?
            let pxRange: Float?
        }

        struct Bounds: Decodable {
            let left: Float
            let bottom: Float
            let right: Float
            let top: Float
        }

        struct Glyph: Decodable {
            let unicode: Int
            let advance: Float
            let planeBounds: Bounds?
            let atlasBounds: Bounds?
        }

        let atlas: AtlasMeta
        let glyphs: [Glyph]
    }

    static func load(fromJSON jsonPath: String, imagePath: String) -> (atlas: FontAtlas, rgbaPixels: [UInt8], width: Int, height: Int)? {
        guard let jsonData = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)) else {
            print("MSDFLoader: failed to read JSON at \(jsonPath)")
            return nil
        }

        let decoder = JSONDecoder()
        guard let parsed = try? decoder.decode(AtlasJSON.self, from: jsonData) else {
            print("MSDFLoader: failed to decode JSON")
            return nil
        }

        guard let (pixels, width, height) = loadRGBAImage(from: imagePath) else {
            print("MSDFLoader: failed to load PNG atlas at \(imagePath)")
            return nil
        }

        let fontSize = parsed.atlas.size
        let atlasWidth = Float(parsed.atlas.width)
        let atlasHeight = Float(parsed.atlas.height)
        let distanceRange = parsed.atlas.distanceRange ?? parsed.atlas.pxRange ?? 4.0

        var glyphs: [Character: GlyphInfo] = [:]
        glyphs.reserveCapacity(parsed.glyphs.count)

        for glyph in parsed.glyphs {
            guard let scalar = UnicodeScalar(glyph.unicode) else { continue }
            let ch = Character(scalar)

            if let plane = glyph.planeBounds, let atlas = glyph.atlasBounds {
                // msdf-atlas-gen plane coordinates are Y-up; our UI space is Y-down.
                let bearing = Vector2(plane.left * fontSize, -plane.top * fontSize)
                let size = Vector2((plane.right - plane.left) * fontSize,
                                   (plane.top - plane.bottom) * fontSize)

                // JSON atlas bounds are bottom-left origin; texture sampling here uses top-left UV origin.
                let u0 = atlas.left / atlasWidth
                let u1 = atlas.right / atlasWidth
                let v0 = 1.0 - (atlas.top / atlasHeight)
                let v1 = 1.0 - (atlas.bottom / atlasHeight)
                let uvRect = Rectangle(
                    position: Vector2(u0, v0),
                    width: u1 - u0,
                    height: v1 - v0
                )

                glyphs[ch] = GlyphInfo(
                    uvRect: uvRect,
                    size: size,
                    bearing: bearing,
                    advance: glyph.advance * fontSize,
                    distanceRange: distanceRange
                )
            } else {
                glyphs[ch] = GlyphInfo(
                    uvRect: Rectangle.zero,
                    size: Vector2(0, 0),
                    bearing: Vector2(0, 0),
                    advance: glyph.advance * fontSize,
                    distanceRange: distanceRange
                )
            }
        }

        let atlas = FontAtlas(
            textureData: [],
            textureWidth: width,
            textureHeight: height,
            glyphs: glyphs,
            fontSize: fontSize,
            distanceRange: distanceRange
        )

        return (atlas, pixels, width, height)
    }

    private static func loadRGBAImage(from path: String) -> ([UInt8], Int, Int)? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        var width: Int32 = 0
        var height: Int32 = 0
        var channels: Int32 = 0

        let pixelsPtr = data.withUnsafeBytes { rawBufferPtr -> UnsafeMutablePointer<UInt8>? in
            let base = rawBufferPtr.bindMemory(to: UInt8.self).baseAddress
            return stbi_load_from_memory(base, Int32(data.count), &width, &height, &channels, 4)
        }

        guard let pixelsPtr else { return nil }
        defer { stbi_image_free(pixelsPtr) }

        let count = Int(width * height * 4)
        let pixels = Array(UnsafeBufferPointer(start: pixelsPtr, count: count))
        return (pixels, Int(width), Int(height))
    }
}
