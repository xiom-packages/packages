// XIOM -- xiom.epos: maxon EPOS (EPOS/EPOS2/EPOS4 positioning controllers)
// bindings via dynamic loader -- the EPOS Command Library.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DECISION (BINDINGS lane, closed-SDK doctrine, 2026-10-16): **system-library
// SKIP path only** -- the maxon EPOS Command Library is a closed SDK: no
// source, no redistributable headers, no licensed redistribution of
// `EposCmd.dll` / `EposCmd64.dll` / `libEposCmd.so` (see PROVENANCE.md).  The
// loader resolves the Windows sonames `EposCmd64.dll` then `EposCmd.dll`
// (and the Linux shared object `libEposCmd.so` as the declared third
// candidate) from the OS search path at run time; the suite reports SKIP
// when none is present, so CI without the SDK stays green.  NOTHING from the
// SDK is vendored or linked at build time.
//
// Declaration oracle (PUBLIC): the maxon `Definitions.h` header (Linux shared
// library declaration header, dated 11.2018) as redistributed by the public
// reference clone `iwata-lab/maxon_epos_ros` (MIT repo; pin in PROVENANCE.md)
// + the public "EPOS Command Library" documentation.  Measured declared
// cluster: **177 VCS_* entry points** (names are identical on the Windows
// artifacts -- public ctypes examples + a measured export sweep of a public
// `EposCmd64.dll` sample: 177/177 resolved) + 2 Linux-layer helpers
// (`CreateCommunication`/`DeleteCommunication`, declared in the header,
// absent from the Windows DLL -- explicit SPEC delta).  All 177 are resolved
// and ABI-checked at load; the 2 helpers are opportunistic.
//
// All XIOM `unsafe`/`extern` live in this single module tree (G5); every call
// is an fn-pointer cast over `xiom.ffi.dl`.
//
// Classification:
//   EPOS_LOAD_ABSENT -> no candidate soname resolved           -> SKIP
//   EPOS_LOAD_ABI    -> library loaded, entries missing        -> FAIL
//
// FFI discipline (v0.64.4 findings B-10/B-12/B-17/B-20/B-21/B-23/B-24/B-25/
// B-26):
//   * the library handle and every C `void*` KeyHandle cross as `Int`
//     end-to-end (B-25: never `Int as *UInt8`; pointer -> Int is fine);
//   * out-params use one XIOM-owned byte slot each, read byte-indexed
//     (B-17/B-24); slots are push-loop built, never `Vec.with_len`;
//   * no foreign-pointer reads and no pointer arithmetic (B-20/B-17);
//   * integer args cross as `Int32` casts at the fn-pointer boundary
//     (win-x64 register convention; the callee reads the low 8/16/32 bits),
//     the 64-bit handle/pointer and `unsigned long long` args as `Int`,
//     `float` args as `Float32`;
//   * the void* returns cross as `*UInt8` and are converted `as Int`
//     (pointer -> Int only; B-25);
//   * callbacks: none in the declared surface -- nothing to route;
//   * flat outcome structs everywhere (B-26: no `Result[Option[T]]`);
//   * Str equality only via `string.str_compare`; no fp returns (B-12).
//
// ABI note (SPEC delta): the public header oracle is the **LP64** Linux
// declaration (C `long` = 64-bit); the measured **win-x64** artifact family is
// LLP64 (C `long` = 32-bit).  This package binds the win-x64 ABI (`long`
// fields cross as Int32); the Linux `libEposCmd.so` binding is declared but
// not exercised on this lane.  `CreateCommunication`/`DeleteCommunication`
// are Linux-layer helpers (absent on Windows).
//
// Coverage (0.1.0): 177/177 declared VCS_* entries + 2/2 declared Linux
// helpers (typed NOT_AVAILABLE on Windows artifacts).  See SPEC.md.

module xiom.epos

use xiom.ffi.dl;
use xiom.convert;

// =========================================================================
// Sonames, classification, coverage counts
// =========================================================================

/// 64-bit Windows runtime of the EPOS Command Library.
pub const EPOS_SONAME_WIN64: Str = "EposCmd64.dll";

/// 32-bit Windows runtime (declared candidate; 32-bit targets out of scope).
pub const EPOS_SONAME_WIN32: Str = "EposCmd.dll";

/// Linux shared-object runtime (declared candidate; LP64 ABI note above).
pub const EPOS_SONAME_LINUX: Str = "libEposCmd.so";

/// Function success return code (maxon int convention: 1 = ok, 0 = failed).
pub const EPOS_RC_OK: Int = 1;

/// Package-level sentinel: the entry exists in the library but the requested
/// feature is not carried by the loaded artifact (e.g. Linux-layer helpers on
/// a Windows DLL).  NOT a maxon error code -- it is never returned by the
/// library itself.
pub const EPOS_NOT_AVAILABLE: Int = -1;

/// No candidate library resolved -> the caller reports SKIP.
pub const EPOS_LOAD_ABSENT: Int = 0;

/// A library loaded but declared entry points are missing -> FAIL
/// (a real install/SDK mismatch).
pub const EPOS_LOAD_ABI: Int = 1;

/// Measured declared cluster: VCS_* entries in the public header oracle and
/// on the measured Windows artifact (177/177 resolved).
pub const EPOS_VCS_COUNT: Int = 177;

/// Declared Linux-layer helpers (CreateCommunication/DeleteCommunication).
pub const EPOS_HELPER_COUNT: Int = 2;

/// Declared total (177 VCS_* + 2 helpers) of the public header oracle.
pub const EPOS_DECLARED_COUNT: Int = 179;

/// Default receiving buffer size for `char*` out-params.
pub const EPOS_STR_MAX: Int = 256;

// =========================================================================
// Type constants (public header oracle; values verbatim)
// =========================================================================

// Dialog mode (CreateCommunication-era Linux layer)
pub const DM_PROGRESS_DLG: Int = 0;
pub const DM_PROGRESS_AND_CONFIRM_DLG: Int = 1;
pub const DM_CONFIRM_DLG: Int = 2;
pub const DM_NO_DLG: Int = 3;

// Motor type
pub const MT_DC_MOTOR: Int = 1;
pub const MT_EC_SINUS_COMMUTATED_MOTOR: Int = 10;
pub const MT_EC_BLOCK_COMMUTATED_MOTOR: Int = 11;

// Sensor type
pub const ST_UNKNOWN: Int = 0;
pub const ST_INC_ENCODER_3CHANNEL: Int = 1;
pub const ST_INC_ENCODER_2CHANNEL: Int = 2;
pub const ST_HALL_SENSORS: Int = 3;
pub const ST_SSI_ABS_ENCODER_BINARY: Int = 4;
pub const ST_SSI_ABS_ENCODER_GREY: Int = 5;
pub const ST_INC_ENCODER2_3CHANNEL: Int = 6;
pub const ST_INC_ENCODER2_2CHANNEL: Int = 7;
pub const ST_ANALOG_INC_ENCODER_3CHANNEL: Int = 8;
pub const ST_ANALOG_INC_ENCODER_2CHANNEL: Int = 9;

// Digital input configuration
pub const DIC_NEGATIVE_LIMIT_SWITCH: Int = 0;
pub const DIC_POSITIVE_LIMIT_SWITCH: Int = 1;
pub const DIC_HOME_SWITCH: Int = 2;
pub const DIC_POSITION_MARKER: Int = 3;
pub const DIC_DRIVE_ENABLE: Int = 4;
pub const DIC_QUICK_STOP: Int = 5;
pub const DIC_GENERAL_PURPOSE_J: Int = 6;
pub const DIC_GENERAL_PURPOSE_I: Int = 7;
pub const DIC_GENERAL_PURPOSE_H: Int = 8;
pub const DIC_GENERAL_PURPOSE_G: Int = 9;
pub const DIC_GENERAL_PURPOSE_F: Int = 10;
pub const DIC_GENERAL_PURPOSE_E: Int = 11;
pub const DIC_GENERAL_PURPOSE_D: Int = 12;
pub const DIC_GENERAL_PURPOSE_C: Int = 13;
pub const DIC_GENERAL_PURPOSE_B: Int = 14;
pub const DIC_GENERAL_PURPOSE_A: Int = 15;

// Digital output configuration
pub const DOC_READY_FAULT: Int = 0;
pub const DOC_POSITION_COMPARE: Int = 1;
pub const DOC_GENERAL_PURPOSE_H: Int = 8;
pub const DOC_GENERAL_PURPOSE_G: Int = 9;
pub const DOC_GENERAL_PURPOSE_F: Int = 10;
pub const DOC_GENERAL_PURPOSE_E: Int = 11;
pub const DOC_GENERAL_PURPOSE_D: Int = 12;
pub const DOC_GENERAL_PURPOSE_C: Int = 13;
pub const DOC_GENERAL_PURPOSE_B: Int = 14;
pub const DOC_GENERAL_PURPOSE_A: Int = 15;

// Analog input configuration
pub const AIC_ANALOG_CURRENT_SETPOINT: Int = 0;
pub const AIC_ANALOG_VELOCITY_SETPOINT: Int = 1;
pub const AIC_ANALOG_POSITION_SETPOINT: Int = 2;
pub const AIC_GENERAL_PURPOSE_H: Int = 8;
pub const AIC_GENERAL_PURPOSE_G: Int = 9;
pub const AIC_GENERAL_PURPOSE_F: Int = 10;
pub const AIC_GENERAL_PURPOSE_E: Int = 11;
pub const AIC_GENERAL_PURPOSE_D: Int = 12;
pub const AIC_GENERAL_PURPOSE_C: Int = 13;
pub const AIC_GENERAL_PURPOSE_B: Int = 14;
pub const AIC_GENERAL_PURPOSE_A: Int = 15;

// Analog output configuration
pub const AOC_GENERAL_PURPOSE_A: Int = 0;
pub const AOC_GENERAL_PURPOSE_B: Int = 1;

// Velocity units
pub const VD_RPM: Int = 164;
pub const VN_STANDARD: Int = 0;
pub const VN_DECI: Int = -1;
pub const VN_CENTI: Int = -2;
pub const VN_MILLI: Int = -3;

// Operational mode (VCS_Set/GetOperationMode values)
pub const OMD_PROFILE_POSITION_MODE: Int = 1;
pub const OMD_PROFILE_VELOCITY_MODE: Int = 3;
pub const OMD_HOMING_MODE: Int = 6;
pub const OMD_INTERPOLATED_POSITION_MODE: Int = 7;
pub const OMD_POSITION_MODE: Int = -1;
pub const OMD_VELOCITY_MODE: Int = -2;
pub const OMD_CURRENT_MODE: Int = -3;
pub const OMD_MASTER_ENCODER_MODE: Int = -5;
pub const OMD_STEP_DIRECTION_MODE: Int = -6;

// State machine states (VCS_Set/GetState values)
pub const ST_DISABLED: Int = 0;
pub const ST_ENABLED: Int = 1;
pub const ST_QUICKSTOP: Int = 2;
pub const ST_FAULT: Int = 3;

// Homing method (VCS_FindHome values)
pub const HM_ACTUAL_POSITION: Int = 35;
pub const HM_NEGATIVE_LIMIT_SWITCH: Int = 17;
pub const HM_NEGATIVE_LIMIT_SWITCH_AND_INDEX: Int = 1;
pub const HM_POSITIVE_LIMIT_SWITCH: Int = 18;
pub const HM_POSITIVE_LIMIT_SWITCH_AND_INDEX: Int = 2;
pub const HM_HOME_SWITCH_POSITIVE_SPEED: Int = 23;
pub const HM_HOME_SWITCH_POSITIVE_SPEED_AND_INDEX: Int = 7;
pub const HM_HOME_SWITCH_NEGATIVE_SPEED: Int = 27;
pub const HM_HOME_SWITCH_NEGATIVE_SPEED_AND_INDEX: Int = 11;
pub const HM_CURRENT_THRESHOLD_POSITIVE_SPEED: Int = -3;
pub const HM_CURRENT_THRESHOLD_POSITIVE_SPEED_AND_INDEX: Int = -1;
pub const HM_CURRENT_THRESHOLD_NEGATIVE_SPEED: Int = -4;
pub const HM_CURRENT_THRESHOLD_NEGATIVE_SPEED_AND_INDEX: Int = -2;
pub const HM_INDEX_POSITIVE_SPEED: Int = 34;
pub const HM_INDEX_NEGATIVE_SPEED: Int = 33;

// Position marker: edge type / mode
pub const PET_BOTH_EDGES: Int = 0;
pub const PET_RISING_EDGE: Int = 1;
pub const PET_FALLING_EDGE: Int = 2;
pub const PM_CONTINUOUS: Int = 0;
pub const PM_SINGLE: Int = 1;
pub const PM_MULTIPLE: Int = 2;

// Position compare: operational/interval/direction modes
pub const PCO_SINGLE_POSITION_MODE: Int = 0;
pub const PCO_POSITION_SEQUENCE_MODE: Int = 1;
pub const PCI_NEGATIVE_DIR_TO_REFPOS: Int = 0;
pub const PCI_POSITIVE_DIR_TO_REFPOS: Int = 1;
pub const PCI_BOTH_DIR_TO_REFPOS: Int = 2;
pub const PCD_MOTOR_DIRECTION_NEGATIVE: Int = 0;
pub const PCD_MOTOR_DIRECTION_POSITIVE: Int = 1;
pub const PCD_MOTOR_DIRECTION_BOTH: Int = 2;

// Data recorder trigger bits
pub const DR_MOVEMENT_START_TRIGGER: Int = 1;
pub const DR_ERROR_TRIGGER: Int = 2;
pub const DR_DIGITAL_INPUT_TRIGGER: Int = 4;
pub const DR_MOVEMENT_END_TRIGGER: Int = 8;

// CAN NMT command specifiers
pub const NCS_START_REMOTE_NODE: Int = 1;
pub const NCS_STOP_REMOTE_NODE: Int = 2;
pub const NCS_ENTER_PRE_OPERATIONAL: Int = 128;
pub const NCS_RESET_NODE: Int = 129;
pub const NCS_RESET_COMMUNICATION: Int = 130;

// Controller selection (VCS_Set/GetControllerGain)
pub const EC_PI_CURRENT_CONTROLLER: Int = 1;
pub const EC_PI_VELOCITY_CONTROLLER: Int = 10;
pub const EC_PI_VELOCITY_CONTROLLER_WITH_OBSERVER: Int = 11;
pub const EC_PID_POSITION_CONTROLLER: Int = 20;
pub const EC_DUAL_LOOP_POSITION_CONTROLLER: Int = 21;

// Gain selection (per controller)
pub const EG_PICC_P_GAIN: Int = 1;
pub const EG_PICC_I_GAIN: Int = 2;
pub const EG_PIVC_P_GAIN: Int = 1;
pub const EG_PIVC_I_GAIN: Int = 2;
pub const EG_PIVC_FEED_FORWARD_VELOCITY_GAIN: Int = 10;
pub const EG_PIVC_FEED_FORWARD_ACCELERATION_GAIN: Int = 11;
pub const EG_PIVCWO_P_GAIN: Int = 1;
pub const EG_PIVCWO_I_GAIN: Int = 2;
pub const EG_PIVCWO_FEED_FORWARD_VELOCITY_GAIN: Int = 10;
pub const EG_PIVCWO_FEED_FORWARD_ACCELERATION_GAIN: Int = 11;
pub const EG_PIVCWO_OBSERVER_THETA_GAIN: Int = 20;
pub const EG_PIVCWO_OBSERVER_OMEGA_GAIN: Int = 21;
pub const EG_PIVCWO_OBSERVER_TAU_GAIN: Int = 22;
pub const EG_PIDPC_P_GAIN: Int = 1;
pub const EG_PIDPC_I_GAIN: Int = 2;
pub const EG_PIDPC_D_GAIN: Int = 3;
pub const EG_PIDPC_FEED_FORWARD_VELOCITY_GAIN: Int = 10;
pub const EG_PIDPC_FEED_FORWARD_ACCELERATION_GAIN: Int = 11;
pub const EG_DLPC_AUXILIARY_LOOP_P_GAIN: Int = 1;
pub const EG_DLPC_AUXILIARY_LOOP_I_GAIN: Int = 2;
pub const EG_DLPC_AUXILIARY_LOOP_FEED_FORWARD_VELOCITY_GAIN: Int = 10;
pub const EG_DLPC_AUXILIARY_LOOP_FEED_FORWARD_ACCELERATION_GAIN: Int = 11;
pub const EG_DLPC_AUXILIARY_LOOP_OBSERVER_THETA_GAIN: Int = 20;
pub const EG_DLPC_AUXILIARY_LOOP_OBSERVER_OMEGA_GAIN: Int = 21;
pub const EG_DLPC_AUXILIARY_LOOP_OBSERVER_TAU_GAIN: Int = 22;
pub const EG_DLPC_MAIN_LOOP_P_GAIN_LOW: Int = 101;
pub const EG_DLPC_MAIN_LOOP_P_GAIN_HIGH: Int = 102;
pub const EG_DLPC_MAIN_LOOP_GAIN_SCHEDULING_WEIGHT: Int = 110;
pub const EG_DLPC_MAIN_LOOP_FILTER_COEFFICIENT_A: Int = 120;
pub const EG_DLPC_MAIN_LOOP_FILTER_COEFFICIENT_B: Int = 121;
pub const EG_DLPC_MAIN_LOOP_FILTER_COEFFICIENT_C: Int = 122;
pub const EG_DLPC_MAIN_LOOP_FILTER_COEFFICIENT_D: Int = 123;
pub const EG_DLPC_MAIN_LOOP_FILTER_COEFFICIENT_E: Int = 124;

// =========================================================================
// Slot helpers (XIOM-owned Vec[UInt8] buffers; push-loop built -- never
// Vec.with_len, see the shaderc audit; byte-indexed reads per B-17/B-24)
// =========================================================================

/// Zeroed slot of `n` bytes.  O(n).
pub fn epos_slot(n: Int) -> Vec[UInt8]
  requires: n > 0
  requires: n <= 65536
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

/// Little-endian u16 store.  O(1).
pub fn epos_wr_u16(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 2
{
  buf[off + 0] = (v & 255) as UInt8;
  buf[off + 1] = ((v >> 8) & 255) as UInt8;
}

/// Little-endian u32 store (also used for the 32-bit `long` fields of the
/// win-x64 ABI).  O(1).
pub fn epos_wr_u32(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  buf[off + 0] = (v & 255) as UInt8;
  buf[off + 1] = ((v >> 8) & 255) as UInt8;
  buf[off + 2] = ((v >> 16) & 255) as UInt8;
  buf[off + 3] = ((v >> 24) & 255) as UInt8;
}

/// Little-endian u64 store (pointers/offsets; pointer -> Int is
/// value-preserving, B-25 only breaks Int -> pointer).  O(1).
pub fn epos_wr_u64(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  epos_wr_u32(buf, off, v & 4294967295);
  epos_wr_u32(buf, off + 4, (v >> 32) & 4294967295);
}

/// Byte read (unsigned char out-params).  O(1).
pub fn epos_rd_u8(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 1
{
  return buf[off] as Int;
}

/// Little-endian u16 read.  O(1).
pub fn epos_rd_u16(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 2
{
  return (buf[off + 0] as Int) | ((buf[off + 1] as Int) << 8);
}

/// Little-endian u32 read.  O(1).
pub fn epos_rd_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  return (buf[off + 0] as Int)
    | ((buf[off + 1] as Int) << 8)
    | ((buf[off + 2] as Int) << 16)
    | ((buf[off + 3] as Int) << 24);
}

/// Little-endian u64 read (pointers/offsets; unsigned long long values).
/// O(1).
pub fn epos_rd_u64(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 8
{
  let lo = epos_rd_u32(buf, off);
  let hi = epos_rd_u32(buf, off + 4);
  return lo | (hi << 32);
}

/// Signed 8-bit read (signed char / char out-params).  O(1).
pub fn epos_rd_i8(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 1
{
  let u = epos_rd_u8(buf, off);
  if u >= 128 { return u - 256; }
  return u;
}

/// Signed 16-bit read (short out-params).  O(1).
pub fn epos_rd_i16(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 2
{
  let u = epos_rd_u16(buf, off);
  if u >= 32768 { return u - 65536; }
  return u;
}

/// Signed 32-bit read (int / long out-params on win-x64).  O(1).
pub fn epos_rd_i32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: buf.len() >= off + 4
{
  let u = epos_rd_u32(buf, off);
  if u >= 2147483648 { return u - 4294967296; }
  return u;
}

/// C string read from the start of an owned slot (the library NUL-terminates
/// `char*` out-params; the slot is pre-zeroed, so an untouched tail reads as
/// empty).  O(len).
pub fn epos_str_from_slot(buf: &Vec[UInt8]) -> Str
  requires: buf.len() > 0
{
  return Str::from_c_str(buf.as_ptr());
}

/// Copy the first `n` bytes of a slot into a new owned Vec (payload bytes
/// read out of CAN/object slots; byte-indexed, no foreign reads).  O(n).
pub fn epos_slot_copy(buf: &Vec[UInt8], n: Int) -> Vec[UInt8]
  requires: n >= 0
  requires: buf.len() >= n
{
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    out.push(buf[i]);
    i = i + 1;
  }
  return out;
}

// =========================================================================
// Outcome types (flat; B-26) -- all carry the maxon return `rc` (1 = ok)
// and the library/device `error_code` (the trailing unsigned int*)
// =========================================================================

pub type EposLoadError = {
  kind: Int;
  message: Str;
}

pub type EposRc = {
  ok: Bool;
  rc: Int;
  error_code: Int;
}

/// One scalar out-param (u8/u16/i16/u32/i32/long/u64/pointer value).
pub type EposValueOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  value: Int;
}

pub type EposPairOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  a: Int;
  b: Int;
}

pub type EposTripleOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  a: Int;
  b: Int;
  c: Int;
}

pub type EposQuadOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  a: Int;
  b: Int;
  c: Int;
  d: Int;
}

pub type EposHandleOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  handle: Int;
}

pub type EposStrOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  text: Str;
}

pub type EposSelectionOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  text: Str;
  end_of_selection: Int;
}

pub type EposBaudrateOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  baudrate: Int;
  end_of_selection: Int;
}

pub type EposDriverInfo = {
  library_name: Str;
  library_version: Str;
}

pub type EposVersionOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  hardware_version: Int;
  software_version: Int;
  application_number: Int;
  application_version: Int;
}

pub type EposVelocityUnitsOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  velocity_dimension: Int;
  velocity_notation: Int;
}

pub type EposMotorParamsOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  nominal_current: Int;
  max_output_current: Int;
  thermal_time_constant: Int;
  nb_of_pole_pairs: Int;
}

pub type EposSsiParamsOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  data_rate: Int;
  nb_of_multi_turn_data_bits: Int;
  nb_of_single_turn_data_bits: Int;
  nb_of_special_data_bits: Int;
  inverted_polarity: Int;
  timeout: Int;
  powerup_time: Int;
}

pub type EposScalingOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  scaling_numerator: Int;
  scaling_denominator: Int;
  polarity: Int;
  max_velocity: Int;
  max_acceleration: Int;
}

pub type EposHomingParamsOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  homing_acceleration: Int;
  speed_switch: Int;
  speed_index: Int;
  home_offset: Int;
  current_threshold: Int;
  home_position: Int;
}

pub type EposIpmBufferOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  underflow_warning_limit: Int;
  overflow_warning_limit: Int;
  max_buffer_size: Int;
}

pub type EposIpmStatusOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  trajectory_running: Int;
  underflow_warning: Int;
  overflow_warning: Int;
  velocity_warning: Int;
  acceleration_warning: Int;
  underflow_error: Int;
  overflow_error: Int;
  velocity_error: Int;
  acceleration_error: Int;
}

pub type EposCanDataOut = {
  ok: Bool;
  rc: Int;
  error_code: Int;
  data: Vec[UInt8];
}

// =========================================================================
// Library handle and entry-point table
// =========================================================================

/// A loaded EPOS Command Library.  Owned by the caller; release with
/// `epos_close`.  `ptrs[i]` is the resolved address (Int, never 0 -- the
/// loader fails closed) of the entry whose index constant is `EPOS_FN_*`.
/// The two Linux-layer helpers are resolved opportunistically into the
/// `helpers` pair (0 when the loaded artifact does not carry them).
pub type EposLibrary = {
  h: Int;
  soname: Str;
  h_create_comm: Int;
  h_delete_comm: Int;
  has_helpers: Bool;
  ptrs: Vec[Int];
}

/// The declared VCS_* entry-point names in index order (alphabetical; the
/// order the EPOS_FN_* index constants are built on).  O(177).
pub fn epos_entry_names() -> Vec[Str]
  requires: true
{
  var v: Vec[Str] = Vec[Str].new();
  v.push("VCS_ActivateAnalogCurrentSetpoint");
  v.push("VCS_ActivateAnalogPositionSetpoint");
  v.push("VCS_ActivateAnalogVelocitySetpoint");
  v.push("VCS_ActivateCurrentMode");
  v.push("VCS_ActivateHomingMode");
  v.push("VCS_ActivateInterpolatedPositionMode");
  v.push("VCS_ActivateMasterEncoderMode");
  v.push("VCS_ActivatePositionCompare");
  v.push("VCS_ActivatePositionMarker");
  v.push("VCS_ActivatePositionMode");
  v.push("VCS_ActivateProfilePositionMode");
  v.push("VCS_ActivateProfileVelocityMode");
  v.push("VCS_ActivateStepDirectionMode");
  v.push("VCS_ActivateVelocityMode");
  v.push("VCS_AddPvtValueToIpmBuffer");
  v.push("VCS_AnalogInputConfiguration");
  v.push("VCS_AnalogOutputConfiguration");
  v.push("VCS_ClearFault");
  v.push("VCS_ClearIpmBuffer");
  v.push("VCS_CloseAllDevices");
  v.push("VCS_CloseAllSubDevices");
  v.push("VCS_CloseDevice");
  v.push("VCS_CloseSubDevice");
  v.push("VCS_DeactivateAnalogCurrentSetpoint");
  v.push("VCS_DeactivateAnalogPositionSetpoint");
  v.push("VCS_DeactivateAnalogVelocitySetpoint");
  v.push("VCS_DeactivatePositionCompare");
  v.push("VCS_DeactivatePositionMarker");
  v.push("VCS_DefinePosition");
  v.push("VCS_DigitalInputConfiguration");
  v.push("VCS_DigitalOutputConfiguration");
  v.push("VCS_DisableAnalogCurrentSetpoint");
  v.push("VCS_DisableAnalogPositionSetpoint");
  v.push("VCS_DisableAnalogVelocitySetpoint");
  v.push("VCS_DisablePositionCompare");
  v.push("VCS_DisablePositionWindow");
  v.push("VCS_DisableVelocityWindow");
  v.push("VCS_EnableAnalogCurrentSetpoint");
  v.push("VCS_EnableAnalogPositionSetpoint");
  v.push("VCS_EnableAnalogVelocitySetpoint");
  v.push("VCS_EnablePositionCompare");
  v.push("VCS_EnablePositionWindow");
  v.push("VCS_EnableVelocityWindow");
  v.push("VCS_FindHome");
  v.push("VCS_GetAllDigitalInputs");
  v.push("VCS_GetAllDigitalOutputs");
  v.push("VCS_GetAnalogInput");
  v.push("VCS_GetAnalogInputState");
  v.push("VCS_GetAnalogInputVoltage");
  v.push("VCS_GetBaudrateSelection");
  v.push("VCS_GetControllerGain");
  v.push("VCS_GetCurrentIs");
  v.push("VCS_GetCurrentIsAveraged");
  v.push("VCS_GetCurrentMust");
  v.push("VCS_GetCurrentRegulatorGain");
  v.push("VCS_GetDcMotorParameter");
  v.push("VCS_GetDeviceErrorCode");
  v.push("VCS_GetDeviceName");
  v.push("VCS_GetDeviceNameSelection");
  v.push("VCS_GetDisableState");
  v.push("VCS_GetDriverInfo");
  v.push("VCS_GetEcMotorParameter");
  v.push("VCS_GetEnableState");
  v.push("VCS_GetErrorInfo");
  v.push("VCS_GetFaultState");
  v.push("VCS_GetFreeIpmBufferSize");
  v.push("VCS_GetGatewaySettings");
  v.push("VCS_GetHallSensorParameter");
  v.push("VCS_GetHomingParameter");
  v.push("VCS_GetHomingState");
  v.push("VCS_GetIncEncoderParameter");
  v.push("VCS_GetInterfaceName");
  v.push("VCS_GetInterfaceNameSelection");
  v.push("VCS_GetIpmBufferParameter");
  v.push("VCS_GetIpmStatus");
  v.push("VCS_GetKeyHandle");
  v.push("VCS_GetMasterEncoderParameter");
  v.push("VCS_GetMaxAcceleration");
  v.push("VCS_GetMaxFollowingError");
  v.push("VCS_GetMaxProfileVelocity");
  v.push("VCS_GetMotorType");
  v.push("VCS_GetMovementState");
  v.push("VCS_GetNbOfDeviceError");
  v.push("VCS_GetObject");
  v.push("VCS_GetOperationMode");
  v.push("VCS_GetPortName");
  v.push("VCS_GetPortNameSelection");
  v.push("VCS_GetPositionCompareParameter");
  v.push("VCS_GetPositionIs");
  v.push("VCS_GetPositionMarkerParameter");
  v.push("VCS_GetPositionMust");
  v.push("VCS_GetPositionProfile");
  v.push("VCS_GetPositionRegulatorFeedForward");
  v.push("VCS_GetPositionRegulatorGain");
  v.push("VCS_GetProtocolStackName");
  v.push("VCS_GetProtocolStackNameSelection");
  v.push("VCS_GetProtocolStackSettings");
  v.push("VCS_GetQuickStopState");
  v.push("VCS_GetSensorType");
  v.push("VCS_GetSsiAbsEncoderParameter");
  v.push("VCS_GetSsiAbsEncoderParameterEx");
  v.push("VCS_GetState");
  v.push("VCS_GetStepDirectionParameter");
  v.push("VCS_GetTargetPosition");
  v.push("VCS_GetTargetVelocity");
  v.push("VCS_GetVelocityIs");
  v.push("VCS_GetVelocityIsAveraged");
  v.push("VCS_GetVelocityMust");
  v.push("VCS_GetVelocityProfile");
  v.push("VCS_GetVelocityRegulatorFeedForward");
  v.push("VCS_GetVelocityRegulatorGain");
  v.push("VCS_GetVelocityUnits");
  v.push("VCS_GetVersion");
  v.push("VCS_HaltPositionMovement");
  v.push("VCS_HaltVelocityMovement");
  v.push("VCS_MoveToPosition");
  v.push("VCS_MoveWithVelocity");
  v.push("VCS_OpenDevice");
  v.push("VCS_OpenSubDevice");
  v.push("VCS_ReadCANFrame");
  v.push("VCS_ReadPositionMarkerCapturedPosition");
  v.push("VCS_ReadPositionMarkerCounter");
  v.push("VCS_RequestCANFrame");
  v.push("VCS_ResetDevice");
  v.push("VCS_ResetPortNameSelection");
  v.push("VCS_ResetPositionMarkerCounter");
  v.push("VCS_Restore");
  v.push("VCS_SendCANFrame");
  v.push("VCS_SendNMTService");
  v.push("VCS_SetAllDigitalOutputs");
  v.push("VCS_SetAnalogOutput");
  v.push("VCS_SetAnalogOutputState");
  v.push("VCS_SetAnalogOutputVoltage");
  v.push("VCS_SetControllerGain");
  v.push("VCS_SetCurrentMust");
  v.push("VCS_SetCurrentRegulatorGain");
  v.push("VCS_SetDcMotorParameter");
  v.push("VCS_SetDisableState");
  v.push("VCS_SetEcMotorParameter");
  v.push("VCS_SetEnableState");
  v.push("VCS_SetGatewaySettings");
  v.push("VCS_SetHallSensorParameter");
  v.push("VCS_SetHomingParameter");
  v.push("VCS_SetIncEncoderParameter");
  v.push("VCS_SetIpmBufferParameter");
  v.push("VCS_SetMasterEncoderParameter");
  v.push("VCS_SetMaxAcceleration");
  v.push("VCS_SetMaxFollowingError");
  v.push("VCS_SetMaxProfileVelocity");
  v.push("VCS_SetMotorType");
  v.push("VCS_SetObject");
  v.push("VCS_SetOperationMode");
  v.push("VCS_SetPositionCompareParameter");
  v.push("VCS_SetPositionCompareReferencePosition");
  v.push("VCS_SetPositionMarkerParameter");
  v.push("VCS_SetPositionMust");
  v.push("VCS_SetPositionProfile");
  v.push("VCS_SetPositionRegulatorFeedForward");
  v.push("VCS_SetPositionRegulatorGain");
  v.push("VCS_SetProtocolStackSettings");
  v.push("VCS_SetQuickStopState");
  v.push("VCS_SetSensorType");
  v.push("VCS_SetSsiAbsEncoderParameter");
  v.push("VCS_SetSsiAbsEncoderParameterEx");
  v.push("VCS_SetState");
  v.push("VCS_SetStepDirectionParameter");
  v.push("VCS_SetVelocityMust");
  v.push("VCS_SetVelocityProfile");
  v.push("VCS_SetVelocityRegulatorFeedForward");
  v.push("VCS_SetVelocityRegulatorGain");
  v.push("VCS_SetVelocityUnits");
  v.push("VCS_StartIpmTrajectory");
  v.push("VCS_StopHoming");
  v.push("VCS_StopIpmTrajectory");
  v.push("VCS_Store");
  v.push("VCS_WaitForHomingAttained");
  v.push("VCS_WaitForTargetReached");
  return v;
}

/// The declared Linux-layer helper names (absent on Windows artifacts).
/// O(2).
pub fn epos_helper_names() -> Vec[Str]
  requires: true
{
  var v: Vec[Str] = Vec[Str].new();
  v.push("CreateCommunication");
  v.push("DeleteCommunication");
  return v;
}

// ---- Entry index constants (alphabetical; 0..176) ----

pub const EPOS_FN_VCS_ACTIVATE_ANALOG_CURRENT_SETPOINT: Int = 0;
pub const EPOS_FN_VCS_ACTIVATE_ANALOG_POSITION_SETPOINT: Int = 1;
pub const EPOS_FN_VCS_ACTIVATE_ANALOG_VELOCITY_SETPOINT: Int = 2;
pub const EPOS_FN_VCS_ACTIVATE_CURRENT_MODE: Int = 3;
pub const EPOS_FN_VCS_ACTIVATE_HOMING_MODE: Int = 4;
pub const EPOS_FN_VCS_ACTIVATE_INTERPOLATED_POSITION_MODE: Int = 5;
pub const EPOS_FN_VCS_ACTIVATE_MASTER_ENCODER_MODE: Int = 6;
pub const EPOS_FN_VCS_ACTIVATE_POSITION_COMPARE: Int = 7;
pub const EPOS_FN_VCS_ACTIVATE_POSITION_MARKER: Int = 8;
pub const EPOS_FN_VCS_ACTIVATE_POSITION_MODE: Int = 9;
pub const EPOS_FN_VCS_ACTIVATE_PROFILE_POSITION_MODE: Int = 10;
pub const EPOS_FN_VCS_ACTIVATE_PROFILE_VELOCITY_MODE: Int = 11;
pub const EPOS_FN_VCS_ACTIVATE_STEP_DIRECTION_MODE: Int = 12;
pub const EPOS_FN_VCS_ACTIVATE_VELOCITY_MODE: Int = 13;
pub const EPOS_FN_VCS_ADD_PVT_VALUE_TO_IPM_BUFFER: Int = 14;
pub const EPOS_FN_VCS_ANALOG_INPUT_CONFIGURATION: Int = 15;
pub const EPOS_FN_VCS_ANALOG_OUTPUT_CONFIGURATION: Int = 16;
pub const EPOS_FN_VCS_CLEAR_FAULT: Int = 17;
pub const EPOS_FN_VCS_CLEAR_IPM_BUFFER: Int = 18;
pub const EPOS_FN_VCS_CLOSE_ALL_DEVICES: Int = 19;
pub const EPOS_FN_VCS_CLOSE_ALL_SUB_DEVICES: Int = 20;
pub const EPOS_FN_VCS_CLOSE_DEVICE: Int = 21;
pub const EPOS_FN_VCS_CLOSE_SUB_DEVICE: Int = 22;
pub const EPOS_FN_VCS_DEACTIVATE_ANALOG_CURRENT_SETPOINT: Int = 23;
pub const EPOS_FN_VCS_DEACTIVATE_ANALOG_POSITION_SETPOINT: Int = 24;
pub const EPOS_FN_VCS_DEACTIVATE_ANALOG_VELOCITY_SETPOINT: Int = 25;
pub const EPOS_FN_VCS_DEACTIVATE_POSITION_COMPARE: Int = 26;
pub const EPOS_FN_VCS_DEACTIVATE_POSITION_MARKER: Int = 27;
pub const EPOS_FN_VCS_DEFINE_POSITION: Int = 28;
pub const EPOS_FN_VCS_DIGITAL_INPUT_CONFIGURATION: Int = 29;
pub const EPOS_FN_VCS_DIGITAL_OUTPUT_CONFIGURATION: Int = 30;
pub const EPOS_FN_VCS_DISABLE_ANALOG_CURRENT_SETPOINT: Int = 31;
pub const EPOS_FN_VCS_DISABLE_ANALOG_POSITION_SETPOINT: Int = 32;
pub const EPOS_FN_VCS_DISABLE_ANALOG_VELOCITY_SETPOINT: Int = 33;
pub const EPOS_FN_VCS_DISABLE_POSITION_COMPARE: Int = 34;
pub const EPOS_FN_VCS_DISABLE_POSITION_WINDOW: Int = 35;
pub const EPOS_FN_VCS_DISABLE_VELOCITY_WINDOW: Int = 36;
pub const EPOS_FN_VCS_ENABLE_ANALOG_CURRENT_SETPOINT: Int = 37;
pub const EPOS_FN_VCS_ENABLE_ANALOG_POSITION_SETPOINT: Int = 38;
pub const EPOS_FN_VCS_ENABLE_ANALOG_VELOCITY_SETPOINT: Int = 39;
pub const EPOS_FN_VCS_ENABLE_POSITION_COMPARE: Int = 40;
pub const EPOS_FN_VCS_ENABLE_POSITION_WINDOW: Int = 41;
pub const EPOS_FN_VCS_ENABLE_VELOCITY_WINDOW: Int = 42;
pub const EPOS_FN_VCS_FIND_HOME: Int = 43;
pub const EPOS_FN_VCS_GET_ALL_DIGITAL_INPUTS: Int = 44;
pub const EPOS_FN_VCS_GET_ALL_DIGITAL_OUTPUTS: Int = 45;
pub const EPOS_FN_VCS_GET_ANALOG_INPUT: Int = 46;
pub const EPOS_FN_VCS_GET_ANALOG_INPUT_STATE: Int = 47;
pub const EPOS_FN_VCS_GET_ANALOG_INPUT_VOLTAGE: Int = 48;
pub const EPOS_FN_VCS_GET_BAUDRATE_SELECTION: Int = 49;
pub const EPOS_FN_VCS_GET_CONTROLLER_GAIN: Int = 50;
pub const EPOS_FN_VCS_GET_CURRENT_IS: Int = 51;
pub const EPOS_FN_VCS_GET_CURRENT_IS_AVERAGED: Int = 52;
pub const EPOS_FN_VCS_GET_CURRENT_MUST: Int = 53;
pub const EPOS_FN_VCS_GET_CURRENT_REGULATOR_GAIN: Int = 54;
pub const EPOS_FN_VCS_GET_DC_MOTOR_PARAMETER: Int = 55;
pub const EPOS_FN_VCS_GET_DEVICE_ERROR_CODE: Int = 56;
pub const EPOS_FN_VCS_GET_DEVICE_NAME: Int = 57;
pub const EPOS_FN_VCS_GET_DEVICE_NAME_SELECTION: Int = 58;
pub const EPOS_FN_VCS_GET_DISABLE_STATE: Int = 59;
pub const EPOS_FN_VCS_GET_DRIVER_INFO: Int = 60;
pub const EPOS_FN_VCS_GET_EC_MOTOR_PARAMETER: Int = 61;
pub const EPOS_FN_VCS_GET_ENABLE_STATE: Int = 62;
pub const EPOS_FN_VCS_GET_ERROR_INFO: Int = 63;
pub const EPOS_FN_VCS_GET_FAULT_STATE: Int = 64;
pub const EPOS_FN_VCS_GET_FREE_IPM_BUFFER_SIZE: Int = 65;
pub const EPOS_FN_VCS_GET_GATEWAY_SETTINGS: Int = 66;
pub const EPOS_FN_VCS_GET_HALL_SENSOR_PARAMETER: Int = 67;
pub const EPOS_FN_VCS_GET_HOMING_PARAMETER: Int = 68;
pub const EPOS_FN_VCS_GET_HOMING_STATE: Int = 69;
pub const EPOS_FN_VCS_GET_INC_ENCODER_PARAMETER: Int = 70;
pub const EPOS_FN_VCS_GET_INTERFACE_NAME: Int = 71;
pub const EPOS_FN_VCS_GET_INTERFACE_NAME_SELECTION: Int = 72;
pub const EPOS_FN_VCS_GET_IPM_BUFFER_PARAMETER: Int = 73;
pub const EPOS_FN_VCS_GET_IPM_STATUS: Int = 74;
pub const EPOS_FN_VCS_GET_KEY_HANDLE: Int = 75;
pub const EPOS_FN_VCS_GET_MASTER_ENCODER_PARAMETER: Int = 76;
pub const EPOS_FN_VCS_GET_MAX_ACCELERATION: Int = 77;
pub const EPOS_FN_VCS_GET_MAX_FOLLOWING_ERROR: Int = 78;
pub const EPOS_FN_VCS_GET_MAX_PROFILE_VELOCITY: Int = 79;
pub const EPOS_FN_VCS_GET_MOTOR_TYPE: Int = 80;
pub const EPOS_FN_VCS_GET_MOVEMENT_STATE: Int = 81;
pub const EPOS_FN_VCS_GET_NB_OF_DEVICE_ERROR: Int = 82;
pub const EPOS_FN_VCS_GET_OBJECT: Int = 83;
pub const EPOS_FN_VCS_GET_OPERATION_MODE: Int = 84;
pub const EPOS_FN_VCS_GET_PORT_NAME: Int = 85;
pub const EPOS_FN_VCS_GET_PORT_NAME_SELECTION: Int = 86;
pub const EPOS_FN_VCS_GET_POSITION_COMPARE_PARAMETER: Int = 87;
pub const EPOS_FN_VCS_GET_POSITION_IS: Int = 88;
pub const EPOS_FN_VCS_GET_POSITION_MARKER_PARAMETER: Int = 89;
pub const EPOS_FN_VCS_GET_POSITION_MUST: Int = 90;
pub const EPOS_FN_VCS_GET_POSITION_PROFILE: Int = 91;
pub const EPOS_FN_VCS_GET_POSITION_REGULATOR_FEED_FORWARD: Int = 92;
pub const EPOS_FN_VCS_GET_POSITION_REGULATOR_GAIN: Int = 93;
pub const EPOS_FN_VCS_GET_PROTOCOL_STACK_NAME: Int = 94;
pub const EPOS_FN_VCS_GET_PROTOCOL_STACK_NAME_SELECTION: Int = 95;
pub const EPOS_FN_VCS_GET_PROTOCOL_STACK_SETTINGS: Int = 96;
pub const EPOS_FN_VCS_GET_QUICK_STOP_STATE: Int = 97;
pub const EPOS_FN_VCS_GET_SENSOR_TYPE: Int = 98;
pub const EPOS_FN_VCS_GET_SSI_ABS_ENCODER_PARAMETER: Int = 99;
pub const EPOS_FN_VCS_GET_SSI_ABS_ENCODER_PARAMETER_EX: Int = 100;
pub const EPOS_FN_VCS_GET_STATE: Int = 101;
pub const EPOS_FN_VCS_GET_STEP_DIRECTION_PARAMETER: Int = 102;
pub const EPOS_FN_VCS_GET_TARGET_POSITION: Int = 103;
pub const EPOS_FN_VCS_GET_TARGET_VELOCITY: Int = 104;
pub const EPOS_FN_VCS_GET_VELOCITY_IS: Int = 105;
pub const EPOS_FN_VCS_GET_VELOCITY_IS_AVERAGED: Int = 106;
pub const EPOS_FN_VCS_GET_VELOCITY_MUST: Int = 107;
pub const EPOS_FN_VCS_GET_VELOCITY_PROFILE: Int = 108;
pub const EPOS_FN_VCS_GET_VELOCITY_REGULATOR_FEED_FORWARD: Int = 109;
pub const EPOS_FN_VCS_GET_VELOCITY_REGULATOR_GAIN: Int = 110;
pub const EPOS_FN_VCS_GET_VELOCITY_UNITS: Int = 111;
pub const EPOS_FN_VCS_GET_VERSION: Int = 112;
pub const EPOS_FN_VCS_HALT_POSITION_MOVEMENT: Int = 113;
pub const EPOS_FN_VCS_HALT_VELOCITY_MOVEMENT: Int = 114;
pub const EPOS_FN_VCS_MOVE_TO_POSITION: Int = 115;
pub const EPOS_FN_VCS_MOVE_WITH_VELOCITY: Int = 116;
pub const EPOS_FN_VCS_OPEN_DEVICE: Int = 117;
pub const EPOS_FN_VCS_OPEN_SUB_DEVICE: Int = 118;
pub const EPOS_FN_VCS_READ_CANFRAME: Int = 119;
pub const EPOS_FN_VCS_READ_POSITION_MARKER_CAPTURED_POSITION: Int = 120;
pub const EPOS_FN_VCS_READ_POSITION_MARKER_COUNTER: Int = 121;
pub const EPOS_FN_VCS_REQUEST_CANFRAME: Int = 122;
pub const EPOS_FN_VCS_RESET_DEVICE: Int = 123;
pub const EPOS_FN_VCS_RESET_PORT_NAME_SELECTION: Int = 124;
pub const EPOS_FN_VCS_RESET_POSITION_MARKER_COUNTER: Int = 125;
pub const EPOS_FN_VCS_RESTORE: Int = 126;
pub const EPOS_FN_VCS_SEND_CANFRAME: Int = 127;
pub const EPOS_FN_VCS_SEND_NMT_SERVICE: Int = 128;
pub const EPOS_FN_VCS_SET_ALL_DIGITAL_OUTPUTS: Int = 129;
pub const EPOS_FN_VCS_SET_ANALOG_OUTPUT: Int = 130;
pub const EPOS_FN_VCS_SET_ANALOG_OUTPUT_STATE: Int = 131;
pub const EPOS_FN_VCS_SET_ANALOG_OUTPUT_VOLTAGE: Int = 132;
pub const EPOS_FN_VCS_SET_CONTROLLER_GAIN: Int = 133;
pub const EPOS_FN_VCS_SET_CURRENT_MUST: Int = 134;
pub const EPOS_FN_VCS_SET_CURRENT_REGULATOR_GAIN: Int = 135;
pub const EPOS_FN_VCS_SET_DC_MOTOR_PARAMETER: Int = 136;
pub const EPOS_FN_VCS_SET_DISABLE_STATE: Int = 137;
pub const EPOS_FN_VCS_SET_EC_MOTOR_PARAMETER: Int = 138;
pub const EPOS_FN_VCS_SET_ENABLE_STATE: Int = 139;
pub const EPOS_FN_VCS_SET_GATEWAY_SETTINGS: Int = 140;
pub const EPOS_FN_VCS_SET_HALL_SENSOR_PARAMETER: Int = 141;
pub const EPOS_FN_VCS_SET_HOMING_PARAMETER: Int = 142;
pub const EPOS_FN_VCS_SET_INC_ENCODER_PARAMETER: Int = 143;
pub const EPOS_FN_VCS_SET_IPM_BUFFER_PARAMETER: Int = 144;
pub const EPOS_FN_VCS_SET_MASTER_ENCODER_PARAMETER: Int = 145;
pub const EPOS_FN_VCS_SET_MAX_ACCELERATION: Int = 146;
pub const EPOS_FN_VCS_SET_MAX_FOLLOWING_ERROR: Int = 147;
pub const EPOS_FN_VCS_SET_MAX_PROFILE_VELOCITY: Int = 148;
pub const EPOS_FN_VCS_SET_MOTOR_TYPE: Int = 149;
pub const EPOS_FN_VCS_SET_OBJECT: Int = 150;
pub const EPOS_FN_VCS_SET_OPERATION_MODE: Int = 151;
pub const EPOS_FN_VCS_SET_POSITION_COMPARE_PARAMETER: Int = 152;
pub const EPOS_FN_VCS_SET_POSITION_COMPARE_REFERENCE_POSITION: Int = 153;
pub const EPOS_FN_VCS_SET_POSITION_MARKER_PARAMETER: Int = 154;
pub const EPOS_FN_VCS_SET_POSITION_MUST: Int = 155;
pub const EPOS_FN_VCS_SET_POSITION_PROFILE: Int = 156;
pub const EPOS_FN_VCS_SET_POSITION_REGULATOR_FEED_FORWARD: Int = 157;
pub const EPOS_FN_VCS_SET_POSITION_REGULATOR_GAIN: Int = 158;
pub const EPOS_FN_VCS_SET_PROTOCOL_STACK_SETTINGS: Int = 159;
pub const EPOS_FN_VCS_SET_QUICK_STOP_STATE: Int = 160;
pub const EPOS_FN_VCS_SET_SENSOR_TYPE: Int = 161;
pub const EPOS_FN_VCS_SET_SSI_ABS_ENCODER_PARAMETER: Int = 162;
pub const EPOS_FN_VCS_SET_SSI_ABS_ENCODER_PARAMETER_EX: Int = 163;
pub const EPOS_FN_VCS_SET_STATE: Int = 164;
pub const EPOS_FN_VCS_SET_STEP_DIRECTION_PARAMETER: Int = 165;
pub const EPOS_FN_VCS_SET_VELOCITY_MUST: Int = 166;
pub const EPOS_FN_VCS_SET_VELOCITY_PROFILE: Int = 167;
pub const EPOS_FN_VCS_SET_VELOCITY_REGULATOR_FEED_FORWARD: Int = 168;
pub const EPOS_FN_VCS_SET_VELOCITY_REGULATOR_GAIN: Int = 169;
pub const EPOS_FN_VCS_SET_VELOCITY_UNITS: Int = 170;
pub const EPOS_FN_VCS_START_IPM_TRAJECTORY: Int = 171;
pub const EPOS_FN_VCS_STOP_HOMING: Int = 172;
pub const EPOS_FN_VCS_STOP_IPM_TRAJECTORY: Int = 173;
pub const EPOS_FN_VCS_STORE: Int = 174;
pub const EPOS_FN_VCS_WAIT_FOR_HOMING_ATTAINED: Int = 175;
pub const EPOS_FN_VCS_WAIT_FOR_TARGET_REACHED: Int = 176;

// =========================================================================
// Loader
// =========================================================================

/// Load an explicitly named runtime.  The 177 declared VCS_* entries must all
/// resolve (any miss -> Err(ABI), handles closed, nothing leaked); the two
/// Linux-layer helpers are resolved opportunistically.  Bogus names exercise
/// the ABSENT/ABI classification deterministically.  O(declared surface).
pub fn epos_load_named(soname: Str) -> Result[EposLibrary, EposLoadError]
  requires: soname.len() > 0
{
  let r = dl.dl_open(soname);
  if !r.is_ok {
    return Err(EposLoadError{ kind: EPOS_LOAD_ABSENT; message: soname + ": " + r.error });
  }
  let h: Int = r.value;

  let names = epos_entry_names();
  var ptrs: Vec[Int] = Vec[Int].new();
  var i: Int = 0;
  while i < EPOS_VCS_COUNT {
    let s = dl.dl_sym(h, names[i]);
    if !s.is_ok {
      var ig = dl.dl_close(h);
      return Err(EposLoadError{ kind: EPOS_LOAD_ABI; message: names[i] + ": " + s.error });
    }
    ptrs.push(s.value);
    i = i + 1;
  }

  var h_create: Int = 0;
  var h_delete: Int = 0;
  let c1 = dl.dl_sym(h, "CreateCommunication");
  if c1.is_ok { h_create = c1.value; }
  let c2 = dl.dl_sym(h, "DeleteCommunication");
  if c2.is_ok { h_delete = c2.value; }
  let has_helpers: Bool = (h_create != 0) && (h_delete != 0);

  return Ok(EposLibrary{
    h: h;
    soname: soname;
    h_create_comm: h_create;
    h_delete_comm: h_delete;
    has_helpers: has_helpers;
    ptrs: ptrs;
  });
}

/// Load the first available runtime from the OS search path:
/// `EposCmd64.dll`, then `EposCmd.dll`, then `libEposCmd.so`.
/// Err(ABSENT) when no candidate resolves (the caller reports SKIP);
/// Err(ABI) when a loaded library lacks declared entry points (FAIL).
/// O(candidates * declared surface).
pub fn epos_load() -> Result[EposLibrary, EposLoadError]
  requires: true
{
  let c1 = epos_load_named(EPOS_SONAME_WIN64);
  if c1.is_ok { return Ok(c1.value); }
  if c1.error.kind == EPOS_LOAD_ABI { return Err(c1.error); }

  let c2 = epos_load_named(EPOS_SONAME_WIN32);
  if c2.is_ok { return Ok(c2.value); }
  if c2.error.kind == EPOS_LOAD_ABI { return Err(c2.error); }

  let c3 = epos_load_named(EPOS_SONAME_LINUX);
  if c3.is_ok { return Ok(c3.value); }
  if c3.error.kind == EPOS_LOAD_ABI { return Err(c3.error); }

  return Err(EposLoadError{
    kind: EPOS_LOAD_ABSENT;
    message: "epos: no EPOS Command Library candidate found (tried EposCmd64.dll, EposCmd.dll, libEposCmd.so)",
  });
}

/// Release the library handle.  O(1).
pub fn epos_close(lib: &EposLibrary) -> Result[Unit, Str]
  requires: lib.h != 0
{
  return dl.dl_close(lib.h);
}

/// Load, query `VCS_GetDriverInfo` (no hardware needed: the library reports
/// its own name/version), close.  Err(ABSENT) -> SKIP.  O(declared surface).
pub fn epos_probe_default() -> Result[EposDriverInfo, EposLoadError]
  requires: true
{
  let l = epos_load();
  if !l.is_ok {
    return Err(l.error);
  }
  let lib: EposLibrary = l.value;

  var name = epos_slot(EPOS_STR_MAX);
  var version = epos_slot(EPOS_STR_MAX);
  var err = epos_slot(4);
  var rc: Int = 0;
  unsafe {
    let f = lib.ptrs[EPOS_FN_VCS_GET_DRIVER_INFO] as fn(*UInt8, Int32, *UInt8, Int32, *UInt8) -> Int32;
    rc = f(name.as_mut_ptr(), EPOS_STR_MAX as Int32, version.as_mut_ptr(), EPOS_STR_MAX as Int32, err.as_mut_ptr()) as Int;
  }
  let error_code = epos_rd_u32(&err, 0);
  let lib_name = epos_str_from_slot(&name);
  let lib_version = epos_str_from_slot(&version);

  let c = epos_close(&lib);
  if !c.is_ok {
    return Err(EposLoadError{ kind: EPOS_LOAD_ABI; message: c.error });
  }
  if rc != EPOS_RC_OK {
    return Err(EposLoadError{
      kind: EPOS_LOAD_ABI;
      message: "VCS_GetDriverInfo rc=" + convert.int_to_string(rc)
        + " error=" + convert.int_to_string(error_code),
    });
  }
  return Ok(EposDriverInfo{
    library_name: lib_name;
    library_version: lib_version;
  });
}
