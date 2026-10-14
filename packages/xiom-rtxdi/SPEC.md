# SPEC: xiom.rtxdi -- NVIDIA RTXDI (ReSTIR DI integration runtime) surface

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.rtxdi` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | NVIDIA RTXDI -- https://github.com/NVIDIAGameWorks/RTXDI |
| Upstream version | pinned tag **v3.1.0** (commit `a6efab96`, 2026-09-03; GitHub "Latest" release) |
| Runtime library | `Libraries/Rtxdi` (https://github.com/NVIDIA-RTX/RTXDI-Library) at the revision RTXDI v3.1.0 selects: **`f12037fa`** (the library carries no version constant of its own) |
| Upstream license | **NOT MIT** -- proprietary "NVIDIA RTX SDKs LICENSE" (see PROVENANCE.md) |
| Package license | MIT OR Apache-2.0 (no upstream code in this package) |
| Platform | Windows x64 (shim module via the loader) |
| Compiler pin | v0.64.4 |
| Reference clones | `E:\repos\RTXDI` @ `a6efab96` and `E:\repos\RTXDI-Library` @ `f12037fa` -- declaration oracle, `PROVENANCE.md` |
| Runtime module | `xiom_rtxdi_shim.dll` built locally from the pinned runtime by the licensee (`XIOM_RTXDI_SHIM` or default module search; SKIP when absent) |

## 2. Decision: reference-only, dynamic loader only (never vendored)

The coordinator task expected MIT and required verification. Verification
(2026-10-14, RTXDI v3.1.0 + RTXDI-Library f12037fa) found the **NVIDIA RTX
SDKs License** (`LICENSE.txt`; every public header carries the SPDX tag
`LicenseRef-NvidiaProprietary`). Clauses 4(b)/4(e) forbid source
redistribution and any open-source-license application; grants cover
install/use, sample-source derivative works and object-code incorporation
into an application only. Vendoring the C++ runtime (or its HLSL shared
headers/shader sources) into this MIT/Apache-2.0 repository is therefore not
permitted, and the bridge is **not** built by linking an RTXDI import
library.

This package follows the NRD/FFmpeg precedent (`BINDINGS-LANE.md` sec. 4/11):
independent XIOM code written against the public header declarations, a
runtime dynamic loader, and a classified SKIP path when the runtime module is
absent. Present-path proof uses a locally built `xiom_rtxdi_shim.dll` (the
licensee's "install and use / modify" grant; PROVENANCE.md); nothing from
RTXDI ships in this repository.

Consequences (explicit non-goals for 0.1.0):

- No GPU execution: running the ReSTIR DI passes (initial sampling, temporal
  and spatial resampling, shading; temporal/spatial PDFs; final visibility)
  requires the application's D3D12/VK device, the reservoir/RIS/light
  buffers and the compiled shaders. `rtxdi_execute_di` returns the typed
  `RTXDI_EXEC_NO_DEVICE` classification (SKIP), never a silent success.
  Shader handling: no prebuilt shader blobs exist for this runtime (the
  headers feed the application's own HLSL compilation pipeline); no HLSL was
  compiled by this package and the fleet's dxc/shaderc tooling was not used.
- ReSTIR GI, ReSTIR PT and the ReGIR presampling shader-side execution:
  their contexts are constructed inside the top-level context (the SDK does
  this itself) but no GI/PT API is bound in 0.1.0.
- Device resource binding (descriptor heaps, GPU buffers): the package
  models the CPU side (parameter images, buffer sizes/indices, segment
  offsets).

## 3. Declared surface (100% of the bound DI integration API)

| Surface | Detail | Suite coverage |
|---------|--------|----------------|
| `CalculateReservoirBufferParameters` | block-linear reservoir layout | B4: 320x180 -> row 5120/array 61440; checkerboard black 2560/30720 |
| `ComputePdfTextureSize` | temporal/spatial PDF texture | B5: 1000 -> 32x32 mips 6; 1 -> 1x1 mips 1 |
| `FillNeighborOffsetBuffer` | deterministic R2 uint8 pairs (radius 250) | B6: byte-exact first 4 offsets, signed decode |
| `JenkinsHash` | 32-bit integer hash | B6: pins 0/1/7; drives temporal `uniformRandomNumber` in B9 |
| `CheckerboardMode` + 4 bias-correction modes + local-light sampling modes + sampling modes + ReGIR modes | enum encodings | A4 |
| `ReSTIRDIStaticParameters` | width/height/checkerboard/neighbor count | B7: static params readback (320x180, neighbor 8192) |
| `ReSTIRDIContext` lifecycle | create/destroy, frame index, resampling mode | B7, B9, B10, B12 (destroy) |
| 7 `GetDefault*` constructors | buffer indices, initial, temporal, boiling, spatial, spatio-temporal, shading | A6, B3 (byte-identical to SDK) |
| `RTXDI_DI*` parameter structs (9) | owned images + field get/set | A2, A5, B2, B7-B11 |
| `RTXDI_Parameters` (272B) | per-frame constant block layout | A3 (offsets 0/16/48/96/128/144/192/240), B11 |
| frame plan (`RTXDI_RuntimeParameters` + `RTXDI_DIBufferIndices` + reservoir params) | dispatch/resource planning per frame | B8/B9/B18: 3-cycle rotation, mask, JenkinsHash URN |
| `RTXDI_LightBufferParameters` (regions + environment) | light-buffer setup | B17: set/get roundtrip through the top-level context |
| `RISBufferSegmentAllocator` | segment allocation | B12: local@0, env@131072, total 262144 |
| `ReGIRContext` | grid + onion calculated parameters, dynamic parameters | B13/B14/B15: grid slots 3072; onion 5 layers/25 rings/2229 cells/1141248 slots; dynamic roundtrip + power-RIS |
| `ImportanceSamplingContext` | context creation, RIS segments, light buffer, child handles | B16/B17/B18: totals 1403392, neighbor 8192, child frame plan |
| `RTXDI_PackedDIReservoir` | 24B reservoir layout anchor | A3 |
| constants | `RTXDI_RESERVOIR_BLOCK_SIZE`, `RTXDI_TILE_SIZE_IN_PIXELS`, onion limits 8/52, `RTXDI_LIGHT_COMPACT_BIT` 0x80000000, `RTXDI_LIGHT_INDEX_MASK`, `RTXDI_INVALID_LIGHT_INDEX`, `RTXDI_NAIVE_SAMPLING_M_THRESHOLD`, `c_NumReSTIRDIReservoirBuffers` 3 | A4, B1 |

Struct sizes mirrored (pinned build, x64): reservoir 16, runtime 16, buffer
indices 32, initial 48, temporal 32, boiling 16, spatial 48,
spatio-temporal 48, shading 32, parameters 272, light buffer 48,
light region 16, environment light 16, packed reservoir 24, RIS segment 16,
DI static 16, ReGIR common 48, grid 16, onion layer 48, onion ring 16,
onion parameters 1232, ReGIR parameters 1296.

Pinned-build observation (recorded, exercised): the `ReSTIRDIContext`
constructor leaves `m_runtimeParams.frameIndex` **indeterminate** and does
not call `SetFrameIndex`; the application owns the frame counter (the
upstream sample calls `SetFrameIndex` every frame). The suite therefore calls
`rtxdi_di_set_frame_index(0)` right after creation, and the buffer-index
rotation follows the call sequence: frame 0 -> (0,2,0,0,1,1), frame 1 ->
(2,1,2,2,0,0), frame 2 -> (1,0,1,1,2,2), frame 3 -> frame 0 (3-cycle).

## 4. Owned images (settings plumbing)

- `RtxdiParams` -- an owned image per struct kind (mirror + 64B slack) with
  the field offset/size table fetched from the bridge's `offsetof` mirrors
  (single source of ABI truth). Generic `get_u32/get_i32/get_f32` and
  `set_u32/set_f32` by field index, plus `_at` variants with a byte delta for
  nested sub-structs (light-buffer regions, environment block).
- Bridge-carried defaults for the seven `GetDefault*` images; the present
  path B3 check proves they are byte-identical to the SDK's.
- Images are composable into the 272-byte `RTXDI_Parameters` constant block
  (layout anchors in A3).

## 5. Loader model and classification

`rtxdi_load()` => `XIOM_RTXDI_SHIM` env var first, then the default module
search (`xiom_rtxdi_shim.dll` in cwd/PATH). Resolves 41 plain export names on
`LoadLibraryA`; a module missing entry points classifies `RTXDI_LOAD_ABI`
(FAIL), a missing module `RTXDI_LOAD_ABSENT` (SKIP, green).

## 6. Local runtime sample + run procedure

| Artifact | Value |
|----------|-------|
| `E:\repos\rtxdi-shim\xiom_rtxdi_shim.dll` | 208,896 bytes, SHA256 `7F12C83E422521EEAC9B332108DCE6E718A9F00B42C938F99FC891FD50A7DC31` |
| Build | clang++ 22.1.8 (LLVM), `-std=c++17 -O2 -shared -fuse-ld=lld`; compiles `rtxdi_shim_local.cpp` (ours) + `Source/{ImportanceSamplingContext,ReSTIRDI,ReSTIRGI,ReSTIRPT,ReGIR,RISBufferSegmentAllocator,RtxdiUtils}.cpp` with `-I <clone>/Include` |
| Shader path | no shader blobs exist for this runtime; none compiled (device execution out of scope, typed SKIP). The fleet's dxc/shaderc tooling was not used. |
| Present-path x2 | `$env:XIOM_RTXDI_SHIM='E:\repos\rtxdi-shim\xiom_rtxdi_shim.dll'; .\scripts\port.ps1 -Package xiom.rtxdi -TimeoutSec 240` -> 33/33 |
| Default-path x2 | `.\scripts\port.ps1 -Package xiom.rtxdi -TimeoutSec 240` -> 33/33 (SKIP-labelled section B) |

## 7. Re-pin procedure

See `PROVENANCE.md` ("Re-carve procedure"): refresh the RTXDI tag + library
revision, re-read the oracle, diff enums/layouts/defaults, rebuild the local
shim sample, run SKIP x2 + present x2, record with `scripts/status.ps1`, sync
counts here.

## 8. Non-goals (0.1.0)

- GPU execution/device bridge (`RTXDI_EXEC_NO_DEVICE` typed SKIP).
- ReSTIR GI / ReSTIR PT API binding (contexts are constructed by the SDK's
  top-level context; no public API surfaced by this package).
- Descriptor/resource binding to a device; shader compilation and dispatch.
- Distribution of any RTXDI artifact (license, sec. 2).
