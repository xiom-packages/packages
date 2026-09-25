# xiom.dimacs

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** DIMACS CNF parsing and canonical emission with strict
> validation: comments, the `p cnf` header, signed literals, split clauses.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at` and
> `xiom.convert.int_to_string`). Tests additionally use `xiom.test`, `xiom.io`
> and `xiom.string.compare`.

## Scope

`xiom.dimacs` is a byte-wise codec for the classic DIMACS CNF subset: `c`
comment lines and blank lines are skipped anywhere, exactly one
`p cnf <vars> <clauses>` header must precede the clause data, and each clause
is a run of non-zero signed decimal literals terminated by `0`. A clause may
be split across lines and several clauses may share one line. The parser is
strict: it rejects wrong header counts, literals outside `1..vars`, missing
zero terminators, content after the last declared clause, `-0`, and decimal
overflow. `dimacs_emit` writes the canonical form (one clause per line,
single-space separators, LF terminators).

Formulas are stored flat -- `lits` holds every literal in document order and
`offs` holds the `clauses + 1` clause boundaries -- so no `Vec[StructType]` is
needed anywhere.

## API

| Function | Returns | Description |
|---|---|---|
| `dimacs_parse(text)` | `Result[Cnf, Str]` | Parse a whole document; `Err` carries the first failure with its line. |
| `dimacs_emit(c)` | `Str` | Canonical DIMACS text: header plus one clause per line, ` 0`-terminated. |
| `dimacs_new(vars)` | `Cnf` | Empty formula with `vars` variables and zero clauses. |
| `dimacs_add_clause(c, clause)` | nothing | Append one clause (literals in order) to a mutable formula. |
| `dimacs_var_count(c)` | `Int` | Declared variable count. |
| `dimacs_clause_count(c)` | `Int` | Clause count. |
| `dimacs_literal_count(c)` | `Int` | Total literal count across all clauses. |
| `dimacs_literal(c, i)` | `Int` | Flat literal `i` (document order); `0` when out of range. |
| `dimacs_clause_start(c, k)` | `Int` | Flat index of clause `k`'s first literal; `-1` out of range. |
| `dimacs_clause_len(c, k)` | `Int` | Width of clause `k` (`0` for the empty clause); `-1` out of range. |
| `dimacs_clause_literal(c, k, j)` | `Int` | Literal `j` of clause `k`; `0` out of range (literals are never `0`). |

## Usage

```xi
use xiom.dimacs;
use xiom.io;

fn main() -> Int {
  let r = dimacs_parse("c tiny\np cnf 3 2\n1 -3 0\n2 0\n");
  match r {
    Ok(f) => {
      io.println(dimacs_clause_count(&f));           // 2
      io.println(dimacs_clause_len(&f, 0));          // 2
      io.println(dimacs_clause_literal(&f, 0, 1));   // -3
      io.println(dimacs_emit(&f));                   // p cnf 3 2
                                                     // 1 -3 0
                                                     // 2 0
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

Building a formula without parsing works the same way:

```xi
var f = dimacs_new(2);
var clause = Vec[Int].new();
clause.push(1);
clause.push(-2);
dimacs_add_clause(&mut f, &clause);
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.dimacs
```

Expected tail: 25 `[PASS]` lines, `xiom.dimacs: all tests passed`, then
`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`.

## Limitations

- Not a solver: no SAT search, no pre-processing, no CNF transformations.
- CNF only: the max-SAT/WCNF and OPB variants, and the `p sat`/`p opb`
  headers, are out of scope.
- Strict input: the clause count must match exactly and no token may follow
  the last declared clause, so lenient documents with trailing garbage are
  rejected rather than guessed.
- `+` signs are not accepted (`+1` is an invalid token), `-0` is an error,
  and a decimal run that does not fit in an `Int` overflows.
- One clause never continues after its `0`; empty clauses (a bare `0`) are
  supported.
- In-memory only: the whole document is a `Str`; there is no streaming API.
- No BOM stripping and no non-ASCII syntax; comment bodies are ignored
  byte-exactly but the rest of the format is ASCII.
- Comments are whole lines only (first non-whitespace byte `c`); a trailing
  comment after a header or clause token is malformed.
- Emission is canonical: comments, spacing and line breaks are not preserved.
- `dimacs_add_clause` and `dimacs_emit` assume their input obeys the `Cnf`
  invariants (non-zero literals with `|literal| <= vars`); the builder does
  not re-validate them.

See `SPEC.md` for the exact grammar, error catalog and test plan. License:
MIT OR Apache-2.0 (see the repository root `LICENSE`).
