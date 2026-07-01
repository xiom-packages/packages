# axiom:glfw — Windowing & Input

GLFW 3.4 FFI bindings for AXIOM.

## Example

```axiom
use axiom.glfw;

fn main() -> Int {
  init()?;
  let window = create_window(800, 600, "AXIOM Window")?;
  
  while !should_close(window) {
    poll_events();
    if get_key(window, KEY_ESCAPE) == PRESS {
      set_should_close(window, true);
    }
  }
  
  destroy_window(window);
  terminate();
  return 0;
}
```
