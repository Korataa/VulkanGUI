import Foundation
import Cvulkan
import Cvma

/// Orchestrates different specialized resource managers
public class ResourceSystem {
    // The specialized resource managers
    public private(set) var graphicsResourceManager: GraphicsResourceManager
    private var managers: [String: Any] = [:]  // Store other specialized managers
    
    // MARK: - Initialization
    public init(device: VkDevice, vmaAllocator: VmaAllocator, totalVRAM: UInt64) {
        self.graphicsResourceManager = GraphicsResourceManager(
            device: device,
            vmaAllocator: vmaAllocator, 
            totalVRAM: totalVRAM
        )
        try? self.graphicsResourceManager.initialize()
    }
    
    // MARK: - Manager Registration
    public func registerManager(_ manager: ResourceManager, forType: Resource.Type) {
        managers[String(describing: forType)] = manager
    }
    
    // MARK: - Resource Management
    public func addResource(_ resource: consuming Resource) -> Int {
        // Check which manager can handle this resource type
        let resourceType = resource.resourceType
        
        // Try graphics manager first
        if graphicsResourceManager.canHandle(resourceType) {
            return graphicsResourceManager.addResource(resource)
        }
        
        // Try other registered managers
        for manager in managers.values {
            if let resourceManager = manager as? ResourceManager,
               resourceManager.canHandle(resourceType) {
                return resourceManager.addResource(resource)
            }
        }
        
        fatalError("No resource manager registered for type \\(resourceType)")
    }
    
    public func getResource<T: Resource>(_ id: Int) -> T? {
        // Try graphics manager first
        if let resource = graphicsResourceManager.getResource(id) as? T {
            return resource
        }
        
        // Try other registered managers
        for manager in managers.values {
            if let resourceManager = manager as? ResourceManager,
               let resource = resourceManager.getResource(id) as? T {
                return resource
            }
        }
        
        return nil
    }
    
    public func removeResource(_ id: Int, resourceType: ResourceType) {
        // Try graphics manager first
        if graphicsResourceManager.canHandle(resourceType) {
            graphicsResourceManager.removeResource(id)
            return
        }
        
        // Try other registered managers
        for manager in managers.values {
            if let resourceManager = manager as? ResourceManager,
               resourceManager.canHandle(resourceType) {
                resourceManager.removeResource(id)
                return
            }
        }
    }
    
    // MARK: - Cleanup
    public func cleanup() {
        graphicsResourceManager.cleanup()
        // Clean up all registered managers
        for manager in managers.values {
            if let resourceManager = manager as? ResourceManager {
                resourceManager.cleanup()
            }
        }
    }
}
