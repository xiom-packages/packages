#ifndef IMGUI_BRIDGE_H_
#define IMGUI_BRIDGE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Lifecycle */
int32_t  imgui_bridge_init(int64_t glfw_window);
void     imgui_bridge_shutdown(void);
int32_t  imgui_bridge_init_vulkan(int64_t instance, int64_t device,
            int64_t physical_device, int64_t graphics_queue,
            int32_t queue_family, int64_t render_pass,
            int32_t subpass_count, float fb_width, float fb_height);
void     imgui_bridge_new_frame(void);
void     imgui_bridge_render(int64_t command_buffer);

/* Windows */
int32_t  imgui_begin(const char* name, int32_t flags);
void     imgui_end(void);
int32_t  imgui_begin_child(const char* id, float w, float h, int32_t border);
void     imgui_end_child(void);
void     imgui_set_next_window_size(float w, float h);
void     imgui_set_next_window_pos(float x, float y);

/* Widgets — return 1 on interaction/true */
int32_t  imgui_button(const char* label);
int32_t  imgui_small_button(const char* label);
void     imgui_text(const char* text);
void     imgui_text_colored(float r, float g, float b, float a, const char* text);
void     imgui_bullet_text(const char* text);
float    imgui_slider_float(const char* label, float val, float mn, float mx);
int32_t  imgui_slider_int(const char* label, int32_t val, int32_t mn, int32_t mx);
int32_t  imgui_checkbox(const char* label, int32_t checked);
float    imgui_drag_float(const char* label, float val, float speed, float mn, float mx);
int32_t  imgui_drag_int(const char* label, int32_t val, float speed, int32_t mn, int32_t mx);
float    imgui_input_float(const char* label, float val);
int32_t  imgui_input_int(const char* label, int32_t val);
int32_t  imgui_input_text(const char* label, char* buf, int32_t buf_size);
int32_t  imgui_color_edit3(const char* label, float r, float g, float b);
int32_t  imgui_color_edit4(const char* label, float r, float g, float b, float a);
int32_t  imgui_combo(const char* label, int32_t cur, const char* const* items, int32_t n);
int32_t  imgui_list_box(const char* label, int32_t cur, const char* const* items, int32_t n);

/* Layout */
void     imgui_separator(void);
void     imgui_same_line(float offset, float spacing);
void     imgui_spacing(void);
void     imgui_dummy(float w, float h);
void     imgui_new_line(void);

/* Trees / Collapsing */
int32_t  imgui_tree_node(const char* label);
int32_t  imgui_tree_node_flags(const char* label, int32_t flags);
void     imgui_tree_pop(void);
int32_t  imgui_collapsing_header(const char* label);

/* Tabs */
int32_t  imgui_begin_tab_bar(const char* id);
void     imgui_end_tab_bar(void);
int32_t  imgui_begin_tab_item(const char* label);
void     imgui_end_tab_item(void);

/* Plots */
void     imgui_plot_lines(const char* label, const float* v, int32_t n,
            float smin, float smax, float w, float h);
void     imgui_plot_histogram(const char* label, const float* v, int32_t n,
            float smin, float smax, float w, float h);

/* Popups / Modals */
void     imgui_open_popup(const char* id);
int32_t  imgui_begin_popup(const char* id);
void     imgui_end_popup(void);
void     imgui_close_current_popup(void);
int32_t  imgui_begin_popup_context_item(const char* id);
int32_t  imgui_begin_popup_modal(const char* name);
void     imgui_end_popup_modal(void);

/* Menus */
int32_t  imgui_begin_menu_bar(void);
void     imgui_end_menu_bar(void);
int32_t  imgui_begin_menu(const char* label);
void     imgui_end_menu(void);
int32_t  imgui_menu_item(const char* label, const char* shortcut, int32_t enabled);

/* Tooltips */
void     imgui_set_tooltip(const char* text);
void     imgui_begin_tooltip(void);
void     imgui_end_tooltip(void);

/* Focus / Scrolling */
void     imgui_set_scroll_here_y(void);
int32_t  imgui_is_item_hovered(void);
int32_t  imgui_is_item_clicked(void);

/* Styling */
void     imgui_style_dark(void);
void     imgui_style_light(void);
void     imgui_style_classic(void);
void     imgui_push_style_color(int32_t idx, float r, float g, float b, float a);
void     imgui_pop_style_color(int32_t count);

/* Utility */
int32_t  imgui_get_framerate(void);
int32_t  imgui_get_frame_count(void);

#ifdef __cplusplus
}
#endif

#endif
