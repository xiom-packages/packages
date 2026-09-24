// XIOM -- xiom.ngram: word and character n-grams, similarity, MinHash
// Port task: replace the xiom.ngram placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The scanner is byte-wise over the UTF-8 representation of Str. Word tokens
// are maximal runs of ASCII [A-Za-z0-9] lowercased with str_lower; every
// other byte, including every non-ASCII byte, is a separator. Character
// shingles are verbatim byte slices, so UTF-8 passes through byte-exact.
// Set-similarity scores are permille integers (0..1000, truncated) and the
// MinHash signature uses an in-module 32-bit FNV-1a hash. Every entry point
// is infallible (Vec/Int-returning, no Result channel). Vec-sourced Str
// values are compared only through str_compare (BUG 17). See SPEC.md for the
// full semantics, formulas and test plan.

module xiom.ngram

use xiom.string;
use xiom.string.compare;
use xiom.convert.int;

// --- byte classes -----------------------------------------------------------

const _NG_ZERO: UInt8 = 48u8;      // '0'
const _NG_NINE: UInt8 = 57u8;      // '9'
const _NG_UPPER_A: UInt8 = 65u8;   // 'A'
const _NG_UPPER_Z: UInt8 = 90u8;   // 'Z'
const _NG_LOWER_A: UInt8 = 97u8;   // 'a'
const _NG_LOWER_Z: UInt8 = 122u8;  // 'z'

// Word byte: ASCII letter or digit. Underscore, punctuation, whitespace and
// every byte of a multi-byte UTF-8 sequence are separators.
fn _is_word_byte(b: UInt8) -> Bool {
  if b >= _NG_ZERO && b <= _NG_NINE { return true; }
  if b >= _NG_UPPER_A && b <= _NG_UPPER_Z { return true; }
  if b >= _NG_LOWER_A && b <= _NG_LOWER_Z { return true; }
  return false;
}

// --- internal helpers -------------------------------------------------------

// Str equality through str_compare, never `==` (BUG 17).
fn _str_eq(a: Str, b: Str) -> Bool {
  return str_compare(a, b) == 0;
}

// True when the slice contains `s` (linear scan, str_compare).
fn _contains(v: &Vec[Str], s: Str) -> Bool {
  var i = 0;
  while i < v.len() {
    let cur: Str = v[i];
    if _str_eq(cur, s) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Size of the intersection of two de-duplicated slices.
fn _intersection_size(a: &Vec[Str], b: &Vec[Str]) -> Int {
  var count = 0;
  var i = 0;
  while i < a.len() {
    let s: Str = a[i];
    if _contains(b, s) {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

// --- 32-bit FNV-1a ----------------------------------------------------------

const _NG_FNV_OFFSET: Int = 2166136261;   // 32-bit offset basis
const _NG_FNV_PRIME: Int = 16777619;      // 32-bit FNV prime
const _NG_U32_MOD: Int = 4294967296;      // 2^32

// FNV-1a 32-bit over all bytes of `s`, continuing from `base`.
// h = ((h XOR byte) * prime) mod 2^32, with h seeded by the caller.
fn _fnv1a32_step(s: Str, base: Int) -> Int {
  var h = base;
  let len = s.len();
  var i = 0;
  while i < len {
    let b: Int = byte_at(s, i) as Int;
    h = (h ^ b) % _NG_U32_MOD;
    h = (h * _NG_FNV_PRIME) % _NG_U32_MOD;
    i = i + 1;
  }
  return h;
}

// MinHash slot hash of `shingle`: FNV-1a over the byte string
// "<seed>:<slot>:<shingle>", where seed and slot are decimal renderings.
fn _minhash_hash(seed: Int, slot: Int, shingle: Str) -> Int {
  var h = _fnv1a32_step(int_to_string(seed), _NG_FNV_OFFSET);
  h = _fnv1a32_step(":", h);
  h = _fnv1a32_step(int_to_string(slot), h);
  h = _fnv1a32_step(":", h);
  return _fnv1a32_step(shingle, h);
}

// --- public API -------------------------------------------------------------

/// Scan text into lowercase word tokens.
/// A token is a maximal run of ASCII letters/digits [A-Za-z0-9]; every other
/// byte -- punctuation, whitespace, underscore and each byte of a multi-byte
/// UTF-8 sequence -- is a separator. Tokens are lowercased with the ASCII
/// lowering of str_lower, so "Hello" and "hello" tokenize identically.
/// Params: text - the text to scan.
/// Returns: one lowercased Str per word, in order; [] for empty or
/// separator-only text.
/// Errors: none.
/// Complexity: O(n).
pub fn ngram_words(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  var i = 0;
  while i < len {
    let b = byte_at(text, i);
    if _is_word_byte(b) {
      let start = i;
      var j = i;
      while j < len {
        if _is_word_byte(byte_at(text, j)) {
          j = j + 1;
        } else {
          break;
        }
      }
      out.push(str_lower(str_slice(text, start, j)));
      i = j;
    } else {
      i = i + 1;
    }
  }
  return out;
}

/// Word n-grams: contiguous windows of `n` words joined with single spaces.
/// Word contents are not modified (call ngram_words first for lowercase).
/// Params: words - the token sequence; n - the window size.
/// Returns: words.len() - n + 1 shingles in order when n >= 1 and there are
/// at least n words; [] when n < 1 or words.len() < n.
/// Errors: none.
/// Complexity: O(n * window length) over the joined output.
pub fn ngram_shingles(words: &Vec[Str], n: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  if n < 1 {
    return out;
  }
  if words.len() < n {
    return out;
  }
  var i = 0;
  while i + n <= words.len() {
    var joined = "";
    var j = 0;
    while j < n {
      if j > 0 {
        joined = joined + " ";
      }
      let part: Str = words[i + j];
      joined = joined + part;
      j = j + 1;
    }
    out.push(joined);
    i = i + 1;
  }
  return out;
}

/// Character (byte) n-grams: verbatim byte slices of length `n`.
/// Each shingle is str_slice(text, i, i + n) for i in 0..len-n, so UTF-8
/// passes through byte-exact and a multi-byte character can be split across
/// two shingles.
/// Params: text - the text to slice; n - the window size in bytes.
/// Returns: text.len() - n + 1 shingles in order when n >= 1 and
/// text.len() >= n; [] otherwise.
/// Errors: none.
/// Complexity: O(n * (len - n + 1)) over the copied bytes.
pub fn ngram_char_shingles(text: Str, n: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  if n < 1 {
    return out;
  }
  let len = text.len();
  if len < n {
    return out;
  }
  var i = 0;
  while i + n <= len {
    out.push(str_slice(text, i, i + n));
    i = i + 1;
  }
  return out;
}

/// De-duplicate shingles, keeping first-seen order.
/// Params: shingles - the (possibly repeated) shingle sequence.
/// Returns: a fresh Vec[Str] with each distinct shingle once, ordered by
/// first occurrence; [] for an empty input.
/// Errors: none.
/// Complexity: O(n^2) str_compare calls, O(n) output.
pub fn ngram_unique(shingles: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < shingles.len() {
    let s: Str = shingles[i];
    if !_contains(&out, s) {
      out.push(s);
    }
    i = i + 1;
  }
  return out;
}

/// Jaccard similarity of two shingle sets, in permille.
/// Duplicates collapse first: |A inter B| / |A union B| with A and B the
/// distinct shingles of `a` and `b`; truncated integer division.
/// Params: a, b - the shingle sequences to compare.
/// Returns: the score in 0..1000; 0 when both sets are empty (the union is
/// empty) or when either union side is empty.
/// Errors: none.
/// Complexity: O(n*m) str_compare calls (n, m = distinct sizes).
pub fn ngram_jaccard(a: &Vec[Str], b: &Vec[Str]) -> Int {
  let ua = ngram_unique(a);
  let ub = ngram_unique(b);
  let inter = _intersection_size(&ua, &ub);
  let union = ua.len() + ub.len() - inter;
  if union == 0 {
    return 0;
  }
  return (inter * 1000) / union;
}

/// Dice (Sorensen-Dice) similarity of two shingle sets, in permille.
/// Duplicates collapse first: 2|A inter B| / (|A| + |B|) over the distinct
/// shingles of `a` and `b`; truncated integer division.
/// Params: a, b - the shingle sequences to compare.
/// Returns: the score in 0..1000; 0 when both sets are empty or when either
/// set is empty.
/// Errors: none.
/// Complexity: O(n*m) str_compare calls (n, m = distinct sizes).
pub fn ngram_dice(a: &Vec[Str], b: &Vec[Str]) -> Int {
  let ua = ngram_unique(a);
  let ub = ngram_unique(b);
  let inter = _intersection_size(&ua, &ub);
  let total = ua.len() + ub.len();
  if total == 0 {
    return 0;
  }
  return (2 * inter * 1000) / total;
}

/// MinHash signature of a shingle collection.
/// `hashes` independent hash slots; slot i is the minimum of
/// fnv1a32(seed:i:shingle) over every shingle (an in-module 32-bit FNV-1a
/// over the bytes of "<seed>:<i>:<shingle>", decimals as rendered by
/// int_to_string). Duplicate shingles cannot lower a minimum twice.
/// Params: shingles - the shingle sequence; hashes - the number of slots;
/// seed - the per-signature salt (any Int, negative allowed).
/// Returns: a Vec[Int] of exactly `hashes` values, each in 0..2^32-1, all 0
/// when `shingles` is empty; [] when hashes < 1.
/// Errors: none.
/// Complexity: O(hashes * shingles * key length).
pub fn ngram_minhash_signature(shingles: &Vec[Str], hashes: Int, seed: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if hashes < 1 {
    return out;
  }
  let total = shingles.len();
  var slot = 0;
  while slot < hashes {
    var best = 0;
    if total > 0 {
      var have = false;
      var k = 0;
      while k < total {
        let s: Str = shingles[k];
        let h = _minhash_hash(seed, slot, s);
        if !have {
          best = h;
          have = true;
        } else {
          if h < best {
            best = h;
          }
        }
        k = k + 1;
      }
    }
    out.push(best);
    slot = slot + 1;
  }
  return out;
}

/// Fraction of matching MinHash slots, in permille.
/// The two signatures must have equal length (they do when produced with the
/// same `hashes` and seed); this is the MinHash estimate of the Jaccard
/// similarity of the underlying shingle sets, truncated.
/// Params: a, b - the two signatures to compare.
/// Returns: matches * 1000 / length in 0..1000; 0 when the lengths differ or
/// when both are empty.
/// Errors: none.
/// Complexity: O(length).
pub fn ngram_signature_similarity(a: &Vec[Int], b: &Vec[Int]) -> Int {
  let n = a.len();
  if n != b.len() {
    return 0;
  }
  if n == 0 {
    return 0;
  }
  var matches = 0;
  var i = 0;
  while i < n {
    let x: Int = a[i];
    let y: Int = b[i];
    if x == y {
      matches = matches + 1;
    }
    i = i + 1;
  }
  return (matches * 1000) / n;
}
