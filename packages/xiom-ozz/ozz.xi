// XIOM -- xiom.ozz: Ozz-Animation bindings (vendored 0.16.0 amalgamations).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored C++ path. ozz-animation is a C++ library with no C API and
// (like zstd) needs an amalgamation because the xiom link line has no
// include-path passthrough.  Two generated translation units are vendored
// (upstream-style combine.py, roots include/ + src/; see SPEC.md):
//   vendor/ozz_all.cpp    -- base + math + animation runtime + offline
//                            skeleton builder, inlined into one TU
//   vendor/ozz_bridge.cpp -- our extern "C" bridge (inlined ozz headers)
// and compiled into the test binary via --c-source (port.args.json).  No
// system library, no SDK, nothing built separately.
//
// G5 confinement: this is the ONE module in the package with `extern "C"`;
// every foreign call is wrapped here.
//
// G2 pin (SPEC.md): upstream tag 0.16.0 archive SHA256 + generated TU hashes
// + MIT license.
//
// API subset (pilot): math primitives (Float3 dot/cross, quaternion axis
// rotation), offline RawSkeleton -> runtime Skeleton construction, and a
// LocalToModelJob run verifying model-space translations.  Animation sampling
// with real assets is Phase 2 (ROADMAP.md).

module xiom.ozz

extern "C" {
  fn ozz_probe_math() -> Int32;
  fn ozz_probe_skeleton() -> Int32;
  fn ozz_probe_local_to_model() -> Int32;
  fn ozz_probe_all() -> Int32;
}

/// Sentinel used by ozz joints: no parent.
pub const OZZ_NO_PARENT: Int = -1;

/// Math primitives smoke: Float3 dot/cross + quaternion axis rotation.
/// Complexity: O(1).
pub fn ozz_math_ok() -> Bool
  requires: true
{
  unsafe { return (ozz_probe_math() as Int) != 0; }
}

/// Offline SkeletonBuilder -> runtime Skeleton smoke (2-joint hierarchy).
/// Complexity: O(1).
pub fn ozz_skeleton_ok() -> Bool
  requires: true
{
  unsafe { return (ozz_probe_skeleton() as Int) != 0; }
}

/// Runtime LocalToModelJob smoke: identity locals + one translated child.
/// Complexity: O(1).
pub fn ozz_local_to_model_ok() -> Bool
  requires: true
{
  unsafe { return (ozz_probe_local_to_model() as Int) != 0; }
}

/// Run every probe.  Ok(()) when all pass; Err lists the failed probe names.
/// Complexity: O(1).
pub fn ozz_probe() -> Result[Unit, Str]
  requires: true
{
  let mask = unsafe { ozz_probe_all() as Int };
  if mask == 0 {
    return Ok({});
  }
  var msg = "ozz: probe failures:";
  if (mask & 1) != 0 { msg = msg + " math"; }
  if (mask & 2) != 0 { msg = msg + " skeleton"; }
  if (mask & 4) != 0 { msg = msg + " local_to_model"; }
  return Err(msg);
}
