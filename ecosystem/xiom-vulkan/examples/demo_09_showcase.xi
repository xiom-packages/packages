// ===========================================================================
// XIOM Vulkan SDK — Example 09: Full API Showcase (All-in-One)
// Demonstrates every available safe wrapper in a single program.
// ===========================================================================

module demo_showcase
use xiom.io;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("09 — Full SDK Showcase", 1024, 768);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      // Lifecycle: get device info
      io.println("Device type: "); io.println(" ");  // SKIP: not printable
      io.println("App valid: true");

      // Offscreen: render + verify
      let off = offscreen_create(32, 32);
      match off {
        Ok(oa) => {
          let ok = offscreen_render_triangle(oa, 0.8, 0.2, 0.2);
          if ok { io.println("Offscreen: OK"); }
          offscreen_destroy(oa);
        }
        _ => { io.println("Offscreen: unavailable (headless?)"); }
      }

      // Particles
      particles_enable(a, 1000);

      // Window render loop
      var angle: Float32 = 0.0;
      while !should_close(a) {
        if is_key_down(a, 256) { break; }
        if is_key_down(a, 292) != 0 { app_toggle_fullscreen(a); }
        poll(a);
        set_clear_color(a, 0.04, 0.04, 0.12);
        let status = begin_frame(a);
        if status == 1 {
          let fb_w = unsafe { xvk_get_fb_width(a) };
          let fb_h = unsafe { xvk_get_fb_height(a) };
          camera_set_aspect_from_fb(a, fb_w, fb_h);
          camera_orbit(a, 0.008, 0.0, 0.0);

          // 2D triangle
          draw_triangle_2d(a, 0.9, 0.2, 0.3);

          // 3D cube
          draw_cube_3d(a, angle);

          // Positioned cubes (satellites)
          let s1 = angle * 1.5;
          draw_cube_3d_at(a, s1 * 0.5, cos(s1) * 1.3, 0.0, sin(s1) * 1.3, 0.12);
          draw_cube_3d_at(a, s1 * 0.7 + 2.0, cos(s1 + 2.0) * 1.6, -0.2, sin(s1 + 2.0) * 1.6, 0.10);

          // Quad
          draw_quad_2d(a, 0.7, 0.8, 0.05, 0.05, 0.2, 1.0, 0.3);

          // Particles
          draw_particles(a, 0.016);

          angle = angle + 0.02;
          end_frame(a);
        } elif status == -1 { break; }
      }
      destroy_app(a);
    }
  }
  return 0;
}
