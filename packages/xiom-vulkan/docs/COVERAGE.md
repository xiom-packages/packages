# xiom.vulkan -- SDK 100% coverage ledger (Vulkan SDK 1.4.350.0)

DoD per docs/checklists/vulkan-sdk-100.md (oracle N == bound N == runtime
resolved N). Oracle: `C:\VulkanSDK\1.4.350.0\share\vulkan\registry\vk.xml`,
byte-identical to the pinned upstream clone
`E:\repos\Vulkan-Headers\registry\vk.xml` @ `v1.4.350` (`8864cdc`), SHA256
`F6F43874297CE094769714DE2FC51EC683C12EED9B7615DA20B34AB4A2F81470`
(see PROVENANCE.md). Generators: `tools/gen_vk.py`, `tools/gen_struct_meta.py`
(+ `tools/find_unavailable_structs.py`, `tools/struct_dump.cpp`).

## Commands -- 845 bound, 0 unexplained unresolved

- Registry: **852** command elements = 845 desktop-Vulkan commands (740 real +
  105 alias) + **7 `vulkansc`-only twins** (excluded at generation; documented
  in `docs/gen_manifest.json`).
- Bound: **845/845** typed loader wrappers in `src/cmds_01..08.xi` (resolution
  via `vkGetInstanceProcAddr` / `vkGetDeviceProcAddr` with an instance
  fallback; device/instance/global classes from the handle parent chain).
- Runtime-resolved on the real loader + RTX 3070 Ti (every loader/driver
  extension enabled): **unresolved_relevant = 0**, i.e. **766/766
  advertised-surface commands resolve**; 62 of the 75 excluded commands are
  absent by loader design; 4 commands belong to extensions this loader does
  not advertise (below).
- Excluded by design (generated from `vk.xml` platform/supported attributes):
  **75** commands (foreign-platform + Vulkan SC-only).
- Unadvertised by this loader (runtime-verified via `xr_ext_present` /
  `xr_dev_ext_present`; they resolve on platforms/drivers that expose them):
  - `vkGetPhysicalDeviceSurfaceCapabilities2EXT` -- `VK_EXT_display_surface_counter`
  - `vkCreateHeadlessSurfaceEXT` -- `VK_EXT_headless_surface`
  - `vkAcquireDrmDisplayEXT`, `vkGetDrmDisplayEXT` -- `VK_EXT_acquire_drm_display`
- Evidence: `tests/test_full_surface.xi` **PASS x2**:
  `commands=845 excluded=75 relevant=770 unresolved_relevant=0 ... resolved=779/845`.

## Constants -- 5,983, full registry harvest

- Sources: enum blocks + feature `<require>` + extension `<require>` (6,050 enum
  elements total), with `bitpos`, `offset+extnumber` (ext-derived values),
  `dir="-"`, string values, and alias chains resolved.
- Emitted: **5,284 int** (`src/consts_1..12.xi`) + **4 float**
  (`consts_float.xi`: LOD_CLAMP_NONE + NV occupancy priorities) + **695 string**
  (`consts_str.xi`: every `VK_*_EXTENSION_NAME`).
- Zero raw/unresolved; 34 Vulkan-SC placeholder conflicts resolved in favour of
  the desktop values (listed in `docs/gen_manifest.json`).

## Struct metadata -- 1,343 sizes + 6,905 member offsets

- Oracle: `tools/struct_dump.cpp` compiled with clang against the SDK headers
  (`sizeof`/`offsetof`; Windows + beta + video codec headers).
- Emitted: **8,243 constants** (`src/struct_meta_1..19.xi`):
  `VK_SIZEOF_*` + `VK_OFF_*_<MEMBER>`.
- Documented gaps: **106 header-unavailable structs** (Vulkan SC core + SC
  pipeline-cache structs; foreign-platform android/fuchsia/metal/ohos/qnx/
  screen/xlib/wayland/xcb/vi/ubm/ggp/directfb surfaces + SciBuf/Zircon/Metal
  handle structs -- not declared by headers available to the Windows C API) and
  **27 bitfield members** (no `offsetof`); lists in
  `docs/struct_meta_manifest.json` and `tools/struct_dump_skips_full.json`.
- Evidence: `tests/test_struct_meta.xi` PASS (all 19 modules compile + known
  64-bit spot checks: AppInfo 48, InstanceCreateInfo 64/flags 16/pApplicationInfo 24,
  PhysicalDeviceProperties 824, ClearColorValue 16, GraphicsPipeline 144).

## Suites

| Suite | Result |
|---|---|
| `tests/test_conformance.xi` (probe + RHI + WSI + triangle + capture/query) | 24/24 via `scripts/port.ps1` |
| `tests/test_full_surface.xi` (845-command loadability) | PASS x2 |
| `tests/test_struct_meta.xi` (metadata compile + spot checks) | PASS |

## Documented non-bindings (no FFI surface)

- CLI tools: `vulkaninfo*`, `vkcube*`, `glslc`, `spirv-*` exes, `vkconfig*`,
  `gfxrecon-*`, `dxc`, `slangc`, `maintenancetool` (their libraries are bound
  by their own packages: shaderc, spirv-tools, spirv-cross, slang, dxc).
- C++-only sugar: `vulkan.hpp` + `vulkan_*.hpp` (same vk.xml surface),
  `vulkan_profiles.hpp`, `VulkanSafeStruct`, `glm`, `volk.h` (loader tech --
  this package's dynamic loader covers the same seam).
- Loader/ICD internals: `vulkan\vk_icd.h`, `vk_layer.h`, `vk_platform.h`.
- Registries/manifests (`share\vulkan\**`), installer/config assets.
