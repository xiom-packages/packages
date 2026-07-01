# axiom:vulkan — Vulkan GPU Bindings

First-party Vulkan FFI bindings for AXIOM. Wraps `vulkan-1.dll` / `libvulkan.so` / `libvulkan.dylib`.

## Install

```powershell
axiom pkg install axiom-vulkan
```

## Requirements

- Vulkan SDK (https://vulkan.lunarg.com/)
- A GPU with Vulkan support

## Example: Triangle

```axiom
use axiom.vulkan;

fn main() -> Int {
  let instance = create_instance("AXIOM App", "AXIOM Engine")?;
  let devices = enumerate_devices(instance)?;
  let device = create_device(devices[0])?;
  
  // Create swapchain, pipeline, render, present...
  
  destroy_device(device);
  destroy_instance(instance);
  return 0;
}
```

## API

See `vulkan.ax` for the full API. Every Vulkan call has a safe AXIOM wrapper with error handling via `Result[T, Str]`.
