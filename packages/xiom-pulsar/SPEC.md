# xiom.pulsar -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3;
27/27 conformance tests; not published).
Manifest: `package.xi` (`xiom.pulsar`, version `0.1.0`).
Module: `src/pulsar.xi` (`module xiom.pulsar`).
Depends on `xiom.std`. The module imports `xiom.string`,
`xiom.string.builder` and `xiom.convert`; the tests add `xiom.test`,
`xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`. No FFI.

Reference: `apache/pulsar` `pulsar-common/src/main/proto/PulsarApi.proto`
(proto2, fetched 2026-09-27). Everything below is what this package
actually implements and accepts.

## Scope

- The protobuf wire subset Pulsar uses: base-128 varints, wire types 0
  (varint), 1 (fixed64), 2 (length-delimited) and 5 (fixed32); field keys;
  nested length-delimited messages with a depth cap; packed repeated
  varints; bounds-checked unknown-field skipping.
- The Pulsar binary-protocol frame: `u32 totalSize | u32 commandSize |
  BaseCommand | [u32 metadataSize | MessageMetadata | payload]`.
- The BaseCommand envelope and the 25 command types listed in the decoded
  subset table below; unknown commands and unknown fields are preserved
  raw and counted.
- MessageIdData and the MessageMetadata subset used by SEND.
- Encoders for the decoded subset (fields the decoder understands), for
  tests, replay and synthetic frames.

## Non-goals

- Transport: sockets, TLS, connection pools, reconnects, brokers, lookup
  caching; the codec operates on complete in-memory buffers.
- Client state: request-id correlation, producer/consumer registries,
  flow control, batching, chunking, deduplication, redelivery logic.
- Compression (LZ4/ZLIB/ZSTD/SNAPPY) and checksum computation/validation.
- Message payload schema decoding (`SingleMessageMetadata`, batches,
  schemas, encryption, transactions).
- Any command type whose body this package does not decode (for example
  CONSUMER_STATS 25, REACHED_END_OF_TOPIC 27, SEEK 28, GET_SCHEMA 34,
  AUTH_CHALLENGE 36, GET_OR_CREATE_SCHEMA 39, the 50+ transaction set and
  everything after 40): such commands decode successfully with
  `known = false`, every field preserved raw.

## Protobuf wire subset

All multi-byte *fixed* integers are little-endian; varints are base-128
little-endian groups with bit 7 as the continuation flag.

| Wire type | Name | Encoding |
|---|---|---|
| 0 | varint | base-128 varint, 1..10 bytes |
| 1 | fixed64 | 8 data bytes, little-endian |
| 2 | length-delimited | u32 varint length + that many payload bytes |
| 5 | fixed32 | 4 data bytes, little-endian |

Wire types 3/4 (groups) and 6/7 are rejected by every decoder with
`pulsar: unsupported wire type W at offset P`.

### Field keys

`key = field_number * 8 + wire_type`. Readers reject `field_number == 0`
(`pulsar: field number 0 at offset P`). Encoders reject field numbers
outside `1..536870911` (`pulsar: bad field number`) and wire types other
than 0/1/2/5 (`pulsar: bad wire type`).

### Varint limits (XIOM Int is signed 64-bit)

| Reader | Accepts | Rejects |
|---|---|---|
| `pulsar_read_varint` | `0 .. 2^63 - 1` | 10th-byte continuation, 10th-byte data > 1, 10th-byte bit 0 (bit 63) |
| `pulsar_read_varint_u32` | `0 .. 2^32 - 1` | the above plus values above `2^32 - 1` |
| `pulsar_read_varint_i32` | signed int32, sign-extended 10-byte forms included | > 10 bytes |
| `pulsar_read_varint_i64` | full signed int64 (10th-byte bit 0 = sign bit) | 10th-byte data > 1, > 10 bytes |

Non-minimal encodings are accepted (a 10-byte varint whose 10th byte is
`0x00` decodes to the 9-byte value). There is no bit-shift operator in
the implementation: the weight is multiplied by 128 per byte, and the
10th byte is handled separately so no intermediate reaches `2^63`.

### Length-delimited values and nesting

`pulsar_read_delimited` reads a u32 varint length and returns the payload
span. A payload that does not fit in the buffer is
`pulsar: truncated length-delimited field at offset N` (N = first missing
byte). Nested message entry points (`pulsar_parse_message_id_body`,
`pulsar_parse_metadata_body`, and the `_at` variants) take a `depth`
argument and reject `depth > 16` with
`pulsar: nesting depth exceeds limit of 16 at offset P`.

### Packed repeated varints

A packed run is a wire-type-2 field whose payload is a sequence of
varints. `pulsar_read_packed_varints` appends every decoded value to the
caller's vector, returns the count, rejects a varint that crosses the
declared run end (`pulsar: packed run crosses boundary at offset P`) and
caps the run at 65536 values (`pulsar: packed run too large at offset S`).

### Unknown-field skipping

`pulsar_skip_field` advances over a value of wire type 0/1/2/5 and
returns the new position plus the byte count; it is bounds-checked with
the same truncation errors as the matching reader.

## Frame layout

Offsets are relative to the start of the frame (`offset` in
`pulsar_parse_frame_at`).

| Offset | Width | Field |
|---|---|---|
| 0 | 4 | `totalSize` (u32 BE): bytes after this field |
| 4 | 4 | `commandSize` (u32 BE): bytes of the BaseCommand |
| 8 | commandSize | BaseCommand protobuf bytes |
| 8+commandSize | 4 | `metadataSize` (u32 BE), SEND (type 6) only |
| 12+commandSize | metadataSize | MessageMetadata protobuf bytes, SEND only |
| ... | rest | payload bytes, SEND only |

`frame_len = 4 + totalSize`. Validation order and exact errors:

1. `offset < 0` -> `pulsar: negative frame offset`.
2. fewer than 8 bytes available -> `pulsar: truncated frame header at
   offset N` (N = buffer end).
3. `totalSize < 4` -> `pulsar: bad total size at offset P` (P = frame
   offset).
4. `offset + 4 + totalSize > len` -> `pulsar: truncated frame at offset
   N`.
5. `commandSize > totalSize - 4` -> `pulsar: bad command size at offset
   P` (P = frame offset + 4).
6. BaseCommand decode errors pass through unchanged.
7. For a SEND command: `rest = frame_len - (8 + commandSize)`.
   * `0 < rest < 4` -> `pulsar: truncated metadata size at offset N`.
   * `metadataSize > rest - 4` -> `pulsar: bad metadata size at offset P`
     (P = offset of the metadata size field).
   * otherwise the metadata body is decoded at depth 1.
   * `rest == 0` decodes with `has_metadata = false` (the field is
     optional in this codec's model).
8. For every other command every byte after the command is kept raw in
   `payload` (normally zero bytes).

`pulsar_parse_frame_at` ignores bytes after the frame; the caller
advances by `PulsarFrame.frame_len` / `pulsar_frame_consumed(f)`.

## BaseCommand envelope

`BaseCommand` is a proto2 message:

| Field | Number | Type | Meaning |
|---|---|---|---|
| type | 1 | enum Type | command discriminator |
| body | == type | message | the per-type command message |

Decode algorithm: scan field 1 for the type; then walk the top-level
fields. For a known type the field whose number equals the type and whose
wire type is 2 is the body (a second one is
`pulsar: duplicate command body at offset P`; a missing one is
`pulsar: missing command body at offset N`). Unknown top-level fields are
counted and their raw tag+value bytes appended to
`PulsarCommand.unknown_bytes`. The whole command is copied into
`PulsarCommand.raw`. `PulsarCommand.field_count` counts envelope fields
plus decoded body fields; `unknown_fields` counts every field outside the
decoded subset.

An empty body (length 0) for a known type is valid: all fields keep their
proto2 defaults.

### Command type values

Canonical `BaseCommand.Type` values implemented by this package:
2 CONNECT, 3 CONNECTED, 4 SUBSCRIBE, 5 PRODUCER, 6 SEND, 7 SEND_RECEIPT,
8 SEND_ERROR, 9 MESSAGE, 10 ACK, 11 FLOW, 12 UNSUBSCRIBE, 13 SUCCESS,
14 ERROR, 15 CLOSE_PRODUCER, 16 CLOSE_CONSUMER, 17 PRODUCER_SUCCESS, 18 PING,
19 PONG, 20 REDELIVER_UNACKNOWLEDGED_MESSAGES, 21 PARTITIONED_METADATA,
22 PARTITIONED_METADATA_RESPONSE, 23 LOOKUP, 24 LOOKUP_RESPONSE,
29 GET_LAST_MESSAGE_ID, 32 GET_TOPICS_OF_NAMESPACE.

> **Discrepancy note.** The port brief listed `GET_LAST_MESSAGE_ID 27`,
> `GET_TOPICS_OF_NAMESPACE 28` and `LOOKUP 40`. The canonical
> `apache/pulsar` `PulsarApi.proto` has 29, 32 and 23 respectively
> (27 = REACHED_END_OF_TOPIC, 28 = SEEK, 40 = GET_OR_CREATE_SCHEMA_RESPONSE).
> This wire codec follows the canonical values; `pulsar_cmd_*()` exposes
> them and `SPEC.md` records the difference.

### Decoded command fields

For every row: wire type 2 = string (validated strict UTF-8, NUL
rejected), wire type 0 = varint. "has_" flags record wire presence.

| Type | Body fields decoded |
|---|---|
| CONNECT (2) | 1 `client_version` str; 4 `protocol_version` int32; 5 `auth_method_name` str. |
| CONNECTED (3) | 1 `server_version` str; 2 `protocol_version` int32; 3 `max_message_size` int32. |
| SUBSCRIBE (4) | 1 `topic` str; 2 `subscription` str; 3 `sub_type` 0..3; 4 `consumer_id`; 5 `request_id`; 8 `durable` bool (`has_durable`; effective default true). |
| PRODUCER (5) | 1 `topic` str; 2 `producer_id`; 3 `request_id`; 4 `producer_name` str. |
| SEND (6) | 1 `producer_id`; 2 `sequence_id`; 3 `num_messages` int32 (effective default 1); 9 `message_id` MessageIdData. |
| SEND_RECEIPT (7) | 1 `producer_id`; 2 `sequence_id`; 3 `message_id` MessageIdData. |
| SEND_ERROR (8) | 1 `producer_id`; 2 `sequence_id`; 3 `error` enum; 4 `message` str. |
| MESSAGE (9) | 1 `consumer_id`; 2 `message_id` MessageIdData; 3 `redelivery_count`; 4 `ack_set` (unpacked or packed). |
| ACK (10) | 1 `consumer_id`; 2 `ack_type` (0 Individual, 1 Cumulative; other values preserved); 3 repeated `message_id` (flat list); 8 `request_id`. |
| FLOW (11) | 1 `consumer_id`; 2 `messagePermits`. |
| UNSUBSCRIBE (12) | 1 `consumer_id`; 2 `request_id`. |
| SUCCESS (13) | 1 `request_id`. |
| ERROR (14) | 1 `request_id`; 2 `error`; 3 `message` str. |
| CLOSE_PRODUCER (15) | 1 `producer_id`; 2 `request_id`. |
| CLOSE_CONSUMER (16) | 1 `consumer_id`; 2 `request_id`. |
| PRODUCER_SUCCESS (17) | 1 `request_id`; 2 `producer_name` str; 3 `last_sequence_id` int64. |
| PING (18) / PONG (19) | none (body is normally zero-length). |
| REDELIVER_UNACKNOWLEDGED_MESSAGES (20) | 1 `consumer_id`; 2 repeated `message_ids` MessageIdData. |
| PARTITIONED_METADATA (21) | 1 `topic` str; 2 `request_id`. |
| PARTITIONED_METADATA_RESPONSE (22) | 1 `partitions` uint32 **or** repeated partition-name strings (both wire forms accepted); 2 `request_id`; 3 `response` enum. |
| LOOKUP (23) | 1 `topic` str; 2 `request_id`. |
| LOOKUP_RESPONSE (24) | 1 `brokerServiceUrl` str; 2 `brokerServiceUrlTls` str; 3 `response` enum; 4 `request_id`. |
| GET_LAST_MESSAGE_ID (29) | 1 `consumer_id`; 2 `request_id`. |
| GET_TOPICS_OF_NAMESPACE (32) | 1 `request_id`; 2 `namespace` str. |

Repeated MessageIdData fields decode into `PulsarMessageIdList`, five
parallel vectors (ledger, entry, partition, batch index, ack summary) that
are always pushed together. The `PARTITIONED_METADATA_RESPONSE` partition
names are `Vec[Vec[UInt8]]` (validated UTF-8, no NUL).

### Unknown and hostile input

- Field number 0, unsupported wire types, truncated keys/values and
  values crossing the containing message boundary are rejected with
  byte offsets (see the catalog).
- Unknown fields are skipped with bounds checks; they are never trusted
  for lengths.
- `ack_set` and packed runs are capped (4096 entries per id, 65536 per
  packed run) so hostile counts fail fast instead of driving huge pushes.
- A NUL byte in any decoded string is rejected (v0.61.3's `sb_to_str`
  aborts on NUL).

## MessageIdData

| Field | Number | Type | Default |
|---|---|---|---|
| ledgerId | 1 | uint64 | 0 (required) |
| entryId | 2 | uint64 | 0 (required) |
| partition | 3 | int32 | -1 |
| batch_index | 4 | int32 | -1 |
| ack_set | 5 | repeated int64 | empty |

`ack_set` accepts both unpacked varints (one field 5 per value) and one
packed wire-type-2 run. The decoded values are kept in
`PulsarMessageId.ack_set`; `ack_set_bits` is a 63-bit summary: for each
non-negative entry `v`, bit `v % 63` is set (idempotently). Bit 63 is not
representable as a positive signed Int, hence 63 positions; negative
entries are kept in the list but do not set a summary bit.
`pulsar_message_id_ack_has(m, v)` tests the bit.

## MessageMetadata

| Field | Number | Type | Decoded as |
|---|---|---|---|
| producer_name | 1 | string | `producer_name` (has flag) |
| sequence_id | 2 | uint64 | `sequence_id` (has flag) |
| publish_time | 3 | uint64 | `publish_time` (has flag) |
| properties | 4 | repeated KeyValue | parallel key/value byte vectors |
| partition_key | 6 | string | `partition_key` (has flag) |
| compression | 8 | enum | `compression` (has flag; NONE 0, LZ4 1, ZLIB 2, ZSTD 3, SNAPPY 4) |
| uncompressed_size | 9 | uint32 | `uncompressed_size` (has flag) |
| event_time | 12 | uint64 | `event_time` (has flag) |
| deliver_at_time | 19 | int64 | `deliver_at_time` (has flag) |

`KeyValue` is `{ 1: key string, 2: value string }`; a pair missing either
half fails with `pulsar: incomplete key-value pair at offset S`. All other
`MessageMetadata` fields (replicated_from 5, replicate_to 7,
num_messages_in_batch 11, encryption 13-16, ordering_key 18, marker_type
20, transactions 22-23, highest_sequence_id 24, uuid 26, chunking 27-29,
and everything after) are counted in `unknown_fields` and skipped.

proto2 defaults are not synthesized: absent optional fields keep the
zero/empty value and `has_* == false` except `num_messages` (effective 1
via `pulsar_command_num_messages`) and `durable` (effective true via
`pulsar_command_durable`).

## Encoders

`pulsar_encode_command` writes field 1 (type) plus the body field for
every known type, including PING/PONG with an empty body, with fields in
ascending field-number order. Only present (`has_*`) optional fields and
non-empty strings are written; `MESSAGE` writes `redelivery_count` only
when positive. Unknown fields captured at decode time are not re-emitted.
`pulsar_encode_frame` writes `totalSize = 4 + commandSize + [4 +
metadataSize] + payloadSize` and does not validate the u32 ceiling
(inputs above `2^32 - 1` are a caller violation). Encoding rejects NUL in
string fields (`pulsar: string contains nul`) and negative ledger/entry
ids (`pulsar: negative id`).

## Error catalog

Both `N` and `P` are absolute byte offsets in the buffer handed to the
function that failed. `N` always means "the first byte that was required
and is missing" (the buffer end for the outermost call); `P` means the
offset of the offending field/value/key; `Q` means the offset of the
offending string or UTF-8 byte.

| Error | Raised by |
|---|---|
| `pulsar: empty base command` | command decode, empty input |
| `pulsar: missing command type at offset N` | command decode, no field 1 |
| `pulsar: missing command body at offset N` | command decode, known type |
| `pulsar: duplicate command body at offset P` | command decode |
| `pulsar: field number 0 at offset P` | field walkers |
| `pulsar: truncated field at offset N` | field walkers |
| `pulsar: field crosses message boundary at offset P` | field walkers |
| `pulsar: unsupported wire type W at offset P` | field walkers, skip |
| `pulsar: varint out of bounds at offset P` | varint readers |
| `pulsar: truncated varint at offset N` | varint readers |
| `pulsar: varint too long at offset P` | varint readers |
| `pulsar: varint overflows 64 bits at offset P` | varint readers |
| `pulsar: varint exceeds signed 64-bit range at offset P` | u64 reader |
| `pulsar: varint exceeds u32 at offset P` | u32 reader |
| `pulsar: truncated fixed32 at offset N` | fixed32 reader, skip |
| `pulsar: truncated fixed64 at offset N` | fixed64 reader, skip |
| `pulsar: fixed64 exceeds signed 64-bit range at offset P` | fixed64 reader |
| `pulsar: truncated length-delimited field at offset N` | delimited reader |
| `pulsar: packed run crosses boundary at offset P` | packed reader |
| `pulsar: packed run too large at offset S` | packed reader |
| `pulsar: string contains nul at offset Q` | string/UTF-8 decode |
| `pulsar: invalid utf-8 at offset Q` | string decode |
| `pulsar: nesting depth exceeds limit of 16 at offset P` | nested decoders |
| `pulsar: bad message range at offset P` | body decoders |
| `pulsar: ack_set too large at offset P` | ack_set accumulation |
| `pulsar: incomplete key-value pair at offset S` | property decode |
| `pulsar: expected length-delimited at offset P` | `*_at` entry points |
| `pulsar: negative frame offset` | frame parse |
| `pulsar: truncated frame header at offset N` | frame parse |
| `pulsar: bad total size at offset P` | frame parse |
| `pulsar: bad command size at offset P` | frame parse |
| `pulsar: truncated frame at offset N` | frame parse |
| `pulsar: truncated metadata size at offset N` | frame parse |
| `pulsar: bad metadata size at offset P` | frame parse |
| `pulsar: negative varint value` | encoder |
| `pulsar: bad field number` / `pulsar: bad wire type` | key encoder |
| `pulsar: negative id` | message id encoder |
| `pulsar: string contains nul` | string field encoder |

## Test coverage

`tests/test_conformance.xi` (27 checks, all green) covers: varint
boundaries (`0`, `127`, `128`, `16383`, `16384`, `2^32-1`, `2^63-1`) and
every varint error; u32/i32/i64 readers including sign-extended `-1`;
fixed32/fixed64; field keys; length-delimited values; unknown-field skip;
packed runs; MessageIdData defaults and ack_set (unpacked, packed, 63-bit
summary); CONNECT/CONNECTED/SUBSCRIBE/PRODUCER/SEND/MESSAGE/SEND_RECEIPT/
ACK/PING/PONG decoding; a SEND frame with metadata properties, compression
and payload (consumed count and offsets); full MessageMetadata; unknown
body-field preservation; malformed frame lengths with exact byte-offset
errors; encode -> decode byte-identical round-trips; the nesting cap; the
name/constant tables; NUL and invalid UTF-8 rejection; and sequential
frame parsing via `pulsar_frame_consumed`.
