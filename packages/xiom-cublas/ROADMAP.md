# ROADMAP: xiom.cublas

## 0.1.0 (landed)

- Loader-only runtime binding (`cublas64_13/12/11/10.dll`), typed SKIP/FAIL
  classification, CUDA context + device-memory helpers.
- Handle lifecycle, `setStream`, `getVersion`.
- BLAS 1: `s/d` axpy, dot, scal, nrm2.
- BLAS 2: `s/d` gemv.
- BLAS 3: `s/d` gemm.
- 62-check live suite (x2) + deterministic SKIP path.

## 0.2.0 (proposed)

- BLAS 2/3 breadth: `ger`, `syr/syrk`, `symv`, `trmv/trsm`, `s/d` swap.
- Complex variants (`c/z` axpy, dotu/dotc, scal, nrm2, gemv, gemm).
- 64-bit-index `_v2_64` entry points.
- Batched/strided (`gemmBatched`, `gemmStridedBatched`) for small-matrix
  workloads.
- Stream/event ownership helpers (create/destroy streams, not raw Int).

## 0.3.0 (proposed)

- `cublasLt` surface (matmul descriptors, epilogue, workspace, heuristic
  query) as a separate submodule so the base stays small.
- Linux loader (`libcublas.so.12` + `libcuda.so.1`) and platform matrix
  reporting.
- Zero-copy interop helpers for an XIOM-owned tensor type.
