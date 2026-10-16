// XIOM -- xiom.onnx conformance suite: pure tier + live ONNX Runtime leg.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// CI WITHOUT a runtime stays green: no candidate soname -> SKIP (the SKIP
// path is exercised deterministically every run via a bogus soname). When
// a runtime is present the suite proves the full declared surface live:
// env + telemetry + providers, the status trio, memory info + allocators,
// tensors (allocator-owned and borrowed-buffer), type/shape metadata,
// session options + wide-path session creation, session metadata, run
// options, Run with exact arithmetic (2+4=6, 3+5=8 on the fixture model),
// IoBinding (device outputs + preallocated outputs + clear/sync), typed
// error paths, and the high-level OnnxModel API.
//
// Build+run (pure-XIOM loader; no compiler args):
//   scripts/port.ps1 -Package xiom.onnx
// The live leg uses the loader candidate order: `XIOM_ONNX_RUNTIME` (an
// explicit path to a runtime, e.g. the pinned E:\repos\onnxruntime-bin
// build), then the bare Windows/Linux/macOS sonames. Without either the
// suite reports SKIP and stays green.
//
// Fixture: tests/fixtures/add_f32.onnx -- a 110-byte Add model (A[2]+B[2]
// -> C[2], FLOAT, opset 14, ir_version 7) crafted for this suite from the
// ONNX protobuf schema (onnx.proto3 @ onnx v1.23.2); SHA256 pinned in
// SPEC.md. It is cross-validated by the Python onnxruntime 1.14.1 build
// and by the live leg below.

module onnx_conformance

use xiom.onnx.types;
use xiom.onnx.loader;
use xiom.onnx.env;
use xiom.onnx.value;
use xiom.onnx.session;
use xiom.onnx.tensor;
use xiom.io;
use xiom.ffi;
use xiom.io.fs;

const FIXTURE: Str = "tests/fixtures/add_f32.onnx";

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

fn why(msg: Str) {
  io.println("    detail: " + msg);
  io.flush_stdout();
}

fn bstr(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

fn ist(i: Int) -> Str {
  return loader.int_to_str(i);
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

fn finish(failed: Int) -> Int {
  if failed == 0 {
    io.println("xiom.onnx: all tests passed");
  } else {
    io.println("xiom.onnx: tests failed");
  }
  return failed;
}

// =========================================================================
// Pure tier (no runtime needed)
// =========================================================================

fn test_pure() -> Int {
  var failed = 0;

  let cfg = onnx_config_default();
  failed = failed + report(cfg.num_threads == 4 && cfg.graph_optimization_level == 1 && cfg.enable_profiling == false,
    "types: config defaults (threads=4, graph_opt=BASIC, profiling=off)");

  var dtypes_ok = true;
  if types.ORT_DTYPE_FLOAT != 1 { dtypes_ok = false; }
  if types.ORT_DTYPE_UINT8 != 2 { dtypes_ok = false; }
  if types.ORT_DTYPE_INT8 != 3 { dtypes_ok = false; }
  if types.ORT_DTYPE_INT32 != 6 { dtypes_ok = false; }
  if types.ORT_DTYPE_INT64 != 7 { dtypes_ok = false; }
  if types.ORT_DTYPE_STRING != 8 { dtypes_ok = false; }
  if types.ORT_DTYPE_BOOL != 9 { dtypes_ok = false; }
  if types.ORT_DTYPE_FLOAT16 != 10 { dtypes_ok = false; }
  if types.ORT_DTYPE_DOUBLE != 11 { dtypes_ok = false; }
  if types.ORT_DTYPE_BFLOAT16 != 16 { dtypes_ok = false; }
  if types.ORT_DTYPE_FLOAT8E4M3FN != 17 { dtypes_ok = false; }
  if types.ORT_DTYPE_FLOAT8E5M2 != 19 { dtypes_ok = false; }
  if types.ORT_DTYPE_INT4 != 22 { dtypes_ok = false; }
  if types.ORT_DTYPE_FLOAT4E2M1 != 23 { dtypes_ok = false; }
  if types.ORT_DTYPE_UINT2 != 24 { dtypes_ok = false; }
  if types.ORT_DTYPE_INT2 != 25 { dtypes_ok = false; }
  if types.ORT_DTYPE_FLOAT8E8M0 != 26 { dtypes_ok = false; }
  failed = failed + report(dtypes_ok, "types: ONNXTensorElementDataType constants (0..26 oracle)");

  var opts_ok = true;
  if types.ORT_GRAPH_OPT_DISABLE != 0 { opts_ok = false; }
  if types.ORT_GRAPH_OPT_BASIC != 1 { opts_ok = false; }
  if types.ORT_GRAPH_OPT_EXTENDED != 2 { opts_ok = false; }
  if types.ORT_GRAPH_OPT_LAYOUT != 3 { opts_ok = false; }
  if types.ORT_GRAPH_OPT_ALL != 99 { opts_ok = false; }
  if types.ORT_EXECUTION_MODE_SEQUENTIAL != 0 { opts_ok = false; }
  if types.ORT_EXECUTION_MODE_PARALLEL != 1 { opts_ok = false; }
  if types.ORT_LOGGING_LEVEL_VERBOSE != 0 { opts_ok = false; }
  if types.ORT_LOGGING_LEVEL_INFO != 1 { opts_ok = false; }
  if types.ORT_LOGGING_LEVEL_WARNING != 2 { opts_ok = false; }
  if types.ORT_LOGGING_LEVEL_ERROR != 3 { opts_ok = false; }
  if types.ORT_LOGGING_LEVEL_FATAL != 4 { opts_ok = false; }
  failed = failed + report(opts_ok, "types: graph-opt / execution-mode / logging constants");

  var codes_ok = true;
  if types.ONNX_TYPE_UNKNOWN != 0 { codes_ok = false; }
  if types.ONNX_TYPE_TENSOR != 1 { codes_ok = false; }
  if types.ONNX_TYPE_OPTIONAL != 6 { codes_ok = false; }
  if types.ORT_OK != 0 { codes_ok = false; }
  if types.ORT_FAIL != 1 { codes_ok = false; }
  if types.ORT_INVALID_ARGUMENT != 2 { codes_ok = false; }
  if types.ORT_NO_SUCHFILE != 3 { codes_ok = false; }
  if types.ORT_INVALID_PROTOBUF != 7 { codes_ok = false; }
  if types.ORT_NOT_FOUND != 14 { codes_ok = false; }
  if types.ORT_DEVICE_RESET != 15 { codes_ok = false; }
  if types.ORT_ALLOCATOR_DEVICE != 0 { codes_ok = false; }
  if types.ORT_ALLOCATOR_ARENA != 1 { codes_ok = false; }
  if types.ORT_MEM_TYPE_CPU_OUTPUT != -1 { codes_ok = false; }
  if types.ORT_MEM_TYPE_DEFAULT != 0 { codes_ok = false; }
  failed = failed + report(codes_ok, "types: ONNXType / OrtErrorCode / allocator / mem-type constants");

  var sizes_ok = true;
  if types.ort_dtype_size(types.ORT_DTYPE_FLOAT) != 4 { sizes_ok = false; }
  if types.ort_dtype_size(types.ORT_DTYPE_DOUBLE) != 8 { sizes_ok = false; }
  if types.ort_dtype_size(types.ORT_DTYPE_BOOL) != 1 { sizes_ok = false; }
  if types.ort_dtype_size(types.ORT_DTYPE_FLOAT16) != 2 { sizes_ok = false; }
  if types.ort_dtype_size(types.ORT_DTYPE_STRING) != 0 { sizes_ok = false; }
  failed = failed + report(sizes_ok, "types: dtype byte sizes");

  var names_ok = true;
  if types.ort_error_code_name(types.ORT_FAIL) != "fail" { names_ok = false; }
  if types.ort_error_code_name(types.ORT_NO_SUCHFILE) != "no_suchfile" { names_ok = false; }
  if types.ort_error_code_name(types.ORT_DEVICE_RESET) != "device_reset" { names_ok = false; }
  if types.ort_error_code_name(999) != "" { names_ok = false; }
  failed = failed + report(names_ok, "types: OrtErrorCode names");

  // io.xi pure tensor helpers (kept from 0.1.0).
  var data: Vec[Float32] = Vec[Float32].new();
  data.push(1.0);
  data.push(2.0);
  data.push(3.0);
  var shape: Vec[Int] = Vec[Int].new();
  shape.push(1);
  shape.push(3);
  let t = tensor.onnx_tensor_from_vec(&data, &shape);
  var from_ok = t.name == "input" && t.data.len() == 3;
  if t.data[0] != 1.0 { from_ok = false; }
  if t.data[2] != 3.0 { from_ok = false; }
  if t.shape[0] != 1 { from_ok = false; }
  if t.shape[1] != 3 { from_ok = false; }
  if t.dtype != types.ORT_DTYPE_FLOAT { from_ok = false; }
  failed = failed + report(from_ok, "io: onnx_tensor_from_vec copies data and shape");

  data[0] = 99.0;
  failed = failed + report(t.data[0] == 1.0, "io: from_vec does not alias the source");

  let v = tensor.onnx_tensor_to_vec(&t);
  failed = failed + report(v.len() == 3 && v[0] == 1.0 && v[1] == 2.0 && v[2] == 3.0,
    "io: onnx_tensor_to_vec roundtrip");

  var v2 = tensor.onnx_tensor_to_vec(&t);
  v2[0] = 42.0;
  failed = failed + report(t.data[0] == 1.0, "io: to_vec does not alias the tensor");

  var shape1: Vec[Int] = Vec[Int].new();
  shape1.push(4);
  var z1 = tensor.onnx_tensor_zeros("features", &shape1);
  var z1_ok = z1.name == "features" && z1.data.len() == 4 && z1.shape[0] == 4;
  var zi = 0;
  while zi < 4 {
    if z1.data[zi] != 0.0 { z1_ok = false; }
    zi = zi + 1;
  };
  failed = failed + report(z1_ok, "io: zeros 1d (4)");

  var shape3: Vec[Int] = Vec[Int].new();
  shape3.push(2);
  shape3.push(3);
  shape3.push(4);
  let z3 = tensor.onnx_tensor_zeros("volume", &shape3);
  failed = failed + report(z3.data.len() == 24 && z3.shape[0] == 2 && z3.shape[1] == 3 && z3.shape[2] == 4,
    "io: zeros 3d (2x3x4)");

  shape3[0] = 999;
  failed = failed + report(z3.shape[0] == 2, "io: zeros does not alias the shape vector");

  failed = failed + report(tensor.onnx_tensor_get_name(&z1) == "features", "io: get_name");
  tensor.onnx_tensor_set_name(&mut z1, "renamed");
  failed = failed + report(tensor.onnx_tensor_get_name(&z1) == "renamed", "io: set_name");

  var px: Vec[Int] = Vec[Int].new();
  px.push(0);
  let pr1 = tensor.onnx_preprocess_image(&px, 2);
  failed = failed + report(pr1.shape.len() == 4 && pr1.shape[0] == 1 && pr1.shape[1] == 3 && pr1.shape[2] == 2 && pr1.shape[3] == 2 && pr1.data.len() == 12,
    "io: preprocess image NCHW shape (1x3x2x2)");

  var allzero = true;
  var pi = 0;
  while pi < pr1.data.len() {
    if pr1.data[pi] != 0.0 { allzero = false; }
    pi = pi + 1;
  };
  failed = failed + report(allzero, "io: preprocess image emits zeros (stub tier)");

  // Loader oracle: the declared surface is index-aligned and complete.
  let slots = onnx_surface_slots();
  let snames = onnx_surface_names();
  var surf_ok = slots.len() == 95 && snames.len() == 95;
  if snames[0] != "CreateStatus" { surf_ok = false; }
  if slots[0] != 0 { surf_ok = false; }
  if snames[94] != "SynchronizeBoundOutputs" { surf_ok = false; }
  if slots[94] != 203 { surf_ok = false; }
  if slots[42] != 216 { surf_ok = false; }
  if snames[42] != "SessionOptionsAppendExecutionProvider" { surf_ok = false; }
  failed = failed + report(surf_ok, "loader: declared surface 95 slots aligned with names");

  var min_ok = true;
  if onnx_parse_minor("1.31.0") != 31 { min_ok = false; }
  if onnx_parse_minor("1.17.1") != 17 { min_ok = false; }
  if onnx_parse_minor("1.14.1+cpu") != 14 { min_ok = false; }
  if onnx_parse_minor("1.9") != 9 { min_ok = false; }
  if onnx_parse_minor("garbage") != 0 { min_ok = false; }
  failed = failed + report(min_ok, "loader: version-minor parsing (1.31.0->31, +suffix, garbage->0)");

  let cands = onnx_load_candidates();
  var cand_ok = cands.len() >= 4;
  if cands[cands.len() - 4] != "onnxruntime.dll" { cand_ok = false; }
  if cands[cands.len() - 3] != "libonnxruntime.so" { cand_ok = false; }
  if cands[cands.len() - 2] != "libonnxruntime.so.1" { cand_ok = false; }
  if cands[cands.len() - 1] != "libonnxruntime.dylib" { cand_ok = false; }
  failed = failed + report(cand_ok, "loader: candidate order (XIOM_ONNX_RUNTIME override, then 4 sonames)");

  // Deterministic SKIP-path classification (every host, every run).
  let missing = onnx_load_named("xiom-absent-onnxruntime-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == types.ONNX_LOAD_ABSENT && missing.error.message.len() > 0,
      "skip-path: absent runtime classified ONNX_LOAD_ABSENT (SKIP)");
  }

  return failed;
}

// =========================================================================
// Live leg (SKIP when no runtime)
// =========================================================================

fn test_tensor_layer(lib: &OnnxLibrary, alloc: Int) -> Int {
  var failed = 0;

  let mir = value.onnx_memory_info_cpu(lib);
  if !mir.is_ok {
    return report(false, "mem-info: CreateCpuMemoryInfo -- " + mir.error.message);
  }
  let mem_info = mir.value;
  let mn = value.onnx_memory_info_name(lib, mem_info);
  let mi = value.onnx_memory_info_id(lib, mem_info);
  let mt = value.onnx_memory_info_mem_type(lib, mem_info);
  let ma = value.onnx_memory_info_type(lib, mem_info);
  var mi_ok = mn.is_ok && mn.value == "Cpu" && mi.is_ok && mi.value == 0;
  if mt.is_ok && mt.value != types.ORT_MEM_TYPE_DEFAULT { mi_ok = false; }
  if ma.is_ok && ma.value != types.ORT_ALLOCATOR_DEVICE { mi_ok = false; }
  failed = failed + report(mi_ok, "mem-info: cpu info name=Cpu id=0 mem_type=CPU allocator=device");

  let air = value.onnx_allocator_info(lib, alloc);
  var ainfo_ok = air.is_ok && air.value != 0;
  if ainfo_ok {
    let an = value.onnx_memory_info_name(lib, air.value);
    if an.is_ok && an.value != "Cpu" { ainfo_ok = false; }
  }
  failed = failed + report(ainfo_ok, "allocator: default allocator info reports Cpu memory");

  let abr = value.onnx_allocator_alloc(lib, alloc, 64);
  if !abr.is_ok {
    failed = failed + report(false, "allocator: AllocatorAlloc -- " + abr.error.message);
  } else {
    let blk = abr.value;
    unsafe {
      ffi.ptr_write_u8(blk as *UInt8, 171);
    }
    var readback = -1;
    unsafe {
      readback = ffi.ptr_read_u8(blk as *UInt8);
    }
    let fr = value.onnx_allocator_free(lib, alloc, blk);
    failed = failed + report(readback == 171 && fr.is_ok, "allocator: alloc/write/read/free 64 bytes");
  }

  var shape: Vec[Int] = Vec[Int].new();
  shape.push(2);
  let vr = value.onnx_value_tensor_new(lib, alloc, &shape, types.ORT_DTYPE_FLOAT);
  if !vr.is_ok {
    return failed + report(false, "tensor: CreateTensorAsOrtValue -- " + vr.error.message);
  }
  let tv = vr.value;

  let it = value.onnx_value_is_tensor(lib, tv);
  let dp = value.onnx_value_data_ptr(lib, tv);
  failed = failed + report(it.is_ok && it.value && dp.is_ok && dp.value != 0,
    "tensor: allocator-owned [2] FLOAT created (IsTensor + data pointer)");

  var d2: Vec[Float32] = Vec[Float32].new();
  d2.push(2.0);
  d2.push(3.0);
  let wr = value.onnx_value_write_f32(lib, tv, &d2);
  var rt_ok = false;
  if wr.is_ok {
    let rd = value.onnx_value_read_f32(lib, tv, 2);
    if rd.is_ok {
      rt_ok = rd.value.items.len() == 2 && rd.value.items[0] == 2.0 && rd.value.items[1] == 3.0;
    } else {
      why(rd.error.message);
    }
  } else {
    why(wr.error.message);
  }
  failed = failed + report(rt_ok, "tensor: write/read Float32 roundtrip exact (2.0, 3.0)");

  let vt = value.onnx_value_type(lib, tv);
  let vc = value.onnx_value_count(lib, tv);
  let vg = value.onnx_value_get(lib, tv, 0, alloc);
  let vmi = value.onnx_value_memory_info(lib, tv);
  var sem_ok = vt.is_ok && vt.value == types.ONNX_TYPE_TENSOR;
  if !vc.is_err { sem_ok = false; }   // tensors have no GetValueCount
  if !vg.is_err { sem_ok = false; }   // GetValue is for maps/sequences
  if vmi.is_ok && vmi.value == 0 { sem_ok = false; }
  failed = failed + report(sem_ok, "tensor: GetValueType=TENSOR; GetValueCount/GetValue fail on tensors (typed)");

  let tir = value.onnx_value_tensor_info(lib, tv);
  var ti_ok = false;
  if tir.is_ok {
    let ti = tir.value;
    let et = value.onnx_tensor_info_element_type(lib, ti);
    let dc = value.onnx_tensor_info_dims_count(lib, ti);
    let dims = value.onnx_tensor_info_dims(lib, ti);
    let sym = value.onnx_tensor_info_symbolic_dims(lib, ti);
    let sc = value.onnx_tensor_info_shape_count(lib, ti);
    ti_ok = et.is_ok && et.value == types.ORT_DTYPE_FLOAT;
    if dc.is_ok && dc.value != 1 { ti_ok = false; }
    if dims.is_ok && (dims.value.len() != 1 || dims.value[0] != 2) { ti_ok = false; }
    if sym.is_ok && (sym.value.len() != 1 || sym.value[0] != "") { ti_ok = false; }
    if sc.is_ok && sc.value != 2 { ti_ok = false; }
    value.onnx_tensor_info_free(lib, ti);
  } else {
    why(tir.error.message);
  }
  failed = failed + report(ti_ok, "tensor: type/shape info (FLOAT, dims [2], shape count 2, no symbols)");

  let tir2 = value.onnx_value_type_info(lib, tv);
  var vti_ok = false;
  if tir2.is_ok {
    let onnx_type = value.onnx_type_info_onnx_type(lib, tir2.value);
    let casted = value.onnx_type_info_tensor(lib, tir2.value);
    vti_ok = onnx_type.is_ok && onnx_type.value == types.ONNX_TYPE_TENSOR && casted.is_ok && casted.value != 0;
    value.onnx_type_info_free(lib, tir2.value);
  }
  failed = failed + report(vti_ok, "tensor: GetTypeInfo -> ONNX_TYPE_TENSOR + CastTypeInfoToTensorInfo");

  value.onnx_value_free(lib, tv);

  // Borrowed-buffer tensor: writes through GetTensorMutableData land in the
  // caller's Vec (no copy, no free).
  var buf: Vec[Float32] = Vec[Float32].new();
  buf.push(7.0);
  buf.push(8.0);
  let bv = value.onnx_value_tensor_from_data(lib, mem_info, &buf, &shape, types.ORT_DTYPE_FLOAT);
  var alias_ok = false;
  if bv.is_ok {
    let wr2 = value.onnx_value_write_f32(lib, bv.value, &d2);
    alias_ok = wr2.is_ok && buf[0] == 2.0 && buf[1] == 3.0;
    let rd2 = value.onnx_value_read_f32(lib, bv.value, 2);
    if rd2.is_ok {
      alias_ok = alias_ok && rd2.value.items[0] == 2.0 && rd2.value.items[1] == 3.0;
    }
    value.onnx_value_free(lib, bv.value);
  } else {
    why(bv.error.message);
  }
  failed = failed + report(alias_ok, "tensor: borrowed-buffer value aliases the caller Vec (write-through)");

  value.onnx_memory_info_free(lib, mem_info);
  return failed;
}

fn test_session_layer(lib: &OnnxLibrary, envh: Int, alloc: Int) -> Int {
  var failed = 0;

  // Fixture bytes.
  let fr = fs.fs_read(FIXTURE);
  if !fr.is_ok {
    return report(false, "fixture: cannot read " + FIXTURE);
  }
  let model: Vec[UInt8] = fr.value;
  failed = failed + report(model.len() == 110, "fixture: add_f32.onnx is 110 bytes");

  // Session options: every setter + config entry + provider append.
  let or_ = session.onnx_session_options_new(lib);
  if !or_.is_ok {
    return failed + report(false, "options: CreateSessionOptions -- " + or_.error.message);
  }
  let opts = or_.value;
  let s1 = session.onnx_options_set_intra_threads(lib, opts, 2);
  let s2 = session.onnx_options_set_inter_threads(lib, opts, 1);
  let s3 = session.onnx_options_set_graph_opt(lib, opts, types.ORT_GRAPH_OPT_BASIC);
  let s4 = session.onnx_options_set_execution_mode(lib, opts, types.ORT_EXECUTION_MODE_SEQUENTIAL);
  let s5 = session.onnx_options_set_log_id(lib, opts, "xiom.onnx.suite");
  let s6 = session.onnx_options_set_log_verbosity(lib, opts, 3);
  let s7 = session.onnx_options_set_log_severity(lib, opts, types.ORT_LOGGING_LEVEL_WARNING);
  let s8 = session.onnx_options_enable_mem_pattern(lib, opts);
  let s9 = session.onnx_options_disable_mem_pattern(lib, opts);
  let s10 = session.onnx_options_enable_cpu_arena(lib, opts);
  let s11 = session.onnx_options_disable_cpu_arena(lib, opts);
  let s12 = session.onnx_options_enable_profiling(lib, opts, "onnx_suite_prof");
  let s13 = session.onnx_options_disable_profiling(lib, opts);
  var setters_ok = s1.is_ok && s2.is_ok && s3.is_ok && s4.is_ok && s5.is_ok && s6.is_ok && s7.is_ok;
  setters_ok = setters_ok && s8.is_ok && s9.is_ok && s10.is_ok && s11.is_ok && s12.is_ok && s13.is_ok;
  if !setters_ok {
    if !s1.is_ok { why("intra: " + s1.error.message); }
    if !s13.is_ok { why("profiling: " + s13.error.message); }
  }
  failed = failed + report(setters_ok, "options: all 13 setters accepted (threads/log/mem/profiling/mode/graph)");
  let cr = session.onnx_options_add_config(lib, opts, "session.intra_op.allow_spinning", "0");
  let ar = session.onnx_options_append_provider(lib, opts, "CPUExecutionProvider");
  let br = session.onnx_options_append_provider(lib, opts, "XiomNoSuchProvider");
  // ORT's generic appender lists a version-specific provider set: newer
  // builds accept "CPUExecutionProvider"; 1.17.x rejects it with its own
  // "Unknown provider name" oracle error. Both are accepted here; an
  // unknown name must always fail.
  var cpu_ok = ar.is_ok;
  if !cpu_ok {
    if contains(ar.error.message, "Unknown provider name") { cpu_ok = true; }
  }
  var opt_detail = "";
  if !cr.is_ok { opt_detail = opt_detail + " config=" + cr.error.message; }
  if !cpu_ok { opt_detail = opt_detail + " cpu=" + ar.error.message; }
  if !br.is_err { opt_detail = opt_detail + " bogus-provider unexpectedly accepted"; }
  failed = failed + report(cr.is_ok && cpu_ok && br.is_err,
    "options: config entry ok; CPU provider appended (or oracle rejection); bogus provider typed error" + opt_detail);

  // Session from the fixture by wide path (ORTCHAR_T on Windows).
  let sr = session.onnx_session_new(lib, envh, opts, FIXTURE);
  if !sr.is_ok {
    session.onnx_session_options_free(lib, opts);
    return failed + report(false, "session: CreateSession(path) -- " + sr.error.message);
  }
  let sess = sr.value;
  session.onnx_session_options_free(lib, opts);

  // Session from bytes (in-memory path).
  let sr2 = session.onnx_session_new_from_bytes(lib, envh, 0, &model);
  var from_bytes_ok = sr2.is_ok;
  var sess2 = 0;
  if sr2.is_ok { sess2 = sr2.value; }
  failed = failed + report(from_bytes_ok, "session: CreateSessionFromArray accepted the fixture model");

  let ic = session.onnx_session_input_count(lib, sess);
  let oc = session.onnx_session_output_count(lib, sess);
  failed = failed + report(ic.is_ok && ic.value == 2 && oc.is_ok && oc.value == 1,
    "session: input count 2 / output count 1");

  let n0 = session.onnx_session_input_name(lib, sess, 0);
  let n1 = session.onnx_session_input_name(lib, sess, 1);
  let n2 = session.onnx_session_output_name(lib, sess, 0);
  failed = failed + report(n0.is_ok && n0.value == "A" && n1.is_ok && n1.value == "B" && n2.is_ok && n2.value == "C",
    "session: names A / B / C");

  let all_in = session.onnx_session_input_names(lib, sess);
  let all_out = session.onnx_session_output_names(lib, sess);
  failed = failed + report(all_in.is_ok && all_in.value.items.len() == 2 && all_out.is_ok && all_out.value.items.len() == 1 && all_out.value.items[0] == "C",
    "session: bulk name queries (2 in / 1 out)");

  // Input/output type info on the session.
  let tir = session.onnx_session_input_type_info(lib, sess, 0);
  var ti_ok = false;
  if tir.is_ok {
    let casted = value.onnx_type_info_tensor(lib, tir.value);
    if casted.is_ok {
      let et = value.onnx_tensor_info_element_type(lib, casted.value);
      let dims = value.onnx_tensor_info_dims(lib, casted.value);
      ti_ok = et.is_ok && et.value == types.ORT_DTYPE_FLOAT && dims.is_ok && dims.value.len() == 1 && dims.value[0] == 2;
    }
    value.onnx_type_info_free(lib, tir.value);
  }
  failed = failed + report(ti_ok, "session: input[0] type info FLOAT dims [2]");

  let tor = session.onnx_session_output_type_info(lib, sess, 0);
  var to_ok = false;
  if tor.is_ok {
    let onnx_type = value.onnx_type_info_onnx_type(lib, tor.value);
    to_ok = onnx_type.is_ok && onnx_type.value == types.ONNX_TYPE_TENSOR;
    value.onnx_type_info_free(lib, tor.value);
  }
  failed = failed + report(to_ok, "session: output[0] type info is a tensor");

  // Model metadata.
  let mr = session.onnx_metadata_new(lib, sess);
  var md_ok = false;
  var md_detail = "";
  if mr.is_ok {
    let producer = session.onnx_metadata_producer(lib, mr.value);
    let graph = session.onnx_metadata_graph_name(lib, mr.value);
    let ver = session.onnx_metadata_version(lib, mr.value);
    let dom = session.onnx_metadata_domain(lib, mr.value);
    md_ok = producer.is_ok && producer.value == "xiom.onnx conformance";
    if graph.is_ok && graph.value != "g" { md_ok = false; }
    // ORT reports INT64_MAX when the model has no model_version (oracle:
    // C smoke + python cross-check).
    if ver.is_ok && ver.value != 9223372036854775807 { md_ok = false; }
    if !dom.is_ok { md_ok = false; }
    if producer.is_ok { md_detail = "producer='" + producer.value + "'"; }
    session.onnx_metadata_free(lib, mr.value);
  }
  failed = failed + report(md_ok, "session: metadata producer/graph/version/domain " + md_detail);

  // Run options roundtrip.
  let ro = session.onnx_run_options_new(lib);
  var ro_ok = false;
  if ro.is_ok {
    let v1 = session.onnx_run_options_set_verbosity(lib, ro.value, 4);
    let v2 = session.onnx_run_options_set_severity(lib, ro.value, types.ORT_LOGGING_LEVEL_ERROR);
    let v3 = session.onnx_run_options_set_tag(lib, ro.value, "xiom-run-tag");
    let g1 = session.onnx_run_options_get_verbosity(lib, ro.value);
    let g2 = session.onnx_run_options_get_severity(lib, ro.value);
    let g3 = session.onnx_run_options_get_tag(lib, ro.value);
    ro_ok = v1.is_ok && v2.is_ok && v3.is_ok;
    if g1.is_ok && g1.value != 4 { ro_ok = false; }
    if g2.is_ok && g2.value != types.ORT_LOGGING_LEVEL_ERROR { ro_ok = false; }
    if g3.is_ok && g3.value != "xiom-run-tag" { ro_ok = false; }
    session.onnx_run_options_free(lib, ro.value);
  }
  failed = failed + report(ro_ok, "run-options: verbosity/severity/tag set + read back");

  // Low-level Run: A=[2,3] + B=[4,5] -> C=[6,8], with RunOptions attached.
  var shape: Vec[Int] = Vec[Int].new();
  shape.push(2);
  var a: Vec[Float32] = Vec[Float32].new();
  a.push(2.0); a.push(3.0);
  var b: Vec[Float32] = Vec[Float32].new();
  b.push(4.0); b.push(5.0);
  let va = value.onnx_value_tensor_new(lib, alloc, &shape, types.ORT_DTYPE_FLOAT);
  let vb = value.onnx_value_tensor_new(lib, alloc, &shape, types.ORT_DTYPE_FLOAT);
  let wa = value.onnx_value_write_f32(lib, va.value, &a);
  let wb = value.onnx_value_write_f32(lib, vb.value, &b);
  var names: Vec[Str] = Vec[Str].new();
  names.push("A");
  names.push("B");
  var vals: Vec[Int] = Vec[Int].new();
  vals.push(va.value);
  vals.push(vb.value);
  var outs: Vec[Str] = Vec[Str].new();
  outs.push("C");
  let ro2 = session.onnx_run_options_new(lib);
  var run_ok = false;
  if wa.is_ok && wb.is_ok && ro2.is_ok {
    let rr = session.onnx_session_run(lib, sess, ro2.value, &names, &vals, &outs);
    if rr.is_ok {
      let orv = value.onnx_value_read_f32(lib, rr.value[0], 2);
      if orv.is_ok {
        run_ok = orv.value.items[0] == 6.0 && orv.value.items[1] == 8.0;
        if !run_ok { why("got [" + ist((orv.value.items[0]) as Int) + "?]"); }
      } else {
        why(orv.error.message);
      }
      value.onnx_value_free(lib, rr.value[0]);
    } else {
      why(rr.error.message);
    }
  }
  if ro2.is_ok { session.onnx_run_options_free(lib, ro2.value); }
  failed = failed + report(run_ok, "run: A(2,3)+B(4,5) -> C(6,8) exact through Run + RunOptions");

  // Run error path: a bogus input name is a typed ORT error.
  var bad_names: Vec[Str] = Vec[Str].new();
  bad_names.push("NOT_AN_INPUT");
  var bad_vals: Vec[Int] = Vec[Int].new();
  bad_vals.push(va.value);
  let bad = session.onnx_session_run(lib, sess, 0, &bad_names, &bad_vals, &outs);
  failed = failed + report(bad.is_err && bad.error.kind == loader.ONNX_CALL_FAILED,
    "run: bogus input name -> typed ONNX_CALL_FAILED");

  // Session-owned allocator: create/alloc/free/release.
  let mir = value.onnx_memory_info_cpu(lib);
  var salloc_ok = false;
  if mir.is_ok {
    let car = value.onnx_allocator_create(lib, sess, mir.value);
    if car.is_ok {
      let ab = value.onnx_allocator_alloc(lib, car.value, 32);
      if ab.is_ok {
        let f1 = value.onnx_allocator_free(lib, car.value, ab.value);
        salloc_ok = f1.is_ok;
      } else {
        why(ab.error.message);
      }
      value.onnx_allocator_release(lib, car.value);
    } else {
      why(car.error.message);
    }
    value.onnx_memory_info_free(lib, mir.value);
  }
  failed = failed + report(salloc_ok, "allocator: session-owned CreateAllocator alloc/free + release");

  // IoBinding: inputs + output-to-device, then clear.
  var bind_ok = false;
  let bir = session.onnx_io_binding_new(lib, sess);
  if bir.is_ok {
    let bnd = bir.value;
    var miok = value.onnx_memory_info_cpu(lib);
    let b1 = session.onnx_binding_bind_input(lib, bnd, "A", va.value);
    let b2 = session.onnx_binding_bind_input(lib, bnd, "B", vb.value);
    var b3r: Result[Unit, OnnxError] = Err(OnnxError{ kind: 0; message: "unset" });
    if miok.is_ok {
      b3r = session.onnx_binding_bind_output_to_device(lib, bnd, "C", miok.value);
    }
    let sy1 = session.onnx_binding_sync_inputs(lib, bnd);
    let sy2 = session.onnx_binding_sync_outputs(lib, bnd);
    if b1.is_ok && b2.is_ok && b3r.is_ok && sy1.is_ok && sy2.is_ok {
      let rrun = session.onnx_binding_run(lib, sess, 0, bnd);
      if rrun.is_ok {
        let onames = session.onnx_binding_output_names(lib, bnd);
        let ovals = session.onnx_binding_output_values(lib, bnd);
        if onames.is_ok && ovals.is_ok && ovals.value.len() == 1 {
          bind_ok = onames.value.items.len() == 1 && onames.value.items[0] == "C";
          let orv = value.onnx_value_read_f32(lib, ovals.value[0], 2);
          if orv.is_ok {
            bind_ok = bind_ok && orv.value.items[0] == 6.0 && orv.value.items[1] == 8.0;
          } else {
            why(orv.error.message);
          }
          var oi = 0;
          while oi < ovals.value.len() {
            value.onnx_value_free(lib, ovals.value[oi]);
            oi = oi + 1;
          };
        } else {
          bind_ok = false;
          if !onames.is_ok { why(onames.error.message); }
          if !ovals.is_ok { why(ovals.error.message); }
        }
        let cl1 = session.onnx_binding_clear_inputs(lib, bnd);
        let cl2 = session.onnx_binding_clear_outputs(lib, bnd);
        if !cl1.is_ok || !cl2.is_ok { bind_ok = false; }
        let after = session.onnx_binding_output_values(lib, bnd);
        if after.is_ok && after.value.len() != 0 { bind_ok = false; }
      } else {
        why(rrun.error.message);
      }
    } else {
      if !b1.is_ok { why(b1.error.message); }
      if !b2.is_ok { why(b2.error.message); }
      if !b3r.is_ok { why(b3r.error.message); }
    }
    value.onnx_memory_info_free(lib, miok.value);
    session.onnx_io_binding_free(lib, bnd);
  }
  failed = failed + report(bind_ok, "io-binding: bind A/B + output-to-device + run -> C[6,8], clear verified");

  // IoBinding: preallocated output value receives the result (alias proof),
  // and a bogus input name is a typed error.
  var prealloc_ok = false;
  let bir2 = session.onnx_io_binding_new(lib, sess);
  if bir2.is_ok {
    let bnd = bir2.value;
    let cv = value.onnx_value_tensor_new(lib, alloc, &shape, types.ORT_DTYPE_FLOAT);
    let b1 = session.onnx_binding_bind_input(lib, bnd, "A", va.value);
    let b2 = session.onnx_binding_bind_input(lib, bnd, "B", vb.value);
    let b3 = session.onnx_binding_bind_output(lib, bnd, "C", cv.value);
    if b1.is_ok && b2.is_ok && b3.is_ok {
      let rrun = session.onnx_binding_run(lib, sess, 0, bnd);
      if rrun.is_ok {
        let orv = value.onnx_value_read_f32(lib, cv.value, 2);
        if orv.is_ok {
          prealloc_ok = orv.value.items[0] == 6.0 && orv.value.items[1] == 8.0;
        } else {
          why(orv.error.message);
        }
      } else {
        why(rrun.error.message);
      }
    }
    let bad_b = session.onnx_binding_bind_input(lib, bnd, "NOT_THERE", va.value);
    if !bad_b.is_err { prealloc_ok = false; }
    value.onnx_value_free(lib, cv.value);
    session.onnx_io_binding_free(lib, bnd);
  }
  failed = failed + report(prealloc_ok, "io-binding: preallocated output value filled in place ([6,8]); bogus name typed error");

  // Corrupted model bytes: typed error with the ORT tag.
  var junk: Vec[UInt8] = Vec[UInt8].new();
  junk.push(1); junk.push(2); junk.push(3); junk.push(4); junk.push(5);
  let bads = session.onnx_session_new_from_bytes(lib, envh, 0, &junk);
  failed = failed + report(bads.is_err && bads.error.kind == loader.ONNX_CALL_FAILED && bads.error.message.len() > 0,
    "session: corrupted model bytes -> typed error");

  value.onnx_value_free(lib, va.value);
  value.onnx_value_free(lib, vb.value);
  if sess2 != 0 { session.onnx_session_free(lib, sess2); }
  session.onnx_session_free(lib, sess);
  return failed;
}

fn test_high_level(lib: &OnnxLibrary) -> Int {
  var failed = 0;

  let cfg = onnx_config_default();
  let mr = session.onnx_load_model(FIXTURE, &cfg);
  if !mr.is_ok {
    return report(false, "high-level: load_model -- " + mr.error);
  }
  let model = mr.value;
  failed = failed + report(session.onnx_get_input_count(&model) == 2 && session.onnx_get_output_count(&model) == 1,
    "high-level: load_model counts 2 in / 1 out (path preserved)");
  var names_ok = model.path == FIXTURE && model.input_names.len() == 2 && model.input_names[0] == "A";
  if model.input_names[1] != "B" { names_ok = false; }
  if model.output_names.len() != 1 { names_ok = false; }
  if model.output_names[0] != "C" { names_ok = false; }
  failed = failed + report(names_ok, "high-level: model carries path + A/B/C names");

  var sh: Vec[Int] = Vec[Int].new();
  sh.push(2);
  var tin: Vec[OnnxTensor] = Vec[OnnxTensor].new();
  var t1 = tensor.onnx_tensor_zeros("A", &sh);
  t1.data[0] = 2.0;
  t1.data[1] = 3.0;
  var t2 = tensor.onnx_tensor_zeros("B", &sh);
  t2.data[0] = 4.0;
  t2.data[1] = 5.0;
  tin.push(t1);
  tin.push(t2);
  let rr = session.onnx_run(&model, &tin);
  var run_ok = false;
  if rr.is_ok {
    let out = rr.value.items;
    run_ok = out.len() == 1 && out[0].name == "C" && out[0].data.len() == 2;
    if run_ok {
      run_ok = out[0].data[0] == 6.0 && out[0].data[1] == 8.0;
      run_ok = run_ok && out[0].shape.len() == 1 && out[0].shape[0] == 2 && out[0].dtype == types.ORT_DTYPE_FLOAT;
    }
  } else {
    why(rr.error);
  }
  failed = failed + report(run_ok, "high-level: onnx_run A+B -> C[6,8] with shape [2] and FLOAT dtype");

  session.onnx_close(&model);

  let mr2 = session.onnx_load_model("tests/fixtures/definitely-missing.onnx", &cfg);
  var err_ok = false;
  if mr2.is_err {
    err_ok = mr2.error.len() > 0;
  }
  failed = failed + report(err_ok, "high-level: missing model file -> Err(load message)");

  return failed;
}

fn test_live() -> Int {
  var failed = 0;
  let lr = onnx_load();
  if !lr.is_ok {
    if lr.error.kind == types.ONNX_LOAD_ABSENT {
      return report(true, "live: SKIP -- no onnxruntime candidate present (" + lr.error.message + ")");
    }
    return report(false, "live: runtime present but unusable -- " + lr.error.message);
  }
  let lib: OnnxLibrary = lr.value;

  let info = onnx_probe(&lib);
  var probe_ok = info.version.len() > 0 && info.resolved == info.required && info.resolved == 95;
  if info.api_version < 1 { probe_ok = false; }
  if onnx_parse_minor(info.version) != info.api_version { probe_ok = false; }
  failed = failed + report(probe_ok,
    "live: " + info.soname + " " + info.version + " (api " + ist(info.api_version) + ", surface " + ist(info.resolved) + "/" + ist(info.required) + ")");

  let sp = onnx_status_probe(&lib, "xiom status probe");
  failed = failed + report(sp.is_ok && sp.value == types.ORT_FAIL,
    "live: status trio CreateStatus/GetErrorCode/GetErrorMessage/ReleaseStatus roundtrip");

  let er = env.onnx_env_new_level(&lib, types.ORT_LOGGING_LEVEL_WARNING, "xiom.onnx.suite");
  if !er.is_ok {
    let crc = onnx_close(&lib);
    return failed + report(false, "live: CreateEnv -- " + er.error.message);
  }
  let envh = er.value;
  let te = env.onnx_telemetry_set(&lib, envh, true);
  let td = env.onnx_telemetry_set(&lib, envh, false);
  failed = failed + report(te.is_ok && td.is_ok, "live: EnableTelemetryEvents + DisableTelemetryEvents");

  let pr = env.onnx_available_providers(&lib);
  var prov_ok = false;
  var prov_detail = "";
  if pr.is_ok {
    var ii = 0;
    while ii < pr.value.items.len() {
      if pr.value.items[ii] == "CPUExecutionProvider" { prov_ok = true; }
      prov_detail = prov_detail + pr.value.items[ii] + " ";
      ii = ii + 1;
    };
  } else {
    why(pr.error.message);
  }
  failed = failed + report(prov_ok, "live: GetAvailableProviders contains CPUExecutionProvider (" + prov_detail + ")");

  let ar = value.onnx_allocator_default(&lib);
  if !ar.is_ok {
    env.onnx_env_free(&lib, envh);
    let crc = onnx_close(&lib);
    return failed + report(false, "live: default allocator -- " + ar.error.message);
  }
  let alloc = ar.value;

  failed = failed + test_tensor_layer(&lib, alloc);
  failed = failed + test_session_layer(&lib, envh, alloc);
  failed = failed + test_high_level(&lib);

  env.onnx_env_free(&lib, envh);
  let cr = onnx_close(&lib);
  failed = failed + report(cr.is_ok, "live: runtime handle released");

  return failed;
}

// =========================================================================
// Driver
// =========================================================================

pub fn main() -> Int {
  io.println("=== xiom.onnx conformance tests (ONNX Runtime C API loader + live inference) ===");
  io.flush_stdout();
  var failed: Int = 0;
  failed = failed + test_pure();
  failed = failed + test_live();
  return finish(failed);
}
