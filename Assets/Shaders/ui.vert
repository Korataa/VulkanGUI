#version 450

// Vertex inputs for UI rendering
layout(location = 0) in vec2 aPosition;  // Screen-space position (pixels)
layout(location = 1) in vec2 aTexCoord;  // Texture coordinates
layout(location = 2) in vec4 aColor;     // Per-vertex color (for UI gradients, etc.)

// Set 0: UI projection (screen-space orthographic)
layout(set = 0, binding = 0) uniform UIProjection {
    mat4 projection;  // Orthographic projection (screen pixels to NDC)
    vec2 screenSize;  // Screen resolution for pixel-perfect positioning
    vec2 padding;     // Alignment padding
} uiProjection;

// Outputs to fragment shader
layout(location = 0) out vec2 texCoords;
layout(location = 1) out vec4 vertexColor;

void main() {
    // Direct screen-space to NDC conversion
    gl_Position = uiProjection.projection * vec4(aPosition, 0.0, 1.0);
    
    // Pass data to fragment shader
    texCoords = aTexCoord;
    vertexColor = aColor;
}