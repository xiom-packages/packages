# xiom.pulsar

> **Status:** `incubating` -- implemented and green on the local harness
> (27/27 with compiler v0.61.3), NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM Apache Pulsar **wire codec**: the protobuf-wire subset
> Pulsar uses, the u32/u32 frame framing, and a documented BaseCommand /
> MessageMetadata / MessageIdData decode subset. No network, no sockets, no
> brokers, no client state machine, no compression and no checksum
> validation.
> **Deps:** `xiom.std` only. The module imports `xiom.string`,
> `xiom.string.builder` and `xiom.convert`; the tests add `xiom.test`,
> `xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`. No FFI.

## What it is

`xiom.pulsar` encodes and decodes the byte-level protocol of Apache Pulsar
(`PulsarApi.proto`, proto2 wire format) over complete in-memory buffers.
It is the transport-free half of a Pulsar client: feed it bytes read from a
socket and it tells you what the broker said; hand it bytes and it tells you
what to write.

```
frame      u32 totalSize | u32 commandSize | BaseCommand bytes
           [ u32 metadataSize | MessageMetadata | payload ]   (SEND only)
command    BaseCommand protobuf: type field 1, body field (number == type)
metadata   MessageMetadata protobuf (SEND only)
payload    opaque bytes (compression is NOT applied or checked here)
```

Decoded command subset: CONNECT (2), CONNECTED (3), SUBSCRIBE (4),
PRODUCER (5), SEND (6), SEND_RECEIPT (7), SEND_ERROR (8), MESSAGE (9),
ACK (10), FLOW (11), UNSUBSCRIBE (12), SUCCESS (13), ERROR (14),
CLOSE_PRODUCER (15), CLOSE_CONSUMER (16), PRODUCER_SUCCESS (17), PING (18),
PONG (19), REDELIVER_UNACKNOWLEDGED_MESSAGES (20), PARTITIONED_METADATA (21),
PARTITIONED_METADATA_RESPONSE (22), LOOKUP (23), LOOKUP_RESPONSE (24),
GET_LAST_MESSAGE_ID (29), GET_TOPICS_OF_NAMESPACE (32). Every other type and
every field outside the decoded subset is preserved raw (`PulsarCommand.raw`
and `PulsarCommand.unknown_bytes`) and counted.

## API

Wire primitives (`Result[_, Str]` errors carry byte offsets):

| Function | Returns | Description |
|---|---|---|
| `pulsar_read_varint(data, pos)` | `Result[PulsarScalar, Str]` | Base-128 varint, u64 semantics restricted to `2^63 - 1`. |
| `pulsar_read_varint_u32(data, pos)` | `Result[PulsarScalar, Str]` | Same, rejects above `2^32 - 1`. |
| `pulsar_read_varint_i32(data, pos)` | `Result[PulsarScalar, Str]` | Signed int32 (accepts 10-byte sign-extended values). |
| `pulsar_read_varint_i64(data, pos)` | `Result[PulsarScalar, Str]` | Full signed int64 range. |
| `pulsar_read_fixed32(data, pos)` / `pulsar_read_fixed64(data, pos)` | `Result[PulsarScalar, Str]` | Wire types 5 / 1. |
| `pulsar_read_delimited(data, pos)` | `Result[PulsarDelimited, Str]` | Length prefix + payload span. |
| `pulsar_skip_field(data, pos, wire_type)` | `Result[PulsarAdvance, Str]` | Bounds-checked unknown-field skip. |
| `pulsar_read_packed_varints(data, start, end, out)` | `Result[Int, Str]` | Packed repeated run into `out`. |
| `pulsar_key(fn, wt)` / `pulsar_key_field_number(key)` / `pulsar_key_wire_type(key)` | `Int` | Field-key arithmetic. |

Decoders:

| Function | Returns | Description |
|---|---|---|
| `pulsar_parse_frame(data)` / `pulsar_parse_frame_at(data, offset)` | `Result[PulsarFrame, Str]` | One frame; `frame_len` is the consumed count. |
| `pulsar_decode_base_command(data)` | `Result[PulsarCommand, Str]` | BaseCommand with the decoded subset. |
| `pulsar_parse_metadata_body(data, start, end, depth)` / `pulsar_parse_metadata_at(data, pos, depth)` | `Result[PulsarMessageMetadata, Str]` | MessageMetadata (nested-aware). |
| `pulsar_parse_message_id_body(data, start, end, depth)` / `pulsar_parse_message_id_at(data, pos, depth)` | `Result[PulsarMessageId, Str]` | MessageIdData. |
| `pulsar_bytes_to_str(v)` / `pulsar_span_to_str(data, start, size)` | `Result[Str, Str]` | Strict UTF-8, NUL-rejecting string materialization. |

Encoders (for tests, replay and synthetic frames):

| Function | Returns | Description |
|---|---|---|
| `pulsar_encode_varint(v)` / `pulsar_encode_key(fn, wt)` | `Result[Vec[UInt8], Str]` | Single scalar / key. |
| `pulsar_encode_string_field(fn, s)` / `pulsar_encode_varint_field(fn, v)` | `Result[Vec[UInt8], Str]` | One field. |
| `pulsar_encode_message_id(m)` / `pulsar_encode_message_id_field(fn, m)` | `Result[Vec[UInt8], Str]` | MessageIdData body / field. |
| `pulsar_encode_metadata(m)` | `Result[Vec[UInt8], Str]` | MessageMetadata body. |
| `pulsar_encode_command(c)` | `Result[Vec[UInt8], Str]` | BaseCommand for every known type. |
| `pulsar_encode_frame(command, has_metadata, metadata, payload)` | `Vec[UInt8]` | Complete frame with computed sizes. |

Accessors: `pulsar_frame_consumed`, `pulsar_frame_command_type`,
`pulsar_frame_payload_len`, `pulsar_command_type/known/field_count/`
`unknown_fields/durable/num_messages/partition_name*`,
`pulsar_mid_list_len/ledger/entry/partition/batch_index/ack_bits`,
`pulsar_message_id_ack_count/ack_at/ack_has`,
`pulsar_metadata_property_count/key/value`,
`pulsar_metadata_add_property(_str)`, plus the constant and name
functions (`pulsar_cmd_*`, `pulsar_wire_*`, `pulsar_cmd_type_name`,
`pulsar_sub_type_name`, `pulsar_ack_type_name`, `pulsar_compression_name`).

`SPEC.md` has the byte tables, the full error catalog and the limitations.

## Usage

```xi
use xiom.pulsar;
use xiom.io;
use xiom.string.compare;

fn main() -> Int {
  // Bytes read from a Pulsar binary-protocol socket.
  // let bytes: Vec[UInt8] = ...;

  // Decode exactly one frame; frame_len is how far to advance the stream.
  // let r = pulsar_parse_frame(&bytes);
  // if !r.is_ok { io.println(r.error); return 1; }
  // let f: PulsarFrame = r.value;

  // SEND on the producer side:
  //   f.command.producer_id, f.command.sequence_id
  //   pulsar_command_num_messages(&f.command)
  //   f.has_metadata, f.metadata.producer_name
  //   pulsar_metadata_property_count(&f.metadata)
  //   f.payload
  //
  // MESSAGE on the consumer side:
  //   f.command.consumer_id, f.command.message_id.ledger_id
  //   f.command.message_id.entry_id, f.command.message_id.partition
  //   f.command.redelivery_count
  return 0;
}
```

Building a frame by hand (the tests do this too):

```xi
// var cmd = Vec[UInt8].new();           // BaseCommand bytes
// var meta = Vec[UInt8].new();          // MessageMetadata bytes
// let payload = Vec[UInt8].new();       // opaque payload
// let frame = pulsar_encode_frame(&cmd, true, &meta, &payload);
// let back = pulsar_parse_frame(&frame);
```

## Honest boundaries

- No transport, no broker, no client state: this package never opens a
  socket and never talks to a cluster.
- XIOM `Int` is signed 64-bit. A u64 varint whose value is `>= 2^63` is
  rejected with a deterministic error instead of being truncated, and the
  ack_set bitset summary uses 63 bit positions (`v % 63`).
- `pulsar_parse_frame_at` ignores bytes after the frame; use
  `pulsar_frame_consumed` to advance. For a non-SEND command any bytes after
  the command are kept raw in `payload`.
- The encoder writes only the decoded subset: fields decoded as "unknown" are
  counted and preserved in `raw`/`unknown_bytes` but are not re-emitted by
  `pulsar_encode_command`.
- No compression or decompression, no checksum validation, no batching
  (SingleMessageMetadata) decoding, no schema/transaction command bodies.
- The command-type numbers follow the canonical `apache/pulsar`
  `PulsarApi.proto`; see `SPEC.md` for the note about the port brief's
  hints (GET_LAST_MESSAGE_ID 27 / GET_TOPICS_OF_NAMESPACE 28 / LOOKUP 40).
