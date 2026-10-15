# xiom.android-sys

Android system-starter bindings for XIOM -- the A12 (system / log+sync)
head of the Android SDK100 program.

- Runtime probe for `liblog.so` + `libsync.so` with SKIP semantics
  (absent runtime -> `ANDROID_SYS_LOAD_ABSENT`; broken core exports ->
  `ANDROID_SYS_LOAD_ABI` FAIL).
- 11-symbol core export set (API 26) ABI-gated; 10 API-30 liblog
  extensions resolved and reported (never a false FAIL on android26).
- Functional `liblog` head: `log_write` / `log_print` /
  `log_buf_write` (rc 1 = written), `log_is_loggable(/_len)` verdicts,
  `log_minimum_priority`; log priorities + log ids transcribed.
- Functional `libsync` typed error path: `sync_file_info` /
  `sync_merge` return `Result[.., AndroidSysError]` with captured
  `errno` (`SYS_EBADF` / `SYS_EINVAL`); info struct accessors
  (`status`, `num_fences`, `name`) read fields in the bridge; no
  pointer ever crosses the boundary.
- `SYNC_IOC_*` values + struct sizes pinned from the headers
  (build-time `_Static_assert` cross-check in the repro driver).

```xiom
use xiom.android_sys;

let p = android_sys_probe();
if p.is_ok {
  let w = log_write(ANDROID_LOG_INFO, "my-app", "hello from XIOM");
  let e = sync_file_info(-1);   // Err(CALL, errno=EBADF) -- typed
  ...
}
```

Run the conformance suite:

```
scripts/port.ps1 -Package xiom.android-sys
```

Program context: `docs/ANDROID-SDK100.md` (coverage ledger) and
`docs/prep/android-wave.md` (wave brief).  On-device evidence:
`docs/repro/android-sys-probe/` (this package).
