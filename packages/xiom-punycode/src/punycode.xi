// XIOM -- xiom.punycode: RFC 3492 Punycode for IDN labels
// Port task: add a real, tested, pure-XIOM punycode package (no FFI) that
// encodes and decodes domain labels without any external table.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// What is covered (see SPEC.md for the algorithm summary, the digit alphabet,
// the error catalog and the test plan):
//   * punycode_encode_label: Unicode label -> Punycode WITHOUT the "xn--"
//     prefix; all-ASCII labels are returned unchanged; the RFC 3492
//     bootstring algorithm (base 36, bias adaptation) uses an inline digit
//     alphabet (a-z = 0..25, 0-9 = 26..35).
//   * punycode_decode_label: Punycode WITHOUT the "xn--" prefix -> Unicode
//     label; digits are case-insensitive; basic code points are copied
//     verbatim; out-of-range and overflowing digit runs are rejected.
//   * punycode_to_ascii / punycode_to_unicode: dot-separated domains; ASCII
//     labels pass through, non-ASCII labels gain the "xn--" prefix, "xn--"
//     labels decode case-insensitively and empty labels are preserved.
//   * punycode_is_ascii_label: true when every byte is < 0x80.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas.
//   * Every raw byte read through xiom.string.byte_at is widened as
//     `(byte_at(s, i) as Int) & 0xFF` before comparisons or arithmetic.
//   * Ok/Err values are constructed only in the tiny leaf helpers _pc_ok /
//     _pc_err; no Ok/Err literal appears in a larger function.
//   * No `==` on Str values: prefix checks compare bytes; the tests route
//     every string comparison through xiom.string.compare.str_compare.
//   * Code point lists are Vec[Int] (no Vec[StructType]); output is
//     accumulated in Vec[UInt8] and materialized once per result with
//     xiom.string.builder.sb_to_str.
//
// This module implements RFC 3492 only. It performs no IDNA mapping,
// normalization or validation (see README "Limitations").

module xiom.punycode

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  RFC 3492 constants
// --------------------------------------------------

const _PC_BASE: Int = 36;
const _PC_TMIN: Int = 1;
const _PC_TMAX: Int = 26;
const _PC_SKEW: Int = 38;
const _PC_DAMP: Int = 700;
const _PC_INITIAL_BIAS: Int = 72;
const _PC_INITIAL_N: Int = 128;
const _PC_MAXINT: Int = 2147483647;
const _PC_DASH: Int = 45;
const _PC_DOT: Int = 46;
const _PC_X: Int = 120;
const _PC_N: Int = 110;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Str, Str].
fn _pc_ok(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _pc_err(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Bias adaptation and thresholds (RFC 3492 section 6.1)
// --------------------------------------------------

// Bias adaptation function: adapt(delta, numpoints, firsttime).
fn _pc_adapt(delta_in: Int, numpoints: Int, firsttime: Bool) -> Int {
  var delta = delta_in;
  if firsttime {
    delta = delta / _PC_DAMP;
  } else {
    delta = delta / 2;
  }
  delta = delta + delta / numpoints;
  var k = 0;
  while delta > ((_PC_BASE - _PC_TMIN) * _PC_TMAX) / 2 {
    delta = delta / (_PC_BASE - _PC_TMIN);
    k = k + _PC_BASE;
  }
  return k + ((_PC_BASE - _PC_TMIN + 1) * delta) / (delta + _PC_SKEW);
}

// Threshold t for loop counter k and current bias.
fn _pc_bias_t(k: Int, bias: Int) -> Int {
  if k <= bias {
    return _PC_TMIN;
  }
  if k >= bias + _PC_TMAX {
    return _PC_TMAX;
  }
  return k - bias;
}

// --------------------------------------------------
//  Digit alphabet (RFC 3492 section 5)
// --------------------------------------------------

// Digit character byte for a value 0..35: a-z then 0-9.
fn _pc_digit_char(d: Int) -> Int {
  if d < 26 {
    return 97 + d;
  }
  return 48 + (d - 26);
}

// Digit value of a byte: a-z/A-Z = 0..25, 0-9 = 26..35; -1 for any other
// byte. Upper- and lowercase digits decode to the same value (RFC 3492
// section 5).
fn _pc_digit_value(b: Int) -> Int {
  if b >= 97 && b <= 122 {
    return b - 97;
  }
  if b >= 65 && b <= 90 {
    return b - 65;
  }
  if b >= 48 && b <= 57 {
    return b - 48 + 26;
  }
  return -1;
}

// --------------------------------------------------
//  UTF-8 (RFC 3629, manual and strict)
// --------------------------------------------------

// Sequence length in bytes for a valid lead byte; 0 for an invalid lead.
fn _pc_seq_len(b0: Int) -> Int {
  if b0 < 0x80 {
    return 1;
  }
  if (b0 & 0xE0) == 0xC0 {
    return 2;
  }
  if (b0 & 0xF0) == 0xE0 {
    return 3;
  }
  if (b0 & 0xF8) == 0xF0 {
    return 4;
  }
  return 0;
}

// Decode one UTF-8 code point at byte offset `pos` of `s`.
// Returns the code point (>= 0), or -1 when the bytes do not form a valid
// sequence: bad lead/continuation bytes, truncated sequences, overlong
// encodings, surrogates U+D800-U+DFFF and code points above U+10FFFF.
fn _pc_decode(s: Str, pos: Int) -> Int {
  let n = s.len();
  let b0: Int = (string.byte_at(s, pos) as Int) & 0xFF;
  if b0 < 0x80 {
    return b0;
  }
  if (b0 & 0xE0) == 0xC0 {
    if pos + 2 > n {
      return -1;
    }
    let b1: Int = (string.byte_at(s, pos + 1) as Int) & 0xFF;
    if (b1 & 0xC0) != 0x80 {
      return -1;
    }
    let cp: Int = ((b0 & 0x1F) << 6) | (b1 & 0x3F);
    if cp < 0x80 {
      return -1;
    }
    return cp;
  }
  if (b0 & 0xF0) == 0xE0 {
    if pos + 3 > n {
      return -1;
    }
    let b1: Int = (string.byte_at(s, pos + 1) as Int) & 0xFF;
    let b2: Int = (string.byte_at(s, pos + 2) as Int) & 0xFF;
    if (b1 & 0xC0) != 0x80 {
      return -1;
    }
    if (b2 & 0xC0) != 0x80 {
      return -1;
    }
    let cp: Int = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);
    if cp < 0x800 {
      return -1;
    }
    if cp >= 0xD800 && cp <= 0xDFFF {
      return -1;
    }
    return cp;
  }
  if (b0 & 0xF8) == 0xF0 {
    if pos + 4 > n {
      return -1;
    }
    let b1: Int = (string.byte_at(s, pos + 1) as Int) & 0xFF;
    let b2: Int = (string.byte_at(s, pos + 2) as Int) & 0xFF;
    let b3: Int = (string.byte_at(s, pos + 3) as Int) & 0xFF;
    if (b1 & 0xC0) != 0x80 {
      return -1;
    }
    if (b2 & 0xC0) != 0x80 {
      return -1;
    }
    if (b3 & 0xC0) != 0x80 {
      return -1;
    }
    let cp: Int = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
    if cp < 0x10000 {
      return -1;
    }
    if cp > 0x10FFFF {
      return -1;
    }
    return cp;
  }
  return -1;
}

// Append one code point to `out` as UTF-8 bytes.
fn _pc_push_cp(out: &mut Vec[UInt8], cp: Int) {
  if cp <= 0x7F {
    out.push(cp as UInt8);
  } elif cp <= 0x7FF {
    out.push((0xC0 | (cp >> 6)) as UInt8);
    out.push((0x80 | (cp & 0x3F)) as UInt8);
  } elif cp <= 0xFFFF {
    out.push((0xE0 | (cp >> 12)) as UInt8);
    out.push((0x80 | ((cp >> 6) & 0x3F)) as UInt8);
    out.push((0x80 | (cp & 0x3F)) as UInt8);
  } else {
    out.push((0xF0 | (cp >> 18)) as UInt8);
    out.push((0x80 | ((cp >> 12) & 0x3F)) as UInt8);
    out.push((0x80 | ((cp >> 6) & 0x3F)) as UInt8);
    out.push((0x80 | (cp & 0x3F)) as UInt8);
  }
}

// Materialize a code point list as a fresh UTF-8 Str.
fn _pc_cps_to_str(cps: &Vec[Int]) -> Str {
  var out = Vec[UInt8].new();
  let n = cps.len();
  var i = 0;
  while i < n {
    let cp: Int = cps[i];
    _pc_push_cp(&mut out, cp);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Encoder (RFC 3492 section 6.3)
// --------------------------------------------------

// Bootstring-encode a non-empty, already-validated code point list.
fn _pc_encode_cps(cps: &Vec[Int]) -> Result[Str, Str] {
  let n = cps.len();
  var basic = 0;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let cp: Int = cps[i];
    if cp < 0x80 {
      out.push(cp as UInt8);
      basic = basic + 1;
    }
    i = i + 1;
  }
  if basic > 0 {
    out.push(_PC_DASH as UInt8);
  }
  var h = basic;
  var nn = _PC_INITIAL_N;
  var delta = 0;
  var bias = _PC_INITIAL_BIAS;
  while h < n {
    var m = 0x110000;
    var j = 0;
    while j < n {
      let cp: Int = cps[j];
      if cp >= nn && cp < m {
        m = cp;
      }
      j = j + 1;
    }
    let step: Int = m - nn;
    if step > 0 {
      let cap: Int = _PC_MAXINT - delta;
      if cap < 0 {
        return _pc_err("punycode: overflow");
      }
      if step > cap / (h + 1) {
        return _pc_err("punycode: overflow");
      }
    }
    delta = delta + step * (h + 1);
    nn = m;
    j = 0;
    while j < n {
      let cp: Int = cps[j];
      if cp < nn {
        delta = delta + 1;
      }
      if cp == nn {
        var q = delta;
        var k = _PC_BASE;
        loop {
          let t: Int = _pc_bias_t(k, bias);
          if q < t {
            break;
          }
          out.push(_pc_digit_char(t + (q - t) % (_PC_BASE - t)) as UInt8);
          q = (q - t) / (_PC_BASE - t);
          k = k + _PC_BASE;
        }
        out.push(_pc_digit_char(q) as UInt8);
        bias = _pc_adapt(delta, h + 1, h == basic);
        delta = 0;
        h = h + 1;
      }
      j = j + 1;
    }
    delta = delta + 1;
    nn = nn + 1;
  }
  return _pc_ok(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Decoder (RFC 3492 section 6.2)
// --------------------------------------------------

// Bootstring-decode `label` (the part after "xn--") into a UTF-8 Str.
// The last '-' separates the verbatim basic code points from the digits;
// without a '-' the whole input is a digit run (e.g. "r8jz45g").
fn _pc_decode_label(label: Str) -> Result[Str, Str] {
  let n = label.len();
  var out = Vec[Int].new();
  var basic_end = -1;
  var scan = 0;
  while scan < n {
    let b: Int = (string.byte_at(label, scan) as Int) & 0xFF;
    if b == _PC_DASH {
      basic_end = scan;
    }
    scan = scan + 1;
  }
  var pos = 0;
  if basic_end >= 0 {
    var k = 0;
    while k < basic_end {
      let b: Int = (string.byte_at(label, k) as Int) & 0xFF;
      if b >= 0x80 {
        return _pc_err("punycode: non-ASCII basic code point");
      }
      out.push(b);
      k = k + 1;
    }
    pos = basic_end + 1;
  }
  var cp = _PC_INITIAL_N;
  var bias = _PC_INITIAL_BIAS;
  var iacc = 0;
  while pos < n {
    let oldi = iacc;
    var w = 1;
    var kk = _PC_BASE;
    loop {
      if pos >= n {
        return _pc_err("punycode: truncated encoded data");
      }
      let b: Int = (string.byte_at(label, pos) as Int) & 0xFF;
      let digit: Int = _pc_digit_value(b);
      if digit < 0 {
        return _pc_err("punycode: invalid digit");
      }
      pos = pos + 1;
      if digit > 0 {
        let cap: Int = _PC_MAXINT - iacc;
        if cap < 0 {
          return _pc_err("punycode: overflow");
        }
        if w > cap / digit {
          return _pc_err("punycode: overflow");
        }
      }
      iacc = iacc + digit * w;
      let t: Int = _pc_bias_t(kk, bias);
      if digit < t {
        break;
      }
      let factor: Int = _PC_BASE - t;
      if w > _PC_MAXINT / factor {
        return _pc_err("punycode: overflow");
      }
      w = w * factor;
      kk = kk + _PC_BASE;
    }
    let out_len: Int = out.len() + 1;
    bias = _pc_adapt(iacc - oldi, out_len, oldi == 0);
    cp = cp + iacc / out_len;
    if cp > 0x10FFFF {
      return _pc_err("punycode: code point out of range");
    }
    iacc = iacc % out_len;
    var rebuilt = Vec[Int].new();
    var idx = 0;
    while idx < iacc {
      let v: Int = out[idx];
      rebuilt.push(v);
      idx = idx + 1;
    }
    rebuilt.push(cp);
    while idx < out.len() {
      let v2: Int = out[idx];
      rebuilt.push(v2);
      idx = idx + 1;
    }
    out = rebuilt;
    iacc = iacc + 1;
  }
  return _pc_ok(_pc_cps_to_str(&out));
}

// --------------------------------------------------
//  Domain helpers
// --------------------------------------------------

// Split on '.' preserving empty labels (including a trailing one).
fn _pc_split_domain(domain: Str) -> Vec[Str] {
  var parts = Vec[Str].new();
  let n = domain.len();
  var start = 0;
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(domain, i) as Int) & 0xFF;
    if b == _PC_DOT {
      parts.push(string.str_slice(domain, start, i));
      start = i + 1;
    }
    i = i + 1;
  }
  parts.push(string.str_slice(domain, start, n));
  return parts;
}

// True when `b` is `lower` or its uppercase ASCII form.
fn _pc_eq_ci(b: Int, lower: Int) -> Bool {
  var x = b;
  if x >= 65 && x <= 90 {
    x = x + 32;
  }
  return x == lower;
}

// True when `s` begins with "xn--" (ASCII case-insensitive).
fn _pc_has_xn_prefix(s: Str) -> Bool {
  if s.len() < 4 {
    return false;
  }
  let b0: Int = (string.byte_at(s, 0) as Int) & 0xFF;
  let b1: Int = (string.byte_at(s, 1) as Int) & 0xFF;
  let b2: Int = (string.byte_at(s, 2) as Int) & 0xFF;
  let b3: Int = (string.byte_at(s, 3) as Int) & 0xFF;
  if !_pc_eq_ci(b0, _PC_X) {
    return false;
  }
  if !_pc_eq_ci(b1, _PC_N) {
    return false;
  }
  if b2 != _PC_DASH {
    return false;
  }
  if b3 != _PC_DASH {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// True when every byte of `label` is an ASCII byte (< 0x80).
/// Params: label - the label text to inspect.
/// Returns: true when no byte is >= 0x80; the empty label is ASCII.
/// Error case: none.
/// Complexity: O(label.len()).
pub fn punycode_is_ascii_label(label: Str) -> Bool {
  let n = label.len();
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(label, i) as Int) & 0xFF;
    if b >= 128 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Encode one Unicode label to Punycode WITHOUT the "xn--" prefix.
/// Params: label - the Unicode label (no dots required by this function).
/// Returns: Ok(punycode) for a label with non-ASCII code points;
/// Ok(label) unchanged when every byte is ASCII (including "").
/// Error case: Err("punycode: invalid UTF-8") for a byte sequence that is
/// not well-formed UTF-8 (RFC 3629); Err("punycode: overflow") when the
/// arithmetic would exceed _PC_MAXINT.
/// Complexity: O(label.len()^2) worst case.
pub fn punycode_encode_label(label: Str) -> Result[Str, Str] {
  if punycode_is_ascii_label(label) {
    return _pc_ok(label);
  }
  var cps = Vec[Int].new();
  let n = label.len();
  var i = 0;
  while i < n {
    let b0: Int = (string.byte_at(label, i) as Int) & 0xFF;
    if b0 < 0x80 {
      cps.push(b0);
      i = i + 1;
    } else {
      let cp: Int = _pc_decode(label, i);
      if cp < 0 {
        return _pc_err("punycode: invalid UTF-8");
      }
      cps.push(cp);
      i = i + _pc_seq_len(b0);
    }
  }
  return _pc_encode_cps(&cps);
}

/// Decode one Punycode label (WITHOUT the "xn--" prefix) to Unicode.
/// Params: label - the encoded part only, e.g. "bcher-kva"; digits are
/// case-insensitive; the last '-' separates the verbatim basic code points.
/// Returns: Ok(unicode label) for well-formed input; Ok("") for "".
/// Error case: Err("punycode: invalid digit") for a byte outside the digit
/// alphabet, Err("punycode: non-ASCII basic code point") for a byte >= 0x80
/// before the last '-', Err("punycode: truncated encoded data") when a
/// digit run ends mid-code-point, and Err("punycode: overflow") /
/// Err("punycode: code point out of range") for non-terminating or
/// out-of-range runs.
/// Complexity: O(label.len()^2) worst case.
pub fn punycode_decode_label(label: Str) -> Result[Str, Str] {
  return _pc_decode_label(label);
}

/// Convert a dot-separated domain to its ASCII form.
/// Params: domain - labels separated by '.'.
/// Returns: Ok(domain) with every ASCII label unchanged (including empty
/// labels) and every non-ASCII label replaced by "xn--" + punycode.
/// Error case: the first Err from punycode_encode_label, propagated
/// unchanged (invalid UTF-8 or overflow in one label).
/// Complexity: O(sum of label encode costs).
pub fn punycode_to_ascii(domain: Str) -> Result[Str, Str] {
  let labels = _pc_split_domain(domain);
  let n = labels.len();
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    if i > 0 {
      out.push(_PC_DOT as UInt8);
    }
    let label: Str = labels[i];
    if label.len() == 0 {
      // Empty labels are preserved without a prefix.
    } elif punycode_is_ascii_label(label) {
      builder.sb_push_str(&mut out, label);
    } else {
      let enc = punycode_encode_label(label);
      if !enc.is_ok {
        let m: Str = enc.error;
        return _pc_err(m);
      }
      let v: Str = enc.value;
      builder.sb_push_str(&mut out, "xn--");
      builder.sb_push_str(&mut out, v);
    }
    i = i + 1;
  }
  return _pc_ok(builder.sb_to_str(&out));
}

/// Convert a dot-separated domain to its Unicode form.
/// Params: domain - labels separated by '.'.
/// Returns: Ok(domain) with every label starting with "xn--"
/// (ASCII case-insensitive) decoded and every other label passed through
/// unchanged (including empty labels).
/// Error case: the first Err from punycode_decode_label, propagated
/// unchanged.
/// Complexity: O(sum of label decode costs).
pub fn punycode_to_unicode(domain: Str) -> Result[Str, Str] {
  let labels = _pc_split_domain(domain);
  let n = labels.len();
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    if i > 0 {
      out.push(_PC_DOT as UInt8);
    }
    let label: Str = labels[i];
    if _pc_has_xn_prefix(label) {
      let payload = string.str_slice(label, 4, label.len());
      let dec = punycode_decode_label(payload);
      if !dec.is_ok {
        let m: Str = dec.error;
        return _pc_err(m);
      }
      let v: Str = dec.value;
      builder.sb_push_str(&mut out, v);
    } else {
      builder.sb_push_str(&mut out, label);
    }
    i = i + 1;
  }
  return _pc_ok(builder.sb_to_str(&out));
}
