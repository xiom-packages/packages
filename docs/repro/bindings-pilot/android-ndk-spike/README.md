# Android NDK spike -- xiom.opus cross-build + on-device roundtrip

W1 of the Android prep wave (`docs/ANDROID-SDK100.md`).  Proves the
vendored-C half of the Android path WITHOUT the compiler target: the
same unity-build units the Windows port compiles produce a working
Android `.so`, and the `xo_*` bridge ABI works under the load semantics
our runtime uses (dlopen by path, mirroring `xiom.ffi.dl`).

## Toolchain

- NDK r27b `27.1.12297006`, clang 18.0.2 (Android r522817b)
- targets: `x86_64-linux-android26` (run) + `aarch64-linux-android26`
  (build; on-device arm64 run waits on a device)
- emulator: API-36 x86_64, AVD `Medium_Phone_API_36.0`, adb

## Build (reproduce with `build-spike.ps1`)

Five units: `src/opus_bridge.c` + `opus_vendor_{celt,silk,silk_float,src}.c`.

Three flags matter (found during the spike):

1. The flat vendor tree needs its subdir include paths:
   `-I vendor/opus -I vendor/opus/float -I vendor/opus/fixed`
   (e.g. `float/structs_FLP.h` includes `typedef.h` from the root).
2. The float build must LINK `-lm` (`DT_NEEDED libm.so`) or the
   on-device `dlopen` fails with
   `cannot locate symbol "exp" referenced by libopus.so`.
3. Pin `-Wl,-soname,libopus.so` for the runtime-load model.

## Evidence (2026-10-15, this box)

`llvm-readelf -h`: `libopus-aarch64.so` = ELF64 / AArch64 / DYN;
`libopus-x86_64.so` = ELF64 / x86-64 / DYN.  `-d` on x86_64:
`NEEDED libm.so / libdl.so / libc.so`; `SONAME libopus.so`.

On the API-36 x86_64 emulator (`adb push` -> `/data/local/tmp/xiom-spike/`):

```
OK dlopen /data/local/tmp/xiom-spike/libopus.so
INFO encoder_size=31668
OK encoder_create
OK decoder_create
OK encode bytes=127
OK decode samples=960 first=0
SPIKE RESULT: PASS
```

(`first=0` is codec lookahead on the first sample -- not a failure.)

## Scope

- **Proves**: vendor-C compile + load + bridge ABI on Android; the
  packaging half of every A-slice; the on-device harness/runner path.
- **Not covered here**: XIOM-emitted code on Android (gate G1, the
  compiler target); arm64 on-device run (build-level only).

## Files

- `opus_harness.c` -- dlopen + `xo_*` encode/decode roundtrip (x86_64 PIE)
- `build-spike.ps1` -- reproduces all three artifacts
