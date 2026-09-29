# xiom.zookeeper

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.1` on the XIOM registry.
> **Scope:** pure-XIOM codec for the Apache ZooKeeper **jute** wire format:
> big-endian primitives, buffer/ustring/vector framing, the connect
> handshake records, request/reply headers, the opcode/xid tables,
> `Stat`/`Id`/`ACL`/watch events, and the common request and response
> records (create, delete, exists, getData, setData, getChildren, getAcl,
> setAcl, sync, check, auth, notification). No sessions, no sockets, no
> packet framing, no heartbeats, no SASL flow, no multi/transaction
> bodies.
> **Deps:** `xiom.std` only. The library module uses `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare` and `xiom.convert`; the
> tests add `xiom.test`, `xiom.io` and `xiom.encoding.hex`. No FFI.

## What it is

`xiom.zookeeper` encodes and decodes the jute-serialized message
**structure** of the ZooKeeper client/server protocol -- the bytes of one
message, without any network layer:

```
primitives   int 4B, long 8B, byte 1B, bool 1B, float 4B raw,
             double 8B raw (all multi-byte integers big-endian)
buffer       int32 length + bytes; -1 = null
ustring      int32 byte length + UTF-8 bytes; -1 = null
vector       int32 count + elements; -1 = null
records      ordered field sequences (connect, headers, Stat, ACL,
             create/getData/setData/getChildren/... request+response)
```

It also parses one whole message from the front of a buffer:

```xi
let parsed = zk_parse_one(window_bytes);   // header + body by opcode
let m: ZkMessage = parsed.value;
// m.op, m.xid, m.body_kind, m.consumed, m.path, m.data, m.acls, ...
```

`consumed` is the exact byte count of the message, so a stream framer can
advance by it; `zk_parse_one_exact` additionally rejects trailing bytes.
`zk_parse_reply(data, op)` does the same for replies, where the body
shape is selected by the *request's* opcode (replies carry no opcode).

Every reader is bounds-checked and every failure is a deterministic
`zookeeper: ... at byte N` string (see SPEC.md for the catalog). Malformed
input never panics: truncation, negative lengths/counts, bad vectors,
non-0/1 bools, invalid UTF-8 and NUL bytes are all rejected with
byte-offset diagnostics.

`float` and `double` are exposed as raw 32/64-bit bit patterns because
XIOM v0.61.3 has no `Int <-> Float64` bitcast; nothing is guessed about
their value.

## API

| Group | Functions |
|---|---|
| Lifecycle | `zk_writer_new/len/bytes`, `zk_reader_new/pos/remaining` |
| Primitives | `zk_write_byte/bool/int/long/float_bits/double_bits` + `zk_read_*` |
| Framed values | `zk_write_buffer/null_buffer/ustring/null_ustring/vector_count/vector_null`, `zk_write_ustring_vector`, `zk_read_buffer/ustring/vector_count/ustring_vector` |
| Headers | `zk_write_request_header`, `zk_read_request_header`, `zk_write_reply_header`, `zk_read_reply_header` |
| Connect | `zk_write/read_connect_request`, `zk_write/read_connect_response`, `zk_encode/decode_connect_request`, `zk_encode/decode_connect_response` |
| Records | `zk_write/read_stat`, `zk_write/read_id`, `zk_write/read_acl`, `zk_write/read_acl_vector`, `zk_acl_vec_new/count/push/perms/scheme/id`, `zk_write/read_watch_event`, `zk_watch_event_make` |
| Requests | `zk_write/read_create_request`, `zk_write_create_response`, `zk_write/read_sync_request`, `zk_write/read_sync_response`, `zk_write/read_path_watch_request`, `zk_write/read_set_data_request`, `zk_write/read_path_version_request`, `zk_write/read_set_acl_request`, `zk_write/read_auth_request` |
| Responses | `zk_write/read_get_children_response`, `zk_write/read_get_data_response`, `zk_write/read_get_acl_response` |
| Parsing | `zk_parse_one`, `zk_parse_one_exact`, `zk_parse_reply`, `zk_parse_reply_exact` |
| Tables | `zk_op_*`, `zk_xid_*`, `zk_event_*`, `zk_state_*`, `zk_err_*`, `zk_create_flag_*`, `zk_op_name/known`, `zk_xid_name/is_special`, `zk_event_name`, `zk_state_name`, `zk_err_name/known`, `zk_body_kind_name` |

Two request shapes are shared on the wire and therefore share one record:
`ZkPathWatchRequest` (`path`, `watch`) is EXISTS, GET_DATA, GET_CHILDREN,
GET_CHILDREN2 and GET_ACL, and `ZkPathVersionRequest` (`path`, `version`)
is DELETE and CHECK. `GetChildrenResponse` is `children vector + Stat`;
the EXISTS / SET_DATA / SET_ACL / CHECK replies are a bare `Stat`.

## Usage

```xi
use xiom.zookeeper;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // Encode a CreateRequest: path "/app", data "v1", one open ACL,
  // SEQUENTIAL flag.
  var payload = Vec[UInt8].new();
  payload.push(118);   // 'v'
  payload.push(49);    // '1'
  var acls = zk_acl_vec_new();
  zk_acl_vec_push(&mut acls, 31, "world", "anyone");
  let req = ZkCreateRequest{ path: "/app"; data: payload; acls: acls; flags: zk_create_flag_sequential(); };
  var w = zk_writer_new();
  zk_write_request_header(&mut w, 1, zk_op_create());
  zk_write_create_request(&mut w, &req);

  // Parse it back as exactly one message; `consumed` is the frame size.
  let parsed = zk_parse_one_exact(zk_writer_bytes(&w));
  if !parsed.is_ok {
    io.println("error: " + parsed.error);
    return 1;
  }
  let m: ZkMessage = parsed.value;
  io.println("op " + zk_op_name(m.op)
    + " path " + m.path
    + " consumed " + convert.int_to_string(m.consumed));
  return 0;
}
```

The ACL vector is a flat parallel model (`perms`, `schemes`, `ids`
vectors grown only by `zk_acl_vec_push`), because v0.61.3 cannot hold a
`Vec[ZkAcl]`.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.zookeeper
```

Expected: the namespace check passes, 24 `[PASS]` lines, and a final
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`. The suite builds
every buffer in-test from hex literals; no external data files.

## Limitations

- **Structure only.** No packet length prefixes, no TCP/socket layer, no
  session establishment/reconnect, no watch bookkeeping, no SASL, no
  `multi` transaction bodies, no quorum/ZAB records.
- **Strict bool.** Only the bytes 0 and 1 decode; any other byte is
  `zookeeper: invalid bool byte B at byte N` (jute writers emit 0/1).
- **Strings are validated on read.** `ustring` must be valid UTF-8 with
  no 0x00 byte (the v0.61.3 string builder aborts on NUL); use the buffer
  codec for arbitrary bytes.
- **Null is collapsed.** A -1 buffer/ustring/vector decodes as empty; only
  watch-event paths keep a `path_is_null` flag. Writers emit length 0 for
  empty values and have `zk_write_null_*` helpers for -1.
- **Floats/doubles are raw bits.** No `Float64` API; pass/read the 32/64
  bit pattern.
- **Vector counts are bounded by the bytes remaining** (1 byte per scalar
  element, 4 per string, 12 per ACL) as a lower bound; a count within the
  bound may still fail element-by-element with truncation.
- **Error-code caveat.** The package follows the canonical Apache
  ZooKeeper values (`CONNECTIONLOSS` -4, `OPERATIONTIMEOUT` -7,
  `BADVERSION` -103, `NOCHILDRENFOREPHEMERALS` -108). See SPEC.md
  "Caveats" for the note on the task brief's table.
- Writers never fail; readers never panic. Plain value types; not
  thread-safe.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
