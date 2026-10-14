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
// API subset (pilot + 0.3.0): math primitives (Float3 dot/cross, quaternion
// axis rotation), offline RawSkeleton -> runtime Skeleton construction, a
// LocalToModelJob run verifying model-space translations, and (0.3.0) the
// clip pipeline: offline RawAnimation -> AnimationBuilder -> runtime
// Animation -> SamplingJob with a context, verified against a hand-computed
// pose.  Blending/IK/archive I/O are Phase 2 (ROADMAP.md).
//
// 0.4.0 caller surface: `ozz_clip_build` builds a clip from caller-supplied
// keys (time + rotation/translation/scale per key) into package-owned bridge
// storage referenced by an opaque integer handle; `ozz_clip_sample` samples
// that clip at a caller-provided time into fresh owned pose buffers
// (per-joint rotations/translations/scales).  Bounds and handle failures are
// typed OzzError codes (OZZ_ERR_TIME / OZZ_ERR_HANDLE / ...).  Handles cross
// to C as integers and are resolved only inside the bridge (B-25); every
// out-param uses its own XIOM-owned buffer (one owned slot per out-param)
// read with plain vector indexing (B-24); no pointer casts, no bare null and
// no foreign-pointer reads (B-20/B-23).

module xiom.ozz

extern "C" {
  fn ozz_probe_math() -> Int32;
  fn ozz_probe_skeleton() -> Int32;
  fn ozz_probe_local_to_model() -> Int32;
  fn ozz_probe_clip() -> Int32;
  fn ozz_probe_caller() -> Int32;
  fn ozz_probe_all() -> Int32;
  fn xozz_clip_build(track_count: Int32, counts: *Float32, keys: *Float32,
    key_float_count: Int32, duration: Float32) -> Int64;
  fn xozz_clip_info(handle: Int64, out: *Float32, out_cap: Int32) -> Int32;
  fn xozz_clip_sample(handle: Int64, time: Float32, out: *Float32,
    out_cap: Int32) -> Int32;
  fn xozz_clip_release(handle: Int64) -> Int32;
}

/// Sentinel used by ozz joints: no parent.
pub const OZZ_NO_PARENT: Int = -1;

/// Floats per caller key: time + rotation xyzw + translation xyz + scale xyz.
pub const OZZ_KEY_FLOATS: Int = 11;

/// Floats per sampled joint: rotation xyzw + translation xyz + scale xyz.
pub const OZZ_POSE_FLOATS: Int = 10;

// --- bridge rc codes (mirror src/ozz-bridge-in.cpp; keep in sync) ----------

pub const OZZ_OK: Int = 0;
pub const OZZ_ERR_ARGS: Int = -1;
pub const OZZ_ERR_HANDLE: Int = -2;
pub const OZZ_ERR_KEYS: Int = -3;
pub const OZZ_ERR_BUILD: Int = -4;
pub const OZZ_ERR_CAPACITY: Int = -5;
pub const OZZ_ERR_TIME: Int = -6;
pub const OZZ_ERR_INTERNAL: Int = -7;

/// Typed caller-surface error: a stable `code` (OZZ_ERR_*) plus a message.
pub type OzzError = {
  code: Int;
  message: Str;
}

pub fn OzzError.new(code: Int, message: Str) -> OzzError {
  return OzzError{ code: code, message: message };
}

/// One caller key: time plus the joint-local rotation (quaternion x, y, z,
/// w), translation (x, y, z) and scale (x, y, z) in effect at that time.
pub type OzzKey = {
  time: Float32;
  rx: Float32;
  ry: Float32;
  rz: Float32;
  rw: Float32;
  tx: Float32;
  ty: Float32;
  tz: Float32;
  sx: Float32;
  sy: Float32;
  sz: Float32;
}

pub fn OzzKey.new(time: Float32, rx: Float32, ry: Float32, rz: Float32, rw: Float32,
    tx: Float32, ty: Float32, tz: Float32, sx: Float32, sy: Float32,
    sz: Float32) -> OzzKey {
  return OzzKey{ time: time, rx: rx, ry: ry, rz: rz, rw: rw, tx: tx, ty: ty,
    tz: tz, sx: sx, sy: sy, sz: sz };
}

/// One animation track: the keys of a single joint (track index == joint
/// index), sharing one time list across rotation/translation/scale.
pub type OzzTrack = {
  keys: Vec[OzzKey];
}

pub fn OzzTrack.new() -> OzzTrack {
  return OzzTrack{ keys: Vec[OzzKey].new() };
}

/// A built clip: opaque handle into the bridge-owned clip storage
/// (0 = empty).  Release with `ozz_clip_release`; other calls on a released
/// handle return OZZ_ERR_HANDLE.
pub type OzzClip = {
  handle: Int;
}

pub fn OzzClip.new() -> OzzClip {
  return OzzClip{ handle: 0 };
}

/// Clip metadata: duration in seconds and the track (= joint) count.
pub type OzzClipInfo = {
  duration: Float32;
  tracks: Int;
  joints: Int;
}

/// A sampled pose in owned buffers, per joint:
/// `rotations` holds joints*4 floats (x, y, z, w), `translations` and
/// `scales` hold joints*3 floats (x, y, z) each.
pub type OzzPose = {
  joints: Int;
  rotations: Vec[Float32];
  translations: Vec[Float32];
  scales: Vec[Float32];
}

pub fn OzzPose.new() -> OzzPose {
  return OzzPose{ joints: 0, rotations: Vec[Float32].new(),
    translations: Vec[Float32].new(), scales: Vec[Float32].new() };
}

// --- old probes -------------------------------------------------------------

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

/// Clip pipeline smoke: RawAnimation (child y 1 -> 3 over 1 s) built by the
/// AnimationBuilder, then sampled at ratio 0.5 (y == 2) and 1.0 (y == 3)
/// through a SamplingJob::Context.  Complexity: O(1).
pub fn ozz_clip_ok() -> Bool
  requires: true
{
  unsafe { return (ozz_probe_clip() as Int) != 0; }
}

/// Caller-surface smoke (C-level): build from flat caller keys, sample t=0
/// and t=duration, typed bounds/handle/capacity rcs, release, determinism.
/// Complexity: O(keys).
pub fn ozz_caller_ok() -> Bool
  requires: true
{
  unsafe { return (ozz_probe_caller() as Int) != 0; }
}

// --- caller surface (0.4.0) -------------------------------------------------

/// Stable message for a bridge rc code.
/// Complexity: O(1).
pub fn ozz_error_name(code: Int) -> Str {
  if code == OZZ_OK { return "ok"; }
  if code == OZZ_ERR_ARGS { return "ozz: bad arguments"; }
  if code == OZZ_ERR_HANDLE { return "ozz: unknown or released clip handle"; }
  if code == OZZ_ERR_KEYS { return "ozz: invalid animation keys"; }
  if code == OZZ_ERR_BUILD { return "ozz: animation build failed"; }
  if code == OZZ_ERR_CAPACITY { return "ozz: output capacity too small"; }
  if code == OZZ_ERR_TIME { return "ozz: sample time out of range"; }
  if code == OZZ_ERR_INTERNAL { return "ozz: internal error"; }
  return "ozz: unknown error";
}

/// Typed error for a bridge rc code.
/// Complexity: O(1).
pub fn ozz_error(code: Int) -> OzzError {
  return OzzError.new(code, ozz_error_name(code));
}

fn ozz_zero_floats(n: Int) -> Vec[Float32]
  requires: n >= 0
{
  var v: Vec[Float32] = Vec[Float32].new();
  var i: Int = 0;
  while i < n {
    v.push(0.0);
    i = i + 1;
  }
  return v;
}

fn ozz_push_keys(keys: &Vec[OzzKey], out: &mut Vec[Float32]) {
  var j: Int = 0;
  while j < keys.len() {
    let k = keys[j];
    out.push(k.time);
    out.push(k.rx);
    out.push(k.ry);
    out.push(k.rz);
    out.push(k.rw);
    out.push(k.tx);
    out.push(k.ty);
    out.push(k.tz);
    out.push(k.sx);
    out.push(k.sy);
    out.push(k.sz);
    j = j + 1;
  }
}

/// Build a clip from caller-supplied per-track keys into package-owned
/// storage; the returned clip holds an opaque handle (the bridge owns the
/// runtime Animation until `ozz_clip_release`).  Every key carries a time
/// plus joint-local rotation (quaternion x, y, z, w), translation and
/// scale; the keys of a track must be strictly ascending in time and within
/// [0, duration], and `duration` must be > 0.  Errors: OZZ_ERR_ARGS (empty
/// tracks / duration <= 0 / empty track), OZZ_ERR_KEYS (times out of range
/// or not ascending), OZZ_ERR_BUILD (builder rejected the clip).
/// Complexity: O(total keys).
pub fn ozz_clip_build(tracks: &Vec[OzzTrack], duration: Float32) -> Result[OzzClip, OzzError]
  requires: true
{
  if tracks.len() == 0 {
    return Err(ozz_error(OZZ_ERR_ARGS));
  }
  if !(duration > 0.0) {
    return Err(ozz_error(OZZ_ERR_ARGS));
  }
  var counts: Vec[Float32] = Vec[Float32].new();
  var keys: Vec[Float32] = Vec[Float32].new();
  var t: Int = 0;
  while t < tracks.len() {
    let tr = tracks[t];
    if tr.keys.len() == 0 {
      return Err(ozz_error(OZZ_ERR_ARGS));
    }
    counts.push(tr.keys.len() as Float32);
    ozz_push_keys(&tr.keys, &mut keys);
    t = t + 1;
  }
  let handle = unsafe {
    xozz_clip_build(tracks.len() as Int32, counts.as_mut_ptr(), keys.as_mut_ptr(),
      keys.len() as Int32, duration) as Int
  };
  if handle <= 0 {
    return Err(ozz_error(handle));
  }
  return Ok(OzzClip{ handle: handle });
}

/// Metadata of a built clip (duration, track count; joints == tracks).
/// Errors: OZZ_ERR_ARGS (empty handle), OZZ_ERR_HANDLE (unknown/released).
/// Complexity: O(1).
pub fn ozz_clip_info(clip: &OzzClip) -> Result[OzzClipInfo, OzzError]
  requires: true
{
  if clip.handle <= 0 {
    return Err(ozz_error(OZZ_ERR_ARGS));
  }
  var out = ozz_zero_floats(3);
  let rc = unsafe { xozz_clip_info(clip.handle as Int64, out.as_mut_ptr(), 3 as Int32) as Int };
  if rc != OZZ_OK {
    return Err(ozz_error(rc));
  }
  let duration = out[0];
  let tracks = out[1] as Int;
  let joints = out[2] as Int;
  return Ok(OzzClipInfo{ duration: duration, tracks: tracks, joints: joints });
}

/// Sample the clip at `time` seconds into fresh owned pose buffers.
/// `time` must be within [0, duration] (typed OZZ_ERR_TIME when beyond the
/// end or negative); a released/unknown handle is OZZ_ERR_HANDLE.
/// Complexity: O(joints).
pub fn ozz_clip_sample(clip: &OzzClip, time: Float32) -> Result[OzzPose, OzzError]
  requires: true
{
  if clip.handle <= 0 {
    return Err(ozz_error(OZZ_ERR_ARGS));
  }
  let info = ozz_clip_info(clip);
  if !info.is_ok {
    return Err(info.error);
  }
  let m = info.value;
  if m.joints <= 0 {
    return Err(ozz_error(OZZ_ERR_INTERNAL));
  }
  var flat = ozz_zero_floats(m.joints * OZZ_POSE_FLOATS);
  let rc = unsafe {
    xozz_clip_sample(clip.handle as Int64, time, flat.as_mut_ptr(),
      flat.len() as Int32) as Int
  };
  if rc != OZZ_OK {
    return Err(ozz_error(rc));
  }
  var rotations: Vec[Float32] = Vec[Float32].new();
  var translations: Vec[Float32] = Vec[Float32].new();
  var scales: Vec[Float32] = Vec[Float32].new();
  var j: Int = 0;
  while j < m.joints {
    let base = j * OZZ_POSE_FLOATS;
    rotations.push(flat[base + 0]);
    rotations.push(flat[base + 1]);
    rotations.push(flat[base + 2]);
    rotations.push(flat[base + 3]);
    translations.push(flat[base + 4]);
    translations.push(flat[base + 5]);
    translations.push(flat[base + 6]);
    scales.push(flat[base + 7]);
    scales.push(flat[base + 8]);
    scales.push(flat[base + 9]);
    j = j + 1;
  }
  return Ok(OzzPose{ joints: m.joints, rotations: rotations,
    translations: translations, scales: scales });
}

/// Release the clip's bridge-owned storage.  The handle is unknown
/// afterwards (OZZ_ERR_HANDLE).  Errors: OZZ_ERR_ARGS (empty handle),
/// OZZ_ERR_HANDLE (already released/unknown).  Complexity: O(1).
pub fn ozz_clip_release(clip: &OzzClip) -> Result[Unit, OzzError]
  requires: true
{
  if clip.handle <= 0 {
    return Err(ozz_error(OZZ_ERR_ARGS));
  }
  let rc = unsafe { xozz_clip_release(clip.handle as Int64) as Int };
  if rc != OZZ_OK {
    return Err(ozz_error(rc));
  }
  return Ok(());
}

/// Run every probe.  Ok(()) when all pass; Err lists the failed probe names.
/// Complexity: O(keys).
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
  if (mask & 8) != 0 { msg = msg + " clip"; }
  if (mask & 16) != 0 { msg = msg + " caller"; }
  return Err(msg);
}
