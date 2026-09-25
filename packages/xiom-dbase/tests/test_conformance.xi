// XIOM -- xiom.dbase conformance tests (25 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.dbase codec against the rules pinned in
// SPEC.md: the 32-byte header, 32-byte field descriptors + 0x0D terminator,
// the record_size equation, record spans, the C/N typed accessors, the
// documented error catalog and build/parse round trips.
//
// All fixtures are assembled byte by byte in this file, so dbase_parse is
// exercised against bytes the test controls rather than only against
// dbase_build. Str comparisons go through xiom.string.compare's str_compare
// (BUG 17: `==` on Str values read from Vec elements lowers to a pointer
// comparison); every Vec element read is bound to an explicitly typed local
// and every `&` argument is a local binding (never a field or call result).

module dbase_tests
use xiom.io; use xiom.test;
use xiom.dbase;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Byte helpers (independent of src/dbase.xi)
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  }
  return true;
}

fn push_zeros(v: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
}

fn push_padded(v: &mut Vec[UInt8], s: Str, width: Int) {
  var i = 0;
  while i < width {
    if i < s.len() {
      v.push(string.byte_at(s, i));
    } else {
      v.push(32 as UInt8);
    }
    i = i + 1;
  }
}

fn push_le16(v: &mut Vec[UInt8], val: Int) {
  v.push((val % 256) as UInt8);
  v.push(((val / 256) % 256) as UInt8);
}

fn push_le32(v: &mut Vec[UInt8], val: Int) {
  v.push((val % 256) as UInt8);
  v.push(((val / 256) % 256) as UInt8);
  v.push(((val / 65536) % 256) as UInt8);
  v.push(((val / 16777216) % 256) as UInt8);
}

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

fn append_byte(v: Vec[UInt8], b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  out.push(b as UInt8);
  return out;
}

fn fill_zero(v: Vec[UInt8], start: Int, count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i >= start && i < start + count {
      out.push(0 as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn slice_of(v: Vec[UInt8], start: Int, count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < count {
    out.push(v[start + i]);
    i = i + 1;
  }
  return out;
}

fn all_zero(v: Vec[UInt8], start: Int, count: Int) -> Bool {
  var i = 0;
  while i < count {
    let b: Int = (v[start + i] as Int) & 0xFF;
    if b != 0 { return false; }
    i = i + 1;
  }
  return true;
}

fn descriptor(v: &mut Vec[UInt8], name: Str, ty: Int, len: Int, dec: Int) {
  var i = 0;
  while i < 11 {
    if i < name.len() {
      v.push(string.byte_at(name, i));
    } else {
      v.push(0 as UInt8);
    }
    i = i + 1;
  }
  v.push(ty as UInt8);
  push_zeros(v, 4);
  v.push(len as UInt8);
  v.push(dec as UInt8);
  push_zeros(v, 14);
}

fn record3(v: &mut Vec[UInt8], a: Str, b: Str, c: Str) {
  v.push(32 as UInt8);
  push_padded(v, a, 5);
  push_padded(v, b, 3);
  push_padded(v, c, 8);
}

// --------------------------------------------------
//  Result helpers
// --------------------------------------------------

fn err_table_is(r: Result[DbaseTable, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn field_str(data: &Vec[UInt8], t: &DbaseTable, r: Int, f: Int) -> Str {
  let b = dbase_field_bytes(data, t, r, f);
  if !b.is_ok { return "<err>"; }
  let v: Vec[UInt8] = b.value;
  return Str::from_utf8(v);
}

fn num_or_empty(data: &Vec[UInt8], t: &DbaseTable, r: Int, f: Int) -> Str {
  let n = dbase_field_number(data, t, r, f);
  if !n.is_ok { return "<err>"; }
  let s: Str = n.value;
  return s;
}

fn raw_cells(data: &Vec[UInt8], t: &DbaseTable, r: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  var f = 0;
  while f < dbase_field_count(t) {
    out.push(field_str(data, t, r, f));
    f = f + 1;
  }
  return out;
}

fn collected_records(data: &Vec[UInt8], t: &DbaseTable) -> Vec[Vec[Str]] {
  var out = Vec[Vec[Str]].new();
  var r = 0;
  while r < dbase_record_count(t) {
    out.push(raw_cells(data, t, r));
    r = r + 1;
  }
  return out;
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// 3 fields (NAME C 5, AGE N 3, HIRED D 8), 2 records, header 129 bytes,
// record 17 bytes, total 163 bytes.
fn fixture() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(3 as UInt8);
  v.push(26 as UInt8);
  v.push(9 as UInt8);
  v.push(25 as UInt8);
  push_le32(&mut v, 2);
  push_le16(&mut v, 129);
  push_le16(&mut v, 17);
  push_zeros(&mut v, 20);
  descriptor(&mut v, "NAME", 67, 5, 0);
  descriptor(&mut v, "AGE", 78, 3, 0);
  descriptor(&mut v, "HIRED", 68, 8, 0);
  v.push(13 as UInt8);
  record3(&mut v, "Ada", " 36", "20260101");
  record3(&mut v, "Bob", "  7", "20251231");
  return v;
}

// Zero fields, 3 records: header 33 bytes, record size 1, total 36 bytes.
fn bare_fixture() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(3 as UInt8);
  v.push(26 as UInt8);
  v.push(9 as UInt8);
  v.push(25 as UInt8);
  push_le32(&mut v, 3);
  push_le16(&mut v, 33);
  push_le16(&mut v, 1);
  push_zeros(&mut v, 20);
  v.push(13 as UInt8);
  v.push(32 as UInt8);
  v.push(32 as UInt8);
  v.push(32 as UInt8);
  return v;
}

// Zero fields, zero records: header + terminator only (33 bytes).
fn empty_bytes() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(3 as UInt8);
  v.push(26 as UInt8);
  v.push(9 as UInt8);
  v.push(25 as UInt8);
  push_le32(&mut v, 0);
  push_le16(&mut v, 33);
  push_le16(&mut v, 1);
  push_zeros(&mut v, 20);
  v.push(13 as UInt8);
  return v;
}

// A one-field descriptor table with no records (used as a builder input).
fn desc_table(name: Str, ty: Int, len: Int, dec: Int) -> DbaseTable {
  var names = Vec[Str].new();
  names.push(name);
  var types = Vec[Int].new();
  types.push(ty);
  var lens = Vec[Int].new();
  lens.push(len);
  var decs = Vec[Int].new();
  decs.push(dec);
  var addresses = Vec[Int].new();
  addresses.push(0);
  var offsets = Vec[Int].new();
  offsets.push(1);
  var ro = Vec[Int].new();
  var rs = Vec[Int].new();
  let t = DbaseTable{
    version: 3;
    last_update_y: 26;
    last_update_m: 9;
    last_update_d: 25;
    record_count: 0;
    header_size: 65;
    record_size: 1 + len;
    names: names;
    types: types;
    lengths: lens;
    decimals: decs;
    addresses: addresses;
    offsets: offsets;
    record_offsets: ro;
    record_spans: rs;
  };
  return t;
}

// NAME C 5, AGE N 3, HIRED D 8 with no records.
fn three_table() -> DbaseTable {
  var names = Vec[Str].new();
  names.push("NAME");
  names.push("AGE");
  names.push("HIRED");
  var types = Vec[Int].new();
  types.push(67);
  types.push(78);
  types.push(68);
  var lens = Vec[Int].new();
  lens.push(5);
  lens.push(3);
  lens.push(8);
  var decs = Vec[Int].new();
  decs.push(0);
  decs.push(0);
  decs.push(0);
  var addresses = Vec[Int].new();
  addresses.push(0);
  addresses.push(0);
  addresses.push(0);
  var offsets = Vec[Int].new();
  offsets.push(1);
  offsets.push(6);
  offsets.push(9);
  var ro = Vec[Int].new();
  var rs = Vec[Int].new();
  let t = DbaseTable{
    version: 3;
    last_update_y: 26;
    last_update_m: 9;
    last_update_d: 25;
    record_count: 0;
    header_size: 129;
    record_size: 17;
    names: names;
    types: types;
    lengths: lens;
    decimals: decs;
    addresses: addresses;
    offsets: offsets;
    record_offsets: ro;
    record_spans: rs;
  };
  return t;
}

// Copy of `t` with a different last-update date.
fn with_date(t: &DbaseTable, y: Int, m: Int, d: Int) -> DbaseTable {
  let out = DbaseTable{
    version: t.version;
    last_update_y: y;
    last_update_m: m;
    last_update_d: d;
    record_count: t.record_count;
    header_size: t.header_size;
    record_size: t.record_size;
    names: t.names;
    types: t.types;
    lengths: t.lengths;
    decimals: t.decimals;
    addresses: t.addresses;
    offsets: t.offsets;
    record_offsets: t.record_offsets;
    record_spans: t.record_spans;
  };
  return out;
}

// Copy of `t` with a different version byte.
fn with_version(t: &DbaseTable, v: Int) -> DbaseTable {
  let out = DbaseTable{
    version: v;
    last_update_y: t.last_update_y;
    last_update_m: t.last_update_m;
    last_update_d: t.last_update_d;
    record_count: t.record_count;
    header_size: t.header_size;
    record_size: t.record_size;
    names: t.names;
    types: t.types;
    lengths: t.lengths;
    decimals: t.decimals;
    addresses: t.addresses;
    offsets: t.offsets;
    record_offsets: t.record_offsets;
    record_spans: t.record_spans;
  };
  return out;
}

// Deliberately drifted parallel vectors: names/lengths/decimals/addresses
// have 2 elements, types has 1, and the record span vectors are empty while
// record_count says 2.
fn drifted_table() -> DbaseTable {
  var names = Vec[Str].new();
  names.push("A");
  names.push("B");
  var types = Vec[Int].new();
  types.push(67);
  var lens = Vec[Int].new();
  lens.push(1);
  lens.push(1);
  var decs = Vec[Int].new();
  decs.push(0);
  decs.push(0);
  var addresses = Vec[Int].new();
  addresses.push(0);
  addresses.push(0);
  var offsets = Vec[Int].new();
  offsets.push(1);
  offsets.push(2);
  var ro = Vec[Int].new();
  var rs = Vec[Int].new();
  let t = DbaseTable{
    version: 3;
    last_update_y: 26;
    last_update_m: 9;
    last_update_d: 25;
    record_count: 2;
    header_size: 97;
    record_size: 3;
    names: names;
    types: types;
    lengths: lens;
    decimals: decs;
    addresses: addresses;
    offsets: offsets;
    record_offsets: ro;
    record_spans: rs;
  };
  return t;
}

// A table with `n` one-byte C fields named "F".
fn many_fields_table(n: Int, flen: Int) -> DbaseTable {
  var names = Vec[Str].new();
  var types = Vec[Int].new();
  var lens = Vec[Int].new();
  var decs = Vec[Int].new();
  var i = 0;
  while i < n {
    names.push("F");
    types.push(67);
    lens.push(flen);
    decs.push(0);
    i = i + 1;
  }
  var addresses = Vec[Int].new();
  var offsets = Vec[Int].new();
  var ro = Vec[Int].new();
  var rs = Vec[Int].new();
  let hs = 32 + n * 32 + 1;
  let rsz = 1 + n * flen;
  let t = DbaseTable{
    version: 3;
    last_update_y: 26;
    last_update_m: 9;
    last_update_d: 25;
    record_count: 0;
    header_size: hs;
    record_size: rsz;
    names: names;
    types: types;
    lengths: lens;
    decimals: decs;
    addresses: addresses;
    offsets: offsets;
    record_offsets: ro;
    record_spans: rs;
  };
  return t;
}

// A one-field table built through dbase_build and returned as bytes; on a
// build failure the caller gets an empty buffer (and its parse check fails).
fn one_field_bytes(ty: Int, len: Int, cell: Str) -> Vec[UInt8] {
  let t = desc_table("NUM", ty, len, 0);
  var rec = Vec[Str].new();
  rec.push(cell);
  var recs = Vec[Vec[Str]].new();
  recs.push(rec);
  let b = dbase_build(&t, &recs);
  if !b.is_ok { return Vec[UInt8].new(); }
  return b.value;
}

fn num_ok(cell: Str) -> Bool {
  let data = one_field_bytes(78, 8, cell);
  let pr = dbase_parse(&data);
  if !pr.is_ok { return false; }
  let t = pr.value;
  let r = dbase_field_number(&data, &t, 0, 0);
  return r.is_ok;
}

fn num_text(cell: Str) -> Str {
  let data = one_field_bytes(78, 8, cell);
  let pr = dbase_parse(&data);
  if !pr.is_ok { return "<parse>"; }
  let t = pr.value;
  let r = dbase_field_number(&data, &t, 0, 0);
  if !r.is_ok { return "<err>"; }
  let s: Str = r.value;
  return s;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = fixture();
  let pr = dbase_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let t = pr.value;
  var ok = dbase_version(&t) == 3;
  if dbase_last_update(&t) != 260925 { ok = false; }
  if dbase_record_count(&t) != 2 { ok = false; }
  if dbase_header_size(&t) != 129 { ok = false; }
  if dbase_record_size(&t) != 17 { ok = false; }
  if dbase_field_count(&t) != 3 { ok = false; }
  if !streq(dbase_field_name(&t, 0), "NAME") { ok = false; }
  if !streq(dbase_field_name(&t, 1), "AGE") { ok = false; }
  if !streq(dbase_field_name(&t, 2), "HIRED") { ok = false; }
  if dbase_field_type(&t, 0) != 67 { ok = false; }
  if dbase_field_type(&t, 1) != 78 { ok = false; }
  if dbase_field_type(&t, 2) != 68 { ok = false; }
  if dbase_field_length(&t, 0) != 5 { ok = false; }
  if dbase_field_length(&t, 1) != 3 { ok = false; }
  if dbase_field_length(&t, 2) != 8 { ok = false; }
  if dbase_field_decimals(&t, 0) != 0 { ok = false; }
  if dbase_field_address(&t, 0) != 0 { ok = false; }
  return assert(ok, "header scalars and descriptor columns");
}

fn t2() -> TestResult {
  let f = fixture();
  let fp = dbase_parse(&f);
  if !fp.is_ok { return assert(false, "fixture must parse"); }
  let ft = fp.value;
  var ok = dbase_header_size(&ft) == 129;
  if dbase_record_size(&ft) != 17 { ok = false; }
  if dbase_record_count(&ft) != 2 { ok = false; }
  let b = bare_fixture();
  let bp = dbase_parse(&b);
  if !bp.is_ok { return assert(false, "bare fixture must parse"); }
  let bt = bp.value;
  if dbase_record_count(&bt) != 3 { ok = false; }
  if dbase_header_size(&bt) != 33 { ok = false; }
  if dbase_record_size(&bt) != 1 { ok = false; }
  if dbase_record_offset(&bt, 0) != 33 { ok = false; }
  if dbase_record_offset(&bt, 2) != 35 { ok = false; }
  return assert(ok, "LE16 and LE32 header fields decode little-endian");
}

fn t3() -> TestResult {
  let data = fixture();
  let pr = dbase_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let t = pr.value;
  var ok = dbase_record_offset(&t, 0) == 129;
  if dbase_record_offset(&t, 1) != 146 { ok = false; }
  if dbase_record_offset(&t, 2) != -1 { ok = false; }
  if dbase_record_offset(&t, -1) != -1 { ok = false; }
  if dbase_record_span(&t, 0) != 17 { ok = false; }
  if dbase_record_span(&t, 1) != 17 { ok = false; }
  if dbase_record_span(&t, 2) != 0 { ok = false; }
  let rb = dbase_record_bytes(&data, &t, 0);
  if !rb.is_ok { ok = false; }
  else {
    let bytes: Vec[UInt8] = rb.value;
    if bytes.len() != 17 { ok = false; }
    elif (bytes[0] as Int) != 32 { ok = false; }
    elif !bytes_equal(bytes, slice_of(data, 129, 17)) { ok = false; }
  }
  return assert(ok, "record offsets, spans and the active deletion flag");
}

fn t4() -> TestResult {
  let data = fixture();
  let pr = dbase_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let t = pr.value;
  var ok = dbase_field_offset(&t, 0) == 1;
  if dbase_field_offset(&t, 1) != 6 { ok = false; }
  if dbase_field_offset(&t, 2) != 9 { ok = false; }
  if dbase_field_offset(&t, 3) != 0 { ok = false; }
  if dbase_field_offset(&t, -1) != 0 { ok = false; }
  return assert(ok, "field offsets include the deletion flag");
}

fn t5() -> TestResult {
  let data = fixture();
  let pr = dbase_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let t = pr.value;
  var ok = streq(field_str(&data, &t, 0, 0), "Ada  ");
  if !streq(field_str(&data, &t, 0, 1), " 36") { ok = false; }
  if !streq(field_str(&data, &t, 0, 2), "20260101") { ok = false; }
  if !streq(field_str(&data, &t, 1, 0), "Bob  ") { ok = false; }
  if !streq(field_str(&data, &t, 1, 1), "  7") { ok = false; }
  if !streq(field_str(&data, &t, 1, 2), "20251231") { ok = false; }
  return assert(ok, "raw field bytes are returned verbatim");
}

fn t6() -> TestResult {
  let data = fixture();
  let pr = dbase_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let t = pr.value;
  var ok = err_bytes_is(dbase_field_bytes(&data, &t, 0, 3), "dbase: field out of range");
  if !err_bytes_is(dbase_field_bytes(&data, &t, 0, -1), "dbase: field out of range") { ok = false; }
  if !err_bytes_is(dbase_field_bytes(&data, &t, -1, 0), "dbase: record out of range") { ok = false; }
  if !err_bytes_is(dbase_field_bytes(&data, &t, 2, 0), "dbase: record out of range") { ok = false; }
  let cut = slice_of(data, 0, 140);
  if !err_bytes_is(dbase_field_bytes(&cut, &t, 1, 2), "dbase: truncated data") { ok = false; }
  return assert(ok, "field_bytes range and truncation errors");
}

fn t7() -> TestResult {
  let data = fixture();
  let pr = dbase_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let t = pr.value;
  let full = dbase_record_bytes(&data, &t, 1);
  var ok = full.is_ok;
  if ok {
    let bytes: Vec[UInt8] = full.value;
    if !bytes_equal(bytes, slice_of(data, 146, 17)) { ok = false; }
  }
  if !err_bytes_is(dbase_record_bytes(&data, &t, 2), "dbase: record out of range") { ok = false; }
  if !err_bytes_is(dbase_record_bytes(&data, &t, -1), "dbase: record out of range") { ok = false; }
  let cut = slice_of(data, 0, 150);
  if !err_bytes_is(dbase_record_bytes(&cut, &t, 1), "dbase: truncated data") { ok = false; }
  return assert(ok, "record_bytes copies the exact span and guards bounds");
}

fn t8() -> TestResult {
  let data = fixture();
  let pr = dbase_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let t = pr.value;
  let text = dbase_field_text(&data, &t, 0, 0);
  var ok = text.is_ok;
  if ok {
    let s: Str = text.value;
    if !streq(s, "Ada  ") { ok = false; }
  }
  if !err_str_is(dbase_field_text(&data, &t, 0, 1), "dbase: field type mismatch") { ok = false; }
  if !err_str_is(dbase_field_text(&data, &t, 0, 2), "dbase: field type mismatch") { ok = false; }
  if !err_str_is(dbase_field_text(&data, &t, 0, 3), "dbase: field out of range") { ok = false; }
  if !err_str_is(dbase_field_text(&data, &t, -1, 0), "dbase: record out of range") { ok = false; }
  return assert(ok, "field_text returns padded C bytes and type-checks");
}

fn t9() -> TestResult {
  let data = fixture();
  let pr = dbase_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let t = pr.value;
  var ok = streq(num_or_empty(&data, &t, 0, 1), "36");
  if !streq(num_or_empty(&data, &t, 1, 1), "7") { ok = false; }
  if !err_str_is(dbase_field_number(&data, &t, 0, 0), "dbase: field type mismatch") { ok = false; }
  if !err_str_is(dbase_field_number(&data, &t, 0, 2), "dbase: field type mismatch") { ok = false; }
  if !err_str_is(dbase_field_number(&data, &t, 0, 3), "dbase: field out of range") { ok = false; }
  return assert(ok, "field_number trims and validates N text");
}

fn t10() -> TestResult {
  var ok = num_ok("0");
  if !num_ok("-12") { ok = false; }
  if !num_ok("+3.5") { ok = false; }
  if !num_ok("3.14") { ok = false; }
  if !num_ok("0007") { ok = false; }
  if !num_ok(" 42") { ok = false; }
  if !streq(num_text(" 42"), "42") { ok = false; }
  if !streq(num_text("+3.5"), "+3.5") { ok = false; }
  if !streq(num_text("0007"), "0007") { ok = false; }
  return assert(ok, "numeric text accepted forms are trimmed, not converted");
}

fn t11() -> TestResult {
  var ok = !num_ok("");
  if num_ok("abc") { ok = false; }
  if num_ok("1.2.3") { ok = false; }
  if num_ok("1.") { ok = false; }
  if num_ok(".5") { ok = false; }
  if num_ok("-") { ok = false; }
  if num_ok("+") { ok = false; }
  if num_ok("1e3") { ok = false; }
  if num_ok("1 2") { ok = false; }
  let data = one_field_bytes(78, 8, "abc");
  let pr = dbase_parse(&data);
  if !pr.is_ok { ok = false; }
  else {
    let t = pr.value;
    if !err_str_is(dbase_field_number(&data, &t, 0, 0), "dbase: bad numeric text") { ok = false; }
  }
  return assert(ok, "malformed numeric text is rejected");
}

fn t12() -> TestResult {
  let short = slice_of(fixture(), 0, 31);
  var ok = err_table_is(dbase_parse(&short), "dbase: truncated header");
  let v4 = set_byte(fixture(), 0, 4);
  if !err_table_is(dbase_parse(&v4), "dbase: unsupported version") { ok = false; }
  let v139 = set_byte(fixture(), 0, 139);
  if !err_table_is(dbase_parse(&v139), "dbase: unsupported version") { ok = false; }
  let tiny = set_byte(set_byte(fixture(), 8, 32), 9, 0);
  if !err_table_is(dbase_parse(&tiny), "dbase: bad header size") { ok = false; }
  let misaligned = set_byte(set_byte(fixture(), 8, 34), 33, 13);
  if !err_table_is(dbase_parse(&misaligned), "dbase: bad header size") { ok = false; }
  let big = set_byte(set_byte(fixture(), 8, 2), 9, 1);
  if !err_table_is(dbase_parse(&big), "dbase: truncated header") { ok = false; }
  return assert(ok, "parse errors: truncation, version, header size");
}

fn t13() -> TestResult {
  let no_term = set_byte(fixture(), 128, 12);
  return assert(err_table_is(dbase_parse(&no_term), "dbase: missing terminator"), "descriptor terminator must be 0x0D");
}

fn t14() -> TestResult {
  let empty_name = fill_zero(fixture(), 32, 11);
  var ok = err_table_is(dbase_parse(&empty_name), "dbase: bad field name");
  let digit_first = set_byte(fixture(), 32, 49);
  if !err_table_is(dbase_parse(&digit_first), "dbase: bad field name") { ok = false; }
  let lower = set_byte(fixture(), 32, 97);
  if !err_table_is(dbase_parse(&lower), "dbase: bad field name") { ok = false; }
  let hyphen = set_byte(fixture(), 36, 45);
  if !err_table_is(dbase_parse(&hyphen), "dbase: bad field name") { ok = false; }
  let high = set_byte(fixture(), 32, 128);
  if !err_table_is(dbase_parse(&high), "dbase: bad field name") { ok = false; }
  return assert(ok, "field names are 1..11 bytes of A-Z, 0-9, _ (A-Z first)");
}

fn t15() -> TestResult {
  let ty_x = set_byte(fixture(), 43, 88);
  var ok = err_table_is(dbase_parse(&ty_x), "dbase: bad field type");
  let ty_0 = set_byte(fixture(), 43, 0);
  if !err_table_is(dbase_parse(&ty_0), "dbase: bad field type") { ok = false; }
  let ty_255 = set_byte(fixture(), 43, 255);
  if !err_table_is(dbase_parse(&ty_255), "dbase: bad field type") { ok = false; }
  return assert(ok, "field type must be C, N, D, L, M or F");
}

fn t16() -> TestResult {
  let rs18 = set_byte(set_byte(fixture(), 10, 18), 11, 0);
  var ok = err_table_is(dbase_parse(&rs18), "dbase: bad record size");
  let rs0 = set_byte(set_byte(fixture(), 10, 0), 11, 0);
  if !err_table_is(dbase_parse(&rs0), "dbase: bad record size") { ok = false; }
  let cnt3 = set_byte(fixture(), 4, 3);
  if !err_table_is(dbase_parse(&cnt3), "dbase: truncated records") { ok = false; }
  let cnt1 = set_byte(fixture(), 4, 1);
  let pr = dbase_parse(&cnt1);
  if !pr.is_ok { ok = false; }
  else {
    let t = pr.value;
    if dbase_record_count(&t) != 1 { ok = false; }
    if dbase_record_offset(&t, 1) != -1 { ok = false; }
  }
  return assert(ok, "record_size equation and record area bounds");
}

fn t17() -> TestResult {
  let with_eof = append_byte(fixture(), 26);
  let pr = dbase_parse(&with_eof);
  if !pr.is_ok { return assert(false, "trailing 0x1A must be tolerated"); }
  let t = pr.value;
  var ok = dbase_record_count(&t) == 2;
  if dbase_record_offset(&t, 1) != 146 { ok = false; }
  return assert(ok, "bytes after the record area are ignored");
}

fn t18() -> TestResult {
  let bare = bare_fixture();
  let bp = dbase_parse(&bare);
  if !bp.is_ok { return assert(false, "bare fixture must parse"); }
  let bt = bp.value;
  var ok = dbase_field_count(&bt) == 0;
  if dbase_record_count(&bt) != 3 { ok = false; }
  if dbase_record_offset(&bt, 2) != 35 { ok = false; }
  if dbase_record_span(&bt, 2) != 1 { ok = false; }
  let empty = empty_bytes();
  let ep = dbase_parse(&empty);
  if !ep.is_ok { return assert(false, "empty table must parse"); }
  let et = ep.value;
  if dbase_field_count(&et) != 0 { ok = false; }
  if dbase_record_count(&et) != 0 { ok = false; }
  if dbase_record_offset(&et, 0) != -1 { ok = false; }
  if !err_bytes_is(dbase_record_bytes(&empty, &et, 0), "dbase: record out of range") { ok = false; }
  var recs = Vec[Vec[Str]].new();
  let built = dbase_build(&et, &recs);
  if !built.is_ok { ok = false; }
  elif !bytes_equal(built.value, empty) { ok = false; }
  return assert(ok, "zero-field and zero-record tables round-trip");
}

fn t19() -> TestResult {
  let t = desc_table("A", 67, 4, 0);
  var recs = Vec[Vec[Str]].new();
  let b = dbase_build(&t, &recs);
  if !b.is_ok { return assert(false, "one-field build must succeed"); }
  let out: Vec[UInt8] = b.value;
  var ok = out.len() == 65;
  if (out[0] as Int) != 3 { ok = false; }
  if (out[1] as Int) != 26 { ok = false; }
  if (out[2] as Int) != 9 { ok = false; }
  if (out[3] as Int) != 25 { ok = false; }
  if !all_zero(out, 4, 4) { ok = false; }
  if (out[8] as Int) != 65 { ok = false; }
  if (out[9] as Int) != 0 { ok = false; }
  if (out[10] as Int) != 5 { ok = false; }
  if (out[11] as Int) != 0 { ok = false; }
  if !all_zero(out, 12, 20) { ok = false; }
  if (out[32] as Int) != 65 { ok = false; }
  if !all_zero(out, 33, 10) { ok = false; }
  if (out[43] as Int) != 67 { ok = false; }
  if !all_zero(out, 44, 4) { ok = false; }
  if (out[48] as Int) != 4 { ok = false; }
  if (out[49] as Int) != 0 { ok = false; }
  if !all_zero(out, 50, 14) { ok = false; }
  if (out[64] as Int) != 13 { ok = false; }
  return assert(ok, "build pins the 32-byte header and 32-byte descriptor");
}

fn t20() -> TestResult {
  let data = fixture();
  let pr = dbase_parse(&data);
  if !pr.is_ok { return assert(false, "fixture must parse"); }
  let t = pr.value;
  let recs = collected_records(&data, &t);
  let b = dbase_build(&t, &recs);
  if !b.is_ok { return assert(false, "fixture build must succeed"); }
  let expected = fixture();
  return assert(bytes_equal(b.value, expected), "parse -> build reproduces the fixture byte for byte");
}

fn t21() -> TestResult {
  let t = three_table();
  var recs = Vec[Vec[Str]].new();
  var rec = Vec[Str].new();
  rec.push("Ada");
  rec.push("36");
  rec.push("20260101");
  recs.push(rec);
  let b = dbase_build(&t, &recs);
  if !b.is_ok { return assert(false, "three-field build must succeed"); }
  let data: Vec<UInt8> = b.value;
  var ok = data.len() == 146;
  if (data[129] as Int) != 32 { ok = false; }
  let pr = dbase_parse(&data);
  if !pr.is_ok { return assert(false, "built table must parse"); }
  let pt = pr.value;
  if dbase_record_count(&pt) != 1 { ok = false; }
  if !streq(field_str(&data, &pt, 0, 0), "Ada  ") { ok = false; }
  if !streq(field_str(&data, &pt, 0, 1), "36 ") { ok = false; }
  if !streq(field_str(&data, &pt, 0, 2), "20260101") { ok = false; }
  if !streq(num_or_empty(&data, &pt, 0, 1), "36") { ok = false; }
  let txt = dbase_field_text(&data, &pt, 0, 0);
  if !txt.is_ok { ok = false; }
  else {
    let s: Str = txt.value;
    if !streq(s, "Ada  ") { ok = false; }
  }
  return assert(ok, "short cells are space-padded to their field length");
}

fn t22() -> TestResult {
  var empty = Vec[Vec[Str]].new();
  let drifted = drifted_table();
  var ok = err_bytes_is(dbase_build(&drifted, &empty), "dbase: descriptor count mismatch");
  let bad_name = desc_table("2BAD", 67, 1, 0);
  if !err_bytes_is(dbase_build(&bad_name, &empty), "dbase: bad field name") { ok = false; }
  let bad_type = desc_table("AB", 88, 1, 0);
  if !err_bytes_is(dbase_build(&bad_type, &empty), "dbase: bad field type") { ok = false; }
  let bad_len = desc_table("AB", 67, 256, 0);
  if !err_bytes_is(dbase_build(&bad_len, &empty), "dbase: bad field length") { ok = false; }
  let bad_dec = desc_table("AB", 67, 1, 300);
  if !err_bytes_is(dbase_build(&bad_dec, &empty), "dbase: bad field decimals") { ok = false; }
  let base = desc_table("AB", 67, 1, 0);
  let bad_date = with_date(&base, 256, 9, 25);
  if !err_bytes_is(dbase_build(&bad_date, &empty), "dbase: bad date") { ok = false; }
  let bad_version = with_version(&base, 4);
  if !err_bytes_is(dbase_build(&bad_version, &empty), "dbase: unsupported version") { ok = false; }
  var recs1 = Vec[Vec[Str]].new();
  var r1 = Vec[Str].new();
  r1.push("a");
  r1.push("b");
  recs1.push(r1);
  if !err_bytes_is(dbase_build(&base, &recs1), "dbase: field count mismatch") { ok = false; }
  var recs2 = Vec[Vec[Str]].new();
  var r2 = Vec[Str].new();
  r2.push("abcde");
  recs2.push(r2);
  if !err_bytes_is(dbase_build(&base, &recs2), "dbase: field too long") { ok = false; }
  let many = many_fields_table(2048, 1);
  if !err_bytes_is(dbase_build(&many, &empty), "dbase: bad header size") { ok = false; }
  let wide = many_fields_table(300, 255);
  if !err_bytes_is(dbase_build(&wide, &empty), "dbase: bad record size") { ok = false; }
  return assert(ok, "builder validation error catalog");
}

fn t23() -> TestResult {
  let t = drifted_table();
  var ok = dbase_field_count(&t) == 1;
  if dbase_field_type(&t, 1) != 0 { ok = false; }
  if !streq(dbase_field_name(&t, 1), "B") { ok = false; }
  if dbase_field_length(&t, 1) != 1 { ok = false; }
  if dbase_field_offset(&t, 1) != 2 { ok = false; }
  if dbase_record_offset(&t, 0) != 97 { ok = false; }
  if dbase_record_offset(&t, 1) != 100 { ok = false; }
  if dbase_record_offset(&t, 2) != -1 { ok = false; }
  if dbase_record_span(&t, 0) != 3 { ok = false; }
  if dbase_record_span(&t, 2) != 0 { ok = false; }
  var empty = Vec[Vec[Str]].new();
  if !err_bytes_is(dbase_build(&t, &empty), "dbase: descriptor count mismatch") { ok = false; }
  return assert(ok, "drifted parallel vectors stay in bounds and fall back");
}

fn t24() -> TestResult {
  let t11 = desc_table("ABCDEFGHIJK", 67, 1, 0);
  var recs = Vec[Vec[Str]].new();
  let b11 = dbase_build(&t11, &recs);
  var ok = b11.is_ok;
  if ok {
    let data: Vec<UInt8> = b11.value;
    let pr = dbase_parse(&data);
    if !pr.is_ok { ok = false; }
    else {
      let pt = pr.value;
      if !streq(dbase_field_name(&pt, 0), "ABCDEFGHIJK") { ok = false; }
    }
  }
  let t12 = desc_table("ABCDEFGHIJKL", 67, 1, 0);
  if !err_bytes_is(dbase_build(&t12, &recs), "dbase: bad field name") { ok = false; }
  let t_us = desc_table("_A", 67, 1, 0);
  if !err_bytes_is(dbase_build(&t_us, &recs), "dbase: bad field name") { ok = false; }
  let t_mix = desc_table("F1_2", 67, 1, 0);
  if !dbase_build(&t_mix, &recs).is_ok { ok = false; }
  return assert(ok, "11-byte names fit; 12-byte names and bad first bytes are rejected");
}

fn t25() -> TestResult {
  var ok = true;
  let v83 = set_byte(fixture(), 0, 131);
  let p83 = dbase_parse(&v83);
  if !p83.is_ok { ok = false; }
  else {
    let t83 = p83.value;
    if dbase_version(&t83) != 131 { ok = false; }
  }
  let v30 = set_byte(fixture(), 0, 48);
  let p30 = dbase_parse(&v30);
  if !p30.is_ok { ok = false; }
  else {
    let t30 = p30.value;
    if dbase_version(&t30) != 48 { ok = false; }
  }
  let t3 = three_table();
  let t48 = with_version(&t3, 48);
  var recs = Vec[Vec[Str]].new();
  var rec = Vec[Str].new();
  rec.push("Ada");
  rec.push("36");
  rec.push("20260101");
  recs.push(rec);
  let b48 = dbase_build(&t48, &recs);
  if !b48.is_ok { ok = false; }
  else {
    let data: Vec<UInt8> = b48.value;
    let pr = dbase_parse(&data);
    if !pr.is_ok { ok = false; }
    else {
      let pt = pr.value;
      if dbase_version(&pt) != 48 { ok = false; }
      if !streq(num_or_empty(&data, &pt, 0, 1), "36") { ok = false; }
    }
  }
  return assert(ok, "0x83 and 0x30 versions parse and build");
}

fn main() -> Int {
  io.println("=== xiom.dbase conformance tests ===");
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
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.dbase: all tests passed");
  } else {
    io.println("xiom.dbase: tests failed");
  }
  return failed;
}
