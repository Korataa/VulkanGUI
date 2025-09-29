import Foundation

/// Represents a 2D UI element or sprite that can be rendered
public class UIElement {
    public var position: SIMD2<Float>
    public var size: SIMD2<Float>
    public var color: Color
    public var textureID: UInt32?
    public var vertices: [Vertex2D]
    public var indices: [UInt32]
    
    public init(position: SIMD2<Float>, size: SIMD2<Float>, color: Color = Color.white, textureID: UInt32? = nil) {
        self.position = position
        self.size = size
        self.color = color
        self.textureID = textureID
        
        // Create a quad (2 triangles)
        self.vertices = UIElement.createQuadVertices(position: position, size: size, color: color)
        self.indices = [0, 1, 2, 0, 2, 3]  // Two triangles forming a quad
    }
    
    /// Create vertices for a quad
    private static func createQuadVertices(position: SIMD2<Float>, size: SIMD2<Float>, color: Color) -> [Vertex2D] {
        let halfWidth = size.x * 0.5
        let halfHeight = size.y * 0.5
        
        return [
            // Bottom-left
            Vertex2D(position: SIMD2(position.x - halfWidth, position.y - halfHeight), 
                     texCoord: SIMD2(0.0, 1.0), color: color),
            // Bottom-right  
            Vertex2D(position: SIMD2(position.x + halfWidth, position.y - halfHeight),
                     texCoord: SIMD2(1.0, 1.0), color: color),
            // Top-right
            Vertex2D(position: SIMD2(position.x + halfWidth, position.y + halfHeight),
                     texCoord: SIMD2(1.0, 0.0), color: color),
            // Top-left
            Vertex2D(position: SIMD2(position.x - halfWidth, position.y + halfHeight),
                     texCoord: SIMD2(0.0, 0.0), color: color)
        ]
    }
    
    /// Update the element's position or size
    public func updateTransform(position: SIMD2<Float>? = nil, size: SIMD2<Float>? = nil) {
        if let newPos = position { self.position = newPos }
        if let newSize = size { self.size = newSize }
        
        // Recreate vertices with new transform
        self.vertices = UIElement.createQuadVertices(position: self.position, size: self.size, color: self.color)
    }
}