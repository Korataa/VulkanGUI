#version 450

// Input from vertex shader
layout(location = 0) in vec2 texCoords;

// Output
layout(location = 0) out vec4 outColor;

// Set 1: Material data (color + texture)
layout(set = 1, binding = 0) uniform Material2D {
    vec4 color;        // Base color/tint
    float opacity;     // Alpha multiplier
    int hasTexture;    // Whether to use texture (0 = solid color, 1 = textured)
    int padding[1];    // Padding for alignment
} material2D;

// Set 1: Texture (if available)
layout(set = 1, binding = 1) uniform sampler2D diffuseTexture;

void main() {
    vec4 finalColor = material2D.color;
    
    if (material2D.hasTexture != 0) {
        // Sample texture and multiply by material color
        vec4 texColor = texture(diffuseTexture, texCoords);
        finalColor = texColor * material2D.color;
    }
    
    // Apply opacity
    finalColor.a *= material2D.opacity;
    
    outColor = finalColor;
}