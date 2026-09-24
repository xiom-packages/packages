// XIOM -- xiom.tar conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.tar codec against POSIX ustar archives.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the exact pinned 512-byte header tar_build
// emits, independent checksum verification and corruption errors, magic
// variants, pinned name/mode/size/mtime/data offsets, prefix joining, the
// typeflag mapping ('0'/NUL -> 0, '5' -> 5, raw byte otherwise), 512-byte
// payload padding (1/511/512/513 and multiples), the terminator rules,
// EOF tolerance (no terminator, missing final padding, partial zero tail),
// truncation errors, 100/101-byte names, count mismatch, octal field forms
// (leading spaces/NULs, malformed digits), tar_entry_data bounds, round
// trips and empty archives.
//
// Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison). Hand-built
// archives are assembled byte by byte so the parser is exercised against
// bytes this test file controls, not against tar_build.

module tar_tests
use xiom.io; use xiom.test;
use xiom.tar;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// Expected bytes for a hex string ("" on malformed input; the caller then
// fails on the length/byte checks).
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

fn name_is(a: &TarArchive, i: Int, want: Str) -> Bool {
  return str_eq(tar_entry_name(a, i), want);
}

fn err_archive_is(r: Result[TarArchive, Str], want: Str) -> Bool {
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

// --------------------------------------------------
//  Byte helpers (independent of src/tar.xi)
// --------------------------------------------------

fn push_text(v: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn push_zeros(v: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    v.push(0 as UInt8);
    i = i + 1;
  }
}

fn zeros(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_zeros(&mut v, n);
  return v;
}

fn push_octal(v: &mut Vec[UInt8], val: Int, digits: Int) {
  var div: Int = 1;
  var k = 1;
  while k < digits {
    div = div * 8;
    k = k + 1;
  }
  var n = val;
  var i = 0;
  while i < digits {
    var d = 0;
    if div > 0 {
      d = (n / div) % 8;
      n = n % div;
    }
    v.push((48 + d) as UInt8);
    div = div / 8;
    i = i + 1;
  }
}

// Unsigned sum of the 512 bytes at `base` with the checksum field read as
// spaces (offsets 148..155).
fn block_sum(v: &Vec[UInt8], base: Int) -> Int {
  var sum = 0;
  var i = 0;
  while i < 512 {
    if i >= 148 && i < 156 {
      sum = sum + 32;
    } else {
      sum = sum + ((v[base + i] as Int) & 0xFF);
    }
    i = i + 1;
  }
  return sum;
}

// Write the 6 octal digits, NUL and space of the checksum field.
fn set_checksum(v: &mut Vec[UInt8], base: Int) {
  let sum = block_sum(v, base);
  var cs = Vec[UInt8].new();
  push_octal(&mut cs, sum, 6);
  var j = 0;
  while j < 6 {
    v[base + 148 + j] = cs[j];
    j = j + 1;
  }
  v[base + 154] = 0 as UInt8;
  v[base + 155] = 32 as UInt8;
}

// Independent octal reader for pinned-field checks (skips NUL/space).
fn read_octal(v: &Vec<UInt8>, off: Int, len: Int) -> Int {
  var value = 0;
  var i = 0;
  while i < len {
    let c: Int = (v[off + i] as Int) & 0xFF;
    if c >= 48 && c <= 55 {
      value = value * 8 + (c - 48);
    }
    i = i + 1;
  }
  return value;
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

// Copy of `v` with `src` written over [pos, pos + src.len()).
fn set_range(v: Vec[UInt8], pos: Int, src: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i >= pos && i < pos + src.len() {
      out.push(src[i - pos]);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
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

fn concat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < a.len() {
    out.push(a[i]);
    i = i + 1;
  }
  i = 0;
  while i < b.len() {
    out.push(b[i]);
    i = i + 1;
  }
  return out;
}

// Hand-built 512-byte ustar header, independent of src/tar.xi.
fn mk_header(name: Str, mode: Int, size: Int, mtime: Int, tflag: Int, prefix_str: Str) -> Vec[UInt8] {
  var h = Vec[UInt8].new();
  var i = 0;
  while i < 100 {
    if i < name.len() {
      h.push(string.byte_at(name, i));
    } else {
      h.push(0 as UInt8);
    }
    i = i + 1;
  }
  push_octal(&mut h, mode, 7);
  h.push(0 as UInt8);
  push_octal(&mut h, 0, 7);
  h.push(0 as UInt8);
  push_octal(&mut h, 0, 7);
  h.push(0 as UInt8);
  push_octal(&mut h, size, 11);
  h.push(0 as UInt8);
  push_octal(&mut h, mtime, 11);
  h.push(0 as UInt8);
  push_zeros(&mut h, 8);
  h.push(tflag as UInt8);
  push_zeros(&mut h, 100);
  push_text(&mut h, "ustar");
  h.push(0 as UInt8);
  push_text(&mut h, "00");
  push_zeros(&mut h, 32);
  push_zeros(&mut h, 32);
  push_octal(&mut h, 0, 7);
  h.push(0 as UInt8);
  push_octal(&mut h, 0, 7);
  h.push(0 as UInt8);
  var p = 0;
  while p < 155 {
    if p < prefix_str.len() {
      h.push(string.byte_at(prefix_str, p));
    } else {
      h.push(0 as UInt8);
    }
    p = p + 1;
  }
  push_zeros(&mut h, 12);
  set_checksum(&mut h, 0);
  return h;
}

// Header + payload padded to a 512-byte boundary.
fn entry(hdr: Vec<UInt8>, payload: Vec<UInt8>) -> Vec<UInt8> {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < hdr.len() {
    out.push(hdr[i]);
    i = i + 1;
  }
  i = 0;
  while i < payload.len() {
    out.push(payload[i]);
    i = i + 1;
  }
  let pad = (512 - (payload.len() % 512)) % 512;
  push_zeros(&mut out, pad);
  return out;
}

fn terminators() -> Vec[UInt8] {
  return zeros(1024);
}

fn payload_of(n: Int, seed: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((seed + i) % 251) as UInt8);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var names = Vec[Str].new();
  names.push("a.txt");
  var payloads = Vec[Vec[UInt8]].new();
  var p = Vec[UInt8].new();
  p.push(97 as UInt8);
  p.push(98 as UInt8);
  p.push(99 as UInt8);
  payloads.push(p);
  let r = tar_build(&names, &payloads);
  if !r.is_ok { return assert(false, "tar_build must succeed"); }
  let out = r.value;
  var ok = out.len() == 2048;
  // Pinned first 345 bytes of the header: name, mode/uid/gid/size/mtime/
  // checksum fields, typeflag, linkname, magic, version, uname/gname and
  // the dev fields. Bytes 345..512 (prefix + pad) must be zero.
  let want = hb("612e74787400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003030303036343400303030303030300030303030303030003030303030303030303033003030303030303030303030003031303135370020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000075737461720030300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030303030303030003030303030303000");
  if want.len() != 345 { ok = false; }
  var i = 0;
  while i < 345 {
    if i >= want.len() { ok = false; } elif out[i] != want[i] { ok = false; }
    i = i + 1;
  }
  i = 345;
  while i < 512 {
    if (out[i] as Int) != 0 { ok = false; }
    i = i + 1;
  }
  if (out[512] as Int) != 97 { ok = false; }
  if (out[513] as Int) != 98 { ok = false; }
  if (out[514] as Int) != 99 { ok = false; }
  i = 515;
  while i < 2048 {
    if (out[i] as Int) != 0 { ok = false; }
    i = i + 1;
  }
  let pr = tar_parse(&out);
  if !pr.is_ok {
    ok = false;
  } else {
    let ar = pr.value;
    if tar_entry_count(&ar) != 1 { ok = false; }
    if !name_is(&ar, 0, "a.txt") { ok = false; }
    if tar_entry_size(&ar, 0) != 3 { ok = false; }
  }
  return assert(ok, "tar_build emits the pinned canonical ustar header");
}

fn t2() -> TestResult {
  var names = Vec[Str].new();
  names.push("c.bin");
  var payloads = Vec[Vec[UInt8]].new();
  payloads.push(payload_of(2, 7));
  let r = tar_build(&names, &payloads);
  if !r.is_ok { return assert(false, "tar_build must succeed"); }
  let out = r.value;
  let stored = read_octal(&out, 148, 8);
  let sum = block_sum(&out, 0);
  var ok = stored == sum;
  if sum <= 0 { ok = false; }
  let pr = tar_parse(&out);
  if !pr.is_ok { ok = false; }
  return assert(ok, "stored checksum equals the independent 512-byte sum");
}

fn t3() -> TestResult {
  var data = entry(mk_header("f.bin", 420, 1, 0, 48, ""), payload_of(1, 1));
  data = concat(data, terminators());
  if !tar_parse(&data).is_ok { return assert(false, "base archive must parse"); }
  let bad_name = set_byte(data, 0, 70);
  let bad_digit = set_byte(data, 148, 57);
  var ok = err_archive_is(tar_parse(&bad_name), "tar: bad checksum");
  if !err_archive_is(tar_parse(&bad_digit), "tar: bad octal") { ok = false; }
  return assert(ok, "corrupted header and non-octal checksum are Err");
}

fn t4() -> TestResult {
  var data = entry(mk_header("m.bin", 420, 1, 0, 48, ""), payload_of(1, 2));
  data = concat(data, terminators());
  var bad1 = set_byte(data, 257, 88);
  set_checksum(&mut bad1, 0);
  var bad2 = set_byte(data, 261, 88);
  set_checksum(&mut bad2, 0);
  var bad3 = set_byte(data, 262, 65);
  set_checksum(&mut bad3, 0);
  var ok = err_archive_is(tar_parse(&bad1), "tar: bad magic");
  if !err_archive_is(tar_parse(&bad2), "tar: bad magic") { ok = false; }
  if !err_archive_is(tar_parse(&bad3), "tar: bad magic") { ok = false; }
  if !tar_parse(&data).is_ok { ok = false; }
  return assert(ok, "bad ustar magic is Err once the checksum matches");
}

fn t5() -> TestResult {
  var data = entry(mk_header("g.bin", 420, 1, 0, 48, ""), payload_of(1, 3));
  var gnu = set_byte(data, 262, 32);
  gnu = set_byte(gnu, 263, 32);
  gnu = set_byte(gnu, 264, 0);
  set_checksum(&mut gnu, 0);
  gnu = concat(gnu, terminators());
  let pr = tar_parse(&gnu);
  var ok = pr.is_ok;
  if pr.is_ok {
    let ar = pr.value;
    if tar_entry_count(&ar) != 1 { ok = false; }
    if !name_is(&ar, 0, "g.bin") { ok = false; }
  }
  return assert(ok, "GNU magic variant (\"ustar \" + NUL version) parses");
}

fn t6() -> TestResult {
  var data = entry(mk_header("pin.txt", 493, 7, 1700000000, 48, ""), payload_of(7, 10));
  data = concat(data, terminators());
  let pr = tar_parse(&data);
  if !pr.is_ok { return assert(false, "hand-built archive must parse"); }
  let ar = pr.value;
  let mode: Int = ar.modes[0];
  let mtime: Int = ar.mtimes[0];
  let typ: Int = ar.types[0];
  let off: Int = ar.data_offsets[0];
  var ok = tar_entry_count(&ar) == 1;
  if !name_is(&ar, 0, "pin.txt") { ok = false; }
  if tar_entry_size(&ar, 0) != 7 { ok = false; }
  if mode != 493 { ok = false; }
  if mtime != 1700000000 { ok = false; }
  if typ != 0 { ok = false; }
  if off != 512 { ok = false; }
  let pd = tar_entry_data(&data, &ar, 0);
  if !pd.is_ok { ok = false; } elif !bytes_equal(pd.value, payload_of(7, 10)) { ok = false; }
  return assert(ok, "name/mode/size/mtime/offset pinned; data slice exact");
}

fn t7() -> TestResult {
  var data = entry(mk_header("plain.txt", 420, 0, 0, 48, ""), zeros(0));
  data = concat(data, entry(mk_header("file.txt", 420, 2, 0, 48, "dir/sub"), payload_of(2, 20)));
  data = concat(data, terminators());
  let pr = tar_parse(&data);
  if !pr.is_ok { return assert(false, "prefix archive must parse"); }
  let ar = pr.value;
  var ok = tar_entry_count(&ar) == 2;
  if !name_is(&ar, 0, "plain.txt") { ok = false; }
  if !name_is(&ar, 1, "dir/sub/file.txt") { ok = false; }
  return assert(ok, "ustar prefix joins with '/' only when non-empty");
}

fn t8() -> TestResult {
  var data = entry(mk_header("dir", 493, 0, 0, 53, ""), zeros(0));
  data = concat(data, entry(mk_header("link", 420, 0, 0, 50, ""), zeros(0)));
  data = concat(data, entry(mk_header("nul", 420, 1, 0, 0, ""), payload_of(1, 30)));
  data = concat(data, terminators());
  let pr = tar_parse(&data);
  if !pr.is_ok { return assert(false, "typeflag archive must parse"); }
  let ar = pr.value;
  let t0: Int = ar.types[0];
  let t1: Int = ar.types[1];
  let t2: Int = ar.types[2];
  var ok = tar_entry_count(&ar) == 3;
  if t0 != 5 { ok = false; }
  if t1 != 50 { ok = false; }
  if t2 != 0 { ok = false; }
  let d0 = tar_entry_data(&data, &ar, 0);
  if !d0.is_ok { ok = false; } elif d0.value.len() != 0 { ok = false; }
  return assert(ok, "typeflag '5'->5, raw bytes kept, '0'/NUL->0");
}

// One-entry tar_build archive with an `n`-byte payload must be 512 header +
// 512-aligned payload + 1024 terminator, and must round-trip.
fn pad_round_trip(n: Int) -> Bool {
  var names = Vec[Str].new();
  names.push("pad.bin");
  var payloads = Vec[Vec[UInt8]].new();
  payloads.push(payload_of(n, 40));
  let r = tar_build(&names, &payloads);
  if !r.is_ok { return false; }
  let out = r.value;
  let want_len = 512 + ((n + 511) / 512) * 512 + 1024;
  if out.len() != want_len { return false; }
  let pr = tar_parse(&out);
  if !pr.is_ok { return false; }
  let ar = pr.value;
  if tar_entry_count(&ar) != 1 { return false; }
  if tar_entry_size(&ar, 0) != n { return false; }
  let pd = tar_entry_data(&out, &ar, 0);
  if !pd.is_ok { return false; }
  return bytes_equal(pd.value, payload_of(n, 40));
}

fn t9() -> TestResult {
  var ok = pad_round_trip(0);
  if !pad_round_trip(1) { ok = false; }
  if !pad_round_trip(511) { ok = false; }
  if !pad_round_trip(512) { ok = false; }
  if !pad_round_trip(513) { ok = false; }
  if !pad_round_trip(1024) { ok = false; }
  return assert(ok, "payloads 0/1/511/512/513/1024 pad and round-trip");
}

fn t10() -> TestResult {
  let base = entry(mk_header("term.bin", 420, 1, 0, 48, ""), payload_of(1, 50));
  let two = concat(base, terminators());
  let one = concat(base, zeros(512));
  let junk = concat(two, hb("6a756e6b"));
  let pr1 = tar_parse(&two);
  let pr2 = tar_parse(&one);
  let pr3 = tar_parse(&junk);
  var ok = pr1.is_ok;
  if pr2.is_ok {
    let a2 = pr2.value;
    if tar_entry_count(&a2) != 1 { ok = false; }
  } else {
    ok = false;
  }
  if pr3.is_ok {
    let a3b = pr3.value;
    if tar_entry_count(&a3b) != 1 { ok = false; }
  } else {
    ok = false;
  }
  if pr1.is_ok {
    let a1 = pr1.value;
    if tar_entry_count(&a1) != 1 { ok = false; }
  }
  return assert(ok, "two-zero-block terminator; trailing bytes ignored");
}

fn t11() -> TestResult {
  let no_term = concat(mk_header("eof.bin", 420, 3, 0, 48, ""), payload_of(3, 60));
  let partial_tail = concat(entry(mk_header("eof.bin", 420, 3, 0, 48, ""), payload_of(3, 61)), zeros(100));
  let half = concat(mk_header("eof2.bin", 420, 512, 0, 48, ""), payload_of(512, 62));
  let pr1 = tar_parse(&no_term);
  let pr2 = tar_parse(&partial_tail);
  let pr3 = tar_parse(&half);
  var ok = no_term.len() == 515;
  if pr1.is_ok {
    let a1 = pr1.value;
    if tar_entry_count(&a1) != 1 { ok = false; }
    if tar_entry_size(&a1, 0) != 3 { ok = false; }
    let pd = tar_entry_data(&no_term, &a1, 0);
    if !pd.is_ok { ok = false; } elif !bytes_equal(pd.value, payload_of(3, 60)) { ok = false; }
  } else {
    ok = false;
  }
  if pr2.is_ok {
    let a2 = pr2.value;
    if tar_entry_count(&a2) != 1 { ok = false; }
  } else {
    ok = false;
  }
  if pr3.is_ok {
    let a3 = pr3.value;
    if tar_entry_size(&a3, 0) != 512 { ok = false; }
    let pd3 = tar_entry_data(&half, &a3, 0);
    if !pd3.is_ok { ok = false; } elif pd3.value.len() != 512 { ok = false; }
  } else {
    ok = false;
  }
  return assert(ok, "EOF without terminator/padding is tolerated");
}

fn t12() -> TestResult {
  let first_entry = entry(mk_header("cut.bin", 420, 10, 0, 48, ""), payload_of(10, 70));
  let second_entry = entry(mk_header("two.bin", 420, 10, 0, 48, ""), payload_of(10, 71));
  let full = concat(first_entry, terminators());
  let both = concat(first_entry, second_entry);
  let head_cut = prefix(full, 300);
  let mid_cut = prefix(both, 1024 + 100);
  let short_data = concat(mk_header("short.bin", 420, 10, 0, 48, ""), payload_of(5, 72));
  var ok = err_archive_is(tar_parse(&head_cut), "tar: truncated header");
  if !err_archive_is(tar_parse(&mid_cut), "tar: truncated header") { ok = false; }
  if !err_archive_is(tar_parse(&short_data), "tar: truncated data") { ok = false; }
  if !tar_parse(&full).is_ok { ok = false; }
  return assert(ok, "partial headers and over-declared sizes are Err");
}

fn t13() -> TestResult {
  var name100 = zeros(0);
  var i = 0;
  while i < 100 {
    push_text(&mut name100, "n");
    i = i + 1;
  }
  let long_name = Str::from_utf8(name100);
  let short_name = Str::from_utf8(prefix(name100, 100));
  var names100 = Vec[Str].new();
  names100.push(long_name);
  var payloads = Vec[Vec[UInt8]].new();
  payloads.push(zeros(0));
  let r100 = tar_build(&names100, &payloads);
  var ok = r100.is_ok;
  if r100.is_ok {
    let built100 = r100.value;
    let pr = tar_parse(&built100);
    if !pr.is_ok {
      ok = false;
    } else {
      let ar = pr.value;
      if !name_is(&ar, 0, long_name) { ok = false; }
    }
  }
  var name101 = zeros(0);
  i = 0;
  while i < 101 {
    push_text(&mut name101, "n");
    i = i + 1;
  }
  var names101 = Vec[Str].new();
  names101.push(Str::from_utf8(name101));
  let r101 = tar_build(&names101, &payloads);
  if !err_bytes_is(r101, "tar: name too long") { ok = false; }
  var two = Vec[Str].new();
  two.push(short_name);
  two.push(short_name);
  if !err_bytes_is(tar_build(&two, &payloads), "tar: payload count mismatch") { ok = false; }
  var no_names = Vec[Str].new();
  if !err_bytes_is(tar_build(&no_names, &payloads), "tar: payload count mismatch") { ok = false; }
  var empty_named = Vec[Str].new();
  empty_named.push("");
  let r_empty = tar_build(&empty_named, &payloads);
  if !r_empty.is_ok {
    ok = false;
  } else {
    let built_empty = r_empty.value;
    let pr_empty = tar_parse(&built_empty);
    if !pr_empty.is_ok {
      ok = false;
    } else {
      let ar_empty = pr_empty.value;
      if tar_entry_count(&ar_empty) != 1 { ok = false; }
    }
  }
  return assert(ok, "100-byte names ok, 101 Err, count mismatch Err");
}

fn t14() -> TestResult {
  var names = Vec[Str].new();
  names.push("first.bin");
  names.push("second.dat");
  var payloads = Vec[Vec[UInt8]].new();
  payloads.push(zeros(0));
  payloads.push(payload_of(1000, 80));
  let r = tar_build(&names, &payloads);
  if !r.is_ok { return assert(false, "tar_build must succeed"); }
  let out = r.value;
  var ok = out.len() == 3072;
  let pr = tar_parse(&out);
  if !pr.is_ok { return assert(false, "round trip must parse"); }
  let ar = pr.value;
  if tar_entry_count(&ar) != 2 { ok = false; }
  if !name_is(&ar, 0, "first.bin") { ok = false; }
  if !name_is(&ar, 1, "second.dat") { ok = false; }
  if tar_entry_size(&ar, 0) != 0 { ok = false; }
  if tar_entry_size(&ar, 1) != 1000 { ok = false; }
  let d1 = tar_entry_data(&out, &ar, 1);
  if !d1.is_ok { ok = false; } elif !bytes_equal(d1.value, payload_of(1000, 80)) { ok = false; }
  if !err_bytes_is(tar_entry_data(&out, &ar, -1), "tar: entry out of range") { ok = false; }
  if !err_bytes_is(tar_entry_data(&out, &ar, 2), "tar: entry out of range") { ok = false; }
  return assert(ok, "two-file build/parse round-trip and data bounds");
}

fn t15() -> TestResult {
  var names = Vec[Str].new();
  var payloads = Vec[Vec[UInt8]].new();
  let r = tar_build(&names, &payloads);
  var ok = r.is_ok;
  if r.is_ok {
    let built = r.value;
    if built.len() != 1024 { ok = false; }
    var i = 0;
    while i < 1024 {
      if (built[i] as Int) != 0 { ok = false; }
      i = i + 1;
    }
    let pr = tar_parse(&built);
    if !pr.is_ok {
      ok = false;
    } else {
      let ar = pr.value;
      if tar_entry_count(&ar) != 0 { ok = false; }
    }
  }
  let empty = Vec[UInt8].new();
  let e = tar_parse(&empty);
  if !e.is_ok {
    ok = false;
  } else {
    let ae = e.value;
    if tar_entry_count(&ae) != 0 { ok = false; }
  }
  let block = zeros(512);
  let b = tar_parse(&block);
  if !b.is_ok {
    ok = false;
  } else {
    let ab = b.value;
    if tar_entry_count(&ab) != 0 { ok = false; }
  }
  let tail = zeros(100);
  let t = tar_parse(&tail);
  if !t.is_ok {
    ok = false;
  } else {
    let at = t.value;
    if tar_entry_count(&at) != 0 { ok = false; }
  }
  return assert(ok, "empty build/input/zero-block archives have no entries");
}

fn t16() -> TestResult {
  var data = entry(mk_header("oct.txt", 420, 5, 0, 48, ""), payload_of(5, 90));
  var spaces = hb("2020363434000000");
  data = set_range(data, 100, spaces);
  var nuldigits = hb("0000303030303030303035");
  data = set_range(data, 124, nuldigits);
  set_checksum(&mut data, 0);
  data = concat(data, terminators());
  let pr = tar_parse(&data);
  var ok = pr.is_ok;
  if pr.is_ok {
    let ar = pr.value;
    let mode: Int = ar.modes[0];
    let size: Int = ar.sizes[0];
    if mode != 420 { ok = false; }
    if size != 5 { ok = false; }
  }
  var bad_mode = set_byte(data, 100, 57);
  set_checksum(&mut bad_mode, 0);
  var bad_size = set_byte(data, 135, 122);
  set_checksum(&mut bad_size, 0);
  if !err_archive_is(tar_parse(&bad_mode), "tar: bad octal") { ok = false; }
  if !err_archive_is(tar_parse(&bad_size), "tar: bad octal") { ok = false; }
  return assert(ok, "octal fields accept leading spaces/NULs; bad digits Err");
}

fn t17() -> TestResult {
  var data = entry(mk_header("slice.bin", 420, 5, 0, 48, ""), payload_of(5, 100));
  data = concat(data, terminators());
  let pr = tar_parse(&data);
  if !pr.is_ok { return assert(false, "archive must parse"); }
  let ar = pr.value;
  let cut = prefix(data, 514);
  var ok = err_bytes_is(tar_entry_data(&cut, &ar, 0), "tar: truncated data");
  let full = tar_entry_data(&data, &ar, 0);
  if !full.is_ok { ok = false; } elif !bytes_equal(full.value, payload_of(5, 100)) { ok = false; }
  return assert(ok, "tar_entry_data reports a short source buffer");
}

fn t18() -> TestResult {
  var data = entry(mk_header("acc.bin", 420, 4, 0, 48, ""), payload_of(4, 110));
  data = concat(data, terminators());
  let pr = tar_parse(&data);
  if !pr.is_ok { return assert(false, "archive must parse"); }
  let ar = pr.value;
  var ok = tar_entry_count(&ar) == 1;
  if tar_entry_size(&ar, 0) != 4 { ok = false; }
  if !name_is(&ar, 0, "acc.bin") { ok = false; }
  if !name_is(&ar, -1, "") { ok = false; }
  if !name_is(&ar, 1, "") { ok = false; }
  if tar_entry_size(&ar, -1) != 0 { ok = false; }
  if tar_entry_size(&ar, 1) != 0 { ok = false; }
  return assert(ok, "accessors: out-of-range name \"\" and size 0");
}

fn t19() -> TestResult {
  var data = entry(mk_header("a.txt", 420, 1, 1, 48, ""), payload_of(1, 120));
  data = concat(data, entry(mk_header("d", 493, 0, 2, 53, "p/q"), zeros(0)));
  data = concat(data, entry(mk_header("z.txt", 420, 2, 3, 48, ""), payload_of(2, 121)));
  data = concat(data, terminators());
  let pr = tar_parse(&data);
  if !pr.is_ok { return assert(false, "three-entry archive must parse"); }
  let ar = pr.value;
  var ok = tar_entry_count(&ar) == 3;
  if !name_is(&ar, 0, "a.txt") { ok = false; }
  if !name_is(&ar, 1, "p/q/d") { ok = false; }
  if !name_is(&ar, 2, "z.txt") { ok = false; }
  let t1: Int = ar.types[1];
  let m1: Int = ar.modes[1];
  let s1: Int = ar.sizes[1];
  let t2: Int = ar.types[2];
  if t1 != 5 { ok = false; }
  if m1 != 493 { ok = false; }
  if s1 != 0 { ok = false; }
  if t2 != 0 { ok = false; }
  return assert(ok, "three mixed entries keep order, names and types");
}

fn t20() -> TestResult {
  var names = Vec[Str].new();
  names.push("r1");
  names.push("r2");
  var payloads = Vec[Vec[UInt8]].new();
  payloads.push(payload_of(1, 130));
  payloads.push(payload_of(513, 131));
  let r1 = tar_build(&names, &payloads);
  if !r1.is_ok { return assert(false, "first build must succeed"); }
  let first = r1.value;
  var ok = first.len() == 3584;
  let pr = tar_parse(&first);
  if !pr.is_ok { return assert(false, "built archive must parse"); }
  let ar = pr.value;
  var names2 = Vec[Str].new();
  names2.push(tar_entry_name(&ar, 0));
  names2.push(tar_entry_name(&ar, 1));
  var payloads2 = Vec[Vec[UInt8]].new();
  let d0 = tar_entry_data(&first, &ar, 0);
  let d1 = tar_entry_data(&first, &ar, 1);
  if !d0.is_ok { ok = false; } else { payloads2.push(d0.value); }
  if !d1.is_ok { ok = false; } else { payloads2.push(d1.value); }
  let r2 = tar_build(&names2, &payloads2);
  if !r2.is_ok { ok = false; } elif !bytes_equal(first, r2.value) { ok = false; }
  return assert(ok, "build -> parse -> build is byte-identical");
}

fn t21() -> TestResult {
  var data = entry(mk_header("one", 420, 1, 0, 48, ""), payload_of(1, 140));
  data = concat(data, entry(mk_header("two", 420, 512, 0, 48, ""), payload_of(512, 141)));
  data = concat(data, terminators());
  let pr = tar_parse(&data);
  if !pr.is_ok { return assert(false, "offset archive must parse"); }
  let ar = pr.value;
  let o0: Int = ar.data_offsets[0];
  let o1: Int = ar.data_offsets[1];
  var ok = o0 == 512;
  if o1 != 1536 { ok = false; }
  if tar_entry_size(&ar, 1) != 512 { ok = false; }
  return assert(ok, "data_offsets pin payload starts across 512-boundaries");
}

fn t22() -> TestResult {
  var names = Vec[Str].new();
  names.push("p1.bin");
  names.push("p2.bin");
  var payloads = Vec[Vec[UInt8]].new();
  payloads.push(payload_of(3, 150));
  payloads.push(payload_of(5, 151));
  let r = tar_build(&names, &payloads);
  if !r.is_ok { return assert(false, "tar_build must succeed"); }
  let out = r.value;
  var ok = out.len() == 3072;
  var i = 515;
  while i < 1024 {
    if (out[i] as Int) != 0 { ok = false; }
    i = i + 1;
  }
  let pr = tar_parse(&out);
  if !pr.is_ok { return assert(false, "padding archive must parse"); }
  let ar = pr.value;
  let o0: Int = ar.data_offsets[0];
  let o1: Int = ar.data_offsets[1];
  if o0 != 512 { ok = false; }
  if o1 != 1536 { ok = false; }
  let d1 = tar_entry_data(&out, &ar, 1);
  if !d1.is_ok { ok = false; } elif !bytes_equal(d1.value, payload_of(5, 151)) { ok = false; }
  return assert(ok, "zero padding between entries; headers at 0 and 1024");
}

fn main() -> Int {
  io.println("=== xiom.tar conformance tests ===");
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
    io.println("xiom.tar: all tests passed");
  } else {
    io.println("xiom.tar: tests failed");
  }
  return failed;
}
