# xiom.lcov

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** an LCOV tracefile parser and canonical emitter for the documented
> record subset: `TN`, `SF`, `FN`, `FNDA`, `FNF`, `FNH`, `DA`, `LF`, `LH`,
> `BRDA`, `BRF`, `BRH` and `end_of_record`.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_starts_with`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.lcov` reads one in-memory LCOV tracefile `Str` into a flat `LcovDoc`
and writes it back in a canonical form. It is a codec, not a coverage tool:
it never instruments code, runs gcov, merges reports or renders HTML. The
accepted input is the subset specified in `SPEC.md`: optional `TN:<test
name>` labels, `SF:<source file>` sections closed by `end_of_record`,
function records (`FN`, `FNDA`, `FNF`, `FNH`), line records (`DA`, `LF`,
`LH`) and branch records (`BRDA`, `BRF`, `BRH`). Blank lines are ignored and
LF/CRLF both work. Anything outside the subset is a deterministic
`Err("lcov: ...")` carrying a 1-based line number.

Storage is flat: every file section owns an `(offset, count)` range into four
index-aligned record stores (FN, FNDA, DA, BRDA), because XIOM v0.61.3 cannot
hold `Vec[StructType]`. Declared `FNF`/`FNH`/`LF`/`LH`/`BRF`/`BRH` records are
kept per file, and the corresponding summary values can be computed from the
records. A declared-vs-computed mismatch is **tolerated** (never an error) and
exposed through `lcov_*_mismatch`, so a caller can decide whether lcov's own
totals are trustworthy.

## API

| Function | Returns | Description |
|---|---|---|
| `lcov_parse(text)` | `Result[LcovDoc, Str]` | Parse a whole tracefile; `Err` carries an `lcov: ...` message with a line number. |
| `lcov_emit(d)` | `Str` | The whole document in canonical record order, LF-terminated. |
| `lcov_doc_new()` | `LcovDoc` | An empty document (no file sections, no records). |
| `lcov_file_count(d)` | `Int` | Number of `SF` sections. |
| `lcov_file_source(d, f)` | `Str` | Source path of file section `f`; `""` out of range. |
| `lcov_file_test_name(d, f)` | `Str` | Test name that labelled section `f`; `""` when none. |
| `lcov_declared_fnf(d, f)` | `Int` | Declared `FNF` value; `-1` when absent. |
| `lcov_declared_fnh(d, f)` | `Int` | Declared `FNH` value; `-1` when absent. |
| `lcov_declared_lf(d, f)` | `Int` | Declared `LF` value; `-1` when absent. |
| `lcov_declared_lh(d, f)` | `Int` | Declared `LH` value; `-1` when absent. |
| `lcov_declared_brf(d, f)` | `Int` | Declared `BRF` value; `-1` when absent. |
| `lcov_declared_brh(d, f)` | `Int` | Declared `BRH` value; `-1` when absent. |
| `lcov_computed_fnf(d, f)` | `Int` | Number of `FN` records. |
| `lcov_computed_fnh(d, f)` | `Int` | Number of `FNDA` records with a positive hit count. |
| `lcov_computed_lf(d, f)` | `Int` | Number of `DA` records. |
| `lcov_computed_lh(d, f)` | `Int` | Number of `DA` records with a positive hit count. |
| `lcov_computed_brf(d, f)` | `Int` | Number of `BRDA` records. |
| `lcov_computed_brh(d, f)` | `Int` | Number of `BRDA` records with a taken count `>= 1`. |
| `lcov_fnf_mismatch(d, f)` | `Bool` | `true` when a declared `FNF` exists and differs from the computed value. |
| `lcov_fnh_mismatch(d, f)` | `Bool` | Same for `FNH`. |
| `lcov_lf_mismatch(d, f)` | `Bool` | Same for `LF`. |
| `lcov_lh_mismatch(d, f)` | `Bool` | Same for `LH`. |
| `lcov_brf_mismatch(d, f)` | `Bool` | Same for `BRF`. |
| `lcov_brh_mismatch(d, f)` | `Bool` | Same for `BRH`. |
| `lcov_fn_count(d, f)` | `Int` | Number of `FN` records in section `f`. |
| `lcov_fn_line(d, f, i)` | `Int` | Declaration line of `FN` record `i`; `-1` out of range. |
| `lcov_fn_name(d, f, i)` | `Str` | Name of `FN` record `i`; `""` out of range. |
| `lcov_fnda_count(d, f)` | `Int` | Number of `FNDA` records in section `f`. |
| `lcov_fnda_hits(d, f, i)` | `Int` | Execution count of `FNDA` record `i`; `-1` out of range. |
| `lcov_fnda_name(d, f, i)` | `Str` | Name of `FNDA` record `i`; `""` out of range. |
| `lcov_da_count(d, f)` | `Int` | Number of `DA` records in section `f`. |
| `lcov_da_line(d, f, i)` | `Int` | Line number of `DA` record `i`; `-1` out of range. |
| `lcov_da_hits(d, f, i)` | `Int` | Execution count of `DA` record `i`; `-1` out of range. |
| `lcov_da_has_checksum(d, f, i)` | `Bool` | `true` when `DA` record `i` carried a checksum field. |
| `lcov_da_checksum(d, f, i)` | `Str` | Checksum of `DA` record `i`; `""` when absent or out of range. |
| `lcov_brda_count(d, f)` | `Int` | Number of `BRDA` records in section `f`. |
| `lcov_brda_line(d, f, i)` | `Int` | Line number of `BRDA` record `i`; `-1` out of range. |
| `lcov_brda_block(d, f, i)` | `Str` | Block field of `BRDA` record `i` (verbatim); `""` out of range. |
| `lcov_brda_branch(d, f, i)` | `Str` | Branch field of `BRDA` record `i` (verbatim); `""` out of range. |
| `lcov_brda_taken(d, f, i)` | `Int` | Taken count of `BRDA` record `i`; `-1` is the `-` sentinel and the out-of-range sentinel. |

Record accessors are bounds-safe: an out-of-range file index or record index
never reads memory and returns the sentinel documented above.

## Usage

```xi
use xiom.lcov;
use xiom.io;

fn main() -> Int {
  let t = "TN:unit\nSF:src/a.c\nFN:3,main\nFNDA:2,main\nDA:3,2\nDA:4,0\nLF:2\nLH:1\nend_of_record\n";
  let r = lcov_parse(t);
  match r {
    Ok(d) => {
      io.println(lcov_file_count(&d));         // 1
      io.println(lcov_file_source(&d, 0));     // src/a.c
      io.println(lcov_declared_lh(&d, 0));     // 1
      io.println(lcov_computed_lh(&d, 0));     // 1 (one DA record with hits > 0)
      io.println(lcov_emit(&d));               // canonical tracefile, LF-terminated
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

Iterating the records of a section:

```xi
var i = 0;
while i < lcov_da_count(&d, 0) {
  io.println(lcov_da_line(&d, 0, i));   // line number
  io.println(lcov_da_hits(&d, 0, i));   // execution count
  i = i + 1;
}
```

## Declared vs computed values

The LCOV summary records (`FNF`, `FNH`, `LF`, `LH`, `BRF`, `BRH`) are
*declared* totals written by the producing tool. `xiom.lcov` also computes the
same totals from the records it parsed:

- `LF` = number of `DA` records, `LH` = `DA` records with hits `> 0`;
- `FNF` = number of `FN` records, `FNH` = `FNDA` records with hits `> 0`;
- `BRF` = number of `BRDA` records, `BRH` = `BRDA` records with taken `>= 1`
  (the `-` sentinel and an explicit `0` both count as not hit).

A mismatch is never a parse error: `lcov_declared_*` returns what the file
said (`-1` when the record is absent), `lcov_computed_*` derives the truth
from the records, and `lcov_*_mismatch` reports whether the two disagree.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.lcov
```

Expected tail: 21 `[PASS]` lines, `xiom.lcov: all tests passed`, then
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- Codec only: no gcov/llvm-cov invocation, no file I/O, no coverage merging,
  no branch-condition semantics, no HTML or text reports.
- Strict by design: unknown record prefixes, malformed fields, negative
  numbers, numbers above `1000000000` and records outside an `SF` section are
  `Err`, not warnings.
- `FN`/`FNDA` names may not contain commas, and a `DA` checksum may not be
  empty (`DA:1,2,` is an empty-field error).
- No whitespace trimming inside a record: only a trailing CR is dropped and
  blank lines are skipped, so `DA:1,2 ` (trailing space) is an error.
- A `TN` record labels every following `SF` section until the next `TN`; the
  canonical emitter writes the label once per section, so output is canonical
  rather than byte-identical to the input.
- Record order inside a section is canonical on emit (see `SPEC.md` section
  7); duplicate declared records are last-wins.
- Declared-vs-computed mismatches are tolerated and exposed, never repaired.
- In-memory only: no streaming, no incremental parsing, no FFI.

See `SPEC.md` for the exact grammar, policies, error catalog and test matrix.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
