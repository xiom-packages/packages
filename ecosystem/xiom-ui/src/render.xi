module xiom.ui.render

pub enum RenderCommand {
  RectCmd(rect: Rect, color: Color),
  TextCmd(text: Str, pos: Point, color: Color, size: Float32),
  CircleCmd(center: Point, radius: Float32, color: Color),
  LineCmd(start: Point, end: Point, color: Color, width: Float32),
  ImageCmd(rect: Rect, image_id: Int),
  ClipCmd(rect: Rect),
}

pub type RenderList = {
  commands: Vec[RenderCommand];
}

pub fn RenderList.new() -> RenderList {
  return RenderList{ commands: Vec[RenderCommand].new() };
}

pub fn RenderList.add_rect(rect: Rect, color: Color) {
  commands.push(RenderCommand.RectCmd(rect, color));
}

pub fn RenderList.add_text(text: Str, pos: Point, color: Color) {
  commands.push(RenderCommand.TextCmd(text, pos, color, 16.0));
}

pub fn RenderList.add_text_sized(text: Str, pos: Point, color: Color, size: Float32) {
  commands.push(RenderCommand.TextCmd(text, pos, color, size));
}

pub fn RenderList.add_circle(center: Point, radius: Float32, color: Color) {
  commands.push(RenderCommand.CircleCmd(center, radius, color));
}

pub fn RenderList.add_line(start: Point, end: Point, color: Color, width: Float32) {
  commands.push(RenderCommand.LineCmd(start, end, color, width));
}

pub fn RenderList.add_image(rect: Rect, image_id: Int) {
  commands.push(RenderCommand.ImageCmd(rect, image_id));
}

pub fn RenderList.add_clip(rect: Rect) {
  commands.push(RenderCommand.ClipCmd(rect));
}

pub fn RenderList.clear() {
  commands = Vec[RenderCommand].new();
}

pub fn RenderList.command_count() -> Int {
  return commands.len();
}

pub fn RenderList.is_empty() -> Bool {
  return commands.len() == 0;
}

pub fn RenderList.get_command(idx: Int) -> Option[RenderCommand] {
  if idx < 0 || idx >= commands.len() { return None; }
  return Some(commands[idx]);
}
