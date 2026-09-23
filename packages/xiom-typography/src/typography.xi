// XIOM -- xiom.typography: typographic prettification for plain text
// Port task: replace the xiom.typography placeholder with a pure-XIOM module
// (no FFI); every transformation is byte-based and locale-independent.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The module converts ASCII conventions into typographic punctuation:
// straight quotes into curly quotes, hyphen runs into en/em dashes, three
// dots into an ellipsis, and runs of spaces/tabs into one space. All Unicode
// output is emitted as explicit UTF-8 byte sequences (three bytes per
// character) through xiom.string.builder -- see the byte table in SPEC.md.
//
// Scanning is byte-wise over the UTF-8 buffer: ASCII trigger bytes can never
// occur inside a multi-byte sequence (continuation bytes are >= 0x80), so
// non-ASCII text passes through byte-exact. Quote direction is decided by the
// byte context that precedes the quote (start of string, whitespace, an
// opening bracket, or a dash); everything else is a closing quote. The
// heuristics are deliberately simple ASCII conventions, documented in
// README.md under Limitations.
//
// Byte reads are normalized to Int with `(byte_at(s, i) as Int) & 0xFF`
// before comparison (stdlib idiom): a direct UInt8 comparison of a byte_at
// result misses values >= 128 on v0.61.3. Output bytes are pushed as UInt8.
//
// Complexity: every function is O(n) over the input bytes and allocates once
// (the final builder materialization).

module xiom.typography

use xiom.string;
use xiom.string.builder;

// -- ASCII trigger bytes (Int domain, see the header note) --------------------

const _TYP_SQUOTE: Int = 39;    // '
const _TYP_DQUOTE: Int = 34;    // "
const _TYP_HYPHEN: Int = 45;    // -
const _TYP_DOT: Int = 46;       // .
const _TYP_SPACE: Int = 32;     // space
const _TYP_TAB: Int = 9;        // tab
const _TYP_LF: Int = 10;        // newline
const _TYP_CR: Int = 13;        // carriage return
const _TYP_LPAREN: Int = 40;    // (
const _TYP_LBRACKET: Int = 91;  // [
const _TYP_LBRACE: Int = 123;   // {
const _TYP_LT: Int = 60;        // <

// -- UTF-8 emission bytes (0xE2 0x80 <third>) ---------------------------------
// U+2018 = E2 80 98, U+2019 = E2 80 99, U+201C = E2 80 9C, U+201D = E2 80 9D,
// U+2013 = E2 80 93, U+2014 = E2 80 94, U+2026 = E2 80 A6. The decimal values
// below are those byte sequences; the glyph table lives in SPEC.md.

const _TYP_UTF8_B0: Int = 226;      // 0xE2, first byte of all seven
const _TYP_UTF8_B1: Int = 128;      // 0x80, second byte of all seven
const _TYP_LSQUO_B2: Int = 152;     // 0x98 -> U+2018 left single quote
const _TYP_RSQUO_B2: Int = 153;     // 0x99 -> U+2019 right single quote
const _TYP_LDQUO_B2: Int = 156;     // 0x9C -> U+201C left double quote
const _TYP_RDQUO_B2: Int = 157;     // 0x9D -> U+201D right double quote
const _TYP_ENDASH_B2: Int = 147;    // 0x93 -> U+2013 en dash
const _TYP_EMDASH_B2: Int = 148;    // 0x94 -> U+2014 em dash
const _TYP_ELLIPSIS_B2: Int = 166;  // 0xA6 -> U+2026 horizontal ellipsis

// One byte of `s` at `i`, zero-extended to Int (0..255).
fn _byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True when the two bytes before `last` in a UTF-8 stream are E2 80, i.e.
// `last` completes a three-byte character emitted by this module.
fn _preceded_by_e2_80(s: Str, i: Int) -> Bool {
  if i < 3 {
    return false;
  }
  if _byte_at(s, i - 3) != _TYP_UTF8_B0 {
    return false;
  }
  return _byte_at(s, i - 2) == _TYP_UTF8_B1;
}

// True when the byte at `i - 1` is a dash in an opening-quote context: the
// ASCII hyphen or an already-converted en/em dash (so quotes still open after
// typography_smart_dashes has run, which is the typography_smart order).
fn _preceded_by_dash(s: Str, i: Int) -> Bool {
  if i < 1 {
    return false;
  }
  if _byte_at(s, i - 1) == _TYP_HYPHEN {
    return true;
  }
  if !_preceded_by_e2_80(s, i) {
    return false;
  }
  let b2 = _byte_at(s, i - 1);
  if b2 == _TYP_ENDASH_B2 {
    return true;
  }
  return b2 == _TYP_EMDASH_B2;
}

// True when a quote at byte offset `i` opens: at start of string, after
// whitespace, after an opening bracket (( [ { <), or after a dash.
fn _quote_opens(s: Str, i: Int) -> Bool {
  if i == 0 {
    return true;
  }
  let p = _byte_at(s, i - 1);
  if p == _TYP_SPACE || p == _TYP_TAB || p == _TYP_LF || p == _TYP_CR {
    return true;
  }
  if p == _TYP_LPAREN || p == _TYP_LBRACKET || p == _TYP_LBRACE || p == _TYP_LT {
    return true;
  }
  return _preceded_by_dash(s, i);
}

/// Convert straight ASCII quotes to typographic curly quotes.
/// Params: s - the input text (UTF-8 bytes are preserved verbatim).
/// Rules: a `'` or `"` opens (becomes U+2018 / U+201C) at start of string,
/// after ASCII whitespace, after an opening bracket `( [ { <`, or after a
/// dash (ASCII `-` or an en/em dash); otherwise it closes (U+2019 / U+201D),
/// which turns apostrophes like "don't" into "don't".
/// Returns: the converted text; no other bytes change.
/// Error case: none.
/// Complexity: O(n).
pub fn typography_smart_quotes(s: Str) -> Str {
  var sb = builder.sb_new();
  let len = s.len();
  var i = 0;
  while i < len {
    let b = _byte_at(s, i);
    if b == _TYP_SQUOTE {
      if _quote_opens(s, i) {
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B0 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B1 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_LSQUO_B2 as UInt8);
      } else {
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B0 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B1 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_RSQUO_B2 as UInt8);
      }
      i = i + 1;
    } elif b == _TYP_DQUOTE {
      if _quote_opens(s, i) {
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B0 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B1 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_LDQUO_B2 as UInt8);
      } else {
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B0 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B1 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_RDQUO_B2 as UInt8);
      }
      i = i + 1;
    } else {
      builder.sb_push_byte(&mut sb, b as UInt8);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&sb);
}

/// Convert runs of ASCII hyphens to typographic dashes, longest match first.
/// Params: s - the input text.
/// Rules: leftmost `---` becomes an em dash (U+2014), leftmost `--` becomes
/// an en dash (U+2013) -- triple hyphens are tested before double ones, so
/// `---` never becomes `-` + en dash. `----` yields em dash + `-`; a single
/// `-` is untouched.
/// Returns: the converted text; no other bytes change.
/// Error case: none.
/// Complexity: O(n).
pub fn typography_smart_dashes(s: Str) -> Str {
  var sb = builder.sb_new();
  let len = s.len();
  var i = 0;
  while i < len {
    let b = _byte_at(s, i);
    if b == _TYP_HYPHEN {
      if i + 2 < len && _byte_at(s, i + 1) == _TYP_HYPHEN && _byte_at(s, i + 2) == _TYP_HYPHEN {
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B0 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B1 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_EMDASH_B2 as UInt8);
        i = i + 3;
      } elif i + 1 < len && _byte_at(s, i + 1) == _TYP_HYPHEN {
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B0 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B1 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_ENDASH_B2 as UInt8);
        i = i + 2;
      } else {
        builder.sb_push_byte(&mut sb, b as UInt8);
        i = i + 1;
      }
    } else {
      builder.sb_push_byte(&mut sb, b as UInt8);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&sb);
}

/// Convert three consecutive ASCII dots to a single ellipsis character.
/// Params: s - the input text.
/// Rules: leftmost `...` becomes U+2026; leftover dots stay literal, so
/// `....` yields an ellipsis followed by one `.`.
/// Returns: the converted text; no other bytes change.
/// Error case: none.
/// Complexity: O(n).
pub fn typography_ellipsis(s: Str) -> Str {
  var sb = builder.sb_new();
  let len = s.len();
  var i = 0;
  while i < len {
    let b = _byte_at(s, i);
    if b == _TYP_DOT {
      if i + 2 < len && _byte_at(s, i + 1) == _TYP_DOT && _byte_at(s, i + 2) == _TYP_DOT {
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B0 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_UTF8_B1 as UInt8);
        builder.sb_push_byte(&mut sb, _TYP_ELLIPSIS_B2 as UInt8);
        i = i + 3;
      } else {
        builder.sb_push_byte(&mut sb, b as UInt8);
        i = i + 1;
      }
    } else {
      builder.sb_push_byte(&mut sb, b as UInt8);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&sb);
}

/// Collapse runs of ASCII spaces and tabs to a single space.
/// Params: s - the input text.
/// Rules: every maximal run of bytes in {space, tab} becomes one space
/// (U+0020); LF and CR are not part of a run and are preserved verbatim, so
/// line structure survives. Nothing is trimmed: leading and trailing runs
/// collapse to one space each.
/// Returns: the collapsed text; no other bytes change.
/// Error case: none.
/// Complexity: O(n).
pub fn typography_collapse_spaces(s: Str) -> Str {
  var sb = builder.sb_new();
  let len = s.len();
  var i = 0;
  while i < len {
    let b = _byte_at(s, i);
    if b == _TYP_SPACE || b == _TYP_TAB {
      builder.sb_push_byte(&mut sb, _TYP_SPACE as UInt8);
      while i < len {
        let c = _byte_at(s, i);
        if c == _TYP_SPACE || c == _TYP_TAB {
          i = i + 1;
        } else {
          break;
        }
      }
    } else {
      builder.sb_push_byte(&mut sb, b as UInt8);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&sb);
}

/// Apply the full typographic pipeline.
/// Params: s - the input text.
/// Rules: ellipsis first, then dashes, then quotes, then space collapsing
/// (dashes before quotes so a quote after a converted dash still opens;
/// collapsing last so quote decisions see the original spacing).
/// Returns: typography_collapse_spaces(typography_smart_quotes(
/// typography_smart_dashes(typography_ellipsis(s)))).
/// Error case: none.
/// Complexity: O(n).
pub fn typography_smart(s: Str) -> Str {
  let after_ellipsis = typography_ellipsis(s);
  let after_dashes = typography_smart_dashes(after_ellipsis);
  let after_quotes = typography_smart_quotes(after_dashes);
  return typography_collapse_spaces(after_quotes);
}
