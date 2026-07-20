// ===========================================================================
// XIOM GLFW SDK — Example 03: Monitors + Fullscreen
// Shows: glfw_get_primary_monitor, glfw_get_video_mode, glfw_toggle_fullscreen
// Press F to toggle fullscreen, M to print monitor info.
// ===========================================================================

module glfw_monitor
use xiom.io;
use xiom.glwf;

fn main() -> Int {
  if !glfw_init() { return 1; }
  let win = glfw_create_window("GLFW — Monitor Demo", 800, 600);
  match win {
    Err(e) => { io.println(e); glfw_terminate(); return 1; }
    Ok(w) => {
      // Print monitor info
      let mon = glfw_get_primary_monitor();
      let (mw, mh, mref) = glfw_get_video_mode(mon);
      io.println("Primary monitor: " + "" + "x" + "" + " @" + "" + "Hz");
      io.println("Press F for fullscreen, M for monitor info, Esc to exit.");

      var f_pressed: Int = 0;
      while !glfw_should_close(w) {
        glfw_poll_events();
        if glfw_get_key(w, 256) { break; }

        // F key: toggle fullscreen (edge-triggered)
        let f_now = if glfw_get_key(w, 70) { 1 } else { 0 };
        if f_now != 0 && f_pressed == 0 {
          glfw_toggle_fullscreen(w);
          let (fw, fh) = glfw_get_framebuffer_size(w);
          io.println("Fullscreen toggled. Framebuffer: " + "" + "x" + "");
        }
        f_pressed = f_now;

        // M key: print monitor info
        if glfw_get_key(w, 77) {
          let mon2 = glfw_get_primary_monitor();
          let (w2, h2, r2) = glfw_get_video_mode(mon2);
          io.println("Monitor: " + "" + "x" + "" + "@" + "" + "Hz");
        }
      }

      glfw_destroy_window(w);
    }
  }
  glfw_terminate();
  return 0;
}
