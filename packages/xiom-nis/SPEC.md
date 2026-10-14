# SPEC: xiom.nis -- NVIDIA Image Scaling (NIS) SDK bindings

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.nis` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | NVIDIA Image Scaling SDK -- https://github.com/NVIDIAGameWorks/NVIDIAImageScaling |
| Upstream version pinned | **v1.0.3** (commit `35e13ba316c98eeecf16f37eae70ce88019911f6`, 2022-08-22; latest release) |
| Upstream license | **MIT** (`licence.txt`; vendored as `vendor/LICENSE.txt`) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (no platform-specific XIOM code; the GPU path is renderer-owned) |
| Compiler pin | v0.64.4 |
| Modules | `xiom.nis` (declared in `package.xi`) |

## 2. Vendored path (G2 pin)

The four NIS SDK files are vendored byte-exact from the pinned commit and
compiled into the test binary through `src/nis_bridge.cpp` (C++17,
`--cxx-standard 17`). The store pins LF-normalized upstream blobs
(`git cat-file blob` of the pinned commit; the clone's working tree is
CRLF via `core.autocrlf=true`, and `.gitattributes` keeps `vendor/** -text`).

| File | Bytes | SHA256 |
|------|-------|--------|
| `vendor/NIS/NIS_Config.h` | 27,335 | `F33C5DD82BB63F3C1CC7CEFD86690053DE0BD3FE0E730463A5E63E90E7778754` |
| `vendor/NIS/NIS_Scaler.h` | 37,643 | `2D3BD5B45D6A0C4169FE36DFE349E7FF5A099DFF6FB6876F8A3286489F74D3BF` |
| `vendor/NIS/NIS_Main.hlsl` | 3,333 | `46402103801007B402AEEB8481D60B1BDA37799BF68B543B32DAEA65F255F301` |
| `vendor/NIS/NIS_Main.glsl` | 3,168 | `4FCD5D351ADA2974110718E6B6ADF294CDAF30356DA4035761F3B8AF56FBA69A` |
| `vendor/LICENSE.txt` (MIT) | 1,178 | `62207F1C0FAE72800EA7D28EE108E7DBEB852DDE20B00C70FC7B0D235E19E46D` |

Reference clone: `E:\repos\NVIDIAImageScaling` (shallow, tag `v1.0.3`;
registered in `E:\repos\CLEANUP.md`, review-after 2026-12-01).

### Re-pin procedure

1. Re-clone/refresh `E:\repos\NVIDIAImageScaling` at the new tag; update the
   pin + the `CLEANUP.md` review date.
2. Re-extract the five files as LF blobs (`git cat-file blob HEAD:<path>`),
   recompute the table above.
3. Re-verify the `NISConfig` field order/sizes, the optimizer geometry table
   and the coefficient tables against the new headers; re-run the suite
   (config checks carry the expected values, so drift fails loudly).
4. `scripts/port.ps1 -Package xiom.nis` (x2); record; conventional commit.

## 3. Design and safe boundary (G5)

| Module | File | Role |
|--------|------|------|
| `xiom.nis` | `nis.xi` | The only module with `extern "C"`: typed wrappers over the bridge + all declared constants/types |
| bridge | `src/nis_bridge.cpp` | Our code (MIT OR Apache-2.0); the only TU including the SDK header; builds configs in a local `NISConfig` and `memcpy`s them into XIOM-owned buffers |

- The bridge holds no state, performs no allocation, and never retains a
  caller pointer; floats cross as IEEE-754 `Float32`, dimensions as `UInt32`
  (marshaled as `Int32`, validated non-negative by callers), HDR modes as
  validated `Int`.
- Configs are XIOM-owned `Vec[UInt8]` buffers (`nis_config_new()` returns
  exactly `nis_config_size()` bytes). The bridge builds the config in C stack
  space and copies it out, so the caller's buffer needs no 256-byte alignment
  and XIOM never reads or writes foreign memory (v0.64.4 findings
  B-20/B-24) and does no pointer arithmetic (B-25).
- Field read-back is bridged (`nis_config_field_f32` / `_u32`,
  `nis_buf_f32`) -- byte-indexed scalar reads from the caller's own buffer,
  no foreign-pointer dereference; flat types only, no
  `Result[Option[T]]` (B-26); no bare `null` to C (B-23).
- All `unsafe`/`extern "C"` live in `nis.xi` (single module, G5).

## 4. Declared API surface (100% of the CPU-visible SDK, 0 skips)

Every declaration of `NIS_Config.h` (the SDK's CPU-visible surface) is bound:

| # | Upstream declaration | Bound as |
|---|----------------------|----------|
| 1 | `struct NISConfig` (28 fields, 4-byte scalars, 256-byte struct) | `nis_config_new` / `nis_config_size` / `nis_config_used_size` / `NIS_FIELD_*` + `nis_config_field_f32` / `nis_config_field_u32` |
| 2 | `enum class NISHDRMode` | `NIS_HDR_MODE_NONE/LINEAR/PQ` |
| 3 | `enum class NISGPUArchitecture` | `NIS_GPU_ARCH_*` (4 values) |
| 4 | `struct NISOptimizer` (ctor) | constructed inside the bridge getters |
| 5 | `NISOptimizer::GetOptimalBlockWidth` | `nis_optimal_block_width` |
| 6 | `NISOptimizer::GetOptimalBlockHeight` | `nis_optimal_block_height` |
| 7 | `NISOptimizer::GetOptimalThreadGroupSize` | `nis_optimal_thread_group_size` |
| 8 | `NVScalerUpdateConfig` | `nis_scaler_update_config` |
| 9 | `NVSharpenUpdateConfig` | `nis_sharpen_update_config` |
| 10 | `kPhaseCount` = 64, `kFilterSize` = 8 | `NIS_PHASE_COUNT` / `NIS_FILTER_SIZE` |
| 11 | `coef_scale` / `coef_usm` (f32), `coef_scale_fp16` / `coef_usm_fp16` | `nis_copy_coefficients` (+ `NIS_COEF_TABLE_BYTES_*`) |

11/11 declarations bound, 0 silent gaps. The upstream surface outside the
`NIS/` SDK directory (samples, third-party sample dependencies) is
explicitly out of scope, not a gap (`ROADMAP.md`).

## 5. GPU pixel path: typed SKIP

NIS v1.0.3 performs pixel processing **only** in the `NVScaler` /
`NVSharpen` compute shaders (`NIS_Scaler.h`, dispatched by `NIS_Main.hlsl` /
`NIS_Main.glsl`); the SDK contains no CPU/scalar pixel implementation
(verified at the pin: no CPU code path in `NIS/`). The package models this as
a typed outcome, not a gap:

- `nis_gpu_path()` returns `NisGpuPath{ kind = NIS_GPU_PATH_SHADER_ONLY,
  cpu_pixel_path = false, entry_points = "NVScaler,NVSharpen", reason = ... }`.
- The suite reports GPU execution as SKIP (the shaders run in the consumer's
  rendering pipeline, not on the CPU); it checks the shader **API surface** at
  source level instead: the vendored `NIS_Scaler.h` declares
  `void NVScaler(NVU2 blockIdx, NVU threadIdx)` and
  `void NVSharpen(NVU2 blockIdx, NVU threadIdx)`, and the dispatch files
  include it.
- The GPU-side inputs are fully covered by the CPU surface: the config
  buffer (`NISConfig`), the dispatch geometry (`NISOptimizer`) and the
  coefficient tables are exactly what a renderer uploads.

## 6. Test matrix

| Configuration | Command | Result |
|---------------|---------|--------|
| Vendored config surface (0.1.0) | `scripts/port.ps1 -Package xiom.nis` | see `STATUS.json` + `AUDIT.md` for the x2 record |

28 `[PASS]` checks (26 CPU/config checks + 2 typed-GPU-SKIP reports; the
descriptor check asserts the SKIP model itself): ABI sizes/filter geometry;
scaler config value checks (scales, norms, viewport fallbacks, SDR/HDR
constant sets, sharpness clamping, byte-level read parity); rejection paths
(scale < 0.5, downscale, zero texture); sharpen config checks; the optimizer
matrix; coefficient tables (sizes, row content, center-phase symmetry, fp16
half bits); GPU typed SKIP + shader-source surface checks.

No SKIP path exists for the CPU surface (the SDK is compiled in); the only
SKIP is the GPU pixel-execution model (typed, section 5).

## 7. Scope

Delivered (0.1.0): the complete CPU-visible NIS v1.0.3 surface -- config
builders for both algorithms, dispatch geometry, coefficient tables -- with
owned-buffer interop, plus the typed GPU-path descriptor.

Out of scope (explicit non-goals): sample/DX11/DX12/VK integration code,
shader compilation (the HLSL/GLSL sources are vendored for the consumer),
`NIS_NV12_SUPPORT`/viewport extension research beyond the pinned header
defines, and a CPU reference pixel path (does not exist upstream at v1.0.3).
Phase 2 candidates: `ROADMAP.md`.
