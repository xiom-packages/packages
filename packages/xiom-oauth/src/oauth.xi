// XIOM -- xiom.oauth: OAuth 2.0 / PKCE request-and-response structure codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no crypto) STRUCTURE codec for OAuth 2.0
// (RFC 6749) messages and the PKCE extension (RFC 7636). It encodes and
// parses the payloads a caller exchanges over its own transport; it never
// performs network I/O, never issues or validates JWTs, and never hashes.
//
// Covered surface:
//   * application/x-www-form-urlencoded percent-encoding: ALPHA / DIGIT /
//     '-' '.' '_' '~' are literal, space encodes as '+', every other byte as
//     %XX with uppercase hex. Decoding maps '+' to space and is strict about
//     '%': a malformed escape is Err with the byte offset.
//   * Authorization requests (RFC 6749 section 4.1.1 / 4.2.1): response_type
//     code|token, client_id, redirect_uri, scope, state, code_challenge and
//     code_challenge_method, plus unknown parameters preserved in order.
//   * Authorization responses (sections 4.1.2 / 4.2.2): code, state and the
//     error / error_description / error_uri triple with the seven registered
//     error codes.
//   * Token endpoint requests (sections 4.1.3 / 4.3.2 / 4.4.2 / 6): the
//     authorization_code, refresh_token and client_credentials grants with
//     grant-specific field rules and optional body client authentication.
//   * Token endpoint responses (section 5.1 / 5.2): access_token, token_type
//     (Bearer, case-insensitive), expires_in (digits only), refresh_token,
//     scope, and the error / error_description pair.
//   * PKCE helpers (RFC 7636): verifier validation (43..128 unreserved
//     characters), the plain challenge equality helper, and the S256
//     challenge builder that base64url-encodes a CALLER-COMPUTED 32-byte
//     SHA-256 digest. This module does not compute SHA-256.
//
// JSON is not parsed. Token responses are inspected with a small raw-byte
// key lookup (_json_find and its oauth_json_* wrappers): it finds the first
// scalar top-level member of the object text, is string-escape aware (a
// backslash escapes the next byte inside string values), rejects composite
// values, raw control bytes and inputs above oauth_max_json_bytes(), and
// returns Err("oauth: json ...") messages. Escapes inside returned string
// values are left exactly as written (no unescaping).
//
// v0.61.3 notes that shaped this module:
//   * Free functions only, no methods, no lambdas, no match in the library,
//     no Vec[StructType] (parallel Vec[Str] fields instead), no floats.
//   * Ok/Err construction is confined to the leaf helpers _ok_* / _err_*
//     (constructing Results inside larger functions miscompiles).
//   * Every byte read from a Str or Vec[UInt8] is widened once with
//     `(x as Int) & 0xFF` before comparison or arithmetic.
//   * No Str value is compared with `==`; everything goes through
//     xiom.string.compare.str_compare / str_eq_ignore_case with typed locals.
//   * &mut write-through is used only for Vec pushes (the sanctioned
//     pattern); no &mut Int out-parameters.
//   * xiom.string.builder's sb_to_str is never fed a NUL byte: percent
//     escapes that decode to 0x00 are rejected with a byte-offset error.

module xiom.oauth

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Byte constants (Int space, always compared masked)
// --------------------------------------------------

const _OAUTH_TAB: Int = 9;
const _OAUTH_LF: Int = 10;
const _OAUTH_CR: Int = 13;
const _OAUTH_SPACE: Int = 32;
const _OAUTH_QUOTE: Int = 34;
const _OAUTH_PERCENT: Int = 37;
const _OAUTH_AMP: Int = 38;
const _OAUTH_PLUS: Int = 43;
const _OAUTH_COMMA: Int = 44;
const _OAUTH_MINUS: Int = 45;
const _OAUTH_DOT: Int = 46;
const _OAUTH_COLON: Int = 58;
const _OAUTH_EQUALS: Int = 61;
const _OAUTH_LBRACKET: Int = 91;
const _OAUTH_BACKSLASH: Int = 92;
const _OAUTH_UNDERSCORE: Int = 95;
const _OAUTH_LBRACE: Int = 123;
const _OAUTH_RBRACE: Int = 125;

// PKCE sizes (RFC 7636): verifier 43..128 characters, S256 digest 32 bytes
// rendered as 43 unpadded base64url characters.
const _OAUTH_PKCE_MIN: Int = 43;
const _OAUTH_PKCE_MAX: Int = 128;
const _OAUTH_S256_LEN: Int = 43;
const _OAUTH_S256_BYTES: Int = 32;

// Upper bound on the JSON text oauth_json_* helpers will scan.
const _OAUTH_MAX_JSON: Int = 65536;

// Largest accepted decimal magnitude: 2^31 - 1.
const _OAUTH_MAX_INT: Int = 2147483647;

// Unpadded base64url alphabet (RFC 4648 section 5).
const _B64URL_ALPHABET: Str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[(Int, Int), Str].
fn _ok_pair(v: (Int, Int)) -> Result[(Int, Int), Str] {
  return Ok(v);
}

// Err(m) for Result[(Int, Int), Str].
fn _err_pair(m: Str) -> Result[(Int, Int), Str] {
  return Err(m);
}

// Ok(v) for Result[OAuthParams, Str].
fn _ok_params(v: OAuthParams) -> Result[OAuthParams, Str] {
  return Ok(v);
}

// Err(m) for Result[OAuthParams, Str].
fn _err_params(m: Str) -> Result[OAuthParams, Str] {
  return Err(m);
}

// Ok(v) for Result[AuthzRequest, Str].
fn _ok_authz_request(v: AuthzRequest) -> Result[AuthzRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[AuthzRequest, Str].
fn _err_authz_request(m: Str) -> Result[AuthzRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[AuthzResponse, Str].
fn _ok_authz_response(v: AuthzResponse) -> Result[AuthzResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[AuthzResponse, Str].
fn _err_authz_response(m: Str) -> Result[AuthzResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[TokenRequest, Str].
fn _ok_token_request(v: TokenRequest) -> Result[TokenRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[TokenRequest, Str].
fn _err_token_request(m: Str) -> Result[TokenRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[TokenResponse, Str].
fn _ok_token_response(v: TokenResponse) -> Result[TokenResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[TokenResponse, Str].
fn _err_token_response(m: Str) -> Result[TokenResponse, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Message types
// --------------------------------------------------

/// Ordered name/value pairs (form parameters, extras, scope is separate).
/// Parallel Vec[Str] fields keep the compiler away from Vec[StructType];
/// names[i] always pairs with values[i].
pub type OAuthParams = {
  names: Vec[Str];
  values: Vec[Str];
}

/// Authorization endpoint request (RFC 6749 section 4.1.1 / 4.2.1 plus PKCE
/// section 4.3). Empty Str means "absent from the wire". `scope` is a list
/// joined with single spaces when encoded.
pub type AuthzRequest = {
  response_type: Str;
  client_id: Str;
  redirect_uri: Str;
  scope: Vec[Str];
  state: Str;
  code_challenge: Str;
  code_challenge_method: Str;
  extra: OAuthParams;
}

/// Authorization endpoint response (RFC 6749 section 4.1.2 / 4.2.2). A
/// success carries `code` (and optionally `state`); a failure carries
/// `error` plus optionally `error_description` / `error_uri`.
pub type AuthzResponse = {
  code: Str;
  state: Str;
  error: Str;
  error_description: Str;
  error_uri: Str;
  extra: OAuthParams;
}

/// Token endpoint request (RFC 6749 sections 4.1.3, 4.3.2, 4.4.2, 6).
/// `client_id` / `client_secret` are optional body client-authentication
/// fields; HTTP Basic authentication is a caller concern.
pub type TokenRequest = {
  grant_type: Str;
  code: Str;
  redirect_uri: Str;
  refresh_token: Str;
  scope: Vec[Str];
  client_id: Str;
  client_secret: Str;
  extra: OAuthParams;
}

/// Token endpoint response (RFC 6749 section 5.1) or error (section 5.2).
/// `expires_in` is meaningful only when `expires_in_present` is true.
pub type TokenResponse = {
  access_token: Str;
  token_type: Str;
  expires_in: Int;
  expires_in_present: Bool;
  refresh_token: Str;
  scope: Vec[Str];
  error: Str;
  error_description: Str;
}

// --------------------------------------------------
//  Shared byte helpers
// --------------------------------------------------

// Byte of a Str at pos, widened to 0..255. Callers guarantee the bounds.
fn _byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// Byte of a Vec[UInt8] at pos, widened to 0..255.
fn _vbyte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Decimal text of v for error messages (sign/digits only; never 0x00).
fn _int_str(v: Int) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_int(&mut out, v);
  return builder.sb_to_str(&out);
}

// "<what> at offset <off>": the offset-bearing error convention.
fn _perr(what: Str, off: Int) -> Str {
  return "oauth: " + what + " at offset " + _int_str(off);
}

// Raw bytes of a Str (one byte per index).
fn _str_bytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

// Independent copy of a Vec[Str] (never aliases the source buffer).
fn _copy_strs(src: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < src.len() {
    let v: Str = src[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

// Append data[a, b) to out; callers guarantee the bounds.
fn _copy_span(data: &Vec[UInt8], a: Int, b: Int, out: &mut Vec[UInt8]) {
  var i = a;
  while i < b {
    out.push(data[i]);
    i = i + 1;
  }
}

fn _is_digit(c: Int) -> Bool {
  if c >= 48 && c <= 57 { return true; }
  return false;
}

fn _is_alpha(c: Int) -> Bool {
  if c >= 65 && c <= 90 { return true; }
  if c >= 97 && c <= 122 { return true; }
  return false;
}

// Numeric value of a hex digit byte (0-9, A-F, a-f); -1 for any other byte.
fn _hex_value(c: Int) -> Int {
  if c >= 48 && c <= 57 { return c - 48; }
  if c >= 65 && c <= 70 { return c - 55; }
  if c >= 97 && c <= 102 { return c - 87; }
  return -1;
}

// Uppercase hex digit byte for a nibble value (0..15).
fn _hex_upper(n: Int) -> UInt8 {
  if n < 10 {
    return (48 + n) as UInt8;
  }
  return (55 + n) as UInt8;
}

// True for the RFC 3986 unreserved set: ALPHA / DIGIT / '-' '.' '_' '~'.
fn _unreserved(c: Int) -> Bool {
  if _is_alpha(c) { return true; }
  if _is_digit(c) { return true; }
  if c == _OAUTH_MINUS || c == _OAUTH_DOT || c == _OAUTH_UNDERSCORE {
    return true;
  }
  if c == 126 { return true; }
  return false;
}

// True for the unpadded base64url alphabet.
fn _b64url_char(c: Int) -> Bool {
  if _is_alpha(c) { return true; }
  if _is_digit(c) { return true; }
  if c == _OAUTH_MINUS || c == _OAUTH_UNDERSCORE { return true; }
  return false;
}

// True for JSON whitespace: space, TAB, LF, CR.
fn _json_ws(c: Int) -> Bool {
  if c == _OAUTH_SPACE || c == _OAUTH_TAB { return true; }
  if c == _OAUTH_LF || c == _OAUTH_CR { return true; }
  return false;
}

// True for a raw JSON control byte (below 0x20, excluding TAB/LF/CR).
fn _json_control(c: Int) -> Bool {
  if c < _OAUTH_SPACE && c != _OAUTH_TAB && c != _OAUTH_LF && c != _OAUTH_CR {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Percent-encoding (application/x-www-form-urlencoded)
// --------------------------------------------------

/// Encode `s` for application/x-www-form-urlencoded.
/// Params: s - any Str; bytes are encoded one by one.
/// Returns: ALPHA / DIGIT / '-' '.' '_' '~' literal; space (0x20) as '+';
/// every other byte as '%' + two uppercase hex digits. Empty input yields "".
/// Error case: none (total).
/// Complexity: O(s.len()).
pub fn oauth_form_encode(s: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if b == _OAUTH_SPACE {
      out.push(_OAUTH_PLUS as UInt8);
    } elif _unreserved(b) {
      out.push(string.byte_at(s, i));
    } else {
      out.push(_OAUTH_PERCENT as UInt8);
      out.push(_hex_upper(b >> 4));
      out.push(_hex_upper(b & 15));
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Decode s[a, b) with form rules; errors carry absolute byte offsets.
fn _form_decode_range(s: Str, a: Int, b: Int) -> Result[Str, Str] {
  var out = Vec[UInt8].new();
  var i = a;
  while i < b {
    let c = _byte(s, i);
    if c == _OAUTH_PLUS {
      out.push(_OAUTH_SPACE as UInt8);
      i = i + 1;
    } elif c == _OAUTH_PERCENT {
      if i + 2 >= b {
        return _err_str(_perr("truncated percent escape", i));
      }
      let hi = _hex_value(_byte(s, i + 1));
      let lo = _hex_value(_byte(s, i + 2));
      if hi < 0 || lo < 0 {
        return _err_str(_perr("bad percent escape", i));
      }
      let v = (hi << 4) | lo;
      if v == 0 {
        return _err_str(_perr("percent escape decodes to NUL", i));
      }
      out.push(v as UInt8);
      i = i + 3;
    } else {
      out.push(string.byte_at(s, i));
      i = i + 1;
    }
  }
  return _ok_str(builder.sb_to_str(&out));
}

/// Decode an application/x-www-form-urlencoded string.
/// Params: s - the encoded text.
/// Returns: Ok(decoded) on success; '+' becomes space, '%XX' (case-
/// insensitive hex) becomes the byte 0xXX, every other byte is copied.
/// Empty input yields Ok("").
/// Error case: Err("oauth: truncated percent escape at offset N") when the
/// input ends after '%' or after one hex digit; Err("oauth: bad percent
/// escape at offset N") when a '%' is not followed by two hex digits; Err(
/// "oauth: percent escape decodes to NUL at offset N") because a decoded
/// 0x00 cannot live in a Str (XIOM strings are NUL-terminated).
/// Complexity: O(s.len()).
pub fn oauth_form_decode(s: Str) -> Result[Str, Str] {
  return _form_decode_range(s, 0, s.len());
}

// --------------------------------------------------
//  Ordered parameters
// --------------------------------------------------

/// A new empty parameter list.
/// Params: none. Returns: OAuthParams with no entries.
/// Error case: none. Complexity: O(1).
pub fn oauth_params_new() -> OAuthParams {
  return OAuthParams{ names: Vec[Str].new(), values: Vec[Str].new() };
}

/// Append one name/value pair (duplicates allowed; order preserved).
/// Params: p - the list to grow; name/value - the pair. Pushes to both
/// parallel vectors together.
/// Error case: none. Complexity: O(1).
pub fn oauth_params_add(p: &mut OAuthParams, name: Str, value: Str) {
  p.names.push(name);
  p.values.push(value);
}

/// Number of pairs. Params: p - the list. Returns: the count.
/// Error case: none. Complexity: O(1).
pub fn oauth_params_count(p: &OAuthParams) -> Int {
  return p.names.len();
}

/// Name of pair `i`. Params: p - the list; i - a valid index.
/// Returns: the name as a typed local copy.
/// Error case: none for a valid index. Complexity: O(1).
pub fn oauth_params_name_at(p: &OAuthParams, i: Int) -> Str {
  let v: Str = p.names[i];
  return v;
}

/// Value of pair `i`. Params: p - the list; i - a valid index.
/// Returns: the value as a typed local copy.
/// Error case: none for a valid index. Complexity: O(1).
pub fn oauth_params_value_at(p: &OAuthParams, i: Int) -> Str {
  let v: Str = p.values[i];
  return v;
}

/// True when a pair named `name` exists (first match wins).
/// Params: p - the list; name - the key. Returns: the predicate.
/// Error case: none. Complexity: O(p.names.len()).
pub fn oauth_params_has(p: &OAuthParams, name: Str) -> Bool {
  var i = 0;
  while i < p.names.len() {
    let cur: Str = p.names[i];
    if compare.str_compare(cur, name) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// First value named `name`.
/// Params: p - the list; name - the key.
/// Returns: Ok(value) for the first matching pair.
/// Error case: Err("oauth: parameter not found: <name>") when absent.
/// Complexity: O(p.names.len()).
pub fn oauth_params_get(p: &OAuthParams, name: Str) -> Result[Str, Str] {
  var i = 0;
  while i < p.names.len() {
    let cur: Str = p.names[i];
    if compare.str_compare(cur, name) == 0 {
      let v: Str = p.values[i];
      return _ok_str(v);
    }
    i = i + 1;
  }
  return _err_str("oauth: parameter not found: " + name);
}

// Value of the first pair named `name`, or "" when absent.
fn _params_get_or_empty(p: &OAuthParams, name: Str) -> Str {
  let r = oauth_params_get(p, name);
  if !r.is_ok {
    return "";
  }
  let v: Str = r.value;
  return v;
}

/// Encode a parameter list as a form body (name=value pairs joined by '&',
/// each side form-encoded). Order is preserved; empty list yields "".
/// Params: p - the list. Returns: the encoded body.
/// Error case: none. Complexity: O(total text).
pub fn oauth_params_encode(p: &OAuthParams) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < p.names.len() {
    let n: Str = p.names[i];
    let v: Str = p.values[i];
    _push_form_pair(&mut out, n, v);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Append "name=value" (form-encoded) with a leading '&' when out is not
// empty.
fn _push_form_pair(out: &mut Vec[UInt8], name: Str, value: Str) {
  if out.len() > 0 {
    out.push(_OAUTH_AMP as UInt8);
  }
  builder.sb_push_str(out, oauth_form_encode(name));
  out.push(_OAUTH_EQUALS as UInt8);
  builder.sb_push_str(out, oauth_form_encode(value));
}

// Parse a form body into p, preserving order.
// Grammar: pair *('&' pair); pair = name ['=' value]; names/values are
// form-decoded. Empty input is Ok(0 pairs); an empty pair ("&&", a leading
// or trailing '&') and an empty name are errors, and names/values may not
// decode to NUL.
// Error case: Err with the byte offset of the first violation; the catalog
// is _perr("empty parameter", off), _perr("empty parameter name", off) and
// the _form_decode_range catalog.
fn _parse_form(s: Str, p: &mut OAuthParams) -> Result[Int, Str] {
  let n = s.len();
  if n == 0 {
    return _ok_int(0);
  }
  if _byte(s, n - 1) == _OAUTH_AMP {
    return _err_int(_perr("empty parameter", n - 1));
  }
  var i = 0;
  while i < n {
    var j = i;
    while j < n && _byte(s, j) != _OAUTH_AMP {
      j = j + 1;
    }
    if j == i {
      return _err_int(_perr("empty parameter", i));
    }
    var k = i;
    while k < j && _byte(s, k) != _OAUTH_EQUALS {
      k = k + 1;
    }
    if k == i {
      return _err_int(_perr("empty parameter name", i));
    }
    let nr = _form_decode_range(s, i, k);
    if !nr.is_ok {
      return _err_int(nr.error);
    }
    var vstart = j;
    if k < j {
      vstart = k + 1;
    }
    let vr = _form_decode_range(s, vstart, j);
    if !vr.is_ok {
      return _err_int(vr.error);
    }
    let nm: Str = nr.value;
    let vl: Str = vr.value;
    oauth_params_add(p, nm, vl);
    i = j + 1;
  }
  return _ok_int(p.names.len());
}

/// Parse a form body into an ordered parameter list.
/// Params: query - the form-encoded text (leading '?' is NOT accepted).
/// Returns: Ok(params) preserving order and duplicates; a pair without '='
/// yields an empty value. Empty input yields Ok(empty list).
/// Error case: the _parse_form catalog: Err("oauth: empty parameter at
/// offset N") for a leading/trailing/double '&', "oauth: empty parameter
/// name at offset N" for "=v", and the percent-decode errors.
/// Complexity: O(query.len()).
pub fn oauth_params_parse(query: Str) -> Result[OAuthParams, Str] {
  var p = oauth_params_new();
  let r = _parse_form(query, &mut p);
  if !r.is_ok {
    return _err_params(r.error);
  }
  return _ok_params(p);
}

// --------------------------------------------------
//  Scope lists (RFC 6749 section 3.3)
// --------------------------------------------------

// True when every byte of token is 0x21..0x7E except '"' and '\'.
fn _scope_chars_ok(token: Str) -> Bool {
  var i = 0;
  while i < token.len() {
    let c = _byte(token, i);
    if c < 33 || c > 126 {
      return false;
    }
    if c == _OAUTH_QUOTE || c == _OAUTH_BACKSLASH {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Validate one scope token; errors carry offsets relative to `token`.
fn _scope_token_check(token: Str, base: Int) -> Result[Str, Str] {
  if token.len() == 0 {
    return _err_str(_perr("empty scope token", base));
  }
  var i = 0;
  while i < token.len() {
    let c = _byte(token, i);
    if c < 33 || c > 126 || c == _OAUTH_QUOTE || c == _OAUTH_BACKSLASH {
      return _err_str(_perr("scope token has invalid character", base + i));
    }
    i = i + 1;
  }
  return _ok_str("");
}

// Validate a scope list without offsets (build side).
fn _scope_tokens_check(tokens: &Vec[Str]) -> Result[Str, Str] {
  var i = 0;
  while i < tokens.len() {
    let t: Str = tokens[i];
    if t.len() == 0 {
      return _err_str("oauth: empty scope token");
    }
    if !_scope_chars_ok(t) {
      return _err_str("oauth: scope token has invalid character");
    }
    i = i + 1;
  }
  return _ok_str("");
}

// Split the decoded scope value `s` on single spaces into out. A leading,
// trailing or doubled space is an empty token and is rejected with an
// offset into `s`. Empty input yields zero tokens.
fn _split_scope_into(s: Str, out: &mut Vec[Str]) -> Result[Int, Str] {
  let n = s.len();
  if n == 0 {
    return _ok_int(0);
  }
  if _byte(s, 0) == _OAUTH_SPACE {
    return _err_int(_perr("empty scope token", 0));
  }
  if _byte(s, n - 1) == _OAUTH_SPACE {
    return _err_int(_perr("empty scope token", n - 1));
  }
  var i = 0;
  var start = 0;
  while i <= n {
    if i == n || _byte(s, i) == _OAUTH_SPACE {
      let tok = string.str_slice(s, start, i);
      let cr = _scope_token_check(tok, start);
      if !cr.is_ok {
        return _err_int(cr.error);
      }
      out.push(tok);
      start = i + 1;
    }
    i = i + 1;
  }
  return _ok_int(out.len());
}

// Join scope tokens with single spaces (wire form).
fn _scope_join(tokens: &Vec[Str]) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < tokens.len() {
    if i > 0 {
      out.push(_OAUTH_SPACE as UInt8);
    }
    let t: Str = tokens[i];
    builder.sb_push_str(&mut out, t);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Registered value predicates
// --------------------------------------------------

/// True when `v` is "code" or "token" (RFC 6749 section 3.1.1).
/// Params: v - the response_type value. Returns: the predicate.
/// Error case: none. Complexity: O(v.len()).
pub fn oauth_response_type_is_valid(v: Str) -> Bool {
  if compare.str_compare(v, "code") == 0 { return true; }
  if compare.str_compare(v, "token") == 0 { return true; }
  return false;
}

/// True when `v` is an authorization_code, refresh_token or
/// client_credentials grant (RFC 6749 sections 4.1.3, 4.4.2, 6).
/// Params: v - the grant_type value. Returns: the predicate.
/// Error case: none. Complexity: O(v.len()).
pub fn oauth_grant_type_is_valid(v: Str) -> Bool {
  if compare.str_compare(v, "authorization_code") == 0 { return true; }
  if compare.str_compare(v, "refresh_token") == 0 { return true; }
  if compare.str_compare(v, "client_credentials") == 0 { return true; }
  return false;
}

/// True when `v` is "plain" or "S256" (RFC 7636 section 4.3).
/// Params: v - the code_challenge_method value. Returns: the predicate.
/// Error case: none. Complexity: O(v.len()).
pub fn oauth_challenge_method_is_valid(v: Str) -> Bool {
  if compare.str_compare(v, "plain") == 0 { return true; }
  if compare.str_compare(v, "S256") == 0 { return true; }
  return false;
}

/// True for the seven authorization error codes of RFC 6749 section 4.1.2.1
/// plus 4.2.2.1: invalid_request, unauthorized_client, access_denied,
/// unsupported_response_type, invalid_scope, server_error,
/// temporarily_unavailable.
/// Params: code - the error code. Returns: the predicate.
/// Error case: none. Complexity: O(code.len()).
pub fn oauth_authz_error_is_valid(code: Str) -> Bool {
  if compare.str_compare(code, "invalid_request") == 0 { return true; }
  if compare.str_compare(code, "unauthorized_client") == 0 { return true; }
  if compare.str_compare(code, "access_denied") == 0 { return true; }
  if compare.str_compare(code, "unsupported_response_type") == 0 { return true; }
  if compare.str_compare(code, "invalid_scope") == 0 { return true; }
  if compare.str_compare(code, "server_error") == 0 { return true; }
  if compare.str_compare(code, "temporarily_unavailable") == 0 { return true; }
  return false;
}

/// True for the six token error codes of RFC 6749 section 5.2:
/// invalid_request, invalid_client, invalid_grant, unauthorized_client,
/// unsupported_grant_type, invalid_scope.
/// Params: code - the error code. Returns: the predicate.
/// Error case: none. Complexity: O(code.len()).
pub fn oauth_token_error_is_valid(code: Str) -> Bool {
  if compare.str_compare(code, "invalid_request") == 0 { return true; }
  if compare.str_compare(code, "invalid_client") == 0 { return true; }
  if compare.str_compare(code, "invalid_grant") == 0 { return true; }
  if compare.str_compare(code, "unauthorized_client") == 0 { return true; }
  if compare.str_compare(code, "unsupported_grant_type") == 0 { return true; }
  if compare.str_compare(code, "invalid_scope") == 0 { return true; }
  return false;
}

// --------------------------------------------------
//  PKCE (RFC 7636)
// --------------------------------------------------

/// Lower bound of the PKCE verifier length: 43. Params: none.
/// Returns: 43. Error case: none. Complexity: O(1).
pub fn oauth_pkce_verifier_min() -> Int {
  return _OAUTH_PKCE_MIN;
}

/// Upper bound of the PKCE verifier length: 128. Params: none.
/// Returns: 128. Error case: none. Complexity: O(1).
pub fn oauth_pkce_verifier_max() -> Int {
  return _OAUTH_PKCE_MAX;
}

/// S256 digest size in bytes: 32. Params: none. Returns: 32.
/// Error case: none. Complexity: O(1).
pub fn oauth_pkce_s256_hash_len() -> Int {
  return _OAUTH_S256_BYTES;
}

// Validate a verifier: 43..128 characters from the unreserved set.
fn _pkce_verifier_check(v: Str) -> Result[Str, Str] {
  if v.len() < _OAUTH_PKCE_MIN || v.len() > _OAUTH_PKCE_MAX {
    return _err_str("oauth: pkce verifier length out of range (43..128)");
  }
  var i = 0;
  while i < v.len() {
    if !_unreserved(_byte(v, i)) {
      return _err_str(_perr("pkce verifier bad character", i));
    }
    i = i + 1;
  }
  return _ok_str("");
}

// Validate a caller-computed S256 challenge: exactly 43 base64url chars.
fn _s256_check(c: Str) -> Result[Str, Str] {
  if c.len() != _OAUTH_S256_LEN {
    return _err_str("oauth: pkce s256 challenge length must be 43");
  }
  var i = 0;
  while i < c.len() {
    if !_b64url_char(_byte(c, i)) {
      return _err_str(_perr("pkce s256 challenge bad character", i));
    }
    i = i + 1;
  }
  return _ok_str("");
}

// Consistent challenge/method pairing: if a method is given it must be
// registered, and a method without a challenge is rejected. A challenge
// with no method defaults to "plain" (RFC 7636 section 4.3).
fn _pkce_pair_check(challenge: Str, method: Str) -> Result[Str, Str] {
  if method.len() > 0 {
    if !oauth_challenge_method_is_valid(method) {
      return _err_str("oauth: unsupported code_challenge_method: " + method);
    }
    if challenge.len() == 0 {
      return _err_str("oauth: code_challenge_method without code_challenge");
    }
  }
  if challenge.len() > 0 {
    if method.len() == 0 || compare.str_compare(method, "plain") == 0 {
      let vr = _pkce_verifier_check(challenge);
      if !vr.is_ok {
        return _err_str(vr.error);
      }
    } else {
      let sr = _s256_check(challenge);
      if !sr.is_ok {
        return _err_str(sr.error);
      }
    }
  }
  return _ok_str("");
}

/// True when `v` is a valid PKCE code verifier: 43..128 characters, every
/// character ALPHA / DIGIT / '-' '.' '_' '~', so no whitespace.
/// Params: v - the candidate verifier. Returns: the predicate.
/// Error case: none. Complexity: O(v.len()).
pub fn oauth_pkce_verifier_is_valid(v: Str) -> Bool {
  let r = _pkce_verifier_check(v);
  return r.is_ok;
}

/// Validate a PKCE code verifier with a detailed error.
/// Params: v - the candidate verifier.
/// Returns: Ok("") when valid.
/// Error case: Err("oauth: pkce verifier length out of range (43..128)") or
/// Err("oauth: pkce verifier bad character at offset N") (offset into v).
/// Complexity: O(v.len()).
pub fn oauth_pkce_verifier_check(v: Str) -> Result[Str, Str] {
  return _pkce_verifier_check(v);
}

/// The plain PKCE challenge of a verifier: the verifier itself (RFC 7636
/// section 4.2), returned only after validating the verifier.
/// Params: verifier - the code verifier.
/// Returns: Ok(verifier) when the verifier is valid.
/// Error case: the oauth_pkce_verifier_check catalog.
/// Complexity: O(verifier.len()).
pub fn oauth_pkce_plain_challenge(verifier: Str) -> Result[Str, Str] {
  let r = _pkce_verifier_check(verifier);
  if !r.is_ok {
    return _err_str(r.error);
  }
  return _ok_str(verifier);
}

/// True when `challenge` equals `verifier` for the plain method, after
/// validating the verifier (an invalid verifier never matches).
/// Params: verifier - the code verifier; challenge - the received
/// code_challenge. Returns: the predicate.
/// Error case: none. Complexity: O(verifier.len()).
pub fn oauth_pkce_plain_matches(verifier: Str, challenge: Str) -> Bool {
  let r = _pkce_verifier_check(verifier);
  if !r.is_ok {
    return false;
  }
  if compare.str_compare(verifier, challenge) == 0 {
    return true;
  }
  return false;
}

// Unpadded base64url encoding of raw bytes.
fn _b64url_encode(data: &Vec[UInt8]) -> Str {
  var out = Vec[UInt8].new();
  let n = data.len();
  var i = 0;
  while i + 3 <= n {
    let b0 = _vbyte(data, i);
    let b1 = _vbyte(data, i + 1);
    let b2 = _vbyte(data, i + 2);
    out.push(string.byte_at(_B64URL_ALPHABET, b0 >> 2));
    out.push(string.byte_at(_B64URL_ALPHABET, ((b0 & 3) << 4) | (b1 >> 4)));
    out.push(string.byte_at(_B64URL_ALPHABET, ((b1 & 15) << 2) | (b2 >> 6)));
    out.push(string.byte_at(_B64URL_ALPHABET, b2 & 63));
    i = i + 3;
  }
  let rem = n - i;
  if rem == 1 {
    let b0 = _vbyte(data, i);
    out.push(string.byte_at(_B64URL_ALPHABET, b0 >> 2));
    out.push(string.byte_at(_B64URL_ALPHABET, (b0 & 3) << 4));
  } elif rem == 2 {
    let b0 = _vbyte(data, i);
    let b1 = _vbyte(data, i + 1);
    out.push(string.byte_at(_B64URL_ALPHABET, b0 >> 2));
    out.push(string.byte_at(_B64URL_ALPHABET, ((b0 & 3) << 4) | (b1 >> 4)));
    out.push(string.byte_at(_B64URL_ALPHABET, (b1 & 15) << 2));
  }
  return builder.sb_to_str(&out);
}

/// Base64url-encode a CALLER-COMPUTED SHA-256 digest for the S256 PKCE
/// method (RFC 7636 section 4.2). This module never hashes: the caller
/// runs SHA-256 over the verifier and passes the 32 raw digest bytes.
/// Params: hash - the 32-byte SHA-256 digest.
/// Returns: Ok(challenge) with unpadded base64url (43 characters) for a
/// 32-byte input.
/// Error case: Err("oauth: pkce s256 hash must be 32 bytes") otherwise.
/// Complexity: O(hash.len()).
pub fn oauth_pkce_s256_challenge(hash: &Vec[UInt8]) -> Result[Str, Str] {
  if hash.len() != _OAUTH_S256_BYTES {
    return _err_str("oauth: pkce s256 hash must be 32 bytes");
  }
  return _ok_str(_b64url_encode(hash));
}

/// True when `challenge` is well formed for `method` ("plain" or "S256";
/// an empty method means the RFC 7636 default "plain").
/// Params: challenge - the candidate; method - the method name.
/// Returns: the predicate (false for an empty challenge or unknown method).
/// Error case: none. Complexity: O(challenge.len()).
pub fn oauth_pkce_challenge_is_valid(challenge: Str, method: Str) -> Bool {
  if challenge.len() == 0 {
    return false;
  }
  if method.len() == 0 || compare.str_compare(method, "plain") == 0 {
    let r = _pkce_verifier_check(challenge);
    return r.is_ok;
  }
  if compare.str_compare(method, "S256") == 0 {
    let r2 = _s256_check(challenge);
    return r2.is_ok;
  }
  return false;
}

// --------------------------------------------------
//  Known-name sets and duplicate detection
// --------------------------------------------------

// Known authorization request parameter names, in wire order.
fn _authz_request_known() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("response_type");
  v.push("client_id");
  v.push("redirect_uri");
  v.push("scope");
  v.push("state");
  v.push("code_challenge");
  v.push("code_challenge_method");
  return v;
}

// Known authorization response parameter names, in wire order.
fn _authz_response_known() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("code");
  v.push("state");
  v.push("error");
  v.push("error_description");
  v.push("error_uri");
  return v;
}

// Known token request parameter names, in wire order.
fn _token_request_known() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("grant_type");
  v.push("code");
  v.push("redirect_uri");
  v.push("refresh_token");
  v.push("scope");
  v.push("client_id");
  v.push("client_secret");
  return v;
}

// True when name is one of names (linear scan; sets are tiny).
fn _name_in(name: Str, names: &Vec[Str]) -> Bool {
  var i = 0;
  while i < names.len() {
    let cur: Str = names[i];
    if compare.str_compare(cur, name) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Reject a duplicated known parameter: for every pair whose name is known,
// any earlier pair with the same name is a duplicate (RFC 6749 section 3.1:
// a parameter MUST NOT appear more than once).
fn _dup_check(p: &OAuthParams, known: &Vec[Str]) -> Result[Str, Str] {
  var i = 0;
  while i < p.names.len() {
    let cur: Str = p.names[i];
    if _name_in(cur, known) {
      var j = 0;
      while j < i {
        let prev: Str = p.names[j];
        if compare.str_compare(prev, cur) == 0 {
          return _err_str("oauth: duplicate parameter: " + cur);
        }
        j = j + 1;
      }
    }
    i = i + 1;
  }
  return _ok_str("");
}

// Copy every pair whose name is not known, preserving order.
fn _extract_extras(p: &OAuthParams, known: &Vec[Str]) -> OAuthParams {
  var ex = oauth_params_new();
  var i = 0;
  while i < p.names.len() {
    let cur: Str = p.names[i];
    if !_name_in(cur, known) {
      let v: Str = p.values[i];
      ex.names.push(cur);
      ex.values.push(v);
    }
    i = i + 1;
  }
  return ex;
}

// --------------------------------------------------
//  Authorization request
// --------------------------------------------------

/// Build an authorization request (no validation shortcuts: the result is
/// already checked, so oauth_authz_request_encode cannot fail on it).
/// Params: response_type - "code" or "token"; client_id - non-empty;
/// redirect_uri - "" when absent; scope - token list (may be empty);
/// state - "" when absent; code_challenge / code_challenge_method - PKCE
/// pair ("" when absent; a challenge without a method means "plain").
/// Returns: Ok(request) with empty extras.
/// Error case: Err for a non-registered response_type, an empty client_id,
/// an invalid scope token, or the _pkce_pair_check catalog.
/// Complexity: O(total input).
pub fn oauth_authz_request(response_type: Str, client_id: Str, redirect_uri: Str,
                           scope: &Vec[Str], state: Str,
                           code_challenge: Str, code_challenge_method: Str) -> Result[AuthzRequest, Str] {
  if !oauth_response_type_is_valid(response_type) {
    return _err_authz_request("oauth: unsupported response_type: " + response_type);
  }
  if client_id.len() == 0 {
    return _err_authz_request("oauth: empty client_id");
  }
  let sc = _scope_tokens_check(scope);
  if !sc.is_ok {
    return _err_authz_request(sc.error);
  }
  let pc = _pkce_pair_check(code_challenge, code_challenge_method);
  if !pc.is_ok {
    return _err_authz_request(pc.error);
  }
  let scope_copy = _copy_strs(scope);
  var req = _authz_request_empty();
  req.response_type = response_type;
  req.client_id = client_id;
  req.redirect_uri = redirect_uri;
  req.scope = scope_copy;
  req.state = state;
  req.code_challenge = code_challenge;
  req.code_challenge_method = code_challenge_method;
  return _ok_authz_request(req);
}

// Fresh authorization request with every field empty and no extras.
fn _authz_request_empty() -> AuthzRequest {
  return AuthzRequest{
    response_type: "";
    client_id: "";
    redirect_uri: "";
    scope: Vec[Str].new();
    state: "";
    code_challenge: "";
    code_challenge_method: "";
    extra: OAuthParams{ names: Vec[Str].new(), values: Vec[Str].new() };
  };
}

/// Attach an extra (non-registered) parameter, preserved in insertion
/// order. Registered names are rejected so a duplicate cannot be smuggled
/// in; empty names are rejected.
/// Params: req - the request to grow; name/value - the pair.
/// Returns: Ok("") on success.
/// Error case: Err("oauth: empty parameter name") or
/// Err("oauth: reserved parameter: <name>").
/// Complexity: O(name.len()).
pub fn oauth_authz_request_add_extra(req: &mut AuthzRequest, name: Str, value: Str) -> Result[Str, Str] {
  if name.len() == 0 {
    return _err_str("oauth: empty parameter name");
  }
  let known = _authz_request_known();
  if _name_in(name, &known) {
    return _err_str("oauth: reserved parameter: " + name);
  }
  req.extra.names.push(name);
  req.extra.values.push(value);
  return _ok_str("");
}

/// Encode an authorization request as the query component to append to the
/// authorization endpoint (no leading '?'; the caller owns the URL and the
/// transport). Field order is fixed: response_type, client_id,
/// redirect_uri, scope, state, code_challenge, code_challenge_method, then
/// extras. Absent optional fields are omitted.
/// Params: req - the request.
/// Returns: Ok(query) for a structurally valid request.
/// Error case: Err("oauth: unsupported response_type: <v>"), Err("oauth:
/// empty client_id"), the scope token errors and the _pkce_pair_check
/// catalog.
/// Complexity: O(total text).
pub fn oauth_authz_request_encode(req: &AuthzRequest) -> Result[Str, Str] {
  let rt: Str = req.response_type;
  if !oauth_response_type_is_valid(rt) {
    return _err_str("oauth: unsupported response_type: " + rt);
  }
  let cid: Str = req.client_id;
  if cid.len() == 0 {
    return _err_str("oauth: empty client_id");
  }
  let sc: Vec[Str] = req.scope;
  let scc = _scope_tokens_check(&sc);
  if !scc.is_ok {
    return _err_str(scc.error);
  }
  let cc: Str = req.code_challenge;
  let cm: Str = req.code_challenge_method;
  let pc = _pkce_pair_check(cc, cm);
  if !pc.is_ok {
    return _err_str(pc.error);
  }
  var out = Vec[UInt8].new();
  _push_form_pair(&mut out, "response_type", rt);
  _push_form_pair(&mut out, "client_id", cid);
  let ru: Str = req.redirect_uri;
  if ru.len() > 0 {
    _push_form_pair(&mut out, "redirect_uri", ru);
  }
  if sc.len() > 0 {
    let joined = _scope_join(&sc);
    _push_form_pair(&mut out, "scope", joined);
  }
  let st: Str = req.state;
  if st.len() > 0 {
    _push_form_pair(&mut out, "state", st);
  }
  if cc.len() > 0 {
    _push_form_pair(&mut out, "code_challenge", cc);
  }
  if cm.len() > 0 {
    _push_form_pair(&mut out, "code_challenge_method", cm);
  }
  let ex: OAuthParams = req.extra;
  var i = 0;
  while i < ex.names.len() {
    let n: Str = ex.names[i];
    let v: Str = ex.values[i];
    _push_form_pair(&mut out, n, v);
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&out));
}

/// Parse an authorization request query component.
/// Params: query - the form-encoded query (no leading '?'). Known
/// parameters are the seven of _authz_request_known; every other parameter
/// is preserved in `extra` in order. A duplicated known parameter is an
/// error. Required: response_type (code|token) and a non-empty client_id;
/// scope is split on single spaces; code_challenge is validated per method
/// with the default "plain".
/// Returns: Ok(request) on success.
/// Error case: the _parse_form catalog, Err("oauth: duplicate parameter:
/// <name>"), Err("oauth: missing parameter: response_type"), Err("oauth:
/// missing parameter: client_id"), Err("oauth: empty client_id"), Err(
/// "oauth: unsupported response_type: <v>"), the scope split errors and the
/// _pkce_pair_check catalog.
/// Complexity: O(query.len()).
pub fn oauth_authz_request_parse(query: Str) -> Result[AuthzRequest, Str] {
  var p = oauth_params_new();
  let pr = _parse_form(query, &mut p);
  if !pr.is_ok {
    return _err_authz_request(pr.error);
  }
  let known = _authz_request_known();
  let dc = _dup_check(&p, &known);
  if !dc.is_ok {
    return _err_authz_request(dc.error);
  }
  if !oauth_params_has(&p, "response_type") {
    return _err_authz_request("oauth: missing parameter: response_type");
  }
  let rt: Str = _params_get_or_empty(&p, "response_type");
  if !oauth_response_type_is_valid(rt) {
    return _err_authz_request("oauth: unsupported response_type: " + rt);
  }
  if !oauth_params_has(&p, "client_id") {
    return _err_authz_request("oauth: missing parameter: client_id");
  }
  let cid: Str = _params_get_or_empty(&p, "client_id");
  if cid.len() == 0 {
    return _err_authz_request("oauth: empty client_id");
  }
  let ru: Str = _params_get_or_empty(&p, "redirect_uri");
  let st: Str = _params_get_or_empty(&p, "state");
  let cc: Str = _params_get_or_empty(&p, "code_challenge");
  let cm: Str = _params_get_or_empty(&p, "code_challenge_method");
  let pc = _pkce_pair_check(cc, cm);
  if !pc.is_ok {
    return _err_authz_request(pc.error);
  }
  var sc = Vec[Str].new();
  if oauth_params_has(&p, "scope") {
    let scv: Str = _params_get_or_empty(&p, "scope");
    let scr = _split_scope_into(scv, &mut sc);
    if !scr.is_ok {
      return _err_authz_request(scr.error);
    }
  }
  let ex = _extract_extras(&p, &known);
  var req = _authz_request_empty();
  req.response_type = rt;
  req.client_id = cid;
  req.redirect_uri = ru;
  req.scope = sc;
  req.state = st;
  req.code_challenge = cc;
  req.code_challenge_method = cm;
  req.extra = ex;
  return _ok_authz_request(req);
}

// --------------------------------------------------
//  Authorization response
// --------------------------------------------------

// Fresh authorization response with every field empty and no extras.
fn _authz_response_empty() -> AuthzResponse {
  return AuthzResponse{
    code: "";
    state: "";
    error: "";
    error_description: "";
    error_uri: "";
    extra: OAuthParams{ names: Vec[Str].new(), values: Vec[Str].new() };
  };
}

/// Parse an authorization response query component (the redirect back to
/// the client): either code (+ optional state) or error (+ optional
/// error_description / error_uri). Unknown parameters are preserved in
/// `extra`. A response carrying both code and error is rejected, as are an
/// unregistered error code and a non-empty `code` missing its value.
/// Params: query - the form-encoded query (no leading '?').
/// Returns: Ok(response) on success.
/// Error case: the _parse_form catalog, Err("oauth: duplicate parameter:
/// <name>"), Err("oauth: code with error"), Err("oauth: empty error code"),
/// Err("oauth: unsupported error code: <v>"), Err("oauth: missing
/// parameter: code"), Err("oauth: empty code").
/// Complexity: O(query.len()).
pub fn oauth_authz_response_parse(query: Str) -> Result[AuthzResponse, Str] {
  var p = oauth_params_new();
  let pr = _parse_form(query, &mut p);
  if !pr.is_ok {
    return _err_authz_response(pr.error);
  }
  let known = _authz_response_known();
  let dc = _dup_check(&p, &known);
  if !dc.is_ok {
    return _err_authz_response(dc.error);
  }
  let has_code = oauth_params_has(&p, "code");
  let has_error = oauth_params_has(&p, "error");
  let code: Str = _params_get_or_empty(&p, "code");
  let err: Str = _params_get_or_empty(&p, "error");
  let desc: Str = _params_get_or_empty(&p, "error_description");
  let uri: Str = _params_get_or_empty(&p, "error_uri");
  let st: Str = _params_get_or_empty(&p, "state");
  if has_error && has_code {
    return _err_authz_response("oauth: code with error");
  }
  if has_error {
    if err.len() == 0 {
      return _err_authz_response("oauth: empty error code");
    }
    if !oauth_authz_error_is_valid(err) {
      return _err_authz_response("oauth: unsupported error code: " + err);
    }
  } else {
    if !has_code {
      return _err_authz_response("oauth: missing parameter: code");
    }
    if code.len() == 0 {
      return _err_authz_response("oauth: empty code");
    }
  }
  let ex = _extract_extras(&p, &known);
  var resp = _authz_response_empty();
  resp.code = code;
  resp.state = st;
  resp.error = err;
  resp.error_description = desc;
  resp.error_uri = uri;
  resp.extra = ex;
  return _ok_authz_response(resp);
}

// --------------------------------------------------
//  Token request
// --------------------------------------------------

// Grant-specific field rules. `client_id`/`client_secret` are not
// constrained (body client authentication is optional here).
fn _grant_fields_check(grant_type: Str, code: Str, redirect_uri: Str,
                       refresh_token: Str) -> Result[Str, Str] {
  if !oauth_grant_type_is_valid(grant_type) {
    return _err_str("oauth: unsupported grant_type: " + grant_type);
  }
  if compare.str_compare(grant_type, "authorization_code") == 0 {
    if code.len() == 0 {
      return _err_str("oauth: missing code");
    }
    if refresh_token.len() > 0 {
      return _err_str("oauth: unexpected refresh_token");
    }
    return _ok_str("");
  }
  if compare.str_compare(grant_type, "refresh_token") == 0 {
    if refresh_token.len() == 0 {
      return _err_str("oauth: missing refresh_token");
    }
    if code.len() > 0 {
      return _err_str("oauth: unexpected code");
    }
    return _ok_str("");
  }
  if code.len() > 0 {
    return _err_str("oauth: unexpected code");
  }
  if redirect_uri.len() > 0 {
    return _err_str("oauth: unexpected redirect_uri");
  }
  if refresh_token.len() > 0 {
    return _err_str("oauth: unexpected refresh_token");
  }
  return _ok_str("");
}

// Fresh token request with every field empty and no extras.
fn _token_request_empty() -> TokenRequest {
  return TokenRequest{
    grant_type: "";
    code: "";
    redirect_uri: "";
    refresh_token: "";
    scope: Vec[Str].new();
    client_id: "";
    client_secret: "";
    extra: OAuthParams{ names: Vec[Str].new(), values: Vec[Str].new() };
  };
}

/// Build a token endpoint request for one of the three supported grants.
/// Params: grant_type - authorization_code|refresh_token|
/// client_credentials; code - the authorization code ("" unless
/// authorization_code); redirect_uri - "" when absent; refresh_token - the
/// refresh token ("" unless refresh_token); scope - token list (may be
/// empty); client_id / client_secret - optional body client authentication
/// ("" when absent).
/// Returns: Ok(request) with empty extras.
/// Error case: _grant_fields_check catalog (unsupported grant_type, missing
/// code, missing refresh_token, unexpected code/redirect_uri/refresh_token)
/// and the scope token errors.
/// Complexity: O(total input).
pub fn oauth_token_request(grant_type: Str, code: Str, redirect_uri: Str,
                           refresh_token: Str, scope: &Vec[Str],
                           client_id: Str, client_secret: Str) -> Result[TokenRequest, Str] {
  let gr = _grant_fields_check(grant_type, code, redirect_uri, refresh_token);
  if !gr.is_ok {
    return _err_token_request(gr.error);
  }
  let sc = _scope_tokens_check(scope);
  if !sc.is_ok {
    return _err_token_request(sc.error);
  }
  let scope_copy = _copy_strs(scope);
  var req = _token_request_empty();
  req.grant_type = grant_type;
  req.code = code;
  req.redirect_uri = redirect_uri;
  req.refresh_token = refresh_token;
  req.scope = scope_copy;
  req.client_id = client_id;
  req.client_secret = client_secret;
  return _ok_token_request(req);
}

/// Attach an extra (non-registered) parameter, preserved in insertion
/// order. Registered names are rejected; empty names are rejected.
/// Params: req - the request to grow; name/value - the pair.
/// Returns: Ok("") on success.
/// Error case: Err("oauth: empty parameter name") or
/// Err("oauth: reserved parameter: <name>").
/// Complexity: O(name.len()).
pub fn oauth_token_request_add_extra(req: &mut TokenRequest, name: Str, value: Str) -> Result[Str, Str] {
  if name.len() == 0 {
    return _err_str("oauth: empty parameter name");
  }
  let known = _token_request_known();
  if _name_in(name, &known) {
    return _err_str("oauth: reserved parameter: " + name);
  }
  req.extra.names.push(name);
  req.extra.values.push(value);
  return _ok_str("");
}

/// Encode a token request as the form body of a POST to the token
/// endpoint. Field order is fixed: grant_type, code, redirect_uri,
/// refresh_token, scope, client_id, client_secret, then extras. Absent
/// optional fields are omitted.
/// Params: req - the request.
/// Returns: Ok(body) for a structurally valid request.
/// Error case: the oauth_token_request catalog.
/// Complexity: O(total text).
pub fn oauth_token_request_encode(req: &TokenRequest) -> Result[Str, Str] {
  let gt: Str = req.grant_type;
  let code: Str = req.code;
  let ru: Str = req.redirect_uri;
  let rtok: Str = req.refresh_token;
  let gr = _grant_fields_check(gt, code, ru, rtok);
  if !gr.is_ok {
    return _err_str(gr.error);
  }
  let sc: Vec[Str] = req.scope;
  let scc = _scope_tokens_check(&sc);
  if !scc.is_ok {
    return _err_str(scc.error);
  }
  var out = Vec[UInt8].new();
  _push_form_pair(&mut out, "grant_type", gt);
  if code.len() > 0 {
    _push_form_pair(&mut out, "code", code);
  }
  if ru.len() > 0 {
    _push_form_pair(&mut out, "redirect_uri", ru);
  }
  if rtok.len() > 0 {
    _push_form_pair(&mut out, "refresh_token", rtok);
  }
  if sc.len() > 0 {
    let joined = _scope_join(&sc);
    _push_form_pair(&mut out, "scope", joined);
  }
  let cid: Str = req.client_id;
  if cid.len() > 0 {
    _push_form_pair(&mut out, "client_id", cid);
  }
  let csec: Str = req.client_secret;
  if csec.len() > 0 {
    _push_form_pair(&mut out, "client_secret", csec);
  }
  let ex: OAuthParams = req.extra;
  var i = 0;
  while i < ex.names.len() {
    let n: Str = ex.names[i];
    let v: Str = ex.values[i];
    _push_form_pair(&mut out, n, v);
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&out));
}

/// Parse a token request body.
/// Params: body - the form-encoded POST body (no leading '?'). Known
/// parameters are the seven of _token_request_known; other parameters are
/// preserved in `extra`. Duplicated known parameters, a missing or
/// unregistered grant_type and grant-specific field violations are errors.
/// Returns: Ok(request) on success.
/// Error case: the _parse_form catalog, Err("oauth: duplicate parameter:
/// <name>"), Err("oauth: missing parameter: grant_type"), the
/// _grant_fields_check catalog and the scope split errors.
/// Complexity: O(body.len()).
pub fn oauth_token_request_parse(body: Str) -> Result[TokenRequest, Str] {
  var p = oauth_params_new();
  let pr = _parse_form(body, &mut p);
  if !pr.is_ok {
    return _err_token_request(pr.error);
  }
  let known = _token_request_known();
  let dc = _dup_check(&p, &known);
  if !dc.is_ok {
    return _err_token_request(dc.error);
  }
  if !oauth_params_has(&p, "grant_type") {
    return _err_token_request("oauth: missing parameter: grant_type");
  }
  let gt: Str = _params_get_or_empty(&p, "grant_type");
  let code: Str = _params_get_or_empty(&p, "code");
  let ru: Str = _params_get_or_empty(&p, "redirect_uri");
  let rtok: Str = _params_get_or_empty(&p, "refresh_token");
  let cid: Str = _params_get_or_empty(&p, "client_id");
  let csec: Str = _params_get_or_empty(&p, "client_secret");
  let gr = _grant_fields_check(gt, code, ru, rtok);
  if !gr.is_ok {
    return _err_token_request(gr.error);
  }
  var sc = Vec[Str].new();
  if oauth_params_has(&p, "scope") {
    let scv: Str = _params_get_or_empty(&p, "scope");
    let scr = _split_scope_into(scv, &mut sc);
    if !scr.is_ok {
      return _err_token_request(scr.error);
    }
  }
  let ex = _extract_extras(&p, &known);
  var req = _token_request_empty();
  req.grant_type = gt;
  req.code = code;
  req.redirect_uri = ru;
  req.refresh_token = rtok;
  req.scope = sc;
  req.client_id = cid;
  req.client_secret = csec;
  req.extra = ex;
  return _ok_token_request(req);
}

// --------------------------------------------------
//  JSON key lookups (token response subset)
// --------------------------------------------------

/// Upper bound on JSON text scanned. Params: none.
/// Returns: 65536. Error case: none. Complexity: O(1).
pub fn oauth_max_json_bytes() -> Int {
  return _OAUTH_MAX_JSON;
}

// True when text[kstart, kstart + key.len()) equals key and is followed by
// a closing quote (kstart points just after the opening quote).
fn _json_key_matches(text: &Vec[UInt8], kstart: Int, key: Str) -> Bool {
  if kstart + key.len() >= text.len() {
    return false;
  }
  var i = 0;
  while i < key.len() {
    let kc = (string.byte_at(key, i) as Int) & 0xFF;
    if _vbyte(text, kstart + i) != kc {
      return false;
    }
    i = i + 1;
  }
  return _vbyte(text, kstart + key.len()) == _OAUTH_QUOTE;
}

// Span of the first scalar value of the top-level member `key` in the
// object text: (start, end), quotes included for strings. Keys are only
// recognised at an object boundary (start, after '{', ',', or
// whitespace), so key text inside a string value never matches. String
// values are scanned escape-aware. Composite values ({...}/[...]) yield
// Err("oauth: json bad value: <key>"); a missing key yields Err("oauth:
// json key not found: <key>"); raw control bytes yield Err("oauth: json
// control byte at offset N").
fn _json_find(text: &Vec[UInt8], key: Str) -> Result[(Int, Int), Str] {
  if key.len() == 0 {
    return _err_pair("oauth: json empty key");
  }
  let n = text.len();
  if n > _OAUTH_MAX_JSON {
    return _err_pair("oauth: json too large");
  }
  var i = 0;
  while i < n {
    if _json_control(_vbyte(text, i)) {
      return _err_pair(_perr("json control byte", i));
    }
    if _vbyte(text, i) == _OAUTH_QUOTE {
      var boundary = false;
      if i == 0 {
        boundary = true;
      } else {
        let before = _vbyte(text, i - 1);
        if before == _OAUTH_LBRACE || before == _OAUTH_COMMA || before == _OAUTH_SPACE {
          boundary = true;
        }
        if before == _OAUTH_CR || before == _OAUTH_LF || before == _OAUTH_TAB {
          boundary = true;
        }
      }
      if boundary && _json_key_matches(text, i + 1, key) {
        var j = i + 2 + key.len();
        while j < n && _vbyte(text, j) == _OAUTH_SPACE {
          j = j + 1;
        }
        if j < n && _vbyte(text, j) == _OAUTH_COLON {
          j = j + 1;
          while j < n && _vbyte(text, j) == _OAUTH_SPACE {
            j = j + 1;
          }
          if j >= n {
            return _err_pair("oauth: json bad value: " + key);
          }
          let vs = j;
          let vc = _vbyte(text, j);
          if vc == _OAUTH_QUOTE {
            j = j + 1;
            var closed = false;
            while j < n {
              let c = _vbyte(text, j);
              if _json_control(c) {
                return _err_pair(_perr("json control byte", j));
              }
              if c == _OAUTH_BACKSLASH {
                if j + 1 >= n {
                  return _err_pair("oauth: json bad value: " + key);
                }
                let nc = _vbyte(text, j + 1);
                if _json_control(nc) {
                  return _err_pair(_perr("json control byte", j + 1));
                }
                j = j + 2;
              } elif c == _OAUTH_QUOTE {
                closed = true;
                j = j + 1;
                break;
              } else {
                j = j + 1;
              }
            }
            if !closed {
              return _err_pair("oauth: json bad value: " + key);
            }
            return _ok_pair((vs, j));
          }
          if vc == _OAUTH_LBRACE || vc == _OAUTH_LBRACKET {
            return _err_pair("oauth: json bad value: " + key);
          }
          while j < n {
            let c2 = _vbyte(text, j);
            if c2 == _OAUTH_COMMA || c2 == _OAUTH_RBRACE || c2 == _OAUTH_LBRACKET {
              break;
            }
            if _json_ws(c2) {
              break;
            }
            if _json_control(c2) {
              return _err_pair(_perr("json control byte", j));
            }
            j = j + 1;
          }
          if j == vs {
            return _err_pair("oauth: json bad value: " + key);
          }
          return _ok_pair((vs, j));
        }
      }
    }
    i = i + 1;
  }
  return _err_pair("oauth: json key not found: " + key);
}

/// True when the object text carries a scalar top-level member `key`.
/// Params: text - JSON object text as raw bytes; key - the member name.
/// Returns: the predicate (false for a missing key and for composite
/// values). Error case: none. Complexity: O(len(text)).
pub fn oauth_json_has(text: &Vec[UInt8], key: Str) -> Bool {
  let r = _json_find(text, key);
  return r.is_ok;
}

/// Byte span of the first scalar value of the top-level member `key`,
/// quotes included for strings.
/// Params: text - JSON object text as raw bytes; key - the member name.
/// Returns: Ok((start, end)).
/// Error case: Err("oauth: json empty key"), Err("oauth: json too large"),
/// Err("oauth: json control byte at offset N"), Err("oauth: json key not
/// found: <key>"), Err("oauth: json bad value: <key>").
/// Complexity: O(len(text)).
pub fn oauth_json_span(text: &Vec[UInt8], key: Str) -> Result[(Int, Int), Str] {
  return _json_find(text, key);
}

/// String value of the top-level member `key`, quotes stripped, escapes
/// left exactly as written (no unescaping; the scanner only guarantees
/// that escaped quotes do not terminate the value).
/// Params: text - JSON object text as raw bytes; key - the member name.
/// Returns: Ok(inner bytes as a Str).
/// Error case: the oauth_json_span catalog; a non-string value yields
/// Err("oauth: json bad value: <key>").
/// Complexity: O(len(text)).
pub fn oauth_json_str(text: &Vec[UInt8], key: Str) -> Result[Str, Str] {
  let r = _json_find(text, key);
  if !r.is_ok {
    return _err_str(r.error);
  }
  let sp = r.value;
  let a: Int = sp.0;
  let b: Int = sp.1;
  if b - a < 2 {
    return _err_str("oauth: json bad value: " + key);
  }
  if _vbyte(text, a) != _OAUTH_QUOTE {
    return _err_str("oauth: json bad value: " + key);
  }
  var out = Vec[UInt8].new();
  _copy_span(text, a + 1, b - 1, &mut out);
  return _ok_str(builder.sb_to_str(&out));
}

/// Integer value of the top-level member `key`: an optional '-' sign then
/// one or more digits, magnitude at most 2147483647.
/// Params: text - JSON object text as raw bytes; key - the member name.
/// Returns: Ok(value).
/// Error case: the oauth_json_span catalog; a non-integer, a bare sign or
/// an out-of-range magnitude yields Err("oauth: json bad value: <key>").
/// Complexity: O(len(text)).
pub fn oauth_json_int(text: &Vec[UInt8], key: Str) -> Result[Int, Str] {
  let r = _json_find(text, key);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let sp = r.value;
  let a: Int = sp.0;
  let b: Int = sp.1;
  var i = a;
  var neg = false;
  if _vbyte(text, i) == _OAUTH_MINUS {
    neg = true;
    i = i + 1;
  }
  if i >= b {
    return _err_int("oauth: json bad value: " + key);
  }
  let lim = _OAUTH_MAX_INT / 10;
  let rem = _OAUTH_MAX_INT % 10;
  var v: Int = 0;
  while i < b {
    let c = _vbyte(text, i);
    if !_is_digit(c) {
      return _err_int("oauth: json bad value: " + key);
    }
    let d = c - 48;
    if v > lim {
      return _err_int("oauth: json bad value: " + key);
    }
    if v == lim && d > rem {
      return _err_int("oauth: json bad value: " + key);
    }
    v = v * 10 + d;
    i = i + 1;
  }
  if neg {
    return _ok_int(0 - v);
  }
  return _ok_int(v);
}

// Digits-only non-negative integer value of `key` (expires_in).
fn _json_uint(text: &Vec[UInt8], key: Str) -> Result[Int, Str] {
  let r = _json_find(text, key);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let sp = r.value;
  let a: Int = sp.0;
  let b: Int = sp.1;
  if a >= b {
    return _err_int("oauth: json bad value: " + key);
  }
  let lim = _OAUTH_MAX_INT / 10;
  let rem = _OAUTH_MAX_INT % 10;
  var v: Int = 0;
  var i = a;
  while i < b {
    let c = _vbyte(text, i);
    if !_is_digit(c) {
      return _err_int("oauth: json bad value: " + key);
    }
    let d = c - 48;
    if v > lim {
      return _err_int("oauth: json bad value: " + key);
    }
    if v == lim && d > rem {
      return _err_int("oauth: json bad value: " + key);
    }
    v = v * 10 + d;
    i = i + 1;
  }
  return _ok_int(v);
}

// --------------------------------------------------
//  Token response
// --------------------------------------------------

// Fresh token response: no token, no error, expires_in absent.
fn _token_response_empty() -> TokenResponse {
  return TokenResponse{
    access_token: "";
    token_type: "";
    expires_in: 0;
    expires_in_present: false;
    refresh_token: "";
    scope: Vec[Str].new();
    error: "";
    error_description: "";
  };
}

// True when data[a, b) holds a raw control byte (other than TAB/LF/CR).
fn _json_span_bad_control(data: &Vec[UInt8], a: Int, b: Int) -> Bool {
  var i = a;
  while i < b {
    if _json_control(_vbyte(data, i)) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// Parse a token endpoint response body: a JSON object carrying either an
/// access token (access_token required, token_type must be "Bearer" case-
/// insensitively, expires_in optional digits-only, refresh_token and scope
/// optional) or an error (registered 5.2 code plus optional
/// error_description; an access_token next to an error is rejected).
/// Unknown JSON members are ignored (this is a lookup helper, not a JSON
/// parser) and string escapes are not unescaped.
/// Params: json - the response body text.
/// Returns: Ok(response) on success; `expires_in` is meaningful only when
/// `expires_in_present` is true; a present-but-empty refresh_token/scope
/// stays empty.
/// Error case: Err("oauth: json not an object"), the oauth_json_* catalog,
/// Err("oauth: access_token with error"), Err("oauth: empty error code"),
/// Err("oauth: unsupported error code: <v>"), Err("oauth: missing
/// access_token"), Err("oauth: empty access_token"), Err("oauth: missing
/// token_type"), Err("oauth: unsupported token_type: <v>"), Err("oauth:
/// invalid expires_in"), and the scope split errors.
/// Complexity: O(json.len()).
pub fn oauth_token_response_parse(json: Str) -> Result[TokenResponse, Str] {
  let data = _str_bytes(json);
  let n = data.len();
  var a = 0;
  var b = n;
  while a < b && _json_ws(_vbyte(&data, a)) {
    a = a + 1;
  }
  while b > a && _json_ws(_vbyte(&data, b - 1)) {
    b = b - 1;
  }
  if b - a < 2 {
    return _err_token_response("oauth: json not an object");
  }
  if _vbyte(&data, a) != _OAUTH_LBRACE {
    return _err_token_response("oauth: json not an object");
  }
  if _vbyte(&data, b - 1) != _OAUTH_RBRACE {
    return _err_token_response("oauth: json not an object");
  }
  if _json_span_bad_control(&data, a, b) {
    return _err_token_response("oauth: json not an object");
  }
  let has_error = oauth_json_has(&data, "error");
  let has_access = oauth_json_has(&data, "access_token");
  if has_error && has_access {
    return _err_token_response("oauth: access_token with error");
  }
  if has_error {
    let er = oauth_json_str(&data, "error");
    if !er.is_ok {
      return _err_token_response(er.error);
    }
    let ev: Str = er.value;
    if ev.len() == 0 {
      return _err_token_response("oauth: empty error code");
    }
    if !oauth_token_error_is_valid(ev) {
      return _err_token_response("oauth: unsupported error code: " + ev);
    }
    var resp = _token_response_empty();
    resp.error = ev;
    if oauth_json_has(&data, "error_description") {
      let dr = oauth_json_str(&data, "error_description");
      if !dr.is_ok {
        return _err_token_response(dr.error);
      }
      resp.error_description = dr.value;
    }
    return _ok_token_response(resp);
  }
  if !has_access {
    return _err_token_response("oauth: missing access_token");
  }
  let ar = oauth_json_str(&data, "access_token");
  if !ar.is_ok {
    return _err_token_response(ar.error);
  }
  let av: Str = ar.value;
  if av.len() == 0 {
    return _err_token_response("oauth: empty access_token");
  }
  if !oauth_json_has(&data, "token_type") {
    return _err_token_response("oauth: missing token_type");
  }
  let ttr = oauth_json_str(&data, "token_type");
  if !ttr.is_ok {
    return _err_token_response(ttr.error);
  }
  let tv: Str = ttr.value;
  if !compare.str_eq_ignore_case(tv, "Bearer") {
    return _err_token_response("oauth: unsupported token_type: " + tv);
  }
  var resp2 = _token_response_empty();
  resp2.access_token = av;
  resp2.token_type = tv;
  if oauth_json_has(&data, "expires_in") {
    let ei = _json_uint(&data, "expires_in");
    if !ei.is_ok {
      return _err_token_response("oauth: invalid expires_in");
    }
    resp2.expires_in = ei.value;
    resp2.expires_in_present = true;
  }
  if oauth_json_has(&data, "refresh_token") {
    let rr = oauth_json_str(&data, "refresh_token");
    if !rr.is_ok {
      return _err_token_response(rr.error);
    }
    resp2.refresh_token = rr.value;
  }
  if oauth_json_has(&data, "scope") {
    let sr = oauth_json_str(&data, "scope");
    if !sr.is_ok {
      return _err_token_response(sr.error);
    }
    let sv: Str = sr.value;
    var sc = Vec[Str].new();
    let spr = _split_scope_into(sv, &mut sc);
    if !spr.is_ok {
      return _err_token_response(spr.error);
    }
    resp2.scope = sc;
  }
  return _ok_token_response(resp2);
}

// --------------------------------------------------
//  Package metadata
// --------------------------------------------------

/// Package version marker. Params: none. Returns: "0.1.0".
/// Error case: none. Complexity: O(1).
pub fn oauth_version() -> Str {
  return "0.1.0";
}
