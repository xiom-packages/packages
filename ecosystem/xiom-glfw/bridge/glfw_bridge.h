// xiom-glfw C Bridge — Production-grade GLFW ABI
// Flat C API for XIOM FFI. Zero dependencies beyond GLFW and OS libs.

#ifndef GLFW_BRIDGE_H
#define GLFW_BRIDGE_H
#include <stdint.h>

// Lifecycle
int32_t  glfw_bridge_init(void);
void     glfw_bridge_terminate(void);

// Window
int64_t  glfw_bridge_create_window(int32_t w, int32_t h, const char* title);
void     glfw_bridge_destroy_window(int64_t window);
int32_t  glfw_bridge_should_close(int64_t window);
void     glfw_bridge_set_window_title(int64_t window, const char* title);

// Framebuffer / size
void     glfw_bridge_get_framebuffer_size(int64_t window, int32_t* w, int32_t* h);
void     glfw_bridge_get_window_size(int64_t window, int32_t* w, int32_t* h);

// Input
void     glfw_bridge_poll_events(void);
int32_t  glfw_bridge_get_key(int64_t window, int32_t key);
int32_t  glfw_bridge_get_mouse_button(int64_t window, int32_t button);
void     glfw_bridge_get_cursor_pos(int64_t window, float* x, float* y);

// Monitors
int64_t  glfw_bridge_get_primary_monitor(void);
void     glfw_bridge_get_monitor_name(int64_t monitor, char* buf, int32_t buf_size);
void     glfw_bridge_get_video_mode(int64_t monitor, int32_t* w, int32_t* h, int32_t* refresh);

// Fullscreen
void     glfw_bridge_set_window_monitor(int64_t window, int64_t monitor,
            int32_t x, int32_t y, int32_t w, int32_t h, int32_t refresh);
int64_t  glfw_bridge_get_window_monitor(int64_t window);

// Error
const char* glfw_bridge_get_error(void);

#endif
