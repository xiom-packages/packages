// XIOM -- xiom.preprocess: configurable text normalization pipeline
// Port task: replace the xiom.preprocess placeholder with a real, tested,
// pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The pipeline order is FIXED: fold -> punct -> ws -> stopwords. Every step is
// also a public function; pp_pipeline applies the selected subset in exactly
// that order, and pp_normalize_default is the fold + punct + ws preset.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; every scan is byte-wise over the input Str
//     (xiom.string.byte_at) and all guards work on widened Int bytes
//     ((byte as Int) & 0xFF).
//   * Output bytes are collected in a Vec[UInt8] and materialized once per
//     result with xiom.string.builder.sb_to_str.
//   * Every Str comparison goes through xiom.string.compare.str_compare --
//     never `==` -- and every Vec[Str] element read goes to a typed local
//     first (BUG 17: `==` on Str read from Vec[Str] lowers to a pointer
//     comparison).
//
// Infallible by design: every function returns Str (or Int) and no step
// reports an error. ASCII-oriented: see README.md and SPEC.md.

module xiom.preprocess

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Byte constants (Int space)
// --------------------------------------------------

const _PP_TAB: Int = 9;
const _PP_LF: Int = 10;
const _PP_CR: Int = 13;
const _PP_SPACE: Int = 32;

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

// True for an ASCII uppercase letter byte (0x41-0x5A).
fn _pp_is_upper(v: Int) -> Bool {
  return v >= 65 && v <= 90;
}

// True for an ASCII lowercase letter byte (0x61-0x7A).
fn _pp_is_lower(v: Int) -> Bool {
  return v >= 97 && v <= 122;
}

// True for an ASCII digit byte (0x30-0x39).
fn _pp_is_digit(v: Int) -> Bool {
  return v >= 48 && v <= 57;
}

// True for the pp_strip_punct keep set: ASCII letter, ASCII digit or the
// space byte (0x20). Tabs, newlines and every byte >= 0x80 are dropped.
fn _pp_is_text_byte(v: Int) -> Bool {
  if _pp_is_upper(v) {
    return true;
  }
  if _pp_is_lower(v) {
    return true;
  }
  if _pp_is_digit(v) {
    return true;
  }
  return v == _PP_SPACE;
}

// True for the whitespace class shared by pp_collapse_ws and
// pp_remove_stopwords: space, tab, LF or CR.
fn _pp_is_ws(v: Int) -> Bool {
  if v == _PP_SPACE {
    return true;
  }
  if v == _PP_TAB {
    return true;
  }
  if v == _PP_LF {
    return true;
  }
  return v == _PP_CR;
}

// True when `folded` exactly matches none of the already folded stopwords.
// Exact match, so a stopword "the" never removes the token "theater".
fn _pp_keeps_token(folded: Str, folded_stops: &Vec[Str]) -> Bool {
  var i = 0;
  while i < folded_stops.len() {
    let fsw: Str = folded_stops[i];
    if compare.str_compare(folded, fsw) == 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Fold ASCII uppercase letters to lowercase; keep every other byte.
/// Params: s - the text to fold.
/// Returns: s with every byte in A-Z (0x41-0x5A) shifted to a-z; all other
/// bytes -- digits, punctuation, whitespace and every non-ASCII byte -- pass
/// through byte-exact, so the result has the same length as the input.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn pp_fold_ascii(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    let v: Int = (b as Int) & 0xFF;
    if _pp_is_upper(v) {
      out.push((v + 32) as UInt8);
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Drop every byte that is not an ASCII letter, ASCII digit or space.
/// Params: s - the text to strip.
/// Returns: s keeping only [A-Za-z0-9] and the space byte (0x20); all other
/// bytes -- marks, underscores, tabs, newlines, CR and every byte >= 0x80 --
/// are removed, not replaced, so words joined by punctuation fuse ("a-b" ->
/// "ab") and a tab-separated pair loses its separator ("a\tb" -> "ab").
/// Error case: none.
/// Complexity: O(s.len()).
pub fn pp_strip_punct(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    let v: Int = (b as Int) & 0xFF;
    if _pp_is_text_byte(v) {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Collapse whitespace runs to one space and trim both ends.
/// Params: s - the text to normalize.
/// Returns: s with every maximal run of space, tab, LF or CR replaced by a
/// single space, leading and trailing whitespace removed, and every other
/// byte passed through unchanged. The result is either "" or starts and ends
/// with a non-whitespace byte and contains no two adjacent whitespace bytes,
/// so the function is idempotent.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn pp_collapse_ws(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var pending = false;
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    let v: Int = (b as Int) & 0xFF;
    if _pp_is_ws(v) {
      pending = true;
    } else {
      if pending && out.len() > 0 {
        out.push(_PP_SPACE as UInt8);
      }
      pending = false;
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Remove stopwords from whitespace-separated text.
/// Params: s - the text to filter; stop - the stopword list.
/// Returns: s split into tokens on runs of space, tab, LF or CR; a token is
/// dropped when its ASCII-folded copy exactly matches the ASCII-folded copy
/// of some stopword (case-insensitive, never a substring match, so "the"
/// does not remove "theater"). Kept tokens retain their original bytes and
/// order and are rejoined with single spaces, so leading/trailing whitespace
/// and whitespace runs are normalized away. Empty input, an empty stop list
/// and an empty entry in the stop list never remove anything; tokens are
/// never empty, so an empty stopword matches nothing.
/// Error case: none.
/// Complexity: O(s.len() + |s| * |stop| * word length).
pub fn pp_remove_stopwords(s: Str, stop: &Vec[Str]) -> Str {
  // Fold the stop list once; all further matching uses these copies.
  var folded_stops = Vec[Str].new();
  var si = 0;
  while si < stop.len() {
    let sw: Str = stop[si];
    folded_stops.push(pp_fold_ascii(sw));
    si = si + 1;
  }
  // Split the input into whitespace-separated tokens.
  var tokens = Vec[Str].new();
  let n = s.len();
  var in_token = false;
  var start = 0;
  var i = 0;
  while i < n {
    let v: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if _pp_is_ws(v) {
      if in_token {
        tokens.push(string.str_slice(s, start, i));
        in_token = false;
      }
    } else {
      if !in_token {
        in_token = true;
        start = i;
      }
    }
    i = i + 1;
  }
  if in_token {
    tokens.push(string.str_slice(s, start, n));
  }
  // Keep the tokens that survive, joined with single spaces.
  var out = Vec[UInt8].new();
  var kept_any = false;
  var k = 0;
  while k < tokens.len() {
    let token: Str = tokens[k];
    let folded = pp_fold_ascii(token);
    if _pp_keeps_token(folded, &folded_stops) {
      if kept_any {
        out.push(_PP_SPACE as UInt8);
      }
      builder.sb_push_str(&mut out, token);
      kept_any = true;
    }
    k = k + 1;
  }
  return builder.sb_to_str(&out);
}

/// Count words in the pp_collapse_ws-normalized text.
/// Params: s - the text to count.
/// Returns: the number of whitespace-separated tokens of pp_collapse_ws(s);
/// 0 when s is empty or whitespace-only, 1 for a single token, and the
/// number of single spaces plus one otherwise.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn pp_word_count(s: Str) -> Int {
  let c = pp_collapse_ws(s);
  let n = c.len();
  if n == 0 {
    return 0;
  }
  var count = 1;
  var i = 0;
  while i < n {
    let v: Int = (string.byte_at(c, i) as Int) & 0xFF;
    if v == _PP_SPACE {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

/// Run the selected normalization steps in the fixed order.
/// Params: s - the text; stop - the stopword list used by the stopwords step;
/// fold, punct, ws, stopw - per-step switches (false skips that step).
/// Returns: s with the enabled steps applied in this fixed order:
///   1. fold      -- pp_fold_ascii(s),
///   2. punct     -- pp_strip_punct(...),
///   3. ws        -- pp_collapse_ws(...),
///   4. stopwords -- pp_remove_stopwords(..., stop).
/// The order is part of the contract: punctuation is stripped before the
/// stopwords pass, so "A, B" with stopword "a" leaves "b", while running
/// stopwords first would leave "A, B" (the token "a," does not match).
/// All steps are infallible.
/// Error case: none.
/// Complexity: the sum of the enabled steps' complexity.
pub fn pp_pipeline(s: Str, stop: &Vec[Str], fold: Bool, punct: Bool, ws: Bool, stopw: Bool) -> Str {
  var out = s;
  if fold {
    out = pp_fold_ascii(out);
  }
  if punct {
    out = pp_strip_punct(out);
  }
  if ws {
    out = pp_collapse_ws(out);
  }
  if stopw {
    out = pp_remove_stopwords(out, stop);
  }
  return out;
}

/// The default preset: fold + punct + ws, no stopwords.
/// Params: s - the text to normalize.
/// Returns: the fold + punct + ws preset, i.e.
/// pp_collapse_ws(pp_strip_punct(pp_fold_ascii(s))) -- equivalent to
/// pp_pipeline(s, <empty stop list>, true, true, true, false).
/// Error case: none.
/// Complexity: O(s.len()).
pub fn pp_normalize_default(s: Str) -> Str {
  return pp_collapse_ws(pp_strip_punct(pp_fold_ascii(s)));
}
