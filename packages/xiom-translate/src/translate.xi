// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// XIOM -- xiom.translate: deterministic, pure-XIOM translation utilities
//
// Scope (SPEC.md states the exact documented subsets):
//   * phrasebook -- term substitution from an in-package concept table with
//                   four languages (en, fr, de, es) and 22 everyday
//                   concepts; all 12 ordered cross-language pairs work;
//   * detection  -- source-language scoring over six languages
//                   (en, de, fr, es, it, nl): case-insensitive stopword
//                   hits + curated character n-gram features + distinctive
//                   character counts, all integer arithmetic;
//   * translit   -- script conversion for a documented subset:
//                   Cyrillic <-> Latin (Russian core block) and
//                   Greek <-> Latin (letters plus tonos vowels);
//   * glossary   -- a small domain term map with case-insensitive lookup
//                   and whole-word application.
//
// Pure and deterministic: no network, no services, no locale, no clocks, no
// randomness. Str equality goes through compare.str_compare (never `==`).
//
// Compiler notes (v0.62.2 traps):
//   * free functions only; no methods, lambdas, Vec[Str] or Vec[StructType];
//   * tables are if/elif chains over literals; the glossary keeps one Str
//     blob with '\t' and '\n' separators (no module-level mutable state);
//   * Vec elements are read through typed locals; UInt8 -> Int widening is
//     masked with 0xFF before comparisons;
//   * output bytes are accumulated in a local Vec[UInt8] and materialized
//     with the builder entry point sb_to_str (no 0x00 byte can occur: a Str
//     cannot carry an interior NUL, per trap 15);
//   * &mut builder buffers are threaded with an explicit &mut at every call.

module xiom.translate

use xiom.string;
use xiom.string.compare;
use xiom.string.builder;

// ---------------------------------------------------------------------------
// Shared byte helpers
// ---------------------------------------------------------------------------

fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn _byte_val(b: UInt8) -> Int {
  return (b as Int) & 0xFF;
}

fn _is_upper_byte(b: UInt8) -> Bool {
  let v: Int = _byte_val(b);
  return v >= 65 && v <= 90;
}

fn _is_lower_byte(b: UInt8) -> Bool {
  let v: Int = _byte_val(b);
  return v >= 97 && v <= 122;
}

fn _is_letter_byte(b: UInt8) -> Bool {
  return _is_upper_byte(b) || _is_lower_byte(b);
}

fn _lower_byte(b: UInt8) -> UInt8 {
  let v: Int = _byte_val(b);
  if v >= 65 && v <= 90 {
    return ((v + 32) as UInt8);
  }
  return b;
}

fn _upper_byte(b: UInt8) -> UInt8 {
  let v: Int = _byte_val(b);
  if v >= 97 && v <= 122 {
    return ((v - 32) as UInt8);
  }
  return b;
}

fn _push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Case-insensitive equality of two Str values (ASCII A-Z only); false when
// the byte lengths differ.
fn _ci_equals(a: Str, b: Str) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = string.byte_at(a, i);
    let y: UInt8 = string.byte_at(b, i);
    let lx: Int = _byte_val(_lower_byte(x));
    let ly: Int = _byte_val(_lower_byte(y));
    if lx != ly { return false; }
    i = i + 1;
  }
  return true;
}

// Index of byte `want` at or after `from`, or -1.
fn _find_byte_from(s: Str, from: Int, want: Int) -> Int {
  let n = s.len();
  var i = from;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    let v: Int = _byte_val(b);
    if v == want { return i; }
    i = i + 1;
  }
  return -1;
}

// Count case-insensitive, possibly overlapping, ASCII occurrences of
// `needle` in `text`; `needle` must be ASCII lowercase.
fn _count_ci(text: Str, needle: Str) -> Int {
  let k = needle.len();
  if k == 0 { return 0; }
  let n = text.len();
  if k > n { return 0; }
  var count = 0;
  var i = 0;
  while i + k <= n {
    var m = true;
    var j = 0;
    while j < k && m {
      let tb: UInt8 = string.byte_at(text, i + j);
      let nb: UInt8 = string.byte_at(needle, j);
      let tv: Int = _byte_val(_lower_byte(tb));
      let nv: Int = _byte_val(_lower_byte(nb));
      if tv != nv { m = false; }
      j = j + 1;
    }
    if m { count = count + 1; }
    i = i + 1;
  }
  return count;
}

// Count byte-exact, possibly overlapping occurrences of `needle` in `text`
// (used for UTF-8 markers such as sharp s or n-tilde).
fn _count_exact(text: Str, needle: Str) -> Int {
  let k = needle.len();
  if k == 0 { return 0; }
  let n = text.len();
  if k > n { return 0; }
  var count = 0;
  var i = 0;
  while i + k <= n {
    var m = true;
    var j = 0;
    while j < k && m {
      let tb: UInt8 = string.byte_at(text, i + j);
      let nb: UInt8 = string.byte_at(needle, j);
      if _byte_val(tb) != _byte_val(nb) { m = false; }
      j = j + 1;
    }
    if m { count = count + 1; }
    i = i + 1;
  }
  return count;
}

// Split a "src-tgt" pair code: which 0 returns the source language id,
// which 1 the target; -1 when the code is malformed or unknown.
fn _pair_part(pair: Str, which: Int) -> Int {
  let dash = _find_byte_from(pair, 0, 45);
  if dash <= 0 { return -1; }
  if dash + 1 >= pair.len() { return -1; }
  let left = string.str_slice(pair, 0, dash);
  let right = string.str_slice(pair, dash + 1, pair.len());
  if which == 0 { return _lang_id(left); }
  return _lang_id(right);
}

// ---------------------------------------------------------------------------
// Phrasebook (4 languages, 22 concepts)
// ---------------------------------------------------------------------------

const _LANG_EN: Int = 0;
const _LANG_FR: Int = 1;
const _LANG_DE: Int = 2;
const _LANG_ES: Int = 3;

fn _lang_id(code: Str) -> Int {
  if _streq(code, "en") { return _LANG_EN; }
  if _streq(code, "fr") { return _LANG_FR; }
  if _streq(code, "de") { return _LANG_DE; }
  if _streq(code, "es") { return _LANG_ES; }
  return -1;
}

fn _concept_count() -> Int {
  return 22;
}

// Word for one concept in one of the four phrasebook languages; "" when the
// concept or language is outside the table.
fn _concept_word(c: Int, lang: Int) -> Str {
  if c == 0 {
    if lang == 0 { return "hello"; }
    if lang == 1 { return "bonjour"; }
    if lang == 2 { return "hallo"; }
    if lang == 3 { return "hola"; }
    return "";
  }
  if c == 1 {
    if lang == 0 { return "goodbye"; }
    if lang == 1 { return "aurevoir"; }
    if lang == 2 { return "tschuess"; }
    if lang == 3 { return "adios"; }
    return "";
  }
  if c == 2 {
    if lang == 0 { return "please"; }
    if lang == 1 { return "silvousplait"; }
    if lang == 2 { return "bitte"; }
    if lang == 3 { return "porfavor"; }
    return "";
  }
  if c == 3 {
    if lang == 0 { return "thanks"; }
    if lang == 1 { return "merci"; }
    if lang == 2 { return "danke"; }
    if lang == 3 { return "gracias"; }
    return "";
  }
  if c == 4 {
    if lang == 0 { return "yes"; }
    if lang == 1 { return "oui"; }
    if lang == 2 { return "ja"; }
    if lang == 3 { return "si"; }
    return "";
  }
  if c == 5 {
    if lang == 0 { return "no"; }
    if lang == 1 { return "non"; }
    if lang == 2 { return "nein"; }
    if lang == 3 { return "no"; }
    return "";
  }
  if c == 6 {
    if lang == 0 { return "good"; }
    if lang == 1 { return "bon"; }
    if lang == 2 { return "gut"; }
    if lang == 3 { return "bueno"; }
    return "";
  }
  if c == 7 {
    if lang == 0 { return "morning"; }
    if lang == 1 { return "matin"; }
    if lang == 2 { return "morgen"; }
    if lang == 3 { return "manana"; }
    return "";
  }
  if c == 8 {
    if lang == 0 { return "night"; }
    if lang == 1 { return "nuit"; }
    if lang == 2 { return "nacht"; }
    if lang == 3 { return "noche"; }
    return "";
  }
  if c == 9 {
    if lang == 0 { return "water"; }
    if lang == 1 { return "eau"; }
    if lang == 2 { return "wasser"; }
    if lang == 3 { return "agua"; }
    return "";
  }
  if c == 10 {
    if lang == 0 { return "bread"; }
    if lang == 1 { return "pain"; }
    if lang == 2 { return "brot"; }
    if lang == 3 { return "pan"; }
    return "";
  }
  if c == 11 {
    if lang == 0 { return "friend"; }
    if lang == 1 { return "ami"; }
    if lang == 2 { return "freund"; }
    if lang == 3 { return "amigo"; }
    return "";
  }
  if c == 12 {
    if lang == 0 { return "house"; }
    if lang == 1 { return "maison"; }
    if lang == 2 { return "haus"; }
    if lang == 3 { return "casa"; }
    return "";
  }
  if c == 13 {
    if lang == 0 { return "book"; }
    if lang == 1 { return "livre"; }
    if lang == 2 { return "buch"; }
    if lang == 3 { return "libro"; }
    return "";
  }
  if c == 14 {
    if lang == 0 { return "city"; }
    if lang == 1 { return "ville"; }
    if lang == 2 { return "stadt"; }
    if lang == 3 { return "ciudad"; }
    return "";
  }
  if c == 15 {
    if lang == 0 { return "name"; }
    if lang == 1 { return "nom"; }
    if lang == 2 { return "name"; }
    if lang == 3 { return "nombre"; }
    return "";
  }
  if c == 16 {
    if lang == 0 { return "love"; }
    if lang == 1 { return "amour"; }
    if lang == 2 { return "liebe"; }
    if lang == 3 { return "amor"; }
    return "";
  }
  if c == 17 {
    if lang == 0 { return "welcome"; }
    if lang == 1 { return "bienvenue"; }
    if lang == 2 { return "willkommen"; }
    if lang == 3 { return "bienvenido"; }
    return "";
  }
  if c == 18 {
    if lang == 0 { return "sorry"; }
    if lang == 1 { return "desole"; }
    if lang == 2 { return "entschuldigung"; }
    if lang == 3 { return "perdona"; }
    return "";
  }
  if c == 19 {
    if lang == 0 { return "one"; }
    if lang == 1 { return "un"; }
    if lang == 2 { return "eins"; }
    if lang == 3 { return "uno"; }
    return "";
  }
  if c == 20 {
    if lang == 0 { return "two"; }
    if lang == 1 { return "deux"; }
    if lang == 2 { return "zwei"; }
    if lang == 3 { return "dos"; }
    return "";
  }
  if c == 21 {
    if lang == 0 { return "three"; }
    if lang == 1 { return "trois"; }
    if lang == 2 { return "drei"; }
    if lang == 3 { return "tres"; }
    return "";
  }
  return "";
}

// Concept id whose word in `lang` equals `term` case-insensitively, or -1.
fn _concept_of(lang: Int, term: Str) -> Int {
  if lang < 0 { return -1; }
  let low = string.str_lower(term);
  var c = 0;
  while c < _concept_count() {
    let w = _concept_word(c, lang);
    if _streq(w, low) { return c; }
    c = c + 1;
  }
  return -1;
}

// Re-apply the case shape of `pattern` to the lowercase ASCII `repl`:
// all-uppercase pattern -> uppercase replacement; leading uppercase ->
// capitalized replacement; otherwise the replacement is used as stored.
fn _apply_case(pattern: Str, repl: Str) -> Str {
  if repl.len() == 0 { return ""; }
  var letters = 0;
  var all_upper = true;
  var i = 0;
  while i < pattern.len() {
    let b: UInt8 = string.byte_at(pattern, i);
    if _is_letter_byte(b) {
      letters = letters + 1;
      if _is_lower_byte(b) { all_upper = false; }
    }
    i = i + 1;
  }
  if letters > 0 && all_upper { return string.str_upper(repl); }
  if pattern.len() > 0 {
    let first: UInt8 = string.byte_at(pattern, 0);
    if _is_upper_byte(first) {
      var out = Vec[UInt8].new();
      var k = 0;
      while k < repl.len() {
        let rb: UInt8 = string.byte_at(repl, k);
        if k == 0 {
          out.push(_upper_byte(rb));
        } else {
          out.push(rb);
        }
        k = k + 1;
      }
      return sb_to_str(&out);
    }
  }
  return repl;
}

/// Comma-separated phrasebook language codes: "en,fr,de,es".
pub fn translate_languages() -> Str {
  return "en,fr,de,es";
}

/// Number of phrasebook concepts (22).
pub fn translate_concept_count() -> Int {
  return _concept_count();
}

/// True when `pair` is a supported ordered language pair such as "en-fr"
/// (both sides known and different). The 12 directed pairs among
/// en/fr/de/es are supported.
pub fn translate_pair_supported(pair: Str) -> Bool {
  let s = _pair_part(pair, 0);
  let t = _pair_part(pair, 1);
  if s < 0 || t < 0 { return false; }
  if s == t { return false; }
  return true;
}

/// Translate one term through the in-package phrasebook. Matching is
/// case-insensitive; the case shape of `term` is re-applied to the result
/// (Hello -> Bonjour, HELLO -> BONJOUR). Returns "" for an unknown pair or a
/// term outside the 22 concepts.
pub fn translate_term(pair: Str, term: Str) -> Str {
  let s = _pair_part(pair, 0);
  let t = _pair_part(pair, 1);
  if s < 0 || t < 0 || s == t { return ""; }
  let c = _concept_of(s, term);
  if c < 0 { return ""; }
  return _apply_case(term, _concept_word(c, t));
}

/// Checked term translation. Ok(translation); Err(1) unknown or malformed
/// pair or equal languages; Err(2) term not found in the phrasebook.
pub fn translate_term_checked(pair: Str, term: Str) -> Result[Str, Int] {
  let s = _pair_part(pair, 0);
  let t = _pair_part(pair, 1);
  if s < 0 || t < 0 || s == t { return Err(1); }
  let c = _concept_of(s, term);
  if c < 0 { return Err(2); }
  return Ok(_apply_case(term, _concept_word(c, t)));
}

/// Substitute phrasebook terms inside `text` word by word. A word is a
/// maximal run of ASCII letters; every other byte (including bytes >= 128,
/// digits and punctuation) is copied through unchanged. Unknown words and
/// unsupported pairs leave the text unchanged.
pub fn translate_apply(pair: Str, text: Str) -> Str {
  let s = _pair_part(pair, 0);
  let t = _pair_part(pair, 1);
  if s < 0 || t < 0 || s == t { return text; }
  var out = Vec[UInt8].new();
  let n = text.len();
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(text, i);
    if _is_letter_byte(b) {
      let start = i;
      var j = i;
      var go = true;
      while j < n && go {
        let c: UInt8 = string.byte_at(text, j);
        if _is_letter_byte(c) { j = j + 1; } else { go = false; }
      }
      let word = string.str_slice(text, start, j);
      let cid = _concept_of(s, word);
      if cid >= 0 {
        _push_str(&mut out, _apply_case(word, _concept_word(cid, t)));
      } else {
        _push_str(&mut out, word);
      }
      i = j;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return sb_to_str(&out);
}

/// Comma-separated English source terms of the phrasebook, in concept order.
pub fn translate_terms() -> Str {
  return "hello,goodbye,please,thanks,yes,no,good,morning,night,water,bread,friend,house,book,city,name,love,welcome,sorry,one,two,three";
}

// ---------------------------------------------------------------------------
// Language detection (en, de, fr, es, it, nl)
// ---------------------------------------------------------------------------
//
// Score(lang) = 8 * (case-insensitive whole-word stopword hits)
//             + sum(weight * case-insensitive n-gram occurrences)
//             + distinctive-character counts (see _special_score).
// All weights are small integers; ties are resolved in the fixed order
// en, de, fr, es, it, nl (first language with the highest score wins).

const _DET_EN: Int = 0;
const _DET_DE: Int = 1;
const _DET_FR: Int = 2;
const _DET_ES: Int = 3;
const _DET_IT: Int = 4;
const _DET_NL: Int = 5;
const _DET_COUNT: Int = 6;
const _STOPWORD_WEIGHT: Int = 8;

fn _detect_lang_id(code: Str) -> Int {
  if _streq(code, "en") { return _DET_EN; }
  if _streq(code, "de") { return _DET_DE; }
  if _streq(code, "fr") { return _DET_FR; }
  if _streq(code, "es") { return _DET_ES; }
  if _streq(code, "it") { return _DET_IT; }
  if _streq(code, "nl") { return _DET_NL; }
  return -1;
}

fn _detect_lang_code(id: Int) -> Str {
  if id == _DET_EN { return "en"; }
  if id == _DET_DE { return "de"; }
  if id == _DET_FR { return "fr"; }
  if id == _DET_ES { return "es"; }
  if id == _DET_IT { return "it"; }
  if id == _DET_NL { return "nl"; }
  return "";
}

// Whole-word stopword test on a lowercased ASCII token.
fn _is_stopword(lang: Int, t: Str) -> Bool {
  if lang == _DET_EN {
    if _streq(t, "the") { return true; }
    if _streq(t, "and") { return true; }
    if _streq(t, "of") { return true; }
    if _streq(t, "in") { return true; }
    if _streq(t, "is") { return true; }
    if _streq(t, "it") { return true; }
    if _streq(t, "for") { return true; }
    if _streq(t, "with") { return true; }
    if _streq(t, "this") { return true; }
    if _streq(t, "that") { return true; }
    if _streq(t, "on") { return true; }
    if _streq(t, "as") { return true; }
    if _streq(t, "at") { return true; }
    if _streq(t, "be") { return true; }
    if _streq(t, "to") { return true; }
    return false;
  }
  if lang == _DET_DE {
    if _streq(t, "der") { return true; }
    if _streq(t, "die") { return true; }
    if _streq(t, "das") { return true; }
    if _streq(t, "und") { return true; }
    if _streq(t, "ein") { return true; }
    if _streq(t, "eine") { return true; }
    if _streq(t, "ist") { return true; }
    if _streq(t, "mit") { return true; }
    if _streq(t, "von") { return true; }
    if _streq(t, "den") { return true; }
    if _streq(t, "zu") { return true; }
    if _streq(t, "im") { return true; }
    if _streq(t, "in") { return true; }
    if _streq(t, "auf") { return true; }
    if _streq(t, "nicht") { return true; }
    if _streq(t, "sich") { return true; }
    return false;
  }
  if lang == _DET_FR {
    if _streq(t, "le") { return true; }
    if _streq(t, "la") { return true; }
    if _streq(t, "les") { return true; }
    if _streq(t, "de") { return true; }
    if _streq(t, "des") { return true; }
    if _streq(t, "un") { return true; }
    if _streq(t, "une") { return true; }
    if _streq(t, "et") { return true; }
    if _streq(t, "est") { return true; }
    if _streq(t, "dans") { return true; }
    if _streq(t, "avec") { return true; }
    if _streq(t, "pour") { return true; }
    if _streq(t, "que") { return true; }
    if _streq(t, "qui") { return true; }
    if _streq(t, "pas") { return true; }
    if _streq(t, "sur") { return true; }
    return false;
  }
  if lang == _DET_ES {
    if _streq(t, "el") { return true; }
    if _streq(t, "la") { return true; }
    if _streq(t, "los") { return true; }
    if _streq(t, "las") { return true; }
    if _streq(t, "de") { return true; }
    if _streq(t, "un") { return true; }
    if _streq(t, "una") { return true; }
    if _streq(t, "es") { return true; }
    if _streq(t, "en") { return true; }
    if _streq(t, "con") { return true; }
    if _streq(t, "por") { return true; }
    if _streq(t, "que") { return true; }
    if _streq(t, "para") { return true; }
    if _streq(t, "no") { return true; }
    if _streq(t, "se") { return true; }
    return false;
  }
  if lang == _DET_IT {
    if _streq(t, "il") { return true; }
    if _streq(t, "lo") { return true; }
    if _streq(t, "la") { return true; }
    if _streq(t, "gli") { return true; }
    if _streq(t, "le") { return true; }
    if _streq(t, "di") { return true; }
    if _streq(t, "un") { return true; }
    if _streq(t, "una") { return true; }
    if _streq(t, "che") { return true; }
    if _streq(t, "con") { return true; }
    if _streq(t, "per") { return true; }
    if _streq(t, "in") { return true; }
    if _streq(t, "non") { return true; }
    if _streq(t, "si") { return true; }
    return false;
  }
  if lang == _DET_NL {
    if _streq(t, "de") { return true; }
    if _streq(t, "het") { return true; }
    if _streq(t, "een") { return true; }
    if _streq(t, "van") { return true; }
    if _streq(t, "en") { return true; }
    if _streq(t, "is") { return true; }
    if _streq(t, "in") { return true; }
    if _streq(t, "op") { return true; }
    if _streq(t, "dat") { return true; }
    if _streq(t, "met") { return true; }
    if _streq(t, "voor") { return true; }
    if _streq(t, "niet") { return true; }
    if _streq(t, "zijn") { return true; }
    if _streq(t, "er") { return true; }
    return false;
  }
  return false;
}

fn _stopword_score(text: Str, lang: Int) -> Int {
  var score = 0;
  let n = text.len();
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(text, i);
    if _is_letter_byte(b) {
      let start = i;
      var j = i;
      var go = true;
      while j < n && go {
        let c: UInt8 = string.byte_at(text, j);
        if _is_letter_byte(c) { j = j + 1; } else { go = false; }
      }
      let word = string.str_slice(text, start, j);
      if _is_stopword(lang, string.str_lower(word)) {
        score = score + _STOPWORD_WEIGHT;
      }
      i = j;
    } else {
      i = i + 1;
    }
  }
  return score;
}

// Curated character n-gram features per language (weights as written).
fn _ngram_score(text: Str, lang: Int) -> Int {
  var s = 0;
  if lang == _DET_EN {
    s = s + _count_ci(text, "the") * 4;
    s = s + _count_ci(text, "and") * 4;
    s = s + _count_ci(text, "ing") * 3;
    s = s + _count_ci(text, "ion") * 2;
    s = s + _count_ci(text, "th") * 2;
    s = s + _count_ci(text, "he") * 2;
    s = s + _count_ci(text, "of") * 2;
    return s;
  }
  if lang == _DET_DE {
    s = s + _count_ci(text, "sch") * 4;
    s = s + _count_ci(text, "der") * 4;
    s = s + _count_ci(text, "die") * 4;
    s = s + _count_ci(text, "und") * 4;
    s = s + _count_ci(text, "ein") * 3;
    s = s + _count_ci(text, "ich") * 3;
    s = s + _count_ci(text, "ch") * 2;
    s = s + _count_ci(text, "ei") * 2;
    s = s + _count_ci(text, "ie") * 2;
    s = s + _count_ci(text, "st") * 1;
    return s;
  }
  if lang == _DET_FR {
    s = s + _count_ci(text, "qu") * 3;
    s = s + _count_ci(text, "le") * 3;
    s = s + _count_ci(text, "la") * 3;
    s = s + _count_ci(text, "de") * 3;
    s = s + _count_ci(text, "un") * 3;
    s = s + _count_ci(text, "ent") * 3;
    s = s + _count_ci(text, "es") * 2;
    s = s + _count_ci(text, "ai") * 2;
    s = s + _count_ci(text, "oi") * 2;
    s = s + _count_ci(text, "on") * 2;
    return s;
  }
  if lang == _DET_ES {
    s = s + _count_ci(text, "acion") * 4;
    s = s + _count_ci(text, "el") * 3;
    s = s + _count_ci(text, "la") * 3;
    s = s + _count_ci(text, "os") * 3;
    s = s + _count_ci(text, "as") * 3;
    s = s + _count_ci(text, "de") * 2;
    s = s + _count_ci(text, "en") * 2;
    s = s + _count_ci(text, "qu") * 2;
    s = s + _count_ci(text, "ll") * 2;
    s = s + _count_ci(text, "ue") * 2;
    return s;
  }
  if lang == _DET_IT {
    s = s + _count_ci(text, "gli") * 4;
    s = s + _count_ci(text, "zione") * 4;
    s = s + _count_ci(text, "che") * 3;
    s = s + _count_ci(text, "gh") * 3;
    s = s + _count_ci(text, "il") * 3;
    s = s + _count_ci(text, "la") * 3;
    s = s + _count_ci(text, "di") * 3;
    s = s + _count_ci(text, "ch") * 2;
    s = s + _count_ci(text, "tt") * 2;
    s = s + _count_ci(text, "ss") * 2;
    return s;
  }
  if lang == _DET_NL {
    s = s + _count_ci(text, "ij") * 4;
    s = s + _count_ci(text, "het") * 4;
    s = s + _count_ci(text, "een") * 4;
    s = s + _count_ci(text, "van") * 3;
    s = s + _count_ci(text, "de") * 3;
    s = s + _count_ci(text, "sch") * 3;
    s = s + _count_ci(text, "ui") * 3;
    s = s + _count_ci(text, "aa") * 2;
    s = s + _count_ci(text, "ee") * 2;
    s = s + _count_ci(text, "oo") * 2;
    return s;
  }
  return 0;
}

// Distinctive-character bonus (UTF-8 markers), byte-exact.
fn _special_score(text: Str, lang: Int) -> Int {
  var s = 0;
  if lang == _DET_DE {
    s = s + _count_exact(text, "ß") * 6;
    s = s + _count_exact(text, "ä") * 3;
    s = s + _count_exact(text, "ö") * 3;
    s = s + _count_exact(text, "ü") * 3;
    return s;
  }
  if lang == _DET_FR {
    s = s + _count_exact(text, "ç") * 5;
    s = s + _count_exact(text, "é") * 3;
    s = s + _count_exact(text, "è") * 3;
    s = s + _count_exact(text, "ê") * 2;
    s = s + _count_exact(text, "à") * 2;
    s = s + _count_exact(text, "ù") * 1;
    return s;
  }
  if lang == _DET_ES {
    s = s + _count_exact(text, "ñ") * 6;
    s = s + _count_exact(text, "¿") * 4;
    s = s + _count_exact(text, "¡") * 4;
    return s;
  }
  if lang == _DET_IT {
    s = s + _count_exact(text, "ì") * 3;
    s = s + _count_exact(text, "ò") * 3;
    s = s + _count_exact(text, "ù") * 3;
    return s;
  }
  return 0;
}

/// Number of supported detection languages (6).
pub fn detect_language_count() -> Int {
  return _DET_COUNT;
}

/// Comma-separated detection language codes: "en,de,fr,es,it,nl".
pub fn detect_language_supported() -> Str {
  return "en,de,fr,es,it,nl";
}

/// Detection score of `text` for language code `lang` (0 for an unknown
/// code and for text without any matching feature).
pub fn detect_language_score(text: Str, lang: Str) -> Int {
  let id = _detect_lang_id(lang);
  if id < 0 { return 0; }
  return _stopword_score(text, id) + _ngram_score(text, id) + _special_score(text, id);
}

/// Best-scoring supported language code for `text`, or "" when no feature
/// matches (empty input, digits, punctuation). Ties go to the fixed order
/// en, de, fr, es, it, nl.
pub fn detect_language(text: Str) -> Str {
  var best = -1;
  var best_score = 0;
  var i = 0;
  while i < _DET_COUNT {
    let s = detect_language_score(text, _detect_lang_code(i));
    if s > best_score {
      best_score = s;
      best = i;
    }
    i = i + 1;
  }
  if best < 0 { return ""; }
  return _detect_lang_code(best);
}

// ---------------------------------------------------------------------------
// Script conversion (Cyrillic <-> Latin, Greek <-> Latin)
// ---------------------------------------------------------------------------

// UTF-8 sequence length from a lead byte widened to Int.
fn _cp_len(b0: Int) -> Int {
  if b0 < 0x80 { return 1; }
  if (b0 & 0xE0) == 0xC0 { return 2; }
  if (b0 & 0xF0) == 0xE0 { return 3; }
  if (b0 & 0xF8) == 0xF0 { return 4; }
  return 1;
}

// Decode one UTF-8 code point at `pos`; -1 when the bytes do not form a
// valid non-overlong sequence (caller then advances one byte).
fn _decode_cp(s: Str, pos: Int) -> Int {
  let n = s.len();
  let b0: Int = _byte_val(string.byte_at(s, pos));
  if b0 < 0x80 { return b0; }
  if (b0 & 0xE0) == 0xC0 {
    if pos + 2 > n { return -1; }
    let b1: Int = _byte_val(string.byte_at(s, pos + 1));
    if (b1 & 0xC0) != 0x80 { return -1; }
    let cp: Int = ((b0 & 0x1F) << 6) | (b1 & 0x3F);
    if cp < 0x80 { return -1; }
    return cp;
  }
  if (b0 & 0xF0) == 0xE0 {
    if pos + 3 > n { return -1; }
    let b1: Int = _byte_val(string.byte_at(s, pos + 1));
    let b2: Int = _byte_val(string.byte_at(s, pos + 2));
    if (b1 & 0xC0) != 0x80 { return -1; }
    if (b2 & 0xC0) != 0x80 { return -1; }
    let cp: Int = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);
    if cp < 0x800 { return -1; }
    if cp >= 0xD800 && cp <= 0xDFFF { return -1; }
    return cp;
  }
  if (b0 & 0xF8) == 0xF0 {
    if pos + 4 > n { return -1; }
    let b1: Int = _byte_val(string.byte_at(s, pos + 1));
    let b2: Int = _byte_val(string.byte_at(s, pos + 2));
    let b3: Int = _byte_val(string.byte_at(s, pos + 3));
    if (b1 & 0xC0) != 0x80 { return -1; }
    if (b2 & 0xC0) != 0x80 { return -1; }
    if (b3 & 0xC0) != 0x80 { return -1; }
    let cp: Int = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
    if cp < 0x10000 { return -1; }
    if cp > 0x10FFFF { return -1; }
    return cp;
  }
  return -1;
}

// Covered Cyrillic: U+0410..U+044F (Russian letters), plus U+0401/U+0451
// (Yo/yo). Every covered code point has an explicit mapping below; the two
// signs (hard/soft) map to "".
fn _cyr_known(cp: Int) -> Bool {
  if cp >= 0x0410 && cp <= 0x044F { return true; }
  if cp == 0x0401 { return true; }
  if cp == 0x0451 { return true; }
  return false;
}

fn _cyr_latin(cp: Int) -> Str {
  if cp == 0x0410 { return "A"; }
  if cp == 0x0411 { return "B"; }
  if cp == 0x0412 { return "V"; }
  if cp == 0x0413 { return "G"; }
  if cp == 0x0414 { return "D"; }
  if cp == 0x0415 { return "E"; }
  if cp == 0x0416 { return "Zh"; }
  if cp == 0x0417 { return "Z"; }
  if cp == 0x0418 { return "I"; }
  if cp == 0x0419 { return "Y"; }
  if cp == 0x041A { return "K"; }
  if cp == 0x041B { return "L"; }
  if cp == 0x041C { return "M"; }
  if cp == 0x041D { return "N"; }
  if cp == 0x041E { return "O"; }
  if cp == 0x041F { return "P"; }
  if cp == 0x0420 { return "R"; }
  if cp == 0x0421 { return "S"; }
  if cp == 0x0422 { return "T"; }
  if cp == 0x0423 { return "U"; }
  if cp == 0x0424 { return "F"; }
  if cp == 0x0425 { return "Kh"; }
  if cp == 0x0426 { return "Ts"; }
  if cp == 0x0427 { return "Ch"; }
  if cp == 0x0428 { return "Sh"; }
  if cp == 0x0429 { return "Shch"; }
  if cp == 0x042A { return ""; }
  if cp == 0x042B { return "Y"; }
  if cp == 0x042C { return ""; }
  if cp == 0x042D { return "E"; }
  if cp == 0x042E { return "Yu"; }
  if cp == 0x042F { return "Ya"; }
  if cp == 0x0401 { return "E"; }
  if cp == 0x0430 { return "a"; }
  if cp == 0x0431 { return "b"; }
  if cp == 0x0432 { return "v"; }
  if cp == 0x0433 { return "g"; }
  if cp == 0x0434 { return "d"; }
  if cp == 0x0435 { return "e"; }
  if cp == 0x0436 { return "zh"; }
  if cp == 0x0437 { return "z"; }
  if cp == 0x0438 { return "i"; }
  if cp == 0x0439 { return "y"; }
  if cp == 0x043A { return "k"; }
  if cp == 0x043B { return "l"; }
  if cp == 0x043C { return "m"; }
  if cp == 0x043D { return "n"; }
  if cp == 0x043E { return "o"; }
  if cp == 0x043F { return "p"; }
  if cp == 0x0440 { return "r"; }
  if cp == 0x0441 { return "s"; }
  if cp == 0x0442 { return "t"; }
  if cp == 0x0443 { return "u"; }
  if cp == 0x0444 { return "f"; }
  if cp == 0x0445 { return "kh"; }
  if cp == 0x0446 { return "ts"; }
  if cp == 0x0447 { return "ch"; }
  if cp == 0x0448 { return "sh"; }
  if cp == 0x0449 { return "shch"; }
  if cp == 0x044A { return ""; }
  if cp == 0x044B { return "y"; }
  if cp == 0x044C { return ""; }
  if cp == 0x044D { return "e"; }
  if cp == 0x044E { return "yu"; }
  if cp == 0x044F { return "ya"; }
  if cp == 0x0451 { return "e"; }
  return "";
}

/// Transliterate the covered Cyrillic subset to Latin. ASCII bytes and
/// uncovered code points pass through unchanged; valid UTF-8 is preserved;
/// an invalid byte is copied one byte at a time. The hard sign and soft
/// sign transliterate to nothing.
pub fn translit_cyrillic_to_latin(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    let bv: Int = _byte_val(b);
    if bv < 0x80 {
      out.push(b);
      i = i + 1;
    } else {
      let cp = _decode_cp(s, i);
      if cp < 0 {
        out.push(b);
        i = i + 1;
      } else {
        if _cyr_known(cp) {
          _push_str(&mut out, _cyr_latin(cp));
        } else {
          _push_str(&mut out, string.str_slice(s, i, i + _cp_len(bv)));
        }
        i = i + _cp_len(bv);
      }
    }
  }
  return sb_to_str(&out);
}

// Case-insensitive match of the lowercase ASCII `seq` at position `i`.
fn _seq_matches(s: Str, i: Int, seq: Str) -> Bool {
  let k = seq.len();
  if i + k > s.len() { return false; }
  var j = 0;
  while j < k {
    let a: UInt8 = string.byte_at(s, i + j);
    let b: UInt8 = string.byte_at(seq, j);
    let va: Int = _byte_val(_lower_byte(a));
    let vb: Int = _byte_val(b);
    if va != vb { return false; }
    j = j + 1;
  }
  return true;
}

// Latin letter sequence -> Cyrillic; `up` capitalizes the first Cyrillic
// letter (the rest of a digraph replacement stays lowercase).
fn _cyr_map(seq: Str, up: Bool) -> Str {
  if _streq(seq, "shch") {
    if up { return "Щ"; }
    return "щ";
  }
  if _streq(seq, "sh") {
    if up { return "Ш"; }
    return "ш";
  }
  if _streq(seq, "ch") {
    if up { return "Ч"; }
    return "ч";
  }
  if _streq(seq, "zh") {
    if up { return "Ж"; }
    return "ж";
  }
  if _streq(seq, "kh") {
    if up { return "Х"; }
    return "х";
  }
  if _streq(seq, "ts") {
    if up { return "Ц"; }
    return "ц";
  }
  if _streq(seq, "yu") {
    if up { return "Ю"; }
    return "ю";
  }
  if _streq(seq, "ya") {
    if up { return "Я"; }
    return "я";
  }
  if _streq(seq, "yo") {
    if up { return "Ё"; }
    return "ё";
  }
  if _streq(seq, "ye") {
    if up { return "Е"; }
    return "е";
  }
  if _streq(seq, "a") {
    if up { return "А"; }
    return "а";
  }
  if _streq(seq, "b") {
    if up { return "Б"; }
    return "б";
  }
  if _streq(seq, "c") {
    if up { return "Ц"; }
    return "ц";
  }
  if _streq(seq, "d") {
    if up { return "Д"; }
    return "д";
  }
  if _streq(seq, "e") {
    if up { return "Е"; }
    return "е";
  }
  if _streq(seq, "f") {
    if up { return "Ф"; }
    return "ф";
  }
  if _streq(seq, "g") {
    if up { return "Г"; }
    return "г";
  }
  if _streq(seq, "h") {
    if up { return "Х"; }
    return "х";
  }
  if _streq(seq, "i") {
    if up { return "И"; }
    return "и";
  }
  if _streq(seq, "j") {
    if up { return "Й"; }
    return "й";
  }
  if _streq(seq, "k") {
    if up { return "К"; }
    return "к";
  }
  if _streq(seq, "l") {
    if up { return "Л"; }
    return "л";
  }
  if _streq(seq, "m") {
    if up { return "М"; }
    return "м";
  }
  if _streq(seq, "n") {
    if up { return "Н"; }
    return "н";
  }
  if _streq(seq, "o") {
    if up { return "О"; }
    return "о";
  }
  if _streq(seq, "p") {
    if up { return "П"; }
    return "п";
  }
  if _streq(seq, "q") {
    if up { return "К"; }
    return "к";
  }
  if _streq(seq, "r") {
    if up { return "Р"; }
    return "р";
  }
  if _streq(seq, "s") {
    if up { return "С"; }
    return "с";
  }
  if _streq(seq, "t") {
    if up { return "Т"; }
    return "т";
  }
  if _streq(seq, "u") {
    if up { return "У"; }
    return "у";
  }
  if _streq(seq, "v") {
    if up { return "В"; }
    return "в";
  }
  if _streq(seq, "w") {
    if up { return "В"; }
    return "в";
  }
  if _streq(seq, "x") {
    if up { return "Кс"; }
    return "кс";
  }
  if _streq(seq, "y") {
    if up { return "Й"; }
    return "й";
  }
  if _streq(seq, "z") {
    if up { return "З"; }
    return "з";
  }
  return "";
}

/// Transliterate Latin letters to the covered Cyrillic subset using the
/// documented digraph table (shch, sh, ch, zh, kh, ts, yu, ya, yo, ye) with
/// the longest match first; apostrophe maps to the soft sign. Non-letters
/// pass through unchanged. The case of the first input letter is applied to
/// the first output letter.
pub fn translit_latin_to_cyrillic(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    if _is_letter_byte(b) {
      let up = _is_upper_byte(b);
      var seq = "";
      if _seq_matches(s, i, "shch") { seq = "shch"; }
      elif _seq_matches(s, i, "sh") { seq = "sh"; }
      elif _seq_matches(s, i, "ch") { seq = "ch"; }
      elif _seq_matches(s, i, "zh") { seq = "zh"; }
      elif _seq_matches(s, i, "kh") { seq = "kh"; }
      elif _seq_matches(s, i, "ts") { seq = "ts"; }
      elif _seq_matches(s, i, "yu") { seq = "yu"; }
      elif _seq_matches(s, i, "ya") { seq = "ya"; }
      elif _seq_matches(s, i, "yo") { seq = "yo"; }
      elif _seq_matches(s, i, "ye") { seq = "ye"; }
      else {
        seq = string.str_lower(string.str_slice(s, i, i + 1));
      }
      let repl = _cyr_map(seq, up);
      if repl.len() > 0 {
        _push_str(&mut out, repl);
        i = i + seq.len();
      } else {
        out.push(b);
        i = i + 1;
      }
    } elif _byte_val(b) == 39 {
      _push_str(&mut out, "ь");
      i = i + 1;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return sb_to_str(&out);
}

// Covered Greek: U+0391..U+03A9 letters (excluding unassigned U+03A2),
// U+03B1..U+03C9 letters (including final sigma U+03C2), and the tonos
// vowels U+03AC, U+03AD, U+03AE, U+03AF, U+03CC, U+03CD, U+03CE.
fn _grk_known(cp: Int) -> Bool {
  if cp >= 0x0391 && cp <= 0x03A9 && cp != 0x03A2 { return true; }
  if cp >= 0x03B1 && cp <= 0x03C9 { return true; }
  if cp == 0x03AC { return true; }
  if cp == 0x03AD { return true; }
  if cp == 0x03AE { return true; }
  if cp == 0x03AF { return true; }
  if cp == 0x03CC { return true; }
  if cp == 0x03CD { return true; }
  if cp == 0x03CE { return true; }
  return false;
}

fn _grk_latin(cp: Int) -> Str {
  if cp == 0x0391 { return "A"; }
  if cp == 0x0392 { return "B"; }
  if cp == 0x0393 { return "G"; }
  if cp == 0x0394 { return "D"; }
  if cp == 0x0395 { return "E"; }
  if cp == 0x0396 { return "Z"; }
  if cp == 0x0397 { return "I"; }
  if cp == 0x0398 { return "Th"; }
  if cp == 0x0399 { return "I"; }
  if cp == 0x039A { return "K"; }
  if cp == 0x039B { return "L"; }
  if cp == 0x039C { return "M"; }
  if cp == 0x039D { return "N"; }
  if cp == 0x039E { return "X"; }
  if cp == 0x039F { return "O"; }
  if cp == 0x03A0 { return "P"; }
  if cp == 0x03A1 { return "R"; }
  if cp == 0x03A3 { return "S"; }
  if cp == 0x03A4 { return "T"; }
  if cp == 0x03A5 { return "Y"; }
  if cp == 0x03A6 { return "F"; }
  if cp == 0x03A7 { return "Ch"; }
  if cp == 0x03A8 { return "Ps"; }
  if cp == 0x03A9 { return "O"; }
  if cp == 0x03B1 { return "a"; }
  if cp == 0x03B2 { return "b"; }
  if cp == 0x03B3 { return "g"; }
  if cp == 0x03B4 { return "d"; }
  if cp == 0x03B5 { return "e"; }
  if cp == 0x03B6 { return "z"; }
  if cp == 0x03B7 { return "i"; }
  if cp == 0x03B8 { return "th"; }
  if cp == 0x03B9 { return "i"; }
  if cp == 0x03BA { return "k"; }
  if cp == 0x03BB { return "l"; }
  if cp == 0x03BC { return "m"; }
  if cp == 0x03BD { return "n"; }
  if cp == 0x03BE { return "x"; }
  if cp == 0x03BF { return "o"; }
  if cp == 0x03C0 { return "p"; }
  if cp == 0x03C1 { return "r"; }
  if cp == 0x03C2 { return "s"; }
  if cp == 0x03C3 { return "s"; }
  if cp == 0x03C4 { return "t"; }
  if cp == 0x03C5 { return "u"; }
  if cp == 0x03C6 { return "f"; }
  if cp == 0x03C7 { return "ch"; }
  if cp == 0x03C8 { return "ps"; }
  if cp == 0x03C9 { return "o"; }
  if cp == 0x03AC { return "a"; }
  if cp == 0x03AD { return "e"; }
  if cp == 0x03AE { return "i"; }
  if cp == 0x03AF { return "i"; }
  if cp == 0x03CC { return "o"; }
  if cp == 0x03CD { return "u"; }
  if cp == 0x03CE { return "o"; }
  return "";
}

/// Transliterate the covered Greek subset to Latin. ASCII bytes and
/// uncovered code points pass through unchanged; final sigma maps to "s";
/// tonos vowels map to their base vowel. Invalid bytes are copied one byte
/// at a time.
pub fn translit_greek_to_latin(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    let bv: Int = _byte_val(b);
    if bv < 0x80 {
      out.push(b);
      i = i + 1;
    } else {
      let cp = _decode_cp(s, i);
      if cp < 0 {
        out.push(b);
        i = i + 1;
      } else {
        if _grk_known(cp) {
          _push_str(&mut out, _grk_latin(cp));
        } else {
          _push_str(&mut out, string.str_slice(s, i, i + _cp_len(bv)));
        }
        i = i + _cp_len(bv);
      }
    }
  }
  return sb_to_str(&out);
}

// Latin letter sequence -> Greek; `up` capitalizes the first Greek letter.
fn _grk_map(seq: Str, up: Bool) -> Str {
  if _streq(seq, "th") {
    if up { return "Θ"; }
    return "θ";
  }
  if _streq(seq, "ph") {
    if up { return "Φ"; }
    return "φ";
  }
  if _streq(seq, "ch") {
    if up { return "Χ"; }
    return "χ";
  }
  if _streq(seq, "ps") {
    if up { return "Ψ"; }
    return "ψ";
  }
  if _streq(seq, "ks") {
    if up { return "Ξ"; }
    return "ξ";
  }
  if _streq(seq, "kh") {
    if up { return "Χ"; }
    return "χ";
  }
  if _streq(seq, "ou") {
    if up { return "Ου"; }
    return "ου";
  }
  if _streq(seq, "a") {
    if up { return "Α"; }
    return "α";
  }
  if _streq(seq, "b") {
    if up { return "Β"; }
    return "β";
  }
  if _streq(seq, "c") {
    if up { return "Κ"; }
    return "κ";
  }
  if _streq(seq, "d") {
    if up { return "Δ"; }
    return "δ";
  }
  if _streq(seq, "e") {
    if up { return "Ε"; }
    return "ε";
  }
  if _streq(seq, "f") {
    if up { return "Φ"; }
    return "φ";
  }
  if _streq(seq, "g") {
    if up { return "Γ"; }
    return "γ";
  }
  if _streq(seq, "h") {
    if up { return "Η"; }
    return "η";
  }
  if _streq(seq, "i") {
    if up { return "Ι"; }
    return "ι";
  }
  if _streq(seq, "j") {
    if up { return "Ι"; }
    return "ι";
  }
  if _streq(seq, "k") {
    if up { return "Κ"; }
    return "κ";
  }
  if _streq(seq, "l") {
    if up { return "Λ"; }
    return "λ";
  }
  if _streq(seq, "m") {
    if up { return "Μ"; }
    return "μ";
  }
  if _streq(seq, "n") {
    if up { return "Ν"; }
    return "ν";
  }
  if _streq(seq, "o") {
    if up { return "Ο"; }
    return "ο";
  }
  if _streq(seq, "p") {
    if up { return "Π"; }
    return "π";
  }
  if _streq(seq, "q") {
    if up { return "Κ"; }
    return "κ";
  }
  if _streq(seq, "r") {
    if up { return "Ρ"; }
    return "ρ";
  }
  if _streq(seq, "s") {
    if up { return "Σ"; }
    return "σ";
  }
  if _streq(seq, "t") {
    if up { return "Τ"; }
    return "τ";
  }
  if _streq(seq, "u") {
    if up { return "Υ"; }
    return "υ";
  }
  if _streq(seq, "v") {
    if up { return "Β"; }
    return "β";
  }
  if _streq(seq, "w") {
    if up { return "Ω"; }
    return "ω";
  }
  if _streq(seq, "x") {
    if up { return "Ξ"; }
    return "ξ";
  }
  if _streq(seq, "y") {
    if up { return "Υ"; }
    return "υ";
  }
  if _streq(seq, "z") {
    if up { return "Ζ"; }
    return "ζ";
  }
  return "";
}

/// Transliterate Latin letters to the covered Greek subset using the
/// documented digraph table (th, ph, ch, ps, ks, kh, ou) with the longest
/// match first; "s" always yields sigma, never final sigma. Non-letters
/// pass through unchanged. The case of the first input letter is applied to
/// the first output letter.
pub fn translit_latin_to_greek(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(s, i);
    if _is_letter_byte(b) {
      let up = _is_upper_byte(b);
      var seq = "";
      if _seq_matches(s, i, "th") { seq = "th"; }
      elif _seq_matches(s, i, "ph") { seq = "ph"; }
      elif _seq_matches(s, i, "ch") { seq = "ch"; }
      elif _seq_matches(s, i, "ps") { seq = "ps"; }
      elif _seq_matches(s, i, "ks") { seq = "ks"; }
      elif _seq_matches(s, i, "kh") { seq = "kh"; }
      elif _seq_matches(s, i, "ou") { seq = "ou"; }
      else {
        seq = string.str_lower(string.str_slice(s, i, i + 1));
      }
      let repl = _grk_map(seq, up);
      if repl.len() > 0 {
        _push_str(&mut out, repl);
        i = i + seq.len();
      } else {
        out.push(b);
        i = i + 1;
      }
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return sb_to_str(&out);
}

// ---------------------------------------------------------------------------
// Domain glossary (one Str blob: "source\ttarget\n" records)
// ---------------------------------------------------------------------------

/// A domain glossary: an immutable value wrapping one record blob with
/// '\t' between source and target and '\n' after every record. Assemble
/// values with glossary_add; entries reject '\t' and '\n' in their fields.
pub type Glossary = {
  blob: Str;
}

fn _make_glossary(blob: Str) -> Glossary {
  return Glossary { blob: blob; };
}

fn _has_separator(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    let v: Int = _byte_val(string.byte_at(s, i));
    if v == 9 || v == 10 { return true; }
    i = i + 1;
  }
  return false;
}

// Start offset of the target for the last entry whose source equals `src`
// case-insensitively, or -1.
fn _glossary_find(g: &Glossary, src: Str) -> Int {
  let b: Str = g.blob;
  let n = b.len();
  var pos = 0;
  var found = -1;
  while pos < n {
    let tab = _find_byte_from(b, pos, 9);
    let nl = _find_byte_from(b, pos, 10);
    if tab < 0 || nl < 0 || nl < tab {
      pos = n;
    } else {
      let key = string.str_slice(b, pos, tab);
      if _ci_equals(key, src) { found = tab + 1; }
      pos = nl + 1;
    }
  }
  return found;
}

fn _glossary_target(g: &Glossary, start: Int) -> Str {
  let b: Str = g.blob;
  let nl = _find_byte_from(b, start, 10);
  if nl < 0 { return string.str_slice(b, start, b.len()); }
  return string.str_slice(b, start, nl);
}

/// Empty glossary.
pub fn glossary_new() -> Glossary {
  return _make_glossary("");
}

/// Number of entries in the glossary.
pub fn glossary_len(g: &Glossary) -> Int {
  let b: Str = g.blob;
  var count = 0;
  var i = 0;
  while i < b.len() {
    let v: Int = _byte_val(string.byte_at(b, i));
    if v == 10 { count = count + 1; }
    i = i + 1;
  }
  return count;
}

/// Add one source -> target entry and return the new glossary. An empty
/// source, or a source/target containing '\t' or '\n', leaves the glossary
/// unchanged (rejected entries are documented, not reported). Adding a
/// source that already exists appends a later entry; lookups return the
/// most recently added match.
pub fn glossary_add(g: &Glossary, src: Str, tgt: Str) -> Glossary {
  let cur: Str = g.blob;
  if src.len() == 0 { return _make_glossary(cur); }
  if _has_separator(src) { return _make_glossary(cur); }
  if _has_separator(tgt) { return _make_glossary(cur); }
  var out = Vec[UInt8].new();
  _push_str(&mut out, cur);
  _push_str(&mut out, src);
  out.push(9u8);
  _push_str(&mut out, tgt);
  out.push(10u8);
  return _make_glossary(sb_to_str(&out));
}

/// Target stored for `src` (case-insensitive); "" when absent. When the
/// same source was added more than once, the most recent target wins.
pub fn glossary_lookup(g: &Glossary, src: Str) -> Str {
  let pos = _glossary_find(g, src);
  if pos < 0 { return ""; }
  return _glossary_target(g, pos);
}

/// True when the glossary has an entry for `src` (case-insensitive).
pub fn glossary_has(g: &Glossary, src: Str) -> Bool {
  return _glossary_find(g, src) >= 0;
}

/// Replace glossary terms inside `text` word by word: a word is a maximal
/// run of ASCII letters, matched case-insensitively against the stored
/// sources, and replaced by the stored target exactly as added. Everything
/// else (punctuation, digits, bytes >= 128) is copied through unchanged;
/// unknown words are kept.
pub fn glossary_apply(g: &Glossary, text: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = text.len();
  var i = 0;
  while i < n {
    let b: UInt8 = string.byte_at(text, i);
    if _is_letter_byte(b) {
      let start = i;
      var j = i;
      var go = true;
      while j < n && go {
        let c: UInt8 = string.byte_at(text, j);
        if _is_letter_byte(c) { j = j + 1; } else { go = false; }
      }
      let word = string.str_slice(text, start, j);
      let pos = _glossary_find(g, word);
      if pos >= 0 {
        _push_str(&mut out, _glossary_target(g, pos));
      } else {
        _push_str(&mut out, word);
      }
      i = j;
    } else {
      out.push(b);
      i = i + 1;
    }
  }
  return sb_to_str(&out);
}
