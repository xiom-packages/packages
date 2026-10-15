// xiom.camera2ndk conformance suite -- libcamera2ndk.so loader/probe for
// the A8 camera head (camera2 NDK).
//
// The probe never FAILs on a missing runtime:
//   present runtime -> export-set ABI check + functional ACameraManager
//                      create/getCameraIdList/delete (typed ACAMERA_ERROR_*
//                      from a shell context is a non-fatal recorded outcome)
//   missing lib     -> CAMERA2_LOAD_ABSENT (SKIP; exercised
//                      deterministically below with a bogus soname)
//   broken install  -> CAMERA2_LOAD_ABI (FAIL -- never a silent SKIP)
//
// On Windows the runtime is absent by design -> SKIP (CI stays green).
// On an Android device/emulator the same suite runs the live path.
//
// Build+run through the runner (compiles src/camera2ndk_bridge.c via
// port.args.json):
//   scripts/port.ps1 -Package xiom.camera2ndk

module camera2ndk_conformance

use xiom.io;
use xiom.camera2ndk;

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
  if CAMERA2_LOAD_ABSENT != 0 || CAMERA2_LOAD_ABI != 1 { ok = false; }
  // ACameraManager status codes (NdkCameraError.h).
  if ACAMERA_OK != 0 { ok = false; }
  if ACAMERA_ERROR_BASE != -10000 || ACAMERA_ERROR_UNKNOWN != -10000 { ok = false; }
  if ACAMERA_ERROR_INVALID_PARAMETER != -10001 || ACAMERA_ERROR_CAMERA_DISCONNECTED != -10002 { ok = false; }
  if ACAMERA_ERROR_CAMERA_SERVICE != -10006 || ACAMERA_ERROR_SESSION_CLOSED != -10007 { ok = false; }
  if ACAMERA_ERROR_MAX_CAMERA_IN_USE != -10011 || ACAMERA_ERROR_PERMISSION_DENIED != -10013 { ok = false; }
  if ACAMERA_ERROR_UNSUPPORTED_OPERATION != -10014 { ok = false; }
  // Metadata entry types.
  if ACAMERA_TYPE_BYTE != 0 || ACAMERA_TYPE_INT32 != 1 || ACAMERA_TYPE_FLOAT != 2 { ok = false; }
  if ACAMERA_TYPE_INT64 != 3 || ACAMERA_TYPE_DOUBLE != 4 || ACAMERA_TYPE_RATIONAL != 5 { ok = false; }
  if ACAMERA_NUM_TYPES != 6 { ok = false; }
  // Device error-state codes + request templates.
  if ERROR_CAMERA_IN_USE != 1 || ERROR_CAMERA_SERVICE != 5 { ok = false; }
  if TEMPLATE_PREVIEW != 1 || TEMPLATE_STILL_CAPTURE != 2 || TEMPLATE_RECORD != 3 { ok = false; }
  if TEMPLATE_VIDEO_SNAPSHOT != 4 || TEMPLATE_ZERO_SHUTTER_LAG != 5 || TEMPLATE_MANUAL != 6 { ok = false; }
  // Capture session enums.
  if CAPTURE_FAILURE_REASON_FLUSHED != 0 || CAPTURE_FAILURE_REASON_ERROR != 1 { ok = false; }
  if CAPTURE_SEQUENCE_ID_NONE != -1 { ok = false; }
  // Tag spot checks: section << 16 | index.
  if ACAMERA_LENS_FACING != 0x00080005 { ok = false; }
  if ACAMERA_LENS_FACING_FRONT != 0 || ACAMERA_LENS_FACING_BACK != 1 || ACAMERA_LENS_FACING_EXTERNAL != 2 { ok = false; }
  if ACAMERA_CONTROL_CAPTURE_INTENT != 0x0001000D { ok = false; }
  if ACAMERA_CONTROL_CAPTURE_INTENT_PREVIEW != 1 || ACAMERA_CONTROL_CAPTURE_INTENT_STILL_CAPTURE != 2 { ok = false; }
  if ACAMERA_CONTROL_CAPTURE_INTENT_VIDEO_RECORD != 3 || ACAMERA_CONTROL_CAPTURE_INTENT_MANUAL != 6 { ok = false; }
  if ACAMERA_SENSOR_EXPOSURE_TIME != 0x000E0000 || ACAMERA_SENSOR_TIMESTAMP != 0x000E0010 { ok = false; }
  if ACAMERA_SCALER_CROP_REGION != 0x000D0000 { ok = false; }
  if ACAMERA_REQUEST_AVAILABLE_CAPABILITIES != 0x000C000C { ok = false; }
  if ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL != 0x00150000 { ok = false; }
  if ACAMERA_STATISTICS_FACE_DETECT_MODE != 0x00110000 { ok = false; }
  // camera_status_name mapping.
  if camera_status_name(ACAMERA_ERROR_CAMERA_SERVICE) != "ACAMERA_ERROR_CAMERA_SERVICE" { ok = false; }
  if camera_status_name(ACAMERA_ERROR_UNSUPPORTED_OPERATION) != "ACAMERA_ERROR_UNSUPPORTED_OPERATION" { ok = false; }
  return ok;
}

fn t_manager_functional() -> Int {
  var failed: Int = 0;
  let m = camera_manager_create();
  if !m.is_ok {
    return report(false, "manager: create failed -- " + m.error.message);
  }
  let mgr: CameraManager = m.value;
  failed = failed + report(true, "manager: create");
  let r = camera_manager_camera_ids(&mgr);
  if r.is_ok {
    let ids: Vec[Str] = r.value;
    failed = failed + report(true, "manager: getCameraIdList ok (camera_count=" + to_string(ids.len()) + ")");
    var i = 0;
    while i < ids.len() {
      io.println("    camera_id[" + to_string(i) + "]=" + ids[i]);
      io.flush_stdout();
      i = i + 1;
    }
  } else {
    // A typed negative ACAMERA_ERROR_* here is honest evidence, not a
    // package failure: a shell process may not reach the camera service.
    let code = r.error.code;
    failed = failed + report(code <= ACAMERA_ERROR_BASE,
      "manager: getCameraIdList typed " + r.error.name + " (non-fatal; device-service availability)");
  }
  camera_manager_delete(mgr);
  failed = failed + report(true, "manager: deleted");
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.camera2ndk conformance tests (libcamera2ndk.so loader/probe) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: kinds + ACAMERA_* statuses + tags + templates");
  failed = failed + report(camera2_declared_exports() == 70,
    "declared: export set size 70 (got " + to_string(camera2_declared_exports()) + ")");

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = camera2_probe_named("xiom-absent-libcamera2ndk-xyz.so");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == CAMERA2_LOAD_ABSENT,
      "skip-path: absent lib classified as CAMERA2_LOAD_ABSENT (SKIP)");
  }

  // Default runtime probe.
  let p = camera2_probe();
  if p.is_ok {
    let rt: Camera2Runtime = p.value;
    failed = failed + report(rt.missing_exports == 0,
      "abi: declared export set fully resolved (" + to_string(rt.missing_exports) + " missing of "
        + to_string(rt.export_count) + ")");
    failed = failed + t_manager_functional();
  } else {
    if p.error.kind == CAMERA2_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- camera runtime not present (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  // Unload must be safe even after a failed probe (and after a manager
  // was deleted above).
  camera2_unload();
  failed = failed + report(true, "loader: unload path exercised");

  if failed == 0 {
    io.println("xiom.camera2ndk: all tests passed");
  } else {
    io.println("xiom.camera2ndk: tests failed");
  }
  return failed;
}
