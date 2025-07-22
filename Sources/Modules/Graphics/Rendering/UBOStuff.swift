struct FrameConstants {
    var viewMatrix: Matrix4x4
    var projectionMatrix: Matrix4x4
    var cameraPosition: Vector3
    var time: Float
    var lightPosition: Vector3
    var lightColor: Vector3
    var ambientColor: Vector3
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
struct MaterialConstants {
    var materialID: UInt32
    var baseColor: Vector4 = Vector4(1.0, 1.0, 1.0, 1.0)
    var metallicFactor: Float = 0.0
    var roughnessFactor: Float = 0.5
    var padding: Vector2 = Vector2(0, 0) // Ensure alignment
}