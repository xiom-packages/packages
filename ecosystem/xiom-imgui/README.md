# xiom:imgui — Dear ImGui Bindings

Immediate mode GUI for XIOM via Dear ImGui (cimgui C wrapper).

## Example
```xiom
use xiom.glfw;
use xiom.imgui;

fn main() -> Int {
  glfw.init()?;
  let window = glfw.create_window(800, 600, "XIOM ImGui")?;
  imgui.create_context()?;
  imgui.init_for_vulkan(window)?;
  imgui.style_dark();
  
  var show = true;
  var value: Float32 = 0.5;
  
  while !glfw.should_close(window) {
    glfw.poll_events();
    imgui.new_frame();
    
    if imgui.begin_window("Controls", &show, 0) {
      imgui.text("Hello from XIOM!");
      imgui.slider_float("Value", &mut value, 0.0, 1.0);
      if imgui.button("Click Me", 100, 30) { value = 1.0; }
      imgui.end_window();
    }
    
    imgui.render();
    glfw.swap_buffers(window);
  }
  
  imgui.destroy_context();
  glfw.destroy_window(window);
  return 0;
}
```
