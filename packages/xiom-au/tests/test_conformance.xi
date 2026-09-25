// XIOM -- xiom.au conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the encoding table (names, bit/byte sizes,
// unknown ids), the exact 24-byte canonical layout for au_build and
// au_build_unknown_size, build -> parse round-trips with and without the
// info field and with the 0xFFFFFFFF unknown-size sentinel, the data-size
// policy (declared underrun ignored, sentinel = rest of buffer, overrun
// rejected), data-offset validation, info raw preservation versus printable
// au_info_text validation, the audio span accessors, frame count and
// duration, builder clamping, and the full error catalog.
//
// Err strings are compared with compare.str_compare (BUG 17 discipline:
// `==` on Str values read from a Vec lowers to a pointer comparison).

module au_tests
use xiom.io; use xiom.test;
use xiom.au;
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

fn push_be32(dst: &mut Vec[UInt8], v: Int) {
  dst.push(byte_of(v, 3));
  dst.push(byte_of(v, 2));
  dst.push(byte_of(v, 1));
  dst.push(byte_of(v, 0));
}

// Independent fixture-side ".snd" magic writer.
fn push_magic(dst: &mut Vec[UInt8]) {
  dst.push(46 as UInt8);
  dst.push(115 as UInt8);
  dst.push(110 as UInt8);
  dst.push(100 as UInt8);
}

// Independent fixture-side 24-byte header writer.
fn raw_header(off: Int, size: Int, enc: Int, rate: Int, ch: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_magic(&mut out);
  push_be32(&mut out, off);
  push_be32(&mut out, size);
  push_be32(&mut out, enc);
  push_be32(&mut out, rate);
  push_be32(&mut out, ch);
  return out;
}

fn str_bytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

fn append_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
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

fn fmt(enc: Int, rate: Int, ch: Int) -> AuFormat {
  return AuFormat{
    encoding: enc;
    sample_rate: rate;
    channels: ch;
  };
}

fn err_info_is(r: Result[AuInfo, Str], want: Str) -> Bool {
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

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Full known-size round-trip: build -> parse -> field, info, span check.
fn rt(enc: Int, rate: Int, ch: Int, n: Int, info: Str) -> Bool {
  let samples = repeat_byte(170, n);
  let f = fmt(enc, rate, ch);
  let data = au_build(&samples, &f, info);
  let pr = au_parse(&data);
  if !pr.is_ok { return false; }
  let parsed = pr.value;
  if parsed.encoding != enc { return false; }
  if parsed.sample_rate != rate { return false; }
  if parsed.channels != ch { return false; }
  if !parsed.size_known { return false; }
  if parsed.stored_size != n { return false; }
  if parsed.data_size != n { return false; }
  if parsed.data_offset != 24 + info.len() { return false; }
  let it = au_info_text(&parsed);
  if !it.is_ok { return false; }
  if !str_eq(it.value, info) { return false; }
  let ad = au_audio_data(&data, &parsed);
  if !ad.is_ok { return false; }
  let adv = ad.value;
  if !bytes_equal(&adv, &samples) { return false; }
  return true;
}

// Full unknown-size-sentinel round-trip.
fn rtu(enc: Int, rate: Int, ch: Int, n: Int, info: Str) -> Bool {
  let samples = repeat_byte(170, n);
  let f = fmt(enc, rate, ch);
  let data = au_build_unknown_size(&samples, &f, info);
  let pr = au_parse(&data);
  if !pr.is_ok { return false; }
  let parsed = pr.value;
  if parsed.size_known { return false; }
  if parsed.stored_size != 4294967295 { return false; }
  if parsed.data_size != n { return false; }
  if parsed.data_offset != 24 + info.len() { return false; }
  let ad = au_audio_data(&data, &parsed);
  if !ad.is_ok { return false; }
  let adv = ad.value;
  if !bytes_equal(&adv, &samples) { return false; }
  let it = au_info_text(&parsed);
  if !it.is_ok { return false; }
  if !str_eq(it.value, info) { return false; }
  return true;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  if !str_eq(au_encoding_name(1), "mu-law 8-bit") { ok = false; }
  if !str_eq(au_encoding_name(2), "linear 8-bit") { ok = false; }
  if !str_eq(au_encoding_name(3), "linear 16-bit") { ok = false; }
  if !str_eq(au_encoding_name(4), "linear 24-bit") { ok = false; }
  if !str_eq(au_encoding_name(5), "linear 32-bit") { ok = false; }
  if !str_eq(au_encoding_name(6), "float 32-bit") { ok = false; }
  if !str_eq(au_encoding_name(7), "double 64-bit") { ok = false; }
  if !str_eq(au_encoding_name(27), "A-law 8-bit") { ok = false; }
  if au_encoding_bits(1) != 8 { ok = false; }
  if au_encoding_bits(3) != 16 { ok = false; }
  if au_encoding_bits(4) != 24 { ok = false; }
  if au_encoding_bits(5) != 32 { ok = false; }
  if au_encoding_bits(6) != 32 { ok = false; }
  if au_encoding_bits(7) != 64 { ok = false; }
  if au_encoding_bits(27) != 8 { ok = false; }
  if au_encoding_bytes(1) != 1 { ok = false; }
  if au_encoding_bytes(3) != 2 { ok = false; }
  if au_encoding_bytes(4) != 3 { ok = false; }
  if au_encoding_bytes(5) != 4 { ok = false; }
  if au_encoding_bytes(7) != 8 { ok = false; }
  if au_encoding_bytes(27) != 1 { ok = false; }
  if !str_eq(au_encoding_name(0), "") { ok = false; }
  if !str_eq(au_encoding_name(8), "") { ok = false; }
  if !str_eq(au_encoding_name(23), "") { ok = false; }
  if !str_eq(au_encoding_name(26), "") { ok = false; }
  if !str_eq(au_encoding_name(28), "") { ok = false; }
  if !str_eq(au_encoding_name(4294967295), "") { ok = false; }
  if au_encoding_bits(0) != 0 { ok = false; }
  if au_encoding_bits(8) != 0 { ok = false; }
  if au_encoding_bits(4294967295) != 0 { ok = false; }
  if au_encoding_bytes(8) != 0 { ok = false; }
  if au_encoding_bytes(4294967295) != 0 { ok = false; }
  return assert(ok, "encoding table: names, bit and byte sizes, unknown ids");
}

fn t2() -> TestResult {
  let data = hb("2e736e6400000018000000040000000100001f400000000101020304");
  let pr = au_parse(&data);
  if !pr.is_ok { return assert(false, "pinned mu-law fixture parses"); }
  let info = pr.value;
  var ok = true;
  if info.encoding != 1 { ok = false; }
  if info.sample_rate != 8000 { ok = false; }
  if info.channels != 1 { ok = false; }
  if !info.size_known { ok = false; }
  if info.stored_size != 4 { ok = false; }
  if info.data_offset != 24 { ok = false; }
  if info.data_size != 4 { ok = false; }
  if au_data_offset(&info) != 24 { ok = false; }
  if au_data_size(&info) != 4 { ok = false; }
  if au_channels(&info) != 1 { ok = false; }
  if au_sample_rate(&info) != 8000 { ok = false; }
  if !au_size_known(&info) { ok = false; }
  if au_stored_size(&info) != 4 { ok = false; }
  let ib = au_info_bytes(&info);
  if ib.len() != 0 { ok = false; }
  let it = au_info_text(&info);
  if !it.is_ok { ok = false; } elif !str_eq(it.value, "") { ok = false; }
  let ad = au_audio_data(&data, &info);
  let want = hb("01020304");
  if !ad.is_ok { ok = false; } else {
    let adv = ad.value;
    if !bytes_equal(&adv, &want) { ok = false; }
  }
  if !au_is_valid(&data) { ok = false; }
  return assert(ok, "pinned mu-law file: header fields, span and audio bytes");
}

fn t3() -> TestResult {
  let data = hb("2e736e640000001b00000008000000030000ac44000000024164610102030405060708");
  let pr = au_parse(&data);
  if !pr.is_ok { return assert(false, "pinned info fixture parses"); }
  let info = pr.value;
  var ok = true;
  if info.encoding != 3 { ok = false; }
  if info.sample_rate != 44100 { ok = false; }
  if info.channels != 2 { ok = false; }
  if info.data_offset != 27 { ok = false; }
  if info.data_size != 8 { ok = false; }
  if !info.size_known { ok = false; }
  let ib = au_info_bytes(&info);
  let want_ib = str_bytes("Ada");
  if !bytes_equal(&ib, &want_ib) { ok = false; }
  let it = au_info_text(&info);
  if !it.is_ok { ok = false; } elif !str_eq(it.value, "Ada") { ok = false; }
  let ad = au_audio_data(&data, &info);
  let want = hb("0102030405060708");
  if !ad.is_ok { ok = false; } else {
    let adv = ad.value;
    if !bytes_equal(&adv, &want) { ok = false; }
  }
  let fc = au_frame_count(&info);
  if !fc.is_ok { ok = false; } elif fc.value != 2 { ok = false; }
  return assert(ok, "optional info field: raw bytes, printable text and span");
}

fn t4() -> TestResult {
  let samples = hb("a1a2a3a4a5a6");
  let f = fmt(27, 8000, 1);
  let data = au_build_unknown_size(&samples, &f, "");
  let want = hb("2e736e6400000018ffffffff0000001b00001f4000000001a1a2a3a4a5a6");
  var ok = bytes_equal(&data, &want);
  let pr = au_parse(&data);
  if !pr.is_ok { return assert(false, "unknown-size sentinel parses"); }
  let info = pr.value;
  if info.size_known { ok = false; }
  if info.stored_size != 4294967295 { ok = false; }
  if info.data_size != 6 { ok = false; }
  if info.data_offset != 24 { ok = false; }
  let ad = au_audio_data(&data, &info);
  if !ad.is_ok { ok = false; } else {
    let adv = ad.value;
    if !bytes_equal(&adv, &samples) { ok = false; }
  }
  let data2 = au_build_unknown_size(&samples, &f, "draft");
  let p2 = au_parse(&data2);
  if !p2.is_ok { ok = false; } else {
    let i2 = p2.value;
    if i2.data_offset != 29 { ok = false; }
    if i2.data_size != 6 { ok = false; }
    if i2.size_known { ok = false; }
    let it2 = au_info_text(&i2);
    if !it2.is_ok { ok = false; } elif !str_eq(it2.value, "draft") { ok = false; }
  }
  return assert(ok, "unknown-size sentinel: pinned bytes, rest-of-buffer span, with info");
}

fn t5() -> TestResult {
  let samples = hb("01020304");
  let f = fmt(1, 8000, 1);
  let data = au_build(&samples, &f, "");
  let want = hb("2e736e6400000018000000040000000100001f400000000101020304");
  var ok = bytes_equal(&data, &want);
  if data.len() != 28 { ok = false; }
  return assert(ok, "au_build emits the pinned 28-byte canonical layout");
}

fn t6() -> TestResult {
  let samples = hb("01020304");
  let f = fmt(3, 8000, 1);
  let data = au_build(&samples, &f, "Ada");
  let want = hb("2e736e640000001b000000040000000300001f400000000141646101020304");
  var ok = bytes_equal(&data, &want);
  if data.len() != 31 { ok = false; }
  return assert(ok, "au_build emits the pinned layout with a 3-byte info field");
}

fn t7() -> TestResult {
  var ok = true;
  if !rt(1, 8000, 1, 4, "") { ok = false; }
  if !rt(2, 8000, 1, 4, "") { ok = false; }
  if !rt(3, 44100, 2, 8, "") { ok = false; }
  if !rt(4, 48000, 2, 6, "") { ok = false; }
  if !rt(5, 96000, 1, 8, "") { ok = false; }
  if !rt(6, 48000, 2, 8, "") { ok = false; }
  if !rt(7, 192000, 1, 16, "") { ok = false; }
  if !rt(27, 8000, 1, 4, "") { ok = false; }
  return assert(ok, "build -> parse round-trips across the encoding table");
}

fn t8() -> TestResult {
  var ok = true;
  if !rt(3, 44100, 2, 8, "x") { ok = false; }
  if !rt(3, 44100, 2, 8, "Ada") { ok = false; }
  if !rt(3, 44100, 2, 8, "created by xiom.au") { ok = false; }
  if !rt(3, 44100, 2, 8, "Sun/NeXT AU") { ok = false; }
  let samples = hb("0102");
  let f = fmt(1, 8000, 1);
  let data = au_build(&samples, &f, "");
  let pr = au_parse(&data);
  if !pr.is_ok { ok = false; } else {
    if pr.value.data_offset != 24 { ok = false; }
    if pr.value.data_size != 2 { ok = false; }
  }
  return assert(ok, "info field round-trips at several lengths; empty info keeps offset 24");
}

fn t9() -> TestResult {
  var ok = true;
  if !rtu(1, 8000, 1, 4, "") { ok = false; }
  if !rtu(3, 44100, 2, 10, "") { ok = false; }
  if !rtu(7, 192000, 2, 24, "session") { ok = false; }
  if !rtu(27, 8000, 1, 6, "A") { ok = false; }
  return assert(ok, "unknown-size sentinel round-trips with and without info");
}

fn t10() -> TestResult {
  let samples = hb("01020304");
  let f = fmt(1, 8000, 1);
  let base = au_build(&samples, &f, "");
  var ok = true;
  let small = set_be32(&base, 8, 2);
  let pr = au_parse(&small);
  if !pr.is_ok { ok = false; } else {
    let info = pr.value;
    if !info.size_known { ok = false; }
    if info.stored_size != 2 { ok = false; }
    if info.data_size != 2 { ok = false; }
    if info.data_offset != 24 { ok = false; }
    let ad = au_audio_data(&small, &info);
    let want = hb("0102");
    if !ad.is_ok { ok = false; } else {
      let adv = ad.value;
      if !bytes_equal(&adv, &want) { ok = false; }
    }
  }
  let zero = set_be32(&base, 8, 0);
  let pz = au_parse(&zero);
  if !pz.is_ok { ok = false; } else {
    let iz = pz.value;
    if iz.data_size != 0 { ok = false; }
    let az = au_audio_data(&zero, &iz);
    if !az.is_ok { ok = false; } elif az.value.len() != 0 { ok = false; }
  }
  let over = set_be32(&base, 8, 5);
  if !err_info_is(au_parse(&over), "au: data size overrun") { ok = false; }
  return assert(ok, "declared size: underrun ignored, zero accepted, overrun is Err");
}

fn t11() -> TestResult {
  let empty = Vec[UInt8].new();
  let short = repeat_byte(0, 23);
  let four = hb("2e736e64");
  let bad = hb("2f736e6400000018000000000000000100001f4000000001");
  var ok = err_info_is(au_parse(&empty), "au: empty input");
  if !err_info_is(au_parse(&short), "au: truncated header") { ok = false; }
  if !err_info_is(au_parse(&four), "au: truncated header") { ok = false; }
  if !err_info_is(au_parse(&bad), "au: bad magic") { ok = false; }
  return assert(ok, "header errors: empty, shorter than 24 bytes, bad magic");
}

fn t12() -> TestResult {
  let base = hb("2e736e6400000018000000040000000100001f400000000101020304");
  let len = base.len();
  let off0 = set_be32(&base, 4, 0);
  let off23 = set_be32(&base, 4, 23);
  let off_lead = set_be32(&base, 4, len + 1);
  let off_end = set_be32(&base, 4, len);
  let off_end0 = set_be32(&off_end, 8, 0);
  let off_endu = set_be32(&off_end, 8, 4294967295);
  let off25 = set_be32(&base, 4, 25);
  var ok = err_info_is(au_parse(&off0), "au: bad data offset");
  if !err_info_is(au_parse(&off23), "au: bad data offset") { ok = false; }
  if !err_info_is(au_parse(&off_lead), "au: data offset past end") { ok = false; }
  if !err_info_is(au_parse(&off25), "au: data size overrun") { ok = false; }
  let pt = au_parse(&off_end0);
  if !pt.is_ok { ok = false; } else {
    let it = pt.value;
    if it.data_offset != len { ok = false; }
    if it.data_size != 0 { ok = false; }
  }
  let pu = au_parse(&off_endu);
  if !pu.is_ok { ok = false; } else {
    let iu = pu.value;
    if iu.data_offset != len { ok = false; }
    if iu.data_size != 0 { ok = false; }
    if iu.size_known { ok = false; }
  }
  return assert(ok, "data offset validation: >= 24, within buffer, empty span");
}

fn t13() -> TestResult {
  let base = hb("2e736e6400000018000000040000000100001f400000000101020304");
  var ok = true;
  let e0 = set_be32(&base, 12, 0);
  let e8 = set_be32(&base, 12, 8);
  let e23 = set_be32(&base, 12, 23);
  let e26 = set_be32(&base, 12, 26);
  let e28 = set_be32(&base, 12, 28);
  let emax = set_be32(&base, 12, 4294967295);
  if !err_info_is(au_parse(&e0), "au: unknown encoding") { ok = false; }
  if !err_info_is(au_parse(&e8), "au: unknown encoding") { ok = false; }
  if !err_info_is(au_parse(&e23), "au: unknown encoding") { ok = false; }
  if !err_info_is(au_parse(&e26), "au: unknown encoding") { ok = false; }
  if !err_info_is(au_parse(&e28), "au: unknown encoding") { ok = false; }
  if !err_info_is(au_parse(&emax), "au: unknown encoding") { ok = false; }
  return assert(ok, "encoding validation: only 1-7 and 27 are known");
}

fn t14() -> TestResult {
  let base = hb("2e736e6400000018000000040000000100001f400000000101020304");
  let c0 = set_be32(&base, 20, 0);
  let r0 = set_be32(&base, 16, 0);
  var ok = err_info_is(au_parse(&c0), "au: zero channels");
  if !err_info_is(au_parse(&r0), "au: zero sample rate") { ok = false; }
  return assert(ok, "zero channels and zero sample rate are Err");
}

fn t15() -> TestResult {
  let samples = hb("0102");
  let f = fmt(1, 8000, 1);
  var ok = true;
  let three = au_build(&samples, &f, "abc");
  let p3 = au_parse(&three);
  if !p3.is_ok { return assert(false, "printable info round-trip: parse"); }
  let i3 = p3.value;
  let t3 = au_info_text(&i3);
  if !t3.is_ok { ok = false; } elif !str_eq(t3.value, "abc") { ok = false; }
  let space = au_build(&samples, &f, " a");
  let ps = au_parse(&space);
  if !ps.is_ok { ok = false; } else {
    let isp = ps.value;
    let ts = au_info_text(&isp);
    if !ts.is_ok { ok = false; } elif !str_eq(ts.value, " a") { ok = false; }
  }
  let tilde = au_build(&samples, &f, "~");
  let pt = au_parse(&tilde);
  if !pt.is_ok { ok = false; } else {
    let itl = pt.value;
    let tl = au_info_text(&itl);
    if !tl.is_ok { ok = false; } elif !str_eq(tl.value, "~") { ok = false; }
  }
  let nul = set_byte(&three, 24, 0);
  let pn = au_parse(&nul);
  if !pn.is_ok { ok = false; } else {
    let inl = pn.value;
    if au_info_text(&inl).is_ok { ok = false; }
    if !err_str_is(au_info_text(&inl), "au: bad info text") { ok = false; }
    let ib = au_info_bytes(&inl);
    if ib.len() != 3 { ok = false; }
    if (ib[0] as Int) != 0 { ok = false; }
    if (ib[1] as Int) != 98 { ok = false; }
    if (ib[2] as Int) != 99 { ok = false; }
  }
  let ctl = set_byte(&three, 26, 9);
  let pc = au_parse(&ctl);
  if !pc.is_ok { ok = false; } else {
    let ic = pc.value;
    if !err_str_is(au_info_text(&ic), "au: bad info text") { ok = false; }
  }
  let del = set_byte(&three, 25, 127);
  let pd = au_parse(&del);
  if !pd.is_ok { ok = false; } else {
    let idl = pd.value;
    if !err_str_is(au_info_text(&idl), "au: bad info text") { ok = false; }
  }
  return assert(ok, "info is preserved raw; au_info_text rejects non-printable bytes");
}

fn t16() -> TestResult {
  var ok = true;
  let zeros = repeat_byte(0, 8000);
  let f = fmt(1, 8000, 1);
  let data = au_build(&zeros, &f, "");
  let pr = au_parse(&data);
  if !pr.is_ok { return assert(false, "frame count and duration: parse"); }
  let info = pr.value;
  let fc = au_frame_count(&info);
  if !fc.is_ok { ok = false; } elif fc.value != 8000 { ok = false; }
  let dm = au_duration_ms(&info);
  if !dm.is_ok { ok = false; } elif dm.value != 1000 { ok = false; }
  let stereo = repeat_byte(0, 176400);
  let f2 = fmt(3, 44100, 2);
  let d2 = au_build(&stereo, &f2, "");
  let p2 = au_parse(&d2);
  if !p2.is_ok { ok = false; } else {
    let i2 = p2.value;
    let c2 = au_frame_count(&i2);
    if !c2.is_ok { ok = false; } elif c2.value != 44100 { ok = false; }
    let m2 = au_duration_ms(&i2);
    if !m2.is_ok { ok = false; } elif m2.value != 1000 { ok = false; }
  }
  let five = hb("0102030405");
  let d3 = au_build(&five, &f2, "");
  let p3 = au_parse(&d3);
  if !p3.is_ok { ok = false; } else {
    let i3 = p3.value;
    let c3 = au_frame_count(&i3);
    if !c3.is_ok { ok = false; } elif c3.value != 1 { ok = false; }
  }
  return assert(ok, "frame count and duration: mu-law mono and 16-bit stereo");
}

fn t17() -> TestResult {
  var ok = true;
  let nb = Vec[UInt8].new();
  let unknown = AuInfo{
    encoding: 9;
    sample_rate: 8000;
    channels: 1;
    size_known: true;
    stored_size: 10;
    data_offset: 24;
    data_size: 10;
    info_bytes: nb;
  };
  if !err_int_is(au_frame_count(&unknown), "au: unknown encoding") { ok = false; }
  if !err_int_is(au_duration_ms(&unknown), "au: unknown encoding") { ok = false; }
  let nb2 = Vec[UInt8].new();
  let zero_ch = AuInfo{
    encoding: 1;
    sample_rate: 8000;
    channels: 0;
    size_known: true;
    stored_size: 10;
    data_offset: 24;
    data_size: 10;
    info_bytes: nb2;
  };
  if !err_int_is(au_frame_count(&zero_ch), "au: zero channels") { ok = false; }
  let nb3 = Vec[UInt8].new();
  let zero_rate = AuInfo{
    encoding: 1;
    sample_rate: 0;
    channels: 1;
    size_known: true;
    stored_size: 10;
    data_offset: 24;
    data_size: 10;
    info_bytes: nb3;
  };
  if !err_int_is(au_duration_ms(&zero_rate), "au: zero sample rate") { ok = false; }
  let fc = au_frame_count(&zero_rate);
  if !fc.is_ok { ok = false; } elif fc.value != 10 { ok = false; }
  return assert(ok, "hand-built metadata: unknown encoding, zero channels, zero rate");
}

fn t18() -> TestResult {
  let samples = hb("0102030405060708");
  let f = fmt(3, 44100, 2);
  let data = au_build(&samples, &f, "");
  let pr = au_parse(&data);
  if !pr.is_ok { return assert(false, "audio span mismatch: parse"); }
  let info = pr.value;
  var ok = true;
  let header_only = raw_header(24, 8, 3, 44100, 2);
  if !err_bytes_is(au_audio_data(&header_only, &info), "au: data size overrun") { ok = false; }
  let cut = truncate(&data, 30);
  if !err_bytes_is(au_audio_data(&cut, &info), "au: data size overrun") { ok = false; }
  let ad = au_audio_data(&data, &info);
  if !ad.is_ok { ok = false; } else {
    let adv = ad.value;
    if !bytes_equal(&adv, &samples) { ok = false; }
  }
  return assert(ok, "au_audio_data rejects spans that do not fit the buffer");
}

fn t19() -> TestResult {
  let samples = hb("0102");
  var ok = true;
  let f1 = fmt(3, -5, 0);
  let d1 = au_build(&samples, &f1, "");
  if d1.len() != 26 { ok = false; }
  if (d1[16] as Int) != 0 { ok = false; }
  if (d1[17] as Int) != 0 { ok = false; }
  if (d1[18] as Int) != 0 { ok = false; }
  if (d1[19] as Int) != 0 { ok = false; }
  if (d1[20] as Int) != 0 { ok = false; }
  if (d1[21] as Int) != 0 { ok = false; }
  if (d1[22] as Int) != 0 { ok = false; }
  if (d1[23] as Int) != 1 { ok = false; }
  let f2 = fmt(1, 4294967396, 4294967296);
  let d2 = au_build(&samples, &f2, "");
  var ones = 0;
  var i = 16;
  while i < 24 {
    if (d2[i] as Int) == 255 { ones = ones + 1; }
    i = i + 1;
  }
  if ones != 8 { ok = false; }
  let f3 = fmt(9, 8000, 1);
  let d3 = au_build(&samples, &f3, "");
  if (d3[15] as Int) != 9 { ok = false; }
  if !err_info_is(au_parse(&d3), "au: unknown encoding") { ok = false; }
  return assert(ok, "builder clamps u32 fields, channels to >= 1, encoding verbatim");
}

fn t20() -> TestResult {
  var ok = true;
  let samples = hb("0102");
  let f = fmt(1, 8000, 1);
  let good = au_build(&samples, &f, "ok");
  if !au_is_valid(&good) { ok = false; }
  let empty = Vec[UInt8].new();
  if au_is_valid(&empty) { ok = false; }
  let junk = hb("6e6f7420617564696f");
  if au_is_valid(&junk) { ok = false; }
  let cut = truncate(&good, 20);
  if au_is_valid(&cut) { ok = false; }
  return assert(ok, "au_is_valid true/false paths");
}

fn t21() -> TestResult {
  var ok = true;
  if !str_eq(au_encoding_name(2), "linear 8-bit") { ok = false; }
  if !str_eq(au_encoding_name(4), "linear 24-bit") { ok = false; }
  if !str_eq(au_encoding_name(5), "linear 32-bit") { ok = false; }
  if !str_eq(au_encoding_name(6), "float 32-bit") { ok = false; }
  if au_encoding_bits(2) != 8 { ok = false; }
  if au_encoding_bytes(2) != 1 { ok = false; }
  if au_encoding_bytes(6) != 4 { ok = false; }
  if au_encoding_bits(27) != 8 { ok = false; }
  return assert(ok, "encoding table: remaining names and sizes");
}

fn t22() -> TestResult {
  let data = hb("2e736e640000001a00000004000000030000bb8000000002415500112233");
  let pr = au_parse(&data);
  if !pr.is_ok { return assert(false, "pinned 16-bit stereo fixture parses"); }
  let info = pr.value;
  var ok = true;
  if info.encoding != 3 { ok = false; }
  if au_data_offset(&info) != 26 { ok = false; }
  if au_data_size(&info) != 4 { ok = false; }
  if au_channels(&info) != 2 { ok = false; }
  if au_sample_rate(&info) != 48000 { ok = false; }
  if !au_size_known(&info) { ok = false; }
  if au_stored_size(&info) != 4 { ok = false; }
  let it = au_info_text(&info);
  if !it.is_ok { ok = false; } elif !str_eq(it.value, "AU") { ok = false; }
  let fc = au_frame_count(&info);
  if !fc.is_ok { ok = false; } elif fc.value != 1 { ok = false; }
  let dm = au_duration_ms(&info);
  if !dm.is_ok { ok = false; } elif dm.value != 0 { ok = false; }
  let ad = au_audio_data(&data, &info);
  let want = hb("00112233");
  if !ad.is_ok { ok = false; } else {
    let adv = ad.value;
    if !bytes_equal(&adv, &want) { ok = false; }
  }
  return assert(ok, "pinned 16-bit stereo fixture: accessors, info text, frame count");
}

fn main() -> Int {
  io.println("=== xiom.au conformance tests ===");
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
    io.println("xiom.au: all tests passed");
  } else {
    io.println("xiom.au: tests failed");
  }
  return failed;
}
