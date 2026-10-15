// XIOM -- xiom.camera2ndk: Android camera2 NDK bindings (NDK r27b).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: runtime probe + functional manager head for the A8 camera slice
// of the Android SDK100 program (docs/ANDROID-SDK100.md), backed by the
// small vendored bridge `src/camera2ndk_bridge.c` (compiled with
// `--c-source`; see port.args.json).  The bridge resolves
// `libcamera2ndk.so` at RUNTIME (dlopen on Android/Linux, LoadLibraryA on
// Windows -- where everything classifies ABSENT) and verifies the
// declared export set of the camera2 NDK headers:
//
//   ACameraManager_*               (10 exports; create/delete +
//                                   camera-id list + characteristics +
//                                   openCamera + availability callbacks)
//   ACameraDevice_* / ACaptureSessionOutput*  (17 exports)
//   ACameraCaptureSession_* / ACaptureSessionSharedOutput* /
//   ACaptureSessionPhysicalOutput* (15 exports)
//   ACaptureRequest_* / ACameraOutputTarget_* (23 exports)
//   ACameraMetadata_*              (5 exports; fromCameraMetadata is the
//                                   JNI route -> A11 exclusion)
//
// Classification (the suite maps it to markers):
//   CAMERA2_LOAD_ABSENT -> SKIP  (runtime missing; CI stays green)
//   CAMERA2_LOAD_ABI    -> FAIL  (present but exports broken; never a
//                                 silent SKIP)
//
// Functional head (this wave): ACameraManager_create / delete and
// ACameraManager_getCameraIdList with the id list copied into owned
// XIOM-side byte slots (the event-copy pattern; pointers never cross the
// boundary -- the bridge keeps the ACameraIdList C-side and copies each
// id on request).  A typed ACAMERA_ERROR_* from getCameraIdList (e.g.
// ACAMERA_ERROR_CAMERA_SERVICE when the camera service is unreachable
// from a shell process) is reported as a typed status, NOT a failure of
// the package: the suite/driver record it honestly and stay green.
//
// Device/session/request/characteristics ops are export-set + ABI-checked
// only this wave: their async callbacks (state/capture callbacks,
// ACaptureRequest_setUserContext handoffs) are staged for a later wave.
// Handles cross as Int.
//
// Naming note: this package is the standalone home of the A8 camera head
// (one package per head), aligned with the `xiom.media*` / `xiom.aaudio`
// pattern; the module name is the package name.

module xiom.camera2ndk

extern "C" {
  fn xc_load_named(soname: *UInt8) -> Int32;
  fn xc_load() -> Int32;
  fn xc_error() -> *UInt8;
  fn xc_abi_missing_count() -> Int32;
  fn xc_abi_missing() -> *UInt8;
  fn xc_declared_exports() -> Int32;
  fn xc_manager_create() -> Int64;
  fn xc_manager_delete(manager: Int64);
  fn xc_manager_get_camera_ids(manager: Int64) -> Int32;
  fn xc_camera_id_count() -> Int32;
  fn xc_camera_id_len(index: Int32) -> Int32;
  fn xc_camera_id_copy(index: Int32, dst: *UInt8, cap: Int32) -> Int32;
  fn xc_unload();
}

// =========================================================================
// Identity and classification
// =========================================================================

pub const CAMERA2_SONAME: Str = "libcamera2ndk.so";

// Probe outcome kinds.
pub const CAMERA2_LOAD_ABSENT: Int = 0; // runtime lib missing -> SKIP
pub const CAMERA2_LOAD_ABI: Int = 1;    // present but exports broken -> FAIL

pub type Camera2ProbeError = {
  kind: Int;
  message: Str;
}

pub type Camera2Runtime = {
  missing_exports: Int;
  missing: Str;
  export_count: Int;
}

/// A camera_status_t outcome (or a bridge-internal status code); the
/// symbolic name is resolved by `camera_status_name`.
pub type Camera2StatusError = {
  code: Int;
  name: Str;
}

/// Bridge-internal status codes (> 0) for the manager head; camera
/// status codes (<= 0, ACAMERA_*) pass through unchanged.
pub const CAMERA2_INTERNAL_NO_MANAGER: Int = 1;
pub const CAMERA2_INTERNAL_UNRESOLVED: Int = 2;
pub const CAMERA2_INTERNAL_NULL_LIST: Int = 3;
pub const CAMERA2_INTERNAL_LIST_RANGE: Int = 4;

// =========================================================================
// ACameraManager status codes (NdkCameraError.h, camera_status_t)
// =========================================================================

pub const ACAMERA_OK: Int = 0;
pub const ACAMERA_ERROR_BASE: Int = -10000;
pub const ACAMERA_ERROR_UNKNOWN: Int = -10000;
pub const ACAMERA_ERROR_INVALID_PARAMETER: Int = -10001;
pub const ACAMERA_ERROR_CAMERA_DISCONNECTED: Int = -10002;
pub const ACAMERA_ERROR_NOT_ENOUGH_MEMORY: Int = -10003;
pub const ACAMERA_ERROR_METADATA_NOT_FOUND: Int = -10004;
pub const ACAMERA_ERROR_CAMERA_DEVICE: Int = -10005;
pub const ACAMERA_ERROR_CAMERA_SERVICE: Int = -10006;
pub const ACAMERA_ERROR_SESSION_CLOSED: Int = -10007;
pub const ACAMERA_ERROR_INVALID_OPERATION: Int = -10008;
pub const ACAMERA_ERROR_STREAM_CONFIGURE_FAIL: Int = -10009;
pub const ACAMERA_ERROR_CAMERA_IN_USE: Int = -10010;
pub const ACAMERA_ERROR_MAX_CAMERA_IN_USE: Int = -10011;
pub const ACAMERA_ERROR_CAMERA_DISABLED: Int = -10012;
pub const ACAMERA_ERROR_PERMISSION_DENIED: Int = -10013;
pub const ACAMERA_ERROR_UNSUPPORTED_OPERATION: Int = -10014;

/// Symbolic name for a camera_status_t (used in suite/driver messages;
/// unknown values render as "ACAMERA_STATUS_<code>").
/// Complexity: O(1).
pub fn camera_status_name(code: Int) -> Str
  requires: true
{
  if code == ACAMERA_ERROR_UNKNOWN { return "ACAMERA_ERROR_UNKNOWN"; }
  if code == ACAMERA_ERROR_INVALID_PARAMETER { return "ACAMERA_ERROR_INVALID_PARAMETER"; }
  if code == ACAMERA_ERROR_CAMERA_DISCONNECTED { return "ACAMERA_ERROR_CAMERA_DISCONNECTED"; }
  if code == ACAMERA_ERROR_NOT_ENOUGH_MEMORY { return "ACAMERA_ERROR_NOT_ENOUGH_MEMORY"; }
  if code == ACAMERA_ERROR_METADATA_NOT_FOUND { return "ACAMERA_ERROR_METADATA_NOT_FOUND"; }
  if code == ACAMERA_ERROR_CAMERA_DEVICE { return "ACAMERA_ERROR_CAMERA_DEVICE"; }
  if code == ACAMERA_ERROR_CAMERA_SERVICE { return "ACAMERA_ERROR_CAMERA_SERVICE"; }
  if code == ACAMERA_ERROR_SESSION_CLOSED { return "ACAMERA_ERROR_SESSION_CLOSED"; }
  if code == ACAMERA_ERROR_INVALID_OPERATION { return "ACAMERA_ERROR_INVALID_OPERATION"; }
  if code == ACAMERA_ERROR_STREAM_CONFIGURE_FAIL { return "ACAMERA_ERROR_STREAM_CONFIGURE_FAIL"; }
  if code == ACAMERA_ERROR_CAMERA_IN_USE { return "ACAMERA_ERROR_CAMERA_IN_USE"; }
  if code == ACAMERA_ERROR_MAX_CAMERA_IN_USE { return "ACAMERA_ERROR_MAX_CAMERA_IN_USE"; }
  if code == ACAMERA_ERROR_CAMERA_DISABLED { return "ACAMERA_ERROR_CAMERA_DISABLED"; }
  if code == ACAMERA_ERROR_PERMISSION_DENIED { return "ACAMERA_ERROR_PERMISSION_DENIED"; }
  if code == ACAMERA_ERROR_UNSUPPORTED_OPERATION { return "ACAMERA_ERROR_UNSUPPORTED_OPERATION"; }
  return "ACAMERA_STATUS_" + to_string(code);
}

// =========================================================================
// Metadata entry types (NdkCameraMetadata.h)
// =========================================================================

pub const ACAMERA_TYPE_BYTE: Int = 0;
pub const ACAMERA_TYPE_INT32: Int = 1;
pub const ACAMERA_TYPE_FLOAT: Int = 2;
pub const ACAMERA_TYPE_INT64: Int = 3;
pub const ACAMERA_TYPE_DOUBLE: Int = 4;
pub const ACAMERA_TYPE_RATIONAL: Int = 5;
pub const ACAMERA_NUM_TYPES: Int = 6;

// =========================================================================
// ACameraDevice error codes (NdkCameraDevice.h, error-state callback)
// =========================================================================

pub const ERROR_CAMERA_IN_USE: Int = 1;
pub const ERROR_MAX_CAMERAS_IN_USE: Int = 2;
pub const ERROR_CAMERA_DISABLED: Int = 3;
pub const ERROR_CAMERA_DEVICE: Int = 4;
pub const ERROR_CAMERA_SERVICE: Int = 5;

// =========================================================================
// Capture request templates (NdkCameraDevice.h, ACameraDevice_request_template)
// =========================================================================

pub const TEMPLATE_PREVIEW: Int = 1;
pub const TEMPLATE_STILL_CAPTURE: Int = 2;
pub const TEMPLATE_RECORD: Int = 3;
pub const TEMPLATE_VIDEO_SNAPSHOT: Int = 4;
pub const TEMPLATE_ZERO_SHUTTER_LAG: Int = 5;
pub const TEMPLATE_MANUAL: Int = 6;

// =========================================================================
// Capture session enums (NdkCameraCaptureSession.h)
// =========================================================================

pub const CAPTURE_FAILURE_REASON_FLUSHED: Int = 0;
pub const CAPTURE_FAILURE_REASON_ERROR: Int = 1;
pub const CAPTURE_SEQUENCE_ID_NONE: Int = -1;

// =========================================================================
// Metadata tags (NdkCameraMetadataTags.h)
//
// Tag values are section << 16 | index (acamera_metadata_section /
// acamera_metadata_tag); every constant below was transcribed from the
// pinned r27b header on 2026-10-15 (see PROVENANCE.md).  This is the
// verified common-tags subset for the A8 head -- not the full 500+ tag
// surface (that is a later widening, per ROADMAP.md).
// =========================================================================

// Color correction (section 0)
pub const ACAMERA_COLOR_CORRECTION_MODE: Int = 0x00000000;
pub const ACAMERA_COLOR_CORRECTION_ABERRATION_MODE: Int = 0x00000003;

// Control (section 1)
pub const ACAMERA_CONTROL_AE_ANTIBANDING_MODE: Int = 0x00010000;
pub const ACAMERA_CONTROL_AE_EXPOSURE_COMPENSATION: Int = 0x00010001;
pub const ACAMERA_CONTROL_AE_LOCK: Int = 0x00010002;
pub const ACAMERA_CONTROL_AE_MODE: Int = 0x00010003;
pub const ACAMERA_CONTROL_AE_REGIONS: Int = 0x00010004;
pub const ACAMERA_CONTROL_AE_TARGET_FPS_RANGE: Int = 0x00010005;
pub const ACAMERA_CONTROL_AE_PRECAPTURE_TRIGGER: Int = 0x00010006;
pub const ACAMERA_CONTROL_AF_MODE: Int = 0x00010007;
pub const ACAMERA_CONTROL_AF_REGIONS: Int = 0x00010008;
pub const ACAMERA_CONTROL_AF_TRIGGER: Int = 0x00010009;
pub const ACAMERA_CONTROL_AWB_LOCK: Int = 0x0001000A;
pub const ACAMERA_CONTROL_AWB_MODE: Int = 0x0001000B;
pub const ACAMERA_CONTROL_AWB_REGIONS: Int = 0x0001000C;
pub const ACAMERA_CONTROL_CAPTURE_INTENT: Int = 0x0001000D;
pub const ACAMERA_CONTROL_MODE: Int = 0x0001000F;
pub const ACAMERA_CONTROL_SCENE_MODE: Int = 0x00010010;
pub const ACAMERA_CONTROL_VIDEO_STABILIZATION_MODE: Int = 0x00010011;
pub const ACAMERA_CONTROL_AE_AVAILABLE_MODES: Int = 0x00010013;
pub const ACAMERA_CONTROL_AE_COMPENSATION_RANGE: Int = 0x00010015;
pub const ACAMERA_CONTROL_AE_COMPENSATION_STEP: Int = 0x00010016;
pub const ACAMERA_CONTROL_AF_AVAILABLE_MODES: Int = 0x00010017;
pub const ACAMERA_CONTROL_AE_STATE: Int = 0x0001001F;
pub const ACAMERA_CONTROL_AF_STATE: Int = 0x00010020;
pub const ACAMERA_CONTROL_AWB_STATE: Int = 0x00010022;
pub const ACAMERA_CONTROL_AE_LOCK_AVAILABLE: Int = 0x00010024;

// Control: capture intent values
pub const ACAMERA_CONTROL_CAPTURE_INTENT_CUSTOM: Int = 0;
pub const ACAMERA_CONTROL_CAPTURE_INTENT_PREVIEW: Int = 1;
pub const ACAMERA_CONTROL_CAPTURE_INTENT_STILL_CAPTURE: Int = 2;
pub const ACAMERA_CONTROL_CAPTURE_INTENT_VIDEO_RECORD: Int = 3;
pub const ACAMERA_CONTROL_CAPTURE_INTENT_VIDEO_SNAPSHOT: Int = 4;
pub const ACAMERA_CONTROL_CAPTURE_INTENT_ZERO_SHUTTER_LAG: Int = 5;
pub const ACAMERA_CONTROL_CAPTURE_INTENT_MANUAL: Int = 6;
pub const ACAMERA_CONTROL_CAPTURE_INTENT_MOTION_TRACKING: Int = 7;

// Control: AE/AF/AWB mode values
pub const ACAMERA_CONTROL_AE_MODE_OFF: Int = 0;
pub const ACAMERA_CONTROL_AE_MODE_ON: Int = 1;
pub const ACAMERA_CONTROL_AE_MODE_ON_AUTO_FLASH: Int = 2;
pub const ACAMERA_CONTROL_AE_MODE_ON_ALWAYS_FLASH: Int = 3;
pub const ACAMERA_CONTROL_AE_MODE_ON_AUTO_FLASH_REDEYE: Int = 4;
pub const ACAMERA_CONTROL_AE_MODE_ON_EXTERNAL_FLASH: Int = 5;
pub const ACAMERA_CONTROL_AF_MODE_OFF: Int = 0;
pub const ACAMERA_CONTROL_AF_MODE_AUTO: Int = 1;
pub const ACAMERA_CONTROL_AF_MODE_MACRO: Int = 2;
pub const ACAMERA_CONTROL_AF_MODE_CONTINUOUS_VIDEO: Int = 3;
pub const ACAMERA_CONTROL_AF_MODE_CONTINUOUS_PICTURE: Int = 4;
pub const ACAMERA_CONTROL_AF_MODE_EDOF: Int = 5;
pub const ACAMERA_CONTROL_AWB_MODE_OFF: Int = 0;
pub const ACAMERA_CONTROL_AWB_MODE_AUTO: Int = 1;
pub const ACAMERA_CONTROL_AWB_MODE_INCANDESCENT: Int = 2;
pub const ACAMERA_CONTROL_AWB_MODE_FLUORESCENT: Int = 3;
pub const ACAMERA_CONTROL_AWB_MODE_WARM_FLUORESCENT: Int = 4;
pub const ACAMERA_CONTROL_AWB_MODE_DAYLIGHT: Int = 5;
pub const ACAMERA_CONTROL_AWB_MODE_CLOUDY_DAYLIGHT: Int = 6;
pub const ACAMERA_CONTROL_AWB_MODE_TWILIGHT: Int = 7;
pub const ACAMERA_CONTROL_AWB_MODE_SHADE: Int = 8;

// Edge (section 3)
pub const ACAMERA_EDGE_MODE: Int = 0x00030000;

// Flash (section 4)
pub const ACAMERA_FLASH_MODE: Int = 0x00040002;
pub const ACAMERA_FLASH_MODE_OFF: Int = 0;
pub const ACAMERA_FLASH_MODE_SINGLE: Int = 1;
pub const ACAMERA_FLASH_MODE_TORCH: Int = 2;

// JPEG (section 7)
pub const ACAMERA_JPEG_ORIENTATION: Int = 0x00070003;
pub const ACAMERA_JPEG_QUALITY: Int = 0x00070004;
pub const ACAMERA_JPEG_THUMBNAIL_QUALITY: Int = 0x00070005;
pub const ACAMERA_JPEG_THUMBNAIL_SIZE: Int = 0x00070006;

// Lens (section 8)
pub const ACAMERA_LENS_APERTURE: Int = 0x00080000;
pub const ACAMERA_LENS_FILTER_DENSITY: Int = 0x00080001;
pub const ACAMERA_LENS_FOCAL_LENGTH: Int = 0x00080002;
pub const ACAMERA_LENS_FOCUS_DISTANCE: Int = 0x00080003;
pub const ACAMERA_LENS_OPTICAL_STABILIZATION_MODE: Int = 0x00080004;
pub const ACAMERA_LENS_FACING: Int = 0x00080005;
pub const ACAMERA_LENS_FACING_FRONT: Int = 0;
pub const ACAMERA_LENS_FACING_BACK: Int = 1;
pub const ACAMERA_LENS_FACING_EXTERNAL: Int = 2;

// Lens info (section 9)
pub const ACAMERA_LENS_INFO_AVAILABLE_APERTURES: Int = 0x00090000;
pub const ACAMERA_LENS_INFO_AVAILABLE_FILTER_DENSITIES: Int = 0x00090001;
pub const ACAMERA_LENS_INFO_AVAILABLE_FOCAL_LENGTHS: Int = 0x00090002;
pub const ACAMERA_LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION: Int = 0x00090003;
pub const ACAMERA_LENS_INFO_HYPERFOCAL_DISTANCE: Int = 0x00090004;
pub const ACAMERA_LENS_INFO_MINIMUM_FOCUS_DISTANCE: Int = 0x00090005;
pub const ACAMERA_LENS_INFO_SHADING_MAP_SIZE: Int = 0x00090006;
pub const ACAMERA_LENS_INFO_FOCUS_DISTANCE_CALIBRATION: Int = 0x00090007;

// Noise reduction (section 10)
pub const ACAMERA_NOISE_REDUCTION_MODE: Int = 0x000A0000;

// Request (section 12)
pub const ACAMERA_REQUEST_PIPELINE_DEPTH: Int = 0x000C0009;
pub const ACAMERA_REQUEST_PIPELINE_MAX_DEPTH: Int = 0x000C000A;
pub const ACAMERA_REQUEST_PARTIAL_RESULT_COUNT: Int = 0x000C000B;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES: Int = 0x000C000C;
pub const ACAMERA_REQUEST_AVAILABLE_REQUEST_KEYS: Int = 0x000C000D;
pub const ACAMERA_REQUEST_AVAILABLE_RESULT_KEYS: Int = 0x000C000E;
pub const ACAMERA_REQUEST_AVAILABLE_CHARACTERISTICS_KEYS: Int = 0x000C000F;
pub const ACAMERA_REQUEST_AVAILABLE_SESSION_KEYS: Int = 0x000C0010;

// Request: available capabilities values
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE: Int = 0;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR: Int = 1;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_MANUAL_POST_PROCESSING: Int = 2;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_RAW: Int = 3;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_READ_SENSOR_SETTINGS: Int = 5;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_BURST_CAPTURE: Int = 6;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_DEPTH_OUTPUT: Int = 8;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_MOTION_TRACKING: Int = 10;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA: Int = 11;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_MONOCHROME: Int = 12;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_SECURE_IMAGE_DATA: Int = 13;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_SYSTEM_CAMERA: Int = 14;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_ULTRA_HIGH_RESOLUTION_SENSOR: Int = 16;
pub const ACAMERA_REQUEST_AVAILABLE_CAPABILITIES_STREAM_USE_CASE: Int = 19;

// Scaler (section 13)
pub const ACAMERA_SCALER_CROP_REGION: Int = 0x000D0000;
pub const ACAMERA_SCALER_AVAILABLE_STREAM_CONFIGURATIONS: Int = 0x000D000A;
pub const ACAMERA_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT: Int = 0;
pub const ACAMERA_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_INPUT: Int = 1;
pub const ACAMERA_SCALER_AVAILABLE_STREAM_USE_CASES: Int = 0x000D001A;

// Sensor (section 14)
pub const ACAMERA_SENSOR_EXPOSURE_TIME: Int = 0x000E0000;
pub const ACAMERA_SENSOR_FRAME_DURATION: Int = 0x000E0001;
pub const ACAMERA_SENSOR_SENSITIVITY: Int = 0x000E0002;
pub const ACAMERA_SENSOR_ORIENTATION: Int = 0x000E000E;
pub const ACAMERA_SENSOR_TIMESTAMP: Int = 0x000E0010;

// Sensor info (section 15)
pub const ACAMERA_SENSOR_INFO_ACTIVE_ARRAY_SIZE: Int = 0x000F0000;
pub const ACAMERA_SENSOR_INFO_SENSITIVITY_RANGE: Int = 0x000F0001;
pub const ACAMERA_SENSOR_INFO_COLOR_FILTER_ARRANGEMENT: Int = 0x000F0002;
pub const ACAMERA_SENSOR_INFO_EXPOSURE_TIME_RANGE: Int = 0x000F0003;
pub const ACAMERA_SENSOR_INFO_MAX_FRAME_DURATION: Int = 0x000F0004;
pub const ACAMERA_SENSOR_INFO_PHYSICAL_SIZE: Int = 0x000F0005;
pub const ACAMERA_SENSOR_INFO_PIXEL_ARRAY_SIZE: Int = 0x000F0006;
pub const ACAMERA_SENSOR_INFO_WHITE_LEVEL: Int = 0x000F0007;
pub const ACAMERA_SENSOR_INFO_TIMESTAMP_SOURCE: Int = 0x000F0008;

// Statistics (section 17)
pub const ACAMERA_STATISTICS_FACE_DETECT_MODE: Int = 0x00110000;

// Tonemap (section 19)
pub const ACAMERA_TONEMAP_MODE: Int = 0x00130003;

// Info (section 21)
pub const ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL: Int = 0x00150000;
pub const ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL_LIMITED: Int = 0;
pub const ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL_FULL: Int = 1;
pub const ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL_LEGACY: Int = 2;
pub const ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL_3: Int = 3;
pub const ACAMERA_INFO_SUPPORTED_HARDWARE_LEVEL_EXTERNAL: Int = 4;

// =========================================================================
// Probe API
// =========================================================================

/// Probe an explicitly named camera runtime library.  Useful for tests: a
/// bogus name exercises the ABSENT/SKIP classification deterministically
/// even on hosts that ship the library.
/// Complexity: O(load + export set).
pub fn camera2_probe_named(soname: Str) -> Result[Camera2Runtime, Camera2ProbeError]
  requires: soname.len() > 0
{
  let rc = unsafe { xc_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xc_error()) };
    if rc == 1 {
      return Err(Camera2ProbeError{ kind: CAMERA2_LOAD_ABSENT; message: msg });
    }
    return Err(Camera2ProbeError{ kind: CAMERA2_LOAD_ABI; message: msg });
  }
  let missing_count = unsafe { xc_abi_missing_count() as Int };
  let missing = unsafe { Str::from_c_str(xc_abi_missing()) };
  let total = unsafe { xc_declared_exports() as Int };
  return Ok(Camera2Runtime{ missing_exports: missing_count, missing: missing, export_count: total });
}

/// Probe the default runtime (libcamera2ndk.so).  On Android this is the
/// platform camera2 NDK; on Windows the probe classifies ABSENT (SKIP).
/// Complexity: O(load + export set).
pub fn camera2_probe() -> Result[Camera2Runtime, Camera2ProbeError]
  requires: true
{
  return camera2_probe_named(CAMERA2_SONAME);
}

/// The declared export-set size of this package (compile-time constant;
/// callable before any load).
/// Complexity: O(1).
pub fn camera2_declared_exports() -> Int
  requires: true
{
  unsafe { return xc_declared_exports() as Int; }
}

/// The last bridge error / missing-export summary (empty when clean).
/// Complexity: O(1).
pub fn camera2_error() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xc_error()); }
}

/// Release any runtime handles held by the bridge (a still-open manager is
/// deleted first).  Safe when nothing is loaded.
/// Complexity: O(1).
pub fn camera2_unload()
  requires: true
{
  unsafe { xc_unload(); }
}

// =========================================================================
// ACameraManager functional head
// =========================================================================

pub type CameraManager = {
  handle: Int;
}

/// Create an ACameraManager (pure: contacts the camera service only on
/// later calls).  The caller must call `camera_manager_delete`.
/// Complexity: O(initialization).
pub fn camera_manager_create() -> Result[CameraManager, Camera2ProbeError]
  requires: true
{
  let h = unsafe { xc_manager_create() as Int };
  if h == 0 {
    return Err(Camera2ProbeError{ kind: CAMERA2_LOAD_ABI; message: camera2_error() });
  }
  return Ok(CameraManager{ handle: h });
}

/// Delete the manager and free every address-space resource the bridge
/// recorded for it (the camera-id list included).
/// Complexity: O(1).
pub fn camera_manager_delete(manager: CameraManager)
  requires: true
{
  unsafe { xc_manager_delete(manager.handle as Int64); }
}

/// ACameraManager_getCameraIdList, with the ids copied into owned XIOM
/// strings (the list itself stays C-side and is freed by the bridge).
/// A typed ACAMERA_ERROR_* (e.g. ACAMERA_ERROR_CAMERA_SERVICE when the
/// camera service is unreachable) is returned as a typed status -- it is
/// a legitimate outcome of a shell process, not a package failure.
/// Complexity: O(cameras).
pub fn camera_manager_camera_ids(manager: &CameraManager) -> Result[Vec[Str], Camera2StatusError]
  requires: true
{
  let rc = unsafe { xc_manager_get_camera_ids(manager.handle as Int64) as Int };
  if rc != 0 {
    return Err(Camera2StatusError{ code: rc, name: camera_status_name(rc) });
  }
  let n = unsafe { xc_camera_id_count() as Int };
  var out: Vec[Str] = Vec[Str].new();
  var i: Int = 0;
  while i < n {
    let len = unsafe { xc_camera_id_len(i as Int32) as Int };
    if len < 0 {
      return Err(Camera2StatusError{ code: CAMERA2_INTERNAL_LIST_RANGE, name: camera_status_name(CAMERA2_INTERNAL_LIST_RANGE) });
    }
    var slot: Vec[UInt8] = Vec[UInt8].new();
    var k: Int = 0;
    while k < len + 1 {
      slot.push(0 as UInt8);
      k = k + 1;
    }
    let got = unsafe { xc_camera_id_copy(i as Int32, slot.as_mut_ptr(), (len + 1) as Int32) as Int };
    if got != len {
      return Err(Camera2StatusError{ code: CAMERA2_INTERNAL_LIST_RANGE, name: camera_status_name(CAMERA2_INTERNAL_LIST_RANGE) });
    }
    out.push(Str::from_c_str(slot.as_ptr()));
    i = i + 1;
  }
  return Ok(out);
}
