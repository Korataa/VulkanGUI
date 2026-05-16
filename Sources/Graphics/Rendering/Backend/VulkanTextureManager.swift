import Platform
import Core
import Foundation
import Cvulkan
import Cvma

public class VulkanTextureManager {
    private let device: VkDevice
    private let physicalDevice: VkPhysicalDevice
    private let allocator: VmaAllocator
    private let commandPool: VkCommandPool
    private let graphicsQueue: VkQueue
    
    // Texture storage
    private var textures: [VulkanTexture] = []
    private var defaultTextureIndex: Int? = nil
    private var sampler: VkSampler?
    private var clampSampler: VkSampler?
    
    // Descriptor set layout and pool for textures
    private var textureDescriptorSetLayout: VkDescriptorSetLayout?
    private var textureDescriptorPool: VkDescriptorPool?
    private var textureDescriptorSets: [VkDescriptorSet] = []
    
    public init(device: VkDevice, physicalDevice: VkPhysicalDevice, allocator: VmaAllocator, 
         commandPool: VkCommandPool, graphicsQueue: VkQueue) {
        self.device = device
        self.physicalDevice = physicalDevice
        self.allocator = allocator
        self.commandPool = commandPool
        self.graphicsQueue = graphicsQueue
    }
    
    public func initialize() -> Bool {
        guard createSampler() else {
            print("Failed to create texture sampler")
            return false
        }

        guard createClampSampler() else {
            print("Failed to create clamp texture sampler")
            return false
        }

        guard ensureDefaultTexture() else {
            print("Failed to create default fallback texture")
            return false
        }
        
        print("VulkanTextureManager initialized successfully")
        return true
    }

    private func ensureDefaultTexture() -> Bool {
        if defaultTextureIndex != nil {
            return true
        }

        let whitePixel: [UInt8] = [255, 255, 255, 255]
        let index = createTextureRGBA(width: 1, height: 1, pixels: whitePixel, srgb: true)
        guard index >= 0 else {
            return false
        }

        defaultTextureIndex = index
        return true
    }
    
    public func cleanup() {
        // Cleanup descriptor sets (automatically freed with pool)
        
        // Cleanup descriptor pool
        if let pool = textureDescriptorPool {
            vkDestroyDescriptorPool(device, pool, nil)
            textureDescriptorPool = nil
        }
        
        // Cleanup descriptor set layout
        if let layout = textureDescriptorSetLayout {
            vkDestroyDescriptorSetLayout(device, layout, nil)
            textureDescriptorSetLayout = nil
        }
        
        // Cleanup textures
        for texture in textures {
            cleanup(texture: texture)
        }
        textures.removeAll()
        
        // Cleanup sampler
        if let sampler = sampler {
            vkDestroySampler(device, sampler, nil)
            self.sampler = nil
        }

        if let clampSampler = clampSampler {
            vkDestroySampler(device, clampSampler, nil)
            self.clampSampler = nil
        }
        
        print("VulkanTextureManager cleanup completed")
    }
    
    // Create a texture from raw pixel data
    public func createTexture(from textureData: borrowing Texture) -> Int {
        let textureIndex = textures.count
        
        guard let vulkanTexture = createVulkanTexture(from: textureData) else {
            print("Failed to create Vulkan texture for index \(textureIndex)")
            return -1
        }
        
        textures.append(vulkanTexture)
        print("Created Vulkan texture \(textureIndex): \(textureData.width)x\(textureData.height)")
        return textureIndex
    }

    public func createTextureRGBA(width: Int, height: Int, pixels: [UInt8], srgb: Bool = true, preferClampSampler: Bool = false) -> Int {
        let expectedByteCount = width * height * 4
        guard pixels.count == expectedByteCount else {
            print("Invalid RGBA texture byte count: got \(pixels.count), expected \(expectedByteCount)")
            return -1
        }

        let textureIndex = textures.count
        guard let vulkanTexture = createVulkanTexture(width: width, height: height, rgbaPixels: pixels, srgb: srgb, preferClampSampler: preferClampSampler) else {
            print("Failed to create Vulkan RGBA texture for index \(textureIndex)")
            return -1
        }

        textures.append(vulkanTexture)
        print("Created Vulkan RGBA texture \(textureIndex): \(width)x\(height)")
        return textureIndex
    }

    public func createTextureR8(width: Int, height: Int, pixels: [UInt8]) -> Int {
        let expectedByteCount = width * height
        guard pixels.count == expectedByteCount else {
            print("Invalid R8 texture byte count: got \(pixels.count), expected \(expectedByteCount)")
            return -1
        }

        let textureIndex = textures.count
        guard let vulkanTexture = createVulkanTexture(width: width, height: height, rPixels: pixels) else {
            print("Failed to create Vulkan R8 texture for index \(textureIndex)")
            return -1
        }

        textures.append(vulkanTexture)
        print("Created Vulkan R8 texture \(textureIndex): \(width)x\(height)")
        return textureIndex
    }
    
    // Get texture for binding
    func getTexture(at index: Int) -> VulkanTexture? {
        guard index >= 0 && index < textures.count else { return nil }
        return textures[index]
    }
    
    // Get sampler
    func getSampler() -> VkSampler? {
        return sampler
    }
    
    private func createSampler() -> Bool {
        var samplerInfo = VkSamplerCreateInfo()
        samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO
        samplerInfo.magFilter = VK_FILTER_LINEAR
        samplerInfo.minFilter = VK_FILTER_LINEAR
        samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT
        samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT
        samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT
        samplerInfo.anisotropyEnable = VK_TRUE
        samplerInfo.maxAnisotropy = 16.0
        samplerInfo.borderColor = VK_BORDER_COLOR_INT_OPAQUE_BLACK
        samplerInfo.unnormalizedCoordinates = VK_FALSE
        samplerInfo.compareEnable = VK_FALSE
        samplerInfo.compareOp = VK_COMPARE_OP_ALWAYS
        samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR
        samplerInfo.mipLodBias = 0.0
        samplerInfo.minLod = 0.0
        samplerInfo.maxLod = 0.0
        
        var tempSampler: VkSampler?
        let result = vkCreateSampler(device, &samplerInfo, nil, &tempSampler)
        guard result == VK_SUCCESS, let createdSampler = tempSampler else {
            print("Failed to create sampler: \(result)")
            return false
        }
        
        sampler = createdSampler
        return true
    }

    private func createClampSampler() -> Bool {
        var samplerInfo = VkSamplerCreateInfo()
        samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO
        samplerInfo.magFilter = VK_FILTER_LINEAR
        samplerInfo.minFilter = VK_FILTER_LINEAR
        samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
        samplerInfo.anisotropyEnable = VK_FALSE
        samplerInfo.maxAnisotropy = 1.0
        samplerInfo.borderColor = VK_BORDER_COLOR_INT_OPAQUE_BLACK
        samplerInfo.unnormalizedCoordinates = VK_FALSE
        samplerInfo.compareEnable = VK_FALSE
        samplerInfo.compareOp = VK_COMPARE_OP_ALWAYS
        samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR
        samplerInfo.mipLodBias = 0.0
        samplerInfo.minLod = 0.0
        samplerInfo.maxLod = 0.0

        var tempSampler: VkSampler?
        let result = vkCreateSampler(device, &samplerInfo, nil, &tempSampler)
        guard result == VK_SUCCESS, let createdSampler = tempSampler else {
            print("Failed to create clamp sampler: \(result)")
            return false
        }

        clampSampler = createdSampler
        return true
    }
    
    private func createVulkanTexture(from textureData: borrowing Texture) -> VulkanTexture? {
        // Create staging buffer
        guard let pixelPtr = textureData.pixels else {
            print("Texture has no pixel data")
            return nil
        }
        
        let imageSize = VkDeviceSize(textureData.width * textureData.height * textureData.channels)
        
        var stagingBuffer: VkBuffer?
        var stagingBufferAllocation: VmaAllocation?
        
        var bufferInfo = VkBufferCreateInfo()
        bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
        bufferInfo.size = imageSize
        bufferInfo.usage = UInt32(VK_BUFFER_USAGE_TRANSFER_SRC_BIT.rawValue)
        bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE
        
        var allocInfo = VmaAllocationCreateInfo()
        allocInfo.usage = VMA_MEMORY_USAGE_CPU_ONLY
        
        var result = vmaCreateBuffer(allocator, &bufferInfo, &allocInfo, &stagingBuffer, &stagingBufferAllocation, nil)
        guard result == VK_SUCCESS, let buffer = stagingBuffer, let allocation = stagingBufferAllocation else {
            print("Failed to create staging buffer: \(result)")
            return nil
        }
        
        // Map and copy data
        var data: UnsafeMutableRawPointer?
        result = vmaMapMemory(allocator, allocation, &data)
        guard result == VK_SUCCESS, let mappedData = data else {
            print("Failed to map staging buffer memory: \(result)")
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }
        
        // Copy pixel data from texture to mapped memory
        mappedData.copyMemory(from: pixelPtr, byteCount: Int(imageSize))
        vmaUnmapMemory(allocator, allocation)
        
        // Create image
        guard let vulkanTexture = createImage(width: UInt32(textureData.width), 
                                            height: UInt32(textureData.height),
                                            format: VK_FORMAT_R8G8B8A8_SRGB,
                                            samplerOverride: sampler) else {
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }
        
        // Transition image layout and copy from staging buffer
        guard transitionImageLayout(vulkanTexture.image, format: VK_FORMAT_R8G8B8A8_SRGB, 
                                  oldLayout: VK_IMAGE_LAYOUT_UNDEFINED, 
                                  newLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) else {
            cleanup(texture: vulkanTexture)
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }
        
        guard copyBufferToImage(buffer, vulkanTexture.image, 
                              width: UInt32(textureData.width), 
                              height: UInt32(textureData.height)) else {
            cleanup(texture: vulkanTexture)
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }
        
        guard transitionImageLayout(vulkanTexture.image, format: VK_FORMAT_R8G8B8A8_SRGB,
                                  oldLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                  newLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) else {
            cleanup(texture: vulkanTexture)
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }
        
        // Cleanup staging buffer
        vmaDestroyBuffer(allocator, buffer, allocation)
        
        return vulkanTexture
    }

    private func createVulkanTexture(width: Int, height: Int, rgbaPixels: [UInt8], srgb: Bool, preferClampSampler: Bool) -> VulkanTexture? {
        let imageSize = VkDeviceSize(width * height * 4)
        let imageFormat: VkFormat = srgb ? VK_FORMAT_R8G8B8A8_SRGB : VK_FORMAT_R8G8B8A8_UNORM

        var stagingBuffer: VkBuffer?
        var stagingBufferAllocation: VmaAllocation?

        var bufferInfo = VkBufferCreateInfo()
        bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
        bufferInfo.size = imageSize
        bufferInfo.usage = UInt32(VK_BUFFER_USAGE_TRANSFER_SRC_BIT.rawValue)
        bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE

        var allocInfo = VmaAllocationCreateInfo()
        allocInfo.usage = VMA_MEMORY_USAGE_CPU_ONLY

        var result = vmaCreateBuffer(allocator, &bufferInfo, &allocInfo, &stagingBuffer, &stagingBufferAllocation, nil)
        guard result == VK_SUCCESS, let buffer = stagingBuffer, let allocation = stagingBufferAllocation else {
            print("Failed to create staging buffer: \(result)")
            return nil
        }

        var data: UnsafeMutableRawPointer?
        result = vmaMapMemory(allocator, allocation, &data)
        guard result == VK_SUCCESS, let mappedData = data else {
            print("Failed to map staging buffer memory: \(result)")
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }

        rgbaPixels.withUnsafeBytes { src in
            mappedData.copyMemory(from: src.baseAddress!, byteCount: Int(imageSize))
        }
        vmaUnmapMemory(allocator, allocation)

        let selectedSampler = preferClampSampler ? (clampSampler ?? sampler) : sampler
        guard let vulkanTexture = createImage(width: UInt32(width), height: UInt32(height), format: imageFormat, samplerOverride: selectedSampler) else {
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }

        guard transitionImageLayout(vulkanTexture.image, format: imageFormat,
                                    oldLayout: VK_IMAGE_LAYOUT_UNDEFINED,
                                    newLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) else {
            cleanup(texture: vulkanTexture)
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }

        guard copyBufferToImage(buffer, vulkanTexture.image, width: UInt32(width), height: UInt32(height)) else {
            cleanup(texture: vulkanTexture)
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }

        guard transitionImageLayout(vulkanTexture.image, format: imageFormat,
                                    oldLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                    newLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) else {
            cleanup(texture: vulkanTexture)
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }

        vmaDestroyBuffer(allocator, buffer, allocation)
        return vulkanTexture
    }

    private func createVulkanTexture(width: Int, height: Int, rPixels: [UInt8]) -> VulkanTexture? {
        let imageSize = VkDeviceSize(width * height)
        let imageFormat: VkFormat = VK_FORMAT_R8_UNORM

        var stagingBuffer: VkBuffer?
        var stagingBufferAllocation: VmaAllocation?

        var bufferInfo = VkBufferCreateInfo()
        bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
        bufferInfo.size = imageSize
        bufferInfo.usage = UInt32(VK_BUFFER_USAGE_TRANSFER_SRC_BIT.rawValue)
        bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE

        var allocInfo = VmaAllocationCreateInfo()
        allocInfo.usage = VMA_MEMORY_USAGE_CPU_ONLY

        var result = vmaCreateBuffer(allocator, &bufferInfo, &allocInfo, &stagingBuffer, &stagingBufferAllocation, nil)
        guard result == VK_SUCCESS, let buffer = stagingBuffer, let allocation = stagingBufferAllocation else {
            print("Failed to create staging buffer: \(result)")
            return nil
        }

        var data: UnsafeMutableRawPointer?
        result = vmaMapMemory(allocator, allocation, &data)
        guard result == VK_SUCCESS, let mappedData = data else {
            print("Failed to map staging buffer memory: \(result)")
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }

        rPixels.withUnsafeBytes { src in
            mappedData.copyMemory(from: src.baseAddress!, byteCount: Int(imageSize))
        }
        vmaUnmapMemory(allocator, allocation)

        guard let vulkanTexture = createImage(width: UInt32(width), height: UInt32(height), format: imageFormat, samplerOverride: clampSampler ?? sampler) else {
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }

        guard transitionImageLayout(vulkanTexture.image, format: imageFormat,
                                    oldLayout: VK_IMAGE_LAYOUT_UNDEFINED,
                                    newLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) else {
            cleanup(texture: vulkanTexture)
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }

        guard copyBufferToImage(buffer, vulkanTexture.image, width: UInt32(width), height: UInt32(height)) else {
            cleanup(texture: vulkanTexture)
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }

        guard transitionImageLayout(vulkanTexture.image, format: imageFormat,
                                    oldLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                    newLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) else {
            cleanup(texture: vulkanTexture)
            vmaDestroyBuffer(allocator, buffer, allocation)
            return nil
        }

        vmaDestroyBuffer(allocator, buffer, allocation)
        return vulkanTexture
    }
    
    private func createImage(width: UInt32, height: UInt32, format: VkFormat, samplerOverride: VkSampler?) -> VulkanTexture? {
        var imageInfo = VkImageCreateInfo()
        imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
        imageInfo.imageType = VK_IMAGE_TYPE_2D
        imageInfo.extent.width = width
        imageInfo.extent.height = height
        imageInfo.extent.depth = 1
        imageInfo.mipLevels = 1
        imageInfo.arrayLayers = 1
        imageInfo.format = format
        imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL
        imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        imageInfo.usage = UInt32(VK_IMAGE_USAGE_TRANSFER_DST_BIT.rawValue) | UInt32(VK_IMAGE_USAGE_SAMPLED_BIT.rawValue)
        imageInfo.samples = VK_SAMPLE_COUNT_1_BIT
        imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE
        
        var allocInfo = VmaAllocationCreateInfo()
        allocInfo.usage = VMA_MEMORY_USAGE_GPU_ONLY
        
        var image: VkImage?
        var allocation: VmaAllocation?
        
        let result = vmaCreateImage(allocator, &imageInfo, &allocInfo, &image, &allocation, nil)
        guard result == VK_SUCCESS, let createdImage = image, let createdAllocation = allocation else {
            print("Failed to create image: \(result)")
            return nil
        }
        
        // Create image view
        guard let imageView = createImageView(createdImage, format: format) else {
            vmaDestroyImage(allocator, createdImage, createdAllocation)
            return nil
        }
        
        return VulkanTexture(image: createdImage, imageView: imageView, sampler: samplerOverride, allocation: createdAllocation)
    }
    
    private func createImageView(_ image: VkImage, format: VkFormat) -> VkImageView? {
        var viewInfo = VkImageViewCreateInfo()
        viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
        viewInfo.image = image
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D
        viewInfo.format = format
        viewInfo.subresourceRange.aspectMask = UInt32(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
        viewInfo.subresourceRange.baseMipLevel = 0
        viewInfo.subresourceRange.levelCount = 1
        viewInfo.subresourceRange.baseArrayLayer = 0
        viewInfo.subresourceRange.layerCount = 1
        
        var imageView: VkImageView?
        let result = vkCreateImageView(device, &viewInfo, nil, &imageView)
        guard result == VK_SUCCESS, let createdView = imageView else {
            print("Failed to create image view: \(result)")
            return nil
        }
        
        return createdView
    }
    
    private func transitionImageLayout(_ image: VkImage, format: VkFormat, 
                                     oldLayout: VkImageLayout, newLayout: VkImageLayout) -> Bool {
        guard let commandBuffer = beginSingleTimeCommands() else { return false }
        
        var barrier = VkImageMemoryBarrier()
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
        barrier.oldLayout = oldLayout
        barrier.newLayout = newLayout
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.image = image
        barrier.subresourceRange.aspectMask = UInt32(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
        barrier.subresourceRange.baseMipLevel = 0
        barrier.subresourceRange.levelCount = 1
        barrier.subresourceRange.baseArrayLayer = 0
        barrier.subresourceRange.layerCount = 1
        
        var sourceStage: VkPipelineStageFlags
        var destinationStage: VkPipelineStageFlags
        
        if oldLayout == VK_IMAGE_LAYOUT_UNDEFINED && newLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL {
            barrier.srcAccessMask = 0
            barrier.dstAccessMask = UInt32(VK_ACCESS_TRANSFER_WRITE_BIT.rawValue)
            sourceStage = UInt32(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT.rawValue)
            destinationStage = UInt32(VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue)
        } else if oldLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL && newLayout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL {
            barrier.srcAccessMask = UInt32(VK_ACCESS_TRANSFER_WRITE_BIT.rawValue)
            barrier.dstAccessMask = UInt32(VK_ACCESS_SHADER_READ_BIT.rawValue)
            sourceStage = UInt32(VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue)
            destinationStage = UInt32(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT.rawValue)
        } else {
            print("Unsupported layout transition!")
            endSingleTimeCommands(commandBuffer)
            return false
        }
        
        vkCmdPipelineBarrier(commandBuffer, sourceStage, destinationStage, 0, 0, nil, 0, nil, 1, &barrier)
        
        endSingleTimeCommands(commandBuffer)
        return true
    }
    
    private func copyBufferToImage(_ buffer: VkBuffer, _ image: VkImage, width: UInt32, height: UInt32) -> Bool {
        guard let commandBuffer = beginSingleTimeCommands() else { return false }
        
        var region = VkBufferImageCopy()
        region.bufferOffset = 0
        region.bufferRowLength = 0
        region.bufferImageHeight = 0
        region.imageSubresource.aspectMask = UInt32(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
        region.imageSubresource.mipLevel = 0
        region.imageSubresource.baseArrayLayer = 0
        region.imageSubresource.layerCount = 1
        region.imageOffset = VkOffset3D(x: 0, y: 0, z: 0)
        region.imageExtent = VkExtent3D(width: width, height: height, depth: 1)
        
        vkCmdCopyBufferToImage(commandBuffer, buffer, image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region)
        
        endSingleTimeCommands(commandBuffer)
        return true
    }
    
    private func beginSingleTimeCommands() -> VkCommandBuffer? {
        var allocInfo = VkCommandBufferAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
        allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
        allocInfo.commandPool = commandPool
        allocInfo.commandBufferCount = 1
        
        var commandBuffer: VkCommandBuffer?
        guard vkAllocateCommandBuffers(device, &allocInfo, &commandBuffer) == VK_SUCCESS,
              let buffer = commandBuffer else {
            return nil
        }
        
        var beginInfo = VkCommandBufferBeginInfo()
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
        beginInfo.flags = UInt32(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT.rawValue)
        
        vkBeginCommandBuffer(buffer, &beginInfo)
        return buffer
    }
    
    private func endSingleTimeCommands(_ commandBuffer: VkCommandBuffer) {
        vkEndCommandBuffer(commandBuffer)
        
        var submitInfo = VkSubmitInfo()
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
        submitInfo.commandBufferCount = 1
        submitInfo.pCommandBuffers = withUnsafePointer(to: commandBuffer) { $0 }
        
        vkQueueSubmit(graphicsQueue, 1, &submitInfo, nil)
        vkQueueWaitIdle(graphicsQueue)
        
        vkFreeCommandBuffers(device, commandPool, 1, withUnsafePointer(to: commandBuffer) { $0 })
    }
    
    private func cleanup(texture: VulkanTexture) {
        if let imageView = texture.imageView {
            vkDestroyImageView(device, imageView, nil)
        }
        vmaDestroyImage(allocator, texture.image, texture.allocation)
    }
    
    // Public methods for accessing textures
    public func getVulkanTexture(at index: Int) -> VulkanTexture? {
        guard index >= 0 && index < textures.count else {
            return nil
        }
        return textures[index]
    }
    
    public func getDefaultTexture() -> VulkanTexture? {
        if let defaultTextureIndex,
           defaultTextureIndex >= 0,
           defaultTextureIndex < textures.count {
            return textures[defaultTextureIndex]
        }
        return textures.first
    }
    
    public func getTextureCount() -> Int {
        return textures.count
    }
}

// Helper struct for Vulkan texture data
public struct VulkanTexture {
    let image: VkImage
    let imageView: VkImageView?
    let sampler: VkSampler?
    let allocation: VmaAllocation
}
