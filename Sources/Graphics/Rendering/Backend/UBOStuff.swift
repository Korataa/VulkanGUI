import Platform
import Core
import Math

struct Transform2DConstants {
    var projection: Matrix4x4
    var model: Matrix4x4
}

struct MaterialConstants2D {
    var color: SIMD4<Float>
    var opacity: Float
    var hasTexture: Int32
    var padding: SIMD4<Int32> = .zero
}

// UI Projection UBO - matches UI shader layout
struct UIProjectionConstants {
    var projection: Matrix4x4   // Orthographic projection matrix (screen pixels to NDC)
    var screenSize: Vector2     // Screen resolution for pixel-perfect positioning  
    var padding: Vector2        // Alignment to 16 bytes
}

// UI Material UBO - matches UI fragment shader layout
struct UIMaterialConstants {
    var tint: SIMD4<Float>     // Color tint/multiplier (vec4 in shader)
    var opacity: Float         // Global opacity
    var textureMode: Int32     // 0=solid, 1=texture, 2=texture+color blend, 3=SDF
    var roundedCorners: Int32  // Enable rounded corner rendering
    var cornerRadius: Float    // Corner radius in pixels
    var sdfThreshold: Float    // SDF cutoff threshold (default 0.5)
    var outlineWidth: Float    // Outline thickness (default 0.0)
    var pad0: Float            // std140 alignment before outlineColor
    var outlineColor: SIMD4<Float>
    var sdfRange: Float        // Distance field range (default 4.0)
    var reserved1: Float       // Reserved for future use
    var reserved2: Float       // Reserved for future use
    var pad1: Float            // Struct size alignment padding
    // Additional UI material params (match GLSL UIMaterial layout)
    var glowColor: SIMD4<Float>
    var glowWidth: Float       // glow width
    var pad2: Float            // padding
    var shadowColor: SIMD4<Float>
    var shadowOffset: SIMD2<Float>
    var pad3: Float            // padding to align to 16 bytes
    var pad4: Float            // extra padding
}