// XIOM -- xiom.onnx.loader: multi-soname ONNX Runtime loader over xiom.ffi.dl.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN DECISION (ML/AI sector): **system-library path, not vendored** --
// the ONNX Runtime C API is reached through its stable `OrtGetApiBase` entry
// point and the versioned `OrtApi` function-pointer table; nothing is
// compiled into this package and nothing is linked at build time. The loader
// probes common sonames in order and the suite reports SKIP when none is
// present, so CI without a runtime stays green.
//
// Table access: the pinned header (v1.31.0) declares 428 OrtApi members in
// order; ORT appends members over releases, so every member keeps its index
// forever (verified: v1.14.1's 239 members are exactly the first 239 of
// v1.31.0's list). Slots are read as u64s at `api + index * 8` and cast to
// `fn` pointers only inside `unsafe` blocks (B-series discipline).
//
// Version negotiation: `GetVersionString` names the runtime (e.g. "1.17.1");
// the minor number IS the OrtApi version implemented by that build. The
// loader requests `min(ORT_API_VERSION_PIN, minor)` and rejects builds older
// than ONNX_MIN_API_VERSION (1.14) as ABI, since the declared surface needs
// every member at its pinned index.
//
// Classification:
//   ONNX_LOAD_ABSENT -> no candidate soname loaded -> SKIP
//   ONNX_LOAD_ABI    -> candidate loaded, surface/version unusable -> FAIL
//   ONNX_CALL_FAILED -> a call returned an OrtStatus error (typed message)

module xiom.onnx.loader

use xiom.onnx.types;
use xiom.ffi.dl;
use xiom.ffi;
use xiom.io;

// =========================================================================
// OrtApi / OrtApiBase member indices (oracle: pinned onnxruntime_c_api.h;
// every index below was compiler-verified with offsetof against the header)
// =========================================================================

pub const ORT_API_CreateStatus: Int = 0;
pub const ORT_API_GetErrorCode: Int = 1;
pub const ORT_API_GetErrorMessage: Int = 2;
pub const ORT_API_CreateEnv: Int = 3;
pub const ORT_API_EnableTelemetryEvents: Int = 5;
pub const ORT_API_DisableTelemetryEvents: Int = 6;
pub const ORT_API_CreateSession: Int = 7;
pub const ORT_API_CreateSessionFromArray: Int = 8;
pub const ORT_API_Run: Int = 9;
pub const ORT_API_CreateSessionOptions: Int = 10;
pub const ORT_API_SetSessionExecutionMode: Int = 13;
pub const ORT_API_EnableProfiling: Int = 14;
pub const ORT_API_DisableProfiling: Int = 15;
pub const ORT_API_EnableMemPattern: Int = 16;
pub const ORT_API_DisableMemPattern: Int = 17;
pub const ORT_API_EnableCpuMemArena: Int = 18;
pub const ORT_API_DisableCpuMemArena: Int = 19;
pub const ORT_API_SetSessionLogId: Int = 20;
pub const ORT_API_SetSessionLogVerbosityLevel: Int = 21;
pub const ORT_API_SetSessionLogSeverityLevel: Int = 22;
pub const ORT_API_SetSessionGraphOptimizationLevel: Int = 23;
pub const ORT_API_SetIntraOpNumThreads: Int = 24;
pub const ORT_API_SetInterOpNumThreads: Int = 25;
pub const ORT_API_SessionGetInputCount: Int = 30;
pub const ORT_API_SessionGetOutputCount: Int = 31;
pub const ORT_API_SessionGetInputTypeInfo: Int = 33;
pub const ORT_API_SessionGetOutputTypeInfo: Int = 34;
pub const ORT_API_SessionGetInputName: Int = 36;
pub const ORT_API_SessionGetOutputName: Int = 37;
pub const ORT_API_CreateRunOptions: Int = 39;
pub const ORT_API_RunOptionsSetRunLogVerbosityLevel: Int = 40;
pub const ORT_API_RunOptionsSetRunLogSeverityLevel: Int = 41;
pub const ORT_API_RunOptionsSetRunTag: Int = 42;
pub const ORT_API_RunOptionsGetRunLogVerbosityLevel: Int = 43;
pub const ORT_API_RunOptionsGetRunLogSeverityLevel: Int = 44;
pub const ORT_API_RunOptionsGetRunTag: Int = 45;
pub const ORT_API_CreateTensorAsOrtValue: Int = 48;
pub const ORT_API_CreateTensorWithDataAsOrtValue: Int = 49;
pub const ORT_API_IsTensor: Int = 50;
pub const ORT_API_GetTensorMutableData: Int = 51;
pub const ORT_API_CastTypeInfoToTensorInfo: Int = 55;
pub const ORT_API_GetOnnxTypeFromTypeInfo: Int = 56;
pub const ORT_API_GetTensorElementType: Int = 60;
pub const ORT_API_GetDimensionsCount: Int = 61;
pub const ORT_API_GetDimensions: Int = 62;
pub const ORT_API_GetSymbolicDimensions: Int = 63;
pub const ORT_API_GetTensorShapeElementCount: Int = 64;
pub const ORT_API_GetTensorTypeAndShape: Int = 65;
pub const ORT_API_GetTypeInfo: Int = 66;
pub const ORT_API_GetValueType: Int = 67;
pub const ORT_API_CreateCpuMemoryInfo: Int = 69;
pub const ORT_API_MemoryInfoGetName: Int = 71;
pub const ORT_API_MemoryInfoGetId: Int = 72;
pub const ORT_API_MemoryInfoGetMemType: Int = 73;
pub const ORT_API_MemoryInfoGetType: Int = 74;
pub const ORT_API_AllocatorAlloc: Int = 75;
pub const ORT_API_AllocatorFree: Int = 76;
pub const ORT_API_AllocatorGetInfo: Int = 77;
pub const ORT_API_GetAllocatorWithDefaultOptions: Int = 78;
pub const ORT_API_GetValue: Int = 80;
pub const ORT_API_GetValueCount: Int = 81;
pub const ORT_API_ReleaseEnv: Int = 92;
pub const ORT_API_ReleaseStatus: Int = 93;
pub const ORT_API_ReleaseMemoryInfo: Int = 94;
pub const ORT_API_ReleaseSession: Int = 95;
pub const ORT_API_ReleaseValue: Int = 96;
pub const ORT_API_ReleaseRunOptions: Int = 97;
pub const ORT_API_ReleaseTypeInfo: Int = 98;
pub const ORT_API_ReleaseTensorTypeAndShapeInfo: Int = 99;
pub const ORT_API_ReleaseSessionOptions: Int = 100;
pub const ORT_API_SessionGetModelMetadata: Int = 111;
pub const ORT_API_ModelMetadataGetProducerName: Int = 112;
pub const ORT_API_ModelMetadataGetGraphName: Int = 113;
pub const ORT_API_ModelMetadataGetDomain: Int = 114;
pub const ORT_API_ModelMetadataGetVersion: Int = 117;
pub const ORT_API_ReleaseModelMetadata: Int = 118;
pub const ORT_API_GetAvailableProviders: Int = 125;
pub const ORT_API_ReleaseAvailableProviders: Int = 126;
pub const ORT_API_AddSessionConfigEntry: Int = 130;
pub const ORT_API_CreateAllocator: Int = 131;
pub const ORT_API_ReleaseAllocator: Int = 132;
pub const ORT_API_RunWithBinding: Int = 133;
pub const ORT_API_CreateIoBinding: Int = 134;
pub const ORT_API_ReleaseIoBinding: Int = 135;
pub const ORT_API_BindInput: Int = 136;
pub const ORT_API_BindOutput: Int = 137;
pub const ORT_API_BindOutputToDevice: Int = 138;
pub const ORT_API_GetBoundOutputNames: Int = 139;
pub const ORT_API_GetBoundOutputValues: Int = 140;
pub const ORT_API_ClearBoundInputs: Int = 141;
pub const ORT_API_ClearBoundOutputs: Int = 142;
pub const ORT_API_GetTensorMemoryInfo: Int = 194;
pub const ORT_API_SynchronizeBoundInputs: Int = 202;
pub const ORT_API_SynchronizeBoundOutputs: Int = 203;
pub const ORT_API_SessionOptionsAppendExecutionProvider: Int = 216;

/// OrtApiBase member indices (2 members: the whole struct).
pub const ORT_BASE_GetApi: Int = 0;
pub const ORT_BASE_GetVersionString: Int = 1;

/// A call failed with an OrtStatus error; the message carries the ORT code.
pub const ONNX_CALL_FAILED: Int = 2;

// =========================================================================
// Declared surface (the 94 OrtApi entry points this package binds; the
// SPEC.md coverage table mirrors this list 1:1)
// =========================================================================

/// The OrtApi indices of the declared surface, in table order.
/// Complexity: O(n).
pub fn onnx_surface_slots() -> Vec[Int]
  requires: true
{
  var v: Vec[Int] = Vec[Int].new();
  v.push(ORT_API_CreateStatus);
  v.push(ORT_API_GetErrorCode);
  v.push(ORT_API_GetErrorMessage);
  v.push(ORT_API_ReleaseStatus);
  v.push(ORT_API_CreateEnv);
  v.push(ORT_API_ReleaseEnv);
  v.push(ORT_API_EnableTelemetryEvents);
  v.push(ORT_API_DisableTelemetryEvents);
  v.push(ORT_API_GetAvailableProviders);
  v.push(ORT_API_ReleaseAvailableProviders);
  v.push(ORT_API_CreateSession);
  v.push(ORT_API_CreateSessionFromArray);
  v.push(ORT_API_Run);
  v.push(ORT_API_CreateSessionOptions);
  v.push(ORT_API_SetSessionExecutionMode);
  v.push(ORT_API_EnableProfiling);
  v.push(ORT_API_DisableProfiling);
  v.push(ORT_API_EnableMemPattern);
  v.push(ORT_API_DisableMemPattern);
  v.push(ORT_API_EnableCpuMemArena);
  v.push(ORT_API_DisableCpuMemArena);
  v.push(ORT_API_SetSessionLogId);
  v.push(ORT_API_SetSessionLogVerbosityLevel);
  v.push(ORT_API_SetSessionLogSeverityLevel);
  v.push(ORT_API_SetSessionGraphOptimizationLevel);
  v.push(ORT_API_SetIntraOpNumThreads);
  v.push(ORT_API_SetInterOpNumThreads);
  v.push(ORT_API_SessionGetInputCount);
  v.push(ORT_API_SessionGetOutputCount);
  v.push(ORT_API_SessionGetInputTypeInfo);
  v.push(ORT_API_SessionGetOutputTypeInfo);
  v.push(ORT_API_SessionGetInputName);
  v.push(ORT_API_SessionGetOutputName);
  v.push(ORT_API_ReleaseSession);
  v.push(ORT_API_ReleaseSessionOptions);
  v.push(ORT_API_SessionGetModelMetadata);
  v.push(ORT_API_ModelMetadataGetProducerName);
  v.push(ORT_API_ModelMetadataGetGraphName);
  v.push(ORT_API_ModelMetadataGetDomain);
  v.push(ORT_API_ModelMetadataGetVersion);
  v.push(ORT_API_ReleaseModelMetadata);
  v.push(ORT_API_AddSessionConfigEntry);
  v.push(ORT_API_SessionOptionsAppendExecutionProvider);
  v.push(ORT_API_CreateTensorAsOrtValue);
  v.push(ORT_API_CreateTensorWithDataAsOrtValue);
  v.push(ORT_API_IsTensor);
  v.push(ORT_API_GetTensorMutableData);
  v.push(ORT_API_CastTypeInfoToTensorInfo);
  v.push(ORT_API_GetOnnxTypeFromTypeInfo);
  v.push(ORT_API_GetTensorElementType);
  v.push(ORT_API_GetDimensionsCount);
  v.push(ORT_API_GetDimensions);
  v.push(ORT_API_GetSymbolicDimensions);
  v.push(ORT_API_GetTensorShapeElementCount);
  v.push(ORT_API_GetTensorTypeAndShape);
  v.push(ORT_API_GetTypeInfo);
  v.push(ORT_API_GetValueType);
  v.push(ORT_API_CreateCpuMemoryInfo);
  v.push(ORT_API_MemoryInfoGetName);
  v.push(ORT_API_MemoryInfoGetId);
  v.push(ORT_API_MemoryInfoGetMemType);
  v.push(ORT_API_MemoryInfoGetType);
  v.push(ORT_API_AllocatorAlloc);
  v.push(ORT_API_AllocatorFree);
  v.push(ORT_API_AllocatorGetInfo);
  v.push(ORT_API_GetAllocatorWithDefaultOptions);
  v.push(ORT_API_GetValue);
  v.push(ORT_API_GetValueCount);
  v.push(ORT_API_ReleaseMemoryInfo);
  v.push(ORT_API_ReleaseValue);
  v.push(ORT_API_ReleaseTypeInfo);
  v.push(ORT_API_ReleaseTensorTypeAndShapeInfo);
  v.push(ORT_API_CreateAllocator);
  v.push(ORT_API_ReleaseAllocator);
  v.push(ORT_API_GetTensorMemoryInfo);
  v.push(ORT_API_CreateRunOptions);
  v.push(ORT_API_RunOptionsSetRunLogVerbosityLevel);
  v.push(ORT_API_RunOptionsSetRunLogSeverityLevel);
  v.push(ORT_API_RunOptionsSetRunTag);
  v.push(ORT_API_RunOptionsGetRunLogVerbosityLevel);
  v.push(ORT_API_RunOptionsGetRunLogSeverityLevel);
  v.push(ORT_API_RunOptionsGetRunTag);
  v.push(ORT_API_ReleaseRunOptions);
  v.push(ORT_API_RunWithBinding);
  v.push(ORT_API_CreateIoBinding);
  v.push(ORT_API_ReleaseIoBinding);
  v.push(ORT_API_BindInput);
  v.push(ORT_API_BindOutput);
  v.push(ORT_API_BindOutputToDevice);
  v.push(ORT_API_GetBoundOutputNames);
  v.push(ORT_API_GetBoundOutputValues);
  v.push(ORT_API_ClearBoundInputs);
  v.push(ORT_API_ClearBoundOutputs);
  v.push(ORT_API_SynchronizeBoundInputs);
  v.push(ORT_API_SynchronizeBoundOutputs);
  return v;
}

/// The C API names of the declared surface, index-aligned with
/// `onnx_surface_slots()` (94 entries; plus the 2 OrtApiBase entries).
/// Complexity: O(n).
pub fn onnx_surface_names() -> Vec[Str]
  requires: true
{
  var v: Vec[Str] = Vec[Str].new();
  v.push("CreateStatus");
  v.push("GetErrorCode");
  v.push("GetErrorMessage");
  v.push("ReleaseStatus");
  v.push("CreateEnv");
  v.push("ReleaseEnv");
  v.push("EnableTelemetryEvents");
  v.push("DisableTelemetryEvents");
  v.push("GetAvailableProviders");
  v.push("ReleaseAvailableProviders");
  v.push("CreateSession");
  v.push("CreateSessionFromArray");
  v.push("Run");
  v.push("CreateSessionOptions");
  v.push("SetSessionExecutionMode");
  v.push("EnableProfiling");
  v.push("DisableProfiling");
  v.push("EnableMemPattern");
  v.push("DisableMemPattern");
  v.push("EnableCpuMemArena");
  v.push("DisableCpuMemArena");
  v.push("SetSessionLogId");
  v.push("SetSessionLogVerbosityLevel");
  v.push("SetSessionLogSeverityLevel");
  v.push("SetSessionGraphOptimizationLevel");
  v.push("SetIntraOpNumThreads");
  v.push("SetInterOpNumThreads");
  v.push("SessionGetInputCount");
  v.push("SessionGetOutputCount");
  v.push("SessionGetInputTypeInfo");
  v.push("SessionGetOutputTypeInfo");
  v.push("SessionGetInputName");
  v.push("SessionGetOutputName");
  v.push("ReleaseSession");
  v.push("ReleaseSessionOptions");
  v.push("SessionGetModelMetadata");
  v.push("ModelMetadataGetProducerName");
  v.push("ModelMetadataGetGraphName");
  v.push("ModelMetadataGetDomain");
  v.push("ModelMetadataGetVersion");
  v.push("ReleaseModelMetadata");
  v.push("AddSessionConfigEntry");
  v.push("SessionOptionsAppendExecutionProvider");
  v.push("CreateTensorAsOrtValue");
  v.push("CreateTensorWithDataAsOrtValue");
  v.push("IsTensor");
  v.push("GetTensorMutableData");
  v.push("CastTypeInfoToTensorInfo");
  v.push("GetOnnxTypeFromTypeInfo");
  v.push("GetTensorElementType");
  v.push("GetDimensionsCount");
  v.push("GetDimensions");
  v.push("GetSymbolicDimensions");
  v.push("GetTensorShapeElementCount");
  v.push("GetTensorTypeAndShape");
  v.push("GetTypeInfo");
  v.push("GetValueType");
  v.push("CreateCpuMemoryInfo");
  v.push("MemoryInfoGetName");
  v.push("MemoryInfoGetId");
  v.push("MemoryInfoGetMemType");
  v.push("MemoryInfoGetType");
  v.push("AllocatorAlloc");
  v.push("AllocatorFree");
  v.push("AllocatorGetInfo");
  v.push("GetAllocatorWithDefaultOptions");
  v.push("GetValue");
  v.push("GetValueCount");
  v.push("ReleaseMemoryInfo");
  v.push("ReleaseValue");
  v.push("ReleaseTypeInfo");
  v.push("ReleaseTensorTypeAndShapeInfo");
  v.push("CreateAllocator");
  v.push("ReleaseAllocator");
  v.push("GetTensorMemoryInfo");
  v.push("CreateRunOptions");
  v.push("RunOptionsSetRunLogVerbosityLevel");
  v.push("RunOptionsSetRunLogSeverityLevel");
  v.push("RunOptionsSetRunTag");
  v.push("RunOptionsGetRunLogVerbosityLevel");
  v.push("RunOptionsGetRunLogSeverityLevel");
  v.push("RunOptionsGetRunTag");
  v.push("ReleaseRunOptions");
  v.push("RunWithBinding");
  v.push("CreateIoBinding");
  v.push("ReleaseIoBinding");
  v.push("BindInput");
  v.push("BindOutput");
  v.push("BindOutputToDevice");
  v.push("GetBoundOutputNames");
  v.push("GetBoundOutputValues");
  v.push("ClearBoundInputs");
  v.push("ClearBoundOutputs");
  v.push("SynchronizeBoundInputs");
  v.push("SynchronizeBoundOutputs");
  return v;
}

// =========================================================================
// Table access helpers
// =========================================================================

/// The fn-pointer slot `idx` of a resolved OrtApi table (0 = not present).
/// Complexity: O(1).
pub fn ort_api_slot(api: Int, idx: Int) -> Int
  requires: api != 0
  requires: idx >= 0
{
  unsafe {
    return ffi.ptr_read_u64_le((api + idx * 8) as *UInt8);
  }
}

/// The fn-pointer slot of an OrtApiBase struct (2 members).
/// Complexity: O(1).
fn ort_base_slot(base: Int, idx: Int) -> Int
  requires: base != 0
  requires: idx >= 0
{
  unsafe {
    return ffi.ptr_read_u64_le((base + idx * 8) as *UInt8);
  }
}

/// Parse the minor number of an ONNX Runtime version string ("1.31.0" -> 31,
/// "1.14.1+cpu" -> 14). Returns 0 when unparsable.
/// Complexity: O(len).
pub fn onnx_parse_minor(version: Str) -> Int
  requires: true
{
  var i = 0;
  var seen_dot = false;
  var value = 0;
  var digits = 0;
  while i < version.len() {
    let c = version.byte_at(i);
    if !seen_dot {
      if c == 46 {
        seen_dot = true;
      }
      i = i + 1;
      continue;
    }
    if c < 48 { break; }
    if c > 57 { break; }
    value = value * 10 + (c - 48);
    digits = digits + 1;
    i = i + 1;
  }
  if digits == 0 { return 0; }
  return value;
}

// =========================================================================
// Loader
// =========================================================================

fn fail_load(handle: Int, message: Str) -> Result[OnnxLibrary, OnnxError] {
  var ig = dl.dl_close(handle);
  return Err(OnnxError{ kind: ONNX_LOAD_ABI; message: message });
}

fn try_load(soname: Str) -> Result[OnnxLibrary, OnnxError]
  requires: soname.len() > 0
{
  let h = dl.dl_open(soname);
  if !h.is_ok {
    // Not this candidate: report ABSENT so the caller can try the next one.
    return Err(OnnxError{ kind: ONNX_LOAD_ABSENT; message: soname + ": " + h.error });
  }
  let handle: Int = h.value;

  let sym = dl.dl_sym(handle, "OrtGetApiBase");
  if !sym.is_ok {
    return fail_load(handle, soname + ": OrtGetApiBase missing: " + sym.error);
  }

  let get_base = unsafe { sym.value as fn() -> Int };
  let base: Int = get_base();
  if base == 0 {
    return fail_load(handle, soname + ": OrtGetApiBase returned null");
  }

  let vs_fp = ort_base_slot(base, ORT_BASE_GetVersionString);
  if vs_fp == 0 {
    return fail_load(handle, soname + ": OrtApiBase.GetVersionString slot empty");
  }
  let vs = unsafe { vs_fp as fn() -> *UInt8 };
  let vp = vs();
  if (unsafe { vp as Int }) == 0 {
    return fail_load(handle, soname + ": OrtApiBase.GetVersionString returned null");
  }
  let version = Str::from_c_str(vp);

  let minor = onnx_parse_minor(version);
  if minor < types.ONNX_MIN_API_VERSION {
    return fail_load(handle, soname + ": runtime " + version +
      " is older than the declared floor 1." + int_to_str(types.ONNX_MIN_API_VERSION));
  }
  var req = minor;
  if req > types.ORT_API_VERSION_PIN {
    req = types.ORT_API_VERSION_PIN;
  }

  let ga_fp = ort_base_slot(base, ORT_BASE_GetApi);
  if ga_fp == 0 {
    return fail_load(handle, soname + ": OrtApiBase.GetApi slot empty");
  }
  let ga = unsafe { ga_fp as fn(Int32) -> Int };
  let api: Int = ga(req as Int32);
  if api == 0 {
    return fail_load(handle, soname + ": GetApi(" + int_to_str(req) + ") returned null");
  }

  let slots = onnx_surface_slots();
  let names = onnx_surface_names();
  var resolved = 0;
  var first_missing = "";
  var i = 0;
  while i < slots.len() {
    if ort_api_slot(api, slots[i]) != 0 {
      resolved = resolved + 1;
    } else {
      if first_missing.len() == 0 {
        first_missing = names[i];
      }
    }
    i = i + 1;
  };
  if resolved < slots.len() {
    return fail_load(handle, soname + ": " + int_to_str(resolved) + "/" +
      int_to_str(slots.len()) + " declared entry points present (first missing: " +
      first_missing + ")");
  }

  return Ok(OnnxLibrary{
    handle: handle;
    soname: soname;
    base: base;
    api: api;
    api_version: req;
    version: version;
    resolved: resolved;
    required: slots.len();
  });
}

/// The multi-soname candidate list, in probe order: the optional
/// `XIOM_ONNX_RUNTIME` override (explicit path, used by the live leg),
/// then the Windows, Linux and macOS sonames.
/// Complexity: O(1).
pub fn onnx_load_candidates() -> Vec[Str]
  requires: true
{
  var v: Vec[Str] = Vec[Str].new();
  let override = io.env_var("XIOM_ONNX_RUNTIME");
  if override.is_some {
    if override.value.len() > 0 {
      v.push(override.value);
    }
  }
  v.push("onnxruntime.dll");
  v.push("libonnxruntime.so");
  v.push("libonnxruntime.so.1");
  v.push("libonnxruntime.dylib");
  return v;
}

/// Load an explicitly named build (path or soname). A bogus name yields the
/// deterministic ABSENT classification on any host (the SKIP probe).
/// Complexity: O(load + surface check).
pub fn onnx_load_named(soname: Str) -> Result[OnnxLibrary, OnnxError]
  requires: soname.len() > 0
{
  return try_load(soname);
}

/// Load the first usable candidate from `onnx_load_candidates()`. No
/// candidate present -> ONNX_LOAD_ABSENT (the typed SKIP state); a candidate
/// that loads but fails the surface/version check -> its ABI error is kept
/// while later candidates are still tried.
/// Complexity: O(candidates * surface).
pub fn onnx_load() -> Result[OnnxLibrary, OnnxError]
  requires: true
{
  let cands = onnx_load_candidates();
  var abi: OnnxError = OnnxError{ kind: ONNX_LOAD_ABSENT; message: "" };
  var i = 0;
  while i < cands.len() {
    let r = try_load(cands[i]);
    if r.is_ok {
      return Ok(r.value);
    }
    if r.error.kind == ONNX_LOAD_ABI {
      abi = r.error;
    }
    i = i + 1;
  };
  if abi.message.len() > 0 {
    return Err(abi);
  }
  return Err(OnnxError{
    kind: ONNX_LOAD_ABSENT;
    message: "onnx: no runtime candidate loaded (tried " + int_to_str(cands.len()) +
      " candidates: XIOM_ONNX_RUNTIME, onnxruntime.dll, libonnxruntime.so, libonnxruntime.so.1, libonnxruntime.dylib)",
  });
}

/// Release the runtime handle.
/// Complexity: O(1).
pub fn onnx_close(lib: &OnnxLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

/// Version + surface counts of a loaded build (the live-leg probe).
/// Complexity: O(1).
pub fn onnx_probe(lib: &OnnxLibrary) -> OnnxInfo
  requires: lib.api != 0
{
  return OnnxInfo{
    soname: lib.soname;
    version: lib.version;
    api_version: lib.api_version;
    resolved: lib.resolved;
    required: lib.required;
  };
}

/// Convert an OrtStatus* (non-null) into a typed error and release the
/// status. `kind` is ONNX_CALL_FAILED; the message carries the ORT error
/// code and its message.
/// Complexity: O(len).
pub fn onnx_status_error(lib: &OnnxLibrary, status: Int, context: Str) -> OnnxError
  requires: lib.api != 0
  requires: status != 0
  requires: context.len() > 0
{
  unsafe {
    let ge_parent = ort_api_slot(lib.api, ORT_API_GetErrorCode);
    let gm_parent = ort_api_slot(lib.api, ORT_API_GetErrorMessage);
    let rs_parent = ort_api_slot(lib.api, ORT_API_ReleaseStatus);
    let ge = ge_parent as fn(Int) -> Int32;
    let code = ge(status) as Int;
    let gm = gm_parent as fn(Int) -> *UInt8;
    let mp = gm(status);
    var msg = "<no message>";
    if (mp as Int) != 0 {
      msg = own_c_str(mp as Int);
    }
    let rs = rs_parent as fn(Int) -> Unit;
    rs(status);
    var code_name = types.ort_error_code_name(code);
    if code_name.len() == 0 { code_name = int_to_str(code); }
    return OnnxError{
      kind: ONNX_CALL_FAILED;
      message: context + ": " + msg + " [ort " + code_name + "]";
    };
  }
}

/// OrtStatus protocol check: 0 (null) = success; otherwise convert.
/// Complexity: O(len).
pub fn ort_check(lib: &OnnxLibrary, status: Int, context: Str) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: context.len() > 0
{
  if status == 0 { return Ok(()); }
  return Err(onnx_status_error(lib, status, context));
}

/// Copy a NUL-terminated foreign string (bounded scan) into an XIOM-owned
/// Str. Required for strings ORT allocates and the caller frees (allocator-
/// returned names, status messages): `Str::from_c_str` views the foreign
/// bytes, which dangle once ORT frees them.
/// Complexity: O(len).
pub fn own_c_str(p: Int) -> Str
  requires: p != 0
{
  var bytes: Vec[UInt8] = Vec[UInt8].new();
  unsafe {
    let sp = ffi.safe_ptr_from_raw(p as *UInt8, 4096);
    if !sp.is_ok { return ""; }
    let safe: SafePtr = sp.value;
    var i = 0;
    var stop = false;
    while i < 4096 {
      let r = ffi.safe_ptr_read_byte(&safe, i);
      if !r.is_ok {
        stop = true;
      } elif r.value == 0 {
        stop = true;
      } else {
        bytes.push(r.value as UInt8);
      }
      if stop { i = 4096; } else { i = i + 1; }
    };
    ffi.safe_ptr_free(safe);
  }
  return Str::from_utf8(bytes);
}

/// OrtStatus protocol roundtrip: create a status (ORT_FAIL + message),
/// read its code and message back, release it. Returns the code
/// (ORT_FAIL == 1) -- proves CreateStatus/GetErrorCode/GetErrorMessage/
/// ReleaseStatus on the live table.
/// Complexity: O(len).
pub fn onnx_status_probe(lib: &OnnxLibrary, message: Str) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: message.len() > 0
{
  unsafe {
    let cs_parent = ort_api_slot(lib.api, ORT_API_CreateStatus);
    let ge_parent = ort_api_slot(lib.api, ORT_API_GetErrorCode);
    let gm_parent = ort_api_slot(lib.api, ORT_API_GetErrorMessage);
    let rs_parent = ort_api_slot(lib.api, ORT_API_ReleaseStatus);
    let cs = cs_parent as fn(Int32, *UInt8) -> Int;
    let st = cs(types.ORT_FAIL as Int32, message.c_str());
    if st == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "CreateStatus returned null" });
    }
    let ge = ge_parent as fn(Int) -> Int32;
    let code = ge(st) as Int;
    let gm = gm_parent as fn(Int) -> *UInt8;
    let mp = gm(st);
    var text = "";
    if (mp as Int) != 0 {
      text = own_c_str(mp as Int);
    }
    let rs = rs_parent as fn(Int) -> Unit;
    rs(st);
    if text != message {
      return Err(OnnxError{
        kind: ONNX_CALL_FAILED;
        message: "status roundtrip text mismatch: got '" + text + "'",
      });
    }
    return Ok(code);
  }
}

/// Local Int-to-Str (lane pattern; no cross-module convert dependency).
/// Complexity: O(digits).
pub fn int_to_str(n: Int) -> Str
  requires: true
{
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
  };
  if neg { return "-" + out; }
  return out;
}
