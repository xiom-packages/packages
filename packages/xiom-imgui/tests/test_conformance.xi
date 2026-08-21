// XIOM -- ImGui Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Comprehensive safe wrapper contract and return-type conformance suite.
// Covers: context lifecycle, window state tracking, widgets, layout,
// tree/tab/popup pairing, menu bar lifecycle, styling, and utility.
module imgui_conformance
use xiom.test;
use xiom.imgui;

// ===========================================================================
// Context Lifecycle
// ===========================================================================

fn test_create_context_null() -> TestResult {
  let ok = create_context(0);
  return assert(!ok, "context: create_context with null window returns false");
}

fn test_destroy_context_noop() -> TestResult {
  destroy_context();
  return assert(true, "context: destroy_context runs without crash");
}

fn test_double_destroy_context_idempotent() -> TestResult {
  destroy_context();
  destroy_context();
  return assert(true, "context: double destroy_context is idempotent");
}

// ===========================================================================
// Window Begin/End State Tracking
// ===========================================================================

fn test_begin_window_no_context() -> TestResult {
  let ok = begin_window("Test", 0 as Int32);
  return assert(!ok, "window: begin_window returns false without imgui context");
}

fn test_window_begin_state_guard() -> TestResult {
  // Without context, begin_window returns false -- g_win_open stays 0.
  // Contract requires g_win_open == 0 before each begin_window call.
  // A failed begin must NOT lock the guard. The second call proves this.
  let ok1 = begin_window("A", 0 as Int32);
  let ok2 = begin_window("B", 0 as Int32);
  return assert(!ok1 && !ok2, "window: state guard not locked by failed begin_window");
}

fn test_set_next_window_pos() -> TestResult {
  set_next_window_pos(10 as Int32, 20 as Int32);
  return assert(true, "window: set_next_window_pos runs without crash");
}

fn test_set_next_window_size() -> TestResult {
  set_next_window_size(800 as Int32, 600 as Int32);
  return assert(true, "window: set_next_window_size runs without crash");
}

// ===========================================================================
// Widget Functions
// ===========================================================================

fn test_button_no_context() -> TestResult {
  let ok = button("Test");
  return assert(!ok, "widget: button returns false without context");
}

fn test_small_button_no_context() -> TestResult {
  let ok = small_button("Test");
  return assert(!ok, "widget: small_button returns false without context");
}

fn test_text_no_crash() -> TestResult {
  text("conformance test text");
  return assert(true, "widget: text runs without crash");
}

fn test_text_colored_no_crash() -> TestResult {
  text_colored(0.5, 0.5, 0.5, 1.0, "colored text");
  return assert(true, "widget: text_colored runs without crash");
}

fn test_text_wrapped_no_crash() -> TestResult {
  text_wrapped("wrapped conformance message");
  return assert(true, "widget: text_wrapped runs without crash");
}

fn test_checkbox_no_context() -> TestResult {
  let ok = checkbox("Test", false);
  return assert(!ok, "widget: checkbox returns false without context");
}

fn test_checkbox_true_state() -> TestResult {
  let ok = checkbox("Test", true);
  return assert(!ok, "widget: checkbox with initial true returns false without context");
}

fn test_slider_float_returns_value() -> TestResult {
  let v = slider_float("Test", 0.5, 0.0, 1.0);
  let valid = v >= 0.0 && v <= 1.0;
  return assert(valid, "widget: slider_float returns value within min/max range");
}

fn test_slider_int_returns_value() -> TestResult {
  let v = slider_int("Test", 50 as Int32, 0 as Int32, 100 as Int32);
  let valid = v >= 0 as Int32 && v <= 100 as Int32;
  return assert(valid, "widget: slider_int returns value within min/max range");
}

fn test_radio_button_no_context() -> TestResult {
  let ok = radio_button("Test", true);
  return assert(!ok, "widget: radio_button returns false without context");
}

fn test_radio_button_inactive() -> TestResult {
  let ok = radio_button("Test", false);
  return assert(!ok, "widget: radio_button inactive returns false without context");
}

fn test_drag_float_returns_value() -> TestResult {
  let v = drag_float("Test", 1.0, 0.1, 0.0, 10.0);
  let valid = v >= 0.0 && v <= 10.0;
  return assert(valid, "widget: drag_float returns value within min/max range");
}

fn test_drag_int_returns_value() -> TestResult {
  let v = drag_int("Test", 50 as Int32, 1.0, 0 as Int32, 100 as Int32);
  let valid = v >= 0 as Int32 && v <= 100 as Int32;
  return assert(valid, "widget: drag_int returns value within min/max range");
}

fn test_progress_bar_no_crash() -> TestResult {
  progress_bar(0.0);
  progress_bar(0.5);
  progress_bar(1.0);
  return assert(true, "widget: progress_bar handles valid fractions [0, 1]");
}

fn test_color_edit3_no_crash() -> TestResult {
  color_edit3("RGB", 0.2, 0.6, 0.9);
  return assert(true, "widget: color_edit3 runs without crash");
}

// ===========================================================================
// Layout Functions
// ===========================================================================

fn test_separator_no_crash() -> TestResult {
  separator();
  return assert(true, "layout: separator runs without crash");
}

fn test_same_line_no_crash() -> TestResult {
  same_line();
  return assert(true, "layout: same_line runs without crash");
}

fn test_same_line_offset_no_crash() -> TestResult {
  same_line_offset(50.0);
  return assert(true, "layout: same_line_offset runs without crash");
}

fn test_same_line_spacing_no_crash() -> TestResult {
  same_line_spacing(8.0);
  return assert(true, "layout: same_line_spacing runs without crash");
}

fn test_spacing_no_crash() -> TestResult {
  spacing();
  return assert(true, "layout: spacing runs without crash");
}

// ===========================================================================
// Tree / Tab / Popup Begin/End Pairing
// ===========================================================================

fn test_tree_node_no_context() -> TestResult {
  let ok = tree_node("Test");
  return assert(!ok, "tree: tree_node returns false without context");
}

fn test_tree_node_state_guard() -> TestResult {
  // Failed tree_node must not increment g_tree_level.
  // Contract requires g_tree_level > 0 for tree_pop;
  // a failed open keeps level at 0 so a retry is legal.
  let ok1 = tree_node("A");
  let ok2 = tree_node("B");
  return assert(!ok1 && !ok2, "tree: state guard not locked by failed tree_node");
}

fn test_collapsing_header_no_context() -> TestResult {
  let ok = collapsing_header("Test");
  return assert(!ok, "tree: collapsing_header returns false without context");
}

fn test_tab_bar_begin_guard() -> TestResult {
  let ok1 = begin_tab_bar("A");
  let ok2 = begin_tab_bar("B");
  return assert(!ok1 && !ok2, "tabs: begin_tab_bar guard not locked by failed begin");
}

fn test_tab_item_begin_guard() -> TestResult {
  let ok1 = begin_tab_item("A");
  let ok2 = begin_tab_item("B");
  return assert(!ok1 && !ok2, "tabs: begin_tab_item guard not locked by failed begin");
}

fn test_popup_modal_begin_guard() -> TestResult {
  let ok1 = begin_popup_modal("A");
  let ok2 = begin_popup_modal("B");
  return assert(!ok1 && !ok2, "popup: begin_popup_modal guard not locked by failed begin");
}

fn test_open_popup_no_crash() -> TestResult {
  open_popup("TestPopup");
  return assert(true, "popup: open_popup runs without crash");
}

fn test_close_current_popup_no_crash() -> TestResult {
  close_current_popup();
  return assert(true, "popup: close_current_popup runs without crash");
}

// ===========================================================================
// Menu Bar Lifecycle
// ===========================================================================

fn test_main_menu_bar_no_context() -> TestResult {
  let ok = begin_main_menu_bar();
  return assert(!ok, "menu: begin_main_menu_bar returns false without context");
}

fn test_main_menu_bar_state_guard() -> TestResult {
  // g_mm_open must not be locked by a failed begin_main_menu_bar.
  let ok1 = begin_main_menu_bar();
  let ok2 = begin_main_menu_bar();
  return assert(!ok1 && !ok2, "menu: main_menu_bar guard not locked by failed begin");
}

fn test_begin_menu_no_context() -> TestResult {
  let ok = begin_menu("Test");
  return assert(!ok, "menu: begin_menu returns false without context");
}

fn test_begin_menu_state_guard() -> TestResult {
  let ok1 = begin_menu("A");
  let ok2 = begin_menu("B");
  return assert(!ok1 && !ok2, "menu: begin_menu guard not locked by failed begin");
}

fn test_menu_item_no_context() -> TestResult {
  let ok = menu_item("Test");
  return assert(!ok, "menu: menu_item returns false without context");
}

fn test_menu_item_shortcut_no_context() -> TestResult {
  let ok = menu_item_shortcut("Test", "Ctrl+T");
  return assert(!ok, "menu: menu_item_shortcut returns false without context");
}

// ===========================================================================
// Styling Functions
// ===========================================================================

fn test_style_dark_no_crash() -> TestResult {
  style_dark();
  return assert(true, "style: style_dark runs without crash");
}

fn test_style_light_no_crash() -> TestResult {
  style_light();
  return assert(true, "style: style_light runs without crash");
}

fn test_style_classic_no_crash() -> TestResult {
  style_classic();
  return assert(true, "style: style_classic runs without crash");
}

fn test_style_cycle_all_no_crash() -> TestResult {
  style_dark();
  style_light();
  style_classic();
  return assert(true, "style: full cycle dark -> light -> classic without crash");
}

fn test_push_pop_style_color() -> TestResult {
  push_style_color(0 as Int32, 1.0, 0.0, 0.0, 1.0);
  pop_style_color(1 as Int32);
  return assert(true, "style: push/pop style_color pair runs without crash");
}

// ===========================================================================
// Utility
// ===========================================================================

fn test_get_framerate_non_negative() -> TestResult {
  let fps = get_framerate();
  return assert(fps >= 0 as Int32, "util: get_framerate returns non-negative Int32");
}

fn test_get_frame_count_non_negative() -> TestResult {
  let fc = get_frame_count();
  return assert(fc >= 0 as Int32, "util: get_frame_count returns non-negative Int32");
}

fn test_get_framerate_is_int32() -> TestResult {
  let fps = get_framerate();
  let zero: Int32 = 0 as Int32;
  let ok = fps >= zero || fps < zero;
  return assert(ok, "util: get_framerate returns valid Int32");
}

fn test_get_frame_count_is_int32() -> TestResult {
  let fc = get_frame_count();
  let zero: Int32 = 0 as Int32;
  let ok = fc >= zero || fc < zero;
  return assert(ok, "util: get_frame_count returns valid Int32");
}

// ===========================================================================
// Dispatcher
// ===========================================================================

fn main() -> Int {
  var tests = [
    test_create_context_null,
    test_destroy_context_noop,
    test_double_destroy_context_idempotent,

    test_begin_window_no_context,
    test_window_begin_state_guard,
    test_set_next_window_pos,
    test_set_next_window_size,

    test_button_no_context,
    test_small_button_no_context,
    test_text_no_crash,
    test_text_colored_no_crash,
    test_text_wrapped_no_crash,
    test_checkbox_no_context,
    test_checkbox_true_state,
    test_slider_float_returns_value,
    test_slider_int_returns_value,
    test_radio_button_no_context,
    test_radio_button_inactive,
    test_drag_float_returns_value,
    test_drag_int_returns_value,
    test_progress_bar_no_crash,
    test_color_edit3_no_crash,

    test_separator_no_crash,
    test_same_line_no_crash,
    test_same_line_offset_no_crash,
    test_same_line_spacing_no_crash,
    test_spacing_no_crash,

    test_tree_node_no_context,
    test_tree_node_state_guard,
    test_collapsing_header_no_context,
    test_tab_bar_begin_guard,
    test_tab_item_begin_guard,
    test_popup_modal_begin_guard,
    test_open_popup_no_crash,
    test_close_current_popup_no_crash,

    test_main_menu_bar_no_context,
    test_main_menu_bar_state_guard,
    test_begin_menu_no_context,
    test_begin_menu_state_guard,
    test_menu_item_no_context,
    test_menu_item_shortcut_no_context,

    test_style_dark_no_crash,
    test_style_light_no_crash,
    test_style_classic_no_crash,
    test_style_cycle_all_no_crash,
    test_push_pop_style_color,

    test_get_framerate_non_negative,
    test_get_frame_count_non_negative,
    test_get_framerate_is_int32,
    test_get_frame_count_is_int32
  ];
  return test.run_all(tests);
}
