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

layout(location = 0) out vec2 uv;

vec2 positions[6] = vec2[](
    vec2(-1.0, -1.0), vec2( 1.0, -1.0), vec2( 1.0,  1.0),
    vec2(-1.0, -1.0), vec2( 1.0,  1.0), vec2(-1.0,  1.0)
);

vec2 uvs[6] = vec2[](
    vec2(0.0, 1.0), vec2(1.0, 1.0), vec2(1.0, 0.0),
    vec2(0.0, 1.0), vec2(1.0, 0.0), vec2(0.0, 0.0)
);

void main() {
    vec2 pos = positions[gl_VertexIndex];
    vec2 translated = vec2(pc.cx + pos.x * pc.hw, pc.cy + pos.y * pc.hh);
    gl_Position = vec4(translated, 0.0, 1.0);
    uv = uvs[gl_VertexIndex];
}
