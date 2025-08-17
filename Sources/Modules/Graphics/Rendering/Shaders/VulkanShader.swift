import Cvulkan
import Cvma
import Foundation

/// Represents a Vulkan shader with its associated pipeline and descriptor sets.
/// Owns and manages shader modules, descriptor sets, and material bindings.
public class VulkanShader: Shader {
    // MARK: - Resource Protocol
    public var name: String?
    private var _id: Int?
    public var id: Int? {
        get { _id }
        set {
            precondition(_id == nil, "Id can only be set once!")
            _id = newValue
        }
    }
    
    public var resourceType: ResourceCategory {
        return .graphics(.shader)
    }
    
    // MARK: - Private Properties
    private let device: VkDevice
    private let vmaAllocator: VmaAllocator
    private let textureManager: VulkanTextureManager?
    
    // Shader modules (owned)
    private var vertexModule: VkShaderModule?
    private var fragmentModule: VkShaderModule?
    
    // Pipeline and descriptor resources (owned)
    private var pipelineLayout: VkPipelineLayout?
    private var descriptorSetLayouts: [VkDescriptorSetLayout?] = []
    private var descriptorPool: VkDescriptorPool?
    
    // Transform descriptor set (externally managed buffer)
    private var transformDescriptorSet: VkDescriptorSet?
    
    // Material binding (owned)
    private var materialBinding: MaterialShaderBinding?
    
    private var descriptorSetsReady = false
    
    // MARK: - Initialization
    public init(device: VkDevice, vmaAllocator: VmaAllocator, textureManager: VulkanTextureManager? = nil) {
        self.device = device
        self.vmaAllocator = vmaAllocator
        self.textureManager = textureManager
    }
    
    // MARK: - Resource Protocol
    public func cleanup() {
        // Clean up shader modules
        if let module = vertexModule {
            vkDestroyShaderModule(device, module, nil)
            vertexModule = nil
        }
        if let module = fragmentModule {
            vkDestroyShaderModule(device, module, nil)
            fragmentModule = nil
        }
        
        // Clean up descriptor resources
        for layout in descriptorSetLayouts {
            if let layout = layout {
                vkDestroyDescriptorSetLayout(device, layout, nil)
            }
        }
        descriptorSetLayouts.removeAll()
        
        if let pool = descriptorPool {
            vkDestroyDescriptorPool(device, pool, nil)
            descriptorPool = nil
        }
        
        if let layout = pipelineLayout {
            vkDestroyPipelineLayout(device, layout, nil)
            pipelineLayout = nil
        }
        
        // Clean up transform descriptor set (buffer is externally owned)
        transformDescriptorSet = nil
        
        // Clean up material binding
        materialBinding?.cleanup()
        materialBinding = nil
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Shader Protocol
    public func load(vertexPath: String, fragmentPath: String) throws {
        // Load shader modules
        guard let vertexData = try? Data(contentsOf: URL(fileURLWithPath: vertexPath)) else {
            throw ShaderError.fileNotFound
        }
        vertexModule = try createShaderModule(code: vertexData)
        
        guard let fragmentData = try? Data(contentsOf: URL(fileURLWithPath: fragmentPath)) else {
            throw ShaderError.fileNotFound
        }
        fragmentModule = try createShaderModule(code: fragmentData)
        
        guard vertexModule != nil && fragmentModule != nil else {
            throw ShaderError.invalidShader
        }
        
        // Create descriptor resources
        try createDescriptorSetLayout()
        try createDescriptorPool()
        try createPipelineLayout()
        
        // Create material binding - will be set up later when material buffer is available
        // Call setupMaterialBinding(materialBuffer:) after material UBO is created
        if textureManager != nil {
            print("Note: MaterialShaderBinding will be set up later when material buffer is available")
        } else {
            print("Warning: VulkanShader created without textureManager - textures will not be available")
        }
        
        // Note: Descriptor sets should be allocated separately when buffer is available
        // Call setupDescriptorSets(transformBuffer:) after creating the transform buffer
    }
    
    public func setupDescriptorSets(transformBuffer: borrowing VulkanBuffer) throws {
        try allocateDescriptorSets(transformBuffer: transformBuffer)
        descriptorSetsReady = true
    }
    
    public func setupMaterialBinding(materialBuffer: VkBuffer) {
        guard let textureManager = textureManager else {
            print("Warning: Cannot setup MaterialShaderBinding without textureManager")
            return
        }
        
        materialBinding = MaterialShaderBinding(
            device: device,
            textureManager: textureManager,
            materialBuffer: materialBuffer
        )
        print("DEBUG: MaterialShaderBinding set up in VulkanShader")
    }
    
    public func getMaterialBinding() -> MaterialShaderBinding? {
        return materialBinding
    }
    
    public func bind(commandBuffer: VkCommandBuffer, frameIndex: Int = 0) {
        guard let pipelineLayout = pipelineLayout else { return }

        // Bind transform descriptor set if available
        if let transformDescriptorSet = transformDescriptorSet {
            withUnsafePointer(to: transformDescriptorSet) { transformSetPtr in
                vkCmdBindDescriptorSets(
                    commandBuffer,
                    VK_PIPELINE_BIND_POINT_GRAPHICS,
                    pipelineLayout,
                    0,                  // First set
                    1,                  // Number of sets
                    transformSetPtr,
                    0,
                    nil
                )
            }
        }
        
        // Bind material descriptor set if available
        if let materialBinding = materialBinding,
           let materialDescriptorSet = materialBinding.getDescriptorSet(frameIndex: frameIndex) {
            withUnsafePointer(to: materialDescriptorSet) { materialSetPtr in
                vkCmdBindDescriptorSets(
                    commandBuffer,
                    VK_PIPELINE_BIND_POINT_GRAPHICS,
                    pipelineLayout,
                    1,                      // Second set (after transforms)
                    1,                      // Number of sets
                    materialSetPtr,
                    0,
                    nil
                )
            }
        }
    }
    
    // Protocol-required method for Shader conformance
    public func bind(commandBuffer: OpaquePointer) {
        bind(commandBuffer: commandBuffer, frameIndex: 0)
    }
    
    public func setMaterial(_ material: Material) throws {
        guard let materialBinding = materialBinding else {
            throw ShaderError.bindingFailed("Material binding not initialized")
        }
        materialBinding.update(material: material)
    }
    
    public func setTransform(model: Matrix4x4, view: Matrix4x4, projection: Matrix4x4) {
        // Note: Transform buffer upload should be handled externally
        // Descriptor sets must be set up first via setupDescriptorSets(transformBuffer:)
        if !descriptorSetsReady {
            print("Warning: Descriptor sets not ready. Call setupDescriptorSets(transformBuffer:) first.")
            return
        }
        // This method assumes descriptor sets were already set up with the buffer
    }
    
    public func updateTransform(transformBuffer: borrowing VulkanBuffer) {
        if descriptorSetsReady {
            updateTransformDescriptorSet(transformBuffer: transformBuffer)
        }
    }
    
    // MARK: - Private Methods
    private func createShaderModule(code: Data) throws -> VkShaderModule? {
        var createInfo = VkShaderModuleCreateInfo()
        createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
        createInfo.codeSize = code.count
        
        return try code.withUnsafeBytes { ptr in
            createInfo.pCode = ptr.baseAddress?.assumingMemoryBound(to: UInt32.self)
            var shaderModule: VkShaderModule?
            let result = vkCreateShaderModule(device, &createInfo, nil, &shaderModule)
            guard result == VK_SUCCESS else {
                throw ShaderError.compilationFailed("Failed to create shader module")
            }
            return shaderModule
        }
    }
    
    private func createDescriptorSetLayout() throws {
        // Create transform descriptor set layout (set 0)
        let transformBinding = createBinding(
            binding: 0,
            type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            stages: UInt32(VK_SHADER_STAGE_VERTEX_BIT.rawValue)
        )
        
        // Create material descriptor set layout (set 1)
        let materialBinding = createBinding(
            binding: 0,
            type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            stages: UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue)
        )
        
        let textureBinding = createBinding(
            binding: 1,
            type: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            stages: UInt32(VK_SHADER_STAGE_FRAGMENT_BIT.rawValue)
        )
        
        descriptorSetLayouts = try [
            createLayout(bindings: [transformBinding]),
            createLayout(bindings: [materialBinding, textureBinding])
        ]
    }
    
    private func createBinding(
        binding: UInt32,
        type: VkDescriptorType,
        stages: VkShaderStageFlags
    ) -> VkDescriptorSetLayoutBinding {
        var layoutBinding = VkDescriptorSetLayoutBinding()
        layoutBinding.binding = binding
        layoutBinding.descriptorType = type
        layoutBinding.descriptorCount = 1
        layoutBinding.stageFlags = stages
        return layoutBinding
    }
    
    private func createLayout(bindings: [VkDescriptorSetLayoutBinding]) throws -> VkDescriptorSetLayout? {
        var layoutInfo = VkDescriptorSetLayoutCreateInfo()
        layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
        layoutInfo.bindingCount = UInt32(bindings.count)
        
        return try bindings.withUnsafeBufferPointer { ptr in
            layoutInfo.pBindings = ptr.baseAddress
            var layout: VkDescriptorSetLayout?
            let result = vkCreateDescriptorSetLayout(device, &layoutInfo, nil, &layout)
            guard result == VK_SUCCESS else {
                throw ShaderError.bindingFailed("Failed to create descriptor set layout")
            }
            return layout
        }
    }
    
    private func createDescriptorPool() throws {
        let poolSizes = [
            createPoolSize(type: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, count: 1000),
            createPoolSize(type: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, count: 1000)
        ]
        
        var poolInfo = VkDescriptorPoolCreateInfo()
        poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
        poolInfo.poolSizeCount = UInt32(poolSizes.count)
        poolInfo.maxSets = 1000
        
        try poolSizes.withUnsafeBufferPointer { ptr in
            poolInfo.pPoolSizes = ptr.baseAddress
            let result = vkCreateDescriptorPool(device, &poolInfo, nil, &descriptorPool)
            guard result == VK_SUCCESS else {
                throw ShaderError.bindingFailed("Failed to create descriptor pool")
            }
        }
    }
    
    private func createPoolSize(type: VkDescriptorType, count: UInt32) -> VkDescriptorPoolSize {
        var poolSize = VkDescriptorPoolSize()
        poolSize.type = type
        poolSize.descriptorCount = count
        return poolSize
    }
    
    private func createPipelineLayout() throws {
        var layoutInfo = VkPipelineLayoutCreateInfo()
        layoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
        layoutInfo.setLayoutCount = UInt32(descriptorSetLayouts.count)
        
        try descriptorSetLayouts.withUnsafeBufferPointer { layoutsPtr in
            layoutInfo.pSetLayouts = UnsafePointer(layoutsPtr.baseAddress)
            let result = vkCreatePipelineLayout(device, &layoutInfo, nil, &pipelineLayout)
            guard result == VK_SUCCESS else {
                throw ShaderError.bindingFailed("Failed to create pipeline layout")
            }
        }
    }
    
    private func allocateDescriptorSets(transformBuffer: borrowing VulkanBuffer) throws {
        // Allocate transform descriptor set
        var allocInfo = VkDescriptorSetAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
        allocInfo.descriptorPool = descriptorPool
        allocInfo.descriptorSetCount = 1
        
        if let layout = descriptorSetLayouts[0] {
            allocInfo.pSetLayouts = [layout].withUnsafeBufferPointer { $0.baseAddress }
            let result = vkAllocateDescriptorSets(device, &allocInfo, &transformDescriptorSet)
            guard result == VK_SUCCESS else {
                throw ShaderError.bindingFailed("Failed to allocate transform descriptor set")
            }
        }
        
        updateTransformDescriptorSet(transformBuffer: transformBuffer)
    }
    
    private func updateTransformDescriptorSet(transformBuffer: borrowing VulkanBuffer) {
        let transformDescriptorSet = transformDescriptorSet
        
        var bufferInfo = VkDescriptorBufferInfo()
        bufferInfo.buffer = transformBuffer.bufferHandle.asVulkanBuffer()
        bufferInfo.offset = 0
        bufferInfo.range = VkDeviceSize(MemoryLayout<Matrix4x4>.size * 3)
        
        var writeSet = VkWriteDescriptorSet()
        writeSet.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
        writeSet.dstSet = transformDescriptorSet
        writeSet.dstBinding = 0
        writeSet.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
        writeSet.descriptorCount = 1
        withUnsafePointer(to: bufferInfo) { bufferInfoPtr in
            writeSet.pBufferInfo = bufferInfoPtr
            vkUpdateDescriptorSets(device, 1, &writeSet, 0, nil)
        }
    }
}