// XIOM -- xiom.epos.motion: motion wrappers for the EPOS Command Library
// (profile position/velocity, homing, interpolated position, position /
// velocity / current modes, master encoder, step/direction).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
// MIT OR Apache-2.0.
//
// 51 entry points of the public header oracle.  All calls are fn-pointer
// casts over the entry table resolved by the root loader; slot discipline
// per the root module notes (B-17/B-24/B-25).  Activate* mode calls live in
// `xiom.epos.operate`.

module xiom.epos.motion

use xiom.epos;

// =========================================================================
// Profile position mode
// =========================================================================

/// `VCS_SetPositionProfile` (profile velocity / acceleration /
/// deceleration).  O(1).
pub fn epos_set_position_profile(lib: &EposLibrary, key_handle: Int, node_id: Int, profile_velocity: Int, profile_acceleration: Int, profile_deceleration: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_POSITION_PROFILE] as fn(Int, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, profile_velocity as Int32, profile_acceleration as Int32, profile_deceleration as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetPositionProfile` (a=velocity, b=acceleration, c=deceleration).
/// O(1).
pub fn epos_get_position_profile(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposTripleOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var a = epos_slot(4);
  var b = epos_slot(4);
  var c = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_POSITION_PROFILE] as fn(Int, Int32, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, a.as_mut_ptr(), b.as_mut_ptr(), c.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposTripleOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    a: epos_rd_u32(&a, 0);
    b: epos_rd_u32(&b, 0);
    c: epos_rd_u32(&c, 0);
  };
}

/// `VCS_MoveToPosition` (absolute/relative, immediately/queued).  O(1).
pub fn epos_move_to_position(lib: &EposLibrary, key_handle: Int, node_id: Int, target_position: Int, absolute: Bool, immediately: Bool) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  let abs_v: Int32 = if absolute { 1 } else { 0 };
  let imm: Int32 = if immediately { 1 } else { 0 };
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_MOVE_TO_POSITION] as fn(Int, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, target_position as Int32, abs_v, imm, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetTargetPosition` [position units].  O(1).
pub fn epos_get_target_position(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_TARGET_POSITION] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_HaltPositionMovement`.  O(1).
pub fn epos_halt_position_movement(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_HALT_POSITION_MOVEMENT] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_EnablePositionWindow` (window + window time [ms]).  O(1).
pub fn epos_enable_position_window(lib: &EposLibrary, key_handle: Int, node_id: Int, position_window: Int, position_window_time: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: position_window >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ENABLE_POSITION_WINDOW] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, position_window as Int32, position_window_time as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_DisablePositionWindow`.  O(1).
pub fn epos_disable_position_window(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DISABLE_POSITION_WINDOW] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

// =========================================================================
// Profile velocity mode
// =========================================================================

/// `VCS_SetVelocityProfile` (profile acceleration / deceleration).  O(1).
pub fn epos_set_velocity_profile(lib: &EposLibrary, key_handle: Int, node_id: Int, profile_acceleration: Int, profile_deceleration: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_VELOCITY_PROFILE] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, profile_acceleration as Int32, profile_deceleration as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetVelocityProfile` (a=acceleration, b=deceleration).  O(1).
pub fn epos_get_velocity_profile(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposPairOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var a = epos_slot(4);
  var b = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_VELOCITY_PROFILE] as fn(Int, Int32, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, a.as_mut_ptr(), b.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposPairOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    a: epos_rd_u32(&a, 0);
    b: epos_rd_u32(&b, 0);
  };
}

/// `VCS_MoveWithVelocity` [velocity units].  O(1).
pub fn epos_move_with_velocity(lib: &EposLibrary, key_handle: Int, node_id: Int, target_velocity: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_MOVE_WITH_VELOCITY] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, target_velocity as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetTargetVelocity` [velocity units].  O(1).
pub fn epos_get_target_velocity(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_TARGET_VELOCITY] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_HaltVelocityMovement`.  O(1).
pub fn epos_halt_velocity_movement(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_HALT_VELOCITY_MOVEMENT] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_EnableVelocityWindow` (window + window time [ms]).  O(1).
pub fn epos_enable_velocity_window(lib: &EposLibrary, key_handle: Int, node_id: Int, velocity_window: Int, velocity_window_time: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: velocity_window >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ENABLE_VELOCITY_WINDOW] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, velocity_window as Int32, velocity_window_time as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_DisableVelocityWindow`.  O(1).
pub fn epos_disable_velocity_window(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DISABLE_VELOCITY_WINDOW] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

// =========================================================================
// Homing mode
// =========================================================================

/// `VCS_SetHomingParameter` (acceleration, switch/index speeds, offset,
/// current threshold, home position).  O(1).
pub fn epos_set_homing_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int, homing_acceleration: Int, speed_switch: Int, speed_index: Int, home_offset: Int, current_threshold: Int, home_position: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_HOMING_PARAMETER] as fn(Int, Int32, Int32, Int32, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, homing_acceleration as Int32, speed_switch as Int32, speed_index as Int32, home_offset as Int32, current_threshold as Int32, home_position as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetHomingParameter` (full homing parameter set).  O(1).
pub fn epos_get_homing_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposHomingParamsOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var accel = epos_slot(4);
  var sw = epos_slot(4);
  var idx = epos_slot(4);
  var offset = epos_slot(4);
  var thresh = epos_slot(2);
  var pos = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_HOMING_PARAMETER] as fn(Int, Int32, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, accel.as_mut_ptr(), sw.as_mut_ptr(), idx.as_mut_ptr(), offset.as_mut_ptr(), thresh.as_mut_ptr(), pos.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposHomingParamsOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    homing_acceleration: epos_rd_u32(&accel, 0);
    speed_switch: epos_rd_u32(&sw, 0);
    speed_index: epos_rd_u32(&idx, 0);
    home_offset: epos_rd_i32(&offset, 0);
    current_threshold: epos_rd_u16(&thresh, 0);
    home_position: epos_rd_i32(&pos, 0);
  };
}

/// `VCS_FindHome` (`HM_*`, signed char).  O(1).
pub fn epos_find_home(lib: &EposLibrary, key_handle: Int, node_id: Int, homing_method: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_FIND_HOME] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, homing_method as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_StopHoming`.  O(1).
pub fn epos_stop_homing(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_STOP_HOMING] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_DefinePosition`: define the actual position as `home_position`.
/// O(1).
pub fn epos_define_position(lib: &EposLibrary, key_handle: Int, node_id: Int, home_position: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DEFINE_POSITION] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, home_position as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_WaitForHomingAttained` (blocking; `timeout` [ms]).  O(1).
pub fn epos_wait_for_homing_attained(lib: &EposLibrary, key_handle: Int, node_id: Int, timeout: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: timeout >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_WAIT_FOR_HOMING_ATTAINED] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, timeout as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetHomingState` (a=attained, b=error).  O(1).
pub fn epos_get_homing_state(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposPairOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var a = epos_slot(4);
  var b = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_HOMING_STATE] as fn(Int, Int32, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, a.as_mut_ptr(), b.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposPairOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    a: epos_rd_i32(&a, 0);
    b: epos_rd_i32(&b, 0);
  };
}

// =========================================================================
// Interpolated position mode (PVT buffer)
// =========================================================================

/// `VCS_SetIpmBufferParameter` (underflow/overflow warning limits).  O(1).
pub fn epos_set_ipm_buffer_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int, underflow_warning_limit: Int, overflow_warning_limit: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: underflow_warning_limit >= 0
  requires: overflow_warning_limit >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_IPM_BUFFER_PARAMETER] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, underflow_warning_limit as Int32, overflow_warning_limit as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetIpmBufferParameter` (warning limits + max buffer size).  O(1).
pub fn epos_get_ipm_buffer_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposIpmBufferOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var uw = epos_slot(2);
  var ow = epos_slot(2);
  var max_buf = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_IPM_BUFFER_PARAMETER] as fn(Int, Int32, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, uw.as_mut_ptr(), ow.as_mut_ptr(), max_buf.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposIpmBufferOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    underflow_warning_limit: epos_rd_u16(&uw, 0);
    overflow_warning_limit: epos_rd_u16(&ow, 0);
    max_buffer_size: epos_rd_u32(&max_buf, 0);
  };
}

/// `VCS_ClearIpmBuffer`.  O(1).
pub fn epos_clear_ipm_buffer(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_CLEAR_IPM_BUFFER] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetFreeIpmBufferSize`.  O(1).
pub fn epos_get_free_ipm_buffer_size(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_FREE_IPM_BUFFER_SIZE] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u32(&v, 0) };
}

/// `VCS_AddPvtValueToIpmBuffer` (position/velocity/time triple).  O(1).
pub fn epos_add_pvt_value_to_ipm_buffer(lib: &EposLibrary, key_handle: Int, node_id: Int, position: Int, velocity: Int, time: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: time >= 0
  requires: time <= 255
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ADD_PVT_VALUE_TO_IPM_BUFFER] as fn(Int, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, position as Int32, velocity as Int32, time as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_StartIpmTrajectory`.  O(1).
pub fn epos_start_ipm_trajectory(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_START_IPM_TRAJECTORY] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_StopIpmTrajectory`.  O(1).
pub fn epos_stop_ipm_trajectory(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_STOP_IPM_TRAJECTORY] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetIpmStatus` (running flag + warning/error flags).  O(1).
pub fn epos_get_ipm_status(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposIpmStatusOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var a = epos_slot(4);
  var b = epos_slot(4);
  var c = epos_slot(4);
  var d = epos_slot(4);
  var e = epos_slot(4);
  var f = epos_slot(4);
  var g = epos_slot(4);
  var h = epos_slot(4);
  var i = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let fptr = lib.ptrs[EPOS_FN_VCS_GET_IPM_STATUS] as fn(Int, Int32, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = fptr(key_handle, node_id as Int32, a.as_mut_ptr(), b.as_mut_ptr(), c.as_mut_ptr(), d.as_mut_ptr(), e.as_mut_ptr(), f.as_mut_ptr(), g.as_mut_ptr(), h.as_mut_ptr(), i.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposIpmStatusOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    trajectory_running: epos_rd_i32(&a, 0);
    underflow_warning: epos_rd_i32(&b, 0);
    overflow_warning: epos_rd_i32(&c, 0);
    velocity_warning: epos_rd_i32(&d, 0);
    acceleration_warning: epos_rd_i32(&e, 0);
    underflow_error: epos_rd_i32(&f, 0);
    overflow_error: epos_rd_i32(&g, 0);
    velocity_error: epos_rd_i32(&h, 0);
    acceleration_error: epos_rd_i32(&i, 0);
  };
}

// =========================================================================
// Position mode (manufacturer-specific) incl. analog setpoint
// =========================================================================

/// `VCS_SetPositionMust` [position units].  O(1).
pub fn epos_set_position_must(lib: &EposLibrary, key_handle: Int, node_id: Int, position_must: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_POSITION_MUST] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, position_must as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetPositionMust` [position units].  O(1).
pub fn epos_get_position_must(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_POSITION_MUST] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_ActivateAnalogPositionSetpoint` (input, scaling, offset).  O(1).
pub fn epos_activate_analog_position_setpoint(lib: &EposLibrary, key_handle: Int, node_id: Int, analog_input_number: Int, scaling: Float64, offset: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_ANALOG_POSITION_SETPOINT] as fn(Int, Int32, Int32, Float32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, analog_input_number as Int32, scaling as Float32, offset as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_DeactivateAnalogPositionSetpoint` (input).  O(1).
pub fn epos_deactivate_analog_position_setpoint(lib: &EposLibrary, key_handle: Int, node_id: Int, analog_input_number: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DEACTIVATE_ANALOG_POSITION_SETPOINT] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, analog_input_number as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_EnableAnalogPositionSetpoint`.  O(1).
pub fn epos_enable_analog_position_setpoint(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ENABLE_ANALOG_POSITION_SETPOINT] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_DisableAnalogPositionSetpoint`.  O(1).
pub fn epos_disable_analog_position_setpoint(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DISABLE_ANALOG_POSITION_SETPOINT] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

// =========================================================================
// Velocity mode (manufacturer-specific) incl. analog setpoint
// =========================================================================

/// `VCS_SetVelocityMust` [velocity units].  O(1).
pub fn epos_set_velocity_must(lib: &EposLibrary, key_handle: Int, node_id: Int, velocity_must: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_VELOCITY_MUST] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, velocity_must as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetVelocityMust` [velocity units].  O(1).
pub fn epos_get_velocity_must(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_VELOCITY_MUST] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_ActivateAnalogVelocitySetpoint` (input, scaling, offset).  O(1).
pub fn epos_activate_analog_velocity_setpoint(lib: &EposLibrary, key_handle: Int, node_id: Int, analog_input_number: Int, scaling: Float64, offset: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_ANALOG_VELOCITY_SETPOINT] as fn(Int, Int32, Int32, Float32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, analog_input_number as Int32, scaling as Float32, offset as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_DeactivateAnalogVelocitySetpoint` (input).  O(1).
pub fn epos_deactivate_analog_velocity_setpoint(lib: &EposLibrary, key_handle: Int, node_id: Int, analog_input_number: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DEACTIVATE_ANALOG_VELOCITY_SETPOINT] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, analog_input_number as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_EnableAnalogVelocitySetpoint`.  O(1).
pub fn epos_enable_analog_velocity_setpoint(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ENABLE_ANALOG_VELOCITY_SETPOINT] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_DisableAnalogVelocitySetpoint`.  O(1).
pub fn epos_disable_analog_velocity_setpoint(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DISABLE_ANALOG_VELOCITY_SETPOINT] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

// =========================================================================
// Current mode (manufacturer-specific) incl. analog setpoint
// =========================================================================

/// `VCS_SetCurrentMust` [A, per mille of nominal; short].  O(1).
pub fn epos_set_current_must(lib: &EposLibrary, key_handle: Int, node_id: Int, current_must: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_CURRENT_MUST] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, current_must as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetCurrentMust` [A, per mille; signed 16-bit read].  O(1).
pub fn epos_get_current_must(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_CURRENT_MUST] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i16(&v, 0) };
}

/// `VCS_ActivateAnalogCurrentSetpoint` (input, scaling, offset).  O(1).
pub fn epos_activate_analog_current_setpoint(lib: &EposLibrary, key_handle: Int, node_id: Int, analog_input_number: Int, scaling: Float64, offset: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_ANALOG_CURRENT_SETPOINT] as fn(Int, Int32, Int32, Float32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, analog_input_number as Int32, scaling as Float32, offset as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_DeactivateAnalogCurrentSetpoint` (input).  O(1).
pub fn epos_deactivate_analog_current_setpoint(lib: &EposLibrary, key_handle: Int, node_id: Int, analog_input_number: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DEACTIVATE_ANALOG_CURRENT_SETPOINT] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, analog_input_number as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_EnableAnalogCurrentSetpoint`.  O(1).
pub fn epos_enable_analog_current_setpoint(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ENABLE_ANALOG_CURRENT_SETPOINT] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_DisableAnalogCurrentSetpoint`.  O(1).
pub fn epos_disable_analog_current_setpoint(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DISABLE_ANALOG_CURRENT_SETPOINT] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

// =========================================================================
// Master encoder mode
// =========================================================================

/// `VCS_SetMasterEncoderParameter` (scaling, polarity, velocity limits).
/// O(1).
pub fn epos_set_master_encoder_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int, scaling_numerator: Int, scaling_denominator: Int, polarity: Int, max_velocity: Int, max_acceleration: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: scaling_denominator > 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_MASTER_ENCODER_PARAMETER] as fn(Int, Int32, Int32, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, scaling_numerator as Int32, scaling_denominator as Int32, polarity as Int32, max_velocity as Int32, max_acceleration as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetMasterEncoderParameter` (full scaling set).  O(1).
pub fn epos_get_master_encoder_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposScalingOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var num = epos_slot(2);
  var den = epos_slot(2);
  var pol = epos_slot(1);
  var maxv = epos_slot(4);
  var maxa = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_MASTER_ENCODER_PARAMETER] as fn(Int, Int32, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, num.as_mut_ptr(), den.as_mut_ptr(), pol.as_mut_ptr(), maxv.as_mut_ptr(), maxa.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposScalingOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    scaling_numerator: epos_rd_u16(&num, 0);
    scaling_denominator: epos_rd_u16(&den, 0);
    polarity: epos_rd_u8(&pol, 0);
    max_velocity: epos_rd_u32(&maxv, 0);
    max_acceleration: epos_rd_u32(&maxa, 0);
  };
}

// =========================================================================
// Step direction mode
// =========================================================================

/// `VCS_SetStepDirectionParameter` (scaling, polarity, velocity limits).
/// O(1).
pub fn epos_set_step_direction_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int, scaling_numerator: Int, scaling_denominator: Int, polarity: Int, max_velocity: Int, max_acceleration: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: scaling_denominator > 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_STEP_DIRECTION_PARAMETER] as fn(Int, Int32, Int32, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, scaling_numerator as Int32, scaling_denominator as Int32, polarity as Int32, max_velocity as Int32, max_acceleration as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetStepDirectionParameter` (full scaling set).  O(1).
pub fn epos_get_step_direction_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposScalingOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var num = epos_slot(2);
  var den = epos_slot(2);
  var pol = epos_slot(1);
  var maxv = epos_slot(4);
  var maxa = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_STEP_DIRECTION_PARAMETER] as fn(Int, Int32, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, num.as_mut_ptr(), den.as_mut_ptr(), pol.as_mut_ptr(), maxv.as_mut_ptr(), maxa.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposScalingOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    scaling_numerator: epos_rd_u16(&num, 0);
    scaling_denominator: epos_rd_u16(&den, 0);
    polarity: epos_rd_u8(&pol, 0);
    max_velocity: epos_rd_u32(&maxv, 0);
    max_acceleration: epos_rd_u32(&maxa, 0);
  };
}
