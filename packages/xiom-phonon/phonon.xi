// XIOM -- xiom.phonon: Steam Audio (Phonon) bindings via dynamic loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader path (same pattern as xiom.odbc / xiom.portaudio).
// Steam Audio (Valve) exposes a C API; the package resolves `phonon.dll` at
// runtime through `xiom.ffi.dl` and needs no headers: constants and the
// IPLContextSettings layout are declared locally (verified against the
// pinned SDK headers).  All XIOM `unsafe`/`extern` live in this single
// module (G5).
//
// Classification:
//   PHONON_LOAD_ABSENT  -> phonon.dll missing -> SKIP (CI stays green)
//   PHONON_LOAD_ABI     -> entry points missing -> FAIL
//   PHONON_PROBE_FAILED -> context creation failed -> FAIL
//
// Coverage (pilot): SDK version pin, context lifecycle (create/retain/
// release).  HRTF creation, effects (binaural/ambisonics/direct), scenes and
// the rest of the ~125-function surface are Phase 2 (ROADMAP.md).
//
// G2 pin (SPEC.md): soname `phonon.dll` + upstream tag v4.8.1 + entry-point
// set + IPLContextSettings layout + local header hashes + local DLL sample.

module xiom.phonon

use xiom.ffi.dl;

// =========================================================================
// Identity, version and ABI constants (Steam Audio; declared locally)
// =========================================================================

pub const PHONON_SONAME: Str = "phonon.dll";

pub const STEAMAUDIO_VERSION_MAJOR: Int = 4;
pub const STEAMAUDIO_VERSION_MINOR: Int = 8;
pub const STEAMAUDIO_VERSION_PATCH: Int = 1;

/// STEAMAUDIO_VERSION = (major << 16) | (minor << 8) | patch = 0x040801.
pub const STEAMAUDIO_VERSION: Int = 0x040801;

pub const IPL_NUM_BANDS: Int = 3;

// IPLerror values.
pub const IPL_STATUS_SUCCESS: Int = 0;
pub const IPL_STATUS_FAILURE: Int = 1;
pub const IPL_STATUS_OUTOFMEMORY: Int = 2;
pub const IPL_STATUS_INITIALIZATION: Int = 3;

// IPLSIMDLevel values.
pub const IPL_SIMDLEVEL_SSE2: Int = 0;
pub const IPL_SIMDLEVEL_SSE4: Int = 1;
pub const IPL_SIMDLEVEL_AVX: Int = 2;
pub const IPL_SIMDLEVEL_AVX2: Int = 3;
pub const IPL_SIMDLEVEL_AVX512: Int = 4;

// IPLContextFlags values.
pub const IPL_CONTEXTFLAGS_VALIDATION: Int = 1;

pub const PHONON_LOAD_ABSENT: Int = 0;  // phonon.dll missing -> SKIP
pub const PHONON_LOAD_ABI: Int = 1;     // entry points missing -> FAIL
pub const PHONON_PROBE_FAILED: Int = 2; // context creation failed -> FAIL

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
pub type PhononLibrary = {
  handle: Int;
  p_context_create: Int;
  p_context_retain: Int;
  p_context_release: Int;
}

// =========================================================================
// Slot helpers (XIOM-owned out-params; no malloc/free in confined blocks)
// =========================================================================

fn slot_new(n: Int) -> Vec[UInt8]
  requires: n > 0
  requires: n <= 256
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn write_u32(buf: &mut Vec[UInt8], idx: Int, v: Int)
  requires: idx >= 0
  requires: idx + 3 < buf.len()
  requires: v >= 0
{
  buf[idx] = (v & 0xFF) as UInt8;
  buf[idx + 1] = ((v >> 8) & 0xFF) as UInt8;
  buf[idx + 2] = ((v >> 16) & 0xFF) as UInt8;
  buf[idx + 3] = ((v >> 24) & 0xFF) as UInt8;
}

fn read_u64_le(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 8
{
  let b0 = buf[0] as Int;
  let b1 = buf[1] as Int;
  let b2 = buf[2] as Int;
  let b3 = buf[3] as Int;
  let b4 = buf[4] as Int;
  let b5 = buf[5] as Int;
  let b6 = buf[6] as Int;
  let b7 = buf[7] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
       | (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56);
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

  let a1 = dl.dl_sym(handle, "iplContextCreate");
  if !a1.is_ok { var ig = dl.dl_close(handle); return Err(PhononLoadError{ kind: PHONON_LOAD_ABI; message: "iplContextCreate: " + a1.error }); }
  let a2 = dl.dl_sym(handle, "iplContextRetain");
  if !a2.is_ok { var ig = dl.dl_close(handle); return Err(PhononLoadError{ kind: PHONON_LOAD_ABI; message: "iplContextRetain: " + a2.error }); }
  let a3 = dl.dl_sym(handle, "iplContextRelease");
  if !a3.is_ok { var ig = dl.dl_close(handle); return Err(PhononLoadError{ kind: PHONON_LOAD_ABI; message: "iplContextRelease: " + a3.error }); }

  return Ok(PhononLibrary{
    handle: handle,
    p_context_create: a1.value,
    p_context_retain: a2.value,
    p_context_release: a3.value,
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

// =========================================================================
// Probe
// =========================================================================

/// Create a Steam Audio context and exercise the retain/release balance.
/// `IPLContextSettings` is a 40-byte struct: version (u32 at 0), three
/// optional callbacks (NULL), simdLevel (u32 at 32), flags (u32 at 36).
/// Complexity: O(1).
pub fn phonon_probe(lib: &PhononLibrary) -> Result[PhononInfo, Str]
  requires: lib.handle != 0
{
  unsafe {
    let f_create = lib.p_context_create as fn(*UInt8, *UInt8) -> Int32;
    let f_retain = lib.p_context_retain as fn(Int) -> Int;
    let f_release = lib.p_context_release as fn(*UInt8);

    var settings = slot_new(40);
    write_u32(&mut settings, 0, STEAMAUDIO_VERSION);       // version 0x040801
    write_u32(&mut settings, 32, IPL_SIMDLEVEL_SSE2);      // baseline SIMD
    write_u32(&mut settings, 36, 0);                       // no flags

    var out = slot_new(8);
    let rc = f_create(settings.as_mut_ptr(), out.as_mut_ptr()) as Int;
    if rc != IPL_STATUS_SUCCESS {
      return Err("phonon: iplContextCreate rc=" + int_to_str(rc));
    }
    let ctx = read_u64_le(&out);
    if ctx == 0 {
      return Err("phonon: iplContextCreate returned a null context");
    }

    let retained = f_retain(ctx);
    if retained != ctx {
      return Err("phonon: iplContextRetain returned a different handle");
    }

    /* Release both references (create + retain); release takes IPLContext*. */
    var r1 = slot_new(8);
    write_u32(&mut r1, 0, ctx & 0xFFFFFFFF);
    write_u32(&mut r1, 4, (ctx >> 32) & 0xFFFFFFFF);
    var r2 = slot_new(8);
    write_u32(&mut r2, 0, retained & 0xFFFFFFFF);
    write_u32(&mut r2, 4, (retained >> 32) & 0xFFFFFFFF);
    f_release(r1.as_mut_ptr());
    f_release(r2.as_mut_ptr());

    return Ok(PhononInfo{
      version: STEAMAUDIO_VERSION,
      simd_level: IPL_SIMDLEVEL_SSE2,
      context_handle: ctx,
    });
  }
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

// Local integer-to-string (stdlib convert must not be called inside the
// confined block; same rule as the other binding modules).
fn int_to_str(n: Int) -> Str {
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
