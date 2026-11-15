import Platform
import Core
import Math

public protocol Shader: Resource {
    //Load compiled Spir-V shaders
    func load(vertexPath: String, fragmentPath: String) throws

    //bind the shader and its descriptor sets to the command buffer
    func bind(commandBuffer: OpaquePointer)

    //Set material properties and textures
    func setMaterial(_ material: Material) throws

}

public enum ShaderError: Error {
    case fileNotFound
    case invalidShader
    case compilationFailed(String)
    case bindingFailed(String)
}