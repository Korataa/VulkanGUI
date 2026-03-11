import Platform
import Core
import Foundation

/// Represents a 2D UI element or sprite that can be rendered
/// 
/// TODO: Memory optimization - Currently stores vertices on both CPU and GPU for flexibility.
/// This is fine for most games (UI data is tiny compared to 3D models), but could be optimized later:
/// - Static UI elements could store GPU offsets only (like static 3D models)
/// - Dynamic UI could use a write-only GPU buffer approach
/// - Only optimize if UI becomes a performance bottleneck (unlikely in 3D games)
public class UIRenderable {
    public var position: SIMD2<Float>
    public var size: SIMD2<Float>
    public var color: Color
    public var textureID: UInt32?
    public var usesSDF: Bool
    public var sdfThreshold: Float
    public var sdfRange: Float
    public var outlineWidth: Float
    public var outlineColor: Color
    public var baseOutlineWidth: Float
    public var glowStrength: Float
    public var glowSpeed: Float
    public var glowColor: Color
    public var glowWidth: Float
    public var shadowColor: Color
    public var shadowOffset: SIMD2<Float>
    public var reserved2: Float = 0.0 // MSDF selector for shader
    public var vertices: [Vertex2D]  // TODO: Could be optimized to GPU-only for static elements
    public var indices: [UInt32]

    // Smart caching system - same pattern as Mesh (store offsets, not BufferRegion)
    private var _isDirty: Bool = true
    private var _isUploaded: Bool = false

    // Buffer offsets (like Mesh does it)
    internal var vertexOffset: Int = 0
    internal var indexOffset: Int = 0

    public var isDirty: Bool { return _isDirty }
    public var isUploaded: Bool { return _isUploaded }

    public init(position: SIMD2<Float>, size: SIMD2<Float>, color: Color = Color.white, textureID: UInt32? = nil, usesSDF: Bool = false, sdfThreshold: Float = 0.5, sdfRange: Float = 4.0, outlineWidth: Float = 0.0, outlineColor: Color = .black, glowStrength: Float = 0.0, glowSpeed: Float = 0.0, glowColor: Color = Color(255,255,255,0), glowWidth: Float = 0.0, shadowColor: Color = Color(0,0,0,0), shadowOffset: SIMD2<Float> = SIMD2<Float>(0,0)) {
        self.position = position
        self.size = size
        self.color = color
        self.textureID = textureID
        self.usesSDF = usesSDF
        self.sdfThreshold = sdfThreshold
        self.sdfRange = sdfRange
        self.outlineWidth = outlineWidth
        self.outlineColor = outlineColor
        self.baseOutlineWidth = outlineWidth
        self.glowStrength = glowStrength
        self.glowSpeed = glowSpeed
        self.glowColor = glowColor
        self.glowWidth = glowWidth
        self.shadowColor = shadowColor
        self.shadowOffset = shadowOffset
        self.reserved2 = 0.0
        // Create a quad (2 triangles)
        self.vertices = UIRenderable.createQuadVertices(position: position, size: size, color: color)
        self.indices = [0, 1, 2, 0, 2, 3]  // Two triangles forming a quad
    }

    public init(
        position: SIMD2<Float>,
        size: SIMD2<Float>,
        color: Color = Color.white,
        textureID: UInt32? = nil,
        usesSDF: Bool = false,
        sdfThreshold: Float = 0.5,
        sdfRange: Float = 4.0,
        outlineWidth: Float = 0.0,
        outlineColor: Color = .black,
        glowStrength: Float = 0.0,
        glowSpeed: Float = 0.0,
        glowColor: Color = Color(255,255,255,0),
        glowWidth: Float = 0.0,
        shadowColor: Color = Color(0,0,0,0),
        shadowOffset: SIMD2<Float> = SIMD2<Float>(0,0),
        vertices: [Vertex2D],
        indices: [UInt32],
        reserved2: Float = 0.0
    ) {
        self.position = position
        self.size = size
        self.color = color
        self.textureID = textureID
        self.usesSDF = usesSDF
        self.sdfThreshold = sdfThreshold
        self.sdfRange = sdfRange
        self.outlineWidth = outlineWidth
        self.outlineColor = outlineColor
        self.baseOutlineWidth = outlineWidth
        self.glowStrength = glowStrength
        self.glowSpeed = glowSpeed
        self.glowColor = glowColor
        self.glowWidth = glowWidth
        self.shadowColor = shadowColor
        self.shadowOffset = shadowOffset
        self.vertices = vertices
        self.indices = indices
        self.reserved2 = reserved2
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
        self.vertices = UIRenderable.createQuadVertices(position: self.position, size: self.size, color: self.color)
        
        // Mark dirty for next frame
        markDirty()
    }
    
    /// Mark element as dirty (needs GPU upload)
    public func markDirty() {
        _isDirty = true
    }
    
    /// Mark element as clean (GPU buffer is up to date) - internal use only
    internal func markClean() {
        _isDirty = false
    }
    
    /// Mark as uploaded to GPU with buffer offsets - internal use only
    internal func markUploaded(vertexOffset: Int, indexOffset: Int) {
        self.vertexOffset = vertexOffset
        self.indexOffset = indexOffset
        _isUploaded = true
        _isDirty = false
    }
    
    /// Mark as not uploaded (when buffers are reset) - internal use only
    internal func markNotUploaded() {
        _isUploaded = false
        _isDirty = true
    }
    
    /// Get vertex offset in the 2D buffer (like Mesh does)
    internal func getVertexOffset() -> Int { return vertexOffset }
    
    /// Get index offset in the 2D buffer (like Mesh does) 
    internal func getIndexOffset() -> Int { return indexOffset }
}