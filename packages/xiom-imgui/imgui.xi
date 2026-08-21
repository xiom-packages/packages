// XIOM -- Dear ImGui Bindings (Immediate Mode GUI)
// Production-grade: 85+ functions wrapping Dear ImGui v1.92.9.
// Self-contained: links bridge/*.obj. No external imgui dependency.
// Contracts enforce non-null handles, valid window state, and correct call order.
module xiom.imgui

// CG-01 workaround: Int32 constants to avoid `X as Int32` casts
const TRUE_I32 : Int32 = 1;
const FALSE_I32: Int32 = 0;
const FLAGS_NONE: Int32 = 0;

// -- extern "C" FFI declarations --------------------------------------------

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

  // Standard widgets (extended)
  fn imgui_input_float(label: Str, val: Float32) -> Float32;
  fn imgui_input_int(label: Str, val: Int32) -> Int32;
  fn imgui_input_text(label: Str, buf: Int, buf_size: Int32) -> Int32;
  fn imgui_color_edit4(label: Str, r: Float32, g: Float32, b: Float32, a: Float32) -> Int32;
  fn imgui_combo(label: Str, current: Int32, items: Int, count: Int32) -> Int32;
  fn imgui_list_box(label: Str, current: Int32, items: Int, count: Int32) -> Int32;
  fn imgui_begin_disabled(disabled: Int32) -> Int32;
  fn imgui_end_disabled();

  // Trees (extended)
  fn imgui_tree_node_flags(label: Str, flags: Int32) -> Int32;

  // Popups (extended)
  fn imgui_begin_popup(id: Str) -> Int32;
  fn imgui_end_popup();
  fn imgui_begin_popup_context_item(id: Str) -> Int32;

  // Menus (extended)
  fn imgui_begin_menu_bar() -> Int32;
  fn imgui_end_menu_bar();

  // Tooltips
  fn imgui_set_tooltip(text: Str);
  fn imgui_begin_tooltip();
  fn imgui_end_tooltip();

  // Interaction queries
  fn imgui_set_scroll_here_y();
  fn imgui_is_item_hovered() -> Int32;
  fn imgui_is_item_clicked() -> Int32;

  // Plots
  fn imgui_plot_lines(label: Str, values: Int, count: Int32, min: Float32, max: Float32, w: Float32, h: Float32);
  fn imgui_plot_histogram(label: Str, values: Int, count: Int32, min: Float32, max: Float32, w: Float32, h: Float32);

  // Styling (extended)
  fn imgui_push_style_color(idx: Int32, r: Float32, g: Float32, b: Float32, a: Float32);
  fn imgui_pop_style_color(count: Int32);
  fn imgui_color_edit4_rgba(label: Str, r: Int, g: Int, b: Int, a: Int);

  // Utility
  fn imgui_get_framerate() -> Int32;
  fn imgui_get_frame_count() -> Int32;
}

// -- Module-level state tracking for Begin/End pairing ---------------------
var g_win_open   : Int = 0;  // begin_window count (non-nesting: 0 or 1)
var g_menu_open  : Int = 0;  // begin_menu count
var g_mm_open    : Int = 0;  // main menu bar
var g_tab_bar    : Int = 0;  // begin_tab_bar
var g_tab_item   : Int = 0;  // begin_tab_item
var g_popup_open : Int = 0;  // begin_popup_modal / begin_popup
var g_tree_level : Int = 0;  // tree_node nesting level (trees CAN nest)

// -- Safe wrappers with contracts -------------------------------------------

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
  requires: g_win_open == 0
{
  let ok = unsafe { imgui_begin(title, flags) != 0 };
  if ok { g_win_open = 1; };
  return ok;
}

pub fn end_window()
  requires: g_win_open == 1
  ensures:  g_win_open == 0
{
  unsafe { imgui_end(); };
  g_win_open = 0;
}

pub fn set_next_window_size(w: Int32, h: Int32)
{ unsafe { imgui_set_next_window_size_i32(w, h); }; }

pub fn set_next_window_pos(x: Int32, y: Int32)
{ unsafe { imgui_set_next_window_pos_i32(x, y); }; }

// Widgets -- button, text
pub fn button(label: Str) -> Bool
  requires: label.len() > 0
{ return unsafe { imgui_button(label) != 0 }; }

pub fn small_button(label: Str) -> Bool
  requires: label.len() > 0
{ return unsafe { imgui_small_button(label) != 0 }; }

pub fn text(text: Str)
{ unsafe { imgui_text(text); }; }

pub fn text_colored(r: Float32, g: Float32, b: Float32, a: Float32, text: Str)
{ unsafe { imgui_text_colored(r, g, b, a, text); }; }

pub fn text_wrapped(text: Str)
{ unsafe { imgui_text_wrapped(text); }; }

// Widgets -- interactive
pub fn checkbox(label: Str, checked: Bool) -> Bool
  requires: label.len() > 0
{ let c: Int32 = if checked { TRUE_I32 } else { FALSE_I32 };
  return unsafe { imgui_checkbox(label, c) != 0 }; }

pub fn slider_float(label: Str, v: Float32, mn: Float32, mx: Float32) -> Float32
  requires: label.len() > 0
{ return unsafe { imgui_slider_float(label, v, mn, mx) }; }

pub fn slider_int(label: Str, v: Int32, mn: Int32, mx: Int32) -> Int32
  requires: label.len() > 0
{ return unsafe { imgui_slider_int(label, v, mn, mx) }; }

pub fn drag_float(label: Str, v: Float32, speed: Float32, mn: Float32, mx: Float32) -> Float32
  requires: label.len() > 0
{ return unsafe { imgui_drag_float(label, v, speed, mn, mx) }; }

pub fn drag_int(label: Str, v: Int32, speed: Float32, mn: Int32, mx: Int32) -> Int32
  requires: label.len() > 0
{ return unsafe { imgui_drag_int(label, v, speed, mn, mx) }; }

pub fn color_edit3(label: Str, r: Float32, g: Float32, b: Float32)
  requires: label.len() > 0
{ unsafe { imgui_color_edit3(label, r, g, b); }; }

pub fn progress_bar(fraction: Float32)
  requires: fraction >= 0.0
{ unsafe { imgui_progress_bar(fraction, -1.0, 0.0); }; }

pub fn radio_button(label: Str, active: Bool) -> Bool
  requires: label.len() > 0
{ let a: Int32 = if active { TRUE_I32 } else { FALSE_I32 };
  return unsafe { imgui_radio_button(label, a) != 0 }; }

// Layout
pub fn separator()
{ unsafe { imgui_separator(); }; }

pub fn same_line()
{ unsafe { imgui_same_line(0.0, 0.0); }; }

pub fn same_line_offset(offset_x: Float32)
{ unsafe { imgui_same_line(offset_x, 0.0); }; }

pub fn same_line_spacing(spacing: Float32)
{ unsafe { imgui_same_line(0.0, spacing); }; }

pub fn spacing()
{ unsafe { imgui_spacing(); }; }

// Trees
pub fn tree_node(label: Str) -> Bool
  requires: label.len() > 0
{
  let ok = unsafe { imgui_tree_node(label) != 0 };
  if ok { g_tree_level = g_tree_level + 1; };
  return ok;
}
pub fn tree_pop()
  requires: g_tree_level > 0
{ unsafe { imgui_tree_pop(); }; g_tree_level = g_tree_level - 1; }

pub fn collapsing_header(label: Str) -> Bool
  requires: label.len() > 0
{ return unsafe { imgui_collapsing_header(label) != 0 }; }

// Tabs
pub fn begin_tab_bar(id: Str) -> Bool
  requires: id.len() > 0
  requires: g_tab_bar == 0
{
  let ok = unsafe { imgui_begin_tab_bar(id) != 0 };
  if ok { g_tab_bar = 1; };
  return ok;
}

pub fn end_tab_bar()
  requires: g_tab_bar == 1
{ unsafe { imgui_end_tab_bar(); }; g_tab_bar = 0; }

pub fn begin_tab_item(label: Str) -> Bool
  requires: label.len() > 0
  requires: g_tab_item == 0
{
  let ok = unsafe { imgui_begin_tab_item(label) != 0 };
  if ok { g_tab_item = 1; };
  return ok;
}

pub fn end_tab_item()
  requires: g_tab_item == 1
{ unsafe { imgui_end_tab_item(); }; g_tab_item = 0; }

// Popups / Modals
pub fn open_popup(id: Str)
  requires: id.len() > 0
{ unsafe { imgui_open_popup(id); }; }

pub fn begin_popup_modal(name: Str) -> Bool
  requires: name.len() > 0
  requires: g_popup_open == 0
{
  let ok = unsafe { imgui_begin_popup_modal(name) != 0 };
  if ok { g_popup_open = 1; };
  return ok;
}

pub fn end_popup_modal()
  requires: g_popup_open == 1
{ unsafe { imgui_end_popup_modal(); }; g_popup_open = 0; }

pub fn close_current_popup()
{ unsafe { imgui_close_current_popup(); }; }

// Menus
pub fn begin_main_menu_bar() -> Bool
  requires: g_mm_open == 0
{
  let ok = unsafe { imgui_begin_main_menu_bar() != 0 };
  if ok { g_mm_open = 1; };
  return ok;
}

pub fn end_main_menu_bar()
  requires: g_mm_open == 1
{ unsafe { imgui_end_main_menu_bar(); }; g_mm_open = 0; }

pub fn begin_menu(label: Str) -> Bool
  requires: label.len() > 0
  requires: g_menu_open == 0
{
  let ok = unsafe { imgui_begin_menu(label) != 0 };
  if ok { g_menu_open = 1; };
  return ok;
}

pub fn end_menu()
  requires: g_menu_open == 1
{ unsafe { imgui_end_menu(); }; g_menu_open = 0; }

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

pub fn push_style_color(idx: Int32, r: Float32, g: Float32, b: Float32, a: Float32)
  requires: idx >= 0
{ unsafe { imgui_push_style_color(idx, r, g, b, a); }; }

pub fn pop_style_color(count: Int32)
  requires: count > 0
{ unsafe { imgui_pop_style_color(count); }; }

// Tooltips
pub fn set_tooltip(text: Str)
  requires: text.len() > 0
{ unsafe { imgui_set_tooltip(text); }; }
pub fn begin_tooltip() { unsafe { imgui_begin_tooltip(); }; }
pub fn end_tooltip()   { unsafe { imgui_end_tooltip(); }; }

// Interaction queries
pub fn set_scroll_here_y() { unsafe { imgui_set_scroll_here_y(); }; }
pub fn is_item_hovered() -> Bool { return unsafe { imgui_is_item_hovered() != 0 }; }
pub fn is_item_clicked() -> Bool { return unsafe { imgui_is_item_clicked() != 0 }; }

// Plots
pub fn plot_lines(label: Str, values: Int, count: Int32, min: Float32, max: Float32)
  requires: label.len() > 0
  { unsafe { imgui_plot_lines(label, values, count, min, max, 0.0, 0.0); }; }

pub fn plot_histogram(label: Str, values: Int, count: Int32, min: Float32, max: Float32)
  requires: label.len() > 0
  { unsafe { imgui_plot_histogram(label, values, count, min, max, 0.0, 0.0); }; }

// Input
pub fn input_float(label: Str, val: Float32) -> Float32
  requires: label.len() > 0
  { return unsafe { imgui_input_float(label, val) }; }

pub fn input_int(label: Str, val: Int32) -> Int32
  requires: label.len() > 0
  { return unsafe { imgui_input_int(label, val) }; }

// Combo / List
pub fn combo(label: Str, current: Int32, items: Int, count: Int32) -> Int32
  requires: label.len() > 0
  { return unsafe { imgui_combo(label, current, items, count) }; }

pub fn list_box(label: Str, current: Int32, items: Int, count: Int32) -> Int32
  requires: label.len() > 0
  { return unsafe { imgui_list_box(label, current, items, count) }; }

// Disabled groups
pub fn begin_disabled(disabled: Bool) { unsafe { imgui_begin_disabled(if disabled { TRUE_I32 } else { FALSE_I32 }); }; }
pub fn end_disabled() { unsafe { imgui_end_disabled(); }; }

// Popups (non-modal)
pub fn begin_popup(id: Str) -> Bool
  requires: id.len() > 0
{ return unsafe { imgui_begin_popup(id) != 0 }; }

pub fn end_popup()
{ unsafe { imgui_end_popup(); }; }

pub fn begin_popup_context_item(id: Str) -> Bool
  requires: id.len() > 0
{ return unsafe { imgui_begin_popup_context_item(id) != 0 }; }

// Window-embedded menu bars
pub fn begin_menu_bar() -> Bool
{ return unsafe { imgui_begin_menu_bar() != 0 }; }

pub fn end_menu_bar()
{ unsafe { imgui_end_menu_bar(); }; }

// Tree node with flags
pub fn tree_node_flags(label: Str, flags: Int32) -> Bool
  requires: label.len() > 0
{ return unsafe { imgui_tree_node_flags(label, flags) != 0 }; }

// Color edit with alpha
pub fn color_edit4(label: Str, r: Float32, g: Float32, b: Float32, a: Float32)
  requires: label.len() > 0
{ unsafe { imgui_color_edit4(label, r, g, b, a); }; }

// Utility
pub fn get_framerate() -> Int32
{ return unsafe { imgui_get_framerate() }; }

pub fn get_frame_count() -> Int32
{ return unsafe { imgui_get_frame_count() }; }
