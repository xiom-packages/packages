# xiom.aaudio

Android AAudio bindings for XIOM -- the A6 AAudio head of the Android
SDK100 program (`aaudio/AAudio.h`, NDK r27b).

> **Published:** `0.1.0` in `eco-v0.1.192` (2026-10-16; sha256 `ab97fe2e...`).

- Runtime probe for `libaaudio.so` with SKIP semantics (absent runtime
  -> `AAUDIO_LOAD_ABSENT`; broken exports -> `AAUDIO_LOAD_ABI` FAIL).
- Full declared surface bound + ABI-checked: 67 `AAUDIO_API` functions;
  the constants/types clusters (`AAUDIO_DIRECTION/PERFORMANCE_MODE/
  FORMAT/SHARING_MODE/STREAM_STATE_*`, `AAUDIO_OK` + `AAUDIO_ERROR_*`,
  usage/content-type/input-preset/spatialization/capture/session,
  channel masks) transcribed from the pinned header.
- Functional builder lifecycle: `builder_create`/`builder_delete` (no
  audio device needed), the full builder setter surface, callbacks via
  top-level C stubs (direct handoff).
- Stream head: `builder_open_stream`, `stream_request_start/pause/
  stop/flush`, `stream_read`/`stream_write` (bridge-side scratch window),
  `stream_wait_for_state_change`/`stream_get_state`,
  `stream_get_xrun_count`, `stream_get_frames_per_burst`,
  `stream_get_timestamp`, `stream_close`, plus the query/getter family.
- Convert helpers: `result_to_text`, `stream_state_to_text` (the
  header's `AAudio_convertResultToText`/`convertStreamStateToText`).

```xiom
use xiom.aaudio;

let p = aaudio_probe();
if p.is_ok {
  let b = builder_create();
  if b.is_ok {
    let builder = b.value;
    builder_set_direction(&builder, AAUDIO_DIRECTION_OUTPUT);
    builder_set_format(&builder, AAUDIO_FORMAT_PCM_I16);
    let o = builder_open_stream(&builder);  // typed outcome via open_result()
    ...
  }
}
```

Run the conformance suite:

```
scripts/port.ps1 -Package xiom.aaudio
```

On-device evidence (API-36 x86_64 emulator, `-no-audio` tolerated):

```
powershell -File docs/repro/build-and-run.ps1
```

Program context: `docs/ANDROID-SDK100.md` (coverage ledger) and
`docs/prep/android-wave.md` (wave brief).
