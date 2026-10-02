// XIOM -- xiom.vault.policy: path rules, capability sets, glob matching
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM MODEL of a vault ACL policy:
//
//   * Capability sets are Int bitmasks over the eight Vault capabilities
//     (create, read, update, delete, list, sudo, deny, patch) plus DENY,
//     which overrides every other capability of the same rule.
//   * A policy is a list of (path pattern, capability mask) rules; the
//     parallel vectors never drift (every rule push mirrors both).
//   * Pattern matching is glob-style over bytes:
//       - '*' matches any run of characters, '/' included (the Vault
//         trailing-star prefix semantics generalize to interior stars);
//       - '+' matches a run of one or more characters within a single path
//         segment (no '/');
//       - every other byte matches itself, case-sensitively.
//     The matcher is an iterative dynamic program (no recursion), bounded to
//     131072 cells; oversized pattern/path pairs simply do not match.
//   * Longest-prefix resolution: among all matching rules the longest pattern
//     wins; equal-length matches are unioned, so a DENY in a tie denies.
//     decision = NONE when nothing matches, DENY when the effective mask has
//     DENY or lacks the requested capability, ALLOW otherwise.
//
// v0.62.2 notes: free functions only; Ok/Err only in the `_ok_*`/`_err_*`
// leaves; bytes widened with `(x as Int) & 0xFF`; Str equality through
// core.vault_str_eq_ci (never `==`); bitwise expressions are parenthesized;
// every DP loop has guaranteed progress.

module xiom.vault.policy

use xiom.vault.core;
use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Capability bit: create (1).
pub const VAULT_CAP_CREATE: Int = 1;

/// Capability bit: read (2).
pub const VAULT_CAP_READ: Int = 2;

/// Capability bit: update (4).
pub const VAULT_CAP_UPDATE: Int = 4;

/// Capability bit: delete (8).
pub const VAULT_CAP_DELETE: Int = 8;

/// Capability bit: list (16).
pub const VAULT_CAP_LIST: Int = 16;

/// Capability bit: sudo (32).
pub const VAULT_CAP_SUDO: Int = 32;

/// Capability bit: deny (64), overrides the other bits of its rule.
pub const VAULT_CAP_DENY: Int = 64;

/// Capability bit: patch (128).
pub const VAULT_CAP_PATCH: Int = 128;

/// Mask of all defined capability bits.
pub const VAULT_CAP_ALL: Int = 255;

/// Decision: no rule matched (0).
pub const VAULT_DECISION_NONE: Int = 0;

/// Decision: a matching rule grants the capability (1).
pub const VAULT_DECISION_ALLOW: Int = 1;

/// Decision: a matching rule denies the capability (2).
pub const VAULT_DECISION_DENY: Int = 2;

/// Maximum length of a path pattern (512 bytes).
pub const VAULT_MAX_PATTERN_LEN: Int = 512;

/// Maximum number of DP cells in the glob matcher (131072).
pub const VAULT_MAX_MATCH_CELLS: Int = 131072;

// --------------------------------------------------
//  Public data model
// --------------------------------------------------

/// A policy: parallel rule vectors, always the same length.
pub type VaultPolicy = {
  patterns: Vec[Str];
  caps: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Capability sets
// --------------------------------------------------

/// Capability code of a capability name (case-insensitive); 0 for unknown
/// names.
/// Params: name - the capability name. Returns: the single-bit code or 0.
/// Error case: none. Complexity: O(name.len()).
pub fn vault_capability_code(name: Str) -> Int {
  if core.vault_str_eq_ci(name, "create") {
    return VAULT_CAP_CREATE;
  }
  if core.vault_str_eq_ci(name, "read") {
    return VAULT_CAP_READ;
  }
  if core.vault_str_eq_ci(name, "update") {
    return VAULT_CAP_UPDATE;
  }
  if core.vault_str_eq_ci(name, "delete") {
    return VAULT_CAP_DELETE;
  }
  if core.vault_str_eq_ci(name, "list") {
    return VAULT_CAP_LIST;
  }
  if core.vault_str_eq_ci(name, "sudo") {
    return VAULT_CAP_SUDO;
  }
  if core.vault_str_eq_ci(name, "deny") {
    return VAULT_CAP_DENY;
  }
  if core.vault_str_eq_ci(name, "patch") {
    return VAULT_CAP_PATCH;
  }
  return 0;
}

/// Canonical name of a single capability bit ("" for 0, combined masks or
/// unknown bits).
/// Params: code - a capability bit. Returns: the canonical name.
/// Error case: none. Complexity: O(1).
pub fn vault_capability_name(code: Int) -> Str {
  if code == VAULT_CAP_CREATE {
    return "create";
  }
  if code == VAULT_CAP_READ {
    return "read";
  }
  if code == VAULT_CAP_UPDATE {
    return "update";
  }
  if code == VAULT_CAP_DELETE {
    return "delete";
  }
  if code == VAULT_CAP_LIST {
    return "list";
  }
  if code == VAULT_CAP_SUDO {
    return "sudo";
  }
  if code == VAULT_CAP_DENY {
    return "deny";
  }
  if code == VAULT_CAP_PATCH {
    return "patch";
  }
  return "";
}

/// Build a capability mask from names (case-insensitive). The list must be
/// non-empty and every name must be a defined capability; duplicates are
/// harmless.
/// Params: names - the capability names.
/// Returns: Ok(mask with the OR of the named bits).
/// Error case: Err("vault: capability list is empty") or
/// Err("vault: unknown capability: <name>").
/// Complexity: O(names count * name length).
pub fn vault_capability_set(names: &Vec[Str]) -> Result[Int, Str] {
  if names.len() == 0 {
    return _err_int(core.vault_err("capability list is empty"));
  }
  var mask = 0;
  var i = 0;
  while i < names.len() {
    let nm: Str = names[i];
    let code = vault_capability_code(nm);
    if code == 0 {
      return _err_int("vault: unknown capability: " + nm);
    }
    mask = mask | code;
    i = i + 1;
  }
  return _ok_int(mask);
}

/// True when the mask grants the capability bit.
/// Params: set - a capability mask; cap - a single capability bit.
/// Returns: the predicate. Error case: none. Complexity: O(1).
pub fn vault_capability_set_has(set: Int, cap: Int) -> Bool {
  if cap == 0 {
    return false;
  }
  if (set & cap) == cap {
    return true;
  }
  return false;
}

/// Render the canonical capability names of `set` in bit order, comma
/// separated ("read,list"); "" for 0. Unknown bits are ignored.
/// Params: set - a capability mask. Returns: the rendered text.
/// Error case: none. Complexity: O(1).
pub fn vault_capability_set_render(set: Int) -> Str {
  var out = Vec[UInt8].new();
  var first = true;
  if (set & VAULT_CAP_CREATE) != 0 {
    builder.sb_push_str(&mut out, "create");
    first = false;
  }
  if (set & VAULT_CAP_READ) != 0 {
    if !first {
      out.push(44 as UInt8);
    }
    builder.sb_push_str(&mut out, "read");
    first = false;
  }
  if (set & VAULT_CAP_UPDATE) != 0 {
    if !first {
      out.push(44 as UInt8);
    }
    builder.sb_push_str(&mut out, "update");
    first = false;
  }
  if (set & VAULT_CAP_DELETE) != 0 {
    if !first {
      out.push(44 as UInt8);
    }
    builder.sb_push_str(&mut out, "delete");
    first = false;
  }
  if (set & VAULT_CAP_LIST) != 0 {
    if !first {
      out.push(44 as UInt8);
    }
    builder.sb_push_str(&mut out, "list");
    first = false;
  }
  if (set & VAULT_CAP_SUDO) != 0 {
    if !first {
      out.push(44 as UInt8);
    }
    builder.sb_push_str(&mut out, "sudo");
    first = false;
  }
  if (set & VAULT_CAP_DENY) != 0 {
    if !first {
      out.push(44 as UInt8);
    }
    builder.sb_push_str(&mut out, "deny");
    first = false;
  }
  if (set & VAULT_CAP_PATCH) != 0 {
    if !first {
      out.push(44 as UInt8);
    }
    builder.sb_push_str(&mut out, "patch");
    first = false;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Policy rules
// --------------------------------------------------

// True when `pattern` is usable: 1..512 printable non-space bytes without
// CTL, '?' or '#'.
fn _pattern_ok(pattern: Str) -> Bool {
  let n = pattern.len();
  if n == 0 || n > VAULT_MAX_PATTERN_LEN {
    return false;
  }
  var i = 0;
  while i < n {
    let c = core.vault_byte(pattern, i);
    if core.vault_is_ctl(c) || c == 32 {
      return false;
    }
    if c == 63 || c == 35 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// A new empty policy.
/// Params: none. Returns: an empty VaultPolicy.
/// Error case: none. Complexity: O(1).
pub fn vault_policy_new() -> VaultPolicy {
  return VaultPolicy{ patterns: Vec[Str].new(); caps: Vec[Int].new() };
}

/// Append a rule. The mask must contain at least one defined capability bit.
/// Params: p - the policy; pattern - the path pattern (1..512 printable
/// bytes, no space / '?' / '#'); caps - the capability mask.
/// Returns: Ok(0).
/// Error case: Err("vault: policy pattern is empty or invalid"),
/// Err("vault: policy rule has no capabilities") or
/// Err("vault: policy has too many rules").
/// Complexity: O(pattern.len()).
pub fn vault_policy_add(p: &mut VaultPolicy, pattern: Str, caps: Int) -> Result[Int, Str] {
  if !_pattern_ok(pattern) {
    return _err_int(core.vault_err("policy pattern is empty or invalid"));
  }
  if (caps & VAULT_CAP_ALL) == 0 {
    return _err_int(core.vault_err("policy rule has no capabilities"));
  }
  if p.patterns.len() >= core.VAULT_MAX_POLICY_RULES {
    return _err_int(core.vault_err("policy has too many rules"));
  }
  p.patterns.push(pattern);
  p.caps.push(caps);
  return _ok_int(0);
}

/// Number of rules.
/// Params: p - the policy. Returns: the count.
/// Error case: none. Complexity: O(1).
pub fn vault_policy_rule_count(p: &VaultPolicy) -> Int {
  return p.patterns.len();
}

/// Pattern of rule i ("" for an out-of-range index).
/// Params: p - the policy; i - a rule index.
/// Returns: the pattern. Error case: none. Complexity: O(1).
pub fn vault_policy_pattern(p: &VaultPolicy, i: Int) -> Str {
  if i < 0 || i >= p.patterns.len() {
    return "";
  }
  let v: Str = p.patterns[i];
  return v;
}

/// Capability mask of rule i (0 for an out-of-range index).
/// Params: p - the policy; i - a rule index.
/// Returns: the mask. Error case: none. Complexity: O(1).
pub fn vault_policy_rule_caps(p: &VaultPolicy, i: Int) -> Int {
  if i < 0 || i >= p.caps.len() {
    return 0;
  }
  let v: Int = p.caps[i];
  return v;
}

// --------------------------------------------------
//  Glob matching
// --------------------------------------------------

/// Glob-match `pattern` against `path` ('*' = any run including '/',
/// '+' = one-or-more bytes within a segment, otherwise literal bytes).
/// Iterative DP; pattern/path pairs with more than 131072 cells do not
/// match.
/// Params: pattern - the glob pattern; path - the path to test.
/// Returns: the predicate. Error case: none. Complexity: O(pattern.len() *
/// path.len()).
pub fn vault_policy_path_matches(pattern: Str, path: Str) -> Bool {
  let plen = pattern.len();
  let slen = path.len();
  let cells = (plen + 1) * (slen + 1);
  if cells > VAULT_MAX_MATCH_CELLS {
    return false;
  }
  var dp = Vec[Int].new();
  var idx = 0;
  while idx < cells {
    dp.push(0);
    idx = idx + 1;
  }
  dp[0] = 1;
  let row = slen + 1;
  var pi = 0;
  while pi < plen {
    let pc = core.vault_byte(pattern, pi);
    let base = pi * row;
    let nbase = (pi + 1) * row;
    var si = 0;
    while si <= slen {
      if dp[base + si] == 0 {
        si = si + 1;
      } else {
        if pc == 42 {
          dp[nbase + si] = 1;
          var k = si;
          while k < slen {
            if dp[nbase + k] == 1 {
              dp[nbase + k + 1] = 1;
            }
            k = k + 1;
          }
        } elif pc == 43 {
          if si < slen && core.vault_byte(path, si) != 47 {
            dp[nbase + si + 1] = 1;
            var k2 = si + 1;
            while k2 < slen {
              if dp[nbase + k2] == 1 && core.vault_byte(path, k2) != 47 {
                dp[nbase + k2 + 1] = 1;
              }
              k2 = k2 + 1;
            }
          }
        } else {
          if si < slen && pc == core.vault_byte(path, si) {
            dp[nbase + si + 1] = 1;
          }
        }
        si = si + 1;
      }
    }
    pi = pi + 1;
  }
  if dp[plen * row + slen] == 1 {
    return true;
  }
  return false;
}

/// Effective capability mask for `path`: the longest matching pattern wins;
/// equal-length matches are unioned (so DENY in a tie denies). 0 when no
/// rule matches.
/// Params: p - the policy; path - the API path.
/// Returns: the effective mask. Error case: none. Complexity: O(rule count *
/// matching cost).
pub fn vault_policy_effective_caps(p: &VaultPolicy, path: Str) -> Int {
  var best_len = -1;
  var best = 0;
  var found = false;
  var i = 0;
  while i < p.patterns.len() {
    let pat: Str = p.patterns[i];
    if vault_policy_path_matches(pat, path) {
      let len = pat.len();
      let c: Int = p.caps[i];
      if !found || len > best_len {
        best_len = len;
        best = c;
        found = true;
      } elif len == best_len {
        best = best | c;
      }
    }
    i = i + 1;
  }
  return best;
}

/// Decision for one capability against a path: NONE (0) when no rule
/// matches, DENY (2) when the effective mask has DENY or lacks the
/// capability, ALLOW (1) otherwise.
/// Params: p - the policy; path - the API path; cap - a capability bit.
/// Returns: the decision code. Error case: none. Complexity: O(rule count *
/// matching cost).
pub fn vault_policy_decision(p: &VaultPolicy, path: Str, cap: Int) -> Int {
  let caps = vault_policy_effective_caps(p, path);
  if caps == 0 {
    return VAULT_DECISION_NONE;
  }
  if (caps & VAULT_CAP_DENY) != 0 {
    return VAULT_DECISION_DENY;
  }
  if vault_capability_set_has(caps, cap) {
    return VAULT_DECISION_ALLOW;
  }
  return VAULT_DECISION_DENY;
}

/// Convenience predicate: the policy grants `cap` on `path`
/// (decision == ALLOW).
/// Params: p - the policy; path - the API path; cap - a capability bit.
/// Returns: the predicate. Error case: none. Complexity: O(rule count *
/// matching cost).
pub fn vault_policy_can(p: &VaultPolicy, path: Str, cap: Int) -> Bool {
  if vault_policy_decision(p, path, cap) == VAULT_DECISION_ALLOW {
    return true;
  }
  return false;
}
