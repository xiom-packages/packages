# xiom.etcd -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3;
26/26 conformance tests; not published).
Manifest: `package.xi` (`xiom.etcd`, version `0.1.0`).
Module: `src/etcd.xi` (`module xiom.etcd`).
Depends on `xiom.std`. The module imports `xiom.string`,
`xiom.string.builder` and `xiom.convert`; the tests add `xiom.test`,
`xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`. No FFI.

Reference: `etcd-io/etcd` `api/etcdserverpb/rpc.proto` (proto3). Everything
below is what this package actually implements and accepts.

## Scope

- The protobuf wire subset etcd uses: base-128 varints, wire types 0
  (varint), 1 (fixed64), 2 (length-delimited) and 5 (fixed32); field keys;
  nested length-delimited messages with a depth cap; packed repeated
  varints; bounds-checked unknown-field skipping.
- The gRPC frame: `1 flag byte | u32 BE message length | message bytes`,
  parsed one frame at a time with consumed counts.
- The `etcdserverpb` message subset in the tables below. Unknown fields are
  counted and preserved raw (`EtcdUnknown.bytes`); one-of branches and
  repeated messages are kept as raw nested bodies with kind tags plus the
  decoded parallel vectors, and can be re-decoded on demand with the exposed
  body parsers.
- Encoders for the wire primitives, field keys and the gRPC frame, for
  tests, replay and synthetic input.

## Non-goals

- Transport: sockets, TLS, HTTP/2, connection pools, DNS, load balancing,
  watches (the long-running call), retries, timeouts.
- Client state: request-id correlation, watcher registries, lease refresh,
  auth token lifecycle, revision bookkeeping, transactional retry logic.
- gRPC compression and the rest of the gRPC header block: the compressed
  flag is preserved but never interpreted; framing here starts at the 5-byte
  LPM (length-prefixed message) level.
- Messages outside the decoded subset (for example `MemberAdd`,
  `MemberRemove`, `MemberUpdate`, `MemberPromote`, `Downgrade`,
  `AuthUserGet`, `AuthRoleGet`, `AuthRoleGrantPermission`, the rest of the
  authz/admin RPC set, `RangeRequest` outside the listed fields,
  `SnapshotRequest`, `StatusRequest`): calling the generic field walkers on
  them is possible, but there is no dedicated decoder; within the decoded
  messages every unknown field is skipped with bounds checks and preserved
  raw (except per-`Member` unknowns, see the MemberList note).
- Proto3 JSON, protobuf reflection, schema resolution, proto2 groups.

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
`etcd: unsupported wire type W at offset P`.

### Field keys

`key = field_number * 8 + wire_type`. Readers reject `field_number == 0`
(`etcd: field number 0 at offset P`). Encoders reject field numbers outside
`1..536870911` (`etcd: bad field number`) and wire types other than 0/1/2/5
(`etcd: bad wire type`).

### Varint limits (XIOM Int is signed 64-bit)

| Reader | Accepts | Rejects |
|---|---|---|
| `etcd_read_varint` | `0 .. 2^63 - 1` | 10th-byte continuation, 10th-byte data > 1, 10th-byte bit 0 (bit 63) |
| `etcd_read_varint_u32` | `0 .. 2^32 - 1` | the above plus values above `2^32 - 1` |
| `etcd_read_varint_i32` | signed int32, sign-extended 10-byte forms included | > 10 bytes |
| `etcd_read_varint_i64` | full signed int64 (10th-byte bit 0 = sign bit) | 10th-byte data > 1, > 10 bytes |

Non-minimal encodings are accepted (a 10-byte varint whose 10th byte is
`0x00` decodes to the 9-byte value). There is no bit-shift operator in the
implementation: the weight is multiplied by 128 per byte, and the 10th byte
is handled separately so no intermediate reaches `2^63`.

Because `Int` is signed, every u64/uint64 field in the tables below is
carried as `Int`: wire values `>= 2^63` fail with
`etcd: varint exceeds signed 64-bit range at offset P` instead of
truncating. Negative int64 fields are decoded exactly through the
sign-extended form (`etcd_read_varint_i64`).

### Length-delimited values and nesting

`etcd_read_delimited` reads a u32 varint length and returns the payload
span. A payload that does not fit in the buffer is
`etcd: truncated length-delimited field at offset N` (N = first missing
byte). Every message body parser takes a `depth` argument (top-level calls
use 1) and rejects `depth > 16` with
`etcd: nesting depth exceeds limit of 16 at offset P`.

### Packed repeated varints

A packed run is a wire-type-2 field whose payload is a sequence of varints.
`etcd_read_packed_varints` appends every decoded value to the caller's
vector, returns the count, rejects a varint that crosses the declared run
end (`etcd: packed run crosses boundary at offset P`) and caps the run at
65536 values (`etcd: packed run too large at offset S`). Watch create
filters accept both the unpacked (wire type 0) and packed (wire type 2)
forms, preserving wire order.

### Unknown-field skipping

`etcd_skip_field` advances over a value of wire type 0/1/2/5 and returns the
new position plus the byte count; it is bounds-checked with the same
truncation errors as the matching reader. Every decoded message counts
fields outside its decoded subset and appends their raw tag+value bytes to
`EtcdUnknown.bytes` in wire order, so nothing is silently dropped.

## gRPC frame

Offsets are relative to the start of the frame (`offset` in
`etcd_parse_frame_at`).

| Offset | Width | Field |
|---|---|---|
| 0 | 1 | compressed flag (0 uncompressed, 1 compressed; preserved raw) |
| 1 | 4 | message length (u32 BE) |
| 5 | length | message bytes (protobuf) |

`frame_len = 5 + length`. Validation order and exact errors:

1. `offset < 0` -> `etcd: negative frame offset`.
2. fewer than 5 bytes available -> `etcd: truncated grpc frame header at
   offset N` (N = buffer end).
3. `length > etcd_max_message_bytes()` (8 MiB) -> `etcd: grpc message
   exceeds 8 MiB at offset P` (P = frame offset). This is a v0.61.3 runtime
   guard: the compiler's `Vec` aborts on ~16 MiB vectors (two live ~16 MiB
   vectors also abort), and this codec copies the message, so it refuses
   larger declared lengths up front.
4. `offset + 5 + length > len` -> `etcd: truncated grpc frame at offset N`.
5. otherwise the frame parses; `compressed` keeps the raw flag byte (gRPC
   uses 0/1; any other value is preserved and never interpreted).

`etcd_parse_frame_at` ignores bytes after the frame; the caller advances by
`EtcdFrame.frame_len` / `etcd_frame_consumed(f)`, which makes sequential
frames in one buffer trivial.

## Message tables

Notation: every row is `field number | proto type | decoded as`. "bytes" is
`Vec[UInt8]`, "str" is a validated `Str` (strict UTF-8, NUL rejected),
"has" notes a presence flag for optional fields. All messages are flat
structs; embedded messages are decoded into nested struct fields
(`EtcdHeader`, `EtcdKeyValue`, `EtcdUnknown`), never into `Vec[StructType]`.

### ResponseHeader (`EtcdHeader`)

| # | Type | Decoded as |
|---|---|---|
| 1 | uint64 | `cluster_id` (also sets `present`) |
| 2 | uint64 | `member_id` |
| 3 | int64 | `revision` |
| 4 | uint64 | `raft_term` |

`present` is false when none of the four fields appeared.

### KeyValue (`EtcdKeyValue`)

| # | Type | Decoded as |
|---|---|---|
| 1 | bytes | `key` |
| 2 | int64 | `create_revision` |
| 3 | int64 | `mod_revision` |
| 4 | int64 | `version` |
| 5 | bytes | `value` |
| 6 | int64 | `lease` |

### RangeRequest (`EtcdRangeRequest`)

| # | Type | Decoded as |
|---|---|---|
| 1 | bytes | `key` |
| 2 | bytes | `range_end` |
| 3 | int64 | `limit` |
| 4 | int64 | `revision` |
| 5 | SortOrder | `sort_order` (NONE 0, ASCEND 1, DESCEND 2) |
| 6 | SortTarget | `sort_target` (KEY 0, VERSION 1, CREATE 2, MOD 3, VALUE 4) |
| 7 | bool | `serializable` |
| 8 | bool | `keys_only` |
| 9 | bool | `count_only` |
| 10 | int64 | `min_mod_revision` |
| 11 | int64 | `max_mod_revision` |
| 12 | int64 | `min_create_revision` |
| 13 | int64 | `max_create_revision` |

### RangeResponse (`EtcdRangeResponse`)

| # | Type | Decoded as |
|---|---|---|
| 1 | ResponseHeader | `header` |
| 2 | repeated KeyValue | `kvs` (flat list, see below) |
| 3 | bool | `more` |
| 4 | int64 | `count` |

### PutRequest (`EtcdPutRequest`)

| # | Type | Decoded as |
|---|---|---|
| 1 | bytes | `key` |
| 2 | bytes | `value` |
| 3 | int64 | `lease` |
| 4 | bool | `prev_kv` |
| 5 | bool | `ignore_value` |
| 6 | bool | `ignore_lease` |

### PutResponse (`EtcdPutResponse`)

| # | Type | Decoded as |
|---|---|---|
| 1 | ResponseHeader | `header` |
| 2 | KeyValue | `prev_kv` + `has_prev_kv` |

### DeleteRangeRequest (`EtcdDeleteRangeRequest`)

| # | Type | Decoded as |
|---|---|---|
| 1 | bytes | `key` |
| 2 | bytes | `range_end` |
| 3 | bool | `prev_kv` |

### DeleteRangeResponse (`EtcdDeleteRangeResponse`)

| # | Type | Decoded as |
|---|---|---|
| 1 | ResponseHeader | `header` |
| 2 | int64 | `deleted` |
| 3 | repeated KeyValue | `prev_kvs` (flat list) |

### Compare (`EtcdCompare` / `EtcdCompareList`)

| # | Type | Decoded as |
|---|---|---|
| 1 | CompareResult | `result` (EQUAL 0, GREATER 1, LESS 2, NOT_EQUAL 3) |
| 2 | CompareTarget | `target` (VERSION 0, CREATE 1, MOD 2, VALUE 3, LEASE 4) |
| 3 | bytes | `key` |
| 4 | int64 | `version` (union; sets `union_field = 4`) |
| 5 | int64 | `create_revision` (union; 5) |
| 6 | int64 | `mod_revision` (union; 6) |
| 7 | bytes | `value` (union; 7) |
| 8 | int64 | `lease` (union; 8) |

### TxnRequest (`EtcdTxnRequest`)

| # | Type | Decoded as |
|---|---|---|
| 1 | repeated Compare | `compares` (flat list) |
| 2 | repeated RequestOp | `success` (op list) |
| 3 | repeated RequestOp | `failure` (op list) |

### TxnResponse (`EtcdTxnResponse`)

| # | Type | Decoded as |
|---|---|---|
| 1 | ResponseHeader | `header` |
| 2 | bool | `succeeded` |
| 3 | repeated ResponseOp | `responses` (op list) |

### RequestOp / ResponseOp (`EtcdOp` / `EtcdOpList`)

A body with at most one of the one-of fields; the last one on the wire wins.

| # | Type | Kind |
|---|---|---|
| 1 | RangeRequest / RangeResponse | 1 |
| 2 | PutRequest / PutResponse | 2 |
| 3 | DeleteRangeRequest / DeleteRangeResponse | 3 |
| 4 | TxnRequest / TxnResponse | 4 |

The nested body is preserved raw in `EtcdOpList.raws[i]`; re-decode it with
the matching body parser (`etcd_parse_range_request_body(&raw, 0,
raw.len(), 1)`, and so on). Kind 0 means no branch was present (an empty
op is legal on the wire). `etcd_op_name` renders RANGE/PUT/DELETE_RANGE/TXN.

### CompactionRequest (`EtcdCompactionRequest`)

| # | Type | Decoded as |
|---|---|---|
| 1 | int64 | `revision` |
| 2 | bool | `physical` |

`CompactionResponse` has only field 1 `header` and decodes to `EtcdHeader`
through `etcd_decode_compaction_response`.

### WatchRequest (`EtcdWatchRequest`)

`kind` is the request_union discriminator: 1 create, 2 cancel, 3 progress,
0 none. A later branch replaces an earlier discriminator; create fields
already decoded stay.

WatchCreateRequest (kind 1):

| # | Type | Decoded as |
|---|---|---|
| 1 | bytes | `key` |
| 2 | bytes | `range_end` |
| 3 | int64 | `start_revision` |
| 4 | bool | `progress_notify` |
| 5 | repeated FilterType | `filters` (unpacked or packed; NOPUT 0, NODELETE 1) |
| 6 | bool | `prev_kv` |
| 7 | int64 | `watch_id` |
| 8 | bool | `fragment` |

WatchCancelRequest (kind 2): field 1 int64 `watch_id` -> `cancel_watch_id`.
WatchProgressRequest (kind 3): no fields.

### WatchResponse (`EtcdWatchResponse`)

| # | Type | Decoded as |
|---|---|---|
| 1 | ResponseHeader | `header` |
| 2 | int64 | `watch_id` |
| 3 | bool | `created` |
| 4 | bool | `canceled` |
| 5 | int64 | `compact_revision` |
| 6 | string | `cancel_reason` (validated str) |
| 7 | bool | `fragment` |
| 11 | repeated Event | folded into the event vectors |

Event (fields folded per event): 1 EventType `type` (PUT 0, DELETE 1);
2 KeyValue `kv`; 3 KeyValue `prev_kv`. Each event contributes one entry to
15 parallel vectors (`event_types`, `event_kv_present`, `event_kv_keys`,
`event_kv_values`, `event_kv_create_revisions`, `event_kv_mod_revisions`,
`event_kv_versions`, `event_kv_leases`, `event_prev_present`,
`event_prev_keys`, `event_prev_values`, `event_prev_create_revisions`,
`event_prev_mod_revisions`, `event_prev_versions`, `event_prev_leases`);
`etcd_watch_event_get` reassembles one event and `etcd_watch_event_count`
is the entry count.

### Lease messages

| Message | Fields |
|---|---|
| LeaseGrantRequest | 1 int64 `ttl`; 2 int64 `id` |
| LeaseGrantResponse | 1 header; 2 int64 `id`; 3 int64 `ttl`; 4 string `error_text` + `has_error_text` |
| LeaseKeepAliveRequest | 1 int64 `id` |
| LeaseKeepAliveResponse | 1 header; 2 int64 `id`; 3 int64 `ttl` |
| LeaseRevokeRequest | 1 int64 `id` |
| LeaseRevokeResponse | 1 header (decodes to `EtcdHeader`) |
| LeaseTimeToLiveRequest | 1 int64 `id`; 2 bool `keys` |
| LeaseTimeToLiveResponse | 1 header; 2 int64 `id`; 3 int64 `ttl`; 4 int64 `granted_ttl`; 5 repeated bytes `keys` |

### Auth messages

| Message | Fields |
|---|---|
| AuthenticateRequest | 1 string `name`; 2 string `password` |
| AuthenticateResponse | 1 header; 2 string `token` |
| AuthUserAddRequest | 1 string `name`; 2 string `password`; 3 bytes `options_raw` (raw `authpb.UserAddOptions` body) + `has_options`; 4 string `hashed_password` + `has_hashed_password` |
| AuthRoleAddRequest | 1 string `name` |

Noted subset: `authpb.UserAddOptions` and the rest of the authz messages are
not decoded; `options_raw` preserves the raw bytes. `hashedPassword` is
decoded as a plain (validated) string.

### Maintenance messages

| Message | Fields |
|---|---|
| StatusResponse | 1 header; 2 string `version`; 3 int64 `db_size`; 4 uint64 `leader`; 5 uint64 `raft_index`; 6 uint64 `raft_term`; 7 uint64 `db_size_in_use`; 8 bool `is_learner` |
| Member | 1 uint64 `ID`; 2 string `name`; 3 repeated string `peerURLs`; 4 repeated string `clientURLs`; 5 bool `isLearner` |
| MemberListResponse | 1 header; 2 repeated Member `members` |
| AlarmRequest | 1 AlarmType `alarm` (NONE 0, NOSPACE 1, CORRUPT 2); 2 uint64 `member_id`; 3 AlarmAction `action` (GET 0, ACTIVATE 1, DEACTIVATE 2) |
| AlarmMember | 1 uint64 `member_id`; 2 AlarmType `alarm` |
| AlarmResponse | 1 header; 2 repeated AlarmMember (parallel `member_ids`/`alarms`) |
| DefragmentResponse | 1 header (decodes to `EtcdHeader`) |
| HashResponse | 1 header; 2 uint32 `hash` |
| HashKVResponse | 1 header; 2 uint64 `hash`; 3 int64 `compact_revision`; 4 uint64 `hash_revision` |
| SnapshotResponse | 1 header; 2 uint64 `remaining_bytes`; 3 bytes `blob` |

MemberList modelling: `EtcdMemberList` keeps `ids`, `names` (validated
UTF-8 bytes), `learners`, and per-member URL runs delimited by
`peer_offsets`/`client_offsets`. The decoders close each run, so
`offsets.len() == member count + 1` and `peer_urls` between
`offsets[i]` and `offsets[i+1]` are member `i`'s URLs. Member-level unknown
fields are skipped with bounds checks but not retained (the enclosing
response keeps its own `unknown`); this is the one place the raw
preservation policy is relaxed, and it is stated here explicitly.

## List and one-of modelling

`Vec[StructType]` is unsupported on v0.61.3, so every repeated message
field is decoded into parallel vectors that are pushed together and never
drift:

| List | Vectors |
|---|---|
| KeyValue list (`EtcdKvList`) | `keys`, `values`, `create_revisions`, `mod_revisions`, `versions`, `leases` |
| Compare list (`EtcdCompareList`) | `results`, `targets`, `keys`, `union_fields`, `versions`, `create_revisions`, `mod_revisions`, `values`, `leases` |
| Op list (`EtcdOpList`) | `kinds`, `raws` |
| Watch events | the 15 vectors above |
| Member list | `ids`, `names`, `learners`, URL runs + offsets |
| Alarm list | `member_ids`, `alarms` |

`*_get` accessors guard every mirrored read and return defaults when an
index is out of range or a mirror is short, so a malformed input cannot
drive an out-of-bounds read; the tests pin the invariants.

## Encoders

`etcd_encode_varint` writes a non-negative `Int` (`etcd: negative varint
value` otherwise). `etcd_encode_key` validates the field number and wire
type. `etcd_encode_frame(message, compressed)` writes the flag byte, the
u32 BE length and the message; the caller is responsible for staying under
the 8 MiB codec cap (documented, not enforced on the encode side, matching
the decode-side guard).

## Deviations from the port brief (recorded)

- The brief listed `AlarmRequest.action` as `GET/PUT/DEACTIVATE`. The
  canonical `rpc.proto` enum is `GET = 0, ACTIVATE = 1, DEACTIVATE = 2`;
  this package follows the canonical values (`etcd_alarm_action_activate`),
  and `etcd_alarm_action_name` renders `ACTIVATE`.
- The brief listed `HashResponse (hash, compact_revision)`. In the canonical
  `rpc.proto`, `HashResponse` carries only `hash` (uint32) while
  `HashKVResponse` carries `hash`, `compact_revision` and `hash_revision`.
  This package implements both messages with their real shapes.
- The brief's `WatchRequest` one-of mentions create/cancel; the canonical
  third branch `progress_request` (field 3) is recognized as kind 3 with no
  fields and is otherwise preserved raw. Likewise `WatchResponse` field 11
  carries the events.
- The brief's `TxnResponse` "responses: one-of range/put/delete/txn" matches
  the op list modelling above (kind 1..4, raw body preserved).
- `Snapshot` is modelled as `SnapshotResponse` (header, remaining_bytes,
  blob); `SnapshotRequest` is empty and has no dedicated decoder.

## Error catalog

Both `N` and `P` are absolute byte offsets in the buffer handed to the
function that failed. `N` always means "the first byte that was required
and is missing" (the buffer end for the outermost call); `P` means the
offset of the offending field/value/key; `Q` means the offset of the
offending string or UTF-8 byte.

| Error | Raised by |
|---|---|
| `etcd: field number 0 at offset P` | field walkers |
| `etcd: truncated field at offset N` | field walkers |
| `etcd: field crosses message boundary at offset P` | field walkers |
| `etcd: unsupported wire type W at offset P` | field walkers, skip |
| `etcd: varint out of bounds at offset P` | varint readers |
| `etcd: truncated varint at offset N` | varint readers |
| `etcd: varint too long at offset P` | varint readers |
| `etcd: varint overflows 64 bits at offset P` | varint readers |
| `etcd: varint exceeds signed 64-bit range at offset P` | u64 reader |
| `etcd: varint exceeds u32 at offset P` | u32 reader |
| `etcd: truncated fixed32 at offset N` | fixed32 reader, skip |
| `etcd: truncated fixed64 at offset N` | fixed64 reader, skip |
| `etcd: fixed64 exceeds signed 64-bit range at offset P` | fixed64 reader |
| `etcd: truncated length-delimited field at offset N` | delimited reader |
| `etcd: packed run crosses boundary at offset P` | packed reader |
| `etcd: packed run too large at offset S` | packed reader |
| `etcd: string contains nul at offset Q` | string/UTF-8 decode |
| `etcd: invalid utf-8 at offset Q` | string decode |
| `etcd: nesting depth exceeds limit of 16 at offset P` | nested decoders |
| `etcd: bad message range at offset P` | body decoders |
| `etcd: list too large at offset P` | repeated-list accumulation |
| `etcd: negative frame offset` | frame parse |
| `etcd: truncated grpc frame header at offset N` | frame parse |
| `etcd: grpc message exceeds 8 MiB at offset P` | frame parse |
| `etcd: truncated grpc frame at offset N` | frame parse |
| `etcd: negative varint value` | varint encoder |
| `etcd: bad field number` / `etcd: bad wire type` | key encoder |

Limits: `etcd_max_varint_bytes()` = 10, `etcd_max_depth()` = 16,
`etcd_max_list_entries()` = `etcd_max_packed_entries()` = 65536,
`etcd_max_message_bytes()` = 8388608.

## Test coverage

`tests/test_conformance.xi` (26 checks, all green) covers: varint
boundaries (`0`, `127`, `128`, `16383`, `16384`, `2^32-1`, `2^63-1`) and
every varint error; u32/i32/i64 readers including sign-extended `-1`;
fixed32/fixed64; field keys; length-delimited values; unknown-field skip;
packed runs; the gRPC frame (layout, flag preservation, consumed counts,
sequential parsing, encode round trip, every malformed length and the 8 MiB
guard); ResponseHeader and KeyValue; RangeRequest (all 13 fields, enums,
defaults, names, a negative int64 revision bound); RangeResponse with two
kvs; PutRequest/PutResponse and DeleteRange request/response;
Compare/TxnRequest with a value and a version union plus raw op re-decode;
TxnResponse one-of dispatch; WatchRequest create (unpacked + packed
filters), cancel and progress; WatchResponse with PUT and DELETE events and
prev_kv; the Lease set; the Auth set; StatusResponse and
MemberListResponse URL runs; Alarm, Hash, HashKV, Snapshot, Compaction and
Defragment; unknown-field raw preservation; malformed input with exact
byte-offset errors (field 0, truncation, boundary crossing, wire type 3,
NUL, invalid UTF-8, bad range, depth cap); defaults and constructors; the
name/constant tables; and encoder validation.
