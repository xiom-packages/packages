// XIOM -- xiom.ntriples: RDF N-Triples codec (parse, access, canonical emit)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM codec for RDF 1.1 N-Triples (https://www.w3.org/TR/n-triples/):
//
//   * nt_parse  -- document text -> Result[NtDocument, Str], where a document
//     is a flat triple list stored as parallel Vecs (one slot per triple):
//     subject kind/text, predicate text, object kind/text, language tag,
//     datatype IRI and a literal-flavor flag. XIOM v0.61.3 cannot hold
//     Vec[StructType], so there is no Vec[Triple].
//   * nt_emit   -- stable canonical text: one triple per line, single spaces,
//     comments stripped, uppercase hex in every \uXXXX/\UXXXXXXXX escape.
//   * accessors -- nt_triple_count and per-triple term readers.
//
// Documented subset (see SPEC.md for the exact grammar, escape table, error
// catalog and test matrix):
//   * subject   = IRIREF | BLANK_NODE_LABEL
//   * predicate = IRIREF
//   * object    = IRIREF | BLANK_NODE_LABEL | STRING_LITERAL_QUOTE, where the
//     literal may be followed by LANGTAG or "^^" IRIREF;
//   * IRIREF escapes: only UCHAR (\uXXXX, \UXXXXXXXX);
//   * literal escapes: \n \t \r \" \\ and UCHAR;
//   * blank node labels: ASCII subset [A-Za-z0-9_] + interior '-' and '.';
//   * line ends: any run of LF and/or CR (so LF, CRLF and CR documents);
//   * comments: '#' outside an IRI or literal, to end of line.
//
// Non-goals: prefixed names and every other Turtle feature, RDF semantics or
// blank-node scoping, Unicode normalization, relative-IRI resolution, IRI
// validity beyond the IRIREF character set, streaming.
//
// Language notes (XIOM v0.61.3):
//   * Free functions only; byte-wise scanning over the input Str.
//   * Str values read from Vec[Str] elements are compared with
//     xiom.string.compare.str_compare (BUG 17: `==` on such elements lowers to
//     a pointer comparison) and are bound to typed locals before use.
//   * Ok/Err for Result[NtDocument, Str] are constructed only in the leaf
//     helpers _ok_doc/_err_doc (direct Result construction in other shapes
//     miscompiles).
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str (one allocation per result Str).
//   * No Vec[Float64], no Vec[StructType], no methods, no lambdas.

module xiom.ntriples

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Term containers
// --------------------------------------------------

// A parsed N-Triples document: one entry per triple, stored as parallel
// vectors (XIOM v0.61.3 cannot hold Vec[StructType]). Triple i is described
// by:
//   * s_kinds[i] / s_texts[i] -- subject ("iri" or "bnode") and its text: the
//     IRI text without the angle brackets, or the label without "_:";
//   * p_texts[i]              -- predicate IRI text (predicates are always
//     IRIs in N-Triples);
//   * o_kinds[i] / o_texts[i] -- object ("iri", "bnode" or "literal") and its
//     text: IRI text, label, or the literal's decoded lexical form;
//   * o_langs[i]              -- language tag of an @-tagged literal, else "";
//   * o_dts[i]                -- datatype IRI text of a ^^-tagged literal,
//     else "";
//   * o_flags[i]              -- literal flavor: 0 plain, 1 language-tagged,
//     2 datatype-tagged (o_dts[i] is "" for an explicit "^^<>").
// Treat the fields as read-only: build documents with nt_parse/nt_add_triple
// and read them with the nt_* accessors.
pub type NtDocument = {
  s_kinds: Vec[Str];
  s_texts: Vec[Str];
  p_texts: Vec[Str];
  o_kinds: Vec[Str];
  o_texts: Vec[Str];
  o_langs: Vec[Str];
  o_dts: Vec[Str];
  o_flags: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[NtDocument, Str].
fn _ok_doc(v: NtDocument) -> Result[NtDocument, Str] {
  return Ok(v);
}

// Err(m) for Result[NtDocument, Str].
fn _err_doc(m: Str) -> Result[NtDocument, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants and predicates
// --------------------------------------------------

const _NT_TAB: UInt8 = 9u8;
const _NT_LF: UInt8 = 10u8;
const _NT_CR: UInt8 = 13u8;
const _NT_SPACE: UInt8 = 32u8;
const _NT_DQUOTE: UInt8 = 34u8;
const _NT_HASH: UInt8 = 35u8;
const _NT_MINUS: UInt8 = 45u8;
const _NT_DOT: UInt8 = 46u8;
const _NT_COLON: UInt8 = 58u8;
const _NT_LT: UInt8 = 60u8;
const _NT_GT: UInt8 = 62u8;
const _NT_AT: UInt8 = 64u8;
const _NT_UPPER_U: UInt8 = 85u8;
const _NT_BACKSLASH: UInt8 = 92u8;
const _NT_CARET: UInt8 = 94u8;
const _NT_UNDERSCORE: UInt8 = 95u8;
const _NT_LOWER_N: UInt8 = 110u8;
const _NT_LOWER_R: UInt8 = 114u8;
const _NT_LOWER_T: UInt8 = 116u8;
const _NT_LOWER_U: UInt8 = 117u8;

// Separator whitespace inside a line: space or tab. CR and LF are line ends,
// never content.
fn _is_ws_byte(b: UInt8) -> Bool {
  return b == _NT_SPACE || b == _NT_TAB;
}

// Line-end byte: LF or CR (EOL is any run of them).
fn _is_eol_byte(b: UInt8) -> Bool {
  return b == _NT_LF || b == _NT_CR;
}

// ASCII digit byte: 0-9.
fn _is_digit_byte(b: UInt8) -> Bool {
  return b >= 48u8 && b <= 57u8;
}

// ASCII letter byte: A-Z or a-z.
fn _is_alpha_byte(b: UInt8) -> Bool {
  if b >= 65u8 && b <= 90u8 {
    return true;
  }
  return b >= 97u8 && b <= 122u8;
}

// ASCII letter-or-digit byte.
fn _is_alnum_byte(b: UInt8) -> Bool {
  if _is_alpha_byte(b) {
    return true;
  }
  return _is_digit_byte(b);
}

// First byte of a (subset) blank node label: [A-Za-z0-9_].
fn _is_label_start(b: UInt8) -> Bool {
  if _is_alnum_byte(b) {
    return true;
  }
  return b == _NT_UNDERSCORE;
}

// Continuation byte of a (subset) blank node label: [A-Za-z0-9_-.].
fn _is_label_byte(b: UInt8) -> Bool {
  if _is_label_start(b) {
    return true;
  }
  return b == _NT_MINUS || b == _NT_DOT;
}

// --------------------------------------------------
//  Hex and UTF-8 helpers
// --------------------------------------------------

// Numeric value of a hex digit byte (0-9, a-f, A-F); -1 for any other byte.
fn _hex_value(b: UInt8) -> Int {
  let c = (b as Int) & 0xFF;
  if c >= 48 && c <= 57 {
    return c - 48;
  }
  if c >= 97 && c <= 102 {
    return c - 87;
  }
  if c >= 65 && c <= 70 {
    return c - 55;
  }
  return -1;
}

// Uppercase hex digit byte for a nibble value (0-15).
fn _hex_upper(n: Int) -> UInt8 {
  if n < 10 {
    return (48 + n) as UInt8;
  }
  return (55 + n) as UInt8;
}

// True for a UTF-8 continuation byte (10xxxxxx).
fn _is_cont(b: Int) -> Bool {
  return (b & 0xC0) == 0x80;
}

// First byte offset of an ill-formed UTF-8 sequence in `text`, or -1 when the
// whole string is well-formed per RFC 3629 (rejects stray continuation bytes,
// truncated sequences, overlong forms, surrogates and > U+10FFFF).
fn _utf8_problem_at(text: Str) -> Int {
  let n = text.len();
  var i = 0;
  while i < n {
    let b0 = (string.byte_at(text, i) as Int) & 0xFF;
    if b0 <= 0x7F {
      i = i + 1;
    } elif b0 >= 0xC2 && b0 <= 0xDF {
      if i + 1 >= n {
        return i;
      }
      let b1 = (string.byte_at(text, i + 1) as Int) & 0xFF;
      if !_is_cont(b1) {
        return i;
      }
      i = i + 2;
    } elif b0 >= 0xE0 && b0 <= 0xEF {
      if i + 2 >= n {
        return i;
      }
      let b1 = (string.byte_at(text, i + 1) as Int) & 0xFF;
      let b2 = (string.byte_at(text, i + 2) as Int) & 0xFF;
      if !_is_cont(b1) || !_is_cont(b2) {
        return i;
      }
      if b0 == 0xE0 && b1 < 0xA0 {
        return i;
      }
      if b0 == 0xED && b1 >= 0xA0 {
        return i;
      }
      i = i + 3;
    } elif b0 >= 0xF0 && b0 <= 0xF4 {
      if i + 3 >= n {
        return i;
      }
      let b1 = (string.byte_at(text, i + 1) as Int) & 0xFF;
      let b2 = (string.byte_at(text, i + 2) as Int) & 0xFF;
      let b3 = (string.byte_at(text, i + 3) as Int) & 0xFF;
      if !_is_cont(b1) || !_is_cont(b2) || !_is_cont(b3) {
        return i;
      }
      if b0 == 0xF0 && b1 < 0x90 {
        return i;
      }
      if b0 == 0xF4 && b1 > 0x8F {
        return i;
      }
      i = i + 4;
    } else {
      return i;
    }
  }
  return -1;
}

// Append the UTF-8 encoding of `code` (a valid scalar value) to `out`.
fn _push_utf8(out: &mut Vec[UInt8], code: Int) {
  if code < 0x80 {
    out.push(code as UInt8);
    return;
  }
  if code < 0x800 {
    out.push((0xC0 + code / 64) as UInt8);
    out.push((0x80 + code % 64) as UInt8);
    return;
  }
  if code < 0x10000 {
    out.push((0xE0 + code / 4096) as UInt8);
    out.push((0x80 + (code / 64) % 64) as UInt8);
    out.push((0x80 + code % 64) as UInt8);
    return;
  }
  out.push((0xF0 + code / 262144) as UInt8);
  out.push((0x80 + (code / 4096) % 64) as UInt8);
  out.push((0x80 + (code / 64) % 64) as UInt8);
  out.push((0x80 + code % 64) as UInt8);
}

// --------------------------------------------------
//  Message and position helpers
// --------------------------------------------------

// "ntriples: <text> at <pos>"; the deterministic shape of every error.
fn _err_at(text: Str, pos: Int) -> Str {
  return "ntriples: " + text + " at " + int_to_string(pos);
}

// First index of LF or CR in [from, end), or `end` when there is none.
fn _find_eol(text: Str, from: Int, end: Int) -> Int {
  var i = from;
  while i < end {
    if _is_eol_byte(string.byte_at(text, i)) {
      return i;
    }
    i = i + 1;
  }
  return end;
}

// First index of [from, end) that is not space/tab.
fn _skip_ws(text: Str, from: Int, end: Int) -> Int {
  var i = from;
  while i < end && _is_ws_byte(string.byte_at(text, i)) {
    i = i + 1;
  }
  return i;
}

// True when the IRIREF character set forbids the code point `v`: the C0
// controls and space (#x00-#x20), '<', '>', '"', '{', '}', '|', '^', '`',
// and '\'.
fn _iri_code_forbidden(v: Int) -> Bool {
  if v <= 0x20 {
    return true;
  }
  if v == 0x3C || v == 0x3E || v == 0x22 {
    return true;
  }
  if v == 0x7B || v == 0x7D || v == 0x7C {
    return true;
  }
  if v == 0x5E || v == 0x60 || v == 0x5C {
    return true;
  }
  return false;
}

// Decode one UCHAR at `at` (the backslash; text[at+1] is 'u' or 'U') with
// `digits` = 4 or 8. Err("ntriples: bad escape at <at>") for a truncated or
// non-hex digit, a NUL code point (XIOM Str cannot carry NUL), a UTF-16
// surrogate (U+D800-U+DFFF) or a value above U+10FFFF.
fn _uchar_code(text: Str, at: Int, end: Int, digits: Int) -> Result[Int, Str] {
  let first = at + 2;
  if first + digits > end {
    return Err(_err_at("bad escape", at));
  }
  var code = 0;
  var k = 0;
  while k < digits {
    let hv = _hex_value(string.byte_at(text, first + k));
    if hv < 0 {
      return Err(_err_at("bad escape", at));
    }
    code = code * 16 + hv;
    k = k + 1;
  }
  if code == 0 {
    return Err(_err_at("bad escape", at));
  }
  if code >= 0xD800 && code <= 0xDFFF {
    return Err(_err_at("bad escape", at));
  }
  if code > 0x10FFFF {
    return Err(_err_at("bad escape", at));
  }
  return Ok(code);
}

// --------------------------------------------------
//  Term scanners
// --------------------------------------------------

// Scan an IRIREF starting at the '<' at `at`; append the decoded IRI text
// (escapes unescaped) to `out` and return the position after '>'.
// Err("ntriples: unterminated IRI at <at>") when the line ends first;
// Err("ntriples: missing '>' at <pos>") for a byte the IRIREF character set
// forbids, or for a UCHAR that decodes to such a character (pos = the byte /
// the backslash); Err("ntriples: bad escape at <pos>") for a backslash that
// does not start \uXXXX or \UXXXXXXXX.
fn _scan_iri(text: Str, at: Int, end: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  var j = at + 1;
  while j < end {
    let b = string.byte_at(text, j);
    let v = (b as Int) & 0xFF;
    if b == _NT_GT {
      return Ok(j + 1);
    }
    if b == _NT_BACKSLASH {
      if j + 1 >= end {
        return Err(_err_at("unterminated IRI", at));
      }
      let e = string.byte_at(text, j + 1);
      if e != _NT_LOWER_U && e != _NT_UPPER_U {
        return Err(_err_at("bad escape", j));
      }
      var digits = 4;
      if e == _NT_UPPER_U {
        digits = 8;
      }
      let r = _uchar_code(text, j, end, digits);
      match r {
        Ok(code) => {
          if _iri_code_forbidden(code) {
            return Err(_err_at("missing '>'", j));
          }
          _push_utf8(out, code);
          j = j + 2 + digits;
        },
        Err(msg) => { return Err(msg); },
      };
    } elif _iri_code_forbidden(v) {
      return Err(_err_at("missing '>'", j));
    } else {
      out.push(b);
      j = j + 1;
    }
  }
  return Err(_err_at("unterminated IRI", at));
}

// Scan a STRING_LITERAL_QUOTE starting at the '"' at `at`; append the decoded
// lexical form to `out` and return the position after the closing '"'.
// Err("ntriples: unterminated literal at <at>") when the line ends first
// (including a trailing backslash); Err("ntriples: bad escape at <pos>") for
// an unknown escape or a malformed UCHAR; Err("ntriples: raw control byte in
// literal at <pos>") for a raw C0 byte other than TAB.
fn _scan_literal(text: Str, at: Int, end: Int, out: &mut Vec[UInt8]) -> Result[Int, Str] {
  var j = at + 1;
  while j < end {
    let b = string.byte_at(text, j);
    if b == _NT_DQUOTE {
      return Ok(j + 1);
    }
    if b == _NT_BACKSLASH {
      if j + 1 >= end {
        return Err(_err_at("unterminated literal", at));
      }
      let e = string.byte_at(text, j + 1);
      if e == _NT_LOWER_N {
        out.push(_NT_LF);
        j = j + 2;
      } elif e == _NT_LOWER_T {
        out.push(_NT_TAB);
        j = j + 2;
      } elif e == _NT_LOWER_R {
        out.push(_NT_CR);
        j = j + 2;
      } elif e == _NT_DQUOTE {
        out.push(_NT_DQUOTE);
        j = j + 2;
      } elif e == _NT_BACKSLASH {
        out.push(_NT_BACKSLASH);
        j = j + 2;
      } elif e == _NT_LOWER_U || e == _NT_UPPER_U {
        var digits = 4;
        if e == _NT_UPPER_U {
          digits = 8;
        }
        let r = _uchar_code(text, j, end, digits);
        match r {
          Ok(code) => {
            _push_utf8(out, code);
            j = j + 2 + digits;
          },
          Err(msg) => { return Err(msg); },
        };
      } else {
        return Err(_err_at("bad escape", j));
      }
    } elif ((b as Int) & 0xFF) < 0x20 && b != _NT_TAB {
      return Err(_err_at("raw control byte in literal", j));
    } else {
      out.push(b);
      j = j + 1;
    }
  }
  return Err(_err_at("unterminated literal", at));
}

// Scan a blank node label after "_:", starting at the '_' at `at`; return the
// position after the label. A trailing '.' is not part of the label (it may be
// the triple terminator) and is handed back. Err("ntriples: invalid blank node
// label at <at>") when the label is empty or contains a byte outside the
// documented ASCII subset.
fn _scan_bnode_label(text: Str, at: Int, end: Int) -> Result[Int, Str] {
  if at + 2 >= end {
    return Err(_err_at("invalid blank node label", at));
  }
  let b0 = string.byte_at(text, at + 2);
  if !_is_label_start(b0) {
    return Err(_err_at("invalid blank node label", at));
  }
  var j = at + 2;
  while j < end && _is_label_byte(string.byte_at(text, j)) {
    j = j + 1;
  }
  while j > at + 3 && string.byte_at(text, j - 1) == _NT_DOT {
    j = j - 1;
  }
  return Ok(j);
}

// Scan a LANGTAG after the '@' at `at`; return the position after the tag.
// The tag must match [a-zA-Z]+ ('-' [a-zA-Z0-9]+)* and end at a terminator
// (space, tab, '.', '#', or end of line). Err("ntriples: bad language tag at
// <at>") otherwise.
fn _scan_langtag(text: Str, at: Int, end: Int) -> Result[Int, Str] {
  var j = at + 1;
  let first_start = j;
  while j < end && _is_alpha_byte(string.byte_at(text, j)) {
    j = j + 1;
  }
  if j == first_start {
    return Err(_err_at("bad language tag", at));
  }
  while j < end && string.byte_at(text, j) == _NT_MINUS {
    j = j + 1;
    let sub_start = j;
    while j < end && _is_alnum_byte(string.byte_at(text, j)) {
      j = j + 1;
    }
    if j == sub_start {
      return Err(_err_at("bad language tag", at));
    }
  }
  if j < end {
    let t = string.byte_at(text, j);
    if !_is_ws_byte(t) && t != _NT_DOT && t != _NT_HASH {
      return Err(_err_at("bad language tag", at));
    }
  }
  return Ok(j);
}

// True when a term starts at `at`: IRIREF, blank node label, or literal.
fn _starts_term(text: Str, at: Int, end: Int) -> Bool {
  if at >= end {
    return false;
  }
  let b = string.byte_at(text, at);
  if b == _NT_LT || b == _NT_DQUOTE {
    return true;
  }
  if b == _NT_UNDERSCORE && at + 1 < end && string.byte_at(text, at + 1) == _NT_COLON {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Line parser
// --------------------------------------------------

// Parse one line [start, end) (line terminators excluded) and, on success,
// append one triple to `d`. Returns Ok(the position after the trailing '.')
// or Err(the first error). A line that is empty, whitespace-only, or a
// comment is Ok and appends nothing.
fn _parse_line(d: &mut NtDocument, text: Str, start: Int, end: Int) -> Result[Int, Str] {
  var i = _skip_ws(text, start, end);
  if i >= end {
    return Ok(i);
  }
  if string.byte_at(text, i) == _NT_HASH {
    return Ok(i);
  }

  // Subject: IRIREF or blank node label.
  var s_kind = "";
  var s_text = "";
  if string.byte_at(text, i) == _NT_LT {
    var s_buf = Vec[UInt8].new();
    let r = _scan_iri(text, i, end, &mut s_buf);
    match r {
      Ok(j) => { s_kind = "iri"; s_text = Str::from_utf8(s_buf); i = j; },
      Err(e) => { return Err(e); },
    };
  } elif string.byte_at(text, i) == _NT_UNDERSCORE && i + 1 < end && string.byte_at(text, i + 1) == _NT_COLON {
    let r = _scan_bnode_label(text, i, end);
    match r {
      Ok(j) => { s_kind = "bnode"; s_text = string.str_slice(text, i + 2, j); i = j; },
      Err(e) => { return Err(e); },
    };
  } else {
    return Err(_err_at("unexpected byte", i));
  }

  // Predicate: an IRIREF is mandatory.
  i = _skip_ws(text, i, end);
  if i >= end {
    return Err(_err_at("unexpected end of line", end));
  }
  if string.byte_at(text, i) != _NT_LT {
    return Err(_err_at("missing '<'", i));
  }
  var p_text = "";
  var p_buf = Vec[UInt8].new();
  let rp = _scan_iri(text, i, end, &mut p_buf);
  match rp {
    Ok(j) => { p_text = Str::from_utf8(p_buf); i = j; },
    Err(e) => { return Err(e); },
  };

  // Object: IRIREF, blank node label or literal (with optional suffix).
  i = _skip_ws(text, i, end);
  if i >= end {
    return Err(_err_at("unexpected end of line", end));
  }
  var o_kind = "";
  var o_text = "";
  var o_lang = "";
  var o_dt = "";
  var o_flag = 0;
  let ob = string.byte_at(text, i);
  if ob == _NT_LT {
    var o_buf = Vec[UInt8].new();
    let r = _scan_iri(text, i, end, &mut o_buf);
    match r {
      Ok(j) => { o_kind = "iri"; o_text = Str::from_utf8(o_buf); i = j; },
      Err(e) => { return Err(e); },
    };
  } elif ob == _NT_UNDERSCORE && i + 1 < end && string.byte_at(text, i + 1) == _NT_COLON {
    let r = _scan_bnode_label(text, i, end);
    match r {
      Ok(j) => { o_kind = "bnode"; o_text = string.str_slice(text, i + 2, j); i = j; },
      Err(e) => { return Err(e); },
    };
  } elif ob == _NT_DQUOTE {
    var o_buf = Vec[UInt8].new();
    let r = _scan_literal(text, i, end, &mut o_buf);
    match r {
      Ok(j) => { o_kind = "literal"; o_text = Str::from_utf8(o_buf); i = j; },
      Err(e) => { return Err(e); },
    };
    // "@lang" or "^^<datatype>" must follow the closing quote immediately.
    if i < end && string.byte_at(text, i) == _NT_AT {
      let rl = _scan_langtag(text, i, end);
      match rl {
        Ok(j) => { o_lang = string.str_slice(text, i + 1, j); o_flag = 1; i = j; },
        Err(e) => { return Err(e); },
      };
    } elif i + 1 < end && string.byte_at(text, i) == _NT_CARET && string.byte_at(text, i + 1) == _NT_CARET {
      let dt_at = i + 2;
      if dt_at >= end || string.byte_at(text, dt_at) != _NT_LT {
        return Err(_err_at("missing '<'", dt_at));
      }
      var dt_buf = Vec[UInt8].new();
      let rd = _scan_iri(text, dt_at, end, &mut dt_buf);
      match rd {
        Ok(j) => { o_dt = Str::from_utf8(dt_buf); o_flag = 2; i = j; },
        Err(e) => { return Err(e); },
      };
    }
  } else {
    return Err(_err_at("unexpected byte", i));
  }

  // Terminator '.'.
  i = _skip_ws(text, i, end);
  if i >= end {
    return Err(_err_at("missing '.'", end));
  }
  if string.byte_at(text, i) != _NT_DOT {
    if _starts_term(text, i, end) {
      return Err(_err_at("extra term", i));
    }
    return Err(_err_at("missing '.'", i));
  }
  i = i + 1;

  // Only whitespace and a trailing comment may follow the dot.
  i = _skip_ws(text, i, end);
  if i < end && string.byte_at(text, i) != _NT_HASH {
    return Err(_err_at("unexpected byte", i));
  }

  d.s_kinds.push(s_kind);
  d.s_texts.push(s_text);
  d.p_texts.push(p_text);
  d.o_kinds.push(o_kind);
  d.o_texts.push(o_text);
  d.o_langs.push(o_lang);
  d.o_dts.push(o_dt);
  d.o_flags.push(o_flag);
  return Ok(i);
}

// --------------------------------------------------
//  Document construction
// --------------------------------------------------

/// An empty document (zero triples).
/// Params: none.
/// Returns: a document with all eight parallel vectors empty.
/// Error case: none.
/// Complexity: O(1).
pub fn nt_new() -> NtDocument {
  return NtDocument{
    s_kinds: Vec[Str].new();
    s_texts: Vec[Str].new();
    p_texts: Vec[Str].new();
    o_kinds: Vec[Str].new();
    o_texts: Vec[Str].new();
    o_langs: Vec[Str].new();
    o_dts: Vec[Str].new();
    o_flags: Vec[Int].new();
  };
}

/// Append one triple to `d` without parsing.
/// Params: d - the document to mutate; s_kind - "iri" or "bnode"; s_text -
/// subject IRI text or blank node label; p_text - predicate IRI text; o_kind -
/// "iri", "bnode" or "literal"; o_text - object IRI text, label, or literal
/// lexical form; o_lang - language tag for a language-tagged literal, else "";
/// o_dt - datatype IRI text for a datatype-tagged literal, else "".
/// Returns: true when the triple was appended.
/// Error case: none -- returns false and mutates nothing when a kind is
/// unknown, when a non-literal carries a language tag or datatype, when a
/// literal carries both, when a language tag does not match
/// [a-zA-Z]+('-'[a-zA-Z0-9]+)*, or when a blank node label is outside
/// [A-Za-z0-9_][A-Za-z0-9_.-]* (not ending in '.'). An empty `o_dt` with
/// `o_kind` = "literal" means a plain literal; the explicit "^^<>" state can
/// only arise from nt_parse.
/// Complexity: O(1) amortized.
pub fn nt_add_triple(d: &mut NtDocument, s_kind: Str, s_text: Str, p_text: Str, o_kind: Str, o_text: Str, o_lang: Str, o_dt: Str) -> Bool {
  let s_iri = compare.str_compare(s_kind, "iri") == 0;
  let s_bnode = compare.str_compare(s_kind, "bnode") == 0;
  if !s_iri && !s_bnode {
    return false;
  }
  let o_iri = compare.str_compare(o_kind, "iri") == 0;
  let o_bnode = compare.str_compare(o_kind, "bnode") == 0;
  let o_literal = compare.str_compare(o_kind, "literal") == 0;
  if !o_iri && !o_bnode && !o_literal {
    return false;
  }
  if s_bnode && !_bnode_label_ok(s_text) {
    return false;
  }
  if o_bnode && !_bnode_label_ok(o_text) {
    return false;
  }
  let lang_len = o_lang.len();
  let dt_len = o_dt.len();
  var flag = 0;
  if o_literal {
    if lang_len > 0 && dt_len > 0 {
      return false;
    }
    if lang_len > 0 {
      if !_langtag_ok(o_lang) {
        return false;
      }
      flag = 1;
    } elif dt_len > 0 {
      flag = 2;
    }
  } else {
    if lang_len > 0 || dt_len > 0 {
      return false;
    }
  }
  d.s_kinds.push(s_kind);
  d.s_texts.push(s_text);
  d.p_texts.push(p_text);
  d.o_kinds.push(o_kind);
  d.o_texts.push(o_text);
  d.o_langs.push(o_lang);
  d.o_dts.push(o_dt);
  d.o_flags.push(flag);
  return true;
}

/// Parse N-Triples document text.
/// Params: text - the full document; line ends are LF, CRLF or CR, and '#' 
/// outside an IRI or literal starts a comment to end of line.
/// Returns: Ok(NtDocument) with one flat triple entry per parsed line, in
/// document order; blank/comment-only lines contribute nothing.
/// Error case: Err("ntriples: ...") for the first error; positions are 0-based
/// byte offsets into `text`. See SPEC.md for the full catalog: invalid UTF-8
/// byte, unterminated IRI/literal, missing '<'/'>'/'.', bad escape (including
/// surrogate code points), bad language tag, invalid blank node label, raw
/// control byte in a literal, extra term, unexpected end of line, unexpected
/// byte.
/// Complexity: O(n) time and memory in the input size.
pub fn nt_parse(text: Str) -> Result[NtDocument, Str] {
  let bad = _utf8_problem_at(text);
  if bad >= 0 {
    return _err_doc(_err_at("invalid UTF-8 byte", bad));
  }
  var d = nt_new();
  let n = text.len();
  var pos = 0;
  while pos < n {
    let line_end = _find_eol(text, pos, n);
    let r = _parse_line(&mut d, text, pos, line_end);
    match r {
      Ok(_) => {
        var next = line_end;
        while next < n && _is_eol_byte(string.byte_at(text, next)) {
          next = next + 1;
        }
        pos = next;
      },
      Err(e) => { return _err_doc(e); },
    };
  }
  return _ok_doc(d);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of triples in `d`.
/// Params: d - the document.
/// Returns: the triple count; 0 for an empty document.
/// Error case: none.
/// Complexity: O(1).
pub fn nt_triple_count(d: &NtDocument) -> Int {
  return d.s_kinds.len();
}

/// Kind of the subject of triple `i`.
/// Params: d - the document; i - the zero-based triple index.
/// Returns: "iri" or "bnode"; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn nt_subject_kind(d: &NtDocument, i: Int) -> Str {
  if i < 0 || i >= d.s_kinds.len() {
    return "";
  }
  return d.s_kinds[i];
}

/// Text of the subject of triple `i`: the IRI text without angle brackets, or
/// the blank node label without "_:".
/// Params: d - the document; i - the zero-based triple index.
/// Returns: the term text; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn nt_subject_text(d: &NtDocument, i: Int) -> Str {
  if i < 0 || i >= d.s_texts.len() {
    return "";
  }
  return d.s_texts[i];
}

/// Predicate IRI text of triple `i` (predicates are always IRIs, so there is
/// no predicate kind accessor).
/// Params: d - the document; i - the zero-based triple index.
/// Returns: the IRI text without angle brackets; "" when `i` is negative or
/// out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn nt_predicate(d: &NtDocument, i: Int) -> Str {
  if i < 0 || i >= d.p_texts.len() {
    return "";
  }
  return d.p_texts[i];
}

/// Kind of the object of triple `i`.
/// Params: d - the document; i - the zero-based triple index.
/// Returns: "iri", "bnode" or "literal"; "" when `i` is negative or out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn nt_object_kind(d: &NtDocument, i: Int) -> Str {
  if i < 0 || i >= d.o_kinds.len() {
    return "";
  }
  return d.o_kinds[i];
}

/// Text of the object of triple `i`: the IRI text without angle brackets, the
/// blank node label without "_:", or the literal lexical form with all escape
/// sequences decoded.
/// Params: d - the document; i - the zero-based triple index.
/// Returns: the term text; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn nt_object_text(d: &NtDocument, i: Int) -> Str {
  if i < 0 || i >= d.o_texts.len() {
    return "";
  }
  return d.o_texts[i];
}

/// Language tag of the object of triple `i`.
/// Params: d - the document; i - the zero-based triple index.
/// Returns: the tag text, preserved exactly as written (no case folding);
/// "" for a non-literal object, a plain literal, a datatype-tagged literal,
/// or an out-of-range index.
/// Error case: none.
/// Complexity: O(1).
pub fn nt_object_lang(d: &NtDocument, i: Int) -> Str {
  if i < 0 || i >= d.o_langs.len() {
    return "";
  }
  return d.o_langs[i];
}

/// Datatype IRI text of the object of triple `i`.
/// Params: d - the document; i - the zero-based triple index.
/// Returns: the datatype IRI text without angle brackets; "" for a non-literal
/// object, a plain or language-tagged literal, an explicit empty datatype
/// ("^^<>", reported as typed by nt_object_has_datatype), or an out-of-range
/// index.
/// Error case: none.
/// Complexity: O(1).
pub fn nt_object_datatype(d: &NtDocument, i: Int) -> Str {
  if i < 0 || i >= d.o_dts.len() {
    return "";
  }
  return d.o_dts[i];
}

/// True when the object of triple `i` is a datatype-tagged literal.
/// Params: d - the document; i - the zero-based triple index.
/// Returns: true only for a literal with a "^^" suffix, including the explicit
/// empty datatype "^^<>"; false otherwise and for out-of-range indices.
/// Error case: none.
/// Complexity: O(1).
pub fn nt_object_has_datatype(d: &NtDocument, i: Int) -> Bool {
  if i < 0 || i >= d.o_flags.len() {
    return false;
  }
  let f: Int = d.o_flags[i];
  return f == 2;
}

// --------------------------------------------------
//  Emitter
// --------------------------------------------------

// Append "\uXXXX" (or "\UXXXXXXXX" above the BMP) for `code`, uppercase hex.
fn _emit_uchar(sb: &mut Vec[UInt8], code: Int) {
  if code <= 0xFFFF {
    builder.sb_push_str(sb, "\\u");
    sb.push(_hex_upper((code >> 12) & 15));
    sb.push(_hex_upper((code >> 8) & 15));
    sb.push(_hex_upper((code >> 4) & 15));
    sb.push(_hex_upper(code & 15));
    return;
  }
  builder.sb_push_str(sb, "\\U");
  sb.push(_hex_upper((code >> 28) & 15));
  sb.push(_hex_upper((code >> 24) & 15));
  sb.push(_hex_upper((code >> 20) & 15));
  sb.push(_hex_upper((code >> 16) & 15));
  sb.push(_hex_upper((code >> 12) & 15));
  sb.push(_hex_upper((code >> 8) & 15));
  sb.push(_hex_upper((code >> 4) & 15));
  sb.push(_hex_upper(code & 15));
}

// Append "<" + IRI text + ">". Bytes the IRIREF character set forbids are
// written as \uXXXX/\UXXXXXXXX with uppercase hex; all other bytes (including
// raw multi-byte UTF-8) pass through.
fn _emit_iri(sb: &mut Vec[UInt8], iri: Str) {
  sb.push(_NT_LT);
  let n = iri.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(iri, i);
    let v = (b as Int) & 0xFF;
    if _iri_code_forbidden(v) {
      _emit_uchar(sb, v);
    } else {
      sb.push(b);
    }
    i = i + 1;
  }
  sb.push(_NT_GT);
}

// Append "_:" + label.
fn _emit_bnode(sb: &mut Vec[UInt8], label: Str) {
  sb.push(_NT_UNDERSCORE);
  sb.push(_NT_COLON);
  builder.sb_push_str(sb, label);
}

// Append a literal: quoted lexical form, then "@lang" (flag 1) or
// "^^<datatype>" (flag 2). Canonical escaping: '\\' '"' LF CR TAB use their
// short escapes, other bytes below 0x20 use \u00XX with uppercase hex, and
// everything else (including raw UTF-8) passes through.
fn _emit_literal(sb: &mut Vec[UInt8], text: Str, lang: Str, dt: Str, flag: Int) {
  sb.push(_NT_DQUOTE);
  let n = text.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(text, i);
    let v = (b as Int) & 0xFF;
    if v == 0x5C {
      builder.sb_push_str(sb, "\\\\");
    } elif v == 0x22 {
      builder.sb_push_str(sb, "\\\"");
    } elif v == 0x0A {
      builder.sb_push_str(sb, "\\n");
    } elif v == 0x0D {
      builder.sb_push_str(sb, "\\r");
    } elif v == 0x09 {
      builder.sb_push_str(sb, "\\t");
    } elif v < 0x20 {
      _emit_uchar(sb, v);
    } else {
      sb.push(b);
    }
    i = i + 1;
  }
  sb.push(_NT_DQUOTE);
  if flag == 1 {
    sb.push(_NT_AT);
    builder.sb_push_str(sb, lang);
  } elif flag == 2 {
    sb.push(_NT_CARET);
    sb.push(_NT_CARET);
    _emit_iri(sb, dt);
  }
}

/// Emit a document as canonical N-Triples text.
/// Params: d - the document.
/// Returns: one line per triple, "<subject> <predicate> <object> ." with a
/// single space after each term and a final LF after every line (so an empty
/// document emits ""). IRIs are escaped inside <>, literals are quoted with
/// canonical escapes, every hex digit in an escape is uppercase, and comments
/// are absent. Documents built by nt_parse reparse to an equal document.
/// Error case: none.
/// Complexity: O(total text length).
pub fn nt_emit(d: &NtDocument) -> Str {
  var sb = Vec[UInt8].new();
  let n = d.s_kinds.len();
  var i = 0;
  while i < n {
    let sk: Str = d.s_kinds[i];
    let st: Str = d.s_texts[i];
    if compare.str_compare(sk, "bnode") == 0 {
      _emit_bnode(&mut sb, st);
    } else {
      _emit_iri(&mut sb, st);
    }
    sb.push(_NT_SPACE);
    let pt: Str = d.p_texts[i];
    _emit_iri(&mut sb, pt);
    sb.push(_NT_SPACE);
    let okk: Str = d.o_kinds[i];
    let ot: Str = d.o_texts[i];
    if compare.str_compare(okk, "literal") == 0 {
      let ol: Str = d.o_langs[i];
      let od: Str = d.o_dts[i];
      let ofl: Int = d.o_flags[i];
      _emit_literal(&mut sb, ot, ol, od, ofl);
    } elif compare.str_compare(okk, "bnode") == 0 {
      _emit_bnode(&mut sb, ot);
    } else {
      _emit_iri(&mut sb, ot);
    }
    sb.push(_NT_SPACE);
    sb.push(_NT_DOT);
    sb.push(_NT_LF);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Validation helpers for nt_add_triple
// --------------------------------------------------

// True when `s` is a blank node label in the documented ASCII subset:
// [A-Za-z0-9_] followed by [A-Za-z0-9_.-]*, not ending in '.'.
fn _bnode_label_ok(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  if !_is_label_start(string.byte_at(s, 0)) {
    return false;
  }
  var i = 0;
  while i < n {
    if !_is_label_byte(string.byte_at(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return string.byte_at(s, n - 1) != _NT_DOT;
}

// True when `s` matches [a-zA-Z]+ ('-' [a-zA-Z0-9]+)*.
fn _langtag_ok(s: Str) -> Bool {
  let n = s.len();
  var i = 0;
  let first_start = i;
  while i < n && _is_alpha_byte(string.byte_at(s, i)) {
    i = i + 1;
  }
  if i == first_start {
    return false;
  }
  while i < n {
    if string.byte_at(s, i) != _NT_MINUS {
      return false;
    }
    i = i + 1;
    let sub_start = i;
    while i < n && _is_alnum_byte(string.byte_at(s, i)) {
      i = i + 1;
    }
    if i == sub_start {
      return false;
    }
  }
  return true;
}
