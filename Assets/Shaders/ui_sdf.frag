#version 450

//Input from vertex shader (same as ui.frag)
layout(location = 0) in vec2 texCoords;
layout(location = 1) in vec4 vertexColor;

//Output
layout(location = 0) out vec4 outColor;

//Unified UI Material (same as ui.frag)
layout(set = 1, binding = 0) uniform UIMaterial {
    vec4 tint;
    float opacity;
    int textureMode;
    int roundedCorners;
    float cornerRadius;
    float sdfThreshold;
    float outlineWidth;
    vec4 outlineColor;
    float sdfRange;
    float reserved1;
    float reserved2;
} uiMaterial;

//SDF texture atlas (same binding as ui.frag)
layout(set = 1, binding = 1) uniform sampler2D uiTexture;

void main() {
    //1. Sample distance field from texture
    float distance = texture(uiTexture, texCoords).r;

    //2. Calculate smoothing based on screen-space derivatives
    float smoothWidth = fwidth(distance);

    //3. Convert distance to alpha using smoothstep
    float alpha = smoothstep(uiMaterial.sdfThreshold - smoothWidth,
                           uiMaterial.sdfThreshold + smoothWidth, distance);

    //4. Apply text color and outline effects
    vec3 textColor = uiMaterial.tint.rgb * vertexColor.rgb;
    float finalAlpha = alpha * uiMaterial.tint.a * vertexColor.a;

    //5. Output final color
    outColor = vec4(textColor, finalAlpha);
}