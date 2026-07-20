// ===========================================================================
// XIOM GLFW SDK — Example 01: Window Lifecycle
// Shows: glfw_init, glfw_create_window, glfw_should_close, glfw_destroy_window
// ===========================================================================

module glfw_window
use xiom.io;
use xiom.glwf;

fn main() -> Int {
  io.println("GLFW Window Lifecycle Demo");

  if !glfw_init() {
    io.println("ERROR: glfw_init failed");
    return 1;
  }

  let win = glfw_create_window("GLFW — Window Demo", 800, 600);
  match win {
    Err(e) => { io.println("ERROR: " + e); glfw_terminate(); return 1; }
    Ok(w) => {
      io.println("Window created. Press Escape to close.");

      var frames: Int = 0;
      while !glfw_should_close(w) {
        glfw_poll_events();
        if glfw_get_key(w, 256) { break; }  // Escape

        frames = frames + 1;
        if frames % 60 == 0 {
          let (fw, fh) = glfw_get_framebuffer_size(w);
          io.println("Frame " + "" + " — " + "" + "x" + "");
        }
      }

      glfw_destroy_window(w);
      io.println("Window closed after rendering normally.");
    }
  }

  glfw_terminate();
  return 0;
}
