# xiom.macro

> **Status:** `incubating` -- conformance-tested (25/25); not yet published on the XIOM registry.
> **Scope:** a pure, deterministic text macro-expansion processor: `define` /
> `undef` directives, parameterized invocation with arity checking, `$1..$N`
> and `$(name)` substitution, recursion depth limiting and cycle detection,
> escaped delimiters (`$$`, `\$`) and an expansion trace.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare` and `xiom.convert`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.macro` is a small, dependency-free text preprocessor. It takes a whole
program as one `Str` and returns the expanded text: lines that define or
remove macros are consumed, and every other line is expanded against the
macro table as it stands at that point. There is no code evaluation, no file
I/O and no state outside the call: every function is a pure `Str` operation.
`SPEC.md` has the full grammar, semantics, error catalog and test plan.

The processor is intentionally strict and predictable:

- a macro is a text template; invocation is textual substitution only,
- arguments are trimmed of ASCII spaces, expanded in the caller's frame and
  inserted into the body byte-exact (inserted text is never re-scanned),
- a macro is disabled while it expands, so indirect recursion is reported as
  a cycle instead of looping,
- everything is deterministic and left to right: the first problem is the
  reported error.

## API

| Function | Returns | Description |
|---|---|---|
| `macro_expand(src)` | `Result[Str, Str]` | Process directives and expand all text. `Err` carries the first error message. |
| `macro_expand_traced(src, trace)` | `Result[Str, Str]` | As `macro_expand`, appending one record per directive and expansion to `trace`. |
| `macro_expand_with_limit(src, max_depth, trace)` | `Result[Str, Str]` | As `macro_expand_traced` with an explicit nesting limit (`max_depth >= 1`). |
| `macro_names(src)` | `Result[Vec[Str], Str]` | Validate directives only (text is ignored) and return the live macro names in definition order. |

Expansion is O(n) over the input plus a linear table lookup per invocation.
Output is built in one `xiom.string.builder` buffer.

## Language

- **Directives** (one per line, leading ASCII spaces allowed):

  ```
  define NAME body                 -- zero-parameter macro
  define NAME(p1, p2) body         -- parameterized macro
  undef NAME                       -- remove a binding (idempotent)
  ```

  A directive line and its newline are removed from the output. A redefinition
  replaces the previous binding. The body is everything after the first run of
  ASCII spaces following the signature; it is not trimmed further.
- **Invocation** in text and in bodies: `$NAME` or `$NAME(args)`. `$NAME` is a
  zero-argument call, so `$Z` and `$Z()` are equivalent. Arguments are
  separated by top-level commas; parentheses nest.
- **Substitution** inside a body: `$1`..`$N` (1-based) and `$(name)`.
- **Escapes:** `$$` and `\$` each emit one literal `$`. A `$` followed by any
  other byte is copied literally; a `\` followed by anything other than `\` or
  `$` is copied together with the next byte.
- **Lines** are split on `\n`; a trailing `\r` on a directive line is consumed
  with it, and text bytes (including `\r`) pass through byte-exact.

## Usage

```xi
use xiom.macro;
use xiom.io;

fn main() -> Int {
  let program = "define GREET(name) Hello, $(name)!\n$GREET(Ada)\n";
  match macro_expand(program) {
    Ok(text) => { io.println(text); },   // Hello, Ada!
    Err(e)   => { io.println(e); },
  }
  return 0;
}
```

## Errors

`macro_expand` returns the first of these messages, exactly:

| Condition | Message |
|---|---|
| `$NAME(...)` with no definition | `macro: unknown macro: <name>` |
| wrong argument count | `macro: arity mismatch: <name> expects N, got M` |
| re-entry of an active macro | `macro: cycle detected: <name>` |
| nesting deeper than the limit | `macro: recursion limit exceeded: <name>` |
| `(` with no `)` on the line | `macro: unterminated call: <name>` |
| `$(` with no `)` | `macro: unterminated parameter reference` |
| `$(name)` not a declared parameter | `macro: unknown parameter: <name>` |
| `$N` out of range (or in plain text) | `macro: no such argument: $N` |
| a parameter name declared twice | `macro: duplicate parameter: <name>` |
| malformed `define` line | `macro: malformed define directive` |
| malformed `undef` line | `macro: malformed undef directive` |
| `max_depth < 1` | `macro: bad depth limit: <n>` |

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.macro
```

Expected tail: 25 `[PASS]` lines, `xiom.macro: all tests passed`, then
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## Limitations

- Text macro expansion only; nothing is evaluated. Directives are
  single-line, cannot span lines, and expansion output is not re-scanned for
  directives.
- Calls do not span lines: an invocation must open and close on one line.
- A macro is disabled for the whole duration of its expansion, including
  while its own arguments are expanded, so `$A($A(x))` is a cycle error.
- Only ASCII spaces (0x20) are trimmed, and only from argument edges and
  inside parameter lists; tabs and other whitespace are ordinary bytes.
- `$` is always significant: a literal dollar sign in text must be written
  `$$` or `\$`.
- No conditional expansion, no variadic macros, no string/character literals
  in the macro language, and no include/partial mechanism.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
