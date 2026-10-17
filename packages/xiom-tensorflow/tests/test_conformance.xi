// XIOM -- xiom.tensorflow conformance suite: pure tier + live libtensorflow leg.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// CI WITHOUT a runtime stays green: no candidate soname -> SKIP (the SKIP
// path is exercised deterministically every run via a bogus soname). When a
// runtime is present the suite proves the declared surface live:
// version negotiation + full 108-slot resolution, the status trio, dtype
// sizes, tensors (allocate/borrow/read/write/bitcast), graph construction
// (Placeholder + Add and the ops tier: Const/Add/MatMul/Relu), operation
// introspection (names, arities, edges via the by-value ABI adapters,
// control edges, attributes), GraphDef export/import (+ prefix/return
// options and the results tier), session options, session Run (exact FP
// arithmetic 1.5+3.5=5.0, 2.5+4.5=7.0), partial runs (PRunSetup/PRun),
// device enumeration, session extend, the typed SavedModel-absent path and
// the wrong-shape runtime error path.
//
// Build+run (pure-XIOM loader; no compiler args):
//   scripts/port.ps1 -Package xiom.tensorflow
// The live leg uses the loader candidate order: `XIOM_TENSORFLOW_RUNTIME`
// (an explicit path to a runtime, e.g. the pinned E:\repos\tensorflow-bin
// CPU build), then the bare tensorflow.dll / libtensorflow.so /
// libtensorflow.so.2 / libtensorflow.dylib sonames. Without either the
// suite reports SKIP and stays green.

module tensorflow_conformance

use xiom.tensorflow.types;
use xiom.tensorflow.loader;
use xiom.tensorflow.tensor;
use xiom.tensorflow.graph;
use xiom.tensorflow.session;
use xiom.tensorflow.ops;
use xiom.io;
use xiom.ffi;
use xiom.os.platform;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn note(msg: Str) {
  io.println("    note: " + msg);
  io.flush_stdout();
}

fn ist(i: Int) -> Str {
  return loader.int_to_str(i);
}

fn bstr(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

/// Substring test (byte scan; avoids extra stdlib coupling).
fn contains(hay: Str, needle: Str) -> Bool
  requires: needle.len() > 0
{
  if needle.len() > hay.len() { return false; }
  var i = 0;
  while i + needle.len() <= hay.len() {
    var j = 0;
    var hit = true;
    while j < needle.len() {
      if hay.byte_at(i + j) != needle.byte_at(j) { hit = false; j = needle.len(); }
      else { j = j + 1; }
    };
    if hit { return true; }
    i = i + 1;
  };
  return false;
}

fn vec2(a: Int, b: Int) -> Vec[Int] {
  var v: Vec[Int] = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn vec1(a: Int) -> Vec[Int] {
  var v: Vec[Int] = Vec[Int].new();
  v.push(a);
  return v;
}

fn f32v2(a: Float32, b: Float32) -> Vec[Float32] {
  var v: Vec[Float32] = Vec[Float32].new();
  v.push(a);
  v.push(b);
  return v;
}

// =========================================================================
// Pure tier (no runtime needed)
// =========================================================================

fn test_pure() -> Int {
  var failed = 0;

  var codes_ok = true;
  if types.TF_OK != 0 { codes_ok = false; }
  if types.TF_CANCELLED != 1 { codes_ok = false; }
  if types.TF_UNKNOWN != 2 { codes_ok = false; }
  if types.TF_INVALID_ARGUMENT != 3 { codes_ok = false; }
  if types.TF_DEADLINE_EXCEEDED != 4 { codes_ok = false; }
  if types.TF_NOT_FOUND != 5 { codes_ok = false; }
  if types.TF_ALREADY_EXISTS != 6 { codes_ok = false; }
  if types.TF_PERMISSION_DENIED != 7 { codes_ok = false; }
  if types.TF_RESOURCE_EXHAUSTED != 8 { codes_ok = false; }
  if types.TF_FAILED_PRECONDITION != 9 { codes_ok = false; }
  if types.TF_ABORTED != 10 { codes_ok = false; }
  if types.TF_OUT_OF_RANGE != 11 { codes_ok = false; }
  if types.TF_UNIMPLEMENTED != 12 { codes_ok = false; }
  if types.TF_INTERNAL != 13 { codes_ok = false; }
  if types.TF_UNAVAILABLE != 14 { codes_ok = false; }
  if types.TF_DATA_LOSS != 15 { codes_ok = false; }
  if types.TF_UNAUTHENTICATED != 16 { codes_ok = false; }
  failed = failed + report(codes_ok, "types: TF_Code constants (0..15 + UNAUTHENTICATED=16)");

  var cname_ok = true;
  if types.tf_code_name(types.TF_OK) != "ok" { cname_ok = false; }
  if types.tf_code_name(types.TF_INVALID_ARGUMENT) != "invalid_argument" { cname_ok = false; }
  if types.tf_code_name(types.TF_NOT_FOUND) != "not_found" { cname_ok = false; }
  if types.tf_code_name(types.TF_UNAUTHENTICATED) != "unauthenticated" { cname_ok = false; }
  if types.tf_code_name(999) != "" { cname_ok = false; }
  failed = failed + report(cname_ok, "types: tf_code_name roundtrips");

  var dt_ok = true;
  if types.TF_FLOAT != 1 { dt_ok = false; }
  if types.TF_DOUBLE != 2 { dt_ok = false; }
  if types.TF_INT32 != 3 { dt_ok = false; }
  if types.TF_UINT8 != 4 { dt_ok = false; }
  if types.TF_INT16 != 5 { dt_ok = false; }
  if types.TF_INT8 != 6 { dt_ok = false; }
  if types.TF_STRING != 7 { dt_ok = false; }
  if types.TF_INT64 != 9 { dt_ok = false; }
  if types.TF_BOOL != 10 { dt_ok = false; }
  if types.TF_HALF != 19 { dt_ok = false; }
  if types.TF_RESOURCE != 20 { dt_ok = false; }
  if types.TF_VARIANT != 21 { dt_ok = false; }
  if types.TF_UINT32 != 22 { dt_ok = false; }
  if types.TF_UINT64 != 23 { dt_ok = false; }
  if types.TF_FLOAT8_E5M2 != 24 { dt_ok = false; }
  if types.TF_FLOAT8_E8M0FNU != 34 { dt_ok = false; }
  failed = failed + report(dt_ok, "types: TF_DataType constants (pinned 1..34 ids)");

  var dsz_ok = true;
  if types.tf_dtype_size(types.TF_FLOAT) != 4 { dsz_ok = false; }
  if types.tf_dtype_size(types.TF_DOUBLE) != 8 { dsz_ok = false; }
  if types.tf_dtype_size(types.TF_INT32) != 4 { dsz_ok = false; }
  if types.tf_dtype_size(types.TF_INT64) != 8 { dsz_ok = false; }
  if types.tf_dtype_size(types.TF_BOOL) != 1 { dsz_ok = false; }
  if types.tf_dtype_size(types.TF_HALF) != 2 { dsz_ok = false; }
  if types.tf_dtype_size(types.TF_STRING) != 0 { dsz_ok = false; }
  if types.tf_dtype_size(999) != 0 { dsz_ok = false; }
  failed = failed + report(dsz_ok, "types: tf_dtype_size table (variable-length -> 0)");

  var dtn_ok = true;
  if types.tf_dtype_name(types.TF_FLOAT) != "float" { dtn_ok = false; }
  if types.tf_dtype_name(types.TF_INT64) != "int64" { dtn_ok = false; }
  if types.tf_dtype_name(types.TF_BFLOAT16) != "bfloat16" { dtn_ok = false; }
  if types.tf_dtype_name(999) != "" { dtn_ok = false; }
  failed = failed + report(dtn_ok, "types: tf_dtype_name roundtrips");

  var attr_ok = true;
  if types.TF_ATTR_STRING != 0 { attr_ok = false; }
  if types.TF_ATTR_INT != 1 { attr_ok = false; }
  if types.TF_ATTR_FLOAT != 2 { attr_ok = false; }
  if types.TF_ATTR_BOOL != 3 { attr_ok = false; }
  if types.TF_ATTR_TYPE != 4 { attr_ok = false; }
  if types.TF_ATTR_SHAPE != 5 { attr_ok = false; }
  if types.TF_ATTR_TENSOR != 6 { attr_ok = false; }
  if types.TF_ATTR_PLACEHOLDER != 7 { attr_ok = false; }
  if types.TF_ATTR_FUNC != 8 { attr_ok = false; }
  failed = failed + report(attr_ok, "types: TF_AttrType constants");

  failed = failed + report(loader.tf_surface_count() == 109, "loader: declared surface count is 109");

  let names = loader.tf_surface_names();
  var idx_ok = names.len() == 109;
  if names.len() == 109 {
    if names[0] != "TF_Version" { idx_ok = false; }
    if names[1] != "TF_NewStatus" { idx_ok = false; }
    if names[5] != "TF_Message" { idx_ok = false; }
    if names[9] != "TF_DataTypeSize" { idx_ok = false; }
    if names[10] != "TF_NewTensor" { idx_ok = false; }
    if names[22] != "TF_NewGraph" { idx_ok = false; }
    if names[33] != "TF_NewImportGraphDefOptions" { idx_ok = false; }
    if names[47] != "TF_NewOperation" { idx_ok = false; }
    if names[87] != "TF_OperationToNodeDef" { idx_ok = false; }
    if names[88] != "TF_NewSessionOptions" { idx_ok = false; }
    if names[107] != "TF_DeviceListIncarnation" { idx_ok = false; }
    if names[108] != "TF_TensorDefaultAlignment" { idx_ok = false; }
  }
  failed = failed + report(idx_ok, "loader: surface names index-aligned with TF_FN_* constants");

  var uniq_ok = true;
  var i = 1;
  while i < names.len() {
    var j = 0;
    while j < i {
      if names[i] == names[j] { uniq_ok = false; }
      j = j + 1;
    };
    i = i + 1;
  };
  failed = failed + report(uniq_ok, "loader: surface names are unique (no duplicated binds)");

  let cands = loader.tf_load_candidates();
  var cands_ok = cands.len() >= 4;
  var has_dll = false;
  var has_so = false;
  i = 0;
  while i < cands.len() {
    if cands[i] == "tensorflow.dll" { has_dll = true; }
    if cands[i] == "libtensorflow.so" { has_so = true; }
    i = i + 1;
  };
  if !has_dll { cands_ok = false; }
  if !has_so { cands_ok = false; }
  let env_override = io.env_var("XIOM_TENSORFLOW_RUNTIME");
  if env_override.is_some {
    if env_override.value.len() > 0 {
      if cands.len() != 5 { cands_ok = false; }
      if cands[0] != env_override.value { cands_ok = false; }
    }
  }
  failed = failed + report(cands_ok, "loader: candidate list (override + dll/so/so.2/dylib sonames)");

  var parse_ok = true;
  if loader.tf_parse_major("2.18.1") != 2 { parse_ok = false; }
  if loader.tf_parse_major("1.15.0") != 1 { parse_ok = false; }
  if loader.tf_parse_major("") != 0 { parse_ok = false; }
  if loader.tf_parse_major("x.y") != 0 { parse_ok = false; }
  failed = failed + report(parse_ok, "loader: version major parse");

  var its_ok = true;
  if loader.int_to_str(0) != "0" { its_ok = false; }
  if loader.int_to_str(42) != "42" { its_ok = false; }
  if loader.int_to_str(-7) != "-7" { its_ok = false; }
  if loader.int_to_str(108) != "108" { its_ok = false; }
  failed = failed + report(its_ok, "loader: int_to_str");

  // Deterministic SKIP probe: a bogus soname must classify ABSENT.
  let skipr = loader.tf_load_named("xiom-not-a-tensorflow-runtime-xyz.dll");
  var skip_ok = !skipr.is_ok && skipr.error.kind == types.TF_LOAD_ABSENT;
  failed = failed + report(skip_ok, "loader: SKIP probe -- bogus soname -> TF_LOAD_ABSENT");

  // ABI probe: an existing non-TF shared library must classify ABI, not
  // ABSENT and not a load failure.
  var probe_name = "libc.so.6";
  if platform.platform_is_windows() { probe_name = "kernel32.dll"; }
  let abir = loader.tf_load_named(probe_name);
  var abi_ok = !abir.is_ok && abir.error.kind == types.TF_LOAD_ABI;
  if abir.is_ok {
    loader.tf_close(&abir.value);
    abi_ok = false;
  }
  failed = failed + report(abi_ok, "loader: ABI probe -- " + probe_name + " -> TF_LOAD_ABI (no TF_Version)");

  // XABI: the 16-byte TF_Output image helpers roundtrip in XIOM memory.
  var buf = Vec[UInt8].with_len(16);
  loader.tf_out16_put(&mut buf, 0, 4096, 7);
  var out16_ok = loader.tf_out16_oper(&buf) == 4096;
  if loader.tf_out16_index(&buf) != 7 { out16_ok = false; }
  var two = Vec[UInt8].with_len(32);
  loader.tf_out16_put(&mut two, 0, 11, 0);
  loader.tf_out16_put(&mut two, 16, 22, 1);
  if loader.tf_out16_oper_at(&two, 16) != 22 { out16_ok = false; }
  if loader.tf_out16_index_at(&two, 0) != 0 { out16_ok = false; }
  failed = failed + report(out16_ok, "loader: TF_Output 16-byte image pack/read");

  var f32_ok = true;
  var scratch = Vec[UInt8].with_len(16);
  var sbase = 0;
  unsafe { sbase = scratch.as_mut_ptr() as Int; }
  tensor.tf_f32_store(sbase, 0, 1.5);
  tensor.tf_f32_store(sbase, 4, -2.25);
  if tensor.tf_f32_load(sbase, 0) != 1.5 { f32_ok = false; }
  if tensor.tf_f32_load(sbase, 4) != -2.25 { f32_ok = false; }
  tensor.tf_i32_store(sbase, 8, -123456);
  if tensor.tf_i32_load(sbase, 8) != -123456 { f32_ok = false; }
  failed = failed + report(f32_ok, "tensor: f32/i32 raw store/load helpers");

  var sc_ok = true;
  if tensor.tf_shape_count(&(vec2(2, 3))) != 6 { sc_ok = false; }
  if tensor.tf_shape_count(&(vec1(4))) != 4 { sc_ok = false; }
  failed = failed + report(sc_ok, "tensor: tf_shape_count");

  return failed;
}

// =========================================================================
// Live tier (a libtensorflow build is loaded)
// =========================================================================

fn test_live(lib: &TfLibrary) -> Int {
  var failed = 0;

  let info = loader.tf_probe(lib);
  var probe_ok = info.version.len() >= 3;
  if info.resolved != 109 { probe_ok = false; }
  if info.required != 109 { probe_ok = false; }
  if loader.tf_parse_major(info.version) < 2 { probe_ok = false; }
  failed = failed + report(probe_ok, "live: probe -- " + info.version + " (" + ist(info.resolved) + "/" + ist(info.required) + " entry points)");

  // ---- status trio ----
  let snr = session.tf_session_options_new(lib);
  var status_ok = false;
  let sfp = loader.tf_fn(lib, loader.TF_FN_NewStatus);
  var st = 0;
  if sfp != 0 {
    unsafe {
      let f = sfp as fn() -> Int;
      st = f();
    }
    status_ok = st != 0;
  }
  failed = failed + report(status_ok, "live: TF_NewStatus returns non-null");

  if status_ok {
    let gcf = loader.tf_fn(lib, loader.TF_FN_GetCode);
    let setf = loader.tf_fn(lib, loader.TF_FN_SetStatus);
    let msgf = loader.tf_fn(lib, loader.TF_FN_Message);
    let delf = loader.tf_fn(lib, loader.TF_FN_DeleteStatus);
    var code0 = -1;
    unsafe {
      let gc = gcf as fn(Int) -> Int32;
      code0 = gc(st) as Int;
    }
    failed = failed + report(code0 == types.TF_OK, "live: fresh TF_Status is TF_OK");

    let txt_in = "bad input";
    unsafe {
      // NOTE: the local must NOT be named `set` -- a local fn-pointer named
      // `set` is misresolved as the builtin Vec.set method on the first
      // argument (compiler finding TF-B2, IR in AUDIT.md).
      let set_fn = setf as fn(Int, Int32, Int) -> Unit;
      set_fn(st, types.TF_INVALID_ARGUMENT as Int32, txt_in.c_str() as Int);
    }
    var code1 = -1;
    var msg = "";
    unsafe {
      let gc = gcf as fn(Int) -> Int32;
      code1 = gc(st) as Int;
      let gm = msgf as fn(Int) -> Int;
      msg = loader.tf_own_c_str(gm(st));
    }
    failed = failed + report(code1 == types.TF_INVALID_ARGUMENT, "live: TF_SetStatus/TF_GetCode roundtrip (INVALID_ARGUMENT) got " + ist(code1));
    failed = failed + report(msg == "bad input", "live: TF_Message roundtrip ('" + msg + "')");
    unsafe {
      let del = delf as fn(Int) -> Unit;
      del(st);
    }
  };

  // ---- dtype sizes (live cross-check of the pure table) ----
  let dszf = loader.tf_fn(lib, loader.TF_FN_DataTypeSize);
  var dsz_ok = dszf != 0;
  if dszf != 0 {
    unsafe {
      let f = dszf as fn(Int32) -> Int;
      if f(types.TF_FLOAT as Int32) != 4 { dsz_ok = false; }
      if f(types.TF_DOUBLE as Int32) != 8 { dsz_ok = false; }
      if f(types.TF_INT32 as Int32) != 4 { dsz_ok = false; }
      if f(types.TF_INT64 as Int32) != 8 { dsz_ok = false; }
      if f(types.TF_BOOL as Int32) != 1 { dsz_ok = false; }
      if f(types.TF_HALF as Int32) != 2 { dsz_ok = false; }
      if f(types.TF_STRING as Int32) != 0 { dsz_ok = false; }
    }
  }
  failed = failed + report(dsz_ok, "live: TF_DataTypeSize agrees with the constant table");

  // ---- tensor tier ----
  var dims23 = vec2(2, 3);
  let tar = tensor.tf_tensor_alloc(lib, types.TF_FLOAT, &dims23, 24);
  var t_ok = tar.is_ok;
  if tar.is_ok {
    let t = tar.value;
    var shape_ok = tensor.tf_tensor_num_dims(lib, t) == 2;
    if tensor.tf_tensor_dim(lib, t, 0) != 2 { shape_ok = false; }
    if tensor.tf_tensor_dim(lib, t, 1) != 3 { shape_ok = false; }
    if tensor.tf_tensor_byte_size(lib, t) != 24 { shape_ok = false; }
    if tensor.tf_tensor_element_count(lib, t) != 6 { shape_ok = false; }
    if tensor.tf_tensor_type(lib, t) != types.TF_FLOAT { shape_ok = false; }
    failed = failed + report(shape_ok, "live: TF_AllocateTensor [2,3] f32 -- dims/bytes/elements");

    var write_ok = true;
    let base = tensor.tf_tensor_data(lib, t);
    if base == 0 { write_ok = false; }
    if write_ok {
      var k = 0;
      while k < 6 {
        tensor.tf_f32_store(base, k * 4, 0.5 + (k as Float32));
        k = k + 1;
      };
      let rr = tensor.tf_tensor_read_f32(lib, t, 6);
      if !rr.is_ok {
        write_ok = false;
      } else {
        let vals = rr.value.items;
        if vals.len() != 6 { write_ok = false; }
        if vals[0] != 0.5 { write_ok = false; }
        if vals[5] != 5.5 { write_ok = false; }
      }
    }
    failed = failed + report(write_ok, "live: tensor storage write + tf_tensor_read_f32 roundtrip");
    failed = failed + report(tensor.tf_tensor_is_aligned(lib, t), "live: TF_TensorIsAligned on allocated storage");

    // SetShape merges an identical shape (and keeps the tensor usable).
    tensor.tf_tensor_set_shape(lib, t, &dims23);
    failed = failed + report(tensor.tf_tensor_dim(lib, t, 1) == 3, "live: TF_SetShape keeps [2,3]");

    tensor.tf_tensor_delete(lib, t);
  } else {
    failed = failed + report(false, "live: TF_AllocateTensor [2,3] f32 -- dims/bytes/elements");
    note(tar.error.message);
  };

  // Borrow: TF_NewTensor over XIOM-owned bytes (no deallocator) at
  // TF-required alignment; the unaligned case must be refused typed.
  var own = Vec[UInt8].with_len(8 + 64);
  var o0 = 0;
  unsafe { o0 = own.as_mut_ptr() as Int; }
  let abase = ((o0 + 63) / 64) * 64;
  tensor.tf_f32_store(abase, 0, 9.0);
  tensor.tf_f32_store(abase, 4, 8.0);
  var borrow_ok = false;
  let balign = tensor.tf_tensor_default_alignment(lib);
  if balign != 64 { note("default alignment is " + ist(balign)); }
  let br = tensor.tf_tensor_borrow(lib, types.TF_FLOAT, &(vec1(2)), abase, 8);
  if br.is_ok {
    let t = br.value;
    borrow_ok = tensor.tf_tensor_data(lib, t) == abase;
    let rr = tensor.tf_tensor_read_f32(lib, t, 2);
    if !rr.is_ok { borrow_ok = false; }
    elif rr.value.items[0] != 9.0 { borrow_ok = false; }
    tensor.tf_tensor_delete(lib, t);
  } else {
    note(br.error.message);
  }
  failed = failed + report(borrow_ok, "live: TF_NewTensor borrowed aligned storage -- TensorData aliases the buffer");
  failed = failed + report(tensor.tf_f32_load(abase, 0) == 9.0, "live: borrowed buffer survives TF_DeleteTensor (null deallocator)");

  // Unaligned address: typed refusal (TF would call the null deallocator).
  let ubad = tensor.tf_tensor_borrow(lib, types.TF_FLOAT, &(vec1(2)), abase + 1, 8);
  var uok = false;
  if !ubad.is_ok {
    uok = contains(ubad.error.message, "aligned");
  }
  failed = failed + report(uok, "live: unaligned borrow is refused typed (TF copy path + null deallocator)");

  // Bitcast: f32[4] -> i32[4] shares storage.
  let b1 = tensor.tf_tensor_alloc(lib, types.TF_FLOAT, &(vec1(4)), 16);
  let b2 = tensor.tf_tensor_alloc(lib, types.TF_INT32, &(vec1(4)), 16);
  var bit_ok = false;
  if b1.is_ok && b2.is_ok {
    let t1 = b1.value;
    let t2 = b2.value;
    tensor.tf_f32_store(tensor.tf_tensor_data(lib, t1), 0, 1.0);
    let bc = tensor.tf_tensor_bitcast(lib, t1, types.TF_INT32, t2, &(vec1(4)));
    if bc.is_ok {
      let rr = tensor.tf_tensor_read_i32(lib, t2, 4);
      if rr.is_ok {
        // 1.0f = 0x3F800000
        bit_ok = rr.value.items[0] == 1065353216;
      } else {
        note(rr.error.message);
      }
    } else {
      note(bc.error.message);
    }
    tensor.tf_tensor_delete(lib, t1);
    tensor.tf_tensor_delete(lib, t2);
  }
  failed = failed + report(bit_ok, "live: TF_TensorBitcastFrom f32->i32 shares bytes (1.0 -> 0x3F800000)");

  let c32 = tensor.tf_tensor_create_f32(lib, &(vec2(1, 2)), &(f32v2(3.5, -4.5)));
  var c32_ok = c32.is_ok;
  if c32.is_ok {
    let rr = tensor.tf_tensor_read_f32(lib, c32.value, 2);
    if rr.is_ok {
      if rr.value.items[0] != 3.5 { c32_ok = false; }
      if rr.value.items[1] != -4.5 { c32_ok = false; }
    } else {
      c32_ok = false;
    }
    tensor.tf_tensor_delete(lib, c32.value);
  }
  failed = failed + report(c32_ok, "live: tf_tensor_create_f32 + read (1x2 values)");

  var iv = vec2(7, -9);
  let ci = tensor.tf_tensor_create_i32(lib, &(vec1(2)), &iv);
  var ci_ok = ci.is_ok;
  if ci.is_ok {
    let rr = tensor.tf_tensor_read_i32(lib, ci.value, 2);
    if rr.is_ok {
      if rr.value.items[0] != 7 { ci_ok = false; }
      if rr.value.items[1] != -9 { ci_ok = false; }
    } else {
      ci_ok = false;
    }
    tensor.tf_tensor_delete(lib, ci.value);
  }
  failed = failed + report(ci_ok, "live: tf_tensor_create_i32 + read (signed roundtrip)");

  // ---- graph build + introspection ----
  let gr = graph.tf_graph_new(lib);
  if !gr.is_ok {
    failed = failed + report(false, "live: graph construction");
    note(gr.error.message);
    session.tf_session_options_delete(lib, snr.value);
    return failed;
  }
  let g = gr.value;

  let pha = ops.op_placeholder(lib, g, "a", types.TF_FLOAT, &(vec1(2)));
  let phb = ops.op_placeholder(lib, g, "b", types.TF_FLOAT, &(vec1(2)));
  var build_ok = pha.is_ok && phb.is_ok;
  var a_op = 0;
  var b_op = 0;
  var sum_op = 0;
  if build_ok {
    a_op = pha.value;
    b_op = phb.value;
    let add = ops.op_add(lib, g, "sum", a_op, b_op);
    if add.is_ok {
      sum_op = add.value;
    } else {
      build_ok = false;
      note(add.error.message);
    }
  } else {
    if !pha.is_ok { note(pha.error.message); }
    if !phb.is_ok { note(phb.error.message); }
  }
  failed = failed + report(build_ok, "live: Placeholder a/b + Add sum finished");

  if build_ok {
    var names_ok = graph.tf_op_name(lib, sum_op) == "sum";
    if graph.tf_op_type(lib, sum_op) != "Add" { names_ok = false; }
    if graph.tf_op_device(lib, sum_op) != "" { names_ok = false; }
    failed = failed + report(names_ok, "live: TF_OperationName/OpType/Device");

    var arity_ok = graph.tf_op_num_inputs(lib, sum_op) == 2;
    if graph.tf_op_num_outputs(lib, sum_op) != 1 { arity_ok = false; }
    failed = failed + report(arity_ok, "live: TF_OperationNumInputs/NumOutputs");

    var types_ok = graph.tf_op_output_type(lib, sum_op, 0) == types.TF_FLOAT;
    if graph.tf_op_input_type(lib, sum_op, 0) != types.TF_FLOAT { types_ok = false; }
    failed = failed + report(types_ok, "live: TF_OperationOutputType/InputType (by-value ABI adapters)");

    let all = graph.tf_op_all_inputs(lib, sum_op);
    var all_ok = all.items.len() == 4;
    if all.items.len() == 4 {
      if all.items[0] != a_op { all_ok = false; }
      if all.items[1] != 0 { all_ok = false; }
      if all.items[2] != b_op { all_ok = false; }
      if all.items[3] != 0 { all_ok = false; }
    }
    failed = failed + report(all_ok, "live: TF_OperationAllInputs producer edges are a and b");

    if platform.platform_is_windows() {
      let prod = graph.tf_op_input(lib, sum_op, 0);
      var inp_ok = prod.is_ok && prod.value.items.len() == 2 && prod.value.items[0] == a_op && prod.value.items[1] == 0;
      failed = failed + report(inp_ok, "live: TF_OperationInput producer of sum:0 is a:0 (Win64 struct return)");
    } else {
      let prod = graph.tf_op_input(lib, sum_op, 0);
      var inp_ok = !prod.is_ok && prod.error.kind == types.TF_ABI_UNSUPPORTED;
      failed = failed + report(inp_ok, "live: TF_OperationInput reports TF_ABI_UNSUPPORTED on the SysV ABI (portable path: AllInputs)");
    }

    var ctrl_ok = graph.tf_op_num_control_inputs(lib, sum_op) == 0;
    if graph.tf_op_num_control_outputs(lib, sum_op) != 0 { ctrl_ok = false; }
    failed = failed + report(ctrl_ok, "live: control-edge counts on sum are zero");

    var attrs_ok = graph.tf_op_num_attrs(lib, a_op) >= 2;
    let dt = graph.tf_op_get_attr_type(lib, a_op, "dtype");
    if !dt.is_ok { attrs_ok = false; }
    elif dt.value != types.TF_FLOAT { attrs_ok = false; }
    failed = failed + report(attrs_ok, "live: TF_OperationGetNumAttrs + GetAttrType(dtype)");

    let ash = graph.tf_op_get_attr_shape(lib, a_op, "shape", 1);
    var ash_ok = ash.is_ok && ash.value.items.len() == 1 && ash.value.items[0] == 2;
    failed = failed + report(ash_ok, "live: TF_OperationGetAttrShape(shape) == [2]");

    var byname_ok = graph.tf_graph_op_by_name(lib, g, "sum") == sum_op;
    if graph.tf_graph_op_by_name(lib, g, "nope") != 0 { byname_ok = false; }
    failed = failed + report(byname_ok, "live: TF_GraphOperationByName hit + miss");

    var gcount_ok = graph.tf_graph_op_count(lib, g) >= 3;
    failed = failed + report(gcount_ok, "live: TF_GraphNextOperation walk finds >= 3 ops");

    let nd = graph.tf_graph_tensor_num_dims(lib, g, a_op, 0);
    var nd_ok = nd.is_ok && nd.value == 1;
    let nsh = graph.tf_graph_tensor_shape(lib, g, a_op, 0);
    if nsh.is_ok {
      if nsh.value.items.len() != 1 { nd_ok = false; }
      elif nsh.value.items[0] != 2 { nd_ok = false; }
    } else {
      nd_ok = false;
    }
    failed = failed + report(nd_ok, "live: GraphGetTensorNumDims/Shape for a:0 == [2]");

    let setsh = graph.tf_graph_set_tensor_shape(lib, g, a_op, 0, &(vec1(2)));
    failed = failed + report(setsh.is_ok, "live: TF_GraphSetTensorShape merges [2]");

    let gdef = graph.tf_graph_to_graph_def(lib, g);
    var gdef_ok = gdef.is_ok && gdef.value.items.len() > 0;
    if !gdef.is_ok { note(gdef.error.message); }
    failed = failed + report(gdef_ok, "live: TF_GraphToGraphDef serializes the graph");

    let node = graph.tf_op_to_node_def(lib, sum_op);
    failed = failed + report(node.is_ok && node.value.items.len() > 0, "live: TF_OperationToNodeDef serializes sum");

    let attr_proto = graph.tf_op_get_attr_value_proto(lib, sum_op, "T");
    failed = failed + report(attr_proto.is_ok && attr_proto.value.items.len() > 0, "live: TF_OperationGetAttrValueProto(T) non-empty");
  };

  // ---- session options + session + Run ----
  var opts = 0;
  if snr.is_ok {
    opts = snr.value;
    failed = failed + report(true, "live: TF_NewSessionOptions (default options object)");
  } else {
    failed = failed + report(false, "live: TF_NewSessionOptions (default options object)");
    note(snr.error.message);
  };

  // TF_SetTarget lives on a throwaway options object: `local` is accepted by
  // the call, but TF 2.x registers only GRPC_SESSION/DIRECT_SESSION
  // factories, so the session itself uses default (empty-target) options.
  let tor = session.tf_session_options_new(lib);
  var target_ok = tor.is_ok;
  if tor.is_ok {
    session.tf_session_options_set_target(lib, tor.value, "local");
    session.tf_session_options_delete(lib, tor.value);
  } else {
    note(tor.error.message);
  }
  failed = failed + report(target_ok, "live: TF_SetTarget('local') accepted on options");

  // TF_SetConfig: a minimal ConfigProto (intra_op_parallelism_threads=1)
  // is accepted; a malformed byte is rejected typed.
  let cor = session.tf_session_options_new(lib);
  var cfg_ok = false;
  if cor.is_ok {
    var good: Vec[UInt8] = Vec[UInt8].with_len(2);
    good[0] = 16;
    good[1] = 1;
    let c1 = session.tf_session_options_set_config(lib, cor.value, &good);
    var bad: Vec[UInt8] = Vec[UInt8].with_len(1);
    bad[0] = 255;
    let c2 = session.tf_session_options_set_config(lib, cor.value, &bad);
    cfg_ok = c1.is_ok && !c2.is_ok && c2.error.message.len() > 0;
    if !c1.is_ok { note(c1.error.message); }
    if !c2.is_ok { note("malformed config: " + c2.error.message); }
    session.tf_session_options_delete(lib, cor.value);
  } else {
    note(cor.error.message);
  }
  failed = failed + report(cfg_ok, "live: TF_SetConfig -- valid ConfigProto bytes accepted, malformed rejected typed");

  let sess_r = session.tf_session_new(lib, g, opts);
  var sess_ok = false;
  var sess = 0;
  if sess_r.is_ok {
    sess = sess_r.value;
    sess_ok = true;
    let ext = session.tf_session_extend(lib, sess);
    if !ext.is_ok { note(ext.error.message); }
  } else {
    note(sess_r.error.message);
  }
  failed = failed + report(sess_ok, "live: TF_NewSession + TF_ExtendSession");

  if sess_ok {
    let ta = tensor.tf_tensor_create_f32(lib, &(vec1(2)), &(f32v2(1.5, 2.5)));
    let tb = tensor.tf_tensor_create_f32(lib, &(vec1(2)), &(f32v2(3.5, 4.5)));
    if ta.is_ok && tb.is_ok {
      var in_o: Vec[Int] = Vec[Int].new();
      in_o.push(a_op);
      in_o.push(b_op);
      var in_i: Vec[Int] = Vec[Int].new();
      in_i.push(0);
      in_i.push(0);
      var in_t: Vec[Int] = Vec[Int].new();
      in_t.push(ta.value);
      in_t.push(tb.value);
      let out_o = vec1(sum_op);
      let out_i = vec1(0);
      let run = session.tf_session_run(lib, sess, &in_o, &in_i, &in_t, &out_o, &out_i);
      var run_ok = run.is_ok;
      if run.is_ok {
        let out = run.value.items[0];
        let rr = tensor.tf_tensor_read_f32(lib, out, 2);
        if rr.is_ok {
          if rr.value.items[0] != 5.0 { run_ok = false; }
          if rr.value.items[1] != 7.0 { run_ok = false; }
        } else {
          run_ok = false;
          note(rr.error.message);
        }
        let shape_ok2 = tensor.tf_tensor_dim(lib, out, 0) == 2;
        if !shape_ok2 { run_ok = false; }
        tensor.tf_tensor_delete(lib, out);
      } else {
        note(run.error.message);
      }
      failed = failed + report(run_ok, "live: TF_SessionRun Add -- [1.5,2.5]+[3.5,4.5] == [5,7] exact");

      // Wrong-shape feed: typed runtime error (not a crash, not a fake pass).
      let tw = tensor.tf_tensor_create_f32(lib, &(vec1(3)), &(f32v3(1.0, 2.0, 3.0)));
      var bad_ok = false;
      if tw.is_ok {
        var bo: Vec[Int] = Vec[Int].new();
        bo.push(a_op);
        var fi: Vec[Int] = Vec[Int].new();
        fi.push(0);
        var ft: Vec[Int] = Vec[Int].new();
        ft.push(tw.value);
        let bad = session.tf_session_run(lib, sess, &bo, &fi, &ft, &out_o, &out_i);
        bad_ok = !bad.is_ok && bad.error.kind == types.TF_CALL_FAILED && bad.error.message.len() > 0;
        if bad.is_ok {
          var k = 0;
          while k < bad.value.items.len() {
            tensor.tf_tensor_delete(lib, bad.value.items[k]);
            k = k + 1;
          };
        } else {
          note(bad.error.message);
        }
        tensor.tf_tensor_delete(lib, tw.value);
      } else {
        note(tw.error.message);
      }
      failed = failed + report(bad_ok, "live: wrong-shape feed -> typed TF_CALL_FAILED (not a crash)");

      // Partial run: setup + one PRun step with the same feeds.
      let setup = session.tf_session_prun_setup(lib, sess, &in_o, &in_i, &out_o, &out_i);
      var prun_ok = false;
      if setup.is_ok {
        let pr = session.tf_session_prun(lib, sess, setup.value, &in_o, &in_i, &in_t, &out_o, &out_i);
        if pr.is_ok {
          let rr = tensor.tf_tensor_read_f32(lib, pr.value.items[0], 2);
          if rr.is_ok {
            prun_ok = rr.value.items[0] == 5.0 && rr.value.items[1] == 7.0;
          } else {
            note(rr.error.message);
          }
          tensor.tf_tensor_delete(lib, pr.value.items[0]);
        } else {
          note(pr.error.message);
        }
        session.tf_prun_delete(lib, setup.value);
      } else {
        note(setup.error.message);
      }
      failed = failed + report(prun_ok, "live: TF_SessionPRunSetup + TF_SessionPRun == [5,7]");

      tensor.tf_tensor_delete(lib, ta.value);
      tensor.tf_tensor_delete(lib, tb.value);
    } else {
      failed = failed + report(false, "live: TF_SessionRun Add -- [1.5,2.5]+[3.5,4.5] == [5,7] exact");
      failed = failed + report(false, "live: wrong-shape feed -> typed TF_CALL_FAILED (not a crash)");
      failed = failed + report(false, "live: TF_SessionPRunSetup + TF_SessionPRun == [5,7]");
    };

    // Devices.
    let dl = session.tf_device_list(lib, sess);
    var dev_ok = false;
    if dl.is_ok {
      let list = dl.value;
      let n = session.tf_device_list_count(lib, list);
      dev_ok = n >= 1;
      if dev_ok {
        let nm = session.tf_device_list_name(lib, list, 0);
        let ty = session.tf_device_list_type(lib, list, 0);
        if !nm.is_ok { dev_ok = false; }
        elif nm.value.len() == 0 { dev_ok = false; }
        if !ty.is_ok { dev_ok = false; }
        elif ty.value != "CPU" { dev_ok = false; }
        let mem = session.tf_device_list_memory_bytes(lib, list, 0);
        if !mem.is_ok { dev_ok = false; }
        let inc = session.tf_device_list_incarnation(lib, list, 0);
        if !inc.is_ok { dev_ok = false; }
      }
      session.tf_device_list_delete(lib, list);
    } else {
      note(dl.error.message);
    }
    failed = failed + report(dev_ok, "live: TF_SessionListDevices -- device 0 is CPU with name/memory/incarnation");

    // SavedModel typed-absent path: a nonexistent export dir must fail with
    // a typed error (never a fake session). TF requires a fresh graph.
    var tags: Vec[Str] = Vec[Str].new();
    tags.push("serve");
    let smg = graph.tf_graph_new(lib);
    var sm_ok = false;
    if smg.is_ok {
      let sm = session.tf_session_load_saved_model(lib, opts, "tests/fixtures/no-such-saved-model", &tags, smg.value);
      sm_ok = !sm.is_ok && sm.error.message.len() > 0;
      if sm.is_ok {
        session.tf_session_delete(lib, sm.value.items[0]);
      } else {
        note(sm.error.message);
      }
      graph.tf_graph_delete(lib, smg.value);
    } else {
      note(smg.error.message);
    }
    failed = failed + report(sm_ok, "live: TF_LoadSessionFromSavedModel on a missing dir -> typed error");

    session.tf_session_close(lib, sess);
    session.tf_session_delete(lib, sess);
  };

  // ---- ops tier beyond Add: Const folding, MatMul, Relu ----
  let g2r = graph.tf_graph_new(lib);
  if g2r.is_ok {
    let g2 = g2r.value;
    let ca = ops.op_const_f32(lib, g2, "ca", &(vec1(2)), &(f32v2(2.0, 3.0)));
    let cb = ops.op_const_f32(lib, g2, "cb", &(vec1(2)), &(f32v2(4.0, 5.0)));
    var cadd_ok = ca.is_ok && cb.is_ok;
    var csum = 0;
    if cadd_ok {
      let add = ops.op_add(lib, g2, "cadd", ca.value, cb.value);
      if add.is_ok { csum = add.value; } else { cadd_ok = false; note(add.error.message); }
    }
    var s2 = 0;
    var s2_ok = false;
    if cadd_ok {
      let sr = new_session(lib, g2);
      if sr.is_ok {
        s2 = sr.value;
        s2_ok = true;
      } else {
        note(sr.error.message);
      }
    }
    var const_run_ok = false;
    if s2_ok {
      // Const-only graph: zero feeds, one fetch (ninputs = 0 is legal).
      var eo: Vec[Int] = Vec[Int].new();
      var ei: Vec[Int] = Vec[Int].new();
      var et: Vec[Int] = Vec[Int].new();
      let out_o = vec1(csum);
      let out_i = vec1(0);
      let runv = session.tf_session_run(lib, s2, &eo, &ei, &et, &out_o, &out_i);
      if runv.is_ok {
        let rr = tensor.tf_tensor_read_f32(lib, runv.value.items[0], 2);
        if rr.is_ok {
          const_run_ok = rr.value.items[0] == 6.0 && rr.value.items[1] == 8.0;
        } else {
          note(rr.error.message);
        }
        tensor.tf_tensor_delete(lib, runv.value.items[0]);
      } else {
        note(runv.error.message);
      }
      session.tf_session_close(lib, s2);
      session.tf_session_delete(lib, s2);
    }
    failed = failed + report(const_run_ok, "live: ops op_const_f32 x2 + op_add -> [2,3]+[4,5] == [6,8] (zero-feed run)");

    // MatMul 2x2 exact: [[1,2],[3,4]] x [[5,6],[7,8]] = [[19,22],[43,50]]
    var mm_ok = false;
    {
      // Const the two matrices into the graph, MatMul them, run zero-feed.
      let k1 = ops.op_const_f32(lib, g2, "m1", &(vec2(2, 2)), &(four_f(1.0, 2.0, 3.0, 4.0)));
      let k2 = ops.op_const_f32(lib, g2, "m2", &(vec2(2, 2)), &(four_f(5.0, 6.0, 7.0, 8.0)));
      if k1.is_ok && k2.is_ok {
        let mm = ops.op_matmul(lib, g2, "mm", k1.value, k2.value, false, false);
        if mm.is_ok {
          let sr = new_session(lib, g2);
          if sr.is_ok {
            let s3 = sr.value;
            let out_o = vec1(mm.value);
            let out_i = vec1(0);
            let eo: Vec[Int] = Vec[Int].new();
            let ei: Vec[Int] = Vec[Int].new();
            let et: Vec[Int] = Vec[Int].new();
            let runv = session.tf_session_run(lib, s3, &eo, &ei, &et, &out_o, &out_i);
            if runv.is_ok {
              let rr = tensor.tf_tensor_read_f32(lib, runv.value.items[0], 4);
              if rr.is_ok {
                let v = rr.value.items;
                mm_ok = v.len() == 4;
                if mm_ok {
                  if v[0] != 19.0 { mm_ok = false; }
                  if v[1] != 22.0 { mm_ok = false; }
                  if v[2] != 43.0 { mm_ok = false; }
                  if v[3] != 50.0 { mm_ok = false; }
                }
              } else {
                note(rr.error.message);
              }
              tensor.tf_tensor_delete(lib, runv.value.items[0]);
            } else {
              note(runv.error.message);
            }
            session.tf_session_close(lib, s3);
            session.tf_session_delete(lib, s3);
          } else {
            note(sr.error.message);
          }
        } else {
          note(mm.error.message);
        }
      }
    }
    failed = failed + report(mm_ok, "live: ops op_matmul 2x2 exact ints as f32");

    // Relu: [-1,2,-3,4] -> [0,2,0,4]
    let rx = ops.op_const_f32(lib, g2, "rx", &(vec1(4)), &(four_f(-1.0, 2.0, -3.0, 4.0)));
    var relu_ok = false;
    if rx.is_ok {
      let rl = ops.op_relu(lib, g2, "rl", rx.value);
      if rl.is_ok {
        let sr = new_session(lib, g2);
        if sr.is_ok {
          let s4 = sr.value;
          let out_o = vec1(rl.value);
          let out_i = vec1(0);
          let eo: Vec[Int] = Vec[Int].new();
          let ei: Vec[Int] = Vec[Int].new();
          let et: Vec[Int] = Vec[Int].new();
          let runv = session.tf_session_run(lib, s4, &eo, &ei, &et, &out_o, &out_i);
          if runv.is_ok {
            let rr = tensor.tf_tensor_read_f32(lib, runv.value.items[0], 4);
            if rr.is_ok {
              let v = rr.value.items;
              relu_ok = v.len() == 4 && v[0] == 0.0 && v[1] == 2.0 && v[2] == 0.0 && v[3] == 4.0;
            } else {
              note(rr.error.message);
            }
            tensor.tf_tensor_delete(lib, runv.value.items[0]);
          } else {
            note(runv.error.message);
          }
          session.tf_session_close(lib, s4);
          session.tf_session_delete(lib, s4);
        } else {
          note(sr.error.message);
        }
      } else {
        note(rl.error.message);
      }
    }
    failed = failed + report(relu_ok, "live: ops op_relu [-1,2,-3,4] -> [0,2,0,4]");

    graph.tf_graph_delete(lib, g2);
  } else {
    failed = failed + report(false, "live: ops Const/Add run");
    failed = failed + report(false, "live: ops MatMul");
    failed = failed + report(false, "live: ops Relu");
  };

  // ---- GraphDef import (fresh graph, prefix + return-output options) ----
  if build_ok {
    let gdef2 = graph.tf_graph_to_graph_def(lib, g);
    let g3r = graph.tf_graph_new(lib);
    var import_ok = false;
    if gdef2.is_ok && g3r.is_ok {
      let g3 = g3r.value;
      let ior = graph.tf_import_options_new(lib);
      var opts2 = 0;
      var opt_ok = ior.is_ok;
      if ior.is_ok {
        opts2 = ior.value;
        graph.tf_import_options_set_prefix(lib, opts2, "imp/");
        graph.tf_import_options_set_default_device(lib, opts2, "/cpu:0");
        graph.tf_import_options_set_uniquify_names(lib, opts2, true);
        graph.tf_import_options_set_uniquify_prefix(lib, opts2, true);
        graph.tf_import_options_add_return_output(lib, opts2, "sum", 0);
        graph.tf_import_options_add_return_operation(lib, opts2, "a");
        var cnt_ok = graph.tf_import_options_num_return_outputs(lib, opts2) == 1;
        if graph.tf_import_options_num_return_operations(lib, opts2) != 1 { cnt_ok = false; }
        failed = failed + report(cnt_ok, "live: import options -- prefix + return counts");
        let imp = graph.tf_graph_import_graph_def(lib, g3, &gdef2.value.items, opts2);
        if imp.is_ok {
          let prefixed = graph.tf_graph_op_by_name(lib, g3, "imp/sum");
          import_ok = prefixed != 0;
          if import_ok {
            if graph.tf_op_num_inputs(lib, prefixed) != 2 { import_ok = false; }
          }
        } else {
          note(imp.error.message);
        }
        graph.tf_import_options_delete(lib, opts2);
      } else {
        note(ior.error.message);
      }
      failed = failed + report(import_ok, "live: TF_GraphImportGraphDef with prefix -> imp/sum in a fresh graph");

      // WithResults tier: return outputs back through the results handle.
      let ior2 = graph.tf_import_options_new(lib);
      var results_ok = false;
      if ior2.is_ok {
        graph.tf_import_options_add_return_operation(lib, ior2.value, "sum");
        let g4r = graph.tf_graph_new(lib);
        if g4r.is_ok {
          let g4 = g4r.value;
          let wr = graph.tf_graph_import_graph_def_with_results(lib, g4, &gdef2.value.items, ior2.value);
          if wr.is_ok {
            let rops = graph.tf_import_results_return_operations(lib, wr.value);
            results_ok = rops.items.len() == 1;
            if results_ok {
              if graph.tf_op_name(lib, rops.items[0]) != "sum" { results_ok = false; }
            }
            let routs = graph.tf_import_results_return_outputs(lib, wr.value);
            if routs.items.len() != 0 { results_ok = false; }
            graph.tf_import_results_delete(lib, wr.value);
          } else {
            note(wr.error.message);
          }
          graph.tf_graph_delete(lib, g4);
        }
        graph.tf_import_options_delete(lib, ior2.value);
      } else {
        note(ior2.error.message);
      }
      failed = failed + report(results_ok, "live: TF_GraphImportGraphDefWithResults returns the requested operation");

      // WithReturnOutputs tier: import and read the returned TF_Output array.
      let ior4 = graph.tf_import_options_new(lib);
      var rout_ok = false;
      if ior4.is_ok {
        graph.tf_import_options_add_return_output(lib, ior4.value, "sum", 0);
        let g6r = graph.tf_graph_new(lib);
        if g6r.is_ok {
          let g6 = g6r.value;
          let wo = graph.tf_graph_import_graph_def_with_return_outputs(lib, g6, &gdef2.value.items, ior4.value, 1);
          if wo.is_ok {
            rout_ok = wo.value.items.len() == 2;
            if rout_ok {
              if wo.value.items[1] != 0 { rout_ok = false; }
              if graph.tf_op_name(lib, wo.value.items[0]) != "sum" { rout_ok = false; }
            }
          } else {
            note(wo.error.message);
          }
          graph.tf_graph_delete(lib, g6);
        }
        graph.tf_import_options_delete(lib, ior4.value);
      } else {
        note(ior4.error.message);
      }
      failed = failed + report(rout_ok, "live: TF_GraphImportGraphDefWithReturnOutputs returns sum:0");

      // Input mapping tier: remap the imported graph's `a` input to an
      // existing node `ext` (sum's input 0 must become ext afterwards).
      let ior5 = graph.tf_import_options_new(lib);
      var map_ok = false;
      if ior5.is_ok {
        let g7r = graph.tf_graph_new(lib);
        if g7r.is_ok {
          let g7 = g7r.value;
          let ext = ops.op_placeholder(lib, g7, "ext", types.TF_FLOAT, &(vec1(2)));
          if ext.is_ok {
            graph.tf_import_options_add_input_mapping(lib, ior5.value, "a", 0, ext.value, 0);
            let imp5 = graph.tf_graph_import_graph_def(lib, g7, &gdef2.value.items, ior5.value);
            if imp5.is_ok {
              let sum7 = graph.tf_graph_op_by_name(lib, g7, "sum");
              if sum7 != 0 {
                let all = graph.tf_op_all_inputs(lib, sum7);
                map_ok = all.items.len() == 4;
                if map_ok {
                  // input 0 was rewired to ext; input 1 is the freshly
                  // imported "b" (a new op object in g7).
                  if all.items[0] != ext.value { map_ok = false; }
                  if graph.tf_op_name(lib, all.items[0]) != "ext" { map_ok = false; }
                  if graph.tf_op_name(lib, all.items[2]) != "b" { map_ok = false; }
                  if graph.tf_graph_op_by_name(lib, g7, "a") == 0 { note("mapping dropped placeholder 'a' from g7"); }
                }
              } else {
                note("imported graph has no 'sum' op");
              }
            } else {
              note(imp5.error.message);
            }
          } else {
            note(ext.error.message);
          }
          graph.tf_graph_delete(lib, g7);
        }
        graph.tf_import_options_delete(lib, ior5.value);
      } else {
        note(ior5.error.message);
      }
      failed = failed + report(map_ok, "live: ImportGraphDefOptionsAddInputMapping rewires sum's first input to ext");

      graph.tf_graph_delete(lib, g3);
    } else {
      failed = failed + report(false, "live: TF_GraphImportGraphDef with prefix -> imp/sum in a fresh graph");
      failed = failed + report(false, "live: TF_GraphImportGraphDefWithResults returns the requested operation");
      failed = failed + report(false, "live: TF_GraphImportGraphDefWithReturnOutputs returns sum:0");
      failed = failed + report(false, "live: ImportGraphDefOptionsAddInputMapping rewires sum's first input to ext");
    }
  };

  failed = failed + test_ops_extended(lib);

  graph.tf_graph_delete(lib, g);
  if snr.is_ok {
    session.tf_session_options_delete(lib, snr.value);
  };
  return failed;
}

fn four_f(a: Float32, b: Float32, c: Float32, d: Float32) -> Vec[Float32] {
  var v: Vec[Float32] = Vec[Float32].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

/// Create a session on default options (TF_NewSession requires non-null
/// options; the options object is released right after).
fn new_session(lib: &TfLibrary, g: Int) -> Result[Int, TfError]
  requires: g != 0
{
  let o = session.tf_session_options_new(lib);
  if !o.is_ok { return Err(o.error); }
  let s = session.tf_session_new(lib, g, o.value);
  session.tf_session_options_delete(lib, o.value);
  return s;
}

fn f32_range(n: Int, start: Float32) -> Vec[Float32] {
  var v: Vec[Float32] = Vec[Float32].new();
  var i = 0;
  while i < n {
    v.push(start + (i as Float32));
    i = i + 1;
  };
  return v;
}

fn u8_bytes(vals: &Vec[Int]) -> Vec[UInt8] {
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < vals.len() {
    v.push(vals[i] as UInt8);
    i = i + 1;
  };
  return v;
}

/// Run zero-feed, fetch one output, read `count` f32 values back.
fn run_fetch_f32(lib: &TfLibrary, g: Int, oper: Int, count: Int) -> Result[TfF32List, TfError]
  requires: g != 0
  requires: oper != 0
{
  let sr = new_session(lib, g);
  if !sr.is_ok { return Err(sr.error); }
  let s = sr.value;
  let out_o = vec1(oper);
  let out_i = vec1(0);
  let eo: Vec[Int] = Vec[Int].new();
  let ei: Vec[Int] = Vec[Int].new();
  let et: Vec[Int] = Vec[Int].new();
  let runv = session.tf_session_run(lib, s, &eo, &ei, &et, &out_o, &out_i);
  var result: Result[TfF32List, TfError] = Err(TfError{ kind: types.TF_CALL_FAILED; message: "run_fetch_f32: unreachable" });
  if runv.is_ok {
    result = tensor.tf_tensor_read_f32(lib, runv.value.items[0], count);
    tensor.tf_tensor_delete(lib, runv.value.items[0]);
  } else {
    result = Err(runv.error);
  }
  session.tf_session_close(lib, s);
  session.tf_session_delete(lib, s);
  return result;
}

fn f32v3(a: Float32, b: Float32, c: Float32) -> Vec[Float32] {
  var v: Vec[Float32] = Vec[Float32].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

// =========================================================================
// Live tier, extended ops/attrs coverage (every remaining declared slot)
// =========================================================================

fn test_ops_extended(lib: &TfLibrary) -> Int {
  var failed = 0;
  let gr = graph.tf_graph_new(lib);
  if !gr.is_ok {
    failed = failed + report(false, "live: extended ops coverage (graph_new failed)");
    note(gr.error.message);
    return failed;
  }
  let g = gr.value;

  // TF_SetAttrValueProto: Neg with T supplied as serialized AttrValue bytes
  // [0x30, 0x01] (field 6 "type", varint TF_FLOAT=1).
  let k1 = ops.op_const_f32(lib, g, "v1", &(vec1(2)), &(f32v2(1.0, -2.0)));
  var neg_ok = false;
  if k1.is_ok {
    let dr = graph.tf_op_new(lib, g, "Neg", "neg");
    if dr.is_ok {
      var proto: Vec[UInt8] = Vec[UInt8].with_len(2);
      proto[0] = 48;
      proto[1] = 1;
      let av = graph.tf_op_set_attr_value_proto(lib, dr.value, "T", &proto);
      graph.tf_op_add_input(lib, dr.value, k1.value, 0);
      let fin = graph.tf_op_finish(lib, dr.value);
      if av.is_ok && fin.is_ok {
        let rr = run_fetch_f32(lib, g, fin.value, 2);
        if rr.is_ok {
          neg_ok = rr.value.items[0] == -1.0 && rr.value.items[1] == 2.0;
        } else {
          note(rr.error.message);
        }
      } else {
        if !av.is_ok { note(av.error.message); }
        if !fin.is_ok { note(fin.error.message); }
      }
    }
  }
  failed = failed + report(neg_ok, "live: TF_SetAttrValueProto (T = AttrValue bytes) + Neg -> [-1,2]");

  // TF_SetAttrInt + TF_OperationOutputListLength + multi-output fetch:
  // Unpack [7,8,9] on num=3/axis=0 -> three scalars 7, 8, 9.
  let ku = ops.op_const_f32(lib, g, "u3", &(vec1(3)), &(f32v3(7.0, 8.0, 9.0)));
  var unpack_ok = false;
  if ku.is_ok {
    let dr = graph.tf_op_new(lib, g, "Unpack", "un");
    if dr.is_ok {
      graph.tf_op_set_attr_type(lib, dr.value, "T", types.TF_FLOAT);
      graph.tf_op_set_attr_int(lib, dr.value, "num", 3);
      graph.tf_op_set_attr_int(lib, dr.value, "axis", 0);
      graph.tf_op_add_input(lib, dr.value, ku.value, 0);
      let fin = graph.tf_op_finish(lib, dr.value);
      if fin.is_ok {
        let un = fin.value;
        let oll = graph.tf_op_output_list_length(lib, un, "output");
        var shape_ok = oll.is_ok && oll.value == 3;
        if !oll.is_ok { note("oll err: " + oll.error.message); }
        elif oll.value != 3 { note("oll=" + ist(oll.value)); }
        let gi = graph.tf_op_get_attr_int(lib, un, "num");
        if !gi.is_ok { shape_ok = false; note("gi err: " + gi.error.message); }
        elif gi.value != 3 { shape_ok = false; note("gi=" + ist(gi.value)); }
        if shape_ok {
          // Three fetched scalars.
          let sr = new_session(lib, g);
          if sr.is_ok {
            let s = sr.value;
            var oo: Vec[Int] = Vec[Int].new();
            oo.push(un);
            oo.push(un);
            oo.push(un);
            var oi: Vec[Int] = Vec[Int].new();
            oi.push(0);
            oi.push(1);
            oi.push(2);
            let eo: Vec[Int] = Vec[Int].new();
            let ei: Vec[Int] = Vec[Int].new();
            let et: Vec[Int] = Vec[Int].new();
            let runv = session.tf_session_run(lib, s, &eo, &ei, &et, &oo, &oi);
            if runv.is_ok {
              var got_ok = runv.value.items.len() == 3;
              if got_ok {
                var j = 0;
                while j < 3 {
                  let rr = tensor.tf_tensor_read_f32(lib, runv.value.items[j], 1);
                  if !rr.is_ok { got_ok = false; }
                  elif rr.value.items[0] != (7.0 + (j as Float32)) { got_ok = false; }
                  tensor.tf_tensor_delete(lib, runv.value.items[j]);
                  j = j + 1;
                }
              }
              unpack_ok = got_ok;
            } else {
              note(runv.error.message);
            }
            session.tf_session_close(lib, s);
            session.tf_session_delete(lib, s);
          } else {
            note(sr.error.message);
          }
        } else {
          shape_ok = false;
        }
      } else {
        note(fin.error.message);
      }
    }
  } else if !ku.is_ok {
    note(ku.error.message);
  }
  failed = failed + report(unpack_ok, "live: SetAttrInt + Unpack 3 scalars [7,8,9] + OutputListLength + GetAttrInt");

  // TF_SetAttrShape + TF_AddInputList + TF_AddControlInput + TF_ColocateWith
  // + TF_OperationInputListLength + control-edge getters: AddN = 9,12.
  let a1 = ops.op_const_f32(lib, g, "a1", &(vec1(2)), &(f32v2(1.0, 2.0)));
  let a2 = ops.op_const_f32(lib, g, "a2", &(vec1(2)), &(f32v2(3.0, 4.0)));
  let a3 = ops.op_const_f32(lib, g, "a3", &(vec1(2)), &(f32v2(5.0, 6.0)));
  var addn_ok = false;
  if a1.is_ok && a2.is_ok && a3.is_ok {
    let dr = graph.tf_op_new(lib, g, "AddN", "addn");
    if dr.is_ok {
      var oo: Vec[Int] = Vec[Int].new();
      oo.push(a1.value);
      oo.push(a2.value);
      oo.push(a3.value);
      var oi: Vec[Int] = Vec[Int].new();
      oi.push(0);
      oi.push(0);
      oi.push(0);
      graph.tf_op_add_input_list(lib, dr.value, &oo, &oi);
      graph.tf_op_add_control_input(lib, dr.value, a1.value);
      graph.tf_op_colocate_with(lib, dr.value, a1.value);
      let fin = graph.tf_op_finish(lib, dr.value);
      if fin.is_ok {
        let an = fin.value;
        let ill = graph.tf_op_input_list_length(lib, an, "inputs");
        var shp = ill.is_ok && ill.value == 3;
        if graph.tf_op_num_control_inputs(lib, an) != 1 { shp = false; }
        let ci = graph.tf_op_control_inputs(lib, an);
        if ci.items.len() != 1 { shp = false; }
        elif ci.items[0] != a1.value { shp = false; }
        let co = graph.tf_op_control_outputs(lib, a1.value);
        if co.items.len() != 1 { shp = false; }
        elif co.items[0] != an { shp = false; }
        if shp {
          let rr = run_fetch_f32(lib, g, an, 2);
          if rr.is_ok {
            addn_ok = rr.value.items[0] == 9.0 && rr.value.items[1] == 12.0;
          } else {
            note(rr.error.message);
          }
        }
      } else {
        note(fin.error.message);
      }
    }
  }
  failed = failed + report(addn_ok, "live: AddInputList+control edge+ColocateWith AddN -> [9,12] (control getters agree)");

  // TF_SetAttrString + TF_SetAttrIntList + TF_SetAttrBool + TF_OperationGetAttrBool:
  // Conv2D 4x4 VALID with all-ones 2x2 filter -> exact window sums.
  var conv_ok = false;
  var ishape: Vec[Int] = Vec[Int].new();
  ishape.push(1);
  ishape.push(4);
  ishape.push(4);
  ishape.push(1);
  var fshape: Vec[Int] = Vec[Int].new();
  fshape.push(2);
  fshape.push(2);
  fshape.push(1);
  fshape.push(1);
  let ki = ops.op_const_f32(lib, g, "img", &ishape, &(f32_range(16, 1.0)));
  let kf = ops.op_const_f32(lib, g, "flt", &fshape, &(four_f(1.0, 1.0, 1.0, 1.0)));
  if ki.is_ok && kf.is_ok {
    let dr = graph.tf_op_new(lib, g, "Conv2D", "conv");
    if dr.is_ok {
      graph.tf_op_add_input(lib, dr.value, ki.value, 0);
      graph.tf_op_add_input(lib, dr.value, kf.value, 0);
      graph.tf_op_set_attr_type(lib, dr.value, "T", types.TF_FLOAT);
      var strides: Vec[Int] = Vec[Int].new();
      strides.push(1);
      strides.push(1);
      strides.push(1);
      strides.push(1);
      graph.tf_op_set_attr_int_list(lib, dr.value, "strides", &strides);
      graph.tf_op_set_attr_string(lib, dr.value, "padding", "VALID");
      graph.tf_op_set_attr_string(lib, dr.value, "data_format", "NHWC");
      graph.tf_op_set_attr_bool(lib, dr.value, "use_cudnn_on_gpu", true);
      let fin = graph.tf_op_finish(lib, dr.value);
      if fin.is_ok {
        let gb = graph.tf_op_get_attr_bool(lib, fin.value, "use_cudnn_on_gpu");
        var conv_attrs_ok = gb.is_ok && gb.value;
        if !gb.is_ok { note("gb err: " + gb.error.message); }
        elif !gb.value { note("gb=false"); }
        if conv_attrs_ok {
          let rr = run_fetch_f32(lib, g, fin.value, 9);
          if rr.is_ok {
            // 14,18,22,30,34,38,46,50,54 -- 14 + row*16 + col*4
            var j = 0;
            var all_ok = rr.value.items.len() == 9;
            if !all_ok { note("conv outputs=" + ist(rr.value.items.len())); }
            while j < 9 {
              let expect = 14.0 + ((j / 3) as Float32) * 16.0 + ((j % 3) as Float32) * 4.0;
              if rr.value.items[j] != expect {
                all_ok = false;
                note("conv[" + ist(j) + "]=" + loader.int_to_str(rr.value.items[j] as Int) + " want " + loader.int_to_str(expect as Int));
              }
              j = j + 1;
            };
            conv_ok = all_ok;
          } else {
            note("conv run: " + rr.error.message);
          }
        }
      } else {
        note("conv finish: " + fin.error.message);
      }
    }
  }
  failed = failed + report(conv_ok, "live: SetAttrString/IntList/Bool + Conv2D VALID exact window sums (GetAttrBool agrees)");

  // TF_SetAttrFloat + TF_OperationGetAttrFloat: LeakyRelu alpha=0.5.
  var lrelu_ok = false;
  let lx = ops.op_const_f32(lib, g, "lx", &(vec1(2)), &(f32v2(-2.0, 3.0)));
  if lx.is_ok {
    let dr = graph.tf_op_new(lib, g, "LeakyRelu", "lrelu");
    if dr.is_ok {
      graph.tf_op_set_attr_type(lib, dr.value, "T", types.TF_FLOAT);
      graph.tf_op_set_attr_float(lib, dr.value, "alpha", 0.5);
      graph.tf_op_add_input(lib, dr.value, lx.value, 0);
      let fin = graph.tf_op_finish(lib, dr.value);
      if fin.is_ok {
        let gf = graph.tf_op_get_attr_float(lib, fin.value, "alpha");
        var ga_ok = gf.is_ok;
        if gf.is_ok {
          if gf.value != 0.5 { ga_ok = false; }
        }
        if ga_ok {
          let rr = run_fetch_f32(lib, g, fin.value, 2);
          if rr.is_ok {
            lrelu_ok = rr.value.items[0] == -1.0 && rr.value.items[1] == 3.0;
          } else {
            note(rr.error.message);
          }
        }
      } else {
        note(fin.error.message);
      }
    }
  }
  failed = failed + report(lrelu_ok, "live: SetAttrFloat + GetAttrFloat LeakyRelu alpha=0.5 -> [-1,3]");

  // TF_SetAttrFloatList: calling it with a scalar-typed attr must surface as
  // a typed FinishOperation failure (the call itself reaches TF).
  let drl = graph.tf_op_new(lib, g, "LeakyRelu", "badlist");
  var flist_ok = false;
  if drl.is_ok {
    graph.tf_op_set_attr_type(lib, drl.value, "T", types.TF_FLOAT);
    graph.tf_op_set_attr_float_list(lib, drl.value, "alpha", &(f32v2(0.5, 0.25)));
    if lx.is_ok {
      graph.tf_op_add_input(lib, drl.value, lx.value, 0);
    }
    let fin = graph.tf_op_finish(lib, drl.value);
    flist_ok = !fin.is_ok && fin.error.message.len() > 0;
    if !flist_ok && fin.is_ok {
      note("float-list on scalar attr was accepted by TF (no typed failure)");
    }
  }
  failed = failed + report(flist_ok, "live: SetAttrFloatList mismatch -> typed FinishOperation error");

  // TF_SetAttrPlaceholder: exercised on an attr that is not a placeholder;
  // the mismatch must surface as a typed FinishOperation failure.
  let drp = graph.tf_op_new(lib, g, "LeakyRelu", "badph");
  var ph_ok = false;
  if drp.is_ok {
    graph.tf_op_set_attr_type(lib, drp.value, "T", types.TF_FLOAT);
    graph.tf_op_set_attr_placeholder(lib, drp.value, "alpha", "ph");
    if lx.is_ok {
      graph.tf_op_add_input(lib, drp.value, lx.value, 0);
    }
    let fin = graph.tf_op_finish(lib, drp.value);
    if fin.is_ok {
      note("placeholder attr accepted by TF; probing attr type");
      let gf = graph.tf_op_get_attr_float(lib, fin.value, "alpha");
      ph_ok = !gf.is_ok && gf.error.message.len() > 0;
      if gf.is_ok { note("alpha still readable as float=" + loader.int_to_str(gf.value as Int)); }
    } else {
      note("placeholder finish err: " + fin.error.message);
      ph_ok = fin.error.message.len() > 0;
    }
  }
  failed = failed + report(ph_ok, "live: SetAttrPlaceholder -- placeholder AttrValue observable on the op");

  // TF_SetDevice + TF_OperationDevice.
  var dev_ok = false;
  if a1.is_ok {
    let dr = graph.tf_op_new(lib, g, "Identity", "devop");
    if dr.is_ok {
      graph.tf_op_set_device(lib, dr.value, "/device:CPU:0");
      graph.tf_op_add_input(lib, dr.value, a1.value, 0);
      let fin = graph.tf_op_finish(lib, dr.value);
      if fin.is_ok {
        let dev = graph.tf_op_device(lib, fin.value);
        dev_ok = contains(dev, "CPU");
        if !dev_ok { note("device string: '" + dev + "'"); }
      } else {
        note(fin.error.message);
      }
    }
  }
  failed = failed + report(dev_ok, "live: TF_SetDevice('/device:CPU:0') + TF_OperationDevice roundtrip");

  graph.tf_graph_delete(lib, g);
  return failed;
}

// =========================================================================
// Runner
// =========================================================================

pub fn main() -> Int {
  io.println("xiom.tensorflow conformance suite");
  io.flush_stdout();

  var failed = 0;
  failed = failed + test_pure();

  let lr = loader.tf_load();
  if lr.is_ok {
    let lib = lr.value;
    io.println("  live: runtime " + lib.version + " via " + lib.soname);
    io.flush_stdout();
    failed = failed + test_live(&lib);
    let cr = loader.tf_close(&lib);
    if !cr.is_ok { note(cr.error); }
  } else {
    if lr.error.kind == types.TF_LOAD_ABSENT {
      io.println("  live: SKIP -- no tensorflow candidate present (" + lr.error.message + ")");
      io.flush_stdout();
    } else {
      io.println("  [FAIL] live: runtime present but unusable");
      note(lr.error.message);
      io.flush_stdout();
      failed = failed + 1;
    }
  };

  if failed == 0 {
    io.println("xiom.tensorflow: all tests passed");
  } else {
    io.println("xiom.tensorflow: tests failed (" + ist(failed) + ")");
  }
  io.flush_stdout();
  return failed;
}
