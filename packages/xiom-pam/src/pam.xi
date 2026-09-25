// XIOM -- xiom.pam: Netpbm PAM (P7) parsing, raster spans and building
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. Reads and writes the Netpbm PAM (P7) format on flat
// Vec[UInt8] buffers:
//
//   header := "P7" LF (field | comment | blank)* "ENDHDR" LF
//   field  := "WIDTH" n | "HEIGHT" n | "DEPTH" n | "MAXVAL" n | "TUPLTYPE" s
//
// WIDTH, HEIGHT, DEPTH and MAXVAL are each required exactly once and may
// appear in any order; TUPLTYPE is optional and repeatable, and each value is
// preserved verbatim in header order. A line whose first non-blank byte is
// '#' is a comment; blank lines are allowed. The raster starts immediately
// after the LF that terminates ENDHDR: width * height * depth samples,
// row-major, one byte per sample for MAXVAL <= 255 and two bytes big-endian
// for MAXVAL 256..65535, with no padding or alignment anywhere. The module
// never interprets the samples or the tuple type; both are the caller's.
// See SPEC.md for the exact grammar and the error catalog.

module xiom.pam

use xiom.string;
use xiom.string.builder;

// A parsed PAM header plus the derived raster span into the source buffer.
pub type PamImage = {
  width: Int;            // 1..1000000
  height: Int;           // 1..1000000
  depth: Int;            // 1..1000000
  maxval: Int;           // 1..65535
  bytes_per_sample: Int; // 1 for maxval <= 255, 2 for maxval 256..65535
  data_offset: Int;      // first raster byte in the source buffer
  raster_len: Int;       // width * height * depth * bytes_per_sample
  tupltypes: Vec[Str];   // TUPLTYPE values, in header order (may be empty)
}

// ---------------------------------------------------------------------------
// Result leaf helpers (v0.61.3: Ok/Err may only appear in fns that return a
// Result directly, so every fallible public fn returns through one of these).
// ---------------------------------------------------------------------------

fn _err_img(m: Str) -> Result[PamImage, Str] { return Err(m); }
fn _ok_img(i: PamImage) -> Result[PamImage, Str] { return Ok(i); }
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// ---------------------------------------------------------------------------
// Byte and line scanners
// ---------------------------------------------------------------------------

// Unsigned byte at index i (widening masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// Header whitespace inside a line: SPACE or TAB.
fn _is_hspace(b: Int) -> Bool {
  if (b == 32) { return true; }
  if (b == 9) { return true; }
  return false;
}

// ASCII decimal digit byte.
fn _is_digit(b: Int) -> Bool {
  if (b < 48) { return false; }
  if (b > 57) { return false; }
  return true;
}

// Index of the LF that terminates the header line starting at `start`, or -1
// when the line is not LF-terminated before EOF.
fn _line_lf(data: &Vec[UInt8], n: Int, start: Int) -> Int {
  var i = start;
  while (i < n) {
    if (_b(data, i) == 10) { return i; }
    i = i + 1;
  }
  return -1;
}

// End of the line content: `lf` minus one when the byte before it is CR, so
// CRLF line endings are accepted everywhere in the header.
fn _content_end(data: &Vec[UInt8], start: Int, lf: Int) -> Int {
  var e = lf;
  if (e > start) {
    if (_b(data, e - 1) == 13) { e = e - 1; }
  }
  return e;
}

// First index at or after `start` (below `end`) that is neither SPACE nor TAB.
fn _skip_hspace(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  var i = start;
  while (i < end) {
    let c = _b(data, i);
    if (!_is_hspace(c)) { break; }
    i = i + 1;
  }
  return i;
}

// Length of the digit run at `start`, bounded by `end` (0 when not a digit).
fn _dec_len(data: &Vec[UInt8], end: Int, start: Int) -> Int {
  var i = start;
  while (i < end) {
    let c = _b(data, i);
    if (!_is_digit(c)) { break; }
    i = i + 1;
  }
  return i - start;
}

// Value of data[start, start+len), a non-empty digit run of at most 9 digits.
fn _dec_value(data: &Vec[UInt8], start: Int, len: Int) -> Int {
  var v = 0;
  var i = 0;
  while (i < len) {
    let c = _b(data, start + i);
    v = v * 10 + (c - 48);
    i = i + 1;
  }
  return v;
}

// Value of a numeric header line tail [start, end): skips SPACE/TAB, requires
// exactly one decimal token of at most 9 digits and nothing but SPACE/TAB
// after it. Codes: -1 no value token, -2 trailing tokens, -3 too many digits,
// otherwise the non-negative value. Range checks are the caller's job.
fn _line_value(data: &Vec[UInt8], start: Int, end: Int) -> Int {
  var i = _skip_hspace(data, start, end);
  let len = _dec_len(data, end, i);
  if (len == 0) { return -1; }
  if (len > 9) { return -3; }
  let v = _dec_value(data, i, len);
  i = _skip_hspace(data, i + len, end);
  if (i < end) { return -2; }
  return v;
}

// True when data[start, end) is exactly the ASCII literal `key`.
fn _key_is(data: &Vec[UInt8], start: Int, end: Int, key: Str) -> Bool {
  if (end - start != key.len()) { return false; }
  var i = 0;
  while (i < key.len()) {
    let a = _b(data, start + i);
    let b: UInt8 = string.byte_at(key, i);
    if (a != ((b as Int) & 0xFF)) { return false; }
    i = i + 1;
  }
  return true;
}

// A tuple type value must be non-empty and contain only bytes 32..126 or
// >= 128: no control bytes, no TAB, no NUL, no DEL. The caller has already
// trimmed the value, so leading/trailing SPACE is impossible here.
fn _tuple_range_ok(data: &Vec[UInt8], start: Int, end: Int) -> Bool {
  if (start >= end) { return false; }
  var i = start;
  while (i < end) {
    let v = _b(data, i);
    if (v < 32) { return false; }
    if (v == 127) { return false; }
    i = i + 1;
  }
  return true;
}

// True when the Str `t` is a value pam_build may emit as one TUPLTYPE line:
// non-empty, every byte 32..126 or >= 128, and no SPACE at either end, so the
// emitted line parses back to the same value.
fn _tuple_type_ok(t: Str) -> Bool {
  let n = t.len();
  if (n == 0) { return false; }
  var i = 0;
  while (i < n) {
    let b: UInt8 = string.byte_at(t, i);
    let v: Int = (b as Int) & 0xFF;
    if (v < 32) { return false; }
    if (v == 127) { return false; }
    i = i + 1;
  }
  let f: UInt8 = string.byte_at(t, 0);
  if (((f as Int) & 0xFF) == 32) { return false; }
  let l: UInt8 = string.byte_at(t, n - 1);
  if (((l as Int) & 0xFF) == 32) { return false; }
  return true;
}

// Copy data[start, end) into a fresh Str. Callers must validate the bytes
// first: builder.sb_to_str is NUL-terminated, so a 0x00 byte would abort.
fn _bytes_to_str(data: &Vec[UInt8], start: Int, end: Int) -> Str {
  let sb = Vec[UInt8].new();
  var i = start;
  while (i < end) {
    let b: UInt8 = data[i];
    sb.push(b);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// ---------------------------------------------------------------------------
// Writers (builders)
// ---------------------------------------------------------------------------

// Append the ASCII decimal spelling of v (v >= 0) to out.
fn _put_decimal(out: &mut Vec[UInt8], v: Int) {
  if (v == 0) {
    out.push(48 as UInt8);
    return;
  }
  let tmp = Vec[UInt8].new();
  var n = v;
  while (n > 0) {
    let d: Int = n % 10;
    tmp.push((48 + d) as UInt8);
    n = n / 10;
  }
  var i = tmp.len() - 1;
  while (i >= 0) {
    let b: UInt8 = tmp[i];
    out.push(b);
    i = i - 1;
  }
}

// Append every byte of `s` to out.
fn _put_str(out: &mut Vec[UInt8], s: Str) {
  let n = s.len();
  var i = 0;
  while (i < n) {
    let b: UInt8 = string.byte_at(s, i);
    out.push(b);
    i = i + 1;
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// Bytes per raster sample for `maxval`: 1 for 1..255, 2 for 256..65535, and 0
// when maxval is outside the PAM range (bad bytes-per-sample). A parsed or
// built image therefore always has 1 or 2.
pub fn pam_bytes_per_sample(maxval: Int) -> Int {
  if (maxval <= 0) { return 0; }
  if (maxval <= 255) { return 1; }
  if (maxval <= 65535) { return 2; }
  return 0;
}

// Raster width in pixels (always 1..1000000 for a parsed image).
pub fn pam_width(img: &PamImage) -> Int {
  return img.width;
}

// Raster height in rows (always 1..1000000 for a parsed image).
pub fn pam_height(img: &PamImage) -> Int {
  return img.height;
}

// Tuple depth (samples per tuple, always 1..1000000 for a parsed image).
pub fn pam_depth(img: &PamImage) -> Int {
  return img.depth;
}

// Sample maximum (always 1..65535 for a parsed image).
pub fn pam_maxval(img: &PamImage) -> Int {
  return img.maxval;
}

// Offset of the first raster byte in the buffer passed to pam_parse_header.
pub fn pam_raster_offset(img: &PamImage) -> Int {
  return img.data_offset;
}

// Exact raster span length in bytes: width * height * depth * bytes-per-sample.
pub fn pam_raster_len(img: &PamImage) -> Int {
  return img.raster_len;
}

// Number of TUPLTYPE header lines (0 or more).
pub fn pam_tupltype_count(img: &PamImage) -> Int {
  let ts: Vec[Str] = img.tupltypes;
  return ts.len();
}

// The `index`-th TUPLTYPE value in header order. Returns "" when `index` is
// negative or at/above pam_tupltype_count: parsed values are never empty, so
// the sentinel is unambiguous.
pub fn pam_tupltype(img: &PamImage, index: Int) -> Str {
  let ts: Vec[Str] = img.tupltypes;
  if (index < 0) { return ""; }
  if (index >= ts.len()) { return ""; }
  let e: Str = ts[index];
  return e;
}

// The effective tuple type: the TUPLTYPE values joined with a single SPACE in
// header order, or "" when the header had none.
pub fn pam_tuple_type(img: &PamImage) -> Str {
  let ts: Vec[Str] = img.tupltypes;
  let n = ts.len();
  if (n == 0) { return ""; }
  let sb = Vec[UInt8].new();
  var i = 0;
  while (i < n) {
    let e: Str = ts[i];
    if (i > 0) { builder.sb_push_byte(&mut sb, 32 as UInt8); }
    builder.sb_push_str(&mut sb, e);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Parse and validate a complete single-image PAM buffer: header plus the
// exact raster. Returns the header fields plus the raster span
// (data_offset, raster_len). The buffer must contain exactly that span after
// ENDHDR: shorter input is "pam: truncated raster", longer input is
// "pam: extra raster bytes". Multi-image PAM streams are out of scope.
pub fn pam_parse_header(data: &Vec[UInt8]) -> Result[PamImage, Str] {
  let n = data.len();
  if (n < 3) { return _err_img("pam: truncated header"); }
  if (_b(data, 0) != 80) { return _err_img("pam: bad magic"); }
  if (_b(data, 1) != 55) { return _err_img("pam: bad magic"); }
  var pos = 0;
  let c2 = _b(data, 2);
  if (c2 == 10) {
    pos = 3;
  } else {
    if (c2 == 13) {
      if (n < 4) { return _err_img("pam: truncated header"); }
      if (_b(data, 3) != 10) { return _err_img("pam: missing newline after magic"); }
      pos = 4;
    } else {
      return _err_img("pam: missing newline after magic");
    }
  }

  var width = 0;
  var height = 0;
  var depth = 0;
  var maxval = 0;
  var have_w = false;
  var have_h = false;
  var have_d = false;
  var have_m = false;
  let tupltypes = Vec[Str].new();
  var saw_end = false;

  while (!saw_end) {
    if (pos >= n) { return _err_img("pam: missing ENDHDR"); }
    let lf = _line_lf(data, n, pos);
    if (lf < 0) { return _err_img("pam: missing ENDHDR"); }
    let cend = _content_end(data, pos, lf);
    let next = lf + 1;
    let fs = _skip_hspace(data, pos, cend);
    if (fs < cend) {
      if (_b(data, fs) == 35) {
        // Comment line: whole line ignored.
      } else {
        var ke = fs;
        while (ke < cend) {
          let k = _b(data, ke);
          if (_is_hspace(k)) { break; }
          ke = ke + 1;
        }
        if (_key_is(data, fs, ke, "ENDHDR")) {
          if (_skip_hspace(data, ke, cend) < cend) {
            return _err_img("pam: malformed header line");
          }
          saw_end = true;
        } else {
          if (_key_is(data, fs, ke, "WIDTH")) {
            if (have_w) { return _err_img("pam: duplicate width"); }
            let v = _line_value(data, ke, cend);
            if (v == -1) { return _err_img("pam: missing width"); }
            if (v == -2) { return _err_img("pam: malformed header line"); }
            if (v == -3) { return _err_img("pam: invalid width"); }
            if (v <= 0) { return _err_img("pam: invalid width"); }
            if (v > 1000000) { return _err_img("pam: invalid width"); }
            width = v;
            have_w = true;
          } else {
            if (_key_is(data, fs, ke, "HEIGHT")) {
              if (have_h) { return _err_img("pam: duplicate height"); }
              let v = _line_value(data, ke, cend);
              if (v == -1) { return _err_img("pam: missing height"); }
              if (v == -2) { return _err_img("pam: malformed header line"); }
              if (v == -3) { return _err_img("pam: invalid height"); }
              if (v <= 0) { return _err_img("pam: invalid height"); }
              if (v > 1000000) { return _err_img("pam: invalid height"); }
              height = v;
              have_h = true;
            } else {
              if (_key_is(data, fs, ke, "DEPTH")) {
                if (have_d) { return _err_img("pam: duplicate depth"); }
                let v = _line_value(data, ke, cend);
                if (v == -1) { return _err_img("pam: missing depth"); }
                if (v == -2) { return _err_img("pam: malformed header line"); }
                if (v == -3) { return _err_img("pam: invalid depth"); }
                if (v <= 0) { return _err_img("pam: invalid depth"); }
                if (v > 1000000) { return _err_img("pam: invalid depth"); }
                depth = v;
                have_d = true;
              } else {
                if (_key_is(data, fs, ke, "MAXVAL")) {
                  if (have_m) { return _err_img("pam: duplicate maxval"); }
                  let v = _line_value(data, ke, cend);
                  if (v == -1) { return _err_img("pam: missing maxval"); }
                  if (v == -2) { return _err_img("pam: malformed header line"); }
                  if (v == -3) { return _err_img("pam: invalid maxval"); }
                  if (v <= 0) { return _err_img("pam: invalid maxval"); }
                  if (v > 65535) { return _err_img("pam: invalid maxval"); }
                  maxval = v;
                  have_m = true;
                } else {
                  if (_key_is(data, fs, ke, "TUPLTYPE")) {
                    var vs = _skip_hspace(data, ke, cend);
                    var ve = cend;
                    while (ve > vs) {
                      let t = _b(data, ve - 1);
                      if (!_is_hspace(t)) { break; }
                      ve = ve - 1;
                    }
                    if (!_tuple_range_ok(data, vs, ve)) {
                      return _err_img("pam: invalid tuple type");
                    }
                    let t = _bytes_to_str(data, vs, ve);
                    tupltypes.push(t);
                  } else {
                    return _err_img("pam: unknown header key");
                  }
                }
              }
            }
          }
        }
      }
    }
    pos = next;
  }

  if (!have_w) { return _err_img("pam: missing width"); }
  if (!have_h) { return _err_img("pam: missing height"); }
  if (!have_d) { return _err_img("pam: missing depth"); }
  if (!have_m) { return _err_img("pam: missing maxval"); }

  let bps = pam_bytes_per_sample(maxval);
  let rlen = width * height * depth * bps;
  let avail = n - pos;
  if (avail < rlen) { return _err_img("pam: truncated raster"); }
  if (avail > rlen) { return _err_img("pam: extra raster bytes"); }

  let img = PamImage{
    width: width;
    height: height;
    depth: depth;
    maxval: maxval;
    bytes_per_sample: bps;
    data_offset: pos;
    raster_len: rlen;
    tupltypes: tupltypes;
  };
  return _ok_img(img);
}

// Copy the exact raster span of `img` out of `data` (flat bytes, no padding).
// Guards the span against `data` so a forged or stale image cannot read out of
// bounds; that is "pam: raster out of range".
pub fn pam_raster_copy(data: &Vec[UInt8], img: &PamImage) -> Result[Vec[UInt8], Str] {
  if (img.data_offset < 0) { return _err_bytes("pam: raster out of range"); }
  if (img.raster_len < 0) { return _err_bytes("pam: raster out of range"); }
  if (img.data_offset + img.raster_len > data.len()) {
    return _err_bytes("pam: raster out of range");
  }
  let out = Vec[UInt8].new();
  var i = 0;
  while (i < img.raster_len) {
    let b: UInt8 = data[img.data_offset + i];
    out.push(b);
    i = i + 1;
  }
  return _ok_bytes(out);
}

// Build a canonical single-image PAM byte string: "P7", then WIDTH, HEIGHT,
// DEPTH and MAXVAL in that order, then one "TUPLTYPE <value>" line per value
// in order, then "ENDHDR", every line LF-terminated, then the raster copied
// verbatim (no padding). `raster` must be exactly
// width*height*depth*bytes-per-sample bytes long; tuple type values must be
// single-line printable strings with no leading or trailing space.
pub fn pam_build(width: Int, height: Int, depth: Int, maxval: Int, tupltypes: &Vec[Str], raster: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  if (width <= 0) { return _err_bytes("pam: invalid width"); }
  if (width > 1000000) { return _err_bytes("pam: invalid width"); }
  if (height <= 0) { return _err_bytes("pam: invalid height"); }
  if (height > 1000000) { return _err_bytes("pam: invalid height"); }
  if (depth <= 0) { return _err_bytes("pam: invalid depth"); }
  if (depth > 1000000) { return _err_bytes("pam: invalid depth"); }
  if (maxval <= 0) { return _err_bytes("pam: invalid maxval"); }
  if (maxval > 65535) { return _err_bytes("pam: invalid maxval"); }
  let bps = pam_bytes_per_sample(maxval);
  let need = width * height * depth * bps;
  if (raster.len() != need) { return _err_bytes("pam: raster buffer size mismatch"); }
  let nt = tupltypes.len();
  var i = 0;
  while (i < nt) {
    let t: Str = tupltypes[i];
    if (!_tuple_type_ok(t)) { return _err_bytes("pam: invalid tuple type"); }
    i = i + 1;
  }

  let out = Vec[UInt8].new();
  out.push(80 as UInt8); // 'P'
  out.push(55 as UInt8); // '7'
  out.push(10 as UInt8);
  _put_str(&mut out, "WIDTH ");
  _put_decimal(&mut out, width);
  out.push(10 as UInt8);
  _put_str(&mut out, "HEIGHT ");
  _put_decimal(&mut out, height);
  out.push(10 as UInt8);
  _put_str(&mut out, "DEPTH ");
  _put_decimal(&mut out, depth);
  out.push(10 as UInt8);
  _put_str(&mut out, "MAXVAL ");
  _put_decimal(&mut out, maxval);
  out.push(10 as UInt8);
  i = 0;
  while (i < nt) {
    let t: Str = tupltypes[i];
    _put_str(&mut out, "TUPLTYPE ");
    _put_str(&mut out, t);
    out.push(10 as UInt8);
    i = i + 1;
  }
  _put_str(&mut out, "ENDHDR");
  out.push(10 as UInt8);
  i = 0;
  while (i < need) {
    let b: UInt8 = raster[i];
    out.push(b);
    i = i + 1;
  }
  return _ok_bytes(out);
}
