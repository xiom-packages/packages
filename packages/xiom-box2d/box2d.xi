// XIOM -- xiom.box2d: Box2D v3.1.1 physics bindings (vendored C).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored C path (the sqlite/lzfse pattern).  The upstream v3.1.1
// sources are vendored unmodified in `vendor/` (flat layout, so the quoted
// "box2d/..." includes resolve against each file's own directory) and are
// compiled into the test binary with --c-source (port.args.json).  No system
// library, no DLL, no SDK.
//
// The module calls a small integer-only C bridge (src/box2d_bridge.c) that
// owns the float/struct ABI internally; values cross the boundary as
// thousandths (milli).  All `unsafe`/`extern "C"` live in this single
// module (G5); no malloc/free (B-05) -- out-params use XIOM-owned slots.
//
// G2 pin (SPEC.md): upstream tag v3.1.1 archive SHA256 + per-file SHA256
// table + MIT license.
//
// API subset (pilot): version, default-world gravity, a resting-drop
// simulation (static ground + dynamic box), and an impulse->velocity check.
// Broad-phase queries, joint variety, callbacks, and real content are
// Phase 2 (ROADMAP.md).

module xiom.box2d

use xiom.ffi;

extern "C" {
  fn b2probe_version() -> Int32;
  fn b2probe_gravity(out_gx_milli: *UInt8, out_gy_milli: *UInt8) -> Int32;
  fn b2probe_drop(start_y_milli: Int32, steps: Int32, out_final_y_milli: *UInt8, out_awake: *UInt8) -> Int32;
  fn b2probe_impulse(impulse_milli: Int32, out_vx_milli: *UInt8) -> Int32;
}

/// Default number of 60 Hz steps used by the drop probes.
pub const B2_DEFAULT_STEPS: Int = 300;

pub type B2Gravity = {
  gx_milli: Int;
  gy_milli: Int;
}

pub type B2DropResult = {
  final_y_milli: Int;
  awake: Bool;
}

/// Packed upstream version: major << 16 | minor << 8 | revision.
/// Complexity: O(1).
pub fn b2_version() -> Int
  requires: true
{
  unsafe { return b2probe_version() as Int; }
}

/// Decode a packed version into "major.minor.revision".
/// Complexity: O(1).
pub fn b2_version_str(v: Int) -> Str
  requires: v >= 0
{
  let major = v >> 16;
  let minor = (v >> 8) & 255;
  let revision = v & 255;
  return b2_i2s(major) + "." + b2_i2s(minor) + "." + b2_i2s(revision);
}

/// Default world gravity in thousandths (Box2D default: 0, -10000).
/// Complexity: O(1).
pub fn b2_gravity() -> Result[B2Gravity, Str]
  requires: true
{
  var f_gx = b2_slot();
  var f_gy = b2_slot();
  let rc = unsafe { b2probe_gravity(f_gx.as_mut_ptr(), f_gy.as_mut_ptr()) as Int };
  if rc != 0 {
    return Err("box2d: gravity probe rc=" + b2_i2s(rc));
  }
  return Ok(B2Gravity{ gx_milli: b2_slot_read(&f_gx); gy_milli: b2_slot_read(&f_gy); });
}

/// Drop a 1x1 dynamic box from `start_y_milli` onto a static ground (top
/// surface at y = 0) and step `steps` times at 60 Hz; returns the final
/// body-center y (milli) and the awake flag.
/// Complexity: O(steps).
pub fn b2_drop(start_y_milli: Int, steps: Int) -> Result[B2DropResult, Str]
  requires: start_y_milli > 0
  requires: steps > 0
{
  var f_final = b2_slot();
  var f_awake = b2_slot();
  let rc = unsafe { b2probe_drop(start_y_milli as Int32, steps as Int32, f_final.as_mut_ptr(), f_awake.as_mut_ptr()) as Int };
  if rc != 0 {
    return Err("box2d: drop probe rc=" + b2_i2s(rc));
  }
  return Ok(B2DropResult{ final_y_milli: b2_slot_read(&f_final); awake: b2_slot_read(&f_awake) != 0 });
}

/// Apply a horizontal impulse (milli N*s) to a free 1x1 dynamic box and
/// return the x velocity (milli m/s) after one step (dv = J / m).
/// Complexity: O(1).
pub fn b2_impulse(impulse_milli: Int) -> Result[Int, Str]
  requires: impulse_milli > 0
{
  var f_vx = b2_slot();
  let rc = unsafe { b2probe_impulse(impulse_milli as Int32, f_vx.as_mut_ptr()) as Int };
  if rc != 0 {
    return Err("box2d: impulse probe rc=" + b2_i2s(rc));
  }
  return Ok(b2_slot_read(&f_vx));
}

// ---- internals -----------------------------------------------------------

// 8-byte zeroed out-param slot owned by XIOM (no malloc/free in confined
// blocks; finding B-05).
fn b2_slot() -> Vec[UInt8]
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
fn b2_slot_read(slot: &Vec[UInt8]) -> Int
  requires: true
{
  let raw = ffi.ptr_read_u32_le(slot.as_mut_ptr());
  if raw >= 2147483648 {
    return raw - 4294967296;
  }
  return raw;
}

fn b2_i2s(n: Int) -> Str
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
