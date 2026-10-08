# SPEC: xiom.vulkan -- Vulkan capability probe via dynamic loader

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.vulkan` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | Vulkan (Khronos); Windows loader `vulkan-1.dll` |
| Upstream license | Apache-2.0 (headers); no headers or code vendored -- the bridge is our code and declares the minimal ABI locally |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (system loader `vulkan-1.dll`, driver-installed in System32) |
| Compiler pin | v0.64.1 |

## 2. G2 pin: soname + header hash + entry-point set

**Soname (runtime contract):** `vulkan-1.dll`. Resolved at runtime via
`LoadLibraryA` + `vkGetInstanceProcAddr`; no SDK, no headers, no link-time
dependency, nothing vendored.

**Header pin** (fetched verbatim from
`https://raw.githubusercontent.com/KhronosGroup/Vulkan-Headers/vulkan-sdk-1.4.350.0/include/vulkan/vulkan_core.h`):

| Header | Bytes | SHA256 |
|--------|-------|--------|
| `vulkan_core.h` (tag `vulkan-sdk-1.4.350.0`) | 1,317,089 | `6D2BA4755774B1D129DA6B8E661268B494D2D609DF6217C6B6485ACF7666B6C2` |

**Resolved entry points** (the ABI this package depends on):
`vkGetInstanceProcAddr` (from the DLL) then, via it:
`vkEnumerateInstanceVersion` (optional, absent on 1.0 loaders),
`vkEnumerateInstanceExtensionProperties`, `vkEnumerateInstanceLayerProperties`,
`vkCreateInstance`; instance-scoped (resolved with the instance handle):
`vkEnumeratePhysicalDevices`, `vkGetPhysicalDeviceProperties`,
`vkDestroyInstance`.

**ABI details pinned:** `VK_STRUCTURE_TYPE_APPLICATION_INFO=0`,
`INSTANCE_CREATE_INFO=1`; requested `apiVersion` = `VK_MAKE_API_VERSION(0,1,0,0)`;
`VkExtensionProperties` = `char name[256] + u32 specVersion`;
`VkLayerProperties` = `char layerName[256] + u32 + u32 + char description[256]`;
`VkPhysicalDeviceProperties` prefix = `apiVersion(0) driverVersion(4) vendorID(8)
deviceID(12) deviceType(16) deviceName(20, 256)` -- received into an oversized
opaque buffer so the full struct write stays in bounds.

**Local runtime sample used for positive-path proof (NOT the pin):**

| Artifact | Value |
|----------|-------|
| System loader | `C:\Windows\System32\vulkan-1.dll`, 1,740,728 bytes, FileVersion 1.4.350.0, SHA256 `0419974F00E82A3D619077BA414DA265A774F8DB9D45AD93BC1843F44B2C2C1F` |
| SDK header copy (reference) | `C:\VulkanSDK\1.4.350.0\Include\vulkan\vulkan_core.h`, 1,343,384 bytes, SHA256 `2F7AA635DB9A068294C70DE0F90D74C869602C132C30F306CB73B973A3F9B502` |
| Runtime report | loader API 1.4.350; 20 instance extensions; 15 layers; device `NVIDIA GeForce RTX 3070 Ti` (type 2 = discrete, api 1.4) |

### Re-pin procedure

1. Pick the new Khronos tag; re-fetch `include/vulkan/vulkan_core.h`,
   recompute the SHA256, update this table and the version rows in
   `README.md`/`AUDIT.md` in one commit.
2. If the entry-point set grows, update `vk_probe.c` + `vulkan.xi` in the same
   commit; missing required entry points fail closed (`VULKAN_LOAD_ABI`).
3. Re-run `scripts/port.ps1 -Package xiom.vulkan` and record the matrix in §4.

## 3. Design

- `src/vk_probe.c` (our code, MIT/Apache) includes **no Vulkan headers**: the
  instance-create structs are declared locally (the bridge is the writer) and
  everything the loader writes back goes into oversized opaque buffers. It
  links nothing but kernel32 and needs no `--link` flags.
- The XIOM module (`vulkan.xi`, module `xiom.vulkan`) is a thin safe wrapper;
  all `unsafe`/`extern` in this package are confined to this single module
  (G5). Public API: `vulkan_probe`, `vulkan_probe_named`,
  `vulkan_has_extension`, `vulkan_has_extension_named`, `VulkanInfo`,
  `VulkanLoadError`, version helpers and constants.
- **Classification**: loader missing -> `VULKAN_LOAD_ABSENT` (SKIP);
  `vkCreateInstance` fails (no ICD/driver) -> `VULKAN_LOAD_NO_DEVICE` (SKIP);
  entry points missing -> `VULKAN_LOAD_ABI` (FAIL). Probes are atomic
  (load -> query -> instance -> device -> unload); a bogus soname exercises
  the SKIP path deterministically on any host.
- **Build:** `port.args.json` compiles the bridge
  (`--c-source ${PACKAGE_DIR}/src/vk_probe.c`).
- The pre-pilot package shipped a ~1.7 MB static-bridge game engine
  (`bridge/xvk_*`, stb headers, shaders, build.ps1/build.sh) that required the
  Vulkan SDK at build time and could not satisfy the SKIP-when-absent gate; it
  is preserved in git history and its scope returns over this loader in
  later phases (`ROADMAP.md`, `AUDIT.md`).

## 4. Test matrix (recorded 2026-10-08, compiler v0.64.1)

| Configuration | Command | Result |
|---------------|---------|--------|
| Vulkan present (System32 loader 1.4.350) | `scripts/port.ps1 -Package xiom.vulkan` | **PASS 10/10 x2** -- version packing, SKIP classification (bogus soname), loader API 1.4.350, 20 instance extensions + head, 15 layers, bogus extension absent, `VK_KHR_surface` present, device (RTX 3070 Ti, type 2, api 1.4) |
| Loader absent (CI shape) | not reproducible on this host (driver-installed loader); the bogus-soname classification runs in every suite invocation | SKIP path exercised + code-reviewed |
| No ICD/driver | not reproducible on this host; instance failure maps to `VULKAN_LOAD_NO_DEVICE` (SKIP) | code-reviewed |

## 5. Scope

Capability probe only: loader identification, instance extensions/layers,
instance creation, physical-device identification. Instance/device creation
with extensions, queues, surfaces/swapchains, and compute/render pipelines
are later phases over the same loader seam (`ROADMAP.md`).
