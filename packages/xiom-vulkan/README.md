# xiom.vulkan

Vulkan **capability probe** for XIOM via a dynamic loader: `vulkan_probe()`
resolves `vulkan-1.dll` at runtime (no SDK, no headers, no link-time
dependency) and reports the loader version, instance extensions/layers, and
the first physical device.

> **Status:** `incubating` -- engine RHI (0.4.0): WSI bring-up -- hidden popup Win32 window
> (user32 via port.args), `VkSurfaceKHR`, swapchain (FIFO; B8G8R8A8 preferred; min+1 images),
> image barriers + `vkCmdClearColorImage`, acquire/submit/present with binary semaphores;
> `VK_KHR_swapchain` enabled when available. Native verified on v0.64.3: **18/18 x2** on the
> RTX 3070 Ti (320x240, format=44, images=3, 3 real clear+present cycles); absent/no-driver
> shapes stay green. 0.3.0 (instance/device/queue + real submit) shipped in `eco-v0.1.133`;
> 0.4.0 published in `eco-v0.1.135` (sha256 `41357590...`). **Lane:** bindings
> (`keywords: ["binding"]`).
> (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.vulkan;

fn main() {
  let p = vulkan_probe();
  if !p.is_ok {
    io.println("Vulkan unavailable: " + p.error.message);  // SKIP in CI
    return;
  }
  let info: VulkanInfo = p.value;
  io.println("loader " + to_string(vulkan_api_major(info.api_version))
    + "." + to_string(vulkan_api_minor(info.api_version))
    + " | " + to_string(info.extension_count) + " instance extensions");
  if info.device_count > 0 {
    io.println("device: " + info.device_name);
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Probe | `vulkan_probe`, `vulkan_probe_named(soname)` |
| Extensions | `vulkan_has_extension(name)`, `vulkan_has_extension_named(soname, name)` |
| Types | `VulkanInfo` (api_version, extension_count/head, layer_count, device_*), `VulkanLoadError` (kind/message) |
| Kinds | `VULKAN_LOAD_ABSENT`, `VULKAN_LOAD_NO_DEVICE`, `VULKAN_LOAD_ABI` |
| Helpers | `vulkan_api_major/minor/patch`, `VK_PHYSICAL_DEVICE_TYPE_*`, `VULKAN_SONAME` |

Failure model: loader missing -> SKIP; no compatible driver instance -> SKIP;
missing entry points -> FAIL. A bogus soname exercises the SKIP path
deterministically.

## Build note

`port.args.json` compiles the header-free probe bridge
(`--c-source ${PACKAGE_DIR}/src/vk_probe.c`); no `--link` flags. Direct runs:

```
xiom --run tests/test_conformance.xi --c-source <abs>\src\vk_probe.c
```

## Tests

```
scripts/port.ps1 -Package xiom.vulkan
```

Expected: 10 `[PASS]`, exit 0 (loader 1.4.350: 20 extensions, 15 layers, one
discrete GPU). G2 pin + re-pin: `SPEC.md` §2.
