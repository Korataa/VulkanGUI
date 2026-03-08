import Platform
import Core
import Math
import Foundation

/// ModelUI - UI models in screen space (mirrors Model3D architecture)
/// Uses Vertex2D and 2D buffers but with screen-space coordinates
public final class ModelUI {
    public var meshes: [MeshUI] = []
    public var materials: [Material] = [] // Simple material system for UI
    public var transform: Transform       // Screen-space transform (usually identity)
    
    /// Create ModelUI from UIRenderable elements
    public init(from renderables: [UIRenderable]) {
        // Convert UIRenderables to MeshUI objects
        self.meshes = renderables.compactMap { renderable in
            guard renderable.isUploaded else { return nil }
            return MeshUI(from: renderable)
        }
        
        // UI uses identity transform (already positioned in screen space)
        self.transform = Transform(
            position: Vector3(0, 0, 0),
            rotation: Quaternion.identity(),
            scale: Vector3(1, 1, 1)
        )
        
        // UI typically uses simple materials
        self.materials = []
    }
    
    /// Create ModelUI from a single UIRenderable
    public convenience init(from renderable: UIRenderable) {
        self.init(from: [renderable])
    }
    
    /// Check if this ModelUI has any meshes to render
    public var isEmpty: Bool {
        return meshes.isEmpty
    }
}