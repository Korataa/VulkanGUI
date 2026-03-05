import Platform
import Core
import Foundation
import Cvulkan
import Cvma

/// GPU-side material data layout that matches shader expectations
public struct MaterialData {
    var baseColor: (Float, Float, Float, Float)  // vec4 in shader
    var emissiveColor: (Float, Float, Float)     // vec3 in shader
    var metallicFactor: Float
    var roughnessFactor: Float
    var normalScale: Float
    var occlusionStrength: Float
    var alphaCutoff: Float
    var flags: UInt32    // Bit flags for various material properties
    
    // Texture indices (correspond to descriptor set bindings)
    var baseColorTexIndex: Int32
    var metallicRoughnessTexIndex: Int32
    var normalTexIndex: Int32
    var occlusionTexIndex: Int32
    var emissiveTexIndex: Int32
}

/// Handles uploading material data to GPU memory and managing its lifecycle
/// Vulkan-specific implementation for maximum performance
public final class VulkanMaterialUploader {
    private let buffer: VulkanBuffer
    
    public init(vmaAllocator: VmaAllocator) {
        buffer = VulkanBuffer(
            vmaAllocator: vmaAllocator,
            size: UInt64(MemoryLayout<MaterialData>.stride),
            usage: .Uniform,
            properties: .CPUVisible, // Allows CPU writes
            isDynamic: false
        )
    }
    
    /// Update GPU memory with new material data
    public func update(from material: Material) {
        var data = MaterialData(
            baseColor: (
                material.baseColor.linearR,
                material.baseColor.linearG,
                material.baseColor.linearB,
                material.isOpaque ? 1.0 : material.alphaCutoff
            ),
            emissiveColor: (
                material.emissiveColor.linearR,
                material.emissiveColor.linearG,
                material.emissiveColor.linearB
            ),
            metallicFactor: material.metallicFactor,
            roughnessFactor: material.roughnessFactor,
            normalScale: material.normalScale,
            occlusionStrength: material.occlusionStrength,
            alphaCutoff: material.alphaCutoff,
            flags: createMaterialFlags(material),
            baseColorTexIndex: Int32(material.baseColorTextureIndex ?? -1),
            metallicRoughnessTexIndex: Int32(material.metallicRoughnessTextureIndex ?? -1),
            normalTexIndex: Int32(material.normalTextureIndex ?? -1),
            occlusionTexIndex: Int32(material.occlusionTextureIndex ?? -1),
            emissiveTexIndex: Int32(material.emissiveTextureIndex ?? -1)
        )
        
        buffer.uploadData(data: &data, size: MemoryLayout<MaterialData>.size)
    }
    
    private func createMaterialFlags(_ material: Material) -> UInt32 {
        var flags: UInt32 = 0
        
        // Set material type flags
        switch material.type {
        case .PBR:          flags |= 1 << 0
        case .Unlit:        flags |= 1 << 1
        case .Translucent:  flags |= 1 << 2
        case .Masked:       flags |= 1 << 3
        case .Emissive:     flags |= 1 << 4
        case .Custom:       flags |= 1 << 5
        }
        
        // Set texture presence flags
        if material.baseColorTextureIndex != nil { flags |= 1 << 8 }
        if material.metallicRoughnessTextureIndex != nil { flags |= 1 << 9 }
        if material.normalTextureIndex != nil { flags |= 1 << 10 }
        if material.occlusionTextureIndex != nil { flags |= 1 << 11 }
        if material.emissiveTextureIndex != nil { flags |= 1 << 12 }
        
        return flags
    }
    
    /// Get the raw Vulkan handle when needed for low-level operations
    public var vulkanBuffer: VkBuffer {
        if case .Vulkan(let handle) = buffer.bufferHandle {
            return handle
        }
        fatalError("Invalid buffer handle type")
    }
    
    public func cleanup() {
        buffer.cleanup()
    }
}
