// XIOM -- xiom.wasm conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented structure-only API: magic/version detection,
// unsigned LEB128 u32 pinning (single/multi-byte values, 5-byte maximum,
// truncation and overflow), the section-name table, a hand-built module
// walked for section ids/offsets/sizes, and export-name extraction
// including a non-ASCII name and malformed-section errors.
//
// Str values read from Vec[Str] are compared with str_compare through
// typed locals (BUG 17 discipline: `==` on such Str values lowers to a
// pointer comparison). Raw bytes widen through `(x as Int) & 0xFF`.

module wasm_tests
use xiom.io; use xiom.test;
use xiom.wasm;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn concat2(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    v.push(a[i]);
    i = i + 1;
  }
  var j = 0;
  while j < b.len() {
    v.push(b[j]);
    j = j + 1;
  }
  return v;
}

// --------------------------------------------------
//  Byte-building helpers (hand-built modules)
// --------------------------------------------------

fn push_byte(out: &mut Vec[UInt8], b: Int) {
  out.push(b as UInt8);
}

// Unsigned LEB128 encoding of a non-negative Int (test-side encoder).
fn push_leb(out: &mut Vec[UInt8], v: Int) {
  var n = v;
  loop {
    let b = n % 128;
    n = n / 128;
    if n == 0 {
      out.push(b as UInt8);
      break;
    }
    out.push((b + 128) as UInt8);
  }
}

// UTF-8 bytes of `s`, verbatim.
fn push_utf8(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn header_bytes() -> Vec[UInt8] {
  var m = Vec[UInt8].new();
  push_byte(&mut m, 0x00);
  push_byte(&mut m, 0x61);
  push_byte(&mut m, 0x73);
  push_byte(&mut m, 0x6D);
  push_byte(&mut m, 0x01);
  push_byte(&mut m, 0x00);
  push_byte(&mut m, 0x00);
  push_byte(&mut m, 0x00);
  return m;
}

fn module_with_section(id: Int, payload: Vec[UInt8]) -> Vec[UInt8] {
  var m = header_bytes();
  push_byte(&mut m, id);
  push_leb(&mut m, payload.len());
  var i = 0;
  while i < payload.len() {
    m.push(payload[i]);
    i = i + 1;
  }
  return m;
}

// Header + type section (1 functype `[] -> [i32]`) + function section
// (1 function of type 0) + export section (3 entries: "run" func 0,
// "memory" memory 0, "π" func 1). 42 bytes total; the section walk is
// pinned in t11 and the names in t17.
fn build_module() -> Vec[UInt8] {
  var m = header_bytes();
  // type section: id 1, payload `01 60 00 01 7F` (size 5)
  push_byte(&mut m, 0x01);
  push_leb(&mut m, 5);
  push_byte(&mut m, 0x01);
  push_byte(&mut m, 0x60);
  push_byte(&mut m, 0x00);
  push_byte(&mut m, 0x01);
  push_byte(&mut m, 0x7F);
  // function section: id 3, payload `01 00` (size 2)
  push_byte(&mut m, 0x03);
  push_leb(&mut m, 2);
  push_byte(&mut m, 0x01);
  push_byte(&mut m, 0x00);
  // export section: id 7, payload size 21
  push_byte(&mut m, 0x07);
  push_leb(&mut m, 21);
  push_byte(&mut m, 0x03);
  push_leb(&mut m, 3);
  push_utf8(&mut m, "run");
  push_byte(&mut m, 0x00);
  push_byte(&mut m, 0x00);
  push_leb(&mut m, 6);
  push_utf8(&mut m, "memory");
  push_byte(&mut m, 0x02);
  push_byte(&mut m, 0x00);
  push_leb(&mut m, 2);
  push_utf8(&mut m, "π");
  push_byte(&mut m, 0x00);
  push_byte(&mut m, 0x01);
  return m;
}

// --------------------------------------------------
//  Assertion helpers
// --------------------------------------------------

fn int_vec_is(v: &Vec[Int], idx: Int, want: Int) -> Bool {
  if idx < 0 || idx >= v.len() {
    return false;
  }
  let got: Int = v[idx];
  return got == want;
}

fn name_is(names: &Vec[Str], idx: Int, want: Str) -> Bool {
  if idx < 0 || idx >= names.len() {
    return false;
  }
  let got: Str = names[idx];
  return compare.str_compare(got, want) == 0;
}

fn err_leb_is(r: Result[(Int, Int), Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return compare.str_compare(r.error, want) == 0;
}

fn err_sections_is(r: Result[WasmSections, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return compare.str_compare(r.error, want) == 0;
}

fn err_names_is(r: Result[Vec[Str], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return compare.str_compare(r.error, want) == 0;
}

fn leb_pair_is(data: Vec[UInt8], off: Int, want_val: Int, want_next: Int) -> Bool {
  let r = wasm_leb_u32(&data, off);
  if !r.is_ok {
    return false;
  }
  let pair = r.value;
  let val: Int = pair.0;
  let next: Int = pair.1;
  return val == want_val && next == want_next;
}

fn section_name_is(id: Int, want: Str) -> Bool {
  let got: Str = wasm_section_name(id);
  return compare.str_compare(got, want) == 0;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let head = hb("0061736d01000000");
  var ok = wasm_is_module(&head);
  let full = build_module();
  if !wasm_is_module(&full) { ok = false; }
  let head_plus = concat2(head, hb("00"));
  if !wasm_is_module(&head_plus) { ok = false; }
  return assert(ok, "is_module accepts the magic+version header, a full module and trailing bytes");
}

fn t2() -> TestResult {
  let empty = Vec[UInt8].new();
  let magic4 = hb("0061736d");
  let seven = hb("0061736d010000");
  let bad_magic = hb("0161736d01000000");
  let bad_version = hb("0061736d02000000");
  var ok = !wasm_is_module(&empty);
  if wasm_is_module(&magic4) { ok = false; }
  if wasm_is_module(&seven) { ok = false; }
  if wasm_is_module(&bad_magic) { ok = false; }
  if wasm_is_module(&bad_version) { ok = false; }
  return assert(ok, "is_module rejects short headers, bad magic and bad version");
}

fn t3() -> TestResult {
  var ok = leb_pair_is(hb("00"), 0, 0, 1);
  if !leb_pair_is(hb("01"), 0, 1, 1) { ok = false; }
  if !leb_pair_is(hb("2a"), 0, 42, 1) { ok = false; }
  if !leb_pair_is(hb("7f"), 0, 127, 1) { ok = false; }
  return assert(ok, "leb u32 single-byte values 0, 1, 42, 127");
}

fn t4() -> TestResult {
  var ok = leb_pair_is(hb("8001"), 0, 128, 2);
  if !leb_pair_is(hb("8101"), 0, 129, 2) { ok = false; }
  if !leb_pair_is(hb("ff01"), 0, 255, 2) { ok = false; }
  if !leb_pair_is(hb("ac02"), 0, 300, 2) { ok = false; }
  return assert(ok, "leb u32 two-byte values 128, 129, 255, 300");
}

fn t5() -> TestResult {
  var ok = leb_pair_is(hb("e58e26"), 0, 624485, 3);
  if !leb_pair_is(hb("ffffffff0f"), 0, 4294967295, 5) { ok = false; }
  if !leb_pair_is(hb("8080808000"), 0, 0, 5) { ok = false; }
  return assert(ok, "leb u32 three-byte 624485, 5-byte max 2^32-1 and non-minimal zero");
}

fn t6() -> TestResult {
  let stream = hb("aa8001e58e2600");
  var ok = leb_pair_is(stream, 1, 128, 3);
  if !leb_pair_is(stream, 3, 624485, 6) { ok = false; }
  if !leb_pair_is(stream, 6, 0, 7) { ok = false; }
  return assert(ok, "leb u32 honours a non-zero start offset and reports offsets after");
}

fn t7() -> TestResult {
  let empty = Vec[UInt8].new();
  let one = hb("01");
  let cont = hb("80");
  let cont4 = hb("80808080");
  var ok = err_leb_is(wasm_leb_u32(&empty, 0), "wasm: truncated leb128");
  if !err_leb_is(wasm_leb_u32(&cont, 0), "wasm: truncated leb128") { ok = false; }
  if !err_leb_is(wasm_leb_u32(&cont4, 0), "wasm: truncated leb128") { ok = false; }
  if !err_leb_is(wasm_leb_u32(&one, 5), "wasm: truncated leb128") { ok = false; }
  if !err_leb_is(wasm_leb_u32(&one, -1), "wasm: negative offset") { ok = false; }
  return assert(ok, "leb u32 truncation and negative-offset errors are Err");
}

fn t8() -> TestResult {
  let over5 = hb("ffffffff10");
  let over7f = hb("ffffffff7f");
  let six = hb("808080808000");
  var ok = err_leb_is(wasm_leb_u32(&over5, 0), "wasm: leb128 overflow");
  if !err_leb_is(wasm_leb_u32(&over7f, 0), "wasm: leb128 overflow") { ok = false; }
  if !err_leb_is(wasm_leb_u32(&six, 0), "wasm: leb128 overflow") { ok = false; }
  return assert(ok, "leb u32 overflow (payload bits above bit 31, 6-byte request) is Err");
}

fn t9() -> TestResult {
  var ok = section_name_is(0, "custom");
  if !section_name_is(1, "type") { ok = false; }
  if !section_name_is(2, "import") { ok = false; }
  if !section_name_is(3, "function") { ok = false; }
  if !section_name_is(4, "table") { ok = false; }
  if !section_name_is(5, "memory") { ok = false; }
  if !section_name_is(6, "global") { ok = false; }
  if !section_name_is(7, "export") { ok = false; }
  if !section_name_is(8, "start") { ok = false; }
  if !section_name_is(9, "element") { ok = false; }
  if !section_name_is(10, "code") { ok = false; }
  if !section_name_is(11, "data") { ok = false; }
  if !section_name_is(12, "datacount") { ok = false; }
  return assert(ok, "section_name maps ids 0..12 to their canonical names");
}

fn t10() -> TestResult {
  var ok = section_name_is(13, "unknown");
  if !section_name_is(31, "unknown") { ok = false; }
  if !section_name_is(255, "unknown") { ok = false; }
  if !section_name_is(-1, "unknown") { ok = false; }
  return assert(ok, "section_name returns unknown outside 0..12");
}

fn t11() -> TestResult {
  let m = build_module();
  let r = wasm_parse_sections(&m);
  if !r.is_ok {
    return assert(false, "parse_sections walks a hand-built module: ids, offsets, sizes");
  }
  let s = r.value;
  var ok = s.ids.len() == 3;
  if s.offsets.len() != 3 { ok = false; }
  if s.sizes.len() != 3 { ok = false; }
  if !int_vec_is(&s.ids, 0, 1) { ok = false; }
  if !int_vec_is(&s.ids, 1, 3) { ok = false; }
  if !int_vec_is(&s.ids, 2, 7) { ok = false; }
  if !int_vec_is(&s.offsets, 0, 10) { ok = false; }
  if !int_vec_is(&s.offsets, 1, 17) { ok = false; }
  if !int_vec_is(&s.offsets, 2, 21) { ok = false; }
  if !int_vec_is(&s.sizes, 0, 5) { ok = false; }
  if !int_vec_is(&s.sizes, 1, 2) { ok = false; }
  if !int_vec_is(&s.sizes, 2, 21) { ok = false; }
  return assert(ok, "parse_sections walks a hand-built module: ids, offsets, sizes");
}

fn t12() -> TestResult {
  let m = hb("0061736d01000000");
  let r = wasm_parse_sections(&m);
  var ok = r.is_ok;
  if !r.is_ok {
    return assert(false, "empty module has three empty section vectors");
  }
  let s = r.value;
  if s.ids.len() != 0 { ok = false; }
  if s.offsets.len() != 0 { ok = false; }
  if s.sizes.len() != 0 { ok = false; }
  return assert(ok, "empty module has three empty section vectors");
}

fn t13() -> TestResult {
  // custom (id 0, 1 payload byte) + unknown id 31 (size 0) + data (id 11,
  // size 0): total 15 bytes, last payload ending exactly at EOF.
  var m = header_bytes();
  push_byte(&mut m, 0x00);
  push_byte(&mut m, 0x01);
  push_byte(&mut m, 0x2A);
  push_byte(&mut m, 0x1F);
  push_byte(&mut m, 0x00);
  push_byte(&mut m, 0x0B);
  push_byte(&mut m, 0x00);
  let r = wasm_parse_sections(&m);
  if !r.is_ok {
    return assert(false, "custom, unknown and zero-size sections walk (offsets pinned)");
  }
  let s = r.value;
  var ok = s.ids.len() == 3 && m.len() == 15;
  if !int_vec_is(&s.ids, 0, 0) { ok = false; }
  if !int_vec_is(&s.ids, 1, 31) { ok = false; }
  if !int_vec_is(&s.ids, 2, 11) { ok = false; }
  if !int_vec_is(&s.offsets, 0, 10) { ok = false; }
  if !int_vec_is(&s.offsets, 1, 13) { ok = false; }
  if !int_vec_is(&s.offsets, 2, 15) { ok = false; }
  if !int_vec_is(&s.sizes, 0, 1) { ok = false; }
  if !int_vec_is(&s.sizes, 1, 0) { ok = false; }
  if !int_vec_is(&s.sizes, 2, 0) { ok = false; }
  return assert(ok, "custom, unknown and zero-size sections walk (offsets pinned)");
}

fn t14() -> TestResult {
  // One type section with a 130-byte payload: size LEB `82 01` (multi-byte).
  var m = header_bytes();
  push_byte(&mut m, 0x01);
  push_leb(&mut m, 130);
  var i = 0;
  while i < 130 {
    push_byte(&mut m, 0x00);
    i = i + 1;
  }
  let r = wasm_parse_sections(&m);
  if !r.is_ok {
    return assert(false, "multi-byte section size LEB (130) is decoded");
  }
  let s = r.value;
  var ok = s.ids.len() == 1 && m.len() == 141;
  if !int_vec_is(&s.offsets, 0, 11) { ok = false; }
  if !int_vec_is(&s.sizes, 0, 130) { ok = false; }
  return assert(ok, "multi-byte section size LEB (130) is decoded");
}

fn t15() -> TestResult {
  let head = hb("0061736d01000000");
  let id_only = concat2(head, hb("01"));
  let short = concat2(head, hb("01050160"));
  let leb_trunc = concat2(head, hb("0180"));
  let leb_over = concat2(head, hb("01ffffffff10"));
  let huge = concat2(head, hb("01ffffffff0f"));
  var ok = err_sections_is(wasm_parse_sections(&id_only), "wasm: truncated leb128");
  if !err_sections_is(wasm_parse_sections(&short), "wasm: truncated section") { ok = false; }
  if !err_sections_is(wasm_parse_sections(&leb_trunc), "wasm: truncated leb128") { ok = false; }
  if !err_sections_is(wasm_parse_sections(&leb_over), "wasm: leb128 overflow") { ok = false; }
  if !err_sections_is(wasm_parse_sections(&huge), "wasm: truncated section") { ok = false; }
  return assert(ok, "parse_sections rejects truncated sections and propagates LEB errors");
}

fn t16() -> TestResult {
  let empty = Vec[UInt8].new();
  let magic4 = hb("0061736d");
  let seven = hb("0061736d010000");
  let bad_magic = hb("0161736d01000000");
  let bad_version = hb("0061736d02000000");
  var ok = err_sections_is(wasm_parse_sections(&empty), "wasm: truncated header");
  if !err_sections_is(wasm_parse_sections(&magic4), "wasm: truncated header") { ok = false; }
  if !err_sections_is(wasm_parse_sections(&seven), "wasm: truncated header") { ok = false; }
  if !err_sections_is(wasm_parse_sections(&bad_magic), "wasm: bad magic") { ok = false; }
  if !err_sections_is(wasm_parse_sections(&bad_version), "wasm: bad version") { ok = false; }
  return assert(ok, "parse_sections header errors carry the exact catalog text");
}

fn t17() -> TestResult {
  let m = build_module();
  let r = wasm_export_names(&m);
  if !r.is_ok {
    return assert(false, "export names are extracted in order incl. unicode");
  }
  let names = r.value;
  var ok = names.len() == 3;
  if !name_is(&names, 0, "run") { ok = false; }
  if !name_is(&names, 1, "memory") { ok = false; }
  if !name_is(&names, 2, "π") { ok = false; }
  return assert(ok, "export names are extracted in order incl. unicode");
}

fn t18() -> TestResult {
  let head = hb("0061736d01000000");
  let none = wasm_export_names(&head);
  if !none.is_ok {
    return assert(false, "modules without an export section yield an empty name list");
  }
  var ok = none.value.len() == 0;
  var t = header_bytes();
  push_byte(&mut t, 0x01);
  push_leb(&mut t, 1);
  push_byte(&mut t, 0x00);
  let typed = wasm_export_names(&t);
  if !typed.is_ok { ok = false; }
  elif typed.value.len() != 0 { ok = false; }
  return assert(ok, "modules without an export section yield an empty name list");
}

fn t19() -> TestResult {
  let short_name = hb("01056162");
  let no_kind = hb("0100");
  let short_index = hb("0101610080");
  let over_index = hb("01016100ffffffff10");
  let two_entries = hb("020161000001");
  let trailing = hb("002a");
  let nul_name = hb("0101000000");
  let m1 = module_with_section(7, short_name);
  let m2 = module_with_section(7, no_kind);
  let m3 = module_with_section(7, short_index);
  let m4 = module_with_section(7, over_index);
  let m5 = module_with_section(7, two_entries);
  let m6 = module_with_section(7, trailing);
  let m7 = module_with_section(7, nul_name);
  var ok = err_names_is(wasm_export_names(&m1), "wasm: truncated export");
  if !err_names_is(wasm_export_names(&m2), "wasm: truncated export") { ok = false; }
  if !err_names_is(wasm_export_names(&m3), "wasm: truncated leb128") { ok = false; }
  if !err_names_is(wasm_export_names(&m4), "wasm: leb128 overflow") { ok = false; }
  if !err_names_is(wasm_export_names(&m5), "wasm: truncated export") { ok = false; }
  if !err_names_is(wasm_export_names(&m6), "wasm: trailing export bytes") { ok = false; }
  if !err_names_is(wasm_export_names(&m7), "wasm: nul in export name") { ok = false; }
  return assert(ok, "malformed export entries are Err (short name, no kind, bad index, tail, nul)");
}

fn t20() -> TestResult {
  // Export index LEB crosses the declared payload boundary into the next
  // section's id byte: header + export(07 05 01 01 61 00 80) + function(03 00).
  let m = concat2(hb("0061736d01000000"), hb("07050101610080"));
  let with_next = concat2(m, hb("0300"));
  var ok = err_names_is(wasm_export_names(&with_next), "wasm: truncated export");
  let trunc_mod = hb("0061736d0100000001050160");
  if !err_names_is(wasm_export_names(&trunc_mod), "wasm: truncated section") { ok = false; }
  let bad_magic = hb("0161736d01000000");
  if !err_names_is(wasm_export_names(&bad_magic), "wasm: bad magic") { ok = false; }
  return assert(ok, "export names propagate section errors and reject boundary-crossing entries");
}

fn t21() -> TestResult {
  // One export with a 130-byte name (multi-byte length LEB) and a
  // multi-byte index (300: `ac 02`).
  var payload = Vec[UInt8].new();
  push_byte(&mut payload, 0x01);
  push_leb(&mut payload, 130);
  var i = 0;
  while i < 130 {
    push_byte(&mut payload, 0x61);
    i = i + 1;
  }
  push_byte(&mut payload, 0x00);
  push_leb(&mut payload, 300);
  let m = module_with_section(7, payload);
  let r = wasm_export_names(&m);
  if !r.is_ok {
    return assert(false, "multi-byte name length LEB and index LEB parse");
  }
  let names = r.value;
  var ok = names.len() == 1;
  let want = string.str_repeat("a", 130);
  if !name_is(&names, 0, want) { ok = false; }
  return assert(ok, "multi-byte name length LEB and index LEB parse");
}

fn t22() -> TestResult {
  let zero_size = hb("0061736d010000000700");
  let zero_count = hb("0061736d01000000070100");
  let e1 = wasm_export_names(&zero_size);
  let e2 = wasm_export_names(&zero_count);
  var ok = e1.is_ok && e1.value.len() == 0;
  if !e2.is_ok { ok = false; }
  elif e2.value.len() != 0 { ok = false; }
  return assert(ok, "empty export sections (size 0 and count 0) yield an empty name list");
}

fn main() -> Int {
  io.println("=== xiom.wasm conformance tests ===");
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
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.wasm: all tests passed");
  } else {
    io.println("xiom.wasm: tests failed");
  }
  return failed;
}
