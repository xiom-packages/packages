# xiom.miniaudio -- test fixtures (streamed decode)

Committed byte fixtures for the 0.4.0 streamed-decode legs, generated from
the same 64-frame 8 kHz mono s16 tone the compile unit embeds (`kSine16` in
`src/miniaudio_all.c`: four periods of the 16-sample sine). The test suite
only reads these files; it never regenerates them.

| File | Bytes | SHA256 | Role |
|------|-------|--------|------|
| `tone.flac` | 8,379 | `754E7FA362A80E0D0112ED7D37AC7734155202D1F5D53BA96E05FD4936EF3EE2` | lossless -- decoded sample-exact (64 frames) by the vendored dr_flac |
| `tone.mp3` | 2,349 | `63C5DD0F8663488F25EAF973771CFE9B98A24A7CFC2DCECCD5D16F813E185C52` | 64 kbps CBR MPEG-2.5 Layer III -- lossy, checked by rate/channels/frame count/peak |

Regenerate (dev-time only) with any ffmpeg that has the flac and libmp3lame
encoders:

```powershell
.\make_fixtures.ps1 -Ffmpeg <path-to-ffmpeg.exe>
```

The script rebuilds the source WAV from the `kSine16` table (no external
input), encodes `tone.flac` (lossless) and `tone.mp3` (64 kbps CBR at
8 kHz mono), and prints the resulting hashes.  The 0.4.0 fixtures were
generated with ffmpeg 4.4.4 (flac_encoder + libmp3lame enabled) on
2026-10-16; the FLAC decode was cross-checked against the raw tone bytes
with the same ffmpeg before committing.
