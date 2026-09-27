// XIOM -- xiom.pulsar: Apache Pulsar wire codec for a documented subset
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no brokers, no client state) codec for the
// byte-level protocol of Apache Pulsar, operating on complete in-memory
// buffers. In scope:
//   * the protobuf-wire subset Pulsar uses: base-128 varints (u32/u64,
//     10 bytes max, overflow rejection), wire types 0 varint / 1 fixed64 /
//     2 length-delimited / 5 fixed32, field keys (field_number * 8 +
//     wire_type), length-delimited nested messages with a nesting cap,
//     packed repeated varints, and unknown-field skipping with bounds.
//   * the Pulsar frame: u32 totalSize | u32 commandSize | BaseCommand bytes
//     [| u32 metadataSize | MessageMetadata bytes | payload] (the bracketed
//     tail only for SEND), with consumed counts and byte-offset errors.
//   * the BaseCommand envelope and the decoded command subset documented in
//     SPEC.md: CONNECT, CONNECTED, SUBSCRIBE, PRODUCER, SEND, SEND_RECEIPT,
//     SEND_ERROR, MESSAGE, ACK, FLOW, UNSUBSCRIBE, SUCCESS, ERROR,
//     CLOSE_PRODUCER, CLOSE_CONSUMER, PRODUCER_SUCCESS, PING, PONG,
//     REDELIVER_UNACKNOWLEDGED_MESSAGES, PARTITIONED_METADATA(_RESPONSE),
//     LOOKUP(_RESPONSE), GET_LAST_MESSAGE_ID, GET_TOPICS_OF_NAMESPACE.
//     Fields outside the decoded subset are preserved raw (see
//     `PulsarCommand.raw` and `PulsarCommand.unknown_bytes`) and counted.
//   * MessageIdData (ledger_id, entry_id, partition, batch_index, ack_set
//     with a 63-bit bitset summary) and the MessageMetadata subset
//     (producer_name, sequence_id, publish_time, properties, partition_key,
//     event_time, deliver_at_time, compression, uncompressed_size).
//
// Documented boundaries (see SPEC.md):
//   * every read is bounds-checked; truncation reports the first missing
//     byte offset, malformed values report the value/field offset;
//   * XIOM Int is signed 64-bit: a u64 wire value >= 2^63 is rejected by the
//     unsigned reader instead of being truncated, and the ack_set bitset
//     summary uses 63 bit positions (entry v sets bit v % 63);
//   * `pulsar_parse_frame_at` ignores bytes after the frame; the frame's
//     `frame_len` is the consumed count;
//   * depth is capped at pulsar_max_depth() (16).
//
// v0.61.3 notes that shaped this module:
//   * free functions only; Ok/Err construction is confined to the leaf
//     helpers below (struct payloads are only wrapped there);
//   * every byte read widens with `(b as Int) & 0xFF`;
//   * Vec reads are bound to typed locals first; Str values are compared
//     with xiom.string.compare, never with `==`;
//   * `&struct.field` is never passed where `&Vec[UInt8]` is expected:
//     values are copied into typed locals first;
//   * struct fields are mutated only through a local `var` or through the
//     `&mut` struct parameter helpers (the pattern proven in xiom.amqp);
//   * numeric widths use division/modulo, never bit shifts.

module xiom.pulsar

use xiom.string;
use xiom.string.builder;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

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

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
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

// Ok(v) for Result[PulsarScalar, Str].
fn _ok_scalar(v: PulsarScalar) -> Result[PulsarScalar, Str] {
  return Ok(v);
}

// Err(m) for Result[PulsarScalar, Str].
fn _err_scalar(m: Str) -> Result[PulsarScalar, Str] {
  return Err(m);
}

// Ok(v) for Result[PulsarAdvance, Str].
fn _ok_advance(v: PulsarAdvance) -> Result[PulsarAdvance, Str] {
  return Ok(v);
}

// Err(m) for Result[PulsarAdvance, Str].
fn _err_advance(m: Str) -> Result[PulsarAdvance, Str] {
  return Err(m);
}

// Ok(v) for Result[PulsarDelimited, Str].
fn _ok_delim(v: PulsarDelimited) -> Result[PulsarDelimited, Str] {
  return Ok(v);
}

// Err(m) for Result[PulsarDelimited, Str].
fn _err_delim(m: Str) -> Result[PulsarDelimited, Str] {
  return Err(m);
}

// Ok(v) for Result[PulsarFieldValue, Str].
fn _ok_fv(v: PulsarFieldValue) -> Result[PulsarFieldValue, Str] {
  return Ok(v);
}

// Err(m) for Result[PulsarFieldValue, Str].
fn _err_fv(m: Str) -> Result[PulsarFieldValue, Str] {
  return Err(m);
}

// Ok(v) for Result[PulsarFieldStep, Str].
fn _ok_step(v: PulsarFieldStep) -> Result[PulsarFieldStep, Str] {
  return Ok(v);
}

// Err(m) for Result[PulsarFieldStep, Str].
fn _err_step(m: Str) -> Result[PulsarFieldStep, Str] {
  return Err(m);
}

// Ok(v) for Result[PulsarMessageId, Str].
fn _ok_mid(v: PulsarMessageId) -> Result[PulsarMessageId, Str] {
  return Ok(v);
}

// Err(m) for Result[PulsarMessageId, Str].
fn _err_mid(m: Str) -> Result[PulsarMessageId, Str] {
  return Err(m);
}

// Ok(v) for Result[PulsarMidRead, Str].
fn _ok_midread(v: PulsarMidRead) -> Result[PulsarMidRead, Str] {
  return Ok(v);
}

// Err(m) for Result[PulsarMidRead, Str].
fn _err_midread(m: Str) -> Result[PulsarMidRead, Str] {
  return Err(m);
}

// Ok(v) for Result[PulsarMessageMetadata, Str].
fn _ok_meta(v: PulsarMessageMetadata) -> Result[PulsarMessageMetadata, Str] {
  return Ok(v);
}

// Err(m) for Result[PulsarMessageMetadata, Str].
fn _err_meta(m: Str) -> Result[PulsarMessageMetadata, Str] {
  return Err(m);
}

// Ok(v) for Result[PulsarMetaRead, Str].
fn _ok_metaread(v: PulsarMetaRead) -> Result[PulsarMetaRead, Str] {
  return Ok(v);
}

// Err(m) for Result[PulsarMetaRead, Str].
fn _err_metaread(m: Str) -> Result[PulsarMetaRead, Str] {
  return Err(m);
}

// Ok(v) for Result[PulsarCommand, Str].
fn _ok_cmd(v: PulsarCommand) -> Result[PulsarCommand, Str] {
  return Ok(v);
}

// Err(m) for Result[PulsarCommand, Str].
fn _err_cmd(m: Str) -> Result[PulsarCommand, Str] {
  return Err(m);
}

// Ok(v) for Result[PulsarFrame, Str].
fn _ok_frame(v: PulsarFrame) -> Result[PulsarFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[PulsarFrame, Str].
fn _err_frame(m: Str) -> Result[PulsarFrame, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// One decoded integer scalar and the number of wire bytes it consumed.
pub type PulsarScalar = {
  value: Int;
  size: Int;
}

/// A new cursor position and the number of bytes consumed to reach it.
pub type PulsarAdvance = {
  pos: Int;
  size: Int;
}

/// A length-delimited value: `start` is the first payload byte, `size` the
/// payload length and `total` the bytes consumed (length prefix + payload).
pub type PulsarDelimited = {
  start: Int;
  size: Int;
  total: Int;
}

/// One decoded protobuf field value (without its key). `wire_type` is
/// 0/1/2/5; `int_value` carries the scalar for 0/1/5; `start`/`size` carry
/// the payload span for 2; `total` is the value's wire size in bytes.
pub type PulsarFieldValue = {
  wire_type: Int;
  int_value: Int;
  start: Int;
  size: Int;
  total: Int;
}

/// One decoded protobuf field: key metadata plus the value, and `next`, the
/// absolute offset of the field after this one.
pub type PulsarFieldStep = {
  field_number: Int;
  wire_type: Int;
  tag_start: Int;
  key_size: Int;
  value: PulsarFieldValue;
  next: Int;
}

/// Decoded MessageIdData. `partition` and `batch_index` keep Pulsar's -1
/// default when the field is absent. `ack_set` holds every decoded ack
/// entry; `ack_set_bits` is a 63-bit summary (bit v % 63 is set for each
/// non-negative entry v -- bit 63 is not representable in a signed XIOM Int).
pub type PulsarMessageId = {
  ledger_id: Int;
  entry_id: Int;
  partition: Int;
  batch_index: Int;
  ack_set: Vec[Int];
  ack_set_bits: Int;
}

/// A decoded length-delimited MessageIdData plus the offset after it.
pub type PulsarMidRead = {
  id: PulsarMessageId;
  pos: Int;
}

/// A flat list of MessageIdData: five parallel vectors, one entry per id,
/// never a Vec[StructType]. `ack_bits` mirrors each id's `ack_set_bits`.
pub type PulsarMessageIdList = {
  ledger_ids: Vec[Int];
  entry_ids: Vec[Int];
  partitions: Vec[Int];
  batch_indexes: Vec[Int];
  ack_bits: Vec[Int];
}

/// Decoded MessageMetadata subset. `property_keys`/`property_values` are
/// index-aligned; they never drift (one mirrored push per pair). The has_
/// flags record wire presence (proto2 defaults are not synthesized for
/// strings; numeric defaults are noted per field in SPEC.md).
pub type PulsarMessageMetadata = {
  producer_name: Str;
  sequence_id: Int;
  publish_time: Int;
  partition_key: Str;
  event_time: Int;
  deliver_at_time: Int;
  compression: Int;
  uncompressed_size: Int;
  property_keys: Vec[Vec[UInt8]];
  property_values: Vec[Vec[UInt8]];
  has_producer_name: Bool;
  has_sequence_id: Bool;
  has_publish_time: Bool;
  has_partition_key: Bool;
  has_event_time: Bool;
  has_deliver_at_time: Bool;
  has_compression: Bool;
  has_uncompressed_size: Bool;
  unknown_fields: Int;
}

/// A decoded length-delimited MessageMetadata plus the offset after it.
pub type PulsarMetaRead = {
  metadata: PulsarMessageMetadata;
  pos: Int;
}

/// Decoded BaseCommand. `cmd_type` is the BaseCommand.Type wire value,
/// `known` tells whether the type is in the decoded subset, `raw` is a copy
/// of the whole command body, and `unknown_bytes` concatenates the raw
/// tag+value bytes of every field outside the decoded subset.
pub type PulsarCommand = {
  cmd_type: Int;
  known: Bool;
  has_body: Bool;
  field_count: Int;
  unknown_fields: Int;
  raw: Vec[UInt8];
  unknown_bytes: Vec[UInt8];
  client_version: Str;
  auth_method_name: Str;
  protocol_version: Int;
  has_protocol_version: Bool;
  server_version: Str;
  max_message_size: Int;
  has_max_message_size: Bool;
  topic: Str;
  subscription: Str;
  sub_type: Int;
  consumer_id: Int;
  producer_id: Int;
  request_id: Int;
  durable: Bool;
  has_durable: Bool;
  producer_name: Str;
  sequence_id: Int;
  num_messages: Int;
  has_num_messages: Bool;
  publish_time: Int;
  redelivery_count: Int;
  message_id: PulsarMessageId;
  has_message_id: Bool;
  msg_ack_set: Vec[Int];
  msg_ack_bits: Int;
  ack_type: Int;
  ack_ids: PulsarMessageIdList;
  message_permits: Int;
  has_message_permits: Bool;
  error_code: Int;
  has_error_code: Bool;
  error_message: Str;
  has_error_message: Bool;
  last_sequence_id: Int;
  has_last_sequence_id: Bool;
  partitions: Int;
  has_partitions: Bool;
  partition_names: Vec[Vec[UInt8]];
  response_code: Int;
  has_response_code: Bool;
  broker_url: Str;
  broker_url_tls: Str;
  namespace: Str;
}

/// One parsed Pulsar frame. `frame_len` is the total consumed size
/// (4 + total_size); `command_offset` and `payload_offset` are absolute
/// offsets into the parsed buffer. `has_metadata` is true only for a SEND
/// frame with the metadata tail present. For non-SEND commands every byte
/// after the command is kept raw in `payload`.
pub type PulsarFrame = {
  total_size: Int;
  command_size: Int;
  command_offset: Int;
  metadata_size: Int;
  payload_offset: Int;
  frame_len: Int;
  has_metadata: Bool;
  command: PulsarCommand;
  metadata: PulsarMessageMetadata;
  payload: Vec[UInt8];
}

// --------------------------------------------------
//  Constants
// --------------------------------------------------

/// Highest ProtocolVersion documented by the vendored PulsarApi subset
/// (v21 carries AUTO_CONSUME schema handling).
pub fn pulsar_protocol_version() -> Int {
  return 21;
}

/// Maximum bytes in one base-128 varint.
pub fn pulsar_max_varint_bytes() -> Int {
  return 10;
}

/// Nesting cap for length-delimited message parsing.
pub fn pulsar_max_depth() -> Int {
  return 16;
}

/// Upper bound on the ack_set entries kept per MessageIdData.
pub fn pulsar_max_ack_set_entries() -> Int {
  return 4096;
}

/// Upper bound on the values decoded from one packed repeated run.
pub fn pulsar_max_packed_entries() -> Int {
  return 65536;
}

/// Wire type 0: base-128 varint.
pub fn pulsar_wire_varint() -> Int {
  return 0;
}

/// Wire type 1: 64-bit little-endian fixed.
pub fn pulsar_wire_fixed64() -> Int {
  return 1;
}

/// Wire type 2: varint length prefix plus payload.
pub fn pulsar_wire_length_delimited() -> Int {
  return 2;
}

/// Wire type 5: 32-bit little-endian fixed.
pub fn pulsar_wire_fixed32() -> Int {
  return 5;
}

// BaseCommand.Type values, canonical apache/pulsar PulsarApi.proto (the
// brief's "GET_LAST_MESSAGE_ID 27 / GET_TOPICS_OF_NAMESPACE 28 / LOOKUP 40"
// hints do not match the canonical enum; SPEC.md records the discrepancy).

/// CONNECT (2).
pub fn pulsar_cmd_connect() -> Int {
  return 2;
}

/// CONNECTED (3).
pub fn pulsar_cmd_connected() -> Int {
  return 3;
}

/// SUBSCRIBE (4).
pub fn pulsar_cmd_subscribe() -> Int {
  return 4;
}

/// PRODUCER (5).
pub fn pulsar_cmd_producer() -> Int {
  return 5;
}

/// SEND (6).
pub fn pulsar_cmd_send() -> Int {
  return 6;
}

/// SEND_RECEIPT (7).
pub fn pulsar_cmd_send_receipt() -> Int {
  return 7;
}

/// SEND_ERROR (8).
pub fn pulsar_cmd_send_error() -> Int {
  return 8;
}

/// MESSAGE (9).
pub fn pulsar_cmd_message() -> Int {
  return 9;
}

/// ACK (10).
pub fn pulsar_cmd_ack() -> Int {
  return 10;
}

/// FLOW (11).
pub fn pulsar_cmd_flow() -> Int {
  return 11;
}

/// UNSUBSCRIBE (12).
pub fn pulsar_cmd_unsubscribe() -> Int {
  return 12;
}

/// SUCCESS (13).
pub fn pulsar_cmd_success() -> Int {
  return 13;
}

/// ERROR (14).
pub fn pulsar_cmd_error() -> Int {
  return 14;
}

/// CLOSE_PRODUCER (15).
pub fn pulsar_cmd_close_producer() -> Int {
  return 15;
}

/// CLOSE_CONSUMER (16).
pub fn pulsar_cmd_close_consumer() -> Int {
  return 16;
}

/// PRODUCER_SUCCESS (17).
pub fn pulsar_cmd_producer_success() -> Int {
  return 17;
}

/// PING (18).
pub fn pulsar_cmd_ping() -> Int {
  return 18;
}

/// PONG (19).
pub fn pulsar_cmd_pong() -> Int {
  return 19;
}

/// REDELIVER_UNACKNOWLEDGED_MESSAGES (20).
pub fn pulsar_cmd_redeliver_unacknowledged_messages() -> Int {
  return 20;
}

/// PARTITIONED_METADATA (21).
pub fn pulsar_cmd_partitioned_metadata() -> Int {
  return 21;
}

/// PARTITIONED_METADATA_RESPONSE (22).
pub fn pulsar_cmd_partitioned_metadata_response() -> Int {
  return 22;
}

/// LOOKUP (23).
pub fn pulsar_cmd_lookup() -> Int {
  return 23;
}

/// LOOKUP_RESPONSE (24).
pub fn pulsar_cmd_lookup_response() -> Int {
  return 24;
}

/// GET_LAST_MESSAGE_ID (29).
pub fn pulsar_cmd_get_last_message_id() -> Int {
  return 29;
}

/// GET_TOPICS_OF_NAMESPACE (32).
pub fn pulsar_cmd_get_topics_of_namespace() -> Int {
  return 32;
}

/// CompressionType: NONE (0).
pub fn pulsar_compression_none() -> Int {
  return 0;
}

/// CompressionType: LZ4 (1).
pub fn pulsar_compression_lz4() -> Int {
  return 1;
}

/// CompressionType: ZLIB (2).
pub fn pulsar_compression_zlib() -> Int {
  return 2;
}

/// CompressionType: ZSTD (3).
pub fn pulsar_compression_zstd() -> Int {
  return 3;
}

/// CompressionType: SNAPPY (4).
pub fn pulsar_compression_snappy() -> Int {
  return 4;
}

/// True when `t` is one of the decoded BaseCommand types.
pub fn pulsar_cmd_type_known(t: Int) -> Bool {
  if t == 2 || t == 3 || t == 4 || t == 5 || t == 6 || t == 7 || t == 8 {
    return true;
  }
  if t == 9 || t == 10 || t == 11 || t == 12 || t == 13 || t == 14 || t == 15 {
    return true;
  }
  if t == 16 || t == 17 || t == 18 || t == 19 || t == 20 || t == 21 || t == 22 {
    return true;
  }
  if t == 23 || t == 24 || t == 29 || t == 32 {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Internal scalar helpers
// --------------------------------------------------

// 2^n for 0 <= n <= 62 (bit 63 is not representable in a signed Int).
fn _pow2(n: Int) -> Int {
  var r = 1;
  var i = 0;
  while i < n {
    r = r * 2;
    i = i + 1;
  }
  return r;
}

// Smallest Int (-2^63), written so the literal itself never overflows.
fn _min_i64() -> Int {
  return -9223372036854775807 - 1;
}

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian u32 at [pos, pos+4); callers guarantee the bounds.
fn _read_be32(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 16777216 + _byte(data, pos + 1) * 65536 + _byte(data, pos + 2) * 256 + _byte(data, pos + 3);
}

// Append `v` (0..2^32-1) as four big-endian bytes.
fn _push_be32(out: &mut Vec[UInt8], v: Int) {
  out.push((v / 16777216) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Append every byte of `v` to `out`.
fn _push_vec(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// A fresh copy of `v`.
fn _vec_copy(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_vec(&mut out, v);
  return out;
}

// A copy of the span [start, start+size) of `data`. An out-of-bounds span
// yields an empty vector; every internal caller checks the bounds first.
fn _slice(data: &Vec[UInt8], start: Int, size: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if start < 0 || size < 0 {
    return out;
  }
  if start + size > data.len() {
    return out;
  }
  var i = 0;
  while i < size {
    out.push(data[start + i]);
    i = i + 1;
  }
  return out;
}

/// Byte-wise equality of two byte vectors. Complexity: O(bytes).
pub fn pulsar_bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
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

// The bytes of a Str (UTF-8, one byte per index).
fn _str_to_bytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

// The bytes of `v` as a Str; only called on NUL-free valid UTF-8 spans, so
// sb_to_str cannot abort.
fn _bytes_to_str(v: &Vec[UInt8]) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    sb.push(v[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Build a Str from a data span (validated by the caller).
fn _span_to_str(data: &Vec[UInt8], start: Int, size: Int) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < size {
    sb.push(data[start + i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Strict UTF-8 validation of a data span (RFC 3629: overlong forms,
// surrogate halves and truncated sequences are rejected). Returns "" when
// valid, otherwise the deterministic error with the offending byte offset.
// A 0x00 byte is valid UTF-8 but reported separately because a NUL would
// abort the v0.61.3 string builder.
fn _utf8_span_error(data: &Vec[UInt8], start: Int, size: Int) -> Str {
  var i = 0;
  while i < size {
    let b = _byte(data, start + i);
    if b == 0 {
      return "pulsar: string contains nul at offset " + convert.int_to_string(start + i);
    }
    if b < 128 {
      i = i + 1;
    } elif b < 194 {
      return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
    } elif b < 224 {
      if i + 1 >= size {
        return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      let c1: Int = _byte(data, start + i + 1);
      if c1 < 128 || c1 >= 192 {
        return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      i = i + 2;
    } elif b < 240 {
      if i + 2 >= size {
        return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      let c1: Int = _byte(data, start + i + 1);
      let c2: Int = _byte(data, start + i + 2);
      if c1 < 128 || c1 >= 192 {
        return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if c2 < 128 || c2 >= 192 {
        return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if b == 224 && c1 < 160 {
        return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if b == 237 && c1 >= 160 {
        return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      i = i + 3;
    } elif b < 245 {
      if i + 3 >= size {
        return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      let c1: Int = _byte(data, start + i + 1);
      let c2: Int = _byte(data, start + i + 2);
      let c3: Int = _byte(data, start + i + 3);
      if c1 < 128 || c1 >= 192 {
        return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if c2 < 128 || c2 >= 192 {
        return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if c3 < 128 || c3 >= 192 {
        return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if b == 240 && c1 < 144 {
        return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if b == 244 && c1 >= 144 {
        return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      i = i + 4;
    } else {
      return "pulsar: invalid utf-8 at offset " + convert.int_to_string(start + i);
    }
  }
  return "";
}

// A validated Str from a data span, or the UTF-8 error.
fn _span_str(data: &Vec[UInt8], start: Int, size: Int) -> Result[Str, Str] {
  let e = _utf8_span_error(data, start, size);
  if e.len() > 0 {
    return _err_str(e);
  }
  return _ok_str(_span_to_str(data, start, size));
}

/// A validated Str from a raw byte vector (same rules as the field
/// decoders: strict UTF-8, no NUL). Complexity: O(bytes).
pub fn pulsar_bytes_to_str(v: &Vec[UInt8]) -> Result[Str, Str] {
  let e = _utf8_span_error(v, 0, v.len());
  if e.len() > 0 {
    return _err_str(e);
  }
  return _ok_str(_bytes_to_str(v));
}

/// A validated Str from the span [start, start+size) of `data`, exposed for
/// callers that keep metadata property bytes. Complexity: O(size).
pub fn pulsar_span_to_str(data: &Vec[UInt8], start: Int, size: Int) -> Result[Str, Str] {
  if start < 0 || size < 0 || start + size > data.len() {
    return _err_str("pulsar: bad message range at offset " + convert.int_to_string(start));
  }
  return _span_str(data, start, size);
}

// Deterministic depth-cap message.
fn _depth_msg(off: Int) -> Str {
  return "pulsar: nesting depth exceeds limit of 16 at offset " + convert.int_to_string(off);
}

// True when `depth` is within the nesting cap.
fn _depth_ok(depth: Int) -> Bool {
  return depth <= pulsar_max_depth();
}

// Note one unknown field: count it and preserve its tag+value bytes raw.
fn _cmd_unknown(cmd: &mut PulsarCommand, data: &Vec[UInt8], tag_start: Int, len: Int) {
  cmd.unknown_fields = cmd.unknown_fields + 1;
  var i = 0;
  while i < len {
    cmd.unknown_bytes.push(data[tag_start + i]);
    i = i + 1;
  }
}

// Set summary bit (v % 63) in a 63-bit bitset, idempotently.
fn _ack_bit_add(bits: Int, v: Int) -> Int {
  if v < 0 {
    return bits;
  }
  let e = v % 63;
  let p = _pow2(e);
  if (bits / p) % 2 == 1 {
    return bits;
  }
  return bits + p;
}

// True when the 63-bit summary has bit (v % 63) set.
fn _ack_bit_has(bits: Int, v: Int) -> Bool {
  if v < 0 {
    return false;
  }
  let p = _pow2(v % 63);
  return (bits / p) % 2 == 1;
}

// --------------------------------------------------
//  Wire primitives
// --------------------------------------------------

/// Encode a field key: field_number * 8 + wire_type. Complexity: O(1).
pub fn pulsar_key(field_number: Int, wire_type: Int) -> Int {
  return field_number * 8 + wire_type;
}

/// The field number encoded in a field key. Complexity: O(1).
pub fn pulsar_key_field_number(key: Int) -> Int {
  return key / 8;
}

/// The wire type encoded in a field key. Complexity: O(1).
pub fn pulsar_key_wire_type(key: Int) -> Int {
  return key % 8;
}

/// Decode a base-128 varint with unsigned u64 semantics, restricted to the
/// signed 64-bit Int range: at most 10 bytes; a continuation bit on the
/// 10th byte, 10th-byte data bits above bit 0, or bit 63 set are rejected.
///
/// Err("pulsar: varint out of bounds at offset P") when `pos` is not a
/// readable index; Err("pulsar: truncated varint at offset N") when the
/// buffer ends mid-varint (N = first missing byte); Err("pulsar: varint too
/// long at offset P"); Err("pulsar: varint overflows 64 bits at offset P");
/// Err("pulsar: varint exceeds signed 64-bit range at offset P").
/// Complexity: O(varint bytes).
pub fn pulsar_read_varint(data: &Vec[UInt8], pos: Int) -> Result[PulsarScalar, Str] {
  let n = data.len();
  if pos < 0 || pos >= n {
    return _err_scalar("pulsar: varint out of bounds at offset " + convert.int_to_string(pos));
  }
  var value = 0;
  var mult = 1;
  var i = 0;
  var p = pos;
  while i < 9 {
    if p >= n {
      return _err_scalar("pulsar: truncated varint at offset " + convert.int_to_string(n));
    }
    let b = _byte(data, p);
    value = value + (b % 128) * mult;
    if b < 128 {
      return _ok_scalar(PulsarScalar{ value: value; size: i + 1 });
    }
    i = i + 1;
    if i < 9 {
      mult = mult * 128;
    }
    p = p + 1;
  }
  if p >= n {
    return _err_scalar("pulsar: truncated varint at offset " + convert.int_to_string(n));
  }
  let b10 = _byte(data, p);
  if b10 >= 128 {
    return _err_scalar("pulsar: varint too long at offset " + convert.int_to_string(pos));
  }
  let bits = b10 % 128;
  if bits > 1 {
    return _err_scalar("pulsar: varint overflows 64 bits at offset " + convert.int_to_string(pos));
  }
  if bits == 1 {
    return _err_scalar("pulsar: varint exceeds signed 64-bit range at offset " + convert.int_to_string(pos));
  }
  return _ok_scalar(PulsarScalar{ value: value; size: 10 });
}

/// Decode a varint and reject values above 2^32 - 1 (u32 semantics).
/// Err("pulsar: varint exceeds u32 at offset P") for larger values; every
/// other error is the same as `pulsar_read_varint`.
/// Complexity: O(varint bytes).
pub fn pulsar_read_varint_u32(data: &Vec[UInt8], pos: Int) -> Result[PulsarScalar, Str] {
  let r = pulsar_read_varint(data, pos);
  if !r.is_ok {
    return _err_scalar(r.error);
  }
  let s: PulsarScalar = r.value;
  if s.value > 4294967295 {
    return _err_scalar("pulsar: varint exceeds u32 at offset " + convert.int_to_string(pos));
  }
  return _ok_scalar(s);
}

/// Decode a varint with signed int32 semantics: the low 32 bits are the
/// value, sign-extended (proto2 encodes negative int32 fields as 10-byte
/// sign-extended varints, which this reader accepts).
/// Complexity: O(varint bytes).
pub fn pulsar_read_varint_i32(data: &Vec[UInt8], pos: Int) -> Result[PulsarScalar, Str] {
  let n = data.len();
  if pos < 0 || pos >= n {
    return _err_scalar("pulsar: varint out of bounds at offset " + convert.int_to_string(pos));
  }
  var acc = 0;
  var mult = 1;
  var i = 0;
  var p = pos;
  while i < 10 {
    if p >= n {
      return _err_scalar("pulsar: truncated varint at offset " + convert.int_to_string(n));
    }
    let b = _byte(data, p);
    if i < 5 {
      acc = acc + (b % 128) * mult;
    }
    if b < 128 {
      let low = acc % 4294967296;
      var v = low;
      if low >= 2147483648 {
        v = low - 4294967296;
      }
      return _ok_scalar(PulsarScalar{ value: v; size: i + 1 });
    }
    if i < 4 {
      mult = mult * 128;
    }
    i = i + 1;
    p = p + 1;
  }
  return _err_scalar("pulsar: varint too long at offset " + convert.int_to_string(pos));
}

/// Decode a varint with the full signed int64 range: a 10-byte varint whose
/// 10th byte carries bit 63 yields a negative value (two's complement), so
/// sign-extended negative int64 fields decode exactly.
/// Complexity: O(varint bytes).
pub fn pulsar_read_varint_i64(data: &Vec[UInt8], pos: Int) -> Result[PulsarScalar, Str] {
  let n = data.len();
  if pos < 0 || pos >= n {
    return _err_scalar("pulsar: varint out of bounds at offset " + convert.int_to_string(pos));
  }
  var value = 0;
  var mult = 1;
  var i = 0;
  var p = pos;
  while i < 9 {
    if p >= n {
      return _err_scalar("pulsar: truncated varint at offset " + convert.int_to_string(n));
    }
    let b = _byte(data, p);
    value = value + (b % 128) * mult;
    if b < 128 {
      return _ok_scalar(PulsarScalar{ value: value; size: i + 1 });
    }
    i = i + 1;
    if i < 9 {
      mult = mult * 128;
    }
    p = p + 1;
  }
  if p >= n {
    return _err_scalar("pulsar: truncated varint at offset " + convert.int_to_string(n));
  }
  let b10 = _byte(data, p);
  if b10 >= 128 {
    return _err_scalar("pulsar: varint too long at offset " + convert.int_to_string(pos));
  }
  let bits = b10 % 128;
  if bits == 0 {
    return _ok_scalar(PulsarScalar{ value: value; size: 10 });
  }
  if bits == 1 {
    return _ok_scalar(PulsarScalar{ value: value + _min_i64(); size: 10 });
  }
  return _err_scalar("pulsar: varint overflows 64 bits at offset " + convert.int_to_string(pos));
}

/// Decode a little-endian fixed32 (wire type 5).
/// Err("pulsar: truncated fixed32 at offset N") when 4 bytes are not
/// available (N = first missing byte). Complexity: O(1).
pub fn pulsar_read_fixed32(data: &Vec[UInt8], pos: Int) -> Result[PulsarScalar, Str] {
  let n = data.len();
  if pos < 0 || pos + 4 > n {
    return _err_scalar("pulsar: truncated fixed32 at offset " + convert.int_to_string(n));
  }
  let v = _byte(data, pos) + _byte(data, pos + 1) * 256 + _byte(data, pos + 2) * 65536 + _byte(data, pos + 3) * 16777216;
  return _ok_scalar(PulsarScalar{ value: v; size: 4 });
}

/// Decode a little-endian fixed64 (wire type 1) into the signed Int range.
/// Err("pulsar: truncated fixed64 at offset N") when 8 bytes are not
/// available; Err("pulsar: fixed64 exceeds signed 64-bit range at offset P")
/// when bit 63 is set. Complexity: O(1).
pub fn pulsar_read_fixed64(data: &Vec[UInt8], pos: Int) -> Result[PulsarScalar, Str] {
  let n = data.len();
  if pos < 0 || pos + 8 > n {
    return _err_scalar("pulsar: truncated fixed64 at offset " + convert.int_to_string(n));
  }
  let hi = _byte(data, pos + 4) + _byte(data, pos + 5) * 256 + _byte(data, pos + 6) * 65536 + _byte(data, pos + 7) * 16777216;
  if hi >= 2147483648 {
    return _err_scalar("pulsar: fixed64 exceeds signed 64-bit range at offset " + convert.int_to_string(pos));
  }
  let lo = _byte(data, pos) + _byte(data, pos + 1) * 256 + _byte(data, pos + 2) * 65536 + _byte(data, pos + 3) * 16777216;
  return _ok_scalar(PulsarScalar{ value: hi * 4294967296 + lo; size: 8 });
}

/// Read a length-delimited value (wire type 2): a u32 varint length at
/// `pos` followed by that many payload bytes.
/// Err("pulsar: truncated length-delimited field at offset N") when the
/// prefix or the payload does not fit (N = first missing byte);
/// Err("pulsar: truncated varint at offset N") for a clipped length prefix;
/// Err("pulsar: varint exceeds u32 at offset P") for a length above 2^32 - 1.
/// Complexity: O(1).
pub fn pulsar_read_delimited(data: &Vec[UInt8], pos: Int) -> Result[PulsarDelimited, Str] {
  let lr = pulsar_read_varint_u32(data, pos);
  if !lr.is_ok {
    return _err_delim(lr.error);
  }
  let ls: PulsarScalar = lr.value;
  let start = pos + ls.size;
  let n = data.len();
  if start + ls.value > n {
    return _err_delim("pulsar: truncated length-delimited field at offset " + convert.int_to_string(n));
  }
  return _ok_delim(PulsarDelimited{ start: start; size: ls.value; total: ls.size + ls.value });
}

/// Skip one field value of wire type 0/1/2/5 and return the new position
/// plus the bytes consumed.
/// Err("pulsar: unsupported wire type W at offset P") for group/other wire
/// types; truncation errors as in the matching reader.
/// Complexity: O(value bytes).
pub fn pulsar_skip_field(data: &Vec[UInt8], pos: Int, wire_type: Int) -> Result[PulsarAdvance, Str] {
  if wire_type == 0 {
    let r = pulsar_read_varint(data, pos);
    if !r.is_ok {
      return _err_advance(r.error);
    }
    let s: PulsarScalar = r.value;
    return _ok_advance(PulsarAdvance{ pos: pos + s.size; size: s.size });
  }
  if wire_type == 1 {
    let n = data.len();
    if pos < 0 || pos + 8 > n {
      return _err_advance("pulsar: truncated fixed64 at offset " + convert.int_to_string(n));
    }
    return _ok_advance(PulsarAdvance{ pos: pos + 8; size: 8 });
  }
  if wire_type == 2 {
    let r = pulsar_read_delimited(data, pos);
    if !r.is_ok {
      return _err_advance(r.error);
    }
    let d: PulsarDelimited = r.value;
    return _ok_advance(PulsarAdvance{ pos: pos + d.total; size: d.total });
  }
  if wire_type == 5 {
    let n = data.len();
    if pos < 0 || pos + 4 > n {
      return _err_advance("pulsar: truncated fixed32 at offset " + convert.int_to_string(n));
    }
    return _ok_advance(PulsarAdvance{ pos: pos + 4; size: 4 });
  }
  return _err_advance("pulsar: unsupported wire type " + convert.int_to_string(wire_type) + " at offset " + convert.int_to_string(pos));
}

/// Decode a packed repeated varint run occupying [start, end) and append
/// every value to `out`; returns the number of values decoded.
/// Err("pulsar: packed run crosses boundary at offset P") when a varint
/// crosses `end`; Err("pulsar: packed run too large at offset S") above
/// pulsar_max_packed_entries(); varint errors as in `pulsar_read_varint`.
/// Complexity: O(run bytes).
pub fn pulsar_read_packed_varints(data: &Vec[UInt8], start: Int, end: Int, out: &mut Vec[Int]) -> Result[Int, Str] {
  var pos = start;
  var count = 0;
  while pos < end {
    if count >= pulsar_max_packed_entries() {
      return _err_int("pulsar: packed run too large at offset " + convert.int_to_string(start));
    }
    let r = pulsar_read_varint(data, pos);
    if !r.is_ok {
      return _err_int(r.error);
    }
    let s: PulsarScalar = r.value;
    if pos + s.size > end {
      return _err_int("pulsar: packed run crosses boundary at offset " + convert.int_to_string(pos));
    }
    out.push(s.value);
    pos = pos + s.size;
    count = count + 1;
  }
  return _ok_int(count);
}

// Decode one field value (without the key) at `pos`.
fn _field_value(data: &Vec[UInt8], pos: Int, wire_type: Int) -> Result[PulsarFieldValue, Str] {
  if wire_type == 0 {
    let r = pulsar_read_varint_i64(data, pos);
    if !r.is_ok {
      return _err_fv(r.error);
    }
    let s: PulsarScalar = r.value;
    return _ok_fv(PulsarFieldValue{ wire_type: 0; int_value: s.value; start: 0; size: 0; total: s.size });
  }
  if wire_type == 1 {
    let r = pulsar_read_fixed64(data, pos);
    if !r.is_ok {
      return _err_fv(r.error);
    }
    let s: PulsarScalar = r.value;
    return _ok_fv(PulsarFieldValue{ wire_type: 1; int_value: s.value; start: 0; size: 0; total: 8 });
  }
  if wire_type == 2 {
    let r = pulsar_read_delimited(data, pos);
    if !r.is_ok {
      return _err_fv(r.error);
    }
    let d: PulsarDelimited = r.value;
    return _ok_fv(PulsarFieldValue{ wire_type: 2; int_value: 0; start: d.start; size: d.size; total: d.total });
  }
  if wire_type == 5 {
    let r = pulsar_read_fixed32(data, pos);
    if !r.is_ok {
      return _err_fv(r.error);
    }
    let s: PulsarScalar = r.value;
    return _ok_fv(PulsarFieldValue{ wire_type: 5; int_value: s.value; start: 0; size: 0; total: 4 });
  }
  return _err_fv("pulsar: unsupported wire type " + convert.int_to_string(wire_type) + " at offset " + convert.int_to_string(pos));
}

// Read one whole field (key + value) that must fit inside [pos, end).
fn _field_step(data: &Vec[UInt8], pos: Int, end: Int) -> Result[PulsarFieldStep, Str] {
  let kr = pulsar_read_varint_u32(data, pos);
  if !kr.is_ok {
    return _err_step(kr.error);
  }
  let ks: PulsarScalar = kr.value;
  let fnum = ks.value / 8;
  let wt = ks.value % 8;
  if fnum < 1 {
    return _err_step("pulsar: field number 0 at offset " + convert.int_to_string(pos));
  }
  let vpos = pos + ks.size;
  if vpos > end {
    return _err_step("pulsar: truncated field at offset " + convert.int_to_string(end));
  }
  let vr = _field_value(data, vpos, wt);
  if !vr.is_ok {
    return _err_step(vr.error);
  }
  let fv: PulsarFieldValue = vr.value;
  if vpos + fv.total > end {
    return _err_step("pulsar: field crosses message boundary at offset " + convert.int_to_string(vpos));
  }
  return _ok_step(PulsarFieldStep{ field_number: fnum; wire_type: wt; tag_start: pos; key_size: ks.size; value: fv; next: vpos + fv.total });
}

// --------------------------------------------------
//  MessageIdData
// --------------------------------------------------

/// A fresh MessageIdData with Pulsar's defaults (partition -1, batch -1).
/// Complexity: O(1).
pub fn pulsar_message_id_new() -> PulsarMessageId {
  return PulsarMessageId{
    ledger_id: 0; entry_id: 0; partition: -1; batch_index: -1;
    ack_set: Vec[Int].new(); ack_set_bits: 0;
  };
}

// Append one id to a flat list, mirroring every parallel vector.
fn _mid_list_push(list: &mut PulsarMessageIdList, m: &PulsarMessageId) {
  list.ledger_ids.push(m.ledger_id);
  list.entry_ids.push(m.entry_id);
  list.partitions.push(m.partition);
  list.batch_indexes.push(m.batch_index);
  list.ack_bits.push(m.ack_set_bits);
}

/// Number of ids in a flat list. Complexity: O(1).
pub fn pulsar_mid_list_len(list: &PulsarMessageIdList) -> Int {
  return list.ledger_ids.len();
}

/// `ledger_id` of list entry `i` (0 when out of range).
pub fn pulsar_mid_list_ledger(list: &PulsarMessageIdList, i: Int) -> Int {
  if i < 0 || i >= list.ledger_ids.len() {
    return 0;
  }
  return list.ledger_ids[i];
}

/// `entry_id` of list entry `i` (0 when out of range).
pub fn pulsar_mid_list_entry(list: &PulsarMessageIdList, i: Int) -> Int {
  if i < 0 || i >= list.entry_ids.len() {
    return 0;
  }
  return list.entry_ids[i];
}

/// `partition` of list entry `i` (-1 when out of range).
pub fn pulsar_mid_list_partition(list: &PulsarMessageIdList, i: Int) -> Int {
  if i < 0 || i >= list.partitions.len() {
    return -1;
  }
  return list.partitions[i];
}

/// `batch_index` of list entry `i` (-1 when out of range).
pub fn pulsar_mid_list_batch_index(list: &PulsarMessageIdList, i: Int) -> Int {
  if i < 0 || i >= list.batch_indexes.len() {
    return -1;
  }
  return list.batch_indexes[i];
}

/// `ack_set_bits` summary of list entry `i` (0 when out of range).
pub fn pulsar_mid_list_ack_bits(list: &PulsarMessageIdList, i: Int) -> Int {
  if i < 0 || i >= list.ack_bits.len() {
    return 0;
  }
  return list.ack_bits[i];
}

/// Number of decoded ack_set entries on one id. Complexity: O(1).
pub fn pulsar_message_id_ack_count(m: &PulsarMessageId) -> Int {
  return m.ack_set.len();
}

/// ack_set entry `i` (0 when out of range). Complexity: O(1).
pub fn pulsar_message_id_ack_at(m: &PulsarMessageId, i: Int) -> Int {
  if i < 0 || i >= m.ack_set.len() {
    return 0;
  }
  return m.ack_set[i];
}

/// True when the ack_set summary has bit (v % 63) set. Complexity: O(1).
pub fn pulsar_message_id_ack_has(m: &PulsarMessageId, v: Int) -> Bool {
  return _ack_bit_has(m.ack_set_bits, v);
}

/// Decode a MessageIdData body occupying [start, end) at nesting `depth`.
///
/// Fields decoded: 1 ledgerId, 2 entryId, 3 partition, 4 batch_index and
/// 5 ack_set (unpacked varints or one packed run); every other field is
/// skipped with bounds checks (the enclosing command keeps raw bytes).
///
/// Err("pulsar: nesting depth exceeds limit of 16 at offset P");
/// Err("pulsar: bad message range at offset P");
/// Err("pulsar: ack_set too large at offset P") beyond
/// pulsar_max_ack_set_entries(); plus the field/varint errors.
/// Complexity: O(body bytes).
pub fn pulsar_parse_message_id_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[PulsarMessageId, Str] {
  if !_depth_ok(depth) {
    return _err_mid(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_mid("pulsar: bad message range at offset " + convert.int_to_string(start));
  }
  var mid = pulsar_message_id_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_mid(sr.error);
    }
    let st: PulsarFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: PulsarFieldValue = st.value;
    if fnum == 1 && wt == 0 {
      mid.ledger_id = fv.int_value;
    } elif fnum == 2 && wt == 0 {
      mid.entry_id = fv.int_value;
    } elif fnum == 3 && wt == 0 {
      mid.partition = fv.int_value;
    } elif fnum == 4 && wt == 0 {
      mid.batch_index = fv.int_value;
    } elif fnum == 5 && wt == 0 {
      if mid.ack_set.len() >= pulsar_max_ack_set_entries() {
        return _err_mid("pulsar: ack_set too large at offset " + convert.int_to_string(pos));
      }
      mid.ack_set.push(fv.int_value);
      mid.ack_set_bits = _ack_bit_add(mid.ack_set_bits, fv.int_value);
    } elif fnum == 5 && wt == 2 {
      var vals = Vec[Int].new();
      let pr = pulsar_read_packed_varints(data, fv.start, fv.start + fv.size, &mut vals);
      if !pr.is_ok {
        return _err_mid(pr.error);
      }
      if mid.ack_set.len() + vals.len() > pulsar_max_ack_set_entries() {
        return _err_mid("pulsar: ack_set too large at offset " + convert.int_to_string(pos));
      }
      var i = 0;
      while i < vals.len() {
        let v: Int = vals[i];
        mid.ack_set.push(v);
        mid.ack_set_bits = _ack_bit_add(mid.ack_set_bits, v);
        i = i + 1;
      }
    }
    pos = st.next;
  }
  return _ok_mid(mid);
}

/// Decode one length-delimited MessageIdData field at `pos` (its key is
/// consumed) and report the offset after it.
/// Errors: as `pulsar_parse_message_id_body` plus
/// Err("pulsar: expected length-delimited at offset P") when the field is
/// not wire type 2. Complexity: O(field bytes).
pub fn pulsar_parse_message_id_at(data: &Vec[UInt8], pos: Int, depth: Int) -> Result[PulsarMidRead, Str] {
  let sr = _field_step(data, pos, data.len());
  if !sr.is_ok {
    return _err_midread(sr.error);
  }
  let st: PulsarFieldStep = sr.value;
  if st.wire_type != 2 {
    return _err_midread("pulsar: expected length-delimited at offset " + convert.int_to_string(pos));
  }
  let fv: PulsarFieldValue = st.value;
  let mr = pulsar_parse_message_id_body(data, fv.start, fv.start + fv.size, depth);
  if !mr.is_ok {
    return _err_midread(mr.error);
  }
  let m: PulsarMessageId = mr.value;
  return _ok_midread(PulsarMidRead{ id: m; pos: st.next });
}

// --------------------------------------------------
//  MessageMetadata
// --------------------------------------------------

/// A fresh MessageMetadata with proto2 defaults (all optional fields unset,
/// compression NONE).
/// Complexity: O(1).
pub fn pulsar_metadata_new() -> PulsarMessageMetadata {
  return PulsarMessageMetadata{
    producer_name: ""; sequence_id: 0; publish_time: 0; partition_key: "";
    event_time: 0; deliver_at_time: 0; compression: 0; uncompressed_size: 0;
    property_keys: Vec[Vec[UInt8]].new(); property_values: Vec[Vec[UInt8]].new();
    has_producer_name: false; has_sequence_id: false; has_publish_time: false;
    has_partition_key: false; has_event_time: false; has_deliver_at_time: false;
    has_compression: false; has_uncompressed_size: false; unknown_fields: 0;
  };
}

/// Append one property pair, mirroring both vectors (they never drift).
/// Complexity: O(bytes).
pub fn pulsar_metadata_add_property(m: &mut PulsarMessageMetadata, key: &Vec[UInt8], value: &Vec[UInt8]) {
  m.property_keys.push(_vec_copy(key));
  m.property_values.push(_vec_copy(value));
}

/// Append one property pair from Str values. Complexity: O(bytes).
pub fn pulsar_metadata_add_property_str(m: &mut PulsarMessageMetadata, key: Str, value: Str) {
  let kb = _str_to_bytes(key);
  let vb = _str_to_bytes(value);
  pulsar_metadata_add_property(m, &kb, &vb);
}

/// Number of decoded properties. Complexity: O(1).
pub fn pulsar_metadata_property_count(m: &PulsarMessageMetadata) -> Int {
  return m.property_keys.len();
}

/// Property key `i` as raw bytes (empty when out of range).
pub fn pulsar_metadata_property_key(m: &PulsarMessageMetadata, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= m.property_keys.len() {
    return Vec[UInt8].new();
  }
  let k: Vec[UInt8] = m.property_keys[i];
  return _vec_copy(&k);
}

/// Property value `i` as raw bytes (empty when out of range).
pub fn pulsar_metadata_property_value(m: &PulsarMessageMetadata, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= m.property_values.len() {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = m.property_values[i];
  return _vec_copy(&v);
}

// Parse one nested KeyValue body and append the pair to `m`.
fn _meta_parse_keyvalue(m: &mut PulsarMessageMetadata, data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[Unit, Str] {
  if !_depth_ok(depth) {
    return _err_unit(_depth_msg(start));
  }
  var kb = Vec[UInt8].new();
  var vb = Vec[UInt8].new();
  var seen_key = false;
  var seen_value = false;
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_unit(sr.error);
    }
    let st: PulsarFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: PulsarFieldValue = st.value;
    if fnum == 1 && wt == 2 {
      let e = _utf8_span_error(data, fv.start, fv.size);
      if e.len() > 0 {
        return _err_unit(e);
      }
      kb = _slice(data, fv.start, fv.size);
      seen_key = true;
    } elif fnum == 2 && wt == 2 {
      let e = _utf8_span_error(data, fv.start, fv.size);
      if e.len() > 0 {
        return _err_unit(e);
      }
      vb = _slice(data, fv.start, fv.size);
      seen_value = true;
    }
    pos = st.next;
  }
  if !seen_key || !seen_value {
    return _err_unit("pulsar: incomplete key-value pair at offset " + convert.int_to_string(start));
  }
  pulsar_metadata_add_property(m, &kb, &vb);
  return _ok_unit();
}

/// Decode a MessageMetadata body occupying [start, end) at nesting `depth`.
///
/// Fields decoded: 1 producer_name, 2 sequence_id, 3 publish_time,
/// 4 properties (repeated KeyValue with string key/value), 6 partition_key,
/// 8 compression, 9 uncompressed_size, 12 event_time, 19 deliver_at_time.
/// Every other field is counted in `unknown_fields` and skipped with bounds
/// checks (the enclosing frame keeps the raw bytes).
///
/// Err("pulsar: nesting depth exceeds limit of 16 at offset P");
/// Err("pulsar: bad message range at offset P"); plus the field/varint and
/// UTF-8 errors. Complexity: O(body bytes).
pub fn pulsar_parse_metadata_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[PulsarMessageMetadata, Str] {
  if !_depth_ok(depth) {
    return _err_meta(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_meta("pulsar: bad message range at offset " + convert.int_to_string(start));
  }
  var meta = pulsar_metadata_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_meta(sr.error);
    }
    let st: PulsarFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: PulsarFieldValue = st.value;
    var handled = false;
    if fnum == 1 && wt == 2 {
      let sr2 = _span_str(data, fv.start, fv.size);
      if !sr2.is_ok {
        return _err_meta(sr2.error);
      }
      let s: Str = sr2.value;
      meta.producer_name = s;
      meta.has_producer_name = true;
      handled = true;
    } elif fnum == 2 && wt == 0 {
      meta.sequence_id = fv.int_value;
      meta.has_sequence_id = true;
      handled = true;
    } elif fnum == 3 && wt == 0 {
      meta.publish_time = fv.int_value;
      meta.has_publish_time = true;
      handled = true;
    } elif fnum == 4 && wt == 2 {
      let kr = _meta_parse_keyvalue(&mut meta, data, fv.start, fv.start + fv.size, depth + 1);
      if !kr.is_ok {
        return _err_meta(kr.error);
      }
      handled = true;
    } elif fnum == 6 && wt == 2 {
      let sr2 = _span_str(data, fv.start, fv.size);
      if !sr2.is_ok {
        return _err_meta(sr2.error);
      }
      let s: Str = sr2.value;
      meta.partition_key = s;
      meta.has_partition_key = true;
      handled = true;
    } elif fnum == 8 && wt == 0 {
      meta.compression = fv.int_value;
      meta.has_compression = true;
      handled = true;
    } elif fnum == 9 && wt == 0 {
      meta.uncompressed_size = fv.int_value;
      meta.has_uncompressed_size = true;
      handled = true;
    } elif fnum == 12 && wt == 0 {
      meta.event_time = fv.int_value;
      meta.has_event_time = true;
      handled = true;
    } elif fnum == 19 && wt == 0 {
      meta.deliver_at_time = fv.int_value;
      meta.has_deliver_at_time = true;
      handled = true;
    }
    if !handled {
      meta.unknown_fields = meta.unknown_fields + 1;
    }
    pos = st.next;
  }
  return _ok_meta(meta);
}

/// Decode one length-delimited MessageMetadata field at `pos` (its key is
/// consumed) and report the offset after it.
/// Err("pulsar: expected length-delimited at offset P") when the field is
/// not wire type 2; otherwise as `pulsar_parse_metadata_body`.
/// Complexity: O(field bytes).
pub fn pulsar_parse_metadata_at(data: &Vec[UInt8], pos: Int, depth: Int) -> Result[PulsarMetaRead, Str] {
  let sr = _field_step(data, pos, data.len());
  if !sr.is_ok {
    return _err_metaread(sr.error);
  }
  let st: PulsarFieldStep = sr.value;
  if st.wire_type != 2 {
    return _err_metaread("pulsar: expected length-delimited at offset " + convert.int_to_string(pos));
  }
  let fv: PulsarFieldValue = st.value;
  let mr = pulsar_parse_metadata_body(data, fv.start, fv.start + fv.size, depth);
  if !mr.is_ok {
    return _err_metaread(mr.error);
  }
  let m: PulsarMessageMetadata = mr.value;
  return _ok_metaread(PulsarMetaRead{ metadata: m; pos: st.next });
}

// --------------------------------------------------
//  BaseCommand body decoders
// --------------------------------------------------

// Find the BaseCommand.type field (1, varint); Ok(-1) when absent.
fn _scan_cmd_type(data: &Vec[UInt8], start: Int, end: Int) -> Result[Int, Str] {
  var t = -1;
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_int(sr.error);
    }
    let st: PulsarFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: PulsarFieldValue = st.value;
    if fnum == 1 && wt == 0 {
      t = fv.int_value;
    }
    pos = st.next;
  }
  return _ok_int(t);
}

// A fresh command with every decoded field at its proto2 default.
fn _empty_command(t: Int) -> PulsarCommand {
  return PulsarCommand{
    cmd_type: t; known: false; has_body: false; field_count: 0; unknown_fields: 0;
    raw: Vec[UInt8].new(); unknown_bytes: Vec[UInt8].new();
    client_version: ""; auth_method_name: ""; protocol_version: 0; has_protocol_version: false;
    server_version: ""; max_message_size: 0; has_max_message_size: false;
    topic: ""; subscription: ""; sub_type: 0; consumer_id: 0; producer_id: 0; request_id: 0;
    durable: false; has_durable: false;
    producer_name: ""; sequence_id: 0; num_messages: 1; has_num_messages: false;
    publish_time: 0; redelivery_count: 0; message_id: pulsar_message_id_new(); has_message_id: false;
    msg_ack_set: Vec[Int].new(); msg_ack_bits: 0;
    ack_type: 0;
    ack_ids: PulsarMessageIdList{
      ledger_ids: Vec[Int].new(); entry_ids: Vec[Int].new(); partitions: Vec[Int].new();
      batch_indexes: Vec[Int].new(); ack_bits: Vec[Int].new();
    };
    message_permits: 0; has_message_permits: false;
    error_code: 0; has_error_code: false; error_message: ""; has_error_message: false;
    last_sequence_id: -1; has_last_sequence_id: false;
    partitions: 0; has_partitions: false; partition_names: Vec[Vec[UInt8]].new();
    response_code: 0; has_response_code: false;
    broker_url: ""; broker_url_tls: ""; namespace: "";
  };
}

// Read a string field into a Str (validated UTF-8, no NUL).
fn _field_str(data: &Vec[UInt8], fv: PulsarFieldValue) -> Result[Str, Str] {
  return _span_str(data, fv.start, fv.size);
}

// Assign the fields decoded for CONNECT commands (type 2).
fn _assign_connect(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.client_version = s;
    return _ok_bool(true);
  }
  if fnum == 5 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.auth_method_name = s;
    return _ok_bool(true);
  }
  if fnum == 4 && wt == 0 {
    cmd.protocol_version = fv.int_value;
    cmd.has_protocol_version = true;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for CONNECTED commands (type 3).
fn _assign_connected(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.server_version = s;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.protocol_version = fv.int_value;
    cmd.has_protocol_version = true;
    return _ok_bool(true);
  }
  if fnum == 3 && wt == 0 {
    cmd.max_message_size = fv.int_value;
    cmd.has_max_message_size = true;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for SUBSCRIBE commands (type 4).
fn _assign_subscribe(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.topic = s;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.subscription = s;
    return _ok_bool(true);
  }
  if fnum == 3 && wt == 0 {
    cmd.sub_type = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 4 && wt == 0 {
    cmd.consumer_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 5 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 8 && wt == 0 {
    if fv.int_value != 0 {
      cmd.durable = true;
    } else {
      cmd.durable = false;
    }
    cmd.has_durable = true;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for PRODUCER commands (type 5).
fn _assign_producer(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.topic = s;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.producer_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 3 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 4 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.producer_name = s;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for SEND commands (type 6).
fn _assign_send(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue, depth: Int) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.producer_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.sequence_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 3 && wt == 0 {
    cmd.num_messages = fv.int_value;
    cmd.has_num_messages = true;
    return _ok_bool(true);
  }
  if fnum == 9 && wt == 2 {
    let mr = pulsar_parse_message_id_body(data, fv.start, fv.start + fv.size, depth + 1);
    if !mr.is_ok {
      return _err_bool(mr.error);
    }
    let m: PulsarMessageId = mr.value;
    cmd.message_id = m;
    cmd.has_message_id = true;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for SEND_RECEIPT commands (type 7).
fn _assign_send_receipt(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue, depth: Int) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.producer_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.sequence_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 3 && wt == 2 {
    let mr = pulsar_parse_message_id_body(data, fv.start, fv.start + fv.size, depth + 1);
    if !mr.is_ok {
      return _err_bool(mr.error);
    }
    let m: PulsarMessageId = mr.value;
    cmd.message_id = m;
    cmd.has_message_id = true;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for SEND_ERROR commands (type 8).
fn _assign_send_error(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.producer_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.sequence_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 3 && wt == 0 {
    cmd.error_code = fv.int_value;
    cmd.has_error_code = true;
    return _ok_bool(true);
  }
  if fnum == 4 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.error_message = s;
    cmd.has_error_message = true;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for MESSAGE commands (type 9).
fn _assign_message(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue, depth: Int) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.consumer_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 2 {
    let mr = pulsar_parse_message_id_body(data, fv.start, fv.start + fv.size, depth + 1);
    if !mr.is_ok {
      return _err_bool(mr.error);
    }
    let m: PulsarMessageId = mr.value;
    cmd.message_id = m;
    cmd.has_message_id = true;
    return _ok_bool(true);
  }
  if fnum == 3 && wt == 0 {
    cmd.redelivery_count = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 4 && wt == 0 {
    if cmd.msg_ack_set.len() >= pulsar_max_ack_set_entries() {
      return _err_bool("pulsar: ack_set too large at offset " + convert.int_to_string(fv.start));
    }
    cmd.msg_ack_set.push(fv.int_value);
    cmd.msg_ack_bits = _ack_bit_add(cmd.msg_ack_bits, fv.int_value);
    return _ok_bool(true);
  }
  if fnum == 4 && wt == 2 {
    var vals = Vec[Int].new();
    let pr = pulsar_read_packed_varints(data, fv.start, fv.start + fv.size, &mut vals);
    if !pr.is_ok {
      return _err_bool(pr.error);
    }
    if cmd.msg_ack_set.len() + vals.len() > pulsar_max_ack_set_entries() {
      return _err_bool("pulsar: ack_set too large at offset " + convert.int_to_string(fv.start));
    }
    var i = 0;
    while i < vals.len() {
      let v: Int = vals[i];
      cmd.msg_ack_set.push(v);
      cmd.msg_ack_bits = _ack_bit_add(cmd.msg_ack_bits, v);
      i = i + 1;
    }
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for ACK commands (type 10).
fn _assign_ack(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue, depth: Int) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.consumer_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.ack_type = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 3 && wt == 2 {
    let mr = pulsar_parse_message_id_body(data, fv.start, fv.start + fv.size, depth + 1);
    if !mr.is_ok {
      return _err_bool(mr.error);
    }
    let m: PulsarMessageId = mr.value;
    _mid_list_push(&mut cmd.ack_ids, &m);
    return _ok_bool(true);
  }
  if fnum == 8 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for FLOW commands (type 11).
fn _assign_flow(cmd: &mut PulsarCommand, fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.consumer_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.message_permits = fv.int_value;
    cmd.has_message_permits = true;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for UNSUBSCRIBE commands (type 12).
fn _assign_unsubscribe(cmd: &mut PulsarCommand, fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.consumer_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for SUCCESS commands (type 13).
fn _assign_success(cmd: &mut PulsarCommand, fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for ERROR commands (type 14).
fn _assign_error(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.error_code = fv.int_value;
    cmd.has_error_code = true;
    return _ok_bool(true);
  }
  if fnum == 3 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.error_message = s;
    cmd.has_error_message = true;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for CLOSE_PRODUCER commands (type 15).
fn _assign_close_producer(cmd: &mut PulsarCommand, fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.producer_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for CLOSE_CONSUMER commands (type 16).
fn _assign_close_consumer(cmd: &mut PulsarCommand, fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.consumer_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for PRODUCER_SUCCESS commands (type 17).
fn _assign_producer_success(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.producer_name = s;
    return _ok_bool(true);
  }
  if fnum == 3 && wt == 0 {
    cmd.last_sequence_id = fv.int_value;
    cmd.has_last_sequence_id = true;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for REDELIVER_UNACKNOWLEDGED_MESSAGES (type 20).
fn _assign_redeliver(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue, depth: Int) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.consumer_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 2 {
    let mr = pulsar_parse_message_id_body(data, fv.start, fv.start + fv.size, depth + 1);
    if !mr.is_ok {
      return _err_bool(mr.error);
    }
    let m: PulsarMessageId = mr.value;
    _mid_list_push(&mut cmd.ack_ids, &m);
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for PARTITIONED_METADATA (type 21).
fn _assign_partitioned_meta(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.topic = s;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for PARTITIONED_METADATA_RESPONSE (type 22).
// Field 1 is a partition count as a varint, or -- in the older/other
// binding this package accepts -- repeated partition-name strings; both
// wire forms are decoded.
fn _assign_partitioned_meta_response(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.partitions = fv.int_value;
    cmd.has_partitions = true;
    return _ok_bool(true);
  }
  if fnum == 1 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    let b = _str_to_bytes(s);
    cmd.partition_names.push(b);
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 3 && wt == 0 {
    cmd.response_code = fv.int_value;
    cmd.has_response_code = true;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for LOOKUP commands (type 23).
fn _assign_lookup(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.topic = s;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for LOOKUP_RESPONSE commands (type 24).
fn _assign_lookup_response(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.broker_url = s;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.broker_url_tls = s;
    return _ok_bool(true);
  }
  if fnum == 3 && wt == 0 {
    cmd.response_code = fv.int_value;
    cmd.has_response_code = true;
    return _ok_bool(true);
  }
  if fnum == 4 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for GET_LAST_MESSAGE_ID commands (type 29).
fn _assign_get_last(cmd: &mut PulsarCommand, fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.consumer_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Assign the fields decoded for GET_TOPICS_OF_NAMESPACE commands (type 32).
fn _assign_get_topics(cmd: &mut PulsarCommand, data: &Vec[UInt8], fnum: Int, wt: Int, fv: PulsarFieldValue) -> Result[Bool, Str] {
  if fnum == 1 && wt == 0 {
    cmd.request_id = fv.int_value;
    return _ok_bool(true);
  }
  if fnum == 2 && wt == 2 {
    let sr = _field_str(data, fv);
    if !sr.is_ok {
      return _err_bool(sr.error);
    }
    let s: Str = sr.value;
    cmd.namespace = s;
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// Dispatch one body field to the decoder for the command type.
fn _assign_body_field(cmd: &mut PulsarCommand, data: &Vec[UInt8], st: &PulsarFieldStep, depth: Int) -> Result[Bool, Str] {
  let t = cmd.cmd_type;
  let fnum = st.field_number;
  let wt = st.wire_type;
  let fv: PulsarFieldValue = st.value;
  if t == 2 {
    return _assign_connect(cmd, data, fnum, wt, fv);
  }
  if t == 3 {
    return _assign_connected(cmd, data, fnum, wt, fv);
  }
  if t == 4 {
    return _assign_subscribe(cmd, data, fnum, wt, fv);
  }
  if t == 5 {
    return _assign_producer(cmd, data, fnum, wt, fv);
  }
  if t == 6 {
    return _assign_send(cmd, data, fnum, wt, fv, depth);
  }
  if t == 7 {
    return _assign_send_receipt(cmd, data, fnum, wt, fv, depth);
  }
  if t == 8 {
    return _assign_send_error(cmd, data, fnum, wt, fv);
  }
  if t == 9 {
    return _assign_message(cmd, data, fnum, wt, fv, depth);
  }
  if t == 10 {
    return _assign_ack(cmd, data, fnum, wt, fv, depth);
  }
  if t == 11 {
    return _assign_flow(cmd, fnum, wt, fv);
  }
  if t == 12 {
    return _assign_unsubscribe(cmd, fnum, wt, fv);
  }
  if t == 13 {
    return _assign_success(cmd, fnum, wt, fv);
  }
  if t == 14 {
    return _assign_error(cmd, data, fnum, wt, fv);
  }
  if t == 15 {
    return _assign_close_producer(cmd, fnum, wt, fv);
  }
  if t == 16 {
    return _assign_close_consumer(cmd, fnum, wt, fv);
  }
  if t == 17 {
    return _assign_producer_success(cmd, data, fnum, wt, fv);
  }
  if t == 20 {
    return _assign_redeliver(cmd, data, fnum, wt, fv, depth);
  }
  if t == 21 {
    return _assign_partitioned_meta(cmd, data, fnum, wt, fv);
  }
  if t == 22 {
    return _assign_partitioned_meta_response(cmd, data, fnum, wt, fv);
  }
  if t == 23 {
    return _assign_lookup(cmd, data, fnum, wt, fv);
  }
  if t == 24 {
    return _assign_lookup_response(cmd, data, fnum, wt, fv);
  }
  if t == 29 {
    return _assign_get_last(cmd, fnum, wt, fv);
  }
  if t == 32 {
    return _assign_get_topics(cmd, data, fnum, wt, fv);
  }
  return _ok_bool(false);
}

// Walk the body of a known command, preserving unknown fields raw.
fn _walk_body(cmd: &mut PulsarCommand, data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[Unit, Str] {
  if !_depth_ok(depth) {
    return _err_unit(_depth_msg(start));
  }
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_unit(sr.error);
    }
    let st: PulsarFieldStep = sr.value;
    let fv: PulsarFieldValue = st.value;
    let ar = _assign_body_field(cmd, data, &st, depth);
    if !ar.is_ok {
      return _err_unit(ar.error);
    }
    let handled: Bool = ar.value;
    if !handled {
      _cmd_unknown(cmd, data, st.tag_start, st.key_size + fv.total);
    }
    cmd.field_count = cmd.field_count + 1;
    pos = st.next;
  }
  return _ok_unit();
}

/// Decode a complete BaseCommand protobuf message.
///
/// The type field is scanned first (field 1, varint); for a known type the
/// body field (`field_number == type`, wire type 2) is then decoded with the
/// type-specific assignments, unknown fields are counted and preserved raw
/// in `unknown_bytes`, and the whole command is copied into `raw`. A known
/// type without its body fails; unknown types decode successfully with
/// `known = false` and every field preserved.
///
/// Err("pulsar: empty base command"); Err("pulsar: missing command type at
/// offset N"); Err("pulsar: missing command body at offset N");
/// Err("pulsar: duplicate command body at offset P"); plus the field and
/// body decoder errors (which carry byte offsets).
/// Complexity: O(command bytes).
pub fn pulsar_decode_base_command(data: &Vec[UInt8]) -> Result[PulsarCommand, Str] {
  let n = data.len();
  if n == 0 {
    return _err_cmd("pulsar: empty base command");
  }
  let tr = _scan_cmd_type(data, 0, n);
  if !tr.is_ok {
    return _err_cmd(tr.error);
  }
  let t: Int = tr.value;
  if t < 0 {
    return _err_cmd("pulsar: missing command type at offset " + convert.int_to_string(n));
  }
  var cmd = _empty_command(t);
  cmd.known = pulsar_cmd_type_known(t);
  cmd.raw = _vec_copy(data);
  var body_start = -1;
  var body_end = -1;
  var pos = 0;
  while pos < n {
    let sr = _field_step(data, pos, n);
    if !sr.is_ok {
      return _err_cmd(sr.error);
    }
    let st: PulsarFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: PulsarFieldValue = st.value;
    if fnum == 1 && wt == 0 {
      // The type field was already scanned.
    } elif fnum == t && wt == 2 && t >= 2 {
      if body_start >= 0 {
        return _err_cmd("pulsar: duplicate command body at offset " + convert.int_to_string(st.tag_start));
      }
      body_start = fv.start;
      body_end = fv.start + fv.size;
      cmd.has_body = true;
    } else {
      _cmd_unknown(&mut cmd, data, st.tag_start, st.key_size + fv.total);
    }
    cmd.field_count = cmd.field_count + 1;
    pos = st.next;
  }
  if cmd.known && !cmd.has_body {
    return _err_cmd("pulsar: missing command body at offset " + convert.int_to_string(n));
  }
  if cmd.has_body {
    let wr = _walk_body(&mut cmd, data, body_start, body_end, 1);
    if !wr.is_ok {
      return _err_cmd(wr.error);
    }
  }
  return _ok_cmd(cmd);
}

// --------------------------------------------------
//  Frame
// --------------------------------------------------

/// Parse one frame starting at `offset`. The buffer must contain the whole
/// frame; bytes after it are ignored and `PulsarFrame.frame_len` is the
/// consumed count (4 + total_size).
///
/// Layout: u32 totalSize | u32 commandSize | BaseCommand bytes, and for a
/// SEND command (type 6) an optional tail u32 metadataSize |
/// MessageMetadata | payload (any bytes after the command for other
/// commands are kept raw in `payload`).
///
/// Err("pulsar: negative frame offset"); Err("pulsar: truncated frame
/// header at offset N"); Err("pulsar: bad total size at offset P");
/// Err("pulsar: bad command size at offset P"); Err("pulsar: truncated
/// frame at offset N"); Err("pulsar: truncated metadata size at offset N");
/// Err("pulsar: bad metadata size at offset P"); plus the command and
/// metadata decoder errors. N is the first missing byte.
/// Complexity: O(frame bytes).
pub fn pulsar_parse_frame_at(data: &Vec[UInt8], offset: Int) -> Result[PulsarFrame, Str] {
  let n = data.len();
  if offset < 0 {
    return _err_frame("pulsar: negative frame offset");
  }
  if offset + 8 > n {
    return _err_frame("pulsar: truncated frame header at offset " + convert.int_to_string(n));
  }
  let total = _read_be32(data, offset);
  let cmd_size = _read_be32(data, offset + 4);
  if total < 4 {
    return _err_frame("pulsar: bad total size at offset " + convert.int_to_string(offset));
  }
  let frame_len = 4 + total;
  if offset + frame_len > n {
    return _err_frame("pulsar: truncated frame at offset " + convert.int_to_string(n));
  }
  if cmd_size > total - 4 {
    return _err_frame("pulsar: bad command size at offset " + convert.int_to_string(offset + 4));
  }
  let cmd_start = offset + 8;
  let after_cmd = cmd_start + cmd_size;
  let raw = _slice(data, cmd_start, cmd_size);
  let cr = pulsar_decode_base_command(&raw);
  if !cr.is_ok {
    return _err_frame(cr.error);
  }
  let cmd: PulsarCommand = cr.value;
  var has_meta = false;
  var meta_size = 0;
  var meta = pulsar_metadata_new();
  var payload_start = after_cmd;
  if cmd.cmd_type == 6 {
    let rest = offset + frame_len - after_cmd;
    if rest > 0 && rest < 4 {
      return _err_frame("pulsar: truncated metadata size at offset " + convert.int_to_string(n));
    }
    if rest >= 4 {
      meta_size = _read_be32(data, after_cmd);
      let meta_start = after_cmd + 4;
      if meta_size > rest - 4 {
        return _err_frame("pulsar: bad metadata size at offset " + convert.int_to_string(after_cmd));
      }
      let mr = pulsar_parse_metadata_body(data, meta_start, meta_start + meta_size, 1);
      if !mr.is_ok {
        return _err_frame(mr.error);
      }
      let m: PulsarMessageMetadata = mr.value;
      meta = m;
      has_meta = true;
      payload_start = meta_start + meta_size;
    }
  }
  let payload_size = offset + frame_len - payload_start;
  let payload = _slice(data, payload_start, payload_size);
  return _ok_frame(PulsarFrame{
    total_size: total; command_size: cmd_size; command_offset: cmd_start;
    metadata_size: meta_size; payload_offset: payload_start; frame_len: frame_len;
    has_metadata: has_meta; command: cmd; metadata: meta; payload: payload;
  });
}

/// Parse one frame at offset 0 (see `pulsar_parse_frame_at`).
/// Complexity: O(frame bytes).
pub fn pulsar_parse_frame(data: &Vec[UInt8]) -> Result[PulsarFrame, Str] {
  return pulsar_parse_frame_at(data, 0);
}

/// Total consumed size of a parsed frame (4 + total_size). Complexity: O(1).
pub fn pulsar_frame_consumed(f: &PulsarFrame) -> Int {
  return f.frame_len;
}

/// The BaseCommand type value of a parsed frame. Complexity: O(1).
pub fn pulsar_frame_command_type(f: &PulsarFrame) -> Int {
  return f.command.cmd_type;
}

/// Number of decoded payload bytes of a frame. Complexity: O(1).
pub fn pulsar_frame_payload_len(f: &PulsarFrame) -> Int {
  return f.payload.len();
}

// --------------------------------------------------
//  Encoders
// --------------------------------------------------

// Append `v` (>= 0) as a base-128 varint.
fn _push_varint_raw(out: &mut Vec[UInt8], v: Int) {
  var x = v;
  while x >= 128 {
    out.push(((x % 128) + 128) as UInt8);
    x = x / 128;
  }
  out.push(x as UInt8);
}

// Append `v` as a base-128 varint; negative values use the 10-byte
// two's-complement sign-extended form proto2 writes for negative int32 and
// int64 fields.
fn _push_varint_signed(out: &mut Vec[UInt8], v: Int) {
  if v >= 0 {
    _push_varint_raw(out, v);
    return;
  }
  var x = v;
  var i = 0;
  while i < 9 {
    let m = ((x % 128) + 128) % 128;
    out.push((m + 128) as UInt8);
    x = (x - m) / 128;
    i = i + 1;
  }
  out.push(1 as UInt8);
}

// Append a field key (unchecked: field_number >= 1, wire type 0/1/2/5).
fn _push_key(out: &mut Vec[UInt8], field_number: Int, wire_type: Int) {
  _push_varint_raw(out, field_number * 8 + wire_type);
}

/// Encode a non-negative Int as a standalone varint.
/// Err("pulsar: negative varint value") for negative input.
/// Complexity: O(varint bytes).
pub fn pulsar_encode_varint(v: Int) -> Result[Vec[UInt8], Str] {
  if v < 0 {
    return _err_bytes("pulsar: negative varint value");
  }
  var out = Vec[UInt8].new();
  _push_varint_raw(&mut out, v);
  return _ok_bytes(out);
}

/// Encode a field key. Err("pulsar: bad field number") unless
/// field_number is in 1..536870911; Err("pulsar: bad wire type") unless the
/// wire type is 0/1/2/5. Complexity: O(1).
pub fn pulsar_encode_key(field_number: Int, wire_type: Int) -> Result[Vec[UInt8], Str] {
  if field_number < 1 || field_number > 536870911 {
    return _err_bytes("pulsar: bad field number");
  }
  if wire_type != 0 && wire_type != 1 && wire_type != 2 && wire_type != 5 {
    return _err_bytes("pulsar: bad wire type");
  }
  var out = Vec[UInt8].new();
  _push_key(&mut out, field_number, wire_type);
  return _ok_bytes(out);
}

// Append a wire type 2 field holding raw bytes.
fn _push_bytes_field(out: &mut Vec[UInt8], field_number: Int, v: &Vec[UInt8]) {
  _push_key(out, field_number, 2);
  _push_varint_raw(out, v.len());
  _push_vec(out, v);
}

// Append a wire type 2 field holding a Str; a NUL byte is rejected because
// it would make the encoded string ambiguous for this codec's readers.
fn _push_string_field(out: &mut Vec[UInt8], field_number: Int, s: Str) -> Result[Unit, Str] {
  let b = _str_to_bytes(s);
  var i = 0;
  while i < b.len() {
    if ((b[i] as Int) & 0xFF) == 0 {
      return _err_unit("pulsar: string contains nul");
    }
    i = i + 1;
  }
  _push_bytes_field(out, field_number, &b);
  return _ok_unit();
}

// Append a wire type 0 field.
fn _push_int_field(out: &mut Vec[UInt8], field_number: Int, v: Int) {
  _push_key(out, field_number, 0);
  _push_varint_signed(out, v);
}

/// Encode one length-delimited string field.
/// Err("pulsar: bad field number"); Err("pulsar: string contains nul").
/// Complexity: O(bytes).
pub fn pulsar_encode_string_field(field_number: Int, s: Str) -> Result[Vec[UInt8], Str] {
  if field_number < 1 || field_number > 536870911 {
    return _err_bytes("pulsar: bad field number");
  }
  var out = Vec[UInt8].new();
  let r = _push_string_field(&mut out, field_number, s);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  return _ok_bytes(out);
}

/// Encode one varint field (negative values use the sign-extended form).
/// Err("pulsar: bad field number"). Complexity: O(varint bytes).
pub fn pulsar_encode_varint_field(field_number: Int, v: Int) -> Result[Vec[UInt8], Str] {
  if field_number < 1 || field_number > 536870911 {
    return _err_bytes("pulsar: bad field number");
  }
  var out = Vec[UInt8].new();
  _push_int_field(&mut out, field_number, v);
  return _ok_bytes(out);
}

// MessageIdData body bytes.
fn _mid_body(m: &PulsarMessageId) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_int_field(&mut out, 1, m.ledger_id);
  _push_int_field(&mut out, 2, m.entry_id);
  if m.partition != -1 {
    _push_int_field(&mut out, 3, m.partition);
  }
  if m.batch_index != -1 {
    _push_int_field(&mut out, 4, m.batch_index);
  }
  var i = 0;
  while i < m.ack_set.len() {
    let v: Int = m.ack_set[i];
    _push_int_field(&mut out, 5, v);
    i = i + 1;
  }
  return out;
}

/// Encode a MessageIdData body. Err("pulsar: negative id") when ledger_id
/// or entry_id is negative. Complexity: O(ack entries).
pub fn pulsar_encode_message_id(m: &PulsarMessageId) -> Result[Vec[UInt8], Str] {
  if m.ledger_id < 0 || m.entry_id < 0 {
    return _err_bytes("pulsar: negative id");
  }
  return _ok_bytes(_mid_body(m));
}

/// Encode one length-delimited MessageIdData field.
/// Err("pulsar: bad field number"); Err("pulsar: negative id").
/// Complexity: O(ack entries).
pub fn pulsar_encode_message_id_field(field_number: Int, m: &PulsarMessageId) -> Result[Vec[UInt8], Str] {
  if field_number < 1 || field_number > 536870911 {
    return _err_bytes("pulsar: bad field number");
  }
  if m.ledger_id < 0 || m.entry_id < 0 {
    return _err_bytes("pulsar: negative id");
  }
  let body = _mid_body(m);
  var out = Vec[UInt8].new();
  _push_bytes_field(&mut out, field_number, &body);
  return _ok_bytes(out);
}

/// Encode a MessageMetadata body for every field this package decodes.
/// Err("pulsar: string contains nul") when a present string field holds a
/// NUL byte. Complexity: O(properties bytes).
pub fn pulsar_encode_metadata(m: &PulsarMessageMetadata) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  if m.has_producer_name {
    let s: Str = m.producer_name;
    let r = _push_string_field(&mut out, 1, s);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
  }
  if m.has_sequence_id {
    _push_int_field(&mut out, 2, m.sequence_id);
  }
  if m.has_publish_time {
    _push_int_field(&mut out, 3, m.publish_time);
  }
  var i = 0;
  while i < m.property_keys.len() {
    let k: Vec[UInt8] = m.property_keys[i];
    let v: Vec[UInt8] = m.property_values[i];
    var kv = Vec[UInt8].new();
    _push_bytes_field(&mut kv, 1, &k);
    _push_bytes_field(&mut kv, 2, &v);
    _push_bytes_field(&mut out, 4, &kv);
    i = i + 1;
  }
  if m.has_partition_key {
    let s: Str = m.partition_key;
    let r = _push_string_field(&mut out, 6, s);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
  }
  if m.has_compression {
    _push_int_field(&mut out, 8, m.compression);
  }
  if m.has_uncompressed_size {
    _push_int_field(&mut out, 9, m.uncompressed_size);
  }
  if m.has_event_time {
    _push_int_field(&mut out, 12, m.event_time);
  }
  if m.has_deliver_at_time {
    _push_int_field(&mut out, 19, m.deliver_at_time);
  }
  return _ok_bytes(out);
}

// Encode the BaseCommand body for the decoded subset.
fn _command_body(c: &PulsarCommand) -> Result[Vec[UInt8], Str] {
  let t = c.cmd_type;
  var body = Vec[UInt8].new();
  if t == 2 {
    if c.client_version.len() > 0 {
      let s: Str = c.client_version;
      let r = _push_string_field(&mut body, 1, s);
      if !r.is_ok {
        return _err_bytes(r.error);
      }
    }
    if c.has_protocol_version {
      _push_int_field(&mut body, 4, c.protocol_version);
    }
    if c.auth_method_name.len() > 0 {
      let s: Str = c.auth_method_name;
      let r = _push_string_field(&mut body, 5, s);
      if !r.is_ok {
        return _err_bytes(r.error);
      }
    }
  } elif t == 3 {
    if c.server_version.len() > 0 {
      let s: Str = c.server_version;
      let r = _push_string_field(&mut body, 1, s);
      if !r.is_ok {
        return _err_bytes(r.error);
      }
    }
    if c.has_protocol_version {
      _push_int_field(&mut body, 2, c.protocol_version);
    }
    if c.has_max_message_size {
      _push_int_field(&mut body, 3, c.max_message_size);
    }
  } elif t == 4 {
    let topic: Str = c.topic;
    let r1 = _push_string_field(&mut body, 1, topic);
    if !r1.is_ok {
      return _err_bytes(r1.error);
    }
    let sub: Str = c.subscription;
    let r2 = _push_string_field(&mut body, 2, sub);
    if !r2.is_ok {
      return _err_bytes(r2.error);
    }
    _push_int_field(&mut body, 3, c.sub_type);
    _push_int_field(&mut body, 4, c.consumer_id);
    _push_int_field(&mut body, 5, c.request_id);
    if c.has_durable {
      if c.durable {
        _push_int_field(&mut body, 8, 1);
      } else {
        _push_int_field(&mut body, 8, 0);
      }
    }
  } elif t == 5 {
    let topic: Str = c.topic;
    let r1 = _push_string_field(&mut body, 1, topic);
    if !r1.is_ok {
      return _err_bytes(r1.error);
    }
    _push_int_field(&mut body, 2, c.producer_id);
    _push_int_field(&mut body, 3, c.request_id);
    if c.producer_name.len() > 0 {
      let s: Str = c.producer_name;
      let r2 = _push_string_field(&mut body, 4, s);
      if !r2.is_ok {
        return _err_bytes(r2.error);
      }
    }
  } elif t == 6 {
    _push_int_field(&mut body, 1, c.producer_id);
    _push_int_field(&mut body, 2, c.sequence_id);
    if c.has_num_messages {
      _push_int_field(&mut body, 3, c.num_messages);
    }
    if c.has_message_id {
      let m: PulsarMessageId = c.message_id;
      let r = pulsar_encode_message_id_field(9, &m);
      if !r.is_ok {
        return _err_bytes(r.error);
      }
      let mb: Vec[UInt8] = r.value;
      _push_vec(&mut body, &mb);
    }
  } elif t == 7 {
    _push_int_field(&mut body, 1, c.producer_id);
    _push_int_field(&mut body, 2, c.sequence_id);
    if c.has_message_id {
      let m: PulsarMessageId = c.message_id;
      let r = pulsar_encode_message_id_field(3, &m);
      if !r.is_ok {
        return _err_bytes(r.error);
      }
      let mb: Vec[UInt8] = r.value;
      _push_vec(&mut body, &mb);
    }
  } elif t == 8 {
    _push_int_field(&mut body, 1, c.producer_id);
    _push_int_field(&mut body, 2, c.sequence_id);
    if c.has_error_code {
      _push_int_field(&mut body, 3, c.error_code);
    }
    if c.has_error_message {
      let s: Str = c.error_message;
      let r = _push_string_field(&mut body, 4, s);
      if !r.is_ok {
        return _err_bytes(r.error);
      }
    }
  } elif t == 9 {
    _push_int_field(&mut body, 1, c.consumer_id);
    if c.has_message_id {
      let m: PulsarMessageId = c.message_id;
      let r = pulsar_encode_message_id_field(2, &m);
      if !r.is_ok {
        return _err_bytes(r.error);
      }
      let mb: Vec[UInt8] = r.value;
      _push_vec(&mut body, &mb);
    }
    if c.redelivery_count > 0 {
      _push_int_field(&mut body, 3, c.redelivery_count);
    }
    var i = 0;
    while i < c.msg_ack_set.len() {
      let v: Int = c.msg_ack_set[i];
      _push_int_field(&mut body, 4, v);
      i = i + 1;
    }
  } elif t == 10 {
    _push_int_field(&mut body, 1, c.consumer_id);
    _push_int_field(&mut body, 2, c.ack_type);
    var i = 0;
    while i < c.ack_ids.ledger_ids.len() {
      let ledger: Int = c.ack_ids.ledger_ids[i];
      let entry: Int = c.ack_ids.entry_ids[i];
      let part: Int = c.ack_ids.partitions[i];
      let batch: Int = c.ack_ids.batch_indexes[i];
      let bits: Int = c.ack_ids.ack_bits[i];
      var m = pulsar_message_id_new();
      m.ledger_id = ledger;
      m.entry_id = entry;
      m.partition = part;
      m.batch_index = batch;
      m.ack_set_bits = bits;
      let r = pulsar_encode_message_id_field(3, &m);
      if !r.is_ok {
        return _err_bytes(r.error);
      }
      let mb: Vec[UInt8] = r.value;
      _push_vec(&mut body, &mb);
      i = i + 1;
    }
  } elif t == 11 {
    _push_int_field(&mut body, 1, c.consumer_id);
    if c.has_message_permits {
      _push_int_field(&mut body, 2, c.message_permits);
    }
  } elif t == 12 {
    _push_int_field(&mut body, 1, c.consumer_id);
    _push_int_field(&mut body, 2, c.request_id);
  } elif t == 13 {
    _push_int_field(&mut body, 1, c.request_id);
  } elif t == 14 {
    _push_int_field(&mut body, 1, c.request_id);
    if c.has_error_code {
      _push_int_field(&mut body, 2, c.error_code);
    }
    if c.has_error_message {
      let s: Str = c.error_message;
      let r = _push_string_field(&mut body, 3, s);
      if !r.is_ok {
        return _err_bytes(r.error);
      }
    }
  } elif t == 15 {
    _push_int_field(&mut body, 1, c.producer_id);
    _push_int_field(&mut body, 2, c.request_id);
  } elif t == 16 {
    _push_int_field(&mut body, 1, c.consumer_id);
    _push_int_field(&mut body, 2, c.request_id);
  } elif t == 17 {
    _push_int_field(&mut body, 1, c.request_id);
    if c.producer_name.len() > 0 {
      let s: Str = c.producer_name;
      let r = _push_string_field(&mut body, 2, s);
      if !r.is_ok {
        return _err_bytes(r.error);
      }
    }
    if c.has_last_sequence_id {
      _push_int_field(&mut body, 3, c.last_sequence_id);
    }
  } elif t == 20 {
    _push_int_field(&mut body, 1, c.consumer_id);
    var i = 0;
    while i < c.ack_ids.ledger_ids.len() {
      let ledger: Int = c.ack_ids.ledger_ids[i];
      let entry: Int = c.ack_ids.entry_ids[i];
      let part: Int = c.ack_ids.partitions[i];
      let batch: Int = c.ack_ids.batch_indexes[i];
      let bits: Int = c.ack_ids.ack_bits[i];
      var m = pulsar_message_id_new();
      m.ledger_id = ledger;
      m.entry_id = entry;
      m.partition = part;
      m.batch_index = batch;
      m.ack_set_bits = bits;
      let r = pulsar_encode_message_id_field(2, &m);
      if !r.is_ok {
        return _err_bytes(r.error);
      }
      let mb: Vec[UInt8] = r.value;
      _push_vec(&mut body, &mb);
      i = i + 1;
    }
  } elif t == 21 {
    let topic: Str = c.topic;
    let r = _push_string_field(&mut body, 1, topic);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
    _push_int_field(&mut body, 2, c.request_id);
  } elif t == 22 {
    if c.has_partitions {
      _push_int_field(&mut body, 1, c.partitions);
    }
    var i = 0;
    while i < c.partition_names.len() {
      let nb: Vec[UInt8] = c.partition_names[i];
      _push_bytes_field(&mut body, 1, &nb);
      i = i + 1;
    }
    _push_int_field(&mut body, 2, c.request_id);
    if c.has_response_code {
      _push_int_field(&mut body, 3, c.response_code);
    }
  } elif t == 23 {
    let topic: Str = c.topic;
    let r = _push_string_field(&mut body, 1, topic);
    if !r.is_ok {
      return _err_bytes(r.error);
    }
    _push_int_field(&mut body, 2, c.request_id);
  } elif t == 24 {
    if c.broker_url.len() > 0 {
      let s: Str = c.broker_url;
      let r1 = _push_string_field(&mut body, 1, s);
      if !r1.is_ok {
        return _err_bytes(r1.error);
      }
    }
    if c.broker_url_tls.len() > 0 {
      let s: Str = c.broker_url_tls;
      let r2 = _push_string_field(&mut body, 2, s);
      if !r2.is_ok {
        return _err_bytes(r2.error);
      }
    }
    if c.has_response_code {
      _push_int_field(&mut body, 3, c.response_code);
    }
    _push_int_field(&mut body, 4, c.request_id);
  } elif t == 29 {
    _push_int_field(&mut body, 1, c.consumer_id);
    _push_int_field(&mut body, 2, c.request_id);
  } elif t == 32 {
    _push_int_field(&mut body, 1, c.request_id);
    if c.namespace.len() > 0 {
      let s: Str = c.namespace;
      let r = _push_string_field(&mut body, 2, s);
      if !r.is_ok {
        return _err_bytes(r.error);
      }
    }
  }
  return _ok_bytes(body);
}

/// Encode a whole BaseCommand: type field 1 plus the body field (its number
/// equals the type) for every known type, including PING/PONG with an empty
/// body. Err("pulsar: string contains nul") from body string fields;
/// Err("pulsar: negative id") from an embedded MessageIdData.
/// Complexity: O(command bytes).
pub fn pulsar_encode_command(c: &PulsarCommand) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  _push_int_field(&mut out, 1, c.cmd_type);
  let br = _command_body(c);
  if !br.is_ok {
    return _err_bytes(br.error);
  }
  let body: Vec[UInt8] = br.value;
  if pulsar_cmd_type_known(c.cmd_type) {
    _push_bytes_field(&mut out, c.cmd_type, &body);
  }
  return _ok_bytes(out);
}

/// Build a complete Pulsar frame: u32 totalSize | u32 commandSize |
/// command [| u32 metadataSize | metadata | payload]. `has_metadata` must be
/// true only for a SEND command. Sizes above 2^32 - 1 would truncate and are
/// a caller violation (documented in SPEC.md).
/// Complexity: O(parts bytes).
pub fn pulsar_encode_frame(command: &Vec[UInt8], has_metadata: Bool, metadata: &Vec[UInt8], payload: &Vec[UInt8]) -> Vec[UInt8] {
  var total = 4 + command.len();
  if has_metadata {
    total = total + 4 + metadata.len();
  }
  total = total + payload.len();
  var out = Vec[UInt8].new();
  _push_be32(&mut out, total);
  _push_be32(&mut out, command.len());
  _push_vec(&mut out, command);
  if has_metadata {
    _push_be32(&mut out, metadata.len());
    _push_vec(&mut out, metadata);
  }
  _push_vec(&mut out, payload);
  return out;
}

// --------------------------------------------------
//  Names and accessors
// --------------------------------------------------

/// The canonical name of a BaseCommand type value ("UNKNOWN" otherwise).
/// Complexity: O(1).
pub fn pulsar_cmd_type_name(t: Int) -> Str {
  if t == 2 {
    return "CONNECT";
  }
  if t == 3 {
    return "CONNECTED";
  }
  if t == 4 {
    return "SUBSCRIBE";
  }
  if t == 5 {
    return "PRODUCER";
  }
  if t == 6 {
    return "SEND";
  }
  if t == 7 {
    return "SEND_RECEIPT";
  }
  if t == 8 {
    return "SEND_ERROR";
  }
  if t == 9 {
    return "MESSAGE";
  }
  if t == 10 {
    return "ACK";
  }
  if t == 11 {
    return "FLOW";
  }
  if t == 12 {
    return "UNSUBSCRIBE";
  }
  if t == 13 {
    return "SUCCESS";
  }
  if t == 14 {
    return "ERROR";
  }
  if t == 15 {
    return "CLOSE_PRODUCER";
  }
  if t == 16 {
    return "CLOSE_CONSUMER";
  }
  if t == 17 {
    return "PRODUCER_SUCCESS";
  }
  if t == 18 {
    return "PING";
  }
  if t == 19 {
    return "PONG";
  }
  if t == 20 {
    return "REDELIVER_UNACKNOWLEDGED_MESSAGES";
  }
  if t == 21 {
    return "PARTITIONED_METADATA";
  }
  if t == 22 {
    return "PARTITIONED_METADATA_RESPONSE";
  }
  if t == 23 {
    return "LOOKUP";
  }
  if t == 24 {
    return "LOOKUP_RESPONSE";
  }
  if t == 29 {
    return "GET_LAST_MESSAGE_ID";
  }
  if t == 32 {
    return "GET_TOPICS_OF_NAMESPACE";
  }
  return "UNKNOWN";
}

/// The command-subscription name for a CommandSubscribe.SubType value:
/// Exclusive 0, Shared 1, Failover 2, Key_Shared 3 ("UNKNOWN" otherwise).
/// Complexity: O(1).
pub fn pulsar_sub_type_name(s: Int) -> Str {
  if s == 0 {
    return "Exclusive";
  }
  if s == 1 {
    return "Shared";
  }
  if s == 2 {
    return "Failover";
  }
  if s == 3 {
    return "Key_Shared";
  }
  return "UNKNOWN";
}

/// The name for a CommandAck.AckType value: Individual 0, Cumulative 1
/// ("UNKNOWN" otherwise; other values are decoded and preserved raw).
/// Complexity: O(1).
pub fn pulsar_ack_type_name(a: Int) -> Str {
  if a == 0 {
    return "Individual";
  }
  if a == 1 {
    return "Cumulative";
  }
  return "UNKNOWN";
}

/// The name for a CompressionType value ("UNKNOWN" otherwise).
/// Complexity: O(1).
pub fn pulsar_compression_name(c: Int) -> Str {
  if c == 0 {
    return "NONE";
  }
  if c == 1 {
    return "LZ4";
  }
  if c == 2 {
    return "ZLIB";
  }
  if c == 3 {
    return "ZSTD";
  }
  if c == 4 {
    return "SNAPPY";
  }
  return "UNKNOWN";
}

/// The BaseCommand type of a decoded command. Complexity: O(1).
pub fn pulsar_command_type(c: &PulsarCommand) -> Int {
  return c.cmd_type;
}

/// True when the command type is in the decoded subset. Complexity: O(1).
pub fn pulsar_command_known(c: &PulsarCommand) -> Bool {
  return c.known;
}

/// Number of fields walked in the command (envelope + body). O(1).
pub fn pulsar_command_field_count(c: &PulsarCommand) -> Int {
  return c.field_count;
}

/// Number of fields outside the decoded subset (preserved raw). O(1).
pub fn pulsar_command_unknown_fields(c: &PulsarCommand) -> Int {
  return c.unknown_fields;
}

/// True when the durable flag was present on the wire. Complexity: O(1).
pub fn pulsar_command_has_durable(c: &PulsarCommand) -> Bool {
  return c.has_durable;
}

/// Effective durable flag: the wire value when present, otherwise Pulsar's
/// proto2 default (true). Complexity: O(1).
pub fn pulsar_command_durable(c: &PulsarCommand) -> Bool {
  if c.has_durable {
    return c.durable;
  }
  return true;
}

/// Effective num_messages: the wire value when present, otherwise 1.
/// Complexity: O(1).
pub fn pulsar_command_num_messages(c: &PulsarCommand) -> Int {
  if c.has_num_messages {
    return c.num_messages;
  }
  return 1;
}

/// Number of partition-name strings decoded from a
/// PARTITIONED_METADATA_RESPONSE. Complexity: O(1).
pub fn pulsar_command_partition_name_count(c: &PulsarCommand) -> Int {
  return c.partition_names.len();
}

/// Partition-name `i` as raw bytes (empty when out of range).
pub fn pulsar_command_partition_name(c: &PulsarCommand, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= c.partition_names.len() {
    return Vec[UInt8].new();
  }
  let b: Vec[UInt8] = c.partition_names[i];
  return _vec_copy(&b);
}

