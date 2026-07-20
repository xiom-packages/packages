module glfw_test
use xiom.glwf;

fn main() -> Int {
  if !init() { return 1; }
  let win = glfw_create_window("GLFW Test", 400, 300);
  match win {
    Err(e) => { return 1; }
    Ok(w) => {
      while !glfw_should_close(w) {
        glfw_poll_events();
        if glfw_get_key(w, 256) == true { break; }
      }
      glfw_destroy_window(w);
    }
  }
  glfw_terminate();
  return 0;
}
