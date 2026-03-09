#version 450

//Input from vertex shader (same as ui.frag)
layout(location = 0) in vec2 texCoords;
layout(location = 1) in vec4 vertexColor;

//Output
layout(location = 0) out vec4 outColor;

//SDF Material properties
layout(set = 1, binding = 0) uniform SDFMaterial {
    vec4 textColor;     //Base text color
    float sdfRange;     //Distance field range (usually 4-8)
    float outlineWidth; //Outline thickness
    vec4 outlineColor;  //Outline Color
    float smoothing;    //Additional smoothing factor
} sdfMaterial;

//SDF texture atlas
layout(set = 1, binding = 1) uniform sampler2D sdfTexture;

void main() {
    //TODO: Implement SDF rendering logic

    //1. Sample distance field from texture
    float distance = texture(sdfTexture, texCoords).r;

    //2. Calculate smoothing based on screen-space derivatives
    float smoothWidth = fwidth(distance);

    //3. Convert distance to alpha using smoothstep
    float alpha = smoothstep(0.5 - smoothWidth, 0.5 + smoothWidth, distance);


    //4. Apply text color and outline effects
    vec3 textColor = sdfMaterial.textColor.rgb * vertexColor.rgb;
    float finalAlpha = alpha * sdfMaterial.textColor.a * vertexColor.a;

    //5. Output final color
    outColor = vec4(textColor, finalAlpha);
}