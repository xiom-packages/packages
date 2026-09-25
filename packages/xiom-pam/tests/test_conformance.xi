// XIOM -- xiom.pam conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.pam module against Netpbm PAM (P7).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module pam_tests
use xiom.io; use xiom.test; use xiom.pam;
use xiom.string; use xiom.string.compare; use xiom.string.builder;

// All Str equality goes through str_compare: `==` on Str lowered from a
// Vec[Str] element is a pointer comparison in v0.61.3, so comparisons are
// routed through streq and the typed Vec reads below.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ASCII bytes of a literal, used to hand-build inputs.
fn bytes_of(s: Str) -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while (i < n) {
    let b: UInt8 = string.byte_at(s, i);
    v.push(b);
    i = i + 1;
  }
  return v;
}

// Byte-wise equality of a built vector against a literal.
fn vec_is_str(data: &Vec[UInt8], want: Str) -> Bool {
  if (data.len() != want.len()) { return false; }
  var i = 0;
  while (i < data.len()) {
    let b: UInt8 = data[i];
    let c: UInt8 = string.byte_at(want, i);
    if (b != c) { return false; }
    i = i + 1;
  }
  return true;
}

// Byte-wise equality of two vectors (0..255 widened).
fn vec_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if (a.len() != b.len()) { return false; }
  var i = 0;
  while (i < a.len()) {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if (x != y) { return false; }
    i = i + 1;
  }
  return true;
}

// True when `data` starts with the literal `want`.
fn bytes_prefix_is(data: &Vec[UInt8], want: Str) -> Bool {
  let n = want.len();
  if (data.len() < n) { return false; }
  var i = 0;
  while (i < n) {
    let b: UInt8 = data[i];
    let c: UInt8 = string.byte_at(want, i);
    if (b != c) { return false; }
    i = i + 1;
  }
  return true;
}

// True when data[start, start + want.len()) equals `want`.
fn span_eq(data: &Vec[UInt8], start: Int, want: &Vec[UInt8]) -> Bool {
  if (start < 0) { return false; }
  if (start + want.len() > data.len()) { return false; }
  var i = 0;
  while (i < want.len()) {
    let a: UInt8 = data[start + i];
    let b: UInt8 = want[i];
    if (a != b) { return false; }
    i = i + 1;
  }
  return true;
}

fn byte_is(data: &Vec[UInt8], i: Int, want: Int) -> Bool {
  let b: Int = (data[i] as Int) & 0xFF;
  return b == want;
}

// Bytes 1..12, used as the raster of a 2x2x3 8-bit image.
fn raster12() -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  var i = 0;
  while (i < 12) {
    v.push((i + 1) as UInt8);
    i = i + 1;
  }
  return v;
}

// Build a Str from raw bytes (used for malformed tuple type values).
fn str_of_bytes(v: &Vec[UInt8]) -> Str {
  let sb = Vec[UInt8].new();
  var i = 0;
  while (i < v.len()) {
    let b: UInt8 = v[i];
    sb.push(b);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

fn ok_bytes(r: Result[Vec[UInt8], Str]) -> Vec[UInt8] {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return Vec[UInt8].new(); },
  }
}

fn bad_bytes(r: Result[Vec[UInt8], Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn bytes_err_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_img(r: Result[PamImage, Str]) -> PamImage {
  match r {
    Ok(v) => { return v; },
    Err(e) => {
      let ts = Vec[Str].new();
      return PamImage{ width: 0; height: 0; depth: 0; maxval: 0; bytes_per_sample: 0; data_offset: 0; raster_len: 0; tupltypes: ts; };
    },
  }
}

fn bad_img(r: Result[PamImage, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn img_err_is(r: Result[PamImage, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

// pam_tupltype result equals a literal (typed local bind, then str_compare).
fn tuple_is(img: &PamImage, index: Int, want: Str) -> Bool {
  let got: Str = pam_tupltype(img, index);
  return streq(got, want);
}

// The raster span of `img` in `data` copies out to exactly `want`.
fn raster_span_is(data: &Vec[UInt8], img: &PamImage, want: &Vec[UInt8]) -> Bool {
  match pam_raster_copy(data, img) {
    Ok(v) => { return vec_eq(v, want); },
    Err(e) => { return false; },
  }
}

fn t1() -> TestResult {
  let raster = raster12();
  let ts = Vec[Str].new();
  ts.push("RGB");
  let built = pam_build(2, 2, 3, 255, &ts, &raster);
  match built {
    Ok(data) => {
      let hdr = "P7\nWIDTH 2\nHEIGHT 2\nDEPTH 3\nMAXVAL 255\nTUPLTYPE RGB\nENDHDR\n";
      if (!bytes_prefix_is(data, hdr)) { return assert(false, "canonical 2x2x3 header bytes"); }
      if (data.len() != hdr.len() + 12) { return assert(false, "2x2x3 8-bit is header + 12 bytes"); }
      if (!span_eq(data, hdr.len(), &raster)) { return assert(false, "raster copied verbatim"); }
      let img = ok_img(pam_parse_header(data));
      if (pam_width(&img) != 2) { return assert(false, "width 2"); }
      if (pam_height(&img) != 2) { return assert(false, "height 2"); }
      if (pam_depth(&img) != 3) { return assert(false, "depth 3"); }
      if (pam_maxval(&img) != 255) { return assert(false, "maxval 255"); }
      if (img.bytes_per_sample != 1) { return assert(false, "bytes per sample 1"); }
      if (pam_raster_offset(&img) != hdr.len()) { return assert(false, "raster offset pins the header length"); }
      if (pam_raster_len(&img) != 12) { return assert(false, "raster length 12"); }
      if (pam_raster_offset(&img) + pam_raster_len(&img) != data.len()) { return assert(false, "span covers the whole buffer"); }
      if (pam_tupltype_count(&img) != 1) { return assert(false, "one TUPLTYPE line"); }
      if (!tuple_is(&img, 0, "RGB")) { return assert(false, "TUPLTYPE value RGB"); }
      let joined: Str = pam_tuple_type(&img);
      if (!streq(joined, "RGB")) { return assert(false, "joined tuple type RGB"); }
      if (!raster_span_is(data, &img, &raster)) { return assert(false, "span copy equals the source raster"); }
      return assert(true, "built 2x2x3 RGB PAM parses with an exact raster span");
    },
    Err(e) => { return assert(false, "canonical build must succeed"); },
  }
}

fn t2() -> TestResult {
  let hdr = "P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n";
  let data = bytes_of(hdr);
  data.push(127 as UInt8);
  let img = ok_img(pam_parse_header(data));
  if (pam_width(&img) != 1) { return assert(false, "minimal width 1"); }
  if (pam_height(&img) != 1) { return assert(false, "minimal height 1"); }
  if (pam_depth(&img) != 1) { return assert(false, "minimal depth 1"); }
  if (pam_maxval(&img) != 255) { return assert(false, "minimal maxval 255"); }
  if (pam_raster_offset(&img) != hdr.len()) { return assert(false, "minimal offset is the header length"); }
  if (pam_raster_len(&img) != 1) { return assert(false, "minimal raster length 1"); }
  if (pam_tupltype_count(&img) != 0) { return assert(false, "no TUPLTYPE lines"); }
  if (!tuple_is(&img, 0, "")) { return assert(false, "tupltype 0 sentinel is empty"); }
  if (!tuple_is(&img, -1, "")) { return assert(false, "tupltype -1 sentinel is empty"); }
  let joined: Str = pam_tuple_type(&img);
  if (!streq(joined, "")) { return assert(false, "no TUPLTYPE joins to the empty string"); }
  let raster = Vec[UInt8].new();
  raster.push(127 as UInt8);
  let ts = Vec[Str].new();
  let built = ok_bytes(pam_build(1, 1, 1, 255, &ts, &raster));
  if (built.len() != hdr.len() + 1) { return assert(false, "tuple-free build emits no TUPLTYPE line"); }
  if (!bytes_prefix_is(built, hdr)) { return assert(false, "tuple-free build canonical header"); }
  if (!byte_is(built, hdr.len(), 127)) { return assert(false, "tuple-free build raster byte"); }
  let back = ok_img(pam_parse_header(built));
  if (pam_raster_len(&back) != 1) { return assert(false, "tuple-free build reparses"); }
  return assert(true, "minimal header without TUPLTYPE parses and rebuilds exactly");
}

fn t3() -> TestResult {
  let raw = "P7\n# pam comment\n\nWIDTH 1\n   # indented comment\nHEIGHT 1\nDEPTH 1\n# c\nMAXVAL 255\nENDHDR\n";
  let data = bytes_of(raw);
  data.push(7 as UInt8);
  let img = ok_img(pam_parse_header(data));
  if (pam_raster_offset(&img) != raw.len()) { return assert(false, "comments and blank lines are skipped"); }
  if (pam_width(&img) != 1) { return assert(false, "commented width 1"); }
  if (pam_raster_len(&img) != 1) { return assert(false, "commented raster length 1"); }
  if (!byte_is(data, pam_raster_offset(&img), 7)) { return assert(false, "raster follows the comment header"); }
  let crlf = "P7\r\nWIDTH 1\r\nHEIGHT 1\r\nDEPTH 1\r\nMAXVAL 255\r\nENDHDR\r\n";
  let d2 = bytes_of(crlf);
  d2.push(9 as UInt8);
  let img2 = ok_img(pam_parse_header(d2));
  if (pam_raster_offset(&img2) != crlf.len()) { return assert(false, "CRLF header offset"); }
  if (!byte_is(d2, pam_raster_offset(&img2), 9)) { return assert(false, "CRLF raster byte"); }
  return assert(true, "comments, blank lines and CRLF line endings are handled");
}

fn t4() -> TestResult {
  let hdr = "P7\nWIDTH 1\nHEIGHT 1\nDEPTH 2\nMAXVAL 65535\nTUPLTYPE GRAYSCALE_ALPHA\nENDHDR\n";
  let raster = Vec[UInt8].new();
  raster.push(18 as UInt8);
  raster.push(52 as UInt8);
  raster.push(171 as UInt8);
  raster.push(205 as UInt8);
  let ts = Vec[Str].new();
  ts.push("GRAYSCALE_ALPHA");
  let data = ok_bytes(pam_build(1, 1, 2, 65535, &ts, &raster));
  if (!bytes_prefix_is(data, hdr)) { return assert(false, "16-bit canonical header bytes"); }
  if (data.len() != hdr.len() + 4) { return assert(false, "16-bit 1x1x2 is header + 4 bytes"); }
  if (!byte_is(data, hdr.len(), 18)) { return assert(false, "first sample high byte"); }
  if (!byte_is(data, hdr.len() + 1, 52)) { return assert(false, "first sample low byte"); }
  if (!byte_is(data, hdr.len() + 2, 171)) { return assert(false, "second sample high byte"); }
  if (!byte_is(data, hdr.len() + 3, 205)) { return assert(false, "second sample low byte"); }
  let img = ok_img(pam_parse_header(data));
  if (pam_maxval(&img) != 65535) { return assert(false, "16-bit maxval"); }
  if (img.bytes_per_sample != 2) { return assert(false, "16-bit bytes per sample 2"); }
  if (pam_raster_len(&img) != 4) { return assert(false, "16-bit raster length 4"); }
  if (!raster_span_is(data, &img, &raster)) { return assert(false, "16-bit raster byte-exact copy"); }
  if (pam_bytes_per_sample(255) != 1) { return assert(false, "maxval 255 is one byte"); }
  if (pam_bytes_per_sample(256) != 2) { return assert(false, "maxval 256 is two bytes"); }
  if (pam_bytes_per_sample(65535) != 2) { return assert(false, "maxval 65535 is two bytes"); }
  if (pam_bytes_per_sample(0) != 0) { return assert(false, "maxval 0 has no byte size"); }
  if (pam_bytes_per_sample(-1) != 0) { return assert(false, "negative maxval has no byte size"); }
  if (pam_bytes_per_sample(65536) != 0) { return assert(false, "maxval 65536 has no byte size"); }
  return assert(true, "16-bit samples are two bytes big-endian");
}

fn t5() -> TestResult {
  let raw = "P7\nWIDTH 1\nHEIGHT 1\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB\nTUPLTYPE ALPHA\nENDHDR\n";
  let data = bytes_of(raw);
  data.push(1 as UInt8);
  data.push(2 as UInt8);
  data.push(3 as UInt8);
  data.push(4 as UInt8);
  let img = ok_img(pam_parse_header(data));
  if (pam_tupltype_count(&img) != 2) { return assert(false, "two TUPLTYPE lines"); }
  if (!tuple_is(&img, 0, "RGB")) { return assert(false, "first TUPLTYPE is RGB"); }
  if (!tuple_is(&img, 1, "ALPHA")) { return assert(false, "second TUPLTYPE is ALPHA"); }
  if (!tuple_is(&img, 2, "")) { return assert(false, "past-the-end TUPLTYPE sentinel"); }
  let joined: Str = pam_tuple_type(&img);
  if (!streq(joined, "RGB ALPHA")) { return assert(false, "tuple type joins with one space"); }
  let ts = Vec[Str].new();
  ts.push("RGB");
  ts.push("ALPHA");
  let raster = Vec[UInt8].new();
  raster.push(1 as UInt8);
  raster.push(2 as UInt8);
  raster.push(3 as UInt8);
  raster.push(4 as UInt8);
  let built = ok_bytes(pam_build(1, 1, 4, 255, &ts, &raster));
  if (!bytes_prefix_is(built, raw)) { return assert(false, "multi-TUPLTYPE build order"); }
  let back = ok_img(pam_parse_header(built));
  if (!tuple_is(&back, 0, "RGB")) { return assert(false, "rebuilt first TUPLTYPE"); }
  if (!tuple_is(&back, 1, "ALPHA")) { return assert(false, "rebuilt second TUPLTYPE"); }
  return assert(true, "multiple TUPLTYPE lines are preserved in order");
}

fn t6() -> TestResult {
  if (!img_err_is(pam_parse_header(bytes_of("P6\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n")), "pam: bad magic")) {
    return assert(false, "P6 magic is rejected");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P8\n")), "pam: bad magic")) {
    return assert(false, "P8 magic is rejected");
  }
  let hi = Vec[UInt8].new();
  hi.push(255 as UInt8);
  hi.push(55 as UInt8);
  hi.push(10 as UInt8);
  if (!img_err_is(pam_parse_header(hi), "pam: bad magic")) {
    return assert(false, "high-byte magic is rejected");
  }
  let empty = Vec[UInt8].new();
  if (!img_err_is(pam_parse_header(empty), "pam: truncated header")) {
    return assert(false, "empty buffer is truncated");
  }
  let one = Vec[UInt8].new();
  one.push(80 as UInt8);
  if (!img_err_is(pam_parse_header(one), "pam: truncated header")) {
    return assert(false, "1-byte buffer is truncated");
  }
  let two = Vec[UInt8].new();
  two.push(80 as UInt8);
  two.push(55 as UInt8);
  if (!img_err_is(pam_parse_header(two), "pam: truncated header")) {
    return assert(false, "magic-only buffer is truncated");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7X\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n")), "pam: missing newline after magic")) {
    return assert(false, "P7 must be followed by a newline");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\rX\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n")), "pam: missing newline after magic")) {
    return assert(false, "CR must be followed by LF after the magic");
  }
  return assert(true, "only P7 followed by LF or CRLF is accepted");
}

fn t7() -> TestResult {
  let no_w = "P7\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(no_w)), "pam: missing width")) {
    return assert(false, "header without WIDTH misses width");
  }
  let no_h = "P7\nWIDTH 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(no_h)), "pam: missing height")) {
    return assert(false, "header without HEIGHT misses height");
  }
  let no_d = "P7\nWIDTH 1\nHEIGHT 1\nMAXVAL 255\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(no_d)), "pam: missing depth")) {
    return assert(false, "header without DEPTH misses depth");
  }
  let no_m = "P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(no_m)), "pam: missing maxval")) {
    return assert(false, "header without MAXVAL misses maxval");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\n")), "pam: missing ENDHDR")) {
    return assert(false, "magic-only header misses ENDHDR");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\n")), "pam: missing ENDHDR")) {
    return assert(false, "EOF before ENDHDR reports missing ENDHDR");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHD")), "pam: missing ENDHDR")) {
    return assert(false, "unterminated ENDHDR line reports missing ENDHDR");
  }
  return assert(true, "every required key is required and ENDHDR terminates the header");
}

fn t8() -> TestResult {
  let w2 = "P7\nWIDTH 1\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(w2)), "pam: duplicate width")) {
    return assert(false, "second WIDTH is a duplicate");
  }
  let h2 = "P7\nWIDTH 1\nHEIGHT 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(h2)), "pam: duplicate height")) {
    return assert(false, "second HEIGHT is a duplicate");
  }
  let d2 = "P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(d2)), "pam: duplicate depth")) {
    return assert(false, "second DEPTH is a duplicate");
  }
  let m2 = "P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nMAXVAL 255\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(m2)), "pam: duplicate maxval")) {
    return assert(false, "second MAXVAL is a duplicate");
  }
  return assert(true, "required keys may not repeat");
}

fn t9() -> TestResult {
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH 0\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n")), "pam: invalid width")) {
    return assert(false, "width 0 is invalid");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH -1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n")), "pam: missing width")) {
    return assert(false, "negative width token is not decimal");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH 1000001\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n")), "pam: invalid width")) {
    return assert(false, "width 1000001 exceeds the cap");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH 1234567890\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n")), "pam: invalid width")) {
    return assert(false, "10-digit width is invalid");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH 1\nHEIGHT 0\nDEPTH 1\nMAXVAL 255\nENDHDR\n")), "pam: invalid height")) {
    return assert(false, "height 0 is invalid");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 0\nMAXVAL 255\nENDHDR\n")), "pam: invalid depth")) {
    return assert(false, "depth 0 is invalid");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1000001\nMAXVAL 255\nENDHDR\n")), "pam: invalid depth")) {
    return assert(false, "depth 1000001 exceeds the cap");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 0\nENDHDR\n")), "pam: invalid maxval")) {
    return assert(false, "maxval 0 is invalid");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 65536\nENDHDR\n")), "pam: invalid maxval")) {
    return assert(false, "maxval 65536 is invalid");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 123456\nENDHDR\n")), "pam: invalid maxval")) {
    return assert(false, "6-digit maxval is invalid");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 1234567890\nENDHDR\n")), "pam: invalid maxval")) {
    return assert(false, "10-digit maxval is invalid");
  }
  return assert(true, "non-positive and oversized dimensions and maxval are rejected");
}

fn t10() -> TestResult {
  let fifo = "P7\nFOO 1\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(fifo)), "pam: unknown header key")) {
    return assert(false, "unknown key is rejected");
  }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nwidth 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n")), "pam: unknown header key")) {
    return assert(false, "keys are case-sensitive");
  }
  let extra = "P7\nWIDTH 1 2\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(extra)), "pam: malformed header line")) {
    return assert(false, "trailing tokens after WIDTH");
  }
  let nondec = "P7\nWIDTH x\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(nondec)), "pam: missing width")) {
    return assert(false, "non-decimal WIDTH value misses the value");
  }
  let noval = "P7\nWIDTH\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(noval)), "pam: missing width")) {
    return assert(false, "WIDTH without a value");
  }
  let endextra = "P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR extra\n";
  if (!img_err_is(pam_parse_header(bytes_of(endextra)), "pam: malformed header line")) {
    return assert(false, "ENDHDR with trailing tokens");
  }
  let emptytt = "P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nTUPLTYPE\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(emptytt)), "pam: invalid tuple type")) {
    return assert(false, "TUPLTYPE without a value");
  }
  let spacett = "P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nTUPLTYPE    \nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(spacett)), "pam: invalid tuple type")) {
    return assert(false, "whitespace-only TUPLTYPE value");
  }
  let tabtt = "P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nTUPLTYPE a\tb\nENDHDR\n";
  if (!img_err_is(pam_parse_header(bytes_of(tabtt)), "pam: invalid tuple type")) {
    return assert(false, "interior TAB in a TUPLTYPE value");
  }
  let nul = bytes_of("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nTUPLTYPE A");
  nul.push(0 as UInt8);
  let tail = bytes_of("B\nENDHDR\n");
  var i = 0;
  while (i < tail.len()) {
    let b: UInt8 = tail[i];
    nul.push(b);
    i = i + 1;
  }
  if (!img_err_is(pam_parse_header(nul), "pam: invalid tuple type")) {
    return assert(false, "NUL in a TUPLTYPE value");
  }
  return assert(true, "malformed lines, unknown keys and bad tuple types are rejected");
}

fn t11() -> TestResult {
  let r = raster12();
  let ts = Vec[Str].new();
  let full = ok_bytes(pam_build(2, 2, 3, 255, &ts, &r));
  full.pop();
  if (!img_err_is(pam_parse_header(full), "pam: truncated raster")) {
    return assert(false, "one byte short is truncated");
  }
  let hdr_only = bytes_of("P7\nWIDTH 2\nHEIGHT 2\nDEPTH 3\nMAXVAL 255\nENDHDR\n");
  if (!img_err_is(pam_parse_header(hdr_only), "pam: truncated raster")) {
    return assert(false, "header with no raster is truncated");
  }
  let d16 = bytes_of("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 256\nENDHDR\n");
  d16.push(1 as UInt8);
  if (!img_err_is(pam_parse_header(d16), "pam: truncated raster")) {
    return assert(false, "one byte of a 16-bit sample is truncated");
  }
  return assert(true, "rasters shorter than width*height*depth*bytes-per-sample are rejected");
}

fn t12() -> TestResult {
  let r = raster12();
  let ts = Vec[Str].new();
  let full = ok_bytes(pam_build(2, 2, 3, 255, &ts, &r));
  let exact = ok_img(pam_parse_header(full));
  if (pam_raster_len(&exact) != 12) { return assert(false, "exact size parses"); }
  full.push(0 as UInt8);
  if (!img_err_is(pam_parse_header(full), "pam: extra raster bytes")) {
    return assert(false, "one extra byte is an error");
  }
  let ws = ok_bytes(pam_build(2, 2, 3, 255, &ts, &r));
  ws.push(10 as UInt8);
  if (!img_err_is(pam_parse_header(ws), "pam: extra raster bytes")) {
    return assert(false, "trailing whitespace is raster data and is extra");
  }
  let one = Vec[UInt8].new();
  one.push(1 as UInt8);
  let first = ok_bytes(pam_build(1, 1, 1, 255, &ts, &one));
  let second = ok_bytes(pam_build(1, 1, 1, 255, &ts, &one));
  var k = 0;
  while (k < second.len()) {
    let b: UInt8 = second[k];
    first.push(b);
    k = k + 1;
  }
  if (!img_err_is(pam_parse_header(first), "pam: extra raster bytes")) {
    return assert(false, "a concatenated second image is extra bytes");
  }
  return assert(true, "rasters longer than the computed size are rejected");
}

fn t13() -> TestResult {
  let raw = "P7\nWIDTH 2\nHEIGHT 1\nDEPTH 2\nMAXVAL 65535\nTUPLTYPE RGB_ALPHA\nENDHDR\n";
  let raster = Vec[UInt8].new();
  raster.push(0 as UInt8);
  raster.push(1 as UInt8);
  raster.push(255 as UInt8);
  raster.push(254 as UInt8);
  raster.push(128 as UInt8);
  raster.push(0 as UInt8);
  raster.push(0 as UInt8);
  raster.push(128 as UInt8);
  let ts = Vec[Str].new();
  ts.push("RGB_ALPHA");
  let data = ok_bytes(pam_build(2, 1, 2, 65535, &ts, &raster));
  if (!bytes_prefix_is(data, raw)) { return assert(false, "16-bit round-trip header"); }
  if (data.len() != raw.len() + 8) { return assert(false, "16-bit round-trip length"); }
  let img = ok_img(pam_parse_header(data));
  if (!raster_span_is(data, &img, &raster)) { return assert(false, "16-bit parse keeps every sample byte"); }
  let copy = ok_bytes(pam_raster_copy(data, &img));
  let ts2 = Vec[Str].new();
  let t0: Str = pam_tupltype(&img, 0);
  ts2.push(t0);
  let again = ok_bytes(pam_build(pam_width(&img), pam_height(&img), pam_depth(&img), pam_maxval(&img), &ts2, &copy));
  if (!vec_eq(again, data)) { return assert(false, "rebuild from parsed fields is byte-identical"); }
  let back = ok_img(pam_parse_header(again));
  if (back.maxval != 65535) { return assert(false, "reparsed maxval 65535"); }
  if (back.bytes_per_sample != 2) { return assert(false, "reparsed bytes per sample 2"); }
  return assert(true, "16-bit 2x1x2 PAM round-trips byte-exactly");
}

fn t14() -> TestResult {
  let raw = "P7\r\n# lead\r\nMAXVAL 255\r\nDEPTH 1\r\nHEIGHT 1\r\nWIDTH 2\r\nTUPLTYPE WEIRD TYPE\r\nENDHDR\r\n";
  let data = bytes_of(raw);
  data.push(1 as UInt8);
  data.push(2 as UInt8);
  let img = ok_img(pam_parse_header(data));
  if (pam_width(&img) != 2) { return assert(false, "odd-order width 2"); }
  if (pam_height(&img) != 1) { return assert(false, "odd-order height 1"); }
  if (pam_depth(&img) != 1) { return assert(false, "odd-order depth 1"); }
  if (pam_maxval(&img) != 255) { return assert(false, "odd-order maxval 255"); }
  if (!tuple_is(&img, 0, "WEIRD TYPE")) { return assert(false, "interior space preserved"); }
  let want = "P7\nWIDTH 2\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nTUPLTYPE WEIRD TYPE\nENDHDR\n";
  let ts = Vec[Str].new();
  let t0: Str = pam_tupltype(&img, 0);
  ts.push(t0);
  let copy = ok_bytes(pam_raster_copy(data, &img));
  let canon = ok_bytes(pam_build(2, 1, 1, 255, &ts, &copy));
  if (canon.len() != want.len() + 2) { return assert(false, "canonicalized length"); }
  if (!bytes_prefix_is(canon, want)) { return assert(false, "odd-order CRLF input canonicalizes"); }
  if (!byte_is(canon, want.len(), 1)) { return assert(false, "canonicalized raster byte 1"); }
  if (!byte_is(canon, want.len() + 1, 2)) { return assert(false, "canonicalized raster byte 2"); }
  let back = ok_img(pam_parse_header(canon));
  if (!tuple_is(&back, 0, "WEIRD TYPE")) { return assert(false, "canonicalized tuple type survives"); }
  return assert(true, "free key order, CRLF and comments canonicalize deterministically");
}

fn t15() -> TestResult {
  let one = Vec[UInt8].new();
  one.push(1 as UInt8);
  let two = Vec[UInt8].new();
  two.push(1 as UInt8);
  two.push(2 as UInt8);
  let ts = Vec[Str].new();
  if (!bytes_err_is(pam_build(2, 1, 1, 255, &ts, &one), "pam: raster buffer size mismatch")) {
    return assert(false, "short raster buffer");
  }
  if (!bytes_err_is(pam_build(1, 1, 1, 255, &ts, &two), "pam: raster buffer size mismatch")) {
    return assert(false, "long raster buffer");
  }
  if (bad_bytes(pam_build(1, 1, 1, 255, &ts, &one))) {
    return assert(false, "exact raster buffer succeeds");
  }
  if (!bytes_err_is(pam_build(0, 1, 1, 255, &ts, &one), "pam: invalid width")) {
    return assert(false, "builder width 0");
  }
  if (!bytes_err_is(pam_build(-2, 1, 1, 255, &ts, &one), "pam: invalid width")) {
    return assert(false, "builder negative width");
  }
  if (!bytes_err_is(pam_build(1, 0, 1, 255, &ts, &one), "pam: invalid height")) {
    return assert(false, "builder height 0");
  }
  if (!bytes_err_is(pam_build(1, 1, 0, 255, &ts, &one), "pam: invalid depth")) {
    return assert(false, "builder depth 0");
  }
  if (!bytes_err_is(pam_build(1, 1, 1, 0, &ts, &one), "pam: invalid maxval")) {
    return assert(false, "builder maxval 0");
  }
  if (!bytes_err_is(pam_build(1, 1, 1, 65536, &ts, &one), "pam: invalid maxval")) {
    return assert(false, "builder maxval 65536");
  }
  let e1 = Vec[Str].new();
  e1.push("");
  if (!bytes_err_is(pam_build(1, 1, 1, 255, &e1, &one), "pam: invalid tuple type")) {
    return assert(false, "empty tuple type");
  }
  let e2 = Vec[Str].new();
  e2.push(" x");
  if (!bytes_err_is(pam_build(1, 1, 1, 255, &e2, &one), "pam: invalid tuple type")) {
    return assert(false, "leading space in a tuple type");
  }
  let e3 = Vec[Str].new();
  e3.push("x ");
  if (!bytes_err_is(pam_build(1, 1, 1, 255, &e3, &one), "pam: invalid tuple type")) {
    return assert(false, "trailing space in a tuple type");
  }
  let ctl = Vec[UInt8].new();
  ctl.push(1 as UInt8);
  ctl.push(120 as UInt8);
  let e4 = Vec[Str].new();
  let s4 = str_of_bytes(ctl);
  e4.push(s4);
  if (!bytes_err_is(pam_build(1, 1, 1, 255, &e4, &one), "pam: invalid tuple type")) {
    return assert(false, "control byte in a tuple type");
  }
  let good = Vec[Str].new();
  good.push("a b");
  let built = ok_bytes(pam_build(1, 1, 1, 255, &good, &one));
  if (!bytes_prefix_is(built, "P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nTUPLTYPE a b\nENDHDR\n")) {
    return assert(false, "interior-space tuple type builds");
  }
  return assert(true, "pam_build validates dimensions, maxval, raster size and tuple types");
}

fn t16() -> TestResult {
  let hdr = "P7\nMAXVAL 255\nDEPTH 3\nHEIGHT 2\nWIDTH 2\nENDHDR\n";
  let data = bytes_of(hdr);
  var i = 0;
  while (i < 12) {
    data.push((i + 1) as UInt8);
    i = i + 1;
  }
  let img = ok_img(pam_parse_header(data));
  if (pam_raster_offset(&img) != hdr.len()) { return assert(false, "odd key order sets the offset"); }
  if (pam_raster_len(&img) != 12) { return assert(false, "odd key order sets the raster length"); }
  let want = raster12();
  if (!raster_span_is(data, &img, &want)) { return assert(false, "span copy is exact"); }
  let ts = Vec[Str].new();
  let forged = PamImage{ width: 1; height: 1; depth: 1; maxval: 255; bytes_per_sample: 1; data_offset: 0; raster_len: 1000000; tupltypes: ts; };
  if (!bytes_err_is(pam_raster_copy(data, &forged), "pam: raster out of range")) {
    return assert(false, "span past the buffer is rejected");
  }
  let ts2 = Vec[Str].new();
  let forged2 = PamImage{ width: 1; height: 1; depth: 1; maxval: 255; bytes_per_sample: 1; data_offset: -1; raster_len: 1; tupltypes: ts2; };
  if (!bytes_err_is(pam_raster_copy(data, &forged2), "pam: raster out of range")) {
    return assert(false, "negative offset is rejected");
  }
  let ts3 = Vec[Str].new();
  let forged3 = PamImage{ width: 1; height: 1; depth: 1; maxval: 255; bytes_per_sample: 1; data_offset: 0; raster_len: -1; tupltypes: ts3; };
  if (!bytes_err_is(pam_raster_copy(data, &forged3), "pam: raster out of range")) {
    return assert(false, "negative length is rejected");
  }
  return assert(true, "pam_raster_offset/len and pam_raster_copy expose exactly the raster");
}

fn t17() -> TestResult {
  let ts = Vec[Str].new();
  let one = Vec[UInt8].new();
  one.push(1 as UInt8);
  let d1 = ok_bytes(pam_build(1, 1, 1, 1, &ts, &one));
  let i1 = ok_img(pam_parse_header(d1));
  if (pam_maxval(&i1) != 1) { return assert(false, "maxval 1 parses"); }
  if (i1.bytes_per_sample != 1) { return assert(false, "maxval 1 is one byte per sample"); }
  if (pam_raster_len(&i1) != 1) { return assert(false, "maxval 1 raster length 1"); }
  let b16 = Vec[UInt8].new();
  b16.push(1 as UInt8);
  b16.push(0 as UInt8);
  let d2 = ok_bytes(pam_build(1, 1, 1, 256, &ts, &b16));
  let i2 = ok_img(pam_parse_header(d2));
  if (pam_maxval(&i2) != 256) { return assert(false, "maxval 256 parses"); }
  if (i2.bytes_per_sample != 2) { return assert(false, "maxval 256 is two bytes per sample"); }
  if (pam_raster_len(&i2) != 2) { return assert(false, "maxval 256 raster length 2"); }
  if (!raster_span_is(d2, &i2, &b16)) { return assert(false, "maxval 256 raster is big-endian bytes"); }
  let short = bytes_of("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 1\nMAXVAL 256\nENDHDR\n");
  short.push(1 as UInt8);
  if (!img_err_is(pam_parse_header(short), "pam: truncated raster")) {
    return assert(false, "one byte cannot hold a 16-bit sample");
  }
  return assert(true, "the 255/256 bytes-per-sample boundary is exact");
}

fn t18() -> TestResult {
  let raster = Vec[UInt8].new();
  raster.push(0 as UInt8);
  raster.push(128 as UInt8);
  raster.push(255 as UInt8);
  raster.push(127 as UInt8);
  raster.push(1 as UInt8);
  raster.push(254 as UInt8);
  let ts = Vec[Str].new();
  ts.push("GRAYSCALE_ALPHA");
  let data = ok_bytes(pam_build(3, 1, 2, 255, &ts, &raster));
  let img = ok_img(pam_parse_header(data));
  if (!raster_span_is(data, &img, &raster)) { return assert(false, "high bytes survive the span copy"); }
  if (!byte_is(data, pam_raster_offset(&img), 0)) { return assert(false, "first raster byte 0"); }
  if (!byte_is(data, pam_raster_offset(&img) + 1, 128)) { return assert(false, "second raster byte 128"); }
  if (!byte_is(data, pam_raster_offset(&img) + 2, 255)) { return assert(false, "third raster byte 255"); }
  if (!byte_is(data, pam_raster_offset(&img) + 5, 254)) { return assert(false, "sixth raster byte 254"); }
  return assert(true, "widened byte comparisons treat >= 128 values correctly");
}

fn t19() -> TestResult {
  let raw = "P7\nWIDTH 1\nHEIGHT 3\nDEPTH 1\nMAXVAL 255\nTUPLTYPE A\nTUPLTYPE B\nTUPLTYPE C\nENDHDR\n";
  let data = bytes_of(raw);
  data.push(1 as UInt8);
  data.push(2 as UInt8);
  data.push(3 as UInt8);
  let img = ok_img(pam_parse_header(data));
  if (pam_tupltype_count(&img) != 3) { return assert(false, "three TUPLTYPE lines"); }
  if (!tuple_is(&img, 0, "A")) { return assert(false, "index 0 is A"); }
  if (!tuple_is(&img, 1, "B")) { return assert(false, "index 1 is B"); }
  if (!tuple_is(&img, 2, "C")) { return assert(false, "index 2 is C"); }
  if (!tuple_is(&img, 3, "")) { return assert(false, "index == count is the empty sentinel"); }
  if (!tuple_is(&img, -1, "")) { return assert(false, "negative index is the empty sentinel"); }
  let joined: Str = pam_tuple_type(&img);
  if (!streq(joined, "A B C")) { return assert(false, "three values join with single spaces"); }
  return assert(true, "pam_tupltype indexing and sentinels are exact");
}

fn t20() -> TestResult {
  let hdr = "P7\nWIDTH 1000000\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n";
  let data = bytes_of(hdr);
  var i = 0;
  while (i < 1000000) {
    data.push(0 as UInt8);
    i = i + 1;
  }
  let img = ok_img(pam_parse_header(data));
  if (pam_width(&img) != 1000000) { return assert(false, "width 1000000 parses"); }
  if (pam_raster_len(&img) != 1000000) { return assert(false, "cap-width raster length"); }
  if (pam_raster_offset(&img) + pam_raster_len(&img) != data.len()) { return assert(false, "cap-width span covers the buffer"); }
  if (!byte_is(data, pam_raster_offset(&img) + 999999, 0)) { return assert(false, "last cap-width raster byte"); }
  if (!img_err_is(pam_parse_header(bytes_of("P7\nWIDTH 1000001\nHEIGHT 1\nDEPTH 1\nMAXVAL 255\nENDHDR\n")), "pam: invalid width")) {
    return assert(false, "width 1000001 is rejected");
  }
  return assert(true, "dimensions are capped at 1000000");
}

fn main() -> Int {
  io.println("=== xiom.pam conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.pam: all tests passed");
  } else {
    io.println("xiom.pam: tests failed");
  }
  return failed;
}
