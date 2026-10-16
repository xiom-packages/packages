# PROVENANCE: xiom.miniaudio

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

Recorded at the 0.4.0 feature touch (A04 growth, 2026-10-16), per the
per-touch PROVENANCE rule.

## 1. Upstream

| Field | Value |
|-------|-------|
| Upstream project | miniaudio -- `https://github.com/mackron/miniaudio` |
| Pin | tag `0.11.25` (header version string `0.11.25 -- 2026-03-04`, `MA_VERSION_MAJOR/MINOR` = 0/11, revision 25) |
| Header of record | `vendor/miniaudio.h` -- 4,108,168 bytes, SHA256 `AC7AF4DE748B7E26B777F37E01CEE313A308A7296A3EB080E2906B320CC55C89` (re-verified byte-identical at this touch) |
| Fetch source of the pin | `https://raw.githubusercontent.com/mackron/miniaudio/0.11.25/miniaudio.h` (vendored verbatim; `.gitattributes` pins `vendor/** -text`) |
| Upstream-first note | The vendored header is the study artifact: every API used by the 0.4.0 bridge (device lifecycle, `ma_engine`, node graph, capture, `dr_wav`/`dr_flac`/`dr_mp3` decoders) was read from the pinned header itself, not from documentation or memory. No separate clone was needed because the whole library is the one pinned file. |

## 2. License (vendored copy)

| Component | License | Evidence |
|-----------|---------|----------|
| `miniaudio.h` (amalgamated: core + `dr_wav` + `dr_flac` + `dr_mp3`) | Unlicense (public domain) OR MIT-0, at your option | header comment + `vendor/LICENSE` (2,597 bytes, SHA256 `457F1B500E0ADF6BC059EDDDFA78A2F62012E7C3BB43476C20E0BD23B25BA0EB`) |
| Package (everything outside `vendor/`) | MIT OR Apache-2.0 | `package.xi`, file headers |

Class: permissive -- verbatim vendoring is allowed. Backends loaded at
runtime are the OS's own (WASAPI/DSound/WinMM loaded by miniaudio itself; no
system audio library is linked and no library of ours ships).

## 3. What was studied, what was derived

**Studied (read for the surface and behavior model, from the pinned header)**

- `ma_device_config` / `ma_device_notification` / `ma_device_notification_type_*` --
  the lifecycle surface (open/start/mix-pull/stop/close) and the loss hooks
  (started/stopped/rerouted/interruption/unlocked).
- `ma_context_init` backend arrays + `ma_backend` priority enum (WASAPI first
  on Windows) and `ma_get_backend_name`.
- `ma_device` internals (`playback.internalSampleRate/internalFormat/
  internalChannels/internalPeriodSizeInFrames`) -- the negotiated shape of
  the opened endpoint.
- `ma_engine`, `ma_engine_config` (`noDevice`, `noAutoStart`), `ma_sound`
  (layout comment: `engineNode` first member "for compatibility with the
  ma_node API"), `ma_sound_group`, per-sound/group volume+pitch API,
  `ma_engine_read_pcm_frames`, `ma_engine_get_time_in_pcm_frames`,
  `ma_engine_play_sound` (fire-and-forget).
- Node graph: `ma_node_graph_init`, `ma_node_attach_output_bus` /
  `ma_node_detach_output_bus`, `ma_node_graph_get_endpoint`,
  `ma_node_graph_read_pcm_frames`, `ma_data_source_node_init` +
  `ma_audio_buffer_init` (the canonical "constant source" recipe from the
  usage documentation inside the header).
- Decoders: `ma_decoder` implements the `ma_data_source` pull interface
  (`ma_data_source_read_pcm_frames`); `ma_decoder_config_init` output
  format/channels/rate conversion rules.

**Vendored verbatim (byte-identical to the tag; hashes in section 1 / SPEC.md section 2)**

- `vendor/miniaudio.h`, `vendor/LICENSE`.

**Original XIOM work (MIT OR Apache-2.0)**

- `miniaudio.xi` -- the single confined module: extern declarations, wrapper
  types and all public functions (version/context/decode/encode from 0.2.0/
  0.3.0; device lifecycle, engine, node graph, capture, streamed decode in
  0.4.0). No foreign pointer crosses the boundary (B-20 discipline: every
  complex leg caches into C statics read through scalar getters; floats are
  compared/quantized C-side and never marshalled).
- `src/miniaudio_all.c` -- compile unit: `MINIAUDIO_IMPLEMENTATION` + the
  `extern "C"` bridge (`xma_*`). The 0.4.0 additions were written against
  the pinned header (callbacks, negotiation readback, exact mix math).
- `tests/test_conformance.xi`, `tests/fixtures/**`,
  `SPEC.md`/`ROADMAP.md`/`README.md`/`AUDIT.md`/this file.

## 4. Upstream findings recorded at this touch

- **`ma_sound` is node-compatible** (header comment on the first member);
  the 0.4.0 suite detaches/reattaches a playing sound's output bus with
  `ma_node_detach_output_bus((ma_node*)&sound, 0)` and proves it
  numerically in the mix (0.375 -> 0.25 -> 0.375 exact). This is the
  documented intent, exercised here as a witness.
- **`ma_device_stop` fires the stopped notification synchronously** before
  returning (observed started=1 / stopped=1 on WASAPI); the `rerouted`
  notification cannot be forced in-process (needs a real default-device
  change), so the loss path is wired + documented rather than fabricated.
- **dr_mp3 applies the LAME gapless trim**: the 64-frame fixture decodes to
  exactly 64 frames with peak 19039 (matching the ffmpeg reference decode of
  the same file); the suite nonetheless checks bounds, not exact samples,
  for the lossy leg.

## 5. Test data

- `tests/fixtures/tone.flac` / `tone.mp3`: 64-frame 8 kHz mono s16 tone
  (four periods of the embedded `kSine16` sine), generated with a local
  ffmpeg 4.4.4 (flac + libmp3lame). The generation script
  (`tests/fixtures/make_fixtures.ps1`) rebuilds the source WAV from the
  embedded table -- no external audio data is imported. Hashes:
  `754E7FA3...` (FLAC, sample-exact against the table) and `63C5DD0F...`
  (MP3, energy-checked). See `tests/fixtures/README.md`.
- No upstream test vectors were imported.

## 6. Re-carve procedure

1. Fetch the new tag's `miniaudio.h` + `LICENSE` from
   `raw.githubusercontent.com/mackron/miniaudio/<tag>/`; verify the header's
   version string and both SHA256 hashes; update SPEC.md section 2 and
   section 1 above.
2. Re-read the 0.4.0 bridge call sites against the new header (the pinned
   API names are listed in section 3); fix any API drift in
   `src/miniaudio_all.c` only -- the XIOM surface stays stable.
3. Regenerate fixtures only if the decoder behavior changed
   (`make_fixtures.ps1`, then re-record the hashes here and in
   `tests/fixtures/README.md`).
4. Re-run `scripts/port.ps1 -Package xiom.miniaudio -TimeoutSec 300` (x2),
   update the SPEC.md test matrix, record via `scripts/status.ps1 -Action
   update`.
