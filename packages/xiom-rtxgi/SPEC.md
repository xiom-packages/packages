# SPEC: xiom.rtxgi -- NVIDIA RTXGI-DDGI integration surface

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.rtxgi` |
| Version | 0.1.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | NVIDIA RTXGI-DDGI (DDGI v1.x SDK) -- https://github.com/NVIDIAGameWorks/RTXGI-DDGI |
| Upstream version | pinned tag **v1.3.7** (commit `c233266e`, 2023-05-08; GitHub "Latest" release) |
| Upstream license | **NOT MIT** -- proprietary "NVIDIA RTX SDKs LICENSE" (see PROVENANCE.md) |
| Package license | MIT OR Apache-2.0 (no upstream code in this package) |
| Platform | Windows x64 (shim module via the loader) |
| Compiler pin | v0.64.4 |
| Reference clone | `E:\repos\RTXGI-DDGI` @ `c233266e95931231961f35c842c78e7c4bdc50cf` -- declaration oracle, `PROVENANCE.md` |
| Runtime module | `xiom_rtxgi_shim.dll` built locally from the clone by the licensee (`XIOM_RTXGI_SHIM` or default module search; SKIP when absent) |

Scope note: the task named `github.com/NVIDIAGameWorks/RTXGI`. That repository
at its latest release (v2.8.0) is the **NRC/SHaRC sample suite and does NOT
contain the DDGI algorithm**; the DDGI v1.x SDK (the surface named in the
task: volume create/move/update, probe counts/blending, resource binding,
constants) lives at `github.com/NVIDIAGameWorks/RTXGI-DDGI`, whose latest
release is v1.3.7. Both repositories were cloned and license-verified
(NOT MIT in either); RTXGI-DDGI v1.3.7 is the pin for this package.

## 2. Decision: reference-only, dynamic loader only (never vendored)

The coordinator task expected MIT and required verification. Verification
(2026-10-14, v1.3.7 + RTXGI v2.8.0) found the **NVIDIA RTX SDKs License**,
which forbids source redistribution (4(b)), forbids applying an open-source
license to the SDK (4(e)) and permits distribution only as object code
incorporated into an application. Vendoring the C++ library (or its HLSL
shaders) into this MIT/Apache-2.0 repository is therefore not permitted, and
the bridge is **not** built by linking an RTXGI import library.

This package follows the NRD/FFmpeg precedent (`BINDINGS-LANE.md` sec. 4/11):
independent XIOM code written against the public header declarations, a
runtime dynamic loader, and a classified SKIP path when the runtime module is
absent. Present-path proof uses a locally built `xiom_rtxgi_shim.dll` (the
licensee's "install and use / modify" grant; PROVENANCE.md); nothing from
RTXGI ships in this repository -- no source, no headers, no shader blobs,
no binaries.

Consequences (explicit non-goals for 0.1.0):

- No GPU execution: dispatching the DDGI ray-trace/blend/relocate passes
  requires the application's D3D12/VK device, the probe textures/descriptor
  heaps and the compiled shader bytecode. `rtxgi_execute` returns the typed
  `RTXGI_EXEC_NO_DEVICE` classification (SKIP), never a silent success.
  Shader handling: the v1.3.7 repository ships **no prebuilt shader blobs**
  (they are produced by the SDK's build system); no HLSL was compiled by this
  package, and the fleet's dxc/shaderc tooling was not used.
- The D3D12/VK subclasses (`DDGIVolume_D3D12.h`, `DDGIVolume_VK.h`): device
  and resource-management surface; out of scope (device path).
- No RTXGI.h in the build: the ABI mirror structs live in
  `src/rtxgi_bridge.cpp` (ours, written from the declaration oracle); layer
  drift is caught by the present-path layout probe (B5) against the shim's
  real structs and by the re-carve procedure.

## 3. Declared surface (100% of the DDGI v1.3.7 public integration API)

Bound through the loader and exercised by the suite (present path):

| Surface | Detail | Suite coverage |
|---------|--------|----------------|
| `GetDDGIVolumeNumRTVDescriptors` / `...Tex2DArrayDescriptors` / `...ResourceDescriptors` | 2 / 6 / 12 | B2 (runtime-reported == pinned constants) |
| `ValidateShaderBytecode` | `ShaderBytecode{pData,size}` validity | B3 (empty false, non-empty true) |
| `SetInsertPerfMarkers` / `bInsertPerfMarkers` | global toggles | B4 (default true, roundtrip) |
| `DDGIVolumeDesc` | 38 fields, owned-image plumbing + defaults | A2/A5/A6, B6 (defaults drift), B7 (probe counts), B8 (texture dims) |
| `GetDDGIVolumeProbeCounts` | y/z axis swap for the pinned right-handed y-up build | B7 (3,2,4) -> (3,4,2) |
| `GetDDGIVolumeTextureDimensions` | 6 texture types | B8: ray(256,12,2) irr(30,40,2) dist(54,72,2) data(3,4,2) var(24,32,2) vavg(2,2,1) |
| `DDGIVolumeBase` lifecycle | create, `Update`, `SeedRNG`, `GetRandomFloat`, `Destroy` | B9, B11, B18 |
| `Set/GetOrigin`, `SetScrollAnchor`, `SetMovementType` | scrolling volumes | B13 (offset 3/clear -> ScrollReset folds into origin) |
| `SetProbeHysteresis`, `SetEulerAngles` | rotation matrices/quaternions | B10, B16 (y=90deg -> (0,.7071,0,.7071); rotated AABB) |
| `GetDescGPU` / `GetDescGPUPacked` | 160B typed image / 128B packed constants | B10, B11, B12 (word0/1/2 pinned, decode counts) |
| `DDGIVolumeResourceIndices` / `DDGIRootConstants` | layout anchors (48B / 24B + 32B aligned) | A3, A4, B5 |
| `GetNumProbes` / `GetNumRaysPerProbe` / `GetTexture2DArraySize` / `GetRayDispatchDimensions` / `GetGPUMemoryUsedInBytes` | 24 / 256 / 2 / (256,12,2) / 9760 bytes | B9 |
| `GetProbeWorldPosition` / `GetAxisAlignedBoundingBox` / `GetOrientedBoundingBox` | grid math + bounds | B14, B15 |
| `ERTXGIStatus` | 86 values (OK + 85 codes) | A4 (spot anchors), typed error mapping |
| `float3/4`, `int3`, `AABB`, `OBB` | value types crossing the surface | parsed into `RtxgiF3/F4/I3/Aabb/Obb` |

Constants mirrored from the headers (all reachable as `pub const`):
version 1.3.7; 4 coordinate systems; 2/6/12 descriptor counts; 86 status
values; 6 texture types + 7 formats; 2 movement types; 2 probe-vis types;
root-constants sizes 24/32; packed bit layouts (mask 1023, shifts 10/20,
threshold scale 65535, scroll mask 32767, packed4 feature shifts 16..31).
Spelling alignment: the bridge keeps the SDK enum names in XIOM constants
(e.g. `RTXGI_TEXTURE_FORMAT_F32X2` for `F32x2`).

## 4. Owned images (settings plumbing)

- `RtxgiDesc` -- a 168-byte owned image (mirror + 64B slack) with the field
  offset/size table fetched from the bridge's `offsetof` mirror (single source
  of ABI truth). Setters/getters: i32/u32-LE, f32, bool, and `*_at` element
  variants for the 3/4-component fields. `rtxgi_desc_for_volume` reproduces
  the SDK sample convention (border texels = interior + 2).
- `RtxgiPacked` -- the 128-byte `DDGIVolumeDescGPUPacked` image; word
  accessors at offsets 92..108; probe counts decode from `packed0`.
- Defaults: the bridge carries the header's documented default member
  initializers; the present path B6 check proves the bridge defaults are
  byte-identical to the SDK's value-initialized struct.

## 5. Loader model and classification

`rtxgi_load()` => `XIOM_RTXGI_SHIM` env var first, then the default module
search (`xiom_rtxgi_shim.dll` in cwd/PATH). Resolves 30 plain export names on
`LoadLibraryA`; a module missing entry points classifies `RTXGI_LOAD_ABI`
(FAIL), a missing module `RTXGI_LOAD_ABSENT` (SKIP, green).

## 6. Local runtime sample + run procedure

| Artifact | Value |
|----------|-------|
| `E:\repos\rtxgi-shim\xiom_rtxgi_shim.dll` | 137,216 bytes, SHA256 `0D39685AE2E3616AB5401ED95D9FB0D3E67AC5911CEA72FD5799D3F9FBC117EC` |
| Build | clang++ 22.1.8 (LLVM), `-std=c++17 -O2 -shared -fuse-ld=lld`; compiles `rtxgi_shim_local.cpp` (ours) + `rtxgi-sdk/src/ddgi/DDGIVolume.cpp` + `rtxgi-sdk/src/Math.cpp` with `-DRTXGI_COORDINATE_SYSTEM=2 -DRTXGI_DDGI_RESOURCE_MANAGEMENT=0` (SDK CMake defaults) |
| Shader path | no shader blobs exist in the v1.3.7 repository and none were compiled; GPU pipeline creation is out of scope (typed SKIP) |
| Present-path x2 | `$env:XIOM_RTXGI_SHIM='E:\repos\rtxgi-shim\xiom_rtxgi_shim.dll'; .\scripts\port.ps1 -Package xiom.rtxgi -TimeoutSec 240` -> 28/28 |
| Default-path x2 | `.\scripts\port.ps1 -Package xiom.rtxgi -TimeoutSec 240` -> 28/28 (SKIP-labelled section B) |

The DLL, the shim source and the clone stay outside the repository
(`E:\repos\rtxgi-shim`, `E:\repos\RTXGI-DDGI`) and are registered in
`E:\repos\CLEANUP.md`.

## 7. Re-pin procedure

See `PROVENANCE.md` ("Re-carve procedure"): refresh the clone, re-read the
oracle, diff enums/layouts/defaults, rebuild the local shim sample, run
SKIP x2 + present x2, record with `scripts/status.ps1`, sync counts here.

## 8. Non-goals (0.1.0)

- GPU execution/device bridge, probe texture allocation, descriptor heaps,
  shader bytecode compilation (`RTXGI_EXEC_NO_DEVICE` typed SKIP).
- The D3D12/VK volume subclasses and managed-resource mode (device path).
- Probe relocation/classification/variability state machines beyond the
  desc flags mirrored in the images (they execute on the GPU passes).
- Distribution of any RTXGI artifact (license, sec. 2).
