import Platform
import Core
/// Simplified storage for texture IDs and metadata
/// Avoids move-only collection issues by using IDs instead of storing textures directly
public struct TextureStorage {
    private var textureIds: [Int] = []
    private var textureMetadata: [(width: Int, height: Int, channels: Int)] = []
    
    public init() {}
    
    /// Add a texture ID and its metadata
    public mutating func addTextureId(_ id: Int, width: Int, height: Int, channels: Int) {
        textureIds.append(id)
        textureMetadata.append((width: width, height: height, channels: channels))
    }
    
    /// Get texture ID by index
    public func getTextureId(_ index: Int) -> Int? {
        guard index >= 0 && index < textureIds.count else { return nil }
        return textureIds[index]
    }
    
    /// Get texture metadata by index
    public func getMetadata(_ index: Int) -> (width: Int, height: Int, channels: Int)? {
        guard index >= 0 && index < textureMetadata.count else { return nil }
        return textureMetadata[index]
    }
    
    /// Get the number of stored texture IDs
    public var count: Int {
        textureIds.count
    }
    
    /// Check if storage is empty
    public var isEmpty: Bool {
        textureIds.isEmpty
    }
}
