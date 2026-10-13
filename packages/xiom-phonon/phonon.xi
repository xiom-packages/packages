// XIOM -- xiom.phonon: Steam Audio (Phonon) bindings via dynamic loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader path (same pattern as xiom.odbc / xiom.portaudio).
// Steam Audio (Valve) exposes a C API; the package resolves `phonon.dll` at
// runtime through `xiom.ffi.dl` and needs no headers: the complete export
// manifest, enum values and struct layouts are generated from the pinned
// public `phonon.h` (tools/gen_phonon.py -> xiom.phonon.abi /
// xiom.phonon.exports).  All XIOM `unsafe` in this package lives in this
// single module (G5); the effect-group wrappers sit in the sections below.
//
// The loader resolves ALL 216 public entry points the pinned header declares
// (header-order table; zero missing in the official v4.8.1 DLL -- verified
// with `tools/gen_phonon.py --verify-dll`).  The typed wrappers cover the
// audio-processing groups (context, HRTF, audio buffers, binaural, panning,
// virtual surround, ambisonics encode/panning/binaural/rotation/decode,
// direct, path); the simulation-domain groups (scenes, simulators, probes,
// reflection baking, serialization, device backends) stay explicit non-goals
// in SPEC.md and are still symbol-resolvable through `phonon_fn_of`.
//
// Classification:
//   PHONON_LOAD_ABSENT  -> phonon.dll missing -> SKIP (CI stays green)
//   PHONON_LOAD_ABI     -> entry points missing -> FAIL
//   PHONON_PROBE_FAILED -> context creation failed -> FAIL
//
// G2 pin (SPEC.md): soname `phonon.dll` + upstream tag v4.8.1 + generated
// header manifest (sha256) + verified ABI layouts (tools/layout_check.c).

module xiom.phonon

use xiom.ffi.dl;
use xiom.num.float;
use xiom.string;
use xiom.phonon.abi;
use xiom.phonon.exports;

// =========================================================================
// Identity, version and ABI constants
// =========================================================================

pub const PHONON_SONAME: Str = "phonon.dll";

// All Steam Audio constants (version, enums, struct sizes/offsets) live in
// the generated `xiom.phonon.abi` module -- the single canonical home per
// name (duplicate constant names across package modules hit compiler finding
// B-28).  Consumers read them as `abi.STEAMAUDIO_VERSION`,
// `abi.IPL_HRTFTYPE_DEFAULT`, `abi.IPL_CONTEXT_SETTINGS_SIZE`, ...

pub const PHONON_LOAD_ABSENT: Int = 0;  // phonon.dll missing -> SKIP
pub const PHONON_LOAD_ABI: Int = 1;     // entry points missing -> FAIL
pub const PHONON_PROBE_FAILED: Int = 2; // context creation failed -> FAIL

// =========================================================================
// Types
// =========================================================================

pub type PhononLoadError = {
  kind: Int;
  message: Str;
}

pub type PhononInfo = {
  version: Int;
  simd_level: Int;
  context_handle: Int;
}

/// A loaded Steam Audio.  Owned by the caller; release with `phonon_close`.
/// `fns` is the resolved address table, indexed by the generated
/// `exports.PHONON_IDX_*` constants, aligned with `phonon_all_export_names`.
pub type PhononLibrary = {
  handle: Int;
  fns: Vec[Int];
  resolved: Int;
}

/// Flat outcome: an opaque handle (0 when `ok` is false).
pub type PhononHandleOutcome = {
  ok: Bool;
  status: Int;
  error: Str;
  handle: Int;
}

/// Flat outcome: a status/void call.
pub type PhononStatusOutcome = {
  ok: Bool;
  status: Int;
  error: Str;
}

/// Flat outcome: an effect Apply / GetTail call (state is the
/// IPLAudioEffectState value when `ok`).
pub type PhononEffectOutcome = {
  ok: Bool;
  state: Int;
  error: Str;
}

/// Flat outcome: a managed (DLL-allocated) audio buffer slot.
pub type PhononManagedBuffer = {
  ok: Bool;
  status: Int;
  error: Str;
  slot: Vec[UInt8];
}

/// Version/capability probe over a loaded library.
pub type PhononCapabilities = {
  version: Int;
  public_fn_count: Int;
  declared_fn_count: Int;
  resolved_fn_count: Int;
  has_context: Bool;
  has_hrtf: Bool;
  has_audio_buffers: Bool;
  has_binaural: Bool;
  has_panning: Bool;
  has_virtual_surround: Bool;
  has_ambisonics: Bool;
  has_direct: Bool;
  has_path: Bool;
}

/// Fully XIOM-owned deinterleaved audio buffer (planar, channel-major).
/// `data` holds `num_channels * num_samples` Float32 samples; `ptrs` is the
/// channel-pointer array and `slot` is the 16-byte `IPLAudioBuffer` struct
/// that points at it.  The DLL only ever reads/writes XIOM-owned memory;
/// this module never reads through a foreign pointer.
pub type PhononAudioBuffer = {
  num_channels: Int;
  num_samples: Int;
  slot: Vec[UInt8];
  ptrs: Vec[UInt8];
  data: Vec[Float32];
}

/// A 3D vector (matches `IPLVector3` semantics; Float64 in XIOM).
pub type PhononVector3 = {
  x: Float64;
  y: Float64;
  z: Float64;
}

/// A listener/source coordinate space (`IPLCoordinateSpace3`).
pub type PhononOrientation = {
  right: PhononVector3;
  up: PhononVector3;
  ahead: PhononVector3;
  origin: PhononVector3;
}

/// Canonical identity orientation: right +X, up +Y, ahead -Z, origin 0.
pub fn phonon_orientation_identity() -> PhononOrientation
  requires: true
{
  return PhononOrientation{
    right: PhononVector3{ x: 1.0; y: 0.0; z: 0.0 };
    up: PhononVector3{ x: 0.0; y: 1.0; z: 0.0 };
    ahead: PhononVector3{ x: 0.0; y: 0.0; z: 0.0 - 1.0 };
    origin: PhononVector3{ x: 0.0; y: 0.0; z: 0.0 };
  };
}

pub fn phonon_ok_handle(h: Int) -> PhononHandleOutcome {
  return PhononHandleOutcome{ ok: true; status: abi.IPL_STATUS_SUCCESS; error: ""; handle: h };
}

pub fn phonon_ok_status() -> PhononStatusOutcome {
  return PhononStatusOutcome{ ok: true; status: abi.IPL_STATUS_SUCCESS; error: "" };
}

pub fn phonon_err_handle(status: Int, msg: Str) -> PhononHandleOutcome {
  return PhononHandleOutcome{ ok: false; status: status; error: msg; handle: 0 };
}

pub fn phonon_err_status(status: Int, msg: Str) -> PhononStatusOutcome {
  return PhononStatusOutcome{ ok: false; status: status; error: msg };
}

pub fn phonon_ok_effect(state: Int) -> PhononEffectOutcome {
  return PhononEffectOutcome{ ok: true; state: state; error: "" };
}

pub fn phonon_err_effect(msg: Str) -> PhononEffectOutcome {
  return PhononEffectOutcome{ ok: false; state: -1; error: msg };
}

// =========================================================================
// Slot helpers (XIOM-owned out-params; byte-indexed little-endian)
// =========================================================================

/// A zeroed XIOM-owned slot of `n` bytes.
/// Complexity: O(n).
pub fn phonon_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
  requires: n <= 65536
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

/// Write the low 32 bits of `v` little-endian at `idx`.
/// Complexity: O(1).
pub fn s_w32(buf: &mut Vec[UInt8], idx: Int, v: Int)
  requires: idx >= 0
  requires: idx + 3 < buf.len()
{
  buf[idx] = (v & 0xFF) as UInt8;
  buf[idx + 1] = ((v >> 8) & 0xFF) as UInt8;
  buf[idx + 2] = ((v >> 16) & 0xFF) as UInt8;
  buf[idx + 3] = ((v >> 24) & 0xFF) as UInt8;
}

/// Write `v` as little-endian 64-bit at `idx`.
/// Complexity: O(1).
pub fn s_w64(buf: &mut Vec[UInt8], idx: Int, v: Int)
  requires: idx >= 0
  requires: idx + 7 < buf.len()
{
  s_w32(buf, idx, v & 0xFFFFFFFF);
  s_w32(buf, idx + 4, (v >> 32) & 0xFFFFFFFF);
}

/// Read a little-endian u32 at `idx` (0..2^32-1).
/// Complexity: O(1).
pub fn s_r32(buf: &Vec[UInt8], idx: Int) -> Int
  requires: idx >= 0
  requires: idx + 3 < buf.len()
{
  let b0 = buf[idx] as Int;
  let b1 = buf[idx + 1] as Int;
  let b2 = buf[idx + 2] as Int;
  let b3 = buf[idx + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

/// Read a little-endian u64 at `idx`.
/// Complexity: O(1).
pub fn s_r64(buf: &Vec[UInt8], idx: Int) -> Int
  requires: idx >= 0
  requires: idx + 7 < buf.len()
{
  let lo = s_r32(buf, idx);
  let hi = s_r32(buf, idx + 4);
  return lo | (hi << 32);
}

/// Write the IEEE-754 binary32 pattern of `x` at `idx` (via
/// `phonon_f32_bits`).
/// Complexity: O(1).
pub fn s_wf32(buf: &mut Vec[UInt8], idx: Int, x: Float64)
  requires: idx >= 0
  requires: idx + 3 < buf.len()
{
  s_w32(buf, idx, phonon_f32_bits(x));
}

// =========================================================================
// IEEE-754 binary32 conversion (pure Int math; f64 bit pattern -> f32)
// =========================================================================

/// IEEE-754 binary32 bit pattern of `x` (round-to-nearest-even; f64
/// subnormals below the f32 range flush to zero; overflow to infinity).
/// `xiom.num.float.float_bits` is exact from v0.64.0, so this is exact for
/// every f32-representable value (table-tested in the conformance suite).
/// Complexity: O(1).
pub fn phonon_f32_bits(x: Float64) -> Int
  requires: true
{
  let b = float.float_bits(x);
  let sn = ((b >> 63) & 1) << 31;
  let m64 = b & 0xFFFFFFFFFFFFF;
  let e64 = (b >> 52) & 0x7FF;
  if e64 == 0x7FF {
    if m64 == 0 { return sn | 0x7F800000; }
    return sn | 0x7FC00000;
  }
  if e64 == 0 {
    // f64 zero or subnormal: |x| < 2^-1022, far below the f32 subnormal
    // range; rounds to signed zero.
    return sn;
  }
  let e = e64 - 1023;
  if e > 127 { return sn | 0x7F800000; }
  if e >= -126 {
    var e2 = e + 127;
    let keep = m64 >> 29;
    let rem = m64 & 0x1FFFFFFF;
    let half = 0x10000000;
    var k = keep;
    if rem > half { k = k + 1; }
    elif rem == half && (k & 1) == 1 { k = k + 1; }
    if k == 0x800000 {
      k = 0;
      e2 = e2 + 1;
    }
    if e2 >= 255 { return sn | 0x7F800000; }
    return sn | (e2 << 23) | k;
  }
  let m53 = m64 + 0x10000000000000;
  let shift = 0 - (e + 97);
  if shift > 54 { return sn; }
  var k = m53 >> shift;
  if shift > 0 {
    let rem = m53 & ((1 << shift) - 1);
    let half = 1 << (shift - 1);
    if rem > half { k = k + 1; }
    elif rem == half && (k & 1) == 1 { k = k + 1; }
  }
  if k >= 0x800000 { return sn | (1 << 23); }
  return sn | k;
}

/// Float64 value of an IEEE-754 binary32 bit pattern (pure arithmetic;
/// NaN inputs produce NaN, infinities produce infinities).
/// Complexity: O(1).
pub fn phonon_f32_from_bits(bits: Int) -> Float64
  requires: bits >= 0
  requires: bits <= 0xFFFFFFFF
{
  let sign = if ((bits >> 31) & 1) == 1 { -1.0 } else { 1.0 };
  let e = (bits >> 23) & 0xFF;
  let m = bits & 0x7FFFFF;
  if e == 0xFF {
    if m == 0 { return sign * (1.0 / 0.0); }
    return 0.0 / 0.0;
  }
  if e == 0 {
    if m == 0 { return sign * 0.0; }
    return sign * scale_pow2(m as Float64, -149);
  }
  let frac = 1.0 + (m as Float64) * scale_pow2(1.0, -23);
  return sign * frac * scale_pow2(1.0, e - 127);
}

fn scale_pow2(x: Float64, e: Int) -> Float64
  requires: e >= -1074
  requires: e <= 1023
{
  var r = x;
  var n = e;
  while n > 0 {
    r = r * 2.0;
    n = n - 1;
  }
  while n < 0 {
    r = r / 2.0;
    n = n + 1;
  }
  return r;
}

// =========================================================================
// Loader
// =========================================================================

/// Load an explicitly named Steam Audio build (bogus names exercise the
/// ABSENT/SKIP classification deterministically on any host).
/// Complexity: O(symbols).
pub fn phonon_load_named(soname: Str) -> Result[PhononLibrary, PhononLoadError]
  requires: soname.len() > 0
{
  let h = dl.dl_open(soname);
  if !h.is_ok {
    return Err(PhononLoadError{ kind: PHONON_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;

  let names = exports.phonon_all_export_names();
  var fns: Vec[Int] = Vec[Int].new();
  var i: Int = 0;
  var missing: Int = 0;
  var first_missing: Str = "";
  while i < names.len() {
    let s = dl.dl_sym(handle, names[i]);
    if s.is_ok {
      fns.push(s.value);
    } else {
      if missing == 0 { first_missing = names[i]; }
      missing = missing + 1;
      fns.push(0);
    }
    i = i + 1;
  }
  if missing > 0 {
    var ig = dl.dl_close(handle);
    return Err(PhononLoadError{
      kind: PHONON_LOAD_ABI;
      message: "missing " + int_to_str(missing) + " of " + int_to_str(names.len())
        + " entry points, first: " + first_missing,
    });
  }

  return Ok(PhononLibrary{
    handle: handle,
    fns: fns,
    resolved: names.len(),
  });
}

/// Load the default build (`phonon.dll`).
/// Complexity: O(symbols).
pub fn phonon_load() -> Result[PhononLibrary, PhononLoadError]
  requires: true
{
  return phonon_load_named(PHONON_SONAME);
}

/// Release the library handle.
/// Complexity: O(1).
pub fn phonon_close(lib: &PhononLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

/// Resolved address of one public export (0 when not resolved).  Lets
/// consumers reach the out-of-scope simulation surface without a typed
/// wrapper; pair with the generated `exports.PHONON_IDX_*` constants or
/// `phonon_export_index`.
/// Complexity: O(1).
pub fn phonon_fn_of(lib: &PhononLibrary, idx: Int) -> Int
  requires: idx >= 0
  requires: idx < lib.fns.len()
{
  return lib.fns[idx];
}

/// Header-order index of a public export name (-1 when unknown).
/// Complexity: O(n).
pub fn phonon_export_index(name: Str) -> Int
  requires: name.len() > 0
{
  let names = exports.phonon_all_export_names();
  var i: Int = 0;
  while i < names.len() {
    if string.str_compare(names[i], name) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

/// Version + capability probe derived from the resolved table.
/// Complexity: O(n).
pub fn phonon_capabilities(lib: &PhononLibrary) -> PhononCapabilities
  requires: lib.handle != 0
{
  let g_context = group_resolved(lib, exports.PHONON_GROUP_CONTEXT);
  let g_hrtf = group_resolved(lib, exports.PHONON_GROUP_HRTF);
  let g_buffers = group_resolved(lib, exports.PHONON_GROUP_AUDIO_BUFFER);
  let g_binaural = group_resolved(lib, exports.PHONON_GROUP_BINAURAL);
  let g_panning = group_resolved(lib, exports.PHONON_GROUP_PANNING);
  let g_vsurround = group_resolved(lib, exports.PHONON_GROUP_VIRTUAL_SURROUND);
  let g_amb = group_resolved(lib, exports.PHONON_GROUP_AMBISONICS_ENCODE)
    && group_resolved(lib, exports.PHONON_GROUP_AMBISONICS_PANNING)
    && group_resolved(lib, exports.PHONON_GROUP_AMBISONICS_BINAURAL)
    && group_resolved(lib, exports.PHONON_GROUP_AMBISONICS_ROTATION)
    && group_resolved(lib, exports.PHONON_GROUP_AMBISONICS_DECODE);
  let g_direct = group_resolved(lib, exports.PHONON_GROUP_DIRECT_EFFECT);
  let g_path = group_resolved(lib, exports.PHONON_GROUP_PATH_EFFECT);
  return PhononCapabilities{
    version: abi.STEAMAUDIO_VERSION;
    public_fn_count: exports.PHONON_PUBLIC_FN_COUNT;
    declared_fn_count: exports.PHONON_DECLARED_FN_COUNT;
    resolved_fn_count: lib.resolved;
    has_context: g_context;
    has_hrtf: g_hrtf;
    has_audio_buffers: g_buffers;
    has_binaural: g_binaural;
    has_panning: g_panning;
    has_virtual_surround: g_vsurround;
    has_ambisonics: g_amb;
    has_direct: g_direct;
    has_path: g_path;
  };
}

fn group_resolved(lib: &PhononLibrary, group: Int) -> Bool
  requires: group >= 0
  requires: group < exports.PHONON_GROUP_COUNT
{
  let idxs = exports.phonon_group_export_indexes(group);
  var i: Int = 0;
  while i < idxs.len() {
    if lib.fns[idxs[i]] == 0 { return false; }
    i = i + 1;
  }
  return true;
}

// =========================================================================
// Probe (context lifecycle)
// =========================================================================

/// Create a Steam Audio context and exercise the retain/release balance.
/// `IPLContextSettings` is the generated 40-byte layout: version (u32 at 0),
/// three optional callbacks (NULL), simdLevel (u32 at 32), flags (u32 at 36).
/// Complexity: O(1).
pub fn phonon_probe(lib: &PhononLibrary) -> Result[PhononInfo, Str]
  requires: lib.handle != 0
{
  let ctx = phonon_context_create(lib, abi.STEAMAUDIO_VERSION, abi.IPL_SIMDLEVEL_SSE2, 0);
  if !ctx.ok {
    return Err("phonon: iplContextCreate rc=" + int_to_str(ctx.status));
  }
  let again = phonon_context_retain(lib, ctx.handle);
  if again != ctx.handle {
    return Err("phonon: iplContextRetain returned a different handle");
  }
  let r1 = phonon_context_release(lib, ctx.handle);
  if !r1.ok {
    return Err("phonon: iplContextRelease failed: " + r1.error);
  }
  let r2 = phonon_context_release(lib, again);
  if !r2.ok {
    return Err("phonon: iplContextRelease failed: " + r2.error);
  }
  return Ok(PhononInfo{
    version: abi.STEAMAUDIO_VERSION,
    simd_level: abi.IPL_SIMDLEVEL_SSE2,
    context_handle: ctx.handle,
  });
}

/// Load an explicitly named build and run `phonon_probe`.
/// Complexity: O(symbols + context lifecycle).
pub fn phonon_probe_named(soname: Str) -> Result[PhononInfo, PhononLoadError]
  requires: soname.len() > 0
{
  let l = phonon_load_named(soname);
  if !l.is_ok {
    return Err(l.error);
  }
  let lib: PhononLibrary = l.value;
  let p = phonon_probe(&lib);
  let cl = phonon_close(&lib);
  if !p.is_ok {
    return Err(PhononLoadError{ kind: PHONON_PROBE_FAILED; message: p.error });
  }
  if !cl.is_ok {
    return Err(PhononLoadError{ kind: PHONON_PROBE_FAILED; message: cl.error });
  }
  return Ok(p.value);
}

/// Probe the default build (`phonon.dll`).
/// Complexity: O(symbols + context lifecycle).
pub fn phonon_probe_default() -> Result[PhononInfo, PhononLoadError]
  requires: true
{
  return phonon_probe_named(PHONON_SONAME);
}

// =========================================================================
// Context
// =========================================================================

/// `iplContextCreate` with the generated `IPLContextSettings` layout.
/// Complexity: O(1).
pub fn phonon_context_create(lib: &PhononLibrary, version: Int, simd_level: Int, flags: Int)
  -> PhononHandleOutcome
  requires: version > 0
  requires: simd_level >= 0
{
  let fidx = exports.PHONON_IDX_IPL_CONTEXT_CREATE;
  if lib.fns[fidx] == 0 {
    return phonon_err_handle(PHONON_LOAD_ABI, "iplContextCreate not resolved");
  }
  var settings = phonon_slot(abi.IPL_CONTEXT_SETTINGS_SIZE);
  s_w32(&mut settings, abi.IPL_CONTEXT_SETTINGS_VERSION, version);
  s_w32(&mut settings, abi.IPL_CONTEXT_SETTINGS_SIMD_LEVEL, simd_level);
  s_w32(&mut settings, abi.IPL_CONTEXT_SETTINGS_FLAGS, flags);
  var out = phonon_slot(8);
  unsafe {
    let f_create = lib.fns[fidx] as fn(*UInt8, *UInt8) -> Int32;
    let rc = f_create(settings.as_mut_ptr(), out.as_mut_ptr()) as Int;
    if rc != abi.IPL_STATUS_SUCCESS {
      return phonon_err_handle(rc, "iplContextCreate rc=" + int_to_str(rc));
    }
    let h = s_r64(&out, 0);
    if h == 0 {
      return phonon_err_handle(PHONON_PROBE_FAILED, "iplContextCreate returned a null context");
    }
    return phonon_ok_handle(h);
  }
}

/// `iplContextRetain` (returns the retained handle; 0 on failure).
/// Complexity: O(1).
pub fn phonon_context_retain(lib: &PhononLibrary, context: Int) -> Int
  requires: context != 0
{
  let fidx = exports.PHONON_IDX_IPL_CONTEXT_RETAIN;
  if lib.fns[fidx] == 0 { return 0; }
  unsafe {
    let f_retain = lib.fns[fidx] as fn(Int) -> Int;
    return f_retain(context);
  }
}

/// `iplContextRelease` (takes `IPLContext*`; handle written into an owned
/// slot).
/// Complexity: O(1).
pub fn phonon_context_release(lib: &PhononLibrary, context: Int) -> PhononStatusOutcome
  requires: context != 0
{
  let fidx = exports.PHONON_IDX_IPL_CONTEXT_RELEASE;
  if lib.fns[fidx] == 0 {
    return phonon_err_status(PHONON_LOAD_ABI, "iplContextRelease not resolved");
  }
  var slot = phonon_slot(8);
  s_w64(&mut slot, 0, context);
  unsafe {
    let f_release = lib.fns[fidx] as fn(*UInt8);
    f_release(slot.as_mut_ptr());
  }
  return phonon_ok_status();
}

// =========================================================================
// HRTF
// =========================================================================

/// `iplHRTFCreate` (built-in HRTF: `IPL_HRTFTYPE_DEFAULT`; NULL SOFA
/// fields stay zeroed in the owned settings slot).
/// Complexity: O(1) + HRTF setup.
pub fn phonon_hrtf_create(lib: &PhononLibrary, context: Int, sampling_rate: Int,
    frame_size: Int, hrtf_type: Int, norm_type: Int, volume: Float64) -> PhononHandleOutcome
  requires: context != 0
  requires: sampling_rate > 0
  requires: frame_size > 0
{
  let fidx = exports.PHONON_IDX_IPL_HRTF_CREATE;
  if lib.fns[fidx] == 0 {
    return phonon_err_handle(PHONON_LOAD_ABI, "iplHRTFCreate not resolved");
  }
  var audio_settings = phonon_slot(abi.IPL_AUDIO_SETTINGS_SIZE);
  s_w32(&mut audio_settings, abi.IPL_AUDIO_SETTINGS_SAMPLING_RATE, sampling_rate);
  s_w32(&mut audio_settings, abi.IPL_AUDIO_SETTINGS_FRAME_SIZE, frame_size);
  var hrtf_settings = phonon_slot(abi.IPL_HRTF_SETTINGS_SIZE);
  s_w32(&mut hrtf_settings, abi.IPL_HRTF_SETTINGS_TYPE, hrtf_type);
  s_wf32(&mut hrtf_settings, abi.IPL_HRTF_SETTINGS_VOLUME, volume);
  s_w32(&mut hrtf_settings, abi.IPL_HRTF_SETTINGS_NORM_TYPE, norm_type);
  var out = phonon_slot(8);
  unsafe {
    let f_create = lib.fns[fidx] as fn(Int, *UInt8, *UInt8, *UInt8) -> Int32;
    let rc = f_create(context, audio_settings.as_mut_ptr(), hrtf_settings.as_mut_ptr(),
      out.as_mut_ptr()) as Int;
    if rc != abi.IPL_STATUS_SUCCESS {
      return phonon_err_handle(rc, "iplHRTFCreate rc=" + int_to_str(rc));
    }
    let h = s_r64(&out, 0);
    if h == 0 {
      return phonon_err_handle(PHONON_PROBE_FAILED, "iplHRTFCreate returned a null HRTF");
    }
    return phonon_ok_handle(h);
  }
}

/// `iplHRTFCreate` with `IPL_HRTFTYPE_SOFA` from a file path.  The path
/// pointer travels as the NUL-terminated C string of `sofa_path`, written
/// byte-wise into the owned settings slot (B-25 safe; verified against the
/// upstream CIPIC SOFA fixture).
/// Complexity: O(1) + SOFA load.
pub fn phonon_hrtf_create_sofa_file(lib: &PhononLibrary, context: Int,
    sampling_rate: Int, frame_size: Int, sofa_path: Str, norm_type: Int,
    volume: Float64) -> PhononHandleOutcome
  requires: context != 0
  requires: sampling_rate > 0
  requires: frame_size > 0
  requires: sofa_path.len() > 0
{
  let fidx = exports.PHONON_IDX_IPL_HRTF_CREATE;
  if lib.fns[fidx] == 0 {
    return phonon_err_handle(PHONON_LOAD_ABI, "iplHRTFCreate not resolved");
  }
  var audio_settings = phonon_slot(abi.IPL_AUDIO_SETTINGS_SIZE);
  s_w32(&mut audio_settings, abi.IPL_AUDIO_SETTINGS_SAMPLING_RATE, sampling_rate);
  s_w32(&mut audio_settings, abi.IPL_AUDIO_SETTINGS_FRAME_SIZE, frame_size);
  var hrtf_settings = phonon_slot(abi.IPL_HRTF_SETTINGS_SIZE);
  s_w32(&mut hrtf_settings, abi.IPL_HRTF_SETTINGS_TYPE, abi.IPL_HRTFTYPE_SOFA);
  var p_name = 0;
  unsafe {
    p_name = sofa_path.c_str() as Int;
  }
  s_w64(&mut hrtf_settings, abi.IPL_HRTF_SETTINGS_SOFA_FILE_NAME, p_name);
  s_wf32(&mut hrtf_settings, abi.IPL_HRTF_SETTINGS_VOLUME, volume);
  s_w32(&mut hrtf_settings, abi.IPL_HRTF_SETTINGS_NORM_TYPE, norm_type);
  var out = phonon_slot(8);
  unsafe {
    let f_create = lib.fns[fidx] as fn(Int, *UInt8, *UInt8, *UInt8) -> Int32;
    let rc = f_create(context, audio_settings.as_mut_ptr(), hrtf_settings.as_mut_ptr(),
      out.as_mut_ptr()) as Int;
    if rc != abi.IPL_STATUS_SUCCESS {
      return phonon_err_handle(rc, "iplHRTFCreate(SOFA) rc=" + int_to_str(rc));
    }
    let h = s_r64(&out, 0);
    if h == 0 {
      return phonon_err_handle(PHONON_PROBE_FAILED, "iplHRTFCreate(SOFA) returned a null HRTF");
    }
    return phonon_ok_handle(h);
  }
}

/// `iplHRTFRetain` (returns the retained handle; 0 on failure).
/// Complexity: O(1).
pub fn phonon_hrtf_retain(lib: &PhononLibrary, hrtf: Int) -> Int
  requires: hrtf != 0
{
  let fidx = exports.PHONON_IDX_IPL_HRTF_RETAIN;
  if lib.fns[fidx] == 0 { return 0; }
  unsafe {
    let f_retain = lib.fns[fidx] as fn(Int) -> Int;
    return f_retain(hrtf);
  }
}

/// `iplHRTFRelease` (takes `IPLHRTF*`).
/// Complexity: O(1).
pub fn phonon_hrtf_release(lib: &PhononLibrary, hrtf: Int) -> PhononStatusOutcome
  requires: hrtf != 0
{
  let fidx = exports.PHONON_IDX_IPL_HRTF_RELEASE;
  if lib.fns[fidx] == 0 {
    return phonon_err_status(PHONON_LOAD_ABI, "iplHRTFRelease not resolved");
  }
  var slot = phonon_slot(8);
  s_w64(&mut slot, 0, hrtf);
  unsafe {
    let f_release = lib.fns[fidx] as fn(*UInt8);
    f_release(slot.as_mut_ptr());
  }
  return phonon_ok_status();
}

// =========================================================================
// Audio buffers
// =========================================================================

/// Build a fully XIOM-owned deinterleaved buffer.  The channel-pointer
/// array is materialized in two phases (collect addresses, then write slot
/// bytes) -- see compiler finding B-27 for why the cast cannot share a
/// confined block with the writes.
/// Complexity: O(channels * samples).
pub fn phonon_audio_buffer_new(channels: Int, samples: Int) -> PhononAudioBuffer
  requires: channels > 0
  requires: channels <= 64
  requires: samples > 0
  requires: samples <= 65536
{
  var data: Vec[Float32] = Vec[Float32].new();
  var n: Int = 0;
  while n < channels * samples {
    data.push(0.0);
    n = n + 1;
  }
  var base = 0;
  unsafe {
    base = data.as_mut_ptr() as Int;
  }
  var ptrs = phonon_slot(channels * 8);
  var i: Int = 0;
  while i < channels {
    s_w64(&mut ptrs, i * 8, base + i * samples * 4);
    i = i + 1;
  }
  var slot = phonon_slot(abi.IPL_AUDIO_BUFFER_SIZE);
  s_w32(&mut slot, abi.IPL_AUDIO_BUFFER_NUM_CHANNELS, channels);
  s_w32(&mut slot, abi.IPL_AUDIO_BUFFER_NUM_SAMPLES, samples);
  var p_ptrs = 0;
  unsafe {
    p_ptrs = ptrs.as_mut_ptr() as Int;
  }
  s_w64(&mut slot, abi.IPL_AUDIO_BUFFER_DATA, p_ptrs);
  return PhononAudioBuffer{
    num_channels: channels;
    num_samples: samples;
    slot: slot;
    ptrs: ptrs;
    data: data;
  };
}

/// Write one sample (channel `ch`, index `i`).
/// Complexity: O(1).
pub fn phonon_audio_buffer_set(buf: &mut PhononAudioBuffer, ch: Int, i: Int, v: Float64)
  requires: ch >= 0
  requires: ch < buf.num_channels
  requires: i >= 0
  requires: i < buf.num_samples
{
  buf.data[ch * buf.num_samples + i] = v as Float32;
}

/// Read one sample (channel `ch`, index `i`).
/// Complexity: O(1).
pub fn phonon_audio_buffer_get(buf: &PhononAudioBuffer, ch: Int, i: Int) -> Float64
  requires: ch >= 0
  requires: ch < buf.num_channels
  requires: i >= 0
  requires: i < buf.num_samples
{
  return buf.data[ch * buf.num_samples + i] as Float64;
}

/// Sum of squares of one channel.
/// Complexity: O(samples).
pub fn phonon_audio_buffer_channel_energy(buf: &PhononAudioBuffer, ch: Int) -> Float64
  requires: ch >= 0
  requires: ch < buf.num_channels
{
  var s = 0.0;
  var i: Int = 0;
  while i < buf.num_samples {
    let x = buf.data[ch * buf.num_samples + i] as Float64;
    s = s + x * x;
    i = i + 1;
  }
  return s;
}

/// Total energy across all channels.
/// Complexity: O(channels * samples).
pub fn phonon_audio_buffer_total_energy(buf: &PhononAudioBuffer) -> Float64
  requires: buf.num_channels > 0
{
  var s = 0.0;
  var ch: Int = 0;
  while ch < buf.num_channels {
    s = s + phonon_audio_buffer_channel_energy(buf, ch);
    ch = ch + 1;
  }
  return s;
}

/// `iplAudioBufferAllocate` (DLL-managed planar buffer; the returned slot
/// is read/written by the DLL itself -- use the interleave/deinterleave
/// wrappers to exchange samples).
/// Complexity: O(1) + allocation.
pub fn phonon_audio_buffer_alloc_managed(lib: &PhononLibrary, context: Int,
    channels: Int, samples: Int) -> PhononManagedBuffer
  requires: context != 0
  requires: channels > 0
  requires: samples > 0
{
  let fidx = exports.PHONON_IDX_IPL_AUDIO_BUFFER_ALLOCATE;
  var slot = phonon_slot(abi.IPL_AUDIO_BUFFER_SIZE);
  if lib.fns[fidx] == 0 {
    return PhononManagedBuffer{ ok: false; status: PHONON_LOAD_ABI;
      error: "iplAudioBufferAllocate not resolved"; slot: slot };
  }
  unsafe {
    let f_alloc = lib.fns[fidx] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    let rc = f_alloc(context, channels as Int32, samples as Int32, slot.as_mut_ptr()) as Int;
    if rc != abi.IPL_STATUS_SUCCESS {
      return PhononManagedBuffer{ ok: false; status: rc;
        error: "iplAudioBufferAllocate rc=" + int_to_str(rc); slot: slot };
    }
  }
  return PhononManagedBuffer{ ok: true; status: abi.IPL_STATUS_SUCCESS; error: ""; slot: slot };
}

/// `iplAudioBufferFree`.
/// Complexity: O(1).
pub fn phonon_audio_buffer_free_managed(lib: &PhononLibrary, context: Int,
    slot: &mut Vec[UInt8]) -> PhononStatusOutcome
  requires: context != 0
  requires: slot.len() >= abi.IPL_AUDIO_BUFFER_SIZE
{
  let fidx = exports.PHONON_IDX_IPL_AUDIO_BUFFER_FREE;
  if lib.fns[fidx] == 0 {
    return phonon_err_status(PHONON_LOAD_ABI, "iplAudioBufferFree not resolved");
  }
  unsafe {
    let f_free = lib.fns[fidx] as fn(Int, *UInt8);
    f_free(context, slot.as_mut_ptr());
  }
  return phonon_ok_status();
}

/// `iplAudioBufferInterleave` into an XIOM-owned Float32 vector
/// (`dst.len()` must be >= channels * samples).
/// Complexity: O(channels * samples).
pub fn phonon_audio_buffer_interleave(lib: &PhononLibrary, context: Int,
    slot: &Vec[UInt8], dst: &mut Vec[Float32]) -> PhononStatusOutcome
  requires: context != 0
  requires: slot.len() >= abi.IPL_AUDIO_BUFFER_SIZE
  requires: dst.len() > 0
{
  let fidx = exports.PHONON_IDX_IPL_AUDIO_BUFFER_INTERLEAVE;
  if lib.fns[fidx] == 0 {
    return phonon_err_status(PHONON_LOAD_ABI, "iplAudioBufferInterleave not resolved");
  }
  unsafe {
    let f_interleave = lib.fns[fidx] as fn(Int, *UInt8, *Float32);
    f_interleave(context, slot.as_mut_ptr(), dst.as_mut_ptr());
  }
  return phonon_ok_status();
}

/// `iplAudioBufferDeinterleave` from an XIOM-owned Float32 vector into a
/// DLL-managed buffer slot.
/// Complexity: O(channels * samples).
pub fn phonon_audio_buffer_deinterleave(lib: &PhononLibrary, context: Int,
    src: &mut Vec[Float32], slot: &mut Vec[UInt8]) -> PhononStatusOutcome
  requires: context != 0
  requires: src.len() > 0
  requires: slot.len() >= abi.IPL_AUDIO_BUFFER_SIZE
{
  let fidx = exports.PHONON_IDX_IPL_AUDIO_BUFFER_DEINTERLEAVE;
  if lib.fns[fidx] == 0 {
    return phonon_err_status(PHONON_LOAD_ABI, "iplAudioBufferDeinterleave not resolved");
  }
  unsafe {
    let f_deinterleave = lib.fns[fidx] as fn(Int, *Float32, *UInt8);
    f_deinterleave(context, src.as_mut_ptr(), slot.as_mut_ptr());
  }
  return phonon_ok_status();
}

/// `iplAudioBufferMix` (both managed slots; same channel/sample counts).
/// Complexity: O(channels * samples).
pub fn phonon_audio_buffer_mix(lib: &PhononLibrary, context: Int,
    src: &Vec[UInt8], dst: &mut Vec[UInt8]) -> PhononStatusOutcome
  requires: context != 0
  requires: src.len() >= abi.IPL_AUDIO_BUFFER_SIZE
  requires: dst.len() >= abi.IPL_AUDIO_BUFFER_SIZE
{
  let fidx = exports.PHONON_IDX_IPL_AUDIO_BUFFER_MIX;
  if lib.fns[fidx] == 0 {
    return phonon_err_status(PHONON_LOAD_ABI, "iplAudioBufferMix not resolved");
  }
  unsafe {
    let f_mix = lib.fns[fidx] as fn(Int, *UInt8, *UInt8);
    f_mix(context, src.as_mut_ptr(), dst.as_mut_ptr());
  }
  return phonon_ok_status();
}

/// `iplAudioBufferDownmix` (multi-channel managed slot -> mono managed
/// slot).
/// Complexity: O(channels * samples).
pub fn phonon_audio_buffer_downmix(lib: &PhononLibrary, context: Int,
    src: &Vec[UInt8], dst: &mut Vec[UInt8]) -> PhononStatusOutcome
  requires: context != 0
  requires: src.len() >= abi.IPL_AUDIO_BUFFER_SIZE
  requires: dst.len() >= abi.IPL_AUDIO_BUFFER_SIZE
{
  let fidx = exports.PHONON_IDX_IPL_AUDIO_BUFFER_DOWNMIX;
  if lib.fns[fidx] == 0 {
    return phonon_err_status(PHONON_LOAD_ABI, "iplAudioBufferDownmix not resolved");
  }
  unsafe {
    let f_downmix = lib.fns[fidx] as fn(Int, *UInt8, *UInt8);
    f_downmix(context, src.as_mut_ptr(), dst.as_mut_ptr());
  }
  return phonon_ok_status();
}

/// `iplAudioBufferConvertAmbisonics` (N3D/SN3D/FUMA conversion; may be
/// applied in place).
/// Complexity: O(channels * samples).
pub fn phonon_audio_buffer_convert_ambisonics(lib: &PhononLibrary, context: Int,
    in_type: Int, out_type: Int, src: &Vec[UInt8], dst: &mut Vec[UInt8])
    -> PhononStatusOutcome
  requires: context != 0
  requires: src.len() >= abi.IPL_AUDIO_BUFFER_SIZE
  requires: dst.len() >= abi.IPL_AUDIO_BUFFER_SIZE
{
  let fidx = exports.PHONON_IDX_IPL_AUDIO_BUFFER_CONVERT_AMBISONICS;
  if lib.fns[fidx] == 0 {
    return phonon_err_status(PHONON_LOAD_ABI, "iplAudioBufferConvertAmbisonics not resolved");
  }
  unsafe {
    let f_convert = lib.fns[fidx] as fn(Int, Int32, Int32, *UInt8, *UInt8);
    f_convert(context, in_type as Int32, out_type as Int32, src.as_mut_ptr(), dst.as_mut_ptr());
  }
  return phonon_ok_status();
}

// =========================================================================
// Local helpers (stdlib convert must not be called inside confined blocks;
// same rule as the other binding modules)
// =========================================================================

pub fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  if neg { return "-" + out; }
  return out;
}

// =========================================================================
// Settings builders (shared)
// =========================================================================

/// `IPLSpeakerLayout` at `off` in `slot`: built-in layouts only (no
/// CUSTOM speaker array -- that needs an owned pointer array, out of the
/// declared surface).
fn set_speaker_layout(slot: &mut Vec[UInt8], off: Int, layout_type: Int)
  requires: off >= 0
  requires: off + 15 < slot.len()
  requires: layout_type >= 0
  requires: layout_type < 5
{
  s_w32(slot, off + 0, layout_type);
  s_w32(slot, off + 4, 0);
}

fn write_vec3(slot: &mut Vec[UInt8], off: Int, v: &PhononVector3)
  requires: off >= 0
  requires: off + 11 < slot.len()
{
  s_wf32(slot, off + 0, v.x);
  s_wf32(slot, off + 4, v.y);
  s_wf32(slot, off + 8, v.z);
}

fn write_orientation(slot: &mut Vec[UInt8], off: Int, o: PhononOrientation)
  requires: off >= 0
  requires: off + 47 < slot.len()
{
  write_vec3(slot, off + 0, o.right);
  write_vec3(slot, off + 12, o.up);
  write_vec3(slot, off + 24, o.ahead);
  write_vec3(slot, off + 36, o.origin);
}

fn audio_settings_slot(sampling_rate: Int, frame_size: Int) -> Vec[UInt8]
  requires: sampling_rate > 0
  requires: frame_size > 0
{
  var slot = phonon_slot(abi.IPL_AUDIO_SETTINGS_SIZE);
  s_w32(&mut slot, abi.IPL_AUDIO_SETTINGS_SAMPLING_RATE, sampling_rate);
  s_w32(&mut slot, abi.IPL_AUDIO_SETTINGS_FRAME_SIZE, frame_size);
  return slot;
}

fn create_effect(lib: &PhononLibrary, fn_idx: Int, context: Int,
    audio_settings: &Vec[UInt8], effect_settings: &mut Vec[UInt8]) -> PhononHandleOutcome
  requires: context != 0
  requires: audio_settings.len() >= abi.IPL_AUDIO_SETTINGS_SIZE
  requires: effect_settings.len() > 0
{
  if lib.fns[fn_idx] == 0 {
    return phonon_err_handle(PHONON_LOAD_ABI, "effect create not resolved");
  }
  var out = phonon_slot(8);
  unsafe {
    let f_create = lib.fns[fn_idx] as fn(Int, *UInt8, *UInt8, *UInt8) -> Int32;
    let rc = f_create(context, audio_settings.as_mut_ptr(), effect_settings.as_mut_ptr(),
      out.as_mut_ptr()) as Int;
    if rc != abi.IPL_STATUS_SUCCESS {
      return phonon_err_handle(rc, "effect create rc=" + int_to_str(rc));
    }
    let h = s_r64(&out, 0);
    if h == 0 {
      return phonon_err_handle(PHONON_PROBE_FAILED, "effect create returned a null handle");
    }
    return phonon_ok_handle(h);
  }
}

fn apply_effect(lib: &PhononLibrary, fn_idx: Int, effect: Int, params: &mut Vec[UInt8],
    in_buf: &PhononAudioBuffer, out_buf: &mut PhononAudioBuffer) -> PhononEffectOutcome
  requires: effect != 0
  requires: params.len() > 0
{
  if lib.fns[fn_idx] == 0 {
    return phonon_err_effect("effect apply not resolved");
  }
  unsafe {
    let f_apply = lib.fns[fn_idx] as fn(Int, *UInt8, *UInt8, *UInt8) -> Int32;
    let st = f_apply(effect, params.as_mut_ptr(), in_buf.slot.as_mut_ptr(),
      out_buf.slot.as_mut_ptr()) as Int;
    return phonon_ok_effect(st);
  }
}

fn apply_effect_inplace(lib: &PhononLibrary, fn_idx: Int, effect: Int,
    params: &mut Vec[UInt8], buf: &mut PhononAudioBuffer) -> PhononEffectOutcome
  requires: effect != 0
  requires: params.len() > 0
{
  if lib.fns[fn_idx] == 0 {
    return phonon_err_effect("effect apply not resolved");
  }
  unsafe {
    let f_apply = lib.fns[fn_idx] as fn(Int, *UInt8, *UInt8, *UInt8) -> Int32;
    let st = f_apply(effect, params.as_mut_ptr(), buf.slot.as_mut_ptr(),
      buf.slot.as_mut_ptr()) as Int;
    return phonon_ok_effect(st);
  }
}

fn reset_effect(lib: &PhononLibrary, fn_idx: Int, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  if lib.fns[fn_idx] == 0 {
    return phonon_err_status(PHONON_LOAD_ABI, "effect reset not resolved");
  }
  unsafe {
    let f_reset = lib.fns[fn_idx] as fn(Int);
    f_reset(effect);
  }
  return phonon_ok_status();
}

fn retain_effect(lib: &PhononLibrary, fn_idx: Int, effect: Int) -> Int
  requires: effect != 0
{
  if lib.fns[fn_idx] == 0 { return 0; }
  unsafe {
    let f_retain = lib.fns[fn_idx] as fn(Int) -> Int;
    return f_retain(effect);
  }
}

fn release_effect(lib: &PhononLibrary, fn_idx: Int, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  if lib.fns[fn_idx] == 0 {
    return phonon_err_status(PHONON_LOAD_ABI, "effect release not resolved");
  }
  var slot = phonon_slot(8);
  s_w64(&mut slot, 0, effect);
  unsafe {
    let f_release = lib.fns[fn_idx] as fn(*UInt8);
    f_release(slot.as_mut_ptr());
  }
  return phonon_ok_status();
}

fn tail_size_effect(lib: &PhononLibrary, fn_idx: Int, effect: Int) -> Int
  requires: effect != 0
{
  if lib.fns[fn_idx] == 0 { return 0; }
  unsafe {
    let f_tail = lib.fns[fn_idx] as fn(Int) -> Int32;
    return f_tail(effect) as Int;
  }
}

fn get_tail_effect(lib: &PhononLibrary, fn_idx: Int, effect: Int,
    out_buf: &mut PhononAudioBuffer) -> PhononEffectOutcome
  requires: effect != 0
{
  if lib.fns[fn_idx] == 0 {
    return phonon_err_effect("effect get_tail not resolved");
  }
  unsafe {
    let f_tail = lib.fns[fn_idx] as fn(Int, *UInt8) -> Int32;
    let st = f_tail(effect, out_buf.slot.as_mut_ptr()) as Int;
    return phonon_ok_effect(st);
  }
}

// =========================================================================
// Binaural effect
// =========================================================================

/// `iplBinauralEffectCreate`.
/// Complexity: O(1).
pub fn phonon_binaural_create(lib: &PhononLibrary, context: Int, sampling_rate: Int,
    frame_size: Int, hrtf: Int) -> PhononHandleOutcome
  requires: context != 0
  requires: sampling_rate > 0
  requires: frame_size > 0
  requires: hrtf != 0
{
  var aset = audio_settings_slot(sampling_rate, frame_size);
  var eset = phonon_slot(abi.IPL_BINAURAL_EFFECT_SETTINGS_SIZE);
  s_w64(&mut eset, abi.IPL_BINAURAL_EFFECT_SETTINGS_HRTF, hrtf);
  return create_effect(lib, exports.PHONON_IDX_IPL_BINAURAL_EFFECT_CREATE, context, &aset, &mut eset);
}

/// `iplBinauralEffectApply` (in 1- or 2-channel, out 2-channel).
/// Complexity: O(samples).
pub fn phonon_binaural_apply(lib: &PhononLibrary, effect: Int, in_buf: &PhononAudioBuffer,
    out_buf: &mut PhononAudioBuffer, direction: &PhononVector3, interpolation: Int,
    spatial_blend: Float64, hrtf: Int) -> PhononEffectOutcome
  requires: effect != 0
  requires: in_buf.num_channels >= 1
  requires: out_buf.num_channels >= 2
  requires: hrtf != 0
{
  var params = phonon_slot(abi.IPL_BINAURAL_EFFECT_PARAMS_SIZE);
  write_vec3(&mut params, abi.IPL_BINAURAL_EFFECT_PARAMS_DIRECTION, direction);
  s_w32(&mut params, abi.IPL_BINAURAL_EFFECT_PARAMS_INTERPOLATION, interpolation);
  s_wf32(&mut params, abi.IPL_BINAURAL_EFFECT_PARAMS_SPATIAL_BLEND, spatial_blend);
  s_w64(&mut params, abi.IPL_BINAURAL_EFFECT_PARAMS_HRTF, hrtf);
  return apply_effect(lib, exports.PHONON_IDX_IPL_BINAURAL_EFFECT_APPLY, effect, &mut params,
    in_buf, out_buf);
}

/// `iplBinauralEffectReset`.
/// Complexity: O(1).
pub fn phonon_binaural_reset(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return reset_effect(lib, exports.PHONON_IDX_IPL_BINAURAL_EFFECT_RESET, effect);
}

/// `iplBinauralEffectRetain`.
/// Complexity: O(1).
pub fn phonon_binaural_retain(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return retain_effect(lib, exports.PHONON_IDX_IPL_BINAURAL_EFFECT_RETAIN, effect);
}

/// `iplBinauralEffectRelease`.
/// Complexity: O(1).
pub fn phonon_binaural_release(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return release_effect(lib, exports.PHONON_IDX_IPL_BINAURAL_EFFECT_RELEASE, effect);
}

/// `iplBinauralEffectGetTailSize`.
/// Complexity: O(1).
pub fn phonon_binaural_tail_size(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return tail_size_effect(lib, exports.PHONON_IDX_IPL_BINAURAL_EFFECT_GET_TAIL_SIZE, effect);
}

/// `iplBinauralEffectGetTail` (out 2-channel).
/// Complexity: O(samples).
pub fn phonon_binaural_get_tail(lib: &PhononLibrary, effect: Int,
    out_buf: &mut PhononAudioBuffer) -> PhononEffectOutcome
  requires: effect != 0
  requires: out_buf.num_channels >= 2
{
  return get_tail_effect(lib, exports.PHONON_IDX_IPL_BINAURAL_EFFECT_GET_TAIL, effect, out_buf);
}

// =========================================================================
// Panning effect
// =========================================================================

/// `iplPanningEffectCreate` (built-in speaker layout).
/// Complexity: O(1).
pub fn phonon_panning_create(lib: &PhononLibrary, context: Int, sampling_rate: Int,
    frame_size: Int, layout_type: Int) -> PhononHandleOutcome
  requires: context != 0
  requires: sampling_rate > 0
  requires: frame_size > 0
{
  var aset = audio_settings_slot(sampling_rate, frame_size);
  var eset = phonon_slot(abi.IPL_PANNING_EFFECT_SETTINGS_SIZE);
  set_speaker_layout(&mut eset, abi.IPL_PANNING_EFFECT_SETTINGS_SPEAKER_LAYOUT, layout_type);
  return create_effect(lib, exports.PHONON_IDX_IPL_PANNING_EFFECT_CREATE, context, &aset, &mut eset);
}

/// `iplPanningEffectApply` (in 1-channel, out `layout_type` channels).
/// Complexity: O(samples).
pub fn phonon_panning_apply(lib: &PhononLibrary, effect: Int, in_buf: &PhononAudioBuffer,
    out_buf: &mut PhononAudioBuffer, direction: PhononVector3) -> PhononEffectOutcome
  requires: effect != 0
  requires: in_buf.num_channels >= 1
  requires: out_buf.num_channels >= 1
{
  var params = phonon_slot(abi.IPL_PANNING_EFFECT_PARAMS_SIZE);
  write_vec3(&mut params, abi.IPL_PANNING_EFFECT_PARAMS_DIRECTION, direction);
  return apply_effect(lib, exports.PHONON_IDX_IPL_PANNING_EFFECT_APPLY, effect, &mut params,
    in_buf, out_buf);
}

/// `iplPanningEffectReset`.
/// Complexity: O(1).
pub fn phonon_panning_reset(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return reset_effect(lib, exports.PHONON_IDX_IPL_PANNING_EFFECT_RESET, effect);
}

/// `iplPanningEffectRetain`.
/// Complexity: O(1).
pub fn phonon_panning_retain(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return retain_effect(lib, exports.PHONON_IDX_IPL_PANNING_EFFECT_RETAIN, effect);
}

/// `iplPanningEffectRelease`.
/// Complexity: O(1).
pub fn phonon_panning_release(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return release_effect(lib, exports.PHONON_IDX_IPL_PANNING_EFFECT_RELEASE, effect);
}

/// `iplPanningEffectGetTailSize`.
/// Complexity: O(1).
pub fn phonon_panning_tail_size(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return tail_size_effect(lib, exports.PHONON_IDX_IPL_PANNING_EFFECT_GET_TAIL_SIZE, effect);
}

/// `iplPanningEffectGetTail`.
/// Complexity: O(samples).
pub fn phonon_panning_get_tail(lib: &PhononLibrary, effect: Int,
    out_buf: &mut PhononAudioBuffer) -> PhononEffectOutcome
  requires: effect != 0
  requires: out_buf.num_channels >= 1
{
  return get_tail_effect(lib, exports.PHONON_IDX_IPL_PANNING_EFFECT_GET_TAIL, effect, out_buf);
}

// =========================================================================
// Virtual surround effect
// =========================================================================

/// `iplVirtualSurroundEffectCreate`.
/// Complexity: O(1).
pub fn phonon_virtual_surround_create(lib: &PhononLibrary, context: Int,
    sampling_rate: Int, frame_size: Int, layout_type: Int, hrtf: Int) -> PhononHandleOutcome
  requires: context != 0
  requires: sampling_rate > 0
  requires: frame_size > 0
  requires: hrtf != 0
{
  var aset = audio_settings_slot(sampling_rate, frame_size);
  var eset = phonon_slot(abi.IPL_VIRTUAL_SURROUND_EFFECT_SETTINGS_SIZE);
  set_speaker_layout(&mut eset, abi.IPL_VIRTUAL_SURROUND_EFFECT_SETTINGS_SPEAKER_LAYOUT, layout_type);
  s_w64(&mut eset, abi.IPL_VIRTUAL_SURROUND_EFFECT_SETTINGS_HRTF, hrtf);
  return create_effect(lib, exports.PHONON_IDX_IPL_VIRTUAL_SURROUND_EFFECT_CREATE, context,
    &aset, &mut eset);
}

/// `iplVirtualSurroundEffectApply` (in `layout_type` channels, out
/// 2-channel).
/// Complexity: O(samples).
pub fn phonon_virtual_surround_apply(lib: &PhononLibrary, effect: Int,
    in_buf: &PhononAudioBuffer, out_buf: &mut PhononAudioBuffer, hrtf: Int) -> PhononEffectOutcome
  requires: effect != 0
  requires: in_buf.num_channels >= 2
  requires: out_buf.num_channels >= 2
  requires: hrtf != 0
{
  var params = phonon_slot(abi.IPL_VIRTUAL_SURROUND_EFFECT_PARAMS_SIZE);
  s_w64(&mut params, abi.IPL_VIRTUAL_SURROUND_EFFECT_PARAMS_HRTF, hrtf);
  return apply_effect(lib, exports.PHONON_IDX_IPL_VIRTUAL_SURROUND_EFFECT_APPLY, effect,
    &mut params, in_buf, out_buf);
}

/// `iplVirtualSurroundEffectReset`.
/// Complexity: O(1).
pub fn phonon_virtual_surround_reset(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return reset_effect(lib, exports.PHONON_IDX_IPL_VIRTUAL_SURROUND_EFFECT_RESET, effect);
}

/// `iplVirtualSurroundEffectRetain`.
/// Complexity: O(1).
pub fn phonon_virtual_surround_retain(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return retain_effect(lib, exports.PHONON_IDX_IPL_VIRTUAL_SURROUND_EFFECT_RETAIN, effect);
}

/// `iplVirtualSurroundEffectRelease`.
/// Complexity: O(1).
pub fn phonon_virtual_surround_release(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return release_effect(lib, exports.PHONON_IDX_IPL_VIRTUAL_SURROUND_EFFECT_RELEASE, effect);
}

/// `iplVirtualSurroundEffectGetTailSize`.
/// Complexity: O(1).
pub fn phonon_virtual_surround_tail_size(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return tail_size_effect(lib, exports.PHONON_IDX_IPL_VIRTUAL_SURROUND_EFFECT_GET_TAIL_SIZE, effect);
}

/// `iplVirtualSurroundEffectGetTail`.
/// Complexity: O(samples).
pub fn phonon_virtual_surround_get_tail(lib: &PhononLibrary, effect: Int,
    out_buf: &mut PhononAudioBuffer) -> PhononEffectOutcome
  requires: effect != 0
  requires: out_buf.num_channels >= 2
{
  return get_tail_effect(lib, exports.PHONON_IDX_IPL_VIRTUAL_SURROUND_EFFECT_GET_TAIL,
    effect, out_buf);
}

// =========================================================================
// Ambisonics encode effect
// =========================================================================

/// `iplAmbisonicsEncodeEffectCreate` (`max_order` >= 1).
/// Complexity: O(1).
pub fn phonon_ambisonics_encode_create(lib: &PhononLibrary, context: Int,
    sampling_rate: Int, frame_size: Int, max_order: Int) -> PhononHandleOutcome
  requires: context != 0
  requires: sampling_rate > 0
  requires: frame_size > 0
  requires: max_order >= 1
{
  var aset = audio_settings_slot(sampling_rate, frame_size);
  var eset = phonon_slot(abi.IPL_AMBISONICS_ENCODE_EFFECT_SETTINGS_SIZE);
  s_w32(&mut eset, abi.IPL_AMBISONICS_ENCODE_EFFECT_SETTINGS_MAX_ORDER, max_order);
  return create_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ENCODE_EFFECT_CREATE, context,
    &aset, &mut eset);
}

/// `iplAmbisonicsEncodeEffectApply` (in 1-channel, out `(order+1)^2`
/// channels).
/// Complexity: O(samples).
pub fn phonon_ambisonics_encode_apply(lib: &PhononLibrary, effect: Int,
    in_buf: &PhononAudioBuffer, out_buf: &mut PhononAudioBuffer, direction: &PhononVector3,
    order: Int) -> PhononEffectOutcome
  requires: effect != 0
  requires: in_buf.num_channels >= 1
  requires: out_buf.num_channels >= 1
  requires: order >= 1
{
  var params = phonon_slot(abi.IPL_AMBISONICS_ENCODE_EFFECT_PARAMS_SIZE);
  write_vec3(&mut params, abi.IPL_AMBISONICS_ENCODE_EFFECT_PARAMS_DIRECTION, direction);
  s_w32(&mut params, abi.IPL_AMBISONICS_ENCODE_EFFECT_PARAMS_ORDER, order);
  return apply_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ENCODE_EFFECT_APPLY, effect,
    &mut params, in_buf, out_buf);
}

/// `iplAmbisonicsEncodeEffectReset`.
/// Complexity: O(1).
pub fn phonon_ambisonics_encode_reset(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return reset_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ENCODE_EFFECT_RESET, effect);
}

/// `iplAmbisonicsEncodeEffectRetain`.
/// Complexity: O(1).
pub fn phonon_ambisonics_encode_retain(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return retain_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ENCODE_EFFECT_RETAIN, effect);
}

/// `iplAmbisonicsEncodeEffectRelease`.
/// Complexity: O(1).
pub fn phonon_ambisonics_encode_release(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return release_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ENCODE_EFFECT_RELEASE, effect);
}

/// `iplAmbisonicsEncodeEffectGetTailSize`.
/// Complexity: O(1).
pub fn phonon_ambisonics_encode_tail_size(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return tail_size_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ENCODE_EFFECT_GET_TAIL_SIZE, effect);
}

/// `iplAmbisonicsEncodeEffectGetTail`.
/// Complexity: O(samples).
pub fn phonon_ambisonics_encode_get_tail(lib: &PhononLibrary, effect: Int,
    out_buf: &mut PhononAudioBuffer) -> PhononEffectOutcome
  requires: effect != 0
  requires: out_buf.num_channels >= 1
{
  return get_tail_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ENCODE_EFFECT_GET_TAIL,
    effect, out_buf);
}

// =========================================================================
// Ambisonics panning effect
// =========================================================================

/// `iplAmbisonicsPanningEffectCreate`.
/// Complexity: O(1).
pub fn phonon_ambisonics_panning_create(lib: &PhononLibrary, context: Int,
    sampling_rate: Int, frame_size: Int, layout_type: Int, max_order: Int) -> PhononHandleOutcome
  requires: context != 0
  requires: sampling_rate > 0
  requires: frame_size > 0
  requires: max_order >= 1
{
  var aset = audio_settings_slot(sampling_rate, frame_size);
  var eset = phonon_slot(abi.IPL_AMBISONICS_PANNING_EFFECT_SETTINGS_SIZE);
  set_speaker_layout(&mut eset, abi.IPL_AMBISONICS_PANNING_EFFECT_SETTINGS_SPEAKER_LAYOUT, layout_type);
  s_w32(&mut eset, abi.IPL_AMBISONICS_PANNING_EFFECT_SETTINGS_MAX_ORDER, max_order);
  return create_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_PANNING_EFFECT_CREATE, context,
    &aset, &mut eset);
}

/// `iplAmbisonicsPanningEffectApply` (in `(order+1)^2` channels, out
/// `layout_type` channels).
/// Complexity: O(samples).
pub fn phonon_ambisonics_panning_apply(lib: &PhononLibrary, effect: Int,
    in_buf: &PhononAudioBuffer, out_buf: &mut PhononAudioBuffer, order: Int)
    -> PhononEffectOutcome
  requires: effect != 0
  requires: in_buf.num_channels >= 1
  requires: out_buf.num_channels >= 1
  requires: order >= 1
{
  var params = phonon_slot(abi.IPL_AMBISONICS_PANNING_EFFECT_PARAMS_SIZE);
  s_w32(&mut params, abi.IPL_AMBISONICS_PANNING_EFFECT_PARAMS_ORDER, order);
  return apply_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_PANNING_EFFECT_APPLY, effect,
    &mut params, in_buf, out_buf);
}

/// `iplAmbisonicsPanningEffectReset`.
/// Complexity: O(1).
pub fn phonon_ambisonics_panning_reset(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return reset_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_PANNING_EFFECT_RESET, effect);
}

/// `iplAmbisonicsPanningEffectRetain`.
/// Complexity: O(1).
pub fn phonon_ambisonics_panning_retain(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return retain_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_PANNING_EFFECT_RETAIN, effect);
}

/// `iplAmbisonicsPanningEffectRelease`.
/// Complexity: O(1).
pub fn phonon_ambisonics_panning_release(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return release_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_PANNING_EFFECT_RELEASE, effect);
}

/// `iplAmbisonicsPanningEffectGetTailSize`.
/// Complexity: O(1).
pub fn phonon_ambisonics_panning_tail_size(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return tail_size_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_PANNING_EFFECT_GET_TAIL_SIZE, effect);
}

/// `iplAmbisonicsPanningEffectGetTail`.
/// Complexity: O(samples).
pub fn phonon_ambisonics_panning_get_tail(lib: &PhononLibrary, effect: Int,
    out_buf: &mut PhononAudioBuffer) -> PhononEffectOutcome
  requires: effect != 0
  requires: out_buf.num_channels >= 1
{
  return get_tail_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_PANNING_EFFECT_GET_TAIL,
    effect, out_buf);
}

// =========================================================================
// Ambisonics binaural effect
// =========================================================================

/// `iplAmbisonicsBinauralEffectCreate`.
/// Complexity: O(1).
pub fn phonon_ambisonics_binaural_create(lib: &PhononLibrary, context: Int,
    sampling_rate: Int, frame_size: Int, hrtf: Int, max_order: Int) -> PhononHandleOutcome
  requires: context != 0
  requires: sampling_rate > 0
  requires: frame_size > 0
  requires: hrtf != 0
  requires: max_order >= 1
{
  var aset = audio_settings_slot(sampling_rate, frame_size);
  var eset = phonon_slot(abi.IPL_AMBISONICS_BINAURAL_EFFECT_SETTINGS_SIZE);
  s_w64(&mut eset, abi.IPL_AMBISONICS_BINAURAL_EFFECT_SETTINGS_HRTF, hrtf);
  s_w32(&mut eset, abi.IPL_AMBISONICS_BINAURAL_EFFECT_SETTINGS_MAX_ORDER, max_order);
  return create_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_BINAURAL_EFFECT_CREATE, context,
    &aset, &mut eset);
}

/// `iplAmbisonicsBinauralEffectApply` (in `(order+1)^2` channels, out
/// 2-channel).
/// Complexity: O(samples).
pub fn phonon_ambisonics_binaural_apply(lib: &PhononLibrary, effect: Int,
    in_buf: &PhononAudioBuffer, out_buf: &mut PhononAudioBuffer, hrtf: Int, order: Int)
    -> PhononEffectOutcome
  requires: effect != 0
  requires: in_buf.num_channels >= 1
  requires: out_buf.num_channels >= 2
  requires: hrtf != 0
  requires: order >= 1
{
  var params = phonon_slot(abi.IPL_AMBISONICS_BINAURAL_EFFECT_PARAMS_SIZE);
  s_w64(&mut params, abi.IPL_AMBISONICS_BINAURAL_EFFECT_PARAMS_HRTF, hrtf);
  s_w32(&mut params, abi.IPL_AMBISONICS_BINAURAL_EFFECT_PARAMS_ORDER, order);
  return apply_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_BINAURAL_EFFECT_APPLY, effect,
    &mut params, in_buf, out_buf);
}

/// `iplAmbisonicsBinauralEffectReset`.
/// Complexity: O(1).
pub fn phonon_ambisonics_binaural_reset(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return reset_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_BINAURAL_EFFECT_RESET, effect);
}

/// `iplAmbisonicsBinauralEffectRetain`.
/// Complexity: O(1).
pub fn phonon_ambisonics_binaural_retain(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return retain_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_BINAURAL_EFFECT_RETAIN, effect);
}

/// `iplAmbisonicsBinauralEffectRelease`.
/// Complexity: O(1).
pub fn phonon_ambisonics_binaural_release(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return release_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_BINAURAL_EFFECT_RELEASE, effect);
}

/// `iplAmbisonicsBinauralEffectGetTailSize`.
/// Complexity: O(1).
pub fn phonon_ambisonics_binaural_tail_size(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return tail_size_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_BINAURAL_EFFECT_GET_TAIL_SIZE, effect);
}

/// `iplAmbisonicsBinauralEffectGetTail`.
/// Complexity: O(samples).
pub fn phonon_ambisonics_binaural_get_tail(lib: &PhononLibrary, effect: Int,
    out_buf: &mut PhononAudioBuffer) -> PhononEffectOutcome
  requires: effect != 0
  requires: out_buf.num_channels >= 2
{
  return get_tail_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_BINAURAL_EFFECT_GET_TAIL,
    effect, out_buf);
}

// =========================================================================
// Ambisonics rotation effect
// =========================================================================

/// `iplAmbisonicsRotationEffectCreate`.
/// Complexity: O(1).
pub fn phonon_ambisonics_rotation_create(lib: &PhononLibrary, context: Int,
    sampling_rate: Int, frame_size: Int, max_order: Int) -> PhononHandleOutcome
  requires: context != 0
  requires: sampling_rate > 0
  requires: frame_size > 0
  requires: max_order >= 1
{
  var aset = audio_settings_slot(sampling_rate, frame_size);
  var eset = phonon_slot(abi.IPL_AMBISONICS_ROTATION_EFFECT_SETTINGS_SIZE);
  s_w32(&mut eset, abi.IPL_AMBISONICS_ROTATION_EFFECT_SETTINGS_MAX_ORDER, max_order);
  return create_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ROTATION_EFFECT_CREATE, context,
    &aset, &mut eset);
}

/// `iplAmbisonicsRotationEffectApply` (in/out `(order+1)^2` channels).
/// Complexity: O(samples).
pub fn phonon_ambisonics_rotation_apply(lib: &PhononLibrary, effect: Int,
    in_buf: &PhononAudioBuffer, out_buf: &mut PhononAudioBuffer, orientation: &PhononOrientation,
    order: Int) -> PhononEffectOutcome
  requires: effect != 0
  requires: in_buf.num_channels >= 1
  requires: out_buf.num_channels >= 1
  requires: order >= 1
{
  var params = phonon_slot(abi.IPL_AMBISONICS_ROTATION_EFFECT_PARAMS_SIZE);
  write_orientation(&mut params, abi.IPL_AMBISONICS_ROTATION_EFFECT_PARAMS_ORIENTATION, orientation);
  s_w32(&mut params, abi.IPL_AMBISONICS_ROTATION_EFFECT_PARAMS_ORDER, order);
  return apply_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ROTATION_EFFECT_APPLY, effect,
    &mut params, in_buf, out_buf);
}

/// `iplAmbisonicsRotationEffectReset`.
/// Complexity: O(1).
pub fn phonon_ambisonics_rotation_reset(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return reset_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ROTATION_EFFECT_RESET, effect);
}

/// `iplAmbisonicsRotationEffectRetain`.
/// Complexity: O(1).
pub fn phonon_ambisonics_rotation_retain(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return retain_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ROTATION_EFFECT_RETAIN, effect);
}

/// `iplAmbisonicsRotationEffectRelease`.
/// Complexity: O(1).
pub fn phonon_ambisonics_rotation_release(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return release_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ROTATION_EFFECT_RELEASE, effect);
}

/// `iplAmbisonicsRotationEffectGetTailSize`.
/// Complexity: O(1).
pub fn phonon_ambisonics_rotation_tail_size(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return tail_size_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ROTATION_EFFECT_GET_TAIL_SIZE, effect);
}

/// `iplAmbisonicsRotationEffectGetTail`.
/// Complexity: O(samples).
pub fn phonon_ambisonics_rotation_get_tail(lib: &PhononLibrary, effect: Int,
    out_buf: &mut PhononAudioBuffer) -> PhononEffectOutcome
  requires: effect != 0
  requires: out_buf.num_channels >= 1
{
  return get_tail_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_ROTATION_EFFECT_GET_TAIL,
    effect, out_buf);
}

// =========================================================================
// Ambisonics decode effect
// =========================================================================

/// `iplAmbisonicsDecodeEffectCreate`.
/// Complexity: O(1).
pub fn phonon_ambisonics_decode_create(lib: &PhononLibrary, context: Int,
    sampling_rate: Int, frame_size: Int, layout_type: Int, hrtf: Int, max_order: Int)
    -> PhononHandleOutcome
  requires: context != 0
  requires: sampling_rate > 0
  requires: frame_size > 0
  requires: hrtf != 0
  requires: max_order >= 1
{
  var aset = audio_settings_slot(sampling_rate, frame_size);
  var eset = phonon_slot(abi.IPL_AMBISONICS_DECODE_EFFECT_SETTINGS_SIZE);
  set_speaker_layout(&mut eset, abi.IPL_AMBISONICS_DECODE_EFFECT_SETTINGS_SPEAKER_LAYOUT, layout_type);
  s_w64(&mut eset, abi.IPL_AMBISONICS_DECODE_EFFECT_SETTINGS_HRTF, hrtf);
  s_w32(&mut eset, abi.IPL_AMBISONICS_DECODE_EFFECT_SETTINGS_MAX_ORDER, max_order);
  return create_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_DECODE_EFFECT_CREATE, context,
    &aset, &mut eset);
}

/// `iplAmbisonicsDecodeEffectApply` (in `(order+1)^2` channels; out
/// 2-channel for binaural, `layout_type` channels for panning).
/// Complexity: O(samples).
pub fn phonon_ambisonics_decode_apply(lib: &PhononLibrary, effect: Int,
    in_buf: &PhononAudioBuffer, out_buf: &mut PhononAudioBuffer, order: Int, hrtf: Int,
    orientation: &PhononOrientation, binaural: Bool) -> PhononEffectOutcome
  requires: effect != 0
  requires: in_buf.num_channels >= 1
  requires: out_buf.num_channels >= 1
  requires: hrtf != 0
  requires: order >= 1
{
  var params = phonon_slot(abi.IPL_AMBISONICS_DECODE_EFFECT_PARAMS_SIZE);
  s_w32(&mut params, abi.IPL_AMBISONICS_DECODE_EFFECT_PARAMS_ORDER, order);
  s_w64(&mut params, abi.IPL_AMBISONICS_DECODE_EFFECT_PARAMS_HRTF, hrtf);
  write_orientation(&mut params, abi.IPL_AMBISONICS_DECODE_EFFECT_PARAMS_ORIENTATION, orientation);
  var bin = 0;
  if binaural { bin = 1; }
  s_w32(&mut params, abi.IPL_AMBISONICS_DECODE_EFFECT_PARAMS_BINAURAL, bin);
  return apply_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_DECODE_EFFECT_APPLY, effect,
    &mut params, in_buf, out_buf);
}

/// `iplAmbisonicsDecodeEffectReset`.
/// Complexity: O(1).
pub fn phonon_ambisonics_decode_reset(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return reset_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_DECODE_EFFECT_RESET, effect);
}

/// `iplAmbisonicsDecodeEffectRetain`.
/// Complexity: O(1).
pub fn phonon_ambisonics_decode_retain(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return retain_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_DECODE_EFFECT_RETAIN, effect);
}

/// `iplAmbisonicsDecodeEffectRelease`.
/// Complexity: O(1).
pub fn phonon_ambisonics_decode_release(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return release_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_DECODE_EFFECT_RELEASE, effect);
}

/// `iplAmbisonicsDecodeEffectGetTailSize`.
/// Complexity: O(1).
pub fn phonon_ambisonics_decode_tail_size(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return tail_size_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_DECODE_EFFECT_GET_TAIL_SIZE, effect);
}

/// `iplAmbisonicsDecodeEffectGetTail`.
/// Complexity: O(samples).
pub fn phonon_ambisonics_decode_get_tail(lib: &PhononLibrary, effect: Int,
    out_buf: &mut PhononAudioBuffer) -> PhononEffectOutcome
  requires: effect != 0
  requires: out_buf.num_channels >= 1
{
  return get_tail_effect(lib, exports.PHONON_IDX_IPL_AMBISONICS_DECODE_EFFECT_GET_TAIL,
    effect, out_buf);
}

// =========================================================================
// Direct effect
// =========================================================================

/// `iplDirectEffectCreate`.
/// Complexity: O(1).
pub fn phonon_direct_create(lib: &PhononLibrary, context: Int, sampling_rate: Int,
    frame_size: Int, num_channels: Int) -> PhononHandleOutcome
  requires: context != 0
  requires: sampling_rate > 0
  requires: frame_size > 0
  requires: num_channels > 0
{
  var aset = audio_settings_slot(sampling_rate, frame_size);
  var eset = phonon_slot(abi.IPL_DIRECT_EFFECT_SETTINGS_SIZE);
  s_w32(&mut eset, abi.IPL_DIRECT_EFFECT_SETTINGS_NUM_CHANNELS, num_channels);
  return create_effect(lib, exports.PHONON_IDX_IPL_DIRECT_EFFECT_CREATE, context, &aset, &mut eset);
}

/// `iplDirectEffectApply` (in/out `num_channels` channels).
/// Complexity: O(samples).
pub fn phonon_direct_apply(lib: &PhononLibrary, effect: Int, in_buf: &PhononAudioBuffer,
    out_buf: &mut PhononAudioBuffer, flags: Int, transmission_type: Int,
    distance_attenuation: Float64, air_absorption: &PhononVector3, directivity: Float64,
    occlusion: Float64, transmission: &PhononVector3) -> PhononEffectOutcome
  requires: effect != 0
  requires: in_buf.num_channels >= 1
  requires: out_buf.num_channels >= 1
{
  var params = phonon_slot(abi.IPL_DIRECT_EFFECT_PARAMS_SIZE);
  s_w32(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_FLAGS, flags);
  s_w32(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_TRANSMISSION_TYPE, transmission_type);
  s_wf32(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_DISTANCE_ATTENUATION, distance_attenuation);
  write_vec3(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_AIR_ABSORPTION, air_absorption);
  s_wf32(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_DIRECTIVITY, directivity);
  s_wf32(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_OCCLUSION, occlusion);
  write_vec3(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_TRANSMISSION, transmission);
  return apply_effect(lib, exports.PHONON_IDX_IPL_DIRECT_EFFECT_APPLY, effect, &mut params,
    in_buf, out_buf);
}

/// `iplDirectEffectApply` in place (the direct effect supports in-place
/// application).
/// Complexity: O(samples).
pub fn phonon_direct_apply_inplace(lib: &PhononLibrary, effect: Int,
    buf: &mut PhononAudioBuffer, flags: Int, transmission_type: Int,
    distance_attenuation: Float64, air_absorption: &PhononVector3, directivity: Float64,
    occlusion: Float64, transmission: &PhononVector3) -> PhononEffectOutcome
  requires: effect != 0
  requires: buf.num_channels >= 1
{
  var params = phonon_slot(abi.IPL_DIRECT_EFFECT_PARAMS_SIZE);
  s_w32(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_FLAGS, flags);
  s_w32(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_TRANSMISSION_TYPE, transmission_type);
  s_wf32(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_DISTANCE_ATTENUATION, distance_attenuation);
  write_vec3(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_AIR_ABSORPTION, air_absorption);
  s_wf32(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_DIRECTIVITY, directivity);
  s_wf32(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_OCCLUSION, occlusion);
  write_vec3(&mut params, abi.IPL_DIRECT_EFFECT_PARAMS_TRANSMISSION, transmission);
  return apply_effect_inplace(lib, exports.PHONON_IDX_IPL_DIRECT_EFFECT_APPLY, effect,
    &mut params, buf);
}

/// `iplDirectEffectReset`.
/// Complexity: O(1).
pub fn phonon_direct_reset(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return reset_effect(lib, exports.PHONON_IDX_IPL_DIRECT_EFFECT_RESET, effect);
}

/// `iplDirectEffectRetain`.
/// Complexity: O(1).
pub fn phonon_direct_retain(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return retain_effect(lib, exports.PHONON_IDX_IPL_DIRECT_EFFECT_RETAIN, effect);
}

/// `iplDirectEffectRelease`.
/// Complexity: O(1).
pub fn phonon_direct_release(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return release_effect(lib, exports.PHONON_IDX_IPL_DIRECT_EFFECT_RELEASE, effect);
}

/// `iplDirectEffectGetTailSize`.
/// Complexity: O(1).
pub fn phonon_direct_tail_size(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return tail_size_effect(lib, exports.PHONON_IDX_IPL_DIRECT_EFFECT_GET_TAIL_SIZE, effect);
}

/// `iplDirectEffectGetTail`.
/// Complexity: O(samples).
pub fn phonon_direct_get_tail(lib: &PhononLibrary, effect: Int,
    out_buf: &mut PhononAudioBuffer) -> PhononEffectOutcome
  requires: effect != 0
  requires: out_buf.num_channels >= 1
{
  return get_tail_effect(lib, exports.PHONON_IDX_IPL_DIRECT_EFFECT_GET_TAIL, effect, out_buf);
}

// =========================================================================
// Path effect
// =========================================================================

/// `iplPathEffectCreate`.
/// Complexity: O(1).
pub fn phonon_path_create(lib: &PhononLibrary, context: Int, sampling_rate: Int,
    frame_size: Int, max_order: Int, spatialize: Bool, layout_type: Int, hrtf: Int)
    -> PhononHandleOutcome
  requires: context != 0
  requires: sampling_rate > 0
  requires: frame_size > 0
  requires: max_order >= 1
  requires: hrtf != 0
{
  var aset = audio_settings_slot(sampling_rate, frame_size);
  var eset = phonon_slot(abi.IPL_PATH_EFFECT_SETTINGS_SIZE);
  s_w32(&mut eset, abi.IPL_PATH_EFFECT_SETTINGS_MAX_ORDER, max_order);
  var sp = 0;
  if spatialize { sp = 1; }
  s_w32(&mut eset, abi.IPL_PATH_EFFECT_SETTINGS_SPATIALIZE, sp);
  set_speaker_layout(&mut eset, abi.IPL_PATH_EFFECT_SETTINGS_SPEAKER_LAYOUT, layout_type);
  s_w64(&mut eset, abi.IPL_PATH_EFFECT_SETTINGS_HRTF, hrtf);
  return create_effect(lib, exports.PHONON_IDX_IPL_PATH_EFFECT_CREATE, context, &aset, &mut eset);
}

/// `iplPathEffectApply`.  `sh_coeffs` is an XIOM-owned Float32 vector of
/// `(order+1)^2` ambisonic coefficients; its address is written byte-wise
/// into the params slot (the DLL reads XIOM-owned memory only).
/// Complexity: O(samples).
pub fn phonon_path_apply(lib: &PhononLibrary, effect: Int, in_buf: &PhononAudioBuffer,
    out_buf: &mut PhononAudioBuffer, sh_coeffs: &Vec[Float32], eq_coeffs: &PhononVector3,
    order: Int, binaural: Bool, hrtf: Int, listener: &PhononOrientation, normalize_eq: Bool)
    -> PhononEffectOutcome
  requires: effect != 0
  requires: in_buf.num_channels >= 1
  requires: out_buf.num_channels >= 1
  requires: sh_coeffs.len() >= 4
  requires: hrtf != 0
  requires: order >= 1
{
  var p_sh = 0;
  unsafe {
    p_sh = sh_coeffs.as_mut_ptr() as Int;
  }
  var params = phonon_slot(abi.IPL_PATH_EFFECT_PARAMS_SIZE);
  write_vec3(&mut params, abi.IPL_PATH_EFFECT_PARAMS_EQ_COEFFS, eq_coeffs);
  s_w64(&mut params, abi.IPL_PATH_EFFECT_PARAMS_SH_COEFFS, p_sh);
  s_w32(&mut params, abi.IPL_PATH_EFFECT_PARAMS_ORDER, order);
  var bin = 0;
  if binaural { bin = 1; }
  s_w32(&mut params, abi.IPL_PATH_EFFECT_PARAMS_BINAURAL, bin);
  s_w64(&mut params, abi.IPL_PATH_EFFECT_PARAMS_HRTF, hrtf);
  write_orientation(&mut params, abi.IPL_PATH_EFFECT_PARAMS_LISTENER, listener);
  var neq = 0;
  if normalize_eq { neq = 1; }
  s_w32(&mut params, abi.IPL_PATH_EFFECT_PARAMS_NORMALIZE_EQ, neq);
  return apply_effect(lib, exports.PHONON_IDX_IPL_PATH_EFFECT_APPLY, effect, &mut params,
    in_buf, out_buf);
}

/// `iplPathEffectReset`.
/// Complexity: O(1).
pub fn phonon_path_reset(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return reset_effect(lib, exports.PHONON_IDX_IPL_PATH_EFFECT_RESET, effect);
}

/// `iplPathEffectRetain`.
/// Complexity: O(1).
pub fn phonon_path_retain(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return retain_effect(lib, exports.PHONON_IDX_IPL_PATH_EFFECT_RETAIN, effect);
}

/// `iplPathEffectRelease`.
/// Complexity: O(1).
pub fn phonon_path_release(lib: &PhononLibrary, effect: Int) -> PhononStatusOutcome
  requires: effect != 0
{
  return release_effect(lib, exports.PHONON_IDX_IPL_PATH_EFFECT_RELEASE, effect);
}

/// `iplPathEffectGetTailSize`.
/// Complexity: O(1).
pub fn phonon_path_tail_size(lib: &PhononLibrary, effect: Int) -> Int
  requires: effect != 0
{
  return tail_size_effect(lib, exports.PHONON_IDX_IPL_PATH_EFFECT_GET_TAIL_SIZE, effect);
}

/// `iplPathEffectGetTail`.
/// Complexity: O(samples).
pub fn phonon_path_get_tail(lib: &PhononLibrary, effect: Int,
    out_buf: &mut PhononAudioBuffer) -> PhononEffectOutcome
  requires: effect != 0
  requires: out_buf.num_channels >= 1
{
  return get_tail_effect(lib, exports.PHONON_IDX_IPL_PATH_EFFECT_GET_TAIL, effect, out_buf);
}
