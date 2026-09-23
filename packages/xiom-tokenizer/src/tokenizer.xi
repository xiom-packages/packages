// XIOM -- xiom.tokenizer: text tokenization (words, sentences, lines, n-grams)
// Port task: replace the xiom.tokenizer placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The scanner is byte-wise over the UTF-8 representation of Str and every
// entry point is infallible (Vec-returning, no Result channel). Word tokens
// are maximal runs of [A-Za-z0-9_]; every other byte, including every
// non-ASCII byte, is a separator. Sentence and line tokens are trimmed slices
// of the input, so UTF-8 passes through byte-exact. See SPEC.md for the full
// semantics and test plan.

module xiom.tokenizer

use xiom.string;

const _TK_TAB: UInt8 = 9u8;
const _TK_LF: UInt8 = 10u8;
const _TK_CR: UInt8 = 13u8;
const _TK_SPACE: UInt8 = 32u8;
const _TK_BANG: UInt8 = 33u8;
const _TK_APOSTROPHE: UInt8 = 39u8;
const _TK_DOT: UInt8 = 46u8;
const _TK_QUESTION: UInt8 = 63u8;
const _TK_UNDERSCORE: UInt8 = 95u8;

// ASCII word alphabet byte: [A-Za-z0-9_]. Every other byte -- punctuation,
// whitespace, and each byte of a multi-byte UTF-8 sequence -- separates words.
fn _is_word_byte(b: UInt8) -> Bool {
  if b >= 48u8 && b <= 57u8 { return true; }   // 0-9
  if b >= 65u8 && b <= 90u8 { return true; }   // A-Z
  if b >= 97u8 && b <= 122u8 { return true; }  // a-z
  if b == _TK_UNDERSCORE { return true; }      // _
  return false;
}

// ASCII whitespace byte: space, tab, LF or CR (the xiom.char set).
fn _is_space_byte(b: UInt8) -> Bool {
  return b == _TK_SPACE || b == _TK_TAB || b == _TK_LF || b == _TK_CR;
}

// Sentence terminator byte: . ! or ?.
fn _is_terminator_byte(b: UInt8) -> Bool {
  return b == _TK_DOT || b == _TK_BANG || b == _TK_QUESTION;
}

// Drop one trailing CR byte (the CRLF -> LF normalization for line tokens).
fn _strip_trailing_cr(s: Str) -> Str {
  let n = s.len();
  if n == 0 {
    return s;
  }
  if string.byte_at(s, n - 1) == _TK_CR {
    return string.str_slice(s, 0, n - 1);
  }
  return s;
}

/// Tokenize text into maximal runs of ASCII word bytes [A-Za-z0-9_].
/// Params: text - the text to scan.
/// Returns: one Str per word, in order. An apostrophe (') is kept only when
/// it sits between two word bytes ("don't" -> "don't"); apostrophes at token
/// edges and doubled apostrophes are separators. Every other byte --
/// punctuation, whitespace, all non-ASCII bytes -- is a separator, so UTF-8
/// text yields ASCII-only tokens. Empty or separator-only text yields [].
/// Error case: none.
/// Complexity: O(n).
pub fn tokenize_words(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  var i = 0;
  while i < len {
    let b = string.byte_at(text, i);
    if _is_word_byte(b) {
      let start = i;
      var j = i;
      while j < len {
        let c = string.byte_at(text, j);
        if _is_word_byte(c) {
          j = j + 1;
        } elif c == _TK_APOSTROPHE && j > start && j + 1 < len && _is_word_byte(string.byte_at(text, j + 1)) {
          j = j + 1;
        } else {
          break;
        }
      }
      out.push(string.str_slice(text, start, j));
      i = j;
    } else {
      i = i + 1;
    }
  }
  return out;
}

/// Split text into sentences at . ! ? followed by whitespace or end of text.
/// Params: text - the text to scan.
/// Returns: one Str per sentence; each sentence is the run up to and
/// including its terminator, outer ASCII whitespace trimmed, interior
/// punctuation and interior whitespace preserved verbatim. Text with no
/// terminator is one sentence. Pieces that are empty after trimming (leading
/// whitespace, inter-sentence runs, trailing whitespace) are dropped, so
/// empty or whitespace-only text yields []. A terminator not followed by
/// whitespace or end does not split ("a.b c" stays whole).
/// Error case: none.
/// Complexity: O(n).
pub fn tokenize_sentences(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  var start = 0;
  var i = 0;
  while i < len {
    let b = string.byte_at(text, i);
    var cut = false;
    if _is_terminator_byte(b) {
      if i + 1 >= len || _is_space_byte(string.byte_at(text, i + 1)) {
        cut = true;
      }
    }
    if cut {
      let piece = string.str_trim(string.str_slice(text, start, i + 1));
      if piece.len() > 0 {
        out.push(piece);
      }
      start = i + 1;
    }
    i = i + 1;
  }
  if start < len {
    let piece = string.str_trim(string.str_slice(text, start, len));
    if piece.len() > 0 {
      out.push(piece);
    }
  }
  return out;
}

/// Split text into lines on LF, normalizing CRLF line endings.
/// Params: text - the text to scan.
/// Returns: one Str per line. A CR immediately before the LF is stripped (a
/// lone CR inside a line is kept). A single trailing LF ends the last line
/// and adds no empty line, so "a\n" -> ["a"] and "\n" -> [""]; empty text
/// yields []. No trimming is performed.
/// Error case: none.
/// Complexity: O(n).
pub fn tokenize_lines(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  if len == 0 {
    return out;
  }
  var start = 0;
  var i = 0;
  while i < len {
    if string.byte_at(text, i) == _TK_LF {
      out.push(_strip_trailing_cr(string.str_slice(text, start, i)));
      start = i + 1;
    }
    i = i + 1;
  }
  if start < len {
    out.push(_strip_trailing_cr(string.str_slice(text, start, len)));
  }
  return out;
}

/// Build word n-grams by joining each sliding window with single spaces.
/// Params: words - the token sequence; n - the window size.
/// Returns: len(words) - n + 1 n-grams in order when n >= 1 and there are at
/// least n words; [] when n < 1 or words.len() < n. Windows are contiguous
/// and non-overlapping is not required: ["a","b","c"] with n = 2 yields
/// ["a b", "b c"].
/// Error case: none.
/// Complexity: O(n * |words|) over the joined length.
pub fn tokenize_ngrams(words: &Vec[Str], n: Int) -> Vec[Str] {
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
      joined = joined + words[i + j];
      j = j + 1;
    }
    out.push(joined);
    i = i + 1;
  }
  return out;
}

/// Count words using the tokenize_words tokenization.
/// Params: text - the text to scan.
/// Returns: the number of word tokens in text; 0 for empty or
/// separator-only text.
/// Error case: none.
/// Complexity: O(n) time, O(words) temporary memory.
pub fn tokenize_count_words(text: Str) -> Int {
  return tokenize_words(text).len();
}
