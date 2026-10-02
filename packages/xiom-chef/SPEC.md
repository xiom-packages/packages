# xiom.chef -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.chef` (`src/chef.xi`). Pure XIOM, no FFI, no network, no shell,
no file I/O.

## 1. Scope

A pure, in-memory model of the Chef configuration pipeline:

- cookbook / recipe / resource declarations (`chef_cookbook_new`,
  `chef_add_recipe`, `chef_add_resource`, `chef_set_attr`, `chef_notifies`,
  `chef_subscribes`),
- role sets and runlist expansion (`chef_roleset_new`, `chef_add_role`,
  `chef_role_entry`, `chef_runlist_expand`),
- attribute precedence with a documented merge order (`chef_attrs_*`),
- explicit provider dispatch (`chef_provider_for`, `chef_resource_provider`),
- the resource-collection compile phase (`chef_compile`),
- notification / subscription delivery with immediate vs delayed timing and
  the idempotence / converge report (`chef_converge`,
  `chef_converge_collection`, `chef_report_render`).

Out of scope by design: real providers, cookbook loading from disk, attribute
files, environments, data bags, search, policyfiles, knife/server operations,
and every form of network or shell access.

## 2. Data model

```xi
pub type Cookbook = {
  name: Str;
  recipes: Vec[Str];       // recipe names, declaration order
  res_recipe: Vec[Int];    // recipe index owning each resource row
  res_type: Vec[Str];      // "package", "service", "template", ...
  res_name: Vec[Str];
  res_action: Vec[Str];    // "nothing" declares a no-op resource
  at_owner: Vec[Int];      // resource index owning each attribute row
  at_key: Vec[Str];
  at_value: Vec[Str];
  nt_owner: Vec[Int];      // resource declaring each notification
  nt_action: Vec[Str];
  nt_target: Vec[Str];     // "type[name]" or bare "name"
  nt_timing: Vec[Int];     // 0 immediate, 1 delayed
  sb_owner: Vec[Int];      // subscribing resource
  sb_action: Vec[Str];
  sb_source: Vec[Str];     // "type[name]" or bare "name"
  sb_timing: Vec[Int];
}

pub type RoleSet = { names: Vec[Str]; e_owner: Vec[Int]; e_entry: Vec[Str]; }

pub type Attrs = { keys: Vec[Str]; values: Vec[Str]; levels: Vec[Int]; }

pub type Collection = {
  recipes: Vec[Str];       // recipe name owning each resource row
  res_type: Vec[Str]; res_name: Vec[Str]; res_action: Vec[Str];
  at_owner: Vec[Int]; at_key: Vec[Str]; at_value: Vec[Str];
  nt_owner: Vec[Int]; nt_action: Vec[Str]; nt_target: Vec[Str]; nt_timing: Vec[Int];
  sb_owner: Vec[Int]; sb_action: Vec[Str]; sb_source: Vec[Str]; sb_timing: Vec[Int];
}

pub type Report = {
  total: Int; updated: Int; unchanged: Int; skipped: Int;
  provider_calls: Int; immediate_fired: Int; delayed_fired: Int;
  events: Vec[Str];
}
```

`Vec[StructType]` is unusable in this compiler (v0.62.2), so every row family
is a separate homogeneous parallel vector. Invariants enforced by the builder
API:

- every resource row's `res_recipe` names a valid recipe index,
- every attribute / notification / subscription row's owner names a valid
  resource index,
- every role entry row's `e_owner` names a valid role index,
- `Attrs.keys` contains no duplicates,
- `Report.total == updated + unchanged + skipped`.

## 3. Cookbook, recipe and resource model

A **recipe** is a named list of resources; `chef_add_recipe` appends in
declaration order and returns the recipe index. A **resource** is
`(type, name, action)` plus attribute rows; `chef_add_resource` appends it to
a recipe and returns the resource index. Resource names need not be unique;
reference resolution uses the first match in collection order.

Special attribute keys understood by the converge model:

| Key | Values | Meaning |
|---|---|---|
| `satisfied` | exact `"true"` | Live state already matches; converges to unchanged. |
| `provider` | a known provider name | Overrides the type dispatch. |

All other keys are model metadata carried through compile and reachable with
`chef_collection_attr`.

## 4. Runlist grammar and expansion

```
runlist     = entry *
entry       = "recipe[" name "]"        ; explicit recipe
            / "role[" name "]"          ; role reference
            / name                      ; bare recipe name
name        = 1*( byte except <= SP, "[", "]" )
```

`chef_runlist_expand` walks the runlist in order and emits recipe names:

1. A bare name or `recipe[name]` must name a declared recipe; otherwise
   `chef: unknown recipe: <name>`.
2. `role[name]` must name a declared role; otherwise
   `chef: unknown role: <name>`. The role's entries are expanded recursively,
   depth-first, in declaration order; role entries may themselves be
   `role[...]` references.
3. A role already on the expansion stack is a cycle:
   `chef: role cycle: <name>`.
4. A malformed entry (empty, unterminated bracket, `[]`, embedding `[`/`]`,
   or inner whitespace) is `chef: malformed runlist entry: <entry>`.
5. Bounds (fail-closed): role nesting deeper than 32 is
   `chef: runlist role nesting exceeded depth 32`; more than 512 expanded
   recipes is `chef: runlist expansion exceeded 512 recipes`.
6. Duplicate recipes are preserved exactly as written (documented, covered by
   test t23).

**Reference resolution** (`type[name]` or bare `name`) is used by
notifications and subscriptions: `type[name]` matches the first collection
resource with that type and name; a bare name matches the first resource with
that name regardless of type. An unknown reference is a compile error.

## 5. Attribute precedence

Levels, lowest to highest: `default` = 0, `normal` = 1, `override` = 2.

Merge order: `chef_attrs_resolve(defaults, normal, overrides)` merges the
three sources in that order. Per assignment (`_attrs_put`):

1. A key not yet present is appended; its position is the first insertion
   position and never changes.
2. An existing key is replaced when the new level is **>=** its current level.
   Equal level = later assignment wins; a lower level never overwrites a
   higher one, regardless of merge order.
3. `chef_attrs_set` returns false for any level name other than
   `"default"` / `"normal"` / `"override"` and stores nothing.

`chef_attrs_level` returns the winning level or -1; `chef_attrs_get` returns
the winning value or `None`.

## 6. Provider resolution

`chef_provider_for(typ)` is an explicit case analysis:

| Resource type(s) | Provider |
|---|---|
| `package` | `package` |
| `service` | `service` |
| `group` | `group` |
| `user` | `user` |
| `file`, `template`, `cookbook_file`, `remote_file`, `directory` | `file` |
| `execute`, `bash`, `script` | `execute` |
| anything else | `Err("chef: no provider for resource type: <type>")` |

`chef_resource_provider(cb, res)` first reads the resource's `provider`
attribute: when present it must be one of the six known provider names
(`package`, `service`, `file`, `execute`, `group`, `user`), else
`Err("chef: unknown provider name: <name>")`; when absent it falls back to
the type dispatch above. The same rule is applied to compiled resources by
`chef_compile` / `chef_converge_collection`.

## 7. Compile and converge

### 7.1 Compile

`chef_compile(cb, rs, runlist)`:

1. Expand the runlist (section 4).
2. In runlist order and, within a recipe, declaration order, copy each
   resource and its attribute / notification / subscription rows into a
   `Collection`, rebinding every owner to the new collection index.
3. Validate every resource resolves a provider (section 6).
4. Validate every notification target and subscription source resolves to a
   collection resource; otherwise
   `chef: unknown notification target: <ref>` /
   `chef: unknown subscription source: <ref>`.
5. Return the collection, or the first error in this order.

### 7.2 Converge

`chef_converge_collection(col)` performs two passes.

**Main pass**, resource `i = 0..n-1` in collection order, each at most once:

- Resolve the provider (errors propagate).
- `action == "nothing"` and not forced -> **skipped**.
- `satisfied == "true"` and not forced -> **unchanged**.
- Otherwise -> **updated**: one provider call, then deliver `i`'s
  notifications (row order) followed by subscriptions whose source resolves
  to `i` (row order):
  - an **immediate** delivery fires during the update. If the target has not
    converged yet it is *forced* (it will run when its turn comes, even for
    `nothing` / `satisfied`). If the target ended unchanged/skipped it is
    **promoted to updated** (one extra provider call, event
    `notified-update: ...`). If it already updated, only the fired counter
    moves.
  - a **delayed** delivery is queued FIFO (owner, target) for the delayed
    pass.

**Delayed pass**, after the main pass, drains the FIFO queue in delivery
order with the same target rules (all targets have converged by then, so a
delivery either promotes unchanged/skipped to updated or is count-only).

**Boundedness:** a delivery never rebroadcasts the target's own notifications
and a resource never converges twice, so cycles terminate; a hard cap of 8192
deliveries fails the run closed with
`chef: notification cascade exceeded bound`. `total == updated + unchanged +
skipped` holds at every point.

Events are appended in exactly this order: classification events during the
main pass (`updated:` / `unchanged:` / `skipped:`), immediate delivery events
at the point of update (`immediate: owner -> target`), promotions
(`notified-update: target`), then delayed delivery events
(`delayed: owner -> target`) and their promotions in the final pass.

### 7.3 Report rendering

`chef_report_render` emits, LF-separated with no trailing LF:

```
chef report: total=<T> updated=<U> unchanged=<N> skipped=<S>
provider_calls=<P> immediate=<I> delayed=<D>
event: <event>
event: <event>
...
```

The two header lines are always present; an empty run renders exactly those
two and no event lines.

## 8. Error catalog

| Message | Raised by |
|---|---|
| `chef: malformed runlist entry: <e>` | expand / compile |
| `chef: unknown recipe: <name>` | expand / compile |
| `chef: unknown role: <name>` | expand / compile |
| `chef: role cycle: <name>` | expand / compile |
| `chef: runlist role nesting exceeded depth 32` | expand / compile |
| `chef: runlist expansion exceeded 512 recipes` | expand / compile |
| `chef: no provider for resource type: <type>` | compile / converge / provider |
| `chef: unknown provider name: <name>` | compile / converge / resource provider |
| `chef: unknown notification target: <ref>` | compile |
| `chef: unknown subscription source: <ref>` | compile |
| `chef: notification cascade exceeded bound` | converge (fail-closed cap) |

## 9. Determinism and complexity

Everything is deterministic: iteration is index order over parallel vectors,
role expansion is depth-first in declaration order, delayed deliveries are
FIFO, and no hash-ordered structure is used. On identical inputs the
collection, report counts and event order are byte-identical.

Let `R` be resource rows, `A` attribute rows, `N` notification rows, `S`
subscription rows and `E` expanded recipes. Compile is O(E * R + A + N + S)
plus reference resolution O(R * (N + S)). Converge is O(R^2) in the worst
case for reference lookups repeated per delivery, bounded by the 8192-step
cap; memory is O(R + A + N + S + events).

## 10. v0.62.2 compiler notes

- Free functions only; every walk is index-based over parallel vectors.
- `Result` constructors live only in the leaf helpers `_col_ok` / `_col_err`,
  `_strs_ok` / `_strs_err`, `_report_ok` / `_report_err`, `_str_ok` /
  `_str_err`, `_bool_ok` / `_bool_err`.
- All `Str` equality goes through `xiom.string.compare.str_compare` via
  `_streq` (BUG 17: `==` on `Vec[Str]` elements lowers to a pointer
  comparison).
- Every byte read is widened and masked through `_byte`
  (`(byte_at(...) as Int) & 0xFF`).
- Every vector element read is bound to a typed local first.
- No `&mut` scalar parameters; all mutable converge state lives in the
  module-internal `Conv` struct.
- One module: no sibling or parent imports, so no cross-module
  `Ok`/`Err` identity issues.

## 11. Conformance map (tests/test_conformance.xi, 26 checks)

| Test | Covers |
|---|---|
| t01 | builders, cookbook metadata, recipe ownership |
| t02 | bare name == `recipe[name]` |
| t03 | runlist order, collection accessors |
| t04 | role expansion order |
| t05 | nested roles, depth-first |
| t06 | role cycle detection |
| t07 | runlist error catalog |
| t08 | precedence default < normal < override |
| t09 | same-level last-wins, lower never wins, first position |
| t10 | three-source resolve chain and merge immutability |
| t11 | provider dispatch table and unknown type |
| t12 | `provider` attribute override, unknown override |
| t13 | compile provider validation, empty runlist |
| t14 | basic converge, all updated |
| t15 | updated / unchanged / skipped split |
| t16 | immediate notification forces `nothing` |
| t17 | immediate notification forces `satisfied` |
| t18 | delayed promotion of a converged unchanged target |
| t19 | subscription inversion |
| t20 | unknown notification target / subscription source |
| t21 | exact report render and event order |
| t22 | already-updated target: no double provider call |
| t23 | duplicate runlist entries preserved |
| t24 | bare-name notification target |
| t25 | bounded immediate notification cycle |
| t26 | error propagation and the zero report |

## 12. Version history

- 0.1.0 -- initial pure-XIOM model, 26-check conformance suite, built and run
  on compiler v0.62.2 with the `stdlib` checkout.
