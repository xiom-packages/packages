# xiom.ini

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** INI file parsing, editing and emitting with ordered sections;
> in-memory `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_trim`,
> `xiom.string.str_contains`, `xiom.string.builder.sb_push_str`,
> `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.ini` parses an INI document into a flat `Ini` (three parallel
`Vec[Str]`: sections, keys and values), supports lookup, editing and removal,
and emits the document back. Sections keep first-seen order and the empty
section name (`""`) is the global/top-level area. A repeated
`(section, key)` assignment replaces the value in place, so the last
assignment wins and the entry keeps its first position. Malformed section
headers, empty keys and non-blank lines without a separator return
`Err("ini: ...")`.

## API

| Function | Returns | Description |
|---|---|---|
| `ini_parse(text)` | `Result[Ini, Str]` | Parse a whole document; `Err("ini: ...")` on malformed headers, empty keys or missing separators. |
| `ini_get(i, section, key)` | `Option[Str]` | Value of the pair; `None` when absent. Byte-exact, case-sensitive. |
| `ini_has(i, section, key)` | `Bool` | True when the pair exists. |
| `ini_keys(i, section)` | `Vec[Str]` | Keys of that section in entry order (a fresh copy). |
| `ini_sections(i)` | `Vec[Str]` | Sections in first-seen order; `""` only when the global area has entries. |
| `ini_set(i, section, key, value)` | -- | Replace the pair in place or append it. |
| `ini_remove(i, section, key)` | `Bool` | Remove the pair (compacting the arrays); false when absent. |
| `ini_emit(i)` | `Str` | Global entries first, then `[name]` groups separated by one blank line; no trailing LF. |

## Usage

```xi
use xiom.ini;
use xiom.io;

fn main() -> Int {
  let r = ini_parse("top = 1\n[server]\nhost = localhost\nport = 8080\n");
  match r {
    Ok(d) => {
      match ini_get(&d, "server", "host") {
        Some(host) => { io.println(host); },   // localhost
        None => {},
      }
      io.println(ini_emit(&d));
      // top = 1
      //
      // [server]
      // host = localhost
      // port = 8080
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.ini
```

Expected tail: 20 `[PASS]` lines, `xiom.ini: all tests passed`, then
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- No nested sections (`[a.b]` is a flat section literally named `a.b`) and no
  section/appendix inheritance.
- No interpolation: `%(name)s`, `${name}` and `$name` are stored literally.
- Comments are not preserved on emit: full-line `;`/`#` comments are parsed
  and dropped, and emit never writes comments.
- No inline comments: `;` and `#` start a comment only at the beginning of a
  line; elsewhere they are ordinary value bytes.
- No quoting, escaping or type coercion: keys and values are trimmed byte
  runs; `get` always returns the raw text.
- `ini_set` stores its arguments verbatim; a key containing `=`/`:` or a
  section name containing `]` can produce text that re-parses differently.
- A value with leading/trailing whitespace or an embedded LF does not survive
  an emit/parse round trip (parse trims; emit writes verbatim).
- No file I/O and no registry integration; the module is pure in-memory `Str`
  parsing.
- Errors carry the offending line text but no line/column numbers.

See `SPEC.md` for the full grammar, merge rules, error strings and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
