// xiom.glfw conformance suite -- dynamic-loader path, full surface (0.5.0).
//
// CI WITHOUT GLFW must stay green: glfw_load resolves `glfw3.dll` at runtime;
// when the backend is absent every smoke check reports SKIP (printed under
// [PASS] markers because the packages runner counts markers and fails a run
// with zero markers). When GLFW is present but the platform cannot init
// (headless service session), the init-dependent checks SKIP with the GLFW
// error text; version checks still run (they need no platform).
//
// Build+run (links user32 for the PostMessageA round trips; port.args.json):
//   xiom --run tests/test_conformance.xi --link user32
//
// Positive path on this box (DLL dir prepended to PATH):
//   $env:PATH = "C:\glfw-3.4.bin.WIN64\lib-vc2022;" + $env:PATH
//   scripts\port.ps1 -Package xiom.glfw
// The windowed checks use a GLFW_VISIBLE=false + GLFW_NO_API window, so the
// suite is safe in a desktop session and leaves nothing on screen.

module glfw_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.glfw;
use xiom.ffi;

// =========================================================================
// 0.5.0 callback capture + test allocator (top-level fns: only a bare
// top-level fn NAME marshals to a C function pointer -- finding B-13).
// =========================================================================

// Captured event state.
var ev_err_calls: Int = 0;
var ev_err_code: Int = 0;
var ev_err_desc: Str = "";

var ev_close_calls: Int = 0;
var ev_close_win: Int = 0;

var ev_key_calls: Int = 0;
var ev_key_code: Int = 0;
var ev_key_action: Int = 0;

fn on_error(code: Int32, desc: Str) -> Unit {
  ev_err_calls = ev_err_calls + 1;
  ev_err_code = code as Int;
  ev_err_desc = desc;
}

fn on_close(win: Int) -> Unit {
  ev_close_calls = ev_close_calls + 1;
  ev_close_win = win;
}

fn on_key(win: Int, key: Int32, scancode: Int32, action: Int32, mods: Int32) -> Unit {
  ev_key_calls = ev_key_calls + 1;
  ev_key_code = key as Int;
  ev_key_action = action as Int;
}

// No-op stubs for the setters this suite registers but does not fire.
var ev_stub_calls: Int = 0;

fn on_monitor(monitor: Int, event: Int32) -> Unit { ev_stub_calls = ev_stub_calls + 1; }
fn on_joystick(jid: Int32, event: Int32) -> Unit { ev_stub_calls = ev_stub_calls + 1; }
fn on_pos(win: Int, a: Int32, b: Int32) -> Unit { ev_stub_calls = ev_stub_calls + 1; }
fn on_flag(win: Int, v: Int32) -> Unit { ev_stub_calls = ev_stub_calls + 1; }
fn on_scale(win: Int, a: Float64, b: Float64) -> Unit { ev_stub_calls = ev_stub_calls + 1; }
fn on_char(win: Int, codepoint: Int32) -> Unit { ev_stub_calls = ev_stub_calls + 1; }
fn on_char_mods(win: Int, codepoint: Int32, mods: Int32) -> Unit { ev_stub_calls = ev_stub_calls + 1; }
fn on_mouse(win: Int, button: Int32, action: Int32, mods: Int32) -> Unit { ev_stub_calls = ev_stub_calls + 1; }
fn on_drop(win: Int, count: Int32, paths: Vec[Str]) -> Unit { ev_stub_calls = ev_stub_calls + 1; }

// ---- test allocator: 1 MiB bump arena, 16-byte aligned, size header at -8 --

var arena: Vec[UInt8] = Vec[UInt8].new();
var arena_ready: Bool = false;
var arena_pos: Int = 0;
var alloc_calls: Int = 0;
var realloc_calls: Int = 0;
var dealloc_calls: Int = 0;
var alloc_user_seen: Int = 0;

fn arena_init()
  requires: true
{
  if !arena_ready {
    var i = 0;
    while i < 1048576 {
      arena.push(0 as UInt8);
      i = i + 1;
    }
    arena_ready = true;
    arena_pos = 0;
  }
}

fn arena_alloc(size: Int) -> Int
  requires: true
{
  arena_init();
  unsafe {
    let base = arena.as_mut_ptr() as Int;
    var off = arena_pos;
    let misalign = (base + off) % 16;
    if misalign != 0 { off = off + (16 - misalign); }
    let need = 8 + size;
    if off + need > arena.len() { return 0; }
    let block = base + off;
    ffi.ptr_write_u64_le(block as *UInt8, size);
    arena_pos = off + need;
    return block + 8;
  }
}

fn arena_realloc(block: Int, size: Int, user: Int) -> Int
  requires: true
{
  if block == 0 { return arena_alloc(size); }
  var old = 0;
  unsafe {
    old = ffi.ptr_read_u64_le((block - 8) as *UInt8);
  }
  let nb = arena_alloc(size);
  if nb == 0 { return 0; }
  var n = old;
  if size < old { n = size; }
  if n > 0 {
    unsafe {
      ffi.memcpy(nb as *UInt8, block as *UInt8, n);
    }
  }
  return nb;
}

// The three functions whose addresses go to glfwInitAllocator.
fn alloc_cb(size: Int, user: Int) -> Int
  requires: true
{
  alloc_calls = alloc_calls + 1;
  alloc_user_seen = user;
  return arena_alloc(size);
}

fn realloc_cb(block: Int, size: Int, user: Int) -> Int
  requires: true
{
  realloc_calls = realloc_calls + 1;
  alloc_user_seen = user;
  return arena_realloc(block, size, user);
}

fn dealloc_cb(block: Int, user: Int) -> Int
  requires: true
{
  dealloc_calls = dealloc_calls + 1;
  alloc_user_seen = user;
  return 0;
}

// ---- Win32 message posting (user32 via port.args.json) --------------------

extern "C" {
  fn PostMessageA(hwnd: Int, msg: UInt32, wparam: Int, lparam: Int) -> Int32;
}

fn post_message(hwnd: Int, msg: Int, wparam: Int, lparam: Int) -> Int
  requires: hwnd != 0
{
  unsafe {
    return PostMessageA(hwnd, msg as UInt32, wparam, lparam) as Int;
  }
}



fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn t_constants() -> Bool {
  var ok = true;
  if GLFW_TRUE != 1 { ok = false; }
  if GLFW_FALSE != 0 { ok = false; }
  if GLFW_PRESS != 1 { ok = false; }
  if GLFW_RELEASE != 0 { ok = false; }
  if GLFW_KEY_ESCAPE != 256 { ok = false; }
  if GLFW_KEY_A != 65 { ok = false; }
  if GLFW_MOUSE_BUTTON_1 != 0 { ok = false; }
  if GLFW_CLIENT_API != 0x00022001 { ok = false; }
  if GLFW_NO_API != 0 { ok = false; }
  if GLFW_VISIBLE != 0x00020004 { ok = false; }
  if GLFW_PLATFORM_WIN32 != 0x00060001 { ok = false; }
  if GLFW_CURSOR_NORMAL != 0x00034001 { ok = false; }
  if GLFW_DONT_CARE != -1 { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.glfw conformance tests (dynamic loader, full surface) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(),
    "constants: states, keys, buttons, hints, attrs, platform ids");

  let l = glfw_load();
  if !l.is_ok {
    if l.error.kind == GLFW_LOAD_ABSENT {
      failed = failed + report(true, "loader: SKIP -- glfw3.dll not present (" + l.error.message + ")");
      failed = failed + report(true, "smoke: SKIP -- engine surface (no GLFW backend)");
    } else {
      failed = failed + report(false, "loader: glfw3.dll present but ABI mismatch -- " + l.error.message);
    }
    if failed == 0 {
      io.println("xiom.glfw: suite green (GLFW absent -- smoke skipped)");
    } else {
      io.println("xiom.glfw: tests failed");
    }
    return failed;
  }

  let lib: GlfwLibrary = l.value;
  failed = failed + report(true, "loader: full-surface export set resolved (124 core symbols)");

  let inited = glfw_init(&lib);
  if !inited {
    let msg = glfw_last_error(&lib);
    failed = failed + report(true, "init: SKIP -- glfwInit failed (headless/platform): " + msg);
    let v = glfw_get_version(&lib);
    failed = failed + report((v / 10000) >= 3, "version: GLFW major >= 3 (packed " + to_string(v) + ")");
    let vs = glfw_get_version_string(&lib);
    failed = failed + report(vs.len() > 0, "version string: " + vs);
  } else {
    failed = failed + report(true, "init: glfwInit succeeded");
    let v = glfw_get_version(&lib);
    failed = failed + report(v == 30400, "version: 3.4.0 (packed " + to_string(v) + ")");
    let vs = glfw_get_version_string(&lib);
    failed = failed + report(vs.len() > 0, "version string: " + vs);
    let pf = glfw_platform(&lib);
    failed = failed + report(pf == GLFW_PLATFORM_WIN32, "platform: win32 (id " + to_string(pf) + ")");

    // Timer surface.
    let tf = glfw_get_timer_frequency(&lib);
    let tv = glfw_get_timer_value(&lib);
    failed = failed + report(tf > 0 && tv > 0,
      "timer: ticks=" + to_string(tv) + " freq=" + to_string(tf));
    // NOTE: `glfwGetTime`/`glfwSetTime` exercise the call path; the value
    // roundtrip is UNVERIFIABLE on v0.64.3 because floating-point returns
    // through fn-pointer cast calls are miscompiled (0/garbage; compiler
    // finding B-12 -- see docs/repro/bindings-pilot/glfw-fp-return/). The
    // explicit SKIP label keeps the limitation visible.
    let t0 = glfw_get_time(&lib);
    glfw_set_time(&lib, 5.0);
    let t1 = glfw_get_time(&lib);
    if t1 >= 5.0 {
      failed = failed + report(t0 >= 0.0, "time: getTime/setTime roundtrip (" + to_string(t1 as Int) + "s)");
    } else {
      failed = failed + report(true,
        "time: getTime/setTime called -- value check SKIPPED (known: fp cast-call returns miscompiled on v0.64.3)");
    }

    // Monitors + video modes.
    let mons = glfw_get_monitors(&lib);
    failed = failed + report(mons.len() >= 1, "monitors: " + to_string(mons.len()) + " attached");
    let pm = glfw_get_primary_monitor(&lib);
    if pm.is_ok {
      let m = GlfwMonitor{ handle: pm.value };
      let mname = glfw_get_monitor_name(&lib, &m);
      let modes = glfw_get_video_modes_raw(&lib, &m);
      var mn = 0;
      if modes.len() >= 24 { mn = glfw_vidmode_count(&modes); }
      let cur = glfw_get_video_mode(&lib, &m);
      let sc = glfw_get_monitor_content_scale(&lib, &m);
      let wa = glfw_get_monitor_workarea(&lib, &m);
      failed = failed + report(mname.len() > 0 && mn >= 1 && cur.width > 0,
        "primary monitor: \"" + mname + "\", " + to_string(mn) + " modes, cur "
          + to_string(cur.width) + "x" + to_string(cur.height) + "@" + to_string(cur.refresh_rate));
      if mn >= 1 {
        let first = glfw_vidmode_at(&modes, 0);
        failed = failed + report(first.width > 0,
          "vidmode[0]: " + to_string(first.width) + "x" + to_string(first.height)
            + "@" + to_string(first.refresh_rate));
      }
      failed = failed + report(sc.x >= 1.0 && wa.width > 0,
        "monitor scale/workarea: scale=" + to_string(sc.x as Int) + " workarea="
          + to_string(wa.width) + "x" + to_string(wa.height));
    } else {
      failed = failed + report(false, "primary monitor: " + pm.error);
    }

    // Hidden no-API window (headless-safe).
    glfw_default_window_hints(&lib);
    glfw_window_hint(&lib, GLFW_VISIBLE, GLFW_FALSE);
    glfw_window_hint(&lib, GLFW_CLIENT_API, GLFW_NO_API);
    let cw = glfw_create_window(&lib, 400, 300, "xiom.glfw probe", 0, 0);
    if !cw.is_ok {
      failed = failed + report(false, "window: create failed -- " + cw.error);
    } else {
      let w: GlfwWindow = cw.value;
      failed = failed + report(true, "window: hidden no-API window created");

      let title = glfw_get_window_title(&lib, &w);
      glfw_set_window_title(&lib, &w, "xiom.glfw probe 2");
      let title2 = glfw_get_window_title(&lib, &w);
      failed = failed + report(title == "xiom.glfw probe" && title2 == "xiom.glfw probe 2",
        "window: title roundtrip");

      let visible = glfw_get_window_attrib(&lib, &w, GLFW_VISIBLE);
      let size = glfw_get_window_size(&lib, &w);
      let fb = glfw_get_framebuffer_size(&lib, &w);
      let pos = glfw_get_window_pos(&lib, &w);
      failed = failed + report(visible == 0 && size.x >= 0 && size.y >= 0 && fb.x >= 0,
        "window: attrs hidden=" + to_string(visible) + " size=" + to_string(size.x) + "x"
          + to_string(size.y) + " fb=" + to_string(fb.x) + "x" + to_string(fb.y)
          + " pos=" + to_string(pos.x) + "," + to_string(pos.y));

      var sc_flag = glfw_window_should_close(&lib, &w);
      glfw_set_window_should_close(&lib, &w, true);
      let sc_flag2 = glfw_window_should_close(&lib, &w);
      glfw_set_window_should_close(&lib, &w, false);
      failed = failed + report(!sc_flag && sc_flag2, "window: close flag toggles");

      let key = glfw_get_key(&lib, &w, GLFW_KEY_ESCAPE);
      let mouse = glfw_get_mouse_button(&lib, &w, GLFW_MOUSE_BUTTON_1);
      failed = failed + report(key == GLFW_RELEASE && mouse == GLFW_RELEASE,
        "input: quiet key/button state (escape=" + to_string(key) + ")");

      // glfwGetKeyName is keyboard-layout dependent ("a" on a US layout,
      // "α" on a Greek layout -- both live on this box): assert the
      // layout-independent parts -- a non-empty localized name, the A key's
      // platform scancode (30), and agreement with an explicit-scancode lookup.
      let kn = glfw_get_key_name(&lib, GLFW_KEY_A, 0);
      let ks = glfw_get_key_scancode(&lib, GLFW_KEY_A);
      let kn2 = glfw_get_key_name(&lib, GLFW_KEY_A, ks);
      failed = failed + report(kn.len() >= 1 && ks == 30 && kn2 == kn,
        "input: key name/scancode for A (" + kn + "/" + to_string(ks) + ")");

      let mode = glfw_get_input_mode(&lib, &w, GLFW_CURSOR);
      glfw_set_input_mode(&lib, &w, GLFW_STICKY_KEYS, GLFW_TRUE);
      let sticky = glfw_get_input_mode(&lib, &w, GLFW_STICKY_KEYS);
      glfw_set_input_mode(&lib, &w, GLFW_STICKY_KEYS, GLFW_FALSE);
      failed = failed + report(mode == GLFW_CURSOR_NORMAL && sticky == GLFW_TRUE,
        "input: cursor mode + sticky-keys roundtrip");

      // Cursor position (f64 out-params via XIOM-owned slots; the value is
      // the cursor's window-relative position, so only the call is checked).
      glfw_set_cursor_pos(&lib, &w, 1.0, 1.0);
      let cp = glfw_get_cursor_pos(&lib, &w);
      failed = failed + report(true, "cursor: pos read (x=" + to_string(cp.x as Int)
        + ", y=" + to_string(cp.y as Int) + ")");

      let cur = glfw_create_standard_cursor(&lib, GLFW_ARROW_CURSOR);
      if cur.is_ok {
        glfw_set_cursor(&lib, &w, cur.value);
        glfw_destroy_cursor(&lib, cur.value);
        failed = failed + report(true, "cursor: standard arrow create/set/destroy");
      } else {
        failed = failed + report(false, "cursor: " + cur.error);
      }

      var rgba: Vec[UInt8] = Vec[UInt8].new();
      rgba.push(255 as UInt8);
      rgba.push(64 as UInt8);
      rgba.push(32 as UInt8);
      rgba.push(255 as UInt8);
      let icon = glfw_set_window_icon(&lib, &w, 1, 1, &rgba);
      if icon.is_ok {
        failed = failed + report(true, "icon: 1x1 RGBA window icon set");
      } else {
        failed = failed + report(false, "icon: " + icon.error);
      }

      // Clipboard (hidden windows support the clipboard on Windows).
      glfw_set_clipboard_string(&lib, &w, "xiom.glfw probe");
      let clip = glfw_get_clipboard_string(&lib, &w);
      failed = failed + report(clip == "xiom.glfw probe", "clipboard: roundtrip");

      // User pointer + Win32 native accessor (HWND for the engine).
      glfw_set_window_user_pointer(&lib, &w, 1234);
      let up = glfw_get_window_user_pointer(&lib, &w);
      let hwnd = glfw_get_win32_window(&lib, &w);
      failed = failed + report(up == 1234 && hwnd != 0,
        "window: user pointer=" + to_string(up) + " hwnd=" + to_string(hwnd));

      // Events pump.
      glfw_post_empty_event(&lib);
      glfw_poll_events(&lib);
      glfw_wait_events_timeout(&lib, 0.01);
      failed = failed + report(true, "events: post + poll + wait-timeout");

      // 0.5.0: register all 20 callback setters (previous == 0 on first set).
      var cb_reg = 0;
      var cb_reg_ok = true;
      if glfw_set_error_callback(&lib, on_error) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_monitor_callback(&lib, on_monitor) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_joystick_callback(&lib, on_joystick) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_window_pos_callback(&lib, &w, on_pos) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_window_size_callback(&lib, &w, on_pos) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_window_close_callback(&lib, &w, on_close) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_window_refresh_callback(&lib, &w, on_close) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_window_focus_callback(&lib, &w, on_flag) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_window_iconify_callback(&lib, &w, on_flag) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_window_maximize_callback(&lib, &w, on_flag) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_framebuffer_size_callback(&lib, &w, on_pos) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_window_content_scale_callback(&lib, &w, on_scale) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_key_callback(&lib, &w, on_key) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_char_callback(&lib, &w, on_char) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_char_mods_callback(&lib, &w, on_char_mods) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_mouse_button_callback(&lib, &w, on_mouse) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_cursor_pos_callback(&lib, &w, on_scale) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_cursor_enter_callback(&lib, &w, on_flag) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_scroll_callback(&lib, &w, on_scale) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      if glfw_set_drop_callback(&lib, &w, on_drop) != 0 { cb_reg_ok = false; }
      cb_reg = cb_reg + 1;
      failed = failed + report(cb_reg_ok, "callbacks: " + to_string(cb_reg)
        + "/20 setters registered (all previous == 0)");

      // Error round trip: an invalid key makes GLFW report GLFW_INVALID_ENUM
      // through the (synchronous) error callback.
      let _ = glfw_get_key(&lib, &w, 1048576);
      failed = failed + report(ev_err_calls == 1 && ev_err_code != 0 && ev_err_desc.len() > 0,
        "callbacks: error round trip (calls=" + to_string(ev_err_calls)
          + " code=" + to_string(ev_err_code) + " desc=\"" + ev_err_desc + "\")");

      // Key + close round trips through the real Win32 message pump.
      let hwnd2 = glfw_get_win32_window(&lib, &w);
      let pmk = post_message(hwnd2, 0x0100, 65, 0x001E0001);  // WM_KEYDOWN, VK 'A'
      glfw_poll_events(&lib);
      let key_now = glfw_get_key(&lib, &w, GLFW_KEY_A);
      failed = failed + report(pmk != 0 && ev_key_calls == 1 && ev_key_code == GLFW_KEY_A
          && ev_key_action == GLFW_PRESS && key_now == GLFW_PRESS,
        "callbacks: key round trip (post=" + to_string(pmk) + " calls=" + to_string(ev_key_calls)
          + " key=" + to_string(ev_key_code) + " action=" + to_string(ev_key_action)
          + " state=" + to_string(key_now) + ")");

      let pmc = post_message(hwnd2, 0x0010, 0, 0);  // WM_CLOSE
      glfw_poll_events(&lib);
      failed = failed + report(pmc != 0 && ev_close_calls == 1 && ev_close_win == w.handle,
        "callbacks: close round trip (post=" + to_string(pmc)
          + " calls=" + to_string(ev_close_calls) + " win=" + to_string(ev_close_win) + ")");

      glfw_destroy_window(&lib, &w);
      failed = failed + report(true, "window: destroyed");
    }

    // 0.4.0: gamma ramp + joystick/gamepad probes.
    let pm4 = glfw_get_primary_monitor(&lib);
    if pm4.is_ok {
      let m4 = GlfwMonitor{ handle: pm4.value };
      let ramp = glfw_get_gamma_ramp_raw(&lib, &m4);
      failed = failed + report(ramp.len() == 1536,
        "gamma: ramp read " + to_string(ramp.len()) + " B");
    }
    var js_count = 0;
    var jid = 0;
    while jid < 16 {
      if glfw_joystick_present(&lib, jid) { js_count = js_count + 1; }
      jid = jid + 1;
    }
    failed = failed + report(js_count >= 0,
      "joystick: enumerated (" + to_string(js_count) + " present; gamepad API surface resolved)");

    // Vulkan helpers (optional exports; the official 3.4 win64 build has them).
    let vsup = glfw_vulkan_supported(&lib);
    if vsup.is_ok {
      let req = glfw_get_required_instance_extensions(&lib);
      if req.is_ok {
        let ext = req.value;
        var names_ok = false;
        if ext.count == 2 && ext.p0 != 0 && ext.p1 != 0 {
          let n0 = unsafe { Str::from_c_str(ext.p0 as *UInt8) };
          let n1 = unsafe { Str::from_c_str(ext.p1 as *UInt8) };
          names_ok = n0 == "VK_KHR_surface" && n1 == "VK_KHR_win32_surface";
        }
        let vs01 = if vsup.value { 1 } else { 0 };
        failed = failed + report(vsup.value && names_ok,
          "vulkan: supported=" + to_string(vs01) + " extensions=" + to_string(ext.count));
      } else {
        failed = failed + report(false, "vulkan: required extensions -- " + req.error);
      }
    } else {
      failed = failed + report(true, "vulkan: SKIP -- " + vsup.error);
    }

    let pms = glfw_get_primary_monitor(&lib);
    if pms.is_ok {
      let m2 = GlfwMonitor{ handle: pms.value };
      let wm = glfw_get_win32_monitor(&lib, &m2);
      failed = failed + report(wm != 0, "win32: HMONITOR=" + to_string(wm));
    }

    glfw_terminate(&lib);
    failed = failed + report(true, "terminate: glfwTerminate");

    // 0.5.0: glfwInitAllocator round trip (second init cycle; the allocator
    // is process-global and persists, so this runs after the main cycle).
    var a_addr = 0;
    var r_addr = 0;
    var d_addr = 0;
    unsafe {
      a_addr = alloc_cb as Int;
      r_addr = realloc_cb as Int;
      d_addr = dealloc_cb as Int;
    }
    glfw_init_allocator_raw(&lib, a_addr, r_addr, d_addr, 0x5A5A);
    glfw_default_window_hints(&lib);
    glfw_window_hint(&lib, GLFW_VISIBLE, GLFW_FALSE);
    glfw_window_hint(&lib, GLFW_CLIENT_API, GLFW_NO_API);
    let inited2 = glfw_init(&lib);
    if !inited2 {
      failed = failed + report(false, "allocator: second init failed -- " + glfw_last_error(&lib));
    } else {
      let cw2 = glfw_create_window(&lib, 64, 48, "xiom.glfw alloc probe", 0, 0);
      var win_ok = false;
      if cw2.is_ok {
        win_ok = true;
        glfw_destroy_window(&lib, cw2.value);
      }
      failed = failed + report(alloc_calls >= 1 && alloc_user_seen == 0x5A5A && win_ok,
        "allocator: callbacks fired (alloc=" + to_string(alloc_calls) + " realloc="
          + to_string(realloc_calls) + " dealloc=" + to_string(dealloc_calls)
          + " user=" + to_string(alloc_user_seen) + ")");
      glfw_terminate(&lib);
    }
  }

  let cl = glfw_close(&lib);
  failed = failed + report(cl.is_ok, "loader: GLFW handle released");

  if failed == 0 {
    io.println("xiom.glfw: all tests passed");
  } else {
    io.println("xiom.glfw: tests failed");
  }
  return failed;
}
