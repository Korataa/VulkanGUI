import Logging
import Platform
import Core
import Math
import Cvulkan
import Cvma

/// Identifies an independently managed group of UI renderables.
public final class UIElementGroup {
    public init() {}
}

struct UIElementList {
    private enum Entry {
        case element(Renderable2D)
        case group(UIElementGroup, [Renderable2D])
    }

    private var entries: [Entry] = []

    var elements: [Renderable2D] {
        var result: [Renderable2D] = []
        for entry in entries {
            switch entry {
            case .element(let element): result.append(element)
            case .group(_, let elements): result.append(contentsOf: elements)
            }
        }
        return result
    }

    var count: Int {
        entries.reduce(0) { count, entry in
            switch entry {
            case .element: return count + 1
            case .group(_, let elements): return count + elements.count
            }
        }
    }

    mutating func add(_ element: Renderable2D) {
        entries.append(.element(element))
    }

    mutating func remove(_ element: Renderable2D) {
        entries = entries.compactMap { entry in
            switch entry {
            case .element(let current):
                return current === element ? nil : entry
            case .group(let group, let elements):
                return .group(group, elements.filter { $0 !== element })
            }
        }
    }

    mutating func clear() {
        entries.removeAll()
    }

    mutating func replace(_ group: UIElementGroup, with elements: [Renderable2D]) {
        if let index = entries.firstIndex(where: {
            if case .group(let current, _) = $0 { return current === group }
            return false
        }) {
            entries[index] = .group(group, elements)
        } else {
            entries.append(.group(group, elements))
        }
    }
}

/// Cross-platform GUI rendering library using Vulkan and SDL3
public class Graphics {
    struct UITextBatchKey: Equatable {
        let textureID: UInt32
        let sdfThreshold: Float
        let sdfRange: Float
        let outlineWidth: Float
        let outlineColor: Color
        let glowColor: Color
        let glowWidth: Float
        let shadowColor: Color
        let shadowOffset: SIMD2<Float>
    }

    enum UIBatchKey: Equatable {
        case solid
        case textured(UInt32)
        case sdf(UITextBatchKey)
    }

    struct UIBatch {
        let key: UIBatchKey
        var elements: [Renderable2D]
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
    
    // Public accessor for the resource manager
    public var resourceManager: VulkanResourceManager {
        return graphicsResourceManager!
    }

    private var uiElements = UIElementList()
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
              let graphicsPool = renderer.commandPool,
              let graphicsQueue = renderer.queueManager?.graphicsQueue else {
            fatalError("Renderer not properly initialized - missing device, allocator, or graphics resources")
        }
        
        self.graphicsResourceManager = VulkanResourceManager(
            device: device,
            vmaAllocator: allocator,
            totalVRAM: renderer.getTotalVRAM(),
            transferCommandPool: graphicsPool,
            transferQueue: graphicsQueue
        )
        renderer.setResourceManager(self.graphicsResourceManager!)
        
        // Initialize the resource manager after it's created and set on the renderer
        do {
            try graphicsResourceManager?.initialize()
        } catch {
            fatalError("Failed to initialize graphics resource manager: \(error)")
        }
    }
    
    /// Add a UI element to be rendered every frame
    public func addUIElement(_ renderable: Renderable2D) {
        uiElements.add(renderable)
    }
    
    /// Remove a UI element from rendering
    public func removeUIElement(_ renderable: Renderable2D) {
        uiElements.remove(renderable)
    }
    
    /// Clear all UI elements
    public func clearUIElements() {
        uiElements.clear()
    }

    /// Replace a managed group without removing unrelated UI elements.
    public func replaceUIElements(in group: UIElementGroup, with elements: [Renderable2D]) {
        uiElements.replace(group, with: elements)
    }
    
    /// Render all UI elements using the clean ModelUI architecture
    public func renderUIElements() {
        precondition(currentImageIndex != nil, "UI rendering requires an active frame")
        precondition(!uiRenderedThisFrame, "UI elements have already been rendered in this frame")
        uiRenderedThisFrame = true
        let uiElements = uiElements.elements
        guard !uiElements.isEmpty else { return }
        
        // Check if any elements are dirty (need GPU upload)
        let dirtyElements = uiElements.filter { $0.isDirty }
        let newElements = uiElements.filter { !$0.isUploaded }
        
        // Only reset buffers AND upload IF we actually have dirty/new elements
        if !dirtyElements.isEmpty || !newElements.isEmpty {
            logDebug(.ui, source: "Graphics", "Found \(dirtyElements.count) dirty + \(newElements.count) new UI elements - uploading")
            guard let resourceManager = graphicsResourceManager else {
                fatalError("Graphics resource manager is not initialized")
            }
            resourceManager.reset2DBuffers()
            let vertexBytes = uiElements.reduce(0) { $0 + $1.vertices.count * MemoryLayout<Vertex2D>.stride }
            let indexBytes = uiElements.reduce(0) { $0 + $1.indices.count * MemoryLayout<UInt32>.stride }
            do {
                try resourceManager.prepare2DBuffers(vertexBytes: vertexBytes, indexBytes: indexBytes)
            } catch {
                fatalError("Failed to prepare UI buffers: \(error)")
            }
            for element in uiElements {
                element.markNotUploaded()
            }
            uploadUIElements(uiElements)
        } else {
            logTrace(.ui, source: "Graphics", "No UI changes detected - skipping upload")
        }
        
        for batch in Self.makeUIBatches(uiElements) {
            renderUIBatch(batch)
        }
    }

    static func makeUIBatches(_ elements: [Renderable2D]) -> [UIBatch] {
        var batches: [UIBatch] = []
        for element in elements {
            let key: UIBatchKey
            if element.usesSDF {
                guard let textureID = element.textureID else {
                    logError(.ui, source: "Graphics", "SDF renderable has no texture")
                    continue
                }
                key = .sdf(UITextBatchKey(
                    textureID: textureID,
                    sdfThreshold: element.sdfThreshold,
                    sdfRange: element.sdfRange,
                    outlineWidth: element.outlineWidth,
                    outlineColor: element.outlineColor,
                    glowColor: element.glowColor,
                    glowWidth: element.glowWidth,
                    shadowColor: element.shadowColor,
                    shadowOffset: element.shadowOffset
                ))
            } else if let textureID = element.textureID {
                key = .textured(textureID)
            } else {
                key = .solid
            }
            if let last = batches.indices.last, batches[last].key == key {
                batches[last].elements.append(element)
            } else {
                batches.append(UIBatch(key: key, elements: [element]))
            }
        }
        return batches
    }

    private func renderUIBatch(_ batch: UIBatch) {
        let model = ModelUI(from: batch.elements)
        guard !model.isEmpty else { return }

        let pipeline: Pipeline
        let materialSet: VkDescriptorSet
        switch batch.key {
        case .solid:
            pipeline = getUIPipeline()
            materialSet = renderer.makeUIMaterialDescriptor(textureMode: 0, textureIndex: nil)
        case .textured(let textureID):
            pipeline = getUIPipeline()
            materialSet = renderer.makeUIMaterialDescriptor(textureMode: 1, textureIndex: Int(textureID))
        case .sdf(let key):
            pipeline = getUISDFPipeline()
            materialSet = renderer.makeUIMaterialDescriptor(
                textureMode: 3, textureIndex: Int(key.textureID),
                sdfThreshold: key.sdfThreshold, sdfRange: key.sdfRange,
                outlineWidth: key.outlineWidth, outlineColor: key.outlineColor,
                glowColor: key.glowColor, glowWidth: key.glowWidth,
                shadowColor: key.shadowColor, shadowOffset: key.shadowOffset
            )
        }
        if let vulkanPipeline = pipeline as? VulkanPipelineImpl {
            vulkanPipeline.renderUI(models: [model], materialSet: materialSet)
        } else {
            print("❌ Failed to get Vulkan UI pipeline for batch")
        }
    }
    
    private func uploadUIElements(_ renderables: [Renderable2D]) {
        guard !renderables.isEmpty else { return }

        do {
            for renderable in renderables {
                if let vertexRegion = try graphicsResourceManager?.allocate2DVertices(vertices: renderable.vertices) {
                    if let indexRegion = try graphicsResourceManager?.allocate2DIndices(indices: renderable.indices) {
                        renderable.markUploaded(
                            vertexOffset: vertexRegion.offset / MemoryLayout<Vertex2D>.stride,
                            indexOffset: indexRegion.offset / MemoryLayout<UInt32>.stride
                        )
                    }
                }
            }
        } catch {
            fatalError("Error uploading UI elements: \(error)")
        }
    }
    
    /// Create a simple 2D sprite/quad
    public func createSprite(at position: (Float, Float), size: (Float, Float), color: Color = Color.white, textureID: UInt32? = nil) -> Renderable2D {
        return Renderable2D(position: SIMD2(position.0, position.1), 
                           size: SIMD2(size.0, size.1), 
                           color: color, 
                           textureID: textureID)
    }

    //MARK: - Frame Management
    
    private var currentImageIndex: UInt32?
    private var uiRenderedThisFrame = false
    
    /// Phase 1: Create frame and begin render pass
    public func createFrame() -> Bool {
        guard let imageIndex = renderer.createFrame() else {
            currentImageIndex = nil
            return false
        }
        currentImageIndex = imageIndex
        uiRenderedThisFrame = false
        return true
    }
    
    /// Phase 2: Render all UI and present the frame
    public func presentFrame() {
        presentFrameWithResult()
    }

    /// Present the frame and report whether it was successfully presented.
    @discardableResult
    public func presentFrameWithResult() -> Bool {
        guard let imageIndex = currentImageIndex else {
            print("ERROR: presentFrame() called without successful createFrame()")
            return false
        }
        
        if !uiRenderedThisFrame {
            renderUIElements()
        }
        let presented = renderer.renderFrame(imageIndex: imageIndex)
        currentImageIndex = nil
        return presented
    }
    
    /// Legacy method - use createFrame() + presentFrame() instead
    public func update() {
        if createFrame() {
            presentFrame()
        }
    }

    public func createTexturesFromResourceManager() {
        renderer.createTexturesFromResourceManager()
    }

    /// Get the current aspect ratio from the renderer
    public func getAspectRatio() -> Float {
        return renderer.getAspectRatio()
    }
    
    // MARK: - Pipeline Helper Methods
    
    /// Create or get a UI pipeline
    private func getUIPipeline() -> Pipeline {
        let descriptor = PipelineDescriptor(
            type: .UI,
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
    
    public func cleanup() {
        if let device = renderer.logicalDevice {
            vkDeviceWaitIdle(device)
        }
        pipelineManager?.cleanupAllPipelines()
        pipelineManager = nil
        graphicsResourceManager?.cleanup()
        graphicsResourceManager = nil
        renderer.cleanup()
    }
}