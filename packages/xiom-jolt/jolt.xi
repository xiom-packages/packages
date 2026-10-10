// XIOM -- xiom.jolt: Jolt Physics bindings (vendored v5.6.0 core).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored C++ core (the ozz/sqlite method, generated).
// `tools/combine.py` mirrors the upstream `Jolt/**` tree into `vendor/Jolt`
// with one textual transform (`#include <Jolt/...>` -> `"Jolt/..."`) and
// emits 25 per-directory TUs plus a shim that compiles the reviewable
// bridge (`src/jolt_bridge.cpp`) from the vendor root (the quoted "Jolt/..."
// includes resolve through the compiler's include stack; the xiom link line
// has no -I passthrough).  Unblocked by compiler v0.64.3 (C++17 default;
// bus item REL-20261010-1548-bindings-7).
//
// The module calls scalar-return probes (no out-param slots; B-11 family
// avoidance) that run real physics worlds: a resting drop and a velocity
// hand-off.  All `unsafe`/`extern "C"` live in this single module (G5).
//
// G2 pin (SPEC.md): upstream tag v5.6.0 + generator + generated-tree sha256.
//
// API subset (pilot): a settled drop and a one-step velocity check.
// Broad-phase queries, joint variety, character controllers, and soft
// bodies are Phase 2 (ROADMAP.md).

module xiom.jolt

extern "C" {
  fn joltprobe_drop() -> Int32;
  fn joltprobe_awake() -> Int32;
  fn joltprobe_impulse() -> Int32;
}

pub type JoltDropResult = {
  final_y_milli: Int;   // settled box-center y in milli
  awake: Bool;          // body still simulating (false = asleep at rest)
}

/// Drop a 1 m dynamic box from y=5 onto a static ground and step 300 frames
/// at 60 Hz with a single-threaded job system.
/// Complexity: O(steps).
pub fn jolt_drop() -> Result[JoltDropResult, Str]
  requires: true
{
  let rc = unsafe { joltprobe_drop() as Int };
  if rc < 0 {
    return Err("jolt: drop probe rc=" + jolt_i2s(0 - rc));
  }
  return Ok(JoltDropResult{
    final_y_milli: rc;
    awake: unsafe { joltprobe_awake() as Int } != 0;
  });
}

/// Give a free dynamic box vx = 5 m/s and return the velocity (milli) after
/// one 60 Hz step.  Complexity: O(1).
pub fn jolt_impulse_vx() -> Result[Int, Str]
  requires: true
{
  let rc = unsafe { joltprobe_impulse() as Int };
  if rc < 0 {
    return Err("jolt: impulse probe rc=" + jolt_i2s(0 - rc));
  }
  return Ok(rc);
}

// ---- internals -----------------------------------------------------------

fn jolt_i2s(n: Int) -> Str
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
