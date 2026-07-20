module glfw_test
use xiom.glwf;

fn main() -> Int {
  if !xiom.glwf.glfw_init() { return 1; }
  let win = xiom.glwf.glfw_create_window("GLFW Test", 400, 300);
  match win {
    Err(e) => { return 1; }
    Ok(w) => {
      while !xiom.glwf.glfw_should_close(w) {
        xiom.glwf.glfw_poll_events();
        if xiom.glwf.glfw_get_key(w, 256) { break; }
      }
      xiom.glwf.glfw_destroy_window(w);
    }
  }
  xiom.glwf.glfw_terminate();
  return 0;
}
