// XIOM -- xiom.tensorflow.graph: TF_Graph, operations and GraphDef I/O.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// The graph tier of the declared surface: TF_Graph lifecycle + tensor-shape
// introspection, operation construction (TF_NewOperation / TF_AddInput* /
// TF_SetAttr* / TF_FinishOperation), operation introspection (names, types,
// arities, control edges, input edges, attributes), GraphDef export/import
// (TF_GraphToGraphDef / TF_GraphImportGraphDef[*]) and the import-options +
// import-results tiers. All calls go through a loaded TfLibrary (see
// xiom.tensorflow.loader for the by-value TF_Output ABI seam).

module xiom.tensorflow.graph

use xiom.tensorflow.types;
use xiom.tensorflow.loader;
use xiom.ffi;

// =========================================================================
// Local helpers
// =========================================================================

/// Allocate a TF_Status; Err when TF_NewStatus is missing/returns null.
/// Complexity: O(1).
fn status_alloc(lib: &TfLibrary) -> Result[Int, TfError]
  requires: true
{
  let fp = loader.tf_fn(lib, loader.TF_FN_NewStatus);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "status_alloc: TF_NewStatus missing" });
  }
  unsafe {
    let f = fp as fn() -> Int;
    let st = f();
    if st == 0 {
      return Err(TfError{ kind: types.TF_CALL_FAILED; message: "status_alloc: TF_NewStatus returned null" });
    }
    return Ok(st);
  }
}

/// Point a buffer at a Vec[Int] payload (0 for empty vectors).
/// Complexity: O(1).
fn vec_ptr_i(v: &Vec[Int]) -> Int
  requires: true
{
  if v.len() == 0 { return 0; }
  unsafe {
    return v.as_mut_ptr() as Int;
  }
}

/// Point a buffer at a Vec[Float32] payload (0 for empty vectors).
/// Complexity: O(1).
fn vec_ptr_f32(v: &Vec[Float32]) -> Int
  requires: true
{
  if v.len() == 0 { return 0; }
  unsafe {
    return v.as_mut_ptr() as Int;
  }
}

/// Point a buffer at a Vec[UInt8] payload (0 for empty vectors).
/// Complexity: O(1).
fn vec_ptr_u8(v: &Vec[UInt8]) -> Int
  requires: true
{
  if v.len() == 0 { return 0; }
  unsafe {
    return v.as_mut_ptr() as Int;
  }
}

/// Read a heap TF_Buffer* (data @0, length @8) into an XIOM byte list and
/// delete the buffer. Complexity: O(len).
fn take_buffer(lib: &TfLibrary, buf: Int, context: Str) -> Result[TfByteList, TfError]
  requires: buf != 0
  requires: context.len() > 0
{
  var data = 0;
  var len = 0;
  unsafe {
    data = ffi.ptr_read_u64_le(buf as *UInt8);
    len = ffi.ptr_read_u64_le((buf + 8) as *UInt8);
  }
  var items: Vec[UInt8] = Vec[UInt8].new();
  if len > 0 {
    if data == 0 {
      let dbf = loader.tf_fn(lib, loader.TF_FN_DeleteBuffer);
      if dbf != 0 {
        unsafe {
          let f = dbf as fn(Int) -> Unit;
          f(buf);
        }
      }
      return Err(TfError{ kind: types.TF_CALL_FAILED; message: context + ": buffer data is null" });
    }
    var bytes: Vec[UInt8] = Vec[UInt8].with_len(len);
    unsafe {
      ffi.memcpy(bytes.as_mut_ptr(), data as *UInt8, len);
    }
    var i = 0;
    while i < len {
      items.push(bytes[i]);
      i = i + 1;
    };
  }
  let dbf = loader.tf_fn(lib, loader.TF_FN_DeleteBuffer);
  if dbf != 0 {
    unsafe {
      let f = dbf as fn(Int) -> Unit;
      f(buf);
    }
  }
  return Ok(TfByteList{ items: items });
}

// =========================================================================
// Graph lifecycle + tensor-shape introspection
// =========================================================================

/// TF_NewGraph. Complexity: O(1).
pub fn tf_graph_new(lib: &TfLibrary) -> Result[Int, TfError]
  requires: true
{
  let fp = loader.tf_fn(lib, loader.TF_FN_NewGraph);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "graph_new: TF_NewGraph missing" });
  }
  unsafe {
    let f = fp as fn() -> Int;
    let g = f();
    if g == 0 {
      return Err(TfError{ kind: types.TF_CALL_FAILED; message: "graph_new: TF_NewGraph returned null" });
    }
    return Ok(g);
  }
}

/// TF_DeleteGraph (safe on 0). Complexity: O(1).
pub fn tf_graph_delete(lib: &TfLibrary, g: Int)
  requires: true
{
  if g == 0 { return; }
  let fp = loader.tf_fn(lib, loader.TF_FN_DeleteGraph);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int) -> Unit;
    f(g);
  }
}

/// TF_GraphGetTensorNumDims for one output edge; -1 = unknown rank, and
/// errors surface as Err. Complexity: O(1).
pub fn tf_graph_tensor_num_dims(lib: &TfLibrary, g: Int, oper: Int, index: Int) -> Result[Int, TfError]
  requires: g != 0
  requires: oper != 0
{
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  let nd = loader.tf_graph_get_tensor_num_dims(lib, g, oper, index, st);
  let c = loader.tf_check(lib, st, "GraphGetTensorNumDims");
  if !c.is_ok { return Err(c.error); }
  return Ok(nd);
}

/// TF_GraphGetTensorShape for one output edge (empty list = scalar/unknown).
/// Complexity: O(rank).
pub fn tf_graph_tensor_shape(lib: &TfLibrary, g: Int, oper: Int, index: Int) -> Result[TfIntList, TfError]
  requires: g != 0
  requires: oper != 0
{
  let nr = tf_graph_tensor_num_dims(lib, g, oper, index);
  if !nr.is_ok { return Err(nr.error); }
  let nd = nr.value;
  var items: Vec[Int] = Vec[Int].new();
  if nd > 0 {
    var buf: Vec[UInt8] = Vec[UInt8].with_len(nd * 8);
    let sr = status_alloc(lib);
    if !sr.is_ok { return Err(sr.error); }
    let st = sr.value;
    var bptr = 0;
    unsafe {
      bptr = buf.as_mut_ptr() as Int;
    }
    loader.tf_graph_get_tensor_shape(lib, g, oper, index, bptr, nd, st);
    let c = loader.tf_check(lib, st, "GraphGetTensorShape");
    if !c.is_ok { return Err(c.error); }
    var i = 0;
    while i < nd {
      unsafe {
        items.push(ffi.ptr_read_u64_le((bptr + i * 8) as *UInt8));
      }
      i = i + 1;
    };
  };
  return Ok(TfIntList{ items: items });
}

/// TF_GraphSetTensorShape (shape merge). Complexity: O(rank).
pub fn tf_graph_set_tensor_shape(lib: &TfLibrary, g: Int, oper: Int, index: Int, dims: &Vec[Int]) -> Result[Unit, TfError]
  requires: g != 0
  requires: oper != 0
  requires: dims.len() > 0
{
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  let dptr = vec_ptr_i(dims);
  loader.tf_graph_set_tensor_shape(lib, g, oper, index, dptr, dims.len(), st);
  return loader.tf_check(lib, st, "GraphSetTensorShape");
}

/// TF_GraphOperationByName (0 when absent). Complexity: O(len).
pub fn tf_graph_op_by_name(lib: &TfLibrary, g: Int, name: Str) -> Int
  requires: g != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_GraphOperationByName);
  if fp == 0 { return 0; }
  unsafe {
    let f = fp as fn(Int, Int) -> Int;
    return f(g, name.c_str() as Int);
  }
}

/// TF_GraphNextOperation iteration: returns the op at `pos` and advances the
/// pos slot (8 bytes); 0 when the graph is exhausted.
/// Complexity: O(1).
pub fn tf_graph_next_op(lib: &TfLibrary, g: Int, pos: &mut Vec[UInt8]) -> Int
  requires: g != 0
  requires: pos.len() >= 8
{
  let fp = loader.tf_fn(lib, loader.TF_FN_GraphNextOperation);
  if fp == 0 { return 0; }
  unsafe {
    let f = fp as fn(Int, Int) -> Int;
    return f(g, pos.as_mut_ptr() as Int);
  }
}

/// Number of operations in a graph (iterates TF_GraphNextOperation).
/// Complexity: O(ops).
pub fn tf_graph_op_count(lib: &TfLibrary, g: Int) -> Int
  requires: g != 0
{
  var pos = Vec[UInt8].with_len(8);
  var n = 0;
  var op = tf_graph_next_op(lib, g, &mut pos);
  while op != 0 {
    n = n + 1;
    op = tf_graph_next_op(lib, g, &mut pos);
  };
  return n;
}

// =========================================================================
// GraphDef export / import
// =========================================================================

/// TF_GraphToGraphDef: serialize the graph (caller owns the byte list).
/// Complexity: O(graph bytes).
pub fn tf_graph_to_graph_def(lib: &TfLibrary, g: Int) -> Result[TfByteList, TfError]
  requires: g != 0
{
  let nbf = loader.tf_fn(lib, loader.TF_FN_NewBuffer);
  if nbf == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "graph_to_graph_def: TF_NewBuffer missing" });
  }
  var buf = 0;
  unsafe {
    let f = nbf as fn() -> Int;
    buf = f();
  }
  if buf == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "graph_to_graph_def: TF_NewBuffer returned null" });
  }
  let fp = loader.tf_fn(lib, loader.TF_FN_GraphToGraphDef);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "graph_to_graph_def: TF_GraphToGraphDef missing" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int, Int) -> Unit;
    f(g, buf, st);
  }
  let c = loader.tf_check(lib, st, "GraphToGraphDef");
  if !c.is_ok {
    let dbf = loader.tf_fn(lib, loader.TF_FN_DeleteBuffer);
    if dbf != 0 {
      unsafe {
        let f = dbf as fn(Int) -> Unit;
        f(buf);
      }
    }
    return Err(c.error);
  }
  return take_buffer(lib, buf, "GraphToGraphDef");
}

/// TF_NewBufferFromString over an XIOM byte list (TF copies the bytes).
/// Complexity: O(len).
pub fn tf_buffer_from_bytes(lib: &TfLibrary, bytes: &Vec[UInt8]) -> Result[Int, TfError]
  requires: bytes.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_NewBufferFromString);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "buffer_from_bytes: TF_NewBufferFromString missing" });
  }
  let p = vec_ptr_u8(bytes);
  unsafe {
    let f = fp as fn(Int, Int) -> Int;
    let b = f(p, bytes.len());
    if b == 0 {
      return Err(TfError{ kind: types.TF_CALL_FAILED; message: "buffer_from_bytes: TF_NewBufferFromString returned null" });
    }
    return Ok(b);
  }
}

/// TF_DeleteBuffer (safe on 0). Complexity: O(1).
pub fn tf_buffer_delete(lib: &TfLibrary, buf: Int)
  requires: true
{
  if buf == 0 { return; }
  let fp = loader.tf_fn(lib, loader.TF_FN_DeleteBuffer);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int) -> Unit;
    f(buf);
  }
}

/// TF_GraphImportGraphDef with `opts` (0 = default options).
/// Complexity: O(graph bytes).
pub fn tf_graph_import_graph_def(lib: &TfLibrary, g: Int, bytes: &Vec[UInt8], opts: Int) -> Result[Unit, TfError]
  requires: g != 0
  requires: bytes.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_GraphImportGraphDef);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "graph_import: TF_GraphImportGraphDef missing" });
  }
  let br = tf_buffer_from_bytes(lib, bytes);
  if !br.is_ok { return Err(br.error); }
  let buf = br.value;
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int) -> Unit;
    f(g, buf, opts, st);
  }
  let c = loader.tf_check(lib, st, "GraphImportGraphDef");
  tf_buffer_delete(lib, buf);
  return c;
}

/// TF_GraphImportGraphDefWithResults: import and return the
/// TF_ImportGraphDefResults* handle (caller owns; delete with
/// `tf_import_results_delete`). Complexity: O(graph bytes).
pub fn tf_graph_import_graph_def_with_results(lib: &TfLibrary, g: Int, bytes: &Vec[UInt8], opts: Int) -> Result[Int, TfError]
  requires: g != 0
  requires: bytes.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_GraphImportGraphDefWithResults);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "graph_import_results: TF_GraphImportGraphDefWithResults missing" });
  }
  let br = tf_buffer_from_bytes(lib, bytes);
  if !br.is_ok { return Err(br.error); }
  let buf = br.value;
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var res = 0;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int) -> Int;
    res = f(g, buf, opts, st);
  }
  let c = loader.tf_check(lib, st, "GraphImportGraphDefWithResults");
  tf_buffer_delete(lib, buf);
  if !c.is_ok { return Err(c.error); }
  if res == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "graph_import_results: null results" });
  }
  return Ok(res);
}

/// TF_DeleteImportGraphDefResults (safe on 0). Complexity: O(1).
pub fn tf_import_results_delete(lib: &TfLibrary, results: Int)
  requires: true
{
  if results == 0 { return; }
  let fp = loader.tf_fn(lib, loader.TF_FN_DeleteImportGraphDefResults);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int) -> Unit;
    f(results);
  }
}

/// TF_GraphImportGraphDefWithReturnOutputs: import and return the requested
/// outputs (flat [oper, index, ...] list) written by TF into a packed
/// TF_Output array. `num_returns` must equal the number of return outputs
/// added to `opts`. Complexity: O(graph bytes).
pub fn tf_graph_import_graph_def_with_return_outputs(lib: &TfLibrary, g: Int, bytes: &Vec[UInt8], opts: Int, num_returns: Int) -> Result[TfIntList, TfError]
  requires: g != 0
  requires: bytes.len() > 0
  requires: opts != 0
  requires: num_returns > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_GraphImportGraphDefWithReturnOutputs);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "graph_import_return_outputs: TF_GraphImportGraphDefWithReturnOutputs missing" });
  }
  let br = tf_buffer_from_bytes(lib, bytes);
  if !br.is_ok { return Err(br.error); }
  let buf = br.value;
  var outs: Vec[UInt8] = Vec[UInt8].with_len(num_returns * 16);
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int, Int32, Int) -> Unit;
    f(g, buf, opts, outs.as_mut_ptr() as Int, num_returns as Int32, st);
  }
  let c = loader.tf_check(lib, st, "GraphImportGraphDefWithReturnOutputs");
  tf_buffer_delete(lib, buf);
  if !c.is_ok { return Err(c.error); }
  var items: Vec[Int] = Vec[Int].new();
  var i = 0;
  while i < num_returns {
    items.push(loader.tf_out16_oper_at(&outs, i * 16));
    items.push(loader.tf_out16_index_at(&outs, i * 16));
    i = i + 1;
  };
  return Ok(TfIntList{ items: items });
}

/// TF_ImportGraphDefResultsReturnOutputs as a flat [oper, index, ...] list.
/// Complexity: O(n).
pub fn tf_import_results_return_outputs(lib: &TfLibrary, results: Int) -> TfIntList
  requires: results != 0
{
  var items: Vec[Int] = Vec[Int].new();
  let fp = loader.tf_fn(lib, loader.TF_FN_ImportGraphDefResultsReturnOutputs);
  if fp == 0 { return TfIntList{ items: items }; }
  var n_slot = Vec[UInt8].with_len(8);
  var arr_slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = fp as fn(Int, Int, Int) -> Unit;
    f(results, n_slot.as_mut_ptr() as Int, arr_slot.as_mut_ptr() as Int);
    let n = ffi.ptr_read_u32_le(n_slot.as_mut_ptr());
    let arr = ffi.ptr_read_u64_le(arr_slot.as_mut_ptr());
    var i = 0;
    while i < n {
      let off = arr + i * 16;
      items.push(ffi.ptr_read_u64_le(off as *UInt8));
      items.push(ffi.ptr_read_u32_le((off + 8) as *UInt8));
      i = i + 1;
    };
  }
  return TfIntList{ items: items };
}

/// TF_ImportGraphDefResultsReturnOperations as a TF_Operation* list.
/// Complexity: O(n).
pub fn tf_import_results_return_operations(lib: &TfLibrary, results: Int) -> TfIntList
  requires: results != 0
{
  var items: Vec[Int] = Vec[Int].new();
  let fp = loader.tf_fn(lib, loader.TF_FN_ImportGraphDefResultsReturnOperations);
  if fp == 0 { return TfIntList{ items: items }; }
  var n_slot = Vec[UInt8].with_len(8);
  var arr_slot = Vec[UInt8].with_len(8);
  unsafe {
    let f = fp as fn(Int, Int, Int) -> Unit;
    f(results, n_slot.as_mut_ptr() as Int, arr_slot.as_mut_ptr() as Int);
    let n = ffi.ptr_read_u32_le(n_slot.as_mut_ptr());
    let arr = ffi.ptr_read_u64_le(arr_slot.as_mut_ptr());
    var i = 0;
    while i < n {
      items.push(ffi.ptr_read_u64_le((arr + i * 8) as *UInt8));
      i = i + 1;
    };
  }
  return TfIntList{ items: items };
}

// =========================================================================
// Import options
// =========================================================================

/// TF_NewImportGraphDefOptions. Complexity: O(1).
pub fn tf_import_options_new(lib: &TfLibrary) -> Result[Int, TfError]
  requires: true
{
  let fp = loader.tf_fn(lib, loader.TF_FN_NewImportGraphDefOptions);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "import_options_new: TF_NewImportGraphDefOptions missing" });
  }
  unsafe {
    let f = fp as fn() -> Int;
    let o = f();
    if o == 0 {
      return Err(TfError{ kind: types.TF_CALL_FAILED; message: "import_options_new: returned null" });
    }
    return Ok(o);
  }
}

/// TF_DeleteImportGraphDefOptions (safe on 0). Complexity: O(1).
pub fn tf_import_options_delete(lib: &TfLibrary, opts: Int)
  requires: true
{
  if opts == 0 { return; }
  let fp = loader.tf_fn(lib, loader.TF_FN_DeleteImportGraphDefOptions);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int) -> Unit;
    f(opts);
  }
}

/// TF_ImportGraphDefOptionsSetPrefix. Complexity: O(1).
pub fn tf_import_options_set_prefix(lib: &TfLibrary, opts: Int, prefix: Str)
  requires: opts != 0
  requires: prefix.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_ImportGraphDefOptionsSetPrefix);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int, Int) -> Unit;
    f(opts, prefix.c_str() as Int);
  }
}

/// TF_ImportGraphDefOptionsSetDefaultDevice. Complexity: O(1).
pub fn tf_import_options_set_default_device(lib: &TfLibrary, opts: Int, device: Str)
  requires: opts != 0
  requires: device.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_ImportGraphDefOptionsSetDefaultDevice);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int, Int) -> Unit;
    f(opts, device.c_str() as Int);
  }
}

/// TF_ImportGraphDefOptionsSetUniquifyNames. Complexity: O(1).
pub fn tf_import_options_set_uniquify_names(lib: &TfLibrary, opts: Int, v: Bool)
  requires: opts != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_ImportGraphDefOptionsSetUniquifyNames);
  if fp == 0 { return; }
  var b = 0;
  if v { b = 1; }
  unsafe {
    let f = fp as fn(Int, Int) -> Unit;
    f(opts, b);
  }
}

/// TF_ImportGraphDefOptionsSetUniquifyPrefix. Complexity: O(1).
pub fn tf_import_options_set_uniquify_prefix(lib: &TfLibrary, opts: Int, v: Bool)
  requires: opts != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_ImportGraphDefOptionsSetUniquifyPrefix);
  if fp == 0 { return; }
  var b = 0;
  if v { b = 1; }
  unsafe {
    let f = fp as fn(Int, Int) -> Unit;
    f(opts, b);
  }
}

/// TF_ImportGraphDefOptionsAddInputMapping (by-value TF_Output dst via the
/// loader ABI adapter). Complexity: O(1).
pub fn tf_import_options_add_input_mapping(lib: &TfLibrary, opts: Int, src_name: Str, src_index: Int, dst_oper: Int, dst_index: Int)
  requires: opts != 0
  requires: src_name.len() > 0
  requires: dst_oper != 0
{
  loader.tf_opts_add_input_mapping(lib, opts, src_name, src_index, dst_oper, dst_index);
}

/// TF_ImportGraphDefOptionsAddReturnOutput. Complexity: O(1).
pub fn tf_import_options_add_return_output(lib: &TfLibrary, opts: Int, name: Str, index: Int)
  requires: opts != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_ImportGraphDefOptionsAddReturnOutput);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int, Int, Int32) -> Unit;
    f(opts, name.c_str() as Int, index as Int32);
  }
}

/// TF_ImportGraphDefOptionsNumReturnOutputs. Complexity: O(1).
pub fn tf_import_options_num_return_outputs(lib: &TfLibrary, opts: Int) -> Int
  requires: opts != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_ImportGraphDefOptionsNumReturnOutputs);
  if fp == 0 { return -1; }
  unsafe {
    let f = fp as fn(Int) -> Int32;
    return f(opts) as Int;
  }
}

/// TF_ImportGraphDefOptionsAddReturnOperation. Complexity: O(1).
pub fn tf_import_options_add_return_operation(lib: &TfLibrary, opts: Int, name: Str)
  requires: opts != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_ImportGraphDefOptionsAddReturnOperation);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int, Int) -> Unit;
    f(opts, name.c_str() as Int);
  }
}

/// TF_ImportGraphDefOptionsNumReturnOperations. Complexity: O(1).
pub fn tf_import_options_num_return_operations(lib: &TfLibrary, opts: Int) -> Int
  requires: opts != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_ImportGraphDefOptionsNumReturnOperations);
  if fp == 0 { return -1; }
  unsafe {
    let f = fp as fn(Int) -> Int32;
    return f(opts) as Int;
  }
}

// =========================================================================
// Operation construction
// =========================================================================

/// TF_NewOperation (operation description). Complexity: O(1).
pub fn tf_op_new(lib: &TfLibrary, g: Int, op_type: Str, name: Str) -> Result[Int, TfError]
  requires: g != 0
  requires: op_type.len() > 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_NewOperation);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "op_new: TF_NewOperation missing" });
  }
  unsafe {
    let f = fp as fn(Int, Int, Int) -> Int;
    let d = f(g, op_type.c_str() as Int, name.c_str() as Int);
    if d == 0 {
      return Err(TfError{ kind: types.TF_CALL_FAILED; message: "op_new: TF_NewOperation returned null" });
    }
    return Ok(d);
  }
}

/// TF_SetDevice. Complexity: O(1).
pub fn tf_op_set_device(lib: &TfLibrary, desc: Int, device: Str)
  requires: desc != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetDevice);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int, Int) -> Unit;
    f(desc, device.c_str() as Int);
  }
}

/// TF_AddInput (by-value TF_Output via the loader ABI adapter).
/// Complexity: O(1).
pub fn tf_op_add_input(lib: &TfLibrary, desc: Int, oper: Int, index: Int)
  requires: desc != 0
  requires: oper != 0
{
  loader.tf_add_input(lib, desc, oper, index);
}

/// TF_AddInputList over parallel oper/index vectors (packed TF_Output array).
/// Complexity: O(n).
pub fn tf_op_add_input_list(lib: &TfLibrary, desc: Int, opers: &Vec[Int], indices: &Vec[Int])
  requires: desc != 0
  requires: opers.len() > 0
  requires: opers.len() == indices.len()
{
  let fp = loader.tf_fn(lib, loader.TF_FN_AddInputList);
  if fp == 0 { return; }
  var buf: Vec[UInt8] = Vec[UInt8].with_len(opers.len() * 16);
  var i = 0;
  while i < opers.len() {
    loader.tf_out16_put(&mut buf, i * 16, opers[i], indices[i]);
    i = i + 1;
  };
  unsafe {
    let f = fp as fn(Int, Int, Int32) -> Unit;
    f(desc, buf.as_mut_ptr() as Int, opers.len() as Int32);
  }
}

/// TF_AddControlInput. Complexity: O(1).
pub fn tf_op_add_control_input(lib: &TfLibrary, desc: Int, oper: Int)
  requires: desc != 0
  requires: oper != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_AddControlInput);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int, Int) -> Unit;
    f(desc, oper);
  }
}

/// TF_ColocateWith. Complexity: O(1).
pub fn tf_op_colocate_with(lib: &TfLibrary, desc: Int, oper: Int)
  requires: desc != 0
  requires: oper != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_ColocateWith);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int, Int) -> Unit;
    f(desc, oper);
  }
}

/// TF_SetAttrString. Complexity: O(len).
pub fn tf_op_set_attr_string(lib: &TfLibrary, desc: Int, name: Str, value: Str)
  requires: desc != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetAttrString);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int, Int, Int, Int) -> Unit;
    f(desc, name.c_str() as Int, value.c_str() as Int, value.len());
  }
}

/// TF_SetAttrInt. Complexity: O(1).
pub fn tf_op_set_attr_int(lib: &TfLibrary, desc: Int, name: Str, value: Int)
  requires: desc != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetAttrInt);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int, Int, Int) -> Unit;
    f(desc, name.c_str() as Int, value);
  }
}

/// TF_SetAttrIntList. Complexity: O(n).
pub fn tf_op_set_attr_int_list(lib: &TfLibrary, desc: Int, name: Str, values: &Vec[Int])
  requires: desc != 0
  requires: name.len() > 0
  requires: values.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetAttrIntList);
  if fp == 0 { return; }
  let p = vec_ptr_i(values);
  unsafe {
    let f = fp as fn(Int, Int, Int, Int32) -> Unit;
    f(desc, name.c_str() as Int, p, values.len() as Int32);
  }
}

/// TF_SetAttrFloat. Complexity: O(1).
pub fn tf_op_set_attr_float(lib: &TfLibrary, desc: Int, name: Str, value: Float32)
  requires: desc != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetAttrFloat);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int, Int, Float32) -> Unit;
    f(desc, name.c_str() as Int, value);
  }
}

/// TF_SetAttrFloatList. Complexity: O(n).
pub fn tf_op_set_attr_float_list(lib: &TfLibrary, desc: Int, name: Str, values: &Vec[Float32])
  requires: desc != 0
  requires: name.len() > 0
  requires: values.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetAttrFloatList);
  if fp == 0 { return; }
  let p = vec_ptr_f32(values);
  unsafe {
    let f = fp as fn(Int, Int, Int, Int32) -> Unit;
    f(desc, name.c_str() as Int, p, values.len() as Int32);
  }
}

/// TF_SetAttrBool (unsigned char 0/1). Complexity: O(1).
pub fn tf_op_set_attr_bool(lib: &TfLibrary, desc: Int, name: Str, value: Bool)
  requires: desc != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetAttrBool);
  if fp == 0 { return; }
  var b = 0;
  if value { b = 1; }
  unsafe {
    let f = fp as fn(Int, Int, Int) -> Unit;
    f(desc, name.c_str() as Int, b);
  }
}

/// TF_SetAttrType. Complexity: O(1).
pub fn tf_op_set_attr_type(lib: &TfLibrary, desc: Int, name: Str, dtype: Int)
  requires: desc != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetAttrType);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int, Int, Int32) -> Unit;
    f(desc, name.c_str() as Int, dtype as Int32);
  }
}

/// TF_SetAttrShape (num_dims -1 = unknown rank is not reachable from XIOM
/// shapes here; pass a non-empty rank). Complexity: O(rank).
pub fn tf_op_set_attr_shape(lib: &TfLibrary, desc: Int, name: Str, dims: &Vec[Int])
  requires: desc != 0
  requires: name.len() > 0
  requires: dims.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetAttrShape);
  if fp == 0 { return; }
  let p = vec_ptr_i(dims);
  unsafe {
    let f = fp as fn(Int, Int, Int, Int32) -> Unit;
    f(desc, name.c_str() as Int, p, dims.len() as Int32);
  }
}

/// TF_SetAttrTensor (the attr value is copied into the node). Returns the
/// status outcome. Complexity: O(tensor bytes, TF-internal).
pub fn tf_op_set_attr_tensor(lib: &TfLibrary, desc: Int, name: Str, tensor: Int) -> Result[Unit, TfError]
  requires: desc != 0
  requires: name.len() > 0
  requires: tensor != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetAttrTensor);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "set_attr_tensor: TF_SetAttrTensor missing" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int) -> Unit;
    f(desc, name.c_str() as Int, tensor, st);
  }
  return loader.tf_check(lib, st, "SetAttrTensor");
}

/// TF_SetAttrValueProto (serialized AttrValue). Complexity: O(len).
pub fn tf_op_set_attr_value_proto(lib: &TfLibrary, desc: Int, name: Str, bytes: &Vec[UInt8]) -> Result[Unit, TfError]
  requires: desc != 0
  requires: name.len() > 0
  requires: bytes.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetAttrValueProto);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "set_attr_value_proto: TF_SetAttrValueProto missing" });
  }
  let p = vec_ptr_u8(bytes);
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int, Int) -> Unit;
    f(desc, name.c_str() as Int, p, bytes.len(), st);
  }
  return loader.tf_check(lib, st, "SetAttrValueProto");
}

/// TF_SetAttrPlaceholder. Complexity: O(1).
pub fn tf_op_set_attr_placeholder(lib: &TfLibrary, desc: Int, name: Str, placeholder: Str)
  requires: desc != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_SetAttrPlaceholder);
  if fp == 0 { return; }
  unsafe {
    let f = fp as fn(Int, Int, Int) -> Unit;
    f(desc, name.c_str() as Int, placeholder.c_str() as Int);
  }
}

/// TF_FinishOperation: commits the description and returns the operation
/// (the description is consumed in all cases). Complexity: O(1).
pub fn tf_op_finish(lib: &TfLibrary, desc: Int) -> Result[Int, TfError]
  requires: desc != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_FinishOperation);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "op_finish: TF_FinishOperation missing" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var op = 0;
  unsafe {
    let f = fp as fn(Int, Int) -> Int;
    op = f(desc, st);
  }
  let c = loader.tf_check(lib, st, "FinishOperation");
  if !c.is_ok { return Err(c.error); }
  if op == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "op_finish: TF_FinishOperation returned null" });
  }
  return Ok(op);
}

// =========================================================================
// Operation introspection
// =========================================================================

/// TF_OperationName (owned copy). Complexity: O(len).
pub fn tf_op_name(lib: &TfLibrary, oper: Int) -> Str
  requires: oper != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationName);
  if fp == 0 { return ""; }
  unsafe {
    let f = fp as fn(Int) -> Int;
    let p = f(oper);
    if p == 0 { return ""; }
    return loader.tf_own_c_str(p);
  }
}

/// TF_OperationOpType (owned copy). Complexity: O(len).
pub fn tf_op_type(lib: &TfLibrary, oper: Int) -> Str
  requires: oper != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationOpType);
  if fp == 0 { return ""; }
  unsafe {
    let f = fp as fn(Int) -> Int;
    let p = f(oper);
    if p == 0 { return ""; }
    return loader.tf_own_c_str(p);
  }
}

/// TF_OperationDevice (owned copy). Complexity: O(len).
pub fn tf_op_device(lib: &TfLibrary, oper: Int) -> Str
  requires: oper != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationDevice);
  if fp == 0 { return ""; }
  unsafe {
    let f = fp as fn(Int) -> Int;
    let p = f(oper);
    if p == 0 { return ""; }
    return loader.tf_own_c_str(p);
  }
}

/// TF_OperationNumOutputs. Complexity: O(1).
pub fn tf_op_num_outputs(lib: &TfLibrary, oper: Int) -> Int
  requires: oper != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationNumOutputs);
  if fp == 0 { return -1; }
  unsafe {
    let f = fp as fn(Int) -> Int32;
    return f(oper) as Int;
  }
}

/// TF_OperationOutputType for output `index` (ABI adapter).
/// Complexity: O(1).
pub fn tf_op_output_type(lib: &TfLibrary, oper: Int, index: Int) -> Int
  requires: oper != 0
{
  return loader.tf_operation_output_type(lib, oper, index);
}

/// TF_OperationOutputListLength for the named output arg.
/// Complexity: O(1).
pub fn tf_op_output_list_length(lib: &TfLibrary, oper: Int, arg_name: Str) -> Result[Int, TfError]
  requires: oper != 0
  requires: arg_name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationOutputListLength);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "output_list_length: missing" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var n = 0;
  unsafe {
    let f = fp as fn(Int, Int, Int) -> Int32;
    n = f(oper, arg_name.c_str() as Int, st) as Int;
  }
  let c = loader.tf_check(lib, st, "OperationOutputListLength");
  if !c.is_ok { return Err(c.error); }
  return Ok(n);
}

/// TF_OperationNumInputs. Complexity: O(1).
pub fn tf_op_num_inputs(lib: &TfLibrary, oper: Int) -> Int
  requires: oper != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationNumInputs);
  if fp == 0 { return -1; }
  unsafe {
    let f = fp as fn(Int) -> Int32;
    return f(oper) as Int;
  }
}

/// TF_OperationInputType for input `index` (ABI adapter).
/// Complexity: O(1).
pub fn tf_op_input_type(lib: &TfLibrary, oper: Int, index: Int) -> Int
  requires: oper != 0
{
  return loader.tf_operation_input_type(lib, oper, index);
}

/// TF_OperationInputListLength for the named input arg.
/// Complexity: O(1).
pub fn tf_op_input_list_length(lib: &TfLibrary, oper: Int, arg_name: Str) -> Result[Int, TfError]
  requires: oper != 0
  requires: arg_name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationInputListLength);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "input_list_length: missing" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var n = 0;
  unsafe {
    let f = fp as fn(Int, Int, Int) -> Int32;
    n = f(oper, arg_name.c_str() as Int, st) as Int;
  }
  let c = loader.tf_check(lib, st, "OperationInputListLength");
  if !c.is_ok { return Err(c.error); }
  return Ok(n);
}

/// TF_OperationInput: producer {oper, index} of one input edge (ABI seam;
/// POSIX reports TF_ABI_UNSUPPORTED -- use `tf_op_all_inputs` there).
/// Complexity: O(1).
pub fn tf_op_input(lib: &TfLibrary, oper: Int, index: Int) -> Result[TfIntList, TfError]
  requires: oper != 0
{
  return loader.tf_operation_input(lib, oper, index);
}

/// TF_OperationAllInputs as a flat [oper, index, ...] list (portable
/// producer-edge read). Complexity: O(inputs).
pub fn tf_op_all_inputs(lib: &TfLibrary, oper: Int) -> TfIntList
  requires: oper != 0
{
  var items: Vec[Int] = Vec[Int].new();
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationAllInputs);
  if fp == 0 { return TfIntList{ items: items }; }
  let n = tf_op_num_inputs(lib, oper);
  if n <= 0 { return TfIntList{ items: items }; }
  var buf: Vec[UInt8] = Vec[UInt8].with_len(n * 16);
  unsafe {
    let f = fp as fn(Int, Int, Int32) -> Unit;
    f(oper, buf.as_mut_ptr() as Int, n as Int32);
  }
  var i = 0;
  while i < n {
    items.push(loader.tf_out16_oper_at(&buf, i * 16));
    items.push(loader.tf_out16_index_at(&buf, i * 16));
    i = i + 1;
  };
  return TfIntList{ items: items };
}

/// TF_OperationNumControlInputs. Complexity: O(1).
pub fn tf_op_num_control_inputs(lib: &TfLibrary, oper: Int) -> Int
  requires: oper != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationNumControlInputs);
  if fp == 0 { return -1; }
  unsafe {
    let f = fp as fn(Int) -> Int32;
    return f(oper) as Int;
  }
}

/// TF_OperationGetControlInputs. Complexity: O(n).
pub fn tf_op_control_inputs(lib: &TfLibrary, oper: Int) -> TfIntList
  requires: oper != 0
{
  var items: Vec[Int] = Vec[Int].new();
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationGetControlInputs);
  if fp == 0 { return TfIntList{ items: items }; }
  let n = tf_op_num_control_inputs(lib, oper);
  if n <= 0 { return TfIntList{ items: items }; }
  var arr = Vec[Int].with_len(n);
  var got = 0;
  unsafe {
    let f = fp as fn(Int, Int, Int32) -> Int32;
    got = f(oper, arr.as_mut_ptr() as Int, n as Int32) as Int;
  }
  var i = 0;
  while i < got {
    items.push(arr[i]);
    i = i + 1;
  };
  return TfIntList{ items: items };
}

/// TF_OperationNumControlOutputs. Complexity: O(1).
pub fn tf_op_num_control_outputs(lib: &TfLibrary, oper: Int) -> Int
  requires: oper != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationNumControlOutputs);
  if fp == 0 { return -1; }
  unsafe {
    let f = fp as fn(Int) -> Int32;
    return f(oper) as Int;
  }
}

/// TF_OperationGetControlOutputs. Complexity: O(n).
pub fn tf_op_control_outputs(lib: &TfLibrary, oper: Int) -> TfIntList
  requires: oper != 0
{
  var items: Vec[Int] = Vec[Int].new();
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationGetControlOutputs);
  if fp == 0 { return TfIntList{ items: items }; }
  let n = tf_op_num_control_outputs(lib, oper);
  if n <= 0 { return TfIntList{ items: items }; }
  var arr = Vec[Int].with_len(n);
  var got = 0;
  unsafe {
    let f = fp as fn(Int, Int, Int32) -> Int32;
    got = f(oper, arr.as_mut_ptr() as Int, n as Int32) as Int;
  }
  var i = 0;
  while i < got {
    items.push(arr[i]);
    i = i + 1;
  };
  return TfIntList{ items: items };
}

// =========================================================================
// Operation attributes (readers)
// =========================================================================

/// TF_OperationGetNumAttrs. Complexity: O(1).
pub fn tf_op_num_attrs(lib: &TfLibrary, oper: Int) -> Int
  requires: oper != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationGetNumAttrs);
  if fp == 0 { return -1; }
  unsafe {
    let f = fp as fn(Int) -> Int32;
    return f(oper) as Int;
  }
}

/// TF_OperationGetAttrInt (attr must be INT-typed). Complexity: O(1).
pub fn tf_op_get_attr_int(lib: &TfLibrary, oper: Int, name: Str) -> Result[Int, TfError]
  requires: oper != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationGetAttrInt);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "get_attr_int: missing" });
  }
  var slot = Vec[UInt8].with_len(8);
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var v = 0;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int) -> Unit;
    f(oper, name.c_str() as Int, slot.as_mut_ptr() as Int, st);
    v = ffi.ptr_read_u64_le(slot.as_mut_ptr());
  }
  let c = loader.tf_check(lib, st, "OperationGetAttrInt");
  if !c.is_ok { return Err(c.error); }
  return Ok(v);
}

/// TF_OperationGetAttrFloat (attr must be FLOAT-typed). Complexity: O(1).
pub fn tf_op_get_attr_float(lib: &TfLibrary, oper: Int, name: Str) -> Result[Float32, TfError]
  requires: oper != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationGetAttrFloat);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "get_attr_float: missing" });
  }
  var slot: Vec[UInt8] = Vec[UInt8].with_len(4);
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var v: Float32 = 0.0;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int) -> Unit;
    f(oper, name.c_str() as Int, slot.as_mut_ptr() as Int, st);
    let p: *const Float32 = slot.as_mut_ptr() as *const Float32;
    v = *p;
  }
  let c = loader.tf_check(lib, st, "OperationGetAttrFloat");
  if !c.is_ok { return Err(c.error); }
  return Ok(v);
}

/// TF_OperationGetAttrBool (attr must be BOOL-typed). Complexity: O(1).
pub fn tf_op_get_attr_bool(lib: &TfLibrary, oper: Int, name: Str) -> Result[Bool, TfError]
  requires: oper != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationGetAttrBool);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "get_attr_bool: missing" });
  }
  var slot = Vec[UInt8].with_len(1);
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var v = 0;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int) -> Unit;
    f(oper, name.c_str() as Int, slot.as_mut_ptr() as Int, st);
    v = ffi.ptr_read_u8(slot.as_mut_ptr());
  }
  let c = loader.tf_check(lib, st, "OperationGetAttrBool");
  if !c.is_ok { return Err(c.error); }
  return Ok(v != 0);
}

/// TF_OperationGetAttrType (attr must be TYPE-typed). Complexity: O(1).
pub fn tf_op_get_attr_type(lib: &TfLibrary, oper: Int, name: Str) -> Result[Int, TfError]
  requires: oper != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationGetAttrType);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "get_attr_type: missing" });
  }
  var slot = Vec[UInt8].with_len(4);
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  var v = 0;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int) -> Unit;
    f(oper, name.c_str() as Int, slot.as_mut_ptr() as Int, st);
    v = ffi.ptr_read_u32_le(slot.as_mut_ptr());
  }
  let c = loader.tf_check(lib, st, "OperationGetAttrType");
  if !c.is_ok { return Err(c.error); }
  return Ok(v);
}

/// TF_OperationGetAttrShape (attr must be SHAPE-typed; caller passes the
/// number of dims to read, e.g. from the op's known rank).
/// Complexity: O(rank).
pub fn tf_op_get_attr_shape(lib: &TfLibrary, oper: Int, name: Str, num_dims: Int) -> Result[TfIntList, TfError]
  requires: oper != 0
  requires: name.len() > 0
  requires: num_dims >= 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationGetAttrShape);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "get_attr_shape: missing" });
  }
  var items: Vec[Int] = Vec[Int].new();
  if num_dims == 0 { return Ok(TfIntList{ items: items }); }
  var buf: Vec[UInt8] = Vec[UInt8].with_len(num_dims * 8);
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int32, Int) -> Unit;
    f(oper, name.c_str() as Int, buf.as_mut_ptr() as Int, num_dims as Int32, st);
  }
  let c = loader.tf_check(lib, st, "OperationGetAttrShape");
  if !c.is_ok { return Err(c.error); }
  var i = 0;
  while i < num_dims {
    unsafe {
      items.push(ffi.ptr_read_u64_le((buf.as_mut_ptr() as Int + i * 8) as *UInt8));
    }
    i = i + 1;
  };
  return Ok(TfIntList{ items: items });
}

/// TF_OperationGetAttrValueProto (serialized AttrValue).
/// Complexity: O(proto bytes).
pub fn tf_op_get_attr_value_proto(lib: &TfLibrary, oper: Int, name: Str) -> Result[TfByteList, TfError]
  requires: oper != 0
  requires: name.len() > 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationGetAttrValueProto);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "get_attr_value_proto: missing" });
  }
  let nbf = loader.tf_fn(lib, loader.TF_FN_NewBuffer);
  if nbf == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "get_attr_value_proto: TF_NewBuffer missing" });
  }
  var buf = 0;
  unsafe {
    let mkb = nbf as fn() -> Int;
    buf = mkb();
  }
  if buf == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "get_attr_value_proto: null buffer" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int, Int, Int) -> Unit;
    f(oper, name.c_str() as Int, buf, st);
  }
  let c = loader.tf_check(lib, st, "OperationGetAttrValueProto");
  if !c.is_ok {
    tf_buffer_delete(lib, buf);
    return Err(c.error);
  }
  return take_buffer(lib, buf, "OperationGetAttrValueProto");
}

/// TF_OperationToNodeDef (serialized NodeDef).
/// Complexity: O(proto bytes).
pub fn tf_op_to_node_def(lib: &TfLibrary, oper: Int) -> Result[TfByteList, TfError]
  requires: oper != 0
{
  let fp = loader.tf_fn(lib, loader.TF_FN_OperationToNodeDef);
  if fp == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "op_to_node_def: missing" });
  }
  let nbf = loader.tf_fn(lib, loader.TF_FN_NewBuffer);
  if nbf == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "op_to_node_def: TF_NewBuffer missing" });
  }
  var buf = 0;
  unsafe {
    let mkb = nbf as fn() -> Int;
    buf = mkb();
  }
  if buf == 0 {
    return Err(TfError{ kind: types.TF_CALL_FAILED; message: "op_to_node_def: null buffer" });
  }
  let sr = status_alloc(lib);
  if !sr.is_ok { return Err(sr.error); }
  let st = sr.value;
  unsafe {
    let f = fp as fn(Int, Int, Int) -> Unit;
    f(oper, buf, st);
  }
  let c = loader.tf_check(lib, st, "OperationToNodeDef");
  if !c.is_ok {
    tf_buffer_delete(lib, buf);
    return Err(c.error);
  }
  return take_buffer(lib, buf, "OperationToNodeDef");
}
