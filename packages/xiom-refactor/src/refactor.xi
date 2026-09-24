// XIOM -- xiom.refactor: text-level identifier renaming with word boundaries
// Port task: replace the xiom.refactor placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Byte-wise, text-level renaming over UTF-8 Str input. A whole-word
// occurrence of `old_name` is a byte-exact match whose neighboring bytes are
// not word characters under the caller-supplied `word_chars` set (the
// default is [A-Za-z0-9_]). Every entry point is infallible: Str/Int/Vec
// returns, no Result channel, no panics on arbitrary bytes. Renaming never
// parses the input, so occurrences inside string literals, comments and
// non-code text are treated exactly like code. See SPEC.md for the full
// semantics and the test plan.
//
// Language notes (XIOM v0.61.3): free functions only; Str values read from
// Vec[Str] elements are compared with str_compare (BUG 17: `==` on such
// elements lowers to a pointer comparison); UInt8 bytes are widened to Int
// with an explicit `as Int` before comparing against the Int `byte` argument.

module xiom.refactor

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// The byte that splits a rename pair into old and new name.
const _RF_EQ: UInt8 = 61u8;

// The line-feed byte: the only line boundary for refactor_occurrence_lines.
const _RF_LF: UInt8 = 10u8;

/// The default word-character alphabet: A-Z, a-z, 0-9 and underscore.
/// Params: none.
/// Returns: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"
/// (63 bytes).
/// Error case: none.
/// Complexity: O(1).
pub fn refactor_word_chars_default() -> Str {
  return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_";
}

/// Membership test: is `byte` one of the bytes of `word_chars`?
/// Params: byte - a byte value widened to Int; word_chars - the set of word
/// bytes.
/// Returns: true when 0 <= byte <= 255 and byte occurs in word_chars. A byte
/// outside 0..255 returns false; an empty word_chars set contains nothing, so
/// every byte returns false (no byte is then a word character).
/// Error case: none.
/// Complexity: O(|word_chars|).
pub fn refactor_is_word_char(byte: Int, word_chars: Str) -> Bool {
  if byte < 0 || byte > 255 {
    return false;
  }
  var i = 0;
  while i < word_chars.len() {
    let w: Int = string.byte_at(word_chars, i) as Int;
    if w == byte {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when the byte at `at` is a word character under `word_chars`.
fn _is_word_byte_at(text: Str, at: Int, word_chars: Str) -> Bool {
  let b: Int = string.byte_at(text, at) as Int;
  return refactor_is_word_char(b, word_chars);
}

// True when old_name occurs byte-exactly at `at` in `text` and neither
// neighbor byte is a word character. An empty old_name never matches.
fn _match_at(text: Str, at: Int, old_name: Str, word_chars: Str) -> Bool {
  let m = old_name.len();
  if m == 0 {
    return false;
  }
  if at < 0 || at + m > text.len() {
    return false;
  }
  let piece = string.str_slice(text, at, at + m);
  if compare.str_compare(piece, old_name) != 0 {
    return false;
  }
  if at > 0 {
    if _is_word_byte_at(text, at - 1, word_chars) {
      return false;
    }
  }
  if at + m < text.len() {
    if _is_word_byte_at(text, at + m, word_chars) {
      return false;
    }
  }
  return true;
}

/// Count whole-word occurrences of `old_name` in `text`.
/// Params: text - the text to scan; old_name - the name to look for;
/// word_chars - the set of word bytes used for the boundary test.
/// Returns: the number of byte-exact occurrences whose preceding and
/// following bytes are not word characters. Scanning is left to right and
/// matches do not overlap: after a match the scan resumes past it. An empty
/// old_name returns 0; an empty word_chars makes every literal occurrence a
/// whole-word occurrence.
/// Error case: none.
/// Complexity: O(n * |old_name|).
pub fn refactor_count(text: Str, old_name: Str, word_chars: Str) -> Int {
  let m = old_name.len();
  if m == 0 {
    return 0;
  }
  let len = text.len();
  var count = 0;
  var i = 0;
  while i + m <= len {
    if _match_at(text, i, old_name, word_chars) {
      count = count + 1;
      i = i + m;
    } else {
      i = i + 1;
    }
  }
  return count;
}

/// Replace every whole-word occurrence of `old_name` with `new_name`.
/// Params: text - the text to rewrite; old_name - the name to replace;
/// new_name - the replacement; word_chars - the set of word bytes used for
/// the boundary test.
/// Returns: `text` with each whole-word occurrence replaced, scanning left to
/// right with non-overlapping matches (the same scan as refactor_count, so a
/// dry-run count equals the number of replacements). When old_name is empty or
/// absent, `text` is returned unchanged. Bytes outside the matches pass
/// through byte-exact, so UTF-8 is preserved.
/// Error case: none.
/// Complexity: O(n * |old_name|) plus output concatenation.
pub fn refactor_rename(text: Str, old_name: Str, new_name: Str, word_chars: Str) -> Str {
  let m = old_name.len();
  let len = text.len();
  if m == 0 || len == 0 {
    return text;
  }
  var out = "";
  var start = 0;
  var i = 0;
  while i + m <= len {
    if _match_at(text, i, old_name, word_chars) {
      out = out + string.str_slice(text, start, i);
      out = out + new_name;
      i = i + m;
      start = i;
    } else {
      i = i + 1;
    }
  }
  out = out + string.str_slice(text, start, len);
  return out;
}

// Byte offset of the first '=' in `pair`, or -1 when there is none.
fn _eq_index(pair: Str) -> Int {
  var i = 0;
  while i < pair.len() {
    if string.byte_at(pair, i) == _RF_EQ {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Report per-pair replacement counts without modifying the caller's text.
/// Params: text - the starting text; renames - a Vec of "old=new" pairs;
/// word_chars - the set of word bytes used for the boundary test.
/// Returns: one line per pair, in order. A well-formed pair yields
/// "old -> new: N replacement(s)", where N is the whole-word count of `old`
/// in the text as produced by the preceding pairs (pairs are applied to a
/// working copy in order, so N reflects earlier renames). A pair with no '='
/// yields exactly "old -> ?: invalid" and is skipped (never an error). The
/// split is at the first '='; the new name may therefore contain '='. An
/// empty old name (a pair starting with '=') never matches, so it reports
/// 0 replacement(s).
/// Error case: none.
/// Complexity: O(pairs * n * |old_name|).
pub fn refactor_rename_dry_run(text: Str, renames: &Vec[Str], word_chars: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  var work = text;
  var i = 0;
  while i < renames.len() {
    let pair: Str = renames[i];
    let at = _eq_index(pair);
    if at < 0 {
      out.push(pair + " -> ?: invalid");
    } else {
      let old_name = string.str_slice(pair, 0, at);
      let new_name = string.str_slice(pair, at + 1, pair.len());
      let n = refactor_count(work, old_name, word_chars);
      var line = old_name + " -> ";
      line = line + new_name;
      line = line + ": ";
      line = line + int_to_string(n);
      line = line + " replacement(s)";
      out.push(line);
      work = refactor_rename(work, old_name, new_name, word_chars);
    }
    i = i + 1;
  }
  return out;
}

/// Apply rename pairs to `text` in order and return the final text.
/// Params: text - the starting text; renames - a Vec of "old=new" pairs;
/// word_chars - the set of word bytes used for the boundary test.
/// Returns: the text after each well-formed pair has been applied with
/// refactor_rename, in order (so a later pair sees the earlier replacements:
/// "a=b" then "b=c" turns "a" into "c"). Pairs with no '=' are skipped;
/// malformed input never errors and never changes the text.
/// Error case: none.
/// Complexity: O(pairs * n * |old_name|).
pub fn refactor_rename_batch(text: Str, renames: &Vec[Str], word_chars: Str) -> Str {
  var work = text;
  var i = 0;
  while i < renames.len() {
    let pair: Str = renames[i];
    let at = _eq_index(pair);
    if at >= 0 {
      let old_name = string.str_slice(pair, 0, at);
      let new_name = string.str_slice(pair, at + 1, pair.len());
      work = refactor_rename(work, old_name, new_name, word_chars);
    }
    i = i + 1;
  }
  return work;
}

/// 1-based line numbers that contain at least one whole-word occurrence.
/// Params: text - the text to scan; name - the name to look for; word_chars -
/// the set of word bytes used for the boundary test.
/// Returns: the 1-based numbers of the LF-delimited lines of `text` that
/// contain at least one whole-word occurrence of `name`, in increasing order.
/// Line splitting follows the usual convention: LF terminates a line, a CR
/// before the LF is just a non-word byte (unless word_chars contains it), and
/// one trailing LF adds no empty line. Empty text or an empty name yields [].
/// Matching is per line, so a name containing an LF byte cannot span lines.
/// Error case: none.
/// Complexity: O(n * |name|).
pub fn refactor_occurrence_lines(text: Str, name: Str, word_chars: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  let len = text.len();
  if len == 0 || name.len() == 0 {
    return out;
  }
  var line_no = 1;
  var start = 0;
  var i = 0;
  while i <= len {
    var cut = false;
    if i == len {
      cut = true;
    } elif string.byte_at(text, i) == _RF_LF {
      cut = true;
    }
    if cut {
      let line = string.str_slice(text, start, i);
      if refactor_count(line, name, word_chars) > 0 {
        out.push(line_no);
      }
      line_no = line_no + 1;
      start = i + 1;
    }
    i = i + 1;
  }
  return out;
}
