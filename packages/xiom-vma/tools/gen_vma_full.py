# This file is part of the xiom.vma package -- see README.md / SPEC.md.
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# Licensed under the MIT or Apache-2.0 license, at your option.
#
# Generator for the xiom.vma full-surface bindings (see SPEC.md section 6).
# Parses the oracle vk_mem_alloc.h and emits the C++ bridge + XIOM modules.
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# Licensed under the MIT or Apache-2.0 license, at your option.
#
# Outputs (all generated):
#   src/vma_full_bridge.cpp   C++ bridge: one wrapper per top-level vma*
#                             function + export table + RHI-path support.
#   src/vma_full_ffi.xi       XIOM raw extern surface (1:1 with the oracle)
#                             + bridge self-description declarations.
#   src/vma_full_<family>.xi  XIOM typed family wrappers (pass-throughs
#                             with the documented type mapping).
#   src/vma_full_rhi.xi       XIOM typed RHI-path helpers (device ->
#                             allocator -> buffer -> info -> teardown).
#
# The oracle is the top-level `vma*` API surface declared in
# vk_mem_alloc.h as shipped by the Vulkan SDK (default pin
# C:\VulkanSDK\1.4.350.0\Include\vma\vk_mem_alloc.h, VMA v3.3.0).  The
# generated bridge compiles against the package's vendored header
# (vendor/vk_mem_alloc.h, VMA v3.4.0 -- a superset of the oracle), so
# every oracle function is bindable.

import argparse
import hashlib
import io
import os
import re
import sys

DEFAULT_HEADER = r"C:\VulkanSDK\1.4.350.0\Include\vma\vk_mem_alloc.h"

# Dispatchable handle typedefs (VK_DEFINE_HANDLE -> struct X_T*) and other
# pointer-sized typedef names used by the oracle signatures.
POINTER_TYPEDEFS = (
    "VmaAllocator",
    "VmaAllocation",
    "VmaPool",
    "VmaVirtualBlock",
    "VmaDefragmentationContext",
)
# 64-bit non-dispatchable handles / sizes.
INT64_TYPES = (
    "VkDeviceSize",
    "uint64_t",
    "VkBuffer",
    "VkImage",
    "VmaVirtualAllocation",
)
# 32-bit scalar typedefs.
INT32_TYPES = (
    "uint32_t",
    "VkBool32",
    "VkMemoryPropertyFlags",
)

# Family split: every oracle function belongs to exactly one family; each
# family becomes one generated XIOM module (files stay small).
FAMILIES = [
    ("allocator", [
        "vmaImportVulkanFunctionsFromVolk",
        "vmaCreateAllocator",
        "vmaDestroyAllocator",
        "vmaGetAllocatorInfo",
        "vmaGetPhysicalDeviceProperties",
        "vmaGetMemoryProperties",
        "vmaGetMemoryTypeProperties",
        "vmaSetCurrentFrameIndex",
    ]),
    ("stats", [
        "vmaCalculateStatistics",
        "vmaGetHeapBudgets",
        "vmaBuildStatsString",
        "vmaFreeStatsString",
    ]),
    ("memtype", [
        "vmaFindMemoryTypeIndex",
        "vmaFindMemoryTypeIndexForBufferInfo",
        "vmaFindMemoryTypeIndexForImageInfo",
    ]),
    ("pool", [
        "vmaCreatePool",
        "vmaDestroyPool",
        "vmaGetPoolStatistics",
        "vmaCalculatePoolStatistics",
        "vmaCheckPoolCorruption",
        "vmaGetPoolName",
        "vmaSetPoolName",
    ]),
    ("allocation", [
        "vmaAllocateMemory",
        "vmaAllocateMemoryPages",
        "vmaAllocateMemoryForBuffer",
        "vmaAllocateMemoryForImage",
        "vmaFreeMemory",
        "vmaFreeMemoryPages",
        "vmaGetAllocationInfo",
        "vmaGetAllocationInfo2",
        "vmaSetAllocationUserData",
        "vmaSetAllocationName",
        "vmaGetAllocationMemoryProperties",
        "vmaGetMemoryWin32Handle",
        "vmaMapMemory",
        "vmaUnmapMemory",
        "vmaFlushAllocation",
        "vmaInvalidateAllocation",
        "vmaFlushAllocations",
        "vmaInvalidateAllocations",
        "vmaCopyMemoryToAllocation",
        "vmaCopyAllocationToMemory",
    ]),
    ("defrag", [
        "vmaCheckCorruption",
        "vmaBeginDefragmentation",
        "vmaEndDefragmentation",
        "vmaBeginDefragmentationPass",
        "vmaEndDefragmentationPass",
    ]),
    ("binding", [
        "vmaBindBufferMemory",
        "vmaBindBufferMemory2",
        "vmaBindImageMemory",
        "vmaBindImageMemory2",
    ]),
    ("buffer", [
        "vmaCreateBuffer",
        "vmaCreateBufferWithAlignment",
        "vmaCreateAliasingBuffer",
        "vmaCreateAliasingBuffer2",
        "vmaDestroyBuffer",
    ]),
    ("image", [
        "vmaCreateImage",
        "vmaCreateAliasingImage",
        "vmaCreateAliasingImage2",
        "vmaDestroyImage",
    ]),
    ("virtual", [
        "vmaCreateVirtualBlock",
        "vmaDestroyVirtualBlock",
        "vmaIsVirtualBlockEmpty",
        "vmaGetVirtualAllocationInfo",
        "vmaVirtualAllocate",
        "vmaVirtualFree",
        "vmaClearVirtualBlock",
        "vmaSetVirtualAllocationUserData",
        "vmaGetVirtualBlockStatistics",
        "vmaCalculateVirtualBlockStatistics",
        "vmaBuildVirtualBlockStatsString",
        "vmaFreeVirtualBlockStatsString",
    ]),
]

FAMILY_OF = {}
for _fam, _fns in FAMILIES:
    for _fn in _fns:
        FAMILY_OF[_fn] = _fam

LICENSE_CPP = """// xiom.vma -- GENERATED full-surface bridge over the top-level vma* API.
// Generator: tools/gen_vma_full.py (do not edit by hand).
// Oracle: {header_path}
//         sha256={header_sha}  functions={oracle_count}
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// COMPOSITION: this single TU is the package's only compiled C++ unit.
// It composes the existing probe bridge (src/vma_bridge.cpp -- included
// verbatim, unchanged: VMA implementation + packed probe) with the
// generated wrappers below.  The TU-level config makes the two
// config-gated API families reachable:
//   VK_USE_PLATFORM_WIN32_KHR -> vendor/vulkan/vulkan_win32.h ->
//     VMA_EXTERNAL_MEMORY_WIN32=1 -> vmaGetMemoryWin32Handle
//   VOLK_IMPLEMENTATION + vendor/volk -> VOLK_HEADER_VERSION ->
//     vmaImportVulkanFunctionsFromVolk (volk loader is NOT initialized;
//     the wrapper is bridged and null-guard-probed only).
//
// ABI (B-20 discipline): every wrapper mirrors the C signature; XIOM
// passes pointers as Int and scalars as Int32/Int64.  Bridge -> XIOM data
// crosses as scalar returns only (packed ints and getter calls), never by
// reading foreign memory through pointers; the B-11 slot-recycle shape is
// avoided.  VMA_NOT_NULL pointer parameters are guarded: a null argument
// returns VK_ERROR_INITIALIZATION_FAILED (or VK_FALSE / no-op for
// VkBool32 / void wrappers) instead of tripping VMA_ASSERT.
"""

BRIDGE_SUPPORT = r"""
#include <cstdint>

#if !defined(VOLK_HEADER_VERSION)
#error gen_vma_full: volk.h must define VOLK_HEADER_VERSION
#endif
#if !defined(VK_KHR_external_memory_win32)
#error gen_vma_full: vendor/vulkan/vulkan_win32.h must be reachable
#endif
#if !defined(VMA_EXTERNAL_MEMORY_WIN32) || !VMA_EXTERNAL_MEMORY_WIN32
#error gen_vma_full: VMA_EXTERNAL_MEMORY_WIN32 must be 1
#endif

// ---------------------------------------------------------------------------
// Generated wrappers: one per top-level vma* function (signature mirrored,
// VMA_NOT_NULL pointer args null-guarded).
// ---------------------------------------------------------------------------

@WRAPPERS@
// ---------------------------------------------------------------------------
// Export table + self-description (runtime coverage proof for the suite).
// ---------------------------------------------------------------------------

static const char* const g_vmafull_export_names[@COUNT@] = {
@EXPORT_NAMES@};

extern "C" int vmafull_export_count(void) { return @COUNT@; }
extern "C" int vmafull_oracle_count(void) { return @COUNT@; }

extern "C" int vmafull_export_name_is(int index, const char* expected) {
  if (index < 0 || index >= @COUNT@ || expected == 0) return 0;
  const char* a = g_vmafull_export_names[index];
  const char* b = expected;
  while (*a != '\0' && *a == *b) { ++a; ++b; }
  return (*a == '\0' && *b == '\0') ? 1 : 0;
}

// Forces a link-time reference to every wrapper; returns @COUNT@ when all
// of them are present in the binary (a missing symbol fails the link).
extern "C" int vmafull_link_proof(void) {
  static volatile int sink = 0;
  int hits = 0;
@LINK_PROOF@
  return hits;
}

// ---------------------------------------------------------------------------
// RHI path support: device -> allocator -> buffer -> info -> teardown.
// Every VMA step below goes through the generated wrappers above (the
// device/instance/queue creation mirrors src/vma_bridge.cpp run_probe).
// Handles stay in bridge-owned slots; XIOM reads scalars via getters.
// ---------------------------------------------------------------------------

namespace {

struct VmaFullSlot {
  int state;  // 0 free; 1 device; 2 allocator; 3 buffer
  HMODULE mod;
  PFN_vkGetInstanceProcAddr gipa;
  PFN_vkGetDeviceProcAddr gdpa;
  VkInstance instance;
  VkPhysicalDevice physical;
  VkDevice device;
  uint32_t queue_family;
  PFN_vkDestroyInstance destroy_instance;
  PFN_vkDestroyDevice destroy_device;
  VmaAllocator allocator;
  VkBuffer buffer;
  VmaAllocation allocation;
  VmaAllocationInfo info;
};

VmaFullSlot g_vmafull_slots[4] = {};

VmaFullSlot* vmafull_slot(int handle) {
  if (handle < 1 || handle > 4) return 0;
  return &g_vmafull_slots[handle - 1];
}

int vmafull_alloc_slot(void) {
  for (int i = 0; i < 4; ++i) {
    if (g_vmafull_slots[i].state == 0) return i + 1;
  }
  return 0;
}

void vmafull_slot_cleanup(VmaFullSlot* s) {
  if (s->allocator != 0) vmaDestroyAllocator(s->allocator);
  if (s->device != 0 && s->destroy_device != 0) s->destroy_device(s->device, 0);
  if (s->instance != 0 && s->destroy_instance != 0) s->destroy_instance(s->instance, 0);
  if (s->mod != 0) FreeLibrary(s->mod);
  *s = VmaFullSlot{};
}

} // namespace

// Creates instance -> physical device -> graphics-queue device (the
// package's device creation path); returns a 1-based slot, or a negative
// classification: -100 loader missing, -101 no physical device,
// -102 no graphics queue family, -1..-9 step failures.
extern "C" int vmafull_device_setup(const char* dll_name) {
  if (dll_name == 0) return -1;
  int h = vmafull_alloc_slot();
  if (h == 0) return -1;
  VmaFullSlot* s = &g_vmafull_slots[h - 1];
  s->state = 1;

  s->mod = LoadLibraryA(dll_name);
  if (s->mod == 0) { *s = VmaFullSlot{}; return -100; }
  s->gipa = (PFN_vkGetInstanceProcAddr)(void*)GetProcAddress(s->mod, "vkGetInstanceProcAddr");
  if (s->gipa == 0) { vmafull_slot_cleanup(s); return -100; }

  PFN_vkCreateInstance create_instance =
      (PFN_vkCreateInstance)s->gipa(VK_NULL_HANDLE, "vkCreateInstance");
  if (create_instance == 0) { vmafull_slot_cleanup(s); return -2; }

  VkApplicationInfo app_info = { VK_STRUCTURE_TYPE_APPLICATION_INFO };
  app_info.apiVersion = VK_API_VERSION_1_0;
  VkInstanceCreateInfo instance_info = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
  instance_info.pApplicationInfo = &app_info;
  if (create_instance(&instance_info, 0, &s->instance) != VK_SUCCESS) {
    vmafull_slot_cleanup(s);
    return -2;
  }
  s->destroy_instance = (PFN_vkDestroyInstance)s->gipa(s->instance, "vkDestroyInstance");

  PFN_vkEnumeratePhysicalDevices enumerate_devices =
      (PFN_vkEnumeratePhysicalDevices)s->gipa(s->instance, "vkEnumeratePhysicalDevices");
  if (enumerate_devices == 0) { vmafull_slot_cleanup(s); return -3; }
  uint32_t device_count = 0;
  if (enumerate_devices(s->instance, &device_count, 0) != VK_SUCCESS || device_count == 0) {
    vmafull_slot_cleanup(s);
    return -101;
  }
  VkPhysicalDevice devices[8] = {};
  uint32_t n = device_count < 8 ? device_count : 8;
  if (enumerate_devices(s->instance, &n, devices) != VK_SUCCESS || n == 0) {
    vmafull_slot_cleanup(s);
    return -101;
  }

  PFN_vkGetPhysicalDeviceQueueFamilyProperties get_queue_props =
      (PFN_vkGetPhysicalDeviceQueueFamilyProperties)s->gipa(s->instance, "vkGetPhysicalDeviceQueueFamilyProperties");
  PFN_vkCreateDevice create_device =
      (PFN_vkCreateDevice)s->gipa(s->instance, "vkCreateDevice");
  if (get_queue_props == 0 || create_device == 0) { vmafull_slot_cleanup(s); return -3; }

  uint32_t queue_family = UINT32_MAX;
  for (uint32_t i = 0; i < n && s->physical == VK_NULL_HANDLE; ++i) {
    uint32_t qcount = 0;
    get_queue_props(devices[i], &qcount, 0);
    VkQueueFamilyProperties props[32] = {};
    uint32_t qn = qcount < 32 ? qcount : 32;
    get_queue_props(devices[i], &qn, props);
    for (uint32_t q = 0; q < qn; ++q) {
      if ((props[q].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0) {
        s->physical = devices[i];
        queue_family = q;
        break;
      }
    }
  }
  if (s->physical == VK_NULL_HANDLE) { vmafull_slot_cleanup(s); return -102; }

  float priority = 1.0f;
  VkDeviceQueueCreateInfo queue_info = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
  queue_info.queueFamilyIndex = queue_family;
  queue_info.queueCount = 1;
  queue_info.pQueuePriorities = &priority;
  VkDeviceCreateInfo device_info = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
  device_info.queueCreateInfoCount = 1;
  device_info.pQueueCreateInfos = &queue_info;
  if (create_device(s->physical, &device_info, 0, &s->device) != VK_SUCCESS) {
    vmafull_slot_cleanup(s);
    return -4;
  }
  s->destroy_device = (PFN_vkDestroyDevice)s->gipa(s->instance, "vkDestroyDevice");
  s->gdpa = (PFN_vkGetDeviceProcAddr)s->gipa(s->instance, "vkGetDeviceProcAddr");
  if (s->gdpa == 0) { vmafull_slot_cleanup(s); return -3; }
  s->queue_family = queue_family;
  s->state = 1;
  return h;
}

extern "C" int vmafull_device_teardown(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return -1;
  vmafull_slot_cleanup(s);
  return 0;
}

// vmaCreateAllocator through the generated wrapper (VMA dynamic functions
// over the setup's gipa/gdpa).  Returns the VkResult.
extern "C" int vmafull_allocator_create(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0 || s->state < 1) return -1;
  if (s->allocator != 0) return -2;
  VmaVulkanFunctions fns = {};
  fns.vkGetInstanceProcAddr = s->gipa;
  fns.vkGetDeviceProcAddr = s->gdpa;
  VmaAllocatorCreateInfo info = {};
  info.physicalDevice = s->physical;
  info.device = s->device;
  info.instance = s->instance;
  info.vulkanApiVersion = VK_API_VERSION_1_0;
  info.pVulkanFunctions = &fns;
  VmaAllocator allocator = VK_NULL_HANDLE;
  VkResult res = vmafull_wrap_vmaCreateAllocator(&info, &allocator);
  if (res == VK_SUCCESS) {
    s->allocator = allocator;
    s->state = 2;
  }
  return (int)res;
}

// vmaDestroyAllocator through the generated wrapper.
extern "C" int vmafull_allocator_destroy(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0 || s->allocator == 0) return -1;
  vmafull_wrap_vmaDestroyAllocator(s->allocator);
  s->allocator = VK_NULL_HANDLE;
  s->state = 1;
  return 0;
}

extern "C" int64_t vmafull_slot_allocator(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return 0;
  return (int64_t)(intptr_t)s->allocator;
}

// vmaCreateBuffer through the generated wrapper: 64 KiB transfer-src
// buffer with a host-visible sequential-write allocation (AUTO memory).
extern "C" int vmafull_buffer_create(int handle, int64_t size) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0 || s->allocator == 0) return -1;
  VkBufferCreateInfo buffer_info = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
  buffer_info.size = (VkDeviceSize)size;
  buffer_info.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
  buffer_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
  VmaAllocationCreateInfo alloc_info = {};
  alloc_info.usage = VMA_MEMORY_USAGE_AUTO;
  alloc_info.flags = VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
  VkBuffer buffer = VK_NULL_HANDLE;
  VmaAllocation allocation = VK_NULL_HANDLE;
  VkResult res = vmafull_wrap_vmaCreateBuffer(
      s->allocator, &buffer_info, &alloc_info, &buffer, &allocation, 0);
  if (res == VK_SUCCESS) {
    s->buffer = buffer;
    s->allocation = allocation;
    s->state = 3;
  }
  return (int)res;
}

// vmaGetAllocationInfo through the generated wrapper; the C-side struct is
// copied into the slot and read back via scalar getters.
extern "C" int vmafull_allocation_info(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0 || s->allocation == 0) return -1;
  VmaAllocationInfo info = {};
  vmafull_wrap_vmaGetAllocationInfo(s->allocator, s->allocation, &info);
  s->info = info;
  return 0;
}

extern "C" int64_t vmafull_buffer_handle(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return 0;
  return (int64_t)s->buffer;
}

extern "C" int64_t vmafull_allocation_handle(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return 0;
  return (int64_t)(intptr_t)s->allocation;
}

extern "C" int64_t vmafull_info_size(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return 0;
  return (int64_t)s->info.size;
}

extern "C" int64_t vmafull_info_offset(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return 0;
  return (int64_t)s->info.offset;
}

extern "C" int vmafull_info_memory_type(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return -1;
  return (int)s->info.memoryType;
}

extern "C" int64_t vmafull_info_device_memory(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return 0;
  return (int64_t)s->info.deviceMemory;
}

// vmaDestroyBuffer through the generated wrapper.
extern "C" int vmafull_buffer_destroy(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return -1;
  vmafull_wrap_vmaDestroyBuffer(s->allocator, s->buffer, s->allocation);
  s->buffer = VK_NULL_HANDLE;
  s->allocation = VK_NULL_HANDLE;
  s->state = 2;
  return 0;
}

// Functional probe for the config-gated win32 function on a real
// allocation: with the win32 handle fn not enabled at device creation VMA
// returns VK_ERROR_FEATURE_NOT_PRESENT (documented); the probe accepts
// that or VK_SUCCESS.
extern "C" int vmafull_win32_handle_probe(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0 || s->allocation == 0) return -1;
  HANDLE out_handle = 0;
  VkResult res =
      vmafull_wrap_vmaGetMemoryWin32Handle(s->allocator, s->allocation, 0, &out_handle);
  return (int)res;
}

// Null-argument error path: every check must match its expected guarded
// return; the returned bitmask is 0 when all guards behaved.
extern "C" int vmafull_error_probe(void) {
  int mask = 0;
  if (vmafull_wrap_vmaCreateAllocator(0, 0) != VK_ERROR_INITIALIZATION_FAILED) mask |= 1;
  if (vmafull_wrap_vmaCreateBuffer(0, 0, 0, 0, 0, 0) != VK_ERROR_INITIALIZATION_FAILED) mask |= 2;
  if (vmafull_wrap_vmaFindMemoryTypeIndex(0, 0, 0, 0) != VK_ERROR_INITIALIZATION_FAILED) mask |= 4;
  if (vmafull_wrap_vmaMapMemory(0, 0, 0) != VK_ERROR_INITIALIZATION_FAILED) mask |= 8;
  if (vmafull_wrap_vmaIsVirtualBlockEmpty(0) != VK_FALSE) mask |= 16;
  if (vmafull_wrap_vmaImportVulkanFunctionsFromVolk(0, 0) != VK_ERROR_INITIALIZATION_FAILED) mask |= 32;
  if (vmafull_wrap_vmaGetMemoryWin32Handle(0, 0, 0, 0) != VK_ERROR_INITIALIZATION_FAILED) mask |= 64;
  vmafull_wrap_vmaDestroyBuffer(0, 0, 0);
  vmafull_wrap_vmaGetAllocationInfo(0, 0, 0);
  vmafull_wrap_vmaFreeMemory(0, 0);
  return mask;
}
"""


def parse_header(text):
    """Extract the top-level vma* declarations (name, ret, params)."""
    m = re.search(r"^#ifdef VMA_IMPLEMENTATION\b", text, re.M)
    region = text[: m.start()] if m else text
    decl_re = re.compile(
        r"VMA_CALL_PRE\s+([A-Za-z0-9_]+)\s+VMA_CALL_POST\s+(vma\w+)\s*\("
    )
    funcs = []
    seen = set()
    for m in decl_re.finditer(region):
        ret = m.group(1).strip()
        name = m.group(2)
        if name in seen:
            continue
        seen.add(name)
        i = m.end()
        depth = 1
        while i < len(region) and depth > 0:
            c = region[i]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            i += 1
        if depth != 0:
            raise SystemExit("unbalanced parentheses in declaration of " + name)
        params = parse_params(region[m.end(): i - 1])
        funcs.append({"name": name, "ret": ret, "params": params})
    return funcs


def split_top_level(text):
    parts = []
    depth = 0
    cur = []
    for c in text:
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        if c == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(c)
    if cur:
        parts.append("".join(cur))
    return parts


def parse_params(text):
    params = []
    for raw in split_top_level(text):
        raw = raw.strip()
        if not raw:
            continue
        tokens = raw.split()
        notnull = any(t.startswith("VMA_NOT_NULL") for t in tokens)
        nullable = any(t.startswith("VMA_NULLABLE") for t in tokens)
        kept = []
        for t in tokens:
            if t.startswith("VMA_"):
                # VMA_NOT_NULL / VMA_NULLABLE (optionally suffixed with '*'),
                # VMA_LEN_IF_NOT_NULL(...), VMA_EXTENDS_VK_STRUCT(...), ...
                # A glued '*' is part of the declarator, keep it.
                if t.endswith("*"):
                    kept.append("*")
                continue
            kept.append(t)
        if len(kept) < 2:
            raise SystemExit("cannot parse parameter: " + raw)
        name = kept[-1]
        ctype = " ".join(kept[:-1])
        ctype = re.sub(r"\s*\*\s*", "*", ctype)
        is_ptr = "*" in ctype or ctype.replace("const ", "").strip() in POINTER_TYPEDEFS
        params.append({
            "name": name,
            "ctype": ctype,
            "is_ptr": is_ptr,
            "guard": is_ptr and notnull and not nullable,
        })
    return params


def xiom_type(ctype):
    base = ctype.replace("const ", "").strip()
    if "*" in ctype or base in POINTER_TYPEDEFS:
        return "Int"
    if base == "size_t" or base == "HANDLE":
        return "Int"
    if base in INT32_TYPES:
        return "Int32"
    if base in INT64_TYPES:
        return "Int64"
    raise SystemExit("unmapped C type: " + ctype)


def xiom_ret(ret):
    if ret == "void":
        return None
    if ret in ("VkResult", "VkBool32"):
        return "Int32"
    raise SystemExit("unmapped return type: " + ret)


def guard_return(ret, indent):
    if ret == "void":
        return indent + "return;"
    if ret == "VkResult":
        return indent + "return VK_ERROR_INITIALIZATION_FAILED;"
    if ret == "VkBool32":
        return indent + "return VK_FALSE;"
    raise SystemExit("unmapped guarded return: " + ret)


def emit_wrapper(fn):
    out = io.StringIO()
    params = fn["params"]
    sig = ", ".join(p["ctype"] + " " + p["name"] for p in params)
    out.write("extern \"C\" %s vmafull_wrap_%s(%s) {\n" % (fn["ret"], fn["name"], sig))
    guarded = [p for p in params if p["guard"]]
    if guarded:
        cond = " || ".join(p["name"] + " == 0" for p in guarded)
        out.write("  if (%s) %s\n" % (cond, guard_return(fn["ret"], "").strip()))
    call = "%s(%s);" % (fn["name"], ", ".join(p["name"] for p in params))
    if fn["ret"] == "void":
        out.write("  " + call + "\n")
    else:
        out.write("  return " + call + "\n")
    out.write("}\n\n")
    return out.getvalue()


def gen_bridge(funcs, header_path, header_sha):
    parts = [LICENSE_CPP.format(header_path=header_path, header_sha=header_sha,
                                oracle_count=len(funcs))]
    parts.append(
        "#define NOMINMAX 1\n"
        "#define WIN32_LEAN_AND_MEAN 1\n"
        "#define VK_USE_PLATFORM_WIN32_KHR 1\n"
        "#define VOLK_IMPLEMENTATION 1\n"
        "#include \"../vendor/volk/volk.h\"\n\n"
        "// Existing probe bridge + VMA implementation (unchanged file).\n"
        "#include \"vma_bridge.cpp\"\n")
    wrappers = "".join(emit_wrapper(f) for f in funcs)
    names = "".join('    "%s",\n' % f["name"] for f in funcs)
    proof = "".join(
        "  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_%s != 0); ++hits;\n" % f["name"]
        for f in funcs)
    support = BRIDGE_SUPPORT.replace("@WRAPPERS@", wrappers)
    support = support.replace("@EXPORT_NAMES@", names)
    support = support.replace("@LINK_PROOF@", proof)
    support = support.replace("@COUNT@", str(len(funcs)))
    parts.append(support)
    return "".join(parts)


def xi_doc(fn):
    ret = xiom_ret(fn["ret"])
    if ret is None:
        return "-> Unit"
    return "-> " + ret


def gen_ffi(funcs, oracle_count):
    out = io.StringIO()
    out.write(
        "// XIOM -- GENERATED raw FFI surface for the full top-level vma* API.\n"
        "// Generator: tools/gen_vma_full.py (do not edit by hand).\n"
        "// Oracle: %d top-level vma* functions (Vulkan SDK 1.4.350.0 vk_mem_alloc.h, VMA v3.3.0).\n"
        "// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors\n"
        "// Licensed under the MIT or Apache-2.0 license, at your option.\n"
        "//\n"
        "// Type mapping: pointers/opaque handles/size_t/HANDLE -> Int (0 = null);\n"
        "// uint32_t/VkBool32/flags -> Int32; VkDeviceSize/VkBuffer/VkImage/\n"
        "// VmaVirtualAllocation -> Int64; void -> Unit.  Out-params are C-side\n"
        "// bridge slots: never read through foreign pointers (B-20).\n"
        "\nmodule xiom.vma.full_ffi\n\n"
        "pub const VMA_FULL_ORACLE_COUNT: Int = %d;\n\n"
        "// Vulkan result codes used by the generated surface (VkResult).\n"
        "pub const VK_SUCCESS: Int32 = 0;\n"
        "pub const VK_ERROR_OUT_OF_HOST_MEMORY: Int32 = -1;\n"
        "pub const VK_ERROR_OUT_OF_DEVICE_MEMORY: Int32 = -2;\n"
        "pub const VK_ERROR_INITIALIZATION_FAILED: Int32 = -3;\n"
        "pub const VK_ERROR_FEATURE_NOT_PRESENT: Int32 = -8;\n\n"
        "// ---------------------------------------------------------------------\n"
        "// The bound surface: one extern per oracle function (header order).\n"
        "// ---------------------------------------------------------------------\n\n"
        "pub extern \"C\" {\n" % (oracle_count, oracle_count))
    for fn in funcs:
        args = ", ".join("%s: %s" % (p["name"], xiom_type(p["ctype"])) for p in fn["params"])
        ret = xiom_ret(fn["ret"])
        decl = "  fn vmafull_wrap_%s(%s)" % (fn["name"], args)
        if ret is not None:
            decl += " -> " + ret
        out.write(decl + ";\n")
    out.write("}\n\n"
              "// ---------------------------------------------------------------------\n"
              "// Bridge self-description + RHI-path support (src/vma_full_bridge.cpp).\n"
              "// ---------------------------------------------------------------------\n\n"
              "pub extern \"C\" {\n"
              "  fn vmafull_export_count() -> Int32;\n"
              "  fn vmafull_oracle_count() -> Int32;\n"
              "  fn vmafull_export_name_is(index: Int32, expected: *UInt8) -> Int32;\n"
              "  fn vmafull_link_proof() -> Int32;\n"
              "  fn vmafull_device_setup(dll_name: *UInt8) -> Int32;\n"
              "  fn vmafull_device_teardown(slot: Int32) -> Int32;\n"
              "  fn vmafull_allocator_create(slot: Int32) -> Int32;\n"
              "  fn vmafull_allocator_destroy(slot: Int32) -> Int32;\n"
              "  fn vmafull_slot_allocator(slot: Int32) -> Int;\n"
              "  fn vmafull_buffer_create(slot: Int32, size: Int64) -> Int32;\n"
              "  fn vmafull_allocation_info(slot: Int32) -> Int32;\n"
              "  fn vmafull_buffer_handle(slot: Int32) -> Int;\n"
              "  fn vmafull_allocation_handle(slot: Int32) -> Int;\n"
              "  fn vmafull_info_size(slot: Int32) -> Int64;\n"
              "  fn vmafull_info_offset(slot: Int32) -> Int64;\n"
              "  fn vmafull_info_memory_type(slot: Int32) -> Int32;\n"
              "  fn vmafull_info_device_memory(slot: Int32) -> Int64;\n"
              "  fn vmafull_buffer_destroy(slot: Int32) -> Int32;\n"
              "  fn vmafull_win32_handle_probe(slot: Int32) -> Int32;\n"
              "  fn vmafull_error_probe() -> Int32;\n"
              "}\n")
    return out.getvalue()


def gen_family(family, funcs):
    out = io.StringIO()
    out.write(
        "// XIOM -- GENERATED typed wrappers: %s family (%d functions).\n"
        "// Generator: tools/gen_vma_full.py (do not edit by hand).\n"
        "// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors\n"
        "// Licensed under the MIT or Apache-2.0 license, at your option.\n"
        "//\n"
        "// Thin typed pass-throughs over the bridge wrappers (same mapping,\n"
        "// same names as the C API).  VMA_NOT_NULL pointer args are guarded in\n"
        "// the bridge (null -> VK_ERROR_INITIALIZATION_FAILED).  The extern\n"
        "// block is module-local: v0.64.3 resolves `use` only in the entry\n"
        "// module, so family modules are self-contained (duplicate extern\n"
        "// declarations of the same C symbol are legal).\n"
        "\nmodule xiom.vma.full_%s\n\n" % (family, len(funcs), family))
    out.write("extern \"C\" {\n")
    for fn in funcs:
        args = ", ".join("%s: %s" % (p["name"], xiom_type(p["ctype"])) for p in fn["params"])
        ret = xiom_ret(fn["ret"])
        decl = "  fn vmafull_wrap_%s(%s)" % (fn["name"], args)
        if ret is not None:
            decl += " -> " + ret
        out.write(decl + ";\n")
    out.write("}\n\n")
    for fn in funcs:
        args = ", ".join("%s: %s" % (p["name"], xiom_type(p["ctype"])) for p in fn["params"])
        ret = xiom_ret(fn["ret"])
        out.write("/// %s %s\n" % (fn["name"], xi_doc(fn)))
        decl = "pub fn vma_full_%s(%s)" % (camel_to_snake(fn["name"][3:]), args)
        if ret is not None:
            decl += " -> " + ret
        out.write(decl + "\n  requires: true\n{\n")
        call = "vmafull_wrap_%s(%s)" % (fn["name"], ", ".join(p["name"] for p in fn["params"]))
        if ret is None:
            out.write("  unsafe { " + call + "; }\n")
        else:
            out.write("  return unsafe { " + call + " };\n")
        out.write("}\n\n")
    return out.getvalue()


def camel_to_snake(name):
    out = []
    for i, c in enumerate(name):
        if c.isupper() and i > 0 and not name[i - 1].isupper():
            out.append("_")
        out.append(c.lower())
    return "".join(out)


def gen_rhi():
    return """// XIOM -- GENERATED typed RHI-path helpers over the bridge support API.
// Generator: tools/gen_vma_full.py (do not edit by hand).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// The suite drives the prescribed path through these helpers:
// device setup -> vmaCreateAllocator -> vmaCreateBuffer ->
// vmaGetAllocationInfo -> vmaDestroyBuffer -> vmaDestroyAllocator ->
// teardown.  Every VMA step goes through a generated bridge wrapper;
// handles stay in bridge slots and cross as scalars (B-11/B-20 safe).

module xiom.vma.full_rhi

extern "C" {
  fn vmafull_export_count() -> Int32;
  fn vmafull_oracle_count() -> Int32;
  fn vmafull_export_name_is(index: Int32, expected: *UInt8) -> Int32;
  fn vmafull_link_proof() -> Int32;
  fn vmafull_device_setup(dll_name: *UInt8) -> Int32;
  fn vmafull_device_teardown(slot: Int32) -> Int32;
  fn vmafull_allocator_create(slot: Int32) -> Int32;
  fn vmafull_allocator_destroy(slot: Int32) -> Int32;
  fn vmafull_slot_allocator(slot: Int32) -> Int;
  fn vmafull_buffer_create(slot: Int32, size: Int64) -> Int32;
  fn vmafull_allocation_info(slot: Int32) -> Int32;
  fn vmafull_buffer_handle(slot: Int32) -> Int;
  fn vmafull_allocation_handle(slot: Int32) -> Int;
  fn vmafull_info_size(slot: Int32) -> Int64;
  fn vmafull_info_offset(slot: Int32) -> Int64;
  fn vmafull_info_memory_type(slot: Int32) -> Int32;
  fn vmafull_info_device_memory(slot: Int32) -> Int64;
  fn vmafull_buffer_destroy(slot: Int32) -> Int32;
  fn vmafull_win32_handle_probe(slot: Int32) -> Int32;
  fn vmafull_error_probe() -> Int32;
}

/// rhi_setup classification for the deterministic SKIP path.
pub const RHI_SKIP_LOADER: Int = -100;
pub const RHI_SKIP_DEVICE: Int = -101;
pub const RHI_SKIP_QUEUE: Int = -102;

/// error_probe_mask() expected value: every null-arg guard behaved.
pub const ERROR_PROBE_EXPECTED: Int = 0;

fn loader_name() -> Str
  requires: true
{
  return "vulkan-1.dll";
}

/// Bridge-exposed function count (export table size).
pub fn surface_count() -> Int
  requires: true
{
  return unsafe { vmafull_export_count() as Int };
}

/// Runtime oracle count baked by the generator.
pub fn surface_oracle() -> Int
  requires: true
{
  return unsafe { vmafull_oracle_count() as Int };
}

/// Link proof: number of wrappers whose symbols are present (== oracle
/// when the full generated surface linked).
pub fn link_proof_count() -> Int
  requires: true
{
  return unsafe { vmafull_link_proof() as Int };
}

/// True when export table entry `index` carries exactly `expected`.
pub fn surface_name_is(index: Int, expected: Str) -> Bool
  requires: index >= 0
{
  return unsafe { (vmafull_export_name_is(index as Int32, expected.c_str()) as Int) != 0 };
}

/// Create instance -> physical device -> graphics-queue device (the
/// package's device creation path).  Returns a 1-based slot, or a negative
/// classification (see RHI_SKIP_*; -1..-9 = step failures).
pub fn rhi_setup() -> Int
  requires: true
{
  return unsafe { vmafull_device_setup(loader_name().c_str()) as Int };
}

/// Same, against an explicitly named loader module (deterministic SKIP
/// classification on any host with a bogus name).
pub fn rhi_setup_named(dll: Str) -> Int
  requires: dll.len() > 0
{
  return unsafe { vmafull_device_setup(dll.c_str()) as Int };
}

pub fn rhi_teardown(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_device_teardown(slot as Int32) };
}

/// vmaCreateAllocator through the generated wrapper (VkResult).
pub fn rhi_allocator_create(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_allocator_create(slot as Int32) };
}

/// vmaDestroyAllocator through the generated wrapper.
pub fn rhi_allocator_destroy(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_allocator_destroy(slot as Int32) };
}

pub fn rhi_slot_allocator(slot: Int) -> Int
  requires: slot > 0
{
  return unsafe { vmafull_slot_allocator(slot as Int32) };
}

/// vmaCreateBuffer (64 KiB path) through the generated wrapper.
pub fn rhi_buffer_create(slot: Int, size: Int) -> Int32
  requires: slot > 0
  requires: size > 0
{
  return unsafe { vmafull_buffer_create(slot as Int32, size as Int64) };
}

/// vmaGetAllocationInfo through the generated wrapper.
pub fn rhi_allocation_info(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_allocation_info(slot as Int32) };
}

pub fn rhi_buffer_handle(slot: Int) -> Int
  requires: slot > 0
{
  return unsafe { vmafull_buffer_handle(slot as Int32) };
}

pub fn rhi_allocation_handle(slot: Int) -> Int
  requires: slot > 0
{
  return unsafe { vmafull_allocation_handle(slot as Int32) };
}

pub fn rhi_info_size(slot: Int) -> Int
  requires: slot > 0
{
  return unsafe { vmafull_info_size(slot as Int32) as Int };
}

pub fn rhi_info_offset(slot: Int) -> Int
  requires: slot > 0
{
  return unsafe { vmafull_info_offset(slot as Int32) as Int };
}

pub fn rhi_info_memory_type(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_info_memory_type(slot as Int32) };
}

pub fn rhi_info_device_memory(slot: Int) -> Int
  requires: slot > 0
{
  return unsafe { vmafull_info_device_memory(slot as Int32) as Int };
}

/// vmaDestroyBuffer through the generated wrapper.
pub fn rhi_buffer_destroy(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_buffer_destroy(slot as Int32) };
}

/// Functional probe for the config-gated vmaGetMemoryWin32Handle on the
/// live allocation: VK_SUCCESS or VK_ERROR_FEATURE_NOT_PRESENT (the
/// win32 handle fn is not enabled at device creation).
pub fn rhi_win32_handle_probe(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_win32_handle_probe(slot as Int32) };
}

/// Null-argument guard bitmask over seven wrapper shapes; 0 = all good.
pub fn error_probe_mask() -> Int
  requires: true
{
  return unsafe { vmafull_error_probe() as Int };
}
"""


def main():
    ap = argparse.ArgumentParser(description="Generate the xiom.vma full-surface bindings.")
    ap.add_argument("--header", default=DEFAULT_HEADER,
                    help="oracle vk_mem_alloc.h (default: the SDK pin)")
    ap.add_argument("--out-dir", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    help="package directory (default: the package this script lives in)")
    args = ap.parse_args()

    with open(args.header, "rb") as fh:
        raw = fh.read()
    header_sha = hashlib.sha256(raw).hexdigest().upper()
    text = raw.decode("utf-8", "replace")
    funcs = parse_header(text)
    if not funcs:
        raise SystemExit("no vma* declarations found in " + args.header)

    missing = [f["name"] for f in funcs if f["name"] not in FAMILY_OF]
    if missing:
        raise SystemExit("functions missing from the family map: " + ", ".join(missing))
    extra = [n for n in FAMILY_OF if n not in set(f["name"] for f in funcs)]
    if extra:
        raise SystemExit("family map names not in the oracle: " + ", ".join(extra))

    src = os.path.join(args.out_dir, "src")
    if not os.path.isdir(src):
        raise SystemExit("src directory not found: " + src)

    write(os.path.join(src, "vma_full_bridge.cpp"),
          gen_bridge(funcs, args.header, header_sha))
    write(os.path.join(src, "vma_full_ffi.xi"), gen_ffi(funcs, len(funcs)))
    for family, names in FAMILIES:
        fam_funcs = [f for f in funcs if FAMILY_OF[f["name"]] == family]
        write(os.path.join(src, "vma_full_%s.xi" % family), gen_family(family, fam_funcs))
    write(os.path.join(src, "vma_full_rhi.xi"), gen_rhi())

    print("oracle: %s" % args.header)
    print("sha256: %s" % header_sha)
    print("bound : %d functions" % len(funcs))
    for family, names in FAMILIES:
        print("  %-10s %d" % (family, len(names)))
    print("generated: src/vma_full_bridge.cpp, src/vma_full_ffi.xi, "
          "src/vma_full_*.xi, src/vma_full_rhi.xi")


def write(path, content):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(content)
    print("wrote %s (%d bytes)" % (path, len(content)))


if __name__ == "__main__":
    main()
