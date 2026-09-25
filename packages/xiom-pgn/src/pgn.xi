// XIOM -- xiom.pgn: PGN (Portable Game Notation) codec for a documented subset
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM, in-memory PGN codec. It parses a game into a tag list plus a
// flat movetext token stream, validates move numbers and SAN lexically, and
// emits a canonical text form. There is no board, no game tree and no
// legality semantics: `1. e4` and `1. Nf3` are equally acceptable SAN tokens.
//
// Document subset (see SPEC.md for the exact statement):
//   * tag pairs:   [Name "value"] on one physical line, with \" and \\
//                  escapes inside the quoted value;
//   * movetext:    move numbers (N. / N...), SAN tokens, brace comments
//                  { ... }, rest-of-line comments ; ..., NAGs $n and the
//                  result tokens 1-0, 0-1, 1/2-1/2, *;
//   * escape lines: a % anywhere a token could start skips to end of line;
//   * canonical emit: tags each on their own line, one blank line, then the
//                  movetext tokens joined with single spaces and a trailing
//                  newline.
//
// Explicit non-goals: board legality, game/annotation semantics, recursive
// annotation variations ( ) -- reported as an unsupported-variation error --
// NAG meaning, and any clock/annotation interpretation (they pass through).
//
// Grammar:
//   document   = *( ws | escape-line | tag-pair ) movetext
//   tag-pair   = "[" ws* name 1*ws '"' value '"' ws* "]" ( LF | CR | EOF )
//   name       = 1*( ALNUM | "_" )
//   value      = *( escaped | byte except '"' / "\" / LF / CR )
//   escaped    = '\"' | '\\'
//   movetext   = *( ws | comment | comment-line | nag | num | san | result )
//   comment    = "{" *( byte except "}" ) "}"      ; may span lines
//   comment-line = ";" *( byte except LF / CR )    ; ends at end of line
//   nag        = "$" 1*DIGIT
//   num        = 1*DIGIT "." | 1*DIGIT "..."       ; no space before the dots
//   result     = "1-0" | "0-1" | "1/2-1/2" | "*"
//   san        = castling | piece-move | pawn-move ; each with an optional
//                "+" or "#" suffix
//   castling   = "O-O" | "O-O-O"
//   piece-move = PIECE [file] [rank] ["x"] file rank
//   pawn-move  = [file "x"] file rank ["=" PROMO]
//   PIECE      = "K" | "Q" | "R" | "B" | "N"
//   PROMO      = "Q" | "R" | "B" | "N"
//   file       = "a".."h"     rank = "1".."8"
//
// Tag values decode only the two PGN escapes; raw LF or CR inside a value is
// an unterminated quote. Move numbers are validated as a sequence: the first
// number must be `1.`, a later `N.` must be the previous number plus one, and
// `N...` must repeat the previous number (so the ellipsis form needs a
// preceding number token).
//
// Language notes (XIOM v0.61.3): free functions only; no Vec[StructType] --
// TagList/MoveText are parallel Vec fields and Game nests the two structs;
// Str equality goes through xiom.string.compare.str_compare (BUG 17: `==` on
// Str values read from Vec[Str] elements lowers to a pointer comparison);
// every Vec[Str] read binds a typed local; Str values are materialized from a
// Vec[UInt8] buffer with xiom.string.builder.sb_to_str; Ok/Err for the public
// Result types are constructed only in the leaf helpers _ok_*/_err_*.

module xiom.pgn

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// Tag pairs in document order: `names[i]` and `values[i]` are index-aligned.
/// Values have `\"` and `\\` decoded; names are kept verbatim (PGN tag names
/// are case-sensitive). Duplicates are preserved in order.
pub type TagList = {
  names: Vec[Str];
  values: Vec[Str];
}

/// Movetext tokens in source order. `kinds[i]` is one of "num", "san",
/// "comment", "comment_line", "nag" or "result"; `texts[i]` is the token text
/// (see SPEC.md section 3 for the exact per-kind text); `starts[i]` is the
/// token's byte offset in the parsed input. Three parallel arrays stand in for
/// a Vec[Token] because XIOM v0.61.3 cannot hold Vec[StructType].
pub type MoveText = {
  kinds: Vec[Str];
  texts: Vec[Str];
  starts: Vec[Int];
}

/// A parsed game: its tag pairs and its movetext token stream.
pub type Game = {
  tags: TagList;
  moves: MoveText;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(g) for Result[Game, Str].
fn _ok_game(g: Game) -> Result[Game, Str] {
  return Ok(g);
}

// Err(m) for Result[Game, Str].
fn _err_game(m: Str) -> Result[Game, Str] {
  return Err(m);
}

// Ok(m) for Result[MoveText, Str].
fn _ok_moves(m: MoveText) -> Result[MoveText, Str] {
  return Ok(m);
}

// Err(m) for Result[MoveText, Str].
fn _err_moves(m: Str) -> Result[MoveText, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_pos(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_pos(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants and predicates
// --------------------------------------------------

const _PGN_TAB: UInt8 = 9u8;
const _PGN_LF: UInt8 = 10u8;
const _PGN_CR: UInt8 = 13u8;
const _PGN_SPACE: UInt8 = 32u8;
const _PGN_HASH: UInt8 = 35u8;
const _PGN_DQUOTE: UInt8 = 34u8;
const _PGN_DOLLAR: UInt8 = 36u8;
const _PGN_PERCENT: UInt8 = 37u8;
const _PGN_LPAREN: UInt8 = 40u8;
const _PGN_RPAREN: UInt8 = 41u8;
const _PGN_STAR: UInt8 = 42u8;
const _PGN_PLUS: UInt8 = 43u8;
const _PGN_DASH: UInt8 = 45u8;
const _PGN_DOT: UInt8 = 46u8;
const _PGN_SLASH: UInt8 = 47u8;
const _PGN_SEMI: UInt8 = 59u8;
const _PGN_EQ: UInt8 = 61u8;
const _PGN_LBRACKET: UInt8 = 91u8;
const _PGN_BACKSLASH: UInt8 = 92u8;
const _PGN_RBRACKET: UInt8 = 93u8;
const _PGN_UNDERSCORE: UInt8 = 95u8;
const _PGN_X: UInt8 = 120u8;
const _PGN_UPPER_O: UInt8 = 79u8;
const _PGN_LBRACE: UInt8 = 123u8;
const _PGN_RBRACE: UInt8 = 125u8;

// ASCII whitespace byte: space, tab, LF or CR.
fn _is_ws(b: UInt8) -> Bool {
  return b == _PGN_SPACE || b == _PGN_TAB || b == _PGN_LF || b == _PGN_CR;
}

// Space or horizontal tab (the only bytes allowed between tag-pair parts).
fn _is_space_tab(b: UInt8) -> Bool {
  return b == _PGN_SPACE || b == _PGN_TAB;
}

// ASCII digit byte: 0-9.
fn _is_digit(b: UInt8) -> Bool {
  return b >= 48u8 && b <= 57u8;
}

// SAN file byte: a-h.
fn _is_file(b: UInt8) -> Bool {
  return b >= 97u8 && b <= 104u8;
}

// SAN rank byte: 1-8.
fn _is_rank(b: UInt8) -> Bool {
  return b >= 49u8 && b <= 56u8;
}

// SAN piece letter: K, Q, R, B or N.
fn _is_piece(b: UInt8) -> Bool {
  if b == 75u8 { return true; }   // K
  if b == 81u8 { return true; }   // Q
  if b == 82u8 { return true; }   // R
  if b == 66u8 { return true; }   // B
  return b == 78u8;               // N
}

// SAN promotion piece letter: Q, R, B or N (a king cannot be promoted).
fn _is_promo_piece(b: UInt8) -> Bool {
  if b == 81u8 { return true; }   // Q
  if b == 82u8 { return true; }   // R
  if b == 66u8 { return true; }   // B
  return b == 78u8;               // N
}

// First byte that can begin an SAN token: a piece letter, a file letter or O.
fn _is_san_start(b: UInt8) -> Bool {
  if _is_piece(b) { return true; }
  if _is_file(b) { return true; }
  return b == _PGN_UPPER_O;
}

// A tag-name byte: ALNUM or "_".
fn _is_tag_name_byte(b: UInt8) -> Bool {
  if _is_digit(b) { return true; }
  if b >= 65u8 && b <= 90u8 { return true; }    // A-Z
  if b >= 97u8 && b <= 122u8 { return true; }   // a-z
  return b == _PGN_UNDERSCORE;
}

// A byte that terminates a movetext word: whitespace and the bytes that start
// or end other movetext tokens never occur inside a SAN token.
fn _is_word_delim(b: UInt8) -> Bool {
  if _is_ws(b) { return true; }
  if b == _PGN_LBRACE || b == _PGN_RBRACE { return true; }
  if b == _PGN_SEMI || b == _PGN_LPAREN || b == _PGN_RPAREN { return true; }
  if b == _PGN_DOLLAR || b == _PGN_PERCENT || b == _PGN_STAR { return true; }
  return b == _PGN_LBRACKET || b == _PGN_RBRACKET;
}

// --------------------------------------------------
//  Small helpers
// --------------------------------------------------

// "prefix" + decimal position, the fixed shape of every position-carrying
// error message.
fn _at(prefix: Str, pos: Int) -> Str {
  return prefix + int_to_string(pos);
}

// Index of the first LF or CR at or after `at` (text.len() when none).
fn _skip_to_eol(text: Str, at: Int) -> Int {
  let n = text.len();
  var i = at;
  while i < n {
    let b = string.byte_at(text, i);
    if b == _PGN_LF || b == _PGN_CR {
      break;
    }
    i = i + 1;
  }
  return i;
}

// Decimal value of a non-empty digit run, clamped at 1000000000 so that
// absurdly long move numbers cannot overflow and still fail the sequence
// check deterministically.
fn _digits_to_int(d: Str) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < d.len() {
    let c = (string.byte_at(d, i) as Int) & 0xFF;
    v = v * 10 + (c - 48);
    if v > 1000000000 {
      return 1000000000;
    }
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  SAN lexical validation
// --------------------------------------------------

// True when `w[0..n)` is exactly "O-O" or "O-O-O".
fn _is_castling_body(w: Str, n: Int) -> Bool {
  if n == 3 {
    return string.byte_at(w, 0) == _PGN_UPPER_O && string.byte_at(w, 1) == _PGN_DASH && string.byte_at(w, 2) == _PGN_UPPER_O;
  }
  if n == 5 {
    return string.byte_at(w, 0) == _PGN_UPPER_O && string.byte_at(w, 1) == _PGN_DASH && string.byte_at(w, 2) == _PGN_UPPER_O
      && string.byte_at(w, 3) == _PGN_DASH && string.byte_at(w, 4) == _PGN_UPPER_O;
  }
  return false;
}

// True when `w[i..n)` is an optional capture sign followed by a destination
// square and nothing else.
fn _piece_tail_ok(w: Str, n: Int, i: Int) -> Bool {
  var p = i;
  if p < n && string.byte_at(w, p) == _PGN_X {
    p = p + 1;
  }
  if p + 1 >= n {
    return false;
  }
  if !_is_file(string.byte_at(w, p)) {
    return false;
  }
  if !_is_rank(string.byte_at(w, p + 1)) {
    return false;
  }
  return p + 2 == n;
}

// Lexical SAN check (no board legality). Accepts castling, piece moves with
// optional file/rank disambiguation and optional capture sign, and pawn moves
// with optional capture file and optional "=" promotion, each with an
// optional "+" or "#" suffix.
fn _san_valid(w: Str) -> Bool {
  var n = w.len();
  if n == 0 {
    return false;
  }
  let last = string.byte_at(w, n - 1);
  if last == _PGN_PLUS || last == _PGN_HASH {
    n = n - 1;
  }
  if n == 0 {
    return false;
  }
  let b0 = string.byte_at(w, 0);
  if b0 == _PGN_UPPER_O {
    return _is_castling_body(w, n);
  }
  if _is_piece(b0) {
    if _piece_tail_ok(w, n, 1) {
      return true;
    }
    if n > 1 && _is_file(string.byte_at(w, 1)) && _piece_tail_ok(w, n, 2) {
      return true;
    }
    if n > 1 && _is_rank(string.byte_at(w, 1)) && _piece_tail_ok(w, n, 2) {
      return true;
    }
    if n > 2 && _is_file(string.byte_at(w, 1)) && _is_rank(string.byte_at(w, 2)) && _piece_tail_ok(w, n, 3) {
      return true;
    }
    return false;
  }
  if _is_file(b0) {
    var i = 1;
    if i < n && string.byte_at(w, i) == _PGN_X {
      i = i + 1;
      if i + 1 >= n {
        return false;
      }
      if !_is_file(string.byte_at(w, i)) {
        return false;
      }
      if !_is_rank(string.byte_at(w, i + 1)) {
        return false;
      }
      i = i + 2;
    } else {
      if i >= n {
        return false;
      }
      if !_is_rank(string.byte_at(w, i)) {
        return false;
      }
      i = i + 1;
    }
    if i < n {
      if string.byte_at(w, i) != _PGN_EQ {
        return false;
      }
      i = i + 1;
      if i >= n {
        return false;
      }
      if !_is_promo_piece(string.byte_at(w, i)) {
        return false;
      }
      i = i + 1;
    }
    return i == n;
  }
  return false;
}

// --------------------------------------------------
//  Tag-section parsing
// --------------------------------------------------

// Parse one tag pair starting at the "[" at `start` and append it to `tags`.
// Returns the position just after the closing "]" or the "pgn: ..." error.
// A tag pair must close on the same physical line it opened on.
fn _parse_tag_pair(text: Str, start: Int, tags: &mut TagList) -> Result[Int, Str] {
  let n = text.len();
  var i = start + 1;
  while i < n && _is_space_tab(string.byte_at(text, i)) {
    i = i + 1;
  }
  let name_start = i;
  while i < n && _is_tag_name_byte(string.byte_at(text, i)) {
    i = i + 1;
  }
  if i == name_start {
    return _err_pos(_at("pgn: bad tag name at ", name_start));
  }
  let name = string.str_slice(text, name_start, i);
  if i >= n || !_is_space_tab(string.byte_at(text, i)) {
    return _err_pos(_at("pgn: missing tag value at ", i));
  }
  while i < n && _is_space_tab(string.byte_at(text, i)) {
    i = i + 1;
  }
  if i >= n || string.byte_at(text, i) != _PGN_DQUOTE {
    return _err_pos(_at("pgn: missing tag value at ", i));
  }
  let quote_pos = i;
  i = i + 1;
  var sb = Vec[UInt8].new();
  var closed = false;
  while i < n {
    let c = string.byte_at(text, i);
    if c == _PGN_DQUOTE {
      closed = true;
      i = i + 1;
      break;
    } elif c == _PGN_LF || c == _PGN_CR {
      return _err_pos(_at("pgn: unterminated quote at ", quote_pos));
    } elif c == _PGN_BACKSLASH {
      if i + 1 >= n {
        return _err_pos(_at("pgn: invalid escape at ", i));
      }
      let e = string.byte_at(text, i + 1);
      if e == _PGN_DQUOTE {
        sb.push(_PGN_DQUOTE);
        i = i + 2;
      } elif e == _PGN_BACKSLASH {
        sb.push(_PGN_BACKSLASH);
        i = i + 2;
      } else {
        return _err_pos(_at("pgn: invalid escape at ", i));
      }
    } else {
      sb.push(c);
      i = i + 1;
    }
  }
  if !closed {
    return _err_pos(_at("pgn: unterminated quote at ", quote_pos));
  }
  while i < n && _is_space_tab(string.byte_at(text, i)) {
    i = i + 1;
  }
  if i >= n || string.byte_at(text, i) == _PGN_LF || string.byte_at(text, i) == _PGN_CR {
    return _err_pos(_at("pgn: unterminated tag at ", start));
  }
  if string.byte_at(text, i) != _PGN_RBRACKET {
    return _err_pos(_at("pgn: stray character at ", i));
  }
  let value = builder.sb_to_str(&sb);
  tags.names.push(name);
  tags.values.push(value);
  return _ok_pos(i + 1);
}

// --------------------------------------------------
//  Movetext parsing
// --------------------------------------------------

// Parse the movetext starting at `start` (after the tag section) into a flat
// token stream. Validation performed here: move-number sequence, SAN lexical
// form, NAG shape, result-token shape, and "only comments after the result".
fn _parse_movetext(text: Str, start: Int) -> Result[MoveText, Str] {
  var kinds = Vec[Str].new();
  var texts = Vec[Str].new();
  var starts = Vec[Int].new();
  let n = text.len();
  var i = start;
  var last_num: Int = 0;
  var seen_num = false;
  var saw_result = false;
  while i < n {
    let b = string.byte_at(text, i);
    if _is_ws(b) {
      i = i + 1;
    } elif b == _PGN_LBRACE {
      let open = i;
      var j = i + 1;
      var closed = false;
      while j < n {
        if string.byte_at(text, j) == _PGN_RBRACE {
          closed = true;
          break;
        }
        j = j + 1;
      }
      if !closed {
        return _err_moves(_at("pgn: unterminated comment at ", open));
      }
      kinds.push("comment");
      texts.push(string.str_slice(text, open + 1, j));
      starts.push(open);
      i = j + 1;
    } elif b == _PGN_SEMI {
      let end = _skip_to_eol(text, i + 1);
      kinds.push("comment_line");
      texts.push(string.str_slice(text, i + 1, end));
      starts.push(i);
      i = end;
    } elif b == _PGN_DOLLAR {
      if saw_result {
        return _err_moves(_at("pgn: token after result at ", i));
      }
      var j = i + 1;
      while j < n && _is_digit(string.byte_at(text, j)) {
        j = j + 1;
      }
      if j == i + 1 {
        return _err_moves(_at("pgn: bad nag at ", i));
      }
      kinds.push("nag");
      texts.push(string.str_slice(text, i + 1, j));
      starts.push(i);
      i = j;
    } elif b == _PGN_LPAREN || b == _PGN_RPAREN {
      return _err_moves(_at("pgn: unsupported variation at ", i));
    } elif b == _PGN_PERCENT {
      i = _skip_to_eol(text, i + 1);
    } elif b == _PGN_STAR {
      if saw_result {
        return _err_moves(_at("pgn: token after result at ", i));
      }
      kinds.push("result");
      texts.push("*");
      starts.push(i);
      saw_result = true;
      i = i + 1;
    } elif _is_digit(b) {
      if saw_result {
        return _err_moves(_at("pgn: token after result at ", i));
      }
      let tok_start = i;
      var j = i;
      while j < n && _is_digit(string.byte_at(text, j)) {
        j = j + 1;
      }
      let digits = string.str_slice(text, tok_start, j);
      var result_len: Int = 0;
      if compare.str_compare(digits, "1") == 0 && j + 2 <= n && compare.str_compare(string.str_slice(text, j, j + 2), "-0") == 0 {
        result_len = 2;
      } elif compare.str_compare(digits, "0") == 0 && j + 2 <= n && compare.str_compare(string.str_slice(text, j, j + 2), "-1") == 0 {
        result_len = 2;
      } elif compare.str_compare(digits, "1") == 0 && j + 6 <= n && compare.str_compare(string.str_slice(text, j, j + 6), "/2-1/2") == 0 {
        result_len = 6;
      }
      if result_len > 0 {
        kinds.push("result");
        texts.push(string.str_slice(text, tok_start, j + result_len));
        starts.push(tok_start);
        saw_result = true;
        i = j + result_len;
      } elif j < n && (string.byte_at(text, j) == _PGN_DASH || string.byte_at(text, j) == _PGN_SLASH) {
        return _err_moves(_at("pgn: illegal result token at ", tok_start));
      } elif j < n && string.byte_at(text, j) == _PGN_DOT {
        var k = j;
        while k < n && string.byte_at(text, k) == _PGN_DOT {
          k = k + 1;
        }
        let dots = k - j;
        if dots != 1 && dots != 3 {
          return _err_moves(_at("pgn: bad move number at ", tok_start));
        }
        let val = _digits_to_int(digits);
        var seq_bad = false;
        if !seen_num {
          if dots != 1 || val != 1 {
            seq_bad = true;
          }
        } elif dots == 3 {
          if val != last_num {
            seq_bad = true;
          }
        } elif val != last_num + 1 {
          seq_bad = true;
        }
        if seq_bad {
          return _err_moves(_at("pgn: bad move number sequence at ", tok_start));
        }
        var num_text: Str = digits;
        if dots == 1 {
          num_text = digits + ".";
        } else {
          num_text = digits + "...";
        }
        kinds.push("num");
        texts.push(num_text);
        starts.push(tok_start);
        last_num = val;
        seen_num = true;
        i = k;
      } else {
        return _err_moves(_at("pgn: bad move number at ", tok_start));
      }
    } else {
      var j = i;
      while j < n && !_is_word_delim(string.byte_at(text, j)) {
        j = j + 1;
      }
      if j == i {
        return _err_moves(_at("pgn: stray character at ", i));
      }
      let w = string.str_slice(text, i, j);
      if !_is_san_start(b) {
        return _err_moves(_at("pgn: stray character at ", i));
      }
      if !_san_valid(w) {
        return _err_moves("pgn: illegal san token '" + w + "' at " + int_to_string(i));
      }
      if saw_result {
        return _err_moves(_at("pgn: token after result at ", i));
      }
      kinds.push("san");
      texts.push(w);
      starts.push(i);
      i = j;
    }
  }
  return _ok_moves(MoveText{
    kinds: kinds;
    texts: texts;
    starts: starts;
  });
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one in-memory PGN game.
/// Params: text - the whole document (tags first, then movetext; LF, CRLF or
/// lone CR line endings).
/// Returns: Ok(Game) with the tag list and the flat movetext token stream, or
/// Err with a fixed "pgn: ..." message from the SPEC.md catalog. Tag values
/// decode `\"` and `\\`; comments are preserved verbatim as "comment" (brace)
/// and "comment_line" (semicolon) tokens; move numbers, NAGs, SAN tokens and
/// result tokens are validated lexically.
/// Complexity: O(input length).
pub fn pgn_parse(text: Str) -> Result[Game, Str] {
  var tags = TagList{ names: Vec[Str].new(); values: Vec[Str].new(); };
  let n = text.len();
  var i = 0;
  var scanning_tags = true;
  while i < n && scanning_tags {
    let b = string.byte_at(text, i);
    if _is_ws(b) {
      i = i + 1;
    } elif b == _PGN_PERCENT {
      i = _skip_to_eol(text, i + 1);
    } elif b == _PGN_LBRACKET {
      let r = _parse_tag_pair(text, i, &mut tags);
      match r {
        Ok(next) => { i = next; },
        Err(e) => { return _err_game(e); },
      }
    } else {
      scanning_tags = false;
    }
  }
  let mr = _parse_movetext(text, i);
  match mr {
    Ok(moves) => {
      return _ok_game(Game{ tags: tags; moves: moves; });
    },
    Err(e) => { return _err_game(e); },
  }
  return _err_game("pgn: unreachable");
}

/// Canonical emit: every tag pair on its own `[Name "value"]` line, one blank
/// line after a non-empty tag section, then the movetext tokens joined with
/// single spaces and a trailing newline. A semicolon comment forces the next
/// token onto a new line (otherwise it would be swallowed by the comment).
/// Values are re-escaped (`"` -> `\"`, `\` -> `\\`); everything else is
/// emitted verbatim, so warn-and-rotate files become single-line movetext.
/// Params: g - the game to serialize.
/// Returns: the canonical text; "" for an empty game.
/// Error case: none.
/// Complexity: O(output length).
pub fn pgn_emit(g: &Game) -> Str {
  var sb = Vec[UInt8].new();
  let tag_count = g.tags.names.len();
  var i = 0;
  while i < tag_count {
    sb.push(_PGN_LBRACKET);
    let name: Str = g.tags.names[i];
    _push_str(&mut sb, name);
    sb.push(_PGN_SPACE);
    sb.push(_PGN_DQUOTE);
    let value: Str = g.tags.values[i];
    _push_escaped(&mut sb, value);
    sb.push(_PGN_DQUOTE);
    sb.push(_PGN_RBRACKET);
    sb.push(_PGN_LF);
    i = i + 1;
  }
  if tag_count > 0 {
    sb.push(_PGN_LF);
  }
  let move_count = g.moves.kinds.len();
  i = 0;
  var prev_line_comment = false;
  while i < move_count {
    if i > 0 {
      if prev_line_comment {
        sb.push(_PGN_LF);
      } else {
        sb.push(_PGN_SPACE);
      }
    }
    let kind: Str = g.moves.kinds[i];
    let token: Str = g.moves.texts[i];
    if compare.str_compare(kind, "comment") == 0 {
      sb.push(_PGN_LBRACE);
      _push_str(&mut sb, token);
      sb.push(_PGN_RBRACE);
      prev_line_comment = false;
    } elif compare.str_compare(kind, "comment_line") == 0 {
      sb.push(_PGN_SEMI);
      _push_str(&mut sb, token);
      prev_line_comment = true;
    } elif compare.str_compare(kind, "nag") == 0 {
      sb.push(_PGN_DOLLAR);
      _push_str(&mut sb, token);
      prev_line_comment = false;
    } else {
      _push_str(&mut sb, token);
      prev_line_comment = false;
    }
    i = i + 1;
  }
  if move_count > 0 {
    sb.push(_PGN_LF);
  }
  return builder.sb_to_str(&sb);
}

// Append every byte of `s` to `sb`.
fn _push_str(sb: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    sb.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Append `s` with `"` and `\` escaped for a tag value.
fn _push_escaped(sb: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _PGN_DQUOTE || b == _PGN_BACKSLASH {
      sb.push(_PGN_BACKSLASH);
    }
    sb.push(b);
    i = i + 1;
  }
}

/// Number of tag pairs in `t` (duplicates counted).
/// Params: t - the tag list.
/// Returns: the tag count; 0 for an empty list.
/// Error case: none.
/// Complexity: O(1).
pub fn pgn_tag_count(t: &TagList) -> Int {
  return t.names.len();
}

/// Name of tag pair `i`, exactly as written.
/// Params: t - the tag list; i - the zero-based pair index.
/// Returns: the tag name; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn pgn_tag_name(t: &TagList, i: Int) -> Str {
  if i < 0 || i >= t.names.len() {
    return "";
  }
  let s: Str = t.names[i];
  return s;
}

/// Value of tag pair `i` with `\"` and `\\` already decoded.
/// Params: t - the tag list; i - the zero-based pair index.
/// Returns: the tag value; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn pgn_tag_value(t: &TagList, i: Int) -> Str {
  if i < 0 || i >= t.values.len() {
    return "";
  }
  let s: Str = t.values[i];
  return s;
}

/// First value of the tag named `name`, compared byte-exactly (PGN tag names
/// are case-sensitive); None when the tag is absent.
/// Params: t - the tag list; name - the exact tag name to look for.
/// Returns: Some(value) for the first match in document order, else None.
/// Error case: none.
/// Complexity: O(tag count).
pub fn pgn_tag_of(t: &TagList, name: Str) -> Option[Str] {
  var i = 0;
  while i < t.names.len() {
    let k: Str = t.names[i];
    if compare.str_compare(k, name) == 0 {
      let v: Str = t.values[i];
      return Some(v);
    }
    i = i + 1;
  }
  return None;
}

/// Number of movetext tokens (comments and result included).
/// Params: m - the movetext token stream.
/// Returns: the token count; 0 for an empty stream.
/// Error case: none.
/// Complexity: O(1).
pub fn pgn_move_count(m: &MoveText) -> Int {
  return m.kinds.len();
}

/// Kind of movetext token `i`: "num", "san", "comment", "comment_line", "nag"
/// or "result".
/// Params: m - the movetext token stream; i - the zero-based token index.
/// Returns: the kind; "" when `i` is negative or out of range. (A comment can
/// legitimately have empty text, so use the kind or the count to tell an
/// empty comment apart from a missing token.)
/// Error case: none.
/// Complexity: O(1).
pub fn pgn_move_kind(m: &MoveText, i: Int) -> Str {
  if i < 0 || i >= m.kinds.len() {
    return "";
  }
  let s: Str = m.kinds[i];
  return s;
}

/// Text of movetext token `i`. Per kind: "num" is the canonical `N.` /
/// `N...`; "san" the move token; "comment" the bytes between the braces;
/// "comment_line" the bytes after the semicolon; "nag" the digits without
/// `$`; "result" the result token itself.
/// Params: m - the movetext token stream; i - the zero-based token index.
/// Returns: the token text; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn pgn_move_text(m: &MoveText, i: Int) -> Str {
  if i < 0 || i >= m.texts.len() {
    return "";
  }
  let s: Str = m.texts[i];
  return s;
}

/// Byte offset of movetext token `i` in the parsed input (the `{` of a brace
/// comment, the `;` of a line comment, the `$` of a NAG, the first digit of a
/// move number or the first byte of an SAN/result token).
/// Params: m - the movetext token stream; i - the zero-based token index.
/// Returns: the offset; -1 when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn pgn_move_start(m: &MoveText, i: Int) -> Int {
  if i < 0 || i >= m.starts.len() {
    return -1;
  }
  let s: Int = m.starts[i];
  return s;
}

/// The game's result token text -- one of "1-0", "0-1", "1/2-1/2" or "*" --
/// or "" when the movetext carries no result token.
/// Params: m - the movetext token stream.
/// Returns: the first "result" token's text, else "".
/// Error case: none.
/// Complexity: O(token count).
pub fn pgn_result(m: &MoveText) -> Str {
  var i = 0;
  while i < m.kinds.len() {
    let k: Str = m.kinds[i];
    if compare.str_compare(k, "result") == 0 {
      let v: Str = m.texts[i];
      return v;
    }
    i = i + 1;
  }
  return "";
}

/// Lexical SAN validation without a board: true when `s` is a castling token,
/// a piece move (with optional file/rank disambiguation and capture sign) or a
/// pawn move (with optional capture file and `=` promotion), optionally
/// suffixed by "+" or "#". No legality, disambiguation-correctness or
/// check/mate verification is performed.
/// Params: s - the candidate token.
/// Returns: true when `s` matches the lexical SAN grammar.
/// Error case: none.
/// Complexity: O(|s|).
pub fn pgn_is_san(s: Str) -> Bool {
  return _san_valid(s);
}
