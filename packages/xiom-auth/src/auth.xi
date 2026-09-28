// XIOM -- xiom.auth: HTTP authentication header codecs (RFC 7235 / 7617 /
// 7616 / 6750)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no network, no crypto) STRUCTURE codec for the HTTP
// authentication header fields. It parses and builds the wire grammar of
// "Authorization", "Proxy-Authorization", "WWW-Authenticate" and
// "Proxy-Authenticate" field values; it never computes a hash, never signs,
// never contacts a server and never decides whether a credential is correct.
//
// Covered surface:
//   * Generic grammar (RFC 7235 section 2.1 / RFC 7230 section 3.2.6):
//     credentials = auth-scheme [ 1*OWS ( token68 / #auth-param ) ];
//     auth-param = token BWS "=" BWS ( token / quoted-string ); quoted-string
//     escapes ("\" QUOTED-PAIR) are decoded, unknown schemes (Negotiate,
//     AWS4-HMAC-SHA256, ...) are preserved through the same generic accessors.
//     Byte offsets are exposed for every scheme, parameter, value span and
//     for the consumed region, so the raw text can always be recovered.
//   * WWW-Authenticate challenge lists: a comma separates challenges when,
//     after optional whitespace, a token is followed by one or more spaces
//     and then a token68 or an auth-param list (RFC 7235 section 2.1); commas
//     inside a parameter list (for example ", type=1") stay parameters.
//   * Basic (RFC 7617): base64 encode/decode of "user-id ":" password",
//     first-colon split, CTL and user-id colon rejection, strict variant that
//     also rejects colons in the password, and the charset parameter note
//     (UTF-8 is the only registered value and the default).
//   * Digest (RFC 7616): challenge builder and response parser with realm,
//     nonce, qop (offer list, pick-one), the six registered algorithms
//     (MD5, MD5-sess, SHA-256, SHA-256-sess, SHA-512-256,
//     SHA-512-256-sess), opaque, stale, domain, nc, cnonce, userhash and the
//     username*/realm*/nonce* extended UTF-8 forms, plus structural
//     validation (required fields, nc shape, qop offered, algorithm match).
//   * Bearer (RFC 6750): token68 credentials, realm/scope/error/
//     error_description/error_uri challenge parameters and the three
//     registered error codes.
//
// What this module does NOT do: compute MD5/SHA digests, verify credentials,
// manage sessions, issue or validate tokens, or perform any I/O.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no match, no floats, no
//     Vec[StructType]. Parallel Vec fields carry ordered parameter lists.
//   * Ok(...) / Err(...) are constructed only in the tiny leaf helpers named
//     _ok_* / _err_* (constructing results inside larger functions
//     miscompiles in this compiler).
//   * Every byte read from a Str or Vec[UInt8] is widened once with
//     `(x as Int) & 0xFF` before comparison or arithmetic.
//   * No Str value is compared with `==`; all equality goes through
//     xiom.string.compare.str_compare / str_eq_ignore_case with typed locals.
//   * &mut is used only for Vec pushes (the sanctioned write-through
//     pattern); no &mut Int out-parameters, no truncating-division tricks.

module xiom.auth

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.encoding.base64 as b64;

// --------------------------------------------------
//  Byte constants (Int space, always compared masked)
// --------------------------------------------------

const _AUTH_TAB: Int = 9;
const _AUTH_LF: Int = 10;
const _AUTH_CR: Int = 13;
const _AUTH_SP: Int = 32;
const _AUTH_DQUOTE: Int = 34;
const _AUTH_APOS: Int = 39;
const _AUTH_PLUS: Int = 43;
const _AUTH_COMMA: Int = 44;
const _AUTH_MINUS: Int = 45;
const _AUTH_DOT: Int = 46;
const _AUTH_SLASH: Int = 47;
const _AUTH_COLON: Int = 58;
const _AUTH_EQUALS: Int = 61;
const _AUTH_BSLASH: Int = 92;
const _AUTH_UNDERSCORE: Int = 95;
const _AUTH_TILDE: Int = 126;
const _AUTH_DEL: Int = 127;

// Parameter value kinds recorded in the parallel "kind" vectors.
const _KIND_TOKEN: Int = 0;
const _KIND_QUOTED: Int = 1;
const _KIND_RAW: Int = 2;

// --------------------------------------------------
//  Result constructors (leaf helpers only, see header)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _ok_strs(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

fn _err_strs(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

fn _ok_piece(v: AuthPiece) -> Result[AuthPiece, Str] {
  return Ok(v);
}

fn _err_piece(m: Str) -> Result[AuthPiece, Str] {
  return Err(m);
}

fn _ok_param(v: AuthParamParse) -> Result[AuthParamParse, Str] {
  return Ok(v);
}

fn _err_param(m: Str) -> Result[AuthParamParse, Str] {
  return Err(m);
}

fn _ok_header(v: AuthHeader) -> Result[AuthHeader, Str] {
  return Ok(v);
}

fn _err_header(m: Str) -> Result[AuthHeader, Str] {
  return Err(m);
}

fn _ok_challenges(v: AuthChallenges) -> Result[AuthChallenges, Str] {
  return Ok(v);
}

fn _err_challenges(m: Str) -> Result[AuthChallenges, Str] {
  return Err(m);
}

fn _ok_basic(v: BasicCredentials) -> Result[BasicCredentials, Str] {
  return Ok(v);
}

fn _err_basic(m: Str) -> Result[BasicCredentials, Str] {
  return Err(m);
}

fn _ok_dc(v: DigestChallenge) -> Result[DigestChallenge, Str] {
  return Ok(v);
}

fn _err_dc(m: Str) -> Result[DigestChallenge, Str] {
  return Err(m);
}

fn _ok_dr(v: DigestResponse) -> Result[DigestResponse, Str] {
  return Ok(v);
}

fn _err_dr(m: Str) -> Result[DigestResponse, Str] {
  return Err(m);
}

fn _ok_bc(v: BearerChallenge) -> Result[BearerChallenge, Str] {
  return Ok(v);
}

fn _err_bc(m: Str) -> Result[BearerChallenge, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// A parsed Authorization-style header value: one scheme plus either a
/// token68 or an ordered auth-param list. The parallel parameter vectors are
/// always the same length; vector index i is one auth-param.
pub type AuthHeader = {
  // Scheme as written on the wire (token characters only).
  scheme: Str;
  // Byte offset of the scheme token in the source value.
  scheme_off: Int;
  // Byte range of the parsed header: start is the scheme offset after
  // leading whitespace, end is one past the last consumed byte.
  start: Int;
  end: Int;
  // 1 when the credentials are a token68; 0 for an auth-param list.
  uses_token68: Int;
  // The token68 text ("" when the credentials are auth-params).
  token68: Str;
  // Byte offset of the token68 (-1 when not a token68).
  token68_off: Int;
  // Byte range of the credentials part: token68 or the parameter list,
  // excluding the scheme and the whitespace between them (-1 when absent).
  cred_off: Int;
  cred_end: Int;
  pname: Vec[Str];
  pvalue: Vec[Str];
  // Value kind: 0 token, 1 quoted-string, 2 relaxed raw run.
  pkind: Vec[Int];
  // Byte offset of the parameter name.
  poff: Vec[Int];
  // Byte range of the value as written (quotes included for quoted-string).
  pvstart: Vec[Int];
  pvend: Vec[Int];
}

/// A parsed WWW-Authenticate challenge list. Challenge i owns the flattened
/// parameter slots [pbase[i], pbase[i] + pcount[i]); every parallel vector is
/// the same length as `scheme`.
pub type AuthChallenges = {
  scheme: Vec[Str];
  start: Vec[Int];
  end: Vec[Int];
  uses_token68: Vec[Int];
  token68: Vec[Str];
  pbase: Vec[Int];
  pcount: Vec[Int];
  pname: Vec[Str];
  pvalue: Vec[Str];
  pkind: Vec[Int];
  poff: Vec[Int];
  pvstart: Vec[Int];
  pvend: Vec[Int];
}

/// Decoded Basic credentials (RFC 7617).
pub type BasicCredentials = {
  user: Str;
  password: Str;
}

/// Digest challenge parameters (RFC 7616). "" means the parameter is absent;
/// algorithm holds the canonical registered spelling when present.
pub type DigestChallenge = {
  realm: Str;
  nonce: Str;
  algorithm: Str;
  qop: Vec[Str];
  opaque: Str;
  // 1 when stale=true was present.
  stale: Int;
  domain: Vec[Str];
  // 1 when userhash=true was present.
  userhash: Int;
  // "UTF-8" when charset=UTF-8 was present, else "".
  charset: Str;
}

/// Digest response parameters (RFC 7616). The username/realm/nonce extended
/// forms (username*/realm*/nonce*) are stored raw and flagged with the
/// matching *_star field; use auth_digest_ext_decode to decode them.
pub type DigestResponse = {
  username: Str;
  username_star: Int;
  realm: Str;
  realm_star: Int;
  nonce: Str;
  nonce_star: Int;
  uri: Str;
  response: Str;
  algorithm: Str;
  qop: Str;
  nc: Str;
  cnonce: Str;
  opaque: Str;
  userhash: Int;
}

/// Bearer challenge parameters (RFC 6750).
pub type BearerChallenge = {
  realm: Str;
  scope: Vec[Str];
  error: Str;
  // 1 when the error parameter was present.
  error_present: Int;
  error_description: Str;
  error_uri: Str;
}

// Internal: a decoded quoted-string and the offset just past its closing
// quote.
type AuthPiece = {
  text: Str;
  end: Int;
}

// Internal: one parsed auth-param plus its spans.
type AuthParamParse = {
  name: Str;
  value: Str;
  kind: Int;
  name_off: Int;
  value_start: Int;
  value_end: Int;
  end: Int;
}

// --------------------------------------------------
//  Byte and character helpers
// --------------------------------------------------

// Byte of a Str at pos, widened to 0..255. Callers guarantee the bounds.
fn _byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// Byte of a Vec[UInt8] at pos, widened to 0..255.
fn _vbyte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

fn _is_digit(c: Int) -> Bool {
  if c >= 48 && c <= 57 {
    return true;
  }
  return false;
}

fn _is_alpha(c: Int) -> Bool {
  if c >= 65 && c <= 90 {
    return true;
  }
  if c >= 97 && c <= 122 {
    return true;
  }
  return false;
}

fn _is_hex(c: Int) -> Bool {
  if _is_digit(c) {
    return true;
  }
  if c >= 65 && c <= 70 {
    return true;
  }
  if c >= 97 && c <= 102 {
    return true;
  }
  return false;
}

fn _hex_val(c: Int) -> Int {
  if c >= 48 && c <= 57 {
    return c - 48;
  }
  if c >= 65 && c <= 70 {
    return c - 55;
  }
  if c >= 97 && c <= 102 {
    return c - 87;
  }
  return -1;
}

// True for SP (0x20).
fn _is_sp(c: Int) -> Bool {
  if c == _AUTH_SP {
    return true;
  }
  return false;
}

// True for optional whitespace: SP / HTAB (RFC 7230 section 3.2.3).
fn _is_ows(c: Int) -> Bool {
  if c == _AUTH_SP || c == _AUTH_TAB {
    return true;
  }
  return false;
}

// True for the RFC 7230 tchar set: "!" / "#" / "$" / "%" / "&" / "'" / "*" /
// "+" / "-" / "." / "^" / "_" / "`" / "|" / "~" / DIGIT / ALPHA.
fn _is_token_char(c: Int) -> Bool {
  if _is_alpha(c) {
    return true;
  }
  if _is_digit(c) {
    return true;
  }
  if c == 33 || c == 35 || c == 36 || c == 37 || c == 38 {
    return true;
  }
  if c == 39 || c == 42 || c == 43 || c == 45 || c == 46 {
    return true;
  }
  if c == 94 || c == 95 || c == 96 || c == 124 || c == 126 {
    return true;
  }
  return false;
}

// True for the RFC 7235 token68 alphabet: ALPHA / DIGIT / "-" / "." / "_" /
// "~" / "+" / "/" (the trailing "=" padding is handled by the readers).
fn _is_token68_char(c: Int) -> Bool {
  if _is_alpha(c) {
    return true;
  }
  if _is_digit(c) {
    return true;
  }
  if c == _AUTH_MINUS || c == _AUTH_DOT || c == _AUTH_UNDERSCORE {
    return true;
  }
  if c == _AUTH_TILDE || c == _AUTH_PLUS || c == _AUTH_SLASH {
    return true;
  }
  return false;
}

// True for qdtext (RFC 7230 section 3.2.6): HTAB / SP / %x21 / %x23-5B /
// %x5D-7E / obs-text (0x80-0xFF). The delimiter '"' and the escape byte '\'
// never reach this predicate.
fn _is_qdtext(c: Int) -> Bool {
  if c == _AUTH_TAB {
    return true;
  }
  if c == _AUTH_SP || c == 33 {
    return true;
  }
  if c >= 35 && c <= 91 {
    return true;
  }
  if c >= 93 && c <= 126 {
    return true;
  }
  if c >= 128 {
    return true;
  }
  return false;
}

// True for a CTL byte (RFC 5234): 0x00-0x1F and 0x7F.
fn _is_ctl(c: Int) -> Bool {
  if c < 32 {
    return true;
  }
  if c == _AUTH_DEL {
    return true;
  }
  return false;
}

// True when every byte of s is a token character; false for "".
fn _is_token(s: Str) -> Bool {
  if s.len() == 0 {
    return false;
  }
  var i = 0;
  while i < s.len() {
    if !_is_token_char(_byte(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when s contains SP (0x20).
fn _has_space(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == _AUTH_SP {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when every byte of s is a hex digit; false for "".
fn _all_hex(s: Str) -> Bool {
  if s.len() == 0 {
    return false;
  }
  var i = 0;
  while i < s.len() {
    if !_is_hex(_byte(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// First index >= from of byte b in s, or -1.
fn _find_byte(s: Str, b: Int, from: Int) -> Int {
  var i = from;
  while i < s.len() {
    if _byte(s, i) == b {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Decimal text of v for error messages (sign/digits only; never 0x00).
fn _int_str(v: Int) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_int(&mut out, v);
  return builder.sb_to_str(&out);
}

// "<what> at offset <off>": the offset-bearing error convention. The offset
// is a byte offset into the string the helper was called with (the header
// value, or a decoded field, as documented per function).
fn _perr(what: Str, off: Int) -> Str {
  return "auth: " + what + " at offset " + _int_str(off);
}

// Str built from data[a, b); callers guarantee the bounds and that the bytes
// are NUL-free (sb_to_str must never see 0x00).
fn _bytes_to_str_range(data: &Vec[UInt8], a: Int, b: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = a;
  while i < b {
    builder.sb_push_byte(&mut out, data[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Token, token68 and quoted-string readers
// --------------------------------------------------

// End offset of the token starting at pos (pos itself when no token char).
fn _read_token_end(s: Str, pos: Int) -> Int {
  var i = pos;
  while i < s.len() && _is_token_char(_byte(s, i)) {
    i = i + 1;
  }
  return i;
}

// Read a quoted-string whose opening '"' is at pos. Decodes quoted-pair
// escapes ("\X", where X is not CR/LF/NUL). The returned AuthPiece carries
// the decoded text and the offset just past the closing quote.
// Error case: Err for an unterminated string, a truncated quoted-pair, an
// invalid escape byte, or a byte outside qdtext (including raw CR/LF).
fn _read_quoted(value: Str, pos: Int) -> Result[AuthPiece, Str] {
  let n = value.len();
  var p = pos + 1;
  var out = Vec[UInt8].new();
  while p < n {
    let c = _byte(value, p);
    if c == _AUTH_DQUOTE {
      return _ok_piece(AuthPiece{ text: builder.sb_to_str(&out), end: p + 1 });
    }
    if c == _AUTH_BSLASH {
      if p + 1 >= n {
        return _err_piece(_perr("truncated quoted-pair", p));
      }
      let e = _byte(value, p + 1);
      if e == 0 || e == _AUTH_CR || e == _AUTH_LF {
        return _err_piece(_perr("invalid quoted-pair escape", p));
      }
      out.push(string.byte_at(value, p + 1));
      p = p + 2;
    } elif _is_qdtext(c) {
      out.push(string.byte_at(value, p));
      p = p + 1;
    } else {
      return _err_piece(_perr("invalid character in quoted-string", p));
    }
  }
  return _err_piece(_perr("unterminated quoted-string", pos));
}

// --------------------------------------------------
//  auth-param parsing
// --------------------------------------------------

// Parse one auth-param at pos: token BWS "=" BWS ( token / quoted-string ).
// A value that begins as a token but continues with bytes outside the token
// set (for example the AWS4-HMAC-SHA256 "Credential=AKID/20130524/..." form)
// is captured as a relaxed raw run up to the next comma or whitespace and
// reported with kind 2; well-formed token values report kind 0.
// Error case: Err("auth: expected parameter name at offset N"), Err("auth:
// expected '=' after parameter name at offset N"), Err("auth: expected
// parameter value at offset N"), and the _read_quoted catalog.
fn _parse_param(value: Str, pos: Int) -> Result[AuthParamParse, Str] {
  let n = value.len();
  var p = pos;
  if p >= n || !_is_token_char(_byte(value, p)) {
    return _err_param(_perr("expected parameter name", p));
  }
  let name_off = p;
  p = _read_token_end(value, p);
  let name = string.str_slice(value, name_off, p);
  while p < n && _is_ows(_byte(value, p)) {
    p = p + 1;
  }
  if p >= n || _byte(value, p) != _AUTH_EQUALS {
    return _err_param(_perr("expected '=' after parameter name", p));
  }
  p = p + 1;
  while p < n && _is_ows(_byte(value, p)) {
    p = p + 1;
  }
  if p >= n {
    return _err_param(_perr("expected parameter value", p));
  }
  if _byte(value, p) == _AUTH_DQUOTE {
    let qr = _read_quoted(value, p);
    if !qr.is_ok {
      return _err_param(qr.error);
    }
    let qp: AuthPiece = qr.value;
    return _ok_param(AuthParamParse{ name: name, value: qp.text, kind: _KIND_QUOTED,
      name_off: name_off, value_start: p, value_end: qp.end, end: qp.end });
  }
  let vstart = p;
  var vdone = false;
  while p < n && !vdone {
    let c = _byte(value, p);
    if c == _AUTH_COMMA || _is_ows(c) {
      vdone = true;
    } else {
      p = p + 1;
    }
  }
  if p == vstart {
    return _err_param(_perr("expected parameter value", p));
  }
  let raw = string.str_slice(value, vstart, p);
  var all_token = true;
  var q = 0;
  while q < raw.len() {
    if !_is_token_char(_byte(raw, q)) {
      all_token = false;
    }
    q = q + 1;
  }
  var kind = _KIND_TOKEN;
  if !all_token {
    kind = _KIND_RAW;
  }
  return _ok_param(AuthParamParse{ name: name, value: raw, kind: kind,
    name_off: name_off, value_start: vstart, value_end: p, end: p });
}

// True when, at a comma inside an auth-param list, the material after the
// comma starts a new challenge. RFC 7235 section 2.1 boundary rule: after
// optional whitespace a token followed by one or more spaces, then either a
// token68 or an auth-param list. A '=' directly after the spaces means the
// comma separates parameters of the current challenge ("name = value"), and
// a token without a following space is a parameter name.
fn _challenge_starts_at(value: Str, pos: Int) -> Bool {
  let n = value.len();
  var p = pos;
  while p < n && _is_ows(_byte(value, p)) {
    p = p + 1;
  }
  if p >= n {
    return false;
  }
  if !_is_token_char(_byte(value, p)) {
    return false;
  }
  p = _read_token_end(value, p);
  if p >= n {
    return false;
  }
  if !_is_sp(_byte(value, p)) {
    return false;
  }
  while p < n && _is_sp(_byte(value, p)) {
    p = p + 1;
  }
  if p >= n {
    return true;
  }
  let c = _byte(value, p);
  if c == _AUTH_EQUALS {
    return false;
  }
  if _is_token68_char(c) || _is_token_char(c) {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Core parser
// --------------------------------------------------

// Parse one scheme + credentials item starting at off. Leading OWS is
// skipped; the returned header records the scheme offset as start and the
// byte just past the consumed region as end (consumed = end - start). The
// header may be scheme-only; the caller decides whether trailing material is
// acceptable.
fn _parse_one(value: Str, off: Int) -> Result[AuthHeader, Str] {
  let n = value.len();
  if off < 0 || off > n {
    return _err_header(_perr("start offset out of range", off));
  }
  var pos = off;
  while pos < n && _is_ows(_byte(value, pos)) {
    pos = pos + 1;
  }
  if pos >= n {
    return _err_header(_perr("expected auth-scheme", pos));
  }
  if !_is_token_char(_byte(value, pos)) {
    return _err_header(_perr("expected auth-scheme", pos));
  }
  let scheme_off = pos;
  pos = _read_token_end(value, pos);
  let scheme = string.str_slice(value, scheme_off, pos);
  var uses68 = 0;
  var tok68 = "";
  var tok68_off = -1;
  var cred_off = -1;
  var cred_end = -1;
  var h_end = pos;
  var pname = Vec[Str].new();
  var pvalue = Vec[Str].new();
  var pkind = Vec[Int].new();
  var poff = Vec[Int].new();
  var pvstart = Vec[Int].new();
  var pvend = Vec[Int].new();
  var has_ws = false;
  if pos < n && _is_ows(_byte(value, pos)) {
    has_ws = true;
  }
  if has_ws {
    while pos < n && _is_ows(_byte(value, pos)) {
      pos = pos + 1;
    }
    if pos < n {
      cred_off = pos;
      cred_end = pos;
      h_end = pos;
      let c0 = _byte(value, pos);
      if _is_token68_char(c0) {
        var i = pos;
        while i < n && _is_token68_char(_byte(value, i)) {
          i = i + 1;
        }
        var j = i;
        while j < n && _byte(value, j) == _AUTH_EQUALS {
          j = j + 1;
        }
        if j > i {
          if j == n || _byte(value, j) == _AUTH_COMMA || _is_ows(_byte(value, j)) {
            uses68 = 1;
            tok68 = string.str_slice(value, pos, j);
            tok68_off = pos;
            cred_end = j;
            h_end = j;
          }
        } else {
          if i == n || _byte(value, i) == _AUTH_COMMA || _is_ows(_byte(value, i)) {
            var k = i;
            while k < n && _is_ows(_byte(value, k)) {
              k = k + 1;
            }
            if !(k < n && _byte(value, k) == _AUTH_EQUALS) {
              uses68 = 1;
              tok68 = string.str_slice(value, pos, i);
              tok68_off = pos;
              cred_end = i;
              h_end = i;
            }
          }
        }
      }
      if uses68 == 0 {
        var done = false;
        while !done {
          if pos >= n {
            return _err_header(_perr("expected parameter name", pos));
          }
          let pr = _parse_param(value, pos);
          if !pr.is_ok {
            return _err_header(pr.error);
          }
          let pp: AuthParamParse = pr.value;
          let nm: Str = pp.name;
          let vl: Str = pp.value;
          let kd: Int = pp.kind;
          let of: Int = pp.name_off;
          let vs: Int = pp.value_start;
          let ve: Int = pp.value_end;
          pname.push(nm);
          pvalue.push(vl);
          pkind.push(kd);
          poff.push(of);
          pvstart.push(vs);
          pvend.push(ve);
          pos = pp.end;
          while pos < n && _is_ows(_byte(value, pos)) {
            pos = pos + 1;
          }
          if pos >= n {
            done = true;
          } elif _byte(value, pos) == _AUTH_COMMA {
            if _challenge_starts_at(value, pos + 1) {
              done = true;
            } else {
              pos = pos + 1;
              while pos < n && _is_ows(_byte(value, pos)) {
                pos = pos + 1;
              }
            }
          } else {
            return _err_header(_perr("expected ',' between parameters", pos));
          }
        }
        cred_end = pos;
        h_end = pos;
      }
    }
  }
  return _ok_header(AuthHeader{
    scheme: scheme,
    scheme_off: scheme_off,
    start: scheme_off,
    end: h_end,
    uses_token68: uses68,
    token68: tok68,
    token68_off: tok68_off,
    cred_off: cred_off,
    cred_end: cred_end,
    pname: pname,
    pvalue: pvalue,
    pkind: pkind,
    poff: poff,
    pvstart: pvstart,
    pvend: pvend
  });
}

/// Parse one Authorization-style header value: exactly one scheme with
/// either a token68 or an auth-param list, consuming the whole value.
/// Params: value - the field value (leading/trailing OWS allowed).
/// Returns: Ok(header) with byte spans; auth_header_consumed(header) equals
/// end - start.
/// Error case: the _parse_one catalog plus Err("auth: unexpected trailing
/// characters at offset N") when material remains after the credentials.
/// Complexity: O(value.len()).
pub fn auth_parse_authorization(value: Str) -> Result[AuthHeader, Str] {
  let n = value.len();
  let r = _parse_one(value, 0);
  if !r.is_ok {
    return _err_header(r.error);
  }
  let h: AuthHeader = r.value;
  var pos = h.end;
  while pos < n && _is_ows(_byte(value, pos)) {
    pos = pos + 1;
  }
  if pos != n {
    return _err_header(_perr("unexpected trailing characters", pos));
  }
  return _ok_header(h);
}

/// Parse one scheme + credentials item starting at off without requiring the
/// rest of the value to be consumed. This is the parse-one primitive behind
/// challenge lists; `off` may point into the middle of a larger value.
/// Params: value - the field value; off - the byte offset to start at.
/// Returns: Ok(header) whose start/end are absolute offsets into value and
/// whose consumed count is end - start.
/// Error case: the _parse_one catalog; Err("auth: start offset out of range
/// at offset N") when off < 0 or off > value.len().
/// Complexity: O(value.len() - off).
pub fn auth_parse_header_at(value: Str, off: Int) -> Result[AuthHeader, Str] {
  return _parse_one(value, off);
}

// Append challenge h to the flattened list l (parallel pushes in lockstep).
fn _push_challenge(l: &mut AuthChallenges, h: &AuthHeader) {
  let sc: Str = h.scheme;
  let st: Int = h.start;
  let en: Int = h.end;
  let t68: Str = h.token68;
  let use68: Int = h.uses_token68;
  let base: Int = l.pname.len();
  l.scheme.push(sc);
  l.start.push(st);
  l.end.push(en);
  l.token68.push(t68);
  l.uses_token68.push(use68);
  l.pbase.push(base);
  l.pcount.push(h.pname.len());
  var i = 0;
  while i < h.pname.len() {
    let nm: Str = h.pname[i];
    let vl: Str = h.pvalue[i];
    let kd: Int = h.pkind[i];
    let of: Int = h.poff[i];
    let vs: Int = h.pvstart[i];
    let ve: Int = h.pvend[i];
    l.pname.push(nm);
    l.pvalue.push(vl);
    l.pkind.push(kd);
    l.poff.push(of);
    l.pvstart.push(vs);
    l.pvend.push(ve);
    i = i + 1;
  }
}

/// Parse a WWW-Authenticate (or Proxy-Authenticate) challenge list.
/// Params: value - the field value.
/// Returns: Ok(challenges) with one entry per comma-separated challenge;
/// challenge boundaries follow RFC 7235 section 2.1 (see
/// _challenge_starts_at). Empty input is an error (the grammar is
/// 1#challenge). Duplicate schemes are preserved in wire order.
/// Error case: the _parse_one catalog plus Err("auth: expected ',' between
/// challenges at offset N") and Err("auth: expected challenge after ',' at
/// offset N") for malformed separators.
/// Complexity: O(value.len()).
pub fn auth_parse_www_authenticate(value: Str) -> Result[AuthChallenges, Str] {
  let n = value.len();
  var l = AuthChallenges{
    scheme: Vec[Str].new(),
    start: Vec[Int].new(),
    end: Vec[Int].new(),
    uses_token68: Vec[Int].new(),
    token68: Vec[Str].new(),
    pbase: Vec[Int].new(),
    pcount: Vec[Int].new(),
    pname: Vec[Str].new(),
    pvalue: Vec[Str].new(),
    pkind: Vec[Int].new(),
    poff: Vec[Int].new(),
    pvstart: Vec[Int].new(),
    pvend: Vec[Int].new()
  };
  var pos = 0;
  while pos < n && _is_ows(_byte(value, pos)) {
    pos = pos + 1;
  }
  if pos >= n {
    return _err_challenges(_perr("expected challenge", pos));
  }
  var done = false;
  while !done {
    let pr = _parse_one(value, pos);
    if !pr.is_ok {
      return _err_challenges(pr.error);
    }
    let h: AuthHeader = pr.value;
    _push_challenge(&mut l, &h);
    pos = h.end;
    while pos < n && _is_ows(_byte(value, pos)) {
      pos = pos + 1;
    }
    if pos >= n {
      done = true;
    } elif _byte(value, pos) == _AUTH_COMMA {
      pos = pos + 1;
      while pos < n && _is_ows(_byte(value, pos)) {
        pos = pos + 1;
      }
      if pos >= n {
        return _err_challenges(_perr("expected challenge after ','", pos));
      }
    } else {
      return _err_challenges(_perr("expected ',' between challenges", pos));
    }
  }
  return _ok_challenges(l);
}

// --------------------------------------------------
//  AuthHeader accessors
// --------------------------------------------------

/// Scheme of the parsed header as written on the wire.
/// Params: h - a parsed header. Returns: the scheme token.
/// Error case: none. Complexity: O(1).
pub fn auth_header_scheme(h: &AuthHeader) -> Str {
  let v: Str = h.scheme;
  return v;
}

/// Byte offset of the scheme token.
/// Params: h - a parsed header. Returns: the offset.
/// Error case: none. Complexity: O(1).
pub fn auth_header_scheme_offset(h: &AuthHeader) -> Int {
  let v: Int = h.scheme_off;
  return v;
}

/// Start offset of the parsed header (first scheme byte).
/// Params: h - a parsed header. Returns: the offset.
/// Error case: none. Complexity: O(1).
pub fn auth_header_start(h: &AuthHeader) -> Int {
  let v: Int = h.start;
  return v;
}

/// End offset of the parsed header (one past the last consumed byte).
/// Params: h - a parsed header. Returns: the offset.
/// Error case: none. Complexity: O(1).
pub fn auth_header_end(h: &AuthHeader) -> Int {
  let v: Int = h.end;
  return v;
}

/// Number of bytes the header consumed: end - start.
/// Params: h - a parsed header. Returns: the consumed count.
/// Error case: none. Complexity: O(1).
pub fn auth_header_consumed(h: &AuthHeader) -> Int {
  return h.end - h.start;
}

/// True when the credentials are a token68 (no auth-params).
/// Params: h - a parsed header. Returns: the predicate.
/// Error case: none. Complexity: O(1).
pub fn auth_header_uses_token68(h: &AuthHeader) -> Bool {
  if h.uses_token68 == 1 {
    return true;
  }
  return false;
}

/// The token68 credentials ("" when the header uses auth-params).
/// Params: h - a parsed header. Returns: the token68 text.
/// Error case: none. Complexity: O(1).
pub fn auth_header_token68(h: &AuthHeader) -> Str {
  let v: Str = h.token68;
  return v;
}

/// Byte offset of the token68 (-1 when the header uses auth-params).
/// Params: h - a parsed header. Returns: the offset.
/// Error case: none. Complexity: O(1).
pub fn auth_header_token68_offset(h: &AuthHeader) -> Int {
  let v: Int = h.token68_off;
  return v;
}

/// Byte offset where the credentials part starts (-1 when scheme-only).
/// Params: h - a parsed header. Returns: the offset.
/// Error case: none. Complexity: O(1).
pub fn auth_header_cred_offset(h: &AuthHeader) -> Int {
  let v: Int = h.cred_off;
  return v;
}

/// Byte offset just past the credentials part (-1 when scheme-only).
/// Params: h - a parsed header. Returns: the offset.
/// Error case: none. Complexity: O(1).
pub fn auth_header_cred_end(h: &AuthHeader) -> Int {
  let v: Int = h.cred_end;
  return v;
}

/// Number of auth-params.
/// Params: h - a parsed header. Returns: the count.
/// Error case: none. Complexity: O(1).
pub fn auth_header_param_count(h: &AuthHeader) -> Int {
  return h.pname.len();
}

/// Name of parameter i (wire case preserved).
/// Params: h - a parsed header; i - a valid parameter index.
/// Returns: the name. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_header_param_name(h: &AuthHeader, i: Int) -> Str {
  let v: Str = h.pname[i];
  return v;
}

/// Decoded value of parameter i (quoted-string escapes applied).
/// Params: h - a parsed header; i - a valid parameter index.
/// Returns: the value. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_header_param_value(h: &AuthHeader, i: Int) -> Str {
  let v: Str = h.pvalue[i];
  return v;
}

/// Value kind of parameter i: 0 token, 1 quoted-string, 2 relaxed raw.
/// Params: h - a parsed header; i - a valid parameter index.
/// Returns: the kind. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_header_param_kind(h: &AuthHeader, i: Int) -> Int {
  let v: Int = h.pkind[i];
  return v;
}

/// True when parameter i was written as a quoted-string.
/// Params: h - a parsed header; i - a valid parameter index.
/// Returns: the predicate. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_header_param_is_quoted(h: &AuthHeader, i: Int) -> Bool {
  let v: Int = h.pkind[i];
  if v == _KIND_QUOTED {
    return true;
  }
  return false;
}

/// Byte offset of the name of parameter i.
/// Params: h - a parsed header; i - a valid parameter index.
/// Returns: the offset. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_header_param_offset(h: &AuthHeader, i: Int) -> Int {
  let v: Int = h.poff[i];
  return v;
}

/// Byte offset of the first byte of the value of parameter i (the opening
/// quote for quoted-strings).
/// Params: h - a parsed header; i - a valid parameter index.
/// Returns: the offset. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_header_param_value_start(h: &AuthHeader, i: Int) -> Int {
  let v: Int = h.pvstart[i];
  return v;
}

/// Byte offset just past the last byte of the value of parameter i (past
/// the closing quote for quoted-strings).
/// Params: h - a parsed header; i - a valid parameter index.
/// Returns: the offset. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_header_param_value_end(h: &AuthHeader, i: Int) -> Int {
  let v: Int = h.pvend[i];
  return v;
}

/// Case-insensitive lookup of the first parameter named `name`.
/// Params: h - a parsed header; name - the parameter name.
/// Returns: the parameter index, or -1 when absent.
/// Error case: none. Complexity: O(param count).
pub fn auth_header_param_index(h: &AuthHeader, name: Str) -> Int {
  var i = 0;
  while i < h.pname.len() {
    let cur: Str = h.pname[i];
    if compare.str_eq_ignore_case(cur, name) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// True when a parameter named `name` exists (case-insensitive).
/// Params: h - a parsed header; name - the parameter name.
/// Returns: the predicate. Error case: none. Complexity: O(param count).
pub fn auth_header_param_has(h: &AuthHeader, name: Str) -> Bool {
  if auth_header_param_index(h, name) >= 0 {
    return true;
  }
  return false;
}

/// First decoded value named `name` (case-insensitive lookup).
/// Params: h - a parsed header; name - the parameter name.
/// Returns: Ok(value) for the first match.
/// Error case: Err("auth: parameter not found: <name>") when absent.
/// Complexity: O(param count).
pub fn auth_header_param_get(h: &AuthHeader, name: Str) -> Result[Str, Str] {
  let idx = auth_header_param_index(h, name);
  if idx < 0 {
    return _err_str("auth: parameter not found: " + name);
  }
  let v: Str = h.pvalue[idx];
  return _ok_str(v);
}

/// Since: the raw text of the parsed header.
/// Params: value - the source field value the header was parsed from;
/// h - a header parsed from value.
/// Returns: value[start, end).
/// Error case: none for a header parsed from value.
/// Complexity: O(header length).
pub fn auth_header_slice(value: Str, h: &AuthHeader) -> Str {
  let a: Int = h.start;
  let b: Int = h.end;
  return string.str_slice(value, a, b);
}

/// The raw credentials text (token68 or parameter list), or "" when the
/// header is scheme-only.
/// Params: value - the source field value; h - a header parsed from value.
/// Returns: value[cred_off, cred_end) or "".
/// Error case: none for a header parsed from value.
/// Complexity: O(credentials length).
pub fn auth_header_cred_slice(value: Str, h: &AuthHeader) -> Str {
  if h.cred_off < 0 {
    return "";
  }
  let a: Int = h.cred_off;
  let b: Int = h.cred_end;
  return string.str_slice(value, a, b);
}

/// True when the header scheme equals `name` (case-insensitive, tokens are
/// case-insensitive per RFC 7235 section 2.1).
/// Params: h - a parsed header; name - the scheme to compare.
/// Returns: the predicate. Error case: none. Complexity: O(name.len()).
pub fn auth_scheme_is(h: &AuthHeader, name: Str) -> Bool {
  let s: Str = h.scheme;
  return compare.str_eq_ignore_case(s, name);
}

// --------------------------------------------------
//  AuthChallenges accessors
// --------------------------------------------------

/// Number of challenges.
/// Params: l - a parsed challenge list. Returns: the count.
/// Error case: none. Complexity: O(1).
pub fn auth_challenge_count(l: &AuthChallenges) -> Int {
  return l.scheme.len();
}

/// Scheme of challenge i.
/// Params: l - a parsed list; i - a valid challenge index.
/// Returns: the scheme. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_challenge_scheme(l: &AuthChallenges, i: Int) -> Str {
  let v: Str = l.scheme[i];
  return v;
}

/// Start offset of challenge i.
/// Params: l - a parsed list; i - a valid challenge index.
/// Returns: the offset. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_challenge_start(l: &AuthChallenges, i: Int) -> Int {
  let v: Int = l.start[i];
  return v;
}

/// End offset of challenge i (one past its last consumed byte).
/// Params: l - a parsed list; i - a valid challenge index.
/// Returns: the offset. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_challenge_end(l: &AuthChallenges, i: Int) -> Int {
  let v: Int = l.end[i];
  return v;
}

/// Bytes consumed by challenge i: end - start.
/// Params: l - a parsed list; i - a valid challenge index.
/// Returns: the consumed count. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_challenge_consumed(l: &AuthChallenges, i: Int) -> Int {
  let a: Int = l.start[i];
  let b: Int = l.end[i];
  return b - a;
}

/// True when challenge i carries token68 credentials.
/// Params: l - a parsed list; i - a valid challenge index.
/// Returns: the predicate. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_challenge_uses_token68(l: &AuthChallenges, i: Int) -> Bool {
  let v: Int = l.uses_token68[i];
  if v == 1 {
    return true;
  }
  return false;
}

/// Token68 of challenge i ("" when it uses auth-params).
/// Params: l - a parsed list; i - a valid challenge index.
/// Returns: the token68. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_challenge_token68(l: &AuthChallenges, i: Int) -> Str {
  let v: Str = l.token68[i];
  return v;
}

/// Number of parameters of challenge i.
/// Params: l - a parsed list; i - a valid challenge index.
/// Returns: the count. Error case: none for a valid index.
/// Complexity: O(1).
pub fn auth_challenge_param_count(l: &AuthChallenges, i: Int) -> Int {
  let v: Int = l.pcount[i];
  return v;
}

/// Name of parameter j of challenge i.
/// Params: l - a parsed list; i - a valid challenge index; j - a valid
/// parameter index within challenge i.
/// Returns: the name. Error case: none for valid indices.
/// Complexity: O(1).
pub fn auth_challenge_param_name(l: &AuthChallenges, i: Int, j: Int) -> Str {
  let base: Int = l.pbase[i];
  let v: Str = l.pname[base + j];
  return v;
}

/// Decoded value of parameter j of challenge i.
/// Params: l - a parsed list; i - a valid challenge index; j - a valid
/// parameter index within challenge i.
/// Returns: the value. Error case: none for valid indices.
/// Complexity: O(1).
pub fn auth_challenge_param_value(l: &AuthChallenges, i: Int, j: Int) -> Str {
  let base: Int = l.pbase[i];
  let v: Str = l.pvalue[base + j];
  return v;
}

/// Value kind of parameter j of challenge i (0 token, 1 quoted, 2 raw).
/// Params: l - a parsed list; i - a valid challenge index; j - a valid
/// parameter index within challenge i.
/// Returns: the kind. Error case: none for valid indices.
/// Complexity: O(1).
pub fn auth_challenge_param_kind(l: &AuthChallenges, i: Int, j: Int) -> Int {
  let base: Int = l.pbase[i];
  let v: Int = l.pkind[base + j];
  return v;
}

/// True when parameter j of challenge i was written as a quoted-string.
/// Params: l - a parsed list; i - a valid challenge index; j - a valid
/// parameter index within challenge i.
/// Returns: the predicate. Error case: none for valid indices.
/// Complexity: O(1).
pub fn auth_challenge_param_is_quoted(l: &AuthChallenges, i: Int, j: Int) -> Bool {
  let base: Int = l.pbase[i];
  let v: Int = l.pkind[base + j];
  if v == _KIND_QUOTED {
    return true;
  }
  return false;
}

/// Byte offset of the name of parameter j of challenge i.
/// Params: l - a parsed list; i - a valid challenge index; j - a valid
/// parameter index within challenge i.
/// Returns: the offset. Error case: none for valid indices.
/// Complexity: O(1).
pub fn auth_challenge_param_offset(l: &AuthChallenges, i: Int, j: Int) -> Int {
  let base: Int = l.pbase[i];
  let v: Int = l.poff[base + j];
  return v;
}

/// Case-insensitive lookup of a parameter of challenge i.
/// Params: l - a parsed list; i - a valid challenge index; name - the
/// parameter name.
/// Returns: the parameter index within challenge i, or -1 when absent.
/// Error case: none. Complexity: O(param count of challenge i).
pub fn auth_challenge_param_index(l: &AuthChallenges, i: Int, name: Str) -> Int {
  let base: Int = l.pbase[i];
  let cnt: Int = l.pcount[i];
  var k = 0;
  while k < cnt {
    let cur: Str = l.pname[base + k];
    if compare.str_eq_ignore_case(cur, name) {
      return k;
    }
    k = k + 1;
  }
  return -1;
}

/// True when challenge i has a parameter named `name` (case-insensitive).
/// Params: l - a parsed list; i - a valid challenge index; name - the name.
/// Returns: the predicate. Error case: none.
/// Complexity: O(param count of challenge i).
pub fn auth_challenge_param_has(l: &AuthChallenges, i: Int, name: Str) -> Bool {
  if auth_challenge_param_index(l, i, name) >= 0 {
    return true;
  }
  return false;
}

/// First decoded parameter value named `name` in challenge i.
/// Params: l - a parsed list; i - a valid challenge index; name - the name.
/// Returns: Ok(value) for the first match.
/// Error case: Err("auth: parameter not found: <name>") when absent.
/// Complexity: O(param count of challenge i).
pub fn auth_challenge_param_get(l: &AuthChallenges, i: Int, name: Str) -> Result[Str, Str] {
  let idx = auth_challenge_param_index(l, i, name);
  if idx < 0 {
    return _err_str("auth: parameter not found: " + name);
  }
  let base: Int = l.pbase[i];
  let v: Str = l.pvalue[base + idx];
  return _ok_str(v);
}

/// Index of the first challenge whose scheme equals `scheme`
/// (case-insensitive), or -1 when none matches.
/// Params: l - a parsed list; scheme - the scheme name.
/// Returns: the challenge index or -1. Error case: none.
/// Complexity: O(challenge count).
pub fn auth_challenge_pick(l: &AuthChallenges, scheme: Str) -> Int {
  var i = 0;
  while i < l.scheme.len() {
    let cur: Str = l.scheme[i];
    if compare.str_eq_ignore_case(cur, scheme) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Raw text of challenge i.
/// Params: value - the source field value; l - a list parsed from value;
/// i - a valid challenge index.
/// Returns: value[start, end). Error case: none for a valid index.
/// Complexity: O(challenge length).
pub fn auth_challenge_slice(value: Str, l: &AuthChallenges, i: Int) -> Str {
  let a: Int = l.start[i];
  let b: Int = l.end[i];
  return string.str_slice(value, a, b);
}

// --------------------------------------------------
//  Basic (RFC 7617)
// --------------------------------------------------

/// Default Basic charset (RFC 7617 section 2.1): "UTF-8".
/// Params: none. Returns: "UTF-8". Error case: none. Complexity: O(1).
pub fn auth_basic_charset_default() -> Str {
  return "UTF-8";
}

// Validate a user-id for encoding: no ':' and no CTL bytes.
fn _basic_user_check(user: Str) -> Result[Str, Str] {
  var i = 0;
  while i < user.len() {
    let c = _byte(user, i);
    if c == _AUTH_COLON {
      return _err_str(_perr("basic user-id contains ':'", i));
    }
    if _is_ctl(c) {
      return _err_str(_perr("basic user-id contains control character", i));
    }
    i = i + 1;
  }
  return _ok_str("");
}

// Validate a password for encoding: no CTL bytes.
fn _basic_password_check(password: Str) -> Result[Str, Str] {
  var i = 0;
  while i < password.len() {
    if _is_ctl(_byte(password, i)) {
      return _err_str(_perr("basic password contains control character", i));
    }
    i = i + 1;
  }
  return _ok_str("");
}

/// True when `user` is encodable in Basic credentials: no ':' and no CTL.
/// Params: user - the user-id. Returns: the predicate.
/// Error case: none. Complexity: O(user.len()).
pub fn auth_basic_user_is_valid(user: Str) -> Bool {
  let r = _basic_user_check(user);
  return r.is_ok;
}

/// True when `password` is encodable in Basic credentials: no CTL bytes
/// (colons are allowed, RFC 7617 puts no restriction on the password).
/// Params: password - the password. Returns: the predicate.
/// Error case: none. Complexity: O(password.len()).
pub fn auth_basic_password_is_valid(password: Str) -> Bool {
  let r = _basic_password_check(password);
  return r.is_ok;
}

/// Encode Basic credentials: "Basic " + base64(user ":" password).
/// Params: user - the user-id (no ':' and no CTL); password - the password
/// (no CTL; colons are allowed and survive the first-colon split).
/// Returns: Ok("Basic <token68>") with standard base64 and '=' padding.
/// Error case: Err("auth: basic user-id contains ':' at offset N") or Err(
/// "auth: basic user-id contains control character at offset N") /
/// "auth: basic password contains control character at offset N" (offsets
/// into the respective argument).
/// Complexity: O(user.len() + password.len()).
pub fn auth_basic_encode(user: Str, password: Str) -> Result[Str, Str] {
  let ur = _basic_user_check(user);
  if !ur.is_ok {
    return _err_str(ur.error);
  }
  let pr = _basic_password_check(password);
  if !pr.is_ok {
    return _err_str(pr.error);
  }
  var raw = Vec[UInt8].new();
  builder.sb_push_str(&mut raw, user);
  raw.push(_AUTH_COLON as UInt8);
  builder.sb_push_str(&mut raw, password);
  let enc = b64.base64_encode(&raw);
  return _ok_str("Basic " + enc);
}

// CTL check for a decoded user-id byte range; offsets are relative to a. The
// first-colon split makes a colon inside this range impossible, so only the
// CTL rule is enforced here.
fn _basic_user_bytes_check(data: &Vec[UInt8], a: Int, b: Int) -> Result[Str, Str] {
  var i = a;
  while i < b {
    let c = _vbyte(data, i);
    if _is_ctl(c) {
      return _err_str(_perr("basic user-id contains control character", i - a));
    }
    i = i + 1;
  }
  return _ok_str("");
}

// CTL check for a decoded password byte range; offsets are relative to a.
fn _basic_password_bytes_check(data: &Vec[UInt8], a: Int, b: Int) -> Result[Str, Str] {
  var i = a;
  while i < b {
    if _is_ctl(_vbyte(data, i)) {
      return _err_str(_perr("basic password contains control character", i - a));
    }
    i = i + 1;
  }
  return _ok_str("");
}

/// Decode the base64 payload of a Basic credential (RFC 7617 section 2).
/// Params: encoded - the token68 payload only (no "Basic " scheme).
/// Returns: Ok(credentials) splitting at the FIRST colon; later colons are
/// part of the password. Bytes are copied verbatim (charset handling is the
/// caller's concern; UTF-8 is the default).
/// Error case: Err("auth: basic invalid base64"), Err("auth: basic
/// credentials missing colon separator"), and CTL errors with offsets into
/// the decoded user-id / password.
/// Complexity: O(encoded.len()).
pub fn auth_basic_decode(encoded: Str) -> Result[BasicCredentials, Str] {
  let dr = b64.base64_decode(encoded);
  if !dr.is_ok {
    return _err_basic("auth: basic invalid base64");
  }
  let raw: Vec[UInt8] = dr.value;
  let n = raw.len();
  var colon = -1;
  var i = 0;
  var found = false;
  while i < n && !found {
    if _vbyte(raw, i) == _AUTH_COLON {
      colon = i;
      found = true;
    } else {
      i = i + 1;
    }
  }
  if colon < 0 {
    return _err_basic("auth: basic credentials missing colon separator");
  }
  let uc = _basic_user_bytes_check(&raw, 0, colon);
  if !uc.is_ok {
    return _err_basic(uc.error);
  }
  let pc = _basic_password_bytes_check(&raw, colon + 1, n);
  if !pc.is_ok {
    return _err_basic(pc.error);
  }
  let user = _bytes_to_str_range(&raw, 0, colon);
  let password = _bytes_to_str_range(&raw, colon + 1, n);
  return _ok_basic(BasicCredentials{ user: user, password: password });
}

/// Strict Basic decode: like auth_basic_decode, but also rejects a password
/// that contains ':' (systems that reserve colons for the separator).
/// Params: encoded - the token68 payload only.
/// Returns: Ok(credentials) when exactly the first colon is present.
/// Error case: the auth_basic_decode catalog plus Err("auth: basic password
/// contains ':' (strict) at offset N") with the offset into the password.
/// Complexity: O(encoded.len()).
pub fn auth_basic_decode_strict(encoded: Str) -> Result[BasicCredentials, Str] {
  let r = auth_basic_decode(encoded);
  if !r.is_ok {
    return _err_basic(r.error);
  }
  let c: BasicCredentials = r.value;
  let pass: Str = c.password;
  var i = 0;
  while i < pass.len() {
    if _byte(pass, i) == _AUTH_COLON {
      return _err_basic(_perr("basic password contains ':' (strict)", i));
    }
    i = i + 1;
  }
  return _ok_basic(c);
}

/// Parse a complete "Basic ..." Authorization header value.
/// Params: value - the full field value.
/// Returns: Ok(credentials) for a token68 Basic credential.
/// Error case: the parser catalog, Err("auth: authorization scheme is not
/// Basic") and Err("auth: Basic credentials must be a token68") (for
/// example "Basic realm=\"x\""), plus the auth_basic_decode catalog.
/// Complexity: O(value.len()).
pub fn auth_basic_parse(value: Str) -> Result[BasicCredentials, Str] {
  let hr = auth_parse_authorization(value);
  if !hr.is_ok {
    return _err_basic(hr.error);
  }
  let h: AuthHeader = hr.value;
  if !auth_scheme_is(&h, "Basic") {
    return _err_basic("auth: authorization scheme is not Basic");
  }
  if h.uses_token68 != 1 {
    return _err_basic("auth: Basic credentials must be a token68");
  }
  let t: Str = h.token68;
  return auth_basic_decode(t);
}

/// Charset of a Basic challenge: the charset parameter value when present,
/// else the default "UTF-8".
/// Params: h - a parsed challenge header. Returns: the charset.
/// Error case: none. Complexity: O(param count).
pub fn auth_basic_charset(h: &AuthHeader) -> Str {
  let r = auth_header_param_get(h, "charset");
  if !r.is_ok {
    return "UTF-8";
  }
  let v: Str = r.value;
  return v;
}

/// True when a Basic challenge's charset is acceptable: absent or
/// case-insensitively "UTF-8" (the only registered value, RFC 7617).
/// Params: h - a parsed challenge header. Returns: the predicate.
/// Error case: none. Complexity: O(param count).
pub fn auth_basic_charset_ok(h: &AuthHeader) -> Bool {
  let v = auth_basic_charset(h);
  return compare.str_eq_ignore_case(v, "UTF-8");
}

// --------------------------------------------------
//  Digest (RFC 7616)
// --------------------------------------------------

/// Default Digest algorithm when the algorithm parameter is absent: "MD5".
/// Params: none. Returns: "MD5". Error case: none. Complexity: O(1).
pub fn auth_digest_algorithm_default() -> Str {
  return "MD5";
}

/// Canonical registered spelling of a Digest algorithm, or "" when the name
/// is not registered. Matching is case-insensitive.
/// Params: name - the algorithm token.
/// Returns: one of MD5, MD5-sess, SHA-256, SHA-256-sess, SHA-512-256,
/// SHA-512-256-sess, or "". Error case: none. Complexity: O(name.len()).
pub fn auth_digest_algorithm_canonical(name: Str) -> Str {
  if compare.str_eq_ignore_case(name, "MD5") {
    return "MD5";
  }
  if compare.str_eq_ignore_case(name, "MD5-sess") {
    return "MD5-sess";
  }
  if compare.str_eq_ignore_case(name, "SHA-256") {
    return "SHA-256";
  }
  if compare.str_eq_ignore_case(name, "SHA-256-sess") {
    return "SHA-256-sess";
  }
  if compare.str_eq_ignore_case(name, "SHA-512-256") {
    return "SHA-512-256";
  }
  if compare.str_eq_ignore_case(name, "SHA-512-256-sess") {
    return "SHA-512-256-sess";
  }
  return "";
}

/// True when `name` is one of the six registered Digest algorithms.
/// Params: name - the algorithm token. Returns: the predicate.
/// Error case: none. Complexity: O(name.len()).
pub fn auth_digest_algorithm_is_valid(name: Str) -> Bool {
  let c = auth_digest_algorithm_canonical(name);
  if c.len() == 0 {
    return false;
  }
  return true;
}

/// True when `name` is one of the three session variants (suffix -sess).
/// Params: name - the algorithm token. Returns: the predicate.
/// Error case: none. Complexity: O(name.len()).
pub fn auth_digest_algorithm_is_sess(name: Str) -> Bool {
  if compare.str_eq_ignore_case(name, "MD5-sess") {
    return true;
  }
  if compare.str_eq_ignore_case(name, "SHA-256-sess") {
    return true;
  }
  if compare.str_eq_ignore_case(name, "SHA-512-256-sess") {
    return true;
  }
  return false;
}

/// Hex length of the response digest for an algorithm: 32 for MD5 /
/// MD5-sess, 64 for SHA-256 / SHA-256-sess / SHA-512-256 /
/// SHA-512-256-sess, 0 for an unknown name.
/// Params: name - the algorithm token. Returns: the length or 0.
/// Error case: none. Complexity: O(name.len()).
pub fn auth_digest_response_hex_len(name: Str) -> Int {
  if compare.str_eq_ignore_case(name, "MD5") {
    return 32;
  }
  if compare.str_eq_ignore_case(name, "MD5-sess") {
    return 32;
  }
  if compare.str_eq_ignore_case(name, "SHA-256") {
    return 64;
  }
  if compare.str_eq_ignore_case(name, "SHA-256-sess") {
    return 64;
  }
  if compare.str_eq_ignore_case(name, "SHA-512-256") {
    return 64;
  }
  if compare.str_eq_ignore_case(name, "SHA-512-256-sess") {
    return 64;
  }
  return 0;
}

/// True when `qop` is a registered quality-of-protection token: "auth" or
/// "auth-int" (RFC 7616 section 3.4).
/// Params: qop - the token. Returns: the predicate.
/// Error case: none. Complexity: O(qop.len()).
pub fn auth_digest_qop_is_valid(qop: Str) -> Bool {
  if compare.str_compare(qop, "auth") == 0 {
    return true;
  }
  if compare.str_compare(qop, "auth-int") == 0 {
    return true;
  }
  return false;
}

// True when q is one non-empty token.
fn _digest_qop_token_valid(q: Str) -> Bool {
  return _is_token(q);
}

/// Split a Digest qop offer list (for example "auth,auth-int") into tokens.
/// Params: value - the qop parameter value (decoded).
/// Returns: Ok(tokens) in wire order; OWS around commas is trimmed.
/// Error case: Err("auth: digest qop list is empty"), Err("auth: digest qop
/// token is empty at offset N") for a leading/trailing/double comma, and Err
/// ("auth: digest qop token has invalid character at offset N") (offsets
/// into value).
/// Complexity: O(value.len()).
pub fn auth_digest_qop_tokens(value: Str) -> Result[Vec[Str], Str] {
  var out = Vec[Str].new();
  let n = value.len();
  if n == 0 {
    return _err_strs("auth: digest qop list is empty");
  }
  var pos = 0;
  var done = false;
  while !done {
    let st = pos;
    while pos < n && _byte(value, pos) != _AUTH_COMMA {
      pos = pos + 1;
    }
    var s = st;
    var e = pos;
    while s < e && _is_ows(_byte(value, s)) {
      s = s + 1;
    }
    while e > s && _is_ows(_byte(value, e - 1)) {
      e = e - 1;
    }
    if s >= e {
      return _err_strs(_perr("digest qop token is empty", st));
    }
    let tok = string.str_slice(value, s, e);
    if !_digest_qop_token_valid(tok) {
      return _err_strs(_perr("digest qop token has invalid character", s));
    }
    out.push(tok);
    if pos >= n {
      done = true;
    } else {
      pos = pos + 1;
      if pos >= n {
        return _err_strs(_perr("digest qop token is empty", pos));
      }
    }
  }
  return _ok_strs(out);
}

/// True when the challenge's qop offer includes `qop` (case-insensitive).
/// Params: c - a parsed challenge; qop - the candidate token.
/// Returns: the predicate (false when the challenge offers no qop).
/// Error case: none. Complexity: O(offer count).
pub fn auth_digest_qop_offered(c: &DigestChallenge, qop: Str) -> Bool {
  var i = 0;
  while i < c.qop.len() {
    let cur: Str = c.qop[i];
    if compare.str_eq_ignore_case(cur, qop) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// Client-side pick-one rule: choose the first token of `preferred` that the
/// server offered (case-insensitive), returning the caller's spelling.
/// Params: c - a parsed challenge; preferred - tokens in preference order.
/// Returns: Ok(token) for the first offered preference.
/// Error case: Err("auth: digest challenge offers no qop") when the
/// challenge has no qop parameter; Err("auth: digest no preferred qop is
/// offered") when none of the preferences is offered.
/// Complexity: O(preferred * offer).
pub fn auth_digest_pick_qop(c: &DigestChallenge, preferred: &Vec[Str]) -> Result[Str, Str] {
  if c.qop.len() == 0 {
    return _err_str("auth: digest challenge offers no qop");
  }
  var i = 0;
  while i < preferred.len() {
    let want: Str = preferred[i];
    if auth_digest_qop_offered(c, want) {
      return _ok_str(want);
    }
    i = i + 1;
  }
  return _err_str("auth: digest no preferred qop is offered");
}

// Split `value` on single spaces into non-empty tokens. Offsets in errors
// are into value.
fn _split_spaces(value: Str, what: Str) -> Result[Vec[Str], Str> {
  var out = Vec[Str].new();
  let n = value.len();
  if n == 0 {
    return _err_strs("auth: " + what + " list is empty");
  }
  var i = 0;
  while i < n {
    let st = i;
    while i < n && _byte(value, i) != _AUTH_SP {
      i = i + 1;
    }
    if i == st {
      return _err_strs(_perr(what + " has empty element", st));
    }
    let tok = string.str_slice(value, st, i);
    out.push(tok);
    if i < n {
      i = i + 1;
      if i >= n {
        return _err_strs(_perr(what + " has empty element", i));
      }
    }
  }
  return _ok_strs(out);
}

// Validate digest domain elements: each is a non-empty URI with no spaces.
fn _digest_domain_check(domain: &Vec[Str]) -> Result[Str, Str> {
  var i = 0;
  while i < domain.len() {
    let t: Str = domain[i];
    if t.len() == 0 {
      return _err_str("auth: digest domain element is empty or contains a space");
    }
    if _has_space(t) {
      return _err_str("auth: digest domain element is empty or contains a space");
    }
    i = i + 1;
  }
  return _ok_str("");
}

/// Parse a Digest challenge header (RFC 7616 section 3.3).
/// Params: h - a header parsed from a WWW-Authenticate challenge.
/// Returns: Ok(challenge) with realm and nonce required, the algorithm
/// canonicalized, the qop offer tokenized, and stale/userhash/charset
/// normalized. Unknown parameters are ignored (they stay reachable through
/// the generic AuthHeader accessors).
/// Error case: Err("auth: challenge scheme is not Digest"), "auth: digest
/// challenge missing realm", "auth: digest challenge missing nonce", "auth:
/// digest unknown algorithm: X", "auth: digest invalid stale value: X",
/// "auth: digest invalid userhash value: X", "auth: digest unsupported
/// charset: X", and the auth_digest_qop_tokens / _split_spaces catalog.
/// Complexity: O(header length).
pub fn auth_digest_parse_challenge(h: &AuthHeader) -> Result[DigestChallenge, Str] {
  if !auth_scheme_is(h, "Digest") {
    return _err_dc("auth: challenge scheme is not Digest");
  }
  var c = DigestChallenge{
    realm: "",
    nonce: "",
    algorithm: "",
    qop: Vec[Str].new(),
    opaque: "",
    stale: 0,
    domain: Vec[Str].new(),
    userhash: 0,
    charset: ""
  };
  let rr = auth_header_param_get(h, "realm");
  if !rr.is_ok {
    return _err_dc("auth: digest challenge missing realm");
  }
  let realm_v: Str = rr.value;
  if realm_v.len() == 0 {
    return _err_dc("auth: digest challenge missing realm");
  }
  c.realm = realm_v;
  let nr = auth_header_param_get(h, "nonce");
  if !nr.is_ok {
    return _err_dc("auth: digest challenge missing nonce");
  }
  let nonce_v: Str = nr.value;
  if nonce_v.len() == 0 {
    return _err_dc("auth: digest challenge missing nonce");
  }
  c.nonce = nonce_v;
  let ar = auth_header_param_get(h, "algorithm");
  if ar.is_ok {
    let av: Str = ar.value;
    let canon = auth_digest_algorithm_canonical(av);
    if canon.len() == 0 {
      return _err_dc("auth: digest unknown algorithm: " + av);
    }
    c.algorithm = canon;
  }
  let qr = auth_header_param_get(h, "qop");
  if qr.is_ok {
    let qv: Str = qr.value;
    let tr = auth_digest_qop_tokens(qv);
    if !tr.is_ok {
      return _err_dc(tr.error);
    }
    c.qop = tr.value;
  }
  let orr = auth_header_param_get(h, "opaque");
  if orr.is_ok {
    let ov: Str = orr.value;
    c.opaque = ov;
  }
  let sr = auth_header_param_get(h, "stale");
  if sr.is_ok {
    let sv: Str = sr.value;
    if compare.str_eq_ignore_case(sv, "true") {
      c.stale = 1;
    } elif compare.str_eq_ignore_case(sv, "false") {
      c.stale = 0;
    } else {
      return _err_dc("auth: digest invalid stale value: " + sv);
    }
  }
  let dr = auth_header_param_get(h, "domain");
  if dr.is_ok {
    let dv: Str = dr.value;
    let ds = _split_spaces(dv, "digest domain");
    if !ds.is_ok {
      return _err_dc(ds.error);
    }
    c.domain = ds.value;
  }
  let ur = auth_header_param_get(h, "userhash");
  if ur.is_ok {
    let uv: Str = ur.value;
    if compare.str_eq_ignore_case(uv, "true") {
      c.userhash = 1;
    } elif compare.str_eq_ignore_case(uv, "false") {
      c.userhash = 0;
    } else {
      return _err_dc("auth: digest invalid userhash value: " + uv);
    }
  }
  let cr = auth_header_param_get(h, "charset");
  if cr.is_ok {
    let cv: Str = cr.value;
    if !compare.str_eq_ignore_case(cv, "UTF-8") {
      return _err_dc("auth: digest unsupported charset: " + cv);
    }
    c.charset = "UTF-8";
  }
  return _ok_dc(c);
}

// Append a quoted-string for s (escapes '"' and '\').
fn _quote_into(out: &mut Vec[UInt8], s: Str) {
  out.push(_AUTH_DQUOTE as UInt8);
  var i = 0;
  while i < s.len() {
    let c = _byte(s, i);
    if c == _AUTH_DQUOTE || c == _AUTH_BSLASH {
      out.push(_AUTH_BSLASH as UInt8);
    }
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  out.push(_AUTH_DQUOTE as UInt8);
}

// Append "name=value" with a leading space (first) or ", " (not first);
// quotes the value when required or when it is not a single token.
fn _emit_param(out: &mut Vec[UInt8], first: Bool, name: Str, value: Str, force_quote: Bool) {
  if first {
    builder.sb_push_str(out, " ");
  } else {
    builder.sb_push_str(out, ", ");
  }
  builder.sb_push_str(out, name);
  out.push(_AUTH_EQUALS as UInt8);
  if force_quote || !_is_token(value) {
    _quote_into(out, value);
  } else {
    builder.sb_push_str(out, value);
  }
}

/// Build a Digest challenge header value.
/// Params: c - the challenge to render.
/// Returns: Ok(value) with realm and nonce always quoted, algorithm as a
/// token, qop as a quoted comma list, domain as a quoted space list, and
/// stale/userhash rendered only when set.
/// Error case: Err for an empty realm or nonce, an unknown algorithm, an
/// invalid qop token, an unsupported charset, or an empty/space-containing
/// domain element.
/// Complexity: O(total text).
pub fn auth_digest_challenge_build(c: &DigestChallenge) -> Result[Str, Str] {
  if c.realm.len() == 0 {
    return _err_str("auth: digest challenge realm is empty");
  }
  if c.nonce.len() == 0 {
    return _err_str("auth: digest challenge nonce is empty");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "Digest realm=");
  _quote_into(&mut out, c.realm);
  builder.sb_push_str(&mut out, ", nonce=");
  _quote_into(&mut out, c.nonce);
  if c.algorithm.len() > 0 {
    let canon = auth_digest_algorithm_canonical(c.algorithm);
    if canon.len() == 0 {
      return _err_str("auth: digest unknown algorithm: " + c.algorithm);
    }
    builder.sb_push_str(&mut out, ", algorithm=");
    builder.sb_push_str(&mut out, canon);
  }
  if c.qop.len() > 0 {
    var listed = Vec[UInt8].new();
    var i = 0;
    while i < c.qop.len() {
      let t: Str = c.qop[i];
      if !_digest_qop_token_valid(t) {
        return _err_str("auth: digest qop token has invalid character");
      }
      if i > 0 {
        listed.push(_AUTH_COMMA as UInt8);
      }
      builder.sb_push_str(&mut listed, t);
      i = i + 1;
    }
    let joined = builder.sb_to_str(&listed);
    builder.sb_push_str(&mut out, ", qop=");
    _quote_into(&mut out, joined);
  }
  if c.opaque.len() > 0 {
    builder.sb_push_str(&mut out, ", opaque=");
    _quote_into(&mut out, c.opaque);
  }
  if c.stale != 0 {
    builder.sb_push_str(&mut out, ", stale=true");
  }
  if c.domain.len() > 0 {
    let dcheck = _digest_domain_check(&c.domain);
    if !dcheck.is_ok {
      return _err_str(dcheck.error);
    }
    var joined2 = Vec[UInt8].new();
    var k = 0;
    while k < c.domain.len() {
      let t: Str = c.domain[k];
      if k > 0 {
        joined2.push(_AUTH_SP as UInt8);
      }
      builder.sb_push_str(&mut joined2, t);
      k = k + 1;
    }
    let dtext = builder.sb_to_str(&joined2);
    builder.sb_push_str(&mut out, ", domain=");
    _quote_into(&mut out, dtext);
  }
  if c.userhash != 0 {
    builder.sb_push_str(&mut out, ", userhash=true");
  }
  if c.charset.len() > 0 {
    if !compare.str_eq_ignore_case(c.charset, "UTF-8") {
      return _err_str("auth: digest unsupported charset: " + c.charset);
    }
    builder.sb_push_str(&mut out, ", charset=UTF-8");
  }
  return _ok_str(builder.sb_to_str(&out));
}

// Read a plain-or-extended parameter pair; detects a response that carries
// both forms.
// Result[Str, Str]: Ok("plain") when only the plain parameter is present,
// Ok("star") when only the extended form is, Ok("") when neither.
fn _digest_param_form(h: &AuthHeader, plain: Str, star: Str) -> Result[Str, Str] {
  let p1 = auth_header_param_get(h, plain);
  let p2 = auth_header_param_get(h, star);
  if p1.is_ok && p2.is_ok {
    return _err_str("auth: digest response has both " + plain + " and " + star);
  }
  if p1.is_ok {
    return _ok_str("plain");
  }
  if p2.is_ok {
    return _ok_str("star");
  }
  return _ok_str("");
}

// Raw value of the parameter pair (plain preferred, star when only present),
// or "" when neither is present.
fn _digest_param_raw(h: &AuthHeader, plain: Str, star: Str) -> Str {
  let f = _digest_param_form(h, plain, star);
  if !f.is_ok {
    return "";
  }
  let kind: Str = f.value;
  if compare.str_compare(kind, "plain") == 0 {
    let r = auth_header_param_get(h, plain);
    let v: Str = r.value;
    return v;
  }
  if compare.str_compare(kind, "star") == 0 {
    let r2 = auth_header_param_get(h, star);
    let v2: Str = r2.value;
    return v2;
  }
  return "";
}

/// Parse a Digest response header (RFC 7616 section 3.4).
/// Params: h - a header parsed from an Authorization challenge response.
/// Returns: Ok(response); username, realm and nonce accept both the plain
/// and the extended (username*/realm*/nonce*) form; a response carrying both
/// forms of one name is an error. Extended values are stored raw and flagged
/// by the *_star fields (decode with auth_digest_ext_decode).
/// Error case: Err("auth: authorization scheme is not Digest"), "auth:
/// digest response missing uri", "auth: digest response missing response",
/// "auth: digest response has both X and X*", "auth: digest unknown
/// algorithm: X", "auth: digest response qop must be a single token", "auth:
/// digest invalid userhash value: X".
/// Complexity: O(header length).
pub fn auth_digest_parse_response(h: &AuthHeader) -> Result[DigestResponse, Str> {
  if !auth_scheme_is(h, "Digest") {
    return _err_dr("auth: authorization scheme is not Digest");
  }
  var r = DigestResponse{
    username: "",
    username_star: 0,
    realm: "",
    realm_star: 0,
    nonce: "",
    nonce_star: 0,
    uri: "",
    response: "",
    algorithm: "",
    qop: "",
    nc: "",
    cnonce: "",
    opaque: "",
    userhash: 0
  };
  let uf = _digest_param_form(h, "username", "username*");
  if !uf.is_ok {
    return _err_dr(uf.error);
  }
  let uk: Str = uf.value;
  if compare.str_compare(uk, "plain") == 0 {
    r.username = _digest_param_raw(h, "username", "username*");
  } elif compare.str_compare(uk, "star") == 0 {
    r.username = _digest_param_raw(h, "username", "username*");
    r.username_star = 1;
  }
  let rf = _digest_param_form(h, "realm", "realm*");
  if !rf.is_ok {
    return _err_dr(rf.error);
  }
  let rk: Str = rf.value;
  if compare.str_compare(rk, "plain") == 0 {
    r.realm = _digest_param_raw(h, "realm", "realm*");
  } elif compare.str_compare(rk, "star") == 0 {
    r.realm = _digest_param_raw(h, "realm", "realm*");
    r.realm_star = 1;
  }
  let nf = _digest_param_form(h, "nonce", "nonce*");
  if !nf.is_ok {
    return _err_dr(nf.error);
  }
  let nk: Str = nf.value;
  if compare.str_compare(nk, "plain") == 0 {
    r.nonce = _digest_param_raw(h, "nonce", "nonce*");
  } elif compare.str_compare(nk, "star") == 0 {
    r.nonce = _digest_param_raw(h, "nonce", "nonce*");
    r.nonce_star = 1;
  }
  let urir = auth_header_param_get(h, "uri");
  if !urir.is_ok {
    return _err_dr("auth: digest response missing uri");
  }
  let uv: Str = urir.value;
  r.uri = uv;
  let rsp = auth_header_param_get(h, "response");
  if !rsp.is_ok {
    return _err_dr("auth: digest response missing response");
  }
  let rv: Str = rsp.value;
  r.response = rv;
  let ar = auth_header_param_get(h, "algorithm");
  if ar.is_ok {
    let av: Str = ar.value;
    let canon = auth_digest_algorithm_canonical(av);
    if canon.len() == 0 {
      return _err_dr("auth: digest unknown algorithm: " + av);
    }
    r.algorithm = canon;
  }
  let qr = auth_header_param_get(h, "qop");
  if qr.is_ok {
    let qv: Str = qr.value;
    if !_digest_qop_token_valid(qv) {
      return _err_dr("auth: digest response qop must be a single token");
    }
    r.qop = qv;
  }
  let ncr = auth_header_param_get(h, "nc");
  if ncr.is_ok {
    let nv: Str = ncr.value;
    r.nc = nv;
  }
  let ccr = auth_header_param_get(h, "cnonce");
  if ccr.is_ok {
    let cv: Str = ccr.value;
    r.cnonce = cv;
  }
  let opr = auth_header_param_get(h, "opaque");
  if opr.is_ok {
    let ov2: Str = opr.value;
    r.opaque = ov2;
  }
  let uhr = auth_header_param_get(h, "userhash");
  if uhr.is_ok {
    let hv: Str = uhr.value;
    if compare.str_eq_ignore_case(hv, "true") {
      r.userhash = 1;
    } elif compare.str_eq_ignore_case(hv, "false") {
      r.userhash = 0;
    } else {
      return _err_dr("auth: digest invalid userhash value: " + hv);
    }
  }
  return _ok_dr(r);
}

/// Decode an HTTP ext-value (RFC 5987) as used by username*, realm* and
/// nonce*: charset "'" [language] "'" percent-encoded. Only UTF-8 is
/// accepted.
/// Params: raw - the raw parameter value.
/// Returns: Ok(decoded) with %XX escapes (case-insensitive hex) decoded.
/// Error case: Err("auth: digest ext-value missing charset separator"),
/// "auth: digest ext-value charset is not UTF-8: X", "auth: digest
/// ext-value missing language separator", "auth: digest ext-value invalid
/// percent escape at offset N", "auth: digest ext-value percent escape
/// decodes to NUL at offset N" (offsets into raw).
/// Complexity: O(raw.len()).
pub fn auth_digest_ext_decode(raw: Str) -> Result[Str, Str] {
  let q1 = _find_byte(raw, _AUTH_APOS, 0);
  if q1 < 0 {
    return _err_str("auth: digest ext-value missing charset separator");
  }
  let cs = string.str_slice(raw, 0, q1);
  if !compare.str_eq_ignore_case(cs, "UTF-8") {
    return _err_str("auth: digest ext-value charset is not UTF-8: " + cs);
  }
  let q2 = _find_byte(raw, _AUTH_APOS, q1 + 1);
  if q2 < 0 {
    return _err_str("auth: digest ext-value missing language separator");
  }
  let val = string.str_slice(raw, q2 + 1, raw.len());
  var out = Vec[UInt8].new();
  var i = 0;
  while i < val.len() {
    let c = _byte(val, i);
    if c == 37 {
      if i + 2 >= val.len() {
        return _err_str(_perr("digest ext-value invalid percent escape", i));
      }
      let hi = _hex_val(_byte(val, i + 1));
      let lo = _hex_val(_byte(val, i + 2));
      if hi < 0 || lo < 0 {
        return _err_str(_perr("digest ext-value invalid percent escape", i));
      }
      let v = (hi << 4) | lo;
      if v == 0 {
        return _err_str(_perr("digest ext-value percent escape decodes to NUL", i));
      }
      out.push(v as UInt8);
      i = i + 3;
    } else {
      out.push(string.byte_at(val, i));
      i = i + 1;
    }
  }
  return _ok_str(builder.sb_to_str(&out));
}

/// Structural check of a Digest response without a challenge.
/// Params: r - a parsed response.
/// Returns: Ok("") when required fields are present (username, realm,
/// nonce, uri, response), the response digest length matches the algorithm
/// (default MD5), nc is 8 hex digits when present, and qop/nc/cnonce are
/// consistent (qop requires nc and cnonce, and must be auth or auth-int).
/// Error case: Err("auth: digest response missing username|realm|nonce|
/// uri|response digest"), "auth: digest unknown algorithm: X", "auth: digest
/// response digest length mismatch", "auth: digest response digest is not
/// hexadecimal", "auth: digest nc must be 8 hex digits", "auth: digest
/// unknown qop: X", "auth: digest nc required with qop", "auth: digest
/// cnonce required with qop".
/// Complexity: O(response length).
pub fn auth_digest_response_check(r: &DigestResponse) -> Result[Str, Str] {
  if r.username.len() == 0 {
    return _err_str("auth: digest response missing username");
  }
  if r.realm.len() == 0 {
    return _err_str("auth: digest response missing realm");
  }
  if r.nonce.len() == 0 {
    return _err_str("auth: digest response missing nonce");
  }
  if r.uri.len() == 0 {
    return _err_str("auth: digest response missing uri");
  }
  if r.response.len() == 0 {
    return _err_str("auth: digest response missing response digest");
  }
  var algo: Str = r.algorithm;
  if algo.len() == 0 {
    algo = "MD5";
  }
  let want = auth_digest_response_hex_len(algo);
  if want == 0 {
    return _err_str("auth: digest unknown algorithm: " + r.algorithm);
  }
  if r.response.len() != want {
    return _err_str("auth: digest response digest length mismatch");
  }
  if !_all_hex(r.response) {
    return _err_str("auth: digest response digest is not hexadecimal");
  }
  if r.nc.len() > 0 {
    if r.nc.len() != 8 {
      return _err_str("auth: digest nc must be 8 hex digits");
    }
    if !_all_hex(r.nc) {
      return _err_str("auth: digest nc must be 8 hex digits");
    }
  }
  if r.qop.len() > 0 {
    if !auth_digest_qop_is_valid(r.qop) {
      return _err_str("auth: digest unknown qop: " + r.qop);
    }
    if r.nc.len() == 0 {
      return _err_str("auth: digest nc required with qop");
    }
    if r.cnonce.len() == 0 {
      return _err_str("auth: digest cnonce required with qop");
    }
  }
  return _ok_str("");
}

/// Validate a Digest response against the challenge it answers.
/// Params: r - the parsed response; c - the parsed challenge.
/// Returns: Ok("") when the response is structurally valid
/// (auth_digest_response_check), realm and nonce match, the algorithm
/// matches the challenge (absent means MD5 on both sides), the qop is one
/// the challenge offered (and required when the challenge offered qop), and
/// userhash is sent exactly when the challenge offered it.
/// Error case: the auth_digest_response_check catalog plus "auth: digest
/// response realm mismatch", "auth: digest response nonce mismatch", "auth:
/// digest challenge unknown algorithm: X", "auth: digest response unknown
/// algorithm: X", "auth: digest algorithm mismatch", "auth: digest qop
/// required: challenge offered qop", "auth: digest qop not offered: X",
/// "auth: digest qop sent but challenge offered none", "auth: digest
/// userhash required", "auth: digest userhash not offered".
/// Complexity: O(response length + offer count).
pub fn auth_digest_validate_response(r: &DigestResponse, c: &DigestChallenge) -> Result[Str, Str> {
  let base = auth_digest_response_check(r);
  if !base.is_ok {
    return _err_str(base.error);
  }
  if c.realm.len() > 0 && r.realm.len() > 0 {
    if compare.str_compare(c.realm, r.realm) != 0 {
      return _err_str("auth: digest response realm mismatch");
    }
  }
  if c.nonce.len() > 0 && r.nonce.len() > 0 {
    if compare.str_compare(c.nonce, r.nonce) != 0 {
      return _err_str("auth: digest response nonce mismatch");
    }
  }
  var calgo: Str = c.algorithm;
  if calgo.len() == 0 {
    calgo = "MD5";
  }
  var ralgo: Str = r.algorithm;
  if ralgo.len() == 0 {
    ralgo = "MD5";
  }
  let cc = auth_digest_algorithm_canonical(calgo);
  let rc = auth_digest_algorithm_canonical(ralgo);
  if cc.len() == 0 {
    return _err_str("auth: digest challenge unknown algorithm: " + c.algorithm);
  }
  if rc.len() == 0 {
    return _err_str("auth: digest response unknown algorithm: " + r.algorithm);
  }
  if compare.str_compare(cc, rc) != 0 {
    return _err_str("auth: digest algorithm mismatch");
  }
  if c.qop.len() > 0 {
    if r.qop.len() == 0 {
      return _err_str("auth: digest qop required: challenge offered qop");
    }
    if !auth_digest_qop_offered(c, r.qop) {
      return _err_str("auth: digest qop not offered: " + r.qop);
    }
  } else {
    if r.qop.len() > 0 {
      return _err_str("auth: digest qop sent but challenge offered none");
    }
  }
  if c.userhash == 1 && r.userhash == 0 {
    return _err_str("auth: digest userhash required");
  }
  if c.userhash == 0 && r.userhash == 1 {
    return _err_str("auth: digest userhash not offered");
  }
  return _ok_str("");
}

// --------------------------------------------------
//  Bearer (RFC 6750)
// --------------------------------------------------

/// True when `code` is one of the three registered Bearer error codes:
/// invalid_request, invalid_token, insufficient_scope (comparison is
/// case-sensitive, the codes are exact tokens).
/// Params: code - the error code. Returns: the predicate.
/// Error case: none. Complexity: O(code.len()).
pub fn auth_bearer_error_is_valid(code: Str) -> Bool {
  if compare.str_compare(code, "invalid_request") == 0 {
    return true;
  }
  if compare.str_compare(code, "invalid_token") == 0 {
    return true;
  }
  if compare.str_compare(code, "insufficient_scope") == 0 {
    return true;
  }
  return false;
}

/// Validate a Bearer access token for building credentials: a token68
/// (ALPHA / DIGIT / "-" "." "_" "~" "+" "/" followed by optional '=').
/// Params: token - the token68. Returns: Ok("") when well formed.
/// Error case: Err("auth: bearer token is empty"), Err("auth: bearer token
/// is not a token68") and Err("auth: bearer token has invalid character at
/// offset N").
/// Complexity: O(token.len()).
pub fn auth_bearer_token_check(token: Str) -> Result[Str, Str] {
  if token.len() == 0 {
    return _err_str("auth: bearer token is empty");
  }
  var i = 0;
  while i < token.len() && _is_token68_char(_byte(token, i)) {
    i = i + 1;
  }
  if i == 0 {
    return _err_str("auth: bearer token is not a token68");
  }
  var j = i;
  while j < token.len() && _byte(token, j) == _AUTH_EQUALS {
    j = j + 1;
  }
  if j != token.len() {
    return _err_str(_perr("bearer token has invalid character", j));
  }
  return _ok_str("");
}

/// Parse a Bearer Authorization header value (RFC 6750 section 2.1).
/// Params: value - the full field value.
/// Returns: Ok(token68) with the access token.
/// Error case: Err("auth: authorization scheme is not Bearer"), Err("auth:
/// Bearer credentials must be a token68") and the parser catalog.
/// Complexity: O(value.len()).
pub fn auth_bearer_token(value: Str) -> Result[Str, Str] {
  let hr = auth_parse_authorization(value);
  if !hr.is_ok {
    return _err_str(hr.error);
  }
  let h: AuthHeader = hr.value;
  if !auth_scheme_is(&h, "Bearer") {
    return _err_str("auth: authorization scheme is not Bearer");
  }
  if h.uses_token68 != 1 {
    return _err_str("auth: Bearer credentials must be a token68");
  }
  let t: Str = h.token68;
  return _ok_str(t);
}

/// Build the Bearer credentials header value "Bearer <token68>".
/// Params: token - the access token (validated as token68).
/// Returns: Ok("Bearer <token>").
/// Error case: the auth_bearer_token_check catalog.
/// Complexity: O(token.len()).
pub fn auth_bearer_authorization(token: Str) -> Result[Str, Str> {
  let tr = auth_bearer_token_check(token);
  if !tr.is_ok {
    return _err_str(tr.error);
  }
  return _ok_str("Bearer " + token);
}

// Validate scope tokens: printable ASCII except '"' and '\'.
fn _bearer_scope_check(scope: &Vec[Str]) -> Result[Str, Str> {
  var i = 0;
  while i < scope.len() {
    let t: Str = scope[i];
    if t.len() == 0 {
      return _err_str("auth: bearer scope token is empty or contains a space");
    }
    var k = 0;
    while k < t.len() {
      let c = _byte(t, k);
      if c < 33 || c > 126 || c == _AUTH_DQUOTE || c == _AUTH_BSLASH {
        return _err_str(_perr("bearer scope token has invalid character", k));
      }
      k = k + 1;
    }
    i = i + 1;
  }
  return _ok_str("");
}

/// Parse a Bearer challenge header (RFC 6750 section 3).
/// Params: h - a header parsed from a WWW-Authenticate challenge.
/// Returns: Ok(challenge); scope tokens are split on single spaces, error
/// must be one of the three registered codes, and error_description /
/// error_uri require error to be present.
/// Error case: Err("auth: challenge scheme is not Bearer"), "auth: bearer
/// unknown error code: X", "auth: bearer error_description without error",
/// "auth: bearer error_uri without error", "auth: bearer scope has empty
/// element at offset N" (offset into the decoded scope value), "auth: bearer
/// scope token has invalid character at offset N".
/// Complexity: O(header length).
pub fn auth_bearer_parse_challenge(h: &AuthHeader) -> Result[BearerChallenge, Str> {
  if !auth_scheme_is(h, "Bearer") {
    return _err_bc("auth: challenge scheme is not Bearer");
  }
  var c = BearerChallenge{
    realm: "",
    scope: Vec[Str].new(),
    error: "",
    error_present: 0,
    error_description: "",
    error_uri: ""
  };
  let rr = auth_header_param_get(h, "realm");
  if rr.is_ok {
    let rv: Str = rr.value;
    c.realm = rv;
  }
  let sr = auth_header_param_get(h, "scope");
  if sr.is_ok {
    let sv: Str = sr.value;
    let parts = _split_spaces(sv, "bearer scope");
    if !parts.is_ok {
      return _err_bc(parts.error);
    }
    let sc: Vec[Str] = parts.value;
    let sv2 = _bearer_scope_check(&sc);
    if !sv2.is_ok {
      return _err_bc(sv2.error);
    }
    c.scope = sc;
  }
  let er = auth_header_param_get(h, "error");
  if er.is_ok {
    let ev: Str = er.value;
    if !auth_bearer_error_is_valid(ev) {
      return _err_bc("auth: bearer unknown error code: " + ev);
    }
    c.error = ev;
    c.error_present = 1;
  }
  let dr = auth_header_param_get(h, "error_description");
  if dr.is_ok {
    if c.error_present == 0 {
      return _err_bc("auth: bearer error_description without error");
    }
    let dv: Str = dr.value;
    c.error_description = dv;
  }
  let ur = auth_header_param_get(h, "error_uri");
  if ur.is_ok {
    if c.error_present == 0 {
      return _err_bc("auth: bearer error_uri without error");
    }
    let uv: Str = ur.value;
    c.error_uri = uv;
  }
  return _ok_bc(c);
}

/// Build a Bearer challenge header value.
/// Params: c - the challenge to render.
/// Returns: Ok(value); realm, scope and error_description/error_uri are
/// quoted when needed, error is emitted as a token.
/// Error case: Err for an unknown error code, error_description or
/// error_uri without error, and invalid scope tokens.
/// Complexity: O(total text).
pub fn auth_bearer_challenge_build(c: &BearerChallenge) -> Result[Str, Str> {
  if c.error_present == 1 {
    if !auth_bearer_error_is_valid(c.error) {
      return _err_str("auth: bearer unknown error code: " + c.error);
    }
  } else {
    if c.error_description.len() > 0 {
      return _err_str("auth: bearer error_description without error");
    }
    if c.error_uri.len() > 0 {
      return _err_str("auth: bearer error_uri without error");
    }
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "Bearer");
  var first = true;
  if c.realm.len() > 0 {
    _emit_param(&mut out, first, "realm", c.realm, true);
    first = false;
  }
  if c.scope.len() > 0 {
    let sccheck = _bearer_scope_check(&c.scope);
    if !sccheck.is_ok {
      return _err_str(sccheck.error);
    }
    var joined = Vec[UInt8].new();
    var i = 0;
    while i < c.scope.len() {
      if i > 0 {
        joined.push(_AUTH_SP as UInt8);
      }
      let t: Str = c.scope[i];
      builder.sb_push_str(&mut joined, t);
      i = i + 1;
    }
    let joined_text = builder.sb_to_str(&joined);
    _emit_param(&mut out, first, "scope", joined_text, true);
    first = false;
  }
  if c.error_present == 1 {
    _emit_param(&mut out, first, "error", c.error, false);
    first = false;
    if c.error_description.len() > 0 {
      _emit_param(&mut out, first, "error_description", c.error_description, true);
      first = false;
    }
    if c.error_uri.len() > 0 {
      _emit_param(&mut out, first, "error_uri", c.error_uri, true);
      first = false;
    }
  }
  return _ok_str(builder.sb_to_str(&out));
}
