<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# `Str` equality on `Vec[Str]` elements -- re-verification (v0.62.2)

Original trap (COMPILER-FINDINGS, 2026-09-25): `==`/`!=` on `Str` values
read from `Vec[Str]` elements compared pointers, and `str_len`/`.len()`
were unreliable; the repo routes such checks through
`xiom.string.compare.str_compare` (e.g. `training` tests define
`streq(a, b) = compare.str_compare(a, b) == 0`).

## Result (2026-10-03, installed v0.62.2)

`probe_str_vec_eq.xi` -- **`bad=0`, exit 0**:

| Check | Result |
|---|---|
| `v[0] == v[1]` (same literals pushed) | true |
| `v[0] == "alpha"` (element vs literal) | true |
| `joined = v[2] + v[3]`; `joined == "alpha"` (runtime-built fresh pointer) | true |
| `str_compare(joined, "alpha") == 0` | true |
| `string.str_len(v[0])` | 5 |

**The pointer-compare trap is NOT reproducible on v0.62.2** in any of
these shapes. Keep the existing `str_compare` sites (green, no drive-by
refactors); treat full retirement as a Tier-2 candidate after the next
release sweep, when the original 9/25 shape can be re-derived against a
fixed compiler.

Run:

```powershell
& .\scripts\xiom.ps1 -Stdlib "E:\xiom-lang\stdlib" --run docs\repro\str-vec-eq\probe_str_vec_eq.xi
# bad=0
```
