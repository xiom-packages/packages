# xiom.rbac -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.rbac` (`src/rbac.xi`). Pure XIOM, no FFI.

## 1. Scope

An in-memory role-based access model with token wildcards and deny-override
evaluation:

- a policy (`RolePolicy`) stores an ordered list of allow/deny rules,
- a rule fixes a role token, a kind (allow/deny), an action token and a
  resource token; any token may be `"*"` to match everything in its position,
- `rbac_matches` is the token matcher (exact or `"*"`),
- `rbac_allows` is the deny-override authorization decision,
- `rbac_roles`, `rbac_role_rules`, `rbac_rule_count` introspect the policy,
- `rbac_clear_role` removes every rule recorded under one exact role token,
- `rbac_allowed_actions` lists the action tokens granted for a role and
  resource by the allow rules.

## 2. Non-goals

- Role hierarchies, inheritance, groups, or transitive role expansion.
- Resource paths, glob patterns other than the single `"*"` token, prefix or
  suffix matching, or per-character wildcards.
- Conditions, attributes, owners, time/IP/context predicates, or policy
  languages (no parser, no serializer).
- Rule priorities, weights, obligations, deny reasons, or conflict metadata;
  deny-override is total and unconditional.
- Persistence, I/O, FFI, global state, or registry integration.
- Mutation by pattern: `rbac_clear_role` matches the role token exactly.

## 3. Rule model

A `RolePolicy` is four index-aligned parallel vectors; rule `i` is
`(roles[i], kinds[i], actions[i], resources[i])`:

| Field | Type | Meaning |
|---|---|---|
| `roles` | `Vec[Str]` | Role token the rule applies to (`"*"` matches any role). |
| `kinds` | `Vec[Int]` | `0` = allow, `1` = deny. |
| `actions` | `Vec[Str]` | Action token (`"*"` matches any action). |
| `resources` | `Vec[Str]` | Resource token (`"*"` matches any resource). |

Invariants: the four vectors always have the same length; `kinds` contains
only `0` and `1`. `rbac_new` yields four empty vectors. `rbac_allow` and
`rbac_deny` append one index-aligned slot; `rbac_clear_role` removes
matching slots and compacts the four vectors together, preserving the order of
the surviving rules. Tokens are stored verbatim -- no trimming, case folding
or validation.

## 4. Wildcard matching and evaluation order

`rbac_matches(pattern, value)`:

1. `pattern == "*"` (byte-exact, `str_compare`) => `true`, for any `value`
   including the empty string and `"*"`.
2. otherwise `pattern == value` byte-exactly (`str_compare == 0`) => `true`.
3. otherwise `false`.

The wildcard lives on the rule token only; `value` is never treated as a
pattern (`rbac_matches("read", "*")` is `false`). A rule matches a triple when
its three tokens each match the corresponding query token.

`rbac_allows(p, role, action, resource)` evaluates deny-override:

1. Scan all rules; if any `kinds[i] == 1` (deny) rule matches the triple,
   return `false`.
2. Otherwise scan all rules; if any `kinds[i] == 0` (allow) rule matches,
   return `true`.
3. Otherwise return `false`.

Consequences: an empty policy denies everything; a deny beats every allow
regardless of insertion order; non-matching rules of either kind are ignored;
the result depends only on the rule set, not on the order in which rules were
recorded.

## 5. Documented choices

- **Duplicates append.** `rbac_allow`/`rbac_deny` append unconditionally;
  recording the same rule twice keeps two entries (counted, listed and
  cleared twice). This keeps recording O(1) and the rule order exact.
- **`rbac_role_rules` is wildcard-aware.** It lists the rules that *apply to*
  `role`: a rule whose role token matches `role` under `rbac_matches` is
  included, so rules recorded under role `"*"` appear for every query role.
  A query of `"*"` matches only rules recorded under `"*"` (the wildcard is a
  property of the rule token, never of the query).
- **`rbac_clear_role` is exact.** It removes rules whose role token equals the
  argument byte-for-byte, so clearing `"*"` removes only wildcard rules and
  never touches concrete roles. Repeated calls are idempotent (`0` removed).
- **`rbac_allowed_actions` is a listing, not a verdict.** It consults allow
  rules only (deny rules are ignored) and reports each matching allow rule's
  action token verbatim, distinct and in first-seen rule order; an action
  token `"*"` contributes the literal token `"*"` and is not expanded. Use
  `rbac_allows` for the authorization decision.
- **Listings return fresh vectors.** `rbac_roles`, `rbac_role_rules` and
  `rbac_allowed_actions` never alias policy storage.

## 6. API signatures

```xi
pub type RolePolicy = {
  roles: Vec[Str];
  kinds: Vec[Int];
  actions: Vec[Str];
  resources: Vec[Str];
}

pub fn rbac_new() -> RolePolicy
pub fn rbac_matches(pattern: Str, value: Str) -> Bool
pub fn rbac_allow(p: &mut RolePolicy, role: Str, action: Str, resource: Str)
pub fn rbac_deny(p: &mut RolePolicy, role: Str, action: Str, resource: Str)
pub fn rbac_allows(p: &RolePolicy, role: Str, action: Str, resource: Str) -> Bool
pub fn rbac_roles(p: &RolePolicy) -> Vec[Str]
pub fn rbac_role_rules(p: &RolePolicy, role: Str) -> Vec[Str]
pub fn rbac_rule_count(p: &RolePolicy) -> Int
pub fn rbac_clear_role(p: &mut RolePolicy, role: Str) -> Int
pub fn rbac_allowed_actions(p: &RolePolicy, role: Str, resource: Str) -> Vec[Str]
```

All functions are infallible (no `Result`, no panic path) and deterministic.
`rbac_new`, `rbac_matches`, `rbac_allow`, `rbac_deny`, `rbac_rule_count` are
O(1) (appends amortized); `rbac_allows`, `rbac_role_rules` and
`rbac_allowed_actions` are O(rule count) plus token comparisons;
`rbac_roles` is O(rule count^2) because of its de-duplication scan;
`rbac_clear_role` is O(rule count).

## 7. Test plan

`tests/test_conformance.xi` (module `rbac_tests`) runs 22 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | empty policy | no rules, every request denied, empty listings |
| t2 | matches exact | byte-exact, case-sensitive, empty/empty only for empty pattern |
| t3 | matches wildcard | `"*"` matches any value; `"re*"`, `"*read"` and query `"*"` do not |
| t4 | allow-only | the recorded triple is permitted; role/action/resource mismatches are not |
| t5 | deny overrides | identical allow + deny => denied |
| t6 | order independence | deny before allow still wins; other resources unaffected |
| t7 | wildcard allow | `("*", "*")` covers all actions/resources for one role only |
| t8 | wildcard deny | `("editor", "*", "doc")` blocks every action on `doc`, not `notes` |
| t9 | role list | distinct tokens in first-seen rule order |
| t10 | rule listing | `allow:`/`deny:` text in rule order, wildcard action text preserved |
| t11 | listing applies-to | wildcard-role rules listed for concrete roles; `"*"` query lists only `"*"` rules |
| t12 | allowed_actions | distinct allow actions for the resource; deny and other resources ignored |
| t13 | actions wildcards | action `"*"` stays literal; rule-side resource `"*"` matches concrete queries |
| t14 | clear_role | removes the exact role's rules, returns the count, other roles intact |
| t15 | clear idempotence | second and unknown-role clears return 0 |
| t16 | clear `"*"` | removes only wildcard rules, concrete roles intact |
| t17 | duplicates | three identical rules count, list and clear as three |
| t18 | many-rule mixed | 12 duplicate allows + viewer allow + deny: deny wins, clear counts 13 |
| t19 | large policy | 40 rules compact to empty in one clear; listing collapses to one action |
| t20 | re-add | policy usable after clear; clear-then-allow grants again |
| t21 | role/action isolation | wildcard allow + targeted deny isolates role and action |
| t22 | counts/unknowns | `rbac_rule_count` matches appends; unknown-role queries list nothing |

Test helpers wrap the `&`-based read API in `&mut`-taking helpers so a
`&local` read call is never followed by a `&mut local` call in the same test
body (advisory E001); every `Str` comparison goes through
`xiom.string.compare.str_compare` with typed locals for `Vec[Str]` reads
(BUG 17 discipline). No `match`, `Vec[StructType]` or `Vec[fn]` is used.

## 8. Compiler / stdlib notes

No compiler workarounds were required beyond the documented v0.61.x
constraints: free functions only, no methods on `RolePolicy`, typed
`let x: Str = v[i];` / `let k: Int = v[i];` element reads, and rule text
assembled with `xiom.string.builder`. The module imports `xiom.string.builder`
and `xiom.string.compare`; the suite uses `xiom.test`, `xiom.io` and
`xiom.string.compare`. Verified with `.\scripts\port.ps1 -Package xiom.rbac`
(v0.61.3): 22 passed, 0 failed, `program_exit=0`.
