import Foundation

// Graphics API enum - defined in Core so Camera and other core types can reference it
public enum GraphicsBackend {
    case Vulkan
    case Metal
    case DirectX
    case OpenGL
}
