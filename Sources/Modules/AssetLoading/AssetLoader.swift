import Cgltf
import Cstb_image

import Foundation

public struct LoadedMesh {
    var vertexOffset: Int
    var vertexCount: Int
    var indexOffset: Int
    var indexCount: Int
    var materialIndex: Int?
    var bounds: (min: Vector3, max: Vector3)  // Added bounds
}

public struct LoadedModel {
    var meshes: [LoadedMesh]
    var textureStorage: TextureStorage
    var materials: [Material]
    var nodeTransforms: [Matrix4x4]
}

public class AssetLoader {
    private let resourceManager: GraphicsResourceManager

    public init(resourceManager: GraphicsResourceManager) {
        self.resourceManager = resourceManager
    }

    public func loadModel(at path: String) -> LoadedModel? {
        //need this for stuff below
        let basePath = (path as NSString).deletingLastPathComponent

        // --- 1. Parse glTF ---
        var options = cgltf_options()
        var data: UnsafeMutablePointer<cgltf_data>? = nil
        var result = path.withCString { cPath in
            cgltf_parse_file(&options, cPath, &data)
        }
        guard result == cgltf_result_success, let dataPtr = data else {
            print("Error: Failed to parse glTF file")
            return nil
        }
        defer { cgltf_free(dataPtr) }

        // --- 2. Load buffers (e.g., .bin files) ---
        let loadResult = path.withCString { cPath in
            cgltf_load_buffers(&options, dataPtr, cPath)
        }
        guard loadResult == cgltf_result_success else {
            print("Error: Failed to load buffers")
            return nil
        }

        let dataVal = dataPtr.pointee

        // --- 3. Load textures ---
        var textureStorage = TextureStorage()
        for i in 0..<dataVal.images_count {
            let image = dataVal.images[i]
            if let imageData = loadImageData(from: image, basePath: basePath) {
                let (pixels, width, height, channels) = decodeImage(imageData)
                let texture = Texture(width: Int(width), height: Int(height), channels: Int(channels), pixels: pixels)
                
                // Register texture with resource manager and get ID
                let textureId = resourceManager.addResource(texture)
                textureStorage.addTextureId(textureId, width: Int(width), height: Int(height), channels: Int(channels))
            }
        }

        // --- 4. Load materials (basic) ---
        var materials: [Material] = []
        for i in 0..<dataVal.materials_count {
            let mat = dataVal.materials[i]
            let material = Material()

            //Fill in pbr properties
            let pbr = mat.pbr_metallic_roughness
            material.baseColor = Color(
                pbr.base_color_factor.0,
                pbr.base_color_factor.1,
                pbr.base_color_factor.2,
                pbr.base_color_factor.3
            )
            material.metallicFactor = pbr.metallic_factor
            material.roughnessFactor = pbr.roughness_factor

            //Add textures
            let baseColorTex = mat.pbr_metallic_roughness.base_color_texture
            material.baseColorTextureIndex = baseColorTex.texture - dataVal.textures

            //similar for other textures
            let metallicRoughnessTex = mat.pbr_metallic_roughness.metallic_roughness_texture
            material.metallicRoughnessTextureIndex = metallicRoughnessTex.texture - dataVal.textures

            let normalTex = mat.normal_texture
            material.normalTextureIndex = normalTex.texture - dataVal.textures
            material.normalScale = normalTex.scale

            let occlusionTex = mat.occlusion_texture
            material.occlusionTextureIndex = occlusionTex.texture - dataVal.textures
            // Note: cgltf_texture_view doesn't have strength field, using default
            material.occlusionStrength = 1.0

            materials.append(material)
        }

        // --- 5. Load node transforms ---
        var nodeTransforms: [Matrix4x4] = []
        for i in 0..<dataVal.nodes_count {
            let node = dataVal.nodes[i]
            nodeTransforms.append(nodeToMatrix(node))
        }

        // --- 6. (Finally) load mesh data and upload to buffers ---
        guard resourceManager.staticVertexBuffer != nil,
              resourceManager.indexBuffer != nil else {
                print("Error: Buffers not initialized")
                return nil
        }

        var meshes: [LoadedMesh] = []

        for i in 0..<dataVal.meshes_count {
            let mesh = dataVal.meshes[i]
            for j in 0..<mesh.primitives_count {
                let prim = mesh.primitives[j]

                // --- Extract vertex atttributes ---
                var positions: [SIMD3<Float>] = []
                var normals: [SIMD3<Float>] = []
                var texCoords: [SIMD2<Float>] = []

                for k in 0..<prim.attributes_count {
                    let attr = prim.attributes[k]
                    let accessor = attr.data?.pointee
                    guard let accessor = accessor,
                            let bufferView = accessor.buffer_view?.pointee,
                            let buffer = bufferView.buffer?.pointee else { continue }

                    let offset = Int(bufferView.offset) + Int(accessor.offset)
                    let stride = bufferView.stride != 0 ? Int(bufferView.stride) : 
                        attr.type == cgltf_attribute_type_position ?
                            (3 * MemoryLayout<Float>.stride) :  //position: 3 floats * 4 bytes = 12 bytes
                            (2 * MemoryLayout<Float>.stride)    //texcoord: 2 floats * 4 bytes = 8 bytes
                    let count = accessor.count

                    if attr.type == cgltf_attribute_type_position {
                        let basePtr = buffer.data!.advanced(by: offset).assumingMemoryBound(to: Float.self)
                        for v in 0..<count {
                            let ptr = basePtr.advanced(by: v * (stride / MemoryLayout<Float>.size))
                            positions.append(SIMD3<Float>(ptr[0], ptr[1], ptr[2]))
                        }
                    } else if attr.type == cgltf_attribute_type_normal {
                        let basePtr = buffer.data!.advanced(by: offset).assumingMemoryBound(to: Float.self)
                        for v in 0..<count {
                            let ptr = basePtr.advanced(by: v * (stride / MemoryLayout<Float>.size))
                            normals.append(SIMD3<Float>(ptr[0], ptr[1], ptr[2]))
                        }
                    } else if attr.type == cgltf_attribute_type_texcoord {
                        let basePtr = buffer.data!.advanced(by: offset).assumingMemoryBound(to: Float.self)
                        for v in 0..<count {
                            let ptr = basePtr.advanced(by: v * (stride / MemoryLayout<Float>.size))
                            texCoords.append(SIMD2<Float>(ptr[0], ptr[1]))
                        }
                    }
                }

                // --- interleave vertex data ---
                var vertices: [Vertex3D] = []
                
                // Initialize bounds for this mesh
                var minBounds = Vector3(Float.infinity, Float.infinity, Float.infinity)
                var maxBounds = Vector3(-Float.infinity, -Float.infinity, -Float.infinity)
                
                for v in 0..<positions.count {
                    let pos = positions[v]
                    let norm = v < normals.count ? normals[v] : SIMD3<Float>(0, 0, 0)
                    let uv = v < texCoords.count ? texCoords[v] : SIMD2<Float>(0, 0)
                    vertices.append(Vertex3D(position: pos, normal: norm, texCoord: uv))
                    
                    // Update bounds
                    let vertexPos = Vector3(pos.x, pos.y, pos.z)
                    minBounds = Vector3(
                        min(minBounds.x, vertexPos.x),
                        min(minBounds.y, vertexPos.y),
                        min(minBounds.z, vertexPos.z)
                    )
                    maxBounds = Vector3(
                        max(maxBounds.x, vertexPos.x),
                        max(maxBounds.y, vertexPos.y),
                        max(maxBounds.z, vertexPos.z)
                    )
                }

                // --- Extract indices ---
                var indices: [UInt32] = []
                if  let indicesAccessor = prim.indices?.pointee,
                    let bufferView = indicesAccessor.buffer_view?.pointee,
                    let buffer = bufferView.buffer?.pointee {
                        let offset = Int(bufferView.offset) + Int(indicesAccessor.offset)
                        let indexCount = indicesAccessor.count
                        let indexType = indicesAccessor.component_type

                        if indexType == cgltf_component_type_r_16u {
                            let basePtr = buffer.data!.advanced(by: offset).assumingMemoryBound(to: UInt16.self)
                            for i in 0..<indexCount {
                                indices.append(UInt32(basePtr[i]))
                            }
                        } else if indexType == cgltf_component_type_r_32u {
                            let basePtr = buffer.data!.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
                            for i in 0..<indexCount {
                                indices.append(basePtr[i])
                            }
                        }
                }

                // --- Upload to buffers and create mesh descriptor ---
                do {
                    let vertexRegion = try resourceManager.allocateRegion(
                        type: .staticVertex, 
                        size: vertices.count * MemoryLayout<Vertex3D>.stride
                    )
                    let indexRegion = try resourceManager.allocateRegion(
                        type: .index, 
                        size: indices.count * MemoryLayout<UInt32>.stride
                    )
                    
                    // Upload the data
                    vertices.withUnsafeBytes { vertexBytes in
                        vertexRegion.buffer.uploadData(
                            data: vertexBytes.baseAddress!,
                            size: vertexBytes.count,
                            offset: vertexRegion.offset
                        )
                    }
                    
                    indices.withUnsafeBytes { indexBytes in
                        indexRegion.buffer.uploadData(
                            data: indexBytes.baseAddress!,
                            size: indexBytes.count,
                            offset: indexRegion.offset
                        )
                    }
                
                    meshes.append(LoadedMesh(
                        vertexOffset: vertexRegion.offset,
                        vertexCount: vertices.count,
                        indexOffset: indexRegion.offset,
                        indexCount: indices.count,
                        materialIndex: prim.material != nil ? Int(prim.material - dataVal.materials) : nil,
                        bounds: (min: minBounds, max: maxBounds)
                    ))
                } catch {
                    print("Error uploading mesh data: \(error)")
                    return nil
                }
            }
        }

        return LoadedModel(
            meshes: meshes,
            textureStorage: textureStorage,
            materials: materials,
            nodeTransforms: nodeTransforms
        )
    }

    // Convert a LoadedMesh to a Mesh instance
    public func createMesh(from loadedMesh: LoadedMesh, primitiveType: PrimitiveType = .triangles) -> Mesh {
        let bounds = BoundingBox(min: loadedMesh.bounds.min, max: loadedMesh.bounds.max)
        
        return StaticMesh(
            vertexOffset: loadedMesh.vertexOffset,
            vertexCount: loadedMesh.vertexCount,
            indexCount: loadedMesh.indexCount,
            indexOffset: loadedMesh.indexOffset,
            vertexStride: MemoryLayout<Vertex3D>.stride,
            primitiveType: primitiveType,
            materialID: UInt32(loadedMesh.materialIndex ?? 0),
            bounds: bounds
        )
    }

    // Create a Model from a LoadedModel
    public func createModel(from loadedModel: LoadedModel) -> Model {
        let meshes = loadedModel.meshes.map { createMesh(from: $0) }
        return Model(
            meshes: meshes,
            transform: Transform(
                position: Vector3(0, 0, 0),
                scale: Vector3(1, 1, 1)
            )
        )
    }

    //Not sure if i will actually loadShaders from here lol, but maybe??
    //public func loadShader()
}

//helper: Convert cgltf_node to Matrix4x4
func nodeToMatrix(_ node: cgltf_node) -> Matrix4x4 {
    if node.has_matrix != 0 {
        //Node has a direct 4x4 matrix
        let m = node.matrix
        return Matrix4x4(
            m.1, m.1, m.2, m.3,
            m.4, m.5, m.6, m.7,
            m.8, m.9, m.10, m.11,
            m.12, m.13, m.14, m.15
        )
    } else {
        //Node has translation, rotation, and scale
        let position = Vector3(
            node.translation.0,
            node.translation.1,
            node.translation.2
        )

        let rotation = Quaternion(
            node.rotation.0,
            node.rotation.1,
            node.rotation.2,
            node.rotation.3
        )

        let scale = Vector3(
            node.scale.0,
            node.scale.1,
            node.scale.2
        )

        let transform = Transform(position: position, rotation: rotation, scale: scale)

        return transform.modelMatrix
    }
}

func loadImageData(from image: cgltf_image, basePath: String) -> Data? {
    //Case 1: Embedded as base64 in a data URI
    if let uriPtr = image.uri, String(cString: uriPtr).starts(with: "data:") {
        let uri = String(cString: uriPtr)
        guard let commaIndex = uri.firstIndex(of: ",") else { return nil }
        let base64String = String(uri[uri.index(after: commaIndex)...])
        return Data(base64Encoded: base64String)
    }

    //Case 2: external image file
    if let uriPtr = image.uri {
        let uri = String(cString: uriPtr)
        let imagePath = (basePath as NSString).appendingPathComponent(uri)
        return try? Data(contentsOf: URL(fileURLWithPath: imagePath))
    }

    //Case 3: image is embedded in the .bin buffer
    if let bufferView = image.buffer_view?.pointee,
        let buffer = bufferView.buffer?.pointee,
        let rawBuffer = buffer.data {
            let offset = Int(bufferView.offset)
            let size = Int(bufferView.size)
            let rawPtr = rawBuffer.advanced(by: offset)
            return Data(bytes: rawPtr, count: size)
    }

    return nil      //image is fucked up somehow, or maybe gltf is corrupted??
}

func decodeImage(_ data: Data) -> (pixels: UnsafeMutablePointer<UInt8>?, width: Int32, height: Int32, channels: Int32) {
    var width: Int32 = 0
    var height: Int32 = 0
    var channels: Int32 = 0

    //stb image expects a pointer to UInt8
    let pixelPtr = data.withUnsafeBytes { rawBufferPtr in
        return stbi_load_from_memory(
            rawBufferPtr.bindMemory(to: UInt8.self).baseAddress,
            Int32(data.count),
            &width,
            &height,
            &channels,
            4   //Force rgba
        )
    }

    return (pixels: pixelPtr, width: width, height: height, channels: 4)
}

func attributeTypeToString(_ type: cgltf_attribute_type) -> String {
    switch type {
        case cgltf_attribute_type_position: return "POSITION"
        case cgltf_attribute_type_normal: return "NORMAL"
        case cgltf_attribute_type_tangent: return "TANGENT"
        case cgltf_attribute_type_texcoord: return "TEXCOORD"
        case cgltf_attribute_type_color: return "COLOR"
        case cgltf_attribute_type_joints: return "JOINTS"
        case cgltf_attribute_type_weights: return "WEIGHTS"
        default: return "UNKNOWN"
    }
}