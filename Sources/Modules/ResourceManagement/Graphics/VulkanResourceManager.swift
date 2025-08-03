import Foundation
import Cvulkan
import Cvma

/// Vulkan-specific resource manager
/// Manages Vulkan buffers, textures, shaders, and other GPU resources with concrete types
/// No generic abstractions - pure Vulkan implementation for maximum performance
public final class VulkanResourceManager: ResourceManager {

    private let device: VkDevice
    private let vmaAllocator: VmaAllocator

    // Direct storage of concrete Vulkan resources - no more 'any' types!
    private var textures: DynamicArray<Texture> = DynamicArray(capacity: 10)
    private var shaders: DynamicArray<VulkanShader> = DynamicArray(capacity: 10)
    private var nextResourceId: Int = 1
    private var activeResourceIds: Set<Int> = []
    
    // Buffer management - Vulkan-specific buffers
    public var staticVertexBuffer: VulkanBuffer?
    public var dynamicVertexBuffer: VulkanBuffer?
    public var transferBuffer: VulkanBuffer?
    public var indexBuffer: VulkanBuffer?
    
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
    public func canHandle(_ typeCategory: ResourceCategory) -> Bool {
        switch typeCategory {
        case .graphics(_):
            return true
        default:
            return false
        }
    }
    
    // MARK: - Vulkan-Specific Resource Management
    
    /// Add a texture - concrete type, no abstractions!
    public func addTexture(_ texture: consuming Texture) -> Int {
        let id = nextResourceId
        nextResourceId += 1

        var mutableTexture = texture
        mutableTexture.id = id

        textures.append(mutableTexture)
        activeResourceIds.insert(id)

        return id
    }
    
    /// Add a shader - concrete Vulkan shader type
    public func addShader(_ shader: consuming VulkanShader) -> Int {
        let id = nextResourceId
        nextResourceId += 1

        var mutableShader = shader
        mutableShader.id = id

        shaders.append(mutableShader)
        activeResourceIds.insert(id)

        return id
    }

    /// Generic addResource for protocol conformance - simplified approach
    public func addResource(_ resource: consuming any Resource) -> Int {
        // For now, we'll require callers to use the specific methods
        fatalError("VulkanResourceManager: Use addTexture() or addShader() instead of generic addResource()")
    }
    
    /// Remove a resource ID from tracking
    /// The caller is responsible for cleaning up the actual resource
    public func removeResource(id: Int) -> Bool {
        return activeResourceIds.remove(id) != nil
    }
    
    /// Safely access static vertex buffer handle
    public borrowing func withStaticVertexBuffer<T>(_ body: (borrowing VulkanBuffer) throws -> T) rethrows -> T? {
        guard staticVertexBuffer != nil else { return nil }
        return try body(staticVertexBuffer!)
    }
    
    /// Safely access dynamic vertex buffer handle
    public borrowing func withDynamicVertexBuffer<T>(_ body: (borrowing VulkanBuffer) throws -> T) rethrows -> T? {
        guard dynamicVertexBuffer != nil else { return nil }
        return try body(dynamicVertexBuffer!)
    }
    
    /// Safely access index buffer handle
    public borrowing func withIndexBuffer<T>(_ body: (borrowing VulkanBuffer) throws -> T) rethrows -> T? {
        guard indexBuffer != nil else { return nil }
        return try body(indexBuffer!)
    }
    
    /// Get a resource by ID - simplified for ~Copyable compatibility
    public func getResource(_ id: Int) -> (any Resource)? {
        // Due to ~Copyable limitations with 'any Resource', use specific methods instead
        fatalError("VulkanResourceManager: Use getTexture() or getShader() instead of generic getResource()")
    }
    
    /// Get texture by ID - consumes and returns the texture
    public func consumeTexture(_ id: Int) -> Texture? {
        let index = id - 1
        guard index >= 0 && index < textures.count else { return nil }
        return textures.consumeElement(at: index)
    }
    
    /// Get shader by ID - consumes and returns the shader
    public func consumeShader(_ id: Int) -> VulkanShader? {
        let index = id - 1
        guard index >= 0 && index < shaders.count else { return nil }
        return shaders.consumeElement(at: index)
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
            guard staticVertexBuffer != nil else {
                throw BufferError.bufferNotInitialized
            }
            try updateVRAMUsage(delta: Int64(size))
            
            let region = BufferRegion(
                offset: staticVertexOffset,
                size: size,
                buffer: staticVertexBuffer!
            )
            staticVertexOffset += size
            return region
            
        case .dynamicVertex:
            guard dynamicVertexBuffer != nil else {
                throw BufferError.bufferNotInitialized
            }
            try updateVRAMUsage(delta: Int64(size))
            
            let region = BufferRegion(
                offset: dynamicVertexOffset,
                size: size,
                buffer: dynamicVertexBuffer!
            )
            dynamicVertexOffset += size
            return region
            
        case .index:
            guard indexBuffer != nil else {
                throw BufferError.bufferNotInitialized
            }
            try updateVRAMUsage(delta: Int64(size))
            
            let region = BufferRegion(
                offset: indexOffset,
                size: size,
                buffer: indexBuffer!
            )
            indexOffset += size
            return region
            
        case .transfer:
            guard transferBuffer != nil else {
                throw BufferError.bufferNotInitialized
            }
            // Transfer buffer doesn't track offset since it's used for temporary operations
            return BufferRegion(
                offset: 0,
                size: size,
                buffer: transferBuffer!
            )
        }
    }
    
    // MARK: - Vertex Buffer Management
    public func allocateStaticVertices<T>(vertices: [T]) throws -> BufferRegion {
        guard staticVertexBuffer != nil else {
            throw BufferError.bufferNotInitialized
        }
        
        let size = vertices.count * MemoryLayout<T>.stride
        try updateVRAMUsage(delta: Int64(size))
        
        let region = BufferRegion(
            offset: staticVertexOffset,
            size: size,
            buffer: staticVertexBuffer!
        )
        
        // Upload vertices to buffer
        vertices.withUnsafeBufferPointer { ptr in
            staticVertexBuffer!.uploadData(data: ptr.baseAddress!, size: size, offset: staticVertexOffset)
        }
        
        staticVertexOffset += size
        return region
    }
    
    public func allocateDynamicVertices<T>(vertices: [T]) throws -> BufferRegion {
        guard dynamicVertexBuffer != nil else {
            throw BufferError.bufferNotInitialized
        }
        
        let size = vertices.count * MemoryLayout<T>.stride
        try updateVRAMUsage(delta: Int64(size))
        
        let region = BufferRegion(
            offset: dynamicVertexOffset,
            size: size,
            buffer: dynamicVertexBuffer!
        )
        
        // Upload vertices to buffer
        vertices.withUnsafeBufferPointer { ptr in
            dynamicVertexBuffer!.uploadData(data: ptr.baseAddress!, size: size, offset: dynamicVertexOffset)
        }
        
        dynamicVertexOffset += size
        return region
    }
    
    public func allocateIndices(indices: [UInt32]) throws -> BufferRegion {
        guard indexBuffer != nil else {
            throw BufferError.bufferNotInitialized
        }
        
        let size = indices.count * MemoryLayout<UInt32>.stride
        try updateVRAMUsage(delta: Int64(size))
        
        let region = BufferRegion(
            offset: indexOffset,
            size: size,
            buffer: indexBuffer!
        )
        
        // Upload indices to buffer
        indices.withUnsafeBufferPointer { ptr in
            indexBuffer!.uploadData(data: ptr.baseAddress!, size: size, offset: indexOffset)
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