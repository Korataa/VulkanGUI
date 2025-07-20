#version 450

layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aNormal;       //For lighting

//Uniform block containing model, view, projection matrices
layout(set = 0, binding = 0) uniform UBO {
    mat4 model;
    mat4 view;
    mat4 proj;
} ubo;

layout(location = 0) out vec3 fragPos;      //to pass position to fragment shader
layout(location = 1) out vec3 normal;       //to pass normal to grament shader

void main() {
    //transform vertex position to world space
    vec4 worldPosition = ubo.model * vec4(aPosition, 1.0);
    fragPos = worldPosition.xyz;

    //transform vertex normal with model matrix (handle non-uniform scale)
    normal = mat3(transpose(inverse(ubo.model))) * aNormal;

    //Transform vertex to clip space
    gl_Position = ubo.proj * ubo.view * worldPosition;
}