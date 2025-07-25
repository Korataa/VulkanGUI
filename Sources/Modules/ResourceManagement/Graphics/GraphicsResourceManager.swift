import Foundation
import Cvulkan
import Cvma

/// Manages graphics resources using ID-based tracking instead of direct storage
/// This approach works with ~Copyable types by avoiding storage in collections
public final class GraphicsResourceManager: ResourceManager {
    public typealias ResourceType = any GraphicsResource

    private let device: VkDevice
    private let vmaAllocator: VmaAllocator

    // ID-based resource tracking - we don't store the resources themselves
    //we do now
    private var resources: DynamicArray<GraphicsResource> = DynamicArray()
    private var nextResourceId: Int = 1
    private var activeResourceIds: Set<Int> = []
    
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
    
    // Allocation percentages for different buffer types
    private let initialStaticVertexPercent: Double = 0.5  // Starts at 50% of initial VRAM
    private let initialDynamicVertexPercent: Double = 0.2 // Starts at 20% of initial VRAM
    private let initialIndexBufferPercent: Double = 0.2   // Starts at 20% of initial VRAM
    private let initialTransferPercent: Double = 0.1      // Starts at 10% of initial VRAM
    
    // Growth threshold - when to increase available VRAM (80% of current available)
    private let growthThreshold: Double = 0.8
    
    public init(device: VkDevice, vmaAllocator: VmaAllocator, totalVRAM: UInt64) {
        self.device = device
        self.vmaAllocator = vmaAllocator
        self.totalVRAM = totalVRAM
        self.availableVRAM = totalVRAM / 10  // Start with 10% of total VRAM
    }
    
    // MARK: - ResourceManager Protocol
    public func canHandle(_ resourceType: ResourceType) -> Bool {
        switch resourceType {
        case .graphics(_):
            return true
        default:
            return false
        }
    }
    
    /// Registers a resource and returns an ID for tracking
    /// The resource ownership remains with the caller
    public func addResource(_ resource: consuming ResourceType) -> Int {
        // Validate that this is a graphics resource
        switch resource.resourceType {
        case .graphics(_):
            break
        default:
            fatalError("GraphicsResourceManager can only handle GraphicsResource types")
        }

        let id = nextResourceId
        nextResourceId += 1

        // Set the resource ID - this mutates the resource in place
        var mutableResource = resource
        mutableResource.id = id

        // Store the resource in the DynamicArray
        resources.append(mutableResource)

        // Track the ID as active
        activeResourceIds.insert(id)

        // The resource is now owned by the manager, do not return it to the caller
        // (no consume needed here)

        return id
    }
    
    /// Remove a resource ID from tracking
    /// The caller is responsible for cleaning up the actual resource
    public func removeResource(id: Int) -> Bool {
        return activeResourceIds.remove(id) != nil
    }
    
    /// Get a resource by ID - returns the stored GraphicsResource if present
    public func getResource(_ id: Int) -> ResourceType? {
        // IDs start at 1, so index is id-1
        let index = id - 1
        guard index >= 0 && index < resources.count else { return nil }
        return resources[index]
    }
    
    /// Remove a resource by ID (protocol conformance)
    public func removeResource(_ id: Int) {
        _ = removeResource(id: id)
    }
    
    /// Check if a resource ID is being tracked
    public func hasResource(id: Int) -> Bool {
        return activeResourceIds.contains(id)
    }
    
    /// Get the count of tracked resources
    public func getResourceCount() -> Int {
        return activeResourceIds.count
    }
    
    /// Get all active resource IDs
    public func getAllResourceIds() -> [Int] {
        return Array(activeResourceIds)
    }
    
    public func cleanup() {
        // Clean up buffers
        staticVertexBuffer?.cleanup()
        dynamicVertexBuffer?.cleanup()
        transferBuffer?.cleanup()
        indexBuffer?.cleanup()
        
        staticVertexBuffer = nil
        dynamicVertexBuffer = nil
        transferBuffer = nil
        indexBuffer = nil
        
        // Clear tracking data
        activeResourceIds.removeAll()
        usedVRAM = 0
    }
    
    // MARK: - Memory Management
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
    
    // MARK: - Buffer Creation
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
            properties: .CPUVisible
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
            properties: .CPUVisible
        )
    }
    
    // MARK: - Buffer Type Enumeration
    public enum BufferType {
        case staticVertex
        case dynamicVertex
        case index
        case transfer
    }
    
    // MARK: - Generic Buffer Allocation
    public func allocateRegion(type: BufferType, size: Int) throws -> BufferRegion {
        switch type {
        case .staticVertex:
            guard let buffer = staticVertexBuffer else {
                throw BufferError.bufferNotInitialized
            }
            try updateVRAMUsage(delta: Int64(size))
            
            let region = BufferRegion(
                offset: staticVertexOffset,
                size: size,
                buffer: buffer
            )
            staticVertexOffset += size
            return region
            
        case .dynamicVertex:
            guard let buffer = dynamicVertexBuffer else {
                throw BufferError.bufferNotInitialized
            }
            try updateVRAMUsage(delta: Int64(size))
            
            let region = BufferRegion(
                offset: dynamicVertexOffset,
                size: size,
                buffer: buffer
            )
            dynamicVertexOffset += size
            return region
            
        case .index:
            guard let buffer = indexBuffer else {
                throw BufferError.bufferNotInitialized
            }
            try updateVRAMUsage(delta: Int64(size))
            
            let region = BufferRegion(
                offset: indexOffset,
                size: size,
                buffer: buffer
            )
            indexOffset += size
            return region
            
        case .transfer:
            guard let buffer = transferBuffer else {
                throw BufferError.bufferNotInitialized
            }
            // Transfer buffer doesn't track offset since it's used for temporary operations
            return BufferRegion(
                offset: 0,
                size: size,
                buffer: buffer
            )
        }
    }
    
    // MARK: - Vertex Buffer Management
    public func allocateStaticVertices<T>(vertices: [T]) throws -> BufferRegion {
        guard let buffer = staticVertexBuffer else {
            throw BufferError.bufferNotInitialized
        }
        
        let size = vertices.count * MemoryLayout<T>.stride
        try updateVRAMUsage(delta: Int64(size))
        
        let region = BufferRegion(
            offset: staticVertexOffset,
            size: size,
            buffer: buffer
        )
        
        // Upload vertices to buffer
        vertices.withUnsafeBufferPointer { ptr in
            buffer.uploadData(data: ptr.baseAddress!, size: size, offset: staticVertexOffset)
        }
        
        staticVertexOffset += size
        return region
    }
    
    public func allocateDynamicVertices<T>(vertices: [T]) throws -> BufferRegion {
        guard let buffer = dynamicVertexBuffer else {
            throw BufferError.bufferNotInitialized
        }
        
        let size = vertices.count * MemoryLayout<T>.stride
        try updateVRAMUsage(delta: Int64(size))
        
        let region = BufferRegion(
            offset: dynamicVertexOffset,
            size: size,
            buffer: buffer
        )
        
        // Upload vertices to buffer
        vertices.withUnsafeBufferPointer { ptr in
            buffer.uploadData(data: ptr.baseAddress!, size: size, offset: dynamicVertexOffset)
        }
        
        dynamicVertexOffset += size
        return region
    }
    
    public func allocateIndices(indices: [UInt32]) throws -> BufferRegion {
        guard let buffer = indexBuffer else {
            throw BufferError.bufferNotInitialized
        }
        
        let size = indices.count * MemoryLayout<UInt32>.stride
        try updateVRAMUsage(delta: Int64(size))
        
        let region = BufferRegion(
            offset: indexOffset,
            size: size,
            buffer: buffer
        )
        
        // Upload indices to buffer
        indices.withUnsafeBufferPointer { ptr in
            buffer.uploadData(data: ptr.baseAddress!, size: size, offset: indexOffset)
        }
        
        indexOffset += size
        return region
    }
    
    // MARK: - Memory Information
    public func getMemoryInfo() -> (total: UInt64, available: UInt64, used: UInt64) {
        return (total: totalVRAM, available: availableVRAM, used: usedVRAM)
    }
    
    public func getVRAMUsagePercent() -> Double {
        return Double(usedVRAM) / Double(availableVRAM)
    }
}

public enum BufferError: Error {
    case bufferNotInitialized
    case outOfVRAM
    case uploadFailed
}