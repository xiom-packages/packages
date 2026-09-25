// XIOM -- xiom.marc conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.marc codec against the rules pinned in
// SPEC.md: the 24-byte leader, the 12-byte directory entries + 0x1E
// terminator, the 0x1E-terminated variable fields, the 0x1D record
// terminator, the 0x1F subfield markers, the documented error catalog and
// build/parse round trips.
//
// The 98-byte fixture is assembled byte by byte in this file, so marc_parse
// is exercised against bytes the test controls rather than only against
// marc_build. All Str equality goes through xiom.string.str_compare (BUG 17
// lowers `==` on Str values read from Vec elements to a pointer comparison);
// every Vec element read is bound to an explicitly typed local and every `&`
// argument is a local binding (never a field or call result).

module marc_tests
use xiom.io; use xiom.test;
use xiom.marc;
use xiom.string;

// --------------------------------------------------
//  Helpers (independent of src/marc.xi)
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
}

fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y { return false; }
    i = i + 1;
  }
  return true;
}

fn push_ascii(v: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
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

fn override_at(v: Vec[UInt8], pos: Int, s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i >= pos && i < pos + s.len() {
      out.push(string.byte_at(s, i - pos));
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

fn str_with_byte(a: Str, b: Int, c: Str) -> Str {
  var bytes = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    bytes.push(string.byte_at(a, i));
    i = i + 1;
  }
  bytes.push(b as UInt8);
  var j = 0;
  while j < c.len() {
    bytes.push(string.byte_at(c, j));
    j = j + 1;
  }
  return Str::from_utf8(bytes);
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

fn err_record_is(r: Result[MarcRecord, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  let msg: Str = r.error;
  return streq(msg, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  let msg: Str = r.error;
  return streq(msg, want);
}

// --------------------------------------------------
//  Fixture
// --------------------------------------------------

// One 98-byte record: leader "00098nam  2200061   4500"; three fields
// 001 "FIXTURE001" (span 11), 245 "10" $a"Title" $b"Sub" (span 15) and
// 650 " 0" $a"Topic" (span 10). Directory 36 bytes, base address 61,
// record terminator 0x1D at byte 97.
fn fixture() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_ascii(&mut v, "00098nam  2200061   4500");
  push_ascii(&mut v, "001001100000");
  push_ascii(&mut v, "245001500011");
  push_ascii(&mut v, "650001000026");
  v.push(30 as UInt8);
  push_ascii(&mut v, "FIXTURE001");
  v.push(30 as UInt8);
  push_ascii(&mut v, "10");
  v.push(31 as UInt8);
  push_ascii(&mut v, "aTitle");
  v.push(31 as UInt8);
  push_ascii(&mut v, "bSub");
  v.push(30 as UInt8);
  push_ascii(&mut v, " 0");
  v.push(31 as UInt8);
  push_ascii(&mut v, "aTopic");
  v.push(30 as UInt8);
  v.push(29 as UInt8);
  return v;
}

// Leader template for builder tests: status 'n', type 'a', bib 'm', the
// two control/coding spaces, encoding/cataloging/multipart spaces, and
// empty vectors. Recomputable leader fields are zero and ignored.
fn blank_record() -> MarcRecord {
  let tags = Vec[Str].new();
  let data = Vec[Str].new();
  let offsets = Vec[Int].new();
  let spans = Vec[Int].new();
  let soff = Vec[Int].new();
  let scnt = Vec[Int].new();
  let codes = Vec[Int].new();
  let vals = Vec[Str].new();
  let rec = MarcRecord{
    record_length: 0;
    record_status: 110;
    record_type: 97;
    bib_level: 109;
    type_of_control: 32;
    char_coding: 32;
    indicator_count: 50;
    subfield_code_count: 50;
    base_address: 0;
    encoding_level: 32;
    cataloging_form: 32;
    multipart_level: 32;
    entry_map: "4500";
    tags: tags;
    field_data: data;
    field_offsets: offsets;
    field_spans: spans;
    sub_offsets: soff;
    sub_counts: scnt;
    sub_codes: codes;
    sub_values: vals;
  };
  return rec;
}

fn parsed_fixture() -> MarcRecord {
  let data = fixture();
  let r = marc_parse(&data);
  if !r.is_ok { return blank_record(); }
  let rec: MarcRecord = r.value;
  return rec;
}

// The same three fields as fixture(), written through marc_build.
fn build_fixture_record() -> Result[Vec[UInt8], Str] {
  let tpl = blank_record();
  var tags = Vec[Str].new();
  tags.push("001"); tags.push("245"); tags.push("650");
  var fd = Vec[Str].new();
  fd.push("FIXTURE001"); fd.push("10"); fd.push(" 0");
  var counts = Vec[Int].new();
  counts.push(0); counts.push(2); counts.push(1);
  var codes = Vec[Int].new();
  codes.push(97); codes.push(98); codes.push(97);
  var vals = Vec[Str].new();
  vals.push("Title"); vals.push("Sub"); vals.push("Topic");
  return marc_build(&tpl, &tags, &fd, &counts, &codes, &vals);
}

// Drifted parallel vectors: two tags, one field-data text, two offsets, one
// span, two sub offsets, one sub count, one flat code and one flat value.
fn drifted_record() -> MarcRecord {
  var tags = Vec[Str].new();
  tags.push("001");
  tags.push("245");
  var data = Vec[Str].new();
  data.push("A");
  var offsets = Vec[Int].new();
  offsets.push(61);
  offsets.push(72);
  var spans = Vec[Int].new();
  spans.push(2);
  var soff = Vec[Int].new();
  soff.push(0);
  soff.push(5);
  var scnt = Vec[Int].new();
  scnt.push(9);
  var codes = Vec[Int].new();
  codes.push(97);
  var vals = Vec[Str].new();
  vals.push("v");
  let rec = MarcRecord{
    record_length: 0;
    record_status: 110;
    record_type: 97;
    bib_level: 109;
    type_of_control: 32;
    char_coding: 32;
    indicator_count: 50;
    subfield_code_count: 50;
    base_address: 0;
    encoding_level: 32;
    cataloging_form: 32;
    multipart_level: 32;
    entry_map: "4500";
    tags: tags;
    field_data: data;
    field_offsets: offsets;
    field_spans: spans;
    sub_offsets: soff;
    sub_counts: scnt;
    sub_codes: codes;
    sub_values: vals;
  };
  return rec;
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  let rec = parsed_fixture();
  var ok = marc_record_length(&rec) == 98;
  if marc_record_status(&rec) != 110 { ok = false; }
  if marc_record_type(&rec) != 97 { ok = false; }
  if marc_bib_level(&rec) != 109 { ok = false; }
  if marc_type_of_control(&rec) != 32 { ok = false; }
  if marc_char_coding(&rec) != 32 { ok = false; }
  if marc_indicator_count(&rec) != 50 { ok = false; }
  if marc_subfield_code_count(&rec) != 50 { ok = false; }
  if marc_base_address(&rec) != 61 { ok = false; }
  if marc_encoding_level(&rec) != 32 { ok = false; }
  if marc_cataloging_form(&rec) != 32 { ok = false; }
  if marc_multipart_level(&rec) != 32 { ok = false; }
  if !streq(marc_entry_map(&rec), "4500") { ok = false; }
  return assert(ok, "leader accessors decode the 24-byte fixture leader");
}

fn t2() -> TestResult {
  let rec = parsed_fixture();
  var ok = marc_field_count(&rec) == 3;
  if !streq(marc_tag(&rec, 0), "001") { ok = false; }
  if !streq(marc_tag(&rec, 1), "245") { ok = false; }
  if !streq(marc_tag(&rec, 2), "650") { ok = false; }
  if marc_field_offset(&rec, 0) != 61 { ok = false; }
  if marc_field_offset(&rec, 1) != 72 { ok = false; }
  if marc_field_offset(&rec, 2) != 87 { ok = false; }
  if marc_field_span(&rec, 0) != 11 { ok = false; }
  if marc_field_span(&rec, 1) != 15 { ok = false; }
  if marc_field_span(&rec, 2) != 10 { ok = false; }
  return assert(ok, "directory accessors expose tags, offsets and spans");
}

fn t3() -> TestResult {
  let rec = parsed_fixture();
  var ok = streq(marc_field_data(&rec, 0), "FIXTURE001");
  if !streq(marc_field_data(&rec, 1), "10") { ok = false; }
  if !streq(marc_field_data(&rec, 2), " 0") { ok = false; }
  return assert(ok, "field data is the bytes before the first 0x1F");
}

fn t4() -> TestResult {
  let rec = parsed_fixture();
  var ok = marc_subfield_count(&rec, 0) == 0;
  if marc_subfield_count(&rec, 1) != 2 { ok = false; }
  if marc_subfield_count(&rec, 2) != 1 { ok = false; }
  if marc_subfield_code(&rec, 1, 0) != 97 { ok = false; }
  if marc_subfield_code(&rec, 1, 1) != 98 { ok = false; }
  if marc_subfield_code(&rec, 2, 0) != 97 { ok = false; }
  if !streq(marc_subfield_value(&rec, 1, 0), "Title") { ok = false; }
  if !streq(marc_subfield_value(&rec, 1, 1), "Sub") { ok = false; }
  if !streq(marc_subfield_value(&rec, 2, 0), "Topic") { ok = false; }
  return assert(ok, "flat subfield code/value pairs match the fixture");
}

fn t5() -> TestResult {
  let rec = parsed_fixture();
  var ok = streq(marc_subfield_value_by_code(&rec, 1, 97), "Title");
  if !streq(marc_subfield_value_by_code(&rec, 1, 98), "Sub") { ok = false; }
  if !streq(marc_subfield_value_by_code(&rec, 2, 97), "Topic") { ok = false; }
  if !streq(marc_subfield_value_by_code(&rec, 1, 122), "") { ok = false; }
  if !streq(marc_subfield_value_by_code(&rec, 0, 97), "") { ok = false; }
  return assert(ok, "value_by_code finds the code or returns empty");
}

fn t6() -> TestResult {
  let rec = parsed_fixture();
  var ok = streq(marc_tag(&rec, 3), "");
  if !streq(marc_tag(&rec, -1), "") { ok = false; }
  if !streq(marc_field_data(&rec, 3), "") { ok = false; }
  if marc_field_offset(&rec, 3) != -1 { ok = false; }
  if marc_field_offset(&rec, -1) != -1 { ok = false; }
  if marc_field_span(&rec, 3) != 0 { ok = false; }
  if marc_subfield_count(&rec, 3) != 0 { ok = false; }
  if marc_subfield_count(&rec, -1) != 0 { ok = false; }
  if marc_subfield_code(&rec, 1, 2) != 0 { ok = false; }
  if marc_subfield_code(&rec, 1, -1) != 0 { ok = false; }
  if !streq(marc_subfield_value(&rec, 1, 2), "") { ok = false; }
  if !streq(marc_subfield_value(&rec, -1, 0), "") { ok = false; }
  if !streq(marc_subfield_value_by_code(&rec, -1, 97), "") { ok = false; }
  return assert(ok, "every accessor is safe out of range");
}

fn t7() -> TestResult {
  let data = fixture();
  let r = marc_parse(&data);
  if !r.is_ok { return assert(false, "parse then build is byte-identical"); }
  let rec: MarcRecord = r.value;
  let tags: Vec[Str] = rec.tags;
  let fd: Vec[Str] = rec.field_data;
  let counts: Vec[Int] = rec.sub_counts;
  let codes: Vec[Int] = rec.sub_codes;
  let vals: Vec[Str] = rec.sub_values;
  let built = marc_build(&rec, &tags, &fd, &counts, &codes, &vals);
  if !built.is_ok { return assert(false, "parse then build is byte-identical"); }
  let out: Vec[UInt8] = built.value;
  var ok = bytes_equal(&out, &data);
  if out.len() != 98 { ok = false; }
  return assert(ok, "parse then build is byte-identical");
}

fn t8() -> TestResult {
  let expected = fixture();
  let r = build_fixture_record();
  if !r.is_ok { return assert(false, "build writes the canonical fixture bytes"); }
  let out: Vec[UInt8] = r.value;
  return assert(bytes_equal(&out, &expected), "build writes the canonical fixture bytes");
}

fn t9() -> TestResult {
  let tpl = blank_record();
  let e1 = Vec[Str].new();
  let e2 = Vec[Str].new();
  let e3 = Vec[Int].new();
  let e4 = Vec[Int].new();
  let e5 = Vec[Str].new();
  let r = marc_build(&tpl, &e1, &e2, &e3, &e4, &e5);
  if !r.is_ok { return assert(false, "zero-field build is leader + 0x1E + 0x1D"); }
  let out: Vec[UInt8] = r.value;
  var want = Vec[UInt8].new();
  push_ascii(&mut want, "00026nam  2200025   4500");
  want.push(30 as UInt8);
  want.push(29 as UInt8);
  var ok = bytes_equal(&out, &want);
  if out.len() != 26 { ok = false; }
  let back = marc_parse(&out);
  if !back.is_ok {
    ok = false;
  } else {
    let rec: MarcRecord = back.value;
    if marc_field_count(&rec) != 0 { ok = false; }
    if marc_record_length(&rec) != 26 { ok = false; }
    if marc_base_address(&rec) != 25 { ok = false; }
  }
  return assert(ok, "zero-field build is leader + 0x1E + 0x1D, and re-parses");
}

fn t10() -> TestResult {
  let short = slice_of(fixture(), 0, 23);
  let empty = Vec[UInt8].new();
  var ok = err_record_is(marc_parse(&short), "marc: truncated leader");
  if !err_record_is(marc_parse(&empty), "marc: truncated leader") { ok = false; }
  let bad_digit = override_at(fixture(), 0, "X0098");
  if !err_record_is(marc_parse(&bad_digit), "marc: bad record length") { ok = false; }
  let too_small = override_at(fixture(), 0, "00025");
  if !err_record_is(marc_parse(&too_small), "marc: bad record length") { ok = false; }
  let too_big = override_at(fixture(), 0, "00100");
  if !err_record_is(marc_parse(&too_big), "marc: truncated record") { ok = false; }
  return assert(ok, "record length is digit-checked, floored at 26 and bounded by the buffer");
}

fn t11() -> TestResult {
  let map = override_at(fixture(), 20, "4501");
  var ok = err_record_is(marc_parse(&map), "marc: unsupported entry map");
  let ind = override_at(fixture(), 10, "1");
  if !err_record_is(marc_parse(&ind), "marc: unsupported indicator count") { ok = false; }
  let sub = override_at(fixture(), 11, "3");
  if !err_record_is(marc_parse(&sub), "marc: unsupported subfield code count") { ok = false; }
  return assert(ok, "entry map and leader 10/11 counts are pinned to MARC21");
}

fn t12() -> TestResult {
  let non_digit = override_at(fixture(), 12, "00A61");
  var ok = err_record_is(marc_parse(&non_digit), "marc: bad base address");
  let low = override_at(fixture(), 12, "00024");
  if !err_record_is(marc_parse(&low), "marc: bad base address") { ok = false; }
  let high = override_at(fixture(), 12, "00098");
  if !err_record_is(marc_parse(&high), "marc: bad base address") { ok = false; }
  let misaligned = override_at(fixture(), 12, "00062");
  if !err_record_is(marc_parse(&misaligned), "marc: bad directory size") { ok = false; }
  return assert(ok, "base address is digit-checked, bounded and 12-byte aligned");
}

fn t13() -> TestResult {
  let dir = set_byte(fixture(), 60, 32);
  var ok = err_record_is(marc_parse(&dir), "marc: missing directory terminator");
  let rec = set_byte(fixture(), 97, 32);
  if !err_record_is(marc_parse(&rec), "marc: missing record terminator") { ok = false; }
  return assert(ok, "directory and record terminator bytes are required");
}

fn t14() -> TestResult {
  let tag = set_byte(fixture(), 24, 65);
  var ok = err_record_is(marc_parse(&tag), "marc: bad directory entry");
  let len = set_byte(fixture(), 27, 65);
  if !err_record_is(marc_parse(&len), "marc: bad directory entry") { ok = false; }
  let start = set_byte(fixture(), 31, 65);
  if !err_record_is(marc_parse(&start), "marc: bad directory entry") { ok = false; }
  let zero = override_at(fixture(), 27, "0000");
  if !err_record_is(marc_parse(&zero), "marc: bad field length") { ok = false; }
  return assert(ok, "directory tag/length/start must be digits and length >= 1");
}

fn t15() -> TestResult {
  let range = override_at(fixture(), 31, "00036");
  var ok = err_record_is(marc_parse(&range), "marc: field out of range");
  let term = set_byte(fixture(), 86, 32);
  if !err_record_is(marc_parse(&term), "marc: missing field terminator") { ok = false; }
  return assert(ok, "field spans are bounded by the data area and terminated by 0x1E");
}

fn t16() -> TestResult {
  let data = set_byte(fixture(), 95, 31);
  return assert(err_record_is(marc_parse(&data), "marc: missing subfield code"), "a trailing 0x1F with no code byte is rejected");
}

fn t17() -> TestResult {
  let tpl = blank_record();
  var tpl_bad = blank_record();
  tpl_bad.record_status = 256;
  let e1 = Vec[Str].new();
  let e2 = Vec[Str].new();
  let e3 = Vec[Int].new();
  let e4 = Vec[Int].new();
  let e5 = Vec[Str].new();
  var ok = err_bytes_is(marc_build(&tpl_bad, &e1, &e2, &e3, &e4, &e5), "marc: bad leader byte");
  var tags = Vec[Str].new();
  tags.push("001");
  var fd_empty = Vec[Str].new();
  var counts_empty = Vec[Int].new();
  var codes_empty = Vec[Int].new();
  var vals_empty = Vec[Str].new();
  if !err_bytes_is(marc_build(&tpl, &tags, &fd_empty, &counts_empty, &codes_empty, &vals_empty), "marc: field count mismatch") { ok = false; }
  var fd_one = Vec[Str].new();
  fd_one.push("x");
  var counts_one = Vec[Int].new();
  counts_one.push(1);
  if !err_bytes_is(marc_build(&tpl, &tags, &fd_one, &counts_one, &codes_empty, &vals_empty), "marc: subfield count mismatch") { ok = false; }
  var codes_one = Vec[Int].new();
  codes_one.push(97);
  if !err_bytes_is(marc_build(&tpl, &tags, &fd_one, &counts_one, &codes_one, &vals_empty), "marc: subfield count mismatch") { ok = false; }
  var counts_neg = Vec[Int].new();
  counts_neg.push(-1);
  if !err_bytes_is(marc_build(&tpl, &tags, &fd_one, &counts_neg, &codes_empty, &vals_empty), "marc: field count mismatch") { ok = false; }
  return assert(ok, "builder validates leader bytes and vector lengths");
}

fn t18() -> TestResult {
  let tpl = blank_record();
  var tags = Vec[Str].new();
  tags.push("245");
  var bad_tags = Vec[Str].new();
  bad_tags.push("45X");
  var fd_plain = Vec[Str].new();
  fd_plain.push("10");
  var counts0 = Vec[Int].new();
  counts0.push(0);
  var codes_empty = Vec[Int].new();
  var vals_empty = Vec[Str].new();
  var ok = err_bytes_is(marc_build(&tpl, &bad_tags, &fd_plain, &counts0, &codes_empty, &vals_empty), "marc: bad tag");
  var fd_bad = Vec[Str].new();
  fd_bad.push(str_with_byte("10", 31, "aTitle"));
  if !err_bytes_is(marc_build(&tpl, &tags, &fd_bad, &counts0, &codes_empty, &vals_empty), "marc: bad field data") { ok = false; }
  var counts1 = Vec[Int].new();
  counts1.push(1);
  var vals1 = Vec[Str].new();
  vals1.push("x");
  var codes_31 = Vec[Int].new();
  codes_31.push(31);
  if !err_bytes_is(marc_build(&tpl, &tags, &fd_plain, &counts1, &codes_31, &vals1), "marc: bad subfield code") { ok = false; }
  var codes_0 = Vec[Int].new();
  codes_0.push(0);
  if !err_bytes_is(marc_build(&tpl, &tags, &fd_plain, &counts1, &codes_0, &vals1), "marc: bad subfield code") { ok = false; }
  var codes_256 = Vec[Int].new();
  codes_256.push(256);
  if !err_bytes_is(marc_build(&tpl, &tags, &fd_plain, &counts1, &codes_256, &vals1), "marc: bad subfield code") { ok = false; }
  var codes_a = Vec[Int].new();
  codes_a.push(97);
  var vals_sf = Vec[Str].new();
  vals_sf.push(str_with_byte("A", 31, "B"));
  if !err_bytes_is(marc_build(&tpl, &tags, &fd_plain, &counts1, &codes_a, &vals_sf), "marc: bad subfield value") { ok = false; }
  var vals_rs = Vec[Str].new();
  vals_rs.push(str_with_byte("A", 30, "B"));
  if !err_bytes_is(marc_build(&tpl, &tags, &fd_plain, &counts1, &codes_a, &vals_rs), "marc: bad subfield value") { ok = false; }
  return assert(ok, "builder rejects bad tags, field data, codes and values");
}

fn t19() -> TestResult {
  let tpl = blank_record();
  var tags1 = Vec[Str].new();
  tags1.push("001");
  var fd1 = Vec[Str].new();
  fd1.push(string.str_repeat("x", 10000));
  var counts1 = Vec[Int].new();
  counts1.push(0);
  var codes = Vec[Int].new();
  var vals = Vec[Str].new();
  var ok = err_bytes_is(marc_build(&tpl, &tags1, &fd1, &counts1, &codes, &vals), "marc: field too long");
  var tags10 = Vec[Str].new();
  var fd10 = Vec[Str].new();
  var counts10 = Vec[Int].new();
  let chunk = string.str_repeat("y", 9990);
  var i = 0;
  while i < 10 {
    tags10.push("001");
    fd10.push(chunk);
    counts10.push(0);
    i = i + 1;
  }
  if !err_bytes_is(marc_build(&tpl, &tags10, &fd10, &counts10, &codes, &vals), "marc: record too long") { ok = false; }
  var tags_many = Vec[Str].new();
  var fd_many = Vec[Str].new();
  var counts_many = Vec[Int].new();
  var j = 0;
  while j < 8332 {
    tags_many.push("001");
    fd_many.push("");
    counts_many.push(0);
    j = j + 1;
  }
  if !err_bytes_is(marc_build(&tpl, &tags_many, &fd_many, &counts_many, &codes, &vals), "marc: too many fields") { ok = false; }
  return assert(ok, "builder enforces the 9999/99999 length and field-count limits");
}

fn t20() -> TestResult {
  let tpl = blank_record();
  var tags = Vec[Str].new();
  tags.push("001"); tags.push("245"); tags.push("650");
  var fd = Vec[Str].new();
  fd.push("SEED"); fd.push("10"); fd.push(" 0");
  var counts = Vec[Int].new();
  counts.push(0); counts.push(3); counts.push(1);
  var codes = Vec[Int].new();
  codes.push(97); codes.push(98); codes.push(97); codes.push(97);
  var vals = Vec[Str].new();
  vals.push("one"); vals.push("two"); vals.push("three"); vals.push("");
  let r = marc_build(&tpl, &tags, &fd, &counts, &codes, &vals);
  if !r.is_ok { return assert(false, "repeated codes take the first match; empty values are kept"); }
  let out: Vec[UInt8] = r.value;
  let back = marc_parse(&out);
  if !back.is_ok { return assert(false, "repeated codes take the first match; empty values are kept"); }
  let rec: MarcRecord = back.value;
  var ok = marc_subfield_count(&rec, 1) == 3;
  if !streq(marc_subfield_value_by_code(&rec, 1, 97), "one") { ok = false; }
  if !streq(marc_subfield_value_by_code(&rec, 1, 98), "two") { ok = false; }
  if !streq(marc_subfield_value(&rec, 1, 2), "three") { ok = false; }
  if marc_subfield_count(&rec, 2) != 1 { ok = false; }
  if !streq(marc_subfield_value(&rec, 2, 0), "") { ok = false; }
  if !streq(marc_subfield_value_by_code(&rec, 2, 97), "") { ok = false; }
  if !streq(marc_field_data(&rec, 0), "SEED") { ok = false; }
  return assert(ok, "repeated codes take the first match; empty values are kept");
}

fn t21() -> TestResult {
  let data = append_byte(fixture(), 90);
  let r = marc_parse(&data);
  var ok = r.is_ok;
  if ok {
    let rec: MarcRecord = r.value;
    if marc_record_length(&rec) != 98 { ok = false; }
    if marc_field_count(&rec) != 3 { ok = false; }
    if !streq(marc_tag(&rec, 2), "650") { ok = false; }
    if marc_field_offset(&rec, 2) != 87 { ok = false; }
  }
  return assert(ok, "bytes after record_length are ignored");
}

fn t22() -> TestResult {
  let rec = drifted_record();
  var ok = marc_field_count(&rec) == 1;
  if marc_field_offset(&rec, 0) != 61 { ok = false; }
  if !streq(marc_tag(&rec, 0), "001") { ok = false; }
  if !streq(marc_tag(&rec, 1), "") { ok = false; }
  if marc_field_offset(&rec, 1) != -1 { ok = false; }
  if marc_field_span(&rec, 1) != 0 { ok = false; }
  if marc_subfield_count(&rec, 0) != 1 { ok = false; }
  if marc_subfield_count(&rec, 1) != 0 { ok = false; }
  if marc_subfield_code(&rec, 0, 0) != 97 { ok = false; }
  if marc_subfield_code(&rec, 0, 1) != 0 { ok = false; }
  if !streq(marc_subfield_value(&rec, 0, 0), "v") { ok = false; }
  if !streq(marc_subfield_value(&rec, 0, 1), "") { ok = false; }
  return assert(ok, "drifted parallel vectors stay in bounds and clamp");
}

fn main() -> Int {
  io.println("=== xiom.marc conformance tests ===");
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
    io.println("xiom.marc: all tests passed");
  } else {
    io.println("xiom.marc: tests failed");
  }
  return failed;
}
