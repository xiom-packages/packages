// XIOM -- xiom.modbus: Modbus RTU/TCP frame codec (PDU, RTU CRC, MBAP)
// Port task: greenfield pure-XIOM port (no FFI) of a Modbus frame codec for
// the documented subset: generic PDU encode/decode, RTU framing with
// CRC-16/Modbus (poly 0xA001 reflected, init 0xFFFF) plus CRC validation,
// TCP framing with the 7-byte MBAP header plus length-consistency
// validation, function 03 and 06 request/response codecs, and the exception
// response codec (function | 0x80 plus exception code 1..4).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Wire layouts (full tables in SPEC.md):
//   PDU       function[1] + data[0..252]                    1..253 bytes
//   RTU ADU   address[1] + PDU + crc[2]                     4..256 bytes
//             crc is CRC-16/Modbus over address+PDU and is transmitted
//             low byte first; address is the slave address 1..247
//   TCP ADU   transaction[2] + protocol[2]=0 + length[2] +
//             unit[1] + PDU                                8..260 bytes
//             MBAP header is 7 bytes; length counts the unit id byte plus
//             the PDU, so length = 1 + pdu.len() and must equal the number
//             of bytes after the length field
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no self methods, no lambdas, no Vec[fn] dispatch;
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (_ok_*/_err_*), because constructing Results directly inside other
//     functions miscompiles;
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic; UInt8
//     values are never compared against Int constants >= 128 without
//     widening;
//   * `&struct.field` is never passed as a `&Vec[UInt8]` parameter (that
//     yields an empty vector in v0.61.3): the field is bound to a typed
//     local first, as in `let d: Vec[UInt8] = p.data;`;
//   * Vec element reads are bound to typed locals (`let x: Int = v[i]`)
//     before use; no Str value is compared in this module, so BUG 17
//     (`==` on a Str read from a Vec) is unreachable.

module xiom.modbus

/// Generic Modbus PDU: the function code and its function-specific data
/// bytes. `function` is 0..255 as carried on the wire; `data` is at most
/// 252 bytes so the encoded PDU stays within the 253-byte Modbus limit.
/// Constructing a value directly is allowed; pdu_encode validates it.
pub type ModbusPdu = {
  function: Int;
  data: Vec[UInt8];
}

/// Decoded RTU ADU: the slave address (1..247) and the carried PDU. The
/// CRC is validated during decoding and is not retained.
pub type ModbusRtuFrame = {
  address: Int;
  pdu: ModbusPdu;
}

/// Decoded TCP ADU: the MBAP transaction identifier (0..65535), the unit
/// identifier (0..255) and the carried PDU. The protocol identifier is
/// validated to be 0 during decoding and is not retained.
pub type ModbusTcpFrame = {
  transaction_id: Int;
  unit_id: Int;
  pdu: ModbusPdu;
}

/// Function 03 (read holding registers) request fields. `start_address` is
/// the first register address (0..65535) and `quantity` the number of
/// registers to read (1..125).
pub type ReadHoldingRegistersRequest = {
  start_address: Int;
  quantity: Int;
}

/// Function 06 (write single register) fields: the target register address
/// (0..65535) and the value to write (0..65535). The response echoes the
/// request, so the same shape serves both directions.
pub type WriteSingleRegister = {
  address: Int;
  value: Int;
}

/// Decoded exception response: `function` is the base function code the
/// server rejected (the wire function minus 0x80, e.g. 3 for 0x83) and
/// `code` is the exception code 1..4.
pub type ModbusException = {
  function: Int;
  code: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[ModbusPdu, Str].
fn _ok_pdu(v: ModbusPdu) -> Result[ModbusPdu, Str] {
  return Ok(v);
}

// Err(m) for Result[ModbusPdu, Str].
fn _err_pdu(m: Str) -> Result[ModbusPdu, Str] {
  return Err(m);
}

// Ok(v) for Result[ModbusRtuFrame, Str].
fn _ok_rtu(v: ModbusRtuFrame) -> Result[ModbusRtuFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[ModbusRtuFrame, Str].
fn _err_rtu(m: Str) -> Result[ModbusRtuFrame, Str] {
  return Err(m);
}

// Ok(v) for Result[ModbusTcpFrame, Str].
fn _ok_tcp(v: ModbusTcpFrame) -> Result[ModbusTcpFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[ModbusTcpFrame, Str].
fn _err_tcp(m: Str) -> Result[ModbusTcpFrame, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Int], Str].
fn _ok_regs(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_regs(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[ReadHoldingRegistersRequest, Str].
fn _ok_read(v: ReadHoldingRegistersRequest) -> Result[ReadHoldingRegistersRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[ReadHoldingRegistersRequest, Str].
fn _err_read(m: Str) -> Result[ReadHoldingRegistersRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[WriteSingleRegister, Str].
fn _ok_write(v: WriteSingleRegister) -> Result[WriteSingleRegister, Str] {
  return Ok(v);
}

// Err(m) for Result[WriteSingleRegister, Str].
fn _err_write(m: Str) -> Result[WriteSingleRegister, Str] {
  return Err(m);
}

// Ok(v) for Result[ModbusException, Str].
fn _ok_exc(v: ModbusException) -> Result[ModbusException, Str] {
  return Ok(v);
}

// Err(m) for Result[ModbusException, Str].
fn _err_exc(m: Str) -> Result[ModbusException, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Copy of data[from, to) as a fresh vector; callers guarantee
// 0 <= from <= to <= data.len().
fn _slice(data: &Vec[UInt8], from: Int, to: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = from;
  while i < to {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// Unsigned big-endian 16-bit value of data[pos] and data[pos+1]; the
// caller guarantees both bytes are in bounds.
fn _u16be(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Append the 16-bit value `v` (0..65535) to `out` in big-endian order.
fn _push_u16be(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Copy the bytes of `v` onto the end of `out`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// --------------------------------------------------
//  CRC-16/Modbus
// --------------------------------------------------

/// CRC-16/Modbus: reflected polynomial 0xA001 (normal form 0x8005), init
/// 0xFFFF, no output reflection and no final XOR, over the bytes of `data`
/// in order. Returns the checksum as an Int in [0, 65535]; an empty input
/// returns 0xFFFF (the init survives). This is the checksum RTU frames
/// carry over address + PDU. "123456789" = 0x4B37 (19255).
/// Complexity: O(data.len()) time, O(1) space (8 bit-steps per byte).
pub fn modbus_crc16(data: &Vec[UInt8]) -> Int {
  var reg = 65535;
  var i = 0;
  while i < data.len() {
    let b: Int = _byte(data, i);
    reg = reg ^ b;
    var j = 0;
    while j < 8 {
      if (reg & 1) == 1 {
        reg = (reg >> 1) ^ 40961;
      } else {
        reg = reg >> 1;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return reg;
}

// --------------------------------------------------
//  Generic PDU codec
// --------------------------------------------------

/// Function code of the PDU (0..255 as carried on the wire).
/// Complexity: O(1).
pub fn pdu_function(p: &ModbusPdu) -> Int {
  return p.function;
}

/// Number of data bytes in the PDU (0..252 for an encodable PDU).
/// Complexity: O(1).
pub fn pdu_data_len(p: &ModbusPdu) -> Int {
  let d: Vec[UInt8] = p.data;
  return d.len();
}

/// True when the function code has the exception bit set (function >= 128,
/// i.e. the server rejected the original request).
/// Complexity: O(1).
pub fn pdu_is_exception(p: &ModbusPdu) -> Bool {
  return p.function >= 128;
}

/// Encode a PDU: the function code byte followed by the data bytes verbatim.
///
/// Err("modbus: invalid function code") when `function` is outside 0..255;
/// Err("modbus: pdu too long") when `data.len()` exceeds 252 (the 253-byte
/// Modbus PDU limit). Nothing is written on Err.
/// Complexity: O(data.len()).
pub fn pdu_encode(p: &ModbusPdu) -> Result[Vec[UInt8], Str] {
  let f: Int = p.function;
  if f < 0 || f > 255 {
    return _err_bytes("modbus: invalid function code");
  }
  let d: Vec[UInt8] = p.data;
  if d.len() > 252 {
    return _err_bytes("modbus: pdu too long");
  }
  var out = Vec[UInt8].new();
  out.push(f as UInt8);
  _push_bytes(&mut out, &d);
  return _ok_bytes(out);
}

/// Decode a PDU: byte 0 is the function code, bytes 1..len are the data.
///
/// Err("modbus: empty pdu") when `data` has no function code;
/// Err("modbus: pdu too long") when `data` exceeds the 253-byte PDU limit.
/// Complexity: O(data.len()).
pub fn pdu_decode(data: &Vec[UInt8]) -> Result[ModbusPdu, Str] {
  let n = data.len();
  if n == 0 {
    return _err_pdu("modbus: empty pdu");
  }
  if n > 253 {
    return _err_pdu("modbus: pdu too long");
  }
  let f: Int = _byte(data, 0);
  let d = _slice(data, 1, n);
  return _ok_pdu(ModbusPdu{ function: f; data: d; });
}

// --------------------------------------------------
//  Function 03: read holding registers
// --------------------------------------------------

/// Build a function 03 (read holding registers) request PDU. `data` is the
/// 4-byte big-endian payload start_address[2] + quantity[2].
///
/// Err("modbus: invalid register address") when `start_address` is outside
/// 0..65535; Err("modbus: invalid register count") when `quantity` is
/// outside 1..125; Err("modbus: address range overflow") when
/// start_address + quantity exceeds 65536.
/// Complexity: O(1).
pub fn read_holding_registers_request_pdu(start_address: Int, quantity: Int) -> Result[ModbusPdu, Str] {
  if start_address < 0 || start_address > 65535 {
    return _err_pdu("modbus: invalid register address");
  }
  if quantity < 1 || quantity > 125 {
    return _err_pdu("modbus: invalid register count");
  }
  if start_address + quantity > 65536 {
    return _err_pdu("modbus: address range overflow");
  }
  var d = Vec[UInt8].new();
  _push_u16be(&mut d, start_address);
  _push_u16be(&mut d, quantity);
  return _ok_pdu(ModbusPdu{ function: 3; data: d; });
}

/// Decode a function 03 request PDU back into its fields.
///
/// Err("modbus: wrong function") when `function` is not 3;
/// Err("modbus: bad pdu length") when the data is not exactly 4 bytes;
/// Err("modbus: invalid register count") when quantity is outside 1..125;
/// Err("modbus: address range overflow") when start_address + quantity
/// exceeds 65536.
/// Complexity: O(1).
pub fn read_holding_registers_request_from_pdu(p: &ModbusPdu) -> Result[ReadHoldingRegistersRequest, Str] {
  if p.function != 3 {
    return _err_read("modbus: wrong function");
  }
  let d: Vec[UInt8] = p.data;
  if d.len() != 4 {
    return _err_read("modbus: bad pdu length");
  }
  let start: Int = _u16be(&d, 0);
  let quantity: Int = _u16be(&d, 2);
  if quantity < 1 || quantity > 125 {
    return _err_read("modbus: invalid register count");
  }
  if start + quantity > 65536 {
    return _err_read("modbus: address range overflow");
  }
  return _ok_read(ReadHoldingRegistersRequest{ start_address: start; quantity: quantity; });
}

/// Build a function 03 response PDU from register values: byte_count[1]
/// (= 2 * registers.len()) followed by each register big-endian.
///
/// Err("modbus: invalid register count") when the number of registers is
/// outside 1..125; Err("modbus: invalid register value") when any register
/// value is outside 0..65535. Each value is validated before it is written
/// and an Err discards the partially built local PDU.
/// Complexity: O(registers.len()).
pub fn read_holding_registers_response_pdu(registers: &Vec[Int]) -> Result[ModbusPdu, Str] {
  let n = registers.len();
  if n < 1 || n > 125 {
    return _err_pdu("modbus: invalid register count");
  }
  var d = Vec[UInt8].new();
  d.push((n * 2) as UInt8);
  var i = 0;
  while i < n {
    let v: Int = registers[i];
    if v < 0 || v > 65535 {
      return _err_pdu("modbus: invalid register value");
    }
    _push_u16be(&mut d, v);
    i = i + 1;
  }
  return _ok_pdu(ModbusPdu{ function: 3; data: d; });
}

/// Decode a function 03 response PDU into its register values.
///
/// Err("modbus: wrong function") when `function` is not 3;
/// Err("modbus: bad pdu length") when the data is empty;
/// Err("modbus: bad byte count") when byte_count is odd or does not equal
/// the remaining data length;
/// Err("modbus: invalid register count") when byte_count/2 is outside
/// 1..125. Values are returned in wire order, each in 0..65535.
/// Complexity: O(registers).
pub fn read_holding_registers_response_from_pdu(p: &ModbusPdu) -> Result[Vec[Int], Str] {
  if p.function != 3 {
    return _err_regs("modbus: wrong function");
  }
  let d: Vec[UInt8] = p.data;
  let n = d.len();
  if n < 1 {
    return _err_regs("modbus: bad pdu length");
  }
  let byte_count: Int = _byte(&d, 0);
  if byte_count % 2 != 0 || byte_count != n - 1 {
    return _err_regs("modbus: bad byte count");
  }
  let count = byte_count / 2;
  if count < 1 || count > 125 {
    return _err_regs("modbus: invalid register count");
  }
  var out = Vec[Int].new();
  var i = 0;
  while i < count {
    out.push(_u16be(&d, 1 + i * 2));
    i = i + 1;
  }
  return _ok_regs(out);
}

// --------------------------------------------------
//  Function 06: write single register
// --------------------------------------------------

/// Build a function 06 (write single register) request PDU: the 4-byte
/// big-endian payload register_address[2] + register_value[2].
///
/// Err("modbus: invalid register address") when `address` is outside
/// 0..65535; Err("modbus: invalid register value") when `value` is outside
/// 0..65535.
/// Complexity: O(1).
pub fn write_single_register_request_pdu(address: Int, value: Int) -> Result[ModbusPdu, Str] {
  if address < 0 || address > 65535 {
    return _err_pdu("modbus: invalid register address");
  }
  if value < 0 || value > 65535 {
    return _err_pdu("modbus: invalid register value");
  }
  var d = Vec[UInt8].new();
  _push_u16be(&mut d, address);
  _push_u16be(&mut d, value);
  return _ok_pdu(ModbusPdu{ function: 6; data: d; });
}

/// Build a function 06 response PDU. The Modbus response echoes the request
/// byte for byte, so this is the same layout as
/// write_single_register_request_pdu and delegates to it; the separate name
/// documents the direction at the call site.
/// Complexity: O(1).
pub fn write_single_register_response_pdu(address: Int, value: Int) -> Result[ModbusPdu, Str] {
  return write_single_register_request_pdu(address, value);
}

/// Decode a function 06 request PDU back into address and value.
///
/// Err("modbus: wrong function") when `function` is not 6;
/// Err("modbus: bad pdu length") when the data is not exactly 4 bytes.
/// Complexity: O(1).
pub fn write_single_register_request_from_pdu(p: &ModbusPdu) -> Result[WriteSingleRegister, Str] {
  if p.function != 6 {
    return _err_write("modbus: wrong function");
  }
  let d: Vec[UInt8] = p.data;
  if d.len() != 4 {
    return _err_write("modbus: bad pdu length");
  }
  let address: Int = _u16be(&d, 0);
  let value: Int = _u16be(&d, 2);
  return _ok_write(WriteSingleRegister{ address: address; value: value; });
}

/// Decode a function 06 response PDU. The response echoes the request, so
/// this is the same layout as write_single_register_request_from_pdu and
/// delegates to it.
/// Complexity: O(1).
pub fn write_single_register_response_from_pdu(p: &ModbusPdu) -> Result[WriteSingleRegister, Str] {
  return write_single_register_request_from_pdu(p);
}

// --------------------------------------------------
//  Exception responses
// --------------------------------------------------

/// Build an exception response PDU: the base function code with the
/// exception bit set (base + 0x80) followed by the exception code.
///
/// Err("modbus: invalid function code") when `base_function` is outside
/// 1..127; Err("modbus: invalid exception code") when `code` is outside
/// 1..4.
/// Complexity: O(1).
pub fn exception_pdu(base_function: Int, code: Int) -> Result[ModbusPdu, Str] {
  if base_function < 1 || base_function > 127 {
    return _err_pdu("modbus: invalid function code");
  }
  if code < 1 || code > 4 {
    return _err_pdu("modbus: invalid exception code");
  }
  var d = Vec[UInt8].new();
  d.push(code as UInt8);
  return _ok_pdu(ModbusPdu{ function: base_function + 128; data: d; });
}

/// Decode an exception response PDU. `function` of the result is the base
/// function code (wire function minus 0x80) and `code` the exception code.
///
/// Err("modbus: wrong function") when the exception bit is not set;
/// Err("modbus: bad pdu length") when the data is not exactly 1 byte;
/// Err("modbus: invalid exception code") when the code is outside 1..4.
/// Complexity: O(1).
pub fn exception_from_pdu(p: &ModbusPdu) -> Result[ModbusException, Str] {
  if p.function < 128 {
    return _err_exc("modbus: wrong function");
  }
  let d: Vec[UInt8] = p.data;
  if d.len() != 1 {
    return _err_exc("modbus: bad pdu length");
  }
  let code: Int = _byte(&d, 0);
  if code < 1 || code > 4 {
    return _err_exc("modbus: invalid exception code");
  }
  return _ok_exc(ModbusException{ function: p.function - 128; code: code; });
}

/// Human-readable name of an exception code: 1 = "illegal function",
/// 2 = "illegal data address", 3 = "illegal data value",
/// 4 = "server device failure"; any other value is "unknown exception".
/// Complexity: O(1).
pub fn exception_name(code: Int) -> Str {
  if code == 1 {
    return "illegal function";
  }
  if code == 2 {
    return "illegal data address";
  }
  if code == 3 {
    return "illegal data value";
  }
  if code == 4 {
    return "server device failure";
  }
  return "unknown exception";
}

// --------------------------------------------------
//  RTU framing
// --------------------------------------------------

/// Encode an RTU ADU: address[1] + PDU + CRC[2], with the CRC-16/Modbus of
/// address+PDU appended low byte first.
///
/// Err("modbus: invalid rtu address") when `address` is outside 1..247;
/// pdu_encode errors are propagated unchanged (the PDU is validated before
/// any byte is written). A maximum PDU (253 bytes) yields the maximum RTU
/// frame of 256 bytes. Complexity: O(PDU length).
pub fn rtu_encode(address: Int, p: &ModbusPdu) -> Result[Vec[UInt8], Str] {
  if address < 1 || address > 247 {
    return _err_bytes("modbus: invalid rtu address");
  }
  let pe = pdu_encode(p);
  if !pe.is_ok {
    return _err_bytes(pe.error);
  }
  let pdu_bytes: Vec[UInt8] = pe.value;
  var body = Vec[UInt8].new();
  body.push(address as UInt8);
  _push_bytes(&mut body, &pdu_bytes);
  let crc = modbus_crc16(&body);
  body.push((crc % 256) as UInt8);
  body.push(((crc / 256) % 256) as UInt8);
  return _ok_bytes(body);
}

/// Decode and validate an RTU ADU.
///
/// The last two bytes are the CRC, low byte first, over everything before
/// them.
/// Err("modbus: truncated rtu frame") when `data` is shorter than the
/// 4-byte minimum (address + function + CRC);
/// Err("modbus: rtu frame too long") when `data` exceeds the 256-byte RTU
/// limit; Err("modbus: bad crc") when the received CRC does not match;
/// Err("modbus: invalid rtu address") when the address is outside 1..247;
/// pdu_decode errors are propagated unchanged (a frame of at least 4 bytes
/// always leaves a 1..253-byte PDU).
/// Complexity: O(data.len()).
pub fn rtu_decode(data: &Vec[UInt8]) -> Result[ModbusRtuFrame, Str] {
  let n = data.len();
  if n < 4 {
    return _err_rtu("modbus: truncated rtu frame");
  }
  if n > 256 {
    return _err_rtu("modbus: rtu frame too long");
  }
  let body = _slice(data, 0, n - 2);
  let crc_calc = modbus_crc16(&body);
  let crc_wire: Int = _byte(data, n - 2) + _byte(data, n - 1) * 256;
  if crc_calc != crc_wire {
    return _err_rtu("modbus: bad crc");
  }
  let address: Int = _byte(data, 0);
  if address < 1 || address > 247 {
    return _err_rtu("modbus: invalid rtu address");
  }
  let pdu_bytes = _slice(data, 1, n - 2);
  let pr = pdu_decode(&pdu_bytes);
  if !pr.is_ok {
    return _err_rtu(pr.error);
  }
  let pdu: ModbusPdu = pr.value;
  return _ok_rtu(ModbusRtuFrame{ address: address; pdu: pdu; });
}

// --------------------------------------------------
//  TCP framing (MBAP)
// --------------------------------------------------

/// Encode a TCP ADU: the 7-byte MBAP header (transaction[2], protocol[2]=0,
/// length[2], unit[1]) followed by the PDU. length is 1 + PDU length: the
/// unit identifier byte plus the PDU.
///
/// Err("modbus: invalid transaction id") when `transaction_id` is outside
/// 0..65535; Err("modbus: invalid unit id") when `unit_id` is outside
/// 0..255; pdu_encode errors are propagated unchanged.
/// Complexity: O(PDU length).
pub fn tcp_encode(transaction_id: Int, unit_id: Int, p: &ModbusPdu) -> Result[Vec[UInt8], Str] {
  if transaction_id < 0 || transaction_id > 65535 {
    return _err_bytes("modbus: invalid transaction id");
  }
  if unit_id < 0 || unit_id > 255 {
    return _err_bytes("modbus: invalid unit id");
  }
  let pe = pdu_encode(p);
  if !pe.is_ok {
    return _err_bytes(pe.error);
  }
  let pdu_bytes: Vec[UInt8] = pe.value;
  var out = Vec[UInt8].new();
  _push_u16be(&mut out, transaction_id);
  _push_u16be(&mut out, 0);
  _push_u16be(&mut out, 1 + pdu_bytes.len());
  out.push(unit_id as UInt8);
  _push_bytes(&mut out, &pdu_bytes);
  return _ok_bytes(out);
}

/// Decode and validate a TCP ADU.
///
/// Err("modbus: truncated mbap header") when `data` is shorter than the
/// 7-byte MBAP header plus one function byte;
/// Err("modbus: bad protocol id") when the protocol identifier is not 0;
/// Err("modbus: length mismatch") when the length field does not equal the
/// number of bytes after it (unit id + PDU);
/// pdu_decode errors are propagated unchanged. The transaction and unit
/// identifiers are read as unsigned. Complexity: O(data.len()).
pub fn tcp_decode(data: &Vec<UInt8>) -> Result[ModbusTcpFrame, Str] {
  let n = data.len();
  if n < 8 {
    return _err_tcp("modbus: truncated mbap header");
  }
  if _u16be(data, 2) != 0 {
    return _err_tcp("modbus: bad protocol id");
  }
  let length: Int = _u16be(data, 4);
  if length != n - 6 {
    return _err_tcp("modbus: length mismatch");
  }
  let transaction_id: Int = _u16be(data, 0);
  let unit_id: Int = _byte(data, 6);
  let pdu_bytes = _slice(data, 7, n);
  let pr = pdu_decode(&pdu_bytes);
  if !pr.is_ok {
    return _err_tcp(pr.error);
  }
  let pdu: ModbusPdu = pr.value;
  return _ok_tcp(ModbusTcpFrame{ transaction_id: transaction_id; unit_id: unit_id; pdu: pdu; });
}
