// XIOM — Vulkan Bindings (C Bridge Wrapper)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations and safe wrappers for the xvk C bridge library.
// Phase 1: Production-grade GPU API with buffers, images, descriptors, compute.
module xiom.vulkan

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub type Buffer  = { handle: Int; }
pub type Image   = { handle: Int; width: Int; height: Int; }
pub type ImageView = { handle: Int; }
pub type Sampler = { handle: Int; }
pub type Shader  = { handle: Int; }
pub type Pipeline = { handle: Int; }
pub type PipelineLayout = { handle: Int; }
pub type DescSetLayout = { handle: Int; }
pub type DescPool = { handle: Int; }
pub type DescSet = { handle: Int; }
pub type RenderPass = { handle: Int; }
pub type Framebuffer = { handle: Int; }

pub type VertexBinding = {
  binding: Int;
  stride: Int;
  input_rate: Int;  // 0 = per-vertex, 1 = per-instance
}

pub type VertexAttribute = {
  location: Int;
  binding: Int;
  format: Int;  // 1=float2, 2=float3, 3=float4, 4=uint8_4norm, 5=int32
  offset: Int;
}

// ===========================================================================
// FFI declarations — existing API (native pointer types, G1/G2 fixed in v0.47.3)
// ===========================================================================
extern "C" {
  fn xvk_app_create(title: Str, width: Int32, height: Int32) -> Int;
  fn xvk_app_destroy(app: Int);
  fn xvk_app_valid(app: Int) -> Int32;
  fn xvk_last_error() -> Str;
  fn xvk_app_did_resize(app: Int) -> Int32;
  fn xvk_app_maximize(app: Int);
  fn xvk_app_toggle_fullscreen(app: Int);

  fn xvk_app_clear_resize(app: Int);

  fn xvk_app_should_close(app: Int) -> Int32;
  fn xvk_app_poll(app: Int);
  fn xvk_now() -> Float64;
  fn xvk_device_type(app: Int) -> Int32;
  fn xvk_begin_frame(app: Int) -> Int32;
  fn xvk_set_clear_color(app: Int, r: Float32, g: Float32, b: Float32);
  fn xvk_end_frame(app: Int);
  fn xvk_draw_triangle_2d(app: Int, r: Float32, g: Float32, b: Float32);
  fn xvk_draw_cube_3d(app: Int, angle: Float32);
  fn xvk_offscreen_create(width: Int32, height: Int32) -> Int;
  fn xvk_offscreen_render_triangle(app: Int, r: Float32, g: Float32, b: Float32) -> Int32;
  fn xvk_offscreen_pixel(app: Int, x: Int32, y: Int32) -> Int32;
  fn xvk_offscreen_hash(app: Int) -> Int;
  fn xvk_offscreen_destroy(app: Int);
  fn xvk_draw_quad_2d(app: Int, cx: Float32, cy: Float32, hw: Float32, hh: Float32, r: Float32, g: Float32, b: Float32);
  fn xvk_draw_cube_3d_at(app: Int, angle: Float32, px: Float32, py: Float32, pz: Float32, scale: Float32);
  fn xvk_particles_enable(app: Int, count: Int32) -> Int32;
  fn xvk_draw_particles(app: Int, dt: Float32);

  // Phase 8.2 — Mouse/Keyboard input
  fn xvk_get_mouse_x(app: Int) -> Float64;
  fn xvk_get_mouse_y(app: Int) -> Float64;
  fn xvk_get_mouse_button(app: Int, button: Int32) -> Int32;
  fn xvk_get_key(app: Int, key: Int32) -> Int32;

  // Phase 1 — Buffers
  fn xvk_buffer_create(app: Int, size: Int, usage: Int32, memory: Int32) -> Int;
  fn xvk_buffer_destroy(app: Int, buf: Int);
  fn xvk_buffer_size(app: Int, buf: Int) -> Int;
  fn xvk_buffer_map(app: Int, buf: Int) -> Int;
  fn xvk_buffer_unmap(app: Int, buf: Int);
  fn xvk_buffer_write(app: Int, buf: Int, offset: Int, data: *UInt8, data_size: Int);
  fn xvk_buffer_read(app: Int, buf: Int, offset: Int, out: *UInt8, out_size: Int);

  // Phase 1 — Images & Views
  fn xvk_image_create_2d(app: Int, width: Int32, height: Int32, format: Int32, usage: Int32, mip_levels: Int32) -> Int;
  fn xvk_image_destroy(app: Int, img: Int);
  fn xvk_image_view_create(app: Int, img: Int, format: Int32, aspect: Int32) -> Int;
  fn xvk_image_view_destroy(app: Int, view: Int);

  // Phase 1 — Samplers
  fn xvk_sampler_create(app: Int, filter: Int32, address_u: Int32, address_v: Int32, mip_mode: Int32, max_lod: Float32) -> Int;
  fn xvk_sampler_destroy(app: Int, sampler: Int);

  // Phase 1 — Shader Modules
  fn xvk_shader_create(app: Int, code: *UInt8, code_size: Int32) -> Int;
  fn xvk_shader_create_named(app: Int, name: Str) -> Int;
  fn xvk_shader_destroy(app: Int, shader: Int);

  // Phase 1 — Pipeline Layouts & Descriptor Set Layouts
  fn xvk_pipeline_layout_create(app: Int, push_size: Int32, push_stages: Int32, desc_layout_count: Int32, desc_layouts: *Int) -> Int;
  fn xvk_pipeline_layout_destroy(app: Int, layout: Int);
  fn xvk_desc_set_layout_create(app: Int, bindings: *Int32, count: Int32) -> Int;
  fn xvk_desc_set_layout_destroy(app: Int, layout: Int);

  // Phase 1 — Pipelines
  fn xvk_pipeline_create_graphics(app: Int, topology: Int32, cull_mode: Int32, depth_test: Int32, depth_write: Int32, blend_enable: Int32, vertex_shader: Int, fragment_shader: Int, layout: Int, render_pass: Int, bindings: *Int32, binding_count: Int32, attributes: *Int32, attr_count: Int32) -> Int;
  fn xvk_pipeline_destroy(app: Int, pipeline: Int);
  fn xvk_pipeline_create_compute(app: Int, shader: Int, layout: Int) -> Int;
  fn xvk_compute_dispatch(app: Int, pipeline: Int, layout: Int, x: Int32, y: Int32, z: Int32);

  // Phase 1 — Descriptor Pool & Sets
  fn xvk_desc_pool_create(app: Int, pool_sizes: *Int32, size_count: Int32, max_sets: Int32) -> Int;
  fn xvk_desc_pool_destroy(app: Int, pool: Int);
  fn xvk_desc_set_allocate(app: Int, pool: Int, layout: Int) -> Int;
  fn xvk_desc_set_free(app: Int, pool: Int, set: Int);
  fn xvk_desc_set_write_buffer(app: Int, set: Int, binding: Int32, buf: Int, offset: Int, range: Int, type_: Int32);
  fn xvk_desc_set_write_image(app: Int, set: Int, binding: Int32, sampler: Int, image_view: Int);

  // Phase 1 — Render Passes & Framebuffers
  fn xvk_render_pass_create(app: Int, color_formats: *Int32, color_count: Int32, depth_format: Int32) -> Int;
  fn xvk_render_pass_destroy(app: Int, rp: Int);
  fn xvk_framebuffer_create(app: Int, render_pass: Int, attachments: *Int, attachment_count: Int32, width: Int32, height: Int32) -> Int;
  fn xvk_framebuffer_destroy(app: Int, fb: Int);

  // Phase 1 — Command Recording
  fn xvk_app_cmd_bind_vertex_buffer(app: Int, binding: Int32, buf: Int, offset: Int);
  fn xvk_app_cmd_bind_index_buffer(app: Int, buf: Int, offset: Int, index_type: Int32);
  fn xvk_app_cmd_bind_pipeline(app: Int, pipeline: Int);
  fn xvk_app_cmd_bind_descriptor_sets(app: Int, layout: Int, first_set: Int32, sets: *Int, set_count: Int32);
  fn xvk_app_cmd_push_constants(app: Int, layout: Int, stages: Int32, offset: Int32, size: Int32, data: *UInt8);
  fn xvk_app_cmd_draw_indexed(app: Int, index_count: Int32, instance_count: Int32, first_index: Int32, vertex_offset: Int32, first_instance: Int32);
  fn xvk_app_cmd_draw(app: Int, vertex_count: Int32, instance_count: Int32, first_vertex: Int32, first_instance: Int32);

  // Phase 1 — Custom Render Pass
  fn xvk_begin_custom_pass(app: Int, render_pass: Int, framebuffer: Int, width: Int32, height: Int32, r: Float32, g: Float32, b: Float32) -> Int32;
  fn xvk_end_custom_pass(app: Int) -> Int32;

  // Phase 1 — Layout Transitions
  fn xvk_image_transition(app: Int, img: Int, old_layout: Int32, new_layout: Int32);

  // Phase 1 — Utility
  fn xvk_get_framebuffer_size(app: Int, out_width: *Int32, out_height: *Int32);

  // Phase 7.5 — Multi-Thread Command Pools
  fn xvk_alloc(size: Int) -> Int;
  fn xvk_free(ptr: Int);
  fn xvk_create_command_pools(count: Int32, device: Int, queue_family: Int32, flags: Int32, out_pools: Int) -> Int;
  fn xvk_allocate_command_buffers_multi(device: Int, pool: Int, level: Int32, count: Int32, out_buffers: Int) -> Int32;
  fn xvk_queue_submit_multi(queue: Int, cmd_buf_count: Int32, cmd_bufs: Int, fence: Int) -> Int32;
  fn vkTrimCommandPool(device: Int, pool: Int, flags: Int32);

  // Phase 7.3 — Shader Compilation Toolchain
  fn xvk_compile_glsl_to_spirv(source: Str, stage: Str, flags: Int) -> Int;
  fn xvk_compile_glsl_file_to_spirv(filepath: Str, stage: Str, flags: Int) -> Int;
  fn xvk_free_spirv_result(result_ptr: Int);
  fn xvk_read_u64(base: Int, offset: Int) -> Int;
  fn xvk_read_u32(base: Int, offset: Int) -> Int32;

  // Phase 7.4 — Texture Loading Pipeline
  fn xvk_get_physical_device(app: Int) -> Int;
  fn xvk_get_graphics_queue(app: Int) -> Int;
  fn xvk_get_command_pool(app: Int) -> Int;
  fn xvk_get_instance(app: Int) -> Int;
  fn xvk_get_render_pass(app: Int) -> Int;
  fn xvk_get_command_buffer(app: Int) -> Int;
  fn xvk_get_glfw_window(app: Int) -> Int;
  fn xvk_get_fb_width(app: Int) -> Int32;
  fn xvk_get_fb_height(app: Int) -> Int32;

  fn xvk_get_device(app: Int) -> Int;
  fn xvk_texture_create(device: Int, physical_device: Int, cmd_pool: Int, queue: Int, pixel_data: Int, width: Int32, height: Int32, generate_mips: Int32) -> Int;
  fn xvk_texture_get_image(texture: Int) -> Int;
  fn xvk_texture_get_image_view(texture: Int) -> Int;
  fn xvk_texture_get_sampler(texture: Int) -> Int;
  fn xvk_texture_get_width(texture: Int) -> Int32;
  fn xvk_texture_get_height(texture: Int) -> Int32;
  fn xvk_texture_get_mip_levels(texture: Int) -> Int32;
  fn xvk_texture_destroy(device: Int, texture: Int);

  // Phase 8.1 — Debug validation message capture
  fn xvk_create_debug_messenger_default(instance: Int, severity_mask: Int32, type_mask: Int32) -> Int;
  fn xvk_get_validation_messages(out_count: Int, out_buffer: Int) -> Int32;
  fn xvk_clear_validation_messages();

  // Phase 8.3 — Font/text rendering
  fn xvk_font_create(font_data: Int, data_size: Int32, px_height: Float32) -> Int;
  fn xvk_font_get_glyph_count(font: Int) -> Int32;
  fn xvk_font_get_glyph(font: Int, codepoint: Int32, out_glyph: Int) -> Int32;
  fn xvk_font_get_atlas_pixels(font: Int, out_width: Int, out_height: Int) -> Int;
  fn xvk_font_get_metrics(font: Int, out_metrics: Int);
  fn xvk_font_measure_text(font: Int, text: Str) -> Float32;
  fn xvk_font_destroy(font: Int);
  fn xvk_font_render_text(font: Int, text: Str, out_width: Int, out_height: Int) -> Int;
  fn xvk_font_free_pixels(pixels: Int);
  fn xvk_proc_texture_solid(width: Int32, height: Int32, r: Float32, g: Float32, b: Float32) -> Int;
  fn xvk_proc_texture_gradient(width: Int32, height: Int32, r1: Float32, g1: Float32, b1: Float32, r2: Float32, g2: Float32, b2: Float32, horizontal: Int32) -> Int;
  fn xvk_free_pixels(pixels: Int);

  // Textured quad rendering
  fn xvk_image_load(filepath: Str, out_width: Int, out_height: Int) -> Int;
  fn xvk_font_create_from_file(filepath: Str, px_height: Float32, out_w: Int, out_h: Int) -> Int;
  fn xvk_audio_beep();
  fn xvk_audio_play_wav(filepath: Str);

  // 3D Camera
  fn xvk_camera_set_view(ex: Float32, ey: Float32, ez: Float32, tx: Float32, ty: Float32, tz: Float32);
  fn xvk_camera_orbit(dyaw: Float32, dpitch: Float32, dradius: Float32);
  fn xvk_camera_zoom(delta: Float32);
  fn xvk_camera_reset();
  fn xvk_camera_set_aspect_ratio(aspect: Float32);
  fn xvk_camera_set_aspect_from_fb(fb_w: Int32, fb_h: Int32);
  fn xvk_cos(x: Float32) -> Float32;
  fn xvk_sin(x: Float32) -> Float32;

  // OBJ Mesh loader
  fn xvk_mesh_load(device: Int, phys_dev: Int, filepath: Str) -> Int;
  fn xvk_mesh_vertex_count(mesh: Int) -> Int32;
  fn xvk_mesh_index_count(mesh: Int) -> Int32;
  fn xvk_mesh_vertex_buffer(mesh: Int) -> Int;
  fn xvk_draw_mesh_lit(app: Int, mesh: Int, angle: Float32, px: Float32, py: Float32, pz: Float32, scale: Float32);
  fn xvk_mesh_destroy(device: Int, mesh: Int);

  fn xvk_image_free(pixels: Int);

  fn xvk_draw_texture_quad(app: Int, image_view: Int, sampler: Int, cx: Float32, cy: Float32, hw: Float32, hh: Float32);

  // UI hit-testing (avoids Float64 in XIOM)
  fn xvk_button_hit_state(app: Int, cx: Float32, cy: Float32, hw: Float32, hh: Float32) -> Int32;
}

// ===========================================================================
// Phase 8.2 — Mouse/Keyboard Input
// ===========================================================================

pub fn get_mouse_pos(app: Int) -> (Float64, Float64) {
  let x = unsafe { xvk_get_mouse_x(app) };
  let y = unsafe { xvk_get_mouse_y(app) };
  return (x, y);
}

pub fn is_mouse_down(app: Int, button: Int) -> Bool {
  return 0 != unsafe { xvk_get_mouse_button(app, button as Int32) };
}

pub fn is_key_down(app: Int, key: Int) -> Bool {
  return 0 != unsafe { xvk_get_key(app, key as Int32) };
}

// ===========================================================================
// Safe wrappers — Lifecycle
// ===========================================================================

fn bool_to_i32(b: Bool) -> Int32 {
  if b { return 1; }
  return 0;
}

pub fn create_app(title: Str, width: Int, height: Int) -> Result[Int, Str]
  requires: width > 0
  requires: height > 0
{
  let raw = unsafe { xvk_app_create(title, width as Int32, height as Int32) };
  if raw == 0 {
    return Err("failed to create vulkan app");
  }
  return Ok(raw);
}

pub fn destroy_app(app: Int)
  requires: app != 0
{
  unsafe { xvk_app_destroy(app); }
}

pub fn app_valid(app: Int) -> Bool {
  let ok: Int32 = unsafe { xvk_app_valid(app) };
  return ok != 0;
}

pub fn should_close(app: Int) -> Bool
  requires: app != 0
{
  let sc: Int32 = unsafe { xvk_app_should_close(app) };
  return sc != 0;
}

pub fn poll(app: Int)
  requires: app != 0
{
  unsafe { xvk_app_poll(app); }
}

pub fn now() -> Float64 {
  return unsafe { xvk_now() };
}

pub fn device_type(app: Int) -> Int
  requires: app != 0
{
  let dt: Int32 = unsafe { xvk_device_type(app) };
  return dt as Int;
}

pub fn last_error() -> Str {
  return unsafe { xvk_last_error() };
}

pub fn get_framebuffer_size(app: Int) -> (Int, Int)
  requires: app != 0
{
  var w: Int32 = 0;
  var h: Int32 = 0;
  unsafe { xvk_get_framebuffer_size(app, &w, &h); }
  return (w as Int, h as Int);
}

// ===========================================================================
// Safe wrappers — Frame lifecycle
// ===========================================================================

pub fn begin_frame(app: Int) -> Int
  requires: app != 0
{
  let bf: Int32 = unsafe { xvk_begin_frame(app) };
  return bf as Int;
}

pub fn set_clear_color(app: Int, r: Float32, g: Float32, b: Float32)
  requires: app != 0
{
  unsafe { xvk_set_clear_color(app, r, g, b); }
}

pub fn end_frame(app: Int)
  requires: app != 0
{
  unsafe { xvk_end_frame(app); }
}

// ===========================================================================
// Safe wrappers — Drawing (legacy, for backward compatibility)
// ===========================================================================

pub fn draw_triangle_2d(app: Int, r: Float32, g: Float32, b: Float32)
  requires: app != 0
{
  unsafe { xvk_draw_triangle_2d(app, r, g, b); }
}

pub fn draw_cube_3d(app: Int, angle: Float32)
  requires: app != 0
{
  unsafe { xvk_draw_cube_3d(app, angle); }
}

pub fn draw_quad_2d(app: Int, cx: Float32, cy: Float32, hw: Float32, hh: Float32, r: Float32, g: Float32, b: Float32)
  requires: app != 0
{
  unsafe { xvk_draw_quad_2d(app, cx, cy, hw, hh, r, g, b); }
}

pub fn draw_texture_quad(app: Int, image_view: Int, sampler: Int, cx: Float32, cy: Float32, hw: Float32, hh: Float32)
  requires: app != 0
  requires: image_view != 0
{
  unsafe { xvk_draw_texture_quad(app, image_view, sampler, cx, cy, hw, hh); }
}

pub fn image_load(app: Int, filepath: Str, out_width: Int, out_height: Int) -> Int
  requires: app != 0
{
  return unsafe { xvk_image_load(filepath, out_width, out_height) };
}

pub fn image_free(pixels: Int) {
  unsafe { xvk_image_free(pixels); }
}

pub fn draw_cube_3d_at(app: Int, angle: Float32, px: Float32, py: Float32, pz: Float32, scale: Float32)
  requires: app != 0
{
  unsafe { xvk_draw_cube_3d_at(app, angle, px, py, pz, scale); }
}

pub fn particles_enable(app: Int, count: Int) -> Bool
  requires: app != 0
  requires: count > 0
{
  let result: Int32 = unsafe { xvk_particles_enable(app, count as Int32) };
  return result != 0;
}

pub fn draw_particles(app: Int, dt: Float32)
  requires: app != 0
{
  unsafe { xvk_draw_particles(app, dt); }
}

// ===========================================================================
// Safe wrappers — Offscreen
// ===========================================================================

pub fn offscreen_create(width: Int, height: Int) -> Result[Int, Str]
  requires: width > 0
  requires: height > 0
{
  let raw = unsafe { xvk_offscreen_create(width as Int32, height as Int32) };
  if raw == 0 {
    return Err("failed to create offscreen surface");
  }
  return Ok(raw);
}

pub fn offscreen_render_triangle(app: Int, r: Float32, g: Float32, b: Float32) -> Bool
  requires: app != 0
{
  let ok: Int32 = unsafe { xvk_offscreen_render_triangle(app, r, g, b) };
  return ok != 0;
}

pub fn offscreen_pixel(app: Int, x: Int, y: Int) -> Int
  requires: app != 0
{
  let px: Int32 = unsafe { xvk_offscreen_pixel(app, x as Int32, y as Int32) };
  return px as Int;
}

pub fn offscreen_hash(app: Int) -> Int
  requires: app != 0
{
  return unsafe { xvk_offscreen_hash(app) };
}

pub fn offscreen_destroy(app: Int)
  requires: app != 0
{
  unsafe { xvk_offscreen_destroy(app); }
}

// ===========================================================================
// Safe wrappers — Buffers
// ===========================================================================

pub fn buffer_create(app: Int, size: Int, usage: Int, memory: Int) -> Result[Int, Str]
  requires: app != 0
  requires: size > 0
{
  let h = unsafe { xvk_buffer_create(app, size, usage as Int32, memory as Int32) };
  if h == 0 {
    return Err("buffer_create failed");
  }
  return Ok(h);
}

pub fn buffer_destroy(app: Int, buf: Int)
  requires: app != 0
{
  unsafe { xvk_buffer_destroy(app, buf); }
}

pub fn buffer_size(app: Int, buf: Int) -> Int
  requires: app != 0
{
  return unsafe { xvk_buffer_size(app, buf) };
}

pub fn buffer_map(app: Int, buf: Int) -> Bool
  requires: app != 0
{
  return unsafe { xvk_buffer_map(app, buf) } != 0;
}

pub fn buffer_unmap(app: Int, buf: Int)
  requires: app != 0
{
  unsafe { xvk_buffer_unmap(app, buf); }
}

pub fn buffer_write_float(app: Int, buf: Int, offset: Int, data: Vec[Float32]) {
  let sz = data.len() * 4;
  unsafe { xvk_buffer_write(app, buf, offset, data as *UInt8, sz); }
}

pub fn buffer_read_float(app: Int, buf: Int, offset: Int, count: Int) -> Vec[Float32] {
  var out: Vec[Float32] = [];
  let sz = count * 4;
  unsafe { xvk_buffer_read(app, buf, offset, out as *UInt8, sz); }
  return out;
}

// ===========================================================================
// Safe wrappers — Images
// ===========================================================================

pub fn image_create_2d(app: Int, width: Int, height: Int, format: Int, usage: Int, mip_levels: Int) -> Result[Int, Str]
  requires: app != 0
  requires: width > 0
  requires: height > 0
{
  let h = unsafe { xvk_image_create_2d(app, width as Int32, height as Int32, format as Int32, usage as Int32, mip_levels as Int32) };
  if h == 0 {
    return Err("image_create_2d failed");
  }
  return Ok(h);
}

pub fn image_destroy(app: Int, img: Int)
  requires: app != 0
{
  unsafe { xvk_image_destroy(app, img); }
}

pub fn image_view_create(app: Int, img: Int, format: Int, aspect: Int) -> Result[Int, Str]
  requires: app != 0
{
  let h = unsafe { xvk_image_view_create(app, img, format as Int32, aspect as Int32) };
  if h == 0 {
    return Err("image_view_create failed");
  }
  return Ok(h);
}

pub fn image_view_destroy(app: Int, view: Int)
  requires: app != 0
{
  unsafe { xvk_image_view_destroy(app, view); }
}

// ===========================================================================
// Safe wrappers — Samplers
// ===========================================================================

pub fn sampler_create(app: Int, filter: Int, address_u: Int, address_v: Int, mip_mode: Int, max_lod: Float32) -> Result[Int, Str]
  requires: app != 0
{
  let h = unsafe { xvk_sampler_create(app, filter as Int32, address_u as Int32, address_v as Int32, mip_mode as Int32, max_lod) };
  if h == 0 {
    return Err("sampler_create failed");
  }
  return Ok(h);
}

pub fn sampler_destroy(app: Int, sampler: Int)
  requires: app != 0
{
  unsafe { xvk_sampler_destroy(app, sampler); }
}

// ===========================================================================
// Safe wrappers — Shader Modules
// ===========================================================================

pub fn shader_create(app: Int, code: Vec[UInt32]) -> Result[Int, Str]
  requires: app != 0
{
  let byte_size = code.len() * 4;
  let h = unsafe { xvk_shader_create(app, code as *UInt8, byte_size as Int32) };
  if h == 0 {
    return Err("shader_create failed");
  }
  return Ok(h);
}

pub fn shader_create_named(app: Int, name: Str) -> Result[Int, Str]
  requires: app != 0
{
  let h = unsafe { xvk_shader_create_named(app, name) };
  if h == 0 {
    return Err("shader_create_named failed");
  }
  return Ok(h);
}

pub fn shader_destroy(app: Int, shader: Int)
  requires: app != 0
{
  unsafe { xvk_shader_destroy(app, shader); }
}

// ===========================================================================
// Safe wrappers — Pipeline Layouts & Descriptor Set Layouts
// ===========================================================================

pub fn pipeline_layout_create(app: Int, push_size: Int, push_stages: Int, desc_layouts: Vec[Int]) -> Result[Int, Str]
  requires: app != 0
{
  let n = desc_layouts.len();
  let h = unsafe { xvk_pipeline_layout_create(app, push_size as Int32, push_stages as Int32, n as Int32, desc_layouts as *Int) };
  if h == 0 {
    return Err("pipeline_layout_create failed");
  }
  return Ok(h);
}

pub fn pipeline_layout_destroy(app: Int, layout: Int)
  requires: app != 0
{
  unsafe { xvk_pipeline_layout_destroy(app, layout); }
}

pub fn desc_set_layout_create(app: Int, bindings: Vec[Int32]) -> Result[Int, Str]
  requires: app != 0
  requires: bindings.len() > 0
{
  let h = unsafe { xvk_desc_set_layout_create(app, bindings as *Int32, bindings.len() as Int32) };
  if h == 0 {
    return Err("desc_set_layout_create failed");
  }
  return Ok(h);
}

pub fn desc_set_layout_destroy(app: Int, layout: Int)
  requires: app != 0
{
  unsafe { xvk_desc_set_layout_destroy(app, layout); }
}

// ===========================================================================
// Safe wrappers — Pipelines
// ===========================================================================

pub fn pipeline_create_graphics(app: Int, topology: Int, cull_mode: Int, depth_test: Bool, depth_write: Bool, blend: Bool, vert_shader: Int, frag_shader: Int, layout: Int, render_pass: Int, bindings: Vec[Int32], attributes: Vec[Int32]) -> Result[Int, Str]
  requires: app != 0
{
  let h = unsafe {
    xvk_pipeline_create_graphics(
      app, topology as Int32, cull_mode as Int32,
      bool_to_i32(depth_test), bool_to_i32(depth_write), bool_to_i32(blend),
      vert_shader, frag_shader, layout, render_pass,
      bindings as *Int32, bindings.len() as Int32,
      attributes as *Int32, attributes.len() as Int32
    )
  };
  if h == 0 {
    return Err("pipeline_create_graphics failed");
  }
  return Ok(h);
}

pub fn pipeline_create_compute(app: Int, shader: Int, layout: Int) -> Result[Int, Str]
  requires: app != 0
{
  let h = unsafe { xvk_pipeline_create_compute(app, shader, layout) };
  if h == 0 {
    return Err("pipeline_create_compute failed");
  }
  return Ok(h);
}

pub fn pipeline_destroy(app: Int, pipeline: Int)
  requires: app != 0
{
  unsafe { xvk_pipeline_destroy(app, pipeline); }
}

pub fn compute_dispatch(app: Int, pipeline: Int, layout: Int, x: Int, y: Int, z: Int)
  requires: app != 0
{
  unsafe { xvk_compute_dispatch(app, pipeline, layout, x as Int32, y as Int32, z as Int32); }
}

// ===========================================================================
// Safe wrappers — Descriptor Pools & Sets
// ===========================================================================

pub fn desc_pool_create(app: Int, pool_sizes: Vec[Int32], max_sets: Int) -> Result[Int, Str]
  requires: app != 0
{
  let h = unsafe { xvk_desc_pool_create(app, pool_sizes as *Int32, pool_sizes.len() as Int32, max_sets as Int32) };
  if h == 0 {
    return Err("desc_pool_create failed");
  }
  return Ok(h);
}

pub fn desc_pool_destroy(app: Int, pool: Int)
  requires: app != 0
{
  unsafe { xvk_desc_pool_destroy(app, pool); }
}

pub fn desc_set_allocate(app: Int, pool: Int, layout: Int) -> Result[Int, Str]
  requires: app != 0
{
  let h = unsafe { xvk_desc_set_allocate(app, pool, layout) };
  if h == 0 {
    return Err("desc_set_allocate failed");
  }
  return Ok(h);
}

pub fn desc_set_write_buffer(app: Int, set: Int, binding: Int, buf: Int, offset: Int, range: Int, desc_type: Int)
  requires: app != 0
{
  unsafe { xvk_desc_set_write_buffer(app, set, binding as Int32, buf, offset, range, desc_type as Int32); }
}

pub fn desc_set_write_image(app: Int, set: Int, binding: Int, sampler: Int, image_view: Int)
  requires: app != 0
{
  unsafe { xvk_desc_set_write_image(app, set, binding as Int32, sampler, image_view); }
}

// ===========================================================================
// Safe wrappers — Render Passes & Framebuffers
// ===========================================================================

pub fn render_pass_create(app: Int, color_formats: Vec[Int32], depth_format: Int) -> Result[Int, Str]
  requires: app != 0
{
  let h = unsafe { xvk_render_pass_create(app, color_formats as *Int32, color_formats.len() as Int32, depth_format as Int32) };
  if h == 0 {
    return Err("render_pass_create failed");
  }
  return Ok(h);
}

pub fn render_pass_destroy(app: Int, rp: Int)
  requires: app != 0
{
  unsafe { xvk_render_pass_destroy(app, rp); }
}

pub fn framebuffer_create(app: Int, render_pass: Int, attachments: Vec[Int], width: Int, height: Int) -> Result[Int, Str]
  requires: app != 0
{
  let h = unsafe { xvk_framebuffer_create(app, render_pass, attachments as *Int, attachments.len() as Int32, width as Int32, height as Int32) };
  if h == 0 {
    return Err("framebuffer_create failed");
  }
  return Ok(h);
}

pub fn framebuffer_destroy(app: Int, fb: Int)
  requires: app != 0
{
  unsafe { xvk_framebuffer_destroy(app, fb); }
}

// ===========================================================================
// Safe wrappers — Command Recording
// ===========================================================================

pub fn cmd_bind_vertex_buffer(app: Int, binding: Int, buf: Int, offset: Int)
  requires: app != 0
{
  unsafe { xvk_app_cmd_bind_vertex_buffer(app, binding as Int32, buf, offset); }
}

pub fn cmd_bind_index_buffer(app: Int, buf: Int, offset: Int, index_type: Int)
  requires: app != 0
{
  unsafe { xvk_app_cmd_bind_index_buffer(app, buf, offset, index_type as Int32); }
}

pub fn cmd_bind_pipeline(app: Int, pipeline: Int)
  requires: app != 0
{
  unsafe { xvk_app_cmd_bind_pipeline(app, pipeline); }
}

pub fn cmd_bind_descriptor_sets(app: Int, layout: Int, first_set: Int, sets: Vec[Int])
  requires: app != 0
{
  unsafe { xvk_app_cmd_bind_descriptor_sets(app, layout, first_set as Int32, sets as *Int, sets.len() as Int32); }
}

pub fn cmd_push_constants_float(app: Int, layout: Int, stages: Int, offset: Int, data: Vec[Float32])
  requires: app != 0
{
  let sz = data.len() * 4;
  unsafe { xvk_app_cmd_push_constants(app, layout, stages as Int32, offset as Int32, sz as Int32, data as *UInt8); }
}

pub fn cmd_draw_indexed(app: Int, index_count: Int, instance_count: Int, first_index: Int, vertex_offset: Int, first_instance: Int)
  requires: app != 0
{
  unsafe { xvk_app_cmd_draw_indexed(app, index_count as Int32, instance_count as Int32, first_index as Int32, vertex_offset as Int32, first_instance as Int32); }
}

pub fn cmd_draw(app: Int, vertex_count: Int, instance_count: Int, first_vertex: Int, first_instance: Int)
  requires: app != 0
{
  unsafe { xvk_app_cmd_draw(app, vertex_count as Int32, instance_count as Int32, first_vertex as Int32, first_instance as Int32); }
}

// ===========================================================================
// Safe wrappers — Custom Render Pass
// ===========================================================================

pub fn begin_custom_pass(app: Int, render_pass: Int, framebuffer: Int, width: Int, height: Int, r: Float32, g: Float32, b: Float32) -> Int
  requires: app != 0
{
  return unsafe { xvk_begin_custom_pass(app, render_pass, framebuffer, width as Int32, height as Int32, r, g, b) } as Int;
}

pub fn end_custom_pass(app: Int) -> Int
  requires: app != 0
{
  return unsafe { xvk_end_custom_pass(app) } as Int;
}

// ===========================================================================
// Safe wrappers — Layout Transitions
// ===========================================================================

pub fn image_transition(app: Int, img: Int, old_layout: Int, new_layout: Int)
  requires: app != 0
{
  unsafe { xvk_image_transition(app, img, old_layout as Int32, new_layout as Int32); }
}

// ===========================================================================
// Phase 7.5: Multi-Thread Command Pools — High-Level API
// ===========================================================================

/// Create N thread-safe command pools for multi-threaded rendering.
/// All pools share the same queue family and include RESET_COMMAND_BUFFER_BIT.
/// Returns: number of pools created (should equal thread_count on success).
///
/// Example: `let count = threaded_command_pool_create(app, 4);`
/// Each pool can be used by one thread to allocate and record command buffers.
pub fn threaded_command_pool_create(app: Int, thread_count: Int) -> Int
  requires: app != 0
  requires: thread_count > 0
{
  // VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT = 2
  // queue family = 0 (graphics) — caller should know their queue family
  let pools_buf = unsafe { xvk_alloc(thread_count * 8) };
  let flags: Int32 = 2;  // VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
  let created: Int = unsafe { xvk_create_command_pools(thread_count as Int32, app, 0 as Int32, flags, pools_buf) };
  unsafe { xvk_free(pools_buf); }
  return created;
}

/// Phase 7.5: Allocate count command buffers from a pool for multi-thread recording.
/// out_bufs must be pre-allocated (8 * count bytes). Returns VkResult.
///
/// Example: `allocate_threaded_command_buffers(app, pool, count, bufs_ptr)`
pub fn allocate_threaded_command_buffers(app: Int, pool: Int, count: Int, out_bufs: Int) -> Int
  requires: app != 0
  requires: pool != 0
  requires: count > 0
  requires: out_bufs != 0
{
  // VK_COMMAND_BUFFER_LEVEL_PRIMARY = 0
  let res: Int32 = unsafe { xvk_allocate_command_buffers_multi(app, pool, 0 as Int32, count as Int32, out_bufs) };
  return res as Int;
}

/// Phase 7.5: Submit multiple command buffers to a queue for execution.
/// cmd_bufs must be a pointer to an array of Int64 handles (8 bytes each).
/// fence is a VkFence handle (0 for no fence). Returns VkResult.
///
/// Example: `submit_multi_command_buffers(queue, cmd_bufs_ptr, count, fence)`
pub fn submit_multi_command_buffers(queue: Int, cmd_bufs: Int, count: Int, fence: Int) -> Int
  requires: queue != 0
  requires: cmd_bufs != 0
  requires: count > 0
{
  let res: Int32 = unsafe { xvk_queue_submit_multi(queue, count as Int32, cmd_bufs, fence) };
  return res as Int;
}

/// Phase 7.5: Trim a command pool to release unused internal resources (VK 1.1+).
pub fn trim_command_pool(app: Int, pool: Int)
  requires: app != 0
  requires: pool != 0
{
  unsafe { vkTrimCommandPool(app, pool, 0); }
}

// ===========================================================================
// Phase 7.3: Shader Compilation Toolchain — High-Level API
// ===========================================================================

/// Phase 7.3: Compile a GLSL source string to SPIR-V at runtime.
/// Uses glslc (Vulkan SDK) as a subprocess via the bridge.
/// Returns: pointer to SPIR-V result buffer (use with shader_create_raw_spirv),
///   or 0 on failure. Free with free_spirv_result.
pub fn shader_compile_glsl(source: Str, stage: Str) -> Int
{
  return unsafe { xvk_compile_glsl_to_spirv(source, stage, 0) };
}

/// Phase 7.3: Compile a GLSL shader file to SPIR-V.
/// filepath: path to .vert/.frag/.comp GLSL source.
/// stage:    shader stage ("vertex", "fragment", etc.). Use "" for auto-detect.
pub fn shader_compile_file(filepath: Str, stage: Str) -> Int
{
  return unsafe { xvk_compile_glsl_file_to_spirv(filepath, stage, 0) };
}

/// Phase 7.3: Get the size of SPIR-V data from a compile result buffer.
pub fn spirv_result_size(result_ptr: Int) -> Int
  requires: result_ptr != 0
{
  return unsafe { xvk_read_u64(result_ptr, 0) };
}

/// Phase 7.3: Free a SPIR-V compile result buffer.
pub fn free_spirv_result(result_ptr: Int)
{
  unsafe { xvk_free_spirv_result(result_ptr); }
}

/// Phase 7.3: Create a shader module from a SPIR-V compile result buffer.
pub fn shader_create_raw_spirv(app: Int, spirv_result: Int) -> Int
  requires: app != 0
  requires: spirv_result != 0
{
  let size: Int32 = unsafe { xvk_read_u32(spirv_result, 0) };
  // The SPIR-V data starts at offset 8 (after the size prefix)
  let code_ptr = spirv_result + 8;
  return unsafe { xvk_shader_create(app, code_ptr, size) };
}

// ===========================================================================
// Phase 7.4: Texture Loading Pipeline — High-Level API
// ===========================================================================

/// Phase 7.4: Create a GPU texture from raw RGBA8 pixel data in CPU memory.
/// Performs staging buffer creation, GPU image allocation, layout transitions,
/// buffer-to-image copy, and optional mipmap generation — all in one call.
///
/// pixel_data: pointer to RGBA8 pixel bytes (width * height * 4).
/// generate_mips: 1 = generate full mip chain, 0 = single level.
/// Returns: texture handle (> 0), or 0 on failure.
pub fn texture_create(app: Int, pixel_data: Int, width: Int, height: Int, generate_mips: Int) -> Int
  requires: app != 0
  requires: pixel_data != 0
  requires: width > 0
  requires: height > 0
{
  let dev = unsafe { xvk_get_device(app) };
  let phys = unsafe { xvk_get_physical_device(app) };
  let pool = unsafe { xvk_get_command_pool(app) };
  let queue = unsafe { xvk_get_graphics_queue(app) };
  return unsafe { xvk_texture_create(dev, phys, pool, queue, pixel_data, width as Int32, height as Int32, generate_mips as Int32) };
}

/// Phase 7.4: Get the Vulkan image handle from a texture.
pub fn texture_get_image(texture: Int) -> Int
  requires: texture != 0
{
  return unsafe { xvk_texture_get_image(texture) };
}

/// Phase 7.4: Get the Vulkan image view handle from a texture.
pub fn texture_get_image_view(texture: Int) -> Int
  requires: texture != 0
{
  return unsafe { xvk_texture_get_image_view(texture) };
}

/// Phase 7.4: Get the Vulkan sampler handle from a texture.
pub fn texture_get_sampler(texture: Int) -> Int
  requires: texture != 0
{
  return unsafe { xvk_texture_get_sampler(texture) };
}

/// Phase 7.4: Get texture width in pixels.
pub fn texture_get_width(texture: Int) -> Int
  requires: texture != 0
{
  return unsafe { xvk_texture_get_width(texture) } as Int;
}

/// Phase 7.4: Get texture height in pixels.
pub fn texture_get_height(texture: Int) -> Int
  requires: texture != 0
{
  return unsafe { xvk_texture_get_height(texture) } as Int;
}

/// Phase 7.4: Get texture mip level count.
pub fn texture_get_mip_levels(texture: Int) -> Int
  requires: texture != 0
{
  return unsafe { xvk_texture_get_mip_levels(texture) } as Int;
}

/// Phase 7.4: Destroy a texture and all associated Vulkan resources.
pub fn texture_destroy(app: Int, texture: Int)
  requires: app != 0
  requires: texture != 0
{
  let dev = unsafe { xvk_get_device(app) };
  unsafe { xvk_texture_destroy(dev, texture); }
}

// ===========================================================================
// Phase 8.1: Debug Validation Message Capture — High-Level API
// ===========================================================================

/// Create a debug utils messenger that captures validation layer messages.
/// severity_mask: VkDebugUtilsMessageSeverityFlagsEXT (0x0F = all severities)
/// type_mask:     VkDebugUtilsMessageTypeFlagsEXT (0x1F = all types)
/// Returns: messenger handle, or 0 on failure.
pub fn debug_messenger_create(app: Int, severity_mask: Int, type_mask: Int) -> Int
{
  return unsafe { xvk_create_debug_messenger_default(app, severity_mask as Int32, type_mask as Int32) };
}

/// Get captured validation messages. Returns Vec[Int] of message string pointers.
/// Each Int is a pointer to a NUL-terminated C string.
/// Messages are in chronological order (oldest first), up to 64 captured.
pub fn debug_get_messages() -> Vec[Int]
{
  let result = Vec[Int]::new();
  // buf layout: [0..3] = count (Int32), [4..] = message pointers (64 x 8 bytes)
  let buf = unsafe { xvk_alloc(4 + 64 * 8) };
  if buf == 0 { return result; }
  let count: Int32 = unsafe { xvk_get_validation_messages(buf, buf + 4) };
  if count <= 0 { unsafe { xvk_free(buf); }; return result; }
  let cnt = count as Int;
  let i = 0;
  while i < cnt {
    let msg_ptr = unsafe { xvk_read_u64(buf + 4, 8 * i) };
    if msg_ptr != 0 {
      result.push(msg_ptr);
    }
    i = i + 1;
  }
  unsafe { xvk_free(buf); }
  return result;
}

/// Clear all captured validation messages.
pub fn debug_clear_messages() {
  unsafe { xvk_clear_validation_messages(); }
}

// ===========================================================================
// Phase 8.3: Font / Text Rendering — High-Level API
// ===========================================================================

/// Create a font from a built-in 8x13 console font, scaled to px_height.
/// font_data can be 0 to use the built-in font. Returns font handle.
pub fn font_create(px_height: Float32) -> Int
{
  return unsafe { xvk_font_create(0, 0, px_height) };
}

/// Get the number of glyphs in the font atlas (95 for ASCII 32-126).
pub fn font_get_glyph_count(font: Int) -> Int
  requires: font != 0
{
  return unsafe { xvk_font_get_glyph_count(font) } as Int;
}

/// Get glyph metrics for a codepoint. out_glyph must point to a 56-byte buffer.
/// Returns 1 on success.
pub fn font_get_glyph(font: Int, codepoint: Int, out_glyph: Int) -> Int
  requires: font != 0
  requires: out_glyph != 0
{
  return unsafe { xvk_font_get_glyph(font, codepoint as Int32, out_glyph) } as Int;
}

/// Get the atlas pixel buffer (R8 grayscale, atlas_w * atlas_h bytes).
/// out_width and out_height must point to 4-byte Int32 buffers.
/// Returns pointer to pixel data (owned by font, valid until font destroyed).
pub fn font_get_atlas_pixels(font: Int, out_width: Int, out_height: Int) -> Int
  requires: font != 0
{
  return unsafe { xvk_font_get_atlas_pixels(font, out_width, out_height) };
}

/// Get font metrics: out_metrics must point to float[3] buffer.
/// Receives {ascender, descender, line_gap} in pixels.
pub fn font_get_metrics(font: Int, out_metrics: Int)
  requires: font != 0
  requires: out_metrics != 0
{
  unsafe { xvk_font_get_metrics(font, out_metrics); }
}

/// Measure the pixel width of a text string.
pub fn font_measure_text(font: Int, text: Str) -> Float32
  requires: font != 0
{
  return unsafe { xvk_font_measure_text(font, text) };
}

/// Destroy a font and free all memory.
pub fn font_destroy(font: Int)
  requires: font != 0
{
  unsafe { xvk_font_destroy(font); }
}


