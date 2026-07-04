# xiom:vulkan — Vulkan GPU Bindings

First-party Vulkan FFI bindings for XIOM. Wraps `vulkan-1.dll` / `libvulkan.so` / `libvulkan.dylib`.

## Install

```powershell
xiom pkg install xiom-vulkan
```

## Requirements

- Vulkan SDK (https://vulkan.lunarg.com/)
- A GPU with Vulkan support

## Example: Triangle

```xiom
use xiom.vulkan;

fn main() -> Int {
  let instance = create_instance("XIOM App", "XIOM Engine")?;
  let devices = enumerate_devices(instance)?;
  let device = create_device(devices[0])?;
  
  // Create swapchain, pipeline, render, present...
  
  destroy_device(device);
  destroy_instance(instance);
  return 0;
}
```

## API

See `vulkan.xi` for the full API. Every Vulkan call has a safe XIOM wrapper with error handling via `Result[T, Str]`.
