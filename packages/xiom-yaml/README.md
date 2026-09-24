# xiom.yaml

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** YAML subset parsing with flat, dotted-path lookups.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_trim`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.yaml` parses the YAML subset described in `SPEC.md` -- comments, blank
lines, nested mappings by spaces-only indentation with a consistent step,
block lists under a key (`- item`), inline scalar lists (`[a, b]`) and
scalars (plain, `'single'`, `"double"` with `\n \t \" \\` escapes, integers
with an optional leading `-`, `true`/`false`, `null`/`~`) -- into a flat
`YamlDoc` whose entry keys are dotted paths (`server.port`). Lookups are by
dotted path; there is no nested value tree and mapping containers have no
entry of their own. Duplicate keys and malformed lines return
`Err("yaml: ...")`.

Anchors/aliases, multi-document streams, tags, flow mappings, multi-line
scalars and nested structures inside list items are unsupported.

## API

| Function | Returns | Description |
|---|---|---|
| `yaml_parse(text)` | `Result[YamlDoc, Str]` | Parse a whole document; `Err("yaml: ...")` on malformed input, indentation errors, duplicates or unsupported constructs. |
| `yaml_has(d, key)` | `Bool` | True when the dotted `key` exists. |
| `yaml_kind(d, key)` | `Option[Int]` | `0` str, `1` int, `2` bool, `3` null, `4` str-list; `None` when absent. |
| `yaml_get_str(d, key)` | `Option[Str]` | String value; `None` when absent or another kind. |
| `yaml_get_int(d, key)` | `Option[Int]` | Integer value; `None` when absent or another kind. |
| `yaml_get_bool(d, key)` | `Option[Bool]` | Boolean value; `None` when absent or another kind. |
| `yaml_get_str_list(d, key)` | `Vec[Str]` | List items as decoded text; empty when absent or another kind. |
| `yaml_keys(d)` | `Vec[Str]` | Dotted keys in document order (a fresh copy). |
| `yaml_key_count(d)` | `Int` | Number of leaf entries. |

## Usage

```xi
use xiom.yaml;
use xiom.io;

fn main() -> Int {
  let r = yaml_parse("server:\n  host: localhost\n  ports: [80, 443]\n");
  match r {
    Ok(d) => {
      match yaml_get_str(&d, "server.host") {
        Some(host) => { io.println(host); },   // localhost
        None => {},
      }
      var ports = yaml_get_str_list(&d, "server.ports");
      io.println(yaml_key_count(&d));          // 1
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.yaml
```

Expected tail: 25 `[PASS]` lines, `xiom.yaml: all tests passed`, then
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## Limitations

- Flat namespace: a dotted key (`a.b: 1`) and a nested mapping (`a:` /
  `  b: 1`) both canonicalize to the path `a.b` and are indistinguishable.
- Mapping containers are implicit: `server:` has no entry, so
  `yaml_has(d, "server")` is false for a document that only defines
  `server.host`; re-opening a container is a duplicate-key error.
- Indentation must use spaces and a single consistent step fixed by the
  first nested level; the root mapping must start at column 0.
- List items are scalars only: nested maps, nested lists and flow
  collections inside a block or inline list are malformed (a plain item may
  not start with `[`, `{` or a nested `- ` indicator, and may not contain
  `": "`).
- Plain scalars are stored verbatim; `true`/`false`, `null`/`~` and
  optional-`-` integers are recognized only when the whole value matches.
  Integers are canonicalized (`007` reads back as `7`, `-0` as `0`) and
  parsed without overflow detection.
- Single-quoted scalars are literal and may not contain a quote (YAML's
  doubled `''` escape is not supported); double-quoted escapes are limited
  to `\n \t \" \\`.
- An empty value (`key:`) becomes null unless the next content line is
  indented deeper, in which case it opens a nested mapping or block list.
- No serialization/writing API and no file I/O; the module is pure in-memory
  `Str` parsing.

See `SPEC.md` for the full semantics, error strings and test plan. License:
MIT OR Apache-2.0 (see the repository root `LICENSE`).
