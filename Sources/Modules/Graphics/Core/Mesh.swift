import Cgltf
import Cvma
import Cvulkan

import Foundation

//Doesnt need to conform to resource because Mesh doesnt own any gpu resources directly
//Lightweight metadata - can be shared between multiple models
public class Mesh {
    public var name: String?

    var vertexOffset: Int
    var vertexCount: Int
    var indexCount: Int
    var indexOffset: Int

    //Maybe not needed?? not sure yet, its the size of a single vertex in bytes
    var vertexStride: Int

    var primitiveType: PrimitiveType
    
    // Material ID for this mesh
    public var materialID: UInt32
    
    // Axis-aligned bounding box for the mesh
    public var bounds: BoundingBox

    init(
        vertexOffset: Int, vertexCount: Int, indexCount: Int, indexOffset: Int, 
        vertexStride: Int, primitiveType: PrimitiveType, materialID: UInt32, bounds: BoundingBox
    ) {
        self.vertexOffset = vertexOffset
        self.vertexCount = vertexCount
        self.indexCount = indexCount
        self.indexOffset = indexOffset
        self.vertexStride = vertexStride
        self.primitiveType = primitiveType
        self.materialID = materialID
        self.bounds = bounds
    }

    func bindBuffers(commandBuffer: VkCommandBuffer, rawVertexBuffer: VkBuffer, rawIndexBuffer: VkBuffer) {
        var vertexBuffers: [VkBuffer?] = [rawVertexBuffer]
        var offsets = [VkDeviceSize(vertexOffset * vertexStride)]
        vkCmdBindVertexBuffers(commandBuffer, 0, 1, &vertexBuffers, &offsets)
        vkCmdBindIndexBuffer(commandBuffer, rawIndexBuffer, VkDeviceSize(indexOffset * MemoryLayout<UInt32>.stride), VK_INDEX_TYPE_UINT32)
    }

    func draw(commandBuffer: VkCommandBuffer) {
        vkCmdDrawIndexed(commandBuffer, UInt32(indexCount), 1, UInt32(indexOffset), Int32(vertexOffset), 0)
    }
}

public final class StaticMesh: Mesh {
    //Static meshes dont change per frame usually
    //could maybe include material info, AABB, etc. ??
}

/// DynamicMesh is a mesh that can change its vertices and indices at runtime.
/// ALSO uses a seperate vertex buffer (from StaticMesh)
public final class DynamicMesh: Mesh {
    private var cpuVertices: DynamicArray<VertexType> = DynamicArray<VertexType>()
    private var cpuIndices: DynamicArray<UInt32> = DynamicArray<UInt32>()

    //Sets the vertices, transferring ownership of the provided  "DynamicArray" to the mesh
    func setVertices(newVertices: consuming DynamicArray<VertexType>) {
        cpuVertices = newVertices
        
        //TODO: update vertex count and offset
    }
}
public final class SkinnedMesh: Mesh {
    struct Joint {
        var name: String
        var parentIndex: Int  // -1 if root
        var localTransform: Matrix4x4
        var globalTransform: Matrix4x4
        var inverseBindMatrix: Matrix4x4
    }

    struct SkinWeight {
        var jointIndices: SIMD4<UInt8>  //up to 4 joints
        var weights: SIMD4<Float>  //sum = 1.0
    }

    var joints: [Joint] = []
    var jointMatrices: [Matrix4x4] = []  //final: global * inverseBind
    var skinWeights: [SkinWeight] = []

    override func bindBuffers(commandBuffer: VkCommandBuffer, rawVertexBuffer: VkBuffer, rawIndexBuffer: VkBuffer) {
        super.bindBuffers(commandBuffer: commandBuffer, rawVertexBuffer: rawVertexBuffer, rawIndexBuffer: rawIndexBuffer)
        
        //upload joint matrices to gpu buffer or push constants
    }

    func updateJointMatrices() {
        for i in joints.indices {
            let joint = joints[i]
            let parentTransform =
                (joint.parentIndex >= 0)
                ? joints[joint.parentIndex].globalTransform : Matrix4x4.identity()
            joints[i].globalTransform = parentTransform * joint.localTransform
            jointMatrices[i] = joints[i].globalTransform * joint.inverseBindMatrix
        }
    }
}
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
