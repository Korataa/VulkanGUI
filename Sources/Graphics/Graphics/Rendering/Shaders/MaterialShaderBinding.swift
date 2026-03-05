import Platform
import Core
import Foundation
import Cvulkan
import Cvma

/// Manages the connection between Materials and their shader representation
public class MaterialShaderBinding {
    private let device: VkDevice
    private let textureManager: VulkanTextureManager
    private var descriptorSetLayout: VkDescriptorSetLayout?
    private var descriptorPool: VkDescriptorPool?
    private var descriptorSets: [VkDescriptorSet] = []
    private let maxFramesInFlight = 2 // Should match renderer's MAX_FRAMES_IN_FLIGHT
    private var materialBuffer: VkBuffer?
    private var currentFrame = 0
    
    init(device: VkDevice, textureManager: VulkanTextureManager, materialBuffer: VkBuffer) {
        self.device = device
        self.textureManager = textureManager
        self.materialBuffer = materialBuffer
        createDescriptorSetLayout()
        createDescriptorPool()
        allocateDescriptorSets()
    }
    
    private func createDescriptorSetLayout() {
        // Material uniform buffer (dynamic)
        var uniformBinding = VkDescriptorSetLayoutBinding()
        uniformBinding.binding = 0
        uniformBinding.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC
        uniformBinding.descriptorCount = 1
        uniformBinding.stageFlags = UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue)
        
        // Add texture sampler binding for diffuse texture
        var samplerBinding = VkDescriptorSetLayoutBinding()
        samplerBinding.binding = 1
        samplerBinding.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
        samplerBinding.descriptorCount = 1  // Start with just diffuse texture
        samplerBinding.stageFlags = UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue)
        
        let bindings = [uniformBinding, samplerBinding]
        
        var layoutInfo = VkDescriptorSetLayoutCreateInfo()
        layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        layoutInfo.bindingCount = UInt32(bindings.count)
        
        bindings.withUnsafeBufferPointer { ptr in
            layoutInfo.pBindings = ptr.baseAddress
            var layout: VkDescriptorSetLayout?
            let result = vkCreateDescriptorSetLayout(device, &layoutInfo, nil, &layout)
            if let createdLayout = layout {
                vkLog("🔷 VkDescriptorSetLayout CREATED: \(createdLayout) in MaterialShaderBinding")
            }
            guard result == VK_SUCCESS else {
                fatalError("Failed to create material descriptor set layout")
            }
            descriptorSetLayout = layout
        }
    }
    
    private func createDescriptorPool() {
        // Pool sizes for material bindings
        var poolSizes = [VkDescriptorPoolSize]()
        
        // Material uniform buffer (dynamic) - multiply by frames in flight  
        var uniformPoolSize = VkDescriptorPoolSize()
        uniformPoolSize.type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC
        uniformPoolSize.descriptorCount = UInt32(maxFramesInFlight)
        poolSizes.append(uniformPoolSize)
        
        // Combined image samplers (textures) - multiply by frames in flight
        var samplerPoolSize = VkDescriptorPoolSize()
        samplerPoolSize.type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
        samplerPoolSize.descriptorCount = UInt32(maxFramesInFlight)
        poolSizes.append(samplerPoolSize)
        
        var poolInfo = VkDescriptorPoolCreateInfo()
        poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
        poolInfo.poolSizeCount = UInt32(poolSizes.count)
        poolInfo.maxSets = UInt32(maxFramesInFlight) // One set per frame in flight
        
        poolSizes.withUnsafeBufferPointer { ptr in
            poolInfo.pPoolSizes = ptr.baseAddress
            var pool: VkDescriptorPool?
            let result = vkCreateDescriptorPool(device, &poolInfo, nil, &pool)
            guard result == VK_SUCCESS else {
                fatalError("Failed to create material descriptor pool")
            }
            descriptorPool = pool
        }
    }
    
    private func allocateDescriptorSets() {
        guard let pool = descriptorPool,
              let layout = descriptorSetLayout else {
            print("ERROR: Cannot allocate descriptor sets without pool and layout")
            return
        }
        
        var allocInfo = VkDescriptorSetAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
        allocInfo.descriptorPool = pool
        allocInfo.descriptorSetCount = UInt32(maxFramesInFlight)
        
        let layouts: [VkDescriptorSetLayout?] = Array(repeating: layout, count: maxFramesInFlight)
        layouts.withUnsafeBufferPointer { layoutsPtr in
            allocInfo.pSetLayouts = layoutsPtr.baseAddress
            var sets = [VkDescriptorSet?](repeating: nil, count: maxFramesInFlight)
            let result = sets.withUnsafeMutableBufferPointer { setsPtr in
                vkAllocateDescriptorSets(device, &allocInfo, setsPtr.baseAddress)
            }
            guard result == VK_SUCCESS else {
                fatalError("Failed to allocate material descriptor sets")
            }
            descriptorSets = sets.compactMap { $0 }
            print("DEBUG: Allocated \(descriptorSets.count) descriptor sets for MaterialShaderBinding")
        }
    }
    
    /// Updates shader bindings for a material
    func update(material: Material, textureIndex: Int? = nil, frameIndex: Int = 0) {
        // Material data is managed by VulkanRenderer's material UBO, not here
        
        guard frameIndex < descriptorSets.count else {
            print("ERROR: Frame index \(frameIndex) out of range, have \(descriptorSets.count) descriptor sets")
            return
        }
        
        updateDescriptorSet(descriptorSet: descriptorSets[frameIndex], textureIndex: textureIndex ?? material.baseColorTextureIndex)
    }
    
    private func updateDescriptorSet(descriptorSet: VkDescriptorSet, textureIndex: Int?) {
        
        var descriptorWrites = [VkWriteDescriptorSet]()
        
        // Update uniform buffer binding (use the VulkanRenderer's material buffer)
        var bufferInfo = VkDescriptorBufferInfo()
        bufferInfo.buffer = materialBuffer
        bufferInfo.offset = 0
        bufferInfo.range = VK_WHOLE_SIZE  // Use VK_WHOLE_SIZE for dynamic buffers
        
        var uniformWriteSet = VkWriteDescriptorSet()
        uniformWriteSet.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        uniformWriteSet.dstSet = descriptorSet
        uniformWriteSet.dstBinding = 0
        uniformWriteSet.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC
        uniformWriteSet.descriptorCount = 1
        descriptorWrites.append(uniformWriteSet)
        
        // Update texture binding if available
        var imageInfo = VkDescriptorImageInfo()
        var textureWriteSet = VkWriteDescriptorSet()
        
        if let textureIndex = textureIndex,
           let vulkanTexture = textureManager.getVulkanTexture(at: textureIndex) {
            // Bind the actual texture
            print("DEBUG: Binding texture \(textureIndex) to material")
            imageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
            imageInfo.imageView = vulkanTexture.imageView
            imageInfo.sampler = vulkanTexture.sampler
        } else {
            // Bind default white texture if no texture available
            print("DEBUG: Binding default texture (textureIndex=\(textureIndex ?? -1))")
            if let defaultTexture = textureManager.getDefaultTexture() {
                imageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
                imageInfo.imageView = defaultTexture.imageView
                imageInfo.sampler = defaultTexture.sampler
            } else {
                print("ERROR: No default texture available!")
                return
            }
        }
        
        textureWriteSet.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        textureWriteSet.dstSet = descriptorSet
        textureWriteSet.dstBinding = 1
        textureWriteSet.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
        textureWriteSet.descriptorCount = 1
        descriptorWrites.append(textureWriteSet)

        // Submit descriptor updates
        withUnsafePointer(to: bufferInfo) { bufferInfoPtr in
            descriptorWrites[0].pBufferInfo = bufferInfoPtr
            withUnsafePointer(to: imageInfo) { imageInfoPtr in
                descriptorWrites[1].pImageInfo = imageInfoPtr
                
                descriptorWrites.withUnsafeBufferPointer { writes in
                    vkUpdateDescriptorSets(device, UInt32(writes.count), writes.baseAddress, 0, nil)
                }
            }
        }
        
        print("DEBUG: Updated material descriptor set with texture binding")
    }
    
    /// Gets the descriptor set layout for pipeline creation
    var layout: VkDescriptorSetLayout? { descriptorSetLayout }
    
    /// Gets the descriptor set for a specific frame
    func getDescriptorSet(frameIndex: Int) -> VkDescriptorSet? {
        guard frameIndex < descriptorSets.count else { return nil }
        return descriptorSets[frameIndex]
    }
    
    /// Gets the current descriptor set (frame 0 for backwards compatibility)
    var currentSet: VkDescriptorSet? { 
        descriptorSets.isEmpty ? nil : descriptorSets[0]
    }

    deinit {
        cleanup()
    }
    
    func cleanup() {
        if let pool = descriptorPool {
            vkDestroyDescriptorPool(device, pool, nil)
            descriptorPool = nil
        }
        if let layout = descriptorSetLayout {
            vkLog("🔶 VkDescriptorSetLayout DESTROYING: \(layout) in MaterialShaderBinding")
            vkDestroyDescriptorSetLayout(device, layout, nil)
            vkLog("✅ VkDescriptorSetLayout DESTROYED: \(layout) in MaterialShaderBinding")
            descriptorSetLayout = nil
        }
        // Material buffer is managed by VulkanRenderer, not here
    }
}
