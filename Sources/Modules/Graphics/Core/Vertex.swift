import Cvulkan

public protocol VertexType {
    //size of the vertex in memory
    static var stride: Int { get }
    static func getBindingDescription() -> VkVertexInputBindingDescription
    static func getAttributeDescriptions() -> DynamicArray<VkVertexInputAttributeDescription>

}

public struct Vertex3D: VertexType {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var texCoord: SIMD2<Float>

    public static var stride: Int {
        return MemoryLayout<Vertex3D>.stride
    }
    
    public static func getBindingDescription() -> VkVertexInputBindingDescription {
        return VkVertexInputBindingDescription(
            binding: 0,
            stride: UInt32(MemoryLayout<Vertex3D>.stride),
            inputRate: VK_VERTEX_INPUT_RATE_VERTEX
        )
    }

    public static func getAttributeDescriptions() -> DynamicArray<VkVertexInputAttributeDescription> {
        var attributeDescriptions = DynamicArray<VkVertexInputAttributeDescription>()

        var positionAttribute = VkVertexInputAttributeDescription()
        positionAttribute.binding = 0
        positionAttribute.location = 0
        positionAttribute.format = VK_FORMAT_R32G32B32_SFLOAT
        positionAttribute.offset = UInt32(MemoryLayout<Vertex3D>.offset(of: \Vertex3D.position)!)
        attributeDescriptions.append(positionAttribute)

        var normalAttribute = VkVertexInputAttributeDescription()
        normalAttribute.binding = 0
        normalAttribute.location = 1
        normalAttribute.format = VK_FORMAT_R32G32B32_SFLOAT
        normalAttribute.offset = UInt32(MemoryLayout<Vertex3D>.offset(of: \Vertex3D.normal)!)
        attributeDescriptions.append(normalAttribute)

        var texCoordAttribute = VkVertexInputAttributeDescription()
        texCoordAttribute.binding = 0
        texCoordAttribute.location = 2
        texCoordAttribute.format = VK_FORMAT_R32G32_SFLOAT
        texCoordAttribute.offset = UInt32(MemoryLayout<Vertex3D>.offset(of: \Vertex3D.texCoord)!)
        attributeDescriptions.append(texCoordAttribute)

        return attributeDescriptions
    }
}

public struct Vertex2D {
    public var position: SIMD2<Float>
    public var texCoord: SIMD2<Float>
    public var color: Color

    public static var stride: Int {
        return MemoryLayout<Vertex2D>.stride
    }

    public static func getBindingDescription() -> VkVertexInputBindingDescription {
        return VkVertexInputBindingDescription(
            binding: 0,
            stride: UInt32(MemoryLayout<Vertex2D>.stride),
            inputRate: VK_VERTEX_INPUT_RATE_VERTEX
        )
    }

    public static func getAttributeDescriptions() -> DynamicArray<VkVertexInputAttributeDescription> {
        var attributeDescriptions = DynamicArray<VkVertexInputAttributeDescription>()

        var positionAttribute = VkVertexInputAttributeDescription()
        positionAttribute.binding = 0
        positionAttribute.location = 0
        positionAttribute.format = VK_FORMAT_R32G32_SFLOAT
        positionAttribute.offset = UInt32(MemoryLayout<Vertex2D>.offset(of: \Vertex2D.position)!)
        attributeDescriptions.append(positionAttribute)

        var texCoordAttribute = VkVertexInputAttributeDescription()
        texCoordAttribute.binding = 0
        texCoordAttribute.location = 1
        texCoordAttribute.format = VK_FORMAT_R32G32_SFLOAT
        texCoordAttribute.offset = UInt32(MemoryLayout<Vertex2D>.offset(of: \Vertex2D.texCoord)!)
        attributeDescriptions.append(texCoordAttribute)

        var colorAttribute = VkVertexInputAttributeDescription()
        colorAttribute.binding = 0
        colorAttribute.location = 2
        colorAttribute.format = VK_FORMAT_R32G32B32A32_SFLOAT
        colorAttribute.offset = UInt32(MemoryLayout<Vertex2D>.offset(of: \Vertex2D.color)!)
        attributeDescriptions.append(colorAttribute)

        return attributeDescriptions
    }
}