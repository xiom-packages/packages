#include "xvk_swapchain.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

VkSurfaceFormatKHR pick_swapchain_fmt(VkPhysicalDevice pd,
                                       VkSurfaceKHR surface)
{
    uint32_t n = 0;
    VkResult res = vkGetPhysicalDeviceSurfaceFormatsKHR(pd, surface, &n, NULL);
    if (res != VK_SUCCESS || n == 0) {
        /* Surface lost or no formats — return safe default */
        VkSurfaceFormatKHR def = { VK_FORMAT_B8G8R8A8_UNORM,
                                   VK_COLOR_SPACE_SRGB_NONLINEAR_KHR };
        return def;
    }
    VkSurfaceFormatKHR* fmts = (VkSurfaceFormatKHR*)
        malloc(n * sizeof(VkSurfaceFormatKHR));
    if (!fmts) {
        VkSurfaceFormatKHR def = { VK_FORMAT_B8G8R8A8_UNORM,
                                   VK_COLOR_SPACE_SRGB_NONLINEAR_KHR };
        return def;
    }
    res = vkGetPhysicalDeviceSurfaceFormatsKHR(pd, surface, &n, fmts);

    VkSurfaceFormatKHR chosen = {0};
    chosen.format = VK_FORMAT_B8G8R8A8_UNORM;
    chosen.colorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;

    if (res == VK_SUCCESS) {
        for (uint32_t i = 0; i < n; ++i) {
            if (fmts[i].format == VK_FORMAT_B8G8R8A8_UNORM &&
                fmts[i].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                chosen = fmts[i];
                break;
            }
        }
    }
    free(fmts);
    return chosen;
}

VkPresentModeKHR pick_present_mode(VkPhysicalDevice pd,
                                    VkSurfaceKHR surface)
{
    uint32_t n = 0;
    VkResult res = vkGetPhysicalDeviceSurfacePresentModesKHR(pd, surface, &n, NULL);
    if (res != VK_SUCCESS || n == 0) {
        return VK_PRESENT_MODE_FIFO_KHR;  /* safe fallback */
    }
    VkPresentModeKHR* modes = (VkPresentModeKHR*)
        malloc(n * sizeof(VkPresentModeKHR));
    if (!modes) {
        return VK_PRESENT_MODE_FIFO_KHR;
    }
    res = vkGetPhysicalDeviceSurfacePresentModesKHR(pd, surface, &n, modes);

    VkPresentModeKHR chosen = VK_PRESENT_MODE_FIFO_KHR;
    if (res == VK_SUCCESS) {
        for (uint32_t i = 0; i < n; ++i) {
            if (modes[i] == VK_PRESENT_MODE_MAILBOX_KHR) {
                chosen = modes[i];
                break;
            }
        }
    }
    free(modes);
    return chosen;
}

VkExtent2D pick_extent(VkPhysicalDevice pd, VkSurfaceKHR surface,
                        GLFWwindow* win)
{
    VkSurfaceCapabilitiesKHR caps;
    memset(&caps, 0, sizeof(caps));  /* zero-init: safe if query fails */
    VkResult res = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pd, surface, &caps);

    if (res == VK_SUCCESS && caps.currentExtent.width != UINT32_MAX &&
        caps.currentExtent.width > 0 && caps.currentExtent.height > 0)
        return caps.currentExtent;

    /* Surface query failed, surface has no fixed size, or extent is zero.
     * Fall back to glfwGetFramebufferSize as authoritative source. */
    int w, h;
    glfwGetFramebufferSize(win, &w, &h);
    VkExtent2D ext = {
        (uint32_t)(w > 0 ? w : 1),
        (uint32_t)(h > 0 ? h : 1)
    };

    /* Clamp to surface limits if we have valid caps data */
    if (res == VK_SUCCESS) {
        if (ext.width  < caps.minImageExtent.width)  ext.width  = caps.minImageExtent.width;
        if (ext.height < caps.minImageExtent.height) ext.height = caps.minImageExtent.height;
        if (caps.maxImageExtent.width  > 0 && ext.width  > caps.maxImageExtent.width)  ext.width  = caps.maxImageExtent.width;
        if (caps.maxImageExtent.height > 0 && ext.height > caps.maxImageExtent.height) ext.height = caps.maxImageExtent.height;
    }
    return ext;
}

int create_depth_resources(XvkApp* a)
{
    VkFormat df = find_depth_format(a->phys_dev);
    if (df == VK_FORMAT_UNDEFINED) {
        xvk_set_error("no suitable depth format found");
        return 0;
    }
    a->depth_format = df;

    VkImageCreateInfo ici = {0};
    ici.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ici.imageType = VK_IMAGE_TYPE_2D;
    ici.format = df;
    ici.extent.width  = a->swapchain_extent.width;
    ici.extent.height = a->swapchain_extent.height;
    ici.extent.depth  = 1;
    ici.mipLevels = 1;
    ici.arrayLayers = 1;
    ici.samples = VK_SAMPLE_COUNT_1_BIT;
    ici.tiling = VK_IMAGE_TILING_OPTIMAL;
    ici.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    VkResult res = vkCreateImage(a->device, &ici, NULL, &a->depth_image);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateImage (depth) failed: %d", (int)res);
        return 0;
    }

    VkMemoryRequirements mr;
    vkGetImageMemoryRequirements(a->device, a->depth_image, &mr);
    uint32_t mi = find_memory_type(&a->mem_props, mr.memoryTypeBits,
                                    VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (mi == UINT32_MAX) {
        xvk_set_error("no device-local memory for depth image");
        vkDestroyImage(a->device, a->depth_image, NULL);
        a->depth_image = VK_NULL_HANDLE;
        return 0;
    }

    VkMemoryAllocateInfo mai = {0};
    mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    mai.allocationSize = mr.size;
    mai.memoryTypeIndex = mi;
    res = vkAllocateMemory(a->device, &mai, NULL, &a->depth_memory);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkAllocateMemory (depth) failed: %d", (int)res);
        vkDestroyImage(a->device, a->depth_image, NULL);
        a->depth_image = VK_NULL_HANDLE;
        return 0;
    }

    res = vkBindImageMemory(a->device, a->depth_image, a->depth_memory, 0);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkBindImageMemory (depth): %d", (int)res);
        vkFreeMemory(a->device, a->depth_memory, NULL);
        a->depth_memory = VK_NULL_HANDLE;
        vkDestroyImage(a->device, a->depth_image, NULL);
        a->depth_image = VK_NULL_HANDLE;
        return 0;
    }

    VkImageViewCreateInfo ivci = {0};
    ivci.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    ivci.image = a->depth_image;
    ivci.viewType = VK_IMAGE_VIEW_TYPE_2D;
    ivci.format = df;
    ivci.subresourceRange.aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT;
    if (df == VK_FORMAT_D24_UNORM_S8_UINT || df == VK_FORMAT_D32_SFLOAT_S8_UINT)
        ivci.subresourceRange.aspectMask |= VK_IMAGE_ASPECT_STENCIL_BIT;
    ivci.subresourceRange.baseMipLevel = 0;
    ivci.subresourceRange.levelCount = 1;
    ivci.subresourceRange.baseArrayLayer = 0;
    ivci.subresourceRange.layerCount = 1;

    res = vkCreateImageView(a->device, &ivci, NULL, &a->depth_image_view);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateImageView (depth) failed: %d", (int)res);
        vkFreeMemory(a->device, a->depth_memory, NULL);
        a->depth_memory = VK_NULL_HANDLE;
        vkDestroyImage(a->device, a->depth_image, NULL);
        a->depth_image = VK_NULL_HANDLE;
        return 0;
    }
    return 1;
}

int create_swapchain(XvkApp* a)
{
    VkSurfaceCapabilitiesKHR caps;
    memset(&caps, 0, sizeof(caps));
    VkResult caps_res = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
        a->phys_dev, a->surface, &caps);
    /* If surface query fails, caps is zeroed; pick_extent falls back to GLFW.
     * minImageCount defaults to 2 (safe minimum); transform + alpha use defaults. */

    int32_t min_images = 2;
    if (caps_res == VK_SUCCESS && caps.minImageCount > 0) {
        min_images = (int32_t)caps.minImageCount;
    }

    VkSurfaceFormatKHR fmt = pick_swapchain_fmt(a->phys_dev, a->surface);
    VkPresentModeKHR   pm  = pick_present_mode(a->phys_dev, a->surface);
    VkExtent2D         ext = pick_extent(a->phys_dev, a->surface, a->window);

    a->swapchain_fmt    = fmt.format;
    a->swapchain_extent = ext;

    uint32_t desired = (uint32_t)(min_images + 1);
    if (caps_res == VK_SUCCESS && caps.maxImageCount > 0 && desired > caps.maxImageCount)
        desired = caps.maxImageCount;

    VkSwapchainCreateInfoKHR sci = {0};
    sci.sType            = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    sci.surface          = a->surface;
    sci.minImageCount    = desired;
    sci.imageFormat      = fmt.format;
    sci.imageColorSpace  = fmt.colorSpace;
    sci.imageExtent      = ext;
    sci.imageArrayLayers = 1;
    sci.imageUsage       = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    sci.preTransform     = (caps_res == VK_SUCCESS)
        ? caps.currentTransform : VK_SURFACE_TRANSFORM_IDENTITY_BIT_KHR;
    sci.compositeAlpha   = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    sci.presentMode      = pm;
    sci.clipped          = VK_TRUE;

    uint32_t families[2] = {
        a->graphics_family, a->present_family
    };
    if (a->graphics_family != a->present_family) {
        sci.imageSharingMode      = VK_SHARING_MODE_CONCURRENT;
        sci.queueFamilyIndexCount = 2;
        sci.pQueueFamilyIndices   = families;
    } else {
        sci.imageSharingMode      = VK_SHARING_MODE_EXCLUSIVE;
        sci.queueFamilyIndexCount = 0;
    }

    VkResult res = vkCreateSwapchainKHR(a->device, &sci, NULL, &a->swapchain);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateSwapchainKHR failed: %d", (int)res);
        return 0;
    }

    vkGetSwapchainImagesKHR(a->device, a->swapchain, &desired, NULL);
    a->swapchain_image_count = (int)desired;
    a->swapchain_images = (VkImage*)malloc(desired * sizeof(VkImage));
    if (!a->swapchain_images) {
        xvk_set_error("malloc failed for swapchain_images");
        return 0;
    }
    vkGetSwapchainImagesKHR(a->device, a->swapchain, &desired,
                            a->swapchain_images);

    a->swapchain_image_views = (VkImageView*)malloc(
        desired * sizeof(VkImageView));
    if (!a->swapchain_image_views) {
        xvk_set_error("malloc failed for swapchain_image_views");
        return 0;
    }
    for (uint32_t i = 0; i < desired; ++i) {
        VkImageViewCreateInfo ivci = {0};
        ivci.sType    = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        ivci.image    = a->swapchain_images[i];
        ivci.viewType = VK_IMAGE_VIEW_TYPE_2D;
        ivci.format   = fmt.format;
        ivci.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
        ivci.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
        ivci.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
        ivci.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
        ivci.subresourceRange.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
        ivci.subresourceRange.baseMipLevel   = 0;
        ivci.subresourceRange.levelCount     = 1;
        ivci.subresourceRange.baseArrayLayer = 0;
        ivci.subresourceRange.layerCount     = 1;

        VkResult r = vkCreateImageView(a->device, &ivci, NULL,
                                        &a->swapchain_image_views[i]);
        if (r != VK_SUCCESS) {
            xvk_set_error_fmt("vkCreateImageView[%u] failed: %d", i, (int)r);
            return 0;
        }
    }
    return 1;
}

void cleanup_swapchain(XvkApp* a)
{
    vkDeviceWaitIdle(a->device);

    for (int i = 0; i < a->swapchain_image_count; ++i) {
        if (a->framebuffers && a->framebuffers[i])
            vkDestroyFramebuffer(a->device, a->framebuffers[i], NULL);
        if (a->swapchain_image_views && a->swapchain_image_views[i])
            vkDestroyImageView(a->device, a->swapchain_image_views[i], NULL);
    }
    free(a->framebuffers);        a->framebuffers        = NULL;
    free(a->swapchain_image_views); a->swapchain_image_views = NULL;
    free(a->swapchain_images);    a->swapchain_images    = NULL;
    a->swapchain_image_count = 0;

    if (a->depth_image_view)
        vkDestroyImageView(a->device, a->depth_image_view, NULL);
    if (a->depth_image)
        vkDestroyImage(a->device, a->depth_image, NULL);
    if (a->depth_memory)
        vkFreeMemory(a->device, a->depth_memory, NULL);
    a->depth_image_view = VK_NULL_HANDLE;
    a->depth_image      = VK_NULL_HANDLE;
    a->depth_memory     = VK_NULL_HANDLE;

    if (a->swapchain)
        vkDestroySwapchainKHR(a->device, a->swapchain, NULL);
    a->swapchain = VK_NULL_HANDLE;
}

int recreate_swapchain(XvkApp* a)
{
    /* Save old state in case recreation fails */
    VkSwapchainKHR old_swapchain   = a->swapchain;
    VkImage*       old_images      = a->swapchain_images;
    VkImageView*   old_views       = a->swapchain_image_views;
    VkFramebuffer* old_fb          = a->framebuffers;
    int            old_count       = a->swapchain_image_count;

    /* Also save old depth resources — create_depth_resources overwrites them */
    VkImage        old_depth_img  = a->depth_image;
    VkDeviceMemory old_depth_mem  = a->depth_memory;
    VkImageView    old_depth_view = a->depth_image_view;

    /* Null out so cleanup doesn't free them (we'll do it explicitly) */
    a->swapchain           = VK_NULL_HANDLE;
    a->swapchain_images    = NULL;
    a->swapchain_image_views = NULL;
    a->framebuffers        = NULL;
    a->depth_image         = VK_NULL_HANDLE;
    a->depth_memory        = VK_NULL_HANDLE;
    a->depth_image_view    = VK_NULL_HANDLE;

    if (!create_swapchain(a)) {
        /* Restore old swapchain and continue */
        a->swapchain            = old_swapchain;
        a->swapchain_images     = old_images;
        a->swapchain_image_views = old_views;
        a->framebuffers         = old_fb;
        a->depth_image          = old_depth_img;
        a->depth_memory         = old_depth_mem;
        a->depth_image_view     = old_depth_view;
        a->swapchain_image_count = old_count;
        return 0;
    }
    if (!create_depth_resources(a)) {
        cleanup_swapchain(a);
        a->swapchain            = old_swapchain;
        a->swapchain_images     = old_images;
        a->swapchain_image_views = old_views;
        a->framebuffers         = old_fb;
        a->depth_image          = old_depth_img;
        a->depth_memory         = old_depth_mem;
        a->depth_image_view     = old_depth_view;
        a->swapchain_image_count = old_count;
        return 0;
    }
    if (!create_framebuffers(a)) {
        cleanup_swapchain(a);
        a->swapchain            = old_swapchain;
        a->swapchain_images     = old_images;
        a->swapchain_image_views = old_views;
        a->framebuffers         = old_fb;
        a->depth_image          = old_depth_img;
        a->depth_memory         = old_depth_mem;
        a->depth_image_view     = old_depth_view;
        a->swapchain_image_count = old_count;
        return 0;
    }

    /* Allocate new command buffers BEFORE freeing old ones.
     * If alloc fails, old CBs are still valid and old state is restored. */
    {
        VkCommandBuffer* new_cb = (VkCommandBuffer*)malloc(
            a->swapchain_image_count * sizeof(VkCommandBuffer));
        if (!new_cb) {
            xvk_set_error("malloc cmd_buffers failed in resize");
            /* Restore old state */
            a->swapchain            = old_swapchain;
            a->swapchain_images     = old_images;
            a->swapchain_image_views = old_views;
            a->framebuffers         = old_fb;
            a->depth_image          = old_depth_img;
            a->depth_memory         = old_depth_mem;
            a->depth_image_view     = old_depth_view;
            a->swapchain_image_count = old_count;
            /* Destroy the new-but-unused swapchain resources */
            cleanup_swapchain(a);
            return 0;
        }

        VkCommandBufferAllocateInfo cbai = {0};
        cbai.sType              = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        cbai.commandPool        = a->cmd_pool;
        cbai.level              = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cbai.commandBufferCount = (uint32_t)a->swapchain_image_count;
        VkResult res = vkAllocateCommandBuffers(a->device, &cbai, new_cb);
        if (res != VK_SUCCESS) {
            xvk_set_error_fmt("allocate cmd buffers failed in resize: %d", (int)res);
            free(new_cb);
            /* Restore old state */
            a->swapchain            = old_swapchain;
            a->swapchain_images     = old_images;
            a->swapchain_image_views = old_views;
            a->framebuffers         = old_fb;
            a->depth_image          = old_depth_img;
            a->depth_memory         = old_depth_mem;
            a->depth_image_view     = old_depth_view;
            a->swapchain_image_count = old_count;
            cleanup_swapchain(a);
            return 0;
        }

        /* New CBs allocated — now safe to free old CBs and old swapchain */
        if (a->cmd_buffers) {
            vkFreeCommandBuffers(a->device, a->cmd_pool,
                                 (uint32_t)old_count, a->cmd_buffers);
            free(a->cmd_buffers);
        }
        a->cmd_buffers = new_cb;
    }

    /* Success — wait for device idle, then free old resources */
    vkDeviceWaitIdle(a->device);
    for (int i = 0; i < old_count; i++) {
        if (old_fb)    vkDestroyFramebuffer(a->device, old_fb[i], NULL);
        if (old_views) vkDestroyImageView(a->device, old_views[i], NULL);
    }
    free(old_fb);
    free(old_views);
    free(old_images);
    if (old_swapchain != VK_NULL_HANDLE)
        vkDestroySwapchainKHR(a->device, old_swapchain, NULL);
    if (old_depth_view)
        vkDestroyImageView(a->device, old_depth_view, NULL);
    if (old_depth_img)
        vkDestroyImage(a->device, old_depth_img, NULL);
    if (old_depth_mem)
        vkFreeMemory(a->device, old_depth_mem, NULL);

    return 1;
}
