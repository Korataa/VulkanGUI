/// Base protocol for all resources in the system
public protocol Resource: ~Copyable {
    /// Optional name for the resource (useful for debugging and asset management)
    var name: String? { get set }
    
    /// Unique identifier assigned by a resource manager
    var id: Int? { get set }
    
    /// Clean up any resources held by this resource
    func cleanup()
}