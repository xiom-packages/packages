# Compiler defect: Vec inside a cross-module Result tuple

**STATUS: FIXED in v0.65.2.** The nested/tuple payload codegen defect no longer
reproduces (`tests/probe_vec_in_tuple_*.xi` -> `len=2`). The package keeps the
n x 1 `Matrix` pivot return for API compatibility; the probes remain as
regression witnesses. A `Vec[Int]` pivot variant is a future-major option.

Observed on XIOM **v0.64.9** (installed toolchain, Windows x86_64) while adding
`lu_factor`.

## Symptom

A public library function whose return type is

```xiom
Result[(Handle, Vec[Int]), Str]   // pub type Handle = Int
```

returns `Ok((h, v))` with `v` populated, but a caller in another module sees
`v.len() == 0`. The `Handle` element survives; the `Vec[Int]` contents do not.
The equivalent function returning `Result[(Int, Vec[Int]), Str]` in the same
module works, and same-module nominal types work. The failure needs the
nominal type and the `Vec` to cross the module boundary inside one tuple.

## Minimal probe

- `tests/probe_vec_in_tuple_lib.xi` (library module, nominal `Handle`)
- `tests/probe_vec_in_tuple_main.xi` (caller)

```powershell
cd packages\xiom-openblas\tests
xiom --run probe_vec_in_tuple_main.xi
```

Observed:

```
cross-module nominal len=0
```

Expected: `len=2`.

## Workaround in this package

`lu_factor` returns `(Matrix, Matrix)` instead: the second matrix is `n x 1`
and holds the 1-based pivot row indices as exact Float64 integers. Tuple
returns of two `Matrix` values already work (`svd`, `eigen_sym`). The test
suite covers the pivot values through `matrix_get(&piv, k, 0) as Int`.
