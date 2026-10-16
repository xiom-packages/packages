// xiom.android conformance suite -- platform-core (libandroid.so +
// libnativewindow.so) loader/probe for the A1 window-core + A5
// assets-storage + A2 lifecycle-glue + A3 input + A4 sensors heads.
//
// The probe never FAILs on a missing runtime:
//   present runtime -> export-set ABI check + functional AHardwareBuffer
//                      roundtrip (isSupported/allocate/describe/write/
//                      read/release) + ASharedMemory + ALooper
//                      (ident + direct-handoff callback + poll codes) +
//                      AConfiguration value object + the A4 sensor
//                      manager (enumerate + describe + queue roundtrip)
//                      -- the A3 queue itself is app-delivered, so its
//                      live path lives in the on-device app probe and
//                      this suite checks the A3/A4 constant clusters +
//                      the explicit-error contract of every head
//   missing libs    -> ANDROID_LOAD_ABSENT (SKIP; exercised
//                      deterministically below with bogus sonames)
//   broken install  -> ANDROID_LOAD_ABI (FAIL -- never a silent SKIP)
//
// On Windows the runtime is absent by design -> SKIP (CI stays green);
// the unloaded-runtime checks below still run (an explicit error, never
// a silent zero handle).  On an Android device/emulator the same suite
// runs the live path.
//
// Build+run through the runner (compiles src/android_bridge.c via
// port.args.json):
//   scripts/port.ps1 -Package xiom.android

module android_conformance

use xiom.io;
use xiom.android;
use xiom.android.lifecycle;
use xiom.android.configuration;
use xiom.android.input;
use xiom.android.sensors;

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

// =========================================================================
// ALooper direct-handoff handler (env-free top-level fn; B-22 fixed in
// m277) + the observation slots the suite asserts on.
// =========================================================================

var looper_cb_calls: Int = 0;
var looper_cb_fd: Int = 0;
var looper_cb_events: Int = 0;

fn on_looper_input(fd: Int32, events: Int32, data: Int) -> Int32 {
  looper_cb_calls = looper_cb_calls + 1;
  looper_cb_fd = fd as Int;
  looper_cb_events = events as Int;
  return 1;
}

fn t_constants() -> Bool {
  var ok = true;
  if ANDROID_LOAD_ABSENT != 0 || ANDROID_LOAD_ABI != 1 { ok = false; }
  if WINDOW_FORMAT_RGBA_8888 != 1 || WINDOW_FORMAT_RGBX_8888 != 2 || WINDOW_FORMAT_RGB_565 != 4 { ok = false; }
  if ANATIVEWINDOW_TRANSFORM_IDENTITY != 0 || ANATIVEWINDOW_TRANSFORM_ROTATE_90 != 4 { ok = false; }
  if ANATIVEWINDOW_TRANSFORM_ROTATE_180 != 3 || ANATIVEWINDOW_TRANSFORM_ROTATE_270 != 7 { ok = false; }
  if AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM != 1 || AHARDWAREBUFFER_FORMAT_R5G6B5_UNORM != 4 { ok = false; }
  if AHARDWAREBUFFER_FORMAT_R16G16B16A16_FLOAT != 0x16 || AHARDWAREBUFFER_FORMAT_BLOB != 0x21 { ok = false; }
  if AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN != 3 || AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN != 0x30 { ok = false; }
  if AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE != 0x100 || AHARDWAREBUFFER_USAGE_GPU_FRAMEBUFFER != 0x200 { ok = false; }
  if AASSET_MODE_UNKNOWN != 0 || AASSET_MODE_RANDOM != 1 || AASSET_MODE_STREAMING != 2 || AASSET_MODE_BUFFER != 3 { ok = false; }
  if PROT_NONE != 0 || PROT_READ != 1 || PROT_WRITE != 2 || PROT_EXEC != 4 { ok = false; }
  return ok;
}

fn t_a2_constants() -> Bool {
  var ok = true;
  // looper.h
  if ALOOPER_PREPARE_ALLOW_NON_CALLBACKS != 1 { ok = false; }
  if ALOOPER_POLL_WAKE != -1 || ALOOPER_POLL_CALLBACK != -2 { ok = false; }
  if ALOOPER_POLL_TIMEOUT != -3 || ALOOPER_POLL_ERROR != -4 { ok = false; }
  if ALOOPER_EVENT_INPUT != 1 || ALOOPER_EVENT_OUTPUT != 2 { ok = false; }
  if ALOOPER_EVENT_ERROR != 4 || ALOOPER_EVENT_HANGUP != 8 || ALOOPER_EVENT_INVALID != 16 { ok = false; }
  // native_activity.h flags
  if ANATIVEACTIVITY_SHOW_SOFT_INPUT_IMPLICIT != 1 || ANATIVEACTIVITY_SHOW_SOFT_INPUT_FORCED != 2 { ok = false; }
  if ANATIVEACTIVITY_HIDE_SOFT_INPUT_IMPLICIT_ONLY != 1 || ANATIVEACTIVITY_HIDE_SOFT_INPUT_NOT_ALWAYS != 2 { ok = false; }
  // configuration.h (spot set; the full transcription is build-time
  // checked against the NDK header in the on-device driver)
  if ACONFIGURATION_ORIENTATION_PORT != 1 || ACONFIGURATION_ORIENTATION_LAND != 2 { ok = false; }
  if ACONFIGURATION_TOUCHSCREEN_FINGER != 3 || ACONFIGURATION_DENSITY_HIGH != 240 { ok = false; }
  if ACONFIGURATION_DENSITY_ANY != 0xfffe || ACONFIGURATION_DENSITY_NONE != 0xffff { ok = false; }
  if ACONFIGURATION_SCREENSIZE_NORMAL != 2 || ACONFIGURATION_UI_MODE_TYPE_VR_HEADSET != 7 { ok = false; }
  if ACONFIGURATION_UI_MODE_NIGHT_YES != 2 || ACONFIGURATION_LAYOUTDIR_RTL != 2 { ok = false; }
  if ACONFIGURATION_MNC_ZERO != 0xffff || ACONFIGURATION_GRAMMATICAL_GENDER_MASCULINE != 3 { ok = false; }
  if ACONFIGURATION_LOCALE != 0x0004 || ACONFIGURATION_DENSITY != 0x0100 { ok = false; }
  if ACONFIGURATION_COLOR_MODE != 0x10000 || ACONFIGURATION_GRAMMATICAL_GENDER != 0x20000 { ok = false; }
  return ok;
}

fn t_a3_constants() -> Bool {
  var ok = true;
  // input.h event types + sources (spot set; the full transcription is
  // build-time checked against the NDK header in the on-device probe).
  if AINPUT_EVENT_TYPE_KEY != 1 || AINPUT_EVENT_TYPE_MOTION != 2 { ok = false; }
  if AINPUT_EVENT_TYPE_CAPTURE != 4 || AINPUT_EVENT_TYPE_DRAG != 5 { ok = false; }
  if AINPUT_SOURCE_CLASS_MASK != 0xFF || AINPUT_SOURCE_CLASS_POINTER != 2 { ok = false; }
  if AINPUT_SOURCE_KEYBOARD != 0x101 || AINPUT_SOURCE_TOUCHSCREEN != 0x1002 { ok = false; }
  if AINPUT_SOURCE_JOYSTICK != 0x1000010 { ok = false; }
  if AINPUT_KEYBOARD_TYPE_ALPHABETIC != 2 { ok = false; }
  // key event actions/flags + meta states.
  if AKEY_EVENT_ACTION_DOWN != 0 || AKEY_EVENT_ACTION_UP != 1 { ok = false; }
  if AKEY_EVENT_FLAG_LONG_PRESS != 128 || AKEY_EVENT_FLAG_FALLBACK != 1024 { ok = false; }
  if AMETA_SHIFT_ON != 1 || AMETA_ALT_ON != 2 || AMETA_CTRL_ON != 4096 { ok = false; }
  if AMETA_META_ON != 65536 || AMETA_SCROLL_LOCK_ON != 4194304 { ok = false; }
  // motion event actions/flags/buttons/edges/tools/classification.
  if AMOTION_EVENT_ACTION_DOWN != 0 || AMOTION_EVENT_ACTION_MOVE != 2 { ok = false; }
  if AMOTION_EVENT_ACTION_POINTER_DOWN != 5 || AMOTION_EVENT_ACTION_SCROLL != 8 { ok = false; }
  if AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT != 8 { ok = false; }
  if AMOTION_EVENT_ACTION_POINTER_INDEX_MASK != 65280 { ok = false; }
  if AMOTION_EVENT_BUTTON_PRIMARY != 1 || AMOTION_EVENT_BUTTON_STYLUS_SECONDARY != 64 { ok = false; }
  if AMOTION_EVENT_EDGE_FLAG_TOP != 1 || AMOTION_EVENT_EDGE_FLAG_RIGHT != 8 { ok = false; }
  if AMOTION_EVENT_TOOL_TYPE_FINGER != 1 || AMOTION_EVENT_TOOL_TYPE_PALM != 5 { ok = false; }
  if AMOTION_EVENT_AXIS_X != 0 || AMOTION_EVENT_AXIS_ORIENTATION != 8 { ok = false; }
  if AMOTION_EVENT_AXIS_GENERIC_1 != 32 || AMOTION_EVENT_AXIS_GESTURE_SWIPE_FINGER_COUNT != 53 { ok = false; }
  if AMOTION_EVENT_CLASSIFICATION_DEEP_PRESS != 2 || AMOTION_EVENT_CLASSIFICATION_PINCH != 5 { ok = false; }
  // keycodes.h frozen enum (spot set across the table incl. the tail).
  if AKEYCODE_UNKNOWN != 0 || AKEYCODE_HOME != 3 || AKEYCODE_BACK != 4 { ok = false; }
  if AKEYCODE_A != 29 || AKEYCODE_Z != 54 || AKEYCODE_ENTER != 66 { ok = false; }
  if AKEYCODE_MENU != 82 || AKEYCODE_ESCAPE != 111 || AKEYCODE_NUM_LOCK != 143 { ok = false; }
  if AKEYCODE_MUTE != 91 || AKEYCODE_ASSIST != 219 || AKEYCODE_HELP != 259 { ok = false; }
  if AKEYCODE_SOFT_SLEEP != 276 || AKEYCODE_RECENT_APPS != 312 { ok = false; }
  if AKEYCODE_STYLUS_BUTTON_TAIL != 311 || AKEYCODE_MACRO_4 != 316 { ok = false; }
  return ok;
}

fn t_a4_constants() -> Bool {
  var ok = true;
  // sensor.h types/status/direct/limits (spot set; the full transcription
  // is build-time checked in the on-device probe).
  if ASENSOR_TYPE_INVALID != -1 || ASENSOR_TYPE_ACCELEROMETER != 1 { ok = false; }
  if ASENSOR_TYPE_MAGNETIC_FIELD != 2 || ASENSOR_TYPE_GYROSCOPE != 4 { ok = false; }
  if ASENSOR_TYPE_LIGHT != 5 || ASENSOR_TYPE_PROXIMITY != 8 { ok = false; }
  if ASENSOR_TYPE_ROTATION_VECTOR != 11 || ASENSOR_TYPE_HEART_RATE != 21 { ok = false; }
  if ASENSOR_TYPE_POSE_6DOF != 28 || ASENSOR_TYPE_DYNAMIC_SENSOR_META != 32 { ok = false; }
  if ASENSOR_TYPE_ADDITIONAL_INFO != 33 || ASENSOR_TYPE_HEADING != 42 { ok = false; }
  if ASENSOR_STATUS_UNRELIABLE != 0 || ASENSOR_STATUS_ACCURACY_HIGH != 3 { ok = false; }
  if ASENSOR_STATUS_NO_CONTACT != -1 { ok = false; }
  if ASENSOR_DIRECT_RATE_STOP != 0 || ASENSOR_DIRECT_RATE_NORMAL != 1 { ok = false; }
  if ASENSOR_DIRECT_RATE_FAST != 2 || ASENSOR_DIRECT_RATE_VERY_FAST != 3 { ok = false; }
  if ASENSOR_DIRECT_CHANNEL_TYPE_SHARED_MEMORY != 1 { ok = false; }
  if ASENSOR_DIRECT_CHANNEL_TYPE_HARDWARE_BUFFER != 2 { ok = false; }
  if ASENSOR_ADDITIONAL_INFO_BEGIN != 0 || ASENSOR_ADDITIONAL_INFO_END != 1 { ok = false; }
  if ASENSOR_ADDITIONAL_INFO_INTERNAL_TEMPERATURE != 65537 { ok = false; }
  if ASENSOR_INVALID != -1 || ASENSOR_FIFO_COUNT_INVALID != -1 { ok = false; }
  if ASENSOR_DELAY_INVALID != -2147483648 { ok = false; }
  // nanf("") sentinel transcribed as its IEEE-754 quiet-NaN bit pattern.
  if ASENSOR_RESOLUTION_INVALID != 2143289344 { ok = false; }
  // float constants (reconstructed value equality at binary32 precision).
  let g = ASENSOR_STANDARD_GRAVITY;
  if g < 9.806 || g > 9.807 { ok = false; }
  if ASENSOR_MAGNETIC_FIELD_EARTH_MAX != 60.0 { ok = false; }
  if ASENSOR_MAGNETIC_FIELD_EARTH_MIN != 30.0 { ok = false; }
  return ok;
}

// Explicit-error contract of the A3/A4 heads: null handles (and an
// unloaded runtime on Windows) must produce recorded errors -- never a
// silent zero.  Null-handle checks are safe on every host.
fn t_a3a4_explicit_errors() -> Int {
  var failed: Int = 0;
  let q0 = InputQueue{ handle: 0 };
  failed = failed + report(input_queue_has_events(&q0) == -1,
    "input: has_events on null queue -> explicit error");
  let ev0 = input_event_read(&q0);
  failed = failed + report(!ev0.is_ok, "input: event_read on null queue -> explicit error");
  let lq0 = SensorEventQueue{ handle: 0 };
  let rd0 = queue_read(&lq0, 4);
  failed = failed + report(!rd0.is_ok, "sensors: queue_read on null queue -> explicit error");
  let s0 = Sensor{ handle: 0 };
  failed = failed + report(sensor_name(&s0) == "", "sensors: name on null sensor -> empty (error recorded)");
  return failed;
}

fn t_hwb_functional() -> Int {
  var failed: Int = 0;
  // Small-value sum (no bitwise ops on the flagship values; B-29 discipline).
  let usage = AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN + AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN;
  let supported = hwb_is_supported(64, 64, AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM, usage);
  failed = failed + report(supported, "hwb: 64x64 RGBA8 with CPU read/write isSupported");
  if !supported {
    return failed;
  }
  let a = hwb_alloc(64, 64, AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM, usage);
  if a.is_ok {
    let buf: HwbBuffer = a.value;
    failed = failed + report(hwb_width(&buf) == 64 && hwb_height(&buf) == 64,
      "hwb: describe 64x64 (got " + to_string(hwb_width(&buf)) + "x" + to_string(hwb_height(&buf)) + ")");
    failed = failed + report(hwb_format(&buf) == AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM,
      "hwb: describe format RGBA8");
    failed = failed + report(hwb_stride(&buf) >= 64 && hwb_layers(&buf) == 1,
      "hwb: stride >= 64 (got " + to_string(hwb_stride(&buf)) + "), layers = 1");
    failed = failed + report(hwb_write_pixel(&buf, 7, 5, 0x11223344), "hwb: write pixel (7,5)");
    let got = hwb_read_pixel(&buf, 7, 5);
    failed = failed + report(got == 0x11223344, "hwb: read pixel roundtrip (got " + to_string(got) + ")");
    hwb_release(buf);
    failed = failed + report(true, "hwb: released");
  } else {
    failed = failed + report(false, "hwb: allocate failed -- " + a.error.message);
  }
  return failed;
}

fn t_shm_functional() -> Int {
  var failed: Int = 0;
  let a = shm_create("xiom-shm-probe", 4096);
  if a.is_ok {
    let reg: ShmRegion = a.value;
    failed = failed + report(shm_get_size(&reg) == 4096,
      "shm: create 4096 bytes (got " + to_string(shm_get_size(&reg)) + ")");
    failed = failed + report(shm_set_prot(&reg, PROT_READ + PROT_WRITE), "shm: setProt READ|WRITE");
    failed = failed + report(shm_write_probe(&reg, 0x11223344), "shm: write probe at 0");
    let got = shm_read_probe(&reg);
    failed = failed + report(got == 0x11223344, "shm: read probe roundtrip (got " + to_string(got) + ")");
    failed = failed + report(shm_close(reg), "shm: closed");
  } else {
    failed = failed + report(false, "shm: create failed -- " + a.error.message);
  }
  return failed;
}

fn t_looper_functional() -> Int {
  var failed: Int = 0;
  let p = looper_prepare(true);
  if !p.is_ok {
    return report(false, "looper: prepare failed -- " + p.error.message);
  }
  let lp: Looper = p.value;
  failed = failed + report(looper_valid(&lp), "looper: prepared on this thread");
  let rt = looper_for_thread();
  failed = failed + report(rt.handle == lp.handle, "looper: forThread returns the prepared looper");

  let pipe = looper_pipe_open();
  if !pipe.is_ok {
    return failed + report(false, "looper: pipe open failed -- " + pipe.error.message);
  }
  let pp: LooperPipe = pipe.value;

  // NULL-callback ident variant (allowed by looper_prepare(true)).
  failed = failed + report(looper_add_fd_ident(&lp, pp.read_fd, 42, ALOOPER_EVENT_INPUT),
    "looper: addFd ident=42 (NULL callback)");
  failed = failed + report(looper_pipe_write(&pp, 0x5a), "looper: write 1 byte to the pipe");
  let ident = looper_poll_once(&lp, 1000);
  failed = failed + report(ident == 42, "looper: pollOnce returned ident 42 (got " + to_string(ident) + ")");
  failed = failed + report(looper_last_fd() == pp.read_fd,
    "looper: last fd == pipe read end (got " + to_string(looper_last_fd()) + ")");
  failed = failed + report(looper_last_events() == ALOOPER_EVENT_INPUT, "looper: last events == INPUT");
  let drained = looper_pipe_read(&pp);
  failed = failed + report(drained == 0x5a, "looper: drained the byte (got " + to_string(drained) + ")");
  failed = failed + report(looper_remove_fd(&lp, pp.read_fd) == 1, "looper: removeFd == 1");

  // Callback variant -- direct handoff of the top-level handler.
  looper_cb_calls = 0;
  looper_cb_fd = 0;
  looper_cb_events = 0;
  failed = failed + report(
    looper_add_fd(&lp, pp.read_fd, ALOOPER_POLL_CALLBACK, ALOOPER_EVENT_INPUT, on_looper_input),
    "looper: addFd with direct-handoff callback");
  failed = failed + report(looper_pipe_write(&pp, 0x33), "looper: write 1 byte for the callback");
  let cb_rc = looper_poll_once(&lp, 1000);
  failed = failed + report(cb_rc == ALOOPER_POLL_CALLBACK,
    "looper: pollOnce returned POLL_CALLBACK (got " + to_string(cb_rc) + ")");
  failed = failed + report(looper_cb_calls == 1, "looper: handler fired once (got " + to_string(looper_cb_calls) + ")");
  failed = failed + report(looper_cb_fd == pp.read_fd, "looper: handler fd matches");
  failed = failed + report(looper_cb_events == ALOOPER_EVENT_INPUT, "looper: handler events == INPUT");
  let drained2 = looper_pipe_read(&pp);
  failed = failed + report(drained2 == 0x33, "looper: drained the callback byte (got " + to_string(drained2) + ")");
  failed = failed + report(looper_remove_fd(&lp, pp.read_fd) == 1, "looper: removeFd (callback) == 1");

  // Empty looper -> timeout; wake -> POLL_WAKE.
  let to = looper_poll_once(&lp, 20);
  failed = failed + report(to == ALOOPER_POLL_TIMEOUT, "looper: pollOnce timeout (got " + to_string(to) + ")");
  failed = failed + report(looper_wake(&lp), "looper: wake issued");
  let woken = looper_poll_once(&lp, 0);
  failed = failed + report(woken == ALOOPER_POLL_WAKE, "looper: pollOnce after wake (got " + to_string(woken) + ")");

  // Legacy pollAll export smoke (nothing pending).
  let pa = looper_poll_all(&lp, 0);
  failed = failed + report(pa == ALOOPER_POLL_TIMEOUT, "looper: pollAll(0) timeout (got " + to_string(pa) + ")");

  looper_acquire(&lp);
  looper_release(&lp);
  failed = failed + report(true, "looper: acquire/release exercised");
  failed = failed + report(looper_pipe_close(pp), "looper: pipe closed");
  return failed;
}

fn t_config_functional() -> Int {
  var failed: Int = 0;
  let n = config_new();
  if !n.is_ok {
    return report(false, "config: new failed -- " + n.error.message);
  }
  let cfg: Config = n.value;
  failed = failed + report(cfg.handle != 0, "config: new handle");
  failed = failed + report(config_set_language(&cfg, "de"), "config: set language de");
  failed = failed + report(config_language(&cfg) == "de",
    "config: language roundtrip (got " + config_language(&cfg) + ")");
  failed = failed + report(config_set_country(&cfg, "DE"), "config: set country DE");
  failed = failed + report(config_country(&cfg) == "DE",
    "config: country roundtrip (got " + config_country(&cfg) + ")");
  failed = failed + report(config_set_orientation(&cfg, ACONFIGURATION_ORIENTATION_LAND),
    "config: set orientation LAND");
  failed = failed + report(config_orientation(&cfg) == ACONFIGURATION_ORIENTATION_LAND,
    "config: orientation roundtrip");
  failed = failed + report(config_set_density(&cfg, ACONFIGURATION_DENSITY_HIGH), "config: set density HIGH");
  failed = failed + report(config_density(&cfg) == ACONFIGURATION_DENSITY_HIGH, "config: density roundtrip");
  failed = failed + report(config_set_screen_size(&cfg, ACONFIGURATION_SCREENSIZE_NORMAL),
    "config: set screen size NORMAL");
  failed = failed + report(config_screen_size(&cfg) == ACONFIGURATION_SCREENSIZE_NORMAL,
    "config: screen size roundtrip");
  failed = failed + report(config_set_sdk_version(&cfg, 36), "config: set sdk 36");
  failed = failed + report(config_sdk_version(&cfg) == 36, "config: sdk roundtrip");
  failed = failed + report(config_screen_round(&cfg) >= 0, "config: screenRound getter responds");

  let fresh = config_new();
  if fresh.is_ok {
    let f: Config = fresh.value;
    // Expected diff of the populated config vs an all-unset one.  API-36
    // maps setScreenSize into SCREEN_LAYOUT's size bits (the legacy
    // screenSize member stays derived), so the screen-size witness rides
    // SCREEN_LAYOUT; summed (B-29 discipline: no bitwise ops here).
    let expected = ACONFIGURATION_LOCALE + ACONFIGURATION_ORIENTATION + ACONFIGURATION_DENSITY
      + ACONFIGURATION_SCREEN_LAYOUT + ACONFIGURATION_VERSION;
    let mask = config_diff(&cfg, &f);
    failed = failed + report(mask == expected,
      "config: diff mask == LOCALE|ORIENTATION|DENSITY|SCREEN_LAYOUT|VERSION (got " + to_string(mask) + ")");
    let copy = config_clone(&cfg);
    if copy.is_ok {
      let c: Config = copy.value;
      failed = failed + report(config_diff(&c, &cfg) == 0, "config: clone diff == 0");
      // match(base, requested): 0 when a value in `base` conflicts with
      // `requested` (NDK doc).  Verified matrix on API-36:
      // (copy,copy)=1 (copy,fresh)=0 (fresh,copy)=1 (fresh,fresh)=1.
      failed = failed + report(config_match(&f, &c), "config: match(fresh, clone) true");
      failed = failed + report(!config_match(&c, &f), "config: match(clone, fresh) false (unset requested)");
      let better = config_is_better_than(&f, &c, &f);
      failed = failed + report(better, "config: clone is better than fresh for fresh");
      failed = failed + report(config_delete(c), "config: clone deleted");
    } else {
      failed = failed + report(false, "config: clone failed -- " + copy.error.message);
    }
    failed = failed + report(config_delete(f), "config: fresh deleted");
  } else {
    failed = failed + report(false, "config: second new failed -- " + fresh.error.message);
  }
  failed = failed + report(config_delete(cfg), "config: deleted");
  return failed;
}

fn t_sensor_functional() -> Int {
  var failed: Int = 0;
  let m = manager();
  if !m.is_ok {
    return report(false, "sensors: manager failed -- " + m.error.message);
  }
  let mgr: SensorManager = m.value;
  failed = failed + report(manager_valid(&mgr), "sensors: manager instance");
  let list = manager_sensor_list(&mgr);
  if !list.is_ok {
    return failed + report(false, "sensors: list failed -- " + list.error.message);
  }
  let sensors: Vec[Sensor] = list.value;
  failed = failed + report(true, "sensors: enumerated " + to_string(sensors.len()) + " sensor(s)");
  if sensors.len() > 0 {
    let s0 = sensors[0];
    failed = failed + report(sensor_valid(&s0), "sensors: first sensor valid");
    let nm = sensor_name(&s0);
    failed = failed + report(nm.len() > 0, "sensors: first sensor named (" + nm + ")");
    let st = sensor_type(&s0);
    failed = failed + report(st >= 0, "sensors: first sensor type " + to_string(st));
    failed = failed + report(sensor_min_delay(&s0) >= 0,
      "sensors: first sensor min delay " + to_string(sensor_min_delay(&s0)));
    failed = failed + report(sensor_handle(&s0) >= 0,
      "sensors: first sensor handle " + to_string(sensor_handle(&s0)));
    let _is_wake = sensor_is_wake_up(&s0);
    failed = failed + report(true, "sensors: wake-up query responds");
  }
  // Default accelerometer: present on every emulator; a sensorless
  // device is a documented case, not a failure.
  let acc = manager_default_sensor(&mgr, ASENSOR_TYPE_ACCELEROMETER);
  if !sensor_valid(&acc) {
    return failed + report(true, "sensors: no accelerometer (no-sensor device; queue path skipped)");
  }
  failed = failed + report(true, "sensors: accelerometer present (type " + to_string(sensor_type(&acc)) + ")");

  // Event-queue roundtrip on the calling thread's looper.
  let lp = looper_prepare(true);
  if !lp.is_ok {
    return failed + report(false, "sensors: looper prepare failed -- " + lp.error.message);
  }
  let qr = manager_create_queue_ident(&mgr, &lp.value, 9);
  if !qr.is_ok {
    return failed + report(false, "sensors: create queue failed -- " + qr.error.message);
  }
  let q: SensorEventQueue = qr.value;
  failed = failed + report(queue_valid(&q), "sensors: queue created");
  failed = failed + report(queue_enable_sensor(&q, &acc), "sensors: enable accelerometer");
  var got: Int = 0;
  var ev_type: Int = -1;
  var ev_ts: Int = -1;
  var ev_mag: Float64 = 0.0;
  var tries: Int = 0;
  while tries < 30 && got == 0 {
    let rc = looper_poll_once(&lp.value, 100);
    if rc == 9 || queue_has_events(&q) == 1 {
      let rr = queue_read(&q, 8);
      if rr.is_ok {
        let batch: Vec[SensorEvent] = rr.value;
        got = batch.len();
        if got > 0 {
          let ev = batch[0];
          ev_type = event_type(&ev);
          ev_ts = event_timestamp(&ev);
          ev_mag = event_x(&ev) + event_y(&ev) + event_z(&ev);
        }
      }
    }
    tries = tries + 1;
  }
  failed = failed + report(got >= 1, "sensors: polled + read " + to_string(got) + " event(s)");
  if got >= 1 {
    failed = failed + report(ev_type == ASENSOR_TYPE_ACCELEROMETER,
      "sensors: event type accelerometer (got " + to_string(ev_type) + ")");
    failed = failed + report(ev_ts > 0, "sensors: event timestamp > 0");
    failed = failed + report(ev_mag < 1000.0 && ev_mag > -1000.0,
      "sensors: event payload sane (x+y+z = " + to_string(ev_mag) + ")");
  }
  failed = failed + report(queue_disable_sensor(&q, &acc), "sensors: disable accelerometer");
  failed = failed + report(manager_destroy_queue(&mgr, q), "sensors: queue destroyed");
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.android conformance tests (platform-core loader/probe) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: kinds + window/HWB formats + usage flags");
  failed = failed + report(t_a2_constants(), "constants: looper events/results + activity flags + config enums");
  failed = failed + report(t_a3_constants(), "constants: A3 event types/sources/key+motion enums + keycode table");
  failed = failed + report(t_a4_constants(), "constants: A4 sensor types/status/direct rates + limits");
  failed = failed + report(android_export_count() == 209,
    "export set: declared size 209 (got " + to_string(android_export_count()) + ")");

  // SKIP-path classification, deterministic on every host (bogus pair).
  let missing = android_probe_named("xiom-absent-libandroid-xyz.so", "xiom-absent-libnativewindow-xyz.so");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus pair unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == ANDROID_LOAD_ABSENT,
      "skip-path: absent pair classified as ANDROID_LOAD_ABSENT (SKIP)");
  }

  // Unloaded runtime: the A2 heads error explicitly (never a silent
  // zero handle).  Runs on Windows (SKIP leg) and on Android alike.
  let lp0 = looper_prepare(true);
  failed = failed + report(!lp0.is_ok, "looper: prepare without runtime -> explicit error");
  let c0 = config_new();
  failed = failed + report(!c0.is_ok, "config: new without runtime -> explicit error");
  failed = failed + t_a3a4_explicit_errors();

  // Default runtime probe.
  let p = android_probe();
  if p.is_ok {
    let rt: AndroidRuntime = p.value;
    failed = failed + report(rt.missing_exports == 0,
      "abi: declared export set fully resolved (" + to_string(rt.missing_exports) + " missing)");
    failed = failed + t_hwb_functional();
    failed = failed + t_shm_functional();
    failed = failed + t_looper_functional();
    failed = failed + t_config_functional();
    failed = failed + t_sensor_functional();
  } else {
    if p.error.kind == ANDROID_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- android runtime not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  // Unload must be safe even after a failed probe.
  android_unload();
  failed = failed + report(true, "loader: unload path exercised");

  if failed == 0 {
    io.println("xiom.android: all tests passed");
  } else {
    io.println("xiom.android: tests failed");
  }
  return failed;
}
