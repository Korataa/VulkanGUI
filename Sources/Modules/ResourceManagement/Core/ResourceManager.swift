import Foundation

/// Base protocol for specialized resource managers
public protocol ResourceManager {
    /// Returns true if this manager can handle the given resource type  
    func canHandle(_ typeCategory: ResourceCategory) -> Bool

    /// Add a resource to this manager - takes any Resource type
    /// Returns the ID of the added resource
    func addResource(_ resource: consuming any Resource) -> Int

    /// Get a resource by its ID - returns any Resource type
    func getResource(_ id: Int) -> (any Resource)?

    /// Remove a resource by its ID
    func removeResource(_ id: Int)

    /// Initialize the manager
    func initialize() throws

    /// Clean up all resources
    func cleanup()
}
