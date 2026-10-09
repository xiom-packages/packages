# xiom.miniaudio

miniaudio (audio playback/capture) bindings for XIOM via the **vendored
single header** (0.11.25, Unlicense OR MIT-0). The library is compiled into
the test binary -- no system audio library at link time.

> **Status:** `incubating` -- suite green x2 on the pin (v0.64.1): 4/4
> (miniaudio 0.11.25, 9 playback + 4 capture devices enumerated, in-memory
> WAV decode verified at 16 frames / 1 channel / 8000 Hz / s16).
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

Expected: 4 `[PASS]`, exit 0. Playback engines/mixing/encoding are Phase 2
(`ROADMAP.md`).
