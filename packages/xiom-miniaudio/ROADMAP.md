# xiom.miniaudio -- Roadmap

**Version**: v0.4.0 | **Compiler**: xiom v0.64.5 | **Last updated**: 2026-10-16

## Current state

| Criterion | Status |
|-----------|--------|
| Vendored single header (G2 pinned) | Done -- 0.11.25 |
| FFI core + probe bridge (single confined module) | Done |
| Version + context/device enumeration | Done -- 9 playback / 4 capture |
| In-memory WAV decode (spot-checked) | Done |
| Encoder + file round trip (`ma_encoder` WAV write -> `ma_decoder_init_file`, sample-exact, temp cleanup) | Done -- 0.3.0 |
| Device lifecycle (open/start/mix-pull/stop/close) + driver negotiation + loss hooks | Done -- 0.4.0 (WASAPI explicit) |
| Playback engine (`ma_engine`, memory + file sounds) | Done -- 0.4.0 |
| Mixing/node graph (attach/detach, sound group, volume/pitch) | Done -- 0.4.0 |
| Capture enumerate + open attempt | Done -- 0.4.0 (typed non-fatal outcomes) |
| Streamed decode through the data-source pull path (built-in WAV/FLAC/MP3) | Done -- 0.4.0 |
| Opus/Ogg custom decoder backends (over live xiom.opus/xiom.ogg) | Staged (see below) |
| Effect nodes / spatialization / full resource-manager surface | Future |

## 0.4.0 (A04 growth -- this touch)

Per the packages ask `REL-20261015-1904-packages-2` (engine audio A04):
device lifecycle with driver negotiation and device-loss handling, playback
engine, mixing/node graph basics, capture open attempt, and streamed decode
of miniaudio's built-in decoders. Live device legs are silent by
construction and degrade to typed SKIP-style checks when the environment
blocks audio; the device-free legs (graph/mix math, decode) are
deterministic. Device-loss boundary: `started`/`stopped` notifications are
proven live; `rerouted`/interruption/unlock are wired but need a real
default-device change to fire (cannot be forced in-process) -- see
`SPEC.md` section 3 and `PROVENANCE.md` section 4.

## Phase 3 (next touches)

1. **Opus/Ogg custom backend (staged)**: `ma_decoder_init` with a custom
   `ma_decoder_config` backend (`onRead`/`onSeek` over the live `xiom.opus`/
   `xiom.ogg` packages). The seam exists in the pinned header, but the
   bridge currently passes plain memory/file sources; wiring a custom
   backend requires a C read/seek trampoline held in the compile unit plus
   the XIOM-side codec handles -- deferred to keep this touch's scope on the
   asked surface. Revisit with the audio codec classes as the durable route.
2. Effect nodes and spatialization: `ma_engine` effect nodes (reverb/
   delay/filters), listener/positional API.
3. Resource-manager surface: `ma_resource_manager` (async loads, VFS,
   decoded banks) beyond `ma_engine_play_sound`.
4. File I/O beyond the round trip: `ma_decoder_init_file_w`, encoder
   to-memory callbacks, larger fixtures.
5. Consumer note: PULSE/XVECTOR do not need audio; keep the API stable for
   media consumers (engine audio tiers A1-A5 consume the 0.4.0 surface).

## Sector note

Audio sector, package 1 of 3 (`xiom.miniaudio` done; `xiom.portaudio` then
`xiom.phonon` next per the proposal).
