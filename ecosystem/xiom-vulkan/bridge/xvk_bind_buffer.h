#ifndef XVK_BIND_BUFFER_H_
#define XVK_BIND_BUFFER_H_

#include <stdint.h>

/*
 * Direct VkBuffer / VkBufferView bindings.
 *
 * Create-info structs are built XIOM-side with the xvk_structs marshalling
 * layer (xvk_alloc + xvk_write_*) using the exact Vulkan struct layout.
 * The sType field is enforced C-side before each call. All handles are
 * int64_t values holding raw pointers / Vulkan handles (0 = NULL/invalid).
 */

/* vkCreateBuffer. create_info_struct: VkBufferCreateInfo*. Returns VkBuffer or 0. */
int64_t xvk_create_buffer(int64_t device, int64_t create_info_struct);

/* vkDestroyBuffer. */
void xvk_destroy_buffer(int64_t device, int64_t buffer);

/* vkBindBufferMemory. Returns VkResult. */
int32_t xvk_bind_buffer_memory(int64_t device, int64_t buffer, int64_t memory, int64_t offset);

/* vkGetBufferMemoryRequirements. out_reqs: VkMemoryRequirements* (24 bytes:
   size u64 @0, alignment u64 @8, memoryTypeBits u32 @16). */
void xvk_get_buffer_memory_requirements(int64_t device, int64_t buffer, int64_t out_reqs);

/* vkCreateBufferView. create_info_struct: VkBufferViewCreateInfo*. Returns VkBufferView or 0. */
int64_t xvk_create_buffer_view(int64_t device, int64_t create_info_struct);

/* vkDestroyBufferView. */
void xvk_destroy_buffer_view(int64_t device, int64_t view);

#endif
