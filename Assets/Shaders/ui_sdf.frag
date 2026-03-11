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
    float pad0; // std140 alignment before outlineColor
    vec4 outlineColor;
    float sdfRange;
    float reserved1;
    float reserved2;
    float pad1; // struct size alignment padding
    vec4 glowColor;
    float glowWidth;
    float pad2;
    vec4 shadowColor;
    vec2 shadowOffset;
    float pad3;
    float pad4;
} uiMaterial;

//SDF texture atlas (same binding as ui.frag)
layout(set = 1, binding = 1) uniform sampler2D uiTexture;

float median3(vec3 v) {
    return max(min(v.r, v.g), min(max(v.r, v.g), v.b));
}

float computeScreenPxRange(vec2 uv, float pxRange) {
    vec2 atlasSize = vec2(textureSize(uiTexture, 0));
    vec2 unitRange = vec2(pxRange) / max(atlasSize, vec2(1.0));
    vec2 screenTexSize = vec2(1.0) / max(fwidth(uv), vec2(1e-6));
    return max(0.5 * dot(unitRange, screenTexSize), 1.0);
}

void main() {
    vec4 sampleValue = texture(uiTexture, texCoords);
    float distance = median3(sampleValue.rgb);

    float pxRange = computeScreenPxRange(texCoords, uiMaterial.sdfRange);

    float edge = 0.5;
    float sharpness = clamp(pxRange * 0.25, 0.0, 0.1);

    // Fill and outline
    float fillAlpha = clamp(pxRange * (distance - (edge - sharpness)) + 0.5, 0.0, 1.0);
    float outlineAlpha = clamp(pxRange * (distance - (edge - uiMaterial.outlineWidth)) + 0.5, 0.0, 1.0);
    float outlineRegion = clamp(outlineAlpha - fillAlpha, 0.0, 1.0);

    // Glow effect
    float glow = smoothstep(edge - uiMaterial.glowWidth, edge, distance);

    // Drop shadow effect
    vec2 shadowUV = texCoords + uiMaterial.shadowOffset;
    float shadowDist = median3(texture(uiTexture, shadowUV).rgb);
    float shadowPxRange = computeScreenPxRange(shadowUV, uiMaterial.sdfRange);
    float shadowAlpha = clamp(shadowPxRange * (shadowDist - (edge - sharpness)) + 0.5, 0.0, 1.0);

    vec3 fillColor = vertexColor.rgb;
    vec3 outlineColor = uiMaterial.outlineColor.rgb;

    vec3 color = outlineColor * outlineRegion + fillColor * fillAlpha;
    float alpha = max(fillAlpha, outlineRegion);

    // Add glow
    color = mix(color, uiMaterial.glowColor.rgb, glow * uiMaterial.glowColor.a);
    alpha = max(alpha, glow * uiMaterial.glowColor.a);

    // Add drop shadow (drawn behind text)
    color = mix(uiMaterial.shadowColor.rgb, color, alpha);
    alpha = max(alpha, shadowAlpha * uiMaterial.shadowColor.a);

    outColor = vec4(color * vertexColor.rgb, alpha * vertexColor.a);
    return;
}