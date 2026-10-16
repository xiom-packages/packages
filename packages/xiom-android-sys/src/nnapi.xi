// XIOM -- xiom.android-sys: libneuralnetworks (NNAPI) head (A12 surface).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: runtime-load unit for the NNAPI C API
// (android/NeuralNetworks.h of NDK r27b -> libneuralnetworks.so), backed
// by the self-contained bridge `src/nnapi_bridge.c`.  Handles (model /
// compilation / execution / device) cross as opaque Int values; u32
// operand ids and tensor dimensions cross as caller-owned little-endian
// byte slots (B-series discipline; helpers below build the slots).
//
//   core (API 27, ABI-gated, 12 symbols)
//     ANeuralNetworksModel_create/addOperand/addOperation/
//     identifyInputsAndOutputs/setOperandValue/finish/free,
//     ANeuralNetworksCompilation_create/finish/free,
//     ANeuralNetworksExecution_create/free
//   ext (API 29, resolved + reported, not gated, 7 symbols)
//     ANeuralNetworks_getDeviceCount/getDevice,
//     ANeuralNetworksDevice_getName/getType/getVersion/getFeatureLevel,
//     ANeuralNetworks_getRuntimeFeatureLevel
//
// Offline smoke (no device execution): create a model, add operands,
// add an ADD operation, identify inputs/outputs, finish; then a
// compilation create + finish and an execution create/free.  Execution
// itself (setInput/compute) is a documented delta -- this wave proves
// the declared model/compilation/execution lifecycle cluster.
//
// Classification (the suite maps it to markers):
//   NNAPI_LOAD_ABSENT -> SKIP  (runtime missing; CI stays green)
//   NNAPI_LOAD_ABI    -> FAIL  (present but core exports broken)
//   NNAPI_CALL        -> Err   (live call failure, upstream code named)

module xiom.android_sys.nnapi

use xiom.android_sys;

extern "C" {
  fn xnn_load_named(soname: *UInt8) -> Int32;
  fn xnn_load() -> Int32;
  fn xnn_error() -> *UInt8;
  fn xnn_core_missing_count() -> Int32;
  fn xnn_core_missing() -> *UInt8;
  fn xnn_ext_count() -> Int32;
  fn xnn_ext_missing_count() -> Int32;
  fn xnn_ext_missing() -> *UInt8;
  fn xnn_model_create() -> Int64;
  fn xnn_model_add_tensor(model: Int64, code: Int32, dims_le: *UInt8, dim_count: Int32, scale_f32_bits: Int32, zero_point: Int32) -> Int32;
  fn xnn_model_add_operation(model: Int64, op: Int32, inputs_le: *UInt8, input_count: Int32, outputs_le: *UInt8, output_count: Int32) -> Int32;
  fn xnn_model_identify_io(model: Int64, inputs_le: *UInt8, input_count: Int32, outputs_le: *UInt8, output_count: Int32) -> Int32;
  fn xnn_model_set_scalar_i32(model: Int64, index: Int32, value: Int32) -> Int32;
  fn xnn_model_finish(model: Int64) -> Int32;
  fn xnn_model_free(model: Int64);
  fn xnn_compilation_create(model: Int64) -> Int64;
  fn xnn_compilation_finish(compilation: Int64) -> Int32;
  fn xnn_compilation_free(compilation: Int64);
  fn xnn_execution_create(compilation: Int64) -> Int64;
  fn xnn_execution_free(execution: Int64);
  fn xnn_device_count() -> Int32;
  fn xnn_device_name(index: Int32, out: *UInt8, cap: Int32) -> Int32;
  fn xnn_device_type(index: Int32) -> Int32;
  fn xnn_device_version(index: Int32, out: *UInt8, cap: Int32) -> Int32;
  fn xnn_device_feature_level(index: Int32) -> Int32;
  fn xnn_runtime_feature_level() -> Int32;
  fn xnn_error_name(code: Int32) -> *UInt8;
  fn xnn_unload();
}

// =========================================================================
// Identity and classification
// =========================================================================

pub const NNAPI_SONAME: Str = "libneuralnetworks.so";

pub const NNAPI_LOAD_ABSENT: Int = 0; // runtime lib missing -> SKIP
pub const NNAPI_LOAD_ABI: Int = 1;    // present but core exports broken -> FAIL
pub const NNAPI_CALL: Int = 2;        // live call failed (upstream code named)

pub type NnapiRuntime = {
  core_missing: Int;       // API-27 core unresolved count; 0 = full cover
  core_missing_names: Str;
  ext_total: Int;          // API-29 device-query set size (7 at r27b)
  ext_missing: Int;        // unresolved extension count (informational)
  ext_missing_names: Str;
}

// =========================================================================
// ANeuralNetworksOperandCode / OperationType / ErrorCode / DeviceType
// (android/NeuralNetworksTypes.h r27b)
// =========================================================================

pub const ANEURALNETWORKS_FLOAT32: Int = 0;
pub const ANEURALNETWORKS_INT32: Int = 1;
pub const ANEURALNETWORKS_UINT32: Int = 2;
pub const ANEURALNETWORKS_TENSOR_FLOAT32: Int = 3;
pub const ANEURALNETWORKS_TENSOR_INT32: Int = 4;

pub const ANEURALNETWORKS_OP_ADD: Int = 0; // the canonical model-build op
pub const ANEURALNETWORKS_OP_MUL: Int = 18;

// Fused activation codes (the post-inputs activation constant that the
// canonical binary-op signatures require, e.g. ADD(input0, input1, act)).
pub const ANEURALNETWORKS_FUSED_NONE: Int = 0;
pub const ANEURALNETWORKS_FUSED_RELU: Int = 1;
pub const ANEURALNETWORKS_FUSED_RELU1: Int = 2;
pub const ANEURALNETWORKS_FUSED_RELU6: Int = 3;

pub const ANEURALNETWORKS_NO_ERROR: Int = 0;
pub const ANEURALNETWORKS_OUT_OF_MEMORY: Int = 1;
pub const ANEURALNETWORKS_INCOMPLETE: Int = 2;
pub const ANEURALNETWORKS_UNEXPECTED_NULL: Int = 3;
pub const ANEURALNETWORKS_BAD_DATA: Int = 4;
pub const ANEURALNETWORKS_OP_FAILED: Int = 5;
pub const ANEURALNETWORKS_BAD_STATE: Int = 6;
pub const ANEURALNETWORKS_UNMAPPABLE: Int = 7;
pub const ANEURALNETWORKS_OUTPUT_INSUFFICIENT_SIZE: Int = 8;
pub const ANEURALNETWORKS_UNAVAILABLE_DEVICE: Int = 9;
pub const ANEURALNETWORKS_MISSED_DEADLINE_TRANSIENT: Int = 10;
pub const ANEURALNETWORKS_MISSED_DEADLINE_PERSISTENT: Int = 11;
pub const ANEURALNETWORKS_DEAD_OBJECT: Int = 14;

pub const ANEURALNETWORKS_DEVICE_UNKNOWN: Int = 0;
pub const ANEURALNETWORKS_DEVICE_OTHER: Int = 1;
pub const ANEURALNETWORKS_DEVICE_CPU: Int = 2;
pub const ANEURALNETWORKS_DEVICE_GPU: Int = 3;
pub const ANEURALNETWORKS_DEVICE_ACCELERATOR: Int = 4;

/// Human name of an ANeuralNetworksErrorCode value (e.g. "NO_ERROR").
/// Complexity: O(1).
pub fn nn_error_name(code: Int) -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xnn_error_name(code as Int32)); }
}

// =========================================================================
// Probe API
// =========================================================================

/// Probe an explicitly named NNAPI runtime (bogus names exercise the
/// ABSENT/SKIP classification deterministically).
/// Complexity: O(load + export set).
pub fn nnapi_probe_named(soname: Str) -> Result[NnapiRuntime, AndroidSysError]
  requires: soname.len() > 0
{
  let rc = unsafe { xnn_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xnn_error()) };
    if rc == 1 {
      return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABSENT, errno_code: 0, message: msg });
    }
    return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABI, errno_code: 0, message: msg });
  }
  let core_missing = unsafe { xnn_core_missing_count() as Int };
  let core_names = unsafe { Str::from_c_str(xnn_core_missing()) };
  let ext_total = unsafe { xnn_ext_count() as Int };
  let ext_missing = unsafe { xnn_ext_missing_count() as Int };
  let ext_names = unsafe { Str::from_c_str(xnn_ext_missing()) };
  return Ok(NnapiRuntime{
    core_missing: core_missing,
    core_missing_names: core_names,
    ext_total: ext_total,
    ext_missing: ext_missing,
    ext_missing_names: ext_names,
  });
}

/// Probe the default runtime (libneuralnetworks.so).  On Windows the
/// probe classifies ABSENT (SKIP).
/// Complexity: O(load + export set).
pub fn nnapi_probe() -> Result[NnapiRuntime, AndroidSysError]
  requires: true
{
  return nnapi_probe_named(NNAPI_SONAME);
}

/// The last bridge error / missing-export summary (empty when clean).
/// Complexity: O(1).
pub fn nnapi_error() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xnn_error()); }
}

/// Release any runtime handles held by the bridge.  Safe when nothing is
/// loaded.  Handles already handed out are not freed here (callers free
/// models/compilations/executions explicitly).
/// Complexity: O(1).
pub fn nnapi_unload()
  requires: true
{
  unsafe { xnn_unload(); }
}

// =========================================================================
// u32 little-endian slot builders (B-series byte-indexed writes)
// =========================================================================

fn _nn_u32_le(slot: &mut Vec[UInt8], v: Int) {
  slot.push((v & 0xFF) as UInt8);
  slot.push(((v >> 8) & 0xFF) as UInt8);
  slot.push(((v >> 16) & 0xFF) as UInt8);
  slot.push(((v >> 24) & 0xFF) as UInt8);
}

/// Owned slot holding one u32 LE per dimension (tensor shape).
/// Complexity: O(rank).
pub fn nn_dims1(d0: Int) -> Vec[UInt8]
  requires: d0 > 0
{
  var slot: Vec[UInt8] = Vec[UInt8].new();
  _nn_u32_le(&mut slot, d0);
  return slot;
}

/// Two-dimension shape slot.
/// Complexity: O(1).
pub fn nn_dims2(d0: Int, d1: Int) -> Vec[UInt8]
  requires: d0 > 0
  requires: d1 > 0
{
  var slot: Vec[UInt8] = Vec[UInt8].new();
  _nn_u32_le(&mut slot, d0);
  _nn_u32_le(&mut slot, d1);
  return slot;
}

/// Owned slot holding one operand id (u32 LE).
/// Complexity: O(1).
pub fn nn_ids1(a: Int) -> Vec[UInt8]
  requires: a >= 0
{
  var slot: Vec[UInt8] = Vec[UInt8].new();
  _nn_u32_le(&mut slot, a);
  return slot;
}

/// Owned slot holding two operand ids (u32 LE each).
/// Complexity: O(1).
pub fn nn_ids2(a: Int, b: Int) -> Vec[UInt8]
  requires: a >= 0
  requires: b >= 0
{
  var slot: Vec[UInt8] = Vec[UInt8].new();
  _nn_u32_le(&mut slot, a);
  _nn_u32_le(&mut slot, b);
  return slot;
}

/// Owned slot holding three operand ids (u32 LE each) -- the canonical
/// binary-op input arity (x, y, activation).
/// Complexity: O(1).
pub fn nn_ids3(a: Int, b: Int, c: Int) -> Vec[UInt8]
  requires: a >= 0
  requires: b >= 0
  requires: c >= 0
{
  var slot: Vec[UInt8] = Vec[UInt8].new();
  _nn_u32_le(&mut slot, a);
  _nn_u32_le(&mut slot, b);
  _nn_u32_le(&mut slot, c);
  return slot;
}

// =========================================================================
// Functional head (model / compilation / execution lifecycle)
// =========================================================================

/// Create an empty NNAPI model (ANeuralNetworksModel_create).  The
/// handle is an opaque Int; release with `nn_model_free`.
/// Complexity: O(1).
pub fn nn_model_create() -> Result[Int, AndroidSysError]
  requires: true
{
  let h = unsafe { xnn_model_create() as Int };
  if h == 0 {
    return Err(AndroidSysError{ kind: NNAPI_CALL, errno_code: 0, message: nnapi_error() });
  }
  return Ok(h);
}

fn _nn_rc(rc: Int, what: Str) -> Result[Int, AndroidSysError] {
  if rc == -2 {
    return Err(AndroidSysError{ kind: NNAPI_LOAD_ABI, errno_code: 0, message: nnapi_error() });
  }
  if rc < 0 {
    return Err(AndroidSysError{ kind: NNAPI_CALL, errno_code: 0, message: nnapi_error() });
  }
  if rc != ANEURALNETWORKS_NO_ERROR {
    return Err(AndroidSysError{ kind: NNAPI_CALL, errno_code: rc, message: what + " -> " + nn_error_name(rc) });
  }
  return Ok(rc);
}

/// Add a tensor operand (ANeuralNetworksModel_addOperand).  `dims` is an
/// owned u32 LE slot built with `nn_dims1`/`nn_dims2` (rank 0 = scalar);
/// `scale_f32_bits` carries the float scale as its binary32 bit pattern
/// (B-12-safe; ignored for non-quantized types), `zero_point` likewise.
/// Complexity: O(rank).
pub fn nn_model_add_tensor(model: Int, operand_code: Int, dims: &mut Vec[UInt8], scale_f32_bits: Int, zero_point: Int) -> Result[Int, AndroidSysError]
  requires: model != 0
  requires: dims.len() % 4 == 0
{
  let dim_count = dims.len() / 4;
  let rc = unsafe {
    xnn_model_add_tensor(model as Int64, operand_code as Int32, dims.as_mut_ptr(), dim_count as Int32, scale_f32_bits as Int32, zero_point as Int32) as Int
  };
  return _nn_rc(rc, "addOperand");
}

/// Add an operation node (ANeuralNetworksModel_addOperation); `inputs`
/// and `outputs` are owned u32 LE id slots built with `nn_ids1`/`nn_ids2`.
/// Complexity: O(inputs + outputs).
pub fn nn_model_add_operation(model: Int, op: Int, inputs: &mut Vec[UInt8], outputs: &mut Vec[UInt8]) -> Result[Int, AndroidSysError]
  requires: model != 0
  requires: inputs.len() % 4 == 0
  requires: outputs.len() % 4 == 0
{
  let input_count = inputs.len() / 4;
  let output_count = outputs.len() / 4;
  let rc = unsafe {
    xnn_model_add_operation(model as Int64, op as Int32, inputs.as_mut_ptr(), input_count as Int32, outputs.as_mut_ptr(), output_count as Int32) as Int
  };
  return _nn_rc(rc, "addOperation");
}

/// Declare the model inputs and outputs
/// (ANeuralNetworksModel_identifyInputsAndOutputs).
/// Complexity: O(inputs + outputs).
pub fn nn_model_identify_io(model: Int, inputs: &mut Vec[UInt8], outputs: &mut Vec[UInt8]) -> Result[Int, AndroidSysError]
  requires: model != 0
  requires: inputs.len() % 4 == 0
  requires: outputs.len() % 4 == 0
{
  let input_count = inputs.len() / 4;
  let output_count = outputs.len() / 4;
  let rc = unsafe {
    xnn_model_identify_io(model as Int64, inputs.as_mut_ptr(), input_count as Int32, outputs.as_mut_ptr(), output_count as Int32) as Int
  };
  return _nn_rc(rc, "identifyInputsAndOutputs");
}

/// Set an INT32 scalar operand to a constant value
/// (ANeuralNetworksModel_setOperandValue with a 4-byte buffer) -- e.g.
/// the ANEURALNETWORKS_FUSED_NONE activation operand of a canonical
/// binary op.
/// Complexity: O(1).
pub fn nn_model_set_scalar_i32(model: Int, index: Int, value: Int) -> Result[Int, AndroidSysError]
  requires: model != 0
  requires: index >= 0
{
  let rc = unsafe { xnn_model_set_scalar_i32(model as Int64, index as Int32, value as Int32) as Int };
  return _nn_rc(rc, "setOperandValue");
}

/// Finish the model (ANeuralNetworksModel_finish) -- required before a
/// compilation can be created.
/// Complexity: O(model).
pub fn nn_model_finish(model: Int) -> Result[Int, AndroidSysError]
  requires: model != 0
{
  let rc = unsafe { xnn_model_finish(model as Int64) as Int };
  return _nn_rc(rc, "model finish");
}

/// Free a model (ANeuralNetworksModel_free).  Safe on 0.
/// Complexity: O(1).
pub fn nn_model_free(model: Int)
  requires: true
{
  unsafe { xnn_model_free(model as Int64); }
}

/// Create a compilation for a finished model
/// (ANeuralNetworksCompilation_create).
/// Complexity: O(1).
pub fn nn_compilation_create(model: Int) -> Result[Int, AndroidSysError]
  requires: model != 0
{
  let h = unsafe { xnn_compilation_create(model as Int64) as Int };
  if h == 0 {
    return Err(AndroidSysError{ kind: NNAPI_CALL, errno_code: 0, message: nnapi_error() });
  }
  return Ok(h);
}

/// Finish the compilation (ANeuralNetworksCompilation_finish).  This is
/// the device-dependent stage: on hosts without usable drivers the
/// upstream result is returned as Err(CALL, code) with the error name --
/// the documented device-absent path.
/// Complexity: O(device work).
pub fn nn_compilation_finish(compilation: Int) -> Result[Int, AndroidSysError]
  requires: compilation != 0
{
  let rc = unsafe { xnn_compilation_finish(compilation as Int64) as Int };
  return _nn_rc(rc, "compilation finish");
}

/// Free a compilation (ANeuralNetworksCompilation_free).  Safe on 0.
/// Complexity: O(1).
pub fn nn_compilation_free(compilation: Int)
  requires: true
{
  unsafe { xnn_compilation_free(compilation as Int64); }
}

/// Create an execution for a finished compilation
/// (ANeuralNetworksExecution_create).
/// Complexity: O(1).
pub fn nn_execution_create(compilation: Int) -> Result[Int, AndroidSysError]
  requires: compilation != 0
{
  let h = unsafe { xnn_execution_create(compilation as Int64) as Int };
  if h == 0 {
    return Err(AndroidSysError{ kind: NNAPI_CALL, errno_code: 0, message: nnapi_error() });
  }
  return Ok(h);
}

/// Free an execution (ANeuralNetworksExecution_free).  Safe on 0.
/// Complexity: O(1).
pub fn nn_execution_free(execution: Int)
  requires: true
{
  unsafe { xnn_execution_free(execution as Int64); }
}

// =========================================================================
// Device query (API 29 extension set; reported, not gated)
// =========================================================================

/// Number of available NNAPI devices (ANeuralNetworks_getDeviceCount).
/// Err(NNAPI_LOAD_ABI) when the symbol is unresolved (API < 29).
/// Complexity: O(1).
pub fn nn_device_count() -> Result[Int, AndroidSysError]
  requires: true
{
  let rc = unsafe { xnn_device_count() as Int };
  if rc == -2 {
    return Err(AndroidSysError{ kind: NNAPI_LOAD_ABI, errno_code: 0, message: nnapi_error() });
  }
  if rc < 0 {
    return Err(AndroidSysError{ kind: NNAPI_CALL, errno_code: 0, message: nnapi_error() });
  }
  return Ok(rc);
}

/// Name of device `index` (ANeuralNetworksDevice_getName).
/// Complexity: O(name).
pub fn nn_device_name(index: Int) -> Result[Str, AndroidSysError]
  requires: index >= 0
{
  var slot: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 256 { slot.push(0); i = i + 1; }
  let rc = unsafe { xnn_device_name(index as Int32, slot.as_mut_ptr(), 256) as Int };
  if rc == -2 {
    return Err(AndroidSysError{ kind: NNAPI_LOAD_ABI, errno_code: 0, message: nnapi_error() });
  }
  if rc < 0 {
    return Err(AndroidSysError{ kind: NNAPI_CALL, errno_code: 0, message: nnapi_error() });
  }
  var n: Int = rc;
  if n >= 256 { n = 255; }
  return Ok(_nn_str_from_slot(&slot, n));
}

fn _nn_str_from_slot(slot: &Vec[UInt8], n: Int) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n && i < slot.len() {
    let b = slot[i];
    if b == 0 { i = n; } else {
      out.push(b);
      i = i + 1;
    }
  }
  return Str::from_utf8(out);
}

/// Type of device `index` (ANeuralNetworksDevice_getType; see the
/// ANEURALNETWORKS_DEVICE_* constants).
/// Complexity: O(1).
pub fn nn_device_type(index: Int) -> Result[Int, AndroidSysError]
  requires: index >= 0
{
  let rc = unsafe { xnn_device_type(index as Int32) as Int };
  if rc == -2 {
    return Err(AndroidSysError{ kind: NNAPI_LOAD_ABI, errno_code: 0, message: nnapi_error() });
  }
  if rc < 0 {
    return Err(AndroidSysError{ kind: NNAPI_CALL, errno_code: 0, message: nnapi_error() });
  }
  return Ok(rc);
}

/// Version string of device `index` (ANeuralNetworksDevice_getVersion).
/// Complexity: O(version).
pub fn nn_device_version(index: Int) -> Result[Str, AndroidSysError]
  requires: index >= 0
{
  var slot: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < 256 { slot.push(0); i = i + 1; }
  let rc = unsafe { xnn_device_version(index as Int32, slot.as_mut_ptr(), 256) as Int };
  if rc == -2 {
    return Err(AndroidSysError{ kind: NNAPI_LOAD_ABI, errno_code: 0, message: nnapi_error() });
  }
  if rc < 0 {
    return Err(AndroidSysError{ kind: NNAPI_CALL, errno_code: 0, message: nnapi_error() });
  }
  var n: Int = rc;
  if n >= 256 { n = 255; }
  return Ok(_nn_str_from_slot(&slot, n));
}

/// Feature level of device `index`
/// (ANeuralNetworksDevice_getFeatureLevel).
/// Complexity: O(1).
pub fn nn_device_feature_level(index: Int) -> Result[Int, AndroidSysError]
  requires: index >= 0
{
  let rc = unsafe { xnn_device_feature_level(index as Int32) as Int };
  if rc == -2 {
    return Err(AndroidSysError{ kind: NNAPI_LOAD_ABI, errno_code: 0, message: nnapi_error() });
  }
  if rc < 0 {
    return Err(AndroidSysError{ kind: NNAPI_CALL, errno_code: 0, message: nnapi_error() });
  }
  return Ok(rc);
}

/// Runtime feature level (ANeuralNetworks_getRuntimeFeatureLevel).
/// Complexity: O(1).
pub fn nn_runtime_feature_level() -> Result[Int, AndroidSysError]
  requires: true
{
  let rc = unsafe { xnn_runtime_feature_level() as Int };
  if rc == -2 {
    return Err(AndroidSysError{ kind: NNAPI_LOAD_ABI, errno_code: 0, message: nnapi_error() });
  }
  if rc < 0 {
    return Err(AndroidSysError{ kind: NNAPI_CALL, errno_code: 0, message: nnapi_error() });
  }
  return Ok(rc);
}
