import Cvulkan
import Cvma

public class Graphics {
    // Struct to bundle info for ResourceSystem
    public struct ResourceSystemInfo {
        public let device: VkDevice
        public let vmaAllocator: VmaAllocator
        public let totalVRAM: UInt64
        public let graphicsResourceManager: VulkanResourceManager
    }

    public func getResourceSystemInfo() -> ResourceSystemInfo? {
        guard let device = renderer.logicalDevice,
              let allocator = renderer.vmaAllocator,
              let resourceManager = graphicsResourceManager else {
            return nil
        }
        return ResourceSystemInfo(
            device: device,
            vmaAllocator: allocator,
            totalVRAM: renderer.getTotalVRAM(),
            graphicsResourceManager: resourceManager
        )
    }

    private var pipelineManager: PipelineManager!

    private var renderer: VulkanRenderer
    private var sdlContext: SDLContext

    var graphicsResourceManager: VulkanResourceManager?
    
    // Public accessor for the resource manager
    public var resourceManager: VulkanResourceManager {
        return graphicsResourceManager!
    }

    var renderModels: [Model] = []        //Models to render
    private var debugPrinted = false     // Only print debug info once

    public init(sdlContext: SDLContext) {
        self.sdlContext = sdlContext
        renderer = VulkanRenderer(context: sdlContext)
        // Note: renderer.initialize() will be called in Graphics.initialize()
        
        // Resource manager will be created in Graphics.initialize() after renderer is ready
        self.graphicsResourceManager = nil
    }

    public init(sdlContext: SDLContext, graphicsResourceManager: VulkanResourceManager) {
        self.sdlContext = sdlContext
        renderer = VulkanRenderer(context: sdlContext)
        renderer.initialize()
        self.graphicsResourceManager = graphicsResourceManager
        renderer.setResourceManager(graphicsResourceManager)
    }

    public func initialize() {
        renderer.initialize()
        
        // Initialize pipeline manager with renderer reference
        pipelineManager = PipelineManager(backend: .Vulkan, renderer: renderer)
        
        // Create resource manager after renderer is initialized with proper device context
        guard let device = renderer.logicalDevice,
              let allocator = renderer.vmaAllocator,
              let transferPool = renderer.transferCommandPool,
              let transferQueue = renderer.queueManager?.transferQueue else {
            fatalError("Renderer not properly initialized - missing device, allocator, or transfer resources")
        }
        
        self.graphicsResourceManager = VulkanResourceManager(
            device: device,
            vmaAllocator: allocator,
            totalVRAM: renderer.getTotalVRAM(),
            transferCommandPool: transferPool,
            transferQueue: transferQueue
        )
        renderer.setResourceManager(self.graphicsResourceManager!)
        
        // Initialize the resource manager after it's created and set on the renderer
        do {
            try graphicsResourceManager?.initialize()
        } catch {
            fatalError("Failed to initialize graphics resource manager: \(error)")
        }
    }

    // MARK: - High-Level Rendering API
    
    /// Render a single 3D model - this is the high-level API game code uses
    public func render3DModel(_ model: Model) {
        let pipeline = get3DPipeline()
        if let vulkanPipeline = pipeline as? VulkanPipelineImpl {
            vulkanPipeline.render(models: [model])
        }
    }
    
    /// Render multiple 3D models efficiently 
    public func render3DModels(_ models: [Model]) {
        if !models.isEmpty {
            let pipeline = get3DPipeline()
            if let vulkanPipeline = pipeline as? VulkanPipelineImpl {
                vulkanPipeline.render(models: models)
            }
        }
    }
    
    /// Render a 2D sprite - high-level API for 2D rendering
    public func render2DSprite(at position: (Float, Float), size: (Float, Float), textureID: UInt32? = nil) {
        // TODO: Create a simple quad model for 2D sprites and render it with the 2D pipeline
        let pipeline = get2DPipeline()
        pipeline.bind()
        // Implementation would create a quad mesh and render it
        pipeline.unbind()
    }
    
    /// Render UI element - high-level API for UI rendering  
    public func renderUIElement(at position: (Float, Float), size: (Float, Float), textureID: UInt32? = nil) {
        let pipeline = getUIPipeline()
        pipeline.bind()
        // Implementation would create UI quad and render it
        pipeline.unbind()
    }

    //Rendering stuff gets updated in here!!
    public func update() {
        // Begin frame and get swapchain image index
        guard let imageIndex = renderer.acquireFrame() else {
            // Frame was skipped (swapchain recreation, etc.)
            return
        }
        
        // Begin render pass
        renderer.beginRenderPass(imageIndex: imageIndex)
        
        // Debug: Print model count and details
        if !renderModels.isEmpty {
            print("Rendering \(renderModels.count) models:")
            for (i, model) in renderModels.enumerated() {
                print("  Model \(i): \(model.meshes.count) meshes, transform: \(model.transform)")
            }
        } else {
            print("No models to render!")
        }
        
        // Use the high-level pipeline system to render all models
        if !renderModels.isEmpty {
            render3DModels(renderModels)
        }
        
        // End render pass and present frame
        renderer.presentFrame(imageIndex: imageIndex)
    }

    ///Everytime model is added to scene this must be called (or the alternative version of this method)
    public func addModel(model: Model) {
        renderModels.append(model)
    }
    
    public func createTexturesFromResourceManager() {
        renderer.createTexturesFromResourceManager()
    }

    ///Everytime model is added to scene this must be called (or the alternative version of this method)
    public func addModel(mesh: Mesh, transform: Transform) {
        renderModels.append(Model(
            meshes: [mesh], transform: transform
        ))
    }

    /// Set the camera for rendering
    public func setCamera(_ camera: Camera) {
        renderer.camera = camera
    }
    
    /// Get the current aspect ratio from the renderer
    public func getAspectRatio() -> Float {
        return renderer.getAspectRatio()
    }
    
    // MARK: - Pipeline Helper Methods
    
    /// Create or get a 3D graphics pipeline for rendering models
    private func get3DPipeline() -> Pipeline {
        let descriptor = PipelineDescriptor(
            type: .Graphics3D,
            vertexShader: loadShaderIfNeeded("shader.vert"), // You'll implement this
            fragmentShader: loadShaderIfNeeded("shader.frag"), // You'll implement this
            blendMode: .None,
            depthTest: true,
            cullMode: .Back
        )
        return pipelineManager.createOrGetPipeline(desc: descriptor, device: renderer.logicalDevice)
    }
    
    /// Create or get a 2D graphics pipeline for sprites
    private func get2DPipeline() -> Pipeline {
        let descriptor = PipelineDescriptor(
            type: .Graphics2D,
            vertexShader: loadShaderIfNeeded("sprite.vert"), // You'll implement this
            fragmentShader: loadShaderIfNeeded("sprite.frag"), // You'll implement this
            blendMode: .Alpha,
            depthTest: false,
            cullMode: .None
        )
        return pipelineManager.createOrGetPipeline(desc: descriptor, device: renderer.logicalDevice)
    }
    
    /// Create or get a UI pipeline
    private func getUIPipeline() -> Pipeline {
        let descriptor = PipelineDescriptor(
            type: .UI,
            vertexShader: loadShaderIfNeeded("ui.vert"), // You'll implement this
            fragmentShader: loadShaderIfNeeded("ui.frag"), // You'll implement this
            blendMode: .Alpha,
            depthTest: false,
            cullMode: .None
        )
        return pipelineManager.createOrGetPipeline(desc: descriptor, device: renderer.logicalDevice)
    }
    
    /// Helper to load shader source (you'll need to implement this based on how you load shaders)
    private func loadShaderIfNeeded(_ filename: String) -> String? {
        // TODO: Implement shader loading from your Assets/Shaders directory
        // For now, return nil - the pipeline implementation should handle this
        return nil
    }

    public func cleanup() {
        pipelineManager?.cleanupAllPipelines()
        renderer.cleanup()
    }
}