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

    func render(commandBuffer: Any) {
        // Example of using the new pipeline system
        // You'll create pipeline descriptors based on what you need to render
        
        // Example: 3D graphics pipeline for models
        let graphics3DDescriptor = PipelineDescriptor(
            type: .Graphics3D,
            vertexShader: nil, // You'll load these from your shader files
            fragmentShader: nil,
            blendMode: .None,
            depthTest: true,
            cullMode: .Back
        )
        
        let pipeline3D = pipelineManager.createOrGetPipeline(
            desc: graphics3DDescriptor,
            device: renderer.logicalDevice
        )
        
        pipeline3D.bind()
        // Your 3D model rendering code would go here
        // This is where you'd call renderer methods to actually draw
        pipeline3D.unbind()
    }

    //Rendering stuff gets updated in here!!
    public func update() {
        // Begin frame and get swapchain image index
        guard let imageIndex = renderer.beginFrame() else {
            // Frame was skipped (swapchain recreation, etc.)
            return
        }
        
        // Debug: Print model count and details
        if !renderModels.isEmpty {
            print("Rendering \(renderModels.count) models:")
            for (i, model) in renderModels.enumerated() {
                print("  Model \(i): \(model.meshes.count) meshes, transform: \(model.transform)")
            }
        } else {
            print("No models to render!")
        }
        
        // Render all models
        renderer.render(models: renderModels)
        
        // End frame and present
        renderer.endFrame(imageIndex: imageIndex)
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