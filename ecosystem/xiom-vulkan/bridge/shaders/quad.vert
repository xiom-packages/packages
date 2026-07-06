#version 450

layout(push_constant) uniform PC {
    vec4 rect;   // cx, cy, hw, hh
    vec4 color;
} pc;

layout(location = 0) out vec3 fragColor;

void main() {
    // Two triangles (6 indices) covering [cx-hw, cx+hw] x [cy-hh, cy+hh]
    // CCW winding in NDC y-down.
    float cx = pc.rect.x, cy = pc.rect.y;
    float hw = pc.rect.z, hh = pc.rect.w;

    float x = cx + (gl_VertexIndex == 0 || gl_VertexIndex == 3 || gl_VertexIndex == 5 ? -hw :
                    gl_VertexIndex == 1 || gl_VertexIndex == 2 || gl_VertexIndex == 4 ?  hw : 0.0);
    float y = cy + (gl_VertexIndex == 0 || gl_VertexIndex == 1 || gl_VertexIndex == 3 ? -hh :
                    gl_VertexIndex == 2 || gl_VertexIndex == 4 || gl_VertexIndex == 5 ?  hh : 0.0);

    gl_Position = vec4(x, y, 0.0, 1.0);
    fragColor = pc.color.rgb;
}
