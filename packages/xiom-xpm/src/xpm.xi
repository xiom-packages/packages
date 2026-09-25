// XIOM -- xiom.xpm: X PixMap (XPM) X11 color-pixmap parsing and canonical building
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure XIOM, no FFI. XPM is the C-source color pixmap format used by X11:
//
//   /* XPM */
//   static char * sample[] = {
//   "2 2 2 1",
//   "  c #ffffff",
//   "X c #000000",
//   " X",
//   "X ",
//   };
//
// This module parses that subset: the optional `/* XPM */` header comment
// (any C comment is accepted between tokens), the
// `static char * <name>[] = { ... };` string list, the value line
// `w h ncolors cpp [x_hot y_hot]`, one color line per color
// (`<cpp symbol chars> <ws> c <ws> <value>`, where bytes after the value are
// extension keys that are accepted and ignored), and `height` pixel rows of
// exactly `width * cpp` symbol characters each. Inside string literals the C
// escapes `\\`, `\"`, `\n` and `\t` are decoded; any other escape is an
// error. A color value is either `#` plus exactly six hex digits or a
// non-empty name token passed through verbatim (so `None` and symbolic names
// survive round trips).
//
// The payload is stored flat, never as a Vec[StructType]: a symbol-character
// pool of ncolors * cpp bytes, the color-value strings (with a parallel
// length Vec so the module never measures a Vec[Str] element), and one color
// index per pixel in row-major order. Accessors expose the dimensions, cpp,
// the color table, symbol lookup and (x, y) pixel lookup; xpm_build and
// xpm_build_hotspot emit canonical XPM text. See SPEC.md for the exact
// grammar, the canonical layout, the error catalog and the test matrix.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read is widened with `(x as Int) & 0xFF`; a UInt8 is never
//     compared against an Int constant without masking.
//   * Strs are built with builder.sb_to_str only from byte ranges validated
//     as NUL-free (control bytes other than TAB are rejected at parse time).
//   * symbol lengths come from the parallel Vec[Int] color_lens / the source
//     buffers, never from a `.len()` call on a Vec[Str] element.

module xiom.xpm

use xiom.string;
use xiom.string.builder;

// Parsed XPM image, stored flat (no Vec[StructType]).
//
// `symbols[i * cpp + j]` is the j-th symbol character of color entry `i`, so
// the symbol of entry i is `symbols[i * cpp .. (i + 1) * cpp)`.
// `colors[i]` is the color value of entry i exactly as written in the source
// (hex spelling preserved, names passed through); `color_lens[i]` is its byte
// length. `pixels[y * width + x]` is the color-table index of pixel (x, y).
// Parsed images always have width/height in 1..1000000, cpp in 1..4 and
// ncolors in 1..4096; x_hot/y_hot are -1 when has_hotspot is false.
pub type XpmImage = {
  width: Int;           // 1..1000000
  height: Int;          // 1..1000000
  cpp: Int;             // 1..4 symbol characters per pixel
  has_hotspot: Bool;    // true when the value line carried x_hot/y_hot
  x_hot: Int;           // 0..width when has_hotspot, -1 otherwise
  y_hot: Int;           // 0..height when has_hotspot, -1 otherwise
  symbols: Vec[UInt8];  // ncolors * cpp symbol characters, color order
  colors: Vec[Str];     // ncolors color values, source spelling preserved
  color_lens: Vec[Int]; // ncolors; byte length of colors[i]
  pixels: Vec[Int];     // width * height color indices, row-major
}

// Decoded value line. `err` is "" when ok is true.
type XpmHeader = {
  ok: Bool;
  err: Str;
  width: Int;
  height: Int;
  ncolors: Int;
  cpp: Int;
  has_hotspot: Bool;
  x_hot: Int;
  y_hot: Int;
}

// Decoded color line: `value_start`/`value_len` delimit the color value
// inside the color-line string. `err` is "" when ok is true.
type ColorLine = {
  ok: Bool;
  err: Str;
  value_start: Int;
  value_len: Int;
}

// ---------------------------------------------------------------------------
// Result leaf helpers (v0.61.3: Ok/Err construction is confined to fns that
// return a Result directly, so fallible public fns return through these).
// ---------------------------------------------------------------------------

// Ok(v) for Result[XpmImage, Str].
fn _ok_img(v: XpmImage) -> Result[XpmImage, Str] { return Ok(v); }

// Err(m) for Result[XpmImage, Str].
fn _err_img(m: Str) -> Result[XpmImage, Str] { return Err(m); }

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] { return Ok(v); }

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Byte predicates
// ---------------------------------------------------------------------------

// Unsigned byte at index i (widening masked to 0..255).
fn _b(data: &Vec[UInt8], i: Int) -> Int {
  return (data[i] as Int) & 0xFF;
}

// C whitespace: SPACE, TAB, LF, CR, VT, FF.
fn _is_space(b: Int) -> Bool {
  if (b == 32) { return true; }
  if (b == 9) { return true; }
  if (b == 10) { return true; }
  if (b == 13) { return true; }
  if (b == 11) { return true; }
  if (b == 12) { return true; }
  return false;
}

// ASCII '0'..'9'.
fn _is_digit(b: Int) -> Bool {
  if (b < 48) { return false; }
  if (b > 57) { return false; }
  return true;
}

// Hex digit value 0..15, or -1 when `b` is not [0-9A-Fa-f].
fn _hex_val(b: Int) -> Int {
  if (b >= 48 && b <= 57) { return b - 48; }
  if (b >= 97 && b <= 102) { return b - 87; }
  if (b >= 65 && b <= 70) { return b - 55; }
  return -1;
}

// A symbol character: any byte except ASCII control bytes and DEL, so
// 0x20..0xFF minus 0x7F. TAB (0x09) can only be a separator, never a symbol.
fn _symbol_byte_ok(b: Int) -> Bool {
  if (b < 32) { return false; }
  if (b == 127) { return false; }
  return true;
}

// C identifier start: A-Z, a-z, '_'.
fn _is_ident_start(b: Int) -> Bool {
  if (b >= 65 && b <= 90) { return true; }
  if (b >= 97 && b <= 122) { return true; }
  if (b == 95) { return true; }
  return false;
}

// C identifier continuation: identifier start or ASCII digit.
fn _is_ident_char(b: Int) -> Bool {
  if (_is_ident_start(b)) { return true; }
  if (_is_digit(b)) { return true; }
  return false;
}

// End index of the C identifier at `start`, or `start` when none begins there.
fn _ident_end(data: &Vec[UInt8], n: Int, start: Int) -> Int {
  if (start >= n) { return start; }
  if (!_is_ident_start(_b(data, start))) { return start; }
  var i = start + 1;
  while (i < n) {
    if (!_is_ident_char(_b(data, i))) { break; }
    i = i + 1;
  }
  return i;
}

// True when `name` is a non-empty C identifier: [A-Za-z_][A-Za-z0-9_]*.
fn _name_ok(name: Str) -> Bool {
  let n = name.len();
  if (n <= 0) { return false; }
  let b0: UInt8 = string.byte_at(name, 0);
  if (!_is_ident_start((b0 as Int) & 0xFF)) { return false; }
  var i = 1;
  while (i < n) {
    let b: UInt8 = string.byte_at(name, i);
    if (!_is_ident_char((b as Int) & 0xFF)) { return false; }
    i = i + 1;
  }
  return true;
}

// True when keyword `s` matches data at `start` and ends on a word boundary
// (the following byte is not an identifier character), so `staticx` fails.
fn _match_kw(data: &Vec[UInt8], n: Int, start: Int, s: Str) -> Bool {
  let sl = s.len();
  if (start + sl > n) { return false; }
  var i = 0;
  while (i < sl) {
    let a = _b(data, start + i);
    let b: UInt8 = string.byte_at(s, i);
    if (a != ((b as Int) & 0xFF)) { return false; }
    i = i + 1;
  }
  if (start + sl < n) {
    if (_is_ident_char(_b(data, start + sl))) { return false; }
  }
  return true;
}

// ---------------------------------------------------------------------------
// Trivia
// ---------------------------------------------------------------------------

// Index of the next byte that is neither C whitespace nor inside a C comment,
// starting at `start`. Returns -1 when a comment is opened but never closed.
// Comments do not nest. Callers only invoke this between tokens, never inside
// a string literal, so `/*` inside a quoted string is not a comment.
fn _skip_trivia(data: &Vec[UInt8], n: Int, start: Int) -> Int {
  var i = start;
  var go: Bool = true;
  while (go) {
    if (i >= n) {
      go = false;
    } else {
      let c = _b(data, i);
      if (c == 47 && i + 1 < n && _b(data, i + 1) == 42) {
        i = i + 2;
        var closed: Bool = false;
        while (i + 1 < n) {
          if (_b(data, i) == 42 && _b(data, i + 1) == 47) {
            i = i + 2;
            closed = true;
            break;
          }
          i = i + 1;
        }
        if (!closed) { return -1; }
      } else {
        if (_is_space(c)) { i = i + 1; } else { go = false; }
      }
    }
  }
  return i;
}

// ---------------------------------------------------------------------------
// String literals
// ---------------------------------------------------------------------------

// Scan the C string literal starting at `start` (which must be a '"').
// Returns the index just past the closing quote, or -1 when EOF is reached
// first (unterminated), -2 for an escape other than \\ \" \n \t, -3 for a raw
// control byte inside the literal (anything below 0x20 except TAB, plus DEL).
fn _scan_string(data: &Vec[UInt8], n: Int, start: Int) -> Int {
  var i = start + 1;
  while (i < n) {
    let c = _b(data, i);
    if (c == 34) { return i + 1; }
    if (c == 92) {
      if (i + 1 >= n) { return -2; }
      let e = _b(data, i + 1);
      if (e == 92 || e == 34 || e == 110 || e == 116) {
        i = i + 2;
      } else {
        return -2;
      }
    } else {
      if (c < 32 && c != 9) { return -3; }
      if (c == 127) { return -3; }
      i = i + 1;
    }
  }
  return -1;
}

// Decode the contents of the C string literal in data[start, end), where
// `start` is the first content byte and `end` the closing quote index. The
// range was validated by _scan_string, so decoding cannot fail.
fn _decode_string(data: &Vec[UInt8], start: Int, end: Int) -> Str {
  let sb = Vec[UInt8].new();
  var i = start;
  while (i < end) {
    let c = _b(data, i);
    if (c == 92) {
      let e = _b(data, i + 1);
      if (e == 92) {
        sb.push(92 as UInt8);
      } else {
        if (e == 34) {
          sb.push(34 as UInt8);
        } else {
          if (e == 110) {
            sb.push(10 as UInt8);
          } else {
            sb.push(9 as UInt8);
          }
        }
      }
      i = i + 2;
    } else {
      sb.push(c as UInt8);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&sb);
}

// Copy s[start, start+len) into a fresh Str. Used for color values, whose
// bytes were already validated as non-control, so no NUL can appear.
fn _substr_str(s: Str, start: Int, len: Int) -> Str {
  let sb = Vec[UInt8].new();
  var i = 0;
  while (i < len) {
    let b: UInt8 = string.byte_at(s, start + i);
    sb.push(b);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// ---------------------------------------------------------------------------
// Str scanners (decoded strings; every read is bounded by an explicit length)
// ---------------------------------------------------------------------------

// C whitespace byte at index i of `h`.
fn _str_is_ws(h: Str, i: Int) -> Bool {
  let b: UInt8 = string.byte_at(h, i);
  return _is_space((b as Int) & 0xFF);
}

// Length of the decimal digit run at `start` in h[0, hlen) (0 when not a digit).
fn _str_dec_len(h: Str, hlen: Int, start: Int) -> Int {
  var i = start;
  while (i < hlen) {
    let b: UInt8 = string.byte_at(h, i);
    if (!_is_digit((b as Int) & 0xFF)) { break; }
    i = i + 1;
  }
  return i - start;
}

// Decimal value of h[start, start+len), a non-empty digit run of <= 9 digits.
fn _str_dec_value(h: Str, start: Int, len: Int) -> Int {
  var v = 0;
  var i = 0;
  while (i < len) {
    let b: UInt8 = string.byte_at(h, start + i);
    v = v * 10 + (((b as Int) & 0xFF) - 48);
    i = i + 1;
  }
  return v;
}

// Error value line with message `m`.
fn _hdr_bad(m: Str) -> XpmHeader {
  return XpmHeader{ ok: false; err: m; width: 0; height: 0; ncolors: 0; cpp: 0; has_hotspot: false; x_hot: -1; y_hot: -1; };
}

// Parse the value line: 4 or 6 whitespace-separated positive decimal tokens
// `w h ncolors cpp [x_hot y_hot]`. Width/height are capped at 1000000,
// ncolors at 4096, cpp must be 1..4, and hotspot coordinates must satisfy
// 0 <= x_hot <= width and 0 <= y_hot <= height.
fn _parse_header(h: Str, hlen: Int) -> XpmHeader {
  let starts = Vec[Int].new();
  let lens = Vec[Int].new();
  var pos = 0;
  var bad: Bool = false;
  while (pos < hlen) {
    var go: Bool = true;
    while (go) {
      if (pos >= hlen) { go = false; } else {
        if (_str_is_ws(h, pos)) { pos = pos + 1; } else { go = false; }
      }
    }
    if (pos >= hlen) { break; }
    let dlen = _str_dec_len(h, hlen, pos);
    if (dlen == 0) { bad = true; break; }
    starts.push(pos);
    lens.push(dlen);
    pos = pos + dlen;
  }
  if (bad) { return _hdr_bad("xpm: malformed header"); }
  let nt = starts.len();
  if (nt != 4 && nt != 6) { return _hdr_bad("xpm: malformed header"); }

  let wl: Int = lens[0];
  if (wl > 9) { return _hdr_bad("xpm: invalid width"); }
  let width = _str_dec_value(h, starts[0], wl);
  if (width <= 0) { return _hdr_bad("xpm: invalid width"); }
  if (width > 1000000) { return _hdr_bad("xpm: invalid width"); }

  let hl: Int = lens[1];
  if (hl > 9) { return _hdr_bad("xpm: invalid height"); }
  let height = _str_dec_value(h, starts[1], hl);
  if (height <= 0) { return _hdr_bad("xpm: invalid height"); }
  if (height > 1000000) { return _hdr_bad("xpm: invalid height"); }

  let nl: Int = lens[2];
  if (nl > 9) { return _hdr_bad("xpm: invalid ncolors"); }
  let ncolors = _str_dec_value(h, starts[2], nl);
  if (ncolors <= 0) { return _hdr_bad("xpm: invalid ncolors"); }
  if (ncolors > 4096) { return _hdr_bad("xpm: invalid ncolors"); }

  let pl: Int = lens[3];
  if (pl > 9) { return _hdr_bad("xpm: invalid cpp"); }
  let cpp = _str_dec_value(h, starts[3], pl);
  if (cpp <= 0) { return _hdr_bad("xpm: invalid cpp"); }
  if (cpp > 4) { return _hdr_bad("xpm: invalid cpp"); }

  var has_hotspot: Bool = false;
  var x_hot = -1;
  var y_hot = -1;
  if (nt == 6) {
    let xl: Int = lens[4];
    if (xl > 9) { return _hdr_bad("xpm: invalid hotspot"); }
    x_hot = _str_dec_value(h, starts[4], xl);
    if (x_hot > width) { return _hdr_bad("xpm: invalid hotspot"); }
    let yl: Int = lens[5];
    if (yl > 9) { return _hdr_bad("xpm: invalid hotspot"); }
    y_hot = _str_dec_value(h, starts[5], yl);
    if (y_hot > height) { return _hdr_bad("xpm: invalid hotspot"); }
    has_hotspot = true;
  }
  return XpmHeader{
    ok: true;
    err: "";
    width: width;
    height: height;
    ncolors: ncolors;
    cpp: cpp;
    has_hotspot: has_hotspot;
    x_hot: x_hot;
    y_hot: y_hot;
  };
}

// ---------------------------------------------------------------------------
// Color lines and symbol tables
// ---------------------------------------------------------------------------

// Error color line with message `m`.
fn _cl_bad(m: Str) -> ColorLine {
  return ColorLine{ ok: false; err: m; value_start: 0; value_len: 0; };
}

// Parse one color line of decoded byte length `l`:
//   <cpp symbol chars> <ws>+ 'c' <ws>+ <value> [<ws>+ ignored keys]
// The value is `#` plus six hex digits (spelled as written) or a non-empty
// name token without whitespace, '#' or '"'. Bytes after the value are
// accepted and ignored (XPM extension keys such as `m`, `s` and `g`).
fn _parse_color_line(line: Str, l: Int, cpp: Int) -> ColorLine {
  if (l < cpp) { return _cl_bad("xpm: malformed color line"); }
  var j = 0;
  while (j < cpp) {
    let sb: UInt8 = string.byte_at(line, j);
    if (!_symbol_byte_ok((sb as Int) & 0xFF)) { return _cl_bad("xpm: invalid symbol"); }
    j = j + 1;
  }
  var pos = cpp;
  if (pos >= l) { return _cl_bad("xpm: malformed color line"); }
  if (!_str_is_ws(line, pos)) { return _cl_bad("xpm: malformed color line"); }
  var go: Bool = true;
  while (go) {
    if (pos >= l) { go = false; } else {
      if (_str_is_ws(line, pos)) { pos = pos + 1; } else { go = false; }
    }
  }
  if (pos >= l) { return _cl_bad("xpm: malformed color line"); }
  let key: UInt8 = string.byte_at(line, pos);
  if (((key as Int) & 0xFF) != 99) { return _cl_bad("xpm: malformed color line"); }
  pos = pos + 1;
  if (pos >= l) { return _cl_bad("xpm: malformed color line"); }
  if (!_str_is_ws(line, pos)) { return _cl_bad("xpm: malformed color line"); }
  go = true;
  while (go) {
    if (pos >= l) { go = false; } else {
      if (_str_is_ws(line, pos)) { pos = pos + 1; } else { go = false; }
    }
  }
  if (pos >= l) { return _cl_bad("xpm: malformed color line"); }
  let vb: UInt8 = string.byte_at(line, pos);
  let v: Int = (vb as Int) & 0xFF;
  if (v == 35) {
    if (pos + 7 > l) { return _cl_bad("xpm: malformed color value"); }
    var k = 1;
    while (k < 7) {
      let hb: UInt8 = string.byte_at(line, pos + k);
      if (_hex_val((hb as Int) & 0xFF) < 0) { return _cl_bad("xpm: malformed color value"); }
      k = k + 1;
    }
    if (pos + 7 < l) {
      if (!_str_is_ws(line, pos + 7)) { return _cl_bad("xpm: malformed color value"); }
    }
    return ColorLine{ ok: true; err: ""; value_start: pos; value_len: 7; };
  }
  var e = pos;
  while (e < l) {
    if (_str_is_ws(line, e)) { break; }
    let nb: UInt8 = string.byte_at(line, e);
    let nv: Int = (nb as Int) & 0xFF;
    if (nv < 32) { return _cl_bad("xpm: malformed color value"); }
    if (nv == 35) { return _cl_bad("xpm: malformed color value"); }
    if (nv == 34) { return _cl_bad("xpm: malformed color value"); }
    e = e + 1;
  }
  if (e == pos) { return _cl_bad("xpm: malformed color value"); }
  return ColorLine{ ok: true; err: ""; value_start: pos; value_len: e - pos; };
}

// Index of the first color entry whose cpp-byte symbol equals the cpp bytes
// of `s` starting at `off`, or -1 when there is none. Also the duplicate
// detector for color lines (count = entries added so far, off = 0).
fn _symbol_find(symbols: &Vec[UInt8], count: Int, cpp: Int, s: Str, off: Int) -> Int {
  var k = 0;
  while (k < count) {
    var same: Bool = true;
    var j = 0;
    while (j < cpp) {
      let pool_b: Int = (symbols[k * cpp + j] as Int) & 0xFF;
      let cand_b: UInt8 = string.byte_at(s, off + j);
      if (pool_b != ((cand_b as Int) & 0xFF)) { same = false; break; }
      j = j + 1;
    }
    if (same) { return k; }
    k = k + 1;
  }
  return -1;
}

// Index of the second occurrence of any symbol in the pool, or -1 when all
// ncolors symbols are distinct.
fn _pool_dup(symbols: &Vec[UInt8], ncolors: Int, cpp: Int) -> Int {
  var i = 1;
  while (i < ncolors) {
    var k = 0;
    while (k < i) {
      var same: Bool = true;
      var j = 0;
      while (j < cpp) {
        let a: Int = (symbols[i * cpp + j] as Int) & 0xFF;
        let b: Int = (symbols[k * cpp + j] as Int) & 0xFF;
        if (a != b) { same = false; break; }
        j = j + 1;
      }
      if (same) { return i; }
      k = k + 1;
    }
    i = i + 1;
  }
  return -1;
}

// True when `c` (byte length cl) is a valid stored color value: `#` plus six
// hex digits, or a non-empty name without whitespace, control bytes, '#' or
// '"'. Stored values never contain whitespace because a color line's value
// token ends at the first whitespace byte.
fn _color_value_ok(c: Str, cl: Int) -> Bool {
  if (cl <= 0) { return false; }
  let b0: UInt8 = string.byte_at(c, 0);
  if (((b0 as Int) & 0xFF) == 35) {
    if (cl != 7) { return false; }
    var k = 1;
    while (k < 7) {
      let hb: UInt8 = string.byte_at(c, k);
      if (_hex_val((hb as Int) & 0xFF) < 0) { return false; }
      k = k + 1;
    }
    return true;
  }
  var k = 0;
  while (k < cl) {
    let v: Int = (string.byte_at(c, k) as Int) & 0xFF;
    if (v < 32) { return false; }
    if (_is_space(v)) { return false; }
    if (v == 34) { return false; }
    if (v == 35) { return false; }
    if (v == 127) { return false; }
    k = k + 1;
  }
  return true;
}

// True when the image's parallel arrays and fields are mutually consistent.
fn _consistent(img: &XpmImage) -> Bool {
  let ncolors = img.colors.len();
  if (ncolors < 1) { return false; }
  if (ncolors > 4096) { return false; }
  if (img.cpp < 1) { return false; }
  if (img.cpp > 4) { return false; }
  if (img.color_lens.len() != ncolors) { return false; }
  if (img.symbols.len() != ncolors * img.cpp) { return false; }
  if (img.width < 1) { return false; }
  if (img.height < 1) { return false; }
  if (img.width > 1000000) { return false; }
  if (img.height > 1000000) { return false; }
  if (img.pixels.len() != img.width * img.height) { return false; }
  return true;
}

// ---------------------------------------------------------------------------
// Writers (canonical builder)
// ---------------------------------------------------------------------------

// Append `s` verbatim to `out`.
fn _put_str(out: &mut Vec[UInt8], s: Str) {
  let n = s.len();
  var i = 0;
  while (i < n) {
    let b: UInt8 = string.byte_at(s, i);
    out.push(b);
    i = i + 1;
  }
}

// Append the ASCII decimal spelling of v (v >= 0) to out.
fn _put_uint(out: &mut Vec[UInt8], v: Int) {
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

// Append byte `b` (0..255) to the XPM C string being built, escaping the
// backslash, double quote, TAB and LF as `\\`, `\"`, `\t` and `\n`.
fn _put_cbyte(out: &mut Vec[UInt8], b: Int) {
  if (b == 92) {
    out.push(92 as UInt8);
    out.push(92 as UInt8);
    return;
  }
  if (b == 34) {
    out.push(92 as UInt8);
    out.push(34 as UInt8);
    return;
  }
  if (b == 9) {
    out.push(92 as UInt8);
    out.push(116 as UInt8);
    return;
  }
  if (b == 10) {
    out.push(92 as UInt8);
    out.push(110 as UInt8);
    return;
  }
  out.push(b as UInt8);
}

// ---------------------------------------------------------------------------
// Public API: accessors
// ---------------------------------------------------------------------------

// Raster width in pixels of a parsed or built image (always 1..1000000 for a
// consistent image).
pub fn xpm_width(img: &XpmImage) -> Int {
  return img.width;
}

// Raster height in pixels of a parsed or built image (always 1..1000000 for a
// consistent image).
pub fn xpm_height(img: &XpmImage) -> Int {
  return img.height;
}

// Number of color-table entries: the length of `img.colors`.
pub fn xpm_ncolors(img: &XpmImage) -> Int {
  return img.colors.len();
}

// Symbol characters per pixel (cpp): 1..4.
pub fn xpm_cpp(img: &XpmImage) -> Int {
  return img.cpp;
}

// True when the source carried a hot spot (`w h ncolors cpp x_hot y_hot`).
pub fn xpm_has_hotspot(img: &XpmImage) -> Bool {
  return img.has_hotspot;
}

// Hot spot x coordinate, or -1 when the image has no hot spot.
pub fn xpm_hotspot_x(img: &XpmImage) -> Int {
  if (!img.has_hotspot) { return -1; }
  return img.x_hot;
}

// Hot spot y coordinate, or -1 when the image has no hot spot.
pub fn xpm_hotspot_y(img: &XpmImage) -> Int {
  if (!img.has_hotspot) { return -1; }
  return img.y_hot;
}

// Color-table index of pixel (x, y) with a top-left origin, or the documented
// sentinel -1 when (x, y) is outside the image or the image is internally
// inconsistent. Callers that need to tell "malformed image" from "out of
// range" call xpm_parse first.
pub fn xpm_pixel_index(img: &XpmImage, x: Int, y: Int) -> Int {
  if (!_consistent(img)) { return -1; }
  if (x < 0) { return -1; }
  if (y < 0) { return -1; }
  if (x >= img.width) { return -1; }
  if (y >= img.height) { return -1; }
  let k: Int = img.pixels[y * img.width + x];
  return k;
}

// Color value of pixel (x, y), or "" when (x, y) is outside the image or the
// image is internally inconsistent. The sentinel is unambiguous because
// stored color values are never empty.
pub fn xpm_pixel_color(img: &XpmImage, x: Int, y: Int) -> Str {
  let k = xpm_pixel_index(img, x, y);
  if (k < 0) { return ""; }
  let c: Str = img.colors[k];
  return c;
}

// Color value of table entry `index`, or "" when `index` is outside
// 0..ncolors-1. The stored spelling is preserved.
pub fn xpm_color_at(img: &XpmImage, index: Int) -> Str {
  if (index < 0) { return ""; }
  if (index >= img.colors.len()) { return ""; }
  let c: Str = img.colors[index];
  return c;
}

// Color-table index whose cpp-character symbol is `symbol`, or -1 when no
// entry matches or `symbol.len() != cpp` or the image is inconsistent.
pub fn xpm_symbol_index(img: &XpmImage, symbol: Str) -> Int {
  if (!_consistent(img)) { return -1; }
  if (symbol.len() != img.cpp) { return -1; }
  let symbols: Vec[UInt8] = img.symbols;
  return _symbol_find(&symbols, img.colors.len(), img.cpp, symbol, 0);
}

// The cpp-character symbol of color entry `index`, or "" when `index` is
// outside 0..ncolors-1 or the image is inconsistent.
pub fn xpm_symbol_at(img: &XpmImage, index: Int) -> Str {
  if (index < 0) { return ""; }
  if (index >= img.colors.len()) { return ""; }
  if (img.cpp < 1) { return ""; }
  if (img.cpp > 4) { return ""; }
  if (img.symbols.len() < (index + 1) * img.cpp) { return ""; }
  let sb = Vec[UInt8].new();
  var j = 0;
  while (j < img.cpp) {
    let b: UInt8 = img.symbols[index * img.cpp + j];
    sb.push(b);
    j = j + 1;
  }
  return builder.sb_to_str(&sb);
}

// ---------------------------------------------------------------------------
// Public API: parse
// ---------------------------------------------------------------------------

// Parse XPM text into an XpmImage: the optional `/* XPM */` header comment,
// the `static char * <name>[] = { ... };` declaration with its string list,
// the value line `w h ncolors cpp [x_hot y_hot]`, `ncolors` color lines and
// `height` pixel rows of `width * cpp` symbol characters. C comments and any
// whitespace may separate tokens outside string literals; a single trailing
// comma before `}` is accepted. Errors are the deterministic `xpm: ...`
// strings catalogued in SPEC.md.
pub fn xpm_parse(data: &Vec[UInt8]) -> Result[XpmImage, Str] {
  let n = data.len();
  var pos = _skip_trivia(data, n, 0);
  if (pos < 0) { return _err_img("xpm: unclosed comment"); }
  if (!_match_kw(data, n, pos, "static")) { return _err_img("xpm: malformed declaration"); }
  pos = pos + 6;
  pos = _skip_trivia(data, n, pos);
  if (pos < 0) { return _err_img("xpm: unclosed comment"); }
  if (!_match_kw(data, n, pos, "char")) { return _err_img("xpm: malformed declaration"); }
  pos = pos + 4;
  pos = _skip_trivia(data, n, pos);
  if (pos < 0) { return _err_img("xpm: unclosed comment"); }
  if (pos >= n) { return _err_img("xpm: malformed declaration"); }
  if (_b(data, pos) != 42) { return _err_img("xpm: malformed declaration"); }
  pos = pos + 1;
  pos = _skip_trivia(data, n, pos);
  if (pos < 0) { return _err_img("xpm: unclosed comment"); }
  let iend = _ident_end(data, n, pos);
  if (iend == pos) { return _err_img("xpm: malformed declaration"); }
  pos = iend;
  pos = _skip_trivia(data, n, pos);
  if (pos < 0) { return _err_img("xpm: unclosed comment"); }
  if (pos >= n) { return _err_img("xpm: malformed declaration"); }
  if (_b(data, pos) != 91) { return _err_img("xpm: malformed declaration"); }
  pos = pos + 1;
  pos = _skip_trivia(data, n, pos);
  if (pos < 0) { return _err_img("xpm: unclosed comment"); }
  if (pos >= n) { return _err_img("xpm: malformed declaration"); }
  if (_b(data, pos) != 93) { return _err_img("xpm: malformed declaration"); }
  pos = pos + 1;
  pos = _skip_trivia(data, n, pos);
  if (pos < 0) { return _err_img("xpm: unclosed comment"); }
  if (pos >= n) { return _err_img("xpm: malformed declaration"); }
  if (_b(data, pos) != 61) { return _err_img("xpm: malformed declaration"); }
  pos = pos + 1;
  pos = _skip_trivia(data, n, pos);
  if (pos < 0) { return _err_img("xpm: unclosed comment"); }
  if (pos >= n) { return _err_img("xpm: malformed declaration"); }
  if (_b(data, pos) != 123) { return _err_img("xpm: malformed declaration"); }
  pos = pos + 1;

  // String list: "..." ( , "..." )* [,] "}".
  let parts = Vec[Str].new();
  let lens = Vec[Int].new();
  var done: Bool = false;
  var need_comma: Bool = false;
  while (!done) {
    pos = _skip_trivia(data, n, pos);
    if (pos < 0) { return _err_img("xpm: unclosed comment"); }
    if (pos >= n) { return _err_img("xpm: unclosed string list"); }
    let c = _b(data, pos);
    if (c == 125) {
      done = true;
    } else {
      if (need_comma) {
        if (c != 44) { return _err_img("xpm: malformed declaration"); }
        pos = pos + 1;
        pos = _skip_trivia(data, n, pos);
        if (pos < 0) { return _err_img("xpm: unclosed comment"); }
        if (pos >= n) { return _err_img("xpm: unclosed string list"); }
        if (_b(data, pos) == 125) { done = true; }
      }
      if (!done) {
        if (_b(data, pos) != 34) { return _err_img("xpm: malformed declaration"); }
        let send = _scan_string(data, n, pos);
        if (send == -1) { return _err_img("xpm: unterminated string"); }
        if (send == -2) { return _err_img("xpm: invalid escape"); }
        if (send == -3) { return _err_img("xpm: invalid character"); }
        let s = _decode_string(data, pos + 1, send - 1);
        let dlen = s.len();
        parts.push(s);
        lens.push(dlen);
        pos = send;
        need_comma = true;
      }
    }
  }
  pos = pos + 1;
  pos = _skip_trivia(data, n, pos);
  if (pos < 0) { return _err_img("xpm: unclosed comment"); }
  if (pos >= n) { return _err_img("xpm: malformed declaration"); }
  if (_b(data, pos) != 59) { return _err_img("xpm: malformed declaration"); }
  pos = pos + 1;
  pos = _skip_trivia(data, n, pos);
  if (pos < 0) { return _err_img("xpm: unclosed comment"); }
  if (pos < n) { return _err_img("xpm: trailing tokens"); }

  if (parts.len() == 0) { return _err_img("xpm: missing header"); }
  let h: Str = parts[0];
  let hl: Int = lens[0];
  let hdr = _parse_header(h, hl);
  if (!hdr.ok) {
    let m: Str = hdr.err;
    return _err_img(m);
  }
  let width = hdr.width;
  let height = hdr.height;
  let ncolors = hdr.ncolors;
  let cpp = hdr.cpp;
  let has_hotspot = hdr.has_hotspot;
  let x_hot = hdr.x_hot;
  let y_hot = hdr.y_hot;

  if (parts.len() < 1 + ncolors) { return _err_img("xpm: missing color lines"); }
  if (parts.len() < 1 + ncolors + height) { return _err_img("xpm: missing pixel rows"); }
  if (parts.len() > 1 + ncolors + height) { return _err_img("xpm: trailing strings"); }

  let symbols = Vec[UInt8].new();
  let colors = Vec[Str].new();
  let color_lens = Vec[Int].new();
  var i = 0;
  while (i < ncolors) {
    let line: Str = parts[1 + i];
    let ll: Int = lens[1 + i];
    let cl = _parse_color_line(line, ll, cpp);
    if (!cl.ok) {
      let m: Str = cl.err;
      return _err_img(m);
    }
    let dup = _symbol_find(&symbols, i, cpp, line, 0);
    if (dup >= 0) { return _err_img("xpm: duplicate symbol"); }
    var j = 0;
    while (j < cpp) {
      let sb: UInt8 = string.byte_at(line, j);
      symbols.push(sb);
      j = j + 1;
    }
    let vstart = cl.value_start;
    let vlen = cl.value_len;
    let cv = _substr_str(line, vstart, vlen);
    colors.push(cv);
    color_lens.push(vlen);
    i = i + 1;
  }

  let pixels = Vec[Int].new();
  var y = 0;
  while (y < height) {
    let row: Str = parts[1 + ncolors + y];
    let rl: Int = lens[1 + ncolors + y];
    if (rl != width * cpp) { return _err_img("xpm: row length mismatch"); }
    var x = 0;
    while (x < width) {
      let k = _symbol_find(&symbols, ncolors, cpp, row, x * cpp);
      if (k < 0) { return _err_img("xpm: unknown symbol"); }
      pixels.push(k);
      x = x + 1;
    }
    y = y + 1;
  }

  let img = XpmImage{
    width: width;
    height: height;
    cpp: cpp;
    has_hotspot: has_hotspot;
    x_hot: x_hot;
    y_hot: y_hot;
    symbols: symbols;
    colors: colors;
    color_lens: color_lens;
    pixels: pixels;
  };
  return _ok_img(img);
}

// ---------------------------------------------------------------------------
// Public API: builder
// ---------------------------------------------------------------------------

// Validate an image and emit canonical XPM text for `name`:
//
//   /* XPM */\n
//   static char * <name>[] = {\n
//   "<w> <h> <ncolors> <cpp>[ <x_hot> <y_hot>]",\n
//   "<symbols>\tc <color>",\n          (one line per color)
//   "<row>",\n                          (one line per pixel row)
//   ...last row without a comma...\n
//   };\n
//
// The hot spot is emitted when `use_hot` is true. Symbol characters and
// color values are escaped as needed (`\\`, `\"`). `name` must be a C
// identifier; every parallel array must agree with the header fields; pixels
// must be in 0..ncolors-1; symbols must be valid and distinct; colors must be
// `#rrggbb` or a name token. Errors are the deterministic `xpm: ...` strings
// catalogued in SPEC.md.
fn _emit(name: Str, img: &XpmImage, use_hot: Bool, x_hot: Int, y_hot: Int) -> Result[Vec[UInt8], Str] {
  let colors: Vec[Str] = img.colors;
  let color_lens: Vec[Int] = img.color_lens;
  let symbols: Vec[UInt8] = img.symbols;
  let pixels: Vec[Int] = img.pixels;
  let ncolors = colors.len();
  let width = img.width;
  let height = img.height;
  let cpp = img.cpp;
  if (width <= 0) { return _err_bytes("xpm: invalid width"); }
  if (width > 1000000) { return _err_bytes("xpm: invalid width"); }
  if (height <= 0) { return _err_bytes("xpm: invalid height"); }
  if (height > 1000000) { return _err_bytes("xpm: invalid height"); }
  if (cpp < 1) { return _err_bytes("xpm: invalid cpp"); }
  if (cpp > 4) { return _err_bytes("xpm: invalid cpp"); }
  if (ncolors < 1) { return _err_bytes("xpm: invalid ncolors"); }
  if (ncolors > 4096) { return _err_bytes("xpm: invalid ncolors"); }
  if (color_lens.len() != ncolors) { return _err_bytes("xpm: color table size mismatch"); }
  if (symbols.len() != ncolors * cpp) { return _err_bytes("xpm: symbol pool size mismatch"); }
  if (pixels.len() != width * height) { return _err_bytes("xpm: pixel buffer size mismatch"); }
  if (!_name_ok(name)) { return _err_bytes("xpm: invalid name"); }
  if (use_hot) {
    if (x_hot < 0) { return _err_bytes("xpm: invalid hotspot"); }
    if (y_hot < 0) { return _err_bytes("xpm: invalid hotspot"); }
    if (x_hot > width) { return _err_bytes("xpm: invalid hotspot"); }
    if (y_hot > height) { return _err_bytes("xpm: invalid hotspot"); }
  }
  var i = 0;
  while (i < symbols.len()) {
    let sb: UInt8 = symbols[i];
    if (!_symbol_byte_ok((sb as Int) & 0xFF)) { return _err_bytes("xpm: invalid symbol"); }
    i = i + 1;
  }
  if (_pool_dup(&symbols, ncolors, cpp) >= 0) { return _err_bytes("xpm: duplicate symbol"); }
  i = 0;
  while (i < ncolors) {
    let cv: Str = colors[i];
    let cl: Int = color_lens[i];
    if (!_color_value_ok(cv, cl)) { return _err_bytes("xpm: malformed color value"); }
    i = i + 1;
  }
  i = 0;
  while (i < pixels.len()) {
    let k: Int = pixels[i];
    if (k < 0) { return _err_bytes("xpm: invalid pixel index"); }
    if (k >= ncolors) { return _err_bytes("xpm: invalid pixel index"); }
    i = i + 1;
  }

  let out = Vec[UInt8].new();
  _put_str(&mut out, "/* XPM */\nstatic char * ");
  _put_str(&mut out, name);
  _put_str(&mut out, "[] = {\n\"");
  _put_uint(&mut out, width);
  out.push(32 as UInt8);
  _put_uint(&mut out, height);
  out.push(32 as UInt8);
  _put_uint(&mut out, ncolors);
  out.push(32 as UInt8);
  _put_uint(&mut out, cpp);
  if (use_hot) {
    out.push(32 as UInt8);
    _put_uint(&mut out, x_hot);
    out.push(32 as UInt8);
    _put_uint(&mut out, y_hot);
  }
  _put_str(&mut out, "\",\n");
  i = 0;
  while (i < ncolors) {
    _put_str(&mut out, "\"");
    var j = 0;
    while (j < cpp) {
      let sb: UInt8 = symbols[i * cpp + j];
      _put_cbyte(&mut out, (sb as Int) & 0xFF);
      j = j + 1;
    }
    _put_str(&mut out, "\tc ");
    let cv: Str = colors[i];
    let cl: Int = color_lens[i];
    j = 0;
    while (j < cl) {
      let cb: UInt8 = string.byte_at(cv, j);
      _put_cbyte(&mut out, (cb as Int) & 0xFF);
      j = j + 1;
    }
    _put_str(&mut out, "\",\n");
    i = i + 1;
  }
  var y = 0;
  while (y < height) {
    _put_str(&mut out, "\"");
    var x = 0;
    while (x < width) {
      let k: Int = pixels[y * width + x];
      var j = 0;
      while (j < cpp) {
        let sb: UInt8 = symbols[k * cpp + j];
        _put_cbyte(&mut out, (sb as Int) & 0xFF);
        j = j + 1;
      }
      x = x + 1;
    }
    if (y + 1 < height) {
      _put_str(&mut out, "\",\n");
    } else {
      _put_str(&mut out, "\"\n");
    }
    y = y + 1;
  }
  _put_str(&mut out, "};\n");
  return _ok_bytes(out);
}

// Build canonical XPM text for `name` from an image, preserving its hot spot
// when it has one (see _emit for the layout and the error catalog).
pub fn xpm_build(name: Str, img: &XpmImage) -> Result[Vec[UInt8], Str] {
  return _emit(name, img, img.has_hotspot, img.x_hot, img.y_hot);
}

// Build canonical XPM text for `name` from an image, always emitting the hot
// spot (x_hot, y_hot), which must satisfy 0 <= x_hot <= width and
// 0 <= y_hot <= height. The image's own hot spot is ignored.
pub fn xpm_build_hotspot(name: Str, img: &XpmImage, x_hot: Int, y_hot: Int) -> Result[Vec[UInt8], Str] {
  return _emit(name, img, true, x_hot, y_hot);
}
