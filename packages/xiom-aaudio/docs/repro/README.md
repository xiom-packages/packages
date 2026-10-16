# xiom.aaudio -- on-device evidence (A6 head)

Proves the A6 AAudio head on the API-36 x86_64 emulator:

| Evidence | How |
|---|---|
| constant transcription | 139 transcribed literals compared AT BUILD TIME against the pinned header `aaudio/AAudio.h` (NDK r27b) |
| runtime bridge | `src/aaudio_bridge.c` (the shipped bridge) dlopens `libaaudio.so` and resolves the 67-symbol export set |
| builder lifecycle | `create -> configure -> delete` with no audio device involvement |
| open attempt | OUTPUT / PERFORMANCE_MODE_NONE / PCM_I16 / 2 ch / 48000 Hz / SHARED, with direct-handoff data + error callbacks; typed verdict recorded |

## Run

```
powershell -File build-and-run.ps1
```

Builds `aaudio_head_probe.c` + the package bridge with the NDK clang for
`x86_64-linux-android26` (`-fPIE -pie -ldl`), pushes to
`/data/local/tmp/xiom-spike/`, runs it.  Emulator context: AVD
`Medium_Phone_API_36.0`, `emulator-5554`.

The constants check is the oracle gate: the literals embedded in the
driver are the exact values transcribed into `aaudio.xi`; the operands
come from the real NDK header at compile time.  (This gate already
caught one real transcription bug during authoring: `AAUDIO_CHANNEL_TRI_BACK`
is `FRONT_LEFT|FRONT_RIGHT|BACK_CENTER` = 259, not 19.)

## Recorded run (2026-10-16)

See `recorded-output.txt`.  Summary: constants 139/139; export set
67/67; builder lifecycle PASS; the stream OPENED (rc=0) and reached
STARTED; the top-level data callback fired (silence fill);
`write()` correctly returned `AAUDIO_ERROR_INVALID_STATE` (the header
forbids writes with an active data callback); `close` + `delete` clean.
A typed open failure would have been an equally valid non-fatal outcome
(emulators often run `-no-audio`); this run had a working audio path.

Handle addresses vary per run (ASLR), so `recorded-output.txt` shows one
representative run.
