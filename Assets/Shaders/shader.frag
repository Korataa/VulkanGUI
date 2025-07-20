#version 450 core

layout(location = 0) in vec3 fragPos;
layout(location = 1) in vec3 normal;

layout(location = 0) out vec4 outColor;

//light properties
layout(set = 0, finding = 1) uniform Light {
    vec3 lightPos;
    vec3 lightColor;
} light;

layout(set = 0, binding = 2) uniform Camera {
    vec3 viewPos;
} camera;

void main() {
    //normalize input normal
    vec3 norm = normalize(normal);

    //calculate light direction
    vec3 lightDir = normalize(light.lightPos - fragPos);

    //diffuse shading
    float diff = max(dot(norm, lightDir), 0.0);

    //ambient term
    vec3 ambient = 0.1 * light.lightColor;

    //diffuse term
    vec3 diffuse = diff * light.lightColor;

    //Simple phong-like color: ambient + diffuse
    vec3 result = ambient + diffuse;

    outColor = vec4(result, 1.0)
}