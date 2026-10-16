# xiom.android-sys -- SPEC

Android system bindings for XIOM.  A12 system head of the Android SDK100
program (`docs/ANDROID-SDK100.md`).  0.2.0 grows the 0.1.0 log + sync
starter into the A12 remainder: **binder, NNAPI, zlib and an ICU subset**
-- each library a separate runtime-load unit with its own SKIP
classification.

## Oracle (NDK r27b `27.1.12297006` sysroot)

| Unit | Header oracle | Runtime library (soname) |
|---|---|---|
| log+sync | `android/log.h`, `android/sync.h`, `linux/sync_file.h` | `liblog.so` + `libsync.so` |
| binder | `android/binder_ibinder.h`, `android/binder_status.h` | `libbinder_ndk.so` |
| nnapi | `android/NeuralNetworks.h`, `android/NeuralNetworksTypes.h` | `libneuralnetworks.so` (APEX-provided on API 31+) |
| zlib | `zlib.h` (ZLIB_VERSION `1.3.0.1-motley`) | `libz.so` |
| icu | `unicode/ustring.h`, `unicode/uchar.h`, `unicode/utypes.h` (ICU 75.1) | `libandroidicu.so` |

Link oracle: the platform stubs (same lib names).  Three on-device
dynsym scans drive the declarations (records in
`docs/repro/android-sys-probe/` and PROVENANCE.md): the log/sync stubs
(API 26/35), the binder/NNAPI/zlib surfaces, and the pulled
`libandroidicu.so` export list.

## Declared clusters (100% declared == 100% implemented == 100% proven)

### log + sync (unchanged from 0.1.0; 11 core + 10 ext reported)

Core export set (API 26, ABI-gated): `__android_log_write/print/vprint/
assert/buf_write/buf_print/is_loggable/is_loggable_len` (8) + `sync_merge/
sync_file_info/sync_file_info_free` (3).  API-30 liblog extension set
(10, resolved + reported, not gated).  Functional head + typed error
path as documented in 0.1.0 (`android_sys.xi`).

### binder -- `libbinder_ndk.so`

Declared core set (API 29, ABI-gated, 12 symbols):

`AIBinder_Class_define`, `AIBinder_new`, `AIBinder_incStrong`,
`AIBinder_decStrong`, `AIBinder_associateClass`, `AIBinder_isAlive`,
`AIBinder_isRemote`, `AIBinder_ping`, `AIBinder_getClass`,
`AIBinder_debugGetRefCount`, `AIBinder_getCallingUid`,
`AIBinder_getCallingPid`.

Declared extension set (resolved + reported, not gated, 3 symbols):
`AIBinder_Class_getDescriptor` (API 31), `AIBinder_Class_setOnDump`
(API 31), `AIBinder_Class_disableInterfaceTokenHeader` (API 33).

- **Interface descriptor**: the NDK has no
  `AIBinder_getInterfaceDescriptor`; the descriptor is read through the
  class (`AIBinder_Class_getDescriptor`).  The module exposes
  `binder_class_descriptor(handle)`; when the API-31 extension symbol is
  absent the bridge falls back to the cached definition descriptor and
  the ext gap is reported (never a guess).
- **Create/destroy smoke** (on-device green): define class
  `"xiom.a12.probe"` -> `AIBinder_new` -> `associateClass` (true,
  class identity) -> `getClass` (same handle) -> `isAlive` (1) /
  `isRemote` (0) -> `ping` = `STATUS_OK` -> ref-count 1 -> inc -> 2 ->
  dec -> 1 -> dec -> 0 with the onDestroy callback observed
  (`binder_destroy_count`).  `AIBinder_getCallingUid/Pid` are recorded
  (own identity outside a transaction).
- **Class lifetime**: `AIBinder_Class` objects have no public delete in
  the NDK; the bridge caches the defined class for the process lifetime
  (the documented usage pattern).
- **binder_status_t**: the full r27b enum is transcribed (19 constants)
  plus `binder_status_name`.  `ping` returns the raw status; its
  "unresolved" sentinel is -1024 because -2 is a real status
  (`STATUS_NAME_NOT_FOUND`).

Delta (documented exclusions): the parcel surface
(`AIBinder_prepareTransaction/transact/getExtension/setExtension` --
needs `android/binder_parcel.h`), death recipients, weak binders,
`AIBinder_dump`, `AIBinder_lt`, `AIBinder_isHandlingTransaction`,
`AIBinder_getUserData`, `AIBinder_Class_setOnDump` (reported only), and
the JNI bridges (`binder_ibinder_jni.h` / `binder_parcel_jni.h`) -- the
onTransact callback replies `STATUS_UNKNOWN_TRANSACTION` and the
transact callbacks-observed counter is 0 by design this wave.

### nnapi -- `libneuralnetworks.so`

Declared core set (API 27, ABI-gated, 12 symbols):

`ANeuralNetworksModel_create`, `_addOperand`, `_addOperation`,
`_identifyInputsAndOutputs`, `_setOperandValue`, `_finish`, `_free`
(7), `ANeuralNetworksCompilation_create`, `_finish`, `_free` (3),
`ANeuralNetworksExecution_create`, `_free` (2).

Declared extension set (API 29, resolved + reported, not gated, 7
symbols): `ANeuralNetworks_getDeviceCount`, `_getDevice`,
`ANeuralNetworksDevice_getName`, `_getType`, `_getVersion`,
`_getFeatureLevel`, `ANeuralNetworks_getRuntimeFeatureLevel`.

- **Canonical op form finding (API-36 level-8 validator)**: the runtime
  rejects `ADD(x, y) -> out` with `BAD_DATA`; the canonical signature
  (`packages/modules/NeuralNetworks/common/types/operations/src/
  Broadcast.cpp`) requires the post-inputs **activation input**:
  `ADD(x, y, activation)` where the activation is an INT32 scalar
  constant (`FUSED_NONE`/`RELU`/`RELU1`/`RELU6`).  The offline smoke
  builds exactly that form (recorded in the repro driver + suite);
  `FUSED_*` constants are transcribed.
- **Offline smoke** (on-device green, no device execution): model
  create -> 2x `TENSOR_FLOAT32 {2}` input operands + INT32 scalar
  activation + `TENSOR_FLOAT32 {2}` output -> `setOperandValue`
  (FUSED_NONE) -> `ADD (x,y,act) -> out` -> `identifyInputsAndOutputs`
  ({0,1},{3}) -> `finish` = `NO_ERROR` -> compilation create ->
  **compilation finish = NO_ERROR (device stage)** -> execution create
  -> frees.  Device query recorded: 4 devices on the API-36 emulator
  (`nnapi-sample_all`, `nnapi-sample_quant`, `nnapi_sample_sl_shim`,
  `nnapi-reference`; type CPU; feature level 1000008).
- The device-absent path is documented and non-gating: if
  `compilation_finish` fails (no usable driver), the suite records the
  upstream code via `Err(NNAPI_CALL, code)` + `nn_error_name` and keeps
  the offline cluster as the gated proof.
- Inputs/outputs cross as opaque `Int` handles; operand-id arrays and
  dimensions cross as caller-owned **u32 little-endian byte slots**
  (`nn_ids1/2/3`, `nn_dims1/2`); float scale crosses as its binary32
  bit pattern (B-12-safe).

Delta (documented exclusions): execution I/O
(`Execution_setInput/setOutput/startCompute`, memory objects
`Memory_createFromFd/AHardwareBuffer/Desc`, bursts, events, timing,
`Compilation_createForDevices`/`setPreference`/`setCaching`,
`Model_getSupportedOperationsForDevices`, quantized symmetric
per-channel params) -- the declared cluster is the offline-declarable
model/compilation/execution lifecycle + device query.

### zlib -- `libz.so`

Declared core set (ABI-gated, 12 symbols): `zlibVersion`, `compress`,
`uncompress`, `compressBound`, `crc32`, `adler32`, `deflateInit_`,
`deflate`, `deflateEnd`, `inflateInit_`, `inflate`, `inflateEnd`.

- `z_stream` management is entirely C-side behind opaque `Int` handles
  (`deflate_begin`/`input`/`step`/`end`, `inflate_*`); the LP64 layout
  (112 bytes) is pinned and cross-checked at build time in the repro
  driver (`sizeof(z_stream)` compile assertion against the r27b header).
- The version string passed to `deflateInit_`/`inflateInit_` is the
  **runtime** `zlibVersion()` (never a compile-time guess).
- **Roundtrip fixture** (required, on-device exact): 4096-byte text
  `compress` -> `uncompress` byte-exact; streaming
  `deflate` -> `inflate` roundtrip byte-exact; known answers
  `crc32("123456789") = 0xCBF43926`, `adler32("123456789") =
  0x091E01DE`; `compressBound` sanity.
- The repr driver also proves the device version string
  (`1.3.0.1-motley`) equals the header pin at target API >= 28 (the
  r27b sysroot reports the historical 1.2.8/1.2.6 pins for targets
  < 28; the probe therefore builds for android28 and asserts the
  target-API precondition).

Delta (documented exclusions): the raw streaming surface beyond
init/step/end basics (per-call flush modes beyond `Z_FINISH` in the
module API, `deflateSetDictionary`/`inflateSetDictionary`,
gzip-file helpers `gzopen`/`gzread`, `deflateBound`, `compress2`,
`uncompress2`, `crc32_z`/`adler32_z`) -- the declared cluster is the
core compression/checksum surface.

### icu -- `libandroidicu.so` (DECLARED SUBSET BY DESIGN)

Declared subset (6 symbols; the loader resolves the `_android`-suffixed
exports that the NDK headers macro-map via `U_ICU_ENTRY_POINT_RENAME`
with `U_LIB_SUFFIX_C_NAME=_android`):

- required (gated on the live path, 5): `u_errorName_android`,
  `u_strToUTF8_android`, `u_strFromUTF8_android`, `u_toupper_android`,
  `u_tolower_android` -- all `__INTRODUCED_IN(31)` in the NDK.
- optional (resolved + reported, 1): `u_strlen_android` -- the NDK
  header announces `u_strlen` `__INTRODUCED_IN(31)`, but the API-36
  platform shim (`libandroidicu.so`, ICU 75.1, 39 exported `u_*`
  symbols) does **not** export it.  The module reports the gap and
  `icu_utf16_length` returns `Err(ICU_GATED, reason)` -- never a faked
  count.

**Subset policy (owner/engine-facing claim, kept honest)**: this module
proves the platform text plumbing -- error naming, UTF-8/UTF-16
decode+encode, encoding length, and simple case mapping of code points.
It is explicitly NOT a collation (`ucol`), break-iteration (`ubrk`),
formatting (`udat`/`unum`), normalization (`unorm2`), or
regex (`uregex`) binding; those remain a documented delta for a future
ICU wave.  Engines that need more than text plumbing must not assume it
from this module.

**Soname note**: Android ships the ICU **C API** as `libandroidicu.so`
(the soname the NDK `-licuuc` alias resolves to).  `libicuuc.so` exists
on-device but carries the C++ ICU API; the probe records the difference
(dynsym: `libicuuc.so` resolves 0/6 of the subset, `libandroidicu.so`
resolves 5/5 required + 0/1 optional).

- **UTF roundtrip fixture** (on-device exact): `"café lab"` (UTF-8 with
  `U+00E9` as `0xC3 0xA9`) -> UTF-16 (16 bytes / 8 units) -> UTF-8
  byte-exact; `u_errorName(U_ZERO_ERROR)` = `"U_ZERO_ERROR"`; case
  mapping `a->A`, `é(U+00E9)->É(U+00C9)`, `Z->z`, `É->é`.
- UTF-16 crosses as caller-owned little-endian u16 byte slots;
  `UErrorCode` is returned as the `AndroidSysError.errno_code` with
  `icu_error_name` for naming.

Delta (documented exclusions): everything outside the subset, incl.
`u_strToLower`/`u_strToUpper` (present on-device, string-level case
conversion -- superseded in the subset by u_toupper/u_tolower code
point mapping), `u_strFromUTF8WithSub`, character-property functions
(`u_charType`, `u_isalpha`, ...; 30+ exported by the shim but outside
the text-plumbing claim), collation/iteration/formatting families.

## Classification

| Unit | libs absent | broken core exports | version-gated subset | live call failure |
|---|---|---|---|---|
| log+sync | `ANDROID_SYS_LOAD_ABSENT` = SKIP | `ANDROID_SYS_LOAD_ABI` = FAIL | n/a (ext reported) | `ANDROID_SYS_CALL` |
| binder | `BINDER_LOAD_ABSENT` = SKIP | `BINDER_LOAD_ABI` = FAIL | n/a (ext reported) | `BINDER_CALL` |
| nnapi | `NNAPI_LOAD_ABSENT` = SKIP | `NNAPI_LOAD_ABI` = FAIL | n/a (device stage recorded) | `NNAPI_CALL` |
| zlib | `ZLIB_LOAD_ABSENT` = SKIP | `ZLIB_LOAD_ABI` = FAIL | n/a | `ZLIB_CALL` |
| icu | `ICU_LOAD_ABSENT` = SKIP | n/a (subset) | `ICU_GATED` = explicit SKIP + names | `ICU_CALL` |

Every unit is independent: a missing library SKIPs its own checks and
never affects the others; a present library with a broken required
export set FAILs (never a silent SKIP).

## Design

- Five self-contained bridge C units (no link-time dependency, no NDK
  headers needed to compile): `dlopen` on Android/Linux,
  `LoadLibraryA` on Windows (everything classifies ABSENT on the dev
  box).  Compiled via `port.args.json` `--c-source` entries.
- Pointers never cross the boundary (B-25/B-series discipline): handles
  are `Int`, strings are `Str` copies, byte buffers are caller-owned
  `Vec[UInt8]` slots read/written byte-indexed; out-params are u64/u32
  LE byte slots.
- The repro driver cross-checks every pinned constant family against
  the real r27b headers at build time (`_Static_assert`:
  priorities/ids, `SYNC_IOC_*`, struct sizes/offsets,
  `binder_status_t`, NNAPI operand/op/error/device codes, zlib rc +
  `z_stream` layout + target-API zlib version, `UErrorCode` values +
  ICU 75 major).

## Build / run

```
scripts/port.ps1 -Package xiom.android-sys            # suite (SKIP on Windows)
scripts/port.ps1 -Package xiom-android-sys -NoRun     # type-check every module
powershell -File packages/xiom-android-sys/docs/repro/android-sys-probe/run-probe.ps1
```

On-device evidence: `docs/repro/android-sys-probe/` (driver output,
`result-2026-10-16-api36-x86_64.txt`, logcat proof).
