// XIOM -- xiom.pem: PEM armor codec (RFC 1421 headers, RFC 7468 block shape)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, nothing beyond xiom.std) PEM armor codec:
//   * pem_decode scans `-----BEGIN <label>-----` ... `-----END <label>-----`
//     blocks whose labels must match; optional RFC 1421 `Name: value` header
//     lines before the first blank line are preserved as raw lines; the body
//     is base64. LF and CRLF line endings are normalized; multiple blocks per
//     input are supported; empty lines outside blocks are ignored.
//   * pem_encode is the canonical emitter: BEGIN line, preserved headers
//     (blank line terminated), base64 wrapped at exactly 64 characters, LF
//     line endings, END line, trailing LF.
//   * The base64 decoder/encoder is self-contained and strict (RFC 4648
//     section 4): no whitespace inside a line; every body line except the
//     last must be exactly 64 characters and the last 1..64; '=' padding is
//     accepted but must be canonical (correct count, final run only, zero
//     unused trailing bits); the emitter always re-emits canonical padding.
//   * Flat block storage: parallel Vecs plus one header pool and one decoded
//     byte pool; each block addresses its headers and bytes by ranges. No
//     Vec[StructType].
//   * No DER/X.509 parsing, no encryption, no PKCS semantics: labels and
//     payload bytes are opaque to this codec. See SPEC.md.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec[StructType],
//     no Vec[fn] dispatch, no `match` in the library (if/elif chains).
//   * Ok/Err for Result[...] are constructed only in the tiny leaf helpers
//     _ok_doc/_err_doc/_ok_bytes/_err_bytes/_ok_str/_err_str; constructing
//     Results directly inside larger functions miscompiles.
//   * Every raw byte read via xiom.string.byte_at or a Vec[UInt8] index is
//     widened with `(x as Int) & 0xFF` before comparison or arithmetic.
//   * No bitwise shifts: base64 groups are split with multiplication,
//     division and modulo only.
//   * Str values read from Vec[Str] are bound to typed locals; this module
//     never compares Str values with `==` (only the byte-wise _str_eq), and
//     callers/tests use xiom.string.compare.str_compare (BUG 17).

module xiom.pem

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Canonical base64 body line width in characters: 64 (RFC 7468 section 2).
pub const PEM_LINE_WIDTH: Int = 64;

/// Largest accepted label, in bytes.
pub const PEM_MAX_LABEL: Int = 64;

// --------------------------------------------------
//  Parsed document
// --------------------------------------------------

/// Parsed PEM document: one logical slot per block, in input order.
///
/// `labels[i]` is the block label shared by its BEGIN and END lines. The
/// headers of block `i` are the `header_counts[i]` raw lines starting at
/// `headers[header_starts[i]]` (empty means no headers). The decoded body
/// bytes of block `i` are the `data_lens[i]` bytes starting at
/// `data[data_starts[i]]`. Fields are implementation details; callers use
/// the pem_* accessors below.
pub type PemDocument = {
  labels: Vec[Str];
  header_starts: Vec[Int];
  header_counts: Vec[Int];
  data_starts: Vec[Int];
  data_lens: Vec[Int];
  headers: Vec[Str];
  data: Vec[UInt8];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[PemDocument, Str].
fn _ok_doc(v: PemDocument) -> Result[PemDocument, Str] {
  return Ok(v);
}

// Err(m) for Result[PemDocument, Str].
fn _err_doc(m: Str) -> Result[PemDocument, Str] {
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

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Byte at `pos` of a Str widened to an Int (0..255); callers guarantee the
// bounds.
fn _tb(text: Str, pos: Int) -> Int {
  return (string.byte_at(text, pos) as Int) & 0xFF;
}

// Byte at `pos` of a byte vector widened to an Int (0..255); callers
// guarantee the bounds.
fn _vb(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Append the bytes of `s`.
fn _push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Append the bytes of `v`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// True when `a` and `b` are byte-for-byte equal. Never uses `==` on Str
// values (BUG 17 discipline).
fn _str_eq(a: Str, b: Str) -> Bool {
  let n = a.len();
  if n != b.len() {
    return false;
  }
  var i = 0;
  while i < n {
    if _tb(a, i) != _tb(b, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Index of the next LF at or after `pos`, or the text length when there is
// none (a final line without a terminator).
fn _line_end(text: Str, pos: Int) -> Int {
  let n = text.len();
  var i = pos;
  while i < n {
    if _tb(text, i) == 10 {
      return i;
    }
    i = i + 1;
  }
  return n;
}

// --------------------------------------------------
//  Base64 (self-contained; RFC 4648 section 4)
// --------------------------------------------------

/// The RFC 4648 standard base64 alphabet (64 characters).
/// Returns: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".
/// Error case: none.
/// Complexity: O(1).
pub fn pem_base64_alphabet() -> Str {
  return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
}

// Base64 digit value (0..63) of one encoded byte; -1 when the byte is not an
// alphabet character. Decoding is case-sensitive: 'A'..'Z' are 0..25,
// 'a'..'z' are 26..51, '0'..'9' are 52..61, '+' is 62 and '/' is 63. The pad
// byte '=' (61) is handled by the caller, not here.
fn _b64_value(b: Int) -> Int {
  if b >= 65 && b <= 90 {
    return b - 65;
  }
  if b >= 97 && b <= 122 {
    return b - 97 + 26;
  }
  if b >= 48 && b <= 57 {
    return b - 48 + 52;
  }
  if b == 43 {
    return 62;
  }
  if b == 47 {
    return 63;
  }
  return -1;
}

// --------------------------------------------------
//  Marker and header grammar
// --------------------------------------------------

// True for a label character: printable US-ASCII except space and
// hyphen-minus (RFC 7468 labelchar).
fn _labelchar(b: Int) -> Bool {
  if b >= 33 && b <= 44 {
    return true;
  }
  if b >= 46 && b <= 126 {
    return true;
  }
  return false;
}

// True when the bytes [ls, le) form a valid label: 1..PEM_MAX_LABEL bytes of
// labelchar with single interior spaces as separators (no leading, trailing
// or consecutive spaces, no hyphen-minus).
fn _label_ok_at(text: Str, ls: Int, le: Int) -> Bool {
  let ln = le - ls;
  if ln < 1 || ln > PEM_MAX_LABEL {
    return false;
  }
  var i = ls;
  while i < le {
    let b = _tb(text, i);
    if b == 32 {
      if i == ls || i + 1 >= le {
        return false;
      }
      if _tb(text, i - 1) == 32 || _tb(text, i + 1) == 32 {
        return false;
      }
    } elif !_labelchar(b) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when the line [start, end) begins with five hyphen-minuses.
fn _dash5(text: Str, start: Int) -> Bool {
  var i = 0;
  while i < 5 {
    if _tb(text, start + i) != 45 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Classify a line [start, end): 0 = not a marker-like line (no five leading
// hyphens), 1 = valid BEGIN marker, 2 = valid END marker, -1 = starts with
// five hyphens but is not a well-formed marker (wrong keyword, missing
// separating space, wrong trailing dashes, or an invalid label).
fn _marker_kind(text: Str, start: Int, end: Int) -> Int {
  if end - start < 5 {
    return 0;
  }
  if !_dash5(text, start) {
    return 0;
  }
  if end - start < 15 {
    return -1;
  }
  let w0 = _tb(text, start + 5);
  let w1 = _tb(text, start + 6);
  let w2 = _tb(text, start + 7);
  var label_start = -1;
  if w0 == 66 && w1 == 69 && w2 == 71 {
    if _tb(text, start + 8) != 73 || _tb(text, start + 9) != 78 {
      return -1;
    }
    if _tb(text, start + 10) != 32 {
      return -1;
    }
    label_start = start + 11;
  } elif w0 == 69 && w1 == 78 && w2 == 68 {
    if _tb(text, start + 8) != 32 {
      return -1;
    }
    label_start = start + 9;
  } else {
    return -1;
  }
  var k = end - 5;
  while k < end {
    if _tb(text, k) != 45 {
      return -1;
    }
    k = k + 1;
  }
  if !_label_ok_at(text, label_start, end - 5) {
    return -1;
  }
  if label_start == start + 11 {
    return 1;
  }
  return 2;
}

// The label of a valid marker line [start, end).
fn _marker_label(text: Str, start: Int, end: Int) -> Str {
  if _marker_kind(text, start, end) == 1 {
    return string.str_slice(text, start + 11, end - 5);
  }
  return string.str_slice(text, start + 9, end - 5);
}

// True when the line [start, end) has RFC 1421 `Name: value` shape: a
// non-empty printable name (no space, no colon) followed by ':' and a value
// of printable bytes (spaces allowed, may be empty).
fn _is_header_line(text: Str, start: Int, end: Int) -> Bool {
  if end - start < 2 {
    return false;
  }
  var colon = -1;
  var i = start;
  while i < end {
    if _tb(text, i) == 58 {
      colon = i;
      break;
    }
    i = i + 1;
  }
  if colon < 0 || colon == start {
    return false;
  }
  i = start;
  while i < colon {
    let b = _tb(text, i);
    if b < 33 || b > 126 {
      return false;
    }
    i = i + 1;
  }
  i = colon + 1;
  while i < end {
    let b = _tb(text, i);
    if b < 32 || b > 126 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Base64 body decode / emit
// --------------------------------------------------

// Decode the base64 characters [start, end) of `chars` to bytes. The
// character count must be a multiple of 4; '=' may appear only in the final
// run, with the exact count implied by the final group; the unused low bits
// of a padded final group must be zero. Empty input yields Ok(empty).
//
// Err("pem: bad padding") when the length is not a multiple of 4, '=' is not
// the exact final run, or a group is left incomplete;
// Err("pem: invalid base64 character") for a byte outside the alphabet;
// Err("pem: non-canonical trailing bits") when a padded final group carries
// non-zero unused bits.
fn _b64_decode_range(chars: &Vec[UInt8], start: Int, end: Int) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let n = end - start;
  if n == 0 {
    return _ok_bytes(out);
  }
  if n % 4 != 0 {
    return _err_bytes("pem: bad padding");
  }
  var first_pad = -1;
  var k = 0;
  while k < n {
    let b = _vb(chars, start + k);
    if b == 61 {
      first_pad = k;
      break;
    }
    if _b64_value(b) < 0 {
      return _err_bytes("pem: invalid base64 character");
    }
    k = k + 1;
  }
  var d = n;
  if first_pad >= 0 {
    d = first_pad;
    var j = first_pad;
    while j < n {
      if _vb(chars, start + j) != 61 {
        return _err_bytes("pem: bad padding");
      }
      j = j + 1;
    }
    let p = n - d;
    if p > 2 {
      return _err_bytes("pem: bad padding");
    }
    if p == 1 && d % 4 != 3 {
      return _err_bytes("pem: bad padding");
    }
    if p == 2 && d % 4 != 2 {
      return _err_bytes("pem: bad padding");
    }
  }
  var acc = 0;
  var count = 0;
  k = 0;
  while k < d {
    acc = acc * 64 + _b64_value(_vb(chars, start + k));
    count = count + 1;
    if count == 4 {
      out.push((acc / 65536) as UInt8);
      out.push(((acc / 256) % 256) as UInt8);
      out.push((acc % 256) as UInt8);
      acc = 0;
      count = 0;
    }
    k = k + 1;
  }
  if count == 2 {
    if acc % 16 != 0 {
      return _err_bytes("pem: non-canonical trailing bits");
    }
    out.push((acc / 16) as UInt8);
  } elif count == 3 {
    if acc % 4 != 0 {
      return _err_bytes("pem: non-canonical trailing bits");
    }
    out.push((acc / 1024) as UInt8);
    out.push(((acc / 4) % 256) as UInt8);
  } elif count != 0 {
    return _err_bytes("pem: bad padding");
  }
  return _ok_bytes(out);
}

// Emit `len` bytes of `src` starting at `start` as canonical base64 into
// `out`: 4 characters per 3-byte group, '=' padded final group, LF after
// every PEM_LINE_WIDTH characters and after a non-empty final partial line.
// Empty input emits nothing.
fn _b64_emit_wrapped(src: &Vec[UInt8], start: Int, len: Int, out: &mut Vec[UInt8]) {
  let alpha = pem_base64_alphabet();
  var col = 0;
  var i = 0;
  while i + 3 <= len {
    let b0 = _vb(src, start + i);
    let b1 = _vb(src, start + i + 1);
    let b2 = _vb(src, start + i + 2);
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16 + b1 / 16));
    out.push(string.byte_at(alpha, (b1 % 16) * 4 + b2 / 64));
    out.push(string.byte_at(alpha, b2 % 64));
    col = col + 4;
    if col == PEM_LINE_WIDTH {
      out.push(10 as UInt8);
      col = 0;
    }
    i = i + 3;
  }
  let rem = len - i;
  if rem == 1 {
    let b0 = _vb(src, start + i);
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16));
    out.push(61 as UInt8);
    out.push(61 as UInt8);
    col = col + 4;
  } elif rem == 2 {
    let b0 = _vb(src, start + i);
    let b1 = _vb(src, start + i + 1);
    out.push(string.byte_at(alpha, b0 / 4));
    out.push(string.byte_at(alpha, (b0 % 4) * 16 + b1 / 16));
    out.push(string.byte_at(alpha, (b1 % 16) * 4));
    out.push(61 as UInt8);
    col = col + 4;
  }
  if col > 0 {
    out.push(10 as UInt8);
  }
}

// --------------------------------------------------
//  Decode
// --------------------------------------------------

/// Parse PEM armor text into a flat PemDocument.
///
/// Params: text - the armor text; its bytes are read as US-ASCII.
/// Returns: Ok(document) listing every block in input order. A line ends at
/// LF or at end of input; one CR immediately before an LF is removed (CRLF
/// normalization). Lines outside blocks must be empty (ignored) or a valid
/// BEGIN marker. Inside a block: a first blank line ends the optional header
/// section, `Name: value` lines before it are preserved raw, and the
/// remaining lines are the base64 body. Every body line except the last must
/// be exactly PEM_LINE_WIDTH (64) characters; the last carries 1..64; a body
/// with no lines decodes to empty bytes. Empty input (or only empty lines)
/// yields Ok with zero blocks.
/// Error case: Err("pem: ...") on the first violation, from the catalog in
/// SPEC.md: unterminated block, label mismatch, invalid base64 character,
/// bad padding, non-canonical trailing bits, text outside blocks, malformed
/// block marker, nested block not allowed, blank line in body, bad body line
/// length, header after body, header section not terminated.
/// Complexity: O(text.len()).
pub fn pem_decode(text: Str) -> Result[PemDocument, Str] {
  var labels = Vec[Str].new();
  var header_starts = Vec[Int].new();
  var header_counts = Vec[Int].new();
  var data_starts = Vec[Int].new();
  var data_lens = Vec[Int].new();
  var headers = Vec[Str].new();
  var data = Vec[UInt8].new();

  let n = text.len();
  var pos = 0;
  var in_block = false;
  var cur_label: Str = "";
  var cur_header_start = 0;
  var cur_header_count = 0;
  var cur_body_start = 0;
  var body_started = false;
  var prev_body_len = -1;
  var body_chars = Vec[UInt8].new();

  while pos < n {
    let e = _line_end(text, pos);
    var ce = e;
    if e < n && ce > pos && _tb(text, ce - 1) == 13 {
      ce = ce - 1;
    }

    if !in_block {
      if ce > pos {
        let kind = _marker_kind(text, pos, ce);
        if kind == 1 {
          in_block = true;
          cur_label = _marker_label(text, pos, ce);
          cur_header_start = headers.len();
          cur_header_count = 0;
          cur_body_start = body_chars.len();
          body_started = false;
          prev_body_len = -1;
        } elif kind == -1 {
          return _err_doc("pem: malformed block marker");
        } else {
          return _err_doc("pem: text outside blocks");
        }
      }
    } else {
      let kind = _marker_kind(text, pos, ce);
      if kind != 0 {
        if kind == 1 {
          return _err_doc("pem: nested block not allowed");
        }
        if kind == -1 {
          return _err_doc("pem: malformed block marker");
        }
        let end_label: Str = string.str_slice(text, pos + 9, ce - 5);
        if !_str_eq(cur_label, end_label) {
          return _err_doc("pem: label mismatch");
        }
        if cur_header_count > 0 && !body_started {
          return _err_doc("pem: header section not terminated");
        }
        let bend: Int = body_chars.len();
        let dec = _b64_decode_range(&body_chars, cur_body_start, bend);
        if !dec.is_ok {
          return _err_doc(dec.error);
        }
        let decoded: Vec[UInt8] = dec.value;
        labels.push(cur_label);
        header_starts.push(cur_header_start);
        header_counts.push(cur_header_count);
        data_starts.push(data.len());
        data_lens.push(decoded.len());
        _push_bytes(&mut data, &decoded);
        in_block = false;
      } elif ce == pos {
        if !body_started {
          body_started = true;
        } else {
          return _err_doc("pem: blank line in body");
        }
      } else {
        if _is_header_line(text, pos, ce) {
          if body_started {
            return _err_doc("pem: header after body");
          }
          let hl: Str = string.str_slice(text, pos, ce);
          headers.push(hl);
          cur_header_count = cur_header_count + 1;
        } elif body_started || cur_header_count == 0 {
          body_started = true;
          let llen = ce - pos;
          if prev_body_len >= 0 && prev_body_len != PEM_LINE_WIDTH {
            return _err_doc("pem: bad body line length");
          }
          if llen > PEM_LINE_WIDTH {
            return _err_doc("pem: bad body line length");
          }
          var k = pos;
          while k < ce {
            let b = _tb(text, k);
            if b != 61 && _b64_value(b) < 0 {
              return _err_doc("pem: invalid base64 character");
            }
            body_chars.push(b as UInt8);
            k = k + 1;
          }
          prev_body_len = llen;
        } else {
          return _err_doc("pem: header section not terminated");
        }
      }
    }
    pos = e + 1;
  }

  if in_block {
    return _err_doc("pem: unterminated block");
  }
  let doc = PemDocument{
    labels: labels;
    header_starts: header_starts;
    header_counts: header_counts;
    data_starts: data_starts;
    data_lens: data_lens;
    headers: headers;
    data: data;
  };
  return _ok_doc(doc);
}

// --------------------------------------------------
//  Encode
// --------------------------------------------------

/// Emit the canonical armor text of a PemDocument.
///
/// Params: doc - a document, normally one returned by pem_decode.
/// Returns: Ok(text) with one block per document slot: the BEGIN line, the
/// preserved header lines and a terminating blank line when the block has
/// headers, the body as canonical base64 wrapped at exactly 64 characters
/// per line (LF endings; the last line may be shorter; an empty body emits
/// no body line), then the END line and one trailing LF. Blocks follow each
/// other directly. Empty documents yield "".
/// Error case: Err("pem: invalid label") when a stored label would not be
/// accepted by pem_decode; Err("pem: malformed document") when the parallel
/// vectors disagree in length, a header or data range does not fit its pool,
/// or a stored header line lacks `Name: value` shape.
/// Complexity: O(total header + data bytes).
pub fn pem_encode(doc: &PemDocument) -> Result[Str, Str] {
  let count: Int = doc.labels.len();
  if doc.header_starts.len() != count || doc.header_counts.len() != count {
    return _err_str("pem: malformed document");
  }
  if doc.data_starts.len() != count || doc.data_lens.len() != count {
    return _err_str("pem: malformed document");
  }
  var i = 0;
  while i < count {
    let lb: Str = doc.labels[i];
    if !_label_ok_at(lb, 0, lb.len()) {
      return _err_str("pem: invalid label");
    }
    let hs: Int = doc.header_starts[i];
    let hc: Int = doc.header_counts[i];
    let ds: Int = doc.data_starts[i];
    let dl: Int = doc.data_lens[i];
    if hs < 0 || hc < 0 || hs + hc > doc.headers.len() {
      return _err_str("pem: malformed document");
    }
    if ds < 0 || dl < 0 || ds + dl > doc.data.len() {
      return _err_str("pem: malformed document");
    }
    var j = 0;
    while j < hc {
      let hl: Str = doc.headers[hs + j];
      if !_is_header_line(hl, 0, hl.len()) {
        return _err_str("pem: malformed document");
      }
      j = j + 1;
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  i = 0;
  while i < count {
    let lb: Str = doc.labels[i];
    _push_str(&mut out, "-----BEGIN ");
    _push_str(&mut out, lb);
    _push_str(&mut out, "-----");
    out.push(10 as UInt8);
    let hs: Int = doc.header_starts[i];
    let hc: Int = doc.header_counts[i];
    var j = 0;
    while j < hc {
      let hl: Str = doc.headers[hs + j];
      _push_str(&mut out, hl);
      out.push(10 as UInt8);
      j = j + 1;
    }
    if hc > 0 {
      out.push(10 as UInt8);
    }
    let ds: Int = doc.data_starts[i];
    let dl: Int = doc.data_lens[i];
    _b64_emit_wrapped(&doc.data, ds, dl, &mut out);
    _push_str(&mut out, "-----END ");
    _push_str(&mut out, lb);
    _push_str(&mut out, "-----");
    out.push(10 as UInt8);
    i = i + 1;
  }
  let text: Str = builder.sb_to_str(&out);
  return _ok_str(text);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of blocks in `d`. Complexity: O(1).
pub fn pem_block_count(d: &PemDocument) -> Int {
  return d.labels.len();
}

/// Label of block `i`, or "" when `i` is out of range. The result is read
/// from a Vec[Str]: callers must compare it with
/// xiom.string.compare.str_compare rather than `==`. Complexity: O(1).
pub fn pem_label(d: &PemDocument, i: Int) -> Str {
  if i < 0 || i >= d.labels.len() {
    return "";
  }
  let lb: Str = d.labels[i];
  return lb;
}

/// Number of raw header lines of block `i`, or 0 when `i` is out of range.
/// Complexity: O(1).
pub fn pem_header_count(d: &PemDocument, i: Int) -> Int {
  if i < 0 || i >= d.header_counts.len() {
    return 0;
  }
  let hc: Int = d.header_counts[i];
  if hc < 0 {
    return 0;
  }
  return hc;
}

/// Raw header line `j` of block `i` (no terminator), or "" when either index
/// is out of range. The result is read from a Vec[Str]: compare it with
/// xiom.string.compare.str_compare. Complexity: O(1).
pub fn pem_header_line(d: &PemDocument, i: Int, j: Int) -> Str {
  if i < 0 || i >= d.header_counts.len() || i >= d.header_starts.len() {
    return "";
  }
  let hs: Int = d.header_starts[i];
  let hc: Int = d.header_counts[i];
  if j < 0 || j >= hc || hs < 0 || hs + hc > d.headers.len() {
    return "";
  }
  let hl: Str = d.headers[hs + j];
  return hl;
}

/// Decoded body length in bytes of block `i`; -1 when `i` is out of range.
/// Complexity: O(1).
pub fn pem_decoded_len(d: &PemDocument, i: Int) -> Int {
  if i < 0 || i >= d.data_lens.len() {
    return -1;
  }
  let dl: Int = d.data_lens[i];
  return dl;
}

/// Copy of the decoded body bytes of block `i`, or an empty vector when `i`
/// is out of range. Complexity: O(len).
pub fn pem_decoded_bytes(d: &PemDocument, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= d.data_lens.len() || i >= d.data_starts.len() {
    return out;
  }
  let off: Int = d.data_starts[i];
  let len: Int = d.data_lens[i];
  if off < 0 || len < 0 || off + len > d.data.len() {
    return out;
  }
  var k = 0;
  while k < len {
    out.push(d.data[off + k]);
    k = k + 1;
  }
  return out;
}

/// The canonical body line width in characters: 64 (PEM_LINE_WIDTH).
/// Complexity: O(1).
pub fn pem_line_width() -> Int {
  return PEM_LINE_WIDTH;
}
