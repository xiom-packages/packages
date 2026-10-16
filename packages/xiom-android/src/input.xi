// XIOM -- xiom.android.input: A3 input head (W2d-A3).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// SCOPE: android/input.h + android/keycodes.h of NDK r27b
// (docs/ANDROID-SDK100.md slice A3; wave brief docs/prep/android-wave.md).
//
//   AInputEvent_*  (4)  type/device id/source + release (API 31)
//   AInputQueue_*  (6)  attachLooper/detachLooper/hasEvents/getEvent/
//                       preDispatchEvent/finishEvent -- the looper
//                       integration point the native_app_glue consumer
//                       uses (the glue's AInputQueue imports are now
//                       covered by this package's export set)
//   AKeyEvent_*    (8)  action/flags/keyCode/scanCode/metaState/
//                       repeatCount/downTime/eventTime
//   AMotionEvent_* (42) the full pointer/history/axis surface incl.
//                       historical accessors, actionButton (API 33)
//                       and classification (API 34)
//
// 60 platform exports (63 prototypes - the 3 *_fromJava JNI routes,
// which are the A11 seam); every one is in the bridge export set and
// wrapped here.  The float-valued accessors cross the boundary as
// IEEE-754 binary32 BIT PATTERNS and are rebuilt with
// android_f32_from_bits (B-12: fp cast-call returns are miscompiled on
// the pinned toolchain).
//
// An AInputQueue cannot be fabricated by a plain process: it is
// delivered by the framework to an app (ANativeActivityCallbacks
// .inputQueueCreated / native_app_glue).  The functional queue path is
// therefore proven by the on-device app probe (docs/repro), while this
// module stays fully usable for the consumer app -- and every call
// without a loaded runtime errors explicitly (never a silent zero).
//
// PROVENANCE: header oracle = NDK r27b android/input.h + keycodes.h
// (Apache-2.0); constant transcription is generated + gated by
// docs/repro/gen-a3a4-consts.ps1 (values evaluated by the NDK compiler,
// re-checked by _Static_asserts in the on-device probe).

module xiom.android.input

use xiom.android;
use xiom.android.lifecycle;

extern "C" {
  fn xa_input_queue_attach(queue: Int64, looper: Int64, ident: Int32,
                           cb: fn(Int32, Int32, Int) -> Int32, data: Int64) -> Int32;
  fn xa_input_queue_attach_ident(queue: Int64, looper: Int64, ident: Int32) -> Int32;
  fn xa_input_queue_detach(queue: Int64) -> Int32;
  fn xa_input_queue_has_events(queue: Int64) -> Int32;
  fn xa_input_event_get(queue: Int64) -> Int64;
  fn xa_input_event_pre_dispatch(queue: Int64, event: Int64) -> Int32;
  fn xa_input_event_finish(queue: Int64, event: Int64, handled: Int32) -> Int32;
  fn xa_input_event_release(event: Int64);
  fn xa_input_event_type(event: Int64) -> Int32;
  fn xa_input_event_device_id(event: Int64) -> Int32;
  fn xa_input_event_source(event: Int64) -> Int32;
  fn xa_key_event_action(event: Int64) -> Int32;
  fn xa_key_event_flags(event: Int64) -> Int32;
  fn xa_key_event_key_code(event: Int64) -> Int32;
  fn xa_key_event_scan_code(event: Int64) -> Int32;
  fn xa_key_event_meta_state(event: Int64) -> Int32;
  fn xa_key_event_repeat_count(event: Int64) -> Int32;
  fn xa_key_event_down_time(event: Int64) -> Int64;
  fn xa_key_event_event_time(event: Int64) -> Int64;
  fn xa_motion_event_action(event: Int64) -> Int32;
  fn xa_motion_event_flags(event: Int64) -> Int32;
  fn xa_motion_event_meta_state(event: Int64) -> Int32;
  fn xa_motion_event_button_state(event: Int64) -> Int32;
  fn xa_motion_event_edge_flags(event: Int64) -> Int32;
  fn xa_motion_event_down_time(event: Int64) -> Int64;
  fn xa_motion_event_event_time(event: Int64) -> Int64;
  fn xa_motion_event_pointer_count(event: Int64) -> Int64;
  fn xa_motion_event_pointer_id(event: Int64, index: Int64) -> Int32;
  fn xa_motion_event_tool_type(event: Int64, index: Int64) -> Int32;
  fn xa_motion_event_action_button(event: Int64) -> Int32;
  fn xa_motion_event_classification(event: Int64) -> Int32;
  fn xa_motion_event_history_size(event: Int64) -> Int64;
  fn xa_motion_event_x_offset_bits(event: Int64) -> Int64;
  fn xa_motion_event_y_offset_bits(event: Int64) -> Int64;
  fn xa_motion_event_x_precision_bits(event: Int64) -> Int64;
  fn xa_motion_event_y_precision_bits(event: Int64) -> Int64;
  fn xa_motion_event_raw_x_bits(event: Int64, index: Int64) -> Int64;
  fn xa_motion_event_raw_y_bits(event: Int64, index: Int64) -> Int64;
  fn xa_motion_event_x_bits(event: Int64, index: Int64) -> Int64;
  fn xa_motion_event_y_bits(event: Int64, index: Int64) -> Int64;
  fn xa_motion_event_pressure_bits(event: Int64, index: Int64) -> Int64;
  fn xa_motion_event_size_bits(event: Int64, index: Int64) -> Int64;
  fn xa_motion_event_touch_major_bits(event: Int64, index: Int64) -> Int64;
  fn xa_motion_event_touch_minor_bits(event: Int64, index: Int64) -> Int64;
  fn xa_motion_event_tool_major_bits(event: Int64, index: Int64) -> Int64;
  fn xa_motion_event_tool_minor_bits(event: Int64, index: Int64) -> Int64;
  fn xa_motion_event_orientation_bits(event: Int64, index: Int64) -> Int64;
  fn xa_motion_event_axis_value_bits(event: Int64, index: Int64, axis: Int32) -> Int64;
  fn xa_motion_event_historical_event_time(event: Int64, index: Int64,
                                           history_index: Int64) -> Int64;
  fn xa_motion_event_historical_raw_x_bits(event: Int64, index: Int64,
                                           history_index: Int64) -> Int64;
  fn xa_motion_event_historical_raw_y_bits(event: Int64, index: Int64,
                                           history_index: Int64) -> Int64;
  fn xa_motion_event_historical_x_bits(event: Int64, index: Int64,
                                       history_index: Int64) -> Int64;
  fn xa_motion_event_historical_y_bits(event: Int64, index: Int64,
                                       history_index: Int64) -> Int64;
  fn xa_motion_event_historical_pressure_bits(event: Int64, index: Int64,
                                              history_index: Int64) -> Int64;
  fn xa_motion_event_historical_size_bits(event: Int64, index: Int64,
                                          history_index: Int64) -> Int64;
  fn xa_motion_event_historical_touch_major_bits(event: Int64, index: Int64,
                                                 history_index: Int64) -> Int64;
  fn xa_motion_event_historical_touch_minor_bits(event: Int64, index: Int64,
                                                 history_index: Int64) -> Int64;
  fn xa_motion_event_historical_tool_major_bits(event: Int64, index: Int64,
                                                history_index: Int64) -> Int64;
  fn xa_motion_event_historical_tool_minor_bits(event: Int64, index: Int64,
                                                history_index: Int64) -> Int64;
  fn xa_motion_event_historical_orientation_bits(event: Int64, index: Int64,
                                                 history_index: Int64) -> Int64;
  fn xa_motion_event_historical_axis_value_bits(event: Int64, index: Int64,
                                                history_index: Int64,
                                                axis: Int32) -> Int64;
}

// =========================================================================
// Input objects
// =========================================================================

// An AInputQueue delivered by the framework (native_app_glue's
// inputQueueCreated); owned by the app, not by this binding.
pub type InputQueue = {
  handle: Int;
}

// An AInputEvent obtained from input_event_read; released with
// input_event_release.
pub type InputEvent = {
  handle: Int;
}

// =========================================================================
// AInputQueue functional head
// =========================================================================

/// True when the handle refers to a queue (non-zero).
/// Complexity: O(1).
pub fn input_queue_valid(queue: &InputQueue) -> Bool
  requires: true
{
  return queue.handle != 0;
}

/// Attach the queue to `looper` for processing (AInputQueue_attachLooper).
/// `handler` is a direct-handoff top-level fn (env-free; the same ABI as
/// the ALooper handlers).  The looper then reports `ident` and fires the
/// handler while events are pending.
/// Complexity: O(1).
pub fn input_queue_attach_looper(queue: &InputQueue, looper: &Looper, ident: Int,
                                 handler: fn(Int32, Int32, Int) -> Int32) -> Bool
  requires: true
{
  let rc = unsafe {
    xa_input_queue_attach(queue.handle as Int64, looper.handle as Int64,
                          ident as Int32, handler, 0 as Int64) as Int
  };
  return rc == 0;
}

/// Attach the queue with NO callback (requires looper_prepare(true));
/// looper_poll_once then returns `ident` while events are pending and
/// the caller reads them with input_event_read.
/// Complexity: O(1).
pub fn input_queue_attach_looper_ident(queue: &InputQueue, looper: &Looper,
                                       ident: Int) -> Bool
  requires: true
{
  let rc = unsafe {
    xa_input_queue_attach_ident(queue.handle as Int64, looper.handle as Int64,
                                ident as Int32) as Int
  };
  return rc == 0;
}

/// Remove the queue from the looper it is currently attached to.
/// Complexity: O(1).
pub fn input_queue_detach_looper(queue: &InputQueue) -> Bool
  requires: true
{
  let rc = unsafe { xa_input_queue_detach(queue.handle as Int64) as Int };
  return rc == 0;
}

/// 1 when the queue has events, 0 when empty, negative on error.
/// Complexity: O(1).
pub fn input_queue_has_events(queue: &InputQueue) -> Int
  requires: true
{
  unsafe { return xa_input_queue_has_events(queue.handle as Int64) as Int; }
}

/// Read the next available event (AInputQueue_getEvent).  Call it while
/// input_queue_has_events reports 1 (the platform call blocks
/// otherwise).  The caller must hand the event to input_event_finish
/// and then input_event_release.
/// Complexity: O(1).
pub fn input_event_read(queue: &InputQueue) -> Result[InputEvent, AndroidProbeError]
  requires: true
{
  let h = unsafe { xa_input_event_get(queue.handle as Int64) as Int };
  if h == 0 {
    return Err(AndroidProbeError{ kind: ANDROID_LOAD_ABI; message: android_error() });
  }
  return Ok(InputEvent{ handle: h });
}

/// Send the event for standard pre-dispatching (IME first).  0 = not
/// pre-dispatched (process it now); non-zero = abandon it for now (it
/// reappears in the queue when not consumed).  Negative on error.
/// Complexity: O(1).
pub fn input_event_pre_dispatch(queue: &InputQueue, event: &InputEvent) -> Int
  requires: true
{
  unsafe {
    return xa_input_event_pre_dispatch(queue.handle as Int64, event.handle as Int64) as Int;
  }
}

/// Report that dispatching has finished (must follow input_event_read).
/// Complexity: O(1).
pub fn input_event_finish(queue: &InputQueue, event: &InputEvent, handled: Bool) -> Bool
  requires: true
{
  let h: Int32 = if handled { 1 } else { 0 };
  let rc = unsafe {
    xa_input_event_finish(queue.handle as Int64, event.handle as Int64, h) as Int
  };
  return rc == 0;
}

/// Release one reference to the event (AInputEvent_release, API 31+).
/// Complexity: O(1).
pub fn input_event_release(event: InputEvent)
  requires: true
{
  unsafe { xa_input_event_release(event.handle as Int64); }
}

// =========================================================================
// AInputEvent accessors
// =========================================================================

/// AINPUT_EVENT_TYPE_* (KEY/MOTION/...).  Negative on error.
/// Complexity: O(1).
pub fn input_event_type(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_input_event_type(event.handle as Int64) as Int; }
}

/// The input device id that generated the event.
/// Complexity: O(1).
pub fn input_event_device_id(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_input_event_device_id(event.handle as Int64) as Int; }
}

/// AINPUT_SOURCE_* combination describing the event source.
/// Complexity: O(1).
pub fn input_event_source(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_input_event_source(event.handle as Int64) as Int; }
}

// =========================================================================
// AKeyEvent accessors (valid when input_event_type == AINPUT_EVENT_TYPE_KEY)
// =========================================================================

/// AKEY_EVENT_ACTION_* (DOWN/UP/MULTIPLE).
/// Complexity: O(1).
pub fn key_event_action(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_key_event_action(event.handle as Int64) as Int; }
}

/// AKEY_EVENT_FLAG_* combination.
/// Complexity: O(1).
pub fn key_event_flags(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_key_event_flags(event.handle as Int64) as Int; }
}

/// The AKEYCODE_* key code.
/// Complexity: O(1).
pub fn key_event_key_code(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_key_event_key_code(event.handle as Int64) as Int; }
}

/// The hardware scan code of the key.
/// Complexity: O(1).
pub fn key_event_scan_code(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_key_event_scan_code(event.handle as Int64) as Int; }
}

/// AMETA_* meta state at the time of the event.
/// Complexity: O(1).
pub fn key_event_meta_state(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_key_event_meta_state(event.handle as Int64) as Int; }
}

/// How many times the key repeated (0 when not a repeat).
/// Complexity: O(1).
pub fn key_event_repeat_count(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_key_event_repeat_count(event.handle as Int64) as Int; }
}

/// The time (ns since boot) the key was first pressed.
/// Complexity: O(1).
pub fn key_event_down_time(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_key_event_down_time(event.handle as Int64) as Int; }
}

/// The time (ns since boot) of this event.
/// Complexity: O(1).
pub fn key_event_event_time(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_key_event_event_time(event.handle as Int64) as Int; }
}

// =========================================================================
// AMotionEvent accessors
// (valid when input_event_type == AINPUT_EVENT_TYPE_MOTION)
//
// The float-valued accessors return Float64 rebuilt from the binary32
// bits written by the bridge (B-12-safe path); the *_bits companions are
// not exposed -- use the Float64 forms.
// =========================================================================

/// AMOTION_EVENT_ACTION_*; pointer-index bits are packed into the top
/// byte (see AMOTION_EVENT_ACTION_POINTER_INDEX_MASK/SHIFT).
/// Complexity: O(1).
pub fn motion_event_action(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_motion_event_action(event.handle as Int64) as Int; }
}

/// AMOTION_EVENT_FLAG_* combination.
/// Complexity: O(1).
pub fn motion_event_flags(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_motion_event_flags(event.handle as Int64) as Int; }
}

/// AMETA_* meta state at the time of the event.
/// Complexity: O(1).
pub fn motion_event_meta_state(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_motion_event_meta_state(event.handle as Int64) as Int; }
}

/// AMOTION_EVENT_BUTTON_* state of the pressed buttons.
/// Complexity: O(1).
pub fn motion_event_button_state(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_motion_event_button_state(event.handle as Int64) as Int; }
}

/// AMOTION_EVENT_EDGE_FLAG_* combination of touched edges.
/// Complexity: O(1).
pub fn motion_event_edge_flags(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_motion_event_edge_flags(event.handle as Int64) as Int; }
}

/// The time (ns since boot) the gesture was first pressed.
/// Complexity: O(1).
pub fn motion_event_down_time(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_motion_event_down_time(event.handle as Int64) as Int; }
}

/// The time (ns since boot) of this event.
/// Complexity: O(1).
pub fn motion_event_event_time(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_motion_event_event_time(event.handle as Int64) as Int; }
}

/// Number of pointers in the gesture.
/// Complexity: O(1).
pub fn motion_event_pointer_count(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_motion_event_pointer_count(event.handle as Int64) as Int; }
}

/// The pointer id of pointer `index` (0 <= index < pointer_count).
/// Complexity: O(1).
pub fn motion_event_pointer_id(event: &InputEvent, index: Int) -> Int
  requires: index >= 0
{
  unsafe { return xa_motion_event_pointer_id(event.handle as Int64, index as Int64) as Int; }
}

/// AMOTION_EVENT_TOOL_TYPE_* of pointer `index`.
/// Complexity: O(1).
pub fn motion_event_tool_type(event: &InputEvent, index: Int) -> Int
  requires: index >= 0
{
  unsafe { return xa_motion_event_tool_type(event.handle as Int64, index as Int64) as Int; }
}

/// AMOTION_EVENT_BUTTON_* of the button that triggered a
/// BUTTON_PRESS/BUTTON_RELEASE action.
/// Complexity: O(1).
pub fn motion_event_action_button(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_motion_event_action_button(event.handle as Int64) as Int; }
}

/// AMOTION_EVENT_CLASSIFICATION_* touch classification (API 34+).
/// Complexity: O(1).
pub fn motion_event_classification(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_motion_event_classification(event.handle as Int64) as Int; }
}

/// Number of historical samples batched into the event.
/// Complexity: O(1).
pub fn motion_event_history_size(event: &InputEvent) -> Int
  requires: true
{
  unsafe { return xa_motion_event_history_size(event.handle as Int64) as Int; }
}

/// X offset of the event's coordinate space (raw vs surface).
/// Complexity: O(1).
pub fn motion_event_x_offset(event: &InputEvent) -> Float64
  requires: true
{
  let bits = unsafe { xa_motion_event_x_offset_bits(event.handle as Int64) as Int };
  return android_f32_from_bits(bits);
}

/// Y offset of the event's coordinate space (raw vs surface).
/// Complexity: O(1).
pub fn motion_event_y_offset(event: &InputEvent) -> Float64
  requires: true
{
  let bits = unsafe { xa_motion_event_y_offset_bits(event.handle as Int64) as Int };
  return android_f32_from_bits(bits);
}

/// X precision (pixels per raw unit).
/// Complexity: O(1).
pub fn motion_event_x_precision(event: &InputEvent) -> Float64
  requires: true
{
  let bits = unsafe { xa_motion_event_x_precision_bits(event.handle as Int64) as Int };
  return android_f32_from_bits(bits);
}

/// Y precision (pixels per raw unit).
/// Complexity: O(1).
pub fn motion_event_y_precision(event: &InputEvent) -> Float64
  requires: true
{
  let bits = unsafe { xa_motion_event_y_precision_bits(event.handle as Int64) as Int };
  return android_f32_from_bits(bits);
}

/// Raw X coordinate of pointer `index` (device units).
/// Complexity: O(1).
pub fn motion_event_raw_x(event: &InputEvent, index: Int) -> Float64
  requires: index >= 0
{
  let bits = unsafe {
    xa_motion_event_raw_x_bits(event.handle as Int64, index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Raw Y coordinate of pointer `index` (device units).
/// Complexity: O(1).
pub fn motion_event_raw_y(event: &InputEvent, index: Int) -> Float64
  requires: index >= 0
{
  let bits = unsafe {
    xa_motion_event_raw_y_bits(event.handle as Int64, index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// X coordinate of pointer `index` (window coordinates).
/// Complexity: O(1).
pub fn motion_event_x(event: &InputEvent, index: Int) -> Float64
  requires: index >= 0
{
  let bits = unsafe {
    xa_motion_event_x_bits(event.handle as Int64, index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Y coordinate of pointer `index` (window coordinates).
/// Complexity: O(1).
pub fn motion_event_y(event: &InputEvent, index: Int) -> Float64
  requires: index >= 0
{
  let bits = unsafe {
    xa_motion_event_y_bits(event.handle as Int64, index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Pressure of pointer `index`.
/// Complexity: O(1).
pub fn motion_event_pressure(event: &InputEvent, index: Int) -> Float64
  requires: index >= 0
{
  let bits = unsafe {
    xa_motion_event_pressure_bits(event.handle as Int64, index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Size of pointer `index`.
/// Complexity: O(1).
pub fn motion_event_size(event: &InputEvent, index: Int) -> Float64
  requires: index >= 0
{
  let bits = unsafe {
    xa_motion_event_size_bits(event.handle as Int64, index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Touch-major axis of pointer `index`.
/// Complexity: O(1).
pub fn motion_event_touch_major(event: &InputEvent, index: Int) -> Float64
  requires: index >= 0
{
  let bits = unsafe {
    xa_motion_event_touch_major_bits(event.handle as Int64, index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Touch-minor axis of pointer `index`.
/// Complexity: O(1).
pub fn motion_event_touch_minor(event: &InputEvent, index: Int) -> Float64
  requires: index >= 0
{
  let bits = unsafe {
    xa_motion_event_touch_minor_bits(event.handle as Int64, index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Tool-major axis of pointer `index`.
/// Complexity: O(1).
pub fn motion_event_tool_major(event: &InputEvent, index: Int) -> Float64
  requires: index >= 0
{
  let bits = unsafe {
    xa_motion_event_tool_major_bits(event.handle as Int64, index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Tool-minor axis of pointer `index`.
/// Complexity: O(1).
pub fn motion_event_tool_minor(event: &InputEvent, index: Int) -> Float64
  requires: index >= 0
{
  let bits = unsafe {
    xa_motion_event_tool_minor_bits(event.handle as Int64, index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Orientation of pointer `index` (radians).
/// Complexity: O(1).
pub fn motion_event_orientation(event: &InputEvent, index: Int) -> Float64
  requires: index >= 0
{
  let bits = unsafe {
    xa_motion_event_orientation_bits(event.handle as Int64, index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// AMOTION_EVENT_AXIS_* value of pointer `index`.
/// Complexity: O(1).
pub fn motion_event_axis_value(event: &InputEvent, index: Int, axis: Int) -> Float64
  requires: index >= 0
{
  let bits = unsafe {
    xa_motion_event_axis_value_bits(event.handle as Int64, index as Int64,
                                    axis as Int32) as Int
  };
  return android_f32_from_bits(bits);
}

/// The time (ns since boot) of historical sample `history_index` of
/// pointer `index` (0 <= history_index < history_size).
/// Complexity: O(1).
pub fn motion_event_historical_event_time(event: &InputEvent, index: Int,
                                          history_index: Int) -> Int
  requires: index >= 0
  requires: history_index >= 0
{
  unsafe {
    return xa_motion_event_historical_event_time(event.handle as Int64,
                                                 index as Int64,
                                                 history_index as Int64) as Int;
  }
}

/// Raw X coordinate of historical sample `history_index`.
/// Complexity: O(1).
pub fn motion_event_historical_raw_x(event: &InputEvent, index: Int,
                                     history_index: Int) -> Float64
  requires: index >= 0
  requires: history_index >= 0
{
  let bits = unsafe {
    xa_motion_event_historical_raw_x_bits(event.handle as Int64, index as Int64,
                                          history_index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Raw Y coordinate of historical sample `history_index`.
/// Complexity: O(1).
pub fn motion_event_historical_raw_y(event: &InputEvent, index: Int,
                                     history_index: Int) -> Float64
  requires: index >= 0
  requires: history_index >= 0
{
  let bits = unsafe {
    xa_motion_event_historical_raw_y_bits(event.handle as Int64, index as Int64,
                                          history_index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// X coordinate of historical sample `history_index`.
/// Complexity: O(1).
pub fn motion_event_historical_x(event: &InputEvent, index: Int,
                                 history_index: Int) -> Float64
  requires: index >= 0
  requires: history_index >= 0
{
  let bits = unsafe {
    xa_motion_event_historical_x_bits(event.handle as Int64, index as Int64,
                                      history_index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Y coordinate of historical sample `history_index`.
/// Complexity: O(1).
pub fn motion_event_historical_y(event: &InputEvent, index: Int,
                                 history_index: Int) -> Float64
  requires: index >= 0
  requires: history_index >= 0
{
  let bits = unsafe {
    xa_motion_event_historical_y_bits(event.handle as Int64, index as Int64,
                                      history_index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Pressure of historical sample `history_index`.
/// Complexity: O(1).
pub fn motion_event_historical_pressure(event: &InputEvent, index: Int,
                                        history_index: Int) -> Float64
  requires: index >= 0
  requires: history_index >= 0
{
  let bits = unsafe {
    xa_motion_event_historical_pressure_bits(event.handle as Int64, index as Int64,
                                             history_index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Size of historical sample `history_index`.
/// Complexity: O(1).
pub fn motion_event_historical_size(event: &InputEvent, index: Int,
                                    history_index: Int) -> Float64
  requires: index >= 0
  requires: history_index >= 0
{
  let bits = unsafe {
    xa_motion_event_historical_size_bits(event.handle as Int64, index as Int64,
                                         history_index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Touch-major axis of historical sample `history_index`.
/// Complexity: O(1).
pub fn motion_event_historical_touch_major(event: &InputEvent, index: Int,
                                           history_index: Int) -> Float64
  requires: index >= 0
  requires: history_index >= 0
{
  let bits = unsafe {
    xa_motion_event_historical_touch_major_bits(event.handle as Int64, index as Int64,
                                                history_index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Touch-minor axis of historical sample `history_index`.
/// Complexity: O(1).
pub fn motion_event_historical_touch_minor(event: &InputEvent, index: Int,
                                           history_index: Int) -> Float64
  requires: index >= 0
  requires: history_index >= 0
{
  let bits = unsafe {
    xa_motion_event_historical_touch_minor_bits(event.handle as Int64, index as Int64,
                                                history_index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Tool-major axis of historical sample `history_index`.
/// Complexity: O(1).
pub fn motion_event_historical_tool_major(event: &InputEvent, index: Int,
                                          history_index: Int) -> Float64
  requires: index >= 0
  requires: history_index >= 0
{
  let bits = unsafe {
    xa_motion_event_historical_tool_major_bits(event.handle as Int64, index as Int64,
                                               history_index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Tool-minor axis of historical sample `history_index`.
/// Complexity: O(1).
pub fn motion_event_historical_tool_minor(event: &InputEvent, index: Int,
                                          history_index: Int) -> Float64
  requires: index >= 0
  requires: history_index >= 0
{
  let bits = unsafe {
    xa_motion_event_historical_tool_minor_bits(event.handle as Int64, index as Int64,
                                               history_index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// Orientation of historical sample `history_index` (radians).
/// Complexity: O(1).
pub fn motion_event_historical_orientation(event: &InputEvent, index: Int,
                                           history_index: Int) -> Float64
  requires: index >= 0
  requires: history_index >= 0
{
  let bits = unsafe {
    xa_motion_event_historical_orientation_bits(event.handle as Int64, index as Int64,
                                                history_index as Int64) as Int
  };
  return android_f32_from_bits(bits);
}

/// AMOTION_EVENT_AXIS_* value of historical sample `history_index`.
/// Complexity: O(1).
pub fn motion_event_historical_axis_value(event: &InputEvent, index: Int,
                                          history_index: Int, axis: Int) -> Float64
  requires: index >= 0
  requires: history_index >= 0
{
  let bits = unsafe {
    xa_motion_event_historical_axis_value_bits(event.handle as Int64, index as Int64,
                                               history_index as Int64,
                                               axis as Int32) as Int
  };
  return android_f32_from_bits(bits);
}

// ============================================================================
// GENERATED CONSTANTS -- do not edit below this line.
// Produced by docs/repro/gen-a3a4-consts.ps1 (values evaluated by the NDK
// r27b compiler on the API-36 emulator; see gen/a3a4_consts_dump.txt).
// ============================================================================
// AINPUT_* event types (android/input.h)
pub const AINPUT_EVENT_TYPE_KEY: Int = 0x0001;
pub const AINPUT_EVENT_TYPE_MOTION: Int = 0x0002;
pub const AINPUT_EVENT_TYPE_FOCUS: Int = 0x0003;
pub const AINPUT_EVENT_TYPE_CAPTURE: Int = 0x0004;
pub const AINPUT_EVENT_TYPE_DRAG: Int = 0x0005;
pub const AINPUT_EVENT_TYPE_TOUCH_MODE: Int = 0x0006;

// AINPUT_SOURCE_* device sources (android/input.h)
pub const AINPUT_SOURCE_CLASS_MASK: Int = 0x00FF;
pub const AINPUT_SOURCE_CLASS_NONE: Int = 0x0000;
pub const AINPUT_SOURCE_CLASS_BUTTON: Int = 0x0001;
pub const AINPUT_SOURCE_CLASS_POINTER: Int = 0x0002;
pub const AINPUT_SOURCE_CLASS_NAVIGATION: Int = 0x0004;
pub const AINPUT_SOURCE_CLASS_POSITION: Int = 0x0008;
pub const AINPUT_SOURCE_CLASS_JOYSTICK: Int = 0x0010;
pub const AINPUT_SOURCE_UNKNOWN: Int = 0x0000;
pub const AINPUT_SOURCE_KEYBOARD: Int = 0x0101;
pub const AINPUT_SOURCE_DPAD: Int = 0x0201;
pub const AINPUT_SOURCE_GAMEPAD: Int = 0x0401;
pub const AINPUT_SOURCE_TOUCHSCREEN: Int = 0x1002;
pub const AINPUT_SOURCE_MOUSE: Int = 0x2002;
pub const AINPUT_SOURCE_STYLUS: Int = 0x4002;
pub const AINPUT_SOURCE_BLUETOOTH_STYLUS: Int = 0xC002;
pub const AINPUT_SOURCE_TRACKBALL: Int = 0x10004;
pub const AINPUT_SOURCE_MOUSE_RELATIVE: Int = 0x20004;
pub const AINPUT_SOURCE_TOUCHPAD: Int = 0x100008;
pub const AINPUT_SOURCE_TOUCH_NAVIGATION: Int = 0x200000;
pub const AINPUT_SOURCE_JOYSTICK: Int = 0x1000010;
pub const AINPUT_SOURCE_HDMI: Int = 0x2000001;
pub const AINPUT_SOURCE_SENSOR: Int = 0x4000000;
pub const AINPUT_SOURCE_ROTARY_ENCODER: Int = 0x400000;
pub const AINPUT_SOURCE_ANY: Int = 0xFFFFFF00;

// AINPUT_KEYBOARD_TYPE_* (android/input.h)
pub const AINPUT_KEYBOARD_TYPE_NONE: Int = 0x0000;
pub const AINPUT_KEYBOARD_TYPE_NON_ALPHABETIC: Int = 0x0001;
pub const AINPUT_KEYBOARD_TYPE_ALPHABETIC: Int = 0x0002;

// AKEY_EVENT_ACTION_* (android/input.h)
pub const AKEY_EVENT_ACTION_DOWN: Int = 0x0000;
pub const AKEY_EVENT_ACTION_UP: Int = 0x0001;
pub const AKEY_EVENT_ACTION_MULTIPLE: Int = 0x0002;

// AKEY_EVENT_FLAG_* (android/input.h)
pub const AKEY_EVENT_FLAG_WOKE_HERE: Int = 0x0001;
pub const AKEY_EVENT_FLAG_SOFT_KEYBOARD: Int = 0x0002;
pub const AKEY_EVENT_FLAG_KEEP_TOUCH_MODE: Int = 0x0004;
pub const AKEY_EVENT_FLAG_FROM_SYSTEM: Int = 0x0008;
pub const AKEY_EVENT_FLAG_EDITOR_ACTION: Int = 0x0010;
pub const AKEY_EVENT_FLAG_CANCELED: Int = 0x0020;
pub const AKEY_EVENT_FLAG_VIRTUAL_HARD_KEY: Int = 0x0040;
pub const AKEY_EVENT_FLAG_LONG_PRESS: Int = 0x0080;
pub const AKEY_EVENT_FLAG_CANCELED_LONG_PRESS: Int = 0x0100;
pub const AKEY_EVENT_FLAG_TRACKING: Int = 0x0200;
pub const AKEY_EVENT_FLAG_FALLBACK: Int = 0x0400;

// AKEY_STATE_* (android/input.h)
pub const AKEY_STATE_UNKNOWN: Int = 0xFFFFFFFF;
pub const AKEY_STATE_UP: Int = 0x0000;
pub const AKEY_STATE_DOWN: Int = 0x0001;
pub const AKEY_STATE_VIRTUAL: Int = 0x0002;

// AMETA_* meta states (android/input.h)
pub const AMETA_NONE: Int = 0x0000;
pub const AMETA_ALT_ON: Int = 0x0002;
pub const AMETA_ALT_LEFT_ON: Int = 0x0010;
pub const AMETA_ALT_RIGHT_ON: Int = 0x0020;
pub const AMETA_SHIFT_ON: Int = 0x0001;
pub const AMETA_SHIFT_LEFT_ON: Int = 0x0040;
pub const AMETA_SHIFT_RIGHT_ON: Int = 0x0080;
pub const AMETA_SYM_ON: Int = 0x0004;
pub const AMETA_FUNCTION_ON: Int = 0x0008;
pub const AMETA_CTRL_ON: Int = 0x1000;
pub const AMETA_CTRL_LEFT_ON: Int = 0x2000;
pub const AMETA_CTRL_RIGHT_ON: Int = 0x4000;
pub const AMETA_META_ON: Int = 0x10000;
pub const AMETA_META_LEFT_ON: Int = 0x20000;
pub const AMETA_META_RIGHT_ON: Int = 0x40000;
pub const AMETA_CAPS_LOCK_ON: Int = 0x100000;
pub const AMETA_NUM_LOCK_ON: Int = 0x200000;
pub const AMETA_SCROLL_LOCK_ON: Int = 0x400000;

// AMOTION_EVENT_ACTION_* (android/input.h)
pub const AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT: Int = 0x0008;
pub const AMOTION_EVENT_ACTION_MASK: Int = 0x00FF;
pub const AMOTION_EVENT_ACTION_POINTER_INDEX_MASK: Int = 0xFF00;
pub const AMOTION_EVENT_ACTION_DOWN: Int = 0x0000;
pub const AMOTION_EVENT_ACTION_UP: Int = 0x0001;
pub const AMOTION_EVENT_ACTION_MOVE: Int = 0x0002;
pub const AMOTION_EVENT_ACTION_CANCEL: Int = 0x0003;
pub const AMOTION_EVENT_ACTION_OUTSIDE: Int = 0x0004;
pub const AMOTION_EVENT_ACTION_POINTER_DOWN: Int = 0x0005;
pub const AMOTION_EVENT_ACTION_POINTER_UP: Int = 0x0006;
pub const AMOTION_EVENT_ACTION_HOVER_MOVE: Int = 0x0007;
pub const AMOTION_EVENT_ACTION_SCROLL: Int = 0x0008;
pub const AMOTION_EVENT_ACTION_HOVER_ENTER: Int = 0x0009;
pub const AMOTION_EVENT_ACTION_HOVER_EXIT: Int = 0x000A;
pub const AMOTION_EVENT_ACTION_BUTTON_PRESS: Int = 0x000B;
pub const AMOTION_EVENT_ACTION_BUTTON_RELEASE: Int = 0x000C;

// AMOTION_EVENT_FLAG_* (android/input.h)
pub const AMOTION_EVENT_FLAG_WINDOW_IS_OBSCURED: Int = 0x0001;

// AMOTION_EVENT_BUTTON_* (android/input.h)
pub const AMOTION_EVENT_BUTTON_PRIMARY: Int = 0x0001;
pub const AMOTION_EVENT_BUTTON_SECONDARY: Int = 0x0002;
pub const AMOTION_EVENT_BUTTON_TERTIARY: Int = 0x0004;
pub const AMOTION_EVENT_BUTTON_BACK: Int = 0x0008;
pub const AMOTION_EVENT_BUTTON_FORWARD: Int = 0x0010;
pub const AMOTION_EVENT_BUTTON_STYLUS_PRIMARY: Int = 0x0020;
pub const AMOTION_EVENT_BUTTON_STYLUS_SECONDARY: Int = 0x0040;

// AMOTION_EVENT_EDGE_FLAG_* (android/input.h)
pub const AMOTION_EVENT_EDGE_FLAG_NONE: Int = 0x0000;
pub const AMOTION_EVENT_EDGE_FLAG_TOP: Int = 0x0001;
pub const AMOTION_EVENT_EDGE_FLAG_BOTTOM: Int = 0x0002;
pub const AMOTION_EVENT_EDGE_FLAG_LEFT: Int = 0x0004;
pub const AMOTION_EVENT_EDGE_FLAG_RIGHT: Int = 0x0008;

// AMOTION_EVENT_TOOL_TYPE_* (android/input.h)
pub const AMOTION_EVENT_TOOL_TYPE_UNKNOWN: Int = 0x0000;
pub const AMOTION_EVENT_TOOL_TYPE_FINGER: Int = 0x0001;
pub const AMOTION_EVENT_TOOL_TYPE_STYLUS: Int = 0x0002;
pub const AMOTION_EVENT_TOOL_TYPE_MOUSE: Int = 0x0003;
pub const AMOTION_EVENT_TOOL_TYPE_ERASER: Int = 0x0004;
pub const AMOTION_EVENT_TOOL_TYPE_PALM: Int = 0x0005;

// AMOTION_EVENT_AXIS_* (android/input.h)
pub const AMOTION_EVENT_AXIS_X: Int = 0;
pub const AMOTION_EVENT_AXIS_Y: Int = 1;
pub const AMOTION_EVENT_AXIS_PRESSURE: Int = 2;
pub const AMOTION_EVENT_AXIS_SIZE: Int = 3;
pub const AMOTION_EVENT_AXIS_TOUCH_MAJOR: Int = 4;
pub const AMOTION_EVENT_AXIS_TOUCH_MINOR: Int = 5;
pub const AMOTION_EVENT_AXIS_TOOL_MAJOR: Int = 6;
pub const AMOTION_EVENT_AXIS_TOOL_MINOR: Int = 7;
pub const AMOTION_EVENT_AXIS_ORIENTATION: Int = 8;
pub const AMOTION_EVENT_AXIS_VSCROLL: Int = 9;
pub const AMOTION_EVENT_AXIS_HSCROLL: Int = 10;
pub const AMOTION_EVENT_AXIS_Z: Int = 11;
pub const AMOTION_EVENT_AXIS_RX: Int = 12;
pub const AMOTION_EVENT_AXIS_RY: Int = 13;
pub const AMOTION_EVENT_AXIS_RZ: Int = 14;
pub const AMOTION_EVENT_AXIS_HAT_X: Int = 15;
pub const AMOTION_EVENT_AXIS_HAT_Y: Int = 16;
pub const AMOTION_EVENT_AXIS_LTRIGGER: Int = 17;
pub const AMOTION_EVENT_AXIS_RTRIGGER: Int = 18;
pub const AMOTION_EVENT_AXIS_THROTTLE: Int = 19;
pub const AMOTION_EVENT_AXIS_RUDDER: Int = 20;
pub const AMOTION_EVENT_AXIS_WHEEL: Int = 21;
pub const AMOTION_EVENT_AXIS_GAS: Int = 22;
pub const AMOTION_EVENT_AXIS_BRAKE: Int = 23;
pub const AMOTION_EVENT_AXIS_DISTANCE: Int = 24;
pub const AMOTION_EVENT_AXIS_TILT: Int = 25;
pub const AMOTION_EVENT_AXIS_SCROLL: Int = 26;
pub const AMOTION_EVENT_AXIS_RELATIVE_X: Int = 27;
pub const AMOTION_EVENT_AXIS_RELATIVE_Y: Int = 28;
pub const AMOTION_EVENT_AXIS_GENERIC_1: Int = 32;
pub const AMOTION_EVENT_AXIS_GENERIC_2: Int = 33;
pub const AMOTION_EVENT_AXIS_GENERIC_3: Int = 34;
pub const AMOTION_EVENT_AXIS_GENERIC_4: Int = 35;
pub const AMOTION_EVENT_AXIS_GENERIC_5: Int = 36;
pub const AMOTION_EVENT_AXIS_GENERIC_6: Int = 37;
pub const AMOTION_EVENT_AXIS_GENERIC_7: Int = 38;
pub const AMOTION_EVENT_AXIS_GENERIC_8: Int = 39;
pub const AMOTION_EVENT_AXIS_GENERIC_9: Int = 40;
pub const AMOTION_EVENT_AXIS_GENERIC_10: Int = 41;
pub const AMOTION_EVENT_AXIS_GENERIC_11: Int = 42;
pub const AMOTION_EVENT_AXIS_GENERIC_12: Int = 43;
pub const AMOTION_EVENT_AXIS_GENERIC_13: Int = 44;
pub const AMOTION_EVENT_AXIS_GENERIC_14: Int = 45;
pub const AMOTION_EVENT_AXIS_GENERIC_15: Int = 46;
pub const AMOTION_EVENT_AXIS_GENERIC_16: Int = 47;
pub const AMOTION_EVENT_AXIS_GESTURE_X_OFFSET: Int = 48;
pub const AMOTION_EVENT_AXIS_GESTURE_Y_OFFSET: Int = 49;
pub const AMOTION_EVENT_AXIS_GESTURE_SCROLL_X_DISTANCE: Int = 50;
pub const AMOTION_EVENT_AXIS_GESTURE_SCROLL_Y_DISTANCE: Int = 51;
pub const AMOTION_EVENT_AXIS_GESTURE_PINCH_SCALE_FACTOR: Int = 52;
pub const AMOTION_EVENT_AXIS_GESTURE_SWIPE_FINGER_COUNT: Int = 53;

// AMOTION_EVENT_CLASSIFICATION_* (android/input.h)
pub const AMOTION_EVENT_CLASSIFICATION_NONE: Int = 0x0000;
pub const AMOTION_EVENT_CLASSIFICATION_AMBIGUOUS_GESTURE: Int = 0x0001;
pub const AMOTION_EVENT_CLASSIFICATION_DEEP_PRESS: Int = 0x0002;
pub const AMOTION_EVENT_CLASSIFICATION_TWO_FINGER_SWIPE: Int = 0x0003;
pub const AMOTION_EVENT_CLASSIFICATION_MULTI_FINGER_SWIPE: Int = 0x0004;
pub const AMOTION_EVENT_CLASSIFICATION_PINCH: Int = 0x0005;

// AKEYCODE_* key codes (android/keycodes.h, frozen enum)
pub const AKEYCODE_UNKNOWN: Int = 0;
pub const AKEYCODE_SOFT_LEFT: Int = 1;
pub const AKEYCODE_SOFT_RIGHT: Int = 2;
pub const AKEYCODE_HOME: Int = 3;
pub const AKEYCODE_BACK: Int = 4;
pub const AKEYCODE_CALL: Int = 5;
pub const AKEYCODE_ENDCALL: Int = 6;
pub const AKEYCODE_0: Int = 7;
pub const AKEYCODE_1: Int = 8;
pub const AKEYCODE_2: Int = 9;
pub const AKEYCODE_3: Int = 10;
pub const AKEYCODE_4: Int = 11;
pub const AKEYCODE_5: Int = 12;
pub const AKEYCODE_6: Int = 13;
pub const AKEYCODE_7: Int = 14;
pub const AKEYCODE_8: Int = 15;
pub const AKEYCODE_9: Int = 16;
pub const AKEYCODE_STAR: Int = 17;
pub const AKEYCODE_POUND: Int = 18;
pub const AKEYCODE_DPAD_UP: Int = 19;
pub const AKEYCODE_DPAD_DOWN: Int = 20;
pub const AKEYCODE_DPAD_LEFT: Int = 21;
pub const AKEYCODE_DPAD_RIGHT: Int = 22;
pub const AKEYCODE_DPAD_CENTER: Int = 23;
pub const AKEYCODE_VOLUME_UP: Int = 24;
pub const AKEYCODE_VOLUME_DOWN: Int = 25;
pub const AKEYCODE_POWER: Int = 26;
pub const AKEYCODE_CAMERA: Int = 27;
pub const AKEYCODE_CLEAR: Int = 28;
pub const AKEYCODE_A: Int = 29;
pub const AKEYCODE_B: Int = 30;
pub const AKEYCODE_C: Int = 31;
pub const AKEYCODE_D: Int = 32;
pub const AKEYCODE_E: Int = 33;
pub const AKEYCODE_F: Int = 34;
pub const AKEYCODE_G: Int = 35;
pub const AKEYCODE_H: Int = 36;
pub const AKEYCODE_I: Int = 37;
pub const AKEYCODE_J: Int = 38;
pub const AKEYCODE_K: Int = 39;
pub const AKEYCODE_L: Int = 40;
pub const AKEYCODE_M: Int = 41;
pub const AKEYCODE_N: Int = 42;
pub const AKEYCODE_O: Int = 43;
pub const AKEYCODE_P: Int = 44;
pub const AKEYCODE_Q: Int = 45;
pub const AKEYCODE_R: Int = 46;
pub const AKEYCODE_S: Int = 47;
pub const AKEYCODE_T: Int = 48;
pub const AKEYCODE_U: Int = 49;
pub const AKEYCODE_V: Int = 50;
pub const AKEYCODE_W: Int = 51;
pub const AKEYCODE_X: Int = 52;
pub const AKEYCODE_Y: Int = 53;
pub const AKEYCODE_Z: Int = 54;
pub const AKEYCODE_COMMA: Int = 55;
pub const AKEYCODE_PERIOD: Int = 56;
pub const AKEYCODE_ALT_LEFT: Int = 57;
pub const AKEYCODE_ALT_RIGHT: Int = 58;
pub const AKEYCODE_SHIFT_LEFT: Int = 59;
pub const AKEYCODE_SHIFT_RIGHT: Int = 60;
pub const AKEYCODE_TAB: Int = 61;
pub const AKEYCODE_SPACE: Int = 62;
pub const AKEYCODE_SYM: Int = 63;
pub const AKEYCODE_EXPLORER: Int = 64;
pub const AKEYCODE_ENVELOPE: Int = 65;
pub const AKEYCODE_ENTER: Int = 66;
pub const AKEYCODE_DEL: Int = 67;
pub const AKEYCODE_GRAVE: Int = 68;
pub const AKEYCODE_MINUS: Int = 69;
pub const AKEYCODE_EQUALS: Int = 70;
pub const AKEYCODE_LEFT_BRACKET: Int = 71;
pub const AKEYCODE_RIGHT_BRACKET: Int = 72;
pub const AKEYCODE_BACKSLASH: Int = 73;
pub const AKEYCODE_SEMICOLON: Int = 74;
pub const AKEYCODE_APOSTROPHE: Int = 75;
pub const AKEYCODE_SLASH: Int = 76;
pub const AKEYCODE_AT: Int = 77;
pub const AKEYCODE_NUM: Int = 78;
pub const AKEYCODE_HEADSETHOOK: Int = 79;
pub const AKEYCODE_FOCUS: Int = 80;
pub const AKEYCODE_PLUS: Int = 81;
pub const AKEYCODE_MENU: Int = 82;
pub const AKEYCODE_NOTIFICATION: Int = 83;
pub const AKEYCODE_SEARCH: Int = 84;
pub const AKEYCODE_MEDIA_PLAY_PAUSE: Int = 85;
pub const AKEYCODE_MEDIA_STOP: Int = 86;
pub const AKEYCODE_MEDIA_NEXT: Int = 87;
pub const AKEYCODE_MEDIA_PREVIOUS: Int = 88;
pub const AKEYCODE_MEDIA_REWIND: Int = 89;
pub const AKEYCODE_MEDIA_FAST_FORWARD: Int = 90;
pub const AKEYCODE_MUTE: Int = 91;
pub const AKEYCODE_PAGE_UP: Int = 92;
pub const AKEYCODE_PAGE_DOWN: Int = 93;
pub const AKEYCODE_PICTSYMBOLS: Int = 94;
pub const AKEYCODE_SWITCH_CHARSET: Int = 95;
pub const AKEYCODE_BUTTON_A: Int = 96;
pub const AKEYCODE_BUTTON_B: Int = 97;
pub const AKEYCODE_BUTTON_C: Int = 98;
pub const AKEYCODE_BUTTON_X: Int = 99;
pub const AKEYCODE_BUTTON_Y: Int = 100;
pub const AKEYCODE_BUTTON_Z: Int = 101;
pub const AKEYCODE_BUTTON_L1: Int = 102;
pub const AKEYCODE_BUTTON_R1: Int = 103;
pub const AKEYCODE_BUTTON_L2: Int = 104;
pub const AKEYCODE_BUTTON_R2: Int = 105;
pub const AKEYCODE_BUTTON_THUMBL: Int = 106;
pub const AKEYCODE_BUTTON_THUMBR: Int = 107;
pub const AKEYCODE_BUTTON_START: Int = 108;
pub const AKEYCODE_BUTTON_SELECT: Int = 109;
pub const AKEYCODE_BUTTON_MODE: Int = 110;
pub const AKEYCODE_ESCAPE: Int = 111;
pub const AKEYCODE_FORWARD_DEL: Int = 112;
pub const AKEYCODE_CTRL_LEFT: Int = 113;
pub const AKEYCODE_CTRL_RIGHT: Int = 114;
pub const AKEYCODE_CAPS_LOCK: Int = 115;
pub const AKEYCODE_SCROLL_LOCK: Int = 116;
pub const AKEYCODE_META_LEFT: Int = 117;
pub const AKEYCODE_META_RIGHT: Int = 118;
pub const AKEYCODE_FUNCTION: Int = 119;
pub const AKEYCODE_SYSRQ: Int = 120;
pub const AKEYCODE_BREAK: Int = 121;
pub const AKEYCODE_MOVE_HOME: Int = 122;
pub const AKEYCODE_MOVE_END: Int = 123;
pub const AKEYCODE_INSERT: Int = 124;
pub const AKEYCODE_FORWARD: Int = 125;
pub const AKEYCODE_MEDIA_PLAY: Int = 126;
pub const AKEYCODE_MEDIA_PAUSE: Int = 127;
pub const AKEYCODE_MEDIA_CLOSE: Int = 128;
pub const AKEYCODE_MEDIA_EJECT: Int = 129;
pub const AKEYCODE_MEDIA_RECORD: Int = 130;
pub const AKEYCODE_F1: Int = 131;
pub const AKEYCODE_F2: Int = 132;
pub const AKEYCODE_F3: Int = 133;
pub const AKEYCODE_F4: Int = 134;
pub const AKEYCODE_F5: Int = 135;
pub const AKEYCODE_F6: Int = 136;
pub const AKEYCODE_F7: Int = 137;
pub const AKEYCODE_F8: Int = 138;
pub const AKEYCODE_F9: Int = 139;
pub const AKEYCODE_F10: Int = 140;
pub const AKEYCODE_F11: Int = 141;
pub const AKEYCODE_F12: Int = 142;
pub const AKEYCODE_NUM_LOCK: Int = 143;
pub const AKEYCODE_NUMPAD_0: Int = 144;
pub const AKEYCODE_NUMPAD_1: Int = 145;
pub const AKEYCODE_NUMPAD_2: Int = 146;
pub const AKEYCODE_NUMPAD_3: Int = 147;
pub const AKEYCODE_NUMPAD_4: Int = 148;
pub const AKEYCODE_NUMPAD_5: Int = 149;
pub const AKEYCODE_NUMPAD_6: Int = 150;
pub const AKEYCODE_NUMPAD_7: Int = 151;
pub const AKEYCODE_NUMPAD_8: Int = 152;
pub const AKEYCODE_NUMPAD_9: Int = 153;
pub const AKEYCODE_NUMPAD_DIVIDE: Int = 154;
pub const AKEYCODE_NUMPAD_MULTIPLY: Int = 155;
pub const AKEYCODE_NUMPAD_SUBTRACT: Int = 156;
pub const AKEYCODE_NUMPAD_ADD: Int = 157;
pub const AKEYCODE_NUMPAD_DOT: Int = 158;
pub const AKEYCODE_NUMPAD_COMMA: Int = 159;
pub const AKEYCODE_NUMPAD_ENTER: Int = 160;
pub const AKEYCODE_NUMPAD_EQUALS: Int = 161;
pub const AKEYCODE_NUMPAD_LEFT_PAREN: Int = 162;
pub const AKEYCODE_NUMPAD_RIGHT_PAREN: Int = 163;
pub const AKEYCODE_VOLUME_MUTE: Int = 164;
pub const AKEYCODE_INFO: Int = 165;
pub const AKEYCODE_CHANNEL_UP: Int = 166;
pub const AKEYCODE_CHANNEL_DOWN: Int = 167;
pub const AKEYCODE_ZOOM_IN: Int = 168;
pub const AKEYCODE_ZOOM_OUT: Int = 169;
pub const AKEYCODE_TV: Int = 170;
pub const AKEYCODE_WINDOW: Int = 171;
pub const AKEYCODE_GUIDE: Int = 172;
pub const AKEYCODE_DVR: Int = 173;
pub const AKEYCODE_BOOKMARK: Int = 174;
pub const AKEYCODE_CAPTIONS: Int = 175;
pub const AKEYCODE_SETTINGS: Int = 176;
pub const AKEYCODE_TV_POWER: Int = 177;
pub const AKEYCODE_TV_INPUT: Int = 178;
pub const AKEYCODE_STB_POWER: Int = 179;
pub const AKEYCODE_STB_INPUT: Int = 180;
pub const AKEYCODE_AVR_POWER: Int = 181;
pub const AKEYCODE_AVR_INPUT: Int = 182;
pub const AKEYCODE_PROG_RED: Int = 183;
pub const AKEYCODE_PROG_GREEN: Int = 184;
pub const AKEYCODE_PROG_YELLOW: Int = 185;
pub const AKEYCODE_PROG_BLUE: Int = 186;
pub const AKEYCODE_APP_SWITCH: Int = 187;
pub const AKEYCODE_BUTTON_1: Int = 188;
pub const AKEYCODE_BUTTON_2: Int = 189;
pub const AKEYCODE_BUTTON_3: Int = 190;
pub const AKEYCODE_BUTTON_4: Int = 191;
pub const AKEYCODE_BUTTON_5: Int = 192;
pub const AKEYCODE_BUTTON_6: Int = 193;
pub const AKEYCODE_BUTTON_7: Int = 194;
pub const AKEYCODE_BUTTON_8: Int = 195;
pub const AKEYCODE_BUTTON_9: Int = 196;
pub const AKEYCODE_BUTTON_10: Int = 197;
pub const AKEYCODE_BUTTON_11: Int = 198;
pub const AKEYCODE_BUTTON_12: Int = 199;
pub const AKEYCODE_BUTTON_13: Int = 200;
pub const AKEYCODE_BUTTON_14: Int = 201;
pub const AKEYCODE_BUTTON_15: Int = 202;
pub const AKEYCODE_BUTTON_16: Int = 203;
pub const AKEYCODE_LANGUAGE_SWITCH: Int = 204;
pub const AKEYCODE_MANNER_MODE: Int = 205;
pub const AKEYCODE_3D_MODE: Int = 206;
pub const AKEYCODE_CONTACTS: Int = 207;
pub const AKEYCODE_CALENDAR: Int = 208;
pub const AKEYCODE_MUSIC: Int = 209;
pub const AKEYCODE_CALCULATOR: Int = 210;
pub const AKEYCODE_ZENKAKU_HANKAKU: Int = 211;
pub const AKEYCODE_EISU: Int = 212;
pub const AKEYCODE_MUHENKAN: Int = 213;
pub const AKEYCODE_HENKAN: Int = 214;
pub const AKEYCODE_KATAKANA_HIRAGANA: Int = 215;
pub const AKEYCODE_YEN: Int = 216;
pub const AKEYCODE_RO: Int = 217;
pub const AKEYCODE_KANA: Int = 218;
pub const AKEYCODE_ASSIST: Int = 219;
pub const AKEYCODE_BRIGHTNESS_DOWN: Int = 220;
pub const AKEYCODE_BRIGHTNESS_UP: Int = 221;
pub const AKEYCODE_MEDIA_AUDIO_TRACK: Int = 222;
pub const AKEYCODE_SLEEP: Int = 223;
pub const AKEYCODE_WAKEUP: Int = 224;
pub const AKEYCODE_PAIRING: Int = 225;
pub const AKEYCODE_MEDIA_TOP_MENU: Int = 226;
pub const AKEYCODE_11: Int = 227;
pub const AKEYCODE_12: Int = 228;
pub const AKEYCODE_LAST_CHANNEL: Int = 229;
pub const AKEYCODE_TV_DATA_SERVICE: Int = 230;
pub const AKEYCODE_VOICE_ASSIST: Int = 231;
pub const AKEYCODE_TV_RADIO_SERVICE: Int = 232;
pub const AKEYCODE_TV_TELETEXT: Int = 233;
pub const AKEYCODE_TV_NUMBER_ENTRY: Int = 234;
pub const AKEYCODE_TV_TERRESTRIAL_ANALOG: Int = 235;
pub const AKEYCODE_TV_TERRESTRIAL_DIGITAL: Int = 236;
pub const AKEYCODE_TV_SATELLITE: Int = 237;
pub const AKEYCODE_TV_SATELLITE_BS: Int = 238;
pub const AKEYCODE_TV_SATELLITE_CS: Int = 239;
pub const AKEYCODE_TV_SATELLITE_SERVICE: Int = 240;
pub const AKEYCODE_TV_NETWORK: Int = 241;
pub const AKEYCODE_TV_ANTENNA_CABLE: Int = 242;
pub const AKEYCODE_TV_INPUT_HDMI_1: Int = 243;
pub const AKEYCODE_TV_INPUT_HDMI_2: Int = 244;
pub const AKEYCODE_TV_INPUT_HDMI_3: Int = 245;
pub const AKEYCODE_TV_INPUT_HDMI_4: Int = 246;
pub const AKEYCODE_TV_INPUT_COMPOSITE_1: Int = 247;
pub const AKEYCODE_TV_INPUT_COMPOSITE_2: Int = 248;
pub const AKEYCODE_TV_INPUT_COMPONENT_1: Int = 249;
pub const AKEYCODE_TV_INPUT_COMPONENT_2: Int = 250;
pub const AKEYCODE_TV_INPUT_VGA_1: Int = 251;
pub const AKEYCODE_TV_AUDIO_DESCRIPTION: Int = 252;
pub const AKEYCODE_TV_AUDIO_DESCRIPTION_MIX_UP: Int = 253;
pub const AKEYCODE_TV_AUDIO_DESCRIPTION_MIX_DOWN: Int = 254;
pub const AKEYCODE_TV_ZOOM_MODE: Int = 255;
pub const AKEYCODE_TV_CONTENTS_MENU: Int = 256;
pub const AKEYCODE_TV_MEDIA_CONTEXT_MENU: Int = 257;
pub const AKEYCODE_TV_TIMER_PROGRAMMING: Int = 258;
pub const AKEYCODE_HELP: Int = 259;
pub const AKEYCODE_NAVIGATE_PREVIOUS: Int = 260;
pub const AKEYCODE_NAVIGATE_NEXT: Int = 261;
pub const AKEYCODE_NAVIGATE_IN: Int = 262;
pub const AKEYCODE_NAVIGATE_OUT: Int = 263;
pub const AKEYCODE_STEM_PRIMARY: Int = 264;
pub const AKEYCODE_STEM_1: Int = 265;
pub const AKEYCODE_STEM_2: Int = 266;
pub const AKEYCODE_STEM_3: Int = 267;
pub const AKEYCODE_DPAD_UP_LEFT: Int = 268;
pub const AKEYCODE_DPAD_DOWN_LEFT: Int = 269;
pub const AKEYCODE_DPAD_UP_RIGHT: Int = 270;
pub const AKEYCODE_DPAD_DOWN_RIGHT: Int = 271;
pub const AKEYCODE_MEDIA_SKIP_FORWARD: Int = 272;
pub const AKEYCODE_MEDIA_SKIP_BACKWARD: Int = 273;
pub const AKEYCODE_MEDIA_STEP_FORWARD: Int = 274;
pub const AKEYCODE_MEDIA_STEP_BACKWARD: Int = 275;
pub const AKEYCODE_SOFT_SLEEP: Int = 276;
pub const AKEYCODE_CUT: Int = 277;
pub const AKEYCODE_COPY: Int = 278;
pub const AKEYCODE_PASTE: Int = 279;
pub const AKEYCODE_SYSTEM_NAVIGATION_UP: Int = 280;
pub const AKEYCODE_SYSTEM_NAVIGATION_DOWN: Int = 281;
pub const AKEYCODE_SYSTEM_NAVIGATION_LEFT: Int = 282;
pub const AKEYCODE_SYSTEM_NAVIGATION_RIGHT: Int = 283;
pub const AKEYCODE_ALL_APPS: Int = 284;
pub const AKEYCODE_REFRESH: Int = 285;
pub const AKEYCODE_THUMBS_UP: Int = 286;
pub const AKEYCODE_THUMBS_DOWN: Int = 287;
pub const AKEYCODE_PROFILE_SWITCH: Int = 288;
pub const AKEYCODE_VIDEO_APP_1: Int = 289;
pub const AKEYCODE_VIDEO_APP_2: Int = 290;
pub const AKEYCODE_VIDEO_APP_3: Int = 291;
pub const AKEYCODE_VIDEO_APP_4: Int = 292;
pub const AKEYCODE_VIDEO_APP_5: Int = 293;
pub const AKEYCODE_VIDEO_APP_6: Int = 294;
pub const AKEYCODE_VIDEO_APP_7: Int = 295;
pub const AKEYCODE_VIDEO_APP_8: Int = 296;
pub const AKEYCODE_FEATURED_APP_1: Int = 297;
pub const AKEYCODE_FEATURED_APP_2: Int = 298;
pub const AKEYCODE_FEATURED_APP_3: Int = 299;
pub const AKEYCODE_FEATURED_APP_4: Int = 300;
pub const AKEYCODE_DEMO_APP_1: Int = 301;
pub const AKEYCODE_DEMO_APP_2: Int = 302;
pub const AKEYCODE_DEMO_APP_3: Int = 303;
pub const AKEYCODE_DEMO_APP_4: Int = 304;
pub const AKEYCODE_KEYBOARD_BACKLIGHT_DOWN: Int = 305;
pub const AKEYCODE_KEYBOARD_BACKLIGHT_UP: Int = 306;
pub const AKEYCODE_KEYBOARD_BACKLIGHT_TOGGLE: Int = 307;
pub const AKEYCODE_STYLUS_BUTTON_PRIMARY: Int = 308;
pub const AKEYCODE_STYLUS_BUTTON_SECONDARY: Int = 309;
pub const AKEYCODE_STYLUS_BUTTON_TERTIARY: Int = 310;
pub const AKEYCODE_STYLUS_BUTTON_TAIL: Int = 311;
pub const AKEYCODE_RECENT_APPS: Int = 312;
pub const AKEYCODE_MACRO_1: Int = 313;
pub const AKEYCODE_MACRO_2: Int = 314;
pub const AKEYCODE_MACRO_3: Int = 315;
pub const AKEYCODE_MACRO_4: Int = 316;

