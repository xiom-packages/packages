// XIOM -- xiom.spell: dictionary-based spell checking (distance, suggestions, scan)
// Port task: replace the xiom.spell placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The caller supplies the dictionary as a Vec[Str]. Distances are measured
// over the UTF-8 bytes of Str (a non-ASCII character therefore counts as its
// encoded byte length). Every comparison of Str values read from Vec elements
// goes through xiom.string.compare.str_compare (BUG 17: `==` lowers to a
// pointer compare). The Levenshtein dynamic program lives in a single flat
// Vec[Int] (no Vec[Vec[Int]], no Vec[StructType], no self methods, no
// lambdas). See SPEC.md for the exact semantics and test plan.

module xiom.spell

use xiom.string;
use xiom.string.compare;

// --- internal helpers -------------------------------------------------------

// Apostrophe byte; joins two word bytes only when it sits between them.
const _APOSTROPHE: UInt8 = 39u8;

// ASCII word-alphabet byte: [A-Za-z0-9_]. Every other byte -- punctuation,
// whitespace, and each byte of a multi-byte UTF-8 sequence -- separates words.
fn _is_word_byte(b: UInt8) -> Bool {
  if b >= 48u8 && b <= 57u8 { return true; }   // 0-9
  if b >= 65u8 && b <= 90u8 { return true; }   // A-Z
  if b >= 97u8 && b <= 122u8 { return true; }  // a-z
  if b == 95u8 { return true; }                // _
  return false;
}

// Index one past the end of the word run starting at `start` (the caller
// guarantees byte_at(text, start) is a word byte). An apostrophe extends the
// run only when it sits between two word bytes; edge and doubled apostrophes
// end it. Single loop exit through `scanning`, no nested breaks.
fn _word_end(text: Str, start: Int) -> Int {
  let len = text.len();
  var j = start;
  var scanning = true;
  while scanning && j < len {
    let c: UInt8 = byte_at(text, j);
    if _is_word_byte(c) {
      j = j + 1;
    } else {
      var joins = false;
      if c == _APOSTROPHE {
        if j > start {
          if j + 1 < len {
            let next_byte: UInt8 = byte_at(text, j + 1);
            if _is_word_byte(next_byte) {
              joins = true;
            }
          }
        }
      }
      if joins {
        j = j + 1;
      } else {
        scanning = false;
      }
    }
  }
  return j;
}

// Flat (n+1) x (m+1) Levenshtein table over the bytes of `a` and `b`,
// row-major with width m+1: dp[i*(m+1)+j] is the unit-cost edit distance
// between a[0..i) and b[0..j). Unclamped and without early exit; the budgeted
// entry point builds its own clamped table.
fn _lev_table(a: Str, b: Str) -> Vec[Int] {
  let n = a.len();
  let m = b.len();
  let width = m + 1;
  let total = (n + 1) * width;
  var dp = Vec[Int].new();
  var k = 0;
  while k < total {
    dp.push(0);
    k = k + 1;
  }
  var i = 0;
  while i <= n {
    dp[i * width] = i;
    i = i + 1;
  }
  var j = 0;
  while j <= m {
    dp[j] = j;
    j = j + 1;
  }
  i = 1;
  while i <= n {
    j = 1;
    while j <= m {
      let ca: UInt8 = byte_at(a, i - 1);
      let cb: UInt8 = byte_at(b, j - 1);
      var cost = 1;
      if ca == cb {
        cost = 0;
      }
      let del: Int = dp[(i - 1) * width + j] + 1;
      let ins: Int = dp[i * width + (j - 1)] + 1;
      let sub: Int = dp[(i - 1) * width + (j - 1)] + cost;
      var best = del;
      if ins < best { best = ins; }
      if sub < best { best = sub; }
      dp[i * width + j] = best;
      j = j + 1;
    }
    i = i + 1;
  }
  return dp;
}

// --- public API -------------------------------------------------------------

/// Byte-wise Levenshtein distance between `a` and `b`.
/// Unit costs: insert, delete and substitute each cost 1; a non-ASCII
/// character counts as its UTF-8 byte length (e.g. "café" vs "cafe" is 2).
/// Params: a, b - the two strings; either may be empty.
/// Returns: the minimum number of unit edits turning a into b, always >= 0.
/// Error case: none.
/// Complexity: O(n*m) time and memory (flat Vec[Int] table).
pub fn spell_distance(a: Str, b: Str) -> Int {
  let n = a.len();
  let m = b.len();
  if n == 0 {
    return m;
  }
  if m == 0 {
    return n;
  }
  let dp = _lev_table(a, b);
  let d: Int = dp[n * (m + 1) + m];
  return d;
}

/// Budgeted byte-wise Levenshtein distance between `a` and `b`.
/// Returns the exact distance when it is at most `max_dist`, otherwise
/// `max_dist + 1`. `max_dist < 0` clamps to 0 (an exact match still returns
/// 0, anything else returns 1).
/// Implementation: the full O(n*m) DP with every cell clamped to
/// max_dist + 1 and a per-row early exit once no cell of the row is within
/// budget; this is NOT the banded (Ukkonen) O(k * min(n, m)) optimisation,
/// so worst-case cost matches spell_distance. The length-difference shortcut
/// returns immediately when |n - m| > max_dist.
/// Params: a, b - the two strings; max_dist - the inclusive budget.
/// Returns: exact distance when <= max_dist, else max_dist + 1.
/// Error case: none.
/// Complexity: O(n*m) time and memory worst case; O(1) when the lengths
/// differ by more than the budget, O(n) when a whole row exceeds it.
pub fn spell_distance_bounded(a: Str, b: Str, max_dist: Int) -> Int {
  var limit = max_dist;
  if limit < 0 {
    limit = 0;
  }
  let n = a.len();
  let m = b.len();
  if n == 0 {
    if m <= limit {
      return m;
    }
    return limit + 1;
  }
  if m == 0 {
    if n <= limit {
      return n;
    }
    return limit + 1;
  }
  var len_diff = n - m;
  if len_diff < 0 {
    len_diff = 0 - len_diff;
  }
  if len_diff > limit {
    return limit + 1;
  }
  let width = m + 1;
  let total = (n + 1) * width;
  var dp = Vec[Int].new();
  var k = 0;
  while k < total {
    dp.push(0);
    k = k + 1;
  }
  var i = 0;
  while i <= n {
    var bound = i;
    if bound > limit {
      bound = limit + 1;
    }
    dp[i * width] = bound;
    i = i + 1;
  }
  var j = 0;
  while j <= m {
    var bound = j;
    if bound > limit {
      bound = limit + 1;
    }
    dp[j] = bound;
    j = j + 1;
  }
  i = 1;
  while i <= n {
    var row_min = i;
    if row_min > limit {
      row_min = limit + 1;
    }
    j = 1;
    while j <= m {
      let ca: UInt8 = byte_at(a, i - 1);
      let cb: UInt8 = byte_at(b, j - 1);
      var cost = 1;
      if ca == cb {
        cost = 0;
      }
      let del: Int = dp[(i - 1) * width + j] + 1;
      let ins: Int = dp[i * width + (j - 1)] + 1;
      let sub: Int = dp[(i - 1) * width + (j - 1)] + cost;
      var best = del;
      if ins < best { best = ins; }
      if sub < best { best = sub; }
      if best > limit {
        best = limit + 1;
      }
      dp[i * width + j] = best;
      if best < row_min {
        row_min = best;
      }
      j = j + 1;
    }
    if row_min > limit {
      return limit + 1;
    }
    i = i + 1;
  }
  let d: Int = dp[n * width + m];
  return d;
}

/// Exact membership of `word` in `dict`.
/// Comparison goes through str_compare, so it is byte-exact and
/// case-sensitive; duplicate dictionary entries are irrelevant.
/// Params: dict - the dictionary slice; word - the word to look up.
/// Returns: true when some dictionary entry compares equal to `word`.
/// Error case: none.
/// Complexity: O(dict.len()) str_compare calls.
pub fn spell_contains(dict: &Vec[Str], word: Str) -> Bool {
  var i = 0;
  while i < dict.len() {
    if str_compare(dict[i], word) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// True when `word` is present in `dict` (alias of spell_contains).
/// Params: dict - the dictionary slice; word - the word to check.
/// Returns: true when the word is exactly in the dictionary.
/// Error case: none.
/// Complexity: O(dict.len()) str_compare calls.
pub fn spell_is_correct(dict: &Vec[Str], word: Str) -> Bool {
  return spell_contains(dict, word);
}

/// Dictionary words within `max_dist` edits of `word`, best first.
/// Candidates are ordered by (distance ascending, dictionary order), so the
/// result is stable and deterministic. `max_results` caps the output
/// (`max_results <= 0` yields []); `max_dist < 0` yields [].
/// Params: dict - the dictionary slice; word - the query word; max_dist -
/// inclusive distance budget; max_results - maximum number of suggestions.
/// Returns: up to max_results dictionary entries, best first.
/// Error case: none.
/// Complexity: O(dict.len() * |word| * avg(dict word length)) to score, plus
/// k selection passes over the dictionary where k is the result length.
pub fn spell_suggest(dict: &Vec[Str], word: Str, max_dist: Int, max_results: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  if max_results <= 0 {
    return out;
  }
  if max_dist < 0 {
    return out;
  }
  let n = dict.len();
  if n == 0 {
    return out;
  }
  // Index-wide distance cache: exact distance when within budget, else -1.
  var dist = Vec[Int].new();
  var i = 0;
  while i < n {
    let d = spell_distance_bounded(dict[i], word, max_dist);
    if d <= max_dist {
      dist.push(d);
    } else {
      dist.push(-1);
    }
    i = i + 1;
  }
  var used = Vec[Int].new();
  i = 0;
  while i < n {
    used.push(0);
    i = i + 1;
  }
  var picked = 0;
  while picked < max_results {
    // First selection pass: smallest distance among unused candidates.
    var best = -1;
    var j = 0;
    while j < n {
      let dj: Int = dist[j];
      let uj: Int = used[j];
      if uj == 0 && dj >= 0 {
        if best < 0 || dj < best {
          best = dj;
        }
      }
      j = j + 1;
    }
    if best < 0 {
      break;
    }
    // Second pass: emit every unused candidate at that distance in
    // dictionary order, so ties stay stable.
    j = 0;
    while j < n {
      if picked >= max_results {
        break;
      }
      let dj: Int = dist[j];
      let uj: Int = used[j];
      if uj == 0 && dj == best {
        let candidate: Str = dict[j];
        out.push(candidate);
        used[j] = 1;
        picked = picked + 1;
      }
      j = j + 1;
    }
  }
  return out;
}

/// Words of `text` that are not in `dict`, first-seen order, deduplicated.
/// Tokenization: a word is a maximal run of [A-Za-z0-9_] bytes; an
/// apostrophe (') is kept only when it sits between two word bytes
/// ("don't"). Every other byte -- punctuation, whitespace, and each byte of
/// a multi-byte UTF-8 sequence -- is a separator. Membership is exact and
/// case-sensitive; a word is reported at most once and the dedup comparison
/// goes through str_compare.
/// Params: dict - the dictionary slice; text - the text to scan.
/// Returns: unknown words in first-seen order, each at most once.
/// Error case: none.
/// Complexity: O(text.len() + words * dict.len()) str_compare calls.
pub fn spell_unknown_words(dict: &Vec[Str], text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  var i = 0;
  while i < len {
    let b: UInt8 = byte_at(text, i);
    if _is_word_byte(b) {
      let end = _word_end(text, i);
      let word = str_slice(text, i, end);
      let known = spell_contains(dict, word);
      if !known {
        let seen = spell_contains(&out, word);
        if !seen {
          out.push(word);
        }
      }
      i = end;
    } else {
      i = i + 1;
    }
  }
  return out;
}
