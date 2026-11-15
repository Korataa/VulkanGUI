import Platform
import Core
import Math
import Foundation

/// ModelUI - UI models in screen space.
/// Uses Vertex2D and 2D buffers but with screen-space coordinates
public final class ModelUI {
    public var meshes: [Mesh2D] = []
    public var materials: [Material] = [] // Simple material system for UI
    
    /// Create ModelUI from Renderable2D elements
    public init(from renderables: [Renderable2D]) {
        // Convert Renderable2D to Mesh2D objects
        self.meshes = renderables.compactMap { renderable in
            guard renderable.isUploaded else { return nil }
            return Mesh2D(from: renderable)
        }
        
        // UI typically uses simple materials
        self.materials = []
    }
    
    /// Create ModelUI from a single Renderable2D
    public convenience init(from renderable: Renderable2D) {
        self.init(from: [renderable])
    }
    
    /// Check if this ModelUI has any meshes to render
    public var isEmpty: Bool {
        return meshes.isEmpty
    }
}