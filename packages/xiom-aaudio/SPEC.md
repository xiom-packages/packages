# xiom.aaudio -- SPEC

Android AAudio bindings for XIOM.  A6 audio head of the Android SDK100
program (`docs/ANDROID-SDK100.md`); this 0.1.0 is the **AAudio head**
(AMidi + OpenSL ES follow as W2d tails).

## Scope (NDK r27b oracle)

- `aaudio/AAudio.h` -- the full declared surface: **67 `AAUDIO_API`
  functions** (measured in the pinned header; the wave brief's "72" was
  an estimate):
  - audio system (3): `AAudio_convertResultToText`,
    `AAudio_convertStreamStateToText`, `AAudio_createStreamBuilder`
  - StreamBuilder (25): the 21 `set*` setters + `openStream` + `delete`
    + the deprecated `setSamplesPerFrame` + `setChannelMask`
  - Stream (39): control (`release`, `close`, `requestStart/Pause/Flush/
    Stop`, `getState`, `waitForStateChange`), I/O (`read`, `write`,
    `setBufferSizeInFrames`) and the query/getter family
    (`getBufferSizeInFrames`, `getFramesPerBurst`,
    `getBufferCapacityInFrames`, `getFramesPerDataCallback`,
    `getXRunCount`, `getSampleRate`, `getHardwareSampleRate`,
    `getChannelCount`, `getHardwareChannelCount`, `getSamplesPerFrame`,
    `getDeviceId`, `getFormat`, `getHardwareFormat`, `getSharingMode`,
    `getPerformanceMode`, `getDirection`, `getFramesWritten`,
    `getFramesRead`, `getSessionId`, `getTimestamp`, `getUsage`,
    `getContentType`, `getSpatializationBehavior`,
    `isContentSpatialized`, `getInputPreset`,
    `getAllowedCapturePolicy`, `isPrivacySensitive`, `getChannelMask`).
- Constant/type clusters transcribed with values: `aaudio_direction_t`,
  `aaudio_format_t`, `aaudio_result_t` (`AAUDIO_OK` +
  `AAUDIO_ERROR_*` computed off `AAUDIO_ERROR_BASE = -900`),
  `aaudio_stream_state_t`, `aaudio_sharing_mode_t`,
  `aaudio_performance_mode_t`, `aaudio_usage_t` (incl.
  `AAUDIO_SYSTEM_USAGE_OFFSET = 1000`), `aaudio_content_type_t`,
  `aaudio_spatialization_behavior_t`, `aaudio_input_preset_t`,
  `aaudio_allowed_capture_policy_t`, `aaudio_session_id_t`,
  `aaudio_data_callback_result_t`, `aaudio_channel_mask_t` (26 bits +
  27 named combinations), `AAUDIO_UNSPECIFIED`.
- Callback ABI pinned from the header typedefs:
  `AAudioStream_dataCallback(stream, userData, audioData, numFrames)`,
  `AAudioStream_errorCallback(stream, userData, error)`.

## Design

- `src/aaudio_bridge.c` is a self-contained runtime loader (no
  link-time dependency, no NDK headers needed to compile): `dlopen` on
  Android/Linux, `LoadLibraryA` on Windows (where the probe classifies
  ABSENT -> SKIP).  Every declared export is resolved and missing names
  are reported (`xaa_abi_missing`); a broken partial install maps to
  `AAUDIO_LOAD_ABI` = FAIL, never a silent SKIP.  A compile-time guard
  enforces the 67-entry export set.
- Functional head: builder lifecycle (create/delete works without any
  audio device), the full builder setter surface, the stream control/IO/
  query surface, and the convert helpers run through typed function
  pointers resolved at load.
- Pointers never cross the boundary (B-25 discipline): builder/stream
  handles cross as `Int`; the read/write data window, the
  `waitForStateChange` next-state slot and the `getTimestamp`
  out-params live entirely inside the bridge and are read back through
  scalar accessors (`stream_wait_state`, `stream_timestamp_frames/nanos`).
- Callbacks are top-level C stubs (`xaa_data_callback_stub` /
  `xaa_error_callback_stub`) handed directly to AAudio (direct handoff;
  no env, no registry).  The data stub zero-fills silence at the
  configured PCM_I16 stereo stride and counts invocations
  (`data_callback_count`); the suite does not require it to fire
  headless.
- Open-attempt policy (honest, best-effort): OUTPUT +
  PERFORMANCE_MODE_NONE + PCM_I16 + 2 ch + 48000 Hz + SHARED.  A typed
  `AAUDIO_ERROR_*` is a recorded outcome (`open_result`, non-fatal);
  a successful open requests start and closes cleanly.

## Classification

| Probe outcome | Marker | Suite result |
|---|---|---|
| lib absent (Windows, bogus soname) | `AAUDIO_LOAD_ABSENT` | SKIP (green) |
| exports missing / broken install | `AAUDIO_LOAD_ABI` | FAIL |
| full export set | Ok | live checks (builder lifecycle; open attempt recorded) |

## Documented exclusions (for this head)

- `AAudioStream_isMMapUsed`, `AAudio_getMMapPolicy`, `AAudio_setMMapPolicy`:
  runtime-only testing exports of AOSP `AAudioTesting.h`, which is NOT
  shipped in the r27b NDK -- outside the header oracle (present in the
  device `libaaudio.so`; intentionally not bound).
- AMidi (`amidi/AMidi.h`, libamidi) and OpenSL ES (`SLES/*`,
  libOpenSLES) -- the remaining A6 tails (W2d follow-ons).
- `CLOCK_MONOTONIC` / `CLOCK_BOOTTIME` are exposed as
  `AAUDIO_CLOCK_*` convenience constants (bionic `time.h` values, not
  AAudio defines) for `stream_get_timestamp`.

## Build

`scripts/port.ps1 -Package xiom.aaudio` (compiles
`src/aaudio_bridge.c` via `port.args.json`; suite SKIPs on Windows, runs
live on Android).  On-device evidence driver:
`docs/repro/` (NDK cross-build for `x86_64-linux-android26`, pushed to
the API-36 emulator).
