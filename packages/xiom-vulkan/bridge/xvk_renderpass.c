#include "xvk_renderpass.h"
#include <stdlib.h>

VkRenderPass create_render_pass(VkDevice dev, VkFormat colour_fmt,
                                 VkFormat depth_fmt)
{
    VkAttachmentDescription att[2] = {{0}};
    att[0].format         = colour_fmt;
    att[0].samples        = VK_SAMPLE_COUNT_1_BIT;
    att[0].loadOp         = VK_ATTACHMENT_LOAD_OP_CLEAR;
    att[0].storeOp        = VK_ATTACHMENT_STORE_OP_STORE;
    att[0].stencilLoadOp  = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    att[0].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    att[0].initialLayout  = VK_IMAGE_LAYOUT_UNDEFINED;
    att[0].finalLayout    = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    att[1].format         = depth_fmt;
    att[1].samples        = VK_SAMPLE_COUNT_1_BIT;
    att[1].loadOp         = VK_ATTACHMENT_LOAD_OP_CLEAR;
    att[1].storeOp        = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    att[1].stencilLoadOp  = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    att[1].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    att[1].initialLayout  = VK_IMAGE_LAYOUT_UNDEFINED;
    att[1].finalLayout    = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

    VkAttachmentReference col_ref = {0};
    col_ref.attachment = 0;
    col_ref.layout     = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkAttachmentReference depth_ref = {0};
    depth_ref.attachment = 1;
    depth_ref.layout     = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

    VkSubpassDescription subpass = {0};
    subpass.pipelineBindPoint    = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments    = &col_ref;
    subpass.pDepthStencilAttachment = &depth_ref;

    VkSubpassDependency dep = {0};
    dep.srcSubpass    = VK_SUBPASS_EXTERNAL;
    dep.dstSubpass    = 0;
    dep.srcStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                        VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dep.dstStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                        VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dep.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT |
                        VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;

    VkRenderPassCreateInfo rpci = {0};
    rpci.sType           = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    rpci.attachmentCount = 2;
    rpci.pAttachments    = att;
    rpci.subpassCount    = 1;
    rpci.pSubpasses      = &subpass;
    rpci.dependencyCount = 1;
    rpci.pDependencies   = &dep;

    VkRenderPass rp = VK_NULL_HANDLE;
    VkResult res = vkCreateRenderPass(dev, &rpci, NULL, &rp);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateRenderPass failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return rp;
}

int create_framebuffers(XvkApp* a)
{
    a->framebuffers = (VkFramebuffer*)malloc(
        a->swapchain_image_count * sizeof(VkFramebuffer));
    if (!a->framebuffers) {
        xvk_set_error("malloc failed for framebuffers");
        return 0;
    }

    for (int i = 0; i < a->swapchain_image_count; ++i) {
        VkImageView attachments[2] = {
            a->swapchain_image_views[i],
            a->depth_image_view
        };
        VkFramebufferCreateInfo fci = {0};
        fci.sType           = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        fci.renderPass      = a->render_pass;
        fci.attachmentCount = 2;
        fci.pAttachments    = attachments;
        fci.width           = a->swapchain_extent.width;
        fci.height          = a->swapchain_extent.height;
        fci.layers          = 1;

        VkResult res = vkCreateFramebuffer(a->device, &fci, NULL,
                                            &a->framebuffers[i]);
        if (res != VK_SUCCESS) {
            xvk_set_error_fmt("vkCreateFramebuffer[%d] failed: %d", i, (int)res);
            for (int j = 0; j < i; ++j)
                vkDestroyFramebuffer(a->device, a->framebuffers[j], NULL);
            free(a->framebuffers);
            a->framebuffers = NULL;
            return 0;
        }
    }
    return 1;
}

int64_t xvk_render_pass_create(int64_t app_h, const int32_t* color_formats,
                                int32_t color_count, int32_t depth_format)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || color_count <= 0) return 0;

    XvkRenderPass* rp = (XvkRenderPass*)calloc(1, sizeof(XvkRenderPass));
    if (!rp) { xvk_set_error("calloc render pass"); return 0; }

    int att_count = color_count + (depth_format > 0 ? 1 : 0);
    VkAttachmentDescription* atts = (VkAttachmentDescription*)
        malloc((size_t)att_count * sizeof(VkAttachmentDescription));
    VkAttachmentReference* col_refs = (VkAttachmentReference*)
        malloc((size_t)color_count * sizeof(VkAttachmentReference));
    if (!atts || !col_refs) {
        if (atts) free(atts); if (col_refs) free(col_refs);
        free(rp); xvk_set_error("malloc attachments"); return 0;
    }
    memset(atts, 0, (size_t)att_count * sizeof(VkAttachmentDescription));

    for (int i = 0; i < color_count; ++i) {
        int off = i * 4;
        int fmt = color_formats[off];
        atts[i].format         = fmt == 2 ? a->swapchain_fmt : xvk_map_format(fmt > 0 ? fmt : 1);
        atts[i].samples        = VK_SAMPLE_COUNT_1_BIT;
        atts[i].loadOp         = color_formats[off+1] == 1 ? VK_ATTACHMENT_LOAD_OP_LOAD :
                                 color_formats[off+1] == 2 ? VK_ATTACHMENT_LOAD_OP_DONT_CARE :
                                 VK_ATTACHMENT_LOAD_OP_CLEAR;
        atts[i].storeOp        = color_formats[off+2] == 1 ? VK_ATTACHMENT_STORE_OP_DONT_CARE :
                                 VK_ATTACHMENT_STORE_OP_STORE;
        atts[i].stencilLoadOp  = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        atts[i].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        atts[i].initialLayout  = VK_IMAGE_LAYOUT_UNDEFINED;
        int fl = color_formats[off+3];
        atts[i].finalLayout    = fl == 1 ? VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL :
                                 fl == 2 ? VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL :
                                 VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        col_refs[i].attachment = (uint32_t)i;
        col_refs[i].layout     = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    }

    VkAttachmentReference depth_ref = {0};
    if (depth_format > 0) {
        int di = color_count;
        atts[di].format         = xvk_map_format(depth_format);
        atts[di].samples        = VK_SAMPLE_COUNT_1_BIT;
        atts[di].loadOp         = VK_ATTACHMENT_LOAD_OP_CLEAR;
        atts[di].storeOp        = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        atts[di].stencilLoadOp  = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        atts[di].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        atts[di].initialLayout  = VK_IMAGE_LAYOUT_UNDEFINED;
        atts[di].finalLayout    = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        depth_ref.attachment = (uint32_t)di;
        depth_ref.layout     = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    }

    VkSubpassDescription subpass = {0};
    subpass.pipelineBindPoint       = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount    = (uint32_t)color_count;
    subpass.pColorAttachments       = col_refs;
    subpass.pDepthStencilAttachment = depth_format > 0 ? &depth_ref : NULL;

    VkSubpassDependency dep = {0};
    dep.srcSubpass    = VK_SUBPASS_EXTERNAL;
    dep.dstSubpass    = 0;
    dep.srcStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                        VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dep.dstStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                        VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dep.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT |
                        VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;

    VkRenderPassCreateInfo rpci = {0};
    rpci.sType           = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    rpci.attachmentCount = (uint32_t)att_count;
    rpci.pAttachments    = atts;
    rpci.subpassCount    = 1;
    rpci.pSubpasses      = &subpass;
    rpci.dependencyCount = 1;
    rpci.pDependencies   = &dep;

    VkResult res = vkCreateRenderPass(a->device, &rpci, NULL, &rp->render_pass);
    free(atts); free(col_refs);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateRenderPass: %d", (int)res);
        free(rp); return 0;
    }
    rp->magic = XVK_RENDERPASS_MAGIC;
    return xvk_rp_to_handle(rp);
}

void xvk_render_pass_destroy(int64_t app_h, int64_t rp_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkRenderPass* rp = xvk_rp_from_handle(rp_h);
    if (!a || !rp) return;
    if (rp->render_pass) vkDestroyRenderPass(a->device, rp->render_pass, NULL);
    rp->magic = 0;
    free(rp);
}

int64_t xvk_framebuffer_create(int64_t app_h, int64_t render_pass_h,
                                const int64_t* attachments, int32_t attachment_count,
                                int32_t width, int32_t height)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkRenderPass* rp = xvk_rp_from_handle(render_pass_h);
    if (!a || !rp || !attachments || attachment_count <= 0) return 0;

    XvkFramebuffer* fb = (XvkFramebuffer*)calloc(1, sizeof(XvkFramebuffer));
    if (!fb) { xvk_set_error("calloc framebuffer"); return 0; }

    VkImageView* views = (VkImageView*)malloc((size_t)attachment_count * sizeof(VkImageView));
    if (!views) { free(fb); return 0; }
    for (int i = 0; i < attachment_count; ++i) {
        XvkImageView* v = xvk_view_from_handle(attachments[i]);
        views[i] = v ? v->view : VK_NULL_HANDLE;
    }

    VkFramebufferCreateInfo fci = {0};
    fci.sType           = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
    fci.renderPass      = rp->render_pass;
    fci.attachmentCount = (uint32_t)attachment_count;
    fci.pAttachments    = views;
    fci.width           = (uint32_t)width;
    fci.height          = (uint32_t)height;
    fci.layers          = 1;

    VkResult res = vkCreateFramebuffer(a->device, &fci, NULL, &fb->framebuffer);
    free(views);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateFramebuffer: %d", (int)res);
        free(fb); return 0;
    }
    fb->magic = XVK_FRAMEBUFFER_MAGIC;
    return xvk_fb_to_handle(fb);
}

void xvk_framebuffer_destroy(int64_t app_h, int64_t fb_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkFramebuffer* fb = xvk_fb_from_handle(fb_h);
    if (!a || !fb) return;
    if (fb->framebuffer) vkDestroyFramebuffer(a->device, fb->framebuffer, NULL);
    fb->magic = 0;
    free(fb);
}
