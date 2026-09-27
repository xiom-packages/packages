# xiom.mysql -- byte-level specification

This document describes exactly what `src/mysql.xi` implements: the packet
framing, the handshake structures, the length-encoded value encoding, the
response packets, the command payloads, the result-set structures and the
constant tables, followed by the error catalog and the documented
boundaries. It is the reference for the conformance suite in
`tests/test_conformance.xi`.

Conventions: all multi-byte integers are **little-endian** unless stated
otherwise. "lenenc" = length-encoded. Offsets are zero-based from the start
of the buffer a reader was constructed with; every reader error names the
offset of the failing read. Byte values are shown in hex.

---

## 1. Packet framing

```
+--------+--------+--------+--------+=====================+
| len0   | len1   | len2   | seq    | payload (len bytes) |
+--------+--------+--------+--------+=====================+
  3-byte little-endian payload length   1-byte sequence id
```

- Header size: 4 bytes (`mysql_packet_header_len`).
- Payload length: unsigned 24-bit little-endian, 0..16,777,215
  (`mysql_max_payload_len` = `0xFFFFFF`).
- Sequence id: 1 byte, wraps at 256 (`mysql_sequence_next`), starting at 0
  per command/response exchange.
- Wire size of one packet: `4 + payload_len`.

### 1.1 Multi-packet continuation rule

A packet whose declared payload length is exactly `0xFFFFFF` announces that
the message continues in the next packet. The message ends at the first
packet whose declared length is **smaller** than `0xFFFFFF`. Consequently:

- A message of exactly `k * 0xFFFFFF` bytes (k >= 1) is terminated by an
  **empty packet** (`payload_len = 0`) because otherwise the last data
  packet would be indistinguishable from a continuation.
- `mysql_read_message` concatenates packet payloads until a packet declares
  less than `0xFFFFFF`; `mysql_write_message` splits at `0xFFFFFF` and adds
  the empty terminator when `total % 0xFFFFFF == 0` (including the zero
  length message, which is a single empty packet).
- The empty payload is classified as packet kind `EMPTY` (6).

### 1.2 Packet kinds (context-free)

`mysql_packet_kind(payload)` classifies by the first byte:

| First byte | Length | Kind | Value |
|---|---|---|---|
| (empty) | 0 | `EMPTY` | 6 |
| `0x00` | any | `OK` (or binary row header) | 0 |
| `0xFB` | any | `LOCAL_INFILE` | 1 |
| `0xFE` | < 9 | `EOF` | 2 |
| `0xFE` | >= 9 | `LENENC_8` (8-byte lenenc marker) | 4 |
| `0xFF` | any | `ERR` | 3 |
| other | any | `OTHER` (lenenc count, column def, text row) | 5 |

`mysql_is_binary_row_header(payload)` returns true when the first byte is
`0x00` (detection only; binary rows are out of scope).

---

## 2. Length-encoded values

First byte (n) decides the encoding:

| n | Meaning |
|---|---|
| 0..250 | the value itself |
| `0xFB` | NULL (in text rows and OK contexts); rejected by the non-nullable integer reader and by the string/bytes readers |
| `0xFC` | 2-byte little-endian integer follows |
| `0xFD` | 3-byte little-endian integer follows |
| `0xFE` | 8-byte little-endian integer follows; bit 63 must be 0 (XIOM `Int` is signed 64-bit) |
| `0xFF` | invalid as a lenenc first byte (ERR marker); rejected |

Boundary encodings (used by the tests):

| Value | Bytes |
|---|---|
| 0 | `00` |
| 250 | `fa` |
| 251 | `fc fb 00` |
| 65535 | `fc ff ff` |
| 65536 | `fd 00 00 01` |
| 16777215 | `fd ff ff ff` |
| 16777216 | `fe 00 00 00 01 00 00 00 00` |
| 9223372036854775807 | `fe ff ff ff ff ff ff ff 7f` |

- `mysql_read_lenenc_int_nullable` returns `MysqlLenenc{ is_null; value }`
  and accepts `0xFB`; `mysql_read_lenenc_int` rejects `0xFB` with
  `mysql: null length-encoded integer at offset N`.
- `mysql_read_lenenc_str` validates UTF-8 and rejects NUL bytes;
  `mysql_read_lenenc_bytes` returns raw bytes.
- A declared length larger than the remaining bytes is rejected as
  truncation at the length's start offset; a u64 with bit 63 set is
  rejected as out of range at the marker offset.
- Writers: `mysql_write_lenenc_int` (rejects negative values),
  `mysql_write_lenenc_null` writes `0xFB`, `mysql_write_lenenc_str`
  (rejects NUL), `mysql_write_lenenc_bytes`.

---

## 3. Initial handshake v10

```
offset  size  field
0       1     protocol version (must be 10)
1       var   server version, NUL-terminated UTF-8
..      4     connection id (u32)
..      8     auth-plugin-data part 1
..      1     filler (0x00)
..      2     capability flags, lower 16 bits
..      1     character set id
..      2     status flags
..      2     capability flags, upper 16 bits
..      1     auth plugin data length (total, including part 1)
..      10    reserved (0x00 x 10)
..      var   auth-plugin-data part 2
..      var   auth plugin name, NUL-terminated (only when CLIENT_PLUGIN_AUTH)
```

- `capability_flags = cap_lo + cap_hi * 65536`.
- Part 2 length: `max(13, auth_plugin_data_len - 8)` when
  `CLIENT_PLUGIN_AUTH` is set, otherwise 13 (the legacy value). Part 2 is
  NUL-padded/terminated on the wire; `mysql_handshake_auth_plugin_data`
  concatenates part 1 + part 2 and removes **one** trailing NUL when
  present (the scramble most plugins expect).
- The plugin name is read exactly when `CLIENT_PLUGIN_AUTH` is set; a
  missing NUL is `mysql: unterminated string at offset N`.
- Any protocol version other than 10 is rejected:
  `mysql: unsupported protocol version N at offset 0`.
- Writer `mysql_write_handshake` is byte-exact, requires part 1 to be
  exactly 8 bytes, rejects NUL bytes in the version/plugin strings, rejects
  negative capability flags and rejects a non-10 protocol version.

---

## 4. Handshake response 41 and SSL request

### 4.1 Handshake response 41

```
size  field
4     capability flags (u32)
4     max packet size (u32)
1     character set id
23    filler (0x00 x 23)
var   username, NUL-terminated
var   auth response:
        CLIENT_PLUGIN_AUTH_LENENC_CLIENT_DATA -> lenenc string
        else CLIENT_SECURE_CONNECTION         -> u8 length + bytes
        else                                  -> NUL-terminated string
var   database, NUL-terminated  (only when CLIENT_CONNECT_WITH_DB)
var   auth plugin name, NUL     (only when CLIENT_PLUGIN_AUTH)
var   connect attrs             (only when CLIENT_CONNECT_ATTRS):
        lenenc total length, then repeated (lenenc key, lenenc value)
```

- The auth framing precedence is lenenc over secure over NUL-string.
  `mysql_response_auth_kind` returns `NONE` 0, `NUL_STRING` 1, `SECURE` 2 or
  `LENENC` 3.
- The connect-attrs total length is validated against the remaining bytes;
  a value that overruns is `mysql: bad length N at offset M` (offset of the
  length field). A key/value pair that crosses the declared total is
  `mysql: connect attrs length mismatch at offset M`.
- Trailing bytes after the declared fields are rejected:
  `mysql: trailing bytes at offset N`.
- Writer `mysql_write_handshake_response` enforces the auth kind/capability
  consistency, a secure auth response <= 255 bytes, a NUL-free auth payload
  for the NUL-string variant, NUL-free strings, and parallel attr
  name/value counts.

### 4.2 SSL request

Exactly 32 bytes: capability flags u32, max packet u32, character set u8,
23 filler bytes. It is sent instead of the full response when the client
wants TLS first.

- `mysql_is_ssl_request_payload(payload)` is true when the payload is
  exactly 32 bytes and `CLIENT_SSL` is set.
- `mysql_read_ssl_request` requires exactly 32 remaining bytes and the
  `CLIENT_SSL` bit; otherwise `mysql: bad ssl request length N at offset M`
  or `mysql: ssl request without CLIENT_SSL at offset M`.
- `mysql_write_ssl_request(w, caps, max_packet, charset)` writes the 4+4+1
  fields plus 23 zero bytes (it does not validate the `CLIENT_SSL` bit).

---

## 5. Response packets

### 5.1 OK (`0x00`)

```
0x00
lenenc  affected rows
lenenc  last insert id
u16     status flags
u16     warnings
var     info (rest of the payload, UTF-8, NUL-free)
```

Only the CLIENT_PROTOCOL_41 layout is decoded. With
`CLIENT_SESSION_TRACK` the info field is length-encoded on the wire and a
state block may follow; that variant is documented but not decoded (info is
the raw rest). Writer `mysql_write_ok` rejects negative counters and NUL in
info.

### 5.2 ERR (`0xFF`)

```
0xFF
u16     error code
[ '#', 5 bytes SQLSTATE ]   (present when the byte after the code is '#')
var     message (rest, UTF-8, NUL-free)
```

A `0x23` (`#`) byte at the message position is always treated as the
SQLSTATE marker; a SQLSTATE shorter than 5 bytes is truncation at its
start offset. Pre-4.1 packets without a marker set `has_sqlstate = false`
and `sqlstate = ""`. Writer `mysql_write_err` requires exactly 5 bytes of
SQLSTATE when `has_sqlstate` is set.

### 5.3 EOF (`0xFE`, payload shorter than 9 bytes)

```
0xFE
u16  warnings
u16  status flags
```

Any trailing byte is rejected (`mysql: trailing bytes at offset N`).
`mysql_packet_kind` performs the `< 9` disambiguation; the reader itself
only validates the first byte.

### 5.4 LOCAL INFILE (`0xFB`)

```
0xFB
var  file name (rest of the payload, UTF-8, NUL-free)
```

`mysql_read_local_infile` and `mysql_local_infile_filename` decode it; a
first byte other than `0xFB` is
`mysql: not a LOCAL INFILE packet (first byte N) at offset M`.

---

## 6. Commands

`mysql_read_command` reads one command payload:

| Code | Name | Payload |
|---|---|---|
| `0x00` | COM_SLEEP | none |
| `0x01` | COM_QUIT | none |
| `0x02` | COM_INIT_DB | database (UTF-8 to end) |
| `0x03` | COM_QUERY | SQL (UTF-8 to end) |
| `0x04` | COM_FIELD_LIST | not named; preserved raw |
| `0x05`..`0x15` | CREATE_DB .. REGISTER_SLAVE | preserved raw |
| `0x16` | COM_STMT_PREPARE | SQL (UTF-8 to end) |
| `0x17`..`0x1F` | STMT_EXECUTE .. RESET_CONNECTION | preserved raw |

- For `COM_QUERY`, `COM_INIT_DB` and `COM_STMT_PREPARE` the argument is the
  remaining UTF-8 (NUL-free) text.
- For every other command the payload must be exactly one byte; extra bytes
  are `mysql: unexpected trailing bytes for command N at offset M`.
- Unknown codes (> 0x1F) are preserved in `MysqlCommand.code` with an empty
  arg; `mysql_command_known` is true for 0..31 and `mysql_command_name`
  returns `"UNKNOWN"` outside the table.
- Writers: `mysql_write_com_query`, `mysql_write_com_init_db`,
  `mysql_write_com_quit`, `mysql_write_com_ping`,
  `mysql_write_com_stmt_prepare`.

---

## 7. Result sets

### 7.1 Column count

A single lenenc integer that must be positive (`>= 1`); zero is
`mysql: bad column count 0 at offset N`. Writer `mysql_write_column_count`
rejects non-positive counts.

### 7.2 Column definition (protocol 41)

```
lenenc  catalog
lenenc  schema
lenenc  table
lenenc  org_table
lenenc  name
lenenc  org_name
0x0C    filler (read as a lenenc integer, must equal 12)
u16     character set id
u32     column length
u8      column type
u16     column flags
u8      decimals
2 bytes filler (0x00 0x00)
```

- A filler value other than 12 is
  `mysql: bad column definition filler N at offset M`.
- The six name strings are UTF-8 and NUL-free.
- Trailing bytes after the fixed fields are rejected.
- Writer `mysql_write_column_definition` writes the canonical layout
  (filler 0x0C and two zero bytes) and rejects NUL bytes in the names.

### 7.3 Text-protocol row

For each of `column_count` cells:

- `0xFB` -> NULL (the row's `values[i]` is `""`, `nulls[i]` is true);
- otherwise a lenenc UTF-8 string.

`values` and `nulls` are parallel and always have exactly `column_count`
entries. Trailing bytes after the last cell are
`mysql: trailing bytes in text row at offset N`. A negative count is
`mysql: bad length N at offset 0`. Writer `mysql_write_text_row` requires
parallel vectors of equal length and NUL-free non-NULL cells.

Binary-protocol rows are **not** decoded: the `0x00` row header is reported
by `mysql_packet_kind`/`mysql_is_binary_row_header` only.

---

## 8. Table 1 -- capability flags (documented subset, bits 0..24)

| Constant | Hex | Decimal |
|---|---|---|
| CLIENT_LONG_PASSWORD | `0x00000001` | 1 |
| CLIENT_FOUND_ROWS | `0x00000002` | 2 |
| CLIENT_LONG_FLAG | `0x00000004` | 4 |
| CLIENT_CONNECT_WITH_DB | `0x00000008` | 8 |
| CLIENT_NO_SCHEMA | `0x00000010` | 16 |
| CLIENT_COMPRESS | `0x00000020` | 32 |
| CLIENT_ODBC | `0x00000040` | 64 |
| CLIENT_LOCAL_FILES | `0x00000080` | 128 |
| CLIENT_IGNORE_SPACE | `0x00000100` | 256 |
| CLIENT_PROTOCOL_41 | `0x00000200` | 512 |
| CLIENT_INTERACTIVE | `0x00000400` | 1024 |
| CLIENT_SSL | `0x00000800` | 2048 |
| CLIENT_IGNORE_SIGPIPE | `0x00001000` | 4096 |
| CLIENT_TRANSACTIONS | `0x00002000` | 8192 |
| CLIENT_RESERVED | `0x00004000` | 16384 |
| CLIENT_SECURE_CONNECTION | `0x00008000` | 32768 |
| CLIENT_MULTI_STATEMENTS | `0x00010000` | 65536 |
| CLIENT_MULTI_RESULTS | `0x00020000` | 131072 |
| CLIENT_PS_MULTI_RESULTS | `0x00040000` | 262144 |
| CLIENT_PLUGIN_AUTH | `0x00080000` | 524288 |
| CLIENT_CONNECT_ATTRS | `0x00100000` | 1048576 |
| CLIENT_PLUGIN_AUTH_LENENC_CLIENT_DATA | `0x00200000` | 2097152 |
| CLIENT_CAN_HANDLE_EXPIRED_PASSWORDS | `0x00400000` | 4194304 |
| CLIENT_SESSION_TRACK | `0x00800000` | 8388608 |
| CLIENT_DEPRECATE_EOF | `0x01000000` | 16777216 |

`mysql_capabilities_known(caps)` is true when every set bit is one of these
25 (i.e. `caps & 0x01FFFFFF == caps` and `caps >= 0`). 8.0 extension bits
(`0x02000000` and above) are preserved raw and report false.

## 9. Table 2 -- status flags

| Constant | Hex | Decimal |
|---|---|---|
| SERVER_STATUS_IN_TRANS | `0x0001` | 1 |
| SERVER_STATUS_AUTOCOMMIT | `0x0002` | 2 |
| SERVER_MORE_RESULTS_EXISTS | `0x0008` | 8 |
| SERVER_STATUS_NO_GOOD_INDEX_USED | `0x0010` | 16 |
| SERVER_STATUS_NO_INDEX_USED | `0x0020` | 32 |
| SERVER_STATUS_CURSOR_EXISTS | `0x0040` | 64 |
| SERVER_STATUS_LAST_ROW_SENT | `0x0080` | 128 |
| SERVER_STATUS_DB_DROPPED | `0x0100` | 256 |
| SERVER_STATUS_NO_BACKSLASH_ESCAPES | `0x0200` | 512 |
| SERVER_STATUS_METADATA_CHANGED | `0x0400` | 1024 |
| SERVER_QUERY_WAS_SLOW | `0x0800` | 2048 |
| SERVER_PS_OUT_PARAMS | `0x1000` | 4096 |
| SERVER_STATUS_IN_TRANS_READONLY | `0x2000` | 8192 |
| SERVER_SESSION_STATE_CHANGED | `0x4000` | 16384 |

`mysql_status_flags_known(s)` is true for a non-negative `s` with no bits
outside this table (`0x7FFB`; `0x0004` is undefined).

## 10. Table 3 -- column types (full table)

| Code | Name | Code | Name |
|---|---|---|---|
| `0x00` | DECIMAL | `0xF5` | JSON |
| `0x01` | TINY | `0xF6` | NEWDECIMAL |
| `0x02` | SHORT | `0xF7` | ENUM |
| `0x03` | LONG | `0xF8` | SET |
| `0x04` | FLOAT | `0xF9` | TINY_BLOB |
| `0x05` | DOUBLE | `0xFA` | MEDIUM_BLOB |
| `0x06` | NULL | `0xFB` | LONG_BLOB |
| `0x07` | TIMESTAMP | `0xFC` | BLOB |
| `0x08` | LONGLONG | `0xFD` | VAR_STRING |
| `0x09` | INT24 | `0xFE` | STRING |
| `0x0A` | DATE | `0xFF` | GEOMETRY |
| `0x0B` | TIME | | |
| `0x0C` | DATETIME | | |
| `0x0D` | YEAR | | |
| `0x0E` | NEWDATE | | |
| `0x0F` | VARCHAR | | |
| `0x10` | BIT | | |
| `0x11` | TIMESTAMP2 | | |
| `0x12` | DATETIME2 | | |
| `0x13` | TIME2 | | |
| `0x14` | TYPED_ARRAY | | |

`mysql_type_known` is true for `0x00..0x14` and `0xF5..0xFF`
(32 codes); `0x15..0xF4` are reserved and named `"UNKNOWN"`.

## 11. Charset ids (documented subset)

| Id | Name |
|---|---|
| 1 | big5_chinese_ci |
| 8 | latin1_swedish_ci |
| 28 | gbk_chinese_ci |
| 33 | utf8_general_ci |
| 45 | utf8mb4_general_ci |
| 46 | utf8mb4_bin |
| 63 | binary |
| 224 | utf8mb4_unicode_ci |
| 255 | utf8mb4_0900_ai_ci |

Ids outside the subset return `"UNKNOWN"` from `mysql_charset_name` and
false from `mysql_charset_known`.

---

## 12. Error catalog

All errors are deterministic strings; `N` is a value or count, `M`/`off` a
byte offset.

| Message | Trigger |
|---|---|
| `mysql: truncated input at offset N` | any read past the end |
| `mysql: unterminated string at offset N` | NUL-string without a NUL |
| `mysql: bad length N at offset M` | negative/oversized declared length (connect attrs) |
| `mysql: bad payload length N` | negative packet payload length (writer) |
| `mysql: payload length N exceeds 16777215` | packet payload above the 24-bit maximum |
| `mysql: invalid length-encoded first byte N at offset M` | `0xFF` as lenenc marker |
| `mysql: null length-encoded integer at offset N` | `0xFB` in a non-nullable integer |
| `mysql: null length-encoded string at offset N` | `0xFB` in a string/bytes read |
| `mysql: 64-bit length-encoded value out of range at offset N` | u64 with bit 63 set |
| `mysql: bad length-encoded integer N` | negative writer value |
| `mysql: unsupported protocol version N at offset M` | handshake version != 10 |
| `mysql: bad auth plugin data part 1 length N` | handshake writer with part 1 != 8 bytes |
| `mysql: bad capability flags N` | negative capability flags |
| `mysql: bad ssl request length N at offset M` | SSL request payload != 32 bytes |
| `mysql: ssl request without CLIENT_SSL at offset M` | missing CLIENT_SSL bit |
| `mysql: handshake response auth kind N does not match capability flags` | writer kind vs. capabilities |
| `mysql: auth response length N exceeds 255` | secure auth response too long |
| `mysql: connect attrs length mismatch at offset M` | attrs block larger than declared total |
| `mysql: trailing bytes at offset N` | extra bytes after a fixed structure |
| `mysql: not an OK packet (first byte N) at offset M` | OK reader on another first byte |
| `mysql: not an ERR packet (first byte N) at offset M` | ERR reader on another first byte |
| `mysql: not an EOF packet (first byte N) at offset M` | EOF reader on another first byte |
| `mysql: not a LOCAL INFILE packet (first byte N) at offset M` | non-`0xFB` payload |
| `mysql: bad column count N at offset M` | column count <= 0 |
| `mysql: bad column definition filler N at offset M` | filler != 12 |
| `mysql: trailing bytes in text row at offset N` | extra bytes after the last cell |
| `mysql: text row cell count mismatch` | writer vectors not parallel |
| `mysql: bad sqlstate length N` | ERR writer with SQLSTATE != 5 bytes |
| `mysql: unexpected trailing bytes for command N at offset M` | argless command with extra bytes |
| `mysql: string contains nul` | NUL byte in a string payload/field |
| `mysql: invalid utf-8` | malformed UTF-8 in a string payload |

---

## 13. Documented boundaries

- No transport, TLS, DNS or connection state.
- No authentication crypto: auth bytes are carried, never computed.
- No compression (the flag is a capability bit only).
- Binary-protocol rows and COM_STMT_EXECUTE bodies are out of scope;
  `0x00` detection only (see section 1.2).
- CLIENT_SESSION_TRACK OK-packet state blocks are not decoded.
- Strings must be valid UTF-8 and NUL-free because v0.61.3's `sb_to_str`
  aborts on a `0x00`; byte readers exist for arbitrary payloads.
- Lengths are signed 64-bit `Int`; lenenc u64 values with bit 63 set are
  rejected.
- **Compiler limit:** in compiler v0.61.3 a single `Vec` cannot grow past
  2^24 (16,777,216) elements -- filling 16,777,217 bytes crashes, and two
  simultaneously live ~16 MiB vectors can also exhaust the runtime. The
  conformance suite therefore exercises the `0xFFFFFF` continuation rule
  with header-level boundary checks and whole messages of runtime-safe
  sizes rather than a live `max + 1` payload. The split/terminator logic is
  implemented as specified in section 1.1.
