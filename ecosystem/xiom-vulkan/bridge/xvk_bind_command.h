#ifndef XVK_BIND_COMMAND_H_
#define XVK_BIND_COMMAND_H_

#include <stdint.h>

int64_t xvk_create_command_pool(int64_t device, int64_t create_info_struct);
void xvk_destroy_command_pool(int64_t device, int64_t pool);
int32_t xvk_reset_command_pool(int64_t device, int64_t pool, int32_t flags);
int32_t xvk_allocate_command_buffers(int64_t device, int64_t allocate_info_struct, int64_t out_buffers);
void xvk_free_command_buffers(int64_t device, int64_t pool, int32_t count, int64_t buffers);
int32_t xvk_begin_command_buffer(int64_t cmd_buf, int64_t begin_info_struct);
int32_t xvk_end_command_buffer(int64_t cmd_buf);
void xvk_cmd_bind_pipeline(int64_t cmd_buf, int32_t bind_point, int64_t pipeline);
void xvk_cmd_draw(int64_t cmd_buf, int32_t vertex_count, int32_t instance_count, int32_t first_vertex, int32_t first_instance);
void xvk_cmd_draw_indexed(int64_t cmd_buf, int32_t index_count, int32_t instance_count, int32_t first_index, int32_t vertex_offset, int32_t first_instance);
void xvk_cmd_draw_indirect(int64_t cmd_buf, int64_t buffer, int64_t offset, int32_t draw_count, int32_t stride);
void xvk_cmd_dispatch(int64_t cmd_buf, int32_t x, int32_t y, int32_t z);
void xvk_cmd_bind_vertex_buffers(int64_t cmd_buf, int32_t first_binding, int32_t count, int64_t buffers, int64_t offsets);
void xvk_cmd_bind_index_buffer(int64_t cmd_buf, int64_t buffer, int64_t offset, int32_t index_type);
void xvk_cmd_bind_descriptor_sets(int64_t cmd_buf, int32_t bind_point, int64_t layout, int32_t first_set, int32_t count, int64_t sets, int32_t dynamic_offset_count, int64_t dynamic_offsets);
void xvk_cmd_push_constants(int64_t cmd_buf, int64_t layout, int32_t stage_flags, int32_t offset, int32_t size, int64_t data);
void xvk_cmd_pipeline_barrier(int64_t cmd_buf, int32_t src_stage, int32_t dst_stage, int32_t dep_flags, int32_t mem_barrier_count, int64_t mem_barriers, int32_t buf_barrier_count, int64_t buf_barriers, int32_t img_barrier_count, int64_t img_barriers);
void xvk_cmd_begin_render_pass(int64_t cmd_buf, int64_t begin_info_struct, int32_t contents);
void xvk_cmd_end_render_pass(int64_t cmd_buf);
void xvk_cmd_begin_rendering(int64_t cmd_buf, int64_t rendering_info_struct);
void xvk_cmd_end_rendering(int64_t cmd_buf);
void xvk_cmd_copy_buffer(int64_t cmd_buf, int64_t src, int64_t dst, int32_t region_count, int64_t regions_struct);
void xvk_cmd_copy_buffer_to_image(int64_t cmd_buf, int64_t src, int64_t dst, int32_t dst_layout, int32_t region_count, int64_t regions_struct);
void xvk_cmd_blit_image(int64_t cmd_buf, int64_t src, int32_t src_layout, int64_t dst, int32_t dst_layout, int32_t region_count, int64_t regions_struct, int32_t filter);

#endif
