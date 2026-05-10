import Platform
import Core
import Cvulkan
import Logging

//High level pipeline types
public enum PipelineType {
    case Graphics2D
    case Graphics3D
    case PostProcessing
    case Compute
    case UI
    case UITextSDF
}

//High level pipeline descriptor - no api specific details needed
public struct PipelineDescriptor: Hashable {
    let type: PipelineType
    let vertexShaderSource: String?
    let fragmentShaderSource: String?
    let computeShaderSource: String?
    let blendMode: BlendMode
    let depthTest: Bool
    let cullMode: CullMode

    public init(
        type: PipelineType,
        vertexShader: String? = nil,
        fragmentShader: String? = nil,
        computeShader: String? = nil,
        blendMode: BlendMode = .Alpha,
        depthTest: Bool = true,
        cullMode: CullMode = .Back
    ) {
        self.type = type
        self.vertexShaderSource = vertexShader
        self.fragmentShaderSource = fragmentShader
        self.computeShaderSource = computeShader
        self.blendMode = blendMode
        self.depthTest = depthTest
        self.cullMode = cullMode
    }
}

//Common enums for high-level pipeline configuration
public enum BlendMode {
    case None
    case Alpha
    case Additive
    case Multiply
}

public enum CullMode {
    case None
    case Front
    case Back
    case FrontAndBack
}

//Main pipeline interface - completely abstracted from underlying graphics api
public protocol Pipeline {
    func bind()
    func unbind()
    func cleanup()
}

public class PipelineFactory {
    public static func createPipeline(
        descriptor: PipelineDescriptor, 
        backend: GraphicsBackend,
        device: Any? = nil,
        renderer: Any? = nil
        ) -> Pipeline {
            switch backend {
                case .Vulkan:
                    guard let vulkanRenderer = renderer as? VulkanRenderer else {
                        fatalError("Vulkan backend requires VulkanRenderer")
                    }
                    return VulkanPipelineImpl(descriptor: descriptor, device: device as? VkDevice, renderer: vulkanRenderer)
                case .DirectX:
                    fatalError("DirectX pipeline not implemented yet")
                case .Metal:
                    fatalError("Metal pipeline not implemented yet")
                case .OpenGL:
                    fatalError("OpenGL pipeline not implemented yet")
            }
        }
}

// MARK: - Implementation classes (internal use only)

final class VulkanPipelineImpl: Pipeline {
    private var pipelineHandle: VkPipeline?
    private var pipelineLayout: VkPipelineLayout?
    private var logicalDevice: VkDevice
    private var vulkanRenderer: VulkanRenderer
    private let descriptor: PipelineDescriptor

    //Descriptor sets for this pipeline
    private var frameDescriptorSet: VkDescriptorSet?
    private var transformDescriptorSet: VkDescriptorSet?
    private var materialDescriptorSet: VkDescriptorSet?

    init(descriptor: PipelineDescriptor, device: VkDevice?, renderer: VulkanRenderer) {
        guard let vkDevice = device else {
            fatalError("Vulkan backend requires VkDevice")
        }
        self.logicalDevice = vkDevice
        self.vulkanRenderer = renderer
        self.descriptor = descriptor
        createVulkanPipeline(from: descriptor)
        createDescriptorSets()
    }

    private func createVulkanPipeline(from descriptor: PipelineDescriptor) {

        
        // Convert high-level descriptor to low-level Vulkan parameters
        let shaderPaths = getShaderPaths(for: descriptor.type)
        let vertexInputType = getVertexInputType(for: descriptor.type)
        let descriptorSetLayouts = getDescriptorSetLayouts(for: descriptor.type)
        

        
        // Use VulkanRenderer's low-level pipeline creation with raw Vulkan parameters
        let (pipeline, layout) = vulkanRenderer.createGraphicsPipeline(
            vertexShaderPath: shaderPaths.vertex,
            fragmentShaderPath: shaderPaths.fragment,
            vertexInputType: vertexInputType,
            descriptorSetLayouts: descriptorSetLayouts,
            cullMode: convertCullMode(descriptor.cullMode),
            depthTest: descriptor.depthTest,
            blendMode: convertBlendMode(descriptor.blendMode)
        )
        
        if pipeline == nil || layout == nil {
            logError(.graphics, source: "Pipeline", "Pipeline creation failed - pipeline: \(pipeline != nil), layout: \(layout != nil)")
            fatalError("Failed to create Vulkan pipeline for type: \(descriptor.type)")
        }
        
        self.pipelineHandle = pipeline
        self.pipelineLayout = layout
        
        logInfo(.graphics, source: "Pipeline", "Created Vulkan pipeline for type: \(descriptor.type)")
    }
    
    // Helper methods to convert high-level descriptor to Vulkan specifics
    private func getShaderPaths(for type: PipelineType) -> (vertex: String, fragment: String) {
        switch type {
        case .Graphics3D:
            return ("vert.spv", "frag.spv")
        case .Graphics2D:
            return ("shader2d_vert.spv", "shader2d_frag.spv")
        case .UI:
            return ("ui_vert.spv", "ui_frag.spv")
        case .UITextSDF:
            return ("ui_vert.spv", "ui_sdf.spv")
        case .PostProcessing, .Compute:
            fatalError("PostProcessing and Compute pipelines not implemented yet")
        }
    }
    
    private func getVertexInputType(for type: PipelineType) -> String {
        switch type {
        case .Graphics3D:
            return "Vertex3D"
        case .Graphics2D, .UI, .UITextSDF:
            return "Vertex2D"
        case .PostProcessing, .Compute:
            fatalError("PostProcessing and Compute pipelines not implemented yet")
        }
    }
    
    private func getDescriptorSetLayouts(for type: PipelineType) -> [VkDescriptorSetLayout?] {
        switch type {
        case .Graphics3D:
            return [vulkanRenderer.frameSetLayout, vulkanRenderer.transformSetLayout, vulkanRenderer.materialSetLayout3D]
        case .Graphics2D:
            return [vulkanRenderer.transform2DSetLayout, vulkanRenderer.material2DSetLayout]
        case .UI, .UITextSDF:
            return [vulkanRenderer.uiProjectionSetLayout, vulkanRenderer.uiMaterialSetLayout]
        case .PostProcessing:
            return [vulkanRenderer.postProcessingSetLayout]
        case .Compute:
            fatalError("Compute pipelines not implemented yet")
        }
    }
    
    private func convertCullMode(_ cullMode: CullMode) -> VkCullModeFlags {
        switch cullMode {
        case .None:
            return VkCullModeFlags(VK_CULL_MODE_NONE.rawValue)
        case .Front:
            return VkCullModeFlags(VK_CULL_MODE_FRONT_BIT.rawValue)
        case .Back:
            return VkCullModeFlags(VK_CULL_MODE_BACK_BIT.rawValue)
        case .FrontAndBack:
            return VkCullModeFlags(VK_CULL_MODE_FRONT_AND_BACK.rawValue)
        }
    }
    
    private func convertBlendMode(_ blendMode: BlendMode) -> String {
        switch blendMode {
        case .None:
            return "None"
        case .Alpha:
            return "Alpha"
        case .Additive:
            return "Additive"
        case .Multiply:
            return "Multiply"
        }
    }

    private func createDescriptorSets() {
        //Create descriptor sets based on pipeline type
        switch descriptor.type {
        case .Graphics3D:
            frameDescriptorSet = vulkanRenderer.frameDescriptorSet
            transformDescriptorSet = vulkanRenderer.transformDescriptorSet
            materialDescriptorSet = vulkanRenderer.materialDescriptorSet
        case .Graphics2D:
            frameDescriptorSet = vulkanRenderer.frameDescriptorSet
            materialDescriptorSet = vulkanRenderer.materialDescriptorSet
        case .UI, .UITextSDF:
            frameDescriptorSet = vulkanRenderer.uiProjectionDescriptorSet
            materialDescriptorSet = vulkanRenderer.uiMaterialDescriptorSet
        case .PostProcessing:
            materialDescriptorSet = vulkanRenderer.materialDescriptorSet
        case .Compute:
            break
        }
    }

    func bind() {
        guard let pipeline = pipelineHandle, let layout = pipelineLayout else {
            fatalError("pipeline not created properly")
        }

        logTrace(.vulkan, source: "Pipeline", "Binding pipeline: \(pipeline) with layout: \(layout)")
        // Use VulkanRenderer's helper methods instead of direct Vulkan calls
        vulkanRenderer.bindPipeline(pipeline)
        logTrace(.vulkan, source: "Pipeline", "About to bind descriptor sets for pipeline type: \(descriptor.type)")
        bindDescriptorSetsForPipeline(layout: layout)
    }

    private func bindDescriptorSetsForPipeline(layout: VkPipelineLayout) {
        switch descriptor.type {
        case .Graphics3D:
            // For 3D graphics, bind frame (set 0) and material (set 2) descriptor sets only
            // The transform descriptor set (set 1) will be bound by drawModelsWithDynamicOffsets with proper per-model offsets
            if let frameSet = frameDescriptorSet {
                logTrace(.vulkan, source: "Pipeline", "Binding frame descriptor set (set 0): \(frameSet)")
                vulkanRenderer.bindDescriptorSets(pipelineLayout: layout, firstSet: 0, sets: [frameSet], dynamicOffsets: [])
            } else {
                logError(.vulkan, source: "Pipeline", "No frame descriptor set available")
            }
            if let materialSet = materialDescriptorSet {
                logTrace(.vulkan, source: "Pipeline", "Binding material descriptor set (set 2): \(materialSet)")
                vulkanRenderer.bindDescriptorSets(pipelineLayout: layout, firstSet: 2, sets: [materialSet], dynamicOffsets: [])
            } else {
                logError(.vulkan, source: "Pipeline", "No material descriptor set available")
            }
        case .Graphics2D, .UI, .UITextSDF:
            // For 2D/UI, bind all sets together since they don't need per-model dynamic offsets
            var descriptorSets: [VkDescriptorSet] = []
            if let frameSet = frameDescriptorSet { descriptorSets.append(frameSet) }
            if let materialSet = materialDescriptorSet { descriptorSets.append(materialSet) }
            
            if !descriptorSets.isEmpty {
                vulkanRenderer.bindDescriptorSets(pipelineLayout: layout, firstSet: 0, sets: descriptorSets, dynamicOffsets: [])
            }
        case .PostProcessing:
            if let materialSet = materialDescriptorSet {
                vulkanRenderer.bindDescriptorSets(pipelineLayout: layout, firstSet: 0, sets: [materialSet], dynamicOffsets: [])
            }
        case .Compute:
            break
        }
    }

    func render(models: [Model]) {
        logTrace(.graphics, source: "Pipeline", "VulkanPipelineImpl.render called with \(models.count) models")
        // Bind this pipeline and its descriptor sets
        bind()
        
        // Draw all models with proper dynamic offset handling
        guard let layout = pipelineLayout, let transformSet = transformDescriptorSet else {
            logError(.graphics, source: "Pipeline", "Missing pipeline layout or transform descriptor set")
            return
        }
        logTrace(.graphics, source: "Pipeline", "About to call drawModelsWithDynamicOffsets with \(models.count) models")
        vulkanRenderer.drawModelsWithDynamicOffsets(models, pipelineLayout: layout, transformDescriptorSet: transformSet)
    }
    
    /// Clean UI rendering that mirrors 3D model rendering
    /// Uses 2D buffers and existing UI descriptor sets
    func renderUI(models: [ModelUI]) {
        logTrace(.ui, source: "Pipeline", "VulkanPipelineImpl.renderUI called with \(models.count) UI models")
        // Bind this UI pipeline and its descriptor sets
        bind()
        
        // Draw all UI models using existing UI infrastructure
        guard let layout = pipelineLayout else {
            logError(.ui, source: "Pipeline", "Missing pipeline layout")
            return
        }
        logTrace(.ui, source: "Pipeline", "About to call drawUIModelsWithOffsets with \(models.count) UI models")
        vulkanRenderer.drawUIModelsWithOffsets(models, pipelineLayout: layout)
    }

    func unbind() {
        // Vulkan doesn't really need explicit unbinding - pipelines stay bound until replaced
        logTrace(.vulkan, source: "Pipeline", "Unbinding Vulkan pipeline (no-op)")
    }

    func cleanup() {
        vkDestroyPipeline(logicalDevice, pipelineHandle, nil)
        vkDestroyPipelineLayout(logicalDevice, pipelineLayout, nil)
    }
}

final class DirectXPipelineImpl: Pipeline {
    init(descriptor: PipelineDescriptor) {
        fatalError("DirectX pipeline not implemented yet")
    }

    func bind() {
        fatalError("DirectX pipeline not implemented yet")
    }

    func unbind() {
        fatalError("DirectX pipeline not implemented yet")
    }

    func cleanup() {
        fatalError("DirectX pipeline not implemented yet")
    }
}

final class MetalPipelineImpl: Pipeline {
    init(descriptor: PipelineDescriptor) {
        fatalError("Metal pipeline not implemented yet")
    }

    func bind() {
        fatalError("Metal pipeline not implemented yet")
    }

    func unbind() {
        fatalError("Metal pipeline not implemented yet")
    }

    func cleanup() {
        fatalError("Metal pipeline not implemented yet")
    }
}

final class OpenGLPipelineImpl: Pipeline {
    init(descriptor: PipelineDescriptor) {
        fatalError("OpenGL pipeline not implemented yet")
    }

    func bind() {
        fatalError("OpenGL pipeline not implemented yet")
    }

    func unbind() {
        fatalError("OpenGL pipeline not implemented yet")
    }

    func cleanup() {
        fatalError("OpenGL pipeline not implemented yet")
    }
}