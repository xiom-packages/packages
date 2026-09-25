# xiom.smtlib

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** an SMT-LIB2 command/term reader for a documented subset plus a
> canonical emitter, over a flat node model.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare` and `xiom.convert`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.smtlib` parses SMT-LIB2 text into a flat, index-based model and writes
it back in a canonical form. The supported subset is the s-expression
surface: simple symbols, keywords (`:produce-models`), numerals, decimals
(kept as validated text tokens), strings with doubled-quote and backslash
escapes, `;` line comments, and the top-level commands `set-logic`,
`set-option`, `set-info`, `declare-const`, `declare-fun`, `define-fun`,
`assert`, `check-sat`, `get-model` and `exit` with fixed shapes. Term bodies
are pass-through data: the parser does not solve, sort-check, type-infer or
validate SMT-LIB 2.6 semantics.

The parser is a byte-wise recursive descent over one `Str` with no C library
and only free functions. The document is *flat*: nodes live in parallel
vectors (`kinds`, `texts`, `parents`) and children are one `Vec[Int]`
addressed through `child_starts` / `child_lengths` ranges, so a node's
children are a contiguous slice regardless of nesting. This is the ecosystem
pattern for XIOM v0.61.3, where `Vec[StructType]` is unsupported. A separate
command index records the root node of every top-level command.

Every malformed construct is a deterministic `Err("smtlib: ...")` that
carries the offending byte offset where one exists; the full catalog is in
`SPEC.md`. `smtlib_emit` prints one command per line with single spaces
between list elements and canonical string escapes, and it is stable under
reparse.

## API

| Function | Returns | Description |
|---|---|---|
| `smtlib_parse(text)` | `Result[SmtDoc, Str]` | Parse a whole document; `Err("smtlib: ...")` on malformed input. |
| `smtlib_emit(d)` | `Str` | Canonical text: one command per line, single spaces, re-escaped strings, no trailing newline. |
| `smtlib_kind_list()` | `Int` | Kind code 0. |
| `smtlib_kind_symbol()` | `Int` | Kind code 1. |
| `smtlib_kind_keyword()` | `Int` | Kind code 2. |
| `smtlib_kind_numeral()` | `Int` | Kind code 3. |
| `smtlib_kind_decimal()` | `Int` | Kind code 4. |
| `smtlib_kind_string()` | `Int` | Kind code 5. |
| `smtlib_kind_name(k)` | `Str` | `"list"`, `"symbol"`, `"keyword"`, `"numeral"`, `"decimal"`, `"string"`; `""` for any other value. |
| `smtlib_max_depth()` | `Int` | Documented nesting limit: 128 lists on a path. |
| `smtlib_node_count(d)` | `Int` | Number of nodes (0 for an empty document). |
| `smtlib_command_count(d)` | `Int` | Number of top-level commands (emit writes this many lines). |
| `smtlib_kind(d, i)` | `Int` | Kind code of node `i`; `-1` out of range. |
| `smtlib_node_text(d, i)` | `Str` | Source text for symbols/keywords/numerals/decimals, decoded text for strings, `""` for lists and out-of-range indices. |
| `smtlib_symbol_text(d, i)` | `Str` | Text of node `i` when it is a symbol, else `""`. |
| `smtlib_parent(d, i)` | `Int` | Containing list node, `-1` for a command root or out of range. |
| `smtlib_child_count(d, i)` | `Int` | Direct child count; `0` for an atom or out of range. |
| `smtlib_child_start(d, i)` | `Int` | First entry of node `i`'s child range in `SmtDoc.children`; `-1` out of range. |
| `smtlib_child(d, i, n)` | `Int` | n-th direct child (0-based) of node `i`; `-1` out of range. |
| `smtlib_node_start(d, i)` | `Int` | Byte offset of the node's first byte; `-1` out of range. |
| `smtlib_node_end(d, i)` | `Int` | Byte offset one past the node's last byte; `-1` out of range. |
| `smtlib_command_node(d, c)` | `Int` | Root node of command `c`; `-1` out of range. |
| `smtlib_command_head(d, c)` | `Int` | Head symbol node of command `c`; `-1` out of range. |
| `smtlib_command_name(d, c)` | `Str` | Head symbol text of command `c`; `""` out of range. |
| `smtlib_command_arg_count(d, c)` | `Int` | Argument count (head excluded); `0` out of range. |
| `smtlib_command_arg(d, c, a)` | `Int` | Node of argument `a` (0-based); `-1` when either index is out of range. |

The `SmtDoc` fields are documented in the module source; callers should use
the accessors. Out-of-range accessors never panic and always return `-1`,
`0` or `""`.

## Quick start

```xi
use xiom.smtlib;
use xiom.io;

fn main() -> Int {
  let src = "(set-logic QF_LIA)\n(declare-const x Int)\n(assert (> x 0))\n(check-sat)\n";
  let r = smtlib_parse(src);
  if !r.is_ok {
    io.println("parse error: " + r.error);
    return 1;
  }
  let d = r.value;
  io.println(smtlib_command_name(&d, 0));                 // set-logic
  io.println(smtlib_command_name(&d, 2));                 // assert
  let term = smtlib_command_arg(&d, 2, 0);                // the (> x 0) list
  io.println(smtlib_kind_name(smtlib_kind(&d, term)));    // list
  io.println(smtlib_symbol_text(&d, smtlib_child(&d, term, 0)));  // >
  io.println(smtlib_emit(&d));                            // canonical form
  return 0;
}
```

For the document above, `smtlib_emit` produces exactly:

```
(set-logic QF_LIA)
(declare-const x Int)
(assert (> x 0))
(check-sat)
```

## Error model

Every parse failure is `Err(msg)` with `msg` starting with `"smtlib: "`; the
parser stops at the first failure and the message is deterministic, e.g.
`smtlib: unbalanced parenthesis at 14`, `smtlib: unterminated string at 16`,
`smtlib: declare-fun expects 3 arguments, got 2` or
`smtlib: declare-const expects a sort at 17`. Comments are dropped from the
emitted form. Accessors never fail; they return sentinel values out of range
(see the API table).

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.smtlib
```

Expected tail: 24 `[PASS]` lines, `xiom.smtlib: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **A documented subset, not the whole language.** Only the ten commands
  above are recognized; `declare-sort`, `define-sort`, `push`, `pop`,
  `get-assertions`, `define-fun-rec` and every other command are
  `smtlib: unknown command`. Attribute values in `set-option`/`set-info`
  must be atoms; s-expression values are rejected.
- **No semantics.** No solving, no sort checking, no type inference, no
  proof handling. Nested lists and sort expressions are pass-through, and a
  term may contain anything once its top level is structurally a term.
- **No quoted symbols or special constants.** `|...|` symbols, `#x`/`#b`
  constants and `\u{...}` escapes are rejected (`smtlib: unexpected byte`
  or `smtlib: invalid escape`).
- **Numbers are text.** A numeral is `0` or `[1-9][0-9]*`; a decimal is
  `<numeral>.<digits>`. Leading zeros, a dangling dot and a symbol character
  directly after the digits are `smtlib: malformed numeric token`; the text
  is preserved verbatim (no float conversion, no rounding).
- **First failure only.** No error recovery, no partial document on `Err`,
  no line/column tracking (byte offsets only).
- **Depth limit.** A list nested at depth 128 is
  `smtlib: nesting depth exceeds limit of 128` (128 lists on a path are
  accepted).
- **Comments are not preserved.** `smtlib_emit` is canonical, not a
  pretty-printer for the original formatting.
- **Input encoding.** `Str` is treated as a UTF-8 byte buffer; scanning is
  byte-wise, multi-byte sequences pass through untouched, and a raw NUL byte
  is rejected. The input is not UTF-8-validated.
- **No file I/O or streaming.** `smtlib_parse` consumes a whole `Str`.

See `SPEC.md` for the grammar subset, the command table, the API contract,
the full error catalog and the test matrix. License: MIT OR Apache-2.0 (see
the repository root `LICENSE`).
