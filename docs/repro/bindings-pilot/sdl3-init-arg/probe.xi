// B-19 repro (regression in compiler commit fde5548e, m263-m265):
// SDL_Init reports success through the loader cast-call but does NOT
// initialize anything -- SDL_WasInit(0) (all-initialized mask) reads 0.
// The same-source probe on v0.64.3 reads 16384 (SDL_INIT_EVENTS).
//
// The arg-marshalling control on the SAME build/function: SDL_Delay(100)
// through the same `lib.p_* as fn(Int)` shape sleeps the full 100 ms
// (elapsed=100), so plain Int args to loader cast-calls are not generally
// dropped -- this looks specific to the p_init binding/call.
//
// Run (SDL3.dll on PATH -- the dev box resolves it from the Vulkan SDK):
//   copy this file into packages/xiom-sdl3/tests/ (module discovery for
//   `use xiom.sdl3`), then from packages/xiom-sdl3:
//     $env:XIOM_STDLIB = 'E:\xiom-lang\stdlib'
//     & <toolchain>\xiom.exe --run tests\<copy>.xi
//
// Expected on a healthy compiler (v0.64.3 observed):
//   elapsed=100 init=1 w_all=16384
// Observed on fde5548e:
//   elapsed=100 init=1 w_all=0
//
// RESOLVED 2026-10-11 (package-side, not a compiler regression): this
// probe and xiom.sdl3 cast SDL_WasInit as `fn(Int) -> UInt8`, but the C
// API returns SDL_InitFlags (Uint32). Toolchains from m263 on honor the
// declared return width, so 16384 (0x4000) read as its low byte 0. Fixed
// in xiom.sdl3 0.16.1 + here (cast -> UInt32); w_all=16384 on the pin and
// re-verified at the v0.64.4 archive.
//
// Suite-level effect: xiom.sdl3 0.13.0 conformance = 51/52 on fde5548e
// (`init: SDL_WasInit(TIMER|EVENTS) reflects the flags` FAILS) vs 52/52 on
// v0.64.3.  The rest of the suite still passes because SDL3 lazily
// initializes most subsystems on first use.

module sdl3_init_arg_probe

use xiom.io;
use xiom.convert;
use xiom.sdl3;

fn main() -> Int {
  let l = sdl3_load();
  if !l.is_ok {
    io.println("LOAD-FAIL " + l.error.message);
    return 1;
  }
  let lib: Sdl3Library = l.value;
  unsafe {
    let f_delay = lib.p_delay as fn(Int);
    let f_ticks = lib.p_get_ticks as fn() -> UInt32;
    let f_init = lib.p_init as fn(Int) -> UInt8;
    let f_was = lib.p_was_init as fn(Int) -> UInt32;
    let t0 = f_ticks() as Int;
    f_delay(100);
    let t1 = f_ticks() as Int;
    let r = f_init(16385) as Int; // SDL_INIT_TIMER | SDL_INIT_EVENTS
    let w = f_was(0) as Int;      // mask of all initialized subsystems
    io.println("elapsed=" + to_string(t1 - t0) + " init=" + to_string(r)
      + " w_all=" + to_string(w));
    io.flush_stdout();
    let f_quit = lib.p_quit as fn();
    f_quit();
  }
  let cl = sdl3_close(&lib);
  return 0;
}
