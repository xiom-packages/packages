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
// API subset (pilot): version, a headless frame (window + text -> draw-data
// vertex/index counts), an empty frame, and determinism.  Widgets, tables,
// draw-list APIs, and GLFW/Vulkan backends are Phase 2 (ROADMAP.md).

module xiom.imgui

use xiom.ffi;

extern "C" {
  fn imguiprobe_version() -> Int32;
  fn imguiprobe_version_str() -> *UInt8;
  fn imguiprobe_frame(out_vertices: *UInt8, out_indices: *UInt8, out_cmd_lists: *UInt8) -> Int32;
  fn imguiprobe_empty_frame(out_cmd_lists: *UInt8) -> Int32;
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
