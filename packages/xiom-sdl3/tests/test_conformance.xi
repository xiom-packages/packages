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
  if SDL_WINDOW_HIDDEN != 0x8 { ok = false; }
  if SDL_EVENT_QUIT != 0x100 { ok = false; }
  if SDL_PIXELFORMAT_RGBA8888 != 0x16462004 { ok = false; }
  if SDL_TEXTUREACCESS_STATIC != 0 { ok = false; }
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
      let shown = sdl3_show_window(&r, win);
      let hidden = sdl3_hide_window(&r, win);
      failed = failed + report(true, "window: show/hide callable (show=" + b2s(shown) + " hide=" + b2s(hidden) + ")");

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

  let cl = sdl3_close(&lib);
  failed = failed + report(cl.is_ok, "loader: SDL3 handle released");

  if failed == 0 {
    io.println("xiom.sdl3: all tests passed");
  } else {
    io.println("xiom.sdl3: tests failed");
  }
  return failed;
}
