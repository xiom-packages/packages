# xiom.toml

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** TOML v1.0 subset parsing with flat, dotted-path lookups.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_trim`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.toml` parses TOML v1.0 documents up to the subset described in
`SPEC.md` -- comments, bare/quoted keys, `key = value`, dotted keys,
`[table]` / `[a.b]` headers, basic and literal strings, integers, booleans and
arrays of strings or integers -- into a flat `TomlDoc` whose entry keys are
dotted paths (`server.port`). Lookups are by dotted path; there is no nested
value tree. Duplicate keys/tables and malformed lines return
`Err("toml: ...")`.

## API

| Function | Returns | Description |
|---|---|---|
| `toml_parse(text)` | `Result[TomlDoc, Str]` | Parse a whole document; `Err("toml: ...")` on malformed input, duplicates or unsupported constructs. |
| `toml_has(d, key)` | `Bool` | True when the dotted `key` exists. |
| `toml_kind(d, key)` | `Option[Int]` | `0` str, `1` int, `2` bool, `3` str-array, `4` int-array; `None` when absent. |
| `toml_get_str(d, key)` | `Option[Str]` | String value; `None` when absent or another kind. |
| `toml_get_int(d, key)` | `Option[Int]` | Integer value; `None` when absent or another kind. |
| `toml_get_bool(d, key)` | `Option[Bool]` | Boolean value; `None` when absent or another kind. |
| `toml_get_str_array(d, key)` | `Vec[Str]` | Array items; empty when absent or another kind. |
| `toml_get_int_array(d, key)` | `Vec[Int]` | Array items parsed to `Int`; empty when absent or another kind. |
| `toml_keys(d)` | `Vec[Str]` | Dotted keys in document order (a fresh copy). |
| `toml_key_count(d)` | `Int` | Number of entries. |

## Usage

```xi
use xiom.toml;
use xiom.io;

fn main() -> Int {
  let r = toml_parse("[server]\nhost = \"localhost\"\nports = [80, 443]\n");
  match r {
    Ok(d) => {
      match toml_get_str(&d, "server.host") {
        Some(host) => { io.println(host); },   // localhost
        None => {},
      }
      var ports = toml_get_int_array(&d, "server.ports");
      io.println(toml_key_count(&d));          // 2
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.toml
```

Expected tail: 21 `[PASS]` lines, `xiom.toml: all tests passed`, then
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- Flat namespace: a quoted key containing a dot (`"a.b" = 1`) is
  indistinguishable from the dotted path `a.b`.
- No multi-line strings (`"""` / `'''`), no dates/times, floats (or any
  decimal/special float), hex/octal/binary integers, `_` digit separators,
  inline tables, arrays of tables or nested arrays.
- Basic-string escapes are limited to `\n \t \r \" \\`; `\uXXXX`/`\UXXXXXXXX`
  and all other escapes are malformed.
- Arrays must be homogeneous and hold only strings or integers; boolean,
  float, mixed and nested arrays are malformed. An empty array is reported as
  a string array.
- Integers are parsed without overflow detection; values outside the `Int`
  range are not rejected.
- Duplicate detection is per exact dotted path and per table header; implicit
  TOML table re-opening rules (`a.b = 1` followed by `[a]`) are not enforced.
- No serialization/writing API and no file I/O; the module is pure in-memory
  `Str` parsing.

See `SPEC.md` for the full semantics, error strings and test plan. License:
MIT OR Apache-2.0 (see the repository root `LICENSE`).
