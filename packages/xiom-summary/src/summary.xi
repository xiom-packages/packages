// XIOM -- xiom.summary: extractive text summarization with frequency scoring
// Port task: replace the xiom.summary placeholder with a real, tested,
// pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The pipeline is byte-wise over the UTF-8 representation of Str and every
// entry point is infallible (Vec/Str/Int-returning, no Result channel):
// sentences are trimmed slices of the input, words are lowercased ASCII
// [a-z0-9] runs, and extraction ranks sentences by the summed frequency of
// their non-stopword words. See SPEC.md for the full semantics and test plan.

module xiom.summary

use xiom.string;
use xiom.string.compare;

// --- byte constants ---------------------------------------------------------

const _ST_TAB: UInt8 = 9u8;
const _ST_LF: UInt8 = 10u8;
const _ST_CR: UInt8 = 13u8;
const _ST_SPACE: UInt8 = 32u8;
const _ST_BANG: UInt8 = 33u8;
const _ST_DOT: UInt8 = 46u8;
const _ST_QUESTION: UInt8 = 63u8;

// --- byte-level helpers -----------------------------------------------------

// Masked byte value: `byte_at ... as Int` can sign-extend (BUG 22), so every
// scan masks with 0xFF before any range comparison.
fn _byte_value(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// ASCII letter or digit value: [0-9A-Za-z].
fn _is_alnum_value(v: Int) -> Bool {
  if v >= 48 && v <= 57 { return true; }   // 0-9
  if v >= 65 && v <= 90 { return true; }   // A-Z
  if v >= 97 && v <= 122 { return true; }  // a-z
  return false;
}

// ASCII whitespace byte: space, tab, LF or CR (the xiom.char set).
fn _is_space_byte(b: UInt8) -> Bool {
  return b == _ST_SPACE || b == _ST_TAB || b == _ST_LF || b == _ST_CR;
}

// Sentence terminator byte: . ! or ?.
fn _is_terminator_byte(b: UInt8) -> Bool {
  return b == _ST_DOT || b == _ST_BANG || b == _ST_QUESTION;
}

// Own ASCII fold: A-Z become a-z, every other byte is copied verbatim.
fn _ascii_lower(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let v = _byte_value(s, i);
    if v >= 65 && v <= 90 {
      out.push((v + 32) as UInt8);
    } else {
      out.push(v as UInt8);
    }
    i = i + 1;
  }
  return Str::from_utf8(out);
}

// True when hay contains needle. Comparisons go through str_compare: `==` on
// Str values read from a Vec[Str] can lower to a pointer compare (BUG 17).
fn _contains_str(hay: &Vec[Str], needle: Str) -> Bool {
  var i = 0;
  while i < hay.len() {
    if compare.str_compare(hay[i], needle) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when hay contains needle. Vec[Int] element reads are typed `let`.
fn _contains_int(hay: &Vec[Int], needle: Int) -> Bool {
  var i = 0;
  while i < hay.len() {
    let v: Int = hay[i];
    if v == needle {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --- public API -------------------------------------------------------------

/// Split text into sentences at . ! ? followed by whitespace or end of text.
/// Params: text - the text to scan.
/// Returns: one Str per sentence; each sentence is the run up to and
/// including its terminator, outer ASCII whitespace trimmed, interior
/// punctuation and whitespace preserved verbatim. A terminator not followed
/// by whitespace or end of text does not split ("a.b c" stays whole). Pieces
/// that are empty after trimming (leading whitespace, inter-sentence runs,
/// trailing whitespace) are dropped, so empty or whitespace-only text yields
/// [].
/// Error case: none.
/// Complexity: O(n).
pub fn summary_sentences(text: Str) -> Vec[Str] {
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

/// Tokenize text into lowercased ASCII alphanumeric words.
/// Params: text - the text to scan.
/// Returns: one Str per maximal run of [A-Za-z0-9]; A-Z are folded to a-z by
/// this module's own fold. Every other byte -- punctuation, whitespace, and
/// each byte of a multi-byte UTF-8 sequence -- is a separator, so UTF-8 text
/// yields ASCII-only tokens ("café" -> ["caf"], "中文" -> []). Empty or
/// separator-only text yields [].
/// Error case: none.
/// Complexity: O(n).
pub fn summary_words(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  var i = 0;
  while i < len {
    let v = _byte_value(text, i);
    if _is_alnum_value(v) {
      let start = i;
      var j = i;
      while j < len {
        let vj = _byte_value(text, j);
        if _is_alnum_value(vj) {
          j = j + 1;
        } else {
          break;
        }
      }
      out.push(_ascii_lower(string.str_slice(text, start, j)));
      i = j;
    } else {
      i = i + 1;
    }
  }
  return out;
}

/// The built-in English stopword list.
/// Returns: 30 lowercase common English stopwords in strictly ascending
/// str_compare order: a, an, and, are, as, at, be, but, by, for, from, had,
/// has, have, he, in, is, it, its, not, of, on, or, that, the, this, to, was,
/// were, with. The list is a fresh Vec on every call, so callers may mutate
/// it freely.
/// Error case: none.
/// Complexity: O(1) apart from the fixed 30 pushes.
pub fn summary_stopwords() -> Vec[Str] {
  var out = Vec[Str].new();
  out.push("a");
  out.push("an");
  out.push("and");
  out.push("are");
  out.push("as");
  out.push("at");
  out.push("be");
  out.push("but");
  out.push("by");
  out.push("for");
  out.push("from");
  out.push("had");
  out.push("has");
  out.push("have");
  out.push("he");
  out.push("in");
  out.push("is");
  out.push("it");
  out.push("its");
  out.push("not");
  out.push("of");
  out.push("on");
  out.push("or");
  out.push("that");
  out.push("the");
  out.push("this");
  out.push("to");
  out.push("was");
  out.push("were");
  out.push("with");
  return out;
}

/// Case-insensitive membership test against a stopword list.
/// Params: w - the word to test (any casing); stop - the stopword list.
/// Returns: true when the ASCII-lowercased form of w equals an element of
/// stop (compared with str_compare, never `==`).
/// Error case: none.
/// Complexity: O(|stop| * |w|).
pub fn summary_is_stopword(w: Str, stop: &Vec[Str]) -> Bool {
  let lowered = _ascii_lower(w);
  var i = 0;
  while i < stop.len() {
    if compare.str_compare(lowered, stop[i]) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// The distinct non-stopword words of a token sequence, in first-seen order.
/// Params: words - the lowercase word tokens; stop - the stopword list.
/// Returns: a fresh Vec[Str] holding each non-stopword element of words once,
/// ordered by first occurrence in words. Empty input (or all-stopword input)
/// yields [].
/// Error case: none.
/// Complexity: O(n * u) with u the number of unique words.
pub fn summary_unique_words(words: &Vec[Str], stop: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < words.len() {
    let w: Str = words[i];
    if !summary_is_stopword(w, stop) {
      if !_contains_str(&out, w) {
        out.push(w);
      }
    }
    i = i + 1;
  }
  return out;
}

/// Frequencies of the unique non-stopword words, parallel to
/// summary_unique_words.
/// Params: words - the lowercase word tokens; stop - the stopword list.
/// Returns: a Vec[Int] with one entry per element of
/// summary_unique_words(words, stop): entry i is the number of occurrences of
/// unique word i in words (stopwords are never counted). Empty input yields
/// [].
/// Error case: none.
/// Complexity: O(n * u) with u the number of unique words.
pub fn summary_word_frequencies(words: &Vec[Str], stop: &Vec[Str]) -> Vec[Int] {
  let unique = summary_unique_words(words, stop);
  var out = Vec[Int].new();
  var u = 0;
  while u < unique.len() {
    var count = 0;
    var i = 0;
    while i < words.len() {
      if compare.str_compare(unique[u], words[i]) == 0 {
        count = count + 1;
      }
      i = i + 1;
    }
    out.push(count);
    u = u + 1;
  }
  return out;
}

/// Frequency score of one sentence: the sum of the frequencies of its
/// non-stopword words.
/// Params: sentence - the sentence to score; unique/freqs - the parallel
/// unique-word and frequency vectors from summary_unique_words and
/// summary_word_frequencies; stop - the stopword list.
/// Returns: the total, 0 when the sentence has no non-stopword word, and 0
/// for a word missing from unique. When freqs is shorter than unique, extra
/// unique words contribute 0.
/// Error case: none.
/// Complexity: O(|sentence| * u) with u the number of unique words.
pub fn summary_sentence_score(sentence: Str, unique: &Vec[Str], freqs: &Vec[Int], stop: &Vec[Str]) -> Int {
  let words = summary_words(sentence);
  var total = 0;
  var i = 0;
  while i < words.len() {
    let w: Str = words[i];
    if !summary_is_stopword(w, stop) {
      var u = 0;
      while u < unique.len() {
        if compare.str_compare(unique[u], w) == 0 {
          if u < freqs.len() {
            let f: Int = freqs[u];
            total = total + f;
          }
          break;
        }
        u = u + 1;
      }
    }
    i = i + 1;
  }
  return total;
}

/// Extractive summary: the top-scoring sentences, in original order.
/// Params: text - the text to summarize; max_sentences - the maximum number
/// of sentences to return.
/// Returns: up to max_sentences sentences selected by the highest
/// summary_sentence_score, then emitted in their original document order.
/// Selection ties keep the earlier sentence (a strictly greater score is
/// required to displace the current best). Returns [] for empty or
/// whitespace-only text and for max_sentences <= 0; when max_sentences
/// exceeds the sentence count, every sentence is returned. Zero-score
/// sentences are still selectable: when fewer than max_sentences positive
/// scores exist, the earliest remaining sentences fill the gap.
/// Error case: none.
/// Complexity: O(n * u + s^2) with s the sentence count.
pub fn summary_extract(text: Str, max_sentences: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  if max_sentences <= 0 {
    return out;
  }
  let sentences = summary_sentences(text);
  if sentences.len() == 0 {
    return out;
  }
  let words = summary_words(text);
  let stop = summary_stopwords();
  let unique = summary_unique_words(&words, &stop);
  let freqs = summary_word_frequencies(&words, &stop);
  var scores = Vec[Int].new();
  var i = 0;
  while i < sentences.len() {
    scores.push(summary_sentence_score(sentences[i], &unique, &freqs, &stop));
    i = i + 1;
  }
  var picked_idx = Vec[Int].new();
  var picked = 0;
  while picked < max_sentences && picked < sentences.len() {
    var best = -1;
    var j = 0;
    while j < sentences.len() {
      if !_contains_int(&picked_idx, j) {
        if best < 0 {
          best = j;
        } else {
          let best_score: Int = scores[best];
          let j_score: Int = scores[j];
          if j_score > best_score {
            best = j;
          }
        }
      }
      j = j + 1;
    }
    if best < 0 {
      break;
    }
    picked_idx.push(best);
    picked = picked + 1;
  }
  var m = 0;
  while m < sentences.len() {
    if _contains_int(&picked_idx, m) {
      out.push(sentences[m]);
    }
    m = m + 1;
  }
  return out;
}

/// Extractive summary as one string: summary_extract joined with single
/// spaces.
/// Params: text - the text to summarize; max_sentences - the maximum number
/// of sentences.
/// Returns: the selected sentences in original order joined with one space
/// between consecutive sentences; "" when summary_extract returns [] or for a
/// single empty result.
/// Error case: none.
/// Complexity: O(sum of selected sentence lengths).
pub fn summary_extract_text(text: Str, max_sentences: Int) -> Str {
  let parts = summary_extract(text, max_sentences);
  var out = "";
  var i = 0;
  while i < parts.len() {
    if i > 0 {
      out = out + " ";
    }
    out = out + parts[i];
    i = i + 1;
  }
  return out;
}
