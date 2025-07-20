public class Graphics {
    private var renderer: VulkanRenderer
    private var sdlContext: SDLContext

    var graphicsResourceManager: GraphicsResourceManager

    var pipelines: [GraphicsPipeline] = []
    var renderModels: [Model] = []        //Models to render

    public init(sdlContext: SDLContext) {
        self.sdlContext = sdlContext
        renderer = VulkanRenderer(context: sdlContext)

        //initialize vulkan first to get handles
        renderer.initialize()

        //probably here we will initialize the 3 big buffers
        self.graphicsResourceManager = GraphicsResourceManager(
            device: renderer.logicalDevice!,
            vmaAllocator: renderer.vmaAllocator!,
            totalVRAM: renderer.getTotalVRAM()
        )

        //give renderer access to ResourceManager
        renderer.setResourceManager(graphicsResourceManager)
    }

    public func initialize() {
        renderer.initialize()
    }

    func addPipeline(_ pipeline: GraphicsPipeline) {
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
        renderer.renderFrame(models: renderModels)
    }

    ///Everytime model is added to scene this must be called (or the alternative version of this method)
    public func addModel(model: Model) {
        renderModels.append(model)
    }

    ///Everytime model is added to scene this must be called (or the alternative version of this method)
    public func addModel(mesh: Mesh, transform: Transform, materialID: UInt32) {
        renderModels.append(Model(
            mesh: mesh, transform: transform, materialID: materialID
        ))
    }

    public func cleanup() {


    }
}