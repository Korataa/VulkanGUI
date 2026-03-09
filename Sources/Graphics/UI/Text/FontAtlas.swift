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
        // TODO: Implement SDF generation - temporarily disabled for now
        print("FontAtlas.generate called - not yet implemented")
        return nil
    }
}