#version 450 core

layout(location = 0) in vec3 fragPos;
layout(location = 1) in vec3 normal;

layout(location = 0) out vec4 outColor;

// Set 0: Frame data (camera, lighting)
layout(set = 0, binding = 0) uniform FrameData {
    mat4 view;
    mat4 proj;
    vec3 lightPos;
    vec3 lightColor;
    vec3 viewPos;
} frameData;

// Set 2: Material data (per mesh)
layout(set = 2, binding = 0) uniform MaterialData {
    uint materialID;
    vec3 albedo;
    float roughness;
    float metallic;
} materialData;

void main() {
    //normalize input normal
    vec3 norm = normalize(normal);

    //calculate light direction
    vec3 lightDir = normalize(frameData.lightPos - fragPos);

    //diffuse shading
    float diff = max(dot(norm, lightDir), 0.0);

    //ambient term
    vec3 ambient = 0.1 * frameData.lightColor;

    //diffuse term
    vec3 diffuse = diff * frameData.lightColor;

    //Simple phong-like color with material influence
    vec3 result = (ambient + diffuse) * materialData.albedo;

    outColor = vec4(result, 1.0);
}