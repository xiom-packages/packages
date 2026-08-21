#ifndef XVK_BIND_EXTENSIONS_H_
#define XVK_BIND_EXTENSIONS_H_

#include <stdint.h>
#include "xvk_types.h"
#include "xvk_util.h"

/*
 * Extension bindings -- every VK extension entry point not covered by the
 * core xvk_bind_* modules. All functions are resolved at runtime through
 * vkGetInstanceProcAddr / vkGetDeviceProcAddr and cached in static
 * function pointers (with automatic fallback to the core-promoted name
 * where one exists, e.g. vkCmdSetCullModeEXT -> vkCmdSetCullMode).
 *
 * Handles are raw VK handles carried in int64_t (0 = NULL). *_struct
 * parameters are raw pointers to fully-built VK structs (see xvk_structs.h).
 *
 * Call xvk_ext_load_instance() after instance creation and
 * xvk_ext_load_device() after device creation so command-buffer/queue
 * level wrappers can resolve their entry points. Functions that receive
 * an instance/device parameter self-register on first use.
 */

/* Loader registration */
void xvk_ext_load_instance(int64_t instance);
void xvk_ext_load_device(int64_t device);

/* VK_EXT_debug_utils */
int32_t xvk_create_debug_utils_messenger_ext(int64_t instance, int64_t create_info_struct);
void xvk_destroy_debug_utils_messenger_ext(int64_t instance, int64_t messenger);
void xvk_set_debug_utils_object_name_ext(int64_t device, int64_t name_info_struct);
void xvk_set_debug_utils_object_tag_ext(int64_t device, int64_t tag_info_struct);
void xvk_queue_begin_debug_utils_label_ext(int64_t queue, int64_t label_info_struct);
void xvk_queue_end_debug_utils_label_ext(int64_t queue);
void xvk_queue_insert_debug_utils_label_ext(int64_t queue, int64_t label_info_struct);
void xvk_cmd_begin_debug_utils_label_ext(int64_t cmd_buf, int64_t label_info_struct);
void xvk_cmd_end_debug_utils_label_ext(int64_t cmd_buf);
void xvk_cmd_insert_debug_utils_label_ext(int64_t cmd_buf, int64_t label_info_struct);

/* ---- Phase 8.1: Debug validation message capture ------------------------ */
/* Creates a debug utils messenger with a built-in callback that captures
 * all validation layer messages into a ring buffer (up to 64 messages).
 * severity_mask: VkDebugUtilsMessageSeverityFlagsEXT (e.g. 0x0000000F for all)
 * type_mask:     VkDebugUtilsMessageTypeFlagsEXT (e.g. 0x0000001F for all)
 * Returns messenger handle on success, 0 on failure. */
int64_t xvk_create_debug_messenger_default(int64_t instance,
                                            int32_t severity_mask,
                                            int32_t type_mask);

/* Query the captured validation message ring buffer.
 * count: receives number of messages currently buffered (0-64).
 * out_buffer: pre-allocated char* array (count * 8 bytes), receives pointers
 *             to NUL-terminated message strings. Strings remain valid until
 *             the next call to xvk_validation_clear() or this function.
 * Returns: number of messages written to out_buffer. */
int32_t xvk_get_validation_messages(int64_t out_count, int64_t out_buffer);

/* Clear the validation message ring buffer. */
void xvk_clear_validation_messages(void);

/* VK_EXT_mesh_shader */
void xvk_cmd_draw_mesh_tasks_ext(int64_t cmd_buf, int32_t group_count_x, int32_t group_count_y, int32_t group_count_z);
void xvk_cmd_draw_mesh_tasks_indirect_ext(int64_t cmd_buf, int64_t buffer, int64_t offset, int32_t draw_count, int32_t stride);
void xvk_cmd_draw_mesh_tasks_indirect_count_ext(int64_t cmd_buf, int64_t buffer, int64_t offset, int64_t count_buffer, int64_t count_offset, int32_t max_draw_count, int32_t stride);

/* VK_EXT_extended_dynamic_state / 2 / 3 + VK_EXT_color_write_enable */
void xvk_cmd_set_cull_mode_ext(int64_t cmd_buf, int32_t cull_mode);
void xvk_cmd_set_front_face_ext(int64_t cmd_buf, int32_t front_face);
void xvk_cmd_set_primitive_topology_ext(int64_t cmd_buf, int32_t topology);
void xvk_cmd_set_viewport_with_count_ext(int64_t cmd_buf, int32_t count, int64_t viewports_struct);
void xvk_cmd_set_scissor_with_count_ext(int64_t cmd_buf, int32_t count, int64_t scissors_struct);
void xvk_cmd_set_depth_test_enable_ext(int64_t cmd_buf, int32_t enable);
void xvk_cmd_set_depth_write_enable_ext(int64_t cmd_buf, int32_t enable);
void xvk_cmd_set_depth_compare_op_ext(int64_t cmd_buf, int32_t compare_op);
void xvk_cmd_set_stencil_test_enable_ext(int64_t cmd_buf, int32_t enable);
void xvk_cmd_set_stencil_op_ext(int64_t cmd_buf, int32_t face_mask, int32_t fail_op, int32_t pass_op, int32_t depth_fail_op, int32_t compare_op);
void xvk_cmd_set_rasterizer_discard_enable_ext(int64_t cmd_buf, int32_t enable);
void xvk_cmd_set_depth_bias_enable_ext(int64_t cmd_buf, int32_t enable);
void xvk_cmd_set_primitive_restart_enable_ext(int64_t cmd_buf, int32_t enable);
void xvk_cmd_set_color_write_enable_ext(int64_t cmd_buf, int32_t count, int64_t enables);
void xvk_cmd_set_logic_op_ext(int64_t cmd_buf, int32_t logic_op);
void xvk_cmd_set_polygon_mode_ext(int64_t cmd_buf, int32_t polygon_mode);
void xvk_cmd_set_rasterization_samples_ext(int64_t cmd_buf, int32_t samples);
void xvk_cmd_set_sample_mask_ext(int64_t cmd_buf, int32_t sample_mask);
void xvk_cmd_set_alpha_to_coverage_enable_ext(int64_t cmd_buf, int32_t enable);
void xvk_cmd_set_color_blend_enable_ext(int64_t cmd_buf, int32_t first, int32_t count, int64_t enables);
void xvk_cmd_set_color_blend_equation_ext(int64_t cmd_buf, int32_t first, int32_t count, int64_t equations_struct);
void xvk_cmd_set_color_write_mask_ext(int64_t cmd_buf, int32_t first, int32_t count, int64_t masks);
void xvk_cmd_set_vertex_input_ext(int64_t cmd_buf, int32_t binding_count, int64_t binding_descs_struct, int32_t attr_count, int64_t attr_descs_struct);

/* VK_EXT_conditional_rendering */
void xvk_cmd_begin_conditional_rendering_ext(int64_t cmd_buf, int64_t conditional_rendering_begin_struct);
void xvk_cmd_end_conditional_rendering_ext(int64_t cmd_buf);

/* VK_EXT_transform_feedback */
void xvk_cmd_bind_transform_feedback_buffers_ext(int64_t cmd_buf, int32_t first_binding, int32_t count, int64_t buffers, int64_t offsets, int64_t sizes);
void xvk_cmd_begin_transform_feedback_ext(int64_t cmd_buf, int32_t first_counter_buffer, int32_t counter_buffer_count, int64_t counter_buffers, int64_t counter_buffer_offsets);
void xvk_cmd_end_transform_feedback_ext(int64_t cmd_buf, int32_t first_counter_buffer, int32_t counter_buffer_count, int64_t counter_buffers, int64_t counter_buffer_offsets);

/* VK_KHR_push_descriptor */
void xvk_cmd_push_descriptor_set_khr(int64_t cmd_buf, int32_t bind_point, int64_t layout, int32_t set, int32_t descriptor_write_count, int64_t descriptor_writes_struct);
void xvk_cmd_push_descriptor_set_with_template_khr(int64_t cmd_buf, int64_t descriptor_update_template, int64_t layout, int32_t set, int64_t data);

/* VK_KHR_fragment_shading_rate */
void xvk_cmd_set_fragment_shading_rate_khr(int64_t cmd_buf, int64_t fragment_size_struct, int32_t combiner_ops[2]);

/* VK_EXT_sample_locations (+ EDS3 enable) */
void xvk_cmd_set_sample_locations_enable_ext(int64_t cmd_buf, int32_t enable);
void xvk_cmd_set_sample_locations_ext(int64_t cmd_buf, int64_t sample_locations_info_struct);

/* VK_EXT_line_rasterization */
void xvk_cmd_set_line_stipple_ext(int64_t cmd_buf, int32_t line_stipple_factor, int16_t line_stipple_pattern);

/* VK_KHR_copy_commands2 */
void xvk_cmd_copy_buffer2_khr(int64_t cmd_buf, int64_t copy_buffer_info_struct);
void xvk_cmd_copy_image2_khr(int64_t cmd_buf, int64_t copy_image_info_struct);
void xvk_cmd_blit_image2_khr(int64_t cmd_buf, int64_t blit_image_info_struct);
void xvk_cmd_copy_buffer_to_image2_khr(int64_t cmd_buf, int64_t copy_buffer_to_image_info_struct);
void xvk_cmd_copy_image_to_buffer2_khr(int64_t cmd_buf, int64_t copy_image_to_buffer_info_struct);
void xvk_cmd_resolve_image2_khr(int64_t cmd_buf, int64_t resolve_image_info_struct);

/* VK_EXT_host_image_copy */
int32_t xvk_copy_memory_to_image_ext(int64_t device, int64_t copy_memory_to_image_info_struct);
int32_t xvk_copy_image_to_memory_ext(int64_t device, int64_t copy_image_to_memory_info_struct);
int32_t xvk_copy_image_to_image_ext(int64_t device, int64_t copy_image_to_image_info_struct);
int32_t xvk_transition_image_layout_ext(int64_t device, int32_t transition_count, int64_t transitions_struct);

/* VK_KHR_timeline_semaphore */
int32_t xvk_get_semaphore_counter_value_khr(int64_t device, int64_t semaphore, int64_t out_value);
int32_t xvk_wait_semaphores_khr(int64_t device, int64_t wait_info_struct, int64_t timeout);
int32_t xvk_signal_semaphore_khr(int64_t device, int64_t signal_info_struct);

/* VK_KHR_dynamic_rendering */
void xvk_cmd_begin_rendering_khr(int64_t cmd_buf, int64_t rendering_info_struct);
void xvk_cmd_end_rendering_khr(int64_t cmd_buf);

/* VK_KHR_synchronization2 */
void xvk_cmd_pipeline_barrier2_khr(int64_t cmd_buf, int64_t dependency_info_struct);
void xvk_cmd_write_timestamp2_khr(int64_t cmd_buf, int32_t stage, int64_t query_pool, int32_t query);
int32_t xvk_queue_submit2_khr(int64_t queue, int32_t submit_count, int64_t submits_struct, int64_t fence);

/* VK_EXT_shader_object */
int32_t xvk_create_shaders_ext(int64_t device, int32_t count, int64_t create_infos_struct, int64_t out_shaders);
void xvk_destroy_shader_ext(int64_t device, int64_t shader, int64_t allocator);
void xvk_cmd_bind_shaders_ext(int64_t cmd_buf, int32_t stage_count, int64_t stages, int64_t shaders);

/* VK_KHR_video_queue / VK_KHR_video_decode_queue / VK_KHR_video_encode_queue */
int64_t xvk_create_video_session_khr(int64_t device, int64_t create_info_struct);
void xvk_destroy_video_session_khr(int64_t device, int64_t session);
int32_t xvk_get_video_session_memory_requirements_khr(int64_t device, int64_t session, int64_t out_count, int64_t out_reqs);
int32_t xvk_bind_video_session_memory_khr(int64_t device, int64_t session, int32_t count, int64_t bind_infos_struct);
int64_t xvk_create_video_session_parameters_khr(int64_t device, int64_t create_info_struct);
int32_t xvk_update_video_session_parameters_khr(int64_t device, int64_t session_params, int64_t update_info_struct);
void xvk_destroy_video_session_parameters_khr(int64_t device, int64_t session_params);
void xvk_cmd_begin_video_coding_khr(int64_t cmd_buf, int64_t begin_info_struct);
void xvk_cmd_end_video_coding_khr(int64_t cmd_buf, int64_t end_info_struct);
void xvk_cmd_control_video_coding_khr(int64_t cmd_buf, int64_t control_info_struct);
void xvk_cmd_decode_video_khr(int64_t cmd_buf, int64_t decode_info_struct);
void xvk_cmd_encode_video_khr(int64_t cmd_buf, int64_t encode_info_struct);

#endif
