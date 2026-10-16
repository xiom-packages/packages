# SPEC: xiom.miniaudio -- miniaudio bindings (vendored single header)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.miniaudio` |
| Version | 0.5.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | miniaudio -- https://github.com/mackron/miniaudio |
| Upstream version pinned | tag **0.11.25** |
| Upstream license | Unlicense (public domain) OR MIT-0, at your option (`vendor/LICENSE`) |
| Package license | MIT OR Apache-2.0 (everything outside `vendor/`) |
| Platform | Windows x64 (miniaudio resolves platform backends itself) |
| Compiler pin | v0.64.5 (suite re-verified on the v0.64.6 slot) |

Provenance of record: `PROVENANCE.md` (upstream pin, license, studied vs
derived, findings, fixtures, re-carve procedure).

## 2. Vendored path (G2 pin)

The single-header library is vendored **verbatim** into `vendor/` and
compiled via `src/miniaudio_all.c` (`MINIAUDIO_IMPLEMENTATION` plus the
`extern "C"` bridge) with `--c-source`; no system audio library at link
time, no runtime DLL of ours (the OS backends miniaudio loads are the
platform's).

| File | Bytes | SHA256 |
|------|-------|--------|
| `vendor/miniaudio.h` (tag 0.11.25) | 4,108,168 | `AC7AF4DE748B7E26B777F37E01CEE313A308A7296A3EB080E2906B320CC55C89` |
| `vendor/LICENSE` | 2,597 | `457F1B500E0ADF6BC059EDDDFA78A2F62012E7C3BB43476C20E0BD23B25BA0EB` |

### Provenance

| Artifact | Value |
|----------|-------|
| Header URL | https://raw.githubusercontent.com/mackron/miniaudio/0.11.25/miniaudio.h |
| License URL | https://raw.githubusercontent.com/mackron/miniaudio/0.11.25/LICENSE |
| Upstream repo | https://github.com/mackron/miniaudio (tag `0.11.25`) |

`.gitattributes` pins `vendor/** -text`. Re-pin: fetch the new tag's header +
LICENSE, recompute hashes, update the table and version rows, re-run
`scripts/port.ps1 -Package xiom.miniaudio` (x2). Full procedure:
`PROVENANCE.md` section 6.

## 3. Design and safe boundary (G5)

`miniaudio.xi` is the only module with `extern "C"`; every foreign call is
wrapped here. Out-params use XIOM-owned 4-byte slots read little-endian;
complex legs cache their result in file-scope C statics exposed through
scalar getters (no foreign pointer crosses the boundary -- the B-20 rule;
floats are compared/quantized C-side and never marshalled). Local
`int_to_str` for error text (the stdlib convert must not be called inside
confined blocks -- see the lane findings).

0.5.0 handle discipline: a fixed **4-slot C registry** holds each open
context + device (file-scope statics; the `ma_device`/`ma_context` structs
are initialized in place and never copied); the handle token is a
monotonically increasing id stored in the slot, so a closed handle can
never alias a newer one -- every operation on a stale handle is the typed
`MA_HANDLE_ERR_BAD_HANDLE`. The render callback is handed to C once as an
env-free top-level XIOM fn (`fn(*UInt8, Int32) -> Unit`; the direct-handoff
callback ABI closed on the v0.64.5 pin) and is **invoked on the device
thread** -- the miniaudio audio-thread contract; the trampoline reads the
registered pointer once per buffer (registration churn while running is at
most one in-flight callback behind) and verifies the two known marker bytes
the suite's renders write, so "the render's writes landed" is counted
(`marked`) rather than assumed. Device-thread counters (`callbacks`,
`frames`, `marked`, `starts`, `stops`) are read by the owner thread through
the info snapshot; the waiting model keeps the owner thread in C
(`ma_device_handle_wait` / bounded sleeps) while the stream runs. Error
typing: `MaHandleError { kind, rc, message }` -- kinds `NO_CONTEXT`,
`NO_DEVICE`, `BAD_HANDLE`, `EXHAUSTED`, `STATE`, `STEP`; `rc` carries the
`ma_result` wherever one exists.

Bridge surface:

| Leg | Functions | Notes |
|-----|-----------|-------|
| Pilot | `ma_version_packed`, `ma_context_probe` (context init + device enumeration), `ma_decode_probe` (in-memory WAV decode spot-checked) | device-free except the context |
| 0.3.0 | `ma_encode_roundtrip` (`ma_encoder` WAV write -> `ma_decoder_init_file` re-decode -> sample compare -> temp cleanup) | device-free, deterministic |
| 0.4.0 device | `ma_device_lifecycle` -> `MaDeviceInfo` | open -> start -> mix-pull -> stop -> close; WASAPI context requested explicitly first, automatic priority list as fallback; negotiated shape read back (`internal_rate`/`internal_channels`/`period_frames`); the mix callback streams a built-in WAV decoder into the output buffer; `started`/`stopped` notifications counted, `rerouted` wired for the unplug case (cannot be forced in-process -- documented boundary) |
| 0.4.0 engine | `ma_engine_probe` -> `MaEngineInfo` | `ma_engine` with explicit start/stop; sound from memory (WAV decoder data source, looping) play/stop with cursor evidence; file sound via `ma_engine_play_sound` (fire-and-forget from a temp WAV); engine frame clock is the mix evidence |
| 0.4.0 graph | `ma_graph_probe` -> `MaGraphInfo` | device-free: standalone `ma_node_graph` attach/detach over a constant `ma_audio_buffer` (0.25 reads, silence after detach); noDevice engine exact mix math (sound group 0.5 x per-sound volumes -> 0.375 exact), sound detach -> 0.25, reattach -> 0.375, volume/pitch get/set, pitch 2.0 cursor-rate ratio; all values quantized x1000 + C-side exactness flags |
| 0.4.0 capture | `ma_capture_probe` -> `MaCaptureInfo` | enumerate capture devices + open attempt; typed non-fatal outcomes: `opened=false` with the `ma_result` in `rc` (no capture device) or `opened=true, frames=0` (silent endpoint); `Err` only for unexpected internal failures |
| 0.4.0 stream | `ma_stream_decode(which)` -> `MaStreamInfo` | chunked (13-frame) pulls through the decoder data source (`ma_data_source_read_pcm_frames`); 1 = in-memory WAV (sample-exact), 2 = FLAC fixture (lossless, sample-exact), 3 = MP3 fixture (rate/channels/frames/energy); chunk counter proves the streaming shape |
| 0.5.0 handles | `ma_device_handle_open` / `ma_device_handle_open_backend(which)` -> `Result[Int, MaHandleError]` | open once: a long-lived playback device (context + device + fixed client shape f32 stereo 48 kHz, 480-frame period) kept alive until close; `which` = `MA_HANDLE_BACKEND_AUTO` (-1; default priority list), `MA_HANDLE_BACKEND_WASAPI` (0), `MA_HANDLE_BACKEND_NULL` (14, deterministic silent device); 4 live handles max (`EXHAUSTED` beyond) |
| 0.5.0 handles | `ma_device_handle_set_render(handle, cb)` / `ma_device_handle_clear_render(handle)` | register / replace / clear the render callback over time, running included; `cb` is an env-free top-level `fn(*UInt8, Int32) -> Unit` invoked on the device thread with the pre-silenced output buffer + frame count (f32 stereo 48 kHz client shape) |
| 0.5.0 handles | `ma_device_handle_start(handle)` / `ma_device_handle_stop(handle)` | stream start/stop cycles over time; start-while-started / stop-while-idle are `MA_HANDLE_ERR_STATE`; start without a render is allowed (silence) |
| 0.5.0 handles | `ma_device_handle_wait(handle, target_callbacks, timeout_ms)` | bounded wait for render progress (1 ms sleeps; Ok either way -- counters via info) |
| 0.5.0 handles | `ma_device_handle_info(handle)` -> `MaHandleInfo` | negotiated shape (`backend`/`rate`/`channels`/`period_frames`) + device-thread counters (`callbacks`/`frames`/`marked`) + `started`/`render_set`/`starts`/`stops`; `marked` = buffers in which the registered render's writes were observed |
| 0.5.0 handles | `ma_device_handle_close(handle)` | close once: a running stream is stopped first, device + context uninitialized, the slot released; stale ops (double close included) are `MA_HANDLE_ERR_BAD_HANDLE` (ids never reused) |

Live device legs are **silent by construction** (the streamed WAV and the
engine sounds are silence -- no audible surprise) and degrade to typed
SKIP-style checks when the environment blocks audio, while still proving the
call paths. The 0.5.0 handle battery's deterministic leg runs on the null
backend (always openable, real-time paced, no audio service); its live legs
(auto/WASAPI open + info + close) degrade to typed SKIP the same way. Test
fixtures: `tests/fixtures/` (README there records hashes; generation script
rebuilds the source tone from the embedded table).

## 4. Test matrix (recorded 2026-10-16/17, compiler v0.64.5)

| Configuration | Command | Result |
|---------------|---------|--------|
| Vendored header (always compiled in) | `scripts/port.ps1 -Package xiom.miniaudio -TimeoutSec 300` | **PASS 44/44 x2 on the v0.64.5 pin; x2 re-verify on the v0.64.6 slot** -- version 0.11.25; context playback=9/capture=4; WAV decode 16 frames/1ch/8000 Hz/s16; encoder round trip 64 frames sample-exact + temp cleanup; **device**: explicit WASAPI (internal 48000/2ch, period 480), mix-pull 10 callbacks/4800 frames, 4800 frames streamed from the built-in WAV decoder inside the live callback, notifications started=1/stopped=1; **engine**: init/start/play/stop lifecycle on WASAPI, memory-sound cursor advanced, file sound accepted; **graph**: standalone attach 250/1000 + detach silence, mix exact 375/1000, detach 250/1000, reattach 375/1000, group volume 500/1000, sound volume 250/1000, pitch get 1500/1000, pitch-2.0 cursor ratio 2000/1000; **capture**: opened + frames (enumerated devices); **stream**: WAV 16 frames exact in 2 chunks, FLAC 64 frames exact in 5 chunks, MP3 64 frames/8000 Hz/1ch peak 19039; **handles (null battery)**: open-once handle + fresh info (null backend, 48000 Hz/2ch, period 480f), render registered + stream started, start-twice typed STATE, running counters (6 callbacks/2880 frames/6 marked == 6 XIOM calls), render replaced while running (B took over 9 calls, A frozen 6), render cleared while running (callbacks continued, B frozen 9), stop halts the stream (frozen 24; marked == XIOM renders exactly), stop-idle typed STATE, second start/stop cycle (starts=2 stops=2), close-while-running + closed-handle typed BAD_HANDLE, unknown-handle typed BAD_HANDLE (all 7 ops), 4-slot registry + 5th-open typed EXHAUSTED + slot release on close, bogus backend 99 -> typed NO_CONTEXT (rc=-203); **handles (live)**: auto open once -> wasapi device, explicit WASAPI open once -> wasapi device |

There is no library-absence SKIP path (the library is vendored). A host
without an audio service reports the context/device/engine/handle-live
checks as SKIP-typed passes with the miniaudio result code; capture without
an endpoint reports the typed non-fatal outcome; decode mismatches are FAILs.
The handle battery's deterministic leg (null backend) always runs.

## 5. Scope

0.5.0 covers: everything at 0.4.0 (version, context + device enumeration,
in-memory WAV decoding and the encoder/file round trip; live playback device
lifecycle with driver negotiation and notification-based loss hooks; live
playback engine (memory + file sounds); node-graph and mixing basics;
capture enumerate + open attempt; streamed decode of WAV/FLAC/MP3 through
the data-source pull path) **plus the long-lived device-handle surface the
engine audio leg asked for** (`REL-20261016-2139-packages-2`): open once ->
register render callbacks / run streams over time -> close once, alongside
the lifecycle bridge, with typed `MaHandleError` kinds throughout and the
null-device battery deterministic on any host.

Handle-surface coverage note (standing owner policy -- 100% of the declared
surface): the suite exercises every declared handle function and the typed
error kinds: all 9 functions (`open`, `open_backend`, `set_render`,
`clear_render`, `start`, `stop`, `wait`, `info`, `close`); `NO_CONTEXT`
(deterministic: bogus backend id), `EXHAUSTED` (5th concurrent open),
`BAD_HANDLE` (all 7 operations on both an unknown handle and a closed
handle, double close included), `STATE` (start-twice, stop-idle);
`NO_DEVICE` and `STEP` gate the live legs -- `NO_DEVICE` is the typed
environment outcome of the auto/WASAPI open legs when the host has no
usable endpoint (the suite records it as a SKIP-typed pass), `STEP` is the
internal-failure floor. Registration churn (set -> replace -> clear) while
running; two start/stop cycles; close-while-running; and the live
auto/WASAPI open+info+close legs are all exercised. Boundaries (documented,
not fabricated): live audio legs are environment-gated (typed SKIP without
a service); the render callback's device-thread execution is witnessed on
the null backend by marker writes + exact counters (a live-WASAPI start
under render is the same `ma_device_start` path the 0.4.0 lifecycle leg
exercises).

Staged (documented in `ROADMAP.md`): opus/ogg custom decoder backends wired
over the live `xiom.opus`/`xiom.ogg` packages (the `ma_decoder` custom
backend seam exists but is not cleanly reachable from the current bridge
shape at this touch); effect nodes, spatialization, and the resource-manager
API beyond `ma_engine_play_sound`; per-handle configurable client shapes
(the handle surface fixes f32 stereo 48 kHz at this touch). The pre-pilot
files referenced a bridge and a miniaudio header that were never vendored;
they are preserved in git history.
