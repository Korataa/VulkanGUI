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
    float distance = uiMaterial.reserved2 > 0.5 ? median3(sampleValue.rgb) : sampleValue.r;

    // Compute screen-space pixel range for SDF smoothing; ensure a reasonable minimum
    float pxRange = computeScreenPxRange(texCoords, uiMaterial.sdfRange);
    pxRange = max(pxRange, 4.0);

    float edge = uiMaterial.sdfThreshold;
    float sharpness = clamp(pxRange * 0.25, 0.0, 0.1);

    // Fill and outline
    float fillAlpha = clamp(pxRange * (distance - (edge - sharpness)) + 0.5, 0.0, 1.0);
    float outlineAlpha = clamp(pxRange * (distance - (edge - uiMaterial.outlineWidth)) + 0.5, 0.0, 1.0);
    float outlineRegion = clamp(outlineAlpha - fillAlpha, 0.0, 1.0);

    // Glow effect
    float glow = smoothstep(edge - uiMaterial.glowWidth, edge, distance);

    // Drop shadow effect
    vec2 shadowUV = texCoords + uiMaterial.shadowOffset;
    vec4 shadowSample = texture(uiTexture, shadowUV);
    float shadowDist = uiMaterial.reserved2 > 0.5 ? median3(shadowSample.rgb) : shadowSample.r;
    float shadowPxRange = computeScreenPxRange(shadowUV, uiMaterial.sdfRange);
    float shadowAlpha = clamp(shadowPxRange * (shadowDist - (edge - sharpness)) + 0.5, 0.0, 1.0);


    // Normalize CPU-side colors (Color is stored 0..255 on the CPU)
    vec3 vertexCol = vertexColor.rgb / 255.0;
    float vertexA = vertexColor.a / 255.0;

    vec3 tint = uiMaterial.tint.rgb / 255.0;
    float tintA = uiMaterial.tint.a / 255.0;
    vec3 outlineCol = uiMaterial.outlineColor.rgb / 255.0;
    vec3 glowCol = uiMaterial.glowColor.rgb / 255.0;
    vec3 shadowCol = uiMaterial.shadowColor.rgb / 255.0;

    // Compose base color (vertex color modulated by material tint)
    vec3 baseColor = vertexCol * tint;

    // Shadow sits behind the glyph; shadowAlpha computed from a displaced sample
    float shadowContribution = shadowAlpha * (1.0 - fillAlpha);

    // Glow contributes outside the glyph; scaled down where the fill exists
    float glowContribution = glow * (1.0 - fillAlpha);

    // Outline region where outline exists outside the fill
    float outlineContribution = outlineRegion;

    // Final alpha should reflect any visible components (fill or outline)
    float finalMask = max(fillAlpha, outlineContribution);
    float finalAlpha = finalMask * vertexA * uiMaterial.opacity * tintA;

    // Accumulate color layers: shadow (behind), outline, fill, then glow (additive-ish)
    vec3 color = vec3(0.0);
    color += shadowCol * shadowContribution * uiMaterial.opacity;
    color += outlineCol * outlineContribution * uiMaterial.opacity;
    color += baseColor * fillAlpha * uiMaterial.opacity;
    color += glowCol * glowContribution * uiMaterial.opacity * 0.5; // tone down glow a bit

    color = clamp(color, 0.0, 1.0);

    outColor = vec4(color, finalAlpha);
}