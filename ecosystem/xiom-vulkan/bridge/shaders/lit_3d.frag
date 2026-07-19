#version 450

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec4 light_dir;
    vec4 light_color;
} pc;

layout(location = 0) in vec3 fragNormal;
layout(location = 1) in vec3 fragWorldPos;
layout(location = 0) out vec4 outColor;

void main() {
    vec3 N = normalize(fragNormal);
    vec3 L = normalize(-pc.light_dir.xyz);
    float NdotL = max(dot(N, L), 0.0);
    vec3 ambient = vec3(0.15, 0.15, 0.18) * pc.light_dir.w;
    vec3 diffuse = pc.light_color.rgb * pc.light_color.w * NdotL;
    vec3 lit = ambient + diffuse;
    outColor = vec4(lit, 1.0);
}
