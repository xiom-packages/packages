# xiom.rbac

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Role-based access rules with token wildcards and deny-override
> evaluation.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.compare` and
> `xiom.string.builder`). Tests additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.rbac` stores access rules in a flat `RolePolicy` (four index-aligned
vectors: role, kind, action, resource) and answers one question: does this
policy allow `(role, action, resource)`? Both rule tokens and query tokens are
single byte strings; the only wildcard is the token `"*"` (see
`SPEC.md`). Evaluation is **deny-override**: a matching deny always wins over
every matching allow, and a request with no matching allow is denied
(default deny).

## Deny-override semantics

1. If **any** deny rule matches the `(role, action, resource)` triple, the
   request is denied -- regardless of how many allow rules match and of the
   order in which rules were recorded.
2. Otherwise, if **any** allow rule matches, the request is allowed.
3. Otherwise the request is denied (empty policy => everything denied).

A rule matches when each of its tokens matches the corresponding query token:
exact byte equality, or the rule token is `"*"` (matches anything in that
position). A query token is never special: querying with `"*"` only matches a
rule whose token is literally `"*"` in that position.

## API

| Function | Returns | Description |
|---|---|---|
| `rbac_new()` | `RolePolicy` | Empty policy: no rules, denies everything. |
| `rbac_matches(pattern, value)` | `Bool` | Token matcher: exact equality, or `pattern == "*"`. |
| `rbac_allow(p, role, action, resource)` | -- | Append an allow rule (`"*"` tokens allowed). |
| `rbac_deny(p, role, action, resource)` | -- | Append a deny rule. |
| `rbac_allows(p, role, action, resource)` | `Bool` | Deny-override verdict; default deny. |
| `rbac_roles(p)` | `Vec[Str]` | Distinct role tokens, first-seen rule order. |
| `rbac_role_rules(p, role)` | `Vec[Str]` | `"allow:action:resource"` / `"deny:..."` for the rules that apply to `role`, in rule order. |
| `rbac_rule_count(p)` | `Int` | Number of recorded rules (duplicates included). |
| `rbac_clear_role(p, role)` | `Int` | Remove rules recorded under the exact token `role`; returns how many. |
| `rbac_allowed_actions(p, role, resource)` | `Vec[Str]` | Distinct action tokens of the matching allow rules; `"*"` stays literal. |

Documented choices (see `SPEC.md` sections 4-5 for the exact statements):

- **Duplicates append.** `rbac_allow`/`rbac_deny` never collapse or reorder
  rules; recording the same rule twice keeps two entries.
- **`rbac_role_rules` is wildcard-aware.** A rule whose role token is `"*"`
  is included for every query role; a query of `"*"` matches only rules
  recorded under `"*"` (the wildcard is a property of the rule token only).
- **`rbac_clear_role` is exact.** It removes rules whose role token equals the
  argument byte-for-byte (so `"*"` clears only wildcard rules).
- **`rbac_allowed_actions` is a listing, not a verdict.** It consults allow
  rules only (denies are ignored) and reports a rule's action token verbatim:
  an action token `"*"` yields the literal token `"*"`, not an expansion.
  Use `rbac_allows` for the authorization decision.

## Usage

```xi
use xiom.rbac;
use xiom.io;

fn main() -> Int {
  var p = rbac_new();
  rbac_allow(&mut p, "editor", "read", "doc");
  rbac_allow(&mut p, "editor", "*", "doc");
  rbac_deny(&mut p, "editor", "delete", "doc");
  io.println(rbac_allows(&p, "editor", "read", "doc"));    // true
  io.println(rbac_allows(&p, "editor", "delete", "doc"));  // false (deny wins)
  io.println(rbac_allows(&p, "guest", "read", "doc"));     // false
  var acts = rbac_allowed_actions(&p, "editor", "doc");    // ["read", "*"]
  io.println(rbac_rule_count(&p));                         // 3
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.rbac
```

Expected tail: 22 `[PASS]` lines, `xiom.rbac: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Token-level wildcards only.** `"*"` matches a whole token; there are no
  prefix/suffix/character globs (`"read*"` is a literal), no role hierarchies
  or inheritance, and no resource paths/patterns.
- **No conditions or attributes.** Rules cannot depend on time, IP, ownership,
  context, or any other predicate; only the three string tokens are consulted.
- **No priorities, obligations or deny reasons.** Deny-override is total: all
  denies are equal and beat all allows; no rule metadata is recorded.
- **No persistence.** A `RolePolicy` is an in-memory value; there is no
  parser, serializer, file I/O or registry integration.
- **No mutation by pattern.** `rbac_clear_role` removes by exact role token;
  a wildcard query in `rbac_allowed_actions`/`rbac_allows` only matches rules
  whose token is literally `"*"` in that position.
- Linear scans: matching, listing and clearing are O(rule count) (listings add
  a de-duplication scan); there is no index.

See `SPEC.md` for the full rule model, evaluation order and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
