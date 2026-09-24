// XIOM -- xiom.cookie: Cookie and Set-Cookie header parsing and serialization
// Greenfield package: pure XIOM, no FFI, no file I/O (in-memory Str only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a request Cookie line holds semicolon-separated "name=value" pairs
// and is stored as two parallel vectors -- Vec[StructType] is unsupported in
// this compiler, so the jar is deliberately flat (names[i], values[i]) instead
// of a list of pair structs. A Set-Cookie line is one "name=value" pair
// followed by optional "Attribute" / "Attribute=value" segments and maps to
// the flat SetCookie struct.
//
// Grammar (full statement in SPEC.md):
//   request       = pair *( ";" pair )
//   pair          = ws* name ws* "=" ws* value? ws*   ; first '=' splits
//   name          = 1*( byte except ";" "=" )         ; non-empty after trim
//   set-cookie    = pair *( ";" attribute )
//   attribute     = ws* ( flag / avpair )             ; unknown names ignored
//   flag          = "Secure" / "HttpOnly"             ; case-insensitive
//   avpair        = name ws* "=" ws* value? ws*
//
// Decisions pinned by the conformance suite and SPEC.md:
//   * Request parsing: whitespace is trimmed around every name and value;
//     a segment without '=' is skipped; a segment whose trimmed name is empty
//     is skipped; the FIRST occurrence of a name wins and later duplicates are
//     skipped.
//   * Set-Cookie parsing: the first pair is required -- Err("cookie: ...")
//     when it has no '=' or an empty name. Attribute names are matched
//     case-insensitively. Max-Age accepts an optional sign and decimal digits;
//     a value that is not a well-formed integer is ignored (the attribute is
//     not applied). SameSite is compared case-insensitively against Strict,
//     Lax and None and stored canonically ("Strict"/"Lax"/"None"); any other
//     value is kept raw. Duplicate attributes are last-wins. Unknown
//     attributes are ignored.
//   * max_age defaults to -1 (absent) and serialization omits it when it is
//     negative, so negative Max-Age values and absent Max-Age render alike.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Ok/Err for Result[SetCookie, Str] are constructed only in the tiny leaf
//     helpers _ok_set/_err_set (constructing Results directly inside other
//     functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); Vec elements are read into typed locals first.
//   * Bytes are read as (string.byte_at(s, i) as Int) & 0xFF and compared in
//     the Int domain; output is collected in a xiom.string.builder buffer.

module xiom.cookie

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A request cookie jar: `names` and `values` are index-aligned. Entry i is
/// the pair `names[i]=values[i]`. A name appears at most once because
/// cookie_parse_request keeps the first occurrence. A hand-built jar that is
/// ragged (unequal vector lengths) is read only up to the shortest vector.
pub type CookieJar = {
  names: Vec[Str];
  values: Vec[Str];
}

/// One parsed Set-Cookie header. `max_age` is -1 when the attribute is absent
/// or invalid; `path`, `domain` and `same_site` are "" when absent; `secure`
/// and `http_only` are the presence flags of the bare attributes.
pub type SetCookie = {
  name: Str;
  value: Str;
  path: Str;
  domain: Str;
  max_age: Int;
  secure: Bool;
  http_only: Bool;
  same_site: Str;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(c) for Result[SetCookie, Str].
fn _ok_set(c: SetCookie) -> Result[SetCookie, Str] {
  return Ok(c);
}

// Err(m) for Result[SetCookie, Str].
fn _err_set(m: Str) -> Result[SetCookie, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _COOKIE_DIGIT0: Int = 48;   // 0
const _COOKIE_DIGIT9: Int = 57;   // 9
const _COOKIE_PLUS: Int = 43;     // +
const _COOKIE_MINUS: Int = 45;    // -
const _COOKIE_SEMI: Int = 59;     // ;
const _COOKIE_EQ: Int = 61;       // =

// --------------------------------------------------
//  Low-level helpers
// --------------------------------------------------

// One byte of `s` at `i`, zero-extended to Int (0..255).
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Index of the first occurrence of byte `target` in `s`, or -1.
fn _find_byte(s: Str, target: Int) -> Int {
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == target {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Number of usable entries: the two parallel vectors are only safe up to the
// shortest one (a hand-built jar may be ragged).
fn _limit(jar: &CookieJar) -> Int {
  var lim = jar.names.len();
  if jar.values.len() < lim {
    lim = jar.values.len();
  }
  return lim;
}

// True when `jar` already holds `name` (BUG 17: str_compare, not `==`).
fn _has_name(jar: &CookieJar, name: Str) -> Bool {
  var i = 0;
  while i < jar.names.len() {
    let n: Str = jar.names[i];
    if compare.str_compare(n, name) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when `s` is a well-formed decimal integer: an optional '+' or '-'
// followed by 1..18 ASCII digits. Longer digit runs are rejected so that
// _int_value cannot overflow.
fn _is_int_text(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  let b0 = _byte(s, 0);
  if b0 == _COOKIE_PLUS || b0 == _COOKIE_MINUS {
    i = 1;
  }
  if i >= n {
    return false;
  }
  var digits = 0;
  while i < n {
    let b = _byte(s, i);
    if b < _COOKIE_DIGIT0 || b > _COOKIE_DIGIT9 {
      return false;
    }
    digits = digits + 1;
    if digits > 18 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Value of a string accepted by _is_int_text.
fn _int_value(s: Str) -> Int {
  let n = s.len();
  var i = 0;
  var neg = false;
  let b0 = _byte(s, 0);
  if b0 == _COOKIE_MINUS {
    neg = true;
    i = 1;
  } elif b0 == _COOKIE_PLUS {
    i = 1;
  }
  var v = 0;
  while i < n {
    v = v * 10 + (_byte(s, i) - _COOKIE_DIGIT0);
    i = i + 1;
  }
  if neg {
    return -v;
  }
  return v;
}

// Canonicalize a SameSite value: Strict/Lax/None match case-insensitively;
// any other value is returned verbatim.
fn _canonical_same_site(val: Str) -> Str {
  let low = string.str_lower(val);
  if compare.str_compare(low, "strict") == 0 {
    return "Strict";
  }
  if compare.str_compare(low, "lax") == 0 {
    return "Lax";
  }
  if compare.str_compare(low, "none") == 0 {
    return "None";
  }
  return val;
}

// --------------------------------------------------
//  Request Cookie parsing / serialization
// --------------------------------------------------

// Store one trimmed request segment into `jar`. Without '=' or with an empty
// name the segment is skipped; an already-present name is skipped (first
// occurrence wins).
fn _add_request_pair(jar: &mut CookieJar, seg: Str) {
  if seg.len() == 0 {
    return;
  }
  let eq = _find_byte(seg, _COOKIE_EQ);
  if eq < 0 {
    return;
  }
  let name = string.str_trim(string.str_slice(seg, 0, eq));
  if name.len() == 0 {
    return;
  }
  if _has_name(jar, name) {
    return;
  }
  let value = string.str_trim(string.str_slice(seg, eq + 1, seg.len()));
  jar.names.push(name);
  jar.values.push(value);
}

/// Parse a request `Cookie` header line into a jar.
/// Params: line - the header value (e.g. "a=1; b=2").
/// Returns: a fresh jar holding one entry per accepted "name=value" segment,
/// in first-seen order. Whitespace around names and values is trimmed; a
/// segment without '=' or with an empty trimmed name is skipped; the first
/// occurrence of a name wins and later duplicates are skipped.
/// Error case: none; malformed segments are silently skipped.
/// Complexity: O(line length * jar size) because duplicate detection scans the
/// names vector per segment; O(line length) with a hash index.
pub fn cookie_parse_request(line: Str) -> CookieJar {
  var jar = CookieJar{ names: Vec[Str].new(); values: Vec[Str].new(); };
  let len = line.len();
  var start = 0;
  var i = 0;
  while i <= len {
    if i == len || _byte(line, i) == _COOKIE_SEMI {
      let seg = string.str_trim(string.str_slice(line, start, i));
      _add_request_pair(&mut jar, seg);
      start = i + 1;
    }
    i = i + 1;
  }
  return jar;
}

/// Value of the first request cookie named `name`; None when absent. Names
/// are compared byte-exactly and case-sensitively (str_compare).
pub fn cookie_get(jar: &CookieJar, name: Str) -> Option[Str] {
  let lim = _limit(jar);
  var i = 0;
  while i < lim {
    let n: Str = jar.names[i];
    if compare.str_compare(n, name) == 0 {
      let v: Str = jar.values[i];
      return Some(v);
    }
    i = i + 1;
  }
  return None;
}

/// Number of entries in `jar` (min of the two parallel vector lengths, so a
/// hand-built ragged jar never over-counts).
pub fn cookie_count(jar: &CookieJar) -> Int {
  return _limit(jar);
}

/// Render the jar as a request `Cookie` header value: "a=1; b=2" in entry
/// order. An empty jar renders "".
pub fn cookie_serialize_request(jar: &CookieJar) -> Str {
  var sb = builder.sb_new();
  let lim = _limit(jar);
  var i = 0;
  while i < lim {
    if i > 0 {
      builder.sb_push_str(&mut sb, "; ");
    }
    let n: Str = jar.names[i];
    let v: Str = jar.values[i];
    builder.sb_push_str(&mut sb, n);
    builder.sb_push_str(&mut sb, "=");
    builder.sb_push_str(&mut sb, v);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Set-Cookie parsing / serialization
// --------------------------------------------------

// Apply one trimmed Set-Cookie attribute segment to `out`. Bare Secure and
// HttpOnly set their flags; Path, Domain, Max-Age and SameSite take the value
// after the first '='; every other name is ignored. Max-Age is applied only
// when its value is a well-formed integer; duplicate attributes are last-wins.
fn _apply_attribute(out: &mut SetCookie, seg: Str) {
  if seg.len() == 0 {
    return;
  }
  let eq = _find_byte(seg, _COOKIE_EQ);
  if eq < 0 {
    let flag = string.str_lower(seg);
    if compare.str_compare(flag, "secure") == 0 {
      out.secure = true;
      return;
    }
    if compare.str_compare(flag, "httponly") == 0 {
      out.http_only = true;
    }
    return;
  }
  let attr = string.str_lower(string.str_trim(string.str_slice(seg, 0, eq)));
  if attr.len() == 0 {
    return;
  }
  let val = string.str_trim(string.str_slice(seg, eq + 1, seg.len()));
  if compare.str_compare(attr, "path") == 0 {
    out.path = val;
    return;
  }
  if compare.str_compare(attr, "domain") == 0 {
    out.domain = val;
    return;
  }
  if compare.str_compare(attr, "max-age") == 0 {
    if _is_int_text(val) {
      out.max_age = _int_value(val);
    }
    return;
  }
  if compare.str_compare(attr, "samesite") == 0 {
    out.same_site = _canonical_same_site(val);
  }
}

/// Parse a `Set-Cookie` header line.
/// Params: line - the header value, e.g.
/// "sid=abc; Path=/; Max-Age=3600; Secure; HttpOnly; SameSite=Lax".
/// Returns: Ok(SetCookie) with the first "name=value" pair as the cookie and
/// the recognized attributes applied. Attribute names are matched
/// case-insensitively; unknown attributes are ignored. Max-Age takes an
/// optional sign and decimal digits and is ignored when malformed. SameSite
/// matches Strict/Lax/None case-insensitively and is stored canonically
/// ("Strict"/"Lax"/"None"); other values are kept raw. Duplicate attributes
/// are last-wins.
/// Error case: Err with a "cookie: " message when the first pair has no '='
/// ("cookie: missing name=value pair") or an empty name
/// ("cookie: empty cookie name").
/// Complexity: O(line length).
pub fn cookie_parse_set(line: Str) -> Result[SetCookie, Str] {
  let len = line.len();
  let first_end = _find_byte(line, _COOKIE_SEMI);
  var head = line;
  var attrs_start = len;
  if first_end >= 0 {
    head = string.str_slice(line, 0, first_end);
    attrs_start = first_end + 1;
  }
  head = string.str_trim(head);
  let eq = _find_byte(head, _COOKIE_EQ);
  if eq < 0 {
    return _err_set("cookie: missing name=value pair");
  }
  let name = string.str_trim(string.str_slice(head, 0, eq));
  if name.len() == 0 {
    return _err_set("cookie: empty cookie name");
  }
  let value = string.str_trim(string.str_slice(head, eq + 1, head.len()));
  var out = SetCookie{
    name: name;
    value: value;
    path: "";
    domain: "";
    max_age: -1;
    secure: false;
    http_only: false;
    same_site: "";
  };
  var start = attrs_start;
  var i = attrs_start;
  while i <= len {
    if i == len || _byte(line, i) == _COOKIE_SEMI {
      let seg = string.str_trim(string.str_slice(line, start, i));
      _apply_attribute(&mut out, seg);
      start = i + 1;
    }
    i = i + 1;
  }
  return _ok_set(out);
}

/// Render a SetCookie as a `Set-Cookie` header value: "name=value; Path=...;
/// Domain=...; Max-Age=N; Secure; HttpOnly; SameSite=Lax" in exactly that
/// order, omitting empty attributes and omitting Max-Age when it is negative.
/// name=value is always rendered, even for an empty value.
pub fn cookie_serialize_set(c: &SetCookie) -> Str {
  var sb = builder.sb_new();
  let name: Str = c.name;
  let value: Str = c.value;
  let path: Str = c.path;
  let domain: Str = c.domain;
  let same_site: Str = c.same_site;
  let max_age = c.max_age;
  let secure = c.secure;
  let http_only = c.http_only;
  builder.sb_push_str(&mut sb, name);
  builder.sb_push_str(&mut sb, "=");
  builder.sb_push_str(&mut sb, value);
  if path.len() > 0 {
    builder.sb_push_str(&mut sb, "; Path=");
    builder.sb_push_str(&mut sb, path);
  }
  if domain.len() > 0 {
    builder.sb_push_str(&mut sb, "; Domain=");
    builder.sb_push_str(&mut sb, domain);
  }
  if max_age >= 0 {
    builder.sb_push_str(&mut sb, "; Max-Age=");
    builder.sb_push_int(&mut sb, max_age);
  }
  if secure {
    builder.sb_push_str(&mut sb, "; Secure");
  }
  if http_only {
    builder.sb_push_str(&mut sb, "; HttpOnly");
  }
  if same_site.len() > 0 {
    builder.sb_push_str(&mut sb, "; SameSite=");
    builder.sb_push_str(&mut sb, same_site);
  }
  return builder.sb_to_str(&sb);
}
