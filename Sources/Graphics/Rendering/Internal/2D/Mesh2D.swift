import Platform
import Core
import Foundation
import Cvulkan

public enum PrimitiveType {
    case points
    case lines
    case lineStrip
    case triangles
    case triangleStrip

    var vkTopology: VkPrimitiveTopology {
        switch self {
        case .points: return VK_PRIMITIVE_TOPOLOGY_POINT_LIST
        case .lines: return VK_PRIMITIVE_TOPOLOGY_LINE_LIST
        case .lineStrip: return VK_PRIMITIVE_TOPOLOGY_LINE_STRIP
        case .triangles: return VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
        case .triangleStrip: return VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP
        }
    }
}

/// Mesh2D - lightweight GPU draw descriptor for 2D elements (screen-space).
///
/// Contract:
/// - `Mesh2D` is a minimal descriptor used at draw time. It contains offsets and counts
///   (vertex/index offsets and counts, stride, primitive type) and a material ID.
/// - `Mesh2D` does not own vertex/index data. It is typically constructed from a
///   `Renderable2D` after the renderable has been uploaded and its buffer offsets set.
/// - Do not attempt to access GPU data through a `Mesh2D` if the source renderable hasn't
///   been uploaded yet.
///
/// Mirrors Mesh but uses Vertex2D and screen coordinates
public final class Mesh2D {
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
    
    /// Create Mesh2D from Renderable2D data
    public convenience init(from renderable: Renderable2D) {
        self.init(
            vertexOffset: renderable.vertexOffset,
            vertexCount: renderable.vertices.count,
            indexCount: renderable.indices.count,
            indexOffset: renderable.indexOffset
        )
    }
}
