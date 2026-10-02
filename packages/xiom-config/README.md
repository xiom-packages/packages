# xiom.config

> **Status:** `incubating` -- conformance-tested (27/27); published at `v0.1.1` on the XIOM registry.
> **Scope:** in-memory configuration model: sectioned key/value parsing,
> overlay merge, typed getters, schema validation and canonical rendering.
> In-memory `Str` only -- no file I/O, no environment reads, no hot reload.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test`,
> `xiom.io` and `xiom.string.compare`.

## What it is

`xiom.config` is a pure, dependency-light configuration model for XIOM
programs. It parses a small INI-style source format into an ordered flat
`Config` (two parallel vectors: `keys` and `values`) and then lets a program
look values up, merge layered sources with later-source-wins precedence,
read typed values (str/int/bool) with precise errors, validate a config
against a declarative schema, and render the config back to canonical text.

There is no global state and no I/O: every function takes and returns values,
so the same model works for defaults compiled into a program, config text
read elsewhere, and override maps.

## Source format (short version)

```ini
# full-line comment; ';' works too
color = #ff0000          ; trailing comments start after whitespace
[server]
host = localhost         ; keys become server.host
port = 8080
[server]                 ; sections may be reopened; keys merge
debug = no
```

- `[section]` headers prefix every following plain key with `section.`
  (dotted keys compose: `[db]` + `server.host = x` -> `db.server.host`).
- `key = value` lines; whitespace around key/`=`/value is trimmed; the value
  may be empty and may contain `=` (the first `=` splits).
- `#` and `;` start full-line comments; inside a value they start a trailing
  comment only when preceded by space/tab, so `color = #ff0000` keeps its
  value.
- Duplicate keys: last assignment wins, first position is kept.
- The format has no quotes and no escape sequences.

`SPEC.md` carries the full grammar, decisions and error catalog.

## API

| Function | Returns | Description |
|---|---|---|
| `config_new()` | `Config` | Empty configuration. |
| `config_parse(text)` | `Result[Config, Str]` | Parse a whole document; `Err("config: ...")` on the first malformed line. |
| `config_get(c, key)` | `Option[Str]` | Value of a dotted key; `None` when absent, byte-exact and case-sensitive. |
| `config_has(c, key)` | `Bool` | True when the key exists. |
| `config_len(c)` | `Int` | Number of entries. |
| `config_keys(c)` | `Vec[Str]` | Keys in first-occurrence order (fresh copy). |
| `config_values(c)` | `Vec[Str]` | Values in key order (fresh copy). |
| `config_entries(c)` | `(Vec[Str], Vec[Str])` | All entries as parallel `(keys, values)` copies. |
| `config_merge(base, overlay)` | `Config` | Later-source-wins merge; either input unchanged. |
| `config_resolve(defaults, file, overrides)` | `Config` | The precedence chain defaults <- file <- overrides. |
| `config_set(c, key, value)` | `Config` | Copy with one key replaced in place or appended. |
| `config_get_str(c, key, default)` | `Str` | String value or `default`. |
| `config_try_str(c, key)` | `Result[Str, Str]` | `Err("config: missing key: <key>")` when absent. |
| `config_get_int(c, key, default)` | `Int` | Integer value, or `default` when absent/invalid. |
| `config_try_int(c, key)` | `Result[Int, Str]` | Precise invalid/out-of-range/missing errors. |
| `config_get_bool(c, key, default)` | `Bool` | Boolean value, or `default` when absent/invalid. |
| `config_try_bool(c, key)` | `Result[Bool, Str]` | Precise invalid/missing errors. |
| `config_schema_new()` | `Schema` | Empty validation schema. |
| `config_schema_add(s, key, typ, required, allowed)` | `Schema` | Append one schema row (`typ` is `"str"`, `"int"` or `"bool"`; `allowed` is comma-separated, `""` = any). |
| `config_validate(c, s)` | `Vec[Str]` | ALL schema errors in schema order; empty = valid. |
| `config_valid(c, s)` | `Bool` | True when validation finds no error. |
| `config_render(c)` | `Str` | Canonical `key = value` text in insertion order. |

Typed values: integers are `[+-]?[0-9]+` in the signed 64-bit range minus the
unrepresentable minimum; booleans are `true/false`, `yes/no` or `1/0`,
ASCII case-insensitive.

## Usage

```xi
use xiom.config;
use xiom.io;

fn main() -> Int {
  let r = config_parse("color = #ff0000\n[server]\nhost = localhost # inline\n");
  match r {
    Ok(cfg) => {
      io.println(config_get_str(&cfg, "server.host", "?")); // localhost
      io.println(config_render(&cfg));
      // color = #ff0000
      // server.host = localhost
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

Layering:

```xi
let effective = config_resolve(&defaults, &file_cfg, &overrides);
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.config
```

Expected tail: 27 `[PASS]` lines, `xiom.config: all tests passed`, then
`port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.

## Limitations (honest scope)

- **No file I/O, no environment reads, no hot reload / watch.** Those are out
  of scope for this package: feed `config_parse` text that your program read
  elsewhere. (`xiom.environment`, `xiom.ini` and `xiom.toml` cover adjacent
  problems.)
- No includes, no variable interpolation (`$VAR` is literal text).
- No quotes, no escape sequences, no multiline values. A value cannot contain
  a space/tab immediately followed by `#` or `;`, cannot be surrounded by
  space/tab, and cannot contain line breaks; parse never produces such
  values, and `config_set` callers must keep to the grammar for round-trips.
- Rendering writes normalized dotted keys and drops comments and section
  headers; there is no "preserve formatting" mode and no option to sort keys
  (insertion order only).
- Keys are case-sensitive; there is no normalization of case or of Unicode.
- Errors carry the offending line text but no line/column numbers.
- The signed 64-bit minimum `-9223372036854775808` is rejected as out of
  range (its magnitude is not representable as a positive `Int`; same choice
  as `xiom.l10n.number`).
- A UTF-8 BOM is not stripped; a BOM makes the first line malformed (or part
  of the first key).
- Schema validation is schema-closed in one direction only: config keys that
  are not listed in the schema are not reported.

See `SPEC.md` for the full grammar, merge semantics, validation rules, error
catalog and test plan. License: MIT OR Apache-2.0 (see the repository root
`LICENSE`).
