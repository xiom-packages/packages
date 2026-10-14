# PROVENANCE: xiom.rtxgi

Per lane doctrine `docs/UPSTREAM-FIRST.md` (owner policy 2026-10-11).

## Upstream

| Field | Value |
|-------|-------|
| Project | NVIDIA RTXGI-DDGI (DDGI v1.x SDK) -- https://github.com/NVIDIAGameWorks/RTXGI-DDGI |
| Upstream license | **NOT MIT** -- the proprietary "NVIDIA RTX SDKs LICENSE" (`License.txt`, SHA256 `85201D19C2DC5041D9A2029E9FDA9D78105FE41CE21CE9701D4AA7E56184B6E7`) |
| License finding | Verified 2026-10-14 against v1.3.7 (the clone) and the NVIDIAGameWorks/RTXGI v2.8.0 repository: both ship the RTX SDKs License, not an OSI license. Clauses 4(b)/4(e) forbid redistribution of SDK material and any open-source-license application; grants cover install/use, derivative works of sample source, and object-code incorporation into an application only. |
| Policy | **Reference-only, dynamic loader only. NEVER vendored** (FFmpeg/NRD precedent, `docs/BINDINGS-LANE.md` sec. 4/11; ledger rows `E:\repos\CLEANUP.md`). No RTXGI code, headers, shader blobs or binaries are copied, linked, or committed to this repository. |
| Scope finding | The task named github.com/NVIDIAGameWorks/RTXGI, but that repo at its latest release (v2.8.0, `711dd7ad`) is the NRC/SHaRC sample suite and does not contain the DDGI surface named in the task. The DDGI v1.x SDK lives at RTXGI-DDGI; tag **v1.3.7** = commit `c233266e` (2023-05-08) is its GitHub "Latest" release and the pin here. |
| Reference clone | `E:\repos\RTXGI-DDGI` -- pinned tag **v1.3.7**, commit `c233266e95931231961f35c842c78e7c4bdc50cf` (shallow). Related clone `E:\repos\RTXGI` (v2.8.0) kept for the license/scope record. |
| Package license | MIT OR Apache-2.0 (no upstream code in this package) |

The shipped surface is **independent XIOM code** (`rtxgi.xi`) plus an
XIOM-side C++ bridge (`src/rtxgi_bridge.cpp`, ours) written against the
public header **declarations** of the pinned commit (the "declaration
oracle" below). Nothing from RTXGI is copied or linked: the loader resolves
`xiom_rtxgi_shim.dll` (a locally built sample, below) at run time and the
suite classifies `RTXGI_LOAD_ABSENT` (SKIP, green) when it is not present.

## Declaration oracle (files read at the pinned commit)

| File | SHA256 |
|------|--------|
| `rtxgi-sdk/include/rtxgi/Common.h` | `4D9764DBA6A15970351CC742AB895DDE2E4EC630F342D99DB63DC76B4451572C` |
| `rtxgi-sdk/include/rtxgi/Defines.h` | `C10DE33FF719DAEC7E0E31D030D6E7B084D37D8956829FEB81F2E24C5572246A` |
| `rtxgi-sdk/include/rtxgi/Types.h` | `5BD49325661EB3CBE41C2CA6B6337A4B32B50EB71A0EF80FDBDF3F947D400DF3` |
| `rtxgi-sdk/include/rtxgi/Math.h` | `C4D014AD8E8AB7B9ECE2D287C481217F2AC214BC747CD0239CACBF3D890358E7` |
| `rtxgi-sdk/include/rtxgi/ddgi/DDGIVolume.h` | `BC85D0F08ECC33140769A1C1F294EAEDBF7AF14069FE54B9484F51B75DC03947` |
| `rtxgi-sdk/include/rtxgi/ddgi/DDGIVolumeDescGPU.h` | `78652BF8463BDDCF03C0475FC395D70907D8B5C33493473A5F90BB3668C6BC52` |
| `rtxgi-sdk/include/rtxgi/ddgi/DDGIRootConstants.h` | `6B45221F233E218EA06A54D1E52CAD4087C2AE25A5FD611E3E79E45922E5EE3F` |
| `rtxgi-sdk/src/ddgi/DDGIVolume.cpp` | `02E1198BCFCC1D0E762A0245B160A825375B5DB6ABA0740D715298F69B713CF2` |
| `rtxgi-sdk/src/Math.cpp` | `36F96E45ADBF6D57AC3CB402795D147F8DD37698EAEE775860C8837E8E300A54` |

Bound entry-point signatures, the ABI mirror structs (DDGIVolumeDesc,
DDGIVolumeDescGPU, DDGIVolumeDescGPUPacked, DDGIVolumeResourceIndices,
DDGIRootConstants) and the default member initializers in
`src/rtxgi_bridge.cpp` come from these headers; result semantics and the
device-free behaviour (probe-count axis swap, texture-dimension rules,
scrolling/ScrollReset, packed bit layout, GPU-memory formula, RNG-based
rotation) were read from `DDGIVolume.cpp` / `Math.cpp` and are exercised
against the locally built shim in the present path.

### Pinned-build observations (recorded, not asserted upstream)

- Sizes on x64: `DDGIVolumeDesc` 168B / `DDGIVolumeDescGPU` 160B /
  `DDGIVolumeDescGPUPacked` 128B / `DDGIVolumeResourceIndices` 48B /
  `DDGIRootConstants` 24B (32B aligned); the present-path layout probe
  compares all 5 field tables against the SDK structs.
- Coordinate system: right hand, y-up (SDK CMake default, value 2).
  `GetDDGIVolumeProbeCounts(3,2,4)` -> texture counts (3,4,2).
- `GetGPUMemoryUsedInBytes` for the suite scene (24 probes, 256 rays,
  10/18 texels, all-U32 formats) = **9760 bytes**.
- Packed words for the suite scene: word0=4196355, word1=1073682841,
  word2=268960000, word3=word4=0.
- `ScrollReset` folds an offset that is a multiple of the probe count into
  the origin at the start of the next `ComputeScrolling` (anchor +3.2 cells,
  counts.x=3: update1 -> offset 3/clear, update2 -> origin.x 1->4, offset 0).
- `SeedRNG` drives a process-wide `std::mt19937` (SDK static): re-seeding
  reproduces the ray-rotation quaternion exactly; seed 4242 yields
  q=(0.9537,-0.1755,0.1276,0.2081).

## Derived vs independent

- `rtxgi.xi` (module, all `unsafe`/`extern`): **independent** XIOM code --
  loader classification, the 30-entry-point dynamic bind, typed errors,
  owned desc/packed images (layouts fetched from the bridge), probe
  counts/texture dimensions passthrough, volume lifecycle, packed-word
  decode, typed execute classification. No RTXGI code, tables, or generated
  files.
- `src/rtxgi_bridge.cpp`: **original XIOM-side helper** (ours, MIT OR
  Apache-2.0). It never links RTXGI and knows no RTXGI implementation: it
  encodes only interface facts (export names, struct layouts, enum values,
  default member initializers) from the declaration oracle above, copies all
  response data into XIOM-owned slots (B-20/B-24 discipline), and forwards
  every behavioural call to the resolution-loaded shim.
- `tests/test_conformance.xi`: original; probes are built in-module (no
  upstream test vectors exist for this surface).

## Local runtime sample used for present-path proof (NOT committed)

| Artifact | Value |
|----------|-------|
| `E:\repos\rtxgi-shim\xiom_rtxgi_shim.dll` (x64) built locally from the pinned clone | 137,216 bytes, SHA256 `0D39685AE2E3616AB5401ED95D9FB0D3E67AC5911CEA72FD5799D3F9FBC117EC` |
| Shim source | `E:\repos\rtxgi-shim\rtxgi_shim_local.cpp` (the licensee's own C-ABI integration layer; kept outside the repository) |
| Build toolchain | clang++ 22.1.8 (LLVM), MSVC 2026 headers/libs |
| Build command | `clang++ -std=c++17 -O2 -shared -fuse-ld=lld -o xiom_rtxgi_shim.dll rtxgi_shim_local.cpp <clone>/rtxgi-sdk/src/ddgi/DDGIVolume.cpp <clone>/rtxgi-sdk/src/Math.cpp -I <clone>/rtxgi-sdk/include -DRTXGI_COORDINATE_SYSTEM=2 -DRTXGI_DDGI_RESOURCE_MANAGEMENT=0` |
| Shader path | **no shader compilation**: the v1.3.7 repository ships no prebuilt blobs (the SDK build produces them), and the device-free surface needs none; GPU pipeline creation is out of scope for 0.1.0 (typed SKIP). The fleet's dxc/shaderc tooling was **not** used. |
| Run-time discovery | `XIOM_RTXGI_SHIM` env var (present-path runs), else the default module search (`xiom_rtxgi_shim.dll` on cwd/PATH). Default PATH -> `RTXGI_LOAD_ABSENT` SKIP. |

The shim, its source and the clones stay outside the repository and are
registered in `E:\repos\CLEANUP.md`.

## Test vectors

None imported from upstream. The suite builds its own deterministic scene
(3x2x4 probes, 256 rays, interior 8/16 texels, origin (1,2,3)) and asserts
SDK-reported facts (sizes, descriptor counts, texture dimensions, GPU memory
9760B, packed words, RNG quaternion reproducibility, scroll offsets) plus
the typed error/classification paths.

## Re-carve procedure (upstream moves)

1. Re-clone/refresh `E:\repos\RTXGI-DDGI` at the new stable tag; update the
   pinned commit here and the `E:\repos\CLEANUP.md` review date.
2. Re-read the declaration oracle (files above); re-hash them into the table.
3. Diff enum values, struct field order/sizes (the present-path layout probe
   B5 fails on any drift), default member initializers (B6), probe-count/
   texture-dimension rules and packed bit layouts (B7/B8/B12).
4. Rebuild the local shim sample with the recorded command; run
   `scripts/port.ps1 -Package xiom.rtxgi` default SKIP x2 + present-path x2,
   record with `scripts/status.ps1`, conventional commit; sync `SPEC.md`
   counts in the same commit.
