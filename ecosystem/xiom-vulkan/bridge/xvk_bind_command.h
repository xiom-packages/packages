#ifndef XVK_BIND_COMMAND_H_
#define XVK_BIND_COMMAND_H_

#include <stdint.h>

/*
 * Flat command-buffer bindings for the XIOM <-> Vulkan FFI boundary.
 *
 * All handles are raw Vulkan handles carried in int64_t (0 = VK_NULL_HANDLE).
 * All *_struct / *_structs parameters are int64_t pointers to Vulkan structs
 * (or arrays of structs) built XIOM-side via the xvk_structs marshalling API.
 * Array-of-handle parameters (events, buffers, sets, command_buffers) point
 * to arrays of int64_t handles, which are layout-compatible with Vulkan
 * handle arrays on 64-bit targets.
 *
 * int32_t returns are raw VkResult values; vkCmd* functions return void and
 * report parameter validation failures via xvk_set_error_fmt.
 *
 * Query commands (begin/end query, write timestamp, reset pool, copy
 * results) live in xvk_bind_query.h; EXT/KHR extension commands live in
 * xvk_bind_extensions.h.
 */

/* ---- Command pool / command buffer lifecycle ---- */
int64_t xvk_create_command_pool(int64_t device, int64_t create_info_struct);
void xvk_destroy_command_pool(int64_t device, int64_t pool);
int32_t xvk_reset_command_pool(int64_t device, int64_t pool, int32_t flags);
int32_t xvk_trim_command_pool(int64_t device, int64_t pool);
int64_t xvk_create_command_pools(int32_t count, int64_t device, int32_t queue_family, int32_t flags, int64_t out_pools_array);
int32_t xvk_allocate_command_buffers(int64_t device, int64_t allocate_info_struct, int64_t out_buffers);
int32_t xvk_allocate_command_buffers_multi(int64_t device, int64_t pool, int32_t level, int32_t count, int64_t out_buffers);
void xvk_free_command_buffers(int64_t device, int64_t pool, int32_t count, int64_t buffers);
int32_t xvk_begin_command_buffer(int64_t cmd_buf, int64_t begin_info_struct);
int32_t xvk_end_command_buffer(int64_t cmd_buf);

/* ---- Bind / draw / dispatch ---- */
void xvk_cmd_bind_pipeline(int64_t cmd_buf, int32_t bind_point, int64_t pipeline);
void xvk_cmd_draw(int64_t cmd_buf, int32_t vertex_count, int32_t instance_count, int32_t first_vertex, int32_t first_instance);
void xvk_cmd_draw_indexed(int64_t cmd_buf, int32_t index_count, int32_t instance_count, int32_t first_index, int32_t vertex_offset, int32_t first_instance);
void xvk_cmd_draw_indirect(int64_t cmd_buf, int64_t buffer, int64_t offset, int32_t draw_count, int32_t stride);
void xvk_cmd_dispatch(int64_t cmd_buf, int32_t x, int32_t y, int32_t z);
void xvk_cmd_bind_vertex_buffers(int64_t cmd_buf, int32_t first_binding, int32_t count, int64_t buffers, int64_t offsets);
void xvk_cmd_bind_index_buffer(int64_t cmd_buf, int64_t buffer, int64_t offset, int32_t index_type);
void xvk_cmd_bind_descriptor_sets(int64_t cmd_buf, int32_t bind_point, int64_t layout, int32_t first_set, int32_t count, int64_t sets, int32_t dynamic_offset_count, int64_t dynamic_offsets);
void xvk_cmd_push_constants(int64_t cmd_buf, int64_t layout, int32_t stage_flags, int32_t offset, int32_t size, int64_t data);

/* ---- Barriers / render passes / dynamic rendering ---- */
void xvk_cmd_pipeline_barrier(int64_t cmd_buf, int32_t src_stage, int32_t dst_stage, int32_t dep_flags, int32_t mem_barrier_count, int64_t mem_barriers, int32_t buf_barrier_count, int64_t buf_barriers, int32_t img_barrier_count, int64_t img_barriers);
void xvk_cmd_begin_render_pass(int64_t cmd_buf, int64_t begin_info_struct, int32_t contents);
void xvk_cmd_end_render_pass(int64_t cmd_buf);
void xvk_cmd_begin_rendering(int64_t cmd_buf, int64_t rendering_info_struct);
void xvk_cmd_end_rendering(int64_t cmd_buf);

/* ---- Buffer <-> image copies / blit ---- */
void xvk_cmd_copy_buffer(int64_t cmd_buf, int64_t src, int64_t dst, int32_t region_count, int64_t regions_struct);
void xvk_cmd_copy_buffer_to_image(int64_t cmd_buf, int64_t src, int64_t dst, int32_t dst_layout, int32_t region_count, int64_t regions_struct);
void xvk_cmd_blit_image(int64_t cmd_buf, int64_t src, int32_t src_layout, int64_t dst, int32_t dst_layout, int32_t region_count, int64_t regions_struct, int32_t filter);

/* ---- Copy / clear operations ---- */
void xvk_cmd_copy_image(int64_t cb, int64_t src, int32_t src_layout, int64_t dst, int32_t dst_layout, int32_t region_count, int64_t regions_struct);
void xvk_cmd_copy_image_to_buffer(int64_t cb, int64_t src, int32_t src_layout, int64_t dst, int32_t region_count, int64_t regions_struct);
void xvk_cmd_update_buffer(int64_t cb, int64_t dst, int64_t dst_offset, int64_t data_size, int64_t data);
void xvk_cmd_fill_buffer(int64_t cb, int64_t dst, int64_t dst_offset, int64_t size, int32_t data);
void xvk_cmd_clear_color_image(int64_t cb, int64_t image, int32_t image_layout, int64_t color_struct, int32_t range_count, int64_t ranges_struct);
void xvk_cmd_clear_depth_stencil_image(int64_t cb, int64_t image, int32_t image_layout, int64_t depth_stencil_struct, int32_t range_count, int64_t ranges_struct);
void xvk_cmd_clear_attachments(int64_t cb, int32_t attachment_count, int64_t attachments_struct, int32_t rect_count, int64_t rects_struct);
void xvk_cmd_resolve_image(int64_t cb, int64_t src, int32_t src_layout, int64_t dst, int32_t dst_layout, int32_t region_count, int64_t regions_struct);

/* ---- Dispatch (indirect / base) ---- */
void xvk_cmd_dispatch_indirect(int64_t cb, int64_t buffer, int64_t offset);
void xvk_cmd_dispatch_base(int64_t cb, int32_t base_x, int32_t base_y, int32_t base_z, int32_t group_x, int32_t group_y, int32_t group_z);

/* ---- Synchronization2 (core 1.3); stage masks limited to the low 32 bits ---- */
void xvk_cmd_pipeline_barrier2(int64_t cb, int64_t dependency_info_struct);
void xvk_cmd_set_event2(int64_t cb, int64_t event, int64_t dependency_info_struct);
void xvk_cmd_reset_event2(int64_t cb, int64_t event, int32_t stage_mask);
void xvk_cmd_wait_events2(int64_t cb, int32_t event_count, int64_t events, int64_t dependency_infos_struct);

/* ---- Dynamic state (core 1.0) ---- */
void xvk_cmd_set_viewport(int64_t cb, int32_t first, int32_t count, int64_t viewports_struct);
void xvk_cmd_set_scissor(int64_t cb, int32_t first, int32_t count, int64_t scissors_struct);
void xvk_cmd_set_line_width(int64_t cb, float width);
void xvk_cmd_set_depth_bias(int64_t cb, float constant_factor, float clamp, float slope_factor);
void xvk_cmd_set_blend_constants(int64_t cb, float constants[4]);
void xvk_cmd_set_depth_bounds(int64_t cb, float min, float max);
void xvk_cmd_set_stencil_compare_mask(int64_t cb, int32_t face_mask, int32_t compare_mask);
void xvk_cmd_set_stencil_write_mask(int64_t cb, int32_t face_mask, int32_t write_mask);
void xvk_cmd_set_stencil_reference(int64_t cb, int32_t face_mask, int32_t reference);

/* ---- Events (core 1.0) ---- */
void xvk_cmd_set_event(int64_t cb, int64_t event, int32_t stage_mask);
void xvk_cmd_reset_event(int64_t cb, int64_t event, int32_t stage_mask);
void xvk_cmd_wait_events(int64_t cb, int32_t event_count, int64_t events, int32_t src_stage_mask, int32_t dst_stage_mask, int32_t memory_barrier_count, int64_t memory_barriers_struct, int32_t buffer_barrier_count, int64_t buffer_barriers_struct, int32_t image_barrier_count, int64_t image_barriers_struct);

/* ---- Device mask / multi-GPU (core 1.1) ---- */
void xvk_cmd_set_device_mask(int64_t cb, int32_t device_mask);

/* ---- Secondary command buffers / render pass 2 (core 1.0 / 1.2) ---- */
void xvk_cmd_execute_commands(int64_t cb, int32_t command_buffer_count, int64_t command_buffers);
void xvk_cmd_begin_render_pass2(int64_t cb, int64_t begin_info_struct, int64_t subpass_begin_info_struct);
void xvk_cmd_next_subpass(int64_t cb, int32_t contents);
void xvk_cmd_next_subpass2(int64_t cb, int64_t subpass_begin_info_struct, int64_t subpass_end_info_struct);
void xvk_cmd_end_render_pass2(int64_t cb, int64_t subpass_end_info_struct);

/* ---- Descriptor / push constant info structs (core 1.4, maintenance6) ---- */
void xvk_cmd_bind_descriptor_sets2(int64_t cb, int64_t bind_info_struct);
void xvk_cmd_push_constants2(int64_t cb, int64_t push_constants_info_struct);

/* ---- Indirect draw count (core 1.2) ---- */
void xvk_cmd_draw_indirect_count(int64_t cb, int64_t buffer, int64_t offset, int64_t count_buffer, int64_t count_offset, int32_t max_draw_count, int32_t stride);
void xvk_cmd_draw_indexed_indirect_count(int64_t cb, int64_t buffer, int64_t offset, int64_t count_buffer, int64_t count_offset, int32_t max_draw_count, int32_t stride);

/* ---- Queries: see xvk_bind_query.h ---- */

/* ---- Buffer device address (core 1.2) ---- */
int64_t xvk_get_buffer_device_address(int64_t device, int64_t buffer_device_address_info_struct);
int64_t xvk_get_buffer_opaque_capture_address(int64_t device, int64_t buffer_device_address_info_struct);
int64_t xvk_get_device_memory_opaque_capture_address(int64_t device, int64_t memory_opaque_capture_address_info_struct);

#endif
