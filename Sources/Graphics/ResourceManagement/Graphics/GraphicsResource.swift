import Platform
import Core
/*
// Example concrete graphics resource: Texture
public struct TextureResource: ~Copyable, GraphicsResource {
    public var name: String?
    public var id: Int?
    public let graphicsType: GraphicsResourceType = .texture
    public let image: VkImage
    public let imageView: VkImageView
    public let width: Int
    public let height: Int
    public let mipLevels: Int

    public func cleanup() {
        // Implement Vulkan cleanup for image/imageView here
    }
}

// Example concrete graphics resource: Buffer
public struct BufferResource: ~Copyable, GraphicsResource {
    public var name: String?
    public var id: Int?
    public let graphicsType: GraphicsResourceType
    public let buffer: VkBuffer
    public let size: Int

    public func cleanup() {
        // Implement Vulkan cleanup for buffer here
    }
}

// Example concrete graphics resource: Shader
public struct ShaderResource: ~Copyable, GraphicsResource {
    public var name: String?
    public var id: Int?
    public let graphicsType: GraphicsResourceType = .shader
    public let shaderModule: VkShaderModule

    public func cleanup() {
        // Implement Vulkan cleanup for shader module here
    }
}
*/
import Foundation
import Cvulkan

/// Protocol for resources that are specifically related to graphics/GPU operations
public protocol GraphicsResource: Resource & ~Copyable {
    // GraphicsResource-specific
    var graphicsType: GraphicsResourceType { get }
}

public extension GraphicsResource {
    var resourceType: ResourceCategory {
        return .graphics(graphicsType)
    }
}