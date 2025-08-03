import Foundation

/// Base protocol for all resources in the system
public protocol Resource: ~Copyable {
    /// Optional name for the resource (useful for debugging and asset management)
    var name: String? { get set }
    
    /// Unique identifier assigned by a resource manager
    var id: Int? { get set }
    
    /// The type category of this resource
    var resourceType: ResourceCategory { get }
    
    /// Clean up any resources held by this resource
    func cleanup()
}

/// General resource type categories
public enum ResourceCategory {
    case graphics(GraphicsResourceType)  // Graphics/GPU resources
    case audio                          // Audio resources
    case data                          // Data/configuration resources
    case other(String)                 // Custom resource types
}

/// Types of graphics resources
public enum GraphicsResourceType {
    case buffer(GPUBufferUsage)  // Buffers specify their usage (vertex, uniform, etc)
    case texture                 // Uses VkImage, not direct buffer
    case shader                  // Uses VkShaderModule
    case other
}