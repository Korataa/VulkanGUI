import Foundation

/// Base protocol for specialized resource managers
public protocol ResourceManager {
    associatedtype ResourceType: Resource

    /// Returns true if this manager can handle the given resource type
    func canHandle(_ resourceType: ResourceType) -> Bool

    /// Add a resource to this manager
    /// Returns the ID of the added resource
    func addResource(_ resource: consuming ResourceType) -> Int

    /// Get a resource by its ID
    func getResource(_ id: Int) -> ResourceType?

    /// Remove a resource by its ID
    func removeResource(_ id: Int)

    /// Initialize the manager
    func initialize() throws

    /// Clean up all resources
    func cleanup()
}
