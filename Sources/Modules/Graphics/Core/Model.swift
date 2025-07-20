public class Model {
    public var meshes: [Mesh] = []
    public var materialID: UInt32
    public var transform: Transform

    //Cache for the model's bounding sphere
    private var boundingSphere: (center: Vector3, radius: Float)

    public var isDynamic: Bool {
        return meshes.contains { mesh in
            if let _ = mesh as? DynamicMesh {
                return true
            }
            return false
        }
    }

    init(meshes: [Mesh], transform: Transform, materialID: UInt32) {
        self.meshes = meshes
        self.transform = transform
        self.materialID = materialID

        //Calculate bounding sphere
        self.boundingSphere = calculateBoundingSphere()
    }

    init(mesh: Mesh, transform: Transform, materialID: UInt32) {
        self.meshes = [mesh]
        self.transform = transform
        self.materialID = materialID

        //Calculate bounding sphere
        self.boundingSphere = calculateBoundingSphere()
    }
    
    func isVisible(in frustum: Frustum) -> Bool {
        // Quick AABB check against frustum planes
        let boundingSphere = self.getBoundingSphere()
        for plane in frustum.planes {
            if plane.dot(Vector4(boundingSphere.center.x, boundingSphere.center.y, boundingSphere.center.z, 1.0)) < -boundingSphere.radius {
                return false // Object is completely outside this plane
            }
        }
        return true
    }
    
    //This method should only be called once, during initialization
    private func getBoundingSphere() -> (center: Vector3, radius: Float) {
        if meshes.isEmpty {
            return (Vector3(0, 0, 0), 1.0) // No meshes, no bounding sphere
        }

        //For dynamic meshes, we can recalculate when the vertices change
        var minBounds = Vector3(Float.infinity, Float.infinity, Float.infinity)
        var maxBounds = Vector3(-Float.infinity, -Float.infinity, -Float.infinity)

        //Calculate AABB (axis-Aligned Bounding Box) from all meshes
        for mesh in meshes {
            minBounds = Vector3(
                min(minBounds.x, mesh.)
            )
        }

        
    }
}