# xiom.etcd

> **Status:** `incubating` -- conformance-tested (26/26); published at `v0.1.1` on the XIOM registry.
> **Scope:** pure-XIOM etcd v3 **message-structure codec**: the protobuf-wire
> subset etcd uses, the gRPC frame, and a documented decode/encode subset of
> the `etcdserverpb` messages (Range, Put, DeleteRange, Txn, Watch, Lease,
> Auth, Status, MemberList, Alarm, Compaction, Hash/HashKV, Snapshot).
> No network, no sockets, no cluster, no client state machine, no gRPC
> compression, no auth protocol logic.
> **Deps:** `xiom.std` only. The module imports `xiom.string`,
> `xiom.string.builder` and `xiom.convert`; the tests add `xiom.test`,
> `xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`. No FFI.

## What it is

`xiom.etcd` encodes and decodes the byte-level structures of the etcd v3 gRPC
API (`api/etcdserverpb/rpc.proto`, proto3 wire format) over complete
in-memory buffers. It is the transport-free half of an etcd client: feed it
bytes read from a gRPC stream and it tells you what the server or client
said; hand it bytes and it tells you what to write.

```
frame     1 flag byte | u32 BE message length | message bytes
message   protobuf wire: fields with keys field_number * 8 + wire_type
```

Decoded message subset: `ResponseHeader`, `KeyValue`, `RangeRequest`,
`RangeResponse`, `PutRequest`, `PutResponse`, `DeleteRangeRequest`,
`DeleteRangeResponse`, `Compare`, `TxnRequest`, `TxnResponse`,
`CompactionRequest`/`CompactionResponse`, `WatchRequest` (create/cancel/
progress one-of) and `WatchResponse` with `Event` lists, `LeaseGrantRequest`/
`Response`, `LeaseKeepAliveRequest`/`Response`, `LeaseRevokeRequest`/`Response`,
`LeaseTimeToLiveRequest`/`Response`, `AuthenticateRequest`/`Response`,
`AuthUserAddRequest` (noted subset), `AuthRoleAddRequest` (noted subset),
`StatusResponse`, `MemberListResponse` with `Member` lists, `AlarmRequest`/
`AlarmResponse` with `AlarmMember` lists, `DefragmentResponse`,
`HashResponse`, `HashKVResponse`, `SnapshotResponse`. Unknown fields are
counted and their raw tag+value bytes kept; one-of branches and repeated
messages are stored as raw nested bodies with kind tags and re-decoded on
demand with the exposed body parsers.

## API

Wire primitives (`Result[_, Str]` errors carry byte offsets):

| Function | Returns | Description |
|---|---|---|
| `etcd_read_varint(data, pos)` | `Result[EtcdScalar, Str]` | Base-128 varint, u64 semantics restricted to `2^63 - 1`. |
| `etcd_read_varint_u32(data, pos)` | `Result[EtcdScalar, Str]` | Same, rejects above `2^32 - 1`. |
| `etcd_read_varint_i32(data, pos)` | `Result[EtcdScalar, Str]` | Signed int32 (accepts 10-byte sign-extended values). |
| `etcd_read_varint_i64(data, pos)` | `Result[EtcdScalar, Str]` | Full signed int64 range. |
| `etcd_read_fixed32(data, pos)` / `etcd_read_fixed64(data, pos)` | `Result[EtcdScalar, Str]` | Wire types 5 / 1. |
| `etcd_read_delimited(data, pos)` | `Result[EtcdDelimited, Str]` | Length prefix + payload span. |
| `etcd_skip_field(data, pos, wire_type)` | `Result[EtcdAdvance, Str]` | Bounds-checked unknown-field skip. |
| `etcd_read_packed_varints(data, start, end, out)` | `Result[Int, Str]` | Packed repeated run into `out`. |
| `etcd_key(fn, wt)` / `etcd_key_field_number(key)` / `etcd_key_wire_type(key)` | `Int` | Field-key arithmetic. |

gRPC frame:

| Function | Returns | Description |
|---|---|---|
| `etcd_parse_frame(data)` / `etcd_parse_frame_at(data, offset)` | `Result[EtcdFrame, Str]` | One frame; `frame_len` is the consumed count. |
| `etcd_frame_consumed/compressed/length/message(f)` | `Int` / `Vec[UInt8]` | Frame accessors. |
| `etcd_encode_frame(message, compressed)` | `Vec[UInt8]` | Complete frame with computed length. |

Message decoders (one `etcd_decode_<name>(data)` plus an
`etcd_parse_<name>_body(data, start, end, depth)` for nested spans):

`header`, `key_value`, `range_request`, `range_response`, `put_request`,
`put_response`, `delete_range_request`, `delete_range_response`, `compare`,
`op`, `txn_request`, `txn_response`, `compaction_request`,
`compaction_response` (returns `EtcdHeader`), `event`, `watch_request`,
`watch_response`, `lease_grant_request`, `lease_grant_response`,
`lease_keep_alive_request`, `lease_keep_alive_response`,
`lease_revoke_request`, `lease_revoke_response` (returns `EtcdHeader`),
`lease_time_to_live_request`, `lease_time_to_live_response`,
`authenticate_request`, `authenticate_response`, `user_add_request`,
`role_add_request`, `status_response`, `member_list_response`,
`alarm_request`, `alarm_response`, `alarm_member`, `defragment_response`
(returns `EtcdHeader`), `hash_response`, `hash_kv_response`,
`snapshot_response`.

Accessors (repeated fields and one-of dispatch):

| Function | Returns | Description |
|---|---|---|
| `etcd_unknown_count(u)` / `etcd_unknown_bytes(u)` | `Int` / `Vec[UInt8]` | Unknown-field count and raw bytes. |
| `etcd_header_present/cluster_id/member_id/revision/raft_term(h)` | `Bool` / `Int` | ResponseHeader. |
| `etcd_kv_key/value/create_revision/mod_revision/version/lease(kv)` | `Vec[UInt8]` / `Int` | KeyValue. |
| `etcd_kvlist_count/get/key/value(list, i)` | `Int` / `EtcdKeyValue` / `Vec[UInt8]` | Flat kv list. |
| `etcd_oplist_count/kind/raw(list, i)` + `etcd_op_name(kind)` | `Int` / `Vec[UInt8]` / `Str` | Op one-of dispatch. |
| `etcd_cmp_count/get/result/target/key/union_field(list, i)` | mixed | Compare list. |
| `etcd_watch_filter_count/filter(w, i)` | `Int` | Watch create filters. |
| `etcd_watch_event_count/type/get/kv_key/kv_value/prev_key(wr, i)` | mixed | WatchResponse events. |
| `etcd_ttl_key_count/key(r, i)` | `Int` / `Vec[UInt8]` | LeaseTimeToLive keys. |
| `etcd_member_count/id/name/is_learner/peer_count/peer_url/client_count/client_url(r, i, j)` | mixed | MemberList URL runs. |
| `etcd_alarm_count/alarm(r, i)` | `Int` / `EtcdAlarmMember` | AlarmResponse. |

`unsigned` values are carried as signed `Int`: a u64 field whose wire value
is `>= 2^63` is rejected with a deterministic error instead of truncating.
Encoders (`etcd_encode_varint`, `etcd_encode_key`, `etcd_encode_frame`) exist
for tests, replay and synthetic frames.

`SPEC.md` has the byte tables, the per-message field tables and the full
error catalog.

## Usage

```xi
use xiom.etcd;
use xiom.io;

fn main() -> Int {
  // Bytes read from an etcd gRPC stream.
  // let bytes: Vec[UInt8] = ...;

  // Decode exactly one frame; frame_len is how far to advance the stream.
  // let fr = etcd_parse_frame(&bytes);
  // if !fr.is_ok { io.println(fr.error); return 1; }
  // let f: EtcdFrame = fr.value;

  // The message inside the frame is a RangeResponse (after a Range call):
  // let rr = etcd_parse_range_response_body(&f.message, 0, f.message.len(), 1);
  // if !rr.is_ok { io.println(rr.error); return 1; }
  // let resp: EtcdRangeResponse = rr.value;
  // io.println("count=" + ...);
  // let kv: EtcdKeyValue = etcd_kvlist_get(&resp.kvs, 0);
  // ... etcd_kv_key(&kv), etcd_kv_value(&kv)
  return 0;
}
```

Building a frame by hand (the tests do this too):

```xi
// var msg = Vec[UInt8].new();          // protobuf message bytes
// let frame = etcd_encode_frame(&msg, etcd_grpc_uncompressed());
// let back = etcd_parse_frame(&frame);
```

## Honest boundaries

- No transport: this package never opens a socket and never talks to a
  cluster; it has no request-id correlation, watcher bookkeeping, auth
  token lifecycle, lease refresh loop or retry logic.
- No gRPC compression: the compressed flag byte is preserved
  (`EtcdFrame.compressed`) but never interpreted, so a compressed message
  is returned as opaque bytes.
- XIOM `Int` is signed 64-bit: u64 values `>= 2^63` are rejected by the
  unsigned reader rather than truncated (documented in SPEC.md).
- Messages are capped at 8 MiB (`etcd_max_message_bytes()`) because the
  v0.61.3 runtime aborts on ~16 MiB vectors; repeated lists and packed runs
  are capped at 65536 entries.
- `authpb.Permission`, options payloads and the rest of the authz message
  set are not decoded; `AuthUserAddRequest.options` is preserved raw
  (`options_raw`) and the decoded subset is documented in SPEC.md.
- The codec follows the canonical shapes; where the port brief differed
  (AlarmAction PUT vs ACTIVATE, HashKV compact_revision, Watch progress),
  SPEC.md records the deviation explicitly.

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 26 `[PASS]` lines, then `xiom.etcd: all tests passed`, exit 0.
