# xiom.flags -- Specification

Status: `incubating` (implemented, tested with compiler v0.61.3; not published).
Manifest: `package.xi` (`xiom.flags`, version `0.1.0`).
Module: `src/flags.xi` (`module xiom.flags`).

## Scope

A small command-line flag parser for XIOM CLI programs:

- declare long flags (`--name`) with optional single-character short aliases
  (`-s`) and optional environment-variable fallback,
- parse an argument vector or the process arguments,
- boolean presence flags and value-taking flags,
- required-flag validation with environment fallback,
- ordered positional arguments (subcommand friendly),
- deterministic error messages for unknown flags and missing values,
- generated one-line-per-flag help text.

## Non-goals

- Subcommand trees, aliases, or per-subcommand parsers.
- Combined short flags (`-abc`), attached short values (`-ovalue`), or
  `--no-name` negation forms.
- Type coercion beyond integer parsing (`flags_int_value`); no float/bool
  value parsing.
- Configuration files, default values, or shell-completion generation.
- Locale/Unicode-aware help layout.

## Argument grammar

Scanned left to right; the first match wins.

```
--                    terminator; every later argument is a positional
--name                boolean long flag (any declared flag); present = true
--name=value          inline value; value may be empty; name must be non-empty
--name value          spaced value; allowed only when the flag takes a value
-s                    boolean short flag (s is exactly one character)
-s value              spaced value; allowed only when the short flag takes one
<other>               positional (including a bare "-")
```

- A value-taking flag consumes the next argument as its value even when it
  begins with `-` or `--`.
- An inline `--name=value` is accepted for any declared flag; for a flag that
  does not take a value the value is ignored and presence is recorded.
- Repeating a flag is allowed: the last occurrence wins (values; presence is
  idempotent).
- Unknown `--name`, `--name=value`, or `-s` forms fail with
  `Err("unknown flag: <arg>")` where `<arg>` is the argument as typed.
- A value-taking flag at the end of the vector fails with
  `Err("missing value for: <arg>")`.
- Short flags longer than one character (`-abc`) are unknown flags.
- `-` alone and `--=x`-style empty names are handled as above (`-` is
  positional, an empty long name is unknown).

## API

All functions are free functions in `module xiom.flags`.

```xi
pub type FlagParser = { ... }   // internal parallel arrays; see below

pub fn flags_new() -> FlagParser
pub fn flags_flag(p: &mut FlagParser, name: Str, short: Str, takes_value: Bool,
                  required: Bool, env_var: Str, help: Str) -> Int
pub fn flags_parse(p: &mut FlagParser, args: &Vec[Str]) -> Result[Unit, Str]
pub fn flags_parse_process(p: &mut FlagParser) -> Result[Unit, Str]
pub fn flags_has(p: &FlagParser, name: Str) -> Bool
pub fn flags_value(p: &FlagParser, name: Str) -> Option[Str]
pub fn flags_int_value(p: &FlagParser, name: Str) -> Result[Int, Str]
pub fn flags_positionals(p: &FlagParser) -> Vec[Str]
pub fn flags_help(p: &FlagParser) -> Str
```

`FlagParser` field layout (internal; use the functions): `names`, `shorts`,
`env_vars`, `helps`, `values` (`Vec[Str]`), `takes_value`, `required`,
`present` (`Vec[Bool]`), and `positionals` (`Vec[Str]`). Field `i` of each
parallel array belongs to declaration `i`; `flags_flag` returns that index.

Resolution rules:

- `flags_has(p, name)`: false for undeclared names. True when the flag was
  provided on the command line, or, when absent, when its declared
  environment variable is set.
- `flags_value(p, name)`: `None` for undeclared names. When present on the
  command line: the last value for value-taking flags, `"true"` for boolean
  flags. When absent: the declared environment variable's value if set,
  otherwise `None`.
- `flags_int_value(p, name)`: `Ok(parse_int(v))` for the value above;
  `Err("flag not provided: <name>")` when `flags_value` is `None`; otherwise
  the `xiom.convert` parse error verbatim (e.g. `"invalid digit"`,
  `"overflow"`).
- `flags_parse_process(p)`: reads `xiom.os.args.args_raw()` and skips index 0
  (the program name) before delegating to `flags_parse`.
- `flags_positionals(p)`: a fresh copy of the collected positionals, in the
  order seen.
- `flags_help(p)`: one line per declaration, in declaration order, joined by
  `"\n"`:
  `  --name, -s VALUE (required) [env: VAR]  help text`, with `-s`, `VALUE`,
  `(required)`, `[env: VAR]`, and the help text omitted when unused.

## Error paths

| Condition | Result error text |
|---|---|
| Unknown long/short flag | `unknown flag: <arg>` |
| Value-taking flag without a value | `missing value for: <arg>` |
| Required flag absent and no environment value | `missing required flag: --<name>` |
| `flags_int_value` with no value available | `flag not provided: <name>` |
| `flags_int_value` with an unparsable value | parser message, e.g. `invalid digit` |

After any `Err` from `flags_parse`, the parser state is unspecified (some
earlier arguments may already be recorded); callers should treat the error as
fatal or re-parse with a fresh `flags_new()` parser. The same applies to the
positional vector.

## Test plan

`tests/test_conformance.xi` (`module flags_tests`) runs 18 named tests and
prints `[PASS]`/`[FAIL]` per test, returning the failure count as the exit
code. Coverage:

1. inline `--name=value`
2. spaced `--name value`
3. short flag with value (`-o out.txt`)
4. boolean short flag presence (`-v`)
5. unknown flag error and exact message
6. missing value error and exact message
7. required flag missing error and exact message
8. required flag satisfied by environment (`xiom.env.set_var`/`clear_var`)
9. duplicate occurrences, last one wins
10. `--` terminator: rest are positionals, flags after it are not parsed
11. positional order preserved
12. `flags_int_value` success
13. `flags_int_value` malformed value error
14. help text contains flag names, value hint, `(required)`, `[env: VAR]`
15. environment fallback value for an absent flag
16. `flags_value` `None` and `flags_int_value` "not provided" error
17. boolean long flag presence (`--verbose`)
18. `flags_parse_process` succeeds with no declared flags

Verification command (repository root):

```
& .\scripts\port.ps1 -Package xiom.flags
```

Expected tail: `port: PASS (passed=18 failed=0 exit=0)`.

## Known limitations and compiler notes

- `FlagParser` uses parallel arrays because the current compiler cannot hold
  `Vec[StructType]` containers reliably, and `StringMap` is `Str -> Int` only.
- String equality uses `xiom.string.str_compare(a, b) == 0`; `==` on `Str`
  elements read from a `Vec[Str]` is not reliable (BUG 17: pointer compare).
- `str_compare` is exported by `xiom.string.compare`, not by the umbrella
  `xiom.string` module; both `use xiom.string;` and `use xiom.string.compare;`
  are required. (Deviation from the porter brief, which listed `str_compare`
  under `use xiom.string;`.)
- Short flags are single-character only; clusters and attached values are
  rejected.
- A value-taking flag consumes the next argument as a value even when it
  looks like a flag; there is no `--name=` value escaping.
- `flags_parse_process` skips index 0 unconditionally, matching
  `xiom.os.args.args_raw()`'s documented argv convention.
- Help output is plain text; there is no wrapping or width negotiation.
