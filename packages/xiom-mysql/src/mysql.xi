// XIOM -- xiom.mysql: MySQL client/server wire protocol structure codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI, no dependencies beyond xiom.std) structural codec for
// the MySQL client/server wire protocol (MySQL 8.0 / MariaDB compatible
// framing). It turns the bytes a transport would carry into typed XIOM
// values and back: no sockets, no TLS, no authentication crypto, no
// compression and no server. See SPEC.md for the byte-level layouts and the
// error catalog.
//
// Implemented:
//   * packet framing: 3-byte little-endian payload length + 1-byte sequence
//     id. A payload length of 0xFFFFFF (16777215) marks a message that
//     continues in the next packet; the message ends with the first packet
//     whose declared length is smaller, and a message whose length is an
//     exact multiple of 0xFFFFFF ends with an empty packet.
//   * initial handshake v10: protocol version 10, server version NUL-string,
//     connection id u32, auth-plugin-data part 1 (8 bytes), filler,
//     capability lower u16, character set, status flags u16, capability
//     upper u16, auth plugin data length, 10 reserved bytes,
//     auth-plugin-data part 2 and the auth plugin name NUL-string.
//   * handshake response 41: capability flags u32, max packet u32, charset,
//     23-byte filler, username NUL-string, auth response (length-encoded,
//     1-byte-length or NUL-string, chosen by capability), database, auth
//     plugin name and the connect-attrs block; the 32-byte SSL request
//     variant.
//   * length-encoded integers and strings: first byte < 0xFB is the value,
//     0xFB is NULL, 0xFC a u16, 0xFD a u24 and 0xFE a u64; 0xFF is rejected
//     as a lenenc first byte (it is the ERR packet marker).
//   * OK 0x00 (affected rows, last insert id, status, warnings, info),
//     ERR 0xFF (code, optional '#' + 5-byte SQLSTATE, message), EOF 0xFE
//     (warnings + status; only when the payload is shorter than 9 bytes) and
//     the LOCAL INFILE 0xFB marker with its filename.
//   * commands: COM_QUERY 0x03 (+ SQL), COM_INIT_DB 0x02, COM_QUIT 0x01,
//     COM_PING 0x0E and COM_STMT_PREPARE 0x16, plus the full 0x00..0x1F
//     command name table.
//   * result sets: lenenc column count, column definition packets (six
//     lenenc strings, 0x0C filler, charset, column length, type, flags,
//     decimals, two filler bytes) and text-protocol row packets (lenenc
//     string cells, 0xFB NULL).
//   * constant tables: capability flags, status flags, the full column type
//     table 0x00..0xFF and a charset-id subset.
//   * every reader is bounds-checked and its errors carry the byte offset of
//     the failing read; negative lengths, truncated packets, hostile
//     lengths and invalid lenenc first bytes are rejected deterministically.
//
// Documented boundaries:
//   * no transport: bytes in, bytes out. Packet segmentation across buffers
//     is the caller's job; mysql_read_packet consumes exactly one packet.
//   * no authentication crypto: auth response bytes are carried and never
//     checked; scramble/token computation is out of scope.
//   * binary-protocol result rows are out of scope. mysql_packet_kind
//     reports the 0x00 marker context-free and mysql_is_binary_row_header
//     detects it, but the NULL bitmap and the typed values are not decoded.
//     A text row whose first cell is empty also starts with 0x00; the
//     caller knows which protocol it asked for (COM_QUERY vs
//     COM_STMT_EXECUTE) and must disambiguate.
//   * CLIENT_SESSION_TRACK session-state payloads in OK packets are not
//     decoded: with that flag the info field is a length-encoded string on
//     the wire and the trailing state block is left to the caller.
//   * the 0xFE EOF disambiguation is "payload length < 9 bytes"; a longer
//     0xFE packet is classified as a length-encoded 8-byte value.
//   * lengths are Int (signed 64-bit): a length-encoded u64 with bit 63 set
//     is rejected as out of range instead of wrapping.
//   * strings must be valid UTF-8 and NUL-free (v0.61.3's sb_to_str aborts
//     on a 0x00); use the byte readers for arbitrary payloads.
//   * the capability table is a documented subset (bits 0..24); upper
//     capability bits are preserved raw and reported as not known by
//     mysql_capabilities_known.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; flat and parallel vectors, never Vec[StructType];
//   * Ok/Err construction is confined to the leaf helpers below;
//   * every byte read is widened with `(b as Int) & 0xFF` before Int
//     arithmetic; little-endian fields are composed byte by byte with
//     explicit multiplication, never with pointer casts;
//   * every vector element read is bound to an explicitly typed local;
//   * struct fields are never passed as `&struct.field` where a
//     `&Vec[UInt8]` parameter is expected (a local is bound first).

module xiom.mysql

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

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

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
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

// Ok(v) for Result[MysqlLenenc, Str].
fn _ok_lenenc(v: MysqlLenenc) -> Result[MysqlLenenc, Str] {
  return Ok(v);
}

// Err(m) for Result[MysqlLenenc, Str].
fn _err_lenenc(m: Str) -> Result[MysqlLenenc, Str] {
  return Err(m);
}

// Ok(v) for Result[MysqlPacketHeader, Str].
fn _ok_header(v: MysqlPacketHeader) -> Result[MysqlPacketHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[MysqlPacketHeader, Str].
fn _err_header(m: Str) -> Result[MysqlPacketHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[MysqlPacket, Str].
fn _ok_packet(v: MysqlPacket) -> Result[MysqlPacket, Str] {
  return Ok(v);
}

// Err(m) for Result[MysqlPacket, Str].
fn _err_packet(m: Str) -> Result[MysqlPacket, Str] {
  return Err(m);
}

// Ok(v) for Result[MysqlMessage, Str].
fn _ok_message(v: MysqlMessage) -> Result[MysqlMessage, Str] {
  return Ok(v);
}

// Err(m) for Result[MysqlMessage, Str].
fn _err_message(m: Str) -> Result[MysqlMessage, Str] {
  return Err(m);
}

// Ok(v) for Result[MysqlHandshake, Str].
fn _ok_handshake(v: MysqlHandshake) -> Result[MysqlHandshake, Str] {
  return Ok(v);
}

// Err(m) for Result[MysqlHandshake, Str].
fn _err_handshake(m: Str) -> Result[MysqlHandshake, Str] {
  return Err(m);
}

// Ok(v) for Result[MysqlSslRequest, Str].
fn _ok_ssl(v: MysqlSslRequest) -> Result[MysqlSslRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[MysqlSslRequest, Str].
fn _err_ssl(m: Str) -> Result[MysqlSslRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[MysqlHandshakeResponse, Str].
fn _ok_response(v: MysqlHandshakeResponse) -> Result[MysqlHandshakeResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[MysqlHandshakeResponse, Str].
fn _err_response(m: Str) -> Result[MysqlHandshakeResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[MysqlOk, Str].
fn _ok_okp(v: MysqlOk) -> Result[MysqlOk, Str] {
  return Ok(v);
}

// Err(m) for Result[MysqlOk, Str].
fn _err_okp(m: Str) -> Result[MysqlOk, Str] {
  return Err(m);
}

// Ok(v) for Result[MysqlErr, Str].
fn _ok_errp(v: MysqlErr) -> Result[MysqlErr, Str] {
  return Ok(v);
}

// Err(m) for Result[MysqlErr, Str].
fn _err_errp(m: Str) -> Result[MysqlErr, Str] {
  return Err(m);
}

// Ok(v) for Result[MysqlEof, Str].
fn _ok_eofp(v: MysqlEof) -> Result[MysqlEof, Str] {
  return Ok(v);
}

// Err(m) for Result[MysqlEof, Str].
fn _err_eofp(m: Str) -> Result[MysqlEof, Str] {
  return Err(m);
}

// Ok(v) for Result[MysqlCommand, Str].
fn _ok_command(v: MysqlCommand) -> Result[MysqlCommand, Str] {
  return Ok(v);
}

// Err(m) for Result[MysqlCommand, Str].
fn _err_command(m: Str) -> Result[MysqlCommand, Str] {
  return Err(m);
}

// Ok(v) for Result[MysqlColumn, Str].
fn _ok_column(v: MysqlColumn) -> Result[MysqlColumn, Str] {
  return Ok(v);
}

// Err(m) for Result[MysqlColumn, Str].
fn _err_column(m: Str) -> Result[MysqlColumn, Str] {
  return Err(m);
}

// Ok(v) for Result[MysqlTextRow, Str].
fn _ok_row(v: MysqlTextRow) -> Result[MysqlTextRow, Str] {
  return Ok(v);
}

// Err(m) for Result[MysqlTextRow, Str].
fn _err_row(m: Str) -> Result[MysqlTextRow, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// An append-only encoder over a byte buffer. Create with mysql_writer_new,
/// write with the mysql_write_* functions, then take the bytes with
/// mysql_writer_bytes (a copy).
pub type MysqlWriter = {
  data: Vec[UInt8];
}

/// A bounds-checked cursor reader over an immutable byte buffer. Create with
/// mysql_reader_new; all mysql_read_* functions advance pos and reject reads
/// past the end.
pub type MysqlReader = {
  data: Vec[UInt8];
  pos: Int;
}

/// A length-encoded integer as it appeared on the wire: 0xFB is NULL (only
/// meaningful inside row/OK contexts) and 0..250, 0xFC u16, 0xFD u24 and
/// 0xFE u64 produce is_null == false. A u64 with bit 63 set is rejected
/// before this type is built.
pub type MysqlLenenc = {
  is_null: Bool;
  value: Int;
}

/// A decoded packet header: a 24-bit little-endian payload length and the
/// 1-byte sequence id. The total wire size of the packet is 4 + payload_len.
pub type MysqlPacketHeader = {
  payload_len: Int;
  sequence_id: Int;
}

/// A decoded packet: header fields plus a copy of the payload.
pub type MysqlPacket = {
  payload_len: Int;
  sequence_id: Int;
  payload: Vec[UInt8];
}

/// A reassembled multi-packet message. `payload` is the concatenation of all
/// packet payloads; `packet_count` is the number of packets that carried it;
/// `first_sequence`/`last_sequence` are the sequence ids of the first and
/// last packet.
pub type MysqlMessage = {
  payload: Vec[UInt8];
  packet_count: Int;
  first_sequence: Int;
  last_sequence: Int;
}

/// A decoded initial handshake v10 packet. `capability_flags` is the 32-bit
/// combination of the two 16-bit halves. `auth_plugin_data_2` is kept raw
/// (it is NUL-padded/terminated on the wire); use
/// mysql_handshake_auth_plugin_data for the concatenation with one trailing
/// NUL removed.
pub type MysqlHandshake = {
  protocol_version: Int;
  server_version: Str;
  connection_id: Int;
  capability_flags: Int;
  character_set: Int;
  status_flags: Int;
  auth_plugin_data_len: Int;
  auth_plugin_data_1: Vec[UInt8];
  auth_plugin_data_2: Vec[UInt8];
  auth_plugin_name: Str;
}

/// A decoded 32-byte SSL request packet (the short handshake response).
pub type MysqlSslRequest = {
  capability_flags: Int;
  max_packet_size: Int;
  character_set: Int;
}

/// A decoded handshake response 41. `auth_response_kind` is one of the
/// mysql_auth_response_kind_* values and records how the bytes were framed.
/// `database` and `auth_plugin_name` are "" when their capability flags were
/// not set. `attr_names`/`attr_values` are parallel and empty when
/// CLIENT_CONNECT_ATTRS was not set.
pub type MysqlHandshakeResponse = {
  capability_flags: Int;
  max_packet_size: Int;
  character_set: Int;
  username: Str;
  auth_response_kind: Int;
  auth_response: Vec[UInt8];
  database: Str;
  auth_plugin_name: Str;
  attr_names: Vec[Str];
  attr_values: Vec[Str];
}

/// A decoded OK packet (first byte 0x00).
pub type MysqlOk = {
  affected_rows: Int;
  last_insert_id: Int;
  status_flags: Int;
  warnings: Int;
  info: Str;
}

/// A decoded ERR packet (first byte 0xFF). `has_sqlstate` is false for the
/// pre-4.1 form where the message follows the code directly.
pub type MysqlErr = {
  code: Int;
  has_sqlstate: Bool;
  sqlstate: Str;
  message: Str;
}

/// A decoded EOF packet (first byte 0xFE, payload shorter than 9 bytes).
pub type MysqlEof = {
  warnings: Int;
  status_flags: Int;
}

/// A decoded command packet. `arg` is the UTF-8 argument for the text
/// commands this codec reads (COM_QUERY, COM_INIT_DB, COM_STMT_PREPARE) and
/// "" for every other command; a command this codec does not name is
/// preserved raw in `code` with `arg` == "".
pub type MysqlCommand = {
  code: Int;
  arg: Str;
}

/// A decoded column definition packet. The six name strings are stored as
/// sent, the 0x0C filler value is validated but not stored, and the two
/// trailing filler bytes are not stored.
pub type MysqlColumn = {
  catalog: Str;
  schema: Str;
  table_name: Str;
  org_table: Str;
  name: Str;
  org_name: Str;
  charset: Int;
  column_length: Int;
  type_code: Int;
  flags: Int;
  decimals: Int;
}

/// A decoded text-protocol row. `values` and `nulls` are parallel and have
/// exactly the requested column count entries; a NULL cell keeps "" in
/// `values` with nulls[i] == true.
pub type MysqlTextRow = {
  values: Vec[Str];
  nulls: Vec[Bool];
}

// --------------------------------------------------
//  Private constants
// --------------------------------------------------

const _PACKET_HEADER_LEN: Int = 4;          // 3-byte length + 1-byte sequence
const _MAX_PAYLOAD_LEN: Int = 16777215;     // 0xFFFFFF, the continuation marker
const _SEQ_MODULUS: Int = 256;              // sequence ids wrap at 256
const _HANDSHAKE_V10: Int = 10;             // protocol version 10
const _SSL_REQUEST_LEN: Int = 32;           // 4 + 4 + 1 + 23
const _COLUMN_FILLER: Int = 12;             // 0x0C fixed-field length
const _DEFAULT_MAX_PACKET: Int = 16777216;  // conventional client max packet
const _EOF_MAX_PAYLOAD: Int = 9;            // 0xFE is EOF below this length

// Documented capability subset (bits 0..24); see SPEC.md table 1.
const _CAPS_KNOWN_MASK: Int = 33554431;     // 0x01FFFFFF
const _STATUS_KNOWN_MASK: Int = 32763;      // 0x7FFB (0x0004 is undefined)

// --------------------------------------------------
//  Public constant tables
// --------------------------------------------------

/// Protocol version carried by the initial handshake v10. Complexity: O(1).
pub fn mysql_protocol_handshake_v10() -> Int {
  return _HANDSHAKE_V10;
}

/// Packet header size in bytes: 3-byte length + 1-byte sequence id.
/// Complexity: O(1).
pub fn mysql_packet_header_len() -> Int {
  return _PACKET_HEADER_LEN;
}

/// Largest payload a single packet can declare: 16777215 (0xFFFFFF). This
/// value is also the continuation marker. Complexity: O(1).
pub fn mysql_max_payload_len() -> Int {
  return _MAX_PAYLOAD_LEN;
}

/// Conventional client max-packet-size field value (16 MiB). This is a
/// capability negotiation number, not a framing limit. Complexity: O(1).
pub fn mysql_default_max_packet_size() -> Int {
  return _DEFAULT_MAX_PACKET;
}

/// Number of distinct sequence ids (256). Complexity: O(1).
pub fn mysql_sequence_modulus() -> Int {
  return _SEQ_MODULUS;
}

/// Length of the SSL request packet: 32 bytes. Complexity: O(1).
pub fn mysql_ssl_request_len() -> Int {
  return _SSL_REQUEST_LEN;
}

/// Next sequence id after `seq` (wraps at 256). Complexity: O(1).
pub fn mysql_sequence_next(seq: Int) -> Int {
  var s = seq % _SEQ_MODULUS;
  if s < 0 {
    s = s + _SEQ_MODULUS;
  }
  return (s + 1) % _SEQ_MODULUS;
}

/// True when a declared payload length marks a multi-packet continuation
/// (payload_len == 16777215). Complexity: O(1).
pub fn mysql_packet_is_continuation(payload_len: Int) -> Bool {
  return payload_len == _MAX_PAYLOAD_LEN;
}

// ---- Capability flags (documented subset, bits 0..24) ----

/// CLIENT_LONG_PASSWORD 0x00000001. Complexity: O(1).
pub fn mysql_capability_long_password() -> Int {
  return 1;
}

/// CLIENT_FOUND_ROWS 0x00000002. Complexity: O(1).
pub fn mysql_capability_found_rows() -> Int {
  return 2;
}

/// CLIENT_LONG_FLAG 0x00000004. Complexity: O(1).
pub fn mysql_capability_long_flag() -> Int {
  return 4;
}

/// CLIENT_CONNECT_WITH_DB 0x00000008. Complexity: O(1).
pub fn mysql_capability_connect_with_db() -> Int {
  return 8;
}

/// CLIENT_NO_SCHEMA 0x00000010. Complexity: O(1).
pub fn mysql_capability_no_schema() -> Int {
  return 16;
}

/// CLIENT_COMPRESS 0x00000020. Complexity: O(1).
pub fn mysql_capability_compress() -> Int {
  return 32;
}

/// CLIENT_ODBC 0x00000040. Complexity: O(1).
pub fn mysql_capability_odbc() -> Int {
  return 64;
}

/// CLIENT_LOCAL_FILES 0x00000080. Complexity: O(1).
pub fn mysql_capability_local_files() -> Int {
  return 128;
}

/// CLIENT_IGNORE_SPACE 0x00000100. Complexity: O(1).
pub fn mysql_capability_ignore_space() -> Int {
  return 256;
}

/// CLIENT_PROTOCOL_41 0x00000200. Complexity: O(1).
pub fn mysql_capability_protocol_41() -> Int {
  return 512;
}

/// CLIENT_INTERACTIVE 0x00000400. Complexity: O(1).
pub fn mysql_capability_interactive() -> Int {
  return 1024;
}

/// CLIENT_SSL 0x00000800. Complexity: O(1).
pub fn mysql_capability_ssl() -> Int {
  return 2048;
}

/// CLIENT_IGNORE_SIGPIPE 0x00001000. Complexity: O(1).
pub fn mysql_capability_ignore_sigpipe() -> Int {
  return 4096;
}

/// CLIENT_TRANSACTIONS 0x00002000. Complexity: O(1).
pub fn mysql_capability_transactions() -> Int {
  return 8192;
}

/// CLIENT_RESERVED 0x00004000. Complexity: O(1).
pub fn mysql_capability_reserved() -> Int {
  return 16384;
}

/// CLIENT_SECURE_CONNECTION 0x00008000. Complexity: O(1).
pub fn mysql_capability_secure_connection() -> Int {
  return 32768;
}

/// CLIENT_MULTI_STATEMENTS 0x00010000. Complexity: O(1).
pub fn mysql_capability_multi_statements() -> Int {
  return 65536;
}

/// CLIENT_MULTI_RESULTS 0x00020000. Complexity: O(1).
pub fn mysql_capability_multi_results() -> Int {
  return 131072;
}

/// CLIENT_PS_MULTI_RESULTS 0x00040000. Complexity: O(1).
pub fn mysql_capability_ps_multi_results() -> Int {
  return 262144;
}

/// CLIENT_PLUGIN_AUTH 0x00080000. Complexity: O(1).
pub fn mysql_capability_plugin_auth() -> Int {
  return 524288;
}

/// CLIENT_CONNECT_ATTRS 0x00100000. Complexity: O(1).
pub fn mysql_capability_connect_attrs() -> Int {
  return 1048576;
}

/// CLIENT_PLUGIN_AUTH_LENENC_CLIENT_DATA 0x00200000. Complexity: O(1).
pub fn mysql_capability_plugin_auth_lenenc_client_data() -> Int {
  return 2097152;
}

/// CLIENT_CAN_HANDLE_EXPIRED_PASSWORDS 0x00400000. Complexity: O(1).
pub fn mysql_capability_can_handle_expired_passwords() -> Int {
  return 4194304;
}

/// CLIENT_SESSION_TRACK 0x00800000. Complexity: O(1).
pub fn mysql_capability_session_track() -> Int {
  return 8388608;
}

/// CLIENT_DEPRECATE_EOF 0x01000000. Complexity: O(1).
pub fn mysql_capability_deprecate_eof() -> Int {
  return 16777216;
}

/// True when every set bit of `caps` is named by this module's
/// mysql_capability_* table (the documented subset, bits 0..24). Bits above
/// 0x01000000 (8.0 extensions) are preserved raw and report false here.
/// Complexity: O(1).
pub fn mysql_capabilities_known(caps: Int) -> Bool {
  if caps < 0 {
    return false;
  }
  return (caps & _CAPS_KNOWN_MASK) == caps;
}

/// True when `caps` has every bit of `bit` set. `bit` is one of the
/// mysql_capability_* values. Complexity: O(1).
pub fn mysql_capability_set(caps: Int, bit: Int) -> Bool {
  return (caps & bit) == bit;
}

// ---- Status flags ----

/// SERVER_STATUS_IN_TRANS 0x0001. Complexity: O(1).
pub fn mysql_status_in_trans() -> Int {
  return 1;
}

/// SERVER_STATUS_AUTOCOMMIT 0x0002. Complexity: O(1).
pub fn mysql_status_autocommit() -> Int {
  return 2;
}

/// SERVER_MORE_RESULTS_EXISTS 0x0008. Complexity: O(1).
pub fn mysql_status_more_results_exists() -> Int {
  return 8;
}

/// SERVER_STATUS_NO_GOOD_INDEX_USED 0x0010. Complexity: O(1).
pub fn mysql_status_no_good_index_used() -> Int {
  return 16;
}

/// SERVER_STATUS_NO_INDEX_USED 0x0020. Complexity: O(1).
pub fn mysql_status_no_index_used() -> Int {
  return 32;
}

/// SERVER_STATUS_CURSOR_EXISTS 0x0040. Complexity: O(1).
pub fn mysql_status_cursor_exists() -> Int {
  return 64;
}

/// SERVER_STATUS_LAST_ROW_SENT 0x0080. Complexity: O(1).
pub fn mysql_status_last_row_sent() -> Int {
  return 128;
}

/// SERVER_STATUS_DB_DROPPED 0x0100. Complexity: O(1).
pub fn mysql_status_db_dropped() -> Int {
  return 256;
}

/// SERVER_STATUS_NO_BACKSLASH_ESCAPES 0x0200. Complexity: O(1).
pub fn mysql_status_no_backslash_escapes() -> Int {
  return 512;
}

/// SERVER_STATUS_METADATA_CHANGED 0x0400. Complexity: O(1).
pub fn mysql_status_metadata_changed() -> Int {
  return 1024;
}

/// SERVER_QUERY_WAS_SLOW 0x0800. Complexity: O(1).
pub fn mysql_status_query_was_slow() -> Int {
  return 2048;
}

/// SERVER_PS_OUT_PARAMS 0x1000. Complexity: O(1).
pub fn mysql_status_ps_out_params() -> Int {
  return 4096;
}

/// SERVER_STATUS_IN_TRANS_READONLY 0x2000. Complexity: O(1).
pub fn mysql_status_in_trans_readonly() -> Int {
  return 8192;
}

/// SERVER_SESSION_STATE_CHANGED 0x4000. Complexity: O(1).
pub fn mysql_status_session_state_changed() -> Int {
  return 16384;
}

/// True when every set bit of `s` is named by this module's mysql_status_*
/// table. Complexity: O(1).
pub fn mysql_status_flags_known(s: Int) -> Bool {
  if s < 0 {
    return false;
  }
  return (s & _STATUS_KNOWN_MASK) == s;
}

// ---- Column types (full table 0x00..0xFF) ----

/// DECIMAL 0x00. Complexity: O(1).
pub fn mysql_type_decimal() -> Int {
  return 0;
}

/// TINY 0x01. Complexity: O(1).
pub fn mysql_type_tiny() -> Int {
  return 1;
}

/// SHORT 0x02. Complexity: O(1).
pub fn mysql_type_short() -> Int {
  return 2;
}

/// LONG 0x03. Complexity: O(1).
pub fn mysql_type_long() -> Int {
  return 3;
}

/// FLOAT 0x04. Complexity: O(1).
pub fn mysql_type_float() -> Int {
  return 4;
}

/// DOUBLE 0x05. Complexity: O(1).
pub fn mysql_type_double() -> Int {
  return 5;
}

/// NULL 0x06. Complexity: O(1).
pub fn mysql_type_null() -> Int {
  return 6;
}

/// TIMESTAMP 0x07. Complexity: O(1).
pub fn mysql_type_timestamp() -> Int {
  return 7;
}

/// LONGLONG 0x08. Complexity: O(1).
pub fn mysql_type_longlong() -> Int {
  return 8;
}

/// INT24 0x09. Complexity: O(1).
pub fn mysql_type_int24() -> Int {
  return 9;
}

/// DATE 0x0A. Complexity: O(1).
pub fn mysql_type_date() -> Int {
  return 10;
}

/// TIME 0x0B. Complexity: O(1).
pub fn mysql_type_time() -> Int {
  return 11;
}

/// DATETIME 0x0C. Complexity: O(1).
pub fn mysql_type_datetime() -> Int {
  return 12;
}

/// YEAR 0x0D. Complexity: O(1).
pub fn mysql_type_year() -> Int {
  return 13;
}

/// NEWDATE 0x0E. Complexity: O(1).
pub fn mysql_type_newdate() -> Int {
  return 14;
}

/// VARCHAR 0x0F. Complexity: O(1).
pub fn mysql_type_varchar() -> Int {
  return 15;
}

/// BIT 0x10. Complexity: O(1).
pub fn mysql_type_bit() -> Int {
  return 16;
}

/// TIMESTAMP2 0x11. Complexity: O(1).
pub fn mysql_type_timestamp2() -> Int {
  return 17;
}

/// DATETIME2 0x12. Complexity: O(1).
pub fn mysql_type_datetime2() -> Int {
  return 18;
}

/// TIME2 0x13. Complexity: O(1).
pub fn mysql_type_time2() -> Int {
  return 19;
}

/// TYPED_ARRAY 0x14 (internal, 8.0 multi-valued indexes). Complexity: O(1).
pub fn mysql_type_typed_array() -> Int {
  return 20;
}

/// JSON 0xF5. Complexity: O(1).
pub fn mysql_type_json() -> Int {
  return 245;
}

/// NEWDECIMAL 0xF6. Complexity: O(1).
pub fn mysql_type_newdecimal() -> Int {
  return 246;
}

/// ENUM 0xF7. Complexity: O(1).
pub fn mysql_type_enum() -> Int {
  return 247;
}

/// SET 0xF8. Complexity: O(1).
pub fn mysql_type_set() -> Int {
  return 248;
}

/// TINY_BLOB 0xF9. Complexity: O(1).
pub fn mysql_type_tiny_blob() -> Int {
  return 249;
}

/// MEDIUM_BLOB 0xFA. Complexity: O(1).
pub fn mysql_type_medium_blob() -> Int {
  return 250;
}

/// LONG_BLOB 0xFB. Complexity: O(1).
pub fn mysql_type_long_blob() -> Int {
  return 251;
}

/// BLOB 0xFC. Complexity: O(1).
pub fn mysql_type_blob() -> Int {
  return 252;
}

/// VAR_STRING 0xFD. Complexity: O(1).
pub fn mysql_type_var_string() -> Int {
  return 253;
}

/// STRING 0xFE. Complexity: O(1).
pub fn mysql_type_string() -> Int {
  return 254;
}

/// GEOMETRY 0xFF. Complexity: O(1).
pub fn mysql_type_geometry() -> Int {
  return 255;
}

/// True for the 32 column type codes named by this module (0x00..0x14 and
/// 0xF5..0xFF). The gaps 0x15..0xF4 are reserved/unknown. Complexity: O(1).
pub fn mysql_type_known(code: Int) -> Bool {
  return _type_known(code);
}

/// Uppercase name of a column type code, or "UNKNOWN" for a reserved code.
/// Complexity: O(1).
pub fn mysql_type_name(code: Int) -> Str {
  if code == 0 { return "DECIMAL"; }
  if code == 1 { return "TINY"; }
  if code == 2 { return "SHORT"; }
  if code == 3 { return "LONG"; }
  if code == 4 { return "FLOAT"; }
  if code == 5 { return "DOUBLE"; }
  if code == 6 { return "NULL"; }
  if code == 7 { return "TIMESTAMP"; }
  if code == 8 { return "LONGLONG"; }
  if code == 9 { return "INT24"; }
  if code == 10 { return "DATE"; }
  if code == 11 { return "TIME"; }
  if code == 12 { return "DATETIME"; }
  if code == 13 { return "YEAR"; }
  if code == 14 { return "NEWDATE"; }
  if code == 15 { return "VARCHAR"; }
  if code == 16 { return "BIT"; }
  if code == 17 { return "TIMESTAMP2"; }
  if code == 18 { return "DATETIME2"; }
  if code == 19 { return "TIME2"; }
  if code == 20 { return "TYPED_ARRAY"; }
  if code == 245 { return "JSON"; }
  if code == 246 { return "NEWDECIMAL"; }
  if code == 247 { return "ENUM"; }
  if code == 248 { return "SET"; }
  if code == 249 { return "TINY_BLOB"; }
  if code == 250 { return "MEDIUM_BLOB"; }
  if code == 251 { return "LONG_BLOB"; }
  if code == 252 { return "BLOB"; }
  if code == 253 { return "VAR_STRING"; }
  if code == 254 { return "STRING"; }
  if code == 255 { return "GEOMETRY"; }
  return "UNKNOWN";
}

// ---- Charset ids (documented subset) ----

/// big5_chinese_ci charset id 1. Complexity: O(1).
pub fn mysql_charset_big5_chinese_ci() -> Int {
  return 1;
}

/// latin1_swedish_ci charset id 8. Complexity: O(1).
pub fn mysql_charset_latin1_swedish_ci() -> Int {
  return 8;
}

/// gbk_chinese_ci charset id 28. Complexity: O(1).
pub fn mysql_charset_gbk_chinese_ci() -> Int {
  return 28;
}

/// utf8_general_ci (utf8mb3) charset id 33. Complexity: O(1).
pub fn mysql_charset_utf8_general_ci() -> Int {
  return 33;
}

/// utf8mb4_general_ci charset id 45. Complexity: O(1).
pub fn mysql_charset_utf8mb4_general_ci() -> Int {
  return 45;
}

/// utf8mb4_bin charset id 46. Complexity: O(1).
pub fn mysql_charset_utf8mb4_bin() -> Int {
  return 46;
}

/// binary charset id 63. Complexity: O(1).
pub fn mysql_charset_binary() -> Int {
  return 63;
}

/// utf8mb4_unicode_ci charset id 224. Complexity: O(1).
pub fn mysql_charset_utf8mb4_unicode_ci() -> Int {
  return 224;
}

/// utf8mb4_0900_ai_ci charset id 255. Complexity: O(1).
pub fn mysql_charset_utf8mb4_0900_ai_ci() -> Int {
  return 255;
}

/// True for the nine charset ids named by this module (a documented
/// subset). Complexity: O(1).
pub fn mysql_charset_known(id: Int) -> Bool {
  if id == 1 || id == 8 || id == 28 || id == 33 || id == 63 {
    return true;
  }
  if id == 45 || id == 46 || id == 224 || id == 255 {
    return true;
  }
  return false;
}

/// Name of a charset id, or "UNKNOWN" outside the documented subset.
/// Complexity: O(1).
pub fn mysql_charset_name(id: Int) -> Str {
  if id == 1 { return "big5_chinese_ci"; }
  if id == 8 { return "latin1_swedish_ci"; }
  if id == 28 { return "gbk_chinese_ci"; }
  if id == 33 { return "utf8_general_ci"; }
  if id == 45 { return "utf8mb4_general_ci"; }
  if id == 46 { return "utf8mb4_bin"; }
  if id == 63 { return "binary"; }
  if id == 224 { return "utf8mb4_unicode_ci"; }
  if id == 255 { return "utf8mb4_0900_ai_ci"; }
  return "UNKNOWN";
}

// ---- Commands 0x00..0x1F ----

/// COM_SLEEP 0x00. Complexity: O(1).
pub fn mysql_com_sleep() -> Int {
  return 0;
}

/// COM_QUIT 0x01. Complexity: O(1).
pub fn mysql_com_quit() -> Int {
  return 1;
}

/// COM_INIT_DB 0x02. Complexity: O(1).
pub fn mysql_com_init_db() -> Int {
  return 2;
}

/// COM_QUERY 0x03. Complexity: O(1).
pub fn mysql_com_query() -> Int {
  return 3;
}

/// COM_FIELD_LIST 0x04. Complexity: O(1).
pub fn mysql_com_field_list() -> Int {
  return 4;
}

/// COM_CREATE_DB 0x05. Complexity: O(1).
pub fn mysql_com_create_db() -> Int {
  return 5;
}

/// COM_DROP_DB 0x06. Complexity: O(1).
pub fn mysql_com_drop_db() -> Int {
  return 6;
}

/// COM_REFRESH 0x07. Complexity: O(1).
pub fn mysql_com_refresh() -> Int {
  return 7;
}

/// COM_SHUTDOWN 0x08. Complexity: O(1).
pub fn mysql_com_shutdown() -> Int {
  return 8;
}

/// COM_STATISTICS 0x09. Complexity: O(1).
pub fn mysql_com_statistics() -> Int {
  return 9;
}

/// COM_PROCESS_INFO 0x0A. Complexity: O(1).
pub fn mysql_com_process_info() -> Int {
  return 10;
}

/// COM_CONNECT 0x0B. Complexity: O(1).
pub fn mysql_com_connect() -> Int {
  return 11;
}

/// COM_PROCESS_KILL 0x0C. Complexity: O(1).
pub fn mysql_com_process_kill() -> Int {
  return 12;
}

/// COM_DEBUG 0x0D. Complexity: O(1).
pub fn mysql_com_debug() -> Int {
  return 13;
}

/// COM_PING 0x0E. Complexity: O(1).
pub fn mysql_com_ping() -> Int {
  return 14;
}

/// COM_TIME 0x0F. Complexity: O(1).
pub fn mysql_com_time() -> Int {
  return 15;
}

/// COM_DELAYED_INSERT 0x10. Complexity: O(1).
pub fn mysql_com_delayed_insert() -> Int {
  return 16;
}

/// COM_CHANGE_USER 0x11. Complexity: O(1).
pub fn mysql_com_change_user() -> Int {
  return 17;
}

/// COM_BINLOG_DUMP 0x12. Complexity: O(1).
pub fn mysql_com_binlog_dump() -> Int {
  return 18;
}

/// COM_TABLE_DUMP 0x13. Complexity: O(1).
pub fn mysql_com_table_dump() -> Int {
  return 19;
}

/// COM_CONNECT_OUT 0x14. Complexity: O(1).
pub fn mysql_com_connect_out() -> Int {
  return 20;
}

/// COM_REGISTER_SLAVE 0x15. Complexity: O(1).
pub fn mysql_com_register_slave() -> Int {
  return 21;
}

/// COM_STMT_PREPARE 0x16. Complexity: O(1).
pub fn mysql_com_stmt_prepare() -> Int {
  return 22;
}

/// COM_STMT_EXECUTE 0x17. Complexity: O(1).
pub fn mysql_com_stmt_execute() -> Int {
  return 23;
}

/// COM_STMT_SEND_LONG_DATA 0x18. Complexity: O(1).
pub fn mysql_com_stmt_send_long_data() -> Int {
  return 24;
}

/// COM_STMT_CLOSE 0x19. Complexity: O(1).
pub fn mysql_com_stmt_close() -> Int {
  return 25;
}

/// COM_STMT_RESET 0x1A. Complexity: O(1).
pub fn mysql_com_stmt_reset() -> Int {
  return 26;
}

/// COM_SET_OPTION 0x1B. Complexity: O(1).
pub fn mysql_com_set_option() -> Int {
  return 27;
}

/// COM_STMT_FETCH 0x1C. Complexity: O(1).
pub fn mysql_com_stmt_fetch() -> Int {
  return 28;
}

/// COM_DAEMON 0x1D. Complexity: O(1).
pub fn mysql_com_daemon() -> Int {
  return 29;
}

/// COM_BINLOG_DUMP_GTID 0x1E. Complexity: O(1).
pub fn mysql_com_binlog_dump_gtid() -> Int {
  return 30;
}

/// COM_RESET_CONNECTION 0x1F. Complexity: O(1).
pub fn mysql_com_reset_connection() -> Int {
  return 31;
}

/// True for the 32 defined command codes (0x00..0x1F). Complexity: O(1).
pub fn mysql_command_known(code: Int) -> Bool {
  return code >= 0 && code <= 31;
}

/// Uppercase name of a command code, or "UNKNOWN" outside 0x00..0x1F.
/// Complexity: O(1).
pub fn mysql_command_name(code: Int) -> Str {
  if code == 0 { return "COM_SLEEP"; }
  if code == 1 { return "COM_QUIT"; }
  if code == 2 { return "COM_INIT_DB"; }
  if code == 3 { return "COM_QUERY"; }
  if code == 4 { return "COM_FIELD_LIST"; }
  if code == 5 { return "COM_CREATE_DB"; }
  if code == 6 { return "COM_DROP_DB"; }
  if code == 7 { return "COM_REFRESH"; }
  if code == 8 { return "COM_SHUTDOWN"; }
  if code == 9 { return "COM_STATISTICS"; }
  if code == 10 { return "COM_PROCESS_INFO"; }
  if code == 11 { return "COM_CONNECT"; }
  if code == 12 { return "COM_PROCESS_KILL"; }
  if code == 13 { return "COM_DEBUG"; }
  if code == 14 { return "COM_PING"; }
  if code == 15 { return "COM_TIME"; }
  if code == 16 { return "COM_DELAYED_INSERT"; }
  if code == 17 { return "COM_CHANGE_USER"; }
  if code == 18 { return "COM_BINLOG_DUMP"; }
  if code == 19 { return "COM_TABLE_DUMP"; }
  if code == 20 { return "COM_CONNECT_OUT"; }
  if code == 21 { return "COM_REGISTER_SLAVE"; }
  if code == 22 { return "COM_STMT_PREPARE"; }
  if code == 23 { return "COM_STMT_EXECUTE"; }
  if code == 24 { return "COM_STMT_SEND_LONG_DATA"; }
  if code == 25 { return "COM_STMT_CLOSE"; }
  if code == 26 { return "COM_STMT_RESET"; }
  if code == 27 { return "COM_SET_OPTION"; }
  if code == 28 { return "COM_STMT_FETCH"; }
  if code == 29 { return "COM_DAEMON"; }
  if code == 30 { return "COM_BINLOG_DUMP_GTID"; }
  if code == 31 { return "COM_RESET_CONNECTION"; }
  return "UNKNOWN";
}

// ---- Packet kinds ----

/// Kind of a packet whose first byte is 0x00 (OK, or a binary row header in
/// a binary result set). Complexity: O(1).
pub fn mysql_packet_kind_ok() -> Int {
  return 0;
}

/// Kind of a packet whose first byte is 0xFB (LOCAL INFILE request).
/// Complexity: O(1).
pub fn mysql_packet_kind_local_infile() -> Int {
  return 1;
}

/// Kind of a packet whose first byte is 0xFE and whose payload is shorter
/// than 9 bytes (EOF). Complexity: O(1).
pub fn mysql_packet_kind_eof() -> Int {
  return 2;
}

/// Kind of a packet whose first byte is 0xFF (ERR). Complexity: O(1).
pub fn mysql_packet_kind_err() -> Int {
  return 3;
}

/// Kind of a 0xFE packet that is 9 bytes or longer: its first byte is the
/// length-encoded 8-byte integer marker, not EOF. Complexity: O(1).
pub fn mysql_packet_kind_lenenc_8() -> Int {
  return 4;
}

/// Kind of any other packet: a length-encoded column count, a column
/// definition, a text row or an unrecognized payload. Complexity: O(1).
pub fn mysql_packet_kind_other() -> Int {
  return 5;
}

/// Kind of an empty payload (a legal zero-length message terminator).
/// Complexity: O(1).
pub fn mysql_packet_kind_empty() -> Int {
  return 6;
}

/// Context-free packet classification from the payload's first byte, with
/// the EOF-vs-lenenc 0xFE disambiguation ("shorter than 9 bytes"). The
/// caller supplies the result-set context (text vs binary, column count vs
/// row). Complexity: O(1).
pub fn mysql_packet_kind(payload: &Vec[UInt8]) -> Int {
  let n: Int = payload.len();
  if n == 0 {
    return mysql_packet_kind_empty();
  }
  let b0: Int = (payload[0] as Int) & 0xFF;
  if b0 == 0 {
    return mysql_packet_kind_ok();
  }
  if b0 == 251 {
    return mysql_packet_kind_local_infile();
  }
  if b0 == 254 {
    if n < _EOF_MAX_PAYLOAD {
      return mysql_packet_kind_eof();
    }
    return mysql_packet_kind_lenenc_8();
  }
  if b0 == 255 {
    return mysql_packet_kind_err();
  }
  return mysql_packet_kind_other();
}

/// Name of a packet kind, or "UNKNOWN". Complexity: O(1).
pub fn mysql_packet_kind_name(kind: Int) -> Str {
  if kind == 0 { return "OK"; }
  if kind == 1 { return "LOCAL_INFILE"; }
  if kind == 2 { return "EOF"; }
  if kind == 3 { return "ERR"; }
  if kind == 4 { return "LENENC_8"; }
  if kind == 5 { return "OTHER"; }
  if kind == 6 { return "EMPTY"; }
  return "UNKNOWN";
}

/// The binary-protocol row header marker byte (0x00). Complexity: O(1).
pub fn mysql_binary_row_marker() -> Int {
  return 0;
}

/// True when a payload starts with the 0x00 binary-row marker. Detection
/// only: the NULL bitmap and typed values of binary rows are out of scope.
/// In a text result set an empty first cell also encodes as 0x00, so the
/// caller must know which protocol the result set uses. Complexity: O(1).
pub fn mysql_is_binary_row_header(payload: &Vec[UInt8]) -> Bool {
  if payload.len() == 0 {
    return false;
  }
  return ((payload[0] as Int) & 0xFF) == 0;
}

// ---- Authentication response framing kinds ----

/// No auth response bytes were present. Complexity: O(1).
pub fn mysql_auth_response_kind_none() -> Int {
  return 0;
}

/// The auth response was a NUL-terminated string (no CLIENT_SECURE_CONNECTION
/// and no CLIENT_PLUGIN_AUTH_LENENC_CLIENT_DATA). Complexity: O(1).
pub fn mysql_auth_response_kind_nul_string() -> Int {
  return 1;
}

/// The auth response was a 1-byte length followed by that many bytes
/// (CLIENT_SECURE_CONNECTION). Complexity: O(1).
pub fn mysql_auth_response_kind_secure() -> Int {
  return 2;
}

/// The auth response was a length-encoded string
/// (CLIENT_PLUGIN_AUTH_LENENC_CLIENT_DATA). Complexity: O(1).
pub fn mysql_auth_response_kind_lenenc() -> Int {
  return 3;
}

/// Name of an auth response framing kind, or "UNKNOWN". Complexity: O(1).
pub fn mysql_auth_response_kind_name(kind: Int) -> Str {
  if kind == 0 { return "NONE"; }
  if kind == 1 { return "NUL_STRING"; }
  if kind == 2 { return "SECURE"; }
  if kind == 3 { return "LENENC"; }
  return "UNKNOWN";
}

// --------------------------------------------------
//  Private helpers
// --------------------------------------------------

// True for the 32 column type codes of the documented table.
fn _type_known(code: Int) -> Bool {
  if code >= 0 && code <= 20 {
    return true;
  }
  return code >= 245 && code <= 255;
}

// Byte `shift_bytes` of `v` in little-endian order (0 = least significant
// byte), as the exact two's-complement bit pattern. Arithmetic only.
fn _le_byte(v: Int, shift_bytes: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift_bytes {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append one byte (low 8 bits of `b`).
fn _w_push_byte(w: &mut MysqlWriter, b: Int) {
  w.data.push(_le_byte(b, 0));
}

// Append the low `size` (1..8) bytes of `v` in little-endian order.
fn _w_push_le(w: &mut MysqlWriter, v: Int, size: Int) {
  var i = 0;
  while i < size {
    w.data.push(_le_byte(v, i));
    i = i + 1;
  }
}

// Append every UTF-8 byte of `s`.
fn _w_push_str(w: &mut MysqlWriter, s: Str) {
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    w.data.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Append every byte of `v`.
fn _w_push_bytes(w: &mut MysqlWriter, v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    w.data.push(v[i]);
    i = i + 1;
  }
}

// Append a length-encoded length for a known non-negative value.
fn _w_push_lenenc_len(w: &mut MysqlWriter, v: Int) {
  if v < 251 {
    _w_push_byte(w, v);
    return;
  }
  if v < 65536 {
    _w_push_byte(w, 252);
    _w_push_le(w, v, 2);
    return;
  }
  if v < 16777216 {
    _w_push_byte(w, 253);
    _w_push_le(w, v, 3);
    return;
  }
  _w_push_byte(w, 254);
  _w_push_le(w, v, 8);
}

// The bytes of `s` as a fresh vector.
fn _str_bytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

// True when `s` contains a 0x00 byte.
fn _str_has_nul(s: Str) -> Bool {
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// True when the byte vector contains a 0x00 byte.
fn _bytes_have_nul(v: &Vec[UInt8]) -> Bool {
  var i = 0;
  while i < v.len() {
    let b: Int = (v[i] as Int) & 0xFF;
    if b == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// A fresh copy of `src` (used where a returned vector must not alias).
fn _copy_bytes(src: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
  return out;
}

// Byte at `pos` widened to 0..255. The caller guarantees in-bounds.
fn _r_byte(r: &MysqlReader, pos: Int) -> Int {
  return (r.data[pos] as Int) & 0xFF;
}

// Same as _r_byte but takes &mut, so reader bodies never mix a `&` call
// before a `&mut` access on the same local (advisory E001).
fn _r_byte_mut(r: &mut MysqlReader, pos: Int) -> Int {
  return _r_byte(r, pos);
}

// Read `size` (1..4) bytes little-endian into an unsigned Int, advancing the
// cursor. Err(truncation with the starting offset) when short.
fn _read_le(r: &mut MysqlReader, size: Int) -> Result[Int, Str] {
  let start: Int = r.pos;
  let total: Int = r.data.len();
  if start + size > total {
    return _err_int(_trunc_at(start));
  }
  var v: Int = 0;
  var i = size - 1;
  while i >= 0 {
    let b: Int = _r_byte_mut(r, start + i);
    v = v * 256 + b;
    i = i - 1;
  }
  r.pos = start + size;
  return _ok_int(v);
}

// Read 8 bytes little-endian as an unsigned Int. A value with bit 63 set
// cannot be represented by a signed Int and is rejected (deterministic,
// documented) instead of wrapping.
fn _read_le_u64(r: &mut MysqlReader) -> Result[Int, Str] {
  let start: Int = r.pos;
  let total: Int = r.data.len();
  if start + 8 > total {
    return _err_int(_trunc_at(start));
  }
  let top: Int = _r_byte_mut(r, start + 7);
  if top >= 128 {
    return _err_int("mysql: 64-bit length-encoded value out of range at offset " + convert.int_to_string(start));
  }
  var v: Int = 0;
  var i = 7;
  while i >= 0 {
    let b: Int = _r_byte_mut(r, start + i);
    v = v * 256 + b;
    i = i - 1;
  }
  r.pos = start + 8;
  return _ok_int(v);
}

// Read exactly `n` bytes into a fresh vector, advancing the cursor.
// Err(bad length) for n < 0 and Err(truncation) when short.
fn _read_bytes_n(r: &mut MysqlReader, n: Int) -> Result[Vec[UInt8], Str] {
  let start: Int = r.pos;
  if n < 0 {
    return _err_bytes(_bad_len_msg(n, start));
  }
  let total: Int = r.data.len();
  if start + n > total {
    return _err_bytes(_trunc_at(start));
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(r.data[start + i]);
    i = i + 1;
  }
  r.pos = start + n;
  return _ok_bytes(out);
}

// Read a NUL-terminated string, advancing past the terminator. The payload
// must be valid UTF-8; a missing terminator is Err(unterminated at offset).
fn _read_nul_str(r: &mut MysqlReader) -> Result[Str, Str] {
  let start: Int = r.pos;
  let total: Int = r.data.len();
  var i = start;
  while i < total {
    let b: Int = _r_byte_mut(r, i);
    if b == 0 {
      let sr = _range_to_str(r, start, i);
      if !sr.is_ok {
        return _err_str(sr.error);
      }
      r.pos = i + 1;
      return _ok_str(sr.value);
    }
    i = i + 1;
  }
  return _err_str("mysql: unterminated string at offset " + convert.int_to_string(start));
}

// The remaining bytes as a fresh vector; advances the cursor to the end.
fn _read_rest_bytes(r: &mut MysqlReader) -> Vec[UInt8] {
  let start: Int = r.pos;
  let total: Int = r.data.len();
  var out = Vec[UInt8].new();
  var i = start;
  while i < total {
    out.push(r.data[i]);
    i = i + 1;
  }
  r.pos = total;
  return out;
}

// The remaining bytes as a validated UTF-8 Str; advances to the end.
fn _read_rest_str(r: &mut MysqlReader) -> Result[Str, Str] {
  let start: Int = r.pos;
  let total: Int = r.data.len();
  let sr = _range_to_str(r, start, total);
  if !sr.is_ok {
    return _err_str(sr.error);
  }
  r.pos = total;
  return _ok_str(sr.value);
}

// Bytes [from, to) of the reader buffer as a validated Str (cursor not
// moved). Internal callers guarantee 0 <= from <= to <= len.
fn _range_to_str(r: &MysqlReader, from: Int, to: Int) -> Result[Str, Str] {
  var sb = Vec[UInt8].new();
  var i = from;
  while i < to {
    sb.push(r.data[i]);
    i = i + 1;
  }
  let ue = _utf8_error(&sb);
  if ue.len() > 0 {
    return _err_str(ue);
  }
  return _ok_str(_bytes_to_str(&sb));
}

// Bytes [from, to) of a payload vector as a validated Str.
fn _payload_range_to_str(p: &Vec[UInt8], from: Int, to: Int) -> Result[Str, Str] {
  var sb = Vec[UInt8].new();
  var i = from;
  while i < to {
    sb.push(p[i]);
    i = i + 1;
  }
  let ue = _utf8_error(&sb);
  if ue.len() > 0 {
    return _err_str(ue);
  }
  return _ok_str(_bytes_to_str(&sb));
}

// --------------------------------------------------
//  Error message helpers
// --------------------------------------------------

// "mysql: truncated input at offset N".
fn _trunc_at(off: Int) -> Str {
  return "mysql: truncated input at offset " + convert.int_to_string(off);
}

// "mysql: bad length N at offset M".
fn _bad_len_msg(n: Int, off: Int) -> Str {
  return "mysql: bad length " + convert.int_to_string(n) + " at offset " + convert.int_to_string(off);
}

// UTF-8 validation of a string payload (RFC 3629, strict: overlong forms
// and surrogates are rejected). Returns "" when valid, otherwise the
// deterministic error. A 0x00 byte is valid UTF-8 but is reported separately
// because a NUL would abort the v0.61.3 string builder.
fn _utf8_error(bytes: &Vec[UInt8]) -> Str {
  let n = bytes.len();
  var i = 0;
  while i < n {
    let b: Int = (bytes[i] as Int) & 0xFF;
    if b == 0 {
      return "mysql: string contains nul";
    }
    if b < 128 {
      i = i + 1;
    } elif b < 194 {
      return "mysql: invalid utf-8";
    } elif b < 224 {
      if i + 1 >= n {
        return "mysql: invalid utf-8";
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return "mysql: invalid utf-8";
      }
      i = i + 2;
    } elif b < 240 {
      if i + 2 >= n {
        return "mysql: invalid utf-8";
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      let c2: Int = (bytes[i + 2] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return "mysql: invalid utf-8";
      }
      if c2 < 128 || c2 >= 192 {
        return "mysql: invalid utf-8";
      }
      if b == 224 && c1 < 160 {
        return "mysql: invalid utf-8";
      }
      if b == 237 && c1 >= 160 {
        return "mysql: invalid utf-8";
      }
      i = i + 3;
    } else {
      if b >= 245 {
        return "mysql: invalid utf-8";
      }
      if i + 3 >= n {
        return "mysql: invalid utf-8";
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      let c2: Int = (bytes[i + 2] as Int) & 0xFF;
      let c3: Int = (bytes[i + 3] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return "mysql: invalid utf-8";
      }
      if c2 < 128 || c2 >= 192 {
        return "mysql: invalid utf-8";
      }
      if c3 < 128 || c3 >= 192 {
        return "mysql: invalid utf-8";
      }
      if b == 240 && c1 < 144 {
        return "mysql: invalid utf-8";
      }
      if b == 244 && c1 >= 144 {
        return "mysql: invalid utf-8";
      }
      i = i + 4;
    }
  }
  return "";
}

// The bytes of `v` as a Str. Only called on NUL-free byte vectors that were
// validated at the API boundary, so sb_to_str cannot abort.
fn _bytes_to_str(v: &Vec[UInt8]) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    sb.push(v[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Writer and reader lifecycle
// --------------------------------------------------

/// A fresh empty writer. Complexity: O(1).
pub fn mysql_writer_new() -> MysqlWriter {
  return MysqlWriter{ data: Vec[UInt8].new() };
}

/// Number of bytes written so far. Complexity: O(1).
pub fn mysql_writer_len(w: &MysqlWriter) -> Int {
  return w.data.len();
}

/// A copy of the bytes written so far. Complexity: O(written bytes).
pub fn mysql_writer_bytes(w: &MysqlWriter) -> Vec[UInt8] {
  return _copy_bytes(&w.data);
}

/// A reader positioned at offset 0 of `data`. Complexity: O(1).
pub fn mysql_reader_new(data: Vec[UInt8]) -> MysqlReader {
  return MysqlReader{ data: data; pos: 0; };
}

/// Current cursor offset. Complexity: O(1).
pub fn mysql_reader_pos(r: &MysqlReader) -> Int {
  return r.pos;
}

/// Current cursor offset, taking &mut so a caller that also mutates the
/// reader never mixes a `&` accessor before a `&mut` call on the same local
/// (advisory E001). Complexity: O(1).
pub fn mysql_reader_pos_mut(r: &mut MysqlReader) -> Int {
  return r.pos;
}

/// Bytes left before the end of the buffer. Complexity: O(1).
pub fn mysql_reader_remaining(r: &MysqlReader) -> Int {
  return r.data.len() - r.pos;
}

// --------------------------------------------------
//  Little-endian primitives
// --------------------------------------------------

/// Read one unsigned byte (0..255). Err(truncation) when empty.
/// Complexity: O(1).
pub fn mysql_read_u8(r: &mut MysqlReader) -> Result[Int, Str] {
  return _read_le(r, 1);
}

/// Read an unsigned 16-bit little-endian integer (0..65535).
/// Err(truncation) when short. Complexity: O(1).
pub fn mysql_read_u16_le(r: &mut MysqlReader) -> Result[Int, Str] {
  return _read_le(r, 2);
}

/// Read an unsigned 32-bit little-endian integer.
/// Err(truncation) when short. Complexity: O(1).
pub fn mysql_read_u32_le(r: &mut MysqlReader) -> Result[Int, Str] {
  return _read_le(r, 4);
}

/// Read an unsigned 64-bit little-endian integer. A value with bit 63 set
/// is rejected as out of range. Err(truncation) when short.
/// Complexity: O(1).
pub fn mysql_read_u64_le(r: &mut MysqlReader) -> Result[Int, Str] {
  return _read_le_u64(r);
}

/// Append the low 8 bits of `v`. Complexity: O(1).
pub fn mysql_write_u8(w: &mut MysqlWriter, v: Int) {
  _w_push_le(w, v, 1);
}

/// Append the low 16 bits of `v` little-endian. Complexity: O(1).
pub fn mysql_write_u16_le(w: &mut MysqlWriter, v: Int) {
  _w_push_le(w, v, 2);
}

/// Append the low 32 bits of `v` little-endian. Complexity: O(1).
pub fn mysql_write_u32_le(w: &mut MysqlWriter, v: Int) {
  _w_push_le(w, v, 4);
}

/// Append the low 64 bits of `v` little-endian (two's complement for
/// negative values). Complexity: O(1).
pub fn mysql_write_u64_le(w: &mut MysqlWriter, v: Int) {
  _w_push_le(w, v, 8);
}

/// Read exactly `n` raw bytes. Err(bad length) for n < 0 and Err(truncation)
/// when short. Complexity: O(n).
pub fn mysql_read_bytes_n(r: &mut MysqlReader, n: Int) -> Result[Vec[UInt8], Str] {
  return _read_bytes_n(r, n);
}

/// Read a NUL-terminated UTF-8 string (terminator consumed, not stored).
/// Err(unterminated at offset) when no 0x00 is found. Complexity: O(n).
pub fn mysql_read_nul_str(r: &mut MysqlReader) -> Result[Str, Str] {
  return _read_nul_str(r);
}

/// The remaining bytes as a copy; the cursor moves to the end.
/// Complexity: O(remaining).
pub fn mysql_read_rest_bytes(r: &mut MysqlReader) -> Vec[UInt8] {
  return _read_rest_bytes(r);
}

/// The remaining bytes as a validated UTF-8 Str; the cursor moves to the
/// end. Complexity: O(remaining).
pub fn mysql_read_rest_str(r: &mut MysqlReader) -> Result[Str, Str] {
  return _read_rest_str(r);
}

/// Append every byte of `v`. Complexity: O(len).
pub fn mysql_write_bytes(w: &mut MysqlWriter, v: &Vec[UInt8]) {
  _w_push_bytes(w, v);
}

/// Append every byte of `s` verbatim (the caller guarantees the payload
/// shape). Complexity: O(len).
pub fn mysql_write_str(w: &mut MysqlWriter, s: Str) {
  _w_push_str(w, s);
}

/// Append `s` followed by a NUL terminator. Err when `s` contains 0x00.
/// Complexity: O(len).
pub fn mysql_write_nul_str(w: &mut MysqlWriter, s: Str) -> Result[Bool, Str] {
  if _str_has_nul(s) {
    return _err_bool("mysql: string contains nul");
  }
  _w_push_str(w, s);
  _w_push_byte(w, 0);
  return _ok_bool(true);
}

// --------------------------------------------------
//  Length-encoded values
// --------------------------------------------------

/// Read a length-encoded integer, allowing the NULL marker 0xFB
/// (is_null == true). 0xFF is rejected as an invalid lenenc first byte.
/// Err(truncation) when the payload is short. Complexity: O(1).
pub fn mysql_read_lenenc_int_nullable(r: &mut MysqlReader) -> Result[MysqlLenenc, Str] {
  let start: Int = r.pos;
  let br = _read_le(r, 1);
  if !br.is_ok {
    return _err_lenenc(br.error);
  }
  let b: Int = br.value;
  if b < 251 {
    return _ok_lenenc(MysqlLenenc{ is_null: false; value: b; });
  }
  if b == 251 {
    return _ok_lenenc(MysqlLenenc{ is_null: true; value: 0; });
  }
  if b == 252 {
    let vr = _read_le(r, 2);
    if !vr.is_ok {
      return _err_lenenc(vr.error);
    }
    return _ok_lenenc(MysqlLenenc{ is_null: false; value: vr.value; });
  }
  if b == 253 {
    let vr = _read_le(r, 3);
    if !vr.is_ok {
      return _err_lenenc(vr.error);
    }
    return _ok_lenenc(MysqlLenenc{ is_null: false; value: vr.value; });
  }
  if b == 254 {
    let vr = _read_le_u64(r);
    if !vr.is_ok {
      return _err_lenenc(vr.error);
    }
    return _ok_lenenc(MysqlLenenc{ is_null: false; value: vr.value; });
  }
  return _err_lenenc("mysql: invalid length-encoded first byte " + convert.int_to_string(b) + " at offset " + convert.int_to_string(start));
}

/// Read a length-encoded integer; the NULL marker is rejected.
/// Complexity: O(1).
pub fn mysql_read_lenenc_int(r: &mut MysqlReader) -> Result[Int, Str] {
  let start: Int = r.pos;
  let lr = mysql_read_lenenc_int_nullable(r);
  if !lr.is_ok {
    return _err_int(lr.error);
  }
  let l: MysqlLenenc = lr.value;
  if l.is_null {
    return _err_int("mysql: null length-encoded integer at offset " + convert.int_to_string(start));
  }
  return _ok_int(l.value);
}

/// Read a length-encoded UTF-8 string. The NULL marker 0xFB is rejected;
/// use mysql_read_text_row for NULL cells. Complexity: O(payload).
pub fn mysql_read_lenenc_str(r: &mut MysqlReader) -> Result[Str, Str] {
  let start: Int = r.pos;
  let lr = mysql_read_lenenc_int_nullable(r);
  if !lr.is_ok {
    return _err_str(lr.error);
  }
  let l: MysqlLenenc = lr.value;
  if l.is_null {
    return _err_str("mysql: null length-encoded string at offset " + convert.int_to_string(start));
  }
  let n: Int = l.value;
  let br = _read_bytes_n(r, n);
  if !br.is_ok {
    return _err_str(br.error);
  }
  let bytes: Vec[UInt8] = br.value;
  let ue = _utf8_error(&bytes);
  if ue.len() > 0 {
    return _err_str(ue);
  }
  return _ok_str(_bytes_to_str(&bytes));
}

/// Read a length-encoded byte string (no UTF-8 requirement). The NULL
/// marker 0xFB is rejected. Complexity: O(payload).
pub fn mysql_read_lenenc_bytes(r: &mut MysqlReader) -> Result[Vec[UInt8], Str] {
  let start: Int = r.pos;
  let lr = mysql_read_lenenc_int_nullable(r);
  if !lr.is_ok {
    return _err_bytes(lr.error);
  }
  let l: MysqlLenenc = lr.value;
  if l.is_null {
    return _err_bytes("mysql: null length-encoded string at offset " + convert.int_to_string(start));
  }
  let n: Int = l.value;
  return _read_bytes_n(r, n);
}

/// Append a length-encoded integer. Err for v < 0. Complexity: O(1).
pub fn mysql_write_lenenc_int(w: &mut MysqlWriter, v: Int) -> Result[Bool, Str] {
  if v < 0 {
    return _err_bool("mysql: bad length-encoded integer " + convert.int_to_string(v));
  }
  _w_push_lenenc_len(w, v);
  return _ok_bool(true);
}

/// Append the NULL length-encoded marker 0xFB. Complexity: O(1).
pub fn mysql_write_lenenc_null(w: &mut MysqlWriter) {
  _w_push_byte(w, 251);
}

/// Append a length-encoded UTF-8 string. Err when `s` contains 0x00.
/// Complexity: O(len).
pub fn mysql_write_lenenc_str(w: &mut MysqlWriter, s: Str) -> Result[Bool, Str] {
  if _str_has_nul(s) {
    return _err_bool("mysql: string contains nul");
  }
  _w_push_lenenc_len(w, string.str_len(s));
  _w_push_str(w, s);
  return _ok_bool(true);
}

/// Append a length-encoded byte string. Complexity: O(len).
pub fn mysql_write_lenenc_bytes(w: &mut MysqlWriter, v: &Vec[UInt8]) {
  _w_push_lenenc_len(w, v.len());
  _w_push_bytes(w, v);
}

/// NULL flag of a decoded length-encoded integer. Complexity: O(1).
pub fn mysql_lenenc_is_null(l: &MysqlLenenc) -> Bool {
  return l.is_null;
}

/// Value of a decoded length-encoded integer (0 when NULL).
/// Complexity: O(1).
pub fn mysql_lenenc_value(l: &MysqlLenenc) -> Int {
  return l.value;
}

// --------------------------------------------------
//  Packet framing
// --------------------------------------------------

/// Read one packet header (3-byte little-endian length + sequence id).
/// The payload is not consumed. Err(truncation) when fewer than 4 bytes
/// remain. Complexity: O(1).
pub fn mysql_read_packet_header(r: &mut MysqlReader) -> Result[MysqlPacketHeader, Str] {
  let lr = _read_le(r, 3);
  if !lr.is_ok {
    return _err_header(lr.error);
  }
  let sr = _read_le(r, 1);
  if !sr.is_ok {
    return _err_header(sr.error);
  }
  return _ok_header(MysqlPacketHeader{ payload_len: lr.value; sequence_id: sr.value; });
}

/// Append a packet header. Err for a negative or larger-than-0xFFFFFF
/// payload length. Complexity: O(1).
pub fn mysql_write_packet_header(w: &mut MysqlWriter, payload_len: Int, sequence_id: Int) -> Result[Bool, Str] {
  if payload_len < 0 {
    return _err_bool("mysql: bad payload length " + convert.int_to_string(payload_len));
  }
  if payload_len > _MAX_PAYLOAD_LEN {
    return _err_bool("mysql: payload length " + convert.int_to_string(payload_len) + " exceeds " + convert.int_to_string(_MAX_PAYLOAD_LEN));
  }
  _w_push_le(w, payload_len, 3);
  _w_push_le(w, sequence_id % _SEQ_MODULUS, 1);
  return _ok_bool(true);
}

/// Read exactly one packet: header plus its declared payload. A declared
/// payload of 0xFFFFFF is read as-is (one packet); use mysql_read_message
/// to reassemble a multi-packet message. Err(truncation) when the payload
/// does not fit the buffer. Complexity: O(payload).
pub fn mysql_read_packet(r: &mut MysqlReader) -> Result[MysqlPacket, Str] {
  let hr = mysql_read_packet_header(r);
  if !hr.is_ok {
    return _err_packet(hr.error);
  }
  let h: MysqlPacketHeader = hr.value;
  let n: Int = h.payload_len;
  let pr = _read_bytes_n(r, n);
  if !pr.is_ok {
    return _err_packet(pr.error);
  }
  let payload: Vec[UInt8] = pr.value;
  return _ok_packet(MysqlPacket{ payload_len: n; sequence_id: h.sequence_id; payload: payload; });
}

/// Append one packet (header + payload). The next sequence id is returned.
/// Err when the payload exceeds 0xFFFFFF bytes; use mysql_write_message to
/// split a larger message. Complexity: O(payload).
pub fn mysql_write_packet(w: &mut MysqlWriter, payload: &Vec[UInt8], sequence_id: Int) -> Result[Int, Str] {
  let n: Int = payload.len();
  if n > _MAX_PAYLOAD_LEN {
    return _err_int("mysql: payload length " + convert.int_to_string(n) + " exceeds " + convert.int_to_string(_MAX_PAYLOAD_LEN));
  }
  let hr = mysql_write_packet_header(w, n, sequence_id);
  if !hr.is_ok {
    return _err_int(hr.error);
  }
  _w_push_bytes(w, payload);
  return _ok_int(mysql_sequence_next(sequence_id));
}

/// Reassemble one message: read packets until a packet declares fewer than
/// 0xFFFFFF bytes and concatenate their payloads. The 0xFFFFFF rule means a
/// message of exactly N * 0xFFFFFF bytes ends with an empty terminating
/// packet. Err(truncation) when the buffer ends inside the message.
/// Complexity: O(message bytes).
pub fn mysql_read_message(r: &mut MysqlReader) -> Result[MysqlMessage, Str] {
  var payload = Vec[UInt8].new();
  var count: Int = 0;
  var first_seq: Int = 0;
  var last_seq: Int = 0;
  var more: Bool = true;
  while more {
    let pr = mysql_read_packet(r);
    if !pr.is_ok {
      return _err_message(pr.error);
    }
    let p: MysqlPacket = pr.value;
    let n: Int = p.payload_len;
    let seq: Int = p.sequence_id;
    if count == 0 {
      first_seq = seq;
    }
    last_seq = seq;
    let chunk: Vec[UInt8] = p.payload;
    var i = 0;
    while i < chunk.len() {
      payload.push(chunk[i]);
      i = i + 1;
    }
    count = count + 1;
    if n < _MAX_PAYLOAD_LEN {
      more = false;
    }
  }
  return _ok_message(MysqlMessage{ payload: payload; packet_count: count; first_sequence: first_seq; last_sequence: last_seq; });
}

/// Append one message, splitting it into 0xFFFFFF-byte packets with a final
/// short packet. A message whose length is a positive multiple of 0xFFFFFF
/// is terminated by an empty packet so the receiver sees an unambiguous
/// end. The next sequence id is returned. Complexity: O(message bytes).
pub fn mysql_write_message(w: &mut MysqlWriter, payload: &Vec[UInt8], sequence_id: Int) -> Result[Int, Str] {
  let total: Int = payload.len();
  let limit: Int = _MAX_PAYLOAD_LEN;
  var off: Int = 0;
  var seq: Int = sequence_id;
  while off < total {
    var n: Int = total - off;
    if n > limit {
      n = limit;
    }
    let hr = mysql_write_packet_header(w, n, seq);
    if !hr.is_ok {
      return _err_int(hr.error);
    }
    var i = 0;
    while i < n {
      w.data.push(payload[off + i]);
      i = i + 1;
    }
    off = off + n;
    seq = mysql_sequence_next(seq);
  }
  if total % limit == 0 {
    let hr2 = mysql_write_packet_header(w, 0, seq);
    if !hr2.is_ok {
      return _err_int(hr2.error);
    }
    seq = mysql_sequence_next(seq);
  }
  return _ok_int(seq);
}

/// Declared payload length of a packet header. Complexity: O(1).
pub fn mysql_packet_header_payload_len(h: &MysqlPacketHeader) -> Int {
  return h.payload_len;
}

/// Sequence id of a packet header. Complexity: O(1).
pub fn mysql_packet_header_sequence_id(h: &MysqlPacketHeader) -> Int {
  return h.sequence_id;
}

/// Declared payload length of a packet. Complexity: O(1).
pub fn mysql_packet_payload_len(p: &MysqlPacket) -> Int {
  return p.payload_len;
}

/// Sequence id of a packet. Complexity: O(1).
pub fn mysql_packet_sequence_id(p: &MysqlPacket) -> Int {
  return p.sequence_id;
}

/// A copy of a packet's payload. Complexity: O(payload).
pub fn mysql_packet_payload(p: &MysqlPacket) -> Vec[UInt8] {
  let v: Vec[UInt8] = p.payload;
  return _copy_bytes(&v);
}

/// A copy of a message's reassembled payload. Complexity: O(payload).
pub fn mysql_message_payload(m: &MysqlMessage) -> Vec[UInt8] {
  let v: Vec[UInt8] = m.payload;
  return _copy_bytes(&v);
}

/// Number of packets that carried a message. Complexity: O(1).
pub fn mysql_message_packet_count(m: &MysqlMessage) -> Int {
  return m.packet_count;
}

/// Sequence id of a message's first packet. Complexity: O(1).
pub fn mysql_message_first_sequence(m: &MysqlMessage) -> Int {
  return m.first_sequence;
}

/// Sequence id of a message's last packet. Complexity: O(1).
pub fn mysql_message_last_sequence(m: &MysqlMessage) -> Int {
  return m.last_sequence;
}

// --------------------------------------------------
//  Initial handshake v10
// --------------------------------------------------

/// Read an initial handshake v10 packet. The protocol version must be 10;
/// the auth-plugin-data part 2 is read as max(13, auth_plugin_data_len - 8)
/// bytes when CLIENT_PLUGIN_AUTH is set and as 13 bytes otherwise, and the
/// auth plugin name NUL-string is read when CLIENT_PLUGIN_AUTH is set.
/// Complexity: O(packet).
pub fn mysql_read_handshake(r: &mut MysqlReader) -> Result[MysqlHandshake, Str] {
  let start: Int = r.pos;
  let pr = _read_le(r, 1);
  if !pr.is_ok {
    return _err_handshake(pr.error);
  }
  let pv: Int = pr.value;
  if pv != _HANDSHAKE_V10 {
    return _err_handshake("mysql: unsupported protocol version " + convert.int_to_string(pv) + " at offset " + convert.int_to_string(start));
  }
  let svr = _read_nul_str(r);
  if !svr.is_ok {
    return _err_handshake(svr.error);
  }
  let server_version: Str = svr.value;
  let cidr = _read_le(r, 4);
  if !cidr.is_ok {
    return _err_handshake(cidr.error);
  }
  let connection_id: Int = cidr.value;
  let p1r = _read_bytes_n(r, 8);
  if !p1r.is_ok {
    return _err_handshake(p1r.error);
  }
  let part1: Vec[UInt8] = p1r.value;
  let fr = _read_le(r, 1);
  if !fr.is_ok {
    return _err_handshake(fr.error);
  }
  let lo_r = _read_le(r, 2);
  if !lo_r.is_ok {
    return _err_handshake(lo_r.error);
  }
  let cap_lo: Int = lo_r.value;
  let cs_r = _read_le(r, 1);
  if !cs_r.is_ok {
    return _err_handshake(cs_r.error);
  }
  let character_set: Int = cs_r.value;
  let st_r = _read_le(r, 2);
  if !st_r.is_ok {
    return _err_handshake(st_r.error);
  }
  let status_flags: Int = st_r.value;
  let hi_r = _read_le(r, 2);
  if !hi_r.is_ok {
    return _err_handshake(hi_r.error);
  }
  let cap_hi: Int = hi_r.value;
  let al_r = _read_le(r, 1);
  if !al_r.is_ok {
    return _err_handshake(al_r.error);
  }
  let auth_data_len: Int = al_r.value;
  let rs_r = _read_bytes_n(r, 10);
  if !rs_r.is_ok {
    return _err_handshake(rs_r.error);
  }
  let caps: Int = cap_lo + cap_hi * 65536;
  var part2_len: Int = 13;
  if (caps & mysql_capability_plugin_auth()) != 0 {
    part2_len = auth_data_len - 8;
    if part2_len < 13 {
      part2_len = 13;
    }
  }
  let p2r = _read_bytes_n(r, part2_len);
  if !p2r.is_ok {
    return _err_handshake(p2r.error);
  }
  let part2: Vec[UInt8] = p2r.value;
  var plugin: Str = "";
  if (caps & mysql_capability_plugin_auth()) != 0 {
    let pnr = _read_nul_str(r);
    if !pnr.is_ok {
      return _err_handshake(pnr.error);
    }
    plugin = pnr.value;
  }
  return _ok_handshake(MysqlHandshake{ protocol_version: pv; server_version: server_version; connection_id: connection_id; capability_flags: caps; character_set: character_set; status_flags: status_flags; auth_plugin_data_len: auth_data_len; auth_plugin_data_1: part1; auth_plugin_data_2: part2; auth_plugin_name: plugin; });
}

/// Append an initial handshake v10 packet. Err when the protocol version is
/// not 10, when auth_plugin_data_1 is not exactly 8 bytes, or when a string
/// field contains 0x00. Complexity: O(packet).
pub fn mysql_write_handshake(w: &mut MysqlWriter, h: &MysqlHandshake) -> Result[Bool, Str] {
  let pv: Int = h.protocol_version;
  if pv != _HANDSHAKE_V10 {
    return _err_bool("mysql: unsupported protocol version " + convert.int_to_string(pv));
  }
  if _str_has_nul(h.server_version) {
    return _err_bool("mysql: string contains nul");
  }
  let part1: Vec[UInt8] = h.auth_plugin_data_1;
  if part1.len() != 8 {
    return _err_bool("mysql: bad auth plugin data part 1 length " + convert.int_to_string(part1.len()));
  }
  if _str_has_nul(h.auth_plugin_name) {
    return _err_bool("mysql: string contains nul");
  }
  let caps: Int = h.capability_flags;
  if caps < 0 {
    return _err_bool("mysql: bad capability flags " + convert.int_to_string(caps));
  }
  let cap_lo: Int = caps % 65536;
  let cap_hi: Int = (caps / 65536) % 65536;
  _w_push_le(w, pv, 1);
  _w_push_str(w, h.server_version);
  _w_push_byte(w, 0);
  _w_push_le(w, h.connection_id, 4);
  _w_push_bytes(w, &part1);
  _w_push_byte(w, 0);
  _w_push_le(w, cap_lo, 2);
  _w_push_le(w, h.character_set, 1);
  _w_push_le(w, h.status_flags, 2);
  _w_push_le(w, cap_hi, 2);
  _w_push_le(w, h.auth_plugin_data_len, 1);
  var i = 0;
  while i < 10 {
    _w_push_byte(w, 0);
    i = i + 1;
  }
  let part2: Vec[UInt8] = h.auth_plugin_data_2;
  _w_push_bytes(w, &part2);
  if (caps & mysql_capability_plugin_auth()) != 0 {
    _w_push_str(w, h.auth_plugin_name);
    _w_push_byte(w, 0);
  }
  return _ok_bool(true);
}

/// Protocol version of a handshake (10). Complexity: O(1).
pub fn mysql_handshake_protocol_version(h: &MysqlHandshake) -> Int {
  return h.protocol_version;
}

/// Server version string of a handshake. Complexity: O(1).
pub fn mysql_handshake_server_version(h: &MysqlHandshake) -> Str {
  let s: Str = h.server_version;
  return s;
}

/// Connection id of a handshake. Complexity: O(1).
pub fn mysql_handshake_connection_id(h: &MysqlHandshake) -> Int {
  return h.connection_id;
}

/// Combined 32-bit capability flags of a handshake. Complexity: O(1).
pub fn mysql_handshake_capability_flags(h: &MysqlHandshake) -> Int {
  return h.capability_flags;
}

/// True when the handshake has every bit of `bit` set. Complexity: O(1).
pub fn mysql_handshake_has_capability(h: &MysqlHandshake, bit: Int) -> Bool {
  let caps: Int = h.capability_flags;
  return (caps & bit) == bit;
}

/// Character set id of a handshake. Complexity: O(1).
pub fn mysql_handshake_character_set(h: &MysqlHandshake) -> Int {
  return h.character_set;
}

/// Status flags of a handshake. Complexity: O(1).
pub fn mysql_handshake_status_flags(h: &MysqlHandshake) -> Int {
  return h.status_flags;
}

/// Auth plugin data length byte of a handshake. Complexity: O(1).
pub fn mysql_handshake_auth_plugin_data_len(h: &MysqlHandshake) -> Int {
  return h.auth_plugin_data_len;
}

/// A copy of auth-plugin-data part 1 (8 bytes). Complexity: O(1).
pub fn mysql_handshake_auth_plugin_data_1(h: &MysqlHandshake) -> Vec[UInt8] {
  let v: Vec[UInt8] = h.auth_plugin_data_1;
  return _copy_bytes(&v);
}

/// A copy of auth-plugin-data part 2 as stored (NUL padding included).
/// Complexity: O(len).
pub fn mysql_handshake_auth_plugin_data_2(h: &MysqlHandshake) -> Vec[UInt8] {
  let v: Vec[UInt8] = h.auth_plugin_data_2;
  return _copy_bytes(&v);
}

/// Auth plugin name of a handshake, or "" when CLIENT_PLUGIN_AUTH was not
/// set. Complexity: O(1).
pub fn mysql_handshake_auth_plugin_name(h: &MysqlHandshake) -> Str {
  let s: Str = h.auth_plugin_name;
  return s;
}

/// The combined auth plugin data (part 1 + part 2) with one trailing NUL
/// byte removed when present, which is the scramble most auth plugins
/// expect. Complexity: O(len).
pub fn mysql_handshake_auth_plugin_data(h: &MysqlHandshake) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let p1: Vec[UInt8] = h.auth_plugin_data_1;
  let p2: Vec[UInt8] = h.auth_plugin_data_2;
  var i = 0;
  while i < p1.len() {
    out.push(p1[i]);
    i = i + 1;
  }
  var n: Int = p2.len();
  if n > 0 {
    let lastb: Int = (p2[n - 1] as Int) & 0xFF;
    if lastb == 0 {
      n = n - 1;
    }
  }
  i = 0;
  while i < n {
    out.push(p2[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Handshake response 41 and SSL request
// --------------------------------------------------

/// Read a handshake response 41 packet. The auth response framing follows
/// the capability flags (lenenc over secure over NUL-string); the database,
/// auth plugin name and connect-attrs block are read when their bits are
/// set. Trailing bytes after the declared fields are rejected.
/// Complexity: O(packet).
pub fn mysql_read_handshake_response(r: &mut MysqlReader) -> Result[MysqlHandshakeResponse, Str] {
  let cr = _read_le(r, 4);
  if !cr.is_ok {
    return _err_response(cr.error);
  }
  let caps: Int = cr.value;
  let mr = _read_le(r, 4);
  if !mr.is_ok {
    return _err_response(mr.error);
  }
  let max_packet: Int = mr.value;
  let csr = _read_le(r, 1);
  if !csr.is_ok {
    return _err_response(csr.error);
  }
  let character_set: Int = csr.value;
  let fillr = _read_bytes_n(r, 23);
  if !fillr.is_ok {
    return _err_response(fillr.error);
  }
  let ur = _read_nul_str(r);
  if !ur.is_ok {
    return _err_response(ur.error);
  }
  let username: Str = ur.value;
  var kind: Int = mysql_auth_response_kind_none();
  var auth = Vec[UInt8].new();
  if (caps & mysql_capability_plugin_auth_lenenc_client_data()) != 0 {
    kind = mysql_auth_response_kind_lenenc();
    let ar = mysql_read_lenenc_bytes(r);
    if !ar.is_ok {
      return _err_response(ar.error);
    }
    auth = ar.value;
  } elif (caps & mysql_capability_secure_connection()) != 0 {
    kind = mysql_auth_response_kind_secure();
    let lr = _read_le(r, 1);
    if !lr.is_ok {
      return _err_response(lr.error);
    }
    let n: Int = lr.value;
    let br = _read_bytes_n(r, n);
    if !br.is_ok {
      return _err_response(br.error);
    }
    auth = br.value;
  } else {
    kind = mysql_auth_response_kind_nul_string();
    let nr = _read_nul_str(r);
    if !nr.is_ok {
      return _err_response(nr.error);
    }
    let s: Str = nr.value;
    auth = _str_bytes(s);
  }
  var database: Str = "";
  if (caps & mysql_capability_connect_with_db()) != 0 {
    let dr = _read_nul_str(r);
    if !dr.is_ok {
      return _err_response(dr.error);
    }
    database = dr.value;
  }
  var plugin: Str = "";
  if (caps & mysql_capability_plugin_auth()) != 0 {
    let pnr = _read_nul_str(r);
    if !pnr.is_ok {
      return _err_response(pnr.error);
    }
    plugin = pnr.value;
  }
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  if (caps & mysql_capability_connect_attrs()) != 0 {
    let attr_start: Int = r.pos;
    let tr = mysql_read_lenenc_int(r);
    if !tr.is_ok {
      return _err_response(tr.error);
    }
    let total_attrs: Int = tr.value;
    let end: Int = r.pos + total_attrs;
    let avail: Int = r.data.len();
    if end > avail {
      return _err_response(_bad_len_msg(total_attrs, attr_start));
    }
    while r.pos < end {
      let kn = mysql_read_lenenc_str(r);
      if !kn.is_ok {
        return _err_response(kn.error);
      }
      let vn = mysql_read_lenenc_str(r);
      if !vn.is_ok {
        return _err_response(vn.error);
      }
      if r.pos > end {
        return _err_response("mysql: connect attrs length mismatch at offset " + convert.int_to_string(attr_start));
      }
      names.push(kn.value);
      values.push(vn.value);
    }
  }
  let total: Int = r.data.len();
  if r.pos != total {
    return _err_response("mysql: trailing bytes at offset " + convert.int_to_string(r.pos));
  }
  return _ok_response(MysqlHandshakeResponse{ capability_flags: caps; max_packet_size: max_packet; character_set: character_set; username: username; auth_response_kind: kind; auth_response: auth; database: database; auth_plugin_name: plugin; attr_names: names; attr_values: values; });
}

/// Append a handshake response 41 packet. The auth response kind must match
/// the capability flags (lenenc bit wins over secure bit wins over the
/// NUL-string default), a secure auth response must fit 255 bytes, and
/// every string field must be NUL-free. Complexity: O(packet).
pub fn mysql_write_handshake_response(w: &mut MysqlWriter, h: &MysqlHandshakeResponse) -> Result[Bool, Str] {
  let caps: Int = h.capability_flags;
  if caps < 0 {
    return _err_bool("mysql: bad capability flags " + convert.int_to_string(caps));
  }
  let kind: Int = h.auth_response_kind;
  let auth: Vec[UInt8] = h.auth_response;
  if (caps & mysql_capability_plugin_auth_lenenc_client_data()) != 0 {
    if kind != mysql_auth_response_kind_lenenc() {
      return _err_bool("mysql: handshake response auth kind " + convert.int_to_string(kind) + " does not match capability flags");
    }
  } elif (caps & mysql_capability_secure_connection()) != 0 {
    if kind != mysql_auth_response_kind_secure() {
      return _err_bool("mysql: handshake response auth kind " + convert.int_to_string(kind) + " does not match capability flags");
    }
    if auth.len() > 255 {
      return _err_bool("mysql: auth response length " + convert.int_to_string(auth.len()) + " exceeds 255");
    }
  } else {
    if kind != mysql_auth_response_kind_nul_string() {
      return _err_bool("mysql: handshake response auth kind " + convert.int_to_string(kind) + " does not match capability flags");
    }
    if _bytes_have_nul(&auth) {
      return _err_bool("mysql: string contains nul");
    }
  }
  if _str_has_nul(h.username) {
    return _err_bool("mysql: string contains nul");
  }
  if _str_has_nul(h.database) {
    return _err_bool("mysql: string contains nul");
  }
  if _str_has_nul(h.auth_plugin_name) {
    return _err_bool("mysql: string contains nul");
  }
  let attr_count: Int = h.attr_names.len();
  if attr_count != h.attr_values.len() {
    return _err_bool("mysql: connect attrs name/value count mismatch");
  }
  _w_push_le(w, caps, 4);
  _w_push_le(w, h.max_packet_size, 4);
  _w_push_le(w, h.character_set, 1);
  var i = 0;
  while i < 23 {
    _w_push_byte(w, 0);
    i = i + 1;
  }
  _w_push_str(w, h.username);
  _w_push_byte(w, 0);
  if kind == mysql_auth_response_kind_lenenc() {
    _w_push_lenenc_len(w, auth.len());
    _w_push_bytes(w, &auth);
  } elif kind == mysql_auth_response_kind_secure() {
    _w_push_le(w, auth.len(), 1);
    _w_push_bytes(w, &auth);
  } else {
    _w_push_bytes(w, &auth);
    _w_push_byte(w, 0);
  }
  if (caps & mysql_capability_connect_with_db()) != 0 {
    _w_push_str(w, h.database);
    _w_push_byte(w, 0);
  }
  if (caps & mysql_capability_plugin_auth()) != 0 {
    _w_push_str(w, h.auth_plugin_name);
    _w_push_byte(w, 0);
  }
  if (caps & mysql_capability_connect_attrs()) != 0 {
    var tmp = mysql_writer_new();
    var j = 0;
    while j < attr_count {
      let kn: Str = h.attr_names[j];
      let vn: Str = h.attr_values[j];
      if _str_has_nul(kn) || _str_has_nul(vn) {
        return _err_bool("mysql: string contains nul");
      }
      _w_push_lenenc_len(&mut tmp, string.str_len(kn));
      _w_push_str(&mut tmp, kn);
      _w_push_lenenc_len(&mut tmp, string.str_len(vn));
      _w_push_str(&mut tmp, vn);
      j = j + 1;
    }
    let blob: Vec[UInt8] = mysql_writer_bytes(&tmp);
    _w_push_lenenc_len(w, blob.len());
    _w_push_bytes(w, &blob);
  }
  return _ok_bool(true);
}

/// Read a 32-byte SSL request packet. The CLIENT_SSL bit must be set and
/// the payload must be exactly 32 bytes. Complexity: O(1).
pub fn mysql_read_ssl_request(r: &mut MysqlReader) -> Result[MysqlSslRequest, Str] {
  let start: Int = r.pos;
  let total: Int = r.data.len();
  let remaining: Int = total - start;
  if remaining != _SSL_REQUEST_LEN {
    return _err_ssl("mysql: bad ssl request length " + convert.int_to_string(remaining) + " at offset " + convert.int_to_string(start));
  }
  let cr = _read_le(r, 4);
  if !cr.is_ok {
    return _err_ssl(cr.error);
  }
  let caps: Int = cr.value;
  if (caps & mysql_capability_ssl()) == 0 {
    return _err_ssl("mysql: ssl request without CLIENT_SSL at offset " + convert.int_to_string(start));
  }
  let mr = _read_le(r, 4);
  if !mr.is_ok {
    return _err_ssl(mr.error);
  }
  let csr = _read_le(r, 1);
  if !csr.is_ok {
    return _err_ssl(csr.error);
  }
  let fillr = _read_bytes_n(r, 23);
  if !fillr.is_ok {
    return _err_ssl(fillr.error);
  }
  return _ok_ssl(MysqlSslRequest{ capability_flags: caps; max_packet_size: mr.value; character_set: csr.value; });
}

/// Append a 32-byte SSL request packet (23 zero filler bytes).
/// Complexity: O(1).
pub fn mysql_write_ssl_request(w: &mut MysqlWriter, capability_flags: Int, max_packet_size: Int, character_set: Int) {
  _w_push_le(w, capability_flags, 4);
  _w_push_le(w, max_packet_size, 4);
  _w_push_le(w, character_set, 1);
  var i = 0;
  while i < 23 {
    _w_push_byte(w, 0);
    i = i + 1;
  }
}

/// True when a payload is exactly 32 bytes and its little-endian capability
/// flags have CLIENT_SSL set (the shape of an SSL request).
/// Complexity: O(1).
pub fn mysql_is_ssl_request_payload(payload: &Vec[UInt8]) -> Bool {
  if payload.len() != _SSL_REQUEST_LEN {
    return false;
  }
  let b0: Int = (payload[0] as Int) & 0xFF;
  let b1: Int = (payload[1] as Int) & 0xFF;
  let b2: Int = (payload[2] as Int) & 0xFF;
  let b3: Int = (payload[3] as Int) & 0xFF;
  let caps: Int = b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
  return (caps & mysql_capability_ssl()) != 0;
}

/// Combined capability flags of an SSL request. Complexity: O(1).
pub fn mysql_ssl_request_capability_flags(s: &MysqlSslRequest) -> Int {
  return s.capability_flags;
}

/// Max-packet-size field of an SSL request. Complexity: O(1).
pub fn mysql_ssl_request_max_packet_size(s: &MysqlSslRequest) -> Int {
  return s.max_packet_size;
}

/// Character set id of an SSL request. Complexity: O(1).
pub fn mysql_ssl_request_character_set(s: &MysqlSslRequest) -> Int {
  return s.character_set;
}

/// Combined capability flags of a handshake response. Complexity: O(1).
pub fn mysql_response_capability_flags(h: &MysqlHandshakeResponse) -> Int {
  return h.capability_flags;
}

/// Max-packet-size field of a handshake response. Complexity: O(1).
pub fn mysql_response_max_packet_size(h: &MysqlHandshakeResponse) -> Int {
  return h.max_packet_size;
}

/// Character set id of a handshake response. Complexity: O(1).
pub fn mysql_response_character_set(h: &MysqlHandshakeResponse) -> Int {
  return h.character_set;
}

/// Username of a handshake response. Complexity: O(1).
pub fn mysql_response_username(h: &MysqlHandshakeResponse) -> Str {
  let s: Str = h.username;
  return s;
}

/// Auth response framing kind of a handshake response. Complexity: O(1).
pub fn mysql_response_auth_kind(h: &MysqlHandshakeResponse) -> Int {
  return h.auth_response_kind;
}

/// A copy of the auth response bytes. Complexity: O(len).
pub fn mysql_response_auth_response(h: &MysqlHandshakeResponse) -> Vec[UInt8] {
  let v: Vec[UInt8] = h.auth_response;
  return _copy_bytes(&v);
}

/// Database of a handshake response, or "" when CLIENT_CONNECT_WITH_DB was
/// not set. Complexity: O(1).
pub fn mysql_response_database(h: &MysqlHandshakeResponse) -> Str {
  let s: Str = h.database;
  return s;
}

/// Auth plugin name of a handshake response, or "" when CLIENT_PLUGIN_AUTH
/// was not set. Complexity: O(1).
pub fn mysql_response_auth_plugin_name(h: &MysqlHandshakeResponse) -> Str {
  let s: Str = h.auth_plugin_name;
  return s;
}

/// Number of connect attributes. Complexity: O(1).
pub fn mysql_response_attr_count(h: &MysqlHandshakeResponse) -> Int {
  return h.attr_names.len();
}

/// Attribute name `i`, or "" when out of range. Complexity: O(1).
pub fn mysql_response_attr_name(h: &MysqlHandshakeResponse, i: Int) -> Str {
  if i < 0 || i >= h.attr_names.len() {
    return "";
  }
  let s: Str = h.attr_names[i];
  return s;
}

/// Attribute value `i`, or "" when out of range. Complexity: O(1).
pub fn mysql_response_attr_value_at(h: &MysqlHandshakeResponse, i: Int) -> Str {
  if i < 0 || i >= h.attr_values.len() {
    return "";
  }
  let s: Str = h.attr_values[i];
  return s;
}

/// Value of attribute `key` (str_compare, case-sensitive), or "" when the
/// attribute is absent. Complexity: O(attrs).
pub fn mysql_response_attr_value(h: &MysqlHandshakeResponse, key: Str) -> Str {
  var i = 0;
  while i < h.attr_names.len() {
    let k: Str = h.attr_names[i];
    if compare.str_compare(k, key) == 0 {
      let v: Str = h.attr_values[i];
      return v;
    }
    i = i + 1;
  }
  return "";
}

// --------------------------------------------------
//  OK / ERR / EOF / LOCAL INFILE
// --------------------------------------------------

/// Read an OK packet payload: 0x00, length-encoded affected rows,
/// length-encoded last insert id, status flags u16, warnings u16, then the
/// info bytes to the end of the payload. With CLIENT_SESSION_TRACK the info
/// field is length-encoded on the wire and a state block may follow; that
/// variant is documented but not decoded. Complexity: O(payload).
pub fn mysql_read_ok(r: &mut MysqlReader) -> Result[MysqlOk, Str] {
  let start: Int = r.pos;
  let hr = _read_le(r, 1);
  if !hr.is_ok {
    return _err_okp(hr.error);
  }
  let first: Int = hr.value;
  if first != 0 {
    return _err_okp("mysql: not an OK packet (first byte " + convert.int_to_string(first) + ") at offset " + convert.int_to_string(start));
  }
  let ar = mysql_read_lenenc_int(r);
  if !ar.is_ok {
    return _err_okp(ar.error);
  }
  let lr = mysql_read_lenenc_int(r);
  if !lr.is_ok {
    return _err_okp(lr.error);
  }
  let st_r = _read_le(r, 2);
  if !st_r.is_ok {
    return _err_okp(st_r.error);
  }
  let wn_r = _read_le(r, 2);
  if !wn_r.is_ok {
    return _err_okp(wn_r.error);
  }
  let irstr = _read_rest_str(r);
  if !irstr.is_ok {
    return _err_okp(irstr.error);
  }
  return _ok_okp(MysqlOk{ affected_rows: ar.value; last_insert_id: lr.value; status_flags: st_r.value; warnings: wn_r.value; info: irstr.value; });
}

/// Append an OK packet payload. Err for negative affected-rows/last-insert-id
/// and for NUL bytes in info. Complexity: O(payload).
pub fn mysql_write_ok(w: &mut MysqlWriter, o: &MysqlOk) -> Result[Bool, Str] {
  let ar: Int = o.affected_rows;
  let li: Int = o.last_insert_id;
  if ar < 0 || li < 0 {
    return _err_bool("mysql: bad length-encoded integer " + convert.int_to_string(ar));
  }
  if _str_has_nul(o.info) {
    return _err_bool("mysql: string contains nul");
  }
  _w_push_byte(w, 0);
  _w_push_lenenc_len(w, ar);
  _w_push_lenenc_len(w, li);
  _w_push_le(w, o.status_flags, 2);
  _w_push_le(w, o.warnings, 2);
  _w_push_str(w, o.info);
  return _ok_bool(true);
}

/// Read an ERR packet payload: 0xFF, error code u16, then either '#' + a
/// 5-byte SQLSTATE and the message, or the message directly. A '#' byte at
/// the message position is always treated as the SQLSTATE marker; a short
/// SQLSTATE is rejected as truncation. Complexity: O(payload).
pub fn mysql_read_err(r: &mut MysqlReader) -> Result[MysqlErr, Str] {
  let start: Int = r.pos;
  let hr = _read_le(r, 1);
  if !hr.is_ok {
    return _err_errp(hr.error);
  }
  let first: Int = hr.value;
  if first != 255 {
    return _err_errp("mysql: not an ERR packet (first byte " + convert.int_to_string(first) + ") at offset " + convert.int_to_string(start));
  }
  let cr = _read_le(r, 2);
  if !cr.is_ok {
    return _err_errp(cr.error);
  }
  let code: Int = cr.value;
  var has_state: Bool = false;
  var state: Str = "";
  let total: Int = r.data.len();
  if r.pos < total {
    let nb: Int = _r_byte_mut(r, r.pos);
    if nb == 35 {
      r.pos = r.pos + 1;
      if r.pos + 5 > total {
        return _err_errp(_trunc_at(r.pos));
      }
      let sr = _range_to_str(r, r.pos, r.pos + 5);
      if !sr.is_ok {
        return _err_errp(sr.error);
      }
      state = sr.value;
      r.pos = r.pos + 5;
      has_state = true;
    }
  }
  let mr = _read_rest_str(r);
  if !mr.is_ok {
    return _err_errp(mr.error);
  }
  return _ok_errp(MysqlErr{ code: code; has_sqlstate: has_state; sqlstate: state; message: mr.value; });
}

/// Append an ERR packet payload. When has_sqlstate is set, sqlstate must be
/// exactly 5 bytes. Err for NUL bytes in message/sqlstate. Complexity:
/// O(payload).
pub fn mysql_write_err(w: &mut MysqlWriter, e: &MysqlErr) -> Result[Bool, Str] {
  if _str_has_nul(e.message) {
    return _err_bool("mysql: string contains nul");
  }
  let has: Bool = e.has_sqlstate;
  let state: Str = e.sqlstate;
  if has {
    if string.str_len(state) != 5 {
      return _err_bool("mysql: bad sqlstate length " + convert.int_to_string(string.str_len(state)));
    }
    if _str_has_nul(state) {
      return _err_bool("mysql: string contains nul");
    }
  }
  _w_push_byte(w, 255);
  _w_push_le(w, e.code, 2);
  if has {
    _w_push_byte(w, 35);
    _w_push_str(w, state);
  }
  _w_push_str(w, e.message);
  return _ok_bool(true);
}

/// Read an EOF packet payload: 0xFE, warnings u16, status flags u16. The
/// caller must have applied the "payload shorter than 9 bytes" rule (see
/// mysql_packet_kind); any trailing byte is rejected. Complexity: O(1).
pub fn mysql_read_eof(r: &mut MysqlReader) -> Result[MysqlEof, Str] {
  let start: Int = r.pos;
  let hr = _read_le(r, 1);
  if !hr.is_ok {
    return _err_eofp(hr.error);
  }
  let first: Int = hr.value;
  if first != 254 {
    return _err_eofp("mysql: not an EOF packet (first byte " + convert.int_to_string(first) + ") at offset " + convert.int_to_string(start));
  }
  let wn_r = _read_le(r, 2);
  if !wn_r.is_ok {
    return _err_eofp(wn_r.error);
  }
  let st_r = _read_le(r, 2);
  if !st_r.is_ok {
    return _err_eofp(st_r.error);
  }
  let total: Int = r.data.len();
  if r.pos != total {
    return _err_eofp("mysql: trailing bytes at offset " + convert.int_to_string(r.pos));
  }
  return _ok_eofp(MysqlEof{ warnings: wn_r.value; status_flags: st_r.value; });
}

/// Append an EOF packet payload (0xFE, warnings u16, status u16).
/// Complexity: O(1).
pub fn mysql_write_eof(w: &mut MysqlWriter, e: &MysqlEof) {
  _w_push_byte(w, 254);
  _w_push_le(w, e.warnings, 2);
  _w_push_le(w, e.status_flags, 2);
}

/// Read a LOCAL INFILE packet payload: 0xFB followed by the file name bytes
/// to the end of the payload. Complexity: O(payload).
pub fn mysql_read_local_infile(r: &mut MysqlReader) -> Result[Str, Str] {
  let start: Int = r.pos;
  let br = _read_le(r, 1);
  if !br.is_ok {
    return _err_str(br.error);
  }
  let first: Int = br.value;
  if first != 251 {
    return _err_str("mysql: not a LOCAL INFILE packet (first byte " + convert.int_to_string(first) + ") at offset " + convert.int_to_string(start));
  }
  return _read_rest_str(r);
}

/// The file name of a LOCAL INFILE payload (0xFB + name), or an error when
/// the first byte is not 0xFB. Complexity: O(payload).
pub fn mysql_local_infile_filename(payload: &Vec[UInt8]) -> Result[Str, Str] {
  if payload.len() == 0 {
    return _err_str("mysql: not a LOCAL INFILE packet (empty payload) at offset 0");
  }
  let first: Int = (payload[0] as Int) & 0xFF;
  if first != 251 {
    return _err_str("mysql: not a LOCAL INFILE packet (first byte " + convert.int_to_string(first) + ") at offset 0");
  }
  return _payload_range_to_str(payload, 1, payload.len());
}

/// Affected rows of an OK packet. Complexity: O(1).
pub fn mysql_ok_affected_rows(o: &MysqlOk) -> Int {
  return o.affected_rows;
}

/// Last insert id of an OK packet. Complexity: O(1).
pub fn mysql_ok_last_insert_id(o: &MysqlOk) -> Int {
  return o.last_insert_id;
}

/// Status flags of an OK packet. Complexity: O(1).
pub fn mysql_ok_status_flags(o: &MysqlOk) -> Int {
  return o.status_flags;
}

/// Warning count of an OK packet. Complexity: O(1).
pub fn mysql_ok_warnings(o: &MysqlOk) -> Int {
  return o.warnings;
}

/// Info string of an OK packet (raw-rest interpretation; see
/// mysql_read_ok). Complexity: O(1).
pub fn mysql_ok_info(o: &MysqlOk) -> Str {
  let s: Str = o.info;
  return s;
}

/// Error code of an ERR packet. Complexity: O(1).
pub fn mysql_err_code(e: &MysqlErr) -> Int {
  return e.code;
}

/// True when an ERR packet carried a SQLSTATE. Complexity: O(1).
pub fn mysql_err_has_sqlstate(e: &MysqlErr) -> Bool {
  return e.has_sqlstate;
}

/// SQLSTATE of an ERR packet, or "" when absent. Complexity: O(1).
pub fn mysql_err_sqlstate(e: &MysqlErr) -> Str {
  let s: Str = e.sqlstate;
  return s;
}

/// Message of an ERR packet. Complexity: O(1).
pub fn mysql_err_message(e: &MysqlErr) -> Str {
  let s: Str = e.message;
  return s;
}

/// Warning count of an EOF packet. Complexity: O(1).
pub fn mysql_eof_warnings(e: &MysqlEof) -> Int {
  return e.warnings;
}

/// Status flags of an EOF packet. Complexity: O(1).
pub fn mysql_eof_status_flags(e: &MysqlEof) -> Int {
  return e.status_flags;
}

// --------------------------------------------------
//  Commands
// --------------------------------------------------

/// Read a command packet: a 1-byte command code, then for COM_QUERY (0x03),
/// COM_INIT_DB (0x02) and COM_STMT_PREPARE (0x16) the UTF-8 argument to the
/// end of the payload. For every other command the payload must be exactly
/// one byte. Complexity: O(payload).
pub fn mysql_read_command(r: &mut MysqlReader) -> Result[MysqlCommand, Str] {
  let cr = _read_le(r, 1);
  if !cr.is_ok {
    return _err_command(cr.error);
  }
  let code: Int = cr.value;
  var arg: Str = "";
  if code == 3 || code == 2 || code == 22 {
    let ar = _read_rest_str(r);
    if !ar.is_ok {
      return _err_command(ar.error);
    }
    arg = ar.value;
  } else {
    let total: Int = r.data.len();
    if r.pos != total {
      return _err_command("mysql: unexpected trailing bytes for command " + convert.int_to_string(code) + " at offset " + convert.int_to_string(r.pos));
    }
  }
  return _ok_command(MysqlCommand{ code: code; arg: arg; });
}

/// Append a COM_QUERY packet (0x03 + SQL). Err when the SQL contains 0x00.
/// Complexity: O(payload).
pub fn mysql_write_com_query(w: &mut MysqlWriter, sql: Str) -> Result[Bool, Str] {
  if _str_has_nul(sql) {
    return _err_bool("mysql: string contains nul");
  }
  _w_push_byte(w, 3);
  _w_push_str(w, sql);
  return _ok_bool(true);
}

/// Append a COM_INIT_DB packet (0x02 + database). Err when the name contains
/// 0x00. Complexity: O(payload).
pub fn mysql_write_com_init_db(w: &mut MysqlWriter, db: Str) -> Result[Bool, Str] {
  if _str_has_nul(db) {
    return _err_bool("mysql: string contains nul");
  }
  _w_push_byte(w, 2);
  _w_push_str(w, db);
  return _ok_bool(true);
}

/// Append a COM_QUIT packet (0x01). Complexity: O(1).
pub fn mysql_write_com_quit(w: &mut MysqlWriter) {
  _w_push_byte(w, 1);
}

/// Append a COM_PING packet (0x0E). Complexity: O(1).
pub fn mysql_write_com_ping(w: &mut MysqlWriter) {
  _w_push_byte(w, 14);
}

/// Append a COM_STMT_PREPARE packet (0x16 + SQL). Err when the SQL contains
/// 0x00. Complexity: O(payload).
pub fn mysql_write_com_stmt_prepare(w: &mut MysqlWriter, sql: Str) -> Result[Bool, Str] {
  if _str_has_nul(sql) {
    return _err_bool("mysql: string contains nul");
  }
  _w_push_byte(w, 22);
  _w_push_str(w, sql);
  return _ok_bool(true);
}

/// Command code of a decoded command. Complexity: O(1).
pub fn mysql_command_code(c: &MysqlCommand) -> Int {
  return c.code;
}

/// Argument of a decoded command, or "" when the command takes none.
/// Complexity: O(1).
pub fn mysql_command_arg(c: &MysqlCommand) -> Str {
  let s: Str = c.arg;
  return s;
}

// --------------------------------------------------
//  Result sets
// --------------------------------------------------

/// Read a column-count packet: a length-encoded integer that must be
/// positive (a zero count is an OK packet, not a result set). Complexity:
/// O(1).
pub fn mysql_read_column_count(r: &mut MysqlReader) -> Result[Int, Str] {
  let start: Int = r.pos;
  let lr = mysql_read_lenenc_int(r);
  if !lr.is_ok {
    return _err_int(lr.error);
  }
  if lr.value <= 0 {
    return _err_int("mysql: bad column count " + convert.int_to_string(lr.value) + " at offset " + convert.int_to_string(start));
  }
  return _ok_int(lr.value);
}

/// Append a column-count packet. Err for a non-positive count.
/// Complexity: O(1).
pub fn mysql_write_column_count(w: &mut MysqlWriter, n: Int) -> Result[Bool, Str] {
  if n <= 0 {
    return _err_bool("mysql: bad column count " + convert.int_to_string(n));
  }
  _w_push_lenenc_len(w, n);
  return _ok_bool(true);
}

/// Read a column definition packet 41: six length-encoded strings
/// (catalog, schema, table, org_table, name, org_name), the 0x0C filler as a
/// length-encoded integer that must equal 12, charset u16, column length
/// u32, type u8, flags u16, decimals u8 and two trailing filler bytes.
/// Trailing bytes after the fixed fields are rejected. Complexity:
/// O(packet).
pub fn mysql_read_column_definition(r: &mut MysqlReader) -> Result[MysqlColumn, Str] {
  let cr = mysql_read_lenenc_str(r);
  if !cr.is_ok {
    return _err_column(cr.error);
  }
  let sr = mysql_read_lenenc_str(r);
  if !sr.is_ok {
    return _err_column(sr.error);
  }
  let tr = mysql_read_lenenc_str(r);
  if !tr.is_ok {
    return _err_column(tr.error);
  }
  let otr = mysql_read_lenenc_str(r);
  if !otr.is_ok {
    return _err_column(otr.error);
  }
  let nr = mysql_read_lenenc_str(r);
  if !nr.is_ok {
    return _err_column(nr.error);
  }
  let onr = mysql_read_lenenc_str(r);
  if !onr.is_ok {
    return _err_column(onr.error);
  }
  let fill_start: Int = r.pos;
  let flr = mysql_read_lenenc_int(r);
  if !flr.is_ok {
    return _err_column(flr.error);
  }
  if flr.value != _COLUMN_FILLER {
    return _err_column("mysql: bad column definition filler " + convert.int_to_string(flr.value) + " at offset " + convert.int_to_string(fill_start));
  }
  let csr = _read_le(r, 2);
  if !csr.is_ok {
    return _err_column(csr.error);
  }
  let clr = _read_le(r, 4);
  if !clr.is_ok {
    return _err_column(clr.error);
  }
  let tyr = _read_le(r, 1);
  if !tyr.is_ok {
    return _err_column(tyr.error);
  }
  let flr2 = _read_le(r, 2);
  if !flr2.is_ok {
    return _err_column(flr2.error);
  }
  let dcr = _read_le(r, 1);
  if !dcr.is_ok {
    return _err_column(dcr.error);
  }
  let padr = _read_bytes_n(r, 2);
  if !padr.is_ok {
    return _err_column(padr.error);
  }
  let total: Int = r.data.len();
  if r.pos != total {
    return _err_column("mysql: trailing bytes at offset " + convert.int_to_string(r.pos));
  }
  return _ok_column(MysqlColumn{ catalog: cr.value; schema: sr.value; table_name: tr.value; org_table: otr.value; name: nr.value; org_name: onr.value; charset: csr.value; column_length: clr.value; type_code: tyr.value; flags: flr2.value; decimals: dcr.value; });
}

/// Append a column definition packet 41. Err for NUL bytes in the six name
/// strings. Complexity: O(packet).
pub fn mysql_write_column_definition(w: &mut MysqlWriter, c: &MysqlColumn) -> Result[Bool, Str] {
  let catalog: Str = c.catalog;
  let schema: Str = c.schema;
  let table_name: Str = c.table_name;
  let org_table: Str = c.org_table;
  let name: Str = c.name;
  let org_name: Str = c.org_name;
  if _str_has_nul(catalog) || _str_has_nul(schema) || _str_has_nul(table_name) {
    return _err_bool("mysql: string contains nul");
  }
  if _str_has_nul(org_table) || _str_has_nul(name) || _str_has_nul(org_name) {
    return _err_bool("mysql: string contains nul");
  }
  _w_push_lenenc_len(w, string.str_len(catalog));
  _w_push_str(w, catalog);
  _w_push_lenenc_len(w, string.str_len(schema));
  _w_push_str(w, schema);
  _w_push_lenenc_len(w, string.str_len(table_name));
  _w_push_str(w, table_name);
  _w_push_lenenc_len(w, string.str_len(org_table));
  _w_push_str(w, org_table);
  _w_push_lenenc_len(w, string.str_len(name));
  _w_push_str(w, name);
  _w_push_lenenc_len(w, string.str_len(org_name));
  _w_push_str(w, org_name);
  _w_push_byte(w, _COLUMN_FILLER);
  _w_push_le(w, c.charset, 2);
  _w_push_le(w, c.column_length, 4);
  _w_push_le(w, c.type_code, 1);
  _w_push_le(w, c.flags, 2);
  _w_push_le(w, c.decimals, 1);
  _w_push_byte(w, 0);
  _w_push_byte(w, 0);
  return _ok_bool(true);
}

/// Read a text-protocol row with exactly `column_count` cells: each cell is
/// either 0xFB (NULL) or a length-encoded string. `values` and `nulls` are
/// parallel and have column_count entries. Trailing bytes after the last
/// cell are rejected. Complexity: O(packet).
pub fn mysql_read_text_row(r: &mut MysqlReader, column_count: Int) -> Result[MysqlTextRow, Str] {
  let start: Int = r.pos;
  if column_count < 0 {
    return _err_row(_bad_len_msg(column_count, start));
  }
  var values = Vec[Str].new();
  var nulls = Vec[Bool].new();
  var i = 0;
  while i < column_count {
    let total: Int = r.data.len();
    if r.pos >= total {
      return _err_row(_trunc_at(r.pos));
    }
    let b: Int = _r_byte_mut(r, r.pos);
    if b == 251 {
      r.pos = r.pos + 1;
      values.push("");
      nulls.push(true);
    } else {
      let sr = mysql_read_lenenc_str(r);
      if !sr.is_ok {
        return _err_row(sr.error);
      }
      values.push(sr.value);
      nulls.push(false);
    }
    i = i + 1;
  }
  let total2: Int = r.data.len();
  if r.pos != total2 {
    return _err_row("mysql: trailing bytes in text row at offset " + convert.int_to_string(r.pos));
  }
  return _ok_row(MysqlTextRow{ values: values; nulls: nulls; });
}

/// Append a text-protocol row. `values` and `nulls` must be parallel; a
/// NULL cell (nulls[i] == true) is written as 0xFB and its values[i] is
/// ignored, every other cell as a length-encoded string. Err on a count
/// mismatch or NUL bytes in a non-null cell. Complexity: O(packet).
pub fn mysql_write_text_row(w: &mut MysqlWriter, row: &MysqlTextRow) -> Result[Bool, Str] {
  let values: Vec[Str] = row.values;
  let nulls: Vec[Bool] = row.nulls;
  if values.len() != nulls.len() {
    return _err_bool("mysql: text row cell count mismatch");
  }
  var i = 0;
  while i < values.len() {
    let is_null: Bool = nulls[i];
    if is_null {
      _w_push_byte(w, 251);
    } else {
      let s: Str = values[i];
      if _str_has_nul(s) {
        return _err_bool("mysql: string contains nul");
      }
      _w_push_lenenc_len(w, string.str_len(s));
      _w_push_str(w, s);
    }
    i = i + 1;
  }
  return _ok_bool(true);
}

/// Catalog of a column definition. Complexity: O(1).
pub fn mysql_column_catalog(c: &MysqlColumn) -> Str {
  let s: Str = c.catalog;
  return s;
}

/// Schema of a column definition. Complexity: O(1).
pub fn mysql_column_schema(c: &MysqlColumn) -> Str {
  let s: Str = c.schema;
  return s;
}

/// Table name of a column definition (alias). Complexity: O(1).
pub fn mysql_column_table(c: &MysqlColumn) -> Str {
  let s: Str = c.table_name;
  return s;
}

/// Original table name of a column definition. Complexity: O(1).
pub fn mysql_column_org_table(c: &MysqlColumn) -> Str {
  let s: Str = c.org_table;
  return s;
}

/// Column name of a column definition. Complexity: O(1).
pub fn mysql_column_name(c: &MysqlColumn) -> Str {
  let s: Str = c.name;
  return s;
}

/// Original column name of a column definition. Complexity: O(1).
pub fn mysql_column_org_name(c: &MysqlColumn) -> Str {
  let s: Str = c.org_name;
  return s;
}

/// Charset id of a column definition. Complexity: O(1).
pub fn mysql_column_charset(c: &MysqlColumn) -> Int {
  return c.charset;
}

/// Column length of a column definition. Complexity: O(1).
pub fn mysql_column_length(c: &MysqlColumn) -> Int {
  return c.column_length;
}

/// Type code of a column definition. Complexity: O(1).
pub fn mysql_column_type_code(c: &MysqlColumn) -> Int {
  return c.type_code;
}

/// Name of a column definition's type code (see mysql_type_name).
/// Complexity: O(1).
pub fn mysql_column_type_name(c: &MysqlColumn) -> Str {
  return mysql_type_name(c.type_code);
}

/// Flags of a column definition. Complexity: O(1).
pub fn mysql_column_flags(c: &MysqlColumn) -> Int {
  return c.flags;
}

/// Decimals of a column definition. Complexity: O(1).
pub fn mysql_column_decimals(c: &MysqlColumn) -> Int {
  return c.decimals;
}

/// Cell count of a text row. Complexity: O(1).
pub fn mysql_text_row_cell_count(r: &MysqlTextRow) -> Int {
  return r.values.len();
}

/// True when cell `i` of a text row is NULL (false when out of range).
/// Complexity: O(1).
pub fn mysql_text_row_cell_is_null(r: &MysqlTextRow, i: Int) -> Bool {
  if i < 0 || i >= r.nulls.len() {
    return false;
  }
  let b: Bool = r.nulls[i];
  return b;
}

/// Cell `i` of a text row as a Str ("" when NULL or out of range).
/// Complexity: O(1).
pub fn mysql_text_row_cell_str(r: &MysqlTextRow, i: Int) -> Str {
  if i < 0 || i >= r.values.len() {
    return "";
  }
  let s: Str = r.values[i];
  return s;
}

/// Number of NULL cells in a text row. Complexity: O(cells).
pub fn mysql_text_row_null_count(r: &MysqlTextRow) -> Int {
  var count = 0;
  var i = 0;
  while i < r.nulls.len() {
    let b: Bool = r.nulls[i];
    if b {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

