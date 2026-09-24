# xiom.properties

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Java `.properties` parsing and emitting with escapes and line
> continuations; in-memory `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.builder.sb_push_str`,
> `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.properties` parses a Java `.properties` document into a flat `Props`
(two parallel `Vec[Str]`: keys and decoded values) and can emit one back. It
implements the `java.util.Properties` reader rules: `#`/`!` comments, `=`/`:`
or whitespace separators, backslash line continuations with leading whitespace
stripped on the continuation, and the `\t \n \r \f \\ \uXXXX` escapes (any
other escaped byte decodes to that byte). Duplicate keys follow last-wins
semantics while keeping the first position; malformed `\uXXXX` escapes return
`Err("properties: ...")`.

## API

| Function | Returns | Description |
|---|---|---|
| `props_parse(text)` | `Result[Props, Str]` | Parse a whole document; `Err("properties: ...")` on a malformed `\uXXXX` escape. |
| `props_get(p, key)` | `Option[Str]` | Value of `key`; `None` when absent. Case-sensitive, byte-exact. |
| `props_count(p)` | `Int` | Number of distinct keys. |
| `props_keys(p)` | `Vec[Str]` | Keys in first-occurrence order (a fresh copy). |
| `props_set(p, key, value)` | `Props` | A new `Props` with the pair replaced in place or appended; `p` is untouched. |
| `props_emit(p)` | `Str` | One `key=value` line per entry (LF separated, no trailing LF); escapes `\`, LF, TAB, CR and the key/value specials. |

## Escapes

| Escape | Decodes to | Re-applied by `props_emit` |
|---|---|---|
| `\\` | one backslash | yes |
| `\n` | LF (0x0A) | yes |
| `\t` | TAB (0x09) | yes |
| `\r` | CR (0x0D) | yes |
| `\f` | FF (0x0C) | no (kept raw) |
| `\uXXXX` | UTF-8 bytes of the BMP code point | no (raw UTF-8 kept) |
| `\X` (unknown) | the byte `X` itself (Java behavior) | n/a |
| `\= \: \# \! \ ` | the byte | key: `=` `:` `#` `!` and every space; value: `=` `:` `#` `!` only as the first byte, spaces only while they lead |

## Usage

```xi
use xiom.properties;
use xiom.io;

fn main() -> Int {
  let r = props_parse("host=localhost\nport: 8080\n# comment\n");
  match r {
    Ok(p) => {
      match props_get(&p, "host") {
        Some(host) => { io.println(host); },   // localhost
        None => {},
      }
      io.println(props_emit(&p));
      // host=localhost
      // port=8080
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.properties
```

Expected tail: 21 `[PASS]` lines, `xiom.properties: all tests passed`, then
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No locale/encoding variants**: `java.util.Properties` reads ISO-8859-1
  (or UTF-8 via a Reader); this module works on the bytes of a `Str` as
  UTF-8 and applies no character-set conversion.
- **BMP-only `\u`**: each `\uXXXX` is encoded on its own; a surrogate pair
  written as two escapes becomes two 3-byte sequences instead of one 4-byte
  code point.
- **No `\uXXXX` on emit**: non-ASCII text is written as raw UTF-8 bytes, not
  as `\uXXXX` (unlike Java's `store`).
- No file I/O, no defaults/cascade merging, no `java.util.Properties` API.
- Comments and blank lines are parsed but never emitted.
- Errors carry the offending line text but no line/column numbers.

See `SPEC.md` for the full grammar, escape table, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
