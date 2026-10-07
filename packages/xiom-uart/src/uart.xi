// XIOM -- xiom.uart: UART line codec (bit-level framing, parity, baud math)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) codec for one UART byte at the bit level: line
// configuration, frame bit layout, one-byte encode/decode against a bit
// stream with idle-high framing, framing-error detection, baud divisor math
// with fractional-error computation and oversampling helpers.
//
// Bit stream model: a bit stream is a Vec[UInt8] whose elements are one bit
// time each and hold the value 0 or 1 (the line level). The idle line is
// high (1). One frame is:
//
//   bit 0          start bit, always 0
//   bits 1..d      data, least significant bit first (d = data_bits, 5..9)
//   bit 1+d        parity bit (unless parity is none: even, odd, mark, space)
//   final n bits   stop bits, always 1, where n = ceil(stop_half / 2)
//
// Stop bits are configured as half bit times (`stop_half`): 2 = 1.0,
// 3 = 1.5, 4 = 2.0. A bit stream element is a whole bit time, so 1.5 stop
// bits occupies one and a half bit times on the wire and two whole mark
// elements in the stream (a half element cannot be represented); the exact
// duration in half bit times is reported by uart_frame_halves.
//
// Parameter codes:
//   parity  0 none, 1 even, 2 odd, 3 mark, 4 space
//   stop    stop_half: 2 = 1.0, 3 = 1.5, 4 = 2.0 stop bits
//   flow    0 none, 1 rts_cts, 2 xon_xoff
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no methods, no lambdas, no Vec[StructType].
//   * Ok/Err construction is confined to the tiny leaf helpers `_ok_*` /
//     `_err_*` below (constructing Results directly inside other functions
//     miscompiles).
//   * every byte read from a Vec[UInt8] is widened with `(x as Int) & 0xFF`
//     before entering Int arithmetic, and every element read is bound to a
//     typed local first.
//   * no Str value is compared in this module, so BUG 17 (`==` on a Str
//     read from a Vec) is unreachable.
//   * `&struct.field` is never passed as a `&Vec[...]` parameter (it lowers
//     to an empty vector); a field is bound to a local first.
//   * all arithmetic is on values far below 2^31; the only bitwise
//     operation is the documented `& 0xFF` widening mask.

module xiom.uart

/// UART line configuration.
///
/// Fields: `baud` -- symbol rate in bits per second, positive; `data_bits`
/// -- payload bits per frame, 5..9; `parity` -- 0 none, 1 even, 2 odd,
/// 3 mark, 4 space; `stop_half` -- stop bits in half bit times, 2 = 1.0,
/// 3 = 1.5, 4 = 2.0; `flow` -- 0 none, 1 rts_cts, 2 xon_xoff.
pub type UartConfig = {
  baud: Int;
  data_bits: Int;
  parity: Int;
  stop_half: Int;
  flow: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
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
fn _ok_intvec(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_intvec(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[UartConfig, Str].
fn _ok_cfg(v: UartConfig) -> Result[UartConfig, Str] {
  return Ok(v);
}

// Err(m) for Result[UartConfig, Str].
fn _err_cfg(m: Str) -> Result[UartConfig, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal arithmetic
// --------------------------------------------------

// 2^k for k >= 0 (1 for k <= 0), by doubling; no shifts.
fn _pow2(k: Int) -> Int {
  var w = 1;
  var i = 0;
  while i < k {
    w = w * 2;
    i = i + 1;
  }
  return w;
}

// Mask of the low `nbits` bits (2^nbits - 1; 0 for nbits <= 0).
fn _mask(nbits: Int) -> Int {
  return _pow2(nbits) - 1;
}

// Number of 1 bits in the low `nbits` of `v`, by repeated division
// (arithmetic only; `v` is non-negative in every call).
fn _popcount_low(v: Int, nbits: Int) -> Int {
  var q = v;
  var n = 0;
  var i = 0;
  while i < nbits {
    if q % 2 != 0 {
      n = n + 1;
    }
    q = q / 2;
    i = i + 1;
  }
  return n;
}

// Shared input check for the baud functions: "" when the clock, baud and
// oversampling factor are usable, otherwise the first error string.
fn _rate_error(clock_hz: Int, baud: Int, oversample: Int) -> Str {
  if clock_hz <= 0 {
    return "uart: invalid clock";
  }
  if baud <= 0 {
    return "uart: invalid baud";
  }
  if !uart_oversample_ok(oversample) {
    return "uart: invalid oversampling";
  }
  return "";
}

// Append one idle-high bit time to `out`.
fn _push_idle(out: &mut Vec[UInt8]) {
  out.push(1 as UInt8);
}

// --------------------------------------------------
//  Configuration codes and names
// --------------------------------------------------

/// Parity code: none. Complexity: O(1).
pub fn uart_parity_none() -> Int
  ensures: result == 0;
{
  return 0;
}

/// Parity code: even. Complexity: O(1).
pub fn uart_parity_even() -> Int
  ensures: result == 1;
{
  return 1;
}

/// Parity code: odd. Complexity: O(1).
pub fn uart_parity_odd() -> Int
  ensures: result == 2;
{
  return 2;
}

/// Parity code: mark (the parity bit is always 1). Complexity: O(1).
pub fn uart_parity_mark() -> Int
  ensures: result == 3;
{
  return 3;
}

/// Parity code: space (the parity bit is always 0). Complexity: O(1).
pub fn uart_parity_space() -> Int
  ensures: result == 4;
{
  return 4;
}

/// Flow-control code: none. Complexity: O(1).
pub fn uart_flow_none() -> Int
  ensures: result == 0;
{
  return 0;
}

/// Flow-control code: RTS/CTS hardware handshake. Complexity: O(1).
pub fn uart_flow_rts_cts() -> Int
  ensures: result == 1;
{
  return 1;
}

/// Flow-control code: XON/XOFF software handshake. Complexity: O(1).
pub fn uart_flow_xon_xoff() -> Int
  ensures: result == 2;
{
  return 2;
}

/// Module version string. Complexity: O(1).
pub fn uart_version() -> Str
  ensures: result.len() == 5;
{
  return "0.1.3";
}

/// Human-readable parity name: "none", "even", "odd", "mark", "space";
/// any other code is "invalid". Complexity: O(1).
pub fn uart_parity_name(parity: Int) -> Str
  ensures: parity < 0 || parity > 4 => result.len() == 7;
  ensures: parity >= 0 && parity <= 4 => result.len() >= 3 && result.len() <= 5;
{
  if parity == 0 {
    return "none";
  }
  if parity == 1 {
    return "even";
  }
  if parity == 2 {
    return "odd";
  }
  if parity == 3 {
    return "mark";
  }
  if parity == 4 {
    return "space";
  }
  return "invalid";
}

/// Human-readable flow-control name: "none", "rts_cts", "xon_xoff"; any
/// other code is "invalid". Complexity: O(1).
pub fn uart_flow_name(flow: Int) -> Str
  ensures: flow < 0 || flow > 2 => result.len() == 7;
  ensures: flow >= 0 && flow <= 2 => result.len() >= 4 && result.len() <= 8;
{
  if flow == 0 {
    return "none";
  }
  if flow == 1 {
    return "rts_cts";
  }
  if flow == 2 {
    return "xon_xoff";
  }
  return "invalid";
}

/// Human-readable stop-bit name for a half-bit-time count: "1", "1.5",
/// "2"; any other value is "invalid". Complexity: O(1).
pub fn uart_stop_name(stop_half: Int) -> Str
  ensures: stop_half < 2 || stop_half > 4 => result.len() == 7;
  ensures: stop_half >= 2 && stop_half <= 4 => result.len() >= 1 && result.len() <= 3;
{
  if stop_half == 2 {
    return "1";
  }
  if stop_half == 3 {
    return "1.5";
  }
  if stop_half == 4 {
    return "2";
  }
  return "invalid";
}

// --------------------------------------------------
//  Configuration
// --------------------------------------------------

/// The default line: 115200 baud, 8 data bits, no parity, 1 stop bit,
/// no flow control (115200 8N1).
/// Complexity: O(1).
pub fn uart_default() -> UartConfig
  ensures: result.baud == 115200;
  ensures: result.data_bits == 8;
  ensures: result.parity == 0 && result.stop_half == 2 && result.flow == 0;
{
  return UartConfig{ baud: 115200; data_bits: 8; parity: 0; stop_half: 2; flow: 0; };
}

/// Structural equality: all five configuration fields match.
/// Complexity: O(1).
pub fn uart_config_equal(a: &UartConfig, b: &UartConfig) -> Bool
  ensures: (a.baud == b.baud && a.data_bits == b.data_bits && a.parity == b.parity && a.stop_half == b.stop_half && a.flow == b.flow) => result;
  ensures: result => (a.baud == b.baud && a.data_bits == b.data_bits && a.parity == b.parity && a.stop_half == b.stop_half && a.flow == b.flow);
{
  if a.baud != b.baud {
    return false;
  }
  if a.data_bits != b.data_bits {
    return false;
  }
  if a.parity != b.parity {
    return false;
  }
  if a.stop_half != b.stop_half {
    return false;
  }
  if a.flow != b.flow {
    return false;
  }
  return true;
}

/// Validate every configuration field, in this order: baud positive;
/// data_bits 5..9; parity 0..4; stop_half 2..4; flow 0..2.
///
/// Returns: Ok(()) for a usable configuration.
/// Error case: Err("uart: invalid baud"), Err("uart: invalid data bits"),
/// Err("uart: invalid parity"), Err("uart: invalid stop bits") or
/// Err("uart: invalid flow control"). Complexity: O(1).
pub fn uart_config_ok(c: &UartConfig) -> Result[Unit, Str]
  ensures: result is Ok => c.baud > 0 && c.data_bits >= 5 && c.data_bits <= 9 && c.parity >= 0 && c.parity <= 4;
  ensures: result is Ok => c.stop_half >= 2 && c.stop_half <= 4 && c.flow >= 0 && c.flow <= 2;
  ensures: (c.baud <= 0 || c.data_bits < 5 || c.data_bits > 9 || c.parity < 0 || c.parity > 4 || c.stop_half < 2 || c.stop_half > 4 || c.flow < 0 || c.flow > 2) => result is Err;
{
  let baud: Int = c.baud;
  if baud <= 0 {
    return _err_unit("uart: invalid baud");
  }
  let db: Int = c.data_bits;
  if db < 5 || db > 9 {
    return _err_unit("uart: invalid data bits");
  }
  let p: Int = c.parity;
  if p < 0 || p > 4 {
    return _err_unit("uart: invalid parity");
  }
  let sh: Int = c.stop_half;
  if sh < 2 || sh > 4 {
    return _err_unit("uart: invalid stop bits");
  }
  let f: Int = c.flow;
  if f < 0 || f > 2 {
    return _err_unit("uart: invalid flow control");
  }
  return _ok_unit();
}

/// Build a configuration from the five fields and validate it with
/// uart_config_ok (same error catalog, same order).
/// Complexity: O(1).
pub fn uart_new(baud: Int, data_bits: Int, parity: Int, stop_half: Int, flow: Int) -> Result[UartConfig, Str]
  ensures: result is Ok => baud > 0 && data_bits >= 5 && data_bits <= 9 && parity >= 0 && parity <= 4 && stop_half >= 2 && stop_half <= 4 && flow >= 0 && flow <= 2;
  ensures: baud <= 0 => result is Err;
  ensures: data_bits < 5 || data_bits > 9 => result is Err;
{
  let c = UartConfig{ baud: baud; data_bits: data_bits; parity: parity; stop_half: stop_half; flow: flow; };
  let vr = uart_config_ok(&c);
  if !vr.is_ok {
    return _err_cfg(vr.error);
  }
  return _ok_cfg(c);
}

// --------------------------------------------------
//  Frame geometry
// --------------------------------------------------

/// True when the configuration uses a parity bit (parity != none).
/// Complexity: O(1).
pub fn uart_has_parity(c: &UartConfig) -> Bool
  ensures: result == (c.parity != 0);
{
  return c.parity != 0;
}

/// Whole stop-bit times represented in a bit stream for a half-bit-time
/// count: ceil(stop_half / 2), so 2 -> 1, 3 -> 2, 4 -> 2. A stream element
/// is a whole bit time, so 1.5 stop bits occupies two mark elements; the
/// exact duration is uart_frame_halves. Meaningful for stop_half 2..4.
/// Complexity: O(1).
pub fn uart_stop_bit_times(stop_half: Int) -> Int
  ensures: result == (stop_half + 1) / 2;
{
  return (stop_half + 1) / 2;
}

/// Number of bit-stream elements in one frame: 1 start bit + data_bits +
/// (1 when parity is used) + uart_stop_bit_times(stop_half). For 8N1 this
/// is 10. Meaningful for a valid configuration. Complexity: O(1).
pub fn uart_frame_len(c: &UartConfig) -> Int
  ensures: c.parity == 0 => result == 1 + c.data_bits + uart_stop_bit_times(c.stop_half);
  ensures: c.parity != 0 => result == 2 + c.data_bits + uart_stop_bit_times(c.stop_half);
{
  let db: Int = c.data_bits;
  var n = 1 + db;
  if c.parity != 0 {
    n = n + 1;
  }
  return n + uart_stop_bit_times(c.stop_half);
}

/// Exact frame duration in half bit times: 2 * (start + data + parity) +
/// stop_half, so 8N1 is 20 halves (10 bit times) and 8N1.5 is 21 halves
/// (the 0.5 stop bit cannot be represented in a whole-bit stream but is
/// counted here). Meaningful for a valid configuration. Complexity: O(1).
pub fn uart_frame_halves(c: &UartConfig) -> Int
  ensures: c.parity == 0 => result == 2 + c.data_bits * 2 + c.stop_half;
  ensures: c.parity != 0 => result == 4 + c.data_bits * 2 + c.stop_half;
{
  let db: Int = c.data_bits;
  var n = 2 + db * 2;
  if c.parity != 0 {
    n = n + 2;
  }
  return n + c.stop_half;
}

// --------------------------------------------------
//  Parity
// --------------------------------------------------

/// Parity bit value for `byte` under the parity code `parity`, considering
/// the low `data_bits` bits of `byte` (the caller normally passes a value
/// that already fits in `data_bits`).
///
/// none -> 0, mark -> 1, space -> 0, even -> 1 when the data has an odd
/// number of 1 bits, odd -> the complement of even. Any other parity code
/// behaves like none (0). Complexity: O(data_bits).
pub fn uart_parity_bit(parity: Int, byte: Int, data_bits: Int) -> Int
  ensures: parity == 3 => result == 1;
  ensures: parity != 1 && parity != 2 && parity != 3 => result == 0;
  ensures: (parity == 1 || parity == 2) => result >= 0 && result <= 1;
{
  if parity == 1 || parity == 2 {
    var v = byte;
    if data_bits >= 0 {
      let m = _mask(data_bits) + 1;
      v = v % m;
    }
    let ones = _popcount_low(v, data_bits);
    if parity == 2 {
      return 1 - (ones % 2);
    }
    return ones % 2;
  }
  if parity == 3 {
    return 1;
  }
  return 0;
}

// --------------------------------------------------
//  Byte values
// --------------------------------------------------

/// True when `byte` is a value a 9-data-bit frame can carry: 0..511.
/// Complexity: O(1).
pub fn uart_byte_ok(byte: Int) -> Bool
  ensures: result == (byte >= 0 && byte <= 511);
{
  if byte < 0 {
    return false;
  }
  return byte <= 511;
}

/// True when `byte` fits the configuration's data width: a 9-bit value is
/// accepted only with data_bits == 9, an 8-bit value only up to 8 data
/// bits, and so on. False for out-of-range bytes and for an invalid
/// configuration. Complexity: O(1).
pub fn uart_byte_fits(c: &UartConfig, byte: Int) -> Bool
  ensures: result => byte >= 0 && byte <= 511;
  ensures: (byte < 0 || byte > 511) => !result;
{
  if !uart_byte_ok(byte) {
    return false;
  }
  return byte <= _mask(c.data_bits);
}

// --------------------------------------------------
//  Encode one byte (frame bits only, start bit first)
// --------------------------------------------------

/// Append the frame of one data value to `out`, with idle-high framing
/// represented by the caller (the frame itself starts with the low start
/// bit and ends with the high stop bits).
///
/// The configuration is validated first, then the value: byte < 0 is
/// Err("uart: byte out of range") and a value above 2^data_bits - 1 is
/// Err("uart: byte exceeds data bits"); on Err, `out` is byte-for-byte
/// unchanged (atomic failure).
/// Returns: Ok(()) after appending uart_frame_len(c) elements.
/// Error case: the uart_config_ok catalog, plus the two byte errors.
/// Complexity: O(data_bits).
pub fn uart_encode_byte_into(out: &mut Vec[UInt8], c: &UartConfig, byte: Int) -> Result[Unit, Str]
  ensures: result is Err => out.len() == out.len()@pre;
  ensures: result is Ok => out.len() == out.len()@pre + uart_frame_len(c);
  ensures: byte < 0 => result is Err;
{
  let vr = uart_config_ok(c);
  if !vr.is_ok {
    return _err_unit(vr.error);
  }
  if byte < 0 {
    return _err_unit("uart: byte out of range");
  }
  let db: Int = c.data_bits;
  if byte > _mask(db) {
    return _err_unit("uart: byte exceeds data bits");
  }
  out.push(0 as UInt8);
  var i = 0;
  while i < db {
    let bit = (byte / _pow2(i)) % 2;
    out.push(bit as UInt8);
    i = i + 1;
  }
  let p: Int = c.parity;
  if p != 0 {
    out.push(uart_parity_bit(p, byte, db) as UInt8);
  }
  let st = uart_stop_bit_times(c.stop_half);
  var k = 0;
  while k < st {
    out.push(1 as UInt8);
    k = k + 1;
  }
  return _ok_unit();
}

/// Encode one data value into a fresh frame bit vector (start bit first,
/// then data LSB-first, the parity bit when configured, then the stop
/// bits). Same validation and error catalog as uart_encode_byte_into.
/// Complexity: O(data_bits).
pub fn uart_encode_byte(c: &UartConfig, byte: Int) -> Result[Vec[UInt8], Str]
  ensures: byte < 0 => result is Err;
  ensures: c.baud <= 0 => result is Err;
  ensures: result is Ok => result.value.len() >= 7 && result.value.len() <= 13;
{
  var out = Vec[UInt8].new();
  let ar = uart_encode_byte_into(&mut out, c, byte);
  if !ar.is_ok {
    return _err_bytes(ar.error);
  }
  return _ok_bytes(out);
}

/// Encode a sequence of data values into one bit stream: one leading
/// idle-high bit time, then one frame per value back to back, then one
/// trailing idle-high bit time. Values are validated against the
/// configuration before anything is written; the error catalog is the
/// uart_encode_byte_into one. An empty sequence encodes to two idle bits.
/// Complexity: O(bytes.len() * data_bits).
pub fn uart_encode_stream(c: &UartConfig, bytes: &Vec[Int]) -> Result[Vec[UInt8], Str]
  ensures: c.baud <= 0 => result is Err;
  ensures: result is Ok => result.value.len() >= 2;
  ensures: result is Ok && bytes.len() == 0 => result.value.len() == 2;
{
  let vr = uart_config_ok(c);
  if !vr.is_ok {
    return _err_bytes(vr.error);
  }
  let n = bytes.len();
  var i = 0;
  while i < n {
    let b: Int = bytes[i];
    if b < 0 {
      return _err_bytes("uart: byte out of range");
    }
    if b > _mask(c.data_bits) {
      return _err_bytes("uart: byte exceeds data bits");
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  _push_idle(&mut out);
  i = 0;
  while i < n {
    let b2: Int = bytes[i];
    let er = uart_encode_byte_into(&mut out, c, b2);
    if !er.is_ok {
      return _err_bytes(er.error);
    }
    i = i + 1;
  }
  _push_idle(&mut out);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Decode one byte (frame starting at a position)
// --------------------------------------------------

/// Decode the frame that starts at bit index `pos` of `bits`; elements
/// after the frame are ignored, so a window may hold idle bits or the next
/// frame.
///
/// Checks in this order: the configuration (uart_config_ok catalog), then
/// pos < 0 -> Err("uart: bad position"), then a frame that does not fit ->
/// Err("uart: truncated frame"), then any frame element above 1 ->
/// Err("uart: invalid bit value"), then a start bit that is not 0 ->
/// Err("uart: false start bit"), then a received parity bit that differs
/// from the computed one -> Err("uart: parity mismatch") (parity modes only;
/// mark and space are compared like any other computed value), then any
/// stop bit that is not 1 -> Err("uart: invalid stop bit").
/// Returns: Ok(value) with the data value, 0..2^data_bits - 1.
/// Complexity: O(data_bits).
pub fn uart_decode_byte_at(bits: &Vec[UInt8], c: &UartConfig, pos: Int) -> Result[Int, Str]
  ensures: pos < 0 => result is Err;
  ensures: result is Ok => pos >= 0;
  ensures: result is Ok => result.value >= 0 && result.value <= 511;
{
  let vr = uart_config_ok(c);
  if !vr.is_ok {
    return _err_int(vr.error);
  }
  if pos < 0 {
    return _err_int("uart: bad position");
  }
  let flen = uart_frame_len(c);
  if pos + flen > bits.len() {
    return _err_int("uart: truncated frame");
  }
  var i = 0;
  while i < flen {
    let b: Int = (bits[pos + i] as Int) & 0xFF;
    if b > 1 {
      return _err_int("uart: invalid bit value");
    }
    i = i + 1;
  }
  let start: Int = (bits[pos] as Int) & 0xFF;
  if start != 0 {
    return _err_int("uart: false start bit");
  }
  let db: Int = c.data_bits;
  var value = 0;
  i = 0;
  while i < db {
    let b2: Int = (bits[pos + 1 + i] as Int) & 0xFF;
    if b2 == 1 {
      value = value + _pow2(i);
    }
    i = i + 1;
  }
  var next = 1 + db;
  let p: Int = c.parity;
  if p != 0 {
    let got: Int = (bits[pos + next] as Int) & 0xFF;
    let want = uart_parity_bit(p, value, db);
    if got != want {
      return _err_int("uart: parity mismatch");
    }
    next = next + 1;
  }
  let st = uart_stop_bit_times(c.stop_half);
  var k = 0;
  while k < st {
    let sb: Int = (bits[pos + next + k] as Int) & 0xFF;
    if sb != 1 {
      return _err_int("uart: invalid stop bit");
    }
    k = k + 1;
  }
  return _ok_int(value);
}

/// Decode the frame that starts at bit index 0 of `bits`;
/// uart_decode_byte_at(bits, c, 0). Complexity: O(data_bits).
pub fn uart_decode_byte(bits: &Vec[UInt8], c: &UartConfig) -> Result[Int, Str]
  ensures: result is Ok => result.value >= 0 && result.value <= 511;
  ensures: bits.len() < 7 => result is Err;
{
  return uart_decode_byte_at(bits, c, 0);
}

/// Decode a whole idle-high bit stream into its data values: leading and
/// trailing 1 bits are idle and skipped, and every 0 bit starts the next
/// frame (back-to-back frames need no idle gap because the stop bits keep
/// the line high until the next start bit).
///
/// Frames are decoded with uart_decode_byte_at, so its error catalog (and
/// the configuration catalog) propagates unchanged; an element above 1
/// anywhere, including in idle positions, is Err("uart: invalid bit value")
/// and a start bit at the end of the stream is Err("uart: truncated
/// frame"). Returns every frame value in order.
/// Complexity: O(bits.len()).
pub fn uart_decode_stream(bits: &Vec[UInt8], c: &UartConfig) -> Result[Vec[Int], Str]
  ensures: c.baud <= 0 => result is Err;
  ensures: result is Ok && bits.len() == 0 => result.value.len() == 0;
{
  let vr = uart_config_ok(c);
  if !vr.is_ok {
    return _err_intvec(vr.error);
  }
  let flen = uart_frame_len(c);
  var out = Vec[Int].new();
  var pos = 0;
  let n = bits.len();
  while pos < n {
    let b: Int = (bits[pos] as Int) & 0xFF;
    if b > 1 {
      return _err_intvec("uart: invalid bit value");
    }
    if b == 1 {
      pos = pos + 1;
    } else {
      let dr = uart_decode_byte_at(bits, c, pos);
      if !dr.is_ok {
        return _err_intvec(dr.error);
      }
      out.push(dr.value);
      pos = pos + flen;
    }
  }
  return _ok_intvec(out);
}

// --------------------------------------------------
//  Bit-stream helpers
// --------------------------------------------------

/// Bit `i` of `bits` widened to 0..255, or -1 when `i` is negative or
/// beyond the stream. A well-formed stream holds only 0 and 1.
/// Complexity: O(1).
pub fn uart_bit_get(bits: &Vec[UInt8], i: Int) -> Int
  ensures: i < 0 => result == -1;
  ensures: i >= bits.len() => result == -1;
  ensures: i >= 0 && i < bits.len() => result >= 0 && result <= 255;
{
  if i < 0 || i >= bits.len() {
    return -1;
  }
  return (bits[i] as Int) & 0xFF;
}

/// True when two bit streams hold the same widened element sequence.
/// Complexity: O(length).
pub fn uart_bits_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool
  ensures: a.len() != b.len() => !result;
  ensures: result => a.len() == b.len();
{
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// The idle line level: 1 (high). Complexity: O(1).
pub fn uart_idle_bit() -> Int
  ensures: result == 1;
{
  return 1;
}

/// A fresh vector of `count` idle-high bit times (empty for count <= 0).
/// Complexity: O(count).
pub fn uart_idle_bits(count: Int) -> Vec[UInt8]
  ensures: count <= 0 => result.len() == 0;
  ensures: count > 0 => result.len() == count;
{
  var v = Vec[UInt8].new();
  var i = 0;
  while i < count {
    v.push(1 as UInt8);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Oversampling
// --------------------------------------------------

/// True for the canonical oversampling factors 4, 8, 16 and 32.
/// Complexity: O(1).
pub fn uart_oversample_ok(oversample: Int) -> Bool
  ensures: result == (oversample == 4 || oversample == 8 || oversample == 16 || oversample == 32);
{
  if oversample == 4 {
    return true;
  }
  if oversample == 8 {
    return true;
  }
  if oversample == 16 {
    return true;
  }
  if oversample == 32 {
    return true;
  }
  return false;
}

/// The mid-bit sample offset within one bit period: oversample / 2 (8 for
/// the standard 16x oversampling), or -1 when oversample <= 0.
/// Complexity: O(1).
pub fn uart_sample_offset(oversample: Int) -> Int
  ensures: oversample <= 0 => result == -1;
  ensures: oversample > 0 => result == oversample / 2;
{
  if oversample <= 0 {
    return -1;
  }
  return oversample / 2;
}

/// Tick at which bit time `bit` starts: bit * oversample.
/// Complexity: O(1).
pub fn uart_bit_tick(bit: Int, oversample: Int) -> Int
  ensures: result == bit * oversample;
{
  return bit * oversample;
}

/// Tick of the mid-bit sample point of bit time `bit`:
/// bit * oversample + oversample / 2. Meaningful for oversample > 0.
/// Complexity: O(1).
pub fn uart_mid_tick(bit: Int, oversample: Int) -> Int
  ensures: result == bit * oversample + uart_sample_offset(oversample);
{
  return bit * oversample + uart_sample_offset(oversample);
}

/// Bit time a tick falls in: tick / oversample (truncating), or -1 when
/// tick < 0 or oversample <= 0. Complexity: O(1).
pub fn uart_tick_bit(tick: Int, oversample: Int) -> Int
  ensures: tick < 0 || oversample <= 0 => result == -1;
  ensures: tick >= 0 && oversample > 0 => result >= 0;
{
  if tick < 0 || oversample <= 0 {
    return -1;
  }
  return tick / oversample;
}

// --------------------------------------------------
//  Baud divisor math
// --------------------------------------------------

/// Baud divisor by truncating division: clock_hz / (oversample * baud).
/// With a valid input triple the divider is at least 1 and the resulting
/// line rate is at or above `baud`.
///
/// Err("uart: invalid clock") when clock_hz <= 0;
/// Err("uart: invalid baud") when baud <= 0;
/// Err("uart: invalid oversampling") when the factor is not 4, 8, 16 or
/// 32; Err("uart: clock too slow") when the divider would be 0.
/// Complexity: O(1).
pub fn uart_divisor(clock_hz: Int, baud: Int, oversample: Int) -> Result[Int, Str]
  ensures: clock_hz <= 0 => result is Err;
  ensures: result is Ok => result.value >= 1;
  ensures: result is Ok => baud > 0 && oversample > 0;
{
  let e = _rate_error(clock_hz, baud, oversample);
  if e.len() != 0 {
    return _err_int(e);
  }
  let den = oversample * baud;
  let d = clock_hz / den;
  if d < 1 {
    return _err_int("uart: clock too slow");
  }
  return _ok_int(d);
}

/// Baud divisor rounded to the nearest integer (half rounds up):
/// (clock_hz + den / 2) / den with den = oversample * baud. This is the
/// divider with the smallest rate error.
///
/// Same error catalog as uart_divisor. Complexity: O(1).
pub fn uart_divisor_nearest(clock_hz: Int, baud: Int, oversample: Int) -> Result[Int, Str]
  ensures: clock_hz <= 0 => result is Err;
  ensures: result is Ok => result.value >= 1;
  ensures: result is Ok => baud > 0 && oversample > 0;
{
  let e = _rate_error(clock_hz, baud, oversample);
  if e.len() != 0 {
    return _err_int(e);
  }
  let den = oversample * baud;
  let d = (clock_hz + den / 2) / den;
  if d < 1 {
    return _err_int("uart: clock too slow");
  }
  return _ok_int(d);
}

/// Fractional baud-rate error in parts per million of the divisor chosen
/// by uart_divisor_nearest: (clock_hz - baud * oversample * divisor) *
/// 1000000 / (baud * oversample * divisor), truncated toward zero, so a
/// divisor that runs fast gives a positive ppm and a slow one negative.
/// Same error catalog as uart_divisor. Complexity: O(1).
pub fn uart_baud_error_ppm(clock_hz: Int, baud: Int, oversample: Int) -> Result[Int, Str]
  ensures: clock_hz <= 0 => result is Err;
  ensures: result is Ok => result.value >= -1000000 && result.value <= 1000000;
  ensures: result is Ok => baud > 0 && oversample > 0;
{
  let dr = uart_divisor_nearest(clock_hz, baud, oversample);
  if !dr.is_ok {
    return _err_int(dr.error);
  }
  let d: Int = dr.value;
  let den = baud * oversample * d;
  let num = clock_hz - den;
  return _ok_int((num * 1000000) / den);
}

/// True when the absolute baud error of the uart_divisor_nearest divisor
/// is at most `max_ppm`; false for invalid inputs or a negative `max_ppm`.
/// Complexity: O(1).
pub fn uart_baud_ok(clock_hz: Int, baud: Int, oversample: Int, max_ppm: Int) -> Bool
  ensures: max_ppm < 0 => !result;
  ensures: result => max_ppm >= 0;
  ensures: clock_hz <= 0 => !result;
{
  let er = uart_baud_error_ppm(clock_hz, baud, oversample);
  if !er.is_ok {
    return false;
  }
  var e: Int = er.value;
  if e < 0 {
    e = 0 - e;
  }
  return e <= max_ppm;
}
