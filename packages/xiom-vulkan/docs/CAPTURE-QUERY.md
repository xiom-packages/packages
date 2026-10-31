# Capture copy (C07) + query readback (B05)

Engine ask: `REL-20261031-1423-engine-4` item 2.  The raw 0.6.0 command
surface already binds every command below; this page pins the exact sequence
and the helper that runs it end to end.

## Thin helper (recommended)

`vulkan_triangle_probe(frames)` (and `_named`) now returns the capture/query
fields on `VulkanTriangle`:

| Field | Meaning |
|-------|---------|
| `capture_bytes` | bytes copied for one full frame (`extent_w * extent_h * 4`) |
| `capture_crc` | FNV-1a over the complete readback frame |
| `capture_stable` | every frame's checksum equals the first frame's |
| `query_ok` | timestamp and occlusion results were read back |
| `timestamp_begin` / `timestamp_end` | GPU ticks at `COLOR_ATTACHMENT_OUTPUT` around the draw |
| `timestamp_period_ns` | `VkPhysicalDeviceLimits.timestampPeriod` (ns/tick) |
| `duration_ns` | `(timestamp_end - timestamp_begin) * timestamp_period_ns` |
| `occlusion_samples` | samples that passed the draw |

At 320x240 on the RTX 3070 Ti the suite reports
`capture_bytes=307200`, `capture_stable=true`, `occlusion_samples=24576`,
`timestamp_period_ns=1`, `duration_ns=3072` (2 frames).  A sample checksum is
`335003077`.

## Raw sequence (engine-owned command buffer)

Use the generated command wrappers with an engine-owned `VkApi`:

```xiom
use xiom.vulkan.api;      // vk_api_load_full, VkApi
use xiom.vulkan.cmds_01;  // query/copy commands
```

### 1. Query pools

`VkQueryPoolCreateInfo` is 32 bytes in the pinned 1.4.350 win64 ABI:

| Offset | Field | Value |
|--------|-------|-------|
| 0 | `sType` | 11 (`VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO`) |
| 8 | `pNext` | 0 |
| 16 | `flags` | 0 |
| 20 | `queryType` | 2 (`TIMESTAMP`) or 0 (`OCCLUSION`) |
| 24 | `queryCount` | 2 for timestamps, 1 for occlusion |
| 28 | `pipelineStatistics` | 0 |

Create timestamp and occlusion pools with
`vk_create_query_pool(&api, device, info_slot, null, &pool_slot)`.
The device needs `timestampValidBits > 0` for the graphics queue family
(`VkQueueFamilyProperties` offset 8; the helper records the bit count).

### 2. Record

Outside the render pass, reset both pools:

```xiom
vk_cmd_reset_query_pool(&api, cmd, ts_pool, 0, 2);
vk_cmd_reset_query_pool(&api, cmd, occ_pool, 0, 1);
```

Inside the render pass, around the draw:

```xiom
// VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT = 0x400
vk_cmd_write_timestamp(&api, cmd, 0x400, ts_pool, 0);
vk_cmd_begin_query(&api, cmd, occ_pool, 0, 0);
// ... engine draws ...
vk_cmd_end_query(&api, cmd, occ_pool, 0);
vk_cmd_write_timestamp(&api, cmd, 0x400, ts_pool, 1);
```

### 3. Stable capture copy (C07)

After the draw, transition the color image and copy the whole frame:

1. Pipeline barrier: `COLOR_ATTACHMENT_WRITE` (0x100) ->
   `TRANSFER_READ` (0x800), stage `COLOR_ATTACHMENT_OUTPUT` (0x400) ->
   `TRANSFER` (0x1000), layout `TRANSFER_SRC_OPTIMAL` (6) -> 6.
2. `vk_cmd_copy_image_to_buffer(&api, cmd, image, 6, readback_buffer, 1,
   region_slot)` where the 56-byte `VkBufferImageCopy` is:

| Offset | Field | Value |
|--------|-------|-------|
| 0 | `bufferOffset` | 0 |
| 8 | `bufferRowLength` | 0 (tightly packed) |
| 12 | `bufferImageHeight` | 0 |
| 16 | `imageSubresource.aspectMask` | 1 (`COLOR`) |
| 20 | `imageSubresource.mipLevel` | 0 |
| 24 | `imageSubresource.baseArrayLayer` | 0 |
| 28 | `imageSubresource.layerCount` | 1 |
| 32 | `imageOffset` (x,y,z) | 0,0,0 |
| 44 | `imageExtent` (w,h,d) | swapchain extent, 1 |

3. Barrier `TRANSFER_WRITE` (0x1000) -> bottom, layout 6 ->
   `PRESENT_SRC_KHR` (1000001002).

The readback buffer must be `HOST_VISIBLE | HOST_COHERENT` with usage
`TRANSFER_DST` (2).  The helper uses one buffer of
`extent_w * extent_h * 4` bytes and hashes the full mapping.

### 4. Read back (B05)

After submit + `vkQueueWaitIdle`:

```xiom
// VK_QUERY_RESULT_64_BIT(1) | VK_QUERY_RESULT_WAIT(2) = 3
vk_get_query_pool_results(&api, device, ts_pool, 0, 2, 16, ts_slot, 8, 3);
vk_get_query_pool_results(&api, device, occ_pool, 0, 1, 8, occ_slot, 8, 3);
```

`VkPhysicalDeviceProperties.limits` starts at offset 292; `timestampPeriod`
is at `limits + 424` = **716** in the pinned win64 struct (a u32, ns/tick).
Then:

- per-pass duration: `(ts[1] - ts[0]) * timestampPeriod` ns;
- copy bandwidth: `capture_bytes / (duration_ns / 1e9)` bytes/s;
- occlusion/draw samples: the occlusion result.

All offsets above come from `src/struct_meta_*.xi` (`VK_OFF_*`) and the
pinned 1.4.350 header; re-run `tools/gen_vk.py` / the struct dump on a new
pin before changing them.
