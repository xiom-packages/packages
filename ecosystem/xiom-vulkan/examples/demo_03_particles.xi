// ===========================================================================
// XIOM Vulkan SDK — Example 03: Particle Fountain
// Shows: particles_enable, particles_update, draw_particles, delta time
// ===========================================================================

module demo_particles
use xiom.io;
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("03 — Particles", 800, 600);
  match app {
    Err(e) => { return 1; }
    Ok(a) => {
      unsafe { xvk_particles_enable(a, 3000); };
      while !should_close(a) {
        if is_key_down(a, 256) { break; }
        poll(a);
        set_clear_color(a, 0.02, 0.02, 0.06);
        let status = begin_frame(a);
        if status == 1 {
          draw_particles(a, 0.016);  // dt controls spread speed
          end_frame(a);
        } elif status == -1 { break; }
      }
      destroy_app(a);
      return 0;
    }
  }
}
