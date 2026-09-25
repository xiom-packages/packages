// XIOM -- xiom.iso8583 conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the pure-XIOM xiom.iso8583 codec against the documented ASCII
// layout: 4-digit MTI, 16/32-digit hex bitmap (bit 1 MSB-first) or 64/128
// binary digits, fixed and LLVAR/LLLVAR fields for the documented subset,
// the field dictionary, the deterministic error catalog and round-trips.
//
// The two wire fixtures are assembled from pinned literal pieces:
//   primary (8 fields: 2,3,4,7,11,39,41,49) -> bitmap 7220000002808000
//   secondary (11 fields, adds 32,48,70)     -> bitmap
//     F2200001028180000400000000000000 (field 70 forces the secondary part)
// Expected bitmaps were computed independently of src/iso8583.xi.
//
// Str equality goes through xiom.string.compare.str_compare (BUG 17
// discipline: `==` on a Str value lowers to a pointer comparison); control
// bytes used in bad-value tests are pushed as bytes, never written as Str
// literals, and 0x00 is never produced (sb_to_str aborts on NUL).

module iso8583_tests
use xiom.io; use xiom.test;
use xiom.iso8583;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Helpers (independent of src/iso8583.xi)
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Bytes of a Str literal.
fn vb(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// Bytes of `prefix` + one control byte + `suffix`.
fn vb_with(prefix: Str, ctl: Int, suffix: Str) -> Vec[UInt8] {
  var v = vb(prefix);
  v.push(ctl as UInt8);
  var i = 0;
  while i < suffix.len() {
    v.push(string.byte_at(suffix, i));
    i = i + 1;
  }
  return v;
}

// Str of `prefix` + one control byte + `suffix` (control byte must not be
// 0x00); used to build malformed wire texts.
fn wire_with_ctl(prefix: Str, ctl: Int, suffix: Str) -> Str {
  var sb = Vec[UInt8].new();
  builder.sb_push_str(&mut sb, prefix);
  builder.sb_push_byte(&mut sb, ctl as UInt8);
  builder.sb_push_str(&mut sb, suffix);
  return builder.sb_to_str(&sb);
}

fn repeat_str(s: Str, n: Int) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < n {
    builder.sb_push_str(&mut sb, s);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

fn err_msg_is(r: Result[Iso8583Message, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bitmap_is(r: Result[Iso8583Bitmap, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn wire_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let got: Str = r.value;
  return str_eq(got, want);
}

fn numbers_are(m: &Iso8583Message, want: Vec[Int]) -> Bool {
  if iso8583_field_count(m) != want.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    let w: Int = want[i];
    if iso8583_field_number(m, i) != w {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn bitmap_numbers_are(b: &Iso8583Bitmap, want: Vec[Int]) -> Bool {
  if b.numbers.len() != want.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    let w: Int = want[i];
    let got: Int = b.numbers[i];
    if got != w {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn field_is(m: &Iso8583Message, number: Int, want: Str) -> Bool {
  let r = iso8583_get(m, number);
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return str_eq(v, want);
}

fn value_at_is(m: &Iso8583Message, i: Int, want: Str) -> Bool {
  let v: Str = iso8583_field_value(m, i);
  return str_eq(v, want);
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// primary-only wire, fields 2,3,4,7,11,39,41,49
fn wire_primary() -> Str {
  return "0200" + "7220000002808000" +
    "16" + "4111111111111111" +
    "000000" +
    "000000010000" +
    "0915120000" +
    "123456" +
    "00" +
    "TERM0001" +
    "EUR";
}

// wire with the secondary bitmap, fields 2,3,4,7,11,32,39,41,48,49,70
fn wire_secondary() -> Str {
  return "0200" + "F2200001028180000400000000000000" +
    "16" + "4111111111111111" +
    "000000" +
    "000000010000" +
    "0915120000" +
    "123456" +
    "11" + "12345678901" +
    "00" +
    "TERM0001" +
    "010" + "ADDPRIVATE" +
    "EUR" +
    "001";
}

fn numbers_primary() -> Vec[Int] {
  var n = Vec[Int].new();
  n.push(2);
  n.push(3);
  n.push(4);
  n.push(7);
  n.push(11);
  n.push(39);
  n.push(41);
  n.push(49);
  return n;
}

fn numbers_secondary() -> Vec[Int] {
  var n = Vec[Int].new();
  n.push(2);
  n.push(3);
  n.push(4);
  n.push(7);
  n.push(11);
  n.push(32);
  n.push(39);
  n.push(41);
  n.push(48);
  n.push(49);
  n.push(70);
  return n;
}

fn values_primary() -> Vec[Vec[UInt8]] {
  var v = Vec[Vec[UInt8]].new();
  v.push(vb("4111111111111111"));
  v.push(vb("000000"));
  v.push(vb("000000010000"));
  v.push(vb("0915120000"));
  v.push(vb("123456"));
  v.push(vb("00"));
  v.push(vb("TERM0001"));
  v.push(vb("EUR"));
  return v;
}

fn values_secondary() -> Vec[Vec[UInt8]] {
  var v = Vec[Vec[UInt8]].new();
  v.push(vb("4111111111111111"));
  v.push(vb("000000"));
  v.push(vb("000000010000"));
  v.push(vb("0915120000"));
  v.push(vb("123456"));
  v.push(vb("12345678901"));
  v.push(vb("00"));
  v.push(vb("TERM0001"));
  v.push(vb("ADDPRIVATE"));
  v.push(vb("EUR"));
  v.push(vb("001"));
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let w = wire_primary();
  let r = iso8583_parse(w);
  if !r.is_ok {
    return assert(false, "primary parse: MTI, bitmap, field numbers and values");
  }
  let m: Iso8583Message = r.value;
  var ok = str_eq(iso8583_mti(&m), "0200");
  if iso8583_has_secondary(&m) { ok = false; }
  if !numbers_are(&m, numbers_primary()) { ok = false; }
  if !field_is(&m, 2, "4111111111111111") { ok = false; }
  if !field_is(&m, 3, "000000") { ok = false; }
  if !field_is(&m, 4, "000000010000") { ok = false; }
  if !field_is(&m, 7, "0915120000") { ok = false; }
  if !field_is(&m, 11, "123456") { ok = false; }
  if !field_is(&m, 39, "00") { ok = false; }
  if !field_is(&m, 41, "TERM0001") { ok = false; }
  if !field_is(&m, 49, "EUR") { ok = false; }
  if !value_at_is(&m, 0, "4111111111111111") { ok = false; }
  if !value_at_is(&m, 7, "EUR") { ok = false; }
  if !str_eq(iso8583_bitmap_hex(&m), "7220000002808000") { ok = false; }
  return assert(ok, "primary parse: MTI, bitmap, field numbers and values");
}

fn t2() -> TestResult {
  let w = wire_secondary();
  let r = iso8583_parse(w);
  if !r.is_ok {
    return assert(false, "secondary parse: has_secondary, 48/70 and bitmap");
  }
  let m: Iso8583Message = r.value;
  var ok = iso8583_has_secondary(&m);
  if !numbers_are(&m, numbers_secondary()) { ok = false; }
  if !field_is(&m, 32, "12345678901") { ok = false; }
  if !field_is(&m, 48, "ADDPRIVATE") { ok = false; }
  if !field_is(&m, 70, "001") { ok = false; }
  if iso8583_has_field(&m, 5) { ok = false; }
  if iso8583_field_index(&m, 70) != 10 { ok = false; }
  if !str_eq(iso8583_bitmap_hex(&m), "F2200001028180000400000000000000") { ok = false; }
  return assert(ok, "secondary parse: has_secondary, 48/70 and bitmap");
}

fn t3() -> TestResult {
  let ns = numbers_primary();
  let vs = values_primary();
  let br = iso8583_build("0200", &ns, &vs);
  var ok = wire_is(br, wire_primary());
  let ns2 = numbers_secondary();
  let vs2 = values_secondary();
  let br2 = iso8583_build("0200", &ns2, &vs2);
  if !wire_is(br2, wire_secondary()) { ok = false; }
  let mr = iso8583_build_message("0200", &ns2, &vs2);
  if !mr.is_ok { ok = false; } else {
    let m: Iso8583Message = mr.value;
    if !numbers_are(&m, numbers_secondary()) { ok = false; }
    let fr = iso8583_format(&m);
    if !wire_is(fr, wire_secondary()) { ok = false; }
  }
  return assert(ok, "build and build_message reproduce both wire fixtures");
}

fn t4() -> TestResult {
  let np = numbers_primary();
  let vp = values_primary();
  let ns = numbers_secondary();
  let vs = values_secondary();
  var ok = wire_is(iso8583_build_with_bitmap("0200", "7220000002808000", &np, &vp), wire_primary());
  let bin_a = "0111001000100000000000000000000000000010100000001000000000000000";
  if !wire_is(iso8583_build_with_bitmap("0200", bin_a, &np, &vp), wire_primary()) { ok = false; }
  let hex_b = "F2200001028180000400000000000000";
  if !wire_is(iso8583_build_with_bitmap("0200", hex_b, &ns, &vs), wire_secondary()) { ok = false; }
  let bin_b = "11110010001000000000000000000001000000101000000110000000000000000000010000000000000000000000000000000000000000000000000000000000";
  if !wire_is(iso8583_build_with_bitmap("0200", bin_b, &ns, &vs), wire_secondary()) { ok = false; }
  if !err_str_is(iso8583_build_with_bitmap("0200", "7220000002808000", &ns, &vs), "iso8583: bitmap/fields mismatch") { ok = false; }
  if !err_str_is(iso8583_build_with_bitmap("0200", hex_b, &np, &vp), "iso8583: bitmap/fields mismatch") { ok = false; }
  if !err_str_is(iso8583_build_with_bitmap("0200", "4000000000000000", &np, &vp), "iso8583: bitmap/fields mismatch") { ok = false; }
  return assert(ok, "build_with_bitmap: hex/binary forms agree, mismatches rejected");
}

fn t5() -> TestResult {
  var ok = false;
  let ra = iso8583_bitmap_parse("7220000002808000");
  if ra.is_ok {
    let b: Iso8583Bitmap = ra.value;
    ok = !b.has_secondary;
    if !bitmap_numbers_are(&b, numbers_primary()) { ok = false; }
  }
  let rb = iso8583_bitmap_parse("F2200001028180000400000000000000");
  if rb.is_ok {
    let b: Iso8583Bitmap = rb.value;
    if !b.has_secondary { ok = false; }
    if !bitmap_numbers_are(&b, numbers_secondary()) { ok = false; }
  } else {
    ok = false;
  }
  let rl = iso8583_bitmap_parse("f2200001028180000400000000000000");
  if rl.is_ok {
    let b: Iso8583Bitmap = rl.value;
    if !b.has_secondary { ok = false; }
    if !bitmap_numbers_are(&b, numbers_secondary()) { ok = false; }
  } else {
    ok = false;
  }
  let bin_b = "11110010001000000000000000000001000000101000000110000000000000000000010000000000000000000000000000000000000000000000000000000000";
  let rbin = iso8583_bitmap_parse(bin_b);
  if rbin.is_ok {
    let b: Iso8583Bitmap = rbin.value;
    if !bitmap_numbers_are(&b, numbers_secondary()) { ok = false; }
  } else {
    ok = false;
  }
  let np = numbers_primary();
  if !wire_is(iso8583_bitmap_of(&np), "7220000002808000") { ok = false; }
  let ns = numbers_secondary();
  if !wire_is(iso8583_bitmap_of(&ns), "F2200001028180000400000000000000") { ok = false; }
  var none = Vec[Int].new();
  if !wire_is(iso8583_bitmap_of(&none), "0000000000000000") { ok = false; }
  let rzero = iso8583_bitmap_parse("0000000000000000");
  if !rzero.is_ok { ok = false; } else {
    let bz: Iso8583Bitmap = rzero.value;
    if bz.numbers.len() != 0 { ok = false; }
    if bz.has_secondary { ok = false; }
  }
  return assert(ok, "bitmap_parse/bitmap_of: hex, binary, lowercase, empty");
}

fn t6() -> TestResult {
  var ok = err_bitmap_is(iso8583_bitmap_parse("zz00000000000000"), "iso8583: bad bitmap hex");
  if !err_bitmap_is(iso8583_bitmap_parse("722000000280800"), "iso8583: bad bitmap length") { ok = false; }
  if !err_bitmap_is(iso8583_bitmap_parse(""), "iso8583: bad bitmap length") { ok = false; }
  if !err_bitmap_is(iso8583_bitmap_parse("8000000000000000"), "iso8583: bad bitmap length") { ok = false; }
  let bad_bin = "0111001000100000000000000000000000000010100000001000000000000002";
  if !err_bitmap_is(iso8583_bitmap_parse(bad_bin), "iso8583: bad bitmap binary") { ok = false; }
  let one_bin = "1" + repeat_str("0", 63);
  if !err_bitmap_is(iso8583_bitmap_parse(one_bin), "iso8583: bad bitmap length") { ok = false; }
  if !err_bitmap_is(iso8583_bitmap_parse("00000000000000004000000000000000"), "iso8583: unexpected secondary bitmap") { ok = false; }
  if !err_bitmap_is(iso8583_bitmap_parse("F220000102818000C400000000000000"), "iso8583: tertiary bitmap not supported") { ok = false; }
  return assert(ok, "bitmap errors: hex, binary, length, secondary, tertiary");
}

fn t7() -> TestResult {
  let bm2 = "4000000000000000";
  let d19 = "1234567890123456789";
  let rmax = iso8583_parse("0200" + bm2 + "19" + d19);
  var ok = false;
  if rmax.is_ok {
    let m: Iso8583Message = rmax.value;
    ok = field_is(&m, 2, d19);
  }
  let rempty = iso8583_parse("0200" + bm2 + "00");
  if !rempty.is_ok { ok = false; } else {
    let m: Iso8583Message = rempty.value;
    if !field_is(&m, 2, "") { ok = false; }
    if iso8583_field_count(&m) != 1 { ok = false; }
  }
  if !err_msg_is(iso8583_parse("0200" + bm2 + "20" + repeat_str("9", 20)), "iso8583: bad field length") { ok = false; }
  if !err_msg_is(iso8583_parse("0200" + bm2 + "0x12345"), "iso8583: bad field length") { ok = false; }
  if !err_msg_is(iso8583_parse("0200" + bm2 + "19" + "12345"), "iso8583: length overrun") { ok = false; }
  return assert(ok, "LLVAR field 2: max 19, empty, bad prefix, overrun");
}

fn t8() -> TestResult {
  let bm48 = "0000000000010000";
  let long = repeat_str("A", 300);
  var ok = false;
  let r = iso8583_parse("0200" + bm48 + "300" + long);
  if r.is_ok {
    let m: Iso8583Message = r.value;
    ok = field_is(&m, 48, long);
    if !str_eq(iso8583_bitmap_hex(&m), bm48) { ok = false; }
    let fr = iso8583_format(&m);
    if !wire_is(fr, "0200" + bm48 + "300" + long) { ok = false; }
  }
  if !err_msg_is(iso8583_parse("0200" + bm48 + "abc" + long), "iso8583: bad field length") { ok = false; }
  if !err_msg_is(iso8583_parse("0200" + bm48 + "999" + long), "iso8583: length overrun") { ok = false; }
  let bad48 = wire_with_ctl("0200" + bm48 + "010" + "ABCDEFGHI", 31, "");
  if !err_msg_is(iso8583_parse(bad48), "iso8583: bad field value") { ok = false; }
  return assert(ok, "LLLVAR field 48: 300-char round-trip and prefix errors");
}

fn t9() -> TestResult {
  var ok = err_msg_is(iso8583_parse(""), "iso8583: bad mti");
  if !err_msg_is(iso8583_parse("020"), "iso8583: bad mti") { ok = false; }
  if !err_msg_is(iso8583_parse("02A0" + "7220000002808000"), "iso8583: bad mti") { ok = false; }
  if !err_msg_is(iso8583_parse("0200"), "iso8583: bad bitmap hex") { ok = false; }
  if !err_msg_is(iso8583_parse("0200" + "72200000028080"), "iso8583: bad bitmap hex") { ok = false; }
  if !err_msg_is(iso8583_parse("0200" + "722000000280800Z"), "iso8583: bad bitmap hex") { ok = false; }
  if !err_msg_is(iso8583_parse("0200" + "8000000000000000"), "iso8583: bad bitmap length") { ok = false; }
  if !err_msg_is(iso8583_parse("0200" + "F220000102818000C400000000000000" + "16" + "4111111111111111"), "iso8583: tertiary bitmap not supported") { ok = false; }
  return assert(ok, "parse errors: bad MTI and truncated/tertiary bitmap");
}

fn t10() -> TestResult {
  var ok = err_msg_is(iso8583_parse("0200" + "0800000000000000" + "AA"), "iso8583: unknown field number");
  if !err_bitmap_is(iso8583_bitmap_parse("0800000000000000"), "iso8583: unknown field number") { ok = false; }
  if !err_bitmap_is(iso8583_bitmap_parse("00000000000000040000000000000000"), "iso8583: unknown field number") { ok = false; }
  var n5 = Vec[Int].new();
  n5.push(5);
  var v1 = Vec[Vec[UInt8]].new();
  v1.push(vb("AB"));
  if !err_msg_is(iso8583_build_message("0200", &n5, &v1), "iso8583: unknown field number") { ok = false; }
  if !err_str_is(iso8583_bitmap_of(&n5), "iso8583: unknown field number") { ok = false; }
  var n1 = Vec[Int].new();
  n1.push(1);
  if !err_str_is(iso8583_bitmap_of(&n1), "iso8583: unknown field number") { ok = false; }
  var n129 = Vec[Int].new();
  n129.push(129);
  if !err_str_is(iso8583_bitmap_of(&n129), "iso8583: unknown field number") { ok = false; }
  return assert(ok, "unknown field numbers are rejected everywhere");
}

fn t11() -> TestResult {
  var ok = err_msg_is(iso8583_parse("0200" + "2000000000000000"), "iso8583: declared field missing");
  if !err_msg_is(iso8583_parse("0200" + "4000000000000000"), "iso8583: declared field missing") { ok = false; }
  if !err_msg_is(iso8583_parse("0200" + "2000000000000000" + "123"), "iso8583: length overrun") { ok = false; }
  if !err_msg_is(iso8583_parse("0200" + "4000000000000000" + "0"), "iso8583: length overrun") { ok = false; }
  if !err_msg_is(iso8583_parse("0200" + "4000000000000000" + "0512"), "iso8583: length overrun") { ok = false; }
  return assert(ok, "declared field missing vs length overrun");
}

fn t12() -> TestResult {
  var ok = err_msg_is(iso8583_parse("0200" + "2000000000000000" + "12A456"), "iso8583: bad field value");
  let bm39 = "0000000002000000";
  let bad39 = wire_with_ctl("0200" + bm39 + "0", 31, "");
  if !err_msg_is(iso8583_parse(bad39), "iso8583: bad field value") { ok = false; }
  let bm41 = "0000000000800000";
  let bad41 = wire_with_ctl("0200" + bm41 + "TERM000", 127, "");
  if !err_msg_is(iso8583_parse(bad41), "iso8583: bad field value") { ok = false; }
  let bm4 = "1000000000000000";
  if !err_msg_is(iso8583_parse("0200" + bm4 + "00000001000x"), "iso8583: bad field value") { ok = false; }
  return assert(ok, "bad field value: numeric digits and printable alphanumerics");
}

fn t13() -> TestResult {
  var ok = err_msg_is(iso8583_parse(wire_primary() + "XYZ"), "iso8583: trailing data");
  if !err_msg_is(iso8583_parse("0200" + "0000000000000000" + "X"), "iso8583: trailing data") { ok = false; }
  let r = iso8583_parse("0200" + "0000000000000000");
  if !r.is_ok {
    ok = false;
  } else {
    let m: Iso8583Message = r.value;
    if iso8583_field_count(&m) != 0 { ok = false; }
    if iso8583_has_secondary(&m) { ok = false; }
    let fr = iso8583_format(&m);
    if !wire_is(fr, "0200" + "0000000000000000") { ok = false; }
  }
  return assert(ok, "trailing data rejected; all-zero bitmap is an empty message");
}

fn t14() -> TestResult {
  var ok = err_msg_is(iso8583_build_message("", &numbers_primary(), &values_primary()), "iso8583: bad mti");
  if !err_msg_is(iso8583_build_message("02A0", &numbers_primary(), &values_primary()), "iso8583: bad mti") { ok = false; }
  var n23 = Vec[Int].new();
  n23.push(2);
  n23.push(3);
  let vp = values_primary();
  var v2 = Vec[Vec[UInt8]].new();
  v2.push(vb("4111111111111111"));
  if !err_msg_is(iso8583_build_message("0200", &n23, &v2), "iso8583: field numbers/values length mismatch") { ok = false; }
  var n32 = Vec[Int].new();
  n32.push(3);
  n32.push(2);
  var v32 = Vec[Vec[UInt8]].new();
  v32.push(vb("000000"));
  v32.push(vb("4111111111111111"));
  if !err_msg_is(iso8583_build_message("0200", &n32, &v32), "iso8583: field numbers out of order") { ok = false; }
  var n22 = Vec[Int].new();
  n22.push(2);
  n22.push(2);
  var v22 = Vec[Vec[UInt8]].new();
  v22.push(vb("4111111111111111"));
  v22.push(vb("4111111111111111"));
  if !err_msg_is(iso8583_build_message("0200", &n22, &v22), "iso8583: field numbers out of order") { ok = false; }
  var n3 = Vec[Int].new();
  n3.push(3);
  var vshort = Vec[Vec[UInt8]].new();
  vshort.push(vb("12345"));
  if !err_msg_is(iso8583_build_message("0200", &n3, &vshort), "iso8583: bad field length") { ok = false; }
  var n2 = Vec[Int].new();
  n2.push(2);
  var vlong = Vec[Vec[UInt8]].new();
  vlong.push(vb(repeat_str("9", 20)));
  if !err_msg_is(iso8583_build_message("0200", &n2, &vlong), "iso8583: bad field length") { ok = false; }
  var vbad3 = Vec[Vec[UInt8]].new();
  vbad3.push(vb("12A456"));
  if !err_msg_is(iso8583_build_message("0200", &n3, &vbad3), "iso8583: bad field value") { ok = false; }
  var n41 = Vec[Int].new();
  n41.push(41);
  var vbad41 = Vec[Vec[UInt8]].new();
  vbad41.push(vb_with("TERM000", 31, ""));
  if !err_msg_is(iso8583_build_message("0200", &n41, &vbad41), "iso8583: bad field value") { ok = false; }
  var none = Vec[Int].new();
  var noval = Vec[Vec[UInt8]].new();
  if !wire_is(iso8583_build("0200", &none, &noval), "0200" + "0000000000000000") { ok = false; }
  return assert(ok, "build validation: MTI, order, duplicates, lengths, values");
}

fn t15() -> TestResult {
  let r = iso8583_parse(wire_primary());
  if !r.is_ok {
    return assert(false, "accessors and field dictionary metadata");
  }
  let m: Iso8583Message = r.value;
  var ok = iso8583_field_count(&m) == 8;
  if iso8583_field_number(&m, -1) != -1 { ok = false; }
  if iso8583_field_number(&m, 8) != -1 { ok = false; }
  if !str_eq(iso8583_field_value(&m, -1), "") { ok = false; }
  if !str_eq(iso8583_field_value(&m, 8), "") { ok = false; }
  if iso8583_field_index(&m, 5) != -1 { ok = false; }
  if iso8583_has_field(&m, 48) { ok = false; }
  if !err_str_is(iso8583_get(&m, 48), "iso8583: field not present") { ok = false; }
  if !iso8583_is_known_field(2) { ok = false; }
  if !iso8583_is_known_field(70) { ok = false; }
  if iso8583_is_known_field(5) { ok = false; }
  if iso8583_is_known_field(64) { ok = false; }
  if !iso8583_is_variable_field(2) { ok = false; }
  if !iso8583_is_variable_field(32) { ok = false; }
  if !iso8583_is_variable_field(48) { ok = false; }
  if iso8583_is_variable_field(3) { ok = false; }
  if iso8583_is_variable_field(70) { ok = false; }
  if iso8583_field_max_length(2) != 19 { ok = false; }
  if iso8583_field_max_length(3) != 6 { ok = false; }
  if iso8583_field_max_length(4) != 12 { ok = false; }
  if iso8583_field_max_length(7) != 10 { ok = false; }
  if iso8583_field_max_length(11) != 6 { ok = false; }
  if iso8583_field_max_length(32) != 11 { ok = false; }
  if iso8583_field_max_length(39) != 2 { ok = false; }
  if iso8583_field_max_length(41) != 8 { ok = false; }
  if iso8583_field_max_length(48) != 999 { ok = false; }
  if iso8583_field_max_length(49) != 3 { ok = false; }
  if iso8583_field_max_length(70) != 3 { ok = false; }
  if iso8583_field_max_length(5) != -1 { ok = false; }
  if iso8583_field_max_length(1) != -1 { ok = false; }
  if iso8583_field_max_length(129) != -1 { ok = false; }
  return assert(ok, "accessors and field dictionary metadata");
}

fn t16() -> TestResult {
  let wlower = "0200" + "f2200001028180000400000000000000" +
    "16" + "4111111111111111" +
    "000000" +
    "000000010000" +
    "0915120000" +
    "123456" +
    "11" + "12345678901" +
    "00" +
    "TERM0001" +
    "010" + "ADDPRIVATE" +
    "EUR" +
    "001";
  let r = iso8583_parse(wlower);
  if !r.is_ok {
    return assert(false, "lowercase bitmap parses and canonicalizes to uppercase");
  }
  let m: Iso8583Message = r.value;
  var ok = field_is(&m, 48, "ADDPRIVATE");
  let fr = iso8583_format(&m);
  if !wire_is(fr, wire_secondary()) { ok = false; }
  if !str_eq(iso8583_bitmap_hex(&m), "F2200001028180000400000000000000") { ok = false; }
  return assert(ok, "lowercase bitmap parses and canonicalizes to uppercase");
}

fn t17() -> TestResult {
  var ok = false;
  let rp = iso8583_parse(wire_primary());
  if rp.is_ok {
    let m: Iso8583Message = rp.value;
    let fr = iso8583_format(&m);
    ok = wire_is(fr, wire_primary());
  }
  let rs = iso8583_parse(wire_secondary());
  if rs.is_ok {
    let m: Iso8583Message = rs.value;
    let fr = iso8583_format(&m);
    if !wire_is(fr, wire_secondary()) { ok = false; }
  } else {
    ok = false;
  }
  let bm2 = "4000000000000000";
  let re = iso8583_parse("0200" + bm2 + "00");
  if re.is_ok {
    let m: Iso8583Message = re.value;
    let fr = iso8583_format(&m);
    if !wire_is(fr, "0200" + bm2 + "00") { ok = false; }
  } else {
    ok = false;
  }
  let rsec = iso8583_parse("0200" + "8000000000000000" + "0000000000000000");
  if !rsec.is_ok {
    ok = false;
  } else {
    let m: Iso8583Message = rsec.value;
    if !iso8583_has_secondary(&m) { ok = false; }
    if iso8583_field_count(&m) != 0 { ok = false; }
    let fr = iso8583_format(&m);
    if !wire_is(fr, "0200" + "8000000000000000" + "0000000000000000") { ok = false; }
  }
  var n4870 = Vec[Int].new();
  n4870.push(48);
  n4870.push(70);
  var v4870 = Vec[Vec[UInt8]].new();
  v4870.push(vb(repeat_str("A", 300)));
  v4870.push(vb("302"));
  let br = iso8583_build("0800", &n4870, &v4870);
  if !br.is_ok {
    ok = false;
  } else {
    let built: Str = br.value;
    let rr = iso8583_parse(built);
    if !rr.is_ok {
      ok = false;
    } else {
      let m: Iso8583Message = rr.value;
      if !field_is(&m, 48, repeat_str("A", 300)) { ok = false; }
      if !field_is(&m, 70, "302") { ok = false; }
      let fr = iso8583_format(&m);
      if !wire_is(fr, built) { ok = false; }
    }
  }
  return assert(ok, "round-trips: parse->format and build->parse->format");
}

fn t18() -> TestResult {
  var n2_70 = Vec[Int].new();
  n2_70.push(2);
  n2_70.push(70);
  var v2_70 = Vec[Vec[UInt8]].new();
  v2_70.push(vb("4111111111111111"));
  v2_70.push(vb("001"));
  let m1 = Iso8583Message{ mti: "0200"; has_secondary: false; field_numbers: n2_70; field_values: v2_70; };
  var ok = err_str_is(iso8583_format(&m1), "iso8583: bitmap/fields mismatch");
  var n3 = Vec[Int].new();
  n3.push(3);
  var vbad = Vec[Vec[UInt8]].new();
  vbad.push(vb("12A456"));
  let m2 = Iso8583Message{ mti: "0200"; has_secondary: false; field_numbers: n3; field_values: vbad; };
  if !err_str_is(iso8583_format(&m2), "iso8583: bad field value") { ok = false; }
  let np = numbers_primary();
  let vp = values_primary();
  let m3 = Iso8583Message{ mti: "02A0"; has_secondary: false; field_numbers: np; field_values: vp; };
  if !err_str_is(iso8583_format(&m3), "iso8583: bad mti") { ok = false; }
  var vshort = Vec[Vec[UInt8]].new();
  vshort.push(vb("12345"));
  let m4 = Iso8583Message{ mti: "0200"; has_secondary: false; field_numbers: n3; field_values: vshort; };
  if !err_str_is(iso8583_format(&m4), "iso8583: bad field length") { ok = false; }
  var n2 = Vec[Int].new();
  n2.push(2);
  let m5 = Iso8583Message{ mti: "0200"; has_secondary: false; field_numbers: n2; field_values: values_secondary(); };
  if !err_str_is(iso8583_format(&m5), "iso8583: field numbers/values length mismatch") { ok = false; }
  var vpan = Vec[Vec[UInt8]].new();
  vpan.push(vb("4111111111111111"));
  let m6 = Iso8583Message{ mti: "0200"; has_secondary: true; field_numbers: n2; field_values: vpan; };
  let fr = iso8583_format(&m6);
  if !wire_is(fr, "0200" + "C000000000000000" + "0000000000000000" + "16" + "4111111111111111") { ok = false; }
  return assert(ok, "format re-validates an inconsistent message");
}

fn main() -> Int {
  io.println("=== xiom.iso8583 conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.iso8583: all tests passed");
  } else {
    io.println("xiom.iso8583: tests failed");
  }
  return failed;
}
