# xiom.environment

> **Status:** `incubating` -- conformance-tested (23/23); published at `v0.1.0` on the XIOM registry.
> **Scope:** deterministic environment-variable expansion over a
> caller-supplied table; in-memory `Str` only, no process-environment access.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.builder.sb_new`,
> `xiom.string.builder.sb_push_str`, `xiom.string.builder.sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.environment` is a pure, deterministic environment-variable expansion
engine. It never reads or writes the process environment: the caller supplies
the variable table (parallel name/value vectors, or `NAME=VALUE` entries) and
a strictness flag, and receives the expanded text plus the distinct list of
referenced variable names. The same inputs always produce the same output.

Recognized syntax:

| Form | Meaning |
|---|---|
| `${NAME}` | value of `NAME`; strict mode errors when `NAME` is unset |
| `${NAME:-word}` | `word` when `NAME` is unset **or** empty |
| `${NAME-word}` | `word` when `NAME` is unset (a set-but-empty value stays `""`) |
| `${NAME:+word}` | `word` when `NAME` is set **and** non-empty, else `""` |
| `${NAME:?message}` | value when set and non-empty, else an error carrying `message` |
| `$$` | one literal `$` |
| `'...'` | literal span: no expansion inside, the quotes are removed |
| `"..."` | expanding span: references expand inside, the quotes are removed |

Operator words are expanded recursively (nested references are allowed up to
eight operand levels) and expansion is single-pass: substituted values are
copied verbatim and never re-scanned, so a value of `${OTHER}` stays literal.

## API

| Function | Returns | Description |
|---|---|---|
| `env_expand(src, vars, strict)` | `Result[Expansion, Str]` | Expand `src` against `&EnvVars`. `Err("environment: ...")` on any failure; strict makes an unset plain `${NAME}` an error. |
| `env_expand_pairs(src, pairs, strict)` | `Result[Expansion, Str]` | Same, with the table built from `NAME=VALUE` entries first. |
| `env_vars_from_pairs(pairs)` | `EnvVars` | Build a table from `NAME=VALUE` entries: split at the first `=`, skip entries with no `=` or an empty key, first duplicate wins. |
| `Expansion.text` | `Str` | The expanded output text. |
| `Expansion.names` | `Vec[Str]` | Distinct variables looked up, in first-lookup order. |
| `EnvVars.names` / `EnvVars.values` | `Vec[Str]` | Index-aligned table; the first matching name with a parallel value wins. |

## Usage

```xi
use xiom.environment;
use xiom.io;

fn main() -> Int {
  var vars = EnvVars{ names: Vec[Str].new(); values: Vec[Str].new() };
  vars.names.push("HOST"); vars.values.push("localhost");
  vars.names.push("PORT"); vars.values.push("");
  let r = env_expand("http://${HOST}:${PORT:-8080}", &vars, true);
  match r {
    Ok(e) => {
      io.println(e.text);        // http://localhost:8080
      io.println(e.names.len()); // 2 (HOST, PORT)
    },
    Err(m) => { io.println(m); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.environment
```

Expected tail: 23 `[PASS]` lines, `xiom.environment: all tests passed`, then
`port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## Limitations

- Only `${NAME}` references expand; bare `$VAR`, `%VAR%`, `$(cmd)` and
  backslash escapes are literal text.
- Only the four operator forms above; colon-less `${VAR+word}` and
  `${VAR?message}` are `unsupported operator` errors, as are `${#VAR}`,
  substring/replacement forms and anything else after the name.
- No process environment, no file I/O, no cascade/chained files: the table is
  entirely caller-supplied.
- Single pass only: values are never re-scanned, so a value containing
  `${X}` is emitted literally.
- A double quote cannot appear inside a double-quoted span (there is no `\"`
  escape); the span ends at the first `"`. Inside a double-quoted span a
  single quote is an ordinary byte.
- Quotes do not shield braces inside an operator word: the word ends at the
  first `}` that balances the reference's `${` nesting.
- An unselected operator word is brace-matched but never validated or
  expanded, so a bad quote or reference inside it is not reported.
- Names are ASCII-only (`[A-Za-z_][A-Za-z0-9_]*`); no Unicode identifiers.
- Nesting is capped at eight operand levels (`environment: nesting too deep`).
- Errors carry no byte offset or line/column position.

See `SPEC.md` for the full grammar, semantics, error catalog and test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
