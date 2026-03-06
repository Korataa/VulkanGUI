import Foundation

public struct Transform {
    //Core properties
    public var position: Vector3
    public var rotation: Quaternion
    public var scale: Vector3

    //default initializer
    public init(
        position: Vector3,
        rotation: Quaternion = .identity(),
        scale: Vector3
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }

    //helper for 2D (z=0, uniform scale)
    public static func transform2D(
        position: Vector2,
        rotationAngle: Float,
        scale: Vector2
    ) -> Transform {
        let halfAngle = rotationAngle * 0.5
        let zRot = Quaternion( cos(halfAngle), 0, 0, sin(halfAngle) )

        return Transform(
            position: Vector3(position.x, position.y, 0), 
            rotation: zRot, 
            scale: Vector3(scale.x, scale.y, 1)
        )
    }

    public var modelMatrix: Matrix4x4 {
        let translationMatrix = Matrix4x4(translation: position)
        let rotationMatrix = rotation.toMatrix4x4()
        let scaleMatrix = Matrix4x4(scale: scale)

        //Compose model matrix: translation * rotation * scale
        return translationMatrix * rotationMatrix * scaleMatrix
    }

    public var normalMatrix: Matrix3x3 {
        return modelMatrix.upperLeft3x3.inverted().transposed()
    }
}