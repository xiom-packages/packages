// XIOM -- xiom.epos.io: inputs/outputs, position compare, position marker
// and CAN-layer wrappers for the EPOS Command Library.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
// MIT OR Apache-2.0.
//
// 27 entry points of the public header oracle.  All calls are fn-pointer
// casts over the entry table resolved by the root loader; slot discipline
// per the root module notes (B-17/B-24/B-25).

module xiom.epos.io

use xiom.epos;

/// `VCS_GetPositionCompareParameter` outcome.
pub type EposCompareParamsOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  operational_mode: Int;
  interval_mode: Int;
  direction_dependency: Int;
  interval_width: Int;
  interval_repetitions: Int;
  pulse_width: Int;
}

// =========================================================================
// Inputs / outputs
// =========================================================================

/// `VCS_GetAllDigitalInputs` (bit mask, `DIC_*` bit positions).  O(1).
pub fn epos_get_all_digital_inputs(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_ALL_DIGITAL_INPUTS] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u16(&v, 0) };
}

/// `VCS_GetAllDigitalOutputs` (bit mask, `DOC_*` bit positions).  O(1).
pub fn epos_get_all_digital_outputs(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_ALL_DIGITAL_OUTPUTS] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u16(&v, 0) };
}

/// `VCS_SetAllDigitalOutputs` (bit mask).  O(1).
pub fn epos_set_all_digital_outputs(lib: &EposLibrary, key_handle: Int, node_id: Int, outputs: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: outputs >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_ALL_DIGITAL_OUTPUTS] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, outputs as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetAnalogInput` (raw value).  O(1).
pub fn epos_get_analog_input(lib: &EposLibrary, key_handle: Int, node_id: Int, input_number: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
  requires: input_number >= 0
{
  var v = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_ANALOG_INPUT] as fn(Int, Int32, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, input_number as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u16(&v, 0) };
}

/// `VCS_GetAnalogInputVoltage` [mV].  O(1).
pub fn epos_get_analog_input_voltage(lib: &EposLibrary, key_handle: Int, node_id: Int, input_number: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
  requires: input_number >= 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_ANALOG_INPUT_VOLTAGE] as fn(Int, Int32, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, input_number as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_GetAnalogInputState` (`AIC_*`).  O(1).
pub fn epos_get_analog_input_state(lib: &EposLibrary, key_handle: Int, node_id: Int, configuration: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_ANALOG_INPUT_STATE] as fn(Int, Int32, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, configuration as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_SetAnalogOutput` (raw value).  O(1).
pub fn epos_set_analog_output(lib: &EposLibrary, key_handle: Int, node_id: Int, output_number: Int, analog_value: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: output_number >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_ANALOG_OUTPUT] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, output_number as Int32, analog_value as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetAnalogOutputVoltage` [mV].  O(1).
pub fn epos_set_analog_output_voltage(lib: &EposLibrary, key_handle: Int, node_id: Int, output_number: Int, voltage_value: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: output_number >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_ANALOG_OUTPUT_VOLTAGE] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, output_number as Int32, voltage_value as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetAnalogOutputState` (`AOC_*`).  O(1).
pub fn epos_set_analog_output_state(lib: &EposLibrary, key_handle: Int, node_id: Int, configuration: Int, state_value: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_ANALOG_OUTPUT_STATE] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, configuration as Int32, state_value as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

// =========================================================================
// Position compare
// =========================================================================

/// `VCS_SetPositionCompareParameter` (`PCO_*`, `PCI_*`, `PCD_*`).  O(1).
pub fn epos_set_position_compare_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int, operational_mode: Int, interval_mode: Int, direction_dependency: Int, interval_width: Int, interval_repetitions: Int, pulse_width: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_POSITION_COMPARE_PARAMETER] as fn(Int, Int32, Int32, Int32, Int32, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, operational_mode as Int32, interval_mode as Int32, direction_dependency as Int32, interval_width as Int32, interval_repetitions as Int32, pulse_width as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetPositionCompareParameter` (full compare set).  O(1).
pub fn epos_get_position_compare_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposCompareParamsOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var opm = epos_slot(1);
  var ivm = epos_slot(1);
  var dir = epos_slot(1);
  var wid = epos_slot(2);
  var rep = epos_slot(2);
  var pul = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_POSITION_COMPARE_PARAMETER] as fn(Int, Int32, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, opm.as_mut_ptr(), ivm.as_mut_ptr(), dir.as_mut_ptr(), wid.as_mut_ptr(), rep.as_mut_ptr(), pul.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposCompareParamsOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    operational_mode: epos_rd_u8(&opm, 0);
    interval_mode: epos_rd_u8(&ivm, 0);
    direction_dependency: epos_rd_u8(&dir, 0);
    interval_width: epos_rd_u16(&wid, 0);
    interval_repetitions: epos_rd_u16(&rep, 0);
    pulse_width: epos_rd_u16(&pul, 0);
  };
}

/// `VCS_ActivatePositionCompare` (digital output).  O(1).
pub fn epos_activate_position_compare(lib: &EposLibrary, key_handle: Int, node_id: Int, digital_output_number: Int, polarity: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_POSITION_COMPARE] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, digital_output_number as Int32, polarity as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_DeactivatePositionCompare`.  O(1).
pub fn epos_deactivate_position_compare(lib: &EposLibrary, key_handle: Int, node_id: Int, digital_output_number: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DEACTIVATE_POSITION_COMPARE] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, digital_output_number as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_EnablePositionCompare`.  O(1).
pub fn epos_enable_position_compare(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ENABLE_POSITION_COMPARE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_DisablePositionCompare`.  O(1).
pub fn epos_disable_position_compare(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DISABLE_POSITION_COMPARE] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetPositionCompareReferencePosition` [position units].  O(1).
pub fn epos_set_position_compare_reference_position(lib: &EposLibrary, key_handle: Int, node_id: Int, reference_position: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_POSITION_COMPARE_REFERENCE_POSITION] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, reference_position as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

// =========================================================================
// Position marker
// =========================================================================

/// `VCS_SetPositionMarkerParameter` (`PET_*`, `PM_*`).  O(1).
pub fn epos_set_position_marker_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int, position_marker_edge_type: Int, position_marker_mode: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_POSITION_MARKER_PARAMETER] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, position_marker_edge_type as Int32, position_marker_mode as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetPositionMarkerParameter` (a=edge type, b=mode).  O(1).
pub fn epos_get_position_marker_parameter(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposPairOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var a = epos_slot(1);
  var b = epos_slot(1);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_POSITION_MARKER_PARAMETER] as fn(Int, Int32, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, a.as_mut_ptr(), b.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposPairOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    a: epos_rd_u8(&a, 0);
    b: epos_rd_u8(&b, 0);
  };
}

/// `VCS_ActivatePositionMarker` (digital input).  O(1).
pub fn epos_activate_position_marker(lib: &EposLibrary, key_handle: Int, node_id: Int, digital_input_number: Int, polarity: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_ACTIVATE_POSITION_MARKER] as fn(Int, Int32, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, digital_input_number as Int32, polarity as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_DeactivatePositionMarker`.  O(1).
pub fn epos_deactivate_position_marker(lib: &EposLibrary, key_handle: Int, node_id: Int, digital_input_number: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_DEACTIVATE_POSITION_MARKER] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, digital_input_number as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_ReadPositionMarkerCounter` (captured count).  O(1).
pub fn epos_read_position_marker_counter(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var v = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_READ_POSITION_MARKER_COUNTER] as fn(Int, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_u16(&v, 0) };
}

/// `VCS_ReadPositionMarkerCapturedPosition` [position units].  O(1).
pub fn epos_read_position_marker_captured_position(lib: &EposLibrary, key_handle: Int, node_id: Int, counter_index: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
  requires: counter_index >= 0
{
  var v = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_READ_POSITION_MARKER_CAPTURED_POSITION] as fn(Int, Int32, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, counter_index as Int32, v.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); value: epos_rd_i32(&v, 0) };
}

/// `VCS_ResetPositionMarkerCounter`.  O(1).
pub fn epos_reset_position_marker_counter(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_RESET_POSITION_MARKER_COUNTER] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

// =========================================================================
// CAN layer
// =========================================================================

/// `VCS_SendCANFrame` (payload read from the owned `data` slot, `Length =
/// data.len()`).  O(data).
pub fn epos_send_can_frame(lib: &EposLibrary, key_handle: Int, cob_id: Int, data: &Vec[UInt8]) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: data.len() > 0
  requires: data.len() <= 8
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SEND_CANFRAME] as fn(Int, Int32, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, cob_id as Int32, data.len() as Int32, data.as_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_ReadCANFrame` (blocking up to `timeout` [ms]; payload copied out of
/// an owned `length`-byte slot).  O(length).
pub fn epos_read_can_frame(lib: &EposLibrary, key_handle: Int, cob_id: Int, length: Int, timeout: Int) -> EposCanDataOut
  requires: lib.h != 0
  requires: key_handle != 0
  requires: length > 0
  requires: length <= 8
  requires: timeout >= 0
{
  var slot = epos_slot(length);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_READ_CANFRAME] as fn(Int, Int32, Int32, *UInt8, Int32, *UInt8) -> Int32;
    rc = f(key_handle, cob_id as Int32, length as Int32, slot.as_mut_ptr(), timeout as Int32, err.as_mut_ptr()) as Int;
  }
  var ncopy: Int = length;
  if !(rc == EPOS_RC_OK) { ncopy = 0; }
  return EposCanDataOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    data: epos_slot_copy(&slot, ncopy);
  };
}

/// `VCS_RequestCANFrame` (payload copied out of an owned `length`-byte
/// slot).  O(length).
pub fn epos_request_can_frame(lib: &EposLibrary, key_handle: Int, cob_id: Int, length: Int) -> EposCanDataOut
  requires: lib.h != 0
  requires: key_handle != 0
  requires: length > 0
  requires: length <= 8
{
  var slot = epos_slot(length);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_REQUEST_CANFRAME] as fn(Int, Int32, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, cob_id as Int32, length as Int32, slot.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  var ncopy: Int = length;
  if !(rc == EPOS_RC_OK) { ncopy = 0; }
  return EposCanDataOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    data: epos_slot_copy(&slot, ncopy);
  };
}

/// `VCS_SendNMTService` (node + `NCS_*` command specifier).  O(1).
pub fn epos_send_nmt_service(lib: &EposLibrary, key_handle: Int, node_id: Int, command_specifier: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SEND_NMT_SERVICE] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, command_specifier as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}
