# xiom.template

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Mustache-style `{{name}}` template rendering with strict and
> lenient key handling.
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

There is no FFI, no file I/O and no state: every function is a pure
`Str`/`Vec[Str]` operation. `SPEC.md` has the full grammar, semantics, error
catalog and test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `template_render(tmpl, keys, values)` | `Result[Str, Str]` | Strict render: a missing key is `Err("template: missing key: <name>")`; an unterminated `{{` is `Err("template: unterminated placeholder")`. |
| `template_render_lenient(tmpl, keys, values)` | `Str` | Missing keys render as `""`; an unterminated `{{` drops the tail. Never fails. |
| `template_keys(tmpl)` | `Vec[Str]` | Referenced key names in first-seen order, deduplicated; comments excluded. |
| `template_needs_keys(tmpl, keys)` | `Vec[Str]` | Names referenced by `tmpl` but absent from `keys`, in first-seen order. |

All four are O(n) over the template plus a linear scan per placeholder
(lookup is O(placeholders x keys)).

## Usage

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

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.template
```

Expected tail: 22 `[PASS]` lines, `xiom.template: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Template subset only:** no sections/conditionals (`{{#...}}`, `{{^...}}`),
  no loops, no partials/includes, no dotted names, no lambdas and no
  set-delimiter tags. Values are plain `Str`; there are no nested contexts.
- **Single pass:** substituted values are copied into the output verbatim and
  never re-scanned, so a value containing `{{...}}` stays literal and
  rendering can never recurse or loop.
- No output escaping (values are inserted byte-exact); no HTML auto-escaping.
- Only ASCII spaces (0x20) are trimmed inside braces; a tab or newline inside
  the braces is part of the placeholder name.
- Lookup scans the parallel vectors linearly per placeholder; very large key
  sets want an external map.
- Strict mode reports only the first problem and discards partial output.
- `template_needs_keys` consults only `keys`; a key present without a parallel
  value is reported missing by `template_render` but not by
  `template_needs_keys`.
- No streaming/incremental API: the whole template is rendered in one call.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
