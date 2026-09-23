// XIOM -- xiom.plural: English pluralization and singularization
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Rule-table English inflection for lowercase ASCII words, preserving an
// initial uppercase letter on output. Irregular and invariant words are
// table-driven; every other word follows the ordered suffix rules in
// SPEC.md. All functions are total: there are no error paths.

module xiom.plural

use xiom.string;
use xiom.string.compare;
use xiom.string.lowercase;
use xiom.string.uppercase;
use xiom.convert;

// --- internal helpers -------------------------------------------------------

// True when `word` starts with an ASCII uppercase letter (byte 65..90).
fn _starts_upper(word: Str) -> Bool {
  if str_len(word) == 0 { return false; }
  let b = byte_at(word, 0) as Int;
  return b >= 65 && b <= 90;
}

// Uppercase the first character of `s`, leaving the remaining bytes alone.
fn _capitalize_first(s: Str) -> Str {
  let n = str_len(s);
  if n == 0 { return ""; }
  return str_uppercase(str_slice(s, 0, 1)) + str_slice(s, 1, n);
}

// True when the single-character string `c` is an ASCII vowel (a, e, i, o, u).
fn _is_vowel(c: Str) -> Bool {
  if str_compare(c, "a") == 0 { return true; }
  if str_compare(c, "e") == 0 { return true; }
  if str_compare(c, "i") == 0 { return true; }
  if str_compare(c, "o") == 0 { return true; }
  if str_compare(c, "u") == 0 { return true; }
  return false;
}

// --- irregular and invariant tables -----------------------------------------

// Irregular singular -> plural pairs. Returns "" when `lower` has no entry.
fn _irregular_plural(lower: Str) -> Str {
  if str_compare(lower, "person") == 0 { return "people"; }
  if str_compare(lower, "man") == 0 { return "men"; }
  if str_compare(lower, "woman") == 0 { return "women"; }
  if str_compare(lower, "child") == 0 { return "children"; }
  if str_compare(lower, "tooth") == 0 { return "teeth"; }
  if str_compare(lower, "foot") == 0 { return "feet"; }
  if str_compare(lower, "mouse") == 0 { return "mice"; }
  if str_compare(lower, "goose") == 0 { return "geese"; }
  if str_compare(lower, "ox") == 0 { return "oxen"; }
  if str_compare(lower, "datum") == 0 { return "data"; }
  if str_compare(lower, "medium") == 0 { return "media"; }
  if str_compare(lower, "analysis") == 0 { return "analyses"; }
  if str_compare(lower, "basis") == 0 { return "bases"; }
  if str_compare(lower, "crisis") == 0 { return "crises"; }
  if str_compare(lower, "thesis") == 0 { return "theses"; }
  if str_compare(lower, "index") == 0 { return "indices"; }
  if str_compare(lower, "matrix") == 0 { return "matrices"; }
  if str_compare(lower, "vertex") == 0 { return "vertices"; }
  if str_compare(lower, "appendix") == 0 { return "appendices"; }
  return "";
}

// Irregular plural -> singular pairs. Returns "" when `lower` has no entry.
fn _irregular_singular(lower: Str) -> Str {
  if str_compare(lower, "people") == 0 { return "person"; }
  if str_compare(lower, "men") == 0 { return "man"; }
  if str_compare(lower, "women") == 0 { return "woman"; }
  if str_compare(lower, "children") == 0 { return "child"; }
  if str_compare(lower, "teeth") == 0 { return "tooth"; }
  if str_compare(lower, "feet") == 0 { return "foot"; }
  if str_compare(lower, "mice") == 0 { return "mouse"; }
  if str_compare(lower, "geese") == 0 { return "goose"; }
  if str_compare(lower, "oxen") == 0 { return "ox"; }
  if str_compare(lower, "data") == 0 { return "datum"; }
  if str_compare(lower, "media") == 0 { return "medium"; }
  if str_compare(lower, "analyses") == 0 { return "analysis"; }
  if str_compare(lower, "bases") == 0 { return "basis"; }
  if str_compare(lower, "crises") == 0 { return "crisis"; }
  if str_compare(lower, "theses") == 0 { return "thesis"; }
  if str_compare(lower, "indices") == 0 { return "index"; }
  if str_compare(lower, "matrices") == 0 { return "matrix"; }
  if str_compare(lower, "vertices") == 0 { return "vertex"; }
  if str_compare(lower, "appendices") == 0 { return "appendix"; }
  return "";
}

// Invariant nouns: the same form is both singular and plural.
fn _is_invariant(lower: Str) -> Bool {
  if str_compare(lower, "sheep") == 0 { return true; }
  if str_compare(lower, "deer") == 0 { return true; }
  if str_compare(lower, "fish") == 0 { return true; }
  if str_compare(lower, "series") == 0 { return true; }
  if str_compare(lower, "species") == 0 { return true; }
  return false;
}

// --- suffix tables ----------------------------------------------------------

// f-stems that take -ves: leaf, wolf, half, shelf, calf, loaf, thief, scarf, self.
fn _is_f_ves_stem(stem: Str) -> Bool {
  if str_compare(stem, "lea") == 0 { return true; }
  if str_compare(stem, "wol") == 0 { return true; }
  if str_compare(stem, "hal") == 0 { return true; }
  if str_compare(stem, "shel") == 0 { return true; }
  if str_compare(stem, "cal") == 0 { return true; }
  if str_compare(stem, "loa") == 0 { return true; }
  if str_compare(stem, "thie") == 0 { return true; }
  if str_compare(stem, "scar") == 0 { return true; }
  if str_compare(stem, "sel") == 0 { return true; }
  return false;
}

// f-words that keep -s against the -ves list: roof, chief, belief, chef, proof.
fn _is_f_exception(word: Str) -> Bool {
  if str_compare(word, "roof") == 0 { return true; }
  if str_compare(word, "chief") == 0 { return true; }
  if str_compare(word, "belief") == 0 { return true; }
  if str_compare(word, "chef") == 0 { return true; }
  if str_compare(word, "proof") == 0 { return true; }
  return false;
}

// o-words that take -oes: hero, potato, tomato, echo, veto, volcano.
fn _is_o_es_word(lower: Str) -> Bool {
  if str_compare(lower, "hero") == 0 { return true; }
  if str_compare(lower, "potato") == 0 { return true; }
  if str_compare(lower, "tomato") == 0 { return true; }
  if str_compare(lower, "echo") == 0 { return true; }
  if str_compare(lower, "veto") == 0 { return true; }
  if str_compare(lower, "volcano") == 0 { return true; }
  return false;
}

// o-words that take -s against the -oes list: photo, piano, halo, solo, memo, kilo.
fn _is_o_exception(word: Str) -> Bool {
  if str_compare(word, "photo") == 0 { return true; }
  if str_compare(word, "piano") == 0 { return true; }
  if str_compare(word, "halo") == 0 { return true; }
  if str_compare(word, "solo") == 0 { return true; }
  if str_compare(word, "memo") == 0 { return true; }
  if str_compare(word, "kilo") == 0 { return true; }
  return false;
}

// Plural -ves forms whose singular must keep the e: knife, wife, life, ...
fn _ves_known_singular(lower: Str) -> Str {
  if str_compare(lower, "knives") == 0 { return "knife"; }
  if str_compare(lower, "leaves") == 0 { return "leaf"; }
  if str_compare(lower, "wolves") == 0 { return "wolf"; }
  if str_compare(lower, "wives") == 0 { return "wife"; }
  if str_compare(lower, "lives") == 0 { return "life"; }
  if str_compare(lower, "halves") == 0 { return "half"; }
  if str_compare(lower, "shelves") == 0 { return "shelf"; }
  if str_compare(lower, "calves") == 0 { return "calf"; }
  if str_compare(lower, "loaves") == 0 { return "loaf"; }
  if str_compare(lower, "thieves") == 0 { return "thief"; }
  if str_compare(lower, "scarves") == 0 { return "scarf"; }
  return "";
}

// Plural -oes forms with their exact singulars: hero, potato, tomato, ...
fn _oes_known_singular(lower: Str) -> Str {
  if str_compare(lower, "heroes") == 0 { return "hero"; }
  if str_compare(lower, "potatoes") == 0 { return "potato"; }
  if str_compare(lower, "tomatoes") == 0 { return "tomato"; }
  if str_compare(lower, "echoes") == 0 { return "echo"; }
  if str_compare(lower, "vetoes") == 0 { return "veto"; }
  if str_compare(lower, "volcanoes") == 0 { return "volcano"; }
  return "";
}

// True when `lower` ends with a sibilant that takes -es (ch, sh, ss, x, z, s).
fn _ends_sibilant(lower: Str) -> Bool {
  if str_ends_with(lower, "ch") { return true; }
  if str_ends_with(lower, "sh") { return true; }
  if str_ends_with(lower, "ss") { return true; }
  if str_ends_with(lower, "x") { return true; }
  if str_ends_with(lower, "z") { return true; }
  if str_ends_with(lower, "s") { return true; }
  return false;
}

// --- core rules -------------------------------------------------------------

// Core pluralization for an already-lowercased word.
fn _plural_lower(lower: Str) -> Str {
  let irregular = _irregular_plural(lower);
  if str_len(irregular) > 0 { return irregular; }
  if _is_invariant(lower) { return lower; }
  let n = str_len(lower);
  if _ends_sibilant(lower) { return lower + "es"; }
  if n >= 2 && str_ends_with(lower, "y") {
    let before = str_slice(lower, n - 2, n - 1);
    if !_is_vowel(before) { return str_slice(lower, 0, n - 1) + "ies"; }
  }
  if str_ends_with(lower, "fe") { return str_slice(lower, 0, n - 2) + "ves"; }
  if str_ends_with(lower, "f") {
    let stem = str_slice(lower, 0, n - 1);
    if _is_f_ves_stem(stem) && !_is_f_exception(lower) { return stem + "ves"; }
    return lower + "s";
  }
  if str_ends_with(lower, "o") {
    if _is_o_es_word(lower) && !_is_o_exception(lower) { return lower + "es"; }
    return lower + "s";
  }
  return lower + "s";
}

// Core singularization for an already-lowercased word.
fn _singular_lower(lower: Str) -> Str {
  let irregular = _irregular_singular(lower);
  if str_len(irregular) > 0 { return irregular; }
  if _is_invariant(lower) { return lower; }
  let n = str_len(lower);
  if str_ends_with(lower, "ies") { return str_slice(lower, 0, n - 3) + "y"; }
  if str_ends_with(lower, "ves") {
    let known = _ves_known_singular(lower);
    if str_len(known) > 0 { return known; }
    return str_slice(lower, 0, n - 3) + "f";
  }
  if str_ends_with(lower, "oes") {
    let known = _oes_known_singular(lower);
    if str_len(known) > 0 { return known; }
    return str_slice(lower, 0, n - 1);
  }
  if str_ends_with(lower, "ches") || str_ends_with(lower, "shes") || str_ends_with(lower, "sses") || str_ends_with(lower, "xes") || str_ends_with(lower, "zes") {
    return str_slice(lower, 0, n - 2);
  }
  if str_ends_with(lower, "s") && !str_ends_with(lower, "ss") {
    return str_slice(lower, 0, n - 1);
  }
  return lower;
}

// --- public API -------------------------------------------------------------

/// Pluralize an English word.
/// Params: word - a lowercase ASCII English word; an initial uppercase ASCII
/// letter is preserved on the result.
/// Returns: the plural form; "" for "".
/// Error case: none (best-effort rule-table result for unknown words).
/// Complexity: O(|word|).
pub fn plural_pluralize(word: Str) -> Str {
  if str_len(word) == 0 { return ""; }
  let result = _plural_lower(str_lowercase(word));
  if _starts_upper(word) { return _capitalize_first(result); }
  return result;
}

/// Singularize an English word.
/// Params: word - a lowercase ASCII English word; an initial uppercase ASCII
/// letter is preserved on the result.
/// Returns: the singular form; "" for "".
/// Error case: none (best-effort rule-table result for unknown words).
/// Complexity: O(|word|).
pub fn plural_singularize(word: Str) -> Str {
  if str_len(word) == 0 { return ""; }
  let result = _singular_lower(str_lowercase(word));
  if _starts_upper(word) { return _capitalize_first(result); }
  return result;
}

/// True when the lowercase form is irregular, in either direction, or an
/// invariant noun (people, person, sheep, ...).
/// Params: word - the word to test.
/// Returns: false for words handled purely by suffix rules (cat, city, box).
/// Error case: none. Complexity: O(|word|) table scans.
pub fn plural_is_irregular(word: Str) -> Bool {
  let lower = str_lowercase(word);
  if _is_invariant(lower) { return true; }
  if str_len(_irregular_plural(lower)) > 0 { return true; }
  if str_len(_irregular_singular(lower)) > 0 { return true; }
  return false;
}

/// Number-aware noun phrase.
/// Params: n - the count; singular - the singular noun.
/// Returns: "1 <singular>" when n == 1, otherwise "<n> <plural>" using
/// plural_pluralize (so "2 people", "0 items", "1 person").
/// Error case: none. Complexity: O(|singular|).
pub fn plural_count(n: Int, singular: Str) -> Str {
  if n == 1 { return "1 " + singular; }
  return int_to_string(n) + " " + plural_pluralize(singular);
}

/// Pluralize every element, preserving order and per-word capitalization.
/// Params: words - the words to pluralize.
/// Returns: a fresh Vec[Str] of the same length as `words`.
/// Error case: none. Complexity: O(total input bytes).
pub fn plural_pluralize_all(words: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  let n = words.len();
  var i: Int = 0;
  while i < n {
    out.push(plural_pluralize(words[i]));
    i = i + 1;
  }
  return out;
}
