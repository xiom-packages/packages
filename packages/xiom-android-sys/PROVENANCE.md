# xiom.android-sys -- PROVENANCE

## Oracle

- NDK r27b `27.1.12297006` public headers (sysroot `usr/include`):
  `android/log.h`, `android/sync.h`, `linux/sync_file.h` (0.1.0);
  `android/binder_ibinder.h`, `android/binder_status.h`,
  `android/NeuralNetworks.h`, `android/NeuralNetworksTypes.h`,
  `zlib.h`, `unicode/ustring.h`, `unicode/uchar.h`, `unicode/utypes.h`
  (0.2.0).
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
  transcribed from the pinned headers (2026-10-15 / 2026-10-16).
  `SYNC_IOC_*` values were computed with the asm-generic `ioctl`
  encoding from the header macros and cross-checked by
  `_Static_assert` against the r27b headers in the repro driver build
  (compile-time proof).  0.2.0 extends the same proof to the whole
  pinned surface: `binder_status_t` values (19), NNAPI operand/op/
  error/device codes, zlib rc family + `z_stream` LP64 layout +
  `ZLIB_VERNUM`, `UErrorCode` values (12/15/-124) + ICU major (75).
- 0.2.0 runtime evidence (2026-10-16, API-36 x86_64 emulator, on-device
  driver output in `docs/repro/android-sys-probe/`):
  - `libbinder_ndk.so`: 12/12 core + 3/3 ext exports resolved; class
    lifecycle functional (descriptor/associate/refcount/destroy/ping).
  - `libneuralnetworks.so` (APEX): 12/12 core + 7/7 ext resolved;
    offline model build + compilation finish + execution create all
    `NO_ERROR`; 4 devices (names/type/feature level recorded).  The
    canonical `ADD(x, y, activation)` form was established empirically:
    the level-8 runtime's `Broadcast.cpp` validator rejects the 2-input
    short form (`BAD_DATA`, logcat evidence), and the activation input
    is required -- recorded in SPEC.md.
  - `libz.so`: 12/12 core resolved; runtime `zlibVersion()` =
    `1.3.0.1-motley` = the header pin at target API >= 28 (the r27b
    sysroot reports historical 1.2.8/1.2.6 pins for targets < 28 --
    hence the probe target 28 with a compile-gated assert); crc32/
    adler32 known answers + compress/uncompress + deflate/inflate
    roundtrips byte-exact.
  - ICU: the C API lives in `libandroidicu.so` (NDK `-licuuc` soname);
    `libicuuc.so` was probed and resolves 0/6 (it carries the C++ API
    only).  `libandroidicu.so` (pulled dynsym, ICU 75.1, 39 exported
    `u_*` symbols) exports the subset with the `_android` rename suffix
    (`U_ICU_ENTRY_POINT_RENAME`, `U_LIB_SUFFIX_C_NAME=_android`):
    5/5 required resolved; `u_strlen_android` is NOT exported (header
    announces it API 31 -- annotation/implementation lag recorded,
    treated as optional + reported, never faked).  UTF-8 <-> UTF-16
    roundtrip (`café lab`) and code-point case mapping byte-exact.
- No upstream implementation code was consulted for behavior beyond the
  public headers and the runtime validators' error output (logcat).

## Code

- `src/android_sys_bridge.c`, `src/binder_bridge.c`,
  `src/nnapi_bridge.c`, `src/zlib_bridge.c`, `src/icu_bridge.c`,
  the five `*.xi` modules, `tests/test_conformance.xi`, the repro
  driver, and this package's metadata are original XIOM code (MIT OR
  Apache-2.0), written for this repository; no upstream implementation
  code is vendored.
- No NDK headers are copied into the repository; the bridges compile
  without them (self-declared pinned ABI facts only).  The repro driver
  includes the real headers and proves the pins with `_Static_assert`.

## License notes

- The NDK platform headers (`android/*`, `linux/sync_file.h`, `zlib.h`,
  `unicode/*`) are distributed by Google under the Apache License 2.0
  (bionic portions BSD-3-Clause; zlib under the zlib license; ICU under
  the Unicode license).  This package interoperates with the public
  ABI; declarations here are facts of that interface, and the package
  itself ships no Google/ICU code.

## Touch log

- 2026-10-15: created (A12 system starter head: log + sync; per-touch
  PROVENANCE rule).  Oracle extraction + stub dynsym dump + on-device
  probe recorded (`docs/repro/android-sys-probe/`).
- 2026-10-16: 0.2.0 (A12 remainder: binder + nnapi + zlib + icu subset;
  per-touch PROVENANCE rule).  Header oracle extended to the ten
  headers above; on-device driver extended to all five units
  (per-lib export resolution counts + functional smokes), full run
  output recorded (`docs/repro/android-sys-probe/
  result-2026-10-16-api36-x86_64.txt`).  Binding-surface correction
  recorded: ICU C API soname `libandroidicu.so` + `_android` symbol
  rename; NNAPI canonical activation input; zlib target-API version
  relationship.
