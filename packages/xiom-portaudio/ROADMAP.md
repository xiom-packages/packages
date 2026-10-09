# xiom.portaudio -- Roadmap

**Version**: v0.2.0 | **Compiler**: xiom v0.64.1 | **Last updated**: 2026-10-09

## Current state

| Criterion | Status |
|-----------|--------|
| Dynamic loader (no link dependency) | Done -- `portaudio_x64.dll` at runtime |
| G2 pin (soname + entry points + struct prefix) | Done -- `SPEC.md` §2 |
| Version probe (int + text) | Done -- V19.7.0 (int 1246976) |
| Device enumeration + default names | Done -- 52 devices, Realtek/Razer defaults |
| SKIP/FAIL classification | Done |
| Streams (`Pa_OpenStream`/`Pa_StartStream`) | Phase 2 |
| Callbacks + buffering | Phase 2 |
| Host-API info (`Pa_GetHostApiInfo`) | Phase 2 |
| MSYS2/POSIX sonames | Phase 2 |

## Phase 2 (next touches)

1. Streams: `pa_open_stream`/`pa_start`/`pa_stop`/`pa_close_stream` with
   `PaStreamParameters` built in a byte layout (device/channels/format/
   latency); a short playback or loopback smoke, device-gated SKIP.
2. Host-API layer: `Pa_GetHostApiCount`/`Pa_GetHostApiInfo`/
   `Pa_HostApiDeviceIndexToDeviceIndex` for WASAPI/WDMKS/MME/ASIO visibility.
3. Callback API: function-pointer callback support (unsafe, confined to the
   module) with an XIOM-side ring buffer.
4. Device info surface: full `PaDeviceInfo` fields (channels, latencies,
   default sample rate) via offset reads with a documented struct pin.
5. SONAME variants: `libportaudio-2.dll` (MSYS2) and POSIX `libportaudio.so`.

## Sector note

Audio sector, package 2 of 3 (`xiom.miniaudio` done, `xiom.portaudio` this
package; `xiom.phonon` next).
