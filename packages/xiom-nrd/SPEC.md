# SPEC: xiom.nrd -- NVIDIA Real-time Denoisers (NRD) integration surface

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.nrd` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | NVIDIA Real-time Denoisers (NRD) -- https://github.com/NVIDIA-RTX/NRD |
| Upstream version | pinned tag **v4.17.3** (commit `792eff19`); v4.18.0 is a GitHub pre-release and is not pinned |
| Upstream license | **NOT MIT** -- proprietary "NVIDIA RTX SDKs LICENSE" (see PROVENANCE.md) |
| Package license | MIT OR Apache-2.0 (no upstream code in this package) |
| Platform | Windows x64 (NRD.dll via the module loader) |
| Compiler pin | v0.64.4 |
| Reference clone | `E:\repos\nrd` @ `792eff196afdd350fd9c3f862119017ccb438a0e` -- declaration oracle, `PROVENANCE.md` |
| Runtime module | `NRD.dll` built locally from the clone by the licensee (`XIOM_NRD_DLL` or default module search; SKIP when absent) |

## 2. Decision: reference-only, dynamic loader only (never vendored)

The coordinator task expected MIT and required verification. Verification
(2026-10-13, v4.17.3 + master) found the **NVIDIA RTX SDKs License**, which
forbids source redistribution (4(b)), forbids applying an open-source
license to the SDK (4(e)) and permits distribution only as object code
incorporated into an application. Vendoring the C++ library into this
MIT/Apache-2.0 repository is therefore not permitted, and the bridge is
**not** built by linking an NRD import library.

This package follows the FFmpeg precedent (`BINDINGS-LANE.md` sec. 4/11):
independent XIOM code written against the public header declarations, a
runtime dynamic loader, and a classified SKIP path when the runtime module
is absent. Present-path proof uses a locally built `NRD.dll` (the licensee's
"install and use" grant); nothing from NRD ships in this repository -- no
source, no headers, no shader blobs, no binaries.

Consequences (explicit non-goals for 0.1.0):

- No GPU execution: creating pipelines from NRD shader blobs and binding
  resources requires the application's D3D12/VK device; `nrd_execute`
  returns the typed `NRD_EXEC_NO_DEVICE` classification (SKIP) and never a
  silent success. The dispatch plan's CPU side is fully computed and
  validated (`nrd_plan_validate`).
- No NRD.h in the build: the ABI mirror structs live in
  `src/nrd_bridge.cpp` (ours, written from the declaration oracle); layer
  drift is caught by the pin assertions in the suite (version, binding
  offsets, name tables, plan behaviour) and the re-carve procedure.

## 3. Declared surface (100% of the public C integration API, v4.17.3)

All nine `NRD.h` entry points (`NRD_API extern "C"`) are bound through the
loader and exercised by the suite:

| Entry point | Signature (declaration oracle) | Suite coverage |
|-------------|--------------------------------|----------------|
| `CreateInstance` | `Result(const InstanceCreationDesc&, Instance*&)` | create with 2 denoisers; typed `UNSUPPORTED`, `NON_UNIQUE_IDENTIFIER` |
| `DestroyInstance` | `void(Instance&)` | destroy after plan checks |
| `GetLibraryDesc` | `const LibraryDesc*()` | version 4.17.3, encodings 2/1, 19 denoisers, SPIR-V offsets 0/20/2/3 |
| `GetInstanceDesc` | `const InstanceDesc*(const Instance&)` | pipelines=59, cbMax=864, samplers=2, pools=25/15, entry "main" (4-denoiser instance) |
| `SetCommonSettings` | `Result(Instance&, const CommonSettings&)` | 320x180 valid frame; typed `INVALID_ARGUMENT` on zero sizes |
| `SetDenoiserSettings` | `Result(Instance&, Identifier, const void*)` | REBLUR + SIGMA + REFERENCE + RELAX settings images; typed `INVALID_ARGUMENT` on unknown id |
| `GetComputeDispatches` | `Result(Instance&, const Identifier*, uint32_t, const DispatchDesc*&, uint32_t&)` | 70 dispatches / 277 resources / 16456 constant bytes at 320x180 (4 denoisers); per-denoiser resource evidence; CB reuse; frameIndex flow |
| `GetResourceTypeString` | `const char*(ResourceType)` | all 32 resource type strings non-empty; spot checks |
| `GetDenoiserString` | `const char*(Denoiser)` | 19 denoiser strings; spot checks |

Constants mirrored from the headers (all reachable as `pub const`):

| Enum | Values | Count |
|------|--------|-------|
| `Result` | SUCCESS..NON_UNIQUE_IDENTIFIER | 5 |
| `ResourceType` | IN_MV..PERMANENT_POOL | 32 |
| `Denoiser` | REBLUR..REFERENCE | 19 |
| `Format` | R8_UNORM..R9_G9_B9_E5_UFLOAT | 43 |
| `DescriptorType` | TEXTURE, STORAGE_TEXTURE | 2 |
| `Sampler` | NEAREST_CLAMP, LINEAR_CLAMP | 2 |
| `NormalEncoding` | RGBA8..RGBA16_SNORM | 5 |
| `RoughnessEncoding` | SQ_LINEAR..SQRT_LINEAR | 3 |
| `CheckerboardMode` / `AccumulationMode` / `HitDistanceReconstructionMode` | 3 each | 9 |
| Total | | **120** |

Description structs mirrored in the bridge (ABI facts from the oracle):
`AllocationCallbacks`, `SPIRVBindingOffsets`, `LibraryDesc`, `DenoiserDesc`,
`InstanceCreationDesc`, `TextureDesc`, `ResourceDesc`, `ResourceRangeDesc`,
`ComputeShaderDesc`/`PipelineDesc` (read-only fields used for counts),
`DescriptorPoolDesc`, `InstanceDesc`, `DispatchDesc` -- 12 structs.

## 4. Settings images (owned structs) and layout tables

Settings cross as XIOM-owned byte images (`Vec[UInt8]`, mirror size + 64
bytes slack). Field offsets/sizes are fetched at run time from the bridge's
`offsetof`/`sizeof` tables (`nrdb_layout`) -- one single source of ABI truth
-- and the suite asserts header-derived anchors against them.

| Kind | Mirror | Size (x64) | Fields | Field index order (SPEC) |
|------|--------|-----------|--------|--------------------------|
| 0 Common | `CommonSettings` | 432 | 31 | matrices (0-4), mv scale, jitter (+prev), resource/rect sizes (+prev), viewZScale, timeDelta, denoisingRange, disocclusion (+alternate), material IDs, strand thickness, splitScreen, printfAt, debug, rectOrigin, frameIndex, accumulationMode, 4 bools |
| 1 REBLUR | `ReblurSettings` | 128 | 28 | hitDistance/antilag/responsive/convergence sub-structs, accumulation/stride ints, blur/weights floats, material IDs, enums, 3 bools |
| 2 RELAX | `RelaxSettings` | 148 | 36 | antilag sub-struct, accumulation/stride ints, A-trous floats, confidence/edge-stopping floats, enums, 2 bools |
| 3 SIGMA | `SigmaSettings` | 20 | 3 | lightDirection, planeDistanceSensitivity, maxStabilizedFrameNum |
| 4 REFERENCE | `ReferenceSettings` | 4 | 1 | maxAccumulatedFrameNum |

Default images (`nrd_image_default`) are produced by the bridge from mirror
structs carrying the header's documented default member initializers
(e.g. `viewZScale=1`, `denoisingRange=500000`, `disocclusionThreshold=0.01`,
`motionVectorScale=(1,1,0)`, `printfAt=(9999,9999)`,
`worldPrevToWorld=identity`). The suite verifies defaults survive the
roundtrip and that raw little-endian bytes land at the oracle offsets.

## 5. Dispatch plan model (owned slots)

`nrd_dispatch_plan` performs a counts pass and a copy pass
(`nrdb_plan_counts` / `nrdb_plan_copy`; the runtime's memory is overwritten
by its next call, so the bridge copies immediately into owned slots).

Summary record, 96 bytes (`NRD_PLAN_SUMMARY_SIZE`):

| Offset | Field |
|--------|-------|
| 0 | identifier (u32) |
| 4 | pipelineIndex (u16 widened) |
| 8 | gridWidth (u16 widened) |
| 12 | gridHeight (u16 widened) |
| 16 | resourcesNum (u32) |
| 20 | constantBufferDataSize (u32) |
| 24 | cbOffset into the constants blob |
| 28 | resOffset into the resource records |
| 32 | flags (bit0 = constantBufferDataMatchesPreviousDispatch) |
| 36 | nameLen |
| 40..96 | dispatch name bytes (NUL-free copy, max 55) |

Resource record, 16 bytes: descriptorType (u32), type (u32),
indexInPool (u32), reserved.

`NrdPlan.validate()` is the CPU-side pre-execute precheck (grids > 0,
resource counts/offsets in bounds, descriptor/type values in range); the
device-side execute is typed SKIP (sec. 2).

## 6. Loader model and classification

`nrd_load()` => `XIOM_NRD_DLL` env var first, then the default module
search (`NRD.dll` in cwd/PATH). Resolves all nine plain export names on
`LoadLibraryA`; a module missing entry points classifies `NRD_LOAD_ABI`
(FAIL), a missing module `NRD_LOAD_ABSENT` (SKIP, green).

## 7. Local runtime sample + run procedure

| Artifact | Value |
|----------|-------|
| `E:\repos\nrd\_Bin\Release\NRD.dll` | 182,784 bytes, SHA256 `AFD8B2B46B999BCDD8A03AB4009348A4E0468CDB234A33B3920723D7539E84AD` |
| Build | CMake 4.3.3 + MSVC 14.51, `-DNRD_EMBEDS_DXBC/DXIL/SPIRV_SHADERS=OFF -DNRD_NRI=OFF`; no shader blobs compiled (PROVENANCE.md) |
| Present-path x2 | `$env:XIOM_NRD_DLL='E:\repos\nrd\_Bin\Release\NRD.dll'; .\scripts\port.ps1 -Package xiom.nrd -TimeoutSec 300` -> 29/29 |
| Default-path x2 | `.\scripts\port.ps1 -Package xiom.nrd -TimeoutSec 300` -> 29/29 (SKIP-labelled section B) |

## 8. Re-pin procedure

See `PROVENANCE.md` ("Re-carve procedure"): refresh the clone, re-read the
oracle, diff enums/layouts/defaults/exports/name tables, rebuild the sample,
re-run SKIP x2 + present x2, record, sync counts here.

## 9. Non-goals (0.1.0)

- GPU execution/device bridge, pipeline creation from shader blobs, resource
  binding (`NRD_EXEC_NO_DEVICE` typed SKIP).
- The NRI-based `NRDIntegration` convenience layer (requires the NRI SDK;
  out of scope).
- Distribution of any NRD artifact (license, sec. 2).
