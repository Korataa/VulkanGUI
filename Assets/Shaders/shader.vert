#version 450

layout(location = 0) in vec3 aPosition;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec2 aTexCoord;

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

layout(location = 0) out vec3 fragPos;
layout(location = 1) out vec3 normal;
layout(location = 2) out vec2 texCoords;  // Pass texture coordinates to fragment shader

void main() {
    vec4 worldPosition = transformData.model * vec4(aPosition, 1.0);
    fragPos = worldPosition.xyz;
    normal = mat3(transformData.normal) * aNormal;
    texCoords = aTexCoord;  // Pass through texture coordinates
    gl_Position = frameData.proj * frameData.view * worldPosition;
}
