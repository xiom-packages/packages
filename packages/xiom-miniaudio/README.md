# xiom.miniaudio

miniaudio (audio playback/capture) bindings for XIOM via the **vendored
single header** (0.11.25, Unlicense OR MIT-0). The library is compiled into
the test binary -- no system audio library at link time.

> **Status:** `incubating` -- suite green on the pin (v0.64.5): **27/27**
> (miniaudio 0.11.25, 9 playback + 4 capture devices enumerated, in-memory
> WAV decode seed-checked, encoder + file round trip sample-exact; live
> **device** lifecycle on explicit WASAPI (mix-pull callbacks, built-in WAV
> decoder streamed in the callback, started/stopped notifications), live
> **engine** (memory + file sounds), device-free **node graph** and exact
> mix math (group/per-sound volume+pitch, attach/detach), **capture** open
> attempt with typed non-fatal outcomes, and streamed **WAV/FLAC/MP3**
> decode in 13-frame chunks). 0.2.0 shipped in `eco-v0.1.114`; 0.3.0
> published in `eco-v0.1.154` (sha256 `6a2a77dd...`).
> **Lane:** bindings (`keywords: ["binding"]`).
> **Published**: `0.4.0` in `eco-v0.1.187` (sha256 `382a16f0...`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.miniaudio;

fn main() {
  io.println("miniaudio " + to_string(ma_version_packed()));
  let dev = ma_device_lifecycle();
  if dev.is_ok {
    io.println("device: " + ma_backend_name(dev.value.backend)
      + " internal=" + to_string(dev.value.internal_rate) + " Hz");
  } else {
    io.println("device: SKIP -- " + dev.error);
  }
  let wav = ma_stream_decode(1);
  if wav.is_ok {
    io.println("streamed " + to_string(wav.value.frames) + " frames in "
      + to_string(wav.value.chunks) + " chunks");
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
| Backends | `ma_backend_name` (id -> name) |
| Constants | `MA_FORMAT_*` |

Failure model: no library-absence path (vendored). The context check reports
SKIP-with-code on hosts without an audio service; the live device/engine
legs report SKIP-typed step codes when the environment blocks audio (the
call paths are still exercised); capture without an endpoint is a typed
non-fatal outcome; decode mismatches are FAILs. Live legs are silent by
construction.

## Build note

`port.args.json` compiles `src/miniaudio_all.c`
(`MINIAUDIO_IMPLEMENTATION` + the `xma_*` bridge over `vendor/miniaudio.h`);
no `--link` flags. Provenance + re-pin: `SPEC.md` section 2 and
`PROVENANCE.md`.

## Tests

```
scripts/port.ps1 -Package xiom.miniaudio
```

Expected: 27 `[PASS]`, exit 0 (streamed-decode fixtures live in
`tests/fixtures/`). Opus/Ogg custom decoder backends are staged
(`ROADMAP.md`).
