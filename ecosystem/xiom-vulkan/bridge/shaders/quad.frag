#version 450

layout(push_constant) uniform PC {
    vec4 rect;
    vec4 color;
} pc;

layout(location = 0) in vec3 fragColor;
layout(location = 0) out vec4 outColor;

void main() {
    outColor = vec4(fragColor, 1.0);
}
