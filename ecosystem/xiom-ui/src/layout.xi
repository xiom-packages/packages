module xiom.ui.layout

pub type LayoutContext = {
  x: Float32;
  y: Float32;
  available_w: Float32;
  available_h: Float32;
  direction: LayoutDirection;
  spacing: Float32;
  padding: Padding;
  cursor_x: Float32;
  cursor_y: Float32;
}

pub fn LayoutContext.new() -> LayoutContext {
  return LayoutContext{
    x: 0.0,
    y: 0.0,
    available_w: 0.0,
    available_h: 0.0,
    direction: LayoutDirection.Vertical,
    spacing: 4.0,
    padding: Padding.all(0.0),
    cursor_x: 0.0,
    cursor_y: 0.0,
  };
}

pub fn LayoutContext.begin(x: Float32, y: Float32, w: Float32, h: Float32) {
  var x_off = x + padding.left;
  var y_off = y + padding.top;
  var aw = w - padding.left - padding.right;
  var ah = h - padding.top - padding.bottom;
  x = x_off;
  y = y_off;
  available_w = aw;
  available_h = ah;
  cursor_x = x_off;
  cursor_y = y_off;
}

pub fn LayoutContext.set_direction(dir: LayoutDirection) {
  direction = dir;
}

pub fn LayoutContext.set_spacing(s: Float32) {
  spacing = s;
}

pub fn LayoutContext.set_padding(p: Padding) {
  padding = p;
}

pub fn LayoutContext.remaining() -> Rect {
  return Rect.new(x, y, available_w, available_h);
}

pub fn LayoutContext.cursor() -> Point {
  return Point.new(cursor_x, cursor_y);
}

pub fn LayoutContext.advance(size: Size) {
  match direction {
    Horizontal => {
      cursor_x = cursor_x + size.w + spacing;
    }
    Vertical => {
      cursor_y = cursor_y + size.h + spacing;
    }
  }
}

pub fn LayoutContext.allocate(size: Size) -> Rect {
  var rect = Rect.new(cursor_x, cursor_y, size.w, size.h);
  advance(size);
  return rect;
}

pub fn LayoutContext.allocate_fill(cross_size: Float32) -> Rect {
  match direction {
    Horizontal => {
      var remaining = available_w - (cursor_x - x);
      if remaining < 0.0 { remaining = 0.0; }
      var rect = Rect.new(cursor_x, cursor_y, remaining, cross_size);
      cursor_x = cursor_x + remaining + spacing;
      return rect;
    }
    Vertical => {
      var remaining = available_h - (cursor_y - y);
      if remaining < 0.0 { remaining = 0.0; }
      var rect = Rect.new(cursor_x, cursor_y, cross_size, remaining);
      cursor_y = cursor_y + remaining + spacing;
      return rect;
    }
  }
}

pub fn LayoutContext.next_row(height: Float32) {
  cursor_x = x;
  cursor_y = cursor_y + height + spacing;
}

pub fn LayoutContext.next_column(width: Float32) {
  cursor_x = cursor_x + width + spacing;
  cursor_y = y;
}

pub fn layout_row(ctx: &mut LayoutContext, height: Float32, count: Int) -> Vec[Rect] {
  var result = Vec[Rect].new();
  if count <= 0 { return result; }
  var total_spacing = int_to_float32(count - 1) * ctx.spacing;
  var cell_w = (ctx.available_w - total_spacing) / int_to_float32(count);
  if cell_w < 0.0 { cell_w = 0.0; }
  var i: Int = 0;
  while i < count {
    var rx = ctx.cursor_x + int_to_float32(i) * (cell_w + ctx.spacing);
    var rect = Rect.new(rx, ctx.cursor_y, cell_w, height);
    result.push(rect);
    i = i + 1;
  }
  ctx.cursor_y = ctx.cursor_y + height + ctx.spacing;
  return result;
}

pub fn layout_column(ctx: &mut LayoutContext, width: Float32, count: Int) -> Vec[Rect] {
  var result = Vec[Rect].new();
  if count <= 0 { return result; }
  var total_spacing = int_to_float32(count - 1) * ctx.spacing;
  var cell_h = (ctx.available_h - total_spacing) / int_to_float32(count);
  if cell_h < 0.0 { cell_h = 0.0; }
  var i: Int = 0;
  while i < count {
    var ry = ctx.cursor_y + int_to_float32(i) * (cell_h + ctx.spacing);
    var rect = Rect.new(ctx.cursor_x, ry, width, cell_h);
    result.push(rect);
    i = i + 1;
  }
  ctx.cursor_x = ctx.cursor_x + width + ctx.spacing;
  return result;
}

pub fn layout_push(ctx: &mut LayoutContext, size: Size) -> Rect {
  return ctx.allocate(size);
}

pub fn layout_remaining(ctx: &LayoutContext) -> Rect {
  return ctx.remaining();
}

pub fn layout_with_margin(rect: &Rect, margin: &Margin) -> Rect {
  return Rect.new(
    rect.x + margin.left,
    rect.y + margin.top,
    rect.w - margin.left - margin.right,
    rect.h - margin.top - margin.bottom,
  );
}

pub fn layout_with_padding(rect: &Rect, padding: &Padding) -> Rect {
  return Rect.new(
    rect.x + padding.left,
    rect.y + padding.top,
    rect.w - padding.left - padding.right,
    rect.h - padding.top - padding.bottom,
  );
}

pub fn layout_align(outer: &Rect, inner: &Size, halign: Alignment, valign: Alignment) -> Rect {
  var x = outer.x;
  var y = outer.y;
  var w = inner.w;
  var h = inner.h;
  match halign {
    Start => x = outer.x,
    Center => x = outer.x + (outer.w - inner.w) * 0.5,
    End => x = outer.x + outer.w - inner.w,
    Stretch => { w = outer.w; x = outer.x; }
  }
  match valign {
    Start => y = outer.y,
    Center => y = outer.y + (outer.h - inner.h) * 0.5,
    End => y = outer.y + outer.h - inner.h,
    Stretch => { h = outer.h; y = outer.y; }
  }
  return Rect.new(x, y, w, h);
}

pub fn layout_center(size: &Size) -> Rect {
  return Rect.new(-size.w * 0.5, -size.h * 0.5, size.w, size.h);
}

pub fn layout_grid(ctx: &mut LayoutContext, cols: Int, rows: Int, cell_w: Float32, cell_h: Float32) -> Vec[Rect] {
  var result = Vec[Rect].new();
  var r: Int = 0;
  while r < rows {
    var c: Int = 0;
    while c < cols {
      var rx = ctx.cursor_x + int_to_float32(c) * (cell_w + ctx.spacing);
      var ry = ctx.cursor_y + int_to_float32(r) * (cell_h + ctx.spacing);
      result.push(Rect.new(rx, ry, cell_w, cell_h));
      c = c + 1;
    }
    r = r + 1;
  }
  var total_h = int_to_float32(rows) * cell_h + int_to_float32(rows - 1) * ctx.spacing;
  ctx.cursor_y = ctx.cursor_y + total_h;
  return result;
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
