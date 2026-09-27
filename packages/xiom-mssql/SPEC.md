# xiom.mssql -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3;
20/20 conformance checks; not published).
Manifest: `package.xi` (`xiom.mssql`, version `0.1.0`).
Module: `src/mssql.xi` (`module xiom.mssql`).
Depends on `xiom.std`; the library module imports `xiom.string` and
`xiom.string.builder` (the tests add `xiom.test`, `xiom.io`,
`xiom.string.compare`, `xiom.encoding.hex` and `xiom.convert.int`).

## Scope

A pure-XIOM (no FFI, no sockets) codec for the structural layers of TDS:

- the 8-byte packet header, single packets and multi-packet message
  assembly/splitting;
- the PRELOGIN option table and the canonical VERSION/ENCRYPTION values;
- the LOGIN7 fixed layout, offset/length field table, raw obfuscated
  password bytes, client id, SSPI (short and long form) and feature
  extension block;
- a token walker and typed decoders for the RESPONSE token stream:
  LOGINACK (0xAD), ERROR (0xAA), INFO (0xAB), ENVCHANGE (0xE3), DONE
  (0xFD), DONEPROC (0xFE), DONEINPROC (0xFF), COLMETADATA (0x81), ROW
  (0xD1), NBCROW (0xD2), RETURNSTATUS (0x79), RETURNVALUE (0xAC),
  FEATUREEXTACK (0xAE), ORDER (0xA9);
- an ASCII-safe UTF-16LE helper;
- deterministic `Err(Str)` messages naming the byte offset of the
  offending structure for every malformed input and every invalid encoder
  argument.

## Non-goals

- Sockets, transports, retries, session state, MARS, TLS/SSPI negotiation,
  login crypto, password de-obfuscation;
- SQL_BATCH (0x01) and RPC (0x03) request bodies; only their framing is
  covered (packet types are recognized and assemblable);
- table-valued parameters, TVP rows, bulk load payload semantics, query
  result interpretation, collation-aware text conversion;
- any semantic layer above the wire format.

## Byte-level layout

### Packet header (8 bytes)

| Offset | Size | Field | Encoding |
|---|---|---|---|
| 0 | 1 | Type | SQL_BATCH 0x01, RPC 0x03, RESPONSE 0x04, LOGIN7 0x10, SSPI 0x11, PRELOGIN 0x12 |
| 1 | 1 | Status | EOM 0x01, IGNORE 0x02, RESETCONNECTION 0x08 |
| 2 | 2 | Length | **big-endian**, header included (>= 8) |
| 4 | 2 | SPID | **big-endian** |
| 6 | 1 | PacketID | incremented per packet, wraps at 255 in the packer |
| 7 | 1 | Window | 0 |

`tds_packet_parse(data, off)` validates length >= 8 and header + payload
inside the buffer. `tds_packet_build` recomputes the length. The builder
masks `pkt_type`/`status`/`packet_id`/`window` to their low byte and SPID
to its low two bytes.

Multi-packet rules (`tds_message_pack` / `tds_message_parse`):
`packet_size` must be in 8..65535; each packet carries at most
`packet_size - 8` payload bytes; packet ids start at 1 and wrap at 255;
only the final packet has EOM. Parsing walks from `off` until the packet
whose status has EOM, concatenating payloads; a mid-message packet whose
type differs from the first is `mssql: packet type mismatch`; a buffer that
runs out before EOM is `mssql: message missing eom`.

### PRELOGIN

Option table entry (5 bytes each, repeated until 0xFF):

| Size | Field | Encoding |
|---|---|---|
| 1 | Token | VERSION 0x00, ENCRYPTION 0x01, INSTOPT 0x02, THREADID 0x03, MARS 0x04, TRACEID 0x05, FEDAUTHREQUIRED 0x06, NONCEOPT 0x07, TERMINATOR 0xFF |
| 2 | Offset | **big-endian**, from the start of the PRELOGIN payload |
| 2 | Length | **big-endian** |

Values: VERSION = 6 bytes (major u8, minor u8, build u16 BE, sub-build
u16 BE); ENCRYPTION = 1 byte (OFF 0x00, ON 0x01, NOT_SUP 0x02, REQ 0x03);
THREADID = u32 big-endian; MARS / FEDAUTHREQUIRED = 1 byte 0/1; INSTOPT,
TRACEID and NONCEOPT are opaque bytes. `tds_prelogin_parse` copies the
buffer from `off` to its end into `payload`, resolves each offset/length
pair against it, and reports `mssql: prelogin option overruns buffer` for a
pair outside that range. `next` is the offset just past the terminator.
`tds_prelogin_build_basic` emits the six options in the order above (table
31 bytes, then values in entry order, no padding).

### LOGIN7

Fixed area: 94 bytes, offsets from the structure start (the `Length`
field). All payload integers are little-endian.

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | Length (total structure length, u32) |
| 4 | 4 | TDSVersion (7.0..7.4 constants provided) |
| 8 | 4 | PacketSize |
| 12 | 4 | ClientProgVer |
| 16 | 4 | ClientPID |
| 20 | 4 | ConnectionID |
| 24 | 1 | OptionFlags1 (byte order, charset, float format, dump/load, use db, database, set lang, language) |
| 25 | 1 | OptionFlags2 (language fatal, ODBC, tran boundary, cache connect, user type, integrated security) |
| 26 | 1 | TypeFlags (SQLTYPE mask 0x0F, OLEDB 0x10, read-only intent 0x20) |
| 27 | 1 | OptionFlags3 (change password, Yukon binary XML, user instance, unknown collation, extension) |
| 28 | 4 | ClientTimeZone (signed i32, minutes) |
| 32 | 4 | ClientLCID (u32) |
| 36..55 | 20 | ib/cch pairs for hostname, username, password, app name, server name |
| 56..59 | 4 | ibExtension / cbExtension (feature extension block, **byte** count) |
| 60..71 | 12 | ib/cch pairs for library, language, database |
| 72 | 6 | ClientID (raw bytes) |
| 78..81 | 4 | ibSSPI / cbSSPI |
| 82..85 | 4 | ibAtchDBFile / cchAtchDBFile |
| 86..89 | 4 | ibChangePassword / cchChangePassword |
| 90 | 4 | cbSSPILong (u32) |

Field-count semantics implemented:

- hostname, username, password, app name, server name, library, language,
  database, attached database file and change password are **character**
  counts: the parser copies `2 * count` raw bytes (whole UTF-16LE
  characters) and preserves them verbatim, including the obfuscated
  password bytes (no de-obfuscation is performed);
- the extension block copies `cbExtension` **bytes**;
- the SSPI block uses `cbSSPI` bytes unless it is 0xFFFF, in which case
  `cbSSPILong` bytes are copied (`sspi_length` records the choice);
- every pair is validated against the declared total length; a pair that
  crosses it is `mssql: login7 field overruns buffer` at the pair's offset.

`tds_login7_build` lays data out after the fixed 94 bytes in this order:
hostname, username, password, app name, server name, extension, library,
language, database, attached database file, change password, SSPI. Text
fields must be even-length (`mssql: login7 text field must be even`); the
extension block may be odd and is padded to two-byte alignment before the
next field; SSPI starts on a four-byte boundary (zero padding). The client
id must be exactly 6 bytes. `cbSSPI` is capped at 65534 around the long
form (0xFFFF + cbSSPILong). All data offsets must fit u16, so a structure
whose SSPI offset exceeds 65535 is rejected (`mssql: login7 too large`) --
the total `Length` field itself is a u32 and may exceed 65535.

### TYPE_INFO (COLMETADATA and RETURNVALUE)

Fixed-length types (MS-TDS 2.2.5.5.2): the TYPE_INFO is only the token byte
and the row value width is implicit.

| Token | Value | Implicit row width |
|---|---|---|
| INT1TYPE | 0x30 | 1 |
| BITTYPE | 0x32 | 1 |
| INT2TYPE | 0x34 | 2 |
| INT4TYPE | 0x38 | 4 |
| DATETIME4TYPE | 0x3A | 4 |
| FLT4TYPE | 0x3B | 4 |
| MONEYTYPE | 0x3C | 8 |
| DATETIMETYPE | 0x3D | 8 |
| FLT8TYPE | 0x3E | 8 |
| INT8TYPE | 0x7F | 8 |

Nullable "N" types (MS-TDS 2.2.5.5.3): the TYPE_INFO carries a 1-byte
max/size length (DECIMALN/NUMERICN add precision and scale) and every row
value carries a 1-byte length (0 = NULL).

| Token | Value | Extra metadata after the token byte |
|---|---|---|
| NULL | 0x1F | none (row value: no bytes) |
| INTNTYPE | 0x26 | size u8 (1/2/4/8 selects int1/2/4/8) |
| BITNTYPE | 0x68 | size u8 |
| FLTNTYPE | 0x6D | size u8 |
| MONEYNTYPE | 0x6E | size u8 |
| DATETIMNTYPE | 0x6F | size u8 |
| GUIDNTYPE | 0x24 | size u8 (16 for a GUID value) |
| DECIMALNTYPE | 0x6A | size u8, precision u8, scale u8 |
| NUMERICNTYPE | 0x6C | size u8, precision u8, scale u8 |

GUID 0x24 appears in both the fixed and nullable spellings (GUIDTYPE and
GUIDNTYPE). MS-TDS encodes GUID values through the nullable 0x24 form with
a length byte, so this module treats 0x24 as GUIDNTYPE: metadata carries
the size byte and row values carry the 1-byte length (0 = NULL, 16 = a
16-byte GUID). `TDS_TYPE_GUID` and `TDS_TYPE_GUIDN` are both defined and
equal.

Variable-length types:

| Token | Value | Extra metadata after the token byte |
|---|---|---|
| BIGVARBIN | 0xA5 | max length u16 LE |
| BIGBINARY | 0xAD | max length u16 LE |
| BIGVARCHAR | 0xA7 | max length u16 LE + collation 5 bytes |
| BIGCHAR | 0xAF | max length u16 LE + collation 5 bytes |
| NVARCHAR | 0xE7 | max length u16 LE + collation 5 bytes |
| NCHAR | 0xEF | max length u16 LE + collation 5 bytes |
| XML | 0xF1 | schema flag u8; if 1: three B_VARCHAR names (db, schema, collection) |
| UDT | 0xF0 | max byte size u16 LE, three B_VARCHAR names (db, schema, type), assembly-qualified name u16 LE byte length + UTF-16LE bytes |
| TEXT | 0x23 | max length u32 LE + collation 5 bytes |
| IMAGE | 0x22 | max length u32 LE |
| NTEXT | 0x63 | max length u32 LE + collation 5 bytes |

A B_VARCHAR is a u8 **character** count followed by that many UTF-16LE
characters. A collation is 5 bytes little-endian: LCID (20 bits), flags
(8), version (4), sort id (8); helpers
`tds_collation_lcid`/`_flags`/`_version`/`_sortid` unpack it. An unknown
type token is `mssql: unsupported type token`. `tds_typeinfo_parse` is
public so callers can decode a standalone TYPE_INFO.

### COLMETADATA (0x81)

| Size | Field |
|---|---|
| 1 | token 0x81 |
| 2 | column count u16 LE (0xFFFF -> `count` = -1, "no metadata") |
| ... | per column: usertype u32 LE, flags u16 LE, TYPE_INFO |

Every per-column vector (`usertypes`, `flags`, `type_tokens`, `type_sizes`,
`precisions`, `scales`, `collations`, `collation_offsets`, and the four
name-span pairs `name1_*`..`name3_*`, `asm_*`) receives exactly one entry
per column, so all vectors stay parallel. When at least one column carries
the fEncrypted flag (0x0800) and the next byte is 0x01, a TDS 7.2+ crypto
metadata trailer (u32 LE length + bytes) is skipped so `next` lands past
it.

### ROW (0xD1) / NBCROW (0xD2)

`{COLMETADATA}` provides `count` and the per-column type. NBCROW prefixes a
null bitmap of `ceil(count / 8)` bytes; bit `i % 8` of byte `i / 8`
(LSB-first) marks column `i` NULL, and only non-null columns carry bytes.

Row value encoding implemented:

| Type class | Encoding |
|---|---|
| NULLTYPE | no bytes |
| fixed-length types | implicit width from the token (INT1/BIT 1, INT2 2, INT4/DATETIME4/FLT4 4, MONEY/DATETIME/FLT8/INT8 8); INT1/INT2/INT4/INT8 decode a sign-extended little-endian integer, BIT decodes one byte |
| nullable "N" types | 1-byte length; 0 = NULL; INTN/BITN decode a sign-extended little-endian integer; DECIMALN/NUMERICN bytes begin with the sign byte; GUIDN carries 16 bytes |
| BIGVARBIN, BIGBINARY, BIGVARCHAR, BIGCHAR | u16 LE **byte** length, 0xFFFF = NULL |
| NVARCHAR, NCHAR | u16 LE **character** count, 0xFFFF = NULL, `2 * count` bytes follow |
| XML, UDT | u16 LE **byte** length, 0xFFFF = NULL |
| TEXT, IMAGE, NTEXT | 16-byte textpointer, 8-byte timestamp, u32 LE data length, data bytes |

A fixed-length (plain) value is always present: NULLs for such columns come
from the NBCROW bitmap. A nullable value longer than its metadata size is
`mssql: bad value length`; a value crossing the buffer is
`mssql: truncated row`. Rows parsed without metadata (`count` -1) are
`mssql: row without colmetadata`. `TdsRow` records `value_offsets`,
`value_lengths`, `value_ints` and `nulls` (-1 / 1 conventions documented on
the type); `tds_row_value` copies a column's raw bytes (error
`mssql: value is null` for NULL) and `tds_row_int` returns a decoded
integer.

### Tokens

| Token | Value | Layout after the type byte |
|---|---|---|
| RETURNSTATUS | 0x79 | status u32 LE |
| ORDER | 0xA9 | length u16 LE (must be even), then length/2 ordinals u16 LE |
| ERROR / INFO | 0xAA / 0xAB | length u16 LE; number u32 LE, state u8, severity u8, message (u16 **character** count + UTF-16LE), server name B_VARCHAR, proc name B_VARCHAR, optional line u32 LE when the token length leaves 4+ bytes |
| RETURNVALUE | 0xAC | ordinal u16 LE, name B_VARCHAR, status u8, usertype u32 LE, flags u16 LE, TYPE_INFO, value (ROW rules for that type) |
| LOGINACK | 0xAD | length u16 LE; interface u8, TDS version u32 **BE**, prog name B_VARCHAR, major u8, minor u8, build u16 BE |
| FEATUREEXTACK | 0xAE | repeated: FeatureId u8 + data length u32 LE + data; terminated by FeatureId 0xFF |
| ROW / NBCROW | 0xD1 / 0xD2 | see above |
| ENVCHANGE | 0xE3 | length u16 LE; subtype u8, new value (u8 length + bytes, 0 = null), old value (same) |
| DONE / DONEPROC / DONEINPROC | 0xFD / 0xFE / 0xFF | status u16 LE, curcmd u16 LE, rowcount u64 LE |

`length` fields cover the bytes after the 2-byte length itself; every
decoder validates that its fields stay inside the token. ENVCHANGE
subtypes 1..19 are named by `tds_envchange_subtype_name` ("database",
"language", "charset", "packet size", ...); unknown subtypes are "unknown".

`tds_token_walk(data, off)` indexes each token as
`offsets[i]`/`kinds[i]`/`ends[i]`, parsing COLMETADATA along the way so
ROW/NBCROW can be measured. A ROW with no preceding COLMETADATA is
`mssql: row without colmetadata`. An unknown (unrecognized) token kind is
preserved raw: its span is `offsets[i]..data.len()`, the walk stops, and
`tds_token_raw` returns those bytes.

### UTF-16LE helper

`tds_utf16le_to_str(data, off, byte_len)` requires an even, non-negative
`byte_len` inside the buffer. Each little-endian code unit in 0x20..0x7E
becomes its ASCII byte; every other unit (NUL, controls, non-ASCII,
surrogates) becomes `?`, so the resulting `Str` can never contain a NUL
byte. `tds_utf16le_encode` writes each Str byte as one little-endian code
unit (exact for ASCII; documented lossy for non-ASCII UTF-8 input).

## Error catalog

Decoder errors carry offsets (`<message> at offset <n>`):

- `mssql: negative offset`
- `mssql: truncated packet header`, `mssql: bad packet length`,
  `mssql: truncated packet`, `mssql: packet type mismatch`,
  `mssql: message missing eom`
- `mssql: truncated prelogin table`,
  `mssql: prelogin option overruns buffer`,
  `mssql: bad prelogin version length`,
  `mssql: bad prelogin encryption length`,
  `mssql: bad prelogin encryption`
- `mssql: truncated login7 header`, `mssql: bad login7 length`,
  `mssql: truncated login7`, `mssql: login7 field overruns buffer`
- `mssql: truncated token`, `mssql: token mismatch`,
  `mssql: bad order length`
- `mssql: truncated utf16 string`, `mssql: bad utf16 length`,
  `mssql: negative utf16 length`
- `mssql: truncated type info`, `mssql: unsupported type token`,
  `mssql: bad xml schema flag`, `mssql: truncated b_varchar`
- `mssql: truncated colmetadata`
- `mssql: truncated row`, `mssql: row without colmetadata`,
  `mssql: bad type size`, `mssql: bad value length`
- `mssql: truncated returnvalue`
- `mssql: truncated featureextack`

Encoder errors carry no offset: `mssql: packet too large`,
`mssql: bad packet size`, `mssql: bad encryption value`,
`mssql: bad mars value`, `mssql: bad fedauth value`,
`mssql: bad threadid`, `mssql: bad version`,
`mssql: login7 text field must be even`,
`mssql: client id must be 6 bytes`, `mssql: login7 too large`.

Accessor errors: `mssql: prelogin option not found`,
`mssql: column index out of range`, `mssql: value is null`,
`mssql: token index out of range`.

## Documented divergences and notes

1. **Canonical type tokens.** The TYPE_INFO table follows MS-TDS
   2.2.5.5.1.2/2.2.5.5.1.3: fixed-length INT1TYPE 0x30, BITTYPE 0x32,
   INT2TYPE 0x34, INT4TYPE 0x38, DATETIME4TYPE 0x3A, FLT4TYPE 0x3B,
   MONEYTYPE 0x3C, DATETIMETYPE 0x3D, FLT8TYPE 0x3E, INT8TYPE 0x7F; nullable
   INTNTYPE 0x26, BITNTYPE 0x68, FLTNTYPE 0x6D, MONEYNTYPE 0x6E,
   DATETIMNTYPE 0x6F, DECIMALNTYPE 0x6A, NUMERICNTYPE 0x6C, GUIDNTYPE 0x24.
   A 64-bit integer is normally sent as INTNTYPE with a length-8 size byte
   (INT8TYPE 0x7F is the legacy fixed form). An earlier port brief assigned
   FLTN/MONEYN/BIGINTN to 0x3B/0x3E/0x38; those aliases have been removed.
2. **GUID 0x24.** GUIDTYPE and GUIDNTYPE share the value 0x24. MS-TDS
   encodes GUID values through the nullable form (length byte in both the
   TYPE_INFO and the row value), so this module dispatches 0x24 as GUIDN;
   `TDS_TYPE_GUID` and `TDS_TYPE_GUIDN` are aliases and `tds_type_token_name`
   reports "GUIDN".
3. **"Length/collation/table-name metadata."** The port brief's table-name
   metadata is implemented as the XML/UDT schema-qualified names
   (db/schema/collection or db/schema/type plus assembly name). TDS 7.x
   COLMETADATA has no standalone table-name field; TDS 7.2+ crypto
   metadata is skipped rather than decoded.
4. **Unicode row lengths.** NVARCHAR / NCHAR / NTEXT row lengths are
   treated as character counts (2 bytes per character); binary,
   non-Unicode character, XML and UDT lengths are byte counts. Both rules
   are pinned by the conformance suite.
5. **ERROR/INFO message length** is a character count (the token's
   `US_VARCHAR` semantics); server and proc names are B_VARCHAR
   (u8 character counts).
6. **Password handling.** The obfuscated password bytes are preserved
   verbatim; nibble de-obfuscation is out of scope (login crypto).
7. **Text safety.** `tds_utf16le_to_str` is intentionally lossy above
   ASCII and can never emit NUL; lossless text would need a full UTF-16
   decoder, which is out of scope.
