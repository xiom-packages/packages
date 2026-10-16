# PROVENANCE: xiom.miniaudio

<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

Recorded at the 0.4.0 feature touch (A04 growth, 2026-10-16) and extended at
the 0.5.0 handle-surface touch (engine ask `REL-20261016-2139-packages-2`,
2026-10-17), per the per-touch PROVENANCE rule. No re-carve at 0.5.0: the
vendored pin (0.11.25) is unchanged and byte-identical.

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
- 0.5.0 handle surface (read from the pinned header): `ma_backend_null`
  explicit selection via the `backends` array of `ma_context_init` (the
  `case ma_backend_null` context-init arm), the default priority list
  (`ma_context_init(NULL, 0, ...)` iterates `0..ma_backend_null` -- the null
  backend is the last resort and "always works"), the null backend's
  `onDeviceDataLoop = NULL` contract (miniaudio's generic device thread
  drives the callback; the null read/write API is blocking and timer-paced),
  `ma_device_config.pUserData`, and `ma_device_start`/`ma_device_stop`
  semantics (stop is synchronous; start on a started device is an invalid
  operation -- surfaced here as the typed `STATE` error).

**Vendored verbatim (byte-identical to the tag; hashes in section 1 / SPEC.md section 2)**

- `vendor/miniaudio.h`, `vendor/LICENSE`.

**Original XIOM work (MIT OR Apache-2.0)**

- `miniaudio.xi` -- the single confined module: extern declarations, wrapper
  types and all public functions (version/context/decode/encode from 0.2.0/
  0.3.0; device lifecycle, engine, node graph, capture, streamed decode in
  0.4.0; the long-lived device-handle surface -- open/close once, render
  registration, start/stop, wait, info, typed `MaHandleError` -- in 0.5.0).
  No foreign pointer crosses the boundary (B-20 discipline: every complex
  leg caches into C statics read through scalar getters; floats are
  compared/quantized C-side and never marshalled); the 0.5.0 handle state
  lives in a C-side 4-slot registry with monotonic ids and scalar counters.
- `src/miniaudio_all.c` -- compile unit: `MINIAUDIO_IMPLEMENTATION` + the
  `extern "C"` bridge (`xma_*`). The 0.4.0 additions were written against
  the pinned header (callbacks, negotiation readback, exact mix math); the
  0.5.0 additions (handle registry, device-thread render trampoline with
  marker verification, bounded wait) likewise.
- `tests/test_conformance.xi`, `tests/fixtures/**`,
  `SPEC.md`/`ROADMAP.md`/`README.md`/`AUDIT.md`/this file.

## 4. Upstream findings recorded at this touch (0.5.0)

- **The null backend can be requested explicitly** (`backends[] =
  { ma_backend_null }`) and always initializes; it is also the tail of the
  default priority list, so `ma_context_init(NULL, 0, NULL, ...)` can land
  on it when the live backends fail at context time. This is the
  deterministic battery device: real-time paced, no audio service, silent.
- **The null backend delegates its audio thread to miniaudio**
  (`onDeviceDataLoop = NULL`; the generic device thread performs blocking
  read/write at the internal period and calls the client data callback),
  so the registered render callback runs on a miniaudio-created thread --
  the audio-thread contract. Verified in-process: with an explicit
  `ma_backend_null` device, the render callback fires every ~10 ms at the
  480-frame/48 kHz period.
- **Foreign-thread XIOM callback feasibility probe (pre-ship)**: a bare
  top-level XIOM fn handed to a C worker thread (which invokes it
  repeatedly while the main thread executes concurrent XIOM code) ran
  green on the v0.64.5 pin and the v0.64.6 slot -- marker writes into the
  C-owned buffer landed and module-level counters advanced (see AUDIT.md
  "Design notes"). This gate preceded the 0.5.0 design (the same class as
  the earlier callback-ABI gates).
- **Handle-id discipline**: miniaudio itself reuses nothing here; XIOM-side
  monotonic ids + slot lookup are the package's own guard so that a stale
  handle never addresses a newer device (typed `BAD_HANDLE` instead).
- **0.4.0 findings retained**: `ma_sound` is node-compatible (detach/
  reattach proven numerically in the mix); `ma_device_stop` fires the
  stopped notification synchronously; dr_mp3 applies the LAME gapless trim
  (fixture decodes to exactly 64 frames, peak 19039 matching the ffmpeg
  reference decode).

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
2. Re-read the 0.4.0/0.5.0 bridge call sites against the new header (the
   pinned API names are listed in section 3; the 0.5.0 handle leg relies on
   `ma_backend_null` explicit selection, the `pUserData` field, and the
   generic device-thread contract); fix any API drift in
   `src/miniaudio_all.c` only -- the XIOM surface stays stable.
3. Regenerate fixtures only if the decoder behavior changed
   (`make_fixtures.ps1`, then re-record the hashes here and in
   `tests/fixtures/README.md`).
4. Re-run `scripts/port.ps1 -Package xiom.miniaudio -TimeoutSec 300` (x2),
   update the SPEC.md test matrix, record via `scripts/status.ps1 -Action
   update`.
