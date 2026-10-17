# xiom.miniaudio

miniaudio (audio playback/capture) bindings for XIOM via the **vendored
single header** (0.11.25, Unlicense OR MIT-0). The library is compiled into
the test binary -- no system audio library at link time.

> **Status:** `incubating` -- suite green on the pin (v0.64.5) **and
> re-verified on the v0.64.6 slot: 44/44** (miniaudio 0.11.25, 9 playback +
> 4 capture devices enumerated, in-memory WAV decode seed-checked, encoder +
> file round trip sample-exact; live **device** lifecycle on explicit WASAPI
> (mix-pull callbacks, built-in WAV decoder streamed in the callback,
> started/stopped notifications), live **engine** (memory + file sounds),
> device-free **node graph** and exact mix math (group/per-sound
> volume+pitch, attach/detach), **capture** open attempt with typed
> non-fatal outcomes, streamed **WAV/FLAC/MP3** decode in 13-frame chunks,
> and the 0.5.0 **long-lived device handles** (null-device battery:
> open-once handle, render registration/replace/clear while running,
> start/stop cycles, typed errors, 4-slot registry) plus the live
> auto/WASAPI open legs). 0.2.0 shipped in `eco-v0.1.114`; 0.3.0
> published in `eco-v0.1.154` (sha256 `6a2a77dd...`); 0.4.0 in
> `eco-v0.1.187`; 0.5.0 single tag `xiom-miniaudio/v0.5.0` (sha256
> `7d83c1ed...`, 2026-10-17).
> **Lane:** bindings (`keywords: ["binding"]`).
> **Published**: `0.5.0` (single tag `xiom-miniaudio/v0.5.0`, sha256 `7d83c1ed...`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.miniaudio;

fn render_silence(out: *UInt8, frames: Int32) -> Unit {
  // fill interleaved f32 stereo frames (the requested 48 kHz shape)
}

fn main() {
  io.println("miniaudio " + to_string(ma_version_packed()));
  let dev = ma_device_lifecycle();
  if dev.is_ok {
    io.println("device: " + ma_backend_name(dev.value.backend)
      + " internal=" + to_string(dev.value.internal_rate) + " Hz");
  } else {
    io.println("device: SKIP -- " + dev.error);
  }
  // 0.5.0: a long-lived device handle -- open once, run callbacks/streams
  // over time, close once (typed errors throughout).
  let h = ma_device_handle_open_backend(MA_HANDLE_BACKEND_NULL);
  if h.is_ok {
    let hh = h.value;
    let sr = ma_device_handle_set_render(hh, render_silence);
    let st = ma_device_handle_start(hh);
    let w = ma_device_handle_wait(hh, 10, 2000);
    let inf = ma_device_handle_info(hh);
    if inf.is_ok {
      io.println("handle: " + to_string(inf.value.callbacks) + " callbacks, "
        + to_string(inf.value.frames) + " frames");
    }
    let sp = ma_device_handle_stop(hh);
    let cl = ma_device_handle_close(hh);
  } else {
    io.println("handle: SKIP -- " + h.error.message);
  }
}
```

## API

| Area | Functions |
|------|-----------|
| Version | `ma_version_packed` |
| Devices | `ma_context_probe` -> `MaContextInfo` (playback/capture counts) |
| Decode | `ma_decode_probe` -> `MaWavInfo` (frames/channels/rate/format) |
| Encode (0.3.0) | `ma_encode_roundtrip` -> `Result[MaEncodeInfo, Str]` (64-frame s16 WAV via `ma_encoder` -> `ma_decoder_init_file` re-decode, sample-exact, temp file removed; device-free) |
| Device lifecycle (0.4.0) | `ma_device_lifecycle` -> `Result[MaDeviceInfo, Str]` (open/start/mix-pull/stop/close; WASAPI requested explicitly, negotiated shape, callback + decoded-frame counters, notification hooks) |
| Engine (0.4.0) | `ma_engine_probe` -> `Result[MaEngineInfo, Str]` (init/start/stop; memory sound play/stop; file sound fire-and-forget) |
| Node graph (0.4.0) | `ma_graph_probe` -> `Result[MaGraphInfo, Str]` (device-free: standalone attach/detach, exact mix math through a sound group + per-sound volumes, sound detach/reattach, pitch rate effect) |
| Capture (0.4.0) | `ma_capture_probe` -> `Result[MaCaptureInfo, Str]` (enumerate + open; typed non-fatal outcomes: no device / silent endpoint) |
| Streamed decode (0.4.0) | `ma_stream_decode(which)` -> `Result[MaStreamInfo, Str]` (1=WAV, 2=FLAC, 3=MP3; chunked data-source pulls) |
| **Handles (0.5.0)** | `ma_device_handle_open` / `ma_device_handle_open_backend(which)` -> `Result[Int, MaHandleError]` (open a long-lived playback device once: `MA_HANDLE_BACKEND_AUTO`/-1 default priority list, `MA_HANDLE_BACKEND_WASAPI`/0, `MA_HANDLE_BACKEND_NULL`/14; fixed client shape f32 stereo 48 kHz, 480-frame period; 4 live handles max) |
| **Handles (0.5.0)** | `ma_device_handle_set_render(handle, cb)` / `ma_device_handle_clear_render(handle)` -> `Result[Unit, MaHandleError]` (register/replace/clear the render callback over time, running included; the callback is an env-free top-level fn `fn(*UInt8, Int32) -> Unit` invoked on the device thread with the pre-silenced f32 stereo output buffer and the frame count) |
| **Handles (0.5.0)** | `ma_device_handle_start(handle)` / `ma_device_handle_stop(handle)` -> `Result[Unit, MaHandleError]` (stream cycles over time; start-while-started and stop-while-idle are the typed `MA_HANDLE_ERR_STATE`) |
| **Handles (0.5.0)** | `ma_device_handle_wait(handle, target_callbacks, timeout_ms)` -> `Result[Unit, MaHandleError]` (bounded wait for render progress) |
| **Handles (0.5.0)** | `ma_device_handle_info(handle)` -> `Result[MaHandleInfo, MaHandleError]` (negotiated shape + device-thread counters `callbacks`/`frames`/`marked` + `started`/`render_set`/`starts`/`stops`) |
| **Handles (0.5.0)** | `ma_device_handle_close(handle)` -> `Result[Unit, MaHandleError]` (close once; a running stream is stopped first; any op on a closed handle -- double close included -- is the typed `MA_HANDLE_ERR_BAD_HANDLE`; ids are never reused) |
| Backends | `ma_backend_name` (id -> name) |
| Constants | `MA_FORMAT_*`, `MA_HANDLE_BACKEND_*`, `MA_HANDLE_ERR_*` |

Handle-surface coverage note (standing owner policy): the declared handle
surface is **100% exercised** by the suite -- all 9 functions; the
deterministic typed error paths (`NO_CONTEXT` via a bogus backend id,
`EXHAUSTED` via the 5th concurrent open, `BAD_HANDLE` across all 7 handle
operations on unknown and closed handles, `STATE` on start-twice/stop-idle);
the environment-typed paths (`NO_DEVICE` gates the live auto/WASAPI open as
a SKIP-typed pass when no endpoint is usable; `STEP` is the internal-failure
floor); registration churn (set / replace / clear) over time while the
stream runs; two start/stop cycles; close-while-running; and the live
auto/WASAPI open legs. The deterministic part of the battery runs on the
**null backend** (`MA_HANDLE_BACKEND_NULL`), which always opens, is paced
at real time and needs no audio service; the live legs (auto/WASAPI
open+info+close) degrade to typed SKIP on hosts without audio.

Failure model: no library-absence path (vendored). The context check reports
SKIP-with-code on hosts without an audio service; the live device/engine
legs report SKIP-typed step codes when the environment blocks audio (the
call paths are still exercised); capture without an endpoint is a typed
non-fatal outcome; decode mismatches are FAILs. The live legs are silent by
construction; the handle battery writes only the two marker bytes its
trampoline checks (denormal-scale samples -- effectively silent) and runs on
the null device.

## Build note

`port.args.json` compiles `src/miniaudio_all.c`
(`MINIAUDIO_IMPLEMENTATION` + the `xma_*` bridge over `vendor/miniaudio.h`);
no `--link` flags. Provenance + re-pin: `SPEC.md` section 2 and
`PROVENANCE.md`.

## Tests

```
scripts/port.ps1 -Package xiom.miniaudio
```

Expected: 44 `[PASS]`, exit 0 (streamed-decode fixtures live in
`tests/fixtures/`). The handle battery's deterministic leg runs on the
null backend; the live device/engine/capture legs degrade to typed SKIP on
hosts without an audio service. Opus/Ogg custom decoder backends are staged
(`ROADMAP.md`).
