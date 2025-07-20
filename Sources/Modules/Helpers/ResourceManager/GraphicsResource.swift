import Foundation
import Cvulkan

/// Protocol for resources that are specifically related to graphics/GPU operations
public protocol GraphicsResource: Resource {
    var resourceType: GraphicsResourceType { get }
}

/// Types of graphics resources
public enum GraphicsResourceType {
    case buffer(GPUBufferUsage)  // Buffers specify their usage (vertex, uniform, etc)
    case texture                 // Uses VkImage, not direct buffer
    case shader                  // Uses VkShaderModule
    case other
}
