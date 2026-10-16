# xiom.android-sys

Android system bindings for XIOM -- the A12 (system) head of the Android
SDK100 program: per-lib runtime-load units with independent SKIP
classification over the NDK r27b oracle.

## 0.2.0 -- A12 remainder surface (5 runtime-load units)

| Unit | Module | Library | Declared set | Classification |
|---|---|---|---|---|
| log+sync | `xiom.android_sys` | `liblog.so` + `libsync.so` | 11 core (API 26) + 10 ext reported | `ANDROID_SYS_LOAD_ABSENT/ABI`, `ANDROID_SYS_CALL` |
| binder | `xiom.android_sys.binder` | `libbinder_ndk.so` | 12 core (API 29) + 3 ext reported | `BINDER_LOAD_ABSENT/ABI`, `BINDER_CALL` |
| nnapi | `xiom.android_sys.nnapi` | `libneuralnetworks.so` | 12 core (API 27) + 7 device-query ext reported | `NNAPI_LOAD_ABSENT/ABI`, `NNAPI_CALL` |
| zlib | `xiom.android_sys.zlib` | `libz.so` | 12 core | `ZLIB_LOAD_ABSENT/ABI`, `ZLIB_CALL` |
| icu | `xiom.android_sys.icu` | `libandroidicu.so` | 5 required + 1 optional (declared subset) | `ICU_LOAD_ABSENT`, `ICU_GATED`, `ICU_CALL` |

- Runtime probes for each library with SKIP semantics (absent runtime ->
  `*_LOAD_ABSENT`; broken core exports -> `*_LOAD_ABI` FAIL; never a
  silent SKIP).  Every unit loads independently: one absent library does
  not affect the others.
- Functional heads:
  - `liblog`: `log_write` / `log_print` / `log_buf_write` (rc 1 =
    written), `log_is_loggable(/_len)` verdicts,
    `log_minimum_priority` (API-30 ext).
  - `libsync`: `sync_file_info` / `sync_merge` returning
    `Result[.., AndroidSysError]` with captured errno
    (`SYS_EBADF` / `SYS_EINVAL`); opaque `Int` info handle + accessors.
  - `libbinder_ndk`: class define (cached, process lifetime), create,
    `incStrong`/`decStrong` (destroy proof via onDestroy count),
    `associateClass`, `isAlive`, `isRemote`, `ping` (binder_status_t),
    `getClass` identity, interface descriptor (API-31 class surface),
    ref-count debug reads; full `binder_status_t` constant family
    transcribed + `binder_status_name`.
  - `libneuralnetworks`: offline model build (`Model_create` /
    `addOperand` / `addOperation` / `setOperandValue` /
    `identifyInputsAndOutputs` / `finish` / `free`), compilation
    (`create` / `finish` / `free`), execution (`create` / `free`),
    device query (`getDeviceCount` / `getDevice` / name/type/version/
    feature level + runtime feature level).  Canonical op form:
    `ADD(x, y, activation)` with the INT32 `FUSED_NONE` constant (the
    feature-level-8 validator requires the activation input).
  - `libz`: `zlibVersion`, one-shot `compress` -> `uncompress`
    roundtrip, `compressBound`, `crc32`/`adler32` (known-answer tested),
    streaming `deflateInit_`/`deflate`/`deflateEnd` +
    `inflateInit_`/`inflate`/`inflateEnd` through opaque handles (the
    one-shot and streaming roundtrips are exact on-device).
  - `libandroidicu` (DECLARED SUBSET by design): `u_errorName`,
    `u_strToUTF8`/`u_strFromUTF8` (UTF-8 <-> UTF-16 roundtrip),
    `u_toupper`/`u_tolower` (simple case mapping); `u_strlen` is an
    optional subset symbol (header-announced API 31, not exported by
    the platform shim -- reported, never faked).  Subset policy in
    `SPEC.md`.
- No pointer ever crosses the boundary: handles are `Int` values, byte
  buffers are caller-owned slots with byte-indexed access (B-series
  discipline).

```xiom
use xiom.android_sys.binder;
use xiom.android_sys.zlib;

let p = zlib_probe();
if p.is_ok {
  var src = /* owned Vec[UInt8] fixture */;
  let cz = zlib_compress(&mut src);
  // ...
}

let b = binder_probe();
if b.is_ok {
  let c = binder_class_define("my.app.Service");
  // ...
}
```

Run the conformance suite (SKIPs cleanly on Windows):

```
scripts/port.ps1 -Package xiom.android-sys
```

Program context: `docs/ANDROID-SDK100.md` (coverage ledger) and
`docs/prep/android-wave.md` (wave brief).  On-device evidence:
`docs/repro/android-sys-probe/` (driver output + logcat proof, recorded
2026-10-16 on the API-36 x86_64 emulator).
