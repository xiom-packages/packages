// ===========================================================================
// XIOM Vulkan SDK -- Example 04: Procedural Textures
// Shows: proc_texture_solid, proc_texture_gradient, texture_create,
//        texture_get_image_view, texture_get_sampler, draw_texture_quad
// ===========================================================================

module demo_textures
use xiom.io;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("04 -- Procedural Textures", 800, 600);
  match app {
    Err(e) => { io.println(e); return 1; }
    Ok(a) => {
      // Create procedural textures (no file loading needed)
      let solid_tex = proc_texture_solid(256, 256, 0.2, 0.6, 0.9);
      let grad_tex  = proc_texture_gradient(256, 256, 1.0, 0.2, 0.2, 0.2, 0.2, 1.0, 1);

      var show_solid: Bool = true;
      while !should_close(a) {
        if is_key_down(a, 256) { break; }
        unsafe { if xvk_get_key(a, 32) != 0 { show_solid = !show_solid; } };  // Space toggles
        poll(a);
        set_clear_color(a, 0.05, 0.05, 0.10);
        let status = begin_frame(a);
        if status == 1 {
          // Draw a textured quad using the selected texture
          if show_solid {
            match solid_tex {
              Ok(tex) => { draw_texture_quad(a, tex, 0, 0.0, 0.0, 0.4, 0.4); }
              _ => {}
            }
          } else {
            match grad_tex {
              Ok(tex) => { draw_texture_quad(a, tex, 0, 0.0, 0.0, 0.4, 0.4); }
              _ => {}
            }
          }
          // Also draw a colored triangle behind
          draw_triangle_2d(a, 0.1, 0.3, 0.6);
          end_frame(a);
        } elif status == -1 { break; }
      }
      destroy_app(a);
    }
  }
  return 0;
}
