# xiom.miniaudio -- Roadmap

**Version**: v0.5.0 | **Compiler**: xiom v0.64.5 (suite re-verified on v0.64.6) | **Last updated**: 2026-10-17

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
| **Long-lived device handles (open once -> render callbacks / streams over time -> close once, typed errors)** | **Done -- 0.5.0 (null battery + live auto/WASAPI open legs; 44/44 x2 on the pin, x2 on v0.64.6)** |
| Opus/Ogg custom decoder backends (over live xiom.opus/xiom.ogg) | Staged (see below) |
| Effect nodes / spatialization / full resource-manager surface | Future |

## 0.5.0 (engine ask -- this touch)

Per the engine audio ask `REL-20261016-2139-packages-2` (miniaudio
long-lived handle surface): `ma_device_handle_open` /
`ma_device_handle_open_backend` (open once; 4-slot registry, monotonic ids,
`MA_HANDLE_BACKEND_AUTO/WASAPI/NULL`), render callback registration
(`set_render` / `clear_render`, replaceable while running; env-free
top-level `fn(*UInt8, Int32) -> Unit` invoked on the device thread),
stream start/stop cycles (`start`/`stop`), a bounded `wait`, an `info`
snapshot (negotiated shape + `callbacks`/`frames`/`marked`/`starts`/`stops`
counters) and `close` (running streams stop first; stale ops are typed
`BAD_HANDLE`). Typed `MaHandleError { kind, rc, message }` throughout
(`NO_CONTEXT`/`NO_DEVICE`/`BAD_HANDLE`/`EXHAUSTED`/`STATE`/`STEP`). The
deterministic battery runs on the null backend (always openable, real-time
paced, audio-service free); the live legs (auto/WASAPI open+info+close)
degrade to typed SKIP. The 0.4.0 lifecycle bridge is unchanged alongside.

## Phase 3 (next touches)

1. **Opus/Ogg custom backend (staged)**: `ma_decoder_init` with a custom
   `ma_decoder_config` backend (`onRead`/`onSeek` over the live `xiom.opus`/
   `xiom.ogg` packages). The seam exists in the pinned header, but the
   bridge currently passes plain memory/file sources; wiring a custom
   backend requires a C read/seek trampoline held in the compile unit plus
   the XIOM-side codec handles -- deferred to keep this touch's scope on the
   asked surface. Revisit with the audio codec classes as the durable route.
2. Handle-surface growth (engine follow-ups): per-handle configurable client
   shapes (rate/channels/format/period), capture handles, and
   frame-accurate render-start alignment if the engine leg needs them.
3. Effect nodes and spatialization: `ma_engine` effect nodes (reverb/
   delay/filters), listener/positional API.
4. Resource-manager surface: `ma_resource_manager` (async loads, VFS,
   decoded banks) beyond `ma_engine_play_sound`.
5. File I/O beyond the round trip: `ma_decoder_init_file_w`, encoder
   to-memory callbacks, larger fixtures.
6. Consumer note: PULSE/XVECTOR do not need audio; keep the API stable for
   media consumers (engine audio tiers A1-A5 consume the 0.4.0 surface; the
   engine handle leg consumes the 0.5.0 surface).

## Sector note

Audio sector, package 1 of 3 (`xiom.miniaudio` done; `xiom.portaudio` then
`xiom.phonon` next per the proposal).
