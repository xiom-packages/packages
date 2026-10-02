# xiom.chef

> **Status:** `incubating` -- conformance-tested (26/26); published at `v0.1.0` on the XIOM registry.
> **Scope:** pure-XIOM Chef-style configuration-management MODEL: cookbook /
> recipe / resource declarations, resource-collection compile phase, runlist
> and role expansion, attribute precedence (default/normal/override), explicit
> provider dispatch, notification/subscription timing (immediate vs delayed)
> and a deterministic idempotence / converge report.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_starts_with`,
> `xiom.string.str_ends_with`, `xiom.string.index_of`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.chef` is a pure, dependency-light model of the Chef configuration
pipeline for XIOM programs. It declares cookbooks, recipes and resources; it
expands a runlist (including nested roles) into an ordered resource
collection; it resolves layered attributes; it dispatches each resource type
to a provider by explicit case analysis; and it converges the collection into
a deterministic report with `updated` / `unchanged` / `skipped` counts,
provider-call counts and immediate/delayed notification counters.

There is no network, no shell-out, no FFI and no file I/O. A converge run is a
pure function of the declared cookbook, role set and runlist: the same inputs
always produce the same collection and the same report. A host that really
converges a machine supplies the `satisfied` resource attribute (whether live
state already matches) and uses the report to drive real providers.

## Quick start

```xi
use xiom.chef;
use xiom.io;

fn main() -> Int {
  var cb = chef_cookbook_new("site");
  let web = chef_add_recipe(&mut cb, "web");
  let pkg = chef_add_resource(&mut cb, web, "package", "nginx", "install");
  chef_add_resource(&mut cb, web, "service", "nginx", "restart");
  chef_notifies(&mut cb, pkg, "restart", "service[nginx]", "immediate");

  let rs = chef_roleset_new();
  var runlist = Vec[Str].new();
  runlist.push("recipe[web]");

  let r = chef_converge(&cb, &rs, &runlist);
  match r {
    Ok(rep) => { io.println(chef_report_render(&rep)); },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

The report:

```
chef report: total=2 updated=2 unchanged=0 skipped=0
provider_calls=2 immediate=1 delayed=0
event: updated: package[nginx]
event: immediate: package[nginx] -> service[nginx]
event: updated: service[nginx]
```

## Model in one screen

- **Cookbook** -- recipe names plus index-aligned parallel resource rows
  (`res_type` / `res_name` / `res_action`), attribute rows, notification rows
  and subscription rows. `Vec[StructType]` is unusable in this compiler, so
  every row family is a separate homogeneous vector and builders keep the
  owners aligned.
- **Runlist expansion** -- `recipe[name]`, `role[name]` or a bare recipe name;
  roles expand recursively in declaration order with cycle detection, a
  nesting cap of 32 and an expanded-recipe cap of 512.
- **Compile** -- expand the runlist, copy each recipe's resources in runlist
  order and declaration order, rebind owners to collection indices, validate
  providers and validate every notification target / subscription source.
- **Attributes** -- precedence from lowest to highest: `default` (0),
  `normal` (1), `override` (2). Merge order is defaults, then normal, then
  overrides; a higher level always beats a lower one; at equal levels the
  later assignment wins; a key keeps the position of its first insertion.
- **Provider dispatch** (explicit case analysis): `package` -> `package`,
  `service` -> `service`, `group` -> `group`, `user` -> `user`,
  `file`/`template`/`cookbook_file`/`remote_file`/`directory` -> `file`,
  `execute`/`bash`/`script` -> `execute`; anything else is an error. A
  resource attribute `provider` overrides the type dispatch.
- **Converge** -- resources run in collection order, each at most once.
  `action == "nothing"` is skipped and `satisfied == "true"` is unchanged
  unless a notification forces the resource. An update fires its immediate
  notifications right away and queues its delayed ones FIFO for a final pass;
  a delivery to an already-converged unchanged/skipped resource promotes it to
  updated (one extra provider call), while a delivery to an already-updated
  resource only bumps the fired counter. Deliveries never rebroadcast the
  target's own notifications, so notification cycles are bounded.

`SPEC.md` carries the full semantics, error catalog and test map.

## API

| Function | Returns | Description |
|---|---|---|
| `chef_cookbook_new(name)` | `Cookbook` | Empty cookbook. |
| `chef_add_recipe(cb, name)` | `Int` | Append a recipe; returns its index. |
| `chef_add_resource(cb, recipe, typ, name, action)` | `Int` | Append a resource owned by a recipe index. |
| `chef_set_attr(cb, res, key, value)` | `--` | Append a resource attribute (`satisfied`, `provider` are special). |
| `chef_notifies(cb, res, action, target, timing)` | `Bool` | Append a notification; false on unknown timing. |
| `chef_subscribes(cb, sub, action, source, timing)` | `Bool` | Append a subscription (inverse notification view). |
| `chef_roleset_new()` | `RoleSet` | Empty role set. |
| `chef_add_role(rs, name)` | `Int` | Append a role; returns its index. |
| `chef_role_entry(rs, role, entry)` | `--` | Append one runlist entry to a role. |
| `chef_attrs_new()` | `Attrs` | Empty attribute set. |
| `chef_attrs_set(a, key, value, level)` | `Bool` | Set at `"default"` / `"normal"` / `"override"`. |
| `chef_attrs_get(a, key)` | `Option[Str]` | Resolved value. |
| `chef_attrs_level(a, key)` | `Int` | Precedence level, or -1 when absent. |
| `chef_attrs_merge(base, overlay)` | `Attrs` | Documented precedence merge. |
| `chef_attrs_resolve(defaults, normal, overrides)` | `Attrs` | The three-source chain. |
| `chef_provider_for(typ)` | `Result[Str, Str]` | Type dispatch table. |
| `chef_resource_provider(cb, res)` | `Result[Str, Str]` | `provider` override or type dispatch. |
| `chef_runlist_expand(cb, rs, runlist)` | `Result[Vec[Str], Str]` | Ordered recipe names. |
| `chef_compile(cb, rs, runlist)` | `Result[Collection, Str]` | Validated resource collection. |
| `chef_collection_len(col)` | `Int` | Resource count. |
| `chef_collection_type/name/action/recipe(col, i)` | `Str` | Row accessors ("" out of range). |
| `chef_collection_attr(col, i, key)` | `Option[Str]` | Attribute lookup. |
| `chef_converge(cb, rs, runlist)` | `Result[Report, Str]` | Compile + converge. |
| `chef_converge_collection(col)` | `Result[Report, Str]` | Converge a compiled collection. |
| `chef_report_render(r)` | `Str` | Canonical two-header-line + event text. |

`Report` fields: `total`, `updated`, `unchanged`, `skipped`, `provider_calls`,
`immediate_fired`, `delayed_fired`, `events`. `total` always equals
`updated + unchanged + skipped`.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom-chef -TimeoutSec 60
```

Expected tail: 26 `[PASS]` lines, `xiom.chef: all tests passed`, then
`port: PASS (passed=26 failed=0 program_exit=0 exit=0)`.

## Limitations (honest scope)

- **Model only.** Providers are names, not implementations: no package is
  installed, no service is restarted, nothing touches the machine. The host
  supplies `satisfied` and executes the plan the report describes.
- **No network, no shell, no FFI, no file I/O.** Cookbooks are built
  programmatically with the builder API; there is no cookbook loader.
- **Simplified notification semantics.** Deliveries do not rebroadcast the
  target's own notifications (bounded convergence), and a resource converges
  at most once per run; a real Chef client re-runs notified resources and can
  cascade. The rule set is documented exactly in `SPEC.md` section 7.
- **No encrypted data bags, no search, no environments, no policyfiles.** The
  placeholder's `knife` / `data_bag` scope is intentionally out of model.
- **Attribute syntax is programmatic.** There is no attribute-file parser and
  no `node[...]` expression language.
