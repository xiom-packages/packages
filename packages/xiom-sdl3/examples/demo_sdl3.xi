// XIOM -- xiom.sdl3 loader demo
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Run from the package directory:  xiom --run examples/demo_sdl3.xi
// Prints SKIP when SDL3.dll is not on the loader search path.

module sdl3_demo

use xiom.io;
use xiom.convert;
use xiom.sdl3;

fn main() -> Int {
  io.println("=== xiom.sdl3 demo (dynamic loader) ===");
  let l = sdl3_load();
  if !l.is_ok {
    io.println("SDL3 unavailable (kind " + to_string(l.error.kind) + "): " + l.error.message);
    io.println("SKIP: install SDL3 or add its directory to PATH.");
    return 0;
  }
  let lib: Sdl3Library = l.value;

  let v = sdl3_get_version(&lib);
  io.println("SDL3 version: " + to_string(sdl3_version_major(v)) + "."
    + to_string(sdl3_version_minor(v)) + "." + to_string(sdl3_version_patch(v)));
  let rev = sdl3_get_revision(&lib);
  if rev.len() > 0 { io.println("revision: " + rev); }

  let flags = SDL_INIT_TIMER | SDL_INIT_EVENTS;
  if !sdl3_init(&lib, flags) {
    io.println("init failed: " + sdl3_get_error(&lib));
    let cl = sdl3_close(&lib);
    return 1;
  }
  io.println("init: timer + events ready");

  let t0 = sdl3_get_ticks(&lib);
  sdl3_delay(&lib, 25);
  let t1 = sdl3_get_ticks(&lib);
  io.println("timer: " + to_string(t1 - t0) + "ms elapsed across SDL_Delay(25)");

  sdl3_pump_events(&lib);
  let got = sdl3_poll_event(&lib, 0);
  if got {
    io.println("events: pump+poll ok (a queued event was consumed)");
  } else {
    io.println("events: pump+poll ok (queue empty)");
  }

  sdl3_quit(&lib);
  let cl = sdl3_close(&lib);
  if cl.is_ok { io.println("closed cleanly"); }
  return 0;
}
