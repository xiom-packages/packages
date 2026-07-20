# xiom-vulkan — Production Roadmap

**Status**: NOT production-ready. 6 CRITICAL, 14 HIGH findings from systematic audit.
**Compiler**: xiomc v0.48.9 (783/783 tests)
**Audit date**: 2026-07-20

---

## PHASE 1: CRITICAL — Must Fix Before Any Production Use

### 1.1 Unchecked Vulkan Bind Operations (10+ sites)
**Severity**: CRITICAL | **Files**: `xvk_swapchain.c`, `xvk_buffer.c`, `xvk_offscreen.c`, `xvk_legacy.c`, `xvk_mesh.c`, `xvk_memory_alloc.c`

`vkBindImageMemory` and `vkBindBufferMemory` return values are never checked. If binding fails, the image/buffer enters an invalid state. Subsequent use causes undefined behavior.

| File | Line | Function |
|------|------|----------|
| `xvk_swapchain.c` | 153 | `vkBindImageMemory` (depth) |
| `xvk_buffer.c` | 43 | `vkBindBufferMemory` |
| `xvk_buffer.c` | 161 | `vkBindImageMemory` |
| `xvk_offscreen.c` | 39 | `vkBindImageMemory` |
| `xvk_offscreen.c` | 232 | `vkBindBufferMemory` |
| `xvk_legacy.c` | 176 | `vkBindBufferMemory` (particles) |
| `xvk_mesh.c` | 137 | `vkBindBufferMemory` (VBO) |
| `xvk_mesh.c` | 154 | `vkBindBufferMemory` (IBO) |
| `xvk_memory_alloc.c` | 179,231 | `vkBindBufferMemory`, `vkBindImageMemory` |

**Fix**: Wrap every call with result check + cleanup on failure:
```c
if (vkBindImageMemory(dev, image, memory, 0) != VK_SUCCESS) {
    vkDestroyImage(dev, image, NULL);
    vkFreeMemory(dev, memory, NULL);
    return VK_NULL_HANDLE;
}
```

### 1.2 Unchecked vkMapMemory (6 sites)
**Severity**: CRITICAL | **Files**: `xvk_offscreen.c`, `xvk_legacy.c`, `xvk_memory_alloc.c`, `xvk_mesh.c`

If `vkMapMemory` fails, `mapped_ptr` stays NULL. All subsequent reads/writes through the pointer crash.

**Fix**: Check `VkResult` and return error on failure.

### 1.3 Swapchain Recreation Failure: cmd_buffers Nullified
**Severity**: CRITICAL | **File**: `xvk_swapchain.c:recreate_swapchain`

When `create_depth_resources` or `create_framebuffers` fails inside `recreate_swapchain`, `cleanup_swapchain` frees `a->cmd_buffers` and sets it to NULL. The old command buffers are NOT saved. When the function restores old state, `cmd_buffers` remains NULL → **all subsequent frames dereference NULL**.

**Fix**: Save old `cmd_buffers`, restore on failure path.

### 1.4 Offscreen Render Target: Resource Leaks on Allocation Failure
**Severity**: CRITICAL | **File**: `xvk_offscreen.c:create_offscreen_rendertarget`

VkImage created at L24. If memory type find, allocation, or image view creation fails at L31/38/52, the VkImage (and partially allocated memory) leaks.

**Fix**: Add `goto fail` labels with proper cleanup in reverse creation order.

### 1.5 Global State Prevents Multi-Instance/Thread Use
**Severity**: CRITICAL | **Files**: `xvk_util.c`, `xvk_camera.c`, `xvk_bind_swapchain.c`, `xvk_bind_extensions.c`, `xvk_bind_raytracing.c`, `xvk_memory_alloc.c`

| File | Global State | Impact |
|------|-------------|--------|
| `xvk_util.c` | `char g_xvk_error[512]` | Error messages race between threads |
| `xvk_camera.c` | `g_eye`, `g_target`, `g_up`, `g_fov`, `g_aspect`, `g_active` | Multi-viewport impossible |
| `xvk_bind_swapchain.c` | `static VkInstance` | Single instance only |
| `xvk_bind_extensions.c` | `static VkInstance`, `static VkDevice`, static proc tables | Single device only |
| `xvk_bind_raytracing.c` | `g_xvk_rt_procs[8]` | Single RT pipeline |
| `xvk_memory_alloc.c` | `static XvkMaState g_ma` | Single allocator |

**Fix**: Thread-local error buffer (`_Thread_local`). Context struct for camera + allocator.

### 1.6 Memory Allocator: Use-After-Free on Bind Failure
**Severity**: CRITICAL | **File**: `xvk_memory_alloc.c:L179-188`

After `vkBindBufferMemory` fails, the buffer is destroyed but `out_buf_h` is never written → caller receives stale/dangling handle.

**Fix**: Set `out_buf_h` to 0 on error, or destroy buffer and return error without writing.

---

## PHASE 2: HIGH — Production Blockers

### 2.1 vkMapMemory Results Not Checked (6 sites)
(Same as 1.2 — promoted to CRITICAL)

### 2.2 vkQueueSubmit Failure Silently Ignored
**File**: `xvk_frame.c:L119`

After submit failure, code continues to `vkQueuePresentKHR`. Semaphore chain broken.

**Fix**: Return early on submit failure.

### 2.3 framebuffers Accessed Without NULL Guard
**Files**: `xvk_frame.c:L72`, `xvk_command.c:L140`

`a->framebuffers[img_idx]` dereferenced without null check. Crashes if framebuffers allocation failed.

**Fix**: Add `if (!a->framebuffers) return -1;` before access.

### 2.4 offs_mapped Dereferenced Without Guard in Hash Path
**File**: `xvk_offscreen.c:L380`

`xvk_offscreen_hash` dereferences `a->offs_mapped` without the null check present in `xvk_offscreen_pixel`.

**Fix**: Add `if (!a->offs_mapped) return 0;` before dereference.

### 2.5 Global Camera State (Not Thread-Safe)
(Already in 1.5 — move to XvkApp struct)

### 2.6 Validation Ring Buffer: No Synchronization
**File**: `xvk_bind_extensions.c:L909-954`

Debug messenger callback writes to ring buffer from arbitrary Vulkan threads; application reads from it. No mutex/lock.

**Fix**: Use atomic operations on head/count, or wrap with mutex.

### 2.7 Descriptor Set Updated Every Frame (Wasteful)
**File**: `xvk_legacy.c:L270-283`

`xvk_draw_texture_quad` updates `texquad_ds` descriptor set every frame. Should be a one-time write at texture creation.

**Fix**: Move descriptor write to texture initialization path.

### 2.8 create_swapchain: Partial Failure Relies on Caller Cleanup
**File**: `xvk_swapchain.c:L240-276`

If image view creation fails partway, partial `swapchain_image_views` exist. Function returns 0 expecting caller to call `cleanup_swapchain`. Fragile contract.

**Fix**: Add internal cleanup on failure path.

### 2.9 Queue Handles Assigned Without Validation
**File**: `xvk_app.c:L200-201`, `xvk_offscreen.c:L142-143`

`vkGetDeviceQueue` result assigned without verifying queue family index is valid.

**Fix**: Verify queue family exists and index is within `queueCount`.

---

## PHASE 3: MEDIUM — Quality Improvements

### 3.1 vkEnumerate* Return Values Unchecked
**Files**: `xvk_instance.c`, `xvk_swapchain.c` — 7+ enumeration calls without error handling.

### 3.2 vkWaitForFences Result Not Checked in Offscreen Path
**File**: `xvk_offscreen.c:L259-262`

### 3.3 Swapchain Image Count Mismatch Possible
**File**: `xvk_swapchain.c:L238-246` — second `vkGetSwapchainImagesKHR` may return different count.

### 3.4 Memory Allocator: ma_destroy() Never Called
**File**: `xvk_memory_alloc.c:L289-303` — exists but never invoked.

### 3.5 DPI: Missing GLFW_SCALE_TO_MONITOR Hint
**File**: `xvk_app.c:L170` — window size in screen coords, framebuffer size in physical pixels. On HiDPI displays these diverge.

---

## PHASE 4: LOW — Polish

### 4.1 Empty Dynamic State Struct Passed
**File**: `xvk_pipeline.c:L428-429` — `VkPipelineDynamicStateCreateInfo` with zero dynamic states.

### 4.2 vkBegin/EndCommandBuffer Not Checked in Texture Path
**File**: `xvk_texture.c:L308,342,355`

### 4.3 Render Pass Destroyed Before Framebuffers
**File**: `xvk_app.c:L93-97` — technically wrong order, harmless with `vkDeviceWaitIdle`.

### 4.4 No Content Scale Callback Registered
Missing `glfwSetWindowContentScaleCallback` — DPI changes detected only on next `begin_frame`.

### 4.5 Redundant Shader Module Destruction
**File**: `xvk_pipeline.c` — duplicate destroy in fail path.

---

## Fix Priority Summary

```
P0 (blocking): 1.1 Bind checks, 1.2 MapMemory checks, 1.3 cmd_buffers restore, 1.4 offscreen leak
P1 (stability): 2.2 QueueSubmit, 2.3 framebuffers NULL guard, 2.4 offs_mapped guard
P2 (correctness): 1.5/2.5 Thread safety/global state, 2.6 validation ring buffer, 2.8 swapchain cleanup
P3 (quality): 3.1 enumeration checks, 3.2 fence checks, 3.3 image count, 3.4 allocator destroy
P4 (polish): 4.1 dynamic state, 4.2 texture checks, 4.3 render pass order, 4.4 content scale, 4.5 shader cleanup
```
