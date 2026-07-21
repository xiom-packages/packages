#include "xvk_offscreen.h"
#include "xvk_pipeline.h"
#include "xvk_instance.h"
#include "xvk_shaders.h"
#include <stdlib.h>

int create_offscreen_rendertarget(XvkApp* a)
{
    VkImageCreateInfo ici = {0};
    ici.sType         = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ici.imageType     = VK_IMAGE_TYPE_2D;
    ici.format        = VK_FORMAT_B8G8R8A8_UNORM;
    ici.extent.width  = (uint32_t)a->offs_w;
    ici.extent.height = (uint32_t)a->offs_h;
    ici.extent.depth  = 1;
    ici.mipLevels     = 1;
    ici.arrayLayers   = 1;
    ici.samples       = VK_SAMPLE_COUNT_1_BIT;
    ici.tiling        = VK_IMAGE_TILING_OPTIMAL;
    ici.usage         = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                        VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    VkResult res = vkCreateImage(a->device, &ici, NULL, &a->offs_image);
    if (res != VK_SUCCESS) { xvk_set_error_fmt("offscreen vkCreateImage: %d", (int)res); return 0; }

    VkMemoryRequirements mr;
    vkGetImageMemoryRequirements(a->device, a->offs_image, &mr);
    uint32_t mi = find_memory_type(&a->mem_props, mr.memoryTypeBits,
                                    VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (mi == UINT32_MAX) {
        xvk_set_error("no device mem for offscreen image");
        goto fail_image;
    }

    VkMemoryAllocateInfo mai = {0};
    mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    mai.allocationSize   = mr.size;
    mai.memoryTypeIndex  = mi;
    res = vkAllocateMemory(a->device, &mai, NULL, &a->offs_memory);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("offscreen vkAllocateMemory: %d", (int)res);
        goto fail_image;
    }
    res = vkBindImageMemory(a->device, a->offs_image, a->offs_memory, 0);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("offscreen vkBindImageMemory: %d", (int)res);
        goto fail_memory;
    }

    VkImageViewCreateInfo ivci = {0};
    ivci.sType    = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    ivci.image    = a->offs_image;
    ivci.viewType = VK_IMAGE_VIEW_TYPE_2D;
    ivci.format   = VK_FORMAT_B8G8R8A8_UNORM;
    ivci.subresourceRange.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
    ivci.subresourceRange.baseMipLevel   = 0;
    ivci.subresourceRange.levelCount     = 1;
    ivci.subresourceRange.baseArrayLayer = 0;
    ivci.subresourceRange.layerCount     = 1;
    res = vkCreateImageView(a->device, &ivci, NULL, &a->offs_image_view);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("offscreen vkCreateImageView: %d", (int)res);
        goto fail_memory;
    }
    return 1;

fail_memory:
    vkFreeMemory(a->device, a->offs_memory, NULL);
    a->offs_memory = VK_NULL_HANDLE;
fail_image:
    vkDestroyImage(a->device, a->offs_image, NULL);
    a->offs_image = VK_NULL_HANDLE;
    return 0;
}

VkRenderPass create_offscreen_render_pass(VkDevice dev, VkFormat fmt)
{
    VkAttachmentDescription att = {0};
    att.format         = fmt;
    att.samples        = VK_SAMPLE_COUNT_1_BIT;
    att.loadOp         = VK_ATTACHMENT_LOAD_OP_CLEAR;
    att.storeOp        = VK_ATTACHMENT_STORE_OP_STORE;
    att.stencilLoadOp  = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    att.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    att.initialLayout  = VK_IMAGE_LAYOUT_UNDEFINED;
    att.finalLayout    = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;

    VkAttachmentReference col_ref = {0};
    col_ref.attachment = 0;
    col_ref.layout     = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkSubpassDescription subpass = {0};
    subpass.pipelineBindPoint    = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments    = &col_ref;

    VkSubpassDependency dep = {0};
    dep.srcSubpass    = VK_SUBPASS_EXTERNAL;
    dep.dstSubpass    = 0;
    dep.srcStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.dstStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

    VkRenderPassCreateInfo rpci = {0};
    rpci.sType           = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    rpci.attachmentCount = 1;
    rpci.pAttachments    = &att;
    rpci.subpassCount    = 1;
    rpci.pSubpasses      = &subpass;
    rpci.dependencyCount = 1;
    rpci.pDependencies   = &dep;

    VkRenderPass rp = VK_NULL_HANDLE;
    VkResult res = vkCreateRenderPass(dev, &rpci, NULL, &rp);
    if (res != VK_SUCCESS) { xvk_set_error_fmt("offscreen vkCreateRenderPass: %d", (int)res); return VK_NULL_HANDLE; }
    return rp;
}

extern void xvk_app_cleanup_internal(XvkApp* a);

int64_t xvk_offscreen_create(int32_t width, int32_t height)
{
    XvkApp* a = (XvkApp*)calloc(1, sizeof(XvkApp));
    if (!a) { xvk_set_error("calloc failed"); return 0; }

    /* Phase 8.5: Use headless instance (no GLFW needed). This allows
     * offscreen rendering on headless systems (CI, VMs, etc.). */
    int have_val = 0;
    a->instance = create_instance_headless("XIOM Offscreen", &have_val);
    if (!a->instance) { free(a); return 0; }

    if (!pick_physical_device(a->instance, VK_NULL_HANDLE,
                               &a->phys_dev, &a->device_type))
        goto offs_fail;

    if (!find_queue_families(a->phys_dev, VK_NULL_HANDLE,
                              &a->graphics_family, &a->present_family))
        goto offs_fail;
    a->present_family = a->graphics_family;

    {
        float q_priority = 1.0f;
        VkDeviceQueueCreateInfo qci = {0};
        qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = a->graphics_family;
        qci.queueCount = 1;
        qci.pQueuePriorities = &q_priority;

        VkDeviceCreateInfo dci = {0};
        dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = 1;
        dci.pQueueCreateInfos = &qci;
        dci.pEnabledFeatures = &(VkPhysicalDeviceFeatures){0};

        VkResult res = vkCreateDevice(a->phys_dev, &dci, NULL, &a->device);
        if (res != VK_SUCCESS) {
            xvk_set_error_fmt("offscreen vkCreateDevice failed: %d", (int)res);
            goto offs_fail;
        }
    }

    vkGetDeviceQueue(a->device, a->graphics_family, 0, &a->graphics_queue);
    a->present_queue = a->graphics_queue;
    vkGetPhysicalDeviceMemoryProperties(a->phys_dev, &a->mem_props);

    a->offs_w = width;
    a->offs_h = height;

    if (!create_offscreen_rendertarget(a)) goto offs_fail;

    a->offs_render_pass = create_offscreen_render_pass(a->device,
                                                         VK_FORMAT_B8G8R8A8_UNORM);
    if (!a->offs_render_pass) goto offs_fail;

    {
        VkFramebufferCreateInfo fci = {0};
        fci.sType           = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        fci.renderPass      = a->offs_render_pass;
        fci.attachmentCount = 1;
        fci.pAttachments    = &a->offs_image_view;
        fci.width           = (uint32_t)width;
        fci.height          = (uint32_t)height;
        fci.layers          = 1;
        VkResult res = vkCreateFramebuffer(a->device, &fci, NULL,
                                            &a->offs_framebuffer);
        if (res != VK_SUCCESS) {
            xvk_set_error_fmt("offscreen vkCreateFramebuffer: %d", (int)res);
            goto offs_fail;
        }
    }

    VkShaderModule tri_vert = create_shader_module(a->device,
        xvk_triangle_vert_spv, xvk_triangle_vert_spv_len);
    VkShaderModule tri_frag = create_shader_module(a->device,
        xvk_triangle_frag_spv, xvk_triangle_frag_spv_len);
    if (!tri_vert || !tri_frag) {
        if (tri_vert) vkDestroyShaderModule(a->device, tri_vert, NULL);
        if (tri_frag) vkDestroyShaderModule(a->device, tri_frag, NULL);
        goto offs_fail;
    }

    VkPushConstantRange pc_range = {0};
    pc_range.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
    pc_range.offset     = 0;
    pc_range.size       = 16;
    a->pipe_layout_2d = create_pipeline_layout(a->device, &pc_range, 1);
    if (!a->pipe_layout_2d) {
        vkDestroyShaderModule(a->device, tri_vert, NULL);
        vkDestroyShaderModule(a->device, tri_frag, NULL);
        goto offs_fail;
    }

    a->offs_pipeline = create_graphics_pipeline(a->device,
        a->pipe_layout_2d, a->offs_render_pass,
        tri_vert, tri_frag, width, height, 0, 0);
    vkDestroyShaderModule(a->device, tri_vert, NULL);
    vkDestroyShaderModule(a->device, tri_frag, NULL);

    if (!a->offs_pipeline) goto offs_fail;

    a->cmd_pool = create_cmd_pool(a->device, a->graphics_family);
    if (!a->cmd_pool) goto offs_fail;

    if (!allocate_cmd_buffers(a->device, a->cmd_pool, &a->offs_cmd, 1))
        goto offs_fail;

    VkDeviceSize buf_size = (VkDeviceSize)(width * height * 4);
    VkBufferCreateInfo bci = {0};
    bci.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bci.size  = buf_size;
    bci.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    VkResult res = vkCreateBuffer(a->device, &bci, NULL, &a->offs_readback);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("offscreen vkCreateBuffer: %d", (int)res);
        goto offs_fail;
    }

    VkMemoryRequirements bmr;
    vkGetBufferMemoryRequirements(a->device, a->offs_readback, &bmr);
    uint32_t bmi = find_memory_type(&a->mem_props, bmr.memoryTypeBits,
                                     VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                     VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (bmi == UINT32_MAX) { xvk_set_error("no host mem for readback"); goto offs_fail; }

    VkMemoryAllocateInfo bmai = {0};
    bmai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    bmai.allocationSize  = bmr.size;
    bmai.memoryTypeIndex = bmi;
    res = vkAllocateMemory(a->device, &bmai, NULL, &a->offs_readback_mem);
    if (res != VK_SUCCESS) { xvk_set_error_fmt("offscreen alloc readback mem: %d", (int)res); goto offs_fail; }
    res = vkBindBufferMemory(a->device, a->offs_readback, a->offs_readback_mem, 0);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("offscreen vkBindBufferMemory: %d", (int)res);
        goto offs_fail;
    }

    res = vkMapMemory(a->device, a->offs_readback_mem, 0, buf_size, 0, &a->offs_mapped);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("offscreen vkMapMemory: %d", (int)res);
        a->offs_mapped = NULL;
        goto offs_fail;
    }

    VkFenceCreateInfo fci = {0};
    fci.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    res = vkCreateFence(a->device, &fci, NULL, &a->offs_fence);
    if (res != VK_SUCCESS) { xvk_set_error_fmt("offscreen vkCreateFence: %d", (int)res); goto offs_fail; }

    a->magic        = XVK_MAGIC;
    a->is_offscreen = 1;
    a->clear_r = a->clear_g = a->clear_b = 0.0f;
    xvk_set_error("");
    return xvk_to_handle(a);

offs_fail:
    xvk_app_cleanup_internal(a);
    /* No glfwTerminate() needed — headless path doesn't use GLFW */
    free(a);
    return 0;
}

int32_t xvk_offscreen_render_triangle(int64_t app_h, float r, float g, float b)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->is_offscreen) return -1;

    if (a->offs_fence) {
        VkResult wait_res = vkWaitForFences(a->device, 1, &a->offs_fence, VK_TRUE, UINT64_MAX);
        if (wait_res != VK_SUCCESS) {
            xvk_set_error_fmt("vkWaitForFences(offscreen): %d", (int)wait_res);
            return 0;
        }
        vkResetFences(a->device, 1, &a->offs_fence);
    }

    VkCommandBuffer cb = a->offs_cmd;
    vkResetCommandBuffer(cb, 0);

    VkCommandBufferBeginInfo cbbi = {0};
    cbbi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    cbbi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if (vkBeginCommandBuffer(cb, &cbbi) != VK_SUCCESS) {
        xvk_set_error("offscreen vkBeginCommandBuffer failed");
        return 0;
    }

    VkClearValue clear;
    clear.color.float32[0] = 0.0f;
    clear.color.float32[1] = 0.0f;
    clear.color.float32[2] = 0.0f;
    clear.color.float32[3] = 1.0f;

    VkRenderPassBeginInfo rpbi = {0};
    rpbi.sType       = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rpbi.renderPass  = a->offs_render_pass;
    rpbi.framebuffer = a->offs_framebuffer;
    rpbi.renderArea.offset.x = 0;
    rpbi.renderArea.offset.y = 0;
    rpbi.renderArea.extent.width  = (uint32_t)a->offs_w;
    rpbi.renderArea.extent.height = (uint32_t)a->offs_h;
    rpbi.clearValueCount     = 1;
    rpbi.pClearValues        = &clear;
    vkCmdBeginRenderPass(cb, &rpbi, VK_SUBPASS_CONTENTS_INLINE);

    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, a->offs_pipeline);
    float colour[4] = { r, g, b, 1.0f };
    vkCmdPushConstants(cb, a->pipe_layout_2d, VK_SHADER_STAGE_VERTEX_BIT,
                       0, 16, colour);
    vkCmdDraw(cb, 3, 1, 0, 0);

    vkCmdEndRenderPass(cb);

    VkImageMemoryBarrier imb = {0};
    imb.sType               = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    imb.srcAccessMask       = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    imb.dstAccessMask       = VK_ACCESS_TRANSFER_READ_BIT;
    imb.oldLayout           = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    imb.newLayout           = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    imb.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    imb.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    imb.image               = a->offs_image;
    imb.subresourceRange.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
    imb.subresourceRange.baseMipLevel   = 0;
    imb.subresourceRange.levelCount     = 1;
    imb.subresourceRange.baseArrayLayer = 0;
    imb.subresourceRange.layerCount     = 1;
    vkCmdPipelineBarrier(cb,
        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, 0, NULL, 0, NULL, 1, &imb);

    VkBufferImageCopy bic = {0};
    bic.bufferOffset      = 0;
    bic.bufferRowLength   = 0;
    bic.bufferImageHeight = 0;
    bic.imageSubresource.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
    bic.imageSubresource.mipLevel       = 0;
    bic.imageSubresource.baseArrayLayer = 0;
    bic.imageSubresource.layerCount     = 1;
    bic.imageOffset.x = 0;
    bic.imageOffset.y = 0;
    bic.imageOffset.z = 0;
    bic.imageExtent.width  = (uint32_t)a->offs_w;
    bic.imageExtent.height = (uint32_t)a->offs_h;
    bic.imageExtent.depth  = 1;
    vkCmdCopyImageToBuffer(cb, a->offs_image,
                           VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                           a->offs_readback, 1, &bic);

    if (vkEndCommandBuffer(cb) != VK_SUCCESS) {
        xvk_set_error("offscreen vkEndCommandBuffer failed");
        return 0;
    }

    VkSubmitInfo si = {0};
    si.sType              = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1;
    si.pCommandBuffers    = &cb;
    VkResult res = vkQueueSubmit(a->graphics_queue, 1, &si, a->offs_fence);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("offscreen vkQueueSubmit failed: %d", (int)res);
        return 0;
    }

    vkWaitForFences(a->device, 1, &a->offs_fence, VK_TRUE, UINT64_MAX);
    return 1;
}

uint32_t xvk_offscreen_pixel(int64_t app_h, int32_t x, int32_t y)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->is_offscreen || !a->offs_mapped) return 0;
    if (x < 0 || x >= a->offs_w || y < 0 || y >= a->offs_h) return 0;

    uint32_t* pixels = (uint32_t*)a->offs_mapped;
    uint32_t bgra = pixels[(uint32_t)y * (uint32_t)a->offs_w + (uint32_t)x];

    uint32_t b = (bgra >> 0)  & 0xFF;
    uint32_t g = (bgra >> 8)  & 0xFF;
    uint32_t rv = (bgra >> 16) & 0xFF;
    uint32_t av = (bgra >> 24) & 0xFF;
    return (rv << 24) | (g << 16) | (b << 8) | av;
}

uint64_t xvk_offscreen_hash(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->is_offscreen || !a->offs_mapped) return 0;

    uint64_t hash = 0xCBF29CE484222325ULL;
    uint32_t count = (uint32_t)(a->offs_w * a->offs_h * 4);
    unsigned char* buf = (unsigned char*)a->offs_mapped;

    for (uint32_t i = 0; i < count; ++i) {
        hash ^= (uint64_t)buf[i];
        hash *= 0x100000001B3ULL;
    }
    return hash;
}

void xvk_offscreen_destroy(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return;
    xvk_app_cleanup_internal(a);
    free(a);
}
