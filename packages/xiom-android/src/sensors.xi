// XIOM -- xiom.android.sensors: A4 sensors head (W2d-A4).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// SCOPE: android/sensor.h of NDK r27b (docs/ANDROID-SDK100.md slice A4;
// wave brief docs/prep/android-wave.md).  32 platform exports:
//
//   ASensorManager_*      (12) getInstance/getInstanceForPackage/
//                              getSensorList/getDynamicSensorList/
//                              getDefaultSensor(+Ex)/createEventQueue/
//                              destroyEventQueue + the direct-channel
//                              trio + configureDirectReport
//   ASensorEventQueue_*   (7)  registerSensor/enableSensor/
//                              disableSensor/setEventRate/hasEvents/
//                              getEvents/requestAdditionalInfoEvents
//   ASensor_*             (13) the whole metadata surface incl.
//                              isWakeUpSensor + the direct-channel
//                              query
//
// The event queue integrates with ALooper exactly like the A2 heads
// (direct-handoff handlers).  getEvents reads into bridge-side owned
// ASensorEvent slots (104-byte struct, byte-xact per the on-device
// sizeof gate) and the module exposes typed per-slot accessors; float
// payloads cross as IEEE-754 binary32 bits and are rebuilt with
// android_f32_from_bits (B-12-safe path).
//
// ASensorManager_getInstance works from ANY process (shell apps too) --
// the on-device probe enumerates the emulator's virtual sensors and runs
// the full event-queue path (enable/register -> poll -> getEvents ->
// disable), or proves the null path when a device has no sensors.
//
// PROVENANCE: header oracle = NDK r27b android/sensor.h (Apache-2.0);
// constant transcription generated + gated by
// docs/repro/gen-a3a4-consts.ps1.

module xiom.android.sensors

use xiom.android;
use xiom.android.lifecycle;

extern "C" {
  fn xa_sensor_manager_get_instance() -> Int64;
  fn xa_sensor_manager_get_instance_for_package(package_name: *UInt8) -> Int64;
  fn xa_sensor_manager_get_sensor_list(manager: Int64) -> Int32;
  fn xa_sensor_manager_get_dynamic_sensor_list(manager: Int64) -> Int32;
  fn xa_sensor_list_at(which: Int32, index: Int32) -> Int64;
  fn xa_sensor_manager_get_default_sensor(manager: Int64, sensor_type: Int32) -> Int64;
  fn xa_sensor_manager_get_default_sensor_ex(manager: Int64, sensor_type: Int32,
                                             wake_up: Int32) -> Int64;
  fn xa_sensor_manager_create_event_queue(manager: Int64, looper: Int64, ident: Int32,
                                          cb: fn(Int32, Int32, Int) -> Int32,
                                          data: Int64) -> Int64;
  fn xa_sensor_manager_create_event_queue_ident(manager: Int64, looper: Int64,
                                                ident: Int32) -> Int64;
  fn xa_sensor_manager_destroy_event_queue(manager: Int64, queue: Int64) -> Int32;
  fn xa_sensor_manager_create_shared_memory_direct_channel(manager: Int64, fd: Int32,
                                                           size: Int64) -> Int32;
  fn xa_sensor_manager_create_hardware_buffer_direct_channel(manager: Int64, hwb: Int64,
                                                             size: Int64) -> Int32;
  fn xa_sensor_manager_destroy_direct_channel(manager: Int64, channel_id: Int32) -> Int32;
  fn xa_sensor_manager_configure_direct_report(manager: Int64, sensor: Int64,
                                               channel_id: Int32, rate_level: Int32) -> Int32;
  fn xa_sensor_event_queue_register_sensor(queue: Int64, sensor: Int64,
                                           sampling_period_us: Int32,
                                           max_report_latency_us: Int64) -> Int32;
  fn xa_sensor_event_queue_enable_sensor(queue: Int64, sensor: Int64) -> Int32;
  fn xa_sensor_event_queue_disable_sensor(queue: Int64, sensor: Int64) -> Int32;
  fn xa_sensor_event_queue_set_event_rate(queue: Int64, sensor: Int64, usec: Int32) -> Int32;
  fn xa_sensor_event_queue_has_events(queue: Int64) -> Int32;
  fn xa_sensor_event_queue_request_additional_info_events(queue: Int64,
                                                          enable: Int32) -> Int32;
  fn xa_sensor_event_queue_read(queue: Int64, max_count: Int32) -> Int32;
  fn xa_sensor_event_version(index: Int32) -> Int32;
  fn xa_sensor_event_sensor(index: Int32) -> Int32;
  fn xa_sensor_event_type(index: Int32) -> Int32;
  fn xa_sensor_event_timestamp(index: Int32) -> Int64;
  fn xa_sensor_event_flags(index: Int32) -> Int32;
  fn xa_sensor_event_x_bits(index: Int32) -> Int64;
  fn xa_sensor_event_y_bits(index: Int32) -> Int64;
  fn xa_sensor_event_z_bits(index: Int32) -> Int64;
  fn xa_sensor_event_scalar_bits(index: Int32) -> Int64;
  fn xa_sensor_event_status(index: Int32) -> Int32;
  fn xa_sensor_event_step_counter(index: Int32) -> Int64;
  fn xa_sensor_event_meta_what(index: Int32) -> Int32;
  fn xa_sensor_event_heart_rate_bpm_bits(index: Int32) -> Int64;
  fn xa_sensor_name(sensor: Int64) -> *UInt8;
  fn xa_sensor_vendor(sensor: Int64) -> *UInt8;
  fn xa_sensor_type(sensor: Int64) -> Int32;
  fn xa_sensor_resolution_bits(sensor: Int64) -> Int64;
  fn xa_sensor_min_delay(sensor: Int64) -> Int32;
  fn xa_sensor_fifo_max_event_count(sensor: Int64) -> Int32;
  fn xa_sensor_fifo_reserved_event_count(sensor: Int64) -> Int32;
  fn xa_sensor_string_type(sensor: Int64) -> *UInt8;
  fn xa_sensor_reporting_mode(sensor: Int64) -> Int32;
  fn xa_sensor_highest_direct_report_rate_level(sensor: Int64) -> Int32;
  fn xa_sensor_handle(sensor: Int64) -> Int32;
  fn xa_sensor_is_wake_up_sensor(sensor: Int64) -> Int32;
  fn xa_sensor_is_direct_channel_type_supported(sensor: Int64,
                                                channel_type: Int32) -> Int32;
}

// =========================================================================
// Sensor objects
// =========================================================================

// The ASensorManager singleton (handle; 0 = unavailable).
pub type SensorManager = {
  handle: Int;
}

// One ASensor from an enumeration or a default-sensor query.
pub type Sensor = {
  handle: Int;
}

// An ASensorEventQueue created on this manager.
pub type SensorEventQueue = {
  handle: Int;
}

// One event from the last queue_read batch; `index` addresses the
// bridge-side owned slot (valid until the next read).
pub type SensorEvent = {
  index: Int;
}

// =========================================================================
// ASensorManager functional head
// =========================================================================

/// The per-process ASensorManager singleton
/// (ASensorManager_getInstance).  Works from any process on a device
/// with a sensor service; absent service -> Err (never a silent OK).
/// Complexity: O(1).
pub fn manager() -> Result[SensorManager, AndroidProbeError]
  requires: true
{
  let h = unsafe { xa_sensor_manager_get_instance() as Int };
  if h == 0 {
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI; message: android_error() });
  }
  return Ok(SensorManager{ handle: h });
}

/// The ASensorManager for a named package
/// (ASensorManager_getInstanceForPackage; package-scoped permission
/// checks).
/// Complexity: O(1).
pub fn manager_for_package(package_name: Str) -> Result[SensorManager, AndroidProbeError]
  requires: package_name.len() > 0
{
  let h = unsafe { xa_sensor_manager_get_instance_for_package(package_name.c_str()) as Int };
  if h == 0 {
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI; message: android_error() });
  }
  return Ok(SensorManager{ handle: h });
}

/// True when the handle refers to a manager (non-zero).
/// Complexity: O(1).
pub fn manager_valid(manager: &SensorManager) -> Bool
  requires: true
{
  return manager.handle != 0;
}

/// True when the handle refers to a sensor (non-zero).
/// Complexity: O(1).
pub fn sensor_valid(sensor: &Sensor) -> Bool
  requires: true
{
  return sensor.handle != 0;
}

/// True when the handle refers to an event queue (non-zero).
/// Complexity: O(1).
pub fn queue_valid(queue: &SensorEventQueue) -> Bool
  requires: true
{
  return queue.handle != 0;
}

/// Enumerate the manager's sensor list (ASensorManager_getSensorList).
/// Complexity: O(sensor count).
pub fn manager_sensor_list(manager: &SensorManager) -> Result[Vec[Sensor], AndroidProbeError]
  requires: true
{
  let n = unsafe { xa_sensor_manager_get_sensor_list(manager.handle as Int64) as Int };
  if n < 0 {
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI; message: android_error() });
  }
  var out: Vec[Sensor] = Vec[Sensor].new();
  var i = 0;
  while i < n {
    let h = unsafe { xa_sensor_list_at(0 as Int32, i as Int32) as Int };
    out.push(Sensor{ handle: h });
    i = i + 1;
  }
  return Ok(out);
}

/// Enumerate the dynamic sensor list
/// (ASensorManager_getDynamicSensorList).
/// Complexity: O(sensor count).
pub fn manager_dynamic_sensor_list(manager: &SensorManager) -> Result[Vec[Sensor], AndroidProbeError]
  requires: true
{
  let n = unsafe { xa_sensor_manager_get_dynamic_sensor_list(manager.handle as Int64) as Int };
  if n < 0 {
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI; message: android_error() });
  }
  var out: Vec[Sensor] = Vec[Sensor].new();
  var i = 0;
  while i < n {
    let h = unsafe { xa_sensor_list_at(1 as Int32, i as Int32) as Int };
    out.push(Sensor{ handle: h });
    i = i + 1;
  }
  return Ok(out);
}

/// The default sensor of ASENSOR_TYPE_* `sensor_type`, or handle 0 when
/// the device has none (check sensor_valid; that state is not an error).
/// Complexity: O(1).
pub fn manager_default_sensor(manager: &SensorManager, sensor_type: Int) -> Sensor
  requires: true
{
  let h = unsafe {
    xa_sensor_manager_get_default_sensor(manager.handle as Int64,
                                         sensor_type as Int32) as Int
  };
  return Sensor{ handle: h };
}

/// The default sensor of `sensor_type`, restricted to wake-up (true) or
/// non-wake-up (false) variants (ASensorManager_getDefaultSensorEx).
/// Complexity: O(1).
pub fn manager_default_sensor_ex(manager: &SensorManager, sensor_type: Int,
                                 wake_up: Bool) -> Sensor
  requires: true
{
  let w: Int32 = if wake_up { 1 } else { 0 };
  let h = unsafe {
    xa_sensor_manager_get_default_sensor_ex(manager.handle as Int64,
                                            sensor_type as Int32, w) as Int
  };
  return Sensor{ handle: h };
}

/// Create an event queue bound to `looper` with a direct-handoff
/// `handler` (the looper then reports `ident` when events arrive; the
/// handler usually calls queue_read).
/// Complexity: O(1).
pub fn manager_create_queue(manager: &SensorManager, looper: &Looper, ident: Int,
                            handler: fn(Int32, Int32, Int) -> Int32) -> Result[SensorEventQueue, AndroidProbeError]
  requires: true
{
  let h = unsafe {
    xa_sensor_manager_create_event_queue(manager.handle as Int64, looper.handle as Int64,
                                         ident as Int32, handler, 0 as Int64) as Int
  };
  if h == 0 {
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI; message: android_error() });
  }
  return Ok(SensorEventQueue{ handle: h });
}

/// Create an event queue with NO callback; ALooper reports `ident` when
/// the queue has events and the caller reads them with queue_read.
/// Complexity: O(1).
pub fn manager_create_queue_ident(manager: &SensorManager, looper: &Looper,
                                  ident: Int) -> Result[SensorEventQueue, AndroidProbeError]
  requires: true
{
  let h = unsafe {
    xa_sensor_manager_create_event_queue_ident(manager.handle as Int64,
                                               looper.handle as Int64,
                                               ident as Int32) as Int
  };
  if h == 0 {
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI; message: android_error() });
  }
  return Ok(SensorEventQueue{ handle: h });
}

/// Destroy the queue (disables its sensors and unregisters it).
/// Complexity: O(1).
pub fn manager_destroy_queue(manager: &SensorManager, queue: SensorEventQueue) -> Bool
  requires: true
{
  let rc = unsafe {
    xa_sensor_manager_destroy_event_queue(manager.handle as Int64,
                                          queue.handle as Int64) as Int
  };
  return rc >= 0;
}

/// Create a shared-memory direct channel over an fd (e.g. one from
/// shm_create).  Returns the channel id (>= 0) or a negative error.
/// Complexity: O(1).
pub fn manager_create_shm_direct_channel(manager: &SensorManager, fd: Int,
                                         size: Int) -> Int
  requires: size > 0
{
  unsafe {
    return xa_sensor_manager_create_shared_memory_direct_channel(manager.handle as Int64,
                                                                 fd as Int32,
                                                                 size as Int64) as Int;
  }
}

/// Create a hardware-buffer direct channel over an AHardwareBuffer
/// handle (from hwb_alloc); `size` must be <= the buffer's size.
/// Returns the channel id (>= 0) or a negative error.
/// Complexity: O(1).
pub fn manager_create_hwb_direct_channel(manager: &SensorManager, hwb: Int,
                                         size: Int) -> Int
  requires: size > 0
{
  unsafe {
    return xa_sensor_manager_create_hardware_buffer_direct_channel(manager.handle as Int64,
                                                                   hwb as Int64,
                                                                   size as Int64) as Int;
  }
}

/// Destroy a direct channel created above.
/// Complexity: O(1).
pub fn manager_destroy_direct_channel(manager: &SensorManager, channel_id: Int) -> Bool
  requires: true
{
  let rc = unsafe {
    xa_sensor_manager_destroy_direct_channel(manager.handle as Int64,
                                             channel_id as Int32) as Int
  };
  return rc == 0;
}

/// Configure a sensor for direct report (ASENSOR_DIRECT_RATE_*) on a
/// direct channel (channelId first, then rate -- the header order).
/// The header also allows sensor NULL with RATE_STOP to stop all active
/// direct reports; pass a zero-handle Sensor for that.
/// Complexity: O(1).
pub fn manager_configure_direct_report(manager: &SensorManager, sensor: &Sensor,
                                       channel_id: Int, rate_level: Int) -> Bool
  requires: true
{
  let rc = unsafe {
    xa_sensor_manager_configure_direct_report(manager.handle as Int64,
                                              sensor.handle as Int64,
                                              channel_id as Int32,
                                              rate_level as Int32) as Int
  };
  return rc == 0;
}

// =========================================================================
// ASensorEventQueue functional head
// =========================================================================

/// Enable a sensor on the queue (default rate).
/// Complexity: O(1).
pub fn queue_enable_sensor(queue: &SensorEventQueue, sensor: &Sensor) -> Bool
  requires: true
{
  let rc = unsafe {
    xa_sensor_event_queue_enable_sensor(queue.handle as Int64, sensor.handle as Int64) as Int
  };
  return rc == 0;
}

/// Disable a sensor on the queue.
/// Complexity: O(1).
pub fn queue_disable_sensor(queue: &SensorEventQueue, sensor: &Sensor) -> Bool
  requires: true
{
  let rc = unsafe {
    xa_sensor_event_queue_disable_sensor(queue.handle as Int64, sensor.handle as Int64) as Int
  };
  return rc == 0;
}

/// Change the sensor's sampling rate (microseconds; 0 = fastest the
/// sensor supports).
/// Complexity: O(1).
pub fn queue_set_event_rate(queue: &SensorEventQueue, sensor: &Sensor, usec: Int) -> Bool
  requires: usec >= 0
{
  let rc = unsafe {
    xa_sensor_event_queue_set_event_rate(queue.handle as Int64, sensor.handle as Int64,
                                         usec as Int32) as Int
  };
  return rc == 0;
}

/// Batch-register a sensor with a sampling period and a max report
/// latency (both microseconds; max_report_latency 0 = no batching).
/// Complexity: O(1).
pub fn queue_register_sensor(queue: &SensorEventQueue, sensor: &Sensor,
                             sampling_period_us: Int, max_report_latency_us: Int) -> Bool
  requires: sampling_period_us >= 0
  requires: max_report_latency_us >= 0
{
  let rc = unsafe {
    xa_sensor_event_queue_register_sensor(queue.handle as Int64, sensor.handle as Int64,
                                          sampling_period_us as Int32,
                                          max_report_latency_us as Int64) as Int
  };
  return rc == 0;
}

/// 1 when events are available, 0 when not, negative on error.
/// Complexity: O(1).
pub fn queue_has_events(queue: &SensorEventQueue) -> Int
  requires: true
{
  unsafe { return xa_sensor_event_queue_has_events(queue.handle as Int64) as Int; }
}

/// Ask for additional-info events (ASENSOR_TYPE_ADDITIONAL_INFO frames).
/// Complexity: O(1).
pub fn queue_request_additional_info_events(queue: &SensorEventQueue, enable: Bool) -> Bool
  requires: true
{
  let e: Int32 = if enable { 1 } else { 0 };
  let rc = unsafe {
    xa_sensor_event_queue_request_additional_info_events(queue.handle as Int64, e) as Int
  };
  return rc == 0;
}

/// Read up to `max_count` events (ASensorEventQueue_getEvents) into the
/// bridge-side owned slots; the returned SensorEvents address those
/// slots by index until the next read.  A read with no pending events
/// returns an empty vector.
/// Complexity: O(events read).
pub fn queue_read(queue: &SensorEventQueue, max_count: Int) -> Result[Vec[SensorEvent], AndroidProbeError]
  requires: max_count > 0
  requires: max_count <= 32
{
  let n = unsafe {
    xa_sensor_event_queue_read(queue.handle as Int64, max_count as Int32) as Int
  };
  if n < 0 {
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI; message: android_error() });
  }
  var out: Vec[SensorEvent] = Vec[SensorEvent].new();
  var i = 0;
  while i < n {
    out.push(SensorEvent{ index: i });
    i = i + 1;
  }
  return Ok(out);
}

// =========================================================================
// ASensorEvent accessors (slot-indexed; see queue_read)
// =========================================================================

/// ASensorEvent.version (struct version).
/// Complexity: O(1).
pub fn event_version(event: &SensorEvent) -> Int
  requires: true
{
  unsafe { return xa_sensor_event_version(event.index as Int32) as Int; }
}

/// The handle of the sensor that generated the event.
/// Complexity: O(1).
pub fn event_sensor(event: &SensorEvent) -> Int
  requires: true
{
  unsafe { return xa_sensor_event_sensor(event.index as Int32) as Int; }
}

/// ASENSOR_TYPE_* of the event.
/// Complexity: O(1).
pub fn event_type(event: &SensorEvent) -> Int
  requires: true
{
  unsafe { return xa_sensor_event_type(event.index as Int32) as Int; }
}

/// Event timestamp in nanoseconds (same epoch semantics as Java
/// SensorEvent.timestamp).
/// Complexity: O(1).
pub fn event_timestamp(event: &SensorEvent) -> Int
  requires: true
{
  unsafe { return xa_sensor_event_timestamp(event.index as Int32) as Int; }
}

/// Wake-up / event flags.
/// Complexity: O(1).
pub fn event_flags(event: &SensorEvent) -> Int
  requires: true
{
  unsafe { return xa_sensor_event_flags(event.index as Int32) as Int; }
}

/// First vector component (vector/acceleration/gyro/magnetic payloads).
/// Complexity: O(1).
pub fn event_x(event: &SensorEvent) -> Float64
  requires: true
{
  let bits = unsafe { xa_sensor_event_x_bits(event.index as Int32) as Int };
  return android_f32_from_bits(bits);
}

/// Second vector component.
/// Complexity: O(1).
pub fn event_y(event: &SensorEvent) -> Float64
  requires: true
{
  let bits = unsafe { xa_sensor_event_y_bits(event.index as Int32) as Int };
  return android_f32_from_bits(bits);
}

/// Third vector component.
/// Complexity: O(1).
pub fn event_z(event: &SensorEvent) -> Float64
  requires: true
{
  let bits = unsafe { xa_sensor_event_z_bits(event.index as Int32) as Int };
  return android_f32_from_bits(bits);
}

/// Scalar payload (temperature / distance / light / pressure /
/// relative humidity).
/// Complexity: O(1).
pub fn event_scalar(event: &SensorEvent) -> Float64
  requires: true
{
  let bits = unsafe { xa_sensor_event_scalar_bits(event.index as Int32) as Int };
  return android_f32_from_bits(bits);
}

/// ASENSOR_STATUS_* accuracy of the vector payload.
/// Complexity: O(1).
pub fn event_status(event: &SensorEvent) -> Int
  requires: true
{
  unsafe { return xa_sensor_event_status(event.index as Int32) as Int; }
}

/// Step-counter payload (u64 slot of the union).
/// Complexity: O(1).
pub fn event_step_counter(event: &SensorEvent) -> Int
  requires: true
{
  unsafe { return xa_sensor_event_step_counter(event.index as Int32) as Int; }
}

/// AMetaDataEvent.what (dynamic sensor meta events).
/// Complexity: O(1).
pub fn event_meta_what(event: &SensorEvent) -> Int
  requires: true
{
  unsafe { return xa_sensor_event_meta_what(event.index as Int32) as Int; }
}

/// Heart-rate payload in beats per minute.
/// Complexity: O(1).
pub fn event_heart_rate_bpm(event: &SensorEvent) -> Float64
  requires: true
{
  let bits = unsafe { xa_sensor_event_heart_rate_bpm_bits(event.index as Int32) as Int };
  return android_f32_from_bits(bits);
}

// =========================================================================
// ASensor accessors
// =========================================================================

/// Sensor name ("" when unset).
/// Complexity: O(1).
pub fn sensor_name(sensor: &Sensor) -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xa_sensor_name(sensor.handle as Int64)); }
}

/// Sensor vendor ("" when unset).
/// Complexity: O(1).
pub fn sensor_vendor(sensor: &Sensor) -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xa_sensor_vendor(sensor.handle as Int64)); }
}

/// ASENSOR_TYPE_* of the sensor.
/// Complexity: O(1).
pub fn sensor_type(sensor: &Sensor) -> Int
  requires: true
{
  unsafe { return xa_sensor_type(sensor.handle as Int64) as Int; }
}

/// Maximum resolution of the sensor in its natural units.  The header's
/// ASENSOR_RESOLUTION_INVALID sentinel (nanf("") -- surfaced as the bit
/// constant) reconstructs as 0.0 here: non-finite patterns are clamped
/// by android_f32_from_bits, and 0.0 is not a legal resolution, so
/// `sensor_resolution(&s) == 0.0` identifies the sentinel.
/// Complexity: O(1).
pub fn sensor_resolution(sensor: &Sensor) -> Float64
  requires: true
{
  let bits = unsafe { xa_sensor_resolution_bits(sensor.handle as Int64) as Int };
  return android_f32_from_bits(bits);
}

/// Minimum delay between events in microseconds.
/// Complexity: O(1).
pub fn sensor_min_delay(sensor: &Sensor) -> Int
  requires: true
{
  unsafe { return xa_sensor_min_delay(sensor.handle as Int64) as Int; }
}

/// Max events the hardware FIFO can hold.
/// Complexity: O(1).
pub fn sensor_fifo_max_event_count(sensor: &Sensor) -> Int
  requires: true
{
  unsafe { return xa_sensor_fifo_max_event_count(sensor.handle as Int64) as Int; }
}

/// Events reserved in the FIFO for this sensor.
/// Complexity: O(1).
pub fn sensor_fifo_reserved_event_count(sensor: &Sensor) -> Int
  requires: true
{
  unsafe { return xa_sensor_fifo_reserved_event_count(sensor.handle as Int64) as Int; }
}

/// String type, e.g. "android.sensor.accelerometer" ("" when unset).
/// Complexity: O(1).
pub fn sensor_string_type(sensor: &Sensor) -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xa_sensor_string_type(sensor.handle as Int64)); }
}

/// Reporting mode (continuous / on-change / one-shot / special).
/// Complexity: O(1).
pub fn sensor_reporting_mode(sensor: &Sensor) -> Int
  requires: true
{
  unsafe { return xa_sensor_reporting_mode(sensor.handle as Int64) as Int; }
}

/// Highest ASENSOR_DIRECT_RATE_* level the sensor supports.
/// Complexity: O(1).
pub fn sensor_highest_direct_report_rate_level(sensor: &Sensor) -> Int
  requires: true
{
  unsafe { return xa_sensor_highest_direct_report_rate_level(sensor.handle as Int64) as Int; }
}

/// The sensor's handle (matches ASensorEvent.sensor).
/// Complexity: O(1).
pub fn sensor_handle(sensor: &Sensor) -> Int
  requires: true
{
  unsafe { return xa_sensor_handle(sensor.handle as Int64) as Int; }
}

/// True when the sensor is a wake-up sensor.
/// Complexity: O(1).
pub fn sensor_is_wake_up(sensor: &Sensor) -> Bool
  requires: true
{
  let rc = unsafe { xa_sensor_is_wake_up_sensor(sensor.handle as Int64) as Int };
  return rc == 1;
}

/// True when the sensor supports the given
/// ASENSOR_DIRECT_CHANNEL_TYPE_* channel.
/// Complexity: O(1).
pub fn sensor_is_direct_channel_type_supported(sensor: &Sensor, channel_type: Int) -> Bool
  requires: true
{
  let rc = unsafe {
    xa_sensor_is_direct_channel_type_supported(sensor.handle as Int64,
                                               channel_type as Int32) as Int
  };
  return rc == 1;
}

// ============================================================================
// GENERATED CONSTANTS -- do not edit below this line.
// Produced by docs/repro/gen-a3a4-consts.ps1 (values evaluated by the NDK
// r27b compiler on the API-36 emulator; see gen/a3a4_consts_dump.txt).
// ============================================================================
// ASENSOR_TYPE_* sensor types (android/sensor.h)
pub const ASENSOR_TYPE_ACCELEROMETER: Int = 1;
pub const ASENSOR_TYPE_ACCELEROMETER_LIMITED_AXES: Int = 38;
pub const ASENSOR_TYPE_ACCELEROMETER_LIMITED_AXES_UNCALIBRATED: Int = 40;
pub const ASENSOR_TYPE_ACCELEROMETER_UNCALIBRATED: Int = 35;
pub const ASENSOR_TYPE_ADDITIONAL_INFO: Int = 33;
pub const ASENSOR_TYPE_AMBIENT_TEMPERATURE: Int = 13;
pub const ASENSOR_TYPE_DYNAMIC_SENSOR_META: Int = 32;
pub const ASENSOR_TYPE_GAME_ROTATION_VECTOR: Int = 15;
pub const ASENSOR_TYPE_GEOMAGNETIC_ROTATION_VECTOR: Int = 20;
pub const ASENSOR_TYPE_GRAVITY: Int = 9;
pub const ASENSOR_TYPE_GYROSCOPE: Int = 4;
pub const ASENSOR_TYPE_GYROSCOPE_LIMITED_AXES: Int = 39;
pub const ASENSOR_TYPE_GYROSCOPE_LIMITED_AXES_UNCALIBRATED: Int = 41;
pub const ASENSOR_TYPE_GYROSCOPE_UNCALIBRATED: Int = 16;
pub const ASENSOR_TYPE_HEAD_TRACKER: Int = 37;
pub const ASENSOR_TYPE_HEADING: Int = 42;
pub const ASENSOR_TYPE_HEART_BEAT: Int = 31;
pub const ASENSOR_TYPE_HEART_RATE: Int = 21;
pub const ASENSOR_TYPE_HINGE_ANGLE: Int = 36;
pub const ASENSOR_TYPE_INVALID: Int = -1;
pub const ASENSOR_TYPE_LIGHT: Int = 5;
pub const ASENSOR_TYPE_LINEAR_ACCELERATION: Int = 10;
pub const ASENSOR_TYPE_LOW_LATENCY_OFFBODY_DETECT: Int = 34;
pub const ASENSOR_TYPE_MAGNETIC_FIELD: Int = 2;
pub const ASENSOR_TYPE_MAGNETIC_FIELD_UNCALIBRATED: Int = 14;
pub const ASENSOR_TYPE_MOTION_DETECT: Int = 30;
pub const ASENSOR_TYPE_POSE_6DOF: Int = 28;
pub const ASENSOR_TYPE_PRESSURE: Int = 6;
pub const ASENSOR_TYPE_PROXIMITY: Int = 8;
pub const ASENSOR_TYPE_RELATIVE_HUMIDITY: Int = 12;
pub const ASENSOR_TYPE_ROTATION_VECTOR: Int = 11;
pub const ASENSOR_TYPE_SIGNIFICANT_MOTION: Int = 17;
pub const ASENSOR_TYPE_STATIONARY_DETECT: Int = 29;
pub const ASENSOR_TYPE_STEP_COUNTER: Int = 19;
pub const ASENSOR_TYPE_STEP_DETECTOR: Int = 18;

// ASENSOR_STATUS_* (android/sensor.h)
pub const ASENSOR_STATUS_ACCURACY_HIGH: Int = 3;
pub const ASENSOR_STATUS_ACCURACY_LOW: Int = 1;
pub const ASENSOR_STATUS_ACCURACY_MEDIUM: Int = 2;
pub const ASENSOR_STATUS_NO_CONTACT: Int = -1;
pub const ASENSOR_STATUS_UNRELIABLE: Int = 0;

// ASENSOR_ADDITIONAL_INFO_* (android/sensor.h)
pub const ASENSOR_ADDITIONAL_INFO_BEGIN: Int = 0;
pub const ASENSOR_ADDITIONAL_INFO_END: Int = 1;
pub const ASENSOR_ADDITIONAL_INFO_INTERNAL_TEMPERATURE: Int = 65537;
pub const ASENSOR_ADDITIONAL_INFO_SAMPLING: Int = 65540;
pub const ASENSOR_ADDITIONAL_INFO_SENSOR_PLACEMENT: Int = 65539;
pub const ASENSOR_ADDITIONAL_INFO_UNTRACKED_DELAY: Int = 65536;
pub const ASENSOR_ADDITIONAL_INFO_VEC3_CALIBRATION: Int = 65538;

// ASENSOR_DIRECT_* (android/sensor.h)
pub const ASENSOR_DIRECT_CHANNEL_TYPE_HARDWARE_BUFFER: Int = 2;
pub const ASENSOR_DIRECT_CHANNEL_TYPE_SHARED_MEMORY: Int = 1;
pub const ASENSOR_DIRECT_RATE_FAST: Int = 2;
pub const ASENSOR_DIRECT_RATE_NORMAL: Int = 1;
pub const ASENSOR_DIRECT_RATE_STOP: Int = 0;
pub const ASENSOR_DIRECT_RATE_VERY_FAST: Int = 3;

// Scalar limits and physical constants (android/sensor.h)
pub const ASENSOR_DELAY_INVALID: Int = -2147483648;
pub const ASENSOR_FIFO_COUNT_INVALID: Int = -1;
pub const ASENSOR_INVALID: Int = -1;

pub const ASENSOR_STANDARD_GRAVITY: Float64 = 9.8066501617431641; // = ASENSOR_STANDARD_GRAVITYf from the header
pub const ASENSOR_MAGNETIC_FIELD_EARTH_MAX: Float64 = 60; // = ASENSOR_MAGNETIC_FIELD_EARTH_MAXf from the header
pub const ASENSOR_MAGNETIC_FIELD_EARTH_MIN: Float64 = 30; // = ASENSOR_MAGNETIC_FIELD_EARTH_MINf from the header
// The header defines ASENSOR_RESOLUTION_INVALID as nanf("") -- surfaced as the IEEE-754 quiet-NaN bit pattern (runtime-checked by the probe).
pub const ASENSOR_RESOLUTION_INVALID: Int = 2143289344;

