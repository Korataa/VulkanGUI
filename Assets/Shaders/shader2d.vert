#version 450

// Vertex inputs for 2D rendering (position + texture coordinates)
layout(location = 0) in vec2 aPosition;  // 2D position
layout(location = 1) in vec2 aTexCoord;  // Texture coordinates

// Set 0: Transform data for 2D (ortho projection + model matrix)
layout(set = 0, binding = 0) uniform Transform2D {
    mat4 projection;  // Orthographic projection matrix
    mat4 model;       // Model/world matrix for positioning
} transform2D;

// Outputs to fragment shader
layout(location = 0) out vec2 texCoords;

void main() {
    // Transform 2D position to clip space
    gl_Position = transform2D.projection * transform2D.model * vec4(aPosition, 0.0, 1.0);
    
    // Pass texture coordinates through
    texCoords = aTexCoord;
}