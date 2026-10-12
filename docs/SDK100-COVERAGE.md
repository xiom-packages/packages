# SDK100 -- 100% Vulkan SDK bindings coverage (program ledger)

Owner directive (2026-10-11): 100% bindings coverage of
`C:\VulkanSDK\1.4.350.0` -- every component with a public C API, not 99.99%.
Definition of Done + coverage matrix: `docs/checklists/vulkan-sdk-100.md`.
Owner policy (upstream-first, 100% target): `docs/UPSTREAM-FIRST.md`.

Legend: **oracle** = functions declared in the shipped/upstream public header
(the count script is committed per package); **bound** = typed XIOM bindings
(wrappers or bridge); **resolved** = runtime-verified against the real DLL (or
vendored build). Coverage = oracle N == bound N == runtime resolved N (with
declared-but-unexported names explicitly listed as SDK shipping facts).

## Component matrix

| # | Component | Package | Oracle | Bound | Runtime resolved | Evidence | Status |
|---|---|---|---|---|---|---|---|
| 1 | Vulkan core+ext (852 registry cmds; 7 vulkansc twins excluded) | `xiom.vulkan` | 845 | 845 | 766/766 advertised (0 unexplained); 75 platform/SC + 4 unadvertised documented | `packages/xiom-vulkan/docs/COVERAGE.md`; `tests/test_full_surface.xi` PASS x2; RHI 22/22 | **DONE** |
| 1a | Vulkan constants | `xiom.vulkan` | 6,050 enum elements | 5,983 consts (5,284 int + 4 float + 695 str) | n/a (constants) | `docs/gen_manifest.json`; zero raw/unresolved | **DONE** |
| 1b | Vulkan struct metadata | `xiom.vulkan` | 1,449 structs/unions | 1,343 sizes + 6,905 offsets (8,243 consts) | n/a (metadata) | `docs/struct_meta_manifest.json`; 106 header-unavailable + 27 bitfields documented; `tests/test_struct_meta.xi` PASS | **DONE** |
| 2 | SPIRV-Tools | `xiom.spirv-tools` | 67 C fns | 67 | 55/55 exported (12 shipping gaps source-verified) | suite 39/39; absent 3/3 SKIP; `docs/COVERAGE.md` | **DONE** (relayed) |
| 3 | SPIRV-Cross | `xiom.spirv-cross` | 169 | 169 | 169/169 | suite 20/20; `docs/COVERAGE.md` | **DONE** (relayed) |
| 4 | SPIRV-Reflect | `xiom.spirv-reflect` | 45 | 45 (vendored + bridge) | 45/45 | suite 40/40; `docs/COVERAGE.md` | **DONE** (relayed) |
| 5 | shaderc | `xiom.shaderc` | 45 | 45 | 45/45 (= DLL exports) | suite 17/17 + SKIP 4/4; 191 consts; shaderc v2026.4 @ b64fd42c | **DONE** (relayed) |
| 6 | glslang | `xiom.glslang` | 61 (57 + 4 resource-limits) | 61 | 61/61 | suite 29/29 incl. GLSL->SPIR-V; C++ surface documented | **DONE** (relayed) |
| 7 | slang | `xiom.slang` | 277 exported + 9 header-only | 277 | 277/277 | suite 20/20 incl. HLSL->SPIR-V | **DONE** (relayed) |
| 8 | DXC | `xiom.dxc` | 128 methods / 27 interfaces | 128 (bridge) | 128/128 + DXIL probe | suite 20/20 | **DONE** (relayed) |
| 9 | SDL2 | `xiom.sdl2` | 844 exported | 844 | 844/844 | suite 16/16 + absent 4/4; SDL2 release-2.32.10 @ 5d249570 | **DONE** (relayed) |
| 10 | SDL3 100% | `xiom.sdl3` | 1,270 exported | 1,270 (additive modules) | 1270/1270 | full-surface suite PASS; existing 59/59 kept green; B-19 fix preserved | **DONE** (relayed) |
| 11 | VMA 100% | `xiom.vma` | 72 top-level vma* | 72 (generated C++ bridge) | 72/72 + RHI probe | suite bound=72/72; existing 5/5 green; vk_mem_alloc v3.3.0 | **DONE** (relayed) |
| 12 | SPIRV-Headers constants | `xiom.spirv-headers` | 2,385 values (74 enum types) | 2,385 | n/a (constants) | suite pass; oracle byte-identical to clone (ad9184e7) | **DONE** (relayed) |

## Relayed batches

- `REL-20261011-2155-bindings` -- xiom.vulkan SDK100 surface (845 cmds +
  5,983 consts + 8,243 meta consts) for batch assembly.
- `REL-20261011-2231-bindings` -- wave-1 batch: spirv-tools, spirv-cross,
  spirv-reflect, glslang, slang, dxc (all six wrap+publish).
- `REL-20261011-2305-bindings` -- wave-2 batch: sdl2, sdl3 full surface,
  vma 100%, spirv-headers, shaderc (wrap+publish) -- **program matrix complete**.
- `REL-20261011-2230-bindings` -- wave-1 compiler finding candidates
  (outbound Int->ptr cast lost across a fn return; `Vec[Str]` temporary element
  + `+` prints the raw pointer).
- `REL-20261011-2140-bindings` -- B-21 (`&mut` of a struct-return temp
  crashes codegen; repro committed).

## Published on v0.64.4 (2026-10-12)

- **Batch 63 (`eco-v0.1.161`, run 38257991947, packages lane)**: `xiom.dxc`
  0.3.0 (`b4376744...`), `xiom.vma` 0.3.0 (`a1cc09e2...`) and `xiom.jolt`
  0.2.0 (`f08d65ca...`) -- vma 0.3.0 = SDK100 slice #11 live; dxc 0.3.0 =
  slice #8 live. Tally: 77 eco releases (`eco-v0.1.86` -> `eco-v0.1.161`).
- **Batch 64 (`eco-v0.1.162`, run 38260596476, packages lane)**: the eight
  first-publish names are LIVE -- `xiom.spirv-tools` 0.1.0 (`24012686...`),
  `xiom.spirv-cross` 0.1.0 (`a08d2d4a...`), `xiom.spirv-reflect` 0.1.0
  (`97f96c62...`), `xiom.glslang` 0.1.0 (`33898cf6...`), `xiom.slang` 0.1.0
  (`0dd5548d...`), `xiom.sdl2` 0.1.0 (`a5bdb037...`), `xiom.shaderc` 0.1.0
  (`9759ab7a...`) -- plus `xiom.sdl3` **0.17.0** (`2f162d32...`; full surface
  1270/1270). All nine x2-verified on v0.64.4 before tagging. Tally: 78 eco
  releases (`eco-v0.1.86` -> `eco-v0.1.162`).
- **Batch 67 (`eco-v0.1.165`)**: `xiom.spirv.headers` 0.1.0 LIVE (ops
  corrected the scope to the dotted name; allowlist 519; run 38294446110,
  live sha256 `a77f364a` @19:01:29Z). With it the **SDK100 wave is
  COMPLETE -- all twelve slices published and live**: the eight new names
  + `xiom.sdl3` 0.17.0 + `xiom.vma` 0.3.0 + `xiom.dxc` 0.3.0 + the
  standing `xiom.vulkan` 0.6.0 + `xiom.jolt` 0.2.0. Tally: 81 eco
  releases (`eco-v0.1.86` -> `eco-v0.1.165`).
- **Batch 66 (`eco-v0.1.164`)**: `xiom.opengl` **0.4.0** live (full
  generated core-4.6 surface; live sha256 `328674f1`) -- the graphics
  drive's OpenGL leg is published.
- **`xiom.vulkan` 0.6.0 LIVE** (`eco-v0.1.163`, live sha256 `a8053f05`;
  owner-approved SDK100 bump): additive full surface (845 cmds + 5,983
  consts + 8,243 struct-meta; loadability 766/766; RHI 22/22 x2). The
  engine adopted it the same day (`probe_rhi_vulkan` + `demo_vk` green;
  scene tier too). Mini-RHI renumbers after it (0.7.0-0.13.0 ladder,
  owner session: `REL-20261012-1800-bindings`).

## Documented exclusions (non-API; full list in the plan + package docs)

- CLI tools (vulkaninfo/vkcube/glslc/spirv-* exes/vkconfig/gfxrecon/dxc/slangc/
  maintenancetool); their libraries are bound by their own packages.
- C++-only sugar (vulkan.hpp and friends, glm, VulkanSafeStruct) and
  loader/ICD internals (vk_icd.h, vk_layer.h, volk.h).
- Vulkan SC-only structs/commands not declared by shipped headers (documented
  with counts in the package manifests).
- Installers/registries/config assets.

## Provenance

Every package carries `PROVENANCE.md` (upstream repo, pinned tag/commit,
license, derived-vs-independent, oracle source). Clone rows live in
`E:\repos\CLEANUP.md` (central). xiom.vulkan's registry is proven
byte-identical to Vulkan-Headers v1.4.350 (`8864cdc`).
