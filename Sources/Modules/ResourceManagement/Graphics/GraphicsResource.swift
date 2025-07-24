import Foundation
import Cvulkan

/// Protocol for resources that are specifically related to graphics/GPU operations
public protocol GraphicsResource: ~Copyable, Resource {
    // resourceType is inherited from Resource and should return .graphics(GraphicsResourceType)
}
