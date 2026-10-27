// XIOM -- xiom.imgui: Dear ImGui v1.92.9b bindings (vendored C++ core).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored C++ path (the ozz/sqlite pattern).  The upstream core is
// vendored unmodified in `vendor/` (flat layout; every core include is
// same-directory quoted) and compiled into the test binary with --c-source
// (port.args.json).  No precompiled objects, no SDK, no backend: the probe
// is headless.
//
// The module calls a small integer-only C++ bridge (src/imgui_bridge.cpp)
// that owns the C++ API internally.  All `unsafe`/`extern "C"` live in this
// single module (G5); no malloc/free (B-05) -- out-params use XIOM-owned
// slots.
//
// G2 pin (SPEC.md): upstream tag v1.92.9b archive SHA256 + per-file SHA256
// table + MIT license.
//
// API subset (pilot + 0.3.0): version, a headless frame (window + text ->
// draw-data vertex/index counts), an empty frame, determinism, and (0.3.0)
// long-lived context handles: imgui_context_create/destroy plus per-handle
// frames that keep window state across separate XIOM calls.  Widgets,
// tables, draw-list APIs, and GLFW/Vulkan backends are Phase 2 (ROADMAP.md).

module xiom.imgui

use xiom.ffi;

extern "C" {
  fn imguiprobe_version() -> Int32;
  fn imguiprobe_version_str() -> *UInt8;
  fn imguiprobe_frame(out_vertices: *UInt8, out_indices: *UInt8, out_cmd_lists: *UInt8) -> Int32;
  fn imguiprobe_empty_frame(out_cmd_lists: *UInt8) -> Int32;
  fn imguiprobe_context_create(width: Int32, height: Int32) -> Int32;
  fn imguiprobe_context_frame(handle: Int32, out_vertices: *UInt8, out_indices: *UInt8, out_cmd_lists: *UInt8) -> Int32;
  fn imguiprobe_context_destroy(handle: Int32) -> Int32;
  fn imguiprobe_context_count() -> Int32;
  fn imguiprobe_context_frames(handle: Int32) -> Int32;

  // 0.4.0 backend tier (SDL3 platform + Vulkan renderer, engine-owned).
  fn imguibridge_backend_create() -> Int32;
  fn imguibridge_backend_count() -> Int32;
  fn imguibridge_backend_frames(handle: Int32) -> Int32;
  fn imguibridge_backend_error() -> *UInt8;
  fn imguibridge_backend_sdl3_available() -> Int32;
  fn imguibridge_backend_sdl3_init(handle: Int32, window: Int, mode: Int32) -> Int32;
  fn imguibridge_backend_sdl3_process_event(handle: Int32, event_ptr: Int) -> Int32;
  fn imguibridge_backend_vulkan_init(handle: Int32, instance: Int, physical_device: Int, device: Int, queue: Int, queue_family: Int32, descriptor_pool: Int, render_pass: Int, api_version: UInt32, min_image_count: Int32, image_count: Int32, msaa: Int32, subpass: Int32) -> Int32;
  fn imguibridge_backend_frame(handle: Int32, out_vertices: *UInt8, out_indices: *UInt8, out_cmd_lists: *UInt8) -> Int32;
  fn imguibridge_backend_vulkan_render(handle: Int32, draw_data: Int, command_buffer: Int) -> Int32;
  fn imguibridge_backend_draw_data(handle: Int32) -> Int;
  fn imguibridge_backend_shutdown(handle: Int32) -> Int32;
  fn imguibridge_backend_sdl3_selftest(out_vertices: *UInt8, out_indices: *UInt8, out_cmd_lists: *UInt8) -> Int32;
}

pub type ImguiFrameStats = {
  vertices: Int;
  indices: Int;
  cmd_lists: Int;
}

/// Packed upstream version number (1.92.9b -> 19291).
/// Complexity: O(1).
pub fn imgui_version() -> Int
  requires: true
{
  unsafe { return imguiprobe_version() as Int; }
}

/// Upstream version string, e.g. "1.92.9b".
/// Complexity: O(1).
pub fn imgui_version_str() -> Str
  requires: true
{
  unsafe {
    let p = imguiprobe_version_str();
    if (p as Int) == 0 {
      return "";
    }
    return Str::from_c_str(p);
  }
}

/// Drive one headless frame containing a window with text and return the
/// draw-data stats (vertices, indices, command lists).
/// Complexity: O(frame).
pub fn imgui_frame() -> Result[ImguiFrameStats, Str]
  requires: true
{
  var f_v = imgui_slot();
  var f_i = imgui_slot();
  var f_c = imgui_slot();
  let rc = unsafe { imguiprobe_frame(f_v.as_mut_ptr(), f_i.as_mut_ptr(), f_c.as_mut_ptr()) as Int };
  if rc != 0 {
    return Err("imgui: frame probe rc=" + imgui_i2s(rc));
  }
  return Ok(ImguiFrameStats{
    vertices: imgui_slot_read(&f_v);
    indices: imgui_slot_read(&f_i);
    cmd_lists: imgui_slot_read(&f_c);
  });
}

/// Drive one empty headless frame (no windows) and return the command-list
/// count (expected 0).
/// Complexity: O(frame).
pub fn imgui_empty_frame() -> Result[Int, Str]
  requires: true
{
  var f_c = imgui_slot();
  let rc = unsafe { imguiprobe_empty_frame(f_c.as_mut_ptr()) as Int };
  if rc != 0 {
    return Err("imgui: empty frame probe rc=" + imgui_i2s(rc));
  }
  return Ok(imgui_slot_read(&f_c));
}

/// Create a long-lived headless context sized width x height (up to 4 live);
/// returns a 1-based handle.  Window/context state persists across calls.
/// Complexity: O(context).
pub fn imgui_context_create(width: Int, height: Int) -> Result[Int, Str]
  requires: width > 0
  requires: height > 0
{
  let h = unsafe { imguiprobe_context_create(width as Int32, height as Int32) as Int };
  if h == 0 {
    return Err("imgui: context_create failed (no free slot or bad size)");
  }
  return Ok(h);
}

/// Drive one frame on a live context handle ("xiom-context" window + text);
/// returns the draw-data stats.  ImGui hides a window on the frame that
/// creates it, so the first frame reports zero command lists.
/// Complexity: O(frame).
pub fn imgui_context_frame(handle: Int) -> Result[ImguiFrameStats, Str]
  requires: handle > 0
{
  var f_v = imgui_slot();
  var f_i = imgui_slot();
  var f_c = imgui_slot();
  let rc = unsafe { imguiprobe_context_frame(handle as Int32, f_v.as_mut_ptr(), f_i.as_mut_ptr(), f_c.as_mut_ptr()) as Int };
  if rc != 0 {
    return Err("imgui: context_frame rc=" + imgui_i2s(rc));
  }
  return Ok(ImguiFrameStats{
    vertices: imgui_slot_read(&f_v);
    indices: imgui_slot_read(&f_i);
    cmd_lists: imgui_slot_read(&f_c);
  });
}

/// Destroy a live context handle; false when the handle is invalid or was
/// already destroyed.  Complexity: O(context).
pub fn imgui_context_destroy(handle: Int) -> Bool
  requires: true
{
  return unsafe { (imguiprobe_context_destroy(handle as Int32) as Int) != 0 };
}

/// Number of live context handles (registry bookkeeping).
/// Complexity: O(1).
pub fn imgui_context_count() -> Int
  requires: true
{
  return unsafe { imguiprobe_context_count() as Int };
}

/// Frames driven on a handle so far; -1 for invalid handles.
/// Complexity: O(1).
pub fn imgui_context_frames(handle: Int) -> Int
  requires: true
{
  return unsafe { imguiprobe_context_frames(handle as Int32) as Int };
}

// ---- 0.4.0 backends (SDL3 platform + Vulkan renderer) -------------------

/// Latest bridge error string (empty when the last call succeeded).
/// Complexity: O(1).
pub fn imgui_backend_last_error() -> Str
  requires: true
{
  unsafe {
    let p = imguibridge_backend_error();
    if (p as Int) == 0 {
      return "";
    }
    return Str::from_c_str(p);
  }
}

/// Create a backend context (up to 2 live); returns a 1-based handle.
/// Complexity: O(context).
pub fn imgui_backend_create() -> Result[Int, Str]
  requires: true
{
  let h = unsafe { imguibridge_backend_create() as Int };
  if h == 0 {
    return Err("imgui: backend_create failed (no free slot)");
  }
  return Ok(h);
}

/// Number of live backend contexts.
/// Complexity: O(1).
pub fn imgui_backend_count() -> Int
  requires: true
{
  return unsafe { imguibridge_backend_count() as Int };
}

/// Frames driven on a backend handle; -1 for invalid handles.
/// Complexity: O(1).
pub fn imgui_backend_frames(handle: Int) -> Int
  requires: true
{
  return unsafe { imguibridge_backend_frames(handle as Int32) as Int };
}

/// True when an SDL3 video driver is present (the backend tests can run).
/// Complexity: O(1).
pub fn imgui_backend_sdl3_available() -> Bool
  requires: true
{
  return unsafe { (imguibridge_backend_sdl3_available() as Int) != 0 };
}

/// Attach the SDL3 platform backend to an engine-owned SDL_Window.
/// `for_vulkan` selects ImGui_ImplSDL3_InitForVulkan; false selects
/// InitForOther.  The engine keeps ownership of the window.
/// Complexity: O(1).
pub fn imgui_backend_sdl3_init(handle: Int, window: Int, for_vulkan: Bool) -> Result[Bool, Str]
  requires: handle > 0
{
  var mode: Int32 = 0;
  if for_vulkan {
    mode = 1;
  }
  let rc = unsafe { imguibridge_backend_sdl3_init(handle as Int32, window, mode) as Int };
  if rc != 0 {
    return Err("imgui: sdl3 backend init rc=" + imgui_i2s(rc) + " (" + imgui_backend_last_error() + ")");
  }
  return Ok(true);
}

/// Feed one engine-owned SDL_Event (pointer) to the platform backend.
/// Complexity: O(event).
pub fn imgui_backend_sdl3_process_event(handle: Int, event_ptr: Int) -> Result[Bool, Str]
  requires: handle > 0
{
  let rc = unsafe { imguibridge_backend_sdl3_process_event(handle as Int32, event_ptr) as Int };
  if rc != 0 {
    return Err("imgui: sdl3 process_event rc=" + imgui_i2s(rc) + " (" + imgui_backend_last_error() + ")");
  }
  return Ok(true);
}

/// Attach the Vulkan renderer backend to an engine-owned device/queue and
/// render pass.  All handles are 64-bit values owned by the engine; the
/// descriptor pool must meet the backend minimums.  `api_version` 0 means
/// Vulkan 1.1.
/// Complexity: O(1).
pub fn imgui_backend_vulkan_init(
    handle: Int,
    instance: Int,
    physical_device: Int,
    device: Int,
    queue: Int,
    queue_family: Int,
    descriptor_pool: Int,
    render_pass: Int,
    api_version: Int,
    min_image_count: Int,
    image_count: Int,
    msaa: Int,
    subpass: Int) -> Result[Bool, Str]
  requires: handle > 0
{
  let rc = unsafe {
    imguibridge_backend_vulkan_init(handle as Int32, instance, physical_device, device,
      queue, queue_family as Int32, descriptor_pool, render_pass,
      api_version as UInt32, min_image_count as Int32, image_count as Int32,
      msaa as Int32, subpass as Int32) as Int
  };
  if rc != 0 {
    return Err("imgui: vulkan backend init rc=" + imgui_i2s(rc) + " (" + imgui_backend_last_error() + ")");
  }
  return Ok(true);
}

/// Drive one engine-owned backend frame (platform + renderer NewFrame) with
/// the current probe window; returns draw-data stats.
/// Complexity: O(frame).
pub fn imgui_backend_frame(handle: Int) -> Result[ImguiFrameStats, Str]
  requires: handle > 0
{
  var f_v = imgui_slot();
  var f_i = imgui_slot();
  var f_c = imgui_slot();
  let rc = unsafe { imguibridge_backend_frame(handle as Int32, f_v.as_mut_ptr(), f_i.as_mut_ptr(), f_c.as_mut_ptr()) as Int };
  if rc != 0 {
    return Err("imgui: backend_frame rc=" + imgui_i2s(rc) + " (" + imgui_backend_last_error() + ")");
  }
  return Ok(ImguiFrameStats{
    vertices: imgui_slot_read(&f_v);
    indices: imgui_slot_read(&f_i);
    cmd_lists: imgui_slot_read(&f_c);
  });
}

/// Pointer to the last frame's ImDrawData (0 before the first frame).
/// Complexity: O(1).
pub fn imgui_backend_draw_data(handle: Int) -> Int
  requires: handle > 0
{
  return unsafe { imguibridge_backend_draw_data(handle as Int32) as Int };
}

/// Record the last frame's draw data into the engine command buffer.
/// Complexity: O(frame).
pub fn imgui_backend_vulkan_render(handle: Int, draw_data: Int, command_buffer: Int) -> Result[Bool, Str]
  requires: handle > 0
{
  let rc = unsafe { imguibridge_backend_vulkan_render(handle as Int32, draw_data, command_buffer) as Int };
  if rc != 0 {
    return Err("imgui: vulkan render rc=" + imgui_i2s(rc) + " (" + imgui_backend_last_error() + ")");
  }
  return Ok(true);
}

/// Shut down the backends and destroy the context; false for bad handles.
/// Complexity: O(context).
pub fn imgui_backend_shutdown(handle: Int) -> Bool
  requires: true
{
  return unsafe { (imguibridge_backend_shutdown(handle as Int32) as Int) != 0 };
}

/// Self-test: a hidden SDL3 window + the real platform backend + two frames.
/// Complexity: O(frame).
pub fn imgui_backend_sdl3_selftest() -> Result[ImguiFrameStats, Str]
  requires: true
{
  var f_v = imgui_slot();
  var f_i = imgui_slot();
  var f_c = imgui_slot();
  let rc = unsafe { imguibridge_backend_sdl3_selftest(f_v.as_mut_ptr(), f_i.as_mut_ptr(), f_c.as_mut_ptr()) as Int };
  if rc != 0 {
    return Err("imgui: sdl3 selftest rc=" + imgui_i2s(rc) + " (" + imgui_backend_last_error() + ")");
  }
  return Ok(ImguiFrameStats{
    vertices: imgui_slot_read(&f_v);
    indices: imgui_slot_read(&f_i);
    cmd_lists: imgui_slot_read(&f_c);
  });
}

// ---- internals -----------------------------------------------------------

// 8-byte zeroed out-param slot owned by XIOM (no malloc/free in confined
// blocks; finding B-05).
fn imgui_slot() -> Vec[UInt8]
  requires: true
{
  var slot: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 8 {
    slot.push(0 as UInt8);
    i = i + 1;
  }
  return slot;
}

// Signed 32-bit read of the low word (the bridge writes C `int`).
fn imgui_slot_read(slot: &Vec[UInt8]) -> Int
  requires: true
{
  let raw = ffi.ptr_read_u32_le(slot.as_mut_ptr());
  if raw >= 2147483648 {
    return raw - 4294967296;
  }
  return raw;
}

fn imgui_i2s(n: Int) -> Str
  requires: n >= 0
{
  if n == 0 { return "0"; }
  var val = n;
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  return buf;
}
