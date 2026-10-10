# xiom.vulkan

Vulkan **capability probe** for XIOM via a dynamic loader: `vulkan_probe()`
resolves `vulkan-1.dll` at runtime (no SDK, no headers, no link-time
dependency) and reports the loader version, instance extensions/layers, and
the first physical device.

> **Status:** `incubating` -- engine RHI bring-up (0.3.0): instance with
> `VK_KHR_surface` + `VK_KHR_win32_surface`, discrete-preferred device pick,
> graphics queue, command pool/buffer, and a **real `vkQueueSubmit` +
> `vkQueueWaitIdle` round trip**. Native verified on v0.64.3: **15/15 x2** on
> the RTX 3070 Ti (loader 1.4.350); absent/no-driver shapes stay green.
> Published in `eco-v0.1.133` (sha256 `668b143b...`). **Lane:** bindings
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
