module xiom.ui.widgets

pub type ButtonState = {
  pressed: Bool;
  hovered: Bool;
  id: Int;
}

pub type CheckboxState = {
  checked: Bool;
  id: Int;
}

pub type TextFieldState = {
  text: Str;
  cursor: Int;
  focused: Bool;
  id: Int;
}

pub type SliderState = {
  value: Float32;
  min: Float32;
  max: Float32;
  dragging: Bool;
  id: Int;
}

pub type DropdownState = {
  open: Bool;
  selected: Int;
  options: Vec[Str];
  id: Int;
}

pub type PanelState = {
  scroll_x: Float32;
  scroll_y: Float32;
  id: Int;
}

pub type TabsState = {
  active_tab: Int;
  tabs: Vec[Str];
  id: Int;
}

pub type LabelState = {
  id: Int;
}

pub type SeparatorState = {
  id: Int;
}

pub fn ButtonState.new(id: Int) -> ButtonState {
  return ButtonState{ pressed: false, hovered: false, id: id };
}

pub fn ButtonState.is_pressed() -> Bool {
  return pressed;
}

pub fn ButtonState.is_hovered() -> Bool {
  return hovered;
}

pub fn CheckboxState.new(id: Int) -> CheckboxState {
  return CheckboxState{ checked: false, id: id };
}

pub fn CheckboxState.toggle() {
  checked = !checked;
}

pub fn TextFieldState.new(id: Int) -> TextFieldState {
  return TextFieldState{ text: "", cursor: 0, focused: false, id: id };
}

pub fn TextFieldState.insert(c: Str) {
  var left = text_substr(text, 0, cursor);
  var right = text_substr(text, cursor, text.len());
  text = left + c + right;
  cursor = cursor + 1;
}

pub fn TextFieldState.backspace() {
  if cursor > 0 && text.len() > 0 {
    var left = text_substr(text, 0, cursor - 1);
    var right = text_substr(text, cursor, text.len());
    text = left + right;
    cursor = cursor - 1;
  }
}

pub fn TextFieldState.delete() {
  if cursor < text.len() {
    var left = text_substr(text, 0, cursor);
    var right = text_substr(text, cursor + 1, text.len());
    text = left + right;
  }
}

pub fn TextFieldState.clear() {
  text = "";
  cursor = 0;
}

pub fn TextFieldState.move_cursor_left() {
  if cursor > 0 {
    cursor = cursor - 1;
  }
}

pub fn TextFieldState.move_cursor_right() {
  if cursor < text.len() {
    cursor = cursor + 1;
  }
}

pub fn TextFieldState.move_cursor_home() {
  cursor = 0;
}

pub fn TextFieldState.move_cursor_end() {
  cursor = text.len();
}

pub fn SliderState.new(id: Int, min: Float32, max: Float32, initial: Float32) -> SliderState {
  return SliderState{ value: initial, min: min, max: max, dragging: false, id: id };
}

pub fn SliderState.set_value(v: Float32) {
  if v < min { value = min; }
  elif v > max { value = max; }
  else { value = v; }
}

pub fn SliderState.normalized() -> Float32 {
  if max == min { return 0.0; }
  return (value - min) / (max - min);
}

pub fn DropdownState.new(id: Int) -> DropdownState {
  return DropdownState{
    open: false,
    selected: -1,
    options: Vec[Str].new(),
    id: id,
  };
}

pub fn DropdownState.set_options(opts: Vec[Str]) {
  options = opts;
}

pub fn DropdownState.toggle() {
  open = !open;
}

pub fn DropdownState.select(idx: Int) {
  if idx >= 0 && idx < options.len() {
    selected = idx;
  }
  open = false;
}

pub fn DropdownState.selected_text() -> Str {
  if selected >= 0 && selected < options.len() {
    return options[selected];
  }
  return "";
}

pub fn PanelState.new(id: Int) -> PanelState {
  return PanelState{ scroll_x: 0.0, scroll_y: 0.0, id: id };
}

pub fn PanelState.scroll(dx: Float32, dy: Float32) {
  scroll_x = scroll_x + dx;
  scroll_y = scroll_y + dy;
}

pub fn TabsState.new(id: Int) -> TabsState {
  return TabsState{ active_tab: 0, tabs: Vec[Str].new(), id: id };
}

pub fn TabsState.set_tabs(t: Vec[Str]) {
  tabs = t;
  if active_tab >= tabs.len() {
    active_tab = 0;
  }
}

pub fn TabsState.select_tab(idx: Int) {
  if idx >= 0 && idx < tabs.len() {
    active_tab = idx;
  }
}

pub fn TabsState.next_tab() {
  if tabs.len() > 0 {
    active_tab = (active_tab + 1) % tabs.len();
  }
}

pub fn TabsState.prev_tab() {
  if tabs.len() > 0 {
    active_tab = active_tab - 1;
    if active_tab < 0 {
      active_tab = tabs.len() - 1;
    }
  }
}

fn text_substr(s: Str, start: Int, end: Int) -> Str {
  if start < 0 { start = 0; }
  if end > s.len() { end = s.len(); }
  if start >= end { return ""; }
  var result = "";
  var i = start;
  while i < end {
    result = result + byte_to_str(s[i]);
    i = i + 1;
  }
  return result;
}

fn byte_to_str(b: Int) -> Str {
  if b == 0 { return "\0"; }
  if b == 32 { return " "; }
  if b == 33 { return "!"; }
  if b == 34 { return "\""; }
  if b == 35 { return "#"; }
  if b == 36 { return "$"; }
  if b == 37 { return "%"; }
  if b == 38 { return "&"; }
  if b == 39 { return "'"; }
  if b == 40 { return "("; }
  if b == 41 { return ")"; }
  if b == 42 { return "*"; }
  if b == 43 { return "+"; }
  if b == 44 { return ","; }
  if b == 45 { return "-"; }
  if b == 46 { return "."; }
  if b == 47 { return "/"; }
  if b == 48 { return "0"; }
  if b == 49 { return "1"; }
  if b == 50 { return "2"; }
  if b == 51 { return "3"; }
  if b == 52 { return "4"; }
  if b == 53 { return "5"; }
  if b == 54 { return "6"; }
  if b == 55 { return "7"; }
  if b == 56 { return "8"; }
  if b == 57 { return "9"; }
  if b == 58 { return ":"; }
  if b == 59 { return ";"; }
  if b == 60 { return "<"; }
  if b == 61 { return "="; }
  if b == 62 { return ">"; }
  if b == 63 { return "?"; }
  if b == 64 { return "@"; }
  if b >= 65 && b <= 90 {
    if b == 65 { return "A"; }
    if b == 66 { return "B"; }
    if b == 67 { return "C"; }
    if b == 68 { return "D"; }
    if b == 69 { return "E"; }
    if b == 70 { return "F"; }
    if b == 71 { return "G"; }
    if b == 72 { return "H"; }
    if b == 73 { return "I"; }
    if b == 74 { return "J"; }
    if b == 75 { return "K"; }
    if b == 76 { return "L"; }
    if b == 77 { return "M"; }
    if b == 78 { return "N"; }
    if b == 79 { return "O"; }
    if b == 80 { return "P"; }
    if b == 81 { return "Q"; }
    if b == 82 { return "R"; }
    if b == 83 { return "S"; }
    if b == 84 { return "T"; }
    if b == 85 { return "U"; }
    if b == 86 { return "V"; }
    if b == 87 { return "W"; }
    if b == 88 { return "X"; }
    if b == 89 { return "Y"; }
    if b == 90 { return "Z"; }
  }
  if b >= 97 && b <= 122 {
    if b == 97 { return "a"; }
    if b == 98 { return "b"; }
    if b == 99 { return "c"; }
    if b == 100 { return "d"; }
    if b == 101 { return "e"; }
    if b == 102 { return "f"; }
    if b == 103 { return "g"; }
    if b == 104 { return "h"; }
    if b == 105 { return "i"; }
    if b == 106 { return "j"; }
    if b == 107 { return "k"; }
    if b == 108 { return "l"; }
    if b == 109 { return "m"; }
    if b == 110 { return "n"; }
    if b == 111 { return "o"; }
    if b == 112 { return "p"; }
    if b == 113 { return "q"; }
    if b == 114 { return "r"; }
    if b == 115 { return "s"; }
    if b == 116 { return "t"; }
    if b == 117 { return "u"; }
    if b == 118 { return "v"; }
    if b == 119 { return "w"; }
    if b == 120 { return "x"; }
    if b == 121 { return "y"; }
    if b == 122 { return "z"; }
  }
  return "?";
}
