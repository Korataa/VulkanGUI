import Cvulkan

public protocol GPUBuffer: ~Copyable, GraphicsResource {
    /// The handle to the underlying GPU buffer, which can be used for operations like binding or copying.
    var bufferHandle: GPUBufferHandle { get } // This can be a Vulkan buffer, DirectX buffer, etc.

    var size: UInt64 { get }
    var usage: GPUBufferUsage { get }

    /// Uploads data to the gpu buffer
    func uploadData(data: UnsafeRawPointer, size: Int)
    
    /// Uploads data to the gpu buffer at a specific offset
    func uploadData(data: UnsafeRawPointer, size: Int, offset: Int)

    func cleanup()
}

public enum GPUBufferHandle {
    case Vulkan(VkBuffer)
    case DirectX(Any)       //Not implemented yet
    case OpenGL(Any)        //not implemented yet
    case Metal(Any)         //not implemented yet

    public func asVulkanBuffer() -> VkBuffer {
        switch self {
            case .Vulkan(let vkBuffer):
                return vkBuffer
            default: 
                fatalError("Buffer handle is not a valid Vulkan buffer!!!")
        }
    }
}