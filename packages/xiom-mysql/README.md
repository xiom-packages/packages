# xiom.mysql

> **Status:** IMPLEMENTED -- MySQL client/server wire protocol structure codec.
> **Scope:** packet framing with the multi-packet continuation rule, the
> initial handshake v10, the handshake response 41 and the 32-byte SSL
> request, length-encoded integers/strings, OK/ERR/EOF/LOCAL INFILE, the
> command packets (COM_QUERY, COM_INIT_DB, COM_QUIT, COM_PING,
> COM_STMT_PREPARE), result-set column counts, column definitions and
> text-protocol rows, plus the capability/status/type/charset/command
> tables. No sockets, no TLS, no authentication crypto, no compression, no
> server.
> **Deps:** `xiom.std` only (the library module imports `xiom.string`,
> `xiom.string.builder`, `xiom.string.compare` and `xiom.convert`; the
> tests additionally use `xiom.test`, `xiom.io` and `xiom.encoding.hex`).

## What it is

`xiom.mysql` is a pure-XIOM, dependency-free **structural** codec for the
MySQL client/server wire protocol (MySQL 8.0 / MariaDB compatible framing).
It turns the bytes a transport would carry into typed XIOM values and back:
it never performs I/O, never keeps connection state, and never looks inside
a SQL statement. Callers supply and receive byte vectors.

Implemented layers:

- **Packet framing**: 3-byte little-endian payload length + 1-byte sequence
  id. A declared length of `0xFFFFFF` (16777215) means the message continues
  in the next packet; the message ends at the first packet whose declared
  length is smaller. A message whose length is an exact multiple of
  `0xFFFFFF` is terminated by an empty packet, so the receiver always sees
  an unambiguous end. `mysql_read_packet` reads exactly one packet;
  `mysql_read_message` reassembles a continuation chain.
- **Initial handshake v10**: protocol version 10, server version
  NUL-string, connection id u32, auth-plugin-data part 1 (8 bytes), filler,
  capability lower u16, character set, status flags u16, capability upper
  u16, auth plugin data length, 10 reserved bytes, auth-plugin-data part 2
  and the auth plugin name NUL-string.
- **Handshake response 41**: capability flags u32, max packet u32, charset,
  23-byte filler, username NUL-string, auth response (length-encoded,
  1-byte-length or NUL-string, chosen by capability), database, auth plugin
  name and the connect-attrs block; the 32-byte SSL request variant.
- **Length-encoded values**: first byte < `0xFB` is the value, `0xFB` is
  NULL, `0xFC` a u16, `0xFD` a u24 and `0xFE` a u64; `0xFF` is rejected as
  a lenenc first byte (it is the ERR packet marker). A u64 with bit 63 set
  is rejected as out of range because XIOM `Int` is signed 64-bit.
- **Responses**: OK `0x00` (affected rows, last insert id, status, warnings,
  info), ERR `0xFF` (code, optional `#` + 5-byte SQLSTATE, message),
  EOF `0xFE` (warnings + status; only when the payload is shorter than
  9 bytes) and the LOCAL INFILE `0xFB` marker with its filename.
- **Commands**: `COM_QUERY` `0x03` + SQL, `COM_INIT_DB` `0x02`,
  `COM_QUIT` `0x01`, `COM_PING` `0x0E`, `COM_STMT_PREPARE` `0x16` + SQL,
  plus the full `0x00`..`0x1F` command name table.
- **Result sets**: length-encoded column count, column definition packets
  (six length-encoded strings, `0x0C` filler, charset, column length, type,
  flags, decimals, two filler bytes) and text-protocol row packets
  (length-encoded string cells, `0xFB` NULL).
- **Constant tables**: capability flags (documented subset, bits 0..24),
  status flags, the full column type table `0x00`..`0xFF` and a charset-id
  subset.

Every reader is bounds-checked and reports the **byte offset** of the
failing read. Negative lengths, truncated packets, hostile lengths and
invalid lenenc first bytes are rejected with deterministic messages (see
SPEC.md).

## Quick start

Decode one packet and its OK payload:

```xi
use xiom.mysql;

var r = mysql_reader_new(bytes_from_transport);
let pr = mysql_read_message(&mut r);          // reassembles 0xFFFFFF chains
if pr.is_ok {
  let m: MysqlMessage = pr.value;
  let payload: Vec[UInt8] = mysql_message_payload(&m);
  if mysql_packet_kind(&payload) == mysql_packet_kind_ok() {
    var pr2 = mysql_reader_new(payload);
    let okr = mysql_read_ok(&mut pr2);
    if okr.is_ok {
      let o: MysqlOk = okr.value;
      // mysql_ok_affected_rows(&o), mysql_ok_last_insert_id(&o), ...
    }
  }
}
```

Build a handshake response and frame it:

```xi
use xiom.mysql;

var resp = MysqlHandshakeResponse{
  capability_flags: mysql_capability_protocol_41() + mysql_capability_plugin_auth(),
  max_packet_size: mysql_default_max_packet_size();
  character_set: mysql_charset_utf8mb4_general_ci();
  username: "root";
  auth_response_kind: mysql_auth_response_kind_nul_string();
  auth_response: auth_bytes;
  database: "";
  auth_plugin_name: "caching_sha2_password";
  attr_names: Vec[Str].new();
  attr_values: Vec[Str].new();
};

var body = mysql_writer_new();
let wr = mysql_write_handshake_response(&mut body, &resp);
let payload: Vec[UInt8] = mysql_writer_bytes(&body);

var framed = mysql_writer_new();
let next_seq = mysql_write_message(&mut framed, &payload, 0);
```

Decode a table result set:

```xi
var r = mysql_reader_new(column_payload);
let n = mysql_read_column_count(&mut r);      // lenenc, must be >= 1
// for each column: mysql_read_column_definition(&mut r)
// then per row packet: mysql_read_text_row(&mut r, n)
```

## API map

The module exposes 275 public functions, all prefixed `mysql_`; the
full byte-level tables live in `SPEC.md`.

| Group | Representative functions |
|---|---|
| Framing constants | `mysql_packet_header_len`, `mysql_max_payload_len`, `mysql_default_max_packet_size`, `mysql_sequence_next`, `mysql_packet_is_continuation` |
| Packets / messages | `mysql_read_packet_header`, `mysql_write_packet_header`, `mysql_read_packet`, `mysql_write_packet`, `mysql_read_message`, `mysql_write_message`, accessors |
| Little-endian primitives | `mysql_read_u8`, `mysql_read_u16_le`, `mysql_read_u32_le`, `mysql_read_u64_le`, `mysql_write_u8` ... `mysql_write_u64_le` |
| Raw strings / bytes | `mysql_read_bytes_n`, `mysql_read_nul_str`, `mysql_read_rest_bytes`, `mysql_read_rest_str`, `mysql_write_bytes`, `mysql_write_str`, `mysql_write_nul_str` |
| Length-encoded | `mysql_read_lenenc_int`, `mysql_read_lenenc_int_nullable`, `mysql_read_lenenc_str`, `mysql_read_lenenc_bytes`, `mysql_write_lenenc_int`, `mysql_write_lenenc_null`, `mysql_write_lenenc_str`, `mysql_write_lenenc_bytes` |
| Handshake v10 | `mysql_read_handshake`, `mysql_write_handshake`, `mysql_handshake_*` accessors, `mysql_handshake_auth_plugin_data` |
| Response 41 / SSL | `mysql_read_handshake_response`, `mysql_write_handshake_response`, `mysql_read_ssl_request`, `mysql_write_ssl_request`, `mysql_is_ssl_request_payload`, `mysql_response_*` accessors |
| OK / ERR / EOF | `mysql_read_ok`, `mysql_write_ok`, `mysql_read_err`, `mysql_write_err`, `mysql_read_eof`, `mysql_write_eof`, `mysql_read_local_infile`, `mysql_local_infile_filename` |
| Commands | `mysql_com_*` constants, `mysql_command_known`, `mysql_command_name`, `mysql_read_command`, `mysql_write_com_query`, `mysql_write_com_init_db`, `mysql_write_com_quit`, `mysql_write_com_ping`, `mysql_write_com_stmt_prepare` |
| Result sets | `mysql_read_column_count`, `mysql_read_column_definition`, `mysql_write_column_definition`, `mysql_read_text_row`, `mysql_write_text_row`, `mysql_column_*` / `mysql_text_row_*` accessors |
| Tables | `mysql_capability_*`, `mysql_capabilities_known`, `mysql_status_*`, `mysql_status_flags_known`, `mysql_type_*`, `mysql_type_name`, `mysql_charset_*`, `mysql_packet_kind*`, `mysql_auth_response_kind*` |

Types: `MysqlWriter`, `MysqlReader`, `MysqlLenenc`, `MysqlPacketHeader`,
`MysqlPacket`, `MysqlMessage`, `MysqlHandshake`, `MysqlSslRequest`,
`MysqlHandshakeResponse`, `MysqlOk`, `MysqlErr`, `MysqlEof`,
`MysqlCommand`, `MysqlColumn`, `MysqlTextRow`.

## Error model

Every fallible function returns `Result[T, Str]`; errors are deterministic
strings of the form `mysql: <what> at offset N` (the offset of the read
that failed):

- `mysql: truncated input at offset N` -- a read ran past the end;
- `mysql: unterminated string at offset N` -- a NUL-string had no NUL;
- `mysql: bad length N at offset M` -- a negative/oversized declared length;
- `mysql: invalid length-encoded first byte N at offset M` -- `0xFF` (and,
  for the non-nullable readers, `0xFB` reported as `null ...`);
- `mysql: null length-encoded integer/string at offset N`;
- `mysql: 64-bit length-encoded value out of range at offset N`;
- `mysql: bad column count N ...`, `mysql: bad column definition filler N ...`;
- `mysql: trailing bytes at offset N` (and `trailing bytes in text row ...`);
- `mysql: not an OK/ERR/EOF packet (first byte N) at offset M`;
- `mysql: unsupported protocol version N at offset M`;
- `mysql: bad ssl request length N at offset M` /
  `mysql: ssl request without CLIENT_SSL at offset M`;
- `mysql: handshake response auth kind N does not match capability flags`,
  `mysql: auth response length N exceeds 255`,
  `mysql: connect attrs name/value count mismatch`;
- `mysql: string contains nul` / `mysql: invalid utf-8` for string payloads;
- `mysql: unexpected trailing bytes for command N at offset M`.

## Tests

```
xiom --run tests/test_conformance.xi
```

20 checks, all synthetic buffers built in-test (hex literals plus the
package's own writers); no external data files. Expected: 20 `[PASS]`
lines, then `xiom.mysql: all tests passed`, exit 0. The port harness
reports:

```
port: PASS (passed=20 failed=0 program_exit=0 exit=0)
```

## Boundaries and non-goals

- No transport: bytes in, bytes out. Packet segmentation across transport
  buffers is the caller's job (`mysql_read_packet` consumes exactly one
  packet).
- No authentication crypto: the auth response bytes are carried and never
  checked; scramble/token computation is out of scope.
- **Binary-protocol result rows are out of scope.** `mysql_packet_kind`
  reports the `0x00` marker context-free and `mysql_is_binary_row_header`
  detects it, but the NULL bitmap and the typed values are not decoded. A
  text row whose first cell is empty also starts with `0x00`; the caller
  knows which protocol it asked for (COM_QUERY vs COM_STMT_EXECUTE).
- CLIENT_SESSION_TRACK session-state payloads inside OK packets are not
  decoded: with that flag the info field is a length-encoded string on the
  wire and the trailing state block is left to the caller.
- Strings must be valid UTF-8 and NUL-free (v0.61.3's `sb_to_str` aborts on
  a `0x00`); use the byte readers for arbitrary payloads.
- The capability table is a documented subset (bits 0..24); upper
  capability bits are preserved raw and reported as not known by
  `mysql_capabilities_known`.
- The `0xFE` EOF disambiguation is "payload length < 9 bytes"; a longer
  `0xFE` packet is classified as a length-encoded 8-byte value.
- **Compiler limit (v0.61.3):** a single `Vec` cannot grow past 2^24
  elements in this toolchain (observed: filling 16,777,217 bytes crashes;
  16,777,216 succeeds, and a second live ~16 MiB vector can also exhaust
  the runtime). The conformance suite therefore verifies the `0xFFFFFF`
  continuation rule at the header/boundary level and exercises whole
  messages only at sizes the runtime can hold; a live `max+1` byte
  multi-packet round-trip is not exercised. The split logic itself is
  implemented and documented in SPEC.md.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
