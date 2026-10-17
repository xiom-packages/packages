// probe_real_backend.xi -- REAL Arrow backend probe (Phase 2, evidence-only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// NOT part of port.ps1 (the conformance suite stays offline via the
// deterministic stub leg of bridge/arrow_bridge.c). This probe links
// bridge/arrow_real.cpp against Apache Arrow C++ and exercises the real
// backend layer end to end:
//
//   1. backend identity: arrow_backend_available()/version() and the pinned
//      Arrow C Data Interface layout (ArrowSchema=72, ArrowArray=80 bytes);
//   2. typed construction: Int64 + Float64 arrays from raw XIOM buffers, a
//      2-field struct schema, and a real arrow::RecordBatch;
//   3. zero-copy handoff: arrow_record_batch_export writes a real
//      (ArrowSchema, ArrowArray) pair into caller-owned 72/80-byte slots,
//      arrow_record_batch_import moves it back into a batch -- the imported
//      column buffer address is IDENTICAL to the producer's buffer address;
//   4. ownership handoff: import consumes the pair (both release pointers
//      become NULL: schema_release/array_release report false); the
//      non-import path releases the exported structs exactly once and the
//      original handle stays valid afterwards.
//
// Invocation (Windows, from the repo root). The ABI gate requires the SAME
// MSVC-family Arrow build for headers and libraries; the verified runtime is
// the pyarrow 22.0.0 win_amd64 wheel (see SPEC.md "Real backend / ABI gate"):
//
//   $arrow = "E:\repos\arrow-bin\pyarrow-22.0.0"
//   $env:CPLUS_INCLUDE_PATH = "$arrow\pyarrow\include"
//   $env:PATH = "$arrow\pyarrow;$arrow\pyarrow.libs;$env:PATH"
//   xiom --run packages\xiom-arrow\tests\probe_real_backend.xi `
//       --cxx-standard 17 `
//       --c-source packages\xiom-arrow\bridge\arrow_real.cpp `
//       --link arrow --link arrow_compute --link arrow_acero `
//       --link-path "$arrow\pyarrow"
//
// Exit code = number of failures. With the offline stub bridge linked the
// probe fails closed at step 1 (backend unavailable), never silently passes.
module arrow_real_backend_probe

use xiom.arrow;
use xiom.io;
use xiom.ffi;
use xiom.encoding;
use xiom.convert;

extern "C" {
  fn xiom_arrow_cdi_layout_check() -> Int;
  fn xiom_arrow_cdi_detail() -> *UInt8;
}

fn cstr_from_str(s: Str) -> Result[SafePtr, Str] {
  var bytes: Vec[UInt8] = encoding.utf8_encode(s);
  let n: Int = bytes.len();
  let alloc = ffi.safe_ptr_alloc(n + 1);
  match alloc {
    Ok(sp) => {
      var handle = sp;
      var i: Int = 0;
      while i < n {
        let w = ffi.safe_ptr_write_byte(&mut handle, i, bytes[i] as Int);
        match w {
          Ok(_) => {},
          Err(e) => { return Err(e); },
        };
        i = i + 1;
      };
      let z = ffi.safe_ptr_write_byte(&mut handle, n, 0);
      match z {
        Ok(_) => {},
        Err(e) => { return Err(e); },
      };
      return Ok(handle);
    },
    Err(e) => { return Err(e); },
  };
}

fn safe_addr(sp: &SafePtr) -> Int
  requires: true
{
  unsafe { return sp.ptr as Int; }
}

fn vec_i64_ptr(v: &mut Vec[Int]) -> Int
  requires: true
{
  unsafe { return v.as_mut_ptr() as Int; }
}

fn vec_f64_ptr(v: &mut Vec[Float64]) -> Int
  requires: true
{
  unsafe { return v.as_mut_ptr() as Int; }
}

fn write_i64(slot: &mut SafePtr, offset: Int, value: Int) -> Bool {
  match ffi.safe_ptr_write_i64(slot, offset, value) {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  };
}

fn print_err(what: Str, detail: Str) {
  io.println("[FAIL] " + what + ": " + detail);
}

pub fn main() -> Int {
  io.println("=== xiom.arrow real backend probe ===");
  io.println("");

  // -- 1. Backend identity + CDI layout. --------------------------------
  let ver = backend_version();
  if !backend_available() || ver.len() == 0 {
    io.println("[FAIL] real backend not linked (stub bridge): backend_version='" + ver + "'");
    return 1;
  };
  io.println("[PASS] real backend linked: Apache Arrow C++ " + ver);

  let layout = unsafe { xiom_arrow_cdi_layout_check() };
  let layout_detail = unsafe { Str::from_c_str(xiom_arrow_cdi_detail()) };
  if layout != 0 {
    print_err("CDI layout", layout_detail);
    return 1;
  };
  io.println("[PASS] CDI layout: " + layout_detail);

  // -- 2. Struct schema: x: int64, y: float64. ---------------------------
  let name_x = match cstr_from_str("x") {
    Ok(sp) => sp,
    Err(e) => { print_err("probe setup name_x", e); return 1; },
  };
  let name_y = match cstr_from_str("y") {
    Ok(sp) => sp,
    Err(e) => { print_err("probe setup name_y", e); return 1; },
  };
  let fmt_l = match cstr_from_str("l") {
    Ok(sp) => sp,
    Err(e) => { print_err("probe setup fmt_l", e); return 1; },
  };
  let fmt_g = match cstr_from_str("g") {
    Ok(sp) => sp,
    Err(e) => { print_err("probe setup fmt_g", e); return 1; },
  };

  let names_alloc = ffi.safe_ptr_alloc(16);
  let formats_alloc = ffi.safe_ptr_alloc(16);
  var names = match names_alloc {
    Ok(sp) => sp,
    Err(e) => { print_err("probe setup names", e); return 1; },
  };
  var formats = match formats_alloc {
    Ok(sp) => sp,
    Err(e) => { print_err("probe setup formats", e); return 1; },
  };
  if !write_i64(&mut names, 0, safe_addr(&name_x)) { print_err("names[0]", "write failed"); return 1; };
  if !write_i64(&mut names, 8, safe_addr(&name_y)) { print_err("names[1]", "write failed"); return 1; };
  if !write_i64(&mut formats, 0, safe_addr(&fmt_l)) { print_err("formats[0]", "write failed"); return 1; };
  if !write_i64(&mut formats, 8, safe_addr(&fmt_g)) { print_err("formats[1]", "write failed"); return 1; };

  let schema_result = schema_create_struct(safe_addr(&names), safe_addr(&formats), 2);
  let schema = match schema_result {
    Ok(h) => h,
    Err(e) => { print_err("schema_create_struct", e); return 1; },
  };
  ffi.safe_ptr_free(name_x);
  ffi.safe_ptr_free(name_y);
  ffi.safe_ptr_free(fmt_l);
  ffi.safe_ptr_free(fmt_g);
  ffi.safe_ptr_free(names);
  ffi.safe_ptr_free(formats);
  io.println("[PASS] struct schema created (x: l, y: g)");

  // -- 3. Typed arrays from raw XIOM buffers. ---------------------------
  var ivals: Vec[Int] = Vec[Int].new();
  ivals.push(42);
  ivals.push(-7);
  ivals.push(0);
  ivals.push(123456789);
  ivals.push(-1);
  let int_result = array_from_int64(vec_i64_ptr(&mut ivals), 5);
  let ints = match int_result {
    Ok(h) => h,
    Err(e) => { print_err("array_from_int64", e); return 1; },
  };

  var fvals: Vec[Float64] = Vec[Float64].new();
  fvals.push(1.5);
  fvals.push(-2.25);
  fvals.push(0.0);
  fvals.push(3.5);
  fvals.push(4.75);
  let float_result = array_from_float64(vec_f64_ptr(&mut fvals), 5);
  let floats = match float_result {
    Ok(h) => h,
    Err(e) => { print_err("array_from_float64", e); return 1; },
  };
  if array_get_length(ints) != 5 || array_get_length(floats) != 5 {
    print_err("typed arrays", "length != 5");
    return 1;
  };
  io.println("[PASS] typed arrays: int64[5] and float64[5]");

  // -- 4. Record batch. --------------------------------------------------
  var cols: Vec[Int] = Vec[Int].new();
  cols.push(ints);
  cols.push(floats);
  let batch_result = record_batch_create(schema, 2, vec_i64_ptr(&mut cols));
  let batch = match batch_result {
    Ok(h) => h,
    Err(e) => { print_err("record_batch_create", e); return 1; },
  };
  if array_get_length(batch) != 5 {
    print_err("record batch", "num_rows != 5");
    return 1;
  };
  let batch_schema = match record_batch_get_schema(batch) {
    Ok(h) => h,
    Err(e) => { print_err("record_batch_get_schema", e); return 1; },
  };
  let batch_fmt = match schema_get_format(batch_schema) {
    Ok(p) => unsafe { Str::from_c_str(p as *UInt8) },
    Err(e) => { print_err("batch schema format", e); return 1; },
  };
  if batch_fmt != "+s" {
    print_err("record batch", "schema format is '" + batch_fmt + "', expected '+s'");
    return 1;
  };
  io.println("[PASS] record batch: 5 rows, schema format '+s'");

  // -- 5. Export -> import (zero copy). ---------------------------------
  let sslot_alloc = ffi.safe_ptr_alloc(72);
  let aslot_alloc = ffi.safe_ptr_alloc(80);
  var sslot = match sslot_alloc {
    Ok(sp) => sp,
    Err(e) => { print_err("probe setup schema slot", e); return 1; },
  };
  var aslot = match aslot_alloc {
    Ok(sp) => sp,
    Err(e) => { print_err("probe setup array slot", e); return 1; },
  };
  let export_result = record_batch_export(batch, safe_addr(&sslot), safe_addr(&aslot));
  match export_result {
    Ok(_) => {},
    Err(e) => { print_err("record_batch_export", e); return 1; },
  };
  io.println("[PASS] export filled the CDI struct pair (72/80 bytes)");

  let import_result = record_batch_import(safe_addr(&sslot), safe_addr(&aslot));
  let imported = match import_result {
    Ok(h) => h,
    Err(e) => { print_err("record_batch_import", e); return 1; },
  };
  if schema_release(safe_addr(&sslot)) {
    print_err("ownership", "import left the schema release pointer live");
    return 1;
  };
  if array_release(safe_addr(&aslot)) {
    print_err("ownership", "import left the array release pointer live");
    return 1;
  };
  io.println("[PASS] import consumed the pair (release pointers NULL)");

  if array_get_length(imported) != 5 {
    print_err("imported batch", "num_rows != 5");
    return 1;
  };
  let icol0 = match record_batch_get_column(imported, 0) {
    Ok(h) => h,
    Err(e) => { print_err("imported column 0", e); return 1; },
  };
  let icol1 = match record_batch_get_column(imported, 1) {
    Ok(h) => h,
    Err(e) => { print_err("imported column 1", e); return 1; },
  };
  let orig_buf = match array_get_buffer(ints, 1) {
    Ok(p) => p,
    Err(e) => { print_err("origin int64 buffer", e); return 1; },
  };
  let imported_buf = match array_get_buffer(icol0, 1) {
    Ok(p) => p,
    Err(e) => { print_err("imported int64 buffer", e); return 1; },
  };
  if orig_buf != imported_buf {
    print_err("zero-copy", "imported int64 buffer address differs from producer");
    return 1;
  };
  io.println("[PASS] zero-copy: imported int64 buffer == producer buffer");

  let raw_ints = unsafe { ffi.safe_ptr_from_raw(imported_buf as *UInt8, 40) };
  let raw_ints_sp = match raw_ints {
    Ok(sp) => sp,
    Err(e) => { print_err("read imported int64 buffer", e); return 1; },
  };
  let first_int = match ffi.safe_ptr_read_i64(&raw_ints_sp, 0) {
    Ok(v) => v,
    Err(e) => { print_err("read first int64", e); return 1; },
  };
  if first_int != 42 {
    print_err("imported data", "first int64 != 42");
    return 1;
  };
  ffi.safe_ptr_free(raw_ints_sp);

  let float_buf = match array_get_buffer(icol1, 1) {
    Ok(p) => p,
    Err(e) => { print_err("imported float64 buffer", e); return 1; },
  };
  let raw_floats = unsafe { ffi.safe_ptr_from_raw(float_buf as *UInt8, 40) };
  let raw_floats_sp = match raw_floats {
    Ok(sp) => sp,
    Err(e) => { print_err("read imported float64 buffer", e); return 1; },
  };
  let first_float = match ffi.safe_ptr_read_f64(&raw_floats_sp, 0) {
    Ok(v) => v,
    Err(e) => { print_err("read first float64", e); return 1; },
  };
  if first_float != 1.5 {
    print_err("imported data", "first float64 != 1.5");
    return 1;
  };
  ffi.safe_ptr_free(raw_floats_sp);
  io.println("[PASS] imported values intact (42, 1.5)");

  // -- 6. Release path (export without import). -------------------------
  let sslot2_alloc = ffi.safe_ptr_alloc(72);
  let aslot2_alloc = ffi.safe_ptr_alloc(80);
  var sslot2 = match sslot2_alloc {
    Ok(sp) => sp,
    Err(e) => { print_err("probe setup second schema slot", e); return 1; },
  };
  var aslot2 = match aslot2_alloc {
    Ok(sp) => sp,
    Err(e) => { print_err("probe setup second array slot", e); return 1; },
  };
  match record_batch_export(batch, safe_addr(&sslot2), safe_addr(&aslot2)) {
    Ok(_) => {},
    Err(e) => { print_err("second record_batch_export", e); return 1; },
  };
  if !schema_release(safe_addr(&sslot2)) {
    print_err("release path", "schema_release reported already released");
    return 1;
  };
  if schema_release(safe_addr(&sslot2)) {
    print_err("release path", "second schema_release was not a no-op");
    return 1;
  };
  if !array_release(safe_addr(&aslot2)) {
    print_err("release path", "array_release reported already released");
    return 1;
  };
  if array_release(safe_addr(&aslot2)) {
    print_err("release path", "second array_release was not a no-op");
    return 1;
  };
  if array_get_length(batch) != 5 {
    print_err("release path", "producer batch invalidated by struct release");
    return 1;
  };
  io.println("[PASS] release path: exactly-once release, producer handle intact");

  // -- 7. Cleanup. -------------------------------------------------------
  ffi.safe_ptr_free(sslot);
  ffi.safe_ptr_free(aslot);
  ffi.safe_ptr_free(sslot2);
  ffi.safe_ptr_free(aslot2);
  array_free(icol0);
  array_free(icol1);
  array_free(imported);
  array_free(batch);
  array_free(ints);
  array_free(floats);
  schema_free(batch_schema);
  schema_free(schema);

  io.println("");
  io.println("probe_real_backend: all checks passed");
  return 0;
}
