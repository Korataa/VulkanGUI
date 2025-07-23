import Foundation
import Cvulkan
import Cvma

/// Orchestrates different specialized resource managers
public class ResourceSystem {
    // The specialized resource managers
    public private(set) var graphicsResourceManager: GraphicsResourceManager
    private var managers: [String: Any] = [:]  // Store other specialized managers
    
    // MARK: - Initialization
    public init(vmaAllocator: VmaAllocator) {
        self.graphicsResourceManager = GraphicsResourceManager(vmaAllocator: vmaAllocator)
        try? self.graphicsResourceManager.initialize()
    }
    
    // MARK: - Manager Registration
    public func registerManager<T: ResourceManager>(_ manager: T, forType: T.ManagedResource.Type) {
        managers[String(describing: forType)] = manager
    }
    
    // MARK: - Resource Management
    public func addResource(_ resource: Resource) -> Int {
        // Try to find a specialized manager for this resource type
        let resourceType = type(of: resource)
        let managerKey = String(describing: resourceType)
        
        if let graphicsResource = resource as? GraphicsResource {
            return graphicsResourceManager.addResource(graphicsResource)
        }
        
        if let manager = managers[managerKey] {
            // Use type erasure to handle the generic manager
            if let baseManager = manager as? AnyResourceManager<Resource> {
                return baseManager.addResource(resource)
            }
        }
        
        fatalError("No resource manager registered for type \\(resourceType)")
    }
    
    public func getResource<T: Resource>(_ id: Int) -> T? {
        // If requesting a graphics resource, check graphics manager first
        if T.self is GraphicsResource.Type {
            return graphicsResources.getResource(id) as? T
        }
        
        // Try to find the appropriate manager
        let managerKey = String(describing: T.self)
        if let manager = managers[managerKey] as? AnyResourceManager<T> {
            return manager.getResource(id)
        }
        
        return nil
    }
    
    public func removeResource(_ id: Int, type: Resource.Type) {
        // Try graphics resources first
        if type is GraphicsResource.Type {
            graphicsResources.removeResource(id)
            return
        }
        
        // Try to find the appropriate manager
        let managerKey = String(describing: type)
        if let manager = managers[managerKey] {
            if let baseManager = manager as? AnyResourceManager<Resource> {
                baseManager.removeResource(id)
            }
        }
    }
    
    // MARK: - Cleanup
    public func cleanup() {
        graphicsResources.cleanup()
        // Clean up all registered managers
        for manager in managers.values {
            if let baseManager = manager as? AnyResourceManagerBase {
                baseManager.cleanup()
            }
        }
    }
}

// Type erasure for resource managers to handle generic types
private class AnyResourceManagerBase {
    func cleanup() {
        fatalError("Must override")
    }
}

private class AnyResourceManager<T: Resource>: AnyResourceManagerBase {
    private let _addResource: (T) -> Int
    private let _getResource: (Int) -> T?
    private let _removeResource: (Int) -> Void
    
    init<M: ResourceManager>(_ manager: M) where M.ManagedResource == T {
        _addResource = manager.addResource
        _getResource = manager.getResource
        _removeResource = manager.removeResource
    }
    
    func addResource(_ resource: T) -> Int {
        _addResource(resource)
    }
    
    func getResource(_ id: Int) -> T? {
        _getResource(id)
    }
    
    func removeResource(_ id: Int) {
        _removeResource(id)
    }
    
    override func cleanup() {
        // Cleanup handled by concrete manager
    }
}
