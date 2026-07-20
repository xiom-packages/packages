// ===========================================================================
// XIOM Vulkan SDK — Example 02: 3D Cube + Camera
// Shows: draw_cube_3d, camera_orbit, set_clear_color, toggle_fullscreen (F11)
// ===========================================================================

module demo_3d_cube
use xiom.io;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("02 — 3D Cube + Camera", 1024, 768);
  match app {
    Err(e) => { return 1; }
    Ok(a) => {
      var angle: Float32 = 0.0;
      while !should_close(a) {
        if is_key_down(a, 256) { break; }                             // Escape
        if is_key_down(a, 292) != 0 { unsafe { xvk_app_toggle_fullscreen(a); }; }  // F11
        poll(a);
        set_clear_color(a, 0.04, 0.04, 0.12);

        let status = begin_frame(a);
        if status == 1 {
          // Orbit camera slowly around origin
          unsafe { xvk_camera_orbit(a, 0.01, 0.0, 0.0); };
          let fb_w = unsafe { xvk_get_fb_width(a) };
          let fb_h = unsafe { xvk_get_fb_height(a) };
          unsafe { xvk_camera_set_aspect_from_fb(a, fb_w, fb_h); };

          // Main rotating cube
          draw_cube_3d(a, angle);

          // Orbiting satellite
          let s_angle = angle * 1.5;
          let sx: Float32 = 1.3 * unsafe { xvk_cos(s_angle) };
          let sz: Float32 = 1.3 * unsafe { xvk_sin(s_angle) };
          unsafe { xvk_draw_cube_3d_at(a, s_angle * 0.5, sx, 0.0, sz, 0.12); };

          angle = angle + 0.02;
          end_frame(a);
        } elif status == -1 { break; }
      }
      destroy_app(a);
      return 0;
    }
  }
}
