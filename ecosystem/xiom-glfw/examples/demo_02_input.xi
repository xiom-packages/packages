// ===========================================================================
// XIOM GLFW SDK — Example 02: Input Events
// Shows: glfw_get_key, glfw_get_mouse_button, glfw_get_cursor_pos
// Press keys, click mouse, move cursor — all logged to console.
// ===========================================================================

module glfw_input
use xiom.io;
use xiom.glwf;

fn main() -> Int {
  if !glfw_init() { return 1; }
  let win = glfw_create_window("GLFW — Input Demo", 600, 400);
  match win {
    Err(e) => { io.println(e); glfw_terminate(); return 1; }
    Ok(w) => {
      io.println("Move mouse, click buttons, press keys. Press Esc to exit.");
      var last_key: Int = -1;
      var last_mb : Int = -1;

      while !glfw_should_close(w) {
        glfw_poll_events();
        if glfw_get_key(w, 256) { break; }

        // Keyboard
        let keys = [65, 66, 67, 68, 87, 83, 32, 290, 291];  // A,B,C,D,W,S,Space,F1,F2
        for k in keys {
          if glfw_get_key(w, k) && k != last_key {
            io.println("Key pressed: " + "");  last_key = k;
          }
        }

        // Mouse buttons
        let btns = [0, 1, 2];  // left, right, middle
        for b in btns {
          if glfw_get_mouse_button(w, b) && b != last_mb {
            io.println("Mouse button: " + "");  last_mb = b;
          }
        }
      }

      glfw_destroy_window(w);
    }
  }
  glfw_terminate();
  return 0;
}
