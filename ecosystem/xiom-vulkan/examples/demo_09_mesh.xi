// ===========================================================================
// XIOM Vulkan SDK — Example 09: Mesh Loading (OBJ)
// Shows: mesh_load, mesh_draw, mesh_vertex_count, mesh_index_count,
//        camera_orbit, camera_set_aspect_from_fb
// NOTE: Requires an OBJ file — falls back to cube rendering if not found
// ===========================================================================

module demo_mesh
use xiom.io;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("09 — Mesh Loading", 1024, 768);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      // Try common OBJ paths — fall back gracefully
      var mesh: Int = 0;
      let obj_paths = ["cube.obj", "teapot.obj", "suzanne.obj",
                       "..\\resources\\cube.obj", "..\\resources\\teapot.obj"];
      for p in obj_paths {
        let m = mesh_load(a, p);
        match m {
          Ok(handle) => { mesh = handle; io.println("Mesh loaded"); break; }
          _ => {}
        }
      }

      var angle: Float32 = 0.0;
      while !should_close(a) {
        if is_key_down(a, 256) { break; }
        poll(a);
        set_clear_color(a, 0.04, 0.04, 0.12);
        let status = begin_frame(a);
        if status == 1 {
          let fb_w = unsafe { xvk_get_fb_width(a) };
          let fb_h = unsafe { xvk_get_fb_height(a) };
          camera_set_aspect_from_fb(a, fb_w, fb_h);
          camera_orbit(a, 0.01, 0.0, 0.0);

          if mesh != 0 {
            // Draw loaded mesh
            mesh_draw(a, mesh, angle, 0.0, 0.0, 0.0, 0.5);
          } else {
            // Fallback: draw cubes
            draw_cube_3d(a, angle);
            draw_cube_3d_at(a, angle * 1.5, 1.0, 0.0, 0.0, 0.15);
            draw_cube_3d_at(a, angle * 0.7, -1.0, 0.3, 0.5, 0.12);
          }

          angle = angle + 0.02;
          end_frame(a);
        } elif status == -1 { break; }
      }

      if mesh != 0 { mesh_destroy(a, mesh); };
      destroy_app(a);
    }
  }
  return 0;
}
