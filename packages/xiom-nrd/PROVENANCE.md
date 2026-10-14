# PROVENANCE: xiom.nrd

Per lane doctrine `docs/UPSTREAM-FIRST.md` (owner policy 2026-10-11).

## Upstream

| Field | Value |
|-------|-------|
| Project | NVIDIA Real-time Denoisers (NRD) -- https://github.com/NVIDIA-RTX/NRD (formerly NVIDIAGameWorks/RayTracingDenoiser) |
| Upstream license | **NOT MIT** -- the proprietary "NVIDIA RTX SDKs LICENSE" (`LICENSE.txt`, v. April 12, 2021; SHA256 `85201D19C2DC5041D9A2029E9FDA9D78105FE41CE21CE9701D4AA7E56184B6E7`) |
| License finding | Verified 2026-10-13 against v4.17.3 and current master: both ship the RTX SDKs License, not an OSI license. Clauses 4(b)/4(e) forbid redistribution of SDK material and any open-source-license application; grants cover install/use and object-code incorporation into an application only. |
| Policy | **Reference-only, dynamic loader only. NEVER vendored** (even more restrictive than the LGPL/MPL class; FFmpeg precedent, `docs/BINDINGS-LANE.md` sec. 4/11; ledger row `E:\repos\CLEANUP.md`). No NRD code, headers, shader blobs or binaries are copied, linked, or committed to this repository. |
| Reference clone | `E:\repos\nrd` -- pinned tag **v4.17.3**, commit `792eff196afdd350fd9c3f862119017ccb438a0e` (2026-04-30; shallow clone). v4.18.0 (tag 2026-10-09) is the newest tag but is flagged **pre-release** on GitHub (`releases/latest` -> v4.17.3), so the pin is the latest stable release. |
| Package license | MIT OR Apache-2.0 (no upstream code in this package) |

The shipped surface is **independent XIOM code** (`nrd.xi`) plus an
XIOM-side C++ bridge (`src/nrd_bridge.cpp`, ours) written against the
public header **declarations** of the pinned commit (the "declaration
oracle" below) and verified against a locally built NRD.dll at run time.
Nothing from NRD is copied or linked: the loader resolves `NRD.dll` at run
time and the suite classifies `NRD_LOAD_ABSENT` (SKIP, green) when the
module is not present.

## Declaration oracle (files read at the pinned commit)

| File | SHA256 |
|------|--------|
| `Include/NRD.h` | `A14FA17E766BA7BA80B4412AC923AD50751DED046B992FF872279621132728CF` |
| `Include/NRDDescs.h` | `0A57E72E4219A8E9EB6D7F4052A5580D70EFC9E055DA7CC950FF3385644084BF` |
| `Include/NRDSettings.h` | `6D9884A3E6DE77CD097627A390BE870B27C0C836788C2E9659015F7F8B7F486D` |
| `Source/Wrapper.cpp` | `5D0702E5DBA3FD25D92FA6F4A877FD6DA204424CEDEC904280407CFB39513A84` |
| `Source/InstanceImpl.cpp` | `4B4BF9F1B824D9C8C67516E1C9E217FFB53E1C215E060D1CD845DFBFEFF36F6E` |

Bound entry-point signatures (all nine `NRD_API extern "C"`, plain export
names) and the ABI mirror structs in `src/nrd_bridge.cpp` come from
`NRD.h`/`NRDDescs.h`; the settings mirrors and the owned-image layout
tables come from `NRDSettings.h`; the result semantics, error cases and the
resource/denoiser name tables were read from `Wrapper.cpp` and
`InstanceImpl.cpp`. The exports were verified byte-for-byte with
`dumpbin /exports` on the locally built DLL (9/9 plain names).

### Pinned-build observations (recorded, not asserted upstream)

- `GetResourceTypeString` name table order in v4.17.3 (`Wrapper.cpp`) is
  **not** consistent with the `ResourceType` enum for indices 3..14: the
  confidence/`DISOCCLUSION_THRESHOLD_MIX` entries are listed later than the
  enum positions. The package forwards the runtime's strings verbatim and
  the suite avoids asserting the affected indices (spot checks use indices
  whose two orders agree: 0/1/2, 15..31).
- `InstanceDesc::shaderEntryPoint` is `NRD_STRINGIFY(NRD_CS_MAIN)` and
  `NRD_CS_MAIN` defaults to `main` (`Shaders/NRD.hlsli`), so the pinned
  build reports `"main"` (asserted with that expectation).
- `ReblurSettings`/`RelaxSettings`/`SigmaSettings`/`ReferenceSettings`
  mirror sizes on x64: 128/148/20/4 bytes; `CommonSettings` 432 bytes;
  offsets are exposed to XIOM by the bridge's `offsetof` tables (single
  source of ABI truth), cross-checked against the header-derived anchors in
  the suite.
- SPIR-V binding offsets on the pinned CMake configuration: sampler 0,
  texture 20, constant buffer 2, storage 3 (`CMakeLists.txt`
  `SPIRV_*REG_OFFSET` constants).

## Derived vs independent

- `nrd.xi` (module, all `unsafe`/`extern`): **independent** XIOM code --
  loader classification, the nine-entry-point dynamic bind, typed errors,
  owned settings images (layouts fetched from the bridge), the dispatch-plan
  model (summaries/resources/constant buffers in owned slots) and the typed
  execute classification. No NRD code, tables, or generated files.
- `src/nrd_bridge.cpp`: **original XIOM-side helper** (ours, MIT OR
  Apache-2.0). It never links NRD and knows no NRD implementation: it
  encodes only interface facts (export names, struct layouts, enum values,
  settings field order and defaults) from the declaration oracle above, and
  it copies all response data into XIOM-owned slots (B-20/B-24 discipline).
- `tests/test_conformance.xi`: original; probes are built in-bridge (no
  upstream test vectors exist for this surface).

## Local runtime sample used for present-path proof (NOT committed)

| Artifact | Value |
|----------|-------|
| `NRD.dll` (Release, x64) built locally from the pinned clone | 182,784 bytes, SHA256 `AFD8B2B46B999BCDD8A03AB4009348A4E0468CDB234A33B3920723D7539E84AD` |
| Build toolchain | CMake 4.3.3 + MSVC (Visual Studio 18 Community, v14.51) |
| Build command | `cmake -S E:\repos\nrd -B E:\repos\nrd_build -G "Visual Studio 18 2026" -A x64 -DNRD_NRI=OFF -DNRD_EMBEDS_DXBC_SHADERS=OFF -DNRD_EMBEDS_DXIL_SHADERS=OFF -DNRD_EMBEDS_SPIRV_SHADERS=OFF` then `cmake --build E:\repos\nrd_build --config Release -j` |
| Shader path | **no shader compilation**: the git repository ships no prebuilt shader blobs (they are produced by the SDK build), and all three `NRD_EMBEDS_*` options are OFF for this harness build, so no DXBC/DXIL/SPIR-V blobs were compiled or shipped. The instance lifecycle and `GetComputeDispatches` plan computation need no blobs; GPU pipeline creation is out of scope for 0.1.0 (typed SKIP). The fleet's dxc/shaderc tooling was **not** used. |
| Run-time discovery | `XIOM_NRD_DLL` env var (present-path runs), else the default module search (`NRD.dll` on cwd/PATH). Default PATH -> `NRD_LOAD_ABSENT` SKIP. |

The DLL and the clone stay outside the repository (`E:\repos\nrd`) and are
registered in `E:\repos\CLEANUP.md`.

## Test vectors

None imported from upstream. The suite builds its own deterministic probes
(320x180 settings frame, two-denoiser instance) and asserts runtime-reported
facts (version 4.17.3, 19 supported denoisers, name tables, plan shape)
plus behaviour (typed error codes, constant-buffer reuse, frameIndex-driven
constant changes).

## Re-carve procedure (upstream moves)

1. Re-clone/refresh `E:\repos\nrd` at the new stable tag; update the pinned
   commit here and the `E:\repos\CLEANUP.md` review date.
2. Re-read the declaration oracle (`NRD.h`, `NRDDescs.h`, `NRDSettings.h`,
   `Wrapper.cpp`, `InstanceImpl.cpp`); re-hash the files into this table.
3. Diff enum values, struct field order/sizes (run the layout anchors in
   `tests/test_conformance.xi`), settings defaults, export names
   (`dumpbin /exports` on a freshly built DLL) and the name tables.
4. Rebuild the local runtime sample with the recorded command (or the
   package's updated record), run `scripts/port.ps1 -Package xiom.nrd`
   default SKIP x2 + present-path x2, record with `scripts/status.ps1`,
   conventional commit; sync `SPEC.md` counts in the same commit.
