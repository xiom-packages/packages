#ifndef XVK_TEXTURE_H_
#define XVK_TEXTURE_H_

#include <stdint.h>

/*
 * Phase 7.4: Texture loading pipeline.
 *
 * Provides a self-contained texture upload pipeline that:
 *   1. Creates a staging buffer and copies pixel data from CPU memory
 *   2. Creates a device-local GPU image with TRANSFER_DST|SAMPLED usage
 *   3. Records a one-shot command buffer: layout transition → copy → transition
 *   4. Optionally generates mipmaps via vkCmdBlitImage
 *   5. Creates an image view and default sampler
 *
 * All VkImage / VkImageView / VkSampler / VkDeviceMemory handles are managed
 * internally. The caller receives a handle that can be queried for individual
 * sub-resource handles.
 *
 * Texture format is RGBA8 UNORM by default. Pixel data must be 4 bytes per
 * pixel (width * height * 4 bytes total).
 */

/* Create a texture from raw RGBA8 pixel data.
 * device:          VkDevice handle
 * physical_device: VkPhysicalDevice handle (for memory type selection)
 * cmd_pool:        VkCommandPool handle (for recording upload commands)
 * queue:           VkQueue handle (graphics queue for submit)
 * pixel_data:      pointer to RGBA8 pixel bytes (width * height * 4)
 * width, height:   image dimensions in pixels
 * generate_mips:   1 = generate full mip chain, 0 = single mip level
 * Returns: texture handle (> 0), or 0 on failure. */
int64_t xvk_texture_create(int64_t device, int64_t physical_device,
                           int64_t cmd_pool, int64_t queue,
                           int64_t pixel_data,
                           int32_t width, int32_t height,
                           int32_t generate_mips);

/* Get sub-resource handles from a texture. Returns 0 if texture is invalid. */
int64_t xvk_texture_get_image(int64_t texture);
int64_t xvk_texture_get_image_view(int64_t texture);
int64_t xvk_texture_get_sampler(int64_t texture);
int32_t xvk_texture_get_width(int64_t texture);
int32_t xvk_texture_get_height(int64_t texture);
int32_t xvk_texture_get_mip_levels(int64_t texture);

/* Destroy all resources associated with the texture. No-op on 0. */
void xvk_texture_destroy(int64_t device, int64_t texture);

#endif
