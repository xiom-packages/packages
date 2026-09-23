// XIOM -- xiom.sentiment: lexicon-based sentiment scoring with negation handling
// Port task: replace the xiom.sentiment placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A small fixed English lexicon (positive / negative word lists) scores text
// as a signed sum: +1 per positive word, -1 per negative word. A negator word
// (not, no, never, ...) in the three words preceding a polarity word flips
// that word's contribution exactly once: multiple negators do not stack. The
// word scan is byte-wise over the UTF-8 representation of Str; a word is a
// maximal run of [A-Za-z0-9] bytes folded to lowercase, and every other byte
// -- punctuation, whitespace, and each byte of a multi-byte UTF-8 sequence --
// is a separator. Every entry point is infallible (Vec/Int/Str/tuple returns,
// no Result channel). All comparisons of Str values read from Vec elements go
// through xiom.string.compare.str_compare (BUG 17: `==` lowers to a pointer
// compare). See SPEC.md for the exact lexicons, scoring algorithm and test
// plan.

module xiom.sentiment

use xiom.string;
use xiom.string.compare;

// --- built-in lexicon -------------------------------------------------------

/// The built-in positive lexicon: 38 lowercase English words, sorted ascending
/// by byte-wise comparison (str_compare order), with no duplicates.
/// Returns: a fresh Vec[Str] holding the positive words in sorted order.
/// Error case: none.
/// Complexity: O(1) (constant-size vector construction).
pub fn sentiment_positive_words() -> Vec[Str] {
  var out = Vec[Str].new();
  out.push("able");
  out.push("awesome");
  out.push("best");
  out.push("brave");
  out.push("bright");
  out.push("calm");
  out.push("cheerful");
  out.push("clever");
  out.push("confident");
  out.push("delighted");
  out.push("eager");
  out.push("easy");
  out.push("excellent");
  out.push("fantastic");
  out.push("friendly");
  out.push("generous");
  out.push("glad");
  out.push("good");
  out.push("great");
  out.push("happy");
  out.push("honest");
  out.push("incredible");
  out.push("joyful");
  out.push("kind");
  out.push("love");
  out.push("lovely");
  out.push("lucky");
  out.push("nice");
  out.push("perfect");
  out.push("pleasant");
  out.push("polite");
  out.push("proud");
  out.push("smart");
  out.push("strong");
  out.push("successful");
  out.push("superb");
  out.push("terrific");
  out.push("wonderful");
  return out;
}

/// The built-in negative lexicon: 54 lowercase English words, sorted ascending
/// by byte-wise comparison (str_compare order), with no duplicates.
/// Returns: a fresh Vec[Str] holding the negative words in sorted order.
/// Error case: none.
/// Complexity: O(1) (constant-size vector construction).
pub fn sentiment_negative_words() -> Vec[Str] {
  var out = Vec[Str].new();
  out.push("afraid");
  out.push("angry");
  out.push("awful");
  out.push("bad");
  out.push("boring");
  out.push("broken");
  out.push("corrupt");
  out.push("cruel");
  out.push("damaged");
  out.push("dangerous");
  out.push("dead");
  out.push("defect");
  out.push("difficult");
  out.push("dirty");
  out.push("disappointing");
  out.push("disaster");
  out.push("evil");
  out.push("failure");
  out.push("fake");
  out.push("fear");
  out.push("filthy");
  out.push("foolish");
  out.push("greedy");
  out.push("grief");
  out.push("hate");
  out.push("horrible");
  out.push("hurt");
  out.push("jealous");
  out.push("liar");
  out.push("lonely");
  out.push("loss");
  out.push("lost");
  out.push("mad");
  out.push("messy");
  out.push("miserable");
  out.push("nasty");
  out.push("negative");
  out.push("painful");
  out.push("poor");
  out.push("problem");
  out.push("rage");
  out.push("reject");
  out.push("rotten");
  out.push("rude");
  out.push("sad");
  out.push("sick");
  out.push("stupid");
  out.push("terrible");
  out.push("ugly");
  out.push("useless");
  out.push("violent");
  out.push("weak");
  out.push("worst");
  out.push("wrong");
  return out;
}

/// The built-in negator lexicon: 8 lowercase English negators, sorted
/// ascending by byte-wise comparison (str_compare order), with no duplicates.
/// Returns: a fresh Vec[Str] holding the negators in sorted order.
/// Error case: none.
/// Complexity: O(1) (constant-size vector construction).
pub fn sentiment_negators() -> Vec[Str] {
  var out = Vec[Str].new();
  out.push("barely");
  out.push("hardly");
  out.push("neither");
  out.push("never");
  out.push("no");
  out.push("nor");
  out.push("not");
  out.push("without");
  return out;
}

// --- internal helpers -------------------------------------------------------

// ASCII word-alphabet byte: [A-Za-z0-9]. Every other byte -- punctuation,
// whitespace, and each byte of a multi-byte UTF-8 sequence -- separates words.
fn _is_word_byte(b: UInt8) -> Bool {
  if b >= 48u8 && b <= 57u8 { return true; }   // 0-9
  if b >= 65u8 && b <= 90u8 { return true; }   // A-Z
  if b >= 97u8 && b <= 122u8 { return true; }  // a-z
  return false;
}

// Linear membership test over a lexicon. Every Str comparison goes through
// str_compare (never `==`, BUG 17).
fn _contains_word(lex: &Vec[Str], word: Str) -> Bool {
  var i = 0;
  while i < lex.len() {
    if str_compare(lex[i], word) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when at least one negator sits in the three words preceding words[i]
// (indices max(0, i - 3) .. i - 1). Returns on the first hit, so any number
// of negators in the window flips the polarity word exactly once.
fn _negated_before(words: &Vec[Str], i: Int, negators: &Vec[Str]) -> Bool {
  var j = i - 3;
  if j < 0 {
    j = 0;
  }
  while j < i {
    if _contains_word(negators, words[j]) {
      return true;
    }
    j = j + 1;
  }
  return false;
}

// Shared scoring pass: one scan over the lowercase words. Returns
// (score, positive_hits, negative_hits, negations_applied).
fn _score_parts(text: Str) -> (Int, Int, Int, Int) {
  let pos = sentiment_positive_words();
  let neg = sentiment_negative_words();
  let negators = sentiment_negators();
  let words = sentiment_words(text);
  var score = 0;
  var pos_hits = 0;
  var neg_hits = 0;
  var negations = 0;
  var i = 0;
  while i < words.len() {
    let w: Str = words[i];
    if _contains_word(&pos, w) {
      pos_hits = pos_hits + 1;
      if _negated_before(&words, i, &negators) {
        score = score - 1;
        negations = negations + 1;
      } else {
        score = score + 1;
      }
    } elif _contains_word(&neg, w) {
      neg_hits = neg_hits + 1;
      if _negated_before(&words, i, &negators) {
        score = score + 1;
        negations = negations + 1;
      } else {
        score = score - 1;
      }
    }
    i = i + 1;
  }
  return (score, pos_hits, neg_hits, negations);
}

// --- public API -------------------------------------------------------------

/// Scan text into lowercase words.
/// Params: text - the text to scan.
/// Returns: one Str per word, in order. A word is a maximal run of ASCII
/// letters and digits ([A-Za-z0-9]); every other byte -- punctuation,
/// whitespace, apostrophe, underscore, and each byte of a multi-byte UTF-8
/// sequence -- is a separator, so non-ASCII text yields ASCII-only tokens.
/// Each token is folded to lowercase (ASCII). Empty or separator-only text
/// yields [].
/// Error case: none.
/// Complexity: O(n).
pub fn sentiment_words(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  var i = 0;
  while i < len {
    let b: UInt8 = byte_at(text, i);
    if _is_word_byte(b) {
      let start = i;
      var j = i;
      var scanning = true;
      while scanning && j < len {
        let c: UInt8 = byte_at(text, j);
        if _is_word_byte(c) {
          j = j + 1;
        } else {
          scanning = false;
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

/// Score the sentiment of text.
/// Params: text - the text to score.
/// Returns: the signed sum: +1 per positive lexicon word, -1 per negative
/// lexicon word. Each polarity word whose three-word lookback window (the
/// three words immediately before it) contains at least one negator is
/// flipped exactly once, regardless of how many negators the window holds
/// (multiple negators do not stack). Neutral text scores 0.
/// Error case: none.
/// Complexity: O(text.len() + words * (|pos| + |neg| + |negators|)).
pub fn sentiment_score(text: Str) -> Int {
  let (score, pos_hits, neg_hits, negations) = _score_parts(text);
  return score;
}

/// Map a sentiment score to its label.
/// Params: score - the signed score from sentiment_score.
/// Returns: "negative" when score < 0, "neutral" when score == 0, and
/// "positive" when score > 0.
/// Error case: none.
/// Complexity: O(1).
pub fn sentiment_label(score: Int) -> Str {
  if score < 0 {
    return "negative";
  }
  if score > 0 {
    return "positive";
  }
  return "neutral";
}

/// Score text and map the score to its label.
/// Params: text - the text to score.
/// Returns: sentiment_label(sentiment_score(text)).
/// Error case: none.
/// Complexity: O(text.len() + words * (|pos| + |neg| + |negators|)).
pub fn sentiment_label_text(text: Str) -> Str {
  return sentiment_label(sentiment_score(text));
}

/// Count the lexicon hits and applied negations of text.
/// Params: text - the text to score.
/// Returns: the triple (positive_hits, negative_hits, negations_applied):
/// positive_hits is the number of positive lexicon words found;
/// negative_hits is the number of negative lexicon words found;
/// negations_applied is the number of polarity words whose contribution was
/// flipped by a negator. Hits are counted before flipping, so
/// sentiment_score is the signed sum over the two hit counts after applying
/// the flips.
/// Error case: none.
/// Complexity: O(text.len() + words * (|pos| + |neg| + |negators|)).
pub fn sentiment_counts(text: Str) -> (Int, Int, Int) {
  let (score, pos_hits, neg_hits, negations) = _score_parts(text);
  return (pos_hits, neg_hits, negations);
}
