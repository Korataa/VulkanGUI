import Foundation
import Cstb_image

//Have to explicitly define ~Copyable because swift sucks (jk but pretty sure this is a compiler bug)
public struct Texture: ~Copyable, GraphicsResource {
    public var name: String?
    private var _id: Int?
    public var id: Int? {
        get { _id }
        set {
            precondition(_id == nil, "Id can only be set once!!")
            _id = newValue
        }
    }

    public var resourceType: ResourceType { .graphics(.texture) }

    public let width: Int
    public let height: Int
    public let channels: Int
    public let pixels: UnsafeMutablePointer<UInt8>?

    public init(width: Int, height: Int, channels: Int, pixels: UnsafeMutablePointer<UInt8>?) {
        self.width = width
        self.height = height
        self.channels = channels
        self.pixels = pixels
    }

    public func cleanup() {
        if let pixels = pixels {
            stbi_image_free(pixels)
        }
    }

    deinit {
        cleanup()
    }
}