# xiom.numpy

> **Status:** `incubating` -- Phase-3 COMPLETE + Phase-3d acceleration dispatch (150/150 x2 on v0.64.6: broadcasting + N-D, reductions, Gauss-Jordan inv, self-contained Jacobi SVD, typed OpenBLAS dispatch); published in `eco-v0.1.196` (sha256 `0eaa9185...`, 2026-10-17).
> **Scope:** NumPy-compatible array computing API.
> **Deps:** stdlib; `xiom.openblas` (path dep) for real-leg BLAS/LAPACK; may wrap C (FFI).

## Acceleration note (Phase-3d)

`array_matmul` (and the 2-D `array_dot` path) dispatch through one typed
decision, `acceleration_leg() -> AccelLeg`:

| Leg | Marker | Matmul implementation | Needs OpenBLAS? |
|-----|--------|-----------------------|-----------------|
| Real | `AccelLeg.OpenBlasReal` (`xiom.openblas.backend_is_real() == true`) | marshals into the openblas pool; `xiom.openblas.gemm` -> `cblas_dgemm` | Yes (linked import library) |
| Offline/stub | `AccelLeg.SelfContained` (stub bridge marker 0) | numpy's own row-major triple loop over the flat f64 arena | No |

The decision is fail-closed: only the explicit real marker selects the BLAS
path; any other build runs the self-contained fallback. Both legs share the
same shape/rank validation and typed `Err` surface, so routing is transparent
and the public `NDArray` API is unchanged. The offline conformance suite runs
on the stub leg and pins `AccelLeg.SelfContained` plus a fractional matmul
golden, so it stays offline-deterministic and FFI-free.

`tests/probe_numpy_real_leg.xi` is an **optional, clearly marked** real-leg
probe (not run by `scripts/port.ps1`); `tests/run_real_leg.ps1` discovers a
system/pinned OpenBLAS and runs it. Verified 6/6 checks x2 against OpenBLAS
v0.3.34 (2026-10-17): the typed marker is `OpenBlasReal` and the 2x2,
2x3*3x2, fractional matmul, `dot`, and `inv` checks match the offline goldens.
The runner sets `XIOM_NO_DEP_PORT_ARGS=1`; otherwise the path dependency's
`port.args.json` auto-applies the stub bridge and lld reports a duplicate
`xiom_openblas_backend` symbol. `array_inv` stays on its self-contained
Gauss-Jordan path this pass (the openblas LAPACK surface exposes `solve`, not
`inv`), and remains the documented acceleration target.

## Libs inventory

| Lib | Description |
|-----|-------------|
| `array` | ND-array data structure. |
| `random` | Random sampling and generators. |
| `linalg` | Linear algebra routines. |
| `fft` | Fast Fourier transforms. |
| `io` | Array file I/O. |
