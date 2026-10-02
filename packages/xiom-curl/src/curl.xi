// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.curl: a pure HTTP client MODEL (no sockets, no FFI, no TLS).
//
// Scope (SPEC.md has the exact subset and the full error catalog):
//   * URL model: absolute-URL lexical parsing (scheme / host / port / path /
//     query / fragment), RFC 3986 normalization (lowercasing, default-port
//     elision, dot-segment removal), reference resolution and percent
//     encoding with byte offsets on every decode error.
//   * Request model: method canonicalization + predicates, ordered header
//     list with case-insensitive lookup, body presence, origin-form target
//     and a deterministic wire encoder.
//   * Redirect model: 301/302/303/307/308 followability, method rewriting,
//     body-retention rule, bounded depth with a stable error.
//   * Cookie model: Set-Cookie subset (name=value + Domain / Path / Max-Age /
//     Secure / HttpOnly; Expires accepted and ignored), domain and path
//     matching, Max-Age expiry, a parallel-vector jar and a Cookie header
//     builder.
//   * Auth helpers: HTTP Basic (stdlib base64) and Bearer header shapes,
//     scheme detection, Basic decode and credential splitting.
//   * Retry policy: deterministic exponential backoff with a cap, status
//     classification, Retry-After delta-seconds parsing and effective delay.
//   * Connection-pool model: keep-alive accounting per (scheme, host, port)
//     slot with max-idle-per-host and max-total bounds.
//   * Response model: builder, header list, keep-alive decision,
//     Content-Length accessor, a bounded response-head parser and HTTP
//     status/envelope classification.
//
// Purity: every function is deterministic, IO-free and transport-free.
// Non-goals: sockets, DNS, TLS, proxying, HTTP/2, chunked transfer decoding,
// streaming, form bodies, date arithmetic (see SPEC.md).
//
// v0.62.2 notes that shaped this module:
//   * free functions only; no self methods, no lambdas, no Vec[StructType]
//     (parallel Vec fields in the header list, cookie jar and pool);
//   * every byte read from a Str or Vec[UInt8] is widened once with
//     `(byte_at(..) as Int) & 0xFF` before comparison or arithmetic;
//   * Str equality never uses `==`; everything goes through
//     xiom.string.compare.str_compare / str_eq_ignore_case, and Str values
//     read out of structs, Vec[Str] or Result fields are bound to typed
//     locals first;
//   * Ok/Err for Result[...] are constructed only in the tiny leaf helpers
//     `_c_ok_*` / `_c_err_*` below;
//   * no `&mut Int` scalar parameters (counters are threaded through
//     returns); `&mut` write-through is used only for Vec pushes and Vec
//     element writes inside &mut struct parameters;
//   * `&struct.field` is bound to a local before it reaches a `&Vec[...]` or
//     `&HeaderList` parameter;
//   * every scan loop is bounded by the input length and has a single
//     advancing counter; no `break`/`continue`;
//   * xiom.string.builder output is never fed a NUL byte: percent escapes
//     that decode to 0x00 are rejected with a byte-offset error.

module xiom.curl

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;
use xiom.encoding.base64;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// Default TCP port for the "http" scheme.
pub const CURL_DEFAULT_PORT_HTTP: Int = 80;
/// Default TCP port for the "https" scheme.
pub const CURL_DEFAULT_PORT_HTTPS: Int = 443;
/// Default redirect depth bound used by callers of curl_redirect_next.
pub const CURL_MAX_REDIRECTS: Int = 10;
/// Envelope class: not a valid HTTP status.
pub const CURL_ENV_NONE: Int = 0;
/// Envelope class: 1xx.
pub const CURL_ENV_INFORMATIONAL: Int = 1;
/// Envelope class: 2xx.
pub const CURL_ENV_SUCCESS: Int = 2;
/// Envelope class: 3xx.
pub const CURL_ENV_REDIRECT: Int = 3;
/// Envelope class: 4xx.
pub const CURL_ENV_CLIENT_ERROR: Int = 4;
/// Envelope class: 5xx.
pub const CURL_ENV_SERVER_ERROR: Int = 5;

// --------------------------------------------------
//  Result constructors (leaf helpers; see the module header)
// --------------------------------------------------

fn _c_ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _c_err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _c_ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _c_err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

fn _c_ok_url(v: Url) -> Result[Url, Str] {
  return Ok(v);
}

fn _c_err_url(m: Str) -> Result[Url, Str] {
  return Err(m);
}

fn _c_ok_request(v: Request) -> Result[Request, Str] {
  return Ok(v);
}

fn _c_err_request(m: Str) -> Result[Request, Str] {
  return Err(m);
}

fn _c_ok_response(v: Response) -> Result[Response, Str] {
  return Ok(v);
}

fn _c_err_response(m: Str) -> Result[Response, Str] {
  return Err(m);
}

fn _c_ok_cookie(v: Cookie) -> Result[Cookie, Str] {
  return Ok(v);
}

fn _c_err_cookie(m: Str) -> Result[Cookie, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte and Str helpers
// --------------------------------------------------

// Widened byte read: always 0..255 (trap 3 / trap 13 domain discipline).
fn _c_by(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Str equality; never `==` on Str values.
fn _c_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Case-insensitive ASCII equality.
fn _c_eq_ci(a: Str, b: Str) -> Bool {
  return compare.str_eq_ignore_case(a, b);
}

fn _c_starts(s: Str, prefix: Str) -> Bool {
  return string.str_starts_with(s, prefix);
}

fn _c_is_digit(b: Int) -> Bool {
  if b >= 48 && b <= 57 { return true; }
  return false;
}

fn _c_is_alpha(b: Int) -> Bool {
  if b >= 65 && b <= 90 { return true; }
  if b >= 97 && b <= 122 { return true; }
  return false;
}

fn _c_is_alnum(b: Int) -> Bool {
  if _c_is_alpha(b) { return true; }
  return _c_is_digit(b);
}

// Numeric value of a hex digit byte (0-9, A-F, a-f); -1 for any other byte.
fn _c_hex_value(b: Int) -> Int {
  if b >= 48 && b <= 57 { return b - 48; }
  if b >= 65 && b <= 70 { return b - 55; }
  if b >= 97 && b <= 102 { return b - 87; }
  return -1;
}

// Uppercase hex digit byte for a nibble value (0..15).
fn _c_hex_upper(n: Int) -> UInt8 {
  if n < 10 {
    return (48 + n) as UInt8;
  }
  return (55 + n) as UInt8;
}

// RFC 3986 unreserved set: ALPHA / DIGIT / '-' '.' '_' '~'.
fn _c_unreserved(b: Int) -> Bool {
  if _c_is_alnum(b) { return true; }
  if b == 45 || b == 46 || b == 95 || b == 126 { return true; }
  return false;
}

// RFC 7230 tchar set (header names, methods, cookie names).
fn _c_is_tchar(b: Int) -> Bool {
  if _c_is_alnum(b) { return true; }
  if b == 33 || b == 35 || b == 36 || b == 37 || b == 38 { return true; }
  if b == 39 || b == 42 || b == 43 || b == 45 || b == 46 { return true; }
  if b == 94 || b == 95 || b == 96 || b == 124 || b == 126 { return true; }
  return false;
}

// First byte equal to ch in [from, to); -1 when absent.
fn _c_find_range(s: Str, ch: Int, from: Int, to: Int) -> Int {
  var i = from;
  while i < to {
    if _c_by(s, i) == ch { return i; }
    i = i + 1;
  }
  return -1;
}

// Last byte equal to ch in [from, to); -1 when absent.
fn _c_find_last_range(s: Str, ch: Int, from: Int, to: Int) -> Int {
  var i = to - 1;
  while i >= from {
    if _c_by(s, i) == ch { return i; }
    i = i - 1;
  }
  return -1;
}

// First occurrence of needle at or after from; -1 when absent.
fn _c_find_seq(s: Str, needle: Str, from: Int) -> Int {
  let n = s.len();
  let m = needle.len();
  if m == 0 || from < 0 { return -1; }
  var i = from;
  while i + m <= n {
    if _c_eq(string.str_slice(s, i, i + m), needle) { return i; }
    i = i + 1;
  }
  return -1;
}

// Index of the CR of the first CRLF at or after from; -1 when absent.
fn _c_find_crlf(s: Str, from: Int) -> Int {
  let n = s.len();
  var i = from;
  while i + 1 < n {
    if _c_by(s, i) == 13 && _c_by(s, i + 1) == 10 { return i; }
    i = i + 1;
  }
  return -1;
}

// Trim SP / HTAB from both ends.
fn _c_trim_ows(s: Str) -> Str {
  let n = s.len();
  var a = 0;
  var going = true;
  while a < n && going {
    let b = _c_by(s, a);
    if b == 32 || b == 9 { a = a + 1; } else { going = false; }
  }
  var e = n;
  going = true;
  while e > a && going {
    let b = _c_by(s, e - 1);
    if b == 32 || b == 9 { e = e - 1; } else { going = false; }
  }
  return string.str_slice(s, a, e);
}

// --------------------------------------------------
//  Percent-encoding (RFC 3986; component scope)
// --------------------------------------------------

/// Percent-encode every non-unreserved byte of `s` (UTF-8 bytes pass through
/// raw when they are unreserved; each other byte becomes %XX uppercase hex).
/// Space becomes %20. Empty input yields "". Total; O(s.len()).
pub fn curl_percent_encode_component(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _c_by(s, i);
    if _c_unreserved(b) {
      out.push(b as UInt8);
    } else {
      out.push(37 as UInt8);
      out.push(_c_hex_upper(b >> 4));
      out.push(_c_hex_upper(b & 15));
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Decode %XX escapes (case-insensitive) byte-wise; '+' stays a literal plus.
/// Errors: "curl: truncated percent escape at offset N",
/// "curl: bad percent escape at offset N",
/// "curl: percent escape decodes to NUL at offset N" (a decoded 0x00 cannot
/// live in a NUL-terminated XIOM Str). O(s.len()).
pub fn curl_percent_decode_component(s: Str) -> Result[Str, Str] {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _c_by(s, i);
    if b == 37 {
      if i + 2 >= n {
        return _c_err_str("curl: truncated percent escape at offset " + convert.int_to_string(i));
      }
      let hi = _c_hex_value(_c_by(s, i + 1));
      let lo = _c_hex_value(_c_by(s, i + 2));
      if hi < 0 || lo < 0 {
        return _c_err_str("curl: bad percent escape at offset " + convert.int_to_string(i));
      }
      let v = (hi << 4) | lo;
      if v == 0 {
        return _c_err_str("curl: percent escape decodes to NUL at offset " + convert.int_to_string(i));
      }
      out.push(v as UInt8);
      i = i + 3;
    } else {
      out.push(b as UInt8);
      i = i + 1;
    }
  }
  return _c_ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  URL model
// --------------------------------------------------

/// Absolute URL in lexical form. `scheme` and `host` are stored lowercase;
/// `port_present` distinguishes an explicit port from the scheme default;
/// `path` is stored as written (curl_url_normalize makes it "/" when empty);
/// `query` / `fragment` exclude their leading delimiter.
pub type Url = {
  scheme: Str;
  host: Str;
  port: Int;
  port_present: Bool;
  path: Str;
  query: Str;
  query_present: Bool;
  fragment: Str;
  fragment_present: Bool;
}

/// Default port for a scheme (case-insensitive): 80 http, 443 https, 0 for
/// any other scheme (unknown). O(1).
pub fn curl_scheme_default_port(scheme: Str) -> Int {
  if _c_eq_ci(scheme, "http") { return CURL_DEFAULT_PORT_HTTP; }
  if _c_eq_ci(scheme, "https") { return CURL_DEFAULT_PORT_HTTPS; }
  return 0;
}

// Validate a scheme, lowercase it. Errors carry an offset into the scheme.
fn _c_check_scheme(s: Str) -> Result[Str, Str] {
  let n = s.len();
  if n == 0 { return _c_err_str("curl: empty scheme"); }
  if !_c_is_alpha(_c_by(s, 0)) {
    return _c_err_str("curl: scheme must start with a letter");
  }
  var i = 1;
  while i < n {
    let b = _c_by(s, i);
    if _c_is_alnum(b) || b == 43 || b == 45 || b == 46 {
      i = i + 1;
    } else {
      return _c_err_str("curl: invalid scheme character at offset " + convert.int_to_string(i));
    }
  }
  return _c_ok_str(string.str_lower(s));
}

// Validate a host reg-name subset (ALPHA / DIGIT / '-' '.' '_'); offsets are
// absolute (base is the offset of the host inside the URL).
fn _c_check_host(s: Str, base: Int) -> Result[Str, Str] {
  let n = s.len();
  if n == 0 { return _c_err_str("curl: empty host"); }
  var i = 0;
  while i < n {
    let b = _c_by(s, i);
    if _c_is_alnum(b) || b == 45 || b == 46 || b == 95 {
      i = i + 1;
    } else {
      return _c_err_str("curl: invalid host character at offset " + convert.int_to_string(base + i));
    }
  }
  return _c_ok_str(s);
}

// Parse a decimal port, 0..65535; offsets are absolute.
fn _c_parse_port(ps: Str, base: Int) -> Result[Int, Str] {
  let n = ps.len();
  if n == 0 {
    return _c_err_int("curl: empty port at offset " + convert.int_to_string(base));
  }
  var v = 0;
  var i = 0;
  while i < n {
    let b = _c_by(ps, i);
    if !_c_is_digit(b) {
      return _c_err_int("curl: invalid port at offset " + convert.int_to_string(base));
    }
    v = v * 10 + (b - 48);
    if v > 65535 {
      return _c_err_int("curl: port out of range at offset " + convert.int_to_string(base));
    }
    i = i + 1;
  }
  return _c_ok_int(v);
}

// Path bytes: visible ASCII except the already-consumed '?' and '#'.
fn _c_check_path(s: Str, base: Int) -> Result[Str, Str] {
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _c_by(s, i);
    if b < 33 || b > 126 {
      return _c_err_str("curl: url path has invalid character at offset " + convert.int_to_string(base + i));
    }
    i = i + 1;
  }
  return _c_ok_str(s);
}

fn _c_check_query(s: Str, base: Int) -> Result[Str, Str] {
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _c_by(s, i);
    if b < 33 || b > 126 {
      return _c_err_str("curl: url query has invalid character at offset " + convert.int_to_string(base + i));
    }
    i = i + 1;
  }
  return _c_ok_str(s);
}

fn _c_check_fragment(s: Str, base: Int) -> Result[Str, Str] {
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _c_by(s, i);
    if b < 33 || b > 126 {
      return _c_err_str("curl: url fragment has invalid character at offset " + convert.int_to_string(base + i));
    }
    i = i + 1;
  }
  return _c_ok_str(s);
}

/// Parse an absolute URL (`scheme://host[:port][/path][?query][#fragment]`).
/// Scheme and host are lowercased; the port must be decimal 0..65535. Userinfo
/// (`@`) and IPv6 literals (`[`) are rejected (documented non-goals). Every
/// error begins with "curl: ". O(s.len()).
pub fn curl_url_parse(s: Str) -> Result[Url, Str] {
  let n = s.len();
  if n == 0 { return _c_err_url("curl: empty url"); }
  let sep = _c_find_seq(s, "://", 0);
  if sep < 1 {
    return _c_err_url("curl: url must be absolute (scheme://...)");
  }
  let sc = _c_check_scheme(string.str_slice(s, 0, sep));
  if !sc.is_ok { return _c_err_url(sc.error); }
  let scheme_lc: Str = sc.value;
  let ai = sep + 3;
  var aend = n;
  var j = ai;
  var hit = false;
  while j < n && !hit {
    let b = _c_by(s, j);
    if b == 47 || b == 63 || b == 35 {
      aend = j;
      hit = true;
    } else {
      j = j + 1;
    }
  }
  let at = _c_find_range(s, 64, ai, aend);
  if at >= 0 { return _c_err_url("curl: userinfo not supported"); }
  let bracket = _c_find_range(s, 91, ai, aend);
  if bracket >= 0 { return _c_err_url("curl: IPv6 literals not supported"); }
  let colon = _c_find_range(s, 58, ai, aend);
  var host_raw = "";
  var port = 0;
  var port_present = false;
  if colon >= 0 {
    host_raw = string.str_slice(s, ai, colon);
    let pr = _c_parse_port(string.str_slice(s, colon + 1, aend), colon + 1);
    if !pr.is_ok { return _c_err_url(pr.error); }
    port = pr.value;
    port_present = true;
  } else {
    host_raw = string.str_slice(s, ai, aend);
  }
  let hc = _c_check_host(host_raw, ai);
  if !hc.is_ok { return _c_err_url(hc.error); }
  let host_raw2: Str = hc.value;
  let qpos_all = _c_find_range(s, 63, aend, n);
  let hpos_all = _c_find_range(s, 35, aend, n);
  var qpos = qpos_all;
  if qpos >= 0 && hpos_all >= 0 && hpos_all < qpos { qpos = -1; }
  var path_end = n;
  if hpos_all >= 0 && hpos_all < path_end { path_end = hpos_all; }
  if qpos >= 0 && qpos < path_end { path_end = qpos; }
  let path_raw = string.str_slice(s, aend, path_end);
  let pc = _c_check_path(path_raw, aend);
  if !pc.is_ok { return _c_err_url(pc.error); }
  var query = "";
  var query_present = false;
  if qpos >= 0 {
    var qend = n;
    if hpos_all >= 0 && hpos_all > qpos { qend = hpos_all; }
    let query_raw = string.str_slice(s, qpos + 1, qend);
    let qc = _c_check_query(query_raw, qpos + 1);
    if !qc.is_ok { return _c_err_url(qc.error); }
    query = qc.value;
    query_present = true;
  }
  var fragment = "";
  var fragment_present = false;
  if hpos_all >= 0 {
    let fragment_raw = string.str_slice(s, hpos_all + 1, n);
    let fc = _c_check_fragment(fragment_raw, hpos_all + 1);
    if !fc.is_ok { return _c_err_url(fc.error); }
    fragment = fc.value;
    fragment_present = true;
  }
  let u = Url{
    scheme: scheme_lc;
    host: string.str_lower(host_raw2);
    port: port;
    port_present: port_present;
    path: path_raw;
    query: query;
    query_present: query_present;
    fragment: fragment;
    fragment_present: fragment_present;
  };
  return _c_ok_url(u);
}

/// Drop the last path segment of `out` (used by dot-segment removal).
fn _c_drop_last_segment(out: Str) -> Str {
  let n = out.len();
  let slash = _c_find_last_range(out, 47, 0, n);
  if slash < 0 { return ""; }
  return string.str_slice(out, 0, slash);
}

/// RFC 3986 section 5.2.4 dot-segment removal (single pass, no I/O).
pub fn curl_url_remove_dot_segments(path: Str) -> Str {
  var out: Str = "";
  var p: Str = path;
  let max_iter = path.len() + 2;
  var guard = 0;
  while p.len() > 0 && guard <= max_iter {
    guard = guard + 1;
    if _c_starts(p, "../") {
      p = string.str_slice(p, 3, p.len());
    } elif _c_starts(p, "./") {
      p = string.str_slice(p, 2, p.len());
    } elif _c_starts(p, "/./") {
      p = "/" + string.str_slice(p, 3, p.len());
    } elif _c_eq(p, "/.") {
      p = "/";
    } elif _c_starts(p, "/../") {
      p = "/" + string.str_slice(p, 4, p.len());
      out = _c_drop_last_segment(out);
    } elif _c_eq(p, "/..") {
      p = "/";
      out = _c_drop_last_segment(out);
    } elif _c_eq(p, ".") || _c_eq(p, "..") {
      p = "";
    } else {
      var take = p.len();
      let slash = _c_find_range(p, 47, 1, p.len());
      if slash >= 0 { take = slash; }
      out = out + string.str_slice(p, 0, take);
      p = string.str_slice(p, take, p.len());
    }
  }
  return out;
}

/// Normalize a URL: lowercase scheme/host, elide a default port, make an
/// empty path "/", remove dot segments, drop an empty fragment, keep query.
pub fn curl_url_normalize(u: &Url) -> Url {
  let sch: Str = string.str_lower(u.scheme);
  let host: Str = string.str_lower(u.host);
  var port: Int = u.port;
  var port_present: Bool = u.port_present;
  let dflt = curl_scheme_default_port(sch);
  if port_present && dflt > 0 && port == dflt {
    port = 0;
    port_present = false;
  }
  var path: Str = u.path;
  if path.len() == 0 { path = "/"; }
  path = curl_url_remove_dot_segments(path);
  if path.len() == 0 { path = "/"; }
  let query: Str = u.query;
  let query_present: Bool = u.query_present;
  let fragment: Str = u.fragment;
  var fragment_present: Bool = u.fragment_present;
  if fragment_present && fragment.len() == 0 { fragment_present = false; }
  let nu = Url{
    scheme: sch;
    host: host;
    port: port;
    port_present: port_present;
    path: path;
    query: query;
    query_present: query_present;
    fragment: fragment;
    fragment_present: fragment_present;
  };
  return nu;
}

/// Render a URL as `scheme://host[:port]path[?query][#fragment]`, exactly as
/// stored (no default-port elision; use curl_url_normalize first if wanted).
pub fn curl_url_to_string(u: &Url) -> Str {
  let sch: Str = u.scheme;
  let host: Str = u.host;
  let path: Str = u.path;
  let query: Str = u.query;
  let fragment: Str = u.fragment;
  var out: Str = sch + "://" + host;
  if u.port_present {
    out = out + ":" + convert.int_to_string(u.port);
  }
  out = out + path;
  if u.query_present { out = out + "?" + query; }
  if u.fragment_present { out = out + "#" + fragment; }
  return out;
}

/// Effective port: the explicit port when present, else the scheme default
/// (0 for an unknown scheme).
pub fn curl_url_effective_port(u: &Url) -> Int {
  if u.port_present { return u.port; }
  return curl_scheme_default_port(u.scheme);
}

/// True when both URLs share scheme (case-insensitive), host
/// (case-insensitive) and effective port.
pub fn curl_url_same_origin(a: &Url, b: &Url) -> Bool {
  if !_c_eq_ci(a.scheme, b.scheme) { return false; }
  if !_c_eq_ci(a.host, b.host) { return false; }
  if curl_url_effective_port(a) != curl_url_effective_port(b) { return false; }
  return true;
}

// True when `reference` starts with a scheme per RFC 3986 section 5.2.2.
fn _c_has_scheme(reference: Str) -> Bool {
  let n = reference.len();
  let colon = _c_find_range(reference, 58, 0, n);
  if colon <= 0 { return false; }
  let slash = _c_find_range(reference, 47, 0, n);
  if slash >= 0 && slash < colon { return false; }
  let q = _c_find_range(reference, 63, 0, n);
  if q >= 0 && q < colon { return false; }
  let h = _c_find_range(reference, 35, 0, n);
  if h >= 0 && h < colon { return false; }
  let sc = _c_check_scheme(string.str_slice(reference, 0, colon));
  return sc.is_ok;
}

/// Resolve a URI reference against an absolute base URL (RFC 3986 section 5.2
/// subset: absolute, network-path `//`, absolute-path, relative-path,
/// query-only, fragment-only and empty references). The result is normalized.
pub fn curl_url_resolve(base: &Url, reference: Str) -> Result[Url, Str] {
  let n = reference.len();
  if n == 0 {
    let b = curl_url_normalize(base);
    let r = Url{
      scheme: b.scheme;
      host: b.host;
      port: b.port;
      port_present: b.port_present;
      path: b.path;
      query: b.query;
      query_present: b.query_present;
      fragment: "";
      fragment_present: false;
    };
    return _c_ok_url(r);
  }
  if _c_has_scheme(reference) {
    let r = curl_url_parse(reference);
    if !r.is_ok { return r; }
    let u: Url = r.value;
    return _c_ok_url(curl_url_normalize(&u));
  }
  if _c_starts(reference, "//") {
    let sch: Str = base.scheme;
    let r = curl_url_parse(sch + ":" + reference);
    if !r.is_ok { return r; }
    let u: Url = r.value;
    return _c_ok_url(curl_url_normalize(&u));
  }
  let hpos = _c_find_range(reference, 35, 0, n);
  var fragment = "";
  var fragment_present = false;
  var main = reference;
  if hpos >= 0 {
    fragment = string.str_slice(reference, hpos + 1, n);
    fragment_present = true;
    main = string.str_slice(reference, 0, hpos);
  }
  let qpos = _c_find_range(main, 63, 0, main.len());
  var query = "";
  var query_present = false;
  var rpath = main;
  if qpos >= 0 {
    query = string.str_slice(main, qpos + 1, main.len());
    query_present = true;
    rpath = string.str_slice(main, 0, qpos);
  }
  let bnorm = curl_url_normalize(base);
  var path = rpath;
  if _c_starts(rpath, "/") {
    path = curl_url_remove_dot_segments(rpath);
  } elif rpath.len() == 0 {
    path = bnorm.path;
    if !query_present {
      query = bnorm.query;
      query_present = bnorm.query_present;
    }
  } else {
    let base_path: Str = bnorm.path;
    let slash = _c_find_last_range(base_path, 47, 0, base_path.len());
    var prefix: Str = "";
    if slash >= 0 {
      prefix = string.str_slice(base_path, 0, slash + 1);
    }
    path = curl_url_remove_dot_segments(prefix + rpath);
  }
  if path.len() == 0 { path = "/"; }
  let r = Url{
    scheme: bnorm.scheme;
    host: bnorm.host;
    port: bnorm.port;
    port_present: bnorm.port_present;
    path: path;
    query: query;
    query_present: query_present;
    fragment: fragment;
    fragment_present: fragment_present;
  };
  return _c_ok_url(r);
}

// --------------------------------------------------
//  Header lists (parallel vectors; alive[i] gates slot i)
// --------------------------------------------------

/// Ordered header list. `names[i]` pairs with `values[i]`; `alive[i]` is 1
/// for a live entry and 0 after removal (the slot stays allocated).
pub type HeaderList = {
  names: Vec[Str];
  values: Vec[Str];
  alive: Vec[Int];
}

/// New empty header list. O(1).
pub fn curl_headers_new() -> HeaderList {
  return HeaderList{
    names: Vec[Str].new();
    values: Vec[Str].new();
    alive: Vec[Int].new();
  };
}

// Validate a header name: non-empty RFC 7230 token.
fn _c_check_header_name(name: Str) -> Result[Str, Str] {
  let n = name.len();
  if n == 0 { return _c_err_str("curl: empty header name"); }
  var i = 0;
  while i < n {
    if !_c_is_tchar(_c_by(name, i)) {
      return _c_err_str("curl: header name has invalid character at offset " + convert.int_to_string(i));
    }
    i = i + 1;
  }
  return _c_ok_str(name);
}

// Validate a header value: HTAB or visible ASCII 0x20..0x7E only.
fn _c_check_header_value(value: Str) -> Result[Str, Str] {
  let n = value.len();
  var i = 0;
  while i < n {
    let b = _c_by(value, i);
    if !(b == 9 || (b >= 32 && b <= 126)) {
      return _c_err_str("curl: header value has invalid character at offset " + convert.int_to_string(i));
    }
    i = i + 1;
  }
  return _c_ok_str(value);
}

fn _c_hdr_count(h: &HeaderList) -> Int {
  let n = h.alive.len();
  var c = 0;
  var i = 0;
  while i < n {
    let a: Int = h.alive[i];
    if a == 1 { c = c + 1; }
    i = i + 1;
  }
  return c;
}

// Physical index of the logical (live) entry; -1 when out of range.
fn _c_hdr_phys(h: &HeaderList, logical: Int) -> Int {
  let n = h.alive.len();
  var seen = 0;
  var i = 0;
  while i < n {
    let a: Int = h.alive[i];
    if a == 1 {
      if seen == logical { return i; }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return -1;
}

// Physical index of the first live entry whose name matches case-insensitively.
fn _c_hdr_find(h: &HeaderList, name: Str) -> Int {
  let n = h.names.len();
  var i = 0;
  while i < n {
    let a: Int = h.alive[i];
    if a == 1 {
      let nm: Str = h.names[i];
      if _c_eq_ci(nm, name) { return i; }
    }
    i = i + 1;
  }
  return -1;
}

/// Append one header. Name must be a non-empty token and the value visible
/// ASCII (HTAB allowed); duplicates are allowed. Errors:
/// "curl: empty header name",
/// "curl: header name has invalid character at offset N",
/// "curl: header value has invalid character at offset N".
pub fn curl_headers_add(h: &mut HeaderList, name: Str, value: Str) -> Result[Str, Str] {
  let nv = _c_check_header_name(name);
  if !nv.is_ok { return nv; }
  let vv = _c_check_header_value(value);
  if !vv.is_ok { return vv; }
  h.names.push(name);
  h.values.push(value);
  h.alive.push(1);
  return _c_ok_str("");
}

/// Live header count. O(n).
pub fn curl_headers_count(h: &HeaderList) -> Int {
  return _c_hdr_count(h);
}

/// Name of the i-th live header ("" when out of range). O(n).
pub fn curl_headers_name_at(h: &HeaderList, i: Int) -> Str {
  let p = _c_hdr_phys(h, i);
  if p < 0 { return ""; }
  let s: Str = h.names[p];
  return s;
}

/// Value of the i-th live header ("" when out of range). O(n).
pub fn curl_headers_value_at(h: &HeaderList, i: Int) -> Str {
  let p = _c_hdr_phys(h, i);
  if p < 0 { return ""; }
  let s: Str = h.values[p];
  return s;
}

/// First live value for `name` (case-insensitive):
/// Ok(value) or Err("curl: header not found: <name>").
pub fn curl_headers_get(h: &HeaderList, name: Str) -> Result[Str, Str] {
  let p = _c_hdr_find(h, name);
  if p < 0 {
    return _c_err_str("curl: header not found: " + name);
  }
  let s: Str = h.values[p];
  return _c_ok_str(s);
}

/// Membership predicate (case-insensitive name). O(n).
pub fn curl_headers_has(h: &HeaderList, name: Str) -> Bool {
  let p = _c_hdr_find(h, name);
  if p < 0 { return false; }
  return true;
}

/// Mark every live entry named `name` (case-insensitive) dead; returns the
/// number removed. O(n).
pub fn curl_headers_remove(h: &mut HeaderList, name: Str) -> Int {
  let n = h.names.len();
  var removed = 0;
  var i = 0;
  while i < n {
    let a: Int = h.alive[i];
    if a == 1 {
      let nm: Str = h.names[i];
      if _c_eq_ci(nm, name) {
        h.alive[i] = 0;
        removed = removed + 1;
      }
    }
    i = i + 1;
  }
  return removed;
}

/// True when the three parallel vectors have equal lengths (drift guard).
pub fn curl_headers_consistent(h: &HeaderList) -> Bool {
  let n = h.names.len();
  if h.values.len() != n { return false; }
  if h.alive.len() != n { return false; }
  return true;
}

// --------------------------------------------------
//  Request model
// --------------------------------------------------

/// HTTP request model. `body_present` distinguishes an absent body from an
/// explicitly empty one; headers are ordered and may repeat.
pub type Request = {
  method: Str;
  url: Url;
  version: Str;
  headers: HeaderList;
  body: Str;
  body_present: Bool;
}

/// "GET".
pub fn curl_method_get() -> Str { return "GET"; }
/// "HEAD".
pub fn curl_method_head() -> Str { return "HEAD"; }
/// "POST".
pub fn curl_method_post() -> Str { return "POST"; }
/// "PUT".
pub fn curl_method_put() -> Str { return "PUT"; }
/// "DELETE".
pub fn curl_method_delete() -> Str { return "DELETE"; }
/// "PATCH".
pub fn curl_method_patch() -> Str { return "PATCH"; }
/// "OPTIONS".
pub fn curl_method_options() -> Str { return "OPTIONS"; }
/// "TRACE".
pub fn curl_method_trace() -> Str { return "TRACE"; }

/// "HTTP/1.0".
pub fn curl_version_http_1_0() -> Str { return "HTTP/1.0"; }
/// "HTTP/1.1".
pub fn curl_version_http_1_1() -> Str { return "HTTP/1.1"; }

/// Supported wire versions: "HTTP/1.0" and "HTTP/1.1" only.
pub fn curl_version_is_supported(v: Str) -> Bool {
  if _c_eq(v, "HTTP/1.0") { return true; }
  if _c_eq(v, "HTTP/1.1") { return true; }
  return false;
}

/// True when `m` is a non-empty RFC 7230 token of at most 32 bytes.
pub fn curl_method_is_valid(m: Str) -> Bool {
  let n = m.len();
  if n == 0 || n > 32 { return false; }
  var i = 0;
  while i < n {
    if !_c_is_tchar(_c_by(m, i)) { return false; }
    i = i + 1;
  }
  return true;
}

/// Uppercase and validate a method token. Errors:
/// "curl: empty method", "curl: method has invalid character at offset N".
pub fn curl_method_canonical(m: Str) -> Result[Str, Str] {
  let n = m.len();
  if n == 0 { return _c_err_str("curl: empty method"); }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b = _c_by(m, i);
    if !_c_is_tchar(b) {
      return _c_err_str("curl: method has invalid character at offset " + convert.int_to_string(i));
    }
    if b >= 97 && b <= 122 {
      out.push((b - 32) as UInt8);
    } else {
      out.push(b as UInt8);
    }
    i = i + 1;
  }
  return _c_ok_str(builder.sb_to_str(&out));
}

/// GET / HEAD / OPTIONS / TRACE (case-insensitive).
pub fn curl_method_is_safe(m: Str) -> Bool {
  if _c_eq_ci(m, "GET") { return true; }
  if _c_eq_ci(m, "HEAD") { return true; }
  if _c_eq_ci(m, "OPTIONS") { return true; }
  if _c_eq_ci(m, "TRACE") { return true; }
  return false;
}

/// Safe methods plus PUT and DELETE (case-insensitive).
pub fn curl_method_is_idempotent(m: Str) -> Bool {
  if curl_method_is_safe(m) { return true; }
  if _c_eq_ci(m, "PUT") { return true; }
  if _c_eq_ci(m, "DELETE") { return true; }
  return false;
}

/// Build a request. The method is canonicalized (uppercased) and validated,
/// and the version must be "HTTP/1.0" or "HTTP/1.1". Errors:
/// "curl: empty method", "curl: method has invalid character at offset N",
/// "curl: unsupported version: <v>".
pub fn curl_request_new(method: Str, url: Url, version: Str) -> Result[Request, Str] {
  let mc = curl_method_canonical(method);
  if !mc.is_ok { return _c_err_request(mc.error); }
  if !curl_version_is_supported(version) {
    return _c_err_request("curl: unsupported version: " + version);
  }
  let mm: Str = mc.value;
  let r = Request{
    method: mm;
    url: url;
    version: version;
    headers: curl_headers_new();
    body: "";
    body_present: false;
  };
  return _c_ok_request(r);
}

/// Append a header (delegates the validation to curl_headers_add).
pub fn curl_request_add_header(r: &mut Request, name: Str, value: Str) -> Result[Str, Str] {
  let res = curl_headers_add(&mut r.headers, name, value);
  return res;
}

/// Remove headers by name (case-insensitive); returns the number removed.
pub fn curl_request_remove_header(r: &mut Request, name: Str) -> Int {
  return curl_headers_remove(&mut r.headers, name);
}

/// First header value or Err("curl: header not found: <name>").
pub fn curl_request_header_get(r: &Request, name: Str) -> Result[Str, Str] {
  let h: HeaderList = r.headers;
  return curl_headers_get(&h, name);
}

/// Live header count.
pub fn curl_request_headers_count(r: &Request) -> Int {
  let h: HeaderList = r.headers;
  return curl_headers_count(&h);
}

/// Name of the i-th live header ("" when out of range).
pub fn curl_request_header_name_at(r: &Request, i: Int) -> Str {
  let h: HeaderList = r.headers;
  return curl_headers_name_at(&h, i);
}

/// Value of the i-th live header ("" when out of range).
pub fn curl_request_header_value_at(r: &Request, i: Int) -> Str {
  let h: HeaderList = r.headers;
  return curl_headers_value_at(&h, i);
}

/// Set the body and mark it present (an empty body is still present).
pub fn curl_request_set_body(r: &mut Request, body: Str) {
  r.body = body;
  r.body_present = true;
}

/// Mark the body absent (the content is kept in the field but not encoded).
pub fn curl_request_clear_body(r: &mut Request) {
  r.body_present = false;
}

/// Request method.
pub fn curl_request_method(r: &Request) -> Str {
  let s: Str = r.method;
  return s;
}

/// Request version.
pub fn curl_request_version(r: &Request) -> Str {
  let s: Str = r.version;
  return s;
}

/// Request URL (struct copy).
pub fn curl_request_url(r: &Request) -> Url {
  let u: Url = r.url;
  return u;
}

/// Request body bytes.
pub fn curl_request_body(r: &Request) -> Str {
  let s: Str = r.body;
  return s;
}

/// Body length in bytes.
pub fn curl_request_body_len(r: &Request) -> Int {
  let s: Str = r.body;
  return s.len();
}

/// True when a body is present (even an empty one).
pub fn curl_request_has_body(r: &Request) -> Bool {
  return r.body_present;
}

/// True when every parallel header pair is aligned.
pub fn curl_request_consistent(r: &Request) -> Bool {
  let h: HeaderList = r.headers;
  return curl_headers_consistent(&h);
}

/// Origin-form target: path ("" becomes "/") plus "?query" when present.
pub fn curl_request_target(r: &Request) -> Str {
  let u: Url = r.url;
  var target: Str = u.path;
  if target.len() == 0 { target = "/"; }
  if u.query_present { target = target + "?" + u.query; }
  return target;
}

/// Deterministic wire encoder: request line, live headers in order, blank
/// line, body when present. No Host header is synthesized (the caller adds
/// one); lines are CRLF-terminated.
pub fn curl_request_encode(r: &Request) -> Str {
  let m: Str = r.method;
  let v: Str = r.version;
  let h: HeaderList = r.headers;
  let target = curl_request_target(r);
  var out: Str = m + " " + target + " " + v + "\r\n";
  let cnt = curl_headers_count(&h);
  var i = 0;
  while i < cnt {
    let nm = curl_headers_name_at(&h, i);
    let vl = curl_headers_value_at(&h, i);
    out = out + nm + ": " + vl + "\r\n";
    i = i + 1;
  }
  out = out + "\r\n";
  if r.body_present {
    let b: Str = r.body;
    out = out + b;
  }
  return out;
}

// --------------------------------------------------
//  Redirect model
// --------------------------------------------------

/// True for 301, 302, 303, 307 and 308.
pub fn curl_redirect_is_followable(status: Int) -> Bool {
  if status == 301 || status == 302 || status == 303 { return true; }
  if status == 307 || status == 308 { return true; }
  return false;
}

/// The follow-up method for a redirect status:
/// 303 -> GET (HEAD stays HEAD); 301/302 -> GET when the method was POST,
/// otherwise unchanged; 307/308 -> unchanged.
pub fn curl_redirect_rewrite_method(status: Int, method: Str) -> Str {
  if status == 303 {
    if _c_eq_ci(method, "HEAD") { return "HEAD"; }
    return "GET";
  }
  if status == 301 || status == 302 {
    if _c_eq_ci(method, "POST") { return "GET"; }
    return method;
  }
  return method;
}

/// True when the follow-up request keeps the original request body: only
/// 307/308 preserve it (301/302/303 drop it in this model).
pub fn curl_redirect_keeps_body(status: Int) -> Bool {
  if status == 307 || status == 308 { return true; }
  return false;
}

/// One redirect step: returns the follow-up method, or an error when the
/// status is not followable ("curl: status is not a redirect: <n>") or the
/// depth bound is reached ("curl: redirect depth exceeded (max <n>)").
pub fn curl_redirect_next_method(status: Int, method: Str, depth: Int, max_depth: Int) -> Result[Str, Str] {
  if !curl_redirect_is_followable(status) {
    return _c_err_str("curl: status is not a redirect: " + convert.int_to_string(status));
  }
  if depth >= max_depth {
    return _c_err_str("curl: redirect depth exceeded (max " + convert.int_to_string(max_depth) + ")");
  }
  return _c_ok_str(curl_redirect_rewrite_method(status, method));
}

// --------------------------------------------------
//  Cookie model
// --------------------------------------------------

/// Parsed cookie. `max_age` is meaningful only when `max_age_present` is
/// true; `created_at` is the caller-supplied clock at parse time (seconds);
/// `host_only` cookies are sent only to the exact host.
pub type Cookie = {
  name: Str;
  value: Str;
  domain: Str;
  path: Str;
  host_only: Bool;
  secure: Bool;
  http_only: Bool;
  max_age: Int;
  max_age_present: Bool;
  created_at: Int;
}

// RFC 6265 cookie-octet value subset; `base` makes the reported offset
// absolute into the Set-Cookie header.
fn _c_check_cookie_value(value: Str, base: Int) -> Result[Str, Str] {
  let n = value.len();
  var i = 0;
  while i < n {
    let b = _c_by(value, i);
    let ok = b == 33 || (b >= 35 && b <= 43) || (b >= 45 && b <= 58)
      || (b >= 60 && b <= 91) || (b >= 93 && b <= 126);
    if !ok {
      return _c_err_str("curl: cookie value has invalid character at offset " + convert.int_to_string(base + i));
    }
    i = i + 1;
  }
  return _c_ok_str(value);
}

fn _c_check_cookie_name(name: Str) -> Result[Str, Str] {
  let n = name.len();
  if n == 0 { return _c_err_str("curl: cookie name is empty"); }
  var i = 0;
  while i < n {
    if !_c_is_tchar(_c_by(name, i)) {
      return _c_err_str("curl: cookie name has invalid character at offset " + convert.int_to_string(i));
    }
    i = i + 1;
  }
  return _c_ok_str(name);
}

// Suffix match used by the cookie Domain attribute: host == domain or host
// ends with ".<domain>". IPv4-looking hosts require exact equality.
fn _c_cookie_domain_ok(domain: Str, host: Str) -> Bool {
  if _c_eq(domain, host) { return true; }
  if _c_is_ipv4_like(host) { return false; }
  let suffix = "." + domain;
  if string.str_ends_with(host, suffix) { return true; }
  return false;
}

// True when host looks like an IPv4 address (digits and dots, at least one
// dot, no letters).
fn _c_is_ipv4_like(host: Str) -> Bool {
  let n = host.len();
  if n == 0 { return false; }
  var dots = 0;
  var i = 0;
  while i < n {
    let b = _c_by(host, i);
    if b == 46 { dots = dots + 1; }
    elif !_c_is_digit(b) { return false; }
    i = i + 1;
  }
  if dots < 1 { return false; }
  return true;
}

// Default path per RFC 6265 section 5.1.4.
pub fn curl_cookie_default_path(req_path: Str) -> Str {
  let n = req_path.len();
  if n == 0 || _c_by(req_path, 0) != 47 { return "/"; }
  let slash = _c_find_last_range(req_path, 47, 0, n);
  if slash <= 0 { return "/"; }
  return string.str_slice(req_path, 0, slash);
}

// Parse a signed decimal Max-Age value (optional '-', 1+ digits, bounded).
fn _c_parse_signed_seconds(s: Str) -> Result[Int, Str] {
  let n = s.len();
  var i = 0;
  var neg = false;
  if n > 0 && _c_by(s, 0) == 45 {
    neg = true;
    i = 1;
  }
  if i >= n { return _c_err_int("curl: invalid Max-Age"); }
  var v = 0;
  while i < n {
    let b = _c_by(s, i);
    if !_c_is_digit(b) { return _c_err_int("curl: invalid Max-Age"); }
    v = v * 10 + (b - 48);
    if v > 2147483647 { return _c_err_int("curl: invalid Max-Age"); }
    i = i + 1;
  }
  if neg { v = 0 - v; }
  return _c_ok_int(v);
}

/// Parse a Set-Cookie header subset:
/// `name=value[; Domain=d][; Path=p][; Max-Age=n][; Secure][; HttpOnly]`.
/// Attribute names are case-insensitive; unknown attributes and `Expires`
/// are accepted and ignored (no date arithmetic). A leading '.' in Domain is
/// stripped, and Domain must match `host`. `req_path` supplies the default
/// path when no valid Path attribute is present. Errors carry byte offsets
/// into `set_cookie`. O(n).
pub fn curl_cookie_parse(set_cookie: Str, host: Str, req_path: Str, now: Int) -> Result[Cookie, Str] {
  let n = set_cookie.len();
  if n == 0 { return _c_err_cookie("curl: empty set-cookie"); }
  if host.len() == 0 { return _c_err_cookie("curl: empty cookie host"); }
  let host_lc = string.str_lower(host);
  let semi = _c_find_range(set_cookie, 59, 0, n);
  var pair = set_cookie;
  var attrs_start = n;
  if semi >= 0 {
    pair = string.str_slice(set_cookie, 0, semi);
    attrs_start = semi + 1;
  }
  let eq = _c_find_range(pair, 61, 0, pair.len());
  if eq <= 0 {
    return _c_err_cookie("curl: set-cookie must be name=value");
  }
  let name = string.str_slice(pair, 0, eq);
  let value = string.str_slice(pair, eq + 1, pair.len());
  let nc = _c_check_cookie_name(name);
  if !nc.is_ok { return _c_err_cookie(nc.error); }
  let vc = _c_check_cookie_value(value, eq + 1);
  if !vc.is_ok { return _c_err_cookie(vc.error); }
  var domain = host_lc;
  var host_only = true;
  var path = "";
  var path_set = false;
  var secure = false;
  var http_only = false;
  var max_age = 0;
  var max_age_present = false;
  var i = attrs_start;
  while i < n {
    var skipping = true;
    while i < n && skipping {
      let b = _c_by(set_cookie, i);
      if b == 32 || b == 9 || b == 59 {
        i = i + 1;
      } else {
        skipping = false;
      }
    }
    if i < n {
      var ne = i;
      var name_done = false;
      while ne < n && !name_done {
        let b = _c_by(set_cookie, ne);
        if b == 61 || b == 59 || b == 32 || b == 9 {
          name_done = true;
        } else {
          ne = ne + 1;
        }
      }
      let aname = string.str_slice(set_cookie, i, ne);
      var aval = "";
      var has_val = false;
      if ne < n {
        if _c_by(set_cookie, ne) == 61 {
          var ve = ne + 1;
          var val_done = false;
          while ve < n && !val_done {
            if _c_by(set_cookie, ve) == 59 {
              val_done = true;
            } else {
              ve = ve + 1;
            }
          }
          aval = _c_trim_ows(string.str_slice(set_cookie, ne + 1, ve));
          has_val = true;
          i = ve + 1;
        } else {
          i = ne;
        }
      } else {
        i = n;
      }
      if _c_eq_ci(aname, "Domain") && has_val {
        var d = aval;
        if d.len() > 0 && _c_by(d, 0) == 46 {
          d = string.str_slice(d, 1, d.len());
        }
        d = string.str_lower(d);
        if d.len() == 0 {
          return _c_err_cookie("curl: empty cookie domain");
        }
        if !_c_cookie_domain_ok(d, host_lc) {
          return _c_err_cookie("curl: cookie domain does not match host: " + d);
        }
        domain = d;
        host_only = false;
      } elif _c_eq_ci(aname, "Path") && has_val {
        if aval.len() > 0 && _c_by(aval, 0) == 47 {
          path = aval;
          path_set = true;
        }
      } elif _c_eq_ci(aname, "Max-Age") && has_val {
        let ma = _c_parse_signed_seconds(aval);
        if !ma.is_ok { return _c_err_cookie(ma.error); }
        max_age = ma.value;
        max_age_present = true;
      } elif _c_eq_ci(aname, "Secure") {
        secure = true;
      } elif _c_eq_ci(aname, "HttpOnly") {
        http_only = true;
      }
    }
  }
  if !path_set {
    path = curl_cookie_default_path(req_path);
  }
  let c = Cookie{
    name: name;
    value: value;
    domain: domain;
    path: path;
    host_only: host_only;
    secure: secure;
    http_only: http_only;
    max_age: max_age;
    max_age_present: max_age_present;
    created_at: now;
  };
  return _c_ok_cookie(c);
}

/// Host match: exact for host-only cookies, suffix for Domain cookies.
pub fn curl_cookie_domain_match(c: &Cookie, host: Str) -> Bool {
  let d: Str = c.domain;
  let h = string.str_lower(host);
  if c.host_only { return _c_eq(d, h); }
  return _c_cookie_domain_ok(d, h);
}

/// RFC 6265 section 5.1.4 path match.
pub fn curl_cookie_path_match(c: &Cookie, req_path: Str) -> Bool {
  let cp: Str = c.path;
  if _c_eq(cp, req_path) { return true; }
  if string.str_starts_with(req_path, cp) {
    if cp.len() > 0 && _c_by(cp, cp.len() - 1) == 47 { return true; }
    if req_path.len() > cp.len() && _c_by(req_path, cp.len()) == 47 { return true; }
  }
  return false;
}

/// True when Max-Age is present and exhausted at `now` (Max-Age <= 0 always
/// means expired).
pub fn curl_cookie_is_expired(c: &Cookie, now: Int) -> Bool {
  if !c.max_age_present { return false; }
  let ma: Int = c.max_age;
  if ma <= 0 { return true; }
  let created: Int = c.created_at;
  if now >= created + ma { return true; }
  return false;
}

/// Domain + path + expiry match.
pub fn curl_cookie_matches(c: &Cookie, host: Str, path: Str, now: Int) -> Bool {
  if !curl_cookie_domain_match(c, host) { return false; }
  if !curl_cookie_path_match(c, path) { return false; }
  if curl_cookie_is_expired(c, now) { return false; }
  return true;
}

/// Match plus the Secure rule: a Secure cookie is sendable only over https.
pub fn curl_cookie_sendable(c: &Cookie, host: Str, path: Str, scheme: Str, now: Int) -> Bool {
  if !curl_cookie_matches(c, host, path, now) { return false; }
  if c.secure && !_c_eq_ci(scheme, "https") { return false; }
  return true;
}

/// Render a cookie as a Set-Cookie value:
/// `name=value[; Domain=d][; Path=p][; Max-Age=n][; Secure][; HttpOnly]`.
pub fn curl_cookie_to_string(c: &Cookie) -> Str {
  let nm: Str = c.name;
  let vl: Str = c.value;
  let d: Str = c.domain;
  let p: Str = c.path;
  var out: Str = nm + "=" + vl;
  if !c.host_only { out = out + "; Domain=" + d; }
  out = out + "; Path=" + p;
  if c.max_age_present {
    let ma: Int = c.max_age;
    out = out + "; Max-Age=" + convert.int_to_string(ma);
  }
  if c.secure { out = out + "; Secure"; }
  if c.http_only { out = out + "; HttpOnly"; }
  return out;
}

// --------------------------------------------------
//  Cookie jar (parallel vectors; alive[i] gates slot i)
// --------------------------------------------------

/// Cookie jar. Every parallel vector has the same length; `alive[i]` is 1
/// for a live cookie and 0 after replacement or expiry.
pub type CookieJar = {
  names: Vec[Str];
  values: Vec[Str];
  domains: Vec[Str];
  paths: Vec[Str];
  host_only: Vec[Int];
  secure: Vec[Int];
  http_only: Vec[Int];
  max_ages: Vec[Int];
  max_age_present: Vec[Int];
  created: Vec[Int];
  alive: Vec[Int];
}

/// New empty jar. O(1).
pub fn curl_jar_new() -> CookieJar {
  return CookieJar{
    names: Vec[Str].new();
    values: Vec[Str].new();
    domains: Vec[Str].new();
    paths: Vec[Str].new();
    host_only: Vec[Int].new();
    secure: Vec[Int].new();
    http_only: Vec[Int].new();
    max_ages: Vec[Int].new();
    max_age_present: Vec[Int].new();
    created: Vec[Int].new();
    alive: Vec[Int].new();
  };
}

// Physical index of a live cookie with the same (name, domain, path); the
// name and path compare case-sensitively, the domain case-insensitively.
fn _c_jar_find(j: &CookieJar, name: Str, domain: Str, path: Str) -> Int {
  let n = j.names.len();
  var i = 0;
  while i < n {
    let a: Int = j.alive[i];
    if a == 1 {
      let nm: Str = j.names[i];
      let dm: Str = j.domains[i];
      let pp: Str = j.paths[i];
      if _c_eq(nm, name) && _c_eq_ci(dm, domain) && _c_eq(pp, path) {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Add a cookie; a live cookie with the same (name, domain, path) is
/// replaced (the new entry is appended, so replacement moves it to the end
/// of the iteration order). O(n).
pub fn curl_jar_add(j: &mut CookieJar, c: &Cookie) {
  let nm: Str = c.name;
  let vl: Str = c.value;
  let dm: Str = c.domain;
  let pp: Str = c.path;
  let p = _c_jar_find(j, nm, dm, pp);
  if p >= 0 {
    j.alive[p] = 0;
  }
  var ho = 0;
  if c.host_only { ho = 1; }
  var se = 0;
  if c.secure { se = 1; }
  var ho2 = 0;
  if c.http_only { ho2 = 1; }
  var map = 0;
  if c.max_age_present { map = 1; }
  let ma: Int = c.max_age;
  let cr: Int = c.created_at;
  j.names.push(nm);
  j.values.push(vl);
  j.domains.push(dm);
  j.paths.push(pp);
  j.host_only.push(ho);
  j.secure.push(se);
  j.http_only.push(ho2);
  j.max_ages.push(ma);
  j.max_age_present.push(map);
  j.created.push(cr);
  j.alive.push(1);
}

fn _c_jar_expired_at(j: &CookieJar, i: Int, now: Int) -> Bool {
  let map: Int = j.max_age_present[i];
  if map != 1 { return false; }
  let ma: Int = j.max_ages[i];
  if ma <= 0 { return true; }
  let cr: Int = j.created[i];
  if now >= cr + ma { return true; }
  return false;
}

/// Live cookie count. O(n).
pub fn curl_jar_count(j: &CookieJar) -> Int {
  let n = j.alive.len();
  var c = 0;
  var i = 0;
  while i < n {
    let a: Int = j.alive[i];
    if a == 1 { c = c + 1; }
    i = i + 1;
  }
  return c;
}

/// Mark expired live cookies dead; returns the number removed. O(n).
pub fn curl_jar_remove_expired(j: &mut CookieJar, now: Int) -> Int {
  let n = j.alive.len();
  var removed = 0;
  var i = 0;
  while i < n {
    let a: Int = j.alive[i];
    if a == 1 && _c_jar_expired_at(j, i, now) {
      j.alive[i] = 0;
      removed = removed + 1;
    }
    i = i + 1;
  }
  return removed;
}

/// Mark every cookie dead (the slots stay allocated). O(n).
pub fn curl_jar_clear(j: &mut CookieJar) {
  let n = j.alive.len();
  var i = 0;
  while i < n {
    j.alive[i] = 0;
    i = i + 1;
  }
}

/// Physical slot count (live plus dead).
pub fn curl_jar_slots(j: &CookieJar) -> Int {
  return j.names.len();
}

/// True when every parallel vector has the same length.
pub fn curl_jar_consistent(j: &CookieJar) -> Bool {
  let n = j.names.len();
  if j.values.len() != n { return false; }
  if j.domains.len() != n { return false; }
  if j.paths.len() != n { return false; }
  if j.host_only.len() != n { return false; }
  if j.secure.len() != n { return false; }
  if j.http_only.len() != n { return false; }
  if j.max_ages.len() != n { return false; }
  if j.max_age_present.len() != n { return false; }
  if j.created.len() != n { return false; }
  if j.alive.len() != n { return false; }
  return true;
}

/// True when physical slot i is live.
pub fn curl_jar_alive_at(j: &CookieJar, i: Int) -> Bool {
  if i < 0 || i >= j.alive.len() { return false; }
  let a: Int = j.alive[i];
  if a == 1 { return true; }
  return false;
}

/// Cookie name at physical slot i ("" when out of range).
pub fn curl_jar_name_at(j: &CookieJar, i: Int) -> Str {
  if i < 0 || i >= j.names.len() { return ""; }
  let s: Str = j.names[i];
  return s;
}

/// Cookie value at physical slot i ("" when out of range).
pub fn curl_jar_value_at(j: &CookieJar, i: Int) -> Str {
  if i < 0 || i >= j.values.len() { return ""; }
  let s: Str = j.values[i];
  return s;
}

/// Cookie domain at physical slot i ("" when out of range).
pub fn curl_jar_domain_at(j: &CookieJar, i: Int) -> Str {
  if i < 0 || i >= j.domains.len() { return ""; }
  let s: Str = j.domains[i];
  return s;
}

/// Cookie path at physical slot i ("" when out of range).
pub fn curl_jar_path_at(j: &CookieJar, i: Int) -> Str {
  if i < 0 || i >= j.paths.len() { return ""; }
  let s: Str = j.paths[i];
  return s;
}

/// Max-Age at physical slot i (0 when absent or out of range).
pub fn curl_jar_max_age_at(j: &CookieJar, i: Int) -> Int {
  if i < 0 || i >= j.max_ages.len() { return 0; }
  return j.max_ages[i];
}

/// True when physical slot i carries a Max-Age.
pub fn curl_jar_max_age_present_at(j: &CookieJar, i: Int) -> Bool {
  if i < 0 || i >= j.max_age_present.len() { return false; }
  let v: Int = j.max_age_present[i];
  if v == 1 { return true; }
  return false;
}

/// True when physical slot i is Secure.
pub fn curl_jar_secure_at(j: &CookieJar, i: Int) -> Bool {
  if i < 0 || i >= j.secure.len() { return false; }
  let v: Int = j.secure[i];
  if v == 1 { return true; }
  return false;
}

/// True when physical slot i is HttpOnly.
pub fn curl_jar_httponly_at(j: &CookieJar, i: Int) -> Bool {
  if i < 0 || i >= j.http_only.len() { return false; }
  let v: Int = j.http_only[i];
  if v == 1 { return true; }
  return false;
}

/// True when physical slot i is host-only.
pub fn curl_jar_host_only_at(j: &CookieJar, i: Int) -> Bool {
  if i < 0 || i >= j.host_only.len() { return false; }
  let v: Int = j.host_only[i];
  if v == 1 { return true; }
  return false;
}

/// Creation clock of physical slot i (0 when out of range).
pub fn curl_jar_created_at(j: &CookieJar, i: Int) -> Int {
  if i < 0 || i >= j.created.len() { return 0; }
  return j.created[i];
}

/// Build the Cookie header value for a request: live, matching, unexpired
/// cookies in slot order, joined with "; "; no sent cookies yields "".
pub fn curl_jar_cookie_header(j: &CookieJar, host: Str, path: Str, scheme: Str, now: Int) -> Str {
  let n = j.names.len();
  var out: Str = "";
  var i = 0;
  while i < n {
    let a: Int = j.alive[i];
    if a == 1 {
      let nm: Str = j.names[i];
      let vl: Str = j.values[i];
      let dm: Str = j.domains[i];
      let pp: Str = j.paths[i];
      let ho: Int = j.host_only[i];
      let se: Int = j.secure[i];
      let c = Cookie{
        name: nm;
        value: vl;
        domain: dm;
        path: pp;
        host_only: ho == 1;
        secure: se == 1;
        http_only: false;
        max_age: j.max_ages[i];
        max_age_present: j.max_age_present[i] == 1;
        created_at: j.created[i];
      };
      if curl_cookie_sendable(&c, host, path, scheme, now) {
        if out.len() > 0 { out = out + "; "; }
        out = out + nm + "=" + vl;
      }
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Auth helpers
// --------------------------------------------------

// Non-empty token with no whitespace/CTL (Bearer token subset).
fn _c_check_bearer_token(token: Str) -> Result[Str, Str] {
  let n = token.len();
  if n == 0 { return _c_err_str("curl: empty token"); }
  var i = 0;
  while i < n {
    let b = _c_by(token, i);
    if b < 33 || b > 126 {
      return _c_err_str("curl: token has invalid character at offset " + convert.int_to_string(i));
    }
    i = i + 1;
  }
  return _c_ok_str(token);
}

// Basic user: visible ASCII except ':'.
fn _c_check_basic_user(user: Str) -> Result[Str, Str] {
  let n = user.len();
  var i = 0;
  while i < n {
    let b = _c_by(user, i);
    if b == 58 || b < 32 || b > 126 {
      return _c_err_str("curl: basic user has invalid character at offset " + convert.int_to_string(i));
    }
    i = i + 1;
  }
  return _c_ok_str(user);
}

// Basic password: visible ASCII (':' allowed).
fn _c_check_basic_password(password: Str) -> Result[Str, Str] {
  let n = password.len();
  var i = 0;
  while i < n {
    let b = _c_by(password, i);
    if b < 32 || b > 126 {
      return _c_err_str("curl: basic password has invalid character at offset " + convert.int_to_string(i));
    }
    i = i + 1;
  }
  return _c_ok_str(password);
}

/// `Authorization: Basic <base64(user:password)>` header value (no header
/// name). Errors: "curl: basic user has invalid character at offset N",
/// "curl: basic password has invalid character at offset N".
pub fn curl_auth_basic_header(user: Str, password: Str) -> Result[Str, Str] {
  let uc = _c_check_basic_user(user);
  if !uc.is_ok { return uc; }
  let pc = _c_check_basic_password(password);
  if !pc.is_ok { return pc; }
  let creds = user + ":" + password;
  return _c_ok_str("Basic " + base64.base64_encode_str(creds));
}

/// `Authorization: Bearer <token>` header value (no header name). The token
/// must be non-empty visible ASCII without whitespace. Errors:
/// "curl: empty token", "curl: token has invalid character at offset N".
pub fn curl_auth_bearer_header(token: Str) -> Result[Str, Str] {
  let tc = _c_check_bearer_token(token);
  if !tc.is_ok { return tc; }
  return _c_ok_str("Bearer " + token);
}

/// Scheme token of an Authorization value (bytes before the first SP/HTAB);
/// "" for an empty value.
pub fn curl_auth_scheme(h: Str) -> Str {
  let n = h.len();
  var i = 0;
  while i < n {
    let b = _c_by(h, i);
    if b == 32 || b == 9 {
      return string.str_slice(h, 0, i);
    }
    i = i + 1;
  }
  return h;
}

/// Credentials part of an Authorization value: everything after the scheme
/// and separating whitespace, with surrounding whitespace trimmed.
pub fn curl_auth_token(h: Str) -> Str {
  let n = h.len();
  var j = 0;
  var scheme_done = false;
  while j < n && !scheme_done {
    let b = _c_by(h, j);
    if b == 32 || b == 9 {
      scheme_done = true;
    } else {
      j = j + 1;
    }
  }
  var k = j;
  var skipping = true;
  while k < n && skipping {
    let b = _c_by(h, k);
    if b == 32 || b == 9 {
      k = k + 1;
    } else {
      skipping = false;
    }
  }
  if k >= n { return ""; }
  return _c_trim_ows(string.str_slice(h, k, n));
}

/// True when the Authorization value's scheme is "Basic" (case-insensitive).
pub fn curl_auth_header_is_basic(h: Str) -> Bool {
  return _c_eq_ci(curl_auth_scheme(h), "Basic");
}

/// True when the Authorization value's scheme is "Bearer" (case-insensitive).
pub fn curl_auth_header_is_bearer(h: Str) -> Bool {
  return _c_eq_ci(curl_auth_scheme(h), "Bearer");
}

/// Decode a Basic Authorization value into "user:password". Errors:
/// "curl: not a Basic authorization header",
/// "curl: basic credentials are not valid base64".
pub fn curl_auth_basic_decode(h: Str) -> Result[Str, Str] {
  if !curl_auth_header_is_basic(h) {
    return _c_err_str("curl: not a Basic authorization header");
  }
  let tok = curl_auth_token(h);
  let r = base64.base64_decode_str(tok);
  if !r.is_ok {
    return _c_err_str("curl: basic credentials are not valid base64");
  }
  let s: Str = r.value;
  return _c_ok_str(s);
}

/// User part of decoded Basic credentials (everything before the first ':';
/// the whole string when there is no colon).
pub fn curl_auth_basic_user(creds: Str) -> Str {
  let n = creds.len();
  let colon = _c_find_range(creds, 58, 0, n);
  if colon < 0 { return creds; }
  return string.str_slice(creds, 0, colon);
}

/// Password part of decoded Basic credentials ("" when there is no colon).
pub fn curl_auth_basic_password(creds: Str) -> Str {
  let n = creds.len();
  let colon = _c_find_range(creds, 58, 0, n);
  if colon < 0 { return ""; }
  return string.str_slice(creds, colon + 1, n);
}

// --------------------------------------------------
//  Retry policy
// --------------------------------------------------

/// Deterministic retry policy. Flags are 1/0. `max_attempts` counts the
/// first try, so max_attempts=3 allows two retries.
pub type RetryPolicy = {
  max_attempts: Int;
  base_delay_ms: Int;
  max_delay_ms: Int;
  retry_5xx: Int;
  retry_429: Int;
  retry_408: Int;
  honor_retry_after: Int;
}

/// Defaults: 3 attempts, 200 ms base, 10 s cap, retry on 5xx/429/408, honor
/// Retry-After.
pub fn curl_retry_default() -> RetryPolicy {
  return RetryPolicy{
    max_attempts: 3;
    base_delay_ms: 200;
    max_delay_ms: 10000;
    retry_5xx: 1;
    retry_429: 1;
    retry_408: 1;
    honor_retry_after: 1;
  };
}

/// Status-only retry classification (408 / 429 / 5xx, gated by the flags).
pub fn curl_retry_status_retryable(p: &RetryPolicy, status: Int) -> Bool {
  if status == 408 && p.retry_408 == 1 { return true; }
  if status == 429 && p.retry_429 == 1 { return true; }
  if status >= 500 && status <= 599 && p.retry_5xx == 1 { return true; }
  return false;
}

/// True when `attempt` (1-based) may be retried: a retryable status, an
/// attempt below max_attempts and a positive attempt number.
pub fn curl_retry_should_retry(p: &RetryPolicy, status: Int, attempt: Int) -> Bool {
  if attempt < 1 { return false; }
  if attempt >= p.max_attempts { return false; }
  return curl_retry_status_retryable(p, status);
}

/// Deterministic exponential backoff: base * 2^(attempt-1), capped at
/// max_delay_ms; 0 for attempt <= 0. No jitter.
pub fn curl_retry_delay_ms(p: &RetryPolicy, attempt: Int) -> Int {
  if attempt <= 0 { return 0; }
  let base: Int = p.base_delay_ms;
  let cap: Int = p.max_delay_ms;
  var d = base;
  var k = 1;
  var going = true;
  while k < attempt && going {
    if d >= cap {
      going = false;
    } else {
      d = d * 2;
      if d > cap { d = cap; }
      k = k + 1;
    }
  }
  if d > cap { d = cap; }
  return d;
}

/// Parse a Retry-After delta-seconds value (digits only, <= 2147483647).
/// The HTTP-date form is intentionally unsupported:
/// Err("curl: unsupported Retry-After value: <v>").
pub fn curl_retry_parse_retry_after(s: Str) -> Result[Int, Str] {
  let n = s.len();
  if n == 0 {
    return _c_err_int("curl: unsupported Retry-After value: " + s);
  }
  var v = 0;
  var i = 0;
  while i < n {
    let b = _c_by(s, i);
    if !_c_is_digit(b) {
      return _c_err_int("curl: unsupported Retry-After value: " + s);
    }
    v = v * 10 + (b - 48);
    if v > 2147483647 {
      return _c_err_int("curl: unsupported Retry-After value: " + s);
    }
    i = i + 1;
  }
  return _c_ok_int(v);
}

/// Effective delay for an attempt: the exponential backoff, raised to the
/// server's Retry-After when the policy honors it and Retry-After is larger.
pub fn curl_retry_effective_delay(p: &RetryPolicy, attempt: Int, retry_after: Int, retry_after_present: Bool) -> Int {
  let d = curl_retry_delay_ms(p, attempt);
  if retry_after_present && p.honor_retry_after == 1 && retry_after > d {
    return retry_after;
  }
  return d;
}

// --------------------------------------------------
//  Connection pool model (keep-alive accounting)
// --------------------------------------------------

/// Keep-alive pool model. Slot i describes the (scheme, host, port) key with
/// `idle[i]` reusable and `active[i]` in-flight connections.
pub type Pool = {
  schemes: Vec[Str];
  hosts: Vec[Str];
  ports: Vec[Int];
  idle: Vec[Int];
  active: Vec[Int];
  max_idle_per_host: Int;
  max_total: Int;
}

/// New empty pool. `max_total` <= 0 means unbounded.
pub fn curl_pool_new(max_idle_per_host: Int, max_total: Int) -> Pool {
  return Pool{
    schemes: Vec[Str].new();
    hosts: Vec[Str].new();
    ports: Vec[Int].new();
    idle: Vec[Int].new();
    active: Vec[Int].new();
    max_idle_per_host: max_idle_per_host;
    max_total: max_total;
  };
}

fn _c_pool_find(p: &Pool, scheme: Str, host: Str, port: Int) -> Int {
  let n = p.schemes.len();
  var i = 0;
  while i < n {
    let sc: Str = p.schemes[i];
    let ho: Str = p.hosts[i];
    let po: Int = p.ports[i];
    if _c_eq_ci(sc, scheme) && _c_eq_ci(ho, host) && po == port {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Total connections (idle + active) across all slots.
pub fn curl_pool_total(p: &Pool) -> Int {
  let n = p.schemes.len();
  var t = 0;
  var i = 0;
  while i < n {
    t = t + p.idle[i] + p.active[i];
    i = i + 1;
  }
  return t;
}

/// Acquire a connection: returns 1 when an idle connection was reused, 0
/// when a new one was started, and -1 when max_total would be exceeded.
pub fn curl_pool_acquire(p: &mut Pool, scheme: Str, host: Str, port: Int) -> Int {
  let idx = _c_pool_find(p, scheme, host, port);
  if idx >= 0 {
    let idl: Int = p.idle[idx];
    let act: Int = p.active[idx];
    if idl > 0 {
      p.idle[idx] = idl - 1;
      p.active[idx] = act + 1;
      return 1;
    }
    p.active[idx] = act + 1;
    return 0;
  }
  let mx: Int = p.max_total;
  if mx > 0 && curl_pool_total(p) >= mx {
    return -1;
  }
  p.schemes.push(scheme);
  p.hosts.push(host);
  p.ports.push(port);
  p.idle.push(0);
  p.active.push(1);
  return 0;
}

/// Release a connection: returns 1 when kept alive as idle (below
/// max_idle_per_host) and 0 when closed (or no such slot).
pub fn curl_pool_release(p: &mut Pool, scheme: Str, host: Str, port: Int) -> Int {
  let idx = _c_pool_find(p, scheme, host, port);
  if idx < 0 { return 0; }
  let act: Int = p.active[idx];
  if act > 0 {
    p.active[idx] = act - 1;
  }
  let idl: Int = p.idle[idx];
  if idl < p.max_idle_per_host {
    p.idle[idx] = idl + 1;
    return 1;
  }
  return 0;
}

/// Idle count for a key (-1 when the key is absent).
pub fn curl_pool_idle(p: &Pool, scheme: Str, host: Str, port: Int) -> Int {
  let idx = _c_pool_find(p, scheme, host, port);
  if idx < 0 { return -1; }
  return p.idle[idx];
}

/// Active count for a key (-1 when the key is absent).
pub fn curl_pool_active(p: &Pool, scheme: Str, host: Str, port: Int) -> Int {
  let idx = _c_pool_find(p, scheme, host, port);
  if idx < 0 { return -1; }
  return p.active[idx];
}

/// True when a release for this key would keep the connection alive.
pub fn curl_pool_keep_alive(p: &Pool, scheme: Str, host: Str, port: Int) -> Bool {
  let idx = _c_pool_find(p, scheme, host, port);
  if idx < 0 { return false; }
  let idl: Int = p.idle[idx];
  if idl < p.max_idle_per_host { return true; }
  return false;
}

/// Number of slots (distinct keys).
pub fn curl_pool_slot_count(p: &Pool) -> Int {
  return p.schemes.len();
}

/// Total idle connections.
pub fn curl_pool_idle_total(p: &Pool) -> Int {
  let n = p.schemes.len();
  var t = 0;
  var i = 0;
  while i < n {
    t = t + p.idle[i];
    i = i + 1;
  }
  return t;
}

/// Total active connections.
pub fn curl_pool_active_total(p: &Pool) -> Int {
  let n = p.schemes.len();
  var t = 0;
  var i = 0;
  while i < n {
    t = t + p.active[i];
    i = i + 1;
  }
  return t;
}

/// Drop every idle connection; returns how many were closed. O(n).
pub fn curl_pool_close_idle(p: &mut Pool) -> Int {
  let n = p.schemes.len();
  var closed = 0;
  var i = 0;
  while i < n {
    let idl: Int = p.idle[i];
    closed = closed + idl;
    p.idle[i] = 0;
    i = i + 1;
  }
  return closed;
}

/// True when the five parallel vectors have equal lengths.
pub fn curl_pool_consistent(p: &Pool) -> Bool {
  let n = p.schemes.len();
  if p.hosts.len() != n { return false; }
  if p.ports.len() != n { return false; }
  if p.idle.len() != n { return false; }
  if p.active.len() != n { return false; }
  return true;
}

// --------------------------------------------------
//  Response model
// --------------------------------------------------

/// HTTP response model.
pub type Response = {
  version: Str;
  status: Int;
  reason: Str;
  headers: HeaderList;
  body: Str;
}

// Reason phrase bytes: HTAB or visible ASCII.
fn _c_check_reason(reason: Str) -> Result[Str, Str] {
  let n = reason.len();
  var i = 0;
  while i < n {
    let b = _c_by(reason, i);
    if !(b == 9 || (b >= 32 && b <= 126)) {
      return _c_err_str("curl: reason has invalid character at offset " + convert.int_to_string(i));
    }
    i = i + 1;
  }
  return _c_ok_str(reason);
}

/// Build a response. The version must be supported and the status in
/// 100..599. Errors: "curl: unsupported version: <v>",
/// "curl: invalid status: <n>", "curl: reason has invalid character at
/// offset N".
pub fn curl_response_new(version: Str, status: Int, reason: Str) -> Result[Response, Str] {
  if !curl_version_is_supported(version) {
    return _c_err_response("curl: unsupported version: " + version);
  }
  if status < 100 || status > 599 {
    return _c_err_response("curl: invalid status: " + convert.int_to_string(status));
  }
  let rc = _c_check_reason(reason);
  if !rc.is_ok { return _c_err_response(rc.error); }
  let r = Response{
    version: version;
    status: status;
    reason: reason;
    headers: curl_headers_new();
    body: "";
  };
  return _c_ok_response(r);
}

/// Append a header (delegates the validation to curl_headers_add).
pub fn curl_response_add_header(r: &mut Response, name: Str, value: Str) -> Result[Str, Str] {
  let res = curl_headers_add(&mut r.headers, name, value);
  return res;
}

/// Remove headers by name (case-insensitive); returns the number removed.
pub fn curl_response_remove_header(r: &mut Response, name: Str) -> Int {
  return curl_headers_remove(&mut r.headers, name);
}

/// First header value or Err("curl: header not found: <name>").
pub fn curl_response_header_get(r: &Response, name: Str) -> Result[Str, Str] {
  let h: HeaderList = r.headers;
  return curl_headers_get(&h, name);
}

/// Live header count.
pub fn curl_response_headers_count(r: &Response) -> Int {
  let h: HeaderList = r.headers;
  return curl_headers_count(&h);
}

/// Name of the i-th live header ("" when out of range).
pub fn curl_response_header_name_at(r: &Response, i: Int) -> Str {
  let h: HeaderList = r.headers;
  return curl_headers_name_at(&h, i);
}

/// Value of the i-th live header ("" when out of range).
pub fn curl_response_header_value_at(r: &Response, i: Int) -> Str {
  let h: HeaderList = r.headers;
  return curl_headers_value_at(&h, i);
}

/// Response status.
pub fn curl_response_status(r: &Response) -> Int {
  return r.status;
}

/// Response reason phrase.
pub fn curl_response_reason(r: &Response) -> Str {
  let s: Str = r.reason;
  return s;
}

/// Response version.
pub fn curl_response_version(r: &Response) -> Str {
  let s: Str = r.version;
  return s;
}

/// Response body bytes.
pub fn curl_response_body(r: &Response) -> Str {
  let s: Str = r.body;
  return s;
}

/// Body length in bytes.
pub fn curl_response_body_len(r: &Response) -> Int {
  let s: Str = r.body;
  return s.len();
}

/// Set the response body.
pub fn curl_response_set_body(r: &mut Response, body: Str) {
  r.body = body;
}

/// True when every parallel header pair is aligned.
pub fn curl_response_consistent(r: &Response) -> Bool {
  let h: HeaderList = r.headers;
  return curl_headers_consistent(&h);
}

/// Keep-alive decision: `Connection: close` closes; `Connection: keep-alive`
/// keeps alive; otherwise HTTP/1.1 defaults to keep-alive and HTTP/1.0 to
/// close. Only the first Connection value is consulted.
pub fn curl_response_is_keep_alive(r: &Response) -> Bool {
  let h: HeaderList = r.headers;
  let conn = curl_headers_get(&h, "Connection");
  if conn.is_ok {
    let c: Str = conn.value;
    if _c_eq_ci(c, "close") { return false; }
    if _c_eq_ci(c, "keep-alive") { return true; }
  }
  let v: Str = r.version;
  if _c_eq(v, "HTTP/1.1") { return true; }
  return false;
}

/// Parse the first live Content-Length as a non-negative decimal integer.
/// Errors: "curl: header not found: Content-Length",
/// "curl: invalid Content-Length".
pub fn curl_response_content_length(r: &Response) -> Result[Int, Str] {
  let h: HeaderList = r.headers;
  let cl = curl_headers_get(&h, "Content-Length");
  if !cl.is_ok { return _c_err_int("curl: header not found: Content-Length"); }
  let s: Str = cl.value;
  let n = s.len();
  if n == 0 { return _c_err_int("curl: invalid Content-Length"); }
  var v = 0;
  var i = 0;
  while i < n {
    let b = _c_by(s, i);
    if !_c_is_digit(b) { return _c_err_int("curl: invalid Content-Length"); }
    v = v * 10 + (b - 48);
    if v > 2147483647 { return _c_err_int("curl: invalid Content-Length"); }
    i = i + 1;
  }
  return _c_ok_int(v);
}

/// Deterministic head encoder: status line, live headers in order, blank
/// line, body. Lines are CRLF-terminated.
pub fn curl_response_encode(r: &Response) -> Str {
  let v: Str = r.version;
  let reason: Str = r.reason;
  let h: HeaderList = r.headers;
  var out: Str = v + " " + convert.int_to_string(r.status) + " " + reason + "\r\n";
  let cnt = curl_headers_count(&h);
  var i = 0;
  while i < cnt {
    let nm = curl_headers_name_at(&h, i);
    let vl = curl_headers_value_at(&h, i);
    out = out + nm + ": " + vl + "\r\n";
    i = i + 1;
  }
  out = out + "\r\n";
  let b: Str = r.body;
  out = out + b;
  return out;
}

// Exactly three decimal digits, 100..599.
fn _c_parse_status3(s: Str) -> Result[Int, Str] {
  if s.len() != 3 { return _c_err_int("curl: invalid status"); }
  var v = 0;
  var i = 0;
  while i < 3 {
    let b = _c_by(s, i);
    if !_c_is_digit(b) { return _c_err_int("curl: invalid status"); }
    v = v * 10 + (b - 48);
    i = i + 1;
  }
  if v < 100 || v > 599 {
    return _c_err_int("curl: invalid status: " + convert.int_to_string(v));
  }
  return _c_ok_int(v);
}

/// Parse a response head (status line + CRLF headers + optional body after
/// the blank line). The status line is `HTTP/1.x SP status SP reason CRLF`;
/// header folding and non-ASCII bytes are rejected. Errors:
/// "curl: response status line malformed",
/// "curl: unsupported version: <v>", "curl: invalid status[: N]",
/// "curl: reason has invalid character at offset N",
/// "curl: header line malformed at offset N",
/// "curl: header folding not supported at offset N",
/// plus the header name/value validation errors (offsets are into the
/// offending field). O(text.len()).
pub fn curl_response_parse(text: Str) -> Result[Response, Str] {
  let n = text.len();
  let eol = _c_find_crlf(text, 0);
  if eol < 0 {
    return _c_err_response("curl: response status line malformed");
  }
  let line = string.str_slice(text, 0, eol);
  let sp1 = _c_find_range(line, 32, 0, line.len());
  if sp1 < 0 {
    return _c_err_response("curl: response status line malformed");
  }
  let version = string.str_slice(line, 0, sp1);
  if !curl_version_is_supported(version) {
    return _c_err_response("curl: unsupported version: " + version);
  }
  let sp2 = _c_find_range(line, 32, sp1 + 1, line.len());
  var status_str = "";
  var reason = "";
  if sp2 < 0 {
    status_str = string.str_slice(line, sp1 + 1, line.len());
  } else {
    status_str = string.str_slice(line, sp1 + 1, sp2);
    reason = string.str_slice(line, sp2 + 1, line.len());
  }
  let st = _c_parse_status3(status_str);
  if !st.is_ok { return _c_err_response(st.error); }
  let rc = _c_check_reason(reason);
  if !rc.is_ok { return _c_err_response(rc.error); }
  var headers = curl_headers_new();
  var body = "";
  var pos = eol + 2;
  var done = false;
  while !done && pos < n {
    let e2 = _c_find_crlf(text, pos);
    if e2 < 0 {
      return _c_err_response("curl: header line malformed at offset " + convert.int_to_string(pos));
    }
    if e2 == pos {
      body = string.str_slice(text, pos + 2, n);
      done = true;
    } else {
      let hline = string.str_slice(text, pos, e2);
      let b0 = _c_by(hline, 0);
      if b0 == 32 || b0 == 9 {
        return _c_err_response("curl: header folding not supported at offset " + convert.int_to_string(pos));
      }
      let colon = _c_find_range(hline, 58, 0, hline.len());
      if colon <= 0 {
        return _c_err_response("curl: header line malformed at offset " + convert.int_to_string(pos));
      }
      let hname = string.str_slice(hline, 0, colon);
      let hval = _c_trim_ows(string.str_slice(hline, colon + 1, hline.len()));
      let hc = _c_check_header_name(hname);
      if !hc.is_ok { return _c_err_response(hc.error); }
      let hv = _c_check_header_value(hval);
      if !hv.is_ok { return _c_err_response(hv.error); }
      headers.names.push(hname);
      headers.values.push(hval);
      headers.alive.push(1);
      pos = e2 + 2;
    }
  }
  let r = Response{
    version: version;
    status: st.value;
    reason: reason;
    headers: headers;
    body: body;
  };
  return _c_ok_response(r);
}

// --------------------------------------------------
//  Status and envelope classification
// --------------------------------------------------

/// Status class: 1..5 for 1xx..5xx, 0 for anything outside 100..599.
pub fn curl_status_class(status: Int) -> Int {
  if status < 100 || status > 599 { return 0; }
  return status / 100;
}

/// 1xx.
pub fn curl_status_is_informational(status: Int) -> Bool {
  if curl_status_class(status) == 1 { return true; }
  return false;
}

/// 2xx.
pub fn curl_status_is_success(status: Int) -> Bool {
  if curl_status_class(status) == 2 { return true; }
  return false;
}

/// 3xx.
pub fn curl_status_is_redirect(status: Int) -> Bool {
  if curl_status_class(status) == 3 { return true; }
  return false;
}

/// 4xx.
pub fn curl_status_is_client_error(status: Int) -> Bool {
  if curl_status_class(status) == 4 { return true; }
  return false;
}

/// 5xx.
pub fn curl_status_is_server_error(status: Int) -> Bool {
  if curl_status_class(status) == 5 { return true; }
  return false;
}

/// Statuses this model considers retryable regardless of policy: 408, 429,
/// 500, 502, 503 and 504.
pub fn curl_status_is_retryable(status: Int) -> Bool {
  if status == 408 || status == 429 { return true; }
  if status == 500 || status == 502 || status == 503 || status == 504 {
    return true;
  }
  return false;
}

/// Class name: "informational", "success", "redirect", "client error",
/// "server error" or "unknown".
pub fn curl_status_class_name(status: Int) -> Str {
  let c = curl_status_class(status);
  if c == 1 { return "informational"; }
  if c == 2 { return "success"; }
  if c == 3 { return "redirect"; }
  if c == 4 { return "client error"; }
  if c == 5 { return "server error"; }
  return "unknown";
}

/// Envelope class constant: 0 (invalid) or CURL_ENV_*.
pub fn curl_envelope_class(status: Int) -> Int {
  let c = curl_status_class(status);
  if c == 1 { return CURL_ENV_INFORMATIONAL; }
  if c == 2 { return CURL_ENV_SUCCESS; }
  if c == 3 { return CURL_ENV_REDIRECT; }
  if c == 4 { return CURL_ENV_CLIENT_ERROR; }
  if c == 5 { return CURL_ENV_SERVER_ERROR; }
  return CURL_ENV_NONE;
}

/// Envelope class name for a curl_envelope_class value.
pub fn curl_envelope_name(kind: Int) -> Str {
  if kind == CURL_ENV_INFORMATIONAL { return "informational"; }
  if kind == CURL_ENV_SUCCESS { return "success"; }
  if kind == CURL_ENV_REDIRECT { return "redirect"; }
  if kind == CURL_ENV_CLIENT_ERROR { return "client error"; }
  if kind == CURL_ENV_SERVER_ERROR { return "server error"; }
  return "none";
}

/// Envelope class of a response.
pub fn curl_response_envelope(r: &Response) -> Int {
  return curl_envelope_class(r.status);
}

/// True when the connection serving this response can be reused: the
/// keep-alive decision of curl_response_is_keep_alive.
pub fn curl_response_reusable(r: &Response) -> Bool {
  return curl_response_is_keep_alive(r);
}

/// "0.1.0".
pub fn curl_version() -> Str {
  return "0.1.0";
}
