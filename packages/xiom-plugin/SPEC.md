# xiom.plugin -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.plugin` (`src/plugin.xi`). Pure XIOM, no FFI, no file I/O, no
dynamic loading.

## 1. Scope

A deterministic, in-memory model of a plugin ecosystem:

- registration metadata (`plugin_spec`, `plugin_register`) with validation,
- strict-semver parsing, ordering and range-constraint checks,
- dependency-order resolution (stable topological sort + cycle detection),
- an enable/disable/activate/deactivate lifecycle state machine,
- capability declaration and lookup.

Out of scope by design: loading code (no `dlopen`/`LoadLibrary`, no FFI), file
I/O, environment reads, hot reload, version negotiation over the network, and
pre-release/build version syntax.

## 2. Data model

```xi
pub type PluginSpec = {
  name: Str;         // non-empty, byte-exact, case-sensitive
  version: Str;      // strict x.y.z (section 4)
  deps: Vec[Str];    // declared dependency names, declaration order
  caps: Vec[Str];    // declared capability names, declaration order
}

pub type Registry = {
  names: Vec[Str];       // one row per plugin, registration order
  versions: Vec[Str];    // index-aligned with names
  states: Vec[Int];      // index-aligned with names (plugin_state_* constants)
  dep_owner: Vec[Int];   // dependency edges: declaring plugin index
  dep_name: Vec[Str];    // index-aligned with dep_owner: dependency name
  cap_owner: Vec[Int];   // capability rows: declaring plugin index
  cap_name: Vec[Str];    // index-aligned with cap_owner: capability name
}
```

`Vec[StructType]` is unusable in this compiler, so a registry is a set of
index-aligned parallel vectors rather than a list of plugin structs.

Invariants maintained by `plugin_register`:

1. `names`, `versions` and `states` are the same length; every name is unique.
2. Every version satisfies section 4.
3. Dependency rows: owner indices are valid; names are non-empty; a plugin's
   dependency names are unique; a plugin never depends on itself. Dependencies
   on *unregistered* plugins are permitted at registration time and reported by
   `plugin_resolve`.
4. Capability rows: owner indices are valid; names are non-empty and unique per
   plugin. The same capability name may be declared by different plugins.

Registration order (the index of each plugin) is the tie-break for every
deterministic walk in this module.

## 3. Exported constants

| Constant | Value | Meaning |
|---|---|---|
| `plugin_state_registered` | 0 | Present; dependencies not checked yet. |
| `plugin_state_enabled` | 1 | May be activated once its dependencies are. |
| `plugin_state_active` | 2 | Enabled and running in the host. |

`plugin_state(reg, name)` returns -1 for an unknown plugin.
`plugin_state_name` maps 0/1/2 to `"registered"`/`"enabled"`/`"active"` and
any other value to `"unknown"`.

## 4. Versions

A version is a **strict** semantic version `x.y.z`:

```
version    = component "." component "." component
component  = "0" / ( non-zero-digit *digit )
```

- Exactly three components; `1.2` and `1.2.3.4` are invalid.
- Components are decimal, ASCII-only, with no leading zeros (`01` invalid).
- Each component is at most 2147483647; a larger value is invalid.
- No sign, whitespace, pre-release (`-rc.1`) or build (`+sha`) suffix.

`plugin_version_valid(v)` reports this. `plugin_version_cmp(a, b)` compares
component-wise (major, then minor, then patch) and returns `Ok(-1 | 0 | 1)`, or
`Err("plugin: invalid version: <v>")` for the first malformed argument.

## 5. Range constraints

```
range      = delimiters* ( comparator delimiters* )*
comparator = op version / "*" / version
op         = ">=" / "<=" / ">" / "<" / "=" / "==" / "^" / "~"
delimiters = SP | TAB | ","
```

- Empty or delimiter-only range:
  `Err("plugin: empty range")`.
- Every comparator must hold (logical AND); evaluation stops reporting at the
  first malformed token, which yields
  `Err("plugin: invalid range token: <tok>")` where `<tok>` is the exact
  token text. A comparator is written without internal whitespace, so
  `">= 1.2.3"` is the invalid token `">="`; separate comparators with commas
  or spaces.
- `*` matches any valid version and is a token like any other (so `"*"` alone
  is a valid non-empty range).
- `=v`, `==v` and a bare `v` all mean "exactly v".
- `>v`, `>=v`, `<v`, `<=v` are strict/weak orderings.
- `^v` (compatible) with `v = x.y.z` means `>= v` **and** `< u`, where `u` is:
  `(x+1).0.0` when `x > 0`; `0.(y+1).0` when `x == 0` and `y > 0`;
  `0.0.(z+1)` when `x == 0` and `y == 0`. Examples: `^1.2.3` accepts 1.9.9,
  rejects 2.0.0; `^0.2.3` accepts 0.2.9, rejects 0.3.0; `^0.0.0` accepts only
  0.0.0.
- `~v` (patch-level) with `v = x.y.z` means `>= v` and `< x.(y+1).0`.

`plugin_check_constraint(version, range)` parses the version first
(`Err("plugin: invalid version: <v>")`), then the range. `plugin_satisfies`
returns `False` for every error case. `plugin_dependency_satisfied(reg, owner,
dep, range)` is `True` only when both plugins are registered, `owner` declares
`dep`, and the registered version of `dep` satisfies `range`.

## 6. Registration

`plugin_spec(name, version, deps, caps)` copies `deps` and `caps` into a fresh
`PluginSpec` (the spec does not alias caller vectors).

`plugin_register(reg, spec)` returns a new `Registry` with the plugin appended
in state `plugin_state_registered`, or an `Err` with the FIRST problem found,
in this validation order:

| # | Check | Error message |
|---|---|---|
| 1 | name is empty | `plugin: empty plugin name` |
| 2 | version fails section 4 | `plugin: invalid version for <name>: <version>` |
| 3 | name already registered | `plugin: duplicate plugin: <name>` |
| 4 | dependency name empty | `plugin: empty dependency name for <name>` |
| 5 | dependency equals the plugin name | `plugin: self dependency for <name>` |
| 6 | duplicate dependency in this spec | `plugin: duplicate dependency <dep> for <name>` |
| 7 | capability name empty | `plugin: empty capability name for <name>` |
| 8 | duplicate capability in this spec | `plugin: duplicate capability <cap> for <name>` |

On `Err` the input registry is unchanged. Names are compared byte-exactly
(`str_compare`); `Core` and `core` are different plugins.

## 7. Dependency resolution

`plugin_resolve(reg) -> Result[Vec[Str], Str]` orders every registered plugin
so that each plugin appears after all of its declared dependencies.

Algorithm (Kahn's, made stable):

1. In-degree of plugin `i` is the number of its declared dependencies (all of
   which must be registered). If any dependency name is not registered:
   `Err("plugin: missing dependency: <dep> (required by <owner>)")` — the
   first offender in (owner registration order, declaration order) wins.
2. Repeatedly emit the **lowest registration index** among not-yet-emitted
   plugins with in-degree 0 (this is the stability rule: independent plugins
   come out in registration order, not alphabetical order). Emitting a plugin
   decrements the in-degree of every not-yet-emitted dependent.
3. If some plugins remain after no zero-in-degree candidate exists, the
   residual graph contains at least one cycle. Starting from the lowest
   not-yet-emitted index, follow the first not-yet-emitted declared dependency
   until an index repeats; the message is
   `Err("plugin: dependency cycle: <a> -> <b> -> ... -> <a>")`, listing the
   repeated path segment plus the closing edge (e.g. `a -> b -> a` or
   `a -> b -> c -> a`).

Properties: the result contains every plugin exactly once; it is a function of
the registry value alone (no hash order, no random tie-breaks); the empty
registry resolves to an empty vector. Complexity is O(n^2 + n*e) for n plugins
and e dependency rows, because the parallel vectors are scanned rather than
indexed by a side map.

## 8. Lifecycle state machine

| From \ Operation | `enable` | `disable` | `activate` | `deactivate` |
|---|---|---|---|---|
| `registered` (0) | -> `enabled` | error | error | error |
| `enabled` (1) | error | -> `registered` | -> `active` (deps must pass) | error |
| `active` (2) | error | error | error | -> `enabled` (no active dependent) |

Every transition returns a new `Registry` (the input is unchanged) or an
`Err`:

- Unknown plugin: `plugin: unknown plugin: <name>`.
- Wrong source state: `plugin: cannot <op> <name>: state is <state>` where
  `<op>` is `enable`, `disable`, `activate` or `deactivate` and `<state>` is
  the current state name. (So an active plugin cannot be disabled directly:
  deactivate first.)
- `plugin_activate` additionally requires **every** declared dependency to be
  in state `enabled` or `active`; otherwise
  `plugin: cannot activate <name>: dependency not enabled: <dep>` (first
  failing dependency in declaration order; an unregistered dependency counts
  as not enabled).
- `plugin_deactivate` additionally requires that no currently `active` plugin
  declares a dependency on it; otherwise
  `plugin: cannot deactivate <name>: active dependent: <dep>` (first such
  dependent in registration order).

Consequences: a dependency cycle can never be fully activated (the first
member's dependency is never enabled), and activation proceeds in
dependency-first order. `plugin_enable_all(reg)` enables every plugin in
`plugin_resolve` order; `plugin_activate_all(reg)` activates every plugin in
`plugin_resolve` order (dependencies first, so the per-plugin precondition
always holds for a resolvable registry). Both propagate the `plugin_resolve`
errors (`missing dependency`, `dependency cycle`) unchanged; the
`activate_all` state guard is defensive only.

## 9. Capabilities

A capability is a free-form, non-empty, byte-exact name a plugin declares.
Duplicate declarations within one spec are rejected (section 6); the same
capability declared by several plugins is allowed and means "several
providers".

- `plugin_capabilities(reg, name)`: declared capabilities in declaration
  order (fresh copy; empty for an unknown plugin).
- `plugin_has_capability(reg, name, cap)`: membership.
- `plugin_find_capability(reg, cap)`: the first provider in registration
  order, as `Option[Str]`.
- `plugin_providers(reg, cap)`: all providers in registration order (fresh
  copy).

## 10. Metadata lookup

- `plugin_count`, `plugin_names` (fresh copy, registration order),
  `plugin_has`, `plugin_index` (-1 when absent),
  `plugin_version` (`Option[Str]`), `plugin_deps` (fresh copy, declaration
  order), `plugin_state`, `plugin_state_name`, `plugin_count_by_state`.
- All returned vectors are fresh copies; mutating them never changes the
  registry. No function in this module mutates its arguments.

## 11. Determinism and error policy

- No randomness, no hashing, no time, no I/O: results depend only on argument
  values, and iteration order is always registration/declaration order.
- Errors are `Err(Str)` values with the exact messages catalogued in
  sections 5-8; there are no panics for malformed input, and out-of-range
  indices are avoided by construction.
- `plugin_satisfies` and `plugin_dependency_satisfied` degrade any error to
  `False` rather than propagating it.

## 12. Conformance test map

`tests/test_conformance.xi` (25 checks) covers: empty-registry behavior and
state names (`t01`); single registration metadata/capabilities (`t02`);
registration order and index stability (`t03`); dependency metadata order
(`t04`); the version grammar and empty-name errors (`t05`); duplicate/self/
dependency/capability errors and registry immutability (`t06`); comparator
ranges and the error catalog (`t07`); caret (`t08`) and tilde (`t09`) upper
bounds; compound/star ranges (`t10`); version ordering (`t11`); component
bounds and leading zeros (`t12`); resolution on empty/single (`t13`),
shuffled (`t14`) and diamond (`t15`) graphs; missing dependencies (`t16`); two-
(`t17`) and three-node (`t18`) cycles; the enable/disable (`t19`),
activate (`t20`) and deactivate (`t21`) transitions with exact errors;
`enable_all`/`activate_all` including propagated resolution errors (`t22`);
capability provider order (`t23`); fresh-copy enumeration (`t24`); and the
dependency-satisfied integration check (`t25`).
