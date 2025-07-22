import Foundation

public struct BoundingBox {
    public var min: Vector3
    public var max: Vector3
    
    public init(min: Vector3, max: Vector3) {
        self.min = min
        self.max = max
    }
    
    public init() {
        self.min = Vector3(Float.infinity, Float.infinity, Float.infinity)
        self.max = Vector3(-Float.infinity, -Float.infinity, -Float.infinity)
    }
    
    /// Creates a bounding box from a center point and extents
    public init(center: Vector3, extents: Vector3) {
        self.min = Vector3(center.x - extents.x, center.y - extents.y, center.z - extents.z)
        self.max = Vector3(center.x + extents.x, center.y + extents.y, center.z + extents.z)
    }
    
    /// Expands the bounding box to include a point
    public mutating func expand(toInclude point: Vector3) {
        min.x = Swift.min(min.x, point.x)
        min.y = Swift.min(min.y, point.y)
        min.z = Swift.min(min.z, point.z)
        
        max.x = Swift.max(max.x, point.x)
        max.y = Swift.max(max.y, point.y)
        max.z = Swift.max(max.z, point.z)
    }
    
    /// Expands the bounding box to include another bounding box
    public mutating func expand(toInclude other: BoundingBox) {
        expand(toInclude: other.min)
        expand(toInclude: other.max)
    }
    
    /// Returns the center point of the bounding box
    public var center: Vector3 {
        return Vector3(
            (min.x + max.x) * 0.5,
            (min.y + max.y) * 0.5,
            (min.z + max.z) * 0.5
        )
    }
    
    /// Returns the size (extents) of the bounding box
    public var size: Vector3 {
        return Vector3(
            max.x - min.x,
            max.y - min.y,
            max.z - min.z
        )
    }
    
    /// Returns the half-extents of the bounding box
    public var extents: Vector3 {
        let s = size
        return Vector3(s.x * 0.5, s.y * 0.5, s.z * 0.5)
    }
    
    /// Checks if the bounding box contains a point
    public func contains(_ point: Vector3) -> Bool {
        return point.x >= min.x && point.x <= max.x &&
               point.y >= min.y && point.y <= max.y &&
               point.z >= min.z && point.z <= max.z
    }
    
    /// Checks if this bounding box intersects with another
    public func intersects(_ other: BoundingBox) -> Bool {
        return !(max.x < other.min.x || min.x > other.max.x ||
                 max.y < other.min.y || min.y > other.max.y ||
                 max.z < other.min.z || min.z > other.max.z)
    }
    
    /// Returns true if the bounding box is valid (min <= max)
    public var isValid: Bool {
        return min.x <= max.x && min.y <= max.y && min.z <= max.z
    }
    
    /// Returns true if the bounding box is empty (min == max)
    public var isEmpty: Bool {
        return min.x == max.x && min.y == max.y && min.z == max.z
    }
}
