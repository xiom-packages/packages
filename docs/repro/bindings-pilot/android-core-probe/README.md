# xiom.android A1 bridge -- on-device probe (W2a evidence)

Runs the package bridge (`packages/xiom-android/src/android_bridge.c`)
against the real platform libraries on the API-36 x86_64 emulator:
load -> declared export-set check -> functional AHardwareBuffer
roundtrip.  Complements the package suite (which SKIPs on Windows).

## Run

```
powershell -File run-probe.ps1                 # emulator must be up
powershell -File run-probe.ps1 -Serial <serial>
```

## Evidence (2026-10-15, API-36 x86_64 emulator)

```
INFO load rc=0 error=
OK load (missing_exports=0)
INFO is_supported=1
OK alloc
INFO w=64 h=64 fmt=1 stride=64 layers=1
INFO read=287454020
RESULT: PASS
```

- `missing_exports=0`: all 27 declared exports (15 `ANativeWindow_*` +
  12 `AHardwareBuffer_*`) resolved from `libandroid.so` /
  `libnativewindow.so`.
- `read=287454020` = `0x11223344`: exact pixel roundtrip through
  lock/write/unlock/lock/read/unlock (pointers stay C-side).
- On Windows the same bridge classifies ABSENT -> the package suite
  SKIPs green (4/4 on v0.64.4).

## Files

- `driver.c` -- bridge driver (x86_64-linux-android26, PIE)
- `run-probe.ps1` -- build + push + run via adb
