// XIOM -- xiom.onnx.value: OrtValue tensors, type/shape metadata, memory
// info and allocators.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Oracle: microsoft/onnxruntime v1.31.0 (pinned) -- OrtApi members
// CreateTensorAsOrtValue(48), CreateTensorWithDataAsOrtValue(49),
// IsTensor(50), GetTensorMutableData(51), CastTypeInfoToTensorInfo(55),
// GetOnnxTypeFromTypeInfo(56), GetTensorElementType(60),
// GetDimensionsCount(61), GetDimensions(62), GetSymbolicDimensions(63),
// GetTensorShapeElementCount(64), GetTensorTypeAndShape(65), GetTypeInfo(66),
// GetValueType(67), CreateCpuMemoryInfo(69), MemoryInfoGetName(71),
// MemoryInfoGetId(72), MemoryInfoGetMemType(73), MemoryInfoGetType(74),
// AllocatorAlloc(75), AllocatorFree(76), AllocatorGetInfo(77),
// GetAllocatorWithDefaultOptions(78), GetValue(80), GetValueCount(81),
// Release* (94/96/98/99/131/132), GetTensorMemoryInfo(194).
//
// All out-parameters go through XIOM-owned u64 slots; tensor data buffers are
// copied with `ffi.memcpy` / read through the `ffi` SafePtr reader -- no
// foreign buffer escapes a call site.

module xiom.onnx.value

use xiom.onnx.types;
use xiom.onnx.loader;
use xiom.ffi;

// =========================================================================
// Memory info
// =========================================================================

/// Create a CPU OrtMemoryInfo (name "Cpu", id 0; ORT_ALLOCATOR_DEVICE +
/// ORT_MEM_TYPE_DEFAULT). Free with `onnx_memory_info_free`.
/// Complexity: O(1).
pub fn onnx_memory_info_cpu(lib: &OnnxLibrary) -> Result[Int, OnnxError]
  requires: lib.api != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_CreateCpuMemoryInfo) as fn(Int32, Int32, *UInt8) -> Int;
    let st = f(types.ORT_ALLOCATOR_DEVICE as Int32, types.ORT_MEM_TYPE_DEFAULT as Int32, slot.as_mut_ptr());
    let c = ort_check(lib, st, "CreateCpuMemoryInfo");
    if !c.is_ok { return Err(c.error); }
    let info = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if info == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "CreateCpuMemoryInfo returned null" });
    }
    return Ok(info);
  }
}

/// Release an OrtMemoryInfo.
/// Complexity: O(1).
pub fn onnx_memory_info_free(lib: &OnnxLibrary, info: Int)
  requires: lib.api != 0
{
  if info == 0 { return; }
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ReleaseMemoryInfo) as fn(Int) -> Unit;
    f(info);
  }
}

/// The memory-info name (owned by the info; not freed).
/// Complexity: O(len).
pub fn onnx_memory_info_name(lib: &OnnxLibrary, info: Int) -> Result[Str, OnnxError]
  requires: lib.api != 0
  requires: info != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_MemoryInfoGetName) as fn(Int, *UInt8) -> Int;
    let st = f(info, slot.as_mut_ptr());
    let c = ort_check(lib, st, "MemoryInfoGetName");
    if !c.is_ok { return Err(c.error); }
    let p = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if p == 0 { return Ok(""); }
    return Ok(own_c_str(p));
  }
}

/// The memory-info device id.
/// Complexity: O(1).
pub fn onnx_memory_info_id(lib: &OnnxLibrary, info: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: info != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_MemoryInfoGetId) as fn(Int, *UInt8) -> Int;
    let st = f(info, slot.as_mut_ptr());
    let c = ort_check(lib, st, "MemoryInfoGetId");
    if !c.is_ok { return Err(c.error); }
    return Ok(ffi.ptr_read_u64_le(slot.as_mut_ptr()));
  }
}

/// The OrtMemType of the memory info.
/// Complexity: O(1).
pub fn onnx_memory_info_mem_type(lib: &OnnxLibrary, info: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: info != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_MemoryInfoGetMemType) as fn(Int, *UInt8) -> Int;
    let st = f(info, slot.as_mut_ptr());
    let c = ort_check(lib, st, "MemoryInfoGetMemType");
    if !c.is_ok { return Err(c.error); }
    return Ok(ffi.ptr_read_u64_le(slot.as_mut_ptr()));
  }
}

/// The OrtAllocatorType of the memory info.
/// Complexity: O(1).
pub fn onnx_memory_info_type(lib: &OnnxLibrary, info: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: info != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_MemoryInfoGetType) as fn(Int, *UInt8) -> Int;
    let st = f(info, slot.as_mut_ptr());
    let c = ort_check(lib, st, "MemoryInfoGetType");
    if !c.is_ok { return Err(c.error); }
    return Ok(ffi.ptr_read_u64_le(slot.as_mut_ptr()));
  }
}

// =========================================================================
// Allocators
// =========================================================================

/// The process-wide default CPU allocator (do NOT release this one; it is
/// owned by ORT and returned identically on every call).
/// Complexity: O(1).
pub fn onnx_allocator_default(lib: &OnnxLibrary) -> Result[Int, OnnxError]
  requires: lib.api != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetAllocatorWithDefaultOptions) as fn(*UInt8) -> Int;
    let st = f(slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetAllocatorWithDefaultOptions");
    if !c.is_ok { return Err(c.error); }
    let alloc = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if alloc == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "GetAllocatorWithDefaultOptions returned null" });
    }
    return Ok(alloc);
  }
}

/// Create a session-owned allocator for a memory info (release with
/// `onnx_allocator_release`; it becomes invalid when the session does).
/// Complexity: O(1).
pub fn onnx_allocator_create(lib: &OnnxLibrary, session: Int, mem_info: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: session != 0
  requires: mem_info != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_CreateAllocator) as fn(Int, Int, *UInt8) -> Int;
    let st = f(session, mem_info, slot.as_mut_ptr());
    let c = ort_check(lib, st, "CreateAllocator");
    if !c.is_ok { return Err(c.error); }
    let alloc = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if alloc == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "CreateAllocator returned null" });
    }
    return Ok(alloc);
  }
}

/// Release an allocator created with `onnx_allocator_create`.
/// Complexity: O(1).
pub fn onnx_allocator_release(lib: &OnnxLibrary, alloc: Int)
  requires: lib.api != 0
{
  if alloc == 0 { return; }
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ReleaseAllocator) as fn(Int) -> Unit;
    f(alloc);
  }
}

/// Allocate `size` bytes through an OrtAllocator. Free with
/// `onnx_allocator_free` on the same allocator.
/// Complexity: O(1).
pub fn onnx_allocator_alloc(lib: &OnnxLibrary, alloc: Int, size: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: alloc != 0
  requires: size > 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_AllocatorAlloc) as fn(Int, Int, *UInt8) -> Int;
    let st = f(alloc, size, slot.as_mut_ptr());
    let c = ort_check(lib, st, "AllocatorAlloc");
    if !c.is_ok { return Err(c.error); }
    let p = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if p == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "AllocatorAlloc returned null" });
    }
    return Ok(p);
  }
}

/// Free a block obtained from `onnx_allocator_alloc`.
/// Complexity: O(1).
pub fn onnx_allocator_free(lib: &OnnxLibrary, alloc: Int, p: Int) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: alloc != 0
  requires: p != 0
{
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_AllocatorFree) as fn(Int, Int) -> Int;
    let st = f(alloc, p);
    return ort_check(lib, st, "AllocatorFree");
  }
}

/// The OrtMemoryInfo an allocator allocates from (owned by the allocator).
/// Complexity: O(1).
pub fn onnx_allocator_info(lib: &OnnxLibrary, alloc: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: alloc != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_AllocatorGetInfo) as fn(Int, *UInt8) -> Int;
    let st = f(alloc, slot.as_mut_ptr());
    let c = ort_check(lib, st, "AllocatorGetInfo");
    if !c.is_ok { return Err(c.error); }
    return Ok(ffi.ptr_read_u64_le(slot.as_mut_ptr()));
  }
}

// =========================================================================
// OrtValue tensors
// =========================================================================

/// Create an allocator-owned tensor value (data filled separately; kept
/// zero-initialized by ORT). Free with `onnx_value_free`.
/// Complexity: O(1).
pub fn onnx_value_tensor_new(lib: &OnnxLibrary, alloc: Int, shape: &Vec[Int], dtype: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: alloc != 0
  requires: shape.len() > 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_CreateTensorAsOrtValue) as fn(Int, *UInt8, Int, Int32, *UInt8) -> Int;
    let st = f(alloc, shape.as_mut_ptr() as *UInt8, shape.len(), dtype as Int32, slot.as_mut_ptr());
    let c = ort_check(lib, st, "CreateTensorAsOrtValue");
    if !c.is_ok { return Err(c.error); }
    let v = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if v == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "CreateTensorAsOrtValue returned null" });
    }
    return Ok(v);
  }
}

/// Create a tensor value over a caller-owned buffer (`data` must stay alive
/// until the value is released; ORT does not copy or free it).
/// Complexity: O(1).
pub fn onnx_value_tensor_from_data(lib: &OnnxLibrary, mem_info: Int, data: &Vec[Float32], shape: &Vec[Int], dtype: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: mem_info != 0
  requires: data.len() > 0
  requires: shape.len() > 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_CreateTensorWithDataAsOrtValue) as fn(Int, *UInt8, Int, *UInt8, Int, Int32, *UInt8) -> Int;
    let st = f(mem_info, data.as_mut_ptr() as *UInt8, data.len() * 4,
               shape.as_mut_ptr() as *UInt8, shape.len(), dtype as Int32, slot.as_mut_ptr());
    let c = ort_check(lib, st, "CreateTensorWithDataAsOrtValue");
    if !c.is_ok { return Err(c.error); }
    let v = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if v == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "CreateTensorWithDataAsOrtValue returned null" });
    }
    return Ok(v);
  }
}

/// Whether an OrtValue is a tensor.
/// Complexity: O(1).
pub fn onnx_value_is_tensor(lib: &OnnxLibrary, value: Int) -> Result[Bool, OnnxError]
  requires: lib.api != 0
  requires: value != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_IsTensor) as fn(Int, *UInt8) -> Int;
    let st = f(value, slot.as_mut_ptr());
    let c = ort_check(lib, st, "IsTensor");
    if !c.is_ok { return Err(c.error); }
    return Ok(ffi.ptr_read_u64_le(slot.as_mut_ptr()) != 0);
  }
}

/// Raw data pointer of an allocator-owned tensor value (valid until the
/// value is released). Low-level: prefer `onnx_value_read_f32` /
/// `onnx_value_write_f32` and the borrowed-buffer path in tests.
/// Complexity: O(1).
pub fn onnx_value_data_ptr(lib: &OnnxLibrary, value: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: value != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetTensorMutableData) as fn(Int, *UInt8) -> Int;
    let st = f(value, slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetTensorMutableData");
    if !c.is_ok { return Err(c.error); }
    let p = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if p == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "GetTensorMutableData returned null" });
    }
    return Ok(p);
  }
}

/// Copy Float32 data into a tensor value (little-endian host).
/// Complexity: O(n).
pub fn onnx_value_write_f32(lib: &OnnxLibrary, value: Int, data: &Vec[Float32]) -> Result[Unit, OnnxError]
  requires: lib.api != 0
  requires: value != 0
  requires: data.len() > 0
{
  let pr = onnx_value_data_ptr(lib, value);
  if !pr.is_ok { return Err(pr.error); }
  unsafe {
    ffi.memcpy(pr.value as *UInt8, data.as_mut_ptr() as *UInt8, data.len() * 4);
  }
  return Ok(());
}

/// Copy `count` Float32 elements out of a tensor value.
/// Complexity: O(n).
pub fn onnx_value_read_f32(lib: &OnnxLibrary, value: Int, count: Int) -> Result[OnnxF32List, OnnxError]
  requires: lib.api != 0
  requires: value != 0
  requires: count > 0
{
  let pr = onnx_value_data_ptr(lib, value);
  if !pr.is_ok { return Err(pr.error); }
  var out: Vec[Float32] = Vec[Float32].new();
  unsafe {
    let sp = ffi.safe_ptr_from_raw(pr.value as *UInt8, count * 4);
    if !sp.is_ok {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "read_f32: " + sp.error });
    }
    let safe: SafePtr = sp.value;
    var i = 0;
    var read_failed = false;
    while i < count {
      let r = ffi.safe_ptr_read_f32(&safe, i * 4);
      if r.is_ok {
        out.push(r.value);
      } else {
        read_failed = true;
      }
      i = i + 1;
    };
    ffi.safe_ptr_free(safe);
    if read_failed {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "read_f32: bounds-safe read failed" });
    }
  }
  return Ok(OnnxF32List{ items: out });
}

/// The ONNXType of an OrtValue (ONNX_TYPE_TENSOR == 1 for tensors).
/// Complexity: O(1).
pub fn onnx_value_type(lib: &OnnxLibrary, value: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: value != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetValueType) as fn(Int, *UInt8) -> Int;
    let st = f(value, slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetValueType");
    if !c.is_ok { return Err(c.error); }
    return Ok(ffi.ptr_read_u64_le(slot.as_mut_ptr()));
  }
}

/// Element count of a non-tensor value (maps: 2; sequences: N). Tensors have
/// no count -- ORT returns an INVALID_ARGUMENT status, surfaced as an error.
/// Complexity: O(1).
pub fn onnx_value_count(lib: &OnnxLibrary, value: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: value != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetValueCount) as fn(Int, *UInt8) -> Int;
    let st = f(value, slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetValueCount");
    if !c.is_ok { return Err(c.error); }
    return Ok(ffi.ptr_read_u64_le(slot.as_mut_ptr()));
  }
}

/// Element accessor for map/sequence values (index 0/1 for maps).
/// Complexity: O(1).
pub fn onnx_value_get(lib: &OnnxLibrary, value: Int, index: Int, alloc: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: value != 0
  requires: alloc != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetValue) as fn(Int, Int32, Int, *UInt8) -> Int;
    let st = f(value, index as Int32, alloc, slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetValue");
    if !c.is_ok { return Err(c.error); }
    let v = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if v == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "GetValue returned null" });
    }
    return Ok(v);
  }
}

/// The OrtMemoryInfo a tensor lives in (owned by the value).
/// Complexity: O(1).
pub fn onnx_value_memory_info(lib: &OnnxLibrary, value: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: value != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetTensorMemoryInfo) as fn(Int, *UInt8) -> Int;
    let st = f(value, slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetTensorMemoryInfo");
    if !c.is_ok { return Err(c.error); }
    return Ok(ffi.ptr_read_u64_le(slot.as_mut_ptr()));
  }
}

/// Release an OrtValue.
/// Complexity: O(1).
pub fn onnx_value_free(lib: &OnnxLibrary, value: Int)
  requires: lib.api != 0
{
  if value == 0 { return; }
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ReleaseValue) as fn(Int) -> Unit;
    f(value);
  }
}

// =========================================================================
// Type info / tensor type-and-shape info
// =========================================================================

/// OrtTypeInfo of a value. Free with `onnx_type_info_free`.
/// Complexity: O(1).
pub fn onnx_value_type_info(lib: &OnnxLibrary, value: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: value != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetTypeInfo) as fn(Int, *UInt8) -> Int;
    let st = f(value, slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetTypeInfo");
    if !c.is_ok { return Err(c.error); }
    let ti = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if ti == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "GetTypeInfo returned null" });
    }
    return Ok(ti);
  }
}

/// OrtTensorTypeAndShapeInfo of a value. Free with
/// `onnx_tensor_info_free`.
/// Complexity: O(1).
pub fn onnx_value_tensor_info(lib: &OnnxLibrary, value: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: value != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetTensorTypeAndShape) as fn(Int, *UInt8) -> Int;
    let st = f(value, slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetTensorTypeAndShape");
    if !c.is_ok { return Err(c.error); }
    let ti = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if ti == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "GetTensorTypeAndShape returned null" });
    }
    return Ok(ti);
  }
}

/// The tensor half of a type info (owned by the type info).
/// Complexity: O(1).
pub fn onnx_type_info_tensor(lib: &OnnxLibrary, type_info: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: type_info != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_CastTypeInfoToTensorInfo) as fn(Int, *UInt8) -> Int;
    let st = f(type_info, slot.as_mut_ptr());
    let c = ort_check(lib, st, "CastTypeInfoToTensorInfo");
    if !c.is_ok { return Err(c.error); }
    let ti = ffi.ptr_read_u64_le(slot.as_mut_ptr());
    if ti == 0 {
      return Err(OnnxError{ kind: ONNX_CALL_FAILED; message: "CastTypeInfoToTensorInfo returned null" });
    }
    return Ok(ti);
  }
}

/// The ONNXType of a type info.
/// Complexity: O(1).
pub fn onnx_type_info_onnx_type(lib: &OnnxLibrary, type_info: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: type_info != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetOnnxTypeFromTypeInfo) as fn(Int, *UInt8) -> Int;
    let st = f(type_info, slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetOnnxTypeFromTypeInfo");
    if !c.is_ok { return Err(c.error); }
    return Ok(ffi.ptr_read_u64_le(slot.as_mut_ptr()));
  }
}

/// Release an OrtTypeInfo.
/// Complexity: O(1).
pub fn onnx_type_info_free(lib: &OnnxLibrary, type_info: Int)
  requires: lib.api != 0
{
  if type_info == 0 { return; }
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ReleaseTypeInfo) as fn(Int) -> Unit;
    f(type_info);
  }
}

/// Element data type of a tensor type-and-shape info (ONNXTensorElement-
/// DataType; ORT_DTYPE_FLOAT == 1).
/// Complexity: O(1).
pub fn onnx_tensor_info_element_type(lib: &OnnxLibrary, info: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: info != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetTensorElementType) as fn(Int, *UInt8) -> Int;
    let st = f(info, slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetTensorElementType");
    if !c.is_ok { return Err(c.error); }
    return Ok(ffi.ptr_read_u64_le(slot.as_mut_ptr()));
  }
}

/// Number of tensor dimensions.
/// Complexity: O(1).
pub fn onnx_tensor_info_dims_count(lib: &OnnxLibrary, info: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: info != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetDimensionsCount) as fn(Int, *UInt8) -> Int;
    let st = f(info, slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetDimensionsCount");
    if !c.is_ok { return Err(c.error); }
    return Ok(ffi.ptr_read_u64_le(slot.as_mut_ptr()));
  }
}

/// The tensor dimensions (as Int; -1 marks a dynamic/symbolic axis -- read
/// `onnx_tensor_info_symbolic_dims` for the symbol names).
/// Complexity: O(n).
pub fn onnx_tensor_info_dims(lib: &OnnxLibrary, info: Int) -> Result[Vec[Int], OnnxError]
  requires: lib.api != 0
  requires: info != 0
{
  let cr = onnx_tensor_info_dims_count(lib, info);
  if !cr.is_ok { return Err(cr.error); }
  let n = cr.value;
  var out: Vec[Int] = Vec[Int].new();
  if n == 0 { return Ok(out); }
  var slots = Vec[Int].with_len(n);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetDimensions) as fn(Int, *UInt8, Int) -> Int;
    let st = f(info, slots.as_mut_ptr() as *UInt8, n);
    let c = ort_check(lib, st, "GetDimensions");
    if !c.is_ok { return Err(c.error); }
    var i = 0;
    while i < n {
      out.push(slots[i]);
      i = i + 1;
    };
  }
  return Ok(out);
}

/// The symbolic (dynamic) dimension names; "" for static axes.
/// Complexity: O(n * len).
pub fn onnx_tensor_info_symbolic_dims(lib: &OnnxLibrary, info: Int) -> Result[Vec[Str], OnnxError]
  requires: lib.api != 0
  requires: info != 0
{
  let cr = onnx_tensor_info_dims_count(lib, info);
  if !cr.is_ok { return Err(cr.error); }
  let n = cr.value;
  var out: Vec[Str] = Vec[Str].new();
  if n == 0 { return Ok(out); }
  var slots = Vec[UInt8].with_len(n * 8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetSymbolicDimensions) as fn(Int, *UInt8, Int) -> Int;
    let st = f(info, slots.as_mut_ptr(), n);
    let c = ort_check(lib, st, "GetSymbolicDimensions");
    if !c.is_ok { return Err(c.error); }
    var i = 0;
    while i < n {
      let p = ffi.ptr_read_u64_le((slots.as_mut_ptr() as Int + i * 8) as *UInt8);
      if p == 0 {
        out.push("");
      } else {
        out.push(own_c_str(p));
      }
      i = i + 1;
    };
  }
  return Ok(out);
}

/// Total element count of the tensor shape (product of dimensions; 0 when
/// any axis is dynamic).
/// Complexity: O(1).
pub fn onnx_tensor_info_shape_count(lib: &OnnxLibrary, info: Int) -> Result[Int, OnnxError]
  requires: lib.api != 0
  requires: info != 0
{
  var slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_GetTensorShapeElementCount) as fn(Int, *UInt8) -> Int;
    let st = f(info, slot.as_mut_ptr());
    let c = ort_check(lib, st, "GetTensorShapeElementCount");
    if !c.is_ok { return Err(c.error); }
    return Ok(ffi.ptr_read_u64_le(slot.as_mut_ptr()));
  }
}

/// Release an OrtTensorTypeAndShapeInfo.
/// Complexity: O(1).
pub fn onnx_tensor_info_free(lib: &OnnxLibrary, info: Int)
  requires: lib.api != 0
{
  if info == 0 { return; }
  unsafe {
    let f = ort_api_slot(lib.api, ORT_API_ReleaseTensorTypeAndShapeInfo) as fn(Int) -> Unit;
    f(info);
  }
}
