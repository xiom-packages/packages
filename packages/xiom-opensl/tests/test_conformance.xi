// xiom.opensl conformance suite -- legacy-audio (libOpenSLES.so +
// libOpenMAXAL.so + libamidi.so) loader/probe for the A6 tail.
//
// The probe never FAILs on a missing runtime:
//   present runtime -> 114-symbol export-set ABI check (3+53 OpenSL ES,
//                      3+41 OpenMAX AL, 14 AMidi) + functional engine
//                      lifecycle + interface-table probes
//   missing libs    -> OPENSL_LOAD_ABSENT (SKIP; exercised
//                      deterministically below with bogus sonames)
//   partial load or
//   broken exports  -> OPENSL_LOAD_ABI (FAIL -- never a silent SKIP)
//
// On Windows the runtime is absent by design -> SKIP (CI stays green).
// On an Android device/emulator the same suite runs the live path.
//
// Build+run through the runner (compiles src/opensl_bridge.c via
// port.args.json):
//   scripts/port.ps1 -Package xiom.opensl -TimeoutSec 300

module opensl_conformance

use xiom.io;
use xiom.opensl;

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
  if OPENSL_LOAD_ABSENT != 0 || OPENSL_LOAD_ABI != 1 { ok = false; }
  if OPENSL_LOADED_OPENSLES != 1 || OPENSL_LOADED_OPENMAXAL != 2 || OPENSL_LOADED_AMIDI != 4 { ok = false; }
  // SLresult family.
  if SL_RESULT_SUCCESS != 0 || SL_RESULT_PRECONDITIONS_VIOLATED != 1 { ok = false; }
  if SL_RESULT_PARAMETER_INVALID != 2 || SL_RESULT_MEMORY_FAILURE != 3 { ok = false; }
  if SL_RESULT_RESOURCE_ERROR != 4 || SL_RESULT_RESOURCE_LOST != 5 { ok = false; }
  if SL_RESULT_IO_ERROR != 6 || SL_RESULT_BUFFER_INSUFFICIENT != 7 { ok = false; }
  if SL_RESULT_CONTENT_CORRUPTED != 8 || SL_RESULT_CONTENT_UNSUPPORTED != 9 { ok = false; }
  if SL_RESULT_CONTENT_NOT_FOUND != 10 || SL_RESULT_PERMISSION_DENIED != 11 { ok = false; }
  if SL_RESULT_FEATURE_UNSUPPORTED != 12 || SL_RESULT_INTERNAL_ERROR != 13 { ok = false; }
  if SL_RESULT_UNKNOWN_ERROR != 14 || SL_RESULT_OPERATION_ABORTED != 15 { ok = false; }
  if SL_RESULT_CONTROL_LOST != 16 { ok = false; }
  // Key SL_* constants.
  if SL_BOOLEAN_FALSE != 0 || SL_BOOLEAN_TRUE != 1 { ok = false; }
  if SL_MILLIBEL_MAX != 32767 || SL_MILLIBEL_MIN != -32768 { ok = false; }
  if SL_MILLIHERTZ_MAX != 4294967295 { ok = false; }
  if SL_OBJECT_STATE_UNREALIZED != 1 || SL_OBJECT_STATE_REALIZED != 2 || SL_OBJECT_STATE_SUSPENDED != 3 { ok = false; }
  if SL_OBJECT_EVENT_RUNTIME_ERROR != 1 || SL_OBJECT_EVENT_ITF_PARAMETERS_CHANGED != 7 { ok = false; }
  if SL_OBJECTID_ENGINE != 0x1001 || SL_OBJECTID_METADATAEXTRACTOR != 0x100A { ok = false; }
  if SL_PLAYSTATE_STOPPED != 1 || SL_PLAYSTATE_PAUSED != 2 || SL_PLAYSTATE_PLAYING != 3 { ok = false; }
  if SL_PLAYEVENT_HEADATEND != 1 || SL_PLAYEVENT_HEADSTALLED != 0x10 { ok = false; }
  if SL_TIME_UNKNOWN != 4294967295 { ok = false; }
  if SL_PREFETCHSTATUS_UNDERFLOW != 1 || SL_PREFETCHSTATUS_OVERFLOW != 3 { ok = false; }
  if SL_SEEKMODE_FAST != 1 || SL_SEEKMODE_ACCURATE != 2 { ok = false; }
  if SL_DEFAULTDEVICEID_AUDIOINPUT != 4294967295 || SL_DEFAULTDEVICEID_AUDIOOUTPUT != 4294967294 { ok = false; }
  if SL_DATALOCATOR_URI != 1 || SL_DATALOCATOR_MIDIBUFFERQUEUE != 7 { ok = false; }
  if SL_DATAFORMAT_MIME != 1 || SL_DATAFORMAT_PCM != 2 { ok = false; }
  if SL_BYTEORDER_LITTLEENDIAN != 2 { ok = false; }
  if SL_SAMPLINGRATE_44_1 != 44100000 || SL_SAMPLINGRATE_48 != 48000000 { ok = false; }
  if SL_PCMSAMPLEFORMAT_FIXED_16 != 16 || SL_SPEAKER_FRONT_LEFT != 1 { ok = false; }
  if SL_PRIORITY_LOWEST != -2147483648 || SL_PRIORITY_HIGHEST != 2147483647 { ok = false; }
  // Android extensions.
  if SL_ANDROID_PCM_REPRESENTATION_SIGNED_INT != 1 || SL_ANDROID_PCM_REPRESENTATION_FLOAT != 3 { ok = false; }
  if SL_ANDROID_DATAFORMAT_PCM_EX != 4 || SL_ANDROID_SPEAKER_NON_POSITIONAL != 2147483648 { ok = false; }
  if SL_ANDROID_JAVA_PROXY_ROUTING != 1 { ok = false; }
  if SL_ANDROID_ITEMKEY_EOS != 1 || SL_ANDROID_ITEMKEY_FORMAT_CHANGE != 4 { ok = false; }
  if SL_ANDROIDBUFFERQUEUEEVENT_PROCESSED != 1 { ok = false; }
  if SL_DATALOCATOR_ANDROIDFD != 0x800007BC || SL_DATALOCATOR_ANDROIDSIMPLEBUFFERQUEUE != 0x800007BD { ok = false; }
  if SL_DATALOCATOR_ANDROIDBUFFERQUEUE != 0x800007BE { ok = false; }
  if SL_ANDROID_RECORDING_PRESET_GENERIC != 1 || SL_ANDROID_RECORDING_PRESET_UNPROCESSED != 5 { ok = false; }
  if SL_ANDROID_STREAM_VOICE != 0 || SL_ANDROID_STREAM_MEDIA != 3 || SL_ANDROID_STREAM_NOTIFICATION != 5 { ok = false; }
  if SL_ANDROID_PERFORMANCE_LATENCY != 1 || SL_ANDROID_PERFORMANCE_POWER_SAVING != 3 { ok = false; }
  // OpenMAX AL.
  if XA_RESULT_SUCCESS != 0 || XA_RESULT_CONTROL_LOST != 16 { ok = false; }
  if XA_BOOLEAN_FALSE != 0 || XA_BOOLEAN_TRUE != 1 || XA_MILLIBEL_MIN != -32768 { ok = false; }
  if XA_OBJECT_STATE_REALIZED != 2 || XA_OBJECT_EVENT_ITF_CONTROL_RETURNED != 6 { ok = false; }
  if XA_OBJECTID_ENGINE != 1 || XA_OBJECTID_CAMERADEVICE != 9 { ok = false; }
  if XA_PLAYSTATE_PLAYING != 3 || XA_PLAYEVENT_HEADMOVING != 8 { ok = false; }
  if XA_TIME_UNKNOWN != 4294967295 { ok = false; }
  if XA_DEFAULTDEVICEID_CAMERA != 4294967291 { ok = false; }
  if XA_DATAFORMAT_RAWIMAGE != 3 || XA_DATALOCATOR_NATIVEDISPLAY != 5 { ok = false; }
  if XA_ENGINEOPTION_THREADSAFE != 1 || XA_ENGINEOPTION_LOSSOFCONTROL != 2 { ok = false; }
  if XA_IODEVICE_RADIO != 5 || XA_SAMPLINGRATE_48 != 48000000 { ok = false; }
  // AMidi.
  if AMIDI_OPCODE_DATA != 1 || AMIDI_OPCODE_FLUSH != 2 { ok = false; }
  if AMIDI_DEVICE_TYPE_USB != 1 || AMIDI_DEVICE_TYPE_BLUETOOTH != 3 { ok = false; }
  if AMIDI_DEVICE_PROTOCOL_UMP_USE_MIDI_CI != 0 || AMIDI_DEVICE_PROTOCOL_UMP_MIDI_2_0 != 17 { ok = false; }
  if AMIDI_DEVICE_PROTOCOL_UNKNOWN != -1 { ok = false; }
  if AMEDIA_OK != 0 || AMEDIA_ERROR_UNKNOWN != -10000 || AMEDIA_ERROR_INVALID_PARAMETER != -10004 { ok = false; }
  return ok;
}

fn t_engine_functional() -> Int {
  var failed: Int = 0;
  let lifecycle = sl_engine_lifecycle();
  failed = failed + report(lifecycle == 0,
    "sl: engine lifecycle create/realize/destroy (rc " + to_string(lifecycle) + ")");
  let state = sl_engine_last_state();
  failed = failed + report(state == SL_OBJECT_STATE_REALIZED,
    "sl: engine state after Realize = SL_OBJECT_STATE_REALIZED (got " + to_string(state) + ")");
  let nulls = sl_iid_null_values();
  failed = failed + report(nulls == 0,
    "sl: SL_IID_* globals all live (null values " + to_string(nulls) + ")");
  let num = sl_query_num_engine_interfaces();
  failed = failed + report(num >= 0,
    "sl: slQueryNumSupportedEngineInterfaces = " + to_string(num));
  let ok = sl_query_engine_interfaces_ok();
  failed = failed + report(ok == num && ok >= 0,
    "sl: slQuerySupportedEngineInterfaces non-null IIDs " + to_string(ok) + "/" + to_string(num));
  return failed;
}

fn t_amidi_verdict() -> Int {
  var failed: Int = 0;
  let present = amidi_get_device_info_present();
  let count = amidi_device_count_attempt();
  if present {
    // Present but beyond the r27b oracle: the recorded verdict is -2
    // (ABI unverified) -- still a deterministic, non-silent outcome.
    failed = failed + report(count == -2 || count >= 0,
      "amidi: AMidi_getDeviceInfo present, count attempt verdict " + to_string(count));
  } else {
    failed = failed + report(count == -1,
      "amidi: AMidi_getDeviceInfo absent (r27b oracle: 14 core fns; JNI-only devices), count attempt verdict " + to_string(count));
  }
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.opensl conformance tests (legacy-audio loader/probe) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: SL_RESULT/SL_*/SL_ANDROID_*/XA_*/AMIDI_*");

  // SKIP-path classification, deterministic on every host (bogus trio).
  let missing = opensl_probe_named("xiom-absent-libopensles-xyz.so", "xiom-absent-libopenmaxal-xyz.so", "xiom-absent-libamidi-xyz.so");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus trio unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == OPENSL_LOAD_ABSENT,
      "skip-path: absent trio classified as OPENSL_LOAD_ABSENT (SKIP)");
  }

  // Default runtime probe.
  let p = opensl_probe();
  if p.is_ok {
    let rt: OpenSlRuntime = p.value;
    failed = failed + report(rt.sl_missing == 0,
      "abi: OpenSLES export set resolved (missing " + to_string(rt.sl_missing) + " of 56)");
    failed = failed + report(rt.xa_missing == 0,
      "abi: OpenMAXAL export set resolved (missing " + to_string(rt.xa_missing) + " of 44)");
    failed = failed + report(rt.amidi_missing == 0,
      "abi: AMidi export set resolved (missing " + to_string(rt.amidi_missing) + " of 14)");
    failed = failed + report(rt.loaded_mask == 7,
      "abi: all three runtimes loaded (mask " + to_string(rt.loaded_mask) + ")");
    failed = failed + t_engine_functional();
    failed = failed + t_amidi_verdict();
  } else {
    if p.error.kind == OPENSL_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- legacy-audio runtime not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  // Unload must be safe even after a failed probe.
  opensl_unload();
  failed = failed + report(true, "loader: unload path exercised");

  if failed == 0 {
    io.println("xiom.opensl: all tests passed");
  } else {
    io.println("xiom.opensl: tests failed");
  }
  return failed;
}
