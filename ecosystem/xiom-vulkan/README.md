# xiom-vulkan — Vulkan GPU Bindings

First-party Vulkan FFI bindings for XIOM. Provides safe, contract-enforced GPU graphics and compute access.

## Install

```powershell
xiom pkg install xiom-vulkan
```

## Requirements

- **Vulkan SDK >= 1.3** — [lunarg.com](https://vulkan.lunarg.com/)
- GPU with Vulkan driver support
- Windows: `VULKAN_SDK` environment variable set
- Linux: `libvulkan.so` from package manager (`apt install vulkan-sdk`)
- macOS: MoltenVK via Vulkan SDK or `brew install molten-vk`

## Link Flags

```
-l vulkan-1
```

## Quick Start

```xiom
use xiom.vulkan;

fn main() -> Int {
  let instance = vk_create_instance("My XIOM App")?;
  let result = vk_destroy_instance(instance);
  return 0;
}
```

## API Overview

| Module | File | Purpose |
|--------|------|---------|
| `xiom.vulkan` | `vulkan.xi` | Raw FFI declarations |
| `xiom.vulkan.wrapper` | `src/wrapper.xi` | Safe typed wrappers with contracts |

### Wrapper Types

```xiom
pub type VulkanInstance = { handle: Int; debug: Bool; }
pub type VulkanDevice = { handle: Int; physical: Int; }
```

### Resource Destruction Order

1. Command buffers → Command pools
2. Framebuffers
3. Pipelines → Shader modules
4. Swapchain → Image views
5. Buffers → Device memory
6. Semaphores → Fences
7. Device
8. Instance

## Full Triangle Example

```xiom
use xiom.vulkan;

fn main() -> Int {
  let instance = create_instance("XIOM Triangle", "XIOM Engine")?;
  let devices = enumerate_devices(instance)?;

  if devices.len() == 0 {
    print("No Vulkan-capable GPU found\n");
    destroy_instance(instance);
    return 1;
  }

  let gpu = devices[0];
  print("GPU: " + get_device_name(gpu) + "\n");

  let device = create_device(gpu)?;

  wait_device_idle(device);
  destroy_device(device);
  destroy_instance(instance);
  return 0;
}
```

## License

MIT or Apache-2.0, at your option.
