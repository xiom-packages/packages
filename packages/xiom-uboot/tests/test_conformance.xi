// XIOM -- xiom.uboot conformance tests (16 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.uboot codec against the rules pinned
// in SPEC.md: the fixed 64-byte legacy header, the big-endian fields, the
// NUL-padded printable name, the partial id name tables with unknown
// pass-through, the raw CRC-32 fields with the explicit verification
// helpers, the strict full-image parse versus the header-only parse, the
// documented error catalog, FIT rejection and build/parse round trips.
//
// Fixtures are assembled byte by byte here (the gzip fixture's CRCs were
// computed with an independent table-driven script, not by this module), so
// the parser is exercised against bytes the test controls. Str comparisons
// go through xiom.string.compare's str_compare (BUG 17: `==` on Str values
// read from aggregates lowers to a pointer comparison); every Vec element
// read is bound to an explicitly typed local and every `&` argument is a
// local binding (never a field or call result).

module uboot_tests
use xiom.io; use xiom.test;
use xiom.uboot;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Byte helpers (independent of src/uboot.xi)
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

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// Bytes for a hex string (empty on malformed input; the test then fails on
// the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if r.is_ok {
    let b: Vec[UInt8] = r.value;
    return b;
  }
  return Vec[UInt8].new();
}

fn slice(v: Vec[UInt8], start: Int, count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < count && start + i < v.len() {
    out.push(v[start + i]);
    i = i + 1;
  }
  return out;
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

fn put_be32(v: Vec[UInt8], pos: Int, val: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(((val / 16777216) % 256) as UInt8);
    } elif i == pos + 1 {
      out.push(((val / 65536) % 256) as UInt8);
    } elif i == pos + 2 {
      out.push(((val / 256) % 256) as UInt8);
    } elif i == pos + 3 {
      out.push((val % 256) as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

fn put_bytes(v: Vec[UInt8], pos: Int, src: Vec[UInt8]) -> Vec[UInt8] {
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

fn concat(a: Vec[UInt8], b: Vec[UInt8]) -> Vec[UInt8] {
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
//  Fixture and header helpers
// --------------------------------------------------

// The pinned gzip fixture: legacy magic, hcrc 0xAB4F488D, timestamp
// 1234567890, size 16, load/entry 0x80008000, dcrc 0xCECEE288, os 5 (linux),
// arch 2 (arm), type 2 (kernel), comp 1 (gzip), name "linux arm", then the
// 16 payload bytes 00..0F. Both CRCs were computed by an independent
// table-driven script whose check value for "123456789" is 3421780262.
fn fixture() -> Vec[UInt8] {
  return hb("27051956ab4f488d499602d2000000108000800080008000cecee288050202016c696e75782061726d0000000000000000000000000000000000000000000000000102030405060708090a0b0c0d0e0f");
}

// A header literal with the canonical magic and raw CRCs zero; `size`,
// `hcrc` and `dcrc` are supplied by the builder or by the test when needed.
fn mk_header(t: Int, load: Int, ep: Int, os: Int, arch: Int, image_type: Int, comp: Int, name: Str) -> UbootHeader {
  let h = UbootHeader{
    magic: 654645590;
    hcrc: 0;
    time: t;
    size: 0;
    load: load;
    ep: ep;
    dcrc: 0;
    os: os;
    arch: arch;
    image_type: image_type;
    comp: comp;
    name: name;
  };
  return h;
}

fn err_header_is(r: Result[UbootHeader, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = fixture();
  let r = uboot_parse(&data);
  if !r.is_ok { return assert(false, "gzip fixture must parse"); }
  let h: UbootHeader = r.value;
  var ok = data.len() == 80;
  if uboot_magic(&h) != 654645590 { ok = false; }
  if uboot_header_crc(&h) != 2874099853 { ok = false; }
  if uboot_timestamp(&h) != 1234567890 { ok = false; }
  if uboot_data_size(&h) != 16 { ok = false; }
  if uboot_load_addr(&h) != 2147516416 { ok = false; }
  if uboot_entry_point(&h) != 2147516416 { ok = false; }
  if uboot_data_crc(&h) != 3469664904 { ok = false; }
  if uboot_os(&h) != 5 { ok = false; }
  if !streq(uboot_os_name(&h), "linux") { ok = false; }
  if uboot_arch(&h) != 2 { ok = false; }
  if !streq(uboot_arch_name(&h), "arm") { ok = false; }
  if uboot_image_type(&h) != 2 { ok = false; }
  if !streq(uboot_image_type_name(&h), "kernel") { ok = false; }
  if uboot_compression(&h) != 1 { ok = false; }
  if !streq(uboot_compression_name(&h), "gzip") { ok = false; }
  if !streq(uboot_name(&h), "linux arm") { ok = false; }
  if uboot_header_size() != 64 { ok = false; }
  if uboot_data_offset() != 64 { ok = false; }
  if uboot_data_end(&h) != 80 { ok = false; }
  if !uboot_header_crc_ok(&data, &h) { ok = false; }
  if !uboot_data_crc_ok(&data, &h) { ok = false; }
  return assert(ok, "gzip fixture: raw fields, id names and CRC helpers");
}

fn t2() -> TestResult {
  let data = fixture();
  let r = uboot_parse(&data);
  if !r.is_ok { return assert(false, "fixture must parse"); }
  let h: UbootHeader = r.value;
  let payload = slice(data, 64, 16);
  if payload.len() != 16 { return assert(false, "fixture payload must be 16 bytes"); }
  let br = uboot_build(&h, &payload);
  if !br.is_ok { return assert(false, "rebuild must succeed"); }
  let built: Vec[UInt8] = br.value;
  var ok = bytes_equal(built, data);
  if built.len() != 80 { ok = false; }
  return assert(ok, "rebuilding the parsed fixture is byte-identical");
}

fn t3() -> TestResult {
  let data = fixture();
  let short = slice(data, 0, 63);
  var ok = err_header_is(uboot_parse(&short), "uboot: truncated header");
  if !err_header_is(uboot_parse_header(&short), "uboot: truncated header") { ok = false; }
  let badmagic = set_byte(data, 0, 40);
  if !err_header_is(uboot_parse(&badmagic), "uboot: bad magic") { ok = false; }
  if !err_header_is(uboot_parse_header(&badmagic), "uboot: bad magic") { ok = false; }
  let fit = put_bytes(data, 0, hb("d00dfeed"));
  if !err_header_is(uboot_parse(&fit), "uboot: FIT image not supported") { ok = false; }
  if !err_header_is(uboot_parse_header(&fit), "uboot: FIT image not supported") { ok = false; }
  var none = Vec[UInt8].new();
  if !err_header_is(uboot_parse(&none), "uboot: truncated header") { ok = false; }
  if !err_header_is(uboot_parse_header(&none), "uboot: truncated header") { ok = false; }
  return assert(ok, "short buffer, bad magic and FIT prefixes are rejected");
}

fn t4() -> TestResult {
  let data = fixture();
  let big = put_be32(data, 12, 17);
  var ok = err_header_is(uboot_parse(&big), "uboot: truncated data");
  let hr = uboot_parse_header(&big);
  if !hr.is_ok { ok = false; } else {
    let h: UbootHeader = hr.value;
    if uboot_data_size(&h) != 17 { ok = false; }
  }
  let header_only = slice(data, 0, 64);
  if !err_header_is(uboot_parse(&header_only), "uboot: truncated data") { ok = false; }
  let hr2 = uboot_parse_header(&header_only);
  if !hr2.is_ok { ok = false; } else {
    let h2: UbootHeader = hr2.value;
    if uboot_data_size(&h2) != 16 { ok = false; }
    if uboot_data_crc_ok(&header_only, &h2) { ok = false; }
  }
  let huge = put_be32(data, 12, 4294967295);
  if !err_header_is(uboot_parse(&huge), "uboot: truncated data") { ok = false; }
  let tail = hb("ffff");
  let padded = concat(data, tail);
  let pr = uboot_parse(&padded);
  var ok2 = pr.is_ok;
  if ok2 {
    let hp: UbootHeader = pr.value;
    if uboot_data_size(&hp) != 16 { ok2 = false; }
    if !uboot_data_crc_ok(&padded, &hp) { ok2 = false; }
  }
  if !ok2 { ok = false; }
  return assert(ok, "uboot_parse requires the data span; uboot_parse_header does not");
}

fn t5() -> TestResult {
  let data = fixture();
  var ok = true;
  let ctl = set_byte(data, 32, 31);
  if !err_header_is(uboot_parse(&ctl), "uboot: bad image name") { ok = false; }
  let del = set_byte(data, 33, 127);
  if !err_header_is(uboot_parse_header(&del), "uboot: bad image name") { ok = false; }
  let high = set_byte(data, 50, 200);
  let hr = uboot_parse_header(&high);
  if !hr.is_ok { ok = false; } else {
    let h: UbootHeader = hr.value;
    if !streq(uboot_name(&h), "linux arm") { ok = false; }
  }
  let name32 = "abcdefghijklmnopqrstuvwxyz012345";
  let h0 = mk_header(1, 0, 0, 5, 2, 2, 0, name32);
  var empty = Vec[UInt8].new();
  let br = uboot_build(&h0, &empty);
  if !br.is_ok { ok = false; } else {
    let b: Vec[UInt8] = br.value;
    if b.len() != 64 { ok = false; }
    let last: Int = (b[63] as Int) & 0xFF;
    if last != 53 { ok = false; }
    let pr = uboot_parse_header(&b);
    if !pr.is_ok { ok = false; } else {
      let hp: UbootHeader = pr.value;
      if !streq(uboot_name(&hp), name32) { ok = false; }
      if uboot_name(&hp).len() != 32 { ok = false; }
    }
  }
  return assert(ok, "name stops at NUL, rejects control/DEL, accepts a full 32-char field");
}

fn t6() -> TestResult {
  let h = mk_header(1, 0, 0, 6, 22, 14, 9, "ids");
  var empty = Vec[UInt8].new();
  let br = uboot_build(&h, &empty);
  if !br.is_ok { return assert(false, "build must succeed"); }
  let b: Vec[UInt8] = br.value;
  let pr = uboot_parse_header(&b);
  if !pr.is_ok { return assert(false, "parse must succeed"); }
  let hp: UbootHeader = pr.value;
  var ok = uboot_os(&hp) == 6;
  if !streq(uboot_os_name(&hp), "vxworks") { ok = false; }
  if uboot_arch(&hp) != 22 { ok = false; }
  if !streq(uboot_arch_name(&hp), "aarch64") { ok = false; }
  if uboot_image_type(&hp) != 14 { ok = false; }
  if !streq(uboot_image_type_name(&hp), "kernel-noload") { ok = false; }
  if uboot_compression(&hp) != 9 { ok = false; }
  if !streq(uboot_compression_name(&hp), "zstd") { ok = false; }
  let hu = mk_header(1, 0, 0, 200, 99, 77, 4, "unknown ids");
  let bu = uboot_build(&hu, &empty);
  if !bu.is_ok { ok = false; } else {
    let buv: Vec[UInt8] = bu.value;
    let pu = uboot_parse_header(&buv);
    if !pu.is_ok { ok = false; } else {
      let hpu: UbootHeader = pu.value;
      if uboot_os(&hpu) != 200 { ok = false; }
      if !streq(uboot_os_name(&hpu), "unknown") { ok = false; }
      if uboot_arch(&hpu) != 99 { ok = false; }
      if !streq(uboot_arch_name(&hpu), "unknown") { ok = false; }
      if uboot_image_type(&hpu) != 77 { ok = false; }
      if !streq(uboot_image_type_name(&hpu), "unknown") { ok = false; }
      if uboot_compression(&hpu) != 4 { ok = false; }
      if !streq(uboot_compression_name(&hpu), "unknown") { ok = false; }
    }
  }
  return assert(ok, "known ids map to names; unknown ids pass through as unknown");
}

fn t7() -> TestResult {
  let s = bytes_of("123456789");
  var ok = uboot_crc32(&s) == 3421780262;
  var empty = Vec[UInt8].new();
  if uboot_crc32(&empty) != 0 { ok = false; }
  if uboot_crc32_range(&s, -1, 9) != -1 { ok = false; }
  if uboot_crc32_range(&s, 0, -1) != -1 { ok = false; }
  if uboot_crc32_range(&s, 10, 0) != -1 { ok = false; }
  if uboot_crc32_range(&s, 0, 10) != -1 { ok = false; }
  if uboot_crc32_range(&s, 9, 0) != 0 { ok = false; }
  let data = fixture();
  let r = uboot_parse(&data);
  if !r.is_ok { ok = false; } else {
    let h: UbootHeader = r.value;
    if uboot_data_crc(&h) != 3469664904 { ok = false; }
    if uboot_data_crc(&h) != uboot_crc32_range(&data, 64, 16) { ok = false; }
  }
  return assert(ok, "check value 3421780262, empty 0, range guards and fixture data CRC");
}

fn t8() -> TestResult {
  let data = fixture();
  let r = uboot_parse(&data);
  if !r.is_ok { return assert(false, "fixture must parse"); }
  let h: UbootHeader = r.value;
  var ok = uboot_header_crc_ok(&data, &h);
  if uboot_header_crc(&h) != 2874099853 { ok = false; }
  let zeroed = fill_zero(data, 4, 4);
  if uboot_crc32_range(&zeroed, 0, 64) != uboot_header_crc(&h) { ok = false; }
  let mutated = put_be32(data, 8, 1234567891);
  let mr = uboot_parse(&mutated);
  if !mr.is_ok { ok = false; } else {
    let hm: UbootHeader = mr.value;
    if uboot_header_crc_ok(&mutated, &hm) { ok = false; }
    if !uboot_data_crc_ok(&mutated, &hm) { ok = false; }
    if uboot_timestamp(&hm) != 1234567891 { ok = false; }
  }
  let short = slice(data, 0, 63);
  if uboot_header_crc_ok(&short, &h) { ok = false; }
  return assert(ok, "header CRC zeroes its own field; mismatch is reported only by the helper");
}

fn t9() -> TestResult {
  let data = fixture();
  let r = uboot_parse(&data);
  if !r.is_ok { return assert(false, "fixture must parse"); }
  let h: UbootHeader = r.value;
  var ok = uboot_data_crc_ok(&data, &h);
  let hdr = slice(data, 0, 64);
  if uboot_data_crc_ok(&hdr, &h) { ok = false; }
  let flipped = set_byte(data, 70, 255);
  let fr = uboot_parse(&flipped);
  if !fr.is_ok { ok = false; } else {
    let hf: UbootHeader = fr.value;
    if uboot_data_crc_ok(&flipped, &hf) { ok = false; }
    if !uboot_header_crc_ok(&flipped, &hf) { ok = false; }
  }
  let dr = uboot_data_bytes(&data, &h);
  if !dr.is_ok { ok = false; } else {
    let got: Vec[UInt8] = dr.value;
    let want = slice(data, 64, 16);
    if !bytes_equal(got, want) { ok = false; }
  }
  let er = uboot_data_bytes(&hdr, &h);
  if er.is_ok { ok = false; }
  return assert(ok, "data CRC covers the payload span; data_bytes copies it or fails");
}

fn t10() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = true;
  let a = mk_header(-1, 0, 0, 5, 2, 2, 1, "x");
  if !err_bytes_is(uboot_build(&a, &empty), "uboot: bad timestamp") { ok = false; }
  let b = mk_header(4294967296, 0, 0, 5, 2, 2, 1, "x");
  if !err_bytes_is(uboot_build(&b, &empty), "uboot: bad timestamp") { ok = false; }
  let c = mk_header(1, -1, 0, 5, 2, 2, 1, "x");
  if !err_bytes_is(uboot_build(&c, &empty), "uboot: bad address") { ok = false; }
  let d = mk_header(1, 0, 4294967296, 5, 2, 2, 1, "x");
  if !err_bytes_is(uboot_build(&d, &empty), "uboot: bad address") { ok = false; }
  let e = mk_header(1, 0, 0, -1, 2, 2, 1, "x");
  if !err_bytes_is(uboot_build(&e, &empty), "uboot: bad id") { ok = false; }
  let f = mk_header(1, 0, 0, 5, 2, 2, 256, "x");
  if !err_bytes_is(uboot_build(&f, &empty), "uboot: bad id") { ok = false; }
  let longname = "abcdefghijklmnopqrstuvwxyz0123456";
  let g = mk_header(1, 0, 0, 5, 2, 2, 1, longname);
  if !err_bytes_is(uboot_build(&g, &empty), "uboot: bad image name") { ok = false; }
  let ctlname = "bad\u{001F}name";
  let i = mk_header(1, 0, 0, 5, 2, 2, 1, ctlname);
  if !err_bytes_is(uboot_build(&i, &empty), "uboot: bad image name") { ok = false; }
  return assert(ok, "builder rejects bad timestamp/address/id/name");
}

fn t11() -> TestResult {
  let h = UbootHeader{
    magic: 0;
    hcrc: 1;
    time: 7;
    size: 999;
    load: 16;
    ep: 32;
    dcrc: 2;
    os: 0;
    arch: 3;
    image_type: 4;
    comp: 0;
    name: "canon";
  };
  let payload = hb("000102030405060708090a0b0c0d0e0f");
  let br = uboot_build(&h, &payload);
  if !br.is_ok { return assert(false, "build must succeed"); }
  let b: Vec[UInt8] = br.value;
  var ok = b.len() == 80;
  let pr = uboot_parse(&b);
  if !pr.is_ok { ok = false; } else {
    let hp: UbootHeader = pr.value;
    if uboot_magic(&hp) != 654645590 { ok = false; }
    if uboot_data_size(&hp) != 16 { ok = false; }
    if uboot_timestamp(&hp) != 7 { ok = false; }
    if uboot_header_crc(&hp) == 1 { ok = false; }
    if uboot_data_crc(&hp) == 2 { ok = false; }
    if !uboot_header_crc_ok(&b, &hp) { ok = false; }
    if !uboot_data_crc_ok(&b, &hp) { ok = false; }
  }
  var empty = Vec[UInt8].new();
  let er = uboot_build(&h, &empty);
  if !er.is_ok { ok = false; } else {
    let eb: Vec[UInt8] = er.value;
    if eb.len() != 64 { ok = false; }
    let ep = uboot_parse(&eb);
    if !ep.is_ok { ok = false; } else {
      let he: UbootHeader = ep.value;
      if uboot_data_size(&he) != 0 { ok = false; }
      if uboot_data_crc(&he) != 0 { ok = false; }
      if !uboot_data_crc_ok(&eb, &he) { ok = false; }
    }
  }
  return assert(ok, "build derives magic/size/CRCs and ignores the input header's");
}

fn t12() -> TestResult {
  var payload = Vec[UInt8].new();
  var i = 0;
  while i < 300 {
    payload.push((i % 256) as UInt8);
    i = i + 1;
  }
  let h = mk_header(1700000000, 3221225472, 3221225473, 5, 2, 3, 0, "ramdisk payload");
  let br = uboot_build(&h, &payload);
  if !br.is_ok { return assert(false, "build must succeed"); }
  let b: Vec[UInt8] = br.value;
  var ok = b.len() == 364;
  let pr = uboot_parse(&b);
  if !pr.is_ok { ok = false; } else {
    let hp: UbootHeader = pr.value;
    if uboot_data_size(&hp) != 300 { ok = false; }
    if uboot_load_addr(&hp) != 3221225472 { ok = false; }
    if uboot_entry_point(&hp) != 3221225473 { ok = false; }
    if !uboot_data_crc_ok(&b, &hp) { ok = false; }
    let dr = uboot_data_bytes(&b, &hp);
    if !dr.is_ok { ok = false; } else {
      let got: Vec[UInt8] = dr.value;
      if !bytes_equal(got, payload) { ok = false; }
      if got.len() != 300 { ok = false; }
    }
    let br2 = uboot_build(&hp, &payload);
    if !br2.is_ok { ok = false; } else {
      let b2: Vec[UInt8] = br2.value;
      if !bytes_equal(b2, b) { ok = false; }
    }
  }
  return assert(ok, "300-byte payload round-trips with 0xC0000000-range addresses");
}

fn t13() -> TestResult {
  let data = fixture();
  let r = uboot_parse(&data);
  if !r.is_ok { return assert(false, "fixture must parse"); }
  let h: UbootHeader = r.value;
  var ok = uboot_header_size() == 64;
  if uboot_data_offset() != 64 { ok = false; }
  if uboot_data_end(&h) != 80 { ok = false; }
  let big = UbootHeader{
    magic: 654645590;
    hcrc: 0;
    time: 0;
    size: 1000000;
    load: 0;
    ep: 0;
    dcrc: 0;
    os: 5;
    arch: 2;
    image_type: 2;
    comp: 0;
    name: "big";
  };
  if uboot_data_end(&big) != 1000064 { ok = false; }
  let hdr = slice(data, 0, 64);
  let dr = uboot_data_bytes(&hdr, &big);
  if dr.is_ok { ok = false; }
  if uboot_data_crc_ok(&hdr, &big) { ok = false; }
  return assert(ok, "data span is 64 + size and is bounds-checked");
}

fn t14() -> TestResult {
  var os_ids = Vec[Int].new();
  os_ids.push(0);
  os_ids.push(1);
  os_ids.push(3);
  os_ids.push(5);
  os_ids.push(6);
  var os_names = Vec[Str].new();
  os_names.push("invalid");
  os_names.push("openbsd");
  os_names.push("freebsd");
  os_names.push("linux");
  os_names.push("vxworks");
  var arch_ids = Vec[Int].new();
  arch_ids.push(2);
  arch_ids.push(3);
  arch_ids.push(5);
  arch_ids.push(6);
  arch_ids.push(7);
  arch_ids.push(22);
  var arch_names = Vec[Str].new();
  arch_names.push("arm");
  arch_names.push("i386");
  arch_names.push("mips");
  arch_names.push("mips64");
  arch_names.push("ppc");
  arch_names.push("aarch64");
  var type_ids = Vec[Int].new();
  type_ids.push(1);
  type_ids.push(2);
  type_ids.push(3);
  type_ids.push(4);
  type_ids.push(5);
  type_ids.push(6);
  type_ids.push(8);
  type_ids.push(14);
  var type_names = Vec[Str].new();
  type_names.push("standalone");
  type_names.push("kernel");
  type_names.push("ramdisk");
  type_names.push("multi");
  type_names.push("firmware");
  type_names.push("script");
  type_names.push("filesystem");
  type_names.push("kernel-noload");
  var comp_ids = Vec[Int].new();
  comp_ids.push(0);
  comp_ids.push(1);
  comp_ids.push(2);
  comp_ids.push(3);
  comp_ids.push(5);
  comp_ids.push(6);
  comp_ids.push(9);
  var comp_names = Vec[Str].new();
  comp_names.push("none");
  comp_names.push("gzip");
  comp_names.push("bzip2");
  comp_names.push("lzma");
  comp_names.push("lzo");
  comp_names.push("lz4");
  comp_names.push("zstd");
  var ok = os_ids.len() == os_names.len();
  if arch_ids.len() != arch_names.len() { ok = false; }
  if type_ids.len() != type_names.len() { ok = false; }
  if comp_ids.len() != comp_names.len() { ok = false; }
  var i = 0;
  while i < os_ids.len() {
    let id: Int = os_ids[i];
    let nm: Str = os_names[i];
    let h = mk_header(0, 0, 0, id, 2, 2, 0, "");
    if !streq(uboot_os_name(&h), nm) { ok = false; }
    i = i + 1;
  }
  i = 0;
  while i < arch_ids.len() {
    let id: Int = arch_ids[i];
    let nm: Str = arch_names[i];
    let h = mk_header(0, 0, 0, 5, id, 2, 0, "");
    if !streq(uboot_arch_name(&h), nm) { ok = false; }
    i = i + 1;
  }
  i = 0;
  while i < type_ids.len() {
    let id: Int = type_ids[i];
    let nm: Str = type_names[i];
    let h = mk_header(0, 0, 0, 5, 2, id, 0, "");
    if !streq(uboot_image_type_name(&h), nm) { ok = false; }
    i = i + 1;
  }
  i = 0;
  while i < comp_ids.len() {
    let id: Int = comp_ids[i];
    let nm: Str = comp_names[i];
    let h = mk_header(0, 0, 0, 5, 2, 2, id, "");
    if !streq(uboot_compression_name(&h), nm) { ok = false; }
    i = i + 1;
  }
  let h2 = mk_header(0, 0, 0, 2, 4, 7, 4, "");
  if !streq(uboot_os_name(&h2), "unknown") { ok = false; }
  if !streq(uboot_arch_name(&h2), "unknown") { ok = false; }
  if !streq(uboot_image_type_name(&h2), "unknown") { ok = false; }
  if !streq(uboot_compression_name(&h2), "unknown") { ok = false; }
  return assert(ok, "all documented ids map to their names and neighbours are unknown");
}

fn t15() -> TestResult {
  let data = fixture();
  var ok = !uboot_is_fit(&data);
  let fit = hb("d00dfeed");
  if !uboot_is_fit(&fit) { ok = false; }
  let tiny = hb("d00dfe");
  if uboot_is_fit(&tiny) { ok = false; }
  var none = Vec[UInt8].new();
  if uboot_is_fit(&none) { ok = false; }
  let fit64 = put_bytes(data, 0, hb("d00dfeed"));
  if !uboot_is_fit(&fit64) { ok = false; }
  if !err_header_is(uboot_parse(&fit64), "uboot: FIT image not supported") { ok = false; }
  if !err_header_is(uboot_parse_header(&fit64), "uboot: FIT image not supported") { ok = false; }
  return assert(ok, "FIT magic is detected and rejected; d00dfeed is not parsed as legacy");
}

fn t16() -> TestResult {
  let h = mk_header(1, 0, 0, 5, 2, 2, 0, "AB");
  var empty = Vec[UInt8].new();
  let br = uboot_build(&h, &empty);
  if !br.is_ok { return assert(false, "build must succeed"); }
  let b: Vec[UInt8] = br.value;
  var ok = b.len() == 64;
  let b32: Int = (b[32] as Int) & 0xFF;
  let b33: Int = (b[33] as Int) & 0xFF;
  if b32 != 65 { ok = false; }
  if b33 != 66 { ok = false; }
  var k = 34;
  while k < 64 {
    let z: Int = (b[k] as Int) & 0xFF;
    if z != 0 { ok = false; }
    k = k + 1;
  }
  let pr = uboot_parse_header(&b);
  if !pr.is_ok { ok = false; } else {
    let hp: UbootHeader = pr.value;
    if !streq(uboot_name(&hp), "AB") { ok = false; }
  }
  let he = mk_header(1, 0, 0, 5, 2, 2, 0, "");
  let er = uboot_build(&he, &empty);
  if !er.is_ok { ok = false; } else {
    let eb: Vec[UInt8] = er.value;
    var k2 = 32;
    while k2 < 64 {
      let z2: Int = (eb[k2] as Int) & 0xFF;
      if z2 != 0 { ok = false; }
      k2 = k2 + 1;
    }
  }
  return assert(ok, "builder NUL-pads the name field and accepts an empty name");
}

fn main() -> Int {
  io.println("=== xiom.uboot conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.uboot: all tests passed");
  } else {
    io.println("xiom.uboot: tests failed");
  }
  return failed;
}
