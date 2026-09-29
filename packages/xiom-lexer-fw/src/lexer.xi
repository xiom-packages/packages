// XIOM -- xiom.lexer: a framework for building lexical analyzers
// Port task: replace the xiom.lexer-fw placeholder with a pure-XIOM module
// (no FFI, no IO, no Vec[Float64], no Vec[StructType]).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the reusable machinery of a hand-written scanner, not a language
// grammar. Five pieces:
//   * token kinds as Int constants (identifier, integer, float-literal,
//     string-literal, punctuation, keyword, comment, EOF) and a Token record;
//   * ScanState (source, pos, line, col) with peek/advance/expect helpers and
//     1-based line/column tracking across LF newlines;
//   * regex-free byte matchers (identifier, integer, float, string, line and
//     block comments) built on xiom.string.byte_at;
//   * KeywordTable: parallel Vec[Str] words + Vec[Int] kinds with an exact,
//     case-sensitive, first-match lookup via str_compare;
//   * lex_next (one token) and lex_scan (the whole stream as the parallel Vec
//     fields kinds/starts/ends/lines/cols), with exact first-error reporting.
//
// Design decisions (see SPEC.md for the full statement):
//   * Every byte read is widened with `(b as Int) & 0xFF` before any
//     comparison: v0.62.1 still miscompiles direct UInt8 comparisons at
//     >= 128 (byte-at-128 trap), one of the pinned compiler traps.
//   * Matching is ASCII-only; a non-ASCII byte outside a string or comment is
//     an "unexpected byte" error.
//   * Token text is the RAW source slice: escapes are recognized while
//     scanning but never decoded, so token_text is a pure str_slice and no
//     NUL byte is ever synthesized.
//   * Signs are caller-level: `-3` scans as punctuation "-" then integer 3.
//   * Comments are tokens (kind comment); lex_scan does not append an EOF
//     sentinel -- lex_next reports EOF as a zero-width token instead.
//   * Built-in patterns (comments, identifiers, numbers, strings) win over
//     the table; the table resolves identifiers into keyword/punct kinds and
//     matches any byte the built-ins do not claim.
//
// Language notes (XIOM v0.62.1): free functions only; Ok/Err literals live
// only in the leaf helpers at the bottom (constructing them inline
// miscompiles in some code shapes); Str values read from Vec[Str] elements
// are compared with str_compare (BUG 17); Vec[Int]/Vec[Str] element reads go
// through typed locals; no indexed Vec[fn] dispatch and no [T,U] callbacks;
// scanner bodies call only &mut-taking private helpers on the state, so no
// `&` call mixes with a `&mut` access on the same local (advisory E001).

module xiom.lexer

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
// Token kinds
// ---------------------------------------------------------------------------

/// No token / lookup miss (the zero value; never produced by lex_scan).
pub const LEX_KIND_NONE: Int = 0;

/// A maximal ASCII identifier run that is not in the table.
pub const LEX_KIND_IDENTIFIER: Int = 1;

/// An integer literal: digits with single underscores between digits.
pub const LEX_KIND_INTEGER: Int = 2;

/// A float-style literal: digits '.' digits with an optional exponent.
pub const LEX_KIND_FLOAT: Int = 3;

/// A string literal, quotes inclusive; text is kept raw (escapes undecoded).
pub const LEX_KIND_STRING: Int = 4;

/// A punctuation/operator token resolved through the table.
pub const LEX_KIND_PUNCT: Int = 5;

/// An identifier whose exact text is registered as a keyword in the table.
pub const LEX_KIND_KEYWORD: Int = 6;

/// A line comment (`// ...`) or block comment (`/* ... */`), delimiters
/// inclusive, trailing newline excluded.
pub const LEX_KIND_COMMENT: Int = 7;

/// End of input, reported by lex_next as a zero-width token; lex_scan never
/// stores it in the stream.
pub const LEX_KIND_EOF: Int = 8;

// ---------------------------------------------------------------------------
// Byte constants (ASCII; all comparisons happen in the Int domain)
// ---------------------------------------------------------------------------

const _LX_TAB: Int = 9;
const _LX_LF: Int = 10;
const _LX_CR: Int = 13;
const _LX_SPACE: Int = 32;
const _LX_QUOTE: Int = 34;
const _LX_STAR: Int = 42;
const _LX_PLUS: Int = 43;
const _LX_MINUS: Int = 45;
const _LX_DOT: Int = 46;
const _LX_SLASH: Int = 47;
const _LX_DIGIT_0: Int = 48;
const _LX_DIGIT_9: Int = 57;
const _LX_UPPER_A: Int = 65;
const _LX_UPPER_E: Int = 69;
const _LX_UPPER_Z: Int = 90;
const _LX_BACKSLASH: Int = 92;
const _LX_UNDERSCORE: Int = 95;
const _LX_LOWER_A: Int = 97;
const _LX_LOWER_E: Int = 101;
const _LX_LOWER_N: Int = 110;
const _LX_LOWER_T: Int = 116;
const _LX_LOWER_Z: Int = 122;

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

/// One classified token. `start` is inclusive and `end` exclusive; `line` and
/// `col` are the 1-based position of the first byte.
pub type Token = {
  kind: Int;
  start: Int;
  end: Int;
  line: Int;
  col: Int;
}

/// Scanner state over an immutable source Str.
///
/// `pos` is a byte offset (0-based); `line` and `col` are 1-based. `line`
/// advances on every LF byte (so CRLF counts as one newline) and `col` is the
/// byte distance from the last LF plus one; tab is one column, not a tab stop.
pub type ScanState = {
  source: Str;
  pos: Int;
  line: Int;
  col: Int;
}

/// Classification table: parallel Vec[Str] words and Vec[Int] kinds (entry i
/// pairs words[i] with kinds[i]). Register keywords, operators and
/// punctuation with lex_table_add.
pub type KeywordTable = {
  words: Vec[Str];
  kinds: Vec[Int];
}

/// Token stream as five parallel Vec fields; token i is fully described by
/// (kinds[i], starts[i], ends[i], lines[i], cols[i]). Five Vecs stand in for a
/// Vec[Token] because XIOM cannot hold Vec[StructType].
pub type TokenStream = {
  kinds: Vec[Int];
  starts: Vec[Int];
  ends: Vec[Int];
  lines: Vec[Int];
  cols: Vec[Int];
}

// ---------------------------------------------------------------------------
// Byte access and predicates
// ---------------------------------------------------------------------------

// Widened, masked byte value: the only way bytes leave UInt8 land.
fn _widen(b: UInt8) -> Int {
  return (b as Int) & 0xFF;
}

// Byte at `pos` as 0..255, or -1 when out of bounds (negative or at/after the
// end). Bounds are checked before byte_at, so this never traps.
fn _peek(source: Str, pos: Int) -> Int {
  if pos < 0 {
    return -1;
  }
  if pos >= source.len() {
    return -1;
  }
  let raw: UInt8 = string.byte_at(source, pos);
  return _widen(raw);
}

fn _is_digit(b: Int) -> Bool {
  return b >= _LX_DIGIT_0 && b <= _LX_DIGIT_9;
}

fn _is_ident_start(b: Int) -> Bool {
  if b >= _LX_UPPER_A && b <= _LX_UPPER_Z {
    return true;
  }
  if b >= _LX_LOWER_A && b <= _LX_LOWER_Z {
    return true;
  }
  return b == _LX_UNDERSCORE;
}

fn _is_ident_byte(b: Int) -> Bool {
  if _is_ident_start(b) {
    return true;
  }
  return _is_digit(b);
}

fn _is_space(b: Int) -> Bool {
  if b == _LX_SPACE {
    return true;
  }
  if b == _LX_TAB {
    return true;
  }
  if b == _LX_CR {
    return true;
  }
  return b == _LX_LF;
}

// The " at <pos>" suffix shared by every error message.
fn _err_pos(text: Str, pos: Int) -> Str {
  return "lexer: " + text + " at " + int_to_string(pos);
}

// ---------------------------------------------------------------------------
// Scan state
// ---------------------------------------------------------------------------

/// A fresh state at byte 0, line 1, column 1.
/// Params: source - the immutable input.
/// Returns: the initial state.
/// Error case: none.
/// Complexity: O(1).
pub fn lex_state_new(source: Str) -> ScanState {
  return ScanState{ source: source; pos: 0; line: 1; col: 1; };
}

/// The source the state scans. Complexity: O(1).
pub fn lex_state_source(s: &ScanState) -> Str {
  return s.source;
}

/// Current byte offset (0-based). Complexity: O(1).
pub fn lex_pos(s: &ScanState) -> Int {
  return s.pos;
}

/// Current 1-based line. Complexity: O(1).
pub fn lex_line(s: &ScanState) -> Int {
  return s.line;
}

/// Current 1-based column (bytes since the last LF, plus one).
/// Complexity: O(1).
pub fn lex_col(s: &ScanState) -> Int {
  return s.col;
}

/// True when every byte has been consumed. Complexity: O(1).
pub fn lex_at_end(s: &ScanState) -> Bool {
  return s.pos >= s.source.len();
}

/// Byte at the current position as 0..255, or -1 at end of input.
/// Complexity: O(1).
pub fn lex_peek(s: &ScanState) -> Int {
  return _peek(s.source, s.pos);
}

/// Byte `ahead` bytes after the current position as 0..255, or -1 when that
/// position is out of bounds (ahead may be negative).
/// Complexity: O(1).
pub fn lex_peek_at(s: &ScanState, ahead: Int) -> Int {
  return _peek(s.source, s.pos + ahead);
}

/// Consume one byte, updating pos and the line/column tracker. An LF moves to
/// the next line, column 1; any other byte increments the column. At end of
/// input this is a no-op.
/// Complexity: O(1).
pub fn lex_advance(s: &mut ScanState) {
  if s.pos >= s.source.len() {
    return;
  }
  let b = _peek(s.source, s.pos);
  if b == _LX_LF {
    s.line = s.line + 1;
    s.col = 1;
  } else {
    s.col = s.col + 1;
  }
  s.pos = s.pos + 1;
}

/// Consume `n` bytes (n <= 0 is a no-op; scanning stops at end of input).
/// Complexity: O(n).
pub fn lex_advance_n(s: &mut ScanState, n: Int) {
  var i = 0;
  while i < n && s.pos < s.source.len() {
    let b = _peek(s.source, s.pos);
    if b == _LX_LF {
      s.line = s.line + 1;
      s.col = 1;
    } else {
      s.col = s.col + 1;
    }
    s.pos = s.pos + 1;
    i = i + 1;
  }
}

/// Consume the next byte when it equals `expected` (an Int byte value 0..255).
/// Params: s - the state; expected - the byte value to match.
/// Returns: true when the byte was consumed.
/// Complexity: O(1).
pub fn lex_expect(s: &mut ScanState, expected: Int) -> Bool {
  if _peek(s.source, s.pos) != expected {
    return false;
  }
  lex_advance(s);
  return true;
}

/// Consume the literal `text` when it is the next input. An empty text
/// matches trivially without consuming anything.
/// Params: s - the state; text - the literal to match.
/// Returns: true when the whole literal was consumed.
/// Complexity: O(len(text)).
pub fn lex_expect_str(s: &mut ScanState, text: Str) -> Bool {
  let n = text.len();
  if n == 0 {
    return true;
  }
  if s.pos + n > s.source.len() {
    return false;
  }
  let piece = string.str_slice(s.source, s.pos, s.pos + n);
  if compare.str_compare(piece, text) != 0 {
    return false;
  }
  lex_advance_n(s, n);
  return true;
}

/// Skip space, tab, LF and CR, tracking lines and columns.
/// Complexity: O(skipped bytes).
pub fn lex_skip_spaces(s: &mut ScanState) {
  while s.pos < s.source.len() {
    let b = _peek(s.source, s.pos);
    if _is_space(b) {
      lex_advance(s);
    } else {
      return;
    }
  }
}

// &mut-taking state probes: lexer_next and lexer_scan bodies touch the state
// only through &mut helpers (advisory E001: a `&` call before a `&mut` access
// on the same local is flagged by this compiler).
fn _peek_mut(s: &mut ScanState) -> Int {
  return _peek(s.source, s.pos);
}

fn _peek_at_mut(s: &mut ScanState, ahead: Int) -> Int {
  return _peek(s.source, s.pos + ahead);
}

// ---------------------------------------------------------------------------
// Matchers (regex-free, byte-wise; each returns the matched length, 0 = no
// match; the Result-returning matchers carry exact error messages)
// ---------------------------------------------------------------------------

// Run of digits with single underscores between digits: [0-9](_?[0-9])*.
// A trailing underscore and a doubled underscore are never consumed.
fn _match_digit_run(source: Str, at: Int) -> Int {
  if !_is_digit(_peek(source, at)) {
    return 0;
  }
  var i = at + 1;
  var scanning = true;
  while scanning {
    let b = _peek(source, i);
    if _is_digit(b) {
      i = i + 1;
    } elif b == _LX_UNDERSCORE && _is_digit(_peek(source, i + 1)) {
      i = i + 2;
    } else {
      scanning = false;
    }
  }
  return i - at;
}

/// Identifier matcher: [A-Za-z_][A-Za-z0-9_]* as a maximal run.
/// Params: source - the input; at - the byte offset to test.
/// Returns: the matched length, or 0 when no identifier starts at `at`.
/// Error case: none.
/// Complexity: O(run length).
pub fn lex_match_identifier(source: Str, at: Int) -> Int {
  if !_is_ident_start(_peek(source, at)) {
    return 0;
  }
  var i = at + 1;
  while _is_ident_byte(_peek(source, i)) {
    i = i + 1;
  }
  return i - at;
}

/// Integer literal matcher: `[0-9](_?[0-9])*` as a maximal run (single
/// underscores between digits; no sign, no decimal point -- a sign is
/// caller-level and the float matcher claims a following '.').
/// Params: source - the input; at - the byte offset to test.
/// Returns: the matched length, or 0 when no digit starts at `at`.
/// Error case: none.
/// Complexity: O(run length).
pub fn lex_match_integer(source: Str, at: Int) -> Int {
  return _match_digit_run(source, at);
}

/// Float-style literal matcher:
/// `digits [underscores] '.' digits [underscores] [ ('e'|'E') ['+'|'-'] digits [underscores] ]`.
/// Both sides of the '.' need at least one digit, so "1." and ".5" do not
/// match. When the exponent marker is not followed by digits it is not
/// consumed: "1.5e" matches "1.5" (then 'e' is a separate identifier).
/// Params: source - the input; at - the byte offset to test.
/// Returns: the matched length, or 0 when no float starts at `at`.
/// Error case: none.
/// Complexity: O(run length).
pub fn lex_match_float(source: Str, at: Int) -> Int {
  let head = _match_digit_run(source, at);
  if head == 0 {
    return 0;
  }
  let dot = at + head;
  if _peek(source, dot) != _LX_DOT {
    return 0;
  }
  let frac = _match_digit_run(source, dot + 1);
  if frac == 0 {
    return 0;
  }
  var end = dot + 1 + frac;
  let marker = _peek(source, end);
  if marker == _LX_LOWER_E || marker == _LX_UPPER_E {
    var j = end + 1;
    let sign = _peek(source, j);
    if sign == _LX_PLUS || sign == _LX_MINUS {
      j = j + 1;
    }
    let exp_len = _match_digit_run(source, j);
    if exp_len > 0 {
      end = j + exp_len;
    }
  }
  return end - at;
}

/// String-literal matcher (double quotes, quotes included in the length).
/// The four recognized escapes are `\"`, `\\`, `\n` and `\t`; every other
/// byte between the quotes, including a raw LF, is kept verbatim and a raw
/// unescaped '"' closes the literal.
/// Params: source - the input; at - the byte offset to test.
/// Returns: Ok(0) when the byte at `at` is not '"'; Ok(len) with the full
/// literal length (quotes inclusive) when it is.
/// Error case: Err("lexer: unterminated string at <pos>") when the closing
/// quote is missing (pos = the opening quote, also when a backslash is the
/// last byte); Err("lexer: invalid escape at <pos>") for a backslash
/// followed by any other byte (pos = the backslash).
/// Complexity: O(literal length).
pub fn lex_match_string(source: Str, at: Int) -> Result[Int, Str] {
  if _peek(source, at) != _LX_QUOTE {
    return _ok_int(0);
  }
  let n = source.len();
  var i = at + 1;
  while i < n {
    let b = _peek(source, i);
    if b == _LX_QUOTE {
      return _ok_int(i + 1 - at);
    }
    if b == _LX_BACKSLASH {
      let e = _peek(source, i + 1);
      if e == _LX_QUOTE || e == _LX_BACKSLASH || e == _LX_LOWER_N || e == _LX_LOWER_T {
        i = i + 2;
      } elif e == -1 {
        return _err_str(_err_pos("unterminated string", at));
      } else {
        return _err_str(_err_pos("invalid escape", i));
      }
    } else {
      i = i + 1;
    }
  }
  return _err_str(_err_pos("unterminated string", at));
}

/// Line-comment matcher: `//` up to (not including) the next LF or end of
/// input. The text always starts with exactly the two slashes.
/// Params: source - the input; at - the byte offset to test.
/// Returns: the matched length (>= 2), or 0 when `//` does not start at `at`.
/// Error case: none.
/// Complexity: O(comment length).
pub fn lex_match_line_comment(source: Str, at: Int) -> Int {
  if _peek(source, at) != _LX_SLASH {
    return 0;
  }
  if _peek(source, at + 1) != _LX_SLASH {
    return 0;
  }
  let n = source.len();
  var i = at + 2;
  while i < n && _peek(source, i) != _LX_LF {
    i = i + 1;
  }
  return i - at;
}

/// Block-comment matcher: `/* ... */`, non-nesting, delimiters included.
/// Params: source - the input; at - the byte offset to test.
/// Returns: Ok(0) when `/*` does not start at `at`; Ok(len) with the full
/// comment length (both delimiters inclusive) when it does.
/// Error case: Err("lexer: unterminated block comment at <pos>") when the
/// closing `*/` is missing (pos = the opening slash).
/// Complexity: O(comment length).
pub fn lex_match_block_comment(source: Str, at: Int) -> Result[Int, Str] {
  if _peek(source, at) != _LX_SLASH {
    return _ok_int(0);
  }
  if _peek(source, at + 1) != _LX_STAR {
    return _ok_int(0);
  }
  let n = source.len();
  var i = at + 2;
  while i + 1 < n {
    if _peek(source, i) == _LX_STAR && _peek(source, i + 1) == _LX_SLASH {
      return _ok_int(i + 2 - at);
    }
    i = i + 1;
  }
  return _err_str(_err_pos("unterminated block comment", at));
}

// ---------------------------------------------------------------------------
// Keyword table
// ---------------------------------------------------------------------------

/// An empty table (no words). Params: none. Returns: a fresh table.
/// Complexity: O(1).
pub fn lex_table_new() -> KeywordTable {
  return KeywordTable{ words: Vec[Str].new(); kinds: Vec[Int].new(); };
}

/// Register `word` with kind `kind` (typically LEX_KIND_KEYWORD or
/// LEX_KIND_PUNCT). The lookup is exact and case-sensitive; the earliest
/// registered duplicate wins. An empty word never matches.
/// Params: t - the table to mutate; word - the text; kind - the kind value.
/// Error case: none.
/// Complexity: O(1).
pub fn lex_table_add(t: &mut KeywordTable, word: Str, kind: Int) {
  t.words.push(word);
  t.kinds.push(kind);
}

/// Number of registered words. Complexity: O(1).
pub fn lex_table_len(t: &KeywordTable) -> Int {
  return t.words.len();
}

/// Word at index `i`, or "" when out of range. Complexity: O(1).
pub fn lex_table_word(t: &KeywordTable, i: Int) -> Str {
  if i < 0 || i >= t.words.len() {
    return "";
  }
  let w: Str = t.words[i];
  return w;
}

/// Kind at index `i`, or LEX_KIND_NONE when out of range. Complexity: O(1).
pub fn lex_table_kind(t: &KeywordTable, i: Int) -> Int {
  if i < 0 || i >= t.kinds.len() {
    return LEX_KIND_NONE;
  }
  let k: Int = t.kinds[i];
  return k;
}

/// Exact, case-sensitive lookup of `word`: the kind registered for the first
/// entry whose text equals `word`, or LEX_KIND_NONE when absent.
/// Params: t - the table; word - the text to look up.
/// Returns: the registered kind, or LEX_KIND_NONE.
/// Error case: none.
/// Complexity: O(|table| * |word|).
pub fn lex_table_lookup(t: &KeywordTable, word: Str) -> Int {
  var i = 0;
  while i < t.words.len() {
    let w: Str = t.words[i];
    if compare.str_compare(w, word) == 0 {
      let k: Int = t.kinds[i];
      return k;
    }
    i = i + 1;
  }
  return LEX_KIND_NONE;
}

/// Classify an identifier text: the table kind when registered, else
/// LEX_KIND_IDENTIFIER.
/// Params: t - the table; word - the identifier text.
/// Returns: the registered kind (keyword/punct/...), or LEX_KIND_IDENTIFIER.
/// Error case: none.
/// Complexity: O(|table| * |word|).
pub fn lex_table_classify(t: &KeywordTable, word: Str) -> Int {
  let k = lex_table_lookup(t, word);
  if k != LEX_KIND_NONE {
    return k;
  }
  return LEX_KIND_IDENTIFIER;
}

// Index of the longest registered word matching `source` at `at` (the
// earliest registered entry wins ties), or -1 when none matches. Empty words
// never match.
fn _table_match_index(table: &KeywordTable, source: Str, at: Int) -> Int {
  var best_len: Int = 0;
  var best: Int = -1;
  var i = 0;
  while i < table.words.len() {
    let w: Str = table.words[i];
    let wl = w.len();
    if wl > best_len && at + wl <= source.len() {
      let piece = string.str_slice(source, at, at + wl);
      if compare.str_compare(piece, w) == 0 {
        best_len = wl;
        best = i;
      }
    }
    i = i + 1;
  }
  return best;
}

// ---------------------------------------------------------------------------
// Scanner engine
// ---------------------------------------------------------------------------

// Kind name for a token kind constant (diagnostics; "none" for unknown).
/// Params: kind - a LEX_KIND_* value.
/// Returns: "identifier", "integer", "float-literal", "string-literal",
/// "punctuation", "keyword", "comment", "EOF", or "none".
/// Complexity: O(1).
pub fn lex_kind_name(kind: Int) -> Str {
  if kind == LEX_KIND_IDENTIFIER {
    return "identifier";
  }
  if kind == LEX_KIND_INTEGER {
    return "integer";
  }
  if kind == LEX_KIND_FLOAT {
    return "float-literal";
  }
  if kind == LEX_KIND_STRING {
    return "string-literal";
  }
  if kind == LEX_KIND_PUNCT {
    return "punctuation";
  }
  if kind == LEX_KIND_KEYWORD {
    return "keyword";
  }
  if kind == LEX_KIND_COMMENT {
    return "comment";
  }
  if kind == LEX_KIND_EOF {
    return "EOF";
  }
  return "none";
}

/// Scan one token, advancing the state past it. Whitespace is skipped. At end
/// of input this returns Ok with a zero-width LEX_KIND_EOF token.
///
/// Resolution order at a position: whitespace; `//` or `/*` comment; ASCII
/// identifier (classified through the table: keyword/punct kind when its
/// exact text is registered, else identifier); float-then-integer for a
/// digit; string for '"'; otherwise the longest registered table word (any
/// registered kind); otherwise an error.
///
/// Params: s - the scan state (mutated); table - the classification table.
/// Returns: Ok(Token) with the token and its 1-based line/col.
/// Error case: Err("lexer: unterminated string at <pos>"),
/// Err("lexer: invalid escape at <pos>"),
/// Err("lexer: unterminated block comment at <pos>"),
/// Err("lexer: unexpected byte at <pos>") -- positions as in SPEC.md.
/// Complexity: O(token length) plus table matching.
pub fn lex_next(s: &mut ScanState, table: &KeywordTable) -> Result[Token, Str] {
  lex_skip_spaces(s);
  let start = s.pos;
  let line = s.line;
  let col = s.col;
  if s.pos >= s.source.len() {
    return _ok_token(Token{ kind: LEX_KIND_EOF; start: start; end: start; line: line; col: col; });
  }
  let b = _peek_mut(s);
  if b == _LX_SLASH {
    let b1 = _peek_at_mut(s, 1);
    if b1 == _LX_SLASH {
      let len = lex_match_line_comment(s.source, start);
      lex_advance_n(s, len);
      return _ok_token(Token{ kind: LEX_KIND_COMMENT; start: start; end: start + len; line: line; col: col; });
    }
    if b1 == _LX_STAR {
      let r = lex_match_block_comment(s.source, start);
      if !r.is_ok {
        return _err_token(r.error);
      }
      let len: Int = r.value;
      lex_advance_n(s, len);
      return _ok_token(Token{ kind: LEX_KIND_COMMENT; start: start; end: start + len; line: line; col: col; });
    }
  }
  if _is_ident_start(b) {
    let len = lex_match_identifier(s.source, start);
    let word = string.str_slice(s.source, start, start + len);
    let kind = lex_table_classify(table, word);
    lex_advance_n(s, len);
    return _ok_token(Token{ kind: kind; start: start; end: start + len; line: line; col: col; });
  }
  if _is_digit(b) {
    let flen = lex_match_float(s.source, start);
    if flen > 0 {
      lex_advance_n(s, flen);
      return _ok_token(Token{ kind: LEX_KIND_FLOAT; start: start; end: start + flen; line: line; col: col; });
    }
    let ilen = lex_match_integer(s.source, start);
    lex_advance_n(s, ilen);
    return _ok_token(Token{ kind: LEX_KIND_INTEGER; start: start; end: start + ilen; line: line; col: col; });
  }
  if b == _LX_QUOTE {
    let r = lex_match_string(s.source, start);
    if !r.is_ok {
      return _err_token(r.error);
    }
    let len: Int = r.value;
    lex_advance_n(s, len);
    return _ok_token(Token{ kind: LEX_KIND_STRING; start: start; end: start + len; line: line; col: col; });
  }
  let idx = _table_match_index(table, s.source, start);
  if idx >= 0 {
    let w: Str = lex_table_word(table, idx);
    let kind: Int = lex_table_kind(table, idx);
    let len = w.len();
    lex_advance_n(s, len);
    return _ok_token(Token{ kind: kind; start: start; end: start + len; line: line; col: col; });
  }
  return _err_token(_err_pos("unexpected byte", start));
}

/// Scan the whole input into a token stream (comments included, no EOF
/// sentinel). On the first error the partial stream is discarded and the
/// exact message is returned.
///
/// Params: source - the input; table - the classification table.
/// Returns: Ok(TokenStream) with one entry per token, in source order.
/// Error case: as lex_next (first error aborts the scan).
/// Complexity: O(n) bytes times the per-token table cost.
pub fn lex_scan(source: Str, table: &KeywordTable) -> Result[TokenStream, Str] {
  var kinds = Vec[Int].new();
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  var lines = Vec[Int].new();
  var cols = Vec[Int].new();
  var st = lex_state_new(source);
  var going = true;
  while going {
    let r = lex_next(&mut st, table);
    if !r.is_ok {
      return _err_stream(r.error);
    }
    let tok: Token = r.value;
    if tok.kind == LEX_KIND_EOF {
      going = false;
    } else {
      kinds.push(tok.kind);
      starts.push(tok.start);
      ends.push(tok.end);
      lines.push(tok.line);
      cols.push(tok.col);
    }
  }
  return _ok_stream(TokenStream{ kinds: kinds; starts: starts; ends: ends; lines: lines; cols: cols; });
}

// ---------------------------------------------------------------------------
// Token-stream accessors
// ---------------------------------------------------------------------------

/// Number of tokens in the stream. Complexity: O(1).
pub fn lex_token_count(t: &TokenStream) -> Int {
  return t.kinds.len();
}

/// Kind of token `i`, or LEX_KIND_NONE when `i` is out of range.
/// Complexity: O(1).
pub fn lex_token_kind(t: &TokenStream, i: Int) -> Int {
  if i < 0 || i >= t.kinds.len() {
    return LEX_KIND_NONE;
  }
  let k: Int = t.kinds[i];
  return k;
}

/// Start byte offset (inclusive) of token `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn lex_token_start(t: &TokenStream, i: Int) -> Int {
  if i < 0 || i >= t.starts.len() {
    return -1;
  }
  let v: Int = t.starts[i];
  return v;
}

/// End byte offset (exclusive) of token `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn lex_token_end(t: &TokenStream, i: Int) -> Int {
  if i < 0 || i >= t.ends.len() {
    return -1;
  }
  let v: Int = t.ends[i];
  return v;
}

/// 1-based line of token `i`, or -1 when out of range. Complexity: O(1).
pub fn lex_token_line(t: &TokenStream, i: Int) -> Int {
  if i < 0 || i >= t.lines.len() {
    return -1;
  }
  let v: Int = t.lines[i];
  return v;
}

/// 1-based column of token `i`, or -1 when out of range. Complexity: O(1).
pub fn lex_token_col(t: &TokenStream, i: Int) -> Int {
  if i < 0 || i >= t.cols.len() {
    return -1;
  }
  let v: Int = t.cols[i];
  return v;
}

/// Raw source slice [start, end): the shared text reconstruction. Out-of-range
/// and inverted spans clamp to the overlapping region (xiom.string.str_slice
/// semantics), so this never traps.
/// Params: source - the scanned input; start - inclusive byte offset;
///         end - exclusive byte offset.
/// Returns: the slice, or "" when the span is empty after clamping.
/// Error case: none.
/// Complexity: O(end - start).
pub fn lex_span_text(source: Str, start: Int, end: Int) -> Str {
  return string.str_slice(source, start, end);
}

/// Reconstruct the raw text of token `i` with a source slice (the convenience
/// accessor). Escapes are NOT decoded: a string token's text includes its
/// quotes and backslash sequences exactly as written.
/// Params: source - the scanned input; t - the stream; i - the token index.
/// Returns: the raw text, or "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(token length).
pub fn token_text(source: Str, t: &TokenStream, i: Int) -> Str {
  if i < 0 || i >= t.kinds.len() {
    return "";
  }
  let a: Int = t.starts[i];
  let e: Int = t.ends[i];
  return string.str_slice(source, a, e);
}

// ---------------------------------------------------------------------------
// Result constructors (leaf helpers only -- see the module header)
// ---------------------------------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Int, Str] {
  return Err(m);
}

fn _ok_token(t: Token) -> Result[Token, Str] {
  return Ok(t);
}

fn _err_token(m: Str) -> Result[Token, Str] {
  return Err(m);
}

fn _ok_stream(v: TokenStream) -> Result[TokenStream, Str] {
  return Ok(v);
}

fn _err_stream(m: Str) -> Result[TokenStream, Str] {
  return Err(m);
}
