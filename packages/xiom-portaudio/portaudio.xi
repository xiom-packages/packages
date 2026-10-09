// XIOM -- xiom.portaudio: PortAudio bindings via dynamic loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader path (same pattern as xiom.miniaudio / xiom.odbc).
// The package does NOT link PortAudio at build time and needs no headers:
// constants are declared locally, `pa_load` resolves `portaudio_x64.dll`
// through `xiom.ffi.dl`, and every call is an fn-pointer cast inside this
// single module -- the ONLY module in the package with `unsafe` (G5).
//
// Classification:
//   PA_LOAD_ABSENT    -> library missing -> SKIP (CI stays green)
//   PA_LOAD_ABI       -> entry points missing -> FAIL
//   PA_PROBE_FAILED   -> Pa_Initialize failed (no audio service) -> SKIP-class
//
// Coverage (pilot): version (int + text), initialize/terminate, device count,
// and default output/input device names (read from PaDeviceInfo at offset 8
// -- structVersion(4) + padding, then char* name).  Streams, formats and the
// callback API are Phase 2 (ROADMAP.md).
//
// G2 pin (SPEC.md): soname `portaudio_x64.dll` + entry-point set + local
// samples (Audacity / DaVinci Resolve builds) + upstream PortAudio v19.7.0.

module xiom.portaudio

use xiom.ffi;
use xiom.ffi.dl;

// =========================================================================
// Identity and constants (PortAudio; declared locally)
// =========================================================================

pub const PORT_AUDIO_SONAME: Str = "portaudio_x64.dll";

// Sample formats (PaSampleFormat).
pub const FORMAT_FLOAT32: Int = 0x00000001;
pub const FORMAT_INT32: Int = 0x00000002;
pub const FORMAT_INT24: Int = 0x00000004;
pub const FORMAT_INT16: Int = 0x00000008;
pub const FORMAT_INT8: Int = 0x00000010;
pub const FORMAT_UINT8: Int = 0x00000020;
pub const FORMAT_CUSTOM: Int = 0x00010000;

pub const PA_LOAD_ABSENT: Int = 0;  // library missing -> SKIP
pub const PA_LOAD_ABI: Int = 1;     // entry points missing -> FAIL
pub const PA_PROBE_FAILED: Int = 2; // initialize failed -> SKIP-class

pub type PaLoadError = {
  kind: Int;
  message: Str;
}

pub type PaInfo = {
  version: Int;
  version_text: Str;
  device_count: Int;
  default_output: Int;
  default_output_name: Str;
  default_input: Int;
  default_input_name: Str;
}

/// A loaded PortAudio.  Owned by the caller; release with `pa_close`.
pub type PaLibrary = {
  handle: Int;
  p_get_version: Int;
  p_get_version_text: Int;
  p_initialize: Int;
  p_terminate: Int;
  p_get_device_count: Int;
  p_get_default_output: Int;
  p_get_default_input: Int;
  p_get_device_info: Int;
}

// =========================================================================
// Loader
// =========================================================================

/// Load an explicitly named PortAudio build (bogus names exercise the
/// ABSENT/SKIP classification deterministically on any host).
/// Complexity: O(symbols).
pub fn pa_load_named(soname: Str) -> Result[PaLibrary, PaLoadError]
  requires: soname.len() > 0
{
  let h = dl.dl_open(soname);
  if !h.is_ok {
    return Err(PaLoadError{ kind: PA_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;

  let a1 = dl.dl_sym(handle, "Pa_GetVersion");
  if !a1.is_ok { var ig = dl.dl_close(handle); return Err(PaLoadError{ kind: PA_LOAD_ABI; message: "Pa_GetVersion: " + a1.error }); }
  let a2 = dl.dl_sym(handle, "Pa_GetVersionText");
  if !a2.is_ok { var ig = dl.dl_close(handle); return Err(PaLoadError{ kind: PA_LOAD_ABI; message: "Pa_GetVersionText: " + a2.error }); }
  let a3 = dl.dl_sym(handle, "Pa_Initialize");
  if !a3.is_ok { var ig = dl.dl_close(handle); return Err(PaLoadError{ kind: PA_LOAD_ABI; message: "Pa_Initialize: " + a3.error }); }
  let a4 = dl.dl_sym(handle, "Pa_Terminate");
  if !a4.is_ok { var ig = dl.dl_close(handle); return Err(PaLoadError{ kind: PA_LOAD_ABI; message: "Pa_Terminate: " + a4.error }); }
  let a5 = dl.dl_sym(handle, "Pa_GetDeviceCount");
  if !a5.is_ok { var ig = dl.dl_close(handle); return Err(PaLoadError{ kind: PA_LOAD_ABI; message: "Pa_GetDeviceCount: " + a5.error }); }
  let a6 = dl.dl_sym(handle, "Pa_GetDefaultOutputDevice");
  if !a6.is_ok { var ig = dl.dl_close(handle); return Err(PaLoadError{ kind: PA_LOAD_ABI; message: "Pa_GetDefaultOutputDevice: " + a6.error }); }
  let a7 = dl.dl_sym(handle, "Pa_GetDefaultInputDevice");
  if !a7.is_ok { var ig = dl.dl_close(handle); return Err(PaLoadError{ kind: PA_LOAD_ABI; message: "Pa_GetDefaultInputDevice: " + a7.error }); }
  let a8 = dl.dl_sym(handle, "Pa_GetDeviceInfo");
  if !a8.is_ok { var ig = dl.dl_close(handle); return Err(PaLoadError{ kind: PA_LOAD_ABI; message: "Pa_GetDeviceInfo: " + a8.error }); }

  return Ok(PaLibrary{
    handle: handle,
    p_get_version: a1.value,
    p_get_version_text: a2.value,
    p_initialize: a3.value,
    p_terminate: a4.value,
    p_get_device_count: a5.value,
    p_get_default_output: a6.value,
    p_get_default_input: a7.value,
    p_get_device_info: a8.value,
  });
}

/// Load the default PortAudio build (`portaudio_x64.dll`).
/// Complexity: O(symbols).
pub fn pa_load() -> Result[PaLibrary, PaLoadError]
  requires: true
{
  return pa_load_named(PORT_AUDIO_SONAME);
}

/// Release the library handle.
/// Complexity: O(1).
pub fn pa_close(lib: &PaLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

// =========================================================================
// Probe
// =========================================================================

/// Initialize PortAudio, report version/devices/defaults, then terminate.
/// Err("portaudio: Pa_Initialize rc=N") on initialize failure (callers treat
/// that as SKIP-class -- a serviceless host).
/// Complexity: O(backends + devices).
pub fn pa_probe(lib: &PaLibrary) -> Result[PaInfo, Str]
  requires: lib.handle != 0
{
  unsafe {
    let f_version = lib.p_get_version as fn() -> Int32;
    let f_text = lib.p_get_version_text as fn() -> *UInt8;
    let f_init = lib.p_initialize as fn() -> Int32;
    let f_term = lib.p_terminate as fn() -> Int32;
    let f_count = lib.p_get_device_count as fn() -> Int32;
    let f_def_out = lib.p_get_default_output as fn() -> Int32;
    let f_def_in = lib.p_get_default_input as fn() -> Int32;
    let f_dev_info = lib.p_get_device_info as fn(Int) -> Int;

    let version = f_version() as Int;

    var version_text = "";
    let tp = f_text();
    if (tp as Int) != 0 {
      version_text = Str::from_c_str(tp);
    }

    let rc = f_init() as Int;
    if rc != 0 {
      return Err("portaudio: Pa_Initialize rc=" + int_to_str(rc));
    }

    let count = f_count() as Int;
    let def_out = f_def_out() as Int;
    let def_in = f_def_in() as Int;

    var out_name = "";
    if def_out >= 0 {
      let info = f_dev_info(def_out);
      if info != 0 {
        let namep = ffi.ptr_read_u64_le((info + 8) as *UInt8);
        if namep != 0 {
          out_name = Str::from_c_str(namep as *UInt8);
        }
      }
    }

    var in_name = "";
    if def_in >= 0 {
      let info = f_dev_info(def_in);
      if info != 0 {
        let namep = ffi.ptr_read_u64_le((info + 8) as *UInt8);
        if namep != 0 {
          in_name = Str::from_c_str(namep as *UInt8);
        }
      }
    }

    var ig = f_term();

    return Ok(PaInfo{
      version: version,
      version_text: version_text,
      device_count: count,
      default_output: def_out,
      default_output_name: out_name,
      default_input: def_in,
      default_input_name: in_name,
    });
  }
}

/// Load an explicitly named build and run `pa_probe`.
/// Complexity: O(backends + devices).
pub fn pa_probe_named(soname: Str) -> Result[PaInfo, PaLoadError]
  requires: soname.len() > 0
{
  let l = pa_load_named(soname);
  if !l.is_ok {
    return Err(l.error);
  }
  let lib: PaLibrary = l.value;
  let p = pa_probe(&lib);
  let cl = pa_close(&lib);
  if !p.is_ok {
    return Err(PaLoadError{ kind: PA_PROBE_FAILED; message: p.error });
  }
  if !cl.is_ok {
    return Err(PaLoadError{ kind: PA_PROBE_FAILED; message: cl.error });
  }
  return Ok(p.value);
}

/// Probe the default build (`portaudio_x64.dll`).
/// Complexity: O(backends + devices).
pub fn pa_probe_default() -> Result[PaInfo, PaLoadError]
  requires: true
{
  return pa_probe_named(PORT_AUDIO_SONAME);
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
