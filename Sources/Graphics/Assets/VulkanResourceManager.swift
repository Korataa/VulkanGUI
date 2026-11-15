import Platform
import Core
import Foundation
import Cvulkan
import Cvma

/// Vulkan-specific resource manager
/// Manages Vulkan buffers, textures, shaders, and other GPU resources with concrete types
/// No generic abstractions - pure Vulkan implementation for maximum performance
public final class VulkanResourceManager: ResourceManager {

    private let device: VkDevice
    private let vmaAllocator: VmaAllocator
    private let transferCommandPool: VkCommandPool
    private let transferQueue: VkQueue

    // Direct storage of concrete Vulkan resources - no more 'any' types!
    private var textures: DynamicArray<Texture> = DynamicArray(capacity: 10)
    private var shaders: DynamicArray<VulkanShader> = DynamicArray(capacity: 10)
    private var nextResourceId: Int = 1
    private var activeResourceIds: Set<Int> = []
    
    // Buffer management - Vulkan-specific buffers
    public var transferBuffer: VulkanBuffer?
    public var vertex2DBuffer: VulkanBuffer?
    public var index2DBuffer: VulkanBuffer?
    
    // Memory tracking
    private let totalVRAM: UInt64         // Total GPU memory available
    
    // Buffer offsets
    private var vertex2DOffset: Int = 0
    private var index2DOffset: Int = 0
    
    private let initialTransferSize: UInt64 = 256 * 1024
    private let initial2DVertexSize: UInt64 = 1024 * 1024
    private let initial2DIndexSize: UInt64 = 256 * 1024
    
    public init(device: VkDevice, vmaAllocator: VmaAllocator, totalVRAM: UInt64, transferCommandPool: VkCommandPool, transferQueue: VkQueue) {
        self.device = device
        self.vmaAllocator = vmaAllocator
        self.totalVRAM = totalVRAM
        self.transferCommandPool = transferCommandPool
        self.transferQueue = transferQueue
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
    
    /// Get texture count
    public func getTextureCount() -> Int {
        return textures.getLength()
    }
    
    /// Get texture by ID using a closure to avoid copy issues
    public func withTexture<T>(id: Int, _ closure: (borrowing Texture) -> T) -> T? {
        guard id >= 0 && id < textures.getLength() else { return nil }
        return closure(textures[id])
    }
    
    /// Add a shader - concrete Vulkan shader type
    public func addShader(_ shader: consuming VulkanShader) -> Int {
        let id = nextResourceId
        nextResourceId += 1

        let mutableShader = shader
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
    
    /// Safely access 2D vertex buffer handle
    public borrowing func withVertex2DBuffer<T>(_ body: (borrowing VulkanBuffer) throws -> T) rethrows -> T? {
        guard vertex2DBuffer != nil else { return nil }
        return try body(vertex2DBuffer!)
    }
    
    /// Safely access 2D index buffer handle
    public borrowing func withIndex2DBuffer<T>(_ body: (borrowing VulkanBuffer) throws -> T) rethrows -> T? {
        guard index2DBuffer != nil else { return nil }
        return try body(index2DBuffer!)
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
        print("🧹 VulkanResourceManager cleanup - freeing 2D buffers...")
        
        //Clean up buffers directly
        vertex2DBuffer?.cleanup()
        index2DBuffer?.cleanup()
        transferBuffer?.cleanup()
        
        transferBuffer = nil
        vertex2DBuffer = nil
        index2DBuffer = nil
        
        // Clear tracking data
        activeResourceIds.removeAll()
        vertex2DOffset = 0
        index2DOffset = 0
        print("✅ VulkanResourceManager cleanup completed")
    }
    
    public func initialize() throws {
        // Create buffers
        try createTransferBuffer()
        try createVertex2DBuffer()
        try createIndex2DBuffer()
    }
    
    // MARK: - Buffer Creation
    private func createTransferBuffer(size: UInt64? = nil) throws {
        transferBuffer = VulkanBuffer(
            vmaAllocator: vmaAllocator,
            size: size ?? initialTransferSize,
            usage: .TransferSrc,
            properties: .GPUUpload
        )
    }
    
    private func createVertex2DBuffer(size: UInt64? = nil) throws {
        vertex2DBuffer = VulkanBuffer(
            vmaAllocator: vmaAllocator,
            size: size ?? initial2DVertexSize,
            usage: [.Vertex, .TransferDst],  // Add TransferDst for staging buffer uploads
            properties: .GPULocal
        )
        vertex2DOffset = 0
    }
    
    private func createIndex2DBuffer(size: UInt64? = nil) throws {
        index2DBuffer = VulkanBuffer(
            vmaAllocator: vmaAllocator,
            size: size ?? initial2DIndexSize,
            usage: [.Index, .TransferDst],  // Add TransferDst for staging buffer uploads
            properties: .GPULocal
        )
        index2DOffset = 0
    }

    private func grownSize(current: UInt64, required: UInt64) throws -> UInt64 {
        var size = current
        while size < required {
            let (next, overflow) = size.multipliedReportingOverflow(by: 2)
            guard !overflow else { throw BufferError.insufficientMemory }
            size = next
        }
        return size
    }

    // Called after the previous frame completes and before uploading any UI geometry.
    func prepare2DBuffers(vertexBytes: Int, indexBytes: Int) throws {
        guard vertexBytes >= 0, indexBytes >= 0, vertex2DOffset == 0, index2DOffset == 0,
              let vertexSize = vertex2DBuffer?.size, let indexSize = index2DBuffer?.size else {
            throw BufferError.bufferNotInitialized
        }
        if UInt64(vertexBytes) > vertexSize {
            let size = try grownSize(current: vertexSize, required: UInt64(vertexBytes))
            vertex2DBuffer?.cleanup()
            vertex2DBuffer = nil
            try createVertex2DBuffer(size: size)
        }
        if UInt64(indexBytes) > indexSize {
            let size = try grownSize(current: indexSize, required: UInt64(indexBytes))
            index2DBuffer?.cleanup()
            index2DBuffer = nil
            try createIndex2DBuffer(size: size)
        }
    }

    private func checkCapacity(offset: Int, size: Int, capacity: UInt64) throws {
        guard offset >= 0, size >= 0, UInt64(offset) <= capacity,
              UInt64(size) <= capacity - UInt64(offset) else {
            throw BufferError.insufficientMemory
        }
    }
    
    // MARK: - Buffer Type Enumeration
    public enum BufferType {
        case transfer
        case vertex2D
        case index2D
    }
    
    // MARK: - Generic Buffer Allocation
    public func allocateRegion(type: BufferType, size: Int) throws -> BufferRegion {
        switch type {
        case .transfer:
            guard let capacity = transferBuffer?.size else {
                throw BufferError.bufferNotInitialized
            }
            try checkCapacity(offset: 0, size: size, capacity: capacity)
            return BufferRegion(
                offset: 0,
                size: size,
                buffer: transferBuffer!
            )
            
        case .vertex2D:
            guard let capacity = vertex2DBuffer?.size else {
                throw BufferError.bufferNotInitialized
            }
            try checkCapacity(offset: vertex2DOffset, size: size, capacity: capacity)
            
            let region = BufferRegion(
                offset: vertex2DOffset,
                size: size,
                buffer: vertex2DBuffer!
            )
            vertex2DOffset += size
            return region
            
        case .index2D:
            guard let capacity = index2DBuffer?.size else {
                throw BufferError.bufferNotInitialized
            }
            try checkCapacity(offset: index2DOffset, size: size, capacity: capacity)
            
            let region = BufferRegion(
                offset: index2DOffset,
                size: size,
                buffer: index2DBuffer!
            )
            index2DOffset += size
            return region
        }
    }
    
    // MARK: - 2D/UI Buffer Management
    
    public func allocate2DVertices(vertices: [Vertex2D]) throws -> BufferRegion {
        guard let capacity = vertex2DBuffer?.size else {
            throw BufferError.bufferNotInitialized
        }
        
        let size = vertices.count * MemoryLayout<Vertex2D>.stride
        
        // Debug: Show first few vertices being allocated
        print("DEBUG: VulkanResourceManager allocating \(vertices.count) 2D vertices (\(size) bytes) at offset \(vertex2DOffset)")
        if vertices.count > 0 {
            let firstVertices = Array(vertices.prefix(3))
            print("  First 2D vertices: \(firstVertices)")
        }
        
        try checkCapacity(offset: vertex2DOffset, size: size, capacity: capacity)
        
        let currentOffset = vertex2DOffset
        let region = BufferRegion(
            offset: currentOffset,
            size: size,
            buffer: vertex2DBuffer!
        )
        
        // Use high-performance staging buffer upload instead of direct upload
        try uploadToGPUBuffer(data: vertices, destinationBuffer: vertex2DBuffer!, destinationOffset: currentOffset)
        
        // Update offset for next allocation
        vertex2DOffset += size
        
        return region
    }
    
    /// Reset 2D buffer offsets to reuse same buffer space each frame (no allocation)
    public func reset2DBuffers() {
        vertex2DOffset = 0
        index2DOffset = 0
    }
    
    public func allocate2DIndices(indices: [UInt32]) throws -> BufferRegion {
        guard let capacity = index2DBuffer?.size else {
            throw BufferError.bufferNotInitialized
        }
        
        let size = indices.count * MemoryLayout<UInt32>.stride
        
        // Debug: Show first few indices being allocated
        print("DEBUG: VulkanResourceManager allocating \(indices.count) 2D indices (\(size) bytes) at offset \(index2DOffset)")
        let firstIndices = Array(indices.prefix(10))
        print("  First 2D indices: \(firstIndices)")
        
        try checkCapacity(offset: index2DOffset, size: size, capacity: capacity)
        
        let region = BufferRegion(
            offset: index2DOffset,
            size: size,
            buffer: index2DBuffer!
        )
        
        // Use high-performance staging buffer upload instead of direct upload
        try uploadToGPUBuffer(data: indices, destinationBuffer: index2DBuffer!, destinationOffset: index2DOffset)
        
        index2DOffset += size
        
        return region
    }
    
    // MARK: - High-Performance Staging Buffer Upload
    
    /// High-performance upload to GPU-local buffers using staging buffer
    /// This is the most efficient way to get data to GPU memory
    private func uploadToGPUBuffer<T>(data: [T], destinationBuffer: borrowing VulkanBuffer, destinationOffset: Int) throws {
        let size = data.count * MemoryLayout<T>.stride
        guard size > 0 else { return }
        
        // Ensure we have a staging buffer
        if transferBuffer == nil {
            try createTransferBuffer()
        }
        
        guard let capacity = transferBuffer?.size else {
            throw BufferError.bufferNotInitialized
        }
        if UInt64(size) > capacity {
            let newSize = try grownSize(current: capacity, required: UInt64(size))
            transferBuffer?.cleanup()
            transferBuffer = nil
            try createTransferBuffer(size: newSize)
        }
        
        // Upload data to staging buffer (host-visible)
        data.withUnsafeBufferPointer { ptr in
            transferBuffer!.uploadData(data: ptr.baseAddress!, size: size, offset: 0)
        }
        
        // Copy from staging buffer to GPU buffer (most efficient transfer)
        // TODO: This needs the actual Vulkan device/queue context to perform the copy
        // For now, we'll need to provide these via the renderer
        copyBufferToGPU(
            source: transferBuffer!,
            destination: destinationBuffer,
            size: size,
            sourceOffset: 0,
            destinationOffset: destinationOffset
        )
    }
    
    /// Performs the actual GPU copy operation using VulkanBuffer's optimized copyTo method
    private func copyBufferToGPU(
        source: borrowing VulkanBuffer,
        destination: borrowing VulkanBuffer,
        size: Int,
        sourceOffset: Int,
        destinationOffset: Int
    ) {
        // Use VulkanBuffer's high-performance copyTo method with proper offsets
        // This creates an optimal command buffer and submits it to the transfer queue
        source.copyTo(
            dstBuffer: destination,
            size: VkDeviceSize(size),
            srcOffset: VkDeviceSize(sourceOffset),
            dstOffset: VkDeviceSize(destinationOffset),
            transferCommandPool: transferCommandPool,
            transferQueue: transferQueue,
            logicalDevice: device
        )
    }
    
    // MARK: - Memory Information
    /// Reports 2D geometry usage, not total Vulkan or texture allocations.
    public func getMemoryInfo() -> (total: UInt64, available: UInt64, used: UInt64) {
        let capacity = (vertex2DBuffer?.size ?? 0) + (index2DBuffer?.size ?? 0)
        return (total: totalVRAM, available: capacity, used: UInt64(vertex2DOffset) + UInt64(index2DOffset))
    }
    
    public func getVRAMUsagePercent() -> Double {
        let info = getMemoryInfo()
        return info.available == 0 ? 0 : Double(info.used) / Double(info.available)
    }
}

public enum BufferError: Error {
    case bufferNotInitialized
    case outOfVRAM
    case uploadFailed
    case insufficientMemory
}