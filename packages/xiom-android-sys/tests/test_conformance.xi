// xiom.android-sys conformance suite -- system-starter head (liblog.so +
// libsync.so) loader/probe for the A12 slice (android/log.h +
// android/sync.h).
//
// The probe never FAILs on a missing runtime:
//   present runtime -> core export-set ABI check (11 symbols) +
//                      functional liblog head (write/print/is_loggable
//                      verdicts) + functional libsync typed error path
//                      (errno capture on fd -1)
//   missing libs    -> ANDROID_SYS_LOAD_ABSENT (SKIP; exercised
//                      deterministically below with bogus sonames)
//   broken install  -> ANDROID_SYS_LOAD_ABI (FAIL -- never a silent SKIP)
//
// On Windows the runtime is absent by design -> SKIP (CI stays green).
// On an Android device/emulator the same suite runs the live path.
//
// Build+run through the runner (compiles src/android_sys_bridge.c via
// port.args.json):
//   scripts/port.ps1 -Package xiom.android-sys

module android_sys_conformance

use xiom.io;
use xiom.android_sys;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn t_constants() -> Bool {
  var ok = true;
  if ANDROID_SYS_LOAD_ABSENT != 0 || ANDROID_SYS_LOAD_ABI != 1 || ANDROID_SYS_CALL != 2 { ok = false; }
  if ANDROID_LOG_UNKNOWN != 0 || ANDROID_LOG_DEFAULT != 1 || ANDROID_LOG_VERBOSE != 2 { ok = false; }
  if ANDROID_LOG_DEBUG != 3 || ANDROID_LOG_INFO != 4 || ANDROID_LOG_WARN != 5 { ok = false; }
  if ANDROID_LOG_ERROR != 6 || ANDROID_LOG_FATAL != 7 || ANDROID_LOG_SILENT != 8 { ok = false; }
  if LOG_ID_MIN != 0 || LOG_ID_MAIN != 0 || LOG_ID_RADIO != 1 || LOG_ID_EVENTS != 2 { ok = false; }
  if LOG_ID_SYSTEM != 3 || LOG_ID_CRASH != 4 || LOG_ID_STATS != 5 || LOG_ID_SECURITY != 6 { ok = false; }
  if LOG_ID_KERNEL != 7 || LOG_ID_MAX != 8 || LOG_ID_DEFAULT != 0x7FFFFFFF { ok = false; }
  if SYNC_IOC_MAGIC != 0x3E { ok = false; }
  if SYNC_IOC_MERGE != 0xC0303E03 || SYNC_IOC_FILE_INFO != 0xC0383E04 { ok = false; }
  if SYNC_IOC_SET_DEADLINE != 0x40103E05 { ok = false; }
  if SYNC_MERGE_DATA_SIZE != 48 || SYNC_FILE_INFO_SIZE != 56 { ok = false; }
  if SYNC_FENCE_INFO_SIZE != 80 || SYNC_SET_DEADLINE_SIZE != 16 { ok = false; }
  if SYS_EBADF != 9 || SYS_EINVAL != 22 { ok = false; }
  return ok;
}

fn t_log_functional() -> Int {
  var failed: Int = 0;
  // The exact probe line the wave requires: INFO=4, tag "xiom-android-sys".
  let w = log_write(ANDROID_LOG_INFO, "xiom-android-sys", "xiom.android-sys probe: __android_log_write ok");
  if w.is_ok {
    failed = failed + report(w.value == 1, "log: __android_log_write rc=" + to_string(w.value) + " (1 = written)");
  } else {
    failed = failed + report(false, "log: __android_log_write failed -- " + w.error.message);
  }
  let p = log_print(ANDROID_LOG_INFO, "xiom-android-sys", "xiom.android-sys probe: __android_log_print ok");
  if p.is_ok {
    failed = failed + report(p.value == 1, "log: __android_log_print rc=" + to_string(p.value) + " (1 = written)");
  } else {
    failed = failed + report(false, "log: __android_log_print failed -- " + p.error.message);
  }

  // is_loggable: INFO is loggable under the default_prio rule.
  failed = failed + report(
    log_is_loggable(ANDROID_LOG_INFO, "xiom-android-sys", ANDROID_LOG_INFO),
    "log: is_loggable(INFO, default INFO) = true");
  // VERBOSE off-list is expected NOT loggable under default INFO; the
  // verdict is recorded either way (a log.tag property / process minimum
  // can legitimately flip it -- environment, not a bridge fault).
  let verbose_ok = log_is_loggable(ANDROID_LOG_VERBOSE, "xiom-android-sys", ANDROID_LOG_INFO);
  var verbose_text: Str = "false";
  if verbose_ok { verbose_text = "true"; }
  io.println("  [INFO] log: is_loggable(VERBOSE, default INFO) = " + verbose_text
    + " (expected false when no log.tag override)");
  io.flush_stdout();
  let len_ok = log_is_loggable_len(ANDROID_LOG_INFO, "xiom-android-sys", 16, ANDROID_LOG_INFO);
  failed = failed + report(len_ok, "log: is_loggable_len(INFO, len=16, default INFO) = true");

  let b = log_buf_write(LOG_ID_MAIN, ANDROID_LOG_INFO, "xiom-android-sys", "xiom.android-sys probe: __android_log_buf_write ok");
  if b.is_ok {
    failed = failed + report(b.value == 1, "log: __android_log_buf_write rc=" + to_string(b.value) + " (1 = written)");
  } else {
    failed = failed + report(false, "log: __android_log_buf_write failed -- " + b.error.message);
  }

  let mp = log_minimum_priority();
  io.println("  [INFO] log: minimum_priority = " + to_string(mp)
    + " (-1 = API-30 ext symbol absent on this device)");
  io.flush_stdout();
  return failed;
}

fn t_sync_error_path() -> Int {
  var failed: Int = 0;
  // Typed error path: fd -1 is not a sync file -> Err with the captured
  // errno (EBADF expected; EINVAL family accepted).
  let r = sync_file_info(-1);
  if r.is_err {
    let e = r.error;
    let family = e.kind == ANDROID_SYS_CALL && (e.errno_code == SYS_EBADF || e.errno_code == SYS_EINVAL);
    failed = failed + report(family,
      "sync: sync_file_info(-1) -> Err(CALL, errno=" + to_string(e.errno_code) + " " + e.message + ")");
  } else {
    failed = failed + report(false, "sync: sync_file_info(-1) unexpectedly succeeded");
    sync_file_info_release(r.value);
  }
  let m = sync_merge("xiom-sys-probe", -1, -1);
  if m.is_err {
    let e2 = m.error;
    let family2 = e2.kind == ANDROID_SYS_CALL && (e2.errno_code == SYS_EBADF || e2.errno_code == SYS_EINVAL);
    failed = failed + report(family2,
      "sync: sync_merge(name, -1, -1) -> Err(CALL, errno=" + to_string(e2.errno_code) + " " + e2.message + ")");
  } else {
    failed = failed + report(false, "sync: sync_merge(name, -1, -1) unexpectedly succeeded");
  }
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.android-sys conformance tests (system-starter loader/probe) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: kinds + log priorities/ids + sync ioctls/struct sizes + errno family");

  // SKIP-path classification, deterministic on every host (bogus pair).
  let missing = android_sys_probe_named("xiom-absent-liblog-xyz.so", "xiom-absent-libsync-xyz.so");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus pair unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == ANDROID_SYS_LOAD_ABSENT,
      "skip-path: absent pair classified as ANDROID_SYS_LOAD_ABSENT (SKIP)");
  }

  // Default runtime probe.
  let p = android_sys_probe();
  if p.is_ok {
    let rt: AndroidSysRuntime = p.value;
    failed = failed + report(rt.missing_exports == 0,
      "abi: core export set fully resolved (" + to_string(rt.missing_exports) + " missing)");
    io.println("  [INFO] abi: API-30 liblog extensions " + to_string(rt.ext_total - rt.ext_missing)
      + "/" + to_string(rt.ext_total) + " present (informational; older devices may miss them)");
    io.flush_stdout();
    failed = failed + t_log_functional();
    failed = failed + t_sync_error_path();
  } else {
    if p.error.kind == ANDROID_SYS_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- android sys runtime not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  // Unload must be safe even after a failed probe.
  android_sys_unload();
  failed = failed + report(true, "loader: unload path exercised");

  if failed == 0 {
    io.println("xiom.android-sys: all tests passed");
  } else {
    io.println("xiom.android-sys: tests failed");
  }
  return failed;
}
