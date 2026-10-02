// XIOM -- xiom.gcp.auth: service-account / OAuth / JWT claim model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM MODEL of the GCP credential surface: the service-account key
// shape, OAuth scope validation, a bounded flat-JSON token-envelope scanner
// and the self-signed JWT claim-set shape with deterministic JSON rendering.
//
// SIGNING IS OUT OF SCOPE. This module never computes a signature: the
// v0.62.2 stdlib `xiom.crypto` does not link from a package (`undefined
// symbol: xiom_sha256_hash`), so RSA/ES256 signing cannot be provided here.
// `gca_jwt_signing_supported` returns false and the caller signs the rendered
// claim set with a transport-layer tool. Likewise no token is fetched over
// the network: the caller supplies the JSON body.
//
// Documented subset:
//   * service-account keys: key_type "service_account", non-empty project id,
//     private_key_id and client_id, a PEM "BEGIN PRIVATE KEY" private key,
//     a "...@....gserviceaccount.com" client email and the standard token URI.
//   * scopes: "https://www.googleapis.com/auth/{name}" with name built from
//     lowercase letters/digits/'.'/'-'/'_'.
//   * token envelope: flat JSON with string access_token, int expires_in and
//     string token_type; "Bearer" is the modeled token type.
//   * JWT claims: iss (service-account email), space-separated scope list,
//     aud, iat >= 0 and 0 < exp - iat <= 3600.
//
// v0.62.2 discipline: free functions only; Str equality via
// xiom.string.compare; bounded loops; leaf Ok/Err constructors for struct
// payloads.

module xiom.gcp.auth

use xiom.gcp.core;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// Prefix shared by all modeled Google OAuth scopes.
pub const GCA_SCOPE_PREFIX: Str = "https://www.googleapis.com/auth/";

/// Full Cloud Platform scope.
pub const GCA_SCOPE_CLOUD_PLATFORM: Str = "https://www.googleapis.com/auth/cloud-platform";

/// Cloud Storage read/write scope.
pub const GCA_SCOPE_DEVSTORAGE_READ_WRITE: Str = "https://www.googleapis.com/auth/devstorage.read_write";

/// BigQuery scope.
pub const GCA_SCOPE_BIGQUERY: Str = "https://www.googleapis.com/auth/bigquery";

/// Pub/Sub scope.
pub const GCA_SCOPE_PUBSUB: Str = "https://www.googleapis.com/auth/pubsub";

/// Compute Engine scope.
pub const GCA_SCOPE_COMPUTE: Str = "https://www.googleapis.com/auth/compute";

/// Google token endpoint URI used by service-account keys.
pub const GCA_TOKEN_URI: Str = "https://oauth2.googleapis.com/token";

/// Suffix of a service-account email.
pub const GCA_SERVICE_ACCOUNT_SUFFIX: Str = ".gserviceaccount.com";

/// Maximum modeled token lifetime in seconds (3600).
pub const GCA_MAX_TOKEN_LIFETIME: Int = 3600;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// The JSON key-file fields of a service-account key (private material is
/// carried as opaque text; nothing is decoded or verified here).
pub type GcaServiceAccountKey = {
  key_type: Str;
  project_id: Str;
  private_key_id: Str;
  private_key: Str;
  client_email: Str;
  client_id: Str;
  token_uri: Str;
}

/// An OAuth 2.0 token envelope.
pub type GcaToken = {
  access_token: Str;
  expires_in: Int;
  token_type: Str;
}

/// A self-signed JWT claim set (signing out of scope).
pub type GcaJwtClaims = {
  issuer: Str;
  scope: Str;
  audience: Str;
  issued_at: Int;
  expires_at: Int;
}

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

fn _ok_token(v: GcaToken) -> Result[GcaToken, Str] {
  return Ok(v);
}

fn _err_token(m: Str) -> Result[GcaToken, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Service-account keys and scopes
// --------------------------------------------------

/// Validate a service-account key shape. Params: k - the key. Returns Ok("")
/// or the first error. Complexity O(total field length).
pub fn gca_service_account_key_validate(k: &GcaServiceAccountKey) -> Result[Str, Str] {
  if !core.gcp_str_eq(k.key_type, "service_account") {
    return _err_str("gcp: key_type must be service_account");
  }
  let pn = k.project_id.len();
  if pn < 1 || pn > 63 {
    return _err_str("gcp: invalid project id: " + k.project_id);
  }
  if k.private_key_id.len() == 0 {
    return _err_str("gcp: empty private_key_id");
  }
  if !core.gcp_contains(k.private_key, "BEGIN PRIVATE KEY") {
    return _err_str("gcp: private_key is not a PEM private key");
  }
  if !core.gcp_contains(k.client_email, "@") {
    return _err_str("gcp: invalid client_email: " + k.client_email);
  }
  if !core.gcp_ends_with(k.client_email, GCA_SERVICE_ACCOUNT_SUFFIX) {
    return _err_str("gcp: client_email is not a service account: " + k.client_email);
  }
  if k.client_id.len() == 0 {
    return _err_str("gcp: empty client_id");
  }
  if !core.gcp_str_eq(k.token_uri, GCA_TOKEN_URI) {
    return _err_str("gcp: unexpected token_uri: " + k.token_uri);
  }
  return _ok_str("");
}

/// True for one modeled OAuth scope. Params: scope - the candidate.
/// Complexity O(scope.len()).
pub fn gca_scope_is_valid(scope: Str) -> Bool {
  if !core.gcp_starts_with(scope, GCA_SCOPE_PREFIX) {
    return false;
  }
  let pn = GCA_SCOPE_PREFIX.len();
  let n = scope.len();
  if n <= pn {
    return false;
  }
  var i = pn;
  while i < n {
    let c = core.gcp_byte(scope, i);
    if !core.gcp_is_alnum_lower(c) {
      var ok = false;
      if c == 46 || c == 45 || c == 95 {
        ok = true;
      }
      if !ok {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

// True for a non-empty space-separated list of valid scopes.
fn _gca_scope_string_is_valid(scope: Str) -> Bool {
  let n = scope.len();
  if n == 0 {
    return false;
  }
  var start = 0;
  var i = 0;
  while i <= n {
    var at_end = i == n;
    if !at_end {
      let b = core.gcp_byte(scope, i);
      if b == 32 {
        at_end = true;
      }
    }
    if at_end {
      if i <= start {
        return false;
      }
      let tok = core.gcp_substr(scope, start, i);
      if !gca_scope_is_valid(tok) {
        return false;
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return true;
}

/// Join a non-empty scope list with single spaces. Params: scopes - the list.
/// Returns the joined text or the first invalid-scope error. Complexity
/// O(total length).
pub fn gca_scope_list_join(scopes: &Vec[Str]) -> Result[Str, Str] {
  if scopes.len() < 1 {
    return _err_str("gcp: empty scope list");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < scopes.len() {
    let sc: Str = scopes[i];
    if !gca_scope_is_valid(sc) {
      return _err_str("gcp: invalid scope: " + sc);
    }
    if i > 0 {
      out.push(32 as UInt8);
    }
    var j = 0;
    while j < sc.len() {
      out.push(string.byte_at(sc, j));
      j = j + 1;
    }
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&out));
}

/// True when the scope list contains the exact scope. Params: scopes - the
/// list; scope - the wanted scope. Complexity O(n*m).
pub fn gca_scope_list_has(scopes: &Vec[Str], scope: Str) -> Bool {
  var i = 0;
  while i < scopes.len() {
    let sc: Str = scopes[i];
    if core.gcp_str_eq(sc, scope) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Flat-JSON token envelope
// --------------------------------------------------

// Skip JSON whitespace from `from` and return the next index.
fn _gca_skip_ws(s: Str, from: Int) -> Int {
  var i = from;
  while i < s.len() {
    let b = core.gcp_byte(s, i);
    if b == 32 || b == 9 || b == 10 || b == 13 {
      i = i + 1;
    } else {
      return i;
    }
  }
  return i;
}

// Index after the closing quote of the first `"key"` occurrence, or -1.
fn _gca_find_key(s: Str, key: Str) -> Int {
  let kn = key.len();
  if kn == 0 {
    return -1;
  }
  let n = s.len();
  var i = 0;
  while i + kn + 1 < n {
    let b = core.gcp_byte(s, i);
    if b == 34 {
      let inner = core.gcp_substr(s, i + 1, i + 1 + kn);
      let after = core.gcp_byte(s, i + 1 + kn);
      if core.gcp_str_eq(inner, key) && after == 34 {
        return i + kn + 2;
      }
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first byte of the value of `key`, or -1.
fn _gca_value_pos(s: Str, key: Str) -> Int {
  let n = s.len();
  let p = _gca_find_key(s, key);
  if p < 0 {
    return -1;
  }
  let i = _gca_skip_ws(s, p);
  if i >= n {
    return -1;
  }
  let colon = core.gcp_byte(s, i);
  if colon != 58 {
    return -1;
  }
  return _gca_skip_ws(s, i + 1);
}

// Parse the JSON string whose opening quote is at `start`.
fn _gca_parse_string_at(s: Str, start: Int, n: Int) -> Result[Str, Str] {
  if start >= n {
    return _err_str("gcp: token JSON expects a string");
  }
  let q = core.gcp_byte(s, start);
  if q != 34 {
    return _err_str("gcp: token JSON expects a string");
  }
  var out = Vec[UInt8].new();
  var i = start + 1;
  while i < n {
    let b = core.gcp_byte(s, i);
    if b == 34 {
      return _ok_str(builder.sb_to_str(&out));
    }
    if b == 92 {
      if i + 1 >= n {
        return _err_str("gcp: unterminated JSON escape");
      }
      let e = core.gcp_byte(s, i + 1);
      var mapped = e;
      if e == 110 {
        mapped = 10;
      }
      if e == 116 {
        mapped = 9;
      }
      if e == 114 {
        mapped = 13;
      }
      if e == 98 {
        mapped = 8;
      }
      if e == 102 {
        mapped = 12;
      }
      out.push((mapped & 0xFF) as UInt8);
      i = i + 2;
    } else {
      out.push((b & 0xFF) as UInt8);
      i = i + 1;
    }
  }
  return _err_str("gcp: unterminated token JSON string");
}

// Parse a JSON integer whose first byte is at `start`.
fn _gca_parse_int_at(s: Str, start: Int, n: Int) -> Result[Int, Str] {
  var i = start;
  var negative = false;
  if i < n {
    let sign = core.gcp_byte(s, i);
    if sign == 45 {
      negative = true;
      i = i + 1;
    }
  }
  var digits = 0;
  var v = 0;
  while i < n {
    let b = core.gcp_byte(s, i);
    if b >= 48 && b <= 57 {
      v = v * 10 + (b - 48);
      digits = digits + 1;
      i = i + 1;
    } else {
      i = n;
    }
  }
  if digits == 0 {
    return _err_int("gcp: token JSON expects an integer");
  }
  if negative {
    return _ok_int(0 - v);
  }
  return _ok_int(v);
}

fn _gca_json_str_field(json: Str, key: Str) -> Result[Str, Str] {
  let n = json.len();
  let p = _gca_value_pos(json, key);
  if p < 0 {
    return _err_str("gcp: token JSON missing field: " + key);
  }
  if p >= n {
    return _err_str("gcp: token JSON missing field: " + key);
  }
  let q = core.gcp_byte(json, p);
  if q != 34 {
    return _err_str("gcp: token JSON field is not a string: " + key);
  }
  return _gca_parse_string_at(json, p, n);
}

fn _gca_json_int_field(json: Str, key: Str) -> Result[Int, Str] {
  let n = json.len();
  let p = _gca_value_pos(json, key);
  if p < 0 {
    return _err_int("gcp: token JSON missing field: " + key);
  }
  if p >= n {
    return _err_int("gcp: token JSON missing field: " + key);
  }
  return _gca_parse_int_at(json, p, n);
}

/// Parse a flat token-envelope JSON body. Params: json - the body text.
/// Returns the GcaToken or the first scanner error. Complexity O(json.len()).
pub fn gca_token_json_parse(json: Str) -> Result[GcaToken, Str] {
  let at = _gca_json_str_field(json, "access_token");
  if !at.is_ok {
    let m1: Str = at.error;
    return _err_token(m1);
  }
  let tt = _gca_json_str_field(json, "token_type");
  if !tt.is_ok {
    let m2: Str = tt.error;
    return _err_token(m2);
  }
  let ei = _gca_json_int_field(json, "expires_in");
  if !ei.is_ok {
    let m3: Str = ei.error;
    return _err_token(m3);
  }
  let t = GcaToken{
    access_token: at.value;
    expires_in: ei.value;
    token_type: tt.value;
  };
  return _ok_token(t);
}

/// True for a modeled token envelope: non-empty access token, positive
/// lifetime and token_type "Bearer". Params: t - the token. Complexity
/// O(access_token.len()).
pub fn gca_token_is_valid(t: &GcaToken) -> Bool {
  if t.access_token.len() == 0 {
    return false;
  }
  if t.expires_in < 1 {
    return false;
  }
  return core.gcp_str_eq(t.token_type, "Bearer");
}

// --------------------------------------------------
//  JWT claim set (signing out of scope)
// --------------------------------------------------

/// False: JWT signing is out of scope for this package (the stdlib crypto
/// module does not link from a package on v0.62.2). Complexity O(1).
pub fn gca_jwt_signing_supported() -> Bool {
  return false;
}

/// Validate a self-signed JWT claim set. Params: c - the claims. Returns
/// Ok("") or the first error. Complexity O(total field length).
pub fn gca_jwt_claims_validate(c: &GcaJwtClaims) -> Result[Str, Str] {
  if !core.gcp_contains(c.issuer, "@") {
    return _err_str("gcp: jwt issuer is not an email: " + c.issuer);
  }
  if !core.gcp_ends_with(c.issuer, GCA_SERVICE_ACCOUNT_SUFFIX) {
    return _err_str("gcp: jwt issuer is not a service account: " + c.issuer);
  }
  if !_gca_scope_string_is_valid(c.scope) {
    return _err_str("gcp: invalid jwt scope list");
  }
  if c.audience.len() == 0 {
    return _err_str("gcp: empty jwt audience");
  }
  if c.issued_at < 0 {
    return _err_str("gcp: negative jwt issued_at");
  }
  if c.expires_at <= c.issued_at {
    return _err_str("gcp: jwt expires_at must exceed issued_at");
  }
  if c.expires_at - c.issued_at > GCA_MAX_TOKEN_LIFETIME {
    return _err_str("gcp: jwt lifetime above 3600 s");
  }
  return _ok_str("");
}

// Append the raw bytes of `s` to `out`.
fn _gca_push_lit(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

/// Render the claim set as deterministic flat JSON with the field order
/// iss, scope, aud, iat, exp -- exactly the bytes to sign. Params: c - the
/// claims. Returns the JSON or the first validation error. Complexity
/// O(total field length).
pub fn gca_jwt_claims_json(c: &GcaJwtClaims) -> Result[Str, Str] {
  let v = gca_jwt_claims_validate(c);
  if !v.is_ok {
    let m: Str = v.error;
    return _err_str(m);
  }
  var out = Vec[UInt8].new();
  out.push(123 as UInt8);
  _gca_push_lit(&mut out, "\"iss\":");
  core.gcp_json_push_quoted(&mut out, c.issuer);
  _gca_push_lit(&mut out, ",\"scope\":");
  core.gcp_json_push_quoted(&mut out, c.scope);
  _gca_push_lit(&mut out, ",\"aud\":");
  core.gcp_json_push_quoted(&mut out, c.audience);
  _gca_push_lit(&mut out, ",\"iat\":");
  core.gcp_json_push_int(&mut out, c.issued_at);
  _gca_push_lit(&mut out, ",\"exp\":");
  core.gcp_json_push_int(&mut out, c.expires_at);
  out.push(125 as UInt8);
  return _ok_str(builder.sb_to_str(&out));
}
