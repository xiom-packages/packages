#ifndef XVK_DESCRIPTOR_H_
#define XVK_DESCRIPTOR_H_

#include <stdint.h>
#include "xvk_types.h"
#include "xvk_util.h"

int64_t xvk_desc_set_layout_create(int64_t app_h, const int32_t* bindings, int32_t count);
void xvk_desc_set_layout_destroy(int64_t app_h, int64_t layout_h);
int64_t xvk_desc_pool_create(int64_t app_h, const int32_t* pool_sizes, int32_t size_count,
                              int32_t max_sets);
void xvk_desc_pool_destroy(int64_t app_h, int64_t pool_h);
int64_t xvk_desc_set_allocate(int64_t app_h, int64_t pool_h, int64_t layout_h);
void xvk_desc_set_free(int64_t app_h, int64_t pool_h, int64_t set_h);
void xvk_desc_set_write_buffer(int64_t app_h, int64_t set_h, int32_t binding,
                                int64_t buf_h, int64_t offset, int64_t range,
                                int32_t type);
void xvk_desc_set_write_image(int64_t app_h, int64_t set_h, int32_t binding,
                               int64_t sampler_h, int64_t image_view_h);

#endif
