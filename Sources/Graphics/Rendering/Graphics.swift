import Logging
import Platform
import Core
import Math
import Cvulkan
import Cvma

public class Graphics {
    private struct UITextBatchKey: Hashable {
        let textureID: UInt32?
        let sdfThreshold: Float
        let sdfRange: Float
        let outlineWidth: Float
        let outlineColor: Color
    }

    private struct OrderedBatch<Key: Hashable> {
        let key: Key
        var elements: [UIRenderable]
    }

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
    
    // Render configuration
    public var settings = RenderSettings()
    
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

        var visibleModels = models

        // Apply frustum culling if enabled
        if settings.frustumCulling {
            guard let camera = renderer.camera else {
                print("⚠️ No camera available for frustum culling - skipping culling")
                return // Early return instead of else
            }
            
            let frustum = renderer.calculateViewFrustum(
                projectionMatrix: camera.projectionMatrix,
                viewMatrix: camera.viewMatrix
            )

            visibleModels = models.filter { model in
                return frustum.intersects(model.boundingBox)
            }

            print("🎯 Culled \(models.count - visibleModels.count) models, rendering \(visibleModels.count)")
        }

        if !visibleModels.isEmpty {
            let pipeline = get3DPipeline()
            print("🎯 Got pipeline: \(type(of: pipeline))")
            if let vulkanPipeline = pipeline as? VulkanPipelineImpl {
                print("🎯 Successfully cast to VulkanPipelineImpl, calling render()")
                vulkanPipeline.render(models: visibleModels)
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
        
        let solidElements = uiElements.filter { !$0.usesSDF && $0.textureID == nil }
        let texturedElements = uiElements.filter { !$0.usesSDF && $0.textureID != nil }
        let sdfElements = uiElements.filter { $0.usesSDF && $0.textureID != nil }

        renderUIBatch(elements: solidElements, pipeline: getUIPipeline(), textureMode: 0, textureID: nil)

        for batch in orderedBatches(from: texturedElements, keySelector: { $0.textureID }) {
            renderUIBatch(elements: batch.elements, pipeline: getUIPipeline(), textureMode: 1, textureID: batch.key)
        }

        let sdfOrderedGroups = orderedBatches(from: sdfElements) { element in
            UITextBatchKey(
                textureID: element.textureID,
                sdfThreshold: element.sdfThreshold,
                sdfRange: element.sdfRange,
                outlineWidth: element.outlineWidth,
                outlineColor: element.outlineColor
            )
        }
        for batch in sdfOrderedGroups {
            let batchKey = batch.key
            renderUIBatch(
                elements: batch.elements,
                pipeline: getUISDFPipeline(),
                textureMode: 3,
                textureID: batchKey.textureID,
                sdfThreshold: batchKey.sdfThreshold,
                sdfRange: batchKey.sdfRange,
                outlineWidth: batchKey.outlineWidth,
                outlineColor: batchKey.outlineColor
            )
        }
    }

    private func orderedBatches<Key: Hashable>(from elements: [UIRenderable], keySelector: (UIRenderable) -> Key) -> [OrderedBatch<Key>] {
        var ordered: [OrderedBatch<Key>] = []
        var indexByKey: [Key: Int] = [:]

        for element in elements {
            let key = keySelector(element)
            if let existingIndex = indexByKey[key] {
                ordered[existingIndex].elements.append(element)
            } else {
                indexByKey[key] = ordered.count
                ordered.append(OrderedBatch(key: key, elements: [element]))
            }
        }

        return ordered
    }

    private func renderUIBatch(
        elements: [UIRenderable],
        pipeline: Pipeline,
        textureMode: Int32,
        textureID: UInt32?,
        sdfThreshold: Float? = nil,
        sdfRange: Float? = nil,
        outlineWidth: Float? = nil,
        outlineColor: Color? = nil
    ) {
        guard !elements.isEmpty else { return }

        // For solid color UI (text, rectangles) and SDF text, use the color of the first element as tint
        var tint: Color = .white
        if (textureMode == 0 || textureMode == 3), let first = elements.first {
            tint = first.color
        }

        renderer.setUIMaterial(
            textureMode: textureMode,
            textureIndex: textureID.map { Int($0) },
            tint: tint,
            sdfThreshold: sdfThreshold,
            sdfRange: sdfRange,
            outlineWidth: outlineWidth,
            outlineColor: outlineColor
        )

        let model = ModelUI(from: elements)
        guard !model.isEmpty else { return }

        if let vulkanPipeline = pipeline as? VulkanPipelineImpl {
            vulkanPipeline.renderUI(models: [model])
        } else {
            print("❌ Failed to get Vulkan UI pipeline for batch")
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

    private func getUISDFPipeline() -> Pipeline {
        return pipelineManager.createOrGetUISDFPipeline(device: renderer.logicalDevice)
    }

    public func createUITextureRGBA(width: Int, height: Int, pixels: [UInt8], srgb: Bool = true) -> UInt32? {
        guard let textureIndex = renderer.createUITextureRGBA(width: width, height: height, pixels: pixels, srgb: srgb) else {
            return nil
        }
        return UInt32(textureIndex)
    }

    public func createUITextureR8(width: Int, height: Int, pixels: [UInt8]) -> UInt32? {
        guard let textureIndex = renderer.createUITextureR8(width: width, height: height, pixels: pixels) else {
            return nil
        }
        return UInt32(textureIndex)
    }

    public func setUITextTrueSDFMode(_ enabled: Bool) {
        renderer.setUITextTrueSDFMode(enabled)
    }

    public func setUITextSDFStepDebugMode(_ enabled: Bool) {
        renderer.setUITextSDFStepDebugMode(enabled)
    }

    public func setUITextMSDFMode(_ enabled: Bool) {
        renderer.setUITextMSDFMode(enabled)
    }

    public func setUITextSDFParameters(threshold: Float, range: Float) {
        renderer.setUITextSDFParameters(threshold: threshold, range: range)
    }
    
    /// Helper to load shader source (you'll need to implement this based on how you load shaders)
    private func loadShaderIfNeeded(_ filename: String) -> String? {
        // TODO: Implement shader loading from your Assets/Shaders directory
        // For now, return nil - the pipeline implementation should handle this
        return nil
    }

    public func cleanup() {
        graphicsResourceManager?.cleanup()
    }
}