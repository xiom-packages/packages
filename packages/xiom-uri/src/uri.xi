// XIOM -- xiom.uri: RFC 3986 URI parsing, formatting and component helpers
// Greenfield package: pure XIOM, no FFI, no file I/O (in-memory Str only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one URI reference is split into scheme, authority, path, query and
// fragment using the RFC 3986 generic syntax (appendix B algorithm). Absent
// components are the empty Str. The authority is kept raw -- userinfo, host
// and port are not separated at parse time; uri_host and uri_port do that on
// demand. Nothing is normalized, resolved or validated beyond the scheme.
//
// Grammar implemented by uri_parse (full statement in SPEC.md):
//   URI-reference = [ scheme ":" ] [ "//" authority ] path [ "?" query ]
//                   [ "#" fragment ]
//   scheme        = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
//   authority     = raw text up to the next "/", "?" or "#"
//   path          = raw text up to the next "?" or "#"
//   query         = raw text up to the next "#"
//   fragment      = raw remainder
//
// Decisions pinned by the conformance suite and SPEC.md:
//   * The scheme exists only when a ':' appears before the first '/', '?' or
//     '#' (RFC 3986 appendix B). A leading ':' is an empty scheme and is
//     rejected; a ':' after the first '/' is an ordinary path byte.
//   * An empty scheme and bad scheme characters are Err("uri: ..."); every
//     other input parses, including the empty string (all components empty).
//   * uri_to_string emits "//" exactly when the authority is non-empty, so
//     "http://" (empty authority) serializes as "http:" -- documented.
//   * Percent decode rejects truncated or non-hex escapes; '+' is always a
//     literal plus, never a space. Percent encode works byte-wise over UTF-8
//     and emits uppercase hex; encode_reserved=false keeps the RFC 3986
//     reserved set literal.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise via xiom.string.byte_at
//     and every raw byte is widened as `(string.byte_at(s, i) as Int) & 0xFF`
//     before comparison.
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str (one allocation per result Str).
//   * Ok/Err for Result[Uri, Str] and Result[Str, Str] are constructed only
//     in the tiny leaf helpers (_ok_uri/_err_uri/_ok_str/_err_str).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); this module never uses `==` on Str.

module xiom.uri

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed URI reference. Every component is "" when absent. The authority
/// is raw (userinfo/host/port undivided); see uri_host and uri_port.
pub type Uri = {
  scheme: Str;
  authority: Str;
  path: Str;
  query: Str;
  fragment: Str;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(u) for Result[Uri, Str].
fn _ok_uri(u: Uri) -> Result[Uri, Str] {
  return Ok(u);
}

// Err(m) for Result[Uri, Str].
fn _err_uri(m: Str) -> Result[Uri, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants and helpers
// --------------------------------------------------

const _URI_COLON: Int = 58;      // :
const _URI_SLASH: Int = 47;      // /
const _URI_QUESTION: Int = 63;   // ?
const _URI_HASH: Int = 35;       // #
const _URI_AT: Int = 64;         // @
const _URI_LBRACKET: Int = 91;   // [
const _URI_RBRACKET: Int = 93;   // ]
const _URI_EQ: Int = 61;         // =
const _URI_AMP: Int = 38;        // &
const _URI_PERCENT: Int = 37;    // %
const _URI_PLUS: Int = 43;       // +
const _URI_MINUS: Int = 45;      // -
const _URI_DOT: Int = 46;        // .
const _URI_UNDERSCORE: Int = 95; // _
const _URI_TILDE: Int = 126;     // ~

// One byte of `s` at `i`, zero-extended to Int (0..255).
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for an ASCII decimal digit byte.
fn _is_digit(b: Int) -> Bool {
  if b >= 48 && b <= 57 { return true; }
  return false;
}

// True for an ASCII letter byte.
fn _is_alpha(b: Int) -> Bool {
  if b >= 65 && b <= 90 { return true; }
  if b >= 97 && b <= 122 { return true; }
  return false;
}

// True for the scheme tail characters: ALPHA / DIGIT / "+" / "-" / ".".
fn _is_scheme_char(b: Int) -> Bool {
  if _is_alpha(b) { return true; }
  if _is_digit(b) { return true; }
  if b == _URI_PLUS || b == _URI_MINUS || b == _URI_DOT { return true; }
  return false;
}

// Index of the first byte among ':', '/', '?' and '#' in `s`, or -1.
fn _find_first_delim(s: Str) -> Int {
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if b == _URI_COLON || b == _URI_SLASH || b == _URI_QUESTION || b == _URI_HASH {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first `target` byte in s[start, end), or -1.
fn _find_byte_range(s: Str, start: Int, end: Int, target: Int) -> Int {
  var i = start;
  while i < end {
    if _byte(s, i) == target {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first byte among b1/b2/b3 in s[start, s.len()), or -1.
fn _find3(s: Str, start: Int, b1: Int, b2: Int, b3: Int) -> Int {
  let n = s.len();
  var i = start;
  while i < n {
    let b = _byte(s, i);
    if b == b1 || b == b2 || b == b3 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the last `target` byte in `s`, or -1.
fn _last_byte(s: Str, target: Int) -> Int {
  var i = s.len() - 1;
  while i >= 0 {
    if _byte(s, i) == target {
      return i;
    }
    i = i - 1;
  }
  return -1;
}

// True when s[0, end) is a well-formed scheme: ALPHA *( ALPHA / DIGIT /
// "+" / "-" / "." ), non-empty.
fn _scheme_ok(s: Str, end: Int) -> Bool {
  if end <= 0 { return false; }
  if !_is_alpha(_byte(s, 0)) { return false; }
  var i = 1;
  while i < end {
    if !_is_scheme_char(_byte(s, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Parsing / formatting
// --------------------------------------------------

/// Parse a URI reference into its five components.
/// Params: s - the URI-reference text (RFC 3986).
/// Returns: Ok(Uri). The scheme is the prefix before the first ':' only when
/// that ':' precedes the first '/', '?' or '#'; otherwise the scheme is "".
/// "//authority" is recognized right after the scheme separator and is raw
/// text up to the next '/', '?' or '#'; path stops at '?' or '#'; query
/// stops at '#'; the fragment takes the rest. No normalization happens.
/// Error case: Err("uri: empty scheme") for a leading ':' and
/// Err("uri: invalid scheme") when the scheme prefix before the first ':'
/// is not ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ).
/// Complexity: O(s.len()).
pub fn uri_parse(s: Str) -> Result[Uri, Str] {
  let n = s.len();
  var scheme = "";
  var pos = 0;
  let d = _find_first_delim(s);
  if d >= 0 && _byte(s, d) == _URI_COLON {
    if d == 0 {
      return _err_uri("uri: empty scheme");
    }
    if !_scheme_ok(s, d) {
      return _err_uri("uri: invalid scheme");
    }
    scheme = string.str_slice(s, 0, d);
    pos = d + 1;
  }
  var authority = "";
  if pos + 1 < n && _byte(s, pos) == _URI_SLASH && _byte(s, pos + 1) == _URI_SLASH {
    let a_start = pos + 2;
    var a_end = n;
    let stop = _find3(s, a_start, _URI_SLASH, _URI_QUESTION, _URI_HASH);
    if stop >= 0 {
      a_end = stop;
    }
    authority = string.str_slice(s, a_start, a_end);
    pos = a_end;
  }
  var path = "";
  var query = "";
  var fragment = "";
  let q = _find_byte_range(s, pos, n, _URI_QUESTION);
  let f = _find_byte_range(s, pos, n, _URI_HASH);
  if q >= 0 && (f < 0 || q < f) {
    path = string.str_slice(s, pos, q);
    if f >= 0 {
      query = string.str_slice(s, q + 1, f);
      fragment = string.str_slice(s, f + 1, n);
    } else {
      query = string.str_slice(s, q + 1, n);
    }
  } elif f >= 0 {
    path = string.str_slice(s, pos, f);
    fragment = string.str_slice(s, f + 1, n);
  } else {
    path = string.str_slice(s, pos, n);
  }
  var out = Uri{ scheme: scheme; authority: authority; path: path; query: query; fragment: fragment; };
  return _ok_uri(out);
}

/// Render a parsed URI back to text.
/// Params: u - the parsed URI.
/// Returns: scheme and ":" when the scheme is non-empty, "//" and the raw
/// authority when the authority is non-empty, then path, then "?" and query
/// when the query is non-empty, then "#" and fragment when the fragment is
/// non-empty. So parse -> to_string is lossless for every form whose
/// authority is either absent or non-empty ("//" with an EMPTY authority is
/// not preserved -- see SPEC.md section 10).
/// Error case: none.
/// Complexity: O(output length).
pub fn uri_to_string(u: &Uri) -> Str {
  let scheme: Str = u.scheme;
  let authority: Str = u.authority;
  let path: Str = u.path;
  let query: Str = u.query;
  let fragment: Str = u.fragment;
  var sb = builder.sb_new();
  if scheme.len() > 0 {
    builder.sb_push_str(&mut sb, scheme);
    builder.sb_push_str(&mut sb, ":");
  }
  if authority.len() > 0 {
    builder.sb_push_str(&mut sb, "//");
    builder.sb_push_str(&mut sb, authority);
  }
  builder.sb_push_str(&mut sb, path);
  if query.len() > 0 {
    builder.sb_push_str(&mut sb, "?");
    builder.sb_push_str(&mut sb, query);
  }
  if fragment.len() > 0 {
    builder.sb_push_str(&mut sb, "#");
    builder.sb_push_str(&mut sb, fragment);
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Percent-encoding
// --------------------------------------------------

// True for the RFC 3986 unreserved set: ALPHA / DIGIT / "-" / "." / "_" / "~".
fn _is_unreserved(b: Int) -> Bool {
  if _is_alpha(b) { return true; }
  if _is_digit(b) { return true; }
  if b == _URI_MINUS || b == _URI_DOT || b == _URI_UNDERSCORE || b == _URI_TILDE {
    return true;
  }
  return false;
}

// True for the RFC 3986 reserved set: gen-delims ":/?#[]@" and sub-delims
// "!$&'()*+,;=".
fn _is_reserved(b: Int) -> Bool {
  if b == _URI_COLON || b == _URI_SLASH || b == _URI_QUESTION || b == _URI_HASH {
    return true;
  }
  if b == _URI_LBRACKET || b == _URI_RBRACKET || b == _URI_AT { return true; }
  if b == 33 { return true; }  // !
  if b == 36 { return true; }  // $
  if b == _URI_AMP { return true; }   // &
  if b == 39 { return true; }  // '
  if b == 40 { return true; }  // (
  if b == 41 { return true; }  // )
  if b == 42 { return true; }  // *
  if b == _URI_PLUS { return true; }  // +
  if b == 44 { return true; }  // ,
  if b == 59 { return true; }  // ;
  if b == _URI_EQ { return true; }    // =
  return false;
}

// Numeric value of a hex digit byte (0-9, a-f, A-F); -1 for any other byte.
fn _hex_value(b: Int) -> Int {
  if b >= 48 && b <= 57 { return b - 48; }
  if b >= 97 && b <= 102 { return b - 87; }
  if b >= 65 && b <= 70 { return b - 55; }
  return -1;
}

// Uppercase hex digit byte for a nibble value (0..15).
fn _hex_upper(v: Int) -> UInt8 {
  if v < 10 { return (48 + v) as UInt8; }
  return (55 + v) as UInt8;
}

/// Decode %XX escapes (case-insensitive hex) in `s`.
/// Params: s - the percent-encoded text.
/// Returns: Ok(decoded). '+' is NOT decoded to a space; it stays '+'. Bytes
/// are emitted verbatim, so "%FF" yields a raw 0xFF byte and the result is
/// not re-validated as UTF-8.
/// Error case: Err("uri: truncated percent escape") when '%' is not followed
/// by two bytes, Err("uri: invalid percent escape") when either following
/// byte is not a hex digit.
/// Complexity: O(s.len()).
pub fn uri_percent_decode(s: Str) -> Result[Str, Str] {
  let n = s.len();
  var out = builder.sb_new();
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if b == _URI_PERCENT {
      if i + 2 >= n {
        return _err_str("uri: truncated percent escape");
      }
      let hi = _hex_value(_byte(s, i + 1));
      let lo = _hex_value(_byte(s, i + 2));
      if hi < 0 || lo < 0 {
        return _err_str("uri: invalid percent escape");
      }
      builder.sb_push_byte(&mut out, ((hi << 4) | lo) as UInt8);
      i = i + 3;
    } else {
      builder.sb_push_byte(&mut out, b as UInt8);
      i = i + 1;
    }
  }
  return _ok_str(builder.sb_to_str(&out));
}

/// Percent-encode the UTF-8 bytes of `s`.
/// Params: s - the text to encode; encode_reserved - when false, the RFC 3986
/// reserved set (:/?#[]@!$&'()*+,;=) is kept literal in addition to the
/// unreserved set; when true only unreserved bytes stay literal.
/// Returns: the encoded text; every encoded byte becomes "%XX" with uppercase
/// hex. Non-ASCII input is encoded byte-wise, one %XX per UTF-8 byte.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn uri_percent_encode(s: Str, encode_reserved: Bool) -> Str {
  let n = s.len();
  var out = builder.sb_new();
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    var keep = false;
    if _is_unreserved(b) {
      keep = true;
    } elif !encode_reserved && _is_reserved(b) {
      keep = true;
    }
    if keep {
      builder.sb_push_byte(&mut out, b as UInt8);
    } else {
      builder.sb_push_byte(&mut out, _URI_PERCENT as UInt8);
      builder.sb_push_byte(&mut out, _hex_upper(b >> 4));
      builder.sb_push_byte(&mut out, _hex_upper(b & 15));
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Authority components
// --------------------------------------------------

// Authority text with any userinfo removed (everything through the last '@').
fn _host_part(a: Str) -> Str {
  let at = _last_byte(a, _URI_AT);
  if at >= 0 {
    return string.str_slice(a, at + 1, a.len());
  }
  return a;
}

/// Host of the authority: userinfo (before the last '@') and port (after ':')
/// removed. IPv6 brackets are kept.
/// Params: u - the parsed URI.
/// Returns: the host text, or "" when the authority is empty. An IPv6
/// literal keeps its brackets ("[::1]"). Bracketless IPv6 is not supported:
/// for non-bracket text everything before the LAST ':' is host and the rest
/// is a port candidate.
/// Error case: none.
/// Complexity: O(authority length).
pub fn uri_host(u: &Uri) -> Str {
  let authority: Str = u.authority;
  let hp = _host_part(authority);
  let n = hp.len();
  if n > 0 && _byte(hp, 0) == _URI_LBRACKET {
    let close = _find_byte_range(hp, 0, n, _URI_RBRACKET);
    if close >= 0 {
      return string.str_slice(hp, 0, close + 1);
    }
    return hp;
  }
  let colon = _last_byte(hp, _URI_COLON);
  if colon >= 0 {
    return string.str_slice(hp, 0, colon);
  }
  return hp;
}

/// Port of the authority as an Int.
/// Params: u - the parsed URI.
/// Returns: the port number when a ':' (or, for an IPv6 literal, "]:") is
/// followed by 1..18 decimal digits; -1 when the port is absent, empty or
/// contains any non-digit. No range check against 65535 is performed.
/// Error case: none.
/// Complexity: O(authority length).
pub fn uri_port(u: &Uri) -> Int {
  let authority: Str = u.authority;
  let hp = _host_part(authority);
  let n = hp.len();
  var start = -1;
  if n > 0 && _byte(hp, 0) == _URI_LBRACKET {
    let close = _find_byte_range(hp, 0, n, _URI_RBRACKET);
    if close < 0 {
      return -1;
    }
    if close + 1 >= n || _byte(hp, close + 1) != _URI_COLON {
      return -1;
    }
    start = close + 2;
  } else {
    let colon = _last_byte(hp, _URI_COLON);
    if colon < 0 {
      return -1;
    }
    start = colon + 1;
  }
  if start >= n {
    return -1;
  }
  var digits = 0;
  var v = 0;
  var i = start;
  while i < n {
    let b = _byte(hp, i);
    if !_is_digit(b) {
      return -1;
    }
    digits = digits + 1;
    if digits > 18 {
      return -1;
    }
    v = v * 10 + (b - 48);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Query lookup
// --------------------------------------------------

/// First value for `name` in the query string.
/// Params: u - the parsed URI; name - the raw parameter name to match.
/// Returns: Some(value) for the first "name=value" pair whose name matches
/// byte-exactly (case-sensitive, before any percent-decoding); a pair without
/// '=' yields Some(""). The value is percent-decoded; when decoding fails the
/// raw value is returned literally. Pairs are separated by '&'; empty
/// segments are skipped. None when the name is absent or the query is empty.
/// Error case: none.
/// Complexity: O(query length).
pub fn uri_query_get(u: &Uri, name: Str) -> Option[Str] {
  let q: Str = u.query;
  let n = q.len();
  var start = 0;
  var i = 0;
  while i <= n {
    if i == n || _byte(q, i) == _URI_AMP {
      if i > start {
        let eq = _find_byte_range(q, start, i, _URI_EQ);
        var pname = "";
        var pvalue = "";
        if eq >= 0 {
          pname = string.str_slice(q, start, eq);
          pvalue = string.str_slice(q, eq + 1, i);
        } else {
          pname = string.str_slice(q, start, i);
        }
        if compare.str_compare(pname, name) == 0 {
          let dec = uri_percent_decode(pvalue);
          match dec {
            Ok(v) => { return Some(v); },
            Err(_) => { return Some(pvalue); },
          }
        }
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return None;
}

/// True when the URI has a non-empty scheme.
/// Params: u - the parsed URI.
/// Returns: true for an absolute URI (scheme present), false for a relative
/// reference.
/// Error case: none.
/// Complexity: O(1).
pub fn uri_is_absolute(u: &Uri) -> Bool {
  let scheme: Str = u.scheme;
  return scheme.len() > 0;
}
