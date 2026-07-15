module xiom.ui.demo

use xiom.ui.types;
use xiom.ui.layout;
use xiom.ui.widgets;
use xiom.ui.render;
use xiom.ui.theme;
use xiom.ui.application;

pub fn demo_counter_app() -> Result[Int, Str] {
  var app = UIApp.new("Counter Demo", 400.0, 300.0);
  var btn = ButtonState.new(0);
  var counter: Int = 0;

  while app.should_close() == false {
    app.begin_frame();

    var title_rect = Rect.new(10.0, 10.0, 380.0, 30.0);
    var title_pos = Point.new(10.0, 10.0);
    app.render_list.add_text("XIOM-UI Counter Demo", title_pos, app.theme.text_color);

    var btn_rect = Rect.new(140.0, 60.0, 120.0, 40.0);
    var mouse = Point.new(app.input.mouse_x, app.input.mouse_y);
    var hovered = btn_rect.contains(&mouse);
    btn.hovered = hovered;

    var btn_color = app.theme.accent_color;
    if hovered {
      btn_color = app.theme.hover_color;
    }
    if btn.pressed {
      btn_color = app.theme.active_color;
    }
    app.render_list.add_rect(btn_rect, btn_color);

    var label_rect = Rect.new(140.0, 110.0, 120.0, 30.0);
    var label_pos = Point.new(label_rect.x, label_rect.y);
    var count_text = int_to_str(counter);
    app.render_list.add_text(count_text, label_pos, app.theme.text_color);

    if hovered && app.input.is_mouse_down(MouseButton.Left) {
      if !btn.pressed {
        counter = counter + 1;
      }
      btn.pressed = true;
    } else {
      btn.pressed = false;
    }

    app.end_frame();
  }

  return Ok(0);
}

pub fn demo_form() -> Result[Int, Str] {
  var app = UIApp.new("Form Demo", 500.0, 400.0);
  var name_field = TextFieldState.new(0);
  var email_field = TextFieldState.new(1);
  var subscribe_check = CheckboxState.new(0);
  var volume_slider = SliderState.new(0, 0.0, 100.0, 50.0);
  var submit_btn = ButtonState.new(1);

  while app.should_close() == false {
    app.begin_frame();

    var form_y: Float32 = 10.0;
    var label_x: Float32 = 10.0;
    var input_x: Float32 = 120.0;

    app.render_list.add_text("Name:", Point.new(label_x, form_y), app.theme.text_color);
    var name_rect = Rect.new(input_x, form_y, 250.0, 24.0);
    app.render_list.add_rect(name_rect, app.theme.bg_color);
    if name_field.text != "" {
      app.render_list.add_text(name_field.text, Point.new(input_x + 4.0, form_y), app.theme.text_color);
    }

    form_y = form_y + 34.0;
    app.render_list.add_text("Email:", Point.new(label_x, form_y), app.theme.text_color);
    var email_rect = Rect.new(input_x, form_y, 250.0, 24.0);
    app.render_list.add_rect(email_rect, app.theme.bg_color);
    if email_field.text != "" {
      app.render_list.add_text(email_field.text, Point.new(input_x + 4.0, form_y), app.theme.text_color);
    }

    form_y = form_y + 34.0;
    app.render_list.add_text("Subscribe:", Point.new(label_x, form_y), app.theme.text_color);
    var cb_rect = Rect.new(input_x, form_y, 20.0, 20.0);
    var cb_color = app.theme.bg_color;
    if subscribe_check.checked { cb_color = app.theme.accent_color; }
    app.render_list.add_rect(cb_rect, cb_color);

    form_y = form_y + 34.0;
    app.render_list.add_text("Volume:", Point.new(label_x, form_y), app.theme.text_color);
    var slider_bg = Rect.new(input_x, form_y + 6.0, 200.0, 8.0);
    app.render_list.add_rect(slider_bg, app.theme.border_color);
    var fill_w = (volume_slider.value / 100.0) * 200.0;
    var slider_fill = Rect.new(input_x, form_y + 6.0, fill_w, 8.0);
    app.render_list.add_rect(slider_fill, app.theme.accent_color);

    form_y = form_y + 44.0;
    var submit_rect = Rect.new(input_x, form_y, 100.0, 32.0);
    app.render_list.add_rect(submit_rect, app.theme.accent_color);
    app.render_list.add_text("Submit", Point.new(input_x + 24.0, form_y + 4.0), WHITE());

    app.end_frame();
  }

  return Ok(0);
}

pub fn demo_layout() -> Result[Int, Str] {
  var app = UIApp.new("Layout Demo", 600.0, 400.0);

  while app.should_close() == false {
    app.begin_frame();

    var ctx = LayoutContext.new();
    ctx.begin(0.0, 0.0, app.width, app.height);
    ctx.set_padding(Padding.all(8.0));

    ctx.set_direction(LayoutDirection.Vertical);
    var header = ctx.allocate(Size.new(app.width - 16.0, 40.0));
    app.render_list.add_rect(header, app.theme.accent_color);
    app.render_list.add_text("Layout Engine Demo", Point.new(12.0, 12.0), WHITE());

    ctx.allocate(Size.new(app.width - 16.0, 8.0));

    var row_cells = layout_row(&ctx, 100.0, 3);
    var ci: Int = 0;
    while ci < row_cells.len() {
      app.render_list.add_rect(row_cells[ci], Color.new(0.3, int_to_float32(ci) * 0.3, 0.6, 1.0));
      var cell_text = "Cell ";
      cell_text = cell_text + int_to_str(ci + 1);
      app.render_list.add_text(cell_text, Point.new(row_cells[ci].x + 8.0, row_cells[ci].y + 8.0), WHITE());
      ci = ci + 1;
    }

    ctx.allocate(Size.new(app.width - 16.0, 8.0));

    var col_cells = layout_column(&ctx, 200.0, 3);
    ci = 0;
    while ci < col_cells.len() {
      app.render_list.add_rect(col_cells[ci], Color.new(0.2, 0.6, int_to_float32(ci) * 0.3, 1.0));
      var cell_text = "Row ";
      cell_text = cell_text + int_to_str(ci + 1);
      app.render_list.add_text(cell_text, Point.new(col_cells[ci].x + 8.0, col_cells[ci].y + 8.0), WHITE());
      ci = ci + 1;
    }

    ctx.allocate(Size.new(app.width - 16.0, 8.0));

    var grid = layout_grid(&ctx, 4, 2, 100.0, 40.0);
    ci = 0;
    while ci < grid.len() {
      var gx = int_to_float32(ci % 4);
      var gy = int_to_float32(ci / 4);
      app.render_list.add_rect(grid[ci], Color.new(gx * 0.2, 0.3, gy * 0.3, 1.0));
      var gtext = "G";
      gtext = gtext + int_to_str(ci);
      app.render_list.add_text(gtext, Point.new(grid[ci].x + 4.0, grid[ci].y + 4.0), WHITE());
      ci = ci + 1;
    }

    app.end_frame();
  }

  return Ok(0);
}

fn int_to_float32(n: Int) -> Float32 {
  if n == 0 { return 0.0; }
  var is_neg = n < 0;
  var val = n;
  if is_neg { val = -val; }
  var result: Float32 = 0.0;
  var mult: Float32 = 1.0;
  while val > 0 {
    var d = val % 10;
    if d == 0 { result = result + 0.0 * mult; }
    elif d == 1 { result = result + 1.0 * mult; }
    elif d == 2 { result = result + 2.0 * mult; }
    elif d == 3 { result = result + 3.0 * mult; }
    elif d == 4 { result = result + 4.0 * mult; }
    elif d == 5 { result = result + 5.0 * mult; }
    elif d == 6 { result = result + 6.0 * mult; }
    elif d == 7 { result = result + 7.0 * mult; }
    elif d == 8 { result = result + 8.0 * mult; }
    elif d == 9 { result = result + 9.0 * mult; }
    mult = mult * 10.0;
    val = val / 10;
  }
  if is_neg { return -result; }
  return result;
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var is_neg = n < 0;
  var val = n;
  if is_neg { val = -val; }
  var digits = Vec[Int].new();
  while val > 0 {
    var d = val % 10;
    digits.push(d);
    val = val / 10;
  }
  var result = "";
  if is_neg { result = "-"; }
  if digits.is_empty() { return "0"; }
  var i = digits.len() - 1;
  while i >= 0 {
    if digits[i] == 0 { result = result + "0"; }
    elif digits[i] == 1 { result = result + "1"; }
    elif digits[i] == 2 { result = result + "2"; }
    elif digits[i] == 3 { result = result + "3"; }
    elif digits[i] == 4 { result = result + "4"; }
    elif digits[i] == 5 { result = result + "5"; }
    elif digits[i] == 6 { result = result + "6"; }
    elif digits[i] == 7 { result = result + "7"; }
    elif digits[i] == 8 { result = result + "8"; }
    elif digits[i] == 9 { result = result + "9"; }
    i = i - 1;
  }
  return result;
}
