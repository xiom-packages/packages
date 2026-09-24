// XIOM -- xiom.rbac: role-based access rules with wildcard matching and
// deny-override evaluation
// Port task: replace the xiom.rbac placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one policy is four parallel vectors. Rule i occupies index i in all
// four of them:
//   roles[i]     - the role token the rule applies to ("*" matches any role),
//   kinds[i]     - 0 = allow, 1 = deny,
//   actions[i]   - the action token ("*" matches any action),
//   resources[i] - the resource token ("*" matches any resource).
// Vec[StructType] is unsupported in this compiler, so the policy is
// deliberately flat (four parallel Vec) instead of a Vec of rule structs.
//
// Matching is token-level: a token is either * or an exact byte string; there
// are no prefix/suffix globs (see rbac_matches). Evaluation is deny-override:
// any matching deny rule rejects the request, otherwise any matching allow
// rule permits it, otherwise the request is denied (default deny).
//
// Every rule recorded verbatim by rbac_allow/rbac_deny is kept, duplicates
// included (appends never collapse or reorder); rbac_roles and the listing
// helpers de-duplicate only their own outputs.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods on RolePolicy.
//   * Ok/Err are not used at all: every function is infallible.
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); Vec[Str] element reads use typed locals.
//   * Rule text for rbac_role_rules is assembled with xiom.string.builder.

module xiom.rbac

use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Rule kinds
// --------------------------------------------------

// Allow rule: the request is permitted unless a deny rule overrides it.
const _RBAC_ALLOW: Int = 0;
// Deny rule: a matching deny always rejects the request.
const _RBAC_DENY: Int = 1;

// --------------------------------------------------
//  Policy model
// --------------------------------------------------

/// A role policy: four index-aligned parallel vectors, one slot per rule.
/// `kinds[i]` is 0 (allow, see _RBAC_ALLOW) or 1 (deny, see _RBAC_DENY) and
/// picks how the triple (roles[i], actions[i], resources[i]) is interpreted;
/// every token may be "*" to match anything in that position. Construct
/// through rbac_new and mutate through rbac_allow/rbac_deny/rbac_clear_role;
/// the parallel vectors are kept the same length by every operation.
pub type RolePolicy = {
  roles: Vec[Str];
  kinds: Vec[Int];
  actions: Vec[Str];
  resources: Vec[Str];
}

// --------------------------------------------------
//  Construction and matching
// --------------------------------------------------

/// Fresh empty policy: no rules, so every request is denied.
/// Returns: a RolePolicy with four empty parallel vectors.
/// Error case: none. Complexity: O(1).
pub fn rbac_new() -> RolePolicy {
  return RolePolicy{
    roles: Vec[Str].new();
    kinds: Vec[Int].new();
    actions: Vec[Str].new();
    resources: Vec[Str].new();
  };
}

/// Token matcher: exact byte equality, plus the single wildcard token "*".
/// Params: pattern - the rule-side token (may be "*"); value - the query
///         token (never special, even when it is "*").
/// Returns: true when pattern is "*", or when pattern and value are the same
/// byte string (str_compare == 0). Empty pattern matches only empty value.
/// No prefix/suffix/character globs: "read*" matches nothing but "read*".
/// Error case: none. Complexity: O(min(|pattern|, |value|)).
pub fn rbac_matches(pattern: Str, value: Str) -> Bool {
  if compare.str_compare(pattern, "*") == 0 {
    return true;
  }
  return compare.str_compare(pattern, value) == 0;
}

// True when `want` is already in v (byte-exact, str_compare). Used to build
// distinct first-seen listings.
fn _rbac_contains(v: &Vec[Str], want: Str) -> Bool {
  var i = 0;
  while i < v.len() {
    let e: Str = v[i];
    if compare.str_compare(e, want) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when rule i matches the whole (role, action, resource) triple.
// Role, action and resource tokens each match under rbac_matches, so a rule
// token of "*" in any position matches every query token there.
fn _rbac_rule_hits(p: &RolePolicy, i: Int, role: Str, action: Str, resource: Str) -> Bool {
  let r: Str = p.roles[i];
  if !rbac_matches(r, role) {
    return false;
  }
  let a: Str = p.actions[i];
  if !rbac_matches(a, action) {
    return false;
  }
  let res: Str = p.resources[i];
  return rbac_matches(res, resource);
}

// --------------------------------------------------
//  Rule recording
// --------------------------------------------------

/// Append an allow rule. Rule tokens are single tokens; role, action and
/// resource may each be "*" to match everything in that position. The rule is
/// appended verbatim: duplicates are kept, never collapsed (documented).
/// Params: p - the policy to mutate; role, action, resource - the rule tokens.
/// Error case: none. Complexity: O(1) amortized.
pub fn rbac_allow(p: &mut RolePolicy, role: Str, action: Str, resource: Str) {
  p.roles.push(role);
  p.kinds.push(_RBAC_ALLOW);
  p.actions.push(action);
  p.resources.push(resource);
}

/// Append a deny rule. Same token and append semantics as rbac_allow; a
/// matching deny always overrides every matching allow (deny-override).
/// Params: p - the policy to mutate; role, action, resource - the rule tokens.
/// Error case: none. Complexity: O(1) amortized.
pub fn rbac_deny(p: &mut RolePolicy, role: Str, action: Str, resource: Str) {
  p.roles.push(role);
  p.kinds.push(_RBAC_DENY);
  p.actions.push(action);
  p.resources.push(resource);
}

// --------------------------------------------------
//  Evaluation
// --------------------------------------------------

/// Decide one request with deny-override.
/// Params: p - the policy; role, action, resource - the request tokens.
/// Returns: false as soon as any deny rule matches the triple; otherwise true
/// when any allow rule matches; otherwise false (default deny). Rules are
/// scanned in recorded order but the result does not depend on that order:
/// deny wins over allow regardless of position.
/// Error case: none. Complexity: O(rule count * token length).
pub fn rbac_allows(p: &RolePolicy, role: Str, action: Str, resource: Str) -> Bool {
  var i = 0;
  while i < p.roles.len() {
    let k: Int = p.kinds[i];
    if k == _RBAC_DENY {
      if _rbac_rule_hits(p, i, role, action, resource) {
        return false;
      }
    }
    i = i + 1;
  }
  var j = 0;
  while j < p.roles.len() {
    let k2: Int = p.kinds[j];
    if k2 == _RBAC_ALLOW {
      if _rbac_rule_hits(p, j, role, action, resource) {
        return true;
      }
    }
    j = j + 1;
  }
  return false;
}

// --------------------------------------------------
//  Introspection
// --------------------------------------------------

/// Distinct role tokens of the policy, in first-seen rule order.
/// Params: p - the policy.
/// Returns: a fresh Vec[Str]; each token once, at the position of its first
/// rule. The wildcard role "*" is listed as itself when present. A policy
/// with no rules yields an empty vector.
/// Error case: none. Complexity: O(rule count^2) str_compare calls.
pub fn rbac_roles(p: &RolePolicy) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < p.roles.len() {
    let r: Str = p.roles[i];
    if !_rbac_contains(&out, r) {
      out.push(r);
    }
    i = i + 1;
  }
  return out;
}

// Render rule i as "allow:action:resource" or "deny:action:resource".
fn _rbac_rule_text(p: &RolePolicy, i: Int) -> Str {
  var out = Vec[UInt8].new();
  let k: Int = p.kinds[i];
  if k == _RBAC_ALLOW {
    builder.sb_push_str(&mut out, "allow:");
  } else {
    builder.sb_push_str(&mut out, "deny:");
  }
  let a: Str = p.actions[i];
  builder.sb_push_str(&mut out, a);
  builder.sb_push_str(&mut out, ":");
  let r: Str = p.resources[i];
  builder.sb_push_str(&mut out, r);
  return builder.sb_to_str(&out);
}

/// Rule text of every rule that applies to `role`, in rule order.
/// Params: p - the policy; role - the query role token.
/// Returns: a fresh Vec[Str] of "allow:action:resource" /
/// "deny:action:resource" strings. The rule's role token is matched with
/// rbac_matches, so rules recorded under role "*" are included for every
/// query role; a query of "*" matches only rules recorded under "*" (the
/// wildcard is a property of the rule token, not of the query).
/// Error case: none. Complexity: O(rule count * token length).
pub fn rbac_role_rules(p: &RolePolicy, role: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < p.roles.len() {
    let r: Str = p.roles[i];
    if rbac_matches(r, role) {
      out.push(_rbac_rule_text(p, i));
    }
    i = i + 1;
  }
  return out;
}

/// Number of recorded rules (every appended rule, duplicates included).
/// Params: p - the policy.
/// Returns: the common length of the four parallel vectors.
/// Error case: none. Complexity: O(1).
pub fn rbac_rule_count(p: &RolePolicy) -> Int {
  return p.roles.len();
}

/// Remove every rule whose role token is exactly `role`.
/// Params: p - the policy to mutate; role - the role token to remove,
///         compared byte-exactly (str_compare), so "*" clears only rules
///         recorded under "*" and never touches other roles.
/// Returns: the number of removed rules; 0 when the role has no rule, which
/// makes repeated calls idempotent. The four parallel vectors are compacted,
/// so the recorded order of the surviving rules is preserved.
/// Error case: none. Complexity: O(rule count * token length).
pub fn rbac_clear_role(p: &mut RolePolicy, role: Str) -> Int {
  var removed = 0;
  var write = 0;
  var i = 0;
  while i < p.roles.len() {
    let r: Str = p.roles[i];
    if compare.str_compare(r, role) == 0 {
      removed = removed + 1;
    } else {
      p.roles[write] = r;
      let k: Int = p.kinds[i];
      p.kinds[write] = k;
      let a: Str = p.actions[i];
      p.actions[write] = a;
      let res: Str = p.resources[i];
      p.resources[write] = res;
      write = write + 1;
    }
    i = i + 1;
  }
  while p.roles.len() > write {
    p.roles.pop();
    p.kinds.pop();
    p.actions.pop();
    p.resources.pop();
  }
  return removed;
}

/// Distinct action tokens of the allow rules that match `role` and `resource`.
/// Params: p - the policy; role, resource - the query tokens.
/// Returns: a fresh Vec[Str] with each matching allow rule's action token
/// once, in first-seen rule order. The tokens are reported verbatim: a rule
/// whose action token is "*" contributes the literal token "*" (it is not
/// expanded into a concrete action list); pass "*" to rbac_matches when
/// interpreting the result. Only allow rules are consulted -- deny rules are
/// ignored, so this is a listing of what is granted, not an authorization
/// decision (use rbac_allows for the deny-override verdict). A policy with no
/// matching allow rule yields an empty vector.
/// Error case: none. Complexity: O(rule count * (token length + output size)).
pub fn rbac_allowed_actions(p: &RolePolicy, role: Str, resource: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < p.roles.len() {
    let k: Int = p.kinds[i];
    if k == _RBAC_ALLOW {
      let r: Str = p.roles[i];
      let res: Str = p.resources[i];
      if rbac_matches(r, role) && rbac_matches(res, resource) {
        let a: Str = p.actions[i];
        if !_rbac_contains(&out, a) {
          out.push(a);
        }
      }
    }
    i = i + 1;
  }
  return out;
}
