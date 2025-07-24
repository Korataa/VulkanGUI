import Cvulkan
import Cvma

public class Graphics {
    // Struct to bundle info for ResourceSystem
    public struct ResourceSystemInfo {
        public let device: VkDevice
        public let vmaAllocator: VmaAllocator
        public let totalVRAM: UInt64
        public let graphicsResourceManager: GraphicsResourceManager
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
    private var renderer: VulkanRenderer
    private var sdlContext: SDLContext

    var graphicsResourceManager: GraphicsResourceManager?
    
    // Public accessor for the resource manager
    public var resourceManager: GraphicsResourceManager {
        return graphicsResourceManager!
    }

    var pipelines: [any GraphicsPipeline] = []
    var renderModels: [Model] = []        //Models to render

    public init(sdlContext: SDLContext) {
        self.sdlContext = sdlContext
        renderer = VulkanRenderer(context: sdlContext)
        renderer.initialize()
    }

    public init(sdlContext: SDLContext, graphicsResourceManager: GraphicsResourceManager) {
        self.sdlContext = sdlContext
        renderer = VulkanRenderer(context: sdlContext)
        renderer.initialize()
        self.graphicsResourceManager = graphicsResourceManager
        renderer.setResourceManager(graphicsResourceManager)
    }

    public func initialize() {
        renderer.initialize()
    }

    func addPipeline(_ pipeline: any GraphicsPipeline) {
        pipelines.append(pipeline)
    }

    func render(commandBuffer: Any) {
        for pipeline in pipelines {
            pipeline.bind(commandBuffer: commandBuffer)
            // Drawing commands would go here
        }
    }

    //Rendering stuff gets updated in here!!
    public func update() {
        // Begin frame and get swapchain image index
        guard let imageIndex = renderer.beginFrame() else {
            // Frame was skipped (swapchain recreation, etc.)
            return
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

    ///Everytime model is added to scene this must be called (or the alternative version of this method)
    public func addModel(mesh: Mesh, transform: Transform) {
        renderModels.append(Model(
            meshes: [mesh], transform: transform
        ))
    }

    public func cleanup() {


    }
}