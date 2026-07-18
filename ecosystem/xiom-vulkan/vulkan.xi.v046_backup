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
// FFI declarations — existing API (all pointers converted to Int handles)
// ===========================================================================
extern "C" {
  fn xvk_app_create(title: Str, width: Int32, height: Int32) -> Int;
  fn xvk_app_destroy(app: Int);
  fn xvk_app_valid(app: Int) -> Int32;
  fn xvk_last_error() -> Str;
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

  // Phase 1 — Buffers (pointers → Int handles)
  fn xvk_buffer_create(app: Int, size: Int, usage: Int32, memory: Int32) -> Int;
  fn xvk_buffer_destroy(app: Int, buf: Int);
  fn xvk_buffer_size(app: Int, buf: Int) -> Int;
  fn xvk_buffer_map(app: Int, buf: Int) -> Int;
  fn xvk_buffer_unmap(app: Int, buf: Int);
  fn xvk_buffer_write(app: Int, buf: Int, offset: Int, data: Int, data_size: Int);
  fn xvk_buffer_read(app: Int, buf: Int, offset: Int, out: Int, out_size: Int);

  // Phase 1 — Images & Views
  fn xvk_image_create_2d(app: Int, width: Int32, height: Int32, format: Int32, usage: Int32, mip_levels: Int32) -> Int;
  fn xvk_image_destroy(app: Int, img: Int);
  fn xvk_image_view_create(app: Int, img: Int, format: Int32, aspect: Int32) -> Int;
  fn xvk_image_view_destroy(app: Int, view: Int);

  // Phase 1 — Samplers
  fn xvk_sampler_create(app: Int, filter: Int32, address_u: Int32, address_v: Int32, mip_mode: Int32, max_lod: Float32) -> Int;
  fn xvk_sampler_destroy(app: Int, sampler: Int);

  // Phase 1 — Shader Modules (code ptr → Int)
  fn xvk_shader_create(app: Int, code: Int, code_size: Int32) -> Int;
  fn xvk_shader_create_named(app: Int, name: Str) -> Int;
  fn xvk_shader_destroy(app: Int, shader: Int);

  // Phase 1 — Pipeline Layouts & Descriptor Set Layouts (ptrs → Int)
  fn xvk_pipeline_layout_create(app: Int, push_size: Int32, push_stages: Int32, desc_layout_count: Int32, desc_layouts: Int) -> Int;
  fn xvk_pipeline_layout_destroy(app: Int, layout: Int);
  fn xvk_desc_set_layout_create(app: Int, bindings: Int, count: Int32) -> Int;
  fn xvk_desc_set_layout_destroy(app: Int, layout: Int);

  // Phase 1 — Pipelines (ptrs → Int)
  fn xvk_pipeline_create_graphics(app: Int, topology: Int32, cull_mode: Int32, depth_test: Int32, depth_write: Int32, blend_enable: Int32, vertex_shader: Int, fragment_shader: Int, layout: Int, render_pass: Int, bindings: Int, binding_count: Int32, attributes: Int, attr_count: Int32) -> Int;
  fn xvk_pipeline_destroy(app: Int, pipeline: Int);
  fn xvk_pipeline_create_compute(app: Int, shader: Int, layout: Int) -> Int;
  fn xvk_compute_dispatch(app: Int, pipeline: Int, layout: Int, x: Int32, y: Int32, z: Int32);

  // Phase 1 — Descriptor Pool & Sets (ptrs → Int)
  fn xvk_desc_pool_create(app: Int, pool_sizes: Int, size_count: Int32, max_sets: Int32) -> Int;
  fn xvk_desc_pool_destroy(app: Int, pool: Int);
  fn xvk_desc_set_allocate(app: Int, pool: Int, layout: Int) -> Int;
  fn xvk_desc_set_free(app: Int, pool: Int, set: Int);
  fn xvk_desc_set_write_buffer(app: Int, set: Int, binding: Int32, buf: Int, offset: Int, range: Int, type_: Int32);
  fn xvk_desc_set_write_image(app: Int, set: Int, binding: Int32, sampler: Int, image_view: Int);

  // Phase 1 — Render Passes & Framebuffers (ptrs → Int)
  fn xvk_render_pass_create(app: Int, color_formats: Int, color_count: Int32, depth_format: Int32) -> Int;
  fn xvk_render_pass_destroy(app: Int, rp: Int);
  fn xvk_framebuffer_create(app: Int, render_pass: Int, attachments: Int, attachment_count: Int32, width: Int32, height: Int32) -> Int;
  fn xvk_framebuffer_destroy(app: Int, fb: Int);

  // Phase 1 — Command Recording
  fn xvk_cmd_bind_vertex_buffer(app: Int, binding: Int32, buf: Int, offset: Int);
  fn xvk_cmd_bind_index_buffer(app: Int, buf: Int, offset: Int, index_type: Int32);
  fn xvk_cmd_bind_pipeline(app: Int, pipeline: Int);
  fn xvk_cmd_bind_descriptor_sets(app: Int, layout: Int, first_set: Int32, sets: Int, set_count: Int32);
  fn xvk_cmd_push_constants(app: Int, layout: Int, stages: Int32, offset: Int32, size: Int32, data: Int);
  fn xvk_cmd_draw_indexed(app: Int, index_count: Int32, instance_count: Int32, first_index: Int32, vertex_offset: Int32, first_instance: Int32);
  fn xvk_cmd_draw(app: Int, vertex_count: Int32, instance_count: Int32, first_vertex: Int32, first_instance: Int32);

  // Phase 1 — Custom Render Pass
  fn xvk_begin_custom_pass(app: Int, render_pass: Int, framebuffer: Int, width: Int32, height: Int32, r: Float32, g: Float32, b: Float32) -> Int32;
  fn xvk_end_custom_pass(app: Int) -> Int32;

  // Phase 1 — Layout Transitions
  fn xvk_image_transition(app: Int, img: Int, old_layout: Int32, new_layout: Int32);

  // Phase 1 — Utility (ptr → Int)
  fn xvk_get_framebuffer_size(app: Int, out_width: Int, out_height: Int);

  // Phase 1 — Scratch marshalling helpers
  fn xvk_scratch_i32_create(count: Int) -> Int;
  fn xvk_scratch_i64_create(count: Int) -> Int;
  fn xvk_scratch_f32_create(count: Int) -> Int;
  fn xvk_scratch_u16_create(count: Int) -> Int;
  fn xvk_scratch_u32_create(count: Int) -> Int;
  fn xvk_scratch_destroy(handle: Int);
  fn xvk_scratch_set_i32(handle: Int, index: Int, value: Int32);
  fn xvk_scratch_get_i32(handle: Int, index: Int) -> Int32;
  fn xvk_scratch_set_i64(handle: Int, index: Int, value: Int);
  fn xvk_scratch_set_f32(handle: Int, index: Int, value: Float32);
  fn xvk_scratch_set_u16(handle: Int, index: Int, value: UInt16);
  fn xvk_scratch_set_u32(handle: Int, index: Int, value: UInt32);
  fn xvk_scratch_get_f32(handle: Int, index: Int) -> Float32;
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
  let wb = unsafe { xvk_scratch_i32_create(1) };
  let hb = unsafe { xvk_scratch_i32_create(1) };
  unsafe { xvk_get_framebuffer_size(app, wb, hb); }
  let w: Int32 = unsafe { xvk_scratch_get_i32(wb, 0) };
  let h: Int32 = unsafe { xvk_scratch_get_i32(hb, 0) };
  unsafe {
    xvk_scratch_destroy(wb);
    xvk_scratch_destroy(hb);
  }
  return (w as Int, h as Int);
}

// ===========================================================================
// Floats staging API — used to upload Float32 arrays to GPU
// (Vec[Float32] element reads are unreliable on v0.46; this is the production path)
// ===========================================================================
pub type Floats = { h: Int; count: Int; }

pub fn floats_create(count: Int) -> Floats {
  let h = unsafe { xvk_scratch_f32_create(count) };
  return Floats{ h: h, count: count };
}

pub fn floats_set(f: &Floats, index: Int, value: Float32)
  requires: index >= 0
  requires: index < f.count
{
  unsafe { xvk_scratch_set_f32(f.h, index, value); }
}

pub fn floats_destroy(f: Floats) {
  unsafe { xvk_scratch_destroy(f.h); }
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
// Helper — consume a Vec and copy its elements into a scratch buffer
// ===========================================================================

fn copy_to_scratch_i32(v: Vec[Int32]) -> Int {
  let n = v.len();
  let sc = unsafe { xvk_scratch_i32_create(n) };
  var i = 0;
  while i < n {
    let x: Int32 = v[i];
    unsafe { xvk_scratch_set_i32(sc, i, x); }
    i = i + 1;
  }
  return sc;
}

fn copy_to_scratch_i64(v: Vec[Int]) -> Int {
  let n = v.len();
  let sc = unsafe { xvk_scratch_i64_create(n) };
  var i = 0;
  while i < n {
    let x: Int = v[i];
    unsafe { xvk_scratch_set_i64(sc, i, x); }
    i = i + 1;
  }
  return sc;
}

fn copy_to_scratch_u16(v: Vec[UInt16]) -> Int {
  let n = v.len();
  let sc = unsafe { xvk_scratch_u16_create(n) };
  var i = 0;
  while i < n {
    let x: UInt16 = v[i];
    unsafe { xvk_scratch_set_u16(sc, i, x); }
    i = i + 1;
  }
  return sc;
}

fn copy_to_scratch_u32(v: Vec[UInt32]) -> Int {
  let n = v.len();
  let sc = unsafe { xvk_scratch_u32_create(n) };
  var i = 0;
  while i < n {
    let x: UInt32 = v[i];
    unsafe { xvk_scratch_set_u32(sc, i, x); }
    i = i + 1;
  }
  return sc;
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

pub fn buffer_write_f32(app: Int, buf: Int, offset: Int, f: &Floats)
  requires: app != 0
{
  let sz = f.count * 4;
  unsafe { xvk_buffer_write(app, buf, offset, f.h, sz); }
}

pub fn buffer_read_float(app: Int, buf: Int, offset: Int, count: Int) -> Vec[Float32] {
  let sc = unsafe { xvk_scratch_f32_create(count) };
  unsafe { xvk_buffer_read(app, buf, offset, sc, count * 4); }
  var out: Vec[Float32] = [];
  var i = 0;
  while i < count {
    let v = unsafe { xvk_scratch_get_f32(sc, i) };
    out.push(v);
    i = i + 1;
  }
  unsafe { xvk_scratch_destroy(sc); }
  return out;
}

pub fn buffer_write_float(app: Int, buf: Int, offset: Int, data: Vec[Float32]) {
  // Deprecated: use floats_create + buffer_write_f32 instead.
  // This shim is retained for backward compatibility with existing callers
  // that have NOT yet been migrated to the Floats staging API.
  // Under v0.46 Vec[Float32] element reads may be unreliable; prefer the
  // Floats-based buffer_write_f32 path for production GPU-visible data.
  var f = floats_create(data.len());
  var i = 0;
  while i < data.len() {
    floats_set(&f, i, data[i]);
    i = i + 1;
  }
  buffer_write_f32(app, buf, offset, &f);
  floats_destroy(f);
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
  let sc = copy_to_scratch_u32(code);
  let byte_size = code.len() * 4;
  let h = unsafe { xvk_shader_create(app, sc, byte_size as Int32) };
  unsafe { xvk_scratch_destroy(sc); }
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
  let sc = copy_to_scratch_i64(desc_layouts);
  let h = unsafe { xvk_pipeline_layout_create(app, push_size as Int32, push_stages as Int32, desc_layouts.len() as Int32, sc) };
  unsafe { xvk_scratch_destroy(sc); }
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
  let sc = copy_to_scratch_i32(bindings);
  let h = unsafe { xvk_desc_set_layout_create(app, sc, bindings.len() as Int32) };
  unsafe { xvk_scratch_destroy(sc); }
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
  let bs = copy_to_scratch_i32(bindings);
  let at = copy_to_scratch_i32(attributes);
  let h = unsafe {
    xvk_pipeline_create_graphics(
      app, topology as Int32, cull_mode as Int32,
      bool_to_i32(depth_test), bool_to_i32(depth_write), bool_to_i32(blend),
      vert_shader, frag_shader, layout, render_pass,
      bs, bindings.len() as Int32,
      at, attributes.len() as Int32
    )
  };
  unsafe { xvk_scratch_destroy(bs); }
  unsafe { xvk_scratch_destroy(at); }
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
  let sc = copy_to_scratch_i32(pool_sizes);
  let h = unsafe { xvk_desc_pool_create(app, sc, pool_sizes.len() as Int32, max_sets as Int32) };
  unsafe { xvk_scratch_destroy(sc); }
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
  let sc = copy_to_scratch_i32(color_formats);
  let h = unsafe { xvk_render_pass_create(app, sc, color_formats.len() as Int32, depth_format as Int32) };
  unsafe { xvk_scratch_destroy(sc); }
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
  let sc = copy_to_scratch_i64(attachments);
  let h = unsafe { xvk_framebuffer_create(app, render_pass, sc, attachments.len() as Int32, width as Int32, height as Int32) };
  unsafe { xvk_scratch_destroy(sc); }
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
  unsafe { xvk_cmd_bind_vertex_buffer(app, binding as Int32, buf, offset); }
}

pub fn cmd_bind_index_buffer(app: Int, buf: Int, offset: Int, index_type: Int)
  requires: app != 0
{
  unsafe { xvk_cmd_bind_index_buffer(app, buf, offset, index_type as Int32); }
}

pub fn cmd_bind_pipeline(app: Int, pipeline: Int)
  requires: app != 0
{
  unsafe { xvk_cmd_bind_pipeline(app, pipeline); }
}

pub fn cmd_bind_descriptor_sets(app: Int, layout: Int, first_set: Int, sets: Vec[Int])
  requires: app != 0
{
  let sc = copy_to_scratch_i64(sets);
  unsafe { xvk_cmd_bind_descriptor_sets(app, layout, first_set as Int32, sc, sets.len() as Int32); }
  unsafe { xvk_scratch_destroy(sc); }
}

pub fn cmd_push_constants_float(app: Int, layout: Int, stages: Int, offset: Int, data: Vec[Float32])
  requires: app != 0
{
  let sz = data.len() * 4;
  // Build a temporary Floats staging buffer from the Vec
  var f = floats_create(data.len());
  var idx = 0;
  while idx < data.len() {
    floats_set(&f, idx, data[idx]);
    idx = idx + 1;
  }
  unsafe { xvk_cmd_push_constants(app, layout, stages as Int32, offset as Int32, sz as Int32, f.h); }
  floats_destroy(f);
}

pub fn cmd_draw_indexed(app: Int, index_count: Int, instance_count: Int, first_index: Int, vertex_offset: Int, first_instance: Int)
  requires: app != 0
{
  unsafe { xvk_cmd_draw_indexed(app, index_count as Int32, instance_count as Int32, first_index as Int32, vertex_offset as Int32, first_instance as Int32); }
}

pub fn cmd_draw(app: Int, vertex_count: Int, instance_count: Int, first_vertex: Int, first_instance: Int)
  requires: app != 0
{
  unsafe { xvk_cmd_draw(app, vertex_count as Int32, instance_count as Int32, first_vertex as Int32, first_instance as Int32); }
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
