// XIOM -- xiom.spf: SPF (RFC 7208 syntax subset) record parser and canonical emitter
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Greenfield package: pure XIOM, no FFI, no DNS, no evaluation, no DNS TXT
// framing.
//
// Model: one parsed record is a flat set of parallel vectors -- kind,
// qualifier, value, cidr and is_modifier -- because Vec[StructType] is not
// usable in this compiler. Term i is a mechanism when is_modifier[i] is 0 and
// a modifier when it is 1:
//   * kind[i]        canonical lowercase mechanism name ("all", "include",
//                    "a", "mx", "ip4", "ip6", "ptr", "exists") or the
//                    modifier name as written ("redirect", "exp", "foo", ...);
//   * qualifier[i]   "+", "-", "~" or "?" for mechanisms ("+" is the default)
//                    and "" for modifiers;
//   * value[i]       domain-spec, address or modifier value, verbatim; "" when
//                    the term has no value;
//   * cidr[i]        validated prefix length, or -1 when the term has none;
//   * is_modifier[i] 1 for a modifier, 0 for a mechanism.
// The five vectors always have the same length in a parsed record; accessors
// and the emitter clamp to the shortest of them, so a hand-built value cannot
// cause an out-of-bounds read.
//
// Grammar (see SPEC.md for the full statement):
//   record    = ws* version ( 1*ws term )* ws*
//   version   = "v=spf1"                            ; ASCII case-insensitive
//   term      = [ qualifier ] mechanism / modifier
//   qualifier = "+" / "-" / "~" / "?"
//   mechanism = "all"
//             / "include" ":" domain-spec
//             / "a" [ ":" domain-spec ] [ "/" cidr4 ]
//             / "mx" [ ":" domain-spec ] [ "/" cidr4 ]
//             / "ptr" [ ":" domain-spec ]
//             / "ip4" ":" ip4-address [ "/" cidr4 ]
//             / "ip6" ":" ip6-address [ "/" cidr6 ]
//             / "exists" ":" domain-spec
//   modifier  = name "=" macro-string
//   name      = ALPHA *( ALPHA / DIGIT / "-" / "_" / "." )
//   cidr4     = "0".."32"    ; canonical decimal, no leading zeros
//   cidr6     = "0".."128"   ; canonical decimal, no leading zeros
//   ws        = SP / TAB
//
// Documented decisions (pinned in SPEC.md and covered by the conformance
// suite):
//   * the first token must be "v=spf1" (ASCII case-insensitive, ABNF string
//     semantics); a first token that starts with "v=" but is not "v=spf1" is
//     a wrong version, any other first token means the version is missing,
//     and a later "v=..." token is an ordinary modifier named "v";
//   * mechanism and modifier names are ASCII case-insensitive; mechanism
//     names are stored canonically lowercase and modifier names verbatim;
//   * the default qualifier "+" is stored and omitted by the emitter;
//   * every modifier name may appear at most once, compared ASCII
//     case-insensitively; this subset is stricter than RFC 7208, which only
//     forbids a second "redirect" or "exp";
//   * include/exists require a non-empty domain-spec and ptr an optional one;
//     none of the three accepts a CIDR, so a top-level "/" in their value is
//     a mechanism-syntax error;
//   * a/mx accept an optional domain-spec and an optional CIDR in 0..32;
//     ip4 accepts 0..32 and ip6 0..128; "a:/24" is stored like "a/24";
//   * ip4/ip6 addresses are stored verbatim: no address-syntax validation
//     (only the CIDR length is checked) and never any DNS lookup;
//   * domain-specs, addresses and modifier values are macro strings and must
//     pass spf_macro_valid; macros are otherwise passed through verbatim;
//   * the emitter writes "v=spf1" and then one space plus one canonical term
//     per term, with single spaces and no trailing space.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; every byte read from a Str goes through
//     xiom.string.byte_at and is widened as `(byte_at(s, i) as Int) & 0xFF`
//     before any comparison;
//   * Ok/Err for Result[Spf, Str] are constructed only in the leaf helpers
//     _spf_ok/_spf_err; the internal term parsers return "" on success and
//     the catalog message on failure, which keeps Result construction out of
//     the parsing functions;
//   * Str equality between values read from Vec[Str] elements goes through
//     xiom.string.compare (str_compare / str_compare_ignore_case); every
//     element read is bound to a typed local first;
//   * no Vec[StructType], no methods, no lambdas, no Vec[fn], no `mut`
//     matches; the five parallel vectors are only ever extended together
//     (_spf_push_term), and every reader clamps to _spf_span.
//
// See SPEC.md for the model, the decisions, the error catalog and the test
// plan.

module xiom.spf

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Byte and character constants (Int space)
// --------------------------------------------------

const _SPF_TAB: Int = 9;
const _SPF_SP: Int = 32;
const _SPF_PERCENT: Int = 37;
const _SPF_PLUS: Int = 43;
const _SPF_COMMA: Int = 44;
const _SPF_MINUS: Int = 45;
const _SPF_DOT: Int = 46;
const _SPF_SLASH: Int = 47;
const _SPF_ZERO: Int = 48;
const _SPF_NINE: Int = 57;
const _SPF_COLON: Int = 58;
const _SPF_EQ: Int = 61;
const _SPF_QUESTION: Int = 63;
const _SPF_UPPER_A: Int = 65;
const _SPF_UPPER_Z: Int = 90;
const _SPF_UNDERSCORE: Int = 95;
const _SPF_LOWER_A: Int = 97;
const _SPF_LOWER_V: Int = 118;
const _SPF_LOWER_R: Int = 114;
const _SPF_LOWER_Z: Int = 122;
const _SPF_LBRACE: Int = 123;
const _SPF_RBRACE: Int = 125;
const _SPF_TILDE: Int = 126;
const _SPF_DEL: Int = 127;

// Mechanism kind codes (see _spf_mech_kind).
const _SPF_M_ALL: Int = 0;
const _SPF_M_INCLUDE: Int = 1;
const _SPF_M_A: Int = 2;
const _SPF_M_MX: Int = 3;
const _SPF_M_IP4: Int = 4;
const _SPF_M_IP6: Int = 5;
const _SPF_M_PTR: Int = 6;
const _SPF_M_EXISTS: Int = 7;

// CIDR upper bounds per mechanism family.
const _SPF_CIDR4_MAX: Int = 32;
const _SPF_CIDR6_MAX: Int = 128;

// --------------------------------------------------
//  Result leaf helpers (see the module header)
// --------------------------------------------------

// Ok(r) for Result[Spf, Str].
fn _spf_ok(r: Spf) -> Result[Spf, Str] {
  return Ok(r);
}

// Err(m) for Result[Spf, Str].
fn _spf_err(m: Str) -> Result[Spf, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed SPF record. See the module header for the field-by-field model.
/// In a parsed record all five parallel vectors have the same length; the
/// accessors and `spf_emit` clamp to the shortest of them.
pub type Spf = {
  kind: Vec[Str];
  qualifier: Vec[Str];
  value: Vec[Str];
  cidr: Vec[Int];
  is_modifier: Vec[Int];
}

// --------------------------------------------------
//  Byte, character and scan helpers
// --------------------------------------------------

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so byte comparisons never touch UInt8 values.
fn _spf_byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for the term separator bytes SP and TAB.
fn _spf_is_sep(b: Int) -> Bool {
  return b == _SPF_SP || b == _SPF_TAB;
}

fn _spf_is_digit(b: Int) -> Bool {
  return b >= _SPF_ZERO && b <= _SPF_NINE;
}

fn _spf_is_alpha(b: Int) -> Bool {
  if b >= _SPF_UPPER_A && b <= _SPF_UPPER_Z {
    return true;
  }
  if b >= _SPF_LOWER_A && b <= _SPF_LOWER_Z {
    return true;
  }
  return false;
}

// ALPHA / DIGIT / "-" / "_" / "." -- the RFC 7208 name characters.
fn _spf_is_name_char(b: Int) -> Bool {
  if _spf_is_alpha(b) {
    return true;
  }
  if _spf_is_digit(b) {
    return true;
  }
  return b == _SPF_MINUS || b == _SPF_UNDERSCORE || b == _SPF_DOT;
}

// ASCII lowercase of one byte; other bytes are returned unchanged.
fn _spf_lower(b: Int) -> Int {
  if b >= _SPF_UPPER_A && b <= _SPF_UPPER_Z {
    return b + 32;
  }
  return b;
}

// s / l / o / d / i / p / h / c / r / t / v, ASCII case-insensitive. The
// numeric comparisons are the lowercased byte values.
fn _spf_is_macro_letter(b: Int) -> Bool {
  let c = _spf_lower(b);
  if c == 99 { return true; }
  if c == 100 { return true; }
  if c == 104 { return true; }
  if c == 105 { return true; }
  if c == 108 { return true; }
  if c == 111 { return true; }
  if c == 112 { return true; }
  if c == 114 { return true; }
  if c == 115 { return true; }
  if c == 116 { return true; }
  if c == 118 { return true; }
  return false;
}

// "." / "-" / "+" / "," / "/" / "_" / "=" -- the RFC 7208 macro delimiters.
fn _spf_is_macro_delim(b: Int) -> Bool {
  if b == _SPF_DOT { return true; }
  if b == _SPF_MINUS { return true; }
  if b == _SPF_PLUS { return true; }
  if b == _SPF_COMMA { return true; }
  if b == _SPF_SLASH { return true; }
  if b == _SPF_UNDERSCORE { return true; }
  if b == _SPF_EQ { return true; }
  return false;
}

// True when every byte of `text` is acceptable record input: printable bytes,
// SP, TAB and bytes >= 0x80 pass; every other C0 control byte, LF and CR
// included, and DEL are rejected. (Str is NUL-terminated on this toolchain,
// so a NUL byte cannot occur in ordinary Str values; the check is defensive
// for NUL and effective for the other control bytes.)
fn _spf_scan_clean(text: Str) -> Bool {
  let n = text.len();
  var i = 0;
  while i < n {
    let b = _spf_byte(text, i);
    if b < _SPF_SP && b != _SPF_TAB {
      return false;
    }
    if b == _SPF_DEL {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Document construction helpers
// --------------------------------------------------

// An empty record (zero terms); spf_emit on it returns "v=spf1".
fn _spf_empty() -> Spf {
  return Spf{
    kind: Vec[Str].new();
    qualifier: Vec[Str].new();
    value: Vec[Str].new();
    cidr: Vec[Int].new();
    is_modifier: Vec[Int].new();
  };
}

// Append one term. The five parallel vectors are only ever extended here, so
// they cannot drift inside this module.
fn _spf_push_term(r: &mut Spf, kind: Str, qual: Str, value: Str, cidr: Int, is_mod: Int) {
  r.kind.push(kind);
  r.qualifier.push(qual);
  r.value.push(value);
  r.cidr.push(cidr);
  r.is_modifier.push(is_mod);
}

// Append one mechanism term with the canonical lowercase kind.
fn _spf_push_mech(r: &mut Spf, k: Int, qual: Str, value: Str, cidr: Int) {
  _spf_push_term(r, _spf_mech_name(k), qual, value, cidr, 0);
}

// Number of terms addressable in r: the length of the shortest parallel
// vector. A parsed record has all five equal, so this equals the term count.
fn _spf_span(r: &Spf) -> Int {
  var n = r.kind.len();
  if r.qualifier.len() < n { n = r.qualifier.len(); }
  if r.value.len() < n { n = r.value.len(); }
  if r.cidr.len() < n { n = r.cidr.len(); }
  if r.is_modifier.len() < n { n = r.is_modifier.len(); }
  return n;
}

// --------------------------------------------------
//  Version and mechanism classification
// --------------------------------------------------

// True when `tok` is exactly "v=spf1", ASCII case-insensitive.
fn _spf_is_version(tok: Str) -> Bool {
  return compare.str_compare_ignore_case(tok, "v=spf1") == 0;
}

// True when `tok` starts with "v=", ASCII case-insensitive: such a first
// token is a wrong version rather than a missing one.
fn _spf_starts_v_eq(tok: Str) -> Bool {
  let n = tok.len();
  if n < 2 {
    return false;
  }
  if _spf_lower(_spf_byte(tok, 0)) != _SPF_LOWER_V {
    return false;
  }
  return _spf_byte(tok, 1) == _SPF_EQ;
}

// Kind code of a mechanism name (ASCII case-insensitive): 0..7 for the eight
// documented mechanisms, -1 when unknown.
fn _spf_mech_kind(name: Str) -> Int {
  if compare.str_compare_ignore_case(name, "all") == 0 {
    return _SPF_M_ALL;
  }
  if compare.str_compare_ignore_case(name, "include") == 0 {
    return _SPF_M_INCLUDE;
  }
  if compare.str_compare_ignore_case(name, "a") == 0 {
    return _SPF_M_A;
  }
  if compare.str_compare_ignore_case(name, "mx") == 0 {
    return _SPF_M_MX;
  }
  if compare.str_compare_ignore_case(name, "ip4") == 0 {
    return _SPF_M_IP4;
  }
  if compare.str_compare_ignore_case(name, "ip6") == 0 {
    return _SPF_M_IP6;
  }
  if compare.str_compare_ignore_case(name, "ptr") == 0 {
    return _SPF_M_PTR;
  }
  if compare.str_compare_ignore_case(name, "exists") == 0 {
    return _SPF_M_EXISTS;
  }
  return -1;
}

// Canonical (lowercase) spelling of a mechanism kind code; "" when k is not a
// valid kind.
fn _spf_mech_name(k: Int) -> Str {
  if k == _SPF_M_ALL {
    return "all";
  }
  if k == _SPF_M_INCLUDE {
    return "include";
  }
  if k == _SPF_M_A {
    return "a";
  }
  if k == _SPF_M_MX {
    return "mx";
  }
  if k == _SPF_M_IP4 {
    return "ip4";
  }
  if k == _SPF_M_IP6 {
    return "ip6";
  }
  if k == _SPF_M_PTR {
    return "ptr";
  }
  if k == _SPF_M_EXISTS {
    return "exists";
  }
  return "";
}

// CIDR upper bound of a mechanism kind.
fn _spf_cidr_max(k: Int) -> Int {
  if k == _SPF_M_IP6 {
    return _SPF_CIDR6_MAX;
  }
  return _SPF_CIDR4_MAX;
}

// --------------------------------------------------
//  CIDR and macro scanning
// --------------------------------------------------

// Scan s[start, stop) as a canonical decimal CIDR length at most max: at
// least one digit, "0" alone allowed, no leading zero on a multi-digit value.
// Returns the value, or -1 when the slice is empty, carries a non-digit byte,
// has a leading zero, or exceeds max. The accumulator stops growing once it
// passes max, so arbitrarily long digit runs cannot overflow.
fn _spf_scan_cidr(s: Str, start: Int, stop: Int, max: Int) -> Int {
  if start >= stop {
    return -1;
  }
  if stop - start > 1 && _spf_byte(s, start) == _SPF_ZERO {
    return -1;
  }
  var v = 0;
  var i = start;
  while i < stop {
    let c = _spf_byte(s, i);
    if !_spf_is_digit(c) {
      return -1;
    }
    if v <= max {
      v = v * 10 + (c - _SPF_ZERO);
    }
    i = i + 1;
  }
  if v > max {
    return -1;
  }
  return v;
}

// Index of the first top-level '/' in s[start, n), or -1. A '%{...}' body is
// skipped as a unit, so a '/' that is a macro delimiter never splits the
// value; a malformed macro is skipped to the end of the string and is then
// rejected by spf_macro_valid.
fn _spf_cidr_slash(s: Str, start: Int) -> Int {
  let n = s.len();
  var i = start;
  while i < n {
    let b = _spf_byte(s, i);
    if b == _SPF_PERCENT && i + 1 < n && _spf_byte(s, i + 1) == _SPF_LBRACE {
      var j = i + 2;
      while j < n && _spf_byte(s, j) != _SPF_RBRACE {
        j = j + 1;
      }
      i = j + 1;
    } elif b == _SPF_SLASH {
      return i;
    } else {
      i = i + 1;
    }
  }
  return -1;
}

/// True when every '%' in `s` begins a well-formed RFC 7208 macro escape and
/// every other byte is macro-literal text.
/// Params: s - a domain-spec, address or modifier value candidate.
/// Returns: true when each '%' is followed by "%%", "%_" or "%-", or by
/// "{...}" whose body is one or more macro letters (s l o d i p h c r t v,
/// ASCII case-insensitive), then digits, then an optional "r", then zero or
/// more delimiters (".", "-", "+", ",", "/", "_", "=") and closes with "}".
/// A '/' inside a macro body is a delimiter and is accepted; a bare '}' is
/// literal text. Bytes >= 0x80 pass through as macro-literal bytes.
/// Error case: none.
/// Examples: spf_macro_valid("%{d}.%{ir}") -> true; spf_macro_valid("%%") ->
/// true; spf_macro_valid("%{x}") -> false; spf_macro_valid("a%") -> false.
/// Complexity: O(s.len()).
pub fn spf_macro_valid(s: Str) -> Bool {
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _spf_byte(s, i);
    if b != _SPF_PERCENT {
      i = i + 1;
      continue;
    }
    if i + 1 >= n {
      return false;
    }
    let c = _spf_byte(s, i + 1);
    if c == _SPF_PERCENT || c == _SPF_UNDERSCORE || c == _SPF_MINUS {
      i = i + 2;
      continue;
    }
    if c != _SPF_LBRACE {
      return false;
    }
    var j = i + 2;
    var letters = 0;
    while j < n && _spf_is_macro_letter(_spf_byte(s, j)) {
      letters = letters + 1;
      j = j + 1;
    }
    if letters == 0 {
      return false;
    }
    while j < n && _spf_is_digit(_spf_byte(s, j)) {
      j = j + 1;
    }
    if j < n && _spf_lower(_spf_byte(s, j)) == _SPF_LOWER_R {
      j = j + 1;
    }
    while j < n && _spf_is_macro_delim(_spf_byte(s, j)) {
      j = j + 1;
    }
    if j >= n || _spf_byte(s, j) != _SPF_RBRACE {
      return false;
    }
    i = j + 1;
  }
  return true;
}

// --------------------------------------------------
//  Term parsers (return "" on success, else the catalog message)
// --------------------------------------------------

// A term with no "=", ":", or "/" after the name. "all", "a", "mx" and "ptr"
// are complete mechanisms; include, ip4, ip6 and exists require a value.
fn _spf_bare(r: &mut Spf, name: Str, qual: Str, term: Str) -> Str {
  let k = _spf_mech_kind(name);
  if k < 0 {
    return "spf: unknown mechanism: " + term;
  }
  if k == _SPF_M_ALL || k == _SPF_M_A || k == _SPF_M_MX || k == _SPF_M_PTR {
    _spf_push_mech(r, k, qual, "", -1);
    return "";
  }
  return "spf: bad mechanism syntax: " + term;
}

// A "name:value" term that takes no CIDR (include, exists, ptr). The value
// must be non-empty and must not contain a top-level "/".
fn _spf_domain_term(r: &mut Spf, k: Int, qual: Str, term: Str, colon: Int) -> Str {
  let value = string.str_slice(term, colon + 1, term.len());
  if value.len() == 0 {
    return "spf: bad mechanism syntax: " + term;
  }
  if _spf_cidr_slash(value, 0) >= 0 {
    return "spf: bad mechanism syntax: " + term;
  }
  if !spf_macro_valid(value) {
    return "spf: bad macro: " + term;
  }
  _spf_push_mech(r, k, qual, value, -1);
  return "";
}

// A "name:value[/cidr]" term for a, mx, ip4 and ip6. a/mx may omit the value
// ("a/24"), ip4/ip6 must have a non-empty one. The CIDR is validated first,
// then the required value, then the macro shape.
fn _spf_value_term(r: &mut Spf, k: Int, qual: Str, term: Str, colon: Int) -> Str {
  let n = term.len();
  let slash = _spf_cidr_slash(term, colon + 1);
  var value = string.str_slice(term, colon + 1, n);
  var cidr = -1;
  if slash >= 0 {
    value = string.str_slice(term, colon + 1, slash);
    cidr = _spf_scan_cidr(term, slash + 1, n, _spf_cidr_max(k));
    if cidr < 0 {
      return "spf: bad cidr: " + term;
    }
  }
  if (k == _SPF_M_IP4 || k == _SPF_M_IP6) && value.len() == 0 {
    return "spf: bad mechanism syntax: " + term;
  }
  if !spf_macro_valid(value) {
    return "spf: bad macro: " + term;
  }
  _spf_push_mech(r, k, qual, value, cidr);
  return "";
}

// A "name/cidr" term with no value: only a and mx allow that form.
fn _spf_cidr_term(r: &mut Spf, k: Int, qual: Str, term: Str, slash: Int) -> Str {
  if k != _SPF_M_A && k != _SPF_M_MX {
    return "spf: bad mechanism syntax: " + term;
  }
  let cidr = _spf_scan_cidr(term, slash + 1, term.len(), _SPF_CIDR4_MAX);
  if cidr < 0 {
    return "spf: bad cidr: " + term;
  }
  _spf_push_mech(r, k, qual, "", cidr);
  return "";
}

// True for the two RFC 7208 modifiers that take a domain-spec.
fn _spf_is_redirect_or_exp(name: Str) -> Bool {
  if compare.str_compare_ignore_case(name, "redirect") == 0 {
    return true;
  }
  if compare.str_compare_ignore_case(name, "exp") == 0 {
    return true;
  }
  return false;
}

// A "name=value" term. redirect and exp require a non-empty value; the macro
// shape is checked next and the duplicate-name check last, so the first
// failure in that order is reported.
fn _spf_modifier(r: &mut Spf, name: Str, term: Str, eq: Int) -> Str {
  let value = string.str_slice(term, eq + 1, term.len());
  if _spf_is_redirect_or_exp(name) && value.len() == 0 {
    return "spf: bad modifier: " + term;
  }
  if !spf_macro_valid(value) {
    return "spf: bad macro: " + term;
  }
  let span = _spf_span(r);
  var i = 0;
  while i < span {
    let im: Int = r.is_modifier[i];
    if im != 0 {
      let k: Str = r.kind[i];
      if compare.str_compare_ignore_case(k, name) == 0 {
        return "spf: duplicate modifier: " + name;
      }
    }
    i = i + 1;
  }
  _spf_push_term(r, name, "", value, -1, 1);
  return "";
}

// Parse and append one term. Returns "" on success, else the catalog message.
// The term has no separator bytes; the caller split it out of the record.
fn _spf_term(r: &mut Spf, term: Str) -> Str {
  let n = term.len();
  if n == 0 {
    return "spf: empty term: " + term;
  }
  var qual = "+";
  var start = 0;
  let first = _spf_byte(term, 0);
  if first == _SPF_PLUS || first == _SPF_MINUS || first == _SPF_TILDE || first == _SPF_QUESTION {
    if first != _SPF_PLUS {
      qual = string.str_slice(term, 0, 1);
    }
    start = 1;
  }
  if start >= n {
    return "spf: empty term: " + term;
  }
  let b0 = _spf_byte(term, start);
  if _spf_is_digit(b0) {
    return "spf: unknown mechanism: " + term;
  }
  if !_spf_is_alpha(b0) {
    return "spf: empty term: " + term;
  }
  var j = start;
  while j < n && _spf_is_name_char(_spf_byte(term, j)) {
    j = j + 1;
  }
  let name = string.str_slice(term, start, j);
  if j >= n {
    return _spf_bare(r, name, qual, term);
  }
  let delim = _spf_byte(term, j);
  if delim == _SPF_EQ {
    if start != 0 {
      return "spf: bad modifier: " + term;
    }
    return _spf_modifier(r, name, term, j);
  }
  let k = _spf_mech_kind(name);
  if delim == _SPF_COLON {
    if k < 0 {
      return "spf: unknown mechanism: " + term;
    }
    if k == _SPF_M_ALL {
      return "spf: bad mechanism syntax: " + term;
    }
    if k == _SPF_M_A || k == _SPF_M_MX || k == _SPF_M_IP4 || k == _SPF_M_IP6 {
      return _spf_value_term(r, k, qual, term, j);
    }
    return _spf_domain_term(r, k, qual, term, j);
  }
  if delim == _SPF_SLASH {
    if k < 0 {
      return "spf: unknown mechanism: " + term;
    }
    return _spf_cidr_term(r, k, qual, term, j);
  }
  return "spf: unknown mechanism: " + term;
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse one in-memory SPF record.
/// Params: record - the record text (for example
/// "v=spf1 ip4:192.0.2.0/24 include:_spf.example.com -all").
/// Returns: Ok(Spf) for a syntactically valid record; Err("spf: ...") with a
/// deterministic catalog message otherwise.
/// Behavior: the first token must be "v=spf1" (ASCII case-insensitive);
/// terms are separated by one or more SP or TAB bytes, which are also
/// stripped around the whole record; mechanism and modifier names are ASCII
/// case-insensitive; qualifiers default to "+"; modifiers may not repeat;
/// values must pass spf_macro_valid; CIDR lengths must be canonical decimals
/// in range. No DNS, no evaluation and no DNS TXT framing is performed.
/// Error case: see the catalog in SPEC.md; messages start with "spf: ".
/// Complexity: O(record length).
pub fn spf_parse(record: Str) -> Result[Spf, Str] {
  if !_spf_scan_clean(record) {
    return _spf_err("spf: control byte in input");
  }
  var r = _spf_empty();
  let n = record.len();
  var i = 0;
  while i < n && _spf_is_sep(_spf_byte(record, i)) {
    i = i + 1;
  }
  if i >= n {
    return _spf_err("spf: missing version");
  }
  let vstart = i;
  while i < n && !_spf_is_sep(_spf_byte(record, i)) {
    i = i + 1;
  }
  let ver = string.str_slice(record, vstart, i);
  if !_spf_is_version(ver) {
    if _spf_starts_v_eq(ver) {
      return _spf_err("spf: wrong version: " + ver);
    }
    return _spf_err("spf: missing version");
  }
  while i < n {
    while i < n && _spf_is_sep(_spf_byte(record, i)) {
      i = i + 1;
    }
    if i < n {
      let tstart = i;
      while i < n && !_spf_is_sep(_spf_byte(record, i)) {
        i = i + 1;
      }
      let term = string.str_slice(record, tstart, i);
      let msg = _spf_term(&mut r, term);
      if msg.len() > 0 {
        return _spf_err(msg);
      }
    }
  }
  return _spf_ok(r);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// An empty record: zero terms. `spf_emit` on it returns "v=spf1".
pub fn spf_new() -> Spf {
  return _spf_empty();
}

/// Number of terms in `r` (mechanisms plus modifiers); 0 for an empty record.
/// Error case: none.
/// Complexity: O(1).
pub fn spf_term_count(r: &Spf) -> Int {
  return _spf_span(r);
}

/// Kind of term `i`: the canonical lowercase mechanism name ("all",
/// "include", "a", "mx", "ip4", "ip6", "ptr", "exists") or the modifier name
/// exactly as written ("redirect", "exp", ...). "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn spf_term_kind(r: &Spf, i: Int) -> Str {
  if i < 0 || i >= _spf_span(r) {
    return "";
  }
  let k: Str = r.kind[i];
  return k;
}

/// Qualifier of term `i`: "+", "-", "~" or "?" for mechanisms, "" for
/// modifiers and "" when `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn spf_term_qualifier(r: &Spf, i: Int) -> Str {
  if i < 0 || i >= _spf_span(r) {
    return "";
  }
  let q: Str = r.qualifier[i];
  return q;
}

/// Value of term `i` verbatim (domain-spec, address or modifier value); ""
/// when the term has no value or `i` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn spf_term_value(r: &Spf, i: Int) -> Str {
  if i < 0 || i >= _spf_span(r) {
    return "";
  }
  let v: Str = r.value[i];
  return v;
}

/// CIDR length of term `i` (0..32 for a/mx/ip4, 0..128 for ip6), or -1 when
/// the term has no CIDR or `i` is out of range. The sentinel matches the
/// stored representation, so -1 is never a valid length.
/// Error case: none.
/// Complexity: O(1).
pub fn spf_term_cidr(r: &Spf, i: Int) -> Int {
  if i < 0 || i >= _spf_span(r) {
    return -1;
  }
  let c: Int = r.cidr[i];
  return c;
}

/// True when term `i` is a modifier, false when it is a mechanism or `i` is
/// out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn spf_term_is_modifier(r: &Spf, i: Int) -> Bool {
  if i < 0 || i >= _spf_span(r) {
    return false;
  }
  let m: Int = r.is_modifier[i];
  return m != 0;
}

/// Index of the first modifier named `name`, compared ASCII
/// case-insensitively, or -1 when there is none. In a parsed record every
/// modifier name appears at most once.
/// Error case: none.
/// Complexity: O(term count).
pub fn spf_find_modifier(r: &Spf, name: Str) -> Int {
  let span = _spf_span(r);
  var i = 0;
  while i < span {
    let m: Int = r.is_modifier[i];
    if m != 0 {
      let k: Str = r.kind[i];
      if compare.str_compare_ignore_case(k, name) == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Emitting
// --------------------------------------------------

// Append one canonical term: modifiers as name=value; mechanisms as
// [qualifier]name[:value][/cidr] with the default "+" omitted.
fn _spf_emit_term(out: &mut Vec[UInt8], r: &Spf, i: Int) {
  let is_mod: Int = r.is_modifier[i];
  let kind: Str = r.kind[i];
  let value: Str = r.value[i];
  if is_mod != 0 {
    builder.sb_push_str(out, kind);
    builder.sb_push_str(out, "=");
    builder.sb_push_str(out, value);
    return;
  }
  let qual: Str = r.qualifier[i];
  var emit_qual = true;
  if qual.len() == 1 && _spf_byte(qual, 0) == _SPF_PLUS {
    emit_qual = false;
  }
  if emit_qual {
    builder.sb_push_str(out, qual);
  }
  builder.sb_push_str(out, kind);
  if value.len() > 0 {
    builder.sb_push_str(out, ":");
    builder.sb_push_str(out, value);
  }
  let c: Int = r.cidr[i];
  if c >= 0 {
    builder.sb_push_str(out, "/");
    builder.sb_push_str(out, convert.int_to_string(c));
  }
}

/// Emit the canonical text of `r`.
/// Params: r - the record to serialize.
/// Returns: "v=spf1", then one space and one canonical term per term in
/// order, with single spaces and no trailing space. Mechanisms are written
/// with the canonical lowercase name, an optional ":" plus the value
/// verbatim, an optional "/" plus the CIDR, and omit the default "+";
/// modifiers are written as name=value with the name and value verbatim. An
/// empty record emits "v=spf1"; spf_parse(spf_emit(r)) preserves every term.
/// Error case: none. Values are written verbatim; parse guarantees they
/// contain no control byte, SP or TAB. A hand-built value whose vectors
/// disagree is clamped to the shortest vector.
/// Complexity: O(total output length).
pub fn spf_emit(r: &Spf) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "v=spf1");
  let count = _spf_span(r);
  var i = 0;
  while i < count {
    builder.sb_push_str(&mut out, " ");
    _spf_emit_term(&mut out, r, i);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
