import Cstb_truetype
import Math
import Foundation

public struct GlyphInfo {
    public let uvRect: Rectangle
    public let size: Vector2
    public let bearing: Vector2
    public let advance: Float
    public let distanceRange: Float
    
    public init(uvRect: Rectangle, size: Vector2, bearing: Vector2, advance: Float, distanceRange: Float) {
        self.uvRect = uvRect
        self.size = size
        self.bearing = bearing
        self.advance = advance
        self.distanceRange = distanceRange
    }
}

public struct FontAtlas {
    public let textureData: [UInt8]
    public let textureWidth: Int
    public let textureHeight: Int
    public let glyphs: [Character: GlyphInfo]
    public let fontSize: Float
    public let distanceRange: Float
    
    public init(textureData: [UInt8], textureWidth: Int, textureHeight: Int, 
                glyphs: [Character: GlyphInfo], fontSize: Float, distanceRange: Float) {
        self.textureData = textureData
        self.textureWidth = textureWidth
        self.textureHeight = textureHeight
        self.glyphs = glyphs
        self.fontSize = fontSize
        self.distanceRange = distanceRange
    }
    
    /// Generate SDF font atlas from TTF font data
    public static func generate(from fontData: Data, fontSize: Float = 48.0, 
                               atlasSize: Int = 512, distanceRange: Float = 4.0) -> FontAtlas? {
        guard atlasSize > 0, fontSize > 0, distanceRange > 0 else {
            print("FontAtlas.generate: invalid parameters")
            return nil
        }

        var texture = [UInt8](repeating: 0, count: atlasSize * atlasSize)
        var glyphMap: [Character: GlyphInfo] = [:]

        let glyphPadding = Int(max(2.0, ceil(Double(distanceRange))))
        // Standard midpoint threshold for SDF reconstruction in shader.
        let onEdgeValue: UInt8 = 128
        let pixelDistanceScale = Float(onEdgeValue) / distanceRange

        var cursorX = 0
        var cursorY = 0
        var rowHeight = 0

        let ok: Bool = fontData.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }

            var fontInfo = stbtt_fontinfo()
            let fontOffset = stbtt_GetFontOffsetForIndex(base, 0)
            if fontOffset < 0 {
                print("FontAtlas.generate: failed to find font offset")
                return false
            }

            guard stbtt_InitFont(&fontInfo, base, fontOffset) != 0 else {
                print("FontAtlas.generate: stbtt_InitFont failed")
                return false
            }

            let scale = stbtt_ScaleForPixelHeight(&fontInfo, fontSize)

            for codepoint in 32...126 {
                let scalar = UnicodeScalar(codepoint)!
                let character = Character(scalar)

                var glyphWidth: Int32 = 0
                var glyphHeight: Int32 = 0
                var xOff: Int32 = 0
                var yOff: Int32 = 0

                let sdfPtr = stbtt_GetCodepointSDF(
                    &fontInfo,
                    scale,
                    Int32(codepoint),
                    Int32(glyphPadding),
                    onEdgeValue,
                    pixelDistanceScale,
                    &glyphWidth,
                    &glyphHeight,
                    &xOff,
                    &yOff
                )

                var advanceWidth: Int32 = 0
                var leftSideBearing: Int32 = 0
                stbtt_GetCodepointHMetrics(&fontInfo, Int32(codepoint), &advanceWidth, &leftSideBearing)
                let advancePixels = Float(advanceWidth) * scale

                guard let sdfPtr else {
                    glyphMap[character] = GlyphInfo(
                        uvRect: Rectangle.zero,
                        size: Vector2(0, 0),
                        bearing: Vector2(Float(leftSideBearing) * scale, 0),
                        advance: advancePixels,
                        distanceRange: distanceRange
                    )
                    continue
                }

                defer {
                    stbtt_FreeSDF(sdfPtr, nil)
                }

                let width = Int(glyphWidth)
                let height = Int(glyphHeight)
                if width <= 0 || height <= 0 {
                    glyphMap[character] = GlyphInfo(
                        uvRect: Rectangle.zero,
                        size: Vector2(0, 0),
                        bearing: Vector2(Float(xOff), Float(yOff)),
                        advance: advancePixels,
                        distanceRange: distanceRange
                    )
                    continue
                }

                if cursorX + width > atlasSize {
                    cursorX = 0
                    cursorY += rowHeight + 1
                    rowHeight = 0
                }

                if cursorY + height > atlasSize {
                    print("FontAtlas.generate: atlas overflow at glyph '\(character)'")
                    return false
                }

                for y in 0..<height {
                    let srcRow = sdfPtr.advanced(by: y * width)
                    let dstRow = (cursorY + y) * atlasSize + cursorX
                    texture.withUnsafeMutableBufferPointer { dst in
                        for x in 0..<width {
                            dst[dstRow + x] = srcRow[x]
                        }
                    }
                }

                let uvRect = Rectangle(
                    position: Vector2(
                        Float(cursorX) / Float(atlasSize),
                        Float(cursorY) / Float(atlasSize)
                    ),
                    width: Float(width) / Float(atlasSize),
                    height: Float(height) / Float(atlasSize)
                )

                glyphMap[character] = GlyphInfo(
                    uvRect: uvRect,
                    size: Vector2(Float(width), Float(height)),
                    bearing: Vector2(Float(xOff), Float(yOff)),
                    advance: advancePixels,
                    distanceRange: distanceRange
                )

                cursorX += width + 1
                rowHeight = max(rowHeight, height)
            }

            return true
        }

        guard ok else {
            return nil
        }

        return FontAtlas(
            textureData: texture,
            textureWidth: atlasSize,
            textureHeight: atlasSize,
            glyphs: glyphMap,
            fontSize: fontSize,
            distanceRange: distanceRange
        )
    }
}