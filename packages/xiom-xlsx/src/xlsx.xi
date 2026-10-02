// XIOM -- xiom.xlsx: pure-XIOM SpreadsheetML (XLSX) reader/writer
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XLSX is a ZIP container of XML parts. This module implements both halves
// without FFI and without leaving xiom.std:
//
//   * a minimal ZIP container: local file headers (PK x03 x04), central
//     directory (PK x01 x02) and EOCD (PK x05 x06). STORED (method 0) and
//     DEFLATE (method 8) entries are written with the real stdlib deflate
//     stack (fixed-Huffman producer); reading supports STORED and deflate
//     streams the stdlib inflater accepts (STORED + FIXED Huffman blocks).
//     Dynamic-Huffman streams (what zlib/Excel usually emit) are rejected
//     with a clear error -- see SPEC.md, documented limitation.
//   * a minimal SpreadsheetML subset: [Content_Types].xml, _rels/.rels,
//     xl/workbook.xml (+rels), xl/worksheets/sheetN.xml, xl/styles.xml and
//     xl/sharedStrings.xml. Cells: number (no t), shared string (t="s"),
//     inline string (t="inlineStr"), formula string (t="str"), bool (t="b").
//     Reading also accepts rich-text shared strings.
//   * a sparse cell model (sheet/row/col/kind/value tuples over parallel
//     vectors) with last-write-wins lookups.
//
// v0.62.x notes that shaped this module:
//   * free functions only, no self methods, no lambdas, no Vec[fn]
//     dispatch, no Vec[StructType] (parallel vectors instead);
//   * Ok/Err for struct payloads are constructed only in the tiny leaf
//     helpers below;
//   * every Vec element read is bound to an explicitly typed local first;
//     Str values read from Vec[Str] are compared with
//     xiom.string.compare.str_compare, never `==`;
//   * every UInt8 is widened with `(b as Int) & 0xFF` before Int math;
//   * `&mut Vec` parameters always receive an explicit `&mut` at the call
//     site; `&struct.field` is never passed where `&Vec[UInt8]` is expected
//     (payloads are bound to locals first);
//   * numeric cells are fixed-point scaled Ints (scale 1_000_000), never
//     Float64 (Vec[Float64] is banned and rounding is documented in SPEC);
//   * output is built in Vec[UInt8] builders and materialized with
//     sb_to_str only after NUL validation (sb_to_str aborts on 0x00).

module xiom.xlsx

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;
use xiom.compress.deflate;
use xiom.hash.hash;

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[XlsxZip, Str].
fn _ok_zip(v: XlsxZip) -> Result[XlsxZip, Str] {
  return Ok(v);
}

// Err(m) for Result[XlsxZip, Str].
fn _err_zip(m: Str) -> Result[XlsxZip, Str] {
  return Err(m);
}

// Ok(v) for Result[XlsxWorkbook, Str].
fn _ok_wb(v: XlsxWorkbook) -> Result[XlsxWorkbook, Str] {
  return Ok(v);
}

// Err(m) for Result[XlsxWorkbook, Str].
fn _err_wb(m: Str) -> Result[XlsxWorkbook, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// A scanned ZIP archive. Payload bytes are decompressed eagerly into one
/// shared pool: pool[poff[i] .. poff[i] + usize[i]) is entry i's data.
/// All parallel vectors have exactly names.len() entries.
pub type XlsxZip = {
  names: Vec[Str];
  methods: Vec[Int];
  crcs: Vec[Int];
  csize: Vec[Int];
  usize: Vec[Int];
  pool: Vec[UInt8];
  poff: Vec[Int];
}

/// A sparse workbook model: cells are (sheet, row, col, value) tuples kept
/// in parallel vectors; rows and columns are zero-based; a lookup returns the
/// LAST cell set at a coordinate so re-setting the same cell overrides it.
/// Styles are workbook-level records referenced by cells; cell_style -1
/// means "no style". str_pool deduplicates all string cell values.
pub type XlsxWorkbook = {
  sheet_names: Vec[Str];
  cell_sheet: Vec[Int];
  cell_row: Vec[Int];
  cell_col: Vec[Int];
  cell_kind: Vec[Int];
  cell_num: Vec[Int];
  cell_bool: Vec[Int];
  cell_str: Vec[Int];
  cell_style: Vec[Int];
  str_pool: Vec[Str];
  sty_bold: Vec[Int];
  sty_italic: Vec[Int];
  sty_size: Vec[Int];
  sty_color: Vec[Int];
  sty_fmt: Vec[Str];
}

// --------------------------------------------------
//  Constants
// --------------------------------------------------

const _XLSX_SCALE: Int = 1000000;
const _K_NUM: Int = 0;
const _K_STR: Int = 1;
const _K_BOOL: Int = 2;
const _MAX_SHEETS: Int = 1024;
const _MAX_CELLS: Int = 1000000;
const _MAX_STRINGS: Int = 1000000;
const _MAX_STYLES: Int = 100000;
const _B_LT: UInt8 = 60u8;

// --------------------------------------------------
//  Byte / integer helpers
// --------------------------------------------------

fn _is_ws_c(c: Int) -> Bool {
  if c == 32 || c == 9 || c == 10 || c == 13 {
    return true;
  }
  return false;
}

fn _pow10(n: Int) -> Int {
  var r = 1;
  var i = 0;
  while i < n && i < 18 {
    r = r * 10;
    i = i + 1;
  }
  return r;
}

fn _put_u16(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
}

fn _put_u32(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

fn _push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  let n = s.len();
  while i < n {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

fn _push_bytes(out: &mut Vec[UInt8], b: &Vec[UInt8]) {
  var i = 0;
  let n = b.len();
  while i < n {
    let v: UInt8 = b[i];
    out.push(v);
    i = i + 1;
  }
}

// Copy [off, off+len) out of buf; empty on any out-of-range request.
fn _slice_copy(buf: &Vec[UInt8], off: Int, len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if off < 0 || len < 0 {
    return out;
  }
  if off + len > buf.len() {
    return out;
  }
  var i = 0;
  while i < len {
    let v: UInt8 = buf[off + i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

// Materialize [off, off+len) of buf as a Str; Err on NUL (sb_to_str aborts
// on 0x00) or out-of-range. Never builds from bytes that may contain 0x00.
fn _range_to_str(buf: &Vec[UInt8], off: Int, len: Int) -> Result[Str, Str] {
  if off < 0 || len < 0 || off + len > buf.len() {
    return _err_str("xlsx: byte range out of bounds");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < len {
    let v: UInt8 = buf[off + i];
    let w: Int = (v as Int) & 0xFF;
    if w == 0 {
      return _err_str("xlsx: byte range contains nul");
    }
    out.push(v);
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&out));
}

fn _hex_digit(d: Int) -> UInt8 {
  if d < 10 {
    return (48 + d) as UInt8;
  }
  return (55 + d) as UInt8;
}

fn _put_hex_byte(out: &mut Vec[UInt8], v: Int) {
  out.push(_hex_digit((v / 16) % 16));
  out.push(_hex_digit(v % 16));
}

// Push the 8 uppercase hex digits of an ARGB color (0xAARRGGBB).
fn _put_argb(out: &mut Vec[UInt8], v: Int) {
  _put_hex_byte(out, (v / 16777216) % 256);
  _put_hex_byte(out, (v / 65536) % 256);
  _put_hex_byte(out, (v / 256) % 256);
  _put_hex_byte(out, v % 256);
}

fn _hex_val(c: Int) -> Int {
  if c >= 48 && c <= 57 {
    return c - 48;
  }
  if c >= 65 && c <= 70 {
    return c - 55;
  }
  if c >= 97 && c <= 102 {
    return c - 87;
  }
  return -1;
}

// Parse 6 or 8 hex digits into an ARGB Int; -1 when malformed.
fn _hex_parse(s: Str) -> Int {
  let n = s.len();
  if n != 6 && n != 8 {
    return -1;
  }
  var v = 0;
  var i = 0;
  while i < n {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    let d = _hex_val(c);
    if d < 0 {
      return -1;
    }
    v = v * 16 + d;
    i = i + 1;
  }
  if n == 6 {
    v = v + 4278190080;
  }
  return v;
}

// --------------------------------------------------
//  Numeric literals (fixed-point, scale 1_000_000)
// --------------------------------------------------

/// Parse a decimal literal (optional sign / fraction / e-exponent) into a
/// fixed-point scaled Int. Up to 6 fractional digits are exact; more are
/// rounded half away from zero. Values with more than 18 significant digits
/// are truncated (documented in SPEC.md).
fn _dec_parse(text: Str, a: Int, b: Int) -> Result[Int, Str] {
  var i = a;
  var j = b;
  while i < j {
    let w: Int = (string.byte_at(text, i) as Int) & 0xFF;
    if !_is_ws_c(w) {
      break;
    }
    i = i + 1;
  }
  while j > i {
    let w2: Int = (string.byte_at(text, j - 1) as Int) & 0xFF;
    if !_is_ws_c(w2) {
      break;
    }
    j = j - 1;
  }
  if i >= j {
    return _err_int("xlsx: invalid numeric literal");
  }
  var sign = 1;
  let c0: Int = (string.byte_at(text, i) as Int) & 0xFF;
  if c0 == 43 {
    i = i + 1;
  } else {
    if c0 == 45 {
      sign = -1;
      i = i + 1;
    };
  };
  var man = 0;
  var digits = 0;
  var frac = 0;
  var dot = false;
  while i < j {
    let c: Int = (string.byte_at(text, i) as Int) & 0xFF;
    if c >= 48 && c <= 57 {
      if digits < 18 {
        man = man * 10 + (c - 48);
        digits = digits + 1;
      };
      if dot {
        frac = frac + 1;
      };
      i = i + 1;
    } else {
      if c == 46 && !dot {
        dot = true;
        i = i + 1;
      } else {
        break;
      };
    };
  }
  if digits == 0 {
    return _err_int("xlsx: invalid numeric literal");
  }
  var exp10 = 0;
  if i < j {
    let ec: Int = (string.byte_at(text, i) as Int) & 0xFF;
    if ec == 69 || ec == 101 {
      i = i + 1;
      var esign = 1;
      if i < j {
        let sc: Int = (string.byte_at(text, i) as Int) & 0xFF;
        if sc == 43 {
          i = i + 1;
        } else {
          if sc == 45 {
            esign = -1;
            i = i + 1;
          };
        };
      };
      var ev = 0;
      var ed = 0;
      while i < j {
        let dc: Int = (string.byte_at(text, i) as Int) & 0xFF;
        if dc < 48 || dc > 57 {
          break;
        }
        ev = ev * 10 + (dc - 48);
        ed = ed + 1;
        if ed > 3 || ev > 320 {
          return _err_int("xlsx: exponent out of range");
        }
        i = i + 1;
      }
      if ed == 0 {
        return _err_int("xlsx: invalid numeric literal");
      }
      exp10 = esign * ev;
    };
  }
  if i != j {
    return _err_int("xlsx: invalid numeric literal");
  }
  let shift = 6 + exp10 - frac;
  var mag = man;
  if shift >= 0 {
    if shift > 18 {
      return _err_int("xlsx: numeric literal out of range");
    }
    let p = _pow10(shift);
    if man > 9223372036854775807 / p {
      return _err_int("xlsx: numeric literal out of range");
    }
    mag = man * p;
  } else {
    let k = 0 - shift;
    if k >= 19 {
      mag = 0;
    } else {
      let d = _pow10(k);
      var q = man / d;
      let rm = man % d;
      if rm * 2 >= d {
        q = q + 1;
      }
      mag = q;
    };
  };
  if sign < 0 {
    mag = 0 - mag;
  }
  return _ok_int(mag);
}

/// Parse a whole decimal integer (no fraction/exponent).
fn _int_parse_str(text: Str, a: Int, b: Int) -> Result[Int, Str] {
  var i = a;
  var j = b;
  while i < j {
    let w: Int = (string.byte_at(text, i) as Int) & 0xFF;
    if !_is_ws_c(w) {
      break;
    }
    i = i + 1;
  }
  while j > i {
    let w2: Int = (string.byte_at(text, j - 1) as Int) & 0xFF;
    if !_is_ws_c(w2) {
      break;
    }
    j = j - 1;
  }
  var sign = 1;
  if i < j {
    let c0: Int = (string.byte_at(text, i) as Int) & 0xFF;
    if c0 == 43 {
      i = i + 1;
    } else {
      if c0 == 45 {
        sign = -1;
        i = i + 1;
      };
    };
  };
  var v = 0;
  var digits = 0;
  while i < j {
    let c: Int = (string.byte_at(text, i) as Int) & 0xFF;
    if c < 48 || c > 57 {
      return _err_int("xlsx: invalid integer literal");
    }
    if digits >= 18 {
      return _err_int("xlsx: integer literal out of range");
    }
    v = v * 10 + (c - 48);
    digits = digits + 1;
    i = i + 1;
  }
  if digits == 0 {
    return _err_int("xlsx: invalid integer literal");
  }
  if sign < 0 {
    v = 0 - v;
  }
  return _ok_int(v);
}

/// Parse a decimal literal to fixed-point micro-units (scale 1_000_000).
pub fn xlsx_number_parse(s: Str) -> Result[Int, Str] {
  return _dec_parse(s, 0, s.len());
}

/// Render fixed-point micro-units as a plain decimal (3.14, -2, 0.000001);
/// trailing fractional zeros are trimmed.
pub fn xlsx_number_to_str(scaled: Int) -> Str {
  var out = Vec[UInt8].new();
  _scaled_into(&mut out, scaled);
  return builder.sb_to_str(&out);
}

fn _scaled_into(out: &mut Vec[UInt8], v: Int) {
  var n = v;
  if n < 0 {
    out.push(45u8);
    n = 0 - n;
  };
  let ip = n / _XLSX_SCALE;
  var fp = n % _XLSX_SCALE;
  builder.sb_push_int(out, ip);
  if fp == 0 {
    return;
  }
  out.push(46u8);
  var div = 100000;
  while div > 0 {
    let dig = fp / div;
    fp = fp % div;
    out.push((48 + dig) as UInt8);
    div = div / 10;
  };
  // trim trailing fractional zeros (fp != 0, so a non-zero digit remains)
  var trims = 0;
  var done_trim = false;
  while !done_trim && trims < 6 {
    let last: UInt8 = out[out.len() - 1];
    if last == 48u8 {
      out.pop();
      trims = trims + 1;
    } else {
      done_trim = true;
    };
  };
}

/// The fixed-point scale used for numeric cells.
pub fn xlsx_scale() -> Int {
  return _XLSX_SCALE;
}

// --------------------------------------------------
//  XML escape / unescape
// --------------------------------------------------

/// XML-escape a Str: & < > " ' and CR become entities; control bytes below
/// 0x20 (except tab/LF) become &#xNN; references; UTF-8 bytes pass through.
pub fn xlsx_xml_escape(s: Str) -> Str {
  var out = Vec[UInt8].new();
  _xml_escape_into(&mut out, s);
  return builder.sb_to_str(&out);
}

fn _xml_escape_into(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  let n = s.len();
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 38 {
      _push_str(out, "&amp;");
    } else {
      if b == 60 {
        _push_str(out, "&lt;");
      } else {
        if b == 62 {
          _push_str(out, "&gt;");
        } else {
          if b == 34 {
            _push_str(out, "&quot;");
          } else {
            if b == 39 {
              _push_str(out, "&apos;");
            } else {
              if b == 13 {
                _push_str(out, "&#xD;");
              } else {
                if b < 32 && b != 9 && b != 10 {
                  _push_str(out, "&#x");
                  _put_hex_byte(out, b);
                  out.push(59u8);
                } else {
                  out.push((b % 256) as UInt8);
                };
              };
            };
          };
        };
      };
    };
    i = i + 1;
  }
}

/// Decode XML entities and numeric character references in `s`. Rejects NUL
/// references, surrogate halves and unknown entities; raw control bytes in
/// the input are rejected, but references to control code points (which the
/// writer emits for control characters) decode to their bytes.
pub fn xlsx_xml_unescape(s: Str) -> Result[Str, Str] {
  return _xml_unescape(s, 0, s.len());
}

fn _utf8_push(out: &mut Vec[UInt8], cp: Int) {
  if cp < 128 {
    out.push((cp % 256) as UInt8);
    return;
  }
  if cp < 2048 {
    out.push((192 + cp / 64) as UInt8);
    out.push((128 + cp % 64) as UInt8);
    return;
  }
  if cp < 65536 {
    out.push((224 + cp / 4096) as UInt8);
    out.push((128 + (cp / 64) % 64) as UInt8);
    out.push((128 + cp % 64) as UInt8);
    return;
  }
  out.push((240 + cp / 262144) as UInt8);
  out.push((128 + (cp / 4096) % 64) as UInt8);
  out.push((128 + (cp / 64) % 64) as UInt8);
  out.push((128 + cp % 64) as UInt8);
}

fn _xml_unescape(text: Str, a: Int, b: Int) -> Result[Str, Str] {
  if a < 0 || b < a || b > text.len() {
    return _err_str("xlsx: byte range out of bounds");
  }
  var out = Vec[UInt8].new();
  var i = a;
  while i < b {
    let c: Int = (string.byte_at(text, i) as Int) & 0xFF;
    if c == 38 {
      var j = i + 1;
      var stop = i + 1 + 12;
      if stop > b {
        stop = b;
      };
      var semi = -1;
      while j < stop {
        let sc: Int = (string.byte_at(text, j) as Int) & 0xFF;
        if sc == 59 {
          semi = j;
          j = stop;
        } else {
          j = j + 1;
        };
      }
      if semi < 0 {
        return _err_str("xlsx: xml unterminated entity");
      }
      var k = i + 1;
      let h: Int = (string.byte_at(text, k) as Int) & 0xFF;
      if h == 35 {
        k = k + 1;
        var base = 10;
        if k < semi {
          let xc: Int = (string.byte_at(text, k) as Int) & 0xFF;
          if xc == 120 || xc == 88 {
            base = 16;
            k = k + 1;
          };
        };
        var cp = 0;
        var dd = 0;
        while k < semi {
          let dc: Int = (string.byte_at(text, k) as Int) & 0xFF;
          let dv = _hex_val(dc);
          if dv < 0 || dv >= base {
            return _err_str("xlsx: invalid xml character reference");
          }
          cp = cp * base + dv;
          dd = dd + 1;
          if dd > 7 || cp > 1114111 {
            return _err_str("xlsx: xml character reference out of range");
          }
          k = k + 1;
        }
        if dd == 0 {
          return _err_str("xlsx: invalid xml character reference");
        }
        if cp == 0 {
          return _err_str("xlsx: xml character reference to nul");
        }
        if cp >= 55296 && cp <= 57343 {
          return _err_str("xlsx: invalid xml character reference");
        }
        _utf8_push(&mut out, cp);
      } else {
        let en = string.str_slice(text, i + 1, semi);
        var matched = false;
        if compare.str_compare(en, "amp") == 0 {
          out.push(38u8);
          matched = true;
        } else {
          if compare.str_compare(en, "lt") == 0 {
            out.push(60u8);
            matched = true;
          } else {
            if compare.str_compare(en, "gt") == 0 {
              out.push(62u8);
              matched = true;
            } else {
              if compare.str_compare(en, "quot") == 0 {
                out.push(34u8);
                matched = true;
              } else {
                if compare.str_compare(en, "apos") == 0 {
                  out.push(39u8);
                  matched = true;
                };
              };
            };
          };
        };
        if !matched {
          return _err_str("xlsx: unknown xml entity");
        };
      };
      i = semi + 1;
    } else {
      if c == 0 {
        return _err_str("xlsx: xml raw nul byte");
      }
      if c < 32 && c != 9 && c != 10 && c != 13 {
        return _err_str("xlsx: xml raw control byte");
      }
      out.push((c % 256) as UInt8);
      i = i + 1;
    };
  }
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Tag scanner over an XML text
// --------------------------------------------------

fn _find_byte(text: Str, from: Int, b: UInt8) -> Int {
  var i = from;
  let n = text.len();
  while i < n {
    if string.byte_at(text, i) == b {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

fn _text_until_lt(text: Str, from: Int) -> Int {
  let lt = _find_byte(text, from, _B_LT);
  if lt < 0 {
    return text.len();
  }
  return lt;
}

// Index of the matching > for a tag starting at < at s; quote-aware,
// comment- and PI-aware. -1 when unterminated.
fn _tag_end(text: Str, s: Int) -> Int {
  let n = text.len();
  if s + 1 < n {
    let c1: Int = (string.byte_at(text, s + 1) as Int) & 0xFF;
    if c1 == 33 && s + 3 < n {
      let c2: Int = (string.byte_at(text, s + 2) as Int) & 0xFF;
      let c3: Int = (string.byte_at(text, s + 3) as Int) & 0xFF;
      if c2 == 45 && c3 == 45 {
        var ci = s + 4;
        while ci + 2 < n {
          let d0: Int = (string.byte_at(text, ci) as Int) & 0xFF;
          let d1: Int = (string.byte_at(text, ci + 1) as Int) & 0xFF;
          let d2: Int = (string.byte_at(text, ci + 2) as Int) & 0xFF;
          if d0 == 45 && d1 == 45 && d2 == 62 {
            return ci + 2;
          }
          ci = ci + 1;
        }
        return -1;
      };
    };
    if c1 == 63 {
      var pi = s + 2;
      while pi + 1 < n {
        let q0: Int = (string.byte_at(text, pi) as Int) & 0xFF;
        let q1: Int = (string.byte_at(text, pi + 1) as Int) & 0xFF;
        if q0 == 63 && q1 == 62 {
          return pi + 1;
        }
        pi = pi + 1;
      }
      return -1;
    };
  };
  var i = s + 1;
  var q = 0;
  while i < n {
    let c: Int = (string.byte_at(text, i) as Int) & 0xFF;
    if q == 0 {
      if c == 34 || c == 39 {
        q = c;
      } else {
        if c == 62 {
          return i;
        };
      };
    } else {
      if c == q {
        q = 0;
      };
    };
    i = i + 1;
  }
  return -1;
}

// 0 = opening/self-closing element, 1 = closing element, 2 = comment/PI/other.
fn _tag_kind(text: Str, s: Int, e: Int) -> Int {
  if s + 1 >= e {
    return 2;
  }
  let c: Int = (string.byte_at(text, s + 1) as Int) & 0xFF;
  if c == 47 {
    return 1;
  }
  if c == 63 || c == 33 {
    return 2;
  }
  return 0;
}

fn _tag_self_closing(text: Str, e: Int) -> Bool {
  if e <= 0 {
    return false;
  }
  let c: Int = (string.byte_at(text, e - 1) as Int) & 0xFF;
  return c == 47;
}

fn _name_begin(text: Str, s: Int) -> Int {
  var i = s + 1;
  let n = text.len();
  if i < n {
    let c: Int = (string.byte_at(text, i) as Int) & 0xFF;
    if c == 47 {
      i = i + 1;
    };
  };
  return i;
}

fn _name_end(text: Str, s: Int, e: Int) -> Int {
  var i = s;
  while i < e {
    let c: Int = (string.byte_at(text, i) as Int) & 0xFF;
    if _is_ws_c(c) || c == 47 || c == 62 {
      return i;
    }
    i = i + 1;
  }
  return i;
}

fn _tag_name_is(text: Str, s: Int, e: Int, want: Str) -> Bool {
  let nb = _name_begin(text, s);
  let ne = _name_end(text, nb, e);
  if ne <= nb {
    return false;
  }
  let name = string.str_slice(text, nb, ne);
  return compare.str_compare(name, want) == 0;
}

// Attribute value of `want` in the tag [s, e]; entities decoded. Err when
// the attribute is absent or malformed.
fn _attr(text: Str, s: Int, e: Int, want: Str) -> Result[Str, Str] {
  let nb = _name_begin(text, s);
  var i = _name_end(text, nb, e);
  while i < e {
    let c: Int = (string.byte_at(text, i) as Int) & 0xFF;
    if _is_ws_c(c) || c == 47 {
      i = i + 1;
    } else {
      break;
    };
  }
  while i < e {
    while i < e {
      let cw: Int = (string.byte_at(text, i) as Int) & 0xFF;
      if _is_ws_c(cw) || cw == 47 {
        i = i + 1;
      } else {
        break;
      };
    }
    if i >= e {
      break;
    }
    let ns = i;
    while i < e {
      let c: Int = (string.byte_at(text, i) as Int) & 0xFF;
      if _is_ws_c(c) || c == 61 || c == 47 || c == 62 {
        break;
      }
      i = i + 1;
    }
    let ne = i;
    while i < e {
      let c: Int = (string.byte_at(text, i) as Int) & 0xFF;
      if _is_ws_c(c) {
        i = i + 1;
      } else {
        break;
      };
    }
    var ok = false;
    if i < e {
      let c: Int = (string.byte_at(text, i) as Int) & 0xFF;
      if c == 61 {
        i = i + 1;
        ok = true;
      };
    };
    if !ok {
      return _err_str("xlsx: attribute not found");
    };
    while i < e {
      let c: Int = (string.byte_at(text, i) as Int) & 0xFF;
      if _is_ws_c(c) {
        i = i + 1;
      } else {
        break;
      };
    }
    if i >= e {
      return _err_str("xlsx: attribute not found");
    }
    let quote: Int = (string.byte_at(text, i) as Int) & 0xFF;
    if quote != 34 && quote != 39 {
      return _err_str("xlsx: attribute not found");
    }
    i = i + 1;
    let vs = i;
    var ve = -1;
    while i < e {
      let c: Int = (string.byte_at(text, i) as Int) & 0xFF;
      if c == quote {
        ve = i;
        i = e;
      } else {
        i = i + 1;
      };
    }
    if ve < 0 {
      return _err_str("xlsx: attribute not found");
    }
    let an = string.str_slice(text, ns, ne);
    if compare.str_compare(an, want) == 0 {
      return _xml_unescape(text, vs, ve);
    }
    i = ve + 1;
  }
  return _err_str("xlsx: attribute not found");
}

// Integer attribute; -1 when absent or malformed.
fn _attr_int(text: Str, s: Int, e: Int, want: Str) -> Int {
  let r = _attr(text, s, e, want);
  if !r.is_ok {
    return -1;
  }
  let v: Str = r.value;
  let p = _int_parse_str(v, 0, v.len());
  if !p.is_ok {
    return -1;
  }
  return p.value;
}

// --------------------------------------------------
//  ZIP writer
// --------------------------------------------------

/// Build a ZIP archive from parallel entry descriptions: entry i has name
/// names[i], compression methods[i] (0 STORED, 8 DEFLATE) and payload
/// pool[offs[i] .. offs[i] + lens[i]). The output is deterministic.
pub fn xlsx_zip_write(names: &Vec[Str], methods: &Vec[Int], pool: &Vec[UInt8], offs: &Vec[Int], lens: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  let count = names.len();
  if methods.len() != count {
    return _err_bytes("xlsx: zip input arrays differ in length");
  }
  if offs.len() != count {
    return _err_bytes("xlsx: zip input arrays differ in length");
  }
  if lens.len() != count {
    return _err_bytes("xlsx: zip input arrays differ in length");
  }
  if count > 4096 {
    return _err_bytes("xlsx: too many zip entries");
  }
  var out = Vec[UInt8].new();
  var cdir = Vec[UInt8].new();
  var i = 0;
  while i < count {
    let name: Str = names[i];
    let method: Int = methods[i];
    let off: Int = offs[i];
    let ln: Int = lens[i];
    if off < 0 || ln < 0 || off + ln > pool.len() {
      return _err_bytes("xlsx: zip input range out of bounds");
    }
    let data = _slice_copy(pool, off, ln);
    var comp = Vec[UInt8].new();
    if method == 0 {
      comp = data;
    } else {
      if method == 8 {
        comp = deflate.deflate_compress_level(&data, 6);
      } else {
        return _err_bytes("xlsx: unsupported zip compression method");
      };
    };
    let crc = hash.crc32_ieee(&data);
    let lfh = out.len();
    _put_u32(&mut out, 0x04034b50);
    _put_u16(&mut out, 20);
    _put_u16(&mut out, 0);
    _put_u16(&mut out, method);
    _put_u16(&mut out, 0);
    _put_u16(&mut out, 33);
    _put_u32(&mut out, crc);
    _put_u32(&mut out, comp.len());
    _put_u32(&mut out, ln);
    _put_u16(&mut out, name.len());
    _put_u16(&mut out, 0);
    _push_str(&mut out, name);
    _push_bytes(&mut out, &comp);
    _put_u32(&mut cdir, 0x02014b50);
    _put_u16(&mut cdir, 20);
    _put_u16(&mut cdir, 20);
    _put_u16(&mut cdir, 0);
    _put_u16(&mut cdir, method);
    _put_u16(&mut cdir, 0);
    _put_u16(&mut cdir, 33);
    _put_u32(&mut cdir, crc);
    _put_u32(&mut cdir, comp.len());
    _put_u32(&mut cdir, ln);
    _put_u16(&mut cdir, name.len());
    _put_u16(&mut cdir, 0);
    _put_u16(&mut cdir, 0);
    _put_u16(&mut cdir, 0);
    _put_u16(&mut cdir, 0);
    _put_u32(&mut cdir, 0);
    _put_u32(&mut cdir, lfh);
    _push_str(&mut cdir, name);
    i = i + 1;
  }
  let cd_off = out.len();
  _push_bytes(&mut out, &cdir);
  _put_u32(&mut out, 0x06054b50);
  _put_u16(&mut out, 0);
  _put_u16(&mut out, 0);
  _put_u16(&mut out, count);
  _put_u16(&mut out, count);
  _put_u32(&mut out, cdir.len());
  _put_u32(&mut out, cd_off);
  _put_u16(&mut out, 0);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  ZIP reader
// --------------------------------------------------

fn _match_sig(buf: &Vec[UInt8], off: Int, sig: Int) -> Bool {
  if off < 0 {
    return false;
  }
  if off + 4 > buf.len() {
    return false;
  }
  let b0: Int = (buf[off] as Int) & 0xFF;
  let b1: Int = (buf[off + 1] as Int) & 0xFF;
  let b2: Int = (buf[off + 2] as Int) & 0xFF;
  let b3: Int = (buf[off + 3] as Int) & 0xFF;
  let v = b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
  return v == sig;
}

fn _rd_u16(buf: &Vec[UInt8], off: Int) -> Result[Int, Str] {
  if off < 0 || off + 2 > buf.len() {
    return _err_int("xlsx: truncated zip structure");
  }
  let b0: Int = (buf[off] as Int) & 0xFF;
  let b1: Int = (buf[off + 1] as Int) & 0xFF;
  return _ok_int(b0 + b1 * 256);
}

fn _rd_u32(buf: &Vec[UInt8], off: Int) -> Result[Int, Str] {
  if off < 0 || off + 4 > buf.len() {
    return _err_int("xlsx: truncated zip structure");
  }
  let b0: Int = (buf[off] as Int) & 0xFF;
  let b1: Int = (buf[off + 1] as Int) & 0xFF;
  let b2: Int = (buf[off + 2] as Int) & 0xFF;
  let b3: Int = (buf[off + 3] as Int) & 0xFF;
  return _ok_int(b0 + b1 * 256 + b2 * 65536 + b3 * 16777216);
}

fn _zip_add(z: &mut XlsxZip, name: Str, method: Int, crc: Int, csize: Int, usize: Int, data: Vec[UInt8]) {
  z.names.push(name);
  z.methods.push(method);
  z.crcs.push(crc);
  z.csize.push(csize);
  z.usize.push(usize);
  z.poff.push(z.pool.len());
  _push_bytes(&mut z.pool, &data);
}

// Extract entry data given its central-directory metadata. STORED copies;
// DEFLATE routes through the real stdlib inflater capped at the declared
// uncompressed size. Dynamic-Huffman streams surface the stdlib error.
fn _zip_extract(buf: &Vec[UInt8], lfh: Int, method: Int, csize: Int, usize: Int, name: Str) -> Result[Vec[UInt8], Str] {
  if !_match_sig(buf, lfh, 0x04034b50) {
    return _err_bytes("xlsx: bad local file header");
  }
  let nl = _rd_u16(buf, lfh + 26);
  if !nl.is_ok {
    return _err_bytes("xlsx: truncated zip entry header");
  }
  let el = _rd_u16(buf, lfh + 28);
  if !el.is_ok {
    return _err_bytes("xlsx: truncated zip entry header");
  }
  let name_len: Int = nl.value;
  let extra_len: Int = el.value;
  let ds = lfh + 30 + name_len + extra_len;
  if ds + csize > buf.len() {
    return _err_bytes("xlsx: truncated zip entry data");
  }
  if usize > 67108864 {
    return _err_bytes("xlsx: zip entry too large");
  }
  if method == 0 {
    if usize > csize {
      return _err_bytes("xlsx: stored entry size mismatch");
    }
    let data = _slice_copy(buf, ds, usize);
    return _ok_bytes(data);
  }
  if method == 8 {
    let comp = _slice_copy(buf, ds, csize);
    let rc = deflate.deflate_decompress_capped(&comp, usize);
    if !rc.is_ok {
      return _err_bytes("xlsx: entry inflate failed: " + rc.error);
    }
    let payload: Vec[UInt8] = rc.value;
    if payload.len() != usize {
      return _err_bytes("xlsx: entry inflate size mismatch");
    }
    return _ok_bytes(payload);
  }
  return _err_bytes("xlsx: unsupported zip compression method");
}

/// Scan a ZIP archive: locate the EOCD, walk the central directory and
/// extract every entry. STORED and stdlib-readable DEFLATE entries succeed;
/// dynamic-Huffman deflate streams fail with xlsx: entry inflate failed: ...
pub fn xlsx_zip_scan(buf: &Vec[UInt8]) -> Result[XlsxZip, Str] {
  let n = buf.len();
  if n < 22 {
    return _err_zip("xlsx: zip too small");
  }
  var floor = n - 22 - 65535;
  if floor < 0 {
    floor = 0;
  }
  var eocd = -1;
  var i = n - 22;
  var searching = true;
  while searching && i >= floor {
    let b0: Int = (buf[i] as Int) & 0xFF;
    if b0 == 80 {
      if _match_sig(buf, i, 0x06054b50) {
        eocd = i;
        searching = false;
      } else {
        i = i - 1;
      };
    } else {
      i = i - 1;
    };
  }
  if eocd < 0 {
    return _err_zip("xlsx: end of central directory not found");
  }
  let entries_r = _rd_u16(buf, eocd + 10);
  let cd_size_r = _rd_u32(buf, eocd + 12);
  let cd_off_r = _rd_u32(buf, eocd + 16);
  if !entries_r.is_ok {
    return _err_zip("xlsx: truncated zip structure");
  }
  if !cd_size_r.is_ok {
    return _err_zip("xlsx: truncated zip structure");
  }
  if !cd_off_r.is_ok {
    return _err_zip("xlsx: truncated zip structure");
  }
  if entries_r.value == 65535 {
    return _err_zip("xlsx: zip64 not supported");
  }
  if cd_off_r.value == 4294967295 {
    return _err_zip("xlsx: zip64 not supported");
  }
  let entries: Int = entries_r.value;
  let cd_size: Int = cd_size_r.value;
  let cd_off: Int = cd_off_r.value;
  if cd_off + cd_size > n || cd_off < 0 {
    return _err_zip("xlsx: truncated central directory");
  }
  if entries > 4096 {
    return _err_zip("xlsx: too many zip entries");
  }
  var z = XlsxZip{
    names: Vec[Str].new();
    methods: Vec[Int].new();
    crcs: Vec[Int].new();
    csize: Vec[Int].new();
    usize: Vec[Int].new();
    pool: Vec[UInt8].new();
    poff: Vec[Int].new();
  };
  var p = cd_off;
  var k = 0;
  while k < entries {
    if !_match_sig(buf, p, 0x02014b50) {
      return _err_zip("xlsx: bad central directory signature");
    }
    let method_r = _rd_u16(buf, p + 10);
    let crc_r = _rd_u32(buf, p + 16);
    let csize_r = _rd_u32(buf, p + 20);
    let usize_r = _rd_u32(buf, p + 24);
    let name_len_r = _rd_u16(buf, p + 28);
    let extra_len_r = _rd_u16(buf, p + 30);
    let cmt_len_r = _rd_u16(buf, p + 32);
    let lfh_r = _rd_u32(buf, p + 42);
    if !method_r.is_ok || !crc_r.is_ok || !csize_r.is_ok || !usize_r.is_ok || !name_len_r.is_ok || !extra_len_r.is_ok || !cmt_len_r.is_ok || !lfh_r.is_ok {
      return _err_zip("xlsx: truncated central directory entry");
    }
    let name_len: Int = name_len_r.value;
    let extra_len: Int = extra_len_r.value;
    let cmt_len: Int = cmt_len_r.value;
    let total = 46 + name_len + extra_len + cmt_len;
    if p + total > n {
      return _err_zip("xlsx: truncated central directory entry");
    }
    let name_r = _range_to_str(buf, p + 46, name_len);
    if !name_r.is_ok {
      return _err_zip("xlsx: zip entry name contains nul");
    }
    let name: Str = name_r.value;
    let method: Int = method_r.value;
    let crc: Int = crc_r.value;
    let csize: Int = csize_r.value;
    let usize: Int = usize_r.value;
    let data_r = _zip_extract(buf, lfh_r.value, method, csize, usize, name);
    if !data_r.is_ok {
      return _err_zip(data_r.error);
    }
    let data: Vec[UInt8] = data_r.value;
    let actual = hash.crc32_ieee(&data);
    if actual != crc {
      return _err_zip("xlsx: crc mismatch for zip entry '" + name + "'");
    }
    _zip_add(&mut z, name, method, crc, csize, usize, data);
    p = p + total;
    k = k + 1;
  }
  return _ok_zip(z);
}

/// Number of entries in a scanned archive.
pub fn xlsx_zip_count(z: &XlsxZip) -> Int {
  return z.names.len();
}

/// Entry name by index.
pub fn xlsx_zip_name(z: &XlsxZip, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= z.names.len() {
    return _err_str("xlsx: zip entry index out of range");
  }
  let name: Str = z.names[i];
  return _ok_str(name);
}

/// Entry compression method (0 STORED, 8 DEFLATE).
pub fn xlsx_zip_entry_method(z: &XlsxZip, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= z.methods.len() {
    return _err_int("xlsx: zip entry index out of range");
  }
  let v: Int = z.methods[i];
  return _ok_int(v);
}

/// Declared uncompressed size of an entry.
pub fn xlsx_zip_entry_size(z: &XlsxZip, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= z.usize.len() {
    return _err_int("xlsx: zip entry index out of range");
  }
  let v: Int = z.usize[i];
  return _ok_int(v);
}

/// Stored CRC32 value of an entry.
pub fn xlsx_zip_entry_crc(z: &XlsxZip, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= z.crcs.len() {
    return _err_int("xlsx: zip entry index out of range");
  }
  let v: Int = z.crcs[i];
  return _ok_int(v);
}

/// Index of the entry with exactly this name, or -1.
pub fn xlsx_zip_find(z: &XlsxZip, name: Str) -> Int {
  var i = 0;
  while i < z.names.len() {
    let nm: Str = z.names[i];
    if compare.str_compare(nm, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Copy an entry's decompressed payload.
pub fn xlsx_zip_data(z: &XlsxZip, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= z.names.len() {
    return _err_bytes("xlsx: zip entry index out of range");
  }
  if z.poff.len() != z.names.len() || z.usize.len() != z.names.len() {
    return _err_bytes("xlsx: zip archive state corrupted");
  }
  let off: Int = z.poff[i];
  let ln: Int = z.usize[i];
  let data = _slice_copy(&z.pool, off, ln);
  if data.len() != ln {
    return _err_bytes("xlsx: zip archive state corrupted");
  }
  return _ok_bytes(data);
}

// --------------------------------------------------
//  Workbook model
// --------------------------------------------------

/// A new, empty workbook with no sheets, cells or styles.
pub fn xlsx_workbook_new() -> XlsxWorkbook {
  return XlsxWorkbook{
    sheet_names: Vec[Str].new();
    cell_sheet: Vec[Int].new();
    cell_row: Vec[Int].new();
    cell_col: Vec[Int].new();
    cell_kind: Vec[Int].new();
    cell_num: Vec[Int].new();
    cell_bool: Vec[Int].new();
    cell_str: Vec[Int].new();
    cell_style: Vec[Int].new();
    str_pool: Vec[Str].new();
    sty_bold: Vec[Int].new();
    sty_italic: Vec[Int].new();
    sty_size: Vec[Int].new();
    sty_color: Vec[Int].new();
    sty_fmt: Vec[Str].new();
  };
}

/// True when `name` is a legal Excel sheet name: 1..31 bytes, no control
/// bytes and none of [ ] : * ? / backslash.
pub fn xlsx_sheet_name_valid(name: Str) -> Bool {
  let n = name.len();
  if n < 1 || n > 31 {
    return false;
  }
  var i = 0;
  while i < n {
    let c: Int = (string.byte_at(name, i) as Int) & 0xFF;
    if c < 32 {
      return false;
    }
    if c == 91 || c == 93 || c == 58 || c == 42 || c == 63 || c == 47 || c == 92 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn _sheet_index_find(wb: &XlsxWorkbook, name: Str) -> Int {
  var i = 0;
  while i < wb.sheet_names.len() {
    let nm: Str = wb.sheet_names[i];
    if compare.str_compare(nm, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Append a sheet and return its zero-based index. Err on an invalid or
/// duplicate name, or when the sheet limit (1024) is reached.
pub fn xlsx_add_sheet(wb: &mut XlsxWorkbook, name: Str) -> Result[Int, Str] {
  if !xlsx_sheet_name_valid(name) {
    return _err_int("xlsx: invalid sheet name");
  }
  if wb.sheet_names.len() >= _MAX_SHEETS {
    return _err_int("xlsx: sheet limit exceeded");
  }
  if _sheet_index_find(wb, name) >= 0 {
    return _err_int("xlsx: duplicate sheet name");
  }
  let idx = wb.sheet_names.len();
  wb.sheet_names.push(name);
  return _ok_int(idx);
}

/// Number of sheets.
pub fn xlsx_sheet_count(wb: &XlsxWorkbook) -> Int {
  return wb.sheet_names.len();
}

/// Sheet name by index.
pub fn xlsx_sheet_name(wb: &XlsxWorkbook, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= wb.sheet_names.len() {
    return _err_str("xlsx: sheet index out of range");
  }
  let name: Str = wb.sheet_names[i];
  return _ok_str(name);
}

/// Number of cells across all sheets.
pub fn xlsx_cell_count(wb: &XlsxWorkbook) -> Int {
  return wb.cell_sheet.len();
}

/// Number of cells stored for one sheet.
pub fn xlsx_sheet_cell_count(wb: &XlsxWorkbook, sheet: Int) -> Result[Int, Str] {
  if sheet < 0 || sheet >= wb.sheet_names.len() {
    return _err_int("xlsx: sheet index out of range");
  }
  var count = 0;
  var i = 0;
  while i < wb.cell_sheet.len() {
    let s: Int = wb.cell_sheet[i];
    if s == sheet {
      count = count + 1;
    }
    i = i + 1;
  }
  return _ok_int(count);
}

/// Number of unique strings in the workbook string pool.
pub fn xlsx_string_count(wb: &XlsxWorkbook) -> Int {
  return wb.str_pool.len();
}

/// String pool entry by index.
pub fn xlsx_string(wb: &XlsxWorkbook, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= wb.str_pool.len() {
    return _err_str("xlsx: string index out of range");
  }
  let s: Str = wb.str_pool[i];
  return _ok_str(s);
}

/// Index of a string in the workbook pool, or -1.
pub fn xlsx_string_find(wb: &XlsxWorkbook, s: Str) -> Int {
  var i = 0;
  while i < wb.str_pool.len() {
    let e: Str = wb.str_pool[i];
    if compare.str_compare(e, s) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

fn _str_intern(wb: &mut XlsxWorkbook, s: Str) -> Int {
  let found = xlsx_string_find(wb, s);
  if found >= 0 {
    return found;
  }
  if wb.str_pool.len() >= _MAX_STRINGS {
    return -1;
  }
  wb.str_pool.push(s);
  return wb.str_pool.len() - 1;
}

// Index of the LAST cell at (sheet, row, col), or -1.
fn _cell_lookup(wb: &XlsxWorkbook, sheet: Int, row: Int, col: Int) -> Int {
  var found = -1;
  var i = 0;
  while i < wb.cell_sheet.len() {
    let s: Int = wb.cell_sheet[i];
    if s == sheet {
      let r: Int = wb.cell_row[i];
      if r == row {
        let c: Int = wb.cell_col[i];
        if c == col {
          found = i;
        };
      };
    };
    i = i + 1;
  }
  return found;
}

// Push one cell keeping every parallel vector in lockstep. False at the cap.
fn _wb_push_cell(wb: &mut XlsxWorkbook, sheet: Int, row: Int, col: Int, kind: Int, num: Int, bval: Int, sidx: Int, style: Int) -> Bool {
  if wb.cell_sheet.len() >= _MAX_CELLS {
    return false;
  }
  wb.cell_sheet.push(sheet);
  wb.cell_row.push(row);
  wb.cell_col.push(col);
  wb.cell_kind.push(kind);
  wb.cell_num.push(num);
  wb.cell_bool.push(bval);
  wb.cell_str.push(sidx);
  wb.cell_style.push(style);
  return true;
}

fn _coord_valid(wb: &XlsxWorkbook, sheet: Int, row: Int, col: Int) -> Bool {
  if sheet < 0 || sheet >= wb.sheet_names.len() {
    return false;
  }
  if row < 0 || col < 0 {
    return false;
  }
  if row > 1048575 || col > 16383 {
    return false;
  }
  return true;
}

/// Set a numeric cell (fixed-point micro-units).
pub fn xlsx_set_number(wb: &mut XlsxWorkbook, sheet: Int, row: Int, col: Int, scaled: Int) -> Result[Bool, Str] {
  if !_coord_valid(wb, sheet, row, col) {
    return _err_bool("xlsx: cell coordinate out of range");
  }
  if !_wb_push_cell(wb, sheet, row, col, _K_NUM, scaled, 0, -1, -1) {
    return _err_bool("xlsx: cell limit exceeded");
  }
  return _ok_bool(true);
}

/// Set a string cell; the value is interned in the workbook string pool.
pub fn xlsx_set_string(wb: &mut XlsxWorkbook, sheet: Int, row: Int, col: Int, value: Str) -> Result[Bool, Str] {
  if !_coord_valid(wb, sheet, row, col) {
    return _err_bool("xlsx: cell coordinate out of range");
  }
  let idx = _str_intern(wb, value);
  if idx < 0 {
    return _err_bool("xlsx: string pool limit exceeded");
  }
  if !_wb_push_cell(wb, sheet, row, col, _K_STR, 0, 0, idx, -1) {
    return _err_bool("xlsx: cell limit exceeded");
  }
  return _ok_bool(true);
}

/// Set a boolean cell.
pub fn xlsx_set_bool(wb: &mut XlsxWorkbook, sheet: Int, row: Int, col: Int, value: Bool) -> Result[Bool, Str] {
  if !_coord_valid(wb, sheet, row, col) {
    return _err_bool("xlsx: cell coordinate out of range");
  }
  var bv = 0;
  if value {
    bv = 1;
  }
  if !_wb_push_cell(wb, sheet, row, col, _K_BOOL, 0, bv, -1, -1) {
    return _err_bool("xlsx: cell limit exceeded");
  }
  return _ok_bool(true);
}

/// Set the style index of an existing cell (-1 clears it). Err when the cell
/// does not exist or the style index is out of range.
pub fn xlsx_set_style(wb: &mut XlsxWorkbook, sheet: Int, row: Int, col: Int, style: Int) -> Result[Bool, Str] {
  if style < -1 || style >= wb.sty_bold.len() {
    return _err_bool("xlsx: style index out of range");
  }
  let idx = _cell_lookup(wb, sheet, row, col);
  if idx < 0 {
    return _err_bool("xlsx: cell not found");
  }
  wb.cell_style[idx] = style;
  return _ok_bool(true);
}

/// Add a style record and return its zero-based index (mapped to cellXfs
/// entry index+1 on the wire, because xf 0 is the default style).
/// size_pt <= 0 defaults to 11; color_rgb 0 defaults to opaque black;
/// numfmt "" means General.
pub fn xlsx_add_style(wb: &mut XlsxWorkbook, bold: Bool, italic: Bool, size_pt: Int, color_rgb: Int, numfmt: Str) -> Int {
  var b = 0;
  if bold {
    b = 1;
  }
  var it = 0;
  if italic {
    it = 1;
  }
  var sz = size_pt;
  if sz <= 0 {
    sz = 11;
  }
  var co = color_rgb;
  if co == 0 {
    co = 4278190080;
  }
  wb.sty_bold.push(b);
  wb.sty_italic.push(it);
  wb.sty_size.push(sz);
  wb.sty_color.push(co);
  wb.sty_fmt.push(numfmt);
  return wb.sty_bold.len() - 1;
}

/// Number of workbook styles.
pub fn xlsx_style_count(wb: &XlsxWorkbook) -> Int {
  return wb.sty_bold.len();
}

fn _style_index_ok(wb: &XlsxWorkbook, i: Int) -> Bool {
  return i >= 0 && i < wb.sty_bold.len();
}

/// Style bold flag by index.
pub fn xlsx_style_bold(wb: &XlsxWorkbook, i: Int) -> Result[Bool, Str] {
  if !_style_index_ok(wb, i) {
    return _err_bool("xlsx: style index out of range");
  }
  let v: Int = wb.sty_bold[i];
  return _ok_bool(v == 1);
}

/// Style italic flag by index.
pub fn xlsx_style_italic(wb: &XlsxWorkbook, i: Int) -> Result[Bool, Str] {
  if !_style_index_ok(wb, i) {
    return _err_bool("xlsx: style index out of range");
  }
  let v: Int = wb.sty_italic[i];
  return _ok_bool(v == 1);
}

/// Style font size in points by index.
pub fn xlsx_style_size(wb: &XlsxWorkbook, i: Int) -> Result[Int, Str] {
  if !_style_index_ok(wb, i) {
    return _err_int("xlsx: style index out of range");
  }
  let v: Int = wb.sty_size[i];
  return _ok_int(v);
}

/// Style font ARGB color by index.
pub fn xlsx_style_color(wb: &XlsxWorkbook, i: Int) -> Result[Int, Str] {
  if !_style_index_ok(wb, i) {
    return _err_int("xlsx: style index out of range");
  }
  let v: Int = wb.sty_color[i];
  return _ok_int(v);
}

/// Style number-format code by index ("" = General).
pub fn xlsx_style_numfmt(wb: &XlsxWorkbook, i: Int) -> Result[Str, Str] {
  if !_style_index_ok(wb, i) {
    return _err_str("xlsx: style index out of range");
  }
  let v: Str = wb.sty_fmt[i];
  return _ok_str(v);
}

/// Cell kind: 0 number, 1 string, 2 bool. Err when the cell does not exist.
pub fn xlsx_cell_kind(wb: &XlsxWorkbook, sheet: Int, row: Int, col: Int) -> Result[Int, Str] {
  let idx = _cell_lookup(wb, sheet, row, col);
  if idx < 0 {
    return _err_int("xlsx: cell not found");
  }
  let v: Int = wb.cell_kind[idx];
  return _ok_int(v);
}

fn _cell_idx_required(wb: &XlsxWorkbook, sheet: Int, row: Int, col: Int, want: Int, what: Str) -> Result[Int, Str] {
  let idx = _cell_lookup(wb, sheet, row, col);
  if idx < 0 {
    return _err_int("xlsx: cell not found");
  }
  let k: Int = wb.cell_kind[idx];
  if k != want {
    return _err_int("xlsx: cell is not a " + what);
  }
  return _ok_int(idx);
}

/// Numeric value of a numeric cell (fixed-point micro-units).
pub fn xlsx_cell_number_scaled(wb: &XlsxWorkbook, sheet: Int, row: Int, col: Int) -> Result[Int, Str] {
  let ir = _cell_idx_required(wb, sheet, row, col, _K_NUM, "number");
  if !ir.is_ok {
    return _err_int(ir.error);
  }
  let idx: Int = ir.value;
  let v: Int = wb.cell_num[idx];
  return _ok_int(v);
}

/// String value of a string cell.
pub fn xlsx_cell_string(wb: &XlsxWorkbook, sheet: Int, row: Int, col: Int) -> Result[Str, Str] {
  let ir = _cell_idx_required(wb, sheet, row, col, _K_STR, "string");
  if !ir.is_ok {
    return _err_str(ir.error);
  }
  let idx: Int = ir.value;
  let sidx: Int = wb.cell_str[idx];
  if sidx < 0 || sidx >= wb.str_pool.len() {
    return _err_str("xlsx: shared string index out of range");
  }
  let s: Str = wb.str_pool[sidx];
  return _ok_str(s);
}

/// Boolean value of a bool cell.
pub fn xlsx_cell_bool(wb: &XlsxWorkbook, sheet: Int, row: Int, col: Int) -> Result[Bool, Str] {
  let ir = _cell_idx_required(wb, sheet, row, col, _K_BOOL, "boolean");
  if !ir.is_ok {
    return _err_bool(ir.error);
  }
  let idx: Int = ir.value;
  let v: Int = wb.cell_bool[idx];
  return _ok_bool(v == 1);
}

/// Style index of a cell (-1 = no style). Err when the cell does not exist.
pub fn xlsx_cell_style(wb: &XlsxWorkbook, sheet: Int, row: Int, col: Int) -> Result[Int, Str] {
  let idx = _cell_lookup(wb, sheet, row, col);
  if idx < 0 {
    return _err_int("xlsx: cell not found");
  }
  let v: Int = wb.cell_style[idx];
  return _ok_int(v);
}

// --------------------------------------------------
//  Number-format builtins
// --------------------------------------------------

fn _builtin_fmt_id(code: Str) -> Int {
  if compare.str_compare(code, "0.00") == 0 {
    return 2;
  }
  if compare.str_compare(code, "#,##0") == 0 {
    return 3;
  }
  if compare.str_compare(code, "#,##0.00") == 0 {
    return 4;
  }
  if compare.str_compare(code, "0%") == 0 {
    return 9;
  }
  if compare.str_compare(code, "0.00%") == 0 {
    return 10;
  }
  if compare.str_compare(code, "mm-dd-yy") == 0 {
    return 14;
  }
  if compare.str_compare(code, "@") == 0 {
    return 49;
  }
  return -1;
}

fn _builtin_fmt_code(id: Int) -> Str {
  if id == 2 {
    return "0.00";
  }
  if id == 3 {
    return "#,##0";
  }
  if id == 4 {
    return "#,##0.00";
  }
  if id == 9 {
    return "0%";
  }
  if id == 10 {
    return "0.00%";
  }
  if id == 14 {
    return "mm-dd-yy";
  }
  if id == 49 {
    return "@";
  }
  return "";
}

// --------------------------------------------------
//  Part writers
// --------------------------------------------------

fn _part_content_types(wb: &XlsxWorkbook) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_str(&mut out, "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">");
  _push_str(&mut out, "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>");
  _push_str(&mut out, "<Default Extension=\"xml\" ContentType=\"application/xml\"/>");
  _push_str(&mut out, "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>");
  var i = 0;
  while i < wb.sheet_names.len() {
    _push_str(&mut out, "<Override PartName=\"/xl/worksheets/sheet");
    builder.sb_push_int(&mut out, i + 1);
    _push_str(&mut out, ".xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>");
    i = i + 1;
  }
  _push_str(&mut out, "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>");
  _push_str(&mut out, "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/>");
  _push_str(&mut out, "</Types>");
  return out;
}

fn _part_root_rels() -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_str(&mut out, "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">");
  _push_str(&mut out, "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>");
  _push_str(&mut out, "</Relationships>");
  return out;
}

fn _part_workbook(wb: &XlsxWorkbook) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_str(&mut out, "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>");
  var i = 0;
  while i < wb.sheet_names.len() {
    let name: Str = wb.sheet_names[i];
    _push_str(&mut out, "<sheet name=\"");
    _xml_escape_into(&mut out, name);
    _push_str(&mut out, "\" sheetId=\"");
    builder.sb_push_int(&mut out, i + 1);
    _push_str(&mut out, "\" r:id=\"rId");
    builder.sb_push_int(&mut out, i + 1);
    _push_str(&mut out, "\"/>");
    i = i + 1;
  }
  _push_str(&mut out, "</sheets></workbook>");
  return out;
}

fn _part_workbook_rels(wb: &XlsxWorkbook) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_str(&mut out, "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">");
  var i = 0;
  while i < wb.sheet_names.len() {
    _push_str(&mut out, "<Relationship Id=\"rId");
    builder.sb_push_int(&mut out, i + 1);
    _push_str(&mut out, "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet");
    builder.sb_push_int(&mut out, i + 1);
    _push_str(&mut out, ".xml\"/>");
    i = i + 1;
  }
  let n = wb.sheet_names.len();
  _push_str(&mut out, "<Relationship Id=\"rId");
  builder.sb_push_int(&mut out, n + 1);
  _push_str(&mut out, "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>");
  _push_str(&mut out, "<Relationship Id=\"rId");
  builder.sb_push_int(&mut out, n + 2);
  _push_str(&mut out, "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>");
  _push_str(&mut out, "</Relationships>");
  return out;
}

fn _col_name_into(out: &mut Vec[UInt8], col: Int) {
  var letters = Vec[UInt8].new();
  var c = col;
  var guard = 0;
  while guard < 8 {
    letters.push((65 + (c % 26)) as UInt8);
    c = c / 26 - 1;
    if c < 0 {
      guard = 8;
    } else {
      guard = guard + 1;
    };
  }
  var i = letters.len() - 1;
  while i >= 0 {
    let b: UInt8 = letters[i];
    out.push(b);
    i = i - 1;
  }
}

fn _cell_ref_into(out: &mut Vec[UInt8], row: Int, col: Int) {
  _col_name_into(out, col);
  builder.sb_push_int(out, row + 1);
}

fn _cell_open(out: &mut Vec[UInt8], row: Int, col: Int, tval: Str, xf: Int) {
  _push_str(out, "<c r=\"");
  _cell_ref_into(out, row, col);
  _push_str(out, "\"");
  if tval.len() > 0 {
    _push_str(out, " t=\"");
    _push_str(out, tval);
    _push_str(out, "\"");
  }
  if xf >= 0 {
    _push_str(out, " s=\"");
    builder.sb_push_int(out, xf);
    _push_str(out, "\"");
  }
  _push_str(out, ">");
}

// Indices of one sheet's cells sorted by (row, col); insertion sort with
// keys looked up in the model (no parallel key vectors to drift).
fn _sheet_sel(wb: &XlsxWorkbook, sheet: Int) -> Vec[Int] {
  var sel = Vec[Int].new();
  var i = 0;
  while i < wb.cell_sheet.len() {
    let s: Int = wb.cell_sheet[i];
    if s == sheet {
      sel.push(i);
    }
    i = i + 1;
  }
  var a = 1;
  while a < sel.len() {
    let key: Int = sel[a];
    let kr: Int = wb.cell_row[key];
    let kc: Int = wb.cell_col[key];
    var b = a - 1;
    var done = false;
    while b >= 0 && !done {
      let bi: Int = sel[b];
      let br: Int = wb.cell_row[bi];
      let bc: Int = wb.cell_col[bi];
      if br > kr || (br == kr && bc > kc) {
        sel[b + 1] = sel[b];
        b = b - 1;
      } else {
        done = true;
      };
    }
    sel[b + 1] = key;
    a = a + 1;
  }
  return sel;
}

fn _part_sheet(wb: &XlsxWorkbook, sheet: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_str(&mut out, "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>");
  let sel = _sheet_sel(wb, sheet);
  var i = 0;
  var cur_row = -1;
  while i < sel.len() {
    let ci: Int = sel[i];
    let r: Int = wb.cell_row[ci];
    let c: Int = wb.cell_col[ci];
    let kind: Int = wb.cell_kind[ci];
    let sidx: Int = wb.cell_str[ci];
    let numv: Int = wb.cell_num[ci];
    let bv: Int = wb.cell_bool[ci];
    let st: Int = wb.cell_style[ci];
    var xf = -1;
    if st >= 0 {
      xf = st + 1;
    }
    if r != cur_row {
      if cur_row >= 0 {
        _push_str(&mut out, "</row>");
      }
      cur_row = r;
      _push_str(&mut out, "<row r=\"");
      builder.sb_push_int(&mut out, r + 1);
      _push_str(&mut out, "\">");
    }
    if kind == _K_STR {
      _cell_open(&mut out, r, c, "s", xf);
      _push_str(&mut out, "<v>");
      builder.sb_push_int(&mut out, sidx);
      _push_str(&mut out, "</v></c>");
    } else {
      if kind == _K_BOOL {
        _cell_open(&mut out, r, c, "b", xf);
        _push_str(&mut out, "<v>");
        builder.sb_push_int(&mut out, bv);
        _push_str(&mut out, "</v></c>");
      } else {
        _cell_open(&mut out, r, c, "", xf);
        _push_str(&mut out, "<v>");
        _scaled_into(&mut out, numv);
        _push_str(&mut out, "</v></c>");
      };
    };
    i = i + 1;
  }
  if cur_row >= 0 {
    _push_str(&mut out, "</row>");
  }
  _push_str(&mut out, "</sheetData></worksheet>");
  return out;
}

fn _part_shared_strings(wb: &XlsxWorkbook) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var count = 0;
  var i = 0;
  while i < wb.cell_kind.len() {
    let k: Int = wb.cell_kind[i];
    if k == _K_STR {
      count = count + 1;
    }
    i = i + 1;
  }
  _push_str(&mut out, "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"");
  builder.sb_push_int(&mut out, count);
  _push_str(&mut out, "\" uniqueCount=\"");
  builder.sb_push_int(&mut out, wb.str_pool.len());
  _push_str(&mut out, "\">");
  i = 0;
  while i < wb.str_pool.len() {
    let s: Str = wb.str_pool[i];
    _push_str(&mut out, "<si><t xml:space=\"preserve\">");
    _xml_escape_into(&mut out, s);
    _push_str(&mut out, "</t></si>");
    i = i + 1;
  }
  _push_str(&mut out, "</sst>");
  return out;
}

fn _part_styles(wb: &XlsxWorkbook) -> Vec[UInt8] {
  var u_bold = Vec[Int].new();
  var u_ital = Vec[Int].new();
  var u_size = Vec[Int].new();
  var u_colr = Vec[Int].new();
  u_bold.push(0);
  u_ital.push(0);
  u_size.push(11);
  u_colr.push(4278190080);
  var style_font = Vec[Int].new();
  var i = 0;
  while i < wb.sty_bold.len() {
    let b: Int = wb.sty_bold[i];
    let it: Int = wb.sty_italic[i];
    let sz: Int = wb.sty_size[i];
    let co: Int = wb.sty_color[i];
    var found = -1;
    var f = 0;
    var scan = true;
    while scan && f < u_bold.len() {
      let fb: Int = u_bold[f];
      let fi: Int = u_ital[f];
      let fs: Int = u_size[f];
      let fc: Int = u_colr[f];
      if fb == b && fi == it && fs == sz && fc == co {
        found = f;
        scan = false;
      } else {
        f = f + 1;
      };
    }
    if found < 0 {
      u_bold.push(b);
      u_ital.push(it);
      u_size.push(sz);
      u_colr.push(co);
      found = u_bold.len() - 1;
    };
    style_font.push(found);
    i = i + 1;
  }
  var nf_ids = Vec[Int].new();
  var nf_codes = Vec[Str].new();
  var style_nf = Vec[Int].new();
  i = 0;
  while i < wb.sty_fmt.len() {
    let code: Str = wb.sty_fmt[i];
    var id = 0;
    if code.len() > 0 {
      id = _builtin_fmt_id(code);
      if id < 0 {
        var k = 0;
        var hit = -1;
        var scanning = true;
        while scanning && k < nf_codes.len() {
          let kc: Str = nf_codes[k];
          if compare.str_compare(kc, code) == 0 {
            hit = k;
            scanning = false;
          } else {
            k = k + 1;
          };
        }
        if hit < 0 {
          nf_ids.push(164 + nf_codes.len());
          nf_codes.push(code);
          hit = nf_codes.len() - 1;
        };
        let nid: Int = nf_ids[hit];
        id = nid;
      };
    };
    style_nf.push(id);
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  _push_str(&mut out, "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">");
  if nf_codes.len() > 0 {
    _push_str(&mut out, "<numFmts count=\"");
    builder.sb_push_int(&mut out, nf_codes.len());
    _push_str(&mut out, "\">");
    var q = 0;
    while q < nf_codes.len() {
      let qc: Str = nf_codes[q];
      let qid: Int = nf_ids[q];
      _push_str(&mut out, "<numFmt numFmtId=\"");
      builder.sb_push_int(&mut out, qid);
      _push_str(&mut out, "\" formatCode=\"");
      _xml_escape_into(&mut out, qc);
      _push_str(&mut out, "\"/>");
      q = q + 1;
    }
    _push_str(&mut out, "</numFmts>");
  }
  _push_str(&mut out, "<fonts count=\"");
  builder.sb_push_int(&mut out, u_bold.len());
  _push_str(&mut out, "\">");
  var fi = 0;
  while fi < u_bold.len() {
    let fb2: Int = u_bold[fi];
    let fi2: Int = u_ital[fi];
    let fs2: Int = u_size[fi];
    let fc2: Int = u_colr[fi];
    _push_str(&mut out, "<font>");
    if fb2 == 1 {
      _push_str(&mut out, "<b/>");
    }
    if fi2 == 1 {
      _push_str(&mut out, "<i/>");
    }
    _push_str(&mut out, "<sz val=\"");
    builder.sb_push_int(&mut out, fs2);
    _push_str(&mut out, "\"/><color rgb=\"");
    _put_argb(&mut out, fc2);
    _push_str(&mut out, "\"/></font>");
    fi = fi + 1;
  }
  _push_str(&mut out, "</fonts>");
  _push_str(&mut out, "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>");
  _push_str(&mut out, "<borders count=\"1\"><border/></borders>");
  _push_str(&mut out, "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>");
  _push_str(&mut out, "<cellXfs count=\"");
  builder.sb_push_int(&mut out, wb.sty_bold.len() + 1);
  _push_str(&mut out, "\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>");
  i = 0;
  while i < wb.sty_bold.len() {
    let fnt: Int = style_font[i];
    let nf: Int = style_nf[i];
    _push_str(&mut out, "<xf numFmtId=\"");
    builder.sb_push_int(&mut out, nf);
    _push_str(&mut out, "\" fontId=\"");
    builder.sb_push_int(&mut out, fnt);
    _push_str(&mut out, "\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\" applyFont=\"1\"/>");
    i = i + 1;
  }
  _push_str(&mut out, "</cellXfs><cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>");
  return out;
}

// --------------------------------------------------
//  Workbook writer
// --------------------------------------------------

fn _pool_add(pool: &mut Vec[UInt8], offs: &mut Vec[Int], lens: &mut Vec[Int], part: &Vec[UInt8]) {
  offs.push(pool.len());
  lens.push(part.len());
  _push_bytes(pool, part);
}

/// Serialize a workbook to a complete XLSX (ZIP) byte stream. `level` 0
/// writes every entry STORED; 1..9 writes every entry with the stdlib
/// fixed-Huffman DEFLATE producer. The output is deterministic.
pub fn xlsx_write(wb: &XlsxWorkbook, level: Int) -> Result[Vec[UInt8], Str] {
  if level < 0 || level > 9 {
    return _err_bytes("xlsx: unsupported compression level");
  }
  var meth = 8;
  if level == 0 {
    meth = 0;
  }
  var names = Vec[Str].new();
  var methods = Vec[Int].new();
  var pool = Vec[UInt8].new();
  var offs = Vec[Int].new();
  var lens = Vec[Int].new();
  let p0 = _part_content_types(wb);
  names.push("[Content_Types].xml");
  methods.push(meth);
  _pool_add(&mut pool, &mut offs, &mut lens, &p0);
  let p1 = _part_root_rels();
  names.push("_rels/.rels");
  methods.push(meth);
  _pool_add(&mut pool, &mut offs, &mut lens, &p1);
  let p2 = _part_workbook(wb);
  names.push("xl/workbook.xml");
  methods.push(meth);
  _pool_add(&mut pool, &mut offs, &mut lens, &p2);
  let p3 = _part_workbook_rels(wb);
  names.push("xl/_rels/workbook.xml.rels");
  methods.push(meth);
  _pool_add(&mut pool, &mut offs, &mut lens, &p3);
  var i = 0;
  while i < wb.sheet_names.len() {
    let pn = "xl/worksheets/sheet" + convert.int_to_string(i + 1) + ".xml";
    names.push(pn);
    methods.push(meth);
    let ps = _part_sheet(wb, i);
    _pool_add(&mut pool, &mut offs, &mut lens, &ps);
    i = i + 1;
  }
  let p4 = _part_styles(wb);
  names.push("xl/styles.xml");
  methods.push(meth);
  _pool_add(&mut pool, &mut offs, &mut lens, &p4);
  let p5 = _part_shared_strings(wb);
  names.push("xl/sharedStrings.xml");
  methods.push(meth);
  _pool_add(&mut pool, &mut offs, &mut lens, &p5);
  return xlsx_zip_write(&names, &methods, &pool, &offs, &lens);
}

// --------------------------------------------------
//  Workbook reader
// --------------------------------------------------

fn _parse_workbook_part(text: Str, wb: &mut XlsxWorkbook, rids: &mut Vec[Str]) -> Result[Bool, Str] {
  let n = text.len();
  var i = 0;
  while i < n {
    let lt = _find_byte(text, i, _B_LT);
    if lt < 0 {
      i = n;
    } else {
      let e = _tag_end(text, lt);
      if e < 0 {
        return _err_bool("xlsx: xml unterminated tag");
      }
      if _tag_kind(text, lt, e) == 0 {
        if _tag_name_is(text, lt, e, "sheet") {
          let nr = _attr(text, lt, e, "name");
          if !nr.is_ok {
            return _err_bool("xlsx: sheet missing name attribute");
          }
          let name: Str = nr.value;
          if wb.sheet_names.len() >= _MAX_SHEETS {
            return _err_bool("xlsx: sheet limit exceeded");
          }
          wb.sheet_names.push(name);
          let rr = _attr(text, lt, e, "r:id");
          if rr.is_ok {
            let rid: Str = rr.value;
            rids.push(rid);
          } else {
            rids.push("");
          };
        };
      };
      i = e + 1;
    };
  }
  return _ok_bool(true);
}

fn _parse_shared_part(text: Str, wb: &mut XlsxWorkbook) -> Result[Bool, Str] {
  let n = text.len();
  var i = 0;
  var in_si = false;
  var cur = Vec[UInt8].new();
  while i < n {
    let lt = _find_byte(text, i, _B_LT);
    if lt < 0 {
      i = n;
    } else {
      let e = _tag_end(text, lt);
      if e < 0 {
        return _err_bool("xlsx: xml unterminated tag");
      }
      let kind = _tag_kind(text, lt, e);
      if kind == 0 {
        if _tag_name_is(text, lt, e, "si") {
          if _tag_self_closing(text, e) {
            let empty = "";
            let idx = _str_intern(wb, empty);
            if idx < 0 {
              return _err_bool("xlsx: string pool limit exceeded");
            }
          } else {
            in_si = true;
            cur = Vec[UInt8].new();
          };
        } else {
          if in_si && _tag_name_is(text, lt, e, "t") {
            if !_tag_self_closing(text, e) {
              let ts = e + 1;
              let te = _text_until_lt(text, ts);
              let ur = _xml_unescape(text, ts, te);
              if !ur.is_ok {
                return _err_bool(ur.error);
              }
              let piece: Str = ur.value;
              _push_str(&mut cur, piece);
            };
          };
        };
      } else {
        if kind == 1 && _tag_name_is(text, lt, e, "si") {
          let sval = builder.sb_to_str(&cur);
          let idx2 = _str_intern(wb, sval);
          if idx2 < 0 {
            return _err_bool("xlsx: string pool limit exceeded");
          }
          in_si = false;
        };
      };
      i = e + 1;
    };
  }
  if in_si {
    return _err_bool("xlsx: unclosed si element");
  }
  return _ok_bool(true);
}

fn _parse_styles_part(text: Str, wb: &mut XlsxWorkbook) -> Result[Bool, Str] {
  let n = text.len();
  var i = 0;
  var section = 0;
  var in_font = false;
  var xf_index = 0;
  var f_bold = Vec[Int].new();
  var f_ital = Vec[Int].new();
  var f_size = Vec[Int].new();
  var f_colr = Vec[Int].new();
  var nf_ids = Vec[Int].new();
  var nf_codes = Vec[Str].new();
  while i < n {
    let lt = _find_byte(text, i, _B_LT);
    if lt < 0 {
      i = n;
    } else {
      let e = _tag_end(text, lt);
      if e < 0 {
        return _err_bool("xlsx: xml unterminated tag");
      }
      let kind = _tag_kind(text, lt, e);
      if kind == 0 {
        if _tag_name_is(text, lt, e, "fonts") {
          section = 1;
        } else {
          if _tag_name_is(text, lt, e, "numFmts") {
            section = 2;
          } else {
            if _tag_name_is(text, lt, e, "cellXfs") {
              section = 3;
              xf_index = 0;
            } else {
              if section == 1 && _tag_name_is(text, lt, e, "font") {
                f_bold.push(0);
                f_ital.push(0);
                f_size.push(11);
                f_colr.push(4278190080);
                if !_tag_self_closing(text, e) {
                  in_font = true;
                };
              } else {
                if section == 1 && in_font && _tag_name_is(text, lt, e, "b") {
                  let lf = f_bold.len() - 1;
                  f_bold[lf] = 1;
                } else {
                  if section == 1 && in_font && _tag_name_is(text, lt, e, "i") {
                    let lf2 = f_ital.len() - 1;
                    f_ital[lf2] = 1;
                  } else {
                    if section == 1 && in_font && _tag_name_is(text, lt, e, "sz") {
                      let vsz = _attr_int(text, lt, e, "val");
                      let lf3 = f_size.len() - 1;
                      if vsz > 0 {
                        f_size[lf3] = vsz;
                      };
                    } else {
                      if section == 1 && in_font && _tag_name_is(text, lt, e, "color") {
                        let cr = _attr(text, lt, e, "rgb");
                        let lf4 = f_colr.len() - 1;
                        if cr.is_ok {
                          let cvs: Str = cr.value;
                          let cv = _hex_parse(cvs);
                          if cv >= 0 {
                            f_colr[lf4] = cv;
                          };
                        };
                      } else {
                        if section == 2 && _tag_name_is(text, lt, e, "numFmt") {
                          let fid = _attr_int(text, lt, e, "numFmtId");
                          let cr2 = _attr(text, lt, e, "formatCode");
                          if fid >= 0 && cr2.is_ok {
                            let code: Str = cr2.value;
                            nf_ids.push(fid);
                            nf_codes.push(code);
                          };
                        } else {
                          if section == 3 && _tag_name_is(text, lt, e, "xf") {
                            if xf_index > 0 {
                              let nfid = _attr_int(text, lt, e, "numFmtId");
                              let fntid = _attr_int(text, lt, e, "fontId");
                              var st_b = 0;
                              var st_i = 0;
                              var st_s = 11;
                              var st_c = 4278190080;
                              if fntid >= 0 && fntid < f_bold.len() {
                                let qb: Int = f_bold[fntid];
                                let qi: Int = f_ital[fntid];
                                let qs: Int = f_size[fntid];
                                let qc: Int = f_colr[fntid];
                                st_b = qb;
                                st_i = qi;
                                st_s = qs;
                                st_c = qc;
                              };
                              var fmt = "";
                              if nfid > 0 {
                                var k = 0;
                                var hit = -1;
                                while k < nf_ids.len() {
                                  let kid: Int = nf_ids[k];
                                  if kid == nfid {
                                    hit = k;
                                    k = nf_ids.len();
                                  } else {
                                    k = k + 1;
                                  };
                                }
                                if hit >= 0 {
                                  let hc: Str = nf_codes[hit];
                                  fmt = hc;
                                } else {
                                  fmt = _builtin_fmt_code(nfid);
                                };
                              };
                              if wb.sty_bold.len() >= _MAX_STYLES {
                                return _err_bool("xlsx: style limit exceeded");
                              }
                              wb.sty_bold.push(st_b);
                              wb.sty_italic.push(st_i);
                              wb.sty_size.push(st_s);
                              wb.sty_color.push(st_c);
                              wb.sty_fmt.push(fmt);
                              xf_index = xf_index + 1;
                            } else {
                              xf_index = xf_index + 1;
                            };
                          };
                        };
                      };
                    };
                  };
                };
              };
            };
          };
        };
      } else {
        if kind == 1 {
          if _tag_name_is(text, lt, e, "fonts") {
            section = 0;
          } else {
            if _tag_name_is(text, lt, e, "numFmts") {
              section = 0;
            } else {
              if _tag_name_is(text, lt, e, "cellXfs") {
                section = 0;
              } else {
                if _tag_name_is(text, lt, e, "font") {
                  in_font = false;
                };
              };
            };
          };
        };
      };
      i = e + 1;
    };
  }
  return _ok_bool(true);
}

// Parse A1-style references ($ absolute markers ignored). Returns
// (row, col), both zero-based, or (-1, -1) when malformed.
fn _ref_parse(r: Str) -> (Int, Int) {
  let n = r.len();
  var i = 0;
  var col = 0;
  var letters = 0;
  while i < n {
    let c: Int = (string.byte_at(r, i) as Int) & 0xFF;
    if c == 36 {
      i = i + 1;
    } else {
      if c >= 65 && c <= 90 {
        col = col * 26 + (c - 64);
        letters = letters + 1;
        i = i + 1;
      } else {
        if c >= 97 && c <= 122 {
          col = col * 26 + (c - 96);
          letters = letters + 1;
          i = i + 1;
        } else {
          break;
        };
      };
    };
  }
  if letters == 0 || letters > 3 {
    return (-1, -1);
  }
  col = col - 1;
  var row = 0;
  var digits = 0;
  while i < n {
    let c2: Int = (string.byte_at(r, i) as Int) & 0xFF;
    if c2 == 36 {
      i = i + 1;
    } else {
      if c2 >= 48 && c2 <= 57 {
        row = row * 10 + (c2 - 48);
        digits = digits + 1;
        if digits > 7 {
          return (-1, -1);
        }
        i = i + 1;
      } else {
        return (-1, -1);
      };
    };
  }
  if digits == 0 {
    return (-1, -1);
  }
  if row < 1 {
    return (-1, -1);
  }
  return (row - 1, col);
}

fn _parse_sheet_part(text: Str, wb: &mut XlsxWorkbook, sheet: Int) -> Result[Bool, Str] {
  let n = text.len();
  var i = 0;
  var active = false;
  var cur_row = 0;
  var cur_col = 0;
  var cur_kind = _K_NUM;
  var cur_form = 0;
  var cur_num = 0;
  var cur_bval = 0;
  var cur_sidx = -1;
  var cur_style = -1;
  var saw_v = false;
  var has_text = false;
  var cur_text = Vec[UInt8].new();
  while i < n {
    let lt = _find_byte(text, i, _B_LT);
    if lt < 0 {
      i = n;
    } else {
      let e = _tag_end(text, lt);
      if e < 0 {
        return _err_bool("xlsx: xml unterminated tag");
      }
      let kind = _tag_kind(text, lt, e);
      if kind == 0 {
        if _tag_name_is(text, lt, e, "c") {
          let ratt = _attr(text, lt, e, "r");
          if !ratt.is_ok {
            return _err_bool("xlsx: cell missing r attribute");
          }
          let r: Str = ratt.value;
          let tpos = _ref_parse(r);
          let row: Int = tpos.0;
          let col: Int = tpos.1;
          if row < 0 || col < 0 {
            return _err_bool("xlsx: invalid cell reference");
          }
          cur_row = row;
          cur_col = col;
          cur_kind = _K_NUM;
          cur_form = 0;
          cur_num = 0;
          cur_bval = 0;
          cur_sidx = -1;
          cur_style = -1;
          saw_v = false;
          has_text = false;
          cur_text = Vec[UInt8].new();
          let tatt = _attr(text, lt, e, "t");
          if tatt.is_ok {
            let ts: Str = tatt.value;
            if compare.str_compare(ts, "s") == 0 {
              cur_kind = _K_STR;
              cur_form = 1;
            } else {
              if compare.str_compare(ts, "b") == 0 {
                cur_kind = _K_BOOL;
              } else {
                if compare.str_compare(ts, "inlineStr") == 0 {
                  cur_kind = _K_STR;
                  cur_form = 3;
                } else {
                  if compare.str_compare(ts, "str") == 0 {
                    cur_kind = _K_STR;
                    cur_form = 2;
                  } else {
                    if compare.str_compare(ts, "e") == 0 {
                      cur_kind = _K_STR;
                      cur_form = 2;
                    } else {
                      if compare.str_compare(ts, "n") != 0 {
                        return _err_bool("xlsx: unsupported cell type");
                      };
                    };
                  };
                };
              };
            };
          };
          let satt = _attr_int(text, lt, e, "s");
          if satt > 0 {
            cur_style = satt - 1;
          };
          if _tag_self_closing(text, e) {
            active = false;
          } else {
            active = true;
          };
        } else {
          if active && _tag_name_is(text, lt, e, "v") {
            if !_tag_self_closing(text, e) {
              let vs = e + 1;
              let ve = _text_until_lt(text, vs);
              if cur_form == 1 {
                let ir = _int_parse_str(text, vs, ve);
                if !ir.is_ok {
                  return _err_bool(ir.error);
                }
                cur_sidx = ir.value;
                saw_v = true;
              } else {
                if cur_form == 2 {
                  let ur2 = _xml_unescape(text, vs, ve);
                  if !ur2.is_ok {
                    return _err_bool(ur2.error);
                  }
                  let piece2: Str = ur2.value;
                  _push_str(&mut cur_text, piece2);
                  has_text = true;
                  saw_v = true;
                } else {
                  if cur_kind == _K_BOOL {
                    let br = _int_parse_str(text, vs, ve);
                    if !br.is_ok {
                      return _err_bool(br.error);
                    }
                    cur_bval = br.value;
                    saw_v = true;
                  } else {
                    let dr = _dec_parse(text, vs, ve);
                    if !dr.is_ok {
                      return _err_bool(dr.error);
                    }
                    cur_num = dr.value;
                    saw_v = true;
                  };
                };
              };
            };
          } else {
            if active && _tag_name_is(text, lt, e, "t") {
              if !_tag_self_closing(text, e) {
                let ts2 = e + 1;
                let te2 = _text_until_lt(text, ts2);
                let ur3 = _xml_unescape(text, ts2, te2);
                if !ur3.is_ok {
                  return _err_bool(ur3.error);
                }
                let piece3: Str = ur3.value;
                _push_str(&mut cur_text, piece3);
                has_text = true;
                saw_v = true;
              };
            };
          };
        };
      } else {
        if kind == 1 && _tag_name_is(text, lt, e, "c") {
          if active {
            if saw_v {
              if cur_kind == _K_STR && has_text {
                let sval2 = builder.sb_to_str(&cur_text);
                var si = _str_intern(wb, sval2);
                if si < 0 {
                  return _err_bool("xlsx: string pool limit exceeded");
                }
                cur_sidx = si;
              };
              if cur_kind == _K_STR {
                if cur_sidx < 0 || cur_sidx >= wb.str_pool.len() {
                  return _err_bool("xlsx: shared string index out of range");
                }
              };
              if !_wb_push_cell(wb, sheet, cur_row, cur_col, cur_kind, cur_num, cur_bval, cur_sidx, cur_style) {
                return _err_bool("xlsx: cell limit exceeded");
              };
            };
            active = false;
          };
        };
      };
      i = e + 1;
    };
  }
  if active {
    return _err_bool("xlsx: unclosed cell element");
  }
  return _ok_bool(true);
}

// Relationship target for `rid` in a workbook.xml.rels part.
fn _rels_target(text: Str, rid: Str) -> Result[Str, Str] {
  let n = text.len();
  var i = 0;
  while i < n {
    let lt = _find_byte(text, i, _B_LT);
    if lt < 0 {
      i = n;
    } else {
      let e = _tag_end(text, lt);
      if e < 0 {
        return _err_str("xlsx: xml unterminated tag");
      }
      if _tag_kind(text, lt, e) == 0 && _tag_name_is(text, lt, e, "Relationship") {
        let ir = _attr(text, lt, e, "Id");
        if ir.is_ok {
          let id: Str = ir.value;
          if compare.str_compare(id, rid) == 0 {
            let tr = _attr(text, lt, e, "Target");
            if !tr.is_ok {
              return _err_str("xlsx: relationship missing target");
            }
            let tgt: Str = tr.value;
            return _ok_str(tgt);
          };
        };
      };
      i = e + 1;
    };
  }
  return _err_str("xlsx: relationship not found");
}

// Resolve a relationship target to an archive entry name. Absolute targets
// (/xl/...) are matched directly; relative targets are resolved against xl/.
fn _resolve_target(z: &XlsxZip, tgt: Str) -> Result[Str, Str] {
  let n = tgt.len();
  if n == 0 {
    return _err_str("xlsx: unsupported relationship target");
  }
  if string.str_contains(tgt, "..") {
    return _err_str("xlsx: unsupported relationship target");
  }
  let c0: Int = (string.byte_at(tgt, 0) as Int) & 0xFF;
  if c0 == 47 {
    let abs = string.str_slice(tgt, 1, n);
    let ai = xlsx_zip_find(z, abs);
    if ai >= 0 {
      let an: Str = z.names[ai];
      return _ok_str(an);
    }
    return _err_str("xlsx: missing worksheet part");
  }
  let rel = "xl/" + tgt;
  let ri = xlsx_zip_find(z, rel);
  if ri >= 0 {
    let rn: Str = z.names[ri];
    return _ok_str(rn);
  }
  let di = xlsx_zip_find(z, tgt);
  if di >= 0 {
    let dn: Str = z.names[di];
    return _ok_str(dn);
  }
  return _err_str("xlsx: missing worksheet part");
}

// Read one archive entry as NUL-free text.
fn _zip_text(z: &XlsxZip, i: Int) -> Result[Str, Str] {
  let dr = xlsx_zip_data(z, i);
  if !dr.is_ok {
    return _err_str(dr.error);
  }
  let bytes: Vec[UInt8] = dr.value;
  return _range_to_str(&bytes, 0, bytes.len());
}

fn _xlsx_from_zip(z: &XlsxZip) -> Result[XlsxWorkbook, Str] {
  var wb = xlsx_workbook_new();
  let wi = xlsx_zip_find(z, "xl/workbook.xml");
  if wi < 0 {
    return _err_wb("xlsx: missing xl/workbook.xml");
  }
  let wt = _zip_text(z, wi);
  if !wt.is_ok {
    return _err_wb(wt.error);
  }
  let wtext: Str = wt.value;
  var rids = Vec[Str].new();
  let pr = _parse_workbook_part(wtext, &mut wb, &mut rids);
  if !pr.is_ok {
    return _err_wb(pr.error);
  }
  let si = xlsx_zip_find(z, "xl/sharedStrings.xml");
  if si >= 0 {
    let st = _zip_text(z, si);
    if !st.is_ok {
      return _err_wb(st.error);
    }
    let stext: Str = st.value;
    let sp = _parse_shared_part(stext, &mut wb);
    if !sp.is_ok {
      return _err_wb(sp.error);
    }
  };
  let ti = xlsx_zip_find(z, "xl/styles.xml");
  if ti >= 0 {
    let tt = _zip_text(z, ti);
    if !tt.is_ok {
      return _err_wb(tt.error);
    }
    let ttext: Str = tt.value;
    let tp = _parse_styles_part(ttext, &mut wb);
    if !tp.is_ok {
      return _err_wb(tp.error);
    }
  };
  let ri = xlsx_zip_find(z, "xl/_rels/workbook.xml.rels");
  var k = 0;
  while k < wb.sheet_names.len() {
    var part = "";
    if k < rids.len() {
      let rid: Str = rids[k];
      if rid.len() > 0 && ri >= 0 {
        let rt = _zip_text(z, ri);
        if rt.is_ok {
          let rtext: Str = rt.value;
          let tg = _rels_target(rtext, rid);
          if tg.is_ok {
            let tgt: Str = tg.value;
            let pn = _resolve_target(z, tgt);
            if pn.is_ok {
              let pns: Str = pn.value;
              part = pns;
            };
          };
        };
      };
    };
    if part.len() == 0 {
      let fb = "xl/worksheets/sheet" + convert.int_to_string(k + 1) + ".xml";
      if xlsx_zip_find(z, fb) >= 0 {
        part = fb;
      };
    };
    if part.len() == 0 {
      return _err_wb("xlsx: missing worksheet part");
    }
    let pi = xlsx_zip_find(z, part);
    if pi < 0 {
      return _err_wb("xlsx: missing worksheet part");
    }
    let stt = _zip_text(z, pi);
    if !stt.is_ok {
      return _err_wb(stt.error);
    }
    let stext2: Str = stt.value;
    let spr = _parse_sheet_part(stext2, &mut wb, k);
    if !spr.is_ok {
      return _err_wb(spr.error);
    }
    k = k + 1;
  }
  return _ok_wb(wb);
}

/// Parse a complete XLSX (ZIP) byte stream into a sparse workbook model.
/// STORED and fixed-Huffman-deflate entries are supported; dynamic-Huffman
/// deflate streams fail with a deterministic error (see SPEC.md).
pub fn xlsx_read(buffer: &Vec[UInt8]) -> Result[XlsxWorkbook, Str] {
  let zr = xlsx_zip_scan(buffer);
  if !zr.is_ok {
    return _err_wb(zr.error);
  }
  let z: XlsxZip = zr.value;
  return _xlsx_from_zip(&z);
}
