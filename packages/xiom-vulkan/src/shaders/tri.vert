#version 450
// xiom.vulkan RHI triangle -- vertex positions from gl_VertexIndex (no
// vertex buffers).  CCW triangle: bottom-left, bottom-right, top-center.
void main() {
  vec2 verts[3] = vec2[3](vec2(-0.8, -0.8), vec2(0.8, -0.8), vec2(0.0, 0.8));
  gl_Position = vec4(verts[gl_VertexIndex], 0.0, 1.0);
}
