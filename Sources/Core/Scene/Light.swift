import Math

public struct Light {
    public var direction: Vector3
    public var color: Color
    public var intensity: Float

    public init(direction: Vector3, color: Color, intensity: Float) {
        self.direction = direction.normalize()
        self.color = color
        self.intensity = intensity
    }
}