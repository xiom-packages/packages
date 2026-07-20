// XIOM — ImGui Production Demo (v0.48.9, Ecosystem v2)
// Fluid layout relative to framebuffer. F11 fullscreen, drag resize, Escape to close.
// Uses safe wrappers with contracts throughout. 3D scene behind ImGui panels.
// Production fixes: DisplaySize timing, NewFrame order, edge-triggered F11,
// io.DeltaTime, radio-button state machine, CG-01 workarounds.

module imgui_demo
use xiom.io;
use xiom.vulkan;
use xiom.imgui;

var g_app: Int = 0;
var g_s_f: Float32 = 0.0;
var g_s_i: Int32 = 32;
var g_c1: Int32 = TRUE_I32;
var g_c2: Int32 = FALSE_I32;
var g_c3: Int32 = FALSE_I32;
var g_drag_f: Float32 = 0.0;
var g_drag_i: Int32 = 50;
var g_cr: Float32 = 0.18;
var g_cg: Float32 = 0.64;
var g_cb: Float32 = 0.88;
var g_radio: Int32 = 0;
var g_progress: Float32 = 0.0;
var g_show_modal: Int32 = FALSE_I32;
var g_frame: Int32 = 0;
var g_theme: Int32 = 0;
var g_time: Float32 = 0.0;
var g_f11_prev: Int32 = FALSE_I32;

fn apply_theme(theme: Int32) {
  if theme == 0 { style_dark(); }
  elif theme == 1 { style_light(); }
  else { style_classic(); }
}

fn draw_3d_scene(app: Int, time: Float32, fb_w: Int32, fb_h: Int32) {
  // C-side aspect ratio computation avoids CG-01 (Int32→Float32 cast bug)
  unsafe { xvk_camera_set_aspect_from_fb(fb_w, fb_h); };
  unsafe { xvk_camera_orbit(0.008, 0.0, 0.0); };

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
  let app = create_app("XIOM ImGui Demo", 1280, 800);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      g_app = a;

      let win  = unsafe { xvk_get_glfw_window(a) };
      let inst = unsafe { xvk_get_instance(a) };
      let dev  = unsafe { xvk_get_device(a) };
      let phys = unsafe { xvk_get_physical_device(a) };
      let q    = unsafe { xvk_get_graphics_queue(a) };
      let rp   = unsafe { xvk_get_render_pass(a) };

      if !create_context(win) { destroy_app(a); return 1; }
      if !init_vulkan(inst, dev, phys, q, 0, rp, 0, 1280.0, 800.0) {
        destroy_context(); destroy_app(a); return 1;
      }

      while !should_close(a) && g_frame < 100000 {
        if is_key_down(a, 256) { break; }

        // F11 fullscreen — edge-triggered, not level-triggered
        let f11_now: Int32 = if is_key_down(a, 292) { TRUE_I32 } else { FALSE_I32 };
        if f11_now != FALSE_I32 && g_f11_prev == FALSE_I32 {
          unsafe { xvk_app_toggle_fullscreen(a); };
        }
        g_f11_prev = f11_now;

        poll(a);
        set_clear_color(a, 0.05, 0.05, 0.09);
        let status = begin_frame(a);
        if status == 1 {
          g_frame = g_frame + 1;

          let fb_w: Int32 = unsafe { xvk_get_fb_width(a) } as Int32;
          let fb_h: Int32 = unsafe { xvk_get_fb_height(a) } as Int32;

          // 3D scene + ImGui frame
          draw_3d_scene(a, g_time, fb_w, fb_h);
          new_frame_sized(fb_w, fb_h);

          // Fluid layout
          let pad: Int32 = 8;
          let sbh: Int32 = 30;
          let third: Int32 = (fb_w - pad * 4) / 3;
          let content_h: Int32 = fb_h - sbh - 32;

          // ── MENU BAR ──
          if begin_main_menu_bar() {
            if begin_menu("File") {
              if menu_item("Exit") { break; }
              end_menu();
            }
            if begin_menu("Theme") {
              if menu_item("Dark")    { g_theme = 0; apply_theme(0); }
              if menu_item("Light")   { g_theme = 1; apply_theme(1); }
              if menu_item("Classic") { g_theme = 2; apply_theme(2); }
              end_menu();
            }
            end_main_menu_bar();
          }

          // ── WIDGETS PANEL (left) ──
          set_next_window_pos(pad, 20);
          set_next_window_size(third, content_h);
          if begin_window("Widgets", FLAGS_NONE) {
            g_s_f = slider_float("Float", g_s_f, 0.0, 1.0);
            g_s_i = slider_int("Int %", g_s_i, 0, 100);
            separator();
            g_c1 = if checkbox("Feature A", g_c1 != FALSE_I32) { TRUE_I32 } else { FALSE_I32 };
            g_c2 = if checkbox("Feature B", g_c2 != FALSE_I32) { TRUE_I32 } else { FALSE_I32 };
            g_c3 = if checkbox("Feature C", g_c3 != FALSE_I32) { TRUE_I32 } else { FALSE_I32 };
            separator();
            // Radio buttons — only update state on click, never overwrite
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
            if button("Open Modal") { g_show_modal = TRUE_I32; }
            end_window();
          }

          // ── BROWSER (center) ──
          let bx: Int32 = pad * 2 + third;
          set_next_window_pos(bx, 20);
          set_next_window_size(third, content_h);
          if begin_window("Browser", FLAGS_NONE) {
            if collapsing_header("Meshes") {
              if tree_node("Cube") {
                text("24 vertices"); text("36 indices");
                text_wrapped("Simple cube mesh with per-face normals.");
                tree_pop();
              }
              if tree_node("Sphere") {
                text("128 vertices"); text("224 indices");
                tree_pop();
              }
              if tree_node("Teapot") {
                text("1,024 vertices");
                text_wrapped("Classic Utah teapot model.");
                tree_pop();
              }
            }
            if collapsing_header("Textures") {
              if tree_node("Diffuse")    { text("albedo.png"); tree_pop(); }
              if tree_node("Normal")     { text("normal.png"); tree_pop(); }
              if tree_node("Roughness")  { text("rough.png"); tree_pop(); }
            }
            if collapsing_header("Shaders") {
              if tree_node("PBR") {
                text_wrapped("Cook-Torrance BRDF with GGX distribution.");
                tree_pop();
              }
              if tree_node("Skybox") { text("procedural"); tree_pop(); }
            }
            end_window();
          }

          // ── PERFORMANCE (right, top) ──
          let tx: Int32 = pad * 3 + third * 2;
          set_next_window_pos(tx, 20);
          set_next_window_size(third, (fb_h / 2 - 16));
          if begin_window("Performance", FLAGS_NONE) {
            let fps: Int32 = get_framerate();
            if fps >= 55 { text_colored(0.2, 1.0, 0.3, 1.0, "  GOOD"); }
            elif fps >= 30 { text_colored(1.0, 0.9, 0.2, 1.0, "  OK"); }
            else { text_colored(1.0, 0.2, 0.2, 1.0, "  SLOW"); }
            separator();
            text("Runtime: XIOM v0.48.9");
            text("Backend: GLFW + Vulkan 1.3");
            text("3D: 4 cubes orbiting");
            separator();
            text_wrapped("F11 fullscreen | drag resize | Escape or File>Exit");
            end_window();
          }

          // ── SETTINGS (right, bottom) ──
          set_next_window_pos(tx, (fb_h / 2 + 4));
          set_next_window_size(third, (fb_h / 2 - 50));
          if begin_window("Settings", FLAGS_NONE) {
            if begin_tab_bar("Tabs") {
              if begin_tab_item("Render") {
                g_c1 = if checkbox("Wireframe", g_c1 != FALSE_I32) { TRUE_I32 } else { FALSE_I32 };
                g_c2 = if checkbox("Shadows",  g_c2 != FALSE_I32) { TRUE_I32 } else { FALSE_I32 };
                g_c3 = if checkbox("Post-FX",  g_c3 != FALSE_I32) { TRUE_I32 } else { FALSE_I32 };
                end_tab_item();
              }
              if begin_tab_item("Audio") {
                g_s_f = slider_float("Master", g_s_f, 0.0, 1.0);
                end_tab_item();
              }
              if begin_tab_item("About") {
                text_wrapped("XIOM ImGui Demo — Dear ImGui v1.92.9 with Vulkan backend. 85+ wrapped functions with contracts. 3D viewport with orbiting cubes.");
                end_tab_item();
              }
              end_tab_bar();
            }
            end_window();
          }

          // ── STATUS BAR ──
          set_next_window_pos(0, fb_h - sbh);
          set_next_window_size(fb_w, sbh);
          if begin_window("##Status", FLAGS_NONE) {
            let fps: Int32 = get_framerate();
            if fps >= 55 { text_colored(0.2, 1.0, 0.3, 1.0, "FPS: "); }
            elif fps >= 30 { text_colored(1.0, 0.9, 0.2, 1.0, "FPS: "); }
            else { text_colored(1.0, 0.2, 0.2, 1.0, "FPS: "); }
            unsafe { imgui_same_line(36.0, 0.0); };
            text("| XIOM v0.48.9 | ImGui v1.92.9 | ");  // FIXED
            unsafe { imgui_same_line(0.0, 0.0); };
            text_colored(g_cr, g_cg, g_cb, 1.0, "accent");
            end_window();
          }

          // ── MODAL ──
          if g_show_modal != FALSE_I32 {
            open_popup("MyModal"); g_show_modal = FALSE_I32;
          }
          if begin_popup_modal("MyModal") {
            text("XIOM ImGui Demo v0.48.9");
            separator();
            text_wrapped("Dear ImGui v1.92.9 on XIOM with Vulkan backend. 85+ wrapped functions with design-by-contract. 3D viewport rendering orbiting cubes behind ImGui panels.");
            separator();
            if button("Close") { close_current_popup(); }
            end_popup_modal();
          }

          let cb = unsafe { xvk_get_command_buffer(a) };
          render(cb);
          end_frame(a);
        } elif status == -1 {
          io.println("ERROR: " + last_error()); break;
        }
      }

      destroy_context();
      destroy_app(a);
      return 0;
    }
  }
}
