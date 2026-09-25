# xiom.dimacs -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.dimacs` (`src/dimacs.xi`). Pure XIOM, no FFI.

## 1. Scope

A small, dependency-free codec for the classic DIMACS CNF file format:

- `dimacs_parse` reads a whole `Str` document into a flat `Cnf` value with
  strict validation,
- `dimacs_emit` writes a `Cnf` back in canonical DIMACS CNF form,
- `dimacs_new` / `dimacs_add_clause` build formulas programmatically,
- read-only accessors expose counts, clause boundaries and literals.

`Str` is treated as a UTF-8 byte buffer; all scanning is byte-wise and the
format itself is ASCII. Comment bodies are skipped byte-exactly (bytes are
never split or rewritten).

## 2. Non-goals

- No SAT solving, no unit propagation, no clause learning, no simplification.
- No max-SAT/WCNF (`p wcnf`), OPB, or `p sat`-style variants; only the
  `p cnf <vars> <clauses>` header is accepted.
- No streaming/incremental parsing: the whole document is one `Str`.
- No preservation of formatting or comments; emission is canonical.
- No BOM handling, no Unicode syntax, no escape sequences.
- No `+` signs, no hexadecimal/underscore digit forms, no floating point.
- No formula transformations (renumbering, clause normalisation, ...).

## 3. Grammar and semantics

Informal grammar (`hspace` = space or tab; a line ends at LF, CR or CRLF):

```
document     = *line
line         = comment-line | blank-line | header-line | token-line
comment-line = *hspace "c" *any-byte
blank-line   = *hspace
header-line  = *hspace "p" 1*hspace "cnf" 1*hspace uint 1*hspace uint *hspace
token-line   = 1*( 1*hspace token ) *hspace
token        = literal | "0"
literal      = ["-"] 1*digit
uint         = 1*digit                        (fits in an Int)
```

A `header-line` may also be the last line without a trailing terminator.
Clauses are not line-scoped: the parser consumes the token stream after the
header and closes the clause in progress at every `0`.

Decisions (each one is covered by the conformance suite):

1. **Line terminators.** LF, CRLF and a lone CR each end a line; the 1-based
   line number in error messages counts those boundaries. A CR immediately
   followed by LF consumes both bytes as one boundary.
2. **Comments.** A line whose first non-whitespace byte is `c` is ignored
   entirely, anywhere: before the header, between clause lines and inside a
   clause that spans several lines. A `c` that is not the first non-whitespace
   byte of its line is an invalid token. Blank/whitespace-only lines are
   ignored too.
3. **Header.** Exactly one header line, before any clause token. It is
   exactly `p`, `cnf`, the variable count and the clause count, separated by
   one or more spaces/tabs, followed only by spaces/tabs to the end of the
   line. Both counts are non-negative decimal integers that must fit in an
   `Int`. A second header is `dimacs: duplicate header`; any other shape is a
   malformed-header error (section 5).
4. **Clauses.** After the header, the document is a token stream. Every
   non-zero literal accumulates into the clause in progress; a `0` closes it
   and starts the next. One clause may span several lines, several clauses
   may share one line, and a bare `0` is a valid empty clause. Comment and
   blank lines may appear between any two tokens when they start a line.
5. **Literals.** A literal is an optional `-` followed by one or more ASCII
   digits. `+` is not accepted, `--1` is not accepted, and `-0` is the
   dedicated negative-zero error. A non-zero literal's magnitude must satisfy
   `1 <= |literal| <= vars`; larger magnitudes are out of range.
6. **Header counts.** `clauses` must be exactly the number of `0`-terminated
   clauses in the document. Once that many clauses are closed, any further
   token is rejected as `dimacs: token after final clause` (this also covers
   trailing garbage and documents with more clauses than declared).
7. **End of input.** If a clause is still open (one or more literals with no
   terminating `0`), parsing fails with `dimacs: unterminated clause at end
   of input`, even when the declared clause count has not been reached. With
   no open clause, a closed-clause count different from the header is
   `dimacs: clause count mismatch: expected <declared>, got <closed>`.
8. **Bounds.** A decimal run whose value does not fit in an `Int` is an
   overflow: `dimacs: integer overflow` for a literal, `invalid variable
   count` / `invalid clause count` in the header. Values are never wrapped.
9. **Check order.** For a token position the parser checks, in order: header
   presence, "all declared clauses already closed", token shape, overflow,
   negative zero, range, then clause closing. So a malformed token after the
   last declared clause reports the trailing-token error, not the shape
   error.
10. **Determinism.** The same input always yields the same `Cnf` or the same
    first `Err` message; parsing never mutates its input.
11. **Canonical emission.** `dimacs_emit` writes `p cnf <vars> <clauses>`
    followed by one line per clause: literals in order separated by single
    spaces and followed by ` 0`; the empty clause is the single token `0`;
    every line, including the header, ends with LF. Zero clauses yield only
    the header line. `emit(parse(emit(parse(t))))` equals `emit(parse(t))`
    for every accepted `t`.
12. **Round trip.** For any accepted document, `dimacs_parse(dimacs_emit(f))`
    yields the same `vars`, `clauses` and literal sequence as `f`.
13. **Out-of-range accessors.** `dimacs_clause_start` and `dimacs_clause_len`
    return `-1` for a negative or too-large clause index; `dimacs_literal`
    and `dimacs_clause_literal` return `0` for out-of-range positions (0 is
    never a literal, so it is an unambiguous sentinel).
14. **Builder contract.** `dimacs_new` and `dimacs_add_clause` do not
    validate: callers must pass non-zero literals with `|literal| <= vars`.
    `dimacs_emit` assumes the documented `Cnf` invariants; a hand-built
    formula outside them produces text outside this specification.

## 4. API signatures

```xi
pub type Cnf = { vars: Int; clauses: Int; lits: Vec[Int]; offs: Vec[Int]; }

pub fn dimacs_parse(text: Str) -> Result[Cnf, Str]
pub fn dimacs_emit(c: &Cnf) -> Str
pub fn dimacs_new(vars: Int) -> Cnf
pub fn dimacs_add_clause(c: &mut Cnf, clause: &Vec[Int])
pub fn dimacs_var_count(c: &Cnf) -> Int
pub fn dimacs_clause_count(c: &Cnf) -> Int
pub fn dimacs_literal_count(c: &Cnf) -> Int
pub fn dimacs_literal(c: &Cnf, i: Int) -> Int
pub fn dimacs_clause_start(c: &Cnf, k: Int) -> Int
pub fn dimacs_clause_len(c: &Cnf, k: Int) -> Int
pub fn dimacs_clause_literal(c: &Cnf, k: Int, j: Int) -> Int
```

`Cnf` is flat: `clauses + 1` offsets with `offs[0] == 0` and
`offs[clauses] == lits.len()`; clause `k` is `lits[offs[k] .. offs[k + 1]]`.
`dimacs_parse` is O(n) over the document with O(1) work per byte;
`dimacs_emit` is O(n) over the output; all accessors are O(1).

## 5. Error catalog

Every failure is the first one encountered and is returned as
`Err(message)`, built deterministically with `xiom.convert.int_to_string`.

| Message | Condition |
|---|---|
| `dimacs: missing header at line <n>` | a clause token appears before the `p` line |
| `dimacs: missing header at end of input` | input is empty, comment-only or blank-only |
| `dimacs: duplicate header at line <n>` | a second `p` line |
| `dimacs: malformed header at line <n>` | the `p` line is not exactly `p cnf <uint> <uint>` (wrong word, missing separator, trailing content) |
| `dimacs: invalid variable count at line <n>` | the variable position is not digits or does not fit in an `Int` |
| `dimacs: invalid clause count at line <n>` | the clause position is not digits or does not fit in an `Int` |
| `dimacs: invalid token at line <n>` | a byte other than `-` or a digit starts a token, or `-` is not followed by a digit |
| `dimacs: integer overflow at line <n>` | a literal's decimal magnitude does not fit in an `Int` |
| `dimacs: negative literal 0 at line <n>` | the token `-0` |
| `dimacs: literal out of range at line <n>` | a non-zero literal with magnitude greater than `vars` |
| `dimacs: token after final clause at line <n>` | any token once the declared clause count is closed |
| `dimacs: unterminated clause at end of input` | end of input with pending (non-terminated) literals |
| `dimacs: clause count mismatch: expected <declared>, got <closed>` | end of input with no open clause and fewer closed clauses than declared |

`<n>` is 1-based. Messages contain no trailing punctuation and no variable
text beyond these numbers.

## 6. Test plan

`tests/test_conformance.xi` (module `dimacs_tests`) runs 25 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | parse counts/flat/boundaries | vars, clauses, literal sequence, clause starts and widths (rules 4, 13) |
| t2 | comments/blank anywhere | comments before the header, between clauses and inside a split clause (rule 2) |
| t3 | split clause | one clause across three lines (rule 4) |
| t4 | empty clauses | bare `0` closes a zero-literal clause; `vars = 0` (rules 4, 5) |
| t5 | header-only | zero clauses parse; emit is the header line (rules 11, 6) |
| t6 | line endings | LF, CRLF and lone CR (rule 1) |
| t7 | missing header | clause token before the header (section 5) |
| t8 | missing header at EOF | empty, comment-only and blank-only input (section 5) |
| t9 | duplicate header | exactly one header (rules 3) |
| t10 | malformed header | truncated, wrong word, trailing content (rule 3) |
| t11 | header counts | non-digits rejected, `INT_MAX` accepted, overflow rejected (rules 3, 8) |
| t12 | clause count mismatch | fewer clauses than declared (rule 7) |
| t13 | unterminated clause | missing terminator, including over a pending mismatch (rule 7) |
| t14 | token after final clause | trailing garbage and a zero-clause header (rule 6) |
| t15 | literal out of range | positive and negative magnitudes above `vars` (rule 5) |
| t16 | negative literal 0 | `-0` rejected with its own message (rule 5) |
| t17 | invalid tokens | `x`, `+` and `--1` (rule 5) |
| t18 | integer overflow | literal magnitude beyond `INT_MAX` (rule 8) |
| t19 | canonical emit | spacing, one clause per line, LF (rule 11) |
| t20 | parse/emit/parse | canonical document and a document with an empty clause (rules 11, 12) |
| t21 | builders | `dimacs_new` + `dimacs_add_clause`, then emit (rule 14) |
| t22 | accessor sentinels | `-1` / `0` for negative and beyond-end indices (rule 13) |
| t23 | clauses per line | three clauses on one line (rule 4) |
| t24 | whitespace and EOF | leading whitespace before `c`/`p`, missing final newline (rules 1, 2, 3) |
| t25 | range boundary | `|literal| == vars` accepted, including `vars = 1` (rule 5) |

All `Str` comparisons go through `xiom.string.compare.str_compare` (BUG 17:
`==` on `Str` values read from `Vec[Str]` elements lowers to a pointer
comparison); error checks compare the entire message, not a substring.

## 7. Known limitations

- Strict by design: mismatched clause counts and trailing tokens are errors,
  not warnings; lenient parsers would accept some documents this one rejects.
- One clause cannot continue after its `0`: content after a terminator is
  only legal while more clauses are still declared (rule 6).
- ASCII-only syntax; a UTF-8 BOM or any non-ASCII byte outside a comment is
  an invalid token or malformed header.
- No `+` sign support, no `-0`, no `p wcnf`/OPB/`p sat` headers.
- In-memory, single pass; no streaming, no line/column spans, no partial
  results on `Err`.
- Canonical emission discards comments and original spacing; it is not a
  formatting-preserving round trip.
- `dimacs_add_clause` does not validate literals; `dimacs_emit` assumes the
  `Cnf` invariants (rule 14).
- Comment lines are recognised only when `c` is the first non-whitespace byte
  of a line; trailing comments after a clause `0` are malformed.

## 8. Compiler / stdlib notes

XIOM v0.61.3 workarounds used (same shape as the other ported codecs):

- Free functions only; no methods on `Cnf`.
- No `Vec[StructType]`: clause storage is the parallel `lits`/`offs` pair.
- `Ok`/`Err` construction lives only in the leaf helpers `_ok_cnf` /
  `_err_cnf`; `dimacs_parse` builds the `Cnf` and passes it to `_ok_cnf`.
- Every `Vec[Int]` element read is bound to a local first
  (`let lit: Int = c.lits[i];`); no element read is used untyped.
- Str equality is never needed inside the module: comments, the `cnf` word and
  digit runs are recognised byte-wise with `xiom.string.byte_at`.
- `_DM_INT_MAX` is a module-local `const` copy of `xiom.core.INT_MAX`
  (`9223372036854775807`) so the package imports only `xiom.string` and
  `xiom.convert`; the overflow check is `acc > (max - digit) / 10` before
  each accumulate step.
- `_scan_uint` returns a `(value, next, status)` tuple (the stdlib
  `xiom.convert.atoi` shape); callers bind the fields to locals.
