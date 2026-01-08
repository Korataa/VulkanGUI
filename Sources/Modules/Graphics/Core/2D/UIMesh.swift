import Foundation
import Cvulkan

/// MeshUI - 2D mesh for UI elements (screen-space)
/// Mirrors Mesh but uses Vertex2D and screen coordinates
public final class MeshUI {
    public var name: String?
    
    var vertexOffset: Int
    var vertexCount: Int
    var indexCount: Int
    var indexOffset: Int
    var vertexStride: Int
    var primitiveType: PrimitiveType
    public var materialID: UInt32
    
    public init(
        vertexOffset: Int, 
        vertexCount: Int, 
        indexCount: Int, 
        indexOffset: Int,
        vertexStride: Int = MemoryLayout<Vertex2D>.stride,
        primitiveType: PrimitiveType = .triangles,
        materialID: UInt32 = 0
    ) {
        self.vertexOffset = vertexOffset
        self.vertexCount = vertexCount
        self.indexCount = indexCount
        self.indexOffset = indexOffset
        self.vertexStride = vertexStride
        self.primitiveType = primitiveType
        self.materialID = materialID
    }
    
    /// Create MeshUI from UIRenderable data
    public convenience init(from renderable: UIRenderable) {
        self.init(
            vertexOffset: renderable.vertexOffset,
            vertexCount: renderable.vertices.count,
            indexCount: renderable.indices.count,
            indexOffset: renderable.indexOffset
        )
    }
}