// XIOM -- xiom-ui Conformance Tests
// 98 tests covering types, layout, theme, widgets, render, and application lifecycle
module ui_tests
use xiom.io;
use xiom.ui.types; use xiom.ui.layout;
use xiom.ui.widgets; use xiom.ui.render;
use xiom.ui.theme; use xiom.ui.application;

type TestResult = {
  passed: Bool;
  name: Str;
}

fn pass(name: Str) -> TestResult {
  return TestResult{ passed: true, name: name };
}

fn fail(name: Str) -> TestResult {
  return TestResult{ passed: false, name: name };
}

fn check(condition: Bool, name: Str) -> TestResult {
  if condition { return pass(name); }
  return fail(name);
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  return out;
}
fn run_test(result: TestResult) -> Int {
  if result.passed { io.println("  [PASS] " + result.name); return 0; }
  io.println("  [FAIL] " + result.name); return 1;
}

// ------ Types ------ (t1-t21)

fn t1() -> TestResult {
  var r = Rect.new(10.0, 20.0, 100.0, 50.0);
  return check(r.x == 10.0 && r.y == 20.0 && r.w == 100.0 && r.h == 50.0, "types: Rect.new sets fields");
}
fn t2() -> TestResult {
  var r = Rect.zero();
  return check(r.x == 0.0 && r.y == 0.0 && r.w == 0.0 && r.h == 0.0, "types: Rect.zero all zero");
}
fn t3() -> TestResult {
  var r = Rect.new(0.0, 0.0, 100.0, 100.0);
  var p = Point.new(50.0, 50.0);
  var inside = r.contains(&p);
  return check(inside, "types: Rect.contains point inside");
}
fn t4() -> TestResult {
  var r = Rect.new(0.0, 0.0, 100.0, 100.0);
  var p = Point.new(150.0, 150.0);
  var inside = r.contains(&p);
  return check(!inside, "types: Rect.contains point outside");
}
fn t5() -> TestResult {
  var c = Color.new(0.5, 0.25, 0.75, 1.0);
  return check(c.r == 0.5 && c.g == 0.25 && c.b == 0.75 && c.a == 1.0, "types: Color.new sets channels");
}
fn t6() -> TestResult {
  var c = RED();
  return check(c.r == 1.0 && c.g == 0.0 && c.b == 0.0 && c.a == 1.0, "types: RED constant");
}
fn t7() -> TestResult {
  var c = GREEN();
  return check(c.r == 0.0 && c.g == 1.0 && c.b == 0.0 && c.a == 1.0, "types: GREEN constant");
}
fn t8() -> TestResult {
  var c = BLUE();
  return check(c.r == 0.0 && c.g == 0.0 && c.b == 1.0 && c.a == 1.0, "types: BLUE constant");
}
fn t9() -> TestResult {
  var c = TRANSPARENT();
  return check(c.a == 0.0, "types: TRANSPARENT alpha zero");
}
fn t10() -> TestResult {
  var c = GRAY();
  return check(c.r == 0.5 && c.g == 0.5 && c.b == 0.5, "types: GRAY constant");
}
fn t11() -> TestResult {
  var s = Size.new(100.0, 50.0);
  return check(s.w == 100.0 && s.h == 50.0, "types: Size.new sets fields");
}
fn t12() -> TestResult {
  var s = Size.zero();
  return check(s.w == 0.0 && s.h == 0.0, "types: Size.zero");
}
fn t13() -> TestResult {
  var p = Point.new(30.0, 40.0);
  return check(p.x == 30.0 && p.y == 40.0, "types: Point.new");
}
fn t14() -> TestResult {
  var p = Point.zero();
  return check(p.x == 0.0 && p.y == 0.0, "types: Point.zero");
}
fn t15() -> TestResult {
  var pad = Padding.new(1.0, 2.0, 3.0, 4.0);
  return check(pad.top == 1.0 && pad.right == 2.0 && pad.bottom == 3.0 && pad.left == 4.0, "types: Padding.new");
}
fn t16() -> TestResult {
  var pad = Padding.all(8.0);
  return check(pad.top == 8.0 && pad.right == 8.0 && pad.bottom == 8.0 && pad.left == 8.0, "types: Padding.all uniform");
}
fn t17() -> TestResult {
  var pad = Padding.symmetric(16.0, 8.0);
  return check(pad.right == 16.0 && pad.left == 16.0 && pad.top == 8.0 && pad.bottom == 8.0, "types: Padding.symmetric");
}
fn t18() -> TestResult {
  var m = Margin.new(1.0, 2.0, 3.0, 4.0);
  return check(m.top == 1.0 && m.right == 2.0 && m.bottom == 3.0 && m.left == 4.0, "types: Margin.new");
}
fn t19() -> TestResult {
  var m = Margin.all(12.0);
  return check(m.top == 12.0 && m.right == 12.0 && m.bottom == 12.0 && m.left == 12.0, "types: Margin.all uniform");
}
fn t20() -> TestResult {
  var input = InputState.new();
  var pressed = input.is_mouse_down(MouseButton.Left);
  return check(!pressed, "types: InputState new has no mouse");
}
fn t21() -> TestResult {
  var input = InputState.new();
  var down = input.is_key_down(65);
  return check(!down, "types: InputState new has no keys");
}

// ------ Theme ------ (t22-t27)

fn t22() -> TestResult {
  var th = theme_default();
  var ok = th.bg_color.a >= 0.0 && th.text_color.a >= 0.0 && th.accent_color.a >= 0.0;
  return check(ok, "theme: default preset valid");
}
fn t23() -> TestResult {
  var th = theme_dark();
  return check(th.bg_color.r < 0.5, "theme: dark bg is dark");
}
fn t24() -> TestResult {
  var th = theme_high_contrast();
  return check(th.font_scale > 1.0, "theme: high-contrast has larger font");
}
fn t25() -> TestResult {
  var th = theme_high_contrast();
  return check(th.corner_radius == 0.0, "theme: high-contrast corner_radius zero");
}
fn t26() -> TestResult {
  var bg = Color.new(0.1, 0.2, 0.3, 1.0);
  var fg = Color.new(0.9, 0.8, 0.7, 1.0);
  var ac = Color.new(0.5, 0.5, 1.0, 0.5);
  var th = Theme.new(bg, fg, ac, fg, fg, fg, 1.5, 8.0);
  return check(th.font_scale == 1.5 && th.corner_radius == 8.0, "theme: Theme.new custom fields");
}
fn t27() -> TestResult {
  var orig = theme_default();
  var copy = orig.clone();
  return check(copy.font_scale == orig.font_scale && copy.corner_radius == orig.corner_radius, "theme: Theme.clone preserves");
}

// ------ Layout ------ (t28-t48)

fn t28() -> TestResult {
  var ctx = LayoutContext.new();
  return check(ctx.spacing == 4.0, "layout: LayoutContext.new default spacing");
}
fn t29() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(0.0, 0.0, 200.0, 100.0);
  return check(ctx.available_w >= 0.0, "layout: begin sets available");
}
fn t30() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.set_direction(LayoutDirection.Horizontal);
  return check(ctx.direction == LayoutDirection.Horizontal, "layout: set_direction changes direction");
}
fn t31() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.set_spacing(10.0);
  return check(ctx.spacing == 10.0, "layout: set_spacing changes spacing");
}
fn t32() -> TestResult {
  var ctx = LayoutContext.new();
  var pad = Padding.all(6.0);
  ctx.set_padding(pad);
  return check(ctx.padding.left == 6.0, "layout: set_padding sets padding");
}
fn t33() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(50.0, 50.0, 500.0, 500.0);
  var rem = ctx.remaining();
  return check(rem.w > 0.0 && rem.h > 0.0, "layout: remaining returns rect");
}
fn t34() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(0.0, 0.0, 400.0, 400.0);
  var cur = ctx.cursor();
  return check(cur.x >= 0.0, "layout: cursor returns point");
}
fn t35() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(0.0, 0.0, 400.0, 400.0);
  var alloc = ctx.allocate(Size.new(100.0, 50.0));
  var moved = ctx.cursor();
  return check(alloc.w == 100.0 && alloc.h == 50.0 && moved.y > 0.0, "layout: allocate advances cursor");
}
fn t36() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(0.0, 0.0, 400.0, 400.0);
  ctx.advance(Size.new(30.0, 30.0));
  var cur = ctx.cursor();
  return check(cur.y > 0.0, "layout: advance moves cursor");
}
fn t37() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(0.0, 0.0, 400.0, 400.0);
  ctx.next_row(20.0);
  var cur = ctx.cursor();
  return check(cur.y > 0.0, "layout: next_row advances Y");
}
fn t38() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(0.0, 0.0, 400.0, 400.0);
  ctx.next_column(30.0);
  var cur = ctx.cursor();
  return check(cur.x > 0.0, "layout: next_column advances X");
}
fn t39() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(0.0, 0.0, 300.0, 200.0);
  ctx.set_direction(LayoutDirection.Horizontal);
  ctx.set_spacing(8.0);
  var cells = layout_row(&ctx, 50.0, 3);
  return check(cells.len() == 3, "layout: layout_row count correct");
}
fn t40() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(0.0, 0.0, 300.0, 200.0);
  ctx.set_spacing(4.0);
  var cells = layout_column(&ctx, 100.0, 3);
  return check(cells.len() == 3, "layout: layout_column count correct");
}
fn t41() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(0.0, 0.0, 500.0, 300.0);
  var grid = layout_grid(&ctx, 4, 3, 80.0, 40.0);
  return check(grid.len() == 12, "layout: layout_grid 4x3 = 12 cells");
}
fn t42() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(0.0, 0.0, 300.0, 200.0);
  var r = layout_push(&ctx, Size.new(64.0, 32.0));
  return check(r.w == 64.0 && r.h == 32.0, "layout: layout_push allocates correct size");
}
fn t43() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(0.0, 0.0, 300.0, 200.0);
  var rem = layout_remaining(&ctx);
  return check(rem.w > 0.0, "layout: layout_remaining non-empty");
}
fn t44() -> TestResult {
  var r = Rect.new(20.0, 20.0, 200.0, 100.0);
  var m = Margin.new(10.0, 10.0, 10.0, 10.0);
  var inner = layout_with_margin(&r, &m);
  return check(inner.x > 20.0 && inner.w < 200.0, "layout: layout_with_margin shrinks");
}
fn t45() -> TestResult {
  var r = Rect.new(10.0, 10.0, 200.0, 100.0);
  var p = Padding.new(10.0, 10.0, 10.0, 10.0);
  var inner = layout_with_padding(&r, &p);
  return check(inner.x > 10.0 && inner.w < 200.0, "layout: layout_with_padding shrinks");
}
fn t46() -> TestResult {
  var outer = Rect.new(0.0, 0.0, 400.0, 200.0);
  var inner = Size.new(100.0, 50.0);
  var aligned = layout_align(&outer, &inner, Alignment.Center, Alignment.Center);
  return check(aligned.x > 0.0, "layout: layout_align center moves x");
}
fn t47() -> TestResult {
  var outer = Rect.new(0.0, 0.0, 200.0, 100.0);
  var inner = Size.new(100.0, 50.0);
  var aligned = layout_align(&outer, &inner, Alignment.Stretch, Alignment.Stretch);
  return check(aligned.w == 200.0 && aligned.h == 100.0, "layout: layout_align stretch fills");
}
fn t48() -> TestResult {
  var size = Size.new(100.0, 80.0);
  var r = layout_center(&size);
  return check(r.x < 0.0, "layout: layout_center x negative");
}

// ------ Render ------ (t49-t59)

fn t49() -> TestResult {
  var rl = RenderList.new();
  return check(rl.is_empty(), "render: new list is empty");
}
fn t50() -> TestResult {
  var rl = RenderList.new();
  rl.add_rect(Rect.new(0.0, 0.0, 10.0, 10.0), RED());
  return check(rl.command_count() == 1, "render: add_rect increments count");
}
fn t51() -> TestResult {
  var rl = RenderList.new();
  rl.add_text("hello", Point.new(0.0, 0.0), WHITE());
  return check(rl.command_count() == 1, "render: add_text adds command");
}
fn t52() -> TestResult {
  var rl = RenderList.new();
  rl.add_text_sized("big", Point.new(0.0, 0.0), WHITE(), 32.0);
  return check(rl.command_count() == 1, "render: add_text_sized adds command");
}
fn t53() -> TestResult {
  var rl = RenderList.new();
  rl.add_circle(Point.new(50.0, 50.0), 20.0, BLUE());
  return check(rl.command_count() == 1, "render: add_circle adds command");
}
fn t54() -> TestResult {
  var rl = RenderList.new();
  rl.add_line(Point.new(0.0, 0.0), Point.new(100.0, 0.0), GRAY(), 2.0);
  return check(rl.command_count() == 1, "render: add_line adds command");
}
fn t55() -> TestResult {
  var rl = RenderList.new();
  rl.add_image(Rect.new(0.0, 0.0, 64.0, 64.0), 42);
  return check(rl.command_count() == 1, "render: add_image adds command");
}
fn t56() -> TestResult {
  var rl = RenderList.new();
  rl.add_clip(Rect.new(0.0, 0.0, 200.0, 200.0));
  return check(rl.command_count() == 1, "render: add_clip adds command");
}
fn t57() -> TestResult {
  var rl = RenderList.new();
  rl.add_rect(Rect.new(0.0, 0.0, 10.0, 10.0), RED());
  rl.clear();
  return check(rl.is_empty(), "render: clear resets list");
}
fn t58() -> TestResult {
  var rl = RenderList.new();
  rl.add_rect(Rect.new(0.0, 0.0, 10.0, 10.0), RED());
  var cmd = rl.get_command(0);
  var ok = false;
  match cmd { Some(_) => { ok = true; } None => { ok = false; } }
  return check(ok, "render: get_command valid index returns Some");
}
fn t59() -> TestResult {
  var rl = RenderList.new();
  var cmd = rl.get_command(999);
  var ok = false;
  match cmd { Some(_) => { ok = false; } None => { ok = true; } }
  return check(ok, "render: get_command out of bounds returns None");
}

// ------ Widgets ------ (t60-t82)

fn t60() -> TestResult {
  var btn = ButtonState.new(0);
  return check(!btn.is_pressed() && !btn.is_hovered(), "widgets: ButtonState new not pressed/hovered");
}
fn t61() -> TestResult {
  var cb = CheckboxState.new(1);
  return check(!cb.checked, "widgets: CheckboxState new unchecked");
}
fn t62() -> TestResult {
  var cb = CheckboxState.new(1);
  cb.toggle();
  return check(cb.checked, "widgets: CheckboxState toggle on");
}
fn t63() -> TestResult {
  var cb = CheckboxState.new(1);
  cb.toggle();
  cb.toggle();
  return check(!cb.checked, "widgets: CheckboxState double toggle off");
}
fn t64() -> TestResult {
  var tf = TextFieldState.new(2);
  return check(tf.text == "" && tf.cursor == 0, "widgets: TextFieldState new empty");
}
fn t65() -> TestResult {
  var tf = TextFieldState.new(2);
  tf.insert("x");
  return check(tf.text == "x" && tf.cursor == 1, "widgets: TextFieldState insert char");
}
fn t66() -> TestResult {
  var tf = TextFieldState.new(2);
  tf.insert("a");
  tf.insert("b");
  tf.backspace();
  return check(tf.text == "a" && tf.cursor == 1, "widgets: TextFieldState backspace removes");
}
fn t67() -> TestResult {
  var tf = TextFieldState.new(2);
  tf.insert("a");
  tf.insert("b");
  tf.move_cursor_left();
  tf.delete();
  return check(tf.text == "a", "widgets: TextFieldState delete char");
}
fn t68() -> TestResult {
  var tf = TextFieldState.new(2);
  tf.insert("a");
  tf.insert("b");
  tf.clear();
  return check(tf.text == "" && tf.cursor == 0, "widgets: TextFieldState clear resets");
}
fn t69() -> TestResult {
  var tf = TextFieldState.new(2);
  tf.insert("abc");
  tf.move_cursor_home();
  return check(tf.cursor == 0, "widgets: TextFieldState cursor home");
}
fn t70() -> TestResult {
  var tf = TextFieldState.new(2);
  tf.insert("abc");
  tf.move_cursor_end();
  return check(tf.cursor == 3, "widgets: TextFieldState cursor end");
}
fn t71() -> TestResult {
  var s = SliderState.new(3, 0.0, 100.0, 50.0);
  return check(s.value == 50.0, "widgets: SliderState new sets initial");
}
fn t72() -> TestResult {
  var s = SliderState.new(3, 0.0, 100.0, 50.0);
  s.set_value(200.0);
  return check(s.value == 100.0, "widgets: SliderState clamps to max");
}
fn t73() -> TestResult {
  var s = SliderState.new(3, 0.0, 100.0, 50.0);
  s.set_value(-10.0);
  return check(s.value == 0.0, "widgets: SliderState clamps to min");
}
fn t74() -> TestResult {
  var s = SliderState.new(3, 0.0, 100.0, 75.0);
  var n = s.normalized();
  return check(n == 0.75, "widgets: SliderState normalized 75%");
}
fn t75() -> TestResult {
  var dd = DropdownState.new(4);
  return check(!dd.open, "widgets: DropdownState new closed");
}
fn t76() -> TestResult {
  var dd = DropdownState.new(4);
  dd.toggle();
  return check(dd.open, "widgets: DropdownState toggle open");
}
fn t77() -> TestResult {
  var dd = DropdownState.new(4);
  var opts = Vec[Str].new();
  opts.push("one");
  opts.push("two");
  opts.push("three");
  dd.set_options(opts);
  dd.select(1);
  return check(dd.selected_text() == "two", "widgets: DropdownState selected_text");
}
fn t78() -> TestResult {
  var dd = DropdownState.new(4);
  var opts = Vec[Str].new();
  opts.push("alpha");
  opts.push("beta");
  dd.set_options(opts);
  dd.select(99);
  return check(dd.selected_text() == "", "widgets: DropdownState out of range select");
}
fn t79() -> TestResult {
  var tstate = TabsState.new(6);
  var tabs = Vec[Str].new();
  tabs.push("A");
  tabs.push("B");
  tabs.push("C");
  tstate.set_tabs(tabs);
  return check(tstate.active_tab == 0, "widgets: TabsState default active 0");
}
fn t80() -> TestResult {
  var tstate = TabsState.new(6);
  var tabs = Vec[Str].new();
  tabs.push("A");
  tabs.push("B");
  tabs.push("C");
  tstate.set_tabs(tabs);
  tstate.next_tab();
  return check(tstate.active_tab == 1, "widgets: TabsState next_tab");
}
fn t81() -> TestResult {
  var tstate = TabsState.new(6);
  var tabs = Vec[Str].new();
  tabs.push("A");
  tabs.push("B");
  tabs.push("C");
  tstate.set_tabs(tabs);
  tstate.prev_tab();
  return check(tstate.active_tab == 2, "widgets: TabsState prev_tab wraps");
}
fn t82() -> TestResult {
  var p = PanelState.new(5);
  p.scroll(10.0, 20.0);
  return check(p.scroll_x == 10.0 && p.scroll_y == 20.0, "widgets: PanelState scroll accumulates");
}

// ------ Application ------ (t83-t88)

fn t83() -> TestResult {
  var app = UIApp.new("Test App", 800.0, 600.0);
  return check(app.width() == 800.0 && app.height() == 600.0, "app: UIApp.new dimensions");
}
fn t84() -> TestResult {
  var app = UIApp.new("Test App", 800.0, 600.0);
  return check(!app.should_close(), "app: UIApp not closing initially");
}
fn t85() -> TestResult {
  var app = UIApp.new("Test App", 800.0, 600.0);
  app.begin_frame();
  app.end_frame();
  return pass("app: begin_frame / end_frame no crash");
}
fn t86() -> TestResult {
  var app = UIApp.new("Test App", 800.0, 600.0);
  app.begin_frame();
  let count = app.render_list.command_count();
  app.end_frame();
  return check(count == 0, "app: begin_frame clears render list");
}
fn t87() -> TestResult {
  var app = UIApp.new("Test App", 800.0, 600.0);
  var dark = theme_dark();
  app.set_theme(dark);
  return check(app.theme.bg_color.r < 0.5, "app: set_theme changes to dark");
}
fn t88() -> TestResult {
  var app = UIApp.new("Test App", 800.0, 600.0);
  app.close();
  return check(app.should_close(), "app: close sets close flag");
}

// ------ Layout edge cases ------ (t89-t90)

fn t89() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(10.0, 10.0, 500.0, 500.0);
  ctx.set_spacing(0.0);
  var cells = layout_row(&ctx, 50.0, 2);
  return check(cells.len() == 2, "layout: layout_row spacing zero");
}
fn t90() -> TestResult {
  var ctx = LayoutContext.new();
  ctx.begin(0.0, 0.0, 300.0, 300.0);
  ctx.set_direction(LayoutDirection.Horizontal);
  var fill = ctx.allocate_fill(30.0);
  return check(fill.w > 0.0, "layout: allocate_fill horizontal");
}

// ------ Render edge cases ------ (t91-t92)

fn t91() -> TestResult {
  var rl = RenderList.new();
  rl.add_rect(Rect.new(0.0, 0.0, 10.0, 10.0), RED());
  rl.add_rect(Rect.new(0.0, 0.0, 10.0, 10.0), GREEN());
  rl.add_rect(Rect.new(0.0, 0.0, 10.0, 10.0), BLUE());
  return check(rl.command_count() == 3, "render: multiple adds correct count");
}
fn t92() -> TestResult {
  var rl = RenderList.new();
  var cmd = rl.get_command(-1);
  var ok = false;
  match cmd { Some(_) => { ok = false; } None => { ok = true; } }
  return check(ok, "render: get_command negative index None");
}

// ------ Widget edge cases ------ (t93-t95)

fn t93() -> TestResult {
  var s = SliderState.new(3, 10.0, 10.0, 10.0);
  var n = s.normalized();
  return check(n == 0.0, "widgets: SliderState normalized min==max");
}
fn t94() -> TestResult {
  var dd = DropdownState.new(4);
  var empty = dd.selected_text();
  return check(empty == "", "widgets: DropdownState selected_text empty list");
}
fn t95() -> TestResult {
  var tstate = TabsState.new(6);
  tstate.next_tab();
  return check(tstate.active_tab == 0, "widgets: TabsState next on empty no-op");
}

// ------ Application edge cases ------ (t96-t98)

fn t96() -> TestResult {
  var app = UIApp.new("Test App", 800.0, 600.0);
  app.set_input(InputState.new());
  var inp = app.input_state();
  return check(inp.mouse_x == 0.0, "app: set_input resets mouse_x");
}
fn t97() -> TestResult {
  var app = UIApp.new("Test App", 800.0, 600.0);
  var rl = app.render_commands();
  return check(rl.is_empty(), "app: render_commands returns ref");
}
fn t98() -> TestResult {
  var app = UIApp.new("Test App", 800.0, 600.0);
  var inp = app.input_state();
  return check(inp.mouse_x >= 0.0, "app: input_state returns ref");
}

fn main() -> Int {
  io.println("=== XIOM UI Conformance ===");
  var failed: Int = 0; var total: Int = 0;

  total = total + 1; failed = failed + run_test(t1());
  total = total + 1; failed = failed + run_test(t2());
  total = total + 1; failed = failed + run_test(t3());
  total = total + 1; failed = failed + run_test(t4());
  total = total + 1; failed = failed + run_test(t5());
  total = total + 1; failed = failed + run_test(t6());
  total = total + 1; failed = failed + run_test(t7());
  total = total + 1; failed = failed + run_test(t8());
  total = total + 1; failed = failed + run_test(t9());
  total = total + 1; failed = failed + run_test(t10());
  total = total + 1; failed = failed + run_test(t11());
  total = total + 1; failed = failed + run_test(t12());
  total = total + 1; failed = failed + run_test(t13());
  total = total + 1; failed = failed + run_test(t14());
  total = total + 1; failed = failed + run_test(t15());
  total = total + 1; failed = failed + run_test(t16());
  total = total + 1; failed = failed + run_test(t17());
  total = total + 1; failed = failed + run_test(t18());
  total = total + 1; failed = failed + run_test(t19());
  total = total + 1; failed = failed + run_test(t20());
  total = total + 1; failed = failed + run_test(t21());
  total = total + 1; failed = failed + run_test(t22());
  total = total + 1; failed = failed + run_test(t23());
  total = total + 1; failed = failed + run_test(t24());
  total = total + 1; failed = failed + run_test(t25());
  total = total + 1; failed = failed + run_test(t26());
  total = total + 1; failed = failed + run_test(t27());
  total = total + 1; failed = failed + run_test(t28());
  total = total + 1; failed = failed + run_test(t29());
  total = total + 1; failed = failed + run_test(t30());
  total = total + 1; failed = failed + run_test(t31());
  total = total + 1; failed = failed + run_test(t32());
  total = total + 1; failed = failed + run_test(t33());
  total = total + 1; failed = failed + run_test(t34());
  total = total + 1; failed = failed + run_test(t35());
  total = total + 1; failed = failed + run_test(t36());
  total = total + 1; failed = failed + run_test(t37());
  total = total + 1; failed = failed + run_test(t38());
  total = total + 1; failed = failed + run_test(t39());
  total = total + 1; failed = failed + run_test(t40());
  total = total + 1; failed = failed + run_test(t41());
  total = total + 1; failed = failed + run_test(t42());
  total = total + 1; failed = failed + run_test(t43());
  total = total + 1; failed = failed + run_test(t44());
  total = total + 1; failed = failed + run_test(t45());
  total = total + 1; failed = failed + run_test(t46());
  total = total + 1; failed = failed + run_test(t47());
  total = total + 1; failed = failed + run_test(t48());
  total = total + 1; failed = failed + run_test(t49());
  total = total + 1; failed = failed + run_test(t50());
  total = total + 1; failed = failed + run_test(t51());
  total = total + 1; failed = failed + run_test(t52());
  total = total + 1; failed = failed + run_test(t53());
  total = total + 1; failed = failed + run_test(t54());
  total = total + 1; failed = failed + run_test(t55());
  total = total + 1; failed = failed + run_test(t56());
  total = total + 1; failed = failed + run_test(t57());
  total = total + 1; failed = failed + run_test(t58());
  total = total + 1; failed = failed + run_test(t59());
  total = total + 1; failed = failed + run_test(t60());
  total = total + 1; failed = failed + run_test(t61());
  total = total + 1; failed = failed + run_test(t62());
  total = total + 1; failed = failed + run_test(t63());
  total = total + 1; failed = failed + run_test(t64());
  total = total + 1; failed = failed + run_test(t65());
  total = total + 1; failed = failed + run_test(t66());
  total = total + 1; failed = failed + run_test(t67());
  total = total + 1; failed = failed + run_test(t68());
  total = total + 1; failed = failed + run_test(t69());
  total = total + 1; failed = failed + run_test(t70());
  total = total + 1; failed = failed + run_test(t71());
  total = total + 1; failed = failed + run_test(t72());
  total = total + 1; failed = failed + run_test(t73());
  total = total + 1; failed = failed + run_test(t74());
  total = total + 1; failed = failed + run_test(t75());
  total = total + 1; failed = failed + run_test(t76());
  total = total + 1; failed = failed + run_test(t77());
  total = total + 1; failed = failed + run_test(t78());
  total = total + 1; failed = failed + run_test(t79());
  total = total + 1; failed = failed + run_test(t80());
  total = total + 1; failed = failed + run_test(t81());
  total = total + 1; failed = failed + run_test(t82());
  total = total + 1; failed = failed + run_test(t83());
  total = total + 1; failed = failed + run_test(t84());
  total = total + 1; failed = failed + run_test(t85());
  total = total + 1; failed = failed + run_test(t86());
  total = total + 1; failed = failed + run_test(t87());
  total = total + 1; failed = failed + run_test(t88());
  total = total + 1; failed = failed + run_test(t89());
  total = total + 1; failed = failed + run_test(t90());
  total = total + 1; failed = failed + run_test(t91());
  total = total + 1; failed = failed + run_test(t92());
  total = total + 1; failed = failed + run_test(t93());
  total = total + 1; failed = failed + run_test(t94());
  total = total + 1; failed = failed + run_test(t95());
  total = total + 1; failed = failed + run_test(t96());
  total = total + 1; failed = failed + run_test(t97());
  total = total + 1; failed = failed + run_test(t98());

  let passed = total - failed;
  io.println("");
  io.println("XIOM UI: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
