public protocol Shader: Resource {
    //Load compiled Spir-V shaders
    func load(vertexPath: String, fragmentPath: String) throws

    //bind the shader and its descriptor sets to the command buffer
    func bind(commandBuffer: OpaquePointer)

    //Set material properties and textures
    func setMaterial(_ material: Material) throws

    //Set transform matrices (modev, view, projection)
    func setTransform(model: Matrix4x4, view: Matrix4x4, projection: Matrix4x4)
}

public enum ShaderError: Error {
    case fileNotFound
    case invalidShader
    case compilationFailed(String)
    case bindingFailed(String)
}