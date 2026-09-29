# xiom.plugin

> **Status:** `incubating` -- conformance-tested (25/25); not yet published on the XIOM registry.
> **Scope:** deterministic plugin registry and lifecycle model: registration
> metadata, strict-semver range checks, dependency-order resolution and an
> enable/activate state machine. Metadata and ordering only -- no dynamic
> loading, no FFI, no file I/O.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_len`,
> `xiom.string.str_slice`, `xiom.string.byte_at` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.plugin` is a pure, in-memory model of a plugin ecosystem for XIOM
programs. It answers the questions a host must answer *before* it loads any
code, without loading any code: which plugins are registered with which
versions and dependencies, which version ranges a candidate satisfies, in
which order plugins may be loaded so every dependency precedes its dependents,
which capability a plugin provides, and which lifecycle transitions are legal
right now.

Everything is deterministic: registration order is the tie-break for every
walk, dependency resolution is a stable topological sort, and capability
lookups return the first registered provider. There is no global state and no
I/O, so the same registry value works in a test, in a build script and in a
long-running host.

## API

| Function | Returns | Description |
|---|---|---|
| `plugin_registry_new()` | `Registry` | Empty registry. |
| `plugin_spec(name, version, deps, caps)` | `PluginSpec` | Registration metadata (copies the two vectors). |
| `plugin_register(reg, spec)` | `Result[Registry, Str]` | Add one plugin (starts `registered`); first error wins, input untouched. |
| `plugin_count(reg)` | `Int` | Number of registered plugins. |
| `plugin_names(reg)` | `Vec[Str]` | Names in registration order (fresh copy). |
| `plugin_has(reg, name)` | `Bool` | True when registered. |
| `plugin_index(reg, name)` | `Int` | Registration index, or -1. |
| `plugin_version(reg, name)` | `Option[Str]` | Registered version, or `None`. |
| `plugin_deps(reg, name)` | `Vec[Str]` | Declared dependencies in declaration order. |
| `plugin_state(reg, name)` | `Int` | `plugin_state_registered`/`_enabled`/`_active`, or -1. |
| `plugin_state_name(state)` | `Str` | `"registered"`, `"enabled"`, `"active"` or `"unknown"`. |
| `plugin_count_by_state(reg, state)` | `Int` | Plugins currently in `state`. |
| `plugin_capabilities(reg, name)` | `Vec[Str]` | Declared capabilities in declaration order. |
| `plugin_has_capability(reg, name, cap)` | `Bool` | True when `name` declares `cap`. |
| `plugin_find_capability(reg, cap)` | `Option[Str]` | First registered provider of `cap`. |
| `plugin_providers(reg, cap)` | `Vec[Str]` | All providers of `cap` in registration order. |
| `plugin_version_valid(v)` | `Bool` | True for strict `x.y.z`. |
| `plugin_version_cmp(a, b)` | `Result[Int, Str]` | -1/0/1, or `Err` on a malformed version. |
| `plugin_check_constraint(version, range)` | `Result[Bool, Str]` | Range check with precise errors. |
| `plugin_satisfies(version, range)` | `Bool` | `False` on any malformed input. |
| `plugin_resolve(reg)` | `Result[Vec[Str], Str]` | Stable dependency order; missing-dep/cycle `Err`. |
| `plugin_enable(reg, name)` | `Result[Registry, Str]` | `registered -> enabled`. |
| `plugin_disable(reg, name)` | `Result[Registry, Str]` | `enabled -> registered`. |
| `plugin_activate(reg, name)` | `Result[Registry, Str]` | `enabled -> active`; all deps must be enabled/active. |
| `plugin_deactivate(reg, name)` | `Result[Registry, Str]` | `active -> enabled`; no active dependent allowed. |
| `plugin_enable_all(reg)` | `Result[Registry, Str]` | Enable every plugin in `plugin_resolve` order. |
| `plugin_activate_all(reg)` | `Result[Registry, Str]` | Activate every plugin in `plugin_resolve` order. |
| `plugin_dependency_satisfied(reg, owner, dep, range)` | `Bool` | Declared edge + version-range integration check. |

Lifecycle states are the exported constants `plugin_state_registered` (0),
`plugin_state_enabled` (1) and `plugin_state_active` (2).

Versions are strict semantic versions: exactly three numeric components
`x.y.z`, no leading zeros, each component at most 2147483647, no pre-release
or build suffix. Ranges are comma/whitespace separated comparators, all of
which must hold: `=v` / `==v` / bare `v` (exact), `>v`, `>=v`, `<v`, `<=v`,
`^v` (compatible) and `~v` (patch-level), plus `*` for any valid version.
See `SPEC.md` for the exact grammar and error catalog.

## Usage

```xi
use xiom.plugin;
use xiom.io;

fn main() -> Int {
  let none = Vec[Str].new();
  var deps = Vec[Str].new();
  deps.push("core");
  var reg = plugin_registry_new();
  let core = plugin_spec("core", "1.4.0", &none, &none);
  let app = plugin_spec("app", "2.0.0", &deps, &none);
  match plugin_register(&reg, &core) {
    Ok(r) => { reg = r; },
    Err(e) => { io.println(e); return 1; },
  }
  match plugin_register(&reg, &app) {
    Ok(r) => { reg = r; },
    Err(e) => { io.println(e); return 1; },
  }
  match plugin_resolve(&reg) {
    Ok(order) => {
      let first: Str = order[0];
      let second: Str = order[1];
      io.println("load order: " + first + ", " + second); // core, app
    },
    Err(e) => { io.println(e); return 1; },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.plugin
```

Expected tail: 25 `[PASS]` lines, `xiom.plugin: all tests passed`, then
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## Install / publish

```
xiom pkg install xiom.plugin@0.1.0     # consumer (once published)
xiom pkg publish                       # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## Limitations (honest scope)

- **No dynamic loading.** `Registry` is metadata: this package never opens a
  library, calls `dlopen`/`LoadLibrary` or uses FFI. Loading code is the
  host's job; this package tells the host what to load and in which order.
- No file I/O, no config parsing, no network: feed the functions values that
  your program read elsewhere.
- Versions are strict `x.y.z` only: pre-release (`-rc.1`) and build metadata
  (`+sha`) are rejected, and each numeric component is capped at 2147483647.
- Range comparators cannot be written with whitespace inside (`>= 1.2.3` is an
  invalid token); separate comparators with commas or spaces instead.
- `plugin_register` rejects duplicate plugins, duplicate/self/empty
  dependency names and duplicate/empty capability names, but it does **not**
  reject dependency cycles; cycles are reported by `plugin_resolve` (and by
  `plugin_enable_all`/`plugin_activate_all`, which use it).
- Duplicate capability declarations across different plugins are allowed;
  `plugin_find_capability` returns the first in registration order.
- Dependency resolution requires every declared dependency to be registered
  (a registry-closed graph); there is no partial/optional-dependency mode.
- Complexity: registration and most lookups are O(plugins); `plugin_resolve`
  is O(plugins^2 + plugins * edges) because it scans parallel vectors, which
  is fine for the registry sizes this model targets.
- Keys and names are byte-exact and case-sensitive; no Unicode normalization.

See `SPEC.md` for the full grammar, transition table, resolution algorithm and
error catalog. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
