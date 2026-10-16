// xiom.aaudio conformance suite -- libaaudio.so loader/probe for the A6
// AAudio head (aaudio/AAudio.h, NDK r27b).
//
// The probe never FAILs on a missing runtime:
//   present runtime -> export-set ABI check + builder lifecycle + an open
//                      attempt (a typed open failure is a recorded outcome,
//                      never a hard FAIL -- emulators often run -no-audio)
//   missing lib     -> AAUDIO_LOAD_ABSENT (SKIP; exercised deterministically
//                      below with a bogus soname)
//   broken install  -> AAUDIO_LOAD_ABI (FAIL -- never a silent SKIP)
//
// On Windows the runtime is absent by design -> SKIP (CI stays green).
// On an Android device/emulator the same suite runs the live path.
//
// Build+run through the runner (compiles src/aaudio_bridge.c via
// port.args.json):
//   scripts/port.ps1 -Package xiom.aaudio

module aaudio_conformance

use xiom.io;
use xiom.aaudio;

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

fn t_classification() -> Bool {
  var ok = true;
  if AAUDIO_LOAD_ABSENT != 0 || AAUDIO_LOAD_ABI != 1 { ok = false; }
  if AAUDIO_UNSPECIFIED != 0 { ok = false; }
  if AAUDIO_OK != 0 { ok = false; }
  return ok;
}

fn t_direction_format() -> Bool {
  var ok = true;
  if AAUDIO_DIRECTION_OUTPUT != 0 || AAUDIO_DIRECTION_INPUT != 1 { ok = false; }
  if AAUDIO_FORMAT_INVALID != -1 || AAUDIO_FORMAT_UNSPECIFIED != 0 { ok = false; }
  if AAUDIO_FORMAT_PCM_I16 != 1 || AAUDIO_FORMAT_PCM_FLOAT != 2 { ok = false; }
  if AAUDIO_FORMAT_PCM_I24_PACKED != 3 || AAUDIO_FORMAT_PCM_I32 != 4 { ok = false; }
  if AAUDIO_FORMAT_IEC61937 != 5 { ok = false; }
  return ok;
}

fn t_results() -> Bool {
  var ok = true;
  if AAUDIO_ERROR_BASE != -900 || AAUDIO_ERROR_DISCONNECTED != -899 { ok = false; }
  if AAUDIO_ERROR_ILLEGAL_ARGUMENT != -898 || AAUDIO_ERROR_INTERNAL != -896 { ok = false; }
  if AAUDIO_ERROR_INVALID_STATE != -895 || AAUDIO_ERROR_INVALID_HANDLE != -892 { ok = false; }
  if AAUDIO_ERROR_UNIMPLEMENTED != -890 || AAUDIO_ERROR_UNAVAILABLE != -889 { ok = false; }
  if AAUDIO_ERROR_NO_FREE_HANDLES != -888 || AAUDIO_ERROR_NO_MEMORY != -887 { ok = false; }
  if AAUDIO_ERROR_NULL != -886 || AAUDIO_ERROR_TIMEOUT != -885 { ok = false; }
  if AAUDIO_ERROR_WOULD_BLOCK != -884 || AAUDIO_ERROR_INVALID_FORMAT != -883 { ok = false; }
  if AAUDIO_ERROR_OUT_OF_RANGE != -882 || AAUDIO_ERROR_NO_SERVICE != -881 { ok = false; }
  if AAUDIO_ERROR_INVALID_RATE != -880 { ok = false; }
  return ok;
}

fn t_stream_states() -> Bool {
  var ok = true;
  if AAUDIO_STREAM_STATE_UNINITIALIZED != 0 || AAUDIO_STREAM_STATE_UNKNOWN != 1 { ok = false; }
  if AAUDIO_STREAM_STATE_OPEN != 2 || AAUDIO_STREAM_STATE_STARTING != 3 { ok = false; }
  if AAUDIO_STREAM_STATE_STARTED != 4 || AAUDIO_STREAM_STATE_PAUSING != 5 { ok = false; }
  if AAUDIO_STREAM_STATE_PAUSED != 6 || AAUDIO_STREAM_STATE_FLUSHING != 7 { ok = false; }
  if AAUDIO_STREAM_STATE_FLUSHED != 8 || AAUDIO_STREAM_STATE_STOPPING != 9 { ok = false; }
  if AAUDIO_STREAM_STATE_STOPPED != 10 || AAUDIO_STREAM_STATE_CLOSING != 11 { ok = false; }
  if AAUDIO_STREAM_STATE_CLOSED != 12 || AAUDIO_STREAM_STATE_DISCONNECTED != 13 { ok = false; }
  return ok;
}

fn t_sharing_performance() -> Bool {
  var ok = true;
  if AAUDIO_SHARING_MODE_EXCLUSIVE != 0 || AAUDIO_SHARING_MODE_SHARED != 1 { ok = false; }
  if AAUDIO_PERFORMANCE_MODE_NONE != 10 { ok = false; }
  if AAUDIO_PERFORMANCE_MODE_POWER_SAVING != 11 || AAUDIO_PERFORMANCE_MODE_LOW_LATENCY != 12 { ok = false; }
  return ok;
}

fn t_usage_content() -> Bool {
  var ok = true;
  if AAUDIO_SYSTEM_USAGE_OFFSET != 1000 { ok = false; }
  if AAUDIO_USAGE_MEDIA != 1 || AAUDIO_USAGE_VOICE_COMMUNICATION != 2 { ok = false; }
  if AAUDIO_USAGE_VOICE_COMMUNICATION_SIGNALLING != 3 || AAUDIO_USAGE_ALARM != 4 { ok = false; }
  if AAUDIO_USAGE_NOTIFICATION != 5 || AAUDIO_USAGE_NOTIFICATION_RINGTONE != 6 { ok = false; }
  if AAUDIO_USAGE_NOTIFICATION_EVENT != 10 || AAUDIO_USAGE_ASSISTANCE_ACCESSIBILITY != 11 { ok = false; }
  if AAUDIO_USAGE_ASSISTANCE_NAVIGATION_GUIDANCE != 12 { ok = false; }
  if AAUDIO_USAGE_ASSISTANCE_SONIFICATION != 13 || AAUDIO_USAGE_GAME != 14 { ok = false; }
  if AAUDIO_USAGE_ASSISTANT != 16 { ok = false; }
  if AAUDIO_SYSTEM_USAGE_EMERGENCY != 1000 || AAUDIO_SYSTEM_USAGE_SAFETY != 1001 { ok = false; }
  if AAUDIO_SYSTEM_USAGE_VEHICLE_STATUS != 1002 || AAUDIO_SYSTEM_USAGE_ANNOUNCEMENT != 1003 { ok = false; }
  if AAUDIO_CONTENT_TYPE_SPEECH != 1 || AAUDIO_CONTENT_TYPE_MUSIC != 2 { ok = false; }
  if AAUDIO_CONTENT_TYPE_MOVIE != 3 || AAUDIO_CONTENT_TYPE_SONIFICATION != 4 { ok = false; }
  if AAUDIO_SPATIALIZATION_BEHAVIOR_AUTO != 1 || AAUDIO_SPATIALIZATION_BEHAVIOR_NEVER != 2 { ok = false; }
  return ok;
}

fn t_presets_capture() -> Bool {
  var ok = true;
  if AAUDIO_INPUT_PRESET_GENERIC != 1 || AAUDIO_INPUT_PRESET_CAMCORDER != 5 { ok = false; }
  if AAUDIO_INPUT_PRESET_VOICE_RECOGNITION != 6 || AAUDIO_INPUT_PRESET_VOICE_COMMUNICATION != 7 { ok = false; }
  if AAUDIO_INPUT_PRESET_UNPROCESSED != 9 || AAUDIO_INPUT_PRESET_VOICE_PERFORMANCE != 10 { ok = false; }
  if AAUDIO_INPUT_PRESET_SYSTEM_ECHO_REFERENCE != 1997 { ok = false; }
  if AAUDIO_INPUT_PRESET_SYSTEM_HOTWORD != 1999 { ok = false; }
  if AAUDIO_ALLOW_CAPTURE_BY_ALL != 1 || AAUDIO_ALLOW_CAPTURE_BY_SYSTEM != 2 { ok = false; }
  if AAUDIO_ALLOW_CAPTURE_BY_NONE != 3 { ok = false; }
  if AAUDIO_SESSION_ID_NONE != -1 || AAUDIO_SESSION_ID_ALLOCATE != 0 { ok = false; }
  if AAUDIO_CALLBACK_RESULT_CONTINUE != 0 || AAUDIO_CALLBACK_RESULT_STOP != 1 { ok = false; }
  return ok;
}

fn t_channel_bits() -> Bool {
  var ok = true;
  if AAUDIO_CHANNEL_INVALID != -1 { ok = false; }
  if AAUDIO_CHANNEL_FRONT_LEFT != 1 || AAUDIO_CHANNEL_FRONT_RIGHT != 2 { ok = false; }
  if AAUDIO_CHANNEL_FRONT_CENTER != 4 || AAUDIO_CHANNEL_LOW_FREQUENCY != 8 { ok = false; }
  if AAUDIO_CHANNEL_BACK_LEFT != 16 || AAUDIO_CHANNEL_BACK_RIGHT != 32 { ok = false; }
  if AAUDIO_CHANNEL_FRONT_LEFT_OF_CENTER != 64 { ok = false; }
  if AAUDIO_CHANNEL_FRONT_RIGHT_OF_CENTER != 128 || AAUDIO_CHANNEL_BACK_CENTER != 256 { ok = false; }
  if AAUDIO_CHANNEL_SIDE_LEFT != 512 || AAUDIO_CHANNEL_SIDE_RIGHT != 1024 { ok = false; }
  if AAUDIO_CHANNEL_TOP_CENTER != 2048 { ok = false; }
  if AAUDIO_CHANNEL_TOP_FRONT_LEFT != 4096 || AAUDIO_CHANNEL_TOP_FRONT_CENTER != 8192 { ok = false; }
  if AAUDIO_CHANNEL_TOP_FRONT_RIGHT != 16384 || AAUDIO_CHANNEL_TOP_BACK_LEFT != 32768 { ok = false; }
  if AAUDIO_CHANNEL_TOP_BACK_CENTER != 65536 || AAUDIO_CHANNEL_TOP_BACK_RIGHT != 131072 { ok = false; }
  if AAUDIO_CHANNEL_TOP_SIDE_LEFT != 262144 || AAUDIO_CHANNEL_TOP_SIDE_RIGHT != 524288 { ok = false; }
  if AAUDIO_CHANNEL_BOTTOM_FRONT_LEFT != 1048576 { ok = false; }
  if AAUDIO_CHANNEL_BOTTOM_FRONT_CENTER != 2097152 { ok = false; }
  if AAUDIO_CHANNEL_BOTTOM_FRONT_RIGHT != 4194304 { ok = false; }
  if AAUDIO_CHANNEL_LOW_FREQUENCY_2 != 8388608 { ok = false; }
  if AAUDIO_CHANNEL_FRONT_WIDE_LEFT != 16777216 || AAUDIO_CHANNEL_FRONT_WIDE_RIGHT != 33554432 { ok = false; }
  return ok;
}

fn t_channel_combos() -> Bool {
  var ok = true;
  if AAUDIO_CHANNEL_MONO != 1 || AAUDIO_CHANNEL_STEREO != 3 { ok = false; }
  if AAUDIO_CHANNEL_2POINT1 != 11 || AAUDIO_CHANNEL_TRI != 7 || AAUDIO_CHANNEL_TRI_BACK != 259 { ok = false; }
  if AAUDIO_CHANNEL_3POINT1 != 15 { ok = false; }
  if AAUDIO_CHANNEL_2POINT0POINT2 != 786435 || AAUDIO_CHANNEL_2POINT1POINT2 != 786443 { ok = false; }
  if AAUDIO_CHANNEL_3POINT0POINT2 != 786439 || AAUDIO_CHANNEL_3POINT1POINT2 != 786447 { ok = false; }
  if AAUDIO_CHANNEL_QUAD != 51 || AAUDIO_CHANNEL_QUAD_SIDE != 1539 { ok = false; }
  if AAUDIO_CHANNEL_SURROUND != 263 || AAUDIO_CHANNEL_PENTA != 55 { ok = false; }
  if AAUDIO_CHANNEL_5POINT1 != 63 || AAUDIO_CHANNEL_5POINT1_SIDE != 1551 { ok = false; }
  if AAUDIO_CHANNEL_6POINT1 != 319 || AAUDIO_CHANNEL_7POINT1 != 1599 { ok = false; }
  if AAUDIO_CHANNEL_5POINT1POINT2 != 786495 || AAUDIO_CHANNEL_5POINT1POINT4 != 184383 { ok = false; }
  if AAUDIO_CHANNEL_7POINT1POINT2 != 788031 || AAUDIO_CHANNEL_7POINT1POINT4 != 185919 { ok = false; }
  if AAUDIO_CHANNEL_9POINT1POINT4 != 50517567 || AAUDIO_CHANNEL_9POINT1POINT6 != 51303999 { ok = false; }
  if AAUDIO_CHANNEL_FRONT_BACK != 260 { ok = false; }
  if AAUDIO_CLOCK_MONOTONIC != 1 || AAUDIO_CLOCK_BOOTTIME != 7 { ok = false; }
  return ok;
}

fn t_live_builder() -> Int {
  var failed: Int = 0;
  let b = builder_create();
  if !b.is_ok {
    failed = failed + report(false, "live: builder_create failed -- " + b.error.message);
    return failed;
  }
  let builder: StreamBuilder = b.value;
  builder_set_direction(&builder, AAUDIO_DIRECTION_OUTPUT);
  builder_set_performance_mode(&builder, AAUDIO_PERFORMANCE_MODE_NONE);
  builder_set_format(&builder, AAUDIO_FORMAT_PCM_I16);
  builder_set_channel_count(&builder, 2);
  builder_set_sample_rate(&builder, 48000);
  builder_set_sharing_mode(&builder, AAUDIO_SHARING_MODE_SHARED);
  builder_set_buffer_capacity_in_frames(&builder, 192);
  builder_set_data_callback(&builder);
  builder_set_error_callback(&builder);
  failed = failed + report(true, "live: builder created + configured (OUTPUT/NONE/PCM_I16/2ch/48000/SHARED)");

  let o = builder_open_stream(&builder);
  if o.is_ok {
    let stream: AaudioStream = o.value;
    let rc_start = stream_request_start(&stream);
    failed = failed + report(rc_start == AAUDIO_OK || rc_start == AAUDIO_ERROR_UNIMPLEMENTED,
      "live: open OK -> requestStart rc=" + to_string(rc_start) + " (" + result_to_text(rc_start) + ")");
    let rc_close = stream_close(stream);
    failed = failed + report(rc_close == AAUDIO_OK,
      "live: close rc=" + to_string(rc_close) + " (" + result_to_text(rc_close) + ")");
  } else {
    // A typed open failure is a recorded outcome (emulator -no-audio).
    failed = failed + report(true, "live: open attempt recorded a typed outcome: " +
      result_to_text(open_result()) + " (" + o.error.message + ")");
  }
  let rc_delete = builder_delete(builder);
  failed = failed + report(rc_delete == AAUDIO_OK,
    "live: builder delete rc=" + to_string(rc_delete) + " (" + result_to_text(rc_delete) + ")");
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.aaudio conformance tests (libaaudio loader/probe) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_classification(), "constants: classification kinds + unspecified + OK");
  failed = failed + report(t_direction_format(), "constants: direction + format family");
  failed = failed + report(t_results(), "constants: AAUDIO_OK + AAUDIO_ERROR_* family");
  failed = failed + report(t_stream_states(), "constants: stream states");
  failed = failed + report(t_sharing_performance(), "constants: sharing + performance modes");
  failed = failed + report(t_usage_content(), "constants: usage + content type + spatialization");
  failed = failed + report(t_presets_capture(), "constants: input presets + capture + session + callback result");
  failed = failed + report(t_channel_bits(), "constants: channel mask bits");
  failed = failed + report(t_channel_combos(), "constants: channel mask combinations + clock ids");

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = aaudio_probe_named("xiom-absent-libaaudio-xyz.so");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == AAUDIO_LOAD_ABSENT,
      "skip-path: absent soname classified as AAUDIO_LOAD_ABSENT (SKIP)");
  }

  // Default runtime probe.
  let p = aaudio_probe();
  if p.is_ok {
    let rt: AaudioRuntime = p.value;
    failed = failed + report(rt.missing_exports == 0,
      "abi: declared export set fully resolved (" + to_string(rt.missing_exports) + " missing)");
    failed = failed + report(result_to_text(AAUDIO_OK) == "AAUDIO_OK",
      "convert: result_to_text(AAUDIO_OK) = " + result_to_text(AAUDIO_OK));
    failed = failed + t_live_builder();
  } else {
    if p.error.kind == AAUDIO_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- aaudio runtime not present (" + p.error.message + ")");
      // Functional surface must degrade gracefully, not crash, with no runtime.
      let b = builder_create();
      if b.is_ok {
        failed = failed + report(false, "guard: builder_create unexpectedly succeeded without a runtime");
        builder_delete(b.value);
      } else {
        failed = failed + report(b.error.kind == AAUDIO_LOAD_ABSENT,
          "guard: builder_create without a runtime -> typed ABSENT error (no crash)");
      }
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  // Unload must be safe even after a failed probe.
  aaudio_unload();
  failed = failed + report(true, "loader: unload path exercised");

  if failed == 0 {
    io.println("xiom.aaudio: all tests passed");
  } else {
    io.println("xiom.aaudio: tests failed");
  }
  return failed;
}
