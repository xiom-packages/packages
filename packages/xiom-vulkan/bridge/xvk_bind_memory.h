#ifndef XVK_BIND_MEMORY_H_
#define XVK_BIND_MEMORY_H_

#include <stdint.h>

/*
 * Direct VkDeviceMemory bindings.
 *
 * Allocate-info structs are built XIOM-side with the xvk_structs marshalling
 * layer (xvk_alloc + xvk_write_*) using the exact Vulkan struct layout.
 * The sType field is enforced C-side before each call. All handles are
 * int64_t values holding raw pointers / Vulkan handles (0 = NULL/invalid).
 */

/* vkAllocateMemory. allocate_info_struct: VkMemoryAllocateInfo*. Returns VkDeviceMemory or 0. */
int64_t xvk_allocate_memory(int64_t device, int64_t allocate_info_struct);

/* vkFreeMemory. */
void xvk_free_memory(int64_t device, int64_t memory);

/* vkMapMemory. size -1 maps VK_WHOLE_SIZE. out_data: u64 slot receiving the
   mapped pointer. Returns VkResult. */
int32_t xvk_map_memory(int64_t device, int64_t memory, int64_t offset, int64_t size, int32_t flags, int64_t out_data);

/* vkUnmapMemory. */
void xvk_unmap_memory(int64_t device, int64_t memory);

/* vkFlushMappedMemoryRanges. ranges_struct: VkMappedMemoryRange[count] (40 bytes
   each: sType u32 @0, pNext u64 @8, memory u64 @16, offset u64 @24, size u64 @32).
   Returns VkResult. */
int32_t xvk_flush_mapped_memory_ranges(int64_t device, int32_t count, int64_t ranges_struct);

/* vkInvalidateMappedMemoryRanges. Same layout as flush. Returns VkResult. */
int32_t xvk_invalidate_mapped_memory_ranges(int64_t device, int32_t count, int64_t ranges_struct);

#endif
