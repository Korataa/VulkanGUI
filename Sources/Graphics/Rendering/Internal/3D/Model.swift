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

    //Cache for the model's bounding box (transformed to world space)
    private var _boundingBox: BoundingBox?
    public var boundingBox: BoundingBox {
        if _boundingBox == nil {
            _boundingBox = calculateBoundingBox(for: meshes, transform: transform)
        }
        return _boundingBox!
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
    
    private func calculateBoundingBox(for meshes: [Mesh], transform: Transform) -> BoundingBox {
        if meshes.isEmpty {
            return BoundingBox() // Empty bounding box
        }
        
        var combinedBox = BoundingBox()
        
        // Combine all mesh bounding boxes
        for mesh in meshes {
            combinedBox.expand(toInclude: mesh.bounds)
        }
        
        // Transform the bounding box to world space
        // For proper transformation, we need to transform all 8 corners of the box
        // and create a new axis-aligned bounding box from the transformed points
        // let modelMatrix = transform.modelMatrix // TODO: Use full matrix transformation later
        
        // Get all 8 corners of the local bounding box
        let corners = [
            Vector3(combinedBox.min.x, combinedBox.min.y, combinedBox.min.z), // min corner
            Vector3(combinedBox.max.x, combinedBox.min.y, combinedBox.min.z),
            Vector3(combinedBox.min.x, combinedBox.max.y, combinedBox.min.z),
            Vector3(combinedBox.min.x, combinedBox.min.y, combinedBox.max.z),
            Vector3(combinedBox.max.x, combinedBox.max.y, combinedBox.min.z),
            Vector3(combinedBox.max.x, combinedBox.min.y, combinedBox.max.z),
            Vector3(combinedBox.min.x, combinedBox.max.y, combinedBox.max.z),
            Vector3(combinedBox.max.x, combinedBox.max.y, combinedBox.max.z)  // max corner
        ]
        
        var transformedBox = BoundingBox()
        
        // Transform each corner and expand the bounding box
        for corner in corners {
            // Transform corner to world space (assuming transform has a method to transform points)
            let worldCorner = Vector3(
                corner.x * transform.scale.x + transform.position.x,
                corner.y * transform.scale.y + transform.position.y,
                corner.z * transform.scale.z + transform.position.z
            )
            // Note: This is a simple implementation - for full matrix transformation you'd use modelMatrix
            transformedBox.expand(toInclude: worldCorner)
        }
        
        return transformedBox
    }

    //if meshes change (for dynamic models), call this to recalculate
    public func invalidateBoundingSphere() {
        _boundingSphere = nil
    }
}