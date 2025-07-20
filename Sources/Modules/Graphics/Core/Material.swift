import Foundation

public enum MaterialType: Hashable {
    case PBR
    case Unlit
    case Translucent
    case Masked
    case Emissive
    case Custom(String) // Custom shader name
    
    public static func == (lhs: MaterialType, rhs: MaterialType) -> Bool {
        switch (lhs, rhs) {
        case (.PBR, .PBR),
             (.Unlit, .Unlit),
             (.Translucent, .Translucent),
             (.Masked, .Masked),
             (.Emissive, .Emissive):
            return true
        case (.Custom(let l), .Custom(let r)):
            return l == r
        default:
            return false
        }
    }
}
public final class Material: Hashable {
    public var name: String?
    
    // Material type and shader info
    var type: MaterialType = .PBR
    var shaderId: String? = nil  // Optional custom shader override
    
    //Base color
    var baseColor: Color = .white
    var baseColorTextureIndex: Int? = nil

    // Metallic and roughness
    var metallicFactor: Float = 1.0
    var roughnessFactor: Float = 1.0
    var metallicRoughnessTextureIndex: Int? = nil
    
    // Custom parameters (for shader-specific values)
    var customParameters: [String: Any] = [:]

    // Normal mapping
    var normalTextureIndex: Int? = nil
    var normalScale: Float = 1.0

    //Occlusion
    var occlusionTextureIndex: Int? = nil
    var occlusionStrength: Float = 1.0

    // Emissive
    var emissiveColor: Color = .black
    var emissiveTextureIndex: Int? = nil

    // Alpha mode
    var alphaCutoff: Float = 0.5
    var isOpaque: Bool = true 

    public static func == (lhs: Material, rhs: Material) -> Bool {
        // Compare material type and basic properties
        guard lhs.type == rhs.type,
              lhs.shaderId == rhs.shaderId,
              lhs.baseColor == rhs.baseColor,
              lhs.baseColorTextureIndex == rhs.baseColorTextureIndex,
              lhs.metallicFactor == rhs.metallicFactor,
              lhs.roughnessFactor == rhs.roughnessFactor,
              lhs.metallicRoughnessTextureIndex == rhs.metallicRoughnessTextureIndex,
              lhs.normalTextureIndex == rhs.normalTextureIndex,
              lhs.normalScale == rhs.normalScale,
              lhs.occlusionTextureIndex == rhs.occlusionTextureIndex,
              lhs.occlusionStrength == rhs.occlusionStrength,
              lhs.emissiveColor == rhs.emissiveColor,
              lhs.emissiveTextureIndex == rhs.emissiveTextureIndex,
              lhs.alphaCutoff == rhs.alphaCutoff,
              lhs.isOpaque == rhs.isOpaque else { return false }
        
        // Compare custom parameters
        // Only compare hashable values, ignore non-hashable ones for equality
        let lhsHashable = lhs.customParameters.compactMapValues { $0 as? AnyHashable }
        let rhsHashable = rhs.customParameters.compactMapValues { $0 as? AnyHashable }
        
        return lhsHashable == rhsHashable
    }

    public func hash(into hasher: inout Hasher) {
        // Hash material type
        switch type {
        case .Custom(let name): 
            hasher.combine("custom")
            hasher.combine(name)
        default:
            hasher.combine(String(describing: type))
        }
        
        // Hash basic properties
        hasher.combine(shaderId)
        hasher.combine(baseColor)
        hasher.combine(baseColorTextureIndex)
        hasher.combine(metallicFactor)
        hasher.combine(roughnessFactor)
        hasher.combine(metallicRoughnessTextureIndex)
        hasher.combine(normalTextureIndex)
        hasher.combine(normalScale)
        hasher.combine(occlusionTextureIndex)
        hasher.combine(occlusionStrength)
        hasher.combine(emissiveColor)
        hasher.combine(emissiveTextureIndex)
        hasher.combine(alphaCutoff)
        hasher.combine(isOpaque)
        
        // Hash custom parameters (only hashable values)
        for (key, value) in customParameters.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)
            if let hashableValue = value as? AnyHashable {
                hasher.combine(hashableValue)
            }
        }
    }
    
    // MARK: - Material Presets
    
    /// Creates a metal material with the specified color and roughness
    public static func createMetal(color: Color = .white, roughness: Float = 0.4) -> Material {
        var material = Material()
        material.type = .PBR
        material.baseColor = color
        material.metallicFactor = 1.0
        material.roughnessFactor = roughness
        return material
    }
    
    /// Creates a plastic material with the specified color and roughness
    public static func createPlastic(color: Color = .white, roughness: Float = 0.5) -> Material {
        var material = Material()
        material.type = .PBR
        material.baseColor = color
        material.metallicFactor = 0.0
        material.roughnessFactor = roughness
        return material
    }
    
    /// Creates an emissive material that glows with the specified color and intensity
    public static func createEmissive(color: Color, intensity: Float = 1.0) -> Material {
        var material = Material()
        material.type = .Emissive
        material.emissiveColor = color
        material.customParameters["emissiveIntensity"] = intensity
        return material
    }
    
    /// Creates a translucent material with the specified color and opacity
    public static func createTranslucent(color: Color = .white, opacity: Float = 0.5) -> Material {
        var material = Material()
        material.type = .Translucent
        material.baseColor = color
        material.isOpaque = false
        material.alphaCutoff = opacity
        return material
    }
    
    /// Creates a basic unlit material with the specified color
    public static func createUnlit(color: Color) -> Material {
        var material = Material()
        material.type = .Unlit
        material.baseColor = color
        return material
    }
    
    // MARK: - Material Modifications
    
    /// Creates a new material instance with modified roughness
    public func withRoughness(_ roughness: Float) -> Material {
        var mat = self
        mat.roughnessFactor = roughness
        return mat
    }
    
    /// Creates a new material instance with modified metallic factor
    public func withMetallic(_ metallic: Float) -> Material {
        var mat = self
        mat.metallicFactor = metallic
        return mat
    }
    
    /// Creates a new material instance with modified base color
    public func withColor(_ color: Color) -> Material {
        var mat = self
        mat.baseColor = color
        return mat
    }
    
    /// Creates a new material instance with a normal map
    public func withNormalMap(textureIndex: Int, scale: Float = 1.0) -> Material {
        var mat = self
        mat.normalTextureIndex = textureIndex
        mat.normalScale = scale
        return mat
    }
    
    /// Creates a new material instance with an occlusion map
    public func withOcclusionMap(textureIndex: Int, strength: Float = 1.0) -> Material {
        var mat = self
        mat.occlusionTextureIndex = textureIndex
        mat.occlusionStrength = strength
        return mat
    }
}