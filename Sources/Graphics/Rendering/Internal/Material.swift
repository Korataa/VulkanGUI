import Core

public struct UIMaterialUniforms {
    public var tint: Color
    public var opacity: Float
    public var textureMode: Int32
    public var roundedCorners: Int32
    public var cornerRadius: Float
    public var sdfThreshold: Float
    public var outlineWidth: Float
    public var pad0: Float
    public var outlineColor: Color
    public var sdfRange: Float
    public var reserved1: Float
    public var reserved2: Float
    public var pad1: Float

    public init(
        tint: Color = .white,
        opacity: Float = 1.0,
        textureMode: Int32 = 0,
        roundedCorners: Int32 = 0,
        cornerRadius: Float = 0.0,
        sdfThreshold: Float = 0.5,
        outlineWidth: Float = 0.0,
        outlineColor: Color = .black,
        sdfRange: Float = 4.0,
        reserved1: Float = 0.0,
        reserved2: Float = 0.0,
        pad0: Float = 0.0,
        pad1: Float = 0.0
    ) {
        self.tint = tint
        self.opacity = opacity
        self.textureMode = textureMode
        self.roundedCorners = roundedCorners
        self.cornerRadius = cornerRadius
        self.sdfThreshold = sdfThreshold
        self.outlineWidth = outlineWidth
        self.pad0 = pad0
        self.outlineColor = outlineColor
        self.sdfRange = sdfRange
        self.reserved1 = reserved1
        self.reserved2 = reserved2
        self.pad1 = pad1
    }
}

public enum MaterialType: Hashable {
    case Unlit
    case Translucent
    case Masked
    case Custom(String)
}

public final class Material: Hashable {
    public var name: String?
    public var type: MaterialType = .Unlit
    public var shaderId: String?
    public var baseColor: Color = .white
    public var baseColorTextureIndex: Int?
    public var isOpaque: Bool = true
    public var alphaCutoff: Float = 0.5
    public var customParameters: [String: Any] = [:]

    public init() {}

    public static func == (lhs: Material, rhs: Material) -> Bool {
        lhs.type == rhs.type && lhs.shaderId == rhs.shaderId &&
        lhs.baseColor == rhs.baseColor && lhs.baseColorTextureIndex == rhs.baseColorTextureIndex &&
        lhs.isOpaque == rhs.isOpaque && lhs.alphaCutoff == rhs.alphaCutoff &&
        lhs.customParameters.compactMapValues { $0 as? AnyHashable } ==
            rhs.customParameters.compactMapValues { $0 as? AnyHashable }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(shaderId)
        hasher.combine(baseColor)
        hasher.combine(baseColorTextureIndex)
        hasher.combine(isOpaque)
        hasher.combine(alphaCutoff)
        for (key, value) in customParameters.sorted(by: { $0.key < $1.key }) {
            if let value = value as? AnyHashable {
                hasher.combine(key)
                hasher.combine(value)
            }
        }
    }

    public static func createUnlit(color: Color) -> Material {
        let material = Material()
        material.baseColor = color
        return material
    }

    public static func createTranslucent(color: Color = .white, opacity: Float = 0.5) -> Material {
        let material = Material()
        material.type = .Translucent
        material.baseColor = color
        material.isOpaque = false
        material.alphaCutoff = opacity
        return material
    }

    public func withColor(_ color: Color) -> Material {
        baseColor = color
        return self
    }
}
