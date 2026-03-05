public class Camera {
    public var position: Vector3
    public var target: Vector3
    public var up: Vector3
    public var fovY: Float = 45.0
    public var fovX: Float?             //optional if derivable from aspect ratio
    public var aspect: Float = 16.0 / 9.0
    public var nearZ: Float = 1.0  // Increased from 0.1 to fix near plane clipping
    public var farZ: Float = 100.0
    public var graphicsBackend: GraphicsBackend = .Vulkan

    public init (
        position: Vector3, target: Vector3, up: Vector3, fovY: Float, fovX: Float, aspect: Float,
        nearZ: Float, farZ: Float
    ) {
        self.position = position
        self.target = target
        self.up = up
        self.fovY = fovY
        self.fovX = fovX
        self.aspect = aspect
        self.nearZ = nearZ
        self.farZ = farZ
    }

    public init (
        position: Vector3, target: Vector3, up: Vector3
    ) {
        self.position = position
        self.target = target
        self.up = up
    }

    public var viewMatrix: Matrix4x4 {
        let matrix: Matrix4x4
        switch graphicsBackend {
            case .Vulkan:
                matrix = lookAtRH(eye: position, target: target, up: up)
            case .DirectX:
                matrix = lookAtLH(eye: position, target: target, up: up)
            case .Metal, .OpenGL:
                fatalError("Graphics backend \(graphicsBackend) not supported yet")
        }
        return matrix
    }

    public var projectionMatrix: Matrix4x4 {
        switch graphicsBackend {
            case .Vulkan:
                return perspectiveRH_ZZeroOne(fovY: fovY, aspect: aspect, nearZ: nearZ, farZ: farZ)
            case .DirectX:
                return perspectiveLH_ZZeroOne(fovY: fovY, aspect: aspect, nearZ: nearZ, farZ: farZ)
            case .Metal, .OpenGL:
                fatalError("Graphics backend \(graphicsBackend) not supported yet")
        }
    }

    public var viewProjectionMatrix: Matrix4x4 {
        return projectionMatrix * viewMatrix  //Matrix multiplcaition is not commutative
    }

    ///Convenience method to update camera parameters
    public func lookAt(newTarget: Vector3, newUp: Vector3? = nil) {
        self.target = newTarget
        if let newUp = newUp {
            self.up = newUp
        }
    }
}

extension Camera: CustomDebugStringConvertible {
    public var debugDescription: String {
        """
        Camera(
          position: \(position), 
          target: \(target),
          up: \(up), 
          fovY: \(fovY)  DEFAULT, 
          nearZ: \(nearZ)  DEFAULT,
          farZ: \(farZ)  DEFAULT
        )
        """
    }
}

struct CameraData {
    var model: Matrix4x4
    var view: Matrix4x4
    var projection: Matrix4x4
    var normalMatrix: Matrix4x4     //padded, DONT USE THE BOTTOM RIGHT PART, ONLY USE THE 3X3 IN THE TOP LEFT
}