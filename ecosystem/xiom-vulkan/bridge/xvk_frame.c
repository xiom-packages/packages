#include "xvk_frame.h"
#include "xvk_swapchain.h"

int32_t xvk_begin_frame(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return -1;

    if (a->window) {
        int w, h;
        glfwGetFramebufferSize(a->window, &w, &h);
        if (w <= 0 || h <= 0) return 0;
        if (w != (int)a->swapchain_extent.width ||
            h != (int)a->swapchain_extent.height) {
            /* Try to resize — if it fails just skip this frame.
             * The window might be momentarily invalid (minimized, DPI change).
             * We'll retry on the next frame. */
            if (recreate_swapchain(a)) return 0;
            /* recreate failed, but that's OK — keep trying */
            return 0;
        }
    }

    VkSemaphore avail = a->image_available[a->frame_index];
    VkFence    fence  = a->in_flight_fences[a->frame_index];

    vkWaitForFences(a->device, 1, &fence, VK_TRUE, UINT64_MAX);
    vkResetFences(a->device, 1, &fence);

    uint32_t img_idx = 0;
    VkResult res = vkAcquireNextImageKHR(a->device, a->swapchain,
                                          UINT64_MAX, avail,
                                          VK_NULL_HANDLE, &img_idx);
    if (res == VK_ERROR_OUT_OF_DATE_KHR || res == VK_SUBOPTIMAL_KHR) {
        recreate_swapchain(a);
        return 0;
    }
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkAcquireNextImageKHR failed: %d", (int)res);
        return -1;
    }

    a->current_image = img_idx;

    VkCommandBuffer cb = a->cmd_buffers[img_idx];
    vkResetCommandBuffer(cb, 0);

    VkCommandBufferBeginInfo cbbi = {0};
    cbbi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    cbbi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if (vkBeginCommandBuffer(cb, &cbbi) != VK_SUCCESS) {
        xvk_set_error("vkBeginCommandBuffer failed");
        return -1;
    }

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
    rpbi.framebuffer = a->framebuffers[img_idx];
    rpbi.renderArea.offset.x = 0;
    rpbi.renderArea.offset.y = 0;
    rpbi.renderArea.extent   = a->swapchain_extent;
    rpbi.clearValueCount     = 2;
    rpbi.pClearValues        = clears;

    vkCmdBeginRenderPass(cb, &rpbi, VK_SUBPASS_CONTENTS_INLINE);
    a->recording      = 1;
    a->in_render_pass = 1;

    return 1;
}

void xvk_end_frame(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording) return;

    uint32_t img_idx = a->current_image;
    VkCommandBuffer cb = a->cmd_buffers[img_idx];

    vkCmdEndRenderPass(cb);
    a->in_render_pass = 0;
    if (vkEndCommandBuffer(cb) != VK_SUCCESS) {
        xvk_set_error("vkEndCommandBuffer failed");
        a->recording = 0;
        return;
    }
    a->recording = 0;

    VkSemaphore          wait_sems[] = { a->image_available[a->frame_index] };
    VkPipelineStageFlags wait_stages[] = { VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT };
    VkSemaphore          sig_sems[]  = { a->render_finished[a->frame_index] };

    VkSubmitInfo si = {0};
    si.sType                = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.waitSemaphoreCount   = 1;
    si.pWaitSemaphores      = wait_sems;
    si.pWaitDstStageMask    = wait_stages;
    si.commandBufferCount   = 1;
    si.pCommandBuffers      = &cb;
    si.signalSemaphoreCount = 1;
    si.pSignalSemaphores    = sig_sems;

    VkFence fence = a->in_flight_fences[a->frame_index];

    if (vkQueueSubmit(a->graphics_queue, 1, &si, fence) != VK_SUCCESS) {
        xvk_set_error("vkQueueSubmit failed");
    }

    VkSwapchainKHR swapchains[] = { a->swapchain };
    VkPresentInfoKHR pi = {0};
    pi.sType              = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    pi.waitSemaphoreCount = 1;
    pi.pWaitSemaphores    = sig_sems;
    pi.swapchainCount     = 1;
    pi.pSwapchains        = swapchains;
    pi.pImageIndices      = &img_idx;

    VkResult res = vkQueuePresentKHR(a->present_queue, &pi);
    if (res == VK_ERROR_OUT_OF_DATE_KHR || res == VK_SUBOPTIMAL_KHR) {
        recreate_swapchain(a);
    }

    a->frame_index = (a->frame_index + 1) % XVK_MAX_FRAMES;
}

void xvk_set_clear_color(int64_t app_h, float r, float g, float b)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return;
    a->clear_r = r;
    a->clear_g = g;
    a->clear_b = b;
}

void xvk_app_poll(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    glfwPollEvents();
    if (a && a->window) {
        glfwGetCursorPos(a->window, &a->mouse_x, &a->mouse_y);
        a->mouse_btn[0] = glfwGetMouseButton(a->window, GLFW_MOUSE_BUTTON_LEFT);
        a->mouse_btn[1] = glfwGetMouseButton(a->window, GLFW_MOUSE_BUTTON_RIGHT);
        a->mouse_btn[2] = glfwGetMouseButton(a->window, GLFW_MOUSE_BUTTON_MIDDLE);
        a->key_escape = glfwGetKey(a->window, GLFW_KEY_ESCAPE);
        a->key_space  = glfwGetKey(a->window, GLFW_KEY_SPACE);
        a->key_w = glfwGetKey(a->window, GLFW_KEY_W);
        a->key_a = glfwGetKey(a->window, GLFW_KEY_A);
        a->key_s = glfwGetKey(a->window, GLFW_KEY_S);
        a->key_d = glfwGetKey(a->window, GLFW_KEY_D);
    }
}

/* ---- Input queries (Phase 8.2) ---- */

double xvk_get_mouse_x(int64_t app_h) {
    XvkApp* a = xvk_from_handle(app_h);
    return a ? a->mouse_x : 0.0;
}
double xvk_get_mouse_y(int64_t app_h) {
    XvkApp* a = xvk_from_handle(app_h);
    return a ? a->mouse_y : 0.0;
}
int32_t xvk_get_mouse_button(int64_t app_h, int32_t button) {
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || button < 0 || button > 2) return 0;
    return a->mouse_btn[button];
}
int32_t xvk_get_key(int64_t app_h, int32_t key) {
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return 0;
    /* Key codes: 256=ESCAPE, 32=SPACE, 87=W, 65=A, 83=S, 68=D */
    switch (key) {
        case 256: return a->key_escape;
        case 32:  return a->key_space;
        case 87:  return a->key_w;
        case 65:  return a->key_a;
        case 83:  return a->key_s;
        case 68:  return a->key_d;
        default: {
            if (a->window) return glfwGetKey(a->window, key);
            return 0;
        }
    }
}

double xvk_now(void)
{
    return glfwGetTime();
}

int32_t xvk_app_should_close(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->window) return 1;
    return glfwWindowShouldClose(a->window) ? 1 : 0;
}

int32_t xvk_device_type(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    return a ? a->device_type : -1;
}

int32_t xvk_app_valid(int64_t app_h)
{
    return xvk_from_handle(app_h) != NULL ? 1 : 0;
}

const char* xvk_last_error(void)
{
    return g_xvk_error;
}

int32_t xvk_button_hit_state(int64_t app_h,
                              float cx, float cy, float hw, float hh)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->window) return 0;

    double mx, my;
    glfwGetCursorPos(a->window, &mx, &my);

    int win_w, win_h;
    glfwGetFramebufferSize(a->window, &win_w, &win_h);
    if (win_w <= 0 || win_h <= 0) return 0;

    /* Convert NDC to pixel: ndc [-1,1] -> pixel [0,size] */
    double px_cx = ((double)cx + 1.0) * 0.5 * (double)win_w;
    double px_cy = (1.0 - (double)cy) * 0.5 * (double)win_h;
    double px_hw = (double)hw * 0.5 * (double)win_w;
    double px_hh = (double)hh * 0.5 * (double)win_h;

    int inside = (mx >= px_cx - px_hw && mx <= px_cx + px_hw &&
                  my >= px_cy - px_hh && my <= px_cy + px_hh);
    if (!inside) return 0;

    int left_down = glfwGetMouseButton(a->window, GLFW_MOUSE_BUTTON_LEFT) == GLFW_PRESS;
    return left_down ? 2 : 1;
}
