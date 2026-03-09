import Platform
import Core
import Cvulkan

class PipelineManager {
    var activeBackend: GraphicsBackend
    var pipelines: [PipelineDescriptor: Pipeline] = [:]
    private var renderer: Any? // Store renderer reference
    
    init(backend: GraphicsBackend, renderer: Any? = nil) {
        self.activeBackend = backend
        self.renderer = renderer
    }

    func createOrGetPipeline(desc: PipelineDescriptor, device: Any? = nil) -> Pipeline {
        if let p = pipelines[desc] { return p }
        let newPipeline = PipelineFactory.createPipeline(
            descriptor: desc,
            backend: activeBackend,
            device: device,
            renderer: renderer
        )

        pipelines[desc] = newPipeline
        return newPipeline
    }

    /// Convenience helper for the unified UI SDF pipeline variant.
    func createOrGetUISDFPipeline(device: Any? = nil) -> Pipeline {
        let descriptor = PipelineDescriptor(
            type: .UITextSDF,
            blendMode: .Alpha,
            depthTest: false,
            cullMode: .None
        )
        return createOrGetPipeline(desc: descriptor, device: device)
    }

    func switchBackend(_ newBackend: GraphicsBackend) {
        // Clean up existing pipelines
        cleanupAllPipelines()

        //update backend
        activeBackend = newBackend
    }

    func cleanupAllPipelines() {
        for (_, pipeline) in pipelines {
            pipeline.cleanup()
        }
        pipelines.removeAll()
    }

    deinit {
        cleanupAllPipelines()
    }
}