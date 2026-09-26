// XIOM -- xiom.png conformance tests (17 checks)
// Port task: prove the pure-XIOM xiom.png PNG 1.2 container codec.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module png_tests
use xiom.io; use xiom.test; use xiom.png;
use xiom.string; use xiom.string.compare;
use xiom.convert;

// All Str equality goes through str_compare: `==` on a Str lowered from a
// Vec[Str] element is a pointer comparison in v0.61.3, so every expected
// message and every keyword/text is compared with this helper.
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Unsigned byte `i` of `data` equals `want` (0..255).
fn byte_is(data: &Vec[UInt8], i: Int, want: Int) -> Bool {
  let b: Int = (data[i] as Int) & 0xFF;
  return b == want;
}

fn ok_img(r: Result[PngImage, Str]) -> PngImage {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return empty_img(); },
  }
}

fn img_err_is(r: Result[PngImage, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn bad_img(r: Result[PngImage, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

// Error message for an offset: "<base> at <off>".
fn at(base: Str, off: Int) -> Str {
  return base + " at " + convert.int_to_string(off);
}

// The dummy image returned by ok_img when a test unexpectedly hit an error.
fn empty_img() -> PngImage {
  return PngImage{
    width: 0; height: 0; bit_depth: 0; color_type: -1; compression: 0;
    filter: 0; interlace: 0; has_plte: 0; palette: Vec[UInt8].new();
    has_trns: 0; trns: Vec[UInt8].new(); gamma: -1; phys_x: -1; phys_y: -1;
    phys_unit: -1; srgb_intent: -1; chunk_type: Vec[Str].new();
    chunk_offset: Vec[Int].new(); chunk_length: Vec[Int].new();
    chunk_data_offset: Vec[Int].new(); chunk_crc: Vec[Int].new();
    text_kind: Vec[Int].new(); text_offset: Vec[Int].new();
    text_length: Vec[Int].new(); text_keyword: Vec[Str].new();
    text_value: Vec[Str].new(); text_lang: Vec[Str].new();
    text_translated: Vec[Str].new(); text_compressed: Vec[Int].new();
    text_method: Vec[Int].new();
  };
}

// --------------------------------------------------
//  Fixture builders (synthetic PNG byte buffers, no external files)
// --------------------------------------------------

fn sig_bytes(out: &mut Vec[UInt8]) {
  out.push(137 as UInt8);
  out.push(80 as UInt8);
  out.push(78 as UInt8);
  out.push(71 as UInt8);
  out.push(13 as UInt8);
  out.push(10 as UInt8);
  out.push(26 as UInt8);
  out.push(10 as UInt8);
}

fn push_be32(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 16777216) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

fn push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while (i < v.len()) {
    out.push(v[i]);
    i = i + 1;
  }
}

// Append one complete chunk with a correct CRC over type+data.
fn push_chunk(out: &mut Vec[UInt8], t0: Int, t1: Int, t2: Int, t3: Int, payload: &Vec[UInt8]) {
  push_be32(out, payload.len());
  out.push(t0 as UInt8);
  out.push(t1 as UInt8);
  out.push(t2 as UInt8);
  out.push(t3 as UInt8);
  push_bytes(out, payload);
  var tc = Vec[UInt8].new();
  tc.push(t0 as UInt8);
  tc.push(t1 as UInt8);
  tc.push(t2 as UInt8);
  tc.push(t3 as UInt8);
  push_bytes(&mut tc, payload);
  push_be32(out, png_crc32(&tc));
}

// Deterministic payload of `n` bytes derived from `seed`.
fn raw_bytes(n: Int, seed: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    v.push(((seed + i) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

fn ihdr_payload(w: Int, h: Int, depth: Int, ctype: Int, comp: Int, filt: Int, inter: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_be32(&mut v, w);
  push_be32(&mut v, h);
  v.push(depth as UInt8);
  v.push(ctype as UInt8);
  v.push(comp as UInt8);
  v.push(filt as UInt8);
  v.push(inter as UInt8);
  return v;
}

fn push_idat(out: &mut Vec[UInt8], n: Int, seed: Int) {
  let v = raw_bytes(n, seed);
  push_chunk(out, 73, 68, 65, 84, v);
}

fn push_iend(out: &mut Vec[UInt8]) {
  let none = Vec[UInt8].new();
  push_chunk(out, 73, 69, 78, 68, none);
}

// Canonical minimal PNG: signature + IHDR + optional 1-entry PLTE + IDAT(1) +
// IEND. With no PLTE it is 58 bytes: IHDR at 8 (25), IDAT at 33 (13), IEND at
// 46 (12).
fn mk_png(w: Int, h: Int, depth: Int, ctype: Int, comp: Int, filt: Int, inter: Int, with_plte: Bool) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  sig_bytes(&mut out);
  let ih = ihdr_payload(w, h, depth, ctype, comp, filt, inter);
  push_chunk(&mut out, 73, 72, 68, 82, ih);
  if (with_plte) {
    var pl = Vec[UInt8].new();
    pl.push(1 as UInt8);
    pl.push(2 as UInt8);
    pl.push(3 as UInt8);
    push_chunk(&mut out, 80, 76, 84, 69, pl);
  }
  push_idat(&mut out, 1, 7);
  push_iend(&mut out);
  return out;
}

// Signature + IHDR + one PLTE payload of `plen` bytes (built for ctype/depth)
// + IDAT + IEND.
fn mk_with_plte(ctype: Int, depth: Int, plen: Int, seed: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  sig_bytes(&mut out);
  let ih = ihdr_payload(1, 1, depth, ctype, 0, 0, 0);
  push_chunk(&mut out, 73, 72, 68, 82, ih);
  let pl = raw_bytes(plen, seed);
  push_chunk(&mut out, 80, 76, 84, 69, pl);
  push_idat(&mut out, 1, 9);
  push_iend(&mut out);
  return out;
}

// Signature + IHDR(1x1) + optional PLTE (`plen` > 0) + optional tRNS
// (`tlen` >= 0) + IDAT + IEND.
fn mk_with_trns(ctype: Int, depth: Int, plen: Int, tlen: Int, seed: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  sig_bytes(&mut out);
  let ih = ihdr_payload(1, 1, depth, ctype, 0, 0, 0);
  push_chunk(&mut out, 73, 72, 68, 82, ih);
  if (plen > 0) {
    let pl = raw_bytes(plen, seed + 1);
    push_chunk(&mut out, 80, 76, 84, 69, pl);
  }
  if (tlen >= 0) {
    let tr = raw_bytes(tlen, seed + 2);
    push_chunk(&mut out, 116, 82, 78, 83, tr);
  }
  push_idat(&mut out, 1, 9);
  push_iend(&mut out);
  return out;
}

// Signature + IHDR(1x1 gray 8) + one tEXt/zTXt/iTXt chunk with `payload` +
// IDAT + IEND. kind: 0 tEXt, 1 zTXt, 2 iTXt.
fn mk_with_text(kind: Int, payload: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  sig_bytes(&mut out);
  let ih = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut out, 73, 72, 68, 82, ih);
  if (kind == 0) {
    push_chunk(&mut out, 116, 69, 88, 116, payload);
  } elif (kind == 1) {
    push_chunk(&mut out, 122, 84, 88, 116, payload);
  } else {
    push_chunk(&mut out, 105, 84, 88, 116, payload);
  }
  push_idat(&mut out, 1, 5);
  push_iend(&mut out);
  return out;
}

// Signature + IHDR(1x1 gray 8) + one ancillary chunk + IDAT + IEND.
fn mk_with_meta(t0: Int, t1: Int, t2: Int, t3: Int, payload: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  sig_bytes(&mut out);
  let ih = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut out, 73, 72, 68, 82, ih);
  push_chunk(&mut out, t0, t1, t2, t3, payload);
  push_idat(&mut out, 1, 5);
  push_iend(&mut out);
  return out;
}

// tEXt payload "keyword" + 0x00 + text bytes.
fn text_payload(keyword: Str, text: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while (i < string.str_len(keyword)) {
    v.push(string.byte_at(keyword, i));
    i = i + 1;
  }
  v.push(0 as UInt8);
  i = 0;
  while (i < string.str_len(text)) {
    v.push(string.byte_at(text, i));
    i = i + 1;
  }
  return v;
}

// Recompute the CRC a chunk at `pos` with data length `len` should carry.
fn chunk_crc_of(d: &Vec[UInt8], pos: Int, len: Int) -> Int {
  var tc = Vec[UInt8].new();
  var i = pos + 4;
  while (i < pos + 8 + len) {
    tc.push(d[i]);
    i = i + 1;
  }
  return png_crc32(&tc);
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  if (png_signature_size() != 8) { return assert(false, "signature size is 8"); }
  if (png_min_chunk_size() != 12) { return assert(false, "min chunk size is 12"); }
  let d = mk_png(1, 1, 8, 0, 0, 0, 0, false);
  if (d.len() != 58) { return assert(false, "minimal PNG is 58 bytes"); }
  if (!png_is_png(d)) { return assert(false, "signature classifies as PNG"); }
  let img = ok_img(png_parse(d));
  if (png_width(img) != 1) { return assert(false, "width 1"); }
  if (png_height(img) != 1) { return assert(false, "height 1"); }
  if (png_bit_depth(img) != 8) { return assert(false, "bit depth 8"); }
  if (png_color_type(img) != 0) { return assert(false, "color type 0"); }
  if (png_compression(img) != 0) { return assert(false, "compression 0"); }
  if (png_filter(img) != 0) { return assert(false, "filter 0"); }
  if (png_interlace(img) != 0) { return assert(false, "interlace 0"); }
  if (png_chunk_count(img) != 3) { return assert(false, "three chunks"); }
  if (png_chunk_offset(img, 0) != 8) { return assert(false, "IHDR at 8"); }
  if (png_chunk_offset(img, 1) != 33) { return assert(false, "IDAT at 33"); }
  if (png_chunk_offset(img, 2) != 46) { return assert(false, "IEND at 46"); }
  if (png_chunk_length(img, 0) != 13) { return assert(false, "IHDR length 13"); }
  if (png_chunk_length(img, 1) != 1) { return assert(false, "IDAT length 1"); }
  if (png_chunk_length(img, 2) != 0) { return assert(false, "IEND length 0"); }
  if (png_chunk_data_offset(img, 0) != 16) { return assert(false, "IHDR data at 16"); }
  if (png_chunk_data_offset(img, 1) != 41) { return assert(false, "IDAT data at 41"); }
  if (png_chunk_data_offset(img, 2) != 54) { return assert(false, "IEND data at 54"); }
  let s0: Str = png_chunk_type(img, 0);
  if (!streq(s0, "IHDR")) { return assert(false, "chunk 0 is IHDR"); }
  let s1: Str = png_chunk_type(img, 1);
  if (!streq(s1, "IDAT")) { return assert(false, "chunk 1 is IDAT"); }
  let s2: Str = png_chunk_type(img, 2);
  if (!streq(s2, "IEND")) { return assert(false, "chunk 2 is IEND"); }
  if (png_chunk_crc(img, 0) != chunk_crc_of(d, 8, 13)) {
    return assert(false, "stored IHDR CRC matches recomputation");
  }
  return assert(true, "minimal PNG header, chunk index and CRCs decode exactly");
}

fn t2() -> TestResult {
  let cts = Vec[Int].new();
  let dps = Vec[Int].new();
  cts.push(0); dps.push(1);
  cts.push(0); dps.push(2);
  cts.push(0); dps.push(4);
  cts.push(0); dps.push(8);
  cts.push(0); dps.push(16);
  cts.push(2); dps.push(8);
  cts.push(2); dps.push(16);
  cts.push(3); dps.push(1);
  cts.push(3); dps.push(2);
  cts.push(3); dps.push(4);
  cts.push(3); dps.push(8);
  cts.push(4); dps.push(8);
  cts.push(4); dps.push(16);
  cts.push(6); dps.push(8);
  cts.push(6); dps.push(16);
  var i = 0;
  while (i < cts.len()) {
    let ct: Int = cts[i];
    let dp: Int = dps[i];
    let has_plte = ct == 3;
    let d = mk_png(3, 2, dp, ct, 0, 0, 0, has_plte);
    if (bad_img(png_parse(d))) {
      return assert(false, "every legal color type/bit depth combo parses");
    }
    i = i + 1;
  }
  if (!img_err_is(png_parse(mk_png(1, 1, 1, 2, 0, 0, 0, false)), at("png: invalid bit depth", 24))) {
    return assert(false, "truecolor depth 1 is rejected");
  }
  if (!img_err_is(png_parse(mk_png(1, 1, 16, 3, 0, 0, 0, false)), at("png: invalid bit depth", 24))) {
    return assert(false, "indexed depth 16 is rejected");
  }
  if (!img_err_is(png_parse(mk_png(1, 1, 0, 0, 0, 0, 0, false)), at("png: invalid bit depth", 24))) {
    return assert(false, "gray depth 0 is rejected");
  }
  if (!img_err_is(png_parse(mk_png(1, 1, 8, 1, 0, 0, 0, false)), at("png: invalid color type", 25))) {
    return assert(false, "color type 1 is rejected");
  }
  if (!img_err_is(png_parse(mk_png(1, 1, 8, 5, 0, 0, 0, false)), at("png: invalid color type", 25))) {
    return assert(false, "color type 5 is rejected");
  }
  if (!img_err_is(png_parse(mk_png(1, 1, 8, 7, 0, 0, 0, false)), at("png: invalid color type", 25))) {
    return assert(false, "color type 7 is rejected");
  }
  let ok1 = mk_png(4, 4, 8, 2, 0, 0, 1, false);
  if (bad_img(png_parse(ok1))) { return assert(false, "interlace 1 is accepted"); }
  let img = ok_img(png_parse(ok1));
  if (png_interlace(img) != 1) { return assert(false, "interlace 1 decodes"); }
  return assert(true, "all 15 legal depth/color-type combos parse; illegal ones are rejected");
}

fn t3() -> TestResult {
  let empty = Vec[UInt8].new();
  if (!img_err_is(png_parse(empty), "png: truncated signature")) {
    return assert(false, "empty buffer is a truncated signature");
  }
  var seven = Vec[UInt8].new();
  seven.push(137 as UInt8);
  seven.push(80 as UInt8);
  seven.push(78 as UInt8);
  seven.push(71 as UInt8);
  seven.push(13 as UInt8);
  seven.push(10 as UInt8);
  seven.push(26 as UInt8);
  if (!img_err_is(png_parse(seven), "png: truncated signature")) {
    return assert(false, "7-byte buffer is a truncated signature");
  }
  var sigonly = Vec[UInt8].new();
  sig_bytes(&mut sigonly);
  if (!img_err_is(png_parse(sigonly), at("png: truncated chunk", 8))) {
    return assert(false, "signature-only buffer has no chunk");
  }
  var i = 0;
  while (i < 8) {
    let m = mk_png(1, 1, 8, 0, 0, 0, 0, false);
    m[i] = (((m[i] as Int) + 1) % 256) as UInt8;
    if (!img_err_is(png_parse(m), at("png: bad signature", i))) {
      return assert(false, "signature byte mutations report their offset");
    }
    i = i + 1;
  }
  return assert(true, "signature truncation and every mismatching byte offset are rejected");
}

fn t4() -> TestResult {
  var nf = Vec[UInt8].new();
  sig_bytes(&mut nf);
  var gp = Vec[UInt8].new();
  push_be32(&mut gp, 45455);
  push_chunk(&mut nf, 103, 65, 77, 65, gp);
  let ih0 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut nf, 73, 72, 68, 82, ih0);
  push_idat(&mut nf, 1, 1);
  push_iend(&mut nf);
  if (!img_err_is(png_parse(nf), at("png: missing IHDR", 8))) {
    return assert(false, "first chunk must be IHDR");
  }
  var l12 = Vec[UInt8].new();
  sig_bytes(&mut l12);
  let bad = raw_bytes(12, 0);
  push_chunk(&mut l12, 73, 72, 68, 82, bad);
  push_idat(&mut l12, 1, 1);
  push_iend(&mut l12);
  if (!img_err_is(png_parse(l12), at("png: invalid IHDR length", 8))) {
    return assert(false, "IHDR length 12 is rejected");
  }
  var dup = Vec[UInt8].new();
  sig_bytes(&mut dup);
  let ih1 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut dup, 73, 72, 68, 82, ih1);
  let ih2 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut dup, 73, 72, 68, 82, ih2);
  push_idat(&mut dup, 1, 1);
  push_iend(&mut dup);
  if (!img_err_is(png_parse(dup), at("png: duplicate IHDR", 33))) {
    return assert(false, "second IHDR is rejected");
  }
  if (!img_err_is(png_parse(mk_png(0, 1, 8, 0, 0, 0, 0, false)), at("png: invalid width", 16))) {
    return assert(false, "width 0 is rejected");
  }
  if (!img_err_is(png_parse(mk_png(1, 0, 8, 0, 0, 0, 0, false)), at("png: invalid height", 20))) {
    return assert(false, "height 0 is rejected");
  }
  if (!img_err_is(png_parse(mk_png(2147483648, 1, 8, 0, 0, 0, 0, false)), at("png: invalid width", 16))) {
    return assert(false, "width 2^31 is rejected");
  }
  if (!img_err_is(png_parse(mk_png(1, 1, 8, 0, 1, 0, 0, false)), at("png: invalid compression method", 26))) {
    return assert(false, "compression 1 is rejected");
  }
  if (!img_err_is(png_parse(mk_png(1, 1, 8, 0, 0, 1, 0, false)), at("png: invalid filter method", 27))) {
    return assert(false, "filter 1 is rejected");
  }
  if (!img_err_is(png_parse(mk_png(1, 1, 8, 0, 0, 0, 2, false)), at("png: invalid interlace method", 28))) {
    return assert(false, "interlace 2 is rejected");
  }
  return assert(true, "IHDR position, length, duplicate, dimensions and method bytes are validated");
}

fn t5() -> TestResult {
  let a = mk_png(1, 1, 8, 0, 0, 0, 0, false);
  a[16] = (((a[16] as Int) + 1) % 256) as UInt8;
  if (!img_err_is(png_parse(a), at("png: crc mismatch", 29))) {
    return assert(false, "IHDR payload corruption is a CRC mismatch at 29");
  }
  let b = mk_png(1, 1, 8, 0, 0, 0, 0, false);
  b[29] = (((b[29] as Int) + 1) % 256) as UInt8;
  if (!img_err_is(png_parse(b), at("png: crc mismatch", 29))) {
    return assert(false, "IHDR stored CRC corruption is a mismatch at 29");
  }
  let c = mk_png(1, 1, 8, 0, 0, 0, 0, false);
  c[41] = (((c[41] as Int) + 1) % 256) as UInt8;
  if (!img_err_is(png_parse(c), at("png: crc mismatch", 42))) {
    return assert(false, "IDAT payload corruption is a mismatch at 42");
  }
  let e = mk_png(1, 1, 8, 0, 0, 0, 0, false);
  e[45] = (((e[45] as Int) + 1) % 256) as UInt8;
  if (!img_err_is(png_parse(e), at("png: crc mismatch", 42))) {
    return assert(false, "IDAT stored CRC corruption is a mismatch at 42");
  }
  return assert(true, "CRC-32 mismatches are detected for IHDR and IDAT at the CRC field offset");
}

fn t6() -> TestResult {
  var nine = Vec[UInt8].new();
  sig_bytes(&mut nine);
  nine.push(1 as UInt8);
  if (!img_err_is(png_parse(nine), at("png: truncated chunk", 8))) {
    return assert(false, "9-byte buffer cannot hold a chunk header");
  }
  var cut = Vec[UInt8].new();
  sig_bytes(&mut cut);
  push_be32(&mut cut, 13);
  cut.push(73 as UInt8);
  cut.push(72 as UInt8);
  cut.push(68 as UInt8);
  cut.push(82 as UInt8);
  cut.push(0 as UInt8);
  cut.push(0 as UInt8);
  cut.push(0 as UInt8);
  cut.push(0 as UInt8);
  if (!img_err_is(png_parse(cut), at("png: truncated chunk", 8))) {
    return assert(false, "IHDR cut after 4 data bytes is truncated at 8");
  }
  var mid = Vec[UInt8].new();
  sig_bytes(&mut mid);
  let ih = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut mid, 73, 72, 68, 82, ih);
  push_be32(&mut mid, 5);
  mid.push(73 as UInt8);
  mid.push(68 as UInt8);
  mid.push(65 as UInt8);
  mid.push(84 as UInt8);
  mid.push(9 as UInt8);
  mid.push(9 as UInt8);
  if (!img_err_is(png_parse(mid), at("png: truncated chunk", 33))) {
    return assert(false, "IDAT cut inside its data is truncated at 33");
  }
  var hdr = Vec[UInt8].new();
  sig_bytes(&mut hdr);
  let ih2 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut hdr, 73, 72, 68, 82, ih2);
  push_be32(&mut hdr, 0);
  hdr.push(73 as UInt8);
  hdr.push(68 as UInt8);
  hdr.push(65 as UInt8);
  hdr.push(84 as UInt8);
  if (!img_err_is(png_parse(hdr), at("png: truncated chunk", 33))) {
    return assert(false, "missing CRC field is a truncated chunk at 33");
  }
  var noend = Vec[UInt8].new();
  sig_bytes(&mut noend);
  let ih3 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut noend, 73, 72, 68, 82, ih3);
  push_idat(&mut noend, 1, 4);
  if (!img_err_is(png_parse(noend), "png: missing IEND")) {
    return assert(false, "buffer ending after IDAT is missing IEND");
  }
  return assert(true, "truncated chunks and a missing IEND are rejected with offsets");
}

fn t7() -> TestResult {
  var extra = mk_png(1, 1, 8, 0, 0, 0, 0, false);
  extra.push(0 as UInt8);
  if (!img_err_is(png_parse(extra), at("png: data after IEND", 58))) {
    return assert(false, "a byte after IEND is rejected");
  }
  var badend = Vec[UInt8].new();
  sig_bytes(&mut badend);
  let ih = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut badend, 73, 72, 68, 82, ih);
  push_idat(&mut badend, 1, 4);
  let one = raw_bytes(1, 3);
  push_chunk(&mut badend, 73, 69, 78, 68, one);
  if (!img_err_is(png_parse(badend), at("png: invalid IEND length", 46))) {
    return assert(false, "IEND with data is rejected");
  }
  var noidat = Vec[UInt8].new();
  sig_bytes(&mut noidat);
  let ih2 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut noidat, 73, 72, 68, 82, ih2);
  push_iend(&mut noidat);
  if (!img_err_is(png_parse(noidat), "png: missing IDAT")) {
    return assert(false, "IHDR + IEND is missing IDAT");
  }
  var two_idat = Vec[UInt8].new();
  sig_bytes(&mut two_idat);
  let ih3 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut two_idat, 73, 72, 68, 82, ih3);
  push_idat(&mut two_idat, 1, 1);
  push_idat(&mut two_idat, 1, 2);
  push_iend(&mut two_idat);
  let img = ok_img(png_parse(two_idat));
  if (png_chunk_count(img) != 4) { return assert(false, "two IDAT chunks are accepted"); }
  if (png_chunk_length(img, 1) != 1) { return assert(false, "first IDAT length 1"); }
  if (png_chunk_length(img, 2) != 1) { return assert(false, "second IDAT length 1"); }
  var late = Vec[UInt8].new();
  sig_bytes(&mut late);
  let ih4 = ihdr_payload(1, 1, 8, 2, 0, 0, 0);
  push_chunk(&mut late, 73, 72, 68, 82, ih4);
  push_idat(&mut late, 1, 1);
  let pl = raw_bytes(3, 4);
  push_chunk(&mut late, 80, 76, 84, 69, pl);
  push_iend(&mut late);
  if (!img_err_is(png_parse(late), at("png: PLTE after IDAT", 46))) {
    return assert(false, "PLTE must precede IDAT");
  }
  return assert(true, "IEND terminator, missing IDAT and PLTE-before-IDAT ordering are enforced");
}

fn t8() -> TestResult {
  var zero = Vec[UInt8].new();
  sig_bytes(&mut zero);
  let ih = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut zero, 73, 72, 68, 82, ih);
  let none = Vec[UInt8].new();
  push_chunk(&mut zero, 122, 90, 90, 90, none);
  push_idat(&mut zero, 1, 1);
  let two = raw_bytes(2, 8);
  push_chunk(&mut zero, 112, 114, 86, 116, two);
  push_iend(&mut zero);
  let img = ok_img(png_parse(zero));
  if (png_chunk_count(img) != 5) { return assert(false, "unknown chunks are indexed"); }
  let s1: Str = png_chunk_type(img, 1);
  if (!streq(s1, "zZZZ")) { return assert(false, "zero-length unknown chunk type"); }
  if (png_chunk_length(img, 1) != 0) { return assert(false, "zero-length unknown chunk accepted"); }
  let s2: Str = png_chunk_type(img, 3);
  if (!streq(s2, "prVt")) { return assert(false, "unknown chunk after IDAT is indexed"); }
  if (png_chunk_length(img, 3) != 2) { return assert(false, "unknown chunk data length"); }
  var badcase = Vec[UInt8].new();
  sig_bytes(&mut badcase);
  push_be32(&mut badcase, 0);
  badcase.push(73 as UInt8);
  badcase.push(72 as UInt8);
  badcase.push(100 as UInt8);
  badcase.push(114 as UInt8);
  let badtype = badtype_bytes();
  push_be32(&mut badcase, png_crc32(badtype));
  if (!img_err_is(png_parse(badcase), at("png: invalid chunk type", 12))) {
    return assert(false, "lowercase reserved third byte is rejected");
  }
  var digitcase = Vec[UInt8].new();
  sig_bytes(&mut digitcase);
  push_be32(&mut digitcase, 0);
  digitcase.push(73 as UInt8);
  digitcase.push(72 as UInt8);
  digitcase.push(49 as UInt8);
  digitcase.push(82 as UInt8);
  let badtype2 = badtype_digit();
  push_be32(&mut digitcase, png_crc32(badtype2));
  if (!img_err_is(png_parse(digitcase), at("png: invalid chunk type", 12))) {
    return assert(false, "digit in a chunk type is rejected");
  }
  return assert(true, "unknown chunks are indexed; invalid type bytes are rejected");
}

// Helper byte vectors for the invalid-type cases in t8.
fn badtype_bytes() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(73 as UInt8);
  v.push(72 as UInt8);
  v.push(100 as UInt8);
  v.push(114 as UInt8);
  return v;
}

fn badtype_digit() -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  v.push(73 as UInt8);
  v.push(72 as UInt8);
  v.push(49 as UInt8);
  v.push(82 as UInt8);
  return v;
}

fn t9() -> TestResult {
  let base = mk_png(2, 2, 4, 3, 0, 0, 0, true);
  let img = ok_img(png_parse(base));
  if (!png_has_palette(img)) { return assert(false, "palette present"); }
  if (png_palette_entries(img) != 1) { return assert(false, "one palette entry"); }
  if (png_palette_byte(img, 0) != 1) { return assert(false, "palette r"); }
  if (png_palette_byte(img, 1) != 2) { return assert(false, "palette g"); }
  if (png_palette_byte(img, 2) != 3) { return assert(false, "palette b"); }
  if (png_palette_byte(img, 3) != -1) { return assert(false, "palette byte out of range"); }
  var late = Vec[UInt8].new();
  sig_bytes(&mut late);
  let ih = ihdr_payload(2, 2, 4, 3, 0, 0, 0);
  push_chunk(&mut late, 73, 72, 68, 82, ih);
  push_idat(&mut late, 1, 1);
  let pl = raw_bytes(3, 1);
  push_chunk(&mut late, 80, 76, 84, 69, pl);
  push_iend(&mut late);
  if (!img_err_is(png_parse(late), at("png: PLTE after IDAT", 46))) {
    return assert(false, "PLTE after IDAT is rejected");
  }
  var dup = Vec[UInt8].new();
  sig_bytes(&mut dup);
  let ih2 = ihdr_payload(1, 1, 8, 2, 0, 0, 0);
  push_chunk(&mut dup, 73, 72, 68, 82, ih2);
  let pl1 = raw_bytes(3, 1);
  push_chunk(&mut dup, 80, 76, 84, 69, pl1);
  let pl2 = raw_bytes(3, 2);
  push_chunk(&mut dup, 80, 76, 84, 69, pl2);
  push_idat(&mut dup, 1, 1);
  push_iend(&mut dup);
  if (!img_err_is(png_parse(dup), at("png: duplicate PLTE", 48))) {
    return assert(false, "second PLTE is rejected");
  }
  if (!img_err_is(png_parse(mk_with_plte(2, 8, 0, 1)), at("png: invalid PLTE length", 33))) {
    return assert(false, "empty PLTE is rejected");
  }
  if (!img_err_is(png_parse(mk_with_plte(2, 8, 2, 1)), at("png: invalid PLTE length", 33))) {
    return assert(false, "PLTE length 2 is rejected");
  }
  if (!img_err_is(png_parse(mk_with_plte(2, 8, 4, 1)), at("png: invalid PLTE length", 33))) {
    return assert(false, "PLTE length 4 is rejected");
  }
  if (!img_err_is(png_parse(mk_with_plte(0, 8, 3, 1)), at("png: PLTE not allowed", 33))) {
    return assert(false, "PLTE is forbidden for grayscale");
  }
  if (!img_err_is(png_parse(mk_with_plte(4, 8, 3, 1)), at("png: PLTE not allowed", 33))) {
    return assert(false, "PLTE is forbidden for gray+alpha");
  }
  if (!img_err_is(png_parse(mk_with_plte(3, 1, 9, 1)), at("png: PLTE too large for bit depth", 33))) {
    return assert(false, "3 entries exceed bit depth 1");
  }
  var after_trns = Vec[UInt8].new();
  sig_bytes(&mut after_trns);
  let ih3 = ihdr_payload(1, 1, 8, 2, 0, 0, 0);
  push_chunk(&mut after_trns, 73, 72, 68, 82, ih3);
  let tr = raw_bytes(6, 5);
  push_chunk(&mut after_trns, 116, 82, 78, 83, tr);
  let pl3 = raw_bytes(3, 6);
  push_chunk(&mut after_trns, 80, 76, 84, 69, pl3);
  push_idat(&mut after_trns, 1, 1);
  push_iend(&mut after_trns);
  if (!img_err_is(png_parse(after_trns), at("png: PLTE after tRNS", 51))) {
    return assert(false, "PLTE after tRNS is rejected");
  }
  if (!img_err_is(png_parse(mk_png(1, 1, 8, 3, 0, 0, 0, false)), "png: missing PLTE")) {
    return assert(false, "indexed image without PLTE is rejected");
  }
  return assert(true, "PLTE length, allowance, ordering, duplicates and bit-depth capacity are enforced");
}

fn t10() -> TestResult {
  let ok3 = mk_with_trns(3, 4, 6, 2, 1);
  let img = ok_img(png_parse(ok3));
  if (!png_has_trns(img)) { return assert(false, "tRNS present"); }
  if (png_trns_len(img) != 2) { return assert(false, "tRNS length 2"); }
  if (png_palette_entries(img) != 2) { return assert(false, "PLTE has two entries"); }
  var before = Vec[UInt8].new();
  sig_bytes(&mut before);
  let ih = ihdr_payload(1, 1, 4, 3, 0, 0, 0);
  push_chunk(&mut before, 73, 72, 68, 82, ih);
  let tr0 = raw_bytes(2, 2);
  push_chunk(&mut before, 116, 82, 78, 83, tr0);
  let pl = raw_bytes(6, 3);
  push_chunk(&mut before, 80, 76, 84, 69, pl);
  push_idat(&mut before, 1, 1);
  push_iend(&mut before);
  if (!img_err_is(png_parse(before), at("png: tRNS before PLTE", 33))) {
    return assert(false, "indexed tRNS before PLTE is rejected");
  }
  if (!img_err_is(png_parse(mk_with_trns(3, 4, 6, 3, 1)), at("png: invalid tRNS length", 51))) {
    return assert(false, "tRNS longer than the palette is rejected");
  }
  if (!img_err_is(png_parse(mk_with_trns(3, 4, 6, 0, 1)), at("png: invalid tRNS length", 51))) {
    return assert(false, "zero-length indexed tRNS is rejected");
  }
  let gray = ok_img(png_parse(mk_with_trns(0, 8, 0, 2, 1)));
  if (png_trns_len(gray) != 2) { return assert(false, "gray tRNS stores 2 bytes"); }
  if (!img_err_is(png_parse(mk_with_trns(0, 8, 0, 3, 1)), at("png: invalid tRNS length", 33))) {
    return assert(false, "gray tRNS must be 2 bytes");
  }
  let rgb = ok_img(png_parse(mk_with_trns(2, 8, 0, 6, 1)));
  if (png_trns_len(rgb) != 6) { return assert(false, "truecolor tRNS stores 6 bytes"); }
  if (!img_err_is(png_parse(mk_with_trns(2, 8, 0, 2, 1)), at("png: invalid tRNS length", 33))) {
    return assert(false, "truecolor tRNS must be 6 bytes");
  }
  if (!img_err_is(png_parse(mk_with_trns(6, 8, 0, 2, 1)), at("png: tRNS not allowed", 33))) {
    return assert(false, "RGBA forbids tRNS");
  }
  var dup = Vec[UInt8].new();
  sig_bytes(&mut dup);
  let ih2 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut dup, 73, 72, 68, 82, ih2);
  let t1 = raw_bytes(2, 1);
  push_chunk(&mut dup, 116, 82, 78, 83, t1);
  let t2 = raw_bytes(2, 2);
  push_chunk(&mut dup, 116, 82, 78, 83, t2);
  push_idat(&mut dup, 1, 1);
  push_iend(&mut dup);
  if (!img_err_is(png_parse(dup), at("png: duplicate tRNS", 47))) {
    return assert(false, "second tRNS is rejected");
  }
  var late = Vec[UInt8].new();
  sig_bytes(&mut late);
  let ih3 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut late, 73, 72, 68, 82, ih3);
  push_idat(&mut late, 1, 1);
  let t3 = raw_bytes(2, 3);
  push_chunk(&mut late, 116, 82, 78, 83, t3);
  push_iend(&mut late);
  if (!img_err_is(png_parse(late), at("png: tRNS after IDAT", 46))) {
    return assert(false, "tRNS after IDAT is rejected");
  }
  return assert(true, "tRNS allowance, per-type lengths, duplicates and ordering are enforced");
}

fn t11() -> TestResult {
  var g = Vec[UInt8].new();
  sig_bytes(&mut g);
  let ih = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut g, 73, 72, 68, 82, ih);
  var gv = Vec[UInt8].new();
  push_be32(&mut gv, 45455);
  push_chunk(&mut g, 103, 65, 77, 65, gv);
  push_idat(&mut g, 1, 1);
  push_iend(&mut g);
  let img = ok_img(png_parse(g));
  if (png_gamma(img) != 45455) { return assert(false, "gAMA value decodes"); }
  var g3 = Vec[UInt8].new();
  g3.push(0 as UInt8);
  g3.push(0 as UInt8);
  g3.push(1 as UInt8);
  if (!img_err_is(png_parse(mk_with_meta(103, 65, 77, 65, g3)), at("png: invalid gAMA length", 33))) {
    return assert(false, "gAMA length 3 is rejected");
  }
  var g0 = Vec[UInt8].new();
  push_be32(&mut g0, 0);
  if (!img_err_is(png_parse(mk_with_meta(103, 65, 77, 65, g0)), at("png: invalid gAMA value", 41))) {
    return assert(false, "gAMA value 0 is rejected");
  }
  var p = Vec[UInt8].new();
  sig_bytes(&mut p);
  let ih2 = ihdr_payload(1, 1, 8, 2, 0, 0, 0);
  push_chunk(&mut p, 73, 72, 68, 82, ih2);
  let pl = raw_bytes(3, 1);
  push_chunk(&mut p, 80, 76, 84, 69, pl);
  var gv2 = Vec[UInt8].new();
  push_be32(&mut gv2, 45455);
  push_chunk(&mut p, 103, 65, 77, 65, gv2);
  push_idat(&mut p, 1, 1);
  push_iend(&mut p);
  if (!img_err_is(png_parse(p), at("png: gAMA after PLTE or IDAT", 48))) {
    return assert(false, "gAMA after PLTE is rejected");
  }
  var gd = Vec[UInt8].new();
  sig_bytes(&mut gd);
  let ih3 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut gd, 73, 72, 68, 82, ih3);
  var gv3 = Vec[UInt8].new();
  push_be32(&mut gv3, 100000);
  push_chunk(&mut gd, 103, 65, 77, 65, gv3);
  var gv4 = Vec[UInt8].new();
  push_be32(&mut gv4, 100000);
  push_chunk(&mut gd, 103, 65, 77, 65, gv4);
  push_idat(&mut gd, 1, 1);
  push_iend(&mut gd);
  if (!img_err_is(png_parse(gd), at("png: duplicate gAMA", 49))) {
    return assert(false, "second gAMA is rejected");
  }
  var ph = Vec[UInt8].new();
  sig_bytes(&mut ph);
  let ih4 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut ph, 73, 72, 68, 82, ih4);
  var pv = Vec[UInt8].new();
  push_be32(&mut pv, 2835);
  push_be32(&mut pv, 2835);
  pv.push(1 as UInt8);
  push_chunk(&mut ph, 112, 72, 89, 115, pv);
  push_idat(&mut ph, 1, 1);
  push_iend(&mut ph);
  let pimg = ok_img(png_parse(ph));
  if (png_phys_x(pimg) != 2835) { return assert(false, "pHYs x decodes"); }
  if (png_phys_y(pimg) != 2835) { return assert(false, "pHYs y decodes"); }
  if (png_phys_unit(pimg) != 1) { return assert(false, "pHYs unit decodes"); }
  let p8 = raw_bytes(8, 1);
  if (!img_err_is(png_parse(mk_with_meta(112, 72, 89, 115, p8)), at("png: invalid pHYs length", 33))) {
    return assert(false, "pHYs length 8 is rejected");
  }
  let pu = raw_bytes(9, 1);
  pu[8] = 2 as UInt8;
  if (!img_err_is(png_parse(mk_with_meta(112, 72, 89, 115, pu)), at("png: invalid pHYs unit", 49))) {
    return assert(false, "pHYs unit 2 is rejected");
  }
  var s = Vec[UInt8].new();
  sig_bytes(&mut s);
  let ih5 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut s, 73, 72, 68, 82, ih5);
  var sv = Vec[UInt8].new();
  sv.push(3 as UInt8);
  push_chunk(&mut s, 115, 82, 71, 66, sv);
  push_idat(&mut s, 1, 1);
  push_iend(&mut s);
  let simg = ok_img(png_parse(s));
  if (png_srgb_intent(simg) != 3) { return assert(false, "sRGB intent decodes"); }
  let s2 = Vec[UInt8].new();
  s2.push(0 as UInt8);
  s2.push(0 as UInt8);
  if (!img_err_is(png_parse(mk_with_meta(115, 82, 71, 66, s2)), at("png: invalid sRGB length", 33))) {
    return assert(false, "sRGB length 2 is rejected");
  }
  let s4 = Vec[UInt8].new();
  s4.push(4 as UInt8);
  if (!img_err_is(png_parse(mk_with_meta(115, 82, 71, 66, s4)), at("png: invalid sRGB intent", 41))) {
    return assert(false, "sRGB intent 4 is rejected");
  }
  var sd = Vec[UInt8].new();
  sig_bytes(&mut sd);
  let ih6 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut sd, 73, 72, 68, 82, ih6);
  var s1 = Vec[UInt8].new();
  s1.push(0 as UInt8);
  push_chunk(&mut sd, 115, 82, 71, 66, s1);
  var s1b = Vec[UInt8].new();
  s1b.push(0 as UInt8);
  push_chunk(&mut sd, 115, 82, 71, 66, s1b);
  push_idat(&mut sd, 1, 1);
  push_iend(&mut sd);
  if (!img_err_is(png_parse(sd), at("png: duplicate sRGB", 46))) {
    return assert(false, "second sRGB is rejected");
  }
  var sl = Vec[UInt8].new();
  sig_bytes(&mut sl);
  let ih7 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut sl, 73, 72, 68, 82, ih7);
  push_idat(&mut sl, 1, 1);
  var s1c = Vec[UInt8].new();
  s1c.push(0 as UInt8);
  push_chunk(&mut sl, 115, 82, 71, 66, s1c);
  push_iend(&mut sl);
  if (!img_err_is(png_parse(sl), at("png: sRGB after PLTE or IDAT", 46))) {
    return assert(false, "sRGB after IDAT is rejected");
  }
  return assert(true, "gAMA, pHYs and sRGB values, lengths, ordering and duplicates are validated");
}

fn t12() -> TestResult {
  let d = mk_with_text(0, text_payload("Comment", "hello world"));
  let img = ok_img(png_parse(d));
  if (png_text_count(img) != 1) { return assert(false, "one text entry"); }
  if (png_text_kind(img, 0) != 0) { return assert(false, "tEXt kind is 0"); }
  if (png_text_compressed(img, 0) != 0) { return assert(false, "tEXt is uncompressed"); }
  if (png_text_method(img, 0) != 0) { return assert(false, "tEXt method 0"); }
  let kw: Str = png_text_keyword(img, 0);
  if (!streq(kw, "Comment")) { return assert(false, "tEXt keyword decodes"); }
  let tv: Str = png_text_value(img, 0);
  if (string.str_len(tv) != 11) { return assert(false, "tEXt text is 11 bytes"); }
  if (png_text_offset(img, 0) != 41) { return assert(false, "tEXt data offset 41"); }
  if (png_text_length(img, 0) != 19) { return assert(false, "tEXt data length 19"); }
  var empty_text = Vec[UInt8].new();
  empty_text.push(107 as UInt8);
  empty_text.push(0 as UInt8);
  let e2 = ok_img(png_parse(mk_with_text(0, empty_text)));
  let ev: Str = png_text_value(e2, 0);
  if (string.str_len(ev) != 0) { return assert(false, "empty tEXt text is accepted"); }
  var kw79 = Vec[UInt8].new();
  var i = 0;
  while (i < 79) {
    kw79.push(97 as UInt8);
    i = i + 1;
  }
  kw79.push(0 as UInt8);
  if (bad_img(png_parse(mk_with_text(0, kw79)))) {
    return assert(false, "79-byte keyword is accepted");
  }
  var kw80 = Vec[UInt8].new();
  i = 0;
  while (i < 80) {
    kw80.push(97 as UInt8);
    i = i + 1;
  }
  kw80.push(0 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(0, kw80)), at("png: invalid text keyword", 41))) {
    return assert(false, "80-byte keyword is rejected");
  }
  var nosep = Vec[UInt8].new();
  nosep.push(107 as UInt8);
  nosep.push(108 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(0, nosep)), at("png: missing keyword separator", 41))) {
    return assert(false, "keyword without separator is rejected");
  }
  var emptykw = Vec[UInt8].new();
  emptykw.push(0 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(0, emptykw)), at("png: invalid text keyword", 41))) {
    return assert(false, "empty keyword is rejected");
  }
  var ctrl = Vec[UInt8].new();
  ctrl.push(107 as UInt8);
  ctrl.push(0 as UInt8);
  ctrl.push(31 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(0, ctrl)), at("png: invalid text", 43))) {
    return assert(false, "control byte in text is rejected");
  }
  var nul = Vec[UInt8].new();
  nul.push(107 as UInt8);
  nul.push(0 as UInt8);
  nul.push(97 as UInt8);
  nul.push(0 as UInt8);
  nul.push(98 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(0, nul)), at("png: invalid text", 43))) {
    return assert(false, "NUL in text is rejected");
  }
  var tab = Vec[UInt8].new();
  tab.push(107 as UInt8);
  tab.push(0 as UInt8);
  tab.push(9 as UInt8);
  if (bad_img(png_parse(mk_with_text(0, tab)))) {
    return assert(false, "TAB in text is accepted");
  }
  var latin = Vec[UInt8].new();
  latin.push(107 as UInt8);
  latin.push(0 as UInt8);
  latin.push(255 as UInt8);
  if (bad_img(png_parse(mk_with_text(0, latin)))) {
    return assert(false, "Latin-1 byte 0xFF in text is accepted");
  }
  var badkw = Vec[UInt8].new();
  badkw.push(128 as UInt8);
  badkw.push(0 as UInt8);
  badkw.push(88 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(0, badkw)), at("png: invalid text keyword", 41))) {
    return assert(false, "0x80 in a keyword is rejected");
  }
  var late = Vec[UInt8].new();
  sig_bytes(&mut late);
  let ih = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut late, 73, 72, 68, 82, ih);
  push_idat(&mut late, 1, 5);
  let tp = text_payload("K", "V");
  push_chunk(&mut late, 116, 69, 88, 116, tp);
  push_iend(&mut late);
  let limg = ok_img(png_parse(late));
  if (png_text_count(limg) != 1) { return assert(false, "text after IDAT is indexed"); }
  return assert(true, "tEXt keyword/text validation, NUL safety and post-IDAT placement hold");
}

fn t13() -> TestResult {
  var z = Vec[UInt8].new();
  z.push(67 as UInt8);
  z.push(111 as UInt8);
  z.push(109 as UInt8);
  z.push(109 as UInt8);
  z.push(101 as UInt8);
  z.push(110 as UInt8);
  z.push(116 as UInt8);
  z.push(0 as UInt8);
  z.push(0 as UInt8);
  z.push(120 as UInt8);
  z.push(156 as UInt8);
  z.push(0 as UInt8);
  z.push(1 as UInt8);
  let img = ok_img(png_parse(mk_with_text(1, z)));
  if (png_text_count(img) != 1) { return assert(false, "one zTXt entry"); }
  if (png_text_kind(img, 0) != 1) { return assert(false, "zTXt kind is 1"); }
  if (png_text_compressed(img, 0) != 1) { return assert(false, "zTXt is compressed"); }
  if (png_text_method(img, 0) != 0) { return assert(false, "zTXt method 0"); }
  let kw: Str = png_text_keyword(img, 0);
  if (!streq(kw, "Comment")) { return assert(false, "zTXt keyword decodes"); }
  let tv: Str = png_text_value(img, 0);
  if (string.str_len(tv) != 0) { return assert(false, "zTXt text is not built from binary"); }
  var m1 = Vec[UInt8].new();
  m1.push(107 as UInt8);
  m1.push(0 as UInt8);
  m1.push(1 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(1, m1)), at("png: invalid zTXt method", 43))) {
    return assert(false, "zTXt method 1 is rejected");
  }
  var mnone = Vec[UInt8].new();
  mnone.push(107 as UInt8);
  mnone.push(0 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(1, mnone)), at("png: invalid zTXt method", 43))) {
    return assert(false, "missing zTXt method is rejected");
  }
  var nosep = Vec[UInt8].new();
  nosep.push(107 as UInt8);
  nosep.push(108 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(1, nosep)), at("png: missing keyword separator", 41))) {
    return assert(false, "zTXt keyword without separator is rejected");
  }
  var zero = Vec[UInt8].new();
  if (!img_err_is(png_parse(mk_with_text(1, zero)), at("png: missing keyword separator", 41))) {
    return assert(false, "empty zTXt payload is rejected");
  }
  var badkw = Vec[UInt8].new();
  badkw.push(1 as UInt8);
  badkw.push(0 as UInt8);
  badkw.push(0 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(1, badkw)), at("png: invalid text keyword", 41))) {
    return assert(false, "zTXt keyword validation is shared with tEXt");
  }
  return assert(true, "zTXt method validation and binary-safe text storage hold");
}

fn t14() -> TestResult {
  var good = Vec[UInt8].new();
  good.push(67 as UInt8);
  good.push(111 as UInt8);
  good.push(109 as UInt8);
  good.push(109 as UInt8);
  good.push(101 as UInt8);
  good.push(110 as UInt8);
  good.push(116 as UInt8);
  good.push(0 as UInt8);
  good.push(0 as UInt8);
  good.push(0 as UInt8);
  good.push(101 as UInt8);
  good.push(110 as UInt8);
  good.push(0 as UInt8);
  good.push(72 as UInt8);
  good.push(105 as UInt8);
  good.push(0 as UInt8);
  good.push(104 as UInt8);
  good.push(195 as UInt8);
  good.push(169 as UInt8);
  good.push(108 as UInt8);
  good.push(108 as UInt8);
  good.push(111 as UInt8);
  let img = ok_img(png_parse(mk_with_text(2, good)));
  if (png_text_kind(img, 0) != 2) { return assert(false, "iTXt kind is 2"); }
  if (png_text_compressed(img, 0) != 0) { return assert(false, "iTXt flag 0"); }
  let lang: Str = png_text_language(img, 0);
  if (!streq(lang, "en")) { return assert(false, "language tag decodes"); }
  let trk: Str = png_text_translated(img, 0);
  if (!streq(trk, "Hi")) { return assert(false, "translated keyword decodes"); }
  let tv: Str = png_text_value(img, 0);
  if (string.str_len(tv) != 6) { return assert(false, "UTF-8 text is 6 bytes"); }
  var comp = Vec[UInt8].new();
  comp.push(107 as UInt8);
  comp.push(0 as UInt8);
  comp.push(1 as UInt8);
  comp.push(0 as UInt8);
  comp.push(0 as UInt8);
  comp.push(0 as UInt8);
  comp.push(120 as UInt8);
  comp.push(156 as UInt8);
  comp.push(0 as UInt8);
  let cimg = ok_img(png_parse(mk_with_text(2, comp)));
  if (png_text_compressed(cimg, 0) != 1) { return assert(false, "iTXt compressed flag 1"); }
  let cv: Str = png_text_value(cimg, 0);
  if (string.str_len(cv) != 0) { return assert(false, "compressed iTXt text is not built"); }
  var flag2 = Vec[UInt8].new();
  flag2.push(107 as UInt8);
  flag2.push(0 as UInt8);
  flag2.push(2 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(2, flag2)), at("png: invalid iTXt flag", 43))) {
    return assert(false, "iTXt flag 2 is rejected");
  }
  var m1 = Vec[UInt8].new();
  m1.push(107 as UInt8);
  m1.push(0 as UInt8);
  m1.push(1 as UInt8);
  m1.push(1 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(2, m1)), at("png: invalid iTXt method", 44))) {
    return assert(false, "iTXt method 1 is rejected");
  }
  var nolang = Vec[UInt8].new();
  nolang.push(107 as UInt8);
  nolang.push(0 as UInt8);
  nolang.push(1 as UInt8);
  nolang.push(0 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(2, nolang)), at("png: missing language separator", 45))) {
    return assert(false, "missing language separator is rejected");
  }
  var badlang = Vec[UInt8].new();
  badlang.push(107 as UInt8);
  badlang.push(0 as UInt8);
  badlang.push(0 as UInt8);
  badlang.push(0 as UInt8);
  badlang.push(1 as UInt8);
  badlang.push(0 as UInt8);
  badlang.push(0 as UInt8);
  badlang.push(0 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(2, badlang)), at("png: invalid iTXt language tag", 45))) {
    return assert(false, "control byte in the language tag is rejected");
  }
  var badtr = Vec[UInt8].new();
  badtr.push(107 as UInt8);
  badtr.push(0 as UInt8);
  badtr.push(0 as UInt8);
  badtr.push(0 as UInt8);
  badtr.push(101 as UInt8);
  badtr.push(110 as UInt8);
  badtr.push(0 as UInt8);
  badtr.push(255 as UInt8);
  badtr.push(0 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(2, badtr)), at("png: invalid iTXt translated keyword", 48))) {
    return assert(false, "invalid UTF-8 translated keyword is rejected");
  }
  var badtext = Vec[UInt8].new();
  badtext.push(107 as UInt8);
  badtext.push(0 as UInt8);
  badtext.push(0 as UInt8);
  badtext.push(0 as UInt8);
  badtext.push(101 as UInt8);
  badtext.push(110 as UInt8);
  badtext.push(0 as UInt8);
  badtext.push(72 as UInt8);
  badtext.push(105 as UInt8);
  badtext.push(0 as UInt8);
  badtext.push(195 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(2, badtext)), at("png: invalid text", 51))) {
    return assert(false, "invalid UTF-8 text is rejected");
  }
  var nultext = Vec[UInt8].new();
  nultext.push(107 as UInt8);
  nultext.push(0 as UInt8);
  nultext.push(0 as UInt8);
  nultext.push(0 as UInt8);
  nultext.push(101 as UInt8);
  nultext.push(110 as UInt8);
  nultext.push(0 as UInt8);
  nultext.push(72 as UInt8);
  nultext.push(105 as UInt8);
  nultext.push(0 as UInt8);
  nultext.push(97 as UInt8);
  nultext.push(0 as UInt8);
  nultext.push(98 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(2, nultext)), at("png: invalid text", 51))) {
    return assert(false, "NUL in iTXt text is rejected");
  }
  var nosep = Vec[UInt8].new();
  nosep.push(107 as UInt8);
  nosep.push(108 as UInt8);
  if (!img_err_is(png_parse(mk_with_text(2, nosep)), at("png: missing keyword separator", 41))) {
    return assert(false, "iTXt keyword without separator is rejected");
  }
  return assert(true, "iTXt flag, method, language, translated keyword and UTF-8 text are validated");
}

fn t15() -> TestResult {
  var out = Vec[UInt8].new();
  sig_bytes(&mut out);
  let ih = ihdr_payload(4, 3, 8, 2, 0, 0, 0);
  push_chunk(&mut out, 73, 72, 68, 82, ih);
  let pl = raw_bytes(3, 1);
  push_chunk(&mut out, 80, 76, 84, 69, pl);
  let tp = text_payload("K", "V");
  push_chunk(&mut out, 116, 69, 88, 116, tp);
  push_idat(&mut out, 2, 4);
  push_iend(&mut out);
  let img = ok_img(png_parse(out));
  if (png_chunk_count(img) != 5) { return assert(false, "five chunks"); }
  var i = 0;
  while (i + 1 < png_chunk_count(img)) {
    let off: Int = png_chunk_offset(img, i);
    let len: Int = png_chunk_length(img, i);
    if (png_chunk_offset(img, i + 1) != off + 12 + len) {
      return assert(false, "chunk offsets chain contiguously");
    }
    if (png_chunk_data_offset(img, i) != off + 8) {
      return assert(false, "chunk data offset is chunk offset + 8");
    }
    i = i + 1;
  }
  let last: Int = png_chunk_count(img) - 1;
  let last_off: Int = png_chunk_offset(img, last);
  let last_len: Int = png_chunk_length(img, last);
  if (png_chunk_data_offset(img, last) != last_off + 8) {
    return assert(false, "last chunk data offset");
  }
  if (last_off + 12 + last_len != out.len()) {
    return assert(false, "last chunk ends the buffer");
  }
  if (png_chunk_offset(img, -1) != -1) { return assert(false, "negative chunk index"); }
  if (png_chunk_length(img, 99) != -1) { return assert(false, "chunk index above count"); }
  if (png_chunk_data_offset(img, 99) != -1) { return assert(false, "data offset above count"); }
  if (png_chunk_crc(img, 99) != -1) { return assert(false, "crc above count"); }
  let none: Str = png_chunk_type(img, 99);
  if (string.str_len(none) != 0) { return assert(false, "type above count is empty"); }
  if (!png_has_palette(img)) { return assert(false, "fixture has a palette"); }
  if (png_palette_byte(img, -1) != -1) { return assert(false, "palette negative index"); }
  if (png_gamma(img) != -1) { return assert(false, "absent gAMA is -1"); }
  if (png_phys_x(img) != -1) { return assert(false, "absent pHYs is -1"); }
  if (png_phys_unit(img) != -1) { return assert(false, "absent pHYs unit is -1"); }
  if (png_srgb_intent(img) != -1) { return assert(false, "absent sRGB is -1"); }
  if (png_text_count(img) != 1) { return assert(false, "one text entry in the chain fixture"); }
  if (png_text_kind(img, -1) != -1) { return assert(false, "negative text index"); }
  if (png_text_kind(img, 1) != -1) { return assert(false, "text index above count"); }
  if (png_text_offset(img, 0) != 56) { return assert(false, "tEXt data offset 56"); }
  if (png_text_length(img, 0) != 3) { return assert(false, "tEXt data length 3"); }
  let lang: Str = png_text_language(img, 0);
  if (string.str_len(lang) != 0) { return assert(false, "tEXt language is empty"); }
  let tr: Str = png_text_translated(img, 0);
  if (string.str_len(tr) != 0) { return assert(false, "tEXt translated is empty"); }
  if (png_text_compressed(img, 99) != -1) { return assert(false, "text compressed out of range"); }
  if (png_text_method(img, 99) != -1) { return assert(false, "text method out of range"); }
  let tkw: Str = png_text_keyword(img, 99);
  if (string.str_len(tkw) != 0) { return assert(false, "keyword above count is empty"); }
  let tvl: Str = png_text_value(img, 99);
  if (string.str_len(tvl) != 0) { return assert(false, "value above count is empty"); }
  let tl: Str = png_text_language(img, 99);
  if (string.str_len(tl) != 0) { return assert(false, "language above count is empty"); }
  let tt: Str = png_text_translated(img, 99);
  if (string.str_len(tt) != 0) { return assert(false, "translated above count is empty"); }
  if (png_text_offset(img, 99) != -1) { return assert(false, "text offset above count"); }
  if (png_text_length(img, 99) != -1) { return assert(false, "text length above count"); }
  return assert(true, "accessor sentinels and the contiguous offset chain are exact");
}

fn t16() -> TestResult {
  var d = Vec[UInt8].new();
  sig_bytes(&mut d);
  let ih = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut d, 73, 72, 68, 82, ih);
  push_idat(&mut d, 0, 0);
  push_iend(&mut d);
  let img = ok_img(png_parse(d));
  if (png_chunk_count(img) != 3) { return assert(false, "zero-length IDAT parses"); }
  if (png_chunk_length(img, 1) != 0) { return assert(false, "IDAT length is 0"); }
  var d2 = Vec[UInt8].new();
  sig_bytes(&mut d2);
  let ih2 = ihdr_payload(1, 1, 8, 0, 0, 0, 0);
  push_chunk(&mut d2, 73, 72, 68, 82, ih2);
  push_idat(&mut d2, 0, 0);
  push_idat(&mut d2, 1, 3);
  push_iend(&mut d2);
  let img2 = ok_img(png_parse(d2));
  if (png_chunk_count(img2) != 4) { return assert(false, "empty IDAT before a data IDAT"); }
  if (png_chunk_length(img2, 1) != 0) { return assert(false, "first IDAT is empty"); }
  if (png_chunk_length(img2, 2) != 1) { return assert(false, "second IDAT has one byte"); }
  let none = Vec[UInt8].new();
  let t0 = mk_with_text(0, none);
  if (!img_err_is(png_parse(t0), at("png: missing keyword separator", 41))) {
    return assert(false, "zero-length tEXt payload is rejected");
  }
  let t1 = mk_with_text(1, none);
  if (!img_err_is(png_parse(t1), at("png: missing keyword separator", 41))) {
    return assert(false, "zero-length zTXt payload is rejected");
  }
  let t2 = mk_with_text(2, none);
  if (!img_err_is(png_parse(t2), at("png: missing keyword separator", 41))) {
    return assert(false, "zero-length iTXt payload is rejected");
  }
  if (!img_err_is(png_parse(mk_with_plte(2, 8, 0, 1)), at("png: invalid PLTE length", 33))) {
    return assert(false, "zero-length PLTE payload is rejected");
  }
  if (!img_err_is(png_parse(mk_with_trns(0, 8, 0, 0, 1)), at("png: invalid tRNS length", 33))) {
    return assert(false, "zero-length gray tRNS is rejected");
  }
  return assert(true, "zero-length chunks are legal only where the spec allows them");
}

fn t17() -> TestResult {
  if (png_max_chunk_length() != 2147483647) {
    return assert(false, "max chunk length is 2^31 - 1");
  }
  if (png_chunk_header_size() != 8) { return assert(false, "chunk header is 8 bytes"); }
  if (png_chunk_crc_size() != 4) { return assert(false, "chunk CRC is 4 bytes"); }
  if (png_text_kind_text() != 0) { return assert(false, "tEXt kind constant"); }
  if (png_text_kind_ztxt() != 1) { return assert(false, "zTXt kind constant"); }
  if (png_text_kind_itxt() != 2) { return assert(false, "iTXt kind constant"); }
  var check = Vec[UInt8].new();
  var k = 49;
  while (k <= 57) {
    check.push(k as UInt8);
    k = k + 1;
  }
  if (png_crc32(check) != 3421780262) {
    return assert(false, "CRC-32 check value of 123456789 is 0xCBF43926");
  }
  var zero = Vec[UInt8].new();
  if (png_crc32(zero) != 0) { return assert(false, "CRC-32 of empty input is 0"); }
  let base = mk_png(1, 1, 8, 0, 0, 0, 0, false);
  if (png_chunk_crc(ok_img(png_parse(base)), 1) != chunk_crc_of(base, 33, 1)) {
    return assert(false, "IDAT CRC matches the stored value");
  }
  let huge = mk_png(1, 1, 8, 0, 0, 0, 0, false);
  huge[33] = 127 as UInt8;
  huge[34] = 255 as UInt8;
  huge[35] = 255 as UInt8;
  huge[36] = 255 as UInt8;
  if (!img_err_is(png_parse(huge), at("png: truncated chunk", 33))) {
    return assert(false, "2^31-1 length in a tiny buffer is truncation, not overflow");
  }
  let over = mk_png(1, 1, 8, 0, 0, 0, 0, false);
  over[33] = 128 as UInt8;
  over[34] = 0 as UInt8;
  over[35] = 0 as UInt8;
  over[36] = 0 as UInt8;
  if (!img_err_is(png_parse(over), at("png: chunk length overflow", 33))) {
    return assert(false, "2^31 length is rejected before any arithmetic");
  }
  let maxv = mk_png(1, 1, 8, 0, 0, 0, 0, false);
  maxv[33] = 255 as UInt8;
  maxv[34] = 255 as UInt8;
  maxv[35] = 255 as UInt8;
  maxv[36] = 255 as UInt8;
  if (!img_err_is(png_parse(maxv), at("png: chunk length overflow", 33))) {
    return assert(false, "u32-max length is rejected by the 64-bit guard");
  }
  return assert(true, "length constants, the 64-bit overflow guard and standard CRC vectors hold");
}

fn check(r: TestResult) -> Int {
  if (r.passed) {
    io.println("  [PASS] " + r.name);
    return 0;
  }
  io.println("  [FAIL] " + r.name + " -- " + r.message);
  return 1;
}

fn main() -> Int {
  io.println("=== xiom.png conformance tests ===");
  var failed: Int = 0;
  failed = failed + check(t1());
  failed = failed + check(t2());
  failed = failed + check(t3());
  failed = failed + check(t4());
  failed = failed + check(t5());
  failed = failed + check(t6());
  failed = failed + check(t7());
  failed = failed + check(t8());
  failed = failed + check(t9());
  failed = failed + check(t10());
  failed = failed + check(t11());
  failed = failed + check(t12());
  failed = failed + check(t13());
  failed = failed + check(t14());
  failed = failed + check(t15());
  failed = failed + check(t16());
  failed = failed + check(t17());
  if failed == 0 {
    io.println("xiom.png: all tests passed");
  } else {
    io.println("xiom.png: tests failed");
  }
  return failed;
}
