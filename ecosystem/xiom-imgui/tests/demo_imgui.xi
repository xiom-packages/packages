// XIOM — ImGui Production Demo (v0.48.7, 3D Viewport)
// Fluid layout relative to framebuffer. F11 fullscreen, drag resize, Escape to close.
// 3D scene: rotating cube + orbiting satellites rendered behind ImGui panels.
// Camera orbits automatically; static viewport (1280x800) — known pipeline limitation.

module imgui_demo
use xiom.io;
use xiom.vulkan;
use xiom.imgui;

var g_app: Int = 0;
var g_s_f: Float32 = 0.0;
var g_s_i: Int = 0;
var g_c1: Int = 0;
var g_c2: Int = 0;
var g_c3: Int = 0;
var g_drag_f: Float32 = 0.0;
var g_drag_i: Int = 0;
var g_cr: Float32 = 0.0;
var g_cg: Float32 = 0.0;
var g_cb: Float32 = 0.0;
var g_radio: Int = 0;
var g_progress: Float32 = 0.0;
var g_show_modal: Int = 0;
var g_frame: Int = 0;
var g_theme: Int = 0;
var g_time: Float32 = 0.0;

fn apply_theme(theme: Int) {
  if theme == 0 { unsafe { imgui_style_dark(); }; }
  elif theme == 1 { unsafe { imgui_style_light(); }; }
  else { unsafe { imgui_style_classic(); }; }
}

fn draw_3d_scene(app: Int, time: Float32, fb_w: Int, fb_h: Int) {
  // Set aspect ratio from current framebuffer dimensions
  let aspect: Float32 = (fb_w as Float32) / (fb_h as Float32);
  unsafe { xvk_camera_set_aspect_ratio(aspect); };

  // Orbiting camera — slowly rotates around origin
  unsafe { xvk_camera_orbit(0.008, 0.0, 0.0); };

  // Central rotating cube
  let angle: Float32 = time * 1.5;
  unsafe { xvk_draw_cube_3d_at(app, angle, 0.0, 0.0, 0.0, 0.45); };

  // Satellite 1: circular orbit at radius 1.3
  let s1_t  : Float32 = time * 1.8;
  let s1_x  : Float32 = 1.3 * unsafe { xvk_cos(s1_t) };
  let s1_z  : Float32 = 1.3 * unsafe { xvk_sin(s1_t) };
  let s1_b  : Float32 = 0.2 * unsafe { xvk_sin(time * 2.0) };
  unsafe { xvk_draw_cube_3d_at(app, s1_t * 0.5, s1_x, s1_b, s1_z, 0.15); };

  // Satellite 2: larger orbit, different phase
  let s2_t  : Float32 = time * 1.3 + 2.1;
  let s2_x  : Float32 = 1.6 * unsafe { xvk_cos(s2_t) };
  let s2_z  : Float32 = 1.6 * unsafe { xvk_sin(s2_t) };
  unsafe { xvk_draw_cube_3d_at(app, s2_t * 0.6, s2_x, -0.25, s2_z, 0.12); };

  // Satellite 3: eccentric orbit
  let s3_t  : Float32 = time * 0.9 + 4.2;
  let s3_x  : Float32 = 1.9 * unsafe { xvk_cos(s3_t) };
  let s3_z  : Float32 = 1.9 * unsafe { xvk_sin(s3_t) };
  let s3_b  : Float32 = 0.35 * unsafe { xvk_cos(time * 1.5) };
  unsafe { xvk_draw_cube_3d_at(app, s3_t * 0.4, s3_x, s3_b, s3_z, 0.10); };
}

fn main() -> Int {
  let app = create_app("XIOM ImGui Demo", 1280, 800);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      g_app = a;
      g_s_f = 0.65; g_s_i = 32; g_c1 = 1; g_c2 = 0; g_c3 = 0;
      g_drag_f = 1.0; g_drag_i = 50;
      g_cr = 0.18; g_cg = 0.64; g_cb = 0.88;
      g_radio = 0; g_progress = 0.4;
      g_show_modal = 0;
      g_frame = 0;
      g_theme = 0;
      g_time = 0.0;

      let win  = unsafe { xvk_get_glfw_window(a) };
      let inst = unsafe { xvk_get_instance(a) };
      let dev  = unsafe { xvk_get_device(a) };
      let phys = unsafe { xvk_get_physical_device(a) };
      let q    = unsafe { xvk_get_graphics_queue(a) };
      let rp   = unsafe { xvk_get_render_pass(a) };

      if unsafe { imgui_bridge_init(win) } == 0 { destroy_app(a); return 1; }
      if unsafe { imgui_bridge_init_vulkan(inst, dev, phys, q, 0 as Int32, rp, 0 as Int32, 1280.0, 800.0) } == 0 {
        unsafe { imgui_bridge_shutdown(); }; destroy_app(a); return 1;
      }

      while !should_close(a) && g_frame < 100000 {
        if is_key_down(a, 256) { break; }
        if is_key_down(a, 292) { unsafe { xvk_app_toggle_fullscreen(a); }; }  // F11
        poll(a);
        // Subtle color shift over time (linear oscillation)
        let cr: Float32 = 0.04 + 0.015 * (g_time * 0.3);
        let cg: Float32 = 0.04 + 0.015 * (g_time * 0.5 + 1.0);
        let cb: Float32 = 0.08 + 0.02 * (1.0 - g_time * 0.2);
        set_clear_color(a, cr, cg, cb);
        let status = begin_frame(a);
        if status == 1 {
          g_frame = g_frame + 1;
          g_time = g_time + 0.016;  // approximate dt

          // ── 3D SCENE (renders before ImGui, behind panels) ──
          let fb_w = unsafe { xvk_get_fb_width(a) } as Int;
          let fb_h = unsafe { xvk_get_fb_height(a) } as Int;
          draw_3d_scene(a, g_time, fb_w, fb_h);

          // ── ImGui setup ──
          let fb_w = unsafe { xvk_get_fb_width(a) } as Int;
          let fb_h = unsafe { xvk_get_fb_height(a) } as Int;
          unsafe { imgui_bridge_new_frame_sized(fb_w as Int32, fb_h as Int32); };

          // Fluid layout: 3 columns + bottom status bar
          let pad: Int = 8;
          let sbh: Int = 30;
          let third: Int = (fb_w - pad * 4) / 3;
          let content_h: Int = fb_h - sbh - 32;

          // ── MENU BAR ──
          if unsafe { imgui_begin_main_menu_bar() } != 0 {
            if unsafe { imgui_begin_menu("File") } != 0 {
              if unsafe { imgui_menu_item("Exit", "Alt+F4", 1 as Int32) } != 0 { break; }
              unsafe { imgui_end_menu(); };
            }
            if unsafe { imgui_begin_menu("Theme") } != 0 {
              if unsafe { imgui_menu_item("Dark", "", 1 as Int32) } != 0 { g_theme = 0; apply_theme(0); }
              if unsafe { imgui_menu_item("Light", "", 1 as Int32) } != 0 { g_theme = 1; apply_theme(1); }
              if unsafe { imgui_menu_item("Classic", "", 1 as Int32) } != 0 { g_theme = 2; apply_theme(2); }
              unsafe { imgui_end_menu(); };
            }
            unsafe { imgui_end_main_menu_bar(); };
          }

          // ── WIDGETS PANEL (left) ──
          unsafe { imgui_set_next_window_pos_i32(pad as Int32, 20 as Int32); };
          unsafe { imgui_set_next_window_size_i32(third as Int32, content_h as Int32); };
          if unsafe { imgui_begin("Widgets", 0 as Int32) } != 0 {
            g_s_f = unsafe { imgui_slider_float("Float", g_s_f, 0.0, 1.0) };
            g_s_i = unsafe { imgui_slider_int("Int %", g_s_i as Int32, 0 as Int32, 100 as Int32) };
            unsafe { imgui_separator(); };

            g_c1 = unsafe { imgui_checkbox("Feature A", g_c1) };
            g_c2 = unsafe { imgui_checkbox("Feature B", g_c2) };
            g_c3 = unsafe { imgui_checkbox("Feature C", g_c3) };
            unsafe { imgui_separator(); };

            g_radio = unsafe { imgui_radio_button("Option 1", if g_radio == 0 { 1 as Int32 } else { 0 as Int32 }) };
            if g_radio != 0 { g_radio = 0; }
            unsafe { imgui_same_line(0.0, 0.0); };
            g_radio = unsafe { imgui_radio_button("Option 2", if g_radio == 1 { 1 as Int32 } else { 0 as Int32 }) };
            if g_radio != 0 { g_radio = 1; }
            unsafe { imgui_same_line(0.0, 0.0); };
            g_radio = unsafe { imgui_radio_button("Option 3", if g_radio == 2 { 1 as Int32 } else { 0 as Int32 }) };
            if g_radio != 0 { g_radio = 2; }
            unsafe { imgui_separator(); };

            g_drag_f = unsafe { imgui_drag_float("Scale", g_drag_f, 0.05, 0.0, 10.0) };
            g_drag_i = unsafe { imgui_drag_int("Count", g_drag_i, 1.0, 0 as Int32, 200 as Int32) };
            unsafe { imgui_separator(); };

            g_progress = g_progress + 0.002;
            if g_progress > 1.0 { g_progress = 0.0; }
            unsafe { imgui_progress_bar(g_progress, -1.0, 0.0); };
            unsafe { imgui_separator(); };

            unsafe { imgui_color_edit3("RGB", g_cr, g_cg, g_cb); };
            unsafe { imgui_separator(); };
            if unsafe { imgui_button("Open Modal") } != 0 { g_show_modal = 1; }
            unsafe { imgui_end(); };
          }

          // ── BROWSER (center) ──
          let bx: Int = pad * 2 + third;
          unsafe { imgui_set_next_window_pos_i32(bx as Int32, 20 as Int32); };
          unsafe { imgui_set_next_window_size_i32(third as Int32, content_h as Int32); };
          if unsafe { imgui_begin("Browser", 0 as Int32) } != 0 {
            if unsafe { imgui_collapsing_header("Meshes") } != 0 {
              if unsafe { imgui_tree_node("Cube") } != 0 {
                unsafe { imgui_text("24 vertices"); };
                unsafe { imgui_text("36 indices"); };
                unsafe { imgui_text_wrapped("Simple cube mesh with per-face normals."); };
                unsafe { imgui_tree_pop(); };
              }
              if unsafe { imgui_tree_node("Sphere") } != 0 {
                unsafe { imgui_text("128 vertices"); };
                unsafe { imgui_text("224 indices"); };
                unsafe { imgui_tree_pop(); };
              }
              if unsafe { imgui_tree_node("Teapot") } != 0 {
                unsafe { imgui_text("1,024 vertices"); };
                unsafe { imgui_text_wrapped("Classic Utah teapot model."); };
                unsafe { imgui_tree_pop(); };
              }
            }
            if unsafe { imgui_collapsing_header("Textures") } != 0 {
              if unsafe { imgui_tree_node("Diffuse") } != 0 { unsafe { imgui_text("albedo.png"); }; unsafe { imgui_tree_pop(); }; }
              if unsafe { imgui_tree_node("Normal") } != 0 { unsafe { imgui_text("normal.png"); }; unsafe { imgui_tree_pop(); }; }
              if unsafe { imgui_tree_node("Roughness") } != 0 { unsafe { imgui_text("rough.png"); }; unsafe { imgui_tree_pop(); }; }
            }
            if unsafe { imgui_collapsing_header("Shaders") } != 0 {
              if unsafe { imgui_tree_node("PBR") } != 0 {
                unsafe { imgui_text_wrapped("Cook-Torrance BRDF with GGX distribution."); };
                unsafe { imgui_tree_pop(); };
              }
              if unsafe { imgui_tree_node("Skybox") } != 0 { unsafe { imgui_text("procedural"); }; unsafe { imgui_tree_pop(); }; }
            }
            unsafe { imgui_end(); };
          }

          // ── PERFORMANCE (right, top half) ──
          let tx: Int = pad * 3 + third * 2;
          unsafe { imgui_set_next_window_pos_i32(tx as Int32, 20 as Int32); };
          unsafe { imgui_set_next_window_size_i32(third as Int32, (fb_h / 2 - 16) as Int32); };
          if unsafe { imgui_begin("Performance", 0 as Int32) } != 0 {
            let fps = unsafe { imgui_get_framerate() } as Int;
            if fps >= 55 { unsafe { imgui_text_colored(0.2, 1.0, 0.3, 1.0, "  GOOD"); }; }
            elif fps >= 30 { unsafe { imgui_text_colored(1.0, 0.9, 0.2, 1.0, "  OK"); }; }
            else { unsafe { imgui_text_colored(1.0, 0.2, 0.2, 1.0, "  SLOW"); }; }
            unsafe { imgui_separator(); };

            unsafe { imgui_text("Runtime: XIOM v0.48.7"); };
            unsafe { imgui_text("Backend: GLFW + Vulkan 1.3"); };
            unsafe { imgui_text("GPU: RTX 3070 Ti"); };
            unsafe { imgui_text("3D: 4 cubes orbiting"); };
            unsafe { imgui_separator(); };

            unsafe { imgui_text_wrapped("F11 fullscreen | drag resize | Escape or File>Exit to close"); };
            unsafe { imgui_end(); };
          }

          // ── SETTINGS (right, bottom half) ──
          unsafe { imgui_set_next_window_pos_i32(tx as Int32, (fb_h / 2 + 4) as Int32); };
          unsafe { imgui_set_next_window_size_i32(third as Int32, (fb_h / 2 - 50) as Int32); };
          if unsafe { imgui_begin("Settings", 0 as Int32) } != 0 {
            if unsafe { imgui_begin_tab_bar("Tabs") } != 0 {
              if unsafe { imgui_begin_tab_item("Render") } != 0 {
                g_c1 = unsafe { imgui_checkbox("Wireframe", g_c1) };
                g_c2 = unsafe { imgui_checkbox("Shadows", g_c2) };
                g_c3 = unsafe { imgui_checkbox("Post-FX", g_c3) };
                unsafe { imgui_end_tab_item(); };
              }
              if unsafe { imgui_begin_tab_item("Audio") } != 0 {
                g_s_f = unsafe { imgui_slider_float("Master", g_s_f, 0.0, 1.0) };
                unsafe { imgui_end_tab_item(); };
              }
              if unsafe { imgui_begin_tab_item("About") } != 0 {
                unsafe { imgui_text_wrapped("XIOM ImGui Demo — Dear ImGui v1.92.9 with Vulkan backend. 70+ wrapped functions. 3D viewport with orbiting cubes."); };
                unsafe { imgui_end_tab_item(); };
              }
              unsafe { imgui_end_tab_bar(); };
            }
            unsafe { imgui_end(); };
          }

          // ── STATUS BAR ──
          unsafe { imgui_set_next_window_pos_i32(0 as Int32, (fb_h - sbh) as Int32); };
          unsafe { imgui_set_next_window_size_i32(fb_w as Int32, sbh as Int32); };
          if unsafe { imgui_begin("##Status", 0 as Int32) } != 0 {
            let fps = unsafe { imgui_get_framerate() } as Int;
            if fps >= 55 { unsafe { imgui_text_colored(0.2, 1.0, 0.3, 1.0, "FPS: "); }; }
            elif fps >= 30 { unsafe { imgui_text_colored(1.0, 0.9, 0.2, 1.0, "FPS: "); }; }
            else { unsafe { imgui_text_colored(1.0, 0.2, 0.2, 1.0, "FPS: "); }; }
            unsafe { imgui_same_line(36.0, 0.0); };
            unsafe { imgui_text("| XIOM v0.48.7 | ImGui v1.92.9 | 3D Viewport | "); };
            unsafe { imgui_same_line(0.0, 0.0); };
            unsafe { imgui_text_colored(g_cr, g_cg, g_cb, 1.0, "accent"); };
            unsafe { imgui_end(); };
          }

          // ── MODAL ──
          if g_show_modal != 0 { unsafe { imgui_open_popup("MyModal"); }; g_show_modal = 0; }
          if unsafe { imgui_begin_popup_modal("MyModal") } != 0 {
            unsafe { imgui_text("XIOM ImGui Demo v0.48.7"); };
            unsafe { imgui_separator(); };
            unsafe { imgui_text_wrapped("Dear ImGui v1.92.9 on XIOM with Vulkan backend. 70+ widget functions. 3D viewport rendering orbiting cubes behind ImGui panels."); };
            unsafe { imgui_separator(); };
            if unsafe { imgui_button("Close") } != 0 { unsafe { imgui_close_current_popup(); }; }
            unsafe { imgui_end_popup_modal(); };
          }

          let cb = unsafe { xvk_get_command_buffer(a) };
          unsafe { imgui_bridge_render(cb); };
          end_frame(a);
        } elif status == -1 {
          io.println("ERROR: " + last_error()); break;
        }
      }

      unsafe { imgui_bridge_shutdown(); };
      destroy_app(a);
      return 0;
    }
  }
}
