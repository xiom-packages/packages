// XIOM -- OpenGL 4.6 Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Pure SPEC package -- all FFI calls return Err until the C bridge is linked.
// Wraps OpenGL 4.6 Core Profile. Extension loader (glad) bundled at build time.
// Depends on: xiom.glfw (window creation), glad (extension loader).
//
// Real C bridge will be linked after xiom.ffi matures.
// Compile (when bridge ready):
//   xiom --link opengl32 opengl.xi glad.c opengl_bridge.c

module xiom.opengl

// -- Opaque handle types ----------------------------------------------------

pub type GlShader = Int;
pub type GlProgram = Int;
pub type GlBuffer = Int;
pub type GlVao = Int;
pub type GlTexture = Int;

// -- GLenum Constants -------------------------------------------------------

// Shader types
pub const GL_VERTEX_SHADER: Int = 35633;
pub const GL_FRAGMENT_SHADER: Int = 35632;
pub const GL_GEOMETRY_SHADER: Int = 36313;
pub const GL_COMPUTE_SHADER: Int = 37305;
pub const GL_TESS_CONTROL_SHADER: Int = 36488;
pub const GL_TESS_EVALUATION_SHADER: Int = 36487;

// Shader / program status
pub const GL_COMPILE_STATUS: Int = 35713;
pub const GL_LINK_STATUS: Int = 35714;
pub const GL_VALIDATE_STATUS: Int = 35715;
pub const GL_INFO_LOG_LENGTH: Int = 35716;
pub const GL_DELETE_STATUS: Int = 35712;

// Buffer targets
pub const GL_ARRAY_BUFFER: Int = 34962;
pub const GL_ELEMENT_ARRAY_BUFFER: Int = 34963;
pub const GL_UNIFORM_BUFFER: Int = 35345;
pub const GL_SHADER_STORAGE_BUFFER: Int = 37074;
pub const GL_PIXEL_PACK_BUFFER: Int = 35051;
pub const GL_PIXEL_UNPACK_BUFFER: Int = 35052;
pub const GL_COPY_READ_BUFFER: Int = 36662;
pub const GL_COPY_WRITE_BUFFER: Int = 36663;

// Buffer usage
pub const GL_STREAM_DRAW: Int = 35040;
pub const GL_STATIC_DRAW: Int = 35044;
pub const GL_DYNAMIC_DRAW: Int = 35048;

// Draw modes
pub const GL_POINTS: Int = 0;
pub const GL_LINES: Int = 1;
pub const GL_LINE_STRIP: Int = 3;
pub const GL_LINE_LOOP: Int = 2;
pub const GL_TRIANGLES: Int = 4;
pub const GL_TRIANGLE_STRIP: Int = 5;
pub const GL_TRIANGLE_FAN: Int = 6;

// Clear masks
pub const GL_COLOR_BUFFER_BIT: Int = 16384;
pub const GL_DEPTH_BUFFER_BIT: Int = 256;
pub const GL_STENCIL_BUFFER_BIT: Int = 1024;

// Vertex attribute types
pub const GL_FLOAT: Int = 5126;
pub const GL_INT: Int = 5124;
pub const GL_UNSIGNED_INT: Int = 5125;
pub const GL_UNSIGNED_BYTE: Int = 5121;
pub const GL_UNSIGNED_SHORT: Int = 5123;
pub const GL_BYTE: Int = 5120;
pub const GL_SHORT: Int = 5122;

// Texture targets
pub const GL_TEXTURE_1D: Int = 3552;
pub const GL_TEXTURE_2D: Int = 3553;
pub const GL_TEXTURE_3D: Int = 32879;
pub const GL_TEXTURE_CUBE_MAP: Int = 34067;

// Texture formats
pub const GL_RED: Int = 6403;
pub const GL_RG: Int = 33319;
pub const GL_RGB: Int = 6407;
pub const GL_RGBA: Int = 6408;
pub const GL_DEPTH_COMPONENT: Int = 6402;
pub const GL_STENCIL_INDEX: Int = 6401;

// Internal texture formats
pub const GL_RGB8: Int = 32849;
pub const GL_RGBA8: Int = 32856;
pub const GL_SRGB8: Int = 35905;
pub const GL_SRGB8_ALPHA8: Int = 35907;
pub const GL_R16F: Int = 33325;
pub const GL_R32F: Int = 33326;
pub const GL_RG16F: Int = 33327;
pub const GL_RG32F: Int = 33328;
pub const GL_RGBA16F: Int = 34842;
pub const GL_RGBA32F: Int = 34836;
pub const GL_DEPTH_COMPONENT24: Int = 33190;
pub const GL_DEPTH_COMPONENT32F: Int = 36012;

// Texture parameters
pub const GL_TEXTURE_MIN_FILTER: Int = 10241;
pub const GL_TEXTURE_MAG_FILTER: Int = 10240;
pub const GL_TEXTURE_WRAP_S: Int = 10242;
pub const GL_TEXTURE_WRAP_T: Int = 10243;
pub const GL_TEXTURE_WRAP_R: Int = 32882;
pub const GL_TEXTURE_MAX_LEVEL: Int = 33485;

// Texture filter values
pub const GL_NEAREST: Int = 9728;
pub const GL_LINEAR: Int = 9729;
pub const GL_NEAREST_MIPMAP_NEAREST: Int = 9984;
pub const GL_LINEAR_MIPMAP_NEAREST: Int = 9985;
pub const GL_NEAREST_MIPMAP_LINEAR: Int = 9986;
pub const GL_LINEAR_MIPMAP_LINEAR: Int = 9987;

// Texture wrap values
pub const GL_REPEAT: Int = 10497;
pub const GL_MIRRORED_REPEAT: Int = 33648;
pub const GL_CLAMP_TO_EDGE: Int = 33071;
pub const GL_CLAMP_TO_BORDER: Int = 33069;

// Booleans
pub const GL_FALSE: Int = 0;
pub const GL_TRUE: Int = 1;

// Error
pub const GL_NO_ERROR: Int = 0;
pub const GL_INVALID_ENUM: Int = 1280;
pub const GL_INVALID_VALUE: Int = 1281;
pub const GL_INVALID_OPERATION: Int = 1282;
pub const GL_OUT_OF_MEMORY: Int = 1285;

// Uniform element types for glDrawElements
pub const GL_UNSIGNED_INT_INDEX: Int = 5125;
pub const GL_UNSIGNED_SHORT_INDEX: Int = 5123;
pub const GL_UNSIGNED_BYTE_INDEX: Int = 5121;

// ===========================================================================
// extern "C" -- Raw OpenGL 4.6 Core Profile Declarations (36 functions)
// ===========================================================================
// These map 1:1 to the system OpenGL library via glad/gl3w loader.
// Pointers are typed as Int for SPEC phase; cast to concrete types when
// the C bridge is linked.

extern "C" {
  // -- Shader compilation --------------------------------------------------
  fn glCreateShader(shaderType: Int) -> Int;
  fn glShaderSource(shader: Int, count: Int, source: Int, length: Int);
  fn glCompileShader(shader: Int);
  fn glGetShaderiv(shader: Int, pname: Int, params: Int);
  fn glGetShaderInfoLog(shader: Int, bufSize: Int, length: Int, infoLog: Int);
  fn glDeleteShader(shader: Int);

  // -- Program linking -----------------------------------------------------
  fn glCreateProgram() -> Int;
  fn glAttachShader(program: Int, shader: Int);
  fn glLinkProgram(program: Int);
  fn glGetProgramiv(program: Int, pname: Int, params: Int);
  fn glGetProgramInfoLog(program: Int, bufSize: Int, length: Int, infoLog: Int);
  fn glUseProgram(program: Int);
  fn glDeleteProgram(program: Int);

  // -- Buffer objects ------------------------------------------------------
  fn glGenBuffers(n: Int, buffers: Int);
  fn glBindBuffer(target: Int, buffer: Int);
  fn glBufferData(target: Int, size: Int, data: Int, usage: Int);
  fn glDeleteBuffers(n: Int, buffers: Int);

  // -- Vertex array objects ------------------------------------------------
  fn glGenVertexArrays(n: Int, arrays: Int);
  fn glBindVertexArray(array: Int);
  fn glDeleteVertexArrays(n: Int, arrays: Int);

  // -- Vertex attributes ---------------------------------------------------
  fn glEnableVertexAttribArray(index: Int);
  fn glVertexAttribPointer(index: Int, size: Int, typ: Int, normalized: Int, stride: Int, pointer: Int);
  fn glDisableVertexAttribArray(index: Int);

  // -- Drawing -------------------------------------------------------------
  fn glDrawArrays(mode: Int, first: Int, count: Int);
  fn glDrawElements(mode: Int, count: Int, typ: Int, indices: Int);
  fn glClear(mask: Int);
  fn glClearColor(red: Float32, green: Float32, blue: Float32, alpha: Float32);
  fn glViewport(x: Int, y: Int, width: Int, height: Int);

  // -- Textures ------------------------------------------------------------
  fn glGenTextures(n: Int, textures: Int);
  fn glBindTexture(target: Int, texture: Int);
  fn glTexImage2D(target: Int, level: Int, internalformat: Int, width: Int, height: Int, border: Int, format: Int, typ: Int, pixels: Int);
  fn glTexParameteri(target: Int, pname: Int, param: Int);
  fn glDeleteTextures(n: Int, textures: Int);

  // -- Uniforms ------------------------------------------------------------
  fn glGetUniformLocation(program: Int, name: Int) -> Int;
  fn glUniform1i(location: Int, v0: Int);
  fn glUniform1f(location: Int, v0: Float32);
  fn glUniformMatrix4fv(location: Int, count: Int, transpose: Int, value: Int);
}

// ===========================================================================
// Safe Wrappers: Shader
// ===========================================================================

pub fn gl_create_shader(typ: Int) -> Result[GlShader, Str]
  requires: typ == GL_VERTEX_SHADER || typ == GL_FRAGMENT_SHADER || typ == GL_GEOMETRY_SHADER || typ == GL_COMPUTE_SHADER || typ == GL_TESS_CONTROL_SHADER || typ == GL_TESS_EVALUATION_SHADER
{
  return Err("gl_create_shader: C bridge not yet linked -- xiom.opengl is in SPEC phase");
}

pub fn gl_shader_source(shader: GlShader, source: Str)
  requires: shader != 0
  requires: source.len() > 0
{
}

pub fn gl_compile_shader(shader: GlShader) -> Result[Unit, Str]
  requires: shader != 0
{
  return Err("gl_compile_shader: C bridge not yet linked -- xiom.opengl is in SPEC phase");
}

pub fn gl_delete_shader(shader: GlShader)
  requires: shader != 0
{
}

// ===========================================================================
// Safe Wrappers: Program
// ===========================================================================

pub fn gl_create_program() -> Result[GlProgram, Str]
{
  return Err("gl_create_program: C bridge not yet linked -- xiom.opengl is in SPEC phase");
}

pub fn gl_attach_shader(prog: GlProgram, shader: GlShader)
  requires: prog != 0
  requires: shader != 0
{
}

pub fn gl_link_program(prog: GlProgram) -> Result[Unit, Str]
  requires: prog != 0
{
  return Err("gl_link_program: C bridge not yet linked -- xiom.opengl is in SPEC phase");
}

pub fn gl_use_program(prog: GlProgram)
  requires: prog != 0
{
}

pub fn gl_delete_program(prog: GlProgram)
  requires: prog != 0
{
}

// ===========================================================================
// Safe Wrappers: Buffer
// ===========================================================================

pub fn gl_gen_buffer() -> Result[GlBuffer, Str]
{
  return Err("gl_gen_buffer: C bridge not yet linked -- xiom.opengl is in SPEC phase");
}

pub fn gl_bind_buffer(target: Int, buf: GlBuffer)
  requires: target == GL_ARRAY_BUFFER || target == GL_ELEMENT_ARRAY_BUFFER || target == GL_UNIFORM_BUFFER || target == GL_SHADER_STORAGE_BUFFER || target == GL_PIXEL_PACK_BUFFER || target == GL_PIXEL_UNPACK_BUFFER || target == GL_COPY_READ_BUFFER || target == GL_COPY_WRITE_BUFFER
  requires: buf != 0
{
}

pub fn gl_buffer_data(target: Int, data: &Vec[Float32], usage: Int)
  requires: target == GL_ARRAY_BUFFER || target == GL_ELEMENT_ARRAY_BUFFER || target == GL_UNIFORM_BUFFER || target == GL_SHADER_STORAGE_BUFFER
  requires: data.len() > 0
  requires: usage == GL_STREAM_DRAW || usage == GL_STATIC_DRAW || usage == GL_DYNAMIC_DRAW
{
}

pub fn gl_delete_buffer(buf: GlBuffer)
  requires: buf != 0
{
}

// ===========================================================================
// Safe Wrappers: Vertex Array Object
// ===========================================================================

pub fn gl_gen_vertex_array() -> Result[GlVao, Str]
{
  return Err("gl_gen_vertex_array: C bridge not yet linked -- xiom.opengl is in SPEC phase");
}

pub fn gl_bind_vertex_array(vao: GlVao)
  requires: vao != 0
{
}

pub fn gl_delete_vertex_array(vao: GlVao)
  requires: vao != 0
{
}

// ===========================================================================
// Safe Wrappers: Vertex Attributes
// ===========================================================================

pub fn gl_enable_vertex_attrib_array(index: Int)
  requires: index >= 0
  requires: index <= 15
{
}

pub fn gl_vertex_attrib_pointer(index: Int, size: Int, typ: Int, normalized: Bool, stride: Int, offset: Int)
  requires: index >= 0
  requires: index <= 15
  requires: size >= 1
  requires: size <= 4
  requires: typ == GL_FLOAT || typ == GL_INT || typ == GL_UNSIGNED_INT || typ == GL_UNSIGNED_BYTE || typ == GL_UNSIGNED_SHORT || typ == GL_BYTE || typ == GL_SHORT
  requires: stride >= 0
  requires: offset >= 0
{
}

pub fn gl_disable_vertex_attrib_array(index: Int)
  requires: index >= 0
  requires: index <= 15
{
}

// ===========================================================================
// Safe Wrappers: Drawing
// ===========================================================================

pub fn gl_clear(r: Float32, g: Float32, b: Float32, a: Float32)
{
}

pub fn gl_clear_color(r: Float32, g: Float32, b: Float32, a: Float32)
  requires: r >= 0.0 && r <= 1.0
  requires: g >= 0.0 && g <= 1.0
  requires: b >= 0.0 && b <= 1.0
  requires: a >= 0.0 && a <= 1.0
{
}

pub fn gl_clear_depth(d: Float32)
  requires: d >= 0.0 && d <= 1.0
{
}

pub fn gl_draw_arrays(mode: Int, first: Int, count: Int)
  requires: mode == GL_POINTS || mode == GL_LINES || mode == GL_LINE_STRIP || mode == GL_LINE_LOOP || mode == GL_TRIANGLES || mode == GL_TRIANGLE_STRIP || mode == GL_TRIANGLE_FAN
  requires: first >= 0
  requires: count >= 0
{
}

pub fn gl_draw_elements(mode: Int, count: Int, typ: Int, offset: Int)
  requires: mode == GL_POINTS || mode == GL_LINES || mode == GL_LINE_STRIP || mode == GL_LINE_LOOP || mode == GL_TRIANGLES || mode == GL_TRIANGLE_STRIP || mode == GL_TRIANGLE_FAN
  requires: count >= 0
  requires: typ == GL_UNSIGNED_INT || typ == GL_UNSIGNED_SHORT || typ == GL_UNSIGNED_BYTE
  requires: offset >= 0
{
}

pub fn gl_viewport(x: Int, y: Int, w: Int, h: Int)
  requires: w >= 0
  requires: h >= 0
{
}

// ===========================================================================
// Safe Wrappers: Textures
// ===========================================================================

pub fn gl_gen_texture() -> Result[GlTexture, Str]
{
  return Err("gl_gen_texture: C bridge not yet linked -- xiom.opengl is in SPEC phase");
}

pub fn gl_bind_texture(target: Int, tex: GlTexture)
  requires: target == GL_TEXTURE_1D || target == GL_TEXTURE_2D || target == GL_TEXTURE_3D || target == GL_TEXTURE_CUBE_MAP
  requires: tex != 0
{
}

pub fn gl_tex_image2d(target: Int, level: Int, internal_fmt: Int, w: Int, h: Int, fmt: Int, typ: Int, data: &Vec[UInt8])
  requires: target == GL_TEXTURE_2D
  requires: level >= 0
  requires: w > 0
  requires: h > 0
  requires: data.len() > 0
{
}

pub fn gl_tex_parameteri(target: Int, pname: Int, param: Int)
  requires: target == GL_TEXTURE_1D || target == GL_TEXTURE_2D || target == GL_TEXTURE_3D || target == GL_TEXTURE_CUBE_MAP
  requires: pname == GL_TEXTURE_MIN_FILTER || pname == GL_TEXTURE_MAG_FILTER || pname == GL_TEXTURE_WRAP_S || pname == GL_TEXTURE_WRAP_T || pname == GL_TEXTURE_WRAP_R || pname == GL_TEXTURE_MAX_LEVEL
{
}

pub fn gl_delete_texture(tex: GlTexture)
  requires: tex != 0
{
}

// ===========================================================================
// Safe Wrappers: Uniforms
// ===========================================================================

pub fn gl_get_uniform_location(prog: GlProgram, name: Str) -> Int
  requires: prog != 0
  requires: name.len() > 0
{
  return -1;
}

pub fn gl_uniform1i(location: Int, val: Int)
  requires: location >= 0
{
}

pub fn gl_uniform1f(location: Int, val: Float32)
  requires: location >= 0
{
}

pub fn gl_uniform_matrix4fv(location: Int, count: Int, transpose: Bool, data: &Vec[Float32])
  requires: location >= 0
  requires: count >= 1
  requires: data.len() >= 16
{
}

// ===========================================================================
// Safe Wrappers: Context (bridge via glfw / WGL / GLX)
// ===========================================================================

pub fn gl_create_context(win: Int, major: Int, minor: Int) -> Result[Int, Str]
  requires: win != 0
  requires: major >= 1
  requires: minor >= 0
{
  return Err("gl_create_context: C bridge not yet linked -- xiom.opengl is in SPEC phase");
}

pub fn gl_make_current(ctx: Int)
  requires: ctx != 0
{
}

pub fn gl_swap_buffers(win: Int)
  requires: win != 0
{
}

pub fn gl_get_error() -> Int
{
  return GL_NO_ERROR;
}
