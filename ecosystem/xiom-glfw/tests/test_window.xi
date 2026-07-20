module glfw_test
use xiom.glwf;

fn main() -> Int {
  if !init() { return 1; }
  let win = create_window("GLFW Test", 400, 300);
  match win {
    Err(e) => { return 1; }
    Ok(w) => {
      while !should_close(w) {
        poll_events();
        if get_key(w, 256) == true { break; }
      }
      destroy_window(w);
    }
  }
  terminate();
  return 0;
}
