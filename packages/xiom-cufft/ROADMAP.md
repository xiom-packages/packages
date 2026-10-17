# ROADMAP: xiom.cufft

## 0.1.0 (landed)

- Loader-only runtime binding (`cufft64_12/11/10.dll`), typed SKIP/FAIL
  classification, CUDA context + device-memory helpers.
- 1D/2D plan creation/destroy, `setStream`, `getVersion`, workspace
  estimates.
- Execution: R2C, C2R, C2C (via `cufftExecZ2Z` only for double; single C2C
  is not bound in 0.1.0), Z2Z, D2Z, Z2D.
- 45-check live suite (x2) + deterministic SKIP path.

## 0.2.0 (proposed)

- `cufftPlan3d` and `cufftPlanMany` (batched/strided 1D/2D/3D).
- Single-precision C2C execution (`cufftExecC2C`) and in-place transforms.
- Plan properties (`cufftSetPlanProperty`), compatibility modes.
- Work-area explicit `cufftSetWorkArea` for caller-owned scratch.

## 0.3.0 (proposed)

- `cufftXt` callback/store APIs (extended precision and custom kernels).
- Batched plans over an XIOM-owned tensor type.
- Linux loader (`libcufft.so.11` + `libcuda.so.1`) and platform matrix
  reporting.
