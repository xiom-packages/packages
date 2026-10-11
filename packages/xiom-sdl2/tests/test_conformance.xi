// xiom.sdl2 conformance suite -- dynamic-loader path, 100% exported surface.
//
// CI WITHOUT SDL2 must stay green: `sdl2_load()` opens SDL2.dll at runtime;
// when the DLL is absent the suite reports SKIP markers (a classified
// platform state, printed as [PASS] with an explicit SKIP label so the
// packages-lane runner counts them). When the DLL is present the suite:
//   1. resolves EVERY exported-oracle function name (the 844 names declared
//      in the shipped SDL2 2.32.10 headers AND exported by SDL2.dll) with
//      `dl.dl_sym` and prints `resolved=N/N`;
//   2. checks generated constant tables;
//   3. runs the functional probe chain:
//      error path (init guard) -> SDL_SetMainReady -> SDL_Init(VIDEO|TIMER)
//      -> SDL_GetPlatform -> SDL_GetNumVideoDisplays -> SDL_GetDisplayBounds
//      -> SDL_CreateWindow(hidden 320x240) -> SDL_GetWindowSize -> destroy
//      -> SDL_Quit;
//   4. releases the loader handle.
//
// Out-params use XIOM-owned Vec[UInt8] slots handed to C via `as_mut_ptr()`
// and are read back with byte-indexed reads (lane discipline B-11..B-20:
// no pointer arithmetic, no reads through foreign pointers).  The error-path
// probe forces a deterministic bad-subsystem init (SDL_AUDIODRIVER pointed
// at a nonexistent driver): rc != 0 and a non-empty error string on every
// host, then SDL_ClearError must empty it.  SDL_SetMainReady is still
// called before the real init (a no-op on DLL builds without
// SDL_MAIN_NEEDED, required by builds that keep the main guard).
//
// Build+run (no extra compiler args: the loader is pure XIOM):
//   xiom --run tests/test_conformance.xi
// Local positive-path proof used the SDL2.dll shipped with the Vulkan SDK
// (C:\VulkanSDK\1.4.350.0\Bin\SDL2.dll, 2.32.10) via PATH.

module sdl2_conformance

use xiom.io;
use xiom.convert;
use xiom.env;
use xiom.ffi;
use xiom.ffi.dl;
use xiom.sdl2;
use xiom.sdl2.names;
use xiom.sdl2.init_f1;
use xiom.sdl2.main_f1;
use xiom.sdl2.error_f1;
use xiom.sdl2.platform_f1;
use xiom.sdl2.version_f1;
use xiom.sdl2.video_f1;
use xiom.sdl2.video_f2;
use xiom.sdl2.video_c;
use xiom.sdl2.pixels_f1;
use xiom.sdl2.events_f1;
use xiom.sdl2.keycode;
use xiom.sdl2.scancode;
use xiom.sdl2.mouse_f1;
use xiom.sdl2.audio_f1;

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

// Zeroed out-param slot (owned; no malloc/free).
fn slot_new(n: Int) -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

// Byte-indexed reads from an owned slot (B-11: byte-indexed access only).
fn read_u8_at(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 1
{
  return buf[off] as Int;
}

fn read_u32_at(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let b0 = buf[off + 0] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

fn read_i32_at(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let u = read_u32_at(buf, off);
  if u >= 0x80000000 { return u - 0x100000000; }
  return u;
}

// Generated constant tables (DLL-independent).
fn t_constants() -> Bool {
  var ok = true;
  if SDL_INIT_TIMER != 0x1 { ok = false; }
  if SDL_INIT_VIDEO != 0x20 { ok = false; }
  if (SDL_INIT_VIDEO | SDL_INIT_TIMER) != 0x21 { ok = false; }
  if SDL_INIT_EVERYTHING != 62001 { ok = false; }
  if SDL_WINDOW_HIDDEN != 0x8 { ok = false; }
  if SDL_WINDOWPOS_UNDEFINED != 0x1FFF0000 { ok = false; }
  if SDL_WINDOWPOS_CENTERED != 0x2FFF0000 { ok = false; }
  if SDL_QUIT != 0x100 { ok = false; }
  if SDL_KEYDOWN != 0x300 { ok = false; }
  if SDL_WINDOWEVENT_CLOSE != 14 { ok = false; }
  if SDL_PIXELFORMAT_RGBA8888 != 0x16462004 { ok = false; }
  if SDL_SCANCODE_A != 4 { ok = false; }
  if SDLK_ESCAPE != 27 { ok = false; }
  // Char-escape decode: '\x1B' -> 27 above; scancode-to-keycode macro
  // expansion: SDLK_CAPSLOCK = SDL_SCANCODE_TO_KEYCODE(57) = 57 | (1 << 30).
  if SDLK_CAPSLOCK != 1073741881 { ok = false; }
  if KMOD_CTRL != 0xC0 { ok = false; }
  if SDL_BUTTON_LMASK != 1 { ok = false; }
  if SDL_BUTTON_MMASK != 2 { ok = false; }
  if SDL_BUTTON_RMASK != 4 { ok = false; }
  // AUDIO_S16LSB (SDL_audio.h macros): 0x8010.
  if AUDIO_S16LSB != 32784 { ok = false; }
  if sdl2_versionnum(2, 32, 10) != 2032010 { ok = false; }
  // SDL_PIXELFORMAT_RGBA8888 packs (packed32|rgba|8888|32bits|4bytes):
  // 0x16462004 verified above; the fourcc path: IYUV = 'I','Y','U','V'.
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.sdl2 conformance tests (dynamic loader, 100% exported surface) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(),
    "constants: init flags, window/pos flags, events, scancodes, keycodes (macro expansions), pixel format, masks, versionnum");

  let l = sdl2_load();
  if !l.is_ok {
    if l.error.kind == SDL2_LOAD_ABSENT {
      failed = failed + report(true, "loader: SKIP -- SDL2.dll not present (" + l.error.message + ")");
      failed = failed + report(true, "surface: SKIP -- 844-function resolution sweep (no SDL2 runtime)");
      failed = failed + report(true, "probe: SKIP -- init/window chain (no SDL2 runtime)");
    } else {
      failed = failed + report(false, "loader: SDL2.dll present but ABI mismatch -- " + l.error.message);
    }
    if failed == 0 {
      io.println("xiom.sdl2: suite green (SDL2 absent -- surface + probes skipped)");
    } else {
      io.println("xiom.sdl2: tests failed");
    }
    return failed;
  }

  let lib: Sdl2Library = l.value;
  failed = failed + report(true, "loader: SDL2.dll loaded; all 844 symbol chunks assembled (sdl2_load)");

  // -------------------------------------------------------------------
  // Full-surface runtime resolution: every exported-oracle name through
  // dl.dl_sym on the loaded handle -> `resolved=N/N`.
  // -------------------------------------------------------------------
  let names = sdl2_exported_names();
  var resolved = 0;
  var missing = 0;
  var i = 0;
  while i < names.len() {
    let r = dl.dl_sym(lib.handle, names[i]);
    if r.is_ok {
      resolved = resolved + 1;
    } else {
      if missing < 10 {
        io.println("  unresolved: " + names[i]);
        io.flush_stdout();
      }
      missing = missing + 1;
    }
    i = i + 1;
  }
  io.println("resolved=" + to_string(resolved) + "/" + to_string(names.len()));
  io.flush_stdout();
  failed = failed + report(resolved == names.len() && names.len() == SDL2_EXPORTED_COUNT,
    "surface: resolved=" + to_string(resolved) + "/" + to_string(names.len())
      + " (exported-oracle count " + to_string(SDL2_EXPORTED_COUNT)
      + ", missing=" + to_string(missing) + ")");

  // -------------------------------------------------------------------
  // Version probe (SDL_GetVersion writes 3 bytes into an owned slot).
  // -------------------------------------------------------------------
  var vslot = slot_new(8);
  sdl2_get_version(&lib.version_f1, vslot.as_mut_ptr());
  let vmaj = read_u8_at(&vslot, 0);
  let vmin = read_u8_at(&vslot, 1);
  let vpat = read_u8_at(&vslot, 2);
  let rev = sdl2_get_revision(&lib.version_f1);
  failed = failed + report(vmaj == 2 && vmin == 32 && vpat == 10 && rev.len() > 0,
    "version: SDL " + to_string(vmaj) + "." + to_string(vmin) + "." + to_string(vpat)
      + " revision=\"" + rev + "\"");

  // -------------------------------------------------------------------
  // Error path (deterministic, hardware-free): a bad audio subsystem
  // configuration.  SDL_AUDIODRIVER is pointed at a driver that does not
  // exist, so SDL_Init(SDL_INIT_AUDIO) must fail with a non-empty error
  // string ("Audio target '<name>' not available"); SDL_ClearError then
  // empties it.  (The SDL main-guard path is NOT used: the shipped
  // Windows DLL is built without SDL_MAIN_NEEDED, so SDL_MainIsReady
  // starts true and that guard never fires.)
  // -------------------------------------------------------------------
  env.set_var("SDL_AUDIODRIVER", "xiom-bogus-driver");
  let erc = sdl2_init(&lib.init_f1, SDL_INIT_AUDIO);
  let emsg = sdl2_get_error(&lib.error_f1);
  env.remove_var("SDL_AUDIODRIVER");
  failed = failed + report(erc != 0 && emsg.len() > 0,
    "error: bad subsystem (SDL_AUDIODRIVER=bogus) fails (rc=" + to_string(erc)
      + ") with non-empty error (\"" + emsg + "\")");
  sdl2_clear_error(&lib.error_f1);
  let emsg2 = sdl2_get_error(&lib.error_f1);
  failed = failed + report(emsg2.len() == 0,
    "error: SDL_ClearError -> empty error string (len=" + to_string(emsg2.len()) + ")");

  // -------------------------------------------------------------------
  // Functional probe chain (hidden window; SKIP when the platform cannot
  // init video, e.g. headless CI).
  // -------------------------------------------------------------------
  sdl2_set_main_ready(&lib.main_f1);
  let inited = sdl2_init(&lib.init_f1, SDL_INIT_VIDEO | SDL_INIT_TIMER);
  if inited != 0 {
    failed = failed + report(true, "video: SKIP -- SDL_Init(VIDEO|TIMER) failed ("
      + sdl2_get_error(&lib.error_f1) + ")");
  } else {
    failed = failed + report(true, "init: SDL_Init(VIDEO|TIMER) -> 0");
    let wmask = sdl2_was_init(&lib.init_f1, SDL_INIT_VIDEO);
    failed = failed + report(wmask != 0,
      "init: SDL_WasInit(VIDEO) mask=" + to_string(wmask));

    let platform = sdl2_get_platform(&lib.platform_f1);
    failed = failed + report(platform.len() > 0, "platform: SDL_GetPlatform = \"" + platform + "\"");

    let ndisp = sdl2_get_num_video_displays(&lib.video_f1);
    failed = failed + report(ndisp >= 1, "displays: SDL_GetNumVideoDisplays = " + to_string(ndisp));

    var bslot = slot_new(16);
    let brc = sdl2_get_display_bounds(&lib.video_f1, 0, bslot.as_mut_ptr());
    let bx = read_i32_at(&bslot, 0);
    let by = read_i32_at(&bslot, 4);
    let bw = read_i32_at(&bslot, 8);
    let bh = read_i32_at(&bslot, 12);
    failed = failed + report(brc == 0 && bw > 0 && bh > 0,
      "display-bounds: display 0 -> " + to_string(bw) + "x" + to_string(bh)
        + " @ " + to_string(bx) + "," + to_string(by) + " (rc=" + to_string(brc) + ")");

    let win = sdl2_create_window(&lib.video_f1, "xiom-sdl2-conformance",
      SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 320, 240, SDL_WINDOW_HIDDEN);
    if win == 0 {
      failed = failed + report(false, "window: SDL_CreateWindow(hidden 320x240) failed -- "
        + sdl2_get_error(&lib.error_f1));
    } else {
      failed = failed + report(true, "window: SDL_CreateWindow(hidden 320x240) -> handle");
      var wslot = slot_new(4);
      var hslot = slot_new(4);
      sdl2_get_window_size(&lib.video_f2, win, wslot.as_mut_ptr(), hslot.as_mut_ptr());
      let ww = read_i32_at(&wslot, 0);
      let wh = read_i32_at(&hslot, 0);
      failed = failed + report(ww == 320 && wh == 240,
        "window-size: SDL_GetWindowSize = " + to_string(ww) + "x" + to_string(wh));
      sdl2_destroy_window(&lib.video_f1, win);
      failed = failed + report(true, "window: SDL_DestroyWindow completed");
    }

    sdl2_quit(&lib.init_f1);
    let wmask2 = sdl2_was_init(&lib.init_f1, SDL_INIT_VIDEO);
    failed = failed + report(wmask2 == 0, "quit: SDL_Quit -> SDL_WasInit(VIDEO) = 0");
  }

  let cl = sdl2_close(&lib);
  failed = failed + report(cl.is_ok, "loader: SDL2 handle released");

  if failed == 0 {
    io.println("xiom.sdl2: all tests passed");
  } else {
    io.println("xiom.sdl2: tests failed");
  }
  return failed;
}
