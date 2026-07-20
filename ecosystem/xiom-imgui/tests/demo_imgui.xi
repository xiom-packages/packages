// XIOM — ImGui Demo (v0.49.2, pure raw C FFI — zero generics)
// NO module imports. NO safe wrappers. ALL functions are extern C.
// Eliminates "unknown type T" and "moved value" compiler warnings.
module imgui_demo

// ── ALL extern C — zero generics, zero module deps ──
extern "C" {
  // Vulkan bridge
  fn xvk_app_create(title: Str, width: Int32, height: Int32) -> Int;
  fn xvk_app_destroy(app: Int);
  fn xvk_app_poll(app: Int);
  fn xvk_begin_frame(app: Int) -> Int32;
  fn xvk_end_frame(app: Int);
  fn xvk_get_key(app: Int, key: Int32) -> Int32;
  fn xvk_set_clear_color(app: Int, r: Float32, g: Float32, b: Float32);
  fn xvk_get_fb_width(app: Int) -> Int32;
  fn xvk_get_fb_height(app: Int) -> Int32;
  fn xvk_get_glfw_window(app: Int) -> Int;
  fn xvk_get_instance(app: Int) -> Int;
  fn xvk_get_device(app: Int) -> Int;
  fn xvk_get_physical_device(app: Int) -> Int;
  fn xvk_get_graphics_queue(app: Int) -> Int;
  fn xvk_get_render_pass(app: Int) -> Int;
  fn xvk_get_command_buffer(app: Int) -> Int;
  fn xvk_app_toggle_fullscreen(app: Int);
  fn xvk_camera_set_aspect_from_fb(app: Int, fb_w: Int32, fb_h: Int32);
  fn xvk_camera_orbit(app: Int, dyaw: Float32, dpitch: Float32, dradius: Float32);
  fn xvk_draw_cube_3d_at(app: Int, angle: Float32, px: Float32, py: Float32, pz: Float32, scale: Float32);
  fn xvk_cos(x: Float32) -> Float32;
  fn xvk_sin(x: Float32) -> Float32;

  // ImGui bridge
  fn imgui_bridge_init(glfw_window: Int) -> Int32;
  fn imgui_bridge_shutdown();
  fn imgui_bridge_init_vulkan(instance: Int, device: Int, physical_device: Int,
      graphics_queue: Int, queue_family: Int32, render_pass: Int,
      subpass_index: Int32, fb_width: Float32, fb_height: Float32) -> Int32;
  fn imgui_bridge_new_frame_sized(fb_w: Int32, fb_h: Int32);
  fn imgui_bridge_render(command_buffer: Int);

  // ImGui widgets
  fn imgui_begin(name: Str, flags: Int32) -> Int32;
  fn imgui_end();
  fn imgui_set_next_window_size_i32(w: Int32, h: Int32);
  fn imgui_set_next_window_pos_i32(x: Int32, y: Int32);
  fn imgui_button(label: Str) -> Int32;
  fn imgui_text(text: Str);
  fn imgui_text_colored(r: Float32, g: Float32, b: Float32, a: Float32, text: Str);
  fn imgui_text_wrapped(text: Str);
  fn imgui_slider_float(label: Str, v: Float32, mn: Float32, mx: Float32) -> Float32;
  fn imgui_slider_int(label: Str, v: Int32, mn: Int32, mx: Int32) -> Int32;
  fn imgui_checkbox(label: Str, checked: Int32) -> Int32;
  fn imgui_drag_float(label: Str, v: Float32, spd: Float32, mn: Float32, mx: Float32) -> Float32;
  fn imgui_drag_int(label: Str, v: Int32, spd: Float32, mn: Int32, mx: Int32) -> Int32;
  fn imgui_color_edit3(label: Str, r: Float32, g: Float32, b: Float32) -> Int32;
  fn imgui_progress_bar(fraction: Float32, w: Float32, h: Float32);
  fn imgui_radio_button(label: Str, active: Int32) -> Int32;
  fn imgui_separator();
  fn imgui_same_line(offset: Float32, spacing: Float32);
  fn imgui_tree_node(label: Str) -> Int32;
  fn imgui_tree_pop();
  fn imgui_collapsing_header(label: Str) -> Int32;
  fn imgui_begin_tab_bar(id: Str) -> Int32;
  fn imgui_end_tab_bar();
  fn imgui_begin_tab_item(label: Str) -> Int32;
  fn imgui_end_tab_item();
  fn imgui_open_popup(id: Str);
  fn imgui_begin_popup_modal(name: Str) -> Int32;
  fn imgui_end_popup_modal();
  fn imgui_close_current_popup();
  fn imgui_begin_main_menu_bar() -> Int32;
  fn imgui_end_main_menu_bar();
  fn imgui_begin_menu(label: Str) -> Int32;
  fn imgui_end_menu();
  fn imgui_menu_item(label: Str, shortcut: Str, enabled: Int32) -> Int32;
  fn imgui_style_dark();
  fn imgui_style_light();
  fn imgui_style_classic();
  fn imgui_get_framerate() -> Int32;
}

// Simple helpers to reduce verbosity
fn ib(label: Str, flags: Int32) -> Int32 { unsafe { imgui_begin(label, flags) } }
fn ie() { unsafe { imgui_end(); } }
fn btn(label: Str) -> Int32 { unsafe { imgui_button(label) } }
fn txt(text: Str) { unsafe { imgui_text(text); } }
fn sep() { unsafe { imgui_separator(); } }
fn tn(label: Str) -> Int32 { unsafe { imgui_tree_node(label) } }
fn tp() { unsafe { imgui_tree_pop(); } }
fn ch(label: Str) -> Int32 { unsafe { imgui_collapsing_header(label) } }
fn menu(label: Str) -> Int32 { unsafe { imgui_begin_menu(label) } }
fn mitem(label: Str) -> Int32 { unsafe { imgui_menu_item(label, "", 1) } }

var g_s_f  : Float32 = 0.65;
var g_s_i  : Int32 = 32;
var g_c1   : Int32 = 1;
var g_c2   : Int32 = 0;
var g_c3   : Int32 = 0;
var g_dragf: Float32 = 1.0;
var g_dragi: Int32 = 50;
var g_cr   : Float32 = 0.18;
var g_cg   : Float32 = 0.64;
var g_cb   : Float32 = 0.88;
var g_radio: Int32 = 0;
var g_prog : Float32 = 0.4;
var g_frame: Int32 = 0;
var g_time : Float32 = 0.0;
var g_f11p : Int32 = 0;
var g_modal: Int32 = 0;
var g_theme: Int32 = 0;
var g_done : Int32 = 0;

fn main() -> Int {
  let aapp: Int = unsafe { xvk_app_create("XIOM ImGui Demo", 1280, 800) };
  if aapp == 0 { return 1; }
  let a: Int = aapp;

  let w = unsafe { xvk_get_glfw_window(a) };
  let i = unsafe { xvk_get_instance(a) };
  let d = unsafe { xvk_get_device(a) };
  let p = unsafe { xvk_get_physical_device(a) };
  let q = unsafe { xvk_get_graphics_queue(a) };
  let r = unsafe { xvk_get_render_pass(a) };

  if unsafe { imgui_bridge_init(w) } == 0 { unsafe { xvk_app_destroy(a); }; return 1; }
  if unsafe { imgui_bridge_init_vulkan(i, d, p, q, 0, r, 0, 1280.0, 800.0) } == 0 {
    unsafe { imgui_bridge_shutdown(); }; unsafe { xvk_app_destroy(a); }; return 1;
  }

  g_done = 0;
  while g_done == 0 && g_frame < 100000 {
    if unsafe { xvk_get_key(a, 256) } != 0 { g_done = 1; }
    let f11: Int32 = unsafe { xvk_get_key(a, 292) };
    if f11 != 0 && g_f11p == 0 { unsafe { xvk_app_toggle_fullscreen(a); }; }
    g_f11p = f11;
    unsafe { xvk_app_poll(a); };
    unsafe { xvk_set_clear_color(a, 0.05, 0.05, 0.09); };

    let s: Int32 = unsafe { xvk_begin_frame(a) };
    if s == 1 {
      g_frame = g_frame + 1;
      g_time = g_time + 0.016;

      let fw: Int32 = unsafe { xvk_get_fb_width(a) };
      let fh: Int32 = unsafe { xvk_get_fb_height(a) };

      // 3D scene
      unsafe { xvk_camera_set_aspect_from_fb(a, fw, fh); };
      unsafe { xvk_camera_orbit(a, 0.008, 0.0, 0.0); };
      let ang: Float32 = g_time * 1.5;
      unsafe { xvk_draw_cube_3d_at(a, ang, 0.0, 0.0, 0.0, 0.45); };

      // ImGui
      unsafe { imgui_bridge_new_frame_sized(fw, fh); };

      let pad: Int32 = 8;
      let sbh: Int32 = 30;
      let th: Int32 = (fw - pad * 4) / 3;
      let ch: Int32 = fh - sbh - 32;

      // Menu bar
      if unsafe { imgui_begin_main_menu_bar() } != 0 {
        if menu("File") != 0 {
          if mitem("Exit") != 0 { g_done = 1; }
          unsafe { imgui_end_menu(); };
        }
        if menu("Theme") != 0 {
          if mitem("Dark") != 0 { g_theme = 0; unsafe { imgui_style_dark(); }; }
          if mitem("Light") != 0 { g_theme = 1; unsafe { imgui_style_light(); }; }
          if mitem("Classic") != 0 { g_theme = 2; unsafe { imgui_style_classic(); }; }
          unsafe { imgui_end_menu(); };
        }
        unsafe { imgui_end_main_menu_bar(); };
      }

      // Widgets panel (left)
      unsafe { imgui_set_next_window_pos_i32(pad, 20); };
      unsafe { imgui_set_next_window_size_i32(th, ch); };
      if ib("Widgets", 0) != 0 {
        g_s_f = unsafe { imgui_slider_float("Float", g_s_f, 0.0, 1.0) };
        g_s_i = unsafe { imgui_slider_int("Int %", g_s_i, 0, 100) };
        sep();
        g_c1 = unsafe { imgui_checkbox("Feature A", g_c1) };
        g_c2 = unsafe { imgui_checkbox("Feature B", g_c2) };
        g_c3 = unsafe { imgui_checkbox("Feature C", g_c3) };
        sep();
        if unsafe { imgui_radio_button("Opt 1", if g_radio == 0 { 1 } else { 0 }) } != 0 { g_radio = 0; }
        unsafe { imgui_same_line(0.0, 0.0); };
        if unsafe { imgui_radio_button("Opt 2", if g_radio == 1 { 1 } else { 0 }) } != 0 { g_radio = 1; }
        unsafe { imgui_same_line(0.0, 0.0); };
        if unsafe { imgui_radio_button("Opt 3", if g_radio == 2 { 1 } else { 0 }) } != 0 { g_radio = 2; }
        sep();
        g_dragf = unsafe { imgui_drag_float("Scale", g_dragf, 0.05, 0.0, 10.0) };
        g_dragi = unsafe { imgui_drag_int("Count", g_dragi, 1.0, 0, 200) };
        sep();
        g_prog = g_prog + 0.002;
        if g_prog > 1.0 { g_prog = 0.0; }
        unsafe { imgui_progress_bar(g_prog, -1.0, 0.0); };
        sep();
        unsafe { imgui_color_edit3("RGB", g_cr, g_cg, g_cb); };
        sep();
        if btn("Open Modal") != 0 { g_modal = 1; }
        ie();
      }

      // Browser (center)
      let bx: Int32 = pad * 2 + th;
      unsafe { imgui_set_next_window_pos_i32(bx, 20); };
      unsafe { imgui_set_next_window_size_i32(th, ch); };
      if ib("Browser", 0) != 0 {
        if ch("Meshes") != 0 {
          if tn("Cube") != 0 { txt("24 vertices"); tp(); }
          if tn("Sphere") != 0 { txt("128 vertices"); tp(); }
        }
        if ch("Textures") != 0 {
          if tn("Diffuse") != 0 { txt("albedo.png"); tp(); }
        }
        ie();
      }

      // Performance (right top)
      let tx: Int32 = pad * 3 + th * 2;
      unsafe { imgui_set_next_window_pos_i32(tx, 20); };
      unsafe { imgui_set_next_window_size_i32(th, (fh / 2 - 16)); };
      if ib("Performance", 0) != 0 {
        let fps = unsafe { imgui_get_framerate() };
        if fps >= 55 { unsafe { imgui_text_colored(0.2, 1.0, 0.3, 1.0, "  GOOD"); }; }
        elif fps >= 30 { unsafe { imgui_text_colored(1.0, 0.9, 0.2, 1.0, "  OK"); }; }
        else { unsafe { imgui_text_colored(1.0, 0.2, 0.2, 1.0, "  SLOW"); }; }
        sep();
        txt("XIOM v0.49.2 | ImGui v1.92.9 | F11=fullscreen | Esc=exit");
        ie();
      }

      // Settings (right bottom)
      unsafe { imgui_set_next_window_pos_i32(tx, (fh / 2 + 4)); };
      unsafe { imgui_set_next_window_size_i32(th, (fh / 2 - 50)); };
      if ib("Settings", 0) != 0 {
        if unsafe { imgui_begin_tab_bar("Tabs") } != 0 {
          if unsafe { imgui_begin_tab_item("Render") } != 0 {
            g_c1 = unsafe { imgui_checkbox("Wireframe", g_c1) };
            g_c3 = unsafe { imgui_checkbox("Post-FX", g_c3) };
            unsafe { imgui_end_tab_item(); };
          }
          if unsafe { imgui_begin_tab_item("About") } != 0 {
            unsafe { imgui_text_wrapped("XIOM ImGui Demo — v0.49.2 pure raw C FFI. Zero generics, zero module imports. Dear ImGui v1.92.9 with Vulkan backend."); };
            unsafe { imgui_end_tab_item(); };
          }
          unsafe { imgui_end_tab_bar(); };
        }
        ie();
      }

      // Status bar
      unsafe { imgui_set_next_window_pos_i32(0, fh - sbh); };
      unsafe { imgui_set_next_window_size_i32(fw, sbh); };
      if ib("##Status", 0) != 0 {
        let fps = unsafe { imgui_get_framerate() };
        if fps >= 55 { unsafe { imgui_text_colored(0.2, 1.0, 0.3, 1.0, "FPS: "); }; }
        elif fps >= 30 { unsafe { imgui_text_colored(1.0, 0.9, 0.2, 1.0, "FPS: "); }; }
        else { unsafe { imgui_text_colored(1.0, 0.2, 0.2, 1.0, "FPS: "); }; }
        unsafe { imgui_same_line(36.0, 0.0); };
        txt("| XIOM | ImGui | pure C FFI");
        ie();
      }

      // Modal
      if g_modal != 0 { unsafe { imgui_open_popup("MyModal"); }; g_modal = 0; }
      if unsafe { imgui_begin_popup_modal("MyModal") } != 0 {
        txt("XIOM ImGui Demo — pure raw C FFI");
        sep();
        if btn("Close") != 0 { unsafe { imgui_close_current_popup(); }; }
        unsafe { imgui_end_popup_modal(); };
      }

      let cb = unsafe { xvk_get_command_buffer(a) };
      unsafe { imgui_bridge_render(cb); };
      unsafe { xvk_end_frame(a); };
    } elif s == -1 { g_done = 1; }
  }

  unsafe { imgui_bridge_shutdown(); };
  unsafe { xvk_app_destroy(a); };
  return 0;
}
