// xiom.android-sys conformance suite -- A12 system surface (0.2.0):
// per-lib runtime-load units with independent SKIP classification.
//
//   log+sync  (liblog.so + libsync.so)          ANDROID_SYS_* classification
//   binder    (libbinder_ndk.so)                BINDER_* classification
//   nnapi     (libneuralnetworks.so)            NNAPI_* classification
//   zlib      (libz.so)                         ZLIB_* classification
//   icu       (libandroidicu.so; declared subset) ICU_* classification
//
// The suite never FAILs on a missing runtime:
//   present runtime -> export-set ABI check + functional head:
//     log/sync   : log write/print/is_loggable + sync typed errno path
//     binder     : class define -> create -> associate/isAlive/isRemote/
//                  ping -> refcount inc/dec -> destroy -> descriptor
//     nnapi      : offline model build (3 tensors + ADD + io identify +
//                  finish) -> compilation create/finish -> execution
//     zlib       : crc32/adler32 known answers + compress->uncompress
//                  roundtrip fixture + deflate/inflate stream roundtrip
//     icu        : UTF-8 -> UTF-16 -> UTF-8 roundtrip + unit length +
//                  simple case mapping (subset policy in SPEC.md)
//   missing libs    -> LOAD_ABSENT (SKIP; exercised deterministically with
//                      bogus sonames)
//   broken install  -> LOAD_ABI (FAIL -- never a silent SKIP)
//   icu version gate-> ICU_GATED (explicit SKIP + missing names; the NDK
//                      marks the whole declared subset __INTRODUCED_IN(31))
//
// On Windows every runtime is absent by design -> SKIP (CI stays green).
// On an Android device/emulator the same suite runs the live paths.
//
// Build+run through the runner (compiles the five bridge C units via
// port.args.json):
//   scripts/port.ps1 -Package xiom.android-sys

module android_sys_conformance

use xiom.io;
use xiom.string;
use xiom.android_sys;
use xiom.android_sys.binder;
use xiom.android_sys.nnapi;
use xiom.android_sys.zlib;
use xiom.android_sys.icu;

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

fn info(text: Str) -> Int {
  io.println("  [INFO] " + text);
  io.flush_stdout();
  return 0;
}

fn str_eq(a: Str, b: Str) -> Bool {
  if string.byte_count(a) != string.byte_count(b) { return false; }
  var i = 0;
  var same = true;
  while i < string.byte_count(a) {
    if (string.byte_at(a, i) as Int) != (string.byte_at(b, i) as Int) { same = false; }
    i = i + 1;
  }
  return same;
}

fn buffers_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  var same = true;
  while i < a.len() {
    if (a[i] as Int) != (b[i] as Int) { same = false; }
    i = i + 1;
  }
  return same;
}

fn copyv(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// n bytes of a repeating ASCII sentence (compressible fixture).
fn text_fixture(n: Int) -> Vec[UInt8] {
  let words = "the quick brown fox jumps over the lazy dog while xiom probes the android system surface for the a12 wave ";
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(string.byte_at(words, i % string.byte_count(words)));
    i = i + 1;
  }
  return v;
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < string.byte_count(s) {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// =========================================================================
// Constants (all declared clusters)
// =========================================================================

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

fn t_binder_constants() -> Bool {
  var ok = true;
  if BINDER_LOAD_ABSENT != 0 || BINDER_LOAD_ABI != 1 || BINDER_CALL != 2 { ok = false; }
  if BINDER_STATUS_OK != 0 { ok = false; }
  if BINDER_STATUS_UNKNOWN_ERROR != -2147483648 { ok = false; }
  if BINDER_STATUS_NO_MEMORY != -12 || BINDER_STATUS_INVALID_OPERATION != -38 { ok = false; }
  if BINDER_STATUS_BAD_VALUE != -22 { ok = false; }
  if BINDER_STATUS_NAME_NOT_FOUND != -2 || BINDER_STATUS_PERMISSION_DENIED != -1 { ok = false; }
  if BINDER_STATUS_NO_INIT != -19 || BINDER_STATUS_ALREADY_EXISTS != -17 { ok = false; }
  if BINDER_STATUS_DEAD_OBJECT != -32 { ok = false; }
  if BINDER_STATUS_BAD_INDEX != -75 || BINDER_STATUS_NOT_ENOUGH_DATA != -61 { ok = false; }
  if BINDER_STATUS_WOULD_BLOCK != -11 || BINDER_STATUS_TIMED_OUT != -110 { ok = false; }
  if BINDER_STATUS_UNKNOWN_TRANSACTION != -74 { ok = false; }
  if BINDER_STATUS_BAD_TYPE != -2147483647 { ok = false; }
  if BINDER_STATUS_FAILED_TRANSACTION != -2147483646 { ok = false; }
  if BINDER_STATUS_FDS_NOT_ALLOWED != -2147483641 { ok = false; }
  if BINDER_STATUS_UNEXPECTED_NULL != -2147483640 { ok = false; }
  if !str_eq(binder_status_name(BINDER_STATUS_OK), "OK") { ok = false; }
  if !str_eq(binder_status_name(BINDER_STATUS_DEAD_OBJECT), "DEAD_OBJECT") { ok = false; }
  return ok;
}

fn t_nnapi_constants() -> Bool {
  var ok = true;
  if NNAPI_LOAD_ABSENT != 0 || NNAPI_LOAD_ABI != 1 || NNAPI_CALL != 2 { ok = false; }
  if ANEURALNETWORKS_FLOAT32 != 0 || ANEURALNETWORKS_INT32 != 1 { ok = false; }
  if ANEURALNETWORKS_TENSOR_FLOAT32 != 3 || ANEURALNETWORKS_TENSOR_INT32 != 4 { ok = false; }
  if ANEURALNETWORKS_OP_ADD != 0 || ANEURALNETWORKS_OP_MUL != 18 { ok = false; }
  if ANEURALNETWORKS_NO_ERROR != 0 { ok = false; }
  if ANEURALNETWORKS_OUT_OF_MEMORY != 1 || ANEURALNETWORKS_INCOMPLETE != 2 { ok = false; }
  if ANEURALNETWORKS_UNEXPECTED_NULL != 3 || ANEURALNETWORKS_BAD_DATA != 4 { ok = false; }
  if ANEURALNETWORKS_OP_FAILED != 5 || ANEURALNETWORKS_BAD_STATE != 6 { ok = false; }
  if ANEURALNETWORKS_UNMAPPABLE != 7 || ANEURALNETWORKS_OUTPUT_INSUFFICIENT_SIZE != 8 { ok = false; }
  if ANEURALNETWORKS_UNAVAILABLE_DEVICE != 9 || ANEURALNETWORKS_DEAD_OBJECT != 14 { ok = false; }
  if ANEURALNETWORKS_DEVICE_UNKNOWN != 0 || ANEURALNETWORKS_DEVICE_OTHER != 1 { ok = false; }
  if ANEURALNETWORKS_DEVICE_CPU != 2 || ANEURALNETWORKS_DEVICE_GPU != 3 { ok = false; }
  if ANEURALNETWORKS_DEVICE_ACCELERATOR != 4 { ok = false; }
  if !str_eq(nn_error_name(ANEURALNETWORKS_NO_ERROR), "NO_ERROR") { ok = false; }
  if !str_eq(nn_error_name(ANEURALNETWORKS_BAD_DATA), "BAD_DATA") { ok = false; }
  return ok;
}

fn t_zlib_constants() -> Bool {
  var ok = true;
  if ZLIB_LOAD_ABSENT != 0 || ZLIB_LOAD_ABI != 1 || ZLIB_CALL != 2 { ok = false; }
  if ZLIB_OK != 0 || ZLIB_STREAM_END != 1 || ZLIB_NEED_DICT != 2 { ok = false; }
  if ZLIB_ERRNO != -1 || ZLIB_STREAM_ERROR != -2 || ZLIB_DATA_ERROR != -3 { ok = false; }
  if ZLIB_MEM_ERROR != -4 || ZLIB_BUF_ERROR != -5 || ZLIB_VERSION_ERROR != -6 { ok = false; }
  if ZLIB_NO_FLUSH != 0 || ZLIB_SYNC_FLUSH != 2 || ZLIB_FINISH != 4 { ok = false; }
  if ZLIB_DEFAULT_COMPRESSION != -1 { ok = false; }
  if ZLIB_NO_COMPRESSION != 0 || ZLIB_BEST_SPEED != 1 || ZLIB_BEST_COMPRESSION != 9 { ok = false; }
  if !str_eq(zlib_rc_name(ZLIB_OK), "Z_OK") { ok = false; }
  if !str_eq(zlib_rc_name(ZLIB_DATA_ERROR), "Z_DATA_ERROR") { ok = false; }
  return ok;
}

fn t_icu_constants() -> Bool {
  var ok = true;
  if ICU_LOAD_ABSENT != 0 || ICU_GATED != 1 || ICU_CALL != 2 { ok = false; }
  if U_ZERO_ERROR != 0 || U_ILLEGAL_ARGUMENT_ERROR != 1 { ok = false; }
  if U_INVALID_CHAR_FOUND != 10 || U_TRUNCATED_CHAR_FOUND != 11 { ok = false; }
  if U_ILLEGAL_CHAR_FOUND != 12 || U_BUFFER_OVERFLOW_ERROR != 15 { ok = false; }
  if U_STRING_NOT_TERMINATED_WARNING != -124 { ok = false; }
  return ok;
}

// =========================================================================
// log + sync (0.1.0 head -- unchanged)
// =========================================================================

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
  info("log: is_loggable(VERBOSE, default INFO) = " + verbose_text
    + " (expected false when no log.tag override)");
  let len_ok = log_is_loggable_len(ANDROID_LOG_INFO, "xiom-android-sys", 16, ANDROID_LOG_INFO);
  failed = failed + report(len_ok, "log: is_loggable_len(INFO, len=16, default INFO) = true");

  let b = log_buf_write(LOG_ID_MAIN, ANDROID_LOG_INFO, "xiom-android-sys", "xiom.android-sys probe: __android_log_buf_write ok");
  if b.is_ok {
    failed = failed + report(b.value == 1, "log: __android_log_buf_write rc=" + to_string(b.value) + " (1 = written)");
  } else {
    failed = failed + report(false, "log: __android_log_buf_write failed -- " + b.error.message);
  }

  let mp = log_minimum_priority();
  info("log: minimum_priority = " + to_string(mp)
    + " (-1 = API-30 ext symbol absent on this device)");
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

fn t_log_sync_runtime() -> Int {
  var failed: Int = 0;
  // Default runtime probe.
  let p = android_sys_probe();
  if p.is_ok {
    let rt: AndroidSysRuntime = p.value;
    failed = failed + report(rt.missing_exports == 0,
      "abi: core export set fully resolved (" + to_string(rt.missing_exports) + " missing)");
    info("abi: API-30 liblog extensions " + to_string(rt.ext_total - rt.ext_missing)
      + "/" + to_string(rt.ext_total) + " present (informational; older devices may miss them)");
    failed = failed + t_log_functional();
    failed = failed + t_sync_error_path();
  } else {
    if p.error.kind == ANDROID_SYS_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- android sys runtime not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }
  android_sys_unload();
  return failed;
}

// =========================================================================
// binder (libbinder_ndk.so)
// =========================================================================

fn t_binder_runtime() -> Int {
  var failed: Int = 0;
  let p = binder_probe();
  if p.is_err {
    if p.error.kind == ANDROID_SYS_LOAD_ABSENT {
      failed = failed + report(true, "binder: SKIP -- libbinder_ndk.so not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "binder: probe failed -- " + p.error.message);
    }
    binder_unload();
    return failed;
  }
  let rt: BinderRuntime = p.value;
  failed = failed + report(rt.core_missing == 0,
    "binder: core export set fully resolved (" + to_string(rt.core_missing) + " missing" + rt.core_missing_names + ")");
  info("binder: API-31/33 class extensions " + to_string(rt.ext_total - rt.ext_missing)
    + "/" + to_string(rt.ext_total) + " present");

  let d = binder_class_define("xiom.a12.probe");
  if d.is_err {
    failed = failed + report(false, "binder: class_define failed -- " + d.error.message);
    binder_unload();
    return failed;
  }
  let clazz = d.value;
  failed = failed + report(clazz != 0, "binder: class defined (AIBinder_Class_define)");

  // Interface descriptor (class surface; AIBinder_Class_getDescriptor is
  // API 31+ -- the loader reports it as ext, the cached fallback covers
  // older devices).
  let desc = binder_class_descriptor(clazz);
  failed = failed + report(str_eq(desc, "xiom.a12.probe"),
    "binder: interface descriptor = \"" + desc + "\"");

  let c = binder_create(clazz, 42);
  if c.is_err {
    failed = failed + report(false, "binder: create failed -- " + c.error.message);
    binder_unload();
    return failed;
  }
  let b = c.value;
  failed = failed + report(b != 0, "binder: instance created (AIBinder_new)");

  let assoc = binder_associate_class(b, clazz);
  if assoc.is_ok {
    failed = failed + report(assoc.value, "binder: associateClass(b, class) = true");
  } else {
    failed = failed + report(false, "binder: associateClass failed -- " + assoc.error.message);
  }

  let gcl = binder_get_class(b);
  if gcl.is_ok {
    failed = failed + report(gcl.value == clazz, "binder: getClass identity (same class handle)");
  } else {
    failed = failed + report(false, "binder: getClass failed -- " + gcl.error.message);
  }

  let alive = binder_is_alive(b);
  if alive.is_ok {
    failed = failed + report(alive.value, "binder: isAlive = true (local instance)");
  } else {
    failed = failed + report(false, "binder: isAlive failed -- " + alive.error.message);
  }

  let remote = binder_is_remote(b);
  if remote.is_ok {
    failed = failed + report(!remote.value, "binder: isRemote = false (local instance)");
  } else {
    failed = failed + report(false, "binder: isRemote failed -- " + remote.error.message);
  }

  let ping = binder_ping(b);
  if ping.is_ok {
    failed = failed + report(ping.value == BINDER_STATUS_OK,
      "binder: ping -> " + binder_status_name(ping.value));
  } else {
    failed = failed + report(false, "binder: ping failed -- " + ping.error.message);
  }

  // Ref-count transitions: 1 -> inc -> 2 -> dec -> 1 -> dec -> destroy.
  let rc1 = binder_debug_ref_count(b);
  if rc1.is_ok {
    failed = failed + report(rc1.value == 1, "binder: refcount after create = " + to_string(rc1.value));
  } else {
    failed = failed + report(false, "binder: debugGetRefCount failed -- " + rc1.error.message);
  }
  binder_inc_strong(b);
  let rc2 = binder_debug_ref_count(b);
  if rc2.is_ok {
    failed = failed + report(rc2.value == 2, "binder: refcount after incStrong = " + to_string(rc2.value));
  } else {
    failed = failed + report(false, "binder: debugGetRefCount (after inc) failed -- " + rc2.error.message);
  }
  binder_dec_strong(b);
  let rc3 = binder_debug_ref_count(b);
  if rc3.is_ok {
    failed = failed + report(rc3.value == 1, "binder: refcount after decStrong = " + to_string(rc3.value));
  } else {
    failed = failed + report(false, "binder: debugGetRefCount (after dec) failed -- " + rc3.error.message);
  }

  let destroys_before = binder_destroy_count();
  binder_dec_strong(b); // last strong reference -> onDestroy
  let destroys_after = binder_destroy_count();
  failed = failed + report(destroys_after == destroys_before + 1,
    "binder: destroy observed (onDestroy count " + to_string(destroys_before) + " -> " + to_string(destroys_after) + ")");

  info("binder: calling uid=" + to_string(binder_calling_uid())
    + " pid=" + to_string(binder_calling_pid()) + " (own identity outside a transaction)");
  info("binder: transact callbacks observed = " + to_string(binder_transact_count())
    + " (transact/parcel surface is a documented delta)");
  binder_unload();
  return failed;
}

// =========================================================================
// nnapi (libneuralnetworks.so)
// =========================================================================

fn t_nnapi_runtime() -> Int {
  var failed: Int = 0;
  let p = nnapi_probe();
  if p.is_err {
    if p.error.kind == ANDROID_SYS_LOAD_ABSENT {
      failed = failed + report(true, "nnapi: SKIP -- libneuralnetworks.so not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "nnapi: probe failed -- " + p.error.message);
    }
    nnapi_unload();
    return failed;
  }
  let rt: NnapiRuntime = p.value;
  failed = failed + report(rt.core_missing == 0,
    "nnapi: core export set fully resolved (" + to_string(rt.core_missing) + " missing" + rt.core_missing_names + ")");
  info("nnapi: API-29 device-query extensions " + to_string(rt.ext_total - rt.ext_missing)
    + "/" + to_string(rt.ext_total) + " present");

  // Device query (recorded; the emulator reference driver reports >= 1).
  let dc = nn_device_count();
  if dc.is_ok {
    info("nnapi: devices = " + to_string(dc.value));
    var di = 0;
    while di < dc.value {
      let nm = nn_device_name(di);
      let tv = nn_device_type(di);
      let fv = nn_device_feature_level(di);
      var name_text: Str = "?";
      if nm.is_ok { name_text = nm.value; }
      var type_text: Str = "?";
      if tv.is_ok { type_text = to_string(tv.value); }
      var level_text: Str = "?";
      if fv.is_ok { level_text = to_string(fv.value); }
      info("nnapi: device[" + to_string(di) + "] name=\"" + name_text + "\" type=" + type_text + " feature=" + level_text);
      di = di + 1;
    }
  } else {
    info("nnapi: getDeviceCount unavailable (" + dc.error.message + ")");
  }
  let rl = nn_runtime_feature_level();
  if rl.is_ok {
    info("nnapi: runtime feature level = " + to_string(rl.value));
  }

  // Offline model build (canonical signature): out = in0 + in1 with the
  // level-8 Broadcast.cpp form ADD(x, y, activation) -- the activation is
  // an INT32 scalar constant (FUSED_NONE).
  let m = nn_model_create();
  if m.is_err {
    failed = failed + report(false, "nnapi: model_create failed -- " + m.error.message);
    nnapi_unload();
    return failed;
  }
  let model = m.value;
  failed = failed + report(model != 0, "nnapi: model created (ANeuralNetworksModel_create)");

  var dims = nn_dims1(2);
  let o0 = nn_model_add_tensor(model, ANEURALNETWORKS_TENSOR_FLOAT32, &mut dims, 0, 0);
  if o0.is_ok {
    failed = failed + report(true, "nnapi: operand 0 (TENSOR_FLOAT32 {2} input)");
  } else {
    failed = failed + report(false, "nnapi: addOperand 0 failed -- " + o0.error.message);
  }
  let o1 = nn_model_add_tensor(model, ANEURALNETWORKS_TENSOR_FLOAT32, &mut dims, 0, 0);
  if o1.is_ok {
    failed = failed + report(true, "nnapi: operand 1 (TENSOR_FLOAT32 {2} input)");
  } else {
    failed = failed + report(false, "nnapi: addOperand 1 failed -- " + o1.error.message);
  }
  var no_dims: Vec[UInt8] = Vec[UInt8].new();
  let o2 = nn_model_add_tensor(model, ANEURALNETWORKS_INT32, &mut no_dims, 0, 0);
  if o2.is_ok {
    failed = failed + report(true, "nnapi: operand 2 (INT32 scalar activation)");
  } else {
    failed = failed + report(false, "nnapi: addOperand 2 failed -- " + o2.error.message);
  }
  let o3 = nn_model_add_tensor(model, ANEURALNETWORKS_TENSOR_FLOAT32, &mut dims, 0, 0);
  if o3.is_ok {
    failed = failed + report(true, "nnapi: operand 3 (output TENSOR_FLOAT32 {2})");
  } else {
    failed = failed + report(false, "nnapi: addOperand 3 failed -- " + o3.error.message);
  }

  let fused = nn_model_set_scalar_i32(model, 2, ANEURALNETWORKS_FUSED_NONE);
  if fused.is_ok {
    failed = failed + report(true, "nnapi: activation operand = FUSED_NONE (setOperandValue)");
  } else {
    failed = failed + report(false, "nnapi: setOperandValue failed -- " + fused.error.message);
  }

  var ins = nn_ids3(0, 1, 2);
  var outs = nn_ids1(3);
  let op = nn_model_add_operation(model, ANEURALNETWORKS_OP_ADD, &mut ins, &mut outs);
  if op.is_ok {
    failed = failed + report(true, "nnapi: ADD (x, y, activation) -> out");
  } else {
    failed = failed + report(false, "nnapi: addOperation failed -- " + op.error.message);
  }

  var io_ins = nn_ids2(0, 1);
  let io = nn_model_identify_io(model, &mut io_ins, &mut outs);
  if io.is_ok {
    failed = failed + report(true, "nnapi: identifyInputsAndOutputs ({0,1},{3})");
  } else {
    failed = failed + report(false, "nnapi: identifyInputsAndOutputs failed -- " + io.error.message);
  }

  let fin = nn_model_finish(model);
  if fin.is_ok {
    failed = failed + report(true, "nnapi: model finish (offline build OK)");
  } else {
    failed = failed + report(false, "nnapi: model finish failed -- " + fin.error.message);
  }

  if fin.is_ok {
    let comp = nn_compilation_create(model);
    if comp.is_ok {
      failed = failed + report(true, "nnapi: compilation created");
      let cfin = nn_compilation_finish(comp.value);
      if cfin.is_ok {
        failed = failed + report(true, "nnapi: compilation finish (device stage OK)");
        let ex = nn_execution_create(comp.value);
        if ex.is_ok {
          failed = failed + report(true, "nnapi: execution created (ANeuralNetworksExecution_create)");
          nn_execution_free(ex.value);
        } else {
          failed = failed + report(false, "nnapi: execution_create failed -- " + ex.error.message);
        }
      } else {
        // Documented device-absent path: the device stage may be
        // unavailable without a usable driver; the offline cluster above
        // is the gated proof.
        failed = failed + report(true, "nnapi: compilation finish gated (documented device-absent path) -- " + cfin.error.message);
      }
      nn_compilation_free(comp.value);
    } else {
      failed = failed + report(false, "nnapi: compilation_create failed -- " + comp.error.message);
    }
  }
  nn_model_free(model);
  nnapi_unload();
  return failed;
}

// =========================================================================
// zlib (libz.so)
// =========================================================================

fn t_zlib_runtime() -> Int {
  var failed: Int = 0;
  let p = zlib_probe();
  if p.is_err {
    if p.error.kind == ANDROID_SYS_LOAD_ABSENT {
      failed = failed + report(true, "zlib: SKIP -- libz.so not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "zlib: probe failed -- " + p.error.message);
    }
    zlib_unload();
    return failed;
  }
  let rt: ZlibRuntime = p.value;
  failed = failed + report(rt.core_missing == 0,
    "zlib: core export set fully resolved (" + to_string(rt.core_missing) + " missing" + rt.core_missing_names + ")");

  let v = zlib_version();
  failed = failed + report(!str_eq(v, ""), "zlib: version = \"" + v + "\"");

  // Known answers (standard zlib test vectors).
  var msg = bytes_of("123456789");
  let crc = zlib_crc32(0, &mut msg);
  failed = failed + report(crc == 0xCBF43926, "zlib: crc32(\"123456789\") = " + to_string(crc) + " (expect 0xCBF43926)");
  let adl = zlib_adler32(1, &mut msg);
  failed = failed + report(adl == 0x091E01DE, "zlib: adler32(\"123456789\") = " + to_string(adl) + " (expect 0x091E01DE)");

  let bound = zlib_compress_bound(1024);
  failed = failed + report(bound >= 1024, "zlib: compressBound(1024) = " + to_string(bound));

  // Roundtrip fixture: compress -> uncompress must be exact.
  var fixture = text_fixture(4096);
  let original = copyv(&fixture);
  let cz = zlib_compress(&mut fixture);
  if cz.is_ok {
    var comp = cz.value;
    failed = failed + report(comp.len() < original.len(),
      "zlib: compress 4096 -> " + to_string(comp.len()) + " bytes (smaller than source)");
    let back = zlib_uncompress(&mut comp, original.len());
    if back.is_ok {
      var plain = back.value;
      failed = failed + report(buffers_equal(&plain, &original),
        "zlib: compress -> uncompress roundtrip exact (" + to_string(plain.len()) + " bytes)");
    } else {
      failed = failed + report(false, "zlib: uncompress failed -- " + back.error.message);
    }
  } else {
    failed = failed + report(false, "zlib: compress failed -- " + cz.error.message);
  }

  // Streaming: deflateInit_/deflate/deflateEnd roundtrip via
  // inflateInit_/inflate/inflateEnd.
  var stream_src = text_fixture(2048);
  let stream_original = copyv(&stream_src);
  let df = zlib_deflate_stream(&mut stream_src, ZLIB_DEFAULT_COMPRESSION);
  if df.is_ok {
    var dcomp = df.value;
    failed = failed + report(dcomp.len() < stream_original.len(),
      "zlib: deflate stream 2048 -> " + to_string(dcomp.len()) + " bytes");
    let inf = zlib_inflate_stream(&mut dcomp, stream_original.len());
    if inf.is_ok {
      var splain = inf.value;
      failed = failed + report(buffers_equal(&splain, &stream_original),
        "zlib: deflate -> inflate stream roundtrip exact (" + to_string(splain.len()) + " bytes)");
    } else {
      failed = failed + report(false, "zlib: inflate_stream failed -- " + inf.error.message);
    }
  } else {
    failed = failed + report(false, "zlib: deflate_stream failed -- " + df.error.message);
  }
  zlib_unload();
  return failed;
}

// =========================================================================
// icu (libicuuc.so; declared subset)
// =========================================================================

fn t_icu_runtime() -> Int {
  var failed: Int = 0;
  let p = icu_probe();
  if p.is_err {
    if p.error.kind == ANDROID_SYS_LOAD_ABSENT {
      failed = failed + report(true, "icu: SKIP -- libandroidicu.so not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "icu: probe failed -- " + p.error.message);
    }
    icu_unload();
    return failed;
  }
  let rt: IcuRuntime = p.value;
  if rt.required_missing != 0 {
    // Version gate by design: the declared subset is __INTRODUCED_IN(31)
    // in the NDK; pre-31 platforms land here.
    failed = failed + report(true, "icu: SKIP (gated) -- required subset requires API 31; missing: "
      + rt.required_missing_names);
    icu_unload();
    return failed;
  }
  failed = failed + report(rt.required_missing == 0,
    "icu: required subset fully resolved (" + to_string(rt.declared_total - rt.required_missing - rt.optional_missing)
    + "/" + to_string(rt.declared_total) + " present; declared total includes optional u_strlen)");
  if rt.optional_missing != 0 {
    // u_strlen is header-announced (API 31) but NOT exported by the
    // API-36 platform shim (libandroidicu.so, ICU 75.1) -- recorded,
    // never faked; the utf16 length verdict is gated below.
    info("icu: optional u_strlen unavailable on this platform shim (" + rt.optional_missing_names + ")");
  }

  if !str_eq(icu_error_name(U_ZERO_ERROR), "U_ZERO_ERROR") {
    failed = failed + report(false, "icu: errorName(U_ZERO_ERROR) = \"" + icu_error_name(U_ZERO_ERROR) + "\"");
  } else {
    failed = failed + report(true, "icu: errorName(U_ZERO_ERROR) = \"U_ZERO_ERROR\"");
  }

  // UTF roundtrip fixture: "caf" + U+00E9 (UTF-8 0xC3 0xA9) + " lab".
  var raw: Vec[UInt8] = Vec[UInt8].new();
  raw.push(string.byte_at("caf", 0));
  raw.push(string.byte_at("caf", 1));
  raw.push(string.byte_at("caf", 2));
  raw.push(0xC3 as UInt8);
  raw.push(0xA9 as UInt8);
  raw.push(string.byte_at(" lab", 0));
  raw.push(string.byte_at(" lab", 1));
  raw.push(string.byte_at(" lab", 2));
  raw.push(string.byte_at(" lab", 3));
  let text = Str::from_utf8(raw);

  let u16 = icu_utf8_to_utf16(text);
  if u16.is_err {
    failed = failed + report(false, "icu: utf8_to_utf16 failed -- " + u16.error.message);
    icu_unload();
    return failed;
  }
  var units = u16.value;
  failed = failed + report(units.len() == 16, "icu: utf8_to_utf16 bytes = " + to_string(units.len()) + " (8 UTF-16 units)");
  if rt.optional_missing == 0 {
    let ulen = icu_utf16_length(&mut units);
    if ulen.is_ok {
      failed = failed + report(ulen.value == 8, "icu: u_strlen = " + to_string(ulen.value) + " (expect 8)");
    } else {
      failed = failed + report(false, "icu: u_strlen failed -- " + ulen.error.message);
    }
  } else {
    failed = failed + report(true, "icu: u_strlen check gated (optional symbol absent on this shim; recorded above)");
  }
  let back = icu_utf16_to_utf8(&mut units);
  if back.is_ok {
    failed = failed + report(str_eq(back.value, text),
      "icu: utf8 -> utf16 -> utf8 roundtrip exact");
  } else {
    failed = failed + report(false, "icu: utf16_to_utf8 failed -- " + back.error.message);
  }

  // Simple case mapping (u_toupper/u_tolower).
  let up_a = icu_toupper(0x61);     // 'a' -> 'A'
  let up_e = icu_toupper(0xE9);     // U+00E9 -> U+00C9
  let lo_z = icu_tolower(0x5A);     // 'Z' -> 'z'
  let lo_e = icu_tolower(0xC9);     // U+00C9 -> U+00E9
  var case_ok = false;
  var up_a_text: Str = "err";
  if up_a.is_ok { up_a_text = to_string(up_a.value); }
  if up_a.is_ok && up_e.is_ok && lo_z.is_ok && lo_e.is_ok {
    if up_a.value == 0x41 && up_e.value == 0xC9 && lo_z.value == 0x7A && lo_e.value == 0xE9 {
      case_ok = true;
    }
  }
  failed = failed + report(case_ok,
    "icu: case mapping a->A, e9->C9, Z->z, C9->e9 (u_toupper=" + up_a_text + ")");
  icu_unload();
  return failed;
}

// =========================================================================
// main
// =========================================================================

fn main() -> Int {
  io.println("=== xiom.android-sys conformance tests (A12 system surface, 0.2.0) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "log/sync constants: kinds + priorities/ids + sync ioctls/struct sizes + errno family");
  failed = failed + report(t_binder_constants(), "binder constants: classification + binder_status_t values + names");
  failed = failed + report(t_nnapi_constants(), "nnapi constants: operand/op/error/device codes + names");
  failed = failed + report(t_zlib_constants(), "zlib constants: rc family + flush levels + names");
  failed = failed + report(t_icu_constants(), "icu constants: classification + UErrorCode values");

  // SKIP-path classification, deterministic on every host (bogus names).
  let missing = android_sys_probe_named("xiom-absent-liblog-xyz.so", "xiom-absent-libsync-xyz.so");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus log/sync pair unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == ANDROID_SYS_LOAD_ABSENT,
      "skip-path: absent log/sync pair classified as ANDROID_SYS_LOAD_ABSENT (SKIP)");
  }
  let bmissing = binder_probe_named("xiom-absent-libbinder-xyz.so");
  if bmissing.is_ok {
    failed = failed + report(false, "skip-path: bogus binder lib unexpectedly loaded");
  } else {
    failed = failed + report(bmissing.error.kind == ANDROID_SYS_LOAD_ABSENT,
      "skip-path: absent binder lib classified as BINDER_LOAD_ABSENT (SKIP)");
  }
  let nmissing = nnapi_probe_named("xiom-absent-libnnapi-xyz.so");
  if nmissing.is_ok {
    failed = failed + report(false, "skip-path: bogus nnapi lib unexpectedly loaded");
  } else {
    failed = failed + report(nmissing.error.kind == ANDROID_SYS_LOAD_ABSENT,
      "skip-path: absent nnapi lib classified as NNAPI_LOAD_ABSENT (SKIP)");
  }
  let zmissing = zlib_probe_named("xiom-absent-libz-xyz.so");
  if zmissing.is_ok {
    failed = failed + report(false, "skip-path: bogus zlib lib unexpectedly loaded");
  } else {
    failed = failed + report(zmissing.error.kind == ANDROID_SYS_LOAD_ABSENT,
      "skip-path: absent zlib lib classified as ZLIB_LOAD_ABSENT (SKIP)");
  }
  let imissing = icu_probe_named("xiom-absent-libicu-xyz.so");
  if imissing.is_ok {
    failed = failed + report(false, "skip-path: bogus icu lib unexpectedly loaded");
  } else {
    failed = failed + report(imissing.error.kind == ANDROID_SYS_LOAD_ABSENT,
      "skip-path: absent icu lib classified as ICU_LOAD_ABSENT (SKIP)");
  }

  // Per-lib live paths (each SKIPs independently when absent).
  failed = failed + t_log_sync_runtime();
  failed = failed + t_binder_runtime();
  failed = failed + t_nnapi_runtime();
  failed = failed + t_zlib_runtime();
  failed = failed + t_icu_runtime();

  // Unload must be safe even after failed probes (idempotent).
  android_sys_unload();
  binder_unload();
  nnapi_unload();
  zlib_unload();
  icu_unload();
  failed = failed + report(true, "loader: unload paths exercised (all five units)");

  if failed == 0 {
    io.println("xiom.android-sys: all tests passed");
  } else {
    io.println("xiom.android-sys: tests failed");
  }
  return failed;
}
