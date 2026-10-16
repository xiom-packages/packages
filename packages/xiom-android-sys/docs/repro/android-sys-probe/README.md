# xiom.android-sys -- on-device probe (A12 system surface, 0.2.0)

Evidence for `xiom.android-sys` 0.2.0.  The driver links the five
shipped bridges (the five bridge C units in
`packages/xiom-android-sys/src`), builds for `x86_64-linux-android28`
with the NDK r27b clang, and runs on the API-36 x86_64 emulator.  It
cross-checks the transcription against the real headers at build time
(`_Static_assert` on log priorities/ids, `SYNC_IOC_*`, struct
sizes/offsets, `binder_status_t`, NNAPI operand/op/error/device codes,
zlib rc + `z_stream` layout, `UErrorCode` + ICU 75), scans the device
libraries independently (`dlopen`/`dlsym`), then exercises all five
bridge heads.  `run-probe.ps1` also clears logcat, runs the probe, and
dumps logcat for the tag as the logd round-trip proof.

## How to reproduce

```
powershell -File run-probe.ps1                 # emulator-5554 running
# or: powershell -File run-probe.ps1 -Serial <serial>
```

Emulator (headless): `C:\Android\sdk\emulator\emulator.exe -avd
Medium_Phone_API_36.0 -no-window -no-audio -no-boot-anim -no-snapshot
-gpu swiftshader_indirect`.

Full recorded output: `result-2026-10-16-api36-x86_64.txt`.

## Result (2026-10-16, API-36 x86_64 emulator, serial emulator-5554)

```
=== xiom.android-sys on-device driver (A12 system surface 0.2.0, NDK r27b oracle) ===
INFO header cross-check: log/sync + binder_status + NNAPI codes + zlib + UErrorCode _Static_assert PASS
--- log + sync (liblog.so + libsync.so) ---
INFO core (API 26) exports resolved: 11/11
INFO ext (API 30) exports resolved: 10/10
INFO bridge core export set resolved (missing=0); ext 10/10
INFO log: __android_log_write/print/buf_write rc=1; is_loggable(INFO)=1; len=16 ->1
INFO sync: sync_file_info(-1) errno=9 (EBADF); sync_merge rc=-1 errno=9 (EBADF)
--- binder (libbinder_ndk.so) ---
INFO binder core (API 29) exports resolved: 12/12
INFO binder ext (API 31/33) exports resolved: 3/3
OK binder core export set resolved (missing=0)
INFO binder: descriptor="xiom.a12.probe"; associateClass=1; getClass=same
INFO binder: isAlive=1 isRemote=0; ping=0 (OK)
INFO binder: refcount 1 -> inc -> 2 -> dec -> 1; onDestroy count 0 -> 1
--- nnapi (libneuralnetworks.so) ---
INFO nnapi core (API 27) exports resolved: 12/12
INFO nnapi ext (API 29) exports resolved: 7/7
OK nnapi core export set resolved (missing=0)
INFO nnapi: device count=4 (nnapi-sample_all/quant/sl_shim + nnapi-reference; feature 1000008)
INFO nnapi: addOperand rc=0/0/0/0; setOperandValue(act=FUSED_NONE) rc=0
INFO nnapi: addOperation ADD (x,y,act)->out rc=0 (NO_ERROR)
INFO nnapi: identifyInputsAndOutputs rc=0; model finish rc=0 (offline build)
INFO nnapi: compilation create handle=...; compilation finish rc=0 (device stage OK)
INFO nnapi: execution create handle=...
--- zlib (libz.so) ---
INFO zlib core exports resolved: 12/12
OK zlib core export set resolved (missing=0)
INFO zlib: version="1.3.0.1-motley" (header pin matches)
INFO zlib: crc32("123456789")=0xCBF43926; adler32("123456789")=0x091E01DE
INFO zlib: compress 4096 -> 119 bytes; uncompress -> 4096 bytes; roundtrip exact
INFO zlib: deflate stream -> 119 bytes (Z_STREAM_END); inflate -> 4096 bytes; roundtrip exact
--- icu (libandroidicu.so; declared subset) ---
INFO icu required subset exports resolved: 5/5
INFO icu optional subset (reported): u_strlen_android missing
INFO icu: errorName(U_ZERO_ERROR)="U_ZERO_ERROR"
INFO icu: utf8_to_utf16 -> 16 bytes; utf16_to_utf8 -> "café lab"; roundtrip exact
INFO icu: case a->0x41 e9->0xC9 Z->0x7A C9->0xE9 (expect 41/C9/7A/E9)
RESULT: PASS
--- logcat proof (tag xiom-android-sys) ---
I/xiom-android-sys: xiom.android-sys probe: __android_log_write ok
I/xiom-android-sys: xiom.android-sys probe: __android_log_print ok
I/xiom-android-sys: xiom.android-sys probe: __android_log_buf_write ok
```

## Notes (honest record)

- **Per-lib export resolution**: 0 missing of every REQUIRED declared
  set (log+sync 11 + 10 ext; binder 12 + 3 ext; nnapi 12 + 7 ext;
  zlib 12; icu required 5).  The one reported gap is optional:
  `u_strlen_android`.
- **ICU soname**: the C API is `libandroidicu.so` (NDK `-licuuc`
  soname; symbols `u_*_android` via the NDK rename macro).
  `libicuuc.so` exists on the device but resolves 0/6 of the subset
  (C++ ICU API only) -- probed and recorded, not used.
- **`u_strlen` gap**: the NDK header announces `u_strlen`
  `__INTRODUCED_IN(31)`, but the API-36 shim (ICU 75.1; 39 exported
  `u_*` symbols, pulled dynsym) does not export it.  The module
  classifies it optional and reports it; the length verdict is gated,
  never faked.
- **NNAPI canonical form**: the level-8 validator requires
  `ADD(x, y, activation)` where the activation is an INT32 scalar
  constant (`FUSED_NONE`); the 2-input form is rejected with
  `BAD_DATA` (`Broadcast.cpp` logcat evidence).  The driver + suite
  build the canonical form; compilation finish reached the device
  stage (rc=0) and execution creation succeeded.
- **zlib version**: `1.3.0.1-motley` on the device equals the header
  pin **for target API >= 28**; the r27b sysroot reports the historical
  1.2.8/1.2.6 pins for lower targets, so the probe targets
  `x86_64-linux-android28` (compile-gated).
- **binder**: `ping` returns the raw `binder_status_t` (0 = `STATUS_OK`
  on a live local binder); the descriptor is read through the class
  (`AIBinder_Class_getDescriptor`, API-31 ext symbol present on this
  device); the transact/parcel surface stays a documented delta
  (callbacks-observed counter = 0).
- **log+sync** (0.1.0 head) remains green unmodified; `sync_wait` is
  present on the device but is private (NDK-undeclared) surface and
  stays excluded.
