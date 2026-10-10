# Repro: fn-pointer cast-call floating-point returns (GLFW, v0.64.2)

Found 2026-10-10 by the bindings lane while growing `xiom.glfw` to the engine
surface.

**Symptom.** Functions reached through a fn-pointer cast (`let f =
lib.p_sym as fn(...) -> Float64; f()`), with a floating-point RETURN,
yield `0` (f64) or garbage (f32). Integer/pointer returns and
floating-point OUT-params are unaffected.

**Evidence (GLFW 3.4 win64 official DLL, `C:\glfw-3.4.bin.WIN64`).**

1. `glfwGetTime()` through the cast never advances:
   `probe_gettime_noop.xi` -> `after_set99_ms=0` (expected 99,000);
   a 0.30 s `glfwWaitEventsTimeout` between reads leaves `gettime_ms=0`.
2. `glfwGetWindowOpacity()` (float return) through the cast:
   `probe_opacity_garbage.xi` -> `opacity_x1000=262416000` (a 1.0 default
   must read 1000).
3. Ground truth via python `ctypes` on the same DLL:
   `glfwGetTime` after `glfwSetTime(7.5)` reads `7.500` (+0.111 after 100 ms)
   -- so the DLL and the stored/`dl_sym`-resolved pointers are correct
   (stored == fresh pointer, compared in-session).
4. Control (working): `glfwGetTimerValue` (u64 return) returns plausible
   ticks; `glfwGetVersionString` (ptr return) reads fine; `glfwGetCursorPos`
   (double OUT-params via XIOM-owned slots) returns the correct
   window-relative position; `glfwGetWindowContentScale` (float OUT) = 1.00.

**Repro commands** (from `packages/xiom-glfw`, DLL dir on PATH):

```
$env:PATH = "C:\glfw-3.4.bin.WIN64\lib-vc2022;" + $env:PATH
xiom --run docs/repro/.../probe_gettime_noop.xi   # copy into tests/ first
xiom --run docs/repro/.../probe_opacity_garbage.xi
```

The copies here are the exact probe sources; run them from
`packages/xiom-glfw/tests/` (they `use xiom.glfw`).
