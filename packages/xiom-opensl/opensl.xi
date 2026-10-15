// XIOM -- xiom.opensl: Android legacy-audio bindings (NDK r27b).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: runtime probe + functional engine head for the A6 legacy tail
// of the Android SDK100 program (docs/ANDROID-SDK100.md), backed by the
// vendored bridge `src/opensl_bridge.c` (compiled with `--c-source`; see
// port.args.json).  The bridge resolves the three platform libraries at
// RUNTIME (dlopen on Android/Linux, LoadLibraryA on Windows -- where
// everything classifies ABSENT) and verifies the declared export sets:
//
//   libOpenSLES.so  -- OpenSL ES (SLES/OpenSLES.h + OpenSLES_Android.h):
//                      slCreateEngine, slQueryNumSupportedEngineInterfaces,
//                      slQuerySupportedEngineInterfaces + the 53 SL_IID_*
//                      interface-ID GLOBALS (runtime GUIDs).
//   libOpenMAXAL.so -- OpenMAX AL (OMXAL/OpenMAXAL.h): xaCreateEngine,
//                      xaQueryNumSupportedEngineInterfaces,
//                      xaQuerySupportedEngineInterfaces + the 41 XA_IID_*
//                      globals.
//   libamidi.so     -- AMidi (amidi/AMidi.h): the 14 declared functions.
//
// SLES interface-table model (see SPEC.md): the flat export surface is
// ONLY that entry trio -- the rest of the API is object/interface-based.
// SL_IID_* symbols are the runtime GUIDs used to query interfaces off
// objects; an SLObjectItf is a handle whose vtable (Realize/GetState/
// Destroy/...) is called through the handle.  All vtable calls stay in
// C (points never cross; B-25 discipline); handles cross as Int.
//
// Classification (the suite maps it to markers):
//   OPENSL_LOAD_ABSENT -> SKIP  (runtime missing; CI stays green)
//   OPENSL_LOAD_ABI    -> FAIL  (partial load / exports broken; never a
//                                silent SKIP)
//
// Naming note: this package is the A6 legacy tail home (OpenSL ES /
// OpenMAX AL / AMidi); the name is rename-safe pending the naming gate
// of docs/prep/android-wave.md.

module xiom.opensl

extern "C" {
  fn xo_load_named(opensles_soname: *UInt8, openmaxal_soname: *UInt8, amidi_soname: *UInt8) -> Int32;
  fn xo_load() -> Int32;
  fn xo_error() -> *UInt8;
  fn xo_loaded_mask() -> Int32;
  fn xo_sl_missing_count() -> Int32;
  fn xo_sl_missing() -> *UInt8;
  fn xo_xa_missing_count() -> Int32;
  fn xo_xa_missing() -> *UInt8;
  fn xo_amidi_missing_count() -> Int32;
  fn xo_amidi_missing() -> *UInt8;
  fn xo_sl_iid_null_values() -> Int32;
  fn xo_sl_engine_lifecycle() -> Int32;
  fn xo_sl_engine_last_state() -> Int32;
  fn xo_sl_query_num_engine_interfaces() -> Int32;
  fn xo_sl_query_engine_interfaces_ok() -> Int32;
  fn xo_amidi_get_device_info_present() -> Int32;
  fn xo_amidi_device_count_attempt() -> Int32;
  fn xo_unload();
}

// =========================================================================
// Identity and classification
// =========================================================================

pub const OPENSLES_SONAME: Str = "libOpenSLES.so";
pub const OPENMAXAL_SONAME: Str = "libOpenMAXAL.so";
pub const AMIDI_SONAME: Str = "libamidi.so";

// Probe outcome kinds.
pub const OPENSL_LOAD_ABSENT: Int = 0; // runtime libs missing -> SKIP
pub const OPENSL_LOAD_ABI: Int = 1;    // present but exports broken -> FAIL

// Loaded-lib bitmask (xo_loaded_mask).
pub const OPENSL_LOADED_OPENSLES: Int = 1;
pub const OPENSL_LOADED_OPENMAXAL: Int = 2;
pub const OPENSL_LOADED_AMIDI: Int = 4;

pub type OpenSlProbeError = {
  kind: Int;
  message: Str;
}

pub type OpenSlRuntime = {
  loaded_mask: Int;     // bit0 OpenSL ES, bit1 OpenMAX AL, bit2 AMidi
  sl_missing: Int;      // unresolved OpenSLES exports (-1: lib not loaded)
  xa_missing: Int;      // unresolved OpenMAXAL exports (-1: lib not loaded)
  amidi_missing: Int;   // unresolved AMidi exports (-1: lib not loaded)
}

// =========================================================================
// SLresult family (SLES/OpenSLES.h)
// =========================================================================

pub const SL_RESULT_SUCCESS: Int = 0x00000000;
pub const SL_RESULT_PRECONDITIONS_VIOLATED: Int = 0x00000001;
pub const SL_RESULT_PARAMETER_INVALID: Int = 0x00000002;
pub const SL_RESULT_MEMORY_FAILURE: Int = 0x00000003;
pub const SL_RESULT_RESOURCE_ERROR: Int = 0x00000004;
pub const SL_RESULT_RESOURCE_LOST: Int = 0x00000005;
pub const SL_RESULT_IO_ERROR: Int = 0x00000006;
pub const SL_RESULT_BUFFER_INSUFFICIENT: Int = 0x00000007;
pub const SL_RESULT_CONTENT_CORRUPTED: Int = 0x00000008;
pub const SL_RESULT_CONTENT_UNSUPPORTED: Int = 0x00000009;
pub const SL_RESULT_CONTENT_NOT_FOUND: Int = 0x0000000A;
pub const SL_RESULT_PERMISSION_DENIED: Int = 0x0000000B;
pub const SL_RESULT_FEATURE_UNSUPPORTED: Int = 0x0000000C;
pub const SL_RESULT_INTERNAL_ERROR: Int = 0x0000000D;
pub const SL_RESULT_UNKNOWN_ERROR: Int = 0x0000000E;
pub const SL_RESULT_OPERATION_ABORTED: Int = 0x0000000F;
pub const SL_RESULT_CONTROL_LOST: Int = 0x00000010;

// =========================================================================
// Key SL_* constants (SLES/OpenSLES.h; transcribed from the r27b oracle)
// =========================================================================

pub const SL_BOOLEAN_FALSE: Int = 0;
pub const SL_BOOLEAN_TRUE: Int = 1;

pub const SL_MILLIBEL_MAX: Int = 0x7FFF;
pub const SL_MILLIBEL_MIN: Int = -32768; // (-SL_MILLIBEL_MAX-1)
pub const SL_MILLIHERTZ_MAX: Int = 0xFFFFFFFF;
pub const SL_MILLIMETER_MAX: Int = 0x7FFFFFFF;

// Object states.
pub const SL_OBJECT_STATE_UNREALIZED: Int = 0x00000001;
pub const SL_OBJECT_STATE_REALIZED: Int = 0x00000002;
pub const SL_OBJECT_STATE_SUSPENDED: Int = 0x00000003;

// Object events.
pub const SL_OBJECT_EVENT_RUNTIME_ERROR: Int = 0x00000001;
pub const SL_OBJECT_EVENT_ASYNC_TERMINATION: Int = 0x00000002;
pub const SL_OBJECT_EVENT_RESOURCES_LOST: Int = 0x00000003;
pub const SL_OBJECT_EVENT_RESOURCES_AVAILABLE: Int = 0x00000004;
pub const SL_OBJECT_EVENT_ITF_CONTROL_TAKEN: Int = 0x00000005;
pub const SL_OBJECT_EVENT_ITF_CONTROL_RETURNED: Int = 0x00000006;
pub const SL_OBJECT_EVENT_ITF_PARAMETERS_CHANGED: Int = 0x00000007;

// Object IDs.
pub const SL_OBJECTID_ENGINE: Int = 0x00001001;
pub const SL_OBJECTID_LEDDEVICE: Int = 0x00001002;
pub const SL_OBJECTID_VIBRADEVICE: Int = 0x00001003;
pub const SL_OBJECTID_AUDIOPLAYER: Int = 0x00001004;
pub const SL_OBJECTID_AUDIORECORDER: Int = 0x00001005;
pub const SL_OBJECTID_MIDIPLAYER: Int = 0x00001006;
pub const SL_OBJECTID_LISTENER: Int = 0x00001007;
pub const SL_OBJECTID_3DGROUP: Int = 0x00001008;
pub const SL_OBJECTID_OUTPUTMIX: Int = 0x00001009;
pub const SL_OBJECTID_METADATAEXTRACTOR: Int = 0x0000100A;

// Play states + play events.
pub const SL_PLAYSTATE_STOPPED: Int = 0x00000001;
pub const SL_PLAYSTATE_PAUSED: Int = 0x00000002;
pub const SL_PLAYSTATE_PLAYING: Int = 0x00000003;
pub const SL_PLAYEVENT_HEADATEND: Int = 0x00000001;
pub const SL_PLAYEVENT_HEADATMARKER: Int = 0x00000002;
pub const SL_PLAYEVENT_HEADATNEWPOS: Int = 0x00000004;
pub const SL_PLAYEVENT_HEADMOVING: Int = 0x00000008;
pub const SL_PLAYEVENT_HEADSTALLED: Int = 0x00000010;
pub const SL_TIME_UNKNOWN: Int = 0xFFFFFFFF;

// Prefetch status + seek mode.
pub const SL_PREFETCHSTATUS_UNDERFLOW: Int = 0x00000001;
pub const SL_PREFETCHSTATUS_SUFFICIENTDATA: Int = 0x00000002;
pub const SL_PREFETCHSTATUS_OVERFLOW: Int = 0x00000003;
pub const SL_SEEKMODE_FAST: Int = 0x0001;
pub const SL_SEEKMODE_ACCURATE: Int = 0x0002;

// Default device IDs.
pub const SL_DEFAULTDEVICEID_AUDIOINPUT: Int = 0xFFFFFFFF;
pub const SL_DEFAULTDEVICEID_AUDIOOUTPUT: Int = 0xFFFFFFFE;
pub const SL_DEFAULTDEVICEID_LED: Int = 0xFFFFFFFD;
pub const SL_DEFAULTDEVICEID_VIBRA: Int = 0xFFFFFFFC;
pub const SL_DEFAULTDEVICEID_RESERVED1: Int = 0xFFFFFFFB;

// Data locators + formats.
pub const SL_DATALOCATOR_URI: Int = 0x00000001;
pub const SL_DATALOCATOR_ADDRESS: Int = 0x00000002;
pub const SL_DATALOCATOR_IODEVICE: Int = 0x00000003;
pub const SL_DATALOCATOR_OUTPUTMIX: Int = 0x00000004;
pub const SL_DATALOCATOR_RESERVED5: Int = 0x00000005;
pub const SL_DATALOCATOR_BUFFERQUEUE: Int = 0x00000006;
pub const SL_DATALOCATOR_MIDIBUFFERQUEUE: Int = 0x00000007;
pub const SL_DATALOCATOR_RESERVED8: Int = 0x00000008;
pub const SL_DATAFORMAT_MIME: Int = 0x00000001;
pub const SL_DATAFORMAT_PCM: Int = 0x00000002;
pub const SL_BYTEORDER_BIGENDIAN: Int = 0x00000001;
pub const SL_BYTEORDER_LITTLEENDIAN: Int = 0x00000002;

// PCM building blocks (key subset).
pub const SL_SAMPLINGRATE_44_1: Int = 44100000; // milliHertz
pub const SL_SAMPLINGRATE_48: Int = 48000000;
pub const SL_PCMSAMPLEFORMAT_FIXED_16: Int = 0x0010;
pub const SL_SPEAKER_FRONT_LEFT: Int = 0x00000001;
pub const SL_SPEAKER_FRONT_RIGHT: Int = 0x00000002;
pub const SL_SPEAKER_FRONT_CENTER: Int = 0x00000004;

// Priority levels.
pub const SL_PRIORITY_LOWEST: Int = -2147483648;
pub const SL_PRIORITY_VERYLOW: Int = -0x60000000;
pub const SL_PRIORITY_LOW: Int = -0x40000000;
pub const SL_PRIORITY_BELOWNORMAL: Int = -0x20000000;
pub const SL_PRIORITY_NORMAL: Int = 0x00000000;
pub const SL_PRIORITY_ABOVENORMAL: Int = 0x20000000;
pub const SL_PRIORITY_HIGH: Int = 0x40000000;
pub const SL_PRIORITY_VERYHIGH: Int = 0x60000000;
pub const SL_PRIORITY_HIGHEST: Int = 0x7FFFFFFF;

// =========================================================================
// Android extensions (SLES/OpenSLES_Android.h + _AndroidConfiguration.h)
// =========================================================================

pub const SL_ANDROID_PCM_REPRESENTATION_SIGNED_INT: Int = 0x00000001;
pub const SL_ANDROID_PCM_REPRESENTATION_UNSIGNED_INT: Int = 0x00000002;
pub const SL_ANDROID_PCM_REPRESENTATION_FLOAT: Int = 0x00000003;
pub const SL_ANDROID_DATAFORMAT_PCM_EX: Int = 0x00000004;
pub const SL_ANDROID_SPEAKER_NON_POSITIONAL: Int = 0x80000000;
pub const SL_ANDROID_SPEAKER_USE_DEFAULT: Int = 0;
pub const SL_ANDROID_JAVA_PROXY_ROUTING: Int = 0x0001;

// Android buffer-queue item keys + events.
pub const SL_ANDROID_ITEMKEY_NONE: Int = 0x00000000;
pub const SL_ANDROID_ITEMKEY_EOS: Int = 0x00000001;
pub const SL_ANDROID_ITEMKEY_DISCONTINUITY: Int = 0x00000002;
pub const SL_ANDROID_ITEMKEY_BUFFERQUEUEEVENT: Int = 0x00000003;
pub const SL_ANDROID_ITEMKEY_FORMAT_CHANGE: Int = 0x00000004;
pub const SL_ANDROIDBUFFERQUEUEEVENT_NONE: Int = 0x00000000;
pub const SL_ANDROIDBUFFERQUEUEEVENT_PROCESSED: Int = 0x00000001;

// Android data locators.
pub const SL_DATALOCATOR_ANDROIDFD: Int = 0x800007BC;
pub const SL_DATALOCATOR_ANDROIDSIMPLEBUFFERQUEUE: Int = 0x800007BD;
pub const SL_DATALOCATOR_ANDROIDBUFFERQUEUE: Int = 0x800007BE;

// Recording presets.
pub const SL_ANDROID_RECORDING_PRESET_NONE: Int = 0x00000000;
pub const SL_ANDROID_RECORDING_PRESET_GENERIC: Int = 0x00000001;
pub const SL_ANDROID_RECORDING_PRESET_CAMCORDER: Int = 0x00000002;
pub const SL_ANDROID_RECORDING_PRESET_VOICE_RECOGNITION: Int = 0x00000003;
pub const SL_ANDROID_RECORDING_PRESET_VOICE_COMMUNICATION: Int = 0x00000004;
pub const SL_ANDROID_RECORDING_PRESET_UNPROCESSED: Int = 0x00000005;

// Playback stream types.
pub const SL_ANDROID_STREAM_VOICE: Int = 0x00000000;
pub const SL_ANDROID_STREAM_SYSTEM: Int = 0x00000001;
pub const SL_ANDROID_STREAM_RING: Int = 0x00000002;
pub const SL_ANDROID_STREAM_MEDIA: Int = 0x00000003;
pub const SL_ANDROID_STREAM_ALARM: Int = 0x00000004;
pub const SL_ANDROID_STREAM_NOTIFICATION: Int = 0x00000005;

// Performance modes.
pub const SL_ANDROID_PERFORMANCE_NONE: Int = 0x00000000;
pub const SL_ANDROID_PERFORMANCE_LATENCY: Int = 0x00000001;
pub const SL_ANDROID_PERFORMANCE_LATENCY_EFFECTS: Int = 0x00000002;
pub const SL_ANDROID_PERFORMANCE_POWER_SAVING: Int = 0x00000003;

// =========================================================================
// OpenMAX AL constants (OMXAL/OpenMAXAL.h)
// =========================================================================

pub const XA_RESULT_SUCCESS: Int = 0x00000000;
pub const XA_RESULT_PRECONDITIONS_VIOLATED: Int = 0x00000001;
pub const XA_RESULT_PARAMETER_INVALID: Int = 0x00000002;
pub const XA_RESULT_MEMORY_FAILURE: Int = 0x00000003;
pub const XA_RESULT_RESOURCE_ERROR: Int = 0x00000004;
pub const XA_RESULT_RESOURCE_LOST: Int = 0x00000005;
pub const XA_RESULT_IO_ERROR: Int = 0x00000006;
pub const XA_RESULT_BUFFER_INSUFFICIENT: Int = 0x00000007;
pub const XA_RESULT_CONTENT_CORRUPTED: Int = 0x00000008;
pub const XA_RESULT_CONTENT_UNSUPPORTED: Int = 0x00000009;
pub const XA_RESULT_CONTENT_NOT_FOUND: Int = 0x0000000A;
pub const XA_RESULT_PERMISSION_DENIED: Int = 0x0000000B;
pub const XA_RESULT_FEATURE_UNSUPPORTED: Int = 0x0000000C;
pub const XA_RESULT_INTERNAL_ERROR: Int = 0x0000000D;
pub const XA_RESULT_UNKNOWN_ERROR: Int = 0x0000000E;
pub const XA_RESULT_OPERATION_ABORTED: Int = 0x0000000F;
pub const XA_RESULT_CONTROL_LOST: Int = 0x00000010;

pub const XA_BOOLEAN_FALSE: Int = 0;
pub const XA_BOOLEAN_TRUE: Int = 1;
pub const XA_MILLIBEL_MAX: Int = 0x7FFF;
pub const XA_MILLIBEL_MIN: Int = -32768;

pub const XA_OBJECT_STATE_UNREALIZED: Int = 0x00000001;
pub const XA_OBJECT_STATE_REALIZED: Int = 0x00000002;
pub const XA_OBJECT_STATE_SUSPENDED: Int = 0x00000003;

pub const XA_OBJECT_EVENT_RUNTIME_ERROR: Int = 0x00000001;
pub const XA_OBJECT_EVENT_ASYNC_TERMINATION: Int = 0x00000002;
pub const XA_OBJECT_EVENT_RESOURCES_LOST: Int = 0x00000003;
pub const XA_OBJECT_EVENT_RESOURCES_AVAILABLE: Int = 0x00000004;
pub const XA_OBJECT_EVENT_ITF_CONTROL_TAKEN: Int = 0x00000005;
pub const XA_OBJECT_EVENT_ITF_CONTROL_RETURNED: Int = 0x00000006;
pub const XA_OBJECT_EVENT_ITF_PARAMETERS_CHANGED: Int = 0x00000007;

pub const XA_OBJECTID_ENGINE: Int = 0x00000001;
pub const XA_OBJECTID_LEDDEVICE: Int = 0x00000002;
pub const XA_OBJECTID_VIBRADEVICE: Int = 0x00000003;
pub const XA_OBJECTID_MEDIAPLAYER: Int = 0x00000004;
pub const XA_OBJECTID_MEDIARECORDER: Int = 0x00000005;
pub const XA_OBJECTID_RADIODEVICE: Int = 0x00000006;
pub const XA_OBJECTID_OUTPUTMIX: Int = 0x00000007;
pub const XA_OBJECTID_METADATAEXTRACTOR: Int = 0x00000008;
pub const XA_OBJECTID_CAMERADEVICE: Int = 0x00000009;

pub const XA_PLAYSTATE_STOPPED: Int = 0x00000001;
pub const XA_PLAYSTATE_PAUSED: Int = 0x00000002;
pub const XA_PLAYSTATE_PLAYING: Int = 0x00000003;
pub const XA_PLAYEVENT_HEADATEND: Int = 0x00000001;
pub const XA_PLAYEVENT_HEADATMARKER: Int = 0x00000002;
pub const XA_PLAYEVENT_HEADATNEWPOS: Int = 0x00000004;
pub const XA_PLAYEVENT_HEADMOVING: Int = 0x00000008;
pub const XA_PLAYEVENT_HEADSTALLED: Int = 0x00000010;
pub const XA_TIME_UNKNOWN: Int = 0xFFFFFFFF;

pub const XA_DEFAULTDEVICEID_AUDIOINPUT: Int = 0xFFFFFFFF;
pub const XA_DEFAULTDEVICEID_AUDIOOUTPUT: Int = 0xFFFFFFFE;
pub const XA_DEFAULTDEVICEID_LED: Int = 0xFFFFFFFD;
pub const XA_DEFAULTDEVICEID_VIBRA: Int = 0xFFFFFFFC;
pub const XA_DEFAULTDEVICEID_CAMERA: Int = 0xFFFFFFFB;

pub const XA_DATAFORMAT_MIME: Int = 0x00000001;
pub const XA_DATAFORMAT_PCM: Int = 0x00000002;
pub const XA_DATAFORMAT_RAWIMAGE: Int = 0x00000003;
pub const XA_DATALOCATOR_URI: Int = 0x00000001;
pub const XA_DATALOCATOR_ADDRESS: Int = 0x00000002;
pub const XA_DATALOCATOR_IODEVICE: Int = 0x00000003;
pub const XA_DATALOCATOR_OUTPUTMIX: Int = 0x00000004;
pub const XA_DATALOCATOR_NATIVEDISPLAY: Int = 0x00000005;
pub const XA_DATALOCATOR_RESERVED6: Int = 0x00000006;
pub const XA_DATALOCATOR_RESERVED7: Int = 0x00000007;
pub const XA_BYTEORDER_BIGENDIAN: Int = 0x00000001;
pub const XA_BYTEORDER_LITTLEENDIAN: Int = 0x00000002;
pub const XA_ENGINEOPTION_THREADSAFE: Int = 0x00000001;
pub const XA_ENGINEOPTION_LOSSOFCONTROL: Int = 0x00000002;

pub const XA_IODEVICE_AUDIOINPUT: Int = 0x00000001;
pub const XA_IODEVICE_LEDARRAY: Int = 0x00000002;
pub const XA_IODEVICE_VIBRA: Int = 0x00000003;
pub const XA_IODEVICE_CAMERA: Int = 0x00000004;
pub const XA_IODEVICE_RADIO: Int = 0x00000005;

pub const XA_SAMPLINGRATE_44_1: Int = 44100000; // milliHertz
pub const XA_SAMPLINGRATE_48: Int = 48000000;
pub const XA_PCMSAMPLEFORMAT_FIXED_16: Int = 0x0010;

pub const XA_PRIORITY_LOWEST: Int = -2147483648;
pub const XA_PRIORITY_NORMAL: Int = 0x00000000;
pub const XA_PRIORITY_HIGHEST: Int = 0x7FFFFFFF;

// =========================================================================
// AMidi constants (amidi/AMidi.h + media/NdkMediaError.h)
// =========================================================================

pub const AMIDI_OPCODE_DATA: Int = 1;
pub const AMIDI_OPCODE_FLUSH: Int = 2;

pub const AMIDI_DEVICE_TYPE_USB: Int = 1;
pub const AMIDI_DEVICE_TYPE_VIRTUAL: Int = 2;
pub const AMIDI_DEVICE_TYPE_BLUETOOTH: Int = 3;

pub const AMIDI_DEVICE_PROTOCOL_UMP_USE_MIDI_CI: Int = 0;
pub const AMIDI_DEVICE_PROTOCOL_UMP_MIDI_1_0_UP_TO_64_BITS: Int = 1;
pub const AMIDI_DEVICE_PROTOCOL_UMP_MIDI_1_0_UP_TO_64_BITS_AND_JRTS: Int = 2;
pub const AMIDI_DEVICE_PROTOCOL_UMP_MIDI_1_0_UP_TO_128_BITS: Int = 3;
pub const AMIDI_DEVICE_PROTOCOL_UMP_MIDI_1_0_UP_TO_128_BITS_AND_JRTS: Int = 4;
pub const AMIDI_DEVICE_PROTOCOL_UMP_MIDI_2_0: Int = 17;
pub const AMIDI_DEVICE_PROTOCOL_UMP_MIDI_2_0_AND_JRTS: Int = 18;
pub const AMIDI_DEVICE_PROTOCOL_UNKNOWN: Int = -1;

// media_status_t subset relevant to the AMidi surface.
pub const AMEDIA_OK: Int = 0;
pub const AMEDIA_ERROR_BASE: Int = -10000;
pub const AMEDIA_ERROR_UNKNOWN: Int = -10000;
pub const AMEDIA_ERROR_MALFORMED: Int = -10001;
pub const AMEDIA_ERROR_UNSUPPORTED: Int = -10002;
pub const AMEDIA_ERROR_INVALID_OBJECT: Int = -10003;
pub const AMEDIA_ERROR_INVALID_PARAMETER: Int = -10004;
pub const AMEDIA_ERROR_INVALID_OPERATION: Int = -10005;
pub const AMEDIA_ERROR_END_OF_STREAM: Int = -10006;
pub const AMEDIA_ERROR_IO: Int = -10007;
pub const AMEDIA_ERROR_WOULD_BLOCK: Int = -10008;

// =========================================================================
// Probe API
// =========================================================================

/// Probe explicitly named legacy-audio libraries.  Useful for tests: a
/// bogus trio exercises the ABSENT/SKIP classification deterministically
/// even on hosts that ship the libraries.
/// Complexity: O(load + 114-symbol export set).
pub fn opensl_probe_named(opensles_soname: Str, openmaxal_soname: Str, amidi_soname: Str) -> Result[OpenSlRuntime, OpenSlProbeError]
  requires: opensles_soname.len() > 0
  requires: openmaxal_soname.len() > 0
  requires: amidi_soname.len() > 0
{
  let rc = unsafe { xo_load_named(opensles_soname.c_str(), openmaxal_soname.c_str(), amidi_soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xo_error()) };
    if rc == 1 {
      return Err(OpenSlProbeError{ kind: OPENSL_LOAD_ABSENT; message: msg });
    }
    return Err(OpenSlProbeError{ kind: OPENSL_LOAD_ABI; message: msg });
  }
  return Ok(OpenSlRuntime{
    loaded_mask: unsafe { xo_loaded_mask() as Int };
    sl_missing: unsafe { xo_sl_missing_count() as Int };
    xa_missing: unsafe { xo_xa_missing_count() as Int };
    amidi_missing: unsafe { xo_amidi_missing_count() as Int };
  });
}

/// Probe the default runtime (libOpenSLES.so + libOpenMAXAL.so +
/// libamidi.so).  On Android these are the platform libraries; on
/// Windows the probe classifies ABSENT (SKIP).
/// Complexity: O(load + export set).
pub fn opensl_probe() -> Result[OpenSlRuntime, OpenSlProbeError]
  requires: true
{
  return opensl_probe_named(OPENSLES_SONAME, OPENMAXAL_SONAME, AMIDI_SONAME);
}

/// The last bridge error / missing-export summary (empty when clean).
/// Complexity: O(1).
pub fn opensl_error() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xo_error()); }
}

/// Release any runtime handles held by the bridge.  Safe when nothing is
/// loaded.
/// Complexity: O(1).
pub fn opensl_unload()
  requires: true
{
  unsafe { xo_unload(); }
}

// =========================================================================
// OpenSL ES functional head (engine lifecycle + interface-table probes)
//
// Every vtable call happens inside the C bridge; the module only sees
// Int statuses and the recorded state value.
// =========================================================================

/// Run the full engine lifecycle: slCreateEngine -> non-null ObjectItf ->
/// Realize(SL_BOOLEAN_FALSE) -> GetState -> Destroy (all through the
/// C-side vtable).  Returns 0 on success; -1 unresolved, -2 create
/// failed, -3 realize failed, -4 state not SL_OBJECT_STATE_REALIZED.
/// The observed state is readable via `sl_engine_last_state`.
/// Complexity: O(create + realize + destroy).
pub fn sl_engine_lifecycle() -> Int
  requires: true
{
  unsafe { return xo_sl_engine_lifecycle() as Int; }
}

/// The SL_OBJECT_STATE_* value observed after the last successful
/// Realize (0 when the lifecycle has not run).
/// Complexity: O(1).
pub fn sl_engine_last_state() -> Int
  requires: true
{
  unsafe { return xo_sl_engine_last_state() as Int; }
}

/// slQueryNumSupportedEngineInterfaces: number of engine interfaces the
/// runtime reports (-1 unresolved, -2 call failed).
/// Complexity: O(1).
pub fn sl_query_num_engine_interfaces() -> Int
  requires: true
{
  unsafe { return xo_sl_query_num_engine_interfaces() as Int; }
}

/// slQuerySupportedEngineInterfaces over every index: count of queries
/// that returned SL_RESULT_SUCCESS with a non-null SLInterfaceID.
/// Equals the query-num count on a healthy runtime.
/// Complexity: O(num engine interfaces).
pub fn sl_query_engine_interfaces_ok() -> Int
  requires: true
{
  unsafe { return xo_sl_query_engine_interfaces_ok() as Int; }
}

/// Count SL_IID_* globals whose stored interface-ID pointer is NULL
/// (0 = the whole interface-ID table is live; a strong ABI signal).
/// Complexity: O(53).
pub fn sl_iid_null_values() -> Int
  requires: true
{
  unsafe { return xo_sl_iid_null_values() as Int; }
}

// =========================================================================
// AMidi head
// =========================================================================

/// Whether this runtime exports the `AMidi_getDeviceInfo` extension
/// symbol.  NOTE: absent on the r27b oracle AND on the API-36 device
/// libraries (both export exactly the 14 declared core functions);
/// device objects arrive only via the JNI `AMidiDevice_fromJava` route.
/// Complexity: O(1).
pub fn amidi_get_device_info_present() -> Bool
  requires: true
{
  let v = unsafe { xo_amidi_get_device_info_present() as Int };
  return v == 1;
}

/// Device-count attempt through `AMidi_getDeviceInfo`.  Outcomes:
/// -1 = API absent (the RECORDED outcome on the r27b oracle / API-36
/// device; not native-enumerable without JNI), -2 = symbol present but
/// its ABI is beyond the r27b oracle (unverified), >=0 = reported
/// device count.
/// Complexity: O(1).
pub fn amidi_device_count_attempt() -> Int
  requires: true
{
  unsafe { return xo_amidi_device_count_attempt() as Int; }
}
