import Platform
import Core
import Math

import Foundation

//Lightweight - references shared mesh (sometimes) + unique transform
public class Model {
    public var meshes: [Mesh] = []
    public var materials: [Material] = []  // Materials indexed by materialID
    public var transform: Transform

    //Cache for the model's bounding sphere
    private var _boundingSphere: (center: Vector3, radius: Float)?
    public var boundingSphere: (center: Vector3, radius: Float) {
        if _boundingSphere == nil {
            _boundingSphere = calculateBoundingSphere(for: meshes)
        }
        return _boundingSphere!
    }

    public var isDynamic: Bool {
        return meshes.contains { mesh in
            if let _ = mesh as? DynamicMesh {
                return true
            }
            return false
        }
    }

    public init(meshes: [Mesh], materials: [Material] = [], transform: Transform) {
        self.meshes = meshes
        self.materials = materials
        self.transform = transform
    }

    init(mesh: Mesh, material: Material? = nil, transform: Transform) {
        self.meshes = [mesh]
        self.materials = material != nil ? [material!] : []
        self.transform = transform
    }
    
    func isVisible(in frustum: Frustum) -> Bool {
        // Quick AABB check against frustum planes
        let boundingSphere = self.boundingSphere
        for plane in frustum.planes {
            if plane.dot(Vector4(boundingSphere.center.x, boundingSphere.center.y, boundingSphere.center.z, 1.0)) < -boundingSphere.radius {
                return false // Object is completely outside this plane
            }
        }
        return true
    }
    
    //This method should only be called once, during initialization
    private func calculateBoundingSphere(for meshes: [Mesh]) -> (center: Vector3, radius: Float) {
        if meshes.isEmpty {
            return (Vector3(0, 0, 0), 1.0) // No meshes, no bounding sphere
        }

        //For dynamic meshes, we can recalculate when the vertices change
        var minBounds = Vector3(Float.infinity, Float.infinity, Float.infinity)
        var maxBounds = Vector3(-Float.infinity, -Float.infinity, -Float.infinity)

        //Calculate AABB (axis-Aligned Bounding Box) from all meshes
        for mesh in meshes {
            let meshMin = mesh.bounds.min
            let meshMax = mesh.bounds.max
            
            minBounds = Vector3(
                min(minBounds.x, meshMin.x),
                min(minBounds.y, meshMin.y),
                min(minBounds.z, meshMin.z)
            )
            
            maxBounds = Vector3(
                max(maxBounds.x, meshMax.x),
                max(maxBounds.y, meshMax.y),
                max(maxBounds.z, meshMax.z)
            )
        }

        // Calculate center of the bounding box
        let center = Vector3(
            (minBounds.x + maxBounds.x) * 0.5,
            (minBounds.y + maxBounds.y) * 0.5,
            (minBounds.z + maxBounds.z) * 0.5
        )

        // Calculate radius as distance from center to farthest corner using 3D distance formula
        // Distance formula: √((x₂-x₁)² + (y₂-y₁)² + (z₂-z₁)²)
        let extent = Vector3(
            maxBounds.x - center.x,  // (x₂-x₁) - difference in X
            maxBounds.y - center.y,  // (y₂-y₁) - difference in Y
            maxBounds.z - center.z   // (z₂-z₁) - difference in Z
        )
        // √(x² + y² + z²) - square root of sum of squared differences
        let radius = sqrt(extent.x * extent.x + extent.y * extent.y + extent.z * extent.z)
        //                     x²              +        y²              +        z²

        return (center, radius)
    }

    //if meshes change (for dynamic models), call this to recalculate
    public func invalidateBoundingSphere() {
        _boundingSphere = nil
    }
}