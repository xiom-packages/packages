# xiom.android-sys -- SPEC

Android system-starter bindings for XIOM.  A12 system head of the Android
SDK100 program (`docs/ANDROID-SDK100.md`); this 0.1.0 covers the **log +
sync** starter pair.

## Scope (NDK r27b `27.1.12297006` oracle)

Header oracle (sysroot `usr/include`):
`android/log.h`, `android/sync.h`, `linux/sync_file.h`.

**Core export set (API 26, ABI-gated, 11 symbols)** -- every symbol also
exported by the API-26 link stubs (verified via `llvm-readelf
--dyn-syms`):

- `__android_log_write`, `__android_log_print`, `__android_log_vprint`,
  `__android_log_assert` (liblog).
- `__android_log_buf_write`, `__android_log_buf_print` (liblog).
- `__android_log_is_loggable`, `__android_log_is_loggable_len` (liblog).
- `sync_merge`, `sync_file_info`, `sync_file_info_free` (libsync;
  `sync_get_fence_info` is a header `static inline` helper, not an
  export).

**API-30 extension set (resolved + reported, not gated, 10 symbols)** --
declared `__INTRODUCED_IN(30)` in the header and present in the API-35
stub but absent from the API-26 stub, so they are not required on
android26 devices:

`__android_log_write_log_message`, `__android_log_set_logger`,
`__android_log_logd_logger`, `__android_log_stderr_logger`,
`__android_log_set_aborter`, `__android_log_call_aborter`,
`__android_log_default_aborter`, `__android_log_set_minimum_priority`,
`__android_log_get_minimum_priority`, `__android_log_set_default_tag`.

Constants transcribed: `android_LogPriority` (0..8), `log_id` (0..7 +
`LOG_ID_MAX` + `LOG_ID_DEFAULT = 0x7FFFFFFF`), `SYNC_IOC_*` (computed
from the header macros with the asm-generic `ioctl` encoding;
cross-checked against the headers by the repro driver via
`_Static_assert`), pinned struct sizes (`sync_merge_data` 48,
`sync_file_info` 56, `sync_fence_info` 80, `sync_set_deadline` 16), and
the `EBADF`/`EINVAL` errno family.

## Design

- `src/android_sys_bridge.c` is a self-contained runtime loader (no
  link-time dependency, no NDK headers needed to compile): `dlopen` on
  Android/Linux, `LoadLibraryA` on Windows (where the probe classifies
  ABSENT -> SKIP).  Missing core names are reported
  (`xs_abi_missing`); a broken partial install maps to
  `ANDROID_SYS_LOAD_ABI` = FAIL, never a silent SKIP.  Missing extension
  names are reported separately (`xs_ext_missing`) without gating.
- Functional liblog head: `log_write` (`__android_log_write`, rc 1 =
  written), `log_print` (`__android_log_print` through a fixed `"%s"`
  format -- the message is never a format string), `log_buf_write`,
  `log_is_loggable(/_len)` verdicts, `log_minimum_priority` (API-30,
  -1 when the symbol is absent).
- Functional libsync head, typed error path: `sync_file_info(fd)`
  returns `Result[SyncFileInfo, AndroidSysError]`; failures carry the
  captured errno (`SYS_EBADF` for fd -1, `SYS_EINVAL` when the fd is not
  a sync file).  `sync_merge` maps its result the same way.  The info
  struct is an opaque `Int` handle; accessors (`..._status`,
  `..._num_fences`, `..._name`) read fields in the bridge, and
  `sync_file_info_release` frees it.  Pointers never cross the boundary
  (B-25 discipline).
- This wave does not synthesize fences (fence creation needs a device
  driver producer); the export set + typed error path are the functional
  proof.

## Classification

| Probe outcome | Marker | Suite result |
|---|---|---|
| libs absent (Windows, bogus pair) | `ANDROID_SYS_LOAD_ABSENT` | SKIP (green) |
| core exports missing / broken install | `ANDROID_SYS_LOAD_ABI` | FAIL |
| full core set + working log/sync | Ok | live checks |
| live call failure with errno | `ANDROID_SYS_CALL` | reported Err (caught by the caller) |

## Documented exclusions (evidence in PROVENANCE.md)

- `sync_wait` / `sync_file_info_is_signaled`: **not declared by the NDK
  r27b headers** (grep of the whole sysroot finds no declaration; absent
  from the API-26/35 stub dynsym) -- libsync private surface, excluded.
  The repro driver probes their device presence informationally.
- `__android_log_print`/`_vprint`/`_assert`: bound + ABI-checked;
  varargs call paths are not crossed from XIOM (the fixed-format
  `log_print` wrapper covers the format path; assert is noreturn).
- `sync_set_deadline` (ioctl only; no libsync wrapper function in the
  headers).
- JNI surfaces (`__android_log_*` are the whole log header surface; no
  JNI in this head).

## Build

`scripts/port.ps1 -Package xiom.android-sys` (compiles
`src/android_sys_bridge.c` via `port.args.json`; suite SKIPs on Windows,
runs live on Android).
