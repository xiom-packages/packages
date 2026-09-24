// XIOM -- xiom.tlv conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.tlv codec against its documented
// flat big-endian TLV layout and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: hand-built streams at 1/1, 2/2 and mixed
// widths with pinned tags/offsets/lengths; tlv_find first-match and -1;
// exact value slices and out-of-bounds errors; exact append bytes for
// 1-byte and 2-byte widths; width/tag/value-size errors with an unchanged
// output buffer; build_from equivalence to per-entry appends; empty-buffer
// and zero-entry behavior; trailing partial header and value-overrun
// errors; bad widths; out-of-range accessors; and build->parse round-trips
// at mixed and 4/4 widths.
//
// Str values are never compared with `==` (BUG 17 discipline: `==` on a
// Str read from a Vec lowers to a pointer comparison); error messages go
// through compare.str_compare.

module tlv_tests
use xiom.io; use xiom.test;
use xiom.tlv;
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

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
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

// Prefix of a byte vector, used to build short source buffers.
fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_list_is(r: Result[TlvList, Str], want: Str) -> Bool {
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

fn value_is(data: &Vec[UInt8], l: &TlvList, i: Int, want: Vec[UInt8]) -> Bool {
  let r = tlv_value(data, l, i);
  if !r.is_ok {
    return false;
  }
  let v: Vec[UInt8] = r.value;
  return bytes_equal(v, want);
}

// Value bytes of entry `i`, or an empty vector on error (callers only use
// it after a successful parse and a checked index).
fn value_at(data: &Vec[UInt8], l: &TlvList, i: Int) -> Vec[UInt8] {
  let r = tlv_value(data, l, i);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = hb("010361626302007f02ff00");
  let r = tlv_parse(&data, 1, 1);
  if !r.is_ok { return assert(false, "1/1 stream must parse"); }
  let l: TlvList = r.value;
  var ok = tlv_count(&l) == 3;
  if tlv_tag(&l, 0) != 1 { ok = false; }
  if tlv_tag(&l, 1) != 2 { ok = false; }
  if tlv_tag(&l, 2) != 127 { ok = false; }
  let o0: Int = l.value_offsets[0];
  let o1: Int = l.value_offsets[1];
  let o2: Int = l.value_offsets[2];
  let n0: Int = l.value_lengths[0];
  let n1: Int = l.value_lengths[1];
  let n2: Int = l.value_lengths[2];
  if o0 != 2 { ok = false; }
  if o1 != 7 { ok = false; }
  if o2 != 9 { ok = false; }
  if n0 != 3 { ok = false; }
  if n1 != 0 { ok = false; }
  if n2 != 2 { ok = false; }
  if !value_is(&data, &l, 0, bytes_of("abc")) { ok = false; }
  if !value_is(&data, &l, 1, Vec[UInt8].new()) { ok = false; }
  if !value_is(&data, &l, 2, hb("ff00")) { ok = false; }
  return assert(ok, "1/1 three-entry stream: pinned tags, offsets and lengths");
}

fn t2() -> TestResult {
  let data = hb("01020002cafe00000000ffff00015a");
  let r = tlv_parse(&data, 2, 2);
  if !r.is_ok { return assert(false, "2/2 stream must parse"); }
  let l: TlvList = r.value;
  var ok = tlv_count(&l) == 3;
  if tlv_tag(&l, 0) != 258 { ok = false; }
  if tlv_tag(&l, 1) != 0 { ok = false; }
  if tlv_tag(&l, 2) != 65535 { ok = false; }
  let o0: Int = l.value_offsets[0];
  let o1: Int = l.value_offsets[1];
  let o2: Int = l.value_offsets[2];
  let n0: Int = l.value_lengths[0];
  let n1: Int = l.value_lengths[1];
  let n2: Int = l.value_lengths[2];
  if o0 != 4 { ok = false; }
  if o1 != 10 { ok = false; }
  if o2 != 14 { ok = false; }
  if n0 != 2 { ok = false; }
  if n1 != 0 { ok = false; }
  if n2 != 1 { ok = false; }
  if !value_is(&data, &l, 0, hb("cafe")) { ok = false; }
  if !value_is(&data, &l, 1, Vec[UInt8].new()) { ok = false; }
  if !value_is(&data, &l, 2, hb("5a")) { ok = false; }
  return assert(ok, "2/2 three-entry stream: pinned tags, offsets and lengths");
}

fn t3() -> TestResult {
  let data = hb("0500026162060000ff000180");
  let r = tlv_parse(&data, 1, 2);
  if !r.is_ok { return assert(false, "1/2 stream must parse"); }
  let l: TlvList = r.value;
  var ok = tlv_count(&l) == 3;
  if tlv_tag(&l, 0) != 5 { ok = false; }
  if tlv_tag(&l, 1) != 6 { ok = false; }
  if tlv_tag(&l, 2) != 255 { ok = false; }
  let o0: Int = l.value_offsets[0];
  let o1: Int = l.value_offsets[1];
  let o2: Int = l.value_offsets[2];
  let n0: Int = l.value_lengths[0];
  let n1: Int = l.value_lengths[1];
  let n2: Int = l.value_lengths[2];
  if o0 != 3 { ok = false; }
  if o1 != 8 { ok = false; }
  if o2 != 11 { ok = false; }
  if n0 != 2 { ok = false; }
  if n1 != 0 { ok = false; }
  if n2 != 1 { ok = false; }
  if !value_is(&data, &l, 0, bytes_of("ab")) { ok = false; }
  if !value_is(&data, &l, 1, Vec[UInt8].new()) { ok = false; }
  if !value_is(&data, &l, 2, hb("80")) { ok = false; }
  return assert(ok, "mixed 1/2 widths: pinned offsets and unsigned 0xff tag");
}

fn t4() -> TestResult {
  let data = hb("050161050162090163");
  let r = tlv_parse(&data, 1, 1);
  if !r.is_ok { return assert(false, "duplicate-tag stream must parse"); }
  let l: TlvList = r.value;
  var ok = tlv_find(&l, 5) == 0;
  if tlv_find(&l, 9) != 2 { ok = false; }
  if tlv_find(&l, 66) != -1 { ok = false; }
  if tlv_find(&l, -7) != -1 { ok = false; }
  var empty_buf = Vec[UInt8].new();
  let er = tlv_parse(&empty_buf, 1, 1);
  if !er.is_ok { return assert(false, "empty buffer must parse"); }
  let el: TlvList = er.value;
  if tlv_find(&el, 5) != -1 { ok = false; }
  return assert(ok, "tlv_find returns the first match and -1 when absent");
}

fn t5() -> TestResult {
  let data = hb("010361626302007f02ff00");
  let r = tlv_parse(&data, 1, 1);
  if !r.is_ok { return assert(false, "stream must parse"); }
  let l: TlvList = r.value;
  var ok = value_is(&data, &l, 0, bytes_of("abc"));
  if !value_is(&data, &l, 2, hb("ff00")) { ok = false; }
  if !err_bytes_is(tlv_value(&data, &l, 3), "tlv: index out of range") { ok = false; }
  if !err_bytes_is(tlv_value(&data, &l, -1), "tlv: index out of range") { ok = false; }
  let cut = prefix(data, 8);
  if !value_is(&cut, &l, 0, bytes_of("abc")) { ok = false; }
  if !err_bytes_is(tlv_value(&cut, &l, 2), "tlv: value out of bounds") { ok = false; }
  return assert(ok, "value slices are exact; bad index and short buffer are Err");
}

fn t6() -> TestResult {
  var out = Vec[UInt8].new();
  let v = bytes_of("abc");
  var empty = Vec[UInt8].new();
  let ra = tlv_append(&mut out, 1, &v, 1, 1);
  let rb = tlv_append(&mut out, 254, &empty, 1, 1);
  var ok = ra.is_ok && rb.is_ok;
  if !bytes_equal(out, hb("0103616263fe00")) { ok = false; }
  return assert(ok, "tlv_append with 1/1 widths writes exact bytes");
}

fn t7() -> TestResult {
  var out = Vec[UInt8].new();
  let v = hb("deadbeef");
  var empty = Vec[UInt8].new();
  let ra = tlv_append(&mut out, 258, &v, 2, 2);
  let rb = tlv_append(&mut out, 0, &empty, 2, 2);
  let rc = tlv_append(&mut out, 65535, &empty, 2, 2);
  var ok = ra.is_ok && rb.is_ok && rc.is_ok;
  if !bytes_equal(out, hb("01020004deadbeef00000000ffff0000")) { ok = false; }
  return assert(ok, "tlv_append with 2/2 widths writes exact big-endian fields");
}

fn t8() -> TestResult {
  var out = Vec[UInt8].new();
  var empty = Vec[UInt8].new();
  var ok = err_unit_is(tlv_append(&mut out, 256, &empty, 1, 1), "tlv: tag too large for tag_size");
  if !err_unit_is(tlv_append(&mut out, -1, &empty, 1, 1), "tlv: negative tag") { ok = false; }
  let big = repeat_byte(7, 256);
  if !err_unit_is(tlv_append(&mut out, 1, &big, 1, 1), "tlv: value too large for length_size") { ok = false; }
  if !err_unit_is(tlv_append(&mut out, 1, &empty, 0, 1), "tlv: invalid tag size") { ok = false; }
  if !err_unit_is(tlv_append(&mut out, 1, &empty, -2, 1), "tlv: invalid tag size") { ok = false; }
  if !err_unit_is(tlv_append(&mut out, 1, &empty, 5, 1), "tlv: invalid tag size") { ok = false; }
  if !err_unit_is(tlv_append(&mut out, 1, &empty, 1, 0), "tlv: invalid length size") { ok = false; }
  if !err_unit_is(tlv_append(&mut out, 1, &empty, 1, 5), "tlv: invalid length size") { ok = false; }
  if out.len() != 0 { ok = false; }
  return assert(ok, "append width/tag/value errors are Err and leave the buffer empty");
}

fn t9() -> TestResult {
  var tags = Vec[Int].new();
  tags.push(1);
  tags.push(2);
  tags.push(300);
  var values = Vec[Vec[UInt8]].new();
  values.push(bytes_of("ab"));
  var empty = Vec[UInt8].new();
  values.push(empty);
  values.push(hb("00ff"));
  let r = tlv_build_from(&tags, &values, 2, 1);
  if !r.is_ok { return assert(false, "build_from must succeed"); }
  let built: Vec[UInt8] = r.value;
  var ok = bytes_equal(built, hb("0001026162000200012c0200ff"));
  var manual = Vec[UInt8].new();
  let v0: Vec[UInt8] = values[0];
  let v1: Vec[UInt8] = values[1];
  let v2: Vec[UInt8] = values[2];
  let a1 = tlv_append(&mut manual, 1, &v0, 2, 1);
  let a2 = tlv_append(&mut manual, 2, &v1, 2, 1);
  let a3 = tlv_append(&mut manual, 300, &v2, 2, 1);
  if !a1.is_ok || !a2.is_ok || !a3.is_ok { ok = false; }
  if !bytes_equal(manual, built) { ok = false; }
  let pr = tlv_parse(&built, 2, 1);
  if !pr.is_ok { ok = false; } else {
    let l: TlvList = pr.value;
    if tlv_count(&l) != 3 { ok = false; }
    if tlv_tag(&l, 0) != 1 { ok = false; }
    if tlv_tag(&l, 2) != 300 { ok = false; }
    if !value_is(&built, &l, 2, hb("00ff")) { ok = false; }
  }
  return assert(ok, "build_from equals per-entry appends and parses back");
}

fn t10() -> TestResult {
  var empty = Vec[UInt8].new();
  let r = tlv_parse(&empty, 1, 1);
  if !r.is_ok { return assert(false, "empty buffer must parse"); }
  let l: TlvList = r.value;
  var ok = tlv_count(&l) == 0;
  if tlv_tag(&l, 0) != -1 { ok = false; }
  if !err_bytes_is(tlv_value(&empty, &l, 0), "tlv: index out of range") { ok = false; }
  let one = hb("0100");
  let r1 = tlv_parse(&one, 1, 1);
  if !r1.is_ok { ok = false; } else {
    let l1: TlvList = r1.value;
    if tlv_count(&l1) != 1 { ok = false; }
    if tlv_tag(&l1, 0) != 1 { ok = false; }
    if !value_is(&one, &l1, 0, Vec[UInt8].new()) { ok = false; }
  }
  var no_tags = Vec[Int].new();
  var no_values = Vec[Vec[UInt8]].new();
  let br = tlv_build_from(&no_tags, &no_values, 1, 1);
  if !br.is_ok { ok = false; } else {
    let b: Vec[UInt8] = br.value;
    if b.len() != 0 { ok = false; }
  }
  return assert(ok, "empty buffer has zero entries; a lone header is one empty value");
}

fn t11() -> TestResult {
  let one = hb("01");
  var ok = err_list_is(tlv_parse(&one, 1, 1), "tlv: truncated header");
  let tail = hb("01016162");
  if !err_list_is(tlv_parse(&tail, 1, 1), "tlv: truncated header") { ok = false; }
  let two = hb("01020002cafe01");
  if !err_list_is(tlv_parse(&two, 2, 2), "tlv: truncated header") { ok = false; }
  let exact = hb("0100");
  if !tlv_parse(&exact, 1, 1).is_ok { ok = false; }
  return assert(ok, "a trailing partial header is Err; a complete lone header is not");
}

fn t12() -> TestResult {
  let a = hb("0105616262");
  var ok = err_list_is(tlv_parse(&a, 1, 1), "tlv: value overruns buffer");
  let b = hb("010561");
  if !err_list_is(tlv_parse(&b, 1, 1), "tlv: value overruns buffer") { ok = false; }
  let c = hb("010200cafe");
  if !err_list_is(tlv_parse(&c, 2, 2), "tlv: value overruns buffer") { ok = false; }
  let d = hb("010161020561");
  if !err_list_is(tlv_parse(&d, 1, 1), "tlv: value overruns buffer") { ok = false; }
  return assert(ok, "declared values that exceed the buffer are Err");
}

fn t13() -> TestResult {
  let data = hb("0101");
  var ok = err_list_is(tlv_parse(&data, 0, 1), "tlv: invalid tag size");
  if !err_list_is(tlv_parse(&data, 5, 1), "tlv: invalid tag size") { ok = false; }
  if !err_list_is(tlv_parse(&data, -1, 1), "tlv: invalid tag size") { ok = false; }
  if !err_list_is(tlv_parse(&data, 1, 0), "tlv: invalid length size") { ok = false; }
  if !err_list_is(tlv_parse(&data, 1, 5), "tlv: invalid length size") { ok = false; }
  var tags = Vec[Int].new();
  var values = Vec[Vec[UInt8]].new();
  if !err_bytes_is(tlv_build_from(&tags, &values, 5, 2), "tlv: invalid tag size") { ok = false; }
  if !err_bytes_is(tlv_build_from(&tags, &values, 2, 0), "tlv: invalid length size") { ok = false; }
  return assert(ok, "widths outside 1..4 are Err in parse and build_from");
}

fn t14() -> TestResult {
  let data = hb("010361626302007f02ff00");
  let r = tlv_parse(&data, 1, 1);
  if !r.is_ok { return assert(false, "stream must parse"); }
  let l: TlvList = r.value;
  var ok = tlv_count(&l) == 3;
  if tlv_tag(&l, -1) != -1 { ok = false; }
  if tlv_tag(&l, 3) != -1 { ok = false; }
  if tlv_tag(&l, 100) != -1 { ok = false; }
  if tlv_tag(&l, 0) != 1 { ok = false; }
  if tlv_tag(&l, 2) != 127 { ok = false; }
  if !err_bytes_is(tlv_value(&data, &l, 3), "tlv: index out of range") { ok = false; }
  return assert(ok, "count and accessors report -1 / Err out of range");
}

fn t15() -> TestResult {
  var tags = Vec[Int].new();
  tags.push(16777215);
  tags.push(1);
  tags.push(66051);
  var payload = Vec[UInt8].new();
  var i = 0;
  while i < 300 {
    payload.push((i % 256) as UInt8);
    i = i + 1;
  }
  var values = Vec[Vec[UInt8]].new();
  var empty = Vec[UInt8].new();
  values.push(empty);
  values.push(payload);
  values.push(bytes_of("z"));
  let r = tlv_build_from(&tags, &values, 3, 2);
  if !r.is_ok { return assert(false, "build_from must succeed"); }
  let built: Vec[UInt8] = r.value;
  var ok = built.len() == 316;
  if tlv_size(3, 2, 300) != 305 { ok = false; }
  let pr = tlv_parse(&built, 3, 2);
  if !pr.is_ok { ok = false; } else {
    let l: TlvList = pr.value;
    if tlv_count(&l) != 3 { ok = false; }
    if tlv_tag(&l, 0) != 16777215 { ok = false; }
    if tlv_tag(&l, 1) != 1 { ok = false; }
    if tlv_tag(&l, 2) != 66051 { ok = false; }
    if !value_is(&built, &l, 0, Vec[UInt8].new()) { ok = false; }
    let back: Vec[UInt8] = value_at(&built, &l, 1);
    if !bytes_equal(back, payload) { ok = false; }
    if back.len() != 300 { ok = false; }
    if !value_is(&built, &l, 2, bytes_of("z")) { ok = false; }
  }
  return assert(ok, "3/2 round-trip preserves tags and a 300-byte value");
}

fn t16() -> TestResult {
  var ok = tlv_size(1, 1, 3) == 5;
  if tlv_size(2, 4, 0) != 6 { ok = false; }
  if tlv_size(4, 4, 300) != 308 { ok = false; }
  if tlv_size(3, 2, 7) != 12 { ok = false; }
  if tlv_size(0, 1, 3) != -1 { ok = false; }
  if tlv_size(5, 1, 3) != -1 { ok = false; }
  if tlv_size(1, 0, 3) != -1 { ok = false; }
  if tlv_size(1, 5, 3) != -1 { ok = false; }
  if tlv_size(1, 1, -1) != -1 { ok = false; }
  var tags = Vec[Int].new();
  tags.push(9);
  var values = Vec[Vec[UInt8]].new();
  values.push(bytes_of("xyz"));
  let r = tlv_build_from(&tags, &values, 2, 3);
  if !r.is_ok { return assert(false, "build must succeed"); }
  let built: Vec[UInt8] = r.value;
  if built.len() != tlv_size(2, 3, 3) { ok = false; }
  return assert(ok, "tlv_size is header + value length and -1 for invalid inputs");
}

fn t17() -> TestResult {
  let data = hb("0500026162060000ff000180");
  let r = tlv_parse(&data, 1, 2);
  if !r.is_ok { return assert(false, "mixed stream must parse"); }
  let l: TlvList = r.value;
  var tags = Vec[Int].new();
  var values = Vec[Vec[UInt8]].new();
  var i = 0;
  while i < tlv_count(&l) {
    tags.push(tlv_tag(&l, i));
    let v: Vec[UInt8] = value_at(&data, &l, i);
    values.push(v);
    i = i + 1;
  }
  let br = tlv_build_from(&tags, &values, 1, 2);
  if !br.is_ok { return assert(false, "rebuild must succeed"); }
  let rebuilt: Vec[UInt8] = br.value;
  var ok = bytes_equal(rebuilt, data);
  if tlv_count(&l) != 3 { ok = false; }
  if rebuilt.len() != 12 { ok = false; }
  return assert(ok, "parse -> rebuild reproduces the original bytes exactly");
}

fn t18() -> TestResult {
  var tags = Vec[Int].new();
  tags.push(4294967295);
  tags.push(2147483648);
  var values = Vec[Vec[UInt8]].new();
  values.push(hb("ff"));
  values.push(hb("0080"));
  let r = tlv_build_from(&tags, &values, 4, 4);
  if !r.is_ok { return assert(false, "4/4 build must succeed"); }
  let built: Vec[UInt8] = r.value;
  var ok = built.len() == 19;
  if !bytes_equal(built, hb("ffffffff00000001ff80000000000000020080")) { ok = false; }
  let pr = tlv_parse(&built, 4, 4);
  if !pr.is_ok { ok = false; } else {
    let l: TlvList = pr.value;
    if tlv_count(&l) != 2 { ok = false; }
    if tlv_tag(&l, 0) != 4294967295 { ok = false; }
    if tlv_tag(&l, 1) != 2147483648 { ok = false; }
    if !value_is(&built, &l, 0, hb("ff")) { ok = false; }
    if !value_is(&built, &l, 1, hb("0080")) { ok = false; }
  }
  let one = hb("ff00");
  let pr1 = tlv_parse(&one, 1, 1);
  if !pr1.is_ok { ok = false; } else {
    let l1: TlvList = pr1.value;
    if tlv_tag(&l1, 0) != 255 { ok = false; }
  }
  let two = hb("fffe0000");
  let pr2 = tlv_parse(&two, 2, 2);
  if !pr2.is_ok { ok = false; } else {
    let l2: TlvList = pr2.value;
    if tlv_tag(&l2, 0) != 65534 { ok = false; }
  }
  return assert(ok, "4/4 high-bit tags/values round-trip; tags read unsigned");
}

fn main() -> Int {
  io.println("=== xiom.tlv conformance tests ===");
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
    io.println("xiom.tlv: all tests passed");
  } else {
    io.println("xiom.tlv: tests failed");
  }
  return failed;
}
