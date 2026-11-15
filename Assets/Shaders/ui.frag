#version 450

// Input from vertex shader
layout(location = 0) in vec2 texCoords;
layout(location = 1) in vec4 vertexColor;

// Output
layout(location = 0) out vec4 outColor;

// Set 1: UI Material properties
layout(set = 1, binding = 0) uniform UIMaterial {
    vec4 tint;           // Color tint/multiplier (also text color for SDF)
    float opacity;       // Global opacity
    int textureMode;     // 0=solid, 1=texture, 2=texture+color blend, 3=SDF
    int roundedCorners;  // Enable rounded corner rendering
    float cornerRadius;  // Corner radius in pixels
    float sdfThreshold;  // SDF cutoff threshold
    float outlineWidth;  // Outline thickness
    vec4 outlineColor;   // Outline color
    float sdfRange;      // Distance field range
    float reserved1;
    float reserved2;
} uiMaterial;

// Set 1: UI Texture (icons, images, etc.)
layout(set = 1, binding = 1) uniform sampler2D uiTexture;

void main() {
    vec4 vertexTint = vertexColor / 255.0;
    vec4 materialTint = uiMaterial.tint / 255.0;
    vec4 color = vertexTint;

    switch(uiMaterial.textureMode) {
        case 0: // Solid color only (use tint for text and rectangles)
            color = vertexTint * materialTint;
            break;
        case 1: // Texture only
            color = texture(uiTexture, texCoords) * vertexTint * materialTint;
            break;
        case 2: // Texture * vertex color * tint
            color = texture(uiTexture, texCoords) * vertexTint * materialTint;
            break;
        case 3: // SDF text rendering
            float sdf = texture(uiTexture, texCoords).r;
            float alpha = smoothstep(uiMaterial.sdfThreshold - uiMaterial.sdfRange, uiMaterial.sdfThreshold + uiMaterial.sdfRange, sdf);
            color = vertexTint * materialTint;
            color.a *= alpha;
            break;
    }

    // Apply global opacity
    color.a *= uiMaterial.opacity;

    // TODO: Add rounded corner logic here if needed

    outColor = color;
}