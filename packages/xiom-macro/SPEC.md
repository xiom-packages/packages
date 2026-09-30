# xiom.macro -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.macro` (`src/macro.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free, deterministic text macro-expansion processor over
in-memory `Str` values. One call takes a whole program (directives plus text)
and returns the expanded text:

- `macro_expand` -- process `define`/`undef` directives and expand all
  invocations, returning `Result[Str, Str]` (strict: the first error is an
  `Err`),
- `macro_expand_traced` -- the same, appending expansion-trace records,
- `macro_expand_with_limit` -- the same with an explicit nesting limit,
- `macro_names` -- validate directives only and list the live macro names.

The macro language is textual substitution. No code is evaluated, no context
stack exists, and there is no I/O.

## 2. Non-goals

- Any evaluation, typing, hygiene or name resolution of the produced text; the
  processor is a pure textual rewriter.
- Conditional expansion, loops, variadics, string/character literals,
  comments, includes/partials, or delimiters other than `$`.
- Multi-line directives or multi-line invocations.
- Re-scanning of expansion output: expanded text is never expanded again.
- Streaming/incremental APIs (one whole `Str` in, one whole `Str` out).
- Any FFI, file I/O or registry integration.

## 3. Grammar

Informal grammar over UTF-8 bytes (`SP` = ASCII space, 0x20; `LF` = 0x0A):

```
program    = *( directive-line | text-line )
text-line  = *( byte ) LF
directive  = "define" SP+ name [ "(" params ")" ] SP+ body
           | "undef"  SP+ name
name       = ident
ident      = ( letter | "_" ) *( letter | digit | "_" )
params     = param *( "," param )
param      = ident                       -- ASCII spaces around it are trimmed
body       = *( byte )                   -- to end of line, not trimmed

text       = *( byte | escape | invocation | positional | named )
escape     = "$$" | "\\$" | "\\\\" | "\\" byte
invocation = "$" name [ "(" arg *( "," arg ) ")" ]
positional = "$" digit+
named      = "$(" SP* name SP* ")"
arg        = text                        -- trimmed of ASCII spaces
```

Directive detection is per line: leading ASCII spaces are skipped, the keyword
must be exactly `define` or `undef` and must be followed by an ASCII space (or
end of line, which is then malformed). `defined`, `undefine` and other keyword
prefixes are ordinary text. A trailing `\r` before the `\n` is consumed with a
directive line.

## 4. Semantics

1. **Line scan.** `src` is split on `\n` (the `\n` is kept for text lines). The
   processor walks the lines in order; the macro table evolves as directives
   are seen, so text observes the definitions made above it.
2. **Directive.** `define NAME[(params)] body` binds `NAME` to its parameter
   list and body; a binding with the same name is replaced in place
   (`redefine`). `undef NAME` removes the binding (idempotent). Both consume
   the whole line, including its newline.
3. **Body start.** After the signature, all consecutive ASCII spaces are
   skipped and the body is the rest of the line up to `\r`/`\n`. The body is
   not otherwise trimmed; a zero-parameter macro may have an empty body.
4. **Parameters.** The region between the parentheses is split at commas;
   each segment is trimmed of ASCII spaces and must be an identifier. An empty
   region (or all spaces) declares zero parameters. Empty segments, non-
   identifier names and duplicate names are errors.
5. **Text expansion.** A text line is expanded left to right. `$NAME` and
   `$NAME(args)` invoke NAME; `args` is the region between balanced
   parentheses, split at top-level commas, each trimmed of ASCII spaces. A
   region that is empty or all spaces yields zero arguments; empty segments
   between commas are legal empty arguments.
6. **Resolution order.** On an invocation the processor first matches the
   parentheses (an unterminated `(` is an error), then resolves NAME (an
   unknown name is an error), then checks the argument count (an arity
   mismatch is an error), then the cycle and depth guards.
7. **Argument evaluation.** Arguments are expanded in the **caller's** frame
   (so a macro body can forward its own `$1` into another macro's arguments),
   left to right. The resulting values become the callee's frame.
8. **Body evaluation.** The body is expanded in the **callee's** frame:
   `$N`/`$(name)` insert the corresponding argument value byte-exact, and
   nested invocations are expanded. Inserted values and nested results are
   appended to the output and are never re-scanned.
9. **Escapes.** `$$` and `\$` each emit one literal `$`; `\\` emits one `\`;
   `\` before any other byte emits the backslash and that byte. A `$` followed
   by a byte that cannot start an invocation, a positional reference or a
   named reference is copied literally.
10. **Recursion, depth and cycles.** A macro is pushed on the active stack
    **before** its arguments and body are expanded, and popped afterwards. If
    NAME is already active, the call is `macro: cycle detected: NAME`. The
    depth of an invocation is its position on the stack (1 for a top-level
    call); a depth greater than the limit is
    `macro: recursion limit exceeded: NAME`. The default limit is 16.
    Consequently `$A($A(x))` (the same macro in its own argument) is a cycle,
    and a chain of distinct macros deeper than the limit is a recursion error.
11. **Trace.** `macro_expand_traced` / `macro_expand_with_limit` append one
    line per directive and per started expansion to the caller's `Vec[Str]`,
    never clearing it. Records are emitted in processing order, before the
    expansion they describe recurses.
12. **Trace record grammar.**

    ```
    record := "define "   name "/" arity
            | "redefine " name "/" arity
            | "undef "    name
            | "undef-missing " name
            | "expand "   name "/" argc " depth=" depth
    ```

13. **Encoding.** `Str` is an opaque UTF-8 byte buffer; scanning is byte-wise
    and all non-trigger bytes pass through byte-exact. Trigger bytes
    (`$ \ ( ) ,` and digits) are ASCII and cannot occur inside a multi-byte
    UTF-8 sequence. Identifiers are ASCII only.

## 5. Error catalog

Strict processing returns the first problem in scan order; partial output is
discarded. Error messages are exact.

| # | Condition | Message |
|---|---|---|
| 1 | `$NAME` / `$NAME(args)` with no binding | `macro: unknown macro: NAME` |
| 2 | argument count different from the declaration | `macro: arity mismatch: NAME expects N, got M` |
| 3 | NAME already on the active stack | `macro: cycle detected: NAME` |
| 4 | nesting depth greater than the limit | `macro: recursion limit exceeded: NAME` |
| 5 | `(` with no matching `)` on the line | `macro: unterminated call: NAME` |
| 6 | `$(` with no matching `)` | `macro: unterminated parameter reference` |
| 7 | `$(name)` where `name` is not a declared parameter | `macro: unknown parameter: NAME` |
| 8 | `$N` with N < 1 or N > the current frame's arity (including any `$N` in plain text, whose frame is empty) | `macro: no such argument: $N` |
| 9 | a parameter name declared twice | `macro: duplicate parameter: NAME` |
| 10 | structural problem in a `define` line | `macro: malformed define directive` |
| 11 | structural problem in an `undef` line | `macro: malformed undef directive` |
| 12 | `max_depth < 1` | `macro: bad depth limit: N` |

Error 10 covers a missing or invalid name, a missing body separator, an
unterminated parameter list, and non-identifier or empty parameter segments.
Error 11 covers a missing or invalid name and trailing non-space text.

## 6. API signatures

```xi
pub fn macro_expand(src: Str) -> Result[Str, Str]
pub fn macro_expand_traced(src: Str, trace: &mut Vec[Str]) -> Result[Str, Str]
pub fn macro_expand_with_limit(src: Str, max_depth: Int, trace: &mut Vec[Str]) -> Result[Str, Str]
pub fn macro_names(src: Str) -> Result[Vec[Str], Str]
```

Complexity: O(total bytes) for the scan plus O(invocations x table size) for
linear lookup; argument splitting and parameter lookup are linear in their
inputs. Output is built in one `xiom.string.builder` buffer (one allocation
per produced `Str`). `macro_names` performs no expansion; it validates
directives only and ignores text lines entirely, so invocation errors are not
raised by it. The table is stored as four parallel `Vec`s
(`names`, `arities`, `params`, `bodies`) that are always mutated together.

## 7. Test plan

`tests/test_conformance.xi` (module `macro_tests`) runs 25 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Every string comparison goes through
`xiom.string.compare.str_compare`; `Result` values are checked through
`is_ok` / `value` / `error`.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | plain text | no trigger bytes => byte-identical output (rule 1) |
| t2 | empty input | empty output (rule 1) |
| t3 | define + zero-arity call | `$GREET` invokes a definition (rules 2/5) |
| t4 | `$1..$N` | positional substitution (rule 8) |
| t5 | `$(name)` | named substitution (rule 8) |
| t6 | nested expansion + trace | body calls another macro; depths 1 and 2 (rules 10/11) |
| t7 | multiple calls + trimming | three calls on one line; `( a )` -> `a` (rules 5/7) |
| t8 | redefinition | the latest binding wins; `redefine` record (rules 2/12) |
| t9 | `undef` | removed binding => unknown macro (rules 2/1) |
| t10 | arity mismatch | too many arguments (rule 6 / error 2) |
| t11 | unknown macro | parenthesized unknown name (error 1) |
| t12 | unterminated call | no `)` on the line (error 5) |
| t13 | cycle | mutual recursion detected (error 3) |
| t14 | recursion limit | a distinct-macro chain deeper than the limit (error 4) |
| t15 | escapes | `$$` and `\$` in bodies and text (rule 9) |
| t16 | no re-scan | the inserted argument text `$1` stays literal (rule 8) |
| t17 | bare vs `()` | `$Z`/`$Z()` both work; bare call to arity 2 mismatches (rule 5) |
| t18 | directive trace | define/redefine/undef/undef-missing records (rule 12) |
| t19 | keyword prefixes | `defined`, `undefine`, `prefix define` stay text (rule 1) |
| t20 | malformed define | bad name, unterminated params, missing body (error 10) |
| t21 | duplicate parameter | named twice => error 9 |
| t22 | substitution errors | unknown parameter, `$2` with arity 1, `$1` in text (errors 7/8) |
| t23 | limit validation + `macro_names` | `max_depth < 1`; directive-only listing (errors 12/9) |
| t24 | unterminated `$(` | no `)` => error 6 |
| t25 | CRLF | a `\r` on a directive line is consumed; text bytes kept (rule 1) |

## 8. Known limitations

- Textual substitution only; the produced text is never evaluated.
- Directives and invocations are single-line.
- Expansion output is not re-scanned, so a macro cannot emit a directive or
  half of a call that later expands.
- A macro is disabled for its whole expansion (arguments included), so
  `$A($A(x))` is a cycle rather than nested use.
- `$` is always significant; literal dollars must be escaped.
- Only ASCII spaces are trimmed; tabs and newlines are ordinary bytes.
- Linear table lookup and linear argument splitting; very large macro sets
  want an external index.
- The error is the first problem in scan order; partial output is discarded.
- Identifiers are ASCII only; non-ASCII bytes are literal text.

## 9. Compiler / stdlib notes

The module uses the proven v0.62.1 idioms from the sibling packages
(`xiom.template`, `xiom.escape`): byte-wise scanning via
`xiom.string.byte_at` normalized as `(byte_at(s, i) as Int) & 0xFF`,
single-allocation output through `xiom.string.builder`
(`sb_new` / `sb_push_str` / `sb_push_byte` / `sb_to_str`), and free functions
only. Deliberate workarounds:

- `Ok`/`Err` for `Result[Str, Str]` and `Result[Vec[Str], Str]` are built only
  in the leaf helpers `_ok_str`/`_err_str`/`_ok_vec`; scalar `Result[Int, Str]`
  values (`_process_line`, `_run_lines`) use direct `Ok(0)`/`Err`.
- Every string comparison goes through `xiom.string.compare.str_compare`
  instead of `==` (BUG 17 on `Vec[Str]` elements); element reads are bound to
  typed locals first.
- Int formatting uses `xiom.convert.int_to_string` (`sb_push_int` is unsafe
  for `INT_MIN`).
- The macro table is four parallel `Vec`s mutated together by `_table_put` /
  `_table_remove`, so the arrays cannot drift.
- The conformance suite avoids inline lambdas, `mut` patterns, `Vec[fn]`
  dispatch and non-exhaustive `match`es by using one explicit `fn` per check
  and explicit `main` dispatch, like the sibling suites.
