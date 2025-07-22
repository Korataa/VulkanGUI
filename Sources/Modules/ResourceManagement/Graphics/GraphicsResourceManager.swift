import Foundation
import Cvulkan
import Cvma

public class GraphicsResourceManager: ResourceManager {
    public typealias ManagedResource = GraphicsResource
    private let device: VkDevice
    private let vmaAllocator: VmaAllocator

    // Resource tracking
    private var resources: [Int: GraphicsResource] = [:]
    private var nextResourceId: Int = 0
    
    // Buffer management
    public var staticVertexBuffer: GPUBuffer?
    public var dynamicVertexBuffer: GPUBuffer?
    public var transferBuffer: GPUBuffer?
    public var indexBuffer: GPUBuffer?
    
    // Memory tracking
    private let totalVRAM: UInt64         // Total GPU memory available
    private var availableVRAM: UInt64     // Current allocation limit (starts at 10% of total)
    private var usedVRAM: UInt64 = 0      // Actually used VRAM
    
    // Buffer offsets
    private var staticVertexOffset: Int = 0
    private var dynamicVertexOffset: Int = 0
    private var indexOffset: Int = 0
    
    // Growth threshold - when to increase available VRAM (80% of current available)
    private let growthThreshold: Double = 0.8
    
    public init(device: VkDevice, vmaAllocator: VmaAllocator, totalVRAM: UInt64) {
        self.device = device
        self.vmaAllocator = vmaAllocator
        self.totalVRAM = totalVRAM
        self.availableVRAM = totalVRAM / 10  // Start with 10% of total VRAM
    }
    
    private func checkAndGrowVRAM(requiredSize: UInt64) throws {
        // Check if we're near the threshold or need more space
        if (usedVRAM + requiredSize) >= UInt64(Double(availableVRAM) * growthThreshold) {
            // Calculate new available VRAM (double current, but don't exceed total)
            let newAvailable = min(availableVRAM * 2, totalVRAM)
            
            // If we can't grow anymore and don't have enough space, throw error
            if newAvailable == availableVRAM && (usedVRAM + requiredSize) > availableVRAM {
                throw BufferError.outOfVRAM
            }
            
            availableVRAM = newAvailable
        }
    }
    
    private func updateVRAMUsage(delta: Int64) throws {
        let newUsage = Int64(usedVRAM) + delta
        
        // If we're adding memory (delta > 0)
        if delta > 0 {
            try checkAndGrowVRAM(requiredSize: UInt64(delta))
        }
        
        // Update used VRAM (allow negative delta for memory freeing)
        usedVRAM = UInt64(max(0, newUsage))
    }
    
    public func initialize() throws {
        // Create buffers
        try createStaticVertexBuffer()
        try createDynamicVertexBuffer()
        try createIndexBuffer()
        try createTransferBuffer()
    }
    
    // Initial buffer size percentages (buffers can grow independently during runtime)
    private let initialStaticVertexPercent: Double = 0.5  // Starts at 50% of initial VRAM
    private let initialDynamicVertexPercent: Double = 0.2 // Starts at 20% of initial VRAM
    private let initialIndexBufferPercent: Double = 0.2   // Starts at 20% of initial VRAM
    private let initialTransferPercent: Double = 0.1      // Starts at 10% of initial VRAM
    
    private func createStaticVertexBuffer() throws {
        let size = UInt64(Double(availableVRAM) * initialStaticVertexPercent)
        staticVertexBuffer = VulkanBuffer(
            vmaAllocator: vmaAllocator,
            size: size,
            usage: .Vertex,
            properties: .GPULocal
        )
        staticVertexOffset = 0
    }
    
    private func createDynamicVertexBuffer() throws {
        let size = UInt64(Double(availableVRAM) * initialDynamicVertexPercent)
        dynamicVertexBuffer = VulkanBuffer(
            vmaAllocator: vmaAllocator,
            size: size,
            usage: .Vertex,
            properties: [.CPUVisible, .CPUCoherent],
            isDynamic: true
        )
        dynamicVertexOffset = 0
    }
    
    private func createIndexBuffer() throws {
        let size = UInt64(Double(availableVRAM) * initialIndexBufferPercent)
        indexBuffer = VulkanBuffer(
            vmaAllocator: vmaAllocator,
            size: size,
            usage: .Index,
            properties: .GPULocal
        )
        indexOffset = 0
    }
    
    private func createTransferBuffer() throws {
        let size = UInt64(Double(availableVRAM) * initialTransferPercent)
        transferBuffer = VulkanBuffer(
            vmaAllocator: vmaAllocator,
            size: size,
            usage: .TransferSrc,
            properties: .GPUUpload
        )
    }
    
    public enum BufferType {
        case staticVertex
        case dynamicVertex
        case index
        case transfer
        
        var buffer: (GraphicsResourceManager) -> GPUBuffer? {
            switch self {
            case .staticVertex: return { $0.staticVertexBuffer }
            case .dynamicVertex: return { $0.dynamicVertexBuffer }
            case .index: return { $0.indexBuffer }
            case .transfer: return { $0.transferBuffer }
            }
        }
        
        var offset: (GraphicsResourceManager) -> Int {
            switch self {
            case .staticVertex: return { $0.staticVertexOffset }
            case .dynamicVertex: return { $0.dynamicVertexOffset }
            case .index: return { $0.indexOffset }
            case .transfer: return { _ in 0 } // Transfer buffer doesn't need offset tracking
            }
        }
        
        var setOffset: (GraphicsResourceManager, Int) -> Void {
            switch self {
            case .staticVertex: return { $0.staticVertexOffset = $1 }
            case .dynamicVertex: return { $0.dynamicVertexOffset = $1 }
            case .index: return { $0.indexOffset = $1 }
            case .transfer: return { _, _ in } // Transfer buffer doesn't track offset
            }
        }
    }
    
    public func allocateRegion(type: BufferType, size: Int, alignment: Int = 16) throws -> BufferRegion {
        guard let buffer = type.buffer(self) else {
            throw BufferError.notInitialized
        }
        
        let currentOffset = type.offset(self)
        let alignedOffset = (currentOffset + alignment - 1) / alignment * alignment
        
        guard alignedOffset + size <= Int(buffer.size) else {
            throw BufferError.outOfSpace
        }
        
        type.setOffset(self, alignedOffset + size)
        try updateVRAMUsage(delta: Int64(size))
        
        return BufferRegion(offset: alignedOffset, size: size, buffer: buffer)
    }

    public func resetBuffer(type: BufferType) {
        switch type {
        case .staticVertex: staticVertexOffset = 0
        case .dynamicVertex: dynamicVertexOffset = 0
        case .index: indexOffset = 0
        case .transfer: break // Transfer buffer doesn't track offset
    }
}
    
    // MARK: - Graphics Resource Management
    
    public func addResource(_ resource: GraphicsResource) -> Int {
        let id = nextResourceId
        nextResourceId += 1
        resources[id] = resource
        return id
    }
    
    public func getResource(_ id: Int) -> GraphicsResource? {
        return resources[id]
    }

    public func removeResource(_ id: Int) {
        if let resource = resources[id] {
            resource.cleanup()
            resources.removeValue(forKey: id)
        }
    }
    
    public func cleanup() {
        // Clean up all graphics resources
        for resource in resources.values {
            resource.cleanup()
        }
        resources.removeAll()
        
        // Clean up buffer management
        staticVertexBuffer = nil
        dynamicVertexBuffer = nil
        indexBuffer = nil
        usedVRAM = 0
        availableVRAM = totalVRAM / 10  // Reset to initial 10% allocation
    }
}

/// Just general buffer errors for a variety of cases
public enum BufferError: Error {
    case outOfSpace
    case bufferCleaned
    case invalidAlignment
    case outOfVRAM
    case notInitialized
}