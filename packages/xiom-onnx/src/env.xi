// XIOM -- xiom.onnx.env: OrtEnv lifecycle, telemetry and provider enumeration.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Oracle: microsoft/onnxruntime v1.31.0 (pinned) -- OrtApi members
// CreateEnv(3), ReleaseEnv(92), EnableTelemetryEvents(5),
// DisableTelemetryEvents(6), GetAvailableProviders(125),
// ReleaseAvailableProviders(126); OrtApiBase GetVersionString(1).

module xiom.onnx.env

use xiom.onnx.types;
use xiom.onnx.loader;
use xiom.ffi;
use xiom.ffi.dl;

/// Create the ORT environment (log severity ORT_LOGGING_LEVEL_WARNING).
/// ORT returns the same underlying env for repeated calls; release with
/// `onnx_env_free` once per successful create.
/// Complexity: O(len).
pub fn onnx_env_new(lib: &OnnxLibrary, logid: Str) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: logid.len() > 0
{
  return onnx_env_new_level(lib, types.ORT_LOGGING_LEVEL_WARNING, logid);
}

/// Create the ORT environment at an explicit logging severity.
/// Complexity: O(len).
pub fn onnx_env_new_level(lib: &OnnxLibrary, level: Int, logid: Str) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: logid.len() > 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_CreateEnv) as fn(Int32, *UInt8, *UInt8) -> Int;
    let st = f(level as Int32, logid.c_str(), slot.as_mut_ptr());
    let c = ort_check(lib, st, "CreateEnv");
    if !c.is_ok { return Err(c.error); }
    let env = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if env == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "CreateEnv returned null env" });
    }
    return Ok(env);
  }
}

/// Release the environment handle.
/// Complexity: O(1).
pub fn onnx_env_free(lib: &OnnxLibrary, env: Int)
  requires: lib.api != 0
{
  if env == 0 { return; }
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ReleaseEnv) as fn(Int) -> Unit;
    f(env);
  }
}

/// Enable or disable telemetry for the environment (both directions; ORT is
/// on by default, so the suite exercises enable -> disable).
/// Complexity: O(1).
pub fn onnx_telemetry_set(lib: &OnnxLibrary, env: Int, enabled: Bool) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: env != 0
{
  var idx = ORT_API_DisableTelemetryEvents;
  if enabled { idx = ORT_API_EnableTelemetryEvents; }
  unsafe {
    let f = ort_api_slot(lib.api, idx) as fn(Int) -> Int;
    let st = f(env);
    return ort_check(lib, st, "telemetry_set");
  }
}

/// The runtime version string (from OrtApiBase.GetVersionString at load).
/// Complexity: O(1).
pub fn onnx_version(lib: &OnnxLibrary) -> Str
  requires: lib.api != 0
{
  return lib.version;
}

/// The execution providers compiled into the loaded runtime, in ORT order
/// (e.g. ["CPUExecutionProvider"]).
/// Complexity: O(providers * len).
pub fn onnx_available_providers(lib: &OnnxLibrary) -> Result[OnnxStrList, OnnxError]
  requires: lib.api != 0
{
  var prov_slot = Vec[UInt8].with_len(8);
  var count_slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetAvailableProviders) as fn(*UInt8, *UInt8) -> Int;
    let st = f(prov_slot.as_mut_ptr(), count_slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetAvailableProviders");
    if !c.is_ok { return Err(c.error); }
    let nprov = ffi.ptr_read_u64_le(count_slot.as_mut_ptr());
    let provs = ffi.ptr_read_u64_le(prov_slot.as_mut_ptr());
    var out: Vec[Str] = Vec[Str].new();
    var i = 0;
    while i < nprov {
      let pp = ffi.ptr_read_u64_le((provs + i * 8) as *UInt8);
      if pp != 0 {
        out.push(own_c_str(pp));
      } else {
        out.push("");
      }
      i = i + 1;
    };
    let rp = ort_api_slot(lib.api, ORT_API_ReleaseAvailableProviders) as fn(Int, Int32) -> Int;
    let _ = rp(provs, nprov as Int32);
    return Ok(OnnxStrList{ items: out });
  }
}
