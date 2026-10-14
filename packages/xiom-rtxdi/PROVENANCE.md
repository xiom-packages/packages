# PROVENANCE: xiom.rtxdi

Per lane doctrine `docs/UPSTREAM-FIRST.md` (owner policy 2026-10-11).

## Upstream

| Field | Value |
|-------|-------|
| Project | NVIDIA RTXDI -- https://github.com/NVIDIAGameWorks/RTXDI |
| Upstream license | **NOT MIT** -- the proprietary "NVIDIA RTX SDKs LICENSE" (`LICENSE.txt`, SHA256 `27638E2233A18FBFFAA57758A9A5A407D4EFCA7CC72DE60DC4ED6E8627398EF2`); every public header carries SPDX `LicenseRef-NvidiaProprietary`. |
| License finding | Verified 2026-10-14 against v3.1.0 (latest stable release) and the RTXDI-Library revision it pins (`f12037fa`); no MIT revision exists in the release line (v1.x/v2.x checked at v1.3.0/v2.0.0/v2.3.1 -- all NVIDIA RTX SDKs License). |
| Policy | **Reference-only, dynamic loader only. NEVER vendored** (FFmpeg/NRD precedent, `docs/BINDINGS-LANE.md` sec. 4/11; ledger rows `E:\repos\CLEANUP.md`). No RTXDI code, headers, shader sources or binaries are copied, linked, or committed to this repository. |
| Reference clones | `E:\repos\RTXDI` -- pinned tag **v3.1.0**, commit `a6efab966b7c3b272da0461578eb56ac61c7cbff` (2026-09-03, shallow; sample/integration repository). Runtime library: `E:\repos\RTXDI-Library` -- pinned commit **`f12037fa8e97ebc08e9e3edfd2de528ed1772a4b`**, the revision v3.1.0 selects for `Libraries/Rtxdi` (shallow; the library has no release tags). |
| Package license | MIT OR Apache-2.0 (no upstream code in this package) |

The shipped surface is **independent XIOM code** (`rtxdi.xi`) plus an
XIOM-side C++ bridge (`src/rtxdi_bridge.cpp`, ours) written against the
public header **declarations** of the pinned revision (the "declaration
oracle" below). Nothing from RTXDI is copied or linked: the loader resolves
`xiom_rtxdi_shim.dll` (a locally built sample, below) at run time and the
suite classifies `RTXDI_LOAD_ABSENT` (SKIP, green) when it is not present.

## Declaration oracle (files read at the pinned revision)

| File | SHA256 |
|------|--------|
| `Include/Rtxdi/RtxdiTypes.h` | `78AD0D8F75ACC58EE289E635B926BE991BBDE1D04FB242118DEEFBDD0F6F5BE5` |
| `Include/Rtxdi/RtxdiParameters.h` | `EFF40446099CABDE4896488B4765552EA070D82E6ABA68C09793FA575FA36EE8` |
| `Include/Rtxdi/RtxdiUtils.h` | `25D8DC0DD1CB7FB79C9A154A4D313F925791BF723EF61FB7A1BDC3F0AE51FF5B` |
| `Include/Rtxdi/DI/ReSTIRDI.h` | `CD84BC7424BA97E7DA80EDDAE4E0617ED42127A9A4B6473A540202D74836DE4C` |
| `Include/Rtxdi/DI/ReSTIRDIParameters.h` | `96C36815D06F915519C2844005B9A67F4AE8E1597A3107C5C5F1E74A6B6039CE` |
| `Include/Rtxdi/LightSampling/RISBufferSegmentParameters.h` | `73571C665DC331A45020FDB36DD7C9B38C0A2A0297A6B805D96D078473FDAF8B` |
| `Include/Rtxdi/LightSampling/RISBufferSegmentAllocator.h` | `86F8A95BC8D0EB7809F62E964B7D9D0BE74041061BDA9F2F5D30B7C8FACAB36C` |
| `Include/Rtxdi/ReGIR/ReGIR.h` | `8B73351C3C0C71883E5BBFBD3A0CFB026AD094B079D78ADABDF21B660E915BFC` |
| `Include/Rtxdi/ReGIR/ReGIRParameters.h` | `ED4EC974469089E21661117C09C2E7383D4C0EE563C055D16958E4C37127567A` |
| `Include/Rtxdi/ImportanceSamplingContext.h` | `DDE0C9D9892F3E13DC7DCD4E1B9E04BB464135E077FFEF26171302ACAF6AC2AE` |
| `Source/ReSTIRDI.cpp` | `7B24C1010B0AD9E612ED7303135E1144705C624520F0B983A6AE2F28CBB7A681` |
| `Source/RtxdiUtils.cpp` | `61D0A91C43951ED407FE150A6CF2CC6F5E01B94459DE3E5528E4DD2BC7A5EE3B` |
| `Source/ReGIR.cpp` | `549EC9256E8731F4DF5E197C6EE98A24FE5FB5BC6E98C62A4A1177D59A44A81B` |
| `Source/RISBufferSegmentAllocator.cpp` | `CA4B609FDA31267D87D052E4B67FAD77C15CF17AD4AD3B1BDF51F906072C161D` |
| `Source/ImportanceSamplingContext.cpp` | `0524C641479D329D8D3CDF5967F795659AE8E031C0764839FA3403E58D5C10CD` |

Bound entry-point signatures, the ABI mirror structs (20 structs, all
4-byte-scalar fields), the seven `GetDefault*` value sets and the constant
table in `src/rtxdi_bridge.cpp` come from these files; result semantics
(reservoir pitches, PDF sizing, R2 neighbor offsets, JenkinsHash, buffer
index rotation, ReGIR onion/grid computation, segment allocation, RIS
segment planning) are exercised against the locally built shim in the
present path.

### Pinned-build observations (recorded, not asserted upstream)

- 20 struct layouts cross-checked field-by-field (offsets+sizes) between the
  bridge mirrors and the SDK structs (B2); padded aggregates:
  boiling 16B, light region 16B, environment light 16B, RIS segment 16B,
  runtime 16B, `RTXDI_Parameters` 272B.
- The seven `GetDefault*` images are byte-identical to the bridge-carried
  defaults (B3); e.g. initial sampling 8/1/1/1 with `brdfCutoff` 1e-4,
  boiling 0.2, spatial radius 32, shading max age 4 / max distance 16.
- `ReSTIRDIContext` constructor: `m_runtimeParams.frameIndex` is
  **indeterminate** until the application calls `SetFrameIndex` (the
  constructor sets only `neighborOffsetMask`); observed as heap-dependent
  garbage in an early suite revision -- the module and suite now follow the
  upstream sample flow and set the frame index explicitly.
- Buffer-index rotation is call-sequence driven (SetFrameIndex advances
  `last <- current`): frame 0 -> (init 0, tIn 2, tOut 0, sIn 0, sOut 1,
  shade 1); frame 1 -> (2,1,2,2,0,0); frame 2 -> (1,0,1,1,2,2); frame 3 ->
  frame 0. `uniformRandomNumber = JenkinsHash(frameIndex)`
  (0 -> 1800329511, 1 -> 3028713910, 7 -> 4090419040).
- Reservoir pitches: 320x180-16blocks off -> row 5120 / array 61440;
  black checkerboard -> 2560/30720. PDF 1000 -> 32x32 mips 6.
- Neighbor offsets: R2 sequence scaled by radius 250, stored as uint8 pairs:
  bytes `C3 95 42 B8 04 45 C8 DB` for count 4; decode (-61,-107), (66,-72).
- RISBufferSegmentAllocator: first two 1024x128 segments at element offsets
  0 and 131072, total 262144.
- ReGIR onion (16x16x16 grid, 512 lights/cell, detail 5, coverage 10):
  cubic root factor 1.776785, linear factor 0.385351, 5 layer groups,
  25 rings, 2229 cells, 1141248 light slots, ring cell counts 8/5/1;
  grid mode 4x6x8x16 -> 3072 slots.
- Top-level context (320x180, onion): local RIS @0, environment RIS
  @131072, total RIS 1403392, neighbor count 8192, power-RIS off until a
  Power_RIS mode is set.

## Derived vs independent

- `rtxdi.xi` (module, all `unsafe`/`extern`): **independent** XIOM code --
  loader classification, the 41-entry-point dynamic bind, typed errors,
  owned parameter images (layouts from the bridge), defaults, frame-plan
  composition, RIS/ReGIR/IS context plumbing, typed execute classification.
- `src/rtxdi_bridge.cpp`: **original XIOM-side helper** (ours, MIT OR
  Apache-2.0). It never links RTXDI: it encodes only interface facts (export
  names, struct layouts, enum values, default value sets) from the
  declaration oracle above, copies all response data into XIOM-owned slots
  (B-20/B-24 discipline), and forwards every behavioural call to the
  resolution-loaded shim.
- `tests/test_conformance.xi`: original; probes are built in-module (no
  upstream test vectors exist for this surface).

## Local runtime sample used for present-path proof (NOT committed)

| Artifact | Value |
|----------|-------|
| `E:\repos\rtxdi-shim\xiom_rtxdi_shim.dll` (x64) built locally from the pinned runtime | 208,896 bytes, SHA256 `7F12C83E422521EEAC9B332108DCE6E718A9F00B42C938F99FC891FD50A7DC31` |
| Shim source | `E:\repos\rtxdi-shim\rtxdi_shim_local.cpp` (the licensee's own C-ABI integration layer; kept outside the repository) |
| Build toolchain | clang++ 22.1.8 (LLVM), MSVC 2026 headers/libs |
| Build command | `clang++ -std=c++17 -O2 -shared -fuse-ld=lld -o xiom_rtxdi_shim.dll rtxdi_shim_local.cpp <clone>/Source/ImportanceSamplingContext.cpp <clone>/Source/ReSTIRDI.cpp <clone>/Source/ReSTIRGI.cpp <clone>/Source/ReSTIRPT.cpp <clone>/Source/ReGIR.cpp <clone>/Source/RISBufferSegmentAllocator.cpp <clone>/Source/RtxdiUtils.cpp -I <clone>/Include` |
| Shader path | **no shader compilation**: the runtime ships no prebuilt shader blobs and the CPU-side surface needs none; device-side ReSTIR execution is out of scope for 0.1.0 (typed SKIP). The fleet's dxc/shaderc tooling was not used. |
| Run-time discovery | `XIOM_RTXDI_SHIM` env var (present-path runs), else the default module search (`xiom_rtxdi_shim.dll` on cwd/PATH). Default PATH -> `RTXDI_LOAD_ABSENT` SKIP. |

The shim, its source and the clones stay outside the repository and are
registered in `E:\repos\CLEANUP.md`.

## Test vectors

None imported from upstream. The suite builds its own deterministic scene
(320x180, 16px reservoir blocks, 8192 neighbor offsets, 128-element RIS
tiles) and asserts SDK-reported facts (struct sizes, layout tables, defaults
byte-compare, reservoir pitches, PDF sizing, packed constants, buffer-index
rotation + JenkinsHash URNs, RIS/ReGIR/IS offsets and totals) plus the typed
error/classification paths.

## Re-carve procedure (upstream moves)

1. Refresh `E:\repos\RTXDI` (new stable tag) and `E:\repos\RTXDI-Library`
   (revision selected by that tag's `Libraries/Rtxdi` submodule); update the
   pins here and the `E:\repos\CLEANUP.md` review date.
2. Re-read the declaration oracle (files above); re-hash them into the table.
3. Diff enum values, struct field order/sizes (present-path layout probe B2
   fails on drift), `GetDefault*` values (B3), reservoir/PDF/neighbor/RIS
   rules and the ReGIR onion math (B4-B6, B13-B14), buffer-index rotation
   (B8/B9).
4. Rebuild the local shim sample with the recorded command; run
   `scripts/port.ps1 -Package xiom.rtxdi` default SKIP x2 + present-path x2,
   record with `scripts/status.ps1`, conventional commit; sync `SPEC.md`
   counts in the same commit.
