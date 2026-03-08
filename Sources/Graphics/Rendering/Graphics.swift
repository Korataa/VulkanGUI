import Platform
import Core
import Math
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

    public var renderSettings: RenderSettings()
    
    // Public accessor for the resource manager
    public var resourceManager: VulkanResourceManager {
        return graphicsResourceManager!
    }

    var renderModels: [Model] = []        //Models to render
    private var uiElements: [UIRenderable] = []      //UI elements to render
    private var debugPrinted = false     // Only print debug info once
    
    /// Public accessor for UI elements count
    public var uiElementCount: Int { uiElements.count }

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
    
    /// Render a single 3D model - used by this class internally
    private func render3DModel(_ model: Model) {
        let pipeline = get3DPipeline()
        if let vulkanPipeline = pipeline as? VulkanPipelineImpl {
            vulkanPipeline.render(models: [model])
        }
    }
    
    /// Render multiple 3D models efficiently 
    private func render3DModels(_ models: [Model]) {
        print("🎯 Graphics.render3DModels called with \(models.count) models")
        if !models.isEmpty {
            let pipeline = get3DPipeline()
            print("🎯 Got pipeline: \(type(of: pipeline))")
            if let vulkanPipeline = pipeline as? VulkanPipelineImpl {
                print("🎯 Successfully cast to VulkanPipelineImpl, calling render()")
                vulkanPipeline.render(models: models)
            } else {
                print("❌ Failed to cast pipeline to VulkanPipelineImpl!")
            }
        } else {
            print("❌ No models to render!")
        }
    }
    
    /// Add a UI element to be rendered every frame
    public func addUIElement(_ renderable: UIRenderable) {
        uiElements.append(renderable)
    }
    
    /// Remove a UI element from rendering
    public func removeUIElement(_ renderable: UIRenderable) {
        uiElements.removeAll { $0 === renderable }
    }
    
    /// Clear all UI elements
    public func clearUIElements() {
        uiElements.removeAll()
    }
    
    /// Render all UI elements using the clean ModelUI architecture (mirrors 3D rendering)
    public func renderUIElements() {
        guard !uiElements.isEmpty else { return }
        
        // Check if any elements are dirty (need GPU upload)
        let dirtyElements = uiElements.filter { $0.isDirty }
        let newElements = uiElements.filter { !$0.isUploaded }
        
        // Only reset buffers AND upload IF we actually have dirty/new elements
        if !dirtyElements.isEmpty || !newElements.isEmpty {
            print("📤 Found \(dirtyElements.count) dirty + \(newElements.count) new UI elements - uploading")
            // Reset buffer offsets BEFORE uploading (critical!)
            graphicsResourceManager?.reset2DBuffers()
            // Mark ALL existing elements as needing re-upload after reset
            for element in uiElements {
                element.markNotUploaded()
            }
            // Upload ALL elements (since we reset the buffer)
            uploadUIElements(uiElements)
        } else {
            print("♻️ No UI changes detected - skipping upload")
        }
        
        let uiModels = [ModelUI(from: uiElements)]
        
        // Filter out empty models
        let nonEmptyModels = uiModels.filter { !$0.isEmpty }
        guard !nonEmptyModels.isEmpty else {
            print("📦 No UI models to render - INTENTIONALLY BROKEN FOR TESTING")
            return
        }
        
        // Use existing UI pipeline (same pattern as 3D rendering)
        let pipeline = getUIPipeline()
        if let vulkanPipeline = pipeline as? VulkanPipelineImpl {
            print("🎨 Rendering UI using ModelUI architecture")
            vulkanPipeline.renderUI(models: nonEmptyModels)
        } else {
            print("❌ Failed to get UI pipeline for rendering")
        }
    }
    
    /// Upload UI elements to GPU using dynamic buffers (like dynamic 3D models)
    /// 
    /// TODO: Performance optimization - Currently treats all UI as dynamic for simplicity.
    /// Could be optimized by categorizing UI elements:
    /// - Static UI (buttons, panels) -> allocate once like 3D models  
    /// - Dynamic UI (health bars, animations) -> use current approach
    /// - Semi-dynamic UI (text) -> hybrid approach with change detection
    /// Only optimize if UI becomes a bottleneck (very unlikely in 3D games)
    private func uploadUIElements(_ renderables: [UIRenderable]) {
        guard !renderables.isEmpty else { return }

        print("📤 Uploading \(renderables.count) dynamic UI elements")

        do {
            for renderable in renderables {
                // Use 2D allocation for UI elements (NOT 3D allocation!)
                if let vertexRegion = try graphicsResourceManager?.allocate2DVertices(vertices: renderable.vertices) {
                    if let indexRegion = try graphicsResourceManager?.allocate2DIndices(indices: renderable.indices) {
                        // Store offsets like Mesh does (not BufferRegion)
                        renderable.markUploaded(
                            vertexOffset: vertexRegion.offset / MemoryLayout<Vertex2D>.stride,
                            indexOffset: indexRegion.offset / MemoryLayout<UInt32>.stride
                        )
                    }
                }
            }
        } catch {
            print("❌ Error uploading dynamic UI elements: \(error)")
        }
    }
    
    /// Create a simple 2D sprite/quad - convenience method
    public func createSprite(at position: (Float, Float), size: (Float, Float), color: Color = Color.white, textureID: UInt32? = nil) -> UIRenderable {
        return UIRenderable(position: SIMD2(position.0, position.1), 
                           size: SIMD2(size.0, size.1), 
                           color: color, 
                           textureID: textureID)
    }

    //MARK: - Frame Management (Input Latency Optimized)
    
    private var currentImageIndex: UInt32?
    
    /// Phase 1: Create frame and begin render pass - call before polling input
    public func createFrame() -> Bool {
        guard let imageIndex = renderer.createFrame() else {
            currentImageIndex = nil
            return false // Frame was skipped (swapchain recreation, etc.)
        }
        currentImageIndex = imageIndex
        return true
    }
    
    /// Phase 2: Render all objects and present the frame - call after polling input
    public func presentFrame() {
        guard let imageIndex = currentImageIndex else {
            print("ERROR: presentFrame() called without successful createFrame()")
            return
        }
        
        // Debug: Print model count (quietly)
        if renderModels.isEmpty {
            print("No models to render!")
        }
        
        // Use the high-level pipeline system to render all models
        if !renderModels.isEmpty {
            render3DModels(renderModels)
        }
        
        // Render UI elements on top of 3D models
        renderUIElements()
        
        // End render pass and present frame
        renderer.renderFrame(imageIndex: imageIndex)
        currentImageIndex = nil
    }
    
    /// Legacy method - use createFrame() + presentFrame() instead for better input latency
    public func update() {
        if createFrame() {
            presentFrame()
        }
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
        let graphics3DDescriptor = PipelineDescriptor(
            type: .Graphics3D,
            vertexShader: "vert.spv",
            fragmentShader: "frag.spv",
            blendMode: .None,
            depthTest: true,
            cullMode: .Back
        )
        return pipelineManager.createOrGetPipeline(desc: graphics3DDescriptor, device: renderer.logicalDevice)
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

    // MARK: - Pipeline Testing
    
    /// Test both 3D and UI pipeline creation - call this after initialize()  
    public func testPipelineCreation() {
        print("=== Testing Pipeline Creation ===")
        
        // Test 3D pipeline creation
        print("Creating 3D graphics pipeline...")
        let pipeline3D = get3DPipeline()
        print("✅ 3D pipeline created successfully: \(type(of: pipeline3D))")
        
        // Test UI pipeline creation  
        print("Creating UI pipeline...")
        let pipelineUI = getUIPipeline()
        print("✅ UI pipeline created successfully: \(type(of: pipelineUI))")
        
        // Test basic pipeline binding (disabled - needs command buffer context)
        print("Pipeline binding test skipped (requires command buffer recording)")
        // TODO: Test pipeline binding within actual render pass context
        
        print("=== Pipeline Test Complete ===")
    }

    public func cleanup() {
        print("🧹 Starting Graphics cleanup in proper order...")
        
        // 0. CRITICAL: Wait for all GPU operations to complete BEFORE destroying anything
        vkLog("🔄 Waiting for GPU to finish all operations before cleanup...")
        vkDeviceWaitIdle(renderer.logicalDevice)
        
        // Also reset command buffers to clear any resource references
        if let cmdBuf = renderer.commandBuffer {
            vkLog("🔄 Resetting command buffer to clear resource references")
            vkResetCommandBuffer(cmdBuf, 0)
        }
        
        // Wait again after reset to ensure all references are cleared
        vkDeviceWaitIdle(renderer.logicalDevice)
        vkLog("✅ GPU operations completed, safe to destroy resources")
        
        // 1. Clean up pipelines first (they reference resources)
        pipelineManager?.cleanupAllPipelines()
        
        // 2. Clean up resource managers BEFORE renderer (to free VMA buffers before VMA destruction)
        print("🧹 Cleaning up VulkanResourceManager buffers...")
        graphicsResourceManager?.cleanup()
        
        // 3. Finally clean up renderer (destroys VMA allocator)
        renderer.cleanup()
    }
}