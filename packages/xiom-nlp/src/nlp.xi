// XIOM -- xiom.nlp: deterministic byte-oriented text analysis
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (SPEC.md states the exact semantics):
//   * tokenizer    -- runs of [A-Za-z0-9'] as words, byte offsets per token;
//   * ASCII case   -- byte lowercasing and case-insensitive comparison;
//   * sentences    -- split on . ! ? before whitespace/end, with an
//                     abbreviation guard list and a decimal-number guard;
//   * Porter stem  -- Porter's 1980 algorithm (steps 1a..5b) over a
//                     lowercase ASCII word, plus its measure/contains-vowel/
//                     ends-with predicates;
//   * statistics   -- token count, total/average token length, and a
//                     distinct-stemmed-forms counter (bounded O(n^2)).
//
// Everything is byte-oriented: no Unicode tables, no locale, no allocation
// beyond the vectors and strings each call returns. A byte >= 128 is a
// separator to the tokenizer, is passed through by the case helpers, and is
// rejected (with its offset) by the checked stemmer.
//
// Language notes (XIOM v0.61.3):
//   * free functions only; no methods, lambdas, or function values;
//   * Str values are compared through xiom.string.compare.str_compare,
//     never with `==` (BUG 17);
//   * Ok/Err for the checked stemmer are constructed only in the leaf
//     helpers _ok_stem/_err_stem;
//   * Vec elements are bound to typed locals before use, and bytes widened
//     to Int are masked with 0xFF before any comparison with a byte >= 128;
//   * `&mut` out-parameters miscompile, so every transformation returns a
//     fresh Vec instead of writing through a reference.

module xiom.nlp

use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Public data model
// --------------------------------------------------

/// Diagnostic error carrying a byte offset into the input that produced it.
///   code 1 = non-ASCII byte; offset = index of the first byte >= 128.
///   code 2 = empty input; offset = 0.
pub type NlpError = {
  code: Int;
  offset: Int;
}

/// A tokenized text: `text` is the source, and token i occupies
/// [starts[i], ends[i]) in it. The three fields are parallel.
pub type NlpTokens = {
  text: Str;
  starts: Vec[Int];
  ends: Vec[Int];
}

/// Sentence spans over a source text: sentence i occupies
/// [starts[i], ends[i]) in `text`. Spans never include leading or trailing
/// whitespace. The three fields are parallel.
pub type NlpSentences = {
  text: Str;
  starts: Vec[Int];
  ends: Vec[Int];
}

// --------------------------------------------------
//  Leaf constructors (see the module header)
// --------------------------------------------------

fn _make_tokens(text: Str, starts: Vec[Int], ends: Vec[Int]) -> NlpTokens {
  return NlpTokens {
    text: text;
    starts: starts;
    ends: ends;
  };
}

fn _make_sentences(text: Str, starts: Vec[Int], ends: Vec[Int]) -> NlpSentences {
  return NlpSentences {
    text: text;
    starts: starts;
    ends: ends;
  };
}

fn _ok_stem(v: Vec[UInt8]) -> Result[Vec[UInt8], NlpError] {
  return Ok(v);
}

fn _err_stem(code: Int, offset: Int) -> Result[Vec[UInt8], NlpError] {
  return Err(NlpError { code: code; offset: offset; });
}

// --------------------------------------------------
//  Byte constants and predicates
// --------------------------------------------------

const _TAB: UInt8 = 9u8;
const _LF: UInt8 = 10u8;
const _CR: UInt8 = 13u8;
const _SPACE: UInt8 = 32u8;
const _BANG: UInt8 = 33u8;
const _APOS: UInt8 = 39u8;
const _DOT: UInt8 = 46u8;
const _QUEST: UInt8 = 63u8;
const _UP_A: UInt8 = 65u8;
const _UP_Z: UInt8 = 90u8;
const _LO_A: UInt8 = 97u8;
const _LO_Z: UInt8 = 122u8;
const _D0: UInt8 = 48u8;
const _D9: UInt8 = 57u8;
const _BYTE_E: UInt8 = 101u8;
const _BYTE_L: UInt8 = 108u8;
const _BYTE_S: UInt8 = 115u8;
const _BYTE_W: UInt8 = 119u8;
const _BYTE_X: UInt8 = 120u8;
const _BYTE_Y: UInt8 = 121u8;
const _BYTE_Z: UInt8 = 122u8;

// Word byte: ASCII letter, digit, or apostrophe.
fn _is_word_byte(b: UInt8) -> Bool {
  if b >= _UP_A && b <= _UP_Z { return true; }
  if b >= _LO_A && b <= _LO_Z { return true; }
  if b >= _D0 && b <= _D9 { return true; }
  return b == _APOS;
}

// Sentence-separating whitespace: space, tab, LF or CR.
fn _is_space_byte(b: UInt8) -> Bool {
  return b == _SPACE || b == _TAB || b == _LF || b == _CR;
}

// ASCII digit byte.
fn _is_digit_byte(b: UInt8) -> Bool {
  return b >= _D0 && b <= _D9;
}

// --------------------------------------------------
//  ASCII case helpers
// --------------------------------------------------

/// Lowercase one ASCII byte: A-Z become a-z, every other byte (including
/// bytes >= 128) is returned unchanged.
pub fn nlp_lower_byte(b: UInt8) -> UInt8 {
  let v: Int = (b as Int) & 0xFF;
  if v >= 65 && v <= 90 {
    return ((v + 32) as UInt8);
  }
  return b;
}

/// Lowercased copy of a byte vector (ASCII A-Z only).
pub fn nlp_lower_bytes(word: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < word.len() {
    let b: UInt8 = word[i];
    out.push(nlp_lower_byte(b));
    i = i + 1;
  }
  return out;
}

/// Lowercased copy of a Str. Only ASCII A-Z are changed, so a valid UTF-8
/// input stays valid UTF-8 and no byte is dropped or inserted.
pub fn nlp_lower_str(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(nlp_lower_byte(string.byte_at(s, i)));
    i = i + 1;
  }
  return Str::from_utf8(out);
}

/// Case-insensitive byte equality (ASCII A-Z only); lengths must match.
pub fn nlp_ci_equals(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    let lx: UInt8 = nlp_lower_byte(x);
    let ly: UInt8 = nlp_lower_byte(y);
    let vx: Int = (lx as Int) & 0xFF;
    let vy: Int = (ly as Int) & 0xFF;
    if vx != vy { return false; }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Tokenizer
// --------------------------------------------------

/// Split `text` into tokens: maximal runs of [A-Za-z0-9']. Every other byte
/// (whitespace, punctuation, bytes >= 128) is a separator and is not part of
/// any token. Tokens carry start/end byte offsets and are never empty.
pub fn nlp_tokenize(text: Str) -> NlpTokens {
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  let n = text.len();
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(text, i);
    if _is_word_byte(b) {
      let start = i;
      var j = i;
      var go = true;
      while j < n && go {
        let c: UInt8 = string.byte_at(text, j);
        if _is_word_byte(c) { j = j + 1; } else { go = false; }
      }
      starts.push(start);
      ends.push(j);
      i = j;
    } else {
      i = i + 1;
    }
  }
  return _make_tokens(text, starts, ends);
}

/// Number of tokens.
pub fn nlp_token_count(t: &NlpTokens) -> Int {
  return t.starts.len();
}

/// Start byte offset of token `i`; -1 when `i` is negative or out of range.
pub fn nlp_token_start(t: &NlpTokens, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= t.starts.len() { return -1; }
  let x: Int = t.starts[i];
  return x;
}

/// End byte offset (exclusive) of token `i`; -1 when `i` is negative or out
/// of range.
pub fn nlp_token_end(t: &NlpTokens, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= t.ends.len() { return -1; }
  let x: Int = t.ends[i];
  return x;
}

/// Text of token `i` ("" when `i` is negative or out of range).
pub fn nlp_token_text(t: &NlpTokens, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= t.starts.len() { return ""; }
  let s: Int = t.starts[i];
  let e: Int = t.ends[i];
  let src: Str = t.text;
  return string.str_slice(src, s, e);
}

/// Bytes of token `i` (empty when `i` is negative or out of range).
pub fn nlp_token_bytes(t: &NlpTokens, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 { return out; }
  if i >= t.starts.len() { return out; }
  let s: Int = t.starts[i];
  let e: Int = t.ends[i];
  let src: Str = t.text;
  var k = s;
  while k < e {
    out.push(string.byte_at(src, k));
    k = k + 1;
  }
  return out;
}

/// Case-sensitive comparison of token `i` with `word` (false when `i` is out
/// of range).
pub fn nlp_token_equals(t: &NlpTokens, i: Int, word: Str) -> Bool {
  if i < 0 { return false; }
  if i >= t.starts.len() { return false; }
  let s: Int = t.starts[i];
  let e: Int = t.ends[i];
  let src: Str = t.text;
  let slice: Str = string.str_slice(src, s, e);
  return compare.str_compare(slice, word) == 0;
}

/// Case-insensitive comparison of token `i` with `word` (ASCII A-Z only;
/// false when `i` is out of range or the lengths differ).
pub fn nlp_token_equals_ci(t: &NlpTokens, i: Int, word: Str) -> Bool {
  if i < 0 { return false; }
  if i >= t.starts.len() { return false; }
  let s: Int = t.starts[i];
  let e: Int = t.ends[i];
  if e - s != word.len() { return false; }
  let src: Str = t.text;
  var k = 0;
  while k < word.len() {
    let a: UInt8 = string.byte_at(src, s + k);
    let b: UInt8 = string.byte_at(word, k);
    let la: UInt8 = nlp_lower_byte(a);
    let lb: UInt8 = nlp_lower_byte(b);
    let va: Int = (la as Int) & 0xFF;
    let vb: Int = (lb as Int) & 0xFF;
    if va != vb { return false; }
    k = k + 1;
  }
  return true;
}

// --------------------------------------------------
//  Sentence splitter
// --------------------------------------------------

// Case-insensitive "text[0..end_excl) ends with abbr" test.
fn _abbrev_ends(text: Str, end_excl: Int, abbr: Str) -> Bool {
  let n = abbr.len();
  if n > end_excl { return false; }
  let start = end_excl - n;
  var i = 0;
  while i < n {
    let tb: UInt8 = string.byte_at(text, start + i);
    let ab: UInt8 = string.byte_at(abbr, i);
    let lt: UInt8 = nlp_lower_byte(tb);
    let la: UInt8 = nlp_lower_byte(ab);
    let vt: Int = (lt as Int) & 0xFF;
    let va: Int = (la as Int) & 0xFF;
    if vt != va { return false; }
    i = i + 1;
  }
  return true;
}

// True when text[0..end_excl) ends with one of the guard abbreviations
// (each written with its trailing "dot"). Case-insensitive.
fn _is_abbreviation(text: Str, end_excl: Int) -> Bool {
  if _abbrev_ends(text, end_excl, "mr.") { return true; }
  if _abbrev_ends(text, end_excl, "mrs.") { return true; }
  if _abbrev_ends(text, end_excl, "dr.") { return true; }
  if _abbrev_ends(text, end_excl, "ms.") { return true; }
  if _abbrev_ends(text, end_excl, "prof.") { return true; }
  if _abbrev_ends(text, end_excl, "st.") { return true; }
  if _abbrev_ends(text, end_excl, "vs.") { return true; }
  if _abbrev_ends(text, end_excl, "etc.") { return true; }
  if _abbrev_ends(text, end_excl, "e.g.") { return true; }
  if _abbrev_ends(text, end_excl, "i.e.") { return true; }
  return false;
}

// True when the first non-whitespace byte at or after `from` is a digit.
fn _next_nonspace_is_digit(text: Str, from: Int) -> Bool {
  let n = text.len();
  var k = from;
  var go = true;
  while k < n && go {
    let b: UInt8 = string.byte_at(text, k);
    if _is_space_byte(b) { k = k + 1; } else { go = false; }
  }
  if k >= n { return false; }
  return _is_digit_byte(string.byte_at(text, k));
}

// True when position `i` in `text` ends a sentence: the byte is . ! ? and it
// is followed by whitespace or the end of the text. A "." is additionally
// suppressed when it ends one of the guard abbreviations, or when it sits
// between ASCII digits (skipping whitespace after the dot), which keeps
// decimal numbers such as "3.14" and "3. 14" in one sentence.
fn _is_boundary(text: Str, i: Int) -> Bool {
  let n = text.len();
  let b: UInt8 = string.byte_at(text, i);
  var is_term = false;
  if b == _DOT || b == _BANG || b == _QUEST { is_term = true; }
  if !is_term { return false; }
  var followed = false;
  if i + 1 >= n {
    followed = true;
  } else {
    let nx: UInt8 = string.byte_at(text, i + 1);
    if _is_space_byte(nx) { followed = true; }
  }
  if !followed { return false; }
  if b == _DOT {
    if _is_abbreviation(text, i + 1) { return false; }
    if i > 0 {
      let pv: UInt8 = string.byte_at(text, i - 1);
      if _is_digit_byte(pv) && _next_nonspace_is_digit(text, i + 1) {
        return false;
      }
    }
  }
  return true;
}

/// Split `text` into sentences. A sentence ends at a "." / "!" / "?" that is
/// followed by whitespace or the end of the text; "." does not end a
/// sentence after a guard abbreviation, nor between digits with only
/// whitespace after the dot. A trailing chunk without a terminator is also a
/// sentence. Spans exclude surrounding whitespace and are empty-input safe.
pub fn nlp_sentences(text: Str) -> NlpSentences {
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  let n = text.len();
  var i = 0;
  var sstart = -1;
  while i < n {
    if sstart < 0 {
      let b: UInt8 = string.byte_at(text, i);
      if !_is_space_byte(b) { sstart = i; }
    }
    if sstart >= 0 && _is_boundary(text, i) {
      starts.push(sstart);
      ends.push(i + 1);
      sstart = -1;
    }
    i = i + 1;
  }
  if sstart >= 0 {
    var e = n;
    var go = true;
    while e > sstart && go {
      let b: UInt8 = string.byte_at(text, e - 1);
      if _is_space_byte(b) { e = e - 1; } else { go = false; }
    }
    if e > sstart {
      starts.push(sstart);
      ends.push(e);
    }
  }
  return _make_sentences(text, starts, ends);
}

/// Number of sentences.
pub fn nlp_sentence_count(s: &NlpSentences) -> Int {
  return s.starts.len();
}

/// Start byte offset of sentence `i`; -1 when `i` is negative or out of
/// range.
pub fn nlp_sentence_start(s: &NlpSentences, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= s.starts.len() { return -1; }
  let x: Int = s.starts[i];
  return x;
}

/// End byte offset (exclusive) of sentence `i`; -1 when `i` is negative or
/// out of range.
pub fn nlp_sentence_end(s: &NlpSentences, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= s.ends.len() { return -1; }
  let x: Int = s.ends[i];
  return x;
}

/// Text of sentence `i` ("" when `i` is negative or out of range).
pub fn nlp_sentence_text(s: &NlpSentences, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= s.starts.len() { return ""; }
  let a: Int = s.starts[i];
  let b: Int = s.ends[i];
  let src: Str = s.text;
  return string.str_slice(src, a, b);
}

// --------------------------------------------------
//  Porter stemmer: predicates and word helpers
// --------------------------------------------------

// True when word[k] is a consonant. 'y' is a consonant when it starts the
// word or follows a vowel; runs of 'y' are resolved by parity.
fn _porter_cons(w: &Vec[UInt8], k: Int) -> Bool {
  var i = k;
  var flips = 0;
  while i >= 0 {
    let b: UInt8 = w[i];
    if b == _BYTE_Y {
      flips = flips + 1;
      i = i - 1;
    } elif b == 97u8 || b == _BYTE_E || b == 105u8 || b == 111u8 || b == 117u8 {
      if flips % 2 == 1 { return true; }
      return false;
    } else {
      if flips % 2 == 1 { return false; }
      return true;
    }
  }
  if flips % 2 == 1 { return true; }
  return false;
}

// Measure m of word[0..j]: the number of vowel-run to consonant-run
// boundaries.
fn _measure_to(w: &Vec[UInt8], j: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < j {
    if !_porter_cons(w, i) && _porter_cons(w, i + 1) {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

// True when word[0..j] contains a vowel.
fn _contains_vowel_to(w: &Vec[UInt8], j: Int) -> Bool {
  var i = 0;
  while i <= j {
    if !_porter_cons(w, i) { return true; }
    i = i + 1;
  }
  return false;
}

// True when word[0..j] ends with a double consonant.
fn _ends_double_consonant_to(w: &Vec[UInt8], j: Int) -> Bool {
  if j < 1 { return false; }
  let last: UInt8 = w[j];
  let prev: UInt8 = w[j - 1];
  if last != prev { return false; }
  return _porter_cons(w, j);
}

// True when word[0..j] ends cvc and the final consonant is not w, x or y.
fn _ends_cvc_to(w: &Vec[UInt8], j: Int) -> Bool {
  if j < 2 { return false; }
  if !_porter_cons(w, j) { return false; }
  if _porter_cons(w, j - 1) { return false; }
  if !_porter_cons(w, j - 2) { return false; }
  let b: UInt8 = w[j];
  if b == _BYTE_W || b == _BYTE_X || b == _BYTE_Y { return false; }
  return true;
}

/// Porter measure m of the whole word: the number of VC sequences in
/// [C](VC)^m[V]. m is 0 for the empty word, for all-consonant and
/// all-vowel words.
pub fn nlp_measure(word: &Vec[UInt8]) -> Int {
  if word.len() == 0 { return 0; }
  return _measure_to(word, word.len() - 1);
}

/// True when the whole word contains a vowel ('y' counts as a vowel when it
/// follows a consonant; the first byte 'y' is a consonant).
pub fn nlp_contains_vowel(word: &Vec[UInt8]) -> Bool {
  if word.len() == 0 { return false; }
  return _contains_vowel_to(word, word.len() - 1);
}

/// True when the whole word ends with the given ASCII suffix.
pub fn nlp_ends_with(word: &Vec[UInt8], suffix: Str) -> Bool {
  let n = suffix.len();
  let len = word.len();
  if n > len { return false; }
  let start = len - n;
  var i = 0;
  while i < n {
    let got: UInt8 = word[start + i];
    let want: UInt8 = string.byte_at(suffix, i);
    let vg: Int = (got as Int) & 0xFF;
    let vw: Int = (want as Int) & 0xFF;
    if vg != vw { return false; }
    i = i + 1;
  }
  return true;
}

/// True when the whole word ends with a double consonant.
pub fn nlp_ends_double_consonant(word: &Vec[UInt8]) -> Bool {
  if word.len() == 0 { return false; }
  return _ends_double_consonant_to(word, word.len() - 1);
}

/// True when the whole word ends cvc with the final consonant not w, x or y
/// (the Porter *o condition).
pub fn nlp_ends_cvc(word: &Vec[UInt8]) -> Bool {
  if word.len() == 0 { return false; }
  return _ends_cvc_to(word, word.len() - 1);
}

// True when word[0..j] ends with the ASCII suffix.
fn _suffix_match(w: &Vec[UInt8], j: Int, suffix: Str) -> Bool {
  let n = suffix.len();
  if n > j + 1 { return false; }
  let start = j + 1 - n;
  var i = 0;
  while i < n {
    let got: UInt8 = w[start + i];
    let want: UInt8 = string.byte_at(suffix, i);
    let vg: Int = (got as Int) & 0xFF;
    let vw: Int = (want as Int) & 0xFF;
    if vg != vw { return false; }
    i = i + 1;
  }
  return true;
}

// Fresh copy of the first `keep` bytes.
fn _copy_prefix(w: &Vec[UInt8], keep: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < keep {
    let b: UInt8 = w[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

// Fresh copy of word[0..j] with the last n bytes removed.
fn _drop_last(w: &Vec[UInt8], j: Int, n: Int) -> Vec[UInt8] {
  return _copy_prefix(w, j + 1 - n);
}

// Fresh copy of word[0..j] followed by the bytes of text.
fn _append_str(w: &Vec[UInt8], j: Int, text: Str) -> Vec[UInt8] {
  var out = _copy_prefix(w, j + 1);
  var i = 0;
  while i < text.len() {
    out.push(string.byte_at(text, i));
    i = i + 1;
  }
  return out;
}

// Fresh copy of word[0..j] with the last n bytes replaced by the bytes of
// repl.
fn _replace_tail(w: &Vec[UInt8], j: Int, n: Int, repl: Str) -> Vec[UInt8] {
  var out = _copy_prefix(w, j + 1 - n);
  var i = 0;
  while i < repl.len() {
    out.push(string.byte_at(repl, i));
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Porter stemmer: steps (Porter 1980, Program 14(3):130-137)
// --------------------------------------------------

// Step 1a: SSES -> SS, IES -> I, SS -> SS, S -> (delete).
fn _step1a(w: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(w, j, "sses") { return _replace_tail(w, j, 4, "ss"); }
  if _suffix_match(w, j, "ies") { return _replace_tail(w, j, 3, "i"); }
  if _suffix_match(w, j, "ss") { return _copy_prefix(w, j + 1); }
  if _suffix_match(w, j, "s") { return _drop_last(w, j, 1); }
  return _copy_prefix(w, j + 1);
}

// Step 1b cleanup applied after ED / ING was cut: AT -> ATE, BL -> BLE,
// IZ -> IZE, a final double consonant loses one byte (unless it is L, S or
// Z), and a one-measure cvc word gains an E.
fn _step1b_after_cut(w: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(w, j, "at") { return _append_str(w, j, "e"); }
  if _suffix_match(w, j, "bl") { return _append_str(w, j, "e"); }
  if _suffix_match(w, j, "iz") { return _append_str(w, j, "e"); }
  if _ends_double_consonant_to(w, j) {
    let last: UInt8 = w[j];
    if last == _BYTE_L || last == _BYTE_S || last == _BYTE_Z {
      return _copy_prefix(w, j + 1);
    }
    return _drop_last(w, j, 1);
  }
  if _measure_to(w, j) == 1 && _ends_cvc_to(w, j) {
    return _append_str(w, j, "e");
  }
  return _copy_prefix(w, j + 1);
}

// Step 1b: (m>0) EED -> EE; (*v*) ED -> (delete); (*v*) ING -> (delete),
// with the cleanup above after the ED / ING cuts.
fn _step1b(w: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(w, j, "eed") {
    if _measure_to(w, j - 3) > 0 { return _drop_last(w, j, 1); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "ed") {
    if _contains_vowel_to(w, j - 2) {
      let cut = _drop_last(w, j, 2);
      return _step1b_after_cut(&cut, cut.len() - 1);
    }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "ing") {
    if _contains_vowel_to(w, j - 3) {
      let cut = _drop_last(w, j, 3);
      return _step1b_after_cut(&cut, cut.len() - 1);
    }
    return _copy_prefix(w, j + 1);
  }
  return _copy_prefix(w, j + 1);
}

// Step 1c: (*v*) Y -> I.
fn _step1c(w: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(w, j, "y") {
    if _contains_vowel_to(w, j - 1) {
      return _replace_tail(w, j, 1, "i");
    }
  }
  return _copy_prefix(w, j + 1);
}

// Step 2: the first matching suffix of the (m>0) table is replaced; a
// matched suffix whose stem has m == 0 stops the step.
fn _step2(w: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(w, j, "ational") {
    if _measure_to(w, j - 7) > 0 { return _replace_tail(w, j, 7, "ate"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "tional") {
    if _measure_to(w, j - 6) > 0 { return _replace_tail(w, j, 6, "tion"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "enci") {
    if _measure_to(w, j - 4) > 0 { return _replace_tail(w, j, 4, "ence"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "anci") {
    if _measure_to(w, j - 4) > 0 { return _replace_tail(w, j, 4, "ance"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "izer") {
    if _measure_to(w, j - 4) > 0 { return _replace_tail(w, j, 4, "ize"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "abli") {
    if _measure_to(w, j - 4) > 0 { return _replace_tail(w, j, 4, "able"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "alli") {
    if _measure_to(w, j - 4) > 0 { return _replace_tail(w, j, 4, "al"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "entli") {
    if _measure_to(w, j - 5) > 0 { return _replace_tail(w, j, 5, "ent"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "eli") {
    if _measure_to(w, j - 3) > 0 { return _replace_tail(w, j, 3, "e"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "ousli") {
    if _measure_to(w, j - 5) > 0 { return _replace_tail(w, j, 5, "ous"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "ization") {
    if _measure_to(w, j - 7) > 0 { return _replace_tail(w, j, 7, "ize"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "ation") {
    if _measure_to(w, j - 5) > 0 { return _replace_tail(w, j, 5, "ate"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "ator") {
    if _measure_to(w, j - 4) > 0 { return _replace_tail(w, j, 4, "ate"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "alism") {
    if _measure_to(w, j - 5) > 0 { return _replace_tail(w, j, 5, "al"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "iveness") {
    if _measure_to(w, j - 7) > 0 { return _replace_tail(w, j, 7, "ive"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "fulness") {
    if _measure_to(w, j - 7) > 0 { return _replace_tail(w, j, 7, "ful"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "ousness") {
    if _measure_to(w, j - 7) > 0 { return _replace_tail(w, j, 7, "ous"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "aliti") {
    if _measure_to(w, j - 5) > 0 { return _replace_tail(w, j, 5, "al"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "iviti") {
    if _measure_to(w, j - 5) > 0 { return _replace_tail(w, j, 5, "ive"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "biliti") {
    if _measure_to(w, j - 6) > 0 { return _replace_tail(w, j, 6, "ble"); }
    return _copy_prefix(w, j + 1);
  }
  return _copy_prefix(w, j + 1);
}

// Step 3: (m>0) ICATE -> IC, ATIVE -> (delete), ALIZE -> AL, ICITI -> IC,
// ICAL -> IC, FUL -> (delete), NESS -> (delete).
fn _step3(w: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(w, j, "icate") {
    if _measure_to(w, j - 5) > 0 { return _replace_tail(w, j, 5, "ic"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "ative") {
    if _measure_to(w, j - 5) > 0 { return _drop_last(w, j, 5); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "alize") {
    if _measure_to(w, j - 5) > 0 { return _replace_tail(w, j, 5, "al"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "iciti") {
    if _measure_to(w, j - 5) > 0 { return _replace_tail(w, j, 5, "ic"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "ical") {
    if _measure_to(w, j - 4) > 0 { return _replace_tail(w, j, 4, "ic"); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "ful") {
    if _measure_to(w, j - 3) > 0 { return _drop_last(w, j, 3); }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "ness") {
    if _measure_to(w, j - 4) > 0 { return _drop_last(w, j, 4); }
    return _copy_prefix(w, j + 1);
  }
  return _copy_prefix(w, j + 1);
}

// Remove a step-4 suffix of length n when its stem has m > 1.
fn _step4_cut(w: &Vec[UInt8], j: Int, n: Int) -> Vec[UInt8] {
  if _measure_to(w, j - n) > 1 {
    return _drop_last(w, j, n);
  }
  return _copy_prefix(w, j + 1);
}

// Step 4: (m>1) AL, ANCE, ENCE, ER, IC, ABLE, IBLE, ANT, EMENT, MENT, ENT,
// (m>1 and (*S or *T)) ION, OU, ISM, ATE, ITI, OUS, IVE, IZE -> (delete).
fn _step4(w: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(w, j, "al") { return _step4_cut(w, j, 2); }
  if _suffix_match(w, j, "ance") { return _step4_cut(w, j, 4); }
  if _suffix_match(w, j, "ence") { return _step4_cut(w, j, 4); }
  if _suffix_match(w, j, "er") { return _step4_cut(w, j, 2); }
  if _suffix_match(w, j, "ic") { return _step4_cut(w, j, 2); }
  if _suffix_match(w, j, "able") { return _step4_cut(w, j, 4); }
  if _suffix_match(w, j, "ible") { return _step4_cut(w, j, 4); }
  if _suffix_match(w, j, "ant") { return _step4_cut(w, j, 3); }
  if _suffix_match(w, j, "ement") { return _step4_cut(w, j, 5); }
  if _suffix_match(w, j, "ment") { return _step4_cut(w, j, 4); }
  if _suffix_match(w, j, "ent") { return _step4_cut(w, j, 3); }
  if _suffix_match(w, j, "ion") {
    let stem_j = j - 3;
    if stem_j >= 0 {
      let b: UInt8 = w[stem_j];
      if b == _BYTE_S || b == 116u8 {
        return _step4_cut(w, j, 3);
      }
    }
    return _copy_prefix(w, j + 1);
  }
  if _suffix_match(w, j, "ou") { return _step4_cut(w, j, 2); }
  if _suffix_match(w, j, "ism") { return _step4_cut(w, j, 3); }
  if _suffix_match(w, j, "ate") { return _step4_cut(w, j, 3); }
  if _suffix_match(w, j, "iti") { return _step4_cut(w, j, 3); }
  if _suffix_match(w, j, "ous") { return _step4_cut(w, j, 3); }
  if _suffix_match(w, j, "ive") { return _step4_cut(w, j, 3); }
  if _suffix_match(w, j, "ize") { return _step4_cut(w, j, 3); }
  return _copy_prefix(w, j + 1);
}

// Step 5a: (m>1) E -> (delete); (m==1 and not *o) E -> (delete).
fn _step5a(w: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(w, j, "e") {
    let m = _measure_to(w, j);
    if m > 1 { return _drop_last(w, j, 1); }
    if m == 1 {
      if !_ends_cvc_to(w, j - 1) { return _drop_last(w, j, 1); }
    }
  }
  return _copy_prefix(w, j + 1);
}

// Step 5b: (m>1 and *d and *L) -> single letter.
fn _step5b(w: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(w, j, "l") {
    if _ends_double_consonant_to(w, j) {
      if _measure_to(w, j) > 1 { return _drop_last(w, j, 1); }
    }
  }
  return _copy_prefix(w, j + 1);
}

// --------------------------------------------------
//  Public stemmer
// --------------------------------------------------

/// Checked Porter stem of one word.
/// Params: word - bytes of a lowercase ASCII word (a-z; nlp_lower_bytes is
/// the usual way to normalize). ASCII bytes outside a-z are allowed and are
/// never part of a matched suffix (suffix bytes are compared literally), so
/// uppercase letters are never cut; a mixed-case word can still change when
/// its tail is lowercase, e.g. "Cats" -> "Cat".
/// Returns: Ok(stem) for a non-empty all-ASCII input; the stem is a prefix
/// of the lowercased input. Words shorter than 3 bytes are returned
/// unchanged (documented departure; see SPEC.md).
/// Errors: Err(code=1, offset) at the first byte >= 128; Err(code=2,
/// offset=0) for empty input.
/// Complexity: O(|word|) per step, O(|word|) in total.
pub fn nlp_stem_checked(word: &Vec[UInt8]) -> Result[Vec[UInt8], NlpError] {
  let n = word.len();
  if n == 0 { return _err_stem(2, 0); }
  var i = 0;
  while i < n {
    let b: UInt8 = word[i];
    let v: Int = (b as Int) & 0xFF;
    if v >= 128 { return _err_stem(1, i); }
    i = i + 1;
  }
  if n < 3 { return _ok_stem(_copy_prefix(word, n)); }
  var cur = _step1a(word, n - 1);
  cur = _step1b(&cur, cur.len() - 1);
  cur = _step1c(&cur, cur.len() - 1);
  cur = _step2(&cur, cur.len() - 1);
  cur = _step3(&cur, cur.len() - 1);
  cur = _step4(&cur, cur.len() - 1);
  cur = _step5a(&cur, cur.len() - 1);
  cur = _step5b(&cur, cur.len() - 1);
  return _ok_stem(cur);
}

/// Lax Porter stem: like nlp_stem_checked, but a non-ASCII or empty input
/// yields a copy of the input unchanged instead of an error. Use
/// nlp_stem_checked when the byte offset of a rejected input is needed.
pub fn nlp_stem(word: &Vec[UInt8]) -> Vec[UInt8] {
  let r = nlp_stem_checked(word);
  match r {
    Ok(v) => { return v; },
    Err(_) => { return _copy_prefix(word, word.len()); },
  };
  return _copy_prefix(word, word.len());
}

// --------------------------------------------------
//  Error accessors
// --------------------------------------------------

/// Numeric code of a stemmer error (1 = non-ASCII, 2 = empty).
pub fn nlp_error_code(e: &NlpError) -> Int {
  let c: Int = e.code;
  return c;
}

/// Byte offset carried by a stemmer error.
pub fn nlp_error_offset(e: &NlpError) -> Int {
  let o: Int = e.offset;
  return o;
}

// --------------------------------------------------
//  Statistics
// --------------------------------------------------

/// Total number of token bytes (sum of token lengths); 0 for no tokens.
pub fn nlp_total_token_length(t: &NlpTokens) -> Int {
  var total = 0;
  var i = 0;
  while i < t.starts.len() {
    let s: Int = t.starts[i];
    let e: Int = t.ends[i];
    total = total + (e - s);
    i = i + 1;
  }
  return total;
}

/// Integer average token length, truncated toward zero; 0 for no tokens.
pub fn nlp_avg_token_length(t: &NlpTokens) -> Int {
  let c = t.starts.len();
  if c == 0 { return 0; }
  return nlp_total_token_length(t) / c;
}

// True when byte ranges [s1,s1+n1) and [s2,s2+n2) of buf are equal.
fn _ranges_equal(buf: &Vec[UInt8], s1: Int, n1: Int, s2: Int, n2: Int) -> Bool {
  if n1 != n2 { return false; }
  var i = 0;
  while i < n1 {
    let a: UInt8 = buf[s1 + i];
    let b: UInt8 = buf[s2 + i];
    let va: Int = (a as Int) & 0xFF;
    let vb: Int = (b as Int) & 0xFF;
    if va != vb { return false; }
    i = i + 1;
  }
  return true;
}

/// Number of distinct stemmed forms among the tokens: every token is
/// lowercased and stemmed, then compared pairwise. Bounded O(n^2) byte
/// comparisons (plus one O(total-bytes) stemming pass), documented.
pub fn nlp_distinct_stem_count(t: &NlpTokens) -> Int {
  let count = t.starts.len();
  var buf = Vec[UInt8].new();
  var offs = Vec[Int].new();
  var lens = Vec[Int].new();
  let src: Str = t.text;
  var i = 0;
  while i < count {
    let s: Int = t.starts[i];
    let e: Int = t.ends[i];
    var raw = Vec[UInt8].new();
    var k = s;
    while k < e {
      raw.push(string.byte_at(src, k));
      k = k + 1;
    }
    let low = nlp_lower_bytes(&raw);
    let stem = nlp_stem(&low);
    let off = buf.len();
    var m = 0;
    while m < stem.len() {
      let b: UInt8 = stem[m];
      buf.push(b);
      m = m + 1;
    }
    offs.push(off);
    lens.push(stem.len());
    i = i + 1;
  }
  var distinct = 0;
  var a = 0;
  while a < count {
    let oa: Int = offs[a];
    let la: Int = lens[a];
    var dup = false;
    var b = 0;
    while b < a {
      let ob: Int = offs[b];
      let lb: Int = lens[b];
      if _ranges_equal(&buf, oa, la, ob, lb) { dup = true; }
      b = b + 1;
    }
    if !dup { distinct = distinct + 1; }
    a = a + 1;
  }
  return distinct;
}
