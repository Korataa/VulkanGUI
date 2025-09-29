struct FrameConstants {
    var viewMatrix: Matrix4x4      // mat4 view
    var projectionMatrix: Matrix4x4 // mat4 proj
    var lightPosition: Vector3      // vec3 lightPos
    var lightColor: Vector3         // vec3 lightColor  
    var cameraPosition: Vector3     // vec3 viewPos (camera position)
}

let MAX_OBJECTS = 1024
let MAX_MATERIALS = 256

// Transform-only UBO (per model)
struct TransformConstants {
    var modelMatrix: Matrix4x4
    var normalMatrix: Matrix3x3
    var padding: Vector3 = Vector3(0, 0, 0) // Ensure 16-byte alignment
}

// Material-only UBO (per mesh/material)
struct MaterialConstants3D {
    var materialID: UInt32
    var baseColor: Vector4 = Vector4(1.0, 1.0, 1.0, 1.0)
    var metallicFactor: Float = 0.0
    var roughnessFactor: Float = 0.5
    var padding: Vector2 = Vector2(0, 0) // Ensure alignment
}

struct MaterialConstants2D {
    var tintColor: Vector4      // RGBA tint/multiply color
    var uvScale: Vector2         // UV scaling (for texture atlases)
    var uvOffset: Vector2        // UV offset (for texture atlases)
    var alpha: Float             // Global alpha multiplier
    var effectParams: Vector3    // Custom effect parameters (glow, etc.)
    // Add padding to align to 16 bytes if needed
}

// UI Projection UBO - matches UI shader layout
struct UIProjectionConstants {
    var projection: Matrix4x4   // Orthographic projection matrix (screen pixels to NDC)
    var screenSize: Vector2     // Screen resolution for pixel-perfect positioning  
    var padding: Vector2        // Alignment to 16 bytes
}

// UI Material UBO - matches UI fragment shader layout
struct UIMaterialConstants {
    var tint: Color            // Color tint/multiplier (vec4 in shader)
    var opacity: Float         // Global opacity
    var textureMode: Int32     // 0=solid, 1=texture, 2=texture+color blend
    var roundedCorners: Int32  // Enable rounded corner rendering
    var cornerRadius: Float    // Corner radius in pixels
    var padding: Vector3       // Alignment padding
}