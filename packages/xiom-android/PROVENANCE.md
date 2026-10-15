# xiom.android -- PROVENANCE

## Oracle

- NDK r27b `27.1.12297006` public headers (sysroot `usr/include`):
  `android/native_window.h`, `android/native_window_jni.h`,
  `android/hardware_buffer.h`, `android/hardware_buffer_jni.h`,
  `android/rect.h`.
- Link oracle: API-35 platform stubs, `libandroid.so` +
  `libnativewindow.so` (both architectures present in the sysroot).
- Function names, struct layouts and constant values are API facts
  transcribed from the headers; every constant in `android.xi` was
  extracted from the pinned header set on 2026-10-15.

## Code

- `src/android_bridge.c`, `android.xi`, `tests/test_conformance.xi`,
  and this package's metadata are original XIOM code (MIT OR
  Apache-2.0), written for this repository; no upstream implementation
  code is vendored.
- No NDK headers are copied into the repository; the bridge compiles
  without them (self-declared pinned ABI facts only).

## License notes

- The NDK platform headers (`android/*`) are distributed by Google
  under the Apache License 2.0 (bionic portions BSD-3-Clause).  This
  package interoperates with the public ABI; declarations here are
  facts of that interface, and the package itself ships no Google
  code.

## Touch log

- 2026-10-15: created (W2a head; per-touch PROVENANCE rule).
- 2026-10-15: W2b A5 head -- asset_manager.h (17) / storage_manager.h
  (6) / sharedmem.h (3) added to the oracle + export set (53 symbols);
  sharedmem exercised functionally (suite + on-device probe).
