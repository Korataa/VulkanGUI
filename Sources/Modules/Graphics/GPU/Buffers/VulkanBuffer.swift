import Cvulkan
import Cvma

import Foundation

public struct VulkanBuffer: GPUBuffer {
    public var resourceType: GraphicsResourceType {
        get { return .buffer(usage) }
        set { /* Optionally handle set if needed, or leave empty if not supported */ }
    }
    public var name: String?
    public var id: Int?

    public let bufferHandle: GPUBufferHandle
    let allocation: VmaAllocation
    let vmaAllocator: VmaAllocator
    public let size: UInt64
    public let usage: GPUBufferUsage

    init(vmaAllocator: VmaAllocator, size: UInt64, usage: GPUBufferUsage, properties: GPUMemoryProperties, isDynamic: Bool = false) {
        self.size = size
        self.usage = usage
        self.vmaAllocator = vmaAllocator

        var buffer: VkBuffer?
        var allocation: VmaAllocation?

        //define vulkan buffer create info
        var bufferInfo = VkBufferCreateInfo()
        bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
        bufferInfo.size = VkDeviceSize(size)
        bufferInfo.usage = usage.toVulkanFlags()
        bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE

        //define vma allocation info
        var allocInfo = VmaAllocationCreateInfo()
        allocInfo.usage = VMA_MEMORY_USAGE_AUTO
        allocInfo.requiredFlags = properties.toVulkanFlags()

        //Handle host visibility and dynamic buffer flags
        let isHostVisible = (properties.toVulkanFlags() & UInt32(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue)) != 0
        if isHostVisible {
            allocInfo.flags |= isDynamic
                ? (UInt32(VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT.rawValue) |
                  UInt32(VMA_ALLOCATION_CREATE_MAPPED_BIT.rawValue))
                  : UInt32(VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT.rawValue)
        }

        //actually create the buffer using VMA
        let result = vmaCreateBuffer(vmaAllocator, &bufferInfo, &allocInfo, &buffer, &allocation, nil)
        if result != VK_SUCCESS {
            fatalError("Failed to create Bulkan buffer!")
        }

        self.bufferHandle = .Vulkan(buffer!)
        self.allocation = allocation!
    }

    public func uploadData(data: UnsafeRawPointer, size: Int) {
        uploadData(data: data, size: size, offset: 0)
    }

    public func uploadData(data: UnsafeRawPointer, size: Int, offset: Int = 0) {
        guard size <= self.size else {
            fatalError("Data size (\(size)) plus offset (\(offset)) exceeds buffer size (\(self.size))")
        }

        var mappedMemory: UnsafeMutableRawPointer?
        let result = vmaMapMemory(vmaAllocator, allocation, &mappedMemory)
        if result != VK_SUCCESS {
            fatalError("Failed to map Vulkan buffer memory!")
        }

        //add the offset to the mapped memory pointer
        let destPtr = mappedMemory!.advanced(by: offset)
        memcpy(destPtr, data, size)

        //unmap the memory after copying
        vmaUnmapMemory(vmaAllocator, allocation)
    }

    public func copyTo( dstBuffer: VulkanBuffer, size: VkDeviceSize, 
                        transferCommandPool: VkCommandPool,
                        transferQueue: VkQueue, logicalDevice: VkDevice) {
        var allocInfo = VkCommandBufferAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
        allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
        allocInfo.commandPool = transferCommandPool
        allocInfo.commandBufferCount = 1

        var commandBuffer: VkCommandBuffer? = nil
        vkAllocateCommandBuffers(logicalDevice, &allocInfo, &commandBuffer)
        defer {
            vkFreeCommandBuffers(logicalDevice, transferCommandPool, 1, &commandBuffer)
        }

        var beginInfo = VkCommandBufferBeginInfo()
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
        beginInfo.flags = UInt32(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT.rawValue)
        
        vkBeginCommandBuffer(commandBuffer!, &beginInfo)

        var copyRegion = VkBufferCopy()
        copyRegion.srcOffset = 0
        copyRegion.dstOffset = 0
        copyRegion.size = size

        vkCmdCopyBuffer(commandBuffer!, self.bufferHandle.asVulkanBuffer(), dstBuffer.bufferHandle.asVulkanBuffer(), 1, &copyRegion)

        vkEndCommandBuffer(commandBuffer!)

        var submitInfo = VkSubmitInfo()
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
        submitInfo.commandBufferCount = 1
        withUnsafePointer(to: &commandBuffer) { ptr in 
            submitInfo.pCommandBuffers = ptr
        }

        vkQueueSubmit(transferQueue, 1, &submitInfo, nil)
        vkQueueWaitIdle(transferQueue)
    }

    public func cleanup() {
        vmaDestroyBuffer(vmaAllocator, bufferHandle.asVulkanBuffer(), allocation)
    }
}