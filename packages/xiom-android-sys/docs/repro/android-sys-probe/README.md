# xiom.android-sys -- on-device probe (A12 log+sync head)

Evidence for `xiom.android-sys` 0.1.0.  The driver links the shipped
bridge (`packages/xiom-android-sys/src/android_sys_bridge.c`), builds for
`x86_64-linux-android26` with the NDK r27b clang, and runs on the API-36
x86_64 emulator.  It cross-checks the transcription against the real
headers at build time (`_Static_assert` on priorities/ids, `SYNC_IOC_*`,
struct sizes/offsets), scans the device libraries independently
(`dlopen`/`dlsym`), then exercises the bridge heads (log write/print/
buf_write, is_loggable verdicts, sync errno capture).  `run-probe.ps1`
also clears logcat, runs the probe, and dumps logcat for the tag as the
logd round-trip proof.

## How to reproduce

```
powershell -File run-probe.ps1                 # emulator-5554 running
# or: powershell -File run-probe.ps1 -Serial <serial>
```

Emulator (headless): `C:\Android\sdk\emulator\emulator.exe -avd
Medium_Phone_API_36.0 -no-window -no-audio -no-boot-anim -no-snapshot
-gpu swiftshader_indirect`.

## Result (2026-10-15, API-36 x86_64 emulator, serial emulator-5554)

```
=== xiom.android-sys on-device driver (A12 log+sync head, NDK r27b oracle) ===
INFO header cross-check: priorities/ids + SYNC_IOC_* + struct sizes _Static_assert PASS
INFO ioctl: merge=0xC0303E03 file_info=0xC0383E04 set_deadline=0x40103E05 magic=0x3E
INFO dlopen: liblog.so=ok libsync.so=ok
INFO core (API 26) exports resolved: 11/11
INFO ext (API 30) exports resolved: 10/10
INFO private (NDK-undeclared) sync_wait: present
INFO private (NDK-undeclared) sync_file_info_is_signaled: absent
INFO private (NDK-undeclared) sync_get_fence_info: absent
INFO private (NDK-undeclared) sync_set_deadline: absent
INFO bridge load rc=0 error=
OK bridge core export set resolved (missing=0)
INFO bridge ext (API 30+): 10/10 present
INFO log: __android_log_write rc=1 (1=written)
INFO log: __android_log_print rc=1
INFO log: is_loggable(INFO, default INFO)=1 (expect 1)
INFO log: is_loggable(VERBOSE, default INFO)=0 (expect 0 off-list; informational)
INFO log: is_loggable_len(INFO, len=16, default INFO)=1 (expect 1)
INFO log: __android_log_buf_write rc=1
INFO log: minimum_priority=1 (-1 = API-30 ext absent)
INFO sync: sync_file_info(-1) handle=0 errno=9 (EBADF)
INFO sync: sync_merge(name,-1,-1) rc=-1 errno=9 (EBADF)
INFO bridge unloaded
RESULT: PASS
--- logcat proof (tag xiom-android-sys) ---
--------- beginning of main
I/xiom-android-sys(11892): xiom.android-sys probe: __android_log_write ok
I/xiom-android-sys(11892): xiom.android-sys probe: __android_log_print ok
I/xiom-android-sys(11892): xiom.android-sys probe: __android_log_buf_write ok
```

## Notes

- The VERBOSE-is-loggable verdict is recorded, not gated: a
  `log.tag.xiom-android-sys` property or process minimum may flip it
  (environment).  On this emulator it is 0 as the default-INFO rule
  predicts.
- `sync_wait` is present on the device libsync but is **not declared by
  the NDK headers** (private surface) -> excluded from the package with
  evidence (SPEC/PROVENANCE); `sync_file_info_is_signaled` is absent even
  from this device libsync, corroborating the exclusion.
- No fences are synthesized this wave (fence creation needs a device
  driver producer); the export set + typed errno error path are the
  functional proof for libsync.
