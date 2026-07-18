#ifndef XVK_COMMAND_H_
#define XVK_COMMAND_H_

#include <stdint.h>
#include "xvk_types.h"
#include "xvk_util.h"

void xvk_app_cmd_bind_vertex_buffer(int64_t app_h, int32_t binding, int64_t buf_h, int64_t offset);
void xvk_app_cmd_bind_index_buffer(int64_t app_h, int64_t buf_h, int64_t offset, int32_t index_type);
void xvk_app_cmd_bind_pipeline(int64_t app_h, int64_t pipeline_h);
void xvk_app_cmd_bind_descriptor_sets(int64_t app_h, int64_t layout_h, int32_t first_set,
                                   const int64_t* sets, int32_t set_count);
void xvk_app_cmd_push_constants(int64_t app_h, int64_t layout_h, int32_t stages,
                             int32_t offset, int32_t size, const void* data);
void xvk_app_cmd_draw_indexed(int64_t app_h, int32_t index_count, int32_t instance_count,
                           int32_t first_index, int32_t vertex_offset, int32_t first_instance);
void xvk_app_cmd_draw(int64_t app_h, int32_t vertex_count, int32_t instance_count,
                   int32_t first_vertex, int32_t first_instance);
int32_t xvk_begin_custom_pass(int64_t app_h, int64_t render_pass_h, int64_t framebuffer_h,
                               int32_t width, int32_t height,
                               float r, float g, float b);
int32_t xvk_end_custom_pass(int64_t app_h);
void xvk_image_transition(int64_t app_h, int64_t img_h, int32_t old_layout, int32_t new_layout);
void xvk_get_framebuffer_size(int64_t app_h, int32_t* out_width, int32_t* out_height);

#endif
