// XIOM -- xiom.dac: DAC command/register codecs
// Port task: greenfield pure-XIOM port (no FFI, no bus I/O, no device state)
// of the deterministic subset of DAC handling: command and register frames for
// the MCP4725 (single 12-bit I2C), MCP4728 (quad 12-bit I2C) and MCP4921 /
// MCP4922 (single/dual 12-bit SPI) families, plus integer code-to-microvolt
// scaling.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Layouts implemented (byte-level tables in SPEC.md; MSB first on the wire):
//
//   MCP4725 (7-bit address 0x60..0x67; VDD is the reference)
//     Fast write (3 bytes):    [addr*2+0] [0 0 PD1 PD0 D11..D8] [D7..D0]
//     Write DAC (4 bytes):     [addr*2+0] [0 1 0 X X PD1 PD0 X] [D11..D4]
//                              [(D3..D0) X X X X]
//     Write DAC+EEPROM (4):    same with command bits 0 1 1 (0x60 + PD).
//     Read:                    [addr*2+1]; the part then clocks out six bytes.
//   MCP4728 (7-bit address 0x60..0x67 via A2 A1 A0, default 000)
//     Multi-write (4 bytes):   [addr*2+0] [0 1 0 0 0 DAC1 DAC0 UDAC]
//                              [VREF PD1 PD0 GX D11..D8] [D7..D0]
//     Single write+EEPROM (4): same with W1 W0 = 1 1 (command byte 0x58 |
//                              channel*2 | UDAC).
//     Fast write (3 bytes):    [addr*2+0] [X X PD1 PD0 D11..D8] [D7..D0]
//                              (channels A..D written sequentially).
//   MCP4921/MCP4922 (16-bit SPI, CS active low)
//     [A/B BUF GA SHDN D11..D0] as two bytes, MSB first. A/B selects DAC B on
//     the dual part, BUF selects the buffered reference input, GA=1 is 1x and
//     GA=0 is 2x, SHDN=1 keeps the output active (0 = high impedance). The
//     hardware SHDN and LDAC pins are active low.
//
// Voltage conversion: all three families are 12-bit and scale as
//   uv = vref_uv * code * gain / 4096
// (the datasheet divides by 2^n, not 2^n-1, so code 4095 maps to full scale
// minus one LSB). The generic helper supports 8..24 bit resolutions with the
// same 2^n divisor. The product is formed first and the single division
// truncates toward zero; the truncation is documented and pinned in tests.
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no methods, no lambdas, no Vec[fn] dispatch and no
//     Vec[StructType]; decoded frames are small structs returned by value from
//     one leaf constructor each.
//   * Ok/Err construction is confined to the tiny leaf helpers `_ok_*` /
//     `_err_*` below (constructing Results directly inside other functions
//     miscompiles).
//   * no Str value is compared with `==` and none is read from a Vec, so
//     BUG 17 is unreachable here; dynamic messages are built with
//     xiom.convert.int_to_string.
//   * every byte read from a Vec[UInt8] is widened with `(x as Int) & 0xFF`
//     before entering Int arithmetic; UInt8 values are never compared against
//     Int constants >= 128 without widening.
//   * `&struct.field` is never passed as a `&Vec[UInt8]` parameter (that
//     yields an empty vector in v0.61.3); frame buffers are always bound to
//     typed locals first.
//   * bit composition and extraction use multiplication, division and modulo
//     by powers of two, never a shift (shifts on a sign-carrying value are
//     unreliable); division truncates toward zero.
//   * no `&mut` out-parameters: every encoder returns its frame by value.

module xiom.dac

use xiom.convert;

// --------------------------------------------------
//  Constants: generic scaling and families
// --------------------------------------------------

/// Lowest resolution supported by the generic scaler, in bits.
pub const DAC_BITS_MIN: Int = 8;
/// Highest resolution supported by the generic scaler, in bits.
pub const DAC_BITS_MAX: Int = 24;
/// Family selector: the single-channel 12-bit MCP4725 I2C DAC.
pub const DAC_FAMILY_MCP4725: Int = 0;
/// Family selector: the quad 12-bit MCP4728 I2C DAC.
pub const DAC_FAMILY_MCP4728: Int = 1;
/// Family selector: the single-channel 12-bit MCP4921 SPI DAC.
pub const DAC_FAMILY_MCP4921: Int = 2;
/// Family selector: the dual-channel 12-bit MCP4922 SPI DAC.
pub const DAC_FAMILY_MCP4922: Int = 3;

// --------------------------------------------------
//  Constants: power-down (MCP4725 Table 5-2 / MCP4728 Table 4-7)
// --------------------------------------------------

/// PD bits 00: normal mode, the output amplifier is on.
pub const DAC_PD_NORMAL: Int = 0;
/// PD bits 01: powered down with a 1 kOhm resistor to ground.
pub const DAC_PD_1K_GND: Int = 1;
/// PD bits 10: powered down with a 100 kOhm resistor to ground.
pub const DAC_PD_100K_GND: Int = 2;
/// PD bits 11: powered down with a 500 kOhm resistor to ground.
pub const DAC_PD_500K_GND: Int = 3;

// --------------------------------------------------
//  Constants: MCP4725
// --------------------------------------------------

/// Lowest 7-bit address of the MCP4725 (A2 A1 A0 = 000).
pub const MCP4725_ADDRESS_BASE: Int = 96;
/// Highest 7-bit address of the MCP4725 (A2 A1 A0 = 111).
pub const MCP4725_ADDRESS_MAX: Int = 103;
/// Resolution of the MCP4725 in bits.
pub const MCP4725_RESOLUTION_BITS: Int = 12;
/// Largest MCP4725 input code (2^12 - 1).
pub const MCP4725_FULL_SCALE: Int = 4095;
/// MCP4725 command bits 000: fast write (C0 is don't care).
pub const MCP4725_CMD_FAST: Int = 0;
/// MCP4725 command bits 010: write the DAC register (EEPROM untouched).
pub const MCP4725_CMD_WRITE_DAC: Int = 2;
/// MCP4725 command bits 011: write the DAC register and the EEPROM.
pub const MCP4725_CMD_WRITE_EEPROM: Int = 3;

// --------------------------------------------------
//  Constants: MCP4728
// --------------------------------------------------

/// Lowest 7-bit address of the MCP4728 (A2 A1 A0 = 000; also the factory default).
pub const MCP4728_ADDRESS_BASE: Int = 96;
/// Highest 7-bit address of the MCP4728 (A2 A1 A0 = 111).
pub const MCP4728_ADDRESS_MAX: Int = 103;
/// Resolution of the MCP4728 in bits.
pub const MCP4728_RESOLUTION_BITS: Int = 12;
/// Largest MCP4728 input code (2^12 - 1).
pub const MCP4728_FULL_SCALE: Int = 4095;
/// MCP4728 channel A (DAC1 DAC0 = 00).
pub const MCP4728_CH_A: Int = 0;
/// MCP4728 channel B (DAC1 DAC0 = 01).
pub const MCP4728_CH_B: Int = 1;
/// MCP4728 channel C (DAC1 DAC0 = 10).
pub const MCP4728_CH_C: Int = 2;
/// MCP4728 channel D (DAC1 DAC0 = 11).
pub const MCP4728_CH_D: Int = 3;
/// MCP4728 command type 010 with W1 W0 = 00: multi-write to one selected channel.
pub const MCP4728_MODE_MULTI: Int = 0;
/// MCP4728 command type 010 with W1 W0 = 10: sequential write from a start channel to D.
pub const MCP4728_MODE_SEQUENTIAL: Int = 1;
/// MCP4728 command type 010 with W1 W0 = 11: single write plus EEPROM.
pub const MCP4728_MODE_SINGLE: Int = 2;
/// MCP4728 fast write (command type 000, 3 bytes, no configuration bits).
pub const MCP4728_MODE_FAST: Int = 3;
/// MCP4728 VREF bit 0: external reference (VDD, gain forced to 1).
pub const MCP4728_VREF_EXTERNAL: Int = 0;
/// MCP4728 VREF bit 1: internal 2.048 V reference.
pub const MCP4728_VREF_INTERNAL: Int = 1;
/// The MCP4728 internal reference in microvolts (2.048 V).
pub const MCP4728_INTERNAL_REF_UV: Int = 2048000;
/// MCP4728 GX bit 0: gain 1x.
pub const MCP4728_GAIN_1X: Int = 0;
/// MCP4728 GX bit 1: gain 2x (internal reference only).
pub const MCP4728_GAIN_2X: Int = 1;
/// MCP4728 UDAC bit 0: upload the selected channel to its output register.
pub const MCP4728_UDAC_UPDATE: Int = 0;
/// MCP4728 UDAC bit 1: hold, do not update the output register.
pub const MCP4728_UDAC_HOLD: Int = 1;

// --------------------------------------------------
//  Constants: MCP4921/MCP4922
// --------------------------------------------------

/// Resolution of the MCP4921/MCP4922 in bits.
pub const MCP492X_RESOLUTION_BITS: Int = 12;
/// Largest MCP492x input code (2^12 - 1).
pub const MCP492X_FULL_SCALE: Int = 4095;
/// MCP492x channel A (A/B bit 0).
pub const MCP492X_CH_A: Int = 0;
/// MCP492x channel B (A/B bit 1; MCP4922 only).
pub const MCP492X_CH_B: Int = 1;
/// MCP492x gain multiplier 1x.
pub const MCP492X_GAIN_1X: Int = 1;
/// MCP492x gain multiplier 2x.
pub const MCP492X_GAIN_2X: Int = 2;
/// GA bit value for 1x gain.
pub const MCP492X_GA_BIT_1X: Int = 1;
/// GA bit value for 2x gain.
pub const MCP492X_GA_BIT_2X: Int = 0;
/// BUF bit 0: the VREF input buffer is bypassed (datasheet default).
pub const MCP492X_BUF_UNBUFFERED: Int = 0;
/// BUF bit 1: the VREF input buffer is enabled.
pub const MCP492X_BUF_BUFFERED: Int = 1;
/// SHDN bit 0: the output buffer is disabled and VOUT is high impedance.
pub const MCP492X_SHDN_HIGH_Z: Int = 0;
/// SHDN bit 1: the output is active (the hardware SHDN pin is active low).
pub const MCP492X_SHDN_ACTIVE: Int = 1;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Decoded MCP4725 write frame: the 7-bit `address`, the command `mode` (one
/// of MCP4725_CMD_FAST / MCP4725_CMD_WRITE_DAC / MCP4725_CMD_WRITE_EEPROM),
/// the power-down selector `pd` (0..3) and the 12-bit input `code` (0..4095).
pub type Mcp4725Frame = {
  address: Int;
  mode: Int;
  pd: Int;
  code: Int;
}

/// Decoded MCP4728 write frame: the 7-bit `address`, the write `mode` (one of
/// MCP4728_MODE_MULTI / MCP4728_MODE_SEQUENTIAL / MCP4728_MODE_SINGLE /
/// MCP4728_MODE_FAST), the `channel` (0..3 = A..D; -1 is never produced by
/// the decoder), the 12-bit input `code`, the `vref` bit, the power-down
/// selector `pd`, the `gain` bit (GX) and the `udac` bit.
pub type Mcp4728Frame = {
  address: Int;
  mode: Int;
  channel: Int;
  code: Int;
  vref: Int;
  pd: Int;
  gain: Int;
  udac: Int;
}

/// Decoded MCP492x SPI write frame: the `channel` (0 = DAC A, 1 = DAC B), the
/// `buf` bit, the effective `gain` multiplier (1 or 2, decoded from GA), the
/// `shdn` bit and the 12-bit input `code`. The A/B, BUF, GA and SHDN fields
/// are raw bits; `gain` is the decoded multiplier so GA=1 decodes to gain 1
/// and GA=0 decodes to gain 2.
pub type Mcp492xFrame = {
  channel: Int;
  buf: Int;
  gain: Int;
  shdn: Int;
  code: Int;
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

// Ok(v) for Result[Mcp4725Frame, Str].
fn _ok_4725(v: Mcp4725Frame) -> Result[Mcp4725Frame, Str] {
  return Ok(v);
}

// Err(m) for Result[Mcp4725Frame, Str].
fn _err_4725(m: Str) -> Result[Mcp4725Frame, Str] {
  return Err(m);
}

// Ok(v) for Result[Mcp4728Frame, Str].
fn _ok_4728(v: Mcp4728Frame) -> Result[Mcp4728Frame, Str] {
  return Ok(v);
}

// Err(m) for Result[Mcp4728Frame, Str].
fn _err_4728(m: Str) -> Result[Mcp4728Frame, Str] {
  return Err(m);
}

// Ok(v) for Result[Mcp492xFrame, Str].
fn _ok_492x(v: Mcp492xFrame) -> Result[Mcp492xFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[Mcp492xFrame, Str].
fn _err_492x(m: Str) -> Result[Mcp492xFrame, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// 2^k for 0 <= k <= 30, computed by repeated multiplication (no shift).
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// True when `bits` is inside the generic 8..24 envelope.
fn _bits_ok(bits: Int) -> Bool {
  return bits >= DAC_BITS_MIN && bits <= DAC_BITS_MAX;
}

// The two power-down bits packed at bit 5 (PD1) and bit 4 (PD0) of an MCP47xx
// fast-write second byte: pd 0..3 -> 0x00 / 0x20 / 0x10 / 0x30.
fn _pd_bits(pd: Int) -> Int {
  return (pd / 2) * 32 + (pd % 2) * 16;
}

// Human-readable power-down mode name shared by the MCP47xx families:
// "normal", "1k gnd", "100k gnd", "500k gnd" or "unknown".
fn _pd_name(pd: Int) -> Str {
  if pd == DAC_PD_NORMAL {
    return "normal";
  }
  if pd == DAC_PD_1K_GND {
    return "1k gnd";
  }
  if pd == DAC_PD_100K_GND {
    return "100k gnd";
  }
  if pd == DAC_PD_500K_GND {
    return "500k gnd";
  }
  return "unknown";
}

// "" when the address is inside lo..hi, else the offset-free range message.
fn _addr_error(prefix: Str, address: Int, lo: Int, hi: Int) -> Str {
  if address < lo || address > hi {
    return prefix + ": address " + convert.int_to_string(address) + " out of range " + convert.int_to_string(lo) + ".." + convert.int_to_string(hi);
  }
  return "";
}

// "" when `code` is inside 0..full_scale, else the range message.
fn _code_error(prefix: Str, code: Int, full_scale: Int) -> Str {
  if code < 0 || code > full_scale {
    return prefix + ": code " + convert.int_to_string(code) + " out of range 0.." + convert.int_to_string(full_scale);
  }
  return "";
}

// "" when `v` is 0 or 1, else the named one-bit message.
fn _bit_error(prefix: Str, field: Str, v: Int) -> Str {
  if v < 0 || v > 1 {
    return prefix + ": " + field + " " + convert.int_to_string(v) + " is not 0 or 1";
  }
  return "";
}

// Shared code-to-microvolt validation. `prefix` is the family message prefix
// (no trailing colon); validation order: resolution, vref, gain, code.
fn _code_uv_error(prefix: Str, code: Int, bits: Int, vref_uv: Int, gain: Int) -> Str {
  if !_bits_ok(bits) {
    return prefix + ": resolution " + convert.int_to_string(bits) + " out of range 8..24";
  }
  if vref_uv <= 0 {
    return prefix + ": vref " + convert.int_to_string(vref_uv) + " uV must be positive";
  }
  if gain < 1 {
    return prefix + ": gain " + convert.int_to_string(gain) + " must be at least 1";
  }
  let fs = _pow2(bits) - 1;
  if code < 0 || code > fs {
    return prefix + ": code " + convert.int_to_string(code) + " out of range 0.." + convert.int_to_string(fs);
  }
  return "";
}

// Shared scaling core: vref_uv * code * gain / 2^bits with one truncating
// division at the end. Callers validate first.
fn _scale_uv(code: Int, bits: Int, vref_uv: Int, gain: Int) -> Int {
  return vref_uv * code * gain / _pow2(bits);
}

// --------------------------------------------------
//  Generic family accessors
// --------------------------------------------------

/// Human-readable family name: "mcp4725", "mcp4728", "mcp4921", "mcp4922" or
/// "unknown". Complexity: O(1).
pub fn dac_family_name(family: Int) -> Str {
  if family == DAC_FAMILY_MCP4725 {
    return "mcp4725";
  }
  if family == DAC_FAMILY_MCP4728 {
    return "mcp4728";
  }
  if family == DAC_FAMILY_MCP4921 {
    return "mcp4921";
  }
  if family == DAC_FAMILY_MCP4922 {
    return "mcp4922";
  }
  return "unknown";
}

/// Resolution in bits of a family selector: 12 for every family in scope, or
/// -1 for an unknown selector. Complexity: O(1).
pub fn dac_resolution_bits(family: Int) -> Int {
  if family == DAC_FAMILY_MCP4725 {
    return MCP4725_RESOLUTION_BITS;
  }
  if family == DAC_FAMILY_MCP4728 {
    return MCP4728_RESOLUTION_BITS;
  }
  if family == DAC_FAMILY_MCP4921 || family == DAC_FAMILY_MCP4922 {
    return MCP492X_RESOLUTION_BITS;
  }
  return -1;
}

/// Largest input code of a family selector (2^bits - 1), or -1 for an unknown
/// selector. Complexity: O(1).
pub fn dac_full_scale(family: Int) -> Int {
  if dac_resolution_bits(family) == MCP4725_RESOLUTION_BITS {
    return MCP4725_FULL_SCALE;
  }
  if family == DAC_FAMILY_MCP4921 || family == DAC_FAMILY_MCP4922 {
    return MCP492X_FULL_SCALE;
  }
  return -1;
}

/// Human-readable power-down mode name (shared MCP47xx table):
/// "normal", "1k gnd", "100k gnd", "500k gnd" or "unknown".
/// Complexity: O(1).
pub fn dac_power_down_name(pd: Int) -> Str {
  return _pd_name(pd);
}

/// Byte `index` of a frame widened to 0..255, or -1 when `index` is negative
/// or beyond the last byte. Complexity: O(1).
pub fn dac_frame_byte(data: &Vec[UInt8], index: Int) -> Int {
  if index < 0 || index >= data.len() {
    return -1;
  }
  return _byte(data, index);
}

/// Convert an unsigned DAC code to microvolts:
/// vref_uv * code * gain / 2^bits, one truncating division toward zero.
///
/// Validation order and errors:
///   1. bits outside 8..24 -> "dac: resolution N out of range 8..24";
///   2. vref_uv <= 0 -> "dac: vref N uV must be positive";
///   3. gain < 1 -> "dac: gain N must be at least 1";
///   4. code outside 0..2^bits-1 -> "dac: code N out of range 0..M".
/// Complexity: O(1).
pub fn dac_code_to_uv(code: Int, bits: Int, vref_uv: Int, gain: Int) -> Result[Int, Str] {
  let msg = _code_uv_error("dac", code, bits, vref_uv, gain);
  if msg.len() > 0 {
    return _err_int(msg);
  }
  return _ok_int(_scale_uv(code, bits, vref_uv, gain));
}

// --------------------------------------------------
//  MCP4725: address and frames
// --------------------------------------------------

/// The on-the-wire MCP4725 address byte: `address * 2` with the R/W bit in
/// bit 0 (0 for a write, 1 for a read). Valid addresses are 0x60..0x67
/// (96..103).
///
/// Error case: Err("dac.mcp4725: address N out of range 96..103").
/// Complexity: O(1).
pub fn mcp4725_address_byte(address: Int, read: Bool) -> Result[Int, Str] {
  let msg = _addr_error("dac.mcp4725", address, MCP4725_ADDRESS_BASE, MCP4725_ADDRESS_MAX);
  if msg.len() > 0 {
    return _err_int(msg);
  }
  var b = address * 2;
  if read {
    b = b + 1;
  }
  return _ok_int(b);
}

/// The address byte of an MCP4725 read command (R/W bit set).
///
/// Same validation and error catalog as mcp4725_address_byte.
/// Complexity: O(1).
pub fn mcp4725_read_address_byte(address: Int) -> Result[Int, Str] {
  return mcp4725_address_byte(address, true);
}

/// MCP4725 fast write frame (3 bytes):
///   [address * 2] [0 0 PD1 PD0 D11..D8] [D7..D0].
/// The command bits are 00 (C0 is don't care). The frame is usable only for
/// the first two bytes of a transfer after the address; the address byte is
/// included so the frame can be written to a bus as-is.
///
/// Validation order and errors: address range, code range 0..4095, power-down
/// range 0..3 (see mcp4725_address_byte and the mcp4725 message catalog).
/// Nothing is written on Err. Complexity: O(1).
pub fn mcp4725_fast_frame(address: Int, code: Int, pd: Int) -> Result[Vec[UInt8], Str] {
  let msg = _mcp4725_write_error(address, code, pd);
  if msg.len() > 0 {
    return _err_bytes(msg);
  }
  var out = Vec[UInt8].new();
  out.push((address * 2) as UInt8);
  out.push((_pd_bits(pd) + code / 256) as UInt8);
  out.push((code % 256) as UInt8);
  return _ok_bytes(out);
}

/// MCP4725 write-DAC-register frame (4 bytes):
///   [address * 2] [0 1 0 X X PD1 PD0 X] [D11..D4] [(D3..D0) X X X X].
/// The EEPROM is not affected. Same validation catalog and errors as
/// mcp4725_fast_frame (plus the address byte). Complexity: O(1).
pub fn mcp4725_write_dac_frame(address: Int, code: Int, pd: Int) -> Result[Vec[UInt8], Str] {
  let msg = _mcp4725_write_error(address, code, pd);
  if msg.len() > 0 {
    return _err_bytes(msg);
  }
  var out = Vec[UInt8].new();
  out.push((address * 2) as UInt8);
  out.push((MCP4725_CMD_WRITE_DAC * 32 + (pd / 2) * 4 + (pd % 2) * 2) as UInt8);
  out.push((code / 16) as UInt8);
  out.push(((code % 16) * 16) as UInt8);
  return _ok_bytes(out);
}

/// MCP4725 write-DAC-register-and-EEPROM frame (4 bytes): command bits 011
/// (0x60 + PD), data laid out exactly like mcp4725_write_dac_frame. The
/// EEPROM write takes up to 50 ms during which the part ignores commands.
///
/// Same validation catalog and errors as mcp4725_fast_frame.
/// Complexity: O(1).
pub fn mcp4725_write_eeprom_frame(address: Int, code: Int, pd: Int) -> Result[Vec[UInt8], Str] {
  let msg = _mcp4725_write_error(address, code, pd);
  if msg.len() > 0 {
    return _err_bytes(msg);
  }
  var out = Vec[UInt8].new();
  out.push((address * 2) as UInt8);
  out.push((MCP4725_CMD_WRITE_EEPROM * 32 + (pd / 2) * 4 + (pd % 2) * 2) as UInt8);
  out.push((code / 16) as UInt8);
  out.push(((code % 16) * 16) as UInt8);
  return _ok_bytes(out);
}

// First validation error of an MCP4725 write frame, in the order address,
// code, power-down; "" when every field fits.
fn _mcp4725_write_error(address: Int, code: Int, pd: Int) -> Str {
  let am = _addr_error("dac.mcp4725", address, MCP4725_ADDRESS_BASE, MCP4725_ADDRESS_MAX);
  if am.len() > 0 {
    return am;
  }
  let cm = _code_error("dac.mcp4725", code, MCP4725_FULL_SCALE);
  if cm.len() > 0 {
    return cm;
  }
  return _pd_error("dac.mcp4725", pd);
}

// "" when pd is 0..3, else the range message.
fn _pd_error(prefix: Str, pd: Int) -> Str {
  if pd < 0 || pd > 3 {
    return prefix + ": power-down " + convert.int_to_string(pd) + " out of range 0..3";
  }
  return "";
}

/// Decode an MCP4725 write frame. Three bytes decode as a fast frame; four
/// bytes decode as a write-DAC (0x40) or write-DAC+EEPROM (0x60) frame.
///
/// Decoded fields: address, mode, pd, code. The command byte's don't-care low
/// bits and the fourth byte's low nibble are ignored, as the datasheet
/// specifies.
///
/// Error case (with the offending byte offset):
///   "dac.mcp4725: frame length N is not 3 (fast) or 4 (normal)";
///   "dac.mcp4725: byte 0 is a read address byte (r/w is 1)";
///   "dac.mcp4725: byte 0 address N out of range 96..103";
///   "dac.mcp4725: byte 1 command N is not 2 (write DAC) or 3 (write DAC+EEPROM)".
/// Complexity: O(1).
pub fn mcp4725_decode(data: &Vec[UInt8]) -> Result[Mcp4725Frame, Str] {
  let n = data.len();
  if n == 3 {
    let b0: Int = _byte(data, 0);
    let am = _dec_addr_error("dac.mcp4725", b0, MCP4725_ADDRESS_BASE, MCP4725_ADDRESS_MAX);
    if am.len() > 0 {
      return _err_4725(am);
    }
    let b1: Int = _byte(data, 1);
    let b2: Int = _byte(data, 2);
    let pd = (b1 / 16) % 4;
    let code = (b1 % 16) * 256 + b2;
    return _ok_4725(Mcp4725Frame{ address: b0 / 2; mode: MCP4725_CMD_FAST; pd: pd; code: code; });
  }
  if n == 4 {
    let b0: Int = _byte(data, 0);
    let am = _dec_addr_error("dac.mcp4725", b0, MCP4725_ADDRESS_BASE, MCP4725_ADDRESS_MAX);
    if am.len() > 0 {
      return _err_4725(am);
    }
    let b1: Int = _byte(data, 1);
    let command = (b1 / 32) % 8;
    if command != MCP4725_CMD_WRITE_DAC && command != MCP4725_CMD_WRITE_EEPROM {
      return _err_4725("dac.mcp4725: byte 1 command " + convert.int_to_string(command) + " is not 2 (write DAC) or 3 (write DAC+EEPROM)");
    }
    let b2: Int = _byte(data, 2);
    let b3: Int = _byte(data, 3);
    let pd = (b1 / 2) % 4;
    let code = b2 * 16 + b3 / 16;
    return _ok_4725(Mcp4725Frame{ address: b0 / 2; mode: command; pd: pd; code: code; });
  }
  return _err_4725("dac.mcp4725: frame length " + convert.int_to_string(n) + " is not 3 (fast) or 4 (normal)");
}

// Decode a write address byte at offset 0 and return "" when it is a valid
// write address, else the offset-bearing message. `b0` is the raw byte.
fn _dec_addr_error(prefix: Str, b0: Int, lo: Int, hi: Int) -> Str {
  if b0 % 2 == 1 {
    return prefix + ": byte 0 is a read address byte (r/w is 1)";
  }
  let address = b0 / 2;
  if address < lo || address > hi {
    return prefix + ": byte 0 address " + convert.int_to_string(address) + " out of range " + convert.int_to_string(lo) + ".." + convert.int_to_string(hi);
  }
  return "";
}

/// Human-readable MCP4725 power-down mode name. Complexity: O(1).
pub fn mcp4725_power_down_name(pd: Int) -> Str {
  return _pd_name(pd);
}

/// Resolution of the MCP4725 in bits (12). Complexity: O(1).
pub fn mcp4725_resolution_bits() -> Int {
  return MCP4725_RESOLUTION_BITS;
}

/// Largest MCP4725 input code (4095). Complexity: O(1).
pub fn mcp4725_full_scale() -> Int {
  return MCP4725_FULL_SCALE;
}

/// Convert an MCP4725 input code to microvolts against a positive supply /
/// reference in microvolts: vdd_uv * code / 4096, one truncation. The output
/// range is 0 .. vdd_uv * 4095 / 4096 (full scale minus one LSB).
///
/// Validation order and errors: code range 0..4095 ("dac.mcp4725: code ..."),
/// then vdd_uv > 0 ("dac.mcp4725: vref ... must be positive").
/// Complexity: O(1).
pub fn mcp4725_code_to_uv(code: Int, vdd_uv: Int) -> Result[Int, Str] {
  let cm = _code_error("dac.mcp4725", code, MCP4725_FULL_SCALE);
  if cm.len() > 0 {
    return _err_int(cm);
  }
  let msg = _code_uv_error("dac.mcp4725", code, MCP4725_RESOLUTION_BITS, vdd_uv, 1);
  if msg.len() > 0 {
    return _err_int(msg);
  }
  return _ok_int(_scale_uv(code, MCP4725_RESOLUTION_BITS, vdd_uv, 1));
}

// --------------------------------------------------
//  MCP4728: address helpers
// --------------------------------------------------

/// The on-the-wire MCP4728 address byte: `(0x60 + A2 A1 A0) * 2` with the R/W
/// bit in bit 0. Valid addresses are 0x60..0x67 (96..103).
///
/// Error case: Err("dac.mcp4728: address N out of range 96..103").
/// Complexity: O(1).
pub fn mcp4728_address_byte(address: Int, read: Bool) -> Result[Int, Str] {
  let msg = _addr_error("dac.mcp4728", address, MCP4728_ADDRESS_BASE, MCP4728_ADDRESS_MAX);
  if msg.len() > 0 {
    return _err_int(msg);
  }
  var b = address * 2;
  if read {
    b = b + 1;
  }
  return _ok_int(b);
}

/// Build the 7-bit MCP4728 address from its three programmable EEPROM bits:
/// 0x60 + a2*4 + a1*2 + a0. Only 0/1 are accepted per bit.
///
/// Error case: Err("dac.mcp4728: a2 N is not 0 or 1") for the first offending
/// bit in the order a2, a1, a0. Complexity: O(1).
pub fn mcp4728_address_from_bits(a2: Int, a1: Int, a0: Int) -> Result[Int, Str] {
  let m2 = _bit_error("dac.mcp4728", "a2", a2);
  if m2.len() > 0 {
    return _err_int(m2);
  }
  let m1 = _bit_error("dac.mcp4728", "a1", a1);
  if m1.len() > 0 {
    return _err_int(m1);
  }
  let m0 = _bit_error("dac.mcp4728", "a0", a0);
  if m0.len() > 0 {
    return _err_int(m0);
  }
  return _ok_int(MCP4728_ADDRESS_BASE + a2 * 4 + a1 * 2 + a0);
}

/// Human-readable MCP4728 channel name: "A", "B", "C", "D" or "unknown".
/// Complexity: O(1).
pub fn mcp4728_channel_name(channel: Int) -> Str {
  if channel == MCP4728_CH_A {
    return "A";
  }
  if channel == MCP4728_CH_B {
    return "B";
  }
  if channel == MCP4728_CH_C {
    return "C";
  }
  if channel == MCP4728_CH_D {
    return "D";
  }
  return "unknown";
}

// First validation error of an MCP4728 multi/single write frame, in the order
// address, channel, code, vref, power-down, gain (GX), UDAC; "" when every
// field fits.
fn _mcp4728_write_error(address: Int, channel: Int, code: Int, vref: Int, pd: Int, gain: Int, udac: Int) -> Str {
  let am = _addr_error("dac.mcp4728", address, MCP4728_ADDRESS_BASE, MCP4728_ADDRESS_MAX);
  if am.len() > 0 {
    return am;
  }
  if channel < MCP4728_CH_A || channel > MCP4728_CH_D {
    return "dac.mcp4728: channel " + convert.int_to_string(channel) + " is not 0 (A) .. 3 (D)";
  }
  let cm = _code_error("dac.mcp4728", code, MCP4728_FULL_SCALE);
  if cm.len() > 0 {
    return cm;
  }
  let vm = _bit_error("dac.mcp4728", "vref", vref);
  if vm.len() > 0 {
    return vm;
  }
  let pm = _pd_error("dac.mcp4728", pd);
  if pm.len() > 0 {
    return pm;
  }
  let gm = _bit_error("dac.mcp4728", "gain", gain);
  if gm.len() > 0 {
    return gm;
  }
  return _bit_error("dac.mcp4728", "udac", udac);
}

// The three data bytes that follow the command byte of an MCP4728 multi or
// single write frame: byte 1 selects the channel and UDAC, byte 2 packs
// VREF/PD/GX and D11..D8, byte 3 is D7..D0.
fn _mcp4728_data_bytes(out: &mut Vec[UInt8], channel: Int, code: Int, vref: Int, pd: Int, gain: Int, udac: Int) {
  out.push((64 + channel * 2 + udac) as UInt8);
  out.push((vref * 128 + pd * 32 + gain * 16 + code / 256) as UInt8);
  out.push((code % 256) as UInt8);
}

/// MCP4728 multi-write frame (4 bytes):
///   [addr*2] [0 1 0 0 0 DAC1 DAC0 UDAC] [VREF PD1 PD0 GX D11..D8] [D7..D0].
/// The EEPROM is not affected. `pd` is the two-bit selector (0..3, see the
/// power-down table), `vref` selects internal (1, 2.048 V) or external (0,
/// VDD) reference, `gain` is the GX bit 0 (1x) or 1 (2x), and `udac` is 0 to
/// upload the selected channel or 1 to hold.
///
/// Validation order and errors: address 96..103, channel 0..3, code 0..4095,
/// vref/udac 0..1, power-down 0..3, gain 0..1 (messages carry the family
/// prefix "dac.mcp4728:"). Nothing is written on Err. Complexity: O(1).
pub fn mcp4728_multi_write_frame(address: Int, channel: Int, code: Int, vref: Int, pd: Int, gain: Int, udac: Int) -> Result[Vec[UInt8], Str] {
  let msg = _mcp4728_write_error(address, channel, code, vref, pd, gain, udac);
  if msg.len() > 0 {
    return _err_bytes(msg);
  }
  var out = Vec[UInt8].new();
  out.push((address * 2) as UInt8);
  _mcp4728_data_bytes(&mut out, channel, code, vref, pd, gain, udac);
  return _ok_bytes(out);
}

/// MCP4728 single-write frame (4 bytes): the multi-write layout with command
/// bits W1 W0 = 1 1 (second byte 0x58 | channel*2 | UDAC). This command also
/// writes the channel's EEPROM.
///
/// Same validation catalog and errors as mcp4728_multi_write_frame.
/// Complexity: O(1).
pub fn mcp4728_single_write_frame(address: Int, channel: Int, code: Int, vref: Int, pd: Int, gain: Int, udac: Int) -> Result[Vec[UInt8], Str] {
  let msg = _mcp4728_write_error(address, channel, code, vref, pd, gain, udac);
  if msg.len() > 0 {
    return _err_bytes(msg);
  }
  var out = Vec[UInt8].new();
  out.push((address * 2) as UInt8);
  out.push((88 + channel * 2 + udac) as UInt8);
  out.push((vref * 128 + pd * 32 + gain * 16 + code / 256) as UInt8);
  out.push((code % 256) as UInt8);
  return _ok_bytes(out);
}

/// MCP4728 fast write frame (3 bytes):
///   [addr*2] [X X PD1 PD0 D11..D8] [D7..D0].
/// The fast command carries only the power-down bits and the code; the four
/// channels are written sequentially A..D by sending the 2-byte group three
/// more times (bytes 1..2 of this frame). VREF, gain and UDAC are not
/// writable in fast mode.
///
/// Validation order and errors: address 96..103, code 0..4095, power-down
/// 0..3. Nothing is written on Err. Complexity: O(1).
pub fn mcp4728_fast_frame(address: Int, code: Int, pd: Int) -> Result[Vec[UInt8], Str] {
  let msg = _mcp4728_fast_error(address, code, pd);
  if msg.len() > 0 {
    return _err_bytes(msg);
  }
  var out = Vec[UInt8].new();
  out.push((address * 2) as UInt8);
  out.push((_pd_bits(pd) + code / 256) as UInt8);
  out.push((code % 256) as UInt8);
  return _ok_bytes(out);
}

// First validation error of an MCP4728 fast frame, in the order address,
// code, power-down; "" when every field fits.
fn _mcp4728_fast_error(address: Int, code: Int, pd: Int) -> Str {
  let am = _addr_error("dac.mcp4728", address, MCP4728_ADDRESS_BASE, MCP4728_ADDRESS_MAX);
  if am.len() > 0 {
    return am;
  }
  let cm = _code_error("dac.mcp4728", code, MCP4728_FULL_SCALE);
  if cm.len() > 0 {
    return cm;
  }
  return _pd_error("dac.mcp4728", pd);
}

/// Decode an MCP4728 write frame. Three bytes decode as a fast frame; four
/// bytes decode as a command-type-010 frame whose W1 W0 bits select
/// multi-write (00), sequential write (10) or single write (11). W1 W0 = 01
/// is reserved and rejected.
///
/// Decoded fields: address, mode, channel, code, vref, pd, gain, udac. In a
/// fast frame channel, vref, gain and udac are reported as -1 (not carried by
/// the command) and mode is MCP4728_MODE_FAST.
///
/// Error case (with the offending byte offset):
///   "dac.mcp4728: frame length N is not 3 (fast) or 4 (normal)";
///   "dac.mcp4728: byte 0 ..." (address errors carry the offset);
///   "dac.mcp4728: byte 1 command N is not 2 (010)";
///   "dac.mcp4728: byte 1 write function 01 is reserved".
/// Complexity: O(1).
pub fn mcp4728_decode(data: &Vec[UInt8]) -> Result[Mcp4728Frame, Str] {
  let n = data.len();
  if n == 3 {
    let b0: Int = _byte(data, 0);
    let am = _dec_addr_error("dac.mcp4728", b0, MCP4728_ADDRESS_BASE, MCP4728_ADDRESS_MAX);
    if am.len() > 0 {
      return _err_4728(am);
    }
    let b1: Int = _byte(data, 1);
    let b2: Int = _byte(data, 2);
    let pd = (b1 / 16) % 4;
    let code = (b1 % 16) * 256 + b2;
    return _ok_4728(Mcp4728Frame{ address: b0 / 2; mode: MCP4728_MODE_FAST; channel: -1; code: code; vref: -1; pd: pd; gain: -1; udac: -1; });
  }
  if n == 4 {
    let b0: Int = _byte(data, 0);
    let am = _dec_addr_error("dac.mcp4728", b0, MCP4728_ADDRESS_BASE, MCP4728_ADDRESS_MAX);
    if am.len() > 0 {
      return _err_4728(am);
    }
    let b1: Int = _byte(data, 1);
    let command = (b1 / 32) % 8;
    if command != MCP4725_CMD_WRITE_DAC {
      return _err_4728("dac.mcp4728: byte 1 command " + convert.int_to_string(command) + " is not 2 (010)");
    }
    let w1 = (b1 / 16) % 2;
    let w0 = (b1 / 8) % 2;
    if w1 == 0 && w0 == 1 {
      return _err_4728("dac.mcp4728: byte 1 write function 01 is reserved");
    }
    var mode = MCP4728_MODE_MULTI;
    if w1 == 1 && w0 == 0 {
      mode = MCP4728_MODE_SEQUENTIAL;
    }
    if w1 == 1 && w0 == 1 {
      mode = MCP4728_MODE_SINGLE;
    }
    let channel = (b1 / 2) % 4;
    let udac = b1 % 2;
    let b2: Int = _byte(data, 2);
    let b3: Int = _byte(data, 3);
    let vref = b2 / 128;
    let pd = (b2 / 32) % 4;
    let gain = (b2 / 16) % 2;
    let code = (b2 % 16) * 256 + b3;
    return _ok_4728(Mcp4728Frame{ address: b0 / 2; mode: mode; channel: channel; code: code; vref: vref; pd: pd; gain: gain; udac: udac; });
  }
  return _err_4728("dac.mcp4728: frame length " + convert.int_to_string(n) + " is not 3 (fast) or 4 (normal)");
}

/// Effective reference in microvolts for an MCP4728 channel: the internal
/// 2.048 V reference for vref = 1 (the `vdd_uv` argument is ignored), or the
/// caller's positive VDD for vref = 0.
///
/// Error case: Err("dac.mcp4728: vref N is not 0 (external) or 1 (internal)");
/// Err("dac.mcp4728: external vref N uV must be positive") for vref = 0 with
/// a non-positive VDD. Complexity: O(1).
pub fn mcp4728_reference_uv(vref: Int, vdd_uv: Int) -> Result[Int, Str] {
  if vref < MCP4728_VREF_EXTERNAL || vref > MCP4728_VREF_INTERNAL {
    return _err_int("dac.mcp4728: vref " + convert.int_to_string(vref) + " is not 0 (external) or 1 (internal)");
  }
  if vref == MCP4728_VREF_INTERNAL {
    return _ok_int(MCP4728_INTERNAL_REF_UV);
  }
  if vdd_uv <= 0 {
    return _err_int("dac.mcp4728: external vref " + convert.int_to_string(vdd_uv) + " uV must be positive");
  }
  return _ok_int(vdd_uv);
}

/// Effective output gain multiplier of an MCP4728 channel: with the internal
/// reference the GX bit selects 1x (gain = 0) or 2x (gain = 1); with the
/// external VDD reference the GX bit is ignored by the silicon and the gain is
/// always 1.
///
/// Error case: Err("dac.mcp4728: vref N ...") for a bad selector;
/// Err("dac.mcp4728: gain N is not 0 (1x) or 1 (2x)") for a bad GX bit.
/// Complexity: O(1).
pub fn mcp4728_effective_gain(vref: Int, gain: Int) -> Result[Int, Str] {
  if vref < MCP4728_VREF_EXTERNAL || vref > MCP4728_VREF_INTERNAL {
    return _err_int("dac.mcp4728: vref " + convert.int_to_string(vref) + " is not 0 (external) or 1 (internal)");
  }
  if gain < MCP4728_GAIN_1X || gain > MCP4728_GAIN_2X {
    return _err_int("dac.mcp4728: gain " + convert.int_to_string(gain) + " is not 0 (1x) or 1 (2x)");
  }
  if vref == MCP4728_VREF_EXTERNAL {
    return _ok_int(1);
  }
  return _ok_int(1 + gain);
}

/// Convert an MCP4728 input code to microvolts for one channel:
/// reference_uv * code * effective_gain / 4096, one truncating division. With
/// the internal 2.048 V reference and gain 2 the full scale is 4.095 V minus
/// one LSB; with the external VDD reference the gain is forced to 1 by the
/// silicon even when the GX bit is set.
///
/// Validation order and errors: code 0..4095, vref 0/1, gain bit 0/1, then a
/// positive VDD when the external reference is selected.
/// Complexity: O(1).
pub fn mcp4728_code_to_uv(code: Int, vref: Int, gain: Int, vdd_uv: Int) -> Result[Int, Str] {
  let cm = _code_error("dac.mcp4728", code, MCP4728_FULL_SCALE);
  if cm.len() > 0 {
    return _err_int(cm);
  }
  let rr = mcp4728_reference_uv(vref, vdd_uv);
  if !rr.is_ok {
    return _err_int(rr.error);
  }
  let gr = mcp4728_effective_gain(vref, gain);
  if !gr.is_ok {
    return _err_int(gr.error);
  }
  let ref_uv: Int = rr.value;
  let effective: Int = gr.value;
  return _ok_int(_scale_uv(code, MCP4728_RESOLUTION_BITS, ref_uv, effective));
}

/// Human-readable MCP4728 power-down mode name. Complexity: O(1).
pub fn mcp4728_power_down_name(pd: Int) -> Str {
  return _pd_name(pd);
}

/// Resolution of the MCP4728 in bits (12). Complexity: O(1).
pub fn mcp4728_resolution_bits() -> Int {
  return MCP4728_RESOLUTION_BITS;
}

/// Largest MCP4728 input code (4095). Complexity: O(1).
pub fn mcp4728_full_scale() -> Int {
  return MCP4728_FULL_SCALE;
}

// --------------------------------------------------
//  MCP4921/MCP4922: SPI frame codec
// --------------------------------------------------

/// First validation error of an MCP492x frame, in the order code, BUF, gain,
/// SHDN; "" when every field fits. The channel is validated by the caller.
/// `prefix` is the family message prefix ("dac.mcp4921" or "dac.mcp4922").
fn _mcp492x_error(prefix: Str, code: Int, buf: Int, gain: Int, shdn: Int) -> Str {
  let cm = _code_error(prefix, code, MCP492X_FULL_SCALE);
  if cm.len() > 0 {
    return cm;
  }
  if buf < MCP492X_BUF_UNBUFFERED || buf > MCP492X_BUF_BUFFERED {
    return prefix + ": buf " + convert.int_to_string(buf) + " is not 0 (unbuffered) or 1 (buffered)";
  }
  if gain != MCP492X_GAIN_1X && gain != MCP492X_GAIN_2X {
    return prefix + ": gain " + convert.int_to_string(gain) + " is not 1 (1x) or 2 (2x)";
  }
  if shdn < MCP492X_SHDN_HIGH_Z || shdn > MCP492X_SHDN_ACTIVE {
    return prefix + ": shdn " + convert.int_to_string(shdn) + " is not 0 (high-Z) or 1 (active)";
  }
  return "";
}

// The raw 16-bit MCP492x word for a validated channel and fields:
// A/B*32768 + BUF*16384 + GA*8192 + SHDN*4096 + code, with GA=1 for 1x and
// GA=0 for 2x.
fn _mcp492x_word(channel: Int, code: Int, buf: Int, gain: Int, shdn: Int) -> Int {
  var ga = MCP492X_GA_BIT_2X;
  if gain == MCP492X_GAIN_1X {
    ga = MCP492X_GA_BIT_1X;
  }
  return channel * 32768 + buf * 16384 + ga * 8192 + shdn * 4096 + code;
}

/// MCP4922 SPI write frame (2 bytes, MSB first):
///   [A/B BUF GA SHDN D11..D8] [D7..D0].
/// `channel` selects DAC A (0) or DAC B (1); BUF enables the reference input
/// buffer; `gain` is the output multiplier 1 or 2 (GA is 1 for 1x and 0 for
/// 2x); `shdn` is 1 for an active output and 0 for the high-impedance
/// shutdown state (the hardware SHDN pin is active low).
///
/// Validation order and errors: channel 0/1 ("dac.mcp4922: channel N is not 0
/// (DAC A) or 1 (DAC B)"), then code, BUF, gain and SHDN (messages carry the
/// "dac.mcp4922:" prefix). Nothing is written on Err. Complexity: O(1).
pub fn mcp4922_frame(channel: Int, code: Int, buf: Int, gain: Int, shdn: Int) -> Result[Vec[UInt8], Str] {
  if channel < MCP492X_CH_A || channel > MCP492X_CH_B {
    return _err_bytes("dac.mcp4922: channel " + convert.int_to_string(channel) + " is not 0 (DAC A) or 1 (DAC B)");
  }
  let msg = _mcp492x_error("dac.mcp4922", code, buf, gain, shdn);
  if msg.len() > 0 {
    return _err_bytes(msg);
  }
  let word = _mcp492x_word(channel, code, buf, gain, shdn);
  var out = Vec[UInt8].new();
  out.push((word / 256) as UInt8);
  out.push((word % 256) as UInt8);
  return _ok_bytes(out);
}

/// MCP4921 SPI write frame (2 bytes): the same layout as mcp4922_frame with
/// the channel forced to DAC A. The SHDN register bit exists on the
/// single-channel part even though only the MCP4922 brings the pin out.
///
/// Same validation catalog and errors as mcp4922_frame, under the
/// "dac.mcp4921:" prefix. Complexity: O(1).
pub fn mcp4921_frame(code: Int, buf: Int, gain: Int, shdn: Int) -> Result[Vec[UInt8], Str] {
  let msg = _mcp492x_error("dac.mcp4921", code, buf, gain, shdn);
  if msg.len() > 0 {
    return _err_bytes(msg);
  }
  let word = _mcp492x_word(MCP492X_CH_A, code, buf, gain, shdn);
  var out = Vec[UInt8].new();
  out.push((word / 256) as UInt8);
  out.push((word % 256) as UInt8);
  return _ok_bytes(out);
}

/// Decode a two-byte MCP492x SPI write frame. Decoded fields: channel, buf,
/// gain (1 or 2, decoded from GA), shdn and code.
///
/// Error case: Err("dac.mcp492x: frame needs 2 bytes, have N") when the buffer
/// is not exactly two bytes long. Complexity: O(1).
pub fn mcp492x_decode(data: &Vec[UInt8]) -> Result[Mcp492xFrame, Str] {
  if data.len() != 2 {
    return _err_492x("dac.mcp492x: frame needs 2 bytes, have " + convert.int_to_string(data.len()));
  }
  let hi: Int = _byte(data, 0);
  let lo: Int = _byte(data, 1);
  let channel = hi / 128;
  let buf = (hi / 64) % 2;
  let ga = (hi / 32) % 2;
  let shdn = (hi / 16) % 2;
  var gain = MCP492X_GAIN_2X;
  if ga == MCP492X_GA_BIT_1X {
    gain = MCP492X_GAIN_1X;
  }
  let code = (hi % 16) * 256 + lo;
  return _ok_492x(Mcp492xFrame{ channel: channel; buf: buf; gain: gain; shdn: shdn; code: code; });
}

/// Decode a two-byte MCP4921 SPI write frame: mcp492x_decode plus a rejection
/// of DAC B, which the single-channel part does not have.
///
/// Error case: the mcp492x_decode length error, or
/// "dac.mcp4921: channel B is not present on the single-channel part".
/// Complexity: O(1).
pub fn mcp4921_decode(data: &Vec[UInt8]) -> Result[Mcp492xFrame, Str] {
  let r = mcp492x_decode(data);
  if !r.is_ok {
    return _err_492x(r.error);
  }
  let f: Mcp492xFrame = r.value;
  if f.channel != MCP492X_CH_A {
    return _err_492x("dac.mcp4921: channel B is not present on the single-channel part");
  }
  return _ok_492x(f);
}

/// Human-readable MCP492x channel name: "A", "B" or "unknown".
/// Complexity: O(1).
pub fn mcp492x_channel_name(channel: Int) -> Str {
  if channel == MCP492X_CH_A {
    return "A";
  }
  if channel == MCP492X_CH_B {
    return "B";
  }
  return "unknown";
}

/// The GA register bit for a gain multiplier: 1 for 1x, 0 for 2x, -1 for any
/// other multiplier. Complexity: O(1).
pub fn mcp492x_ga_bit(gain: Int) -> Int {
  if gain == MCP492X_GAIN_1X {
    return MCP492X_GA_BIT_1X;
  }
  if gain == MCP492X_GAIN_2X {
    return MCP492X_GA_BIT_2X;
  }
  return -1;
}

/// The SHDN register bit for a shutdown request: 1 when the output is active
/// (`shutdown` false), 0 when the output is high impedance (`shutdown` true).
/// The hardware SHDN pin is active low; the register bit is active high.
/// Complexity: O(1).
pub fn mcp492x_shutdown_bit(shutdown: Bool) -> Int {
  if shutdown {
    return MCP492X_SHDN_HIGH_Z;
  }
  return MCP492X_SHDN_ACTIVE;
}

/// Resolution of the MCP4921/MCP4922 in bits (12). Complexity: O(1).
pub fn mcp492x_resolution_bits() -> Int {
  return MCP492X_RESOLUTION_BITS;
}

/// Largest MCP492x input code (4095). Complexity: O(1).
pub fn mcp492x_full_scale() -> Int {
  return MCP492X_FULL_SCALE;
}

/// Convert an MCP492x input code to microvolts against a positive external
/// reference: vref_uv * code * gain / 4096, one truncating division. `gain`
/// is the output multiplier 1 or 2.
///
/// Validation order and errors: code 0..4095, then gain 1/2, then vref_uv > 0
/// under the "dac.mcp492x:" prefix. Complexity: O(1).
pub fn mcp492x_code_to_uv(code: Int, vref_uv: Int, gain: Int) -> Result[Int, Str] {
  let cm = _code_error("dac.mcp492x", code, MCP492X_FULL_SCALE);
  if cm.len() > 0 {
    return _err_int(cm);
  }
  if gain != MCP492X_GAIN_1X && gain != MCP492X_GAIN_2X {
    return _err_int("dac.mcp492x: gain " + convert.int_to_string(gain) + " is not 1 (1x) or 2 (2x)");
  }
  if vref_uv <= 0 {
    return _err_int("dac.mcp492x: vref " + convert.int_to_string(vref_uv) + " uV must be positive");
  }
  return _ok_int(_scale_uv(code, MCP492X_RESOLUTION_BITS, vref_uv, gain));
}
