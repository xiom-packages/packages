# xiom.zookeeper -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.zookeeper`, version `0.1.0`).
Module: `src/zookeeper.xi` (`module xiom.zookeeper`, 168 public
functions).
Depends on `xiom.std`. The library module imports `xiom.string`,
`xiom.string.builder`, `xiom.string.compare` and `xiom.convert`; the tests
add `xiom.test`, `xiom.io` and `xiom.encoding.hex`. No FFI.

## Scope

A pure-XIOM implementation of the Apache ZooKeeper **jute** serialized
message structure -- the record layouts a client and server exchange --
with no sessions, no sockets, no framing and no RPC layer:

- jute primitives, all multi-byte integers big-endian: `byte` (int8),
  `bool`, `int` (int32), `long` (int64), `float` (raw 32-bit), `double`
  (raw 64-bit), `buffer` (int32 length + bytes), `ustring` (int32 byte
  length + UTF-8), `vector` (int32 count + elements);
- the connect handshake records `ConnectRequest` and `ConnectResponse`;
- `RequestHeader` (xid + opcode) and `ReplyHeader` (xid + zxid + err);
- the opcode, special-xid, watch-event, watch-state, create-flag and
  error-code tables;
- the common records: `Stat`, `Id`, `ACL` and ACL vectors, watch events,
  create request/response, delete, exists, getData, setData,
  getChildren/getChildren2 request+response, getAcl, setAcl, sync,
  check and auth;
- `zk_parse_one` / `zk_parse_reply`: parse one message from the front of
  a buffer, reporting the consumed byte count, with deterministic
  byte-offset diagnostics for every malformed input.

## Non-goals

- The 4-byte jute packet length prefix and any stream/socket framing;
  the codec operates on complete in-memory message buffers.
- Sessions: no connect/session negotiation logic, reconnect, session
  expiry handling, or `sessionId` bookkeeping beyond the record fields.
- Watch bookkeeping and delivery; only the `watch` flags of requests and
  the notification record are encoded/decoded.
- `multi` transaction bodies (opcode 14 is in the table, its body is
  `unsupported opcode`), quorum/ZAB records, SASL exchanges beyond the
  `AuthPacket` structure.
- A `Float64` convenience layer (no `Int <-> Float64` bitcast in
  v0.61.3); no `Vec[Float64]`.
- Compression and TLS.

## Byte-level format

All multi-byte integers are big-endian, two's complement. Byte offsets
below are relative to the start of the value.

### Primitives

| Type | Width | Encoding |
|---|---|---|
| `byte` | 1 | int8, two's complement |
| `bool` | 1 | `01` true, `00` false; any other byte is rejected on read |
| `int` | 4 | int32, two's complement |
| `long` | 8 | int64, two's complement |
| `float` | 4 | raw IEEE-754 binary32 bits (opaque) |
| `double` | 8 | raw IEEE-754 binary64 bits (opaque) |

`float`/`double` are opaque: v0.61.3 has no `Int <-> Float64` bitcast, so
readers return the raw pattern (`zk_read_float_bits` unsigned
0..4294967295, `zk_read_double_bits` as the signed 64-bit word).

### buffer, ustring, vector

| Type | Layout |
|---|---|
| `buffer` | int32 length, then exactly `length` bytes |
| `ustring` | int32 byte length, then the UTF-8 bytes |
| `vector` | int32 element count, then the elements |

A length/count of **-1 is null** and decodes as an empty value. Any other
negative value is rejected:
`invalid buffer length L`, `invalid string length L`,
`invalid vector count C` (all with the byte offset of the length word).

`ustring` payloads must be valid UTF-8 (strict RFC 3629: overlong forms,
surrogates and truncated sequences are rejected) and must not contain
`0x00` (the v0.61.3 string builder aborts on NUL); a leading byte outside
`0x20..0x7E` is *not* rejected (paths and ids may hold any valid UTF-8).

Vector readers bound the count against the bytes remaining before
iterating: at least 1 byte per scalar element, 4 per ustring, 12 per ACL
(perms int + scheme length + id length). A count above that lower bound
is `oversized vector count C at byte N`. The bound is a lower bound only:
a header inside it can still fail later with `truncated input`.

### ConnectRequest

| Offset | Field | Type | Width |
|---|---|---|---|
| 0 | protocolVersion | int | 4 |
| 4 | lastZxidSeen | long | 8 |
| 12 | timeOut | int | 4 |
| 16 | sessionId | long | 8 |
| 24 | passwd | buffer | 4 + len |
| 28+len | readOnly | bool | 1 |

Total 29 + passwd length bytes; 45 with the 16-byte password ZooKeeper
clients send. `zk_protocol_version()` is 0.

### ConnectResponse

| Offset | Field | Type | Width |
|---|---|---|---|
| 0 | protocolVersion | int | 4 |
| 4 | timeOut | int | 4 |
| 8 | sessionId | long | 8 |
| 16 | passwd | buffer | 4 + len |
| 20+len | readOnly | bool | 1 |

Total 21 + passwd length bytes; 37 with a 16-byte password.

### RequestHeader and ReplyHeader

| Record | Layout | Size |
|---|---|---|
| RequestHeader | xid int + type int | 8 |
| ReplyHeader | xid int + zxid long + err int | 16 |

### Stat (68 bytes)

| Offset | Field | Type |
|---|---|---|
| 0 | czxid | long |
| 8 | mzxid | long |
| 16 | ctime | long |
| 24 | mtime | long |
| 32 | version | int |
| 36 | cversion | int |
| 40 | aversion | int |
| 44 | ephemeralOwner | long |
| 52 | dataLength | int |
| 56 | numChildren | int |
| 60 | pzxid | long |

`zk_stat_wire_size()` returns 68. `zk_stat_zero()` builds the zero value.

### Id, ACL, ACL vector

| Record | Layout |
|---|---|
| `Id` | scheme ustring + id ustring |
| `ACL` | perms int + Id |
| ACL vector | int32 count + that many `ACL` records |

The ACL vector is exposed as the flat `ZkAclVec` (parallel `perms`,
`schemes`, `ids` vectors, one entry per ACL, grown only by
`zk_acl_vec_push`), because v0.61.3 cannot hold a `Vec[ZkAcl]`.

### Watch event (notification body)

| Field | Type |
|---|---|
| type | int |
| state | int |
| path | ustring (a -1 length is the null path) |

`ZkWatchEvent.path_is_null` records the distinction between a null path
and an empty path, which a `Str` cannot represent.

### Request records

| Record | Layout |
|---|---|
| CreateRequest | path ustring + data buffer + acl vector + flags int |
| CreateResponse | path ustring |
| DeleteRequest | path ustring + version int |
| CheckRequest | path ustring + version int |
| ExistsRequest | path ustring + watch bool |
| GetDataRequest | path ustring + watch bool |
| GetChildrenRequest | path ustring + watch bool |
| GetChildren2Request | path ustring + watch bool |
| GetAclRequest | path ustring + watch bool |
| SetDataRequest | path ustring + data buffer + version int |
| SetAclRequest | path ustring + acl vector + version int |
| SyncRequest | path ustring |
| AuthPacket | type int + scheme ustring + auth buffer |

Because the wire shapes are identical, this module uses one record type
per shape: `ZkPathWatchRequest` for EXISTS/GET_DATA/GET_CHILDREN/
GET_CHILDREN2/GET_ACL and `ZkPathVersionRequest` for DELETE/CHECK.
Create flags: `EPHEMERAL` 1, `SEQUENTIAL` 2, combinable
(`zk_create_flag_is_ephemeral` / `..._is_sequential`).

### Response records

| Record | Layout |
|---|---|
| GetChildrenResponse | children vector of ustring + Stat |
| GetDataResponse | data buffer + Stat |
| GetAclResponse | acl vector + Stat |
| Exists/SET_DATA/SET_ACL/CHECK reply | Stat only |
| Create/Create2 reply | path ustring |
| Sync reply | path ustring |
| Error reply | no body (the code is in ReplyHeader.err) |

### parse-one message

`zk_parse_one(data)` reads the 8-byte request header, then the body
selected by the opcode, and returns a `ZkMessage` whose `consumed` is the
total byte count of header + body. `body_kind` names the body that was
parsed (EMPTY, CREATE, DELETE, EXISTS, GET_DATA, SET_DATA, GET_ACL,
SET_ACL, GET_CHILDREN, SYNC, CHECK, AUTH, NOTIFICATION); fields not
relevant to the kind keep their zero value. `zk_parse_one_exact` requires
the whole buffer to be consumed (`trailing data at byte N`).

`zk_parse_reply(data, op)` reads the 16-byte reply header and then the
body implied by the request's opcode:

| Request op | Reply body |
|---|---|
| EXISTS, SET_DATA, SET_ACL | Stat |
| GET_DATA | buffer + Stat |
| GET_CHILDREN, GET_CHILDREN2 | children vector + Stat |
| GET_ACL | acl vector + Stat |
| CREATE, CREATE2, SYNC | path ustring |
| PING, CLOSE, CHECK, DELETE, AUTH, others | none |

A non-zero `ReplyHeader.err` sets `is_error` and consumes only the
16-byte header, matching the ZooKeeper wire behaviour (the server sends
no body on errors).

## Tables

### Opcodes (`type` field / request header)

| Code | Name | Code | Name |
|---|---|---|---|
| -1 | ERROR | 11 | PING |
| 0 | NOTIFICATION | 12 | GET_CHILDREN2 |
| 1 | CREATE | 13 | CHECK |
| 2 | DELETE | 14 | MULTI (body unsupported) |
| 3 | EXISTS | 15 | CREATE2 |
| 4 | GET_DATA | -10 | CREATE_SESSION |
| 5 | SET_DATA | -11 | CLOSE |
| 6 | GET_ACL | 100 | AUTH |
| 7 | SET_ACL | 101 | SET_WATCHES |
| 8 | GET_CHILDREN | | |
| 9 | SYNC | | |

`zk_op_known` accepts the values above; `zk_op_name` maps any other value
to `UNKNOWN`.

### Special xids

| xid | Meaning |
|---|---|
| -1 | notification |
| -2 | ping |
| -4 | auth |
| -8 | set watches |

`zk_xid_name` returns `REQUEST` for any non-negative xid and `UNKNOWN`
for other negatives.

### Watch event types and states

| type | Name | state | Name |
|---|---|---|---|
| -1 | NONE | 0 | DISCONNECTED |
| 1 | NODE_CREATED | 3 | SYNC_CONNECTED |
| 2 | NODE_DELETED | 4 | AUTH_FAILED |
| 3 | NODE_DATA_CHANGED | 5 | CONNECTED_READ_ONLY |
| 4 | NODE_CHILDREN_CHANGED | 6 | SASL_AUTHENTICATED |
| | | -112 | EXPIRED |

### Error codes

The module implements the canonical Apache ZooKeeper client error codes:

| Code | Name | Code | Name |
|---|---|---|---|
| 0 | OK | -101 | NONODE |
| -1 | SYSTEMERROR | -102 | NOAUTH |
| -2 | RUNTIMEINCONSISTENCY | -103 | BADVERSION |
| -3 | DATAINCONSISTENCY | -108 | NOCHILDRENFOREPHEMERALS |
| -4 | CONNECTIONLOSS | -110 | NODEEXISTS |
| -5 | MARSHALLINGERROR | -111 | NOTEMPTY |
| -6 | UNIMPLEMENTED | -112 | SESSIONEXPIRED |
| -7 | OPERATIONTIMEOUT | -113 | INVALIDCALLBACK |
| -8 | BADARGUMENTS | -114 | INVALIDACL |
| -12 | UNKNOWNSESSION | -115 | AUTHFAILED |
| -13 | NEWCONFIGNOQUORUM | -117 | NOTHING |
| -14 | RECONFIGINPROGRESS | -118 | SESSIONMOVED |
| | | -119 | NOTREADONLY |
| | | -120 | EPHEMERALONLOCALSESSION |
| | | -121 | NOWATCHER |
| | | -122 | REQUESTTIMEOUT |
| | | -123 | RECONFIGDISABLED |
| | | -127 | THROTTLEDOP |

## API

All functions are free functions in module `xiom.zookeeper`. The main
groups (168 public functions in total; every function carries a doc
comment with its exact error behaviour and complexity):

```xi
pub type ZkWriter = { data: Vec[UInt8]; }
pub type ZkReader = { data: Vec[UInt8]; pos: Int; }
pub type ZkConnectRequest = { protocol_version: Int; last_zxid_seen: Int; timeout: Int; session_id: Int; passwd: Vec[UInt8]; read_only: Bool; }
pub type ZkConnectResponse = { protocol_version: Int; timeout: Int; session_id: Int; passwd: Vec[UInt8]; read_only: Bool; }
pub type ZkRequestHeader = { xid: Int; op: Int; }
pub type ZkReplyHeader = { xid: Int; zxid: Int; err: Int; }
pub type ZkStat = { czxid: Int; mzxid: Int; ctime: Int; mtime: Int; version: Int; cversion: Int; aversion: Int; ephemeral_owner: Int; data_length: Int; num_children: Int; pzxid: Int; }
pub type ZkId = { scheme: Str; id: Str; }
pub type ZkAcl = { perms: Int; id: ZkId; }
pub type ZkAclVec = { perms: Vec[Int]; schemes: Vec[Str]; ids: Vec[Str]; }
pub type ZkWatchEvent = { event_type: Int; state: Int; path: Str; path_is_null: Bool; }
pub type ZkCreateRequest = { path: Str; data: Vec[UInt8]; acls: ZkAclVec; flags: Int; }
pub type ZkPathWatchRequest = { path: Str; watch: Bool; }
pub type ZkSetDataRequest = { path: Str; data: Vec[UInt8]; version: Int; }
pub type ZkPathVersionRequest = { path: Str; version: Int; }
pub type ZkSetAclRequest = { path: Str; acls: ZkAclVec; version: Int; }
pub type ZkAuthRequest = { auth_type: Int; scheme: Str; auth_data: Vec[UInt8]; }
pub type ZkGetChildrenResponse = { children: Vec[Str]; stat: ZkStat; }
pub type ZkGetDataResponse = { data: Vec[UInt8]; stat: ZkStat; }
pub type ZkGetAclResponse = { acls: ZkAclVec; stat: ZkStat; }
pub type ZkMessage = { xid: Int; op: Int; body_kind: Int; consumed: Int; path: Str; path_is_null: Bool; version: Int; watch: Bool; flags: Int; data: Vec[UInt8]; acls: ZkAclVec; event_type: Int; state: Int; auth_type: Int; auth_scheme: Str; auth_data: Vec[UInt8]; }
pub type ZkReply = { xid: Int; zxid: Int; err: Int; is_error: Bool; body_kind: Int; consumed: Int; path: Str; data: Vec[UInt8]; stat: ZkStat; children: Vec[Str]; acls: ZkAclVec; }

pub fn zk_writer_new/len/bytes, zk_reader_new/pos/remaining
pub fn zk_write_byte/bool/int/long/float_bits/double_bits, zk_read_*
pub fn zk_write_buffer/null_buffer/ustring/null_ustring/vector_count/vector_null
pub fn zk_read_buffer/ustring/vector_count
pub fn zk_write_ustring_vector, zk_read_ustring_vector
pub fn zk_write_request_header, zk_read_request_header
pub fn zk_write_reply_header, zk_read_reply_header
pub fn zk_write/read_connect_request, zk_encode/decode_connect_request
pub fn zk_write/read_connect_response, zk_encode/decode_connect_response
pub fn zk_stat_zero, zk_write_stat, zk_read_stat, zk_stat_wire_size
pub fn zk_write_id, zk_read_id, zk_write_acl, zk_read_acl
pub fn zk_acl_vec_new/count/push/perms/scheme/id
pub fn zk_write_acl_vector, zk_read_acl_vector
pub fn zk_watch_event_make, zk_write_watch_event, zk_read_watch_event
pub fn zk_write/read_create_request, zk_write_create_response, zk_read_create_response
pub fn zk_write/read_sync_request, zk_write_sync_response, zk_read_sync_response
pub fn zk_write/read_path_watch_request
pub fn zk_write/read_set_data_request
pub fn zk_write/read_path_version_request
pub fn zk_write/read_set_acl_request
pub fn zk_write/read_auth_request
pub fn zk_write/read_get_children_response
pub fn zk_write/read_get_data_response
pub fn zk_write/read_get_acl_response
pub fn zk_parse_one, zk_parse_one_exact, zk_parse_reply, zk_parse_reply_exact
pub fn zk_protocol_version, zk_null_len, zk_body_kind_name
pub fn zk_op_* (20 accessors), zk_op_name, zk_op_known
pub fn zk_xid_* (4 accessors), zk_xid_name, zk_xid_is_special
pub fn zk_event_* (5 accessors), zk_event_name
pub fn zk_state_* (6 accessors), zk_state_name
pub fn zk_err_* (29 accessors), zk_err_name, zk_err_known
pub fn zk_create_flag_ephemeral/sequential/is_ephemeral/is_sequential
```

## Error string catalog

Every diagnostic is `<text> at byte <N>`, where `N` is the offset (from
the start of the buffer handed to the reader) of the length word, the
offending byte, or the first byte of the read that ran past the end.

| Condition | Error text |
|---|---|
| Read past the end of the buffer | `zookeeper: truncated input at byte N` |
| bool byte other than 0 or 1 | `zookeeper: invalid bool byte B at byte N` |
| buffer length < -1 | `zookeeper: invalid buffer length L at byte N` |
| ustring length < -1 | `zookeeper: invalid string length L at byte N` |
| vector count < -1 | `zookeeper: invalid vector count C at byte N` |
| vector count above the lower byte bound | `zookeeper: oversized vector count C at byte N` |
| ustring payload not valid UTF-8 | `zookeeper: invalid utf-8 at byte N` |
| ustring payload containing 0x00 | `zookeeper: string contains nul at byte N` |
| `zk_parse_one` opcode absent/unsupported (MULTI, unknown) | `zookeeper: unsupported opcode N at byte 4` |
| `zk_parse_*_exact` with bytes left after the message | `zookeeper: trailing data at byte N` |
| `zk_decode_connect_request/response` with trailing bytes | `zookeeper: trailing data at byte N` |

Error precedence is the documented read order: a short read is always
reported first, then the value's own validation. Reads leave the cursor
advanced by whatever was consumed successfully; `Err` never carries a
partial value.

## Caveats

- **Error table.** The task brief that requested this package listed
  `CONNECTIONLOSS -103` and `OPERATIONTIMEOUT -108`. In the canonical
  Apache ZooKeeper protocol those codes are `-4` (`CONNECTIONLOSS`) and
  `-7` (`OPERATIONTIMEOUT`), while `-103` is `BADVERSION` and `-108` is
  `NOCHILDRENFOREPHEMERALS`. A decoder that labelled `-103` as
  connection loss would misreport every real server error, so this
  package follows the canonical wire values; all other codes in the
  brief's list (`0`, `-101`, `-110`, `-111`, `-112`, `-113`, `-114`,
  `-115`, `-118`, `-119`, `-102`) match.
- **Null collapse.** A -1 buffer/ustring/vector decodes to an empty
  value; only the watch-event path preserves a null flag. Writers encode
  empty as length 0; an explicit null is available through
  `zk_write_null_buffer`, `zk_write_null_ustring`,
  `zk_write_vector_null` and `ZkWatchEvent.path_is_null`.
- **Vector bounds are lower bounds.** They make hostile counts fail fast
  (no loop over 2^31 elements) but do not pre-validate element size.
- **Strict bool.** Jute's generated readers accept any non-zero byte as
  true; this codec accepts only 0 and 1 and rejects the rest, mirroring
  the sibling `xiom.thrift` codec's strictness. ZooKeeper only emits 0/1.
- **Opaque floats.** `float`/`double` have no value API, only raw bits.
- **`zk_err_known`** compares the rendered name against `UNKNOWN`, so an
  unknown code returns false and `zk_err_name` returns `UNKNOWN`.

## Complexity

| Operation | Complexity |
|---|---|
| Writer/reader lifecycle | O(1) / O(written bytes) |
| Every fixed primitive | O(1) |
| buffer / ustring / vector element | O(payload bytes) |
| Connect records | O(passwd bytes) |
| Stat, Id, ACL, watch event | O(bytes) |
| Request/response records | O(record bytes) |
| `zk_parse_one` / `zk_parse_reply` | O(message bytes) |
| Table lookups (`zk_op_name` etc.) | O(1) |

## Test plan

`tests/test_conformance.xi` (`module zookeeper_tests`, 24 named tests;
the hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line,
and returns the failure count). All buffers are synthetic hex literals
decoded in-test; no external data files. Coverage:

1. int/long exact big-endian bytes and round-trip through the signed
   boundaries (`INT32_MIN/MAX`, `INT64_MIN/MAX`, `-1`, `-2`);
2. byte/bool/float/double raw bits, strict bool rejection (`02`, `FF`),
   truncation;
3. buffer: empty, `00 FF` payload, null, negative lengths, truncation at
   the payload and the length word;
4. ustring: ASCII, `héllo` UTF-8, empty, null, invalid length, invalid
   UTF-8 (`C3 28`), NUL, truncation, 4-byte emoji;
5. vector count and ustring vectors: round-trip, null, invalid count,
   oversized count, truncation;
6. request/reply headers: exact bytes, negative xid/zxid/err,
   truncation at every prefix;
7. ConnectRequest: 45-byte record, round-trip with non-zero/negative
   fields, trailing data, truncation;
8. ConnectResponse: 22-byte record, round-trip, trailing data,
   truncation;
9. opcode accessors/names/known and the four special xids;
10. error-code accessors/names/known;
11. event/state accessors/names, create-flag bit helpers, body-kind
    names;
12. Stat: exact 68-byte layout, accessor round-trip, negative values,
    truncation at byte 60;
13. Id/ACL/ACL vector exact bytes, accessors, out-of-range accessors,
    null vector, invalid count, oversized guard;
14. watch events: round-trip, null path, invalid length, invalid UTF-8;
15. CreateRequest 43-byte record, response path, empty request,
    truncation at byte 39;
16. GetChildrenResponse exact bytes, accessors, truncation offsets;
17. SetData/GetData records and the shared path+watch shape;
18. delete/check path+version, exists path+watch, setAcl, sync;
19. AuthPacket;
20. `zk_parse_one` over every request body with exact consumed counts
    (PING/CLOSE/SET_WATCHES, CREATE, CREATE2, DELETE, EXISTS, GET_DATA,
    SET_DATA, GET_ACL, SET_ACL, GET_CHILDREN, GET_CHILDREN2, SYNC,
    CHECK, AUTH, NOTIFICATION);
21. `zk_parse_one` malformed: truncated header/body, MULTI and unknown
    opcodes, bad bool, negative string/buffer lengths, oversized vector,
    trailing data via `zk_parse_one_exact`;
22. `zk_parse_reply` for every reply shape (Stat, data+Stat,
    children+Stat, acl+Stat, path, error frame, empty);
23. reply exactness/trailing data, truncated Stat and header;
24. reader/writer lifecycle and codec metadata.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.zookeeper
```

Last verified: compiler 0.61.3,
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers `_ok_*` /
  `_err_*` (one pair per result payload type); constructing Results for
  struct payloads inside other functions miscompiles.
- A generic `err_is[T](r: Result[T, Str], want: Str)` helper
  miscompiles in the test harness (it compares unrelated strings), so
  the tests use monomorphic `err_is_*` helpers.
- No `Vec[StructType]` (ACL vectors are parallel columns), no
  `Vec[Float64]`, no `Vec[fn]` dispatch, no lambdas, no methods.
- Every byte read from a `Vec[UInt8]` is widened with `(b as Int) & 0xFF`
  before arithmetic; every Vec element read is bound to an explicitly
  typed local first.
- A `&Vec[...]` argument is always a local: struct fields are copied into
  a local before being passed (passing `&struct.field` yields an empty
  vector on v0.61.3).
- Big-endian encoding uses arithmetic byte extraction; 64-bit decoding
  accumulates 63 bits and applies the sign afterwards, so every pattern
  round-trips without overflow. No bit operators are used.
- `Str` output is materialized with `xiom.string.builder.sb_to_str` only
  after the bytes were validated NUL-free UTF-8.
- The module declares no `extern "C"` blocks (no FFI).
