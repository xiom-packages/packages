// XIOM -- xiom.vault: composed vault client operations (package entry module)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The `xiom.vault` package models secret-vault integrations (Vault-shaped)
// with pure, deterministic XIOM: no HTTP, no crypto, no FFI. This entry
// module composes the sibling modules into ready-to-send request builders so
// a consumer can import `xiom.vault` plus the area modules it needs:
//
//   * `xiom.vault.client` -- request/response/body model (methods, paths,
//     headers, JSON-ish body builder, response envelope)
//   * `xiom.vault.json`   -- bounded flat-JSON scanner (raw key lookup)
//   * `xiom.vault.kv`     -- KV v1/v2 paths, versions, soft-delete model
//   * `xiom.vault.unseal` -- GF(256) Shamir sharing + unseal progress
//   * `xiom.vault.auth`   -- token / AppRole login models
//   * `xiom.vault.policy` -- path rules, capability sets, glob matching
//   * `xiom.vault.core`   -- shared constants and byte helpers
//
// Everything here is a thin composition: build a request, attach the body
// and the X-Vault-Token header. Success means the request STRUCTURE is
// valid; sending it and interpreting the response are the caller's concern.
//
// v0.62.2 note: this parent module imports and calls child modules only
// (child-to-parent imports miscompile on this compiler), so all base code
// lives in the sibling modules above.

module xiom.vault

use xiom.vault.core;
use xiom.vault.client;
use xiom.vault.kv;
use xiom.vault.auth;

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_req(v: VaultRequest) -> Result[VaultRequest, Str] {
  return Ok(v);
}

fn _err_req(m: Str) -> Result[VaultRequest, Str] {
  return Err(m);
}

// Attach the token header unless the token is empty (some endpoints are
// unauthenticated, e.g. sys/health and sys/seal-status).
fn _with_token(req: VaultRequest, token: Str) -> Result[VaultRequest, Str] {
  var r = req;
  if token.len() == 0 {
    return _ok_req(r);
  }
  let tr = client.vault_request_set_token(&mut r, token);
  if !tr.is_ok {
    return _err_req(tr.error);
  }
  return _ok_req(r);
}

// --------------------------------------------------
//  System endpoints
// --------------------------------------------------

/// Health request: GET /sys/health (unauthenticated; no token header).
/// Params: none. Returns: Ok(request).
/// Error case: the client request catalog.
/// Complexity: O(1).
pub fn vault_health_request() -> Result[VaultRequest, Str] {
  return client.vault_request_new(core.VAULT_METHOD_GET, "/sys/health");
}

/// Seal-status request: GET /sys/seal-status (unauthenticated).
/// Params: none. Returns: Ok(request).
/// Error case: the client request catalog.
/// Complexity: O(1).
pub fn vault_seal_status_request() -> Result[VaultRequest, Str] {
  return client.vault_request_new(core.VAULT_METHOD_GET, "/sys/seal-status");
}

/// List-mounts request: GET /sys/mounts with the token header when `token`
/// is non-empty.
/// Params: token - a client token or "".
/// Returns: Ok(request).
/// Error case: the client request catalog and the token catalog.
/// Complexity: O(token.len()).
pub fn vault_sys_mounts_request(token: Str) -> Result[VaultRequest, Str] {
  let rr = client.vault_request_new(core.VAULT_METHOD_GET, "/sys/mounts");
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  let req: VaultRequest = rr.value;
  return _with_token(req, token);
}

// --------------------------------------------------
//  KV v2 composed operations
// --------------------------------------------------

/// KV v2 read: GET <mount>/data/<key> with the optional version query and the
/// token header.
/// Params: mount - the KV mount segment; key - the secret key; version - 0
/// for latest, else 1..1000000; token - a client token or "".
/// Returns: Ok(request). Error case: the kv, client and token catalogs.
/// Complexity: O(mount.len() + key.len() + token.len()).
pub fn vault_kv2_read(mount: Str, key: Str, version: Int, token: Str) -> Result[VaultRequest, Str] {
  let rr = kv.vault_kv2_read_request(mount, key, version);
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  let req: VaultRequest = rr.value;
  return _with_token(req, token);
}

/// KV v2 write: POST <mount>/data/<key> with the secret body and the token
/// header.
/// Params: mount - the KV mount segment; key - the secret key; body - the
/// secret body builder; token - a client token or "".
/// Returns: Ok(request) with the rendered body attached.
/// Error case: the kv, client, body and token catalogs.
/// Complexity: O(mount.len() + key.len() + body size).
pub fn vault_kv2_write(mount: Str, key: Str, body: &VaultBody, token: Str) -> Result[VaultRequest, Str] {
  let rr = kv.vault_kv2_write_request(mount, key);
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  var req: VaultRequest = rr.value;
  let br = client.vault_request_set_body(&mut req, body);
  if !br.is_ok {
    return _err_req(br.error);
  }
  return _with_token(req, token);
}

/// KV v2 soft delete: POST <mount>/delete/<key>. An empty `versions` list
/// deletes the latest version (no body); a non-empty list attaches
/// {"versions":[...]} and deletes exactly those versions.
/// Params: mount - the KV mount segment; key - the secret key; versions -
/// version numbers (0..64 entries); token - a client token or "".
/// Returns: Ok(request).
/// Error case: the kv, versions-body, client and token catalogs.
/// Complexity: O(mount.len() + key.len() + versions count).
pub fn vault_kv2_soft_delete(mount: Str, key: Str, versions: &Vec[Int], token: Str) -> Result[VaultRequest, Str] {
  var rr = kv.vault_kv2_delete_request(mount, key);
  if versions.len() > 0 {
    rr = kv.vault_kv2_delete_versions_request(mount, key, versions);
  }
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  let req: VaultRequest = rr.value;
  return _with_token(req, token);
}

/// KV v2 undelete: POST <mount>/undelete/<key>. An empty `versions` list
/// targets the latest version (no body); a non-empty list attaches
/// {"versions":[...]}.
/// Params: mount - the KV mount segment; key - the secret key; versions -
/// version numbers (0..64 entries); token - a client token or "".
/// Returns: Ok(request).
/// Error case: the kv, versions-body, client and token catalogs.
/// Complexity: O(mount.len() + key.len() + versions count).
pub fn vault_kv2_undelete(mount: Str, key: Str, versions: &Vec[Int], token: Str) -> Result[VaultRequest, Str] {
  var rr = kv.vault_kv2_undelete_request(mount, key);
  if versions.len() > 0 {
    rr = kv.vault_kv2_undelete_versions_request(mount, key, versions);
  }
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  let req: VaultRequest = rr.value;
  return _with_token(req, token);
}

/// KV v2 destroy: PUT <mount>/destroy/<key> (irreversible). An empty
/// `versions` list targets the latest version (no body); a non-empty list
/// attaches {"versions":[...]}.
/// Params: mount - the KV mount segment; key - the secret key; versions -
/// version numbers (0..64 entries); token - a client token or "".
/// Returns: Ok(request).
/// Error case: the kv, versions-body, client and token catalogs.
/// Complexity: O(mount.len() + key.len() + versions count).
pub fn vault_kv2_destroy(mount: Str, key: Str, versions: &Vec[Int], token: Str) -> Result[VaultRequest, Str] {
  var rr = kv.vault_kv2_destroy_request(mount, key);
  if versions.len() > 0 {
    rr = kv.vault_kv2_destroy_versions_request(mount, key, versions);
  }
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  let req: VaultRequest = rr.value;
  return _with_token(req, token);
}

// --------------------------------------------------
//  Auth composed operations
// --------------------------------------------------

/// AppRole login: POST auth/<mount>/login with the role_id/secret_id body.
/// Params: mount - the AppRole mount segment; role_id - the role UUID;
/// secret_id - the secret UUID.
/// Returns: Ok(request).
/// Error case: the auth and client catalogs.
/// Complexity: O(mount.len()).
pub fn vault_approle_login(mount: Str, role_id: Str, secret_id: Str) -> Result[VaultRequest, Str] {
  return auth.vault_approle_login_request(mount, role_id, secret_id);
}

/// Token lookup: GET auth/token/lookup-self with the token header.
/// Params: token - the client token.
/// Returns: Ok(request). Error case: the auth and client catalogs.
/// Complexity: O(token.len()).
pub fn vault_token_lookup(token: Str) -> Result[VaultRequest, Str] {
  return auth.vault_token_lookup_request(token);
}

/// Token renew: PUT auth/token/renew-self with the token header and the
/// optional {"increment":N} body.
/// Params: token - the client token; increment - 0 or 1..31536000 seconds.
/// Returns: Ok(request). Error case: the auth and client catalogs.
/// Complexity: O(token.len()).
pub fn vault_token_renew(token: Str, increment: Int) -> Result[VaultRequest, Str] {
  return auth.vault_token_renew_request(token, increment);
}
