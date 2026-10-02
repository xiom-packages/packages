// XIOM -- xiom.vault.kv: KV secrets engine paths, versions and state model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM MODEL of a KV secrets engine mount:
//
//   * KV v1 paths: "<mount>/<key>".
//   * KV v2 paths: "<mount>/data/<key>" (read / write the secret),
//     "<mount>/metadata/<key>" (version metadata), "<mount>/delete/<key>"
//     (soft delete), "<mount>/undelete/<key>" and "<mount>/destroy/<key>"
//     (permanent destruction).
//   * Version selection: the v2 read query "version=N" (N >= 1; absent means
//     latest) and the "{"versions":[...]}" request body used by
//     delete/undelete/destroy.
//   * A per-version STATE LEDGER for the v2 soft-delete model with the
//     transitions Vault allows: absent -> live (write), live -> soft-deleted
//     (delete), soft-deleted -> live (undelete), live/soft-deleted ->
//     destroyed (destroy, irreversible). Reads require the live state.
//     Destroyed slots can never be written or read again. Delete/undelete on
//     an already soft-deleted/live slot are idempotent; destroy on an already
//     destroyed slot is idempotent. Every other transition is an error.
//   * Request builders (GET/POST/PUT) for the v2 operations, layered on
//     `xiom.vault.client`.
//
// The model is a documented simplification of the real Vault v2 semantics:
// the ledger is slot-based (one slot per version number) rather than an
// append-only journal, and a write to an existing live slot overwrites it.
//
// Mounts are single path segments of [A-Za-z0-9_-] (1..64 bytes); keys are
// 1..512 byte '/'-separated non-empty segments of [A-Za-z0-9_.-].
//
// v0.62.2 notes: free functions only; Ok/Err only in the `_ok_*`/`_err_*`
// leaves; bytes widened with `(x as Int) & 0xFF`; Str equality through
// core.vault_str_eq (never `==`); every cloned vector is rebuilt explicitly
// so the input ledger is never aliased.

module xiom.vault.kv

use xiom.vault.core;
use xiom.vault.client;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// KV v2 request op: read the secret (1).
pub const VAULT_KV2_READ: Int = 1;

/// KV v2 request op: write the secret (2).
pub const VAULT_KV2_WRITE: Int = 2;

/// KV v2 request op: read version metadata (3).
pub const VAULT_KV2_METADATA: Int = 3;

/// KV v2 request op: soft delete (4).
pub const VAULT_KV2_DELETE: Int = 4;

/// KV v2 request op: undelete (5).
pub const VAULT_KV2_UNDELETE: Int = 5;

/// KV v2 request op: destroy (6).
pub const VAULT_KV2_DESTROY: Int = 6;

/// KV version state: the slot has never been written (0).
pub const VAULT_KV_ABSENT: Int = 0;

/// KV version state: the version exists and is readable (1).
pub const VAULT_KV_LIVE: Int = 1;

/// KV version state: soft-deleted, data retained, recoverable (2).
pub const VAULT_KV_SOFT_DELETED: Int = 2;

/// KV version state: destroyed, data gone, irreversible (3).
pub const VAULT_KV_DESTROYED: Int = 3;

/// KV ledger op: write the version (1).
pub const VAULT_KV_OP_WRITE: Int = 1;

/// KV ledger op: read the version, no state change (2).
pub const VAULT_KV_OP_READ: Int = 2;

/// KV ledger op: soft delete the version (3).
pub const VAULT_KV_OP_DELETE: Int = 3;

/// KV ledger op: undelete the version (4).
pub const VAULT_KV_OP_UNDELETE: Int = 4;

/// KV ledger op: destroy the version (5).
pub const VAULT_KV_OP_DESTROY: Int = 5;

/// Maximum number of versions accepted in one versions body (64).
pub const VAULT_KV_MAX_BATCH: Int = 64;

/// Maximum version number accepted (1000000).
pub const VAULT_KV_MAX_VERSION: Int = 1000000;

// --------------------------------------------------
//  Public data model
// --------------------------------------------------

/// A slot-based KV v2 version ledger. `states[i]` is the state of version
/// i + 1 (VAULT_KV_ABSENT / LIVE / SOFT_DELETED / DESTROYED).
pub type VaultKvVersions = {
  states: Vec[Int];
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

fn _ok_kv(v: VaultKvVersions) -> Result[VaultKvVersions, Str] {
  return Ok(v);
}

fn _err_kv(m: Str) -> Result[VaultKvVersions, Str] {
  return Err(m);
}

fn _ok_req(v: VaultRequest) -> Result[VaultRequest, Str] {
  return Ok(v);
}

fn _err_req(m: Str) -> Result[VaultRequest, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Name validation and path joining
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

// True when `s` is a secret key: 1..512 bytes, '/'-separated non-empty
// segments of [A-Za-z0-9_.-], no leading or trailing '/'.
fn _key_ok(s: Str) -> Bool {
  let n = s.len();
  if n == 0 || n > 512 {
    return false;
  }
  if core.vault_byte(s, 0) == 47 {
    return false;
  }
  if core.vault_byte(s, n - 1) == 47 {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.vault_byte(s, i);
    if c == 47 {
      if i == 0 || core.vault_byte(s, i - 1) == 47 {
        return false;
      }
      i = i + 1;
    } else {
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
      if c == 95 || c == 45 || c == 46 {
        ok = true;
      }
      if !ok {
        return false;
      }
      i = i + 1;
    }
  }
  return true;
}

// "<mount>/<mid><key>" with validation; `mid` is "" (v1) or "data/" etc.
fn _join(mount: Str, mid: Str, key: Str) -> Result[Str, Str] {
  if !_mount_ok(mount) {
    return _err_str(core.vault_err("kv mount is empty or invalid"));
  }
  if !_key_ok(key) {
    return _err_str(core.vault_err("kv key is empty or invalid"));
  }
  return _ok_str(((mount + "/") + mid) + key);
}

// --------------------------------------------------
//  Path builders
// --------------------------------------------------

/// KV v1 path "<mount>/<key>".
/// Params: mount - the mount segment; key - the secret key.
/// Returns: Ok(path).
/// Error case: Err("vault: kv mount is empty or invalid") or
/// Err("vault: kv key is empty or invalid").
/// Complexity: O(mount.len() + key.len()).
pub fn vault_kv1_path(mount: Str, key: Str) -> Result[Str, Str] {
  return _join(mount, "", key);
}

/// KV v2 data path "<mount>/data/<key>" (read and write the secret).
/// Params: mount - the mount segment; key - the secret key.
/// Returns: Ok(path). Error case: the _join catalog.
/// Complexity: O(mount.len() + key.len()).
pub fn vault_kv2_data_path(mount: Str, key: Str) -> Result[Str, Str] {
  return _join(mount, "data/", key);
}

/// KV v2 metadata path "<mount>/metadata/<key>".
/// Params: mount - the mount segment; key - the secret key.
/// Returns: Ok(path). Error case: the _join catalog.
/// Complexity: O(mount.len() + key.len()).
pub fn vault_kv2_metadata_path(mount: Str, key: Str) -> Result[Str, Str] {
  return _join(mount, "metadata/", key);
}

/// KV v2 soft-delete path "<mount>/delete/<key>".
/// Params: mount - the mount segment; key - the secret key.
/// Returns: Ok(path). Error case: the _join catalog.
/// Complexity: O(mount.len() + key.len()).
pub fn vault_kv2_delete_path(mount: Str, key: Str) -> Result[Str, Str] {
  return _join(mount, "delete/", key);
}

/// KV v2 undelete path "<mount>/undelete/<key>".
/// Params: mount - the mount segment; key - the secret key.
/// Returns: Ok(path). Error case: the _join catalog.
/// Complexity: O(mount.len() + key.len()).
pub fn vault_kv2_undelete_path(mount: Str, key: Str) -> Result[Str, Str] {
  return _join(mount, "undelete/", key);
}

/// KV v2 destroy path "<mount>/destroy/<key>".
/// Params: mount - the mount segment; key - the secret key.
/// Returns: Ok(path). Error case: the _join catalog.
/// Complexity: O(mount.len() + key.len()).
pub fn vault_kv2_destroy_path(mount: Str, key: Str) -> Result[Str, Str] {
  return _join(mount, "destroy/", key);
}

// --------------------------------------------------
//  Version query and versions body
// --------------------------------------------------

/// KV v2 version query parameter "version=N" (without the leading '?').
/// Params: version - a version number in 1..1000000.
/// Returns: Ok("version=N").
/// Error case: Err("vault: kv version out of range: N").
/// Complexity: O(digits).
pub fn vault_kv2_version_query(version: Int) -> Result[Str, Str] {
  if version < 1 || version > VAULT_KV_MAX_VERSION {
    return _err_str(core.vault_err("kv version out of range: " + core.vault_int_str(version)));
  }
  return _ok_str("version=" + core.vault_int_str(version));
}

/// Build the KV v2 versions request body {"versions":[v,...]} with 1..64
/// version numbers, each in 1..1000000. Duplicates are preserved.
/// Params: versions - the version numbers.
/// Returns: Ok(rendered JSON text).
/// Error case: Err("vault: kv versions list is empty"),
/// Err("vault: kv versions list is too long"),
/// Err("vault: kv version out of range: N").
/// Complexity: O(versions count * digits).
pub fn vault_kv2_versions_body(versions: &Vec[Int]) -> Result[Str, Str] {
  let cnt = versions.len();
  if cnt == 0 {
    return _err_str(core.vault_err("kv versions list is empty"));
  }
  if cnt > VAULT_KV_MAX_BATCH {
    return _err_str(core.vault_err("kv versions list is too long"));
  }
  var i = 0;
  while i < cnt {
    let v: Int = versions[i];
    if v < 1 || v > VAULT_KV_MAX_VERSION {
      return _err_str(core.vault_err("kv version out of range: " + core.vault_int_str(v)));
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "{\"versions\":[");
  i = 0;
  while i < cnt {
    if i > 0 {
      out.push(44 as UInt8);
    }
    let v2: Int = versions[i];
    builder.sb_push_int(&mut out, v2);
    i = i + 1;
  }
  builder.sb_push_str(&mut out, "]}");
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  KV v2 request builders
// --------------------------------------------------

/// KV v2 read request: GET <mount>/data/<key>, with the "version=N" query
/// when `version` > 0 (0 means latest).
/// Params: mount - the mount segment; key - the secret key; version - 0 for
/// latest, else 1..1000000.
/// Returns: Ok(request).
/// Error case: the path catalog, Err("vault: kv version out of range: N")
/// and the client request catalog.
/// Complexity: O(mount.len() + key.len()).
pub fn vault_kv2_read_request(mount: Str, key: Str, version: Int) -> Result[VaultRequest, Str] {
  if version < 0 {
    return _err_req(core.vault_err("kv version out of range: " + core.vault_int_str(version)));
  }
  let pr = vault_kv2_data_path(mount, key);
  if !pr.is_ok {
    return _err_req(pr.error);
  }
  let path: Str = pr.value;
  let rr = client.vault_request_new(core.VAULT_METHOD_GET, path);
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  var req: VaultRequest = rr.value;
  if version > 0 {
    let qr = vault_kv2_version_query(version);
    if !qr.is_ok {
      return _err_req(qr.error);
    }
    let q: Str = qr.value;
    let sr = client.vault_request_set_query(&mut req, q);
    if !sr.is_ok {
      return _err_req(sr.error);
    }
  }
  return _ok_req(req);
}

/// KV v2 write request: POST <mount>/data/<key>; attach the secret with the
/// body builder before sending.
/// Params: mount - the mount segment; key - the secret key.
/// Returns: Ok(request). Error case: the path and client catalogs.
/// Complexity: O(mount.len() + key.len()).
pub fn vault_kv2_write_request(mount: Str, key: Str) -> Result[VaultRequest, Str] {
  let pr = vault_kv2_data_path(mount, key);
  if !pr.is_ok {
    return _err_req(pr.error);
  }
  let path: Str = pr.value;
  return client.vault_request_new(core.VAULT_METHOD_POST, path);
}

/// KV v2 metadata request: GET <mount>/metadata/<key>.
/// Params: mount - the mount segment; key - the secret key.
/// Returns: Ok(request). Error case: the path and client catalogs.
/// Complexity: O(mount.len() + key.len()).
pub fn vault_kv2_metadata_request(mount: Str, key: Str) -> Result[VaultRequest, Str] {
  let pr = vault_kv2_metadata_path(mount, key);
  if !pr.is_ok {
    return _err_req(pr.error);
  }
  let path: Str = pr.value;
  return client.vault_request_new(core.VAULT_METHOD_GET, path);
}

/// KV v2 soft-delete request: POST <mount>/delete/<key>; without a body it
/// soft-deletes the latest version, with vault_kv2_versions_body it deletes
/// exactly the listed versions.
/// Params: mount - the mount segment; key - the secret key.
/// Returns: Ok(request). Error case: the path and client catalogs.
/// Complexity: O(mount.len() + key.len()).
pub fn vault_kv2_delete_request(mount: Str, key: Str) -> Result[VaultRequest, Str] {
  let pr = vault_kv2_delete_path(mount, key);
  if !pr.is_ok {
    return _err_req(pr.error);
  }
  let path: Str = pr.value;
  return client.vault_request_new(core.VAULT_METHOD_POST, path);
}

/// KV v2 undelete request: POST <mount>/undelete/<key>.
/// Params: mount - the mount segment; key - the secret key.
/// Returns: Ok(request). Error case: the path and client catalogs.
/// Complexity: O(mount.len() + key.len()).
pub fn vault_kv2_undelete_request(mount: Str, key: Str) -> Result[VaultRequest, Str] {
  let pr = vault_kv2_undelete_path(mount, key);
  if !pr.is_ok {
    return _err_req(pr.error);
  }
  let path: Str = pr.value;
  return client.vault_request_new(core.VAULT_METHOD_POST, path);
}

/// KV v2 destroy request: PUT <mount>/destroy/<key> (irreversible).
/// Params: mount - the mount segment; key - the secret key.
/// Returns: Ok(request). Error case: the path and client catalogs.
/// Complexity: O(mount.len() + key.len()).
pub fn vault_kv2_destroy_request(mount: Str, key: Str) -> Result[VaultRequest, Str] {
  let pr = vault_kv2_destroy_path(mount, key);
  if !pr.is_ok {
    return _err_req(pr.error);
  }
  let path: Str = pr.value;
  return client.vault_request_new(core.VAULT_METHOD_PUT, path);
}

/// KV v2 delete request with an explicit version list body.
/// Params: mount - the mount segment; key - the secret key; versions - the
/// version numbers to soft-delete.
/// Returns: Ok(request) with {"versions":[...]} attached.
/// Error case: the path catalog, the versions-body catalog and
/// Err("vault: body text is empty") / control-byte errors from the client.
/// Complexity: O(mount.len() + key.len() + versions count).
pub fn vault_kv2_delete_versions_request(mount: Str, key: Str, versions: &Vec[Int]) -> Result[VaultRequest, Str] {
  let rr = vault_kv2_delete_request(mount, key);
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  var req: VaultRequest = rr.value;
  let br = vault_kv2_versions_body(versions);
  if !br.is_ok {
    return _err_req(br.error);
  }
  let body: Str = br.value;
  let sr = client.vault_request_set_body_text(&mut req, body);
  if !sr.is_ok {
    return _err_req(sr.error);
  }
  return _ok_req(req);
}

/// KV v2 undelete request with an explicit version list body.
/// Params: mount - the mount segment; key - the secret key; versions - the
/// version numbers to undelete.
/// Returns: Ok(request) with {"versions":[...]} attached.
/// Error case: the path catalog, the versions-body catalog and the client
/// body-text catalog.
/// Complexity: O(mount.len() + key.len() + versions count).
pub fn vault_kv2_undelete_versions_request(mount: Str, key: Str, versions: &Vec[Int]) -> Result[VaultRequest, Str] {
  let rr = vault_kv2_undelete_request(mount, key);
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  var req: VaultRequest = rr.value;
  let br = vault_kv2_versions_body(versions);
  if !br.is_ok {
    return _err_req(br.error);
  }
  let body: Str = br.value;
  let sr = client.vault_request_set_body_text(&mut req, body);
  if !sr.is_ok {
    return _err_req(sr.error);
  }
  return _ok_req(req);
}

/// KV v2 destroy request with an explicit version list body.
/// Params: mount - the mount segment; key - the secret key; versions - the
/// version numbers to destroy.
/// Returns: Ok(request) with {"versions":[...]} attached.
/// Error case: the path catalog, the versions-body catalog and the client
/// body-text catalog.
/// Complexity: O(mount.len() + key.len() + versions count).
pub fn vault_kv2_destroy_versions_request(mount: Str, key: Str, versions: &Vec[Int]) -> Result[VaultRequest, Str] {
  let rr = vault_kv2_destroy_request(mount, key);
  if !rr.is_ok {
    return _err_req(rr.error);
  }
  var req: VaultRequest = rr.value;
  let br = vault_kv2_versions_body(versions);
  if !br.is_ok {
    return _err_req(br.error);
  }
  let body: Str = br.value;
  let sr = client.vault_request_set_body_text(&mut req, body);
  if !sr.is_ok {
    return _err_req(sr.error);
  }
  return _ok_req(req);
}

// --------------------------------------------------
//  Version state ledger
// --------------------------------------------------

/// Create a ledger with `version_count` absent slots (1..256).
/// Params: version_count - the number of version slots.
/// Returns: Ok(ledger). Error case: Err("vault: kv version count out of
/// range: N").
/// Complexity: O(version_count).
pub fn vault_kv_versions_new(version_count: Int) -> Result[VaultKvVersions, Str] {
  if version_count < 1 || version_count > core.VAULT_MAX_KV_VERSIONS {
    return _err_kv(core.vault_err("kv version count out of range: " + core.vault_int_str(version_count)));
  }
  var states = Vec[Int].new();
  var i = 0;
  while i < version_count {
    states.push(VAULT_KV_ABSENT);
    i = i + 1;
  }
  return _ok_kv(VaultKvVersions{ states: states });
}

/// State of version `version` in the ledger; -1 when the version number is
/// out of the ledger's range.
/// Params: v - the ledger; version - a 1-based version number.
/// Returns: the state code or -1. Error case: none. Complexity: O(1).
pub fn vault_kv_versions_state(v: &VaultKvVersions, version: Int) -> Int {
  if version < 1 || version > v.states.len() {
    return -1;
  }
  let s: Int = v.states[version - 1];
  return s;
}

/// Human-readable name of a version state ("absent", "live",
/// "soft-deleted", "destroyed"; "" for an unknown code).
/// Params: state - a state code. Returns: the name.
/// Error case: none. Complexity: O(1).
pub fn vault_kv_state_name(state: Int) -> Str {
  if state == VAULT_KV_ABSENT {
    return "absent";
  }
  if state == VAULT_KV_LIVE {
    return "live";
  }
  if state == VAULT_KV_SOFT_DELETED {
    return "soft-deleted";
  }
  if state == VAULT_KV_DESTROYED {
    return "destroyed";
  }
  return "";
}

/// True when version `version` exists and is readable (state live).
/// Params: v - the ledger; version - a 1-based version number.
/// Returns: the predicate. Error case: none. Complexity: O(1).
pub fn vault_kv_can_read(v: &VaultKvVersions, version: Int) -> Bool {
  let s = vault_kv_versions_state(v, version);
  if s == VAULT_KV_LIVE {
    return true;
  }
  return false;
}

// Copy the state vector (never alias the input ledger).
fn _copy_states(v: &VaultKvVersions) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.states.len() {
    let s: Int = v.states[i];
    out.push(s);
    i = i + 1;
  }
  return out;
}

/// Apply a ledger operation to `version` and return the resulting ledger
/// (the input is never mutated). Ops and rules:
///   * WRITE: absent -> live, live -> live (overwrite), soft-deleted -> live
///     (revive); destroyed -> error.
///   * READ: state must be live; the ledger is returned unchanged.
///   * DELETE (soft): live -> soft-deleted; soft-deleted -> soft-deleted
///     (idempotent); absent or destroyed -> error.
///   * UNDELETE: soft-deleted -> live; live -> live (idempotent); absent or
///     destroyed -> error.
///   * DESTROY: live or soft-deleted -> destroyed; destroyed -> destroyed
///     (idempotent); absent -> error.
/// Params: v - the ledger; op - a VAULT_KV_OP_* code; version - a 1-based
/// version number inside the ledger.
/// Returns: Ok(new ledger).
/// Error case: Err("vault: kv unknown op: N"),
/// Err("vault: kv version out of range: N"),
/// Err("vault: kv version N is destroyed"),
/// Err("vault: kv version N is absent"),
/// Err("vault: kv version N is deleted"),
/// Err("vault: kv version N is not deleted"),
/// Err("vault: kv version N is not live").
/// Complexity: O(version count).
pub fn vault_kv_versions_apply(v: &VaultKvVersions, op: Int, version: Int) -> Result[VaultKvVersions, Str] {
  if op < VAULT_KV_OP_WRITE || op > VAULT_KV_OP_DESTROY {
    return _err_kv(core.vault_err("kv unknown op: " + core.vault_int_str(op)));
  }
  if version < 1 || version > v.states.len() {
    return _err_kv(core.vault_err("kv version out of range: " + core.vault_int_str(version)));
  }
  let cur: Int = v.states[version - 1];
  if cur == VAULT_KV_DESTROYED && op != VAULT_KV_OP_DESTROY {
    return _err_kv(core.vault_err("kv version " + core.vault_int_str(version) + " is destroyed"));
  }
  var next_state = cur;
  if op == VAULT_KV_OP_WRITE {
    next_state = VAULT_KV_LIVE;
  } elif op == VAULT_KV_OP_READ {
    if cur != VAULT_KV_LIVE {
      if cur == VAULT_KV_ABSENT {
        return _err_kv(core.vault_err("kv version " + core.vault_int_str(version) + " is absent"));
      }
      if cur == VAULT_KV_SOFT_DELETED {
        return _err_kv(core.vault_err("kv version " + core.vault_int_str(version) + " is deleted"));
      }
    }
  } elif op == VAULT_KV_OP_DELETE {
    if cur == VAULT_KV_ABSENT {
      return _err_kv(core.vault_err("kv version " + core.vault_int_str(version) + " is absent"));
    }
    next_state = VAULT_KV_SOFT_DELETED;
  } elif op == VAULT_KV_OP_UNDELETE {
    if cur == VAULT_KV_ABSENT {
      return _err_kv(core.vault_err("kv version " + core.vault_int_str(version) + " is absent"));
    }
    if cur != VAULT_KV_SOFT_DELETED && cur != VAULT_KV_LIVE {
      return _err_kv(core.vault_err("kv version " + core.vault_int_str(version) + " is not deleted"));
    }
    next_state = VAULT_KV_LIVE;
  } else {
    if cur == VAULT_KV_ABSENT {
      return _err_kv(core.vault_err("kv version " + core.vault_int_str(version) + " is absent"));
    }
    next_state = VAULT_KV_DESTROYED;
  }
  var states = _copy_states(v);
  states[version - 1] = next_state;
  return _ok_kv(VaultKvVersions{ states: states });
}
