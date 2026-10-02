# xiom.puppet

> **Status:** `incubating` -- conformance-tested (26/26); published at `v0.1.0` on the XIOM registry.
> **Scope:** pure-XIOM Puppet-style declarative configuration-management
> MODEL: a manifest-parsing subset (class and resource declarations,
> attributes, `->`/`require`/`before`/`notify`/`subscribe` relationships), a
> module layout / metadata model, hiera lookup (first / unique / hash merge
> with `%{...}` interpolation), a catalog builder with dependency ordering, a
> deterministic apply / change simulation and a run report with
> applied / changed / failed / skipped accounting.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_contains`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test`, `xiom.io` and `xiom.string`.

## What it is

`xiom.puppet` is a pure, dependency-light model of the Puppet configuration
pipeline for XIOM programs. It parses a manifest subset into classes,
resources, attributes and relationship rows; validates module metadata; looks
up hierarchical data with first / unique / hash merge and `%{...}`
interpolation; builds a topologically ordered catalog for one class; and
applies it to an in-memory host state, producing a deterministic report with
`applied` / `changed` / `unchanged` / `skipped` / `failed` counts, provider
call counts and an ordered event log.

There is no network, no shell-out, no FFI and no file I/O. An apply is a pure
function of the parsed manifest and the host state: the same inputs always
produce the same run order, the same counters and the same events. A host
that really applies a catalog supplies the current state, reads the report
and drives real providers.

## Quick start

```xi
use xiom.puppet;
use xiom.io;

fn main() -> Int {
  let m = puppet_manifest_parse(
    "class web {\n" +
    "  package { 'nginx': ensure => present, }\n" +
    "  file { 'nginx.conf': ensure => present, notify => Service['nginx'], }\n" +
    "  service { 'nginx': ensure => present, }\n" +
    "}\n");
  match m {
    Ok(manifest) => {
      let c = puppet_catalog(&manifest, "web");
      match c {
        Ok(catalog) => {
          var state = puppet_state_new();
          let rep = puppet_apply(&catalog, &mut state);
          io.println(puppet_report_render(&rep));
        },
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

The report:

```
puppet report: total=3 applied=3 changed=3 unchanged=0 skipped=0 failed=0
provider_calls=3 refreshed=1
event: changed: package[nginx]
event: changed: file[nginx.conf]
event: refreshed: service[nginx]
```

## Model in one screen

- **Manifest** -- classes plus index-aligned parallel resource rows
  (`res_type` / `res_title`), attribute rows (`at_*`) and relationship rows
  (`rel_*`). `Vec[StructType]` is unusable in this compiler, so every row
  family is a separate homogeneous vector and the parser keeps the owners
  aligned.
- **Grammar subset** -- `class name { ... }` blocks with resource
  declarations `type { 'title': key => value, ... }` (quoted strings without
  escapes, bare identifiers, `Type['title']` references, trailing commas) and
  chain statements `A -> B -> C`. Metaparams `require` / `before` / `notify` /
  `subscribe` become relationship rows; every other attribute is carried on
  the resource.
- **Module metadata** -- `puppet_module_new("author-name", "x.y.z")` plus
  immutable `puppet_module_add_manifest` / `puppet_module_add_dep` builders;
  `puppet_module_validate` reports all errors (name / version format, manifest
  tokens, duplicates, self-dependency) and `puppet_module_files` returns the
  canonical layout (`metadata.json`, `manifests/init.pp`, one `.pp` per
  declared manifest).
- **Hiera** -- hierarchy levels in priority order plus data rows. `first`
  returns the highest-priority value, `unique` unions all values in priority
  order and dedupes, `hash` merges every strict descendant of a prefix with
  the first level winning per subkey.
- **Interpolation** -- `%{name}` / `%{::name}` substitute scope variables
  recursively (depth cap 8), `%%{` escapes a literal `%{`.
- **Catalog** -- one class's resources with a deterministic topological run
  order (smallest index wins ties), dependency edges (`require` -> target
  before owner, `before` / `->` -> owner before target, `notify`, `subscribe`)
  and refresh edges for the notification pair.
- **Apply** -- resources run once, in catalog order. A failed or skipped
  dependency skips the resource; `fail => true` simulates a provider failure;
  otherwise `ensure` (default `"present"`) is compared with the host state --
  a mismatch changes the resource, and a changed notify / subscribe partner
  refreshes an otherwise unchanged target.

`SPEC.md` carries the full semantics, error catalog, complexity notes and the
test map.

## API

| Function | Returns | Description |
|---|---|---|
| `puppet_manifest_parse(text)` | `Result[Manifest, Str]` | Parse the manifest subset. |
| `puppet_manifest_new()` | `Manifest` | Empty manifest. |
| `puppet_manifest_class_count/class_name/class_index` | `Int`/`Str`/`Int` | Class accessors. |
| `puppet_manifest_resource_count/type/title/ref/class` | `Int`/`Str`/`Int` | Resource accessors. |
| `puppet_manifest_attr(m, res, key)` | `Option[Str]` | First attribute value. |
| `puppet_manifest_attr_count/attr_key_at` | `Int`/`Str` | Attribute row accessors. |
| `puppet_manifest_rel_count/owner/kind/src_type/src_title/type/title` | mixed | Relationship row accessors. |
| `puppet_module_new(name, version)` | `ModuleMeta` | Empty module metadata. |
| `puppet_module_add_manifest/mm, name` | `ModuleMeta` | Immutable append. |
| `puppet_module_add_dep(mm, dep)` | `ModuleMeta` | Immutable append. |
| `puppet_module_validate(mm)` | `Vec[Str]` | All metadata errors. |
| `puppet_module_valid(mm)` | `Bool` | No errors. |
| `puppet_module_files(mm)` | `Vec[Str]` | Canonical relative layout. |
| `puppet_hiera_new()` | `Hiera` | Empty hierarchy. |
| `puppet_hiera_add_level(h, name)` | `Int` | Append a level (`-1` duplicate). |
| `puppet_hiera_set(h, level, key, value)` | `Bool` | Store a value (false unknown level). |
| `puppet_hiera_lookup_first(h, key, scope)` | `Result[Str, Str]` | Highest-priority value. |
| `puppet_hiera_lookup_unique(h, key, scope)` | `Result[Vec[Str], Str]` | Deduped union. |
| `puppet_hiera_lookup_hash(h, prefix, scope)` | `Result[Scope, Str]` | Merged descendants. |
| `puppet_scope_new/set/get/len/key_at/value_at` | mixed | Ordered key/value scope. |
| `puppet_interpolate(text, scope)` | `Result[Str, Str]` | `%{...}` expansion. |
| `puppet_catalog(m, class_name)` | `Result[Catalog, Str]` | Ordered catalog for one class. |
| `puppet_catalog_len/type/title/ref/order/attr` | mixed | Catalog accessors. |
| `puppet_catalog_edge_count/edge_from/edge_to` | `Int` | Dependency edges. |
| `puppet_catalog_refresh_count/refresh_from/refresh_to` | `Int` | Refresh edges. |
| `puppet_known_type(t)` | `Bool` | One of the seven supported types. |
| `puppet_state_new/get/set/len` | mixed | Host state. |
| `puppet_apply(c, state)` | `Report` | Apply and update the state. |
| `puppet_report_render(r)` | `Str` | Canonical two-header-line + event text. |

Supported resource types: `package`, `service`, `file`, `exec`, `user`,
`group`, `notify`.

`Report` fields: `total`, `applied`, `changed`, `unchanged`, `skipped`,
`failed`, `provider_calls`, `refreshed`, `events`. `total` always equals
`applied + skipped + failed`, and `applied` always equals
`changed + unchanged`.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom-puppet -TimeoutSec 60
```

Expected tail: 26 `[PASS]` lines, `xiom.puppet: all tests passed`, then
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Limitations (honest scope)

- **Model only.** Nothing on the machine changes: providers are simulated by
  the state comparison and the `fail` attribute. A real agent would drive
  providers from the report.
- **No network, no shell, no FFI, no file I/O.** Manifests are in-memory
  strings; there is no module loader.
- **Manifest subset, not the language.** Only class blocks, resource
  declarations, scalar attributes, resource references, metaparams and `->`
  chains parse. There are no defined types, functions, conditionals,
  variables, resource defaults, collectors, arrays, hashes, `include`,
  exported resources or node blocks. Quoted strings have no escape
  sequences.
- **Single-class catalogs.** `puppet_catalog` selects one class; references
  resolve inside it. Chains entirely outside the selected class are ignored.
- **Simplified apply semantics.** Each resource converges at most once per
  run, refreshed targets are promoted in place, and the failure model is a
  single boolean attribute rather than provider error hierarchies.
- **Hiera values are strings.** Hash merge is modeled as descendant keys
  under a prefix (`users.admin.uid`), not nested hashes; interpolation looks
  up scope variables only (`%{lookup(...)}` is out of subset).
