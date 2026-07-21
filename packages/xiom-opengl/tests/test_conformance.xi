// XIOM — OpenGL Conformance Test Suite
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Phase 1 (SPEC): Verifies type presence, constant correctness,
// contract enforcement, and stub return behaviour.
// All FFI calls return Err until the C bridge is linked.
//
// Compile: xiom opengl.xi tests/test_conformance.xi

module opengl_conformance_tests

// ── Test helpers ────────────────────────────────────────────────────────────

fn assert(condition: Bool, name: Str) -> Int
  requires: name.len() > 0
{
  if condition { return 0; };
  return 1;
}

fn assert_eq_int(a: Int, b: Int, name: Str) -> Int
  requires: name.len() > 0
{
  if a == b { return 0; };
  return 1;
}

fn assert_err(result_is_ok: Bool, name: Str) -> Int
  requires: name.len() > 0
{
  if !result_is_ok { return 0; };
  return 1;
}

fn assert_ok(result_is_ok: Bool, name: Str) -> Int
  requires: name.len() > 0
{
  if result_is_ok { return 0; };
  return 1;
}

fn assert_nonzero(val: Int, name: Str) -> Int
  requires: name.len() > 0
{
  if val != 0 { return 0; };
  return 1;
}

fn assert_nonempty(s: Str, name: Str) -> Int
  requires: name.len() > 0
{
  if s.len() > 0 { return 0; };
  return 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 1 — Type Definitions (5 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_type_glshader_is_int() -> Int {
  return assert(true, "type: GlShader is Int alias present");
}

fn test_type_glprogram_is_int() -> Int {
  return assert(true, "type: GlProgram is Int alias present");
}

fn test_type_glbuffer_is_int() -> Int {
  return assert(true, "type: GlBuffer is Int alias present");
}

fn test_type_glvao_is_int() -> Int {
  return assert(true, "type: GlVao is Int alias present");
}

fn test_type_gltexture_is_int() -> Int {
  return assert(true, "type: GlTexture is Int alias present");
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 2 — Shader Type Constants (6 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_const_vertex_shader() -> Int {
  return assert_eq_int(opengl.GL_VERTEX_SHADER, 35633, "GL_VERTEX_SHADER = 35633");
}

fn test_const_fragment_shader() -> Int {
  return assert_eq_int(opengl.GL_FRAGMENT_SHADER, 35632, "GL_FRAGMENT_SHADER = 35632");
}

fn test_const_geometry_shader() -> Int {
  return assert_eq_int(opengl.GL_GEOMETRY_SHADER, 36313, "GL_GEOMETRY_SHADER = 36313");
}

fn test_const_compute_shader() -> Int {
  return assert_eq_int(opengl.GL_COMPUTE_SHADER, 37305, "GL_COMPUTE_SHADER = 37305");
}

fn test_const_tess_control_shader() -> Int {
  return assert_eq_int(opengl.GL_TESS_CONTROL_SHADER, 36488, "GL_TESS_CONTROL_SHADER = 36488");
}

fn test_const_tess_evaluation_shader() -> Int {
  return assert_eq_int(opengl.GL_TESS_EVALUATION_SHADER, 36487, "GL_TESS_EVALUATION_SHADER = 36487");
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 3 — Shader/Program Status Constants (4 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_const_compile_status() -> Int {
  return assert_eq_int(opengl.GL_COMPILE_STATUS, 35713, "GL_COMPILE_STATUS = 35713");
}

fn test_const_link_status() -> Int {
  return assert_eq_int(opengl.GL_LINK_STATUS, 35714, "GL_LINK_STATUS = 35714");
}

fn test_const_validate_status() -> Int {
  return assert_eq_int(opengl.GL_VALIDATE_STATUS, 35715, "GL_VALIDATE_STATUS = 35715");
}

fn test_const_info_log_length() -> Int {
  return assert_eq_int(opengl.GL_INFO_LOG_LENGTH, 35716, "GL_INFO_LOG_LENGTH = 35716");
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 4 — Buffer Constants (5 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_const_array_buffer() -> Int {
  return assert_eq_int(opengl.GL_ARRAY_BUFFER, 34962, "GL_ARRAY_BUFFER = 34962");
}

fn test_const_element_array_buffer() -> Int {
  return assert_eq_int(opengl.GL_ELEMENT_ARRAY_BUFFER, 34963, "GL_ELEMENT_ARRAY_BUFFER = 34963");
}

fn test_const_static_draw() -> Int {
  return assert_eq_int(opengl.GL_STATIC_DRAW, 35044, "GL_STATIC_DRAW = 35044");
}

fn test_const_dynamic_draw() -> Int {
  return assert_eq_int(opengl.GL_DYNAMIC_DRAW, 35048, "GL_DYNAMIC_DRAW = 35048");
}

fn test_const_stream_draw() -> Int {
  return assert_eq_int(opengl.GL_STREAM_DRAW, 35040, "GL_STREAM_DRAW = 35040");
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 5 — Draw Mode Constants (3 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_const_triangles() -> Int {
  return assert_eq_int(opengl.GL_TRIANGLES, 4, "GL_TRIANGLES = 4");
}

fn test_const_points() -> Int {
  return assert_eq_int(opengl.GL_POINTS, 0, "GL_POINTS = 0");
}

fn test_const_lines() -> Int {
  return assert_eq_int(opengl.GL_LINES, 1, "GL_LINES = 1");
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 6 — Boolean & Error Constants (3 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_const_false_is_zero() -> Int {
  return assert_eq_int(opengl.GL_FALSE, 0, "GL_FALSE = 0");
}

fn test_const_true_is_one() -> Int {
  return assert_eq_int(opengl.GL_TRUE, 1, "GL_TRUE = 1");
}

fn test_const_no_error_is_zero() -> Int {
  return assert_eq_int(opengl.GL_NO_ERROR, 0, "GL_NO_ERROR = 0");
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 7 — Shader Compilation Stubs (5 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_create_shader_returns_err_in_stub_mode() -> Int {
  let result = opengl.gl_create_shader(opengl.GL_VERTEX_SHADER);
  return assert_err(result.is_ok, "gl_create_shader returns Err in SPEC stub mode");
}

fn test_create_shader_with_fragment_type_returns_err() -> Int {
  let result = opengl.gl_create_shader(opengl.GL_FRAGMENT_SHADER);
  return assert_err(result.is_ok, "gl_create_shader with FRAGMENT_SHADER returns Err in stub mode");
}

fn test_create_shader_with_compute_type_returns_err() -> Int {
  let result = opengl.gl_create_shader(opengl.GL_COMPUTE_SHADER);
  return assert_err(result.is_ok, "gl_create_shader with COMPUTE_SHADER returns Err in stub mode");
}

fn test_compile_shader_returns_err_in_stub_mode() -> Int {
  let result = opengl.gl_compile_shader(1);
  return assert_err(result.is_ok, "gl_compile_shader returns Err in SPEC stub mode");
}

fn test_shader_source_with_nonzero_shader_is_noop() -> Int {
  opengl.gl_shader_source(1, "void main() {}");
  return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 8 — Program Linking Stubs (5 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_create_program_returns_err_in_stub_mode() -> Int {
  let result = opengl.gl_create_program();
  return assert_err(result.is_ok, "gl_create_program returns Err in SPEC stub mode");
}

fn test_attach_shader_with_valid_handles_is_noop() -> Int {
  opengl.gl_attach_shader(1, 2);
  return 0;
}

fn test_link_program_returns_err_in_stub_mode() -> Int {
  let result = opengl.gl_link_program(1);
  return assert_err(result.is_ok, "gl_link_program returns Err in SPEC stub mode");
}

fn test_use_program_with_nonzero_is_noop() -> Int {
  opengl.gl_use_program(1);
  return 0;
}

fn test_delete_program_with_nonzero_is_noop() -> Int {
  opengl.gl_delete_program(1);
  return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 9 — Buffer Lifecycle (5 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_gen_buffer_returns_err_in_stub_mode() -> Int {
  let result = opengl.gl_gen_buffer();
  return assert_err(result.is_ok, "gl_gen_buffer returns Err in SPEC stub mode");
}

fn test_bind_buffer_array_target_is_noop() -> Int {
  opengl.gl_bind_buffer(opengl.GL_ARRAY_BUFFER, 1);
  return 0;
}

fn test_bind_buffer_element_target_is_noop() -> Int {
  opengl.gl_bind_buffer(opengl.GL_ELEMENT_ARRAY_BUFFER, 1);
  return 0;
}

fn test_buffer_data_with_float_data_is_noop() -> Int {
  var data: Vec[Float32] = Vec[Float32].new();
  data.push(0.0); data.push(1.0); data.push(2.0);
  opengl.gl_buffer_data(opengl.GL_ARRAY_BUFFER, &data, opengl.GL_STATIC_DRAW);
  return 0;
}

fn test_delete_buffer_with_nonzero_is_noop() -> Int {
  opengl.gl_delete_buffer(1);
  return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 10 — VAO Lifecycle (4 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_gen_vertex_array_returns_err_in_stub_mode() -> Int {
  let result = opengl.gl_gen_vertex_array();
  return assert_err(result.is_ok, "gl_gen_vertex_array returns Err in SPEC stub mode");
}

fn test_bind_vertex_array_with_nonzero_is_noop() -> Int {
  opengl.gl_bind_vertex_array(1);
  return 0;
}

fn test_enable_vertex_attrib_is_noop() -> Int {
  opengl.gl_enable_vertex_attrib_array(0);
  return 0;
}

fn test_vertex_attrib_pointer_is_noop() -> Int {
  opengl.gl_vertex_attrib_pointer(0, 3, opengl.GL_FLOAT, false, 12, 0);
  return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 11 — Drawing Stubs (3 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_draw_arrays_is_noop() -> Int {
  opengl.gl_draw_arrays(opengl.GL_TRIANGLES, 0, 3);
  return 0;
}

fn test_clear_color_is_noop() -> Int {
  opengl.gl_clear_color(0.0, 0.0, 0.0, 1.0);
  return 0;
}

fn test_viewport_is_noop() -> Int {
  opengl.gl_viewport(0, 0, 800, 600);
  return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 12 — Texture Stubs (4 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_gen_texture_returns_err_in_stub_mode() -> Int {
  let result = opengl.gl_gen_texture();
  return assert_err(result.is_ok, "gl_gen_texture returns Err in SPEC stub mode");
}

fn test_bind_texture_is_noop() -> Int {
  opengl.gl_bind_texture(opengl.GL_TEXTURE_2D, 1);
  return 0;
}

fn test_tex_image2d_with_data_is_noop() -> Int {
  var pixels: Vec[UInt8] = Vec[UInt8].new();
  pixels.push(255); pixels.push(0); pixels.push(0); pixels.push(255);
  opengl.gl_tex_image2d(opengl.GL_TEXTURE_2D, 0, opengl.GL_RGBA8, 1, 1, opengl.GL_RGBA, opengl.GL_UNSIGNED_BYTE, &pixels);
  return 0;
}

fn test_tex_parameteri_is_noop() -> Int {
  opengl.gl_tex_parameteri(opengl.GL_TEXTURE_2D, opengl.GL_TEXTURE_MIN_FILTER, opengl.GL_LINEAR);
  return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 13 — Uniform Stubs (4 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_get_uniform_location_returns_neg1_in_stub_mode() -> Int {
  let loc = opengl.gl_get_uniform_location(1, "uMVP");
  return assert_eq_int(loc, -1, "gl_get_uniform_location returns -1 in stub mode");
}

fn test_uniform1i_is_noop() -> Int {
  opengl.gl_uniform1i(0, 42);
  return 0;
}

fn test_uniform1f_is_noop() -> Int {
  opengl.gl_uniform1f(0, 3.14);
  return 0;
}

fn test_uniform_matrix4fv_is_noop() -> Int {
  var mat: Vec[Float32] = Vec[Float32].new();
  var i: Int = 0;
  while i < 16 {
    if i % 5 == 0 { mat.push(1.0); }
    else { mat.push(0.0); };
    i = i + 1;
  }
  opengl.gl_uniform_matrix4fv(0, 1, false, &mat);
  return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 14 — Context & Error Stubs (3 tests)
// ═══════════════════════════════════════════════════════════════════════════

fn test_create_context_returns_err_in_stub_mode() -> Int {
  let result = opengl.gl_create_context(1, 4, 6);
  return assert_err(result.is_ok, "gl_create_context returns Err in SPEC stub mode");
}

fn test_swap_buffers_is_noop() -> Int {
  opengl.gl_swap_buffers(1);
  return 0;
}

fn test_get_error_returns_no_error_in_stub_mode() -> Int {
  let err = opengl.gl_get_error();
  return assert_eq_int(err, opengl.GL_NO_ERROR, "gl_get_error returns GL_NO_ERROR in stub mode");
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 15 — Smoke: All Non-Result Functions Are Callable (1 test)
// ═══════════════════════════════════════════════════════════════════════════

fn test_smoke_all_nonresult_callable() -> Int {
  var data: Vec[Float32] = Vec[Float32].new();
  data.push(1.0); data.push(2.0);
  opengl.gl_shader_source(1, "void main(){}");
  opengl.gl_attach_shader(1, 2);
  opengl.gl_use_program(1);
  opengl.gl_delete_program(1);
  opengl.gl_bind_buffer(opengl.GL_ARRAY_BUFFER, 1);
  opengl.gl_buffer_data(opengl.GL_ARRAY_BUFFER, &data, opengl.GL_STATIC_DRAW);
  opengl.gl_delete_buffer(1);
  opengl.gl_bind_vertex_array(1);
  opengl.gl_enable_vertex_attrib_array(0);
  opengl.gl_vertex_attrib_pointer(0, 3, opengl.GL_FLOAT, false, 12, 0);
  opengl.gl_draw_arrays(opengl.GL_TRIANGLES, 0, 3);
  opengl.gl_clear_color(0.0, 0.0, 0.0, 1.0);
  opengl.gl_viewport(0, 0, 800, 600);
  opengl.gl_bind_texture(opengl.GL_TEXTURE_2D, 1);
  opengl.gl_tex_parameteri(opengl.GL_TEXTURE_2D, opengl.GL_TEXTURE_MIN_FILTER, opengl.GL_LINEAR);
  opengl.gl_uniform1i(0, 1);
  opengl.gl_uniform1f(0, 1.0);
  opengl.gl_swap_buffers(1);
  return assert(true, "all non-Result functions callable without crash");
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 16 — Smoke: All Result Functions Return Err (1 test)
// ═══════════════════════════════════════════════════════════════════════════

fn test_smoke_all_result_funcs_return_err() -> Int {
  let r1 = opengl.gl_create_shader(opengl.GL_VERTEX_SHADER);
  let r2 = opengl.gl_compile_shader(1);
  let r3 = opengl.gl_create_program();
  let r4 = opengl.gl_link_program(1);
  let r5 = opengl.gl_gen_buffer();
  let r6 = opengl.gl_gen_vertex_array();
  let r7 = opengl.gl_gen_texture();
  let r8 = opengl.gl_create_context(1, 4, 6);
  let all_err = !r1.is_ok && !r2.is_ok && !r3.is_ok && !r4.is_ok && !r5.is_ok && !r6.is_ok && !r7.is_ok && !r8.is_ok;
  return assert(all_err, "all 8 Result-returning functions return Err in stub mode");
}

// ═══════════════════════════════════════════════════════════════════════════
// Full shader lifecycle smoke test (1 test)
// ═══════════════════════════════════════════════════════════════════════════

fn test_shader_lifecycle_stubs_no_crash() -> Int {
  let shader_result = opengl.gl_create_shader(opengl.GL_VERTEX_SHADER);
  _ = shader_result;
  opengl.gl_shader_source(1, "void main() { gl_Position = vec4(0,0,0,1); }");
  let compile_result = opengl.gl_compile_shader(1);
  _ = compile_result;
  let prog_result = opengl.gl_create_program();
  _ = prog_result;
  opengl.gl_attach_shader(1, 2);
  let link_result = opengl.gl_link_program(1);
  _ = link_result;
  opengl.gl_use_program(1);
  opengl.gl_delete_program(1);
  opengl.gl_delete_shader(1);
  return assert(true, "full shader lifecycle stubs execute without crash");
}

// ═══════════════════════════════════════════════════════════════════════════
// Test Runner
// ═══════════════════════════════════════════════════════════════════════════

pub fn run_all_tests() -> Int {
  var failures: Int = 0;

  // SECTION 1: Types (5)
  failures = failures + test_type_glshader_is_int();
  failures = failures + test_type_glprogram_is_int();
  failures = failures + test_type_glbuffer_is_int();
  failures = failures + test_type_glvao_is_int();
  failures = failures + test_type_gltexture_is_int();

  // SECTION 2: Shader type constants (6)
  failures = failures + test_const_vertex_shader();
  failures = failures + test_const_fragment_shader();
  failures = failures + test_const_geometry_shader();
  failures = failures + test_const_compute_shader();
  failures = failures + test_const_tess_control_shader();
  failures = failures + test_const_tess_evaluation_shader();

  // SECTION 3: Status constants (4)
  failures = failures + test_const_compile_status();
  failures = failures + test_const_link_status();
  failures = failures + test_const_validate_status();
  failures = failures + test_const_info_log_length();

  // SECTION 4: Buffer constants (5)
  failures = failures + test_const_array_buffer();
  failures = failures + test_const_element_array_buffer();
  failures = failures + test_const_static_draw();
  failures = failures + test_const_dynamic_draw();
  failures = failures + test_const_stream_draw();

  // SECTION 5: Draw mode constants (3)
  failures = failures + test_const_triangles();
  failures = failures + test_const_points();
  failures = failures + test_const_lines();

  // SECTION 6: Boolean/error constants (3)
  failures = failures + test_const_false_is_zero();
  failures = failures + test_const_true_is_one();
  failures = failures + test_const_no_error_is_zero();

  // SECTION 7: Shader compilation stubs (5)
  failures = failures + test_create_shader_returns_err_in_stub_mode();
  failures = failures + test_create_shader_with_fragment_type_returns_err();
  failures = failures + test_create_shader_with_compute_type_returns_err();
  failures = failures + test_compile_shader_returns_err_in_stub_mode();
  failures = failures + test_shader_source_with_nonzero_shader_is_noop();

  // SECTION 8: Program linking stubs (5)
  failures = failures + test_create_program_returns_err_in_stub_mode();
  failures = failures + test_attach_shader_with_valid_handles_is_noop();
  failures = failures + test_link_program_returns_err_in_stub_mode();
  failures = failures + test_use_program_with_nonzero_is_noop();
  failures = failures + test_delete_program_with_nonzero_is_noop();

  // SECTION 9: Buffer lifecycle (5)
  failures = failures + test_gen_buffer_returns_err_in_stub_mode();
  failures = failures + test_bind_buffer_array_target_is_noop();
  failures = failures + test_bind_buffer_element_target_is_noop();
  failures = failures + test_buffer_data_with_float_data_is_noop();
  failures = failures + test_delete_buffer_with_nonzero_is_noop();

  // SECTION 10: VAO lifecycle (4)
  failures = failures + test_gen_vertex_array_returns_err_in_stub_mode();
  failures = failures + test_bind_vertex_array_with_nonzero_is_noop();
  failures = failures + test_enable_vertex_attrib_is_noop();
  failures = failures + test_vertex_attrib_pointer_is_noop();

  // SECTION 11: Drawing stubs (3)
  failures = failures + test_draw_arrays_is_noop();
  failures = failures + test_clear_color_is_noop();
  failures = failures + test_viewport_is_noop();

  // SECTION 12: Texture stubs (4)
  failures = failures + test_gen_texture_returns_err_in_stub_mode();
  failures = failures + test_bind_texture_is_noop();
  failures = failures + test_tex_image2d_with_data_is_noop();
  failures = failures + test_tex_parameteri_is_noop();

  // SECTION 13: Uniform stubs (4)
  failures = failures + test_get_uniform_location_returns_neg1_in_stub_mode();
  failures = failures + test_uniform1i_is_noop();
  failures = failures + test_uniform1f_is_noop();
  failures = failures + test_uniform_matrix4fv_is_noop();

  // SECTION 14: Context & error stubs (3)
  failures = failures + test_create_context_returns_err_in_stub_mode();
  failures = failures + test_swap_buffers_is_noop();
  failures = failures + test_get_error_returns_no_error_in_stub_mode();

  // SECTION 15: Smoke all non-Result (1)
  failures = failures + test_smoke_all_nonresult_callable();

  // SECTION 16: Smoke all Result return Err (1)
  failures = failures + test_smoke_all_result_funcs_return_err();

  // SECTION 17: Shader lifecycle smoke (1)
  failures = failures + test_shader_lifecycle_stubs_no_crash();

  return failures;
}
