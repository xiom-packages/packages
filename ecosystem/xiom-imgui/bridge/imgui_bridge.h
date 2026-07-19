#ifndef IMGUI_BRIDGE_H_
#define IMGUI_BRIDGE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t  imgui_bridge_init(int64_t glfw_window);
void     imgui_bridge_shutdown(void);
int32_t  imgui_bridge_init_vulkan(int64_t instance, int64_t device,
            int64_t physical_device, int64_t graphics_queue,
            int32_t queue_family, int64_t render_pass,
            int32_t subpass_count, float fb_width, float fb_height);
void     imgui_bridge_new_frame(void);
void     imgui_bridge_render(int64_t command_buffer);

int32_t  imgui_begin(const char* name);
void     imgui_end(void);
int32_t  imgui_button(const char* label);
void     imgui_text(const char* text);
float    imgui_slider_float(const char* label, float value, float min_val, float max_val);
int32_t  imgui_checkbox(const char* label, int32_t checked);
void     imgui_separator(void);
void     imgui_same_line(void);
void     imgui_spacing(void);
int32_t  imgui_tree_node(const char* label);
void     imgui_tree_pop(void);
int32_t  imgui_collapsing_header(const char* label);
void     imgui_plot_lines(const char* label, const float* values, int32_t count,
            float scale_min, float scale_max, float width, float height);
int32_t  imgui_input_text(const char* label, char* buf, int32_t buf_size);
int32_t  imgui_combo(const char* label, int32_t current_item,
            const char* const* items, int32_t item_count);
void     imgui_style_dark(void);
void     imgui_style_light(void);
void     imgui_style_classic(void);

#ifdef __cplusplus
}
#endif

#endif
