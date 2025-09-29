#version 450

// Input from vertex shader
layout(location = 0) in vec2 texCoords;
layout(location = 1) in vec4 vertexColor;

// Output
layout(location = 0) out vec4 outColor;

// Set 1: UI Material properties
layout(set = 1, binding = 0) uniform UIMaterial {
    vec4 tint;         // Color tint/multiplier
    float opacity;     // Global opacity
    int textureMode;   // 0=solid, 1=texture, 2=texture+color blend
    int roundedCorners; // Enable rounded corner rendering
    float cornerRadius; // Corner radius in pixels
} uiMaterial;

// Set 1: UI Texture (icons, images, etc.)
layout(set = 1, binding = 1) uniform sampler2D uiTexture;

void main() {
    // For debugging: use vertex color directly, ignore material tint
    vec4 color = vertexColor;
    
    switch(uiMaterial.textureMode) {
        case 0: // Solid color only
            break;
        case 1: // Texture only
            color = texture(uiTexture, texCoords) * uiMaterial.tint;
            break;
        case 2: // Texture * vertex color * tint
            color = texture(uiTexture, texCoords) * vertexColor * uiMaterial.tint;
            break;
    }
    
    // Apply global opacity
    color.a *= uiMaterial.opacity;
    
    // TODO: Add rounded corner logic here if needed
    
    outColor = color;
}