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
// Coverage (pilot smoke): loader API version, instance extension count/scan,
// layer count, minimal instance creation, physical-device count + first
// device name/type/apiVersion. Swapchain/render resources remain the
// pre-pilot bridge's territory (preserved in git history; see AUDIT.md).
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
