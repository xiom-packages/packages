# xiom.mssql

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.1` on the XIOM registry.
> **Scope:** pure-XIOM (no FFI, no sockets, no login crypto) structure codec
> for Microsoft SQL Server's TDS (Tabular Data Stream) wire format: packet
> headers and multi-packet message assembly, the PRELOGIN option table, the
> LOGIN7 fixed layout with its offset/length field table, and RESPONSE token
> streams (LOGINACK, ERROR/INFO, ENVCHANGE, DONE/DONEPROC/DONEINPROC,
> COLMETADATA, ROW, NBCROW, RETURNSTATUS, RETURNVALUE, FEATUREEXTACK,
> ORDER).
> **Deps:** `xiom.std` only. The library module imports `xiom.string` and
> `xiom.string.builder`; the tests add `xiom.test`, `xiom.io`,
> `xiom.string.compare`, `xiom.encoding.hex` and `xiom.convert.int`.

## What it is

`xiom.mssql` is a byte-level *structure* codec. It parses and builds the
framing and metadata layers of TDS so a caller can drive a connection with
any transport it likes (including none at all -- the conformance suite runs
entirely on synthetic buffers). It deliberately does not open sockets and
does not perform login crypto: passwords are preserved exactly as the
obfuscated bytes found on the wire, and TLS/SSPI negotiation is out of
scope.

Four layers are covered:

1. **Packet framing.** `tds_packet_parse` / `tds_packet_build` handle the
   8-byte header (`type`, `status`, big-endian `length`, big-endian `SPID`,
   `packet id`, `window`). `tds_message_pack` splits a payload into packets
   with the EOM bit on the last one; `tds_message_parse` walks and
   concatenates a multi-packet message.
2. **PRELOGIN.** `tds_prelogin_parse` reads the (token, offset u16 BE,
   length u16 BE) option table up to the 0xFF terminator with value
   accessors (`tds_prelogin_value`, `tds_prelogin_version_get`,
   `tds_prelogin_encryption_get`); `tds_prelogin_build_basic` emits the
   canonical six-option payload.
3. **LOGIN7.** `tds_login7_parse` decodes the 94-byte fixed area, every
   offset/length field (hostname, username, raw obfuscated password, app
   name, server name, extension, library, language, database, attached
   database file, change password), the 6-byte client id and the
   SSPI/cbSSPILong block. `tds_login7_build` lays a structure back out with
   two-byte aligned text fields and a four-byte aligned SSPI block.
4. **RESPONSE tokens.** `tds_token_walk` indexes every token (kind, start,
   end) in one pass, parsing COLMETADATA on the way so ROW/NBCROW lengths
   can be measured. Typed decoders exist for LOGINACK, ERROR/INFO,
   ENVCHANGE, DONE/DONEPROC/DONEINPROC, COLMETADATA, ROW, NBCROW,
   RETURNSTATUS, RETURNVALUE, FEATUREEXTACK and ORDER. An unknown token is
   preserved raw: its span runs to the end of the buffer and ends the walk.

Text is decoded with `tds_utf16le_to_str`, which is ASCII-safe by
construction: code units in 0x20..0x7E are kept and every other unit
(including NUL, control characters, non-ASCII and surrogate units) becomes
`?`. Raw byte fields that must not be lossy (password, SSPI, extension
block, ENVCHANGE values, column value spans) are always returned as
`Vec[UInt8]`.

## Usage sketch

```xiom
use xiom.mssql;

// Build a PRELOGIN payload and read it back.
let pr = tds_prelogin_build_basic(16, 0, 2026, 1, TDS_ENCRYPT_ON,
                                  &instopt_bytes, 12345, 1, 0);
if pr.is_ok {
  let payload: Vec[UInt8] = pr.value;
  let back = tds_prelogin_parse(&payload, 0);
  // back.value.tokens / offsets / lengths
}

// Walk a RESPONSE payload and decode each token by offset.
let idx = tds_token_walk(&response_payload, 0);
if idx.is_ok {
  let index: TdsTokenIndex = idx.value;
  var i = 0;
  while i < tds_token_count(&index) {
    let kind: Int = index.kinds[i];
    let off: Int = index.offsets[i];
    if kind == TDS_TOKEN_COLMETADATA {
      let mr = tds_colmetadata_parse(&response_payload, off);
      // mr.value.count / type_tokens / type_sizes / collations ...
    }
    i = i + 1;
  }
}
```

`ROW`/`NBCROW` need their `COLMETADATA`: parse the metadata token first,
then `tds_row_parse(&data, off, &meta)` / `tds_nbcrow_parse(&data, off,
&meta)`, and read values with `tds_row_value` / `tds_row_int` (or the
`value_offsets` / `value_lengths` / `value_ints` / `nulls` vectors
directly).

## Wire scope

| Layer | Covered | Notes |
|---|---|---|
| Packet header | all six packet types, status bits | length/SPID big-endian |
| Message assembly | multi-packet, EOM, packet-id wrap | type must repeat across a message |
| PRELOGIN | 8 option tokens, terminator | VERSION value decoded into 4 fields |
| LOGIN7 | full 94-byte layout + 12 data fields | password bytes preserved, not de-obfuscated |
| COLMETADATA | fixed (INT1, BIT, INT2, INT4, DATETIME4, FLT4, MONEY, DATETIME, FLT8, INT8), nullable-N (INTN, BITN, FLTN, MONEYN, DATETIMEN, GUIDN, DECIMALN, NUMERICN), variable (BIGVARBIN, BIGBINARY, BIGVARCHAR, BIGCHAR, NVARCHAR, NCHAR, XML, UDT, TEXT, IMAGE, NTEXT) | TDS 7.2+ crypto-metadata trailer skipped |
| ROW / NBCROW | fixed, variable, Unicode, XML/UDT and legacy value spans | Unicode lengths count characters (x2 bytes) |
| Tokens | LOGINACK, ERROR/INFO, ENVCHANGE, DONE family, RETURNSTATUS, RETURNVALUE, FEATUREEXTACK, ORDER | unknown token preserved raw |

## Non-goals

- Sockets, transports, reconnection, TLS/SSPI negotiation, login crypto and
  password de-obfuscation, SQL_BATCH/RPC body construction, MARS session
  management, and any semantic interpretation of query results beyond the
  wire representation.
- Character decoding beyond the ASCII-safe helper; collations are exposed
  as packed 5-byte values plus LCID/flags/version/sort-id extractors.

## Error contract

Every decoder returns a stable `Err(Str)` that names the byte offset of the
offending structure, for example
`mssql: truncated packet header at offset 4` or
`mssql: unsupported type token at offset 25`. Encoder-side argument errors
carry no offset (for example `mssql: bad encryption value`). The full
catalog is in SPEC.md.

## MS-TDS alignment notes

TYPE_INFO follows the canonical MS-TDS token values: fixed-length INT1TYPE
0x30, BITTYPE 0x32, INT2TYPE 0x34, INT4TYPE 0x38, DATETIME4TYPE 0x3A,
FLT4TYPE 0x3B, MONEYTYPE 0x3C, DATETIMETYPE 0x3D, FLT8TYPE 0x3E, INT8TYPE
0x7F; nullable INTNTYPE 0x26, BITNTYPE 0x68, FLTNTYPE 0x6D, MONEYNTYPE
0x6E, DATETIMNTYPE 0x6F, DECIMALNTYPE 0x6A, NUMERICNTYPE 0x6C, GUIDNTYPE
0x24; the variable-length family unchanged. A 64-bit integer normally
travels as INTNTYPE with a length-8 size byte (INT8TYPE 0x7F is the legacy
fixed form). GUIDTYPE and GUIDNTYPE share 0x24; the module dispatches it as
the nullable GUIDN form (length byte in metadata and row values) per
MS-TDS. See SPEC.md for the remaining length-semantics notes and
divergences.
