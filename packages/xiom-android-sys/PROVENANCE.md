# xiom.android-sys -- PROVENANCE

## Oracle

- NDK r27b `27.1.12297006` public headers (sysroot `usr/include`):
  `android/log.h`, `android/sync.h`, `linux/sync_file.h`.
- Link oracle: the platform stubs, `liblog.so` + `libsync.so`
  (x86_64-linux-android and aarch64-linux-android, API dirs 21..35).
  Dynsym evidence (llvm-readelf, 2026-10-15):
  - API 26 stubs: liblog 8 exports (`__android_log_write`,
    `__android_log_print`, `__android_log_vprint`,
    `__android_log_assert`, `__android_log_buf_write`,
    `__android_log_buf_print`, `__android_log_is_loggable`,
    `__android_log_is_loggable_len`); libsync 3 exports (`sync_merge`,
    `sync_file_info`, `sync_file_info_free`, versioned `@@LIBSYNC`).
  - API 35 stub: liblog 18 exports (the 8 above + the 10 API-30
    extensions); libsync unchanged (3).
  - Header annotation lag noted: `android/log.h` marks
    `is_loggable(/_len)` `__INTRODUCED_IN(30)` yet both symbols are in
    the API-26 stub; the stub evidence was taken as authoritative for
    availability, the annotations for the extension split.
  - `sync_wait` and `sync_file_info_is_signaled` are **not declared**
    anywhere in the r27b sysroot (grep) and not in either stub; they
    are libsync private surface and excluded (device presence probed
    informationally by the repro driver).
  - `sync_get_fence_info` is a header `static inline` helper (no
    export); its `sync_fence_info` field offset is pinned in the
    bridge struct mirror instead.
- Function names, struct layouts and constant values are API facts
  transcribed from the pinned headers (2026-10-15).  `SYNC_IOC_*`
  values were computed with the asm-generic `ioctl` encoding from the
  header macros and cross-checked by `_Static_assert` against the r27b
  headers in the repro driver build (compile-time proof).

## Code

- `src/android_sys_bridge.c`, `android_sys.xi`,
  `tests/test_conformance.xi`, and this package's metadata are original
  XIOM code (MIT OR Apache-2.0), written for this repository; no
  upstream implementation code is vendored.
- No NDK headers are copied into the repository; the bridge compiles
  without them (self-declared pinned ABI facts only).

## License notes

- The NDK platform headers (`android/*`, `linux/sync_file.h`) are
  distributed by Google under the Apache License 2.0 (bionic portions
  BSD-3-Clause).  This package interoperates with the public ABI;
  declarations here are facts of that interface, and the package
  itself ships no Google code.

## Touch log

- 2026-10-15: created (A12 system starter head: log + sync; per-touch
  PROVENANCE rule).  Oracle extraction + stub dynsym dump + on-device
  probe recorded (`docs/repro/android-sys-probe/`).
