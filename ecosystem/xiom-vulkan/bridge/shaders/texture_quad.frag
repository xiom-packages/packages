#version 450

layout(push_constant) uniform PushConstants {
    float cx;
    float cy;
    float hw;
    float hh;
    float r;
    float g;
    float b;
    float a;
} pc;

layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 outColor;

layout(binding = 1) uniform sampler2D texSampler;

void main() {
    vec4 texColor = texture(texSampler, uv);
    outColor = texColor * vec4(pc.r, pc.g, pc.b, pc.a);
}
