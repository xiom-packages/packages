// XIOM — Dear ImGui Bindings (Immediate Mode GUI)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Self-contained: ships pre-compiled imgui_bridge.obj files.
// No external dependencies beyond Vulkan SDK + GLFW.
module xiom.imgui

// ── Lifecycle ──
extern "C" {
  fn imgui_bridge_init(glfw_window: Int) -> Int32;
  fn imgui_bridge_shutdown();
  fn imgui_bridge_init_vulkan(instance: Int, device: Int, physical_device: Int,
      graphics_queue: Int, queue_family: Int32, render_pass: Int,
      subpass_count: Int32, fb_width: Float32, fb_height: Float32) -> Int32;
  fn imgui_bridge_new_frame();
  fn imgui_bridge_render(command_buffer: Int);

  fn imgui_begin(name: Str) -> Int32;
  fn imgui_end();
  fn imgui_button(label: Str) -> Int32;
  fn imgui_text(text: Str);
  fn imgui_slider_float(label: Str, value: Float32, min_val: Float32, max_val: Float32) -> Float32;
  fn imgui_checkbox(label: Str, checked: Int32) -> Int32;
  fn imgui_separator();
  fn imgui_same_line();
  fn imgui_spacing();
  fn imgui_tree_node(label: Str) -> Int32;
  fn imgui_tree_pop();
  fn imgui_collapsing_header(label: Str) -> Int32;
  fn imgui_style_dark();
  fn imgui_style_light();
  fn imgui_style_classic();
}

pub fn create_context(glfw_window: Int) -> Bool {
  return unsafe { imgui_bridge_init(glfw_window) != 0 };
}
pub fn destroy_context() { unsafe { imgui_bridge_shutdown(); }; }

pub fn init_vulkan(instance: Int, device: Int, phys: Int, queue: Int,
    family: Int, rp: Int, subpass: Int, w: Float32, h: Float32) -> Bool {
  return unsafe { imgui_bridge_init_vulkan(instance, device, phys, queue,
      family as Int32, rp, subpass as Int32, w, h) != 0 };
}
pub fn new_frame() { unsafe { imgui_bridge_new_frame(); }; }
pub fn render(cb: Int) { unsafe { imgui_bridge_render(cb); }; }

pub fn begin_window(title: Str) -> Bool {
  return unsafe { imgui_begin(title) != 0 };
}
pub fn end_window() { unsafe { imgui_end(); }; }
pub fn button(label: Str) -> Bool {
  return unsafe { imgui_button(label) != 0 };
}
pub fn text(text: Str) { unsafe { imgui_text(text); }; }
pub fn slider_float(label: Str, value: Float32, min_val: Float32, max_val: Float32) -> Float32 {
  return unsafe { imgui_slider_float(label, value, min_val, max_val) };
}
pub fn checkbox(label: Str, checked: Bool) -> Bool {
  return unsafe { imgui_checkbox(label, if checked { 1 } else { 0 } as Int32) != 0 };
}
pub fn separator() { unsafe { imgui_separator(); }; }
pub fn same_line() { unsafe { imgui_same_line(); }; }
pub fn spacing() { unsafe { imgui_spacing(); }; }
pub fn tree_node(label: Str) -> Bool {
  return unsafe { imgui_tree_node(label) != 0 };
}
pub fn tree_pop() { unsafe { imgui_tree_pop(); }; }
pub fn collapsing_header(label: Str) -> Bool {
  return unsafe { imgui_collapsing_header(label) != 0 };
}
pub fn style_dark() { unsafe { imgui_style_dark(); }; }
pub fn style_light() { unsafe { imgui_style_light(); }; }
pub fn style_classic() { unsafe { imgui_style_classic(); }; }
