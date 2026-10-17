// XIOM -- xiom.onnx.session: sessions, session options, run options, model
// metadata, Run and IoBinding -- plus the high-level model API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Oracle: microsoft/onnxruntime v1.31.0 (pinned) -- OrtApi members
// CreateSession(7), CreateSessionFromArray(8), Run(9),
// CreateSessionOptions(10), SetSessionExecutionMode(13),
// Enable/DisableProfiling(14/15), Enable/DisableMemPattern(16/17),
// Enable/DisableCpuMemArena(18/19), SetSessionLogId(20),
// SetSessionLog{V,Se}verityLevel(21/22), SetSessionGraphOptimizationLevel(23),
// SetIntra/InterOpNumThreads(24/25), SessionGet*Count(30/31),
// SessionGet*TypeInfo(33/34), SessionGet*Name(36/37), ReleaseSession(95),
// ReleaseSessionOptions(100), SessionGetModelMetadata(111) + metadata
// getters (112/113/114/117/118), AddSessionConfigEntry(130),
// SessionOptionsAppendExecutionProvider(216), RunOptions (39..45, 97),
// IoBinding (133..142, 202/203).
//
// ORTCHAR_T is wchar_t on the pinned Windows build: file-path / profiling-
// prefix arguments cross as UTF-16LE (ASCII paths; see `to_wide`).
// Run/IO-binding name arrays are marshalled through XIOM-owned contiguous
// blobs (`str_array`) -- no C-string lifetime escapes.

module xiom.onnx.session

use xiom.onnx.types;
use xiom.onnx.loader;
use xiom.onnx.value;
use xiom.ffi;

// =========================================================================
// Local helpers
// =========================================================================

/// UTF-16LE (wchar_t) form of an ASCII path/prefix, NUL-terminated. The
/// pinned Windows build defines ORTCHAR_T as wchar_t; byte values above
/// 0x7F are out of scope (documented limitation).
/// Complexity: O(len).
fn to_wide(s: Str) -> Vec[UInt8]
  requires: s.len() > 0
{
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    out.push(0);
    i = i + 1;
  };
  out.push(0);
  out.push(0);
  return out;
}

/// A packed NUL-terminated string array: the byte blob plus the pointer
/// table into it (kept together so both stay alive across the call).
pub type StrArray = {
  blob: Vec[UInt8];
  ptrs: Vec[Int];
}

/// Pack N strings as NUL-terminated bytes in one blob + a pointer table.
/// Complexity: O(total bytes).
fn str_array(names: &Vec[Str]) -> StrArray
  requires: names.len() > 0
{
  var total = 1;
  var i = 0;
  while i < names.len() {
    total = total + names[i].len() + 1;
    i = i + 1;
  };
  var blob = Vec[UInt8].with_len(total);
  var offsets: Vec[Int] = Vec[Int].new();
  var pos = 0;
  i = 0;
  while i < names.len() {
    offsets.push(pos);
    var j = 0;
    while j < names[i].len() {
      blob[pos + j] = names[i].byte_at(j);
      j = j + 1;
    };
    blob[pos + names[i].len()] = 0;
    pos = pos + names[i].len() + 1;
    i = i + 1;
  };
  let base = unsafe { blob.as_mut_ptr() as Int };
  var ptrs: Vec[Int] = Vec[Int].new();
  i = 0;
  while i < offsets.len() {
    ptrs.push(base + offsets[i]);
    i = i + 1;
  };
  return StrArray{ blob: blob; ptrs: ptrs; };
}

/// Read `len` raw bytes at `p` as a Str (UTF-8; "" for len 0 / null).
/// Complexity: O(len).
fn read_bytes(p: Int, len: Int) -> Str
  requires: len >= 0
{
  if len == 0 { return ""; }
  if p == 0 { return ""; }
  var bytes: Vec[UInt8] = Vec[UInt8].new();
  unsafe {
    let sp = ffi.safe_ptr_from_raw(p as *UInt8, len);
    if !sp.is_ok { return ""; }
    let safe: SafePtr = sp.value;
    var i = 0;
    while i < len {
      let r = ffi.safe_ptr_read_byte(&safe, i);
      if r.is_ok {
        bytes.push((r.value % 256) as UInt8);
      } else {
        bytes.push(0);
      }
      i = i + 1;
    };
    ffi.safe_ptr_free(safe);
  }
  return Str::from_utf8(bytes);
}

/// One u64 read from a slot buffer.
/// Complexity: O(1).
fn slot_read(slot: &Vec[UInt8]) -> Int
  requires: slot.len() >= 8
{
  unsafe {
    return ffi.ptr_read_u64_le(slot.as_mut_ptr());
  }
}

// =========================================================================
// Session options
// =========================================================================

/// Create OrtSessionOptions. Free with `onnx_session_options_free`.
/// Complexity: O(1).
pub fn onnx_session_options_new(lib: &OnnxLibrary) -> Result[Int, OnnxError]
  requires: lib.api != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_CreateSessionOptions) as fn(*UInt8) -> Int;
    let st = f(slot.as_mut_ptr());
    let c = ort_check(lib, st, "CreateSessionOptions");
    if !c.is_ok { return Err(c.error); }
    let opts = slot_read(&slot);
    if opts == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "CreateSessionOptions returned null" });
    }
    return Ok(opts);
  }
}

/// Release OrtSessionOptions.
/// Complexity: O(1).
pub fn onnx_session_options_free(lib: &OnnxLibrary, opts: Int)
  requires: lib.api != 0
{
  if opts == 0 { return; }
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ReleaseSessionOptions) as fn(Int) -> Unit;
    f(opts);
  }
}

/// Intra-op thread count (0 = ORT default).
/// Complexity: O(1).
pub fn onnx_options_set_intra_threads(lib: &OnnxLibrary, opts: Int, n: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_SetIntraOpNumThreads) as fn(Int, Int32) -> Int;
    let st = f(opts, n as Int32);
    return ort_check(lib, st, "SetIntraOpNumThreads");
  }
}

/// Inter-op thread count (0 = ORT default).
/// Complexity: O(1).
pub fn onnx_options_set_inter_threads(lib: &OnnxLibrary, opts: Int, n: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_SetInterOpNumThreads) as fn(Int, Int32) -> Int;
    let st = f(opts, n as Int32);
    return ort_check(lib, st, "SetInterOpNumThreads");
  }
}

/// Graph optimization level (ORT_GRAPH_OPT_*).
/// Complexity: O(1).
pub fn onnx_options_set_graph_opt(lib: &OnnxLibrary, opts: Int, level: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_SetSessionGraphOptimizationLevel) as fn(Int, Int32) -> Int;
    let st = f(opts, level as Int32);
    return ort_check(lib, st, "SetSessionGraphOptimizationLevel");
  }
}

/// Execution mode (ORT_EXECUTION_MODE_SEQUENTIAL / _PARALLEL).
/// Complexity: O(1).
pub fn onnx_options_set_execution_mode(lib: &OnnxLibrary, opts: Int, mode: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_SetSessionExecutionMode) as fn(Int, Int32) -> Int;
    let st = f(opts, mode as Int32);
    return ort_check(lib, st, "SetSessionExecutionMode");
  }
}

/// Session log id.
/// Complexity: O(len).
pub fn onnx_options_set_log_id(lib: &OnnxLibrary, opts: Int, logid: Str) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
  requires: logid.len() > 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_SetSessionLogId) as fn(Int, *UInt8) -> Int;
    let st = f(opts, logid.c_str());
    return ort_check(lib, st, "SetSessionLogId");
  }
}

/// Session log verbosity level.
/// Complexity: O(1).
pub fn onnx_options_set_log_verbosity(lib: &OnnxLibrary, opts: Int, level: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_SetSessionLogVerbosityLevel) as fn(Int, Int32) -> Int;
    let st = f(opts, level as Int32);
    return ort_check(lib, st, "SetSessionLogVerbosityLevel");
  }
}

/// Session log severity level (ORT_LOGGING_LEVEL_*).
/// Complexity: O(1).
pub fn onnx_options_set_log_severity(lib: &OnnxLibrary, opts: Int, level: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_SetSessionLogSeverityLevel) as fn(Int, Int32) -> Int;
    let st = f(opts, level as Int32);
    return ort_check(lib, st, "SetSessionLogSeverityLevel");
  }
}

/// Enable profiling into files prefixed with `prefix` (UTF-16 path).
/// Complexity: O(len).
pub fn onnx_options_enable_profiling(lib: &OnnxLibrary, opts: Int, prefix: Str) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
  requires: prefix.len() > 0
{
  var wide = to_wide(prefix);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_EnableProfiling) as fn(Int, *UInt8) -> Int;
    let st = f(opts, wide.as_mut_ptr());
    return ort_check(lib, st, "EnableProfiling");
  }
}

/// Disable profiling.
/// Complexity: O(1).
pub fn onnx_options_disable_profiling(lib: &OnnxLibrary, opts: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_DisableProfiling) as fn(Int) -> Int;
    let st = f(opts);
    return ort_check(lib, st, "DisableProfiling");
  }
}

/// Enable the memory pattern optimization.
/// Complexity: O(1).
pub fn onnx_options_enable_mem_pattern(lib: &OnnxLibrary, opts: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_EnableMemPattern) as fn(Int) -> Int;
    let st = f(opts);
    return ort_check(lib, st, "EnableMemPattern");
  }
}

/// Disable the memory pattern optimization.
/// Complexity: O(1).
pub fn onnx_options_disable_mem_pattern(lib: &OnnxLibrary, opts: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_DisableMemPattern) as fn(Int) -> Int;
    let st = f(opts);
    return ort_check(lib, st, "DisableMemPattern");
  }
}

/// Enable the CPU memory arena.
/// Complexity: O(1).
pub fn onnx_options_enable_cpu_arena(lib: &OnnxLibrary, opts: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_EnableCpuMemArena) as fn(Int) -> Int;
    let st = f(opts);
    return ort_check(lib, st, "EnableCpuMemArena");
  }
}

/// Disable the CPU memory arena.
/// Complexity: O(1).
pub fn onnx_options_disable_cpu_arena(lib: &OnnxLibrary, opts: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_DisableCpuMemArena) as fn(Int) -> Int;
    let st = f(opts);
    return ort_check(lib, st, "DisableCpuMemArena");
  }
}

/// Add a session configuration entry (keys: onnxruntime_session_options_
/// config_keys.h).
/// Complexity: O(len).
pub fn onnx_options_add_config(lib: &OnnxLibrary, opts: Int, key: Str, value_: Str) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
  requires: key.len() > 0
  requires: value_.len() > 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_AddSessionConfigEntry) as fn(Int, *UInt8, *UInt8) -> Int;
    let st = f(opts, key.c_str(), value_.c_str());
    return ort_check(lib, st, "AddSessionConfigEntry");
  }
}

/// Append an execution provider by name (e.g. "CPUExecutionProvider";
/// unknown names fail with ORT's own typed error).
/// Complexity: O(len).
pub fn onnx_options_append_provider(lib: &OnnxLibrary, opts: Int, name: Str) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
  requires: name.len() > 0
{
  var keys = Vec[UInt8].with_len(8);
  var values = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_SessionOptionsAppendExecutionProvider) as fn(Int, *UInt8, *UInt8, *UInt8, Int) -> Int;
    let st = f(opts, name.c_str(), keys.as_mut_ptr(), values.as_mut_ptr(), 0);
    return ort_check(lib, st, "SessionOptionsAppendExecutionProvider(" + name + ")");
  }
}

/// The DirectML execution-provider API table exposed by the loaded runtime
/// (`OrtApi::GetExecutionProviderApi("DML", api_version, &api)`), or the
/// typed SKIP state `ONNX_EP_ABSENT` when the runtime is a build without the
/// DirectML EP (CPU-only). The returned pointer is owned by ORT and stays
/// valid for the lifetime of the loaded runtime; it is an `OrtDmlApi*`.
/// Complexity: O(len).
pub fn onnx_directml_provider_api(lib: &OnnxLibrary) -> Result[Int, OnnxError]
  requires: lib.api != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetExecutionProviderApi) as fn(*UInt8, UInt32, *UInt8) -> Int;
    let st = f("DML".c_str(), lib.api_version as UInt32, slot.as_mut_ptr());
    if st != 0 {
      let e = onnx_status_error(lib, st, "GetExecutionProviderApi(DML)");
      return Err(OnnxError{
        kind: types.ONNX_EP_ABSENT;
        message: "DirectML execution provider absent from this runtime: " + e.message,
      });
    }
    let p = slot_read(&slot);
    if p == 0 {
      return Err(OnnxError{
        kind: types.ONNX_EP_ABSENT;
        message: "DirectML execution provider absent: GetExecutionProviderApi returned null",
      });
    }
    return Ok(p);
  }
}

/// Append the DirectML execution provider to the session options, targeting
/// the adapter at `device_id`. This calls ORT's modern C API path
/// `OrtDmlApi.SessionOptionsAppendExecutionProvider_DML(options, device_id)`
/// (the non-deprecated replacement for the `OrtSessionOptionsAppendExecution
/// Provider_DML` export); it carries the device id directly and needs a
/// runtime built with DirectML. A CPU-only build yields the typed SKIP state
/// `ONNX_EP_ABSENT`, never a hard failure.
///
/// Device expectations: `device_id` is a DXGI adapter index in
/// `IDXGIFactory::EnumAdapters` enumeration order (0-based).
/// `ORT_DML_DEVICE_DEFAULT` (0) selects the default adapter, typically the
/// primary display GPU. Negative ids are invalid; an id beyond the adapter
/// count fails here with ORT's own typed error. See SPEC.md for the recorded
/// live host mapping (adapter 0 = RTX 3070 Ti).
/// Complexity: O(len).
pub fn onnx_options_append_directml(lib: &OnnxLibrary, opts: Int, device_id: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: opts != 0
  requires: device_id >= 0
{
  let ar = onnx_directml_provider_api(lib);
  if !ar.is_ok { return Err(ar.error); }
  unsafe {
    let f = ort_api_slot(ar.value, 0) as fn(Int, Int32) -> Int;
    let st = f(opts, device_id as Int32);
    return ort_check(lib, st, "SessionOptionsAppendExecutionProvider_DML(device_id=" +
      int_to_str(device_id) + ")");
  }
}



// =========================================================================
// Sessions
// =========================================================================

/// Create a session from a model file path (UTF-16 ORTCHAR_T on Windows).
/// Free with `onnx_session_free`.
/// Complexity: O(model).
pub fn onnx_session_new(lib: &OnnxLibrary, env: Int, opts: Int, path: Str) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: env != 0
  requires: path.len() > 0
{
  var wide = to_wide(path);
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_CreateSession) as fn(Int, *UInt8, Int, *UInt8) -> Int;
    let st = f(env, wide.as_mut_ptr(), opts, slot.as_mut_ptr());
    let c = ort_check(lib, st, "CreateSession(" + path + ")");
    if !c.is_ok { return Err(c.error); }
    let s = slot_read(&slot);
    if s == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "CreateSession returned null" });
    }
    return Ok(s);
  }
}

/// Create a session from an in-memory ONNX model.
/// Complexity: O(model).
pub fn onnx_session_new_from_bytes(lib: &OnnxLibrary, env: Int, opts: Int, model: &Vec[UInt8]) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: env != 0
  requires: model.len() > 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_CreateSessionFromArray) as fn(Int, *UInt8, Int, Int, *UInt8) -> Int;
    let st = f(env, model.as_mut_ptr(), model.len(), opts, slot.as_mut_ptr());
    let c = ort_check(lib, st, "CreateSessionFromArray");
    if !c.is_ok { return Err(c.error); }
    let s = slot_read(&slot);
    if s == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "CreateSessionFromArray returned null" });
    }
    return Ok(s);
  }
}

/// Release an OrtSession.
/// Complexity: O(1).
pub fn onnx_session_free(lib: &OnnxLibrary, session: Int)
  requires: lib.api != 0
{
  if session == 0 { return; }
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ReleaseSession) as fn(Int) -> Unit;
    f(session);
  }
}

/// Session input count.
/// Complexity: O(1).
pub fn onnx_session_input_count(lib: &OnnxLibrary, session: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: session != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_SessionGetInputCount) as fn(Int, *UInt8) -> Int;
    let st = f(session, slot.as_mut_ptr());
    let c = ort_check(lib, st, "SessionGetInputCount");
    if !c.is_ok { return Err(c.error); }
    return Ok(slot_read(&slot));
  }
}

/// Session output count.
/// Complexity: O(1).
pub fn onnx_session_output_count(lib: &OnnxLibrary, session: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: session != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_SessionGetOutputCount) as fn(Int, *UInt8) -> Int;
    let st = f(session, slot.as_mut_ptr());
    let c = ort_check(lib, st, "SessionGetOutputCount");
    if !c.is_ok { return Err(c.error); }
    return Ok(slot_read(&slot));
  }
}

/// Input name `idx` (allocator-owned; freed here with the default
/// allocator).
/// Complexity: O(len).
pub fn onnx_session_input_name(lib: &OnnxLibrary, session: Int, idx: Int) -> Result[Str, OnnxError]
  requires: lib.api != 0
  requires: session != 0
  requires: idx >= 0
{
  return session_name(lib, session, idx, true);
}

/// Output name `idx` (allocator-owned; freed here with the default
/// allocator).
/// Complexity: O(len).
pub fn onnx_session_output_name(lib: &OnnxLibrary, session: Int, idx: Int) -> Result[Str, OnnxError]
  requires: lib.api != 0
  requires: session != 0
  requires: idx >= 0
{
  return session_name(lib, session, idx, false);
}

fn session_name(lib: &OnnxLibrary, session: Int, idx: Int, input: Bool) -> Result[Str, OnnxError]
  requires: lib.api != 0
  requires: session != 0
{
  let ar = value.onnx_allocator_default(lib);
  if !ar.is_ok { return Err(ar.error); }
  let alloc = ar.value;
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let idx_api = ORT_API_SessionGetOutputName;
    if input { idx_api = ORT_API_SessionGetInputName; }
    let f = ort_api_slot(lib.api, idx_api) as fn(Int, Int, Int, *UInt8) -> Int;
    let st = f(session, idx, alloc, slot.as_mut_ptr());
    let c = ort_check(lib, st, "SessionGetName(" + int_to_str(idx) + ")");
    if !c.is_ok { return Err(c.error); }
    let p = slot_read(&slot);
    var name = "";
    if p != 0 {
      name = own_c_str(p);
      let fr = value.onnx_allocator_free(lib, alloc, p);
      if !fr.is_ok { return Err(fr.error); }
    }
    return Ok(name);
  }
}

/// All input names, in session order.
/// Complexity: O(inputs * len).
pub fn onnx_session_input_names(lib: &OnnxLibrary, session: Int) -> Result[OnnxStrList, OnnxError]
  requires: lib.api != 0
  requires: session != 0
{
  return session_names(lib, session, true);
}

/// All output names, in session order.
/// Complexity: O(outputs * len).
pub fn onnx_session_output_names(lib: &OnnxLibrary, session: Int) -> Result[OnnxStrList, OnnxError]
  requires: lib.api != 0
  requires: session != 0
{
  return session_names(lib, session, false);
}

fn session_names(lib: &OnnxLibrary, session: Int, input: Bool) -> Result[OnnxStrList, OnnxError]
  requires: lib.api != 0
  requires: session != 0
{
  var count = 0;
  if input {
    let cr = onnx_session_input_count(lib, session);
    if !cr.is_ok { return Err(cr.error); }
    count = cr.value;
  } else {
    let cr = onnx_session_output_count(lib, session);
    if !cr.is_ok { return Err(cr.error); }
    count = cr.value;
  }
  var out: Vec[Str] = Vec[Str].new();
  var i = 0;
  while i < count {
    var nr = onnx_session_output_name(lib, session, i);
    if input { nr = onnx_session_input_name(lib, session, i); }
    if !nr.is_ok { return Err(nr.error); }
    out.push(nr.value);
    i = i + 1;
  };
  return Ok(OnnxStrList{ items: out });
}

/// OrtTypeInfo for session input `idx` (release with
/// `onnx_type_info_free`).
/// Complexity: O(1).
pub fn onnx_session_input_type_info(lib: &OnnxLibrary, session: Int, idx: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: session != 0
  requires: idx >= 0
{
  return session_type_info(lib, session, idx, true);
}

/// OrtTypeInfo for session output `idx` (release with
/// `onnx_type_info_free`).
/// Complexity: O(1).
pub fn onnx_session_output_type_info(lib: &OnnxLibrary, session: Int, idx: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: session != 0
  requires: idx >= 0
{
  return session_type_info(lib, session, idx, false);
}

fn session_type_info(lib: &OnnxLibrary, session: Int, idx: Int, input: Bool) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: session != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let idx_api = ORT_API_SessionGetOutputTypeInfo;
    if input { idx_api = ORT_API_SessionGetInputTypeInfo; }
    let f = ort_api_slot(lib.api, idx_api) as fn(Int, Int, *UInt8) -> Int;
    let st = f(session, idx, slot.as_mut_ptr());
    let c = ort_check(lib, st, "SessionGetTypeInfo(" + int_to_str(idx) + ")");
    if !c.is_ok { return Err(c.error); }
    let ti = slot_read(&slot);
    if ti == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "SessionGetTypeInfo returned null" });
    }
    return Ok(ti);
  }
}

// =========================================================================
// Model metadata
// =========================================================================

/// OrtModelMetadata of a session (release with `onnx_metadata_free`).
/// Complexity: O(1).
pub fn onnx_metadata_new(lib: &OnnxLibrary, session: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: session != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_SessionGetModelMetadata) as fn(Int, *UInt8) -> Int;
    let st = f(session, slot.as_mut_ptr());
    let c = ort_check(lib, st, "SessionGetModelMetadata");
    if !c.is_ok { return Err(c.error); }
    let md = slot_read(&slot);
    if md == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "SessionGetModelMetadata returned null" });
    }
    return Ok(md);
  }
}

fn metadata_str(lib: &OnnxLibrary, md: Int, which: Int) -> Result[Str, OnnxError]
  requires: lib.api != 0
  requires: md != 0
{
  let ar = value.onnx_allocator_default(lib);
  if !ar.is_ok { return Err(ar.error); }
  let alloc = ar.value;
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, which) as fn(Int, Int, *UInt8) -> Int;
    let st = f(md, alloc, slot.as_mut_ptr());
    let c = ort_check(lib, st, "ModelMetadataGet");
    if !c.is_ok { return Err(c.error); }
    let p = slot_read(&slot);
    var s = "";
    if p != 0 {
      s = own_c_str(p);
      let fr = value.onnx_allocator_free(lib, alloc, p);
      if !fr.is_ok { return Err(fr.error); }
    }
    return Ok(s);
  }
}

/// The model producer name (allocator-owned; freed here).
/// Complexity: O(len).
pub fn onnx_metadata_producer(lib: &OnnxLibrary, md: Int) -> Result[Str, OnnxError]
  requires: lib.api != 0
  requires: md != 0
{
  return metadata_str(lib, md, ORT_API_ModelMetadataGetProducerName);
}

/// The model graph name (allocator-owned; freed here).
/// Complexity: O(len).
pub fn onnx_metadata_graph_name(lib: &OnnxLibrary, md: Int) -> Result[Str, OnnxError]
  requires: lib.api != 0
  requires: md != 0
{
  return metadata_str(lib, md, ORT_API_ModelMetadataGetGraphName);
}

/// The model domain (allocator-owned; freed here).
/// Complexity: O(len).
pub fn onnx_metadata_domain(lib: &OnnxLibrary, md: Int) -> Result[Str, OnnxError]
  requires: lib.api != 0
  requires: md != 0
{
  return metadata_str(lib, md, ORT_API_ModelMetadataGetDomain);
}

/// The model version (0 when unset).
/// Complexity: O(1).
pub fn onnx_metadata_version(lib: &OnnxLibrary, md: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: md != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ModelMetadataGetVersion) as fn(Int, *UInt8) -> Int;
    let st = f(md, slot.as_mut_ptr());
    let c = ort_check(lib, st, "ModelMetadataGetVersion");
    if !c.is_ok { return Err(c.error); }
    return Ok(slot_read(&slot));
  }
}

/// Release OrtModelMetadata.
/// Complexity: O(1).
pub fn onnx_metadata_free(lib: &OnnxLibrary, md: Int)
  requires: lib.api != 0
{
  if md == 0 { return; }
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ReleaseModelMetadata) as fn(Int) -> Unit;
    f(md);
  }
}

// =========================================================================
// Run options
// =========================================================================

/// Create OrtRunOptions. Free with `onnx_run_options_free`.
/// Complexity: O(1).
pub fn onnx_run_options_new(lib: &OnnxLibrary) -> Result[Int, OnnxError]
  requires: lib.api != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_CreateRunOptions) as fn(*UInt8) -> Int;
    let st = f(slot.as_mut_ptr());
    let c = ort_check(lib, st, "CreateRunOptions");
    if !c.is_ok { return Err(c.error); }
    let ro = slot_read(&slot);
    if ro == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "CreateRunOptions returned null" });
    }
    return Ok(ro);
  }
}

/// Per-run log verbosity level.
/// Complexity: O(1).
pub fn onnx_run_options_set_verbosity(lib: &OnnxLibrary, ro: Int, level: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: ro != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_RunOptionsSetRunLogVerbosityLevel) as fn(Int, Int32) -> Int;
    let st = f(ro, level as Int32);
    return ort_check(lib, st, "RunOptionsSetRunLogVerbosityLevel");
  }
}

/// Per-run log severity level (ORT_LOGGING_LEVEL_*).
/// Complexity: O(1).
pub fn onnx_run_options_set_severity(lib: &OnnxLibrary, ro: Int, level: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: ro != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_RunOptionsSetRunLogSeverityLevel) as fn(Int, Int32) -> Int;
    let st = f(ro, level as Int32);
    return ort_check(lib, st, "RunOptionsSetRunLogSeverityLevel");
  }
}

/// Per-run tag (used in the per-run log identifier).
/// Complexity: O(len).
pub fn onnx_run_options_set_tag(lib: &OnnxLibrary, ro: Int, tag: Str) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: ro != 0
  requires: tag.len() > 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_RunOptionsSetRunTag) as fn(Int, *UInt8) -> Int;
    let st = f(ro, tag.c_str());
    return ort_check(lib, st, "RunOptionsSetRunTag");
  }
}

/// Read back the per-run verbosity level.
/// Complexity: O(1).
pub fn onnx_run_options_get_verbosity(lib: &OnnxLibrary, ro: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: ro != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_RunOptionsGetRunLogVerbosityLevel) as fn(Int, *UInt8) -> Int;
    let st = f(ro, slot.as_mut_ptr());
    let c = ort_check(lib, st, "RunOptionsGetRunLogVerbosityLevel");
    if !c.is_ok { return Err(c.error); }
    return Ok(slot_read(&slot));
  }
}

/// Read back the per-run severity level.
/// Complexity: O(1).
pub fn onnx_run_options_get_severity(lib: &OnnxLibrary, ro: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: ro != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_RunOptionsGetRunLogSeverityLevel) as fn(Int, *UInt8) -> Int;
    let st = f(ro, slot.as_mut_ptr());
    let c = ort_check(lib, st, "RunOptionsGetRunLogSeverityLevel");
    if !c.is_ok { return Err(c.error); }
    return Ok(slot_read(&slot));
  }
}

/// Read back the per-run tag (owned by the run options).
/// Complexity: O(len).
pub fn onnx_run_options_get_tag(lib: &OnnxLibrary, ro: Int) -> Result[Str, OnnxError]
  requires: lib.api != 0
  requires: ro != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_RunOptionsGetRunTag) as fn(Int, *UInt8) -> Int;
    let st = f(ro, slot.as_mut_ptr());
    let c = ort_check(lib, st, "RunOptionsGetRunTag");
    if !c.is_ok { return Err(c.error); }
    let p = slot_read(&slot);
    if p == 0 { return Ok(""); }
    return Ok(own_c_str(p));
  }
}

/// Release OrtRunOptions.
/// Complexity: O(1).
pub fn onnx_run_options_free(lib: &OnnxLibrary, ro: Int)
  requires: lib.api != 0
{
  if ro == 0 { return; }
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ReleaseRunOptions) as fn(Int) -> Unit;
    f(ro);
  }
}

// =========================================================================
// Run + IoBinding
// =========================================================================

/// Run the session: `inputs[i]` binds to `input_names[i]`;
/// `output_names` selects the outputs. Returns freshly allocated OrtValue
/// handles (release each with `onnx_value_free`). `run_options` may be 0.
/// Complexity: O(run).
pub fn onnx_session_run(lib: &OnnxLibrary, session: Int, run_options: Int, input_names: &Vec[Str], inputs: &Vec[Int], output_names: &Vec[Str]) -> Result[Vec[Int], OnnxError]
  requires: lib.api != 0
  requires: session != 0
  requires: input_names.len() > 0
  requires: inputs.len() > 0
  requires: input_names.len() == inputs.len()
  requires: output_names.len() > 0
{
  let ins = str_array(input_names);
  let outs = str_array(output_names);
  var out_slots = Vec[Int].with_len(output_names.len());
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_Run) as fn(Int, Int, *UInt8, *UInt8, Int, *UInt8, Int, *UInt8) -> Int;
    let st = f(session, run_options, ins.ptrs.as_mut_ptr() as *UInt8, inputs.as_mut_ptr() as *UInt8,
               input_names.len(), outs.ptrs.as_mut_ptr() as *UInt8, output_names.len(),
               out_slots.as_mut_ptr() as *UInt8);
    let c = ort_check(lib, st, "Run");
    if !c.is_ok { return Err(c.error); }
    var out: Vec[Int] = Vec[Int].new();
    var i = 0;
    while i < output_names.len() {
      out.push(out_slots[i]);
      i = i + 1;
    };
    return Ok(out);
  }
}

/// Create an OrtIoBinding for a session. Free with
/// `onnx_io_binding_free`.
/// Complexity: O(1).
pub fn onnx_io_binding_new(lib: &OnnxLibrary, session: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: session != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_CreateIoBinding) as fn(Int, *UInt8) -> Int;
    let st = f(session, slot.as_mut_ptr());
    let c = ort_check(lib, st, "CreateIoBinding");
    if !c.is_ok { return Err(c.error); }
    let b = slot_read(&slot);
    if b == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "CreateIoBinding returned null" });
    }
    return Ok(b);
  }
}

/// Release an OrtIoBinding.
/// Complexity: O(1).
pub fn onnx_io_binding_free(lib: &OnnxLibrary, b: Int)
  requires: lib.api != 0
{
  if b == 0 { return; }
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ReleaseIoBinding) as fn(Int) -> Unit;
    f(b);
  }
}

/// Bind an OrtValue to a named model input.
/// Complexity: O(len).
pub fn onnx_binding_bind_input(lib: &OnnxLibrary, b: Int, name: Str, v: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: b != 0
  requires: name.len() > 0
  requires: v != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_BindInput) as fn(Int, *UInt8, Int) -> Int;
    let st = f(b, name.c_str(), v);
    return ort_check(lib, st, "BindInput(" + name + ")");
  }
}

/// Bind an OrtValue to a named model output.
/// Complexity: O(len).
pub fn onnx_binding_bind_output(lib: &OnnxLibrary, b: Int, name: Str, v: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: b != 0
  requires: name.len() > 0
  requires: v != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_BindOutput) as fn(Int, *UInt8, Int) -> Int;
    let st = f(b, name.c_str(), v);
    return ort_check(lib, st, "BindOutput(" + name + ")");
  }
}

/// Bind a named output to a device (memory info); ORT allocates the output.
/// Complexity: O(len).
pub fn onnx_binding_bind_output_to_device(lib: &OnnxLibrary, b: Int, name: Str, mem_info: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: b != 0
  requires: name.len() > 0
  requires: mem_info != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_BindOutputToDevice) as fn(Int, *UInt8, Int) -> Int;
    let st = f(b, name.c_str(), mem_info);
    return ort_check(lib, st, "BindOutputToDevice(" + name + ")");
  }
}

/// Clear all bound inputs. NOTE: this OrtApi member returns void (not
/// OrtStatus*) per the pinned header.
/// Complexity: O(1).
pub fn onnx_binding_clear_inputs(lib: &OnnxLibrary, b: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: b != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ClearBoundInputs) as fn(Int) -> Unit;
    f(b);
    return Ok(());
  }
}

/// Clear all bound outputs. NOTE: this OrtApi member returns void (not
/// OrtStatus*) per the pinned header.
/// Complexity: O(1).
pub fn onnx_binding_clear_outputs(lib: &OnnxLibrary, b: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: b != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ClearBoundOutputs) as fn(Int) -> Unit;
    f(b);
    return Ok(());
  }
}

/// Synchronize bound inputs (provider-specific; no-op on CPU).
/// Complexity: O(1).
pub fn onnx_binding_sync_inputs(lib: &OnnxLibrary, b: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: b != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_SynchronizeBoundInputs) as fn(Int) -> Int;
    let st = f(b);
    return ort_check(lib, st, "SynchronizeBoundInputs");
  }
}

/// Synchronize bound outputs (provider-specific; no-op on CPU).
/// Complexity: O(1).
pub fn onnx_binding_sync_outputs(lib: &OnnxLibrary, b: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: b != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_SynchronizeBoundOutputs) as fn(Int) -> Int;
    let st = f(b);
    return ort_check(lib, st, "SynchronizeBoundOutputs");
  }
}

/// Run the session through the binding (bound values carry the IO).
/// `run_options` may be 0.
/// Complexity: O(run).
pub fn onnx_binding_run(lib: &OnnxLibrary, session: Int, run_options: Int, b: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: session != 0
  requires: b != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_RunWithBinding) as fn(Int, Int, Int) -> Int;
    let st = f(session, run_options, b);
    return ort_check(lib, st, "RunWithBinding");
  }
}

/// The bound output names in binding order (ownership: ORT allocator; the
/// buffers are freed here with the default allocator).
/// Complexity: O(n * len).
pub fn onnx_binding_output_names(lib: &OnnxLibrary, b: Int) -> Result[OnnxStrList, OnnxError]
  requires: lib.api != 0
  requires: b != 0
{
  let ar = value.onnx_allocator_default(lib);
  if !ar.is_ok { return Err(ar.error); }
  let alloc = ar.value;
  var buf_slot = Vec[UInt8].with_len(8);
  var lens_slot = Vec[UInt8].with_len(8);
  var count_slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetBoundOutputNames) as fn(Int, Int, *UInt8, *UInt8, *UInt8) -> Int;
    let st = f(b, alloc, buf_slot.as_mut_ptr(), lens_slot.as_mut_ptr(), count_slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetBoundOutputNames");
    if !c.is_ok { return Err(c.error); }
    let count = slot_read(&count_slot);
    let buf = slot_read(&buf_slot);
    let lens = slot_read(&lens_slot);
    var out: Vec[Str] = Vec[Str].new();
    var offset = 0;
    var i = 0;
    while i < count {
      let len = ffi.ptr_read_u64_le((lens + i * 8) as *UInt8);
      out.push(read_bytes(buf + offset, len));
      offset = offset + len;
      i = i + 1;
    };
    if buf != 0 {
      let fb = value.onnx_allocator_free(lib, alloc, buf);
      if !fb.is_ok { return Err(fb.error); }
    }
    if lens != 0 {
      let fl = value.onnx_allocator_free(lib, alloc, lens);
      if !fl.is_ok { return Err(fl.error); }
    }
    return Ok(OnnxStrList{ items: out });
  }
}

/// The bound output values in binding order (each release with
/// `onnx_value_free`; the array itself is freed here).
/// Complexity: O(n).
pub fn onnx_binding_output_values(lib: &OnnxLibrary, b: Int) -> Result[Vec[Int], OnnxError]
  requires: lib.api != 0
  requires: b != 0
{
  let ar = value.onnx_allocator_default(lib);
  if !ar.is_ok { return Err(ar.error); }
  let alloc = ar.value;
  var arr_slot = Vec[UInt8].with_len(8);
  var count_slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetBoundOutputValues) as fn(Int, Int, *UInt8, *UInt8) -> Int;
    let st = f(b, alloc, arr_slot.as_mut_ptr(), count_slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetBoundOutputValues");
    if !c.is_ok { return Err(c.error); }
    let count = slot_read(&count_slot);
    let arr = slot_read(&arr_slot);
    var out: Vec[Int] = Vec[Int].new();
    var i = 0;
    while i < count {
      out.push(ffi.ptr_read_u64_le((arr + i * 8) as *UInt8));
      i = i + 1;
    };
    if arr != 0 {
      let fa = value.onnx_allocator_free(lib, alloc, arr);
      if !fa.is_ok { return Err(fa.error); }
    }
    return Ok(out);
  }
}

// =========================================================================
// High-level model API (keeps the 0.1.0 public shape)
// =========================================================================

/// Load `path`, producing a runnable OnnxModel (runtime + env + session +
/// default allocator + IO names). Returns Err with the loader message when
/// no runtime is present (the typed SKIP state surfaces here).
/// Complexity: O(load).
pub fn onnx_load_model(path: Str, config: &OnnxConfig) -> Result[OnnxModel, Str]
  requires: path.len() > 0
{
  let lr = onnx_load();
  if !lr.is_ok {
    return Err("onnx runtime unavailable: " + lr.error.message);
  }
  let lib: OnnxLibrary = lr.value;
  let er = env_new_h(&lib, "xiom.onnx.log");
  if !er.is_ok { close_quiet(&lib); return Err(er.error); }
  let env = er.value;
  let or_ = onnx_session_options_new(&lib);
  if !or_.is_ok { env_free_h(&lib, env); close_quiet(&lib); return Err(or_.error.message); }
  let opts = or_.value;

  let t1 = onnx_options_set_intra_threads(&lib, opts, config.num_threads);
  let t2 = onnx_options_set_graph_opt(&lib, opts, config.graph_optimization_level);
  if !t1.is_ok { onnx_session_options_free(&lib, opts); env_free_h(&lib, env); close_quiet(&lib); return Err(t1.error.message); }
  if !t2.is_ok { onnx_session_options_free(&lib, opts); env_free_h(&lib, env); close_quiet(&lib); return Err(t2.error.message); }
  if config.enable_profiling {
    let tp = onnx_options_enable_profiling(&lib, opts, "onnx_profile");
    if !tp.is_ok { onnx_session_options_free(&lib, opts); env_free_h(&lib, env); close_quiet(&lib); return Err(tp.error.message); }
  }

  let sr = onnx_session_new(&lib, env, opts, path);
  onnx_session_options_free(&lib, opts);
  if !sr.is_ok { env_free_h(&lib, env); close_quiet(&lib); return Err(sr.error.message); }
  let session = sr.value;

  let nr = onnx_session_input_names(&lib, session);
  if !nr.is_ok { onnx_session_free(&lib, session); env_free_h(&lib, env); close_quiet(&lib); return Err(nr.error.message); }
  let mr = onnx_session_output_names(&lib, session);
  if !mr.is_ok { onnx_session_free(&lib, session); env_free_h(&lib, env); close_quiet(&lib); return Err(mr.error.message); }

  let ar = onnx_allocator_default(&lib);
  if !ar.is_ok { onnx_session_free(&lib, session); env_free_h(&lib, env); close_quiet(&lib); return Err(ar.error.message); }

  return Ok(OnnxModel{
    path: path;
    session: session;
    env: env;
    allocator: ar.value;
    api: lib.api;
    handle: lib.handle;
    input_names: nr.value.items;
    output_names: mr.value.items;
  });
}

fn env_new_h(lib: &OnnxLibrary, logid: Str) -> Result[Int, Str]
  requires: lib.api != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_CreateEnv) as fn(Int32, *UInt8, *UInt8) -> Int;
    let st = f(types.ORT_LOGGING_LEVEL_WARNING as Int32, logid.c_str(), slot.as_mut_ptr());
    if st != 0 { return Err(onnx_status_error(lib, st, "CreateEnv").message); }
    let env = slot_read(&slot);
    if env == 0 { return Err("CreateEnv returned null"); }
    return Ok(env);
  }
}

fn env_free_h(lib: &OnnxLibrary, env: Int)
  requires: lib.api != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ReleaseEnv) as fn(Int) -> Unit;
    f(env);
  }
}

fn close_quiet(lib: &OnnxLibrary) {
  let cr = loader.onnx_close(lib);
  let _ = cr;
}

/// Rebuild the library view a model carries (low-level calls use it).
/// Complexity: O(1).
pub fn onnx_model_library(model: &OnnxModel) -> OnnxLibrary
  requires: model.api != 0
{
  return OnnxLibrary{
    handle: model.handle;
    soname: "";
    base: 0;
    api: model.api;
    api_version: 0;
    version: "";
    resolved: 0;
    required: 0;
  };
}

/// Model input count (from the names captured at load).
/// Complexity: O(1).
pub fn onnx_get_input_count(model: &OnnxModel) -> Int
  requires: model.session != 0
{
  return model.input_names.len();
}

/// Model output count (from the names captured at load).
/// Complexity: O(1).
pub fn onnx_get_output_count(model: &OnnxModel) -> Int
  requires: model.session != 0
{
  return model.output_names.len();
}

/// Run inference: FLOAT inputs in, FLOAT outputs out. Input tensors bind by
/// their `name`; outputs come back in model output order with shape/dtype
/// read from ORT.
/// Complexity: O(run + data).
pub fn onnx_run(model: &OnnxModel, inputs: &Vec[OnnxTensor]) -> Result[OnnxTensorList, Str]
  requires: model.session != 0
  requires: inputs.len() > 0
{
  let lib = onnx_model_library(model);
  var values: Vec[Int] = Vec[Int].new();
  var names: Vec[Str] = Vec[Str].new();

  var i = 0;
  while i < inputs.len() {
    let t = inputs[i];
    if t.dtype != types.ORT_DTYPE_FLOAT {
      release_values(&lib, &values);
      return Err("onnx_run: only FLOAT inputs are supported (dtype " + int_to_str(t.dtype) + ")");
    }
    let vr = value.onnx_value_tensor_new(&lib, model.allocator, &t.shape, t.dtype);
    if !vr.is_ok {
      release_values(&lib, &values);
      return Err(vr.error.message);
    };
    let wr = value.onnx_value_write_f32(&lib, vr.value, &t.data);
    if !wr.is_ok {
      value.onnx_value_free(&lib, vr.value);
      release_values(&lib, &values);
      return Err(wr.error.message);
    };
    values.push(vr.value);
    names.push(t.name);
    i = i + 1;
  };

  let rr = onnx_session_run(&lib, model.session, 0, &names, &values, &model.output_names);
  if !rr.is_ok {
    release_values(&lib, &values);
    return Err(rr.error.message);
  }
  let out_values: Vec[Int] = rr.value;
  release_values(&lib, &values);

  var out: Vec[OnnxTensor] = Vec[OnnxTensor].new();
  var j = 0;
  while j < out_values.len() {
    let v = out_values[j];
    let ti = value.onnx_value_tensor_info(&lib, v);
    if !ti.is_ok {
      release_values(&lib, &out_values);
      return Err(ti.error.message);
    };
    let dims = value.onnx_tensor_info_dims(&lib, ti.value);
    let dts = value.onnx_tensor_info_element_type(&lib, ti.value);
    let cnt = value.onnx_tensor_info_shape_count(&lib, ti.value);
    value.onnx_tensor_info_free(&lib, ti.value);
    if !dims.is_ok || !dts.is_ok || !cnt.is_ok {
      release_values(&lib, &out_values);
      return Err("onnx_run: output metadata read failed");
    };
    if dts.value != types.ORT_DTYPE_FLOAT {
      release_values(&lib, &out_values);
      return Err("onnx_run: only FLOAT outputs are supported (dtype " + int_to_str(dts.value) + ")");
    }
    if cnt.value <= 0 {
      release_values(&lib, &out_values);
      return Err("onnx_run: output has no static element count");
    }
    let data = value.onnx_value_read_f32(&lib, v, cnt.value);
    if !data.is_ok {
      release_values(&lib, &out_values);
      return Err(data.error.message);
    }
    var nm = "";
    if j < model.output_names.len() { nm = model.output_names[j]; }
    out.push(OnnxTensor{
      name: nm;
      data: data.value.items;
      shape: dims.value;
      dtype: dts.value;
    });
    j = j + 1;
  }
  release_values(&lib, &out_values);
  return Ok(OnnxTensorList{ items: out });
}

fn release_values(lib: &OnnxLibrary, values: &Vec[Int]) {
  var i = 0;
  while i < values.len() {
    value.onnx_value_free(lib, values[i]);
    i = i + 1;
  };
}

/// Release a model: session, environment and runtime handle.
/// Complexity: O(1).
pub fn onnx_close(model: &OnnxModel) {
  let lib = onnx_model_library(model);
  onnx_session_free(&lib, model.session);
  env_free_h(&lib, model.env);
  close_quiet(&lib);
}
