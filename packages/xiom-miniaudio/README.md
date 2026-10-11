# xiom.miniaudio

miniaudio (audio playback/capture) bindings for XIOM via the **vendored
single header** (0.11.25, Unlicense OR MIT-0). The library is compiled into
the test binary -- no system audio library at link time.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.3): 6/6
> (miniaudio 0.11.25, 9 playback + 4 capture devices enumerated, in-memory
> WAV decode verified at 16 frames / 1 channel / 8000 Hz / s16, and a
> device-free encoder + file round trip: 64 frames sample-exact, temp file
> removed). 0.2.0 shipped in `eco-v0.1.114`; 0.3.0 published in
> `eco-v0.1.154` (sha256 `6a2a77dd...`).
> **Lane:** bindings (`keywords: ["binding"]`).

## Quick start

```xiom
use xiom.io;
use xiom.convert;
use xiom.miniaudio;

fn main() {
  io.println("miniaudio " + to_string(ma_version_packed()));
  let ctx = ma_context_probe();
  if ctx.is_ok {
    io.println("playback devices: " + to_string(ctx.value.playback_count));
  }
  let wav = ma_decode_probe();
  if wav.is_ok {
    io.println("decoded " + to_string(wav.value.frames) + " frames");
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
| Constants | `MA_FORMAT_*` |

Failure model: no library-absence path (vendored). The context check reports
SKIP-with-code on hosts without an audio service; decode mismatches are
FAILs.

## Build note

`port.args.json` compiles `src/miniaudio_all.c`
(`MINIAUDIO_IMPLEMENTATION` + the probe bridge over `vendor/miniaudio.h`);
no `--link` flags. Provenance + re-pin: `SPEC.md` §2.

## Tests

```
scripts/port.ps1 -Package xiom.miniaudio
```

Expected: 6 `[PASS]`, exit 0. Playback engines/mixing/capture are Phase 2
(`ROADMAP.md`).
