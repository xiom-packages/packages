# xiom.helm

> **Status:** `incubating` -- conformance-tested (23/23); not yet published.
> **Scope:** pure in-memory Helm model: chart manifest subset, release
> install/upgrade/rollback state machine, repository index subset, values
> deep-merge precedence and a bounded Go-template-ish renderer.
> No Kubernetes API, no networking, no file I/O.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.compare`, `xiom.convert` and `xiom.misc.semver`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.helm` is a deterministic, IO-free model of the parts of Helm that do
not need a cluster: what a chart says about itself, how layered values
resolve, how a release moves through its statuses, what a repository index
contains, and how a minimal template renders into manifest text. Every
function takes and returns values; nothing mutates shared state.

Modules (all in `src/`):

| Module | Responsibility |
|---|---|
| `xiom.helm` | `Chart` (Chart.yaml subset) and `Values` (flat dotted paths) |
| `xiom.helm.base` | shared limits, byte helpers and validators |
| `xiom.helm.release` | `Release` revision history and status transitions |
| `xiom.helm.repo` | `RepoIndex` subset parse/render and lookups |
| `xiom.helm.tmpl` | bounded `{{ }}` template lexer/renderer |

## Source formats (short version)

Chart.yaml subset (`apiVersion`, `name`, `version`, `appVersion`,
`description`; unknown keys ignored):

```yaml
apiVersion: v2
name: web
version: 1.2.3
appVersion: "2.0"
description: A web server chart
```

Values are built programmatically as flat dotted paths; merging follows
Helm semantics: an overlay path replaces an equal path in place, drops the
path's descendants, and replaces a strict ancestor scalar with the subtree.

Repository `index.yaml` subset (`apiVersion: v1`, `entries:`, flat stanzas,
comma-separated inline `urls`):

```yaml
apiVersion: v1
entries:
  - name: nginx
    version: 1.2.3
    appVersion: "1.19.0"
    description: A web server
    urls: https://a/nginx-1.2.3.tgz, https://b/nginx-1.2.3.tgz
```

Template subset -- plain text plus `{{ .Values.a.b }}`, `{{ .Release.Name }}`,
`{{ if .Values.x }}/{{ else }}/{{ end }}`:

```xi
tmpl_render("image={{ .Values.image }}:{{ .Values.tag }}", &ctx);
```

## API

### `xiom.helm` -- chart and values

| Function | Returns | Description |
|---|---|---|
| `chart_new(name, version)` | `Result[Chart, Str]` | apiVersion `v2`, empty optionals; validates name/version. |
| `chart_parse(text)` | `Result[Chart, Str]` | Parse the Chart.yaml subset; syntax only. |
| `chart_validate(c)` | `Vec[Str]` | ALL errors in field order (apiVersion, name, version); empty = valid. |
| `chart_valid(c)` | `Bool` | True when `chart_validate` finds nothing. |
| `chart_render(c)` | `Str` | Canonical five-key text; parse -> render -> parse is stable. |
| `values_new()` | `Values` | Empty values map. |
| `values_get(v, path)` | `Option[Str]` | Byte-exact lookup; `None` when absent. |
| `values_has(v, path)` | `Bool` | True when the path exists. |
| `values_len(v)` | `Int` | Entry count. |
| `values_entries(v)` | `(Vec[Str], Vec[Str])` | Fresh `(keys, vals)` copies in insertion order. |
| `values_set(v, path, value)` | `Result[Values, Str]` | Deep set in a new map; malformed path Err. |
| `values_merge(base, overlay)` | `Result[Values, Str]` | Later-source-wins deep merge; inputs untouched. |
| `values_resolve(defaults, file, overrides)` | `Result[Values, Str]` | The precedence chain defaults <- file <- overrides. |
| `values_render(v)` | `Str` | Canonical `path: value` lines in insertion order. |

### `xiom.helm.release` -- state machine

| Function | Returns | Description |
|---|---|---|
| `release_create(name)` | `Result[Release, Str]` | Empty history (status `unknown`); validates the name (<= 53). |
| `release_begin_install(r, note)` | `Result[Release, Str]` | Revision 1, status `pending-install`; empty history required. |
| `release_upgrade(r, note)` | `Result[Release, Str]` | Revision n+1, `pending-upgrade`; from `deployed`/`failed`. |
| `release_rollback(r, target, note)` | `Result[Release, Str]` | Revision n+1, `pending-rollback`; target deployed/superseded. |
| `release_complete(r)` | `Result[Release, Str]` | Latest pending -> `deployed`; earlier deployed -> `superseded`. |
| `release_fail(r, reason)` | `Result[Release, Str]` | Latest pending -> `failed`; note becomes `reason`. |
| `release_uninstall(r)` | `Result[Release, Str]` | Latest deployed -> `uninstalled` (no new revision). |
| `release_status(r)` / `release_revision(r)` | `Str` / `Int` | Latest status (`unknown` when empty) / latest revision (0). |
| `release_status_at(r, i)` / `release_note_at(r, i)` | `Str` | Range-safe per-index accessors ("" out of range). |
| `release_history_len(r)` | `Int` | Number of revisions. |
| `release_count_status(r, status)` | `Int` | History entries with exactly that status. |
| `release_is_deployed(r)` | `Bool` | Latest revision is `deployed`. |
| `release_status_known(s)` | `Bool` | True for the eight documented status names. |

### `xiom.helm.repo` -- repository index

| Function | Returns | Description |
|---|---|---|
| `repo_index_new()` | `RepoIndex` | Empty index, apiVersion `v1`. |
| `repo_index_add(idx, name, version, appVersion, description, urls)` | `Result[RepoIndex, Str]` | Append one entry; urls comma-split and canonicalized. |
| `repo_index_parse(text)` | `Result[RepoIndex, Str]` | Parse the documented subset; precise errors. |
| `repo_index_render(idx)` | `Str` | Canonical subset text; round-trips through parse. |
| `repo_index_len(idx)` | `Int` | Entry count. |
| `repo_index_name/version/app_version/description/urls(idx, i)` | `Str` | Range-safe column accessors ("" out of range). |
| `repo_index_find(idx, name, version)` | `Int` | First exact match index, or -1. |
| `repo_index_count_name(idx, name)` | `Int` | Entries with that chart name. |

### `xiom.helm.tmpl` -- bounded renderer

| Function | Returns | Description |
|---|---|---|
| `tmpl_context_new()` | `RenderContext` | Defaults: no values, name "", namespace `default`, revision 1. |
| `tmpl_context_basic(keys, vals, release_name)` | `RenderContext` | Context from flat values columns. |
| `tmpl_render(text, ctx)` | `Result[Str, Str]` | Render the documented subset; syntax/context errors are Err. |
| `tmpl_render_values(text, keys, vals, release_name)` | `Result[Str, Str]` | Convenience render with a basic context. |

`RenderContext` exposes `.Values.*` (missing path -> `""`), `.Release.Name`,
`.Release.Namespace`, `.Release.Revision`, `.Release.Service`, `.Release.IsInstall`,
`.Release.IsUpgrade` and `.Chart.{ApiVersion,Name,Version,AppVersion,Description}`.

## Usage

```xi
use xiom.helm;
use xiom.helm.repo;
use xiom.helm.tmpl;

let cr = chart_parse("apiVersion: v2\nname: web\nversion: 1.2.3");
match cr {
  Ok(chart) => {
    if chart_valid(&chart) {
      var v = values_new();
      let s1 = values_set(&v, "image", "nginx");
      // ... build the release context and render
    }
  },
  Err(e) => { /* precise "chart: ..." message */ },
}
```

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 23 `[PASS]` lines, then `xiom.helm: all tests passed`, exit 0.

## Install / publish

```
xiom pkg install xiom.helm@0.1.0     # consumer
xiom pkg publish                      # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
