// XIOM -- xiom.avi conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.avi module against RIFF/AVI fixtures.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the "RIFF"+size+"AVI " signature, the stored
// RIFF size (never cross-checked), top-level chunk walking with word
// alignment and payload offsets, the avih field map (streams at payload
// offset 24, the historical dwStreams slot), the avih search fallback into
// "LIST hdrl", duration/fps metadata, and the error catalog (truncated
// header, bad magics, bad chunk id, bad start offset, out-of-range payload,
// partial trailing header, truncated avih, avih not found).
//
// Fixtures are assembled byte by byte (push_text/push_le32) so the parser is
// exercised against bytes this test file controls. Str equality goes through
// str_compare (BUG 17 discipline: `==` on Str values read from a Vec lowers
// to a pointer comparison).

module avi_tests
use xiom.io; use xiom.test;
use xiom.avi;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_info_is(r: Result[AviInfo, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Byte `k` (0 = least significant) of `val` as an UInt8.
fn byte_of(val: Int, k: Int) -> UInt8 {
  var q = val;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    i = i + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

fn push_text(v: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn push_le32(v: &mut Vec[UInt8], val: Int) {
  v.push(byte_of(val, 0));
  v.push(byte_of(val, 1));
  v.push(byte_of(val, 2));
  v.push(byte_of(val, 3));
}

fn push_bytes(v: &mut Vec[UInt8], src: Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    v.push(src[i]);
    i = i + 1;
  }
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
  return v;
}

fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Copy of `v` with byte `pos` replaced.
fn set_byte(v: Vec[UInt8], pos: Int, b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(b as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

// Copy of `v` with the four LE bytes at `pos` replaced by `val`.
fn set_le32(v: Vec[UInt8], pos: Int, val: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i >= pos && i < pos + 4 {
      out.push(byte_of(val, i - pos));
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

// Append one RIFF chunk: id, LE u32 payload length, payload, and a padding
// byte for odd payload lengths.
fn push_chunk(v: &mut Vec[UInt8], id: Str, payload: Vec[UInt8]) {
  push_text(v, id);
  push_le32(v, payload.len());
  push_bytes(v, payload);
  if payload.len() % 2 == 1 {
    v.push(0 as UInt8);
  }
}

// Wrap a chunk body in the 12-byte RIFF/AVI file header with the correct
// size field (4 + body length, i.e. total - 8).
fn riff(body: Vec<UInt8>) -> Vec[UInt8] {
  var f = Vec[UInt8].new();
  push_text(&mut f, "RIFF");
  push_le32(&mut f, 4 + body.len());
  push_text(&mut f, "AVI ");
  push_bytes(&mut f, body);
  return f;
}

// 56-byte avih payload. Field offsets: 0 micro, 16 total frames, 24 dwStreams,
// 32 width, 36 height. `streams24` lands at payload offset 24 (the real
// dwStreams slot read by this package); `sentinel40` lands at payload
// offset 40 (reserved, must be ignored).
fn avih_payload(micro: Int, frames: Int, width: Int, height: Int, streams24: Int, sentinel40: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_le32(&mut v, micro);            // 0  dwMicroSecPerFrame
  push_le32(&mut v, 0);                // 4  dwMaxBytesPerSec
  push_le32(&mut v, 0);                // 8  dwPaddingGranularity
  push_le32(&mut v, 16);               // 12 dwFlags (AVIF_HASINDEX)
  push_le32(&mut v, frames);           // 16 dwTotalFrames
  push_le32(&mut v, 0);                // 20 dwInitialFrames
  push_le32(&mut v, streams24);        // 24 dwStreams (read by this package)
  push_le32(&mut v, 0);                // 28 dwSuggestedBufferSize
  push_le32(&mut v, width);            // 32 dwWidth
  push_le32(&mut v, height);           // 36 dwHeight
  push_le32(&mut v, sentinel40);       // 40 dwReserved[0] (ignored)
  push_le32(&mut v, 0);                // 44
  push_le32(&mut v, 0);                // 48
  push_le32(&mut v, 0);                // 52
  return v;
}

fn build_basic() -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_chunk(&mut body, "avih", avih_payload(40000, 300, 640, 480, 2, 7));
  push_chunk(&mut body, "JUNK", zeros(4));
  return riff(body);
}

// Odd-sized JUNK chunk before avih: avih header must land on the even
// offset 24 (payload 32), not 23.
fn build_odd() -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  var odd = Vec[UInt8].new();
  odd.push(1 as UInt8);
  odd.push(2 as UInt8);
  odd.push(3 as UInt8);
  push_chunk(&mut body, "JUNK", odd);
  push_chunk(&mut body, "avih", avih_payload(40000, 300, 640, 480, 2, 7));
  return riff(body);
}

// avih only inside the first LIST hdrl.
fn build_nested() -> Vec[UInt8] {
  var inner = Vec[UInt8].new();
  push_chunk(&mut inner, "avih", avih_payload(40000, 300, 640, 480, 2, 7));
  var list_payload = Vec[UInt8].new();
  push_text(&mut list_payload, "hdrl");
  push_bytes(&mut list_payload, inner);
  var body = Vec[UInt8].new();
  push_chunk(&mut body, "LIST", list_payload);
  return riff(body);
}

// LIST whose type is "movi", not "hdrl": parse must report avih not found.
fn build_movi_list() -> Vec[UInt8] {
  var list_payload = Vec[UInt8].new();
  push_text(&mut list_payload, "movi");
  push_bytes(&mut list_payload, zeros(8));
  var body = Vec[UInt8].new();
  push_chunk(&mut body, "LIST", list_payload);
  return riff(body);
}

// A JUNK chunk, an avih, and a trailing LIST movi.
fn build_e2e() -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_chunk(&mut body, "JUNK", zeros(6));
  push_chunk(&mut body, "avih", avih_payload(40000, 300, 640, 480, 2, 7));
  var list_payload = Vec[UInt8].new();
  push_text(&mut list_payload, "movi");
  push_bytes(&mut list_payload, zeros(4));
  push_chunk(&mut body, "LIST", list_payload);
  return riff(body);
}

// avih chunk whose declared (and actual) payload is only 40 bytes.
fn build_short_avih() -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_chunk(&mut body, "avih", zeros(40));
  return riff(body);
}

// JUNK declaring a 100-byte payload with only 4 bytes present.
fn build_bad_payload() -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_text(&mut body, "JUNK");
  push_le32(&mut body, 100);
  push_bytes(&mut body, zeros(4));
  return riff(body);
}

// A complete JUNK chunk followed by a 4-byte partial chunk header.
fn build_trailing() -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_chunk(&mut body, "JUNK", zeros(4));
  push_text(&mut body, "nota");
  return riff(body);
}

// A single JUNK chunk: no avih anywhere.
fn build_no_avih() -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  push_chunk(&mut body, "JUNK", zeros(4));
  return riff(body);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = build_basic();
  var ok = data.len() == 88;
  if !avi_is_file(&data) { ok = false; }
  return assert(ok, "avi_is_file accepts the minimal RIFF/AVI buffer");
}

fn t2() -> TestResult {
  let full = build_basic();
  let empty = Vec[UInt8].new();
  let short = prefix(full, 11);
  let bad_riff = set_byte(full, 0, 88);
  let bad_form = set_byte(full, 8, 88);
  var junk = Vec[UInt8].new();
  push_text(&mut junk, "not an avi file");
  let mismatch = set_le32(full, 4, 0);
  var ok = true;
  if avi_is_file(&empty) { ok = false; }
  if avi_is_file(&short) { ok = false; }
  if avi_is_file(&bad_riff) { ok = false; }
  if avi_is_file(&bad_form) { ok = false; }
  if avi_is_file(&junk) { ok = false; }
  // A wrong size field is tolerated: the field is not cross-checked.
  if !avi_is_file(&mismatch) { ok = false; }
  return assert(ok, "avi_is_file rejects bad magic but tolerates a size mismatch");
}

fn t3() -> TestResult {
  let data = build_basic();
  let r = avi_riff_size(&data);
  var ok = true;
  if !r.is_ok { ok = false; } elif r.value != 80 { ok = false; }
  var empty_body = Vec[UInt8].new();
  let header_only = riff(empty_body);
  let r2 = avi_riff_size(&header_only);
  if header_only.len() != 12 { ok = false; }
  if !r2.is_ok { ok = false; } elif r2.value != 4 { ok = false; }
  let mismatch = set_le32(data, 4, 0);
  let r3 = avi_riff_size(&mismatch);
  if !r3.is_ok { ok = false; } elif r3.value != 0 { ok = false; }
  let p = avi_parse_avih(&mismatch);
  if !p.is_ok { ok = false; }
  return assert(ok, "avi_riff_size returns the stored size field, never cross-checked");
}

fn t4() -> TestResult {
  let full = build_basic();
  let empty = Vec[UInt8].new();
  let short = prefix(full, 11);
  let bad_riff = set_byte(full, 0, 88);
  let bad_form = set_byte(full, 8, 88);
  var ok = err_int_is(avi_riff_size(&empty), "avi: truncated header");
  if !err_int_is(avi_riff_size(&short), "avi: truncated header") { ok = false; }
  if !err_int_is(avi_riff_size(&bad_riff), "avi: bad RIFF magic") { ok = false; }
  if !err_int_is(avi_riff_size(&bad_form), "avi: bad AVI magic") { ok = false; }
  return assert(ok, "avi_riff_size error catalog");
}

fn t5() -> TestResult {
  let data = build_basic();
  let a = avi_find_chunk(&data, "avih", 12);
  let j = avi_find_chunk(&data, "JUNK", 12);
  var ok = true;
  if !a.is_ok { ok = false; } elif a.value != 20 { ok = false; }
  if !j.is_ok { ok = false; } elif j.value != 84 { ok = false; }
  return assert(ok, "avi_find_chunk returns payload offsets (avih 20, JUNK 84)");
}

fn t6() -> TestResult {
  let data = build_basic();
  let missing = avi_find_chunk(&data, "strh", 12);
  var ok = err_int_is(missing, "avi: chunk not found");
  if !err_int_is(avi_find_chunk(&data, "avi", 12), "avi: bad chunk id") { ok = false; }
  if !err_int_is(avi_find_chunk(&data, "avihx", 12), "avi: bad chunk id") { ok = false; }
  if !err_int_is(avi_find_chunk(&data, "avih", 11), "avi: bad start offset") { ok = false; }
  if !err_int_is(avi_find_chunk(&data, "avih", data.len() + 1), "avi: bad start offset") { ok = false; }
  let at_end = avi_find_chunk(&data, "avih", data.len());
  if !err_int_is(at_end, "avi: chunk not found") { ok = false; }
  return assert(ok, "avi_find_chunk not found, bad id and bad start offset");
}

fn t7() -> TestResult {
  let data = build_odd();
  let a = avi_find_chunk(&data, "avih", 12);
  let j = avi_find_chunk(&data, "JUNK", 12);
  let p = avi_parse_avih(&data);
  var ok = data.len() == 88;
  if !j.is_ok { ok = false; } elif j.value != 20 { ok = false; }
  if !a.is_ok { ok = false; } elif a.value != 32 { ok = false; }
  if !p.is_ok { ok = false; } elif p.value.micro_sec_per_frame != 40000 { ok = false; }
  return assert(ok, "odd-sized chunk is padded before the next header");
}

fn t8() -> TestResult {
  let data = build_basic();
  let r = avi_parse_avih(&data);
  if !r.is_ok { return assert(false, "avih parse must succeed"); }
  let info = r.value;
  var ok = info.micro_sec_per_frame == 40000;
  if info.total_frames != 300 { ok = false; }
  if info.width != 640 { ok = false; }
  if info.height != 480 { ok = false; }
  if info.streams != 2 { ok = false; }
  return assert(ok, "avih fields; streams comes from payload offset 24");
}

fn t9() -> TestResult {
  let data = build_basic();
  let r = avi_parse_avih(&data);
  if !r.is_ok { return assert(false, "avih parse must succeed"); }
  let info = r.value;
  var ok = avi_duration_ms(&info) == 12000;
  let truncated = AviInfo{ micro_sec_per_frame: 999; total_frames: 1; width: 0; height: 0; streams: 0 };
  if avi_duration_ms(&truncated) != 0 { ok = false; }
  let exact = AviInfo{ micro_sec_per_frame: 1000; total_frames: 1; width: 0; height: 0; streams: 0 };
  if avi_duration_ms(&exact) != 1 { ok = false; }
  return assert(ok, "avi_duration_ms truncates to whole milliseconds");
}

fn t10() -> TestResult {
  let data = build_basic();
  let r = avi_parse_avih(&data);
  if !r.is_ok { return assert(false, "avih parse must succeed"); }
  let info = r.value;
  var ok = avi_fps_permille(&info) == 25000;
  let zero = AviInfo{ micro_sec_per_frame: 0; total_frames: 0; width: 0; height: 0; streams: 0 };
  if avi_fps_permille(&zero) != 0 { ok = false; }
  let negative = AviInfo{ micro_sec_per_frame: -1; total_frames: 0; width: 0; height: 0; streams: 0 };
  if avi_fps_permille(&negative) != 0 { ok = false; }
  let rounded = AviInfo{ micro_sec_per_frame: 33367; total_frames: 0; width: 0; height: 0; streams: 0 };
  if avi_fps_permille(&rounded) != 29970 { ok = false; }
  let two = AviInfo{ micro_sec_per_frame: 500000; total_frames: 0; width: 0; height: 0; streams: 0 };
  if avi_fps_permille(&two) != 2000 { ok = false; }
  return assert(ok, "avi_fps_permille rounds to the nearest permille");
}

fn t11() -> TestResult {
  let data = build_nested();
  let top = avi_find_chunk(&data, "avih", 12);
  let l = avi_find_chunk(&data, "LIST", 12);
  let r = avi_parse_avih(&data);
  var ok = data.len() == 88;
  // Top-level only: an avih inside LIST hdrl is not found by avi_find_chunk.
  if !err_int_is(top, "avi: chunk not found") { ok = false; }
  if !l.is_ok { ok = false; } elif l.value != 20 { ok = false; }
  if !r.is_ok { ok = false; } else {
    if r.value.micro_sec_per_frame != 40000 { ok = false; }
    if r.value.total_frames != 300 { ok = false; }
    if r.value.width != 640 { ok = false; }
    if r.value.height != 480 { ok = false; }
    if r.value.streams != 2 { ok = false; }
  }
  return assert(ok, "avi_parse_avih finds avih inside the first LIST hdrl");
}

fn t12() -> TestResult {
  let movi = build_movi_list();
  let plain = build_no_avih();
  var ok = err_info_is(avi_parse_avih(&movi), "avi: avih not found");
  if !err_info_is(avi_parse_avih(&plain), "avi: avih not found") { ok = false; }
  if !err_int_is(avi_find_chunk(&plain, "avih", 12), "avi: chunk not found") { ok = false; }
  return assert(ok, "missing avih is Err(\"avi: avih not found\")");
}

fn t13() -> TestResult {
  let data = build_short_avih();
  let f = avi_find_chunk(&data, "avih", 12);
  var ok = true;
  if !f.is_ok { ok = false; } elif f.value != 20 { ok = false; }
  if !err_info_is(avi_parse_avih(&data), "avi: truncated avih") { ok = false; }
  return assert(ok, "avih payload shorter than 56 bytes is Err");
}

fn t14() -> TestResult {
  let data = build_bad_payload();
  var ok = err_int_is(avi_find_chunk(&data, "JUNK", 12), "avi: chunk out of range");
  if !err_info_is(avi_parse_avih(&data), "avi: chunk out of range") { ok = false; }
  return assert(ok, "a declared payload beyond the buffer is Err");
}

fn t15() -> TestResult {
  let data = build_trailing();
  var ok = err_int_is(avi_find_chunk(&data, "avih", 12), "avi: chunk truncated");
  if !err_info_is(avi_parse_avih(&data), "avi: chunk truncated") { ok = false; }
  return assert(ok, "a trailing partial chunk header is Err");
}

fn t16() -> TestResult {
  let full = build_basic();
  let empty = Vec[UInt8].new();
  let short = prefix(full, 11);
  let bad_riff = set_byte(full, 0, 88);
  let bad_form = set_byte(full, 8, 88);
  var ok = err_info_is(avi_parse_avih(&empty), "avi: truncated header");
  if !err_info_is(avi_parse_avih(&short), "avi: truncated header") { ok = false; }
  if !err_info_is(avi_parse_avih(&bad_riff), "avi: bad RIFF magic") { ok = false; }
  if !err_info_is(avi_parse_avih(&bad_form), "avi: bad AVI magic") { ok = false; }
  return assert(ok, "avi_parse_avih header error catalog");
}

fn t17() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = !avi_is_file(&empty);
  if !err_int_is(avi_riff_size(&empty), "avi: truncated header") { ok = false; }
  if !err_int_is(avi_find_chunk(&empty, "avih", 12), "avi: truncated header") { ok = false; }
  if !err_info_is(avi_parse_avih(&empty), "avi: truncated header") { ok = false; }
  return assert(ok, "empty input is rejected by every reader");
}

fn t18() -> TestResult {
  let data = build_e2e();
  let j = avi_find_chunk(&data, "JUNK", 12);
  let a = avi_find_chunk(&data, "avih", 12);
  let l = avi_find_chunk(&data, "LIST", 12);
  var ok = data.len() == 106;
  if !j.is_ok { ok = false; } elif j.value != 20 { ok = false; }
  if !a.is_ok { ok = false; } elif a.value != 34 { ok = false; }
  if !l.is_ok { ok = false; } elif l.value != 98 { ok = false; }
  let r = avi_parse_avih(&data);
  if !r.is_ok { ok = false; } else {
    let info = r.value;
    if info.micro_sec_per_frame != 40000 { ok = false; }
    if info.total_frames != 300 { ok = false; }
    if info.width != 640 { ok = false; }
    if info.height != 480 { ok = false; }
    if info.streams != 2 { ok = false; }
    if avi_duration_ms(&info) != 12000 { ok = false; }
    if avi_fps_permille(&info) != 25000 { ok = false; }
  }
  return assert(ok, "end-to-end: chunks before and after avih are walked correctly");
}

fn main() -> Int {
  io.println("=== xiom.avi conformance tests ===");
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
    io.println("xiom.avi: all tests passed");
  } else {
    io.println("xiom.avi: tests failed");
  }
  return failed;
}
