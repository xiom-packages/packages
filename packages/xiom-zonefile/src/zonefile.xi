// XIOM -- xiom.zonefile: DNS zone-file (master file) codec subset
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets) parser and canonical emitter for the
// documented master-file subset: the $ORIGIN and $TTL directives, records
// with an optional owner name, TTL and class, relative-name completion
// against the current origin, `@`, parenthesized multi-line records, `;`
// comments and quoted strings with \" and \\ escapes. RDATA is stored as
// whitespace-separated tokens plus a joined-text form for TXT. See SPEC.md
// for the grammar, the name-resolution rules, the error catalog and the
// exact subset.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; every byte read from a Str goes through
//     _zf_byte_at and is widened as `(byte_at(s, i) as Int) & 0xFF` before
//     any comparison (a raw UInt8 compared against a constant >= 128
//     miscompiles);
//   * no `==` on Str values (BUG 17); equality goes through
//     compare.str_compare and every Vec[Str] element is bound to a typed
//     local before use;
//   * Ok/Err for the struct-payload Result are constructed only in the leaf
//     helpers _zf_ok/_zf_err;
//   * the document is flat (Vec[StructType] is unsupported) and every push
//     on the index-aligned vectors happens in _zf_push_record, so the
//     parallel vectors cannot drift apart;
//   * the scanner returns negative error codes instead of a Result, so no
//     Result is constructed outside the leaf helpers.

module xiom.zonefile

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Document model
// --------------------------------------------------

/// Parsed zone document. `names`, `ttls`, `classes`, `types`,
/// `token_starts`, `token_counts` and `texts` are index-aligned per-record
/// vectors: record i has the resolved absolute owner name names[i] (always
/// with a trailing dot; "@" and relative names are already completed), the
/// effective TTL ttls[i] (0..4294967295), the class classes[i] ("IN"), the
/// canonical uppercase type types[i], and its RDATA as the slice
///                      tokens[token_starts[i] ..
///                             token_starts[i] + token_counts[i]]
/// of the shared flat pool. texts[i] is the joined TXT text (tokens joined
/// with a single space) for TXT records and "" for every other type.
/// Vec[StructType] is unsupported in this compiler, so the model is flat.
/// None of the directives survive in the document: names are resolved and
/// TTLs are already effective.
pub type Zone = {
  names: Vec[Str];
  ttls: Vec[Int];
  classes: Vec[Str];
  types: Vec[Str];
  token_starts: Vec[Int];
  token_counts: Vec[Int];
  tokens: Vec[Str];
  texts: Vec[Str];
}

// --------------------------------------------------
//  Constants and byte helpers
// --------------------------------------------------

const _ZF_TAB: Int = 9;
const _ZF_LF: Int = 10;
const _ZF_CR: Int = 13;
const _ZF_SPACE: Int = 32;
const _ZF_DQUOTE: Int = 34;
const _ZF_DOLLAR: Int = 36;
const _ZF_LPAREN: Int = 40;
const _ZF_RPAREN: Int = 41;
const _ZF_DOT: Int = 46;
const _ZF_ZERO: Int = 48;
const _ZF_NINE: Int = 57;
const _ZF_SEMI: Int = 59;
const _ZF_BSLASH: Int = 92;
const _ZF_TTL_MAX: Int = 4294967295;

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so byte comparisons never touch UInt8 values.
fn _zf_byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// ASCII space, TAB or CR. A newline is not "horizontal" whitespace: it ends
// a logical record or is skipped between records.
fn _zf_is_hspace(c: Int) -> Bool {
  return c == _ZF_SPACE || c == _ZF_TAB || c == _ZF_CR;
}

fn _zf_is_digit(c: Int) -> Bool {
  return c >= _ZF_ZERO && c <= _ZF_NINE;
}

// Byte-equal Str comparison (BUG 17 discipline: never `==` on Str).
fn _zf_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Case-insensitive ASCII Str comparison.
fn _zf_eq_ci(a: Str, b: Str) -> Bool {
  return compare.str_compare_ignore_case(a, b) == 0;
}

// --------------------------------------------------
//  Result leaf helpers
// --------------------------------------------------

// v0.61.3 miscompiles Ok/Err constructed inside larger functions, so every
// Result value in this module is built by one of these tiny wrappers.

fn _zf_ok(z: Zone) -> Result[Zone, Str] {
  return Ok(z);
}

fn _zf_err(m: Str) -> Result[Zone, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Types, TTLs and names
// --------------------------------------------------

// Canonical uppercase spelling of a documented type token, or "" when the
// token is not one of the eight documented types. Matching is
// case-insensitive; the result is the canonical spelling.
fn _zf_canonical_type(t: Str) -> Str {
  if _zf_eq_ci(t, "SOA") { return "SOA"; }
  if _zf_eq_ci(t, "NS") { return "NS"; }
  if _zf_eq_ci(t, "A") { return "A"; }
  if _zf_eq_ci(t, "AAAA") { return "AAAA"; }
  if _zf_eq_ci(t, "CNAME") { return "CNAME"; }
  if _zf_eq_ci(t, "MX") { return "MX"; }
  if _zf_eq_ci(t, "TXT") { return "TXT"; }
  if _zf_eq_ci(t, "PTR") { return "PTR"; }
  return "";
}

// Required RDATA token count for a canonical type: 7 for SOA, 2 for MX, -1
// for TXT (one or more), 1 for NS, A, AAAA, CNAME and PTR. Callers only
// pass a canonical type.
fn _zf_type_token_count(t: Str) -> Int {
  if _zf_eq(t, "SOA") { return 7; }
  if _zf_eq(t, "MX") { return 2; }
  if _zf_eq(t, "TXT") { return -1; }
  return 1;
}

// True when s is a non-empty run of ASCII digits.
fn _zf_all_digits(s: Str) -> Bool {
  let n = s.len();
  if n == 0 { return false; }
  var i = 0;
  while i < n {
    if !_zf_is_digit(_zf_byte_at(s, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// Value of an all-digit TTL token, or -1 when the token is not all digits
// or its value exceeds 4294967295 (the largest representable TTL).
fn _zf_parse_ttl(s: Str) -> Int {
  if !_zf_all_digits(s) { return -1; }
  var v = 0;
  var i = 0;
  while i < s.len() {
    v = v * 10 + (_zf_byte_at(s, i) - _ZF_ZERO);
    if v > _ZF_TTL_MAX { return -1; }
    i = i + 1;
  }
  return v;
}

// Resolve an owner name (or an $ORIGIN value) against the current origin.
// "@" is the origin itself; a name with a trailing dot is absolute and is
// returned verbatim; any other name is completed as name + "." + origin.
// The initial origin is the root ".", so a relative name with no $ORIGIN
// seen yet becomes absolute at the root ("www" -> "www."). Every result
// ends with a trailing dot.
fn _zf_resolve(origin: Str, name: Str) -> Str {
  if _zf_eq(name, "@") { return origin; }
  let n = name.len();
  if n > 0 {
    if _zf_byte_at(name, n - 1) == _ZF_DOT { return name; }
  }
  if _zf_eq(origin, ".") { return name + "."; }
  return name + "." + origin;
}

// --------------------------------------------------
//  Token scanning
// --------------------------------------------------

// Read one bare token starting at `start` and append it to `out`; returns
// the offset of the first byte that is not part of the token. A bare token
// ends at horizontal whitespace, a newline, ';', '(' or ')'. A quote is an
// ordinary byte inside a bare token (it only opens a quoted token at the
// start of one).
fn _zf_scan_bare(text: Str, start: Int, out: &mut Vec[Str]) -> Int {
  let total = text.len();
  var end = start;
  var sb = builder.sb_new();
  while end < total {
    let b = _zf_byte_at(text, end);
    if _zf_is_hspace(b) { break; }
    if b == _ZF_LF || b == _ZF_SEMI || b == _ZF_LPAREN || b == _ZF_RPAREN { break; }
    builder.sb_push_byte(&mut sb, b as UInt8);
    end = end + 1;
  }
  out.push(builder.sb_to_str(&sb));
  return end;
}

// Read one quoted token: `start` points at the opening quote. \" and \\
// decode to " and \; any other backslash sequence is kept verbatim
// (backslash plus the next byte). The unescaped text is appended to `out`.
// Returns the offset just past the closing quote, or -1 for an
// unterminated quote (EOF, a newline, or a backslash at EOF).
fn _zf_scan_quoted(text: Str, start: Int, out: &mut Vec[Str]) -> Int {
  let total = text.len();
  var sb = builder.sb_new();
  var pos = start + 1;
  while pos < total {
    let b = _zf_byte_at(text, pos);
    if b == _ZF_DQUOTE {
      out.push(builder.sb_to_str(&sb));
      return pos + 1;
    }
    if b == _ZF_LF { return -1; }
    if b == _ZF_BSLASH {
      if pos + 1 >= total { return -1; }
      let nb = _zf_byte_at(text, pos + 1);
      if nb == _ZF_LF { return -1; }
      if nb == _ZF_DQUOTE || nb == _ZF_BSLASH {
        builder.sb_push_byte(&mut sb, nb as UInt8);
      } else {
        builder.sb_push_byte(&mut sb, _ZF_BSLASH as UInt8);
        builder.sb_push_byte(&mut sb, nb as UInt8);
      }
      pos = pos + 2;
    } else {
      builder.sb_push_byte(&mut sb, b as UInt8);
      pos = pos + 1;
    }
  }
  return -1;
}

// Scan one logical record starting at `start` and append its tokens to
// `out`. Returns the offset just past the record (past the newline that
// ended it, or text.len() at EOF), -1 for unbalanced parentheses (a ')'
// at depth 0, or '(' never closed at EOF), or -2 for an unterminated
// quote. A newline at depth 0 ends the record; inside parentheses
// newlines are whitespace. ';' starts a comment that runs to end of line
// (but not inside a quoted token); '(' and ')' outside quotes are token
// separators and never part of a token.
fn _zf_scan_tokens(text: Str, start: Int, out: &mut Vec[Str]) -> Int {
  let total = text.len();
  var pos = start;
  var depth = 0;
  while pos < total {
    let b = _zf_byte_at(text, pos);
    if _zf_is_hspace(b) {
      pos = pos + 1;
    } elif b == _ZF_LF {
      if depth == 0 {
        return pos + 1;
      }
      pos = pos + 1;
    } elif b == _ZF_SEMI {
      while pos < total && _zf_byte_at(text, pos) != _ZF_LF {
        pos = pos + 1;
      }
    } elif b == _ZF_LPAREN {
      depth = depth + 1;
      pos = pos + 1;
    } elif b == _ZF_RPAREN {
      if depth == 0 { return -1; }
      depth = depth - 1;
      pos = pos + 1;
    } elif b == _ZF_DQUOTE {
      let q = _zf_scan_quoted(text, pos, out);
      if q < 0 { return -2; }
      pos = q;
    } else {
      pos = _zf_scan_bare(text, pos, out);
    }
  }
  if depth != 0 { return -1; }
  return pos;
}

// --------------------------------------------------
//  Record assembly
// --------------------------------------------------

// Joined TXT text: the `count` tokens starting at `start`, joined with a
// single space; "" for every non-TXT canonical type.
fn _zf_txt_text(typ: Str, toks: &Vec[Str], start: Int, count: Int) -> Str {
  if !_zf_eq(typ, "TXT") { return ""; }
  var sb = builder.sb_new();
  var k = 0;
  while k < count {
    if k > 0 { builder.sb_push_str(&mut sb, " "); }
    let t: Str = toks[start + k];
    builder.sb_push_str(&mut sb, t);
    k = k + 1;
  }
  return builder.sb_to_str(&sb);
}

// Append one parsed record. Every index-aligned vector is pushed here and
// the RDATA tokens are copied into the shared pool, so the vectors cannot
// drift apart.
fn _zf_push_record(z: &mut Zone, name: Str, ttl: Int, cls: Str, typ: Str, toks: &Vec[Str], start: Int, count: Int) {
  let pool_len = z.tokens.len();
  let txt = _zf_txt_text(typ, toks, start, count);
  z.names.push(name);
  z.ttls.push(ttl);
  z.classes.push(cls);
  z.types.push(typ);
  z.token_starts.push(pool_len);
  z.token_counts.push(count);
  z.texts.push(txt);
  var k = 0;
  while k < count {
    let t: Str = toks[start + k];
    z.tokens.push(t);
    k = k + 1;
  }
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse a zone file in the documented master-file subset.
/// Params: text - the whole file (LF or CRLF line endings; a missing final
/// newline is accepted).
/// Returns: Ok(Zone) for a document in the documented subset, including an
/// empty one and one with only comments/blank lines. Owner names are
/// resolved against the running origin; omitted owner names and TTLs are
/// inherited from the previous record; directives and comments are not
/// stored.
/// Error case: the first failure in document order, with an exact ASCII
/// message from the catalog in SPEC.md:
/// "zonefile: unterminated quote"; "zonefile: unbalanced parentheses";
/// "zonefile: unknown directive"; "zonefile: $ORIGIN without value";
/// "zonefile: bad $ORIGIN"; "zonefile: $TTL without value"; "zonefile: bad
/// $TTL"; "zonefile: missing name"; "zonefile: bad TTL"; "zonefile: bad
/// type"; "zonefile: missing rdata"; "zonefile: bad token count".
/// Within one record the checks run name, TTL, type, RDATA presence, then
/// the per-type token count.
/// Examples: "@ IN SOA ns admin 1 2 3 4 5\n" -> one SOA record;
/// "$ORIGIN example.com.\nwww A 192.0.2.1\n" -> the owner is
/// "www.example.com."; "    A 192.0.2.2\n" after it -> the same owner again.
/// Complexity: O(text.len()).
pub fn zone_parse(text: Str) -> Result[Zone, Str] {
  var z = Zone{
    names: Vec[Str].new();
    ttls: Vec[Int].new();
    classes: Vec[Str].new();
    types: Vec[Str].new();
    token_starts: Vec[Int].new();
    token_counts: Vec[Int].new();
    tokens: Vec[Str].new();
    texts: Vec[Str].new();
  };
  let total = text.len();
  var pos = 0;
  var origin = ".";
  var last_ttl = 0;
  var last_name = "";
  var has_last_name = false;
  while pos < total {
    // Skip horizontal whitespace, newlines and whole comment lines.
    while pos < total {
      let b = _zf_byte_at(text, pos);
      if _zf_is_hspace(b) || b == _ZF_LF {
        pos = pos + 1;
      } elif b == _ZF_SEMI {
        while pos < total && _zf_byte_at(text, pos) != _ZF_LF {
          pos = pos + 1;
        }
      } else {
        break;
      }
    }
    if pos >= total { break; }
    let rec_start = pos;
    var indented = false;
    if rec_start > 0 {
      let prev = _zf_byte_at(text, rec_start - 1);
      if prev == _ZF_SPACE || prev == _ZF_TAB {
        indented = true;
      }
    }
    var toks = Vec[Str].new();
    let next = _zf_scan_tokens(text, pos, &mut toks);
    if next == -1 { return _zf_err("zonefile: unbalanced parentheses"); }
    if next == -2 { return _zf_err("zonefile: unterminated quote"); }
    pos = next;
    if toks.len() == 0 { continue; }
    let first: Str = toks[0];
    if _zf_byte_at(first, 0) == _ZF_DOLLAR {
      // Directive: exactly one value for both documented directives.
      if _zf_eq_ci(first, "$ORIGIN") {
        if toks.len() < 2 { return _zf_err("zonefile: $ORIGIN without value"); }
        if toks.len() > 2 { return _zf_err("zonefile: bad $ORIGIN"); }
        let value: Str = toks[1];
        origin = _zf_resolve(origin, value);
      } elif _zf_eq_ci(first, "$TTL") {
        if toks.len() < 2 { return _zf_err("zonefile: $TTL without value"); }
        if toks.len() > 2 { return _zf_err("zonefile: bad $TTL"); }
        let value: Str = toks[1];
        let parsed = _zf_parse_ttl(value);
        if parsed < 0 { return _zf_err("zonefile: bad $TTL"); }
        last_ttl = parsed;
      } else {
        return _zf_err("zonefile: unknown directive");
      }
    } else {
      // Record: [name] [ttl] [class] type rdata...
      var idx = 0;
      var name = "";
      if indented {
        if !has_last_name { return _zf_err("zonefile: missing name"); }
        name = last_name;
      } else {
        name = _zf_resolve(origin, first);
        last_name = name;
        has_last_name = true;
        idx = 1;
      }
      var ttl = last_ttl;
      if idx < toks.len() {
        let t: Str = toks[idx];
        if _zf_all_digits(t) {
          let parsed = _zf_parse_ttl(t);
          if parsed < 0 { return _zf_err("zonefile: bad TTL"); }
          ttl = parsed;
          last_ttl = parsed;
          idx = idx + 1;
        }
      }
      var cls = "IN";
      if idx < toks.len() {
        let c: Str = toks[idx];
        if _zf_eq_ci(c, "IN") {
          cls = "IN";
          idx = idx + 1;
        }
      }
      if idx >= toks.len() { return _zf_err("zonefile: bad type"); }
      let raw_type: Str = toks[idx];
      idx = idx + 1;
      let typ = _zf_canonical_type(raw_type);
      if typ.len() == 0 { return _zf_err("zonefile: bad type"); }
      let rcount = toks.len() - idx;
      if rcount == 0 { return _zf_err("zonefile: missing rdata"); }
      let want = _zf_type_token_count(typ);
      if want >= 0 && rcount != want {
        return _zf_err("zonefile: bad token count");
      }
      _zf_push_record(&mut z, name, ttl, cls, typ, &toks, idx, rcount);
    }
  }
  return _zf_ok(z);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of records in the document.
/// Params: z - parsed document.
/// Returns: the record count; a corrupted document reports the smallest of
/// the aligned vectors, so trailing rows are ignored rather than read out
/// of range.
/// Error case: none.
/// Complexity: O(1).
pub fn zone_record_count(z: &Zone) -> Int {
  var n = z.names.len();
  if z.ttls.len() < n { n = z.ttls.len(); }
  if z.classes.len() < n { n = z.classes.len(); }
  if z.types.len() < n { n = z.types.len(); }
  if z.token_starts.len() < n { n = z.token_starts.len(); }
  if z.token_counts.len() < n { n = z.token_counts.len(); }
  if z.texts.len() < n { n = z.texts.len(); }
  return n;
}

/// Resolved absolute owner name of record i.
/// Params: z - parsed document; i - zero-based record index.
/// Returns: the name for 0 <= i < zone_record_count(z), else "". The name
/// is already completed against the origin and carries the trailing dot;
/// "@" and relative names never appear in stored output.
/// Error case: none.
/// Examples: "www" in example.com. -> "www.example.com.".
/// Complexity: O(1).
pub fn zone_name(z: &Zone, i: Int) -> Str {
  if i < 0 || i >= zone_record_count(z) { return ""; }
  let v: Str = z.names[i];
  return v;
}

/// Effective TTL of record i.
/// Params: z - parsed document; i - zero-based record index.
/// Returns: the TTL (0..4294967295) for 0 <= i < zone_record_count(z),
/// else -1. The value is already resolved: an explicit TTL wins and
/// updates the inherited value, an omitted TTL inherits the last explicit
/// TTL or the $TTL default (0 before any $TTL).
/// Error case: none.
/// Complexity: O(1).
pub fn zone_ttl(z: &Zone, i: Int) -> Int {
  if i < 0 || i >= zone_record_count(z) { return -1; }
  let v: Int = z.ttls[i];
  return v;
}

/// Class of record i.
/// Params: z - parsed document; i - zero-based record index.
/// Returns: "IN" for 0 <= i < zone_record_count(z), else "". "IN" is the
/// only class in the documented subset; an omitted class defaults to it.
/// Error case: none.
/// Complexity: O(1).
pub fn zone_class(z: &Zone, i: Int) -> Str {
  if i < 0 || i >= zone_record_count(z) { return ""; }
  let v: Str = z.classes[i];
  return v;
}

/// Type of record i, in canonical uppercase spelling.
/// Params: z - parsed document; i - zero-based record index.
/// Returns: the type for 0 <= i < zone_record_count(z), else "". One of
/// "SOA", "NS", "A", "AAAA", "CNAME", "MX", "TXT", "PTR"; the input may be
/// any case.
/// Error case: none.
/// Complexity: O(1).
pub fn zone_type(z: &Zone, i: Int) -> Str {
  if i < 0 || i >= zone_record_count(z) { return ""; }
  let v: Str = z.types[i];
  return v;
}

/// Number of RDATA tokens of record i.
/// Params: z - parsed document; i - zero-based record index.
/// Returns: the token count for 0 <= i < zone_record_count(z), else 0. The
/// count is clamped to the shared token pool, so a corrupted document
/// reports a safe value instead of reading past `tokens`.
/// Error case: none.
/// Complexity: O(1).
pub fn zone_rdata_token_count(z: &Zone, i: Int) -> Int {
  if i < 0 || i >= zone_record_count(z) { return 0; }
  let start: Int = z.token_starts[i];
  if start < 0 { return 0; }
  var c: Int = z.token_counts[i];
  if c < 0 { c = 0; }
  if start + c > z.tokens.len() { c = z.tokens.len() - start; }
  if c < 0 { c = 0; }
  return c;
}

/// RDATA token j of record i, exactly as written after unquoting.
/// Params: z - parsed document; i - zero-based record index; j - zero-based
/// token index.
/// Returns: the token for 0 <= j < zone_rdata_token_count(z, i), else "".
/// Tokens are verbatim: they are not name-resolved, validated or
/// interpreted (a quoted token loses only its quotes and the documented
/// \" and \\ escapes). An out-of-range token cannot be distinguished from
/// a real empty TXT token; use zone_rdata_token_count to tell them apart.
/// Error case: none.
/// Complexity: O(1).
pub fn zone_rdata_token(z: &Zone, i: Int, j: Int) -> Str {
  let c = zone_rdata_token_count(z, i);
  if j < 0 || j >= c { return ""; }
  let start: Int = z.token_starts[i];
  let v: Str = z.tokens[start + j];
  return v;
}

/// Joined TXT text of record i.
/// Params: z - parsed document; i - zero-based record index.
/// Returns: the record's RDATA tokens joined with a single space for a TXT
/// record, else "". Also "" for an out-of-range index. The join is what
/// makes `"hello world"` (one token containing a space) and `hello world`
/// (two tokens) both read as "hello world"; the token accessors keep them
/// apart.
/// Error case: none.
/// Complexity: O(1).
pub fn zone_txt_text(z: &Zone, i: Int) -> Str {
  if i < 0 || i >= zone_record_count(z) { return ""; }
  let v: Str = z.texts[i];
  return v;
}

// --------------------------------------------------
//  Emitting
// --------------------------------------------------

// Append one RDATA token in canonical form: a token that is empty or
// contains whitespace, a newline, ';', '(', ')', '"' or '\' is emitted as
// a quoted string with \" and \\ escapes; every other token verbatim.
fn _zf_render_token(sb: &mut Vec[UInt8], tok: Str) {
  let n = tok.len();
  var need_quote = n == 0;
  var i = 0;
  while i < n {
    let b = _zf_byte_at(tok, i);
    if _zf_is_hspace(b) { need_quote = true; }
    if b == _ZF_LF || b == _ZF_SEMI || b == _ZF_LPAREN || b == _ZF_RPAREN || b == _ZF_DQUOTE || b == _ZF_BSLASH {
      need_quote = true;
    }
    i = i + 1;
  }
  if !need_quote {
    builder.sb_push_str(sb, tok);
    return;
  }
  builder.sb_push_byte(sb, _ZF_DQUOTE as UInt8);
  i = 0;
  while i < n {
    let b = _zf_byte_at(tok, i);
    if b == _ZF_DQUOTE || b == _ZF_BSLASH {
      builder.sb_push_byte(sb, _ZF_BSLASH as UInt8);
    }
    builder.sb_push_byte(sb, b as UInt8);
    i = i + 1;
  }
  builder.sb_push_byte(sb, _ZF_DQUOTE as UInt8);
}

/// Emit a document in the canonical zone-file form.
/// Params: z - parsed document.
/// Returns: one line per record,
/// `name SP ttl SP class SP type SP token...`, each line terminated by LF
/// (an empty document emits ""). Names are the resolved absolute owner
/// names, the TTL is the effective decimal value, the class and type are
/// canonical, and the RDATA tokens are written in canonical form (quoted
/// with \" and \\ escapes only when a token would otherwise be ambiguous).
/// Directives, comments, source line breaks and parentheses are not
/// preserved. For a document produced by zone_parse, emit(parse(x)) is a
/// fixed point: parsing the emitted text yields the same records and
/// emitting that result reproduces the text byte for byte.
/// Error case: none.
/// Examples: parse("$ORIGIN example.com.\n$TTL 300\nwww A 192.0.2.1\n")
/// emits "www.example.com. 300 IN A 192.0.2.1\n".
/// Complexity: O(total output length).
pub fn zone_emit(z: &Zone) -> Str {
  var sb = builder.sb_new();
  let count = zone_record_count(z);
  var i = 0;
  while i < count {
    let nm: Str = z.names[i];
    let ttl: Int = z.ttls[i];
    let cls: Str = z.classes[i];
    let typ: Str = z.types[i];
    let start: Int = z.token_starts[i];
    let cnt = zone_rdata_token_count(z, i);
    builder.sb_push_str(&mut sb, nm);
    builder.sb_push_byte(&mut sb, _ZF_SPACE as UInt8);
    builder.sb_push_int(&mut sb, ttl);
    builder.sb_push_byte(&mut sb, _ZF_SPACE as UInt8);
    builder.sb_push_str(&mut sb, cls);
    builder.sb_push_byte(&mut sb, _ZF_SPACE as UInt8);
    builder.sb_push_str(&mut sb, typ);
    var j = 0;
    while j < cnt {
      builder.sb_push_byte(&mut sb, _ZF_SPACE as UInt8);
      let tok: Str = z.tokens[start + j];
      _zf_render_token(&mut sb, tok);
      j = j + 1;
    }
    builder.sb_push_byte(&mut sb, _ZF_LF as UInt8);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}
