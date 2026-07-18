#include "xvk_bind_command.h"

#include <vulkan/vulkan.h>

#include "xvk_util.h"

#define XVK_BC_CB(h)        ((VkCommandBuffer)(intptr_t)(h))
#define XVK_BC_DEVICE(h)    ((VkDevice)(intptr_t)(h))
#define XVK_BC_HANDLE(T, h) ((T)(uint64_t)(h))
#define XVK_BC_CPTR(T, h)   ((const T*)(intptr_t)(h))

#define XVK_BC_REQUIRE(cond, name, why) \
    do { if (!(cond)) { xvk_set_error_fmt(name ": " why); return; } } while (0)

/* ---- Copy / clear operations ---- */

void xvk_cmd_copy_image(int64_t cb, int64_t src, int32_t src_layout, int64_t dst, int32_t dst_layout, int32_t region_count, int64_t regions_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_copy_image", "null command buffer");
    XVK_BC_REQUIRE(src != 0 && dst != 0, "xvk_cmd_copy_image", "null src/dst image");
    XVK_BC_REQUIRE(region_count > 0 && regions_struct != 0, "xvk_cmd_copy_image", "invalid regions");
    vkCmdCopyImage(XVK_BC_CB(cb),
                   XVK_BC_HANDLE(VkImage, src), (VkImageLayout)src_layout,
                   XVK_BC_HANDLE(VkImage, dst), (VkImageLayout)dst_layout,
                   (uint32_t)region_count, XVK_BC_CPTR(VkImageCopy, regions_struct));
}

void xvk_cmd_copy_image_to_buffer(int64_t cb, int64_t src, int32_t src_layout, int64_t dst, int32_t region_count, int64_t regions_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_copy_image_to_buffer", "null command buffer");
    XVK_BC_REQUIRE(src != 0 && dst != 0, "xvk_cmd_copy_image_to_buffer", "null src image/dst buffer");
    XVK_BC_REQUIRE(region_count > 0 && regions_struct != 0, "xvk_cmd_copy_image_to_buffer", "invalid regions");
    vkCmdCopyImageToBuffer(XVK_BC_CB(cb),
                           XVK_BC_HANDLE(VkImage, src), (VkImageLayout)src_layout,
                           XVK_BC_HANDLE(VkBuffer, dst),
                           (uint32_t)region_count, XVK_BC_CPTR(VkBufferImageCopy, regions_struct));
}

void xvk_cmd_update_buffer(int64_t cb, int64_t dst, int64_t dst_offset, int64_t data_size, int64_t data)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_update_buffer", "null command buffer");
    XVK_BC_REQUIRE(dst != 0, "xvk_cmd_update_buffer", "null dst buffer");
    XVK_BC_REQUIRE(data != 0 && data_size > 0, "xvk_cmd_update_buffer", "invalid data");
    vkCmdUpdateBuffer(XVK_BC_CB(cb), XVK_BC_HANDLE(VkBuffer, dst),
                      (VkDeviceSize)dst_offset, (VkDeviceSize)data_size,
                      (const void*)(intptr_t)data);
}

void xvk_cmd_fill_buffer(int64_t cb, int64_t dst, int64_t dst_offset, int64_t size, int32_t data)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_fill_buffer", "null command buffer");
    XVK_BC_REQUIRE(dst != 0, "xvk_cmd_fill_buffer", "null dst buffer");
    vkCmdFillBuffer(XVK_BC_CB(cb), XVK_BC_HANDLE(VkBuffer, dst),
                    (VkDeviceSize)dst_offset, (VkDeviceSize)size, (uint32_t)data);
}

void xvk_cmd_clear_color_image(int64_t cb, int64_t image, int32_t image_layout, int64_t color_struct, int32_t range_count, int64_t ranges_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_clear_color_image", "null command buffer");
    XVK_BC_REQUIRE(image != 0, "xvk_cmd_clear_color_image", "null image");
    XVK_BC_REQUIRE(color_struct != 0, "xvk_cmd_clear_color_image", "null clear color");
    XVK_BC_REQUIRE(range_count > 0 && ranges_struct != 0, "xvk_cmd_clear_color_image", "invalid ranges");
    vkCmdClearColorImage(XVK_BC_CB(cb),
                         XVK_BC_HANDLE(VkImage, image), (VkImageLayout)image_layout,
                         XVK_BC_CPTR(VkClearColorValue, color_struct),
                         (uint32_t)range_count, XVK_BC_CPTR(VkImageSubresourceRange, ranges_struct));
}

void xvk_cmd_clear_depth_stencil_image(int64_t cb, int64_t image, int32_t image_layout, int64_t depth_stencil_struct, int32_t range_count, int64_t ranges_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_clear_depth_stencil_image", "null command buffer");
    XVK_BC_REQUIRE(image != 0, "xvk_cmd_clear_depth_stencil_image", "null image");
    XVK_BC_REQUIRE(depth_stencil_struct != 0, "xvk_cmd_clear_depth_stencil_image", "null clear value");
    XVK_BC_REQUIRE(range_count > 0 && ranges_struct != 0, "xvk_cmd_clear_depth_stencil_image", "invalid ranges");
    vkCmdClearDepthStencilImage(XVK_BC_CB(cb),
                                XVK_BC_HANDLE(VkImage, image), (VkImageLayout)image_layout,
                                XVK_BC_CPTR(VkClearDepthStencilValue, depth_stencil_struct),
                                (uint32_t)range_count, XVK_BC_CPTR(VkImageSubresourceRange, ranges_struct));
}

void xvk_cmd_clear_attachments(int64_t cb, int32_t attachment_count, int64_t attachments_struct, int32_t rect_count, int64_t rects_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_clear_attachments", "null command buffer");
    XVK_BC_REQUIRE(attachment_count > 0 && attachments_struct != 0, "xvk_cmd_clear_attachments", "invalid attachments");
    XVK_BC_REQUIRE(rect_count > 0 && rects_struct != 0, "xvk_cmd_clear_attachments", "invalid rects");
    vkCmdClearAttachments(XVK_BC_CB(cb),
                          (uint32_t)attachment_count, XVK_BC_CPTR(VkClearAttachment, attachments_struct),
                          (uint32_t)rect_count, XVK_BC_CPTR(VkClearRect, rects_struct));
}

void xvk_cmd_resolve_image(int64_t cb, int64_t src, int32_t src_layout, int64_t dst, int32_t dst_layout, int32_t region_count, int64_t regions_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_resolve_image", "null command buffer");
    XVK_BC_REQUIRE(src != 0 && dst != 0, "xvk_cmd_resolve_image", "null src/dst image");
    XVK_BC_REQUIRE(region_count > 0 && regions_struct != 0, "xvk_cmd_resolve_image", "invalid regions");
    vkCmdResolveImage(XVK_BC_CB(cb),
                      XVK_BC_HANDLE(VkImage, src), (VkImageLayout)src_layout,
                      XVK_BC_HANDLE(VkImage, dst), (VkImageLayout)dst_layout,
                      (uint32_t)region_count, XVK_BC_CPTR(VkImageResolve, regions_struct));
}

/* ---- Dispatch ---- */

void xvk_cmd_dispatch_indirect(int64_t cb, int64_t buffer, int64_t offset)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_dispatch_indirect", "null command buffer");
    XVK_BC_REQUIRE(buffer != 0, "xvk_cmd_dispatch_indirect", "null buffer");
    vkCmdDispatchIndirect(XVK_BC_CB(cb), XVK_BC_HANDLE(VkBuffer, buffer), (VkDeviceSize)offset);
}

void xvk_cmd_dispatch_base(int64_t cb, int32_t base_x, int32_t base_y, int32_t base_z, int32_t group_x, int32_t group_y, int32_t group_z)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_dispatch_base", "null command buffer");
#if defined(VK_VERSION_1_1)
    vkCmdDispatchBase(XVK_BC_CB(cb),
                      (uint32_t)base_x, (uint32_t)base_y, (uint32_t)base_z,
                      (uint32_t)group_x, (uint32_t)group_y, (uint32_t)group_z);
#else
    (void)base_x; (void)base_y; (void)base_z; (void)group_x; (void)group_y; (void)group_z;
    xvk_set_error_fmt("xvk_cmd_dispatch_base: requires Vulkan 1.1 headers");
#endif
}

/* ---- Synchronization2 (core 1.3) ---- */

void xvk_cmd_pipeline_barrier2(int64_t cb, int64_t dependency_info_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_pipeline_barrier2", "null command buffer");
    XVK_BC_REQUIRE(dependency_info_struct != 0, "xvk_cmd_pipeline_barrier2", "null dependency info");
#if defined(VK_VERSION_1_3)
    vkCmdPipelineBarrier2(XVK_BC_CB(cb), XVK_BC_CPTR(VkDependencyInfo, dependency_info_struct));
#else
    xvk_set_error_fmt("xvk_cmd_pipeline_barrier2: requires Vulkan 1.3 headers");
#endif
}

void xvk_cmd_set_event2(int64_t cb, int64_t event, int64_t dependency_info_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_set_event2", "null command buffer");
    XVK_BC_REQUIRE(event != 0, "xvk_cmd_set_event2", "null event");
    XVK_BC_REQUIRE(dependency_info_struct != 0, "xvk_cmd_set_event2", "null dependency info");
#if defined(VK_VERSION_1_3)
    vkCmdSetEvent2(XVK_BC_CB(cb), XVK_BC_HANDLE(VkEvent, event),
                   XVK_BC_CPTR(VkDependencyInfo, dependency_info_struct));
#else
    xvk_set_error_fmt("xvk_cmd_set_event2: requires Vulkan 1.3 headers");
#endif
}

void xvk_cmd_reset_event2(int64_t cb, int64_t event, int32_t stage_mask)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_reset_event2", "null command buffer");
    XVK_BC_REQUIRE(event != 0, "xvk_cmd_reset_event2", "null event");
#if defined(VK_VERSION_1_3)
    vkCmdResetEvent2(XVK_BC_CB(cb), XVK_BC_HANDLE(VkEvent, event),
                     (VkPipelineStageFlags2)(uint32_t)stage_mask);
#else
    (void)stage_mask;
    xvk_set_error_fmt("xvk_cmd_reset_event2: requires Vulkan 1.3 headers");
#endif
}

void xvk_cmd_wait_events2(int64_t cb, int32_t event_count, int64_t events, int64_t dependency_infos_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_wait_events2", "null command buffer");
    XVK_BC_REQUIRE(event_count > 0 && events != 0, "xvk_cmd_wait_events2", "invalid events");
    XVK_BC_REQUIRE(dependency_infos_struct != 0, "xvk_cmd_wait_events2", "null dependency infos");
#if defined(VK_VERSION_1_3)
    vkCmdWaitEvents2(XVK_BC_CB(cb), (uint32_t)event_count,
                     XVK_BC_CPTR(VkEvent, events),
                     XVK_BC_CPTR(VkDependencyInfo, dependency_infos_struct));
#else
    xvk_set_error_fmt("xvk_cmd_wait_events2: requires Vulkan 1.3 headers");
#endif
}

/* ---- Dynamic state (core 1.0) ---- */

void xvk_cmd_set_viewport(int64_t cb, int32_t first, int32_t count, int64_t viewports_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_set_viewport", "null command buffer");
    XVK_BC_REQUIRE(count > 0 && viewports_struct != 0, "xvk_cmd_set_viewport", "invalid viewports");
    vkCmdSetViewport(XVK_BC_CB(cb), (uint32_t)first, (uint32_t)count,
                     XVK_BC_CPTR(VkViewport, viewports_struct));
}

void xvk_cmd_set_scissor(int64_t cb, int32_t first, int32_t count, int64_t scissors_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_set_scissor", "null command buffer");
    XVK_BC_REQUIRE(count > 0 && scissors_struct != 0, "xvk_cmd_set_scissor", "invalid scissors");
    vkCmdSetScissor(XVK_BC_CB(cb), (uint32_t)first, (uint32_t)count,
                    XVK_BC_CPTR(VkRect2D, scissors_struct));
}

void xvk_cmd_set_line_width(int64_t cb, float width)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_set_line_width", "null command buffer");
    vkCmdSetLineWidth(XVK_BC_CB(cb), width);
}

void xvk_cmd_set_depth_bias(int64_t cb, float constant_factor, float clamp, float slope_factor)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_set_depth_bias", "null command buffer");
    vkCmdSetDepthBias(XVK_BC_CB(cb), constant_factor, clamp, slope_factor);
}

void xvk_cmd_set_blend_constants(int64_t cb, float constants[4])
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_set_blend_constants", "null command buffer");
    XVK_BC_REQUIRE(constants != NULL, "xvk_cmd_set_blend_constants", "null constants");
    vkCmdSetBlendConstants(XVK_BC_CB(cb), constants);
}

void xvk_cmd_set_depth_bounds(int64_t cb, float min, float max)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_set_depth_bounds", "null command buffer");
    vkCmdSetDepthBounds(XVK_BC_CB(cb), min, max);
}

void xvk_cmd_set_stencil_compare_mask(int64_t cb, int32_t face_mask, int32_t compare_mask)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_set_stencil_compare_mask", "null command buffer");
    vkCmdSetStencilCompareMask(XVK_BC_CB(cb), (VkStencilFaceFlags)(uint32_t)face_mask, (uint32_t)compare_mask);
}

void xvk_cmd_set_stencil_write_mask(int64_t cb, int32_t face_mask, int32_t write_mask)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_set_stencil_write_mask", "null command buffer");
    vkCmdSetStencilWriteMask(XVK_BC_CB(cb), (VkStencilFaceFlags)(uint32_t)face_mask, (uint32_t)write_mask);
}

void xvk_cmd_set_stencil_reference(int64_t cb, int32_t face_mask, int32_t reference)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_set_stencil_reference", "null command buffer");
    vkCmdSetStencilReference(XVK_BC_CB(cb), (VkStencilFaceFlags)(uint32_t)face_mask, (uint32_t)reference);
}

/* ---- Events (core 1.0) ---- */

void xvk_cmd_set_event(int64_t cb, int64_t event, int32_t stage_mask)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_set_event", "null command buffer");
    XVK_BC_REQUIRE(event != 0, "xvk_cmd_set_event", "null event");
    vkCmdSetEvent(XVK_BC_CB(cb), XVK_BC_HANDLE(VkEvent, event),
                  (VkPipelineStageFlags)(uint32_t)stage_mask);
}

void xvk_cmd_reset_event(int64_t cb, int64_t event, int32_t stage_mask)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_reset_event", "null command buffer");
    XVK_BC_REQUIRE(event != 0, "xvk_cmd_reset_event", "null event");
    vkCmdResetEvent(XVK_BC_CB(cb), XVK_BC_HANDLE(VkEvent, event),
                    (VkPipelineStageFlags)(uint32_t)stage_mask);
}

void xvk_cmd_wait_events(int64_t cb, int32_t event_count, int64_t events, int32_t src_stage_mask, int32_t dst_stage_mask, int32_t memory_barrier_count, int64_t memory_barriers_struct, int32_t buffer_barrier_count, int64_t buffer_barriers_struct, int32_t image_barrier_count, int64_t image_barriers_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_wait_events", "null command buffer");
    XVK_BC_REQUIRE(event_count > 0 && events != 0, "xvk_cmd_wait_events", "invalid events");
    XVK_BC_REQUIRE(memory_barrier_count <= 0 || memory_barriers_struct != 0, "xvk_cmd_wait_events", "invalid memory barriers");
    XVK_BC_REQUIRE(buffer_barrier_count <= 0 || buffer_barriers_struct != 0, "xvk_cmd_wait_events", "invalid buffer barriers");
    XVK_BC_REQUIRE(image_barrier_count <= 0 || image_barriers_struct != 0, "xvk_cmd_wait_events", "invalid image barriers");
    vkCmdWaitEvents(XVK_BC_CB(cb),
                    (uint32_t)event_count, XVK_BC_CPTR(VkEvent, events),
                    (VkPipelineStageFlags)(uint32_t)src_stage_mask,
                    (VkPipelineStageFlags)(uint32_t)dst_stage_mask,
                    (uint32_t)(memory_barrier_count > 0 ? memory_barrier_count : 0),
                    XVK_BC_CPTR(VkMemoryBarrier, memory_barriers_struct),
                    (uint32_t)(buffer_barrier_count > 0 ? buffer_barrier_count : 0),
                    XVK_BC_CPTR(VkBufferMemoryBarrier, buffer_barriers_struct),
                    (uint32_t)(image_barrier_count > 0 ? image_barrier_count : 0),
                    XVK_BC_CPTR(VkImageMemoryBarrier, image_barriers_struct));
}

/* ---- Device mask / multi-GPU (core 1.1) ---- */

void xvk_cmd_set_device_mask(int64_t cb, int32_t device_mask)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_set_device_mask", "null command buffer");
#if defined(VK_VERSION_1_1)
    vkCmdSetDeviceMask(XVK_BC_CB(cb), (uint32_t)device_mask);
#else
    (void)device_mask;
    xvk_set_error_fmt("xvk_cmd_set_device_mask: requires Vulkan 1.1 headers");
#endif
}

/* ---- Secondary command buffers / render pass 2 ---- */

void xvk_cmd_execute_commands(int64_t cb, int32_t command_buffer_count, int64_t command_buffers)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_execute_commands", "null command buffer");
    XVK_BC_REQUIRE(command_buffer_count > 0 && command_buffers != 0, "xvk_cmd_execute_commands", "invalid command buffers");
    vkCmdExecuteCommands(XVK_BC_CB(cb), (uint32_t)command_buffer_count,
                         XVK_BC_CPTR(VkCommandBuffer, command_buffers));
}

void xvk_cmd_begin_render_pass2(int64_t cb, int64_t begin_info_struct, int64_t subpass_begin_info_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_begin_render_pass2", "null command buffer");
    XVK_BC_REQUIRE(begin_info_struct != 0, "xvk_cmd_begin_render_pass2", "null begin info");
    XVK_BC_REQUIRE(subpass_begin_info_struct != 0, "xvk_cmd_begin_render_pass2", "null subpass begin info");
#if defined(VK_VERSION_1_2)
    vkCmdBeginRenderPass2(XVK_BC_CB(cb),
                          XVK_BC_CPTR(VkRenderPassBeginInfo, begin_info_struct),
                          XVK_BC_CPTR(VkSubpassBeginInfo, subpass_begin_info_struct));
#else
    xvk_set_error_fmt("xvk_cmd_begin_render_pass2: requires Vulkan 1.2 headers");
#endif
}

void xvk_cmd_next_subpass(int64_t cb, int32_t contents)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_next_subpass", "null command buffer");
    vkCmdNextSubpass(XVK_BC_CB(cb), (VkSubpassContents)contents);
}

void xvk_cmd_next_subpass2(int64_t cb, int64_t subpass_begin_info_struct, int64_t subpass_end_info_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_next_subpass2", "null command buffer");
    XVK_BC_REQUIRE(subpass_begin_info_struct != 0, "xvk_cmd_next_subpass2", "null subpass begin info");
    XVK_BC_REQUIRE(subpass_end_info_struct != 0, "xvk_cmd_next_subpass2", "null subpass end info");
#if defined(VK_VERSION_1_2)
    vkCmdNextSubpass2(XVK_BC_CB(cb),
                      XVK_BC_CPTR(VkSubpassBeginInfo, subpass_begin_info_struct),
                      XVK_BC_CPTR(VkSubpassEndInfo, subpass_end_info_struct));
#else
    xvk_set_error_fmt("xvk_cmd_next_subpass2: requires Vulkan 1.2 headers");
#endif
}

void xvk_cmd_end_render_pass2(int64_t cb, int64_t subpass_end_info_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_end_render_pass2", "null command buffer");
    XVK_BC_REQUIRE(subpass_end_info_struct != 0, "xvk_cmd_end_render_pass2", "null subpass end info");
#if defined(VK_VERSION_1_2)
    vkCmdEndRenderPass2(XVK_BC_CB(cb), XVK_BC_CPTR(VkSubpassEndInfo, subpass_end_info_struct));
#else
    xvk_set_error_fmt("xvk_cmd_end_render_pass2: requires Vulkan 1.2 headers");
#endif
}

/* ---- Descriptor / push constant info structs (core 1.4, maintenance6) ---- */

void xvk_cmd_bind_descriptor_sets2(int64_t cb, int64_t bind_info_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_bind_descriptor_sets2", "null command buffer");
    XVK_BC_REQUIRE(bind_info_struct != 0, "xvk_cmd_bind_descriptor_sets2", "null bind info");
#if defined(VK_VERSION_1_4)
    vkCmdBindDescriptorSets2(XVK_BC_CB(cb), XVK_BC_CPTR(VkBindDescriptorSetsInfo, bind_info_struct));
#else
    xvk_set_error_fmt("xvk_cmd_bind_descriptor_sets2: requires Vulkan 1.4 headers (VK_KHR_maintenance6)");
#endif
}

void xvk_cmd_push_constants2(int64_t cb, int64_t push_constants_info_struct)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_push_constants2", "null command buffer");
    XVK_BC_REQUIRE(push_constants_info_struct != 0, "xvk_cmd_push_constants2", "null push constants info");
#if defined(VK_VERSION_1_4)
    vkCmdPushConstants2(XVK_BC_CB(cb), XVK_BC_CPTR(VkPushConstantsInfo, push_constants_info_struct));
#else
    xvk_set_error_fmt("xvk_cmd_push_constants2: requires Vulkan 1.4 headers (VK_KHR_maintenance6)");
#endif
}

/* ---- Indirect draw count (core 1.2) ---- */

void xvk_cmd_draw_indirect_count(int64_t cb, int64_t buffer, int64_t offset, int64_t count_buffer, int64_t count_offset, int32_t max_draw_count, int32_t stride)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_draw_indirect_count", "null command buffer");
    XVK_BC_REQUIRE(buffer != 0 && count_buffer != 0, "xvk_cmd_draw_indirect_count", "null buffer/count buffer");
#if defined(VK_VERSION_1_2)
    vkCmdDrawIndirectCount(XVK_BC_CB(cb),
                           XVK_BC_HANDLE(VkBuffer, buffer), (VkDeviceSize)offset,
                           XVK_BC_HANDLE(VkBuffer, count_buffer), (VkDeviceSize)count_offset,
                           (uint32_t)max_draw_count, (uint32_t)stride);
#else
    (void)offset; (void)count_offset; (void)max_draw_count; (void)stride;
    xvk_set_error_fmt("xvk_cmd_draw_indirect_count: requires Vulkan 1.2 headers");
#endif
}

void xvk_cmd_draw_indexed_indirect_count(int64_t cb, int64_t buffer, int64_t offset, int64_t count_buffer, int64_t count_offset, int32_t max_draw_count, int32_t stride)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_draw_indexed_indirect_count", "null command buffer");
    XVK_BC_REQUIRE(buffer != 0 && count_buffer != 0, "xvk_cmd_draw_indexed_indirect_count", "null buffer/count buffer");
#if defined(VK_VERSION_1_2)
    vkCmdDrawIndexedIndirectCount(XVK_BC_CB(cb),
                                  XVK_BC_HANDLE(VkBuffer, buffer), (VkDeviceSize)offset,
                                  XVK_BC_HANDLE(VkBuffer, count_buffer), (VkDeviceSize)count_offset,
                                  (uint32_t)max_draw_count, (uint32_t)stride);
#else
    (void)offset; (void)count_offset; (void)max_draw_count; (void)stride;
    xvk_set_error_fmt("xvk_cmd_draw_indexed_indirect_count: requires Vulkan 1.2 headers");
#endif
}

/* ---- Queries (core 1.0) ---- */

void xvk_cmd_write_timestamp(int64_t cb, int32_t pipeline_stage, int64_t query_pool, int32_t query)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_write_timestamp", "null command buffer");
    XVK_BC_REQUIRE(query_pool != 0, "xvk_cmd_write_timestamp", "null query pool");
    vkCmdWriteTimestamp(XVK_BC_CB(cb), (VkPipelineStageFlagBits)pipeline_stage,
                        XVK_BC_HANDLE(VkQueryPool, query_pool), (uint32_t)query);
}

void xvk_cmd_copy_query_pool_results(int64_t cb, int64_t query_pool, int32_t first_query, int32_t query_count, int64_t dst_buffer, int64_t dst_offset, int64_t stride, int32_t flags)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_copy_query_pool_results", "null command buffer");
    XVK_BC_REQUIRE(query_pool != 0, "xvk_cmd_copy_query_pool_results", "null query pool");
    XVK_BC_REQUIRE(dst_buffer != 0, "xvk_cmd_copy_query_pool_results", "null dst buffer");
    vkCmdCopyQueryPoolResults(XVK_BC_CB(cb), XVK_BC_HANDLE(VkQueryPool, query_pool),
                              (uint32_t)first_query, (uint32_t)query_count,
                              XVK_BC_HANDLE(VkBuffer, dst_buffer), (VkDeviceSize)dst_offset,
                              (VkDeviceSize)stride, (VkQueryResultFlags)(uint32_t)flags);
}

void xvk_cmd_reset_query_pool(int64_t cb, int64_t query_pool, int32_t first_query, int32_t query_count)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_reset_query_pool", "null command buffer");
    XVK_BC_REQUIRE(query_pool != 0, "xvk_cmd_reset_query_pool", "null query pool");
    vkCmdResetQueryPool(XVK_BC_CB(cb), XVK_BC_HANDLE(VkQueryPool, query_pool),
                        (uint32_t)first_query, (uint32_t)query_count);
}

void xvk_cmd_begin_query(int64_t cb, int64_t query_pool, int32_t query, int32_t flags)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_begin_query", "null command buffer");
    XVK_BC_REQUIRE(query_pool != 0, "xvk_cmd_begin_query", "null query pool");
    vkCmdBeginQuery(XVK_BC_CB(cb), XVK_BC_HANDLE(VkQueryPool, query_pool),
                    (uint32_t)query, (VkQueryControlFlags)(uint32_t)flags);
}

void xvk_cmd_end_query(int64_t cb, int64_t query_pool, int32_t query)
{
    XVK_BC_REQUIRE(cb != 0, "xvk_cmd_end_query", "null command buffer");
    XVK_BC_REQUIRE(query_pool != 0, "xvk_cmd_end_query", "null query pool");
    vkCmdEndQuery(XVK_BC_CB(cb), XVK_BC_HANDLE(VkQueryPool, query_pool), (uint32_t)query);
}

/* ---- Buffer device address (core 1.2) ---- */

int64_t xvk_get_buffer_device_address(int64_t device, int64_t buffer_device_address_info_struct)
{
    if (device == 0) { xvk_set_error_fmt("xvk_get_buffer_device_address: null device"); return 0; }
    if (buffer_device_address_info_struct == 0) { xvk_set_error_fmt("xvk_get_buffer_device_address: null info"); return 0; }
#if defined(VK_VERSION_1_2)
    return (int64_t)vkGetBufferDeviceAddress(XVK_BC_DEVICE(device),
                                             XVK_BC_CPTR(VkBufferDeviceAddressInfo, buffer_device_address_info_struct));
#else
    xvk_set_error_fmt("xvk_get_buffer_device_address: requires Vulkan 1.2 headers");
    return 0;
#endif
}

int64_t xvk_get_buffer_opaque_capture_address(int64_t device, int64_t buffer_device_address_info_struct)
{
    if (device == 0) { xvk_set_error_fmt("xvk_get_buffer_opaque_capture_address: null device"); return 0; }
    if (buffer_device_address_info_struct == 0) { xvk_set_error_fmt("xvk_get_buffer_opaque_capture_address: null info"); return 0; }
#if defined(VK_VERSION_1_2)
    return (int64_t)vkGetBufferOpaqueCaptureAddress(XVK_BC_DEVICE(device),
                                                    XVK_BC_CPTR(VkBufferDeviceAddressInfo, buffer_device_address_info_struct));
#else
    xvk_set_error_fmt("xvk_get_buffer_opaque_capture_address: requires Vulkan 1.2 headers");
    return 0;
#endif
}

int64_t xvk_get_device_memory_opaque_capture_address(int64_t device, int64_t memory_opaque_capture_address_info_struct)
{
    if (device == 0) { xvk_set_error_fmt("xvk_get_device_memory_opaque_capture_address: null device"); return 0; }
    if (memory_opaque_capture_address_info_struct == 0) { xvk_set_error_fmt("xvk_get_device_memory_opaque_capture_address: null info"); return 0; }
#if defined(VK_VERSION_1_2)
    return (int64_t)vkGetDeviceMemoryOpaqueCaptureAddress(XVK_BC_DEVICE(device),
                                                          XVK_BC_CPTR(VkDeviceMemoryOpaqueCaptureAddressInfo, memory_opaque_capture_address_info_struct));
#else
    xvk_set_error_fmt("xvk_get_device_memory_opaque_capture_address: requires Vulkan 1.2 headers");
    return 0;
#endif
}
