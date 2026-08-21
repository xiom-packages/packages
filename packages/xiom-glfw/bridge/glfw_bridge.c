#define _CRT_SECURE_NO_WARNINGS
#include "glfw_bridge.h"
#include <GLFW/glfw3.h>
#include <stdio.h>
#include <string.h>

static char g_error[256] = "";

/* -- Lifecycle -- */
int32_t glfw_bridge_init(void) {
    if (!glfwInit()) {
        const char* desc;
        glfwGetError(&desc);
        snprintf(g_error, sizeof(g_error), "glfwInit failed: %s", desc ? desc : "unknown");
        return 0;
    }
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    return 1;
}

void glfw_bridge_terminate(void) { glfwTerminate(); }

/* -- Window -- */
int64_t glfw_bridge_create_window(int32_t w, int32_t h, const char* title) {
    GLFWwindow* win = glfwCreateWindow(w, h, title ? title : "XIOM", NULL, NULL);
    if (!win) {
        const char* desc;
        glfwGetError(&desc);
        snprintf(g_error, sizeof(g_error), "glfwCreateWindow: %s", desc ? desc : "unknown");
        return 0;
    }
    return (int64_t)(uint64_t)win;
}

void glfw_bridge_destroy_window(int64_t window) {
    GLFWwindow* win = (GLFWwindow*)(uint64_t)window;
    if (win) glfwDestroyWindow(win);
}

int32_t glfw_bridge_should_close(int64_t window) {
    GLFWwindow* win = (GLFWwindow*)(uint64_t)window;
    return win ? (int32_t)glfwWindowShouldClose(win) : 1;
}

void glfw_bridge_set_window_title(int64_t window, const char* title) {
    GLFWwindow* win = (GLFWwindow*)(uint64_t)window;
    if (win && title) glfwSetWindowTitle(win, title);
}

/* -- Framebuffer / size -- */
void glfw_bridge_get_framebuffer_size(int64_t window, int32_t* w, int32_t* h) {
    GLFWwindow* win = (GLFWwindow*)(uint64_t)window;
    if (win && w && h) glfwGetFramebufferSize(win, w, h);
}

void glfw_bridge_get_window_size(int64_t window, int32_t* w, int32_t* h) {
    GLFWwindow* win = (GLFWwindow*)(uint64_t)window;
    if (win && w && h) glfwGetWindowSize(win, w, h);
}

/* -- Input -- */
void glfw_bridge_poll_events(void) { glfwPollEvents(); }

int32_t glfw_bridge_get_key(int64_t window, int32_t key) {
    GLFWwindow* win = (GLFWwindow*)(uint64_t)window;
    return win ? (int32_t)glfwGetKey(win, key) : 0;
}

int32_t glfw_bridge_get_mouse_button(int64_t window, int32_t button) {
    GLFWwindow* win = (GLFWwindow*)(uint64_t)window;
    return win ? (int32_t)glfwGetMouseButton(win, button) : 0;
}

void glfw_bridge_get_cursor_pos(int64_t window, float* x, float* y) {
    GLFWwindow* win = (GLFWwindow*)(uint64_t)window;
    double dx = 0, dy = 0;
    if (win) glfwGetCursorPos(win, &dx, &dy);
    if (x) *x = (float)dx;
    if (y) *y = (float)dy;
}

/* -- Monitors -- */
int64_t glfw_bridge_get_primary_monitor(void) {
    return (int64_t)(uint64_t)glfwGetPrimaryMonitor();
}

void glfw_bridge_get_monitor_name(int64_t monitor, char* buf, int32_t buf_size) {
    GLFWmonitor* mon = (GLFWmonitor*)(uint64_t)monitor;
    const char* name = mon ? glfwGetMonitorName(mon) : "unknown";
    if (buf && buf_size > 0) {
        strncpy(buf, name, (size_t)buf_size - 1);
        buf[buf_size - 1] = 0;
    }
}

void glfw_bridge_get_video_mode(int64_t monitor, int32_t* w, int32_t* h, int32_t* refresh) {
    GLFWmonitor* mon = (GLFWmonitor*)(uint64_t)monitor;
    const GLFWvidmode* mode = mon ? glfwGetVideoMode(mon) : NULL;
    if (w) *w = mode ? mode->width : 0;
    if (h) *h = mode ? mode->height : 0;
    if (refresh) *refresh = mode ? mode->refreshRate : 0;
}

/* -- Fullscreen -- */
void glfw_bridge_set_window_monitor(int64_t window, int64_t monitor,
    int32_t x, int32_t y, int32_t w, int32_t h, int32_t refresh)
{
    GLFWwindow* win = (GLFWwindow*)(uint64_t)window;
    GLFWmonitor* mon = (GLFWmonitor*)(uint64_t)monitor;
    if (win) glfwSetWindowMonitor(win, mon, x, y, w, h, refresh);
}

int64_t glfw_bridge_get_window_monitor(int64_t window) {
    GLFWwindow* win = (GLFWwindow*)(uint64_t)window;
    return (int64_t)(uint64_t)glfwGetWindowMonitor(win);
}

/* -- Error -- */
const char* glfw_bridge_get_error(void) { return g_error; }
