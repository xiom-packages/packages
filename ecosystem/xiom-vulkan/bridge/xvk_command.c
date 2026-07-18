#include "xvk_command.h"
#include <stdlib.h>

void xvk_cmd_bind_vertex_buffer(int64_t app_h, int32_t binding, int64_t buf_h, int64_t offset)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !a->recording || !b) return;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    VkDeviceSize off = (VkDeviceSize)offset;
    vkCmdBindVertexBuffers(cb, (uint32_t)binding, 1, &b->buffer, &off);
}

void xvk_cmd_bind_index_buffer(int64_t app_h, int64_t buf_h, int64_t offset, int32_t index_type)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !a->recording || !b) return;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdBindIndexBuffer(cb, b->buffer, (VkDeviceSize)offset, xvk_map_index_type(index_type));
}

void xvk_cmd_bind_pipeline(int64_t app_h, int64_t pipeline_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipeline* p = xvk_pipeline_from_handle(pipeline_h);
    if (!a || !a->recording || !p) return;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdBindPipeline(cb, p->bind_point, p->pipeline);
}

void xvk_cmd_bind_descriptor_sets(int64_t app_h, int64_t layout_h, int32_t first_set,
                                   const int64_t* sets, int32_t set_count)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipelineLayout* pl = xvk_playout_from_handle(layout_h);
    if (!a || !a->recording || !pl || !sets || set_count <= 0) return;

    VkDescriptorSet* dss = (VkDescriptorSet*)malloc((size_t)set_count * sizeof(VkDescriptorSet));
    if (!dss) return;
    for (int i = 0; i < set_count; ++i) {
        XvkDescSet* ds = xvk_descset_from_handle(sets[i]);
        dss[i] = ds ? ds->set : VK_NULL_HANDLE;
    }
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, pl->layout,
                            (uint32_t)first_set, (uint32_t)set_count, dss, 0, NULL);
    free(dss);
}

void xvk_cmd_push_constants(int64_t app_h, int64_t layout_h, int32_t stages,
                             int32_t offset, int32_t size, const void* data)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipelineLayout* pl = xvk_playout_from_handle(layout_h);
    if (!a || !a->recording || !pl || !data || size <= 0) return;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdPushConstants(cb, pl->layout, xvk_map_stage_flags(stages),
                       (uint32_t)offset, (uint32_t)size, data);
}

void xvk_cmd_draw_indexed(int64_t app_h, int32_t index_count, int32_t instance_count,
                           int32_t first_index, int32_t vertex_offset, int32_t first_instance)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording || !a->in_render_pass) return;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdDrawIndexed(cb, (uint32_t)index_count, (uint32_t)instance_count,
                     (uint32_t)first_index, vertex_offset, (uint32_t)first_instance);
}

void xvk_cmd_draw(int64_t app_h, int32_t vertex_count, int32_t instance_count,
                   int32_t first_vertex, int32_t first_instance)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording || !a->in_render_pass) return;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdDraw(cb, (uint32_t)vertex_count, (uint32_t)instance_count,
              (uint32_t)first_vertex, (uint32_t)first_instance);
}

int32_t xvk_begin_custom_pass(int64_t app_h, int64_t render_pass_h, int64_t framebuffer_h,
                               int32_t width, int32_t height,
                               float r, float g, float b)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkRenderPass* xrp = xvk_rp_from_handle(render_pass_h);
    XvkFramebuffer* xfb = xvk_fb_from_handle(framebuffer_h);
    if (!a || !a->recording || !xrp || !xfb) return -1;

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];

    if (a->in_render_pass) {
        vkCmdEndRenderPass(cb);
        a->in_render_pass = 0;
    }

    VkClearValue clear = {0};
    clear.color.float32[0] = r;
    clear.color.float32[1] = g;
    clear.color.float32[2] = b;
    clear.color.float32[3] = 1.0f;

    VkRenderPassBeginInfo rpbi = {0};
    rpbi.sType       = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rpbi.renderPass  = xrp->render_pass;
    rpbi.framebuffer = xfb->framebuffer;
    rpbi.renderArea.offset.x = 0;
    rpbi.renderArea.offset.y = 0;
    rpbi.renderArea.extent.width  = (uint32_t)width;
    rpbi.renderArea.extent.height = (uint32_t)height;
    rpbi.clearValueCount = 1;
    rpbi.pClearValues    = &clear;

    vkCmdBeginRenderPass(cb, &rpbi, VK_SUBPASS_CONTENTS_INLINE);
    a->in_render_pass = 1;
    return 1;
}

int32_t xvk_end_custom_pass(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording || !a->in_render_pass) return -1;

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdEndRenderPass(cb);
    a->in_render_pass = 0;

    VkClearValue clears[2];
    clears[0].color.float32[0] = a->clear_r;
    clears[0].color.float32[1] = a->clear_g;
    clears[0].color.float32[2] = a->clear_b;
    clears[0].color.float32[3] = 1.0f;
    clears[1].depthStencil.depth   = 1.0f;
    clears[1].depthStencil.stencil = 0;

    VkRenderPassBeginInfo rpbi = {0};
    rpbi.sType       = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rpbi.renderPass  = a->render_pass;
    rpbi.framebuffer = a->framebuffers[a->current_image];
    rpbi.renderArea.extent = a->swapchain_extent;
    rpbi.clearValueCount   = 2;
    rpbi.pClearValues      = clears;

    vkCmdBeginRenderPass(cb, &rpbi, VK_SUBPASS_CONTENTS_INLINE);
    a->in_render_pass = 1;
    return 1;
}

void xvk_image_transition(int64_t app_h, int64_t img_h, int32_t old_layout, int32_t new_layout)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkImage* img = xvk_image_from_handle(img_h);
    if (!a || !a->recording || !img) return;

    VkImageLayout old_l = xvk_map_image_layout(old_layout);
    VkImageLayout new_l = xvk_map_image_layout(new_layout);
    if (old_l == new_l) return;

    VkImageMemoryBarrier barrier = {0};
    barrier.sType               = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout           = old_l;
    barrier.newLayout           = new_l;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image               = img->image;
    barrier.subresourceRange.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseMipLevel   = 0;
    barrier.subresourceRange.levelCount     = img->mip_levels;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount     = 1;

    VkPipelineStageFlags src_stage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
    VkPipelineStageFlags dst_stage = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;

    if (old_l == VK_IMAGE_LAYOUT_UNDEFINED && new_l == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        src_stage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        dst_stage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    } else if (old_l == VK_IMAGE_LAYOUT_UNDEFINED && new_l == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        src_stage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        dst_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    } else if (old_l == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL && new_l == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
        barrier.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        src_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dst_stage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    } else {
        barrier.srcAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
    }

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdPipelineBarrier(cb, src_stage, dst_stage, 0, 0, NULL, 0, NULL, 1, &barrier);
}

void xvk_get_framebuffer_size(int64_t app_h, int32_t* out_width, int32_t* out_height)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !out_width || !out_height) return;
    *out_width  = (int32_t)a->swapchain_extent.width;
    *out_height = (int32_t)a->swapchain_extent.height;
}
