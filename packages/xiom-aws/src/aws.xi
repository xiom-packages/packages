// XIOM -- xiom.aws: pure-XIOM AWS request/signing model (SigV4)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM MODEL of the AWS request surface: SigV4 signing (canonical
// request, string to sign, derived signing key, Authorization header),
// credential model with a resolution chain, service/request model, a service
// registry with explicit case dispatch, a bounded deterministic retry/backoff
// policy and a response envelope model. No network, no FFI, no clocks: every
// input (region, date, credentials, response) is supplied by the caller, so
// every result is deterministic and testable.
//
// SHA-256 / HMAC-SHA-256 are hand-rolled in the sibling module xiom.aws.base
// (the v0.62.2 stdlib crypto does not link from a package; see that module).
//
// Covered rules (see SPEC.md for the step-by-step signing description):
//   * SigV4 URI encoding: unreserved ALPHA / DIGIT / '-' '.' '_' '~' literal,
//     every other byte as %XX with UPPERCASE hex; the canonical URI keeps '/'.
//   * Canonical query string: pairs sorted by encoded name then encoded value,
//     joined with '&'; parameters without '=' render as "name=".
//   * Canonical headers: names lowercased, values trimmed with internal runs
//     of SP / HT collapsed to one space, lines sorted by name, each "name:value"
//     terminated by '\n'; the "host" header is required for signing.
//   * Credential scope "date/region/service/aws4_request" with the signing
//     name mapping (cloudwatch -> monitoring); derived signing key
//     HMAC(HMAC(HMAC(HMAC("AWS4"+secret, date), region), service),
//     "aws4_request").
//   * Service registry: iam / sts / route53 / cloudfront are global endpoints,
//     cloudwatch maps to monitoring.{region}..., everything else uses
//     {service}.{region}.amazonaws.com.
//   * Retry policy: full-jitter exponential schedule (cap = base * 2^(attempt-1)
//     clamped to max), deterministic from an integer seed; retryable HTTP
//     statuses 408 / 429 / 500 / 502 / 503 / 504 and a fixed set of transient
//     AWS error codes.
//   * Response envelope: status class (1xx..5xx), success 2xx, body-shape
//     classification empty / JSON / XML / text / binary, case-insensitive
//     header lookup, retryable derivation.
//
// v0.62.2 discipline: free functions only, no match, no methods, no
// Vec[StructType], no Vec[Float64], Ok/Err only inside leaf helpers, Str
// comparisons via xiom.string.compare.str_compare, masked byte widening.

module xiom.aws

use xiom.aws.base;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

pub const AWS_SIGV4_ALGORITHM: Str = "AWS4-HMAC-SHA256";
pub const AWS_SIGV4_TERMINATOR: Str = "aws4_request";

// Response status classes (aws_response_class).
pub const AWS_STATUS_UNKNOWN: Int = 0;
pub const AWS_STATUS_INFORMATIONAL: Int = 1;
pub const AWS_STATUS_SUCCESS: Int = 2;
pub const AWS_STATUS_REDIRECT: Int = 3;
pub const AWS_STATUS_CLIENT_ERROR: Int = 4;
pub const AWS_STATUS_SERVER_ERROR: Int = 5;

// Body shapes (aws_body_shape).
pub const AWS_SHAPE_EMPTY: Int = 0;
pub const AWS_SHAPE_JSON: Int = 1;
pub const AWS_SHAPE_XML: Int = 2;
pub const AWS_SHAPE_TEXT: Int = 3;
pub const AWS_SHAPE_BINARY: Int = 4;

// Credential resolution chain sources, in chain order (explicit first).
pub const AWS_CRED_SOURCE_NONE: Int = 0;
pub const AWS_CRED_SOURCE_EXPLICIT: Int = 1;
pub const AWS_CRED_SOURCE_ENVIRONMENT: Int = 2;
pub const AWS_CRED_SOURCE_PROFILE: Int = 3;
pub const AWS_CRED_SOURCE_INSTANCE: Int = 4;

// Retry policy defaults.
pub const AWS_RETRY_MAX_ATTEMPTS: Int = 5;
pub const AWS_RETRY_BASE_MS: Int = 50;
pub const AWS_RETRY_MAX_MS: Int = 20000;

// Byte constants used by the canonicalizers (Int space, always masked).
const _AWS_TAB: Int = 9;
const _AWS_LF: Int = 10;
const _AWS_CR: Int = 13;
const _AWS_SPACE: Int = 32;
const _AWS_AMP: Int = 38;
const _AWS_PLUS: Int = 43;
const _AWS_DASH: Int = 45;
const _AWS_DOT: Int = 46;
const _AWS_EQUALS: Int = 61;
const _AWS_SLASH: Int = 47;
const _AWS_PERCENT: Int = 37;
const _AWS_UNDERSCORE: Int = 95;
const _AWS_TILDE: Int = 126;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// One resolved credential. `expiry_unix` is 0 for non-expiring credentials
/// (long-term access keys); `session_token` is "" when absent.
pub type AwsCredential = {
  access_key: Str;
  secret_key: Str;
  session_token: Str;
  expiry_unix: Int;
  source: Int;
}

/// One service registry entry.
pub type AwsService = {
  name: Str;
  signing_name: Str;
  host: Str;
  is_global: Bool;
}

/// A request as modeled before signing. `action` is the AWS action name; it is
/// carried for the caller's own dispatch and does not enter the signature
/// (the canonical query does).
pub type AwsRequest = {
  service: Str;
  region: Str;
  method: Str;
  path: Str;
  query: Str;
  action: Str;
  payload_hash: Str;
}

/// Scalar response envelope (headers stay in caller-owned parallel Vecs).
pub type AwsResponse = {
  status: Int;
  shape: Int;
  retryable: Bool;
}

// --------------------------------------------------
//  Result constructors (leaf helpers only; see module header)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _ok_cred(v: AwsCredential) -> Result[AwsCredential, Str] {
  return Ok(v);
}

fn _err_cred(m: Str) -> Result[AwsCredential, Str] {
  return Err(m);
}

fn _ok_service(v: AwsService) -> Result[AwsService, Str] {
  return Ok(v);
}

fn _err_service(m: Str) -> Result[AwsService, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Local helpers
// --------------------------------------------------

fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Copy s[from, to) into a fresh Str (bounds are the caller's contract).
fn _substr(s: Str, from: Int, to: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = from;
  while i < to {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// First index of byte `ch` in s[from, to), or -1.
fn _index_of(s: Str, from: Int, to: Int, ch: Int) -> Int {
  var i = from;
  while i < to {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == ch {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when the (unencoded) byte is a SigV4 unreserved character.
fn _is_unreserved(c: Int) -> Bool {
  if c >= 65 && c <= 90 {
    return true;
  }
  if c >= 97 && c <= 122 {
    return true;
  }
  if c >= 48 && c <= 57 {
    return true;
  }
  if c == _AWS_DASH || c == _AWS_DOT || c == _AWS_UNDERSCORE || c == _AWS_TILDE {
    return true;
  }
  return false;
}

// Encode one byte into `out`; '/' is literal when keep_slash is true.
fn _encode_byte(out: &mut Vec[UInt8], b: Int, keep_slash: Bool) {
  if keep_slash && b == _AWS_SLASH {
    out.push(47 as UInt8);
    return;
  }
  if _is_unreserved(b) {
    out.push((b & 0xFF) as UInt8);
    return;
  }
  out.push(37 as UInt8);
  out.push(string.byte_at("0123456789ABCDEF", (b >> 4) & 0x0F));
  out.push(string.byte_at("0123456789ABCDEF", b & 0x0F));
}

// Lowercase ASCII copy.
fn _lower_str(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b >= 65 && b <= 90 {
      out.push((b + 32) as UInt8);
    } else {
      out.push((b & 0xFF) as UInt8);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Trim leading/trailing SP / HT and collapse internal runs to one space.
fn _normalize_header_value(s: Str) -> Str {
  let n = s.len();
  var i = 0;
  var done = false;
  while i < n && !done {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == _AWS_SPACE || b == _AWS_TAB {
      i = i + 1;
    } else {
      done = true;
    }
  }
  var out = Vec[UInt8].new();
  var pending_space = false;
  var started = false;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == _AWS_SPACE || b == _AWS_TAB {
      pending_space = true;
    } else {
      if pending_space && started {
        out.push(32 as UInt8);
      }
      pending_space = false;
      out.push((b & 0xFF) as UInt8);
      started = true;
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// Index of the smallest unused entry of v (used[i] == 0), or -1.
fn _pick_min_unused(v: &Vec[Str], used: &Vec[Int], count: Int) -> Int {
  var best = -1;
  var i = 0;
  while i < count {
    let ui: Int = used[i];
    if ui == 0 {
      if best < 0 {
        best = i;
      } else {
        let cand: Str = v[i];
        let cur: Str = v[best];
        if compare.str_compare(cand, cur) < 0 {
          best = i;
        }
      }
    }
    i = i + 1;
  }
  return best;
}

// Index of the smallest unused (name, value) pair by name then value, or -1.
fn _pick_min_pair(names: &Vec[Str], values: &Vec[Str], used: &Vec[Int], count: Int) -> Int {
  var best = -1;
  var i = 0;
  while i < count {
    let ui: Int = used[i];
    if ui == 0 {
      if best < 0 {
        best = i;
      } else {
        let cn: Str = names[i];
        let bn: Str = names[best];
        let cmp = compare.str_compare(cn, bn);
        if cmp < 0 {
          best = i;
        } else if cmp == 0 {
          let cv: Str = values[i];
          let bv: Str = values[best];
          if compare.str_compare(cv, bv) < 0 {
            best = i;
          }
        }
      }
    }
    i = i + 1;
  }
  return best;
}

// Append all bytes of s to out.
fn _append_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// True when a header name matches `want` ignoring case.
fn _headers_have(names: &Vec[Str], want: Str) -> Bool {
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    if compare.str_eq_ignore_case(nm, want) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  URI encoding and canonicalization
// --------------------------------------------------

/// SigV4 URI encoding of every byte of `s` (strict: '/' becomes %2F).
pub fn aws_uri_encode(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    _encode_byte(&mut out, b, false);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Canonical URI: like aws_uri_encode but '/' is preserved.
pub fn aws_canonical_uri(path: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < path.len() {
    let b: Int = (string.byte_at(path, i) as Int) & 0xFF;
    _encode_byte(&mut out, b, true);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Canonical query string: raw "k=v&..." pairs URI-encoded, sorted by encoded
/// name then encoded value, joined with '&'. A parameter without '=' renders
/// as "name=". Empty segments ("a=1&&b=2") are ignored.
pub fn aws_canonical_query(query: Str) -> Str {
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  let n = query.len();
  var start = 0;
  while start <= n {
    let amp = _index_of(query, start, n, _AWS_AMP);
    var stop = n;
    if amp >= 0 {
      stop = amp;
    }
    if stop > start {
      let eq = _index_of(query, start, stop, _AWS_EQUALS);
      if eq >= 0 {
        let nm = _substr(query, start, eq);
        let vl = _substr(query, eq + 1, stop);
        names.push(aws_uri_encode(nm));
        values.push(aws_uri_encode(vl));
      } else {
        let nm2 = _substr(query, start, stop);
        names.push(aws_uri_encode(nm2));
        values.push("");
      }
    }
    if amp < 0 {
      start = n + 1;
    } else {
      start = amp + 1;
    }
  }
  let count = names.len();
  var used = Vec[Int].new();
  var u = 0;
  while u < count {
    used.push(0);
    u = u + 1;
  }
  var out = Vec[UInt8].new();
  var emitted = 0;
  while emitted < count {
    let best = _pick_min_pair(&names, &values, &used, count);
    if best >= 0 {
      if emitted > 0 {
        out.push((_AWS_AMP & 0xFF) as UInt8);
      }
      let bn: Str = names[best];
      let bv: Str = values[best];
      _append_str(&mut out, bn);
      out.push((_AWS_EQUALS & 0xFF) as UInt8);
      _append_str(&mut out, bv);
      used[best] = 1;
    }
    emitted = emitted + 1;
  }
  return builder.sb_to_str(&out);
}

/// Canonical headers block: lowercased names, trimmed/collapsed values, sorted
/// by name, every line "name:value\n" (the final line ends with '\n'). Duplicate
/// header names are not merged: the request model requires unique names.
pub fn aws_canonical_headers(names: &Vec[Str], values: &Vec[Str]) -> Str {
  if names.len() != values.len() {
    return "";
  }
  let count = names.len();
  var lnames = Vec[Str].new();
  var nvalues = Vec[Str].new();
  var i = 0;
  while i < count {
    let nm: Str = names[i];
    let vl: Str = values[i];
    lnames.push(_lower_str(nm));
    nvalues.push(_normalize_header_value(vl));
    i = i + 1;
  }
  var used = Vec[Int].new();
  var u = 0;
  while u < count {
    used.push(0);
    u = u + 1;
  }
  var out = Vec[UInt8].new();
  var emitted = 0;
  while emitted < count {
    let best = _pick_min_unused(&lnames, &used, count);
    if best >= 0 {
      let bn: Str = lnames[best];
      let bv: Str = nvalues[best];
      _append_str(&mut out, bn);
      out.push(58 as UInt8);
      _append_str(&mut out, bv);
      out.push((_AWS_LF & 0xFF) as UInt8);
      used[best] = 1;
    }
    emitted = emitted + 1;
  }
  return builder.sb_to_str(&out);
}

/// SignedHeaders list: lowercased names sorted by name, joined with ';'.
pub fn aws_signed_headers(names: &Vec[Str]) -> Str {
  let count = names.len();
  var lnames = Vec[Str].new();
  var i = 0;
  while i < count {
    let nm: Str = names[i];
    lnames.push(_lower_str(nm));
    i = i + 1;
  }
  var used = Vec[Int].new();
  var u = 0;
  while u < count {
    used.push(0);
    u = u + 1;
  }
  var out = Vec[UInt8].new();
  var emitted = 0;
  while emitted < count {
    let best = _pick_min_unused(&lnames, &used, count);
    if best >= 0 {
      if emitted > 0 {
        out.push(59 as UInt8);
      }
      let bn: Str = lnames[best];
      _append_str(&mut out, bn);
      used[best] = 1;
    }
    emitted = emitted + 1;
  }
  return builder.sb_to_str(&out);
}

/// Canonical request text:
/// METHOD \n canonical-uri \n canonical-query \n canonical-headers \n
/// signed-headers \n payload-hash. `host` must be present in the headers.
pub fn aws_canonical_request(req: &AwsRequest, names: &Vec[Str], values: &Vec[Str]) -> Result[Str, Str] {
  let method: Str = req.method;
  let payload_hash: Str = req.payload_hash;
  let path: Str = req.path;
  let query: Str = req.query;
  if method.len() == 0 {
    return _err_str("aws: missing method");
  }
  if payload_hash.len() == 0 {
    return _err_str("aws: missing payload hash");
  }
  if names.len() != values.len() {
    return _err_str("aws: header name/value count mismatch");
  }
  if !_headers_have(names, "host") {
    return _err_str("aws: missing host header");
  }
  let uri = aws_canonical_uri(path);
  let cq = aws_canonical_query(query);
  let ch = aws_canonical_headers(names, values);
  let sh = aws_signed_headers(names);
  return _ok_str(method + "\n" + uri + "\n" + cq + "\n" + ch + "\n" + sh + "\n" + payload_hash);
}

// --------------------------------------------------
//  Signing steps
// --------------------------------------------------

/// First 8 characters of an amz date ("20150830T123600Z" -> "20150830").
pub fn aws_date8(amz_date: Str) -> Str {
  if amz_date.len() <= 8 {
    return amz_date;
  }
  return _substr(amz_date, 0, 8);
}

// SigV4 signing-name mapping.
fn _signing_name(service: Str) -> Str {
  if _streq(service, "cloudwatch") {
    return "monitoring";
  }
  return service;
}

/// Credential scope "date/region/signing-name/aws4_request".
pub fn aws_credential_scope(amz_date: Str, region: Str, service: Str) -> Result[Str, Str] {
  let d8 = aws_date8(amz_date);
  if d8.len() != 8 {
    return _err_str("aws: bad amz date");
  }
  if region.len() == 0 {
    return _err_str("aws: missing region");
  }
  if service.len() == 0 {
    return _err_str("aws: missing service");
  }
  return _ok_str(d8 + "/" + region + "/" + _signing_name(service) + "/" + AWS_SIGV4_TERMINATOR);
}

/// String to sign: algorithm \n amz-date \n scope \n hex(sha256(canonical)).
pub fn aws_string_to_sign(amz_date: Str, scope: Str, canonical_request: Str) -> Str {
  let cr_hash = base.aws_sha256_hex_str(canonical_request);
  return AWS_SIGV4_ALGORITHM + "\n" + amz_date + "\n" + scope + "\n" + cr_hash;
}

/// Derived SigV4 signing key (32 bytes): four HMAC-SHA-256 rounds.
pub fn aws_signing_key(secret_key: Str, date8: Str, region: Str, service: Str) -> Vec[UInt8] {
  let secret_prefix: Str = "AWS4" + secret_key;
  let k0 = base.aws_bytes_of_str(secret_prefix);
  let d8 = base.aws_bytes_of_str(date8);
  let rg = base.aws_bytes_of_str(region);
  let sn = _signing_name(service);
  let sv = base.aws_bytes_of_str(sn);
  let term = base.aws_bytes_of_str(AWS_SIGV4_TERMINATOR);
  let k1 = base.aws_hmac_sha256(&k0, &d8);
  let k2 = base.aws_hmac_sha256(&k1, &rg);
  let k3 = base.aws_hmac_sha256(&k2, &sv);
  let k4 = base.aws_hmac_sha256(&k3, &term);
  return k4;
}

/// Lowercase hex HMAC-SHA-256 of the string to sign under the signing key.
pub fn aws_signature_hex(signing_key: &Vec[UInt8], string_to_sign: Str) -> Str {
  let sts = base.aws_bytes_of_str(string_to_sign);
  return base.aws_hmac_sha256_hex(signing_key, &sts);
}

/// Authorization header value:
/// "AWS4-HMAC-SHA256 Credential=<ak>/<scope>, SignedHeaders=<sh>, Signature=<sig>".
pub fn aws_authorization_header(access_key: Str, scope: Str, signed_headers: Str, signature: Str) -> Str {
  return AWS_SIGV4_ALGORITHM + " Credential=" + access_key + "/" + scope + ", SignedHeaders=" + signed_headers + ", Signature=" + signature;
}

/// Full SigV4 signing of a modeled request with caller-supplied headers
/// (parallel name/value vectors; "host" required). The caller must include
/// every header the signature covers, including x-amz-security-token when a
/// session credential is used. Returns the Authorization header value.
pub fn aws_sign_v4(req: &AwsRequest, cred: &AwsCredential, amz_date: Str, names: &Vec[Str], values: &Vec[Str]) -> Result[Str, Str] {
  let ak: Str = cred.access_key;
  let sk: Str = cred.secret_key;
  let region: Str = req.region;
  let service: Str = req.service;
  if ak.len() == 0 {
    return _err_str("aws: missing access key");
  }
  if sk.len() == 0 {
    return _err_str("aws: missing secret key");
  }
  let scope_r = aws_credential_scope(amz_date, region, service);
  if !scope_r.is_ok {
    let em: Str = scope_r.error;
    return _err_str(em);
  }
  let scope: Str = scope_r.value;
  let cr_r = aws_canonical_request(req, names, values);
  if !cr_r.is_ok {
    let em2: Str = cr_r.error;
    return _err_str(em2);
  }
  let cr: Str = cr_r.value;
  let d8 = aws_date8(amz_date);
  let key = aws_signing_key(sk, d8, region, service);
  let sts = aws_string_to_sign(amz_date, scope, cr);
  let sig = aws_signature_hex(&key, sts);
  let sh = aws_signed_headers(names);
  return _ok_str(aws_authorization_header(ak, scope, sh, sig));
}

// --------------------------------------------------
//  Credential model
// --------------------------------------------------

/// Human-readable name of a credential source constant.
pub fn aws_credential_source_name(src: Int) -> Str {
  if src == AWS_CRED_SOURCE_EXPLICIT {
    return "explicit";
  }
  if src == AWS_CRED_SOURCE_ENVIRONMENT {
    return "environment";
  }
  if src == AWS_CRED_SOURCE_PROFILE {
    return "profile";
  }
  if src == AWS_CRED_SOURCE_INSTANCE {
    return "instance";
  }
  if src == AWS_CRED_SOURCE_NONE {
    return "none";
  }
  return "unknown";
}

/// A credential is usable when both keys are non-empty and it has not expired
/// (`expiry_unix` 0 means "no expiry"; expiry must be strictly after `now`).
pub fn aws_credential_valid(c: &AwsCredential, now_unix: Int) -> Bool {
  let ak: Str = c.access_key;
  let sk: Str = c.secret_key;
  if ak.len() == 0 {
    return false;
  }
  if sk.len() == 0 {
    return false;
  }
  let exp: Int = c.expiry_unix;
  if exp <= 0 {
    return true;
  }
  return exp > now_unix;
}

/// Resolve the first usable credential from a chain given as parallel vectors
/// in chain order (explicit > environment > profile > instance). All vectors
/// must have the same length. Returns Err("aws: no usable credentials") when
/// no candidate is usable.
pub fn aws_resolve_credential(sources: &Vec[Int], access_keys: &Vec[Str], secret_keys: &Vec[Str], session_tokens: &Vec[Str], expiries: &Vec[Int], now_unix: Int) -> Result[AwsCredential, Str] {
  let n = sources.len();
  if access_keys.len() != n || secret_keys.len() != n || session_tokens.len() != n || expiries.len() != n {
    return _err_cred("aws: credential chain arity mismatch");
  }
  var i = 0;
  while i < n {
    let ak: Str = access_keys[i];
    let skv: Str = secret_keys[i];
    let tok: Str = session_tokens[i];
    let exp: Int = expiries[i];
    let src: Int = sources[i];
    let cand = AwsCredential{
      access_key: ak;
      secret_key: skv;
      session_token: tok;
      expiry_unix: exp;
      source: src;
    };
    if aws_credential_valid(&cand, now_unix) {
      return _ok_cred(cand);
    }
    i = i + 1;
  }
  return _err_cred("aws: no usable credentials");
}

// --------------------------------------------------
//  Service registry (explicit case dispatch)
// --------------------------------------------------

fn _service_is_global(service: Str) -> Bool {
  if _streq(service, "iam") {
    return true;
  }
  if _streq(service, "sts") {
    return true;
  }
  if _streq(service, "route53") {
    return true;
  }
  if _streq(service, "cloudfront") {
    return true;
  }
  return false;
}

/// Service registry lookup. Global services (iam, sts, route53, cloudfront)
/// ignore the region; cloudwatch resolves to the monitoring endpoint; every
/// other non-empty service uses {service}.{region}.amazonaws.com.
pub fn aws_service_lookup(service: Str, region: Str) -> Result[AwsService, Str] {
  if service.len() == 0 {
    return _err_service("aws: empty service name");
  }
  let signing: Str = _signing_name(service);
  if _service_is_global(service) {
    let host_g: Str = service + ".amazonaws.com";
    return _ok_service(AwsService{ name: service; signing_name: signing; host: host_g; is_global: true; });
  }
  if region.len() == 0 {
    return _err_service("aws: empty region for regional service");
  }
  var host: Str = service + "." + region + ".amazonaws.com";
  if _streq(service, "cloudwatch") {
    host = "monitoring." + region + ".amazonaws.com";
  }
  return _ok_service(AwsService{ name: service; signing_name: signing; host: host; is_global: false; });
}

/// Convenience accessor: the endpoint host for a service/region, or Err.
pub fn aws_service_host(service: Str, region: Str) -> Result[Str, Str] {
  let r = aws_service_lookup(service, region);
  if !r.is_ok {
    let em: Str = r.error;
    return _err_str(em);
  }
  let svc: AwsService = r.value;
  let h: Str = svc.host;
  return _ok_str(h);
}

// --------------------------------------------------
//  Retry / backoff policy
// --------------------------------------------------

/// Transient HTTP statuses worth retrying (408, 429, 500, 502, 503, 504).
pub fn aws_retryable_status(status: Int) -> Bool {
  if status == 408 {
    return true;
  }
  if status == 429 {
    return true;
  }
  if status == 500 {
    return true;
  }
  if status == 502 {
    return true;
  }
  if status == 503 {
    return true;
  }
  if status == 504 {
    return true;
  }
  return false;
}

/// Transient AWS error codes worth retrying.
pub fn aws_retryable_error_code(code: Str) -> Bool {
  if _streq(code, "Throttling") {
    return true;
  }
  if _streq(code, "ThrottlingException") {
    return true;
  }
  if _streq(code, "ProvisionedThroughputExceededException") {
    return true;
  }
  if _streq(code, "RequestTimeout") {
    return true;
  }
  if _streq(code, "RequestTimeoutException") {
    return true;
  }
  if _streq(code, "SlowDown") {
    return true;
  }
  if _streq(code, "InternalError") {
    return true;
  }
  if _streq(code, "InternalErrorException") {
    return true;
  }
  if _streq(code, "ServiceUnavailable") {
    return true;
  }
  if _streq(code, "TransientError") {
    return true;
  }
  return false;
}

/// Full-jitter exponential backoff: attempt is 1-based, the cap is
/// min(base * 2^(attempt-1), max), and the delay is a deterministic
/// pseudo-random value in [0, cap] derived from `seed` alone (same inputs ->
/// same delay; different seeds -> different schedules). attempt <= 0 or a
/// non-positive base / max yields 0.
pub fn aws_backoff_delay_ms(attempt: Int, base_ms: Int, max_ms: Int, seed: Int) -> Int {
  if attempt <= 0 {
    return 0;
  }
  if base_ms <= 0 {
    return 0;
  }
  if max_ms <= 0 {
    return 0;
  }
  var cap = base_ms;
  var i = 1;
  while i < attempt {
    if cap >= max_ms {
      i = attempt;
    } else {
      cap = cap * 2;
      i = i + 1;
    }
  }
  if cap > max_ms {
    cap = max_ms;
  }
  var s = seed & 0x7FFFFFFF;
  s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
  s = (s ^ (s >> 13)) & 0x7FFFFFFF;
  s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
  return s % (cap + 1);
}

// --------------------------------------------------
//  Response envelope
// --------------------------------------------------

/// Status class: 1xx..5xx as AWS_STATUS_*; anything else AWS_STATUS_UNKNOWN.
pub fn aws_response_class(status: Int) -> Int {
  if status >= 100 && status <= 199 {
    return AWS_STATUS_INFORMATIONAL;
  }
  if status >= 200 && status <= 299 {
    return AWS_STATUS_SUCCESS;
  }
  if status >= 300 && status <= 399 {
    return AWS_STATUS_REDIRECT;
  }
  if status >= 400 && status <= 499 {
    return AWS_STATUS_CLIENT_ERROR;
  }
  if status >= 500 && status <= 599 {
    return AWS_STATUS_SERVER_ERROR;
  }
  return AWS_STATUS_UNKNOWN;
}

/// True for 2xx.
pub fn aws_response_is_success(status: Int) -> Bool {
  return aws_response_class(status) == AWS_STATUS_SUCCESS;
}

/// Body shape from the first non-whitespace byte plus a printability scan:
/// empty / JSON ('{' or '[') / XML ('<') / text (printable ASCII, TAB, LF, CR)
/// / binary (anything else).
pub fn aws_body_shape(body: &Vec[UInt8]) -> Int {
  let n = body.len();
  var i = 0;
  var done = false;
  while i < n && !done {
    let b: Int = (body[i] as Int) & 0xFF;
    if b == _AWS_SPACE || b == _AWS_TAB || b == _AWS_LF || b == _AWS_CR {
      i = i + 1;
    } else {
      done = true;
    }
  }
  if i >= n {
    return AWS_SHAPE_EMPTY;
  }
  let c: Int = (body[i] as Int) & 0xFF;
  if c == 123 || c == 91 {
    return AWS_SHAPE_JSON;
  }
  if c == 60 {
    return AWS_SHAPE_XML;
  }
  var j = 0;
  while j < n {
    let b: Int = (body[j] as Int) & 0xFF;
    if b == _AWS_TAB || b == _AWS_LF || b == _AWS_CR {
      j = j + 1;
    } else if b >= 32 && b <= 126 {
      j = j + 1;
    } else {
      return AWS_SHAPE_BINARY;
    }
  }
  return AWS_SHAPE_TEXT;
}

/// First header value whose name matches `name` ignoring case.
pub fn aws_header_find(names: &Vec[Str], values: &Vec[Str], name: Str) -> Result[Str, Str] {
  if names.len() != values.len() {
    return _err_str("aws: header name/value count mismatch");
  }
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    if compare.str_eq_ignore_case(nm, name) {
      let vl: Str = values[i];
      return _ok_str(vl);
    }
    i = i + 1;
  }
  return _err_str("aws: header not found: " + name);
}

/// Scalar response envelope: status, body shape and retryability.
pub fn aws_response_envelope(status: Int, body: &Vec[UInt8]) -> AwsResponse {
  return AwsResponse{
    status: status;
    shape: aws_body_shape(body);
    retryable: aws_retryable_status(status);
  };
}

// --------------------------------------------------
//  amz date from Unix seconds (UTC, integer-only)
// --------------------------------------------------

fn _pad2(n: Int) -> Str {
  if n < 10 {
    return "0" + convert.int_to_string(n);
  }
  return convert.int_to_string(n);
}

fn _pad4(n: Int) -> Str {
  var s = convert.int_to_string(n);
  while s.len() < 4 {
    s = "0" + s;
  }
  return s;
}

// Days since 1970-01-01 -> (year, month, day); Hinnant civil_from_days.
fn _civil_from_days(z: Int) -> (Int, Int, Int) {
  let zz = z + 719468;
  let era = zz / 146097;
  let doe = zz - era * 146097;
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  let mp = (5 * doy + 2) / 153;
  let d = doy - (153 * mp + 2) / 5 + 1;
  var m = mp + 3;
  if mp >= 10 {
    m = mp - 9;
  }
  var y = yoe + era * 400;
  if m <= 2 {
    y = y + 1;
  }
  return (y, m, d);
}

/// AWS amz date "YYYYMMDDTHHMMSSZ" for non-negative Unix seconds (UTC).
pub fn aws_amz_date_from_unix(secs: Int) -> Result[Str, Str] {
  if secs < 0 {
    return _err_str("aws: negative unix time");
  }
  let days = secs / 86400;
  let rem = secs % 86400;
  let (y, m, d) = _civil_from_days(days);
  let hh = rem / 3600;
  let mm = (rem % 3600) / 60;
  let ss = rem % 60;
  return _ok_str(_pad4(y) + _pad2(m) + _pad2(d) + "T" + _pad2(hh) + _pad2(mm) + _pad2(ss) + "Z");
}
