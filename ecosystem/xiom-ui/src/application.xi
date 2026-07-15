module xiom.ui.application

use xiom.ui.types;
use xiom.ui.theme;
use xiom.ui.render;

pub type UIApp = {
  running: Bool;
  width: Float32;
  height: Float32;
  input: InputState;
  theme: Theme;
  render_list: RenderList;
}

pub fn UIApp.new(title: Str, w: Float32, h: Float32) -> UIApp
  requires: title.len() > 0
  requires: w > 0.0
  requires: h > 0.0 {
  return UIApp{
    running: true,
    width: w,
    height: h,
    input: InputState.new(),
    theme: theme_default(),
    render_list: RenderList.new(),
  };
}

pub fn UIApp.should_close() -> Bool {
  return !running;
}

pub fn UIApp.begin_frame() {
  render_list.clear();
  input.reset();
}

pub fn UIApp.end_frame() {
}

pub fn UIApp.run() {
  running = true;
}

pub fn UIApp.close() {
  running = false;
}

pub fn UIApp.set_theme(t: Theme) {
  theme = t;
}

pub fn UIApp.set_input(new_input: InputState) {
  input = new_input;
}

pub fn UIApp.width() -> Float32 {
  return width;
}

pub fn UIApp.height() -> Float32 {
  return height;
}

pub fn UIApp.input_state() -> &InputState {
  return &input;
}

pub fn UIApp.render_commands() -> &RenderList {
  return &render_list;
}
