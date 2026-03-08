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
        // This is where you'll implement the SDF generation
        // For now, let's create a placeholder that you can fill in
        
        return fontData.withUnsafeBytes { bytes in
            guard let fontPtr = bytes.bindMemory(to: UInt8.self).baseAddress else { return nil }
            
            // Initialize stb_truetype
            var fontInfo = stbtt_fontinfo()
            guard stbtt_InitFont(&fontInfo, fontPtr, 0) != 0 else {
                print("Failed to initialize font")
                return nil
            }
            
            // Calculate scale for desired pixel height
            let scale = stbtt_ScaleForPixelHeight(&fontInfo, fontSize)
            
            // Get font metrics
            var ascent: Int32 = 0, descent: Int32 = 0, lineGap: Int32 = 0
            stbtt_GetFontVMetrics(&fontInfo, &ascent, &descent, &lineGap)
            
            print("Font metrics - Scale: \(scale), Ascent: \(ascent), Descent: \(descent)")
            
            // Character set - ASCII printable characters for now
            let charRange = Character(" ")...Character("~")
            var glyphs: [Character: GlyphInfo] = [:]
            
            // Simple atlas packing - arrange in grid for now
            let atlasData = Array(repeating: UInt8(128), count: atlasSize * atlasSize) // Middle gray = distance 0
            
            // TODO: Implement actual SDF generation and packing
            // For now, create placeholder glyph info
            let glyphSize = Vector2(Float(fontSize * 0.7), Float(fontSize))
            let uvSize = Vector2(glyphSize.x / Float(atlasSize), glyphSize.y / Float(atlasSize))
            
            for (index, char) in charRange.enumerated() {
                let codepoint = Int32(char.asciiValue ?? 32)
                
                // Get glyph metrics
                var advanceWidth: Int32 = 0, leftSideBearing: Int32 = 0
                stbtt_GetCodepointHMetrics(&fontInfo, codepoint, &advanceWidth, &leftSideBearing)
                
                // Simple grid layout for now
                let col = index % 16
                let row = index / 16
                let x = Float(col) / 16.0
                let y = Float(row) / 16.0
                
                let glyph = GlyphInfo(
                    uvRect: Rectangle(position: Vector2(x, y), width: uvSize.x, height: uvSize.y),
                    size: glyphSize,
                    bearing: Vector2(Float(leftSideBearing) * scale, Float(ascent) * scale),
                    advance: Float(advanceWidth) * scale,
                    distanceRange: distanceRange
                )
                
                glyphs[char] = glyph
            }
            
            return FontAtlas(
                textureData: atlasData,
                textureWidth: atlasSize,
                textureHeight: atlasSize,
                glyphs: glyphs,
                fontSize: fontSize,
                distanceRange: distanceRange
            )
        }
    }
}