// XIOM -- xiom.tensorflow.loader: multi-soname TensorFlow C API loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN DECISION (ML/AI sector): **system-library path, not vendored** --
// libtensorflow is reached through its exported TF_* symbols by name; nothing
// is compiled into this package and nothing is linked at build time. The
// loader probes common sonames in order and the suite reports SKIP when none
// is present, so CI without a runtime stays green.
//
// ABI seam (empirically verified on the pinned toolchain, see AUDIT.md):
// the C API passes `TF_Output` / `TF_Input` -- 16-byte {ptr, int} structs --
// BY VALUE, and returns such structs by value. The Windows x64 ABI passes a
// 16-byte aggregate by reference (pointer to a caller temp) while the
// SysV x64 ABI splits it across two integer registers; a struct RETURN uses
// a hidden first pointer argument on Win64 and RAX:RDX on SysV (not
// expressible through an XIOM `fn` pointer). Every wrapper crossing this
// seam therefore branches on the runtime platform and emits the matching
// call shape; the one entry point whose return value cannot be expressed on
// SysV (TF_OperationInput) reports TF_ABI_UNSUPPORTED there and offers the
// portable TF_OperationAllInputs path instead.
//
// Classification:
//   TF_LOAD_ABSENT      -> no candidate soname loaded -> SKIP
//   TF_LOAD_ABI         -> candidate loaded, surface/version unusable -> FAIL
//   TF_CALL_FAILED      -> a call returned a non-OK TF_Status (typed message)
//   TF_ABI_UNSUPPORTED  -> call shape not expressible on this platform ABI

module xiom.tensorflow.loader

use xiom.tensorflow.types;
use xiom.ffi.dl;
use xiom.ffi;
use xiom.io;
use xiom.os.platform;

// =========================================================================
// Declared surface -- the 108 TF C API entry points this package binds.
// tf_surface_names() is the single source of truth for both the load-time
// symbol check and the SPEC.md coverage table; the TF_FN_* constants are
// index-aligned with it.
// =========================================================================

/// The number of declared C API entry points.
/// Complexity: O(1).
pub fn tf_surface_count() -> Int {
  return 109;
}

pub const TF_FN_Version: Int = 0;

pub const TF_FN_NewStatus: Int = 1;
pub const TF_FN_DeleteStatus: Int = 2;
pub const TF_FN_SetStatus: Int = 3;
pub const TF_FN_GetCode: Int = 4;
pub const TF_FN_Message: Int = 5;

pub const TF_FN_NewBufferFromString: Int = 6;
pub const TF_FN_NewBuffer: Int = 7;
pub const TF_FN_DeleteBuffer: Int = 8;

pub const TF_FN_DataTypeSize: Int = 9;

pub const TF_FN_NewTensor: Int = 10;
pub const TF_FN_AllocateTensor: Int = 11;
pub const TF_FN_DeleteTensor: Int = 12;
pub const TF_FN_TensorType: Int = 13;
pub const TF_FN_SetShape: Int = 14;
pub const TF_FN_NumDims: Int = 15;
pub const TF_FN_Dim: Int = 16;
pub const TF_FN_TensorByteSize: Int = 17;
pub const TF_FN_TensorData: Int = 18;
pub const TF_FN_TensorElementCount: Int = 19;
pub const TF_FN_TensorBitcastFrom: Int = 20;
pub const TF_FN_TensorIsAligned: Int = 21;

pub const TF_FN_NewGraph: Int = 22;
pub const TF_FN_DeleteGraph: Int = 23;
pub const TF_FN_GraphSetTensorShape: Int = 24;
pub const TF_FN_GraphGetTensorNumDims: Int = 25;
pub const TF_FN_GraphGetTensorShape: Int = 26;
pub const TF_FN_GraphOperationByName: Int = 27;
pub const TF_FN_GraphNextOperation: Int = 28;
pub const TF_FN_GraphToGraphDef: Int = 29;
pub const TF_FN_GraphImportGraphDef: Int = 30;
pub const TF_FN_GraphImportGraphDefWithResults: Int = 31;
pub const TF_FN_GraphImportGraphDefWithReturnOutputs: Int = 32;

pub const TF_FN_NewImportGraphDefOptions: Int = 33;
pub const TF_FN_DeleteImportGraphDefOptions: Int = 34;
pub const TF_FN_ImportGraphDefOptionsSetPrefix: Int = 35;
pub const TF_FN_ImportGraphDefOptionsSetDefaultDevice: Int = 36;
pub const TF_FN_ImportGraphDefOptionsSetUniquifyNames: Int = 37;
pub const TF_FN_ImportGraphDefOptionsSetUniquifyPrefix: Int = 38;
pub const TF_FN_ImportGraphDefOptionsAddInputMapping: Int = 39;
pub const TF_FN_ImportGraphDefOptionsAddReturnOutput: Int = 40;
pub const TF_FN_ImportGraphDefOptionsAddReturnOperation: Int = 41;
pub const TF_FN_ImportGraphDefOptionsNumReturnOutputs: Int = 42;
pub const TF_FN_ImportGraphDefOptionsNumReturnOperations: Int = 43;

pub const TF_FN_ImportGraphDefResultsReturnOutputs: Int = 44;
pub const TF_FN_ImportGraphDefResultsReturnOperations: Int = 45;
pub const TF_FN_DeleteImportGraphDefResults: Int = 46;

pub const TF_FN_NewOperation: Int = 47;
pub const TF_FN_SetDevice: Int = 48;
pub const TF_FN_AddInput: Int = 49;
pub const TF_FN_AddInputList: Int = 50;
pub const TF_FN_AddControlInput: Int = 51;
pub const TF_FN_ColocateWith: Int = 52;
pub const TF_FN_SetAttrString: Int = 53;
pub const TF_FN_SetAttrInt: Int = 54;
pub const TF_FN_SetAttrIntList: Int = 55;
pub const TF_FN_SetAttrFloat: Int = 56;
pub const TF_FN_SetAttrFloatList: Int = 57;
pub const TF_FN_SetAttrBool: Int = 58;
pub const TF_FN_SetAttrType: Int = 59;
pub const TF_FN_SetAttrShape: Int = 60;
pub const TF_FN_SetAttrTensor: Int = 61;
pub const TF_FN_SetAttrValueProto: Int = 62;
pub const TF_FN_SetAttrPlaceholder: Int = 63;
pub const TF_FN_FinishOperation: Int = 64;
pub const TF_FN_OperationName: Int = 65;
pub const TF_FN_OperationOpType: Int = 66;
pub const TF_FN_OperationDevice: Int = 67;
pub const TF_FN_OperationNumOutputs: Int = 68;
pub const TF_FN_OperationOutputType: Int = 69;
pub const TF_FN_OperationOutputListLength: Int = 70;
pub const TF_FN_OperationNumInputs: Int = 71;
pub const TF_FN_OperationInputType: Int = 72;
pub const TF_FN_OperationInputListLength: Int = 73;
pub const TF_FN_OperationInput: Int = 74;
pub const TF_FN_OperationAllInputs: Int = 75;
pub const TF_FN_OperationNumControlInputs: Int = 76;
pub const TF_FN_OperationGetControlInputs: Int = 77;
pub const TF_FN_OperationNumControlOutputs: Int = 78;
pub const TF_FN_OperationGetControlOutputs: Int = 79;
pub const TF_FN_OperationGetNumAttrs: Int = 80;
pub const TF_FN_OperationGetAttrInt: Int = 81;
pub const TF_FN_OperationGetAttrFloat: Int = 82;
pub const TF_FN_OperationGetAttrBool: Int = 83;
pub const TF_FN_OperationGetAttrType: Int = 84;
pub const TF_FN_OperationGetAttrShape: Int = 85;
pub const TF_FN_OperationGetAttrValueProto: Int = 86;
pub const TF_FN_OperationToNodeDef: Int = 87;

pub const TF_FN_NewSessionOptions: Int = 88;
pub const TF_FN_SetTarget: Int = 89;
pub const TF_FN_SetConfig: Int = 90;
pub const TF_FN_DeleteSessionOptions: Int = 91;
pub const TF_FN_NewSession: Int = 92;
pub const TF_FN_LoadSessionFromSavedModel: Int = 93;
pub const TF_FN_CloseSession: Int = 94;
pub const TF_FN_DeleteSession: Int = 95;
pub const TF_FN_SessionRun: Int = 96;
pub const TF_FN_SessionPRunSetup: Int = 97;
pub const TF_FN_SessionPRun: Int = 98;
pub const TF_FN_DeletePRunHandle: Int = 99;
pub const TF_FN_ExtendSession: Int = 100;
pub const TF_FN_SessionListDevices: Int = 101;
pub const TF_FN_DeleteDeviceList: Int = 102;
pub const TF_FN_DeviceListCount: Int = 103;
pub const TF_FN_DeviceListName: Int = 104;
pub const TF_FN_DeviceListType: Int = 105;
pub const TF_FN_DeviceListMemoryBytes: Int = 106;
pub const TF_FN_DeviceListIncarnation: Int = 107;

/// TF_TensorDefaultAlignment -- appended after the session group so the
/// pinned TF_FN_* values above stay stable; it is the alignment oracle for
/// the borrowed-storage path (see tf_tensor_borrow in xiom.tensorflow.tensor).
pub const TF_FN_TensorDefaultAlignment: Int = 108;

/// The C API symbol names of the declared surface, in TF_FN_* index order
/// (108 entries; the load-time check resolves every one of them).
/// Complexity: O(n).
pub fn tf_surface_names() -> Vec[Str]
  requires: true
{
  var v: Vec[Str] = Vec[Str].new();
  v.push("TF_Version");

  v.push("TF_NewStatus");
  v.push("TF_DeleteStatus");
  v.push("TF_SetStatus");
  v.push("TF_GetCode");
  v.push("TF_Message");

  v.push("TF_NewBufferFromString");
  v.push("TF_NewBuffer");
  v.push("TF_DeleteBuffer");

  v.push("TF_DataTypeSize");

  v.push("TF_NewTensor");
  v.push("TF_AllocateTensor");
  v.push("TF_DeleteTensor");
  v.push("TF_TensorType");
  v.push("TF_SetShape");
  v.push("TF_NumDims");
  v.push("TF_Dim");
  v.push("TF_TensorByteSize");
  v.push("TF_TensorData");
  v.push("TF_TensorElementCount");
  v.push("TF_TensorBitcastFrom");
  v.push("TF_TensorIsAligned");

  v.push("TF_NewGraph");
  v.push("TF_DeleteGraph");
  v.push("TF_GraphSetTensorShape");
  v.push("TF_GraphGetTensorNumDims");
  v.push("TF_GraphGetTensorShape");
  v.push("TF_GraphOperationByName");
  v.push("TF_GraphNextOperation");
  v.push("TF_GraphToGraphDef");
  v.push("TF_GraphImportGraphDef");
  v.push("TF_GraphImportGraphDefWithResults");
  v.push("TF_GraphImportGraphDefWithReturnOutputs");

  v.push("TF_NewImportGraphDefOptions");
  v.push("TF_DeleteImportGraphDefOptions");
  v.push("TF_ImportGraphDefOptionsSetPrefix");
  v.push("TF_ImportGraphDefOptionsSetDefaultDevice");
  v.push("TF_ImportGraphDefOptionsSetUniquifyNames");
  v.push("TF_ImportGraphDefOptionsSetUniquifyPrefix");
  v.push("TF_ImportGraphDefOptionsAddInputMapping");
  v.push("TF_ImportGraphDefOptionsAddReturnOutput");
  v.push("TF_ImportGraphDefOptionsAddReturnOperation");
  v.push("TF_ImportGraphDefOptionsNumReturnOutputs");
  v.push("TF_ImportGraphDefOptionsNumReturnOperations");

  v.push("TF_ImportGraphDefResultsReturnOutputs");
  v.push("TF_ImportGraphDefResultsReturnOperations");
  v.push("TF_DeleteImportGraphDefResults");

  v.push("TF_NewOperation");
  v.push("TF_SetDevice");
  v.push("TF_AddInput");
  v.push("TF_AddInputList");
  v.push("TF_AddControlInput");
  v.push("TF_ColocateWith");
  v.push("TF_SetAttrString");
  v.push("TF_SetAttrInt");
  v.push("TF_SetAttrIntList");
  v.push("TF_SetAttrFloat");
  v.push("TF_SetAttrFloatList");
  v.push("TF_SetAttrBool");
  v.push("TF_SetAttrType");
  v.push("TF_SetAttrShape");
  v.push("TF_SetAttrTensor");
  v.push("TF_SetAttrValueProto");
  v.push("TF_SetAttrPlaceholder");
  v.push("TF_FinishOperation");
  v.push("TF_OperationName");
  v.push("TF_OperationOpType");
  v.push("TF_OperationDevice");
  v.push("TF_OperationNumOutputs");
  v.push("TF_OperationOutputType");
  v.push("TF_OperationOutputListLength");
  v.push("TF_OperationNumInputs");
  v.push("TF_OperationInputType");
  v.push("TF_OperationInputListLength");
  v.push("TF_OperationInput");
  v.push("TF_OperationAllInputs");
  v.push("TF_OperationNumControlInputs");
  v.push("TF_OperationGetControlInputs");
  v.push("TF_OperationNumControlOutputs");
  v.push("TF_OperationGetControlOutputs");
  v.push("TF_OperationGetNumAttrs");
  v.push("TF_OperationGetAttrInt");
  v.push("TF_OperationGetAttrFloat");
  v.push("TF_OperationGetAttrBool");
  v.push("TF_OperationGetAttrType");
  v.push("TF_OperationGetAttrShape");
  v.push("TF_OperationGetAttrValueProto");
  v.push("TF_OperationToNodeDef");

  v.push("TF_NewSessionOptions");
  v.push("TF_SetTarget");
  v.push("TF_SetConfig");
  v.push("TF_DeleteSessionOptions");
  v.push("TF_NewSession");
  v.push("TF_LoadSessionFromSavedModel");
  v.push("TF_CloseSession");
  v.push("TF_DeleteSession");
  v.push("TF_SessionRun");
  v.push("TF_SessionPRunSetup");
  v.push("TF_SessionPRun");
  v.push("TF_DeletePRunHandle");
  v.push("TF_ExtendSession");
  v.push("TF_SessionListDevices");
  v.push("TF_DeleteDeviceList");
  v.push("TF_DeviceListCount");
  v.push("TF_DeviceListName");
  v.push("TF_DeviceListType");
  v.push("TF_DeviceListMemoryBytes");
  v.push("TF_DeviceListIncarnation");
  v.push("TF_TensorDefaultAlignment");
  return v;
}

/// The resolved entry point for TF_FN_* slot `idx` (0 when the library
/// predates the surface -- impossible after a successful `tf_load`).
/// Complexity: O(1).
pub fn tf_fn(lib: &TfLibrary, idx: Int) -> Int
  requires: idx >= 0
{
  if idx >= lib.fns.len() { return 0; }
  return lib.fns[idx];
}

// =========================================================================
// Local helpers
// =========================================================================

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

/// True on the Windows x64 ABI (16-byte aggregates by reference, struct
/// returns via hidden pointer). Complexity: O(1).
pub fn tf_abi_windows() -> Bool
  requires: true
{
  return platform.platform_is_windows();
}

/// Parse the major number of a TensorFlow version string ("2.18.1" -> 2).
/// Returns 0 when unparsable. Complexity: O(len).
pub fn tf_parse_major(version: Str) -> Int
  requires: true
{
  var i = 0;
  var value = 0;
  var digits = 0;
  while i < version.len() {
    let c = version.byte_at(i);
    if c < 48 { break; }
    if c > 57 { break; }
    value = value * 10 + (c - 48);
    digits = digits + 1;
    i = i + 1;
  };
  if digits == 0 { return 0; }
  return value;
}

/// Copy a NUL-terminated foreign string (bounded scan) into an XIOM-owned
/// Str. Required for strings TF owns that die with their owner (status
/// messages, device names come from TF_DeviceListName and are valid until
/// TF_DeleteDeviceList; both are copied here so results never dangle).
/// Complexity: O(len).
pub fn tf_own_c_str(p: Int) -> Str
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

/// Write the two members of a by-value TF_Output/TF_Input image at byte
/// offset `off`: pointer at +0, index (i32, zero-padded) at +8. Used both
/// for the 16-byte call temp and for packed TF_Output arrays (stride 16).
/// Complexity: O(1).
pub fn tf_out16_put(buf: &mut Vec[UInt8], off: Int, oper: Int, index: Int)
  requires: off >= 0
  requires: off + 16 <= buf.len()
{
  unsafe {
    let base = buf.as_mut_ptr() as Int;
    ffi.ptr_write_u64_le((base + off) as *UInt8, oper);
    ffi.ptr_write_u32_le((base + off + 8) as *UInt8, index);
    ffi.ptr_write_u32_le((base + off + 12) as *UInt8, 0);
  }
}

/// Write a 16-byte call temp at offset 0.
/// Complexity: O(1).
pub fn tf_out16_write(buf: &mut Vec[UInt8], oper: Int, index: Int)
  requires: buf.len() >= 16
{
  tf_out16_put(buf, 0, oper, index);
}

/// Read the pointer member of a 16-byte TF_Output/TF_Input image at byte
/// offset `off`. Complexity: O(1).
pub fn tf_out16_oper_at(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: off + 16 <= buf.len()
{
  unsafe {
    return ffi.ptr_read_u64_le((buf.as_mut_ptr() as Int + off) as *UInt8);
  }
}

/// Read the index member of a 16-byte TF_Output/TF_Input image at byte
/// offset `off`. Complexity: O(1).
pub fn tf_out16_index_at(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: off + 16 <= buf.len()
{
  unsafe {
    return ffi.ptr_read_u32_le((buf.as_mut_ptr() as Int + off + 8) as *UInt8);
  }
}

/// The pointer member of a 16-byte TF_Output/TF_Input image.
/// Complexity: O(1).
pub fn tf_out16_oper(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 16
{
  unsafe {
    return ffi.ptr_read_u64_le(buf.as_mut_ptr());
  }
}

/// The index member of a 16-byte TF_Output/TF_Input image.
/// Complexity: O(1).
pub fn tf_out16_index(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 16
{
  unsafe {
    return ffi.ptr_read_u32_le((buf.as_mut_ptr() as Int + 8) as *UInt8);
  }
}

// =========================================================================
// Typed errors + status protocol
// =========================================================================

/// Convert a non-null TF_Status* into a typed error and delete the status.
/// Complexity: O(len).
pub fn tf_status_error(lib: &TfLibrary, status: Int, context: Str) -> TfError
  requires: status != 0
  requires: context.len() > 0
{
  unsafe {
    let gc_parent = tf_fn(lib, TF_FN_GetCode);
    let gm_parent = tf_fn(lib, TF_FN_Message);
    let dsl_parent = tf_fn(lib, TF_FN_DeleteStatus);
    var code = 0;
    var msg = "<no message>";
    if gc_parent != 0 {
      let gc = gc_parent as fn(Int) -> Int32;
      code = gc(status) as Int;
    }
    if gm_parent != 0 {
      let gm = gm_parent as fn(Int) -> Int;
      let mp = gm(status);
      if mp != 0 {
        msg = tf_own_c_str(mp);
      }
    }
    if dsl_parent != 0 {
      let dsl = dsl_parent as fn(Int) -> Unit;
      dsl(status);
    }
    var cname = types.tf_code_name(code);
    if cname.len() == 0 { cname = int_to_str(code); }
    return TfError{
      kind: types.TF_CALL_FAILED;
      message: context + ": " + msg + " [tf " + cname + "]";
    };
  }
}

/// TF_Status protocol check: TF_OK = success; otherwise convert (and delete)
/// the status. Complexity: O(len).
pub fn tf_check(lib: &TfLibrary, status: Int, context: Str) -> Result[Unit, TfError]
  requires: status != 0
  requires: context.len() > 0
{
  unsafe {
    let gc_parent = tf_fn(lib, TF_FN_GetCode);
    if gc_parent == 0 {
      return Err(TfError{ kind: types.TF_CALL_FAILED; message: context + ": TF_GetCode missing" });
    }
    let gc = gc_parent as fn(Int) -> Int32;
    if gc(status) == 0 {
      let dsl_parent = tf_fn(lib, TF_FN_DeleteStatus);
      if dsl_parent != 0 {
        let dsl = dsl_parent as fn(Int) -> Unit;
        dsl(status);
      }
      return Ok(());
    }
    return Err(tf_status_error(lib, status, context));
  }
}

// =========================================================================
// Loader
// =========================================================================

fn fail_load(handle: Int, message: Str) -> Result[TfLibrary, TfError] {
  if handle != 0 {
    let ig = dl.dl_close(handle);
  }
  return Err(TfError{ kind: types.TF_LOAD_ABI; message: message });
}

fn try_load(soname: Str) -> Result[TfLibrary, TfError]
  requires: soname.len() > 0
{
  let h = dl.dl_open(soname);
  if !h.is_ok {
    // Not this candidate: report ABSENT so the caller can try the next one.
    return Err(TfError{ kind: types.TF_LOAD_ABSENT; message: soname + ": " + h.error });
  }
  let handle: Int = h.value;

  let sym = dl.dl_sym(handle, "TF_Version");
  if !sym.is_ok {
    return fail_load(handle, soname + ": TF_Version missing (not libtensorflow?)");
  }
  let version_fn = unsafe { sym.value as fn() -> Int };
  let vp = version_fn();
  if vp == 0 {
    return fail_load(handle, soname + ": TF_Version returned null");
  }
  let version = tf_own_c_str(vp);
  let major = tf_parse_major(version);
  if major == 0 {
    return fail_load(handle, soname + ": unparsable version '" + version + "'");
  }
  if major < types.TF_MIN_MAJOR {
    return fail_load(handle, soname + ": runtime " + version +
      " is older than the declared floor " + int_to_str(types.TF_MIN_MAJOR) + ".x");
  }

  let names = tf_surface_names();
  var fns: Vec[Int] = Vec[Int].new();
  var resolved = 0;
  var first_missing = "";
  var i = 0;
  while i < names.len() {
    let s = dl.dl_sym(handle, names[i]);
    if s.is_ok {
      fns.push(s.value);
      resolved = resolved + 1;
    } else {
      fns.push(0);
      if first_missing.len() == 0 {
        first_missing = names[i];
      }
    }
    i = i + 1;
  };
  if resolved < names.len() {
    return fail_load(handle, soname + ": " + int_to_str(resolved) + "/" +
      int_to_str(names.len()) + " declared entry points present (first missing: " +
      first_missing + ")");
  }

  return Ok(TfLibrary{
    handle: handle;
    soname: soname;
    version: version;
    fns: fns;
    resolved: resolved;
    required: names.len();
  });
}

/// The multi-soname candidate list, in probe order: the optional
/// `XIOM_TENSORFLOW_RUNTIME` override (explicit path, used by the live leg),
/// then the Windows, Linux and macOS sonames.
/// Complexity: O(1).
pub fn tf_load_candidates() -> Vec[Str]
  requires: true
{
  var v: Vec[Str] = Vec[Str].new();
  let override = io.env_var("XIOM_TENSORFLOW_RUNTIME");
  if override.is_some {
    if override.value.len() > 0 {
      v.push(override.value);
    }
  }
  v.push("tensorflow.dll");
  v.push("libtensorflow.so");
  v.push("libtensorflow.so.2");
  v.push("libtensorflow.dylib");
  return v;
}

/// Load an explicitly named build (path or soname). A bogus name yields the
/// deterministic ABSENT classification on any host (the SKIP probe).
/// Complexity: O(load + surface).
pub fn tf_load_named(soname: Str) -> Result[TfLibrary, TfError]
  requires: soname.len() > 0
{
  return try_load(soname);
}

/// Load the first usable candidate from `tf_load_candidates()`. No candidate
/// present -> TF_LOAD_ABSENT (the typed SKIP state); a candidate that loads
/// but fails the surface/version check -> its ABI error is kept while later
/// candidates are still tried.
/// Complexity: O(candidates * surface).
pub fn tf_load() -> Result[TfLibrary, TfError]
  requires: true
{
  let cands = tf_load_candidates();
  var abi: TfError = TfError{ kind: types.TF_LOAD_ABSENT; message: "" };
  var i = 0;
  while i < cands.len() {
    let r = try_load(cands[i]);
    if r.is_ok {
      return Ok(r.value);
    }
    if r.error.kind == types.TF_LOAD_ABI {
      abi = r.error;
    }
    i = i + 1;
  };
  if abi.message.len() > 0 {
    return Err(abi);
  }
  return Err(TfError{
    kind: types.TF_LOAD_ABSENT;
    message: "tensorflow: no runtime candidate loaded (tried " + int_to_str(cands.len()) +
      " candidates: XIOM_TENSORFLOW_RUNTIME, tensorflow.dll, libtensorflow.so, libtensorflow.so.2, libtensorflow.dylib)",
  });
}

/// Release the runtime handle. Complexity: O(1).
pub fn tf_close(lib: &TfLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

/// Version + surface counts of a loaded build (the live-leg probe).
/// Complexity: O(1).
pub fn tf_probe(lib: &TfLibrary) -> TfInfo
  requires: lib.resolved > 0
{
  return TfInfo{
    soname: lib.soname;
    version: lib.version;
    resolved: lib.resolved;
    required: lib.required;
  };
}

// =========================================================================
// ABI seam adapters -- TF_Output/TF_Input by value (see the header comment)
// =========================================================================

/// `TF_AddInput(desc, TF_Output)`: Win64 passes the 16-byte temp by
/// reference; SysV splits it across two registers.
/// Complexity: O(1).
pub fn tf_add_input(lib: &TfLibrary, desc: Int, oper: Int, index: Int)
  requires: desc != 0
  requires: oper != 0
{
  let fp = tf_fn(lib, TF_FN_AddInput);
  if fp == 0 { return; }
  unsafe {
    if tf_abi_windows() {
      var buf = Vec[UInt8].with_len(16);
      tf_out16_write(&mut buf, oper, index);
      let f = fp as fn(Int, Int) -> Unit;
      f(desc, buf.as_mut_ptr() as Int);
      return;
    }
    let f = fp as fn(Int, Int, Int) -> Unit;
    f(desc, oper, index);
  }
}

/// `TF_OperationOutputType(TF_Output) -> TF_DataType`; -1 when the slot is
/// missing (impossible after `tf_load`) or unknown. Complexity: O(1).
pub fn tf_operation_output_type(lib: &TfLibrary, oper: Int, index: Int) -> Int
  requires: oper != 0
{
  let fp = tf_fn(lib, TF_FN_OperationOutputType);
  if fp == 0 { return -1; }
  unsafe {
    if tf_abi_windows() {
      var buf = Vec[UInt8].with_len(16);
      tf_out16_write(&mut buf, oper, index);
      let f = fp as fn(Int) -> Int32;
      return f(buf.as_mut_ptr() as Int) as Int;
    }
    let f = fp as fn(Int, Int) -> Int32;
    return f(oper, index) as Int;
  }
}

/// `TF_OperationInputType(TF_Input) -> TF_DataType`; -1 on missing slot.
/// Complexity: O(1).
pub fn tf_operation_input_type(lib: &TfLibrary, oper: Int, index: Int) -> Int
  requires: oper != 0
{
  let fp = tf_fn(lib, TF_FN_OperationInputType);
  if fp == 0 { return -1; }
  unsafe {
    if tf_abi_windows() {
      var buf = Vec[UInt8].with_len(16);
      tf_out16_write(&mut buf, oper, index);
      let f = fp as fn(Int) -> Int32;
      return f(buf.as_mut_ptr() as Int) as Int;
    }
    let f = fp as fn(Int, Int) -> Int32;
    return f(oper, index) as Int;
  }
}

/// `TF_OperationInput(TF_Input) -> TF_Output`: producer {oper, index} of the
/// given input edge. Win64 struct-return (hidden retbuf) is expressible;
/// the SysV struct-return (RAX:RDX) is not expressible through an XIOM `fn`
/// pointer, so POSIX reports TF_ABI_UNSUPPORTED and callers use
/// `tf_operation_all_inputs` instead.
/// Complexity: O(1).
pub fn tf_operation_input(lib: &TfLibrary, oper: Int, index: Int) -> Result[TfIntList, TfError]
  requires: oper != 0
{
  let fp = tf_fn(lib, TF_FN_OperationInput);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "OperationInput: slot missing" });
  }
  unsafe {
    if !tf_abi_windows() {
      return Err(TfError{
        kind: types.TF_ABI_UNSUPPORTED;
        message: "TF_OperationInput: 16-byte struct return is not expressible on the SysV x64 ABI; use tf_operation_all_inputs (portable)",
      });
    }
    var inbuf = Vec[UInt8].with_len(16);
    tf_out16_write(&mut inbuf, oper, index);
    var ret = Vec[UInt8].with_len(16);
    let f = fp as fn(Int, Int) -> Unit;
    f(ret.as_mut_ptr() as Int, inbuf.as_mut_ptr() as Int);
    var items: Vec[Int] = Vec[Int].new();
    items.push(tf_out16_oper(&ret));
    items.push(tf_out16_index(&ret));
    return Ok(TfIntList{ items: items });
  }
}

/// `TF_GraphGetTensorNumDims(graph, TF_Output, status) -> int`. Returns the
/// adapter's value; callers must consult `status` (the function reports
/// errors through it). -1 when the slot is missing. Complexity: O(1).
pub fn tf_graph_get_tensor_num_dims(lib: &TfLibrary, graph: Int, oper: Int, index: Int, status: Int) -> Int
  requires: graph != 0
  requires: oper != 0
  requires: status != 0
{
  let fp = tf_fn(lib, TF_FN_GraphGetTensorNumDims);
  if fp == 0 { return -1; }
  unsafe {
    if tf_abi_windows() {
      var buf = Vec[UInt8].with_len(16);
      tf_out16_write(&mut buf, oper, index);
      let f = fp as fn(Int, Int, Int) -> Int32;
      return f(graph, buf.as_mut_ptr() as Int, status) as Int;
    }
    let f = fp as fn(Int, Int, Int, Int) -> Int32;
    return f(graph, oper, index, status) as Int;
  }
}

/// `TF_GraphGetTensorShape(graph, TF_Output, dims*, num_dims, status)`.
/// Complexity: O(1).
pub fn tf_graph_get_tensor_shape(lib: &TfLibrary, graph: Int, oper: Int, index: Int, dims: Int, num_dims: Int, status: Int)
  requires: graph != 0
  requires: oper != 0
  requires: dims != 0
  requires: num_dims > 0
  requires: status != 0
{
  let fp = tf_fn(lib, TF_FN_GraphGetTensorShape);
  if fp == 0 { return; }
  unsafe {
    if tf_abi_windows() {
      var buf = Vec[UInt8].with_len(16);
      tf_out16_write(&mut buf, oper, index);
      let f = fp as fn(Int, Int, Int, Int, Int) -> Unit;
      f(graph, buf.as_mut_ptr() as Int, dims, num_dims, status);
      return;
    }
    let f = fp as fn(Int, Int, Int, Int, Int, Int) -> Unit;
    f(graph, oper, index, dims, num_dims, status);
  }
}

/// `TF_GraphSetTensorShape(graph, TF_Output, dims*, num_dims, status)`.
/// Complexity: O(1).
pub fn tf_graph_set_tensor_shape(lib: &TfLibrary, graph: Int, oper: Int, index: Int, dims: Int, num_dims: Int, status: Int)
  requires: graph != 0
  requires: oper != 0
  requires: dims != 0
  requires: num_dims > 0
  requires: status != 0
{
  let fp = tf_fn(lib, TF_FN_GraphSetTensorShape);
  if fp == 0 { return; }
  unsafe {
    if tf_abi_windows() {
      var buf = Vec[UInt8].with_len(16);
      tf_out16_write(&mut buf, oper, index);
      let f = fp as fn(Int, Int, Int, Int, Int) -> Unit;
      f(graph, buf.as_mut_ptr() as Int, dims, num_dims, status);
      return;
    }
    let f = fp as fn(Int, Int, Int, Int, Int, Int) -> Unit;
    f(graph, oper, index, dims, num_dims, status);
  }
}

/// `TF_ImportGraphDefOptionsAddInputMapping(opts, src_name, src_index,
/// TF_Output dst)`. Complexity: O(1).
pub fn tf_opts_add_input_mapping(lib: &TfLibrary, opts: Int, src_name: Str, src_index: Int, dst_oper: Int, dst_index: Int)
  requires: opts != 0
  requires: src_name.len() > 0
  requires: dst_oper != 0
{
  let fp = tf_fn(lib, TF_FN_ImportGraphDefOptionsAddInputMapping);
  if fp == 0 { return; }
  unsafe {
    if tf_abi_windows() {
      var buf = Vec[UInt8].with_len(16);
      tf_out16_write(&mut buf, dst_oper, dst_index);
      let f = fp as fn(Int, Int, Int, Int) -> Unit;
      f(opts, src_name.c_str() as Int, src_index, buf.as_mut_ptr() as Int);
      return;
    }
    let f = fp as fn(Int, Int, Int, Int, Int) -> Unit;
    f(opts, src_name.c_str() as Int, src_index, dst_oper, dst_index);
  }
}
