// XIOM -- xiom.stemming: the classic Porter stemming algorithm
// Port task: replace the xiom.stemming placeholder with a pure-XIOM Porter
// stemmer (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// This is Porter's 1980 algorithm, steps 1a, 1b, 1c, 2, 3, 4, 5a and 5b, and
// follows Martin Porter's reference C implementation for the rule details
// (notably the BLI -> BLE and LOGI -> LOG spellings). The whole algorithm
// runs over a Vec[UInt8]: no Str value is ever compared, so no string
// comparison can be mis-lowered to a pointer compare, and no code point
// arithmetic is involved.
//
// Input contract: lowercase ASCII a-z. A word that contains any other byte
// (uppercase letter, digit, punctuation or non-ASCII UTF-8) and a word
// shorter than three bytes are both returned unchanged. See SPEC.md for the
// complete rule set and its limitations.

module xiom.stemming

use xiom.string;

// --- byte constants ---------------------------------------------------------

const _BYTE_A: UInt8 = 97u8;
const _BYTE_E: UInt8 = 101u8;
const _BYTE_I: UInt8 = 105u8;
const _BYTE_L: UInt8 = 108u8;
const _BYTE_O: UInt8 = 111u8;
const _BYTE_S: UInt8 = 115u8;
const _BYTE_T: UInt8 = 116u8;
const _BYTE_U: UInt8 = 117u8;
const _BYTE_W: UInt8 = 119u8;
const _BYTE_X: UInt8 = 120u8;
const _BYTE_Y: UInt8 = 121u8;
const _BYTE_Z: UInt8 = 122u8;

// --- byte-level helpers -----------------------------------------------------

// Copy a Str into a fresh byte vector. Only called for validated input.
fn _to_bytes(word: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < word.len() {
    out.push(string.byte_at(word, i));
    i = i + 1;
  }
  return out;
}

// True when every byte is an ASCII lowercase letter (a-z).
fn _is_lower_ascii(word: Str) -> Bool {
  var i = 0;
  while i < word.len() {
    let b = string.byte_at(word, i) as Int;
    if b < 97 || b > 122 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Fresh copy of the valid prefix 0..j of buf.
fn _copy_bytes(buf: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i <= j {
    let b: UInt8 = buf[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

// Bytes 0..j with the last n bytes removed.
fn _drop_last(buf: &Vec[UInt8], j: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let keep = j + 1 - n;
  var i = 0;
  while i < keep {
    let b: UInt8 = buf[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

// Bytes 0..j followed by the bytes of text.
fn _append_str(buf: &Vec[UInt8], j: Int, text: Str) -> Vec[UInt8] {
  var out = _copy_bytes(buf, j);
  var i = 0;
  while i < text.len() {
    out.push(string.byte_at(text, i));
    i = i + 1;
  }
  return out;
}

// Bytes 0..j with the last n bytes replaced by the bytes of repl.
fn _replace_tail(buf: &Vec[UInt8], j: Int, n: Int, repl: Str) -> Vec[UInt8] {
  var out = _drop_last(buf, j, n);
  var i = 0;
  while i < repl.len() {
    out.push(string.byte_at(repl, i));
    i = i + 1;
  }
  return out;
}

// True when bytes 0..j end with the ASCII suffix.
fn _suffix_match(buf: &Vec[UInt8], j: Int, suffix: Str) -> Bool {
  let n = suffix.len();
  if n > j + 1 {
    return false;
  }
  let start = j + 1 - n;
  var i = 0;
  while i < n {
    let got: UInt8 = buf[start + i];
    let want: UInt8 = string.byte_at(suffix, i);
    if got != want {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --- Porter predicates ------------------------------------------------------

// True when buf[i] is a consonant. 'y' at index 0 is a consonant; elsewhere
// 'y' is a consonant exactly when the preceding letter is a vowel. Runs of
// 'y' are resolved iteratively to keep this a plain loop.
fn _cons(buf: &Vec[UInt8], i: Int) -> Bool {
  var k = i;
  var flips = 0;
  while k >= 0 {
    let b: UInt8 = buf[k];
    if b == _BYTE_Y {
      flips = flips + 1;
      k = k - 1;
    } elif b == _BYTE_A || b == _BYTE_E || b == _BYTE_I || b == _BYTE_O || b == _BYTE_U {
      if flips % 2 == 1 {
        return true;
      }
      return false;
    } else {
      if flips % 2 == 1 {
        return false;
      }
      return true;
    }
  }
  if flips % 2 == 1 {
    return true;
  }
  return false;
}

// m: the number of VC sequences in bytes 0..j. Each vowel-run to
// consonant-run boundary inside the word is one sequence.
fn _measure(buf: &Vec[UInt8], j: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < j {
    if !_cons(buf, i) && _cons(buf, i + 1) {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

// True when bytes 0..j contain at least one vowel.
fn _contains_vowel(buf: &Vec[UInt8], j: Int) -> Bool {
  var i = 0;
  while i <= j {
    if !_cons(buf, i) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// *d: true when bytes 0..j end in a double consonant.
fn _ends_double_consonant(buf: &Vec[UInt8], j: Int) -> Bool {
  if j < 1 {
    return false;
  }
  let last: UInt8 = buf[j];
  let prev: UInt8 = buf[j - 1];
  if last != prev {
    return false;
  }
  return _cons(buf, j);
}

// *o: true when buf ends in consonant-vowel-consonant at index i, with the
// final consonant not w, x or y.
fn _ends_cvc(buf: &Vec[UInt8], i: Int) -> Bool {
  if i < 2 {
    return false;
  }
  if !_cons(buf, i) {
    return false;
  }
  if _cons(buf, i - 1) {
    return false;
  }
  if !_cons(buf, i - 2) {
    return false;
  }
  let b: UInt8 = buf[i];
  if b == _BYTE_W || b == _BYTE_X || b == _BYTE_Y {
    return false;
  }
  return true;
}

// --- algorithm steps --------------------------------------------------------

// Step 1a: SSES -> SS, IES -> I, SS -> SS, S -> "".
fn _step1a(buf: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(buf, j, "sses") {
    return _replace_tail(buf, j, 4, "ss");
  }
  if _suffix_match(buf, j, "ies") {
    return _replace_tail(buf, j, 3, "i");
  }
  if _suffix_match(buf, j, "ss") {
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "s") {
    return _drop_last(buf, j, 1);
  }
  return _copy_bytes(buf, j);
}

// Step 1b cleanup: AT -> ATE, BL -> BLE, IZ -> IZE, otherwise a final double
// consonant loses one letter (unless it is l, s or z), otherwise a
// one-measure word ending cvc gains an E.
fn _step1b_after_cut(buf: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(buf, j, "at") {
    return _append_str(buf, j, "e");
  }
  if _suffix_match(buf, j, "bl") {
    return _append_str(buf, j, "e");
  }
  if _suffix_match(buf, j, "iz") {
    return _append_str(buf, j, "e");
  }
  if _ends_double_consonant(buf, j) {
    let last: UInt8 = buf[j];
    if last == _BYTE_L || last == _BYTE_S || last == _BYTE_Z {
      return _copy_bytes(buf, j);
    }
    return _drop_last(buf, j, 1);
  }
  if _measure(buf, j) == 1 && _ends_cvc(buf, j) {
    return _append_str(buf, j, "e");
  }
  return _copy_bytes(buf, j);
}

// Step 1b: (m>0) EED -> EE; (*v*) ED -> ""; (*v*) ING -> "", each cut
// followed by the cleanup rules above.
fn _step1b(buf: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(buf, j, "eed") {
    if _measure(buf, j - 3) > 0 {
      return _drop_last(buf, j, 1);
    }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "ed") {
    if _contains_vowel(buf, j - 2) {
      let cut = _drop_last(buf, j, 2);
      return _step1b_after_cut(&cut, cut.len() - 1);
    }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "ing") {
    if _contains_vowel(buf, j - 3) {
      let cut = _drop_last(buf, j, 3);
      return _step1b_after_cut(&cut, cut.len() - 1);
    }
    return _copy_bytes(buf, j);
  }
  return _copy_bytes(buf, j);
}

// Step 1c: (*v*) Y -> I.
fn _step1c(buf: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(buf, j, "y") {
    if _contains_vowel(buf, j - 1) {
      return _replace_tail(buf, j, 1, "i");
    }
  }
  return _copy_bytes(buf, j);
}

// Step 2: the first matching suffix from the ordered table is replaced when
// the stem has m > 0; a matched suffix with m == 0 stops the step.
fn _step2(buf: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(buf, j, "ational") {
    if _measure(buf, j - 7) > 0 { return _replace_tail(buf, j, 7, "ate"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "tional") {
    if _measure(buf, j - 6) > 0 { return _replace_tail(buf, j, 6, "tion"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "enci") {
    if _measure(buf, j - 4) > 0 { return _replace_tail(buf, j, 4, "ence"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "anci") {
    if _measure(buf, j - 4) > 0 { return _replace_tail(buf, j, 4, "ance"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "izer") {
    if _measure(buf, j - 4) > 0 { return _replace_tail(buf, j, 4, "ize"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "bli") {
    if _measure(buf, j - 3) > 0 { return _replace_tail(buf, j, 3, "ble"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "alli") {
    if _measure(buf, j - 4) > 0 { return _replace_tail(buf, j, 4, "al"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "entli") {
    if _measure(buf, j - 5) > 0 { return _replace_tail(buf, j, 5, "ent"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "eli") {
    if _measure(buf, j - 3) > 0 { return _replace_tail(buf, j, 3, "e"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "ousli") {
    if _measure(buf, j - 5) > 0 { return _replace_tail(buf, j, 5, "ous"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "ization") {
    if _measure(buf, j - 7) > 0 { return _replace_tail(buf, j, 7, "ize"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "ation") {
    if _measure(buf, j - 5) > 0 { return _replace_tail(buf, j, 5, "ate"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "ator") {
    if _measure(buf, j - 4) > 0 { return _replace_tail(buf, j, 4, "ate"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "alism") {
    if _measure(buf, j - 5) > 0 { return _replace_tail(buf, j, 5, "al"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "iveness") {
    if _measure(buf, j - 7) > 0 { return _replace_tail(buf, j, 7, "ive"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "fulness") {
    if _measure(buf, j - 7) > 0 { return _replace_tail(buf, j, 7, "ful"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "ousness") {
    if _measure(buf, j - 7) > 0 { return _replace_tail(buf, j, 7, "ous"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "aliti") {
    if _measure(buf, j - 5) > 0 { return _replace_tail(buf, j, 5, "al"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "iviti") {
    if _measure(buf, j - 5) > 0 { return _replace_tail(buf, j, 5, "ive"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "biliti") {
    if _measure(buf, j - 6) > 0 { return _replace_tail(buf, j, 6, "ble"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "logi") {
    if _measure(buf, j - 4) > 0 { return _replace_tail(buf, j, 4, "log"); }
    return _copy_bytes(buf, j);
  }
  return _copy_bytes(buf, j);
}

// Step 3: (m>0) ICATE -> IC, ATIVE -> "", ALIZE -> AL, ICITI -> IC,
// ICAL -> IC, FUL -> "", NESS -> "".
fn _step3(buf: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(buf, j, "icate") {
    if _measure(buf, j - 5) > 0 { return _replace_tail(buf, j, 5, "ic"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "ative") {
    if _measure(buf, j - 5) > 0 { return _drop_last(buf, j, 5); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "alize") {
    if _measure(buf, j - 5) > 0 { return _replace_tail(buf, j, 5, "al"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "iciti") {
    if _measure(buf, j - 5) > 0 { return _replace_tail(buf, j, 5, "ic"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "ical") {
    if _measure(buf, j - 4) > 0 { return _replace_tail(buf, j, 4, "ic"); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "ful") {
    if _measure(buf, j - 3) > 0 { return _drop_last(buf, j, 3); }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "ness") {
    if _measure(buf, j - 4) > 0 { return _drop_last(buf, j, 4); }
    return _copy_bytes(buf, j);
  }
  return _copy_bytes(buf, j);
}

// Remove a step-4 suffix when its stem has m > 1.
fn _step4_cut(buf: &Vec[UInt8], j: Int, n: Int) -> Vec[UInt8] {
  if _measure(buf, j - n) > 1 {
    return _drop_last(buf, j, n);
  }
  return _copy_bytes(buf, j);
}

// Step 4: (m>1) AL, ANCE, ENCE, ER, IC, ABLE, IBLE, ANT, EMENT, MENT, ENT,
// (S or T) ION, OU, ISM, ATE, ITI, OUS, IVE, IZE -> "".
fn _step4(buf: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(buf, j, "al") { return _step4_cut(buf, j, 2); }
  if _suffix_match(buf, j, "ance") { return _step4_cut(buf, j, 4); }
  if _suffix_match(buf, j, "ence") { return _step4_cut(buf, j, 4); }
  if _suffix_match(buf, j, "er") { return _step4_cut(buf, j, 2); }
  if _suffix_match(buf, j, "ic") { return _step4_cut(buf, j, 2); }
  if _suffix_match(buf, j, "able") { return _step4_cut(buf, j, 4); }
  if _suffix_match(buf, j, "ible") { return _step4_cut(buf, j, 4); }
  if _suffix_match(buf, j, "ant") { return _step4_cut(buf, j, 3); }
  if _suffix_match(buf, j, "ement") { return _step4_cut(buf, j, 5); }
  if _suffix_match(buf, j, "ment") { return _step4_cut(buf, j, 4); }
  if _suffix_match(buf, j, "ent") { return _step4_cut(buf, j, 3); }
  if _suffix_match(buf, j, "ion") {
    let stem_j = j - 3;
    if stem_j >= 0 {
      let b: UInt8 = buf[stem_j];
      if b == _BYTE_S || b == _BYTE_T {
        return _step4_cut(buf, j, 3);
      }
    }
    return _copy_bytes(buf, j);
  }
  if _suffix_match(buf, j, "ou") { return _step4_cut(buf, j, 2); }
  if _suffix_match(buf, j, "ism") { return _step4_cut(buf, j, 3); }
  if _suffix_match(buf, j, "ate") { return _step4_cut(buf, j, 3); }
  if _suffix_match(buf, j, "iti") { return _step4_cut(buf, j, 3); }
  if _suffix_match(buf, j, "ous") { return _step4_cut(buf, j, 3); }
  if _suffix_match(buf, j, "ive") { return _step4_cut(buf, j, 3); }
  if _suffix_match(buf, j, "ize") { return _step4_cut(buf, j, 3); }
  return _copy_bytes(buf, j);
}

// Step 5a: (m>1) E -> ""; (m==1 and not cvc) E -> "".
fn _step5a(buf: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(buf, j, "e") {
    let m = _measure(buf, j);
    if m > 1 {
      return _drop_last(buf, j, 1);
    }
    if m == 1 {
      if !_ends_cvc(buf, j - 1) {
        return _drop_last(buf, j, 1);
      }
    }
  }
  return _copy_bytes(buf, j);
}

// Step 5b: (m>1 and *d and *L) -> single letter.
fn _step5b(buf: &Vec[UInt8], j: Int) -> Vec[UInt8] {
  if _suffix_match(buf, j, "l") {
    if _ends_double_consonant(buf, j) {
      if _measure(buf, j) > 1 {
        return _drop_last(buf, j, 1);
      }
    }
  }
  return _copy_bytes(buf, j);
}

// --- public API -------------------------------------------------------------

/// Stem one English word with the classic Porter algorithm.
/// Params: word - assumed lowercase ASCII a-z. A word containing any other
/// byte (uppercase, digit, punctuation, non-ASCII UTF-8) is returned
/// unchanged, as is a word shorter than three bytes.
/// Returns: the stem, a prefix of the input; stem("") is "".
/// Error case: none.
/// Complexity: O(|word|) per step, O(|word|) in total.
pub fn stem(word: Str) -> Str {
  if word.len() < 3 {
    return word;
  }
  if !_is_lower_ascii(word) {
    return word;
  }
  let source = _to_bytes(word);
  let s1 = _step1a(&source, source.len() - 1);
  let s2 = _step1b(&s1, s1.len() - 1);
  let s3 = _step1c(&s2, s2.len() - 1);
  let s4 = _step2(&s3, s3.len() - 1);
  let s5 = _step3(&s4, s4.len() - 1);
  let s6 = _step4(&s5, s5.len() - 1);
  let s7 = _step5a(&s6, s6.len() - 1);
  let s8 = _step5b(&s7, s7.len() - 1);
  return Str::from_utf8(s8);
}

/// Stem every word of a slice, preserving order and length.
/// Params: words - the words to stem.
/// Returns: a fresh Vec[Str] with one stem per input word.
/// Error case: none.
/// Complexity: O(total input bytes).
pub fn stem_all(words: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < words.len() {
    out.push(stem(words[i]));
    i = i + 1;
  }
  return out;
}

/// Porter's m for one word: the number of VC sequences in it.
/// Params: word - assumed lowercase ASCII a-z (other bytes are treated as
/// consonants by the diagnostic measurement).
/// Returns: 0 for "" and for all-consonant or all-vowel words; for example
/// stem_measure("tr") == 0, stem_measure("tree") == 0 and
/// stem_measure("trouble") == 1.
/// Error case: none.
/// Complexity: O(|word|).
pub fn stem_measure(word: Str) -> Int {
  if word.len() == 0 {
    return 0;
  }
  let buf = _to_bytes(word);
  return _measure(&buf, buf.len() - 1);
}
