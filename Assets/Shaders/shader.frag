#version 450 core

layout(location = 0) in vec3 fragPos;
layout(location = 1) in vec3 normal;
layout(location = 2) in vec2 texCoords;  // Add texture coordinates

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
    vec4 baseColor;
    float roughness;
    float metallic;
} materialData;

// Set 2: Texture sampler for diffuse/base color texture  
layout(set = 2, binding = 1) uniform sampler2D diffuseTexture;

void main() {
    // Sample the diffuse texture
    vec4 textureColor = texture(diffuseTexture, texCoords);
    
    // Debug: Let's see what the material base color is
    vec3 matColor = materialData.baseColor.rgb;
    
    // Ensure material color isn't too dark (some materials might have very dark base colors)
    matColor = max(matColor, vec3(0.2)); // Minimum brightness
    
    // Combine texture with material
    vec3 finalColor = matColor * textureColor.rgb;

    // Correct normals on backfaces when double-sided rendering is active.
    // With culling enabled this is a no-op, but it prevents inverted lighting when culling is disabled.
    vec3 N = normalize(normal);
    N = gl_FrontFacing ? N : -N;

    vec3 lightDelta = frameData.lightPos - fragPos;
    float lightLen = length(lightDelta);
    vec3 L = lightLen > 1e-5 ? (lightDelta / lightLen) : vec3(0.0, 1.0, 0.0);
    float lambert = max(dot(N, L), 0.0);

    // Additive ambient prevents fully black surfaces when texture/light data is weak.
    finalColor = finalColor * (0.7 + 0.3 * lambert) + vec3(0.2);
    
    outColor = vec4(finalColor, 1.0);
}