# AUDIT: xiom.miniaudio

## Status (2026-10-17)

Vendored single-header implementation at 0.5.0 (long-lived device handles;
A04 growth at 0.4.0). The pre-pilot files
(`bridge/xiom_ma_bridge.c/h`, `miniaudio_safe.xi`, `demo_miniaudio.xi`)
referenced a miniaudio header that was **never vendored** and could not
build; they are preserved in git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.5 (pin), v0.64.6 slot re-verify |
| Pin | tag 0.11.25 header SHA256 + LICENSE SHA256 (`SPEC.md` section 2; unchanged at this touch -- no re-carve) |
| Link model | `--c-source src/miniaudio_all.c`; no system audio library |
| FFI confinement | all `extern "C"` in the root module `miniaudio.xi` (G5) |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 44/44 x2 on the v0.64.5 pin + x2 on the v0.64.6 slot** via `scripts/port.ps1 -TimeoutSec 300` (27 lifecycle checks + 17 handle checks: null-device battery deterministic, live auto/WASAPI open legs) |
| Provenance | `PROVENANCE.md` (per-touch rule; 0.5.0 touch recorded) |

## Design notes

- The compile unit embeds the bridge in the same TU as the implementation;
  no separate bridge object and no include paths needed.
- Decode probe bug found and fixed (0.2.0): the EOS read returns `MA_AT_END`
  on a drained decoder -- the probe accepts `MA_SUCCESS || MA_AT_END` with
  zero frames read.
- Sample data is precomputed (no libm); WAV headers are built byte-wise.
- XIOM-side slots are 4-byte out-params; `int_to_str` is local to the module
  (no stdlib convert inside confined blocks).
- 0.3.0/0.4.0 keep the scalar/cached-return bridge style: probes write
  results into C statics and the module reads them through getters -- no
  foreign-pointer reads (the B-20 rule); floats are compared/quantized
  C-side (`x1000` ints + exactness flags), never marshalled.
- 0.4.0 live legs are silent by construction: the device callback streams a
  silent WAV through the real WAV decoder into the output buffer; engine
  sounds are silence. Evidence is counters (frames/callbacks/decoded) and
  the engine frame clock -- no audible surprise.
- 0.5.0 handles: file-scope 4-slot registry (`ma_context`/`ma_device`
  initialized in place, never copied); handle token = monotonic id, so a
  closed handle can never alias a new one -- stale ops are the typed
  `BAD_HANDLE` (double close included). The render callback is an env-free
  top-level XIOM fn handed to C once (the direct-handoff callback ABI) and
  invoked from the **device thread**; the C trampoline reads the pointer
  once per buffer (registration churn while running is at most one
  in-flight callback behind) and verifies the two marker bytes the suite's
  renders write, so "the render's writes landed" is counted (`marked`)
  rather than assumed. Feasibility was probed before shipping: a
  foreign-C-thread invocation of a bare top-level XIOM fn (with concurrent
  main-thread XIOM code) ran green x2 on both the v0.64.5 pin and the
  v0.64.6 slot.
- 0.5.0 typed errors: `MaHandleError { kind, rc, message }` with kinds
  `NO_CONTEXT`/`NO_DEVICE`/`BAD_HANDLE`/`EXHAUSTED`/`STATE`/`STEP`; the
  `ma_result` travels in `rc` wherever one exists (e.g. bogus backend id ->
  `NO_CONTEXT rc=-203`).
- 0.5.0 battery determinism: the deterministic leg runs on
  `ma_backend_null` (explicitly requested; always openable, paced at real
  time by miniaudio's generic device thread, no audio service needed); the
  live auto/WASAPI legs do open -> info -> close only (the 0.4.0 lifecycle
  leg owns the live start path); both degrade to typed SKIP on hosts
  without audio.
- Device-loss boundary (0.4.0, unchanged): `started`/`stopped`
  notifications are proven live; `rerouted`/interruption/unlock are wired
  but require a real default-device change (cannot be forced in-process).
  The graph leg proves the detach/reattach recovery shape on a sound node.
- Capture is typed: no endpoint -> `opened=false` + `ma_result` code; silent
  endpoint -> `opened=true, frames=0`; both are non-fatal SKIP-style
  outcomes that still exercise `ma_device_init(ma_device_type_capture)`.
- The MP3 fixture decodes through dr_mp3 with the LAME gapless trim (64
  frames, peak 19039 -- matching the ffmpeg reference decode); assertions
  use bounds, not exact samples, for the lossy leg.

## Known limitations

- Scope at 0.5.0: everything in `SPEC.md` section 5. Opus/Ogg custom
  decoder backends, effect nodes/spatialization, and the full
  resource-manager surface are staged (`ROADMAP.md`); the handle surface's
  client shape is fixed (f32 stereo 48 kHz, 480-frame period) at this touch.
- The device-count and negotiation reports are environment-dependent; a
  serviceless host reports the device/engine/handle-live checks as
  SKIP-typed passes. The null-device handle battery always runs.
- The render callback runs on the device thread: it must be an env-free
  top-level fn, and concurrent main-thread XIOM execution is proven safe
  only in the witnessed probe shape (bounded work, marker writes + counter
  bumps; no allocation inside the callback).
- `vendor/miniaudio.h` is 4.1 MB; the amalgamation compile adds a few
  seconds to the suite build (watchdog headroom is fine).
