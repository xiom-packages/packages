# AUDIT: xiom.miniaudio

## Status (2026-10-16)

Vendored single-header implementation at 0.4.0 (A04 growth). The pre-pilot
files (`bridge/xiom_ma_bridge.c/h`, `miniaudio_safe.xi`, `demo_miniaudio.xi`)
referenced a miniaudio header that was **never vendored** and could not
build; they are preserved in git history only as reference.

| Item | State |
|------|-------|
| Compiler | xiom v0.64.5 |
| Pin | tag 0.11.25 header SHA256 + LICENSE SHA256 (`SPEC.md` section 2; re-verified at this touch) |
| Link model | `--c-source src/miniaudio_all.c`; no system audio library |
| FFI confinement | all `extern "C"` in the root module `miniaudio.xi` (G5) |
| Suite | `tests/test_conformance.xi` |
| Runs | **PASS 27/27** via `scripts/port.ps1 -TimeoutSec 300` (live WASAPI device + engine legs; device-free graph/decode legs; capture typed outcome; streamed WAV/FLAC/MP3) |
| Provenance | `PROVENANCE.md` (per-touch rule, added at 0.4.0) |

## Design notes

- The compile unit embeds the bridge in the same TU as the implementation;
  no separate bridge object and no include paths needed.
- Decode probe bug found and fixed (0.2.0): the EOS read returns `MA_AT_END`
  on a drained decoder -- the probe accepts `MA_SUCCESS || MA_AT_END` with
  zero frames read.
- Sample data is precomputed (no libm); WAV headers are built byte-wise.
- XIOM-side slots are 4-byte out-params; `int_to_str` is local to the module
  (no stdlib convert inside confined blocks).
- 0.3.0 keeps the scalar/cached-return bridge style: probes write results
  into C statics and the module reads them through getters -- no
  foreign-pointer reads (the B-20 rule).
- 0.4.0 extends the same discipline to every new leg (device/engine/graph/
  capture/stream): all state C-side, scalars through getters; floats are
  compared/quantized C-side (`x1000` ints + exactness flags), never
  marshalled.
- 0.4.0 live legs are silent by construction: the device callback streams a
  silent WAV through the real WAV decoder into the output buffer; engine
  sounds are silence. Evidence is counters (frames/callbacks/decoded) and
  the engine frame clock -- no audible surprise.
- Device-loss boundary: `started`/`stopped` notifications are proven live;
  `rerouted`/interruption/unlock are wired but require a real default-device
  change (cannot be forced in-process). The graph leg proves the
  detach/reattach recovery shape on a sound node.
- Capture is typed: no endpoint -> `opened=false` + `ma_result` code; silent
  endpoint -> `opened=true, frames=0`; both are non-fatal SKIP-style
  outcomes that still exercise `ma_device_init(ma_device_type_capture)`.
- The MP3 fixture decodes through dr_mp3 with the LAME gapless trim (64
  frames, peak 19039 -- matching the ffmpeg reference decode); assertions
  use bounds, not exact samples, for the lossy leg.

## Known limitations

- Scope at 0.4.0: everything in `SPEC.md` section 5. Opus/Ogg custom
  decoder backends, effect nodes/spatialization, and the full
  resource-manager surface are staged (`ROADMAP.md`).
- The device-count and negotiation reports are environment-dependent; a
  serviceless host reports the device/engine checks as SKIP-typed passes.
- `vendor/miniaudio.h` is 4.1 MB; the amalgamation compile adds a few
  seconds to the suite build (watchdog headroom is fine).
