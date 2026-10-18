<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->


Status: **FIXED in v0.64.1** (2026-10-08 re-test): all six matrix shapes and the Option shape read correctly; the SearchHits wrapper is now an unwind candidate.
# XVC-C-04 repro: `Result[Vec[non-scalar], E]` / `Option[Vec[non-scalar]]` payload loss

Compiler: **v0.64.0** (Windows and WSL Linux, identical). A `Result` / `Option`
whose payload is **directly** a `Vec[T]` with a non-scalar `T` loses element
field data at the caller: the length survives, struct fields read `0`, and
`Str` elements read address-like integers. No diagnostic.

`probe_matrix.xi` (run it) prints the six-shape matrix:

| Shape | Observed |
|---|---|
| `Result[Int, E]` | `99` correct |
| `Result[SR{Int,Float32}, E]` | `id=42` correct |
| `Result[Vec[Int], E]` | `7, 8` correct |
| `Result[Vec[Str], E]` | `v0=140701543766878` (address-like) **WRONG** |
| `Result[Vec[SR], CE]` (unit-only error enum) | `len=1 id=0` **WRONG** |
| `Result[Vec[SR], SE]` (Str-bearing error enum) | `len=1 id=0` **WRONG** |

`probe_workaround.xi` controls:

| Shape | Observed |
|---|---|
| direct `Vec[Str]` return | `alpha` correct |
| `Result[Hits{items: Vec[SR]}, E]` (Vec wrapped in a struct) | `id=42` correct |
| `Option[Vec[SR]]` | `id=0` **WRONG** (Option is affected too) |

Workaround adopted by xvector `src/engine.xi` and the suite: wrap the Vec in a
struct Ok-payload (`SearchHits { items: Vec[SearchResult] }`); the suite's
`test_search_hits_shape` is the regression guard and would fail against a
raw `Result[Vec[SearchResult], CoreError]`.

Relation to the packages lane: the v0.62.2-fixed `generic-fnptr` family covers
a fn-pointer struct field and scalar `Vec[U]` maps; this is a distinct
`Vec`-of-aggregate container payload shape. Keep both rows.

Reproduce:

```powershell
. .\scripts\dev-env.ps1
foreach ($p in @("probe.xi","probe_matrix.xi","probe_workaround.xi")) {
  & $env:XIOM_COMPILER -o "out\$([IO.Path]::GetFileNameWithoutExtension($p)).exe" "docs\repro\xv-result-vec-struct\$p"
  & "out\$([IO.Path]::GetFileNameWithoutExtension($p)).exe"
}
```
