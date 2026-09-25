// XIOM -- xiom.ktx conformance tests (19 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module ktx_tests
use xiom.io; use xiom.test; use xiom.ktx;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: `==` on a Str read from a
// Vec[Str] element is a pointer comparison in v0.61.3.
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------- builders

// Low 32 bits of v, little-endian.
fn push_u32_le(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

// Low 32 bits of v, big-endian.
fn push_u32_be(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 16777216) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// The 12 KTX 1 identifier bytes, pinned independently of the library.
fn push_identifier(out: &mut Vec[UInt8>) {
  out.push((0xAB) as UInt8);
  out.push(75 as UInt8);   // K
  out.push(84 as UInt8);   // T
  out.push(88 as UInt8);   // X
  out.push(32 as UInt8);   // space
  out.push(49 as UInt8);   // 1
  out.push(49 as UInt8);   // 1
  out.push((0xBB) as UInt8);
  out.push(13 as UInt8);   // CR
  out.push(10 as UInt8);   // LF
  out.push(26 as UInt8);   // 0x1A
  out.push(10 as UInt8);   // LF
}

// The 12 KTX 2 identifier bytes ("KTX 20"), used for the rejection check.
fn push_identifier2(out: &mut Vec[UInt8>) {
  out.push((0xAB) as UInt8);
  out.push(75 as UInt8);
  out.push(84 as UInt8);
  out.push(88 as UInt8);
  out.push(32 as UInt8);
  out.push(50 as UInt8);   // 2
  out.push(48 as UInt8);   // 0
  out.push((0xBB) as UInt8);
  out.push(13 as UInt8);
  out.push(10 as UInt8);
  out.push(26 as UInt8);
  out.push(10 as UInt8);
}

// ASCII bytes of a literal.
fn bytes_of(s: Str) -> Vec[UInt8] {
  let v = Vec[UInt8].new();
  var i = 0;
  while (i < s.len()) {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// Hand-built 64-byte little-endian header with fixed realistic GL values:
// glType 5121, glFormat/glBase 6408, glInternalFormat 32856, no array.
fn mk_hdr_le(w: Int, h: Int, d: Int, faces: Int, levels: Int, kv_bytes: Int, type_size: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_identifier(&mut out);
  push_u32_le(&mut out, 0x04030201);
  push_u32_le(&mut out, 5121);
  push_u32_le(&mut out, type_size);
  push_u32_le(&mut out, 6408);
  push_u32_le(&mut out, 32856);
  push_u32_le(&mut out, 6408);
  push_u32_le(&mut out, w);
  push_u32_le(&mut out, h);
  push_u32_le(&mut out, d);
  push_u32_le(&mut out, 0);
  push_u32_le(&mut out, faces);
  push_u32_le(&mut out, levels);
  push_u32_le(&mut out, kv_bytes);
  return out;
}

// Hand-built 64-byte big-endian header: glType 0 (compressed), glBase 6403.
fn mk_hdr_be(w: Int, h: Int, d: Int, faces: Int, levels: Int, kv_bytes: Int, type_size: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  push_identifier(&mut out);
  push_u32_be(&mut out, 0x04030201);
  push_u32_be(&mut out, 0);
  push_u32_be(&mut out, type_size);
  push_u32_be(&mut out, 0);
  push_u32_be(&mut out, 36161);
  push_u32_be(&mut out, 6403);
  push_u32_be(&mut out, w);
  push_u32_be(&mut out, h);
  push_u32_be(&mut out, d);
  push_u32_be(&mut out, 0);
  push_u32_be(&mut out, faces);
  push_u32_be(&mut out, levels);
  push_u32_be(&mut out, kv_bytes);
  return out;
}

// A little-endian key/value pair: u32 size, key, NUL, value bytes,
// zero padding to the next 4-byte boundary. Size excludes the padding.
fn push_key_value_le(out: &mut Vec[UInt8>, key: Str, value: &Vec[UInt8]) {
  let klen: Int = key.len();
  let vlen: Int = value.len();
  let size: Int = klen + 1 + vlen;
  push_u32_le(out, size);
  var i = 0;
  while (i < klen) {
    out.push(string.byte_at(key, i));
    i = i + 1;
  }
  out.push(0 as UInt8);
  i = 0;
  while (i < vlen) {
    let b: UInt8 = value[i];
    out.push(b);
    i = i + 1;
  }
  let aligned: Int = ((size + 3) / 4) * 4;
  i = size;
  while (i < aligned) {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

// Big-endian variant of push_key_value_le.
fn push_key_value_be(out: &mut Vec[UInt8>, key: Str, value: &Vec[UInt8>) {
  let klen: Int = key.len();
  let vlen: Int = value.len();
  let size: Int = klen + 1 + vlen;
  push_u32_be(out, size);
  var i = 0;
  while (i < klen) {
    out.push(string.byte_at(key, i));
    i = i + 1;
  }
  out.push(0 as UInt8);
  i = 0;
  while (i < vlen) {
    let b: UInt8 = value[i];
    out.push(b);
    i = i + 1;
  }
  let aligned: Int = ((size + 3) / 4) * 4;
  i = size;
  while (i < aligned) {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

// Raw little-endian pair: caller supplies the declared size and the exact
// `size` body bytes; padding is appended mechanically (none when size % 4
// == 0, so malformed bodies can be planted).
fn push_pair_raw_le(out: &mut Vec[UInt8>, size: Int, body: &Vec[UInt8>) {
  push_u32_le(out, size);
  var i = 0;
  while (i < size) {
    let b: UInt8 = body[i];
    out.push(b);
    i = i + 1;
  }
  let aligned: Int = ((size + 3) / 4) * 4;
  i = size;
  while (i < aligned) {
    out.push(0 as UInt8);
    i = i + 1;
  }
}

// Level record: u32 imageSize then a deterministic fill pattern
// (i * 7 + 1) % 256, optionally padded to the next 4-byte boundary.
fn push_level_le(out: &mut Vec[UInt8>, image_size: Int, with_pad: Bool) {
  push_u32_le(out, image_size);
  var i = 0;
  while (i < image_size) {
    out.push(((i * 7 + 1) % 256) as UInt8);
    i = i + 1;
  }
  if with_pad {
    let aligned: Int = ((image_size + 3) / 4) * 4;
    i = image_size;
    while (i < aligned) {
      out.push(0 as UInt8);
      i = i + 1;
    }
  }
}

// Big-endian level record (same fill pattern).
fn push_level_be(out: &mut Vec[UInt8>, image_size: Int, with_pad: Bool) {
  push_u32_be(out, image_size);
  var i = 0;
  while (i < image_size) {
    out.push(((i * 7 + 1) % 256) as UInt8);
    i = i + 1;
  }
  if with_pad {
    let aligned: Int = ((image_size + 3) / 4) * 4;
    i = image_size;
    while (i < aligned) {
      out.push(0 as UInt8);
      i = i + 1;
    }
  }
}

fn concat_bytes(a: &Vec[UInt8], b: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while (i < a.len()) {
    let x: UInt8 = a[i];
    out.push(x);
    i = i + 1;
  }
  i = 0;
  while (i < b.len()) {
    let x: UInt8 = b[i];
    out.push(x);
    i = i + 1;
  }
  return out;
}

// First `count` bytes of a buffer.
fn slice_bytes(data: &Vec[UInt8], count: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while (i < count) {
    let x: UInt8 = data[i];
    out.push(x);
    i = i + 1;
  }
  return out;
}

fn byte_is(data: &Vec[UInt8], i: Int, want: Int) -> Bool {
  let b: Int = (data[i] as Int) & 0xFF;
  return b == want;
}

// ---------------------------------------------------------------- outcomes

fn zero_hdr() -> KtxHeader {
  return KtxHeader{
    endianness: 0; big_endian: false; gl_type: 0; gl_type_size: 0;
    gl_format: 0; gl_internal_format: 0; gl_base_internal_format: 0;
    pixel_width: 0; pixel_height: 0; pixel_depth: 0; array_elements: 0;
    faces: 0; mipmap_levels: 0; kv_bytes: 0;
  };
}

fn zero_kv() -> KtxKeyValues {
  let keys = Vec[Str].new();
  let offsets = Vec[Int].new();
  let sizes = Vec[Int].new();
  return KtxKeyValues{
    count: 0; keys: keys; value_offsets: offsets; value_bytes: sizes;
  };
}

fn zero_info() -> KtxInfo {
  let h = zero_hdr();
  let kv = zero_kv();
  let offsets = Vec[Int].new();
  let sizes = Vec[Int].new();
  return KtxInfo{
    header: h; kv: kv; kv_offset: 0; data_offset: 0; level_count: 0;
    size_offsets: offsets; image_sizes: sizes; data_bytes: 0;
  };
}

fn ok_hdr(r: Result[KtxHeader, Str]) -> KtxHeader {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return zero_hdr(); },
  }
}

fn bad_hdr(r: Result[KtxHeader, Str]) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return true; },
  }
}

fn hdr_err_is(r: Result[KtxHeader, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_kv(r: Result[KtxKeyValues, Str]) -> KtxKeyValues {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return zero_kv(); },
  }
}

fn kv_err_is(r: Result[KtxKeyValues, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn ok_info(r: Result[KtxInfo, Str]) -> KtxInfo {
  match r {
    Ok(v) => { return v; },
    Err(e) => { return zero_info(); },
  }
}

fn info_err_is(r: Result[KtxInfo, Str], want: Str) -> Bool {
  match r {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
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

// A valid builder header: 4x4 RGBA8, one level, one face, no array.
fn base_h() -> KtxHeader {
  return KtxHeader{
    endianness: 0x04030201; big_endian: false; gl_type: 5121;
    gl_type_size: 1; gl_format: 6408; gl_internal_format: 32856;
    gl_base_internal_format: 6408; pixel_width: 4; pixel_height: 4;
    pixel_depth: 0; array_elements: 0; faces: 1; mipmap_levels: 1;
    kv_bytes: 0;
  };
}

// ---------------------------------------------------------------- checks

fn t1() -> TestResult {
  let d = mk_hdr_le(16, 8, 0, 1, 3, 0, 2);
  if (d.len() != 64) { return assert(false, "hand-built header is 64 bytes"); }
  if (!ktx_is_ktx(d)) { return assert(false, "identifier is recognized"); }
  match ktx_parse_header(d) {
    Ok(h) => {
      if (h.endianness != 0x04030201) { return assert(false, "marker is 0x04030201"); }
      if (h.big_endian) { return assert(false, "LE file is not big endian"); }
      if (h.gl_type != 5121) { return assert(false, "glType is 5121"); }
      if (h.gl_type_size != 2) { return assert(false, "glTypeSize is 2"); }
      if (h.gl_format != 6408) { return assert(false, "glFormat is 6408"); }
      if (h.gl_internal_format != 32856) { return assert(false, "glInternalFormat is 32856"); }
      if (h.gl_base_internal_format != 6408) { return assert(false, "glBaseInternalFormat is 6408"); }
      if (h.pixel_width != 16) { return assert(false, "pixelWidth is 16"); }
      if (h.pixel_height != 8) { return assert(false, "pixelHeight is 8"); }
      if (h.pixel_depth != 0) { return assert(false, "pixelDepth is 0"); }
      if (h.array_elements != 0) { return assert(false, "array elements is 0"); }
      if (h.faces != 1) { return assert(false, "faces is 1"); }
      if (h.mipmap_levels != 3) { return assert(false, "mipmap levels is 3"); }
      if (h.kv_bytes != 0) { return assert(false, "kv bytes is 0"); }
      if (ktx_width(h) != 16) { return assert(false, "width accessor"); }
      if (ktx_height(h) != 8) { return assert(false, "height accessor"); }
      if (ktx_depth(h) != 0) { return assert(false, "depth accessor"); }
      if (ktx_gl_type(h) != 5121) { return assert(false, "glType accessor"); }
      if (ktx_gl_format(h) != 6408) { return assert(false, "glFormat accessor"); }
      if (ktx_gl_internal_format(h) != 32856) { return assert(false, "glInternalFormat accessor"); }
      if (ktx_gl_base_internal_format(h) != 6408) { return assert(false, "glBaseInternalFormat accessor"); }
      if (ktx_is_compressed(h)) { return assert(false, "texture is not compressed"); }
      if (ktx_is_cubemap(h)) { return assert(false, "texture is not a cubemap"); }
      if (ktx_is_array(h)) { return assert(false, "texture is not an array"); }
      if (ktx_data_offset(h) != 64) { return assert(false, "data offset is 64"); }
      if (ktx_level_count(h) != 3) { return assert(false, "level count is 3"); }
      return assert(true, "hand-built LE header decodes every field and accessor");
    },
    Err(e) => { return assert(false, "hand-built LE header was rejected"); },
  }
}

fn t2() -> TestResult {
  let d = mk_hdr_be(32, 32, 1, 1, 2, 0, 4);
  match ktx_parse_header(d) {
    Ok(h) => {
      if (h.endianness != 0x01020304) { return assert(false, "marker is 0x01020304"); }
      if (!h.big_endian) { return assert(false, "BE file reports big endian"); }
      if (h.gl_type != 0) { return assert(false, "glType is 0 (compressed)"); }
      if (h.gl_type_size != 4) { return assert(false, "glTypeSize is 4"); }
      if (h.gl_format != 0) { return assert(false, "glFormat is 0 (compressed)"); }
      if (h.gl_internal_format != 36161) { return assert(false, "glInternalFormat is 36161"); }
      if (h.gl_base_internal_format != 6403) { return assert(false, "glBaseInternalFormat is 6403"); }
      if (h.pixel_width != 32) { return assert(false, "pixelWidth is 32"); }
      if (h.pixel_height != 32) { return assert(false, "pixelHeight is 32"); }
      if (h.pixel_depth != 1) { return assert(false, "pixelDepth is 1"); }
      if (h.faces != 1) { return assert(false, "faces is 1"); }
      if (h.mipmap_levels != 2) { return assert(false, "mipmap levels is 2"); }
      if (!ktx_is_compressed(h)) { return assert(false, "glType 0 is compressed"); }
      return assert(true, "big-endian header decodes every field");
    },
    Err(e) => { return assert(false, "BE header was rejected"); },
  }
}

fn t3() -> TestResult {
  let d = mk_hdr_le(4, 4, 0, 1, 1, 0, 1);
  if (!ktx_is_ktx(d)) { return assert(false, "valid identifier is recognized"); }
  var i = 0;
  while (i < 12) {
    let save: UInt8 = d[i];
    d[i] = 0 as UInt8;
    if (!hdr_err_is(ktx_parse_header(d), "ktx: bad identifier")) {
      return assert(false, "corrupt identifier byte is rejected");
    }
    d[i] = save;
    i = i + 1;
  }
  if (bad_hdr(ktx_parse_header(d))) { return assert(false, "restored identifier parses"); }
  let empty = Vec[UInt8].new();
  if (!hdr_err_is(ktx_parse_header(empty), "ktx: truncated header")) {
    return assert(false, "empty buffer is truncated");
  }
  let eleven = Vec[UInt8].new();
  i = 0;
  while (i < 11) {
    eleven.push(0 as UInt8);
    i = i + 1;
  }
  if (!hdr_err_is(ktx_parse_header(eleven), "ktx: truncated header")) {
    return assert(false, "11-byte buffer is truncated");
  }
  var id_only = Vec[UInt8].new();
  push_identifier(&mut id_only);
  if (id_only.len() != 12) { return assert(false, "identifier-only buffer is 12 bytes"); }
  if (!hdr_err_is(ktx_parse_header(id_only), "ktx: truncated header")) {
    return assert(false, "identifier-only buffer is truncated");
  }
  var ktx2 = Vec[UInt8].new();
  push_identifier2(&mut ktx2);
  if (ktx_is_ktx(ktx2)) { return assert(false, "KTX 2 identifier is not KTX 1"); }
  while (ktx2.len() < 64) {
    ktx2.push(0 as UInt8);
  }
  if (!hdr_err_is(ktx_parse_header(ktx2), "ktx: ktx2 not supported")) {
    return assert(false, "KTX 2 file is rejected explicitly");
  }
  return assert(true, "identifier is exact and KTX 2 is rejected");
}

fn t4() -> TestResult {
  let le = mk_hdr_le(4, 4, 0, 1, 1, 0, 1);
  if (bad_hdr(ktx_parse_header(le))) { return assert(false, "LE marker parses"); }
  let be = mk_hdr_be(4, 4, 0, 1, 1, 0, 1);
  if (bad_hdr(ktx_parse_header(be))) { return assert(false, "BE marker parses"); }
  let bad = mk_hdr_le(4, 4, 0, 1, 1, 0, 1);
  bad[12] = 1 as UInt8;
  bad[13] = 2 as UInt8;
  bad[14] = 3 as UInt8;
  bad[15] = 5 as UInt8;
  if (!hdr_err_is(ktx_parse_header(bad), "ktx: bad endianness")) {
    return assert(false, "unknown marker is rejected");
  }
  return assert(true, "endianness markers 0x04030201 and 0x01020304 are accepted");
}

fn t5() -> TestResult {
  var t = 0;
  while (t <= 9) {
    let d = mk_hdr_le(4, 4, 0, 1, 1, 0, t);
    if (t >= 1) {
      if (t <= 8) {
        if (bad_hdr(ktx_parse_header(d))) { return assert(false, "type size 1..8 is Ok"); }
      } else {
        if (!hdr_err_is(ktx_parse_header(d), "ktx: invalid type size")) {
          return assert(false, "type size 9 is Err");
        }
      }
    } else {
      if (!hdr_err_is(ktx_parse_header(d), "ktx: invalid type size")) {
        return assert(false, "type size 0 is Err");
      }
    }
    t = t + 1;
  }
  let big = mk_hdr_le(4, 4, 0, 1, 1, 0, 255);
  if (!hdr_err_is(ktx_parse_header(big), "ktx: invalid type size")) {
    return assert(false, "type size 255 is Err");
  }
  let huge = mk_hdr_le(4, 4, 0, 1, 1, 0, 4294967295);
  if (!hdr_err_is(ktx_parse_header(huge), "ktx: invalid type size")) {
    return assert(false, "type size 2^32-1 is Err");
  }
  return assert(true, "glTypeSize must be in 1..8");
}

fn t6() -> TestResult {
  let one = mk_hdr_le(4, 4, 0, 1, 1, 0, 1);
  let h1 = ok_hdr(ktx_parse_header(one));
  if (ktx_is_cubemap(h1)) { return assert(false, "faces 1 is not a cubemap"); }
  let six = mk_hdr_le(4, 4, 0, 6, 1, 0, 1);
  let h6 = ok_hdr(ktx_parse_header(six));
  if (!ktx_is_cubemap(h6)) { return assert(false, "faces 6 is a cubemap"); }
  let bad_face = Vec[Int].new();
  bad_face.push(0); bad_face.push(2); bad_face.push(5);
  bad_face.push(7); bad_face.push(255);
  var i = 0;
  while (i < bad_face.len()) {
    let f: Int = bad_face[i];
    let d = mk_hdr_le(4, 4, 0, f, 1, 0, 1);
    if (!hdr_err_is(ktx_parse_header(d), "ktx: invalid face count")) {
      return assert(false, "face count 0/2/5/7/255 is Err");
    }
    i = i + 1;
  }
  return assert(true, "numberOfFaces must be 1 or 6");
}

fn t7() -> TestResult {
  let zero = mk_hdr_le(0, 4, 0, 1, 1, 0, 1);
  if (!hdr_err_is(ktx_parse_header(zero), "ktx: invalid width")) {
    return assert(false, "zero width is Err");
  }
  let one = mk_hdr_le(1, 0, 0, 1, 1, 0, 1);
  if (bad_hdr(ktx_parse_header(one))) { return assert(false, "1x0 1D shape parses"); }
  let cube = mk_hdr_le(1, 1, 1, 1, 1, 0, 1);
  if (bad_hdr(ktx_parse_header(cube))) { return assert(false, "1x1x1 3D shape parses"); }
  let wide = mk_hdr_le(4294967295, 0, 0, 1, 1, 0, 1);
  let hw = ok_hdr(ktx_parse_header(wide));
  if (ktx_width(hw) != 4294967295) { return assert(false, "max u32 width is kept"); }
  return assert(true, "pixelWidth must be nonzero; other axes are unconstrained");
}

fn t8() -> TestResult {
  let value = Vec[UInt8].new();
  value.push(103 as UInt8); value.push(108 as UInt8);
  value.push(101 as UInt8); value.push(115 as UInt8);
  value.push(50 as UInt8); value.push(0 as UInt8);
  var body = Vec[UInt8].new();
  push_key_value_le(&mut body, "api", value);
  if (body.len() != 16) { return assert(false, "api pair occupies 16 bytes"); }
  let hdr = mk_hdr_le(4, 4, 0, 1, 1, body.len(), 1);
  let f = concat_bytes(hdr, body);
  if (f.len() != 80) { return assert(false, "file is 80 bytes"); }
  let kv = ok_kv(ktx_parse_key_values(f));
  if (kv.count != 1) { return assert(false, "one pair is indexed"); }
  if (ktx_kv_count(kv) != 1) { return assert(false, "count accessor"); }
  if (!streq(ktx_kv_key(kv, 0), "api")) { return assert(false, "key is api"); }
  if (ktx_kv_value_offset(kv, 0) != 72) { return assert(false, "value starts at 72"); }
  if (ktx_kv_value_bytes(kv, 0) != 6) { return assert(false, "value is 6 bytes"); }
  let v = ok_bytes(ktx_kv_value(f, kv, 0));
  if (v.len() != 6) { return assert(false, "value copy is 6 bytes"); }
  if (!byte_is(v, 0, 103)) { return assert(false, "value byte 0 is 'g'"); }
  if (!byte_is(v, 4, 50)) { return assert(false, "value byte 4 is '2'"); }
  if (!byte_is(v, 5, 0)) { return assert(false, "value byte 5 is NUL"); }
  let h = ok_hdr(ktx_parse_header(f));
  if (ktx_data_offset(h) != 80) { return assert(false, "data offset is 64 + kv bytes"); }
  return assert(true, "the specification api/gles2 example round-trips");
}

fn t9() -> TestResult {
  let v1 = bytes_of("S=r,T=u");
  v1.push(0 as UInt8);
  let v2 = bytes_of("me");
  let v3 = Vec[UInt8].new();
  var body = Vec[UInt8].new();
  push_key_value_le(&mut body, "KTXorientation", v1);
  push_key_value_le(&mut body, "author", v2);
  push_key_value_le(&mut body, "empty", v3);
  let hdr = mk_hdr_le(2, 2, 0, 1, 1, body.len(), 1);
  let f = concat_bytes(hdr, body);
  let kv = ok_kv(ktx_parse_key_values(f));
  if (kv.count != 3) { return assert(false, "three pairs are indexed"); }
  if (!streq(ktx_kv_key(kv, 0), "KTXorientation")) { return assert(false, "pair 0 key"); }
  if (!streq(ktx_kv_key(kv, 1), "author")) { return assert(false, "pair 1 key"); }
  if (!streq(ktx_kv_key(kv, 2), "empty")) { return assert(false, "pair 2 key"); }
  if (ktx_kv_value_bytes(kv, 0) != 8) { return assert(false, "pair 0 value is 8 bytes"); }
  if (ktx_kv_value_bytes(kv, 1) != 2) { return assert(false, "pair 1 value is 2 bytes"); }
  if (ktx_kv_value_bytes(kv, 2) != 0) { return assert(false, "pair 2 value is empty"); }
  let c1 = ok_bytes(ktx_kv_value(f, kv, 1));
  if (!byte_is(c1, 0, 109)) { return assert(false, "pair 1 value is 'm'"); }
  if (!byte_is(c1, 1, 101)) { return assert(false, "pair 1 value is 'e'"); }
  let c0 = ok_bytes(ktx_kv_value(f, kv, 0));
  if (!byte_is(c0, 7, 0)) { return assert(false, "pair 0 value ends with NUL"); }
  let hdr2 = ok_hdr(ktx_parse_header(f));
  if (ktx_data_offset(hdr2) != 64 + body.len()) {
    return assert(false, "levels start after the kv region");
  }
  return assert(true, "multiple key/value pairs index with flat spans");
}

fn t10() -> TestResult {
  let b1 = bytes_of("abc");
  var p1 = Vec[UInt8].new();
  push_pair_raw_le(&mut p1, 3, b1);
  let h1 = mk_hdr_le(4, 4, 0, 1, 1, p1.len(), 1);
  let f1 = concat_bytes(h1, p1);
  if (!kv_err_is(ktx_parse_key_values(f1), "ktx: missing key terminator")) {
    return assert(false, "key without NUL is Err");
  }
  let b2 = Vec[UInt8].new();
  b2.push(0 as UInt8);
  b2.push(118 as UInt8);
  var p2 = Vec[UInt8].new();
  push_pair_raw_le(&mut p2, 2, b2);
  let h2 = mk_hdr_le(4, 4, 0, 1, 1, p2.len(), 1);
  if (!kv_err_is(ktx_parse_key_values(concat_bytes(h2, p2)), "ktx: invalid key")) {
    return assert(false, "empty key is Err");
  }
  let b3 = Vec[UInt8].new();
  b3.push(97 as UInt8); b3.push(1 as UInt8);
  b3.push(0 as UInt8); b3.push(118 as UInt8);
  var p3 = Vec[UInt8].new();
  push_pair_raw_le(&mut p3, 4, b3);
  let h3 = mk_hdr_le(4, 4, 0, 1, 1, p3.len(), 1);
  if (!kv_err_is(ktx_parse_key_values(concat_bytes(h3, p3)), "ktx: invalid key")) {
    return assert(false, "control byte in key is Err");
  }
  let b4 = Vec[UInt8].new();
  b4.push(127 as UInt8); b4.push(0 as UInt8); b4.push(118 as UInt8);
  var p4 = Vec[UInt8].new();
  push_pair_raw_le(&mut p4, 3, b4);
  let h4 = mk_hdr_le(4, 4, 0, 1, 1, p4.len(), 1);
  if (!kv_err_is(ktx_parse_key_values(concat_bytes(h4, p4)), "ktx: invalid key")) {
    return assert(false, "DEL in key is Err");
  }
  let b5 = Vec[UInt8].new();
  b5.push(128 as UInt8); b5.push(0 as UInt8); b5.push(118 as UInt8);
  var p5 = Vec[UInt8].new();
  push_pair_raw_le(&mut p5, 3, b5);
  let h5 = mk_hdr_le(4, 4, 0, 1, 1, p5.len(), 1);
  if (!kv_err_is(ktx_parse_key_values(concat_bytes(h5, p5)), "ktx: invalid key")) {
    return assert(false, "high byte in key is Err");
  }
  let b6 = Vec[UInt8].new();
  b6.push(32 as UInt8); b6.push(0 as UInt8);
  var p6 = Vec[UInt8].new();
  push_pair_raw_le(&mut p6, 2, b6);
  let h6 = mk_hdr_le(4, 4, 0, 1, 1, p6.len(), 1);
  let kv6 = ok_kv(ktx_parse_key_values(concat_bytes(h6, p6)));
  if (!streq(ktx_kv_key(kv6, 0), " ")) { return assert(false, "space key is printable"); }
  let opq = Vec[UInt8].new();
  opq.push(0 as UInt8); opq.push(255 as UInt8);
  opq.push(128 as UInt8); opq.push(1 as UInt8);
  var body7 = Vec[UInt8].new();
  push_key_value_le(&mut body7, "data", opq);
  let h7 = mk_hdr_le(4, 4, 0, 1, 1, body7.len(), 1);
  let f7 = concat_bytes(h7, body7);
  let kv7 = ok_kv(ktx_parse_key_values(f7));
  let cop = ok_bytes(ktx_kv_value(f7, kv7, 0));
  if (!byte_is(cop, 0, 0)) { return assert(false, "value byte 0 is NUL"); }
  if (!byte_is(cop, 1, 255)) { return assert(false, "value byte 1 is 255"); }
  if (!byte_is(cop, 2, 128)) { return assert(false, "value byte 2 is 128"); }
  if (!byte_is(cop, 3, 1)) { return assert(false, "value byte 3 is 1"); }
  return assert(true, "printable-key rule and opaque value bytes");
}

fn t11() -> TestResult {
  let h1 = mk_hdr_le(4, 4, 0, 1, 1, 16, 1);
  var extra = Vec[UInt8].new();
  var i = 0;
  while (i < 8) {
    extra.push(0 as UInt8);
    i = i + 1;
  }
  if (!kv_err_is(ktx_parse_key_values(concat_bytes(h1, extra)), "ktx: truncated key/value data")) {
    return assert(false, "kv region beyond the buffer is Err");
  }
  let h2 = mk_hdr_le(4, 4, 0, 1, 1, 6, 1);
  var six = Vec[UInt8].new();
  i = 0;
  while (i < 6) {
    six.push(0 as UInt8);
    i = i + 1;
  }
  if (!kv_err_is(ktx_parse_key_values(concat_bytes(h2, six)), "ktx: unaligned key/value data")) {
    return assert(false, "kv region not multiple of 4 is Err");
  }
  let h3 = mk_hdr_le(4, 4, 0, 1, 1, 4, 1);
  var s3 = Vec[UInt8].new();
  push_u32_le(&mut s3, 100);
  if (!kv_err_is(ktx_parse_key_values(concat_bytes(h3, s3)), "ktx: bad key/value size")) {
    return assert(false, "declared pair larger than the region is Err");
  }
  let h4 = mk_hdr_le(4, 4, 0, 1, 1, 4, 1);
  var s4 = Vec[UInt8].new();
  push_u32_le(&mut s4, 0);
  if (!kv_err_is(ktx_parse_key_values(concat_bytes(h4, s4)), "ktx: invalid key")) {
    return assert(false, "zero-size pair is Err");
  }
  let h5 = mk_hdr_le(4, 4, 0, 1, 1, 12, 1);
  var s5 = Vec[UInt8].new();
  push_u32_le(&mut s5, 5);
  s5.push(97 as UInt8); s5.push(0 as UInt8);
  s5.push(1 as UInt8); s5.push(2 as UInt8); s5.push(3 as UInt8);
  var pad5 = Vec[UInt8].new();
  i = 0;
  while (i < 3) {
    pad5.push(0 as UInt8);
    i = i + 1;
  }
  let kv5 = ok_kv(ktx_parse_key_values(concat_bytes(h5, concat_bytes(s5, pad5))));
  if (kv5.count != 1) { return assert(false, "padded pair fits its region"); }
  if (ktx_kv_value_bytes(kv5, 0) != 3) { return assert(false, "pair value is 3 bytes"); }
  return assert(true, "key/value region bounds and alignment are validated");
}

fn t12() -> TestResult {
  var body = Vec[UInt8].new();
  push_level_le(&mut body, 3, true);
  push_level_le(&mut body, 5, false);
  let f = concat_bytes(mk_hdr_le(2, 2, 0, 1, 2, 0, 1), body);
  if (f.len() != 81) { return assert(false, "two-level file is 81 bytes"); }
  let info = ok_info(ktx_parse(f));
  if (info.kv_offset != 64) { return assert(false, "kv offset is 64"); }
  if (info.data_offset != 64) { return assert(false, "data offset is 64"); }
  if (info.level_count != 2) { return assert(false, "level count is 2"); }
  if (ktx_level_offset(info, 0) != 64) { return assert(false, "level 0 record at 64"); }
  if (ktx_level_offset(info, 1) != 72) { return assert(false, "level 1 record at 72"); }
  if (ktx_level_size(info, 0) != 3) { return assert(false, "level 0 imageSize is 3"); }
  if (ktx_level_size(info, 1) != 5) { return assert(false, "level 1 imageSize is 5"); }
  if (ktx_payload_offset(info, 0) != 68) { return assert(false, "level 0 payload at 68"); }
  if (ktx_payload_offset(info, 1) != 76) { return assert(false, "level 1 payload at 76"); }
  if (info.data_bytes != 17) { return assert(false, "data bytes is 8 + 9"); }
  let l0 = ok_bytes(ktx_level_data(f, info, 0));
  if (l0.len() != 3) { return assert(false, "level 0 data is 3 bytes"); }
  if (!byte_is(l0, 0, 1)) { return assert(false, "level 0 byte 0 is 1"); }
  if (!byte_is(l0, 2, 15)) { return assert(false, "level 0 byte 2 is 15"); }
  let l1 = ok_bytes(ktx_level_data(f, info, 1));
  if (l1.len() != 5) { return assert(false, "level 1 data is 5 bytes"); }
  if (!byte_is(l1, 0, 1)) { return assert(false, "level 1 byte 0 is 1"); }
  if (!byte_is(l1, 4, 29)) { return assert(false, "level 1 byte 4 is 29"); }
  return assert(true, "level records locate imageSize and payload spans");
}

fn t13() -> TestResult {
  var one = Vec[UInt8].new();
  push_level_le(&mut one, 2, false);
  let f0 = concat_bytes(mk_hdr_le(2, 2, 0, 1, 0, 0, 1), one);
  let i0 = ok_info(ktx_parse(f0));
  if (i0.level_count != 1) { return assert(false, "0 levels is treated as 1"); }
  if (ktx_level_size(i0, 0) != 2) { return assert(false, "the single level is parsed"); }
  if (i0.data_bytes != 6) { return assert(false, "data bytes is 6"); }
  var three = Vec[UInt8].new();
  push_level_le(&mut three, 1, true);
  push_level_le(&mut three, 2, true);
  push_level_le(&mut three, 3, false);
  let f3 = concat_bytes(mk_hdr_le(2, 2, 0, 1, 3, 0, 1), three);
  if (f3.len() != 87) { return assert(false, "three-level file is 87 bytes"); }
  let i3 = ok_info(ktx_parse(f3));
  if (i3.level_count != 3) { return assert(false, "three levels are parsed"); }
  if (ktx_level_offset(i3, 2) != 80) { return assert(false, "level 2 record at 80"); }
  if (ktx_level_size(i3, 2) != 3) { return assert(false, "level 2 imageSize is 3"); }
  if (i3.data_bytes != 23) { return assert(false, "three-level data bytes is 23"); }
  return assert(true, "mipmap levels 0 and many are both handled");
}

fn t14() -> TestResult {
  let h1 = mk_hdr_le(2, 2, 0, 1, 1, 0, 1);
  var two = Vec[UInt8].new();
  two.push(0 as UInt8);
  two.push(0 as UInt8);
  if (!info_err_is(ktx_parse(concat_bytes(h1, two)), "ktx: truncated level data")) {
    return assert(false, "missing imageSize is Err");
  }
  var size10 = Vec[UInt8].new();
  push_u32_le(&mut size10, 10);
  size10.push(0 as UInt8);
  size10.push(0 as UInt8);
  size10.push(0 as UInt8);
  if (!info_err_is(ktx_parse(concat_bytes(h1, size10)), "ktx: truncated level data")) {
    return assert(false, "image data beyond the buffer is Err");
  }
  let h2 = mk_hdr_le(2, 2, 0, 1, 2, 0, 1);
  var partial = Vec[UInt8].new();
  push_level_le(&mut partial, 1, true);
  partial.push(0 as UInt8);
  partial.push(0 as UInt8);
  if (!info_err_is(ktx_parse(concat_bytes(h2, partial)), "ktx: truncated level data")) {
    return assert(false, "second imageSize cut short is Err");
  }
  let h3 = mk_hdr_le(2, 2, 0, 1, 1, 0, 1);
  var tail = Vec[UInt8].new();
  push_level_le(&mut tail, 7, false);
  let okf = concat_bytes(h3, tail);
  if (okf.len() != 75) { return assert(false, "unpadded final level is 75 bytes"); }
  let info = ok_info(ktx_parse(okf));
  if (ktx_level_size(info, 0) != 7) { return assert(false, "unpadded final level parses"); }
  return assert(true, "level truncation is exact; final padding is optional");
}

fn t15() -> TestResult {
  let cube = mk_hdr_le(16, 16, 0, 6, 1, 0, 1);
  let h = ok_hdr(ktx_parse_header(cube));
  if (!ktx_is_cubemap(h)) { return assert(false, "cubemap header parses"); }
  if (h.faces != 6) { return assert(false, "faces is 6"); }
  if (!info_err_is(ktx_parse(cube), "ktx: unsupported level layout")) {
    return assert(false, "cubemap whole parse is out of scope");
  }
  let arr = mk_hdr_le(16, 16, 0, 1, 1, 0, 1);
  arr[48] = 1 as UInt8;
  let ha = ok_hdr(ktx_parse_header(arr));
  if (!ktx_is_array(ha)) { return assert(false, "array header parses"); }
  if (!info_err_is(ktx_parse(arr), "ktx: unsupported level layout")) {
    return assert(false, "array whole parse is out of scope");
  }
  let value = bytes_of("S=r,T=u");
  value.push(0 as UInt8);
  var body = Vec[UInt8].new();
  push_key_value_le(&mut body, "KTXorientation", value);
  let cube_kv = concat_bytes(mk_hdr_le(16, 16, 0, 6, 1, body.len(), 1), body);
  let kv = ok_kv(ktx_parse_key_values(cube_kv));
  if (kv.count != 1) { return assert(false, "cubemap key/value data still parses"); }
  if (!streq(ktx_kv_key(kv, 0), "KTXorientation")) { return assert(false, "cubemap key reads back"); }
  return assert(true, "cubemap and array headers parse; whole-parse is scoped to flat textures");
}

fn t16() -> TestResult {
  var h = base_h();
  h.endianness = 0x01020304;
  h.big_endian = true;
  h.kv_bytes = 4096;
  let d = ok_bytes(ktx_build_header(h));
  if (d.len() != 64) { return assert(false, "built header is 64 bytes"); }
  if (!byte_is(d, 0, 0xAB)) { return assert(false, "identifier byte 0"); }
  if (!byte_is(d, 1, 75)) { return assert(false, "identifier byte 1"); }
  if (!byte_is(d, 2, 84)) { return assert(false, "identifier byte 2"); }
  if (!byte_is(d, 3, 88)) { return assert(false, "identifier byte 3"); }
  if (!byte_is(d, 4, 32)) { return assert(false, "identifier byte 4"); }
  if (!byte_is(d, 5, 49)) { return assert(false, "identifier byte 5"); }
  if (!byte_is(d, 6, 49)) { return assert(false, "identifier byte 6"); }
  if (!byte_is(d, 7, 0xBB)) { return assert(false, "identifier byte 7"); }
  if (!byte_is(d, 8, 13)) { return assert(false, "identifier byte 8"); }
  if (!byte_is(d, 9, 10)) { return assert(false, "identifier byte 9"); }
  if (!byte_is(d, 10, 26)) { return assert(false, "identifier byte 10"); }
  if (!byte_is(d, 11, 10)) { return assert(false, "identifier byte 11"); }
  if (!byte_is(d, 12, 1)) { return assert(false, "marker byte 0 is 01"); }
  if (!byte_is(d, 13, 2)) { return assert(false, "marker byte 1 is 02"); }
  if (!byte_is(d, 14, 3)) { return assert(false, "marker byte 2 is 03"); }
  if (!byte_is(d, 15, 4)) { return assert(false, "marker byte 3 is 04"); }
  if (!byte_is(d, 16, 1)) { return assert(false, "glType low byte"); }
  if (!byte_is(d, 17, 20)) { return assert(false, "glType high byte"); }
  if (!byte_is(d, 20, 1)) { return assert(false, "glTypeSize byte"); }
  if (!byte_is(d, 24, 8)) { return assert(false, "glFormat low byte"); }
  if (!byte_is(d, 25, 25)) { return assert(false, "glFormat high byte"); }
  if (!byte_is(d, 28, 88)) { return assert(false, "glInternalFormat low byte"); }
  if (!byte_is(d, 29, 128)) { return assert(false, "glInternalFormat high byte"); }
  if (!byte_is(d, 32, 8)) { return assert(false, "glBaseInternalFormat low byte"); }
  if (!byte_is(d, 36, 4)) { return assert(false, "pixelWidth byte"); }
  if (!byte_is(d, 40, 4)) { return assert(false, "pixelHeight byte"); }
  if (!byte_is(d, 52, 1)) { return assert(false, "faces byte"); }
  if (!byte_is(d, 56, 1)) { return assert(false, "mipmap levels byte"); }
  if (!byte_is(d, 60, 0)) { return assert(false, "kv bytes byte 0 is 0"); }
  if (!byte_is(d, 63, 0)) { return assert(false, "kv bytes byte 3 is 0"); }
  let p = ok_hdr(ktx_parse_header(d));
  if (p.endianness != 0x04030201) { return assert(false, "built marker is canonical LE"); }
  if (p.big_endian) { return assert(false, "built header is not big endian"); }
  if (p.kv_bytes != 0) { return assert(false, "built kv bytes is pinned to 0"); }
  if (p.gl_type != 5121) { return assert(false, "built glType round-trips"); }
  if (p.gl_type_size != 1) { return assert(false, "built glTypeSize round-trips"); }
  if (p.gl_format != 6408) { return assert(false, "built glFormat round-trips"); }
  if (p.gl_internal_format != 32856) { return assert(false, "built glInternalFormat round-trips"); }
  if (p.gl_base_internal_format != 6408) { return assert(false, "built glBaseInternalFormat round-trips"); }
  if (p.pixel_width != 4) { return assert(false, "built width round-trips"); }
  if (p.pixel_height != 4) { return assert(false, "built height round-trips"); }
  if (p.pixel_depth != 0) { return assert(false, "built depth round-trips"); }
  if (p.array_elements != 0) { return assert(false, "built array round-trips"); }
  if (p.faces != 1) { return assert(false, "built faces round-trips"); }
  if (p.mipmap_levels != 1) { return assert(false, "built levels round-trips"); }
  if (ktx_data_offset(p) != 64) { return assert(false, "built data offset is 64"); }
  var level = Vec[UInt8].new();
  push_level_le(&mut level, 4, false);
  let whole = concat_bytes(d, level);
  let info = ok_info(ktx_parse(whole));
  if (ktx_level_size(info, 0) != 4) { return assert(false, "built header accepts a level"); }
  let data = ok_bytes(ktx_level_data(whole, info, 0));
  if (!byte_is(data, 3, 22)) { return assert(false, "level data follows the built header"); }
  return assert(true, "builder emits a canonical little-endian header");
}

fn t17() -> TestResult {
  var h1 = base_h();
  h1.gl_type_size = 0;
  if (!bytes_err_is(ktx_build_header(h1), "ktx: invalid type size")) {
    return assert(false, "builder type size 0 is Err");
  }
  var h2 = base_h();
  h2.gl_type_size = 9;
  if (!bytes_err_is(ktx_build_header(h2), "ktx: invalid type size")) {
    return assert(false, "builder type size 9 is Err");
  }
  var h3 = base_h();
  h3.faces = 2;
  if (!bytes_err_is(ktx_build_header(h3), "ktx: invalid face count")) {
    return assert(false, "builder faces 2 is Err");
  }
  var h4 = base_h();
  h4.pixel_width = 0;
  if (!bytes_err_is(ktx_build_header(h4), "ktx: invalid width")) {
    return assert(false, "builder width 0 is Err");
  }
  var h5 = base_h();
  h5.gl_type = -1;
  if (!bytes_err_is(ktx_build_header(h5), "ktx: field out of range")) {
    return assert(false, "builder negative glType is Err");
  }
  var h6 = base_h();
  h6.gl_format = 4294967296;
  if (!bytes_err_is(ktx_build_header(h6), "ktx: field out of range")) {
    return assert(false, "builder 2^32 glFormat is Err");
  }
  var h7 = base_h();
  h7.pixel_height = -5;
  if (!bytes_err_is(ktx_build_header(h7), "ktx: field out of range")) {
    return assert(false, "builder negative height is Err");
  }
  var h8 = base_h();
  h8.array_elements = 4294967296;
  if (!bytes_err_is(ktx_build_header(h8), "ktx: field out of range")) {
    return assert(false, "builder 2^32 array count is Err");
  }
  if (bad_bytes(ktx_build_header(base_h()))) {
    return assert(false, "valid builder input is Ok");
  }
  return assert(true, "builder range checks cover every field");
}

fn t18() -> TestResult {
  let v1 = bytes_of("S=r,T=u");
  v1.push(0 as UInt8);
  let v2 = bytes_of("me");
  var body = Vec[UInt8].new();
  push_key_value_le(&mut body, "KTXorientation", v1);
  push_key_value_le(&mut body, "author", v2);
  var levels = Vec[UInt8].new();
  push_level_le(&mut levels, 3, true);
  push_level_le(&mut levels, 5, false);
  let le = concat_bytes(concat_bytes(mk_hdr_le(8, 8, 0, 1, 2, body.len(), 1), body), levels);
  let info = ok_info(ktx_parse(le));
  if (info.header.pixel_width != 8) { return assert(false, "LE width round-trips"); }
  if (info.header.mipmap_levels != 2) { return assert(false, "LE levels round-trip"); }
  if (info.kv.count != 2) { return assert(false, "LE kv count round-trips"); }
  if (!streq(ktx_kv_key(info.kv, 0), "KTXorientation")) { return assert(false, "LE key 0"); }
  if (!streq(ktx_kv_key(info.kv, 1), "author")) { return assert(false, "LE key 1"); }
  let cv1 = ok_bytes(ktx_kv_value(le, info.kv, 0));
  if (!byte_is(cv1, 0, 83)) { return assert(false, "LE orientation starts with S"); }
  if (!byte_is(cv1, 7, 0)) { return assert(false, "LE orientation ends with NUL"); }
  let cv2 = ok_bytes(ktx_kv_value(le, info.kv, 1));
  if (!byte_is(cv2, 1, 101)) { return assert(false, "LE author is 'me'"); }
  if (info.data_offset != 64 + body.len()) { return assert(false, "LE data offset"); }
  if (ktx_level_size(info, 1) != 5) { return assert(false, "LE level 1 size"); }
  let l1 = ok_bytes(ktx_level_data(le, info, 1));
  if (!byte_is(l1, 4, 29)) { return assert(false, "LE level 1 data"); }
  let vbe = Vec[UInt8].new();
  vbe.push(103 as UInt8); vbe.push(108 as UInt8);
  vbe.push(101 as UInt8); vbe.push(115 as UInt8);
  vbe.push(50 as UInt8); vbe.push(0 as UInt8);
  var body_be = Vec[UInt8].new();
  push_key_value_be(&mut body_be, "api", vbe);
  var be_levels = Vec[UInt8].new();
  push_level_be(&mut be_levels, 6, true);
  push_level_be(&mut be_levels, 2, false);
  let be = concat_bytes(concat_bytes(mk_hdr_be(4, 4, 0, 1, 2, body_be.len(), 1), body_be), be_levels);
  let binfo = ok_info(ktx_parse(be));
  if (!binfo.header.big_endian) { return assert(false, "BE header reports big endian"); }
  if (binfo.kv.count != 1) { return assert(false, "BE kv count"); }
  if (!streq(ktx_kv_key(binfo.kv, 0), "api")) { return assert(false, "BE key api"); }
  if (ktx_kv_value_bytes(binfo.kv, 0) != 6) { return assert(false, "BE value is 6 bytes"); }
  if (ktx_level_size(binfo, 0) != 6) { return assert(false, "BE level 0 size"); }
  if (ktx_level_size(binfo, 1) != 2) { return assert(false, "BE level 1 size"); }
  let bl0 = ok_bytes(ktx_level_data(be, binfo, 0));
  if (!byte_is(bl0, 5, 36)) { return assert(false, "BE level 0 data"); }
  return assert(true, "LE and BE files round-trip with key/value data and levels");
}

fn t19() -> TestResult {
  let value = bytes_of("S=r,T=u");
  value.push(0 as UInt8);
  var body = Vec[UInt8].new();
  push_key_value_le(&mut body, "KTXorientation", value);
  var levels = Vec[UInt8].new();
  push_level_le(&mut levels, 3, true);
  push_level_le(&mut levels, 5, false);
  let f = concat_bytes(concat_bytes(mk_hdr_le(8, 8, 0, 1, 2, body.len(), 1), body), levels);
  let info = ok_info(ktx_parse(f));
  if (!streq(ktx_kv_key(info.kv, -1), "")) { return assert(false, "kv key -1 is empty"); }
  if (!streq(ktx_kv_key(info.kv, 9), "")) { return assert(false, "kv key 9 is empty"); }
  if (ktx_kv_value_offset(info.kv, -1) != -1) { return assert(false, "kv offset -1"); }
  if (ktx_kv_value_offset(info.kv, 9) != -1) { return assert(false, "kv offset 9"); }
  if (ktx_kv_value_bytes(info.kv, -1) != -1) { return assert(false, "kv bytes -1"); }
  if (!bytes_err_is(ktx_kv_value(f, info.kv, 9), "ktx: key/value index out of range")) {
    return assert(false, "kv value out of range is Err");
  }
  if (ktx_level_offset(info, -1) != -1) { return assert(false, "level offset -1"); }
  if (ktx_level_offset(info, 7) != -1) { return assert(false, "level offset 7"); }
  if (ktx_level_size(info, 7) != -1) { return assert(false, "level size 7"); }
  if (ktx_payload_offset(info, 7) != -1) { return assert(false, "payload offset 7"); }
  if (!bytes_err_is(ktx_level_data(f, info, 7), "ktx: level index out of range")) {
    return assert(false, "level data out of range is Err");
  }
  let short = slice_bytes(f, f.len() - 3);
  if (!bytes_err_is(ktx_level_data(short, info, 1), "ktx: truncated level data")) {
    return assert(false, "level data beyond a short buffer is Err");
  }
  return assert(true, "accessors report out-of-range indices and short buffers");
}

fn main() -> Int {
  io.println("=== xiom.ktx conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.ktx: all tests passed");
  } else {
    io.println("xiom.ktx: tests failed");
  }
  return failed;
}
