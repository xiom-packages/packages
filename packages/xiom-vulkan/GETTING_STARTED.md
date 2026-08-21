# XIOM Vulkan -- Getting Started

**Version:** v1.0.0  
**Compiler required:** xiom v0.48.0+  
**Tested on:** Windows 11, RTX 3070 Ti, Vulkan SDK 1.4.350.0

## Prerequisites

| Tool | Version | Download |
|------|---------|----------|
| xiom | >= 0.48.0 | `cargo install xiom` or prebuilt in `release/` |
| Vulkan SDK | >= 1.3 | [vulkan.lunarg.com](https://vulkan.lunarg.com) |
| GLFW | 3.4 | [glfw.org](https://glfw.org/download.html) -- prebuilt Windows binaries |
| LLVM/clang | >= 18 | [llvm.org](https://llvm.org) -- for C bridge compilation |
| glslc | bundled with VK SDK | Compiles GLSL shaders to SPIR-V |

### Environment Variables

```powershell
$env:VULKAN_SDK = "C:\VulkanSDK\1.4.350.0"
$env:GLFW_DIR   = "C:\glfw-3.4.bin.WIN64"
```

## Quick Start -- Run a Demo (30 seconds)

```powershell
cd ecosystem\xiom-vulkan
.\build.ps1 -Target demo2d -Run
```

This runs a 4-step pipeline:
1. Compiles GLSL shaders -> SPIR-V
2. Generates C header with embedded SPIR-V arrays
3. Compiles the C bridge (30 Vulkan modules) into xvk_bridge.obj
4. Builds + links the XIOM demo with xiom

The window opens and stays until you close it. GPU: NVIDIA RTX 3070 Ti detected.

## Available Demos

```powershell
.\build.ps1 -Target demo2d -Run       # Color-cycling triangle
.\build.ps1 -Target demo3d -Run       # Spinning 3D cube
.\build.ps1 -Target particles -Run    # GPU particle fountain
.\build.ps1 -Target cubes -Run        # 3x3 spinning cube grid
.\build.ps1 -Target shapes -Run       # Animated quads + triangle
.\build.ps1 -Target vertex_buffer -Run # Vertex/index buffer workflow
.\build.ps1 -Target models -Run       # 20 rotating model instances
.\build.ps1 -Target sprites -Run      # 50 sprite field
.\build.ps1 -Target ui -Run           # UI panel system
.\build.ps1 -Target viewport -Run     # Multi-cube viewport
.\build.ps1 -Target compute -Run      # Offscreen golden-image test
.\build.ps1 -Target test -Run         # CI smoke test
```

## Direct xiom Compilation (No Build Script)

```powershell
# Type-check only:
xiom --diagnostics=json examples/demo_2d.xi vulkan.xi src/wrapper.xi

# Full build + run (requires bridge compiled first):
xiom -o demo_2d.exe examples/demo_2d.xi vulkan.xi src/wrapper.xi `
  --c-source bridge/xvk_bridge.obj `
  --link vulkan-1 --link glfw3 --link gdi32 --link user32 `
  --link kernel32 --link shell32 --link ole32 `
  --link-path $env:VULKAN_SDK\Lib --link-path $env:GLFW_DIR\lib-vc2022 `
  --run
```

## Using the Full Vulkan API from XIOM

### Raw bindings (755 VK functions)

```xiom
// vulkan_extern.xi declares all VK functions -- links directly to vulkan-1.lib
// Compile with: xiom app.xi vulkan_extern.xi vulkan_safe.xi vulkan_structs.xi
use xiom.vulkan.safe;
use xiom.vulkan.structs;

// Build create-info structs with typed builders
let ai = build_application_info("MyApp", "XIOM", 4210688);
let ci = build_instance_create_info(ai, [], []);
free_struct(ai);

// Create instance via safe wrapper
let inst = VulkanInstance.create_from_struct(ci).unwrap();
free_struct(ci);

// Use and destroy
inst.destroy();
```

### Struct builders (30+ create-info types)

```xiom
use xiom.vulkan.structs;

let bci = build_buffer_create_info(4096, VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, 0);
let ici = build_image_create_info(VK_IMAGE_TYPE_2D, VK_FORMAT_R8G8B8A8_UNORM,
    256, 256, 1, 1, 1, VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL,
    VK_IMAGE_USAGE_SAMPLED_BIT, 0, 0, 0, VK_IMAGE_LAYOUT_UNDEFINED);
let sci = build_sampler_create_info(VK_FILTER_LINEAR, VK_FILTER_LINEAR,
    VK_SAMPLER_MIPMAP_MODE_LINEAR, VK_SAMPLER_ADDRESS_MODE_REPEAT, ...);
```

### Direct bridge access (303 C functions)

For maximum control, call the C bridge struct marshalling functions directly:

```xiom
extern "C" {
  fn xvk_alloc(size: Int) -> Int;
  fn xvk_free(handle: Int);
  fn xvk_write_u32(h: Int, off: Int, v: Int32);
  fn xvk_write_u64(h: Int, off: Int, v: Int);
  fn xvk_set_sType(h: Int, v: Int32);
}

let buf = unsafe { xvk_alloc(56) };
unsafe { xvk_set_sType(buf, 12); }     // VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
unsafe { xvk_write_u64(buf, 24, 4096); } // size field
unsafe { xvk_write_u32(buf, 32, 1); }    // usage field
// ... pass to vkCreateBuffer via vulkan_extern.xi
unsafe { xvk_free(buf); }
```

## Architecture

```
XIOM .xi files
  |-- vulkan_extern.xi        755 raw VK function declarations -> vulkan-1.lib
  |-- vulkan_safe.xi          29 resource types + 5 create_from_struct
  |-- vulkan_structs.xi       30+ struct builders (alloc + write at offsets)
  `-- vulkan_constants_all.xi 3691 VK constants

FFI boundary -- int64_t handles

C bridge  (332KB, 30 modules, 318 functions)
  |-- xvk_structs.c           alloc / write_u32 / write_u64 / write_f32 / write_str
  |-- xvk_bind_instance.c     vkCreateInstance / vkEnumeratePhysicalDevices
  |-- xvk_bind_device.c       vkCreateDevice / vkGetDeviceQueue
  |-- xvk_bind_buffer.c       vkCreateBuffer / vkDestroyBuffer
  |-- xvk_bind_image.c        vkCreateImage / vkCreateImageView / vkCreateSampler
  |-- xvk_bind_memory.c       vkAllocateMemory / vkMapMemory
  |-- xvk_bind_pipeline.c     vkCreateShaderModule / vkCreatePipelineLayout
  |-- xvk_bind_descriptor.c   vkCreateDescriptorSetLayout / vkAllocateDescriptorSets
  |-- xvk_bind_command.c      vkAllocateCommandBuffers / all vkCmd* functions
  |-- xvk_bind_sync.c         vkCreateFence / vkCreateSemaphore / vkQueueSubmit
  |-- xvk_bind_query.c        vkCreateQueryPool / vkCmdWriteTimestamp
  |-- xvk_bind_swapchain.c    vkCreateSwapchainKHR / vkQueuePresentKHR
  |-- xvk_bind_extensions.c   mesh shaders / video / debug / VRS / push desc / sync2
  |-- xvk_bind_raytracing.c   KHR + NV ray tracing
  `-- Legacy (17 modules)     xvk_app_create / xvk_draw_triangle_2d / ... (demo API)

Vulkan SDK  (vulkan-1.lib)
  `-- Driver (RTX 3070 Ti)
```
