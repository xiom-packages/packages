// XIOM -- xiom.fits: FITS header card/block codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI) codec for the header part of FITS files (Flexible
// Image Transport System, IAU FITS Standard 4.0). A header is a sequence of
// 2880-byte blocks of 80-character cards; the final card carries the keyword
// END and the rest of the last block is ASCII space padding. Each card is
// `KEYWORD  = value / comment` with the keyword in columns 1-8, '=' in
// column 9 and the value starting in column 10 or later.
//
// Decoding (`fits_parse`) walks whole 80-character cards, validates every
// one and stores five parallel vectors in `FitsHeader`: the raw card text,
// the keyword, the card kind, the value text and the comment text.
// `fits_encode` writes the raw cards back verbatim, appends the END card and
// pads with spaces, so a parsed header re-encodes byte-for-byte.
//
// Value model (`FITK_*` kinds): STR (single-quoted, '' unescaping),
// LOGICAL ("T"/"F"), INT and REAL (validated raw tokens, preserved exactly
// as written -- no parsed number types are produced), UNDEFINED (empty value
// field), plus the non-value cards COMMENT, HISTORY and BLANK (blank-keyword
// continuation). Real tokens must contain a '.' or an E/D exponent so the
// decode kind is stable across a parse/encode round-trip.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the small leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * Str values read from Vec[Str] elements are always bound to a typed
//     local first and compared through xiom.string.compare.str_compare
//     (BUG 17: `==` on such values lowers to a pointer comparison).
//   * no Vec[StructType] and no Vec[Float64]; the header is five flat
//     parallel vectors and numeric tokens stay text.

module xiom.fits

use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Card kinds
// --------------------------------------------------

/// Single-quoted character string value ('' is decoded to ').
pub const FITK_STR: Int = 0;
/// Logical value, always stored as "T" or "F".
pub const FITK_LOGICAL: Int = 1;
/// Integer value, stored as the validated raw token ("+0042", "-7", ...).
pub const FITK_INT: Int = 2;
/// Real value, stored as the validated raw token ("-1.5E+02", ".5", ...).
pub const FITK_REAL: Int = 3;
/// No value: the value field is empty (optionally followed by a comment).
pub const FITK_UNDEFINED: Int = 4;
/// COMMENT card; its text is returned by fits_comment.
pub const FITK_COMMENT: Int = 5;
/// HISTORY card; its text is returned by fits_comment.
pub const FITK_HISTORY: Int = 6;
/// Blank-keyword continuation card; its text is in fits_comment.
pub const FITK_BLANK: Int = 7;

// --------------------------------------------------
//  Header
// --------------------------------------------------

// Decoded FITS header. Five parallel vectors hold one entry per non-END
// card in file order: `cards` is the raw 80-byte card text (verbatim, used
// by fits_encode), `keywords` the trimmed keyword ("" on blank cards),
// `kinds` a FITK_* constant, `values` the decoded string / "T"/"F" / raw
// numeric token ("" for non-value kinds) and `comments` the comment text
// (for COMMENT/HISTORY/BLANK cards, the card text itself). Fields are
// implementation details; go through the free functions below.
pub type FitsHeader = {
  cards: Vec[Str];
  keywords: Vec[Str];
  kinds: Vec[Int];
  values: Vec[Str];
  comments: Vec[Str];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[FitsHeader, Str].
fn _ok_header(v: FitsHeader) -> Result[FitsHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[FitsHeader, Str].
fn _err_header(m: Str) -> Result[FitsHeader, Str] {
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

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte and keyword helpers
// --------------------------------------------------

// `s` with trailing ASCII spaces removed.
fn _trim_end_spaces(s: Str) -> Str {
  var n = s.len();
  while n > 0 {
    if string.byte_at(s, n - 1) != 32 {
      break;
    }
    n = n - 1;
  }
  return string.str_slice(s, 0, n);
}

// True when s[start, end) is all ASCII spaces (`end` above s.len() is
// clamped). `start` is assumed non-negative.
fn _all_spaces(s: Str, start: Int, end: Int) -> Bool {
  let n = s.len();
  var e = end;
  if e > n {
    e = n;
  }
  var i = start;
  while i < e {
    if string.byte_at(s, i) != 32 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when every byte of `s` is an ASCII space.
fn _is_all_spaces(s: Str) -> Bool {
  return _all_spaces(s, 0, s.len());
}

// The 8-byte keyword field of `card`, trailing spaces removed.
fn _card_keyword(card: Str) -> Str {
  return _trim_end_spaces(string.str_slice(card, 0, 8));
}

// True when the keyword field of `card` is all spaces (continuation card).
fn _blank_keyword(card: Str) -> Bool {
  return _all_spaces(card, 0, 8);
}

// True when `b` may appear in a FITS keyword: A-Z, 0-9, '-', '_'.
fn _is_keyword_byte(b: UInt8) -> Bool {
  if b >= 65 && b <= 90 {
    return true;
  }
  if b >= 48 && b <= 57 {
    return true;
  }
  return b == 45 || b == 95;
}

// True for a 1..8 byte keyword made only of _is_keyword_byte bytes.
fn _keyword_ok(keyword: Str) -> Bool {
  let n = keyword.len();
  if n < 1 || n > 8 {
    return false;
  }
  var i = 0;
  while i < n {
    if !_is_keyword_byte(string.byte_at(keyword, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `keyword` is one of the reserved whole-card keywords.
fn _reserved_keyword(keyword: Str) -> Bool {
  if compare.str_compare(keyword, "END") == 0 {
    return true;
  }
  if compare.str_compare(keyword, "COMMENT") == 0 {
    return true;
  }
  return compare.str_compare(keyword, "HISTORY") == 0;
}

// ASCII uppercase of `b` widened to Int (used for case-insensitive lookup).
fn _upper(b: UInt8) -> Int {
  if b >= 97 && b <= 122 {
    return (b as Int) - 32;
  }
  return b as Int;
}

// True when `a` and `b` are equal ignoring ASCII letter case.
fn _ci_eq(a: Str, b: Str) -> Bool {
  let na = a.len();
  let nb = b.len();
  if na != nb {
    return false;
  }
  var i = 0;
  while i < na {
    if _upper(string.byte_at(a, i)) != _upper(string.byte_at(b, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Value token validation
// --------------------------------------------------

// True for an optionally signed run of ASCII digits ("" and "+" are not).
fn _token_is_int(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  let b0 = string.byte_at(s, 0);
  if b0 == 43 || b0 == 45 {
    i = 1;
  }
  if i >= n {
    return false;
  }
  while i < n {
    let b = string.byte_at(s, i);
    if b < 48 || b > 57 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True for an optionally signed real token that contains a '.' or an E/D
// exponent, so decoding classifies it as REAL and never as INT.
fn _token_is_real(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  let b0 = string.byte_at(s, 0);
  if b0 == 43 || b0 == 45 {
    i = 1;
  }
  var digits = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b < 48 || b > 57 {
      break;
    }
    digits = digits + 1;
    i = i + 1;
  }
  var has_dot = false;
  if i < n && string.byte_at(s, i) == 46 {
    has_dot = true;
    i = i + 1;
    while i < n {
      let b = string.byte_at(s, i);
      if b < 48 || b > 57 {
        break;
      }
      digits = digits + 1;
      i = i + 1;
    }
  }
  if digits == 0 {
    return false;
  }
  var has_exp = false;
  if i < n {
    let b = string.byte_at(s, i);
    if b == 69 || b == 101 || b == 68 || b == 100 {
      has_exp = true;
      i = i + 1;
      if i < n {
        let sb = string.byte_at(s, i);
        if sb == 43 || sb == 45 {
          i = i + 1;
        }
      }
      var exp_digits = 0;
      while i < n {
        let b2 = string.byte_at(s, i);
        if b2 < 48 || b2 > 57 {
          return false;
        }
        exp_digits = exp_digits + 1;
        i = i + 1;
      }
      if exp_digits == 0 {
        return false;
      }
    }
  }
  if i != n {
    return false;
  }
  if !has_dot && !has_exp {
    return false;
  }
  return true;
}

// --------------------------------------------------
//  Card field scanning
// --------------------------------------------------

// Index of the first non-space byte at or after column 10 (index 9); 80
// when the value field is empty.
fn _value_start(card: Str) -> Int {
  var i = 9;
  while i < 80 {
    if string.byte_at(card, i) != 32 {
      break;
    }
    i = i + 1;
  }
  return i;
}

// End of an unquoted token: the first space or '/' at or after `start`,
// else 80.
fn _token_end(card: Str, start: Int) -> Int {
  var i = start;
  while i < 80 {
    let b = string.byte_at(card, i);
    if b == 32 || b == 47 {
      break;
    }
    i = i + 1;
  }
  return i;
}

// Where a comment may begin after `pos`: skips spaces and returns the index
// of '/', -1 when the card ends first, -2 when junk precedes '/'.
fn _comment_start(card: Str, pos: Int) -> Int {
  var i = pos;
  while i < 80 {
    if string.byte_at(card, i) != 32 {
      break;
    }
    i = i + 1;
  }
  if i >= 80 {
    return -1;
  }
  if string.byte_at(card, i) == 47 {
    return i;
  }
  return -2;
}

// Comment text: the bytes after the '/' at `slash`, fully trimmed.
fn _comment_text(card: Str, slash: Int) -> Str {
  return string.str_trim(_trim_end_spaces(string.str_slice(card, slash + 1, 80)));
}

// Text of a COMMENT/HISTORY/blank card: columns 9-80, fully trimmed.
fn _text_card_text(card: Str) -> Str {
  return string.str_trim(_trim_end_spaces(string.str_slice(card, 8, 80)));
}

// --------------------------------------------------
//  Card classification and appending
// --------------------------------------------------

// Append one already-classified card to every parallel vector.
fn _push_fields(h: &mut FitsHeader, card: Str, key: Str, kind: Int, value: Str, comment: Str) {
  h.cards.push(card);
  h.keywords.push(key);
  h.kinds.push(kind);
  h.values.push(value);
  h.comments.push(comment);
}

// Decode the quoted string value whose opening quote is at `start` and
// append the card. Doubled quotes decode to one quote; the closing quote
// must precede column 81.
fn _append_string_card(h: &mut FitsHeader, card: Str, key: Str, start: Int) -> Result[Unit, Str] {
  var out = Vec[UInt8].new();
  var i = start + 1;
  var closed = false;
  while i < 80 {
    let b = string.byte_at(card, i);
    if b == 39 {
      if i + 1 < 80 && string.byte_at(card, i + 1) == 39 {
        out.push(39u8);
        i = i + 2;
      } else {
        closed = true;
        i = i + 1;
        break;
      }
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  if !closed {
    return _err_unit("fits: quote not closed");
  }
  let cs = _comment_start(card, i);
  if cs == -2 {
    return _err_unit("fits: junk after value");
  }
  var comment = "";
  if cs >= 0 {
    comment = _comment_text(card, cs);
  }
  let value = Str::from_utf8(out);
  _push_fields(h, card, key, FITK_STR, value, comment);
  return _ok_unit();
}

// Validate and classify one 80-character card, then append it. `card` must
// already be exactly 80 bytes; fits_push_card checks that for callers.
fn _append_card(h: &mut FitsHeader, card: Str) -> Result[Unit, Str] {
  if _blank_keyword(card) {
    _push_fields(h, card, "", FITK_BLANK, "", _text_card_text(card));
    return _ok_unit();
  }
  let key = _card_keyword(card);
  if compare.str_compare(key, "END") == 0 {
    return _err_unit("fits: unexpected END");
  }
  if compare.str_compare(key, "COMMENT") == 0 {
    _push_fields(h, card, key, FITK_COMMENT, "", _text_card_text(card));
    return _ok_unit();
  }
  if compare.str_compare(key, "HISTORY") == 0 {
    _push_fields(h, card, key, FITK_HISTORY, "", _text_card_text(card));
    return _ok_unit();
  }
  if string.byte_at(card, 8) != 61 {
    return _err_unit("fits: missing '='");
  }
  if !_keyword_ok(key) {
    return _err_unit("fits: bad keyword");
  }
  let start = _value_start(card);
  if start >= 80 {
    _push_fields(h, card, key, FITK_UNDEFINED, "", "");
    return _ok_unit();
  }
  if string.byte_at(card, start) == 47 {
    _push_fields(h, card, key, FITK_UNDEFINED, "", _comment_text(card, start));
    return _ok_unit();
  }
  if string.byte_at(card, start) == 39 {
    return _append_string_card(h, card, key, start);
  }
  let te = _token_end(card, start);
  let token = string.str_slice(card, start, te);
  let cs = _comment_start(card, te);
  if cs == -2 {
    return _err_unit("fits: junk after value");
  }
  var comment = "";
  if cs >= 0 {
    comment = _comment_text(card, cs);
  }
  if compare.str_compare(token, "T") == 0 {
    _push_fields(h, card, key, FITK_LOGICAL, "T", comment);
    return _ok_unit();
  }
  if compare.str_compare(token, "F") == 0 {
    _push_fields(h, card, key, FITK_LOGICAL, "F", comment);
    return _ok_unit();
  }
  if _token_is_int(token) {
    _push_fields(h, card, key, FITK_INT, token, comment);
    return _ok_unit();
  }
  if _token_is_real(token) {
    _push_fields(h, card, key, FITK_REAL, token, comment);
    return _ok_unit();
  }
  return _err_unit("fits: bad logical");
}

// --------------------------------------------------
//  Encoding
// --------------------------------------------------

// Append every byte of `s` to `out`.
fn _push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Pad `out` with ASCII spaces until it holds at least `n` bytes.
fn _pad_to(out: &mut Vec[UInt8], n: Int) {
  while out.len() < n {
    out.push(32u8);
  }
}

// Value-field bytes for a value kind; Err on an invalid token.
fn _value_field(kind: Int, value: Str) -> Result[Vec[UInt8], Str] {
  var fv = Vec[UInt8].new();
  if kind == FITK_STR {
    fv.push(39u8);
    var i = 0;
    while i < value.len() {
      let b = string.byte_at(value, i);
      if b == 39 {
        fv.push(39u8);
      }
      fv.push(b);
      i = i + 1;
    }
    fv.push(39u8);
    if fv.len() > 70 {
      return _err_bytes("fits: card too long");
    }
    return _ok_bytes(fv);
  }
  if kind == FITK_LOGICAL {
    if compare.str_compare(value, "T") != 0 && compare.str_compare(value, "F") != 0 {
      return _err_bytes("fits: bad logical");
    }
    _push_str(&mut fv, value);
    return _ok_bytes(fv);
  }
  if kind == FITK_INT {
    if !_token_is_int(value) {
      return _err_bytes("fits: invalid integer");
    }
    _push_str(&mut fv, value);
    return _ok_bytes(fv);
  }
  if kind == FITK_REAL {
    if !_token_is_real(value) {
      return _err_bytes("fits: invalid real");
    }
    _push_str(&mut fv, value);
    return _ok_bytes(fv);
  }
  if kind == FITK_UNDEFINED {
    if value.len() != 0 {
      return _err_bytes("fits: invalid value");
    }
    return _ok_bytes(fv);
  }
  return _err_bytes("fits: bad kind");
}

/// Format one card as an exactly 80-character string.
///
/// `kind` is a FITK_* constant. For value kinds, `value` is the string text
/// (STR, doubled quotes are added), "T"/"F" (LOGICAL), a validated integer
/// token (INT) or a validated real token (REAL); FITK_UNDEFINED requires an
/// empty value. For FITK_COMMENT/FITK_HISTORY/FITK_BLANK, `value` is the
/// card text and `keyword` must be "" (the reserved keyword is emitted).
///
/// Fixed-width layout: keyword left-justified in columns 1-8, '=' in column
/// 9, a space in column 10, the value field in columns 11-30 (numbers and
/// logicals right-justified, strings left-justified; longer values extend
/// past column 30), then " / comment" when a comment is present. Values too
/// long for one card are Err("fits: card too long").
///
/// Err: "fits: bad keyword", "fits: bad kind", "fits: bad logical",
/// "fits: invalid integer", "fits: invalid real", "fits: invalid value",
/// "fits: card too long". Complexity: O(keyword + value + comment).
pub fn fits_card_format(keyword: Str, kind: Int, value: Str, comment: Str) -> Result[Str, Str] {
  if kind == FITK_COMMENT || kind == FITK_HISTORY || kind == FITK_BLANK {
    var head = "        ";
    if kind == FITK_COMMENT {
      head = "COMMENT ";
    } elif kind == FITK_HISTORY {
      head = "HISTORY ";
    }
    if value.len() > 72 {
      return _err_str("fits: card too long");
    }
    var tout = Vec[UInt8].new();
    _push_str(&mut tout, head);
    _push_str(&mut tout, value);
    _pad_to(&mut tout, 80);
    return _ok_str(Str::from_utf8(tout));
  }
  if kind < FITK_STR || kind > FITK_UNDEFINED {
    return _err_str("fits: bad kind");
  }
  let kw = _trim_end_spaces(keyword);
  if !_keyword_ok(kw) || _reserved_keyword(kw) {
    return _err_str("fits: bad keyword");
  }
  let vr = _value_field(kind, value);
  if !vr.is_ok {
    return _err_str(vr.error);
  }
  let fv: Vec[UInt8] = vr.value;
  var out = Vec[UInt8].new();
  _push_str(&mut out, kw);
  _pad_to(&mut out, 8);
  out.push(61u8);
  out.push(32u8);
  let flen = fv.len();
  if kind == FITK_STR {
    var j = 0;
    while j < flen {
      out.push(fv[j]);
      j = j + 1;
    }
    if flen < 20 {
      _pad_to(&mut out, 30);
    }
  } else {
    var pad = 20 - flen;
    while pad > 0 {
      out.push(32u8);
      pad = pad - 1;
    }
    var k = 0;
    while k < flen {
      out.push(fv[k]);
      k = k + 1;
    }
  }
  if comment.len() > 0 {
    out.push(32u8);
    out.push(47u8);
    out.push(32u8);
    _push_str(&mut out, comment);
  }
  if out.len() > 80 {
    return _err_str("fits: card too long");
  }
  _pad_to(&mut out, 80);
  return _ok_str(Str::from_utf8(out));
}

// Format keyword/kind/value/comment and append the resulting card.
fn _push_formatted(h: &mut FitsHeader, keyword: Str, kind: Int, value: Str, comment: Str) -> Result[Unit, Str] {
  let r = fits_card_format(keyword, kind, value, comment);
  if !r.is_ok {
    return _err_unit(r.error);
  }
  let c: Str = r.value;
  return _append_card(h, c);
}

// --------------------------------------------------
//  Building
// --------------------------------------------------

/// Create an empty header (no cards, no END; fits_encode adds END).
/// Complexity: O(1).
pub fn fits_new() -> FitsHeader {
  return FitsHeader{
    cards: Vec[Str].new();
    keywords: Vec[Str].new();
    kinds: Vec[Int].new();
    values: Vec[Str].new();
    comments: Vec[Str].new();
  };
}

/// Validate one 80-character card and append it to `h`.
///
/// Use this with a card produced by fits_card_format, or with a card read
/// from a file when building a header by hand. Err("fits: card not 80
/// chars") when the length differs; Err("fits: unexpected END") for an END
/// card (fits_encode appends END itself); otherwise the same errors as
/// fits_parse, and `h` is unchanged on Err.
/// Complexity: O(card length).
pub fn fits_push_card(h: &mut FitsHeader, card: Str) -> Result[Unit, Str] {
  if card.len() != 80 {
    return _err_unit("fits: card not 80 chars");
  }
  return _append_card(h, card);
}

/// Append a string value card. Err on the fits_card_format errors; `h` is
/// unchanged when the card cannot be formatted.
/// Complexity: O(value length + comment length).
pub fn fits_push_str(h: &mut FitsHeader, keyword: Str, value: Str, comment: Str) -> Result[Unit, Str] {
  return _push_formatted(h, keyword, FITK_STR, value, comment);
}

/// Append a logical value card ("T" when `value`, else "F").
/// Err on the fits_card_format errors; `h` is unchanged on Err.
/// Complexity: O(comment length).
pub fn fits_push_logical(h: &mut FitsHeader, keyword: Str, value: Bool, comment: Str) -> Result[Unit, Str] {
  var token = "F";
  if value {
    token = "T";
  }
  return _push_formatted(h, keyword, FITK_LOGICAL, token, comment);
}

/// Append an integer card from a validated raw token (kept verbatim).
/// Err("fits: invalid integer") or another fits_card_format error; `h` is
/// unchanged on Err. Complexity: O(token length + comment length).
pub fn fits_push_int(h: &mut FitsHeader, keyword: Str, token: Str, comment: Str) -> Result[Unit, Str] {
  return _push_formatted(h, keyword, FITK_INT, token, comment);
}

/// Append a real card from a validated raw token (kept verbatim; must
/// contain a '.' or an E/D exponent). Err("fits: invalid real") or another
/// fits_card_format error; `h` is unchanged on Err.
/// Complexity: O(token length + comment length).
pub fn fits_push_float(h: &mut FitsHeader, keyword: Str, token: Str, comment: Str) -> Result[Unit, Str] {
  return _push_formatted(h, keyword, FITK_REAL, token, comment);
}

/// Append a card whose value field is empty, with an optional comment.
/// Err on the fits_card_format errors; `h` is unchanged on Err.
/// Complexity: O(comment length).
pub fn fits_push_undefined(h: &mut FitsHeader, keyword: Str, comment: Str) -> Result[Unit, Str] {
  return _push_formatted(h, keyword, FITK_UNDEFINED, "", comment);
}

/// Append a COMMENT card whose text is `text`.
/// Err("fits: card too long") when the text exceeds 72 characters;
/// `h` is unchanged on Err. Complexity: O(text length).
pub fn fits_push_comment(h: &mut FitsHeader, text: Str) -> Result[Unit, Str] {
  return _push_formatted(h, "COMMENT", FITK_COMMENT, text, "");
}

/// Append a HISTORY card whose text is `text`.
/// Err("fits: card too long") when the text exceeds 72 characters;
/// `h` is unchanged on Err. Complexity: O(text length).
pub fn fits_push_history(h: &mut FitsHeader, text: Str) -> Result[Unit, Str] {
  return _push_formatted(h, "HISTORY", FITK_HISTORY, text, "");
}

/// Append a blank-keyword continuation card whose text is `text`.
/// Err("fits: card too long") when the text exceeds 72 characters;
/// `h` is unchanged on Err. Complexity: O(text length).
pub fn fits_push_blank(h: &mut FitsHeader, text: Str) -> Result[Unit, Str] {
  return _push_formatted(h, "", FITK_BLANK, text, "");
}

// --------------------------------------------------
//  Decoding and encoding
// --------------------------------------------------

/// Parse a whole FITS header from whole 2880-byte blocks.
///
/// `data` must be non-empty and a multiple of 2880 bytes. Cards are read 80
/// bytes at a time across block boundaries; the END card terminates the
/// header, and every byte after it must be an ASCII space. Cards are
/// validated exactly as fits_push_card validates them. The END card is not
/// stored: fits_card_count counts value/COMMENT/HISTORY/BLANK cards only.
///
/// Err("fits: bad block padding") when the length is zero or not a multiple
/// of 2880, or when a non-space byte follows the END card;
/// Err("fits: missing END") when no END card is present; otherwise the
/// per-card errors ("fits: card ...", "fits: bad keyword",
/// "fits: missing '='", "fits: quote not closed", "fits: junk after
/// value", "fits: bad logical"). Complexity: O(data.len()).
pub fn fits_parse(data: &Vec[UInt8]) -> Result[FitsHeader, Str] {
  let total = data.len();
  if total == 0 || total % 2880 != 0 {
    return _err_header("fits: bad block padding");
  }
  var h = FitsHeader{
    cards: Vec[Str].new();
    keywords: Vec[Str].new();
    kinds: Vec[Int].new();
    values: Vec[Str].new();
    comments: Vec[Str].new();
  };
  var seen_end = false;
  var pos = 0;
  while pos < total {
    var bytes = Vec[UInt8].new();
    var k = 0;
    while k < 80 {
      bytes.push(data[pos + k]);
      k = k + 1;
    }
    let card = Str::from_utf8(bytes);
    if seen_end {
      if !_is_all_spaces(card) {
        return _err_header("fits: bad block padding");
      }
    } else {
      let key = _card_keyword(card);
      if compare.str_compare(key, "END") == 0 {
        if !_all_spaces(card, 3, 80) {
          return _err_header("fits: bad block padding");
        }
        seen_end = true;
      } else {
        let r = _append_card(&mut h, card);
        if !r.is_ok {
          return _err_header(r.error);
        }
      }
    }
    pos = pos + 80;
  }
  if !seen_end {
    return _err_header("fits: missing END");
  }
  return _ok_header(h);
}

/// Encode a whole FITS header: every stored card verbatim, then an END card,
/// then ASCII spaces up to the next multiple of 2880.
///
/// Output length is always a positive multiple of 2880. Cards are validated
/// when they are pushed, so encoding cannot fail. Complexity: O(cards).
pub fn fits_encode(h: &FitsHeader) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < h.cards.len() {
    let c: Str = h.cards[i];
    _push_str(&mut out, c);
    i = i + 1;
  }
  _push_str(&mut out, "END");
  _pad_to(&mut out, 80);
  while out.len() % 2880 != 0 {
    out.push(32u8);
  }
  return out;
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of stored cards (the END card is not stored).
/// Complexity: O(1).
pub fn fits_card_count(h: &FitsHeader) -> Int {
  return h.cards.len();
}

/// Raw 80-character text of card `i`, or "" when out of range.
/// Complexity: O(card length).
pub fn fits_card(h: &FitsHeader, i: Int) -> Str {
  if i < 0 || i >= h.cards.len() {
    return "";
  }
  let c: Str = h.cards[i];
  return c;
}

/// Keyword of card `i` ("" for a blank-keyword card or an out-of-range `i`).
/// Complexity: O(keyword length).
pub fn fits_keyword(h: &FitsHeader, i: Int) -> Str {
  if i < 0 || i >= h.cards.len() {
    return "";
  }
  let k: Str = h.keywords[i];
  return k;
}

/// Kind of card `i` (a FITK_* constant), or -1 when out of range.
/// Complexity: O(1).
pub fn fits_kind(h: &FitsHeader, i: Int) -> Int {
  if i < 0 || i >= h.cards.len() {
    return -1;
  }
  return h.kinds[i];
}

/// Value text of card `i`: the decoded string (STR), "T"/"F" (LOGICAL) or
/// the raw token (INT/REAL); None for UNDEFINED, non-value cards and
/// out-of-range `i`.
/// Complexity: O(value length).
pub fn fits_value(h: &FitsHeader, i: Int) -> Option[Str] {
  if i < 0 || i >= h.cards.len() {
    return None;
  }
  let k: Int = h.kinds[i];
  if k != FITK_STR && k != FITK_LOGICAL && k != FITK_INT && k != FITK_REAL {
    return None;
  }
  let v: Str = h.values[i];
  return Some(v);
}

/// Comment text of card `i` ("" when the card has none). For COMMENT,
/// HISTORY and blank-keyword cards this returns the card text itself. For
/// an out-of-range `i` it returns "".
/// Complexity: O(comment length).
pub fn fits_comment(h: &FitsHeader, i: Int) -> Str {
  if i < 0 || i >= h.cards.len() {
    return "";
  }
  let c: Str = h.comments[i];
  return c;
}

/// Index of the first card whose keyword matches `keyword` ignoring ASCII
/// case, or -1 when absent.
///
/// Lookup is a linear first-match scan in file order, so with duplicate
/// keywords the earliest card wins; blank-keyword cards never match, and an
/// empty query returns -1. Complexity: O(cards * keyword length).
pub fn fits_find(h: &FitsHeader, keyword: Str) -> Int {
  let q = _trim_end_spaces(keyword);
  if q.len() == 0 {
    return -1;
  }
  var i = 0;
  while i < h.cards.len() {
    let k: Str = h.keywords[i];
    if compare.str_compare(k, "") != 0 && _ci_eq(k, q) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Decoded string value of the first card matching `keyword`; None when the
/// keyword is absent or its card is not of kind FITK_STR.
/// Complexity: O(cards * keyword length).
pub fn fits_str_value(h: &FitsHeader, keyword: Str) -> Option[Str] {
  let i = fits_find(h, keyword);
  if i < 0 {
    return None;
  }
  let k: Int = h.kinds[i];
  if k != FITK_STR {
    return None;
  }
  let v: Str = h.values[i];
  return Some(v);
}

/// Logical value of the first card matching `keyword`; None when the keyword
/// is absent or its card is not of kind FITK_LOGICAL.
/// Complexity: O(cards * keyword length).
pub fn fits_bool_value(h: &FitsHeader, keyword: Str) -> Option[Bool] {
  let i = fits_find(h, keyword);
  if i < 0 {
    return None;
  }
  let k: Int = h.kinds[i];
  if k != FITK_LOGICAL {
    return None;
  }
  let v: Str = h.values[i];
  if compare.str_compare(v, "T") == 0 {
    return Some(true);
  }
  return Some(false);
}

/// Raw integer token of the first card matching `keyword`; None when the
/// keyword is absent or its card is not of kind FITK_INT.
/// Complexity: O(cards * keyword length).
pub fn fits_int_token(h: &FitsHeader, keyword: Str) -> Option[Str] {
  let i = fits_find(h, keyword);
  if i < 0 {
    return None;
  }
  let k: Int = h.kinds[i];
  if k != FITK_INT {
    return None;
  }
  let v: Str = h.values[i];
  return Some(v);
}

/// Raw real token of the first card matching `keyword`; None when the
/// keyword is absent or its card is not of kind FITK_REAL.
/// Complexity: O(cards * keyword length).
pub fn fits_float_token(h: &FitsHeader, keyword: Str) -> Option[Str] {
  let i = fits_find(h, keyword);
  if i < 0 {
    return None;
  }
  let k: Int = h.kinds[i];
  if k != FITK_REAL {
    return None;
  }
  let v: Str = h.values[i];
  return Some(v);
}

/// Comment of the first card matching `keyword`; "" when the keyword is
/// absent or the card has no comment.
/// Complexity: O(cards * keyword length).
pub fn fits_comment_of(h: &FitsHeader, keyword: Str) -> Str {
  let i = fits_find(h, keyword);
  if i < 0 {
    return "";
  }
  let c: Str = h.comments[i];
  return c;
}
