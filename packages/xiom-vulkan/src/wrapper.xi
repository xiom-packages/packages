// XIOM -- Vulkan Convenience Wrapper
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Typed convenience layer over the raw xvk C bridge API.
// Frame lifecycle guarded: end_frame requires preceding begin_frame(1).

module xiom.vulkan.wrapper

use xiom.vulkan;

pub type VulkanApp = {
  handle: Int;
  width: Int;
  height: Int;
} derive[Clone]

pub fn VulkanApp.new(title: Str, width: Int, height: Int) -> Result[VulkanApp, Str]
  requires: width > 0
  requires: height > 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let handle = create_app(title, width, height)?;
  return Ok(VulkanApp{ handle: handle, width: width, height: height });
}

pub fn VulkanApp.is_open() -> Bool {
  return !should_close(handle);
}

pub fn VulkanApp.poll() {
  poll(handle);
}

pub fn VulkanApp.begin_frame() -> Int {
  return begin_frame(handle);
}

pub fn VulkanApp.end_frame() {
  end_frame(handle);
}

pub fn VulkanApp.set_clear_color(r: Float32, g: Float32, b: Float32) {
  set_clear_color(handle, r, g, b);
}

pub fn VulkanApp.frame_2d(r: Float32, g: Float32, b: Float32) {
  poll(handle);
  set_clear_color(handle, r, g, b);
  let status = begin_frame(handle);
  if status == 1 {
    draw_triangle_2d(handle, r, g, b);
    end_frame(handle);
  }
}

pub fn VulkanApp.frame_3d(angle: Float32) {
  poll(handle);
  set_clear_color(handle, 0.05, 0.05, 0.1);
  let status = begin_frame(handle);
  if status == 1 {
    draw_cube_3d(handle, angle);
    end_frame(handle);
  }
}

pub fn VulkanApp.frame_particles(dt: Float32) {
  poll(handle);
  set_clear_color(handle, 0.02, 0.02, 0.05);
  let s = begin_frame(handle);
  if s == 1 {
    draw_particles(handle, dt);
    end_frame(handle);
  }
}

pub fn VulkanApp.close() {
  destroy_app(handle);
}
