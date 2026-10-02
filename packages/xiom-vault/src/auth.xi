// XIOM -- xiom.vault.auth: token and AppRole login models
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM MODEL of vault authentication:
//
//   * Token responses: parse a client token payload (client_token, accessor,
//     token_type, policies, lease_duration, renewable, entity_id) out of a
//     JSON response body, with the module's own error when client_token is
//     missing or empty. Policy membership and root detection are helpers.
//   * Token lifecycle requests: lookup-self (GET), renew-self (PUT, optional
//     {"increment":N} body) and revoke-self (POST), each carrying the
//     X-Vault-Token header.
//   * AppRole login: mount path "auth/<mount>/login", UUID-shaped role_id and
//     secret_id validation, the {"role_id":"..","secret_id":".."} login body,
//     and parsing the nested "auth" object of the login response into a
//     VaultToken.
//
// No HTTP, no crypto, no token generation or lease arithmetic: durations are
// carried as integers and everything is deterministic.
//
// v0.62.2 notes: free functions only; Ok/Err only in the `_ok_*`/`_err_*`
// leaves; bytes widened with `(x as Int) & 0xFF`; Str equality through
// core.vault_str_eq / core.vault_str_eq_ci (never `==`); optional fields are
// probed with vault_json_lookup so an absent key defaults and a malformed one
// errors.

module xiom.vault.auth

use xiom.vault.core;
use xiom.vault.client;
use xiom.vault.json;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Default (built-in) policy name.
pub const VAULT_DEFAULT_POLICY: Str = "default";

/// The root policy name.
pub const VAULT_ROOT_POLICY: Str = "root";

/// Maximum token renew increment accepted (31536000 = 365 days, seconds).
pub const VAULT_MAX_RENEW_INCREMENT: Int = 31536000;

// --------------------------------------------------
//  Public data model
// --------------------------------------------------

/// A parsed token payload. Optional fields are "" / 0 / false when absent.
pub type VaultToken = {
  client_token: Str;
  accessor: Str;
  token_type: Str;
  policies: Vec[Str];
  lease_duration: Int;
  renewable: Bool;
  entity_id: Str;
}

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_token(v: VaultToken) -> Result[VaultToken, Str] {
  return Ok(v);
}

fn _err_token(m: Str) -> Result[VaultToken, Str] {
  return Err(m);
}

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

fn _ok_req(v: VaultRequest) -> Result[VaultRequest, Str] {
  return Ok(v);
}

fn _err_req(m: Str) -> Result[VaultRequest, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Optional-field readers (absent -> default, malformed -> error)
// --------------------------------------------------

// Optional string member: default when the key is absent, the getter's error
// when it is present with the wrong kind or bad escapes.
fn _opt_str(text: Str, key: Str, dflt: Str) -> Result[Str, Str] {
  let h = json.vault_json_lookup(text, key);
  if !h.is_ok {
    return _ok_str(dflt);
  }
  return json.vault_json_get_str(text, key);
}

// Optional integer member (absent -> 0).
fn _opt_int(text: Str, key: Str) -> Result[Int, Str] {
  let h = json.vault_json_lookup(text, key);
  if !h.is_ok {
    return _ok_int(0);
  }
  return json.vault_json_get_int(text, key);
}

// Optional boolean member (absent -> false).
fn _opt_bool(text: Str, key: Str) -> Result[Bool, Str] {
  let h = json.vault_json_lookup(text, key);
  if !h.is_ok {
    return _ok_bool(false);
  }
  return json.vault_json_get_bool(text, key);
}

// --------------------------------------------------
//  Token response parsing
// --------------------------------------------------

/// Parse a token payload. `client_token` must be present and non-empty;
/// accessor, token_type and entity_id default to "", lease_duration to 0,
/// renewable to false and policies to the empty list. Mismatched or malformed
/// present fields are errors.
/// Params: text - the JSON response body (flat object).
/// Returns: Ok(token).
/// Error case: Err("vault: token response missing client_token"),
/// Err("vault: token response has empty client_token"), the JSON scanner
/// catalog and the getters' kind errors.
/// Complexity: O(text.len()).
pub fn vault_token_parse(text: Str) -> Result[VaultToken, Str] {
  let h = json.vault_json_lookup(text, "client_token");
  if !h.is_ok {
    return _err_token(core.vault_err("token response missing client_token"));
  }
  let cr = json.vault_json_get_str(text, "client_token");
  if !cr.is_ok {
    return _err_token(cr.error);
  }
  let ct: Str = cr.value;
  if ct.len() == 0 {
    return _err_token(core.vault_err("token response has empty client_token"));
  }
  let ar = _opt_str(text, "accessor", "");
  if !ar.is_ok {
    return _err_token(ar.error);
  }
  let tr = _opt_str(text, "token_type", "");
  if !tr.is_ok {
    return _err_token(tr.error);
  }
  let er = _opt_str(text, "entity_id", "");
  if !er.is_ok {
    return _err_token(er.error);
  }
  let lr = _opt_int(text, "lease_duration");
  if !lr.is_ok {
    return _err_token(lr.error);
  }
  let rn = _opt_bool(text, "renewable");
  if !rn.is_ok {
    return _err_token(rn.error);
  }
  var policies = Vec[Str].new();
  let ph = json.vault_json_lookup(text, "policies");
  if ph.is_ok {
    let pv = json.vault_json_strs_at(text, &ph.value);
    if !pv.is_ok {
      return _err_token(pv.error);
    }
    policies = pv.value;
  }
  let accessor: Str = ar.value;
  let token_type: Str = tr.value;
  let entity_id: Str = er.value;
  let lease_duration: Int = lr.value;
  let renewable: Bool = rn.value;
  return _ok_token(VaultToken{
    client_token: ct;
    accessor: accessor;
    token_type: token_type;
    policies: policies;
    lease_duration: lease_duration;
    renewable: renewable;
    entity_id: entity_id
  });
}

/// True when the token carries the named policy (case-insensitive).
/// Params: t - the token; name - the policy name.
/// Returns: the predicate. Error case: none. Complexity: O(policy count).
pub fn vault_token_has_policy(t: &VaultToken, name: Str) -> Bool {
  var i = 0;
  while i < t.policies.len() {
    let cur: Str = t.policies[i];
    if core.vault_str_eq_ci(cur, name) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// True when the token carries the root policy.
/// Params: t - the token. Returns: the predicate.
/// Error case: none. Complexity: O(policy count).
pub fn vault_token_is_root(t: &VaultToken) -> Bool {
  return vault_token_has_policy(t, VAULT_ROOT_POLICY);
}

/// The built-in default policy name ("default").
/// Params: none. Returns: "default". Error case: none. Complexity: O(1).
pub fn vault_token_default_policy() -> Str {
  return VAULT_DEFAULT_POLICY;
}

// --------------------------------------------------
//  Token lifecycle requests
// --------------------------------------------------

/// Build the token lookup request: GET auth/token/lookup-self with the token
/// header.
/// Params: token - the client token.
/// Returns: Ok(request).
/// Error case: Err("vault: token is empty") and the token control-byte error
/// from the client, plus the client request catalog.
/// Complexity: O(token.len()).
pub fn vault_token_lookup_request(token: Str) -> Result[VaultRequest, Str] {
  let rr = client.vault_request_new(core.VAULT_METHOD_GET, "auth/token/lookup-self");
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  var req: VaultRequest = rr.value;
  let tr = client.vault_request_set_token(&mut req, token);
  if !tr.is_ok {
    return _err_req(tr.error);
  }
  return _ok_req(req);
}

/// Build the token renew request: PUT auth/token/renew-self with the token
/// header. `increment` 0 renews for the default lease (no body);
/// 1..31536000 attaches {"increment":N} seconds.
/// Params: token - the client token; increment - the requested lease
/// extension in seconds.
/// Returns: Ok(request).
/// Error case: Err("vault: token is empty"), the client token catalog,
/// Err("vault: token renew increment out of range: N") and the client body
/// catalog.
/// Complexity: O(token.len()).
pub fn vault_token_renew_request(token: Str, increment: Int) -> Result[VaultRequest, Str] {
  if increment < 0 || increment > VAULT_MAX_RENEW_INCREMENT {
    return _err_req(core.vault_err("token renew increment out of range: " + core.vault_int_str(increment)));
  }
  let rr = client.vault_request_new(core.VAULT_METHOD_PUT, "auth/token/renew-self");
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  var req: VaultRequest = rr.value;
  let tr = client.vault_request_set_token(&mut req, token);
  if !tr.is_ok {
    return _err_req(tr.error);
  }
  if increment > 0 {
    var b = client.vault_body_new();
    let br = client.vault_body_add_int(&mut b, "increment", increment);
    if !br.is_ok {
      return _err_req(br.error);
    }
    let sr = client.vault_request_set_body(&mut req, &b);
    if !sr.is_ok {
      return _err_req(sr.error);
    }
  }
  return _ok_req(req);
}

/// Build the token revoke request: POST auth/token/revoke-self with the token
/// header.
/// Params: token - the client token.
/// Returns: Ok(request).
/// Error case: Err("vault: token is empty") and the client token catalog.
/// Complexity: O(token.len()).
pub fn vault_token_revoke_request(token: Str) -> Result[VaultRequest, Str] {
  let rr = client.vault_request_new(core.VAULT_METHOD_POST, "auth/token/revoke-self");
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  var req: VaultRequest = rr.value;
  let tr = client.vault_request_set_token(&mut req, token);
  if !tr.is_ok {
    return _err_req(tr.error);
  }
  return _ok_req(req);
}

// --------------------------------------------------
//  AppRole
// --------------------------------------------------

// True when `s` is a mount segment: 1..64 bytes of [A-Za-z0-9_-].
fn _mount_ok(s: Str) -> Bool {
  let n = s.len();
  if n == 0 || n > 64 {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.vault_byte(s, i);
    var ok = false;
    if c >= 65 && c <= 90 {
      ok = true;
    }
    if c >= 97 && c <= 122 {
      ok = true;
    }
    if c >= 48 && c <= 57 {
      ok = true;
    }
    if c == 95 || c == 45 {
      ok = true;
    }
    if !ok {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `s` has the canonical UUID shape 8-4-4-4-12 (hex, any case).
fn _uuid_ok(s: Str) -> Bool {
  if s.len() != 36 {
    return false;
  }
  var i = 0;
  while i < 36 {
    let c = core.vault_byte(s, i);
    if i == 8 || i == 13 || i == 18 || i == 23 {
      if c != 45 {
        return false;
      }
    } else {
      var hexd = false;
      if c >= 48 && c <= 57 {
        hexd = true;
      }
      if c >= 97 && c <= 102 {
        hexd = true;
      }
      if c >= 65 && c <= 70 {
        hexd = true;
      }
      if !hexd {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

/// True when `id` has the canonical UUID shape used by AppRole role IDs.
/// Params: id - the candidate role_id. Returns: the predicate.
/// Error case: none. Complexity: O(id.len()).
pub fn vault_approle_role_id_is_valid(id: Str) -> Bool {
  return _uuid_ok(id);
}

/// True when `id` has the canonical UUID shape used by AppRole secret IDs.
/// Params: id - the candidate secret_id. Returns: the predicate.
/// Error case: none. Complexity: O(id.len()).
pub fn vault_approle_secret_id_is_valid(id: Str) -> Bool {
  return _uuid_ok(id);
}

/// AppRole login API path "auth/<mount>/login".
/// Params: mount - the AppRole mount segment (usually "approle").
/// Returns: Ok(path).
/// Error case: Err("vault: approle mount is empty or invalid").
/// Complexity: O(mount.len()).
pub fn vault_approle_login_path(mount: Str) -> Result[Str, Str] {
  if !_mount_ok(mount) {
    return _err_str(core.vault_err("approle mount is empty or invalid"));
  }
  return _ok_str(("auth/" + mount) + "/login");
}

/// Build the AppRole login request: POST auth/<mount>/login with
/// {"role_id":"..","secret_id":".."}. Both IDs must have the UUID shape.
/// Params: mount - the AppRole mount segment; role_id - the role UUID;
/// secret_id - the secret UUID.
/// Returns: Ok(request) with the login body attached.
/// Error case: Err("vault: approle mount is empty or invalid"),
/// Err("vault: approle role_id is not a UUID"),
/// Err("vault: approle secret_id is not a UUID"), the client request catalog
/// and the client body catalog.
/// Complexity: O(mount.len()).
pub fn vault_approle_login_request(mount: Str, role_id: Str, secret_id: Str) -> Result[VaultRequest, Str] {
  let pr = vault_approle_login_path(mount);
  if !pr.is_ok {
    return _err_req(pr.error);
  }
  if !vault_approle_role_id_is_valid(role_id) {
    return _err_req(core.vault_err("approle role_id is not a UUID"));
  }
  if !vault_approle_secret_id_is_valid(secret_id) {
    return _err_req(core.vault_err("approle secret_id is not a UUID"));
  }
  let path: Str = pr.value;
  let rr = client.vault_request_new(core.VAULT_METHOD_POST, path);
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  var req: VaultRequest = rr.value;
  var b = client.vault_body_new();
  let b1 = client.vault_body_add_str(&mut b, "role_id", role_id);
  if !b1.is_ok {
    return _err_req(b1.error);
  }
  let b2 = client.vault_body_add_str(&mut b, "secret_id", secret_id);
  if !b2.is_ok {
    return _err_req(b2.error);
  }
  let sr = client.vault_request_set_body(&mut req, &b);
  if !sr.is_ok {
    return _err_req(sr.error);
  }
  return _ok_req(req);
}

/// Parse an AppRole login response: the nested "auth" object is extracted and
/// parsed as a token payload.
/// Params: text - the login JSON response body.
/// Returns: Ok(token).
/// Error case: Err("vault: approle login response missing auth"),
/// Err("vault: approle login response auth is not an object"), the JSON
/// scanner catalog and the vault_token_parse catalog.
/// Complexity: O(text.len()).
pub fn vault_approle_parse_login(text: Str) -> Result[VaultToken, Str] {
  let hr = json.vault_json_lookup(text, "auth");
  if !hr.is_ok {
    return _err_token(core.vault_err("approle login response missing auth"));
  }
  let h: VaultJsonHit = hr.value;
  if h.kind != json.VAULT_JSON_OBJECT {
    return _err_token(core.vault_err("approle login response auth is not an object"));
  }
  let rawr = json.vault_json_get_raw(text, "auth");
  if !rawr.is_ok {
    return _err_token(rawr.error);
  }
  let raw: Str = rawr.value;
  return vault_token_parse(raw);
}
