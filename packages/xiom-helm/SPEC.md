# xiom.helm -- Specification

Version: 0.1.0 (incubating, not published).
Modules: `xiom.helm` (`src/helm.xi`), `xiom.helm.base` (`src/helm_base.xi`),
`xiom.helm.release` (`src/helm_release.xi`), `xiom.helm.repo`
(`src/helm_repo.xi`), `xiom.helm.tmpl` (`src/helm_tmpl.xi`).
Pure XIOM, no FFI, no networking, no file I/O, no Kubernetes API.

## 1. Scope

- **Chart** -- parse, validate and render a Chart.yaml subset
  (`apiVersion`/`name`/`version`/`appVersion`/`description`).
- **Values** -- flat dotted-path scalars with Helm-style deep-merge
  precedence (`values_set`, `values_merge`, `values_resolve`).
- **Release** -- install/upgrade/rollback/uninstall state machine with a
  revision history, explicit statuses and validated transitions.
- **Repository index** -- parse, build and render an index.yaml subset plus
  entry lookups.
- **Template** -- a bounded, documented Go-template-ish subset:
  `{{ .Values.a.b }}`, `{{ .Release.Name }}`, `{{ if }}/{{ else }}/{{ end }}`
  and plain text.

Out of scope by design: Kubernetes APIs and objects, networking, file I/O,
YAML in general (only the documented subsets), dependency resolution,
hooks, capabilities, named templates, pipelines, functions, quoting/escapes
in templates, Unicode semantics beyond byte-exact handling.

## 2. Data models

```xi
pub type Chart = {
  api_version: Str;  // recognized keys: apiVersion/name/version/appVersion/description
  name: Str;
  version: Str;
  app_version: Str;  // free text, may be ""
  description: Str;  // free text, may be ""
}

pub type Values = {
  keys: Vec[Str];  // unique dotted paths, insertion order
  vals: Vec[Str];  // scalar text, index-aligned with keys
}

pub type Release = {
  name: Str;
  revisions: Vec[Int];  // 1-based revision numbers in order
  statuses: Vec[Str];   // per-revision status
  notes: Vec[Str];      // per-revision note
}

pub type RepoIndex = {
  api_version: Str;     // always "v1" in this version
  names: Vec[Str];      // five index-aligned columns
  versions: Vec[Str];
  app_versions: Vec[Str];
  descriptions: Vec[Str];
  urls: Vec[Str];       // canonical ", "-joined lists, possibly ""
}

pub type RenderContext = {
  vkeys: Vec[Str];  // flat Values copy
  vvals: Vec[Str];
  release_name: Str;
  release_namespace: Str;
  release_revision: Int;
  chart_api_version: Str;
  chart_name: Str;
  chart_version: Str;
  chart_app_version: Str;
  chart_description: Str;
}
```

Invariants: every parallel vector set is only pushed by one helper
(`_vpush`, `_rpush`, `_idx_push`), so lengths cannot drift; every reader
guards with a min-length helper. `Vec[StructType]` is unusable in this
compiler, so all collections are parallel homogeneous vectors.

## 3. Chart.yaml subset

Grammar:

```
document    = *( line )
line        = ws* ( comment / pair )
comment     = "#" byte*
pair        = key ws* ":" ws* value?
key         = byte except ':' and ws
value       = byte*                     ; trimmed; one pair of surrounding
                                        ; double quotes stripped
ws          = SP | TAB
EOL         = LF / CRLF / lone CR
```

Decisions (each covered by the suite):

1. Lines: LF, CRLF and lone CR all terminate; a final line without a
   terminator still counts; blank lines are skipped.
2. Comments: a line whose first non-whitespace byte is `#` is skipped.
   There are no trailing comments: everything after the first `:` is value
   text (a `#` there is literal).
3. `key: value` splits at the FIRST `:`; the key must be non-empty.
4. The recognized keys are exactly `apiVersion`, `name`, `version`,
   `appVersion`, `description`. Unknown keys are ignored
   (forward-compatible subset); duplicate keys are last-wins.
5. Surrounding double quotes are stripped when the value starts and ends
   with `"` and is at least 2 bytes; there are no escape sequences.
6. NUL input and input over `HELM_MAX_INPUT` (65536 bytes) are rejected.
7. `chart_parse` checks syntax only. `chart_validate` reports, in field
   order: apiVersion missing / not `v1` or `v2`; name missing / not a DNS
   name; version missing / not SemVer 2.0.0 (delegated to
   `xiom.misc.semver.semver_parse`, which also accepts a leading `v`).
8. Chart name rule (`helm_dns_name_valid`, max 253): 1..max_len bytes, only
   lowercase ASCII letters, digits, `-` and `.`; first and last bytes
   alphanumeric.

`chart_render` emits exactly five lines in the order apiVersion, name,
version, appVersion, description, LF separated, no trailing LF, raw values.
`parse -> render -> parse` is stable except that a value which itself
starts and ends with `"` loses one quote pair per round-trip.

## 4. Values model and deep merge

A values map is flat: path strings such as `image.tag` are keys, scalars are
`Str`. A "map" is implicit in the dotted path structure.

`helm_values_path_valid`: 1..256 bytes, 1..64 dot-separated non-empty
segments, bytes ASCII letters/digits/`_`/`-`/`/`.

`values_set(v, path, value)` returns a new map with these rules, applied in
base order:

- an entry equal to `path` is replaced in place;
- an entry strictly under `path` (descendant, e.g. `a.b` under `a`) is
  dropped;
- a strict ancestor of `path` (e.g. `a` when setting `a.b`) is dropped;
- the first dropped/replaced entry keeps the position; if nothing
  conflicted, `path` is appended;
- every other entry is copied unchanged.

`values_merge(base, overlay)` starts from a copy of `base` and applies every
overlay entry in overlay order with the `values_set` rules, so:

- an overlay path replaces its equal base path in place;
- an overlay subtree replaces a base scalar ancestor;
- an overlay scalar replaces a base subtree (all descendants dropped);
- overlay-only paths append in overlay order;
- neither input is modified.

`values_resolve(defaults, file, overrides)` is
`values_merge(values_merge(defaults, file), overrides)`, i.e. the
precedence chain **defaults <- file <- overrides**.

`values_render` emits `path: value` lines in insertion order, LF separated,
no trailing LF; an empty map renders as `""`.

## 5. Release state machine

Statuses (8): `unknown`, `pending-install`, `pending-upgrade`,
`pending-rollback`, `deployed`, `superseded`, `failed`, `uninstalled`.

| Operation | Requires latest status | Appends | On complete |
|---|---|---|---|
| `release_begin_install` | history empty | rev 1 `pending-install` | rev 1 `deployed` |
| `release_upgrade` | `deployed` or `failed` | rev n+1 `pending-upgrade` | new rev `deployed`; earlier `deployed` -> `superseded` |
| `release_rollback(target)` | n >= 1; target exists, != n, target status `deployed` or `superseded` | rev n+1 `pending-rollback` | new rev `deployed`; earlier `deployed` -> `superseded` |
| `release_complete` | latest is pending-* | -- | latest -> `deployed` |
| `release_fail` | latest is pending-* | -- | latest -> `failed`, note := reason |
| `release_uninstall` | latest `deployed` | -- | latest -> `uninstalled` |

- `release_create` starts with an empty history (`release_status` =
  `unknown`, `release_revision` = 0). Release names use
  `helm_dns_name_valid` with the 53-byte Helm limit.
- `release_complete` marks EVERY earlier `deployed` revision `superseded`
  (failed and superseded entries are untouched).
- History is capped at `HELM_RELEASE_MAX_REVISIONS` = 100; upgrade and
  rollback refuse with `release: revision limit reached`.
- `release_fail` replaces the failed revision's note with the reason;
  install/upgrade/rollback notes are otherwise preserved.
- Every operation returns a NEW release; the input is never modified.

## 6. Repository index subset

Grammar (flattened YAML subset, not general YAML):

```
document  = *( line )
line      = ws* ( comment / item / field )
comment   = "#" byte*
item      = "-" ws+ "name" ws* ":" ws* value?   ; starts a new entry
field     = key ws* ":" ws* value?              ; current entry
          | "apiVersion" ...                    ; before the first entry
          | "entries" ...                       ; before the first entry
key       = byte except ':' and ws
value     = byte*                                ; quote-stripped like charts
```

Decisions:

1. LF/CRLF/lone-CR lines; blank lines and full-line `#` comments skipped.
2. Before the first entry only `apiVersion: v1` and `entries:` are legal
   (`entries` must have an empty value); anything else is
   `repo: unexpected line: <line>`.
3. An entry starts with a `- name: X` line; any other `- key:` line is
   `repo: entry must start with name: <line>`.
4. Entry fields: `name`, `version`, `appVersion`, `description`, `urls`
   (last wins); unknown keys are ignored (so a real `digest:` line is
   tolerated), and a `urls` value is a comma-separated INLINE list --
   YAML sequence items (`- https://...`) are NOT part of this subset.
5. On flush, an entry must have non-empty name and version; name and
   version are validated with the same rules as charts. At most
   `HELM_MAX_ENTRIES` = 512 entries.
6. `urls` is canonicalized: comma-split, each token trimmed, empty tokens
   dropped, joined with `", "`.
7. NUL input and input over `HELM_MAX_INDEX_INPUT` (65536 bytes) are
   rejected.
8. `repo_index_render` emits `apiVersion: v1`, `entries:` and five lines per
   entry (`- name` at 2 spaces, fields at 4). `parse(render(idx))` round-trips
   all five columns for values without line breaks or surrounding quotes.

## 7. Template subset

Grammar:

```
template = *( text / action )
text     = any byte sequence not containing "{{"
action   = "{{" ws* command ws* "}}"       ; first "}}" closes
command  = "if" ws+ path                   ; path starts with '.'
         | "else"
         | "end"
         | path                            ; path starts with '.'
path     = "." segment *( "." segment )
segment  = 1..n of ASCII letters/digits/'_'/'-'/'/'
```

Decisions:

1. `{{` always opens an action; there is no escape syntax and no whitespace
   trimming (`{{-` is a syntax error). A literal `{{` cannot be emitted.
2. Plain text is copied verbatim. Actions are lexed and syntactically
   validated wherever they appear.
3. Paths are resolved against the context (leading `.` not part of the
   path):
   | Path | Result |
   |---|---|
   | `Values.<rest>` | the flat values lookup; a missing path is `""` |
   | `Values` alone | `""` |
   | `Release.Name/Namespace/Service` | context fields; `Service` = `"Helm"` |
   | `Release.Revision` | decimal revision, e.g. `"3"` |
   | `Release.IsInstall` / `IsUpgrade` | `"true"`/`"false"`, true install iff revision == 1 |
   | `Chart.ApiVersion/Name/Version/AppVersion/Description` | context fields |
   | any other root or unknown non-Values field | Err `tmpl: unknown context path: <path>` |
4. Truthiness (used by `if`): a resolved scalar is FALSE for `""`,
   `"false"` and `"0"`, TRUE for every other text (including `"true"`,
   `"no"`, `" "`).
5. `{{ if P }}A{{ else }}B{{ end }}`: `else` is optional; `if` requires a
   literal path (no `not`, no comparisons, no `else if`, no pipelines).
6. Nesting is allowed up to `TMPL_MAX_DEPTH` = 32 open `if` clauses; deeper
   nesting is Err. An unterminated `if` at the end is Err, as are `else`/
   `end` without an open `if`.
7. Suppressed branches are not resolved and not emitted: a syntax error
   inside an action still fails, but an unknown context path inside a
   branch that is not taken cannot fail, and no output is produced from it.
8. NUL input and input over `TMPL_MAX_INPUT` (65536 bytes) are rejected.

`tmpl_render` is a single deterministic left-to-right pass; it does not
allocate token streams and cannot recurse.

## 8. Limits

| Limit | Value | Applies to |
|---|---|---|
| `HELM_CHART_NAME_MAX` | 253 | chart names (releases: 53) |
| `HELM_MAX_INPUT` | 65536 bytes | chart parse |
| `HELM_MAX_INDEX_INPUT` | 65536 bytes | index parse |
| `HELM_MAX_ENTRIES` | 512 | index entries |
| `HELM_RELEASE_MAX_REVISIONS` | 100 | release history |
| `TMPL_MAX_INPUT` | 65536 bytes | template text |
| `TMPL_MAX_DEPTH` | 32 | nested `if` clauses |

## 9. Error catalog

Chart:

| Message | Trigger |
|---|---|
| `chart: NUL byte in input` | NUL in parse input |
| `chart: input too large` | input > 65536 bytes |
| `chart: expected ':' in line: <line>` | non-comment line without `:` |
| `chart: missing key in line: <line>` | empty key before `:` |
| `chart: missing apiVersion` / `chart: missing name` / `chart: missing version` | validate: field empty |
| `chart: unsupported apiVersion: <v>` | validate: not `v1`/`v2` |
| `chart: invalid chart name: <name>` | validate/new: DNS rule violated |
| `chart: invalid chart version: <version>` | validate/new: not SemVer |

Values:

| Message | Trigger |
|---|---|
| `values: malformed path: <path>` | set/merge path violates the path rule |
| `values: merge failed` | defensive final return in resolve |

Release:

| Message | Trigger |
|---|---|
| `release: invalid release name: <name>` | create: DNS rule or > 53 bytes |
| `release: install requires an empty revision history` | begin_install on non-empty |
| `release: upgrade requires an installed release` | upgrade with no revisions |
| `release: rollback requires an installed release` | rollback with no revisions |
| `release: complete requires a pending revision` | complete with no revisions |
| `release: fail requires a pending revision` | fail with no revisions |
| `release: uninstall requires an installed release` | uninstall with no revisions |
| `release: cannot upgrade from status: <s>` | latest not deployed/failed |
| `release: complete requires a pending status, got: <s>` | latest not pending |
| `release: fail requires a pending status, got: <s>` | latest not pending |
| `release: uninstall requires status deployed, got: <s>` | latest not deployed |
| `release: unknown revision: <n>` | rollback target absent |
| `release: cannot roll back to the current revision: <n>` | target == latest |
| `release: cannot roll back to revision <n> with status: <s>` | target not deployed/superseded |
| `release: revision limit reached` | history already 100 |

Repository index:

| Message | Trigger |
|---|---|
| `repo: NUL byte in input` | NUL in parse input |
| `repo: input too large` | input > 65536 bytes |
| `repo: expected ':' in line: <line>` | non-item line without `:` |
| `repo: expected ':' in entry line: <line>` | `- ...` item without `:` |
| `repo: missing key in line: <line>` | empty key |
| `repo: entry must start with name: <line>` | first field of an item is not `name` |
| `repo: entry missing name` / `repo: entry missing version` | flush: field empty |
| `repo: invalid chart name: <name>` / `repo: invalid chart version: <v>` | flush/add: invalid |
| `repo: unexpected line: <line>` | top-level line that is not apiVersion/entries |
| `repo: malformed entries line: <line>` | `entries: <non-empty>` |
| `repo: unsupported apiVersion: <v>` | top-level apiVersion not `v1` |
| `repo: entry limit reached` | 512 entries already |

Template:

| Message | Trigger |
|---|---|
| `tmpl: NUL byte in input` | NUL in template text |
| `tmpl: input too large` | input > 65536 bytes |
| `tmpl: unterminated action at offset <i>` | `{{` without `}}` |
| `tmpl: empty action at offset <i>` | `{{ }}` |
| `tmpl: unexpected action: <content>` | not if/else/end/path |
| `tmpl: if requires a path` | bare `{{ if }}` |
| `tmpl: if requires a path starting with '.': <content>` | `{{ if x }}` |
| `tmpl: malformed path: <content>` | bad path bytes/segments |
| `tmpl: unknown context path: <path>` | unknown root or non-Values field |
| `tmpl: unexpected else` / `tmpl: unexpected end` | no open if |
| `tmpl: unclosed if` | open if at end of template |
| `tmpl: if nesting limit exceeded` | depth > 32 |

## 10. API signatures

```xi
// xiom.helm.base
pub fn helm_streq(a: Str, b: Str) -> Bool
pub fn helm_has_nul(s: Str) -> Bool
pub fn helm_dns_name_valid(name: Str, max_len: Int) -> Bool
pub fn helm_semver_valid(v: Str) -> Bool
pub fn helm_values_path_valid(path: Str) -> Bool

// xiom.helm
pub fn chart_new(name: Str, version: Str) -> Result[Chart, Str]
pub fn chart_parse(text: Str) -> Result[Chart, Str]
pub fn chart_validate(c: &Chart) -> Vec[Str]
pub fn chart_valid(c: &Chart) -> Bool
pub fn chart_render(c: &Chart) -> Str
pub fn values_new() -> Values
pub fn values_len(v: &Values) -> Int
pub fn values_get(v: &Values, path: Str) -> Option[Str]
pub fn values_has(v: &Values, path: Str) -> Bool
pub fn values_entries(v: &Values) -> (Vec[Str], Vec[Str])
pub fn values_set(v: &Values, path: Str, value: Str) -> Result[Values, Str]
pub fn values_merge(base: &Values, overlay: &Values) -> Result[Values, Str]
pub fn values_resolve(defaults: &Values, file: &Values, overrides: &Values) -> Result[Values, Str]
pub fn values_render(v: &Values) -> Str

// xiom.helm.release
pub const HELM_RELEASE_NAME_MAX: Int
pub const HELM_RELEASE_MAX_REVISIONS: Int
pub const HELM_STATUS_UNKNOWN/PENDING_INSTALL/PENDING_UPGRADE/PENDING_ROLLBACK/DEPLOYED/SUPERSEDED/FAILED/UNINSTALLED: Str
pub fn release_create(name: Str) -> Result[Release, Str]
pub fn release_name(r: &Release) -> Str
pub fn release_history_len(r: &Release) -> Int
pub fn release_revision(r: &Release) -> Int
pub fn release_status(r: &Release) -> Str
pub fn release_status_at(r: &Release, i: Int) -> Str
pub fn release_note_at(r: &Release, i: Int) -> Str
pub fn release_is_deployed(r: &Release) -> Bool
pub fn release_count_status(r: &Release, status: Str) -> Int
pub fn release_status_known(s: Str) -> Bool
pub fn release_begin_install(r: &Release, note: Str) -> Result[Release, Str]
pub fn release_complete(r: &Release) -> Result[Release, Str]
pub fn release_upgrade(r: &Release, note: Str) -> Result[Release, Str]
pub fn release_rollback(r: &Release, target: Int, note: Str) -> Result[Release, Str]
pub fn release_fail(r: &Release, reason: Str) -> Result[Release, Str]
pub fn release_uninstall(r: &Release) -> Result[Release, Str]

// xiom.helm.repo
pub const HELM_MAX_ENTRIES: Int
pub const HELM_MAX_INDEX_INPUT: Int
pub fn repo_index_new() -> RepoIndex
pub fn repo_index_add(idx: &RepoIndex, name: Str, version: Str, app_version: Str, description: Str, urls: Str) -> Result[RepoIndex, Str]
pub fn repo_index_len(idx: &RepoIndex) -> Int
pub fn repo_index_name/version/app_version/description/urls(idx: &RepoIndex, i: Int) -> Str
pub fn repo_index_find(idx: &RepoIndex, name: Str, version: Str) -> Int
pub fn repo_index_count_name(idx: &RepoIndex, name: Str) -> Int
pub fn repo_index_parse(text: Str) -> Result[RepoIndex, Str]
pub fn repo_index_render(idx: &RepoIndex) -> Str

// xiom.helm.tmpl
pub const TMPL_MAX_INPUT: Int
pub const TMPL_MAX_DEPTH: Int
pub fn tmpl_context_new() -> RenderContext
pub fn tmpl_context_basic(vkeys: &Vec[Str], vvals: &Vec[Str], release_name: Str) -> RenderContext
pub fn tmpl_render(text: Str, ctx: &RenderContext) -> Result[Str, Str]
pub fn tmpl_render_values(text: Str, vkeys: &Vec[Str], vvals: &Vec[Str], release_name: Str) -> Result[Str, Str]
```

Complexity: charts and indexes are O(input length); values are O(n^2) in
the map size for deep sets/merges (linear scans), fine for model-sized
inputs; template rendering is O(template length) with Str concatenation and
is bounded by `TMPL_MAX_INPUT`.

## 11. Test plan

`tests/test_conformance.xi` (module `helm_tests`) runs 23 named checks and
`main` returns the failure count (0 = green).

| # | Check | Semantics pinned |
|---|---|---|
| t01 | chart_new | defaults, render text, validity, invalid name/version errors |
| t02 | chart_parse ok | fields, quotes, comments, unknown keys ignored, valid |
| t03 | chart_parse syntax errors | missing `:` and missing key |
| t04 | chart_validate | all errors in field order; invalid chart rejected |
| t05 | chart round-trip | parse -> render -> parse stable |
| t06 | values basics | set/get/has/len/entries, malformed-path Err |
| t07 | values deep set | subtree replace, ancestor replace, first position kept |
| t08 | values merge/resolve | overlay wins, ancestor scalar replaced, inputs untouched |
| t09 | values errors/render | malformed overlay, canonical render, empty map, fresh copies |
| t10 | release install | unknown -> pending-install -> deployed; invalid repeats |
| t11 | release upgrade/rollback | supersede, new revision, history kept |
| t12 | release failures | rollback errors, failed status, upgrade from failed |
| t13 | release uninstall | uninstall, empty-history errors, range-safe accessors |
| t14 | release cap | history stops at 100; upgrade refuses |
| t15 | repo add | columns, find/count, validation errors, empty render |
| t16 | repo parse ok | two entries, quotes, comments, unknown keys, empty index |
| t17 | repo errors | entry shape, missing/invalid fields, bad top level |
| t18 | repo round-trip | render -> parse preserves all five columns |
| t19 | tmpl substitution | text, Values/Release/Chart, missing -> "", defaults |
| t20 | tmpl if/else | truthiness, nesting, suppressed branches |
| t21 | tmpl errors | full syntax/context error catalog |
| t22 | tmpl caps | depth limit enforced, depth-1 works |
| t23 | tmpl convenience | flat columns + release name; render_values |

All Str comparisons go through `str_compare`; Vec element reads use typed
locals; tuple-field borrows are bound to locals before `&Vec` parameters.

## 12. Compiler notes (v0.62.2)

- **Child module importing its parent module is not resolved** by the
  installed compiler (probe: `use xiom.probe;` inside module
  `xiom.probe.child` leaves `probe` unusable and unqualified parent symbols
  undefined). Shared primitives therefore live in the separate sibling
  module `xiom.helm.base`, which the other modules import successfully.
- `Vec[StructType]` is unsupported: all collections are parallel
  homogeneous vectors with a single push site per family.
- `Ok`/`Err` for struct payloads are constructed only in leaf helpers
  (`_chart_ok`, `_values_ok`, `_rel_ok`, `_repo_ok`, `_str_ok`).
- Str equality goes through `xiom.string.compare.str_compare`; bytes are
  widened and masked (`(byte_at(...) as Int) & 0xFF`).
- No indexed `Vec[fn]` dispatch, no lambdas, no `mut` match bindings; every
  match is exhaustive.
- `&mut Vec` parameters are only used in the three push helpers and every
  call site passes an explicit `&mut`.
- Rendering uses `Str` concatenation, never `sb_to_str`.

## 13. Known limitations

- No Kubernetes interaction of any kind, no networking, no file I/O.
- Chart/values/index parsing covers only the documented flat subsets: no
  general YAML (no nested maps beyond dotted paths, no sequences, no
  anchors, no multiline scalars, no escapes).
- No `Chart.lock`, dependencies, hooks, capabilities, CRDs or release
  storage.
- Values are scalars only: no lists, no booleans/ints types (everything is
  text), no schema files.
- The template subset has no functions, pipelines, variables, `range`,
  `with`, `define`/`template`, `not`, comparisons, `else if`, whitespace
  trimming or escape syntax; missing Values paths render as `""` (no
  `missingkey=error` mode).
- Suppressed `if` branches are not resolved, so context-path errors there
  are invisible by design.
- Release history keeps only the latest 100 revisions and has no rollback
  target auto-selection; an uninstalled release cannot be reinstalled.
- The repository index subset uses an inline comma-separated `urls` field,
  not the YAML sequence used by real index.yaml files.
