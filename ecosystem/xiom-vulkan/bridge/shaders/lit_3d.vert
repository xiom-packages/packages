#version 450

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec4 light_dir;   // xyz = direction, w = ambient
    vec4 light_color; // xyz = diffuse color, w = intensity
} pc;

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 0) out vec3 fragNormal;
layout(location = 1) out vec3 fragWorldPos;

void main() {
    vec4 worldPos = vec4(inPosition, 1.0);
    gl_Position = pc.mvp * worldPos;
    fragNormal = inNormal;
    fragWorldPos = worldPos.xyz;
}
