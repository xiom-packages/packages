#include "xvk_bind_command.h"

#include <vulkan/vulkan.h>

#include "xvk_util.h"

#define XVK_BC_CB(h)        ((VkCommandBuffer)(intptr_t)(h))
#define XVK_BC_DEVICE(h)    ((VkDevice)(intptr_t)(h))
#define XVK_BC_HANDLE(T, h) ((T)(uint64_t)(h))
#define XVK_BC_CPTR(T, h)   ((const T*)(intptr_t)(h))

#define XVK_BC_REQUIRE(cond, name, why) \
    do { if (!(cond)) { xvk_set_error_fmt(name ": " why); return; } } while (0)

/* ---- Command pool / command buffer lifecycle ---- */

int64_t xvk_create_command_pool(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = XVK_BC_DEVICE(device);
    const VkCommandPoolCreateInfo* ci = XVK_BC_CPTR(VkCommandPoolCreateInfo, create_info_struct);
    if (!dev || !ci) { xvk_set_error("xvk_create_command_pool: null device or create_info"); return 0; }

    VkCommandPool pool = VK_NULL_HANDLE;
    VkResult res = vkCreateCommandPool(dev, ci, NULL, &pool);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateCommandPool failed: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)pool;
}

void xvk_destroy_command_pool(int64_t device, int64_t pool)
{
    VkDevice dev = XVK_BC_DEVICE(device);
    if (!dev || !pool) return;
    vkDestroyCommandPool(dev, XVK_BC_HANDLE(VkCommandPool, pool), NULL);
}

int32_t xvk_reset_command_pool(int64_t device, int64_t pool, int32_t flags)
{
    VkDevice dev = XVK_BC_DEVICE(device);
    if (!dev || !pool) return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    return (int32_t)vkResetCommandPool(dev, XVK_BC_HANDLE(VkCommandPool, pool),
                                       (VkCommandPoolResetFlags)flags);
}

int32_t xvk_trim_command_pool(int64_t device, int64_t pool)
{
    VkDevice dev = XVK_BC_DEVICE(device);
    if (!dev || !pool) return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    vkTrimCommandPool(dev, XVK_BC_HANDLE(VkCommandPool, pool), 0);
    return (int32_t)VK_SUCCESS;
}

/* Phase 7.5: Create N command pools for multi-threaded rendering.
 * All pools get the same queue_family and flags (typically RESET_COMMAND_BUFFER_BIT).
 * out_pools_array is a pre-allocated array of count int64_t handles.
 * Returns the number of pools created; caller should check against count. */
int64_t xvk_create_command_pools(int32_t count, int64_t device, int32_t queue_family, int32_t flags, int64_t out_pools_array)
{
    VkDevice dev = XVK_BC_DEVICE(device);
    int64_t* pools = (int64_t*)(intptr_t)out_pools_array;
    if (!dev || count <= 0 || !pools) { xvk_set_error("xvk_create_command_pools: bad params"); return 0; }

    VkCommandPoolCreateInfo ci = {0};
    ci.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    ci.queueFamilyIndex = (uint32_t)queue_family;
    ci.flags = (VkCommandPoolCreateFlags)flags;

    int32_t created = 0;
    for (int32_t i = 0; i < count; i++) {
        VkCommandPool pool = VK_NULL_HANDLE;
        VkResult res = vkCreateCommandPool(dev, &ci, NULL, &pool);
        if (res != VK_SUCCESS) {
            xvk_set_error_fmt("xvk_create_command_pools: vkCreateCommandPool[%d] failed: %d", (int)i, (int)res);
            return (int64_t)created;
        }
        pools[i] = (int64_t)(uint64_t)pool;
        created++;
    }
    return (int64_t)created;
}

int32_t xvk_allocate_command_buffers(int64_t device, int64_t allocate_info_struct, int64_t out_buffers)
{
    VkDevice dev = XVK_BC_DEVICE(device);
    const VkCommandBufferAllocateInfo* ai = XVK_BC_CPTR(VkCommandBufferAllocateInfo, allocate_info_struct);
    VkCommandBuffer* out = (VkCommandBuffer*)(intptr_t)out_buffers;
    if (!dev || !ai || !out) {
        xvk_set_error("xvk_allocate_command_buffers: null device, allocate_info or out_buffers");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkAllocateCommandBuffers(dev, ai, out);
    if (res != VK_SUCCESS) xvk_set_error_fmt("vkAllocateCommandBuffers failed: %d", (int)res);
    return (int32_t)res;
}

void xvk_free_command_buffers(int64_t device, int64_t pool, int32_t count, int64_t buffers)
{
    VkDevice dev = XVK_BC_DEVICE(device);
    const VkCommandBuffer* cbs = XVK_BC_CPTR(VkCommandBuffer, buffers);
    if (!dev || !pool || !cbs || count <= 0) return;
    vkFreeCommandBuffers(dev, XVK_BC_HANDLE(VkCommandPool, pool), (uint32_t)count, cbs);
}

/* Phase 7.5: Convenience -- allocate count command buffers with one call.
 * Builds VkCommandBufferAllocateInfo internally from the given pool, level, count.
 * out_buffers is a pre-allocated array of count int64_t handles. */
int32_t xvk_allocate_command_buffers_multi(int64_t device, int64_t pool, int32_t level, int32_t count, int64_t out_buffers)
{
    VkDevice dev = XVK_BC_DEVICE(device);
    VkCommandPool pl = XVK_BC_HANDLE(VkCommandPool, pool);
    VkCommandBuffer* out = (VkCommandBuffer*)(intptr_t)out_buffers;
    if (!dev || !pl || !out || count <= 0) {
        xvk_set_error("xvk_allocate_command_buffers_multi: null device, pool, or out_buffers");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }

    VkCommandBufferAllocateInfo ai = {0};
    ai.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    ai.commandPool = pl;
    ai.level = (VkCommandBufferLevel)level;
    ai.commandBufferCount = (uint32_t)count;

    VkResult res = vkAllocateCommandBuffers(dev, &ai, out);
    if (res != VK_SUCCESS) xvk_set_error_fmt("vkAllocateCommandBuffers multi failed: %d", (int)res);
    return (int32_t)res;
}

int32_t xvk_begin_command_buffer(int64_t cmd_buf, int64_t begin_info_struct)
{
    VkCommandBuffer cb = XVK_BC_CB(cmd_buf);
    const VkCommandBufferBeginInfo* bi = XVK_BC_CPTR(VkCommandBufferBeginInfo, begin_info_struct);
    if (!cb) return (int32_t)VK_ERROR_INITIALIZATION_FAILED;

    VkCommandBufferBeginInfo def = {0};
    if (!bi) {
        def.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        bi = &def;
    }
    return (int32_t)vkBeginCommandBuffer(cb, bi);
}

int32_t xvk_end_command_buffer(int64_t cmd_buf)
{
    VkCommandBuffer cb = XVK_BC_CB(cmd_buf);
    if (!cb) return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    return (int32_t)vkEndCommandBuffer(cb);
}

/* ---- Bind / draw / dispatch ---- */

void xvk_cmd_bind_pipeline(int64_t cmd_buf, int32_t bind_point, int64_t pipeline)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_bind_pipeline", "null command buffer");
    XVK_BC_REQUIRE(pipeline != 0, "xvk_cmd_bind_pipeline", "null pipeline");
    vkCmdBindPipeline(XVK_BC_CB(cmd_buf), (VkPipelineBindPoint)bind_point,
                      XVK_BC_HANDLE(VkPipeline, pipeline));
}

void xvk_cmd_draw(int64_t cmd_buf, int32_t vertex_count, int32_t instance_count, int32_t first_vertex, int32_t first_instance)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_draw", "null command buffer");
    vkCmdDraw(XVK_BC_CB(cmd_buf), (uint32_t)vertex_count, (uint32_t)instance_count,
              (uint32_t)first_vertex, (uint32_t)first_instance);
}

void xvk_cmd_draw_indexed(int64_t cmd_buf, int32_t index_count, int32_t instance_count, int32_t first_index, int32_t vertex_offset, int32_t first_instance)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_draw_indexed", "null command buffer");
    vkCmdDrawIndexed(XVK_BC_CB(cmd_buf), (uint32_t)index_count, (uint32_t)instance_count,
                     (uint32_t)first_index, vertex_offset, (uint32_t)first_instance);
}

void xvk_cmd_draw_indirect(int64_t cmd_buf, int64_t buffer, int64_t offset, int32_t draw_count, int32_t stride)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_draw_indirect", "null command buffer");
    XVK_BC_REQUIRE(buffer != 0, "xvk_cmd_draw_indirect", "null buffer");
    vkCmdDrawIndirect(XVK_BC_CB(cmd_buf), XVK_BC_HANDLE(VkBuffer, buffer),
                      (VkDeviceSize)offset, (uint32_t)draw_count, (uint32_t)stride);
}

void xvk_cmd_dispatch(int64_t cmd_buf, int32_t x, int32_t y, int32_t z)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_dispatch", "null command buffer");
    vkCmdDispatch(XVK_BC_CB(cmd_buf), (uint32_t)x, (uint32_t)y, (uint32_t)z);
}

void xvk_cmd_bind_vertex_buffers(int64_t cmd_buf, int32_t first_binding, int32_t count, int64_t buffers, int64_t offsets)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_bind_vertex_buffers", "null command buffer");
    XVK_BC_REQUIRE(count > 0 && buffers != 0 && offsets != 0, "xvk_cmd_bind_vertex_buffers", "invalid buffers/offsets");
    vkCmdBindVertexBuffers(XVK_BC_CB(cmd_buf), (uint32_t)first_binding, (uint32_t)count,
                           XVK_BC_CPTR(VkBuffer, buffers),
                           XVK_BC_CPTR(VkDeviceSize, offsets));
}

void xvk_cmd_bind_index_buffer(int64_t cmd_buf, int64_t buffer, int64_t offset, int32_t index_type)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_bind_index_buffer", "null command buffer");
    XVK_BC_REQUIRE(buffer != 0, "xvk_cmd_bind_index_buffer", "null buffer");
    vkCmdBindIndexBuffer(XVK_BC_CB(cmd_buf), XVK_BC_HANDLE(VkBuffer, buffer),
                         (VkDeviceSize)offset, (VkIndexType)index_type);
}

void xvk_cmd_bind_descriptor_sets(int64_t cmd_buf, int32_t bind_point, int64_t layout, int32_t first_set, int32_t count, int64_t sets, int32_t dynamic_offset_count, int64_t dynamic_offsets)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_bind_descriptor_sets", "null command buffer");
    XVK_BC_REQUIRE(layout != 0, "xvk_cmd_bind_descriptor_sets", "null layout");
    XVK_BC_REQUIRE(count > 0 && sets != 0, "xvk_cmd_bind_descriptor_sets", "invalid sets");
    XVK_BC_REQUIRE(dynamic_offset_count <= 0 || dynamic_offsets != 0, "xvk_cmd_bind_descriptor_sets", "invalid dynamic offsets");
    vkCmdBindDescriptorSets(XVK_BC_CB(cmd_buf), (VkPipelineBindPoint)bind_point,
                            XVK_BC_HANDLE(VkPipelineLayout, layout),
                            (uint32_t)first_set, (uint32_t)count,
                            XVK_BC_CPTR(VkDescriptorSet, sets),
                            (uint32_t)(dynamic_offset_count > 0 ? dynamic_offset_count : 0),
                            dynamic_offset_count > 0 ? (const uint32_t*)(intptr_t)dynamic_offsets : NULL);
}

void xvk_cmd_push_constants(int64_t cmd_buf, int64_t layout, int32_t stage_flags, int32_t offset, int32_t size, int64_t data)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_push_constants", "null command buffer");
    XVK_BC_REQUIRE(layout != 0, "xvk_cmd_push_constants", "null layout");
    XVK_BC_REQUIRE(data != 0 && size > 0, "xvk_cmd_push_constants", "invalid data");
    vkCmdPushConstants(XVK_BC_CB(cmd_buf), XVK_BC_HANDLE(VkPipelineLayout, layout),
                       (VkShaderStageFlags)stage_flags,
                       (uint32_t)offset, (uint32_t)size, (const void*)(intptr_t)data);
}

/* ---- Barriers ---- */

void xvk_cmd_pipeline_barrier(int64_t cmd_buf, int32_t src_stage, int32_t dst_stage, int32_t dep_flags, int32_t mem_barrier_count, int64_t mem_barriers, int32_t buf_barrier_count, int64_t buf_barriers, int32_t img_barrier_count, int64_t img_barriers)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_pipeline_barrier", "null command buffer");
    XVK_BC_REQUIRE(mem_barrier_count <= 0 || mem_barriers != 0, "xvk_cmd_pipeline_barrier", "invalid memory barriers");
    XVK_BC_REQUIRE(buf_barrier_count <= 0 || buf_barriers != 0, "xvk_cmd_pipeline_barrier", "invalid buffer barriers");
    XVK_BC_REQUIRE(img_barrier_count <= 0 || img_barriers != 0, "xvk_cmd_pipeline_barrier", "invalid image barriers");
    vkCmdPipelineBarrier(XVK_BC_CB(cmd_buf),
                         (VkPipelineStageFlags)src_stage,
                         (VkPipelineStageFlags)dst_stage,
                         (VkDependencyFlags)dep_flags,
                         (uint32_t)(mem_barrier_count > 0 ? mem_barrier_count : 0),
                         XVK_BC_CPTR(VkMemoryBarrier, mem_barriers),
                         (uint32_t)(buf_barrier_count > 0 ? buf_barrier_count : 0),
                         XVK_BC_CPTR(VkBufferMemoryBarrier, buf_barriers),
                         (uint32_t)(img_barrier_count > 0 ? img_barrier_count : 0),
                         XVK_BC_CPTR(VkImageMemoryBarrier, img_barriers));
}

/* ---- Render pass / dynamic rendering ---- */

void xvk_cmd_begin_render_pass(int64_t cmd_buf, int64_t begin_info_struct, int32_t contents)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_begin_render_pass", "null command buffer");
    XVK_BC_REQUIRE(begin_info_struct != 0, "xvk_cmd_begin_render_pass", "null begin info");
    vkCmdBeginRenderPass(XVK_BC_CB(cmd_buf),
                         XVK_BC_CPTR(VkRenderPassBeginInfo, begin_info_struct),
                         (VkSubpassContents)contents);
}

void xvk_cmd_end_render_pass(int64_t cmd_buf)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_end_render_pass", "null command buffer");
    vkCmdEndRenderPass(XVK_BC_CB(cmd_buf));
}

void xvk_cmd_begin_rendering(int64_t cmd_buf, int64_t rendering_info_struct)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_begin_rendering", "null command buffer");
    XVK_BC_REQUIRE(rendering_info_struct != 0, "xvk_cmd_begin_rendering", "null rendering info");
#if defined(VK_VERSION_1_3)
    vkCmdBeginRendering(XVK_BC_CB(cmd_buf), XVK_BC_CPTR(VkRenderingInfo, rendering_info_struct));
#else
    xvk_set_error_fmt("xvk_cmd_begin_rendering: requires Vulkan 1.3 headers");
#endif
}

void xvk_cmd_end_rendering(int64_t cmd_buf)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_end_rendering", "null command buffer");
#if defined(VK_VERSION_1_3)
    vkCmdEndRendering(XVK_BC_CB(cmd_buf));
#else
    xvk_set_error_fmt("xvk_cmd_end_rendering: requires Vulkan 1.3 headers");
#endif
}

/* ---- Copy / blit (core spec) ---- */

void xvk_cmd_copy_buffer(int64_t cmd_buf, int64_t src, int64_t dst, int32_t region_count, int64_t regions_struct)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_copy_buffer", "null command buffer");
    XVK_BC_REQUIRE(src != 0 && dst != 0, "xvk_cmd_copy_buffer", "null src/dst buffer");
    XVK_BC_REQUIRE(region_count > 0 && regions_struct != 0, "xvk_cmd_copy_buffer", "invalid regions");
    vkCmdCopyBuffer(XVK_BC_CB(cmd_buf),
                    XVK_BC_HANDLE(VkBuffer, src), XVK_BC_HANDLE(VkBuffer, dst),
                    (uint32_t)region_count, XVK_BC_CPTR(VkBufferCopy, regions_struct));
}

void xvk_cmd_copy_buffer_to_image(int64_t cmd_buf, int64_t src, int64_t dst, int32_t dst_layout, int32_t region_count, int64_t regions_struct)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_copy_buffer_to_image", "null command buffer");
    XVK_BC_REQUIRE(src != 0 && dst != 0, "xvk_cmd_copy_buffer_to_image", "null src buffer/dst image");
    XVK_BC_REQUIRE(region_count > 0 && regions_struct != 0, "xvk_cmd_copy_buffer_to_image", "invalid regions");
    vkCmdCopyBufferToImage(XVK_BC_CB(cmd_buf),
                           XVK_BC_HANDLE(VkBuffer, src), XVK_BC_HANDLE(VkImage, dst),
                           (VkImageLayout)dst_layout,
                           (uint32_t)region_count, XVK_BC_CPTR(VkBufferImageCopy, regions_struct));
}

void xvk_cmd_blit_image(int64_t cmd_buf, int64_t src, int32_t src_layout, int64_t dst, int32_t dst_layout, int32_t region_count, int64_t regions_struct, int32_t filter)
{
    XVK_BC_REQUIRE(cmd_buf != 0, "xvk_cmd_blit_image", "null command buffer");
    XVK_BC_REQUIRE(src != 0 && dst != 0, "xvk_cmd_blit_image", "null src/dst image");
    XVK_BC_REQUIRE(region_count > 0 && regions_struct != 0, "xvk_cmd_blit_image", "invalid regions");
    vkCmdBlitImage(XVK_BC_CB(cmd_buf),
                   XVK_BC_HANDLE(VkImage, src), (VkImageLayout)src_layout,
                   XVK_BC_HANDLE(VkImage, dst), (VkImageLayout)dst_layout,
                   (uint32_t)region_count, XVK_BC_CPTR(VkImageBlit, regions_struct),
                   (VkFilter)filter);
}

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
