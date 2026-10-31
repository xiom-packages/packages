// XIOM -- xiom.vulkan: Vulkan capability probe via dynamic loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader + capability probe (same pattern as xiom.opengl).
// The package does NOT link Vulkan at build time and requires no SDK headers:
// `src/vk_probe.c` declares the minimal instance-create ABI locally, resolves
// `vulkan-1.dll` at runtime (LoadLibraryA + vkGetInstanceProcAddr), and
// reports loader/instance/device capabilities. All XIOM `unsafe`/`extern`
// live in this single module (G5).
//
// Classification (the suite maps it to markers):
//   VULKAN_LOAD_ABSENT   -> backend missing -> SKIP (CI stays green)
//   VULKAN_LOAD_NO_DEVICE -> vkCreateInstance failed (no ICD/driver) -> SKIP
//   VULKAN_LOAD_ABI      -> loader present but entry points missing -> FAIL
//
// Coverage: loader API version, instance extension count/scan, layer count,
// minimal instance creation, physical-device count + first device
// name/type/apiVersion; RHI bring-up (instance + device + queue + submit);
// WSI (hidden window + surface + swapchain + clear/present round trips);
// render pipeline (embedded SPIR-V + render pass + 3-vertex draw + readback +
// present).  See ROADMAP.md for the remaining engine surface.
//
// G2 pin (SPEC.md): soname `vulkan-1.dll` + Vulkan-Headers tag
// `vulkan-sdk-1.4.350.0` `vulkan_core.h` hash + the resolved entry-point set.

module xiom.vulkan

extern "C" {
  fn xvk_load_named(soname: *UInt8) -> Int32;
  fn xvk_load() -> Int32;
  fn xvk_error() -> *UInt8;
  fn xvk_api_version() -> UInt32;
  fn xvk_extension_count() -> Int32;
  fn xvk_extension_head() -> *UInt8;
  fn xvk_has_extension(name: *UInt8) -> Int32;
  fn xvk_layer_count() -> Int32;
  fn xvk_instance_probe() -> Int32;
  fn xvk_device_count() -> Int32;
  fn xvk_device_name() -> *UInt8;
  fn xvk_device_type() -> Int32;
  fn xvk_device_api_version() -> UInt32;
  fn xvk_unload();
  // Engine RHI bring-up bridge (src/vk_rhi.c).
  fn xr_load(soname: *UInt8) -> Int32;
  fn xr_instance() -> Int32;
  fn xr_pick_device() -> Int32;
  fn xr_device_count() -> Int32;
  fn xr_device_name() -> *UInt8;
  fn xr_device_type() -> Int32;
  fn xr_device_api() -> UInt32;
  fn xr_surface_extensions() -> Int32;
  fn xr_queue_family() -> Int32;
  fn xr_create_device() -> Int32;
  fn xr_submit_probe() -> Int32;
  fn xr_error() -> *UInt8;
  fn xr_destroy();
  fn xr_unload();
  // WSI bridge (src/vk_rhi.c, build order #2).
  fn xw_window_create() -> Int32;
  fn xw_surface() -> Int32;
  fn xw_swapchain() -> Int32;
  fn xw_frames(n: Int32) -> Int32;
  fn xw_clear_present(r: Float32, g: Float32, b: Float32) -> Int32;
  fn xw_extent_w() -> UInt32;
  fn xw_extent_h() -> UInt32;
  fn xw_format() -> UInt32;
  fn xw_present_mode() -> UInt32;
  fn xw_image_count() -> Int32;
  fn xw_frames_done() -> Int32;
  fn xw_destroy();
  // Render pipeline bridge (src/vk_rhi.c, build order #3).
  fn xw_pipeline() -> Int32;
  fn xw_draw_triangle(r: Float32, g: Float32, b: Float32) -> Int32;
  fn xw_center_pixel() -> UInt32;
  fn xw_corner_pixel() -> UInt32;
  fn xw_tri_drawn() -> Int32;
  // 0.6.0 capture/query readback (C07/B05).
  fn xw_capture_crc() -> UInt32;
  fn xw_capture_bytes() -> UInt32;
  fn xw_capture_stable() -> Int32;
  fn xw_query_ok() -> Int32;
  fn xw_ts_begin() -> UInt64;
  fn xw_ts_end() -> UInt64;
  fn xw_ts_period_ns() -> UInt32;
  fn xw_occlusion_samples() -> UInt64;
  // 0.7.0 mini-RHI indirect tier (2012-engine-2).
  fn xw_enable_indirect() -> Int32;
  fn xw_indirect_ok() -> UInt32;
  fn xw_indirect_frames() -> UInt32;
  // 0.7.0 per-frame sync + external surface tier (2015-engine #1/#6/#7).
  fn xw_frame_sync_probe(frames: Int32) -> Int32;
  fn xw_frame_sync_ok() -> Int32;
  fn xw_frame_sync_frames() -> Int32;
  fn xw_test_window_create(w: UInt32, h: UInt32) -> UInt64;
  fn xw_test_window_resize(hwnd: UInt64, w: UInt32, h: UInt32);
  fn xw_test_window_destroy(hwnd: UInt64);
  fn xw_window_from_hwnd(hwnd: UInt64, w: UInt32, h: UInt32) -> Int32;
  fn xw_set_present_mode(mode: UInt32);
  fn xw_recreate_swapchain(w: UInt32, h: UInt32) -> Int32;
  // 0.7.0 mini-RHI buffer tier (2015-engine #2).
  fn xw_buffer_probe() -> Int32;
  fn xw_buffer_ok() -> UInt32;
  fn xw_buffer_bytes() -> UInt32;
  fn xw_buffer_checksum() -> UInt32;
  // 0.7.0 mini-RHI debug labels tier (2012-engine-2).
  fn xw_labels_probe() -> Int32;
  fn xw_labels_available() -> UInt32;
  fn xw_labels_used() -> UInt32;
  // 0.7.0 mini-RHI compute tier (2012-engine-2).
  fn xw_compute_probe() -> Int32;
  fn xw_compute_ok() -> UInt32;
  fn xw_compute_checksum() -> UInt32;
  fn xw_compute_first() -> UInt32;
  fn xw_compute_last() -> UInt32;
  fn xw_compute_expected() -> UInt32;
  // SDK100 full-surface seam (src/vk_rhi.c): raw handles for the generated loader.
  fn xr_instance_handle() -> *UInt8;
  fn xr_device_handle() -> *UInt8;
  fn xr_instance_all_ext() -> Int32;
  fn xr_create_device_all_ext() -> Int32;
  fn xr_ext_present(name: *UInt8) -> Int32;
  fn xr_dev_ext_present(name: *UInt8) -> Int32;
}

// =========================================================================
// Identity, kinds, API-version helpers
// =========================================================================

pub const VULKAN_SONAME: Str = "vulkan-1.dll";

pub const VULKAN_LOAD_ABSENT: Int = 0;    // loader missing -> SKIP
pub const VULKAN_LOAD_NO_DEVICE: Int = 1; // no ICD/driver instance -> SKIP
pub const VULKAN_LOAD_ABI: Int = 2;       // entry points missing -> FAIL

// VkPhysicalDeviceType values.
pub const VK_PHYSICAL_DEVICE_TYPE_OTHER: Int = 0;
pub const VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU: Int = 1;
pub const VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU: Int = 2;
pub const VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU: Int = 3;
pub const VK_PHYSICAL_DEVICE_TYPE_CPU: Int = 4;

pub type VulkanLoadError = {
  kind: Int;
  message: Str;
}

pub type VulkanInfo = {
  api_version: Int;
  extension_count: Int;
  extension_head: Str;
  layer_count: Int;
  device_count: Int;
  device_name: Str;
  device_type: Int;
  device_api_version: Int;
}

/// VK_MAKE_API_VERSION packing helpers (major 7 bits, minor 10, patch 12).
/// Complexity: O(1).
pub fn vulkan_api_major(v: Int) -> Int
  requires: v >= 0
{
  return (v / 4194304) % 128;
}

pub fn vulkan_api_minor(v: Int) -> Int
  requires: v >= 0
{
  return (v / 4096) % 1024;
}

pub fn vulkan_api_patch(v: Int) -> Int
  requires: v >= 0
{
  return v % 4096;
}

// =========================================================================
// Probe API (atomic: load -> query -> unload)
// =========================================================================

/// Probe an explicitly named Vulkan loader.  A bogus soname exercises the
/// ABSENT/SKIP classification deterministically on any host.
/// Complexity: O(load + instance + device enumeration).
pub fn vulkan_probe_named(soname: Str) -> Result[VulkanInfo, VulkanLoadError]
  requires: soname.len() > 0
{
  let rc = unsafe { xvk_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xvk_error()) };
    if rc == 1 {
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABSENT; message: msg });
    }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }

  let api = unsafe { xvk_api_version() as Int };
  let ext_count = unsafe { xvk_extension_count() as Int };
  let ext_head = unsafe { Str::from_c_str(xvk_extension_head()) };
  let layer_count = unsafe { xvk_layer_count() as Int };

  let probe = unsafe { xvk_instance_probe() as Int };
  if probe != 0 {
    let msg = unsafe { Str::from_c_str(xvk_error()) };
    unsafe { xvk_unload(); }
    if probe == 2 {
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
    }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }

  let devices = unsafe { xvk_device_count() as Int };
  let dname = unsafe { Str::from_c_str(xvk_device_name()) };
  let dtype = unsafe { xvk_device_type() as Int };
  let dapi = unsafe { xvk_device_api_version() as Int };
  unsafe { xvk_unload(); }

  return Ok(VulkanInfo{
    api_version: api,
    extension_count: ext_count,
    extension_head: ext_head,
    layer_count: layer_count,
    device_count: devices,
    device_name: dname,
    device_type: dtype,
    device_api_version: dapi,
  });
}

/// Probe the default loader (`vulkan-1.dll`).
/// Complexity: O(load + instance + device enumeration).
pub fn vulkan_probe() -> Result[VulkanInfo, VulkanLoadError]
  requires: true
{
  return vulkan_probe_named(VULKAN_SONAME);
}

/// True when the named **instance** extension is present (exact match).
/// Complexity: O(load + extension scan).
pub fn vulkan_has_extension_named(soname: Str, name: Str) -> Result[Bool, VulkanLoadError]
  requires: soname.len() > 0
  requires: name.len() > 0
{
  let rc = unsafe { xvk_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xvk_error()) };
    if rc == 1 {
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABSENT; message: msg });
    }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let r = unsafe { xvk_has_extension(name.c_str()) as Int };
  if r < 0 {
    let msg = unsafe { Str::from_c_str(xvk_error()) };
    unsafe { xvk_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  unsafe { xvk_unload(); }
  if r == 1 {
    return Ok(true);
  }
  return Ok(false);
}

/// Default-loader instance-extension check.
/// Complexity: O(load + extension scan).
pub fn vulkan_has_extension(name: Str) -> Result[Bool, VulkanLoadError]
  requires: name.len() > 0
{
  return vulkan_has_extension_named(VULKAN_SONAME, name);
}

// =========================================================================
// Engine RHI bring-up (build order #1; headless-safe)
// =========================================================================

pub type VulkanRhi = {
  device_count: Int;
  device_name: Str;
  device_type: Int;
  device_api: Int;
  surface_extensions: Bool;
  queue_family: Int;
}

/// RHI bring-up: instance (VK_KHR_surface + VK_KHR_win32_surface enabled
/// when the loader has them) -> physical-device pick (discrete preferred) ->
/// graphics queue family -> logical device + queue -> command pool +
/// command buffer begin/end + queue submit + wait.  Everything crosses the
/// XIOM boundary as scalars (no out-param slots; findings B-11/B-12), and
/// the whole sequence is headless-safe (no window/surface needed).
/// Cleanup always runs before returning.  Complexity: O(load+device+submit).
pub fn vulkan_rhi_probe_named(soname: Str) -> Result[VulkanRhi, VulkanLoadError]
  requires: soname.len() > 0
{
  let rc = unsafe { xr_load(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    if rc == 1 {
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABSENT; message: msg });
    }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let ir = unsafe { xr_instance() as Int };
  if ir != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let pr = unsafe { xr_pick_device() as Int };
  if pr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let dr = unsafe { xr_create_device() as Int };
  if dr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let sr = unsafe { xr_submit_probe() as Int };
  if sr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let dc = unsafe { xr_device_count() as Int };
  let dn = unsafe { Str::from_c_str(xr_device_name()) };
  let dt = unsafe { xr_device_type() as Int };
  let da = unsafe { xr_device_api() as Int };
  let sx = unsafe { xr_surface_extensions() as Int } != 0;
  let qf = unsafe { xr_queue_family() as Int };
  unsafe { xr_destroy(); xr_unload(); }
  return Ok(VulkanRhi{
    device_count: dc;
    device_name: dn;
    device_type: dt;
    device_api: da;
    surface_extensions: sx;
    queue_family: qf;
  });
}

/// RHI bring-up on the default loader.
/// Complexity: O(load+device+submit).
pub fn vulkan_rhi_probe() -> Result[VulkanRhi, VulkanLoadError]
  requires: true
{
  return vulkan_rhi_probe_named(VULKAN_SONAME);
}

// =========================================================================
// WSI (build order #2): window -> surface -> swapchain -> clear/present
// =========================================================================

pub type VulkanWsi = {
  device_name: Str;
  extent_w: Int;
  extent_h: Int;
  format: Int;
  present_mode: Int;
  image_count: Int;
  frames_presented: Int;
}

/// WSI round trip: hidden Win32 window -> `VkSurfaceKHR` -> swapchain
/// (FIFO, B8G8R8A8 when offered) -> `frames` acquire/clear/present cycles.
/// Headless-safe: the window is never shown; cleanup always runs.  All
/// structs live in the C bridge (scalar-only boundary).
/// Complexity: O(load+device+swapchain+frames).
pub fn vulkan_wsi_probe_named(soname: Str, frames: Int) -> Result[VulkanWsi, VulkanLoadError]
  requires: soname.len() > 0
  requires: frames > 0
{
  let rc = unsafe { xr_load(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    if rc == 1 {
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABSENT; message: msg });
    }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let ir = unsafe { xr_instance() as Int };
  if ir != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let pr = unsafe { xr_pick_device() as Int };
  if pr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let dr = unsafe { xr_create_device() as Int };
  if dr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let spr = unsafe { xr_submit_probe() as Int };
  if spr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let wr = unsafe { xw_window_create() as Int };
  if wr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let su = unsafe { xw_surface() as Int };
  if su != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let sw = unsafe { xw_swapchain() as Int };
  if sw != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let fr = unsafe { xw_frames(frames as Int32) as Int };
  if fr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let dn = unsafe { Str::from_c_str(xr_device_name()) };
  let ew = unsafe { xw_extent_w() as Int };
  let eh = unsafe { xw_extent_h() as Int };
  let fm = unsafe { xw_format() as Int };
  let pm = unsafe { xw_present_mode() as Int };
  let ic = unsafe { xw_image_count() as Int };
  let fd = unsafe { xw_frames_done() as Int };
  unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
  return Ok(VulkanWsi{
    device_name: dn;
    extent_w: ew;
    extent_h: eh;
    format: fm;
    present_mode: pm;
    image_count: ic;
    frames_presented: fd;
  });
}

/// WSI round trip on the default loader.
/// Complexity: O(load+device+swapchain+frames).
pub fn vulkan_wsi_probe(frames: Int) -> Result[VulkanWsi, VulkanLoadError]
  requires: frames > 0
{
  return vulkan_wsi_probe_named(VULKAN_SONAME, frames);
}

// =========================================================================
// Render pipeline (build order #3): SPIR-V + render pass + draw + present
// =========================================================================

pub type VulkanTriangle = {
  device_name: Str;
  extent_w: Int;
  extent_h: Int;
  format: Int;
  center_pixel: Int;   // packed r<<16 | g<<8 | b, read back from the frame
  corner_pixel: Int;   // outside the triangle (clear color)
  frames: Int;
  // 0.6.0 C07 stable capture-copy evidence.
  capture_bytes: Int;  // full frame bytes copied (extent_w * extent_h * 4)
  capture_crc: Int;    // FNV-1a over the full readback frame
  capture_stable: Bool; // every frame's checksum matched the first
  // 0.6.0 B05 query readback (engine frame debugger).
  query_ok: Bool;      // both timestamp and occlusion results read back
  timestamp_begin: Int; // GPU ticks at COLOR_ATTACHMENT_OUTPUT before the draw
  timestamp_end: Int;   // GPU ticks at COLOR_ATTACHMENT_OUTPUT after the draw
  timestamp_period_ns: Int; // VkPhysicalDeviceLimits.timestampPeriod
  duration_ns: Int;     // (end - begin) * period; 0 when query_ok=false
  occlusion_samples: Int; // samples that passed the draw
}

/// Render round trip: hidden window -> surface -> swapchain -> render pass
/// (clear to the given color) -> graphics pipeline (embedded SPIR-V, 3-vertex
/// draw from `gl_VertexIndex`) -> copy-to-buffer readback -> present, `frames`
/// times.  The engine done-bar: "clears, draws a triangle, and presents" --
/// the returned center pixel proves the green triangle covered the frame
/// center and the corner pixel proves the clear color outside it.
/// 0.6.0 adds C07 capture-copy stability (`capture_bytes` + full-frame
/// `capture_crc` compared across frames) and B05 query readback
/// (`timestamp_begin/end` + `timestamp_period_ns` -> `duration_ns`, plus
/// `occlusion_samples`).  See `docs/CAPTURE-QUERY.md` for the raw sequence
/// when the engine owns its command buffer.  Headless-safe (window never
/// shown); cleanup always runs; scalar boundary.
/// Complexity: O(load+device+pipeline+frames).
pub fn vulkan_triangle_probe_named(soname: Str, frames: Int, r: Float32, g: Float32, b: Float32) -> Result[VulkanTriangle, VulkanLoadError]
  requires: soname.len() > 0
  requires: frames > 0
{
  let rc = unsafe { xr_load(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    if rc == 1 {
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABSENT; message: msg });
    }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let ir = unsafe { xr_instance() as Int };
  if ir != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let pr = unsafe { xr_pick_device() as Int };
  if pr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let dr = unsafe { xr_create_device() as Int };
  if dr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let spr = unsafe { xr_submit_probe() as Int };
  if spr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let wr = unsafe { xw_window_create() as Int };
  if wr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let su = unsafe { xw_surface() as Int };
  if su != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let sw = unsafe { xw_swapchain() as Int };
  if sw != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let pp = unsafe { xw_pipeline() as Int };
  if pp != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  var i = 0;
  while i < frames {
    let frc = unsafe { xw_draw_triangle(r, g, b) as Int };
    if frc != 0 {
      let msg = unsafe { Str::from_c_str(xr_error()) };
      unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
    }
    i = i + 1;
  }
  let dn = unsafe { Str::from_c_str(xr_device_name()) };
  let ew = unsafe { xw_extent_w() as Int };
  let eh = unsafe { xw_extent_h() as Int };
  let fm = unsafe { xw_format() as Int };
  let cp = unsafe { xw_center_pixel() as Int };
  let op = unsafe { xw_corner_pixel() as Int };
  let td = unsafe { xw_tri_drawn() as Int };
  let cb = unsafe { xw_capture_bytes() as Int };
  let cc = unsafe { xw_capture_crc() as Int };
  let cs = unsafe { xw_capture_stable() as Int } != 0;
  let qo = unsafe { xw_query_ok() as Int } != 0;
  let tb = unsafe { xw_ts_begin() as Int };
  let te = unsafe { xw_ts_end() as Int };
  let tp = unsafe { xw_ts_period_ns() as Int };
  let oc = unsafe { xw_occlusion_samples() as Int };
  var dur = 0;
  if qo && te >= tb && tp > 0 {
    dur = (te - tb) * tp;
  }
  unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
  return Ok(VulkanTriangle{
    device_name: dn;
    extent_w: ew;
    extent_h: eh;
    format: fm;
    center_pixel: cp;
    corner_pixel: op;
    frames: td;
    capture_bytes: cb;
    capture_crc: cc;
    capture_stable: cs;
    query_ok: qo;
    timestamp_begin: tb;
    timestamp_end: te;
    timestamp_period_ns: tp;
    duration_ns: dur;
    occlusion_samples: oc;
  });
}

/// Triangle round trip on the default loader (clear color 0.1/0.2/0.3).
/// Complexity: O(load+device+pipeline+frames).
pub fn vulkan_triangle_probe(frames: Int) -> Result[VulkanTriangle, VulkanLoadError]
  requires: frames > 0
{
  return vulkan_triangle_probe_named(VULKAN_SONAME, frames, 0.1, 0.2, 0.3);
}

// =========================================================================
// 0.7.0 mini-RHI: compute pipeline + storage buffer + dispatch (2012-engine-2)
// =========================================================================

pub type VulkanCompute = {
  device_name: Str;
  ok: Bool;
  checksum: Int;
  first: Int;
  last: Int;
  expected: Int;
  dispatch_groups: Int;
}

/// Compute tier probe: create a host-visible 256-uint storage buffer,
/// one descriptor set (binding 0 = storage buffer), a compute pipeline from
/// the embedded mini_comp SPIR-V, `vkCmdDispatch(4,1,1)`, submit/wait and
/// read back `v[i] = v[i]*3 + 1`.  `ok` proves every element matched.
/// Complexity: O(load+device+dispatch).
pub fn vulkan_compute_probe_named(soname: Str) -> Result[VulkanCompute, VulkanLoadError]
  requires: soname.len() > 0
{
  let rc = unsafe { xr_load(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    if rc == 1 {
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABSENT; message: msg });
    }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let ir = unsafe { xr_instance() as Int };
  if ir != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let pr = unsafe { xr_pick_device() as Int };
  if pr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let dr = unsafe { xr_create_device() as Int };
  if dr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let spr = unsafe { xr_submit_probe() as Int };
  if spr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let cr = unsafe { xw_compute_probe() as Int };
  let ok = unsafe { xw_compute_ok() as Int } != 0;
  let checksum = unsafe { xw_compute_checksum() as Int };
  let first = unsafe { xw_compute_first() as Int };
  let last = unsafe { xw_compute_last() as Int };
  let expected = unsafe { xw_compute_expected() as Int };
  let dn = unsafe { Str::from_c_str(xr_device_name()) };
  unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
  return Ok(VulkanCompute{
    device_name: dn;
    ok: ok && cr == 0;
    checksum: checksum;
    first: first;
    last: last;
    expected: expected;
    dispatch_groups: 4;
  });
}

/// Compute tier probe on the default loader.
/// Complexity: O(load+device+dispatch).
pub fn vulkan_compute_probe() -> Result[VulkanCompute, VulkanLoadError]
  requires: true
{
  return vulkan_compute_probe_named(VULKAN_SONAME);
}

pub type VulkanIndirect = {
  device_name: Str;
  frames: Int;
  center_pixel: Int;
  corner_pixel: Int;
  ok: Bool;
}

/// Indirect tier probe: index buffer (0,1,2) + a
/// vkCmdDrawIndexedIndirect command in a host-visible buffer, drawn through
/// the same green-triangle pipeline.  `ok` proves the indirect path was used
/// on every frame; the pixel checks prove the draw still lands.
/// Complexity: O(load+device+pipeline+frames).
pub fn vulkan_indirect_probe_named(soname: Str, frames: Int) -> Result[VulkanIndirect, VulkanLoadError]
  requires: soname.len() > 0
  requires: frames > 0
{
  let rc = unsafe { xr_load(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    if rc == 1 {
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABSENT; message: msg });
    }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let ir = unsafe { xr_instance() as Int };
  if ir != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let pr = unsafe { xr_pick_device() as Int };
  if pr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let dr = unsafe { xr_create_device() as Int };
  if dr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let spr = unsafe { xr_submit_probe() as Int };
  if spr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let wr = unsafe { xw_window_create() as Int };
  if wr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let su = unsafe { xw_surface() as Int };
  if su != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let sw = unsafe { xw_swapchain() as Int };
  if sw != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let pp = unsafe { xw_pipeline() as Int };
  if pp != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let ei = unsafe { xw_enable_indirect() as Int };
  if ei != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  var i = 0;
  while i < frames {
    let frc = unsafe { xw_draw_triangle(0.1, 0.2, 0.3) as Int };
    if frc != 0 {
      let msg = unsafe { Str::from_c_str(xr_error()) };
      unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
    }
    i = i + 1;
  }
  let dn = unsafe { Str::from_c_str(xr_device_name()) };
  let cp = unsafe { xw_center_pixel() as Int };
  let op = unsafe { xw_corner_pixel() as Int };
  let ok = unsafe { xw_indirect_ok() as Int } != 0;
  let nf = unsafe { xw_indirect_frames() as Int };
  unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
  return Ok(VulkanIndirect{
    device_name: dn;
    frames: nf;
    center_pixel: cp;
    corner_pixel: op;
    ok: ok;
  });
}

/// Indirect tier probe on the default loader.
/// Complexity: O(load+device+pipeline+frames).
pub fn vulkan_indirect_probe(frames: Int) -> Result[VulkanIndirect, VulkanLoadError]
  requires: frames > 0
{
  return vulkan_indirect_probe_named(VULKAN_SONAME, frames);
}

pub type VulkanLabels = {
  device_name: Str;
  available: Bool; // VK_EXT_debug_utils advertised by the loader
  used: Bool;      // begin/end label pair recorded into a real command buffer
}

/// Debug-label tier probe.  When VK_EXT_debug_utils is present the bridge
/// enables it at instance creation and records a begin/end
/// vkCmdBeginDebugUtilsLabelEXT pair into a submitted command buffer;
/// available=false means SKIP (loader has no debug-utils).
/// Complexity: O(load+device+submit).
pub fn vulkan_labels_probe_named(soname: Str) -> Result[VulkanLabels, VulkanLoadError]
  requires: soname.len() > 0
{
  let rc = unsafe { xr_load(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    if rc == 1 {
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABSENT; message: msg });
    }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let ir = unsafe { xr_instance() as Int };
  if ir != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let pr = unsafe { xr_pick_device() as Int };
  if pr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let dr = unsafe { xr_create_device() as Int };
  if dr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let spr = unsafe { xr_submit_probe() as Int };
  if spr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let lr = unsafe { xw_labels_probe() as Int };
  let avail = unsafe { xw_labels_available() as Int } != 0;
  let used = unsafe { xw_labels_used() as Int } != 0;
  let dn = unsafe { Str::from_c_str(xr_device_name()) };
  unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
  if lr != 0 {
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: "label command buffer submit failed" });
  }
  return Ok(VulkanLabels{ device_name: dn; available: avail; used: used; });
}

/// Debug-label tier probe on the default loader.
/// Complexity: O(load+device+submit).
pub fn vulkan_labels_probe() -> Result[VulkanLabels, VulkanLoadError]
  requires: true
{
  return vulkan_labels_probe_named(VULKAN_SONAME);
}

pub type VulkanBuffers = {
  device_name: Str;
  ok: Bool;
  bytes: Int;
  checksum: Int;
  stride: Int;
}

/// Host-visible vertex/index buffer probe: uploads 3 vertices at stride 48
/// (`x,y,z,u,v,w` + pad), reads the bytes back and verifies the pattern.
/// The engine can layer its own `VkBuffer`/upload path on the same calls.
/// Complexity: O(load+device+buffer size).
pub fn vulkan_buffer_probe_named(soname: Str) -> Result[VulkanBuffers, VulkanLoadError]
  requires: soname.len() > 0
{
  let rc = unsafe { xr_load(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    if rc == 1 {
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABSENT; message: msg });
    }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let ir = unsafe { xr_instance() as Int };
  if ir != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let pr = unsafe { xr_pick_device() as Int };
  if pr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let dr = unsafe { xr_create_device() as Int };
  if dr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let br = unsafe { xw_buffer_probe() as Int };
  let ok = unsafe { xw_buffer_ok() as Int } != 0;
  let bytes = unsafe { xw_buffer_bytes() as Int };
  let checksum = unsafe { xw_buffer_checksum() as Int };
  let dn = unsafe { Str::from_c_str(xr_device_name()) };
  unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
  if br != 0 {
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: "host-visible buffer readback mismatch" });
  }
  return Ok(VulkanBuffers{ device_name: dn; ok: ok; bytes: bytes; checksum: checksum; stride: 48; });
}

/// Host-visible buffer probe on the default loader.
/// Complexity: O(load+device+buffer size).
pub fn vulkan_buffer_probe() -> Result[VulkanBuffers, VulkanLoadError]
  requires: true
{
  return vulkan_buffer_probe_named(VULKAN_SONAME);
}

pub type VulkanFrameSync = {
  device_name: Str;
  frames: Int;
  ok: Bool;
  width: Int;
  height: Int;
}

/// Per-frame sync + recording probe: two command buffers + two fences +
/// two acquire/render semaphore pairs rotate without queue-wide idle; a
/// fence is waited on before re-recording and present waits on the frame's
/// render semaphore.  `ok` means every frame acquired, submitted and
/// presented.
/// Complexity: O(load+device+frames).
pub fn vulkan_frame_sync_probe_named(soname: Str, frames: Int) -> Result[VulkanFrameSync, VulkanLoadError]
  requires: soname.len() > 0
  requires: frames >= 2
{
  let rc = unsafe { xr_load(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    if rc == 1 {
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABSENT; message: msg });
    }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let ir = unsafe { xr_instance() as Int };
  if ir != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let pr = unsafe { xr_pick_device() as Int };
  if pr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let dr = unsafe { xr_create_device() as Int };
  if dr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let spr = unsafe { xr_submit_probe() as Int };
  if spr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let wr = unsafe { xw_window_create() as Int };
  if wr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let su = unsafe { xw_surface() as Int };
  if su != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let sw = unsafe { xw_swapchain() as Int };
  if sw != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let fs = unsafe { xw_frame_sync_probe(frames as Int32) as Int };
  let ok = unsafe { xw_frame_sync_ok() as Int } != 0;
  let nf = unsafe { xw_frame_sync_frames() as Int };
  let dn = unsafe { Str::from_c_str(xr_device_name()) };
  let ew = unsafe { xw_extent_w() as Int };
  let eh = unsafe { xw_extent_h() as Int };
  unsafe { xw_destroy(); xr_destroy(); xr_unload(); }
  if fs != 0 {
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: "per-frame sync/present failed" });
  }
  return Ok(VulkanFrameSync{ device_name: dn; frames: nf; ok: ok; width: ew; height: eh; });
}

/// Per-frame sync probe on the default loader.
/// Complexity: O(load+device+frames).
pub fn vulkan_frame_sync_probe(frames: Int) -> Result[VulkanFrameSync, VulkanLoadError]
  requires: frames >= 2
{
  return vulkan_frame_sync_probe_named(VULKAN_SONAME, frames);
}

pub type VulkanSurface = {
  device_name: Str;
  width: Int;
  height: Int;
  present_mode: Int; // 0 IMMEDIATE, 2 FIFO
  frames: Int;
  recreated_width: Int;
  recreated_height: Int;
  ok: Bool;
}

/// Engine-owned-window surface probe (2015-engine #6/#7): create an
/// external HWND, bind it with `xw_window_from_hwnd` (the engine passes the
/// HWND from `sdl3_window_native_handle` instead of the test window), pick
/// IMMEDIATE when offered (mode 0) or FIFO (2), clear/present frames, then
/// resize + recreate the swapchain and present again.
/// Complexity: O(load+device+frames+recreate).
pub fn vulkan_surface_probe_named(soname: Str, width: Int, height: Int, mode: Int, frames: Int) -> Result[VulkanSurface, VulkanLoadError]
  requires: soname.len() > 0
  requires: width > 0
  requires: height > 0
  requires: frames > 0
{
  let rc = unsafe { xr_load(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    if rc == 1 {
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABSENT; message: msg });
    }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let ir = unsafe { xr_instance() as Int };
  if ir != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let pr = unsafe { xr_pick_device() as Int };
  if pr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let dr = unsafe { xr_create_device() as Int };
  if dr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let spr = unsafe { xr_submit_probe() as Int };
  if spr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let hwnd = unsafe { xw_test_window_create(width as UInt32, height as UInt32) };
  if hwnd == 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let wf = unsafe { xw_window_from_hwnd(hwnd, width as UInt32, height as UInt32) as Int };
  if wf != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xr_destroy(); xr_unload(); xw_test_window_destroy(hwnd); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  unsafe { xw_set_present_mode(mode as UInt32); }
  let su = unsafe { xw_surface() as Int };
  if su != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); xw_test_window_destroy(hwnd); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_NO_DEVICE; message: msg });
  }
  let sw = unsafe { xw_swapchain() as Int };
  if sw != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); xw_test_window_destroy(hwnd); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  var f = 0;
  while f < frames {
    let frc = unsafe { xw_clear_present(0.1, 0.2, 0.3) as Int };
    if frc != 0 {
      let msg = unsafe { Str::from_c_str(xr_error()) };
      unsafe { xw_destroy(); xr_destroy(); xr_unload(); xw_test_window_destroy(hwnd); }
      return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
    }
    f = f + 1;
  }
  let ew = unsafe { xw_extent_w() as Int };
  let eh = unsafe { xw_extent_h() as Int };
  let pm = unsafe { xw_present_mode() as Int };
  let nf = unsafe { xw_frames_done() as Int };
  unsafe { xw_test_window_resize(hwnd, 800 as UInt32, 600 as UInt32); }
  unsafe { xw_set_present_mode(mode as UInt32); }
  let rr = unsafe { xw_recreate_swapchain(800 as UInt32, 600 as UInt32) as Int };
  if rr != 0 {
    let msg = unsafe { Str::from_c_str(xr_error()) };
    unsafe { xw_destroy(); xr_destroy(); xr_unload(); xw_test_window_destroy(hwnd); }
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: msg });
  }
  let fr2 = unsafe { xw_frames(1) as Int };
  let rw = unsafe { xw_extent_w() as Int };
  let rh = unsafe { xw_extent_h() as Int };
  let dn = unsafe { Str::from_c_str(xr_device_name()) };
  unsafe { xw_destroy(); xr_destroy(); xr_unload(); xw_test_window_destroy(hwnd); }
  if fr2 != 0 {
    return Err(VulkanLoadError{ kind: VULKAN_LOAD_ABI; message: "post-recreate present failed" });
  }
  return Ok(VulkanSurface{
    device_name: dn;
    width: ew;
    height: eh;
    present_mode: pm;
    frames: nf;
    recreated_width: rw;
    recreated_height: rh;
    ok: true;
  });
}

/// Engine-owned-window surface probe on the default loader (FIFO).
/// Complexity: O(load+device+frames+recreate).
pub fn vulkan_surface_probe(width: Int, height: Int, frames: Int) -> Result[VulkanSurface, VulkanLoadError]
  requires: width > 0
  requires: height > 0
  requires: frames > 0
{
  return vulkan_surface_probe_named(VULKAN_SONAME, width, height, 0, frames);
}


