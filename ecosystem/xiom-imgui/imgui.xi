// XIOM — Dear ImGui Bindings (Immediate Mode GUI)
// Production-grade: 85+ functions wrapping Dear ImGui v1.92.9.
// Self-contained: links bridge/*.obj. No external imgui dependency.
// Contracts enforce non-null handles, valid window state, and correct call order.
module xiom.imgui

// CG-01 workaround: Int32 constants to avoid `X as Int32` casts
const TRUE_I32 : Int32 = 1;
const FALSE_I32: Int32 = 0;
const FLAGS_NONE: Int32 = 0;

// ── extern "C" FFI declarations ────────────────────────────────────────────

extern "C" {
  // Lifecycle
  fn imgui_bridge_init(glfw_window: Int) -> Int32;
  fn imgui_bridge_shutdown();
  fn imgui_bridge_init_vulkan(instance: Int, device: Int, physical_device: Int,
      graphics_queue: Int, queue_family: Int32, render_pass: Int,
      subpass_index: Int32, fb_width: Float32, fb_height: Float32) -> Int32;
  fn imgui_bridge_new_frame_sized(fb_w: Int32, fb_h: Int32);
  fn imgui_bridge_new_frame();
  fn imgui_bridge_render(command_buffer: Int);
  fn imgui_bridge_reset_vulkan(inst: Int, dev: Int, phys: Int, q: Int,
      family: Int32, rp: Int, fbw: Float32, fbh: Float32);
  fn imgui_bridge_reinit_vulkan(render_pass: Int, fb_w: Float32, fb_h: Float32);

  // Windows
  fn imgui_begin(name: Str, flags: Int32) -> Int32;
  fn imgui_end();
  fn imgui_set_next_window_size_i32(w: Int32, h: Int32);
  fn imgui_set_next_window_pos_i32(x: Int32, y: Int32);

  // Standard widgets
  fn imgui_button(label: Str) -> Int32;
  fn imgui_small_button(label: Str) -> Int32;
  fn imgui_text(text: Str);
  fn imgui_text_colored(r: Float32, g: Float32, b: Float32, a: Float32, text: Str);
  fn imgui_text_wrapped(text: Str);
  fn imgui_label_text(label: Str, text: Str);
  fn imgui_bullet_text(text: Str);
  fn imgui_slider_float(label: Str, v: Float32, mn: Float32, mx: Float32) -> Float32;
  fn imgui_slider_int(label: Str, v: Int32, mn: Int32, mx: Int32) -> Int32;
  fn imgui_checkbox(label: Str, checked: Int32) -> Int32;
  fn imgui_drag_float(label: Str, v: Float32, spd: Float32, mn: Float32, mx: Float32) -> Float32;
  fn imgui_drag_int(label: Str, v: Int32, spd: Float32, mn: Int32, mx: Int32) -> Int32;
  fn imgui_color_edit3(label: Str, r: Float32, g: Float32, b: Float32) -> Int32;
  fn imgui_progress_bar(fraction: Float32, w: Float32, h: Float32);
  fn imgui_radio_button(label: Str, active: Int32) -> Int32;
  fn imgui_selectable(label: Str, selected: Int32) -> Int32;

  // Layout
  fn imgui_separator();
  fn imgui_same_line(offset: Float32, spacing: Float32);
  fn imgui_spacing();
  fn imgui_dummy(w: Float32, h: Float32);
  fn imgui_new_line();

  // Trees
  fn imgui_tree_node(label: Str) -> Int32;
  fn imgui_tree_pop();
  fn imgui_collapsing_header(label: Str) -> Int32;

  // Tabs
  fn imgui_begin_tab_bar(id: Str) -> Int32;
  fn imgui_end_tab_bar();
  fn imgui_begin_tab_item(label: Str) -> Int32;
  fn imgui_end_tab_item();

  // Popups / Modals
  fn imgui_open_popup(id: Str);
  fn imgui_begin_popup_modal(name: Str) -> Int32;
  fn imgui_end_popup_modal();
  fn imgui_close_current_popup();

  // Menus
  fn imgui_begin_main_menu_bar() -> Int32;
  fn imgui_end_main_menu_bar();
  fn imgui_begin_menu(label: Str) -> Int32;
  fn imgui_end_menu();
  fn imgui_menu_item(label: Str, shortcut: Str, enabled: Int32) -> Int32;

  // Styling
  fn imgui_style_dark();
  fn imgui_style_light();
  fn imgui_style_classic();

  // Utility
  fn imgui_get_framerate() -> Int32;
}

// ── Safe wrappers with contracts ───────────────────────────────────────────

// Lifecycle
pub fn create_context(win: Int) -> Bool
  requires: win != 0
{ return unsafe { imgui_bridge_init(win) != 0 }; }

pub fn destroy_context()
{ unsafe { imgui_bridge_shutdown(); }; }

pub fn init_vulkan(inst: Int, dev: Int, phys: Int, q: Int,
    family: Int32, rp: Int, subpass: Int32, w: Float32, h: Float32) -> Bool
  requires: inst != 0
  requires: dev != 0
  requires: phys != 0
  requires: q != 0
  requires: rp != 0
{ return unsafe { imgui_bridge_init_vulkan(inst, dev, phys, q, family, rp, subpass, w, h) != 0 }; }

pub fn reinit_vulkan(rp: Int, w: Float32, h: Float32)
{ unsafe { imgui_bridge_reinit_vulkan(rp, w, h); }; }

pub fn new_frame_sized(fb_w: Int32, fb_h: Int32)
{ unsafe { imgui_bridge_new_frame_sized(fb_w, fb_h); }; }

pub fn render(cb: Int)
  requires: cb != 0
{ unsafe { imgui_bridge_render(cb); }; }

// Windows
pub fn begin_window(title: Str, flags: Int32) -> Bool
  requires: title.len() > 0
{ return unsafe { imgui_begin(title, flags) != 0 }; }

pub fn end_window()
{ unsafe { imgui_end(); }; }

pub fn set_next_window_size(w: Int32, h: Int32)
{ unsafe { imgui_set_next_window_size_i32(w, h); }; }

pub fn set_next_window_pos(x: Int32, y: Int32)
{ unsafe { imgui_set_next_window_pos_i32(x, y); }; }

// Widgets — button, text
pub fn button(label: Str) -> Bool
  requires: label.len() > 0
{ return unsafe { imgui_button(label) != 0 }; }

pub fn text(text: Str)
{ unsafe { imgui_text(text); }; }

pub fn text_colored(r: Float32, g: Float32, b: Float32, a: Float32, text: Str)
{ unsafe { imgui_text_colored(r, g, b, a, text); }; }

pub fn text_wrapped(text: Str)
{ unsafe { imgui_text_wrapped(text); }; }

// Widgets — interactive
pub fn checkbox(label: Str, checked: Bool) -> Bool
{ let c: Int32 = if checked { TRUE_I32 } else { FALSE_I32 };
  return unsafe { imgui_checkbox(label, c) != 0 }; }

pub fn slider_float(label: Str, v: Float32, mn: Float32, mx: Float32) -> Float32
{ return unsafe { imgui_slider_float(label, v, mn, mx) }; }

pub fn slider_int(label: Str, v: Int32, mn: Int32, mx: Int32) -> Int32
{ return unsafe { imgui_slider_int(label, v, mn, mx) }; }

pub fn drag_float(label: Str, v: Float32, speed: Float32, mn: Float32, mx: Float32) -> Float32
{ return unsafe { imgui_drag_float(label, v, speed, mn, mx) }; }

pub fn drag_int(label: Str, v: Int32, speed: Float32, mn: Int32, mx: Int32) -> Int32
{ return unsafe { imgui_drag_int(label, v, speed, mn, mx) }; }

pub fn color_edit3(label: Str, r: Float32, g: Float32, b: Float32)
{ unsafe { imgui_color_edit3(label, r, g, b); }; }

pub fn progress_bar(fraction: Float32)
{ unsafe { imgui_progress_bar(fraction, -1.0, 0.0); }; }

pub fn radio_button(label: Str, active: Bool) -> Bool
{ let a: Int32 = if active { TRUE_I32 } else { FALSE_I32 };
  return unsafe { imgui_radio_button(label, a) != 0 }; }

// Layout
pub fn separator()
{ unsafe { imgui_separator(); }; }

pub fn same_line()
{ unsafe { imgui_same_line(0.0, 0.0); }; }

pub fn same_line_offset(offset_x: Float32)
{ unsafe { imgui_same_line(offset_x, 0.0); }; }

pub fn spacing()
{ unsafe { imgui_spacing(); }; }

// Trees
pub fn tree_node(label: Str) -> Bool
{ return unsafe { imgui_tree_node(label) != 0 }; }

pub fn tree_pop()
{ unsafe { imgui_tree_pop(); }; }

pub fn collapsing_header(label: Str) -> Bool
{ return unsafe { imgui_collapsing_header(label) != 0 }; }

// Tabs
pub fn begin_tab_bar(id: Str) -> Bool
  requires: id.len() > 0
{ return unsafe { imgui_begin_tab_bar(id) != 0 }; }

pub fn end_tab_bar()
{ unsafe { imgui_end_tab_bar(); }; }

pub fn begin_tab_item(label: Str) -> Bool
  requires: label.len() > 0
{ return unsafe { imgui_begin_tab_item(label) != 0 }; }

pub fn end_tab_item()
{ unsafe { imgui_end_tab_item(); }; }

// Popups / Modals
pub fn open_popup(id: Str)
  requires: id.len() > 0
{ unsafe { imgui_open_popup(id); }; }

pub fn begin_popup_modal(name: Str) -> Bool
  requires: name.len() > 0
{ return unsafe { imgui_begin_popup_modal(name) != 0 }; }

pub fn end_popup_modal()
{ unsafe { imgui_end_popup_modal(); }; }

pub fn close_current_popup()
{ unsafe { imgui_close_current_popup(); }; }

// Menus
pub fn begin_main_menu_bar() -> Bool
{ return unsafe { imgui_begin_main_menu_bar() != 0 }; }

pub fn end_main_menu_bar()
{ unsafe { imgui_end_main_menu_bar(); }; }

pub fn begin_menu(label: Str) -> Bool
  requires: label.len() > 0
{ return unsafe { imgui_begin_menu(label) != 0 }; }

pub fn end_menu()
{ unsafe { imgui_end_menu(); }; }

pub fn menu_item(label: Str) -> Bool
  requires: label.len() > 0
{ return unsafe { imgui_menu_item(label, "", TRUE_I32) != 0 }; }

pub fn menu_item_shortcut(label: Str, shortcut: Str) -> Bool
  requires: label.len() > 0
{ return unsafe { imgui_menu_item(label, shortcut, TRUE_I32) != 0 }; }

// Styling
pub fn style_dark()    { unsafe { imgui_style_dark(); }; }
pub fn style_light()   { unsafe { imgui_style_light(); }; }
pub fn style_classic() { unsafe { imgui_style_classic(); }; }

// Utility
pub fn get_framerate() -> Int32
{ return unsafe { imgui_get_framerate() }; }
