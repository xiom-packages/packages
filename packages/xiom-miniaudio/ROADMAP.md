# xiom.miniaudio -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-09

## Current state

| Criterion | Status |
|-----------|--------|
| Vendored single header (G2 pinned) | Done -- 0.11.25 |
| FFI core + probe bridge (single confined module) | Done |
| Version + context/device enumeration | Done -- 9 playback / 4 capture |
| In-memory WAV decode (spot-checked) | Done |
| Playback engine (`ma_engine`) | Phase 2 |
| Mixing/effects (node graph) | Phase 2 |
| Capture + ring buffer | Phase 2 |
| Encoding (`ma_encoder`, WAV write) | Phase 2 |
| File decoding (`ma_decoder_init_file`) | Phase 2 |

## Phase 2 (next touches)

1. Playback engine: `ma_engine_init` + `ma_engine_play_sound` with a
   generated in-memory sound (SKIP when no playback device); keep the
   callback-free API shape.
2. Encoding: `ma_encoder` over an in-memory backend or file; WAV encode of a
   generated sine + re-decode round-trip.
3. Capture: `ma_device` capture with a ring buffer (device-gated SKIP).
4. Node graph: `ma_node_graph`/`ma_engine` mixing with two sources.
5. File I/O: `ma_decoder_init_file`/`ma_encoder_init_file` using the fs
   helpers (fs_remove now available in stdlib 0.64.2 for temp cleanup).
6. Consumer note: PULSE/XVECTOR do not need audio; keep the API stable for
   media consumers.

## Sector note

Audio sector, package 1 of 3 (`xiom.miniaudio` done; `xiom.portaudio` then
`xiom.phonon` next per the proposal).
