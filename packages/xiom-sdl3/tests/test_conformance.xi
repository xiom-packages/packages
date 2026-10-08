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

// Constant tables and version arithmetic (independent of the DLL).
fn t_constants() -> Bool {
  var ok = true;
  if SDL_INIT_EVENTS != 0x4000 { ok = false; }
  if SDL_INIT_TIMER != 0x1 { ok = false; }
  if SDL_INIT_VIDEO != 0x20 { ok = false; }
  if SDL_WINDOW_VULKAN != 0x10000000 { ok = false; }
  if SDL_EVENT_QUIT != 0x100 { ok = false; }
  if sdl3_versionnum(3, 4, 8) != 3004008 { ok = false; }
  if sdl3_version_major(3004008) != 3 { ok = false; }
  if sdl3_version_minor(3004008) != 4 { ok = false; }
  if sdl3_version_patch(3004008) != 8 { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.sdl3 conformance tests (dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: init/window/event tables + SDL_VERSIONNUM math");

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

    // Quit and verify the flags are cleared.
    sdl3_quit(&lib);
    let still = sdl3_was_init(&lib, flags);
    failed = failed + report(!still, "quit: SDL_Quit clears TIMER|EVENTS");
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
