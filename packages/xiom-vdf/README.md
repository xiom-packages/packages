# xiom.vdf

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** Valve KeyValues (VDF) text parsing, case-insensitive lookup and
> canonical emitting; in-memory `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_split`,
> `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare_ignore_case` /
> `str_eq_ignore_case`). Tests additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.vdf` parses the Valve KeyValues text format used by Source-engine
games and tools (`.vdf` / `.txt` keyvalue files): nested `"key" "value"`
pairs and `"key" { ... }` blocks, `//` line comments, and quoted strings with
the four common escapes `\n` `\t` `\"` `\\`. Unquoted tokens are accepted
only where a value is expected; keys must be quoted.

A parsed document is five parallel vectors -- a flat, child-contiguous node
array. Every block owns a range of direct children, lookups are by dotted
path (`settings.player.name`), key matching is ASCII case-insensitive, and
duplicate keys are all preserved while the last occurrence wins for lookup.
`vdf_emit` writes a canonical form with one TAB per nesting level. The module
is pure in-memory `Str` handling: no FFI, no file I/O, no binary VDF, and no
app-specific schemas.

## Install / use

```
xiom pkg install xiom.vdf@0.1.0     # consumer (once published)
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

When working from this repository, add the package folder to your build and
import the module directly:

```xi
use xiom.vdf;
use xiom.io;
```

## Quick start

```xi
use xiom.vdf;
use xiom.io;

fn main() -> Int {
  let r = vdf_parse("\"settings\"\n{\n\t\"player\"\n\t{\n\t\t\"name\" \"ada\"\n\t\t\"level\" \"7\"\n\t}\n}\n");
  match r {
    Ok(d) => {
      match vdf_get_str(&d, "settings.player.name") {
        Some(name) => { io.println(name); },        // ada
        None => {},
      }
      match vdf_get_int(&d, "settings.player.level") {
        Some(level) => { io.println(level); },      // 7
        None => {},
      }
      io.println(vdf_emit(&d));
      // "settings"
      // {
      //   "player"
      //   {
      //     "name" "ada"
      //     "level" "7"
      //   }
      // }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## API

| Function | Returns | Description |
|---|---|---|
| `vdf_parse(text)` | `Result[Vdf, Str]` | Parse a whole document; `Err("vdf: ...")` on any malformed input (see the error model). |
| `vdf_root_keys(d)` | `Vec[Str]` | Root-level keys in document order, duplicates kept (a fresh copy). |
| `vdf_child_keys(d, path)` | `Vec[Str]` | Direct child keys of the block at `path` (`""` = root); empty for values, absent paths or empty path segments. |
| `vdf_has(d, path)` | `Bool` | True when `path` resolves to a value or block (`""` resolves to the root). |
| `vdf_get_str(d, path)` | `Option[Str]` | Scalar text; `None` when absent or a block. |
| `vdf_get_int(d, path)` | `Option[Int]` | Decimal integer (optional leading `-`, leading zeros allowed); `None` when absent, a block, or not a decimal integer. |
| `vdf_get_bool(d, path)` | `Option[Bool]` | `1`/`true` (ASCII case-insensitive) is true, `0`/`false` is false; `None` otherwise. |
| `vdf_emit(d)` | `Str` | Canonical text: one node per line, one TAB per nesting level, quoted and escaped keys/values, LF-terminated lines; `""` for an empty document. |

Lookup semantics: a dotted `path` is split on `.`; each segment is matched
against the direct children of the current block (ASCII case-insensitive),
and if a key repeats the **last** occurrence wins. Keys are stored byte-exact,
so `vdf_root_keys` / `vdf_child_keys` return the original spellings and every
duplicate.

## Error model

Every parse failure is `Err(msg)` with a deterministic message starting with
`"vdf: "`. Messages carry no line/column numbers:

| Message | Trigger |
|---|---|
| `vdf: unterminated quoted string` | EOF, LF or CR before the closing `"` |
| `vdf: unterminated block` | EOF with at least one `{` still open |
| `vdf: unexpected '}'` | `}` at top level (no open block) |
| `vdf: stray token: <token>` | unquoted token where a key is expected |
| `vdf: bad escape: <seq>` | `\` followed by anything but `n` `t` `"` `\` |
| `vdf: key without value: <key>` | key followed by EOF or `}` |
| `vdf: empty key` | a quoted key that decodes to `""` |
| `vdf: depth exceeded (max 64)` | more than 64 simultaneously open blocks |

Lookups never fail: an unresolvable path yields `None`, `false` or an empty
vector.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.vdf
```

Expected tail: 23 `[PASS]` lines, `xiom.vdf: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- Keys must be quoted; unquoted tokens are a documented value-only convenience.
- No conditionals or macros: `[$WIN32]`, `[!$X]`, `#base` and `#include` are
  not interpreted (an unquoted `[$WIN32]` is a stray token / parse error).
- No binary VDF (the byte-oriented `.vdf`/`kv` format) and no app-specific
  schemas.
- Flat path namespace: a key containing `.` cannot be addressed (`a.b` always
  means segment `b` under block `a`), and empty path segments are not
  addressable.
- Case-insensitive matching folds ASCII `A-Z` only; non-ASCII bytes compare
  byte-exact.
- Quoted strings cannot contain raw LF/CR (write `\n`); the parser reports an
  unterminated string instead.
- Typed accessors cover decimal integers and `0`/`1`/`true`/`false` only; no
  floats, hex, or trimming of surrounding whitespace. Integer overflow is not
  detected.
- Duplicate keys/blocks are preserved (no deduplication); the last occurrence
  wins for lookup.
- Comments are parsed and dropped: `vdf_emit` never writes comments.
- No file I/O, no streaming, no registry integration.

See `SPEC.md` for the full grammar, semantics, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
