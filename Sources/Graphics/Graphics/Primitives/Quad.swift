import Platform
import Core
public struct Quad {
    public var position: Vector2
    public var size: Vector2
    public var color: Color
    public var textureID: UInt32?

    public init(position: Vector2, size: Vector2, color: Color, textureID: UInt32? = nil) {
        self.position = position
        self.size = size
        self.color = color
        self.textureID = textureID
    }
}