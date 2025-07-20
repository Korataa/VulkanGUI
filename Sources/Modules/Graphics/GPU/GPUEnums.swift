import Cvulkan

public struct GPUBufferUsage: OptionSet, Sendable {
    public let rawValue: Int

    static let Vertex               = GPUBufferUsage(rawValue: 1 << 0) //VK_BUFFER_USAGE_VERTEX_BUFFER_BIT
    static let Index                = GPUBufferUsage(rawValue: 1 << 1) //VK_BUFFER_USAGE_INDEX_BUFFER_BIT
    static let Uniform              = GPUBufferUsage(rawValue: 1 << 2) //VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT
    static let Storage              = GPUBufferUsage(rawValue: 1 << 3) //VK_BUFFER_BIT_USAGE_STORAGE_BUFFER_BIT
    static let TransferSrc          = GPUBufferUsage(rawValue: 1 << 4) //VK_BUFFER_USAGE_TRANSFER_SRC_BIT
    static let TransferDst          = GPUBufferUsage(rawValue: 1 << 5) //VK_BUFFER_USAGE_TRANSFER_DST_BIT
    static let Indirect             = GPUBufferUsage(rawValue: 1 << 6) //VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public func toVulkanFlags() -> VkBufferUsageFlags {
        var flags: VkBufferUsageFlags = 0

        if contains(.Vertex)        { flags |= UInt32(VK_BUFFER_USAGE_VERTEX_BUFFER_BIT.rawValue) }
        if contains(.Index)         { flags |= UInt32(VK_BUFFER_USAGE_INDEX_BUFFER_BIT.rawValue) }
        if contains(.Uniform)       { flags |= UInt32(VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT.rawValue) }
        if contains(.Storage)       { flags |= UInt32(VK_BUFFER_USAGE_STORAGE_BUFFER_BIT.rawValue) }
        if contains(.TransferSrc)   { flags |= UInt32(VK_BUFFER_USAGE_TRANSFER_SRC_BIT.rawValue) }
        if contains(.TransferDst)   { flags |= UInt32(VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue) }
        if contains(.Indirect)      { flags |= UInt32(VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT.rawValue) }

        return flags
    }

    static func |(lhs: GPUBufferUsage, rhs: GPUBufferUsage) -> GPUBufferUsage {
        return GPUBufferUsage(rawValue: lhs.rawValue | rhs.rawValue)
    }

    static func &(lhs: GPUBufferUsage, rhs: GPUBufferUsage) -> GPUBufferUsage {
        return GPUBufferUsage(rawValue: lhs.rawValue & rhs.rawValue)
    }
}

public struct GPUMemoryProperties: OptionSet, Sendable {
    public let rawValue: Int

    //MARK: - Memory Location types

    static let GPULocal         = GPUMemoryProperties(rawValue: 1 << 0) //VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
    static let CPUVisible       = GPUMemoryProperties(rawValue: 1 << 1) //VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
    static let CPUCoherent      = GPUMemoryProperties(rawValue: 1 << 2) //VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
    static let CPUCached        = GPUMemoryProperties(rawValue: 1 << 3) //VK_MEMORY_PROPERTY_HOST_CACHED_BIT
    static let LazilyAllocated  = GPUMemoryProperties(rawValue: 1 << 4) //VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT

    //Mark: - Combined memory types (for convenience)

    static let GPUOnly = GPUMemoryProperties([.GPULocal])

    ///for CPU -> GPU transfers (like staging buffers)
    static let GPUUpload = GPUMemoryProperties([.CPUVisible, .CPUCoherent])

    /// For gpu -> CPU reads (like screenshots or debug outputs)
    static let Readback = GPUMemoryProperties([.CPUVisible, .CPUCached])

    /// Useful on integrated GPUs where cpu and gpu share memory
    static let Shared = GPUMemoryProperties([.GPULocal, .CPUVisible, .CPUCoherent])

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public func toVulkanFlags() -> VkMemoryPropertyFlags {
        var flags: VkMemoryPropertyFlags = 0

        if contains(.GPULocal)       { flags |= UInt32(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue) }
        if contains(.CPUVisible)     { flags |= UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue) }
        if contains(.CPUCoherent)    { flags |= UInt32(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue) }
        if contains(.CPUCached)      { flags |= UInt32(VK_MEMORY_PROPERTY_HOST_CACHED_BIT.rawValue) }
        if contains(.LazilyAllocated) { flags |= UInt32(VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT.rawValue) }

        return flags
    }

    static func |(lhs: GPUMemoryProperties, rhs: GPUMemoryProperties) -> GPUMemoryProperties {
        return GPUMemoryProperties(rawValue: lhs.rawValue | rhs.rawValue)
    }

    static func &(lhs: GPUMemoryProperties, rhs: GPUMemoryProperties) -> GPUMemoryProperties {
        return GPUMemoryProperties(rawValue: lhs.rawValue & rhs.rawValue)
    }
}