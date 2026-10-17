# ROADMAP: xiom.cusparse

## 0.1.0 (landed)

- Loader-only runtime binding (`cusparse64_13/12/11/10.dll`), typed
  SKIP/FAIL classification, CUDA context + device-memory helpers
  (Float32/Float64/Int32).
- Handle lifecycle, `setStream`, `getVersion`.
- Legacy mat descriptor create/destroy/type/index-base.
- Generic CSR + DnVec + DnMat descriptors (create/destroy).
- SpMV (f32/f64) and SpMM (f64) with buffer-size query + external buffer.
- 54-check live suite (x2) + deterministic SKIP path.

## 0.2.0 (proposed)

- Formats: COO, CSC, BSR (create/destroy + SpMV/SpMM).
- `cusparseSpGEMM` (sparse x sparse) with its workspace phases.
- Transposed/conjugate-transposed SpMV (`opA != NON_TRANSPOSE`).
- Device pointer mode (`cusparseSetPointerMode`) and device scalars.
- Preprocess APIs (`cusparseSpMV_preprocess`, `cusparseSpMM_preprocess`).

## 0.3.0 (proposed)

- Triangular solves (`SpSV`, `SpSM`) and ILU/IC preconditioners.
- Batched/multiple-vector SpMM variants and 64-bit index coverage in the
  suite.
- Linux loader (`libcusparse.so.12` + `libcuda.so.1`) and platform matrix
  reporting.
