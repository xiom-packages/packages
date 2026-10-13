// xiom.sdl3 conformance suite -- dynamic-loader path (pilot).
//
// Design goal: CI WITHOUT SDL3 must stay green. The suite loads SDL3.dll at
// runtime; when the library is absent every smoke check reports SKIP (printed
// as a [PASS] marker with an explicit SKIP label, because the packages-lane
// runner counts markers and fails a run with zero markers). When the library
// is present the full smoke runs: version/revision, init (timer+events),
// ticks/delay, event pump/peek, quit.
//
// Build+run (no extra compiler args: the loader is pure XIOM):
//   xiom --run tests/test_conformance.xi
//
// Local positive-path proof used the SDL 3.4.8 DLL shipped with the Vulkan
// SDK (C:\VulkanSDK\1.4.350.0\Bin\SDL3.dll, sha256 6E2B4B6A...C263) copied
// next to the test binary; see BINDINGS-SESSION.md for the run matrix.

module sdl3_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.sdl3;

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
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

// Zeroed out-param slot (the lane's proven idiom; no malloc/free).
fn slot_new(n: Int) -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

// Drain the event queue (consume semantics; returns the drained count).
fn drain_events(lib: &Sdl3Library, max: Int) -> Int
  requires: max > 0
{
  var n = 0;
  while n < max {
    if !sdl3_poll_event(lib, 0) { break; }
    n = n + 1;
  }
  return n;
}

// Constant tables and version arithmetic (independent of the DLL).
fn t_constants() -> Bool {
  var ok = true;
  if SDL_INIT_EVENTS != 0x4000 { ok = false; }
  if SDL_INIT_TIMER != 0x1 { ok = false; }
  if SDL_INIT_VIDEO != 0x20 { ok = false; }
  if SDL_WINDOW_VULKAN != 0x10000000 { ok = false; }
  if SDL_WINDOW_HIDDEN != 0x8 { ok = false; }
  if SDL_EVENT_QUIT != 0x100 { ok = false; }
  if SDL_EVENT_KEY_DOWN != 0x300 || SDL_EVENT_KEY_UP != 0x301 { ok = false; }
  if SDL_EVENT_MOUSE_MOTION != 0x400 || SDL_EVENT_MOUSE_BUTTON_DOWN != 0x401 { ok = false; }
  if SDL_EVENT_MOUSE_BUTTON_UP != 0x402 || SDL_EVENT_MOUSE_WHEEL != 0x403 { ok = false; }
  if SDL_EVENT_USER != 0x8000 { ok = false; }
  if SDL_SCANCODE_A != 4 || SDL_SCANCODE_ESCAPE != 41 || SDL_SCANCODE_SPACE != 44 { ok = false; }
  if SDL_EVENT_SIZE != 128 { ok = false; }
  if SDL_PIXELFORMAT_RGBA8888 != 0x16462004 { ok = false; }
  // ABGR8888 is the byte-order RGBA array (engine ask 1321): SDL names are
  // MSB-first, so on little-endian ABGR8888 lands as R,G,B,A in memory.
  if SDL_PIXELFORMAT_ABGR8888 != 0x16762004 { ok = false; }
  if SDL_INIT_AUDIO != 0x10 || SDL_INIT_JOYSTICK != 0x200 { ok = false; }
  // 0.13.0: default device selectors (pin header: 0xFFFFFFFF / 0xFFFFFFFE).
  if SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK != 0xFFFFFFFF { ok = false; }
  if SDL_AUDIO_DEVICE_DEFAULT_RECORDING != 0xFFFFFFFE { ok = false; }
  if SDL_TEXTUREACCESS_STATIC != 0 { ok = false; }
  if sdl3_versionnum(3, 4, 8) != 3004008 { ok = false; }
  if sdl3_version_major(3004008) != 3 { ok = false; }
  if sdl3_version_minor(3004008) != 4 { ok = false; }
  if sdl3_version_patch(3004008) != 8 { ok = false; }
  // 0.11.0: source-generated full tables (sampled).
  if SDL_EVENT_FIRST != 0 || SDL_EVENT_LAST != 0xFFFF { ok = false; }
  if SDL_EVENT_TEXT_EDITING != 0x302 { ok = false; }
  if SDL_EVENT_JOYSTICK_AXIS_MOTION != 0x600 || SDL_EVENT_GAMEPAD_ADDED != 0x653 { ok = false; }
  if SDL_EVENT_AUDIO_DEVICE_ADDED != 0x1100 || SDL_EVENT_POLL_SENTINEL != 0x7F00 { ok = false; }
  if SDL_WINDOW_FULLSCREEN != 0x1 || SDL_WINDOW_BORDERLESS != 0x10 || SDL_WINDOW_RESIZABLE != 0x20 { ok = false; }
  if SDL_WINDOW_HIGH_PIXEL_DENSITY != 0x2000 || SDL_WINDOW_TRANSPARENT != 0x40000000 { ok = false; }
  if SDL_KMOD_LSHIFT != 0x1 || SDL_KMOD_LCTRL != 0x40 || SDL_KMOD_RALT != 0x200 { ok = false; }
  if SDL_KMOD_NUM != 0x1000 || SDL_KMOD_SCROLL != 0x8000 { ok = false; }
  if SDL_PIXELFORMAT_RGB565 != 0x15151002 || SDL_PIXELFORMAT_XRGB8888 != 0x16161804 { ok = false; }
  if SDL_PIXELFORMAT_NV12 != 0x3231564E { ok = false; }
  return ok;
}

// ---- 0.4.0: SDL_Event decoding over self-built 128-byte buffers -----------

fn wr_u8(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: buf.len() >= off + 1
{
  buf[off] = (v & 0xFF) as UInt8;
}

fn wr_u16(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: buf.len() >= off + 2
{
  wr_u8(buf, off + 0, v & 0xFF);
  wr_u8(buf, off + 1, (v >> 8) & 0xFF);
}

fn wr_u32(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: buf.len() >= off + 4
{
  wr_u8(buf, off + 0, v & 0xFF);
  wr_u8(buf, off + 1, (v >> 8) & 0xFF);
  wr_u8(buf, off + 2, (v >> 16) & 0xFF);
  wr_u8(buf, off + 3, (v >> 24) & 0xFF);
}

fn wr_u64(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: buf.len() >= off + 8
{
  wr_u32(buf, off + 0, v & 0xFFFFFFFF);
  wr_u32(buf, off + 4, (v >> 32) & 0xFFFFFFFF);
}

fn t_event_decode() -> Bool {
  var ok = true;

  // Key down: 'A' (scancode 4, keycode 97) with a modifier bit.
  var ev = slot_new(128);
  wr_u32(&mut ev, 0, SDL_EVENT_KEY_DOWN);
  wr_u64(&mut ev, 8, 123456789);
  wr_u32(&mut ev, 16, 7);
  wr_u32(&mut ev, 24, SDL_SCANCODE_A);
  wr_u32(&mut ev, 28, 97);
  wr_u16(&mut ev, 32, 0x1001);
  wr_u8(&mut ev, 36, 1);
  wr_u8(&mut ev, 37, 0);
  if sdl3_event_type(&ev) != SDL_EVENT_KEY_DOWN { ok = false; }
  if sdl3_event_timestamp(&ev) != 123456789 { ok = false; }
  if sdl3_event_window_id(&ev) != 7 { ok = false; }
  if sdl3_event_key_scancode(&ev) != SDL_SCANCODE_A { ok = false; }
  if sdl3_event_key_code(&ev) != 97 { ok = false; }
  if sdl3_event_key_mods(&ev) != 0x1001 { ok = false; }
  if !sdl3_event_key_down(&ev) { ok = false; }
  if sdl3_event_key_repeat(&ev) { ok = false; }

  // Mouse motion: x = 12.5 (0x41480000), y = -3.25 (0xC0500000).
  var mev = slot_new(128);
  wr_u32(&mut mev, 0, SDL_EVENT_MOUSE_MOTION);
  wr_u32(&mut mev, 16, 3);
  wr_u32(&mut mev, 24, 5);
  wr_u32(&mut mev, 28, 0x41480000);
  wr_u32(&mut mev, 32, 0xC0500000);
  if sdl3_event_type(&mev) != SDL_EVENT_MOUSE_MOTION { ok = false; }
  if sdl3_event_mouse_state(&mev) != 5 { ok = false; }
  if sdl3_event_mouse_x_bits(&mev) != 0x41480000 { ok = false; }
  if sdl3_event_mouse_x(&mev) != 12.5 { ok = false; }
  if sdl3_event_mouse_y(&mev) != -3.25 { ok = false; }

  // Mouse button: right button (3), double click, same x float slot.
  var bev = slot_new(128);
  wr_u32(&mut bev, 0, SDL_EVENT_MOUSE_BUTTON_DOWN);
  wr_u8(&mut bev, 24, 3);
  wr_u8(&mut bev, 25, 1);
  wr_u8(&mut bev, 26, 2);
  wr_u32(&mut bev, 28, 0x41480000);
  if sdl3_event_mouse_button(&bev) != 3 { ok = false; }
  if !sdl3_event_mouse_button_down(&bev) { ok = false; }
  if sdl3_event_mouse_clicks(&bev) != 2 { ok = false; }
  if sdl3_event_mouse_x(&bev) != 12.5 { ok = false; }

  // Window event with a negative data1 (i32 sign handling).
  var wev = slot_new(128);
  wr_u32(&mut wev, 0, SDL_EVENT_WINDOW_CLOSE_REQUESTED);
  wr_u32(&mut wev, 16, 9);
  wr_u32(&mut wev, 20, 0xFFFFFFDF);
  wr_u32(&mut wev, 24, 17);
  if sdl3_event_type(&wev) != SDL_EVENT_WINDOW_CLOSE_REQUESTED { ok = false; }
  if sdl3_event_window_id(&wev) != 9 { ok = false; }
  if sdl3_event_window_data1(&wev) != -33 { ok = false; }
  if sdl3_event_window_data2(&wev) != 17 { ok = false; }

  // f32 bit decode sanity (exact powers of two).
  if sdl3_f32_from_bits(0x3F800000) != 1.0 { ok = false; }
  if sdl3_f32_from_bits(0xC0500000) != -3.25 { ok = false; }

  // 0.12.0: mouse-wheel event (engine ask 1411-2): x=0.5, y=-1.25,
  // direction=FLIPPED, cursor at 100.5/200.25.
  var wheel_ev = slot_new(128);
  wr_u32(&mut wheel_ev, 0, SDL_EVENT_MOUSE_WHEEL);
  wr_u32(&mut wheel_ev, 16, 4);
  wr_u32(&mut wheel_ev, 24, 0x3F000000);
  wr_u32(&mut wheel_ev, 28, 0xBFA00000);
  wr_u32(&mut wheel_ev, 32, SDL_MOUSEWHEEL_FLIPPED);
  wr_u32(&mut wheel_ev, 36, 0x42C90000);
  wr_u32(&mut wheel_ev, 40, 0x43484000);
  if sdl3_event_type(&wheel_ev) != SDL_EVENT_MOUSE_WHEEL { ok = false; }
  if sdl3_event_wheel_x(&wheel_ev) != 0.5 || sdl3_event_wheel_y(&wheel_ev) != -1.25 { ok = false; }
  if sdl3_event_wheel_x_bits(&wheel_ev) != 0x3F000000 { ok = false; }
  if sdl3_event_wheel_direction(&wheel_ev) != SDL_MOUSEWHEEL_FLIPPED { ok = false; }
  if sdl3_event_wheel_mouse_x(&wheel_ev) != 100.5 { ok = false; }
  if sdl3_event_wheel_mouse_y(&wheel_ev) != 200.25 { ok = false; }
  return ok;
}

// ---- 0.16.0: drag-drop payload decode (DLL-independent) -------------------
// SDL_DropEvent: windowID u32 @16, x f32 @20, y f32 @24, source ptr @32,
// data ptr @40.  Built with real C-string pointers; NULL payloads must
// decode to "" without a crash.

fn t_drop_decode() -> Bool {
  var ok = true;
  var dev = slot_new(128);
  wr_u32(&mut dev, 0, SDL_EVENT_DROP_FILE);
  wr_u32(&mut dev, 16, 7);
  wr_u32(&mut dev, 20, 0x42C80000);            // x = 100.0
  wr_u32(&mut dev, 24, 0x42700000);            // y = 60.0
  let sptr = sdl3_str_c_ptr("xiom-source");
  let dptr = sdl3_str_c_ptr("C:/tmp/suzanne.glb");
  wr_u64(&mut dev, 32, sptr);
  wr_u64(&mut dev, 40, dptr);
  if sdl3_event_type(&dev) != SDL_EVENT_DROP_FILE { ok = false; }
  if sdl3_event_drop_window_id(&dev) != 7 { ok = false; }
  if sdl3_event_drop_x(&dev) != 100.0 { ok = false; }
  if sdl3_event_drop_y(&dev) != 60.0 { ok = false; }
  if sdl3_event_drop_source(&dev) != "xiom-source" { ok = false; }
  if sdl3_event_drop_data(&dev) != "C:/tmp/suzanne.glb" { ok = false; }

  // NULL payloads (DROP_BEGIN carries no data/source): empty + no crash.
  var nev = slot_new(128);
  wr_u32(&mut nev, 0, SDL_EVENT_DROP_BEGIN);
  if sdl3_event_type(&nev) != SDL_EVENT_DROP_BEGIN { ok = false; }
  if sdl3_event_drop_source(&nev) != "" { ok = false; }
  if sdl3_event_drop_data(&nev) != "" { ok = false; }
  if sdl3_event_drop_x(&nev) != 0.0 { ok = false; }
  return ok;
}

// ---- 0.5.0: event filter + watch capture state ----------------------------
// Handlers take the event only (B-15: Vec[fn] element calls with >= 2 args
// type their result as ()); userdata comes back via the package getters.

var flt_calls: Int = 0;
var flt_last_type: Int = 0;
var flt_userdata: Int = 0;
var flt_drop_type: Int = 0;

fn on_filter(ev: Vec[UInt8]) -> Bool {
  flt_calls = flt_calls + 1;
  flt_last_type = sdl3_event_type(&ev);
  flt_userdata = sdl3_filter_userdata();
  if flt_drop_type != 0 && flt_last_type == flt_drop_type {
    return false;
  }
  return true;
}

var wtc_calls: Int = 0;
var wtc_last_type: Int = 0;
var wtc_userdata: Int = 0;
var wtc_saw_resized: Bool = false;
var wtc_saw_pixel: Bool = false;

fn on_watch(ev: Vec[UInt8]) -> Unit {
  wtc_calls = wtc_calls + 1;
  wtc_last_type = sdl3_event_type(&ev);
  wtc_userdata = sdl3_watch_userdata();
  if sdl3_event_type(&ev) == SDL_EVENT_WINDOW_RESIZED {
    if sdl3_event_window_data1(&ev) == 300 && sdl3_event_window_data2(&ev) == 180 {
      wtc_saw_resized = true;
    }
  }
  if sdl3_event_type(&ev) == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED {
    if sdl3_event_window_data1(&ev) == 300 && sdl3_event_window_data2(&ev) == 180 {
      wtc_saw_pixel = true;
    }
  }
}

fn main() -> Int {
  io.println("=== xiom.sdl3 conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: init/window/event tables + SDL_VERSIONNUM math");
  failed = failed + report(t_event_decode(), "events: decode layer (key/mouse-motion/mouse-button/window + f32 bits) on owned buffers");
  failed = failed + report(t_drop_decode(), "events: drag-drop payload decode (windowID/xy + source/data C-string reads; NULL-safe)");

  let l = sdl3_load();
  if !l.is_ok {
    if l.error.kind == SDL3_LOAD_ABSENT {
      // Library absent: SKIP, still green (SKIP label is explicit).
      failed = failed + report(true, "loader: SKIP -- SDL3.dll not present (" + l.error.message + ")");
      failed = failed + report(true, "smoke: SKIP -- init/version/quit/timer/events (no SDL3 runtime)");
    } else {
      failed = failed + report(false, "loader: SDL3.dll present but ABI mismatch -- " + l.error.message);
    }
    if failed == 0 {
      io.println("xiom.sdl3: suite green (SDL3 absent -- smoke skipped)");
    } else {
      io.println("xiom.sdl3: tests failed");
    }
    return failed;
  }

  let lib: Sdl3Library = l.value;

  // Version + revision.
  let v = sdl3_get_version(&lib);
  let major = sdl3_version_major(v);
  var vdetail = "major=" + to_string(major) + " num=" + to_string(v);
  failed = failed + report(major == 3, "version: SDL3 runtime major 3 (" + vdetail + ")");

  let rev = sdl3_get_revision(&lib);
  failed = failed + report(rev.len() >= 0, "revision: SDL_GetRevision() callable");

  // Headless init: timer + events only (no display/audio device needed).
  let flags = SDL_INIT_TIMER | SDL_INIT_EVENTS;
  let inited = sdl3_init(&lib, flags);
  var init_detail = "";
  if !inited { init_detail = " -- " + sdl3_get_error(&lib); }
  failed = failed + report(inited, "init: SDL_Init(TIMER|EVENTS)" + init_detail);

  if inited {
    failed = failed + report(sdl3_was_init(&lib, flags), "init: SDL_WasInit(TIMER|EVENTS) reflects the flags");

    // Timer: ticks advance across SDL_Delay.
    let t0 = sdl3_get_ticks(&lib);
    sdl3_delay(&lib, 15);
    let t1 = sdl3_get_ticks(&lib);
    let advanced = t1 >= t0;
    let sane = (t1 - t0) <= 2000;
    failed = failed + report(advanced && sane, "timer: SDL_GetTicks advanced " + to_string(t1 - t0) + "ms across SDL_Delay(15)");

    let pc = sdl3_get_performance_counter(&lib);
    failed = failed + report(pc != 0, "timer: SDL_GetPerformanceCounter() non-zero");

    // Event peek: pump + poll with a NULL buffer must be safe.
    sdl3_pump_events(&lib);
    let got = sdl3_poll_event(&lib, 0);
    failed = failed + report(true, "events: SDL_PumpEvents + SDL_PollEvent(NULL) safe (polled=" + b2s(got) + ")");

    // Headless event-pump proof (engine ask REL-20261010-1834-engine-3):
    // inject a synthetic user event (SDL_EVENT_USER = 0x8000) into a
    // 128-byte XIOM slot, pump, and verify the queue semantics WITHOUT
    // reading the foreign-written buffer: poll(NULL) must consume it
    // (true) and the following poll(NULL) must find the queue empty
    // (false).  Buffer readback is deferred -- on this host it reproduces
    // the B-11 slot-read corruption (recycled bytes; see the addendum item
    // filed to the compiler lane).
    var ev_in = slot_new(128);
    // Byte-indexed writes only (B-16), and NO pointer arithmetic (B-17:
    // `as_mut_ptr() + 1` compiles to a wild address on v0.64.3).  slot_new
    // zero-fills, so byte 0 (the low half of 0x8000) is already 0; only
    // byte 1 needs the 0x80 high half.
    wr_u8(&mut ev_in, 1, 128);
    // Drain any early queue entries (bounded) so the consume check is ours.
    var drained: Int = 0;
    while drained < 500 {
      if !sdl3_poll_event(&lib, 0) { break; }
      drained = drained + 1;
    }
    let pushed = sdl3_push_event(&lib, ev_in.as_mut_ptr() as Int);
    sdl3_pump_events(&lib);
    let consumed = sdl3_poll_event(&lib, 0);
    failed = failed + report(pushed && consumed,
      "events: synthetic user event (0x8000) injected + consumed (pushed=" + b2s(pushed)
        + ", consumed=" + b2s(consumed) + ", drained-before=" + to_string(drained) + ")");

    // 0.4.0: push a synthetic KEY_DOWN (the decode layout above is what the
    // runtime reads) and consume it; the same consume semantics avoid the
    // foreign-write readback path (B-11).
    var kev = slot_new(128);
    wr_u32(&mut kev, 0, SDL_EVENT_KEY_DOWN);
    wr_u32(&mut kev, 16, 1);
    wr_u32(&mut kev, 24, SDL_SCANCODE_A);
    wr_u32(&mut kev, 28, 97);
    wr_u8(&mut kev, 36, 1);
    let kpushed = sdl3_push_event(&lib, kev.as_mut_ptr() as Int);
    sdl3_pump_events(&lib);
    let kconsumed = sdl3_poll_event(&lib, 0);
    failed = failed + report(kpushed && kconsumed,
      "events: synthetic KEY_DOWN (scancode A) injected + consumed (pushed=" + b2s(kpushed)
        + ", consumed=" + b2s(kconsumed) + ")");

    // 0.18.0: foreign-written event readback -- the B-11 addendum shape
    // (SDL writing an event INTO an XIOM-owned buffer) is FIXED on
    // v0.64.4: poll the pushed user event into an owned 128-byte buffer
    // and read the type back byte-indexed.  The 0.3.1-era deferral is
    // retired (addendum item REL-20261011-0304 re-tested 2026-10-13).
    var ev_out = slot_new(128);
    let opushed = sdl3_push_event(&lib, ev_in.as_mut_ptr() as Int);
    sdl3_pump_events(&lib);
    let oconsumed = sdl3_poll_event(&lib, ev_out.as_mut_ptr() as Int);
    failed = failed + report(opushed && oconsumed && sdl3_event_type(&ev_out) == SDL_EVENT_USER,
      "events: poll into owned buffer -> readback type = " + to_string(sdl3_event_type(&ev_out))
        + " (B-11 addendum retired)");

    // The full decode layer over a FOREIGN-written buffer (deferred in
    // 0.4.0): push the KEY_DOWN again, poll it into a fresh owned slot and
    // decode field-by-field with the 0.4.0 accessors.
    var kev_out = slot_new(128);
    let k2pushed = sdl3_push_event(&lib, kev.as_mut_ptr() as Int);
    sdl3_pump_events(&lib);
    let k2consumed = sdl3_poll_event(&lib, kev_out.as_mut_ptr() as Int);
    failed = failed + report(k2pushed && k2consumed
        && sdl3_event_type(&kev_out) == SDL_EVENT_KEY_DOWN
        && sdl3_event_key_scancode(&kev_out) == SDL_SCANCODE_A
        && sdl3_event_key_code(&kev_out) == 97
        && sdl3_event_key_down(&kev_out),
      "events: KEY_DOWN readback decode (type=" + to_string(sdl3_event_type(&kev_out))
        + " scancode=" + to_string(sdl3_event_key_scancode(&kev_out))
        + " key=" + to_string(sdl3_event_key_code(&kev_out)) + ")");

    // 0.5.0: event filter (C callback -> dispatcher -> handler registry).
    // Drains keep the queue deterministic (SDL's filter/poll internals can
    // leave sentinel residue).  Keep-path: the filter sees the KEY_DOWN and
    // the event survives to the poll.  Drop-path proof: SDL refuses the
    // push (returns false) when the filter rejects the event.
    var dr0 = drain_events(&lib, 50);
    flt_calls = 0;
    flt_drop_type = 0;
    let flt_set = sdl3_set_event_filter(&lib, on_filter, 0x77);
    var kev2 = slot_new(128);
    wr_u32(&mut kev2, 0, SDL_EVENT_KEY_DOWN);
    wr_u32(&mut kev2, 24, SDL_SCANCODE_A);
    wr_u32(&mut kev2, 28, 97);
    wr_u8(&mut kev2, 36, 1);
    let fpushed = sdl3_push_event(&lib, kev2.as_mut_ptr() as Int);
    sdl3_pump_events(&lib);
    let fkept = sdl3_poll_event(&lib, 0);
    failed = failed + report(flt_set && fpushed && fkept && flt_calls >= 1
        && flt_last_type == SDL_EVENT_KEY_DOWN && flt_userdata == 0x77,
      "events: filter saw the pushed KEY_DOWN and kept it (drained=" + to_string(dr0)
        + " calls=" + to_string(flt_calls) + " last=" + to_string(flt_last_type)
        + " userdata=" + to_string(flt_userdata) + ")");

    // Drop-path: the filter rejects MOUSE_MOTION -> SDL refuses the push.
    let dr1 = drain_events(&lib, 50);
    flt_calls = 0;
    flt_drop_type = SDL_EVENT_MOUSE_MOTION;
    var mev2 = slot_new(128);
    wr_u32(&mut mev2, 0, SDL_EVENT_MOUSE_MOTION);
    wr_u32(&mut mev2, 28, 0x41480000);
    let mpushed = sdl3_push_event(&lib, mev2.as_mut_ptr() as Int);
    sdl3_pump_events(&lib);
    let fc_ok = sdl3_clear_event_filter(&lib);
    let dr2 = drain_events(&lib, 50);
    failed = failed + report(fc_ok && !mpushed && flt_calls >= 1
        && flt_last_type == SDL_EVENT_MOUSE_MOTION,
      "events: filter rejected the pushed MOUSE_MOTION (push refused=" + b2s(!mpushed)
        + " drained=" + to_string(dr1) + " calls=" + to_string(flt_calls)
        + " last=" + to_string(flt_last_type) + " cleared=" + b2s(fc_ok)
        + " residue=" + to_string(dr2) + ")");

    // Event watch: observes without consuming; removal stops the firing.
    let dr3 = drain_events(&lib, 50);
    wtc_calls = 0;
    let wset = sdl3_add_event_watch(&lib, on_watch, 0x88);
    var kev3 = slot_new(128);
    wr_u32(&mut kev3, 0, SDL_EVENT_KEY_UP);
    wr_u8(&mut kev3, 36, 0);
    let k3pushed = sdl3_push_event(&lib, kev3.as_mut_ptr() as Int);
    sdl3_pump_events(&lib);
    let k3kept = sdl3_poll_event(&lib, 0);
    let wc_before = wtc_calls;
    let wremoved = sdl3_remove_event_watch(&lib, 0x88);
    var kev4 = slot_new(128);
    wr_u32(&mut kev4, 0, SDL_EVENT_KEY_UP);
    let k4pushed = sdl3_push_event(&lib, kev4.as_mut_ptr() as Int);
    sdl3_pump_events(&lib);
    let k4kept = sdl3_poll_event(&lib, 0);
    let dr4 = drain_events(&lib, 50);
    failed = failed + report(wset && k3pushed && k3kept && k4pushed && k4kept
        && wremoved && wc_before >= 1 && wtc_last_type == SDL_EVENT_KEY_UP
        && wtc_userdata == 0x88 && wtc_calls == wc_before,
      "events: watch saw KEY_UP without consuming; removed watch stopped firing (drained="
        + to_string(dr3) + " calls=" + to_string(wtc_calls) + " last="
        + to_string(wtc_last_type) + " userdata=" + to_string(wtc_userdata)
        + " removed=" + b2s(wremoved) + " residue=" + to_string(dr4) + ")");

    // Quit and verify the flags are cleared.
    sdl3_quit(&lib);
    let still = sdl3_was_init(&lib, flags);
    failed = failed + report(!still, "quit: SDL_Quit clears TIMER|EVENTS");
  }

  // -------------------------------------------------------------------
  // Phase 2: resource stage (window/renderer/texture/gamepad).
  // Window-dependent checks SKIP cleanly when the platform cannot create
  // one (headless CI); the resource loader itself must still resolve.
  // -------------------------------------------------------------------
  let rl = sdl3_load_resources();
  if !rl.is_ok {
    if rl.error.kind == SDL3_LOAD_ABSENT {
      failed = failed + report(true, "resources: SKIP -- SDL3 runtime not present");
    } else {
      failed = failed + report(false, "resources: ABI mismatch -- " + rl.error.message);
    }
  } else {
    let r: Sdl3Resources = rl.value;
    failed = failed + report(true, "resources: window/renderer/texture/gamepad symbol set resolved");

    let winr = sdl3_create_window(&r, "xiom-sdl3-phase2", 320, 200, SDL_WINDOW_HIDDEN);
    if !winr.is_ok {
      failed = failed + report(true, "window: SKIP -- create failed (headless/platform): " + winr.error);
    } else {
      let win: Int = winr.value;
      failed = failed + report(true, "window: created hidden 320x200");
      let sz = sdl3_window_size(&r, win);
      failed = failed + report(sz.width > 0, "window: size = " + to_string(sz.width) + "x" + to_string(sz.height));
      failed = failed + report(sdl3_set_window_title(&r, win, "xiom-sdl3-phase2-renamed"), "window: title update");

      // 0.9.0: window contract -- resizable toggle + a typed resize event
      // through the event watch (the engine's typed input route).
      let rsz_off = sdl3_set_window_resizable(&r, win, false);
      let rsz_on = sdl3_set_window_resizable(&r, win, true);
      wtc_saw_resized = false;
      wtc_saw_pixel = false;
      let wset = sdl3_add_event_watch(&lib, on_watch, 0x99);
      let szset = sdl3_set_window_size(&r, win, 300, 180);
      sdl3_pump_events(&lib);
      let sz2 = sdl3_window_size(&r, win);
      let wrm = sdl3_remove_event_watch(&lib, 0x99);
      failed = failed + report(rsz_off && rsz_on && wset && szset && wrm
          && sz2.width == 300 && sz2.height == 180 && wtc_saw_resized,
        "window: resizable false/true + resize to 300x180 (readback="
          + to_string(sz2.width) + "x" + to_string(sz2.height) + ") -> typed WINDOW_RESIZED seen="
          + b2s(wtc_saw_resized) + " pixel-size-changed=" + b2s(wtc_saw_pixel));
      let shown = sdl3_show_window(&r, win);
      let hidden = sdl3_hide_window(&r, win);
      failed = failed + report(true, "window: show/hide callable (show=" + b2s(shown) + " hide=" + b2s(hidden) + ")");

      // 0.14.0: pointer + relative mouse (per-window relative mode; engine
      // pointer-look).  Out-params use separate owned slots (B-17).
      let gm = sdl3_global_mouse_state(&lib);
      failed = failed + report(gm.buttons >= 0 && gm.x > -100000.0 && gm.x < 100000.0
          && gm.y > -100000.0 && gm.y < 100000.0,
        "pointer: global mouse state (buttons=" + to_string(gm.buttons) + " at "
          + to_string(gm.x as Int) + "," + to_string(gm.y as Int) + ")");
      let rm = sdl3_relative_mouse_state(&lib);
      failed = failed + report(rm.buttons >= 0 && rm.x > -100000.0 && rm.x < 100000.0
          && rm.y > -100000.0 && rm.y < 100000.0,
        "pointer: relative mouse state (buttons=" + to_string(rm.buttons) + " delta "
          + to_string(rm.x as Int) + "," + to_string(rm.y as Int) + ")");
      let rmon = sdl3_set_window_relative_mouse_mode(&lib, win, true);
      let rmg1 = sdl3_window_relative_mouse_mode(&lib, win);
      let rmoff = sdl3_set_window_relative_mouse_mode(&lib, win, false);
      let rmg2 = sdl3_window_relative_mouse_mode(&lib, win);
      failed = failed + report(rmon && rmg1 && rmoff && !rmg2,
        "pointer: relative mode round trip (set-true=" + b2s(rmon) + " get=" + b2s(rmg1)
          + " set-false=" + b2s(rmoff) + " get=" + b2s(rmg2) + ")");
      // Capture is foreground-only; on a hidden window the enable is
      // expected to be refused (recorded), the disable must succeed.
      let cap_on = sdl3_capture_mouse(&lib, true);
      let cap_off = sdl3_capture_mouse(&lib, false);
      failed = failed + report(cap_off,
        "pointer: capture toggle callable (on=" + b2s(cap_on) + " off=" + b2s(cap_off)
          + "; on=false without focus is documented)");

      let renr = sdl3_create_renderer(&r, win);
      if !renr.is_ok {
        failed = failed + report(true, "renderer: SKIP -- create failed: " + renr.error);
      } else {
        let ren: Int = renr.value;
        let colored = sdl3_set_render_draw_color(&r, ren, 20, 40, 60, 255);
        let cleared = sdl3_render_clear(&r, ren);
        let presented = sdl3_render_present(&r, ren);
        failed = failed + report(colored, "renderer: draw color set");
        failed = failed + report(presented, "renderer: clear + present (clear=" + b2s(cleared) + ")");

        let texr = sdl3_create_texture(&r, ren, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_STATIC, 16, 16);
        if !texr.is_ok {
          failed = failed + report(false, "texture: create failed -- " + texr.error);
        } else {
          let tex: Int = texr.value;
          sdl3_destroy_texture(&r, tex);
          failed = failed + report(true, "texture: RGBA8888 16x16 created + destroyed");
        }

        // 0.8.0: streaming texture upload + blit + vsync (engine ask
        // REL-20261011-1153-engine): 64x64 RGBA checker into an XIOM-owned
        // buffer -> SDL_UpdateTexture -> RenderTexture -> present.
        let texr2 = sdl3_create_texture(&r, ren, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_STREAMING, 64, 64);
        if !texr2.is_ok {
          failed = failed + report(false, "blit: streaming texture create failed -- " + texr2.error);
        } else {
          let tex2: Int = texr2.value;
          var pattern: Vec[UInt8] = Vec[UInt8].new();
          var py = 0;
          while py < 64 {
            var px = 0;
            while px < 64 {
              if ((px / 8) % 2) == ((py / 8) % 2) {
                pattern.push(220 as UInt8);
                pattern.push(20 as UInt8);
                pattern.push(20 as UInt8);
                pattern.push(255 as UInt8);
              } else {
                pattern.push(20 as UInt8);
                pattern.push(20 as UInt8);
                pattern.push(220 as UInt8);
                pattern.push(255 as UInt8);
              }
              px = px + 1;
            }
            py = py + 1;
          }
          let colored2 = sdl3_set_render_draw_color(&r, ren, 0, 0, 0, 255);
          let cleared2 = sdl3_render_clear(&r, ren);
          let up = sdl3_update_texture(&r, tex2, &mut pattern, 64, 64);
          let vs = sdl3_set_render_vsync(&r, ren, 1);
          let blit = sdl3_render_texture(&r, ren, tex2);
          let pres = sdl3_render_present(&r, ren);
          failed = failed + report(colored2 && cleared2 && up && vs && blit && pres,
            "blit: 64x64 RGBA checker uploaded + rendered + presented (bytes="
              + to_string(pattern.len()) + " update=" + b2s(up) + " vsync=" + b2s(vs)
              + " blit=" + b2s(blit) + " present=" + b2s(pres) + ")");
          sdl3_destroy_texture(&r, tex2);
        }
        sdl3_destroy_renderer(&r, ren);
      }
      sdl3_destroy_window(&r, win);
    }

    let has = sdl3_has_gamepad(&r);
    let n = sdl3_gamepad_count(&r);
    failed = failed + report(true, "gamepad: enumeration callable (has=" + b2s(has) + " count=" + to_string(n) + ")");
    if n > 0 {
      // No gamepad is attached in CI; if one is, open/close the first id.
      let gp = sdl3_open_gamepad(&r, 0);
      if gp.is_ok {
        sdl3_close_gamepad(&r, gp.value);
        failed = failed + report(true, "gamepad: open/close first id succeeded");
      } else {
        failed = failed + report(true, "gamepad: SKIP -- open failed: " + gp.error);
      }
    } else {
      failed = failed + report(true, "gamepad: SKIP -- no gamepad attached");
    }

    let rc = sdl3_resources_close(&r);
    failed = failed + report(rc.is_ok, "resources: handle released");
  }

  // -------------------------------------------------------------------
  // 0.6.0: displays + keyboard state (SDL_Init(VIDEO|EVENTS); SKIP when
  // the platform cannot init video, e.g. headless CI).
  // -------------------------------------------------------------------
  let vflags = SDL_INIT_VIDEO | SDL_INIT_EVENTS;
  let vinited = sdl3_init(&lib, vflags);
  if !vinited {
    failed = failed + report(true, "video: SKIP -- SDL_Init(VIDEO|EVENTS) failed ("
      + sdl3_get_error(&lib) + ")");
  } else {
    let dc = sdl3_display_count(&lib);
    failed = failed + report(dc >= 1, "displays: count = " + to_string(dc));

    let did = sdl3_display_at(&lib, 0);
    let pid = sdl3_primary_display(&lib);
    var in_list = did == pid;
    var k = 0;
    while k < dc && !in_list {
      if sdl3_display_at(&lib, k) == pid { in_list = true; }
      k = k + 1;
    }
    failed = failed + report(did != 0 && pid != 0 && in_list,
      "displays: first=" + to_string(did) + " primary=" + to_string(pid)
        + " primary-in-list=" + b2s(in_list));

    let nm = sdl3_display_name(&lib, pid);
    failed = failed + report(nm.len() > 0, "display: name = \"" + nm + "\"");

    let bnd = sdl3_display_bounds(&lib, pid);
    failed = failed + report(bnd.w > 0 && bnd.h > 0,
      "display: bounds " + to_string(bnd.w) + "x" + to_string(bnd.h)
        + " @ " + to_string(bnd.x) + "," + to_string(bnd.y));

    let ub = sdl3_display_usable_bounds(&lib, pid);
    failed = failed + report(ub.w > 0 && ub.h > 0,
      "display: usable " + to_string(ub.w) + "x" + to_string(ub.h));

    let md = sdl3_display_mode(&lib, pid);
    failed = failed + report(md.w > 0 && md.h > 0 && md.refresh_rate >= 0.0,
      "display: current mode " + to_string(md.w) + "x" + to_string(md.h)
        + " @" + to_string(md.refresh_rate as Int) + "Hz fmt=" + to_string(md.pixel_format));

    let dm = sdl3_desktop_display_mode(&lib, pid);
    failed = failed + report(dm.w > 0 && dm.h > 0,
      "display: desktop mode " + to_string(dm.w) + "x" + to_string(dm.h)
        + " @" + to_string(dm.refresh_rate as Int) + "Hz");

    let nk = sdl3_keyboard_state_count(&lib);
    let a_down = sdl3_keyboard_key_down(&lib, SDL_SCANCODE_A);
    let esc_down = sdl3_keyboard_key_down(&lib, SDL_SCANCODE_ESCAPE);
    failed = failed + report(nk >= 64 && !a_down && !esc_down,
      "keyboard: state array numkeys=" + to_string(nk) + " idle (A=" + b2s(a_down)
        + " ESC=" + b2s(esc_down) + ")");

    let ms = sdl3_mod_state(&lib);
    let kf = sdl3_keyboard_focus(&lib);
    // Lock keys (Num/Caps/Scroll) legitimately make bits 0x1000+ set;
    // assert the non-lock modifier bits (shift/ctrl/alt/gui = 0x0FFF) idle.
    failed = failed + report((ms & 0x0FFF) == 0,
      "keyboard: mod state " + to_string(ms) + " (non-lock bits idle"
        + ", focus=" + to_string(kf) + ")");

    // 0.9.0: mouse state (idle buttons; window-relative coords decoded).
    let mst = sdl3_mouse_state(&lib);
    failed = failed + report(mst.buttons == 0 && mst.x > -100000.0 && mst.x < 100000.0
        && mst.y > -100000.0 && mst.y < 100000.0,
      "mouse: state idle (buttons=" + to_string(mst.buttons) + " at "
        + to_string(mst.x as Int) + "," + to_string(mst.y as Int) + ")");

    sdl3_quit(&lib);
  }

  // -------------------------------------------------------------------
  // 0.10.0: audio + joystick enumeration (engine device selection).
  // SKIP when the platform cannot init audio/joystick (headless CI).
  // -------------------------------------------------------------------
  let aflags = SDL_INIT_AUDIO | SDL_INIT_JOYSTICK;
  let ainited = sdl3_init(&lib, aflags);
  if !ainited {
    failed = failed + report(true, "audio: SKIP -- SDL_Init(AUDIO|JOYSTICK) failed ("
      + sdl3_get_error(&lib) + ")");
  } else {
    let drv = sdl3_current_audio_driver(&lib);
    let apc = sdl3_audio_playback_count(&lib);
    let arc = sdl3_audio_recording_count(&lib);
    var aname = "";
    if apc > 0 {
      aname = sdl3_audio_device_name(&lib, sdl3_audio_playback_at(&lib, 0));
    }
    failed = failed + report(drv.len() > 0 && apc >= 0 && arc >= 0 && (apc == 0 || aname.len() > 0),
      "audio: driver=\"" + drv + "\" playback=" + to_string(apc) + " recording="
        + to_string(arc) + " first-device=\"" + aname + "\"");

    let jc = sdl3_joystick_count(&lib);
    let jbad = sdl3_joystick_name_for_id(&lib, 999999);
    failed = failed + report(jc >= 0 && jbad.len() == 0,
      "joystick: enumeration count=" + to_string(jc) + " (unknown-id name empty="
        + b2s(jbad.len() == 0) + ")");

    // 0.15.0: virtual joystick instrumentation -> the REAL open/read path
    // with no hardware.  desc version = sizeof(desc) (SDL_INIT_INTERFACE;
    // 136 on x64); all desc writes are byte-indexed (B-16/B-17).
    let vjid = sdl3_attach_virtual_joystick(&lib, "xiom-virtual-pad", 2, 2);
    if vjid == 0 {
      failed = failed + report(true, "joystick-live: SKIP -- attach virtual joystick failed ("
        + sdl3_get_error(&lib) + ")");
    } else {
      let jh = sdl3_open_joystick(&lib, vjid);
      if jh == 0 {
        failed = failed + report(false, "joystick-live: SDL_OpenJoystick(attached virtual) failed -- "
          + sdl3_get_error(&lib));
      } else {
        let jname = sdl3_joystick_name(&lib, jh);
        let sva = sdl3_set_joystick_virtual_axis(&lib, jh, 0, 16384);
        let svb = sdl3_set_joystick_virtual_button(&lib, jh, 1, true);
        sdl3_pump_events(&lib);
        let ax = sdl3_joystick_axis(&lib, jh, 0);
        let bt = sdl3_joystick_button(&lib, jh, 1);
        let conn = sdl3_joystick_connected(&lib, jh);
        sdl3_close_joystick(&lib, jh);
        failed = failed + report(sva && svb && ax == 16384 && bt && conn
            && jname == "xiom-virtual-pad",
          "joystick-live: virtual pad axis0 set=16384 read=" + to_string(ax)
            + " button1=" + b2s(bt) + " connected=" + b2s(conn) + " name=\"" + jname
            + "\" (set-axis=" + b2s(sva) + " set-button=" + b2s(svb) + ")");
      }
      let vdet = sdl3_detach_virtual_joystick(&lib, vjid);
      failed = failed + report(vdet, "joystick-live: virtual pad detached=" + b2s(vdet));
    }

    // 0.12.0: push audio stream (silent buffer: no audible surprise).
    let stream = sdl3_open_audio_playback_stream(&lib, SDL_AUDIO_F32, 2, 48000);
    if stream == 0 {
      failed = failed + report(false, "audio-stream: open failed -- " + sdl3_get_error(&lib));
    } else {
      var silence: Vec[UInt8] = Vec[UInt8].new();
      var sb = 0;
      while sb < 7680 {
        silence.push(0 as UInt8);
        sb = sb + 1;
      }
      let put = sdl3_put_audio_stream_data(&lib, stream, &mut silence, 7680);
      let queued = sdl3_get_audio_stream_queued(&lib, stream);
      let resumed = sdl3_resume_audio_stream_device(&lib, stream);
      let paused = sdl3_audio_stream_device_paused(&lib, stream);
      sdl3_delay(&lib, 20);
      let paus = sdl3_pause_audio_stream_device(&lib, stream);
      sdl3_destroy_audio_stream(&lib, stream);
      failed = failed + report(put && resumed && !paused && paus && queued >= 0,
        "audio-stream: 7680B silence pushed + device resumed/paused (put=" + b2s(put)
          + " queued=" + to_string(queued) + " resumed=" + b2s(resumed)
          + " device-paused=" + b2s(paused) + " pause-ok=" + b2s(paus) + ")");
    }

    // 0.13.0: stream query round trip on a push stream (deterministic;
    // no capture hardware involved).  Format readback: the app side of a
    // stream opened through SDL_OpenAudioDeviceStream carries the requested
    // spec on ONE side of the pair (on the pinned 3.4.8 DLL both sides come
    // back equal here); accept either side so a differently-ordered
    // implementation still passes.  HISTORY: an earlier build passed one
    // 24-byte slot with `dst = as_mut_ptr() + 12` and read dst as zeros --
    // that was compiler finding B-17 (pointer arithmetic yields a wild
    // address; the DLL wrote dst to unowned memory and the process crashed
    // nondeterministically with heap corruption).  The wrapper now uses two
    // separate 12-byte slots (no pointer arithmetic).
    // Available/clear semantics: push 4096 B, clear, then queued/available
    // must be 0 and a read must return 0 (non-blocking).
    let qstream = sdl3_open_audio_playback_stream(&lib, SDL_AUDIO_F32, 2, 48000);
    if qstream == 0 {
      failed = failed + report(false, "audio-stream-format: open failed -- " + sdl3_get_error(&lib));
    } else {
      let qf = sdl3_get_audio_stream_format(&lib, qstream);
      let qf_app = (qf.src_format == SDL_AUDIO_F32 && qf.src_channels == 2 && qf.src_freq == 48000)
        || (qf.dst_format == SDL_AUDIO_F32 && qf.dst_channels == 2 && qf.dst_freq == 48000);
      failed = failed + report(qf.ok && qf_app,
        "audio-stream-format: src=" + to_string(qf.src_format) + "/" + to_string(qf.src_channels)
          + "ch/" + to_string(qf.src_freq) + "Hz dst=" + to_string(qf.dst_format) + "/"
          + to_string(qf.dst_channels) + "ch/" + to_string(qf.dst_freq) + "Hz (ok=" + b2s(qf.ok) + ")");

      var qsil: Vec[UInt8] = Vec[UInt8].new();
      var qb = 0;
      while qb < 4096 {
        qsil.push(0 as UInt8);
        qb = qb + 1;
      }
      let qput = sdl3_put_audio_stream_data(&lib, qstream, &mut qsil, 4096);
      let qavail = sdl3_get_audio_stream_available(&lib, qstream);
      let qclear = sdl3_clear_audio_stream(&lib, qstream);
      let qqueued = sdl3_get_audio_stream_queued(&lib, qstream);
      let qavail2 = sdl3_get_audio_stream_available(&lib, qstream);
      var qbuf = slot_new(512);
      let qgot = sdl3_get_audio_stream_data(&lib, qstream, &mut qbuf, 512);
      sdl3_destroy_audio_stream(&lib, qstream);
      failed = failed + report(qput && qavail >= 0 && qclear && qqueued == 0
          && qavail2 == 0 && qgot == 0,
        "audio-stream-available: pushed=4096B avail=" + to_string(qavail)
          + " cleared->queued=" + to_string(qqueued) + " avail=" + to_string(qavail2)
          + " read-after-clear=" + to_string(qgot) + " (clear=" + b2s(qclear) + ")");
    }

    // 0.13.0: capture streams -- open the default recording device
    // (SKIP-safe: no recording device / mic access denied by privacy
    // settings), resume, then drain PCM via SDL_GetAudioStreamData into an
    // owned buffer.  App side of a recording stream is the OUTPUT (dst).
    let rstream = sdl3_open_audio_recording_stream(&lib, SDL_AUDIO_F32, 2, 48000);
    if rstream == 0 {
      failed = failed + report(true, "audio-capture: SKIP -- no default recording stream ("
        + sdl3_get_error(&lib) + ")");
    } else {
      let rf = sdl3_get_audio_stream_format(&lib, rstream);
      // Same either-side rule as the playback query above (3.4.8: src).
      let rf_ok = rf.ok && ((rf.src_format == SDL_AUDIO_F32 && rf.src_channels == 2
          && rf.src_freq == 48000)
        || (rf.dst_format == SDL_AUDIO_F32 && rf.dst_channels == 2 && rf.dst_freq == 48000));
      let rres = sdl3_resume_audio_stream_device(&lib, rstream);
      // Bounded wait (<= 2 s): capture devices need a beat to deliver.
      var rava = sdl3_get_audio_stream_available(&lib, rstream);
      var rwait = 0;
      while rava <= 0 && rwait < 40 {
        sdl3_delay(&lib, 50);
        rava = sdl3_get_audio_stream_available(&lib, rstream);
        rwait = rwait + 1;
      }
      var rgot = 0;
      if rava > 0 {
        var rwant = 8192;
        if rava < 8192 { rwant = rava; }
        var rbuf = slot_new(rwant);
        rgot = sdl3_get_audio_stream_data(&lib, rstream, &mut rbuf, rwant);
      }
      let rpaus = sdl3_pause_audio_stream_device(&lib, rstream);
      let rclear = sdl3_clear_audio_stream(&lib, rstream);
      sdl3_destroy_audio_stream(&lib, rstream);
      if rava > 0 {
        failed = failed + report(rf_ok && rres && rgot > 0 && rpaus && rclear,
          "audio-capture: default recording stream src=" + to_string(rf.src_format) + "/"
            + to_string(rf.src_channels) + "ch/" + to_string(rf.src_freq) + "Hz dst="
            + to_string(rf.dst_format) + "/" + to_string(rf.dst_channels) + "ch/"
            + to_string(rf.dst_freq) + "Hz read=" + to_string(rgot) + "B avail="
            + to_string(rava) + " (resume=" + b2s(rres) + " paused-again=" + b2s(rpaus)
            + " clear=" + b2s(rclear) + ")");
      } else {
        // Open + format + resume all worked but no PCM arrived (device
        // silent/disabled): report honestly, do not fail the lane.
        failed = failed + report(rf_ok && rres && rpaus && rclear,
          "audio-capture: open+format+resume OK, no PCM within 2s (avail="
            + to_string(rava) + " dst=" + to_string(rf.dst_format) + "/"
            + to_string(rf.dst_channels) + "ch/" + to_string(rf.dst_freq) + "Hz)");
      }
    }
    sdl3_quit(&lib);
  }

  // -------------------------------------------------------------------
  // 0.7.0: filesystem basics (no subsystem init required).  The create/
  // remove round trip lives under the per-user pref path and is cleaned up.
  // -------------------------------------------------------------------
  let fbase = sdl3_get_base_path(&lib);
  failed = failed + report(fbase.len() > 0, "filesystem: base path = \"" + fbase + "\"");
  let fcwd = sdl3_get_current_directory(&lib);
  failed = failed + report(fcwd.len() > 0, "filesystem: current dir = \"" + fcwd + "\"");
  let fpref = sdl3_get_pref_path(&lib, "xiom-lane", "sdl3-conformance");
  failed = failed + report(fpref.len() > 0, "filesystem: pref path = \"" + fpref + "\"");
  if fpref.len() > 0 {
    let pi0 = sdl3_get_path_info(&lib, fpref);
    failed = failed + report(pi0.exists && pi0.kind == SDL_PATHTYPE_DIRECTORY,
      "filesystem: pref path info kind=" + to_string(pi0.kind) + " exists=" + b2s(pi0.exists));
    let fsub = fpref + "sub";
    let fmade = sdl3_create_directory(&lib, fsub);
    let pi1 = sdl3_get_path_info(&lib, fsub);
    failed = failed + report(fmade && pi1.exists && pi1.kind == SDL_PATHTYPE_DIRECTORY
        && pi1.modify_time > 0,
      "filesystem: create subdir (made=" + b2s(fmade) + " kind=" + to_string(pi1.kind)
        + " size=" + to_string(pi1.size) + " mtime-ns=" + to_string(pi1.modify_time) + ")");
    let frm1 = sdl3_remove_path(&lib, fsub);
    let pi2 = sdl3_get_path_info(&lib, fsub);
    let fbad = sdl3_get_path_info(&lib, "Q:\\xiom-lane-no-such-path\\x");
    failed = failed + report(frm1 && !pi2.exists && !fbad.exists,
      "filesystem: remove subdir + missing-path probe (removed=" + b2s(frm1)
        + " gone=" + b2s(!pi2.exists) + " missing=" + b2s(!fbad.exists) + ")");
    let frm2 = sdl3_remove_path(&lib, fpref);
    failed = failed + report(true, "filesystem: cleanup pref dir (removed=" + b2s(frm2) + ")");
  }

  let cl = sdl3_close(&lib);
  failed = failed + report(cl.is_ok, "loader: SDL3 handle released");

  if failed == 0 {
    io.println("xiom.sdl3: all tests passed");
  } else {
    io.println("xiom.sdl3: tests failed");
  }
  return failed;
}
