# xiom.envsubst

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** shell-style `${VAR}` expansion of in-memory `Str` text against a
> caller-supplied variable table (parallel `Vec[Str]` names/values or
> `"NAME=VALUE"` pairs). No environment access, no file I/O.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.builder.sb_push_str`,
> `xiom.string.builder.sb_push_byte`, `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## Scope

`xiom.envsubst` expands `${NAME}` references in a text using variables the
caller supplies. `NAME` must match `[A-Za-z_][A-Za-z0-9_]*` and lookups are
byte-exact and case-sensitive. A missing name is an
`Err("envsubst: undefined variable: NAME")` in strict mode and an empty string
in lenient mode. `$$` expands to a literal `$`; a `{` not preceded by `$` and a
lone `$` are literal text; a `${` with no closing `}` and a `${...}` with an
invalid name are always `Err`. Expansion is a single left-to-right pass, so
substituted values are never re-scanned.

## API

| Function | Returns | Description |
|---|---|---|
| `envsubst_expand(text, names, values, missing_empty)` | `Result[Str, Str]` | Expand every `${NAME}` from the parallel table; strict `Err` or empty string for undefined names. |
| `envsubst_expand_pairs(text, pairs, missing_empty)` | `Result[Str, Str]` | Same, sourcing variables from `"NAME=VALUE"` entries; malformed pairs (no `=` or empty name) are ignored. |
| `envsubst_has_vars(text)` | `Bool` | True when the byte pair `${` occurs (a cheap, deliberately over-reporting pre-check). |
| `envsubst_names(text)` | `Vec[Str]` | Distinct referenced names, first-seen order; malformed references are skipped; an unterminated `${` stops the scan. |

## Usage

```xi
use xiom.envsubst;
use xiom.io;

fn main() -> Int {
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  names.push("HOST"); values.push("localhost");
  names.push("PORT"); values.push("8080");

  let r = envsubst_expand("http://${HOST}:${PORT}/", &names, &values, false);
  match r {
    Ok(url) => { io.println(url); },        // http://localhost:8080/
    Err(e) => { io.println(e); },
  }

  var pairs = Vec[Str].new();
  pairs.push("HOME=/root");
  let r2 = envsubst_expand_pairs("$${HOME} is ${HOME}", &pairs, true);
  match r2 {
    Ok(s) => { io.println(s); },            // ${HOME} is /root
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.envsubst
```

Expected tail: 22 `[PASS]` lines, `xiom.envsubst: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **`${}` only**: bare `$VAR`, `%VAR%` and `$(cmd)` are plain text; only
  `${NAME}` references expand, plus the `$$` literal escape.
- **No defaults or operators**: no `${VAR:-x}`, `${VAR-default}`, `${#VAR}`,
  `${VAR/x/y}` or any other shell parameter expansion; such content fails name
  validation.
- **Single pass**: a substituted value containing `${X}` is emitted literally
  and never expanded again.
- **No environment or file access**: the variable table is entirely
  caller-supplied, which keeps expansion deterministic and testable.
- **No nesting**: `${A${B}}` is not a nested reference; the brace content up
  to the first `}` (`A${B`) fails name validation.
- **Values are bytes**: no length limits, no escaping, no NUL handling beyond
  the compiler's `Str` semantics.
- Errors carry the offending name (or a fixed message) but no byte offset.

See `SPEC.md` for the full grammar, semantics, error strings and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
