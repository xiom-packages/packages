// XIOM -- xiom.gpio: Linux GPIO character-device uAPI (v2) structure codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no device access) in-memory codec for the structure
// layer of the Linux GPIO character-device uAPI version 2, as defined by
// include/uapi/linux/gpio.h. In scope:
//   * gpiochip_info: name/label 32-byte NUL-padded C strings plus the line
//     count (68 bytes);
//   * gpio_v2_line_info: name/consumer strings, offset, num_attrs, the flags
//     bitmap and the attribute array (256 bytes);
//   * the v2 line flag bits 0..12 (USED, ACTIVE_LOW, INPUT, OUTPUT,
//     EDGE_RISING, EDGE_FALLING, OPEN_DRAIN, OPEN_SOURCE, BIAS_PULL_UP,
//     BIAS_PULL_DOWN, BIAS_DISABLED, EVENT_CLOCK_REALTIME, EVENT_CLOCK_HTE),
//     decoded with division/modulo (never a sign-bit operation), plus the
//     line-changed type enum that carries the uAPI's REQUESTED value;
//   * gpio_v2_line_attribute (16 bytes) and gpio_v2_line_config (272 bytes):
//     the FLAGS, OUTPUT_VALUES and DEBOUNCE attribute kinds with their
//     index-aligned id/value/mask arrays;
//   * gpio_v2_line_request (592 bytes): 64 offset slots, the consumer
//     string, the embedded config, num_lines, event_buffer_size and fd --
//     encode and decode with explicit little-endian layout and exact size
//     validation;
//   * gpio_v2_line_event (48 bytes): the 64-bit timestamp, event id, line
//     offset and both sequence numbers, with the 64-bit value composed by
//     explicit byte multiplication and a branch for bit 63;
//   * gpio_v2_line_values (16 bytes): the bits/mask pair used for output
//     default values (the v2 OUTPUT_VALUES attribute payload).
//
// The byte layout is little-endian throughout. The real ioctl interface
// passes these structs in native byte order; this package intentionally
// fixes a single explicit layout (LE) so buffers can be built and checked
// on any host, which is exactly what the conformance suite pins.
//
// Every failure is a deterministic Err(Str) message. Truncated buffers,
// wrong sizes, nonzero padding, names without a NUL within 32 bytes,
// inconsistent num_attrs/num_lines/offsets, unknown attribute or event ids
// and 64-bit values with bit 63 set all carry the byte offset of the
// offending field (e.g. "gpio: line config: bad padding at offset 12:
// expected zero byte, found 255").
//
// v0.61.3 notes that shaped this module:
//   * free functions only: no methods, no lambdas, no Vec[fn] dispatch and
//     no Vec[StructType]; variable-length collections are index-aligned
//     Vec[Int] arrays and every push writes all mirrors (attribute ids,
//     values and masks move together).
//   * Ok/Err construction is confined to the tiny leaf helpers `_ok_*` /
//     `_err_*` below (constructing Results inside other functions
//     miscompiles).
//   * every byte read from a Vec[UInt8] is widened with `(x as Int) & 0xFF`
//     before entering Int arithmetic; no UInt8 is compared against an Int
//     constant >= 128 without widening.
//   * `&struct.field` is never passed directly to a `&Vec` parameter (that
//     yields an empty vector in v0.61.3): fields are bound to typed locals
//     first.
//   * no Str value is compared with `==` anywhere in this module; string
//     fields are materialized through xiom.string.builder.sb_to_str over the
//     NUL-free prefix of the field only (sb_to_str must never see 0x00).
//   * flag decode uses division and modulo by powers of two, never a shift
//     or a mask that could touch the sign bit; 64-bit little-endian
//     composition is explicit byte multiplication with a bit-63 branch.
//   * `&mut StructType` write-through is limited to Vec pushes and field
//     assignment on the builder helpers; `&mut Int` out-parameters are
//     avoided entirely, fallible helpers return their value.
//
// uAPI note: the v2 line flags have no REQUESTED bit. The uAPI's REQUESTED
// value is the line-changed event type GPIO_V2_LINE_CHANGED_REQUESTED (1),
// decoded here by gpio_line_changed_type_name next to RELEASED and CONFIG.

module xiom.gpio

use xiom.convert;
use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Struct sizes
// --------------------------------------------------

/// gpiochip_info struct size in bytes.
pub const GPIO_CHIP_INFO_SIZE: Int = 68;
/// Size of the C string name/label/consumer fields (GPIO_MAX_NAME_SIZE).
pub const GPIO_MAX_NAME_SIZE: Int = 32;
/// Maximum number of lines in one request (GPIO_V2_LINES_MAX).
pub const GPIO_V2_LINES_MAX: Int = 64;
/// Maximum number of config attributes (GPIO_V2_LINE_NUM_ATTRS_MAX).
pub const GPIO_V2_LINE_NUM_ATTRS_MAX: Int = 10;
/// gpio_v2_line_attribute struct size in bytes (id, padding, 8-byte union).
pub const GPIO_V2_LINE_ATTRIBUTE_SIZE: Int = 16;
/// gpio_v2_line_config_attribute size in bytes (attribute plus line mask).
pub const GPIO_V2_LINE_CONFIG_ATTRIBUTE_SIZE: Int = 24;
/// gpio_v2_line_config struct size in bytes (32 + 10 * 24).
pub const GPIO_V2_LINE_CONFIG_SIZE: Int = 272;
/// gpio_v2_line_request struct size in bytes (592).
pub const GPIO_V2_LINE_REQUEST_SIZE: Int = 592;
/// gpio_v2_line_info struct size in bytes (256).
pub const GPIO_V2_LINE_INFO_SIZE: Int = 256;
/// gpio_v2_line_event struct size in bytes (48).
pub const GPIO_V2_LINE_EVENT_SIZE: Int = 48;
/// gpio_v2_line_values struct size in bytes (16).
pub const GPIO_V2_LINE_VALUES_SIZE: Int = 16;

// --------------------------------------------------
//  Struct field offsets
// --------------------------------------------------

/// gpiochip_info.name offset.
pub const GPIO_CHIP_INFO_NAME_OFFSET: Int = 0;
/// gpiochip_info.label offset.
pub const GPIO_CHIP_INFO_LABEL_OFFSET: Int = 32;
/// gpiochip_info.lines offset.
pub const GPIO_CHIP_INFO_LINES_OFFSET: Int = 64;

/// gpio_v2_line_request.offsets[0] offset.
pub const GPIO_V2_LINE_REQUEST_OFFSETS_OFFSET: Int = 0;
/// gpio_v2_line_request.consumer offset.
pub const GPIO_V2_LINE_REQUEST_CONSUMER_OFFSET: Int = 256;
/// gpio_v2_line_request.config offset.
pub const GPIO_V2_LINE_REQUEST_CONFIG_OFFSET: Int = 288;
/// gpio_v2_line_request.num_lines offset.
pub const GPIO_V2_LINE_REQUEST_NUM_LINES_OFFSET: Int = 560;
/// gpio_v2_line_request.event_buffer_size offset.
pub const GPIO_V2_LINE_REQUEST_EVENT_BUFFER_SIZE_OFFSET: Int = 564;
/// gpio_v2_line_request.padding[5] offset (20 bytes).
pub const GPIO_V2_LINE_REQUEST_PADDING_OFFSET: Int = 568;
/// gpio_v2_line_request.fd offset.
pub const GPIO_V2_LINE_REQUEST_FD_OFFSET: Int = 588;

/// gpio_v2_line_config.flags offset.
pub const GPIO_V2_LINE_CONFIG_FLAGS_OFFSET: Int = 0;
/// gpio_v2_line_config.num_attrs offset.
pub const GPIO_V2_LINE_CONFIG_NUM_ATTRS_OFFSET: Int = 8;
/// gpio_v2_line_config.padding[5] offset (20 bytes).
pub const GPIO_V2_LINE_CONFIG_PADDING_OFFSET: Int = 12;
/// gpio_v2_line_config.attrs[0] offset.
pub const GPIO_V2_LINE_CONFIG_ATTRS_OFFSET: Int = 32;

/// gpio_v2_line_attribute.id offset.
pub const GPIO_V2_LINE_ATTRIBUTE_ID_OFFSET: Int = 0;
/// gpio_v2_line_attribute.padding offset (4 bytes).
pub const GPIO_V2_LINE_ATTRIBUTE_PADDING_OFFSET: Int = 4;
/// gpio_v2_line_attribute union offset (flags/values u64 or debounce u32).
pub const GPIO_V2_LINE_ATTRIBUTE_VALUE_OFFSET: Int = 8;
/// gpio_v2_line_config_attribute.mask offset.
pub const GPIO_V2_LINE_CONFIG_ATTRIBUTE_MASK_OFFSET: Int = 16;

/// gpio_v2_line_info.name offset.
pub const GPIO_V2_LINE_INFO_NAME_OFFSET: Int = 0;
/// gpio_v2_line_info.consumer offset.
pub const GPIO_V2_LINE_INFO_CONSUMER_OFFSET: Int = 32;
/// gpio_v2_line_info.offset field offset.
pub const GPIO_V2_LINE_INFO_LINE_OFFSET_OFFSET: Int = 64;
/// gpio_v2_line_info.num_attrs offset.
pub const GPIO_V2_LINE_INFO_NUM_ATTRS_OFFSET: Int = 68;
/// gpio_v2_line_info.flags offset.
pub const GPIO_V2_LINE_INFO_FLAGS_OFFSET: Int = 72;
/// gpio_v2_line_info.attrs[0] offset.
pub const GPIO_V2_LINE_INFO_ATTRS_OFFSET: Int = 80;
/// gpio_v2_line_info.padding[4] offset (16 bytes).
pub const GPIO_V2_LINE_INFO_PADDING_OFFSET: Int = 240;

/// gpio_v2_line_event.timestamp_ns offset.
pub const GPIO_V2_LINE_EVENT_TIMESTAMP_OFFSET: Int = 0;
/// gpio_v2_line_event.id offset.
pub const GPIO_V2_LINE_EVENT_ID_OFFSET: Int = 8;
/// gpio_v2_line_event.offset field offset.
pub const GPIO_V2_LINE_EVENT_LINE_OFFSET_OFFSET: Int = 12;
/// gpio_v2_line_event.seqno offset.
pub const GPIO_V2_LINE_EVENT_SEQNO_OFFSET: Int = 16;
/// gpio_v2_line_event.line_seqno offset.
pub const GPIO_V2_LINE_EVENT_LINE_SEQNO_OFFSET: Int = 20;
/// gpio_v2_line_event.padding[6] offset (24 bytes).
pub const GPIO_V2_LINE_EVENT_PADDING_OFFSET: Int = 24;

/// gpio_v2_line_values.bits offset.
pub const GPIO_V2_LINE_VALUES_BITS_OFFSET: Int = 0;
/// gpio_v2_line_values.mask offset.
pub const GPIO_V2_LINE_VALUES_MASK_OFFSET: Int = 8;

// --------------------------------------------------
//  Line flags (bit positions per the uAPI enum)
// --------------------------------------------------

/// Flag bit 0: line is not available for request.
pub const GPIO_V2_LINE_FLAG_USED: Int = 1;
/// Flag bit 1: line active state is physical low.
pub const GPIO_V2_LINE_FLAG_ACTIVE_LOW: Int = 2;
/// Flag bit 2: line is an input.
pub const GPIO_V2_LINE_FLAG_INPUT: Int = 4;
/// Flag bit 3: line is an output.
pub const GPIO_V2_LINE_FLAG_OUTPUT: Int = 8;
/// Flag bit 4: line detects rising (inactive to active) edges.
pub const GPIO_V2_LINE_FLAG_EDGE_RISING: Int = 16;
/// Flag bit 5: line detects falling (active to inactive) edges.
pub const GPIO_V2_LINE_FLAG_EDGE_FALLING: Int = 32;
/// Flag bit 6: line is an open drain output.
pub const GPIO_V2_LINE_FLAG_OPEN_DRAIN: Int = 64;
/// Flag bit 7: line is an open source output.
pub const GPIO_V2_LINE_FLAG_OPEN_SOURCE: Int = 128;
/// Flag bit 8: line has pull-up bias enabled.
pub const GPIO_V2_LINE_FLAG_BIAS_PULL_UP: Int = 256;
/// Flag bit 9: line has pull-down bias enabled.
pub const GPIO_V2_LINE_FLAG_BIAS_PULL_DOWN: Int = 512;
/// Flag bit 10: line has bias disabled.
pub const GPIO_V2_LINE_FLAG_BIAS_DISABLED: Int = 1024;
/// Flag bit 11: line events carry CLOCK_REALTIME timestamps.
pub const GPIO_V2_LINE_FLAG_EVENT_CLOCK_REALTIME: Int = 2048;
/// Flag bit 12: line events carry hardware timestamp engine timestamps.
pub const GPIO_V2_LINE_FLAG_EVENT_CLOCK_HTE: Int = 4096;
/// Number of defined flag bits (0..12); bit 13 is the first unassigned bit.
pub const GPIO_V2_LINE_FLAGS_BITS: Int = 13;
/// Mask of every defined v2 line flag (bits 0..12 set).
pub const GPIO_V2_LINE_FLAG_KNOWN_MASK: Int = 8191;

// --------------------------------------------------
//  Attribute ids, line-changed types, event ids
// --------------------------------------------------

/// Attribute id 1: the union holds a flag bitmap.
pub const GPIO_V2_LINE_ATTR_ID_FLAGS: Int = 1;
/// Attribute id 2: the union holds an output values bitmap.
pub const GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES: Int = 2;
/// Attribute id 3: the union holds a debounce period in microseconds.
pub const GPIO_V2_LINE_ATTR_ID_DEBOUNCE: Int = 3;

/// Line-changed type 1: the line has been requested.
pub const GPIO_V2_LINE_CHANGED_REQUESTED: Int = 1;
/// Line-changed type 2: the line has been released.
pub const GPIO_V2_LINE_CHANGED_RELEASED: Int = 2;
/// Line-changed type 3: the line has been reconfigured.
pub const GPIO_V2_LINE_CHANGED_CONFIG: Int = 3;

/// Event id 1: rising edge.
pub const GPIO_V2_LINE_EVENT_RISING_EDGE: Int = 1;
/// Event id 2: falling edge.
pub const GPIO_V2_LINE_EVENT_FALLING_EDGE: Int = 2;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Decoded gpiochip_info. `name` and `label` are the C strings trimmed at
/// the first NUL; `lines` is the raw u32 line count.
pub type GpioChipInfo = {
  name: Str;
  label: Str;
  lines: Int;
}

/// One decoded gpio_v2_line_attribute: `id` is one of the
/// GPIO_V2_LINE_ATTR_ID_* constants and `value` is the union payload (a
/// 64-bit flag or output-values bitmap, or the debounce period in
/// microseconds).
pub type GpioLineAttribute = {
  id: Int;
  value: Int;
}

/// Decoded gpio_v2_line_config: the default `flags` bitmap plus the
/// index-aligned attribute arrays. `attr_ids[i]`, `attr_values[i]` and
/// `attr_masks[i]` describe attribute `i`; the number of attributes is
/// `attr_ids.len()`. Never push to one array without the others.
pub type GpioLineConfig = {
  flags: Int;
  attr_ids: Vec[Int];
  attr_values: Vec[Int];
  attr_masks: Vec[Int];
}

/// Decoded gpio_v2_line_request. `offsets` holds exactly `num_lines` line
/// offsets; `consumer` is the trimmed consumer string; `fd` is the raw
/// unsigned 32-bit image of the file descriptor field (use
/// gpio_u32_to_i32 for the signed view); the config arrays are flattened.
pub type GpioLineRequest = {
  offsets: Vec[Int];
  consumer: Str;
  num_lines: Int;
  event_buffer_size: Int;
  fd: Int;
  config_flags: Int;
  attr_ids: Vec[Int];
  attr_values: Vec[Int];
  attr_masks: Vec[Int];
}

/// Decoded gpio_v2_line_info. `line_offset` is the uAPI `offset` field,
/// `num_attrs` counts the attribute entries and `flags` is the raw flag
/// bitmap.
pub type GpioLineInfo = {
  name: Str;
  consumer: Str;
  line_offset: Int;
  num_attrs: Int;
  flags: Int;
  attr_ids: Vec[Int];
  attr_values: Vec[Int];
}

/// Decoded gpio_v2_line_event. `event_type` is one of the
/// GPIO_V2_LINE_EVENT_* constants, `line_offset` is the uAPI `offset`
/// field, `global_seqno` is the uAPI `seqno` field and `line_seqno` the
/// per-line sequence number.
pub type GpioLineEvent = {
  timestamp_ns: Int;
  event_type: Int;
  line_offset: Int;
  global_seqno: Int;
  line_seqno: Int;
}

/// Decoded gpio_v2_line_values: the `bits` value bitmap and the `mask` of
/// lines it applies to.
pub type GpioLineValues = {
  bits: Int;
  mask: Int;
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

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
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

// Ok(v) for Result[GpioChipInfo, Str].
fn _ok_chip(v: GpioChipInfo) -> Result[GpioChipInfo, Str] {
  return Ok(v);
}

// Err(m) for Result[GpioChipInfo, Str].
fn _err_chip(m: Str) -> Result[GpioChipInfo, Str] {
  return Err(m);
}

// Ok(v) for Result[GpioLineAttribute, Str].
fn _ok_attr(v: GpioLineAttribute) -> Result[GpioLineAttribute, Str] {
  return Ok(v);
}

// Err(m) for Result[GpioLineAttribute, Str].
fn _err_attr(m: Str) -> Result[GpioLineAttribute, Str] {
  return Err(m);
}

// Ok(v) for Result[GpioLineConfig, Str].
fn _ok_config(v: GpioLineConfig) -> Result[GpioLineConfig, Str] {
  return Ok(v);
}

// Err(m) for Result[GpioLineConfig, Str].
fn _err_config(m: Str) -> Result[GpioLineConfig, Str] {
  return Err(m);
}

// Ok(v) for Result[GpioLineRequest, Str].
fn _ok_request(v: GpioLineRequest) -> Result[GpioLineRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[GpioLineRequest, Str].
fn _err_request(m: Str) -> Result[GpioLineRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[GpioLineInfo, Str].
fn _ok_info(v: GpioLineInfo) -> Result[GpioLineInfo, Str] {
  return Ok(v);
}

// Err(m) for Result[GpioLineInfo, Str].
fn _err_info(m: Str) -> Result[GpioLineInfo, Str] {
  return Err(m);
}

// Ok(v) for Result[GpioLineEvent, Str].
fn _ok_event(v: GpioLineEvent) -> Result[GpioLineEvent, Str] {
  return Ok(v);
}

// Err(m) for Result[GpioLineEvent, Str].
fn _err_event(m: Str) -> Result[GpioLineEvent, Str] {
  return Err(m);
}

// Ok(v) for Result[GpioLineValues, Str].
fn _ok_values(v: GpioLineValues) -> Result[GpioLineValues, Str] {
  return Ok(v);
}

// Err(m) for Result[GpioLineValues, Str].
fn _err_values(m: Str) -> Result[GpioLineValues, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte and text helpers
// --------------------------------------------------

// Decimal text (xiom.convert.int; wrapped so the call sites stay short).
fn _dec(v: Int) -> Str {
  return convert.int_to_string(v);
}

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// 2^k for 0 <= k <= 62, computed by repeated multiplication (no shift).
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Little-endian u32 at `off`; callers guarantee the bounds. The result is
// always 0..4294967295.
fn _u32_le(data: &Vec[UInt8], off: Int) -> Int {
  return _byte(data, off) + _byte(data, off + 1) * 256 + _byte(data, off + 2) * 65536 + _byte(data, off + 3) * 16777216;
}

// Little-endian u64 at `off` as a non-negative Int; callers guarantee the
// bounds. A byte 7 with bit 7 set means bit 63 of the u64 is set, which no
// Int can hold, so it is a deterministic Err instead of a silent wrap.
// `label` names the field in the error text.
fn _u64_le(data: &Vec[UInt8], off: Int, label: Str) -> Result[Int, Str] {
  let hi = _byte(data, off + 7);
  if hi >= 128 {
    return _err_int("gpio: " + label + ": 64-bit value at offset " + _dec(off) + " has bit 63 set (not representable as Int)");
  }
  var v = _byte(data, off + 6) * 281474976710656 + _byte(data, off + 5) * 1099511627776 + _byte(data, off + 4) * 4294967296;
  v = v + _byte(data, off + 3) * 16777216 + _byte(data, off + 2) * 65536 + _byte(data, off + 1) * 256 + _byte(data, off);
  v = v + hi * 72057594037927936;
  return _ok_int(v);
}

// Append a little-endian u32. `v` must be in 0..4294967295.
fn _put_u32_le(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 16777216) % 256) as UInt8);
}

// Append a little-endian u64. `v` must be in 0..9223372036854775807.
fn _put_u64_le(out: &mut Vec[UInt8], v: Int) {
  _put_u32_le(out, v % 4294967296);
  _put_u32_le(out, v / 4294967296);
}

// Append `n` zero bytes.
fn _put_zeros(out: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    out.push(0);
    i = i + 1;
  }
}

// True when `v` fits in an unsigned 32-bit field.
fn _u32_fits(v: Int) -> Bool {
  return v >= 0 && v <= 4294967295;
}

// Check that `n` bytes at `off` are all zero (uAPI padding must be zero
// filled). The error carries the absolute offset of the first bad byte.
fn _zeros_ok(data: &Vec[UInt8], off: Int, n: Int, label: Str) -> Result[Unit, Str] {
  var i = 0;
  while i < n {
    let b: Int = _byte(data, off + i);
    if b != 0 {
      return _err_unit("gpio: " + label + ": bad padding at offset " + _dec(off + i) + ": expected zero byte, found " + _dec(b));
    }
    i = i + 1;
  }
  return _ok_unit();
}

// Exact-size gate shared by every decode function: too few bytes reports
// the first missing offset, too many reports the unexpected tail.
fn _size_exact(data: &Vec[UInt8], size: Int, label: Str) -> Result[Unit, Str] {
  let n = data.len();
  if n < size {
    return _err_unit("gpio: " + label + ": truncated at offset " + _dec(n) + ": need " + _dec(size) + " bytes, have " + _dec(n));
  }
  if n > size {
    return _err_unit("gpio: " + label + ": buffer has " + _dec(n) + " bytes, expected exactly " + _dec(size));
  }
  return _ok_unit();
}

// Materialize the 32-byte C string field at `off`: trim at the first NUL and
// build the Str from that NUL-free prefix only (sb_to_str must never see
// 0x00). A field with no NUL within 32 bytes is an error. Callers
// guarantee the 32 bytes are in bounds.
fn _cstr32(data: &Vec[UInt8], off: Int, label: Str) -> Result[Str, Str] {
  var nul = -1;
  var i = 0;
  while i < GPIO_MAX_NAME_SIZE {
    let b: Int = _byte(data, off + i);
    if b == 0 && nul < 0 {
      nul = i;
    }
    i = i + 1;
  }
  if nul < 0 {
    return _err_str("gpio: " + label + " at offset " + _dec(off) + " has no NUL within 32 bytes");
  }
  var sb = Vec[UInt8].new();
  i = 0;
  while i < nul {
    sb.push(_byte(data, off + i) as UInt8);
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&sb));
}

// Validate a name that will be written into a 32-byte C string field: at
// most 31 bytes plus the terminating NUL, and no embedded NUL byte.
fn _validate_name(name: Str, label: Str) -> Result[Unit, Str] {
  let n = name.len();
  if n > 31 {
    return _err_unit("gpio: " + label + " is " + _dec(n) + " bytes, needs at most 31 plus NUL within 32");
  }
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(name, i) as Int) & 0xFF;
    if b == 0 {
      return _err_unit("gpio: " + label + " has an embedded NUL at byte " + _dec(i));
    }
    i = i + 1;
  }
  return _ok_unit();
}

// Append `s` into a 32-byte C string field: the bytes, then zero padding.
// Callers validate the name first (32 bytes are always written).
fn _put_cstr32(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  _put_zeros(out, GPIO_MAX_NAME_SIZE - s.len());
}

// --------------------------------------------------
//  Public name helpers
// --------------------------------------------------

/// True when `name` fits a 32-byte C string field with its terminating NUL
/// (at most 31 bytes).
pub fn gpio_name_fits(name: Str) -> Bool {
  return name.len() <= 31;
}

/// True when `name` is a valid consumer/name value: at most 31 bytes and no
/// embedded NUL byte. This is the consumer-name validation predicate.
pub fn gpio_consumer_name_ok(name: Str) -> Bool {
  if name.len() > 31 {
    return false;
  }
  var i = 0;
  while i < name.len() {
    let b: Int = (string.byte_at(name, i) as Int) & 0xFF;
    if b == 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Decode a 32-byte NUL-padded C string field at `off` (trimmed at the
/// first NUL, never past it).
///
/// Err("gpio: name at offset O: truncated: need 32 bytes, have H") when the
/// buffer is too short; Err("gpio: name at offset O has no NUL within 32
/// bytes") when the field is not terminated.
pub fn gpio_name_decode(data: &Vec[UInt8], off: Int) -> Result[Str, Str] {
  let n = data.len();
  if off < 0 || off + GPIO_MAX_NAME_SIZE > n {
    var have = n - off;
    if have < 0 {
      have = 0;
    }
    return _err_str("gpio: name at offset " + _dec(off) + ": truncated: need 32 bytes, have " + _dec(have));
  }
  return _cstr32(data, off, "name");
}

/// Append `name` as a 32-byte NUL-padded C string field.
///
/// Err("gpio: name is N bytes, needs at most 31 plus NUL within 32");
/// Err("gpio: name has an embedded NUL at byte I"). Nothing is appended on
/// Err (validated first).
pub fn gpio_name_encode_into(out: &mut Vec[UInt8], name: Str) -> Result[Unit, Str] {
  let vr = _validate_name(name, "name");
  if !vr.is_ok {
    return _err_unit(vr.error);
  }
  _put_cstr32(out, name);
  return _ok_unit();
}

// --------------------------------------------------
//  Public line-flag helpers
// --------------------------------------------------

// True when `flag` is exactly one of the 13 defined single-bit flags.
fn _known_single_flag(flag: Int) -> Bool {
  if flag == GPIO_V2_LINE_FLAG_USED {
    return true;
  }
  if flag == GPIO_V2_LINE_FLAG_ACTIVE_LOW {
    return true;
  }
  if flag == GPIO_V2_LINE_FLAG_INPUT {
    return true;
  }
  if flag == GPIO_V2_LINE_FLAG_OUTPUT {
    return true;
  }
  if flag == GPIO_V2_LINE_FLAG_EDGE_RISING {
    return true;
  }
  if flag == GPIO_V2_LINE_FLAG_EDGE_FALLING {
    return true;
  }
  if flag == GPIO_V2_LINE_FLAG_OPEN_DRAIN {
    return true;
  }
  if flag == GPIO_V2_LINE_FLAG_OPEN_SOURCE {
    return true;
  }
  if flag == GPIO_V2_LINE_FLAG_BIAS_PULL_UP {
    return true;
  }
  if flag == GPIO_V2_LINE_FLAG_BIAS_PULL_DOWN {
    return true;
  }
  if flag == GPIO_V2_LINE_FLAG_BIAS_DISABLED {
    return true;
  }
  if flag == GPIO_V2_LINE_FLAG_EVENT_CLOCK_REALTIME {
    return true;
  }
  return flag == GPIO_V2_LINE_FLAG_EVENT_CLOCK_HTE;
}

// The single-bit flag constant for bit index `i` (0..12).
fn _flag_at(i: Int) -> Int {
  if i == 0 {
    return GPIO_V2_LINE_FLAG_USED;
  }
  if i == 1 {
    return GPIO_V2_LINE_FLAG_ACTIVE_LOW;
  }
  if i == 2 {
    return GPIO_V2_LINE_FLAG_INPUT;
  }
  if i == 3 {
    return GPIO_V2_LINE_FLAG_OUTPUT;
  }
  if i == 4 {
    return GPIO_V2_LINE_FLAG_EDGE_RISING;
  }
  if i == 5 {
    return GPIO_V2_LINE_FLAG_EDGE_FALLING;
  }
  if i == 6 {
    return GPIO_V2_LINE_FLAG_OPEN_DRAIN;
  }
  if i == 7 {
    return GPIO_V2_LINE_FLAG_OPEN_SOURCE;
  }
  if i == 8 {
    return GPIO_V2_LINE_FLAG_BIAS_PULL_UP;
  }
  if i == 9 {
    return GPIO_V2_LINE_FLAG_BIAS_PULL_DOWN;
  }
  if i == 10 {
    return GPIO_V2_LINE_FLAG_BIAS_DISABLED;
  }
  if i == 11 {
    return GPIO_V2_LINE_FLAG_EVENT_CLOCK_REALTIME;
  }
  return GPIO_V2_LINE_FLAG_EVENT_CLOCK_HTE;
}

/// True when the single-bit `flag` (one of the GPIO_V2_LINE_FLAG_*
/// constants) is set in the `flags` bitmap. The bit is probed with division
/// and modulo, so bit 63 can never reach a sign operation. Returns false
/// for a non-single-bit flag value or a negative bitmap.
pub fn gpio_line_flag_set(flags: Int, flag: Int) -> Bool {
  if !_known_single_flag(flag) {
    return false;
  }
  if flags < 0 {
    return false;
  }
  return (flags / flag) % 2 == 1;
}

/// True when `flag` is one of the 13 defined single-bit v2 line flags.
pub fn gpio_line_flag_known(flag: Int) -> Bool {
  return _known_single_flag(flag);
}

/// Human-readable name of a single-bit v2 line flag: "used", "active_low",
/// "input", "output", "edge_rising", "edge_falling", "open_drain",
/// "open_source", "bias_pull_up", "bias_pull_down", "bias_disabled",
/// "event_clock_realtime", "event_clock_hte"; any other value is "unknown".
pub fn gpio_line_flag_name(flag: Int) -> Str {
  if flag == GPIO_V2_LINE_FLAG_USED {
    return "used";
  }
  if flag == GPIO_V2_LINE_FLAG_ACTIVE_LOW {
    return "active_low";
  }
  if flag == GPIO_V2_LINE_FLAG_INPUT {
    return "input";
  }
  if flag == GPIO_V2_LINE_FLAG_OUTPUT {
    return "output";
  }
  if flag == GPIO_V2_LINE_FLAG_EDGE_RISING {
    return "edge_rising";
  }
  if flag == GPIO_V2_LINE_FLAG_EDGE_FALLING {
    return "edge_falling";
  }
  if flag == GPIO_V2_LINE_FLAG_OPEN_DRAIN {
    return "open_drain";
  }
  if flag == GPIO_V2_LINE_FLAG_OPEN_SOURCE {
    return "open_source";
  }
  if flag == GPIO_V2_LINE_FLAG_BIAS_PULL_UP {
    return "bias_pull_up";
  }
  if flag == GPIO_V2_LINE_FLAG_BIAS_PULL_DOWN {
    return "bias_pull_down";
  }
  if flag == GPIO_V2_LINE_FLAG_BIAS_DISABLED {
    return "bias_disabled";
  }
  if flag == GPIO_V2_LINE_FLAG_EVENT_CLOCK_REALTIME {
    return "event_clock_realtime";
  }
  if flag == GPIO_V2_LINE_FLAG_EVENT_CLOCK_HTE {
    return "event_clock_hte";
  }
  return "unknown";
}

/// Set flags of a `flags` bitmap, lowest bit first: the single-bit constants
/// for every defined bit that is set. Unknown bits are not reported.
pub fn gpio_line_flags_decode(flags: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if flags < 0 {
    return out;
  }
  var i = 0;
  while i < GPIO_V2_LINE_FLAGS_BITS {
    if (flags / _pow2(i)) % 2 == 1 {
      out.push(_flag_at(i));
    }
    i = i + 1;
  }
  return out;
}

/// The defined bits of `flags` (bits 0..12), with every unknown bit
/// cleared. A negative bitmap reports 0.
pub fn gpio_line_flags_known(flags: Int) -> Int {
  if flags < 0 {
    return 0;
  }
  return flags % _pow2(GPIO_V2_LINE_FLAGS_BITS);
}

/// The bits of `flags` above the defined range (bits 13 and up). A negative
/// bitmap reports 0.
pub fn gpio_line_flags_unknown(flags: Int) -> Int {
  if flags < 0 {
    return 0;
  }
  return flags - gpio_line_flags_known(flags);
}

/// Human-readable name of an attribute id: "flags", "output_values",
/// "debounce" or "unknown".
pub fn gpio_attr_id_name(id: Int) -> Str {
  if id == GPIO_V2_LINE_ATTR_ID_FLAGS {
    return "flags";
  }
  if id == GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES {
    return "output_values";
  }
  if id == GPIO_V2_LINE_ATTR_ID_DEBOUNCE {
    return "debounce";
  }
  return "unknown";
}

/// Human-readable name of a line-changed type: "requested", "released",
/// "config" or "unknown". The uAPI's REQUESTED value lives here
/// (GPIO_V2_LINE_CHANGED_REQUESTED), not in the line flag bitmap.
pub fn gpio_line_changed_type_name(change_type: Int) -> Str {
  if change_type == GPIO_V2_LINE_CHANGED_REQUESTED {
    return "requested";
  }
  if change_type == GPIO_V2_LINE_CHANGED_RELEASED {
    return "released";
  }
  if change_type == GPIO_V2_LINE_CHANGED_CONFIG {
    return "config";
  }
  return "unknown";
}

/// Human-readable name of a line event id: "rising edge", "falling edge" or
/// "unknown".
pub fn gpio_event_type_name(event_type: Int) -> Str {
  if event_type == GPIO_V2_LINE_EVENT_RISING_EDGE {
    return "rising edge";
  }
  if event_type == GPIO_V2_LINE_EVENT_FALLING_EDGE {
    return "falling edge";
  }
  return "unknown";
}

// --------------------------------------------------
//  Public predicate and alignment helpers
// --------------------------------------------------

/// True when `id` is one of the three attribute ids (1..3).
pub fn gpio_attr_id_ok(id: Int) -> Bool {
  return id >= GPIO_V2_LINE_ATTR_ID_FLAGS && id <= GPIO_V2_LINE_ATTR_ID_DEBOUNCE;
}

/// True when `n` is a legal attribute count (0..10).
pub fn gpio_num_attrs_ok(n: Int) -> Bool {
  return n >= 0 && n <= GPIO_V2_LINE_NUM_ATTRS_MAX;
}

/// True when `n` is a legal line count for one request (1..64).
pub fn gpio_num_lines_ok(n: Int) -> Bool {
  return n >= 1 && n <= GPIO_V2_LINES_MAX;
}

/// True when `event_type` is a defined line event id (1 or 2).
pub fn gpio_event_type_ok(event_type: Int) -> Bool {
  return event_type == GPIO_V2_LINE_EVENT_RISING_EDGE || event_type == GPIO_V2_LINE_EVENT_FALLING_EDGE;
}

/// True when `off` is an 8-byte aligned offset, the alignment the uAPI
/// attributes and their u64 members require.
pub fn gpio_attr_offset_aligned(off: Int) -> Bool {
  if off < 0 {
    return false;
  }
  return off % 8 == 0;
}

/// True when a 16-byte attribute at `off` fits within `len` bytes.
pub fn gpio_attr_fits(off: Int, len: Int) -> Bool {
  if off < 0 {
    return false;
  }
  return off + GPIO_V2_LINE_ATTRIBUTE_SIZE <= len;
}

/// Signed view of a raw unsigned 32-bit image such as the request `fd`
/// field: 0..2147483647 unchanged, 2147483648..4294967295 mapped to
/// -2147483648..-1.
pub fn gpio_u32_to_i32(v: Int) -> Int {
  if v >= 2147483648 {
    return v - 4294967296;
  }
  return v;
}

// --------------------------------------------------
//  gpiochip_info codec
// --------------------------------------------------

/// Decode a 68-byte gpiochip_info image. The name and label are trimmed at
/// the first NUL; bytes after that NUL are ignored.
///
/// Err("gpio: gpiochip_info: truncated at offset N: need 68 bytes, have N");
/// Err("gpio: gpiochip_info: buffer has N bytes, expected exactly 68");
/// Err("gpio: name at offset 0 has no NUL within 32 bytes") when a string
/// field is not terminated; the same for `label` at offset 32.
pub fn gpio_chip_info_decode(data: &Vec[UInt8]) -> Result[GpioChipInfo, Str] {
  let sr = _size_exact(data, GPIO_CHIP_INFO_SIZE, "gpiochip_info");
  if !sr.is_ok {
    return _err_chip(sr.error);
  }
  let name_r = _cstr32(data, GPIO_CHIP_INFO_NAME_OFFSET, "name");
  if !name_r.is_ok {
    return _err_chip(name_r.error);
  }
  let label_r = _cstr32(data, GPIO_CHIP_INFO_LABEL_OFFSET, "label");
  if !label_r.is_ok {
    return _err_chip(label_r.error);
  }
  let lines = _u32_le(data, GPIO_CHIP_INFO_LINES_OFFSET);
  let nm: Str = name_r.value;
  let lb: Str = label_r.value;
  return _ok_chip(GpioChipInfo{ name: nm; label: lb; lines: lines; });
}

/// Append the 68-byte gpiochip_info image of `info` to `out` (atomic: the
/// input is validated first, nothing is appended on Err).
///
/// Err("gpio: name is N bytes, needs at most 31 plus NUL within 32");
/// Err("gpio: label is N bytes, needs at most 31 plus NUL within 32");
/// Err("gpio: gpiochip_info: lines N does not fit in u32").
pub fn gpio_chip_info_encode_into(out: &mut Vec[UInt8], info: &GpioChipInfo) -> Result[Unit, Str] {
  let nr = _validate_name(info.name, "name");
  if !nr.is_ok {
    return _err_unit(nr.error);
  }
  let lr = _validate_name(info.label, "label");
  if !lr.is_ok {
    return _err_unit(lr.error);
  }
  if !_u32_fits(info.lines) {
    return _err_unit("gpio: gpiochip_info: lines " + _dec(info.lines) + " does not fit in u32");
  }
  _put_cstr32(out, info.name);
  _put_cstr32(out, info.label);
  _put_u32_le(out, info.lines);
  return _ok_unit();
}

/// Encode a fresh 68-byte gpiochip_info image. Same error catalog as
/// gpio_chip_info_encode_into.
pub fn gpio_chip_info_encode(info: &GpioChipInfo) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let r = gpio_chip_info_encode_into(&mut out, info);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  gpio_v2_line_attribute codec
// --------------------------------------------------

/// Decode the 16-byte gpio_v2_line_attribute at `off`.
///
/// Err("gpio: line attribute at offset O: truncated at offset N: need 16
/// bytes, have H") when out of bounds; Err("gpio: line attribute at offset
/// O: bad padding at offset O+4: expected zero byte, found V") when the
/// padding field is nonzero; Err("gpio: line attribute at offset O: unknown
/// id N") when the id is not 1..3. For a DEBOUNCE attribute the 32-bit
/// period is read from the low half of the union and the union's upper four
/// bytes are ignored; the other ids are read as unsigned 64-bit values
/// (bit 63 set is an error).
pub fn gpio_line_attribute_decode(data: &Vec[UInt8], off: Int) -> Result[GpioLineAttribute, Str] {
  let n = data.len();
  if off < 0 || off + GPIO_V2_LINE_ATTRIBUTE_SIZE > n {
    var have = n - off;
    if have < 0 {
      have = 0;
    }
    return _err_attr("gpio: line attribute at offset " + _dec(off) + ": truncated at offset " + _dec(n) + ": need 16 bytes, have " + _dec(have));
  }
  let id = _u32_le(data, off + GPIO_V2_LINE_ATTRIBUTE_ID_OFFSET);
  let zr = _zeros_ok(data, off + GPIO_V2_LINE_ATTRIBUTE_PADDING_OFFSET, 4, "line attribute at offset " + _dec(off));
  if !zr.is_ok {
    return _err_attr(zr.error);
  }
  if !gpio_attr_id_ok(id) {
    return _err_attr("gpio: line attribute at offset " + _dec(off) + ": unknown id " + _dec(id));
  }
  var value = 0;
  if id == GPIO_V2_LINE_ATTR_ID_DEBOUNCE {
    value = _u32_le(data, off + GPIO_V2_LINE_ATTRIBUTE_VALUE_OFFSET);
  } else {
    let vr = _u64_le(data, off + GPIO_V2_LINE_ATTRIBUTE_VALUE_OFFSET, "line attribute value");
    if !vr.is_ok {
      return _err_attr(vr.error);
    }
    value = vr.value;
  }
  return _ok_attr(GpioLineAttribute{ id: id; value: value; });
}

/// Append one 16-byte gpio_v2_line_attribute to `out` (id, four zero
/// padding bytes, then the union value; DEBOUNCE uses the 32-bit low half
/// and zeroes the upper half).
///
/// Err("gpio: line attribute: unknown id N"); Err("gpio: line attribute:
/// value V is negative"); Err("gpio: line attribute: debounce period V does
/// not fit in u32"). Nothing is appended on Err.
pub fn gpio_line_attribute_encode_into(out: &mut Vec[UInt8], id: Int, value: Int) -> Result[Unit, Str] {
  if !gpio_attr_id_ok(id) {
    return _err_unit("gpio: line attribute: unknown id " + _dec(id));
  }
  if value < 0 {
    return _err_unit("gpio: line attribute: value " + _dec(value) + " is negative");
  }
  if id == GPIO_V2_LINE_ATTR_ID_DEBOUNCE && !_u32_fits(value) {
    return _err_unit("gpio: line attribute: debounce period " + _dec(value) + " does not fit in u32");
  }
  _put_attribute(out, id, value);
  return _ok_unit();
}

// Append one attribute in the same layout used by the config and line-info
// writers. `id` and `value` are already validated by the caller.
fn _put_attribute(out: &mut Vec[UInt8], id: Int, v: Int) {
  _put_u32_le(out, id);
  _put_zeros(out, 4);
  if id == GPIO_V2_LINE_ATTR_ID_DEBOUNCE {
    _put_u32_le(out, v);
    _put_zeros(out, 4);
  } else {
    _put_u64_le(out, v);
  }
}

// --------------------------------------------------
//  gpio_v2_line_config codec
// --------------------------------------------------

// Validate one attribute entry independently (shared by the full-array
// check and the add_attr builder).
fn _attr_entry_check(id: Int, v: Int, m: Int, idx: Int, label: Str) -> Result[Unit, Str] {
  if !gpio_attr_id_ok(id) {
    return _err_unit("gpio: " + label + ": attr " + _dec(idx) + " has unknown id " + _dec(id));
  }
  if v < 0 {
    return _err_unit("gpio: " + label + ": attr " + _dec(idx) + " has a negative value (" + _dec(v) + ")");
  }
  if m < 0 {
    return _err_unit("gpio: " + label + ": attr " + _dec(idx) + " has a negative mask (" + _dec(m) + ")");
  }
  if id == GPIO_V2_LINE_ATTR_ID_DEBOUNCE && !_u32_fits(v) {
    return _err_unit("gpio: " + label + ": attr " + _dec(idx) + " debounce period " + _dec(v) + " does not fit in u32");
  }
  if id == GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES {
    let masked = v & m;
    if masked != v {
      return _err_unit("gpio: " + label + ": attr " + _dec(idx) + " output values " + _dec(v) + " have bits outside mask " + _dec(m));
    }
  }
  return _ok_unit();
}

// Validate the three index-aligned attribute arrays.
fn _attrs_check(ids: &Vec[Int], values: &Vec[Int], masks: &Vec[Int], label: Str) -> Result[Unit, Str] {
  let n = ids.len();
  if n != values.len() || n != masks.len() {
    return _err_unit("gpio: " + label + ": attribute arrays out of step (" + _dec(n) + " ids, " + _dec(values.len()) + " values, " + _dec(masks.len()) + " masks)");
  }
  if n > GPIO_V2_LINE_NUM_ATTRS_MAX {
    return _err_unit("gpio: " + label + ": " + _dec(n) + " attributes exceed the maximum of 10");
  }
  var i = 0;
  while i < n {
    let id: Int = ids[i];
    let v: Int = values[i];
    let m: Int = masks[i];
    let r = _attr_entry_check(id, v, m, i, label);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    i = i + 1;
  }
  return _ok_unit();
}

// Append the 272-byte config body. The caller validates first.
fn _config_write(out: &mut Vec[UInt8], cfg: &GpioLineConfig) {
  let ids: Vec[Int] = cfg.attr_ids;
  let vals: Vec[Int] = cfg.attr_values;
  let masks: Vec[Int] = cfg.attr_masks;
  _put_u64_le(out, cfg.flags);
  _put_u32_le(out, ids.len());
  _put_zeros(out, 20);
  var i = 0;
  while i < ids.len() {
    let id: Int = ids[i];
    _put_attribute(out, id, vals[i]);
    _put_u64_le(out, masks[i]);
    i = i + 1;
  }
  _put_zeros(out, (GPIO_V2_LINE_NUM_ATTRS_MAX - ids.len()) * GPIO_V2_LINE_CONFIG_ATTRIBUTE_SIZE);
}

// Decode the 272-byte config starting at absolute offset `base`; all error
// messages use absolute offsets.
fn _config_decode_at(data: &Vec[UInt8], base: Int) -> Result[GpioLineConfig, Str] {
  let flags_r = _u64_le(data, base + GPIO_V2_LINE_CONFIG_FLAGS_OFFSET, "line config flags");
  if !flags_r.is_ok {
    return _err_config(flags_r.error);
  }
  let num_attrs = _u32_le(data, base + GPIO_V2_LINE_CONFIG_NUM_ATTRS_OFFSET);
  if !gpio_num_attrs_ok(num_attrs) {
    return _err_config("gpio: line config: num_attrs " + _dec(num_attrs) + " out of range 0..10 at offset " + _dec(base + GPIO_V2_LINE_CONFIG_NUM_ATTRS_OFFSET));
  }
  let zr = _zeros_ok(data, base + GPIO_V2_LINE_CONFIG_PADDING_OFFSET, 20, "line config");
  if !zr.is_ok {
    return _err_config(zr.error);
  }
  var ids = Vec[Int].new();
  var vals = Vec[Int].new();
  var masks = Vec[Int].new();
  var i = 0;
  while i < num_attrs {
    let aoff = base + GPIO_V2_LINE_CONFIG_ATTRS_OFFSET + i * GPIO_V2_LINE_CONFIG_ATTRIBUTE_SIZE;
    let ar = gpio_line_attribute_decode(data, aoff);
    if !ar.is_ok {
      return _err_config(ar.error);
    }
    let a: GpioLineAttribute = ar.value;
    let mr = _u64_le(data, aoff + GPIO_V2_LINE_CONFIG_ATTRIBUTE_MASK_OFFSET, "line config attr mask");
    if !mr.is_ok {
      return _err_config(mr.error);
    }
    let m: Int = mr.value;
    ids.push(a.id);
    vals.push(a.value);
    masks.push(m);
    if a.id == GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES {
      let masked = a.value & m;
      if masked != a.value {
        return _err_config("gpio: line config: attr " + _dec(i) + " output values " + _dec(a.value) + " have bits outside mask " + _dec(m));
      }
    }
    i = i + 1;
  }
  let flags: Int = flags_r.value;
  return _ok_config(GpioLineConfig{ flags: flags; attr_ids: ids; attr_values: vals; attr_masks: masks; });
}

/// Decode a 272-byte gpio_v2_line_config image.
///
/// Err("gpio: line config: truncated at offset N: need 272 bytes, have N");
/// Err("gpio: line config: buffer has N bytes, expected exactly 272");
/// Err("gpio: line config: num_attrs N out of range 0..10 at offset 8");
/// Err("gpio: line config: bad padding at offset O: expected zero byte,
/// found V") for the config padding at 12; the attribute decoder catalog for
/// each of the num_attrs entries; Err("gpio: line config: attr I output
/// values V have bits outside mask M") for an inconsistent OUTPUT_VALUES
/// entry.
pub fn gpio_line_config_decode(data: &Vec[UInt8]) -> Result[GpioLineConfig, Str] {
  let sr = _size_exact(data, GPIO_V2_LINE_CONFIG_SIZE, "line config");
  if !sr.is_ok {
    return _err_config(sr.error);
  }
  return _config_decode_at(data, 0);
}

/// Append the 272-byte gpio_v2_line_config image of `cfg` to `out` (atomic:
/// validated first).
///
/// Err("gpio: line config: flags V are negative (64-bit fields are
/// unsigned)"); Err("gpio: line config: attribute arrays out of step (A
/// ids, B values, C masks)"); Err("gpio: line config: N attributes exceed
/// the maximum of 10"); the per-attribute catalog of _attr_entry_check.
pub fn gpio_line_config_encode_into(out: &mut Vec[UInt8], cfg: &GpioLineConfig) -> Result[Unit, Str] {
  let ids: Vec[Int] = cfg.attr_ids;
  let vals: Vec[Int] = cfg.attr_values;
  let masks: Vec[Int] = cfg.attr_masks;
  if cfg.flags < 0 {
    return _err_unit("gpio: line config: flags " + _dec(cfg.flags) + " are negative (64-bit fields are unsigned)");
  }
  let ar = _attrs_check(&ids, &vals, &masks, "line config");
  if !ar.is_ok {
    return _err_unit(ar.error);
  }
  _config_write(out, cfg);
  return _ok_unit();
}

/// Encode a fresh 272-byte gpio_v2_line_config image. Same error catalog as
/// gpio_line_config_encode_into.
pub fn gpio_line_config_encode(cfg: &GpioLineConfig) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let r = gpio_line_config_encode_into(&mut out, cfg);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  return _ok_bytes(out);
}

/// A new empty config: flags 0, no attributes.
pub fn gpio_line_config_new() -> GpioLineConfig {
  return GpioLineConfig{ flags: 0; attr_ids: Vec[Int].new(); attr_values: Vec[Int].new(); attr_masks: Vec[Int].new(); };
}

/// Set the default flags of `cfg`.
///
/// Err("gpio: line config: flags V are negative (64-bit fields are
/// unsigned)").
pub fn gpio_line_config_set_flags(cfg: &mut GpioLineConfig, flags: Int) -> Result[Unit, Str] {
  if flags < 0 {
    return _err_unit("gpio: line config: flags " + _dec(flags) + " are negative (64-bit fields are unsigned)");
  }
  cfg.flags = flags;
  return _ok_unit();
}

/// Append one attribute to `cfg` (mirrored pushes into the three arrays).
///
/// Err("gpio: line config: cannot add an 11th attribute") at the limit, plus
/// the _attr_entry_check catalog.
pub fn gpio_line_config_add_attr(cfg: &mut GpioLineConfig, id: Int, value: Int, mask: Int) -> Result[Unit, Str] {
  let cur: Vec[Int] = cfg.attr_ids;
  if cur.len() >= GPIO_V2_LINE_NUM_ATTRS_MAX {
    return _err_unit("gpio: line config: cannot add an 11th attribute");
  }
  let r = _attr_entry_check(id, value, mask, cur.len(), "line config");
  if !r.is_ok {
    return _err_unit(r.error);
  }
  cfg.attr_ids.push(id);
  cfg.attr_values.push(value);
  cfg.attr_masks.push(mask);
  return _ok_unit();
}

// --------------------------------------------------
//  gpio_v2_line_request codec
// --------------------------------------------------

/// Decode a 592-byte gpio_v2_line_request image.
///
/// Err("gpio: line request: truncated at offset N: need 592 bytes, have N");
/// Err("gpio: line request: buffer has N bytes, expected exactly 592");
/// Err("gpio: line request: num_lines N out of range 1..64 at offset 560");
/// Err("gpio: line request: duplicate line offset V at offsets entry I
/// (byte offset B)"); the config and attribute catalogs with their absolute
/// offsets; Err("gpio: line request: bad padding at offset O: expected zero
/// byte, found V") for the request padding at 568. `fd` is returned as its
/// raw unsigned 32-bit image.
pub fn gpio_line_request_decode(data: &Vec[UInt8]) -> Result[GpioLineRequest, Str] {
  let sr = _size_exact(data, GPIO_V2_LINE_REQUEST_SIZE, "line request");
  if !sr.is_ok {
    return _err_request(sr.error);
  }
  let num_lines = _u32_le(data, GPIO_V2_LINE_REQUEST_NUM_LINES_OFFSET);
  if !gpio_num_lines_ok(num_lines) {
    return _err_request("gpio: line request: num_lines " + _dec(num_lines) + " out of range 1..64 at offset " + _dec(GPIO_V2_LINE_REQUEST_NUM_LINES_OFFSET));
  }
  var offs = Vec[Int].new();
  var i = 0;
  while i < num_lines {
    let v = _u32_le(data, i * 4);
    var j = 0;
    while j < i {
      let prev: Int = offs[j];
      if prev == v {
        return _err_request("gpio: line request: duplicate line offset " + _dec(v) + " at offsets entry " + _dec(i) + " (byte offset " + _dec(i * 4) + ")");
      }
      j = j + 1;
    }
    offs.push(v);
    i = i + 1;
  }
  let consumer_r = _cstr32(data, GPIO_V2_LINE_REQUEST_CONSUMER_OFFSET, "consumer");
  if !consumer_r.is_ok {
    return _err_request(consumer_r.error);
  }
  let cfg_r = _config_decode_at(data, GPIO_V2_LINE_REQUEST_CONFIG_OFFSET);
  if !cfg_r.is_ok {
    return _err_request(cfg_r.error);
  }
  let cfg: GpioLineConfig = cfg_r.value;
  let event_buffer_size = _u32_le(data, GPIO_V2_LINE_REQUEST_EVENT_BUFFER_SIZE_OFFSET);
  let zr = _zeros_ok(data, GPIO_V2_LINE_REQUEST_PADDING_OFFSET, 20, "line request");
  if !zr.is_ok {
    return _err_request(zr.error);
  }
  let fd = _u32_le(data, GPIO_V2_LINE_REQUEST_FD_OFFSET);
  let consumer: Str = consumer_r.value;
  return _ok_request(GpioLineRequest{
    offsets: offs;
    consumer: consumer;
    num_lines: num_lines;
    event_buffer_size: event_buffer_size;
    fd: fd;
    config_flags: cfg.flags;
    attr_ids: cfg.attr_ids;
    attr_values: cfg.attr_values;
    attr_masks: cfg.attr_masks;
  });
}

/// Append the 592-byte gpio_v2_line_request image of `req` to `out` (atomic:
/// validated first). The offsets array must hold exactly `num_lines`
/// entries, the entries must be unique u32 values, and the consumer name at
/// most 31 bytes plus NUL.
///
/// Err("gpio: line request: num_lines N out of range 1..64"); Err("gpio:
/// line request: offsets length N does not match num_lines M"); Err("gpio:
/// line request: duplicate line offset V at offsets entry I"); Err("gpio:
/// line request: line offset V at offsets entry I does not fit in u32");
/// Err("gpio: consumer is N bytes, needs at most 31 plus NUL within 32");
/// Err("gpio: line request: event_buffer_size N does not fit in u32");
/// Err("gpio: line request: fd N does not fit in u32"); plus the config
/// catalog.
pub fn gpio_line_request_encode_into(out: &mut Vec[UInt8], req: &GpioLineRequest) -> Result[Unit, Str] {
  let offs: Vec[Int] = req.offsets;
  let ids: Vec[Int] = req.attr_ids;
  let vals: Vec[Int] = req.attr_values;
  let masks: Vec[Int] = req.attr_masks;
  let nl = req.num_lines;
  if !gpio_num_lines_ok(nl) {
    return _err_unit("gpio: line request: num_lines " + _dec(nl) + " out of range 1..64");
  }
  if offs.len() != nl {
    return _err_unit("gpio: line request: offsets length " + _dec(offs.len()) + " does not match num_lines " + _dec(nl));
  }
  var i = 0;
  while i < offs.len() {
    let v: Int = offs[i];
    if !_u32_fits(v) {
      return _err_unit("gpio: line request: line offset " + _dec(v) + " at offsets entry " + _dec(i) + " does not fit in u32");
    }
    var j = 0;
    while j < i {
      let prev: Int = offs[j];
      if prev == v {
        return _err_unit("gpio: line request: duplicate line offset " + _dec(v) + " at offsets entry " + _dec(i));
      }
      j = j + 1;
    }
    i = i + 1;
  }
  let cr = _validate_name(req.consumer, "consumer");
  if !cr.is_ok {
    return _err_unit(cr.error);
  }
  if !_u32_fits(req.event_buffer_size) {
    return _err_unit("gpio: line request: event_buffer_size " + _dec(req.event_buffer_size) + " does not fit in u32");
  }
  if !_u32_fits(req.fd) {
    return _err_unit("gpio: line request: fd " + _dec(req.fd) + " does not fit in u32");
  }
  if req.config_flags < 0 {
    return _err_unit("gpio: line config: flags " + _dec(req.config_flags) + " are negative (64-bit fields are unsigned)");
  }
  let ar = _attrs_check(&ids, &vals, &masks, "line config");
  if !ar.is_ok {
    return _err_unit(ar.error);
  }
  i = 0;
  while i < nl {
    _put_u32_le(out, offs[i]);
    i = i + 1;
  }
  _put_zeros(out, (GPIO_V2_LINES_MAX - nl) * 4);
  _put_cstr32(out, req.consumer);
  let cfg = GpioLineConfig{ flags: req.config_flags; attr_ids: ids; attr_values: vals; attr_masks: masks; };
  _config_write(out, &cfg);
  _put_u32_le(out, nl);
  _put_u32_le(out, req.event_buffer_size);
  _put_zeros(out, 20);
  _put_u32_le(out, req.fd);
  return _ok_unit();
}

/// Encode a fresh 592-byte gpio_v2_line_request image. Same error catalog as
/// gpio_line_request_encode_into.
pub fn gpio_line_request_encode(req: &GpioLineRequest) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let r = gpio_line_request_encode_into(&mut out, req);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  return _ok_bytes(out);
}

/// A new empty request: no offsets, empty consumer, zero config. Set
/// num_lines by adding offsets.
pub fn gpio_line_request_new() -> GpioLineRequest {
  return GpioLineRequest{
    offsets: Vec[Int].new();
    consumer: "";
    num_lines: 0;
    event_buffer_size: 0;
    fd: 0;
    config_flags: 0;
    attr_ids: Vec[Int].new();
    attr_values: Vec[Int].new();
    attr_masks: Vec[Int].new();
  };
}

/// Append one line offset to `req` and bump `num_lines` (mirrored update).
///
/// Err("gpio: line request: cannot request more than 64 lines"); Err("gpio:
/// line request: line offset V does not fit in u32"); Err("gpio: line
/// request: duplicate line offset V").
pub fn gpio_line_request_add_offset(req: &mut GpioLineRequest, offset: Int) -> Result[Unit, Str] {
  let cur: Vec[Int] = req.offsets;
  if cur.len() >= GPIO_V2_LINES_MAX {
    return _err_unit("gpio: line request: cannot request more than 64 lines");
  }
  if !_u32_fits(offset) {
    return _err_unit("gpio: line request: line offset " + _dec(offset) + " does not fit in u32");
  }
  var j = 0;
  while j < cur.len() {
    let prev: Int = cur[j];
    if prev == offset {
      return _err_unit("gpio: line request: duplicate line offset " + _dec(offset));
    }
    j = j + 1;
  }
  req.offsets.push(offset);
  req.num_lines = req.num_lines + 1;
  return _ok_unit();
}

/// Set the consumer name of `req`.
///
/// Err("gpio: consumer is N bytes, needs at most 31 plus NUL within 32");
/// Err("gpio: consumer has an embedded NUL at byte I").
pub fn gpio_line_request_set_consumer(req: &mut GpioLineRequest, name: Str) -> Result[Unit, Str] {
  let vr = _validate_name(name, "consumer");
  if !vr.is_ok {
    return _err_unit(vr.error);
  }
  req.consumer = name;
  return _ok_unit();
}

/// Set the default config flags of `req`.
///
/// Err("gpio: line config: flags V are negative (64-bit fields are
/// unsigned)").
pub fn gpio_line_request_set_config_flags(req: &mut GpioLineRequest, flags: Int) -> Result[Unit, Str] {
  if flags < 0 {
    return _err_unit("gpio: line config: flags " + _dec(flags) + " are negative (64-bit fields are unsigned)");
  }
  req.config_flags = flags;
  return _ok_unit();
}

// --------------------------------------------------
//  gpio_v2_line_info codec
// --------------------------------------------------

/// Decode a 256-byte gpio_v2_line_info image. `line_offset` is the uAPI
/// `offset` field; `num_attrs` bounds the decoded attribute entries.
///
/// Err("gpio: line info: truncated at offset N: need 256 bytes, have N");
/// Err("gpio: line info: buffer has N bytes, expected exactly 256");
/// Err("gpio: name at offset 0 has no NUL within 32 bytes") and the same
/// for `consumer` at 32; Err("gpio: line info: num_attrs N out of range
/// 0..10 at offset 68"); the attribute decoder catalog; Err("gpio: line
/// info: bad padding at offset O: expected zero byte, found V") for the
/// trailing padding at 240.
pub fn gpio_line_info_decode(data: &Vec[UInt8]) -> Result[GpioLineInfo, Str] {
  let sr = _size_exact(data, GPIO_V2_LINE_INFO_SIZE, "line info");
  if !sr.is_ok {
    return _err_info(sr.error);
  }
  let name_r = _cstr32(data, GPIO_V2_LINE_INFO_NAME_OFFSET, "name");
  if !name_r.is_ok {
    return _err_info(name_r.error);
  }
  let consumer_r = _cstr32(data, GPIO_V2_LINE_INFO_CONSUMER_OFFSET, "consumer");
  if !consumer_r.is_ok {
    return _err_info(consumer_r.error);
  }
  let line_offset = _u32_le(data, GPIO_V2_LINE_INFO_LINE_OFFSET_OFFSET);
  let num_attrs = _u32_le(data, GPIO_V2_LINE_INFO_NUM_ATTRS_OFFSET);
  if !gpio_num_attrs_ok(num_attrs) {
    return _err_info("gpio: line info: num_attrs " + _dec(num_attrs) + " out of range 0..10 at offset " + _dec(GPIO_V2_LINE_INFO_NUM_ATTRS_OFFSET));
  }
  let flags_r = _u64_le(data, GPIO_V2_LINE_INFO_FLAGS_OFFSET, "line info flags");
  if !flags_r.is_ok {
    return _err_info(flags_r.error);
  }
  var ids = Vec[Int].new();
  var vals = Vec[Int].new();
  var i = 0;
  while i < num_attrs {
    let aoff = GPIO_V2_LINE_INFO_ATTRS_OFFSET + i * GPIO_V2_LINE_ATTRIBUTE_SIZE;
    let ar = gpio_line_attribute_decode(data, aoff);
    if !ar.is_ok {
      return _err_info(ar.error);
    }
    let a: GpioLineAttribute = ar.value;
    ids.push(a.id);
    vals.push(a.value);
    i = i + 1;
  }
  let zr = _zeros_ok(data, GPIO_V2_LINE_INFO_PADDING_OFFSET, 16, "line info");
  if !zr.is_ok {
    return _err_info(zr.error);
  }
  let nm: Str = name_r.value;
  let cs: Str = consumer_r.value;
  let fl: Int = flags_r.value;
  return _ok_info(GpioLineInfo{ name: nm; consumer: cs; line_offset: line_offset; num_attrs: num_attrs; flags: fl; attr_ids: ids; attr_values: vals; });
}

/// Append the 256-byte gpio_v2_line_info image of `info` to `out` (atomic:
/// validated first).
///
/// Err("gpio: name is N bytes, needs at most 31 plus NUL within 32") and the
/// same for `consumer`; Err("gpio: line info: line offset V does not fit in
/// u32"); Err("gpio: line info: num_attrs N out of range 0..10"); Err("gpio:
/// line info: num_attrs N does not match A id / B value entries"); Err("gpio:
/// line info: attribute arrays out of step (A ids, B values)"); the
/// attribute id catalog; Err("gpio: line info: flags V are negative (64-bit
/// fields are unsigned)").
pub fn gpio_line_info_encode_into(out: &mut Vec[UInt8], info: &GpioLineInfo) -> Result[Unit, Str] {
  let ids: Vec[Int] = info.attr_ids;
  let vals: Vec[Int] = info.attr_values;
  let nr = _validate_name(info.name, "name");
  if !nr.is_ok {
    return _err_unit(nr.error);
  }
  let cr = _validate_name(info.consumer, "consumer");
  if !cr.is_ok {
    return _err_unit(cr.error);
  }
  if !_u32_fits(info.line_offset) {
    return _err_unit("gpio: line info: line offset " + _dec(info.line_offset) + " does not fit in u32");
  }
  if !gpio_num_attrs_ok(info.num_attrs) {
    return _err_unit("gpio: line info: num_attrs " + _dec(info.num_attrs) + " out of range 0..10");
  }
  if ids.len() != info.num_attrs || vals.len() != info.num_attrs {
    return _err_unit("gpio: line info: num_attrs " + _dec(info.num_attrs) + " does not match " + _dec(ids.len()) + " id / " + _dec(vals.len()) + " value entries");
  }
  if ids.len() != vals.len() {
    return _err_unit("gpio: line info: attribute arrays out of step (" + _dec(ids.len()) + " ids, " + _dec(vals.len()) + " values)");
  }
  var i = 0;
  while i < ids.len() {
    let id: Int = ids[i];
    let v: Int = vals[i];
    if !gpio_attr_id_ok(id) {
      return _err_unit("gpio: line info: attr " + _dec(i) + " has unknown id " + _dec(id));
    }
    if v < 0 {
      return _err_unit("gpio: line info: attr " + _dec(i) + " has a negative value (" + _dec(v) + ")");
    }
    if id == GPIO_V2_LINE_ATTR_ID_DEBOUNCE && !_u32_fits(v) {
      return _err_unit("gpio: line info: attr " + _dec(i) + " debounce period " + _dec(v) + " does not fit in u32");
    }
    i = i + 1;
  }
  if info.flags < 0 {
    return _err_unit("gpio: line info: flags " + _dec(info.flags) + " are negative (64-bit fields are unsigned)");
  }
  _put_cstr32(out, info.name);
  _put_cstr32(out, info.consumer);
  _put_u32_le(out, info.line_offset);
  _put_u32_le(out, info.num_attrs);
  _put_u64_le(out, info.flags);
  i = 0;
  while i < ids.len() {
    let id: Int = ids[i];
    _put_attribute(out, id, vals[i]);
    i = i + 1;
  }
  _put_zeros(out, (GPIO_V2_LINE_NUM_ATTRS_MAX - ids.len()) * GPIO_V2_LINE_ATTRIBUTE_SIZE);
  _put_zeros(out, 16);
  return _ok_unit();
}

/// Encode a fresh 256-byte gpio_v2_line_info image. Same error catalog as
/// gpio_line_info_encode_into.
pub fn gpio_line_info_encode(info: &GpioLineInfo) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let r = gpio_line_info_encode_into(&mut out, info);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  gpio_v2_line_event codec
// --------------------------------------------------

/// Decode a 48-byte gpio_v2_line_event image. `line_offset` is the uAPI
/// `offset` field and `global_seqno` the uAPI `seqno` field.
///
/// Err("gpio: line event: truncated at offset N: need 48 bytes, have N");
/// Err("gpio: line event: buffer has N bytes, expected exactly 48");
/// Err("gpio: line event: 64-bit value at offset 0 has bit 63 set (not
/// representable as Int)") when the timestamp's top bit is set;
/// Err("gpio: line event: unknown event id N at offset 8") when the id is
/// not 1..2; Err("gpio: line event: bad padding at offset O: expected zero
/// byte, found V") for the padding at 24.
pub fn gpio_line_event_decode(data: &Vec[UInt8]) -> Result[GpioLineEvent, Str] {
  let sr = _size_exact(data, GPIO_V2_LINE_EVENT_SIZE, "line event");
  if !sr.is_ok {
    return _err_event(sr.error);
  }
  let ts_r = _u64_le(data, GPIO_V2_LINE_EVENT_TIMESTAMP_OFFSET, "line event");
  if !ts_r.is_ok {
    return _err_event(ts_r.error);
  }
  let id = _u32_le(data, GPIO_V2_LINE_EVENT_ID_OFFSET);
  if !gpio_event_type_ok(id) {
    return _err_event("gpio: line event: unknown event id " + _dec(id) + " at offset " + _dec(GPIO_V2_LINE_EVENT_ID_OFFSET));
  }
  let line_offset = _u32_le(data, GPIO_V2_LINE_EVENT_LINE_OFFSET_OFFSET);
  let seqno = _u32_le(data, GPIO_V2_LINE_EVENT_SEQNO_OFFSET);
  let line_seqno = _u32_le(data, GPIO_V2_LINE_EVENT_LINE_SEQNO_OFFSET);
  let zr = _zeros_ok(data, GPIO_V2_LINE_EVENT_PADDING_OFFSET, 24, "line event");
  if !zr.is_ok {
    return _err_event(zr.error);
  }
  let ts: Int = ts_r.value;
  return _ok_event(GpioLineEvent{ timestamp_ns: ts; event_type: id; line_offset: line_offset; global_seqno: seqno; line_seqno: line_seqno; });
}

/// Append the 48-byte gpio_v2_line_event image of `ev` to `out` (atomic:
/// validated first).
///
/// Err("gpio: line event: timestamp V is negative"); Err("gpio: line event:
/// event id V is not 1 (rising) or 2 (falling)"); Err("gpio: line event:
/// line offset V does not fit in u32") and the same for `global_seqno` and
/// `line_seqno`.
pub fn gpio_line_event_encode_into(out: &mut Vec[UInt8], ev: &GpioLineEvent) -> Result[Unit, Str] {
  if ev.timestamp_ns < 0 {
    return _err_unit("gpio: line event: timestamp " + _dec(ev.timestamp_ns) + " is negative");
  }
  if !gpio_event_type_ok(ev.event_type) {
    return _err_unit("gpio: line event: event id " + _dec(ev.event_type) + " is not 1 (rising) or 2 (falling)");
  }
  if !_u32_fits(ev.line_offset) {
    return _err_unit("gpio: line event: line offset " + _dec(ev.line_offset) + " does not fit in u32");
  }
  if !_u32_fits(ev.global_seqno) {
    return _err_unit("gpio: line event: global_seqno " + _dec(ev.global_seqno) + " does not fit in u32");
  }
  if !_u32_fits(ev.line_seqno) {
    return _err_unit("gpio: line event: line_seqno " + _dec(ev.line_seqno) + " does not fit in u32");
  }
  _put_u64_le(out, ev.timestamp_ns);
  _put_u32_le(out, ev.event_type);
  _put_u32_le(out, ev.line_offset);
  _put_u32_le(out, ev.global_seqno);
  _put_u32_le(out, ev.line_seqno);
  _put_zeros(out, 24);
  return _ok_unit();
}

/// Encode a fresh 48-byte gpio_v2_line_event image. Same error catalog as
/// gpio_line_event_encode_into.
pub fn gpio_line_event_encode(ev: &GpioLineEvent) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let r = gpio_line_event_encode_into(&mut out, ev);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  gpio_v2_line_values codec
// --------------------------------------------------

/// Decode a 16-byte gpio_v2_line_values image (the bits/mask pair used by
/// the OUTPUT_VALUES attribute for default output values).
///
/// Err("gpio: line values: truncated at offset N: need 16 bytes, have N");
/// Err("gpio: line values: buffer has N bytes, expected exactly 16");
/// Err("gpio: line values bits: 64-bit value at offset 0 has bit 63 set
/// (not representable as Int)") and the same for the mask at offset 8.
pub fn gpio_line_values_decode(data: &Vec[UInt8]) -> Result[GpioLineValues, Str] {
  let sr = _size_exact(data, GPIO_V2_LINE_VALUES_SIZE, "line values");
  if !sr.is_ok {
    return _err_values(sr.error);
  }
  let bits_r = _u64_le(data, GPIO_V2_LINE_VALUES_BITS_OFFSET, "line values bits");
  if !bits_r.is_ok {
    return _err_values(bits_r.error);
  }
  let mask_r = _u64_le(data, GPIO_V2_LINE_VALUES_MASK_OFFSET, "line values mask");
  if !mask_r.is_ok {
    return _err_values(mask_r.error);
  }
  let b: Int = bits_r.value;
  let m: Int = mask_r.value;
  return _ok_values(GpioLineValues{ bits: b; mask: m; });
}

/// Append the 16-byte gpio_v2_line_values image of `values` to `out`
/// (atomic: validated first).
///
/// Err("gpio: line values: bits V are negative (64-bit fields are
/// unsigned)") and the same for the mask.
pub fn gpio_line_values_encode_into(out: &mut Vec[UInt8], values: &GpioLineValues) -> Result[Unit, Str] {
  if values.bits < 0 {
    return _err_unit("gpio: line values: bits " + _dec(values.bits) + " are negative (64-bit fields are unsigned)");
  }
  if values.mask < 0 {
    return _err_unit("gpio: line values: mask " + _dec(values.mask) + " are negative (64-bit fields are unsigned)");
  }
  _put_u64_le(out, values.bits);
  _put_u64_le(out, values.mask);
  return _ok_unit();
}

/// Encode a fresh 16-byte gpio_v2_line_values image. Same error catalog as
/// gpio_line_values_encode_into.
pub fn gpio_line_values_encode(values: &GpioLineValues) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  let r = gpio_line_values_encode_into(&mut out, values);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  return _ok_bytes(out);
}
