// XIOM -- xiom.rtf: a strict, in-memory RTF subset codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Documented subset (SPEC.md is normative):
//   * a document is exactly one outer group that must start with the six
//     bytes {\rtf1 (control word \rtf with parameter 1);
//   * groups { ... } nest; every group is one group_open token and one
//     group_close token, both carrying the group's depth;
//   * control words \word (1..32 ASCII letters) with an optional signed
//     numeric parameter and one optional single-space delimiter;
//   * control symbols \\ \{ \} only (any other backslash + non-letter is a
//     bad control word, as are a trailing lone backslash and >32 letters);
//   * hex escapes \'hh as raw-byte tokens: texts hold the two lowercase hex
//     digits, params hold the byte value 0..255, plain text skips \'00
//     (XIOM Str is NUL-terminated; see the emitter note below);
//   * unicode escapes \uN (signed 16-bit RTF value; negative values add
//     65536) followed by one optional fallback byte, which is consumed and
//     discarded; surrogate code units are kept as code units and their text
//     is the 3-byte CESU-8 form; rtf_plain_text joins an adjacent high/low
//     surrogate pair into one 4-byte UTF-8 character;
//   * plain text runs, including LF/CRLF: CRLF and lone CR normalize to LF.
// Font, color and stylesheet tables, destinations and RTF 1.9 semantics are
// NOT interpreted: their control words are ordinary tokens (pass-through).
//
// Model: one flat token stream stored as four parallel Vecs (kinds, texts,
// params, depth) because XIOM v0.61.3 cannot hold Vec[StructType]. Token i
// has kind kinds[i], text texts[i], numeric parameter params[i] (the
// sentinel rtf_no_param() when absent; see rtf_param for the per-kind
// meaning) and group depth depth[i]. rtf_emit writes a canonical form
// (single space after every control word, lowercase hex digits, fallback
// "?" after every \u) and rtf_plain_text extracts the visible text.
//
// v0.61.3 notes that shaped this module (SPEC.md section 9):
//   * free functions only; no methods, lambdas, or generics;
//   * Ok/Err are constructed only in the tiny leaf helpers below;
//   * Str values read from Vec[Str] are compared through
//     xiom.string.compare.str_compare, never `==` (BUG 17);
//   * every byte is read as Int through _byte() with a 0xFF mask, so no
//     UInt8 widening takes part in a comparison;
//   * no 0x00 byte ever enters a builder (sb_to_str is NUL-terminated), so
//     \u0 has empty text and \'00 is skipped by rtf_plain_text.

module xiom.rtf

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Public data model
// --------------------------------------------------

/// A flat RTF token stream: parallel per-token arrays.
/// Token i has kind kinds[i] ("group_open", "group_close", "control",
/// "symbol", "hex", "unicode" or "text"), text texts[i], numeric parameter
/// params[i], and group depth depth[i] (number of enclosing groups; a
/// group_open token carries the depth before it opens, a group_close token
/// the depth of the group it closes). All four vectors always have the same
/// length for a stream produced by rtf_parse.
pub type RtfTokens = {
  kinds: Vec[Str];
  texts: Vec[Str];
  params: Vec[Int];
  depth: Vec[Int];
}

// --------------------------------------------------
//  Constants
// --------------------------------------------------

const _LF: Int = 10;
const _CR: Int = 13;
const _SPACE: Int = 32;
const _APOS: Int = 39;
const _MINUS: Int = 45;
const _ZERO: Int = 48;
const _NINE: Int = 57;
const _UPPER_A: Int = 65;
const _UPPER_F: Int = 70;
const _UPPER_Z: Int = 90;
const _LOWER_A: Int = 97;
const _LOWER_F: Int = 102;
const _LOWER_Z: Int = 122;
const _BACKSLASH: Int = 92;
const _LBRACE: Int = 123;
const _RBRACE: Int = 125;

// No control word parameter can take this value: parameters are bounded to
// the signed 32-bit range, so the sentinel is unambiguous. For "unicode"
// tokens params holds the code unit after negative adjustment (0..65535);
// for "hex" tokens it holds the raw byte value (0..255).
const _NO_PARAM: Int = -2147483649;

// --------------------------------------------------
//  Result and struct constructors (leaf helpers)
// --------------------------------------------------

// The one place an RtfTokens value is assembled from its parallel vectors.
fn _make_tokens(kinds: Vec[Str], texts: Vec[Str], params: Vec[Int], depth: Vec[Int]) -> RtfTokens {
  return RtfTokens{
    kinds: kinds;
    texts: texts;
    params: params;
    depth: depth;
  };
}

// Ok(v) for Result[RtfTokens, Str].
fn _ok_rtf(v: RtfTokens) -> Result[RtfTokens, Str] {
  return Ok(v);
}

// Err(m) for Result[RtfTokens, Str].
fn _err_rtf(m: Str) -> Result[RtfTokens, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte and character helpers
// --------------------------------------------------

// Byte `pos` of `s` as an Int in 0..255 (callers guarantee the bounds).
// The 0xFF mask keeps the widening explicit (see the header note).
fn _byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// ASCII letter: A-Z or a-z.
fn _is_letter(b: Int) -> Bool {
  if b >= _UPPER_A && b <= _UPPER_Z { return true; }
  if b >= _LOWER_A && b <= _LOWER_Z { return true; }
  return false;
}

// ASCII digit: 0-9.
fn _is_digit(b: Int) -> Bool {
  return b >= _ZERO && b <= _NINE;
}

// Value of one hex digit (0..15); -1 when `b` is not a hex digit.
fn _hex_value(b: Int) -> Int {
  if b >= _ZERO && b <= _NINE { return b - _ZERO; }
  if b >= _LOWER_A && b <= _LOWER_F { return b - _LOWER_A + 10; }
  if b >= _UPPER_A && b <= _UPPER_F { return b - _UPPER_A + 10; }
  return -1;
}

// Append the UTF-8 encoding of a BMP code unit (1..65535; code unit 0 is
// never encoded, see _utf8_text).
fn _push_utf8_unit(out: &mut Vec[UInt8], cu: Int) {
  if cu < 128 {
    out.push(cu as UInt8);
  } elif cu < 2048 {
    out.push((192 | (cu >> 6)) as UInt8);
    out.push((128 | (cu & 63)) as UInt8);
  } else {
    out.push((224 | (cu >> 12)) as UInt8);
    out.push((128 | ((cu >> 6) & 63)) as UInt8);
    out.push((128 | (cu & 63)) as UInt8);
  }
}

// Append the UTF-8 encoding of a code point (including 4-byte forms above
// the BMP, used when rtf_plain_text joins a surrogate pair).
fn _push_utf8_cp(out: &mut Vec[UInt8], cp: Int) {
  if cp < 65536 {
    _push_utf8_unit(out, cp);
    return;
  }
  out.push((240 | (cp >> 18)) as UInt8);
  out.push((128 | ((cp >> 12) & 63)) as UInt8);
  out.push((128 | ((cp >> 6) & 63)) as UInt8);
  out.push((128 | (cp & 63)) as UInt8);
}

// UTF-8 text of one unicode code unit. Code unit 0 returns "" because a NUL
// byte cannot be represented in a Str (see the header note).
fn _utf8_text(cu: Int) -> Str {
  if cu <= 0 { return ""; }
  var out = Vec[UInt8].new();
  _push_utf8_unit(&mut out, cu);
  return builder.sb_to_str(&out);
}

// Text run [from, to) with CRLF and lone CR normalized to a single LF; all
// other bytes pass through. The slice is returned unchanged when no CR is
// present (the common case).
fn _normalize_crlf(text: Str, from: Int, to: Int) -> Str {
  var p = from;
  var found = false;
  while p < to {
    if _byte(text, p) == _CR {
      found = true;
      break;
    }
    p = p + 1;
  }
  if !found { return string.str_slice(text, from, to); }
  var out = Vec[UInt8].new();
  p = from;
  while p < to {
    let c = _byte(text, p);
    if c == _CR {
      out.push(_LF as UInt8);
      if p + 1 < to && _byte(text, p + 1) == _LF {
        p = p + 2;
      } else {
        p = p + 1;
      }
    } else {
      out.push(c as UInt8);
      p = p + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Numeric parameters
// --------------------------------------------------

// End index (exclusive) of the number starting at `from`: an optional "-"
// followed by one or more digits. Returns `from` when no digit follows, so
// "no parameter" and "parameter" are distinguishable.
fn _number_end(text: Str, from: Int) -> Int {
  let n = text.len();
  var p = from;
  if p < n && _byte(text, p) == _MINUS { p = p + 1; }
  let digits = p;
  while p < n && _is_digit(_byte(text, p)) { p = p + 1; }
  if p == digits { return from; }
  return p;
}

// Value of the number in [from, to); callers guarantee _number_end covers
// it. Returns _NO_PARAM when the value does not fit the signed 32-bit range
// [-2147483648, 2147483647].
fn _number_value(text: Str, from: Int, to: Int) -> Int {
  var p = from;
  var neg = false;
  if _byte(text, p) == _MINUS {
    neg = true;
    p = p + 1;
  }
  if to - p > 10 { return _NO_PARAM; }
  var acc = 0;
  while p < to {
    acc = acc * 10 + (_byte(text, p) - _ZERO);
    p = p + 1;
  }
  if neg {
    if acc > 2147483648 { return _NO_PARAM; }
    if acc == 2147483648 { return -2147483648; }
    return 0 - acc;
  }
  if acc > 2147483647 { return _NO_PARAM; }
  return acc;
}

// --------------------------------------------------
//  Scanner
// --------------------------------------------------

// Scan the control sequence starting at the backslash `start`, append its
// token(s) to the four parallel vectors at `depth`, and return the index
// after it. Errors: "rtf: bad control word at <start>" (lone backslash,
// non-letter symbol outside the subset, or a name longer than 32 letters),
// "rtf: bad hex escape at <start>", "rtf: numeric overflow at <start>",
// "rtf: truncated unicode escape at <start>", "rtf: unicode value out of
// range at <start>" (unicode parameters must be signed 16-bit).
fn _scan_control(text: Str, start: Int, kinds: &mut Vec[Str], texts: &mut Vec[Str], params: &mut Vec[Int], depths: &mut Vec[Int], depth: Int) -> Result[Int, Str] {
  let n = text.len();
  var i = start + 1;
  if i >= n { return _err_int("rtf: bad control word at " + int_to_string(start)); }
  let b = _byte(text, i);
  if b == _BACKSLASH {
    kinds.push("symbol");
    texts.push("\\");
    params.push(_NO_PARAM);
    depths.push(depth);
    return _ok_int(i + 1);
  }
  if b == _LBRACE {
    kinds.push("symbol");
    texts.push("{");
    params.push(_NO_PARAM);
    depths.push(depth);
    return _ok_int(i + 1);
  }
  if b == _RBRACE {
    kinds.push("symbol");
    texts.push("}");
    params.push(_NO_PARAM);
    depths.push(depth);
    return _ok_int(i + 1);
  }
  if b == _APOS {
    if i + 2 >= n { return _err_int("rtf: bad hex escape at " + int_to_string(start)); }
    let hi = _hex_value(_byte(text, i + 1));
    let lo = _hex_value(_byte(text, i + 2));
    if hi < 0 || lo < 0 { return _err_int("rtf: bad hex escape at " + int_to_string(start)); }
    let digits = string.str_slice("0123456789abcdef", hi, hi + 1) + string.str_slice("0123456789abcdef", lo, lo + 1);
    kinds.push("hex");
    texts.push(digits);
    params.push(hi * 16 + lo);
    depths.push(depth);
    return _ok_int(i + 3);
  }
  if !_is_letter(b) { return _err_int("rtf: bad control word at " + int_to_string(start)); }
  var j = i;
  while j < n && _is_letter(_byte(text, j)) { j = j + 1; }
  if j - i > 32 { return _err_int("rtf: bad control word at " + int_to_string(start)); }
  let name = string.str_slice(text, i, j);
  var param = _NO_PARAM;
  let num_end = _number_end(text, j);
  if num_end > j {
    param = _number_value(text, j, num_end);
    if param == _NO_PARAM { return _err_int("rtf: numeric overflow at " + int_to_string(start)); }
    j = num_end;
  }
  // One optional single-space delimiter after the control word.
  if j < n && _byte(text, j) == _SPACE { j = j + 1; }
  if compare.str_compare(name, "u") == 0 {
    if param == _NO_PARAM { return _err_int("rtf: truncated unicode escape at " + int_to_string(start)); }
    if param < -32768 || param > 32767 { return _err_int("rtf: unicode value out of range at " + int_to_string(start)); }
    var cu = param;
    if cu < 0 { cu = cu + 65536; }
    kinds.push("unicode");
    texts.push(_utf8_text(cu));
    params.push(cu);
    depths.push(depth);
    // Optional fallback character: consumed and discarded when the next byte
    // is not a control delimiter. \u0 with fallback "?" is canonical.
    if j < n {
      let fb = _byte(text, j);
      if fb != _BACKSLASH && fb != _LBRACE && fb != _RBRACE { j = j + 1; }
    }
    return _ok_int(j);
  }
  kinds.push("control");
  texts.push(name);
  params.push(param);
  depths.push(depth);
  return _ok_int(j);
}

// Tokenize `text` into a flat RtfTokens stream. Document shape is enforced
// here: exactly one outermost group (any byte after its closing brace is
// "rtf: trailing bytes after document end at <pos>") and balanced braces
// ("rtf: unbalanced braces at <pos>", the position of the extra "}" or of
// the outermost still-open "{").
fn _scan(text: Str) -> Result[RtfTokens, Str] {
  var kinds = Vec[Str].new();
  var texts = Vec[Str].new();
  var params = Vec[Int].new();
  var depths = Vec[Int].new();
  let n = text.len();
  var depth = 0;
  var outer_open = -1;
  var i = 0;
  while i < n {
    let b = _byte(text, i);
    if b == _LBRACE {
      if depth == 0 { outer_open = i; }
      kinds.push("group_open");
      texts.push("");
      params.push(_NO_PARAM);
      depths.push(depth);
      depth = depth + 1;
      i = i + 1;
    } elif b == _RBRACE {
      if depth == 0 { return _err_rtf("rtf: unbalanced braces at " + int_to_string(i)); }
      kinds.push("group_close");
      texts.push("");
      params.push(_NO_PARAM);
      depths.push(depth);
      depth = depth - 1;
      if depth == 0 && i + 1 < n {
        return _err_rtf("rtf: trailing bytes after document end at " + int_to_string(i + 1));
      }
      i = i + 1;
    } elif b == _BACKSLASH {
      let r = _scan_control(text, i, &mut kinds, &mut texts, &mut params, &mut depths, depth);
      match r {
        Ok(next) => { i = next; },
        Err(e) => { return _err_rtf(e); },
      }
    } else {
      let start = i;
      var j = i;
      while j < n {
        let c = _byte(text, j);
        if c == _LBRACE || c == _RBRACE || c == _BACKSLASH { break; }
        j = j + 1;
      }
      kinds.push("text");
      texts.push(_normalize_crlf(text, start, j));
      params.push(_NO_PARAM);
      depths.push(depth);
      i = j;
    }
  }
  if depth > 0 { return _err_rtf("rtf: unbalanced braces at " + int_to_string(outer_open)); }
  return _ok_rtf(_make_tokens(kinds, texts, params, depths));
}

// First offset at which `text` differs from the six-byte document-start
// prefix "{\rtf1"; -1 when the prefix matches. A missing byte counts as a
// difference at the end of the input.
fn _doc_prefix_mismatch(text: Str) -> Int {
  let want = "{\\rtf1";
  let n = text.len();
  var i = 0;
  while i < 6 {
    if i >= n { return i; }
    if _byte(text, i) != _byte(want, i) { return i; }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Public API -- parse, emit, plain text
// --------------------------------------------------

/// Parse an RTF document of the documented subset into a flat token stream.
/// Params: text - the whole document as one Str.
/// Returns: Ok(RtfTokens) whose four vectors have equal length, in source
/// order, with the rules described in the module header (group nesting,
/// control words/symbols, raw \'hh byte tokens, \uNNNN code units, text runs
/// with CRLF normalization).
/// Errors: "rtf: text before document start at <pos>" (the input does not
/// start with the six bytes {\rtf1; <pos> is the first differing offset, so
/// an empty input reports 0 and {\rtf2 reports 5), "rtf: bad document
/// start at 1" (\rtf tokenizes but is not the control word rtf with
/// parameter exactly 1, e.g. {\rtf12), "rtf: unbalanced braces at <pos>",
/// "rtf: trailing bytes after document end at <pos>", "rtf: bad control
/// word at <pos>", "rtf: bad hex escape at <pos>", "rtf: numeric overflow
/// at <pos>", "rtf: truncated unicode escape at <pos>", "rtf: unicode value
/// out of range at <pos>". Control-word-level positions are the offset of
/// the introducing backslash.
/// Complexity: O(text length).
pub fn rtf_parse(text: Str) -> Result[RtfTokens, Str] {
  let mm = _doc_prefix_mismatch(text);
  if mm >= 0 {
    return _err_rtf("rtf: text before document start at " + int_to_string(mm));
  }
  let r = _scan(text);
  match r {
    Ok(t) => {
      if t.kinds.len() < 2 { return _err_rtf("rtf: bad document start at 1"); }
      let k1: Str = t.kinds[1];
      let name1: Str = t.texts[1];
      let p1: Int = t.params[1];
      if compare.str_compare(k1, "control") != 0 { return _err_rtf("rtf: bad document start at 1"); }
      if compare.str_compare(name1, "rtf") != 0 { return _err_rtf("rtf: bad document start at 1"); }
      if p1 != 1 { return _err_rtf("rtf: bad document start at 1"); }
      return _ok_rtf(t);
    },
    Err(e) => { return _err_rtf(e); },
  }
}

// Escape a text run for emission: { } \ are prefixed with a backslash so the
// output re-parses to the same text; everything else is byte-copied.
fn _push_escaped_text(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  let n = s.len();
  while i < n {
    let b = _byte(s, i);
    if b == _LBRACE || b == _RBRACE || b == _BACKSLASH {
      out.push(_BACKSLASH as UInt8);
    }
    out.push(b as UInt8);
    i = i + 1;
  }
}

/// Serialize a token stream as canonical RTF.
/// Params: tokens - a stream produced by rtf_parse (per-token meaning as in
/// the type documentation).
/// Returns: canonical text in which every control word is followed by
/// exactly one space (plus its parameter when present), hex tokens are
/// written \'hh with lowercase digits, every unicode token is written in
/// signed form as \uN followed by the fallback "?", text bytes { } \ are
/// backslash-escaped, and everything else is byte-exact. For any stream
/// produced by rtf_parse this is idempotent and reparses to an identical
/// stream (round-trip).
/// Error case: none.
/// Complexity: O(total text length).
pub fn rtf_emit(tokens: &RtfTokens) -> Str {
  var out = Vec[UInt8].new();
  let n = tokens.kinds.len();
  var i = 0;
  while i < n {
    let k: Str = tokens.kinds[i];
    if compare.str_compare(k, "group_open") == 0 {
      builder.sb_push_str(&mut out, "{");
    } elif compare.str_compare(k, "group_close") == 0 {
      builder.sb_push_str(&mut out, "}");
    } elif compare.str_compare(k, "control") == 0 {
      builder.sb_push_str(&mut out, "\\");
      let name: Str = tokens.texts[i];
      builder.sb_push_str(&mut out, name);
      let p: Int = tokens.params[i];
      if p != _NO_PARAM { builder.sb_push_int(&mut out, p); }
      builder.sb_push_str(&mut out, " ");
    } elif compare.str_compare(k, "symbol") == 0 {
      builder.sb_push_str(&mut out, "\\");
      let sym: Str = tokens.texts[i];
      builder.sb_push_str(&mut out, sym);
    } elif compare.str_compare(k, "hex") == 0 {
      builder.sb_push_str(&mut out, "\\'");
      let hx: Str = tokens.texts[i];
      builder.sb_push_str(&mut out, hx);
    } elif compare.str_compare(k, "unicode") == 0 {
      let cu: Int = tokens.params[i];
      var sgn = cu;
      if cu >= 32768 { sgn = cu - 65536; }
      builder.sb_push_str(&mut out, "\\u");
      builder.sb_push_int(&mut out, sgn);
      builder.sb_push_str(&mut out, " ?");
    } else {
      let txt: Str = tokens.texts[i];
      _push_escaped_text(&mut out, txt);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Append the visible text of `t` (text runs, control symbols, hex bytes
// except \'00, and unicode code units with surrogate-pair joining).
fn _push_plain(out: &mut Vec[UInt8], t: &RtfTokens) {
  let n = t.kinds.len();
  var i = 0;
  while i < n {
    let k: Str = t.kinds[i];
    var step = 1;
    if compare.str_compare(k, "text") == 0 {
      let x: Str = t.texts[i];
      builder.sb_push_str(out, x);
    } elif compare.str_compare(k, "symbol") == 0 {
      let x: Str = t.texts[i];
      builder.sb_push_str(out, x);
    } elif compare.str_compare(k, "hex") == 0 {
      let v: Int = t.params[i];
      if v > 0 { out.push(v as UInt8); }
    } elif compare.str_compare(k, "unicode") == 0 {
      let cu: Int = t.params[i];
      var joined = false;
      if cu >= 55296 && cu <= 56319 && i + 1 < n {
        let k2: Str = t.kinds[i + 1];
        if compare.str_compare(k2, "unicode") == 0 {
          let lo: Int = t.params[i + 1];
          if lo >= 56320 && lo <= 57343 {
            _push_utf8_cp(out, 65536 + (cu - 55296) * 1024 + (lo - 56320));
            joined = true;
          }
        }
      }
      if joined {
        step = 2;
      } elif cu > 0 {
        _push_utf8_unit(out, cu);
      }
    }
    i = i + step;
  }
}

/// Extract the visible plain text of a token stream: every text run, every
/// control symbol \\ \{ \}, every hex byte except \'00, and every unicode
/// code unit, in order. Control words (including \par and all table control
/// words) contribute nothing, and group braces contribute nothing. An
/// adjacent pair of a high-surrogate and a low-surrogate unicode token is
/// joined into one 4-byte UTF-8 character; other surrogate code units are
/// written as their 3-byte form. Code unit 0 and the byte \'00 contribute
/// nothing (XIOM Str cannot hold NUL; documented).
/// Params: tokens - a stream produced by rtf_parse.
/// Returns: the extracted text ("" for a document with no visible text).
/// Error case: none.
/// Complexity: O(total text length).
pub fn rtf_plain_text(tokens: &RtfTokens) -> Str {
  var out = Vec[UInt8].new();
  _push_plain(&mut out, tokens);
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Public API -- accessors
// --------------------------------------------------

/// The sentinel stored in params[i] when token i has no numeric parameter.
/// It is -2147483649, one below the smallest legal parameter, so no parsed
/// parameter can collide with it.
pub fn rtf_no_param() -> Int {
  return _NO_PARAM;
}

/// Number of tokens in `tokens` (0 for an empty stream).
/// Error case: none.
/// Complexity: O(1).
pub fn rtf_token_count(tokens: &RtfTokens) -> Int {
  return tokens.kinds.len();
}

/// Kind of token `i`: "group_open", "group_close", "control", "symbol",
/// "hex", "unicode" or "text"; "" when `i` is negative or out of range (so
/// compare against the wanted kind, never against "").
/// Error case: none.
/// Complexity: O(1).
pub fn rtf_kind(tokens: &RtfTokens, i: Int) -> Str {
  if i < 0 || i >= tokens.kinds.len() { return ""; }
  let x: Str = tokens.kinds[i];
  return x;
}

/// Text of token `i`. Per kind: the control word name without the backslash
/// ("control"), the escaped character ("symbol"), the two lowercase hex
/// digits ("hex"), the UTF-8 text of the code unit ("" for code unit 0,
/// "unicode"), the run bytes with CRLF already normalized ("text"), and ""
/// for group tokens. Returns "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1) (the text is stored, not rebuilt).
pub fn rtf_text(tokens: &RtfTokens, i: Int) -> Str {
  if i < 0 || i >= tokens.texts.len() { return ""; }
  let x: Str = tokens.texts[i];
  return x;
}

/// Numeric parameter of token `i`. For a "control" token it is the signed
/// parameter or rtf_no_param() when absent; for a "unicode" token it is the
/// code unit after negative adjustment (0..65535); for a "hex" token it is
/// the raw byte value (0..255); for every other kind it is rtf_no_param().
/// Returns rtf_no_param() when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn rtf_param(tokens: &RtfTokens, i: Int) -> Int {
  if i < 0 || i >= tokens.params.len() { return _NO_PARAM; }
  let x: Int = tokens.params[i];
  return x;
}

/// True when token `i` carries a parsed numeric parameter: always true for
/// "unicode" tokens, true for a "control" token with a parameter, false for
/// every other kind (including "hex", whose params entry is a byte value,
/// not a parameter). False when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn rtf_has_param(tokens: &RtfTokens, i: Int) -> Bool {
  if i < 0 || i >= tokens.kinds.len() { return false; }
  let k: Str = tokens.kinds[i];
  if compare.str_compare(k, "unicode") == 0 { return true; }
  if compare.str_compare(k, "control") != 0 { return false; }
  let p: Int = tokens.params[i];
  return p != _NO_PARAM;
}

/// Group depth of token `i`: the number of groups enclosing it. A
/// group_open token carries the depth before it opens (the outermost "{"
/// has depth 0); a group_close token carries the depth of the group it
/// closes; every other token carries the depth of its group. Returns -1
/// when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn rtf_depth(tokens: &RtfTokens, i: Int) -> Int {
  if i < 0 || i >= tokens.depth.len() { return -1; }
  let x: Int = tokens.depth[i];
  return x;
}

/// Raw byte value (0..255) of a "hex" token, i.e. the byte written as \'hh.
/// Returns -1 when `i` is negative or out of range, or when token `i` is
/// not a hex token.
/// Error case: none.
/// Complexity: O(1).
pub fn rtf_hex_value(tokens: &RtfTokens, i: Int) -> Int {
  if i < 0 || i >= tokens.kinds.len() { return -1; }
  let k: Str = tokens.kinds[i];
  if compare.str_compare(k, "hex") != 0 { return -1; }
  let x: Int = tokens.params[i];
  return x;
}
