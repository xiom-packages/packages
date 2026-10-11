# xiom.miniaudio -- Roadmap

**Version**: v0.3.0 | **Compiler**: xiom v0.64.3 | **Last updated**: 2026-10-11

## Current state

| Criterion | Status |
|-----------|--------|
| Vendored single header (G2 pinned) | Done -- 0.11.25 |
| FFI core + probe bridge (single confined module) | Done |
| Version + context/device enumeration | Done -- 9 playback / 4 capture |
| In-memory WAV decode (spot-checked) | Done |
| Encoder + file round trip (`ma_encoder` WAV write -> `ma_decoder_init_file`, sample-exact, temp cleanup) | Done -- 0.3.0 |
| Playback engine (`ma_engine`) | Phase 2 |
| Mixing/effects (node graph) | Phase 2 |
| Capture + ring buffer | Phase 2 |
| File decoding beyond the round trip (`ma_decoder_init_file` variants) | Phase 2 |

## Phase 2 (next touches)

1. Playback engine: `ma_engine_init` + `ma_engine_play_sound` with a
   generated in-memory sound (SKIP when no playback device); keep the
   callback-free API shape.
2. ~~Encoding~~ Done 0.3.0 (encoder + file round trip, sample-exact).
3. Capture: `ma_device` capture with a ring buffer (device-gated SKIP).
4. Node graph: `ma_node_graph`/`ma_engine` mixing with two sources.
5. File I/O beyond the round trip: `ma_decoder_init_file_w`, encoder
   to-memory callbacks, larger fixtures.
6. Consumer note: PULSE/XVECTOR do not need audio; keep the API stable for
   media consumers.

## Sector note

Audio sector, package 1 of 3 (`xiom.miniaudio` done; `xiom.portaudio` then
`xiom.phonon` next per the proposal).
