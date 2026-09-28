// XIOM -- xiom.perf conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Synthetic perf.data buffers are assembled here byte by byte (independent
// of src/perf.xi) so the parser is exercised against bytes the test
// controls: fixed headers with every validation branch, attrs records with
// full and short perf_event_attr images, MMAP/MMAP2/COMM/FORK/EXIT/LOST/
// READ/THROTTLE/SWITCH/AUX/NAMESPACES/KSYMBOL/BPF/ID_INDEX/BUILD_ID record
// payloads, SAMPLE reconstructions from several sample_types (including
// IDENTIFIER-first and CALLCHAIN-skipping layouts), sample_id tails,
// feature sections (build_id, hostname/osrelease/version strings, cmdline
// list, cpu_topology) and the documented malformed-input errors.
//
// Str equality goes through str_compare (BUG 17 discipline: `==` on a Str
// read from a Vec lowers to a pointer comparison).

module perf_tests
use xiom.io; use xiom.test;
use xiom.perf;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Generic test helpers
// --------------------------------------------------

// Expected bytes for a hex string ("" on malformed input).
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

fn err_file_is(r: Result[PerfFile, Str], want: Str) -> Bool {
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

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
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

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// True when `r` is Ok and its value equals `want`.
fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn bool_is(r: Result[Bool, Str], want: Bool) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Bool = r.value;
  return v == want;
}

// True when `r` is Ok and its Str value equals `want`.
fn str_is(r: Result[Str, Str], want: Str) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Str = r.value;
  return str_eq(v, want);
}

// True when `r` is Ok and its byte value equals `want`.
fn bytes_is(r: Result[Vec[UInt8], Str], want: Vec[UInt8]) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Vec[UInt8] = r.value;
  return bytes_equal(v, want);
}

// --------------------------------------------------
//  Byte builders (independent of src/perf.xi)
// --------------------------------------------------

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
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

// Byte `k` (0 = least significant) of `val`'s two's-complement pattern.
fn low_byte(val: Int, k: Int) -> Int {
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
  return b;
}

// Append `src` to `v`.
fn append(v: &mut Vec[UInt8], src: Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    v.push(src[i]);
    i = i + 1;
  }
}

// Little-endian `size` (1..8) byte encoding of `val`.
fn le_bytes(val: Int, size: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < size {
    v.push(low_byte(val, i) as UInt8);
    i = i + 1;
  }
  return v;
}

// Concatenation of two byte vectors.
fn cat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  append(&mut v, a);
  append(&mut v, b);
  return v;
}

fn put_u8(v: &mut Vec[UInt8], off: Int, val: Int) {
  v[off] = (val % 256) as UInt8;
}

// Patch `size` (1..8) bytes at `off` with `val`, little-endian.
fn put_uint(v: &mut Vec[UInt8], off: Int, val: Int, size: Int) {
  var i = 0;
  while i < size {
    v[off + i] = low_byte(val, i) as UInt8;
    i = i + 1;
  }
}

// Write the LE PERFILE2 magic at offset 0.
fn put_magic(v: &mut Vec[UInt8]) {
  put_uint(v, 0, PERF_MAGIC0, 1);
  put_uint(v, 1, PERF_MAGIC1, 1);
  put_uint(v, 2, PERF_MAGIC2, 1);
  put_uint(v, 3, PERF_MAGIC3, 1);
  put_uint(v, 4, PERF_MAGIC4, 1);
  put_uint(v, 5, PERF_MAGIC5, 1);
  put_uint(v, 6, PERF_MAGIC6, 1);
  put_uint(v, 7, PERF_MAGIC7, 1);
}

// Write the byte-swapped (big-endian) magic at offset 0.
fn put_magic_be(v: &mut Vec[UInt8]) {
  put_uint(v, 0, PERF_MAGIC_BE0, 1);
  put_uint(v, 1, PERF_MAGIC_BE1, 1);
  put_uint(v, 2, PERF_MAGIC_BE2, 1);
  put_uint(v, 3, PERF_MAGIC_BE3, 1);
  put_uint(v, 4, PERF_MAGIC_BE4, 1);
  put_uint(v, 5, PERF_MAGIC_BE5, 1);
  put_uint(v, 6, PERF_MAGIC_BE6, 1);
  put_uint(v, 7, PERF_MAGIC_BE7, 1);
}

// Full fixed header for a buffer that already has room for it.
fn put_header(v: &mut Vec[UInt8], attr_size: Int, attrs_off: Int, attrs_sz: Int, data_off: Int, data_sz: Int, et_off: Int, et_sz: Int) {
  put_magic(v);
  put_uint(v, 8, 104, 8);
  put_uint(v, 16, attr_size, 8);
  put_uint(v, 24, attrs_off, 8);
  put_uint(v, 32, attrs_sz, 8);
  put_uint(v, 40, data_off, 8);
  put_uint(v, 48, data_sz, 8);
  put_uint(v, 56, et_off, 8);
  put_uint(v, 64, et_sz, 8);
}

// A fresh 104-byte empty file (header only, no attrs/data/features).
fn base104() -> Vec[UInt8] {
  var v = zeros(104);
  put_header(&mut v, 152, 104, 0, 104, 0, 104, 0);
  return v;
}

// One perf_event_attr at `off` with the given sample_type, read_format and
// flag word; size 136 (VER8), sample period 1000, every other field 0.
fn put_attr(v: &mut Vec[UInt8], off: Int, stype: Int, rfmt: Int, flags: Int) {
  put_uint(v, off, 0, 4);
  put_uint(v, off + 4, 136, 4);
  put_uint(v, off + 16, 1000, 8);
  put_uint(v, off + 24, stype, 8);
  put_uint(v, off + 32, rfmt, 8);
  put_uint(v, off + 40, flags, 8);
}

// A record header + payload.
fn rec_of(rtype: Int, misc: Int, payload: Vec[UInt8]) -> Vec[UInt8] {
  var v = le_bytes(rtype, 4);
  append(&mut v, le_bytes(misc, 2));
  append(&mut v, le_bytes(payload.len() + 8, 2));
  append(&mut v, payload);
  return v;
}

// One perf_header_string: u32 len (including any NUL) + the bytes.
fn str_rec(hexstr: Str) -> Vec[UInt8] {
  let b = hb(hexstr);
  var v = le_bytes(b.len(), 4);
  append(&mut v, b);
  return v;
}

// One perf_header_string_list: u32 nr + nr perf_header_string records.
fn str_list1(hex1: Str) -> Vec[UInt8] {
  var v = le_bytes(1, 4);
  append(&mut v, str_rec(hex1));
  return v;
}

fn str_list2(hex1: Str, hex2: Str) -> Vec[UInt8] {
  var v = le_bytes(2, 4);
  append(&mut v, str_rec(hex1));
  append(&mut v, str_rec(hex2));
  return v;
}

// The standard one-attr file: header, one 152-byte attr record (attr at
// 104, ids descriptor at 240 pointing at two u64 ids placed just past the
// data section), then `data`.
fn f_1attr(data: Vec[UInt8], stype: Int, rfmt: Int, flags: Int) -> Vec[UInt8] {
  let attrs_sz = 152;
  let data_off = 104 + attrs_sz;
  let n_data = data.len();
  var v = zeros(data_off);
  put_header(&mut v, attrs_sz, 104, attrs_sz, data_off, n_data, data_off, 0);
  put_attr(&mut v, 104, stype, rfmt, flags);
  append(&mut v, data);
  append(&mut v, le_bytes(0x1001, 8));
  append(&mut v, le_bytes(0x1002, 8));
  put_uint(&mut v, 240, data_off + n_data, 8);
  put_uint(&mut v, 248, 16, 8);
  return v;
}

// Attribute offset of attr `i` in the f_1attr layout (stride 152).
fn aoff(i: Int) -> Int {
  return 104 + i * 152;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var v = zeros(104);
  put_header(&mut v, 152, 104, 0, 104, 0, 104, 0);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "minimal file must parse"); }
  let f: PerfFile = r.value;
  var ok = perf_header_size(&f) == 104;
  if perf_attr_size(&f) != 152 { ok = false; }
  if !int_is(perf_section_field(&f, PERF_SECTION_ATTRS_OFFSET), 104) { ok = false; }
  if !int_is(perf_section_field(&f, PERF_SECTION_ATTRS_SIZE), 0) { ok = false; }
  if !int_is(perf_section_field(&f, PERF_SECTION_DATA_OFFSET), 104) { ok = false; }
  if !int_is(perf_section_field(&f, PERF_SECTION_DATA_SIZE), 0) { ok = false; }
  if !int_is(perf_section_field(&f, PERF_SECTION_EVENT_TYPES_OFFSET), 104) { ok = false; }
  if !int_is(perf_section_field(&f, PERF_SECTION_EVENT_TYPES_SIZE), 0) { ok = false; }
  if !err_int_is(perf_section_field(&f, PERF_SECTION_FIELD_COUNT), "perf: bad field selector") { ok = false; }
  if perf_attr_count(&f) != 0 { ok = false; }
  if perf_record_count(&f) != 0 { ok = false; }
  if perf_feature_count(&f) != 0 { ok = false; }
  if perf_feature_present(&f, PERF_FEATURE_HOSTNAME) { ok = false; }
  if perf_variant(&v) != PERF_VARIANT_LE { ok = false; }
  return assert(ok, "minimal 104-byte file: header fields, empty tables, LE variant");
}

fn t2() -> TestResult {
  var v1 = base104();
  put_u8(&mut v1, 3, 0);
  var ok = err_file_is(perf_parse(&v1), "perf: bad magic");
  if perf_variant(&v1) != PERF_VARIANT_UNKNOWN { ok = false; }
  var v2 = zeros(104);
  put_magic_be(&mut v2);
  put_uint(&mut v2, 8, 104, 8);
  put_uint(&mut v2, 16, 152, 8);
  if !err_file_is(perf_parse(&v2), "perf: big-endian perf.data not supported") { ok = false; }
  if perf_variant(&v2) != PERF_VARIANT_BE { ok = false; }
  var v3 = zeros(4);
  if !err_file_is(perf_parse(&v3), "perf: truncated magic") { ok = false; }
  if perf_variant(&v3) != PERF_VARIANT_UNKNOWN { ok = false; }
  var v4 = zeros(50);
  put_magic(&mut v4);
  if !err_file_is(perf_parse(&v4), "perf: truncated header") { ok = false; }
  let p4 = prefix(base104(), 103);
  if !err_file_is(perf_parse(&p4), "perf: truncated header") { ok = false; }
  return assert(ok, "bad magic, BE magic (recognized), truncated magic/header");
}

fn t3() -> TestResult {
  var v1 = zeros(104);
  put_header(&mut v1, 152, 104, 0, 104, 0, 104, 0);
  put_uint(&mut v1, 8, 100, 8);
  var ok = err_file_is(perf_parse(&v1), "perf: bad header size at 8");
  var v2 = zeros(104);
  put_header(&mut v2, 56, 104, 0, 104, 0, 104, 0);
  if !err_file_is(perf_parse(&v2), "perf: bad attr size at 16") { ok = false; }
  var v3 = zeros(104);
  put_header(&mut v3, 100, 104, 0, 104, 0, 104, 0);
  if !err_file_is(perf_parse(&v3), "perf: bad attr size at 16") { ok = false; }
  var v4 = zeros(200);
  put_header(&mut v4, 152, 150, 80, 104, 0, 104, 0);
  if !err_file_is(perf_parse(&v4), "perf: attrs section out of bounds") { ok = false; }
  var v5 = zeros(104);
  put_header(&mut v5, 152, 104, 0, 0, 200, 104, 0);
  if !err_file_is(perf_parse(&v5), "perf: data section out of bounds") { ok = false; }
  var v6 = zeros(104);
  put_header(&mut v6, 152, 104, 0, 104, 0, 20, 200);
  if !err_file_is(perf_parse(&v6), "perf: event_types section out of bounds") { ok = false; }
  var v7 = zeros(264);
  put_header(&mut v7, 152, 104, 160, 264, 0, 264, 0);
  if !err_file_is(perf_parse(&v7), "perf: attrs section size not a multiple of attr_size") { ok = false; }
  return assert(ok, "header sizes, section spans and attrs length alignment");
}

fn t4() -> TestResult {
  let st = PERF_SAMPLE_IP + PERF_SAMPLE_TID + PERF_SAMPLE_TIME + PERF_SAMPLE_ADDR + PERF_SAMPLE_ID + PERF_SAMPLE_STREAM_ID + PERF_SAMPLE_CPU + PERF_SAMPLE_PERIOD + PERF_SAMPLE_READ + PERF_SAMPLE_CALLCHAIN;
  let rf = PERF_FORMAT_TOTAL_TIME_ENABLED + PERF_FORMAT_TOTAL_TIME_RUNNING + PERF_FORMAT_ID;
  let fl = 126092289;
  var v = f_1attr(Vec[UInt8].new(), st, rf, fl);
  put_uint(&mut v, aoff(0) + 8, 0x1122334455667788, 8);
  put_uint(&mut v, aoff(0) + 48, 8, 4);
  put_uint(&mut v, aoff(0) + 52, 4, 4);
  put_uint(&mut v, aoff(0) + 56, 0x0102, 8);
  put_uint(&mut v, aoff(0) + 64, 0x0304, 8);
  put_uint(&mut v, aoff(0) + 72, 0x1F, 8);
  put_uint(&mut v, aoff(0) + 80, 0xFFFF, 8);
  put_uint(&mut v, aoff(0) + 88, 512, 4);
  put_uint(&mut v, aoff(0) + 92, 4, 4);
  put_uint(&mut v, aoff(0) + 96, 0xABCD, 8);
  put_uint(&mut v, aoff(0) + 104, 4096, 4);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "attr fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = perf_attr_count(&f) == 1;
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_TYPE), 0) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_SIZE), 136) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_CONFIG), 0x1122334455667788) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_SAMPLE_PERIOD), 1000) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_SAMPLE_TYPE), 1023) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_READ_FORMAT), 7) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_FLAGS), fl) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_WAKEUP_EVENTS), 8) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_BP_TYPE), 4) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_CONFIG1), 0x0102) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_CONFIG2), 0x0304) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_BRANCH_SAMPLE_TYPE), 0x1F) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_SAMPLE_REGS_USER), 0xFFFF) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_SAMPLE_STACK_USER), 512) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_CLOCKID), 4) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_SAMPLE_REGS_INTR), 0xABCD) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_AUX_WATERMARK), 4096) { ok = false; }
  if !bool_is(perf_attr_flag(&f, 0, PERF_ATTR_FLAG_DISABLED), true) { ok = false; }
  if !bool_is(perf_attr_flag(&f, 0, PERF_ATTR_FLAG_INHERIT), false) { ok = false; }
  if !bool_is(perf_attr_flag(&f, 0, PERF_ATTR_FLAG_FREQ), true) { ok = false; }
  if !bool_is(perf_attr_flag(&f, 0, PERF_ATTR_FLAG_TASK), false) { ok = false; }
  if !bool_is(perf_attr_flag(&f, 0, PERF_ATTR_FLAG_PRECISE_IP), false) { ok = false; }
  if !bool_is(perf_attr_flag(&f, 0, PERF_ATTR_FLAG_SAMPLE_ID_ALL), true) { ok = false; }
  if !bool_is(perf_attr_flag(&f, 0, PERF_ATTR_FLAG_MMAP2), true) { ok = false; }
  if !bool_is(perf_attr_flag(&f, 0, PERF_ATTR_FLAG_COMM_EXEC), true) { ok = false; }
  if !bool_is(perf_attr_flag(&f, 0, PERF_ATTR_FLAG_USE_CLOCKID), true) { ok = false; }
  if !bool_is(perf_attr_flag(&f, 0, PERF_ATTR_FLAG_CONTEXT_SWITCH), true) { ok = false; }
  if !bool_is(perf_attr_flag(&f, 0, PERF_ATTR_FLAG_SIGTRAP), false) { ok = false; }
  if !int_is(perf_attr_ids_count(&f, 0), 2) { ok = false; }
  if !int_is(perf_attr_ids_section_field(&f, 0, PERF_FEATURE_FIELD_OFFSET), 256) { ok = false; }
  if !int_is(perf_attr_ids_section_field(&f, 0, PERF_FEATURE_FIELD_SIZE), 16) { ok = false; }
  if !int_is(perf_attr_id(&v, &f, 0, 0), 0x1001) { ok = false; }
  if !int_is(perf_attr_id(&v, &f, 0, 1), 0x1002) { ok = false; }
  if !err_int_is(perf_attr_field(&f, 1, PERF_ATTR_FIELD_TYPE), "perf: index out of range") { ok = false; }
  if !err_int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_COUNT), "perf: bad field selector") { ok = false; }
  if !err_bool_is(perf_attr_flag(&f, 0, 64), "perf: bad attr flag bit") { ok = false; }
  if !err_int_is(perf_attr_id(&v, &f, 0, 2), "perf: index out of range") { ok = false; }
  return assert(ok, "attr: every field, flag bits, ids array, selector errors");
}

fn t5() -> TestResult {
  var v = zeros(184);
  put_header(&mut v, 80, 104, 80, 184, 0, 184, 0);
  put_uint(&mut v, 104, 4, 4);
  put_uint(&mut v, 108, 64, 4);
  put_uint(&mut v, 112, 0x99, 8);
  put_uint(&mut v, 120, 77, 8);
  put_uint(&mut v, 128, 2, 8);
  put_uint(&mut v, 136, 4, 8);
  put_uint(&mut v, 144, 1, 8);
  put_uint(&mut v, 152, 9, 4);
  put_uint(&mut v, 156, 3, 4);
  put_uint(&mut v, 160, 5, 8);
  put_uint(&mut v, 168, 184, 8);
  put_uint(&mut v, 176, 0, 8);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "short-attr fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = perf_attr_count(&f) == 1;
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_TYPE), 4) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_SIZE), 64) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_CONFIG), 0x99) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_SAMPLE_PERIOD), 77) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_SAMPLE_TYPE), 2) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_READ_FORMAT), 4) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_FLAGS), 1) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_WAKEUP_EVENTS), 9) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_BP_TYPE), 3) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_CONFIG1), 5) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_CONFIG2), 0) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_BRANCH_SAMPLE_TYPE), 0) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_SAMPLE_REGS_USER), 0) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_SAMPLE_STACK_USER), 0) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_CLOCKID), 0) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_SAMPLE_REGS_INTR), 0) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_AUX_WATERMARK), 0) { ok = false; }
  if !int_is(perf_attr_ids_count(&f, 0), 0) { ok = false; }
  var v1 = zeros(184);
  put_header(&mut v1, 80, 104, 80, 184, 0, 184, 0);
  put_uint(&mut v1, 108, 63, 4);
  if !err_file_is(perf_parse(&v1), "perf: bad attr record size at 104") { ok = false; }
  var v2 = zeros(256);
  put_header(&mut v2, 152, 104, 152, 256, 0, 256, 0);
  put_uint(&mut v2, 108, 140, 4);
  if !err_file_is(perf_parse(&v2), "perf: bad attr record size at 104") { ok = false; }
  var v3 = zeros(184);
  put_header(&mut v3, 80, 104, 80, 184, 0, 184, 0);
  put_uint(&mut v3, 104, 4, 4);
  put_uint(&mut v3, 108, 64, 4);
  put_uint(&mut v3, 168, 999, 8);
  if !err_file_is(perf_parse(&v3), "perf: ids section out of bounds at 168") { ok = false; }
  return assert(ok, "attr size 64: present fields read, later fields are 0, size/ids errors");
}

fn t6() -> TestResult {
  var mmap_p = cat(cat(le_bytes(1234, 4), le_bytes(1235, 4)), cat(cat(le_bytes(0x7fff0000, 8), le_bytes(0x1000, 8)), cat(le_bytes(0, 8), hb("6c696278"))));
  var comm_p = cat(cat(le_bytes(7, 4), le_bytes(8, 4)), hb("68656c6c6f"));
  var fork_p = cat(cat(le_bytes(10, 4), le_bytes(9, 4)), cat(cat(le_bytes(10, 4), le_bytes(9, 4)), le_bytes(555, 8)));
  var sample_p = cat(cat(cat(le_bytes(0x401000, 8), le_bytes(100, 4)), cat(le_bytes(101, 4), le_bytes(222, 8))), cat(cat(le_bytes(0xdead, 8), le_bytes(3, 8)), cat(cat(le_bytes(4, 8), le_bytes(5, 8)), cat(cat(le_bytes(6, 4), le_bytes(0, 4)), cat(le_bytes(1000, 8), le_bytes(42, 8))))));
  var idx_p = cat(le_bytes(2, 8), cat(cat(le_bytes(0x1001, 8), cat(le_bytes(0, 8), cat(le_bytes(0, 8), le_bytes(1, 8)))), cat(le_bytes(0x1002, 8), cat(le_bytes(1, 8), cat(le_bytes(0, 8), le_bytes(2, 8))))));
  var bid_p = cat(le_bytes(77, 4), cat(hb("00112233445566778899aabbccddeeff00112233"), hb("6c696278")));
  var d = Vec[UInt8].new();
  append(&mut d, rec_of(PERF_RECORD_MMAP, PERF_RECORD_MISC_USER, mmap_p));
  append(&mut d, rec_of(PERF_RECORD_COMM, PERF_RECORD_MISC_USER, comm_p));
  append(&mut d, rec_of(PERF_RECORD_FORK, PERF_RECORD_MISC_USER, fork_p));
  append(&mut d, rec_of(PERF_RECORD_SAMPLE, PERF_RECORD_MISC_USER, sample_p));
  append(&mut d, rec_of(PERF_RECORD_ID_INDEX, 0, idx_p));
  append(&mut d, rec_of(PERF_RECORD_HEADER_BUILD_ID, 0, bid_p));
  append(&mut d, rec_of(PERF_RECORD_FINISHED_ROUND, 0, Vec[UInt8].new()));
  var v = f_1attr(d, 511, 0, 0);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "record stream must parse"); }
  let f: PerfFile = r.value;
  var ok = perf_record_count(&f) == 7;
  if !int_is(perf_record_field(&f, 0, PERF_REC_FIELD_TYPE), PERF_RECORD_MMAP) { ok = false; }
  if !int_is(perf_record_field(&f, 0, PERF_REC_FIELD_MISC), PERF_RECORD_MISC_USER) { ok = false; }
  if !int_is(perf_record_field(&f, 0, PERF_REC_FIELD_OFFSET), 256) { ok = false; }
  if !int_is(perf_record_field(&f, 0, PERF_REC_FIELD_SIZE), 8 + mmap_p.len()) { ok = false; }
  if !int_is(perf_record_field(&f, 0, PERF_REC_FIELD_PAYLOAD_OFFSET), 264) { ok = false; }
  if !int_is(perf_record_field(&f, 0, PERF_REC_FIELD_PAYLOAD_SIZE), mmap_p.len()) { ok = false; }
  if !int_is(perf_record_field(&f, 1, PERF_REC_FIELD_OFFSET), 256 + 8 + mmap_p.len()) { ok = false; }
  if !int_is(perf_record_field(&f, 6, PERF_REC_FIELD_TYPE), PERF_RECORD_FINISHED_ROUND) { ok = false; }
  if !int_is(perf_record_field(&f, 6, PERF_REC_FIELD_SIZE), 8) { ok = false; }
  if !int_is(perf_record_field(&f, 6, PERF_REC_FIELD_PAYLOAD_SIZE), 0) { ok = false; }
  if !err_int_is(perf_record_field(&f, 7, PERF_REC_FIELD_TYPE), "perf: index out of range") { ok = false; }
  if !err_int_is(perf_record_field(&f, 0, PERF_REC_FIELD_COUNT), "perf: bad field selector") { ok = false; }
  if !str_eq(perf_record_type_name(PERF_RECORD_SAMPLE), "SAMPLE") { ok = false; }
  if !str_eq(perf_record_type_name(PERF_RECORD_ID_INDEX), "ID_INDEX") { ok = false; }
  if !str_eq(perf_record_type_name(PERF_RECORD_COMPRESSED2), "COMPRESSED2") { ok = false; }
  if !str_eq(perf_record_type_name(99), "UNKNOWN") { ok = false; }
  if !bool_is(perf_record_misc_is(&v, &f, 0, PERF_RECORD_MISC_USER), true) { ok = false; }
  if !bool_is(perf_record_misc_is(&v, &f, 0, PERF_RECORD_MISC_KERNEL), false) { ok = false; }
  return assert(ok, "record walk: 7 records with offsets/sizes, type names, misc");
}

fn t7() -> TestResult {
  var mmap_p = cat(cat(le_bytes(100, 4), le_bytes(101, 4)), cat(cat(le_bytes(0x400000, 8), le_bytes(0x200, 8)), cat(le_bytes(5, 8), hb("6c696278"))));
  var mmap2_p = cat(cat(le_bytes(200, 4), le_bytes(201, 4)), cat(cat(le_bytes(0x500000, 8), le_bytes(0x300, 8)), cat(cat(le_bytes(7, 8), le_bytes(1, 4)), cat(cat(le_bytes(2, 4), le_bytes(0x1234, 8)), cat(cat(le_bytes(9, 8), le_bytes(5, 4)), cat(le_bytes(6, 4), hb("616f7574")))))));
  var d = Vec[UInt8].new();
  append(&mut d, rec_of(PERF_RECORD_MMAP, PERF_RECORD_MISC_USER, mmap_p));
  append(&mut d, rec_of(PERF_RECORD_MMAP2, PERF_RECORD_MISC_KERNEL, mmap2_p));
  var v = f_1attr(d, 0, 0, 0);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "mmap fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = int_is(perf_mmap_field(&v, &f, 0, PERF_MMAP_FIELD_PID), 100);
  if !int_is(perf_mmap_field(&v, &f, 0, PERF_MMAP_FIELD_TID), 101) { ok = false; }
  if !int_is(perf_mmap_field(&v, &f, 0, PERF_MMAP_FIELD_ADDR), 0x400000) { ok = false; }
  if !int_is(perf_mmap_field(&v, &f, 0, PERF_MMAP_FIELD_LEN), 0x200) { ok = false; }
  if !int_is(perf_mmap_field(&v, &f, 0, PERF_MMAP_FIELD_PGOFF), 5) { ok = false; }
  if !int_is(perf_mmap_field(&v, &f, 0, PERF_MMAP_FIELD_FILENAME_SIZE), 4) { ok = false; }
  if !str_is(perf_span_str(&v, 264 + 32, 4), "libx") { ok = false; }
  if !int_is(perf_mmap2_field(&v, &f, 1, PERF_MMAP2_FIELD_PID), 200) { ok = false; }
  if !int_is(perf_mmap2_field(&v, &f, 1, PERF_MMAP2_FIELD_TID), 201) { ok = false; }
  if !int_is(perf_mmap2_field(&v, &f, 1, PERF_MMAP2_FIELD_ADDR), 0x500000) { ok = false; }
  if !int_is(perf_mmap2_field(&v, &f, 1, PERF_MMAP2_FIELD_LEN), 0x300) { ok = false; }
  if !int_is(perf_mmap2_field(&v, &f, 1, PERF_MMAP2_FIELD_PGOFF), 7) { ok = false; }
  if !int_is(perf_mmap2_field(&v, &f, 1, PERF_MMAP2_FIELD_MAJ), 1) { ok = false; }
  if !int_is(perf_mmap2_field(&v, &f, 1, PERF_MMAP2_FIELD_MIN), 2) { ok = false; }
  if !int_is(perf_mmap2_field(&v, &f, 1, PERF_MMAP2_FIELD_INO), 0x1234) { ok = false; }
  if !int_is(perf_mmap2_field(&v, &f, 1, PERF_MMAP2_FIELD_INO_GENERATION), 9) { ok = false; }
  if !int_is(perf_mmap2_field(&v, &f, 1, PERF_MMAP2_FIELD_PROT), 5) { ok = false; }
  if !int_is(perf_mmap2_field(&v, &f, 1, PERF_MMAP2_FIELD_FLAGS), 6) { ok = false; }
  if !int_is(perf_mmap2_field(&v, &f, 1, PERF_MMAP2_FIELD_FILENAME_SIZE), 4) { ok = false; }
  if !err_int_is(perf_mmap_field(&v, &f, 1, PERF_MMAP_FIELD_PID), "perf: record type mismatch") { ok = false; }
  if !err_int_is(perf_mmap_field(&v, &f, 0, PERF_MMAP_FIELD_COUNT), "perf: bad field selector") { ok = false; }
  return assert(ok, "MMAP and MMAP2 payloads decode field by field");
}

fn t8() -> TestResult {
  var comm_p = cat(cat(le_bytes(5, 4), le_bytes(6, 4)), hb("68656c6c6f"));
  var d = Vec[UInt8].new();
  append(&mut d, rec_of(PERF_RECORD_COMM, PERF_RECORD_MISC_USER + PERF_RECORD_MISC_COMM_EXEC, comm_p));
  var v = f_1attr(d, 0, 0, 0);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "comm fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = int_is(perf_comm_field(&v, &f, 0, PERF_COMM_FIELD_PID), 5);
  if !int_is(perf_comm_field(&v, &f, 0, PERF_COMM_FIELD_TID), 6) { ok = false; }
  if !int_is(perf_comm_field(&v, &f, 0, PERF_COMM_FIELD_COMM_SIZE), 5) { ok = false; }
  if !int_is(perf_comm_field(&v, &f, 0, PERF_COMM_FIELD_COMM_OFFSET), 264 + 8) { ok = false; }
  if !str_is(perf_span_str(&v, 272, 5), "hello") { ok = false; }
  if !bool_is(perf_record_misc_is(&v, &f, 0, PERF_RECORD_MISC_USER), true) { ok = false; }
  return assert(ok, "COMM pid/tid/text span decode");
}

fn t9() -> TestResult {
  var fork_p = cat(cat(le_bytes(20, 4), le_bytes(19, 4)), cat(cat(le_bytes(20, 4), le_bytes(19, 4)), le_bytes(777, 8)));
  var exit_p = cat(cat(le_bytes(20, 4), le_bytes(1, 4)), cat(cat(le_bytes(20, 4), le_bytes(1, 4)), le_bytes(888, 8)));
  var d = Vec[UInt8].new();
  append(&mut d, rec_of(PERF_RECORD_FORK, PERF_RECORD_MISC_USER, fork_p));
  append(&mut d, rec_of(PERF_RECORD_EXIT, PERF_RECORD_MISC_USER, exit_p));
  var v = f_1attr(d, 0, 0, 0);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "fork fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = int_is(perf_fork_field(&v, &f, 0, PERF_TASK_FIELD_PID), 20);
  if !int_is(perf_fork_field(&v, &f, 0, PERF_TASK_FIELD_PPID), 19) { ok = false; }
  if !int_is(perf_fork_field(&v, &f, 0, PERF_TASK_FIELD_TID), 20) { ok = false; }
  if !int_is(perf_fork_field(&v, &f, 0, PERF_TASK_FIELD_PTID), 19) { ok = false; }
  if !int_is(perf_fork_field(&v, &f, 0, PERF_TASK_FIELD_TIME), 777) { ok = false; }
  if !int_is(perf_exit_field(&v, &f, 1, PERF_TASK_FIELD_PPID), 1) { ok = false; }
  if !int_is(perf_exit_field(&v, &f, 1, PERF_TASK_FIELD_TIME), 888) { ok = false; }
  if !err_int_is(perf_fork_field(&v, &f, 1, PERF_TASK_FIELD_PID), "perf: record type mismatch") { ok = false; }
  if !err_int_is(perf_exit_field(&v, &f, 0, PERF_TASK_FIELD_COUNT), "perf: bad field selector") { ok = false; }
  return assert(ok, "FORK and EXIT pid/ppid/tid/ptid/time decode");
}

fn t10() -> TestResult {
  var lost_p = cat(le_bytes(0xAA, 8), le_bytes(3, 8));
  var read_p = cat(cat(le_bytes(1, 4), le_bytes(2, 4)), cat(le_bytes(42, 8), cat(le_bytes(100, 8), cat(le_bytes(90, 8), le_bytes(0x55, 8)))));
  var thr_p = cat(le_bytes(1, 8), cat(le_bytes(2, 8), le_bytes(3, 8)));
  var sw_p = cat(le_bytes(11, 4), le_bytes(12, 4));
  var aux_p = cat(le_bytes(0x1000, 8), cat(le_bytes(0x2000, 8), le_bytes(3, 8)));
  var itr_p = cat(le_bytes(1, 4), le_bytes(2, 4));
  var ns_p = cat(cat(le_bytes(1, 4), le_bytes(2, 4)), cat(le_bytes(2, 8), cat(cat(le_bytes(10, 8), le_bytes(11, 8)), cat(le_bytes(12, 8), le_bytes(13, 8)))));
  var ks_p = cat(le_bytes(0x1000, 8), cat(le_bytes(16, 4), cat(le_bytes(2, 2), cat(le_bytes(1, 2), hb("6b66756e63")))));
  var bpf_p = cat(le_bytes(1, 2), cat(le_bytes(0, 1), cat(le_bytes(0, 1), le_bytes(77, 4))));
  var d = Vec[UInt8].new();
  append(&mut d, rec_of(PERF_RECORD_LOST, 0, lost_p));
  append(&mut d, rec_of(PERF_RECORD_READ, 0, read_p));
  append(&mut d, rec_of(PERF_RECORD_THROTTLE, 0, thr_p));
  append(&mut d, rec_of(PERF_RECORD_UNTHROTTLE, 0, thr_p));
  append(&mut d, rec_of(PERF_RECORD_SWITCH, PERF_RECORD_MISC_SWITCH_OUT, sw_p));
  append(&mut d, rec_of(PERF_RECORD_SWITCH_CPU_WIDE, 0, sw_p));
  append(&mut d, rec_of(PERF_RECORD_AUX, 0, aux_p));
  append(&mut d, rec_of(PERF_RECORD_ITRACE_START, 0, itr_p));
  append(&mut d, rec_of(PERF_RECORD_LOST_SAMPLES, 0, le_bytes(9, 8)));
  append(&mut d, rec_of(PERF_RECORD_NAMESPACES, 0, ns_p));
  append(&mut d, rec_of(PERF_RECORD_KSYMBOL, 0, ks_p));
  append(&mut d, rec_of(PERF_RECORD_BPF_EVENT, 0, bpf_p));
  var v = f_1attr(d, 0, 7, 0);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "misc record fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = perf_record_count(&f) == 12;
  if !int_is(perf_lost_field(&v, &f, 0, PERF_LOST_FIELD_ID), 0xAA) { ok = false; }
  if !int_is(perf_lost_field(&v, &f, 0, PERF_LOST_FIELD_LOST), 3) { ok = false; }
  if !int_is(perf_read_field(&v, &f, 1, 0, PERF_READ_FIELD_VALUE), 42) { ok = false; }
  if !int_is(perf_read_field(&v, &f, 1, 0, PERF_READ_FIELD_TIME_ENABLED), 100) { ok = false; }
  if !int_is(perf_read_field(&v, &f, 1, 0, PERF_READ_FIELD_TIME_RUNNING), 90) { ok = false; }
  if !int_is(perf_read_field(&v, &f, 1, 0, PERF_READ_FIELD_ID), 0x55) { ok = false; }
  if !int_is(perf_throttle_field(&v, &f, 2, PERF_THROTTLE_FIELD_STREAM_ID), 3) { ok = false; }
  if !int_is(perf_unthrottle_field(&v, &f, 3, PERF_THROTTLE_FIELD_TIME), 1) { ok = false; }
  if !int_is(perf_switch_field(&v, &f, 4, PERF_SWITCH_FIELD_NEXT_PREV_PID), 11) { ok = false; }
  if !int_is(perf_switch_field(&v, &f, 5, PERF_SWITCH_FIELD_NEXT_PREV_TID), 12) { ok = false; }
  if !int_is(perf_aux_field(&v, &f, 6, PERF_AUX_FIELD_AUX_OFFSET), 0x1000) { ok = false; }
  if !int_is(perf_aux_field(&v, &f, 6, PERF_AUX_FIELD_AUX_SIZE), 0x2000) { ok = false; }
  if !int_is(perf_aux_field(&v, &f, 6, PERF_AUX_FIELD_FLAGS), 3) { ok = false; }
  if !int_is(perf_itrace_start_field(&v, &f, 7, PERF_ITRACE_FIELD_TID), 2) { ok = false; }
  if !int_is(perf_lost_samples_field(&v, &f, 8, PERF_LOST_SAMPLES_FIELD_LOST), 9) { ok = false; }
  if !int_is(perf_namespaces_field(&v, &f, 9, 0, PERF_NS_FIELD_NR_NAMESPACES), 2) { ok = false; }
  if !int_is(perf_namespaces_field(&v, &f, 9, 0, PERF_NS_FIELD_ENTRY_DEV), 10) { ok = false; }
  if !int_is(perf_namespaces_field(&v, &f, 9, 1, PERF_NS_FIELD_ENTRY_INO), 13) { ok = false; }
  if !err_int_is(perf_namespaces_field(&v, &f, 9, 2, PERF_NS_FIELD_ENTRY_DEV), "perf: index out of range") { ok = false; }
  if !int_is(perf_ksymbol_field(&v, &f, 10, PERF_KSYMBOL_FIELD_ADDR), 0x1000) { ok = false; }
  if !int_is(perf_ksymbol_field(&v, &f, 10, PERF_KSYMBOL_FIELD_LEN), 16) { ok = false; }
  if !int_is(perf_ksymbol_field(&v, &f, 10, PERF_KSYMBOL_FIELD_KSYM_TYPE), 2) { ok = false; }
  if !int_is(perf_ksymbol_field(&v, &f, 10, PERF_KSYMBOL_FIELD_NAME_SIZE), 5) { ok = false; }
  if !int_is(perf_bpf_field(&v, &f, 11, PERF_BPF_FIELD_TYPE), 1) { ok = false; }
  if !int_is(perf_bpf_field(&v, &f, 11, PERF_BPF_FIELD_ID), 77) { ok = false; }
  return assert(ok, "LOST/READ/THROTTLE/SWITCH/AUX/ITRACE/LOST_SAMPLES/NAMESPACES/KSYMBOL/BPF");
}

fn t11() -> TestResult {
  let st = PERF_SAMPLE_IP + PERF_SAMPLE_TID + PERF_SAMPLE_TIME + PERF_SAMPLE_ADDR + PERF_SAMPLE_ID + PERF_SAMPLE_STREAM_ID + PERF_SAMPLE_CPU + PERF_SAMPLE_PERIOD + PERF_SAMPLE_READ;
  var sp = cat(cat(le_bytes(0x401234, 8), le_bytes(100, 4)), cat(cat(le_bytes(101, 4), le_bytes(555, 8)), cat(cat(le_bytes(0xdead, 8), le_bytes(7, 8)), cat(cat(le_bytes(8, 8), le_bytes(3, 4)), cat(cat(le_bytes(0, 4), le_bytes(1000, 8)), le_bytes(42, 8))))));
  var d = Vec[UInt8].new();
  append(&mut d, rec_of(PERF_RECORD_SAMPLE, PERF_RECORD_MISC_USER, sp));
  append(&mut d, rec_of(PERF_RECORD_COMM, 0, cat(cat(le_bytes(1, 4), le_bytes(2, 4)), hb("78"))));
  var v = f_1attr(d, st, 0, 0);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "sample fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = perf_record_count(&f) == 2;
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_IP), 0x401234) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_PID), 100) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_TID), 101) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_TIME), 555) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_ADDR), 0xdead) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_ID), 7) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_STREAM_ID), 8) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_CPU), 3) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_PERIOD), 1000) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_READ_VALUE), 42) { ok = false; }
  if !err_int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_IDENTIFIER), "perf: sample field not present in sample_type") { ok = false; }
  if !err_int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_COUNT), "perf: bad field selector") { ok = false; }
  if !err_int_is(perf_sample_field(&v, &f, 0, 3, PERF_SAMPLE_FIELD_IP), "perf: attr index out of range") { ok = false; }
  if !err_int_is(perf_sample_field(&v, &f, 2, 0, PERF_SAMPLE_FIELD_IP), "perf: record index out of range") { ok = false; }
  if !err_int_is(perf_sample_field(&v, &f, 1, 0, PERF_SAMPLE_FIELD_IP), "perf: record type mismatch") { ok = false; }
  return assert(ok, "SAMPLE: IP/TID/TIME/ADDR/ID/STREAM_ID/CPU/PERIOD/READ reconstructed from sample_type");
}

fn t12() -> TestResult {
  let st = PERF_SAMPLE_IDENTIFIER + PERF_SAMPLE_IP + PERF_SAMPLE_TID + PERF_SAMPLE_TIME + PERF_SAMPLE_ADDR + PERF_SAMPLE_ID + PERF_SAMPLE_STREAM_ID + PERF_SAMPLE_CPU + PERF_SAMPLE_PERIOD + PERF_SAMPLE_READ + PERF_SAMPLE_CALLCHAIN;
  let rf = PERF_FORMAT_TOTAL_TIME_ENABLED + PERF_FORMAT_ID;
  var sp = cat(cat(le_bytes(0x1234, 8), le_bytes(0x1000, 8)), cat(cat(le_bytes(1, 4), le_bytes(2, 4)), cat(cat(le_bytes(10, 8), le_bytes(0x2000, 8)), cat(cat(le_bytes(3, 8), le_bytes(4, 8)), cat(cat(le_bytes(5, 4), le_bytes(0, 4)), cat(cat(le_bytes(20, 8), le_bytes(30, 8)), cat(cat(le_bytes(40, 8), le_bytes(50, 8)), cat(le_bytes(2, 8), cat(le_bytes(0xAA, 8), le_bytes(0xBB, 8))))))))));
  var d = Vec[UInt8].new();
  append(&mut d, rec_of(PERF_RECORD_SAMPLE, PERF_RECORD_MISC_USER, sp));
  var v = f_1attr(d, st, rf, 0);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "identifier sample fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_IDENTIFIER), 0x1234);
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_IP), 0x1000) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_PID), 1) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_TID), 2) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_TIME), 10) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_ADDR), 0x2000) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_ID), 3) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_PERIOD), 20) { ok = false; }
  if !int_is(perf_sample_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_READ_VALUE), 30) { ok = false; }
  var rp = cat(cat(le_bytes(9, 4), le_bytes(10, 4)), cat(le_bytes(99, 8), cat(le_bytes(1, 8), cat(le_bytes(2, 8), cat(le_bytes(3, 8), cat(le_bytes(4, 8), le_bytes(5, 8)))))));
  var d2 = Vec[UInt8].new();
  append(&mut d2, rec_of(PERF_RECORD_READ, 0, rp));
  var v2 = f_1attr(d2, 0, PERF_FORMAT_GROUP, 0);
  let r2 = perf_parse(&v2);
  if !r2.is_ok { ok = false; } else {
    let f2: PerfFile = r2.value;
    if !err_int_is(perf_read_field(&v2, &f2, 0, 0, PERF_READ_FIELD_TIME_ENABLED), "perf: grouped read format not supported") { ok = false; }
    if !int_is(perf_read_field(&v2, &f2, 0, 0, PERF_READ_FIELD_VALUE), 99) { ok = false; }
  }
  return assert(ok, "SAMPLE with IDENTIFIER first, CALLCHAIN skip and READ id/time flags");
}

fn t13() -> TestResult {
  let st = PERF_SAMPLE_TID + PERF_SAMPLE_TIME + PERF_SAMPLE_CPU + PERF_SAMPLE_IDENTIFIER;
  var cp = cat(cat(le_bytes(1, 4), le_bytes(2, 4)), hb("78"));
  var tail = cat(cat(le_bytes(7, 4), le_bytes(8, 4)), cat(le_bytes(9, 8), cat(cat(le_bytes(2, 4), le_bytes(0, 4)), le_bytes(0xABC, 8))));
  var d = Vec[UInt8].new();
  append(&mut d, rec_of(PERF_RECORD_COMM, 0, cat(cp, tail)));
  append(&mut d, rec_of(PERF_RECORD_SAMPLE, 0, Vec[UInt8].new()));
  var v = f_1attr(d, st, 0, 262144);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "sample_id tail fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = int_is(perf_sample_id_tail_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_PID), 7);
  if !int_is(perf_sample_id_tail_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_TID), 8) { ok = false; }
  if !int_is(perf_sample_id_tail_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_TIME), 9) { ok = false; }
  if !int_is(perf_sample_id_tail_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_CPU), 2) { ok = false; }
  if !int_is(perf_sample_id_tail_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_IDENTIFIER), 0xABC) { ok = false; }
  if !err_int_is(perf_sample_id_tail_field(&v, &f, 0, 0, PERF_SAMPLE_FIELD_STREAM_ID), "perf: sample_id field not present in sample_type") { ok = false; }
  if !err_int_is(perf_sample_id_tail_field(&v, &f, 1, 0, PERF_SAMPLE_FIELD_PID), "perf: sample_id tail not applicable to SAMPLE records") { ok = false; }
  var v2 = f_1attr(d, st, 0, 0);
  let r2 = perf_parse(&v2);
  if !r2.is_ok { ok = false; } else {
    let f2: PerfFile = r2.value;
    if !err_int_is(perf_sample_id_tail_field(&v2, &f2, 0, 0, PERF_SAMPLE_FIELD_PID), "perf: sample_id_all not set") { ok = false; }
  }
  return assert(ok, "sample_id tails: pid/tid/time/cpu/identifier appended after the payload");
}

fn t14() -> TestResult {
  var idx_p = cat(le_bytes(2, 8), cat(cat(le_bytes(0x1001, 8), cat(le_bytes(0, 8), cat(le_bytes(0, 8), le_bytes(1, 8)))), cat(le_bytes(0x1002, 8), cat(le_bytes(1, 8), cat(le_bytes(3, 8), le_bytes(2, 8))))));
  var bid20 = cat(le_bytes(100, 4), cat(hb("00112233445566778899aabbccddeeff00112233"), hb("6c696278")));
  var bid32 = cat(le_bytes(200, 4), cat(hb("00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"), hb("616f7574")));
  var d = Vec[UInt8].new();
  append(&mut d, rec_of(PERF_RECORD_ID_INDEX, 0, idx_p));
  append(&mut d, rec_of(PERF_RECORD_HEADER_BUILD_ID, 0, bid20));
  append(&mut d, rec_of(PERF_RECORD_HEADER_BUILD_ID, 0, bid32));
  var v = f_1attr(d, 0, 0, 0);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "id_index/build_id fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = int_is(perf_id_index_count(&v, &f, 0), 2);
  if !int_is(perf_id_index_entry_field(&v, &f, 0, 0, PERF_IDX_ENTRY_FIELD_ID), 0x1001) { ok = false; }
  if !int_is(perf_id_index_entry_field(&v, &f, 0, 0, PERF_IDX_ENTRY_FIELD_IDX), 0) { ok = false; }
  if !int_is(perf_id_index_entry_field(&v, &f, 0, 0, PERF_IDX_ENTRY_FIELD_CPU), 0) { ok = false; }
  if !int_is(perf_id_index_entry_field(&v, &f, 0, 0, PERF_IDX_ENTRY_FIELD_TID), 1) { ok = false; }
  if !int_is(perf_id_index_entry_field(&v, &f, 0, 1, PERF_IDX_ENTRY_FIELD_ID), 0x1002) { ok = false; }
  if !int_is(perf_id_index_entry_field(&v, &f, 0, 1, PERF_IDX_ENTRY_FIELD_CPU), 3) { ok = false; }
  if !err_int_is(perf_id_index_entry_field(&v, &f, 0, 2, PERF_IDX_ENTRY_FIELD_ID), "perf: index out of range") { ok = false; }
  if !err_int_is(perf_id_index_entry_field(&v, &f, 0, 0, PERF_IDX_ENTRY_FIELD_COUNT), "perf: bad field selector") { ok = false; }
  if !err_int_is(perf_id_index_count(&v, &f, 1), "perf: record type mismatch") { ok = false; }
  if !int_is(perf_build_id_field(&v, &f, 1, 20, PERF_BD_FIELD_PID), 100) { ok = false; }
  if !int_is(perf_build_id_field(&v, &f, 1, 20, PERF_BD_FIELD_BUILD_ID_SIZE), 20) { ok = false; }
  if !int_is(perf_build_id_field(&v, &f, 1, 20, PERF_BD_FIELD_BUILD_ID_OFFSET), 348) { ok = false; }
  if !int_is(perf_build_id_field(&v, &f, 1, 20, PERF_BD_FIELD_FILENAME_OFFSET), 368) { ok = false; }
  if !int_is(perf_build_id_field(&v, &f, 1, 20, PERF_BD_FIELD_FILENAME_SIZE), 4) { ok = false; }
  if !bytes_is(perf_span_bytes(&v, 348, 20), hb("00112233445566778899aabbccddeeff00112233")) { ok = false; }
  if !str_is(perf_span_str(&v, 368, 4), "libx") { ok = false; }
  if !int_is(perf_build_id_field(&v, &f, 2, 32, PERF_BD_FIELD_PID), 200) { ok = false; }
  if !int_is(perf_build_id_field(&v, &f, 2, 32, PERF_BD_FIELD_BUILD_ID_SIZE), 32) { ok = false; }
  if !int_is(perf_build_id_field(&v, &f, 2, 32, PERF_BD_FIELD_FILENAME_SIZE), 4) { ok = false; }
  if !err_int_is(perf_build_id_field(&v, &f, 1, 0, PERF_BD_FIELD_PID), "perf: bad build id size") { ok = false; }
  if !err_int_is(perf_build_id_field(&v, &f, 1, 65, PERF_BD_FIELD_PID), "perf: bad build id size") { ok = false; }
  if !err_int_is(perf_build_id_field(&v, &f, 1, 64, PERF_BD_FIELD_PID), "perf: record payload out of bounds") { ok = false; }
  return assert(ok, "ID_INDEX entries and BUILD_ID records with 20/32-byte ids");
}

fn t15() -> TestResult {
  let host = str_rec("686f73743100");
  let osr = str_rec("362e362e3000");
  let ver = str_rec("7065726635");
  let cmd = str_list2("7065726600", "7265636f726400");
  let topo = cat(str_list1("302d3300"), cat(str_list1("302d3100"), cat(cat(le_bytes(0, 4), le_bytes(0, 4)), cat(le_bytes(1, 4), le_bytes(1, 4)))));
  let b1 = cat(le_bytes(100, 4), hb("00112233445566778899aabbccddeeff00112233"));
  let b2 = cat(le_bytes(200, 4), hb("ffeeddccbbaa99887766554433221100ffeeddcc"));
  let bid = cat(le_bytes(2, 4), cat(b1, b2));
  let desc = 104;
  let pay = desc + 6 * 16;
  var v = zeros(pay);
  put_header(&mut v, 152, 104, 0, 104, 0, 104, 0);
  put_uint(&mut v, PERF_HEADER_FLAGS_OFFSET, 10300, 8);
  var pos = pay;
  let o_bid = pos;
  let n_bid = bid.len();
  put_uint(&mut v, desc, pos, 8);
  put_uint(&mut v, desc + 8, n_bid, 8);
  append(&mut v, bid);
  pos = pos + n_bid;
  let o_host = pos;
  put_uint(&mut v, desc + 16, pos, 8);
  put_uint(&mut v, desc + 24, host.len(), 8);
  append(&mut v, host);
  pos = pos + 10;
  let o_osr = pos;
  put_uint(&mut v, desc + 32, pos, 8);
  put_uint(&mut v, desc + 40, osr.len(), 8);
  append(&mut v, osr);
  pos = pos + 10;
  let o_ver = pos;
  put_uint(&mut v, desc + 48, pos, 8);
  put_uint(&mut v, desc + 56, ver.len(), 8);
  append(&mut v, ver);
  pos = pos + 9;
  let o_cmd = pos;
  put_uint(&mut v, desc + 64, pos, 8);
  put_uint(&mut v, desc + 72, cmd.len(), 8);
  append(&mut v, cmd);
  pos = pos + cmd.len();
  let o_topo = pos;
  put_uint(&mut v, desc + 80, pos, 8);
  put_uint(&mut v, desc + 88, topo.len(), 8);
  append(&mut v, topo);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "feature fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = perf_feature_count(&f) == 6;
  if !perf_feature_present(&f, PERF_FEATURE_BUILD_ID) { ok = false; }
  if !perf_feature_present(&f, PERF_FEATURE_HOSTNAME) { ok = false; }
  if !perf_feature_present(&f, PERF_FEATURE_OSRELEASE) { ok = false; }
  if !perf_feature_present(&f, PERF_FEATURE_VERSION) { ok = false; }
  if !perf_feature_present(&f, PERF_FEATURE_CMDLINE) { ok = false; }
  if !perf_feature_present(&f, PERF_FEATURE_CPU_TOPOLOGY) { ok = false; }
  if perf_feature_present(&f, PERF_FEATURE_NUMA_TOPOLOGY) { ok = false; }
  if !int_is(perf_feature_bit(&f, 0), PERF_FEATURE_BUILD_ID) { ok = false; }
  if !int_is(perf_feature_bit(&f, 5), PERF_FEATURE_CPU_TOPOLOGY) { ok = false; }
  if !err_int_is(perf_feature_bit(&f, 6), "perf: index out of range") { ok = false; }
  if !int_is(perf_feature_section_field(&f, PERF_FEATURE_HOSTNAME, PERF_FEATURE_FIELD_OFFSET), o_host) { ok = false; }
  if !int_is(perf_feature_section_field(&f, PERF_FEATURE_HOSTNAME, PERF_FEATURE_FIELD_SIZE), 10) { ok = false; }
  if !int_is(perf_feature_string_field(&v, &f, PERF_FEATURE_HOSTNAME, PERF_STRING_FIELD_LEN), 6) { ok = false; }
  if !int_is(perf_feature_string_field(&v, &f, PERF_FEATURE_HOSTNAME, PERF_STRING_FIELD_TEXT_OFFSET), o_host + 4) { ok = false; }
  if !int_is(perf_feature_string_field(&v, &f, PERF_FEATURE_HOSTNAME, PERF_STRING_FIELD_TEXT_SIZE), 6) { ok = false; }
  if !str_is(perf_span_str(&v, o_host + 4, 5), "host1") { ok = false; }
  if !str_is(perf_span_str(&v, o_osr + 4, 6), "6.6.0") { ok = false; }
  if !int_is(perf_feature_string_field(&v, &f, PERF_FEATURE_VERSION, PERF_STRING_FIELD_LEN), 5) { ok = false; }
  if !str_is(perf_span_str(&v, o_ver + 4, 5), "perf5") { ok = false; }
  if !int_is(perf_feature_cmdline_count(&v, &f), 2) { ok = false; }
  if !int_is(perf_feature_cmdline_field(&v, &f, 0, PERF_STRING_FIELD_LEN), 5) { ok = false; }
  if !str_is(perf_span_str(&v, o_cmd + 4 + 4, 4), "perf") { ok = false; }
  if !int_is(perf_feature_cmdline_field(&v, &f, 1, PERF_STRING_FIELD_LEN), 7) { ok = false; }
  if !str_is(perf_span_str(&v, o_cmd + 4 + 9 + 4, 6), "record") { ok = false; }
  if !err_int_is(perf_feature_cmdline_field(&v, &f, 2, PERF_STRING_FIELD_LEN), "perf: index out of range") { ok = false; }
  if !int_is(perf_feature_topo_count(&v, &f, PERF_TOPO_LIST_CORES), 1) { ok = false; }
  if !int_is(perf_feature_topo_count(&v, &f, PERF_TOPO_LIST_THREADS), 1) { ok = false; }
  if !int_is(perf_feature_topo_string_field(&v, &f, PERF_TOPO_LIST_CORES, 0, PERF_STRING_FIELD_LEN), 4) { ok = false; }
  if !str_is(perf_span_str(&v, o_topo + 4 + 4, 3), "0-3") { ok = false; }
  if !str_is(perf_span_str(&v, o_topo + 20, 3), "0-1") { ok = false; }
  if !int_is(perf_feature_cpu_entry_count(&v, &f), 2) { ok = false; }
  if !int_is(perf_feature_cpu_entry_field(&v, &f, 0, PERF_CPU_ENTRY_FIELD_CORE_ID), 0) { ok = false; }
  if !int_is(perf_feature_cpu_entry_field(&v, &f, 1, PERF_CPU_ENTRY_FIELD_CORE_ID), 1) { ok = false; }
  if !int_is(perf_feature_cpu_entry_field(&v, &f, 1, PERF_CPU_ENTRY_FIELD_SOCKET_ID), 1) { ok = false; }
  if !int_is(perf_feature_build_id_count(&v, &f), 2) { ok = false; }
  if !int_is(perf_feature_build_id_field(&v, &f, 0, 20, PERF_FBI_FIELD_PID), 100) { ok = false; }
  if !int_is(perf_feature_build_id_field(&v, &f, 0, 20, PERF_FBI_FIELD_BUILD_ID_SIZE), 20) { ok = false; }
  if !bytes_is(perf_span_bytes(&v, o_bid + 8, 20), hb("00112233445566778899aabbccddeeff00112233")) { ok = false; }
  if !int_is(perf_feature_build_id_field(&v, &f, 1, 20, PERF_FBI_FIELD_PID), 200) { ok = false; }
  if !bytes_is(perf_feature_bytes(&v, &f, PERF_FEATURE_HOSTNAME), host) { ok = false; }
  if !err_int_is(perf_feature_section_field(&f, PERF_FEATURE_NUMA_TOPOLOGY, PERF_FEATURE_FIELD_OFFSET), "perf: feature not present") { ok = false; }
  if !err_int_is(perf_feature_section_field(&f, PERF_FEATURE_HOSTNAME, 9), "perf: bad field selector") { ok = false; }
  var v2 = zeros(104);
  put_header(&mut v2, 152, 104, 0, 104, 0, 104, 0);
  let r2 = perf_parse(&v2);
  if !r2.is_ok { ok = false; } else {
    let f2: PerfFile = r2.value;
    if !err_int_is(perf_feature_build_id_count(&v2, &f2), "perf: feature not present") { ok = false; }
    if !err_int_is(perf_feature_cmdline_count(&v2, &f2), "perf: feature not present") { ok = false; }
    if !err_int_is(perf_feature_topo_count(&v2, &f2, PERF_TOPO_LIST_CORES), "perf: feature not present") { ok = false; }
    if !err_int_is(perf_feature_string_field(&v2, &f2, PERF_FEATURE_HOSTNAME, PERF_STRING_FIELD_LEN), "perf: feature not present") { ok = false; }
  }
  return assert(ok, "features: build_id, strings, cmdline list, cpu_topology and errors");
}

fn t16() -> TestResult {
  var v1 = zeros(104);
  put_header(&mut v1, 152, 104, 0, 104, 0, 104, 0);
  put_uint(&mut v1, PERF_HEADER_FLAGS_OFFSET, 8, 8);
  var ok = err_file_is(perf_parse(&v1), "perf: feature sections out of bounds");
  var v2 = zeros(120);
  put_header(&mut v2, 152, 104, 0, 104, 0, 104, 0);
  put_uint(&mut v2, PERF_HEADER_FLAGS_OFFSET, 8, 8);
  put_uint(&mut v2, 104, 5000, 8);
  put_uint(&mut v2, 112, 4, 8);
  if !err_file_is(perf_parse(&v2), "perf: feature section out of bounds at 104") { ok = false; }
  let host = str_rec("686f73743100");
  var v3 = zeros(120);
  put_header(&mut v3, 152, 104, 0, 104, 0, 104, 0);
  put_uint(&mut v3, PERF_HEADER_FLAGS_OFFSET, 8, 8);
  put_uint(&mut v3, 104, 120, 8);
  put_uint(&mut v3, 112, host.len(), 8);
  append(&mut v3, host);
  let r3 = perf_parse(&v3);
  if !r3.is_ok { ok = false; } else {
    let f3: PerfFile = r3.value;
    if !err_int_is(perf_feature_section_field(&f3, PERF_FEATURE_HOSTNAME, PERF_FEATURE_FIELD_COUNT), "perf: bad field selector") { ok = false; }
    if !err_int_is(perf_feature_topo_count(&v3, &f3, 5), "perf: bad field selector") { ok = false; }
    if !err_int_is(perf_feature_cpu_entry_field(&v3, &f3, 0, 9), "perf: bad field selector") { ok = false; }
    if !err_int_is(perf_feature_cpu_entry_count(&v3, &f3), "perf: feature not present") { ok = false; }
    if !err_int_is(perf_feature_build_id_field(&v3, &f3, 0, 20, PERF_FBI_FIELD_PID), "perf: feature not present") { ok = false; }
    if !err_bytes_is(perf_feature_bytes(&v3, &f3, PERF_FEATURE_BUILD_ID), "perf: feature not present") { ok = false; }
  }
  var v4 = zeros(120);
  put_header(&mut v4, 152, 104, 0, 104, 0, 104, 0);
  put_uint(&mut v4, PERF_HEADER_FLAGS_OFFSET, 8, 8);
  put_uint(&mut v4, 104, 120, 8);
  put_uint(&mut v4, 112, 4, 8);
  append(&mut v4, le_bytes(1000, 4));
  let r4 = perf_parse(&v4);
  if !r4.is_ok { ok = false; } else {
    let f4: PerfFile = r4.value;
    if !err_int_is(perf_feature_string_field(&v4, &f4, PERF_FEATURE_HOSTNAME, PERF_STRING_FIELD_TEXT_SIZE), "perf: feature payload out of bounds") { ok = false; }
  }
  return assert(ok, "feature descriptors: truncated array, bad payload span, selector/presence errors");
}

fn t17() -> TestResult {
  var d1 = cat(cat(le_bytes(9, 4), le_bytes(0, 2)), le_bytes(4, 2));
  var v1 = f_1attr(d1, 0, 0, 0);
  var ok = err_file_is(perf_parse(&v1), "perf: bad record size at 256");
  var d2 = cat(cat(le_bytes(9, 4), le_bytes(0, 2)), le_bytes(100, 2));
  var v2 = f_1attr(d2, 0, 0, 0);
  if !err_file_is(perf_parse(&v2), "perf: oversized record at 256") { ok = false; }
  var d3 = cat(rec_of(PERF_RECORD_FINISHED_ROUND, 0, Vec[UInt8].new()), cat(le_bytes(1, 1), cat(le_bytes(2, 1), le_bytes(3, 1))));
  var v3 = f_1attr(d3, 0, 0, 0);
  if !err_file_is(perf_parse(&v3), "perf: truncated record at 264") { ok = false; }
  return assert(ok, "record walk rejects size < 8, oversized and truncated trailing bytes");
}

fn t18() -> TestResult {
  var v = f_1attr(Vec[UInt8].new(), 0, 0, 0);
  put_uint(&mut v, aoff(0) + 8, -1, 8);
  put_uint(&mut v, aoff(0) + 16, -2, 8);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "high-bit attr fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_CONFIG), -1);
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_SAMPLE_PERIOD), -2) { ok = false; }
  if !bool_is(perf_attr_flag(&f, 0, 63), false) { ok = false; }
  var mp = cat(cat(le_bytes(1, 4), le_bytes(2, 4)), cat(cat(le_bytes(-1, 8), le_bytes(0x1000, 8)), cat(le_bytes(0, 8), hb("78"))));
  var d = Vec[UInt8].new();
  append(&mut d, rec_of(PERF_RECORD_MMAP, 0, mp));
  var v2 = f_1attr(d, 0, 0, 0);
  let r2 = perf_parse(&v2);
  if !r2.is_ok { ok = false; } else {
    let f2: PerfFile = r2.value;
    if !int_is(perf_mmap_field(&v2, &f2, 0, PERF_MMAP_FIELD_ADDR), -1) { ok = false; }
  }
  var v3 = zeros(104);
  put_header(&mut v3, 152, 104, 0, 104, 0, 104, 0);
  put_uint(&mut v3, 40, 104, 8);
  put_uint(&mut v3, 48, -1, 8);
  if !err_file_is(perf_parse(&v3), "perf: data section out of bounds") { ok = false; }
  var v4 = zeros(104);
  put_header(&mut v4, 152, 104, 0, 104, 0, 104, 0);
  put_uint(&mut v4, 40, -1, 8);
  if !err_file_is(perf_parse(&v4), "perf: data section out of bounds") { ok = false; }
  var d5 = Vec[UInt8].new();
  append(&mut d5, rec_of(PERF_RECORD_ID_INDEX, 0, le_bytes(-1, 8)));
  var v5 = f_1attr(d5, 0, 0, 0);
  let r5 = perf_parse(&v5);
  if !r5.is_ok { ok = false; } else {
    let f5: PerfFile = r5.value;
    if !err_int_is(perf_id_index_count(&v5, &f5, 0), "perf: negative id_index count at 264") { ok = false; }
  }
  return assert(ok, "64-bit fields: bit 63 decodes raw; negative offsets/counts rejected with offsets");
}

fn t19() -> TestResult {
  var v = zeros(432);
  put_header(&mut v, 152, 104, 304, 432, 0, 432, 0);
  put_attr(&mut v, 104, 2, 0, 0);
  put_uint(&mut v, 104, 2, 4);
  put_uint(&mut v, 112, 0x1111, 8);
  put_attr(&mut v, 256, 4, 0, 0);
  put_uint(&mut v, 256, 4, 4);
  put_uint(&mut v, 264, 0x2222, 8);
  put_uint(&mut v, 240, 408, 8);
  put_uint(&mut v, 248, 8, 8);
  put_uint(&mut v, 392, 416, 8);
  put_uint(&mut v, 400, 16, 8);
  put_uint(&mut v, 408, 0xAA, 8);
  put_uint(&mut v, 416, 0xBB, 8);
  put_uint(&mut v, 424, 0xCC, 8);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "two-attr fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = perf_attr_count(&f) == 2;
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_TYPE), 2) { ok = false; }
  if !int_is(perf_attr_field(&f, 0, PERF_ATTR_FIELD_CONFIG), 0x1111) { ok = false; }
  if !int_is(perf_attr_field(&f, 1, PERF_ATTR_FIELD_TYPE), 4) { ok = false; }
  if !int_is(perf_attr_field(&f, 1, PERF_ATTR_FIELD_CONFIG), 0x2222) { ok = false; }
  if !int_is(perf_attr_ids_count(&f, 0), 1) { ok = false; }
  if !int_is(perf_attr_ids_count(&f, 1), 2) { ok = false; }
  if !int_is(perf_attr_id(&v, &f, 0, 0), 0xAA) { ok = false; }
  if !int_is(perf_attr_id(&v, &f, 1, 0), 0xBB) { ok = false; }
  if !int_is(perf_attr_id(&v, &f, 1, 1), 0xCC) { ok = false; }
  if !int_is(perf_attr_ids_section_field(&f, 1, PERF_FEATURE_FIELD_OFFSET), 416) { ok = false; }
  return assert(ok, "two attrs at stride 152 with independent ids sections");
}

fn t20() -> TestResult {
  var v = f_1attr(Vec[UInt8].new(), 0, 0, 0);
  let r = perf_parse(&v);
  if !r.is_ok { return assert(false, "span fixture must parse"); }
  let f: PerfFile = r.value;
  var ok = bytes_is(perf_span_bytes(&v, 0, 8), hb("50455246494c4532"));
  if !str_is(perf_span_str(&v, 0, 8), "PERFILE2") { ok = false; }
  let e0 = perf_span_bytes(&v, 0, 0);
  if !e0.is_ok { ok = false; }
  if !err_bytes_is(perf_span_bytes(&v, 0, 5000), "perf: span out of bounds") { ok = false; }
  if !err_bytes_is(perf_span_bytes(&v, -1, 1), "perf: span out of bounds") { ok = false; }
  if !err_str_is(perf_span_str(&v, 200, 200), "perf: span out of bounds") { ok = false; }
  if !err_bytes_is(perf_feature_bytes(&v, &f, PERF_FEATURE_HOSTNAME), "perf: feature not present") { ok = false; }
  return assert(ok, "span copies and feature byte accessors: bounds and empty results");
}

fn report(r: TestResult) -> Int {
  if r.passed {
    io.println("  [PASS] " + r.name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + r.name);
  io.flush_stdout();
  return 1;
}

fn main() -> Int {
  io.println("=== xiom.perf conformance tests ===");
  io.flush_stdout();
  var failed: Int = 0;
  io.println("  [RUN] t1"); io.flush_stdout();
  failed = failed + report(t1());
  io.println("  [RUN] t2"); io.flush_stdout();
  failed = failed + report(t2());
  io.println("  [RUN] t3"); io.flush_stdout();
  failed = failed + report(t3());
  io.println("  [RUN] t4"); io.flush_stdout();
  failed = failed + report(t4());
  io.println("  [RUN] t5"); io.flush_stdout();
  failed = failed + report(t5());
  io.println("  [RUN] t6"); io.flush_stdout();
  failed = failed + report(t6());
  io.println("  [RUN] t7"); io.flush_stdout();
  failed = failed + report(t7());
  io.println("  [RUN] t8"); io.flush_stdout();
  failed = failed + report(t8());
  io.println("  [RUN] t9"); io.flush_stdout();
  failed = failed + report(t9());
  io.println("  [RUN] t10"); io.flush_stdout();
  failed = failed + report(t10());
  io.println("  [RUN] t11"); io.flush_stdout();
  failed = failed + report(t11());
  io.println("  [RUN] t12"); io.flush_stdout();
  failed = failed + report(t12());
  io.println("  [RUN] t13"); io.flush_stdout();
  failed = failed + report(t13());
  io.println("  [RUN] t14"); io.flush_stdout();
  failed = failed + report(t14());
  io.println("  [RUN] t15"); io.flush_stdout();
  failed = failed + report(t15());
  io.println("  [RUN] t16"); io.flush_stdout();
  failed = failed + report(t16());
  io.println("  [RUN] t17"); io.flush_stdout();
  failed = failed + report(t17());
  io.println("  [RUN] t18"); io.flush_stdout();
  failed = failed + report(t18());
  io.println("  [RUN] t19"); io.flush_stdout();
  failed = failed + report(t19());
  io.println("  [RUN] t20"); io.flush_stdout();
  failed = failed + report(t20());
  if failed == 0 {
    io.println("xiom.perf: all tests passed");
    io.flush_stdout();
  } else {
    io.println("xiom.perf: tests failed");
    io.flush_stdout();
  }
  return failed;
}
