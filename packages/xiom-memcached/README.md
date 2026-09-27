# xiom.memcached

Pure-XIOM **memcached protocol codec** covering both the classic text protocol
and the (modern) binary protocol. Encoding and decoding only: the package
never opens a socket, keeps no session state and performs no connection
management. Feed it bytes, get structured values back.

- **Package:** `xiom.memcached` (module `xiom.memcached`)
- **Version:** 0.1.0
- **Dependency:** `xiom.std` only (uses `xiom.string`, `xiom.string.builder`,
  `xiom.string.compare`; tests use `xiom.test`, `xiom.io`,
  `xiom.encoding.hex`)
- **Conformance:** `tests/test_conformance.xi` -- 22 checks

## Scope

Text protocol:

| Direction | Covered |
|-----------|---------|
| Request encode | `set`, `add`, `replace`, `append`, `prepend`, `cas`, `get`, `gets`, `delete`, `incr`, `decr`, `touch`, `stats`, `flush_all`, `version`, `quit` |
| Request parse | all of the above, with consumed-byte counts and binary-safe data blocks |
| Response parse | `STORED`, `NOT_STORED`, `EXISTS`, `NOT_FOUND`, `DELETED`, `TOUCHED`, `OK`, `ERROR`, `CLIENT_ERROR`, `SERVER_ERROR`, `VERSION`, `END`, and full `VALUE ... / END` retrieval responses |

Binary protocol:

| Direction | Covered |
|-----------|---------|
| Request encode | `GET`, `GETK`, `GETKQ`, `SET`, `ADD`, `REPLACE`, `DELETE`, `INCR`, `DECR`, `QUIT`, `FLUSH`, `NOOP`, `VERSION` |
| Response encode | any supported opcode with the status table, including error responses |
| Header/packet parse | 24-byte header and whole packets, with extras-layout validation and consumed-byte counts |
| Extras decode | 8-byte `SET` family (expiration + flags), 20-byte `INCR`/`DECR` (delta + initial + expiration), 4-byte `GET` response flags |

Not covered: sockets/TCP, SASL authentication opcodes, `APPEND`/`PREPEND`/
`STAT`/`GETQ`/`SETQ` and the other binary opcodes outside the table above,
compression/serialization of values (only the flag bits are exposed), URL or
connection-string parsing, and auto-discovery. See `SPEC.md` for exact byte
layouts, limits and the full error catalog.

## Usage

Encode and parse text commands:

```xiom
use xiom.memcached;

let key = bytes_of("user:42");       // your own Str -> bytes helper
let value = bytes_of("Ada");
let req = memcached.text_encode_set(&key, 0, 300, &value, false);
// "set user:42 0 300 3\r\nAda\r\n"

let cmd = memcached.text_parse_command(&buffer, 0);
if cmd.is_ok {
  let c: TextCommand = cmd.value;
  // c.verb, c.keys, c.flags, c.exptime, c.data, c.consumed, ...
}
```

Parse a multi-key retrieval response (binary-safe payloads):

```xiom
let r = memcached.text_parse_get_response(&buffer, 0);
if r.is_ok {
  let resp: TextGetResponse = r.value;
  let n = memcached.text_values_count(&resp);
  let data = memcached.text_value_data(&resp, 0);
  let flags = memcached.text_value_flags(&resp, 0);
  let cas = memcached.text_value_cas(&resp, 0);   // -1 for `get`
}
```

Build binary packets:

```xiom
let setp = memcached.bin_encode_set(&key, &value, 5, 60, 0, 7);   // cas 0
let pkt = memcached.bin_parse_packet(&bytes, 0);
if pkt.is_ok {
  let p: BinPacket = pkt.value;
  // p.opcode, p.status, p.cas, p.extras, p.key, p.value, p.consumed
}
let se = memcached.bin_decode_set_extras(&extras);   // exptime + flags
let de = memcached.bin_decode_delta_extras(&extras); // delta + initial + exptime
```

User flags helpers (memcached flags are opaque to the server; this package
documents the two conventional low bits):

```xiom
let f = memcached.text_flags_pack(user_flags, compressed, serialized);
let compressed = memcached.text_flags_is_compressed(f);  // bit 0x2
let serialized = memcached.text_flags_is_serialized(f);  // bit 0x4
let raw = memcached.text_flags_user(f);                  // clears 0x2|0x4
```

## Errors

Every fallible API returns `Result[T, Str]` with a stable, prefixed message
(`"memcached: ..."`). Parsers reject truncation, non-numeric numeric fields,
over-long keys and data blocks, bad CRLF framing, opcode/extras mismatches
and unrepresentable 64-bit values instead of guessing. See `SPEC.md` for the
complete message catalog.

## Testing

From the repository root:

```powershell
.\scripts\port.ps1 -Package xiom.memcached
```

The suite prints one `[PASS]`/`[FAIL]` line per check and exits non-zero on
any failure.
