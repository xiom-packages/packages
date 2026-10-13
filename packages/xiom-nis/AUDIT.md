# AUDIT: xiom.nis

## Status (2026-10-13, v0.64.4)

New package at 0.1.0: vendored NIS v1.0.3 (MIT) with the complete CPU-visible
config surface bound over XIOM-owned buffers, and a typed SKIP for the
GPU pixel path. No pre-pilot module exists in git history for this package.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.4 |
| Upstream | NIS v1.0.3, commit `35e13ba3` (latest release); MIT (`vendor/LICENSE.txt`) |
| Link model | `--c-source src/nis_bridge.cpp --cxx-standard 17` (vendored header-only SDK; no upstream binary) |
| FFI confinement | all `unsafe`/`extern "C"` in `nis.xi` (single module, G5); bridge is ours |
| Surface | 11/11 `NIS_Config.h` declarations bound (0 skips); GPU pixel path = typed SKIP |
| Suite | `tests/test_conformance.xi` |
| Runs | see `STATUS.json` (x2 record) |

## Design notes

- **No CPU pixel path exists at v1.0.3.** Grep of the pinned `NIS/` tree
  shows the scaler/sharpener are shader entry points only
  (`void NVScaler(NVU2, NVU)`, `void NVSharpen(NVU2, NVU)` in
  `NIS_Scaler.h`); the CPU-visible API is the config/optimizer/coefficient
  layer. The suite therefore exercises the real vendored builders on the CPU
  and reports pixel execution as a typed SKIP, with source-level checks of
  the shader API surface.
- **Bridge buffers:** `NVScalerUpdateConfig`/`NVSharpenUpdateConfig` run
  against a stack-local `NISConfig` in the bridge and the result is
  `memcpy`-ed into the caller's `Vec[UInt8]`; the caller's buffer needs no
  256-byte alignment and no pointer ever crosses back into XIOM
  (B-20/B-24/B-25 discipline). Rejection semantics mirror upstream exactly
  (false on zero viewport, scale outside [0.5, 1.0], invalid HDR mode) and
  the suite asserts the partially written fields too.
- **Interface facts encoded by the bridge** (from the vendored header, not
  copied code): the `NISConfig` field count (28) and order for the scalar
  accessors -- all fields are 4-byte scalars with no inter-field padding, so
  field index maps to byte offset `4*i` (the suite cross-checks an accessor
  against a byte-offset read at `kScaleX`, offset 48); the HDR mode value set
  (0/1/2); the four coefficient tables. The 256-byte `sizeof(NISConfig)`
  comes from the `NIS_ALIGNED(256)` attribute and matches what the upstream
  samples upload as the constant-buffer size.
- **Float handling:** `sharpness` crosses as IEEE-754 `Float32` (the repo's
  proven fn-pointer float shape, see glfw/raylib/spirv-cross bindings);
  dimensions cross as validated `Int32`; no fp returns from the bridge.
- **Naming:** bridge locals are prefixed (`f_` rule, finding B-10 -- the
  bridge allocates nothing and calls no libc allocator, so B-05 does not
  apply).

## Coverage ledger (declared surface)

| Upstream item | Bound | Tested |
|---------------|-------|--------|
| `NISConfig` (28 fields) | yes | sizes, values for every field family, byte-offset parity |
| `NISHDRMode` (3) | yes | SDR/Linear/PQ constant sets + invalid-mode rejection in bridge |
| `NISGPUArchitecture` (4) | yes | optimizer matrix (4 archs x upscale/sharpen) |
| `NISOptimizer` + 3 getters | yes | 3 checks (width/height/thread-group) |
| `NVScalerUpdateConfig` | yes | 12 checks (accepts, rejects, clamps, constant sets) |
| `NVSharpenUpdateConfig` | yes | 1 check (scale 1.0, viewport/origin propagation) |
| `coef_scale`/`coef_usm` f32 | yes | 2 checks (size, rows, center-phase symmetry) |
| `coef_scale_fp16`/`coef_usm_fp16` | yes | 1 check (size, half-bit row) |
| `NVScaler`/`NVSharpen` shader entries | typed SKIP | source-level surface checks |
