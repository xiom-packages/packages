<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Module-level const tables -- complex-shape probe (v0.62.2)

Follow-up to COMPILER-FINDINGS row 25 / MAINTENANCE "runtime table
builders". Simple `[N]Int` module-level const arrays were verified
CORRECT on v0.62.2 (2026-10-02); **complex initializers were untested**
until this probe.

## Result (2026-10-03, installed v0.62.2) -- COMPLEX SHAPES BROKEN

`probe_const_tables.xi` -- deterministic `bad=5`, 3/3 runs:

| Shape | Observed | Expected |
|---|---|---|
| `const K: [4]Int = [3,1,4,1]`, runtime-indexed loop read | `sum=9` (correct) | 9 |
| `const NAMES: [3]Str = ["alpha","beta","gamma"]`, `str_len` sum | **30** | 14 |
| `NAMES[1]` via `str_compare` | **wrong** | "beta" |
| `const ROWS: [3]Row`, `ROWS[i].code` sum | **0** | 6 |
| `const ROWS`, `ROWS[i].name` `str_len` sum | **0** | 11 |
| `ROWS[2].name` via `str_compare` | **wrong** | "three" |

Runtime controls (same file, all correct): a runtime struct literal
`Row{ code: 9, name: "nine" }` reads `code=9`; a runtime `Vec[Str]` with
the same content sums `str_len` to 14. So the defect is specific to
module-level `const` tables with `Str`/struct payloads.

**Guidance:** keep runtime table builders for `Str`/struct tables
(`merkle`, `l10n-currency`, `l10n-unicode`); `[N]Int` const tables are
usable. Row 25 is not retirable for complex shapes.

Run:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\const-tables\probe_const_tables.xi
# bad=5 (expect 0 after the fix)
```
