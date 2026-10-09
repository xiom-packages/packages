// xiom.vma -- C bridge over the vendored Vulkan Memory Allocator 3.4.0
// (header-only) plus a dlopen'd Vulkan loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// No SDK and no import library: `vulkan-1.dll` is loaded at runtime and
// every entry point is fetched via vkGetInstanceProcAddr; VMA runs with
// VMA_DYNAMIC_VULKAN_FUNCTIONS using the same two procs.
//
// RESULT SHAPE: the probe returns a PACKED int (no out-param slots).
// Under the v0.64.2 runtime + the NVIDIA loader, slot memory written by a
// Vulkan-heavy C call was observed recycled before XIOM could read it
// (finding B-11; repro `vmaprobe_run` below + the committed probe bundle).
// Packing dodge: `(heap << 20) | (verify << 28) | size` (size < 2^20 for
// the probe); a negative return is `-classification_code`.
//
// Classification codes (negated in the packed return):
//   100  = loader module missing -> SKIP
//   101  = no physical device -> SKIP
//   102  = no graphics queue family -> SKIP
//   1..9 = probe step failures -> FAIL

#define VMA_STATIC_VULKAN_FUNCTIONS 0
#define VMA_DYNAMIC_VULKAN_FUNCTIONS 1
#define VMA_IMPLEMENTATION
#include "../vendor/vk_mem_alloc.h"

#include <windows.h>
#include <cstring>

namespace {

struct Cleanup {
  VmaAllocator allocator;
  VkDevice device;
  VkInstance instance;
  PFN_vkDestroyInstance destroy_instance;
  PFN_vkDestroyDevice destroy_device;
};

struct ProbeResult {
  int rc;      // 0 = success; 100/101/102 = SKIP; 1..9 = FAIL step
  int heap;    // memory heap count
  int size;    // allocation size in bytes
  int verify;  // 1 when the mapped write/read-back pattern verified
};

void cleanup_all(Cleanup* c) {
  if (c->allocator != 0) vmaDestroyAllocator(c->allocator);
  if (c->device != 0 && c->destroy_device != 0) c->destroy_device(c->device, 0);
  if (c->instance != 0 && c->destroy_instance != 0) c->destroy_instance(c->instance, 0);
}

ProbeResult run_probe(const char* dll_name) {
  ProbeResult r = {};
  r.rc = 1;

  HMODULE mod = LoadLibraryA(dll_name);
  if (mod == 0) {
    r.rc = 100;
    return r;
  }
  PFN_vkGetInstanceProcAddr gipa =
      (PFN_vkGetInstanceProcAddr)(void*)GetProcAddress(mod, "vkGetInstanceProcAddr");
  if (gipa == 0) {
    FreeLibrary(mod);
    r.rc = 100;
    return r;
  }

  Cleanup c = {};

  PFN_vkCreateInstance create_instance =
      (PFN_vkCreateInstance)gipa(VK_NULL_HANDLE, "vkCreateInstance");
  if (create_instance == 0) {
    FreeLibrary(mod);
    r.rc = 2;
    return r;
  }

  VkApplicationInfo app_info = { VK_STRUCTURE_TYPE_APPLICATION_INFO };
  app_info.apiVersion = VK_API_VERSION_1_0;
  VkInstanceCreateInfo instance_info = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
  instance_info.pApplicationInfo = &app_info;
  if (create_instance(&instance_info, 0, &c.instance) != VK_SUCCESS) {
    FreeLibrary(mod);
    r.rc = 2;
    return r;
  }
  c.destroy_instance = (PFN_vkDestroyInstance)gipa(c.instance, "vkDestroyInstance");

  PFN_vkEnumeratePhysicalDevices enumerate_devices =
      (PFN_vkEnumeratePhysicalDevices)gipa(c.instance, "vkEnumeratePhysicalDevices");
  if (enumerate_devices == 0) {
    cleanup_all(&c);
    FreeLibrary(mod);
    r.rc = 3;
    return r;
  }
  uint32_t device_count = 0;
  if (enumerate_devices(c.instance, &device_count, 0) != VK_SUCCESS || device_count == 0) {
    cleanup_all(&c);
    FreeLibrary(mod);
    r.rc = 101;
    return r;
  }
  VkPhysicalDevice devices[8] = {};
  uint32_t n = device_count < 8 ? device_count : 8;
  if (enumerate_devices(c.instance, &n, devices) != VK_SUCCESS || n == 0) {
    cleanup_all(&c);
    FreeLibrary(mod);
    r.rc = 101;
    return r;
  }

  PFN_vkGetPhysicalDeviceQueueFamilyProperties get_queue_props =
      (PFN_vkGetPhysicalDeviceQueueFamilyProperties)gipa(c.instance, "vkGetPhysicalDeviceQueueFamilyProperties");
  PFN_vkCreateDevice create_device = (PFN_vkCreateDevice)gipa(c.instance, "vkCreateDevice");
  if (get_queue_props == 0 || create_device == 0) {
    cleanup_all(&c);
    FreeLibrary(mod);
    r.rc = 3;
    return r;
  }

  // First physical device with a graphics-capable queue family.
  VkPhysicalDevice physical = VK_NULL_HANDLE;
  uint32_t queue_family = UINT32_MAX;
  for (uint32_t i = 0; i < n && physical == VK_NULL_HANDLE; i++) {
    uint32_t qcount = 0;
    get_queue_props(devices[i], &qcount, 0);
    VkQueueFamilyProperties props[32] = {};
    uint32_t qn = qcount < 32 ? qcount : 32;
    get_queue_props(devices[i], &qn, props);
    for (uint32_t q = 0; q < qn; q++) {
      if ((props[q].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0) {
        physical = devices[i];
        queue_family = q;
        break;
      }
    }
  }
  if (physical == VK_NULL_HANDLE) {
    cleanup_all(&c);
    FreeLibrary(mod);
    r.rc = 102;
    return r;
  }

  float priority = 1.0f;
  VkDeviceQueueCreateInfo queue_info = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
  queue_info.queueFamilyIndex = queue_family;
  queue_info.queueCount = 1;
  queue_info.pQueuePriorities = &priority;
  VkDeviceCreateInfo device_info = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
  device_info.queueCreateInfoCount = 1;
  device_info.pQueueCreateInfos = &queue_info;
  if (create_device(physical, &device_info, 0, &c.device) != VK_SUCCESS) {
    cleanup_all(&c);
    FreeLibrary(mod);
    r.rc = 4;
    return r;
  }
  c.destroy_device = (PFN_vkDestroyDevice)gipa(c.instance, "vkDestroyDevice");

  PFN_vkGetDeviceProcAddr gdpa = (PFN_vkGetDeviceProcAddr)gipa(c.instance, "vkGetDeviceProcAddr");
  if (gdpa == 0) {
    cleanup_all(&c);
    FreeLibrary(mod);
    r.rc = 3;
    return r;
  }

  VmaVulkanFunctions vulkan_functions = {};
  vulkan_functions.vkGetInstanceProcAddr = gipa;
  vulkan_functions.vkGetDeviceProcAddr = gdpa;

  VmaAllocatorCreateInfo allocator_info = {};
  allocator_info.physicalDevice = physical;
  allocator_info.device = c.device;
  allocator_info.instance = c.instance;
  allocator_info.vulkanApiVersion = VK_API_VERSION_1_0;
  allocator_info.pVulkanFunctions = &vulkan_functions;
  if (vmaCreateAllocator(&allocator_info, &c.allocator) != VK_SUCCESS) {
    cleanup_all(&c);
    FreeLibrary(mod);
    r.rc = 5;
    return r;
  }

  const VkPhysicalDeviceMemoryProperties* memory_properties = 0;
  vmaGetMemoryProperties(c.allocator, &memory_properties);
  r.heap = memory_properties != 0 ? (int)memory_properties->memoryHeapCount : 0;

  VkBufferCreateInfo buffer_info = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
  buffer_info.size = 65536;
  buffer_info.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
  VmaAllocationCreateInfo allocation_info = {};
  allocation_info.usage = VMA_MEMORY_USAGE_AUTO;
  allocation_info.flags = VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
  VkBuffer buffer = VK_NULL_HANDLE;
  VmaAllocation allocation = VK_NULL_HANDLE;
  VmaAllocationInfo allocation_result = {};
  if (vmaCreateBuffer(c.allocator, &buffer_info, &allocation_info, &buffer, &allocation,
                      &allocation_result) != VK_SUCCESS) {
    cleanup_all(&c);
    FreeLibrary(mod);
    r.rc = 6;
    return r;
  }
  r.size = (int)allocation_result.size;

  void* mapped = 0;
  if (vmaMapMemory(c.allocator, allocation, &mapped) != VK_SUCCESS || mapped == 0) {
    vmaDestroyBuffer(c.allocator, buffer, allocation);
    cleanup_all(&c);
    FreeLibrary(mod);
    r.rc = 7;
    return r;
  }
  unsigned char* bytes = (unsigned char*)mapped;
  for (int i = 0; i < 4096; i++) bytes[i] = (unsigned char)(i & 0xFF);
  int verify = 1;
  for (int i = 0; i < 4096; i++) {
    if (bytes[i] != (unsigned char)(i & 0xFF)) {
      verify = 0;
      break;
    }
  }
  vmaUnmapMemory(c.allocator, allocation);
  r.verify = verify;

  vmaDestroyBuffer(c.allocator, buffer, allocation);
  cleanup_all(&c);
  FreeLibrary(mod);
  r.rc = 0;
  return r;
}

} // namespace

extern "C" {

// Packed probe (the supported path): (heap << 20) | (verify << 28) | size;
// a negative return is `-classification_code`.
int vmaprobe_run_packed(void) {
  ProbeResult r = run_probe("vulkan-1.dll");
  if (r.rc != 0) return -r.rc;
  return (r.heap << 20) | (r.verify << 28) | (r.size & 0xFFFFF);
}

int vmaprobe_run_packed_named(const char* dll_name) {
  if (dll_name == 0) return -1;
  ProbeResult r = run_probe(dll_name);
  if (r.rc != 0) return -r.rc;
  return (r.heap << 20) | (r.verify << 28) | (r.size & 0xFFFFF);
}

// Out-param slot variants: kept as the finding B-11 reproduction (slot
// memory written by this call was observed recycled before the caller could
// read it under the v0.64.2 runtime; see docs/repro/bindings-pilot/).
int vmaprobe_run(int* out_heap_count, int* out_alloc_size, int* out_verify) {
  ProbeResult r = run_probe("vulkan-1.dll");
  if (out_heap_count != 0) *out_heap_count = r.heap;
  if (out_alloc_size != 0) *out_alloc_size = r.size;
  if (out_verify != 0) *out_verify = r.verify;
  return r.rc;
}

int vmaprobe_run_named(const char* dll_name, int* out_heap_count, int* out_alloc_size,
                       int* out_verify) {
  if (dll_name == 0) return 1;
  ProbeResult r = run_probe(dll_name);
  if (out_heap_count != 0) *out_heap_count = r.heap;
  if (out_alloc_size != 0) *out_alloc_size = r.size;
  if (out_verify != 0) *out_verify = r.verify;
  return r.rc;
}

} // extern "C"
