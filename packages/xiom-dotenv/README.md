# xiom.dotenv

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** dotenv (`.env`) parsing and emitting with quoting and comment
> rules; in-memory `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_trim`,
> `xiom.string.builder.sb_push_str`, `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.dotenv` parses a dotenv document into a flat `EnvFile` (two parallel
`Vec[Str]`: keys and decoded values) and can emit one back. It supports
`export` prefixes, full-line and trailing comments, double-quoted values with
the `\n \t \r \\ \"` escapes, single-quoted literal values, and unquoted
trimmed values. Duplicate keys follow last-wins semantics while keeping the
first position. Malformed lines, bad escapes and unterminated quotes return
`Err("dotenv: ...")`.

## API

| Function | Returns | Description |
|---|---|---|
| `dotenv_parse(text)` | `Result[EnvFile, Str]` | Parse a whole document; `Err("dotenv: ...")` on malformed lines, bad escapes or unterminated quotes. |
| `dotenv_get(e, key)` | `Option[Str]` | Value of `key`; `None` when absent. Case-sensitive, byte-exact. |
| `dotenv_has(e, key)` | `Bool` | True when the key exists. |
| `dotenv_keys(e)` | `Vec[Str]` | Keys in first-occurrence order (a fresh copy). |
| `dotenv_len(e)` | `Int` | Number of distinct keys. |
| `dotenv_emit(e)` | `Str` | One `KEY=VALUE` line per entry (LF separated); quotes values that need it and re-applies escapes. |

## Usage

```xi
use xiom.dotenv;
use xiom.io;

fn main() -> Int {
  let r = dotenv_parse("export HOST=localhost\nPORT=\"8080\"\n# comment\n");
  match r {
    Ok(env) => {
      match dotenv_get(&env, "HOST") {
        Some(host) => { io.println(host); },   // localhost
        None => {},
      }
      io.println(dotenv_emit(&env));
      // HOST=localhost
      // PORT=8080
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.dotenv
```

Expected tail: 18 `[PASS]` lines, `xiom.dotenv: all tests passed`, then
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No variable expansion**: `A=${B}` and `A=$B` are stored literally; there
  is no interpolation pass.
- **No multiline values**: every value lives on one logical line; embedded
  newlines are only representable via `\n` inside double quotes.
- No `export` round-trip: parsing strips the prefix and emitting never writes
  it back.
- No file I/O, no `.env` chain/cascade, no `process.env` integration.
- Keys are `[A-Za-z_][A-Za-z0-9_]*` only; no quoted or dotted keys.
- Unquoted values cannot contain a `#` preceded by whitespace (that starts a
  trailing comment) and are `str_trim`-ed on both ends.
- Errors carry the offending line text but no line/column numbers.

See `SPEC.md` for the full grammar, quoting rules, error strings and test
plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
