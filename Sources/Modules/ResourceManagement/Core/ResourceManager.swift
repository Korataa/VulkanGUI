import Foundation

/// Base protocol for specialized resource managers
public protocol ResourceManager {
    /// The type of resource this manager handles
    associatedtype ManagedResource: Resource
    
    /// Add a resource to this manager
    /// Returns the ID of the added resource
    func addResource(_ resource: ManagedResource) -> Int
    
    /// Get a resource by its ID
    func getResource(_ id: Int) -> ManagedResource?
    
    /// Remove a resource by its ID
    func removeResource(_ id: Int)
    
    /// Initialize the manager
    func initialize() throws
    
    /// Clean up all resources
    func cleanup()
}
