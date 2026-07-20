module minimal_test
use xiom.vulkan;

fn main() -> Int {
  let app = create_app("Minimal Test", 800, 600);
  match app {
    Err(e) => { return 1; }
    Ok(a) => {
      var done: Bool = false;
      while !done && !should_close(a) {
        poll(a);
        set_clear_color(a, 0.1, 0.1, 0.2);
        let status = begin_frame(a);
        if status == 1 {
          end_frame(a);
        } elif status == -1 {
          return 1;
        }
      }
      destroy_app(a);
      return 0;
    }
  }
}
