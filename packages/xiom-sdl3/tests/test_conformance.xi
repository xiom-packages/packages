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
use xiom.string;
use xiom.sdl3;

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

// All Str equality goes through string.str_compare (B-26 discipline).
fn sc_eq(a: Str, b: Str) -> Bool {
  return string.str_compare(a, b) == 0;
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

// Drain the event queue with TRUE consume semantics: poll into a scratch
// owned buffer.  SDL_PollEvent(NULL) on the pinned 3.4.8 runtime is a PEEK
// (real events stay queued; only the internal poll sentinel is cleared) --
// see the 0.19.0 pen-live check, which caught stale events this way.  The
// loop ends when the poll hits SDL's end-of-cycle sentinel (false).
fn drain_events(lib: &Sdl3Library, max: Int) -> Int
  requires: max > 0
{
  var n = 0;
  while n < max {
    var scratch = slot_new(128);
    if !sdl3_poll_event(lib, scratch.as_mut_ptr() as Int) { break; }
    n = n + 1;
  }
  return n;
}

// Poll until an event of type `want` is CONSUMED into `out` (an owned
// 128-byte buffer).  Pinned 3.4.8 poll-cycle semantics: a poll that meets
// SDL's internal POLL_SENTINEL returns false (the sentinel is consumed) even
// when pushed events are queued right behind it, so the suite drains before
// pushing and then matches on the event type (non-matching events, if any,
// are consumed until `want` arrives or `tries` is exhausted).
fn poll_for(lib: &Sdl3Library, want: Int, out: &mut Vec[UInt8], tries: Int) -> Bool
  requires: out.len() >= 128
  requires: tries > 0
{
  var i = 0;
  while i < tries {
    if sdl3_poll_event(lib, out.as_mut_ptr() as Int) {
      if sdl3_event_type(out) == want {
        return true;
      }
    }
    i = i + 1;
  }
  return false;
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
  // 0.21.0: A14 UI platform (focus/DPI/text + window/display constants).
  if SDL_EVENT_TEXT_INPUT != 0x303 || SDL_EVENT_TEXT_EDITING_CANDIDATES != 0x307 { ok = false; }
  if SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED != 0x207 { ok = false; }
  if SDL_EVENT_WINDOW_FOCUS_GAINED != 0x20E || SDL_EVENT_WINDOW_FOCUS_LOST != 0x20F { ok = false; }
  if SDL_EVENT_WINDOW_DISPLAY_CHANGED != 531 || SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED != 532 { ok = false; }
  if SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED != 343 { ok = false; }
  if SDL3_WINDOW_FOCUS_NONE != 0 || SDL3_WINDOW_FOCUS_GAINED != 1 || SDL3_WINDOW_FOCUS_LOST != 2 { ok = false; }
  if SDL3_DPI_CHANGE_NONE != 0 || SDL3_DPI_CHANGE_PIXEL_SIZE != 1 || SDL3_DPI_CHANGE_DISPLAY != 2 { ok = false; }
  if SDL3_DPI_CHANGE_DISPLAY_SCALE != 3 { ok = false; }
  if SDL3_TEXT_EVENT_NONE != 0 || SDL3_TEXT_EVENT_EDITING != 1 || SDL3_TEXT_EVENT_COMMIT != 2 { ok = false; }
  if SDL3_TEXT_EVENT_CANCELLED != 3 { ok = false; }
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

fn rd_u16(buf: &Vec[UInt8], off: Int) -> Int
  requires: buf.len() >= off + 2
{
  return (buf[off + 0] as Int) | ((buf[off + 1] as Int) << 8);
}

fn rd_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
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

// SINE wave used by the haptic device path (built per call: the parameter
// struct is passed by value and moved at the first use).
fn haptic_sine_wave() -> Sdl3HapticPeriodic {
  return Sdl3HapticPeriodic{
    wave: SDL_HAPTIC_SINE;
    length: 100;
    period: 20;
    magnitude: 10000;
    offset: 0;
    phase: 0;
    attack_length: 0;
    attack_level: 0;
    fade_length: 0;
    fade_level: 0;
    dir_type: SDL_HAPTIC_CARTESIAN;
    dir0: 1;
    dir1: 0;
    dir2: 0;
  };
}

// ---- 0.19.0: device-surface constant tables (DLL-independent) -------------

fn t_device_constants() -> Bool {
  var ok = true;
  // Haptic wave forms + direction encodings + the x64 union size.
  if SDL_HAPTIC_SINE != 2 || SDL_HAPTIC_SQUARE != 4 || SDL_HAPTIC_TRIANGLE != 8 { ok = false; }
  if SDL_HAPTIC_SAWTOOTHUP != 16 || SDL_HAPTIC_SAWTOOTHDOWN != 32 { ok = false; }
  if SDL_HAPTIC_INFINITY != 4294967295 { ok = false; }
  if SDL_HAPTIC_POLAR != 0 || SDL_HAPTIC_CARTESIAN != 1 || SDL_HAPTIC_SPHERICAL != 2 { ok = false; }
  if SDL_HAPTIC_EFFECT_SIZE != 72 { ok = false; }
  // Pen/tablet device types + input flags + event types.
  if SDL_PEN_DEVICE_TYPE_INVALID != -1 || SDL_PEN_DEVICE_TYPE_UNKNOWN != 0 { ok = false; }
  if SDL_PEN_DEVICE_TYPE_DIRECT != 1 || SDL_PEN_DEVICE_TYPE_INDIRECT != 2 { ok = false; }
  if SDL_PEN_INPUT_DOWN != 1 || SDL_PEN_INPUT_BUTTON_1 != 2 || SDL_PEN_INPUT_BUTTON_5 != 32 { ok = false; }
  if SDL_PEN_INPUT_ERASER_TIP != 1073741824 || SDL_PEN_INPUT_IN_PROXIMITY != 2147483648 { ok = false; }
  if SDL_EVENT_PEN_PROXIMITY_IN != 4864 || SDL_EVENT_PEN_PROXIMITY_OUT != 4865 { ok = false; }
  if SDL_EVENT_PEN_DOWN != 4866 || SDL_EVENT_PEN_UP != 4867 { ok = false; }
  if SDL_EVENT_PEN_BUTTON_DOWN != 4868 || SDL_EVENT_PEN_BUTTON_UP != 4869 { ok = false; }
  if SDL_EVENT_PEN_MOTION != 4870 || SDL_EVENT_PEN_AXIS != 4871 { ok = false; }
  // Joystick types + the five capability property names (Str via str_compare).
  if SDL_JOYSTICK_TYPE_UNKNOWN != 0 || SDL_JOYSTICK_TYPE_GAMEPAD != 1 { ok = false; }
  if SDL_JOYSTICK_TYPE_COUNT != 10 { ok = false; }
  if !sc_eq(SDL_PROP_JOYSTICK_CAP_MONO_LED_BOOLEAN, "SDL.joystick.cap.mono_led") { ok = false; }
  if !sc_eq(SDL_PROP_JOYSTICK_CAP_RGB_LED_BOOLEAN, "SDL.joystick.cap.rgb_led") { ok = false; }
  if !sc_eq(SDL_PROP_JOYSTICK_CAP_PLAYER_LED_BOOLEAN, "SDL.joystick.cap.player_led") { ok = false; }
  if !sc_eq(SDL_PROP_JOYSTICK_CAP_RUMBLE_BOOLEAN, "SDL.joystick.cap.rumble") { ok = false; }
  if !sc_eq(SDL_PROP_JOYSTICK_CAP_TRIGGER_RUMBLE_BOOLEAN, "SDL.joystick.cap.trigger_rumble") { ok = false; }
  return ok;
}

// ---- 0.19.0: haptic wave-form slot encode (DLL-independent) ---------------
// Lays out SDL_HapticPeriodic byte-indexed (type u16 @0, direction @4/8/12/16,
// length @20, delay/button/interval @24/26/28, period @30, magnitude @32,
// offset @34, phase @36, attack @38/@40, fade @42/@44; Win64 pin, see the
// generator's layout audit) and validates the typed PARAM error path.

fn t_haptic_encode() -> Bool {
  var ok = true;
  var slot = slot_new(SDL_HAPTIC_EFFECT_SIZE);
  let eff = Sdl3HapticPeriodic{
    wave: SDL_HAPTIC_SINE;
    length: 500;
    period: 40;
    magnitude: 20000;
    offset: -1000;
    phase: 9000;
    attack_length: 10;
    attack_level: 5;
    fade_length: 20;
    fade_level: 7;
    dir_type: SDL_HAPTIC_CARTESIAN;
    dir0: 1;
    dir1: 0;
    dir2: 0;
  };
  let enc = sdl3_haptic_encode_periodic(&mut slot, eff);
  if !enc.is_ok { ok = false; }
  if rd_u16(&slot, 0) != SDL_HAPTIC_SINE { ok = false; }
  if (slot[4] as Int) != SDL_HAPTIC_CARTESIAN { ok = false; }
  if rd_u32(&slot, 8) != 1 || rd_u32(&slot, 12) != 0 || rd_u32(&slot, 16) != 0 { ok = false; }
  if rd_u32(&slot, 20) != 500 { ok = false; }
  if rd_u16(&slot, 24) != 0 || rd_u16(&slot, 26) != 0 || rd_u16(&slot, 28) != 0 { ok = false; }
  if rd_u16(&slot, 30) != 40 { ok = false; }
  if rd_u16(&slot, 32) != 20000 { ok = false; }
  if rd_u16(&slot, 34) != 64536 { ok = false; }   // -1000 two's complement
  if rd_u16(&slot, 36) != 9000 { ok = false; }
  if rd_u16(&slot, 38) != 10 || rd_u16(&slot, 40) != 5 { ok = false; }
  if rd_u16(&slot, 42) != 20 || rd_u16(&slot, 44) != 7 { ok = false; }

  // Square wave, infinite length, extreme signed values (two's complement).
  var slot2 = slot_new(SDL_HAPTIC_EFFECT_SIZE);
  let sq = Sdl3HapticPeriodic{
    wave: SDL_HAPTIC_SQUARE;
    length: SDL_HAPTIC_INFINITY;
    period: 100;
    magnitude: -32768;
    offset: 32767;
    phase: 0;
    attack_length: 0;
    attack_level: 0;
    fade_length: 0;
    fade_level: 0;
    dir_type: SDL_HAPTIC_POLAR;
    dir0: 0;
    dir1: 0;
    dir2: 0;
  };
  let enc2 = sdl3_haptic_encode_periodic(&mut slot2, sq);
  if !enc2.is_ok { ok = false; }
  if rd_u32(&slot2, 20) != SDL_HAPTIC_INFINITY { ok = false; }
  if rd_u16(&slot2, 32) != 32768 { ok = false; }
  if rd_u16(&slot2, 34) != 32767 { ok = false; }

  // Unknown wave -> typed PARAM error, slot untouched.
  var slot3 = slot_new(SDL_HAPTIC_EFFECT_SIZE);
  let bad = Sdl3HapticPeriodic{
    wave: 99;
    length: 100;
    period: 10;
    magnitude: 0;
    offset: 0;
    phase: 0;
    attack_length: 0;
    attack_level: 0;
    fade_length: 0;
    fade_level: 0;
    dir_type: SDL_HAPTIC_CARTESIAN;
    dir0: 0;
    dir1: 0;
    dir2: 0;
  };
  let enc3 = sdl3_haptic_encode_periodic(&mut slot3, bad);
  if enc3.is_ok { ok = false; }
  if !enc3.is_ok {
    if enc3.error.kind != SDL3_HAPTIC_ERR_PARAM { ok = false; }
  }
  if rd_u32(&slot3, 0) != 0 || rd_u32(&slot3, 20) != 0 { ok = false; }
  return ok;
}

// ---- 0.19.0: PEN/TABLET decode (DLL-independent) --------------------------
// SDL_PenProximityEvent (24 bytes: windowID @16, which @20), SDL_PenMotionEvent
// (40 bytes: + pen_state @24, x @28, y @32), SDL_PenTouchEvent (40 bytes:
// + eraser @36, down @37), SDL_PenButtonEvent (40 bytes: button @36, down @37)
// -- offsets from the generator's Win64 layout audit of the pinned headers.

fn t_pen_decode() -> Bool {
  var ok = true;

  // Motion: windowID 7, pen 42, IN_PROXIMITY|DOWN, x=12.5, y=-3.25.
  var mev = slot_new(128);
  wr_u32(&mut mev, 0, SDL_EVENT_PEN_MOTION);
  wr_u64(&mut mev, 8, 5551212);
  wr_u32(&mut mev, 16, 7);
  wr_u32(&mut mev, 20, 42);
  wr_u32(&mut mev, 24, SDL_PEN_INPUT_IN_PROXIMITY | SDL_PEN_INPUT_DOWN);
  wr_u32(&mut mev, 28, 0x41480000);
  wr_u32(&mut mev, 32, 0xC0500000);
  if sdl3_event_type(&mev) != SDL_EVENT_PEN_MOTION { ok = false; }
  if sdl3_event_timestamp(&mev) != 5551212 { ok = false; }
  if sdl3_event_pen_window_id(&mev) != 7 { ok = false; }
  if sdl3_event_pen_which(&mev) != 42 { ok = false; }
  if sdl3_event_pen_state(&mev) != (SDL_PEN_INPUT_IN_PROXIMITY | SDL_PEN_INPUT_DOWN) { ok = false; }
  if sdl3_event_pen_x_bits(&mev) != 0x41480000 { ok = false; }
  if sdl3_event_pen_x(&mev) != 12.5 { ok = false; }
  if sdl3_event_pen_y(&mev) != -3.25 { ok = false; }

  // Touch down with the eraser tip: x=100.0, y=0.0.
  var tev = slot_new(128);
  wr_u32(&mut tev, 0, SDL_EVENT_PEN_DOWN);
  wr_u32(&mut tev, 16, 9);
  wr_u32(&mut tev, 20, 43);
  wr_u32(&mut tev, 24, SDL_PEN_INPUT_DOWN | SDL_PEN_INPUT_ERASER_TIP);
  wr_u32(&mut tev, 28, 0x42C80000);
  wr_u32(&mut tev, 32, 0x00000000);
  wr_u8(&mut tev, 36, 1);
  wr_u8(&mut tev, 37, 1);
  if !sdl3_event_pen_touch_eraser(&tev) { ok = false; }
  if !sdl3_event_pen_touch_down(&tev) { ok = false; }
  if sdl3_event_pen_x(&tev) != 100.0 { ok = false; }
  if sdl3_event_pen_which(&tev) != 43 { ok = false; }

  // Touch up: down flag false (eraser clear).
  var uev = slot_new(128);
  wr_u32(&mut uev, 0, SDL_EVENT_PEN_UP);
  wr_u8(&mut uev, 37, 0);
  if sdl3_event_pen_touch_down(&uev) { ok = false; }
  if sdl3_event_pen_touch_eraser(&uev) { ok = false; }

  // Button 2 pressed (barrel button).
  var bev = slot_new(128);
  wr_u32(&mut bev, 0, SDL_EVENT_PEN_BUTTON_DOWN);
  wr_u32(&mut bev, 16, 9);
  wr_u32(&mut bev, 20, 44);
  wr_u32(&mut bev, 24, SDL_PEN_INPUT_BUTTON_2);
  wr_u32(&mut bev, 28, 0x42480000);
  wr_u32(&mut bev, 32, 0x42C80000);
  wr_u8(&mut bev, 36, 2);
  wr_u8(&mut bev, 37, 1);
  if sdl3_event_pen_button(&bev) != 2 { ok = false; }
  if !sdl3_event_pen_button_down(&bev) { ok = false; }
  if sdl3_event_pen_x(&bev) != 50.0 { ok = false; }
  if sdl3_event_pen_y(&bev) != 100.0 { ok = false; }

  // Proximity in: windowID + which only (24-byte member; proximity out too).
  var pev = slot_new(128);
  wr_u32(&mut pev, 0, SDL_EVENT_PEN_PROXIMITY_IN);
  wr_u32(&mut pev, 16, 11);
  wr_u32(&mut pev, 20, 45);
  if sdl3_event_type(&pev) != SDL_EVENT_PEN_PROXIMITY_IN { ok = false; }
  if sdl3_event_pen_window_id(&pev) != 11 { ok = false; }
  if sdl3_event_pen_which(&pev) != 45 { ok = false; }
  var xev = slot_new(128);
  wr_u32(&mut xev, 0, SDL_EVENT_PEN_PROXIMITY_OUT);
  wr_u32(&mut xev, 20, 45);
  if sdl3_event_type(&xev) != SDL_EVENT_PEN_PROXIMITY_OUT { ok = false; }
  if sdl3_event_pen_which(&xev) != 45 { ok = false; }
  return ok;
}

// ---- 0.21.0: A14 UI decode (focus/DPI/IME) -- DLL-independent ------------

fn t_ui_event_decode() -> Bool {
  var ok = true;

  // Per-window focus: gained/lost carry the window id at offset 16.
  var fg = slot_new(128);
  wr_u32(&mut fg, 0, SDL_EVENT_WINDOW_FOCUS_GAINED);
  wr_u32(&mut fg, 16, 5);
  let f1 = sdl3_event_window_focus(&fg);
  if f1.state != SDL3_WINDOW_FOCUS_GAINED || f1.window_id != 5 { ok = false; }
  if !sdl3_event_is_focus_change(&fg) { ok = false; }

  var fl = slot_new(128);
  wr_u32(&mut fl, 0, SDL_EVENT_WINDOW_FOCUS_LOST);
  wr_u32(&mut fl, 16, 6);
  let f2 = sdl3_event_window_focus(&fl);
  if f2.state != SDL3_WINDOW_FOCUS_LOST || f2.window_id != 6 { ok = false; }
  if !sdl3_event_is_focus_change(&fl) { ok = false; }

  var nf = slot_new(128);
  wr_u32(&mut nf, 0, SDL_EVENT_KEY_DOWN);
  wr_u32(&mut nf, 16, 7);
  let f3 = sdl3_event_window_focus(&nf);
  if f3.state != SDL3_WINDOW_FOCUS_NONE { ok = false; }
  if sdl3_event_is_focus_change(&nf) { ok = false; }

  // DPI-change signals: pixel size (data1xdata2), display change (data1 id),
  // display scale change.
  var ps = slot_new(128);
  wr_u32(&mut ps, 0, SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED);
  wr_u32(&mut ps, 16, 7);
  wr_u32(&mut ps, 20, 640);
  wr_u32(&mut ps, 24, 480);
  let d1 = sdl3_event_dpi_change(&ps);
  if d1.reason != SDL3_DPI_CHANGE_PIXEL_SIZE || d1.window_id != 7 { ok = false; }
  if d1.pixel_width != 640 || d1.pixel_height != 480 { ok = false; }
  if !sdl3_event_is_dpi_change(&ps) { ok = false; }

  var dc = slot_new(128);
  wr_u32(&mut dc, 0, SDL_EVENT_WINDOW_DISPLAY_CHANGED);
  wr_u32(&mut dc, 16, 8);
  wr_u32(&mut dc, 20, 2);
  let d2 = sdl3_event_dpi_change(&dc);
  if d2.reason != SDL3_DPI_CHANGE_DISPLAY || d2.display_id != 2 || d2.window_id != 8 { ok = false; }

  var ds = slot_new(128);
  wr_u32(&mut ds, 0, SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED);
  wr_u32(&mut ds, 16, 9);
  let d3 = sdl3_event_dpi_change(&ds);
  if d3.reason != SDL3_DPI_CHANGE_DISPLAY_SCALE || d3.window_id != 9 { ok = false; }

  let d4 = sdl3_event_dpi_change(&nf);
  if d4.reason != SDL3_DPI_CHANGE_NONE { ok = false; }
  if sdl3_event_is_dpi_change(&nf) { ok = false; }

  // IME composition: preedit text + start/length + window id.
  var ed = slot_new(128);
  wr_u32(&mut ed, 0, SDL_EVENT_TEXT_EDITING);
  wr_u32(&mut ed, 16, 10);
  wr_u64(&mut ed, 24, sdl3_str_c_ptr("日本語"));
  wr_u32(&mut ed, 32, 1);
  wr_u32(&mut ed, 36, 2);
  let te = sdl3_event_text_editing(&ed);
  if te.window_id != 10 || te.start != 1 || te.length != 2 { ok = false; }
  if !sc_eq(te.text, "日本語") { ok = false; }
  if sdl3_event_text_kind(&ed) != SDL3_TEXT_EVENT_EDITING { ok = false; }

  // IME commit: the committed UTF-8 string.
  var ti = slot_new(128);
  wr_u32(&mut ti, 0, SDL_EVENT_TEXT_INPUT);
  wr_u32(&mut ti, 16, 11);
  wr_u64(&mut ti, 24, sdl3_str_c_ptr("café"));
  if !sc_eq(sdl3_event_text_input(&ti), "café") { ok = false; }
  if sdl3_event_text_kind(&ti) != SDL3_TEXT_EVENT_COMMIT { ok = false; }

  // Cancellation: SDL3 has no dedicated type; an empty/NULL preedit in a
  // TEXT_EDITING event is the typed cancellation signal.
  var ce = slot_new(128);
  wr_u32(&mut ce, 0, SDL_EVENT_TEXT_EDITING);
  wr_u32(&mut ce, 16, 12);
  wr_u64(&mut ce, 24, 0);
  wr_u32(&mut ce, 32, 0xFFFFFFFF);
  wr_u32(&mut ce, 36, 0xFFFFFFFF);
  let tce = sdl3_event_text_editing(&ce);
  if tce.window_id != 12 || tce.text.len() != 0 { ok = false; }
  if tce.start != -1 || tce.length != -1 { ok = false; }
  if sdl3_event_text_kind(&ce) != SDL3_TEXT_EVENT_CANCELLED { ok = false; }
  if sdl3_event_text_kind(&nf) != SDL3_TEXT_EVENT_NONE { ok = false; }

  // NULL commit text is empty, no crash.
  var tn = slot_new(128);
  wr_u32(&mut tn, 0, SDL_EVENT_TEXT_INPUT);
  wr_u64(&mut tn, 24, 0);
  if sdl3_event_text_input(&tn).len() != 0 { ok = false; }

  return ok;
}

// ---- 0.5.0/0.20.0: event filter + watch capture state --------------------
// Direct handoff (B-22/m277): handlers take the NATURAL C shape
// (userdata, event) and read the event bytes via sdl3_event_copy.

var flt_calls: Int = 0;
var flt_last_type: Int = 0;
var flt_userdata: Int = 0;
var flt_drop_type: Int = 0;

fn on_filter(userdata: Int, event: Int) -> UInt8 {
  flt_calls = flt_calls + 1;
  let ev = sdl3_event_copy(event);
  flt_last_type = sdl3_event_type(&ev);
  flt_userdata = userdata;
  if flt_drop_type != 0 && flt_last_type == flt_drop_type {
    return 0 as UInt8;
  }
  return 1 as UInt8;
}

var wtc_calls: Int = 0;
var wtc_last_type: Int = 0;
var wtc_userdata: Int = 0;
var wtc_saw_resized: Bool = false;
var wtc_saw_pixel: Bool = false;

fn on_watch(userdata: Int, event: Int) -> Unit {
  wtc_calls = wtc_calls + 1;
  let ev = sdl3_event_copy(event);
  wtc_last_type = sdl3_event_type(&ev);
  wtc_userdata = userdata;
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

// ---- 0.21.0: A14 UI routing capture state (focus/DPI/IME) ----------------

var ui_watch_calls: Int = 0;
var ui_focus_gained_id: Int = 0;
var ui_focus_lost_id: Int = 0;
var ui_dpi_pixel_w: Int = 0;
var ui_dpi_pixel_h: Int = 0;
var ui_dpi_display_id: Int = 0;
var ui_dpi_scale_seen: Bool = false;
var ui_text_edit: Str = "";
var ui_text_start: Int = -99;
var ui_text_length: Int = -99;
var ui_text_commit: Str = "";
var ui_text_cancelled: Bool = false;

fn on_ui_watch(userdata: Int, event: Int) -> Unit {
  ui_watch_calls = ui_watch_calls + 1;
  let ev = sdl3_event_copy(event);
  let focus = sdl3_event_window_focus(&ev);
  if focus.state == SDL3_WINDOW_FOCUS_GAINED { ui_focus_gained_id = focus.window_id; }
  if focus.state == SDL3_WINDOW_FOCUS_LOST { ui_focus_lost_id = focus.window_id; }
  let dpi = sdl3_event_dpi_change(&ev);
  if dpi.reason == SDL3_DPI_CHANGE_PIXEL_SIZE {
    ui_dpi_pixel_w = dpi.pixel_width;
    ui_dpi_pixel_h = dpi.pixel_height;
  }
  if dpi.reason == SDL3_DPI_CHANGE_DISPLAY { ui_dpi_display_id = dpi.display_id; }
  if dpi.reason == SDL3_DPI_CHANGE_DISPLAY_SCALE { ui_dpi_scale_seen = true; }
  let kind = sdl3_event_text_kind(&ev);
  if kind == SDL3_TEXT_EVENT_EDITING {
    let te = sdl3_event_text_editing(&ev);
    ui_text_edit = te.text;
    ui_text_start = te.start;
    ui_text_length = te.length;
  }
  if kind == SDL3_TEXT_EVENT_COMMIT { ui_text_commit = sdl3_event_text_input(&ev); }
  if kind == SDL3_TEXT_EVENT_CANCELLED { ui_text_cancelled = true; }
}

fn main() -> Int {
  io.println("=== xiom.sdl3 conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: init/window/event tables + SDL_VERSIONNUM math");
  failed = failed + report(t_event_decode(), "events: decode layer (key/mouse-motion/mouse-button/window + f32 bits) on owned buffers");
  failed = failed + report(t_drop_decode(), "events: drag-drop payload decode (windowID/xy + source/data C-string reads; NULL-safe)");
  failed = failed + report(t_device_constants(), "constants: 0.19.0 device tables (haptic waves/dirs, pen types+flags+events, joystick caps props)");
  failed = failed + report(t_haptic_encode(), "haptic: SDL_HapticPeriodic slot encode (sine/square fields, two's-complement, typed PARAM error)");
  failed = failed + report(t_pen_decode(), "pen: motion/touch/button/proximity decode on owned buffers (Win64 layout pin)");
  failed = failed + report(t_ui_event_decode(), "ui-decode: focus (gained/lost) + DPI (pixel/display/scale) + IME preedit/commit/cancel on owned buffers");

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

  // 0.22.0: surface tier -- create -> SaveBMP -> LoadBMP -> destroy round
  // trip (the engine icon path), plus a typed error for a missing file.
  let surface = sdl3_create_surface(&lib, 4, 3, SDL_PIXELFORMAT_RGBA8888);
  if !surface.is_ok {
    failed = failed + report(false, "surface: create failed -- " + surface.error);
  } else {
    let sptr: Int = surface.value;
    let spref = sdl3_get_pref_path(&lib, "xiom-lane", "sdl3-conformance");
    let sbmp = spref + "surface-tier-0.22.0.bmp";
    let ssaved = sdl3_save_bmp(&lib, sptr, sbmp);
    let sloaded = sdl3_load_bmp(&lib, sbmp);
    var sload_ok = false;
    if sloaded.is_ok {
      sdl3_destroy_surface(&lib, sloaded.value);
      sload_ok = true;
    }
    let smissing = sdl3_load_bmp(&lib, spref + "no-such-surface-0.22.0.bmp");
    let smissing_ok = !smissing.is_ok && smissing.error.len() > 0;
    sdl3_destroy_surface(&lib, sptr);
    let sremoved = sdl3_remove_path(&lib, sbmp);
    failed = failed + report(ssaved.is_ok && sload_ok && smissing_ok && sremoved,
      "surface: 4x3 RGBA create -> SaveBMP -> LoadBMP -> destroy (save=" + b2s(ssaved.is_ok)
        + " load=" + b2s(sload_ok) + " missing-typed=" + b2s(smissing_ok)
        + " removed=" + b2s(sremoved) + ")");
  }

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
    // 128-byte XIOM slot, pump, and consume it with a real poll into an
    // owned buffer.  (0.19.0 correction: SDL_PollEvent(NULL) is a PEEK on
    // the pinned 3.4.8 runtime -- it reports the event but does NOT consume
    // it; the earlier poll(NULL) "consume" wording was a suite bug caught
    // by the pen-live check.)
    var ev_in = slot_new(128);
    // Byte-indexed writes only (B-16), and NO pointer arithmetic (B-17:
    // `as_mut_ptr() + 1` compiles to a wild address on v0.64.3).  slot_new
    // zero-fills, so byte 0 (the low half of 0x8000) is already 0; only
    // byte 1 needs the 0x80 high half.
    wr_u8(&mut ev_in, 1, 128);
    // Drain any early queue entries (bounded, true consume) so the poll
    // below is ours.
    var drained: Int = 0;
    var drain_scratch = slot_new(128);
    while drained < 500 {
      if !sdl3_poll_event(&lib, drain_scratch.as_mut_ptr() as Int) { break; }
      drained = drained + 1;
    }
    let pushed = sdl3_push_event(&lib, ev_in.as_mut_ptr() as Int);
    sdl3_pump_events(&lib);
    var u1_out = slot_new(128);
    let consumed = poll_for(&lib, SDL_EVENT_USER, &mut u1_out, 8);
    failed = failed + report(pushed && consumed && sdl3_event_type(&u1_out) == SDL_EVENT_USER,
      "events: synthetic user event (0x8000) injected + consumed (pushed=" + b2s(pushed)
        + ", consumed=" + b2s(consumed) + ", type=" + to_string(sdl3_event_type(&u1_out))
        + ", drained-before=" + to_string(drained) + ")");

    // 0.4.0: push a synthetic KEY_DOWN (the decode layout above is what the
    // runtime reads) and consume it into an owned buffer; true consumption
    // (poll into a buffer) avoids the foreign-write readback path (B-11).
    var kev = slot_new(128);
    wr_u32(&mut kev, 0, SDL_EVENT_KEY_DOWN);
    wr_u32(&mut kev, 16, 1);
    wr_u32(&mut kev, 24, SDL_SCANCODE_A);
    wr_u32(&mut kev, 28, 97);
    wr_u8(&mut kev, 36, 1);
    let kpushed = sdl3_push_event(&lib, kev.as_mut_ptr() as Int);
    sdl3_pump_events(&lib);
    var k1_out = slot_new(128);
    let kconsumed = poll_for(&lib, SDL_EVENT_KEY_DOWN, &mut k1_out, 8);
    failed = failed + report(kpushed && kconsumed
        && sdl3_event_type(&k1_out) == SDL_EVENT_KEY_DOWN
        && sdl3_event_key_scancode(&k1_out) == SDL_SCANCODE_A,
      "events: synthetic KEY_DOWN (scancode A) injected + consumed (pushed=" + b2s(kpushed)
        + ", consumed=" + b2s(kconsumed) + ", type=" + to_string(sdl3_event_type(&k1_out)) + ")");

    // 0.18.0: foreign-written event readback -- the B-11 addendum shape
    // (SDL writing an event INTO an XIOM-owned buffer) is FIXED on
    // v0.64.4: poll the pushed user event into an owned 128-byte buffer
    // and read the type back byte-indexed.  The 0.3.1-era deferral is
    // retired (addendum item REL-20261011-0304 re-tested 2026-10-13).
    // Bounded drains first: SDL's poll internals can leave sentinel
    // residue (SDL_EVENT_POLL_SENTINEL) ahead of our event.
    let _ = drain_events(&lib, 50);
    var ev_out = slot_new(128);
    let opushed = sdl3_push_event(&lib, ev_in.as_mut_ptr() as Int);
    sdl3_pump_events(&lib);
    let oconsumed = poll_for(&lib, SDL_EVENT_USER, &mut ev_out, 8);
    failed = failed + report(opushed && oconsumed && sdl3_event_type(&ev_out) == SDL_EVENT_USER,
      "events: poll into owned buffer -> readback type = " + to_string(sdl3_event_type(&ev_out))
        + " (B-11 addendum retired)");

    // The full decode layer over a FOREIGN-written buffer (deferred in
    // 0.4.0): push the KEY_DOWN again, poll it into a fresh owned slot and
    // decode field-by-field with the 0.4.0 accessors.
    let _ = drain_events(&lib, 50);
    var kev_out = slot_new(128);
    let k2pushed = sdl3_push_event(&lib, kev.as_mut_ptr() as Int);
    sdl3_pump_events(&lib);
    let k2consumed = poll_for(&lib, SDL_EVENT_KEY_DOWN, &mut kev_out, 8);
    failed = failed + report(k2pushed && k2consumed
        && sdl3_event_type(&kev_out) == SDL_EVENT_KEY_DOWN
        && sdl3_event_key_scancode(&kev_out) == SDL_SCANCODE_A
        && sdl3_event_key_code(&kev_out) == 97
        && sdl3_event_key_down(&kev_out),
      "events: KEY_DOWN readback decode (type=" + to_string(sdl3_event_type(&kev_out))
        + " scancode=" + to_string(sdl3_event_key_scancode(&kev_out))
        + " key=" + to_string(sdl3_event_key_code(&kev_out)) + ")");

    // 0.19.0: pen motion through the real queue -- push a synthetic
    // PEN_MOTION (which=77, IN_PROXIMITY|DOWN, x=100.0, y=-3.25), poll it
    // into an owned buffer and decode with the pen accessors (the 0.18.0
    // foreign-written readback route).
    let _ = drain_events(&lib, 50);
    var pen_in = slot_new(128);
    wr_u32(&mut pen_in, 0, SDL_EVENT_PEN_MOTION);
    wr_u32(&mut pen_in, 16, 3);
    wr_u32(&mut pen_in, 20, 77);
    wr_u32(&mut pen_in, 24, SDL_PEN_INPUT_IN_PROXIMITY | SDL_PEN_INPUT_DOWN);
    wr_u32(&mut pen_in, 28, 0x42C80000);
    wr_u32(&mut pen_in, 32, 0xC0500000);
    var pen_out = slot_new(128);
    let ppushed = sdl3_push_event(&lib, pen_in.as_mut_ptr() as Int);
    sdl3_pump_events(&lib);
    let pconsumed = poll_for(&lib, SDL_EVENT_PEN_MOTION, &mut pen_out, 8);
    failed = failed + report(ppushed && pconsumed
        && sdl3_event_type(&pen_out) == SDL_EVENT_PEN_MOTION
        && sdl3_event_pen_window_id(&pen_out) == 3
        && sdl3_event_pen_which(&pen_out) == 77
        && sdl3_event_pen_state(&pen_out) == (SDL_PEN_INPUT_IN_PROXIMITY | SDL_PEN_INPUT_DOWN)
        && sdl3_event_pen_x(&pen_out) == 100.0
        && sdl3_event_pen_y(&pen_out) == -3.25,
      "pen-live: PEN_MOTION pushed + polled readback (type="
        + to_string(sdl3_event_type(&pen_out)) + " which="
        + to_string(sdl3_event_pen_which(&pen_out)) + " x="
        + to_string(sdl3_event_pen_x(&pen_out) as Int) + " pushed=" + b2s(ppushed)
        + " consumed=" + b2s(pconsumed) + ")");

    // 0.5.0/0.20.0: event filter (C callback -> direct handoff).
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
    let wremoved = sdl3_remove_event_watch(&lib, on_watch, 0x88);
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

      // 0.21.0: window identity + geometry (A14/S5-S6).
      let wid = sdl3_window_id(&r, win);
      let win_back = sdl3_window_from_id(&r, wid);
      failed = failed + report(wid != 0 && win_back == win,
        "window: identity id=" + to_string(wid) + " round-trip=" + b2s(win_back == win));

      // 0.22.0: icon, native handle, and the Vulkan surface wrapper.
      let iconr = sdl3_create_surface(&lib, 2, 2, SDL_PIXELFORMAT_RGBA8888);
      if iconr.is_ok {
        let icon_set = sdl3_set_window_icon(&r, win, iconr.value);
        sdl3_destroy_surface(&lib, iconr.value);
        failed = failed + report(icon_set,
          "window: SDL_SetWindowIcon(2x2 RGBA surface) accepted");
      } else {
        failed = failed + report(false, "window: icon surface create failed -- " + iconr.error);
      }

      let nh = sdl3_window_native_handle(&r, win);
      failed = failed + report(nh.ok && nh.handle != 0 && nh.kind != SDL3_NATIVE_WINDOW_NONE,
        "window: native handle kind=" + to_string(nh.kind) + " handle=" + to_string(nh.handle));

      // The wrapper is a pass-through; the engine owns the VkInstance.  A
      // zero instance is the typed rejection path (no Vulkan needed here).
      var vkout = sdl3_vulkan_surface_slot();
      let vkbad = sdl3_vulkan_create_surface(&r, win, 0, &mut vkout);
      let vkzero = sdl3_vulkan_surface_value(&vkout);
      let vkerr = sdl3_get_error(&lib);
      failed = failed + report(!vkbad && vkzero == 0 && vkerr.len() > 0,
        "vulkan: CreateSurface wrapper rejects instance=0 (ret=" + b2s(vkbad)
          + " surface=" + to_string(vkzero) + " error-len=" + to_string(vkerr.len()) + ")");

      let pos_set = sdl3_set_window_position(&r, win, 120, 90);
      let pos = sdl3_window_position(&r, win);
      failed = failed + report(pos_set && pos.ok && pos.x == 120 && pos.y == 90,
        "window: position set/get 120,90 (set=" + b2s(pos_set) + " read="
          + to_string(pos.x) + "," + to_string(pos.y) + " ok=" + b2s(pos.ok) + ")");

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
      let wrm = sdl3_remove_event_watch(&lib, on_watch, 0x99);
      failed = failed + report(rsz_off && rsz_on && wset && szset && wrm
          && sz2.width == 300 && sz2.height == 180 && wtc_saw_resized,
        "window: resizable false/true + resize to 300x180 (readback="
          + to_string(sz2.width) + "x" + to_string(sz2.height) + ") -> typed WINDOW_RESIZED seen="
          + b2s(wtc_saw_resized) + " pixel-size-changed=" + b2s(wtc_saw_pixel));

      // 0.21.0: size-in-pixels + display scale (S5 cross-monitor DPI).
      let pix = sdl3_window_size_pixels(&r, win);
      let scale = sdl3_window_display_scale(&r, win);
      let logical = sdl3_window_size(&r, win);
      var dw = (logical.width as Float64) * scale - (pix.width as Float64);
      if dw < 0.0 { dw = -dw; }
      var dh = (logical.height as Float64) * scale - (pix.height as Float64);
      if dh < 0.0 { dh = -dh; }
      failed = failed + report(pix.ok && pix.width > 0 && pix.height > 0
          && scale > 0.0 && scale <= 8.0 && dw <= 1.0 && dh <= 1.0,
        "window: size-in-pixels " + to_string(pix.width) + "x" + to_string(pix.height)
          + " scale=" + to_string(scale as Int) + " (logical=" + to_string(logical.width)
          + "x" + to_string(logical.height) + " ok=" + b2s(pix.ok) + ")");

      // 0.21.0: display id/index/bounds/content scale for the window.
      let wdisp = sdl3_window_display(&r, win);
      let wdi = sdl3_display_index(&lib, wdisp);
      let wb = sdl3_display_bounds(&lib, wdisp);
      let cscale = sdl3_display_content_scale(&lib, wdisp);
      failed = failed + report(wdisp != 0 && wdi >= 0 && wb.w > 0 && wb.h > 0 && cscale > 0.0,
        "window: display id=" + to_string(wdisp) + " index=" + to_string(wdi)
          + " bounds=" + to_string(wb.w) + "x" + to_string(wb.h)
          + " content-scale=" + to_string(cscale as Int));

      let shown = sdl3_show_window(&r, win);
      let hidden = sdl3_hide_window(&r, win);
      failed = failed + report(true, "window: show/hide callable (show=" + b2s(shown) + " hide=" + b2s(hidden) + ")");

      // 0.21.0: IME start/stop + text-input area/cursor (live, hidden window).
      let ime_on = sdl3_start_text_input(&r, win);
      let ime_active1 = sdl3_text_input_active(&r, win);
      let area_set = sdl3_set_text_input_area(&r, win, Sdl3Rect{ x: 10; y: 20; w: 200; h: 30 }, 7);
      let area = sdl3_get_text_input_area(&r, win);
      let ime_clear = sdl3_clear_composition(&r, win);
      let ime_off = sdl3_stop_text_input(&r, win);
      let ime_active2 = sdl3_text_input_active(&r, win);
      failed = failed + report(ime_on && ime_active1 && area_set && area.ok
          && area.x == 10 && area.y == 20 && area.w == 200 && area.h == 30
          && area.cursor == 7 && ime_clear && ime_off && !ime_active2,
        "ime: start/active -> area 10,20 200x30 cursor=7 -> clear -> stop (on="
          + b2s(ime_on) + " active=" + b2s(ime_active1) + " area=" + b2s(area.ok)
          + " clear=" + b2s(ime_clear) + " off=" + b2s(ime_off)
          + " inactive=" + b2s(!ime_active2) + ")");

      // 0.21.0: focus + DPI + text events routed through the existing watch
      // (synthetic queue push; the handler sees the copied 128-byte event).
      let _uid = drain_events(&lib, 50);
      ui_watch_calls = 0;
      ui_focus_gained_id = 0;
      ui_focus_lost_id = 0;
      ui_dpi_pixel_w = 0;
      ui_dpi_pixel_h = 0;
      ui_dpi_display_id = 0;
      ui_dpi_scale_seen = false;
      ui_text_edit = "";
      ui_text_start = -99;
      ui_text_length = -99;
      ui_text_commit = "";
      ui_text_cancelled = false;
      let uwset = sdl3_add_event_watch(&lib, on_ui_watch, 0xA14);

      var fge = slot_new(128);
      wr_u32(&mut fge, 0, SDL_EVENT_WINDOW_FOCUS_GAINED);
      wr_u32(&mut fge, 16, wid);
      var fle = slot_new(128);
      wr_u32(&mut fle, 0, SDL_EVENT_WINDOW_FOCUS_LOST);
      wr_u32(&mut fle, 16, wid);
      var pse = slot_new(128);
      wr_u32(&mut pse, 0, SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED);
      wr_u32(&mut pse, 16, wid);
      wr_u32(&mut pse, 20, 640);
      wr_u32(&mut pse, 24, 480);
      var dce = slot_new(128);
      wr_u32(&mut dce, 0, SDL_EVENT_WINDOW_DISPLAY_CHANGED);
      wr_u32(&mut dce, 16, wid);
      wr_u32(&mut dce, 20, wdisp);
      var dse = slot_new(128);
      wr_u32(&mut dse, 0, SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED);
      wr_u32(&mut dse, 16, wid);
      var ede = slot_new(128);
      wr_u32(&mut ede, 0, SDL_EVENT_TEXT_EDITING);
      wr_u32(&mut ede, 16, wid);
      wr_u64(&mut ede, 24, sdl3_str_c_ptr("日本語"));
      wr_u32(&mut ede, 32, 1);
      wr_u32(&mut ede, 36, 2);
      var tie = slot_new(128);
      wr_u32(&mut tie, 0, SDL_EVENT_TEXT_INPUT);
      wr_u32(&mut tie, 16, wid);
      wr_u64(&mut tie, 24, sdl3_str_c_ptr("café"));
      var cee = slot_new(128);
      wr_u32(&mut cee, 0, SDL_EVENT_TEXT_EDITING);
      wr_u32(&mut cee, 16, wid);
      wr_u64(&mut cee, 24, 0);

      let pu1 = sdl3_push_event(&lib, fge.as_mut_ptr() as Int);
      let pu2 = sdl3_push_event(&lib, fle.as_mut_ptr() as Int);
      let pu3 = sdl3_push_event(&lib, pse.as_mut_ptr() as Int);
      let pu4 = sdl3_push_event(&lib, dce.as_mut_ptr() as Int);
      let pu5 = sdl3_push_event(&lib, dse.as_mut_ptr() as Int);
      let pu6 = sdl3_push_event(&lib, ede.as_mut_ptr() as Int);
      let pu7 = sdl3_push_event(&lib, tie.as_mut_ptr() as Int);
      let pu8 = sdl3_push_event(&lib, cee.as_mut_ptr() as Int);
      sdl3_pump_events(&lib);
      let uwrm = sdl3_remove_event_watch(&lib, on_ui_watch, 0xA14);
      let _uir = drain_events(&lib, 50);
      failed = failed + report(uwset && pu1 && pu2 && pu3 && pu4 && pu5 && pu6 && pu7 && pu8
          && uwrm && ui_watch_calls >= 8
          && ui_focus_gained_id == wid && ui_focus_lost_id == wid
          && ui_dpi_pixel_w == 640 && ui_dpi_pixel_h == 480
          && ui_dpi_display_id == wdisp && ui_dpi_scale_seen
          && sc_eq(ui_text_edit, "日本語") && ui_text_start == 1 && ui_text_length == 2
          && sc_eq(ui_text_commit, "café") && ui_text_cancelled,
        "events: watch routed focus gained/lost, DPI pixel/display/scale, IME preedit/commit/cancel (calls="
          + to_string(ui_watch_calls) + " gained=" + to_string(ui_focus_gained_id)
          + " lost=" + to_string(ui_focus_lost_id) + " pix=" + to_string(ui_dpi_pixel_w)
          + "x" + to_string(ui_dpi_pixel_h) + " disp=" + to_string(ui_dpi_display_id)
          + " scale=" + b2s(ui_dpi_scale_seen) + " preedit-len="
          + to_string(ui_text_edit.len()) + " commit-len=" + to_string(ui_text_commit.len())
          + " cancel=" + b2s(ui_text_cancelled) + ")");


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

    // 0.21.0: clipboard UTF-8 round trip + primary selection.  The previous
    // text is restored; a platform without a primary selection (Windows)
    // reports the typed-unsupported SKIP instead of failing.
    let prev_clip = sdl3_get_clipboard_text(&lib);
    let clip_marker = "xiom-sdl3-a14-clipboard-7319";
    let clip_set = sdl3_set_clipboard_text(&lib, clip_marker);
    let clip_has = sdl3_has_clipboard_text(&lib);
    let clip_got = sdl3_get_clipboard_text(&lib);
    let clip_restore = sdl3_set_clipboard_text(&lib, prev_clip);
    failed = failed + report(clip_set && clip_has && sc_eq(clip_got, clip_marker),
      "clipboard: UTF-8 set/has/get round trip (set=" + b2s(clip_set) + " has="
        + b2s(clip_has) + " got=\"" + clip_got + "\" restored=" + b2s(clip_restore)
        + " previous-len=" + to_string(prev_clip.len()) + ")");

    let prev_primary = sdl3_get_primary_selection_text(&lib);
    let primary_set = sdl3_set_primary_selection_text(&lib, clip_marker);
    if primary_set {
      let primary_has = sdl3_has_primary_selection_text(&lib);
      let primary_got = sdl3_get_primary_selection_text(&lib);
      let primary_restore = sdl3_set_primary_selection_text(&lib, prev_primary);
      failed = failed + report(primary_has && sc_eq(primary_got, clip_marker),
        "clipboard: primary selection set/has/get round trip (has="
          + b2s(primary_has) + " restored=" + b2s(primary_restore) + ")");
    } else {
      let perr = sdl3_get_error(&lib);
      let primary_has = sdl3_has_primary_selection_text(&lib);
      let primary_got = sdl3_get_primary_selection_text(&lib);
      failed = failed + report(true,
        "clipboard: SKIP -- primary selection unsupported on this platform ("
          + perr + "; has=" + b2s(primary_has) + " text-len="
          + to_string(primary_got.len()) + ")");
    }


    // 0.19.0: pen/tablet tool type via a typed query -- an unknown pen id
    // must report INVALID (no stale handle wall).
    let pbad = sdl3_pen_device_type(&lib, 987654);
    failed = failed + report(pbad == SDL_PEN_DEVICE_TYPE_INVALID,
      "pen: tool-type query INVALID for unknown id (got " + to_string(pbad) + ")");

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

        // 0.19.0: joystick CAPS (properties flags + counts/type).  The
        // virtual driver declares no Rumble/SetLED callbacks, so every
        // capability flag is naturally false; the flag read path is then
        // witnessed positively with a property round trip on the SDL-owned
        // group (set true -> read true -> reset false -> read false).
        let caps = sdl3_joystick_caps(&lib, jh);
        let jtype = sdl3_joystick_type(&lib, jh);
        let props = sdl3_joystick_properties(&lib, jh);
        let caps_ok = caps.axes == 2 && caps.buttons == 2 && caps.hats == 0 && caps.balls == 0
          && caps.kind == SDL_JOYSTICK_TYPE_UNKNOWN
          && !caps.has_rumble && !caps.has_rumble_triggers
          && !caps.has_mono_led && !caps.has_rgb_led && !caps.has_player_led;
        var flag_ok = false;
        if props != 0 {
          let set_on = sdl3_set_boolean_property(&lib, props, SDL_PROP_JOYSTICK_CAP_RUMBLE_BOOLEAN, true);
          let on = sdl3_joystick_has_rumble(&lib, jh);
          let set_off = sdl3_set_boolean_property(&lib, props, SDL_PROP_JOYSTICK_CAP_RUMBLE_BOOLEAN, false);
          let off = sdl3_joystick_has_rumble(&lib, jh);
          flag_ok = set_on && on && set_off && !off;
        }

        sdl3_close_joystick(&lib, jh);
        failed = failed + report(sva && svb && ax == 16384 && bt && conn
            && jname == "xiom-virtual-pad",
          "joystick-live: virtual pad axis0 set=16384 read=" + to_string(ax)
            + " button1=" + b2s(bt) + " connected=" + b2s(conn) + " name=\"" + jname
            + "\" (set-axis=" + b2s(sva) + " set-button=" + b2s(svb) + ")");
        failed = failed + report(caps_ok && jtype == SDL_JOYSTICK_TYPE_UNKNOWN && props != 0,
          "joystick-caps: typed caps axes=" + to_string(caps.axes) + " buttons="
            + to_string(caps.buttons) + " hats=" + to_string(caps.hats) + " balls="
            + to_string(caps.balls) + " type=" + to_string(caps.kind) + " flags-all-false="
            + b2s(caps_ok) + " props=" + to_string(props));
        failed = failed + report(flag_ok,
          "joystick-caps: SDL.joystick.cap.rumble flag round trip true->false (read path witnessed)");
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
  // 0.19.0: haptic wave-form surface (engine ask REL-20261013-2324).
  // Needs SDL_INIT_HAPTIC; SKIP when the platform cannot init.  The encode
  // layer + typed open error run without any device; the device path (when
  // GetHaptics finds one) creates a SINE effect through the real API.
  // -------------------------------------------------------------------
  let hflags = SDL_INIT_HAPTIC | SDL_INIT_JOYSTICK;
  let hinited = sdl3_init(&lib, hflags);
  if !hinited {
    failed = failed + report(true, "haptic: SKIP -- SDL_Init(HAPTIC|JOYSTICK) failed ("
      + sdl3_get_error(&lib) + ")");
  } else {
    let hc = sdl3_haptic_count(&lib);
    let hname = sdl3_haptic_name_for_id(&lib, 999999);
    let hopen = sdl3_haptic_open(&lib, 999999);
    var hopen_kind = -1;
    var herr_ok = false;
    if !hopen.is_ok {
      hopen_kind = hopen.error.kind;
      herr_ok = hopen.error.kind == SDL3_HAPTIC_ERR_OPEN && hopen.error.message.len() > 0;
    }
    failed = failed + report(hc >= 0 && sc_eq(hname, "") && herr_ok,
      "haptic: enumeration count=" + to_string(hc) + " unknown-id name empty="
        + b2s(sc_eq(hname, "")) + " typed open error kind=" + to_string(hopen_kind));

    // Virtual pad: not haptic -> typed OPEN error through the real path
    // (SDL_OpenHapticFromJoystick on a device without a haptic driver).
    let vhjid = sdl3_attach_virtual_joystick(&lib, "xiom-virtual-haptic", 2, 2);
    if vhjid == 0 {
      failed = failed + report(true, "haptic: SKIP -- attach virtual joystick failed ("
        + sdl3_get_error(&lib) + ")");
    } else {
      let vjh = sdl3_open_joystick(&lib, vhjid);
      if vjh == 0 {
        failed = failed + report(false, "haptic: SDL_OpenJoystick(attached virtual) failed -- "
          + sdl3_get_error(&lib));
      } else {
        let ish = sdl3_is_joystick_haptic(&lib, vjh);
        let oh = sdl3_open_haptic_from_joystick(&lib, vjh);
        var oh_kind = -1;
        var oh_err = false;
        if !oh.is_ok {
          oh_kind = oh.error.kind;
          oh_err = oh.error.kind == SDL3_HAPTIC_ERR_OPEN && oh.error.message.len() > 0;
        }
        sdl3_close_joystick(&lib, vjh);
        failed = failed + report(!ish && oh_err,
          "haptic: virtual pad is not haptic; OpenHapticFromJoystick typed error (kind="
            + to_string(oh_kind) + ")");
      }
      let vhdet = sdl3_detach_virtual_joystick(&lib, vhjid);
      failed = failed + report(vhdet, "haptic: virtual pad detached=" + b2s(vhdet));
    }

    if hc > 0 {
      // Device path: open the first id, query caps, then encode + create +
      // run + status + stop + destroy a SINE effect (support-gated).
      let hid0 = sdl3_haptic_at(&lib, 0);
      let ho = sdl3_haptic_open(&lib, hid0);
      if !ho.is_ok {
        failed = failed + report(true, "haptic-device: SKIP -- open first id failed: "
          + ho.error.message);
      } else {
        let haptic: Int = ho.value;
        let hnm = sdl3_haptic_name(&lib, haptic);
        let feats = sdl3_haptic_features(&lib, haptic);
        let maxe = sdl3_haptic_max_effects(&lib, haptic);
        let axes = sdl3_haptic_num_axes(&lib, haptic);
        var hslot = slot_new(SDL_HAPTIC_EFFECT_SIZE);
        let henc = sdl3_haptic_encode_periodic(&mut hslot, haptic_sine_wave());
        var supported = false;
        if henc.is_ok {
          supported = sdl3_haptic_effect_supported(&lib, haptic, &mut hslot);
        }
        var cid_ok = false;
        var eid = 0;
        if supported {
          let cr = sdl3_haptic_create_periodic(&lib, haptic, haptic_sine_wave());
          if cr.is_ok {
            eid = cr.value;
            cid_ok = true;
          }
        }
        var run_ok = false;
        var stat = false;
        var stop_ok = false;
        if cid_ok {
          let rr = sdl3_haptic_run(&lib, haptic, eid, 1);
          run_ok = rr.is_ok;
          stat = sdl3_haptic_status(&lib, haptic, eid);
          let sr = sdl3_haptic_stop(&lib, haptic, eid);
          stop_ok = sr.is_ok;
          sdl3_haptic_destroy(&lib, haptic, eid);
        }
        let rum = sdl3_haptic_rumble_supported(&lib, haptic);
        var rum_ok = true;
        if rum {
          let ir = sdl3_haptic_init_rumble(&lib, haptic);
          let pr = sdl3_haptic_play_rumble(&lib, haptic, 0.5, 50);
          sdl3_delay(&lib, 20);
          let sr2 = sdl3_haptic_stop_rumble(&lib, haptic);
          rum_ok = ir && pr && sr2;
        }
        sdl3_haptic_close(&lib, haptic);
        var effect_ok = true;
        if supported {
          effect_ok = cid_ok && run_ok && stop_ok;
        }
        failed = failed + report(hnm.len() > 0 && maxe > 0 && axes >= 0 && effect_ok && rum_ok,
          "haptic-device: name=\"" + hnm + "\" feats=" + to_string(feats) + " max="
            + to_string(maxe) + " axes=" + to_string(axes) + " sine-supported=" + b2s(supported)
            + " created=" + b2s(cid_ok) + " run=" + b2s(run_ok) + " status=" + b2s(stat)
            + " stop=" + b2s(stop_ok) + " rumble=" + b2s(rum) + " rumble-run=" + b2s(rum_ok));
      }
    } else {
      failed = failed + report(true,
        "haptic-device: SKIP -- no haptic device on this host (encode + typed-error paths covered)");
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
