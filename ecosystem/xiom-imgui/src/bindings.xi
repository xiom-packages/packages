module xiom.imgui

fn ig_create_context() -> Result[Unit, Str]
{
  create_context()
}

fn ig_destroy_context()
{
  destroy_context();
}

fn ig_new_frame()
{
  new_frame();
}

fn ig_render()
{
  render();
}

fn ig_begin(name: Str) -> Bool
  requires: name.len() > 0
{
  let mut open = true;
  begin_window(name, &mut open, 0)
}

fn ig_end()
{
  end_window();
}

fn ig_button(label: Str) -> Bool
  requires: label.len() > 0
{
  button(label, 0.0, 0.0)
}

fn ig_text(text: Str)
{
  text(text);
}

fn ig_slider_float(label: Str, value: Float32, min: Float32, max: Float32) -> Float32
  requires: label.len() > 0
  requires: min <= max
{
  let mut v = value;
  slider_float(label, &mut v, min, max);
  v
}

fn ig_checkbox(label: Str, checked: Bool) -> Bool
  requires: label.len() > 0
{
  let mut v = checked;
  checkbox(label, &mut v);
  v
}

fn ig_input_text(label: Str, text: Str) -> Str
  requires: label.len() > 0
{
  let mut buffer = text.clone();
  input_text(label, &mut buffer, 256);
  buffer
}

fn ig_slider_int(label: Str, value: Int, min: Int, max: Int) -> Int
  requires: label.len() > 0
  requires: min <= max
{
  let mut v = value;
  slider_int(label, &mut v, min, max);
  v
}

fn ig_input_float(label: Str, value: Float32) -> Float32
  requires: label.len() > 0
{
  let mut v = value;
  input_float(label, &mut v);
  v
}

fn ig_input_int(label: Str, value: Int) -> Int
  requires: label.len() > 0
{
  let mut v = value;
  input_int(label, &mut v);
  v
}

fn ig_text_colored(r: Float32, g: Float32, b: Float32, a: Float32, text: Str)
{
  text_colored(r, g, b, a, text);
}

fn ig_begin_child(id: Str, width: Float32, height: Float32) -> Bool
{
  begin_child(id, width, height)
}

fn ig_end_child()
{
  end_child();
}

fn ig_separator()
{
  separator();
}

fn ig_same_line(offset: Float32, spacing: Float32)
{
  same_line(offset, spacing);
}

fn ig_spacing()
{
  spacing();
}

fn ig_tree_node(label: Str) -> Bool
  requires: label.len() > 0
{
  tree_node(label)
}

fn ig_tree_pop()
{
  tree_pop();
}

fn ig_collapsing_header(label: Str) -> Bool
  requires: label.len() > 0
{
  collapsing_header(label)
}

fn ig_plot_lines(label: Str, values: &Vec[Float32], scale_min: Float32, scale_max: Float32)
{
  plot_lines(label, values, scale_min, scale_max);
}

fn ig_plot_histogram(label: Str, values: &Vec[Float32], scale_min: Float32, scale_max: Float32)
{
  plot_histogram(label, values, scale_min, scale_max);
}

fn ig_open_popup(name: Str)
  requires: name.len() > 0
{
  open_popup(name);
}

fn ig_begin_popup(name: Str) -> Bool
  requires: name.len() > 0
{
  begin_popup(name)
}

fn ig_end_popup()
{
  end_popup();
}

fn ig_begin_modal(name: Str) -> Bool
  requires: name.len() > 0
{
  let mut open = true;
  begin_modal(name, &mut open)
}

fn ig_end_modal()
{
  end_modal();
}

fn ig_combo(label: Str, current: Int, items: &Vec[Str]) -> Int
  requires: label.len() > 0
{
  let mut cur = current;
  combo(label, &mut cur, items.clone());
  cur
}

fn ig_style_dark()
{
  style_dark();
}

fn ig_style_light()
{
  style_light();
}

fn ig_style_classic()
{
  style_classic();
}

fn ig_init_for_vulkan(window: Int) -> Result[Unit, Str]
{
  init_for_vulkan(window)
}

fn ig_init_for_opengl(window: Int) -> Result[Unit, Str]
{
  init_for_opengl(window)
}

fn ig_shutdown_backend()
{
  shutdown_backend();
}

fn ig_render_vulkan(draw_data: Int, cmd_buffer: Int, pipeline: Int)
{
  render_vulkan(draw_data, cmd_buffer, pipeline);
}
