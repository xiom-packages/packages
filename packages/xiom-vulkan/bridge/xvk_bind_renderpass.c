#include "xvk_bind_renderpass.h"

#include <vulkan/vulkan.h>

#include "xvk_util.h"

int64_t xvk_create_render_pass(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkRenderPassCreateInfo* ci =
        (const VkRenderPassCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) {
        xvk_set_error("xvk_create_render_pass: null device or create info");
        return 0;
    }
    VkRenderPass rp = VK_NULL_HANDLE;
    VkResult res = vkCreateRenderPass(dev, ci, NULL, &rp);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateRenderPass: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)rp;
}

void xvk_destroy_render_pass(int64_t device, int64_t render_pass)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (!dev || !render_pass) return;
    vkDestroyRenderPass(dev, (VkRenderPass)(uint64_t)render_pass, NULL);
}

int64_t xvk_create_framebuffer(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkFramebufferCreateInfo* ci =
        (const VkFramebufferCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) {
        xvk_set_error("xvk_create_framebuffer: null device or create info");
        return 0;
    }
    VkFramebuffer fb = VK_NULL_HANDLE;
    VkResult res = vkCreateFramebuffer(dev, ci, NULL, &fb);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateFramebuffer: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)fb;
}

void xvk_destroy_framebuffer(int64_t device, int64_t framebuffer)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (!dev || !framebuffer) return;
    vkDestroyFramebuffer(dev, (VkFramebuffer)(uint64_t)framebuffer, NULL);
}
