struct FrameConstants {
    var viewMatrix: Matrix4x4
    var projectionMatrix: Matrix4x4
    var lightPosition: Vector3
    var lightColor: Vector3
    var ambientColor: Vector3
}

let MAX_OBJECTS = 1024

struct ObjectConstants {
    var modelMatrix: Matrix4x4
    var normalMatrix: Matrix3x3
    var materialID: UInt32
    var padding: UInt32 = 0
}   //128 bytes (good for dynamic offsetting)