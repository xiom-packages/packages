// XIOM — ImGui Demo (v0.49.1, raw FFI — bypass generic wrapper bug)
// Pure raw FFI: no xiom.vulkan safe wrappers (avoids "unknown type T" compiler warning).
// All vulkan calls use extern C functions directly from vulkan.xi.

module imgui_demo
use xiom.io;
use xiom.imgui;

// Raw FFI imports from vulkan.xi directly
extern "C" {
  fn xvk_app_create(title: Str, width: Int32, height: Int32) -> Int;
  fn xvk_app_destroy(app: Int);
  fn xvk_app_poll(app: Int);
  fn xvk_should_close(app: Int) -> Int32;
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
  fn xvk_last_error() -> Int;
  fn xvk_app_toggle_fullscreen(app: Int);
  fn xvk_camera_set_aspect_from_fb(app: Int, fb_w: Int32, fb_h: Int32);
  fn xvk_camera_orbit(app: Int, dyaw: Float32, dpitch: Float32, dradius: Float32);
  fn xvk_draw_cube_3d_at(app: Int, angle: Float32, px: Float32, py: Float32, pz: Float32, scale: Float32);
  fn xvk_cos(x: Float32) -> Float32;
  fn xvk_sin(x: Float32) -> Float32;
}

var g_s_f: Float32 = 0.0;
var g_s_i: Int32 = 32;
var g_c1: Int32 = 1;
var g_c2: Int32 = 0;
var g_c3: Int32 = 0;
var g_drag_f: Float32 = 0.0;
var g_drag_i: Int32 = 50;
var g_cr: Float32 = 0.18;
var g_cg: Float32 = 0.64;
var g_cb: Float32 = 0.88;
var g_radio: Int32 = 0;
var g_progress: Float32 = 0.0;
var g_show_modal: Int32 = 0;
var g_frame: Int32 = 0;
var g_theme: Int32 = 0;
var g_time: Float32 = 0.0;
var g_f11_prev: Int32 = 0;

fn apply_theme(theme: Int32) {
  if theme == 0 { style_dark(); }
  elif theme == 1 { style_light(); }
  else { style_classic(); }
}

fn draw_3d_scene(app: Int, time: Float32, fb_w: Int32, fb_h: Int32) {
  unsafe { xvk_camera_set_aspect_from_fb(app, fb_w, fb_h); };
  unsafe { xvk_camera_orbit(app, 0.008, 0.0, 0.0); };

  let angle: Float32 = time * 1.5;
  unsafe { xvk_draw_cube_3d_at(app, angle, 0.0, 0.0, 0.0, 0.45); };

  let s1_t: Float32 = time * 1.8;
  let s1_x: Float32 = 1.3 * unsafe { xvk_cos(s1_t) };
  let s1_z: Float32 = 1.3 * unsafe { xvk_sin(s1_t) };
  let s1_b: Float32 = 0.2 * unsafe { xvk_sin(time * 2.0) };
  unsafe { xvk_draw_cube_3d_at(app, s1_t * 0.5, s1_x, s1_b, s1_z, 0.15); };

  let s2_t: Float32 = time * 1.3 + 2.1;
  let s2_x: Float32 = 1.6 * unsafe { xvk_cos(s2_t) };
  let s2_z: Float32 = 1.6 * unsafe { xvk_sin(s2_t) };
  unsafe { xvk_draw_cube_3d_at(app, s2_t * 0.6, s2_x, -0.25, s2_z, 0.12); };

  let s3_t: Float32 = time * 0.9 + 4.2;
  let s3_x: Float32 = 1.9 * unsafe { xvk_cos(s3_t) };
  let s3_z: Float32 = 1.9 * unsafe { xvk_sin(s3_t) };
  let s3_b: Float32 = 0.35 * unsafe { xvk_cos(time * 1.5) };
  unsafe { xvk_draw_cube_3d_at(app, s3_t * 0.4, s3_x, s3_b, s3_z, 0.10); };
}

fn main() -> Int {
  let app: Int = unsafe { xvk_app_create("XIOM ImGui Demo", 1280, 800) };
  if app == 0 { io.println("FAILED: xvk_app_create"); return 1; }

  let win  = unsafe { xvk_get_glfw_window(app) };
  let inst = unsafe { xvk_get_instance(app) };
  let dev  = unsafe { xvk_get_device(app) };
  let phys = unsafe { xvk_get_physical_device(app) };
  let q    = unsafe { xvk_get_graphics_queue(app) };
  let rp   = unsafe { xvk_get_render_pass(app) };

  if !create_context(win) { unsafe { xvk_app_destroy(app); }; return 1; }
  if !init_vulkan(inst, dev, phys, q, 0, rp, 0, 1280.0, 800.0) {
    destroy_context(); unsafe { xvk_app_destroy(app); }; return 1;
  }

  io.println("[demo] entering loop");
  let close: Int32 = 0;

  while close == 0 && g_frame < 100000 {
    let esc: Int32 = unsafe { xvk_get_key(app, 256) };
    if esc != 0 { io.println("[demo] Escape"); break; }

    let f11: Int32 = unsafe { xvk_get_key(app, 292) };
    if f11 != 0 && g_f11_prev == 0 {
      unsafe { xvk_app_toggle_fullscreen(app); };
    }
    g_f11_prev = f11;

    unsafe { xvk_app_poll(app); };
    unsafe { xvk_set_clear_color(app, 0.05, 0.05, 0.09); };

    let status: Int32 = unsafe { xvk_begin_frame(app) };
    if status == 1 {
      g_frame = g_frame + 1;
      if g_frame == 1 { io.println("[demo] frame 1 OK"); }

      let fb_w: Int32 = unsafe { xvk_get_fb_width(app) };
      let fb_h: Int32 = unsafe { xvk_get_fb_height(app) };

      draw_3d_scene(app, g_time, fb_w, fb_h);
      new_frame_sized(fb_w, fb_h);
      g_time = g_time + 0.016;

      // Simple UI — just text to verify rendering works
      let pad: Int32 = 8;
      let sbh: Int32 = 30;
      let third: Int32 = (fb_w - pad * 4) / 3;
      let content_h: Int32 = fb_h - sbh - 32;

      // Menu
      if begin_main_menu_bar() {
        if begin_menu("File") {
          if menu_item("Exit") { close = 1; }
          end_menu();
        }
        if begin_menu("Theme") {
          if menu_item("Dark") { g_theme = 0; apply_theme(0); }
          if menu_item("Light") { g_theme = 1; apply_theme(1); }
          if menu_item("Classic") { g_theme = 2; apply_theme(2); }
          end_menu();
        }
        end_main_menu_bar();
      }

      // Widgets
      set_next_window_pos(pad, 20);
      set_next_window_size(third, content_h);
      if begin_window("Widgets", 0) {
        g_s_f = slider_float("Float", g_s_f, 0.0, 1.0);
        g_s_i = slider_int("Int %", g_s_i, 0, 100);
        separator();
        g_c1 = if checkbox("Feature A", g_c1 != 0) { 1 } else { 0 };
        g_c2 = if checkbox("Feature B", g_c2 != 0) { 1 } else { 0 };
        separator();
        if radio_button("Option 1", g_radio == 0) { g_radio = 0; }
        unsafe { imgui_same_line(0.0, 0.0); };
        if radio_button("Option 2", g_radio == 1) { g_radio = 1; }
        unsafe { imgui_same_line(0.0, 0.0); };
        if radio_button("Option 3", g_radio == 2) { g_radio = 2; }
        separator();
        g_drag_f = drag_float("Scale", g_drag_f, 0.05, 0.0, 10.0);
        g_drag_i = drag_int("Count", g_drag_i, 1.0, 0, 200);
        separator();
        g_progress = g_progress + 0.002;
        if g_progress > 1.0 { g_progress = 0.0; }
        progress_bar(g_progress);
        separator();
        color_edit3("RGB", g_cr, g_cg, g_cb);
        separator();
        if button("Open Modal") { g_show_modal = 1; }
        end_window();
      }

      // Browser
      let bx: Int32 = pad * 2 + third;
      set_next_window_pos(bx, 20);
      set_next_window_size(third, content_h);
      if begin_window("Browser", 0) {
        if collapsing_header("Meshes") {
          if tree_node("Cube") { text("24 vertices"); tree_pop(); }
          if tree_node("Sphere") { text("128 vertices"); tree_pop(); }
        }
        if collapsing_header("Textures") {
          if tree_node("Diffuse") { text("albedo.png"); tree_pop(); }
        }
        end_window();
      }

      // Performance
      let tx: Int32 = pad * 3 + third * 2;
      set_next_window_pos(tx, 20);
      set_next_window_size(third, (fb_h / 2 - 16));
      if begin_window("Performance", 0) {
        let fps: Int32 = get_framerate();
        if fps >= 55 { text_colored(0.2, 1.0, 0.3, 1.0, "  GOOD"); }
        elif fps >= 30 { text_colored(1.0, 0.9, 0.2, 1.0, "  OK"); }
        else { text_colored(1.0, 0.2, 0.2, 1.0, "  SLOW"); }
        separator();
        text("XIOM v0.49.1 | ImGui v1.92.9");
        text("F11=fullscreen | Esc=exit");
        end_window();
      }

      // Settings tabs
      set_next_window_pos(tx, (fb_h / 2 + 4));
      set_next_window_size(third, (fb_h / 2 - 50));
      if begin_window("Settings", 0) {
        if begin_tab_bar("Tabs") {
          if begin_tab_item("Render") {
            g_c1 = if checkbox("Wireframe", g_c1 != 0) { 1 } else { 0 };
            g_c3 = if checkbox("Post-FX",  g_c3 != 0) { 1 } else { 0 };
            end_tab_item();
          }
          if begin_tab_item("About") {
            text_wrapped("XIOM ImGui Demo — v0.49.1 raw FFI. Dear ImGui v1.92.9 with Vulkan backend.");
            end_tab_item();
          }
          end_tab_bar();
        }
        end_window();
      }

      // Status bar
      set_next_window_pos(0, fb_h - sbh);
      set_next_window_size(fb_w, sbh);
      if begin_window("##Status", 0) {
        let fps: Int32 = get_framerate();
        if fps >= 55 { text_colored(0.2, 1.0, 0.3, 1.0, "FPS: "); }
        elif fps >= 30 { text_colored(1.0, 0.9, 0.2, 1.0, "FPS: "); }
        else { text_colored(1.0, 0.2, 0.2, 1.0, "FPS: "); }
        unsafe { imgui_same_line(36.0, 0.0); };
        text("| XIOM | ImGui | accent");
        end_window();
      }

      // Modal
      if g_show_modal != 0 { open_popup("MyModal"); g_show_modal = 0; }
      if begin_popup_modal("MyModal") {
        text("XIOM ImGui Demo");
        separator();
        if button("Close") { close_current_popup(); }
        end_popup_modal();
      }

      let cb = unsafe { xvk_get_command_buffer(app) };
      render(cb);
      unsafe { xvk_end_frame(app); };
    } elif status == -1 {
      io.println("[demo] begin_frame error");
      break;
    }
  }

  io.println("[demo] shutdown");
  destroy_context();
  unsafe { xvk_app_destroy(app); };
  return 0;
}
