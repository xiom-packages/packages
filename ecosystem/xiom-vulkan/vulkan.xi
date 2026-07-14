// XIOM — Vulkan Bindings (C Bridge Wrapper)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations and safe wrappers for the xvk C bridge library.
module xiom.vulkan

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
