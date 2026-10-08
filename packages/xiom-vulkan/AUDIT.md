# AUDIT: xiom.vulkan

## Status (2026-10-08)

Capability-probe implementation at 0.2.0 (same version number as the pre-pilot
manifest; the pre-pilot *content* was replaced).

| Item | State |
|------|-------|
| Compiler | xiom v0.64.1 |
| Pin | soname `vulkan-1.dll` + tag `vulkan-sdk-1.4.350.0` `vulkan_core.h` hash + entry-point set (`SPEC.md` §2) |
| Link model | none at build time; runtime `LoadLibraryA` + `vkGetInstanceProcAddr`; **no Vulkan headers included** (minimal ABI declared locally, opaque receive buffers) |
| Build | `port.args.json`: `--c-source ${PACKAGE_DIR}/src/vk_probe.c` (no `--link`) |
| FFI confinement | all `unsafe`/`extern` in the root module `xiom.vulkan` (G5); the bridge is plain C with no XIOM unsafe |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 10/10 x2** via `scripts/port.ps1`: loader 1.4.350, 20 instance extensions, 15 layers, device RTX 3070 Ti (discrete, api 1.4); deterministic SKIP classification per run |

## Pre-pilot removal (preserved in git history)

The pre-pilot package carried a ~1.7 MB static-bridge game engine:
`bridge/xvk_*` (instance, swapchain, pipeline, renderpass, command, descriptors,
memory allocator, raytracing, textures, fonts, offscreen, shaders, stb_image,
stb_truetype), `build.ps1`/`build.sh`/`run.ps1`, `vulkan_extern.xi`,
`src/vulkan_safe.xi` / `vulkan_structs.xi` / `vulkan_constants_all.xi`,
examples and the old audit/handoff docs. It required the Vulkan SDK at build
time (link-time `vulkan-1.lib`) and could not satisfy the SKIP-when-absent
gate; it is preserved in git history as reference and its scope returns over
this loader in later phases.

## Design notes

- Header-free bridge: the minimal instance-create ABI is declared locally;
  `vkGetInstanceProcAddr` provides all instance-level entry points (global
  functions resolved with NULL, instance functions with the instance handle --
  the first present-path run surfaced the NULL-dispatch mistake as
  `device_count == 0`).
- `VK_INCOMPLETE`(5) from enumeration with a capacity smaller than the count
  is treated as success (the second present-path bug: head list came back
  empty until fixed).
- Out-of-scope by design: no instance extensions/layers are enabled, no
  surface/swapchain, no queues -- this package identifies capability only.

## Known limitations

- Windows loader name only (`vulkan-1.dll`).
- Instance creation requests API 1.0 for maximum compatibility; device
  apiVersion is reported from `VkPhysicalDeviceProperties`.
- The no-ICD SKIP path is code-reviewed, not force-tested (this host has a
  driver); the bogus-soname SKIP classification runs in every suite run.
