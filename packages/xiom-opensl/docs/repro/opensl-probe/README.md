# xiom.opensl A6 bridge -- on-device probe (W2d evidence)

Runs the package bridge (`packages/xiom-opensl/src/opensl_bridge.c`)
against the real platform libraries on the API-36 x86_64 emulator:
load -> 114-symbol export-table check (3+53 OpenSL ES, 3+41 OpenMAX AL,
14 AMidi) -> slCreateEngine/Realize/GetState/Destroy lifecycle (bridge +
direct-header control) -> slQuery*EngineInterfaces -> AMidi verdict.

The driver also includes the REAL NDK r27b headers and prints a
`CONST ...` oracle dump (candidate values for cross-reading against the
transcribed constants in `packages/xiom-opensl/opensl.xi`).

## Run

```
powershell -File run-probe.ps1                 # emulator must be up
powershell -File run-probe.ps1 -Serial <serial>
```

## Evidence (2026-10-15, API-36 x86_64 emulator)

```
INFO load rc=0 error=
OK load (loaded_mask=7 sl_missing=0 xa_missing=0 amidi_missing=0)
INFO export-set resolved sl=56/56 xa=44/44 amidi=14/14
INFO sl_iid_null_values=0
INFO bridge lifecycle rc=0 state=2 error=
DIRECT create rc=0 engine=non-null
DIRECT realize rc=0
DIRECT state rc=0 state=2
DIRECT destroy ok
INFO sl engine interfaces num=6 queried_ok=6
INFO amidi getDeviceInfo_present=0 count_attempt=-1 (AMidi_getDeviceInfo absent: r27b oracle declares 14 core fns; device objects arrive only via AMidiDevice_fromJava (JNI))
CONST sl-result 0 1 2 10 12 16
CONST sl-bool-state 0 1 2 3
CONST sl-play-time 1 3 16 4294967295
CONST sl-device-format 4294967294 7 2 2
CONST sl-pcm 44100000 48000000 16 -32768 1
CONST sl-android-loc 4 2147485628 2147485629 2147485630 1
CONST sl-android-cfg 3 1 5 4
CONST xa-result 0 16 2 9
CONST xa-misc 4294967291 3 5 2
CONST amidi 1 3 17 -1 0 -10004
RESULT: PASS
```

- `sl_missing=0` / `xa_missing=0` / `amidi_missing=0`: the whole
  114-symbol export table resolves on-device, including all 53
  `SL_IID_*` and 41 `XA_IID_*` runtime-GUID globals
  (`sl_iid_null_values=0` = every GUID slot is live).
- `state=2` = `SL_OBJECT_STATE_REALIZED`: `slCreateEngine` -> non-null
  engine -> `Realize(SL_BOOLEAN_FALSE)` -> `GetState` -> `Destroy` all
  clean, in the bridge AND in the direct-header control block.
- `num=6 queried_ok=6`: `slQueryNumSupportedEngineInterfaces` = 6 and
  every `slQuerySupportedEngineInterfaces(index)` returned a non-null
  `SLInterfaceID`.
- `count_attempt=-1`: `AMidi_getDeviceInfo` is absent (r27b oracle and
  the API-36 device `libamidi.so` both export exactly the 14 core
  functions) -- the recorded outcome; 0 devices would be the fine
  result if the API existed.
- `CONST ...`: values printed from the REAL r27b headers; each matches
  the transcribed constants in `packages/xiom-opensl/opensl.xi`
  (e.g. `sl-android-loc 2147485628 2147485629 2147485630` =
  `0x800007BC`/`BD`/`BE`; `amidi ... -10004` = `AMEDIA_ERROR_INVALID_PARAMETER`).
- On Windows the same bridge classifies ABSENT -> the package suite
  SKIPs green.

## Files

- `driver.c` -- bridge driver + header-oracle dump (x86_64-linux-android26, PIE)
- `run-probe.ps1` -- build + push + run via adb
