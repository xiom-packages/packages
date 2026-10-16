// XIOM -- xiom.aaudio: Android AAudio bindings (NDK r27b).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: runtime probe + functional head for the A6 audio slice of the
// Android SDK100 program (docs/ANDROID-SDK100.md), backed by the vendored
// bridge `src/aaudio_bridge.c` (compiled with `--c-source`; see
// port.args.json).  The bridge resolves `libaaudio.so` at RUNTIME (dlopen
// on Android/Linux, LoadLibraryA on Windows -- where everything
// classifies ABSENT) and verifies the declared export set of
// aaudio/AAudio.h (NDK r27b):
//
//   67 AAUDIO_API declarations measured in the pinned header:
//     AAudio_*               (3: convertResultToText, convertStreamStateToText,
//                               createStreamBuilder)
//     AAudioStreamBuilder_* (23: setters + openStream + delete)
//     AAudioStream_*        (41: control + I/O + queries + release/close)
//   (The brief's "72" was an estimate; the header holds 67 exports, the
//   three AAudioTesting.h runtime symbols -- getMMapPolicy/setMMapPolicy/
//   isMMapUsed -- ship in libaaudio.so without a shipped header and are a
//   documented exclusion, see SPEC.md.)
//
// Classification (the suite maps it to markers):
//   AAUDIO_LOAD_ABSENT -> SKIP  (runtime missing; CI stays green)
//   AAUDIO_LOAD_ABI    -> FAIL  (present but exports broken; never a
//                                silent SKIP)
//
// Pointers never cross the boundary (B-25 discipline): AAudioStream /
// AAudioStreamBuilder handles cross as Int; out-params (waitForStateChange
// next-state, getTimestamp frame/time) and the read/write data window stay
// entirely inside the bridge and are read back through scalar accessors.
// Callbacks are top-level C stubs handed directly to AAudio (direct
// handoff; no env, no registry).
//
// Functional head (best-effort, honest): builder create/delete works
// without any device; a stream open attempt (OUTPUT, NONE, PCM_I16,
// 2 ch, 48000 Hz, SHARED) records the typed AAUDIO_ERROR_* verdict and a
// successful open requests start and closes cleanly.  The emulator often
// runs -no-audio; a typed open failure is a recorded outcome, not a
// package failure.

module xiom.aaudio

extern "C" {
  fn xaa_load_named(soname: *UInt8) -> Int32;

  fn xaa_load() -> Int32;
  fn xaa_loaded() -> Int32;
  fn xaa_error() -> *UInt8;
  fn xaa_abi_missing_count() -> Int32;
  fn xaa_abi_missing() -> *UInt8;
  fn xaa_unload();

  fn xaa_builder_create() -> Int64;
  fn xaa_builder_delete(builder: Int64) -> Int32;
  fn xaa_builder_set_device_id(builder: Int64, value: Int32);
  fn xaa_builder_set_package_name(builder: Int64, name: *UInt8);
  fn xaa_builder_set_attribution_tag(builder: Int64, tag: *UInt8);
  fn xaa_builder_set_sample_rate(builder: Int64, value: Int32);
  fn xaa_builder_set_channel_count(builder: Int64, value: Int32);
  fn xaa_builder_set_samples_per_frame(builder: Int64, value: Int32);
  fn xaa_builder_set_format(builder: Int64, value: Int32);
  fn xaa_builder_set_sharing_mode(builder: Int64, value: Int32);
  fn xaa_builder_set_direction(builder: Int64, value: Int32);
  fn xaa_builder_set_buffer_capacity_in_frames(builder: Int64, value: Int32);
  fn xaa_builder_set_performance_mode(builder: Int64, value: Int32);
  fn xaa_builder_set_usage(builder: Int64, value: Int32);
  fn xaa_builder_set_content_type(builder: Int64, value: Int32);
  fn xaa_builder_set_spatialization_behavior(builder: Int64, value: Int32);
  fn xaa_builder_set_is_content_spatialized(builder: Int64, value: Int32);
  fn xaa_builder_set_input_preset(builder: Int64, value: Int32);
  fn xaa_builder_set_allowed_capture_policy(builder: Int64, value: Int32);
  fn xaa_builder_set_session_id(builder: Int64, value: Int32);
  fn xaa_builder_set_privacy_sensitive(builder: Int64, value: Int32);
  fn xaa_builder_set_frames_per_data_callback(builder: Int64, value: Int32);
  fn xaa_builder_set_channel_mask(builder: Int64, value: Int32);
  fn xaa_builder_set_data_callback(builder: Int64);
  fn xaa_builder_set_error_callback(builder: Int64);
  fn xaa_builder_open_stream(builder: Int64) -> Int64;
  fn xaa_open_result() -> Int32;

  fn xaa_stream_release(stream: Int64) -> Int32;
  fn xaa_stream_close(stream: Int64) -> Int32;
  fn xaa_stream_request_start(stream: Int64) -> Int32;
  fn xaa_stream_request_pause(stream: Int64) -> Int32;
  fn xaa_stream_request_flush(stream: Int64) -> Int32;
  fn xaa_stream_request_stop(stream: Int64) -> Int32;
  fn xaa_stream_get_state(stream: Int64) -> Int32;
  fn xaa_stream_wait_for_state_change(stream: Int64, input_state: Int32, timeout_ns: Int64) -> Int32;
  fn xaa_wait_state_value() -> Int32;
  fn xaa_stream_read(stream: Int64, num_frames: Int32, timeout_ns: Int64) -> Int32;
  fn xaa_stream_write(stream: Int64, num_frames: Int32, timeout_ns: Int64) -> Int32;
  fn xaa_stream_set_buffer_size_in_frames(stream: Int64, num_frames: Int32) -> Int32;
  fn xaa_stream_get_buffer_size_in_frames(stream: Int64) -> Int32;
  fn xaa_stream_get_frames_per_burst(stream: Int64) -> Int32;
  fn xaa_stream_get_buffer_capacity_in_frames(stream: Int64) -> Int32;
  fn xaa_stream_get_frames_per_data_callback(stream: Int64) -> Int32;
  fn xaa_stream_get_xrun_count(stream: Int64) -> Int32;
  fn xaa_stream_get_sample_rate(stream: Int64) -> Int32;
  fn xaa_stream_get_hardware_sample_rate(stream: Int64) -> Int32;
  fn xaa_stream_get_channel_count(stream: Int64) -> Int32;
  fn xaa_stream_get_hardware_channel_count(stream: Int64) -> Int32;
  fn xaa_stream_get_samples_per_frame(stream: Int64) -> Int32;
  fn xaa_stream_get_device_id(stream: Int64) -> Int32;
  fn xaa_stream_get_format(stream: Int64) -> Int32;
  fn xaa_stream_get_hardware_format(stream: Int64) -> Int32;
  fn xaa_stream_get_sharing_mode(stream: Int64) -> Int32;
  fn xaa_stream_get_performance_mode(stream: Int64) -> Int32;
  fn xaa_stream_get_direction(stream: Int64) -> Int32;
  fn xaa_stream_get_frames_written(stream: Int64) -> Int64;
  fn xaa_stream_get_frames_read(stream: Int64) -> Int64;
  fn xaa_stream_get_session_id(stream: Int64) -> Int32;
  fn xaa_stream_get_timestamp(stream: Int64, clock_id: Int32) -> Int32;
  fn xaa_timestamp_frames() -> Int64;
  fn xaa_timestamp_nanos() -> Int64;
  fn xaa_stream_get_usage(stream: Int64) -> Int32;
  fn xaa_stream_get_content_type(stream: Int64) -> Int32;
  fn xaa_stream_get_spatialization_behavior(stream: Int64) -> Int32;
  fn xaa_stream_is_content_spatialized(stream: Int64) -> Int32;
  fn xaa_stream_get_input_preset(stream: Int64) -> Int32;
  fn xaa_stream_get_allowed_capture_policy(stream: Int64) -> Int32;
  fn xaa_stream_is_privacy_sensitive(stream: Int64) -> Int32;
  fn xaa_stream_get_channel_mask(stream: Int64) -> Int32;

  fn xaa_convert_result_to_text(code: Int32) -> *UInt8;
  fn xaa_convert_stream_state_to_text(state: Int32) -> *UInt8;
  fn xaa_data_callback_count() -> Int32;
  fn xaa_error_callback_count() -> Int32;
}

// =========================================================================
// Identity and classification
// =========================================================================

pub const AAUDIO_SONAME: Str = "libaaudio.so";

// Probe outcome kinds.
pub const AAUDIO_LOAD_ABSENT: Int = 0; // runtime lib missing -> SKIP
pub const AAUDIO_LOAD_ABI: Int = 1;    // present but exports broken -> FAIL

pub type AaudioProbeError = {
  kind: Int;
  message: Str;
}

pub type AaudioRuntime = {
  missing_exports: Int;
  missing: Str;
}

// =========================================================================
// Core constants (aaudio/AAudio.h, NDK r27b)
// =========================================================================

// Value not specified (header #define).
pub const AAUDIO_UNSPECIFIED: Int = 0;

// aaudio_direction_t.
pub const AAUDIO_DIRECTION_OUTPUT: Int = 0;
pub const AAUDIO_DIRECTION_INPUT: Int = 1;

// aaudio_format_t.
pub const AAUDIO_FORMAT_INVALID: Int = -1;
pub const AAUDIO_FORMAT_UNSPECIFIED: Int = 0;
pub const AAUDIO_FORMAT_PCM_I16: Int = 1;
pub const AAUDIO_FORMAT_PCM_FLOAT: Int = 2;
pub const AAUDIO_FORMAT_PCM_I24_PACKED: Int = 3;
pub const AAUDIO_FORMAT_PCM_I32: Int = 4;
pub const AAUDIO_FORMAT_IEC61937: Int = 5;

// aaudio_result_t (the AAUDIO_OK + AAUDIO_ERROR_* family; computed in the
// header from AAUDIO_ERROR_BASE = -900 with reserved gaps).
pub const AAUDIO_OK: Int = 0;
pub const AAUDIO_ERROR_BASE: Int = -900;
pub const AAUDIO_ERROR_DISCONNECTED: Int = -899;
pub const AAUDIO_ERROR_ILLEGAL_ARGUMENT: Int = -898;
pub const AAUDIO_ERROR_INTERNAL: Int = -896;
pub const AAUDIO_ERROR_INVALID_STATE: Int = -895;
pub const AAUDIO_ERROR_INVALID_HANDLE: Int = -892;
pub const AAUDIO_ERROR_UNIMPLEMENTED: Int = -890;
pub const AAUDIO_ERROR_UNAVAILABLE: Int = -889;
pub const AAUDIO_ERROR_NO_FREE_HANDLES: Int = -888;
pub const AAUDIO_ERROR_NO_MEMORY: Int = -887;
pub const AAUDIO_ERROR_NULL: Int = -886;
pub const AAUDIO_ERROR_TIMEOUT: Int = -885;
pub const AAUDIO_ERROR_WOULD_BLOCK: Int = -884;
pub const AAUDIO_ERROR_INVALID_FORMAT: Int = -883;
pub const AAUDIO_ERROR_OUT_OF_RANGE: Int = -882;
pub const AAUDIO_ERROR_NO_SERVICE: Int = -881;
pub const AAUDIO_ERROR_INVALID_RATE: Int = -880;

// aaudio_stream_state_t.
pub const AAUDIO_STREAM_STATE_UNINITIALIZED: Int = 0;
pub const AAUDIO_STREAM_STATE_UNKNOWN: Int = 1;
pub const AAUDIO_STREAM_STATE_OPEN: Int = 2;
pub const AAUDIO_STREAM_STATE_STARTING: Int = 3;
pub const AAUDIO_STREAM_STATE_STARTED: Int = 4;
pub const AAUDIO_STREAM_STATE_PAUSING: Int = 5;
pub const AAUDIO_STREAM_STATE_PAUSED: Int = 6;
pub const AAUDIO_STREAM_STATE_FLUSHING: Int = 7;
pub const AAUDIO_STREAM_STATE_FLUSHED: Int = 8;
pub const AAUDIO_STREAM_STATE_STOPPING: Int = 9;
pub const AAUDIO_STREAM_STATE_STOPPED: Int = 10;
pub const AAUDIO_STREAM_STATE_CLOSING: Int = 11;
pub const AAUDIO_STREAM_STATE_CLOSED: Int = 12;
pub const AAUDIO_STREAM_STATE_DISCONNECTED: Int = 13;

// aaudio_sharing_mode_t.
pub const AAUDIO_SHARING_MODE_EXCLUSIVE: Int = 0;
pub const AAUDIO_SHARING_MODE_SHARED: Int = 1;

// aaudio_performance_mode_t.
pub const AAUDIO_PERFORMANCE_MODE_NONE: Int = 10;
pub const AAUDIO_PERFORMANCE_MODE_POWER_SAVING: Int = 11;
pub const AAUDIO_PERFORMANCE_MODE_LOW_LATENCY: Int = 12;

// aaudio_usage_t.
pub const AAUDIO_SYSTEM_USAGE_OFFSET: Int = 1000;
pub const AAUDIO_USAGE_MEDIA: Int = 1;
pub const AAUDIO_USAGE_VOICE_COMMUNICATION: Int = 2;
pub const AAUDIO_USAGE_VOICE_COMMUNICATION_SIGNALLING: Int = 3;
pub const AAUDIO_USAGE_ALARM: Int = 4;
pub const AAUDIO_USAGE_NOTIFICATION: Int = 5;
pub const AAUDIO_USAGE_NOTIFICATION_RINGTONE: Int = 6;
pub const AAUDIO_USAGE_NOTIFICATION_EVENT: Int = 10;
pub const AAUDIO_USAGE_ASSISTANCE_ACCESSIBILITY: Int = 11;
pub const AAUDIO_USAGE_ASSISTANCE_NAVIGATION_GUIDANCE: Int = 12;
pub const AAUDIO_USAGE_ASSISTANCE_SONIFICATION: Int = 13;
pub const AAUDIO_USAGE_GAME: Int = 14;
pub const AAUDIO_USAGE_ASSISTANT: Int = 16;
pub const AAUDIO_SYSTEM_USAGE_EMERGENCY: Int = 1000;
pub const AAUDIO_SYSTEM_USAGE_SAFETY: Int = 1001;
pub const AAUDIO_SYSTEM_USAGE_VEHICLE_STATUS: Int = 1002;
pub const AAUDIO_SYSTEM_USAGE_ANNOUNCEMENT: Int = 1003;

// aaudio_content_type_t.
pub const AAUDIO_CONTENT_TYPE_SPEECH: Int = 1;
pub const AAUDIO_CONTENT_TYPE_MUSIC: Int = 2;
pub const AAUDIO_CONTENT_TYPE_MOVIE: Int = 3;
pub const AAUDIO_CONTENT_TYPE_SONIFICATION: Int = 4;

// aaudio_spatialization_behavior_t.
pub const AAUDIO_SPATIALIZATION_BEHAVIOR_AUTO: Int = 1;
pub const AAUDIO_SPATIALIZATION_BEHAVIOR_NEVER: Int = 2;

// aaudio_input_preset_t.
pub const AAUDIO_INPUT_PRESET_GENERIC: Int = 1;
pub const AAUDIO_INPUT_PRESET_CAMCORDER: Int = 5;
pub const AAUDIO_INPUT_PRESET_VOICE_RECOGNITION: Int = 6;
pub const AAUDIO_INPUT_PRESET_VOICE_COMMUNICATION: Int = 7;
pub const AAUDIO_INPUT_PRESET_UNPROCESSED: Int = 9;
pub const AAUDIO_INPUT_PRESET_VOICE_PERFORMANCE: Int = 10;
pub const AAUDIO_INPUT_PRESET_SYSTEM_ECHO_REFERENCE: Int = 1997;
pub const AAUDIO_INPUT_PRESET_SYSTEM_HOTWORD: Int = 1999;

// aaudio_allowed_capture_policy_t.
pub const AAUDIO_ALLOW_CAPTURE_BY_ALL: Int = 1;
pub const AAUDIO_ALLOW_CAPTURE_BY_SYSTEM: Int = 2;
pub const AAUDIO_ALLOW_CAPTURE_BY_NONE: Int = 3;

// aaudio_session_id_t.
pub const AAUDIO_SESSION_ID_NONE: Int = -1;
pub const AAUDIO_SESSION_ID_ALLOCATE: Int = 0;

// aaudio_data_callback_result_t.
pub const AAUDIO_CALLBACK_RESULT_CONTINUE: Int = 0;
pub const AAUDIO_CALLBACK_RESULT_STOP: Int = 1;

// aaudio_channel_mask_t -- single-channel bits (1 << n).
pub const AAUDIO_CHANNEL_INVALID: Int = -1;
pub const AAUDIO_CHANNEL_FRONT_LEFT: Int = 1;
pub const AAUDIO_CHANNEL_FRONT_RIGHT: Int = 2;
pub const AAUDIO_CHANNEL_FRONT_CENTER: Int = 4;
pub const AAUDIO_CHANNEL_LOW_FREQUENCY: Int = 8;
pub const AAUDIO_CHANNEL_BACK_LEFT: Int = 16;
pub const AAUDIO_CHANNEL_BACK_RIGHT: Int = 32;
pub const AAUDIO_CHANNEL_FRONT_LEFT_OF_CENTER: Int = 64;
pub const AAUDIO_CHANNEL_FRONT_RIGHT_OF_CENTER: Int = 128;
pub const AAUDIO_CHANNEL_BACK_CENTER: Int = 256;
pub const AAUDIO_CHANNEL_SIDE_LEFT: Int = 512;
pub const AAUDIO_CHANNEL_SIDE_RIGHT: Int = 1024;
pub const AAUDIO_CHANNEL_TOP_CENTER: Int = 2048;
pub const AAUDIO_CHANNEL_TOP_FRONT_LEFT: Int = 4096;
pub const AAUDIO_CHANNEL_TOP_FRONT_CENTER: Int = 8192;
pub const AAUDIO_CHANNEL_TOP_FRONT_RIGHT: Int = 16384;
pub const AAUDIO_CHANNEL_TOP_BACK_LEFT: Int = 32768;
pub const AAUDIO_CHANNEL_TOP_BACK_CENTER: Int = 65536;
pub const AAUDIO_CHANNEL_TOP_BACK_RIGHT: Int = 131072;
pub const AAUDIO_CHANNEL_TOP_SIDE_LEFT: Int = 262144;
pub const AAUDIO_CHANNEL_TOP_SIDE_RIGHT: Int = 524288;
pub const AAUDIO_CHANNEL_BOTTOM_FRONT_LEFT: Int = 1048576;
pub const AAUDIO_CHANNEL_BOTTOM_FRONT_CENTER: Int = 2097152;
pub const AAUDIO_CHANNEL_BOTTOM_FRONT_RIGHT: Int = 4194304;
pub const AAUDIO_CHANNEL_LOW_FREQUENCY_2: Int = 8388608;
pub const AAUDIO_CHANNEL_FRONT_WIDE_LEFT: Int = 16777216;
pub const AAUDIO_CHANNEL_FRONT_WIDE_RIGHT: Int = 33554432;

// aaudio_channel_mask_t -- named combinations (header computations).
pub const AAUDIO_CHANNEL_MONO: Int = 1;
pub const AAUDIO_CHANNEL_STEREO: Int = 3;
pub const AAUDIO_CHANNEL_2POINT1: Int = 11;
pub const AAUDIO_CHANNEL_TRI: Int = 7;
pub const AAUDIO_CHANNEL_TRI_BACK: Int = 259;
pub const AAUDIO_CHANNEL_3POINT1: Int = 15;
pub const AAUDIO_CHANNEL_2POINT0POINT2: Int = 786435;
pub const AAUDIO_CHANNEL_2POINT1POINT2: Int = 786443;
pub const AAUDIO_CHANNEL_3POINT0POINT2: Int = 786439;
pub const AAUDIO_CHANNEL_3POINT1POINT2: Int = 786447;
pub const AAUDIO_CHANNEL_QUAD: Int = 51;
pub const AAUDIO_CHANNEL_QUAD_SIDE: Int = 1539;
pub const AAUDIO_CHANNEL_SURROUND: Int = 263;
pub const AAUDIO_CHANNEL_PENTA: Int = 55;
pub const AAUDIO_CHANNEL_5POINT1: Int = 63;
pub const AAUDIO_CHANNEL_5POINT1_SIDE: Int = 1551;
pub const AAUDIO_CHANNEL_6POINT1: Int = 319;
pub const AAUDIO_CHANNEL_7POINT1: Int = 1599;
pub const AAUDIO_CHANNEL_5POINT1POINT2: Int = 786495;
pub const AAUDIO_CHANNEL_5POINT1POINT4: Int = 184383;
pub const AAUDIO_CHANNEL_7POINT1POINT2: Int = 788031;
pub const AAUDIO_CHANNEL_7POINT1POINT4: Int = 185919;
pub const AAUDIO_CHANNEL_9POINT1POINT4: Int = 50517567;
pub const AAUDIO_CHANNEL_9POINT1POINT6: Int = 51303999;
pub const AAUDIO_CHANNEL_FRONT_BACK: Int = 260;

// bionic clockid_t values for AAudioStream_getTimestamp (POSIX time.h,
// not AAudio defines -- recorded here because the header names only the
// constants).
pub const AAUDIO_CLOCK_MONOTONIC: Int = 1;
pub const AAUDIO_CLOCK_BOOTTIME: Int = 7;

// =========================================================================
// Probe API
// =========================================================================

/// Probe an explicitly named AAudio library.  Useful for tests: a bogus
/// soname exercises the ABSENT/SKIP classification deterministically even
/// on hosts that ship the library.
/// Complexity: O(load + export set).
pub fn aaudio_probe_named(soname: Str) -> Result[AaudioRuntime, AaudioProbeError]
  requires: soname.len() > 0
{
  let rc = unsafe { xaa_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xaa_error()) };
    if rc == 1 {
      return Err(AaudioProbeError{ kind: AAUDIO_LOAD_ABSENT; message: msg });
    }
    return Err(AaudioProbeError{ kind: AAUDIO_LOAD_ABI; message: msg });
  }
  let missing_count = unsafe { xaa_abi_missing_count() as Int };
  let missing = unsafe { Str::from_c_str(xaa_abi_missing()) };
  return Ok(AaudioRuntime{ missing_exports: missing_count; missing: missing });
}

/// Probe the default runtime (libaaudio.so).  On Android this is the
/// platform itself; on Windows the probe classifies ABSENT (SKIP).
/// Complexity: O(load + export set).
pub fn aaudio_probe() -> Result[AaudioRuntime, AaudioProbeError]
  requires: true
{
  return aaudio_probe_named(AAUDIO_SONAME);
}

/// The last bridge error / missing-export summary (empty when clean).
/// Complexity: O(1).
pub fn aaudio_error() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xaa_error()); }
}

/// True while a runtime handle is held by the bridge.
/// Complexity: O(1).
pub fn aaudio_loaded() -> Bool
  requires: true
{
  let rc = unsafe { xaa_loaded() as Int };
  return rc == 1;
}

/// Release any runtime handle held by the bridge.  Safe when nothing is
/// loaded.
/// Complexity: O(1).
pub fn aaudio_unload()
  requires: true
{
  unsafe { xaa_unload(); }
}

// =========================================================================
// Result / state text helpers (AAudio_convert*ToText)
// =========================================================================

/// ASCII symbol for an aaudio_result_t code (e.g. "AAUDIO_OK").
/// Complexity: O(1).
pub fn result_to_text(code: Int) -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xaa_convert_result_to_text(code as Int32)); }
}

/// ASCII symbol for an aaudio_stream_state_t value.
/// Complexity: O(1).
pub fn stream_state_to_text(state: Int) -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xaa_convert_stream_state_to_text(state as Int32)); }
}

// =========================================================================
// StreamBuilder surface
// =========================================================================

pub type StreamBuilder = {
  handle: Int;
}

pub type AaudioStream = {
  handle: Int;
}

/// Create a StreamBuilder.  Works without any audio device (pure
/// allocation); close with `builder_delete`.
/// Complexity: O(1).
pub fn builder_create() -> Result[StreamBuilder, AaudioProbeError]
  requires: true
{
  let h = unsafe { xaa_builder_create() as Int };
  if h == 0 {
    let msg = unsafe { Str::from_c_str(xaa_error()) };
    let loaded = unsafe { xaa_loaded() as Int };
    if loaded == 1 {
      return Err(AaudioProbeError{ kind: AAUDIO_LOAD_ABI; message: msg });
    }
    return Err(AaudioProbeError{ kind: AAUDIO_LOAD_ABSENT; message: msg });
  }
  return Ok(StreamBuilder{ handle: h });
}

/// Delete a StreamBuilder.
/// Complexity: O(1).
pub fn builder_delete(builder: StreamBuilder) -> Int
  requires: true
{
  unsafe { return xaa_builder_delete(builder.handle as Int64) as Int; }
}

/// Request an audio device id (AAUDIO_UNSPECIFIED = default device).
/// Complexity: O(1).
pub fn builder_set_device_id(builder: &StreamBuilder, device_id: Int)
  requires: true
{
  unsafe { xaa_builder_set_device_id(builder.handle as Int64, device_id as Int32); }
}

/// Declare the calling package name (usually Context#getPackageName()).
/// Complexity: O(1).
pub fn builder_set_package_name(builder: &StreamBuilder, name: Str)
  requires: name.len() > 0
{
  unsafe { xaa_builder_set_package_name(builder.handle as Int64, name.c_str()); }
}

/// Declare the calling attribution tag.
/// Complexity: O(1).
pub fn builder_set_attribution_tag(builder: &StreamBuilder, tag: Str)
  requires: true
{
  unsafe { xaa_builder_set_attribution_tag(builder.handle as Int64, tag.c_str()); }
}

/// Request a sample rate in Hz.
/// Complexity: O(1).
pub fn builder_set_sample_rate(builder: &StreamBuilder, sample_rate: Int)
  requires: true
{
  unsafe { xaa_builder_set_sample_rate(builder.handle as Int64, sample_rate as Int32); }
}

/// Request a channel count.
/// Complexity: O(1).
pub fn builder_set_channel_count(builder: &StreamBuilder, channel_count: Int)
  requires: true
{
  unsafe { xaa_builder_set_channel_count(builder.handle as Int64, channel_count as Int32); }
}

/// Request samples-per-frame (identical to channel count; deprecated).
/// Complexity: O(1).
pub fn builder_set_samples_per_frame(builder: &StreamBuilder, samples_per_frame: Int)
  requires: true
{
  unsafe { xaa_builder_set_samples_per_frame(builder.handle as Int64, samples_per_frame as Int32); }
}

/// Request a sample data format (AAUDIO_FORMAT_*).
/// Complexity: O(1).
pub fn builder_set_format(builder: &StreamBuilder, format: Int)
  requires: true
{
  unsafe { xaa_builder_set_format(builder.handle as Int64, format as Int32); }
}

/// Request a sharing mode (AAUDIO_SHARING_MODE_*).
/// Complexity: O(1).
pub fn builder_set_sharing_mode(builder: &StreamBuilder, sharing_mode: Int)
  requires: true
{
  unsafe { xaa_builder_set_sharing_mode(builder.handle as Int64, sharing_mode as Int32); }
}

/// Request a direction (AAUDIO_DIRECTION_*).
/// Complexity: O(1).
pub fn builder_set_direction(builder: &StreamBuilder, direction: Int)
  requires: true
{
  unsafe { xaa_builder_set_direction(builder.handle as Int64, direction as Int32); }
}

/// Request a buffer capacity in frames.
/// Complexity: O(1).
pub fn builder_set_buffer_capacity_in_frames(builder: &StreamBuilder, num_frames: Int)
  requires: true
{
  unsafe { xaa_builder_set_buffer_capacity_in_frames(builder.handle as Int64, num_frames as Int32); }
}

/// Request a performance mode (AAUDIO_PERFORMANCE_MODE_*).
/// Complexity: O(1).
pub fn builder_set_performance_mode(builder: &StreamBuilder, mode: Int)
  requires: true
{
  unsafe { xaa_builder_set_performance_mode(builder.handle as Int64, mode as Int32); }
}

/// Set the intended usage (AAUDIO_USAGE_*).
/// Complexity: O(1).
pub fn builder_set_usage(builder: &StreamBuilder, usage: Int)
  requires: true
{
  unsafe { xaa_builder_set_usage(builder.handle as Int64, usage as Int32); }
}

/// Set the content type (AAUDIO_CONTENT_TYPE_*).
/// Complexity: O(1).
pub fn builder_set_content_type(builder: &StreamBuilder, content_type: Int)
  requires: true
{
  unsafe { xaa_builder_set_content_type(builder.handle as Int64, content_type as Int32); }
}

/// Set the spatialization behavior (AAUDIO_SPATIALIZATION_BEHAVIOR_*).
/// Complexity: O(1).
pub fn builder_set_spatialization_behavior(builder: &StreamBuilder, behavior: Int)
  requires: true
{
  unsafe { xaa_builder_set_spatialization_behavior(builder.handle as Int64, behavior as Int32); }
}

/// Declare whether the content is already spatialized (0/1).
/// Complexity: O(1).
pub fn builder_set_is_content_spatialized(builder: &StreamBuilder, is_spatialized: Int)
  requires: true
{
  unsafe { xaa_builder_set_is_content_spatialized(builder.handle as Int64, is_spatialized as Int32); }
}

/// Set the input (capture) preset (AAUDIO_INPUT_PRESET_*).
/// Complexity: O(1).
pub fn builder_set_input_preset(builder: &StreamBuilder, input_preset: Int)
  requires: true
{
  unsafe { xaa_builder_set_input_preset(builder.handle as Int64, input_preset as Int32); }
}

/// Set the allowed capture policy (AAUDIO_ALLOW_CAPTURE_BY_*).
/// Complexity: O(1).
pub fn builder_set_allowed_capture_policy(builder: &StreamBuilder, capture_policy: Int)
  requires: true
{
  unsafe { xaa_builder_set_allowed_capture_policy(builder.handle as Int64, capture_policy as Int32); }
}

/// Set the requested session id (AAUDIO_SESSION_ID_*).
/// Complexity: O(1).
pub fn builder_set_session_id(builder: &StreamBuilder, session_id: Int)
  requires: true
{
  unsafe { xaa_builder_set_session_id(builder.handle as Int64, session_id as Int32); }
}

/// Mark an input stream privacy sensitive (0/1).
/// Complexity: O(1).
pub fn builder_set_privacy_sensitive(builder: &StreamBuilder, privacy_sensitive: Int)
  requires: true
{
  unsafe { xaa_builder_set_privacy_sensitive(builder.handle as Int64, privacy_sensitive as Int32); }
}

/// Request a data-callback buffer size in frames.
/// Complexity: O(1).
pub fn builder_set_frames_per_data_callback(builder: &StreamBuilder, num_frames: Int)
  requires: true
{
  unsafe { xaa_builder_set_frames_per_data_callback(builder.handle as Int64, num_frames as Int32); }
}

/// Set the audio channel mask (AAUDIO_CHANNEL_*).
/// Complexity: O(1).
pub fn builder_set_channel_mask(builder: &StreamBuilder, channel_mask: Int)
  requires: true
{
  unsafe { xaa_builder_set_channel_mask(builder.handle as Int64, channel_mask as Int32); }
}

/// Install the bridge's top-level data callback (direct handoff; silence
/// filling for output streams).  The callbacks never capture an
/// environment; counters are read via `data_callback_count`.
/// Complexity: O(1).
pub fn builder_set_data_callback(builder: &StreamBuilder)
  requires: true
{
  unsafe { xaa_builder_set_data_callback(builder.handle as Int64); }
}

/// Install the bridge's top-level error callback (direct handoff).
/// Complexity: O(1).
pub fn builder_set_error_callback(builder: &StreamBuilder)
  requires: true
{
  unsafe { xaa_builder_set_error_callback(builder.handle as Int64); }
}

/// Open a stream from the builder's options.  On success the typed open
/// result is AAUDIO_OK; on a typed failure the code is read back with
/// `open_result` (best-effort on emulators without audio output).
/// Complexity: O(open).
pub fn builder_open_stream(builder: &StreamBuilder) -> Result[AaudioStream, AaudioProbeError]
  requires: true
{
  let h = unsafe { xaa_builder_open_stream(builder.handle as Int64) as Int };
  if h == 0 {
    let rc = unsafe { xaa_open_result() as Int };
    let msg = unsafe { Str::from_c_str(xaa_error()) };
    return Err(AaudioProbeError{ kind: AAUDIO_LOAD_ABI; message: to_string(rc) + ": " + msg });
  }
  return Ok(AaudioStream{ handle: h });
}

/// The aaudio_result_t of the most recent open attempt.
/// Complexity: O(1).
pub fn open_result() -> Int
  requires: true
{
  unsafe { return xaa_open_result() as Int; }
}

// =========================================================================
// Stream surface
// =========================================================================

/// Free the audio resources associated with a stream (keep the handle
/// queryable until `stream_close`).
/// Complexity: O(1).
pub fn stream_release(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_release(stream.handle as Int64) as Int; }
}

/// Close the stream (releases everything; the handle is dead after).
/// Complexity: O(1).
pub fn stream_close(stream: AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_close(stream.handle as Int64) as Int; }
}

/// Asynchronously request the stream to start.
/// Complexity: O(1).
pub fn stream_request_start(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_request_start(stream.handle as Int64) as Int; }
}

/// Asynchronously request the stream to pause.
/// Complexity: O(1).
pub fn stream_request_pause(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_request_pause(stream.handle as Int64) as Int; }
}

/// Asynchronously request the stream to flush.
/// Complexity: O(1).
pub fn stream_request_flush(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_request_flush(stream.handle as Int64) as Int; }
}

/// Asynchronously request the stream to stop.
/// Complexity: O(1).
pub fn stream_request_stop(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_request_stop(stream.handle as Int64) as Int; }
}

/// Current client state (AAUDIO_STREAM_STATE_*).
/// Complexity: O(1).
pub fn stream_get_state(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_state(stream.handle as Int64) as Int; }
}

/// Wait until the state no longer matches `input_state`.  Returns the
/// result code; the new state is read back with `stream_wait_state`.
/// Complexity: O(wait).
pub fn stream_wait_for_state_change(stream: &AaudioStream, input_state: Int, timeout_ns: Int) -> Int
  requires: true
{
  unsafe { return xaa_stream_wait_for_state_change(stream.handle as Int64, input_state as Int32, timeout_ns as Int64) as Int; }
}

/// The next state captured by the last waitForStateChange call.
/// Complexity: O(1).
pub fn stream_wait_state() -> Int
  requires: true
{
  unsafe { return xaa_wait_state_value() as Int; }
}

/// Read numFrames into the bridge's internal scratch window (no pointer
/// crosses); returns frames read or a negative error.
/// Complexity: O(read).
pub fn stream_read(stream: &AaudioStream, num_frames: Int, timeout_ns: Int) -> Int
  requires: true
{
  unsafe { return xaa_stream_read(stream.handle as Int64, num_frames as Int32, timeout_ns as Int64) as Int; }
}

/// Write numFrames of silence (bridge-side zero scratch); returns frames
/// written or a negative error.
/// Complexity: O(write).
pub fn stream_write(stream: &AaudioStream, num_frames: Int, timeout_ns: Int) -> Int
  requires: true
{
  unsafe { return xaa_stream_write(stream.handle as Int64, num_frames as Int32, timeout_ns as Int64) as Int; }
}

/// Adjust the buffer size in frames (returns the actual or an error).
/// Complexity: O(1).
pub fn stream_set_buffer_size_in_frames(stream: &AaudioStream, num_frames: Int) -> Int
  requires: true
{
  unsafe { return xaa_stream_set_buffer_size_in_frames(stream.handle as Int64, num_frames as Int32) as Int; }
}

/// Maximum number of frames that can be filled without blocking.
/// Complexity: O(1).
pub fn stream_get_buffer_size_in_frames(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_buffer_size_in_frames(stream.handle as Int64) as Int; }
}

/// Optimal frames per read/write burst.
/// Complexity: O(1).
pub fn stream_get_frames_per_burst(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_frames_per_burst(stream.handle as Int64) as Int; }
}

/// Maximum buffer capacity in frames.
/// Complexity: O(1).
pub fn stream_get_buffer_capacity_in_frames(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_buffer_capacity_in_frames(stream.handle as Int64) as Int; }
}

/// Callback buffer size in frames (or AAUDIO_UNSPECIFIED).
/// Complexity: O(1).
pub fn stream_get_frames_per_data_callback(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_frames_per_data_callback(stream.handle as Int64) as Int; }
}

/// Underrun/overrun count.
/// Complexity: O(1).
pub fn stream_get_xrun_count(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_xrun_count(stream.handle as Int64) as Int; }
}

/// Actual stream sample rate.
/// Complexity: O(1).
pub fn stream_get_sample_rate(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_sample_rate(stream.handle as Int64) as Int; }
}

/// Hardware sample rate (API 34+).
/// Complexity: O(1).
pub fn stream_get_hardware_sample_rate(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_hardware_sample_rate(stream.handle as Int64) as Int; }
}

/// Actual channel count.
/// Complexity: O(1).
pub fn stream_get_channel_count(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_channel_count(stream.handle as Int64) as Int; }
}

/// Hardware channel count (API 34+).
/// Complexity: O(1).
pub fn stream_get_hardware_channel_count(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_hardware_channel_count(stream.handle as Int64) as Int; }
}

/// Actual samples per frame (identical to channel count).
/// Complexity: O(1).
pub fn stream_get_samples_per_frame(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_samples_per_frame(stream.handle as Int64) as Int; }
}

/// Actual device id.
/// Complexity: O(1).
pub fn stream_get_device_id(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_device_id(stream.handle as Int64) as Int; }
}

/// Actual data format (AAUDIO_FORMAT_*).
/// Complexity: O(1).
pub fn stream_get_format(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_format(stream.handle as Int64) as Int; }
}

/// Hardware data format (API 34+).
/// Complexity: O(1).
pub fn stream_get_hardware_format(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_hardware_format(stream.handle as Int64) as Int; }
}

/// Actual sharing mode.
/// Complexity: O(1).
pub fn stream_get_sharing_mode(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_sharing_mode(stream.handle as Int64) as Int; }
}

/// Actual performance mode.
/// Complexity: O(1).
pub fn stream_get_performance_mode(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_performance_mode(stream.handle as Int64) as Int; }
}

/// Stream direction.
/// Complexity: O(1).
pub fn stream_get_direction(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_direction(stream.handle as Int64) as Int; }
}

/// Frames written since creation.
/// Complexity: O(1).
pub fn stream_get_frames_written(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_frames_written(stream.handle as Int64) as Int; }
}

/// Frames read since creation.
/// Complexity: O(1).
pub fn stream_get_frames_read(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_frames_read(stream.handle as Int64) as Int; }
}

/// Session id (AAUDIO_SESSION_ID_NONE when none).
/// Complexity: O(1).
pub fn stream_get_session_id(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_session_id(stream.handle as Int64) as Int; }
}

/// Query the presentation timestamp.  Returns the result code; the frame
/// position and time are read back with `stream_timestamp_frames` /
/// `stream_timestamp_nanos`.
/// Complexity: O(1).
pub fn stream_get_timestamp(stream: &AaudioStream, clock_id: Int) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_timestamp(stream.handle as Int64, clock_id as Int32) as Int; }
}

/// Frame position captured by the last successful getTimestamp.
/// Complexity: O(1).
pub fn stream_timestamp_frames() -> Int
  requires: true
{
  unsafe { return xaa_timestamp_frames() as Int; }
}

/// Time in nanoseconds captured by the last successful getTimestamp.
/// Complexity: O(1).
pub fn stream_timestamp_nanos() -> Int
  requires: true
{
  unsafe { return xaa_timestamp_nanos() as Int; }
}

/// The stream's usage (AAUDIO_USAGE_*).
/// Complexity: O(1).
pub fn stream_get_usage(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_usage(stream.handle as Int64) as Int; }
}

/// The stream's content type (AAUDIO_CONTENT_TYPE_*).
/// Complexity: O(1).
pub fn stream_get_content_type(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_content_type(stream.handle as Int64) as Int; }
}

/// The stream's spatialization behavior.
/// Complexity: O(1).
pub fn stream_get_spatialization_behavior(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_spatialization_behavior(stream.handle as Int64) as Int; }
}

/// Whether the stream content is spatialized (0/1).
/// Complexity: O(1).
pub fn stream_is_content_spatialized(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_is_content_spatialized(stream.handle as Int64) as Int; }
}

/// The stream's input preset (AAUDIO_INPUT_PRESET_*).
/// Complexity: O(1).
pub fn stream_get_input_preset(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_input_preset(stream.handle as Int64) as Int; }
}

/// The stream's allowed capture policy.
/// Complexity: O(1).
pub fn stream_get_allowed_capture_policy(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_allowed_capture_policy(stream.handle as Int64) as Int; }
}

/// Whether the stream is privacy sensitive (0/1).
/// Complexity: O(1).
pub fn stream_is_privacy_sensitive(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_is_privacy_sensitive(stream.handle as Int64) as Int; }
}

/// The stream's channel mask (AAUDIO_CHANNEL_* or AAUDIO_UNSPECIFIED).
/// Complexity: O(1).
pub fn stream_get_channel_mask(stream: &AaudioStream) -> Int
  requires: true
{
  unsafe { return xaa_stream_get_channel_mask(stream.handle as Int64) as Int; }
}

// =========================================================================
// Callback counters (evidence that the top-level stubs fired)
// =========================================================================

/// Number of times the bridge data callback has fired.
/// Complexity: O(1).
pub fn data_callback_count() -> Int
  requires: true
{
  unsafe { return xaa_data_callback_count() as Int; }
}

/// Number of times the bridge error callback has fired.
/// Complexity: O(1).
pub fn error_callback_count() -> Int
  requires: true
{
  unsafe { return xaa_error_callback_count() as Int; }
}
