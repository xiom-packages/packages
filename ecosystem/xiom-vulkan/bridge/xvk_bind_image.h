#ifndef XVK_BIND_IMAGE_H_
#define XVK_BIND_IMAGE_H_

#include <stdint.h>

/*
 * Direct VkImage / VkImageView / VkSampler bindings.
 *
 * Create-info structs are built XIOM-side with the xvk_structs marshalling
 * layer (xvk_alloc + xvk_write_*) using the exact Vulkan struct layout.
 * The sType field is enforced C-side before each call. All handles are
 * int64_t values holding raw pointers / Vulkan handles (0 = NULL/invalid).
 */

/* vkCreateImage. create_info_struct: VkImageCreateInfo*. Returns VkImage or 0. */
int64_t xvk_create_image(int64_t device, int64_t create_info_struct);

/* vkDestroyImage. */
void xvk_destroy_image(int64_t device, int64_t image);

/* vkBindImageMemory. Returns VkResult. */
int32_t xvk_bind_image_memory(int64_t device, int64_t image, int64_t memory, int64_t offset);

/* vkGetImageMemoryRequirements. out_reqs: VkMemoryRequirements* (24 bytes:
   size u64 @0, alignment u64 @8, memoryTypeBits u32 @16). */
void xvk_get_image_memory_requirements(int64_t device, int64_t image, int64_t out_reqs);

/* vkCreateImageView. create_info_struct: VkImageViewCreateInfo*. Returns VkImageView or 0. */
int64_t xvk_create_image_view(int64_t device, int64_t create_info_struct);

/* vkDestroyImageView. */
void xvk_destroy_image_view(int64_t device, int64_t view);

/* vkCreateSampler. create_info_struct: VkSamplerCreateInfo*. Returns VkSampler or 0. */
int64_t xvk_create_sampler(int64_t device, int64_t create_info_struct);

/* vkDestroySampler. */
void xvk_destroy_sampler(int64_t device, int64_t sampler);

#endif
