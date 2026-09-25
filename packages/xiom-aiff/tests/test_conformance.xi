// XIOM -- xiom.aiff conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the 80-bit extended sample-rate codec
// (pinned bytes, integer round-trips, rounding boundaries), the exact
// FORM/COMM/SSND layouts for AIFF and AIFC (hand-written hex fixtures),
// build -> parse round-trips across formats and rates, the chunk index
// (optional and unknown chunks, odd-size padding), the SSND offset/block
// semantics, and the full error catalog (empty/truncated FORM, magic, form
// type, FORM size, chunk header/overrun/padding, missing/duplicate/ordered
// COMM and SSND, COMM field validation, AIFC compression fields, bad chunk
// id, append validation).
//
// Err strings are compared with compare.str_compare (BUG 17 discipline:
// `==` on Str values read from a Vec lowers to a pointer comparison).

module aiff_tests
use xiom.io; use xiom.test;
use xiom.aiff;
use xiom.string;
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

fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
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

// Byte `k` (0 = least significant) of `v` as a UInt8.
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

fn append_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

fn push_be16(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 1));
  dst.push(byte_of(v, 0));
}

fn push_be32(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 3));
  dst.push(byte_of(v, 2));
  dst.push(byte_of(v, 1));
  dst.push(byte_of(v, 0));
}

// Independent fixture-side 4-character code writer (right-padded, like the
// codec but duplicated on purpose so fixtures do not depend on module code).
fn push_code4(dst: &mut Vec[UInt8], code: Str) {
  var i = 0;
  while i < 4 {
    var b = 32;
    if i < code.len() {
      b = (string.byte_at(code, i) as Int) & 0xFF;
    }
    dst.push(b as UInt8);
    i = i + 1;
  }
}

// Independent fixture-side Pascal-string writer (even total length).
fn push_pstring(dst: &mut Vec[UInt8], name: Str) {
  var n = name.len();
  if n > 255 {
    n = 255;
  }
  dst.push(n as UInt8);
  var i = 0;
  while i < n {
    dst.push(string.byte_at(name, i));
    i = i + 1;
  }
  if n % 2 == 0 {
    dst.push(0 as UInt8);
  }
}

// One chunk: 4-character id, big-endian payload size, payload, pad if odd.
fn raw_chunk(id: Str, payload: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < 4 {
    out.push(string.byte_at(id, i));
    i = i + 1;
  }
  push_be32(&mut out, payload.len());
  append_bytes(&mut out, payload);
  if payload.len() % 2 == 1 {
    out.push(0 as UInt8);
  }
  return out;
}

// Wrap a chunk body in "FORM" + big-endian size + 4-character form type.
fn form_wrap(form_type: Str, body: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(70 as UInt8);
  out.push(79 as UInt8);
  out.push(82 as UInt8);
  out.push(77 as UInt8);
  push_be32(&mut out, 4 + body.len());
  var i = 0;
  while i < 4 {
    out.push(string.byte_at(form_type, i));
    i = i + 1;
  }
  append_bytes(&mut out, body);
  return out;
}

// COMM payload built independently of the codec.
fn comm_pl(ch: Int, frames: Int, ssize: Int, rate: &Vec[UInt8], aifc: Bool, ctype: Str, cname: Str) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  push_be16(&mut p, ch);
  push_be32(&mut p, frames);
  push_be16(&mut p, ssize);
  append_bytes(&mut p, rate);
  if aifc {
    push_code4(&mut p, ctype);
    push_pstring(&mut p, cname);
  }
  return p;
}

// SSND payload: offset, block size, `offset` zero bytes, then sample data.
fn ssnd_pl(offset: Int, block: Int, data: &Vec[UInt8]) -> Vec[UInt8] {
  var p = Vec[UInt8].new();
  push_be32(&mut p, offset);
  push_be32(&mut p, block);
  var i = 0;
  while i < offset {
    p.push(0 as UInt8);
    i = i + 1;
  }
  append_bytes(&mut p, data);
  return p;
}

fn fmt(aifc: Bool, ch: Int, frames: Int, ssize: Int, rate: Int, ctype: Str, cname: Str, soff: Int, sblock: Int) -> AiffFormat {
  return AiffFormat{
    aifc: aifc;
    channels: ch;
    sample_frames: frames;
    sample_size: ssize;
    sample_rate: rate;
    compression_type: ctype;
    compression_name: cname;
    ssnd_offset: soff;
    ssnd_block_size: sblock;
  };
}

fn err_info_is(r: Result[AiffInfo, Str], want: Str) -> Bool {
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

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
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

fn set_be16(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    if i >= pos && i < pos + 2 {
      out.push(byte_of(v, pos + 1 - i));
    } else {
      out.push(data[i]);
    }
    i = i + 1;
  }
  return out;
}

fn set_be32(data: &Vec[UInt8], pos: Int, v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < data.len() {
    if i >= pos && i < pos + 4 {
      out.push(byte_of(v, pos + 3 - i));
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

// Full round-trip for one format: build -> parse -> field and payload check.
fn rt(aifc: Bool, ch: Int, frames: Int, ssize: Int, rate: Int, ctype: Str, cname: Str, n: Int) -> Bool {
  let samples = repeat_byte(90, n);
  let f = fmt(aifc, ch, frames, ssize, rate, ctype, cname, 0, 0);
  let data = aiff_build(&samples, &f);
  let pr = aiff_parse(&data);
  if !pr.is_ok { return false; }
  let info = pr.value;
  if info.aifc != aifc { return false; }
  if info.channels != ch { return false; }
  if info.sample_frames != frames { return false; }
  if info.sample_size != ssize { return false; }
  if info.sample_rate != rate { return false; }
  if !info.rate_exact { return false; }
  var want_type = "NONE";
  var want_name = "";
  if aifc {
    want_type = ctype;
    want_name = cname;
    if want_name.len() == 0 {
      want_name = "not compressed";
    }
  }
  if !str_eq(info.compression_type, want_type) { return false; }
  if !str_eq(info.compression_name, want_name) { return false; }
  if aiff_chunk_count(&info) != 2 { return false; }
  let sd = aiff_sample_data(&data, &info);
  if !sd.is_ok { return false; }
  let sdv = sd.value;
  if !bytes_equal(&sdv, &samples) { return false; }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  let e8000 = aiff_encode_sample_rate(8000);
  let w8000 = hb("400bfa00000000000000");
  if !bytes_equal(&e8000, &w8000) { ok = false; }
  let e44100 = aiff_encode_sample_rate(44100);
  let w44100 = hb("400eac44000000000000");
  if !bytes_equal(&e44100, &w44100) { ok = false; }
  let e48000 = aiff_encode_sample_rate(48000);
  let w48000 = hb("400ebb80000000000000");
  if !bytes_equal(&e48000, &w48000) { ok = false; }
  let e96000 = aiff_encode_sample_rate(96000);
  let w96000 = hb("400fbb80000000000000");
  if !bytes_equal(&e96000, &w96000) { ok = false; }
  let e11025 = aiff_encode_sample_rate(11025);
  let w11025 = hb("400cac44000000000000");
  if !bytes_equal(&e11025, &w11025) { ok = false; }
  let e192000 = aiff_encode_sample_rate(192000);
  let w192000 = hb("4010bb80000000000000");
  if !bytes_equal(&e192000, &w192000) { ok = false; }
  let e1 = aiff_encode_sample_rate(1);
  let w1 = hb("3fff8000000000000000");
  if !bytes_equal(&e1, &w1) { ok = false; }
  let e0 = aiff_encode_sample_rate(0);
  let w0 = hb("00000000000000000000");
  if !bytes_equal(&e0, &w0) { ok = false; }
  let eneg = aiff_encode_sample_rate(-5);
  if !bytes_equal(&eneg, &w0) { ok = false; }
  return assert(ok, "80-bit sample rate encoding: pinned integer rates");
}

fn t2() -> TestResult {
  var ok = true;
  let b8000 = hb("400bfa00000000000000");
  let r8000 = aiff_decode_sample_rate(&b8000, 0);
  if !r8000.is_ok { ok = false; } elif r8000.value != 8000 { ok = false; }
  let b44100 = hb("400eac44000000000000");
  let r44100 = aiff_decode_sample_rate(&b44100, 0);
  if !r44100.is_ok { ok = false; } elif r44100.value != 44100 { ok = false; }
  let bzero = hb("00000000000000000000");
  let rzero = aiff_decode_sample_rate(&bzero, 0);
  if !rzero.is_ok { ok = false; } elif rzero.value != 0 { ok = false; }
  let bden = hb("00018000000000000000");
  let rden = aiff_decode_sample_rate(&bden, 0);
  if !rden.is_ok { ok = false; } elif rden.value != 0 { ok = false; }
  if !err_int_is(aiff_decode_sample_rate(&b8000, -1), "aiff: offset out of range") { ok = false; }
  if !err_int_is(aiff_decode_sample_rate(&b8000, 1), "aiff: offset out of range") { ok = false; }
  if !err_int_is(aiff_decode_sample_rate(&b8000, 4), "aiff: offset out of range") { ok = false; }
  let empty = Vec[UInt8].new();
  if !err_int_is(aiff_decode_sample_rate(&empty, 0), "aiff: offset out of range") { ok = false; }
  return assert(ok, "80-bit sample rate decoding: pinned values, zero, denormal, bounds");
}

fn t3() -> TestResult {
  var ok = true;
  let half_up = hb("400eac44800000000000");
  let rhu = aiff_decode_sample_rate(&half_up, 0);
  if !rhu.is_ok { ok = false; } elif rhu.value != 44101 { ok = false; }
  let half_down = hb("400eac43800000000000");
  let rhd = aiff_decode_sample_rate(&half_down, 0);
  if !rhd.is_ok { ok = false; } elif rhd.value != 44100 { ok = false; }
  let below = hb("400eac43666666666666");
  let rb = aiff_decode_sample_rate(&below, 0);
  if !rb.is_ok { ok = false; } elif rb.value != 44099 { ok = false; }
  let inf = hb("7fff8000000000000000");
  if !err_int_is(aiff_decode_sample_rate(&inf, 0), "aiff: bad sample rate") { ok = false; }
  let neg = hb("c00eac44000000000000");
  if !err_int_is(aiff_decode_sample_rate(&neg, 0), "aiff: bad sample rate") { ok = false; }
  let huge = hb("403eac44000000000000");
  if !err_int_is(aiff_decode_sample_rate(&huge, 0), "aiff: bad sample rate") { ok = false; }
  return assert(ok, "80-bit rounding half-up and rejection of inf/negative/out-of-range");
}

fn t4() -> TestResult {
  var rates = Vec[Int].new();
  rates.push(1);
  rates.push(2);
  rates.push(3);
  rates.push(7);
  rates.push(1000);
  rates.push(8000);
  rates.push(11025);
  rates.push(22050);
  rates.push(32000);
  rates.push(44100);
  rates.push(48000);
  rates.push(88200);
  rates.push(96000);
  rates.push(192000);
  rates.push(384000);
  rates.push(1000000);
  rates.push(2147483647);
  var ok = true;
  var i = 0;
  while i < rates.len() {
    let r0: Int = rates[i];
    let enc = aiff_encode_sample_rate(r0);
    if enc.len() != 10 { ok = false; }
    let dec = aiff_decode_sample_rate(&enc, 0);
    if !dec.is_ok { ok = false; } elif dec.value != r0 { ok = false; }
    i = i + 1;
  }
  return assert(ok, "encode/decode round-trip over an integer rate matrix");
}

fn t5() -> TestResult {
  let data = hb("464f524d0000003641494646434f4d4d000000120001000006400010400bfa0000000000000053534e440000001000000000000000000102030405060708");
  let pr = aiff_parse(&data);
  if !pr.is_ok { return assert(false, "pinned AIFF fixture parses"); }
  let info = pr.value;
  var ok = true;
  if info.aifc { ok = false; }
  if info.channels != 1 { ok = false; }
  if info.sample_frames != 1600 { ok = false; }
  if info.sample_size != 16 { ok = false; }
  if info.sample_rate != 8000 { ok = false; }
  if !info.rate_exact { ok = false; }
  if !str_eq(info.compression_type, "NONE") { ok = false; }
  if !str_eq(info.compression_name, "") { ok = false; }
  if info.ssnd_offset != 0 { ok = false; }
  if info.ssnd_block_size != 0 { ok = false; }
  if info.ssnd_data_offset != 54 { ok = false; }
  if info.ssnd_data_size != 8 { ok = false; }
  if aiff_chunk_count(&info) != 2 { ok = false; }
  if !str_eq(aiff_chunk_id(&info, 0), "COMM") { ok = false; }
  if !str_eq(aiff_chunk_id(&info, 1), "SSND") { ok = false; }
  if aiff_chunk_offset(&info, 0) != 12 { ok = false; }
  if aiff_chunk_offset(&info, 1) != 38 { ok = false; }
  if aiff_chunk_size(&info, 0) != 18 { ok = false; }
  if aiff_chunk_size(&info, 1) != 16 { ok = false; }
  let sd = aiff_sample_data(&data, &info);
  let want_s = hb("0102030405060708");
  if !sd.is_ok { ok = false; } else {
    let sdv = sd.value;
    if !bytes_equal(&sdv, &want_s) { ok = false; }
  }
  let cd = aiff_chunk_data(&data, &info, 0);
  let want_c = hb("0001000006400010400bfa00000000000000");
  if !cd.is_ok { ok = false; } else {
    let cdv = cd.value;
    if !bytes_equal(&cdv, &want_c) { ok = false; }
  }
  return assert(ok, "pinned AIFF file: COMM/SSND fields and chunk index");
}

fn t6() -> TestResult {
  let data = hb("464f524d0000004641494643434f4d4d000000260002000000020010400eac440000000000004e4f4e450e6e6f7420636f6d707265737365640053534e440000000c000000000000000001020304");
  let pr = aiff_parse(&data);
  if !pr.is_ok { return assert(false, "pinned AIFC fixture parses"); }
  let info = pr.value;
  var ok = true;
  if !info.aifc { ok = false; }
  if info.channels != 2 { ok = false; }
  if info.sample_frames != 2 { ok = false; }
  if info.sample_size != 16 { ok = false; }
  if info.sample_rate != 44100 { ok = false; }
  if !info.rate_exact { ok = false; }
  if !str_eq(info.compression_type, "NONE") { ok = false; }
  if !str_eq(info.compression_name, "not compressed") { ok = false; }
  if info.ssnd_data_offset != 74 { ok = false; }
  if info.ssnd_data_size != 4 { ok = false; }
  if aiff_chunk_count(&info) != 2 { ok = false; }
  if aiff_chunk_offset(&info, 1) != 58 { ok = false; }
  if aiff_chunk_size(&info, 0) != 38 { ok = false; }
  let sd = aiff_sample_data(&data, &info);
  let want_s = hb("01020304");
  if !sd.is_ok { ok = false; } else {
    let sdv = sd.value;
    if !bytes_equal(&sdv, &want_s) { ok = false; }
  }
  return assert(ok, "pinned AIFC file: compression type/name pass-through and SSND span");
}

fn t7() -> TestResult {
  var ok = true;
  let samples = repeat_byte(33, 4);
  let f_odd = fmt(true, 1, 4, 16, 44100, "sowt", "abc", 0, 0);
  let d_odd = aiff_build(&samples, &f_odd);
  let p_odd = aiff_parse(&d_odd);
  if !p_odd.is_ok { ok = false; }
  else {
    if !str_eq(p_odd.value.compression_type, "sowt") { ok = false; }
    if !str_eq(p_odd.value.compression_name, "abc") { ok = false; }
  }
  let f_even = fmt(true, 1, 4, 16, 44100, "NONE", "abcd", 0, 0);
  let d_even = aiff_build(&samples, &f_even);
  let p_even = aiff_parse(&d_even);
  if !p_even.is_ok { ok = false; }
  else {
    if !str_eq(p_even.value.compression_name, "abcd") { ok = false; }
  }
  let f_empty = fmt(true, 1, 4, 16, 44100, "NONE", "", 0, 0);
  let d_empty = aiff_build(&samples, &f_empty);
  let p_empty = aiff_parse(&d_empty);
  if !p_empty.is_ok { ok = false; }
  else {
    if !str_eq(p_empty.value.compression_name, "not compressed") { ok = false; }
  }
  return assert(ok, "AIFC compression type/name pass-through and pstring padding");
}

fn t8() -> TestResult {
  let samples = hb("0102030405060708");
  let f = fmt(false, 1, 1600, 16, 8000, "", "", 0, 0);
  let data = aiff_build(&samples, &f);
  let want = hb("464f524d0000003641494646434f4d4d000000120001000006400010400bfa0000000000000053534e440000001000000000000000000102030405060708");
  var ok = bytes_equal(&data, &want);
  if data.len() != 62 { ok = false; }
  return assert(ok, "aiff_build emits the pinned AIFF layout byte-for-byte");
}

fn t9() -> TestResult {
  let samples = hb("01020304");
  let f = fmt(true, 2, 2, 16, 44100, "NONE", "not compressed", 0, 0);
  let data = aiff_build(&samples, &f);
  let want = hb("464f524d0000004641494643434f4d4d000000260002000000020010400eac440000000000004e4f4e450e6e6f7420636f6d707265737365640053534e440000000c000000000000000001020304");
  var ok = bytes_equal(&data, &want);
  if data.len() != 78 { ok = false; }
  return assert(ok, "aiff_build emits the pinned AIFC layout byte-for-byte");
}

fn t10() -> TestResult {
  var ok = true;
  if !rt(false, 1, 1600, 8, 8000, "", "", 0) { ok = false; }
  if !rt(false, 1, 1600, 16, 44100, "", "", 4) { ok = false; }
  if !rt(false, 2, 48000, 24, 48000, "", "", 6) { ok = false; }
  if !rt(false, 2, 96000, 32, 96000, "", "", 8) { ok = false; }
  if !rt(true, 1, 44100, 8, 44100, "NONE", "not compressed", 0) { ok = false; }
  if !rt(true, 2, 48000, 16, 48000, "NONE", "not compressed", 10) { ok = false; }
  if !rt(true, 1, 22050, 24, 22050, "sowt", "abc", 3) { ok = false; }
  if !rt(true, 2, 11025, 32, 11025, "NONE", "abcd", 4) { ok = false; }
  return assert(ok, "build -> parse round-trips across AIFF and AIFC formats");
}

// Container with the given COMM payload (form type AIFF or AIFC) plus a
// minimal valid SSND chunk; used to reach COMM/SSND validation errors.
fn container_with_comm(comm_pay: &Vec[UInt8], form_type: Str) -> Vec[UInt8] {
  var body = Vec[UInt8].new();
  let comm = raw_chunk("COMM", comm_pay);
  append_bytes(&mut body, &comm);
  let snd = hb("0000000000000000");
  let ssnd = raw_chunk("SSND", &snd);
  append_bytes(&mut body, &ssnd);
  return form_wrap(form_type, &body);
}

fn t11() -> TestResult {
  let samples = repeat_byte(7, 4);
  let f = fmt(false, 1, 4, 16, 8000, "", "", 0, 0);
  var file = aiff_build(&samples, &f);
  let len0 = file.len();
  let name_pl = hb("416461");
  let anno_pl = hb("68656c6c6f21");
  let c_pl = hb("32303236");
  let r1 = aiff_append_chunk(&mut file, "NAME", &name_pl);
  let r2 = aiff_append_chunk(&mut file, "ANNO", &anno_pl);
  let r3 = aiff_append_chunk(&mut file, "(c) ", &c_pl);
  var ok = r1.is_ok && r2.is_ok && r3.is_ok;
  if file.len() != len0 + 12 + 14 + 12 { ok = false; }
  let pr = aiff_parse(&file);
  if !pr.is_ok { return assert(false, "odd-sized optional chunks appended and indexed"); }
  let info = pr.value;
  if aiff_chunk_count(&info) != 5 { ok = false; }
  if !str_eq(aiff_chunk_id(&info, 2), "NAME") { ok = false; }
  if !str_eq(aiff_chunk_id(&info, 3), "ANNO") { ok = false; }
  if !str_eq(aiff_chunk_id(&info, 4), "(c) ") { ok = false; }
  if aiff_chunk_size(&info, 2) != 3 { ok = false; }
  if aiff_chunk_size(&info, 3) != 6 { ok = false; }
  if aiff_chunk_size(&info, 4) != 4 { ok = false; }
  let off2 = aiff_chunk_offset(&info, 2);
  if off2 != len0 { ok = false; }
  let nm = aiff_chunk_data(&file, &info, 2);
  if !nm.is_ok { ok = false; } else {
    let nmv = nm.value;
    if !bytes_equal(&nmv, &name_pl) { ok = false; }
  }
  if (file[off2 + 8 + 3] as Int) != 0 { ok = false; }
  let sd = aiff_sample_data(&file, &info);
  if !sd.is_ok { ok = false; } else {
    let sdv = sd.value;
    if !bytes_equal(&sdv, &samples) { ok = false; }
  }
  return assert(ok, "odd-sized optional chunks: append, pad, index and raw spans");
}

fn t12() -> TestResult {
  let samples = repeat_byte(5, 2);
  let f = fmt(false, 1, 2, 8, 8000, "", "", 0, 0);
  var file = aiff_build(&samples, &f);
  let comt_pl = hb("4142434445");
  let fver_pl = hb("a2805140");
  let r1 = aiff_append_chunk(&mut file, "COMT", &comt_pl);
  let r2 = aiff_append_chunk(&mut file, "FVER", &fver_pl);
  var ok = r1.is_ok && r2.is_ok;
  let pr = aiff_parse(&file);
  if !pr.is_ok { return assert(false, "unknown chunks are indexed and preserved"); }
  let info = pr.value;
  if aiff_chunk_count(&info) != 4 { ok = false; }
  if aiff_find_chunk(&info, "COMT") != 2 { ok = false; }
  if aiff_find_chunk(&info, "FVER") != 3 { ok = false; }
  if aiff_find_chunk(&info, "wat?") != -1 { ok = false; }
  if aiff_find_chunk(&info, "SSND") != 1 { ok = false; }
  if aiff_chunk_id(&info, -1).len() != 0 { ok = false; }
  if aiff_chunk_id(&info, 99).len() != 0 { ok = false; }
  if aiff_chunk_offset(&info, -1) != -1 { ok = false; }
  if aiff_chunk_offset(&info, 99) != -1 { ok = false; }
  if aiff_chunk_size(&info, -1) != -1 { ok = false; }
  if aiff_chunk_size(&info, 99) != -1 { ok = false; }
  if !err_bytes_is(aiff_chunk_data(&file, &info, -1), "aiff: chunk index out of range") { ok = false; }
  if !err_bytes_is(aiff_chunk_data(&file, &info, 99), "aiff: chunk index out of range") { ok = false; }
  let fv = aiff_chunk_data(&file, &info, 3);
  if !fv.is_ok { ok = false; } else {
    let fvv = fv.value;
    if !bytes_equal(&fvv, &fver_pl) { ok = false; }
  }
  return assert(ok, "unknown chunk ids, index accessors and chunk_data spans");
}

fn t13() -> TestResult {
  let samples = hb("0a0b0c");
  let f = fmt(false, 1, 3, 8, 8000, "", "", 0, 0);
  let data = aiff_build(&samples, &f);
  var ok = true;
  if data.len() != 58 { ok = false; }
  let pr = aiff_parse(&data);
  if !pr.is_ok { return assert(false, "odd-sized SSND payload: pad byte and sample span"); }
  let info = pr.value;
  if info.ssnd_data_size != 3 { ok = false; }
  if info.ssnd_data_offset != 54 { ok = false; }
  if (data[data.len() - 1] as Int) != 0 { ok = false; }
  let sd = aiff_sample_data(&data, &info);
  if !sd.is_ok { ok = false; } else {
    let sdv = sd.value;
    if !bytes_equal(&sdv, &samples) { ok = false; }
  }
  return assert(ok, "odd-sized SSND payload: pad byte and sample span");
}

fn t14() -> TestResult {
  let samples = hb("1112131415");
  let f = fmt(false, 2, 2, 16, 48000, "", "", 4, 2);
  let data = aiff_build(&samples, &f);
  let pr = aiff_parse(&data);
  if !pr.is_ok { return assert(false, "SSND offset/block fields: zero fill and data span"); }
  let info = pr.value;
  var ok = true;
  if info.ssnd_offset != 4 { ok = false; }
  if info.ssnd_block_size != 2 { ok = false; }
  if info.ssnd_data_size != 5 { ok = false; }
  let pos = aiff_chunk_offset(&info, 1);
  if info.ssnd_data_offset != pos + 16 + 4 { ok = false; }
  var z = 0;
  while z < 4 {
    if (data[pos + 16 + z] as Int) != 0 { ok = false; }
    z = z + 1;
  }
  let sd = aiff_sample_data(&data, &info);
  if !sd.is_ok { ok = false; } else {
    let sdv = sd.value;
    if !bytes_equal(&sdv, &samples) { ok = false; }
  }
  return assert(ok, "SSND offset/block fields: zero fill and data span");
}

fn t15() -> TestResult {
  let empty = Vec[UInt8].new();
  let four = hb("464f524d");
  let eleven = repeat_byte(70, 11);
  let samples = repeat_byte(1, 2);
  let f = fmt(false, 1, 2, 16, 8000, "", "", 0, 0);
  let full = aiff_build(&samples, &f);
  let bad_magic = set_byte(&full, 0, 88);
  let bad_type = set_byte(&full, 11, 88);
  let size_big = set_be32(&full, 4, 100);
  let size_zero = set_be32(&full, 4, 0);
  var ok = err_info_is(aiff_parse(&empty), "aiff: empty input");
  if !err_info_is(aiff_parse(&four), "aiff: truncated form header") { ok = false; }
  if !err_info_is(aiff_parse(&eleven), "aiff: truncated form header") { ok = false; }
  if !err_info_is(aiff_parse(&bad_magic), "aiff: bad FORM magic") { ok = false; }
  if !err_info_is(aiff_parse(&bad_type), "aiff: bad form type") { ok = false; }
  if !err_info_is(aiff_parse(&size_big), "aiff: bad FORM size") { ok = false; }
  if !err_info_is(aiff_parse(&size_zero), "aiff: bad FORM size") { ok = false; }
  return assert(ok, "FORM header errors: empty, truncated, magic, type, size");
}

fn t16() -> TestResult {
  let samples = repeat_byte(9, 2);
  let f = fmt(false, 1, 2, 16, 8000, "", "", 0, 0);
  let full = aiff_build(&samples, &f);
  let cut = truncate(&full, 42);
  let cut_fixed = set_be32(&cut, 4, 34);
  let comm_over = set_be32(&full, 16, 100);
  let ssnd_over = set_be32(&full, 42, 1000);
  var ok = err_info_is(aiff_parse(&cut_fixed), "aiff: truncated chunk header");
  if !err_info_is(aiff_parse(&comm_over), "aiff: chunk size overrun") { ok = false; }
  if !err_info_is(aiff_parse(&ssnd_over), "aiff: chunk size overrun") { ok = false; }
  var bad_body = Vec[UInt8].new();
  let rate = aiff_encode_sample_rate(8000);
  let cp = comm_pl(1, 0, 16, &rate, false, "", "");
  let comm = raw_chunk("COMM", &cp);
  append_bytes(&mut bad_body, &comm);
  bad_body.push(78 as UInt8);
  bad_body.push(65 as UInt8);
  bad_body.push(77 as UInt8);
  bad_body.push(69 as UInt8);
  push_be32(&mut bad_body, 3);
  bad_body.push(1 as UInt8);
  bad_body.push(2 as UInt8);
  bad_body.push(3 as UInt8);
  let bad_pad = form_wrap("AIFF", &bad_body);
  if !err_info_is(aiff_parse(&bad_pad), "aiff: truncated chunk padding") { ok = false; }
  return assert(ok, "chunk walk errors: truncated header, overrun, missing pad");
}

fn t17() -> TestResult {
  let rate = aiff_encode_sample_rate(8000);
  let cp = comm_pl(1, 0, 16, &rate, false, "", "");
  let sp = hb("0000000000000000");
  let comm = raw_chunk("COMM", &cp);
  let ssnd = raw_chunk("SSND", &sp);
  let name_pl = hb("4142");
  let name = raw_chunk("NAME", &name_pl);
  var body1 = Vec[UInt8].new();
  append_bytes(&mut body1, &name);
  let f1 = form_wrap("AIFF", &body1);
  var body2 = Vec[UInt8].new();
  append_bytes(&mut body2, &comm);
  let f2 = form_wrap("AIFF", &body2);
  var body3 = Vec[UInt8].new();
  append_bytes(&mut body3, &comm);
  append_bytes(&mut body3, &ssnd);
  append_bytes(&mut body3, &ssnd);
  let f3 = form_wrap("AIFF", &body3);
  var body4 = Vec[UInt8].new();
  append_bytes(&mut body4, &comm);
  append_bytes(&mut body4, &comm);
  append_bytes(&mut body4, &ssnd);
  let f4 = form_wrap("AIFF", &body4);
  var body5 = Vec[UInt8].new();
  append_bytes(&mut body5, &ssnd);
  append_bytes(&mut body5, &comm);
  let f5 = form_wrap("AIFF", &body5);
  var ok = err_info_is(aiff_parse(&f1), "aiff: missing COMM");
  if !err_info_is(aiff_parse(&f2), "aiff: missing SSND") { ok = false; }
  if !err_info_is(aiff_parse(&f3), "aiff: duplicate SSND") { ok = false; }
  if !err_info_is(aiff_parse(&f4), "aiff: duplicate COMM") { ok = false; }
  if !err_info_is(aiff_parse(&f5), "aiff: SSND before COMM") { ok = false; }
  return assert(ok, "missing, duplicate and out-of-order COMM/SSND are Err");
}

fn t18() -> TestResult {
  let rate = aiff_encode_sample_rate(8000);
  let zero_rate = hb("00000000000000000000");
  let bad_rate = hb("7fff8000000000000000");
  let cp_zero_ch = comm_pl(0, 0, 16, &rate, false, "", "");
  let cp_zero_size = comm_pl(1, 0, 0, &rate, false, "", "");
  let cp_big_size = comm_pl(1, 0, 33, &rate, false, "", "");
  let cp_zero_rate = comm_pl(1, 0, 16, &zero_rate, false, "", "");
  let cp_bad_rate = comm_pl(1, 0, 16, &bad_rate, false, "", "");
  let cp_short = hb("0001000006400010400bfa000000");
  let c1 = container_with_comm(&cp_zero_ch, "AIFF");
  let c2 = container_with_comm(&cp_zero_size, "AIFF");
  let c3 = container_with_comm(&cp_big_size, "AIFF");
  let c4 = container_with_comm(&cp_zero_rate, "AIFF");
  let c5 = container_with_comm(&cp_bad_rate, "AIFF");
  let c6 = container_with_comm(&cp_short, "AIFF");
  let c7 = container_with_comm(&cp_short, "AIFC");
  let cp18 = comm_pl(1, 0, 16, &rate, false, "", "");
  let c8 = container_with_comm(&cp18, "AIFC");
  var ok = err_info_is(aiff_parse(&c1), "aiff: zero channels");
  if !err_info_is(aiff_parse(&c2), "aiff: bad sample size") { ok = false; }
  if !err_info_is(aiff_parse(&c3), "aiff: bad sample size") { ok = false; }
  if !err_info_is(aiff_parse(&c4), "aiff: zero sample rate") { ok = false; }
  if !err_info_is(aiff_parse(&c5), "aiff: bad sample rate") { ok = false; }
  if !err_info_is(aiff_parse(&c6), "aiff: bad COMM size") { ok = false; }
  if !err_info_is(aiff_parse(&c7), "aiff: bad COMM size") { ok = false; }
  if !err_info_is(aiff_parse(&c8), "aiff: bad COMM size") { ok = false; }
  return assert(ok, "COMM validation: channels, sample size, rate, COMM size");
}

fn t19() -> TestResult {
  let rate = aiff_encode_sample_rate(8000);
  let cp = comm_pl(1, 0, 16, &rate, false, "", "");
  let comm = raw_chunk("COMM", &cp);
  let tiny_pl = hb("0000");
  let off_pl = hb("0000006400000000");
  var b1 = Vec[UInt8].new();
  append_bytes(&mut b1, &comm);
  let tiny_ssnd = raw_chunk("SSND", &tiny_pl);
  append_bytes(&mut b1, &tiny_ssnd);
  let f1 = form_wrap("AIFF", &b1);
  var b2 = Vec[UInt8].new();
  append_bytes(&mut b2, &comm);
  let off_ssnd = raw_chunk("SSND", &off_pl);
  append_bytes(&mut b2, &off_ssnd);
  let f2 = form_wrap("AIFF", &b2);
  var ok = err_info_is(aiff_parse(&f1), "aiff: short SSND");
  if !err_info_is(aiff_parse(&f2), "aiff: short SSND") { ok = false; }
  return assert(ok, "SSND shorter than 8 bytes or with an out-of-range offset is Err");
}

fn t20() -> TestResult {
  let samples = repeat_byte(4, 2);
  let f = fmt(true, 1, 2, 8, 8000, "NONE", "ok", 0, 0);
  let data = aiff_build(&samples, &f);
  let bad_type = set_byte(&data, 38, 1);
  let bad_len = set_byte(&data, 42, 200);
  let empty_name = set_byte(&data, 42, 0);
  let bad_name_byte = set_byte(&data, 43, 9);
  var ok = err_info_is(aiff_parse(&bad_type), "aiff: bad compression type");
  if !err_info_is(aiff_parse(&bad_len), "aiff: bad compression name") { ok = false; }
  if !err_info_is(aiff_parse(&empty_name), "aiff: bad compression name") { ok = false; }
  if !err_info_is(aiff_parse(&bad_name_byte), "aiff: bad compression name") { ok = false; }
  let rate = aiff_encode_sample_rate(8000);
  let cp = comm_pl(1, 0, 16, &rate, false, "", "");
  var body = Vec[UInt8].new();
  let comm = raw_chunk("COMM", &cp);
  append_bytes(&mut body, &comm);
  body.push(78 as UInt8);
  body.push(0 as UInt8);
  body.push(77 as UInt8);
  body.push(77 as UInt8);
  push_be32(&mut body, 2);
  body.push(65 as UInt8);
  body.push(66 as UInt8);
  let badid = form_wrap("AIFF", &body);
  if !err_info_is(aiff_parse(&badid), "aiff: bad chunk id") { ok = false; }
  return assert(ok, "AIFC compression field validation and bad chunk id");
}

fn t21() -> TestResult {
  let samples = repeat_byte(3, 8);
  let f = fmt(false, 1, 1600, 16, 8000, "", "", 0, 0);
  let data = aiff_build(&samples, &f);
  let pr = aiff_parse(&data);
  if !pr.is_ok { return assert(false, "aiff_is_valid and aiff_duration_ms"); }
  let info = pr.value;
  var ok = true;
  if !aiff_is_valid(&data) { ok = false; }
  let empty = Vec[UInt8].new();
  if aiff_is_valid(&empty) { ok = false; }
  let junk = hb("6e6f7420616e2061696666");
  if aiff_is_valid(&junk) { ok = false; }
  let cut = truncate(&data, 20);
  if aiff_is_valid(&cut) { ok = false; }
  let d1 = aiff_duration_ms(&info);
  if !d1.is_ok { ok = false; } elif d1.value != 200 { ok = false; }
  let f2 = fmt(false, 1, 44100, 16, 44100, "", "", 0, 0);
  let d2data = aiff_build(&samples, &f2);
  let p2 = aiff_parse(&d2data);
  if !p2.is_ok { ok = false; } else {
    let d2 = aiff_duration_ms(&p2.value);
    if !d2.is_ok { ok = false; } elif d2.value != 1000 { ok = false; }
  }
  let f3 = fmt(false, 1, 0, 16, 8000, "", "", 0, 0);
  let d3data = aiff_build(&samples, &f3);
  let p3 = aiff_parse(&d3data);
  if !p3.is_ok { ok = false; } else {
    let d3 = aiff_duration_ms(&p3.value);
    if !d3.is_ok { ok = false; } elif d3.value != 0 { ok = false; }
  }
  return assert(ok, "aiff_is_valid and aiff_duration_ms");
}

fn t22() -> TestResult {
  let samples = repeat_byte(2, 4);
  let f = fmt(false, 1, 4, 16, 8000, "", "", 0, 0);
  var file = aiff_build(&samples, &f);
  let len0 = file.len();
  let pl = hb("416461");
  var tiny = hb("464f524d");
  let r1 = aiff_append_chunk(&mut tiny, "NAME", &pl);
  var not_form = repeat_byte(70, 20);
  let r2 = aiff_append_chunk(&mut not_form, "NAME", &pl);
  let r3 = aiff_append_chunk(&mut file, "NAME5", &pl);
  var ok = err_unit_is(r1, "aiff: not a FORM container");
  if !err_unit_is(r2, "aiff: bad FORM magic") { ok = false; }
  if !err_unit_is(r3, "aiff: bad chunk id") { ok = false; }
  if file.len() != len0 { ok = false; }
  let good = aiff_append_chunk(&mut file, "NAME", &pl);
  if !good.is_ok { ok = false; }
  if file.len() != len0 + 12 { ok = false; }
  let fs = ((file[4] as Int) & 0xFF) * 16777216 + ((file[5] as Int) & 0xFF) * 65536 + ((file[6] as Int) & 0xFF) * 256 + ((file[7] as Int) & 0xFF);
  if fs != file.len() - 8 { ok = false; }
  let pr = aiff_parse(&file);
  if !pr.is_ok { ok = false; } else {
    if aiff_chunk_count(&pr.value) != 3 { ok = false; }
    if !str_eq(aiff_chunk_id(&pr.value, 2), "NAME") { ok = false; }
  }
  return assert(ok, "append validation and FORM size maintenance");
}

fn main() -> Int {
  io.println("=== xiom.aiff conformance tests ===");
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
    io.println("xiom.aiff: all tests passed");
  } else {
    io.println("xiom.aiff: tests failed");
  }
  return failed;
}
