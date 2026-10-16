// XIOM -- xiom.epos.system: communication / device-handle / selection wrappers
// for the EPOS Command Library.  Copyright (c) 2026 Eleftherios Notas and The
// XIOM Authors. MIT OR Apache-2.0.
//
// The initialisation cluster of the public header oracle: communication,
// gateway, sub-device, info and the advanced name/port selection helpers --
// plus the two declared Linux-layer helpers (CreateCommunication /
// DeleteCommunication) which return the typed EPOS_NOT_AVAILABLE sentinel on
// Windows artifacts instead of calling through a null entry (never a silent
// failure; SPEC.md sec. 3).
//
// All calls are fn-pointer casts over the entry table resolved by the root
// loader; slot discipline per the root module notes (B-17/B-24/B-25).

module xiom.epos.system

use xiom.epos;

/// `VCS_GetDriverInfo` outcome (two `char*` out-params).
pub type EposInfoOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  library_name: Str;
  library_version: Str;
}

// =========================================================================
// Communication / device handles
// =========================================================================

/// `VCS_OpenDevice`: open a device (EPOS2/EPOS4, protocol stack, interface,
/// port) and return the key handle.  `rc` is synthesized (the C function
/// returns the handle, not an int): 1 when a non-NULL handle was returned.
/// O(1).
pub fn epos_open_device(lib: &EposLibrary, device_name: Str, protocol_stack_name: Str, interface_name: Str, port_name: Str) -> EposHandleOut
  requires: lib.h != 0
  requires: device_name.len() > 0
  requires: protocol_stack_name.len() > 0
  requires: interface_name.len() > 0
  requires: port_name.len() > 0
{
  var err = epos_slot(4);
  var handle: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_OPEN_DEVICE] as fn(*UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> *UInt8;
    let hp = f(device_name.c_str(), protocol_stack_name.c_str(), interface_name.c_str(), port_name.c_str(), err.as_mut_ptr());
    handle = hp as Int;
  }
  let okh: Bool = handle != 0;
  return EposHandleOut{
    ok: okh;
    rc: if okh { 1 } else { 0 };
    error_code: epos_rd_u32(&err, 0);
    handle: handle;
  };
}

/// `VCS_SetProtocolStackSettings`: baudrate + timeout for the open device.
/// O(1).
pub fn epos_set_protocol_stack_settings(lib: &EposLibrary, key_handle: Int, baudrate: Int, timeout: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: baudrate >= 0
  requires: timeout >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_PROTOCOL_STACK_SETTINGS] as fn(Int, Int32, Int32, *UInt8) -> Int32;
    rc = f(key_handle, baudrate as Int32, timeout as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetProtocolStackSettings`: reads back baudrate (a) and timeout (b).
/// O(1).
pub fn epos_get_protocol_stack_settings(lib: &EposLibrary, key_handle: Int) -> EposPairOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var baud = epos_slot(4);
  var tmo = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_PROTOCOL_STACK_SETTINGS] as fn(Int, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, baud.as_mut_ptr(), tmo.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposPairOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    a: epos_rd_u32(&baud, 0);
    b: epos_rd_u32(&tmo, 0);
  };
}

/// `VCS_CloseDevice`.  O(1).
pub fn epos_close_device(lib: &EposLibrary, key_handle: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_CLOSE_DEVICE] as fn(Int, *UInt8) -> Int32;
    rc = f(key_handle, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_CloseAllDevices`.  O(1).
pub fn epos_close_all_devices(lib: &EposLibrary) -> EposRc
  requires: lib.h != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_CLOSE_ALL_DEVICES] as fn(*UInt8) -> Int32;
    rc = f(err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_SetGatewaySettings`: baudrate of a gateway device.  O(1).
pub fn epos_set_gateway_settings(lib: &EposLibrary, key_handle: Int, baudrate: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
  requires: baudrate >= 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_SET_GATEWAY_SETTINGS] as fn(Int, Int32, *UInt8) -> Int32;
    rc = f(key_handle, baudrate as Int32, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetGatewaySettings`: reads back the gateway baudrate.  O(1).
pub fn epos_get_gateway_settings(lib: &EposLibrary, key_handle: Int) -> EposValueOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var baud = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_GATEWAY_SETTINGS] as fn(Int, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, baud.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposValueOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    value: epos_rd_u32(&baud, 0);
  };
}

/// `VCS_OpenSubDevice`: open a sub-device on a gateway handle.  `rc` is
/// synthesized from the non-NULL handle (C returns `void*`).  O(1).
pub fn epos_open_sub_device(lib: &EposLibrary, device_handle: Int, device_name: Str, protocol_stack_name: Str) -> EposHandleOut
  requires: lib.h != 0
  requires: device_handle != 0
  requires: device_name.len() > 0
  requires: protocol_stack_name.len() > 0
{
  var err = epos_slot(4);
  var handle: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_OPEN_SUB_DEVICE] as fn(Int, *UInt8, *UInt8, *UInt8) -> *UInt8;
    let hp = f(device_handle, device_name.c_str(), protocol_stack_name.c_str(), err.as_mut_ptr());
    handle = hp as Int;
  }
  let okh: Bool = handle != 0;
  return EposHandleOut{
    ok: okh;
    rc: if okh { 1 } else { 0 };
    error_code: epos_rd_u32(&err, 0);
    handle: handle;
  };
}

/// `VCS_CloseSubDevice`.  O(1).
pub fn epos_close_sub_device(lib: &EposLibrary, key_handle: Int) -> EposRc
  requires: lib.h != 0
  requires: key_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_CLOSE_SUB_DEVICE] as fn(Int, *UInt8) -> Int32;
    rc = f(key_handle, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_CloseAllSubDevices`.  O(1).
pub fn epos_close_all_sub_devices(lib: &EposLibrary, device_handle: Int) -> EposRc
  requires: lib.h != 0
  requires: device_handle != 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_CLOSE_ALL_SUB_DEVICES] as fn(Int, *UInt8) -> Int32;
    rc = f(device_handle, err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

// =========================================================================
// Info
// =========================================================================

/// `VCS_GetDriverInfo`: the loaded library's own name and version (no
/// hardware needed).  O(1).
pub fn epos_get_driver_info(lib: &EposLibrary) -> EposInfoOut
  requires: lib.h != 0
{
  var name = epos_slot(EPOS_STR_MAX);
  var version = epos_slot(EPOS_STR_MAX);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_DRIVER_INFO] as fn(*UInt8, Int32, *UInt8, Int32, *UInt8) -> Int32;
    rc = f(name.as_mut_ptr(), EPOS_STR_MAX as Int32, version.as_mut_ptr(), EPOS_STR_MAX as Int32, err.as_mut_ptr()) as Int;
  }
  return EposInfoOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    library_name: epos_str_from_slot(&name);
    library_version: epos_str_from_slot(&version);
  };
}

/// `VCS_GetVersion`: hardware/software/application version words of a node.
/// O(1).
pub fn epos_get_version(lib: &EposLibrary, key_handle: Int, node_id: Int) -> EposVersionOut
  requires: lib.h != 0
  requires: key_handle != 0
  requires: node_id >= 0
{
  var hw = epos_slot(2);
  var sw = epos_slot(2);
  var app_num = epos_slot(2);
  var app_ver = epos_slot(2);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_VERSION] as fn(Int, Int32, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(key_handle, node_id as Int32, hw.as_mut_ptr(), sw.as_mut_ptr(), app_num.as_mut_ptr(), app_ver.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposVersionOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    hardware_version: epos_rd_u16(&hw, 0);
    software_version: epos_rd_u16(&sw, 0);
    application_number: epos_rd_u16(&app_num, 0);
    application_version: epos_rd_u16(&app_ver, 0);
  };
}

/// `VCS_GetErrorInfo`: human-readable text for a library error code.  The
/// library fills the buffer even when `rc` is 0 (observed on the 6.6 sample:
/// rc=0 + "Unknown Error" for an undefined code); `ok` therefore reflects a
/// non-empty message, and the full `rc`/`error_code` stay visible.  O(1).
pub fn epos_get_error_info(lib: &EposLibrary, error_code_value: Int) -> EposStrOut
  requires: lib.h != 0
  requires: error_code_value >= 0
{
  var buf = epos_slot(EPOS_STR_MAX);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_ERROR_INFO] as fn(Int32, *UInt8, Int32) -> Int32;
    rc = f(error_code_value as Int32, buf.as_mut_ptr(), EPOS_STR_MAX as Int32) as Int;
  }
  let text = epos_str_from_slot(&buf);
  return EposStrOut{ ok: text.len() > 0; rc: rc; error_code: 0; text: text };
}

// =========================================================================
// Advanced selection helpers (name/port/baudrate enumeration)
// =========================================================================

/// `VCS_GetDeviceNameSelection`: step through available device names
/// (e.g. "EPOS4"); loop with `end_of_selection` as the next start.  O(1).
pub fn epos_get_device_name_selection(lib: &EposLibrary, start_of_selection: Int) -> EposSelectionOut
  requires: lib.h != 0
{
  var buf = epos_slot(EPOS_STR_MAX);
  var end = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_DEVICE_NAME_SELECTION] as fn(Int32, *UInt8, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(start_of_selection as Int32, buf.as_mut_ptr(), EPOS_STR_MAX as Int32, end.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposSelectionOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    text: epos_str_from_slot(&buf);
    end_of_selection: epos_rd_i32(&end, 0);
  };
}

/// `VCS_GetProtocolStackNameSelection`: step through protocol-stack names
/// for a device name.  O(1).
pub fn epos_get_protocol_stack_name_selection(lib: &EposLibrary, device_name: Str, start_of_selection: Int) -> EposSelectionOut
  requires: lib.h != 0
  requires: device_name.len() > 0
{
  var buf = epos_slot(EPOS_STR_MAX);
  var end = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_PROTOCOL_STACK_NAME_SELECTION] as fn(*UInt8, Int32, *UInt8, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(device_name.c_str(), start_of_selection as Int32, buf.as_mut_ptr(), EPOS_STR_MAX as Int32, end.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposSelectionOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    text: epos_str_from_slot(&buf);
    end_of_selection: epos_rd_i32(&end, 0);
  };
}

/// `VCS_GetInterfaceNameSelection`: step through interface names for a
/// device/protocol stack (e.g. "USB").  O(1).
pub fn epos_get_interface_name_selection(lib: &EposLibrary, device_name: Str, protocol_stack_name: Str, start_of_selection: Int) -> EposSelectionOut
  requires: lib.h != 0
  requires: device_name.len() > 0
  requires: protocol_stack_name.len() > 0
{
  var buf = epos_slot(EPOS_STR_MAX);
  var end = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_INTERFACE_NAME_SELECTION] as fn(*UInt8, *UInt8, Int32, *UInt8, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(device_name.c_str(), protocol_stack_name.c_str(), start_of_selection as Int32, buf.as_mut_ptr(), EPOS_STR_MAX as Int32, end.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposSelectionOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    text: epos_str_from_slot(&buf);
    end_of_selection: epos_rd_i32(&end, 0);
  };
}

/// `VCS_GetPortNameSelection`: step through port names for a
/// device/protocol/interface (e.g. "USB0").  O(1).
pub fn epos_get_port_name_selection(lib: &EposLibrary, device_name: Str, protocol_stack_name: Str, interface_name: Str, start_of_selection: Int) -> EposSelectionOut
  requires: lib.h != 0
  requires: device_name.len() > 0
  requires: protocol_stack_name.len() > 0
  requires: interface_name.len() > 0
{
  var buf = epos_slot(EPOS_STR_MAX);
  var end = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_PORT_NAME_SELECTION] as fn(*UInt8, *UInt8, *UInt8, Int32, *UInt8, Int32, *UInt8, *UInt8) -> Int32;
    rc = f(device_name.c_str(), protocol_stack_name.c_str(), interface_name.c_str(), start_of_selection as Int32, buf.as_mut_ptr(), EPOS_STR_MAX as Int32, end.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposSelectionOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    text: epos_str_from_slot(&buf);
    end_of_selection: epos_rd_i32(&end, 0);
  };
}

/// `VCS_ResetPortNameSelection`: restart a port-name enumeration.  O(1).
pub fn epos_reset_port_name_selection(lib: &EposLibrary, device_name: Str, protocol_stack_name: Str, interface_name: Str) -> EposRc
  requires: lib.h != 0
  requires: device_name.len() > 0
  requires: protocol_stack_name.len() > 0
  requires: interface_name.len() > 0
{
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_RESET_PORT_NAME_SELECTION] as fn(*UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(device_name.c_str(), protocol_stack_name.c_str(), interface_name.c_str(), err.as_mut_ptr()) as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0) };
}

/// `VCS_GetBaudrateSelection`: step through baudrates for a port.  O(1).
pub fn epos_get_baudrate_selection(lib: &EposLibrary, device_name: Str, protocol_stack_name: Str, interface_name: Str, port_name: Str, start_of_selection: Int) -> EposBaudrateOut
  requires: lib.h != 0
  requires: device_name.len() > 0
  requires: protocol_stack_name.len() > 0
  requires: interface_name.len() > 0
  requires: port_name.len() > 0
{
  var baud = epos_slot(4);
  var end = epos_slot(4);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_BAUDRATE_SELECTION] as fn(*UInt8, *UInt8, *UInt8, *UInt8, Int32, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(device_name.c_str(), protocol_stack_name.c_str(), interface_name.c_str(), port_name.c_str(), start_of_selection as Int32, baud.as_mut_ptr(), end.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposBaudrateOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    baudrate: epos_rd_u32(&baud, 0);
    end_of_selection: epos_rd_i32(&end, 0);
  };
}

/// `VCS_GetKeyHandle`: resolve the key handle for an already-open device
/// signature (`void**` out-param read as a 64-bit value).  O(1).
pub fn epos_get_key_handle(lib: &EposLibrary, device_name: Str, protocol_stack_name: Str, interface_name: Str, port_name: Str) -> EposHandleOut
  requires: lib.h != 0
  requires: device_name.len() > 0
  requires: protocol_stack_name.len() > 0
  requires: interface_name.len() > 0
  requires: port_name.len() > 0
{
  var slot = epos_slot(8);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_KEY_HANDLE] as fn(*UInt8, *UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int32;
    rc = f(device_name.c_str(), protocol_stack_name.c_str(), interface_name.c_str(), port_name.c_str(), slot.as_mut_ptr(), err.as_mut_ptr()) as Int;
  }
  return EposHandleOut{
    ok: rc == EPOS_RC_OK;
    rc: rc;
    error_code: epos_rd_u32(&err, 0);
    handle: epos_rd_u64(&slot, 0);
  };
}

/// `VCS_GetDeviceName` of an open handle.  O(1).
pub fn epos_get_device_name(lib: &EposLibrary, key_handle: Int) -> EposStrOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var buf = epos_slot(EPOS_STR_MAX);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_DEVICE_NAME] as fn(Int, *UInt8, Int32, *UInt8) -> Int32;
    rc = f(key_handle, buf.as_mut_ptr(), EPOS_STR_MAX as Int32, err.as_mut_ptr()) as Int;
  }
  return EposStrOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); text: epos_str_from_slot(&buf) };
}

/// `VCS_GetProtocolStackName` of an open handle.  O(1).
pub fn epos_get_protocol_stack_name(lib: &EposLibrary, key_handle: Int) -> EposStrOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var buf = epos_slot(EPOS_STR_MAX);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_PROTOCOL_STACK_NAME] as fn(Int, *UInt8, Int32, *UInt8) -> Int32;
    rc = f(key_handle, buf.as_mut_ptr(), EPOS_STR_MAX as Int32, err.as_mut_ptr()) as Int;
  }
  return EposStrOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); text: epos_str_from_slot(&buf) };
}

/// `VCS_GetInterfaceName` of an open handle.  O(1).
pub fn epos_get_interface_name(lib: &EposLibrary, key_handle: Int) -> EposStrOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var buf = epos_slot(EPOS_STR_MAX);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_INTERFACE_NAME] as fn(Int, *UInt8, Int32, *UInt8) -> Int32;
    rc = f(key_handle, buf.as_mut_ptr(), EPOS_STR_MAX as Int32, err.as_mut_ptr()) as Int;
  }
  return EposStrOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); text: epos_str_from_slot(&buf) };
}

/// `VCS_GetPortName` of an open handle.  O(1).
pub fn epos_get_port_name(lib: &EposLibrary, key_handle: Int) -> EposStrOut
  requires: lib.h != 0
  requires: key_handle != 0
{
  var buf = epos_slot(EPOS_STR_MAX);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_PORT_NAME] as fn(Int, *UInt8, Int32, *UInt8) -> Int32;
    rc = f(key_handle, buf.as_mut_ptr(), EPOS_STR_MAX as Int32, err.as_mut_ptr()) as Int;
  }
  return EposStrOut{ ok: rc == EPOS_RC_OK; rc: rc; error_code: epos_rd_u32(&err, 0); text: epos_str_from_slot(&buf) };
}

// =========================================================================
// Linux-layer helpers (declared in the header; absent from Windows
// artifacts -> typed EPOS_NOT_AVAILABLE, never a null call-through)
// =========================================================================

/// `CreateCommunication` (declared Linux-layer helper; not exported by the
/// Windows DLL -- returns the typed sentinel there).  O(1).
pub fn epos_create_communication(lib: &EposLibrary) -> EposRc
  requires: lib.h != 0
{
  if !lib.has_helpers {
    return EposRc{ ok: false; rc: 0; error_code: EPOS_NOT_AVAILABLE };
  }
  var rc: Int = 0;
  unsafe {
    let f = lib.h_create_comm as fn() -> Int32;
    rc = f() as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: 0 };
}

/// `DeleteCommunication` (declared Linux-layer helper; not exported by the
/// Windows DLL -- returns the typed sentinel there).  O(1).
pub fn epos_delete_communication(lib: &EposLibrary) -> EposRc
  requires: lib.h != 0
{
  if !lib.has_helpers {
    return EposRc{ ok: false; rc: 0; error_code: EPOS_NOT_AVAILABLE };
  }
  var rc: Int = 0;
  unsafe {
    let f = lib.h_delete_comm as fn() -> Int32;
    rc = f() as Int;
  }
  return EposRc{ ok: rc == EPOS_RC_OK; rc: rc; error_code: 0 };
}
