// XIOM — Dear ImGui Bindings (Immediate Mode GUI)
// Production-grade: ~60 functions wrapping Dear ImGui v1.92.9.
// Self-contained: links bridge/*.obj. No external imgui dependency.
module xiom.imgui

extern "C" {
  fn imgui_bridge_init(glfw_window: Int) -> Int32;
  fn imgui_bridge_shutdown();
  fn imgui_bridge_init_vulkan(instance: Int, device: Int, physical_device: Int,
      graphics_queue: Int, queue_family: Int32, render_pass: Int,
      subpass_count: Int32, fb_width: Float32, fb_height: Float32) -> Int32;
  fn imgui_bridge_new_frame();
  fn imgui_bridge_render(command_buffer: Int);

  fn imgui_begin(name: Str, flags: Int32) -> Int32;
  fn imgui_end();
  fn imgui_begin_child(id: Str, w: Float32, h: Float32, border: Int32) -> Int32;
  fn imgui_end_child();
  fn imgui_set_next_window_size(w: Float32, h: Float32);
  fn imgui_set_next_window_pos(x: Float32, y: Float32);

  fn imgui_button(label: Str) -> Int32;
  fn imgui_small_button(label: Str) -> Int32;
  fn imgui_text(text: Str);
  fn imgui_text_colored(r: Float32, g: Float32, b: Float32, a: Float32, text: Str);
  fn imgui_bullet_text(text: Str);
  fn imgui_slider_float(label: Str, v: Float32, mn: Float32, mx: Float32) -> Float32;
  fn imgui_slider_int(label: Str, v: Int32, mn: Int32, mx: Int32) -> Int32;
  fn imgui_checkbox(label: Str, checked: Int32) -> Int32;
  fn imgui_drag_float(label: Str, v: Float32, spd: Float32, mn: Float32, mx: Float32) -> Float32;
  fn imgui_drag_int(label: Str, v: Int32, spd: Float32, mn: Int32, mx: Int32) -> Int32;
  fn imgui_input_float(label: Str, v: Float32) -> Float32;
  fn imgui_input_int(label: Str, v: Int32) -> Int32;
  fn imgui_input_text(label: Str, buf: Int, buf_size: Int32) -> Int32;
  fn imgui_color_edit3(label: Str, r: Float32, g: Float32, b: Float32) -> Int32;
  fn imgui_color_edit4(label: Str, r: Float32, g: Float32, b: Float32, a: Float32) -> Int32;
  fn imgui_combo(label: Str, cur: Int32, items: Int, n: Int32) -> Int32;
  fn imgui_list_box(label: Str, cur: Int32, items: Int, n: Int32) -> Int32;

  fn imgui_separator();
  fn imgui_same_line(offset: Float32, spacing: Float32);
  fn imgui_spacing();
  fn imgui_dummy(w: Float32, h: Float32);
  fn imgui_new_line();

  fn imgui_tree_node(label: Str) -> Int32;
  fn imgui_tree_node_flags(label: Str, flags: Int32) -> Int32;
  fn imgui_tree_pop();
  fn imgui_collapsing_header(label: Str) -> Int32;

  fn imgui_begin_tab_bar(id: Str) -> Int32;
  fn imgui_end_tab_bar();
  fn imgui_begin_tab_item(label: Str) -> Int32;
  fn imgui_end_tab_item();

  fn imgui_plot_lines(label: Str, v: Int, n: Int32, smin: Float32, smax: Float32, w: Float32, h: Float32);
  fn imgui_plot_histogram(label: Str, v: Int, n: Int32, smin: Float32, smax: Float32, w: Float32, h: Float32);

  fn imgui_open_popup(id: Str);
  fn imgui_begin_popup(id: Str) -> Int32;
  fn imgui_end_popup();
  fn imgui_begin_popup_context_item(id: Str) -> Int32;
  fn imgui_begin_popup_modal(name: Str) -> Int32;
  fn imgui_end_popup_modal();

  fn imgui_begin_menu_bar() -> Int32;
  fn imgui_end_menu_bar();
  fn imgui_begin_menu(label: Str) -> Int32;
  fn imgui_end_menu();
  fn imgui_menu_item(label: Str, shortcut: Str, enabled: Int32) -> Int32;

  fn imgui_set_tooltip(text: Str);
  fn imgui_begin_tooltip();
  fn imgui_end_tooltip();

  fn imgui_set_scroll_here_y();
  fn imgui_is_item_hovered() -> Int32;
  fn imgui_is_item_clicked() -> Int32;

  fn imgui_style_dark();
  fn imgui_style_light();
  fn imgui_style_classic();
  fn imgui_push_style_color(idx: Int32, r: Float32, g: Float32, b: Float32, a: Float32);
  fn imgui_pop_style_color(count: Int32);

  fn imgui_get_framerate() -> Int32;
  fn imgui_get_frame_count() -> Int32;
}
