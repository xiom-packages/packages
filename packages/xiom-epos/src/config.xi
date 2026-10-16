// XIOM -- xiom.epos.config: configuration wrappers for the EPOS Command
// Library (motor, sensor, safety, controller gains, I/O configuration,
// velocity units and the compatibility regulator surface).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
// MIT OR Apache-2.0.
//
// The configuration cluster of the public header oracle, 44 entry points.
// All calls are fn-pointer casts over the entry table resolved by the root
// loader; slot discipline per the root module notes (B-17/B-24/B-25).

module xiom.epos.config

use xiom.epos;

/// `VCS_GetObject` outcome: the payload bytes read out of an owned slot plus
/// the count the library reported.
pub type EposObjectOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  data: Vec[UInt8];
  nb_of_bytes_read: Int;
}

// =========================================================================
// General (object dictionary + persistence)
// =========================================================================

/// `VCS_SetObject`: write object-dictionary data (`pData` from the owned
/// `data` slot; `NbOfBytesToWrite = data.len()`); the bytes-written count is
/// the `value`.  O(data).
pub fn epos_set_object(lib: &EposLibrary, key_handle: Int, node_id: Int, object_index: Int, object_sub_index: Int, data: &Vec[UInt8]) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
  requires: data.len() > 0
{
  var written = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_OBJECT] as fn(Int, Int32, Int32, Int32, *UInt8, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, object_index as Int32, object_sub_index as Int32, data.as_ptr(), data.len() as Int32, written.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    value: epos_rd_u32(&written, 0);
  };
}

/// `VCS_GetObject`: read object-dictionary data into an owned slot of
/// `nb_of_bytes_to_read` and copy out exactly the count the library
/// reported (clamped to the slot size).  O(nb).
pub fn epos_get_object(lib: &EposLibrary, key_handle: Int, node_id: Int, object_index: Int, object_sub_index: Int, nb_of_bytes_to_read: Int) -> EposObjectOut
  requires: lib.h != 0
  requires: key_handle != 0
  requires: nb_of_bytes_to_read > 0
  requires: nb_of_bytes_to_read <= 65536
{
  var slot = epos_slot(nb_of_bytes_to_read);
  var cnt = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_OBJECT] as fn(Int, Int32, Int32, Int32, *UInt8, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, object_index as Int32, object_sub_index as Int32, slot.as_mut_ptr(), nb_of_bytes_to_read as Int32, cnt.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  var ncopy = epos_rd_u32(&cnt, 0);
  if ncopy > nb_of_bytes_to_read { ncopy = nb_of_bytes_to_read; }
  if !(rc == EPOS_RC_OK) { ncopy = 0; }
  return EposObjectOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    data: epos_slot_copy(&slot, ncopy);
    nb_of_bytes_read: ncopy;
  };
}

/// `VCS_Restore`: restore the default parameters in the node.  O(1).
pub fn epos_restore(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_RESTORE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_Store`: store the current parameters in the non-volatile memory.
/// O(1).
pub fn epos_store(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_STORE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

// =========================================================================
// Motor
// =========================================================================

/// `VCS_SetMotorType` (`MT_*`).  O(1).
pub fn epos_set_motor_type(lib: &EposLibrary, key_handle: Int, node_id: Int, motor_type: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_MOTOR_TYPE] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, motor_type as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetDcMotorParameter` (nominal/max current [mA], thermal time constant
/// [ms]).  O(1).
pub fn epos_set_dc_motor_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int, nominal_current: Int, max_output_current: Int, thermal_time_constant: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_DC_MOTOR_PARAMETER] as fn(Int, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, nominal_current as Int32, max_output_current as Int32, thermal_time_constant as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetEcMotorParameter` (EC motor + pole pairs).  O(1).
pub fn epos_set_ec_motor_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int, nominal_current: Int, max_output_current: Int, thermal_time_constant: Int, nb_of_pole_pairs: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: nb_of_pole_pairs > 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_EC_MOTOR_PARAMETER] as fn(Int, Int32, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, nominal_current as Int32, max_output_current as Int32, thermal_time_constant as Int32, nb_of_pole_pairs as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetMotorType` (`MT_*`).  O(1).
pub fn epos_get_motor_type(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_MOTOR_TYPE] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u16(&v, 0) };
}

/// `VCS_GetDcMotorParameter` (a=nominal, b=max output, c=thermal).  O(1).
pub fn epos_get_dc_motor_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposTripleOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var a = epos_slot(2);
  var b = epos_slot(2);
  var c = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_DC_MOTOR_PARAMETER] as fn(Int, Int32, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, a.as_mut_ptr(), b.as_mut_ptr(), c.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposTripleOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    a: epos_rd_u16(&a, 0);
    b: epos_rd_u16(&b, 0);
    c: epos_rd_u16(&c, 0);
  };
}

/// `VCS_GetEcMotorParameter` (currents/thermal + pole pairs).  O(1).
pub fn epos_get_ec_motor_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposMotorParamsOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var cur_nom = epos_slot(2);
  var cur_max = epos_slot(2);
  var thermal = epos_slot(2);
  var poles = epos_slot(1);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_EC_MOTOR_PARAMETER] as fn(Int, Int32, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, cur_nom.as_mut_ptr(), cur_max.as_mut_ptr(), thermal.as_mut_ptr(), poles.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposMotorParamsOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    nominal_current: epos_rd_u16(&cur_nom, 0);
    max_output_current: epos_rd_u16(&cur_max, 0);
    thermal_time_constant: epos_rd_u16(&thermal, 0);
    nb_of_pole_pairs: epos_rd_u8(&poles, 0);
  };
}

// =========================================================================
// Sensor
// =========================================================================

/// `VCS_SetSensorType` (`ST_*`).  O(1).
pub fn epos_set_sensor_type(lib: &EposLibrary, key_handle: Int, node_id: Int, sensor_type: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_SENSOR_TYPE] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, sensor_type as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetIncEncoderParameter` (resolution + inverted polarity flag).  O(1).
pub fn epos_set_inc_encoder_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int, encoder_resolution: Int, inverted_polarity: Bool) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: encoder_resolution >= 0
{
  let inv: Int32 = if inverted_polarity { 1 } else { 0 };
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_INC_ENCODER_PARAMETER] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, encoder_resolution as Int32, inv, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetHallSensorParameter` (inverted polarity flag).  O(1).
pub fn epos_set_hall_sensor_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int, inverted_polarity: Bool) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  let inv: Int32 = if inverted_polarity { 1 } else { 0 };
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_HALL_SENSOR_PARAMETER] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, inv, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetSsiAbsEncoderParameter` (data rate, multi/single turn bits,
/// inverted polarity).  O(1).
pub fn epos_set_ssi_abs_encoder_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int, data_rate: Int, nb_of_multi_turn_data_bits: Int, nb_of_single_turn_data_bits: Int, inverted_polarity: Bool) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  let inv: Int32 = if inverted_polarity { 1 } else { 0 };
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_SSI_ABS_ENCODER_PARAMETER] as fn(Int, Int32, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, data_rate as Int32, nb_of_multi_turn_data_bits as Int32, nb_of_single_turn_data_bits as Int32, inv, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetSsiAbsEncoderParameterEx` (adds special-data bits, timeout and
/// power-up time).  O(1).
pub fn epos_set_ssi_abs_encoder_parameter_ex(lib: &EposLibrary, key_handle: Int, node_id: Int, data_rate: Int, nb_of_multi_turn_data_bits: Int, nb_of_single_turn_data_bits: Int, nb_of_special_data_bits: Int, inverted_polarity: Bool, timeout: Int, powerup_time: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  let inv: Int32 = if inverted_polarity { 1 } else { 0 };
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_SSI_ABS_ENCODER_PARAMETER_EX] as fn(Int, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, data_rate as Int32, nb_of_multi_turn_data_bits as Int32, nb_of_single_turn_data_bits as Int32, nb_of_special_data_bits as Int32, inv, timeout as Int32, powerup_time as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetSensorType` (`ST_*`).  O(1).
pub fn epos_get_sensor_type(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_SENSOR_TYPE] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u16(&v, 0) };
}

/// `VCS_GetIncEncoderParameter` (a=resolution, b=inverted polarity).
/// O(1).
pub fn epos_get_inc_encoder_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposPairOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var res = epos_slot(4);
  var inv = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_INC_ENCODER_PARAMETER] as fn(Int, Int32, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, res.as_mut_ptr(), inv.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposPairOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    a: epos_rd_u32(&res, 0);
    b: epos_rd_i32(&inv, 0);
  };
}

/// `VCS_GetHallSensorParameter` (inverted polarity).  O(1).
pub fn epos_get_hall_sensor_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_HALL_SENSOR_PARAMETER] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_GetSsiAbsEncoderParameter` (a=data rate, b=multi-turn bits,
/// c=single-turn bits, d=inverted polarity).  O(1).
pub fn epos_get_ssi_abs_encoder_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposQuadOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var a = epos_slot(2);
  var b = epos_slot(2);
  var c = epos_slot(2);
  var d = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_SSI_ABS_ENCODER_PARAMETER] as fn(Int, Int32, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, a.as_mut_ptr(), b.as_mut_ptr(), c.as_mut_ptr(), d.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposQuadOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    a: epos_rd_u16(&a, 0);
    b: epos_rd_u16(&b, 0);
    c: epos_rd_u16(&c, 0);
    d: epos_rd_i32(&d, 0);
  };
}

/// `VCS_GetSsiAbsEncoderParameterEx` (full SSI set incl. special bits,
/// timeout, power-up time).  O(1).
pub fn epos_get_ssi_abs_encoder_parameter_ex(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposSsiParamsOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var rate = epos_slot(2);
  var multi = epos_slot(2);
  var single = epos_slot(2);
  var special = epos_slot(2);
  var inv = epos_slot(4);
  var tmo = epos_slot(2);
  var power = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_SSI_ABS_ENCODER_PARAMETER_EX] as fn(Int, Int32, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, rate.as_mut_ptr(), multi.as_mut_ptr(), single.as_mut_ptr(), special.as_mut_ptr(), inv.as_mut_ptr(), tmo.as_mut_ptr(), power.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposSsiParamsOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    data_rate: epos_rd_u16(&rate, 0);
    nb_of_multi_turn_data_bits: epos_rd_u16(&multi, 0);
    nb_of_single_turn_data_bits: epos_rd_u16(&single, 0);
    nb_of_special_data_bits: epos_rd_u16(&special, 0);
    inverted_polarity: epos_rd_i32(&inv, 0);
    timeout: epos_rd_u16(&tmo, 0);
    powerup_time: epos_rd_u16(&power, 0);
  };
}

// =========================================================================
// Safety
// =========================================================================

/// `VCS_SetMaxFollowingError` [position units].  O(1).
pub fn epos_set_max_following_error(lib: &EposLibrary, key_handle: Int, node_id: Int, max_following_error: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: max_following_error >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_MAX_FOLLOWING_ERROR] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, max_following_error as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetMaxFollowingError`.  O(1).
pub fn epos_get_max_following_error(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_MAX_FOLLOWING_ERROR] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u32(&v, 0) };
}

/// `VCS_SetMaxProfileVelocity` [velocity units].  O(1).
pub fn epos_set_max_profile_velocity(lib: &EposLibrary, key_handle: Int, node_id: Int, max_profile_velocity: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: max_profile_velocity >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_MAX_PROFILE_VELOCITY] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, max_profile_velocity as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetMaxProfileVelocity`.  O(1).
pub fn epos_get_max_profile_velocity(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_MAX_PROFILE_VELOCITY] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u32(&v, 0) };
}

/// `VCS_SetMaxAcceleration` [acceleration units].  O(1).
pub fn epos_set_max_acceleration(lib: &EposLibrary, key_handle: Int, node_id: Int, max_acceleration: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: max_acceleration >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_MAX_ACCELERATION] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, max_acceleration as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetMaxAcceleration`.  O(1).
pub fn epos_get_max_acceleration(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_MAX_ACCELERATION] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u32(&v, 0) };
}

// =========================================================================
// Controller gains
// =========================================================================

/// `VCS_SetControllerGain` (`EC_*` controller, `EG_*` gain, 64-bit value).
/// O(1).
pub fn epos_set_controller_gain(lib: &EposLibrary, key_handle: Int, node_id: Int, e_controller: Int, e_gain: Int, value: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: value >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_CONTROLLER_GAIN] as fn(Int, Int32, Int32, Int32, Int, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, e_controller as Int32, e_gain as Int32, value, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetControllerGain` (64-bit value read out of an owned slot).
/// O(1).
pub fn epos_get_controller_gain(lib: &EposLibrary, key_handle: Int, node_id: Int, e_controller: Int, e_gain: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(8);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_CONTROLLER_GAIN] as fn(Int, Int32, Int32, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, e_controller as Int32, e_gain as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u64(&v, 0) };
}

// =========================================================================
// Inputs / outputs configuration
// =========================================================================

/// `VCS_DigitalInputConfiguration` (`DIC_*`).  O(1).
pub fn epos_digital_input_configuration(lib: &EposLibrary, key_handle: Int, node_id: Int, digital_input_nb: Int, configuration: Int, mask: Int, polarity: Int, execution_mask: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DIGITAL_INPUT_CONFIGURATION] as fn(Int, Int32, Int32, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, digital_input_nb as Int32, configuration as Int32, mask as Int32, polarity as Int32, execution_mask as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_DigitalOutputConfiguration` (`DOC_*`).  O(1).
pub fn epos_digital_output_configuration(lib: &EposLibrary, key_handle: Int, node_id: Int, digital_output_nb: Int, configuration: Int, state: Int, mask: Int, polarity: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DIGITAL_OUTPUT_CONFIGURATION] as fn(Int, Int32, Int32, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, digital_output_nb as Int32, configuration as Int32, state as Int32, mask as Int32, polarity as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_AnalogInputConfiguration` (`AIC_*`).  O(1).
pub fn epos_analog_input_configuration(lib: &EposLibrary, key_handle: Int, node_id: Int, analog_input_nb: Int, configuration: Int, execution_mask: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ANALOG_INPUT_CONFIGURATION] as fn(Int, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, analog_input_nb as Int32, configuration as Int32, execution_mask as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_AnalogOutputConfiguration` (`AOC_*`).  O(1).
pub fn epos_analog_output_configuration(lib: &EposLibrary, key_handle: Int, node_id: Int, analog_output_nb: Int, configuration: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ANALOG_OUTPUT_CONFIGURATION] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, analog_output_nb as Int32, configuration as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

// =========================================================================
// Velocity units
// =========================================================================

/// `VCS_SetVelocityUnits` (`VD_RPM`, `VN_*`).  O(1).
pub fn epos_set_velocity_units(lib: &EposLibrary, key_handle: Int, node_id: Int, velocity_dimension: Int, velocity_notation: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_VELOCITY_UNITS] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, velocity_dimension as Int32, velocity_notation as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetVelocityUnits` (dimension + signed notation).  O(1).
pub fn epos_get_velocity_units(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposVelocityUnitsOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var dim = epos_slot(1);
  var notation = epos_slot(1);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_VELOCITY_UNITS] as fn(Int, Int32, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, dim.as_mut_ptr(), notation.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposVelocityUnitsOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    velocity_dimension: epos_rd_u8(&dim, 0);
    velocity_notation: epos_rd_i8(&notation, 0);
  };
}

// =========================================================================
// Compatibility regulator surface (header marks it "do not use")
// =========================================================================

/// `VCS_SetPositionRegulatorGain` (compat).  O(1).
pub fn epos_set_position_regulator_gain(lib: &EposLibrary, key_handle: Int, node_id: Int, p: Int, i: Int, d: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_POSITION_REGULATOR_GAIN] as fn(Int, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, p as Int32, i as Int32, d as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetPositionRegulatorFeedForward` (compat).  O(1).
pub fn epos_set_position_regulator_feed_forward(lib: &EposLibrary, key_handle: Int, node_id: Int, velocity_feed_forward: Int, acceleration_feed_forward: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_POSITION_REGULATOR_FEED_FORWARD] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, velocity_feed_forward as Int32, acceleration_feed_forward as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetPositionRegulatorGain` (compat; a=P, b=I, c=D).  O(1).
pub fn epos_get_position_regulator_gain(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposTripleOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var a = epos_slot(2);
  var b = epos_slot(2);
  var c = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_POSITION_REGULATOR_GAIN] as fn(Int, Int32, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, a.as_mut_ptr(), b.as_mut_ptr(), c.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposTripleOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    a: epos_rd_u16(&a, 0);
    b: epos_rd_u16(&b, 0);
    c: epos_rd_u16(&c, 0);
  };
}

/// `VCS_GetPositionRegulatorFeedForward` (compat; a=velocity, b=accel).  O(1).
pub fn epos_get_position_regulator_feed_forward(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposPairOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var a = epos_slot(2);
  var b = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_POSITION_REGULATOR_FEED_FORWARD] as fn(Int, Int32, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, a.as_mut_ptr(), b.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposPairOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    a: epos_rd_u16(&a, 0);
    b: epos_rd_u16(&b, 0);
  };
}

/// `VCS_SetVelocityRegulatorGain` (compat).  O(1).
pub fn epos_set_velocity_regulator_gain(lib: &EposLibrary, key_handle: Int, node_id: Int, p: Int, i: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_VELOCITY_REGULATOR_GAIN] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, p as Int32, i as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetVelocityRegulatorFeedForward` (compat).  O(1).
pub fn epos_set_velocity_regulator_feed_forward(lib: &EposLibrary, key_handle: Int, node_id: Int, velocity_feed_forward: Int, acceleration_feed_forward: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_VELOCITY_REGULATOR_FEED_FORWARD] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, velocity_feed_forward as Int32, acceleration_feed_forward as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetVelocityRegulatorGain` (compat; a=P, b=I).  O(1).
pub fn epos_get_velocity_regulator_gain(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposPairOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var a = epos_slot(2);
  var b = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_VELOCITY_REGULATOR_GAIN] as fn(Int, Int32, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, a.as_mut_ptr(), b.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposPairOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    a: epos_rd_u16(&a, 0);
    b: epos_rd_u16(&b, 0);
  };
}

/// `VCS_GetVelocityRegulatorFeedForward` (compat; a=velocity, b=accel).
/// O(1).
pub fn epos_get_velocity_regulator_feed_forward(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposPairOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var a = epos_slot(2);
  var b = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_VELOCITY_REGULATOR_FEED_FORWARD] as fn(Int, Int32, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, a.as_mut_ptr(), b.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposPairOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    a: epos_rd_u16(&a, 0);
    b: epos_rd_u16(&b, 0);
  };
}

/// `VCS_SetCurrentRegulatorGain` (compat).  O(1).
pub fn epos_set_current_regulator_gain(lib: &EposLibrary, key_handle: Int, node_id: Int, p: Int, i: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_CURRENT_REGULATOR_GAIN] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, p as Int32, i as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetCurrentRegulatorGain` (compat; a=P, b=I).  O(1).
pub fn epos_get_current_regulator_gain(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposPairOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var a = epos_slot(2);
  var b = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_CURRENT_REGULATOR_GAIN] as fn(Int, Int32, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, a.as_mut_ptr(), b.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposPairOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    a: epos_rd_u16(&a, 0);
    b: epos_rd_u16(&b, 0);
  };
}
