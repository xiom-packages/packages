# xiom.osrelease

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** `/etc/os-release` (systemd spec) parsing and canonical emitting;
> in-memory `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.str_slice`,
> `xiom.string.byte_at`, `xiom.string.str_contains`,
> `xiom.string.builder.sb_push_str`, `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.osrelease` parses an os-release document (`KEY=VALUE` assignments, the
format of `/etc/os-release` and `/usr/lib/os-release`) into a flat
`OsRelease` (two parallel `Vec[Str]`: keys and decoded values, document order
preserved) and can emit a canonical document back. It supports unquoted
values, single-quoted literal values, double-quoted values with the four
shell escapes (`\"`, `\\`, `\$`, `` \` ``), full-line `#` comments, blank
lines and CRLF/LF input. Duplicate keys are preserved; `osrelease_first` and
`osrelease_last` expose both ends (the spec tells readers to prefer the later
entry, and the `ID`/`ID_LIKE`/`VERSION_ID` conveniences do). Malformed
assignments, bad keys, unterminated quotes, invalid escapes, control bytes
and unquoted whitespace return `Err("osrelease: ...")`.

## API

| Function | Returns | Description |
|---|---|---|
| `osrelease_parse(text)` | `Result[OsRelease, Str]` | Parse a whole document; `Err("osrelease: ...")` on malformed input. |
| `osrelease_len(r)` | `Int` | Number of assignments, repeats included. |
| `osrelease_key_at(r, i)` | `Option[Str]` | Key of assignment `i`; `None` when out of range. |
| `osrelease_value_at(r, i)` | `Option[Str]` | Decoded value of assignment `i`; `None` when out of range. |
| `osrelease_first(r, key)` | `Option[Str]` | First value for `key`; `None` when absent. Case-sensitive. |
| `osrelease_last(r, key)` | `Option[Str]` | Last value for `key` (spec-recommended on repeats). |
| `osrelease_has(r, key)` | `Bool` | True when the key exists. |
| `osrelease_id(r)` | `Option[Str]` | Last `ID` value; `None` when unset. |
| `osrelease_id_like(r)` | `Option[Str]` | Last `ID_LIKE` value; `None` when unset. |
| `osrelease_version_id(r)` | `Option[Str]` | Last `VERSION_ID` value; `None` when unset. |
| `osrelease_emit(r)` | `Str` | Canonical document: LF separated, no trailing LF, values double-quoted when needed. |

## Usage

```xi
use xiom.osrelease;
use xiom.io;

fn main() -> Int {
  let text = "NAME=Fedora\nID=fedora\nVERSION_ID=32\nPRETTY_NAME=\"Fedora 32 (Workstation Edition)\"\n";
  match osrelease_parse(text) {
    Ok(rel) => {
      match osrelease_id(&rel) {
        Some(id) => { io.println(id); },          // fedora
        None => {},
      }
      match osrelease_version_id(&rel) {
        Some(v) => { io.println(v); },            // 32
        None => {},
      }
      io.println(osrelease_emit(&rel));
      // NAME=Fedora
      // ID=fedora
      // VERSION_ID=32
      // PRETTY_NAME="Fedora 32 (Workstation Edition)"
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.osrelease
```

Expected tail: 20 `[PASS]` lines, `xiom.osrelease: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No shell evaluation or variable expansion**: `$VAR`, `${VAR}` and
  `` `cmd` `` are literal text, exactly as in the file.
- **No cross-file merging**: `/etc/os-release` vs `/usr/lib/os-release`
  precedence and `/run/host/os-release` are callers' concerns; this package
  handles one in-memory document.
- **Strict subset of systemd's lenient reader**: whitespace around `=` is
  rejected (`KEY = x` is not an assignment), an unquoted value may not contain
  a space, a `#` is a comment only at byte 0 (no trailing comments), and an
  unknown escape such as `\n` is `Err` rather than a kept backslash. TAB and
  other control bytes are rejected everywhere.
- **No line continuation**: a trailing `\` inside double quotes is an
  unterminated quote, not a continuation.
- No file I/O, no key validation on emit (keys are written verbatim), and
  errors carry the offending line text but no line numbers.
- Values carrying control bytes cannot be emitted in a re-parsable form; such
  values are outside the accepted domain (see `SPEC.md`).

See `SPEC.md` for the full grammar, quoting rules, error strings and test
plan. License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
