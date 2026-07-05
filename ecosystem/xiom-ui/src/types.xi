module xiom.ui.types

pub type Rect = {
  x: Float32;
  y: Float32;
  w: Float32;
  h: Float32;
}

pub type Color = {
  r: Float32;
  g: Float32;
  b: Float32;
  a: Float32;
}

pub type Point = {
  x: Float32;
  y: Float32;
}

pub type Size = {
  w: Float32;
  h: Float32;
}

pub type Padding = {
  top: Float32;
  right: Float32;
  bottom: Float32;
  left: Float32;
}

pub type Margin = {
  top: Float32;
  right: Float32;
  bottom: Float32;
  left: Float32;
}

pub enum LayoutDirection {
  Horizontal,
  Vertical,
}

pub enum Alignment {
  Start,
  Center,
  End,
  Stretch,
}

pub enum TextAlign {
  Left,
  Center,
  Right,
}

pub enum MouseButton {
  Left,
  Right,
  Middle,
}

pub type InputState = {
  mouse_x: Float32;
  mouse_y: Float32;
  mouse_down: Vec[Bool];
  keys_down: Vec[Int];
  scroll: Float32;
}

pub fn Rect.new(x: Float32, y: Float32, w: Float32, h: Float32) -> Rect
  requires: w >= 0.0
  requires: h >= 0.0 {
  return Rect{ x: x, y: y, w: w, h: h };
}

pub fn Rect.zero() -> Rect {
  return Rect{ x: 0.0, y: 0.0, w: 0.0, h: 0.0 };
}

pub fn Rect.contains(point: &Point) -> Bool {
  return point.x >= x && point.x <= x + w && point.y >= y && point.y <= y + h;
}

pub fn Color.new(r: Float32, g: Float32, b: Float32, a: Float32) -> Color
  requires: r >= 0.0 && r <= 1.0
  requires: g >= 0.0 && g <= 1.0
  requires: b >= 0.0 && b <= 1.0
  requires: a >= 0.0 && a <= 1.0 {
  return Color{ r: r, g: g, b: b, a: a };
}

pub fn Point.new(x: Float32, y: Float32) -> Point {
  return Point{ x: x, y: y };
}

pub fn Point.zero() -> Point {
  return Point{ x: 0.0, y: 0.0 };
}

pub fn Size.new(w: Float32, h: Float32) -> Size
  requires: w >= 0.0
  requires: h >= 0.0 {
  return Size{ w: w, h: h };
}

pub fn Size.zero() -> Size {
  return Size{ w: 0.0, h: 0.0 };
}

pub fn Padding.new(top: Float32, right: Float32, bottom: Float32, left: Float32) -> Padding
  requires: top >= 0.0
  requires: right >= 0.0
  requires: bottom >= 0.0
  requires: left >= 0.0 {
  return Padding{ top: top, right: right, bottom: bottom, left: left };
}

pub fn Padding.all(v: Float32) -> Padding {
  return Padding{ top: v, right: v, bottom: v, left: v };
}

pub fn Padding.symmetric(h: Float32, v: Float32) -> Padding {
  return Padding{ top: v, right: h, bottom: v, left: h };
}

pub fn Margin.new(top: Float32, right: Float32, bottom: Float32, left: Float32) -> Margin
  requires: top >= 0.0
  requires: right >= 0.0
  requires: bottom >= 0.0
  requires: left >= 0.0 {
  return Margin{ top: top, right: right, bottom: bottom, left: left };
}

pub fn Margin.all(v: Float32) -> Margin {
  return Margin{ top: v, right: v, bottom: v, left: v };
}

pub fn InputState.new() -> InputState {
  return InputState{
    mouse_x: 0.0,
    mouse_y: 0.0,
    mouse_down: Vec[Bool].new(),
    keys_down: Vec[Int].new(),
    scroll: 0.0,
  };
}

pub fn InputState.reset() {
  mouse_x = 0.0;
  mouse_y = 0.0;
  scroll = 0.0;
}

pub fn InputState.is_mouse_down(button: MouseButton) -> Bool {
  var idx: Int = 0;
  match button {
    Left => idx = 0,
    Right => idx = 1,
    Middle => idx = 2,
  }
  if idx >= mouse_down.len() { return false; }
  return mouse_down[idx];
}

pub fn InputState.is_key_down(key: Int) -> Bool {
  var i: Int = 0;
  while i < keys_down.len() {
    if keys_down[i] == key { return true; }
    i = i + 1;
  }
  return false;
}

pub fn RED() -> Color { return Color{ r: 1.0, g: 0.0, b: 0.0, a: 1.0 }; }
pub fn GREEN() -> Color { return Color{ r: 0.0, g: 1.0, b: 0.0, a: 1.0 }; }
pub fn BLUE() -> Color { return Color{ r: 0.0, g: 0.0, b: 1.0, a: 1.0 }; }
pub fn WHITE() -> Color { return Color{ r: 1.0, g: 1.0, b: 1.0, a: 1.0 }; }
pub fn BLACK() -> Color { return Color{ r: 0.0, g: 0.0, b: 0.0, a: 1.0 }; }
pub fn GRAY() -> Color { return Color{ r: 0.5, g: 0.5, b: 0.5, a: 1.0 }; }
pub fn TRANSPARENT() -> Color { return Color{ r: 0.0, g: 0.0, b: 0.0, a: 0.0 }; }
