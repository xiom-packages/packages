// XIOM -- xiom.azure.auth: pure-XIOM Microsoft Entra ID token model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Models the Microsoft Entra ID (Azure AD) client-credentials surface the
// caller drives over its own transport. This module is deliberately
// structural: it validates ids, scopes, URLs, token envelopes and an
// identity resolution chain, and never computes signatures, hashes or JWTs.
//
//   * Tenant ids (GUID or domain), client ids (GUID) and client secrets.
//   * Scopes: "https://{resource}/.default" validation, appendix and
//     resource extraction.
//   * Authority and v2.0 token endpoint URLs.
//   * Token envelope: Bearer token type, positive lifetime, scope, optional
//     refresh token; absolute expiry arithmetic with a caller-supplied skew;
//     the "Bearer {token}" Authorization header value.
//   * Identity sources (client secret, certificate, managed identity, CLI,
//     environment) and a parallel-vector resolution chain that skips expired
//     or incomplete candidates.
//
// v0.62.2 discipline: free functions only, no match, no &mut scalar
// parameters, masked byte widening, bounded loops, no Vec[StructType],
// Ok/Err construction confined to the _ok_* / _err_* leaf helpers.

module xiom.azure.auth

use xiom.azure.base;
use xiom.string;

// Identity sources, in chain order (explicit client secret first).
pub const AZURE_IDENTITY_NONE: Int = 0;
pub const AZURE_IDENTITY_CLIENT_SECRET: Int = 1;
pub const AZURE_IDENTITY_CERTIFICATE: Int = 2;
pub const AZURE_IDENTITY_MANAGED_IDENTITY: Int = 3;
pub const AZURE_IDENTITY_CLI: Int = 4;
pub const AZURE_IDENTITY_ENVIRONMENT: Int = 5;

// The v2 scope suffix.
pub const AZURE_SCOPE_SUFFIX: Str = "/.default";

/// One resolved identity.
pub type AzureIdentity = {
  tenant_id: Str;
  client_id: Str;
  client_secret: Str;
  source: Int;
  expires_unix: Int;
}

/// One token-endpoint response envelope (shape only; no signature checks).
pub type AzureToken = {
  access_token: Str;
  token_type: Str;
  expires_in_sec: Int;
  scope: Str;
  refresh_token: Str;
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

fn _ok_identity(v: AzureIdentity) -> Result[AzureIdentity, Str] {
  return Ok(v);
}

fn _err_identity(m: Str) -> Result[AzureIdentity, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Local helpers
// --------------------------------------------------

fn _streq_ci(a: Str, b: Str) -> Bool {
  return base.azure_streq_ignore_case(a, b);
}

fn _byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

fn _has_prefix(s: Str, prefix: Str) -> Bool {
  if s.len() < prefix.len() {
    return false;
  }
  let head = base.azure_substr(s, 0, prefix.len());
  return base.azure_streq(head, prefix);
}

fn _ends_with(s: Str, suffix: Str) -> Bool {
  let n = s.len();
  let m = suffix.len();
  if n < m {
    return false;
  }
  let tail = base.azure_substr(s, n - m, n);
  return base.azure_streq(tail, suffix);
}

// --------------------------------------------------
//  IDs
// --------------------------------------------------

/// Tenant id: a GUID or a domain name (1..253 chars, letters/digits/'-'/'.',
/// starting and ending alphanumeric, no "..").
pub fn azure_tenant_id_valid(s: Str) -> Bool {
  if base.azure_guid_valid(s) {
    return true;
  }
  let n = s.len();
  if n < 1 || n > 253 {
    return false;
  }
  let b0: Int = _byte_at(s, 0);
  let bl: Int = _byte_at(s, n - 1);
  if !base.azure_is_alpha(b0) && !base.azure_is_digit(b0) {
    return false;
  }
  if !base.azure_is_alpha(bl) && !base.azure_is_digit(bl) {
    return false;
  }
  var i = 0;
  while i < n {
    let b: Int = _byte_at(s, i);
    let ok = base.azure_is_alpha(b) || base.azure_is_digit(b) || b == 45 || b == 46;
    if !ok {
      return false;
    }
    if i > 0 {
      let prev: Int = _byte_at(s, i - 1);
      if b == 46 && prev == 46 {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

/// Client (application) id: canonical GUID shape.
pub fn azure_client_id_valid(s: Str) -> Bool {
  return base.azure_guid_valid(s);
}

// --------------------------------------------------
//  Scopes and endpoints
// --------------------------------------------------

/// Scope: "https://{host}/.default" with a non-empty host without '/' or
/// whitespace.
pub fn azure_scope_valid(scope: Str) -> Bool {
  if !_has_prefix(scope, "https://") {
    return false;
  }
  if !_ends_with(scope, AZURE_SCOPE_SUFFIX) {
    return false;
  }
  let n = scope.len();
  if n <= 8 + 9 {
    return false;
  }
  let host = base.azure_substr(scope, 8, n - 9);
  if host.len() == 0 {
    return false;
  }
  var i = 0;
  while i < host.len() {
    let b: Int = _byte_at(host, i);
    if b < 33 || b == 47 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Turn a resource URL into its ".default" scope; an already suffixed
/// resource is returned canonicalized (trailing '/' removed).
pub fn azure_scope_for_resource(resource: Str) -> Result[Str, Str] {
  if resource.len() == 0 {
    return _err_str("azure: empty resource");
  }
  if !_has_prefix(resource, "https://") {
    return _err_str("azure: resource must be https");
  }
  var base_url = resource;
  while base_url.len() > 0 && _ends_with(base_url, "/") {
    base_url = base.azure_substr(base_url, 0, base_url.len() - 1);
  }
  if _ends_with(base_url, AZURE_SCOPE_SUFFIX) {
    if !azure_scope_valid(base_url) {
      return _err_str("azure: invalid scope");
    }
    return _ok_str(base_url);
  }
  let full = base_url + AZURE_SCOPE_SUFFIX;
  if !azure_scope_valid(full) {
    return _err_str("azure: invalid scope");
  }
  return _ok_str(full);
}

/// Resource URL of a ".default" scope.
pub fn azure_scope_resource(scope: Str) -> Result[Str, Str] {
  if !azure_scope_valid(scope) {
    return _err_str("azure: invalid scope");
  }
  return _ok_str(base.azure_substr(scope, 0, scope.len() - 9));
}

/// Authority URL "https://login.microsoftonline.com/{tenant}".
pub fn azure_authority_url(tenant_id: Str) -> Result[Str, Str] {
  if !azure_tenant_id_valid(tenant_id) {
    return _err_str("azure: invalid tenant id");
  }
  return _ok_str("https://login.microsoftonline.com/" + tenant_id);
}

/// v2.0 token endpoint URL ".../oauth2/v2.0/token".
pub fn azure_token_url(tenant_id: Str) -> Result[Str, Str] {
  let a = azure_authority_url(tenant_id);
  if !a.is_ok {
    let em: Str = a.error;
    return _err_str(em);
  }
  let av: Str = a.value;
  return _ok_str(av + "/oauth2/v2.0/token");
}

// --------------------------------------------------
//  Token envelope
// --------------------------------------------------

/// Token shape: 1..4096-byte access token, Bearer token type (case-
/// insensitive), positive lifetime, valid scope, optional refresh token.
pub fn azure_token_valid(t: &AzureToken) -> Bool {
  let at: Str = t.access_token;
  let tt: Str = t.token_type;
  let exp: Int = t.expires_in_sec;
  let sc: Str = t.scope;
  let rt: Str = t.refresh_token;
  if at.len() < 1 || at.len() > 4096 {
    return false;
  }
  if !base.azure_is_printable_ascii(at) {
    return false;
  }
  if !_streq_ci(tt, "Bearer") {
    return false;
  }
  if exp < 1 || exp > 2147483647 {
    return false;
  }
  if !azure_scope_valid(sc) {
    return false;
  }
  if rt.len() > 4096 {
    return false;
  }
  return true;
}

/// Absolute expiry Unix time, or -1 for invalid inputs.
pub fn azure_token_expires_at(acquired_unix: Int, expires_in_sec: Int) -> Int {
  if acquired_unix < 0 {
    return -1;
  }
  if expires_in_sec < 1 {
    return -1;
  }
  return acquired_unix + expires_in_sec;
}

/// True when the token is expired at `now_unix` with `skew_sec` of early
/// refresh margin (negative skew is treated as 0; a non-positive expiry is
/// always expired).
pub fn azure_token_is_expired(expires_at: Int, now_unix: Int, skew_sec: Int) -> Bool {
  if expires_at <= 0 {
    return true;
  }
  var skew = skew_sec;
  if skew < 0 {
    skew = 0;
  }
  return now_unix + skew >= expires_at;
}

/// "Bearer {access_token}" header value, or Err for an invalid envelope.
pub fn azure_bearer_header(t: &AzureToken) -> Result[Str, Str] {
  if !azure_token_valid(t) {
    return _err_str("azure: malformed token");
  }
  let at: Str = t.access_token;
  return _ok_str("Bearer " + at);
}

// --------------------------------------------------
//  Identity chain
// --------------------------------------------------

/// Identity-source name (unknown -> "unknown").
pub fn azure_identity_source_name(source: Int) -> Str {
  if source == AZURE_IDENTITY_CLIENT_SECRET {
    return "client_secret";
  }
  if source == AZURE_IDENTITY_CERTIFICATE {
    return "certificate";
  }
  if source == AZURE_IDENTITY_MANAGED_IDENTITY {
    return "managed_identity";
  }
  if source == AZURE_IDENTITY_CLI {
    return "cli";
  }
  if source == AZURE_IDENTITY_ENVIRONMENT {
    return "environment";
  }
  if source == AZURE_IDENTITY_NONE {
    return "none";
  }
  return "unknown";
}

/// Identity usability: known source, valid tenant, valid client id, a
/// non-empty secret for secret/certificate sources and an unexpired
/// credential (expires_unix 0 means "no expiry"; otherwise strictly after
/// `now_unix`).
pub fn azure_identity_valid(id: &AzureIdentity, now_unix: Int) -> Bool {
  let src: Int = id.source;
  let tenant: Str = id.tenant_id;
  let client: Str = id.client_id;
  let secret: Str = id.client_secret;
  let exp: Int = id.expires_unix;
  if src < AZURE_IDENTITY_CLIENT_SECRET || src > AZURE_IDENTITY_ENVIRONMENT {
    return false;
  }
  if !azure_tenant_id_valid(tenant) {
    return false;
  }
  if !azure_client_id_valid(client) {
    return false;
  }
  if src == AZURE_IDENTITY_CLIENT_SECRET || src == AZURE_IDENTITY_CERTIFICATE {
    if secret.len() == 0 {
      return false;
    }
  }
  if secret.len() > 4096 {
    return false;
  }
  if exp > 0 && exp <= now_unix {
    return false;
  }
  return true;
}

/// Resolve the first usable identity from parallel vectors in chain order.
/// All vectors must share one length; Err("azure: no usable identity") when
/// no candidate is usable.
pub fn azure_identity_resolve(sources: &Vec[Int], tenant_ids: &Vec[Str], client_ids: &Vec[Str], secrets: &Vec[Str], expiries: &Vec[Int], now_unix: Int) -> Result[AzureIdentity, Str] {
  let n = sources.len();
  if tenant_ids.len() != n || client_ids.len() != n || secrets.len() != n || expiries.len() != n {
    return _err_identity("azure: identity chain arity mismatch");
  }
  var i = 0;
  while i < n {
    let src: Int = sources[i];
    let tenant: Str = tenant_ids[i];
    let client: Str = client_ids[i];
    let secret: Str = secrets[i];
    let exp: Int = expiries[i];
    let cand = AzureIdentity{
      tenant_id: tenant;
      client_id: client;
      client_secret: secret;
      source: src;
      expires_unix: exp;
    };
    if azure_identity_valid(&cand, now_unix) {
      return _ok_identity(cand);
    }
    i = i + 1;
  }
  return _err_identity("azure: no usable identity");
}
