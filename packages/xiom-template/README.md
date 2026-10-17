# xiom.template

> **Status:** `stable` -- conformance-tested (43/43), `port.ps1` x2 green on
> XIOM v0.64.5. Published: `0.2.0` in `eco-v0.1.186` (sha256 `bedd03a9...`;
> `0.1.2` reference retained below). 0.2.0 adds the block surface below.
> **Scope:** Mustache-style template rendering: placeholder substitution
> (v0.1 surface, unchanged) plus sections, loops, inverted sections, dotted
> paths and optional HTML auto-escaping (v0.2 block surface).
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder` and `xiom.string.compare`). Tests additionally use
> `xiom.test` and `xiom.io`.

## Scope

`xiom.template` renders `{{name}}` placeholders from two parallel `Vec[Str]`
vectors (`keys` and `values`) with a deliberately small Mustache subset:

- substitution: `{{name}}`, with ASCII spaces allowed inside the braces
  (`{{ name }}`); the first matching key wins when a name is duplicated,
- comments: `{{! ... }}` is removed entirely and never counts as a key,
- literal braces: `{{{{` emits a single `{{`,
- two failure modes: `template_render` returns `Result[Str, Str]` (strict),
  while `template_render_lenient` renders missing keys as empty text,
- inspection: `template_keys` lists the referenced names and
  `template_needs_keys` reports the ones absent from a key list.

The 0.2.0 block surface (module `xiom.template.blocks`) adds, without
changing any v0.1 signature:

- **sections** `{{#key}}...{{/key}}`: iterate a `Str` list (`{{.}}` is the
  item), render a truthy `Bool` / non-empty `Str` / dotted group once;
  nested sections keep a context stack and `a.b` paths resolve against the
  current context, then ancestors,
- **inverted sections** `{{^key}}...{{/key}}`: render when the key is
  empty, `false` or missing,
- **auto-escaping**: `{{key}}` escapes `& < > " '` when `escape_html` is
  true; `{{{key}}}` and `{{&key}}` stay raw,
- **typed errors with byte offsets** (unknown key, unclosed interpolation,
  unterminated section, mismatched close) and a lenient twin that never
  fails,
- a **flat, ordered `TemplateData` model** (Str / Bool / Str-list entries;
  dotted names express structure; deliberately non-recursive) with caps on
  nesting depth (64) and output size (8 MiB).

There is no FFI, no file I/O and no state: every function is a pure
`Str`/`Vec[Str]` operation. `SPEC.md` has the full grammar, semantics,
error catalog and test plan.

## API

### Placeholder surface (v0.1, `xiom.template`)

| Function | Returns | Description |
|---|---|---|
| `template_render(tmpl, keys, values)` | `Result[Str, Str]` | Strict render: a missing key is `Err("template: missing key: <name>")`; an unterminated `{{` is `Err("template: unterminated placeholder")`. |
| `template_render_lenient(tmpl, keys, values)` | `Str` | Missing keys render as `""`; an unterminated `{{` drops the tail. Never fails. |
| `template_keys(tmpl)` | `Vec[Str]` | Referenced key names in first-seen order, deduplicated; comments excluded. |
| `template_needs_keys(tmpl, keys)` | `Vec[Str]` | Names referenced by `tmpl` but absent from `keys`, in first-seen order. |

All four are O(n) over the template plus a linear scan per placeholder
(lookup is O(placeholders x keys)).

### Block surface (v0.2, `xiom.template.blocks`)

| Function | Returns | Description |
|---|---|---|
| `template_data_new()` | `TemplateData` | Empty ordered data. |
| `template_data_set_str(d, name, value)` | - | Set/replace a `Str` value in place. |
| `template_data_set_bool(d, name, value)` | - | Set/replace a `Bool` value. |
| `template_data_set_list(d, name, items)` | - | Set/replace a `Str`-list value (items are copied). |
| `template_data_len(d)` | `Int` | Entry count. |
| `template_data_has(d, name)` | `Bool` | Exact-name presence (dotted groups excluded). |
| `template_data_kind(d, name)` | `Int` | `TEMPLATE_VALUE_STR` / `_BOOL` / `_LIST`, or -1. |
| `template_render_blocks(tmpl, data, escape_html)` | `Result[Str, Str]` | Strict block render; typed errors with byte offsets. |
| `template_render_blocks_lenient(tmpl, data, escape_html)` | `Str` | Block render that never fails (unknown keys render empty/skipped, unterminated sections complete at end of template, the output truncates at the cap). |

Caps: `TEMPLATE_MAX_DEPTH` (64 sections) and `TEMPLATE_MAX_OUTPUT`
(8388608 bytes); the full error catalog is in `SPEC.md` section 12.

## Usage

**Consumer note:** declare the dependency in your consuming manifest
(`[dependencies] "xiom.template" = "0.2.0"`, or the equivalent
`xiom.toml` entry) -- without the declaration, `use xiom.template;` can
silently bind to the stdlib's `xiom.string.template` surface
(`template_render`) while `xiom.template.blocks` stays unresolved (no
dedicated diagnostic for the mismatch; PULSE consumer-verify note,
2026-10-16).

```xi
use xiom.template;
use xiom.io;

fn main() -> Int {
  var keys = Vec[Str].new();
  keys.push("name");
  keys.push("role");
  var values = Vec[Str].new();
  values.push("Ada");
  values.push("engineer");

  let strict = template_render("Hello, {{ name }} -- {{role}}!", &keys, &values);
  match strict {
    Ok(s) => { io.println(s); },       // Hello, Ada -- engineer!
    Err(e) => { io.println(e); },
  }

  io.println(template_render_lenient("Hi {{missing}}!", &keys, &values)); // Hi !
  return 0;
}
```

Block surface with auto-escaping:

```xi
use xiom.template.blocks;

fn page() -> Int {
  var data = template_data_new();
  template_data_set_str(&mut data, "title", "Shop & Co");
  var items = Vec[Str].new();
  items.push("<one>");
  items.push("two");
  template_data_set_list(&mut data, "items", &items);

  let html = template_render_blocks(
    "<h1>{{title}}</h1>{{#items}}<li>{{.}}</li>{{/items}}{{^items}}<li>empty</li>{{/items}}",
    &data, true);
  match html {
    Ok(s) => { io.println(s); },  // <h1>Shop &amp; Co</h1><li>&lt;one&gt;</li><li>two</li>
    Err(e) => { io.println(e); }, // e.g. template: unknown key: x at byte 3
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.template
```

Expected tail: 43 `[PASS]` lines (t1-t22 placeholder surface, t23-t43 block
surface), `xiom.template: all tests passed`, then
`port: PASS (passed=43 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Template subset:** the v0.1 surface is placeholder-only; the v0.2 block
  surface adds sections, loops, inverted sections, dotted paths and
  auto-escaping. Partials (`{{>...}}`), lambdas, set-delimiter tags
  (`{{=...=}}`) and standalone-line whitespace handling remain unsupported
  on both surfaces.
- **Flat data model by design:** `TemplateData` is ordered Str / Bool /
  Str-list entries with dotted names for structure; there are no nested or
  recursive values. Only `Str` entries interpolate text (Bool, list and
  group interpolations render `""`; use sections for those). A list
  section keeps the parent context for non-dot names -- only `{{.}}` is the
  item.
- **Caps:** block sections nest at most 64 deep and the block renderer
  never emits more than 8 MiB (strict `Err` / lenient truncation; see
  `SPEC.md` sections 12-13).
- **Single pass:** substituted values are copied into the output verbatim and
  never re-scanned, so a value containing `{{...}}` stays literal and
  rendering can never recurse or loop.
- No output escaping on the v0.1 surface (values are inserted byte-exact);
  the block surface escapes only when `escape_html` is set.
- Only ASCII spaces (0x20) are trimmed inside braces; a tab or newline inside
  the braces is part of the placeholder name.
- Lookup scans the entries linearly per resolved name; very large data sets
  want an external map.
- Strict mode reports only the first problem and discards partial output.
- `template_needs_keys` consults only `keys`; a key present without a parallel
  value is reported missing by `template_render` but not by
  `template_needs_keys`.
- The v0.1 surface reads bytes with `string.byte_at`, which the runtime
  clamps at 1 MiB and re-scans per call; very large v0.1 inputs are slow or
  cannot see bytes past 1 MiB (unchanged from 0.1.2). The block surface
  uses raw-pointer reads and its 8 MiB cap is exact.
- No streaming/incremental API: the whole template is rendered in one call.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
