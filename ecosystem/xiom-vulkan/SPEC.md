# xiom-vulkan Specification

## Overview
First-party Vulkan FFI bindings for XIOM. Wraps `vulkan-1.dll` / `libvulkan.so` / `libvulkan.dylib` to provide safe, contract-enforced GPU graphics and compute access.

## Architecture

### Layers
```
┌─────────────────────────────────────┐
│  src/wrapper.xi  (Safe XIOM types)  │
│  VulkanInstance, VulkanDevice       │
├─────────────────────────────────────┤
│  vulkan.xi       (Raw FFI decls)    │
│  Instance, Device, Pipeline, etc.   │
├─────────────────────────────────────┤
│  vulkan.xiom-bind (C ABI mapping)   │
│  vkCreateInstance, vkDestroyDevice  │
└─────────────────────────────────────┘
```

### Design Decisions
- All handles are opaque `Int` values at the FFI layer; the wrapper layer uses typed structs with handle fields.
- Every FFI call is wrapped in a safe function that validates preconditions via `requires:` contracts.
- Errors propagate as `Result[T, Str]` — the `Str` carries the Vulkan error message when available.

## Lifecycle Safety

### Instance Lifecycle
```
vk_create_instance  (allocates Instance)
    │
    ├─► enumerate_devices
    ├─► get_device_name / get_device_type
    │
    vk_destroy_instance (invalidates all child resources)
```

**Invariant:** A `VulkanInstance` must have `handle != 0` for any operation. After `vk_destroy_instance`, the handle is zeroed.

### Device Lifecycle
```
vk_create_device  (child of Instance)
    │
    ├─► create_swapchain
    ├─► create_pipeline
    ├─► create_command_pool
    ├─► allocate_buffer
    │
    vk_destroy_device (must destroy all child resources first)
```

**Rule:** All child resources (pipelines, buffers, semaphores, etc.) must be destroyed before the parent device.

### Resource Destruction Order (mandatory)
1. Command buffers → command pools
2. Framebuffers
3. Pipelines, shader modules
4. Swapchain, image views
5. Buffers → memory
6. Semaphores, fences
7. Device
8. Instance

## Safety Contracts

All safe wrapper functions enforce:
- `requires: instance.handle != 0` on instance operations
- `requires: device.handle != 0` on device operations
- `requires: physical_device != 0` on physical device queries
- Null-pointer guards at the C ABI boundary
- `VK_SUCCESS` return code checks translated to `Result`

## External Dependencies
- **Runtime:** Vulkan SDK (>= 1.3) — `vulkan-1.dll` / `libvulkan.so` / `libvulkan.dylib`
- **Build:** Vulkan SDK headers for C ABI type definitions
- **Link flags:** `-l vulkan-1`

## API Surface

### Wrapper Layer (`src/wrapper.xi`)
- `VulkanInstance` — typed instance with debug flag
- `VulkanDevice` — typed device with physical device reference
- `vk_create_instance(app_name: Str) -> Result[VulkanInstance, Str]`
- `vk_destroy_instance(instance: VulkanInstance)`

### FFI Layer (`vulkan.xi`)
- Instance/Device: `create_instance`, `destroy_instance`, `create_device`, `destroy_device`
- Swapchain: `create_swapchain`, `acquire_next_image`, `present`
- Pipeline: `create_graphics_pipeline`, `create_render_pass`, `create_framebuffer`
- Shaders: `create_shader_module`, `destroy_shader_module`
- Commands: `create_command_pool`, `allocate_command_buffer`, `begin_/end_` variants
- Synchronization: `create_semaphore`, `create_fence`, `wait_for_fence`
- Memory: `allocate_buffer`, `map_memory`, `unmap_memory`

### Constants
| Name | Value | Meaning |
|------|-------|---------|
| `DEVICE_TYPE_OTHER` | 0 | Unknown device type |
| `DEVICE_TYPE_INTEGRATED` | 1 | Integrated GPU |
| `DEVICE_TYPE_DISCRETE` | 2 | Discrete GPU |
| `DEVICE_TYPE_VIRTUAL` | 3 | Virtual GPU |
| `DEVICE_TYPE_CPU` | 4 | CPU |

## Error Handling Strategy
1. C ABI calls return `i32` (VkResult) — `0` = `VK_SUCCESS`.
2. FFI layer converts to `Result[T, Str]` with error message from Vulkan.
3. Wrapper layer adds contract validation before delegating to FFI.
4. Resource leaks are prevented by requiring destroy calls and documenting the destruction order.
