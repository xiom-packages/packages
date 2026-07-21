#ifndef XVK_BUFFER_H_
#define XVK_BUFFER_H_

#include <stdint.h>
#include "xvk_types.h"
#include "xvk_util.h"

int64_t xvk_buffer_create(int64_t app_h, int64_t size, int32_t usage, int32_t memory);
void xvk_buffer_destroy(int64_t app_h, int64_t buf_h);
int64_t xvk_buffer_size(int64_t app_h, int64_t buf_h);
int64_t xvk_buffer_map(int64_t app_h, int64_t buf_h);
void xvk_buffer_unmap(int64_t app_h, int64_t buf_h);
void xvk_buffer_write(int64_t app_h, int64_t buf_h, int64_t offset,
                       const void* data, int64_t data_size);
void xvk_buffer_read(int64_t app_h, int64_t buf_h, int64_t offset,
                      void* out, int64_t out_size);

int64_t xvk_image_create_2d(int64_t app_h, int32_t width, int32_t height,
                             int32_t format, int32_t usage, int32_t mip_levels);
void xvk_image_destroy(int64_t app_h, int64_t img_h);
int64_t xvk_image_view_create(int64_t app_h, int64_t img_h, int32_t format, int32_t aspect);
void xvk_image_view_destroy(int64_t app_h, int64_t view_h);

int64_t xvk_sampler_create(int64_t app_h, int32_t filter, int32_t address_u,
                            int32_t address_v, int32_t mip_mode, float max_lod);
void xvk_sampler_destroy(int64_t app_h, int64_t sampler_h);

#endif
