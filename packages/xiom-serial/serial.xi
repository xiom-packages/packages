// XIOM -- xiom.serial: UART/serial-port bindings (Win32 comm API).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN DECISION (MCU/host bridge sector): **platform wrapper, not a
// vendored upstream**. The canonical cross-platform UART library is
// libserialport, which is LGPL-3.0+ -- outside the vendoring policy
// entirely (owner restated 2026-10-16).  This module therefore implements
// the Win32 comm API directly (kernel32 CreateFileA/DCB/COMMTIMEOUTS/
// PurgeComm family + advapi32 SERIALCOMM enumeration), loaded through
// xiom.ffi.dl exactly like the xiom.ssl / xiom.openssl pattern: system
// libraries only, nothing vendored, no C shipped.  The oracle is the
// Microsoft Win32 API documentation plus the local Windows SDK headers
// (winbase.h/winerror.h, 10.0.26100.0); the libserialport clone
// (E:\repos\serial @ 21b3dfe5, reference-only) cross-checks enumeration
// and timeout/purge semantics.  See PROVENANCE.md / SPEC.md.
//
// All XIOM `unsafe`/`extern` live in this single module (G5); every call
// is an fn-pointer cast over `xiom.ffi.dl`.  Structs (DCB 28 bytes,
// COMMTIMEOUTS 20 bytes) travel through XIOM-owned Vec[UInt8] slots and
// the ffi byte helpers -- the W-2 out-param recipe.
//
// Classification:
//   SERIAL_LOAD_ABSENT -> no Win32 serial API on this OS (non-Windows
//       leg) or a genuinely absent library -> SKIP (typed, deterministic)
//   SERIAL_LOAD_ABI    -> a library loaded but entry points are missing
//       -> FAIL
//   absent/removed/busy device -> typed SerialError (NOT_FOUND /
//       DISCONNECTED / ACCESS_DENIED), the absent-device SKIP path
//   operational failures -> typed SerialError { kind, code, message }
//
// Coverage (0.1.0 declared surface, 100%): enumerate ports; open/close;
// configure baud/data-bits/parity/stop/flow-control; get/set config;
// blocking and poll-mode reads with timeouts; writes; flush (input/
// output/both) + drain; typed errors throughout; pure DCB/COMMTIMEOUTS
// codecs for golden and round-trip testing.  DTR/RTS line control, modem
// status, break signalling, XON/XOFF trigger tuning and POSIX termios are
// later phases (ROADMAP.md).
//
// Documented deviations from libserialport (deliberate, for the MCU/
// device-fleet use case): serial_open applies default timeouts (read
// 1000 ms blocking-with-timeout, write 1000 ms) so an open port is
// immediately readable; libserialport opens with all-zero timeouts and
// defers mode selection.  The COMMTIMEOUTS encodings for both modes are
// byte-identical to the reference (windows semantics: interval=0 for
// blocking, interval=MAXDWORD for poll).

module xiom.serial

use xiom.ffi.dl;
use xiom.ffi;

// =========================================================================
// Identity
// =========================================================================

/// Backend identity reported by serial_probe.
pub const SERIAL_API_WIN32: Str = "win32-comm-api";

// =========================================================================
// Classification and error kinds
// =========================================================================

/// No Win32 serial API on this OS (non-Windows leg) -> SKIP.
pub const SERIAL_LOAD_ABSENT: Int = 0;
/// A library loaded but entry points are missing -> FAIL.
pub const SERIAL_LOAD_ABI: Int = 1;
/// Device absent (ENOENT-class: no such COM port).
pub const SERIAL_ERR_NOT_FOUND: Int = 2;
/// Device busy or access denied (already open elsewhere / permissions).
pub const SERIAL_ERR_ACCESS_DENIED: Int = 3;
/// Handle invalid or already closed (local check).
pub const SERIAL_ERR_INVALID_HANDLE: Int = 4;
/// Argument rejected by validation (no OS call made).
pub const SERIAL_ERR_INVALID_ARG: Int = 5;
/// No data within the configured read timeout (ERROR_TIMEOUT).
pub const SERIAL_ERR_TIMEOUT: Int = 6;
/// Device removed mid-operation (ERROR_BROKEN_PIPE).
pub const SERIAL_ERR_DISCONNECTED: Int = 7;
/// Any other OS failure (code carried in SerialError.code).
pub const SERIAL_ERR_IO: Int = 8;

// =========================================================================
// Configuration enums (values match the Win32 DCB constants)
// =========================================================================

/// Parity: DCB.Parity values (NOPARITY..SPACEPARITY).
pub const SERIAL_PARITY_NONE: Int = 0;
pub const SERIAL_PARITY_ODD: Int = 1;
pub const SERIAL_PARITY_EVEN: Int = 2;
pub const SERIAL_PARITY_MARK: Int = 3;
pub const SERIAL_PARITY_SPACE: Int = 4;

/// Stop bits: DCB.StopBits values (ONESTOPBIT/ONE5STOPBITS/TWOSTOPBITS).
/// 1.5 stop bits is only valid with 5 data bits; 2 stop bits is invalid
/// with 5 data bits (winbase.h DCB notes; enforced by validation).
pub const SERIAL_STOP_ONE: Int = 0;
pub const SERIAL_STOP_ONE_POINT_FIVE: Int = 1;
pub const SERIAL_STOP_TWO: Int = 2;

/// Flow control: SERIAL_FLOW_RTS_CTS sets fOutxCtsFlow + RTS handshake;
/// SERIAL_FLOW_XON_XOFF sets fOutX + fInX; NONE enables RTS/DTR output.
pub const SERIAL_FLOW_NONE: Int = 0;
pub const SERIAL_FLOW_RTS_CTS: Int = 1;
pub const SERIAL_FLOW_XON_XOFF: Int = 2;

/// Flush selector for serial_flush.
pub const SERIAL_FLUSH_INPUT: Int = 1;
pub const SERIAL_FLUSH_OUTPUT: Int = 2;
pub const SERIAL_FLUSH_BOTH: Int = 3;

/// Baud rate validation window (1 .. 12,000,000: FT232H/STM32-class
/// upper range; drivers reject anything they cannot clock).
pub const SERIAL_BAUD_MIN: Int = 1;
pub const SERIAL_BAUD_MAX: Int = 12000000;

// =========================================================================
// Win32 constants (oracle: winbase.h / winerror.h / winnt.h, Windows SDK
// 10.0.26100.0; verified against the local headers on this host)
// =========================================================================

const WIN32_ERROR_FILE_NOT_FOUND: Int = 2;
const WIN32_ERROR_ACCESS_DENIED: Int = 5;
const WIN32_ERROR_INVALID_HANDLE: Int = 6;
const WIN32_ERROR_INVALID_PARAMETER: Int = 87;
const WIN32_ERROR_BROKEN_PIPE: Int = 109;
const WIN32_ERROR_INSUFFICIENT_BUFFER: Int = 122;
const WIN32_ERROR_MORE_DATA: Int = 234;
const WIN32_ERROR_NO_MORE_ITEMS: Int = 259;
const WIN32_ERROR_TIMEOUT: Int = 1460;

const SERIAL_ACCESS_RW: Int = 3221225472;     // GENERIC_READ|GENERIC_WRITE = 0xC0000000
const SERIAL_OPEN_EXISTING: Int = 3;          // OPEN_EXISTING
const SERIAL_HKEY_LOCAL_MACHINE: Int = 2147483650; // 0x80000002
const SERIAL_KEY_READ: Int = 131097;          // KEY_READ = 0x20019
const SERIAL_REG_SZ: Int = 1;                 // REG_SZ

const SERIAL_MAXDWORD: Int = 4294967295;      // MAXDWORD (COMMTIMEOUTS poll mode)

// DCB layout (winbase.h): 28 bytes.
//   0  DCBlength     u32 (28)
//   4  BaudRate      u32
//   8  Flags         u32 (bitfield, see DCB_F_* below)
//   12 wReserved     u16 (0)
//   14 XonLim        u16 (2048 default)
//   16 XoffLim       u16 (512 default)
//   18 ByteSize      u8  (5..8)
//   19 Parity        u8  (0..4)
//   20 StopBits      u8  (0..2)
//   21 XonChar       u8  (0x11 default)
//   22 XoffChar      u8  (0x13 default)
//   23 ErrorChar     u8  (0)
//   24 EofChar       u8  (0)
//   25 EvtChar       u8  (0)
//   26 wReserved1    u16 (0)
const SERIAL_DCB_LENGTH: Int = 28;
const SERIAL_DCB_SLOT: Int = 32;              // GetCommState target (headroom)
const SERIAL_TIMEOUTS_LENGTH: Int = 20;       // COMMTIMEOUTS

// DCB Flags bits.  fBinary must be 1 (DCB documentation).
const SERIAL_DCB_F_BINARY: Int = 1;           // bit 0
const SERIAL_DCB_F_PARITY: Int = 2;           // bit 1
const SERIAL_DCB_F_OUTX_CTS_FLOW: Int = 4;    // bit 2
const SERIAL_DCB_F_OUTX_DSR_FLOW: Int = 8;    // bit 3
const SERIAL_DCB_F_DTR_ENABLE: Int = 16;      // bits 4-5 value 1 (DTR_CONTROL_ENABLE)
const SERIAL_DCB_F_OUT_X: Int = 256;          // bit 8
const SERIAL_DCB_F_IN_X: Int = 512;           // bit 9
const SERIAL_DCB_F_RTS_ENABLE: Int = 4096;    // bits 12-13 value 1 (RTS_CONTROL_ENABLE)
const SERIAL_DCB_F_RTS_HANDSHAKE: Int = 8192; // bits 12-13 value 2 (RTS_CONTROL_HANDSHAKE)

// PurgeComm flags.
const SERIAL_PURGE_TXCLEAR: Int = 4;
const SERIAL_PURGE_RXCLEAR: Int = 8;

// Registry enumeration sizing.
const SERIAL_REG_NAME_MAX: Int = 256;
const SERIAL_REG_DATA_MAX: Int = 256;
const SERIAL_REG_MAX_VALUES: Int = 512;

/// Default read timeout applied by serial_open (ms; 0 would be poll mode).
pub const SERIAL_DEFAULT_READ_MS: Int = 1000;
/// Default write timeout applied by serial_open (ms).
pub const SERIAL_DEFAULT_WRITE_MS: Int = 1000;

// =========================================================================
// Types
// =========================================================================

/// A typed serial failure: classification or operational error.  `code`
/// carries the Win32 error for OS failures, 0 for local validation.
pub type SerialError = {
  kind: Int;
  code: Int;
  message: Str;
}

/// One present serial port (COM3-class name, as the OS lists it).
pub type SerialPortInfo = {
  name: Str;
}

/// Line configuration: baud, data bits (5..8), parity, stop bits, flow.
pub type SerialConfig = {
  baud: Int;
  data_bits: Int;
  parity: Int;
  stop_bits: Int;
  flow: Int;
}

/// Read/write timeouts in milliseconds (0 = poll mode for reads,
/// immediate-return for writes; see serial_timeouts_encode).
pub type SerialTimeouts = {
  read_ms: Int;
  write_ms: Int;
}

/// One loaded Win32 serial backend and its resolved entry points.  Owned
/// by the caller; release with `serial_unload`.
pub type SerialLibrary = {
  kernel: Int;
  registry: Int;
  kernel_name: Str;
  registry_name: Str;
  p_create_file_a: Int;
  p_close_handle: Int;
  p_read_file: Int;
  p_write_file: Int;
  p_get_comm_state: Int;
  p_set_comm_state: Int;
  p_get_comm_timeouts: Int;
  p_set_comm_timeouts: Int;
  p_purge_comm: Int;
  p_flush_file_buffers: Int;
  p_get_last_error: Int;
  p_reg_open_key_ex_a: Int;
  p_reg_enum_value_a: Int;
  p_reg_close_key: Int;
}

/// One open serial port.  Owned; release with `serial_close`.
pub type SerialPort = {
  handle: Int;
  name: Str;
}

/// Backend identity reported by serial_probe.
pub type SerialBackendInfo = {
  api: Str;
  kernel: Str;
  registry: Str;
  entry_points: Int;
}

// =========================================================================
// Local helpers (lane pattern, BINDINGS-COMPILER-FINDINGS: avoids
// cross-module convert resolution traps inside confined modules)
// =========================================================================

/// Local Int-to-Str.
/// Complexity: O(digits).
fn int_to_str(n: Int) -> Str
  requires: true
{
  if n == 0 { return "0"; }
  var num = n;
  var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  if neg { return "-" + out; }
  return out;
}

/// Local little-endian u16 write (the stdlib ffi exposes u8/u32/u64).
/// Complexity: O(1).
fn wr_u16_le(p: *UInt8, v: Int)
  requires: p != null
  requires: v >= 0
{
  unsafe {
    ffi.ptr_write_u8(p, v & 255);
    ffi.ptr_write_u8(p + 1, (v >> 8) & 255);
  }
}

/// Human name for a Win32 error code (subset this module maps; the
/// canonical names from winerror.h).
/// Complexity: O(1).
pub fn serial_win32_error_name(code: Int) -> Str
  requires: true
{
  if code == WIN32_ERROR_FILE_NOT_FOUND { return "ERROR_FILE_NOT_FOUND"; }
  if code == WIN32_ERROR_ACCESS_DENIED { return "ERROR_ACCESS_DENIED"; }
  if code == WIN32_ERROR_INVALID_HANDLE { return "ERROR_INVALID_HANDLE"; }
  if code == WIN32_ERROR_INVALID_PARAMETER { return "ERROR_INVALID_PARAMETER"; }
  if code == WIN32_ERROR_BROKEN_PIPE { return "ERROR_BROKEN_PIPE"; }
  if code == WIN32_ERROR_INSUFFICIENT_BUFFER { return "ERROR_INSUFFICIENT_BUFFER"; }
  if code == WIN32_ERROR_MORE_DATA { return "ERROR_MORE_DATA"; }
  if code == WIN32_ERROR_NO_MORE_ITEMS { return "ERROR_NO_MORE_ITEMS"; }
  if code == WIN32_ERROR_TIMEOUT { return "ERROR_TIMEOUT"; }
  return "OS_ERROR";
}

/// Human name for a SerialError kind.
/// Complexity: O(1).
pub fn serial_error_name(kind: Int) -> Str
  requires: true
{
  if kind == SERIAL_LOAD_ABSENT { return "absent"; }
  if kind == SERIAL_LOAD_ABI { return "abi"; }
  if kind == SERIAL_ERR_NOT_FOUND { return "not-found"; }
  if kind == SERIAL_ERR_ACCESS_DENIED { return "access-denied"; }
  if kind == SERIAL_ERR_INVALID_HANDLE { return "invalid-handle"; }
  if kind == SERIAL_ERR_INVALID_ARG { return "invalid-arg"; }
  if kind == SERIAL_ERR_TIMEOUT { return "timeout"; }
  if kind == SERIAL_ERR_DISCONNECTED { return "disconnected"; }
  if kind == SERIAL_ERR_IO { return "io"; }
  return "unknown";
}

/// Human name for a parity code.
/// Complexity: O(1).
pub fn serial_parity_name(parity: Int) -> Str
  requires: true
{
  if parity == SERIAL_PARITY_NONE { return "none"; }
  if parity == SERIAL_PARITY_ODD { return "odd"; }
  if parity == SERIAL_PARITY_EVEN { return "even"; }
  if parity == SERIAL_PARITY_MARK { return "mark"; }
  if parity == SERIAL_PARITY_SPACE { return "space"; }
  return "invalid";
}

/// Human name for a stop-bits code.
/// Complexity: O(1).
pub fn serial_stop_name(stop_bits: Int) -> Str
  requires: true
{
  if stop_bits == SERIAL_STOP_ONE { return "1"; }
  if stop_bits == SERIAL_STOP_ONE_POINT_FIVE { return "1.5"; }
  if stop_bits == SERIAL_STOP_TWO { return "2"; }
  return "invalid";
}

/// Human name for a flow-control code.
/// Complexity: O(1).
pub fn serial_flow_name(flow: Int) -> Str
  requires: true
{
  if flow == SERIAL_FLOW_NONE { return "none"; }
  if flow == SERIAL_FLOW_RTS_CTS { return "rts-cts"; }
  if flow == SERIAL_FLOW_XON_XOFF { return "xon-xoff"; }
  return "invalid";
}

/// Build a local validation failure (code 0: no OS call was made).
/// Complexity: O(len).
fn fail_arg(message: Str) -> SerialError
  requires: message.len() > 0
{
  return SerialError{ kind: SERIAL_ERR_INVALID_ARG; code: 0; message: message };
}

/// Map a Win32 error code to a typed SerialError with the OS name.
/// Complexity: O(1).
fn map_win32(code: Int, context: Str) -> SerialError
  requires: code != 0
  requires: context.len() > 0
{
  var kind = SERIAL_ERR_IO;
  if code == WIN32_ERROR_FILE_NOT_FOUND { kind = SERIAL_ERR_NOT_FOUND; }
  elif code == WIN32_ERROR_ACCESS_DENIED { kind = SERIAL_ERR_ACCESS_DENIED; }
  elif code == WIN32_ERROR_INVALID_HANDLE { kind = SERIAL_ERR_INVALID_HANDLE; }
  elif code == WIN32_ERROR_INVALID_PARAMETER { kind = SERIAL_ERR_INVALID_ARG; }
  elif code == WIN32_ERROR_BROKEN_PIPE { kind = SERIAL_ERR_DISCONNECTED; }
  elif code == WIN32_ERROR_TIMEOUT { kind = SERIAL_ERR_TIMEOUT; }
  return SerialError{
    kind: kind;
    code: code;
    message: context + " (win32 " + int_to_str(code) + ": " + serial_win32_error_name(code) + ")";
  };
}

// =========================================================================
// Pure codecs: DCB (28-byte wire format) and COMMTIMEOUTS (20-byte)
// =========================================================================

/// Validate a line configuration against the DCB field constraints.
/// Complexity: O(1).
pub fn serial_config_validate(cfg: &SerialConfig) -> Result[Unit, SerialError]
  requires: true
{
  if cfg.baud < SERIAL_BAUD_MIN {
    return Err(fail_arg("config: baud must be >= " + int_to_str(SERIAL_BAUD_MIN)));
  }
  if cfg.baud > SERIAL_BAUD_MAX {
    return Err(fail_arg("config: baud must be <= " + int_to_str(SERIAL_BAUD_MAX)));
  }
  if cfg.data_bits < 5 {
    return Err(fail_arg("config: data_bits must be 5..8 (got " + int_to_str(cfg.data_bits) + ")"));
  }
  if cfg.data_bits > 8 {
    return Err(fail_arg("config: data_bits must be 5..8 (got " + int_to_str(cfg.data_bits) + ")"));
  }
  if cfg.parity < SERIAL_PARITY_NONE {
    return Err(fail_arg("config: parity must be 0..4 (got " + int_to_str(cfg.parity) + ")"));
  }
  if cfg.parity > SERIAL_PARITY_SPACE {
    return Err(fail_arg("config: parity must be 0..4 (got " + int_to_str(cfg.parity) + ")"));
  }
  if cfg.stop_bits < SERIAL_STOP_ONE {
    return Err(fail_arg("config: stop_bits must be 0..2 (got " + int_to_str(cfg.stop_bits) + ")"));
  }
  if cfg.stop_bits > SERIAL_STOP_TWO {
    return Err(fail_arg("config: stop_bits must be 0..2 (got " + int_to_str(cfg.stop_bits) + ")"));
  }
  if cfg.stop_bits == SERIAL_STOP_ONE_POINT_FIVE {
    if cfg.data_bits != 5 {
      return Err(fail_arg("config: 1.5 stop bits is only valid with 5 data bits (winbase.h DCB)"));
    }
  }
  if cfg.stop_bits == SERIAL_STOP_TWO {
    if cfg.data_bits == 5 {
      return Err(fail_arg("config: 2 stop bits is not valid with 5 data bits (winbase.h DCB)"));
    }
  }
  if cfg.flow < SERIAL_FLOW_NONE {
    return Err(fail_arg("config: flow must be 0..2 (got " + int_to_str(cfg.flow) + ")"));
  }
  if cfg.flow > SERIAL_FLOW_XON_XOFF {
    return Err(fail_arg("config: flow must be 0..2 (got " + int_to_str(cfg.flow) + ")"));
  }
  return Ok(());
}

/// The DCB Flags DWORD for a validated configuration.  Deterministic
/// flag set: fBinary=1; fParity set for any non-NONE parity; flow bits
/// per SERIAL_FLOW_*; DTR_CONTROL_ENABLE; fOutxDsrFlow/fDsrSensitivity/
/// fTXContinueOnXoff/fErrorChar/fNull/fAbortOnError cleared (the
/// libserialport "sane settings" set, cross-checked at the reference).
/// Complexity: O(1).
fn dcb_flags(cfg: &SerialConfig) -> Int
  requires: true
{
  var flags = SERIAL_DCB_F_BINARY + SERIAL_DCB_F_DTR_ENABLE;
  if cfg.parity != SERIAL_PARITY_NONE {
    flags = flags + SERIAL_DCB_F_PARITY;
  }
  if cfg.flow == SERIAL_FLOW_RTS_CTS {
    flags = flags + SERIAL_DCB_F_OUTX_CTS_FLOW + SERIAL_DCB_F_RTS_HANDSHAKE;
  } elif cfg.flow == SERIAL_FLOW_XON_XOFF {
    flags = flags + SERIAL_DCB_F_OUT_X + SERIAL_DCB_F_IN_X + SERIAL_DCB_F_RTS_ENABLE;
  } else {
    flags = flags + SERIAL_DCB_F_RTS_ENABLE;
  }
  return flags;
}

/// Patch a caller-owned DCB slot (>= 28 bytes) with a validated
/// configuration: DCBlength, BaudRate, Flags, ByteSize, Parity,
/// StopBits.  All other DCB fields are left as the caller set them
/// (the serial_configure flow starts from GetCommState).
/// Complexity: O(1).
pub fn serial_dcb_patch(cfg: &SerialConfig, dcb: &mut Vec[UInt8]) -> Result[Unit, SerialError]
  requires: true
{
  let v = serial_config_validate(cfg);
  if !v.is_ok { return Err(v.error); }
  if dcb.len() < SERIAL_DCB_LENGTH {
    return Err(fail_arg("dcb_patch: slot smaller than 28 bytes"));
  }
  unsafe {
    let p = dcb.as_mut_ptr();
    ffi.ptr_write_u32_le(p, SERIAL_DCB_LENGTH);
    ffi.ptr_write_u32_le(p + 4, cfg.baud);
    ffi.ptr_write_u32_le(p + 8, dcb_flags(cfg));
    ffi.ptr_write_u8(p + 18, cfg.data_bits);
    ffi.ptr_write_u8(p + 19, cfg.parity);
    ffi.ptr_write_u8(p + 20, cfg.stop_bits);
  }
  return Ok(());
}

/// Encode a standalone DCB (28 bytes) for a validated configuration,
/// with the documented defaults for unmanaged fields (wReserved=0,
/// XonLim=2048, XoffLim=512, XonChar=0x11, XoffChar=0x13, other chars 0).
/// Complexity: O(1).
pub fn serial_dcb_encode(cfg: &SerialConfig) -> Result[Vec[UInt8], SerialError]
  requires: true
{
  var dcb: Vec[UInt8] = Vec[UInt8].with_len(SERIAL_DCB_LENGTH);
  unsafe {
    let p = dcb.as_mut_ptr();
    wr_u16_le(p + 14, 2048);
    wr_u16_le(p + 16, 512);
    ffi.ptr_write_u8(p + 21, 17);
    ffi.ptr_write_u8(p + 22, 19);
  }
  let r = serial_dcb_patch(cfg, &mut dcb);
  if !r.is_ok { return Err(r.error); }
  return Ok(dcb);
}

/// Decode a DCB buffer (>= 28 bytes) into a SerialConfig.  Flow is read
/// back from the flags with hardware (fOutxCtsFlow) taking precedence
/// over software (fOutX/fInX); parity/data-bits/stop-bits come from
/// their byte fields.
/// Complexity: O(1).
pub fn serial_dcb_decode(dcb: &Vec[UInt8]) -> Result[SerialConfig, SerialError]
  requires: true
{
  if dcb.len() < SERIAL_DCB_LENGTH {
    return Err(fail_arg("dcb_decode: slot smaller than 28 bytes"));
  }
  var baud = 0;
  var flags = 0;
  unsafe {
    let p = dcb.as_mut_ptr();
    baud = ffi.ptr_read_u32_le(p + 4);
    flags = ffi.ptr_read_u32_le(p + 8);
  }
  let parity = dcb[19] as Int;
  let data_bits = dcb[18] as Int;
  let stop_bits = dcb[20] as Int;
  var flow = SERIAL_FLOW_NONE;
  if (flags & SERIAL_DCB_F_OUTX_CTS_FLOW) != 0 {
    flow = SERIAL_FLOW_RTS_CTS;
  } elif (flags & SERIAL_DCB_F_OUT_X) != 0 {
    flow = SERIAL_FLOW_XON_XOFF;
  } elif (flags & SERIAL_DCB_F_IN_X) != 0 {
    flow = SERIAL_FLOW_XON_XOFF;
  }
  return Ok(SerialConfig{
    baud: baud;
    data_bits: data_bits;
    parity: parity;
    stop_bits: stop_bits;
    flow: flow;
  });
}

/// Encode COMMTIMEOUTS (20 bytes) from read/write millisecond timeouts.
///   read_ms > 0 : interval=0, multiplier=0, constant=read_ms
///                 (blocking until >= 1 byte or the total timeout)
///   read_ms = 0 : interval=MAXDWORD, multiplier=0, constant=0
///                 (poll: return immediately with whatever is buffered)
///   write_ms    : multiplier=0, constant=write_ms (0 = return as soon
///                 as the bytes are accepted into the driver queue)
/// Complexity: O(1).
pub fn serial_timeouts_encode(t: &SerialTimeouts) -> Result[Vec[UInt8], SerialError]
  requires: true
{
  if t.read_ms < 0 {
    return Err(fail_arg("timeouts: read_ms must be >= 0"));
  }
  if t.write_ms < 0 {
    return Err(fail_arg("timeouts: write_ms must be >= 0"));
  }
  if t.read_ms > SERIAL_MAXDWORD {
    return Err(fail_arg("timeouts: read_ms over MAXDWORD"));
  }
  if t.write_ms > SERIAL_MAXDWORD {
    return Err(fail_arg("timeouts: write_ms over MAXDWORD"));
  }
  var out: Vec[UInt8] = Vec[UInt8].with_len(SERIAL_TIMEOUTS_LENGTH);
  unsafe {
    let p = out.as_mut_ptr();
    if t.read_ms == 0 {
      ffi.ptr_write_u32_le(p, SERIAL_MAXDWORD);
      ffi.ptr_write_u32_le(p + 4, 0);
      ffi.ptr_write_u32_le(p + 8, 0);
    } else {
      ffi.ptr_write_u32_le(p, 0);
      ffi.ptr_write_u32_le(p + 4, 0);
      ffi.ptr_write_u32_le(p + 8, t.read_ms);
    }
    ffi.ptr_write_u32_le(p + 12, 0);
    ffi.ptr_write_u32_le(p + 16, t.write_ms);
  }
  return Ok(out);
}

/// Decode COMMTIMEOUTS (>= 20 bytes) back to millisecond timeouts.
/// The canonical poll shape (interval=MAXDWORD, multiplier 0,
/// constant 0) decodes to read_ms = 0; otherwise read_ms = constant
/// (this module only emits multiplier 0).
/// Complexity: O(1).
pub fn serial_timeouts_decode(bytes: &Vec[UInt8]) -> Result[SerialTimeouts, SerialError]
  requires: true
{
  if bytes.len() < SERIAL_TIMEOUTS_LENGTH {
    return Err(fail_arg("timeouts_decode: slot smaller than 20 bytes"));
  }
  var interval = 0;
  var read_const = 0;
  var write_const = 0;
  unsafe {
    let p = bytes.as_mut_ptr();
    interval = ffi.ptr_read_u32_le(p);
    read_const = ffi.ptr_read_u32_le(p + 8);
    write_const = ffi.ptr_read_u32_le(p + 16);
  }
  var read_ms = read_const;
  if interval == SERIAL_MAXDWORD {
    if read_const == 0 {
      read_ms = 0;
    }
  }
  return Ok(SerialTimeouts{ read_ms: read_ms; write_ms: write_const; });
}

// =========================================================================
// Loader (multi-library: kernel32 comm API + advapi32 registry)
// =========================================================================

fn load_fail(kernel: Int, message: Str) -> Result[SerialLibrary, SerialError]
  requires: kernel != 0
  requires: message.len() > 0
{
  var ig = dl.dl_close(kernel);
  return Err(SerialError{ kind: SERIAL_LOAD_ABI; code: 0; message: message });
}

fn load_fail2(kernel: Int, registry: Int, message: Str) -> Result[SerialLibrary, SerialError]
  requires: kernel != 0
  requires: registry != 0
  requires: message.len() > 0
{
  var ig1 = dl.dl_close(registry);
  var ig2 = dl.dl_close(kernel);
  return Err(SerialError{ kind: SERIAL_LOAD_ABI; code: 0; message: message });
}

fn sym_or(handle: Int, name: Str) -> Result[Int, Str]
  requires: handle != 0
  requires: name.len() > 0
{
  let a = dl.dl_sym(handle, name);
  if !a.is_ok { return Err(name + ": " + a.error); }
  return Ok(a.value);
}

fn entry_points(k: Int, a: Int, kname: Str) -> Result[SerialLibrary, SerialError]
  requires: k != 0
  requires: a != 0
  requires: kname.len() > 0
{
  let e01 = sym_or(k, "CreateFileA");
  if !e01.is_ok { return load_fail2(k, a, e01.error); }
  let e02 = sym_or(k, "CloseHandle");
  if !e02.is_ok { return load_fail2(k, a, e02.error); }
  let e03 = sym_or(k, "ReadFile");
  if !e03.is_ok { return load_fail2(k, a, e03.error); }
  let e04 = sym_or(k, "WriteFile");
  if !e04.is_ok { return load_fail2(k, a, e04.error); }
  let e05 = sym_or(k, "GetCommState");
  if !e05.is_ok { return load_fail2(k, a, e05.error); }
  let e06 = sym_or(k, "SetCommState");
  if !e06.is_ok { return load_fail2(k, a, e06.error); }
  let e07 = sym_or(k, "GetCommTimeouts");
  if !e07.is_ok { return load_fail2(k, a, e07.error); }
  let e08 = sym_or(k, "SetCommTimeouts");
  if !e08.is_ok { return load_fail2(k, a, e08.error); }
  let e09 = sym_or(k, "PurgeComm");
  if !e09.is_ok { return load_fail2(k, a, e09.error); }
  let e10 = sym_or(k, "FlushFileBuffers");
  if !e10.is_ok { return load_fail2(k, a, e10.error); }
  let e11 = sym_or(k, "GetLastError");
  if !e11.is_ok { return load_fail2(k, a, e11.error); }
  let e12 = sym_or(a, "RegOpenKeyExA");
  if !e12.is_ok { return load_fail2(k, a, e12.error); }
  let e13 = sym_or(a, "RegEnumValueA");
  if !e13.is_ok { return load_fail2(k, a, e13.error); }
  let e14 = sym_or(a, "RegCloseKey");
  if !e14.is_ok { return load_fail2(k, a, e14.error); }
  return Ok(SerialLibrary{
    kernel: k;
    registry: a;
    kernel_name: kname;
    registry_name: "advapi32.dll";
    p_create_file_a: e01.value;
    p_close_handle: e02.value;
    p_read_file: e03.value;
    p_write_file: e04.value;
    p_get_comm_state: e05.value;
    p_set_comm_state: e06.value;
    p_get_comm_timeouts: e07.value;
    p_set_comm_timeouts: e08.value;
    p_purge_comm: e09.value;
    p_flush_file_buffers: e10.value;
    p_get_last_error: e11.value;
    p_reg_open_key_ex_a: e12.value;
    p_reg_enum_value_a: e13.value;
    p_reg_close_key: e14.value;
  });
}

/// Load an explicitly named kernel library plus advapi32.dll (the bogus
/// name exercises the ABSENT/SKIP classification deterministically on
/// any host).
/// Complexity: O(entry points).
pub fn serial_load_named(kernel_soname: Str) -> Result[SerialLibrary, SerialError]
  requires: true
{
  let h = dl.dl_open(kernel_soname);
  if !h.is_ok {
    // Not this candidate: report ABSENT so the caller can SKIP.
    return Err(SerialError{ kind: SERIAL_LOAD_ABSENT; code: 0; message: h.error });
  }
  let kh: Int = h.value;
  let a = dl.dl_open("advapi32.dll");
  if !a.is_ok {
    return load_fail(kh, "no advapi32.dll for registry enumeration: " + a.error);
  }
  let ah: Int = a.value;
  return entry_points(kh, ah, kernel_soname);
}

/// Load the Win32 serial backend (kernel32.dll + advapi32.dll).
/// Complexity: O(entry points).
pub fn serial_load() -> Result[SerialLibrary, SerialError]
  requires: true
{
  let r = serial_load_named("kernel32.dll");
  if !r.is_ok {
    if r.error.kind == SERIAL_LOAD_ABSENT {
      return Err(SerialError{
        kind: SERIAL_LOAD_ABSENT;
        code: 0;
        message: "serial: no Win32 serial backend on this OS (kernel32.dll absent)";
      });
    }
    return Err(r.error);
  }
  return Ok(r.value);
}

/// Release the backend handles (advapi32 first, then kernel32).
/// Complexity: O(1).
pub fn serial_unload(lib: &SerialLibrary) -> Result[Unit, Str]
  requires: lib.kernel != 0
  requires: lib.registry != 0
{
  let rc2 = dl.dl_close(lib.registry);
  let rc1 = dl.dl_close(lib.kernel);
  if !rc2.is_ok { return Err(rc2.error); }
  if !rc1.is_ok { return Err(rc1.error); }
  return Ok(());
}

/// Backend identity: API tag, library names, resolved entry-point count.
/// Complexity: O(1).
pub fn serial_probe(lib: &SerialLibrary) -> SerialBackendInfo
  requires: lib.kernel != 0
  requires: lib.registry != 0
{
  return SerialBackendInfo{
    api: SERIAL_API_WIN32;
    kernel: lib.kernel_name;
    registry: lib.registry_name;
    entry_points: 14;
  };
}

// =========================================================================
// Port enumeration (registry SERIALCOMM; absent key = no ports)
// =========================================================================

/// Enumerate present serial ports via HKLM\HARDWARE\DEVICEMAP\SERIALCOMM.
/// An absent key is the canonical "no serial ports at all" state
/// (cross-checked against libserialport list_ports) and returns an empty
/// list, not an error.  Value data carries the COM name.
/// Complexity: O(values).
pub fn serial_ports(lib: &SerialLibrary) -> Result[Vec[SerialPortInfo], SerialError]
  requires: lib.registry != 0
{
  var out: Vec[SerialPortInfo] = Vec[SerialPortInfo].new();
  var key_slot: Vec[UInt8] = Vec[UInt8].with_len(8);
  var rc: Int = 0;
  unsafe {
    let f = lib.p_reg_open_key_ex_a as fn(Int, *UInt8, UInt32, UInt32, *UInt8) -> UInt32;
    let sub = "HARDWARE\\DEVICEMAP\\SERIALCOMM";
    rc = f(SERIAL_HKEY_LOCAL_MACHINE, sub as *UInt8, 0, SERIAL_KEY_READ as UInt32, key_slot.as_mut_ptr()) as Int;
  }
  if rc == WIN32_ERROR_FILE_NOT_FOUND {
    return Ok(out);  // no SERIALCOMM key -> no serial ports present
  }
  if rc != 0 {
    return Err(map_win32(rc, "serial_ports: RegOpenKeyExA SERIALCOMM"));
  }
  var key: Int = 0;
  unsafe { key = ffi.ptr_read_u64_le(key_slot.as_mut_ptr()); }
  if key == 0 {
    return Err(SerialError{ kind: SERIAL_ERR_IO; code: 0; message: "serial_ports: null registry key" });
  }

  var idx: Int = 0;
  var done = false;
  var err_code: Int = 0;
  var err_ctx = "";
  while !done {
    var name_buf: Vec[UInt8] = Vec[UInt8].with_len(SERIAL_REG_NAME_MAX);
    var data_buf: Vec[UInt8] = Vec[UInt8].with_len(SERIAL_REG_DATA_MAX);
    var nlen: Vec[UInt8] = Vec[UInt8].with_len(4);
    var dlen: Vec[UInt8] = Vec[UInt8].with_len(4);
    var typ: Vec[UInt8] = Vec[UInt8].with_len(4);
    unsafe {
      ffi.ptr_write_u32_le(nlen.as_mut_ptr(), SERIAL_REG_NAME_MAX);
      ffi.ptr_write_u32_le(dlen.as_mut_ptr(), SERIAL_REG_DATA_MAX);
    }
    var e: Int = 0;
    unsafe {
      let f = lib.p_reg_enum_value_a as fn(Int, UInt32, *UInt8, *UInt8, Int, *UInt8, *UInt8, *UInt8) -> UInt32;
      e = f(key, idx as UInt32, name_buf.as_mut_ptr(), nlen.as_mut_ptr(), 0, typ.as_mut_ptr(), data_buf.as_mut_ptr(), dlen.as_mut_ptr()) as Int;
    }
    if e == WIN32_ERROR_NO_MORE_ITEMS {
      done = true;
    } elif e == 0 {
      var t = 0;
      unsafe { t = ffi.ptr_read_u32_le(typ.as_mut_ptr()); }
      if t == SERIAL_REG_SZ {
        var name = "";
        unsafe { name = Str::from_c_str(data_buf.as_mut_ptr()); }
        out.push(SerialPortInfo{ name: name; });
      }
      idx = idx + 1;
    } elif e == WIN32_ERROR_MORE_DATA {
      idx = idx + 1;  // oversized value name/data: skip this entry
    } else {
      err_code = e;
      err_ctx = "serial_ports: RegEnumValueA";
      done = true;
    }
    if idx >= SERIAL_REG_MAX_VALUES {
      done = true;
    }
  }

  var close_rc: Int = 0;
  unsafe {
    let f = lib.p_reg_close_key as fn(Int) -> UInt32;
    close_rc = f(key) as Int;
  }
  if err_code != 0 {
    return Err(map_win32(err_code, err_ctx));
  }
  if close_rc != 0 {
    return Err(map_win32(close_rc, "serial_ports: RegCloseKey"));
  }
  return Ok(out);
}

// =========================================================================
// Open / close
// =========================================================================

/// True when the port struct carries a live handle (not 0 and not
/// INVALID_HANDLE_VALUE).
/// Complexity: O(1).
pub fn serial_is_open(port: &SerialPort) -> Bool
  requires: true
{
  if port.handle == 0 { return false; }
  if port.handle == -1 { return false; }
  return true;
}

/// Close a raw handle (internal; used by failure paths).
/// Complexity: O(1).
fn close_raw(lib: &SerialLibrary, handle: Int) -> Int
  requires: handle != 0
{
  var ok: Int = 0;
  var e: Int = 0;
  unsafe {
    let f = lib.p_close_handle as fn(Int) -> UInt32;
    ok = f(handle) as Int;
    if ok == 0 {
      let fg = lib.p_get_last_error as fn() -> UInt32;
      e = fg() as Int;
    }
  }
  if ok == 0 { return e; }
  return 0;
}

/// Open a serial port by name (e.g. "COM3"), exclusive access, with
/// default timeouts applied (read SERIAL_DEFAULT_READ_MS,
/// write SERIAL_DEFAULT_WRITE_MS).  Line configuration is left as the
/// driver presents it; call serial_configure explicitly.
/// Absent device -> typed SERIAL_ERR_NOT_FOUND (the SKIP classification
/// for fleet hosts without that port).
/// Complexity: O(1).
pub fn serial_open(lib: &SerialLibrary, port_name: Str) -> Result[SerialPort, SerialError]
  requires: true
{
  if port_name.len() == 0 {
    return Err(fail_arg("serial_open: empty port name"));
  }
  var path = "\\\\.\\" + port_name;
  var h: Int = 0;
  var e: Int = 0;
  unsafe {
    let f = lib.p_create_file_a as fn(*UInt8, UInt32, UInt32, Int, UInt32, UInt32, Int) -> Int;
    h = f(path as *UInt8, SERIAL_ACCESS_RW as UInt32, 0, 0, SERIAL_OPEN_EXISTING as UInt32, 0, 0);
    if h == -1 {
      let fg = lib.p_get_last_error as fn() -> UInt32;
      e = fg() as Int;
    }
  }
  if h == -1 {
    return Err(map_win32(e, "serial_open: " + port_name));
  }

  let port = SerialPort{ handle: h; name: port_name; };
  let tr = serial_set_timeouts(lib, &port, SerialTimeouts{
    read_ms: SERIAL_DEFAULT_READ_MS;
    write_ms: SERIAL_DEFAULT_WRITE_MS;
  });
  if !tr.is_ok {
    let ce = close_raw(lib, h);
    var msg = tr.error.message;
    if ce != 0 { msg = msg + " (close also failed: win32 " + int_to_str(ce) + ")"; }
    return Err(SerialError{ kind: tr.error.kind; code: tr.error.code; message: msg });
  }
  return Ok(port);
}

/// Close an open port.  The caller's SerialPort keeps the stale handle
/// value; serial_is_open on it reports true until overwritten -- treat
/// the value as consumed.
/// Complexity: O(1).
pub fn serial_close(lib: &SerialLibrary, port: &SerialPort) -> Result[Unit, SerialError]
  requires: true
{
  if !serial_is_open(port) {
    return Err(SerialError{ kind: SERIAL_ERR_INVALID_HANDLE; code: 0; message: "serial_close: port is not open" });
  }
  let e = close_raw(lib, port.handle);
  if e != 0 {
    return Err(map_win32(e, "serial_close: " + port.name));
  }
  return Ok(());
}

// =========================================================================
// Configuration
// =========================================================================

/// Apply a line configuration.  Reads the device's current DCB
/// (GetCommState), patches the managed fields, writes it back
/// (SetCommState) -- unmanaged DCB fields keep their driver values.
/// Complexity: O(1).
pub fn serial_configure(lib: &SerialLibrary, port: &SerialPort, cfg: &SerialConfig) -> Result[Unit, SerialError]
  requires: true
{
  let v = serial_config_validate(cfg);
  if !v.is_ok { return Err(v.error); }
  if !serial_is_open(port) {
    return Err(SerialError{ kind: SERIAL_ERR_INVALID_HANDLE; code: 0; message: "serial_configure: port is not open" });
  }

  var dcb: Vec[UInt8] = Vec[UInt8].with_len(SERIAL_DCB_SLOT);
  var ok: Int = 0;
  var e: Int = 0;
  unsafe {
    ffi.ptr_write_u32_le(dcb.as_mut_ptr(), SERIAL_DCB_LENGTH);
    let f = lib.p_get_comm_state as fn(Int, *UInt8) -> UInt32;
    ok = f(port.handle, dcb.as_mut_ptr()) as Int;
    if ok == 0 {
      let fg = lib.p_get_last_error as fn() -> UInt32;
      e = fg() as Int;
    }
  }
  if ok == 0 {
    return Err(map_win32(e, "serial_configure: GetCommState " + port.name));
  }
  let pr = serial_dcb_patch(cfg, &mut dcb);
  if !pr.is_ok { return Err(pr.error); }
  var ok2: Int = 0;
  var e2: Int = 0;
  unsafe {
    let f = lib.p_set_comm_state as fn(Int, *UInt8) -> UInt32;
    ok2 = f(port.handle, dcb.as_mut_ptr()) as Int;
    if ok2 == 0 {
      let fg = lib.p_get_last_error as fn() -> UInt32;
      e2 = fg() as Int;
    }
  }
  if ok2 == 0 {
    return Err(map_win32(e2, "serial_configure: SetCommState " + port.name));
  }
  return Ok(());
}

/// Read the current line configuration (GetCommState + decode).
/// Complexity: O(1).
pub fn serial_get_config(lib: &SerialLibrary, port: &SerialPort) -> Result[SerialConfig, SerialError]
  requires: true
{
  if !serial_is_open(port) {
    return Err(SerialError{ kind: SERIAL_ERR_INVALID_HANDLE; code: 0; message: "serial_get_config: port is not open" });
  }
  var dcb: Vec[UInt8] = Vec[UInt8].with_len(SERIAL_DCB_SLOT);
  var ok: Int = 0;
  var e: Int = 0;
  unsafe {
    ffi.ptr_write_u32_le(dcb.as_mut_ptr(), SERIAL_DCB_LENGTH);
    let f = lib.p_get_comm_state as fn(Int, *UInt8) -> UInt32;
    ok = f(port.handle, dcb.as_mut_ptr()) as Int;
    if ok == 0 {
      let fg = lib.p_get_last_error as fn() -> UInt32;
      e = fg() as Int;
    }
  }
  if ok == 0 {
    return Err(map_win32(e, "serial_get_config: GetCommState " + port.name));
  }
  return serial_dcb_decode(&dcb);
}

/// Set read/write timeouts (SetCommTimeouts; see serial_timeouts_encode
/// for the exact Windows semantics of read_ms/write_ms).
/// Complexity: O(1).
pub fn serial_set_timeouts(lib: &SerialLibrary, port: &SerialPort, t: &SerialTimeouts) -> Result[Unit, SerialError]
  requires: true
{
  let enc = serial_timeouts_encode(t);
  if !enc.is_ok { return Err(enc.error); }
  if !serial_is_open(port) {
    return Err(SerialError{ kind: SERIAL_ERR_INVALID_HANDLE; code: 0; message: "serial_set_timeouts: port is not open" });
  }
  var ct: Vec[UInt8] = enc.value;
  var ok: Int = 0;
  var e: Int = 0;
  unsafe {
    let f = lib.p_set_comm_timeouts as fn(Int, *UInt8) -> UInt32;
    ok = f(port.handle, ct.as_mut_ptr()) as Int;
    if ok == 0 {
      let fg = lib.p_get_last_error as fn() -> UInt32;
      e = fg() as Int;
    }
  }
  if ok == 0 {
    return Err(map_win32(e, "serial_set_timeouts: " + port.name));
  }
  return Ok(());
}

/// Read the current timeouts (GetCommTimeouts + decode).
/// Complexity: O(1).
pub fn serial_get_timeouts(lib: &SerialLibrary, port: &SerialPort) -> Result[SerialTimeouts, SerialError]
  requires: true
{
  if !serial_is_open(port) {
    return Err(SerialError{ kind: SERIAL_ERR_INVALID_HANDLE; code: 0; message: "serial_get_timeouts: port is not open" });
  }
  var ct: Vec[UInt8] = Vec[UInt8].with_len(SERIAL_TIMEOUTS_LENGTH);
  var ok: Int = 0;
  var e: Int = 0;
  unsafe {
    let f = lib.p_get_comm_timeouts as fn(Int, *UInt8) -> UInt32;
    ok = f(port.handle, ct.as_mut_ptr()) as Int;
    if ok == 0 {
      let fg = lib.p_get_last_error as fn() -> UInt32;
      e = fg() as Int;
    }
  }
  if ok == 0 {
    return Err(map_win32(e, "serial_get_timeouts: " + port.name));
  }
  return serial_timeouts_decode(&ct);
}

// =========================================================================
// Read / write
// =========================================================================

/// Blocking read with the configured read timeout: returns as soon as at
/// least one byte arrives (interval timeout 0), up to max_bytes.
/// read_ms == 0 (poll mode) returns Ok(empty) immediately when nothing
/// is buffered.  Zero bytes within a positive read timeout -> typed
/// SERIAL_ERR_TIMEOUT.  Device removal -> SERIAL_ERR_DISCONNECTED.
/// Complexity: O(max_bytes).
pub fn serial_read(lib: &SerialLibrary, port: &SerialPort, max_bytes: Int) -> Result[Vec[UInt8], SerialError]
  requires: true
{
  if max_bytes <= 0 {
    return Err(fail_arg("serial_read: max_bytes must be > 0"));
  }
  if max_bytes > 65536 {
    return Err(fail_arg("serial_read: max_bytes must be <= 65536"));
  }
  if !serial_is_open(port) {
    return Err(SerialError{ kind: SERIAL_ERR_INVALID_HANDLE; code: 0; message: "serial_read: port is not open" });
  }
  var buf: Vec[UInt8] = Vec[UInt8].with_len(max_bytes);
  var cnt: Vec[UInt8] = Vec[UInt8].with_len(4);
  var ok: Int = 0;
  var e: Int = 0;
  unsafe {
    let f = lib.p_read_file as fn(Int, *UInt8, UInt32, *UInt8, Int) -> UInt32;
    ok = f(port.handle, buf.as_mut_ptr(), max_bytes as UInt32, cnt.as_mut_ptr(), 0) as Int;
    if ok == 0 {
      let fg = lib.p_get_last_error as fn() -> UInt32;
      e = fg() as Int;
    }
  }
  if ok == 0 {
    if e == WIN32_ERROR_TIMEOUT {
      return Err(SerialError{
        kind: SERIAL_ERR_TIMEOUT;
        code: e;
        message: "serial_read: no data within read timeout (" + port.name + ")";
      });
    }
    return Err(map_win32(e, "serial_read: " + port.name));
  }
  var n: Int = 0;
  unsafe { n = ffi.ptr_read_u32_le(cnt.as_mut_ptr()); }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    if i < buf.len() {
      out.push(buf[i]);
    }
    i = i + 1;
  }
  return Ok(out);
}

/// Write payload bytes (WriteFile with the configured write timeout).
/// Returns the byte count accepted (partial writes are reported as-is;
/// callers needing all-bytes semantics should loop).  Device removal ->
/// SERIAL_ERR_DISCONNECTED; timeout -> SERIAL_ERR_TIMEOUT.
/// Complexity: O(len).
pub fn serial_write(lib: &SerialLibrary, port: &SerialPort, bytes: &Vec[UInt8]) -> Result[Int, SerialError]
  requires: true
{
  let n = bytes.len();
  if n > 65536 {
    return Err(fail_arg("serial_write: payload must be <= 65536 bytes"));
  }
  if n == 0 { return Ok(0); }
  if !serial_is_open(port) {
    return Err(SerialError{ kind: SERIAL_ERR_INVALID_HANDLE; code: 0; message: "serial_write: port is not open" });
  }
  var cnt: Vec[UInt8] = Vec[UInt8].with_len(4);
  var ok: Int = 0;
  var e: Int = 0;
  unsafe {
    let base = &bytes[0] as *UInt8;
    let f = lib.p_write_file as fn(Int, *UInt8, UInt32, *UInt8, Int) -> UInt32;
    ok = f(port.handle, base, n as UInt32, cnt.as_mut_ptr(), 0) as Int;
    if ok == 0 {
      let fg = lib.p_get_last_error as fn() -> UInt32;
      e = fg() as Int;
    }
  }
  if ok == 0 {
    if e == WIN32_ERROR_TIMEOUT {
      return Err(SerialError{
        kind: SERIAL_ERR_TIMEOUT;
        code: e;
        message: "serial_write: drain ran out of write timeout (" + port.name + ")";
      });
    }
    return Err(map_win32(e, "serial_write: " + port.name));
  }
  var written: Int = 0;
  unsafe { written = ffi.ptr_read_u32_le(cnt.as_mut_ptr()); }
  return Ok(written);
}

// =========================================================================
// Flush / drain
// =========================================================================

/// Discard input and/or output buffers (PurgeComm RXCLEAR/TXCLEAR; the
/// same mapping the libserialport reference uses for SP_BUF_*).
/// Complexity: O(1).
pub fn serial_flush(lib: &SerialLibrary, port: &SerialPort, flags: Int) -> Result[Unit, SerialError]
  requires: true
{
  var purge = 0;
  if flags == SERIAL_FLUSH_INPUT {
    purge = SERIAL_PURGE_RXCLEAR;
  } elif flags == SERIAL_FLUSH_OUTPUT {
    purge = SERIAL_PURGE_TXCLEAR;
  } elif flags == SERIAL_FLUSH_BOTH {
    purge = SERIAL_PURGE_RXCLEAR + SERIAL_PURGE_TXCLEAR;
  } else {
    return Err(fail_arg("serial_flush: flags must be 1 (input), 2 (output) or 3 (both)"));
  }
  if !serial_is_open(port) {
    return Err(SerialError{ kind: SERIAL_ERR_INVALID_HANDLE; code: 0; message: "serial_flush: port is not open" });
  }
  var ok: Int = 0;
  var e: Int = 0;
  unsafe {
    let f = lib.p_purge_comm as fn(Int, UInt32) -> UInt32;
    ok = f(port.handle, purge as UInt32) as Int;
    if ok == 0 {
      let fg = lib.p_get_last_error as fn() -> UInt32;
      e = fg() as Int;
    }
  }
  if ok == 0 {
    return Err(map_win32(e, "serial_flush: " + port.name));
  }
  return Ok(());
}

/// Block until the transmit queue is empty (FlushFileBuffers).
/// Complexity: O(1) + queue drain wait.
pub fn serial_drain(lib: &SerialLibrary, port: &SerialPort) -> Result[Unit, SerialError]
  requires: true
{
  if !serial_is_open(port) {
    return Err(SerialError{ kind: SERIAL_ERR_INVALID_HANDLE; code: 0; message: "serial_drain: port is not open" });
  }
  var ok: Int = 0;
  var e: Int = 0;
  unsafe {
    let f = lib.p_flush_file_buffers as fn(Int) -> UInt32;
    ok = f(port.handle) as Int;
    if ok == 0 {
      let fg = lib.p_get_last_error as fn() -> UInt32;
      e = fg() as Int;
    }
  }
  if ok == 0 {
    return Err(map_win32(e, "serial_drain: " + port.name));
  }
  return Ok(());
}
