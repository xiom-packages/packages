// XIOM -- xiom.spi: SPI transfer codec (modes, prescaler, bit order, events)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) codec for SPI (Serial Peripheral Interface) transfers.
// A transfer is the plain SpiTransfer struct: a SpiConfig (mode, word size,
// bit order), the chip-select line, the MOSI byte stream (tx) and the MISO
// byte stream (rx). spi_encode maps a transfer to a self-describing
// event/byte stream and spi_decode maps the stream back; decode errors carry
// the byte offset where decoding failed, encode errors carry offset -1 (the
// failure is in an input field, not in a stream).
//
// Event stream (full byte-level description in SPEC.md):
//
//   CONFIG      01 mode word_size bit_order   4 bytes; exactly the first event
//   CS_ASSERT   02 line                       chip select driven low
//   TX          04 byte                       one MOSI byte
//   RX          05 byte                       one MISO byte, after its TX
//   CS_DEASSERT 03 line                       chip select released high
//   END         06                            1 byte; exactly the last event
//
// A transfer with cs == -1 (3-wire, no chip select) omits both CS events.
// rx is either empty (MISO not captured) or exactly tx.len() bytes, in which
// case each RX event directly follows its TX event. Every multi-byte free
// integer field is one byte, so no endianness is involved anywhere.
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no methods, no lambdas, no Vec[fn] dispatch and no
//     Vec[StructType]; every byte read from a Vec[UInt8] is widened with
//     `(x as Int) & 0xFF` before entering Int arithmetic;
//   * Ok/Err construction is confined to the tiny leaf helpers _ok_*/_err_*
//     below (constructing Results directly inside other functions
//     miscompiles);
//   * Vec element reads are bound to typed locals (`let x: Int = v[i]`);
//   * no Str value is ever compared with `==` in this module (BUG 17);
//   * no `&struct.field` is passed as a `&Vec[UInt8]` parameter (that yields
//     an empty vector): fields are bound to typed locals first;
//   * all shifts are written as multiplication/division by powers of two,
//     and all bit tests use `% 2` on non-negative Ints.

module xiom.spi

/// SPI configuration of a transfer. `mode` is 0..3 with CPOL = mode / 2 and
/// CPHA = mode % 2; `word_size` is the number of bits per word, 4..16;
/// `bit_order` is 0 for MSB-first or 1 for LSB-first.
pub type SpiConfig = {
  mode: Int;
  word_size: Int;
  bit_order: Int;
}

/// A full-duplex SPI transfer. `config` carries mode, word size and bit
/// order; `cs` is the chip-select line 0..7 or -1 for no chip select;
/// `tx` is the MOSI byte stream; `rx` is the MISO byte stream, either empty
/// (not captured) or exactly as long as `tx`. The clocked bit stream spans
/// the tx bytes in order; it must contain a whole number of `word_size`-bit
/// words in the configured bit order.
pub type SpiTransfer = {
  config: SpiConfig;
  cs: Int;
  tx: Vec[UInt8];
  rx: Vec[UInt8];
}

/// A codec error. `offset` is the byte offset of the offending event in the
/// stream for decode errors, or -1 when the error concerns an encode input
/// field (there is no stream position yet). `message` is a stable lowercase
/// "spi:" text from the catalog in SPEC.md.
pub type SpiError = {
  offset: Int;
  message: Str;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[SpiConfig, SpiError].
fn _ok_cfg(v: SpiConfig) -> Result[SpiConfig, SpiError] {
  return Ok(v);
}

// Err(offset, message) for Result[SpiConfig, SpiError].
fn _err_cfg(offset: Int, message: Str) -> Result[SpiConfig, SpiError] {
  let e = SpiError{ offset: offset; message: message; };
  return Err(e);
}

// Ok(v) for Result[SpiTransfer, SpiError].
fn _ok_transfer(v: SpiTransfer) -> Result[SpiTransfer, SpiError] {
  return Ok(v);
}

// Err(offset, message) for Result[SpiTransfer, SpiError].
fn _err_transfer(offset: Int, message: Str) -> Result[SpiTransfer, SpiError] {
  let e = SpiError{ offset: offset; message: message; };
  return Err(e);
}

// Ok(v) for Result[Vec[UInt8], SpiError].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], SpiError] {
  return Ok(v);
}

// Err(offset, message) for Result[Vec[UInt8], SpiError].
fn _err_bytes(offset: Int, message: Str) -> Result[Vec[UInt8], SpiError] {
  let e = SpiError{ offset: offset; message: message; };
  return Err(e);
}

// Ok(()) for Result[Unit, SpiError].
fn _ok_unit() -> Result[Unit, SpiError] {
  return Ok(());
}

// Err(offset, message) for Result[Unit, SpiError].
fn _err_unit(offset: Int, message: Str) -> Result[Unit, SpiError] {
  let e = SpiError{ offset: offset; message: message; };
  return Err(e);
}

// --------------------------------------------------
//  Internal byte and bit helpers
// --------------------------------------------------

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// 2 raised to `k` for 0 <= k <= 16; callers guarantee the range.
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Bit `bit` (0 = first clocked) of `data` as 0 or 1. In MSB-first order the
// first clocked bit of a byte is bit 7 and the last is bit 0; in LSB-first
// order the first is bit 0 and the last is bit 7. Callers guarantee
// `bit < data.len() * 8`.
fn _bit_at(data: &Vec[UInt8], bit: Int, msb_first: Bool) -> Int {
  let b: Int = _byte(data, bit / 8);
  let k = bit % 8;
  if msb_first {
    return (b / _pow2(7 - k)) % 2;
  }
  return (b / _pow2(k)) % 2;
}

// Copy of `v` as a fresh vector.
fn _copy_bytes(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// Byte equality of two vectors.
fn _bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Modes (CPOL/CPHA)
// --------------------------------------------------

/// True when `mode` is one of the four standard SPI modes 0..3.
/// Complexity: O(1).
pub fn spi_mode_valid(mode: Int) -> Bool {
  return mode >= 0 && mode <= 3;
}

/// Clock polarity of `mode`: 0 for modes 0/1, 1 for modes 2/3, -1 for an
/// invalid mode. Complexity: O(1).
pub fn spi_cpol(mode: Int) -> Int {
  if !spi_mode_valid(mode) {
    return -1;
  }
  return mode / 2;
}

/// Clock phase of `mode`: 0 for modes 0/2, 1 for modes 1/3, -1 for an
/// invalid mode. Complexity: O(1).
pub fn spi_cpha(mode: Int) -> Int {
  if !spi_mode_valid(mode) {
    return -1;
  }
  return mode % 2;
}

/// Mode number for a (CPOL, CPHA) pair, both 0 or 1; -1 when either input
/// is outside 0..1. Inverse of spi_cpol/spi_cpha.
/// Complexity: O(1).
pub fn spi_mode_of(cpol: Int, cpha: Int) -> Int {
  if cpol < 0 || cpol > 1 {
    return -1;
  }
  if cpha < 0 || cpha > 1 {
    return -1;
  }
  return cpol * 2 + cpha;
}

/// Human-readable mode name: "CPOL=0 CPHA=0" ... "CPOL=1 CPHA=1", or
/// "invalid mode" for a value outside 0..3. Complexity: O(1).
pub fn spi_mode_name(mode: Int) -> Str {
  if mode == 0 {
    return "CPOL=0 CPHA=0";
  }
  if mode == 1 {
    return "CPOL=0 CPHA=1";
  }
  if mode == 2 {
    return "CPOL=1 CPHA=0";
  }
  if mode == 3 {
    return "CPOL=1 CPHA=1";
  }
  return "invalid mode";
}

/// The mode table as 8 Ints: for mode m, entry 2*m is its CPOL and entry
/// 2*m+1 its CPHA. Always [0,0, 0,1, 1,0, 1,1]. Complexity: O(1).
pub fn spi_mode_table() -> Vec[Int] {
  var v = Vec[Int].new();
  var m = 0;
  while m < 4 {
    v.push(spi_cpol(m));
    v.push(spi_cpha(m));
    m = m + 1;
  }
  return v;
}

// --------------------------------------------------
//  Bit order and word size
// --------------------------------------------------

/// True when `order` is 0 (MSB-first) or 1 (LSB-first).
/// Complexity: O(1).
pub fn spi_bit_order_valid(order: Int) -> Bool {
  return order == 0 || order == 1;
}

/// "MSB-first" for 0, "LSB-first" for 1, "invalid" otherwise.
/// Complexity: O(1).
pub fn spi_bit_order_name(order: Int) -> Str {
  if order == 0 {
    return "MSB-first";
  }
  if order == 1 {
    return "LSB-first";
  }
  return "invalid";
}

/// True when `word_size` is a supported word width 4..16 bits.
/// Complexity: O(1).
pub fn spi_word_size_valid(word_size: Int) -> Bool {
  return word_size >= 4 && word_size <= 16;
}

/// All-ones mask for a `word_size`-bit word: 2^word_size - 1 (15 for 4 bits,
/// 255 for 8, 65535 for 16); -1 for an invalid word size.
/// Complexity: O(1).
pub fn spi_word_mask(word_size: Int) -> Int {
  if !spi_word_size_valid(word_size) {
    return -1;
  }
  return _pow2(word_size) - 1;
}

// --------------------------------------------------
//  Chip select
// --------------------------------------------------

/// True when `cs` is a chip-select line 0..7 or -1 (no chip select).
/// Complexity: O(1).
pub fn spi_cs_valid(cs: Int) -> Bool {
  return cs >= -1 && cs <= 7;
}

/// "cs0" .. "cs7" for a line, "none" for -1, "invalid" otherwise.
/// Complexity: O(1).
pub fn spi_cs_name(cs: Int) -> Str {
  if cs == -1 {
    return "none";
  }
  if cs == 0 {
    return "cs0";
  }
  if cs == 1 {
    return "cs1";
  }
  if cs == 2 {
    return "cs2";
  }
  if cs == 3 {
    return "cs3";
  }
  if cs == 4 {
    return "cs4";
  }
  if cs == 5 {
    return "cs5";
  }
  if cs == 6 {
    return "cs6";
  }
  if cs == 7 {
    return "cs7";
  }
  return "invalid";
}

/// Logic level a chip-select line is driven to: 0 (low) while asserted,
/// 1 (high) while idle, -1 when `cs` is -1 (no line) or invalid. Chip-select
/// lines are active-low. Complexity: O(1).
pub fn spi_cs_line_level(cs: Int, asserted: Bool) -> Int {
  if !spi_cs_valid(cs) {
    return -1;
  }
  if cs == -1 {
    return -1;
  }
  if asserted {
    return 0;
  }
  return 1;
}

/// The level of an asserted chip-select line: 0 (active-low).
/// Complexity: O(1).
pub fn spi_cs_assert_level() -> Int {
  return 0;
}

/// The level of a deasserted (idle) chip-select line: 1 (high).
/// Complexity: O(1).
pub fn spi_cs_idle_level() -> Int {
  return 1;
}

// --------------------------------------------------
//  Clock prescaler table
// --------------------------------------------------

/// Number of prescaler table entries (16). Complexity: O(1).
pub fn spi_prescaler_count() -> Int {
  return 16;
}

/// The prescaler divider table: index i maps to 2^(i+1), so entry 0 is 2,
/// entry 1 is 4 and entry 15 is 65536. Clock = bus frequency / divider.
/// Complexity: O(1).
pub fn spi_prescaler_table() -> Vec[Int] {
  var v = Vec[Int].new();
  var d = 2;
  var i = 0;
  while i < 16 {
    v.push(d);
    d = d * 2;
    i = i + 1;
  }
  return v;
}

/// Divider at prescaler `index` (0..15): 2^(index+1); -1 when the index is
/// outside 0..15. Complexity: O(1).
pub fn spi_clock_divider(index: Int) -> Int {
  let table = spi_prescaler_table();
  if index < 0 || index >= table.len() {
    return -1;
  }
  let d: Int = table[index];
  return d;
}

/// Table index whose divider is exactly `divider` (a power of two in
/// 2..65536); -1 for any other value. Inverse of spi_clock_divider.
/// Complexity: O(1).
pub fn spi_divider_index(divider: Int) -> Int {
  let table = spi_prescaler_table();
  var i = 0;
  while i < table.len() {
    let d: Int = table[i];
    if d == divider {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// SPI clock in Hz for a bus of `bus_hz` using prescaler `index`: integer
/// division (floor), or -1 when `bus_hz` is not positive or the index is
/// outside 0..15. Complexity: O(1).
pub fn spi_clock_hz(bus_hz: Int, index: Int) -> Int {
  if bus_hz <= 0 {
    return -1;
  }
  let d = spi_clock_divider(index);
  if d <= 0 {
    return -1;
  }
  return bus_hz / d;
}

/// Smallest prescaler index whose clock does not exceed `max_hz`, i.e. the
/// first index i with bus_hz / divider(i) <= max_hz; -1 when `bus_hz` or
/// `max_hz` is not positive or even index 15 is still too fast.
/// Complexity: O(1).
pub fn spi_prescaler_for(bus_hz: Int, max_hz: Int) -> Int {
  if bus_hz <= 0 || max_hz <= 0 {
    return -1;
  }
  let count = spi_prescaler_count();
  var i = 0;
  while i < count {
    let d: Int = spi_clock_divider(i);
    if d > 0 && bus_hz / d <= max_hz {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Event stream vocabulary
// --------------------------------------------------

/// Human-readable name of a stream event type: "CONFIG", "CS_ASSERT",
/// "CS_DEASSERT", "TX", "RX", "END", or "unknown".
/// Complexity: O(1).
pub fn spi_event_name(event: Int) -> Str {
  if event == 1 {
    return "CONFIG";
  }
  if event == 2 {
    return "CS_ASSERT";
  }
  if event == 3 {
    return "CS_DEASSERT";
  }
  if event == 4 {
    return "TX";
  }
  if event == 5 {
    return "RX";
  }
  if event == 6 {
    return "END";
  }
  return "unknown";
}

/// Encoded size in bytes of a stream event: 4 for CONFIG, 2 for CS_ASSERT,
/// CS_DEASSERT, TX and RX, 1 for END, -1 for an unknown event type.
/// Complexity: O(1).
pub fn spi_event_size(event: Int) -> Int {
  if event == 1 {
    return 4;
  }
  if event == 6 {
    return 1;
  }
  if event == 2 || event == 3 || event == 4 || event == 5 {
    return 2;
  }
  return -1;
}

// --------------------------------------------------
//  Validation and construction
// --------------------------------------------------

/// Validate a transfer, in this order: mode 0..3, word size 4..16, bit order
/// 0/1, chip select -1..7, then rx empty or rx.len() == tx.len(), then the
/// tx bit count (8 * tx.len()) divisible by the word size.
///
/// Returns: Ok(()) for a canonical transfer.
/// Error case: with offset -1, Err("spi: invalid mode"), Err("spi: invalid
/// word size"), Err("spi: invalid bit order"), Err("spi: invalid chip
/// select") or Err("spi: length mismatch"). Complexity: O(1).
pub fn spi_validate(t: &SpiTransfer) -> Result[Unit, SpiError] {
  let mode: Int = t.config.mode;
  let word_size: Int = t.config.word_size;
  let bit_order: Int = t.config.bit_order;
  if !spi_mode_valid(mode) {
    return _err_unit(-1, "spi: invalid mode");
  }
  if !spi_word_size_valid(word_size) {
    return _err_unit(-1, "spi: invalid word size");
  }
  if !spi_bit_order_valid(bit_order) {
    return _err_unit(-1, "spi: invalid bit order");
  }
  let cs: Int = t.cs;
  if !spi_cs_valid(cs) {
    return _err_unit(-1, "spi: invalid chip select");
  }
  let tx: Vec[UInt8] = t.tx;
  let rx: Vec[UInt8] = t.rx;
  if rx.len() > 0 && rx.len() != tx.len() {
    return _err_unit(-1, "spi: length mismatch");
  }
  if (tx.len() * 8) % word_size != 0 {
    return _err_unit(-1, "spi: length mismatch");
  }
  return _ok_unit();
}

/// Build a config from three fields, validating mode 0..3, word size 4..16
/// and bit order 0/1 (same offset -1 errors as spi_validate).
/// Complexity: O(1).
pub fn spi_config_new(mode: Int, word_size: Int, bit_order: Int) -> Result[SpiConfig, SpiError] {
  if !spi_mode_valid(mode) {
    return _err_cfg(-1, "spi: invalid mode");
  }
  if !spi_word_size_valid(word_size) {
    return _err_cfg(-1, "spi: invalid word size");
  }
  if !spi_bit_order_valid(bit_order) {
    return _err_cfg(-1, "spi: invalid bit order");
  }
  return _ok_cfg(SpiConfig{ mode: mode; word_size: word_size; bit_order: bit_order; });
}

/// Build a transfer from a config, a chip-select line and two byte streams,
/// copying both buffers, then run spi_validate. `rx` may be empty or exactly
/// tx.len() bytes.
///
/// Returns: Ok(transfer) owning copies of `tx` and `rx`.
/// Error case: the spi_validate catalog, with offset -1.
/// Complexity: O(tx.len() + rx.len()).
pub fn spi_transfer_new(cfg: &SpiConfig, cs: Int, tx: &Vec[UInt8], rx: &Vec[UInt8]) -> Result[SpiTransfer, SpiError] {
  let mode: Int = cfg.mode;
  let word_size: Int = cfg.word_size;
  let bit_order: Int = cfg.bit_order;
  let c = SpiConfig{ mode: mode; word_size: word_size; bit_order: bit_order; };
  let tx_copy = _copy_bytes(tx);
  let rx_copy = _copy_bytes(rx);
  let out = SpiTransfer{ config: c; cs: cs; tx: tx_copy; rx: rx_copy; };
  let vr = spi_validate(&out);
  if !vr.is_ok {
    let e: SpiError = vr.error;
    let off: Int = e.offset;
    let msg: Str = e.message;
    return _err_transfer(off, msg);
  }
  return _ok_transfer(out);
}

/// Build a tx-only 8-bit MSB-first transfer: config mode 0..3 / word size 8
/// / bit order 0, empty rx. The convenience form of the "mode, cs, tx bytes"
/// transfer.
///
/// Returns: Ok(transfer).
/// Error case: the spi_validate catalog, with offset -1.
/// Complexity: O(tx.len()).
pub fn spi_transfer(mode: Int, cs: Int, tx: &Vec[UInt8]) -> Result[SpiTransfer, SpiError] {
  let c = SpiConfig{ mode: mode; word_size: 8; bit_order: 0; };
  var empty = Vec[UInt8].new();
  return spi_transfer_new(&c, cs, tx, &empty);
}

// --------------------------------------------------
//  Encode
// --------------------------------------------------

/// Encode a transfer into a fresh event stream (layout in the module header
/// and SPEC.md): CONFIG, optional CS_ASSERT, the TX/RX byte events, optional
/// CS_DEASSERT, END. With an empty rx only TX events are written; otherwise
/// each RX event follows its TX event.
///
/// The transfer is validated first, so an invalid transfer is an Err with
/// offset -1 and nothing is produced.
/// Complexity: O(tx.len()).
pub fn spi_encode(t: &SpiTransfer) -> Result[Vec[UInt8], SpiError] {
  let vr = spi_validate(t);
  if !vr.is_ok {
    let e: SpiError = vr.error;
    let off: Int = e.offset;
    let msg: Str = e.message;
    return _err_bytes(off, msg);
  }
  let mode: Int = t.config.mode;
  let word_size: Int = t.config.word_size;
  let bit_order: Int = t.config.bit_order;
  let cs: Int = t.cs;
  let tx: Vec[UInt8] = t.tx;
  let rx: Vec[UInt8] = t.rx;
  var out = Vec[UInt8].new();
  out.push(1 as UInt8);
  out.push(mode as UInt8);
  out.push(word_size as UInt8);
  out.push(bit_order as UInt8);
  if cs >= 0 {
    out.push(2 as UInt8);
    out.push(cs as UInt8);
  }
  var i = 0;
  while i < tx.len() {
    out.push(4 as UInt8);
    out.push(tx[i]);
    if rx.len() > 0 {
      out.push(5 as UInt8);
      out.push(rx[i]);
    }
    i = i + 1;
  }
  if cs >= 0 {
    out.push(3 as UInt8);
    out.push(cs as UInt8);
  }
  out.push(6 as UInt8);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Decode
// --------------------------------------------------

/// Decode an event stream back into a transfer, in this fixed order:
/// the stream must start with a complete CONFIG event; mode, word size and
/// bit order are validated at their own offsets 1, 2 and 3; an optional
/// CS_ASSERT learns the chip-select line; then TX/RX events accumulate the
/// two streams until the optional CS_DEASSERT and the final END; bytes after
/// END are rejected; at END the stream must contain a whole number of words
/// and rx must be empty or as long as tx.
///
/// Error case (offset is the byte the decoder was reading, or the offset of
/// the offending field/event; when the buffer ends mid-parse the offset is
/// the first missing byte, so it can equal stream.len()):
///   Err("spi: truncated stream")  -- buffer ended before a byte was read
///   Err("spi: missing config")    -- first byte is not 0x01
///   Err("spi: invalid mode")      -- CONFIG mode > 3, at offset 1
///   Err("spi: invalid word size") -- CONFIG word size outside 4..16, at 2
///   Err("spi: invalid bit order") -- CONFIG bit order > 1, at offset 3
///   Err("spi: unknown event")     -- event type not in 0x01..0x06
///   Err("spi: unexpected event")  -- CONFIG/CS_ASSERT in the wrong place
///   Err("spi: invalid chip select") -- CS line > 7
///   Err("spi: chip select not asserted") -- CS_DEASSERT without CS_ASSERT
///   Err("spi: chip select mismatch") -- CS_DEASSERT line != CS_ASSERT line
///   Err("spi: cs left asserted")  -- END while the line is still asserted
///   Err("spi: length mismatch")   -- extra RX, rx != tx count, or tx bits
///                                    not a whole number of words, at END
///   Err("spi: trailing bytes")    -- bytes after the END event
/// Complexity: O(stream.len()).
pub fn spi_decode(stream: &Vec[UInt8]) -> Result[SpiTransfer, SpiError] {
  let n = stream.len();
  if n == 0 {
    return _err_transfer(0, "spi: truncated stream");
  }
  if _byte(stream, 0) != 1 {
    return _err_transfer(0, "spi: missing config");
  }
  if n < 4 {
    return _err_transfer(n, "spi: truncated stream");
  }
  let mode: Int = _byte(stream, 1);
  let word_size: Int = _byte(stream, 2);
  let bit_order: Int = _byte(stream, 3);
  if mode > 3 {
    return _err_transfer(1, "spi: invalid mode");
  }
  if word_size < 4 || word_size > 16 {
    return _err_transfer(2, "spi: invalid word size");
  }
  if bit_order > 1 {
    return _err_transfer(3, "spi: invalid bit order");
  }
  var pos = 4;
  var cs = -1;
  var cs_open = false;
  var closed = false;
  if pos < n {
    if _byte(stream, pos) == 2 {
      if pos + 1 >= n {
        return _err_transfer(pos + 1, "spi: truncated stream");
      }
      let line: Int = _byte(stream, pos + 1);
      if line > 7 {
        return _err_transfer(pos + 1, "spi: invalid chip select");
      }
      cs = line;
      cs_open = true;
      pos = pos + 2;
    }
  }
  var tx = Vec[UInt8].new();
  var rx = Vec[UInt8].new();
  var ended = false;
  while !ended {
    if pos >= n {
      return _err_transfer(n, "spi: truncated stream");
    }
    let event: Int = _byte(stream, pos);
    if event == 4 {
      if closed {
        return _err_transfer(pos, "spi: unexpected event");
      }
      if pos + 1 >= n {
        return _err_transfer(pos + 1, "spi: truncated stream");
      }
      tx.push(stream[pos + 1]);
      pos = pos + 2;
    } elif event == 5 {
      if closed {
        return _err_transfer(pos, "spi: unexpected event");
      }
      if pos + 1 >= n {
        return _err_transfer(pos + 1, "spi: truncated stream");
      }
      if rx.len() >= tx.len() {
        return _err_transfer(pos, "spi: length mismatch");
      }
      rx.push(stream[pos + 1]);
      pos = pos + 2;
    } elif event == 3 {
      if pos + 1 >= n {
        return _err_transfer(pos + 1, "spi: truncated stream");
      }
      if !cs_open {
        return _err_transfer(pos, "spi: chip select not asserted");
      }
      let line2: Int = _byte(stream, pos + 1);
      if line2 != cs {
        return _err_transfer(pos + 1, "spi: chip select mismatch");
      }
      cs_open = false;
      closed = true;
      pos = pos + 2;
    } elif event == 6 {
      ended = true;
    } elif event == 1 || event == 2 {
      return _err_transfer(pos, "spi: unexpected event");
    } else {
      return _err_transfer(pos, "spi: unknown event");
    }
  }
  if cs_open {
    return _err_transfer(pos, "spi: cs left asserted");
  }
  if rx.len() > 0 && rx.len() != tx.len() {
    return _err_transfer(pos, "spi: length mismatch");
  }
  if (tx.len() * 8) % word_size != 0 {
    return _err_transfer(pos, "spi: length mismatch");
  }
  let end_pos = pos + 1;
  if end_pos != n {
    return _err_transfer(end_pos, "spi: trailing bytes");
  }
  let c = SpiConfig{ mode: mode; word_size: word_size; bit_order: bit_order; };
  let out = SpiTransfer{ config: c; cs: cs; tx: tx; rx: rx; };
  return _ok_transfer(out);
}

// --------------------------------------------------
//  Accessors and equality
// --------------------------------------------------

/// Mode of the transfer (0..3 for a valid transfer). Complexity: O(1).
pub fn spi_transfer_mode(t: &SpiTransfer) -> Int {
  return t.config.mode;
}

/// Word size of the transfer in bits (4..16 for a valid transfer).
/// Complexity: O(1).
pub fn spi_transfer_word_size(t: &SpiTransfer) -> Int {
  return t.config.word_size;
}

/// Bit order of the transfer (0 MSB-first, 1 LSB-first).
/// Complexity: O(1).
pub fn spi_transfer_bit_order(t: &SpiTransfer) -> Int {
  return t.config.bit_order;
}

/// Chip-select line of the transfer (-1 or 0..7). Complexity: O(1).
pub fn spi_transfer_cs(t: &SpiTransfer) -> Int {
  return t.cs;
}

/// Number of bytes in the MOSI stream. Complexity: O(1).
pub fn spi_tx_len(t: &SpiTransfer) -> Int {
  let tx: Vec[UInt8] = t.tx;
  return tx.len();
}

/// Number of bytes in the MISO stream (0 when not captured).
/// Complexity: O(1).
pub fn spi_rx_len(t: &SpiTransfer) -> Int {
  let rx: Vec[UInt8] = t.rx;
  return rx.len();
}

/// True when both byte streams are present and equal in length (a captured
/// full-duplex transfer; a zero-byte transfer is not full duplex).
/// Complexity: O(1).
pub fn spi_is_full_duplex(t: &SpiTransfer) -> Bool {
  let tx: Vec[UInt8] = t.tx;
  let rx: Vec[UInt8] = t.rx;
  if tx.len() == 0 {
    return false;
  }
  return rx.len() == tx.len();
}

/// Number of whole words in the tx stream: tx.len() * 8 / word_size; -1 when
/// the word size is invalid or the bit count is not a whole number of words.
/// Complexity: O(1).
pub fn spi_word_count(t: &SpiTransfer) -> Int {
  let word_size: Int = t.config.word_size;
  if !spi_word_size_valid(word_size) {
    return -1;
  }
  let tx: Vec[UInt8] = t.tx;
  if (tx.len() * 8) % word_size != 0 {
    return -1;
  }
  return tx.len() * 8 / word_size;
}

/// Value of word `index` in the tx stream as clocked, assembled with the
/// transfer's bit order: the first clocked bit is the most significant bit
/// for MSB-first and the least significant bit for LSB-first. Returns -1
/// when the word size is invalid, `index` is negative, or the word lies
/// beyond the tx bit stream. Complexity: O(word_size).
pub fn spi_word_at(t: &SpiTransfer, index: Int) -> Int {
  let word_size: Int = t.config.word_size;
  if !spi_word_size_valid(word_size) {
    return -1;
  }
  let tx: Vec[UInt8] = t.tx;
  let bits = tx.len() * 8;
  if index < 0 {
    return -1;
  }
  if index * word_size + word_size > bits {
    return -1;
  }
  let msb: Bool = t.config.bit_order == 0;
  var v = 0;
  var m = 0;
  while m < word_size {
    let bit: Int = _bit_at(&tx, index * word_size + m, msb);
    if msb {
      v = v * 2 + bit;
    } else {
      v = v + bit * _pow2(m);
    }
    m = m + 1;
  }
  return v;
}

/// Structural equality: same mode, word size, bit order, chip-select line
/// and both byte streams. Complexity: O(tx.len() + rx.len()).
pub fn spi_equal(a: &SpiTransfer, b: &SpiTransfer) -> Bool {
  let am: Int = a.config.mode;
  let bm: Int = b.config.mode;
  if am != bm {
    return false;
  }
  let aw: Int = a.config.word_size;
  let bw: Int = b.config.word_size;
  if aw != bw {
    return false;
  }
  let ao: Int = a.config.bit_order;
  let bo: Int = b.config.bit_order;
  if ao != bo {
    return false;
  }
  let ac: Int = a.cs;
  let bc: Int = b.cs;
  if ac != bc {
    return false;
  }
  let atx: Vec[UInt8] = a.tx;
  let btx: Vec[UInt8] = b.tx;
  if !_bytes_equal(&atx, &btx) {
    return false;
  }
  let arx: Vec[UInt8] = a.rx;
  let brx: Vec[UInt8] = b.rx;
  return _bytes_equal(&arx, &brx);
}
