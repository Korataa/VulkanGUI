import Foundation
import Cvulkan
import Cvma

/// Manages the connection between Materials and their shader representation
public class MaterialShaderBinding {
    private let device: VkDevice
    private let materialUploader: MaterialUploader
    private var descriptorSetLayout: VkDescriptorSetLayout?
    private var descriptorSet: VkDescriptorSet?
    
    init(device: VkDevice, vmaAllocator: VmaAllocator) {
        self.device = device
        self.materialUploader = MaterialUploader(vmaAllocator: vmaAllocator)
        createDescriptorSetLayout()
    }
    
    private func createDescriptorSetLayout() {
        // Material uniform buffer binding
        var uniformBinding = VkDescriptorSetLayoutBinding()
        uniformBinding.binding = 0
        uniformBinding.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        uniformBinding.descriptorCount = 1
        uniformBinding.stageFlags = UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue)
        
        // Texture array bindings start at binding = 1
        var samplerBinding = VkDescriptorSetLayoutBinding()
        samplerBinding.binding = 1
        samplerBinding.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
        samplerBinding.descriptorCount = 5  // baseColor, metalRough, normal, occlusion, emissive
        samplerBinding.stageFlags = UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue)
        
        let bindings = [uniformBinding, samplerBinding]
        
        var layoutInfo = VkDescriptorSetLayoutCreateInfo()
        layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        layoutInfo.bindingCount = UInt32(bindings.count)
        
        bindings.withUnsafeBufferPointer { ptr in
            layoutInfo.pBindings = ptr.baseAddress
            var layout: VkDescriptorSetLayout?
            let result = vkCreateDescriptorSetLayout(device, &layoutInfo, nil, &layout)
            guard result == VK_SUCCESS else {
                fatalError("Failed to create material descriptor set layout")
            }
            descriptorSetLayout = layout
        }
    }
    
    /// Updates shader bindings for a material
    func update(material: Material) {
        materialUploader.update(from: material)
        updateDescriptorSet()
    }
    
    private func updateDescriptorSet() {
        // Update uniform buffer binding
        var bufferInfo = VkDescriptorBufferInfo()
        bufferInfo.buffer = materialUploader.vulkanBuffer
        bufferInfo.offset = 0
        bufferInfo.range = VkDeviceSize(MemoryLayout<MaterialData>.size)
        
        var writeSet = VkWriteDescriptorSet()
        writeSet.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        writeSet.dstSet = descriptorSet
        writeSet.dstBinding = 0
        writeSet.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        writeSet.descriptorCount = 1

        withUnsafePointer(to: bufferInfo) { bufferInfoPtr in
            writeSet.pBufferInfo = bufferInfoPtr
            vkUpdateDescriptorSets(device, 1, &writeSet, 0, nil)
        }
    }
    
    /// Gets the descriptor set layout for pipeline creation
    var layout: VkDescriptorSetLayout? { descriptorSetLayout }
    
    /// Gets the current descriptor set for binding during rendering
    var currentSet: VkDescriptorSet? { descriptorSet }
    
    func cleanup() {
        if let layout = descriptorSetLayout {
            vkDestroyDescriptorSetLayout(device, layout, nil)
        }
        materialUploader.cleanup()
    }
}
