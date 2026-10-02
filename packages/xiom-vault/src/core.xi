// XIOM -- xiom.vault.core: shared constants and byte/string helpers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The support layer of the xiom.vault package: method-code and header
// constants plus the tiny byte/text helpers that every sibling module uses.
// It has no dependencies beyond xiom.std and defines no composite logic.
//
// Sibling layout (all modules under `xiom.vault.*`, import direction is
// sibling-to-sibling only -- child modules cannot import their parent on
// compiler v0.62.2):
//
//   * `xiom.vault`        composed client operations (the package entry)
//   * `xiom.vault.core`   this module: constants + helpers
//   * `xiom.vault.client` request / response / body model
//   * `xiom.vault.json`   bounded flat-JSON scanner
//   * `xiom.vault.kv`     KV secrets engine model
//   * `xiom.vault.unseal` Shamir sharing and unseal progress
//   * `xiom.vault.auth`   token / AppRole models
//   * `xiom.vault.policy` path rules and capability sets
//
// v0.62.2 notes: free functions only; every byte read widened with
// `(x as Int) & 0xFF`; Str equality through xiom.string.compare (never `==`).

module xiom.vault.core

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Method codes
// --------------------------------------------------

/// Unknown method code (0).
pub const VAULT_METHOD_UNKNOWN: Int = 0;

/// HTTP method code: GET (1).
pub const VAULT_METHOD_GET: Int = 1;

/// HTTP method code: POST (2).
pub const VAULT_METHOD_POST: Int = 2;

/// HTTP method code: PUT (3).
pub const VAULT_METHOD_PUT: Int = 3;

/// HTTP method code: PATCH (4).
pub const VAULT_METHOD_PATCH: Int = 4;

/// HTTP method code: DELETE (5).
pub const VAULT_METHOD_DELETE: Int = 5;

/// HTTP method code: LIST (6, Vault's list verb).
pub const VAULT_METHOD_LIST: Int = 6;

/// HTTP method code: HEAD (7).
pub const VAULT_METHOD_HEAD: Int = 7;

/// HTTP method code: OPTIONS (8).
pub const VAULT_METHOD_OPTIONS: Int = 8;

// --------------------------------------------------
//  Header and size limits
// --------------------------------------------------

/// Canonical Vault token header name.
pub const VAULT_HEADER_TOKEN: Str = "X-Vault-Token";

/// Canonical Vault namespace header name.
pub const VAULT_HEADER_NAMESPACE: Str = "X-Vault-Namespace";

/// Maximum number of request headers (64).
pub const VAULT_MAX_HEADERS: Int = 64;

/// Maximum number of body members (64).
pub const VAULT_MAX_BODY_MEMBERS: Int = 64;

/// Maximum normalized path length (4096 bytes).
pub const VAULT_MAX_PATH: Int = 4096;

/// Maximum number of policy rules (64).
pub const VAULT_MAX_POLICY_RULES: Int = 64;

/// Maximum length of a policy path pattern (512 bytes).
pub const VAULT_MAX_PATTERN: Int = 512;

/// Maximum number of KV version slots in the state model (256).
pub const VAULT_MAX_KV_VERSIONS: Int = 256;

/// Maximum secret length accepted by the Shamir helpers (1024 bytes).
pub const VAULT_MAX_SECRET: Int = 1024;

/// Maximum number of Shamir shares (255).
pub const VAULT_MAX_SHARES: Int = 255;

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

/// Byte at `pos` of a Str widened to an Int in 0..255; callers guarantee the
/// bounds.
/// Params: s - the text; pos - a valid byte index. Returns: the byte value.
/// Error case: none. Complexity: O(1).
pub fn vault_byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

/// True for a CTL byte (0x00-0x1F, 0x7F).
/// Params: c - a widened byte. Returns: the predicate.
/// Error case: none. Complexity: O(1).
pub fn vault_is_ctl(c: Int) -> Bool {
  if c < 32 {
    return true;
  }
  if c == 127 {
    return true;
  }
  return false;
}

/// True when two Str values are byte-for-byte equal (never `==` on Str).
/// Params: a, b - the values. Returns: the predicate.
/// Error case: none. Complexity: O(min(len)).
pub fn vault_str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

/// True when two Str values are equal ignoring ASCII case.
/// Params: a, b - the values. Returns: the predicate.
/// Error case: none. Complexity: O(min(len)).
pub fn vault_str_eq_ci(a: Str, b: Str) -> Bool {
  return compare.str_eq_ignore_case(a, b);
}

/// Decimal rendering of `v` with no leading zeros ("0" for zero, "-" for
/// negatives). Used for error messages and rendered body integers.
/// Params: v - the integer. Returns: the decimal text.
/// Error case: none. Complexity: O(digits).
pub fn vault_int_str(v: Int) -> Str {
  var sb = Vec[UInt8].new();
  builder.sb_push_int(&mut sb, v);
  return builder.sb_to_str(&sb);
}

/// "vault: <what>" -- the package's plain error form.
/// Params: what - the description. Returns: the message.
/// Error case: none. Complexity: O(what.len()).
pub fn vault_err(what: Str) -> Str {
  return "vault: " + what;
}

/// "vault: <what> at offset N" -- the package's offset-bearing error form.
/// Params: what - the description; off - a byte offset. Returns: the message.
/// Error case: none. Complexity: O(what.len()).
pub fn vault_err_at(what: Str, off: Int) -> Str {
  return ("vault: " + what + " at offset ") + vault_int_str(off);
}

/// True when `name` is an RFC 7230 token (the header-name alphabet); false
/// for "".
/// Params: name - the candidate text. Returns: the predicate.
/// Error case: none. Complexity: O(name.len()).
pub fn vault_is_token(name: Str) -> Bool {
  if name.len() == 0 {
    return false;
  }
  var i = 0;
  while i < name.len() {
    let c = vault_byte(name, i);
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
    if c == 33 || c == 35 || c == 36 || c == 37 || c == 38 {
      ok = true;
    }
    if c == 39 || c == 42 || c == 43 || c == 45 || c == 46 {
      ok = true;
    }
    if c == 94 || c == 95 || c == 96 || c == 124 || c == 126 {
      ok = true;
    }
    if !ok {
      return false;
    }
    i = i + 1;
  }
  return true;
}
