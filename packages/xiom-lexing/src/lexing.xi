// XIOM -- xiom.lexing: configurable tokenizer (identifiers, keywords, integers,
// strings, operators)
// Port task: replace the xiom.lexing placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A small, configuration-driven lexer over UTF-8 Str input. The scanner is
// byte-wise and classifies tokens in this priority order:
//   * [A-Za-z_][A-Za-z0-9_]* => "kw" when the exact token text was registered
//     with lexer_add_keyword, else "ident";
//   * [0-9]+                  => "int" (verbatim digits; no sign, no float);
//   * "..."                   => "str" with \" \\ \n \t escapes decoded;
//   * a registered operator   => "op" (the longest matching operator wins);
//   * any other byte          => Err("lexing: unexpected byte at <pos>").
// Whitespace (space, tab, LF, CR) is skipped. Every scan has three parallel
// Vecs (kinds/texts/starts) because XIOM v0.61.3 cannot hold Vec[StructType].
// See SPEC.md for the full token grammar, escape table, error catalog and
// test plan.
//
// Language notes (XIOM v0.61.3): free functions only; Str values read from
// Vec[Str] elements are compared with str_compare (BUG 17: `==` on such
// elements lowers to a pointer comparison); Ok/Err are constructed only in
// the leaf helpers _ok_tokens/_err_tokens because direct Result construction
// in other shapes miscompiles in this compiler.

module xiom.lexing

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Token containers
// --------------------------------------------------

// Token i is described by kinds[i] ("ident", "kw", "int", "str" or "op"),
// texts[i] (its source text; escapes decoded for "str") and starts[i] (its
// byte offset in the scanned input). Three parallel arrays stand in for a
// Vec[Token] because XIOM v0.61.3 cannot hold Vec[StructType].
pub type TokenList = {
  kinds: Vec[Str];
  texts: Vec[Str];
  starts: Vec[Int];
}

// Lexer configuration: the registered keywords and operators. All fields are
// internal; use the lexer_* functions below.
pub type Lexer = {
  keywords: Vec[Str];
  operators: Vec[Str];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[TokenList, Str].
fn _ok_tokens(v: TokenList) -> Result[TokenList, Str] {
  return Ok(v);
}

// Err(m) for Result[TokenList, Str].
fn _err_tokens(m: Str) -> Result[TokenList, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants and predicates
// --------------------------------------------------

const _LX_TAB: UInt8 = 9u8;
const _LX_LF: UInt8 = 10u8;
const _LX_CR: UInt8 = 13u8;
const _LX_SPACE: UInt8 = 32u8;
const _LX_QUOTE: UInt8 = 34u8;
const _LX_BACKSLASH: UInt8 = 92u8;
const _LX_UNDERSCORE: UInt8 = 95u8;
const _LX_LOWER_N: UInt8 = 110u8;
const _LX_LOWER_T: UInt8 = 116u8;

// ASCII whitespace byte: space, tab, LF or CR.
fn _is_space_byte(b: UInt8) -> Bool {
  return b == _LX_SPACE || b == _LX_TAB || b == _LX_LF || b == _LX_CR;
}

// ASCII digit byte: 0-9.
fn _is_digit_byte(b: UInt8) -> Bool {
  return b >= 48u8 && b <= 57u8;
}

// Identifier-start byte: A-Z, a-z or _.
fn _is_ident_start(b: UInt8) -> Bool {
  if b >= 65u8 && b <= 90u8 { return true; }   // A-Z
  if b >= 97u8 && b <= 122u8 { return true; }  // a-z
  return b == _LX_UNDERSCORE;
}

// Identifier-continue byte: A-Z, a-z, 0-9 or _.
fn _is_ident_byte(b: UInt8) -> Bool {
  if _is_ident_start(b) { return true; }
  return _is_digit_byte(b);
}

// --------------------------------------------------
//  Configuration
// --------------------------------------------------

/// A lexer with no keywords and no operators.
/// Params: none.
/// Returns: a fresh, empty configuration.
/// Error case: none.
/// Complexity: O(1).
pub fn lexer_new() -> Lexer {
  return Lexer{
    keywords: Vec[Str].new();
    operators: Vec[Str].new();
  };
}

/// Register `word` as a keyword. Scanning classifies an identifier token as
/// "kw" exactly when its text equals a registered keyword (case-sensitive;
/// duplicates are harmless).
/// Params: l - the lexer to mutate; word - the keyword text.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn lexer_add_keyword(l: &mut Lexer, word: Str) {
  l.keywords.push(word);
}

/// Register `op` as an operator. During scanning the longest registered
/// operator matching at a position wins; ties are won by the earliest
/// registered operator. An empty operator string never matches.
/// Params: l - the lexer to mutate; op - the operator text.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn lexer_add_operator(l: &mut Lexer, op: Str) {
  l.operators.push(op);
}

// True when `word` is one of the registered keywords (str_compare because
// keyword texts are read from a Vec[Str]).
fn _is_keyword(l: &Lexer, word: Str) -> Bool {
  var i = 0;
  while i < l.keywords.len() {
    if compare.str_compare(l.keywords[i], word) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Length of the longest registered operator matching `text` at `at`; 0 when
// none matches. Empty operators are ignored (0 is never a match).
fn _match_operator_len(l: &Lexer, text: Str, at: Int) -> Int {
  var best: Int = 0;
  var i = 0;
  while i < l.operators.len() {
    let op = l.operators[i];
    let olen = op.len();
    if olen > best && at + olen <= text.len() {
      let piece = string.str_slice(text, at, at + olen);
      if compare.str_compare(piece, op) == 0 {
        best = olen;
      }
    }
    i = i + 1;
  }
  return best;
}

// --------------------------------------------------
//  Scanning
// --------------------------------------------------

/// Scan `text` into a token list under the lexer's configuration.
/// Params: l - the lexer configuration; text - the input to scan.
/// Returns: Ok(TokenList) with one entry per token, in source order:
///   * [A-Za-z_][A-Za-z0-9_]* -> "kw" when the exact text is registered,
///     else "ident";
///   * [0-9]+ -> "int", text verbatim;
///   * "..." -> "str", with \" \\ \n \t decoded (any other byte inside the
///     quotes is kept verbatim; an empty literal yields text "");
///   * a registered operator -> "op", longest match at the position wins.
///   Whitespace (space, tab, LF, CR) is skipped; starts are byte offsets.
/// Error case: Err("lexing: unexpected byte at <pos>") for a byte that
/// starts no token; Err("lexing: invalid escape at <pos>") for an unknown
/// backslash escape inside a string (pos = the backslash); Err("lexing:
/// unterminated string at <pos>") when the closing quote is missing
/// (pos = the opening quote).
/// Complexity: O(n * (keywords + operators)) worst case, O(n) with small
/// configurations.
pub fn lexer_scan(l: &Lexer, text: Str) -> Result[TokenList, Str] {
  var kinds = Vec[Str].new();
  var texts = Vec[Str].new();
  var starts = Vec[Int].new();
  let n = text.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(text, i);
    if _is_space_byte(b) {
      i = i + 1;
    } elif _is_ident_start(b) {
      var j = i + 1;
      while j < n {
        let c = string.byte_at(text, j);
        if _is_ident_byte(c) {
          j = j + 1;
        } else {
          break;
        }
      }
      let word = string.str_slice(text, i, j);
      if _is_keyword(l, word) {
        kinds.push("kw");
      } else {
        kinds.push("ident");
      }
      texts.push(word);
      starts.push(i);
      i = j;
    } elif _is_digit_byte(b) {
      var j = i + 1;
      while j < n {
        let c = string.byte_at(text, j);
        if _is_digit_byte(c) {
          j = j + 1;
        } else {
          break;
        }
      }
      kinds.push("int");
      texts.push(string.str_slice(text, i, j));
      starts.push(i);
      i = j;
    } elif b == _LX_QUOTE {
      var sb = Vec[UInt8].new();
      var j = i + 1;
      var closed = false;
      while j < n {
        let c = string.byte_at(text, j);
        if c == _LX_QUOTE {
          closed = true;
          j = j + 1;
          break;
        } elif c == _LX_BACKSLASH {
          if j + 1 >= n {
            return _err_tokens("lexing: unterminated string at " + int_to_string(i));
          }
          let e = string.byte_at(text, j + 1);
          if e == _LX_QUOTE {
            sb.push(_LX_QUOTE);
            j = j + 2;
          } elif e == _LX_BACKSLASH {
            sb.push(_LX_BACKSLASH);
            j = j + 2;
          } elif e == _LX_LOWER_N {
            sb.push(_LX_LF);
            j = j + 2;
          } elif e == _LX_LOWER_T {
            sb.push(_LX_TAB);
            j = j + 2;
          } else {
            return _err_tokens("lexing: invalid escape at " + int_to_string(j));
          }
        } else {
          sb.push(c);
          j = j + 1;
        }
      }
      if !closed {
        return _err_tokens("lexing: unterminated string at " + int_to_string(i));
      }
      kinds.push("str");
      texts.push(Str::from_utf8(sb));
      starts.push(i);
      i = j;
    } else {
      let olen = _match_operator_len(l, text, i);
      if olen > 0 {
        kinds.push("op");
        texts.push(string.str_slice(text, i, i + olen));
        starts.push(i);
        i = i + olen;
      } else {
        return _err_tokens("lexing: unexpected byte at " + int_to_string(i));
      }
    }
  }
  return _ok_tokens(TokenList{
    kinds: kinds;
    texts: texts;
    starts: starts;
  });
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of tokens in `t`.
/// Params: t - the token list.
/// Returns: the token count; 0 for an empty list.
/// Error case: none.
/// Complexity: O(1).
pub fn lexer_token_count(t: &TokenList) -> Int {
  return t.kinds.len();
}

/// Kind of token `i`.
/// Params: t - the token list; i - the zero-based token index.
/// Returns: "ident", "kw", "int", "str" or "op"; "" when `i` is negative or
/// out of range (so use the kind to tell an empty-string token apart).
/// Error case: none.
/// Complexity: O(1).
pub fn lexer_kind(t: &TokenList, i: Int) -> Str {
  if i < 0 || i >= t.kinds.len() {
    return "";
  }
  return t.kinds[i];
}

/// Text of token `i`.
/// Params: t - the token list; i - the zero-based token index.
/// Returns: the token text (escape sequences already decoded for "str"
/// tokens); "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lexer_text(t: &TokenList, i: Int) -> Str {
  if i < 0 || i >= t.texts.len() {
    return "";
  }
  return t.texts[i];
}

/// Byte offset of token `i` in the scanned input.
/// Params: t - the token list; i - the zero-based token index.
/// Returns: the offset of the token's first byte; -1 when `i` is negative or
/// out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn lexer_start(t: &TokenList, i: Int) -> Int {
  if i < 0 || i >= t.starts.len() {
    return -1;
  }
  let s: Int = t.starts[i];
  return s;
}
