# xiom.nats

> **Status:** `incubating` -- conformance-tested (21/21); published at `v0.1.2` on the XIOM registry.

Pure-XIOM codec for the NATS 1.x text protocol as spoken by clients and
servers on the wire. No FFI, no sockets, no runtime: it encodes and parses the
bytes, and the caller owns the transport.

- **Package:** `xiom.nats` 0.1.0
- **Module:** `xiom.nats` (single module)
- **Deps:** `xiom.std` (stdlib platform dependency) only
- **Tests:** `tests/test_conformance.xi`, 21 checks

## Scope

| Direction | Ops |
|-----------|-----|
| client -> server | `CONNECT`, `PUB`, `HPUB`, `SUB`, `UNSUB`, `PING`, `PONG` |
| server -> client | `INFO`, `MSG`, `HMSG`, `+OK`, `-ERR`, `PING`, `PONG` |

Everything is CRLF-framed. `PUB`/`HPUB`/`MSG`/`HMSG` carry a decimal byte count
in the control line; the payload is copied out verbatim by that count, so
payloads may contain embedded NULs, CR, LF and any byte >= 128. Payloads stay
`Vec[UInt8]` end to end and are never converted to `Str`. `HPUB`/`HMSG` carry a
`NATS/1.0` header block followed by the payload.

## Quick start

```xiom
use xiom.nats;

// Parse one op out of a receive buffer (consumed says where the next one starts).
let r = nats_parse_op(&buffer, 0);
match r {
  Ok(op) => {
    if op.kind == nats_kind_msg() {
      // op.subject, op.sid, op.reply, op.payload are ready to use
    }
    // next op begins at op.consumed
  },
  Err(e) => { /* "nats: bad size at 0" */ },
}
```

```xiom
// Encode a client publish with a reply-to subject.
let empty = Vec[UInt8].new();
let e = nats_encode_pub(&subject, &reply, &payload);   // PUB <subj> <reply> <n>\r\n<bytes>\r\n
let p = nats_encode_ping();                            // PING\r\n
let s = nats_encode_sub(&filter, &queue, 42);          // SUB <filter> <queue> 42\r\n
```

## API

Encoders (all return `Result[Vec[UInt8], Str]`, except the fixed ops):

| Function | Wire form |
|----------|-----------|
| `nats_encode_connect(json)` | `CONNECT <json>\r\n` |
| `nats_encode_info(json)` | `INFO <json>\r\n` |
| `nats_encode_pub(subject, reply, payload)` | `PUB <subject> [reply] <n>\r\n<payload>\r\n` |
| `nats_encode_hpub(subject, reply, headers, payload)` | `HPUB ... <hsize> <tsize>\r\n<headers><payload>\r\n` |
| `nats_encode_sub(subject, queue, sid)` | `SUB <subject> [queue] <sid>\r\n` |
| `nats_encode_unsub(sid, max_msgs)` | `UNSUB <sid> [max_msgs]\r\n` |
| `nats_encode_msg(subject, sid, reply, payload)` | `MSG <subject> <sid> [reply] <n>\r\n<payload>\r\n` |
| `nats_encode_hmsg(subject, sid, reply, headers, payload)` | `HMSG ... <hsize> <tsize>\r\n<headers><payload>\r\n` |
| `nats_encode_err(message)` | `-ERR <message>\r\n` |
| `nats_encode_ok()` / `nats_encode_ping()` / `nats_encode_pong()` | `+OK`/`PING`/`PONG` + CRLF |

Parser:

| Function | Purpose |
|----------|---------|
| `nats_parse_op(data, off)` | Parse exactly one op at `off`; `Ok(op)` where `op.consumed` is the byte count to advance. |

Subjects:

| Function | Purpose |
|----------|---------|
| `nats_subject_is_valid(filter)` | structural filter check (`*`/`>` allowed) |
| `nats_publish_subject_is_valid(subject)` | literal subject check (no wildcards) |
| `nats_subject_matches(filter, subject)` | NATS wildcard match of a filter against a literal subject |

JSON lookup helpers (INFO/CONNECT subset, not a JSON parser):

| Function | Purpose |
|----------|---------|
| `nats_json_has(text, key)` | true when a scalar top-level member exists |
| `nats_json_str(text, key)` | raw string value bytes (no unescaping) |
| `nats_json_int(text, key)` | integer value |
| `nats_json_bool(text, key)` | boolean value |

Metadata: `nats_kind_*()` (kind ids), `nats_kind_name(kind)`,
`nats_is_client_kind(kind)`, `nats_is_server_kind(kind)`,
`nats_max_control_line()` (4096, CRLF included),
`nats_max_payload_size()` (2147483647).

## Error model

Every parse failure is `Err(Str)` and carries the op start offset:
`"nats: bad size at 0"`, `"nats: truncated payload at 12"`,
`"nats: unknown op at 3"`, ... Encoder failures are plain
`"nats: bad subject"`, `"nats: bad headers"`, ... The full catalog is pinned in
`SPEC.md`.

## Documented limitations

- No sockets, TLS, reconnect logic, auth or session state (crlf codec only).
- `CONNECT`/`INFO` JSON is carried as raw bytes and only shape-checked
  (`{...}`, no control bytes); the key lookups are a small subset (scalar
  top-level members, no unescaping, no composites).
- Subjects are validated structurally at the byte level (no UTF-8 validation).
- Payload counts are capped at 2147483647 bytes.

See `SPEC.md` for the byte-exact grammar, the framing rules and the complete
error catalog.

## Testing

From the repository root:

```powershell
.\scripts\port.ps1 -Package xiom.nats
```

Expected tail: `port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.
