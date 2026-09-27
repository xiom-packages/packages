// XIOM -- xiom.i2c: I2C/SMBus codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no bus I/O) codec for I2C/SMBus byte-level transfers.
// In scope:
//   * 7-bit address byte encoding (address << 1 | R/W) with reserved-range
//     validation (0x00..0x07 and 0x78..0x7F are reserved) and decoding;
//   * the 10-bit two-byte addressing form (1111 0xx lead byte plus the low
//     address byte) with reserved-range validation and decoding;
//   * a typed, logical bus event model (START, repeated START, STOP, 7-bit
//     and 10-bit address events, data bytes, ACK and NACK) stored as two
//     index-aligned Vec[Int] arrays, with structural validation, a tagged
//     byte-stream encoding and a decoding round-trip;
//   * SMBus PEC: CRC-8 with polynomial 0x07 (x^8 + x^2 + x + 1), initial
//     value 0x00, no input/output reflection and no final XOR, plus cover
//     and verify helpers;
//   * SMBus quick and send-byte transaction builders.
// Every failure is a deterministic Err(Str) message; structural errors carry
// the event index and stream errors carry the byte offset of the offending
// element, e.g. "i2c: event 2: address or data event not followed by ACK or
// NACK" or "i2c: truncated event at byte 5".
//
// Event-stream wire format (one tag byte per event, payload as noted):
//   0x01 START            0x02 repeated START     0x03 STOP
//   0x04 ADDR7 write      0x05 ADDR7 read
//   0x06 ADDR10 write     0x07 ADDR10 read
//   0x08 data byte        0x09 ACK               0x0A NACK
//   ADDR7 and data events carry one payload byte (the 7-bit address or the
//   data byte); ADDR10 events carry two (high byte then low byte). The tag
//   value is the event kind constant itself. This is a logical, tagged
//   serialization of the event model, not a raw wire capture: the actual
//   address byte of a 7-bit transfer is derived with i2c_addr7_wire_byte and
//   the physical bus also interleaves ACK/NACK clock slots.
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no methods, no lambdas, no Vec[fn] dispatch and no
//     Vec[StructType]; a transaction is two index-aligned Vec[Int] arrays and
//     every push writes both arrays (mirrored pushes).
//   * Ok/Err construction is confined to the tiny leaf helpers `_ok_*` /
//     `_err_*` below (constructing Results inside other functions
//     miscompiles).
//   * every byte read from a Vec[UInt8] is widened with `(x as Int) & 0xFF`
//     before entering Int arithmetic; UInt8 values are never compared
//     against Int constants >= 128 without widening.
//   * `&struct.field` is never passed directly to a `&Vec` parameter (that
//     yields an empty vector in v0.61.3): the field is bound to a typed
//     local first.
//   * no Str value is compared with `==` in this module and none is read
//     from a Vec, so BUG 17 is unreachable; decimal formatting for the
//     offset-bearing messages is hand-rolled in `_dec` because the module
//     imports nothing.
//   * numeric splitting uses multiplication, division and modulo only (no
//     bit shift is used anywhere in this module).

module xiom.i2c

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// A decoded I2C address together with its transfer direction: `address` is
/// 0..127 for a 7-bit address or 0..1023 for a 10-bit address, and `read` is
/// `true` when the R/W bit selects a read (1) and `false` for a write (0).
pub type I2cAddr = {
  address: Int;
  read: Bool;
}

/// A logical I2C transaction as two index-aligned event arrays: `kinds[i]` is
/// the event kind (one of the I2C_EV_* constants) and `values[i]` the event
/// payload (the 7-bit address for ADDR7 events, the 10-bit address for
/// ADDR10 events, the data byte for DATA events, 0 for control events).
/// Constructing a value directly is allowed; i2c_txn_validate checks it.
/// Never push to one array without the other.
pub type I2cTransaction = {
  kinds: Vec[Int];
  values: Vec[Int];
}

// --------------------------------------------------
//  Event kinds
// --------------------------------------------------

/// Event kind: START condition.
pub const I2C_EV_START: Int = 1;
/// Event kind: repeated START condition.
pub const I2C_EV_RSTART: Int = 2;
/// Event kind: STOP condition.
pub const I2C_EV_STOP: Int = 3;
/// Event kind: 7-bit address event with the R/W bit clear (write).
pub const I2C_EV_ADDR7_W: Int = 4;
/// Event kind: 7-bit address event with the R/W bit set (read).
pub const I2C_EV_ADDR7_R: Int = 5;
/// Event kind: 10-bit address event with the R/W bit clear (write).
pub const I2C_EV_ADDR10_W: Int = 6;
/// Event kind: 10-bit address event with the R/W bit set (read).
pub const I2C_EV_ADDR10_R: Int = 7;
/// Event kind: data byte.
pub const I2C_EV_DATA: Int = 8;
/// Event kind: ACK driven by the receiver of the preceding byte.
pub const I2C_EV_ACK: Int = 9;
/// Event kind: NACK driven by the receiver of the preceding byte.
pub const I2C_EV_NACK: Int = 10;

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

// Ok(v) for Result[I2cAddr, Str].
fn _ok_addr(v: I2cAddr) -> Result[I2cAddr, Str] {
  return Ok(v);
}

// Err(m) for Result[I2cAddr, Str].
fn _err_addr(m: Str) -> Result[I2cAddr, Str] {
  return Err(m);
}

// Ok(v) for Result[I2cTransaction, Str].
fn _ok_txn(v: I2cTransaction) -> Result[I2cTransaction, Str] {
  return Ok(v);
}

// Err(m) for Result[I2cTransaction, Str].
fn _err_txn(m: Str) -> Result[I2cTransaction, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal text and byte helpers
// --------------------------------------------------

// Decimal text of `v` (including a leading minus for negatives), so error
// messages can carry offsets and values without importing xiom.convert.int.
fn _dec(v: Int) -> Str {
  var x = v;
  var prefix = "";
  if x < 0 {
    prefix = "-";
    x = 0 - x;
  }
  if x == 0 {
    return prefix + "0";
  }
  var digits = "";
  while x > 0 {
    let d = x % 10;
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
    digits = ds + digits;
    x = (x - d) / 10;
  }
  return prefix + digits;
}

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// True when `k` is an address or data event (the kinds that are acknowledged
// on the bus).
fn _is_byte_kind(k: Int) -> Bool {
  if k == I2C_EV_ADDR7_W || k == I2C_EV_ADDR7_R {
    return true;
  }
  if k == I2C_EV_ADDR10_W || k == I2C_EV_ADDR10_R {
    return true;
  }
  return k == I2C_EV_DATA;
}

// True when `k` is ACK or NACK.
fn _is_ack_kind(k: Int) -> Bool {
  return k == I2C_EV_ACK || k == I2C_EV_NACK;
}

// True when `k` is a 7-bit or 10-bit address event.
fn _is_addr_kind(k: Int) -> Bool {
  if k == I2C_EV_ADDR7_W || k == I2C_EV_ADDR7_R {
    return true;
  }
  return k == I2C_EV_ADDR10_W || k == I2C_EV_ADDR10_R;
}

// True when `k` is a control event (no payload byte on the bus).
fn _is_control_kind(k: Int) -> Bool {
  if k == I2C_EV_START || k == I2C_EV_RSTART || k == I2C_EV_STOP {
    return true;
  }
  return _is_ack_kind(k);
}

// --------------------------------------------------
//  Address validation
// --------------------------------------------------

// Validate a 7-bit address: 0..127 overall, 0x00..0x07 and 0x78..0x7F
// reserved. Messages carry the offending value but no "i2c: " prefix; public
// functions add it.
fn _addr7_check(address: Int) -> Result[Unit, Str] {
  if address < 0 || address > 127 {
    return _err_unit("7-bit address out of range (" + _dec(address) + ")");
  }
  if address < 8 || address > 119 {
    return _err_unit("reserved 7-bit address (" + _dec(address) + ")");
  }
  return _ok_unit();
}

// Validate a 10-bit address: 0..1023 overall, 0x000..0x007 and
// 0x3F8..0x3FF reserved. Messages carry the offending value but no "i2c: "
// prefix; public functions add it.
fn _addr10_check(address: Int) -> Result[Unit, Str] {
  if address < 0 || address > 1023 {
    return _err_unit("10-bit address out of range (" + _dec(address) + ")");
  }
  if address < 8 || address > 1015 {
    return _err_unit("reserved 10-bit address (" + _dec(address) + ")");
  }
  return _ok_unit();
}

/// True when `address` is a valid, non-reserved 7-bit address (8..119,
/// i.e. 0x08..0x77). Complexity: O(1).
pub fn i2c_addr7_ok(address: Int) -> Bool {
  if address < 0 {
    return false;
  }
  return address >= 8 && address <= 119;
}

/// True when `address` is a valid, non-reserved 10-bit address (8..1015,
/// i.e. 0x008..0x3F7). Complexity: O(1).
pub fn i2c_addr10_ok(address: Int) -> Bool {
  if address < 0 {
    return false;
  }
  return address >= 8 && address <= 1015;
}

// --------------------------------------------------
//  7-bit addressing
// --------------------------------------------------

/// The on-the-wire address byte of a 7-bit transfer: `address * 2` with the
/// R/W bit (`1` for a read) in bit 0.
///
/// Returns: Ok(byte) with byte in 0x10..0xEF (even for a write, odd for a
/// read).
/// Error case: Err("i2c: 7-bit address out of range (v)") when the address
/// is outside 0..127; Err("i2c: reserved 7-bit address (v)") when it is in
/// the reserved range 0x00..0x07 or 0x78..0x7F. Complexity: O(1).
pub fn i2c_addr7_wire_byte(address: Int, read: Bool) -> Result[Int, Str] {
  let vr = _addr7_check(address);
  if !vr.is_ok {
    return _err_int("i2c: " + vr.error);
  }
  var b = address * 2;
  if read {
    b = b + 1;
  }
  return _ok_int(b);
}

/// Decode a wire address byte into a 7-bit address and direction.
///
/// Returns: Ok(addr) with `addr.address == byte / 2` and
/// `addr.read == (byte % 2 == 1)`.
/// Error case: Err("i2c: address byte out of range (v)") when byte is
/// outside 0..255; the reserved-range message of i2c_addr7_wire_byte when
/// the decoded address is reserved (this also rejects every 10-bit lead
/// byte, whose decoded address 0x78..0x7F is reserved).
/// Complexity: O(1).
pub fn i2c_addr7_from_wire(byte: Int) -> Result[I2cAddr, Str] {
  if byte < 0 || byte > 255 {
    return _err_addr("i2c: address byte out of range (" + _dec(byte) + ")");
  }
  let address = byte / 2;
  var read = false;
  if byte % 2 == 1 {
    read = true;
  }
  let vr = _addr7_check(address);
  if !vr.is_ok {
    return _err_addr("i2c: " + vr.error);
  }
  return _ok_addr(I2cAddr{ address: address; read: read; });
}

// --------------------------------------------------
//  10-bit addressing
// --------------------------------------------------

/// The lead (first) byte of a 10-bit transfer: 1111 0xx where xx are the two
/// high address bits, with the R/W bit in bit 0.
///
/// Returns: Ok(byte) with byte in 0xF0..0xF7.
/// Error case: the i2c_addr10_wire_byte error catalog (i2c_addr10_check).
/// Complexity: O(1).
pub fn i2c_addr10_high_byte(address: Int, read: Bool) -> Result[Int, Str] {
  let vr = _addr10_check(address);
  if !vr.is_ok {
    return _err_int("i2c: " + vr.error);
  }
  var b = 240 + (address / 256) * 2;
  if read {
    b = b + 1;
  }
  return _ok_int(b);
}

/// The low (second) byte of a 10-bit transfer: `address % 256`.
///
/// Returns: Ok(byte) with byte in 0..255.
/// Error case: the i2c_addr10_check catalog. Complexity: O(1).
pub fn i2c_addr10_low_byte(address: Int) -> Result[Int, Str] {
  let vr = _addr10_check(address);
  if !vr.is_ok {
    return _err_int("i2c: " + vr.error);
  }
  return _ok_int(address % 256);
}

/// Decode the two-byte 10-bit addressing form into an address and direction.
///
/// Returns: Ok(addr) with `addr.address == ((high - 0xF0) / 2) * 256 + low`
/// and `addr.read == (high % 2 == 1)`.
/// Error case: Err("i2c: bad 10-bit address lead byte (v)") when `high` is
/// outside 0xF0..0xF7; Err("i2c: address byte out of range (v)") when `low`
/// is outside 0..255; the i2c_addr10_check catalog when the decoded address
/// is reserved. Complexity: O(1).
pub fn i2c_addr10_from_bytes(high: Int, low: Int) -> Result[I2cAddr, Str] {
  if high < 240 || high > 247 {
    return _err_addr("i2c: bad 10-bit address lead byte (" + _dec(high) + ")");
  }
  if low < 0 || low > 255 {
    return _err_addr("i2c: address byte out of range (" + _dec(low) + ")");
  }
  let address = ((high - 240) / 2) * 256 + low;
  var read = false;
  if high % 2 == 1 {
    read = true;
  }
  let vr = _addr10_check(address);
  if !vr.is_ok {
    return _err_addr("i2c: " + vr.error);
  }
  return _ok_addr(I2cAddr{ address: address; read: read; });
}

// --------------------------------------------------
//  Event helpers
// --------------------------------------------------

/// Human-readable name of an event kind: "START", "repeated START", "STOP",
/// "7-bit address write", "7-bit address read", "10-bit address write",
/// "10-bit address read", "data byte", "ACK", "NACK"; any other value is
/// "unknown event". Complexity: O(1).
pub fn i2c_kind_name(kind: Int) -> Str {
  if kind == I2C_EV_START {
    return "START";
  }
  if kind == I2C_EV_RSTART {
    return "repeated START";
  }
  if kind == I2C_EV_STOP {
    return "STOP";
  }
  if kind == I2C_EV_ADDR7_W {
    return "7-bit address write";
  }
  if kind == I2C_EV_ADDR7_R {
    return "7-bit address read";
  }
  if kind == I2C_EV_ADDR10_W {
    return "10-bit address write";
  }
  if kind == I2C_EV_ADDR10_R {
    return "10-bit address read";
  }
  if kind == I2C_EV_DATA {
    return "data byte";
  }
  if kind == I2C_EV_ACK {
    return "ACK";
  }
  if kind == I2C_EV_NACK {
    return "NACK";
  }
  return "unknown event";
}

// --------------------------------------------------
//  Transaction construction and access
// --------------------------------------------------

/// A new empty transaction (no events). Complexity: O(1).
pub fn i2c_txn_new() -> I2cTransaction {
  let ks = Vec[Int].new();
  let vs = Vec[Int].new();
  let t = I2cTransaction{ kinds: ks; values: vs; };
  return t;
}

/// Number of events in the transaction (`kinds.len()`). Complexity: O(1).
pub fn i2c_txn_len(t: &I2cTransaction) -> Int {
  let ks: Vec[Int] = t.kinds;
  return ks.len();
}

/// Kind of event `i`, or -1 when `i` is negative or beyond the last event.
/// Complexity: O(1).
pub fn i2c_txn_kind(t: &I2cTransaction, i: Int) -> Int {
  let ks: Vec[Int] = t.kinds;
  if i < 0 || i >= ks.len() {
    return -1;
  }
  let k: Int = ks[i];
  return k;
}

/// Value (payload) of event `i`, or -1 when `i` is negative or beyond the
/// last event. Complexity: O(1).
pub fn i2c_txn_value(t: &I2cTransaction, i: Int) -> Int {
  let vs: Vec[Int] = t.values;
  if i < 0 || i >= vs.len() {
    return -1;
  }
  let v: Int = vs[i];
  return v;
}

/// Append a START event. Complexity: O(1).
pub fn i2c_txn_push_start(t: &mut I2cTransaction) {
  t.kinds.push(I2C_EV_START);
  t.values.push(0);
}

/// Append a repeated START event. Complexity: O(1).
pub fn i2c_txn_push_rstart(t: &mut I2cTransaction) {
  t.kinds.push(I2C_EV_RSTART);
  t.values.push(0);
}

/// Append a STOP event. Complexity: O(1).
pub fn i2c_txn_push_stop(t: &mut I2cTransaction) {
  t.kinds.push(I2C_EV_STOP);
  t.values.push(0);
}

/// Append an ACK event. Complexity: O(1).
pub fn i2c_txn_push_ack(t: &mut I2cTransaction) {
  t.kinds.push(I2C_EV_ACK);
  t.values.push(0);
}

/// Append a NACK event. Complexity: O(1).
pub fn i2c_txn_push_nack(t: &mut I2cTransaction) {
  t.kinds.push(I2C_EV_NACK);
  t.values.push(0);
}

/// Append a 7-bit address event (write when `read` is false, read when true).
///
/// Returns: Ok(()) on success, with exactly one event appended.
/// Error case: the i2c_addr7_wire_byte catalog; nothing is appended on Err
/// (atomic failure). Complexity: O(1).
pub fn i2c_txn_push_addr7(t: &mut I2cTransaction, address: Int, read: Bool) -> Result[Unit, Str] {
  let vr = _addr7_check(address);
  if !vr.is_ok {
    return _err_unit("i2c: " + vr.error);
  }
  var k = I2C_EV_ADDR7_W;
  if read {
    k = I2C_EV_ADDR7_R;
  }
  t.kinds.push(k);
  t.values.push(address);
  return _ok_unit();
}

/// Append a 10-bit address event (write when `read` is false, read when
/// true).
///
/// Returns: Ok(()) on success, with exactly one event appended.
/// Error case: the i2c_addr10_check catalog; nothing is appended on Err
/// (atomic failure). Complexity: O(1).
pub fn i2c_txn_push_addr10(t: &mut I2cTransaction, address: Int, read: Bool) -> Result[Unit, Str] {
  let vr = _addr10_check(address);
  if !vr.is_ok {
    return _err_unit("i2c: " + vr.error);
  }
  var k = I2C_EV_ADDR10_W;
  if read {
    k = I2C_EV_ADDR10_R;
  }
  t.kinds.push(k);
  t.values.push(address);
  return _ok_unit();
}

/// Append a data byte event.
///
/// Returns: Ok(()) on success, with exactly one event appended.
/// Error case: Err("i2c: data byte out of range (v)") when `byte` is outside
/// 0..255; nothing is appended on Err (atomic failure). Complexity: O(1).
pub fn i2c_txn_push_data(t: &mut I2cTransaction, byte: Int) -> Result[Unit, Str] {
  if byte < 0 || byte > 255 {
    return _err_unit("i2c: data byte out of range (" + _dec(byte) + ")");
  }
  t.kinds.push(I2C_EV_DATA);
  t.values.push(byte);
  return _ok_unit();
}

// --------------------------------------------------
//  Validation and equality
// --------------------------------------------------

/// Validate the full transaction structure. The two arrays must be
/// index-aligned and non-empty, the first event must be START, the last must
/// be STOP, every control event must carry value 0, address and data values
/// must be in range (address events use the reserved-range rules), every
/// address or data event must be immediately followed by ACK or NACK, ACK
/// and NACK must immediately follow an address or data event, a repeated
/// START must follow an ACK or NACK and be followed by an address event, a
/// START may only appear at position 0 and a STOP only at the end.
///
/// Returns: Ok(()) for a well-formed transaction.
/// Error case: deterministic Err("i2c: ...") messages carrying the event
/// index, or Err("i2c: empty transaction"), or Err("i2c: event arrays out of
/// step (a kinds, b values)"). Complexity: O(events).
pub fn i2c_txn_validate(t: &I2cTransaction) -> Result[Unit, Str] {
  let ks: Vec[Int] = t.kinds;
  let vs: Vec[Int] = t.values;
  let n = ks.len();
  if n != vs.len() {
    return _err_unit("i2c: event arrays out of step (" + _dec(n) + " kinds, " + _dec(vs.len()) + " values)");
  }
  if n == 0 {
    return _err_unit("i2c: empty transaction");
  }
  let k_first: Int = ks[0];
  if k_first != I2C_EV_START {
    return _err_unit("i2c: event 0: transaction must begin with START");
  }
  let k_last: Int = ks[n - 1];
  if k_last != I2C_EV_STOP {
    return _err_unit("i2c: event " + _dec(n - 1) + ": transaction must end with STOP");
  }
  var i = 0;
  while i < n {
    let k: Int = ks[i];
    let v: Int = vs[i];
    if k < I2C_EV_START || k > I2C_EV_NACK {
      return _err_unit("i2c: event " + _dec(i) + ": invalid event kind (" + _dec(k) + ")");
    }
    if _is_control_kind(k) {
      if v != 0 {
        return _err_unit("i2c: event " + _dec(i) + ": control event carries a value (" + _dec(v) + ")");
      }
    }
    if k == I2C_EV_ADDR7_W || k == I2C_EV_ADDR7_R {
      let ar = _addr7_check(v);
      if !ar.is_ok {
        return _err_unit("i2c: event " + _dec(i) + ": " + ar.error);
      }
    }
    if k == I2C_EV_ADDR10_W || k == I2C_EV_ADDR10_R {
      let ar10 = _addr10_check(v);
      if !ar10.is_ok {
        return _err_unit("i2c: event " + _dec(i) + ": " + ar10.error);
      }
    }
    if k == I2C_EV_DATA {
      if v < 0 || v > 255 {
        return _err_unit("i2c: event " + _dec(i) + ": data byte out of range (" + _dec(v) + ")");
      }
    }
    if k == I2C_EV_ACK || k == I2C_EV_NACK {
      if i == 0 {
        return _err_unit("i2c: event " + _dec(i) + ": ACK or NACK without a preceding byte event");
      }
      let pk: Int = ks[i - 1];
      if !_is_byte_kind(pk) {
        return _err_unit("i2c: event " + _dec(i) + ": ACK or NACK without a preceding byte event");
      }
    }
    if k == I2C_EV_RSTART {
      if i == 0 {
        return _err_unit("i2c: event " + _dec(i) + ": repeated START without a preceding ACK or NACK");
      }
      let pk2: Int = ks[i - 1];
      if !_is_ack_kind(pk2) {
        return _err_unit("i2c: event " + _dec(i) + ": repeated START without a preceding ACK or NACK");
      }
    }
    if k == I2C_EV_START {
      if i != 0 {
        return _err_unit("i2c: event " + _dec(i) + ": START after position 0 (use repeated START)");
      }
    }
    if k == I2C_EV_STOP {
      if i != n - 1 {
        return _err_unit("i2c: event " + _dec(i) + ": STOP before the end of the transaction");
      }
    }
    if _is_byte_kind(k) {
      if i + 1 >= n {
        return _err_unit("i2c: event " + _dec(i) + ": address or data event not followed by ACK or NACK");
      }
      let nk: Int = ks[i + 1];
      if !_is_ack_kind(nk) {
        return _err_unit("i2c: event " + _dec(i) + ": address or data event not followed by ACK or NACK");
      }
    }
    if k == I2C_EV_START || k == I2C_EV_RSTART {
      if i + 1 >= n {
        return _err_unit("i2c: event " + _dec(i) + ": START or repeated START not followed by an address event");
      }
      let nk2: Int = ks[i + 1];
      if !_is_addr_kind(nk2) {
        return _err_unit("i2c: event " + _dec(i) + ": START or repeated START not followed by an address event");
      }
    }
    i = i + 1;
  }
  return _ok_unit();
}

/// Structural equality: same event count and the same kind/value pairs in
/// the same order. Complexity: O(events).
pub fn i2c_txn_equal(a: &I2cTransaction, b: &I2cTransaction) -> Bool {
  let ak: Vec[Int] = a.kinds;
  let bk: Vec[Int] = b.kinds;
  if ak.len() != bk.len() {
    return false;
  }
  let av: Vec[Int] = a.values;
  let bv: Vec[Int] = b.values;
  if av.len() != bv.len() {
    return false;
  }
  var i = 0;
  while i < ak.len() {
    let x: Int = ak[i];
    let y: Int = bk[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  var j = 0;
  while j < av.len() {
    let x2: Int = av[j];
    let y2: Int = bv[j];
    if x2 != y2 {
      return false;
    }
    j = j + 1;
  }
  return true;
}

// --------------------------------------------------
//  Event-stream codec
// --------------------------------------------------

/// Encoded length of one event of kind `kind`: 1 byte for START, repeated
/// START, STOP, ACK and NACK; 2 bytes for 7-bit address and data events;
/// 3 bytes for 10-bit address events; -1 for an unknown kind.
/// Complexity: O(1).
pub fn i2c_event_encoded_len(kind: Int) -> Int {
  if kind == I2C_EV_ADDR7_W || kind == I2C_EV_ADDR7_R {
    return 2;
  }
  if kind == I2C_EV_DATA {
    return 2;
  }
  if kind == I2C_EV_ADDR10_W || kind == I2C_EV_ADDR10_R {
    return 3;
  }
  if kind >= I2C_EV_START && kind <= I2C_EV_NACK {
    return 1;
  }
  return -1;
}

/// Encoded length of a whole transaction, or -1 when it contains an unknown
/// event kind. Complexity: O(events).
pub fn i2c_txn_encoded_len(t: &I2cTransaction) -> Int {
  let ks: Vec[Int] = t.kinds;
  var total = 0;
  var i = 0;
  while i < ks.len() {
    let k: Int = ks[i];
    let el = i2c_event_encoded_len(k);
    if el < 0 {
      return -1;
    }
    total = total + el;
    i = i + 1;
  }
  return total;
}

/// Append the tagged event stream of `t` to `out`. The transaction is
/// validated first, so an invalid transaction is an Err and `out` is
/// byte-for-byte unchanged (atomic failure).
///
/// Returns: Ok(()) on success.
/// Error case: the i2c_txn_validate catalog. Complexity: O(events).
pub fn i2c_events_encode_into(out: &mut Vec[UInt8], t: &I2cTransaction) -> Result[Unit, Str] {
  let vr = i2c_txn_validate(t);
  if !vr.is_ok {
    return _err_unit(vr.error);
  }
  let ks: Vec[Int] = t.kinds;
  let vs: Vec[Int] = t.values;
  var i = 0;
  while i < ks.len() {
    let k: Int = ks[i];
    let v: Int = vs[i];
    out.push(k as UInt8);
    if k == I2C_EV_ADDR7_W || k == I2C_EV_ADDR7_R || k == I2C_EV_DATA {
      out.push(v as UInt8);
    } elif k == I2C_EV_ADDR10_W || k == I2C_EV_ADDR10_R {
      out.push(((v / 256) % 256) as UInt8);
      out.push((v % 256) as UInt8);
    }
    i = i + 1;
  }
  return _ok_unit();
}

/// Encode `t` into a fresh tagged event stream (i2c_txn_encoded_len bytes on
/// success). Same validation and error catalog as i2c_events_encode_into.
/// Complexity: O(events).
pub fn i2c_events_encode(t: &I2cTransaction) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let er = i2c_events_encode_into(&mut out, t);
  if !er.is_ok {
    return _err_bytes(er.error);
  }
  return _ok_bytes(out);
}

/// Decode a tagged event stream into a transaction.
///
/// Returns: Ok(transaction) for a stream that parses and passes
/// i2c_txn_validate.
/// Error case: Err("i2c: truncated event at byte i") when a tag's payload
/// runs past the end of the stream; Err("i2c: unknown event tag (v) at byte
/// i") for an unassigned tag; otherwise the i2c_txn_validate catalog with
/// event indexes (including "i2c: empty transaction" for an empty stream).
/// Complexity: O(bytes).
pub fn i2c_events_decode(bytes: &Vec[UInt8]) -> Result[I2cTransaction, Str] {
  let n = bytes.len();
  let ks = Vec[Int].new();
  let vs = Vec[Int].new();
  var t = I2cTransaction{ kinds: ks; values: vs; };
  var i = 0;
  while i < n {
    let tag: Int = _byte(bytes, i);
    if _is_control_kind(tag) {
      t.kinds.push(tag);
      t.values.push(0);
      i = i + 1;
    } elif tag == I2C_EV_ADDR7_W || tag == I2C_EV_ADDR7_R || tag == I2C_EV_DATA {
      if i + 1 >= n {
        return _err_txn("i2c: truncated event at byte " + _dec(i));
      }
      let v: Int = _byte(bytes, i + 1);
      t.kinds.push(tag);
      t.values.push(v);
      i = i + 2;
    } elif tag == I2C_EV_ADDR10_W || tag == I2C_EV_ADDR10_R {
      if i + 2 >= n {
        return _err_txn("i2c: truncated event at byte " + _dec(i));
      }
      let hi: Int = _byte(bytes, i + 1);
      let lo: Int = _byte(bytes, i + 2);
      t.kinds.push(tag);
      t.values.push(hi * 256 + lo);
      i = i + 3;
    } else {
      return _err_txn("i2c: unknown event tag (" + _dec(tag) + ") at byte " + _dec(i));
    }
  }
  let vr = i2c_txn_validate(&t);
  if !vr.is_ok {
    return _err_txn(vr.error);
  }
  return _ok_txn(t);
}

// --------------------------------------------------
//  SMBus PEC (CRC-8)
// --------------------------------------------------

/// SMBus PEC: CRC-8 with polynomial 0x07 (x^8 + x^2 + x + 1), initial value
/// 0x00, no input or output reflection and no final XOR, over the bytes of
/// `data` in order. Returns the checksum as an Int in 0..255; an empty input
/// returns 0 (the initial value survives). The catalogue check value over
/// "123456789" is 244 (0xF4). This is the checksum SMBus appends to a
/// transaction. Complexity: O(data.len()) time, O(1) space.
pub fn i2c_pec(data: &Vec[UInt8]) -> Int {
  var crc = 0;
  var i = 0;
  while i < data.len() {
    let b: Int = _byte(data, i);
    crc = crc ^ b;
    var j = 0;
    while j < 8 {
      if (crc & 128) != 0 {
        crc = ((crc * 2) & 255) ^ 7;
      } else {
        crc = (crc * 2) & 255;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return crc;
}

/// A copy of `frame` with its SMBus PEC byte appended (the PEC covers the
/// original `frame` bytes). Appending the PEC again to the result would
/// cover it too, so the returned frame has one extra byte and its own PEC is
/// `i2c_pec(&result) == 0`. Complexity: O(frame.len()).
pub fn i2c_pec_cover(frame: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < frame.len() {
    out.push(frame[i]);
    i = i + 1;
  }
  let p = i2c_pec(frame);
  out.push(p as UInt8);
  return out;
}

/// Validate a PEC-protected frame: the last byte must equal i2c_pec over the
/// bytes before it.
///
/// Returns: Ok(()) when the trailing PEC is correct.
/// Error case: Err("i2c: short pec frame (n)") when `frame` has fewer than
/// two bytes (no data byte plus PEC); Err("i2c: bad pec (computed c,
/// received r)") on mismatch. Complexity: O(frame.len()).
pub fn i2c_pec_verify(frame: &Vec[UInt8]) -> Result[Unit, Str] {
  let n = frame.len();
  if n < 2 {
    return _err_unit("i2c: short pec frame (" + _dec(n) + ")");
  }
  var body = Vec[UInt8].new();
  var i = 0;
  while i < n - 1 {
    body.push(frame[i]);
    i = i + 1;
  }
  let computed = i2c_pec(&body);
  let received: Int = _byte(frame, n - 1);
  if computed != received {
    return _err_unit("i2c: bad pec (computed " + _dec(computed) + ", received " + _dec(received) + ")");
  }
  return _ok_unit();
}

// --------------------------------------------------
//  SMBus command helpers
// --------------------------------------------------

/// Build the transaction of an SMBus Quick command: START, the 7-bit address
/// event with the requested direction, the address ACK and STOP (no data
/// byte).
///
/// Returns: Ok(transaction).
/// Error case: the i2c_addr7_wire_byte catalog. Complexity: O(1).
pub fn smbus_quick(address: Int, read: Bool) -> Result[I2cTransaction, Str] {
  var t = i2c_txn_new();
  i2c_txn_push_start(&mut t);
  let ar = i2c_txn_push_addr7(&mut t, address, read);
  if !ar.is_ok {
    return _err_txn(ar.error);
  }
  i2c_txn_push_ack(&mut t);
  i2c_txn_push_stop(&mut t);
  return _ok_txn(t);
}

/// Build the transaction of an SMBus Send Byte command: START, the 7-bit
/// address event (always a write), the address ACK, the data byte, its ACK
/// and STOP.
///
/// Returns: Ok(transaction).
/// Error case: the i2c_addr7_wire_byte catalog, or Err("i2c: data byte out
/// of range (v)") when `value` is outside 0..255. Complexity: O(1).
pub fn smbus_send_byte(address: Int, value: Int) -> Result[I2cTransaction, Str] {
  var t = i2c_txn_new();
  i2c_txn_push_start(&mut t);
  let ar = i2c_txn_push_addr7(&mut t, address, false);
  if !ar.is_ok {
    return _err_txn(ar.error);
  }
  i2c_txn_push_ack(&mut t);
  let dr = i2c_txn_push_data(&mut t, value);
  if !dr.is_ok {
    return _err_txn(dr.error);
  }
  i2c_txn_push_ack(&mut t);
  i2c_txn_push_stop(&mut t);
  return _ok_txn(t);
}
