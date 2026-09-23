// XIOM -- xiom.wav conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.wav module against canonical PCM WAV.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the exact 44-byte canonical header, build ->
// parse round-trips at every supported bit width, PCM payload preservation,
// frame/duration metadata, input clamping, wav_le_u32, and the error
// catalog (truncation, magic, non-PCM, fmt size, bits, RIFF size, data
// bounds, zero align, zero rate, out-of-range offset).
//
// Err strings are compared with str_compare (BUG 17 discipline: `==` on
// Str values read from a Vec lowers to a pointer comparison).

module wav_tests
use xiom.io; use xiom.test;
use xiom.wav;
use xiom.string.compare;
use xiom.encoding.hex;

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    return r.value;
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

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn repeat_byte(b: Int, n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(b as UInt8);
    i = i + 1;
  }
  return v;
}

// A WavFormat literal for the tests.
fn fmt(channels: Int, rate: Int, bits: Int) -> WavFormat {
  return WavFormat{
    channels: channels;
    sample_rate: rate;
    bits_per_sample: bits;
  };
}

fn err_fmt_is(r: Result[WavFormat, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Byte `k` (0 = least significant) of `v` as an UInt8.
fn byte_of(v: Int, k: Int) -> UInt8 {
  var q = v;
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

fn set_byte(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    if i == pos {
      out.push(v as UInt8);
    } else {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
}

fn set_le16(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    if i >= pos && i < pos + 2 {
      out.push(byte_of(v, i - pos));
    } else {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
}

fn set_le32(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    if i >= pos && i < pos + 4 {
      out.push(byte_of(v, i - pos));
    } else {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
}

fn truncate(data: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// Full round-trip for one format: build -> size -> parse fields -> PCM copy.
fn rt(channels: Int, rate: Int, bits: Int, n: Int) -> Bool {
  let f = fmt(channels, rate, bits);
  let pcm = repeat_byte(85, n);
  let data = wav_build_pcm(&pcm, &f);
  if data.len() != 44 + n { return false; }
  let r = wav_header_parse(&data);
  if !r.is_ok { return false; }
  if r.value.channels != channels { return false; }
  if r.value.sample_rate != rate { return false; }
  if r.value.bits_per_sample != bits { return false; }
  let pd = wav_pcm_data(&data);
  if !pd.is_ok { return false; }
  let got = pd.value;
  if !bytes_equal(got, pcm) { return false; }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let empty = Vec[UInt8].new();
  let f = fmt(1, 8000, 16);
  let hdr = wav_build_pcm(&empty, &f);
  let want = hb("524946462400000057415645666d74201000000001000100401f0000803e0000020010006461746100000000");
  var ok = hdr.len() == 44;
  if !bytes_equal(hdr, want) { ok = false; }
  return assert(ok, "exact 44-byte header for 1ch/8000Hz/16-bit empty PCM");
}

fn t2() -> TestResult {
  let f = fmt(1, 11025, 8);
  let pcm = repeat_byte(64, 5);
  let data = wav_build_pcm(&pcm, &f);
  let r = wav_header_parse(&data);
  if !r.is_ok { return assert(false, "build->parse round-trip: 8-bit mono"); }
  var ok = r.value.channels == 1;
  if r.value.sample_rate != 11025 { ok = false; }
  if r.value.bits_per_sample != 8 { ok = false; }
  if data.len() != 49 { ok = false; }
  if !wav_is_valid(&data) { ok = false; }
  return assert(ok, "build->parse round-trip: 8-bit mono");
}

fn t3() -> TestResult {
  let f = fmt(1, 44100, 16);
  let pcm = repeat_byte(17, 8);
  let data = wav_build_pcm(&pcm, &f);
  let r = wav_header_parse(&data);
  if !r.is_ok { return assert(false, "build->parse round-trip: 16-bit mono"); }
  var ok = r.value.channels == 1;
  if r.value.sample_rate != 44100 { ok = false; }
  if r.value.bits_per_sample != 16 { ok = false; }
  let rs = wav_le_u32(&data, 4);
  if !rs.is_ok { ok = false; } elif rs.value != 44 { ok = false; }
  return assert(ok, "build->parse round-trip: 16-bit mono");
}

fn t4() -> TestResult {
  let f = fmt(2, 48000, 24);
  let pcm = repeat_byte(34, 6);
  let data = wav_build_pcm(&pcm, &f);
  let r = wav_header_parse(&data);
  if !r.is_ok { return assert(false, "build->parse round-trip: 24-bit stereo"); }
  var ok = r.value.channels == 2;
  if r.value.sample_rate != 48000 { ok = false; }
  if r.value.bits_per_sample != 24 { ok = false; }
  return assert(ok, "build->parse round-trip: 24-bit stereo");
}

fn t5() -> TestResult {
  let f = fmt(2, 44100, 32);
  let pcm = repeat_byte(68, 8);
  let data = wav_build_pcm(&pcm, &f);
  let r = wav_header_parse(&data);
  if !r.is_ok { return assert(false, "build->parse round-trip: 32-bit stereo"); }
  var ok = r.value.channels == 2;
  if r.value.sample_rate != 44100 { ok = false; }
  if r.value.bits_per_sample != 32 { ok = false; }
  return assert(ok, "build->parse round-trip: 32-bit stereo");
}

fn t6() -> TestResult {
  var pcm = Vec[UInt8].new();
  pcm.push(0 as UInt8);
  pcm.push(127 as UInt8);
  pcm.push(128 as UInt8);
  pcm.push(200 as UInt8);
  pcm.push(255 as UInt8);
  let f = fmt(2, 44100, 16);
  let data = wav_build_pcm(&pcm, &f);
  let pd = wav_pcm_data(&data);
  if !pd.is_ok { return assert(false, "PCM payload preserved byte-for-byte"); }
  let got = pd.value;
  var ok = got.len() == 5;
  if !bytes_equal(got, pcm) { ok = false; }
  return assert(ok, "PCM payload preserved byte-for-byte");
}

fn t7() -> TestResult {
  let f = fmt(1, 8000, 16);
  let pcm = repeat_byte(127, 1600);
  let data = wav_build_pcm(&pcm, &f);
  let fr = wav_frame_count(&data);
  let du = wav_duration_ms(&data);
  var ok = true;
  if !fr.is_ok { ok = false; } elif fr.value != 800 { ok = false; }
  if !du.is_ok { ok = false; } elif du.value != 100 { ok = false; }
  let pd = wav_pcm_data(&data);
  if !pd.is_ok { ok = false; } elif pd.value.len() != 1600 { ok = false; }
  return assert(ok, "1600-byte 16-bit 8kHz mono: 800 frames, 100 ms");
}

fn t8() -> TestResult {
  let pcm = repeat_byte(17, 4);
  let f = fmt(2, 44100, 16);
  let data = wav_build_pcm(&pcm, &f);
  let br = wav_le_u32(&data, 28);
  var ok = true;
  if !br.is_ok { ok = false; } elif br.value != 176400 { ok = false; }
  if (data[32] as Int) != 4 { ok = false; }
  if (data[33] as Int) != 0 { ok = false; }
  let f8 = fmt(1, 8000, 8);
  let d8 = wav_build_pcm(&pcm, &f8);
  let br8 = wav_le_u32(&d8, 28);
  if !br8.is_ok { ok = false; } elif br8.value != 8000 { ok = false; }
  if (d8[32] as Int) != 1 { ok = false; }
  if (d8[33] as Int) != 0 { ok = false; }
  return assert(ok, "byte_rate and block_align fields are canonical");
}

fn t9() -> TestResult {
  let empty = Vec[UInt8].new();
  var ok = true;
  let f1 = fmt(0, 8000, 7);
  let d1 = wav_build_pcm(&empty, &f1);
  let r1 = wav_header_parse(&d1);
  if !r1.is_ok {
    ok = false;
  } else {
    if r1.value.channels != 1 { ok = false; }
    if r1.value.bits_per_sample != 8 { ok = false; }
    if (d1[32] as Int) != 1 { ok = false; }
  }
  let f2 = fmt(1, 8000, 12);
  let d2 = wav_build_pcm(&empty, &f2);
  let r2 = wav_header_parse(&d2);
  if !r2.is_ok {
    ok = false;
  } else {
    if r2.value.bits_per_sample != 16 { ok = false; }
    if (d2[32] as Int) != 2 { ok = false; }
  }
  let f3 = fmt(-5, 8000, 33);
  let d3 = wav_build_pcm(&empty, &f3);
  let r3 = wav_header_parse(&d3);
  if !r3.is_ok {
    ok = false;
  } else {
    if r3.value.channels != 1 { ok = false; }
    if r3.value.bits_per_sample != 32 { ok = false; }
    if (d3[32] as Int) != 4 { ok = false; }
  }
  return assert(ok, "channels and bits_per_sample are clamped in the header");
}

fn t10() -> TestResult {
  let empty = Vec[UInt8].new();
  let f = fmt(1, 8000, 16);
  let full = wav_build_pcm(&empty, &f);
  let short = truncate(&full, 43);
  let tiny = truncate(&full, 10);
  var ok = err_fmt_is(wav_header_parse(&empty), "wav: truncated header");
  if !err_fmt_is(wav_header_parse(&short), "wav: truncated header") { ok = false; }
  if !err_fmt_is(wav_header_parse(&tiny), "wav: truncated header") { ok = false; }
  if !err_bytes_is(wav_pcm_data(&tiny), "wav: truncated header") { ok = false; }
  return assert(ok, "truncated header (< 44 bytes) is Err");
}

fn t11() -> TestResult {
  let empty = Vec[UInt8].new();
  let f = fmt(1, 8000, 16);
  let full = wav_build_pcm(&empty, &f);
  let bad0 = set_byte(&full, 0, 88);
  let bad3 = set_byte(&full, 3, 88);
  var ok = err_fmt_is(wav_header_parse(&bad0), "wav: bad RIFF magic");
  if !err_fmt_is(wav_header_parse(&bad3), "wav: bad RIFF magic") { ok = false; }
  return assert(ok, "bad RIFF magic is Err");
}

fn t12() -> TestResult {
  let empty = Vec[UInt8].new();
  let f = fmt(1, 8000, 16);
  let full = wav_build_pcm(&empty, &f);
  let bad8 = set_byte(&full, 8, 88);
  let bad11 = set_byte(&full, 11, 88);
  var ok = err_fmt_is(wav_header_parse(&bad8), "wav: bad WAVE magic");
  if !err_fmt_is(wav_header_parse(&bad11), "wav: bad WAVE magic") { ok = false; }
  return assert(ok, "bad WAVE magic is Err");
}

fn t13() -> TestResult {
  let empty = Vec[UInt8].new();
  let f = fmt(1, 8000, 16);
  let full = wav_build_pcm(&empty, &f);
  let flt = set_le16(&full, 20, 3);
  let zero = set_le16(&full, 20, 0);
  var ok = err_fmt_is(wav_header_parse(&flt), "wav: non-PCM format");
  if !err_fmt_is(wav_header_parse(&zero), "wav: non-PCM format") { ok = false; }
  return assert(ok, "non-PCM format tag is Err");
}

fn t14() -> TestResult {
  let empty = Vec[UInt8].new();
  let f = fmt(1, 8000, 16);
  let full = wav_build_pcm(&empty, &f);
  let b12 = set_le16(&full, 34, 12);
  let b1 = set_le16(&full, 34, 1);
  let b64 = set_le16(&full, 34, 64);
  var ok = err_fmt_is(wav_header_parse(&b12), "wav: invalid bits per sample");
  if !err_fmt_is(wav_header_parse(&b1), "wav: invalid bits per sample") { ok = false; }
  if !err_fmt_is(wav_header_parse(&b64), "wav: invalid bits per sample") { ok = false; }
  return assert(ok, "bits_per_sample outside {8,16,24,32} is Err");
}

fn t15() -> TestResult {
  let empty = Vec[UInt8].new();
  let f = fmt(1, 8000, 16);
  let full = wav_build_pcm(&empty, &f);
  let sz = set_le32(&full, 16, 18);
  let tag = set_byte(&full, 12, 88);
  var ok = err_fmt_is(wav_header_parse(&sz), "wav: bad fmt chunk");
  if !err_fmt_is(wav_header_parse(&tag), "wav: bad fmt chunk") { ok = false; }
  return assert(ok, "fmt chunk size != 16 is Err");
}

fn t16() -> TestResult {
  let empty = Vec[UInt8].new();
  let f = fmt(1, 8000, 16);
  let full = wav_build_pcm(&empty, &f);
  let big = set_le32(&full, 4, 100);
  let zero = set_le32(&full, 4, 0);
  var ok = err_fmt_is(wav_header_parse(&big), "wav: riff size mismatch");
  if !err_fmt_is(wav_header_parse(&zero), "wav: riff size mismatch") { ok = false; }
  return assert(ok, "RIFF size field mismatch is Err");
}

fn t17() -> TestResult {
  let f = fmt(1, 8000, 16);
  let pcm = repeat_byte(9, 8);
  let data = wav_build_pcm(&pcm, &f);
  let over = set_le32(&data, 40, 1000);
  let tag = set_byte(&data, 36, 88);
  var ok = err_fmt_is(wav_header_parse(&over), "wav: data chunk out of range");
  if !err_bytes_is(wav_pcm_data(&over), "wav: data chunk out of range") { ok = false; }
  if !err_fmt_is(wav_header_parse(&tag), "wav: bad data chunk") { ok = false; }
  if !err_int_is(wav_frame_count(&over), "wav: data chunk out of range") { ok = false; }
  return assert(ok, "data chunk tag and bounds are validated");
}

fn t18() -> TestResult {
  let empty = Vec[UInt8].new();
  let f = fmt(1, 8000, 16);
  let full = wav_build_pcm(&empty, &f);
  let junk = hb("6e6f74206120776176");
  let bad = set_byte(&full, 0, 88);
  let short = truncate(&full, 43);
  var ok = wav_is_valid(&full);
  if wav_is_valid(&empty) { ok = false; }
  if wav_is_valid(&junk) { ok = false; }
  if wav_is_valid(&bad) { ok = false; }
  if wav_is_valid(&short) { ok = false; }
  return assert(ok, "wav_is_valid true/false");
}

fn t19() -> TestResult {
  let b = hb("401f0000");
  let big = hb("ffffffff");
  let hi = hb("00000080");
  let r1 = wav_le_u32(&b, 0);
  let r2 = wav_le_u32(&big, 0);
  let r3 = wav_le_u32(&hi, 0);
  let r4 = wav_le_u32(&b, 1);
  let r5 = wav_le_u32(&b, -1);
  let empty = Vec[UInt8].new();
  var ok = true;
  if !r1.is_ok { ok = false; } elif r1.value != 8000 { ok = false; }
  if !r2.is_ok { ok = false; } elif r2.value != 4294967295 { ok = false; }
  if !r3.is_ok { ok = false; } elif r3.value != 2147483648 { ok = false; }
  if r4.is_ok { ok = false; }
  if !err_int_is(r4, "wav: offset out of range") { ok = false; }
  if r5.is_ok { ok = false; }
  if !err_int_is(r5, "wav: offset out of range") { ok = false; }
  if !err_int_is(wav_le_u32(&empty, 0), "wav: offset out of range") { ok = false; }
  return assert(ok, "wav_le_u32 reads known bytes; out-of-range is Err");
}

fn t20() -> TestResult {
  let empty = Vec[UInt8].new();
  let f = fmt(1, 8000, 16);
  let full = wav_build_pcm(&empty, &f);
  let zero_ch = set_le16(&full, 22, 0);
  let zero_rate = set_le32(&full, 24, 0);
  var ok = err_int_is(wav_frame_count(&zero_ch), "wav: zero block align");
  if !err_int_is(wav_duration_ms(&zero_rate), "wav: zero sample rate") { ok = false; }
  let fr = wav_frame_count(&zero_rate);
  if !fr.is_ok { ok = false; } elif fr.value != 0 { ok = false; }
  return assert(ok, "zero block align and zero sample rate are Err");
}

fn t21() -> TestResult {
  let empty = Vec[UInt8].new();
  let f = fmt(1, 8000, 16);
  let data = wav_build_pcm(&empty, &f);
  let fr = wav_frame_count(&data);
  let du = wav_duration_ms(&data);
  let pd = wav_pcm_data(&data);
  var ok = wav_is_valid(&data);
  if !fr.is_ok { ok = false; } elif fr.value != 0 { ok = false; }
  if !du.is_ok { ok = false; } elif du.value != 0 { ok = false; }
  if !pd.is_ok { ok = false; } elif pd.value.len() != 0 { ok = false; }
  return assert(ok, "empty PCM: 0 frames, 0 ms, empty data copy");
}

fn t22() -> TestResult {
  var ok = rt(1, 8000, 8, 8);
  if !rt(1, 11025, 16, 8) { ok = false; }
  if !rt(1, 22050, 24, 8) { ok = false; }
  if !rt(1, 44100, 32, 8) { ok = false; }
  if !rt(2, 8000, 8, 8) { ok = false; }
  if !rt(2, 44100, 16, 8) { ok = false; }
  if !rt(2, 48000, 24, 8) { ok = false; }
  if !rt(2, 96000, 32, 8) { ok = false; }
  return assert(ok, "all four bit widths round-trip mono and stereo");
}

fn main() -> Int {
  io.println("=== xiom.wav conformance tests ===");
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
    io.println("xiom.wav: all tests passed");
  } else {
    io.println("xiom.wav: tests failed");
  }
  return failed;
}
