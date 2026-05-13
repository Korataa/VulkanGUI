import Graphics
import Core
import Math
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
    private let resourceManager: VulkanResourceManager
    
    public init(resourceManager: VulkanResourceManager) {
        self.resourceManager = resourceManager
    }

    public func loadModel(at path: String, flipNormals: Bool = false) -> LoadedModel? {
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
                var texture = Texture(width: Int(width), height: Int(height), channels: Int(channels), pixels: pixels)
                
                // Register texture with resource manager and get ID using explicit move
                let textureId = resourceManager.addTexture(consume texture)
                textureStorage.addTextureId(textureId, width: Int(width), height: Int(height), channels: Int(channels))
            } else {
            }
        }

        // --- 4. Load materials (basic) ---
        var materials: [Material] = []
        for i in 0..<dataVal.materials_count {
            let mat = dataVal.materials[i]
            let material = Material()

            //Fill in pbr properties
            let pbr = mat.pbr_metallic_roughness
            
            // Check if this GLTF uses specular glossiness extension
            
            // Use specular-glossiness extension if available (which contains the real colors)
            if mat.has_pbr_specular_glossiness != 0 {
                let specGloss = mat.pbr_specular_glossiness
                
                // Use the diffuse_factor from specular-glossiness extension (this is the actual color)
                material.baseColor = Color(
                    specGloss.diffuse_factor.0 * 255.0,
                    specGloss.diffuse_factor.1 * 255.0,
                    specGloss.diffuse_factor.2 * 255.0,
                    specGloss.diffuse_factor.3 * 255.0
                )
                
                // Convert glossiness to roughness (roughness = 1.0 - glossiness)
                material.roughnessFactor = 1.0 - specGloss.glossiness_factor
                // Use specular factor as metallic approximation (this is not perfect but a reasonable conversion)
                let specularIntensity = (specGloss.specular_factor.0 + specGloss.specular_factor.1 + specGloss.specular_factor.2) / 3.0
                material.metallicFactor = specularIntensity
                
            } else {
                // Fallback to standard PBR
                material.baseColor = Color(
                    pbr.base_color_factor.0 * 255.0,
                    pbr.base_color_factor.1 * 255.0,
                    pbr.base_color_factor.2 * 255.0,
                    pbr.base_color_factor.3 * 255.0
                )
                material.metallicFactor = pbr.metallic_factor
                material.roughnessFactor = pbr.roughness_factor
            }

            material.doubleSided = mat.double_sided != 0

            //Add textures - check specular-glossiness extension first
            if mat.has_pbr_specular_glossiness != 0 {
                // Use diffuse texture from specular-glossiness extension
                let diffuseTex = mat.pbr_specular_glossiness.diffuse_texture
                if let texPtr = diffuseTex.texture, let basePtr = dataVal.textures {
                    material.baseColorTextureIndex = texPtr - basePtr
                } else {
                    material.baseColorTextureIndex = -1
                }
                
                // Use specular-glossiness texture for metallic-roughness
                let specGlossTex = mat.pbr_specular_glossiness.specular_glossiness_texture  
                if let texPtr = specGlossTex.texture, let basePtr = dataVal.textures {
                    material.metallicRoughnessTextureIndex = texPtr - basePtr
                } else {
                    material.metallicRoughnessTextureIndex = -1
                }
            } else {
                // Standard PBR texture handling
                let baseColorTex = mat.pbr_metallic_roughness.base_color_texture
                if let texPtr = baseColorTex.texture, let basePtr = dataVal.textures {
                    material.baseColorTextureIndex = texPtr - basePtr
                } else {
                    material.baseColorTextureIndex = -1
                }

                //similar for other textures
                let metallicRoughnessTex = mat.pbr_metallic_roughness.metallic_roughness_texture
                if let texPtr = metallicRoughnessTex.texture, let basePtr = dataVal.textures {
                    material.metallicRoughnessTextureIndex = texPtr - basePtr
                } else {
                    material.metallicRoughnessTextureIndex = -1
                }
            }

            let normalTex = mat.normal_texture
            if let texPtr = normalTex.texture, let basePtr = dataVal.textures {
                material.normalTextureIndex = texPtr - basePtr
            } else {
                material.normalTextureIndex = -1
            }
            material.normalScale = normalTex.scale

            let occlusionTex = mat.occlusion_texture
            if let texPtr = occlusionTex.texture, let basePtr = dataVal.textures {
                material.occlusionTextureIndex = texPtr - basePtr
            } else {
                material.occlusionTextureIndex = -1
            }
            // Note: cgltf_texture_view doesn't have strength field, using default
            material.occlusionStrength = 1.0

            // Fix for materials with no texture but black base color factor
            if material.baseColorTextureIndex == -1 {
                let baseColorFactor = (material.baseColor.r / 255.0, material.baseColor.g / 255.0, material.baseColor.b / 255.0)
                if baseColorFactor.0 == 0.0 && baseColorFactor.1 == 0.0 && baseColorFactor.2 == 0.0 {
                    // This material has no texture and black base color - give it a reasonable default
                    material.baseColor = Color(200, 200, 200, 255)  // Light gray
                }
            }
            
            // TEMPORARY DEBUG: Make ALL materials bright white to test visibility
            material.baseColor = Color(255, 255, 255, 255)  // Force white

            materials.append(material)
        }

        // --- 5. Load node transforms and bake into mesh vertices ---
        var nodeTransforms: [Matrix4x4] = []
        var nodeTransformMap: [Int: Matrix4x4] = [:]
        for i in 0..<dataVal.nodes_count {
            let node = dataVal.nodes[i]
            let transform = nodeToMatrix(node)
            nodeTransforms.append(transform)
            nodeTransformMap[Int(i)] = transform
        }

        // --- 6. (Finally) load mesh data and upload to buffers ---
        guard let meshes = loadMeshes(from: dataVal, nodeTransformMap: nodeTransformMap, flipNormals: flipNormals) else {
            return nil
        }

        return LoadedModel(
            meshes: meshes,
            textureStorage: textureStorage,
            materials: materials,
            nodeTransforms: nodeTransforms
        )
    }

    private func loadMeshes(from dataVal: cgltf_data, nodeTransformMap: [Int: Matrix4x4], flipNormals: Bool = false) -> [LoadedMesh]? {
        guard resourceManager.staticVertexBuffer != nil,
              resourceManager.indexBuffer != nil else {
            if resourceManager.staticVertexBuffer == nil {
                print("Error: staticVertexBuffer is nil")
            }
            if resourceManager.indexBuffer == nil {
                print("Error: indexBuffer is nil")
            }
            print("Error: Buffers not initialized")
            return nil
        }

        // Build node-to-mesh mapping (which node uses which mesh)
        var nodeToMesh: [Int: Int] = [:]
        for nodeIdx in 0..<dataVal.nodes_count {
            let node = dataVal.nodes[nodeIdx]
            if let meshPtr = node.mesh {
                let meshIdx = Int(meshPtr - dataVal.meshes)
                nodeToMesh[nodeIdx] = meshIdx
            }
        }

        var meshes: [LoadedMesh] = []
        for i in 0..<dataVal.meshes_count {
            let mesh = dataVal.meshes[i]
            
            // Find which node(s) use this mesh to get the transform
            var meshTransform: Matrix4x4? = nil
            for (nodeIdx, meshIdx) in nodeToMesh {
                if meshIdx == i {
                    meshTransform = nodeTransformMap[nodeIdx]
                    break
                }
            }
            
            for j in 0..<mesh.primitives_count {
                let prim = mesh.primitives[j]
                var (positions, normals, texCoords) = extractVertexAttributes(from: prim)
                
                // Flip normals if needed (for incorrectly exported glTF files)
                if flipNormals {
                    normals = normals.map { norm in
                        return SIMD3<Float>(-norm.x, -norm.y, -norm.z)
                    }
                }
                
                // Apply node transform to vertex positions and normals if this mesh has a transform
                if let transform = meshTransform {
                    // DISABLED FOR DEBUG - verify geometry is clean at origin
                    /*
                    // Transform positions (use full 4x4 matrix for translation)
                    positions = positions.map { pos in
                        let pos4 = SIMD4<Float>(pos.x, pos.y, pos.z, 1.0)
                        let transformed = transform * pos4
                        return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
                    }
                    
                    // Transform normals (use 3x3 rotation part only, then normalize)
                    normals = normals.map { norm in
                        let normVec = Vector3(norm.x, norm.y, norm.z)
                        // Extract 3x3 rotation and apply to normal
                        let rotated = Vector3(
                            transform[0].x * normVec.x + transform[0].y * normVec.y + transform[0].z * normVec.z,
                            transform[1].x * normVec.x + transform[1].y * normVec.y + transform[1].z * normVec.z,
                            transform[2].x * normVec.x + transform[2].y * normVec.y + transform[2].z * normVec.z
                        )
                        let normalized = rotated.normalize()
                        return SIMD3<Float>(normalized.x, normalized.y, normalized.z)
                    }
                    */
                }
                
                let (vertices, minBounds, maxBounds) = buildVerticesAndBounds(
                    positions: positions,
                    normals: normals,
                    texCoords: texCoords
                )
                let indices = extractIndices(from: prim)

                do {
                    let vertexRegion = try resourceManager.allocateStaticVertices(vertices: vertices)
                    let indexRegion = try resourceManager.allocateIndices(indices: indices)

                    let maxIndex = indices.max() ?? 0
                    if maxIndex >= vertices.count {
                        print("ERROR: Index out of bounds! Max index: \(maxIndex), vertex count: \(vertices.count)")
                    }

                    meshes.append(LoadedMesh(
                        vertexOffset: vertexRegion.offset / MemoryLayout<Vertex3D>.stride,
                        vertexCount: vertices.count,
                        indexOffset: indexRegion.offset / MemoryLayout<UInt32>.stride,
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

        return meshes
    }

    private func extractVertexAttributes(from prim: cgltf_primitive) -> ([SIMD3<Float>], [SIMD3<Float>], [SIMD2<Float>]) {
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
            let stride: Int
            if bufferView.stride != 0 {
                stride = Int(bufferView.stride)
            } else if attr.type == cgltf_attribute_type_position {
                stride = 3 * MemoryLayout<Float>.stride
                } else if attr.type == cgltf_attribute_type_normal {
                    stride = 3 * MemoryLayout<Float>.stride
                } else {
                stride = 2 * MemoryLayout<Float>.stride
            }

            let count = accessor.count
            guard let bufferData = buffer.data else {
                print("Warning: buffer.data is nil for attribute type \(attributeTypeToString(attr.type)), skipping this attribute.")
                continue
            }

            if attr.type == cgltf_attribute_type_position {
                let basePtr = bufferData.advanced(by: offset).assumingMemoryBound(to: Float.self)
                for v in 0..<count {
                    let ptr = basePtr.advanced(by: v * (stride / MemoryLayout<Float>.size))
                    positions.append(SIMD3<Float>(ptr[0], ptr[1], ptr[2]))
                }
            } else if attr.type == cgltf_attribute_type_normal {
                let basePtr = bufferData.advanced(by: offset).assumingMemoryBound(to: Float.self)
                for v in 0..<count {
                    let ptr = basePtr.advanced(by: v * (stride / MemoryLayout<Float>.size))
                    normals.append(SIMD3<Float>(ptr[0], ptr[1], ptr[2]))
                }
            } else if attr.type == cgltf_attribute_type_texcoord {
                let basePtr = bufferData.advanced(by: offset).assumingMemoryBound(to: Float.self)
                for v in 0..<count {
                    let ptr = basePtr.advanced(by: v * (stride / MemoryLayout<Float>.size))
                    texCoords.append(SIMD2<Float>(ptr[0], ptr[1]))
                }
            }
        }

        return (positions, normals, texCoords)
    }

    private func buildVerticesAndBounds(
        positions: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        texCoords: [SIMD2<Float>]
    ) -> ([Vertex3D], Vector3, Vector3) {
        var vertices: [Vertex3D] = []
        var minBounds = Vector3(Float.infinity, Float.infinity, Float.infinity)
        var maxBounds = Vector3(-Float.infinity, -Float.infinity, -Float.infinity)

        for v in 0..<positions.count {
            let pos = positions[v]
            let norm = v < normals.count ? normals[v] : SIMD3<Float>(0, 0, 0)
            let uv = v < texCoords.count ? texCoords[v] : SIMD2<Float>(0, 0)
            vertices.append(Vertex3D(position: pos, normal: norm, texCoord: uv))

            let vertexPos = Vector3(pos.x, pos.y, pos.z)
            minBounds = Vector3(min(minBounds.x, vertexPos.x), min(minBounds.y, vertexPos.y), min(minBounds.z, vertexPos.z))
            maxBounds = Vector3(max(maxBounds.x, vertexPos.x), max(maxBounds.y, vertexPos.y), max(maxBounds.z, vertexPos.z))
        }

        return (vertices, minBounds, maxBounds)
    }

    private func extractIndices(from prim: cgltf_primitive) -> [UInt32] {
        var indices: [UInt32] = []
        if let indicesAccessor = prim.indices?.pointee,
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

        return indices
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
            materials: loadedModel.materials,  // Pass the actual materials
            transform: Transform(
                position: Vector3(0, 0, 0),
                scale: Vector3(10, 10, 10)  // Scale up 10x for visibility test
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
            m.0, m.1, m.2, m.3,
            m.4, m.5, m.6, m.7,
            m.8, m.9, m.10, m.11,
            m.12, m.13, m.14, m.15
        )
    }

    let position = node.has_translation != 0
        ? Vector3(node.translation.0, node.translation.1, node.translation.2)
        : Vector3(0, 0, 0)

    let rotation = node.has_rotation != 0
        ? Quaternion(node.rotation.0, node.rotation.1, node.rotation.2, node.rotation.3)
        : Quaternion.identity()

    let scale = node.has_scale != 0
        ? Vector3(node.scale.0, node.scale.1, node.scale.2)
        : Vector3(1, 1, 1)

    let transform = Transform(position: position, rotation: rotation, scale: scale)
    return transform.modelMatrix
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
