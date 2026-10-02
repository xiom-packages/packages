# xiom.puppet -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.puppet` (`src/puppet.xi`). Pure XIOM, no FFI, no network, no
shell, no file I/O.

## 1. Scope

A pure, in-memory model of the Puppet configuration pipeline:

- manifest parsing subset: class declarations, resource declarations with
  titles and attributes, relationship metaparams
  (`->` chains, `require`, `before`, `notify`, `subscribe`);
- module layout and metadata model (`puppet_module_*`);
- hiera lookup: hierarchy levels, `first` / `unique` / `hash` merge behaviors,
  `%{...}` interpolation subset (`puppet_hiera_*`, `puppet_interpolate`);
- catalog apply model: dependency ordering, change simulation,
  idempotence (`puppet_catalog`, `puppet_apply`, `puppet_state_*`);
- report and events: applied / changed / unchanged / skipped / failed
  accounting and a run report (`puppet_report_render`).

Out of scope by design: a real agent, providers, module loading from disk,
Facter, environments, exported resources, resource defaults and collectors,
the expression language (variables, conditionals, functions, lambdas), node
classification, and every form of network, shell or file access.

## 2. Data model

```xi
pub type Manifest = {
  classes: Vec[Str];        // class names, declaration order
  cls_owner: Vec[Int];      // resource row -> class index
  res_type: Vec[Str];       // "package", "service", "file", ...
  res_title: Vec[Str];
  rel_owner: Vec[Int];      // metaparam row -> declaring resource index; -1 chain
  rel_kind: Vec[Str];       // "require" / "before" / "notify" / "subscribe" / "chain"
  rel_src_type: Vec[Str];   // chain source type (metaparam rows copy the owner type)
  rel_src_title: Vec[Str];  // chain source title (metaparam rows copy the owner title)
  rel_type: Vec[Str];       // target reference type
  rel_title: Vec[Str];      // target reference title
  at_owner: Vec[Int];       // attribute row -> resource index
  at_key: Vec[Str];
  at_value: Vec[Str];
}

pub type ModuleMeta = {
  name: Str;                // "author-name"
  version: Str;             // "major.minor.patch"
  deps: Vec[Str];
  manifests: Vec[Str];
}

pub type Hiera = {
  levels: Vec[Str];         // hierarchy level names, index 0 = highest priority
  h_level: Vec[Int];        // data row -> level index
  h_key: Vec[Str];
  h_value: Vec[Str];
}

pub type Scope = { keys: Vec[Str]; values: Vec[Str]; }

pub type Catalog = {
  res_type: Vec[Str];
  res_title: Vec[Str];
  at_owner: Vec[Int]; at_key: Vec[Str]; at_value: Vec[Str];
  order: Vec[Int];          // position -> resource index (topological run order)
  edge_from: Vec[Int]; edge_to: Vec[Int];   // dependency edges
  rf_from: Vec[Int]; rf_to: Vec[Int];       // refresh edges
}

pub type State = { keys: Vec[Str]; values: Vec[Str]; }  // "type[title]" -> ensure

pub type Report = {
  total: Int; applied: Int; changed: Int; unchanged: Int;
  skipped: Int; failed: Int; provider_calls: Int; refreshed: Int;
  events: Vec[Str];
}
```

`Vec[StructType]` is unusable in this compiler (v0.62.2), so every row family
is a separate homogeneous parallel vector; builders and the parser keep the
owners aligned. Invariants:

- every resource row's `cls_owner` names a valid class index,
- every attribute row's `at_owner` names a valid resource index,
- every relationship row is either a metaparam row (`rel_owner` names a valid
  resource index) or a chain row (`rel_owner == -1`, source fields filled),
- `Scope.keys` contains no duplicates (last write wins in place),
- `Report.total == applied + skipped + failed` and
  `Report.applied == changed + unchanged`.

## 3. Manifest grammar subset and parser

```
manifest     = *( ws / comment / class_decl )
class_decl   = "class" ws+ ident ws* "{" body "}"
body         = *( ws / comment / resource_decl / chain )
resource_decl= ident ws* "{" ws* title ws* ":" attrs "}"
attrs        = *( attr ws* [ "," ] )          ; trailing comma allowed,
                                              ; empty body allowed
attr         = ident ws* "=>" ws* value
value        = quoted / bare / ref
ref          = ident ws* "[" ws* title ws* "]"
chain        = ref ws* "->" ws* ref *( ws* "->" ws* ref )
title        = quoted / ident                 ; non-empty
quoted       = "'" *( byte except "'", LF, CR ) "'"   ; no escapes
bare         = value-byte +                    ; byte > SP except
                                               ; , { } [ ] : = > # ' "
comment      = "#" *( byte except LF )
ws           = SP / TAB / LF / CR
ident        = [A-Za-z_][A-Za-z0-9_]*
```

- A NUL byte anywhere in the input is rejected up front (so no rendered value
  can carry a NUL sentinel).
- Classes are declared at top level only; a class name is unique or
  `puppet: duplicate class: <name>` is returned.
- Metaparam values must be resource references
  (`<Type>['<title>']` or with a bare title); a scalar is
  `puppet: parse error at <i>: expected resource reference for metaparam:
  <key>`.
- All other attributes keep the attribute text as written (a reference value
  is stored as `Type['title']`).
- Every parse error except the duplicate-class error is
  `puppet: parse error at <offset>: <detail>` where `<detail>` is one of:
  `expected class declaration`, `expected class name`, `expected identifier`,
  `expected '{'`, `expected '{' or '[' after '<word>'`, `expected ':' after
  title`, `expected '=>'`, `expected ',' or '}'`, `expected attribute value`,
  `expected resource reference`, `expected resource title`,
  `expected '[' after '<type>'`, `expected ']'`, `expected resource reference
  for metaparam: <key>`, `unterminated string`, `unterminated class body`,
  `unterminated resource body`, `unterminated chain`.
- Bare titles are identifiers; quoted titles are byte-exact and may contain
  spaces, dots and dashes (`'nginx.conf'`, `'my app'`).
- Chain statements record one relationship row per arrow; the source of the
  first row is the left reference and each subsequent row starts where the
  previous ended (`a -> b -> c` yields `a -> b` and `b -> c`).

The parser is a single pass over the input; building the manifest is linear in
input length except duplicate-class checks, which scan the class list
(O(input * classes)).

## 4. Module metadata model

- `puppet_module_new(name, version)` creates an empty `ModuleMeta`.
- `puppet_module_add_manifest` / `puppet_module_add_dep` return a new
  `ModuleMeta` with the entry appended; the input is untouched.
- `puppet_module_validate` returns ALL errors in this order:
  - name: `puppet: malformed module name: <name>` unless it is exactly two
    non-empty lowercase words separated by one dash (`author-name`),
  - version: `puppet: malformed module version: <version>` unless it is
    exactly three non-empty ASCII digit runs separated by dots,
  - per manifest token: `puppet: malformed manifest name: <n>` unless it is
    `[a-z][a-z0-9_]*`; a token seen before is
    `puppet: duplicate manifest: <n>`,
  - per dependency: `puppet: malformed dependency name: <d>`,
    `puppet: module depends on itself: <d>`, or
    `puppet: duplicate dependency: <d>`.
- `puppet_module_valid` is true when the error vector is empty.
- `puppet_module_files` returns `metadata.json`, `manifests/init.pp`, then
  `manifests/<name>.pp` for every declared manifest other than `init` (in
  declaration order).

## 5. Interpolation

`puppet_interpolate(text, scope)` expands:

- `%{name}` and `%{::name}`: look up `name` in `scope` (a leading `::`
  accesses the same flat scope) and substitute recursively, at most 8 levels
  deep;
- `%%{`: a literal `%{` (the escape is consumed and the result is not
  re-scanned);
- any other byte is copied literally.

Variable names are non-empty and consist of letters, digits, underscores,
dots and dashes, starting with a letter or underscore. Errors:

| Message | When |
|---|---|
| `puppet: interpolation: unknown variable: <name>` | no scope entry |
| `puppet: interpolation: malformed variable name: <raw>` | empty or bad name |
| `puppet: interpolation: unterminated variable reference in: <text>` | no `}` |
| `puppet: interpolation: depth exceeded in: <text>` | more than 8 expansions |

## 6. Hiera

A `Hiera` is a list of level names in priority order (index 0 is consulted
first) plus data rows. `puppet_hiera_add_level` appends (returns the index, or
-1 for a duplicate). `puppet_hiera_set` stores `key = value` at a level (the
last write at that level wins; unknown level returns false and stores
nothing). All lookups interpolate values against the supplied `Scope`.

- **first** (`puppet_hiera_lookup_first`): scan levels in index order; the
  value of the first level that defines `key` wins. Missing:
  `puppet: hiera: no value for key: <key>`.
- **unique** (`puppet_hiera_lookup_unique`): collect `key` from every level
  in index order, interpolate each, drop byte-exact duplicates keeping the
  first occurrence. Missing: same message as first.
- **hash** (`puppet_hiera_lookup_hash`): collect every data key that is a
  strict descendant of `prefix` (`<prefix>.<sub>`, nested descendants
  included); a key equal to `prefix` itself is ignored. The first level
  defining a full key wins; entries keep first-insertion order and the
  returned keys are the suffixes with the prefix stripped. Missing:
  `puppet: hiera: no hash values for key: <prefix>`.

`Scope` is also the interpolation variable scope: `puppet_scope_set`
replaces in place (first position kept) or appends; `puppet_scope_get`
returns `Option[Str]`.

## 7. Catalog

`puppet_catalog(manifest, class_name)`:

1. Find the class (`puppet: unknown class: <name>`).
2. Copy the class's resources in declaration order; rebind `at_owner` to
   catalog indices. Validate the type against the seven known types
   (`puppet: unknown resource type: <t>`) and reject a duplicate
   `type[title]` (`puppet: duplicate resource: <type>[<title>]`).
3. Resolve relationship rows into edges:
   - metaparam on an in-class resource:
     - `require`: target -> owner,
     - `before`: owner -> target,
     - `notify`: owner -> target, refresh,
     - `subscribe`: target -> owner, refresh;
     the target must resolve in-class, else
     `puppet: unresolved reference: <ref>` (reference types compare ASCII
     case-insensitively, so `Package['x']` matches declared `package { 'x' }`;
     titles are byte-exact);
   - chain row: resolve both endpoints; when neither resolves in-class the
     row is ignored (it belongs to another class), when exactly one resolves
     the missing one is an unresolved-reference error; otherwise
     source -> target.
   - Duplicate `(from, to)` edges are collapsed; the refresh flag is OR-ed.
4. Topologically sort with Kahn's algorithm, always picking the smallest
   unplaced catalog index with indegree 0, so the order is deterministic and
   stable. A remaining resource means a cycle:
   `puppet: dependency cycle: <type>[<title>]` (the smallest-index resource
   still unplaced).

## 8. Apply

`puppet_apply(catalog, state)` runs resources in catalog order, each at most
once, updating `state` in place:

1. **Blocked**: any dependency (`edge_from -> this`) whose status is failed or
   skipped skips this resource with event
   `skipped: <ref> (dependency failed)`.
2. **Failed**: attribute `fail == "true"` marks the resource failed with
   event `failed: <ref>` and changes no state (simulated provider failure).
3. Otherwise compare the desired ensure value (attribute `ensure`, default
   `"present"`) with the current state (`None` = absent):
   - different -> **changed**: one provider call, state set to the desired
     value, event `changed: <ref>`;
   - equal but a refresh is pending -> **refreshed**: one provider call, the
     refreshed counter moves, event `refreshed: <ref>`;
   - equal and no refresh -> **unchanged**, event `unchanged: <ref>`.
4. A changed resource (either kind) marks the targets of its refresh edges as
   pending. Refresh edges come from `notify` (owner changes -> target
   refreshes) and `subscribe` (source changes -> subscriber refreshes).
   Because edges also order the run, the promotion is deterministic; a
   resource with a pending refresh that also fails or is blocked is not
   promoted.

Counters: `total` resources, `applied = changed + unchanged`, `skipped`,
`failed`, `provider_calls` (one per changed/refreshed resource), `refreshed`.
The event log is appended in run order. Idempotence: after a successful run
with no `fail` attributes, a second apply against the updated state reports
`changed == 0` and `provider_calls == 0`.

Report rendering (`puppet_report_render`), LF-separated with no trailing LF:

```
puppet report: total=<T> applied=<A> changed=<C> unchanged=<U> skipped=<S> failed=<F>
provider_calls=<P> refreshed=<R>
event: <event>
event: <event>
...
```

The two header lines are always present; an empty catalog renders exactly
those two.

## 9. Error catalog

| Message | Raised by |
|---|---|
| `puppet: NUL byte in input` | parse |
| `puppet: duplicate class: <name>` | parse |
| `puppet: parse error at <i>: <detail>` | parse (details in section 3) |
| `puppet: malformed module name: <name>` | module validate |
| `puppet: malformed module version: <version>` | module validate |
| `puppet: malformed manifest name: <n>` | module validate |
| `puppet: duplicate manifest: <n>` | module validate |
| `puppet: malformed dependency name: <d>` | module validate |
| `puppet: module depends on itself: <d>` | module validate |
| `puppet: duplicate dependency: <d>` | module validate |
| `puppet: interpolation: unknown variable: <name>` | interpolation |
| `puppet: interpolation: malformed variable name: <raw>` | interpolation |
| `puppet: interpolation: unterminated variable reference in: <text>` | interpolation |
| `puppet: interpolation: depth exceeded in: <text>` | interpolation |
| `puppet: hiera: no value for key: <key>` | hiera first / unique |
| `puppet: hiera: no hash values for key: <prefix>` | hiera hash |
| `puppet: unknown class: <name>` | catalog |
| `puppet: unknown resource type: <t>` | catalog |
| `puppet: duplicate resource: <type>[<title>]` | catalog |
| `puppet: unresolved reference: <ref>` | catalog |
| `puppet: unknown relationship kind: <kind>` | catalog |
| `puppet: dependency cycle: <type>[<title>]` | catalog |

## 10. Determinism and complexity

Everything is deterministic: iteration is index order over parallel vectors,
class lookup is first-match, hierarchy lookup is level order, the topological
sort breaks ties by smallest index, and no hash-ordered structure is used. On
identical inputs the manifest, catalog, report counts and event order are
byte-identical.

Let `N` be resources in a class, `A` attribute rows, `R` relationship rows,
`E` edges and `L` hiera levels with `D` data rows. Catalog build is
O(N*A + R*N + N^2 + E) plus the topo sort O(N^2 + E). Apply is
O(N * E + N + events). Hiera first / unique are O(L*D * interpolation) and
hash adds a subkey scan per row. Memory is O(rows + events).

## 11. v0.62.2 compiler notes

- Free functions only; every walk is index-based over parallel vectors and no
  `Vec[StructType]` value is ever created.
- `Result` constructors live only in the leaf helpers `_manifest_ok` /
  `_manifest_err`, `_catalog_ok` / `_catalog_err`, `_str_ok` / `_str_err`,
  `_strs_ok` / `_strs_err`, `_int_ok` / `_int_err`, `_bool_ok` / `_bool_err`,
  `_ref_ok` / `_ref_err`, `_val_ok` / `_val_err`, `_scope_ok` / `_scope_err`.
- All `Str` equality goes through `xiom.string.compare.str_compare` via
  `_streq` (BUG 17: `==` on `Vec[Str]` elements lowers to a pointer
  comparison); reference types additionally use the ASCII-folded `_streq_ci`.
- Every byte read is widened and masked through `_byte`
  (`(byte_at(...) as Int) & 0xFF`).
- Every vector element read is bound to a typed local first.
- No `&mut` scalar parameters: the parser cursor lives in the `Parser` struct,
  apply state in local `Vec[Int]`s.
- One module, so no cross-module `Ok`/`Err` identity issues.

## 12. Conformance map (tests/test_conformance.xi, 26 checks)

| Test | Covers |
|---|---|
| t01 | parse structure: classes, resources, ownership |
| t02 | metaparams become relationship rows |
| t03 | chained arrows become chain rows |
| t04 | parse error catalog and a valid manifest |
| t05 | accessor guards and attribute rows |
| t06 | module metadata validation |
| t07 | module immutable builders and file layout |
| t08 | module duplicate / self-dependency errors |
| t09 | hiera first lookup hierarchy priority |
| t10 | hiera first lookup interpolation and escape |
| t11 | hiera unique merge dedupe and order |
| t12 | hiera hash merge priority per subkey |
| t13 | interpolation error catalog and plain text |
| t14 | recursive interpolation and depth guard |
| t15 | catalog require reorders into dependency order |
| t16 | catalog metaparam and chain edges |
| t17 | catalog error catalog |
| t18 | apply: initial state changes every resource |
| t19 | apply: second run is idempotent |
| t20 | apply: present / absent classification |
| t21 | apply: notify refreshes an unchanged target |
| t22 | apply: subscribe inverts into a refresh |
| t23 | apply: failure propagates to dependents |
| t24 | exact report rendering and the empty catalog |
| t25 | end to end: web fixture applies and idempotent |
| t26 | parse: comments, CRLF, bare titles, chains |

## 13. Version history

- 0.1.0 -- initial pure-XIOM model, 26-check conformance suite, built and run
  on compiler v0.62.2 with the `stdlib` checkout.
