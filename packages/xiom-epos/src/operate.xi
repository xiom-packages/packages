// XIOM -- xiom.epos.operate: operation mode, state machine, error handling,
// motion info and mode-activation wrappers for the EPOS Command Library.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
// MIT OR Apache-2.0.
//
// 31 entry points of the public header oracle.  All calls are fn-pointer
// casts over the entry table resolved by the root loader; slot discipline
// per the root module notes (B-17/B-24/B-25).

module xiom.epos.operate

use xiom.epos;

// =========================================================================
// Operation mode
// =========================================================================

/// `VCS_SetOperationMode` (`OMD_*`; signed char).  O(1).
pub fn epos_set_operation_mode(lib: &EposLibrary, key_handle: Int, node_id: Int, operation_mode: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_OPERATION_MODE] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, operation_mode as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetOperationMode` (`OMD_*`; signed char read).  O(1).
pub fn epos_get_operation_mode(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(1);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_OPERATION_MODE] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i8(&v, 0) };
}

// =========================================================================
// State machine
// =========================================================================

/// `VCS_ResetDevice`: reset the node.  O(1).
pub fn epos_reset_device(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_RESET_DEVICE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetState` (`ST_*`).  O(1).
pub fn epos_set_state(lib: &EposLibrary, key_handle: Int, node_id: Int, state: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_STATE] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, state as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetEnableState`: enable the node (drive becomes energised).  O(1).
pub fn epos_set_enable_state(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_ENABLE_STATE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetDisableState`: disable the node (drive free).  O(1).
pub fn epos_set_disable_state(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_DISABLE_STATE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetQuickStopState`: quick-stop the motion.  O(1).
pub fn epos_set_quick_stop_state(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_QUICK_STOP_STATE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_ClearFault`: clear the fault state.  O(1).
pub fn epos_clear_fault(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_CLEAR_FAULT] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetState` (`ST_*`).  O(1).
pub fn epos_get_state(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_STATE] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u16(&v, 0) };
}

/// `VCS_GetEnableState` (0/1 flag).  O(1).
pub fn epos_get_enable_state(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_ENABLE_STATE] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_GetDisableState` (0/1 flag).  O(1).
pub fn epos_get_disable_state(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_DISABLE_STATE] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_GetQuickStopState` (0/1 flag).  O(1).
pub fn epos_get_quick_stop_state(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_QUICK_STOP_STATE] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_GetFaultState` (0/1 flag).  O(1).
pub fn epos_get_fault_state(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_FAULT_STATE] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

// =========================================================================
// Error handling
// =========================================================================

/// `VCS_GetNbOfDeviceError`: number of errors currently held by the node.
/// O(1).
pub fn epos_get_nb_of_device_error(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(1);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_NB_OF_DEVICE_ERROR] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u8(&v, 0) };
}

/// `VCS_GetDeviceErrorCode` (1-based error number).  O(1).
pub fn epos_get_device_error_code(lib: &EposLibrary, key_handle: Int, node_id: Int, device_error_number: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
  requires: device_error_number >= 1
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_DEVICE_ERROR_CODE] as fn(Int, Int32, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, device_error_number as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u32(&v, 0) };
}

// =========================================================================
// Motion info
// =========================================================================

/// `VCS_GetMovementState` (0/1: target reached).  O(1).
pub fn epos_get_movement_state(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_MOVEMENT_STATE] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_GetPositionIs` [position units].  O(1).
pub fn epos_get_position_is(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_POSITION_IS] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_GetVelocityIs` [velocity units].  O(1).
pub fn epos_get_velocity_is(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_VELOCITY_IS] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_GetVelocityIsAveraged` [velocity units].  O(1).
pub fn epos_get_velocity_is_averaged(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_VELOCITY_IS_AVERAGED] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_GetCurrentIs` [A, per mille of nominal].  O(1).
pub fn epos_get_current_is(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_CURRENT_IS] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i16(&v, 0) };
}

/// `VCS_GetCurrentIsAveraged` [A, per mille of nominal].  O(1).
pub fn epos_get_current_is_averaged(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_CURRENT_IS_AVERAGED] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i16(&v, 0) };
}

/// `VCS_WaitForTargetReached` (blocking; `timeout` [ms]).  O(1).
pub fn epos_wait_for_target_reached(lib: &EposLibrary, key_handle: Int, node_id: Int, timeout: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: timeout >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_WAIT_FOR_TARGET_REACHED] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, timeout as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

// =========================================================================
// Mode activation
// =========================================================================

/// `VCS_ActivateProfilePositionMode`.  O(1).
pub fn epos_activate_profile_position_mode(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_PROFILE_POSITION_MODE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_ActivateProfileVelocityMode`.  O(1).
pub fn epos_activate_profile_velocity_mode(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_PROFILE_VELOCITY_MODE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_ActivateHomingMode`.  O(1).
pub fn epos_activate_homing_mode(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_HOMING_MODE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_ActivateInterpolatedPositionMode`.  O(1).
pub fn epos_activate_interpolated_position_mode(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_INTERPOLATED_POSITION_MODE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_ActivatePositionMode` (manufacturer-specific).  O(1).
pub fn epos_activate_position_mode(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_POSITION_MODE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_ActivateVelocityMode` (manufacturer-specific).  O(1).
pub fn epos_activate_velocity_mode(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_VELOCITY_MODE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_ActivateCurrentMode` (manufacturer-specific).  O(1).
pub fn epos_activate_current_mode(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_CURRENT_MODE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_ActivateMasterEncoderMode` (manufacturer-specific).  O(1).
pub fn epos_activate_master_encoder_mode(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_MASTER_ENCODER_MODE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_ActivateStepDirectionMode` (manufacturer-specific).  O(1).
pub fn epos_activate_step_direction_mode(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_STEP_DIRECTION_MODE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}
