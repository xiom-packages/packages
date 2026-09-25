// XIOM -- xiom.gguf conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: minimal header layout and alignment padding,
// every KV value family (integers with sign extension, bool, string, f32
// raw-hex, arrays), tensor info accessors, the general.alignment override,
// the builder round-trip, and the full error catalog (bad magic/version,
// truncation, unknown type, NUL/non-printable strings, u64 out of Int
// range, nested arrays, invalid alignment, tensor offsets past the data
// section, duplicates, not-found accessors).
//
// Harness style mirrors xiom.safetensors: one fn tN() -> Int per check,
// called directly from main; main prints [PASS]/[FAIL] and returns the
// failure count. Str payloads are compared with str_compare and every Vec
// element read is bound to a typed local.

module gguf_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.gguf;

// --------------------------------------------------
//  Harness helpers
// --------------------------------------------------

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn expect_gguf_err(r: Result[Gguf, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

fn expect_int_err(r: Result[Int, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

fn expect_str_err(r: Result[Str, Str], want: Str, name: Str) -> Int {
  if r.is_ok {
    return report(false, name + " (expected Err)");
  }
  let got: Str = r.error;
  if !str_eq(got, want) {
    return report(false, name + " (got: " + got + ")");
  }
  return report(true, name);
}

// Zero-filled byte vector of length `n` (for truncation fixtures).
fn zero_bytes(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push((0 as UInt8));
    i = i + 1;
  }
  return v;
}

// First `n` bytes of `src` as a fresh vector.
fn copy_prefix(src: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let raw: UInt8 = src[i];
    v.push(raw);
    i = i + 1;
  }
  return v;
}

// Minimal valid buffer: version 3, no KVs, no tensors.
fn minimal() -> Vec[UInt8] {
  let b = gguf_builder_new();
  let r = gguf_builder_finish(&b);
  return r.value;
}

// Buffer with exactly one u32 KV ("k" = 7): 41 header bytes padded to 64.
fn one_int_kv() -> Vec[UInt8] {
  var b = gguf_builder_new();
  let ar = gguf_builder_add_kv_int(&mut b, "k", 4, 7);
  let r = gguf_builder_finish(&b);
  return r.value;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

// Minimal header: counts 0, default alignment 32, data offset 32.
fn t1() -> Int {
  let buf = minimal();
  let r = gguf_parse(&buf);
  if !r.is_ok {
    return report(false, "minimal header parses");
  }
  let g = r.value;
  if gguf_version(&g) != 3 {
    return report(false, "minimal header: version 3");
  }
  if gguf_kv_count(&g) != 0 {
    return report(false, "minimal header: 0 KVs");
  }
  if gguf_tensor_count(&g) != 0 {
    return report(false, "minimal header: 0 tensors");
  }
  if gguf_alignment(&g) != 32 {
    return report(false, "minimal header: alignment 32");
  }
  if gguf_data_offset(&g) != 32 {
    return report(false, "minimal header: data offset 32");
  }
  return report(gguf_data_len(&g) == 0, "minimal header: empty data section");
}

// Bad magic byte.
fn t2() -> Int {
  var buf = minimal();
  buf[0] = 7;
  let r = gguf_parse(&buf);
  return expect_gguf_err(r, "gguf: bad magic", "bad magic rejected");
}

// Unsupported version 1.
fn t3() -> Int {
  var buf = minimal();
  buf[4] = 1;
  buf[5] = 0;
  buf[6] = 0;
  buf[7] = 0;
  let r = gguf_parse(&buf);
  return expect_gguf_err(r, "gguf: unsupported version", "version 1 rejected");
}

// Short buffer.
fn t4() -> Int {
  let buf = zero_bytes(20);
  let r = gguf_parse(&buf);
  return expect_gguf_err(r, "gguf: buffer too small for header", "short buffer rejected");
}

// u32 KV accessors.
fn t5() -> Int {
  let buf = one_int_kv();
  let r = gguf_parse(&buf);
  if !r.is_ok {
    return report(false, "u32 KV parses");
  }
  let g = r.value;
  let fr = gguf_find_kv(&g, "k");
  if !fr.is_ok {
    return report(false, "u32 KV: find");
  }
  let i = fr.value;
  let tr = gguf_kv_type(&g, i);
  let vr = gguf_kv_int(&g, i);
  return report(tr.value == 4 && vr.value == 7, "u32 KV: type and value");
}

// String KV.
fn t6() -> Int {
  var b = gguf_builder_new();
  let ar = gguf_builder_add_kv_str(&mut b, "general.name", "hello");
  let buf = gguf_builder_finish(&b).value;
  let r = gguf_parse(&buf);
  if !ar.is_ok || !r.is_ok {
    return report(false, "string KV parses");
  }
  let g = r.value;
  let fr = gguf_find_kv(&g, "general.name");
  let sr = gguf_kv_str(&g, fr.value);
  return report(str_eq(sr.value, "hello"), "string KV: value");
}

// Bool KV.
fn t7() -> Int {
  var b = gguf_builder_new();
  let ar = gguf_builder_add_kv_int(&mut b, "flag", 7, 1);
  let buf = gguf_builder_finish(&b).value;
  let r = gguf_parse(&buf);
  if !ar.is_ok || !r.is_ok {
    return report(false, "bool KV parses");
  }
  let g = r.value;
  let fr = gguf_find_kv(&g, "flag");
  let vr = gguf_kv_int(&g, fr.value);
  return report(vr.value == 1, "bool KV: true");
}

// Negative i8 sign extension through the builder and parser.
fn t8() -> Int {
  var b = gguf_builder_new();
  let ar = gguf_builder_add_kv_int(&mut b, "x", 1, -5);
  let buf = gguf_builder_finish(&b).value;
  let r = gguf_parse(&buf);
  if !ar.is_ok || !r.is_ok {
    return report(false, "i8 KV parses");
  }
  let g = r.value;
  let fr = gguf_find_kv(&g, "x");
  let vr = gguf_kv_int(&g, fr.value);
  return report(vr.value == -5, "i8 KV: negative round-trip");
}

// Integer array KV.
fn t9() -> Int {
  var vals = Vec[Int].new();
  vals.push(1);
  vals.push(2);
  vals.push(3);
  var b = gguf_builder_new();
  let ar = gguf_builder_add_kv_arr_int(&mut b, "dims", 4, &vals);
  let buf = gguf_builder_finish(&b).value;
  let r = gguf_parse(&buf);
  if !ar.is_ok || !r.is_ok {
    return report(false, "array KV parses");
  }
  let g = r.value;
  let fr = gguf_find_kv(&g, "dims");
  let i = fr.value;
  let et = gguf_kv_arr_type(&g, i);
  let cn = gguf_kv_arr_count(&g, i);
  let e0 = gguf_kv_arr_int(&g, i, 0);
  let e2 = gguf_kv_arr_int(&g, i, 2);
  if et.value != 4 || cn.value != 3 {
    return report(false, "array KV: type/count");
  }
  return report(e0.value == 1 && e2.value == 3, "array KV: elements");
}

// f32 raw-byte hex KV.
fn t10() -> Int {
  var b = gguf_builder_new();
  let ar = gguf_builder_add_kv_float(&mut b, "f", 6, "0000803f");
  let buf = gguf_builder_finish(&b).value;
  let r = gguf_parse(&buf);
  if !ar.is_ok || !r.is_ok {
    return report(false, "f32 KV parses");
  }
  let g = r.value;
  let fr = gguf_find_kv(&g, "f");
  let sr = gguf_kv_str(&g, fr.value);
  return report(str_eq(sr.value, "0000803f"), "f32 KV: raw hex preserved");
}

// Tensor info accessors.
fn t11() -> Int {
  var dims = Vec[Int].new();
  dims.push(2);
  dims.push(3);
  var b = gguf_builder_new();
  let ar = gguf_builder_add_tensor(&mut b, "tok_emb", &dims, 0, 0);
  let buf = gguf_builder_finish(&b).value;
  let r = gguf_parse(&buf);
  if !ar.is_ok || !r.is_ok {
    return report(false, "tensor info parses");
  }
  let g = r.value;
  if gguf_tensor_count(&g) != 1 {
    return report(false, "tensor info: count");
  }
  let nr = gguf_tensor_name(&g, 0);
  let rr = gguf_tensor_ndims(&g, 0);
  let d0 = gguf_tensor_dim(&g, 0, 0);
  let d1 = gguf_tensor_dim(&g, 0, 1);
  let ty = gguf_tensor_type(&g, 0);
  let of = gguf_tensor_offset(&g, 0);
  if !str_eq(nr.value, "tok_emb") || rr.value != 2 {
    return report(false, "tensor info: name/rank");
  }
  if d0.value != 2 || d1.value != 3 {
    return report(false, "tensor info: dims");
  }
  return report(ty.value == 0 && of.value == 0, "tensor info: type/offset");
}

// Duplicate tensor names are rejected by the builder.
fn t12() -> Int {
  var dims = Vec[Int].new();
  dims.push(1);
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_tensor(&mut b, "t", &dims, 0, 0);
  let a2 = gguf_builder_add_tensor(&mut b, "t", &dims, 0, 0);
  if !a1.is_ok {
    return report(false, "duplicate tensor: first add ok");
  }
  return expect_int_err(a2, "gguf: duplicate tensor name", "duplicate tensor rejected");
}

// Custom alignment affects the data offset.
fn t13() -> Int {
  var b = gguf_builder_new();
  let sr = gguf_builder_set_alignment(&mut b, 64);
  let buf = gguf_builder_finish(&b).value;
  let r = gguf_parse(&buf);
  if !sr.is_ok || !r.is_ok {
    return report(false, "alignment 64 parses");
  }
  let g = r.value;
  return report(gguf_alignment(&g) == 64 && gguf_data_offset(&g) == 64, "alignment 64 honoured");
}

// Non-power-of-two alignment rejected by the builder.
fn t14() -> Int {
  var b = gguf_builder_new();
  let sr = gguf_builder_set_alignment(&mut b, 48);
  return expect_int_err(sr, "gguf: alignment is not a power of two", "alignment 48 rejected");
}

// Unknown KV value type rejected by the parser.
fn t15() -> Int {
  var buf = one_int_kv();
  buf[33] = 13;
  let r = gguf_parse(&buf);
  return expect_gguf_err(r, "gguf: unknown value type", "unknown value type rejected");
}

// NUL byte inside a key rejected by the parser.
fn t16() -> Int {
  var buf = one_int_kv();
  buf[32] = 0;
  let r = gguf_parse(&buf);
  return expect_gguf_err(r, "gguf: string contains NUL byte", "NUL in key rejected");
}

// u64 value with the sign bit set rejected (does not fit Int).
fn t17() -> Int {
  var buf = one_int_kv();
  buf[33] = 10;
  buf[44] = 128;
  let r = gguf_parse(&buf);
  return expect_gguf_err(r, "gguf: integer out of Int range", "u64 out of Int range rejected");
}

// Nested arrays rejected.
fn t18() -> Int {
  var buf = one_int_kv();
  buf[33] = 9;
  buf[37] = 9;
  let r = gguf_parse(&buf);
  return expect_gguf_err(r, "gguf: nested arrays are not supported", "nested array rejected");
}

// Declared value truncated by the buffer end.
fn t19() -> Int {
  let full = one_int_kv();
  let buf = copy_prefix(&full, 40);
  let r = gguf_parse(&buf);
  return expect_gguf_err(r, "gguf: truncated value", "truncated value rejected");
}

// Builder round-trip across every supported family plus two tensors.
fn t20() -> Int {
  var vals = Vec[Int].new();
  vals.push(10);
  vals.push(20);
  var d1 = Vec[Int].new();
  d1.push(4);
  var d2 = Vec[Int].new();
  d2.push(8);
  d2.push(8);
  var b = gguf_builder_new();
  let a1 = gguf_builder_add_kv_int(&mut b, "block_count", 4, 3);
  let a2 = gguf_builder_add_kv_str(&mut b, "general.name", "model");
  let a3 = gguf_builder_add_kv_int(&mut b, "general.alignment", 4, 32);
  let a4 = gguf_builder_add_kv_arr_int(&mut b, "dims", 4, &vals);
  let a5 = gguf_builder_add_kv_float(&mut b, "f", 6, "0000803f");
  let a6 = gguf_builder_add_tensor(&mut b, "a", &d1, 0, 0);
  let a7 = gguf_builder_add_tensor(&mut b, "b", &d2, 6, 16);
  if !a1.is_ok || !a2.is_ok || !a3.is_ok || !a4.is_ok || !a5.is_ok || !a6.is_ok || !a7.is_ok {
    return report(false, "round-trip: builder adds");
  }
  let fr = gguf_builder_finish(&b);
  if !fr.is_ok {
    return report(false, "round-trip: finish");
  }
  var buf = fr.value;
  // Append a payload so the declared tensor offsets (0 and 16) are valid.
  var pad = 0;
  while pad < 32 {
    buf.push((0 as UInt8));
    pad = pad + 1;
  }
  let r = gguf_parse(&buf);
  if !r.is_ok {
    return report(false, "round-trip: parse");
  }
  let g = r.value;
  if gguf_kv_count(&g) != 5 || gguf_tensor_count(&g) != 2 {
    return report(false, "round-trip: counts");
  }
  let i1 = gguf_find_kv(&g, "block_count");
  let i2 = gguf_find_kv(&g, "dims");
  let n1 = gguf_kv_int(&g, i1.value);
  let n2 = gguf_kv_arr_count(&g, i2.value);
  let e1 = gguf_kv_arr_int(&g, i2.value, 1);
  let t1r = gguf_find_tensor(&g, "a");
  let t2r = gguf_find_tensor(&g, "b");
  let o2 = gguf_tensor_offset(&g, t2r.value);
  if n1.value != 3 || n2.value != 2 || e1.value != 20 {
    return report(false, "round-trip: KV values");
  }
  return report(t1r.value == 0 && o2.value == 16, "round-trip: tensors");
}

// Tensor offset past the data section rejected.
fn t21() -> Int {
  var d = Vec[Int].new();
  d.push(1);
  var b = gguf_builder_new();
  let ar = gguf_builder_add_tensor(&mut b, "t", &d, 0, 32);
  let buf = gguf_builder_finish(&b).value;
  let r = gguf_parse(&buf);
  return expect_gguf_err(r, "gguf: tensor offset exceeds data section", "offset past data section rejected");
}

// find_kv with a missing key.
fn t22() -> Int {
  let buf = minimal();
  let r = gguf_parse(&buf);
  let g = r.value;
  let fr = gguf_find_kv(&g, "missing");
  return expect_int_err(fr, "gguf: key not found", "missing key reported");
}

// find_tensor with a missing name.
fn t23() -> Int {
  let buf = minimal();
  let r = gguf_parse(&buf);
  let g = r.value;
  let fr = gguf_find_tensor(&g, "missing");
  return expect_int_err(fr, "gguf: tensor not found", "missing tensor reported");
}

// Type name table.
fn t24() -> Int {
  let a = gguf_type_name(6);
  let b = gguf_type_name(13);
  return report(str_eq(a, "f32") && str_eq(b, "unknown"), "type names");
}

// --------------------------------------------------
//  Main
// --------------------------------------------------

fn main() -> Int {
  var failed = 0;
  failed = failed + t1();
  failed = failed + t2();
  failed = failed + t3();
  failed = failed + t4();
  failed = failed + t5();
  failed = failed + t6();
  failed = failed + t7();
  failed = failed + t8();
  failed = failed + t9();
  failed = failed + t10();
  failed = failed + t11();
  failed = failed + t12();
  failed = failed + t13();
  failed = failed + t14();
  failed = failed + t15();
  failed = failed + t16();
  failed = failed + t17();
  failed = failed + t18();
  failed = failed + t19();
  failed = failed + t20();
  failed = failed + t21();
  failed = failed + t22();
  failed = failed + t23();
  failed = failed + t24();
  if failed == 0 {
    io.println("xiom.gguf: all tests passed");
  }
  return failed;
}
