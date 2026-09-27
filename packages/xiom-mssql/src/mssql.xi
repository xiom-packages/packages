// XIOM -- xiom.mssql: Microsoft SQL Server TDS structure codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no login crypto) codec for the structural
// layers of the TDS (Tabular Data Stream) wire protocol used by Microsoft
// SQL Server:
//
//   * packet framing: the 8-byte packet header (type, status, big-endian
//     length, SPID, packet id, window) and multi-packet message assembly;
//   * PRELOGIN: the option table of (token, offset u16 BE, length u16 BE)
//     entries plus the VERSION and ENCRYPTION values;
//   * LOGIN7: the fixed 94-byte layout, the offset/length field table, the
//     raw (obfuscated) password bytes, the client id, the SSPI block and the
//     raw feature-extension block;
//   * RESPONSE token streams: a walking index over LOGINACK, ERROR, INFO,
//     ENVCHANGE, DONE/DONEPROC/DONEINPROC, COLMETADATA, ROW, NBCROW,
//     RETURNSTATUS, RETURNVALUE, FEATUREEXTACK and ORDER tokens, plus typed
//     decoders for each of those tokens;
//   * a UTF-16LE text helper that maps every non-printable-ASCII code unit
//     to '?' so it can never produce a NUL byte inside a Str.
//
// Mixed endianness is composed explicitly: the packet header length and SPID
// are big-endian, almost every payload length is little-endian.
//
// Every malformed input is rejected with a stable Err(Str) that names the
// byte offset of the offending structure. See SPEC.md for the byte-level
// layouts and the documented divergences from MS-TDS.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, lambdas or indexed Vec[fn] dispatch;
//   * Ok/Err construction is confined to the tiny leaf helpers below;
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic;
//   * Vec[Int] element reads are bound to typed locals;
//   * `&struct.field` is bound to a local before being passed to a
//     `&Vec[UInt8]` parameter;
//   * parallel Vec[Int] fields carry per-item data (columns, rows, tokens);
//     Vec[StructType] and Vec[Vec[UInt8]] are not used.

module xiom.mssql

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Protocol constants
// --------------------------------------------------

/// Package version string.
pub fn tds_package_version() -> Str {
  return "0.1.0";
}

/// Size of the TDS packet header in bytes.
pub const TDS_PACKET_HEADER_LEN: Int = 8;

/// Packet type SQL_BATCH (0x01).
pub const TDS_PKT_SQL_BATCH: Int = 1;

/// Packet type RPC (0x03).
pub const TDS_PKT_RPC: Int = 3;

/// Packet type RESPONSE / TABULAR_RESULT (0x04).
pub const TDS_PKT_RESPONSE: Int = 4;

/// Packet type LOGIN7 (0x10).
pub const TDS_PKT_LOGIN7: Int = 16;

/// Packet type SSPI (0x11).
pub const TDS_PKT_SSPI: Int = 17;

/// Packet type PRELOGIN (0x12).
pub const TDS_PKT_PRELOGIN: Int = 18;

/// Status bit EOM: last packet of a message (0x01).
pub const TDS_STATUS_EOM: Int = 1;

/// Status bit IGNORE: packet to be ignored (0x02).
pub const TDS_STATUS_IGNORE: Int = 2;

/// Status bit RESETCONNECTION (0x08).
pub const TDS_STATUS_RESETCONNECTION: Int = 8;

// PRELOGIN option tokens.

/// PRELOGIN VERSION option token (0x00).
pub const TDS_PRELOGIN_VERSION: Int = 0;

/// PRELOGIN ENCRYPTION option token (0x01).
pub const TDS_PRELOGIN_ENCRYPTION: Int = 1;

/// PRELOGIN INSTOPT option token (0x02).
pub const TDS_PRELOGIN_INSTOPT: Int = 2;

/// PRELOGIN THREADID option token (0x03).
pub const TDS_PRELOGIN_THREADID: Int = 3;

/// PRELOGIN MARS option token (0x04).
pub const TDS_PRELOGIN_MARS: Int = 4;

/// PRELOGIN TRACEID option token (0x05).
pub const TDS_PRELOGIN_TRACEID: Int = 5;

/// PRELOGIN FEDAUTHREQUIRED option token (0x06).
pub const TDS_PRELOGIN_FEDAUTHREQUIRED: Int = 6;

/// PRELOGIN NONCEOPT option token (0x07).
pub const TDS_PRELOGIN_NONCEOPT: Int = 7;

/// PRELOGIN terminator byte (0xFF).
pub const TDS_PRELOGIN_TERMINATOR: Int = 255;

// PRELOGIN ENCRYPTION values.

/// ENCRYPT_OFF (0x00).
pub const TDS_ENCRYPT_OFF: Int = 0;

/// ENCRYPT_ON (0x01).
pub const TDS_ENCRYPT_ON: Int = 1;

/// ENCRYPT_NOT_SUP (0x02).
pub const TDS_ENCRYPT_NOT_SUP: Int = 2;

/// ENCRYPT_REQ (0x03).
pub const TDS_ENCRYPT_REQ: Int = 3;

// LOGIN7 OptionFlags1 bits.

/// fByteOrder (0x01; 0 = ORDER_X86 little-endian).
pub const TDS_LOGIN7_OPT1_BYTE_ORDER: Int = 1;

/// fChar (0x02; 0 = ASCII, 1 = EBCDIC).
pub const TDS_LOGIN7_OPT1_CHARSET: Int = 2;

/// fFloat (0x04; 0 = IEEE 754, 1 = VAX).
pub const TDS_LOGIN7_OPT1_FLOAT_FORMAT: Int = 4;

/// fDumpLoad (0x08).
pub const TDS_LOGIN7_OPT1_DUMP_LOAD: Int = 8;

/// fUseDB (0x10).
pub const TDS_LOGIN7_OPT1_USE_DB: Int = 16;

/// fDatabase (0x20).
pub const TDS_LOGIN7_OPT1_DATABASE: Int = 32;

/// fSetLang (0x40).
pub const TDS_LOGIN7_OPT1_SET_LANG: Int = 64;

/// fLanguage (0x80, deprecated).
pub const TDS_LOGIN7_OPT1_LANGUAGE: Int = 128;

// LOGIN7 OptionFlags2 bits.

/// fLanguage (0x01 in option flags 2: 0 = LANGUAGE_FATAL).
pub const TDS_LOGIN7_OPT2_LANGUAGE_FATAL: Int = 1;

/// fODBC (0x02).
pub const TDS_LOGIN7_OPT2_ODBC: Int = 2;

/// fTranBoundary (0x04).
pub const TDS_LOGIN7_OPT2_TRAN_BOUNDARY: Int = 4;

/// fCacheConnect (0x08).
pub const TDS_LOGIN7_OPT2_CACHE_CONNECT: Int = 8;

/// fUserType (0x10).
pub const TDS_LOGIN7_OPT2_USER_TYPE: Int = 16;

/// fIntegratedSecurity (0x80).
pub const TDS_LOGIN7_OPT2_INTEGRATED_SECURITY: Int = 128;

// LOGIN7 OptionFlags3 bits.

/// fChangePassword (0x01).
pub const TDS_LOGIN7_OPT3_CHANGE_PASSWORD: Int = 1;

/// fSendYukonBinaryXML (0x02).
pub const TDS_LOGIN7_OPT3_SEND_YUKON_BINARY_XML: Int = 2;

/// fUserInstance (0x04).
pub const TDS_LOGIN7_OPT3_USER_INSTANCE: Int = 4;

/// fUnknownCollationHandling (0x08).
pub const TDS_LOGIN7_OPT3_UNKNOWN_COLLATION: Int = 8;

/// fExtension (0x10; the feature-extension block is present).
pub const TDS_LOGIN7_OPT3_EXTENSION: Int = 16;

// LOGIN7 TypeFlags bits.

/// fSQLType mask (0x0F).
pub const TDS_LOGIN7_TYPE_SQLTYPE_MASK: Int = 15;

/// SQL_DFLT (1).
pub const TDS_LOGIN7_TYPE_DEFAULT: Int = 1;

/// SQL_TSQL (2).
pub const TDS_LOGIN7_TYPE_TSQL: Int = 2;

/// fOLEDB (0x10).
pub const TDS_LOGIN7_TYPE_OLEDB: Int = 16;

/// fReadOnlyIntent (0x20).
pub const TDS_LOGIN7_TYPE_READONLY_INTENT: Int = 32;

/// LOGIN7 fixed-area size in bytes.
pub const TDS_LOGIN7_FIXED_LEN: Int = 94;

// LOGIN7 fixed-area byte offsets.

/// LOGIN7 offset of Length (u32 LE).
pub const TDS_LOGIN7_OFF_LENGTH: Int = 0;

/// LOGIN7 offset of the field table (ibHostName).
pub const TDS_LOGIN7_OFF_HOSTNAME: Int = 36;

/// LOGIN7 offset of ibSSPI.
pub const TDS_LOGIN7_OFF_SSPI: Int = 78;

/// LOGIN7 offset of ibAtchDBFile.
pub const TDS_LOGIN7_OFF_ATTACH_DB_FILE: Int = 82;

/// LOGIN7 offset of ibChangePassword.
pub const TDS_LOGIN7_OFF_CHANGE_PASSWORD: Int = 86;

/// LOGIN7 offset of cbSSPILong (u32 LE).
pub const TDS_LOGIN7_OFF_SSPI_LONG: Int = 90;

// TDS versions (LOGIN7 TDSVersion field values).

/// TDS 7.0.
pub const TDS_VERSION_70: Int = 1879048192;

/// TDS 7.1.
pub const TDS_VERSION_71: Int = 1895825409;

/// TDS 7.2.
pub const TDS_VERSION_72: Int = 1913188866;

/// TDS 7.3.
pub const TDS_VERSION_73: Int = 1930035203;

/// TDS 7.4.
pub const TDS_VERSION_74: Int = 1946157060;

// RESPONSE token types.

/// RETURNSTATUS token (0x79).
pub const TDS_TOKEN_RETURNSTATUS: Int = 121;

/// COLMETADATA token (0x81).
pub const TDS_TOKEN_COLMETADATA: Int = 129;

/// ORDER token (0xA9).
pub const TDS_TOKEN_ORDER: Int = 169;

/// ERROR token (0xAA).
pub const TDS_TOKEN_ERROR: Int = 170;

/// INFO token (0xAB).
pub const TDS_TOKEN_INFO: Int = 171;

/// RETURNVALUE token (0xAC).
pub const TDS_TOKEN_RETURNVALUE: Int = 172;

/// LOGINACK token (0xAD).
pub const TDS_TOKEN_LOGINACK: Int = 173;

/// FEATUREEXTACK token (0xAE).
pub const TDS_TOKEN_FEATUREEXTACK: Int = 174;

/// ROW token (0xD1).
pub const TDS_TOKEN_ROW: Int = 209;

/// NBCROW token (0xD2).
pub const TDS_TOKEN_NBCROW: Int = 210;

/// ENVCHANGE token (0xE3).
pub const TDS_TOKEN_ENVCHANGE: Int = 227;

/// DONE token (0xFD).
pub const TDS_TOKEN_DONE: Int = 253;

/// DONEPROC token (0xFE).
pub const TDS_TOKEN_DONEPROC: Int = 254;

/// DONEINPROC token (0xFF).
pub const TDS_TOKEN_DONEINPROC: Int = 255;

/// DONEFINAL: package-brief name for the 0xFF token (DONEINPROC).
pub const TDS_TOKEN_DONEFINAL: Int = 255;

// DONE status bits.

/// DONE_MORE (0x0001).
pub const TDS_DONE_MORE: Int = 1;

/// DONE_ERROR (0x0002).
pub const TDS_DONE_ERROR: Int = 2;

/// DONE_INXACT (0x0004).
pub const TDS_DONE_INXACT: Int = 4;

/// DONE_COUNT (0x0010).
pub const TDS_DONE_COUNT: Int = 16;

/// DONE_ATTN (0x0020).
pub const TDS_DONE_ATTN: Int = 32;

/// DONE_SRVERROR (0x0100).
pub const TDS_DONE_SRVERROR: Int = 256;

// ENVCHANGE subtypes.

/// ENVCHANGE subtype database (1).
pub const TDS_ENV_DATABASE: Int = 1;

/// ENVCHANGE subtype language (2).
pub const TDS_ENV_LANGUAGE: Int = 2;

/// ENVCHANGE subtype charset (3).
pub const TDS_ENV_CHARSET: Int = 3;

/// ENVCHANGE subtype packet size (4).
pub const TDS_ENV_PACKET_SIZE: Int = 4;

/// ENVCHANGE subtype unicode sort (5).
pub const TDS_ENV_UNICODE_SORT: Int = 5;

/// ENVCHANGE subtype unicode comparison flags (6).
pub const TDS_ENV_UNICODE_COMPARE: Int = 6;

/// ENVCHANGE subtype collation (7).
pub const TDS_ENV_COLLATION: Int = 7;

/// ENVCHANGE subtype begin transaction (8).
pub const TDS_ENV_BEGIN_TXN: Int = 8;

/// ENVCHANGE subtype commit transaction (9).
pub const TDS_ENV_COMMIT_TXN: Int = 9;

/// ENVCHANGE subtype rollback transaction (10).
pub const TDS_ENV_ROLLBACK_TXN: Int = 10;

/// ENVCHANGE subtype enlist DTC (11).
pub const TDS_ENV_ENLIST_DTC: Int = 11;

/// ENVCHANGE subtype defect transaction (12).
pub const TDS_ENV_DEFECT_TXN: Int = 12;

/// ENVCHANGE subtype real-time log shipping (13).
pub const TDS_ENV_REAL_TIME_LOG: Int = 13;

/// ENVCHANGE subtype promote transaction (14).
pub const TDS_ENV_PROMOTE_TXN: Int = 14;

/// ENVCHANGE subtype transaction manager address (15).
pub const TDS_ENV_TXN_MANAGER: Int = 15;

/// ENVCHANGE subtype transaction ended (16).
pub const TDS_ENV_TXN_ENDED: Int = 16;

/// ENVCHANGE subtype reset ack (17).
pub const TDS_ENV_RESET_ACK: Int = 17;

/// ENVCHANGE subtype user instance name (18).
pub const TDS_ENV_USER_INSTANCE: Int = 18;

/// ENVCHANGE subtype routing (19).
pub const TDS_ENV_ROUTING: Int = 19;

// TYPE_INFO tokens (see SPEC.md for the divergences from MS-TDS).

/// NULLTYPE (0x1F).
pub const TDS_TYPE_NULL: Int = 31;

// Fixed-length types (MS-TDS 2.2.5.5.1.2): TYPE_INFO is only the token byte
// and the row value width is implicit.

/// INT1TYPE (0x30), implicit 1-byte value.
pub const TDS_TYPE_INT1: Int = 48;

/// BITTYPE (0x32), implicit 1-byte value.
pub const TDS_TYPE_BIT: Int = 50;

/// INT2TYPE (0x34), implicit 2-byte value.
pub const TDS_TYPE_INT2: Int = 52;

/// INT4TYPE (0x38), implicit 4-byte value.
pub const TDS_TYPE_INT4: Int = 56;

/// DATETIME4TYPE (0x3A), implicit 4-byte value.
pub const TDS_TYPE_DATETIME4: Int = 58;

/// FLT4TYPE (0x3B), implicit 4-byte value.
pub const TDS_TYPE_FLT4: Int = 59;

/// MONEYTYPE (0x3C), implicit 8-byte value.
pub const TDS_TYPE_MONEY: Int = 60;

/// DATETIMETYPE (0x3D), implicit 8-byte value.
pub const TDS_TYPE_DATETIME: Int = 61;

/// FLT8TYPE (0x3E), implicit 8-byte value.
pub const TDS_TYPE_FLT8: Int = 62;

/// INT8TYPE (0x7F), implicit 8-byte value.
pub const TDS_TYPE_INT8: Int = 127;

/// GUIDTYPE (0x24; treated as the nullable GUIDN form, see TDS_TYPE_GUIDN).
pub const TDS_TYPE_GUID: Int = 36;

// Nullable "N" types (MS-TDS 2.2.5.5.1.3): a 1-byte max/size length in the
// TYPE_INFO (DECIMALN/NUMERICN add precision and scale) and a 1-byte length
// in each row value.

/// INTNTYPE (0x26), 1-byte max length (1/2/4/8 selects int1/2/4/8).
pub const TDS_TYPE_INTN: Int = 38;

/// BITNTYPE (0x68), 1-byte max length.
pub const TDS_TYPE_BITN: Int = 104;

/// FLTNTYPE (0x6D), 1-byte max length.
pub const TDS_TYPE_FLTN: Int = 109;

/// MONEYNTYPE (0x6E), 1-byte max length.
pub const TDS_TYPE_MONEYN: Int = 110;

/// DATETIMNTYPE (0x6F), 1-byte max length.
pub const TDS_TYPE_DATETIMEN: Int = 111;

/// GUIDNTYPE (0x24), 1-byte max length (16 for a GUID value).
pub const TDS_TYPE_GUIDN: Int = 36;

/// DECIMALNTYPE (0x6A), size + precision + scale.
pub const TDS_TYPE_DECIMALN: Int = 106;

/// NUMERICNTYPE (0x6C), size + precision + scale.
pub const TDS_TYPE_NUMERICN: Int = 108;

/// BIGVARBIN (0xA5), u16 max length.
pub const TDS_TYPE_BIGVARBIN: Int = 165;

/// BIGBINARY (0xAD), u16 max length.
pub const TDS_TYPE_BIGBINARY: Int = 173;

/// BIGVARCHAR (0xA7), u16 max length + collation.
pub const TDS_TYPE_BIGVARCHAR: Int = 167;

/// BIGCHAR (0xAF), u16 max length + collation.
pub const TDS_TYPE_BIGCHAR: Int = 175;

/// NVARCHAR (0xE7), u16 max length + collation.
pub const TDS_TYPE_NVARCHAR: Int = 231;

/// NCHAR (0xEF), u16 max length + collation.
pub const TDS_TYPE_NCHAR: Int = 239;

/// XML (0xF1), schema info.
pub const TDS_TYPE_XML: Int = 241;

/// UDT (0xF0), size + schema-qualified type name + assembly name.
pub const TDS_TYPE_UDT: Int = 240;

/// TEXT (0x23), u32 max length + collation.
pub const TDS_TYPE_TEXT: Int = 35;

/// IMAGE (0x22), u32 max length.
pub const TDS_TYPE_IMAGE: Int = 34;

/// NTEXT (0x63), u32 max length + collation.
pub const TDS_TYPE_NTEXT: Int = 99;

/// Column flag fEncrypted (0x0800) used by the TDS 7.2+ crypto metadata.
pub const TDS_COL_FLAG_ENCRYPTED: Int = 2048;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One decoded 8-byte TDS packet header. `length` includes the header;
/// `payload_offset` is the absolute offset of the first payload byte and
/// `next` the absolute offset just past the packet.
pub type TdsPacket = {
  pkt_type: Int;
  status: Int;
  length: Int;
  spid: Int;
  packet_id: Int;
  window: Int;
  payload_offset: Int;
  next: Int;
}

/// One assembled multi-packet message: the fields of the first packet plus
/// the concatenated payloads of every packet up to and including the one
/// with the EOM status bit, and `next` (the offset just past that packet).
pub type TdsMessage = {
  pkt_type: Int;
  status: Int;
  spid: Int;
  window: Int;
  first_packet_id: Int;
  packet_count: Int;
  payload: Vec[UInt8];
  next: Int;
}

/// A parsed PRELOGIN option table. Entry `i` is `(tokens[i], offsets[i],
/// lengths[i])`; offsets are relative to the start of the PRELOGIN payload
/// and `payload` holds a copy of the buffer from `off` to its end, so value
/// accessors need no second source buffer. `next` is the offset just past
/// the 0xFF terminator.
pub type TdsPrelogin = {
  tokens: Vec[Int];
  offsets: Vec[Int];
  lengths: Vec[Int];
  payload: Vec[UInt8];
  next: Int;
}

/// The 6-byte PRELOGIN VERSION value: major, minor, build (u16 BE) and
/// sub-build (u16 BE).
pub type TdsPreloginVersion = {
  major: Int;
  minor: Int;
  build: Int;
  subbuild: Int;
}

/// A parsed LOGIN7 structure. Text fields hold their raw bytes (2 bytes per
/// character of the offset/length table); `password` keeps the obfuscated
/// bytes verbatim, `extension` the raw feature-extension block and `sspi`
/// the raw SSPI block (`sspi_length` records the chosen cbSSPI/cbSSPILong
/// byte count). `next` is the offset just past the declared total length.
pub type TdsLogin7 = {
  total_length: Int;
  tds_version: Int;
  packet_size: Int;
  client_prog_version: Int;
  client_pid: Int;
  connection_id: Int;
  option_flags1: Int;
  option_flags2: Int;
  type_flags: Int;
  option_flags3: Int;
  client_timezone: Int;
  client_lcid: Int;
  hostname: Vec[UInt8];
  username: Vec[UInt8];
  password: Vec[UInt8];
  app_name: Vec[UInt8];
  server_name: Vec[UInt8];
  extension: Vec[UInt8];
  library: Vec[UInt8];
  language: Vec[UInt8];
  database: Vec[UInt8];
  client_id: Vec[UInt8];
  attach_db_file: Vec[UInt8];
  change_password: Vec[UInt8];
  sspi: Vec[UInt8];
  sspi_length: Int;
  next: Int;
}

/// Decoded TYPE_INFO metadata (shared by COLMETADATA and RETURNVALUE).
/// `size` is the max length / max byte size, `precision`/`scale` are -1 when
/// absent, `collation` packs the 5-byte collation little-endian (-1 when
/// absent, raw offset in `collation_offset`), the name spans describe the
/// schema-qualified names of XML/UDT types and `asm_offset`/`asm_length` the
/// UDT assembly-qualified name. `next` is the offset just past the type
/// info.
pub type TdsTypeInfo = {
  token: Int;
  size: Int;
  precision: Int;
  scale: Int;
  collation: Int;
  collation_offset: Int;
  name1_offset: Int;
  name1_length: Int;
  name2_offset: Int;
  name2_length: Int;
  name3_offset: Int;
  name3_length: Int;
  asm_offset: Int;
  asm_length: Int;
  next: Int;
}

/// A B_VARCHAR span: `data_offset`/`length` locate the raw UTF-16LE bytes in
/// the source buffer (the 1-byte character count is not included) and `next`
/// is the offset just past the value.
pub type TdsNameSpan = {
  data_offset: Int;
  length: Int;
  next: Int;
}

/// A parsed COLMETADATA token. Every per-column vector has exactly one entry
/// per column (mirrored pushes). `count` is -1 for the 0xFFFF "no metadata"
/// marker.
pub type TdsColMeta = {
  count: Int;
  usertypes: Vec[Int];
  flags: Vec[Int];
  type_tokens: Vec[Int];
  type_sizes: Vec[Int];
  precisions: Vec[Int];
  scales: Vec[Int];
  collations: Vec[Int];
  collation_offsets: Vec[Int];
  name1_offsets: Vec[Int];
  name1_lengths: Vec[Int];
  name2_offsets: Vec[Int];
  name2_lengths: Vec[Int];
  name3_offsets: Vec[Int];
  name3_lengths: Vec[Int];
  asm_offsets: Vec[Int];
  asm_lengths: Vec[Int];
  next: Int;
}

/// One decoded row value span. `is_null` is 1 for a NULL column (then
/// `data_offset`/`data_length` are -1 and `value_int` is 0); for fixed
/// integer types `value_int` is the sign-extended little-endian value.
/// `next` is the offset just past the value.
pub type TdsValueSpan = {
  is_null: Int;
  data_offset: Int;
  data_length: Int;
  value_int: Int;
  next: Int;
}

/// A parsed ROW (0xD1) or NBCROW (0xD2) token. `nulls[i]` is 1 when column
/// `i` is NULL; `value_offsets[i]`/`value_lengths[i]` are -1 for NULL.
pub type TdsRow = {
  is_nbc: Int;
  count: Int;
  value_offsets: Vec[Int];
  value_lengths: Vec[Int];
  value_ints: Vec[Int];
  nulls: Vec[Int];
  next: Int;
}

/// A walking index over a RESPONSE payload: for token `i`, `offsets[i]` is
/// the token type byte offset, `kinds[i]` the type byte and `ends[i]` the
/// offset just past the token. An unknown token owns the rest of the buffer
/// (`ends[i]` == buffer length) and ends the walk. `next` is the offset just
/// past the last indexed token.
pub type TdsTokenIndex = {
  offsets: Vec[Int];
  kinds: Vec[Int];
  ends: Vec[Int];
  next: Int;
}

/// A parsed LOGINACK token (0xAD). `tds_version` is the big-endian 4-byte
/// version; `prog_name` is the ASCII-safe decoded program name; `build` is
/// the two build bytes (hi*256 + lo).
pub type TdsLoginAck = {
  length: Int;
  iface: Int;
  tds_version: Int;
  prog_name: Str;
  major: Int;
  minor: Int;
  build: Int;
  next: Int;
}

/// A parsed ERROR (0xAA) or INFO (0xAB) token. `severity` is the class byte;
/// `line` is -1 when the token length omits the line number.
pub type TdsError = {
  is_info: Int;
  length: Int;
  number: Int;
  state: Int;
  severity: Int;
  message: Str;
  server_name: Str;
  proc_name: Str;
  line: Int;
  next: Int;
}

/// A parsed ENVCHANGE token (0xE3). `new_bytes`/`old_bytes` hold the raw
/// value bytes (empty when the u8 length was 0, with the corresponding
/// `*_is_null` flag set).
pub type TdsEnvChange = {
  length: Int;
  subtype: Int;
  new_is_null: Int;
  old_is_null: Int;
  new_bytes: Vec[UInt8];
  old_bytes: Vec[UInt8];
  next: Int;
}

/// A parsed DONE (0xFD), DONEPROC (0xFE) or DONEINPROC (0xFF) token.
pub type TdsDone = {
  token: Int;
  status: Int;
  curcmd: Int;
  rowcount: Int;
  next: Int;
}

/// A parsed RETURNSTATUS token (0x79).
pub type TdsReturnStatus = {
  status: Int;
  next: Int;
}

/// A parsed RETURNVALUE token (0xAC). `name` is the ASCII-safe decoded
/// parameter name; `value_*` mirror `TdsValueSpan`.
pub type TdsReturnValue = {
  ordinal: Int;
  name: Str;
  status: Int;
  usertype: Int;
  flags: Int;
  type_token: Int;
  type_size: Int;
  precision: Int;
  scale: Int;
  collation: Int;
  is_null: Int;
  value_offset: Int;
  value_length: Int;
  value_int: Int;
  next: Int;
}

/// A parsed FEATUREEXTACK token (0xAE): one entry per feature block.
pub type TdsFeatureExtAck = {
  ids: Vec[Int];
  offsets: Vec[Int];
  lengths: Vec[Int];
  next: Int;
}

/// A parsed ORDER token (0xA9).
pub type TdsOrder = {
  length: Int;
  ordinals: Vec[Int];
  next: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[TdsPacket, Str].
fn _ok_packet(v: TdsPacket) -> Result[TdsPacket, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsPacket, Str].
fn _err_packet(m: Str) -> Result[TdsPacket, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsMessage, Str].
fn _ok_message(v: TdsMessage) -> Result[TdsMessage, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsMessage, Str].
fn _err_message(m: Str) -> Result[TdsMessage, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsPrelogin, Str].
fn _ok_prelogin(v: TdsPrelogin) -> Result[TdsPrelogin, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsPrelogin, Str].
fn _err_prelogin(m: Str) -> Result[TdsPrelogin, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsPreloginVersion, Str].
fn _ok_pversion(v: TdsPreloginVersion) -> Result[TdsPreloginVersion, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsPreloginVersion, Str].
fn _err_pversion(m: Str) -> Result[TdsPreloginVersion, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsLogin7, Str].
fn _ok_login7(v: TdsLogin7) -> Result[TdsLogin7, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsLogin7, Str].
fn _err_login7(m: Str) -> Result[TdsLogin7, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsTypeInfo, Str].
fn _ok_typeinfo(v: TdsTypeInfo) -> Result[TdsTypeInfo, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsTypeInfo, Str].
fn _err_typeinfo(m: Str) -> Result[TdsTypeInfo, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsNameSpan, Str].
fn _ok_namespan(v: TdsNameSpan) -> Result[TdsNameSpan, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsNameSpan, Str].
fn _err_namespan(m: Str) -> Result[TdsNameSpan, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsColMeta, Str].
fn _ok_colmeta(v: TdsColMeta) -> Result[TdsColMeta, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsColMeta, Str].
fn _err_colmeta(m: Str) -> Result[TdsColMeta, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsValueSpan, Str].
fn _ok_valspan(v: TdsValueSpan) -> Result[TdsValueSpan, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsValueSpan, Str].
fn _err_valspan(m: Str) -> Result[TdsValueSpan, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsRow, Str].
fn _ok_row(v: TdsRow) -> Result[TdsRow, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsRow, Str].
fn _err_row(m: Str) -> Result[TdsRow, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsTokenIndex, Str].
fn _ok_tokenindex(v: TdsTokenIndex) -> Result[TdsTokenIndex, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsTokenIndex, Str].
fn _err_tokenindex(m: Str) -> Result[TdsTokenIndex, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsLoginAck, Str].
fn _ok_loginack(v: TdsLoginAck) -> Result[TdsLoginAck, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsLoginAck, Str].
fn _err_loginack(m: Str) -> Result[TdsLoginAck, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsError, Str].
fn _ok_error(v: TdsError) -> Result[TdsError, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsError, Str].
fn _err_error(m: Str) -> Result[TdsError, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsEnvChange, Str].
fn _ok_envchange(v: TdsEnvChange) -> Result[TdsEnvChange, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsEnvChange, Str].
fn _err_envchange(m: Str) -> Result[TdsEnvChange, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsDone, Str].
fn _ok_done(v: TdsDone) -> Result[TdsDone, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsDone, Str].
fn _err_done(m: Str) -> Result[TdsDone, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsReturnStatus, Str].
fn _ok_returnstatus(v: TdsReturnStatus) -> Result[TdsReturnStatus, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsReturnStatus, Str].
fn _err_returnstatus(m: Str) -> Result[TdsReturnStatus, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsReturnValue, Str].
fn _ok_returnvalue(v: TdsReturnValue) -> Result[TdsReturnValue, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsReturnValue, Str].
fn _err_returnvalue(m: Str) -> Result[TdsReturnValue, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsFeatureExtAck, Str].
fn _ok_featureack(v: TdsFeatureExtAck) -> Result[TdsFeatureExtAck, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsFeatureExtAck, Str].
fn _err_featureack(m: Str) -> Result[TdsFeatureExtAck, Str] {
  return Err(m);
}

// Ok(v) for Result[TdsOrder, Str].
fn _ok_order(v: TdsOrder) -> Result[TdsOrder, Str] {
  return Ok(v);
}

// Err(m) for Result[TdsOrder, Str].
fn _err_order(m: Str) -> Result[TdsOrder, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Little-endian u16 at `pos`.
fn _u16le(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) + _byte(data, pos + 1) * 256;
}

// Big-endian u16 at `pos`.
fn _u16be(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Little-endian u32 at `pos` (0..4294967295).
fn _u32le(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) + _byte(data, pos + 1) * 256 + _byte(data, pos + 2) * 65536 + _byte(data, pos + 3) * 16777216;
}

// Big-endian u32 at `pos` (0..4294967295).
fn _u32be(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 16777216 + _byte(data, pos + 1) * 65536 + _byte(data, pos + 2) * 256 + _byte(data, pos + 3);
}

// Little-endian i32 at `pos` (sign-extended).
fn _i32le(data: &Vec[UInt8], pos: Int) -> Int {
  let u: Int = _u32le(data, pos);
  if u >= 2147483648 {
    return u - 4294967296;
  }
  return u;
}

// Little-endian u64 at `pos` reinterpreted as a signed Int.
fn _u64le(data: &Vec[UInt8], pos: Int) -> Int {
  let lo: Int = _u32le(data, pos);
  let hi: Int = _u32le(data, pos + 4);
  return lo + hi * 4294967296;
}

// 2^k for k in 0..62 (used for sign extension and bitmap bit tests).
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Sign-extended little-endian integer of `width` bytes (1..8) at `pos`.
// The most significant (last) byte seeds the sign so the accumulator never
// exceeds Int range, then each lower byte is folded in.
fn _le_signed(data: &Vec[UInt8], pos: Int, width: Int) -> Int {
  if width <= 0 {
    return 0;
  }
  let top: Int = _byte(data, pos + width - 1);
  var v = 0;
  if top >= 128 {
    v = top - 256;
  } else {
    v = top;
  }
  var i = width - 2;
  while i >= 0 {
    v = v * 256 + _byte(data, pos + i);
    i = i - 1;
  }
  return v;
}

// Copy `n` bytes starting at `start` into a fresh vector; callers guarantee
// `start >= 0`, `n >= 0` and `start + n <= data.len()`.
fn _copy_bytes(data: &Vec[UInt8], start: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(data[start + i]);
    i = i + 1;
  }
  return out;
}

// Append every byte of `v` to `out`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Append the low byte of `v`.
fn _push_u8(out: &mut Vec[UInt8], v: Int) {
  out.push((v & 255) as UInt8);
}

// Append the low two bytes of `v` little-endian.
fn _push_u16le(out: &mut Vec[UInt8], v: Int) {
  out.push((v & 255) as UInt8);
  out.push(((v / 256) & 255) as UInt8);
}

// Append the low two bytes of `v` big-endian.
fn _push_u16be(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 256) & 255) as UInt8);
  out.push((v & 255) as UInt8);
}

// Append the low four bytes of `v` little-endian.
fn _push_u32le(out: &mut Vec[UInt8], v: Int) {
  out.push((v & 255) as UInt8);
  out.push(((v / 256) & 255) as UInt8);
  out.push(((v / 65536) & 255) as UInt8);
  out.push(((v / 16777216) & 255) as UInt8);
}

// Append the low four bytes of `v` big-endian.
fn _push_u32be(out: &mut Vec[UInt8], v: Int) {
  out.push(((v / 16777216) & 255) as UInt8);
  out.push(((v / 65536) & 255) as UInt8);
  out.push(((v / 256) & 255) as UInt8);
  out.push((v & 255) as UInt8);
}

// Append `v` as a signed 32-bit little-endian value (two's complement).
fn _push_i32le(out: &mut Vec[UInt8], v: Int) {
  _push_u32le(out, v & 4294967295);
}

// True when bit `bit` of `flags` is set.
fn _has_bit(flags: Int, bit: Int) -> Bool {
  return (flags & bit) != 0;
}

// Render "`msg` at offset `off`" for the error catalog.
fn _at(msg: Str, off: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, msg);
  builder.sb_push_str(&mut sb, " at offset ");
  builder.sb_push_int(&mut sb, off);
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Packet framing
// --------------------------------------------------

/// True when the EOM status bit is set.
pub fn tds_status_is_eom(status: Int) -> Bool {
  return _has_bit(status, TDS_STATUS_EOM);
}

/// True when the IGNORE status bit is set.
pub fn tds_status_is_ignore(status: Int) -> Bool {
  return _has_bit(status, TDS_STATUS_IGNORE);
}

/// True when the RESETCONNECTION status bit is set.
pub fn tds_status_is_reset(status: Int) -> Bool {
  return _has_bit(status, TDS_STATUS_RESETCONNECTION);
}

/// Name of a packet type byte (`"SQL_BATCH"`, `"RPC"`, `"RESPONSE"`,
/// `"LOGIN7"`, `"SSPI"`, `"PRELOGIN"` or `"UNKNOWN"`).
pub fn tds_packet_type_name(t: Int) -> Str {
  if t == TDS_PKT_SQL_BATCH {
    return "SQL_BATCH";
  }
  if t == TDS_PKT_RPC {
    return "RPC";
  }
  if t == TDS_PKT_RESPONSE {
    return "RESPONSE";
  }
  if t == TDS_PKT_LOGIN7 {
    return "LOGIN7";
  }
  if t == TDS_PKT_SSPI {
    return "SSPI";
  }
  if t == TDS_PKT_PRELOGIN {
    return "PRELOGIN";
  }
  return "UNKNOWN";
}

/// Parse the 8-byte packet header at `off`. The declared length (big-endian,
/// including the header) must be at least 8 and must fit the buffer.
/// Errors, each naming `off` or the field offset:
///   * `mssql: negative offset`;
///   * `mssql: truncated packet header at offset off`;
///   * `mssql: bad packet length at offset off` (declared < 8);
///   * `mssql: truncated packet at offset off` (header + payload overruns).
/// Complexity: O(1).
pub fn tds_packet_parse(data: &Vec[UInt8], off: Int) -> Result[TdsPacket, Str] {
  if off < 0 {
    return _err_packet("mssql: negative offset");
  }
  if off + TDS_PACKET_HEADER_LEN > data.len() {
    return _err_packet(_at("mssql: truncated packet header", off));
  }
  let pkt_type: Int = _byte(data, off);
  let status: Int = _byte(data, off + 1);
  let length: Int = _u16be(data, off + 2);
  let spid: Int = _u16be(data, off + 4);
  let packet_id: Int = _byte(data, off + 6);
  let window: Int = _byte(data, off + 7);
  if length < TDS_PACKET_HEADER_LEN {
    return _err_packet(_at("mssql: bad packet length", off));
  }
  if off + length > data.len() {
    return _err_packet(_at("mssql: truncated packet", off));
  }
  return _ok_packet(TdsPacket{ pkt_type: pkt_type; status: status; length: length; spid: spid; packet_id: packet_id; window: window; payload_offset: off + TDS_PACKET_HEADER_LEN; next: off + length; });
}

/// Encode one packet: the 8-byte header (length = 8 + payload byte count,
/// big-endian) followed by `payload`. `pkt_type`, `status`, `packet_id` and
/// `window` keep their low byte, `spid` its low two bytes.
/// Errors: `mssql: packet too large` when 8 + payload.len() > 65535.
/// Complexity: O(payload bytes).
pub fn tds_packet_build(pkt_type: Int, status: Int, spid: Int, packet_id: Int, window: Int, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let total: Int = TDS_PACKET_HEADER_LEN + payload.len();
  if total > 65535 {
    return _err_bytes("mssql: packet too large");
  }
  var out = Vec[UInt8].new();
  _push_u8(&mut out, pkt_type);
  _push_u8(&mut out, status);
  _push_u16be(&mut out, total);
  _push_u16be(&mut out, spid);
  _push_u8(&mut out, packet_id);
  _push_u8(&mut out, window);
  _push_bytes(&mut out, payload);
  return _ok_bytes(out);
}

/// Split `payload` into packets of at most `packet_size` bytes each (header
/// included), ring the EOM status bit on the last one and increment the
/// packet id (wrapping at 255) from 1. An empty payload yields one empty
/// packet with EOM set.
/// Errors: `mssql: bad packet size` when `packet_size` is outside 8..65535.
/// Complexity: O(payload bytes).
pub fn tds_message_pack(pkt_type: Int, spid: Int, payload: &Vec[UInt8], packet_size: Int) -> Result[Vec[UInt8], Str] {
  if packet_size < TDS_PACKET_HEADER_LEN || packet_size > 65535 {
    return _err_bytes("mssql: bad packet size");
  }
  let chunk_max: Int = packet_size - TDS_PACKET_HEADER_LEN;
  var out = Vec[UInt8].new();
  if payload.len() == 0 {
    let er = tds_packet_build(pkt_type, TDS_STATUS_EOM, spid, 1, 0, payload);
    if !er.is_ok {
      return _err_bytes(er.error);
    }
    let eb: Vec[UInt8] = er.value;
    _push_bytes(&mut out, &eb);
    return _ok_bytes(out);
  }
  var offset = 0;
  var pid = 1;
  while offset < payload.len() {
    let remain: Int = payload.len() - offset;
    var n = chunk_max;
    if remain < n {
      n = remain;
    }
    var status = 0;
    if offset + n >= payload.len() {
      status = TDS_STATUS_EOM;
    }
    var chunk = Vec[UInt8].new();
    var i = 0;
    while i < n {
      chunk.push(payload[offset + i]);
      i = i + 1;
    }
    let pr = tds_packet_build(pkt_type, status, spid, pid & 255, 0, &chunk);
    if !pr.is_ok {
      return _err_bytes(pr.error);
    }
    let pb: Vec[UInt8] = pr.value;
    _push_bytes(&mut out, &pb);
    offset = offset + n;
    pid = pid + 1;
  }
  return _ok_bytes(out);
}

/// Assemble one full multi-packet message starting at `off`: walk packets
/// until the packet whose status carries EOM, concatenating their payloads.
/// Headers after the first must repeat the first packet's type.
/// Errors, each naming the failing packet offset:
///   * `mssql: negative offset`;
///   * the `tds_packet_parse` catalog;
///   * `mssql: packet type mismatch at offset off`;
///   * `mssql: message missing eom at offset off` (buffer ended first).
/// Complexity: O(message bytes).
pub fn tds_message_parse(data: &Vec[UInt8], off: Int) -> Result[TdsMessage, Str] {
  if off < 0 {
    return _err_message("mssql: negative offset");
  }
  var pos = off;
  var count = 0;
  var eom = false;
  var first_type = 0;
  var first_status = 0;
  var first_spid = 0;
  var first_window = 0;
  var first_id = 0;
  var payload = Vec[UInt8].new();
  while !eom {
    if pos >= data.len() {
      return _err_message(_at("mssql: message missing eom", pos));
    }
    let pr = tds_packet_parse(data, pos);
    if !pr.is_ok {
      return _err_message(pr.error);
    }
    let p: TdsPacket = pr.value;
    if count == 0 {
      first_type = p.pkt_type;
      first_status = p.status;
      first_spid = p.spid;
      first_window = p.window;
      first_id = p.packet_id;
    } else {
      if p.pkt_type != first_type {
        return _err_message(_at("mssql: packet type mismatch", pos));
      }
    }
    var i = p.payload_offset;
    while i < p.next {
      payload.push(data[i]);
      i = i + 1;
    }
    count = count + 1;
    pos = p.next;
    if _has_bit(p.status, TDS_STATUS_EOM) {
      eom = true;
    }
  }
  return _ok_message(TdsMessage{ pkt_type: first_type; status: first_status; spid: first_spid; window: first_window; first_packet_id: first_id; packet_count: count; payload: payload; next: pos; });
}

// --------------------------------------------------
//  UTF-16LE text helper
// --------------------------------------------------

/// Decode `byte_len` bytes of UTF-16LE at `off` into an ASCII-safe Str:
/// code units 0x20..0x7E are kept, every other code unit (including NUL and
/// all non-ASCII / surrogate units) becomes '?'. The result therefore never
/// contains a NUL byte.
/// Errors, each naming `off`:
///   * `mssql: negative offset`;
///   * `mssql: negative utf16 length at offset off`;
///   * `mssql: bad utf16 length at offset off` (odd byte_len);
///   * `mssql: truncated utf16 string at offset off`.
/// Complexity: O(byte_len).
pub fn tds_utf16le_to_str(data: &Vec[UInt8], off: Int, byte_len: Int) -> Result[Str, Str] {
  if off < 0 {
    return _err_str("mssql: negative offset");
  }
  if byte_len < 0 {
    return _err_str(_at("mssql: negative utf16 length", off));
  }
  if byte_len % 2 != 0 {
    return _err_str(_at("mssql: bad utf16 length", off));
  }
  if off + byte_len > data.len() {
    return _err_str(_at("mssql: truncated utf16 string", off));
  }
  var sb = builder.sb_new();
  var i = 0;
  while i < byte_len {
    let lo: Int = _byte(data, off + i);
    let hi: Int = _byte(data, off + i + 1);
    let unit: Int = lo + hi * 256;
    if unit >= 32 && unit <= 126 {
      builder.sb_push_byte(&mut sb, unit as UInt8);
    } else {
      builder.sb_push_byte(&mut sb, 63 as UInt8);
    }
    i = i + 2;
  }
  return _ok_str(builder.sb_to_str(&sb));
}

/// Encode a Str as UTF-16LE: each byte of the Str becomes one little-endian
/// code unit. This is exact for ASCII; a non-ASCII UTF-8 byte becomes the
/// code unit U+00xx with the same byte value (documented lossy round-trip).
/// Complexity: O(s bytes).
pub fn tds_utf16le_encode(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let b: UInt8 = string.byte_at(s, i);
    out.push(b);
    out.push(0 as UInt8);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  PRELOGIN
// --------------------------------------------------

/// Parse the PRELOGIN option table starting at `off` (the token byte of the
/// first entry). Walk (token u8, offset u16 BE, length u16 BE) entries until
/// the 0xFF terminator; every offset/length pair is resolved against the
/// buffer from `off` to its end, and a copy of that range is kept in
/// `payload` for the value accessors.
/// Errors, each naming the entry offset:
///   * `mssql: negative offset`;
///   * `mssql: truncated prelogin table at offset off` (no token byte, or a
///     partial 5-byte entry);
///   * `mssql: prelogin option overruns buffer at offset off`.
/// Complexity: O(entries).
pub fn tds_prelogin_parse(data: &Vec[UInt8], off: Int) -> Result[TdsPrelogin, Str] {
  if off < 0 {
    return _err_prelogin("mssql: negative offset");
  }
  if off >= data.len() {
    return _err_prelogin(_at("mssql: truncated prelogin table", off));
  }
  var tokens = Vec[Int].new();
  var offsets = Vec[Int].new();
  var lengths = Vec[Int].new();
  var pos = off;
  var table_end = -1;
  while pos < data.len() {
    let token: Int = _byte(data, pos);
    if token == TDS_PRELOGIN_TERMINATOR {
      table_end = pos + 1;
      pos = pos + 1;
      break;
    }
    if pos + 5 > data.len() {
      return _err_prelogin(_at("mssql: truncated prelogin table", pos));
    }
    let o: Int = _u16be(data, pos + 1);
    let l: Int = _u16be(data, pos + 3);
    if o > data.len() - off {
      return _err_prelogin(_at("mssql: prelogin option overruns buffer", pos));
    }
    if l > data.len() - off - o {
      return _err_prelogin(_at("mssql: prelogin option overruns buffer", pos));
    }
    tokens.push(token);
    offsets.push(o);
    lengths.push(l);
    pos = pos + 5;
  }
  if table_end < 0 {
    return _err_prelogin(_at("mssql: truncated prelogin table", pos));
  }
  let payload: Vec[UInt8] = _copy_bytes(data, off, data.len() - off);
  return _ok_prelogin(TdsPrelogin{ tokens: tokens; offsets: offsets; lengths: lengths; payload: payload; next: table_end; });
}

/// Number of option table entries (the terminator is not counted).
pub fn tds_prelogin_entry_count(p: &TdsPrelogin) -> Int {
  return p.tokens.len();
}

/// Index of the first entry with `token`, or -1 when absent.
pub fn tds_prelogin_find(p: &TdsPrelogin, token: Int) -> Int {
  var i = 0;
  while i < p.tokens.len() {
    let t: Int = p.tokens[i];
    if t == token {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Raw value bytes of the first entry with `token` (a copy).
/// Errors: `mssql: prelogin option not found` (no offset).
pub fn tds_prelogin_value(p: &TdsPrelogin, token: Int) -> Result[Vec[UInt8], Str] {
  let idx = tds_prelogin_find(p, token);
  if idx < 0 {
    return _err_bytes("mssql: prelogin option not found");
  }
  let o: Int = p.offsets[idx];
  let l: Int = p.lengths[idx];
  let payload: Vec[UInt8] = p.payload;
  return _ok_bytes(_copy_bytes(&payload, o, l));
}

/// Decode the VERSION value: 6 bytes (major u8, minor u8, build u16 BE,
/// sub-build u16 BE).
/// Errors: `mssql: prelogin option not found` or
/// `mssql: bad prelogin version length at offset o` (value length != 6).
/// Complexity: O(1).
pub fn tds_prelogin_version_get(p: &TdsPrelogin) -> Result[TdsPreloginVersion, Str] {
  let idx = tds_prelogin_find(p, TDS_PRELOGIN_VERSION);
  if idx < 0 {
    return _err_pversion("mssql: prelogin option not found");
  }
  let o: Int = p.offsets[idx];
  let l: Int = p.lengths[idx];
  if l != 6 {
    return _err_pversion(_at("mssql: bad prelogin version length", o));
  }
  let payload: Vec[UInt8] = p.payload;
  let major: Int = _byte(&payload, o);
  let minor: Int = _byte(&payload, o + 1);
  let build: Int = _u16be(&payload, o + 2);
  let subbuild: Int = _u16be(&payload, o + 4);
  return _ok_pversion(TdsPreloginVersion{ major: major; minor: minor; build: build; subbuild: subbuild; });
}

/// Decode the ENCRYPTION value (one byte, 0..3).
/// Errors: `mssql: prelogin option not found`,
/// `mssql: bad prelogin encryption length at offset o`, or
/// `mssql: bad prelogin encryption at offset o` (byte > 3).
/// Complexity: O(1).
pub fn tds_prelogin_encryption_get(p: &TdsPrelogin) -> Result[Int, Str] {
  let idx = tds_prelogin_find(p, TDS_PRELOGIN_ENCRYPTION);
  if idx < 0 {
    return _err_int("mssql: prelogin option not found");
  }
  let o: Int = p.offsets[idx];
  let l: Int = p.lengths[idx];
  if l != 1 {
    return _err_int(_at("mssql: bad prelogin encryption length", o));
  }
  let payload: Vec[UInt8] = p.payload;
  let e: Int = _byte(&payload, o);
  if e > 3 {
    return _err_int(_at("mssql: bad prelogin encryption", o));
  }
  return _ok_int(e);
}

/// Name of an ENCRYPTION value (`"OFF"`, `"ON"`, `"NOT_SUP"`, `"REQ"` or
/// `"UNKNOWN"`).
pub fn tds_prelogin_encryption_name(e: Int) -> Str {
  if e == TDS_ENCRYPT_OFF {
    return "OFF";
  }
  if e == TDS_ENCRYPT_ON {
    return "ON";
  }
  if e == TDS_ENCRYPT_NOT_SUP {
    return "NOT_SUP";
  }
  if e == TDS_ENCRYPT_REQ {
    return "REQ";
  }
  return "UNKNOWN";
}

// Append one 5-byte PRELOGIN table entry.
fn _push_prelogin_entry(out: &mut Vec[UInt8], token: Int, off: Int, len: Int) {
  _push_u8(out, token);
  _push_u16be(out, off);
  _push_u16be(out, len);
}

/// Build the canonical PRELOGIN payload with six options in this order:
/// VERSION (6 bytes), ENCRYPTION (1 byte), INSTOPT (raw bytes), THREADID
/// (u32 BE), MARS (1 byte), FEDAUTHREQUIRED (1 byte), then the 0xFF
/// terminator; data offsets are byte offsets from the payload start.
/// Errors (no offsets; encoder):
///   * `mssql: bad encryption value` -- not 0..3;
///   * `mssql: bad mars value` / `mssql: bad fedauth value` -- not 0/1;
///   * `mssql: bad threadid` -- outside u32;
///   * `mssql: bad version` -- a version field outside its 8/16-bit range.
/// Complexity: O(instopt bytes).
pub fn tds_prelogin_build_basic(version_major: Int, version_minor: Int, version_build: Int, version_subbuild: Int, encryption: Int, instopt: &Vec[UInt8], threadid: Int, mars: Int, fedauth: Int) -> Result[Vec[UInt8], Str] {
  if encryption < 0 || encryption > 3 {
    return _err_bytes("mssql: bad encryption value");
  }
  if mars != 0 && mars != 1 {
    return _err_bytes("mssql: bad mars value");
  }
  if fedauth != 0 && fedauth != 1 {
    return _err_bytes("mssql: bad fedauth value");
  }
  if threadid < 0 || threadid > 4294967295 {
    return _err_bytes("mssql: bad threadid");
  }
  if version_major < 0 || version_major > 255 {
    return _err_bytes("mssql: bad version");
  }
  if version_minor < 0 || version_minor > 255 {
    return _err_bytes("mssql: bad version");
  }
  if version_build < 0 || version_build > 65535 {
    return _err_bytes("mssql: bad version");
  }
  if version_subbuild < 0 || version_subbuild > 65535 {
    return _err_bytes("mssql: bad version");
  }
  let table_len: Int = 31;
  let ib_version: Int = table_len;
  let ib_enc: Int = ib_version + 6;
  let ib_inst: Int = ib_enc + 1;
  let ib_thread: Int = ib_inst + instopt.len();
  let ib_mars: Int = ib_thread + 4;
  let ib_fedauth: Int = ib_mars + 1;
  var out = Vec[UInt8].new();
  _push_prelogin_entry(&mut out, TDS_PRELOGIN_VERSION, ib_version, 6);
  _push_prelogin_entry(&mut out, TDS_PRELOGIN_ENCRYPTION, ib_enc, 1);
  _push_prelogin_entry(&mut out, TDS_PRELOGIN_INSTOPT, ib_inst, instopt.len());
  _push_prelogin_entry(&mut out, TDS_PRELOGIN_THREADID, ib_thread, 4);
  _push_prelogin_entry(&mut out, TDS_PRELOGIN_MARS, ib_mars, 1);
  _push_prelogin_entry(&mut out, TDS_PRELOGIN_FEDAUTHREQUIRED, ib_fedauth, 1);
  _push_u8(&mut out, TDS_PRELOGIN_TERMINATOR);
  _push_u8(&mut out, version_major);
  _push_u8(&mut out, version_minor);
  _push_u16be(&mut out, version_build);
  _push_u16be(&mut out, version_subbuild);
  _push_u8(&mut out, encryption);
  _push_bytes(&mut out, instopt);
  _push_u32be(&mut out, threadid);
  _push_u8(&mut out, mars);
  _push_u8(&mut out, fedauth);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  LOGIN7
// --------------------------------------------------

// Read one character offset/length pair at `pair_pos` inside the LOGIN7
// structure starting at `base`; the byte count is two per declared
// character. Reports at the pair's own offset when the field overruns the
// declared total length.
fn _login7_text_field(data: &Vec[UInt8], base: Int, total: Int, pair_pos: Int) -> Result[Vec[UInt8], Str] {
  let fld_off: Int = _u16le(data, base + pair_pos);
  let count: Int = _u16le(data, base + pair_pos + 2);
  let byte_len: Int = count * 2;
  if fld_off + byte_len > total {
    return _err_bytes(_at("mssql: login7 field overruns buffer", base + pair_pos));
  }
  return _ok_bytes(_copy_bytes(data, base + fld_off, byte_len));
}

// Read one byte-length offset/length pair (the extension block and SSPI).
fn _login7_byte_field(data: &Vec[UInt8], base: Int, total: Int, pair_pos: Int) -> Result[Vec[UInt8], Str] {
  let fld_off: Int = _u16le(data, base + pair_pos);
  let count: Int = _u16le(data, base + pair_pos + 2);
  if fld_off + count > total {
    return _err_bytes(_at("mssql: login7 field overruns buffer", base + pair_pos));
  }
  return _ok_bytes(_copy_bytes(data, base + fld_off, count));
}

// True when a raw text field holds a whole number of UTF-16LE characters.
fn _login7_even(v: &Vec[UInt8]) -> Bool {
  return v.len() % 2 == 0;
}

/// Parse the LOGIN7 structure at `off` (the Length field). Every offset in
/// the field table is relative to the structure start; character fields copy
/// two bytes per declared character, the extension block copies its byte
/// count, the password keeps its raw (obfuscated) bytes, and the SSPI block
/// uses cbSSPI unless it is 0xFFFF, in which case cbSSPILong is used.
/// Errors, each naming `off` or the offending pair offset:
///   * `mssql: negative offset`;
///   * `mssql: truncated login7 header at offset off` (< 94 bytes);
///   * `mssql: bad login7 length at offset off` (declared < 94);
///   * `mssql: truncated login7 at offset off` (declared total overruns);
///   * `mssql: login7 field overruns buffer at offset pair`.
/// Complexity: O(total length).
pub fn tds_login7_parse(data: &Vec[UInt8], off: Int) -> Result[TdsLogin7, Str] {
  if off < 0 {
    return _err_login7("mssql: negative offset");
  }
  if off + TDS_LOGIN7_FIXED_LEN > data.len() {
    return _err_login7(_at("mssql: truncated login7 header", off));
  }
  let total: Int = _u32le(data, off);
  if total < TDS_LOGIN7_FIXED_LEN {
    return _err_login7(_at("mssql: bad login7 length", off));
  }
  if off + total > data.len() {
    return _err_login7(_at("mssql: truncated login7", off));
  }
  let hr = _login7_text_field(data, off, total, 36);
  if !hr.is_ok {
    return _err_login7(hr.error);
  }
  let hostname: Vec[UInt8] = hr.value;
  let ur = _login7_text_field(data, off, total, 40);
  if !ur.is_ok {
    return _err_login7(ur.error);
  }
  let username: Vec[UInt8] = ur.value;
  let pr = _login7_text_field(data, off, total, 44);
  if !pr.is_ok {
    return _err_login7(pr.error);
  }
  let password: Vec[UInt8] = pr.value;
  let ar = _login7_text_field(data, off, total, 48);
  if !ar.is_ok {
    return _err_login7(ar.error);
  }
  let app_name: Vec[UInt8] = ar.value;
  let sr = _login7_text_field(data, off, total, 52);
  if !sr.is_ok {
    return _err_login7(sr.error);
  }
  let server_name: Vec[UInt8] = sr.value;
  let er = _login7_byte_field(data, off, total, 56);
  if !er.is_ok {
    return _err_login7(er.error);
  }
  let extension: Vec[UInt8] = er.value;
  let lr = _login7_text_field(data, off, total, 60);
  if !lr.is_ok {
    return _err_login7(lr.error);
  }
  let library: Vec[UInt8] = lr.value;
  let gr = _login7_text_field(data, off, total, 64);
  if !gr.is_ok {
    return _err_login7(gr.error);
  }
  let language: Vec[UInt8] = gr.value;
  let dr = _login7_text_field(data, off, total, 68);
  if !dr.is_ok {
    return _err_login7(dr.error);
  }
  let database: Vec[UInt8] = dr.value;
  let client_id: Vec[UInt8] = _copy_bytes(data, off + 72, 6);
  let sspi_cb: Int = _u16le(data, off + TDS_LOGIN7_OFF_SSPI + 2);
  var sspi_len = sspi_cb;
  if sspi_cb == 65535 {
    sspi_len = _u32le(data, off + TDS_LOGIN7_OFF_SSPI_LONG);
  }
  let ib_sspi: Int = _u16le(data, off + TDS_LOGIN7_OFF_SSPI);
  if ib_sspi + sspi_len > total {
    return _err_login7(_at("mssql: login7 field overruns buffer", off + TDS_LOGIN7_OFF_SSPI));
  }
  let sspi: Vec[UInt8] = _copy_bytes(data, off + ib_sspi, sspi_len);
  let atr = _login7_text_field(data, off, total, 82);
  if !atr.is_ok {
    return _err_login7(atr.error);
  }
  let attach_db_file: Vec[UInt8] = atr.value;
  let chr = _login7_text_field(data, off, total, 86);
  if !chr.is_ok {
    return _err_login7(chr.error);
  }
  let change_password: Vec[UInt8] = chr.value;
  let tds_version: Int = _u32le(data, off + 4);
  let packet_size: Int = _u32le(data, off + 8);
  let client_prog_version: Int = _u32le(data, off + 12);
  let client_pid: Int = _u32le(data, off + 16);
  let connection_id: Int = _u32le(data, off + 20);
  let option_flags1: Int = _byte(data, off + 24);
  let option_flags2: Int = _byte(data, off + 25);
  let type_flags: Int = _byte(data, off + 26);
  let option_flags3: Int = _byte(data, off + 27);
  let client_timezone: Int = _i32le(data, off + 28);
  let client_lcid: Int = _u32le(data, off + 32);
  return _ok_login7(TdsLogin7{ total_length: total; tds_version: tds_version; packet_size: packet_size; client_prog_version: client_prog_version; client_pid: client_pid; connection_id: connection_id; option_flags1: option_flags1; option_flags2: option_flags2; type_flags: type_flags; option_flags3: option_flags3; client_timezone: client_timezone; client_lcid: client_lcid; hostname: hostname; username: username; password: password; app_name: app_name; server_name: server_name; extension: extension; library: library; language: language; database: database; client_id: client_id; attach_db_file: attach_db_file; change_password: change_password; sspi: sspi; sspi_length: sspi_len; next: off + total; });
}

/// Build a LOGIN7 structure from `l` (the `total_length` and `next` fields
/// of the argument are ignored and recomputed). Data fields are laid out in
/// this order after the fixed 94-byte area: hostname, username, password,
/// app name, server name, extension, library, language, database, attached
/// database file, change password, SSPI. Text fields must hold whole
/// UTF-16LE characters (even byte counts); the extension block and SSPI may
/// be odd, each field starts two-byte aligned and SSPI four-byte aligned
/// (padding bytes are zero).
/// Errors (no offsets; encoder):
///   * `mssql: login7 text field must be even` -- odd text byte count;
///   * `mssql: client id must be 6 bytes`;
///   * `mssql: login7 too large` -- total length above 65535 (u16 offsets).
/// Complexity: O(total length).
pub fn tds_login7_build(l: &TdsLogin7) -> Result[Vec[UInt8], Str] {
  let hostname: Vec[UInt8] = l.hostname;
  let username: Vec[UInt8] = l.username;
  let password: Vec[UInt8] = l.password;
  let app_name: Vec[UInt8] = l.app_name;
  let server_name: Vec[UInt8] = l.server_name;
  let extension: Vec[UInt8] = l.extension;
  let library: Vec[UInt8] = l.library;
  let language: Vec[UInt8] = l.language;
  let database: Vec[UInt8] = l.database;
  let attach_db_file: Vec[UInt8] = l.attach_db_file;
  let change_password: Vec[UInt8] = l.change_password;
  let sspi: Vec[UInt8] = l.sspi;
  let client_id: Vec[UInt8] = l.client_id;
  if !_login7_even(&hostname) {
    return _err_bytes("mssql: login7 text field must be even");
  }
  if !_login7_even(&username) {
    return _err_bytes("mssql: login7 text field must be even");
  }
  if !_login7_even(&password) {
    return _err_bytes("mssql: login7 text field must be even");
  }
  if !_login7_even(&app_name) {
    return _err_bytes("mssql: login7 text field must be even");
  }
  if !_login7_even(&server_name) {
    return _err_bytes("mssql: login7 text field must be even");
  }
  if !_login7_even(&library) {
    return _err_bytes("mssql: login7 text field must be even");
  }
  if !_login7_even(&language) {
    return _err_bytes("mssql: login7 text field must be even");
  }
  if !_login7_even(&database) {
    return _err_bytes("mssql: login7 text field must be even");
  }
  if !_login7_even(&attach_db_file) {
    return _err_bytes("mssql: login7 text field must be even");
  }
  if !_login7_even(&change_password) {
    return _err_bytes("mssql: login7 text field must be even");
  }
  if client_id.len() != 6 {
    return _err_bytes("mssql: client id must be 6 bytes");
  }
  var body = Vec[UInt8].new();
  var pos = TDS_LOGIN7_FIXED_LEN;
  let ib_host: Int = pos;
  let cb_host: Int = hostname.len() / 2;
  _push_bytes(&mut body, &hostname);
  pos = pos + hostname.len();
  let ib_user: Int = pos;
  let cb_user: Int = username.len() / 2;
  _push_bytes(&mut body, &username);
  pos = pos + username.len();
  let ib_pass: Int = pos;
  let cb_pass: Int = password.len() / 2;
  _push_bytes(&mut body, &password);
  pos = pos + password.len();
  let ib_app: Int = pos;
  let cb_app: Int = app_name.len() / 2;
  _push_bytes(&mut body, &app_name);
  pos = pos + app_name.len();
  let ib_server: Int = pos;
  let cb_server: Int = server_name.len() / 2;
  _push_bytes(&mut body, &server_name);
  pos = pos + server_name.len();
  let ib_ext: Int = pos;
  let cb_ext: Int = extension.len();
  _push_bytes(&mut body, &extension);
  pos = pos + extension.len();
  if pos % 2 != 0 {
    _push_u8(&mut body, 0);
    pos = pos + 1;
  }
  let ib_lib: Int = pos;
  let cb_lib: Int = library.len() / 2;
  _push_bytes(&mut body, &library);
  pos = pos + library.len();
  let ib_lang: Int = pos;
  let cb_lang: Int = language.len() / 2;
  _push_bytes(&mut body, &language);
  pos = pos + language.len();
  let ib_db: Int = pos;
  let cb_db: Int = database.len() / 2;
  _push_bytes(&mut body, &database);
  pos = pos + database.len();
  let ib_atch: Int = pos;
  let cb_atch: Int = attach_db_file.len() / 2;
  _push_bytes(&mut body, &attach_db_file);
  pos = pos + attach_db_file.len();
  let ib_change: Int = pos;
  let cb_change: Int = change_password.len() / 2;
  _push_bytes(&mut body, &change_password);
  pos = pos + change_password.len();
  while pos % 4 != 0 {
    _push_u8(&mut body, 0);
    pos = pos + 1;
  }
  let ib_sspi: Int = pos;
  var cb_sspi = sspi.len();
  var cb_sspi_long = 0;
  if sspi.len() > 65534 {
    cb_sspi = 65535;
    cb_sspi_long = sspi.len();
  }
  _push_bytes(&mut body, &sspi);
  pos = pos + sspi.len();
  let total: Int = pos;
  if ib_sspi > 65535 {
    return _err_bytes("mssql: login7 too large");
  }
  var out = Vec[UInt8].new();
  _push_u32le(&mut out, total);
  _push_u32le(&mut out, l.tds_version);
  _push_u32le(&mut out, l.packet_size);
  _push_u32le(&mut out, l.client_prog_version);
  _push_u32le(&mut out, l.client_pid & 4294967295);
  _push_u32le(&mut out, l.connection_id);
  _push_u8(&mut out, l.option_flags1);
  _push_u8(&mut out, l.option_flags2);
  _push_u8(&mut out, l.type_flags);
  _push_u8(&mut out, l.option_flags3);
  _push_i32le(&mut out, l.client_timezone);
  _push_u32le(&mut out, l.client_lcid);
  _push_u16le(&mut out, ib_host);
  _push_u16le(&mut out, cb_host);
  _push_u16le(&mut out, ib_user);
  _push_u16le(&mut out, cb_user);
  _push_u16le(&mut out, ib_pass);
  _push_u16le(&mut out, cb_pass);
  _push_u16le(&mut out, ib_app);
  _push_u16le(&mut out, cb_app);
  _push_u16le(&mut out, ib_server);
  _push_u16le(&mut out, cb_server);
  _push_u16le(&mut out, ib_ext);
  _push_u16le(&mut out, cb_ext);
  _push_u16le(&mut out, ib_lib);
  _push_u16le(&mut out, cb_lib);
  _push_u16le(&mut out, ib_lang);
  _push_u16le(&mut out, cb_lang);
  _push_u16le(&mut out, ib_db);
  _push_u16le(&mut out, cb_db);
  var i = 0;
  while i < 6 {
    out.push(client_id[i]);
    i = i + 1;
  }
  _push_u16le(&mut out, ib_sspi);
  _push_u16le(&mut out, cb_sspi);
  _push_u16le(&mut out, ib_atch);
  _push_u16le(&mut out, cb_atch);
  _push_u16le(&mut out, ib_change);
  _push_u16le(&mut out, cb_change);
  _push_u32le(&mut out, cb_sspi_long);
  _push_bytes(&mut out, &body);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  TYPE_INFO
// --------------------------------------------------

// True for the canonical fixed-length types (MS-TDS 2.2.5.5.1.2): their
// TYPE_INFO is only the token byte and their row value width is implicit.
fn _type_is_plain_fixed(token: Int) -> Bool {
  if token == TDS_TYPE_INT1 {
    return true;
  }
  if token == TDS_TYPE_BIT {
    return true;
  }
  if token == TDS_TYPE_INT2 {
    return true;
  }
  if token == TDS_TYPE_INT4 {
    return true;
  }
  if token == TDS_TYPE_DATETIME4 {
    return true;
  }
  if token == TDS_TYPE_FLT4 {
    return true;
  }
  if token == TDS_TYPE_MONEY {
    return true;
  }
  if token == TDS_TYPE_DATETIME {
    return true;
  }
  if token == TDS_TYPE_FLT8 {
    return true;
  }
  if token == TDS_TYPE_INT8 {
    return true;
  }
  return false;
}

// Implicit row value width of a fixed-length type (0 when not fixed).
fn _fixed_width(token: Int) -> Int {
  if token == TDS_TYPE_INT1 || token == TDS_TYPE_BIT {
    return 1;
  }
  if token == TDS_TYPE_INT2 {
    return 2;
  }
  if token == TDS_TYPE_INT4 || token == TDS_TYPE_DATETIME4 || token == TDS_TYPE_FLT4 {
    return 4;
  }
  if token == TDS_TYPE_MONEY || token == TDS_TYPE_DATETIME || token == TDS_TYPE_FLT8 || token == TDS_TYPE_INT8 {
    return 8;
  }
  return 0;
}

// True for the nullable "N" types (MS-TDS 2.2.5.5.1.3): TYPE_INFO carries a
// 1-byte max/size length (DECIMALN/NUMERICN add precision and scale) and the
// row value carries a 1-byte length (0 = NULL).
fn _type_is_nullable_n(token: Int) -> Bool {
  if token == TDS_TYPE_INTN {
    return true;
  }
  if token == TDS_TYPE_BITN {
    return true;
  }
  if token == TDS_TYPE_FLTN {
    return true;
  }
  if token == TDS_TYPE_MONEYN {
    return true;
  }
  if token == TDS_TYPE_DATETIMEN {
    return true;
  }
  if token == TDS_TYPE_GUIDN {
    return true;
  }
  if token == TDS_TYPE_DECIMALN {
    return true;
  }
  if token == TDS_TYPE_NUMERICN {
    return true;
  }
  return false;
}

// True for the variable-length types whose TYPE_INFO carries a u16 max
// length (plus a collation for the character ones).
fn _type_is_variable(token: Int) -> Bool {
  if token == TDS_TYPE_BIGVARBIN {
    return true;
  }
  if token == TDS_TYPE_BIGBINARY {
    return true;
  }
  if token == TDS_TYPE_BIGVARCHAR {
    return true;
  }
  if token == TDS_TYPE_BIGCHAR {
    return true;
  }
  if token == TDS_TYPE_NVARCHAR {
    return true;
  }
  if token == TDS_TYPE_NCHAR {
    return true;
  }
  return false;
}

// True for the UTF-16 types whose row length prefix counts characters.
fn _type_is_unicode(token: Int) -> Bool {
  if token == TDS_TYPE_NVARCHAR {
    return true;
  }
  if token == TDS_TYPE_NCHAR {
    return true;
  }
  if token == TDS_TYPE_NTEXT {
    return true;
  }
  return false;
}

// True for the types whose TYPE_INFO carries a 5-byte collation.
fn _type_has_collation(token: Int) -> Bool {
  if token == TDS_TYPE_BIGVARCHAR {
    return true;
  }
  if token == TDS_TYPE_BIGCHAR {
    return true;
  }
  if token == TDS_TYPE_NVARCHAR {
    return true;
  }
  if token == TDS_TYPE_NCHAR {
    return true;
  }
  if token == TDS_TYPE_TEXT {
    return true;
  }
  if token == TDS_TYPE_NTEXT {
    return true;
  }
  return false;
}

// Pack the 5-byte collation at `off` little-endian into one Int.
fn _pack_collation(data: &Vec[UInt8], off: Int) -> Int {
  return _u32le(data, off) + _byte(data, off + 4) * 4294967296;
}

/// LCID field of a packed 5-byte collation (low 20 bits).
pub fn tds_collation_lcid(c: Int) -> Int {
  return c % 1048576;
}

/// Flags byte of a packed collation (bits 20..27).
pub fn tds_collation_flags(c: Int) -> Int {
  return (c / 1048576) % 256;
}

/// Version nibble of a packed collation (bits 28..31).
pub fn tds_collation_version(c: Int) -> Int {
  return (c / 268435456) % 16;
}

/// Sort id byte of a packed collation (byte 5).
pub fn tds_collation_sortid(c: Int) -> Int {
  return (c / 4294967296) % 256;
}

// TYPE_INFO with just `token`, `size` and `next` set.
fn _typeinfo_sized(token: Int, size: Int, next: Int) -> TdsTypeInfo {
  return TdsTypeInfo{ token: token; size: size; precision: -1; scale: -1; collation: -1; collation_offset: -1; name1_offset: -1; name1_length: -1; name2_offset: -1; name2_length: -1; name3_offset: -1; name3_length: -1; asm_offset: -1; asm_length: -1; next: next; };
}

// All-absent TYPE_INFO with just `token` and `next` set.
fn _typeinfo_zero(token: Int, next: Int) -> TdsTypeInfo {
  return _typeinfo_sized(token, -1, next);
}

/// Parse one TYPE_INFO at `off` (the type token byte).
/// Errors, each naming `off`:
///   * `mssql: negative offset`;
///   * `mssql: truncated type info at offset off`;
///   * `mssql: unsupported type token at offset off`;
///   * `mssql: bad xml schema flag at offset off`.
/// Complexity: O(name bytes).
pub fn tds_typeinfo_parse(data: &Vec[UInt8], off: Int) -> Result[TdsTypeInfo, Str] {
  if off < 0 {
    return _err_typeinfo("mssql: negative offset");
  }
  if off >= data.len() {
    return _err_typeinfo(_at("mssql: truncated type info", off));
  }
  let token: Int = _byte(data, off);
  if token == TDS_TYPE_NULL {
    return _ok_typeinfo(_typeinfo_zero(token, off + 1));
  }
  if _type_is_plain_fixed(token) {
    return _ok_typeinfo(_typeinfo_sized(token, _fixed_width(token), off + 1));
  }
  if _type_is_nullable_n(token) {
    return _typeinfo_fixed(data, off, token);
  }
  if _type_is_variable(token) {
    return _typeinfo_variable(data, off, token);
  }
  if token == TDS_TYPE_XML || token == TDS_TYPE_UDT {
    return _typeinfo_special(data, off, token);
  }
  if token == TDS_TYPE_TEXT || token == TDS_TYPE_IMAGE || token == TDS_TYPE_NTEXT {
    return _typeinfo_legacy(data, off, token);
  }
  return _err_typeinfo(_at("mssql: unsupported type token", off));
}

// Nullable "N" types: DECIMALN/NUMERICN carry size + precision + scale,
// the rest a single size byte.
fn _typeinfo_fixed(data: &Vec[UInt8], off: Int, token: Int) -> Result[TdsTypeInfo, Str] {
  if token == TDS_TYPE_DECIMALN || token == TDS_TYPE_NUMERICN {
    if off + 4 > data.len() {
      return _err_typeinfo(_at("mssql: truncated type info", off));
    }
    let size: Int = _byte(data, off + 1);
    let precision: Int = _byte(data, off + 2);
    let scale: Int = _byte(data, off + 3);
    return _ok_typeinfo(TdsTypeInfo{ token: token; size: size; precision: precision; scale: scale; collation: -1; collation_offset: -1; name1_offset: -1; name1_length: -1; name2_offset: -1; name2_length: -1; name3_offset: -1; name3_length: -1; asm_offset: -1; asm_length: -1; next: off + 4; });
  }
  if off + 2 > data.len() {
    return _err_typeinfo(_at("mssql: truncated type info", off));
  }
  let size: Int = _byte(data, off + 1);
  return _ok_typeinfo(TdsTypeInfo{ token: token; size: size; precision: -1; scale: -1; collation: -1; collation_offset: -1; name1_offset: -1; name1_length: -1; name2_offset: -1; name2_length: -1; name3_offset: -1; name3_length: -1; asm_offset: -1; asm_length: -1; next: off + 2; });
}

// Variable-length types: u16 max length and, for the character types, a
// 5-byte collation.
fn _typeinfo_variable(data: &Vec[UInt8], off: Int, token: Int) -> Result[TdsTypeInfo, Str] {
  if off + 3 > data.len() {
    return _err_typeinfo(_at("mssql: truncated type info", off));
  }
  let size: Int = _u16le(data, off + 1);
  if _type_has_collation(token) {
    if off + 8 > data.len() {
      return _err_typeinfo(_at("mssql: truncated type info", off));
    }
    let coll: Int = _pack_collation(data, off + 3);
    return _ok_typeinfo(TdsTypeInfo{ token: token; size: size; precision: -1; scale: -1; collation: coll; collation_offset: off + 3; name1_offset: -1; name1_length: -1; name2_offset: -1; name2_length: -1; name3_offset: -1; name3_length: -1; asm_offset: -1; asm_length: -1; next: off + 8; });
  }
  return _ok_typeinfo(TdsTypeInfo{ token: token; size: size; precision: -1; scale: -1; collation: -1; collation_offset: -1; name1_offset: -1; name1_length: -1; name2_offset: -1; name2_length: -1; name3_offset: -1; name3_length: -1; asm_offset: -1; asm_length: -1; next: off + 3; });
}

// XML (schema-present flag + up to three B_VARCHAR names) and UDT (u16 max
// byte size + three B_VARCHAR names + u16-length assembly name).
fn _typeinfo_special(data: &Vec[UInt8], off: Int, token: Int) -> Result[TdsTypeInfo, Str] {
  var pos = off + 1;
  var size = -1;
  if token == TDS_TYPE_UDT {
    if pos + 2 > data.len() {
      return _err_typeinfo(_at("mssql: truncated type info", off));
    }
    size = _u16le(data, pos);
    pos = pos + 2;
  }
  if token == TDS_TYPE_XML {
    if pos + 1 > data.len() {
      return _err_typeinfo(_at("mssql: truncated type info", off));
    }
    let schema: Int = _byte(data, pos);
    if schema != 0 {
      if schema != 1 {
        return _err_typeinfo(_at("mssql: bad xml schema flag", pos));
      }
      pos = pos + 1;
    } else {
      return _ok_typeinfo(_typeinfo_zero(token, pos + 1));
    }
  }
  let n1 = _b_varchar(data, pos);
  if !n1.is_ok {
    return _err_typeinfo(n1.error);
  }
  let s1: TdsNameSpan = n1.value;
  let n2 = _b_varchar(data, s1.next);
  if !n2.is_ok {
    return _err_typeinfo(n2.error);
  }
  let s2: TdsNameSpan = n2.value;
  let n3 = _b_varchar(data, s2.next);
  if !n3.is_ok {
    return _err_typeinfo(n3.error);
  }
  let s3: TdsNameSpan = n3.value;
  var pos2 = s3.next;
  var asm_off = -1;
  var asm_len = -1;
  if token == TDS_TYPE_UDT {
    if pos2 + 2 > data.len() {
      return _err_typeinfo(_at("mssql: truncated type info", off));
    }
    asm_len = _u16le(data, pos2);
    if pos2 + 2 + asm_len > data.len() {
      return _err_typeinfo(_at("mssql: truncated type info", off));
    }
    asm_off = pos2 + 2;
    pos2 = pos2 + 2 + asm_len;
  }
  return _ok_typeinfo(TdsTypeInfo{ token: token; size: size; precision: -1; scale: -1; collation: -1; collation_offset: -1; name1_offset: s1.data_offset; name1_length: s1.length; name2_offset: s2.data_offset; name2_length: s2.length; name3_offset: s3.data_offset; name3_length: s3.length; asm_offset: asm_off; asm_length: asm_len; next: pos2; });
}

// Legacy TEXT (u32 + collation), IMAGE (u32) and NTEXT (u32 + collation).
fn _typeinfo_legacy(data: &Vec[UInt8], off: Int, token: Int) -> Result[TdsTypeInfo, Str] {
  if off + 5 > data.len() {
    return _err_typeinfo(_at("mssql: truncated type info", off));
  }
  let size: Int = _u32le(data, off + 1);
  if _type_has_collation(token) {
    if off + 10 > data.len() {
      return _err_typeinfo(_at("mssql: truncated type info", off));
    }
    let coll: Int = _pack_collation(data, off + 5);
    return _ok_typeinfo(TdsTypeInfo{ token: token; size: size; precision: -1; scale: -1; collation: coll; collation_offset: off + 5; name1_offset: -1; name1_length: -1; name2_offset: -1; name2_length: -1; name3_offset: -1; name3_length: -1; asm_offset: -1; asm_length: -1; next: off + 10; });
  }
  return _ok_typeinfo(TdsTypeInfo{ token: token; size: size; precision: -1; scale: -1; collation: -1; collation_offset: -1; name1_offset: -1; name1_length: -1; name2_offset: -1; name2_length: -1; name3_offset: -1; name3_length: -1; asm_offset: -1; asm_length: -1; next: off + 5; });
}

// B_VARCHAR: 1-byte character count then that many UTF-16LE characters.
fn _b_varchar(data: &Vec[UInt8], off: Int) -> Result[TdsNameSpan, Str] {
  if off < 0 {
    return _err_namespan("mssql: negative offset");
  }
  if off + 1 > data.len() {
    return _err_namespan(_at("mssql: truncated b_varchar", off));
  }
  let count: Int = _byte(data, off);
  let byte_len: Int = count * 2;
  if off + 1 + byte_len > data.len() {
    return _err_namespan(_at("mssql: truncated b_varchar", off));
  }
  return _ok_namespan(TdsNameSpan{ data_offset: off + 1; length: byte_len; next: off + 1 + byte_len; });
}

/// Name of a TYPE_INFO token (e.g. `"INTN"`, `"INT4"`, `"NVARCHAR"`).
pub fn tds_type_token_name(t: Int) -> Str {
  if t == TDS_TYPE_NULL {
    return "NULL";
  }
  if t == TDS_TYPE_INT1 {
    return "INT1";
  }
  if t == TDS_TYPE_BIT {
    return "BIT";
  }
  if t == TDS_TYPE_INT2 {
    return "INT2";
  }
  if t == TDS_TYPE_INT4 {
    return "INT4";
  }
  if t == TDS_TYPE_DATETIME4 {
    return "DATETIME4";
  }
  if t == TDS_TYPE_FLT4 {
    return "FLT4";
  }
  if t == TDS_TYPE_MONEY {
    return "MONEY";
  }
  if t == TDS_TYPE_DATETIME {
    return "DATETIME";
  }
  if t == TDS_TYPE_FLT8 {
    return "FLT8";
  }
  if t == TDS_TYPE_INT8 {
    return "INT8";
  }
  if t == TDS_TYPE_INTN {
    return "INTN";
  }
  if t == TDS_TYPE_BITN {
    return "BITN";
  }
  if t == TDS_TYPE_FLTN {
    return "FLTN";
  }
  if t == TDS_TYPE_MONEYN {
    return "MONEYN";
  }
  if t == TDS_TYPE_DATETIMEN {
    return "DATETIMEN";
  }
  if t == TDS_TYPE_GUIDN {
    return "GUIDN";
  }
  if t == TDS_TYPE_DECIMALN {
    return "DECIMALN";
  }
  if t == TDS_TYPE_NUMERICN {
    return "NUMERICN";
  }
  if t == TDS_TYPE_BIGVARBIN {
    return "BIGVARBIN";
  }
  if t == TDS_TYPE_BIGBINARY {
    return "BIGBINARY";
  }
  if t == TDS_TYPE_BIGVARCHAR {
    return "BIGVARCHAR";
  }
  if t == TDS_TYPE_BIGCHAR {
    return "BIGCHAR";
  }
  if t == TDS_TYPE_NVARCHAR {
    return "NVARCHAR";
  }
  if t == TDS_TYPE_NCHAR {
    return "NCHAR";
  }
  if t == TDS_TYPE_XML {
    return "XML";
  }
  if t == TDS_TYPE_UDT {
    return "UDT";
  }
  if t == TDS_TYPE_TEXT {
    return "TEXT";
  }
  if t == TDS_TYPE_IMAGE {
    return "IMAGE";
  }
  if t == TDS_TYPE_NTEXT {
    return "NTEXT";
  }
  return "UNKNOWN";
}

// True when any column flag carries the fEncrypted bit.
fn _has_crypto_flag(flags: &Vec[Int]) -> Bool {
  var i = 0;
  while i < flags.len() {
    let f: Int = flags[i];
    if _has_bit(f, TDS_COL_FLAG_ENCRYPTED) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  COLMETADATA
// --------------------------------------------------

/// Parse a COLMETADATA token (0x81) at `off`. `count` 0xFFFF becomes -1
/// ("no metadata"); otherwise one entry per column is pushed into every
/// parallel vector. A trailing TDS 7.2+ crypto-metadata block (token byte
/// 0x01 + u32 length) is skipped when at least one column carries the
/// fEncrypted flag.
/// Errors, each naming `off`, the column offset or the type-info offset:
///   * `mssql: negative offset`;
///   * `mssql: token mismatch at offset off`;
///   * `mssql: truncated colmetadata at offset off`;
///   * the `tds_typeinfo_parse` catalog.
/// Complexity: O(columns + type metadata).
pub fn tds_colmetadata_parse(data: &Vec[UInt8], off: Int) -> Result[TdsColMeta, Str] {
  if off < 0 {
    return _err_colmeta("mssql: negative offset");
  }
  if off + 1 > data.len() {
    return _err_colmeta(_at("mssql: truncated colmetadata", off));
  }
  let token: Int = _byte(data, off);
  if token != TDS_TOKEN_COLMETADATA {
    return _err_colmeta(_at("mssql: token mismatch", off));
  }
  if off + 3 > data.len() {
    return _err_colmeta(_at("mssql: truncated colmetadata", off));
  }
  let raw_count: Int = _u16le(data, off + 1);
  var count = raw_count;
  if raw_count == 65535 {
    count = -1;
  }
  var usertypes = Vec[Int].new();
  var flags = Vec[Int].new();
  var type_tokens = Vec[Int].new();
  var type_sizes = Vec[Int].new();
  var precisions = Vec[Int].new();
  var scales = Vec[Int].new();
  var collations = Vec[Int].new();
  var collation_offsets = Vec[Int].new();
  var name1_offsets = Vec[Int].new();
  var name1_lengths = Vec[Int].new();
  var name2_offsets = Vec[Int].new();
  var name2_lengths = Vec[Int].new();
  var name3_offsets = Vec[Int].new();
  var name3_lengths = Vec[Int].new();
  var asm_offsets = Vec[Int].new();
  var asm_lengths = Vec[Int].new();
  var pos = off + 3;
  var i = 0;
  while i < count {
    if pos + 6 > data.len() {
      return _err_colmeta(_at("mssql: truncated colmetadata", pos));
    }
    let usertype: Int = _u32le(data, pos);
    let flag: Int = _u16le(data, pos + 4);
    let tr = tds_typeinfo_parse(data, pos + 6);
    if !tr.is_ok {
      return _err_colmeta(tr.error);
    }
    let ti: TdsTypeInfo = tr.value;
    usertypes.push(usertype);
    flags.push(flag);
    type_tokens.push(ti.token);
    type_sizes.push(ti.size);
    precisions.push(ti.precision);
    scales.push(ti.scale);
    collations.push(ti.collation);
    collation_offsets.push(ti.collation_offset);
    name1_offsets.push(ti.name1_offset);
    name1_lengths.push(ti.name1_length);
    name2_offsets.push(ti.name2_offset);
    name2_lengths.push(ti.name2_length);
    name3_offsets.push(ti.name3_offset);
    name3_lengths.push(ti.name3_length);
    asm_offsets.push(ti.asm_offset);
    asm_lengths.push(ti.asm_length);
    pos = ti.next;
    i = i + 1;
  }
  if count >= 0 {
    if pos < data.len() {
      let nb: Int = _byte(data, pos);
      if nb == 1 {
        if _has_crypto_flag(&flags) {
          if pos + 5 > data.len() {
            return _err_colmeta(_at("mssql: truncated colmetadata", pos));
          }
          let clen: Int = _u32le(data, pos + 1);
          if pos + 5 + clen > data.len() {
            return _err_colmeta(_at("mssql: truncated colmetadata", pos));
          }
          pos = pos + 5 + clen;
        }
      }
    }
  }
  return _ok_colmeta(TdsColMeta{ count: count; usertypes: usertypes; flags: flags; type_tokens: type_tokens; type_sizes: type_sizes; precisions: precisions; scales: scales; collations: collations; collation_offsets: collation_offsets; name1_offsets: name1_offsets; name1_lengths: name1_lengths; name2_offsets: name2_offsets; name2_lengths: name2_lengths; name3_offsets: name3_offsets; name3_lengths: name3_lengths; asm_offsets: asm_offsets; asm_lengths: asm_lengths; next: pos; });
}

// --------------------------------------------------
//  ROW / NBCROW
// --------------------------------------------------

// Test bit `bit` of a widened bitmap byte.
fn _bit_test(byte_value: Int, bit: Int) -> Bool {
  return byte_value / _pow2(bit) % 2 == 1;
}

/// Byte count of a column null bitmap: ceil(count / 8).
pub fn tds_null_bitmap_len(count: Int) -> Int {
  if count <= 0 {
    return 0;
  }
  let q: Int = count / 8;
  let r: Int = count % 8;
  if r > 0 {
    return q + 1;
  }
  return q;
}

// Parse one row value. Plain fixed-length types have an implicit width (the
// size recorded by the metadata parser) and the sign-extended integer is
// decoded for INT1/INT2/INT4/INT8 and BIT. Nullable "N" types carry a 1-byte
// length (0 = NULL); the integer is decoded for INTN/BITN and DECIMALN /
// NUMERICN carry a 1-byte length whose bytes include the sign. Variable
// types carry a u16 LE length (0xFFFF = NULL) that counts bytes except for
// the UTF-16 types (characters); XML/UDT use a u16 byte length; legacy
// TEXT/IMAGE/NTEXT use 16-byte textpointer + 8-byte timestamp + u32 length.
fn _value_span(data: &Vec[UInt8], pos: Int, token: Int, size: Int, precision: Int, scale: Int) -> Result[TdsValueSpan, Str] {
  if token == TDS_TYPE_NULL {
    return _ok_valspan(TdsValueSpan{ is_null: 1; data_offset: -1; data_length: -1; value_int: 0; next: pos; });
  }
  if _type_is_plain_fixed(token) {
    if size <= 0 || size > 16 {
      return _err_valspan(_at("mssql: bad type size", pos));
    }
    if pos + size > data.len() {
      return _err_valspan(_at("mssql: truncated row", pos));
    }
    var fvi = 0;
    if token == TDS_TYPE_INT1 || token == TDS_TYPE_INT2 || token == TDS_TYPE_INT4 || token == TDS_TYPE_INT8 {
      fvi = _le_signed(data, pos, size);
    }
    if token == TDS_TYPE_BIT {
      fvi = _byte(data, pos);
    }
    return _ok_valspan(TdsValueSpan{ is_null: 0; data_offset: pos; data_length: size; value_int: fvi; next: pos + size; });
  }
  if _type_is_nullable_n(token) {
    if size < 0 || size > 16 {
      return _err_valspan(_at("mssql: bad type size", pos));
    }
    if pos + 1 > data.len() {
      return _err_valspan(_at("mssql: truncated row", pos));
    }
    let n: Int = _byte(data, pos);
    if n == 0 {
      return _ok_valspan(TdsValueSpan{ is_null: 1; data_offset: -1; data_length: -1; value_int: 0; next: pos + 1; });
    }
    if n > size {
      return _err_valspan(_at("mssql: bad value length", pos));
    }
    if pos + 1 + n > data.len() {
      return _err_valspan(_at("mssql: truncated row", pos));
    }
    var vi = 0;
    if token == TDS_TYPE_INTN {
      vi = _le_signed(data, pos + 1, n);
    }
    if token == TDS_TYPE_BITN {
      vi = _byte(data, pos + 1);
    }
    return _ok_valspan(TdsValueSpan{ is_null: 0; data_offset: pos + 1; data_length: n; value_int: vi; next: pos + 1 + n; });
  }
  if _type_is_variable(token) {
    if pos + 2 > data.len() {
      return _err_valspan(_at("mssql: truncated row", pos));
    }
    let raw_len: Int = _u16le(data, pos);
    if raw_len == 65535 {
      return _ok_valspan(TdsValueSpan{ is_null: 1; data_offset: -1; data_length: -1; value_int: 0; next: pos + 2; });
    }
    var byte_len = raw_len;
    if _type_is_unicode(token) {
      byte_len = raw_len * 2;
    }
    if size >= 0 && byte_len > size {
      return _err_valspan(_at("mssql: bad value length", pos));
    }
    if pos + 2 + byte_len > data.len() {
      return _err_valspan(_at("mssql: truncated row", pos));
    }
    return _ok_valspan(TdsValueSpan{ is_null: 0; data_offset: pos + 2; data_length: byte_len; value_int: 0; next: pos + 2 + byte_len; });
  }
  if token == TDS_TYPE_XML || token == TDS_TYPE_UDT {
    if pos + 2 > data.len() {
      return _err_valspan(_at("mssql: truncated row", pos));
    }
    let byte_len: Int = _u16le(data, pos);
    if byte_len == 65535 {
      return _ok_valspan(TdsValueSpan{ is_null: 1; data_offset: -1; data_length: -1; value_int: 0; next: pos + 2; });
    }
    if size >= 0 && byte_len > size {
      return _err_valspan(_at("mssql: bad value length", pos));
    }
    if pos + 2 + byte_len > data.len() {
      return _err_valspan(_at("mssql: truncated row", pos));
    }
    return _ok_valspan(TdsValueSpan{ is_null: 0; data_offset: pos + 2; data_length: byte_len; value_int: 0; next: pos + 2 + byte_len; });
  }
  if token == TDS_TYPE_TEXT || token == TDS_TYPE_IMAGE || token == TDS_TYPE_NTEXT {
    if pos + 28 > data.len() {
      return _err_valspan(_at("mssql: truncated row", pos));
    }
    let dlen: Int = _u32le(data, pos + 24);
    if pos + 28 + dlen > data.len() {
      return _err_valspan(_at("mssql: truncated row", pos));
    }
    return _ok_valspan(TdsValueSpan{ is_null: 0; data_offset: pos + 28; data_length: dlen; value_int: 0; next: pos + 28 + dlen; });
  }
  return _err_valspan(_at("mssql: unsupported type token", pos));
}

// Shared ROW/NBCROW parser; `is_nbc` selects the 0xD2 layout with the null
// bitmap before the values.
fn _row_parse(data: &Vec[UInt8], off: Int, meta: &TdsColMeta, is_nbc: Bool) -> Result[TdsRow, Str] {
  if off < 0 {
    return _err_row("mssql: negative offset");
  }
  if off >= data.len() {
    return _err_row(_at("mssql: truncated row", off));
  }
  let token: Int = _byte(data, off);
  if is_nbc {
    if token != TDS_TOKEN_NBCROW {
      return _err_row(_at("mssql: token mismatch", off));
    }
  } else {
    if token != TDS_TOKEN_ROW {
      return _err_row(_at("mssql: token mismatch", off));
    }
  }
  let count: Int = meta.count;
  if count < 0 {
    return _err_row(_at("mssql: row without colmetadata", off));
  }
  var pos = off + 1;
  var bitmap = Vec[UInt8].new();
  if is_nbc {
    let bn: Int = tds_null_bitmap_len(count);
    if pos + bn > data.len() {
      return _err_row(_at("mssql: truncated row", pos));
    }
    bitmap = _copy_bytes(data, pos, bn);
    pos = pos + bn;
  }
  var value_offsets = Vec[Int].new();
  var value_lengths = Vec[Int].new();
  var value_ints = Vec[Int].new();
  var nulls = Vec[Int].new();
  var i = 0;
  while i < count {
    let t: Int = meta.type_tokens[i];
    let size: Int = meta.type_sizes[i];
    let prec: Int = meta.precisions[i];
    let sc: Int = meta.scales[i];
    var is_null = 0;
    if t == TDS_TYPE_NULL {
      is_null = 1;
    }
    if is_nbc {
      let bi: Int = i / 8;
      let bit: Int = i % 8;
      let b: Int = (bitmap[bi] as Int) & 0xFF;
      if _bit_test(b, bit) {
        is_null = 1;
      }
    }
    if is_null == 1 {
      value_offsets.push(-1);
      value_lengths.push(-1);
      value_ints.push(0);
      nulls.push(1);
    } else {
      let vr = _value_span(data, pos, t, size, prec, sc);
      if !vr.is_ok {
        return _err_row(vr.error);
      }
      let v: TdsValueSpan = vr.value;
      if v.is_null == 1 {
        value_offsets.push(-1);
        value_lengths.push(-1);
        value_ints.push(0);
        nulls.push(1);
      } else {
        value_offsets.push(v.data_offset);
        value_lengths.push(v.data_length);
        value_ints.push(v.value_int);
        nulls.push(0);
        pos = v.next;
      }
    }
    i = i + 1;
  }
  var nbc_flag = 0;
  if is_nbc {
    nbc_flag = 1;
  }
  return _ok_row(TdsRow{ is_nbc: nbc_flag; count: count; value_offsets: value_offsets; value_lengths: value_lengths; value_ints: value_ints; nulls: nulls; next: pos; });
}

/// Parse a ROW token (0xD1) at `off` against the column metadata `meta`.
/// Values follow in column order; NULL columns come from the metadata's
/// NULLTYPE or from a 0/0xFFFF length prefix.
/// Errors, each naming `off` or the value offset:
///   * `mssql: negative offset`;
///   * `mssql: token mismatch at offset off`;
///   * `mssql: row without colmetadata at offset off` (count -1);
///   * `mssql: truncated row at offset off`;
///   * `mssql: bad type size at offset off`;
///   * `mssql: bad value length at offset off`;
///   * `mssql: unsupported type token at offset off`.
/// Complexity: O(columns + value bytes).
pub fn tds_row_parse(data: &Vec[UInt8], off: Int, meta: &TdsColMeta) -> Result[TdsRow, Str] {
  return _row_parse(data, off, meta, false);
}

/// Parse an NBCROW token (0xD2) at `off`: a ceil(count/8)-byte null bitmap
/// (LSB of byte 0 = column 0) precedes the values, and only non-null
/// columns carry data. Errors as `tds_row_parse`.
/// Complexity: O(columns + value bytes).
pub fn tds_nbcrow_parse(data: &Vec[UInt8], off: Int, meta: &TdsColMeta) -> Result[TdsRow, Str] {
  return _row_parse(data, off, meta, true);
}

/// Copy the raw bytes of column `col` out of `row`. Errors:
/// `mssql: column index out of range` (no offset) and
/// `mssql: value is null` (no offset).
/// Complexity: O(value bytes).
pub fn tds_row_value(data: &Vec[UInt8], row: &TdsRow, col: Int) -> Result[Vec[UInt8], Str] {
  if col < 0 || col >= row.count {
    return _err_bytes("mssql: column index out of range");
  }
  let is_null: Int = row.nulls[col];
  if is_null == 1 {
    return _err_bytes("mssql: value is null");
  }
  let o: Int = row.value_offsets[col];
  let l: Int = row.value_lengths[col];
  return _ok_bytes(_copy_bytes(data, o, l));
}

/// Decoded integer of column `col` (meaningful for INT1/INT2/INT4/INT8, INTN,
/// BIT, BITN, else 0). Errors: `mssql: column index out of range` and
/// `mssql: value is null` (no offsets).
pub fn tds_row_int(row: &TdsRow, col: Int) -> Result[Int, Str] {
  if col < 0 || col >= row.count {
    return _err_int("mssql: column index out of range");
  }
  let is_null: Int = row.nulls[col];
  if is_null == 1 {
    return _err_int("mssql: value is null");
  }
  let v: Int = row.value_ints[col];
  return _ok_int(v);
}

// --------------------------------------------------
//  Tokens
// --------------------------------------------------

/// True for the token type bytes this package indexes.
pub fn tds_token_known(kind: Int) -> Bool {
  if kind == TDS_TOKEN_RETURNSTATUS {
    return true;
  }
  if kind == TDS_TOKEN_COLMETADATA {
    return true;
  }
  if kind == TDS_TOKEN_ORDER {
    return true;
  }
  if kind == TDS_TOKEN_ERROR {
    return true;
  }
  if kind == TDS_TOKEN_INFO {
    return true;
  }
  if kind == TDS_TOKEN_RETURNVALUE {
    return true;
  }
  if kind == TDS_TOKEN_LOGINACK {
    return true;
  }
  if kind == TDS_TOKEN_FEATUREEXTACK {
    return true;
  }
  if kind == TDS_TOKEN_ROW {
    return true;
  }
  if kind == TDS_TOKEN_NBCROW {
    return true;
  }
  if kind == TDS_TOKEN_ENVCHANGE {
    return true;
  }
  if kind == TDS_TOKEN_DONE {
    return true;
  }
  if kind == TDS_TOKEN_DONEPROC {
    return true;
  }
  if kind == TDS_TOKEN_DONEINPROC {
    return true;
  }
  return false;
}

/// Name of a token type byte (e.g. `"LOGINACK"`, `"ROW"`, `"DONE"`).
pub fn tds_token_name(kind: Int) -> Str {
  if kind == TDS_TOKEN_RETURNSTATUS {
    return "RETURNSTATUS";
  }
  if kind == TDS_TOKEN_COLMETADATA {
    return "COLMETADATA";
  }
  if kind == TDS_TOKEN_ORDER {
    return "ORDER";
  }
  if kind == TDS_TOKEN_ERROR {
    return "ERROR";
  }
  if kind == TDS_TOKEN_INFO {
    return "INFO";
  }
  if kind == TDS_TOKEN_RETURNVALUE {
    return "RETURNVALUE";
  }
  if kind == TDS_TOKEN_LOGINACK {
    return "LOGINACK";
  }
  if kind == TDS_TOKEN_FEATUREEXTACK {
    return "FEATUREEXTACK";
  }
  if kind == TDS_TOKEN_ROW {
    return "ROW";
  }
  if kind == TDS_TOKEN_NBCROW {
    return "NBCROW";
  }
  if kind == TDS_TOKEN_ENVCHANGE {
    return "ENVCHANGE";
  }
  if kind == TDS_TOKEN_DONE {
    return "DONE";
  }
  if kind == TDS_TOKEN_DONEPROC {
    return "DONEPROC";
  }
  if kind == TDS_TOKEN_DONEINPROC {
    return "DONEINPROC";
  }
  return "UNKNOWN";
}

// Empty column metadata used before the first COLMETADATA token.
fn _colmeta_zero() -> TdsColMeta {
  return TdsColMeta{ count: 0; usertypes: Vec[Int].new(); flags: Vec[Int].new(); type_tokens: Vec[Int].new(); type_sizes: Vec[Int].new(); precisions: Vec[Int].new(); scales: Vec[Int].new(); collations: Vec[Int].new(); collation_offsets: Vec[Int].new(); name1_offsets: Vec[Int].new(); name1_lengths: Vec[Int].new(); name2_offsets: Vec[Int].new(); name2_lengths: Vec[Int].new(); name3_offsets: Vec[Int].new(); name3_lengths: Vec[Int].new(); asm_offsets: Vec[Int].new(); asm_lengths: Vec[Int].new(); next: 0; };
}

// End offset of a token with a u16 LE length right after the type byte.
fn _token_len_end(data: &Vec[UInt8], pos: Int) -> Result[Int, Str] {
  if pos + 3 > data.len() {
    return _err_int(_at("mssql: truncated token", pos));
  }
  let end: Int = pos + 3 + _u16le(data, pos + 1);
  if end > data.len() {
    return _err_int(_at("mssql: truncated token", pos));
  }
  return _ok_int(end);
}

/// Walk the token stream at `off` and index every token: for token `i`,
/// `offsets[i]` is the token byte, `kinds[i]` its type and `ends[i]` the
/// offset just past it. COLMETADATA is parsed on the way so ROW/NBCROW can
/// be measured; a ROW before any COLMETADATA is rejected. An unknown token
/// is preserved raw: its span runs to the end of the buffer and the walk
/// stops there.
/// Errors, each naming the token offset:
///   * `mssql: negative offset`;
///   * `mssql: truncated token at offset off`;
///   * `mssql: row without colmetadata at offset off`;
///   * the `tds_colmetadata_parse`, `tds_row_parse` / `tds_nbcrow_parse`,
///     `tds_returnvalue_parse` and `tds_featureextack_parse` catalogs.
/// Complexity: O(tokens + payload bytes).
pub fn tds_token_walk(data: &Vec[UInt8], off: Int) -> Result[TdsTokenIndex, Str] {
  if off < 0 {
    return _err_tokenindex("mssql: negative offset");
  }
  if off >= data.len() {
    return _err_tokenindex(_at("mssql: truncated token", off));
  }
  var offsets = Vec[Int].new();
  var kinds = Vec[Int].new();
  var ends = Vec[Int].new();
  var meta: TdsColMeta = _colmeta_zero();
  var has_meta = false;
  var pos = off;
  var stop = false;
  while pos < data.len() {
    if stop {
      break;
    }
    let kind: Int = _byte(data, pos);
    var end = pos;
    if kind == TDS_TOKEN_COLMETADATA {
      let mr = tds_colmetadata_parse(data, pos);
      if !mr.is_ok {
        return _err_tokenindex(mr.error);
      }
      meta = mr.value;
      has_meta = true;
      end = meta.next;
    } elif kind == TDS_TOKEN_ROW {
      if !has_meta {
        return _err_tokenindex(_at("mssql: row without colmetadata", pos));
      }
      let rr = tds_row_parse(data, pos, &meta);
      if !rr.is_ok {
        return _err_tokenindex(rr.error);
      }
      let r: TdsRow = rr.value;
      end = r.next;
    } elif kind == TDS_TOKEN_NBCROW {
      if !has_meta {
        return _err_tokenindex(_at("mssql: row without colmetadata", pos));
      }
      let rr = tds_nbcrow_parse(data, pos, &meta);
      if !rr.is_ok {
        return _err_tokenindex(rr.error);
      }
      let r: TdsRow = rr.value;
      end = r.next;
    } elif kind == TDS_TOKEN_RETURNVALUE {
      let vr = tds_returnvalue_parse(data, pos);
      if !vr.is_ok {
        return _err_tokenindex(vr.error);
      }
      let v: TdsReturnValue = vr.value;
      end = v.next;
    } elif kind == TDS_TOKEN_FEATUREEXTACK {
      let fr = tds_featureextack_parse(data, pos);
      if !fr.is_ok {
        return _err_tokenindex(fr.error);
      }
      let f: TdsFeatureExtAck = fr.value;
      end = f.next;
    } elif kind == TDS_TOKEN_RETURNSTATUS {
      if pos + 5 > data.len() {
        return _err_tokenindex(_at("mssql: truncated token", pos));
      }
      end = pos + 5;
    } elif kind == TDS_TOKEN_DONE || kind == TDS_TOKEN_DONEPROC || kind == TDS_TOKEN_DONEINPROC {
      if pos + 13 > data.len() {
        return _err_tokenindex(_at("mssql: truncated token", pos));
      }
      end = pos + 13;
    } elif kind == TDS_TOKEN_ORDER || kind == TDS_TOKEN_ERROR || kind == TDS_TOKEN_INFO || kind == TDS_TOKEN_LOGINACK || kind == TDS_TOKEN_ENVCHANGE {
      let er = _token_len_end(data, pos);
      if !er.is_ok {
        return _err_tokenindex(er.error);
      }
      end = er.value;
    } else {
      end = data.len();
      stop = true;
    }
    offsets.push(pos);
    kinds.push(kind);
    ends.push(end);
    pos = end;
  }
  return _ok_tokenindex(TdsTokenIndex{ offsets: offsets; kinds: kinds; ends: ends; next: pos; });
}

/// Number of indexed tokens.
pub fn tds_token_count(idx: &TdsTokenIndex) -> Int {
  return idx.offsets.len();
}

/// Kind of token `i`, or -1 when out of range.
pub fn tds_token_kind_at(idx: &TdsTokenIndex, i: Int) -> Int {
  if i < 0 || i >= idx.offsets.len() {
    return -1;
  }
  let k: Int = idx.kinds[i];
  return k;
}

/// Start offset of token `i`, or -1 when out of range.
pub fn tds_token_offset_at(idx: &TdsTokenIndex, i: Int) -> Int {
  if i < 0 || i >= idx.offsets.len() {
    return -1;
  }
  let o: Int = idx.offsets[i];
  return o;
}

/// Raw bytes of token `i` (the unknown-token escape hatch; the span of an
/// unknown token runs to the end of the buffer). Errors:
/// `mssql: token index out of range` (no offset).
pub fn tds_token_raw(data: &Vec[UInt8], idx: &TdsTokenIndex, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= idx.offsets.len() {
    return _err_bytes("mssql: token index out of range");
  }
  let s: Int = idx.offsets[i];
  let e: Int = idx.ends[i];
  return _ok_bytes(_copy_bytes(data, s, e - s));
}

/// Parse a LOGINACK token (0xAD): u16 length, interface byte, big-endian
/// u32 TDS version, B_VARCHAR program name, then major/minor bytes and a
/// big-endian u16 build number.
/// Errors, each naming `off`: `mssql: negative offset`,
/// `mssql: token mismatch at offset off`,
/// `mssql: truncated token at offset off`.
/// Complexity: O(program name bytes).
pub fn tds_loginack_parse(data: &Vec[UInt8], off: Int) -> Result[TdsLoginAck, Str] {
  if off < 0 {
    return _err_loginack("mssql: negative offset");
  }
  if off + 1 > data.len() {
    return _err_loginack(_at("mssql: truncated token", off));
  }
  let token: Int = _byte(data, off);
  if token != TDS_TOKEN_LOGINACK {
    return _err_loginack(_at("mssql: token mismatch", off));
  }
  let er = _token_len_end(data, off);
  if !er.is_ok {
    return _err_loginack(er.error);
  }
  let end: Int = er.value;
  let length: Int = _u16le(data, off + 1);
  var pos = off + 3;
  if pos + 5 > end {
    return _err_loginack(_at("mssql: truncated token", off));
  }
  let iface: Int = _byte(data, pos);
  let version: Int = _u32be(data, pos + 1);
  pos = pos + 5;
  let nr = _b_varchar(data, pos);
  if !nr.is_ok {
    return _err_loginack(nr.error);
  }
  let ns: TdsNameSpan = nr.value;
  if ns.next > end {
    return _err_loginack(_at("mssql: truncated token", off));
  }
  let nr2 = tds_utf16le_to_str(data, ns.data_offset, ns.length);
  if !nr2.is_ok {
    return _err_loginack(nr2.error);
  }
  let prog_name: Str = nr2.value;
  pos = ns.next;
  if pos + 4 > end {
    return _err_loginack(_at("mssql: truncated token", off));
  }
  let major: Int = _byte(data, pos);
  let minor: Int = _byte(data, pos + 1);
  let build: Int = _u16be(data, pos + 2);
  return _ok_loginack(TdsLoginAck{ length: length; iface: iface; tds_version: version; prog_name: prog_name; major: major; minor: minor; build: build; next: end; });
}

/// Parse an ERROR (0xAA) or INFO (0xAB) token: u16 length, number u32 LE,
/// state byte, severity (class) byte, message (u16 character count then
/// UTF-16LE), server name and proc name (B_VARCHAR) and, when the token
/// length leaves room, a u32 LE line number.
/// Errors, each naming `off`: `mssql: negative offset`,
/// `mssql: token mismatch at offset off`,
/// `mssql: truncated token at offset off`.
/// Complexity: O(message bytes).
pub fn tds_error_parse(data: &Vec[UInt8], off: Int) -> Result[TdsError, Str] {
  if off < 0 {
    return _err_error("mssql: negative offset");
  }
  if off + 1 > data.len() {
    return _err_error(_at("mssql: truncated token", off));
  }
  let token: Int = _byte(data, off);
  var is_info = 0;
  if token == TDS_TOKEN_INFO {
    is_info = 1;
  } elif token != TDS_TOKEN_ERROR {
    return _err_error(_at("mssql: token mismatch", off));
  }
  let er = _token_len_end(data, off);
  if !er.is_ok {
    return _err_error(er.error);
  }
  let end: Int = er.value;
  let length: Int = _u16le(data, off + 1);
  var pos = off + 3;
  if pos + 8 > end {
    return _err_error(_at("mssql: truncated token", off));
  }
  let number: Int = _u32le(data, pos);
  let state: Int = _byte(data, pos + 4);
  let severity: Int = _byte(data, pos + 5);
  let msg_chars: Int = _u16le(data, pos + 6);
  pos = pos + 8;
  let msg_bytes: Int = msg_chars * 2;
  if pos + msg_bytes > end {
    return _err_error(_at("mssql: truncated token", off));
  }
  let mr = tds_utf16le_to_str(data, pos, msg_bytes);
  if !mr.is_ok {
    return _err_error(mr.error);
  }
  let message: Str = mr.value;
  pos = pos + msg_bytes;
  let sr = _b_varchar(data, pos);
  if !sr.is_ok {
    return _err_error(sr.error);
  }
  let ss: TdsNameSpan = sr.value;
  if ss.next > end {
    return _err_error(_at("mssql: truncated token", off));
  }
  let sr2 = tds_utf16le_to_str(data, ss.data_offset, ss.length);
  if !sr2.is_ok {
    return _err_error(sr2.error);
  }
  let server_name: Str = sr2.value;
  let pr = _b_varchar(data, ss.next);
  if !pr.is_ok {
    return _err_error(pr.error);
  }
  let ps: TdsNameSpan = pr.value;
  if ps.next > end {
    return _err_error(_at("mssql: truncated token", off));
  }
  let pr2 = tds_utf16le_to_str(data, ps.data_offset, ps.length);
  if !pr2.is_ok {
    return _err_error(pr2.error);
  }
  let proc_name: Str = pr2.value;
  var line = -1;
  if ps.next + 4 <= end {
    line = _u32le(data, ps.next);
  }
  return _ok_error(TdsError{ is_info: is_info; length: length; number: number; state: state; severity: severity; message: message; server_name: server_name; proc_name: proc_name; line: line; next: end; });
}

/// Name of an ENVCHANGE subtype (`"database"`, `"language"`, ... or
/// `"unknown"`).
pub fn tds_envchange_subtype_name(subtype: Int) -> Str {
  if subtype == TDS_ENV_DATABASE {
    return "database";
  }
  if subtype == TDS_ENV_LANGUAGE {
    return "language";
  }
  if subtype == TDS_ENV_CHARSET {
    return "charset";
  }
  if subtype == TDS_ENV_PACKET_SIZE {
    return "packet size";
  }
  if subtype == TDS_ENV_UNICODE_SORT {
    return "unicode sort";
  }
  if subtype == TDS_ENV_UNICODE_COMPARE {
    return "unicode compare";
  }
  if subtype == TDS_ENV_COLLATION {
    return "collation";
  }
  if subtype == TDS_ENV_BEGIN_TXN {
    return "begin transaction";
  }
  if subtype == TDS_ENV_COMMIT_TXN {
    return "commit transaction";
  }
  if subtype == TDS_ENV_ROLLBACK_TXN {
    return "rollback transaction";
  }
  if subtype == TDS_ENV_ENLIST_DTC {
    return "enlist dtc";
  }
  if subtype == TDS_ENV_DEFECT_TXN {
    return "defect transaction";
  }
  if subtype == TDS_ENV_REAL_TIME_LOG {
    return "real-time log shipping";
  }
  if subtype == TDS_ENV_PROMOTE_TXN {
    return "promote transaction";
  }
  if subtype == TDS_ENV_TXN_MANAGER {
    return "transaction manager address";
  }
  if subtype == TDS_ENV_TXN_ENDED {
    return "transaction ended";
  }
  if subtype == TDS_ENV_RESET_ACK {
    return "reset ack";
  }
  if subtype == TDS_ENV_USER_INSTANCE {
    return "user instance name";
  }
  if subtype == TDS_ENV_ROUTING {
    return "routing";
  }
  return "unknown";
}

/// Parse an ENVCHANGE token (0xE3): u16 length, subtype byte, then a new
/// value and an old value, each as a u8 length (0 = null/absent) and that
/// many raw bytes.
/// Errors, each naming `off`: `mssql: negative offset`,
/// `mssql: token mismatch at offset off`,
/// `mssql: truncated token at offset off`.
/// Complexity: O(value bytes).
pub fn tds_envchange_parse(data: &Vec[UInt8], off: Int) -> Result[TdsEnvChange, Str] {
  if off < 0 {
    return _err_envchange("mssql: negative offset");
  }
  if off + 1 > data.len() {
    return _err_envchange(_at("mssql: truncated token", off));
  }
  let token: Int = _byte(data, off);
  if token != TDS_TOKEN_ENVCHANGE {
    return _err_envchange(_at("mssql: token mismatch", off));
  }
  let er = _token_len_end(data, off);
  if !er.is_ok {
    return _err_envchange(er.error);
  }
  let end: Int = er.value;
  let length: Int = _u16le(data, off + 1);
  var pos = off + 3;
  if pos + 1 > end {
    return _err_envchange(_at("mssql: truncated token", off));
  }
  let subtype: Int = _byte(data, pos);
  pos = pos + 1;
  if pos + 1 > end {
    return _err_envchange(_at("mssql: truncated token", off));
  }
  let new_len: Int = _byte(data, pos);
  pos = pos + 1;
  var new_is_null = 0;
  var new_bytes = Vec[UInt8].new();
  if new_len == 0 {
    new_is_null = 1;
  } else {
    if pos + new_len > end {
      return _err_envchange(_at("mssql: truncated token", off));
    }
    new_bytes = _copy_bytes(data, pos, new_len);
    pos = pos + new_len;
  }
  if pos + 1 > end {
    return _err_envchange(_at("mssql: truncated token", off));
  }
  let old_len: Int = _byte(data, pos);
  pos = pos + 1;
  var old_is_null = 0;
  var old_bytes = Vec[UInt8].new();
  if old_len == 0 {
    old_is_null = 1;
  } else {
    if pos + old_len > end {
      return _err_envchange(_at("mssql: truncated token", off));
    }
    old_bytes = _copy_bytes(data, pos, old_len);
    pos = pos + old_len;
  }
  return _ok_envchange(TdsEnvChange{ length: length; subtype: subtype; new_is_null: new_is_null; old_is_null: old_is_null; new_bytes: new_bytes; old_bytes: old_bytes; next: end; });
}

/// Parse a DONE (0xFD), DONEPROC (0xFE) or DONEINPROC (0xFF) token: status
/// u16 LE, curcmd u16 LE, rowcount u64 LE. Errors, each naming `off`:
/// `mssql: negative offset`, `mssql: token mismatch at offset off`,
/// `mssql: truncated token at offset off`.
/// Complexity: O(1).
pub fn tds_done_parse(data: &Vec[UInt8], off: Int) -> Result[TdsDone, Str] {
  if off < 0 {
    return _err_done("mssql: negative offset");
  }
  if off + 1 > data.len() {
    return _err_done(_at("mssql: truncated token", off));
  }
  let token: Int = _byte(data, off);
  if token != TDS_TOKEN_DONE && token != TDS_TOKEN_DONEPROC && token != TDS_TOKEN_DONEINPROC {
    return _err_done(_at("mssql: token mismatch", off));
  }
  if off + 13 > data.len() {
    return _err_done(_at("mssql: truncated token", off));
  }
  let status: Int = _u16le(data, off + 1);
  let curcmd: Int = _u16le(data, off + 3);
  let rowcount: Int = _u64le(data, off + 5);
  return _ok_done(TdsDone{ token: token; status: status; curcmd: curcmd; rowcount: rowcount; next: off + 13; });
}

/// Parse a RETURNSTATUS token (0x79): u32 LE status. Errors, each naming
/// `off`: `mssql: negative offset`, `mssql: token mismatch at offset off`,
/// `mssql: truncated token at offset off`.
/// Complexity: O(1).
pub fn tds_returnstatus_parse(data: &Vec[UInt8], off: Int) -> Result[TdsReturnStatus, Str] {
  if off < 0 {
    return _err_returnstatus("mssql: negative offset");
  }
  if off + 1 > data.len() {
    return _err_returnstatus(_at("mssql: truncated token", off));
  }
  let token: Int = _byte(data, off);
  if token != TDS_TOKEN_RETURNSTATUS {
    return _err_returnstatus(_at("mssql: token mismatch", off));
  }
  if off + 5 > data.len() {
    return _err_returnstatus(_at("mssql: truncated token", off));
  }
  let status: Int = _u32le(data, off + 1);
  return _ok_returnstatus(TdsReturnStatus{ status: status; next: off + 5; });
}

/// Parse a RETURNVALUE token (0xAC): ordinal u16 LE, B_VARCHAR name, status
/// byte, usertype u32 LE, flags u16 LE, TYPE_INFO and one value (same rules
/// as a ROW value). Errors, each naming `off` or the failing field offset:
/// `mssql: negative offset`, `mssql: token mismatch at offset off`,
/// `mssql: truncated returnvalue at offset off`,
/// `mssql: truncated token at offset off`, `mssql: bad value length at
/// offset off`, `mssql: bad type size at offset off`,
/// `mssql: unsupported type token at offset off`, and the
/// `tds_typeinfo_parse` catalog.
/// Complexity: O(name + value bytes).
pub fn tds_returnvalue_parse(data: &Vec[UInt8], off: Int) -> Result[TdsReturnValue, Str] {
  if off < 0 {
    return _err_returnvalue("mssql: negative offset");
  }
  if off + 1 > data.len() {
    return _err_returnvalue(_at("mssql: truncated returnvalue", off));
  }
  let token: Int = _byte(data, off);
  if token != TDS_TOKEN_RETURNVALUE {
    return _err_returnvalue(_at("mssql: token mismatch", off));
  }
  var pos = off + 1;
  if pos + 2 > data.len() {
    return _err_returnvalue(_at("mssql: truncated returnvalue", off));
  }
  let ordinal: Int = _u16le(data, pos);
  pos = pos + 2;
  let nr = _b_varchar(data, pos);
  if !nr.is_ok {
    return _err_returnvalue(nr.error);
  }
  let ns: TdsNameSpan = nr.value;
  let nr2 = tds_utf16le_to_str(data, ns.data_offset, ns.length);
  if !nr2.is_ok {
    return _err_returnvalue(nr2.error);
  }
  let name: Str = nr2.value;
  pos = ns.next;
  if pos + 7 > data.len() {
    return _err_returnvalue(_at("mssql: truncated returnvalue", off));
  }
  let status: Int = _byte(data, pos);
  let usertype: Int = _u32le(data, pos + 1);
  let flags: Int = _u16le(data, pos + 5);
  pos = pos + 7;
  let tr = tds_typeinfo_parse(data, pos);
  if !tr.is_ok {
    return _err_returnvalue(tr.error);
  }
  let ti: TdsTypeInfo = tr.value;
  pos = ti.next;
  let vr = _value_span(data, pos, ti.token, ti.size, ti.precision, ti.scale);
  if !vr.is_ok {
    return _err_returnvalue(vr.error);
  }
  let v: TdsValueSpan = vr.value;
  return _ok_returnvalue(TdsReturnValue{ ordinal: ordinal; name: name; status: status; usertype: usertype; flags: flags; type_token: ti.token; type_size: ti.size; precision: ti.precision; scale: ti.scale; collation: ti.collation; is_null: v.is_null; value_offset: v.data_offset; value_length: v.data_length; value_int: v.value_int; next: v.next; });
}

/// Parse a FEATUREEXTACK token (0xAE): feature blocks of FeatureId byte,
/// u32 LE data length and data, terminated by FeatureId 0xFF.
/// Errors, each naming the block offset:
/// `mssql: negative offset`, `mssql: token mismatch at offset off`,
/// `mssql: truncated featureextack at offset off`.
/// Complexity: O(feature bytes).
pub fn tds_featureextack_parse(data: &Vec[UInt8], off: Int) -> Result[TdsFeatureExtAck, Str] {
  if off < 0 {
    return _err_featureack("mssql: negative offset");
  }
  if off + 1 > data.len() {
    return _err_featureack(_at("mssql: truncated featureextack", off));
  }
  let token: Int = _byte(data, off);
  if token != TDS_TOKEN_FEATUREEXTACK {
    return _err_featureack(_at("mssql: token mismatch", off));
  }
  var ids = Vec[Int].new();
  var offsets = Vec[Int].new();
  var lengths = Vec[Int].new();
  var pos = off + 1;
  var done = false;
  while !done {
    if pos + 1 > data.len() {
      return _err_featureack(_at("mssql: truncated featureextack", pos));
    }
    let id: Int = _byte(data, pos);
    if id == 255 {
      pos = pos + 1;
      done = true;
    } else {
      if pos + 5 > data.len() {
        return _err_featureack(_at("mssql: truncated featureextack", pos));
      }
      let flen: Int = _u32le(data, pos + 1);
      if pos + 5 + flen > data.len() {
        return _err_featureack(_at("mssql: truncated featureextack", pos));
      }
      ids.push(id);
      offsets.push(pos + 5);
      lengths.push(flen);
      pos = pos + 5 + flen;
    }
  }
  return _ok_featureack(TdsFeatureExtAck{ ids: ids; offsets: offsets; lengths: lengths; next: pos; });
}

/// Parse an ORDER token (0xA9): u16 LE byte length then that many u16 LE
/// ordinals (the length must be even). Errors, each naming `off`:
/// `mssql: negative offset`, `mssql: token mismatch at offset off`,
/// `mssql: truncated token at offset off`,
/// `mssql: bad order length at offset off`.
/// Complexity: O(ordinals).
pub fn tds_order_parse(data: &Vec[UInt8], off: Int) -> Result[TdsOrder, Str] {
  if off < 0 {
    return _err_order("mssql: negative offset");
  }
  if off + 1 > data.len() {
    return _err_order(_at("mssql: truncated token", off));
  }
  let token: Int = _byte(data, off);
  if token != TDS_TOKEN_ORDER {
    return _err_order(_at("mssql: token mismatch", off));
  }
  let er = _token_len_end(data, off);
  if !er.is_ok {
    return _err_order(er.error);
  }
  let end: Int = er.value;
  let length: Int = _u16le(data, off + 1);
  if length % 2 != 0 {
    return _err_order(_at("mssql: bad order length", off));
  }
  var ordinals = Vec[Int].new();
  var pos = off + 3;
  while pos < end {
    ordinals.push(_u16le(data, pos));
    pos = pos + 2;
  }
  return _ok_order(TdsOrder{ length: length; ordinals: ordinals; next: end; });
}

