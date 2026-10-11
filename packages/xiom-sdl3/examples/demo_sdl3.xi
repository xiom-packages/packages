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

  // 0.8.0: display blit -- upload an RGBA frame into a streaming texture,
  // blit it over the render target and present (hidden window; safe on a
  // desktop session).
  let rs = sdl3_load_resources();
  if !rs.is_ok {
    io.println("resources unavailable: " + rs.error.message);
  } else {
    let r: Sdl3Resources = rs.value;
    let winr = sdl3_create_window(&r, "xiom.sdl3 demo blit", 320, 200, SDL_WINDOW_HIDDEN);
    if !winr.is_ok {
      io.println("window SKIP: " + winr.error);
    } else {
      let win: Int = winr.value;
      let renr = sdl3_create_renderer(&r, win);
      if !renr.is_ok {
        io.println("renderer SKIP: " + renr.error);
      } else {
        let ren: Int = renr.value;
        let texr = sdl3_create_texture(&r, ren, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_STREAMING, 64, 64);
        if texr.is_ok {
          let tex: Int = texr.value;
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
          let up = sdl3_update_texture(&r, tex, &mut pattern, 64, 64);
          let vs = sdl3_set_render_vsync(&r, ren, 1);
          let blit = sdl3_render_texture(&r, ren, tex);
          let pres = sdl3_render_present(&r, ren);
          io.println("blit: 64x64 RGBA checker uploaded + presented (update="
            + b2s(up) + " vsync=" + b2s(vs) + " blit=" + b2s(blit) + " present=" + b2s(pres) + ")");
          sdl3_destroy_texture(&r, tex);
        }
        sdl3_destroy_renderer(&r, ren);
      }
      sdl3_destroy_window(&r, win);
    }
    let rcl = sdl3_resources_close(&r);
    if !rcl.is_ok { io.println("resource handle close failed: " + rcl.error); }
  }

  sdl3_quit(&lib);
  let cl = sdl3_close(&lib);
  if cl.is_ok { io.println("closed cleanly"); }
  return 0;
}

fn b2s(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}
