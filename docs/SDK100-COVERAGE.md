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
| 5 | shaderc | `xiom.shaderc` | (building) | -- | -- | wave-1 agent running | IN FLIGHT |
| 6 | glslang | `xiom.glslang` | 61 (57 + 4 resource-limits) | 61 | 61/61 | suite 29/29 incl. GLSL->SPIR-V; C++ surface documented | **DONE** (relayed) |
| 7 | slang | `xiom.slang` | 277 exported + 9 header-only | 277 | 277/277 | suite 20/20 incl. HLSL->SPIR-V | **DONE** (relayed) |
| 8 | DXC | `xiom.dxc` | 128 methods / 27 interfaces | 128 (bridge) | 128/128 + DXIL probe | suite 20/20 | **DONE** (relayed) |
| 9 | SDL2 | `xiom.sdl2` | (building) | -- | -- | wave-2 agent running | IN FLIGHT |
| 10 | SDL3 100% | `xiom.sdl3` | (building; existing 59/59 suite kept green) | -- | -- | wave-2 agent running | IN FLIGHT |
| 11 | VMA 100% | `xiom.vma` | (building; extends 0.2.0) | -- | -- | wave-2 agent running | IN FLIGHT |
| 12 | SPIRV-Headers constants | `xiom.spirv-headers` | (building) | -- | -- | wave-2 agent running | IN FLIGHT |

## Relayed batches

- `REL-20261011-2155-bindings` -- xiom.vulkan SDK100 surface (845 cmds +
  5,983 consts + 8,243 meta consts) for batch assembly.
- `REL-20261011-2231-bindings` -- wave-1 batch: spirv-tools, spirv-cross,
  spirv-reflect, glslang, slang, dxc (all six wrap+publish).
- `REL-20261011-2230-bindings` -- wave-1 compiler finding candidates
  (outbound Int->ptr cast lost across a fn return; `Vec[Str]` temporary element
  + `+` prints the raw pointer).
- `REL-20261011-2140-bindings` -- B-21 (`&mut` of a struct-return temp
  crashes codegen; repro committed).

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
