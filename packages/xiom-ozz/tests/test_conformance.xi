// xiom.ozz conformance suite -- vendored C++ amalgamation path.
//
// Proves the real binding against the vendored ozz-animation 0.16.0
// amalgamations compiled into the test binary:
//   scripts/port.ps1 -Package xiom.ozz
// (port.args.json passes vendor/ozz_all.cpp + vendor/ozz_bridge.cpp).
//
// Coverage: math primitives, offline RawSkeleton -> runtime Skeleton, a
// LocalToModelJob run with verified model-space translations, the clip
// pipeline (RawAnimation -> AnimationBuilder -> SamplingJob, hand-checked
// pose), and (0.4.0) the caller surface: build a clip from caller keys,
// sample at t=0 / t=duration into owned pose buffers, typed out-of-range /
// bad-handle / bad-key errors, and build + sample determinism.  There is no
// SKIP path (the library is compiled in).
//
// Discipline (v0.64.4): Str equality goes through compare.str_compare; no
// pointer casts, no foreign-pointer reads, no bare null; every C-written
// buffer is an XIOM-owned Vec read with plain indexing.

module ozz_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.ozz;
use xiom.string;
use xiom.string.compare;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn abs_f32(x: Float32) -> Float32 {
  if x < 0.0 { return 0.0 - x; }
  return x;
}

fn close_f32(a: Float32, b: Float32, tol: Float32) -> Bool {
  return abs_f32(a - b) <= tol;
}

fn floats_equal(a: &Vec[Float32], b: &Vec[Float32]) -> Bool {
  if a.len() != b.len() { return false; }
  var i: Int = 0;
  while i < a.len() {
    let x = a[i];
    let y = b[i];
    if x != y { return false; }
    i = i + 1;
  }
  return true;
}

fn dup_floats(v: &Vec[Float32]) -> Vec[Float32] {
  var out: Vec[Float32] = Vec[Float32].new();
  var i: Int = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Two-joint caller fixture: root static; child translates y 1 -> 3, rotates
// 90 degrees about Z and scales 1 -> 2 over one second.  Matches the C-side
// ozz_probe_caller fixture in shape.
fn fixture_tracks() -> Vec[OzzTrack] {
  var root = OzzTrack.new();
  root.keys.push(OzzKey.new(0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0));
  root.keys.push(OzzKey.new(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0));
  var child = OzzTrack.new();
  child.keys.push(OzzKey.new(0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0));
  child.keys.push(OzzKey.new(1.0, 0.0, 0.0, 0.70710678, 0.70710678, 0.0, 3.0, 0.0, 2.0, 2.0, 2.0));
  var tracks: Vec[OzzTrack] = Vec[OzzTrack].new();
  tracks.push(root);
  tracks.push(child);
  return tracks;
}

// build -> info -> sample t=0: ownership, counts and first-key pose.
fn test_caller_build_zero() -> Bool {
  var tracks = fixture_tracks();
  let br = ozz_clip_build(&tracks, 1.0);
  if !br.is_ok { return false; }
  let clip = br.value;
  var ok = true;

  let ir = ozz_clip_info(&clip);
  if !ir.is_ok {
    ok = false;
  } else {
    let info = ir.value;
    if info.tracks != 2 { ok = false; }
    if info.joints != 2 { ok = false; }
    if !close_f32(info.duration, 1.0, 0.0001) { ok = false; }
  }

  let pr = ozz_clip_sample(&clip, 0.0);
  if !pr.is_ok {
    ok = false;
  } else {
    let pose = pr.value;
    if pose.joints != 2 { ok = false; }
    if pose.rotations.len() != 8 { ok = false; }
    if pose.translations.len() != 6 { ok = false; }
    if pose.scales.len() != 6 { ok = false; }
    if pose.rotations.len() == 8 && pose.translations.len() == 6 && pose.scales.len() == 6 {
      // joint 0 (root): identity
      if !close_f32(pose.rotations[0], 0.0, 0.0001) { ok = false; }
      if !close_f32(pose.rotations[3], 1.0, 0.0001) { ok = false; }
      if !close_f32(pose.translations[1], 0.0, 0.0001) { ok = false; }
      if !close_f32(pose.scales[0], 1.0, 0.0001) { ok = false; }
      // joint 1 (child) at its first key: identity rotation, y = 1, scale 1
      if !close_f32(pose.rotations[7], 1.0, 0.0001) { ok = false; }
      if !close_f32(pose.translations[4], 1.0, 0.0001) { ok = false; }
      if !close_f32(pose.scales[3], 1.0, 0.0001) { ok = false; }
    }
  }

  let rel = ozz_clip_release(&clip);
  if !rel.is_ok { ok = false; }
  return ok;
}

// sample at t = duration: end-key pose (y=3, scale 2, 90-degree Z).
fn test_caller_end() -> Bool {
  var tracks = fixture_tracks();
  let br = ozz_clip_build(&tracks, 1.0);
  if !br.is_ok { return false; }
  let clip = br.value;
  var ok = true;

  let pr = ozz_clip_sample(&clip, 1.0);
  if !pr.is_ok {
    ok = false;
  } else {
    let pose = pr.value;
    // joint 1: rotation z = w ~ sin/cos(45 deg), y = 3, scale = 2.  Ozz
    // quantizes keyframes (rotation ~1.6e-4, time ratio ~2^-12), so end
    // values are verified within 1e-3 (same window as the clip probe).
    if !close_f32(pose.rotations[6], 0.70710678, 0.001) { ok = false; }
    if !close_f32(pose.rotations[7], 0.70710678, 0.001) { ok = false; }
    if !close_f32(pose.translations[4], 3.0, 0.001) { ok = false; }
    if !close_f32(pose.scales[3], 2.0, 0.001) { ok = false; }
    if !close_f32(pose.scales[4], 2.0, 0.001) { ok = false; }
    if !close_f32(pose.scales[5], 2.0, 0.001) { ok = false; }
    // joint 0 unchanged
    if !close_f32(pose.translations[1], 0.0, 0.0001) { ok = false; }
  }

  let rel = ozz_clip_release(&clip);
  if !rel.is_ok { ok = false; }
  return ok;
}

// typed edge behavior: beyond-duration / negative -> OZZ_ERR_TIME, ghost and
// released handles -> OZZ_ERR_HANDLE, bad builds -> OZZ_ERR_ARGS/KEYS.
fn test_caller_edge() -> Bool {
  var tracks = fixture_tracks();
  let br = ozz_clip_build(&tracks, 1.0);
  if !br.is_ok { return false; }
  let clip = br.value;
  var ok = true;

  let over = ozz_clip_sample(&clip, 1.5);
  if over.is_ok {
    ok = false;
  } else {
    if over.error.code != OZZ_ERR_TIME { ok = false; }
    if !str_eq(over.error.message, "ozz: sample time out of range") { ok = false; }
  }

  let neg = ozz_clip_sample(&clip, -0.25);
  if neg.is_ok {
    ok = false;
  } else {
    if neg.error.code != OZZ_ERR_TIME { ok = false; }
  }

  // exactly at the end is inside the bounds
  let end = ozz_clip_sample(&clip, 1.0);
  if !end.is_ok { ok = false; }

  // unknown handle
  let ghost = OzzClip{ handle: 4242 };
  let g = ozz_clip_sample(&ghost, 0.5);
  if g.is_ok {
    ok = false;
  } else {
    if g.error.code != OZZ_ERR_HANDLE { ok = false; }
  }

  // released handle
  let rel = ozz_clip_release(&clip);
  if !rel.is_ok { ok = false; }
  let post = ozz_clip_sample(&clip, 0.5);
  if post.is_ok {
    ok = false;
  } else {
    if post.error.code != OZZ_ERR_HANDLE { ok = false; }
  }

  // build rejects: no tracks, duration 0, a key time beyond the duration
  let empty: Vec[OzzTrack] = Vec[OzzTrack].new();
  let b0 = ozz_clip_build(&empty, 1.0);
  if b0.is_ok {
    ok = false;
  } else {
    if b0.error.code != OZZ_ERR_ARGS { ok = false; }
  }
  let b1 = ozz_clip_build(&tracks, 0.0);
  if b1.is_ok {
    ok = false;
  } else {
    if b1.error.code != OZZ_ERR_ARGS { ok = false; }
  }
  var late: Vec[OzzTrack] = Vec[OzzTrack].new();
  var lt = OzzTrack.new();
  lt.keys.push(OzzKey.new(0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0));
  lt.keys.push(OzzKey.new(2.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0));
  late.push(lt);
  let b2 = ozz_clip_build(&late, 1.0);
  if b2.is_ok {
    ok = false;
  } else {
    if b2.error.code != OZZ_ERR_KEYS { ok = false; }
  }
  return ok;
}

// determinism: two builds of identical keys sample bit-identically at
// t=0.5, and resampling one clip is stable.
fn test_caller_determinism() -> Bool {
  var ta = fixture_tracks();
  var tb = fixture_tracks();
  let ba = ozz_clip_build(&ta, 1.0);
  let bb = ozz_clip_build(&tb, 1.0);
  if !ba.is_ok || !bb.is_ok { return false; }
  let ca = ba.value;
  let cb = bb.value;
  var ok = true;

  let sa1 = ozz_clip_sample(&ca, 0.5);
  let sa2 = ozz_clip_sample(&ca, 0.5);
  let sb = ozz_clip_sample(&cb, 0.5);
  if !sa1.is_ok || !sa2.is_ok || !sb.is_ok {
    ok = false;
  } else {
    let pa1 = sa1.value;
    let pa2 = sa2.value;
    let pb = sb.value;
    let ra1 = dup_floats(&pa1.rotations);
    let ra2 = dup_floats(&pa2.rotations);
    let rb = dup_floats(&pb.rotations);
    let ta1 = dup_floats(&pa1.translations);
    let ta2 = dup_floats(&pa2.translations);
    let tb2 = dup_floats(&pb.translations);
    let ga1 = dup_floats(&pa1.scales);
    let ga2 = dup_floats(&pa2.scales);
    let gb = dup_floats(&pb.scales);
    if !floats_equal(&ra1, &ra2) { ok = false; }
    if !floats_equal(&ta1, &ta2) { ok = false; }
    if !floats_equal(&ga1, &ga2) { ok = false; }
    if !floats_equal(&ra1, &rb) { ok = false; }
    if !floats_equal(&ta1, &tb2) { ok = false; }
    if !floats_equal(&ga1, &gb) { ok = false; }
  }

  let r1 = ozz_clip_release(&ca);
  let r2 = ozz_clip_release(&cb);
  if !r1.is_ok || !r2.is_ok { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.ozz conformance tests (vendored amalgamation) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(ozz_math_ok(),
    "math: Float3 dot/cross + quaternion axis rotation (90deg about Z maps X->Y)");
  failed = failed + report(ozz_skeleton_ok(),
    "skeleton: offline RawSkeleton -> runtime Skeleton (2 joints, parents -1/0)");
  failed = failed + report(ozz_local_to_model_ok(),
    "local_to_model: root at origin, child translated (0,1,0) in model space");
  failed = failed + report(ozz_clip_ok(),
    "clip: RawAnimation -> AnimationBuilder -> SamplingJob (child y=1->3 linear; 0.5 -> 2.0, 1.0 -> 3.0)");
  failed = failed + report(test_caller_build_zero(),
    "caller_build: clip from caller keys (2 tracks) -> sample t=0 (first-key pose, owned buffers)");
  failed = failed + report(test_caller_end(),
    "caller_end: sample t=duration -> child y=3, scale 2, rot 90deg about Z (z=w=0.7071)");
  failed = failed + report(test_caller_edge(),
    "caller_edge: t>duration / t<0 -> OZZ_ERR_TIME; ghost/released handle -> OZZ_ERR_HANDLE; bad builds -> OZZ_ERR_ARGS/KEYS");
  failed = failed + report(test_caller_determinism(),
    "caller_determinism: two builds of the same keys -> identical poses at t=0.5; resample stable");

  let all = ozz_probe();
  if all.is_ok {
    failed = failed + report(true, "aggregate: ozz_probe() all green");
  } else {
    failed = failed + report(false, "aggregate: " + all.error);
  }

  if failed == 0 {
    io.println("xiom.ozz: all tests passed");
  } else {
    io.println("xiom.ozz: tests failed");
  }
  return failed;
}
