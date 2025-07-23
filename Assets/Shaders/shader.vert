#version 450

layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aNormal;       //For lighting

// Set 0: Frame data (camera, lighting)
layout(set = 0, binding = 0) uniform FrameData {
    mat4 view;
    mat4 proj;
    vec3 lightPos;
    vec3 lightColor;
    vec3 viewPos;
} frameData;

// Set 1: Transform data (per model)
layout(set = 1, binding = 0) uniform TransformData {
    mat4 model;
    mat4 normal;
} transformData;

layout(location = 0) out vec3 fragPos;      //to pass position to fragment shader
layout(location = 1) out vec3 normal;       //to pass normal to grament shader

void main() {
    //transform vertex position to world space
    vec4 worldPosition = transformData.model * vec4(aPosition, 1.0);
    fragPos = worldPosition.xyz;

    //transform vertex normal with normal matrix
    normal = mat3(transformData.normal) * aNormal;

    //Transform vertex to clip space
    gl_Position = frameData.proj * frameData.view * worldPosition;
}