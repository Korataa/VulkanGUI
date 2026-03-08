import Foundation

/// Configuration for rendering features and optimizations
public struct RenderSettings {
    /// Enable/disable frustum culling
    public var frustumCulling: Bool = true
    
    /// Enable/disable occlusion culling (future feature)
    public var occlusionCulling: Bool = false
    
    /// Show debug visualization for culling
    public var debugCulling: Bool = false
    
    /// Distance culling threshold (optional)
    public var maxDrawDistance: Float? = nil
    
    /// Level of detail (LOD) settings
    public var lodEnabled: Bool = false
    public var lodDistanceMultiplier: Float = 1.0
    
    public init() {}
    
    /// Preset for high performance (aggressive culling)
    public static var performance: RenderSettings {
        var settings = RenderSettings()
        settings.frustumCulling = true
        settings.maxDrawDistance = 1000.0
        settings.lodEnabled = true
        return settings
    }
    
    /// Preset for high quality (minimal culling)
    public static var quality: RenderSettings {
        var settings = RenderSettings()
        settings.frustumCulling = false  // Disable for max quality
        settings.maxDrawDistance = nil   // No distance limit
        settings.lodEnabled = false
        return settings
    }
    
    /// Preset for debugging (visualize culling)
    public static var debug: RenderSettings {
        var settings = RenderSettings()
        settings.frustumCulling = true
        settings.debugCulling = true
        return settings
    }
}