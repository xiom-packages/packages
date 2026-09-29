# xiom.coverage

> **Status:** `incubating` -- conformance-tested (22/22); published at `v0.1.0` on the XIOM registry.

Pure-XIOM (no FFI, no I/O) codec for the **text form** of gcov coverage data
(`.gcov` files) plus per-file and overall coverage summary math.

- Parse `.gcov` text into a flat `GcovDoc` with exact error reporting
  (message, 1-based line, 0-based byte offset).
- Read every record back through bounds-clamped accessors: metadata, line
  counts, branches, function summaries, calls and unconditional branches.
- Compute coverage: executable / covered / unexecuted lines, taken branches,
  called functions, integer percents and integer basis points, per file and
  pooled across all files.
- Emit a canonical `.gcov` stream that re-parses to an equivalent document
  (round-trip stable, idempotent).

Not in scope: **no `.gcda` / `.gcno` binary parsing**, no `gcov` invocation,
no coverage merging, no filtering, no HTML/text report rendering. This module
reads and writes the text form only; the numbers in the text are data, taken
as parsed. See `SPEC.md` for the exact grammar, the error catalog and the
summary rules.

## Library inventory

| Item | Description |
|------|-------------|
| `gcov_parse` | `.gcov` text -> `Result[GcovDoc, Str]` |
| `gcov_emit` | `GcovDoc` -> canonical `.gcov` text |
| `gcov_file_*` | Source/Graph/Data/Runs/Programs metadata accessors |
| `gcov_file_line_*`, `gcov_line_*` | line records and per-line flags |
| `gcov_file_branch_*`, `gcov_branch_*` | branch records and taken math |
| `gcov_file_function_*`, `gcov_function_*` | function summaries and called math |
| `gcov_file_call_*`, `gcov_call_*` | call records |
| `gcov_file_unconditional_*`, `gcov_unconditional_*` | unconditional branches |
| `gcov_file_event_*`, `gcov_event_*` | per-file record order (for emit) |
| `gcov_total_*` | pooled totals and coverage percents across all files |

## Usage

```xiom
use xiom.coverage;

let r = gcov_parse(text);
match r {
  Ok(d) => {
    let exec = gcov_file_executable_lines(&d, 0);
    let covered = gcov_file_covered_lines(&d, 0);
    let pct = gcov_total_line_percent(&d);        // floor, 0 when none
    let bp = gcov_total_line_basis_points(&d);    // hundredths of a percent
  },
  Err(e) => { /* "coverage: <reason> at line L byte O" */ },
}
```

A `GcovDoc` is flat by design: XIOM v0.61.3 cannot hold `Vec[StructType]`, so
records live in index-aligned parallel `Vec` fields grouped per Source
section. Accessors clamp every range, so out-of-range indices return
documented sentinels instead of reading out of bounds.

## Coverage math

- **Executable lines**: digits records (including `0`) and `#####`. `=====`
  and `-` records are not executable.
- **Covered lines**: count `>= 1`. Both `0` and `#####` are uncovered.
- **Unexecuted**: `max(0, executable - covered)`.
- **Branches**: every branch record counts; taken means taken count `>= 1`
  (`taken 0`, `taken never` and `never executed` are not taken).
- **Functions**: every function summary counts; called means call count
  `>= 1`.
- **Percents**: floor of `covered * 100 / total`; **0** when `total == 0`.
  Basis points are floor of `covered * 10000 / total`, likewise 0 when empty.
  Totals are pooled across files (exact), never an average of per-file
  percents.

## Tests

```powershell
.\scripts\port.ps1 -Package xiom.coverage
```

22 conformance checks, all with synthetic `.gcov` text built in-test.

## License

MIT OR Apache-2.0. Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
