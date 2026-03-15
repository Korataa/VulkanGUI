import Platform
import Core
import Foundation
import Cstb_image

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

    public var graphicsType: GraphicsResourceType { .texture }
    public var resourceType: ResourceCategory { .graphics(graphicsType) }

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