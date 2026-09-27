// XIOM -- xiom.cassandra: CQL native protocol v4 frame structure codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI, no dependencies beyond xiom.std) structural codec for
// the Apache Cassandra native protocol version 4 (the CQL binary protocol):
// the 9-byte frame header, the protocol primitive types, and the request and
// response bodies of STARTUP, QUERY, RESULT and ERROR. There is no transport,
// no compression codec, no authentication exchange, no CQL text analysis and
// no server. See SPEC.md for the byte-level layouts and the error catalog.
//
// Implemented:
//   * frame header: version byte (request 0x04 / response 0x84; the v3
//     0x03/0x83 pair is recognized and reported, v4 is the target), flags
//     byte (compression 0x01, tracing 0x02, custom payload 0x04, warning
//     0x08, use beta 0x10), stream id int16 (signed), opcode byte and body
//     length int32. The opcode table covers ERROR 0x00 through AUTH_SUCCESS
//     0x10 (0x04 is unused); unknown opcodes are preserved raw and named
//     "UNKNOWN".
//   * primitives: [int], [long], [byte], [short], [string], [long string],
//     [bytes], [value] (null -1 / not set -2), [short bytes], [string list],
//     [string map], [string multimap], [bytes map].
//   * bodies: STARTUP [string map]; QUERY [long string] + consistency
//     [short] + flags [byte] with the optional value, page-size, paging-
//     state, serial-consistency and timestamp sections; RESULT kinds VOID,
//     ROWS (metadata + rows), SET_KEYSPACE, PREPARED (id + metadata + result
//     metadata) and SCHEMA_CHANGE; ERROR (code + message + per-code extras)
//     with the 0x0000..0x2500 code table.
//   * every reader is bounds-checked and its errors carry the byte offset of
//     the failing read; negative lengths, truncated input and oversized
//     hostile counts are rejected with deterministic messages.
//
// Documented boundaries:
//   * [string] payloads must be valid UTF-8 and NUL-free (v0.61.3's
//     sb_to_str aborts on a 0x00); malformed UTF-8 and NUL bytes are
//     rejected with deterministic errors.
//   * a null [bytes] (-1) is rejected by cql_read_bytes; the [value] reader
//     cql_read_value represents null (-1) and not set (-2) explicitly.
//   * unknown opcodes, frame flag bits, query flag bits, consistency levels
//     and error codes are preserved raw; the cql_*_known / cql_*_name
//     helpers report what the v4 tables define.
//   * QUERY flag 0x80 (keyspace) is exposed as a constant but is a v5 flag
//     and is not interpreted by the v4 body reader.
//   * the type option reader renders a display string (e.g. "list<int>",
//     "udt(ks.name)") and consumes UDT field definitions without retaining
//     them; nesting is capped at depth 32.
//
// Non-goals: no sockets/TLS/DNS, no compression (lz4/snappy), no transport
// framing, no AUTHENTICATE/AUTH_CHALLENGE/AUTH_RESPONSE/AUTH_SUCCESS bodies,
// no PREPARE/EXECUTE/BATCH/REGISTER/EVENT body codecs, no CQL parser, no
// token-aware routing, no response-side compression unwrapping.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; flat and parallel vectors, never Vec[StructType];
//   * Ok/Err construction is confined to the leaf helpers below;
//   * every byte read is widened with `(b as Int) & 0xFF` before entering
//     Int arithmetic or comparisons;
//   * every vector element read is bound to an explicitly typed local;
//   * struct fields are never passed as `&struct.field` where a
//     `&Vec[UInt8]` parameter is expected (a local is bound first);
//   * big-endian fields are composed byte by byte; decoding accumulates at
//     most 63 bits before applying the sign bit;
//   * Str output is collected in a Vec[UInt8] and materialized with
//     sb_to_str only after the bytes were validated NUL-free UTF-8.

module xiom.cassandra

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

// Ok(v) for Result[CqlValue, Str].
fn _ok_value(v: CqlValue) -> Result[CqlValue, Str] {
  return Ok(v);
}

// Err(m) for Result[CqlValue, Str].
fn _err_value(m: Str) -> Result[CqlValue, Str] {
  return Err(m);
}

// Ok(v) for Result[CqlFrame, Str].
fn _ok_frame(v: CqlFrame) -> Result[CqlFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[CqlFrame, Str].
fn _err_frame(m: Str) -> Result[CqlFrame, Str] {
  return Err(m);
}

// Ok(v) for Result[CqlStringList, Str].
fn _ok_strlist(v: CqlStringList) -> Result[CqlStringList, Str] {
  return Ok(v);
}

// Err(m) for Result[CqlStringList, Str].
fn _err_strlist(m: Str) -> Result[CqlStringList, Str] {
  return Err(m);
}

// Ok(v) for Result[CqlStringMap, Str].
fn _ok_strmap(v: CqlStringMap) -> Result[CqlStringMap, Str] {
  return Ok(v);
}

// Err(m) for Result[CqlStringMap, Str].
fn _err_strmap(m: Str) -> Result[CqlStringMap, Str] {
  return Err(m);
}

// Ok(v) for Result[CqlStringMultiMap, Str].
fn _ok_multimap(v: CqlStringMultiMap) -> Result[CqlStringMultiMap, Str] {
  return Ok(v);
}

// Err(m) for Result[CqlStringMultiMap, Str].
fn _err_multimap(m: Str) -> Result[CqlStringMultiMap, Str] {
  return Err(m);
}

// Ok(v) for Result[CqlBytesMap, Str].
fn _ok_bytesmap(v: CqlBytesMap) -> Result[CqlBytesMap, Str] {
  return Ok(v);
}

// Err(m) for Result[CqlBytesMap, Str].
fn _err_bytesmap(m: Str) -> Result[CqlBytesMap, Str] {
  return Err(m);
}

// Ok(v) for Result[CqlQuery, Str].
fn _ok_query(v: CqlQuery) -> Result[CqlQuery, Str] {
  return Ok(v);
}

// Err(m) for Result[CqlQuery, Str].
fn _err_query(m: Str) -> Result[CqlQuery, Str] {
  return Err(m);
}

// Ok(v) for Result[CqlTypeInfo, Str].
fn _ok_typeinfo(v: CqlTypeInfo) -> Result[CqlTypeInfo, Str] {
  return Ok(v);
}

// Err(m) for Result[CqlTypeInfo, Str].
fn _err_typeinfo(m: Str) -> Result[CqlTypeInfo, Str] {
  return Err(m);
}

// Ok(v) for Result[CqlRowsMetadata, Str].
fn _ok_meta(v: CqlRowsMetadata) -> Result[CqlRowsMetadata, Str] {
  return Ok(v);
}

// Err(m) for Result[CqlRowsMetadata, Str].
fn _err_meta(m: Str) -> Result[CqlRowsMetadata, Str] {
  return Err(m);
}

// Ok(v) for Result[CqlResult, Str].
fn _ok_result(v: CqlResult) -> Result[CqlResult, Str] {
  return Ok(v);
}

// Err(m) for Result[CqlResult, Str].
fn _err_result(m: Str) -> Result[CqlResult, Str] {
  return Err(m);
}

// Ok(v) for Result[CqlErrorBody, Str].
fn _ok_errbody(v: CqlErrorBody) -> Result[CqlErrorBody, Str] {
  return Ok(v);
}

// Err(m) for Result[CqlErrorBody, Str].
fn _err_errbody(m: Str) -> Result[CqlErrorBody, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// An append-only encoder over a byte buffer. Create with cql_writer_new,
/// write with the cql_write_* functions, then take the bytes with
/// cql_writer_bytes (a copy).
pub type CqlWriter = {
  data: Vec[UInt8];
}

/// A bounds-checked cursor reader over an immutable byte buffer. Create with
/// cql_reader_new; all cql_read_* functions advance pos and reject reads
/// past the end.
pub type CqlReader = {
  data: Vec[UInt8];
  pos: Int;
}

/// A decoded frame header plus its raw body. `length` equals body.len().
/// The frame's total wire size is 9 + length bytes (see cql_frame_consumed).
pub type CqlFrame = {
  version: Int;
  flags: Int;
  stream: Int;
  opcode: Int;
  length: Int;
  body: Vec[UInt8];
}

/// A [value]: kind is 0 for a byte payload, 1 for null (-1) and 2 for not
/// set (-2). `data` is empty for null and not set.
pub type CqlValue = {
  kind: Int;
  data: Vec[UInt8];
}

/// A [string list]: parallel items.
pub type CqlStringList = {
  items: Vec[Str];
}

/// A [string map]: parallel keys and values, equal length.
pub type CqlStringMap = {
  keys: Vec[Str];
  values: Vec[Str];
}

/// A [string multimap] in flat form: `offsets` has keys.len() + 1 entries
/// and the values of keys[i] are values[offsets[i] .. offsets[i + 1]).
pub type CqlStringMultiMap = {
  keys: Vec[Str];
  values: Vec[Str];
  offsets: Vec[Int];
}

/// A [bytes map]: parallel keys and byte payloads, equal length.
pub type CqlBytesMap = {
  keys: Vec[Str];
  values: Vec[Vec[UInt8]];
}

/// A decoded QUERY body. `value_names[i]`, `value_kinds[i]` and
/// `values[i]` are parallel and always have `value_count` entries; the name
/// is "" when the query used positional values.
pub type CqlQuery = {
  query: Str;
  consistency: Int;
  flags: Int;
  has_values: Bool;
  value_count: Int;
  value_names: Vec[Str];
  value_kinds: Vec[Int];
  values: Vec[Vec[UInt8]];
  has_page_size: Bool;
  page_size: Int;
  has_paging_state: Bool;
  paging_state: Vec[UInt8];
  has_serial_consistency: Bool;
  serial_consistency: Int;
  has_timestamp: Bool;
  timestamp: Int;
}

/// A decoded type option: the wire code and a display rendering such as
/// "int", "list<varchar>", "map<varchar, int>", "custom(com.example.T)",
/// "tuple<int, varchar>" or "udt(ks.name)".
pub type CqlTypeInfo = {
  code: Int;
  display: Str;
}

/// Decoded ROWS (or PREPARED) metadata. The five column vectors are
/// parallel and have column_count entries when metadata is present. With
/// no_metadata set only column_count is meaningful and the vectors are
/// empty.
pub type CqlRowsMetadata = {
  flags: Int;
  column_count: Int;
  has_more_pages: Bool;
  global_tables_spec: Bool;
  no_metadata: Bool;
  has_paging_state: Bool;
  paging_state: Vec[UInt8];
  keyspaces: Vec[Str];
  tables: Vec[Str];
  names: Vec[Str];
  type_codes: Vec[Int];
  type_names: Vec[Str];
}

/// A decoded RESULT body, flat by design (v0.61.3 miscompiles struct
/// fields of struct type). Fields prefixed meta_/col_ describe the ROWS
/// result set; fields prefixed res_ describe the result metadata of a
/// PREPARED response; cells are row-major over cell_kinds/cells.
pub type CqlResult = {
  kind: Int;
  keyspace: Str;
  meta_flags: Int;
  meta_column_count: Int;
  meta_has_more_pages: Bool;
  meta_global_tables_spec: Bool;
  meta_no_metadata: Bool;
  meta_has_paging_state: Bool;
  meta_paging_state: Vec[UInt8];
  col_keyspaces: Vec[Str];
  col_tables: Vec[Str];
  col_names: Vec[Str];
  col_type_codes: Vec[Int];
  col_type_names: Vec[Str];
  rows_count: Int;
  cell_kinds: Vec[Int];
  cells: Vec[Vec[UInt8]];
  prepared_id: Vec[UInt8];
  res_flags: Int;
  res_column_count: Int;
  res_has_more_pages: Bool;
  res_global_tables_spec: Bool;
  res_no_metadata: Bool;
  res_has_paging_state: Bool;
  res_paging_state: Vec[UInt8];
  res_col_keyspaces: Vec[Str];
  res_col_tables: Vec[Str];
  res_col_names: Vec[Str];
  res_col_type_codes: Vec[Int];
  res_col_type_names: Vec[Str];
  schema_change_type: Str;
  schema_change_target: Str;
  schema_change_keyspace: Str;
  schema_change_name: Str;
  schema_change_args: Vec[Str];
}

/// A decoded ERROR body. Only the extras defined for the body's code are
/// filled in; every other extra keeps its default (0, false, "" or empty).
pub type CqlErrorBody = {
  code: Int;
  message: Str;
  consistency: Int;
  required: Int;
  alive: Int;
  received: Int;
  blockfor: Int;
  data_present: Bool;
  num_failures: Int;
  write_type: Str;
  keyspace: Str;
  table: Str;
  function: Str;
  arg_types: Vec[Str];
  prepared_id: Vec[UInt8];
}

// --------------------------------------------------
//  Private constants
// --------------------------------------------------

const _HEADER_LEN: Int = 9;          // frame header size in bytes
const _PROTO_MASK: Int = 127;        // 0x7F protocol-version bits
const _DIR_MASK: Int = 128;          // 0x80 direction bit (response)
const _FLAG_MASK: Int = 31;          // 0x1F defined v4 frame flag bits
const _INT32_FULL: Int = 4294967296; // 2^32

const _QF_VALUES: Int = 1;           // 0x01 QUERY flag: values present
const _QF_SKIP_METADATA: Int = 2;    // 0x02 QUERY flag: skip metadata
const _QF_PAGE_SIZE: Int = 4;        // 0x04 QUERY flag: page size present
const _QF_PAGING_STATE: Int = 8;     // 0x08 QUERY flag: paging state
const _QF_SERIAL: Int = 16;          // 0x10 QUERY flag: serial consistency
const _QF_TIMESTAMP: Int = 32;       // 0x20 QUERY flag: default timestamp
const _QF_NAMES: Int = 64;           // 0x40 QUERY flag: named values
const _QF_KEYSPACE: Int = 128;       // 0x80 QUERY flag: v5 keyspace

const _MF_GLOBAL: Int = 1;           // 0x0001 metadata: global tables spec
const _MF_MORE: Int = 2;             // 0x0002 metadata: has more pages
const _MF_NONE: Int = 4;             // 0x0004 metadata: no metadata

const _MAX_TYPE_DEPTH: Int = 32;     // type option nesting cap

// --------------------------------------------------
//  Codec metadata
// --------------------------------------------------

/// Native protocol version implemented by this module (4).
/// Complexity: O(1).
pub fn cql_protocol_version() -> Int {
  return 4;
}

/// The v4 request version byte (0x04).
/// Complexity: O(1).
pub fn cql_version_request_v4() -> Int {
  return 4;
}

/// The v4 response version byte (0x84).
/// Complexity: O(1).
pub fn cql_version_response_v4() -> Int {
  return 132;
}

/// The v3 request version byte (0x03); recognized on read, v4 is target.
/// Complexity: O(1).
pub fn cql_version_request_v3() -> Int {
  return 3;
}

/// The v3 response version byte (0x83); recognized on read, v4 is target.
/// Complexity: O(1).
pub fn cql_version_response_v3() -> Int {
  return 131;
}

/// The direction bit (0x80) that marks a response version byte.
/// Complexity: O(1).
pub fn cql_version_direction_mask() -> Int {
  return 128;
}

/// True when `v` is one of the four recognized version bytes (0x03, 0x83,
/// 0x04, 0x84). Complexity: O(1).
pub fn cql_version_known(v: Int) -> Bool {
  return _version_known(v);
}

/// The protocol number of a version byte (v & 0x7F): 3 or 4 for the
/// recognized bytes. Complexity: O(1).
pub fn cql_version_protocol(v: Int) -> Int {
  return v & _PROTO_MASK;
}

/// True when the version byte has the response direction bit set.
/// Complexity: O(1).
pub fn cql_version_is_response(v: Int) -> Bool {
  return (v & _DIR_MASK) != 0;
}

/// True when the version byte has the request direction bit clear.
/// Complexity: O(1).
pub fn cql_version_is_request(v: Int) -> Bool {
  return (v & _DIR_MASK) == 0;
}

/// The frame header size in bytes (9). Complexity: O(1).
pub fn cql_frame_header_len() -> Int {
  return 9;
}

/// Number of bytes one frame occupies on the wire: 9 + body length.
/// Complexity: O(1).
pub fn cql_frame_consumed(f: &CqlFrame) -> Int {
  return _HEADER_LEN + f.length;
}

/// Frame flag bit: body is compressed (0x01), not handled here.
/// Complexity: O(1).
pub fn cql_flag_compression() -> Int {
  return 1;
}

/// Frame flag bit: tracing was requested (0x02).
/// Complexity: O(1).
pub fn cql_flag_tracing() -> Int {
  return 2;
}

/// Frame flag bit: a custom payload section is present (0x04).
/// Complexity: O(1).
pub fn cql_flag_custom_payload() -> Int {
  return 4;
}

/// Frame flag bit: response carries warnings (0x08).
/// Complexity: O(1).
pub fn cql_flag_warning() -> Int {
  return 8;
}

/// Frame flag bit: use-beta was set on the request (0x10).
/// Complexity: O(1).
pub fn cql_flag_use_beta() -> Int {
  return 16;
}

/// True when every set bit of `f` is a flag the v4 spec defines (0x01..0x10).
/// Complexity: O(1).
pub fn cql_flags_known(f: Int) -> Bool {
  return (f & _FLAG_MASK) == f;
}

/// ERROR opcode (0x00). Complexity: O(1).
pub fn cql_opcode_error() -> Int {
  return 0;
}

/// STARTUP opcode (0x01). Complexity: O(1).
pub fn cql_opcode_startup() -> Int {
  return 1;
}

/// READY opcode (0x02). Complexity: O(1).
pub fn cql_opcode_ready() -> Int {
  return 2;
}

/// AUTHENTICATE opcode (0x03). Complexity: O(1).
pub fn cql_opcode_authenticate() -> Int {
  return 3;
}

/// OPTIONS opcode (0x05). Complexity: O(1).
pub fn cql_opcode_options() -> Int {
  return 5;
}

/// SUPPORTED opcode (0x06). Complexity: O(1).
pub fn cql_opcode_supported() -> Int {
  return 6;
}

/// QUERY opcode (0x07). Complexity: O(1).
pub fn cql_opcode_query() -> Int {
  return 7;
}

/// RESULT opcode (0x08). Complexity: O(1).
pub fn cql_opcode_result() -> Int {
  return 8;
}

/// PREPARE opcode (0x09). Complexity: O(1).
pub fn cql_opcode_prepare() -> Int {
  return 9;
}

/// EXECUTE opcode (0x0A). Complexity: O(1).
pub fn cql_opcode_execute() -> Int {
  return 10;
}

/// REGISTER opcode (0x0B). Complexity: O(1).
pub fn cql_opcode_register() -> Int {
  return 11;
}

/// EVENT opcode (0x0C). Complexity: O(1).
pub fn cql_opcode_event() -> Int {
  return 12;
}

/// BATCH opcode (0x0D). Complexity: O(1).
pub fn cql_opcode_batch() -> Int {
  return 13;
}

/// AUTH_CHALLENGE opcode (0x0E). Complexity: O(1).
pub fn cql_opcode_auth_challenge() -> Int {
  return 14;
}

/// AUTH_RESPONSE opcode (0x0F). Complexity: O(1).
pub fn cql_opcode_auth_response() -> Int {
  return 15;
}

/// AUTH_SUCCESS opcode (0x10). Complexity: O(1).
pub fn cql_opcode_auth_success() -> Int {
  return 16;
}

/// True when `op` is one of the sixteen v4 opcodes (0x04 is unused).
/// Complexity: O(1).
pub fn cql_opcode_known(op: Int) -> Bool {
  return _opcode_known(op);
}

/// The v4 opcode name for `op` ("ERROR" .. "AUTH_SUCCESS"), or "UNKNOWN"
/// for opcodes outside the table. Complexity: O(1).
pub fn cql_opcode_name(op: Int) -> Str {
  if op == 0 { return "ERROR"; }
  if op == 1 { return "STARTUP"; }
  if op == 2 { return "READY"; }
  if op == 3 { return "AUTHENTICATE"; }
  if op == 5 { return "OPTIONS"; }
  if op == 6 { return "SUPPORTED"; }
  if op == 7 { return "QUERY"; }
  if op == 8 { return "RESULT"; }
  if op == 9 { return "PREPARE"; }
  if op == 10 { return "EXECUTE"; }
  if op == 11 { return "REGISTER"; }
  if op == 12 { return "EVENT"; }
  if op == 13 { return "BATCH"; }
  if op == 14 { return "AUTH_CHALLENGE"; }
  if op == 15 { return "AUTH_RESPONSE"; }
  if op == 16 { return "AUTH_SUCCESS"; }
  return "UNKNOWN";
}

/// Consistency ANY (0x00). Complexity: O(1).
pub fn cql_consistency_any() -> Int {
  return 0;
}

/// Consistency ONE (0x01). Complexity: O(1).
pub fn cql_consistency_one() -> Int {
  return 1;
}

/// Consistency TWO (0x02). Complexity: O(1).
pub fn cql_consistency_two() -> Int {
  return 2;
}

/// Consistency THREE (0x03). Complexity: O(1).
pub fn cql_consistency_three() -> Int {
  return 3;
}

/// Consistency QUORUM (0x04). Complexity: O(1).
pub fn cql_consistency_quorum() -> Int {
  return 4;
}

/// Consistency ALL (0x05). Complexity: O(1).
pub fn cql_consistency_all() -> Int {
  return 5;
}

/// Consistency LOCAL_QUORUM (0x06). Complexity: O(1).
pub fn cql_consistency_local_quorum() -> Int {
  return 6;
}

/// Consistency EACH_QUORUM (0x07). Complexity: O(1).
pub fn cql_consistency_each_quorum() -> Int {
  return 7;
}

/// Consistency SERIAL (0x08). Complexity: O(1).
pub fn cql_consistency_serial() -> Int {
  return 8;
}

/// Consistency LOCAL_SERIAL (0x09). Complexity: O(1).
pub fn cql_consistency_local_serial() -> Int {
  return 9;
}

/// Consistency LOCAL_ONE (0x0A). Complexity: O(1).
pub fn cql_consistency_local_one() -> Int {
  return 10;
}

/// True when `c` is a consistency value the v4 table defines (0x00..0x0A).
/// Complexity: O(1).
pub fn cql_consistency_known(c: Int) -> Bool {
  return c >= 0 && c <= 10;
}

/// The consistency name for `c` ("ANY" .. "LOCAL_ONE"), or "UNKNOWN".
/// Complexity: O(1).
pub fn cql_consistency_name(c: Int) -> Str {
  if c == 0 { return "ANY"; }
  if c == 1 { return "ONE"; }
  if c == 2 { return "TWO"; }
  if c == 3 { return "THREE"; }
  if c == 4 { return "QUORUM"; }
  if c == 5 { return "ALL"; }
  if c == 6 { return "LOCAL_QUORUM"; }
  if c == 7 { return "EACH_QUORUM"; }
  if c == 8 { return "SERIAL"; }
  if c == 9 { return "LOCAL_SERIAL"; }
  if c == 10 { return "LOCAL_ONE"; }
  return "UNKNOWN";
}

/// QUERY flag VALUES (0x01): a values section follows. Complexity: O(1).
pub fn cql_query_flag_values() -> Int {
  return 1;
}

/// QUERY flag SKIP_METADATA (0x02). Complexity: O(1).
pub fn cql_query_flag_skip_metadata() -> Int {
  return 2;
}

/// QUERY flag PAGE_SIZE (0x04): a page size follows. Complexity: O(1).
pub fn cql_query_flag_page_size() -> Int {
  return 4;
}

/// QUERY flag WITH_PAGING_STATE (0x08): a paging state follows.
/// Complexity: O(1).
pub fn cql_query_flag_paging_state() -> Int {
  return 8;
}

/// QUERY flag WITH_SERIAL_CONSISTENCY (0x10): a consistency follows.
/// Complexity: O(1).
pub fn cql_query_flag_serial_consistency() -> Int {
  return 16;
}

/// QUERY flag WITH_DEFAULT_TIMESTAMP (0x20): a timestamp follows.
/// Complexity: O(1).
pub fn cql_query_flag_default_timestamp() -> Int {
  return 32;
}

/// QUERY flag WITH_NAMES_FOR_VALUES (0x40): values carry names.
/// Complexity: O(1).
pub fn cql_query_flag_names_for_values() -> Int {
  return 64;
}

/// QUERY flag KEYSPACE (0x80): v5 only, not interpreted by the v4 reader.
/// Complexity: O(1).
pub fn cql_query_flag_keyspace() -> Int {
  return 128;
}

/// True when every set bit of `f` is a QUERY flag defined for v4
/// (0x01..0x40; the v5 keyspace bit 0x80 is reported as unknown).
/// Complexity: O(1).
pub fn cql_query_flags_known(f: Int) -> Bool {
  return (f & 127) == f;
}

/// RESULT kind VOID (0x01). Complexity: O(1).
pub fn cql_result_void() -> Int {
  return 1;
}

/// RESULT kind ROWS (0x02). Complexity: O(1).
pub fn cql_result_rows() -> Int {
  return 2;
}

/// RESULT kind SET_KEYSPACE (0x03). Complexity: O(1).
pub fn cql_result_set_keyspace() -> Int {
  return 3;
}

/// RESULT kind PREPARED (0x04). Complexity: O(1).
pub fn cql_result_prepared() -> Int {
  return 4;
}

/// RESULT kind SCHEMA_CHANGE (0x05). Complexity: O(1).
pub fn cql_result_schema_change() -> Int {
  return 5;
}

/// True when `k` is a RESULT kind the v4 table defines (0x01..0x05).
/// Complexity: O(1).
pub fn cql_result_kind_known(k: Int) -> Bool {
  return _result_kind_known(k);
}

/// Metadata flag GLOBAL_TABLES_SPEC (0x0001). Complexity: O(1).
pub fn cql_meta_flag_global_tables_spec() -> Int {
  return 1;
}

/// Metadata flag HAS_MORE_PAGES (0x0002). Complexity: O(1).
pub fn cql_meta_flag_has_more_pages() -> Int {
  return 2;
}

/// Metadata flag NO_METADATA (0x0004). Complexity: O(1).
pub fn cql_meta_flag_no_metadata() -> Int {
  return 4;
}

/// True when every set bit of `f` is a metadata flag the v4 spec defines.
/// Complexity: O(1).
pub fn cql_meta_flags_known(f: Int) -> Bool {
  return f >= 0 && (f & 7) == f;
}

/// Value kind: the [value] carries bytes. Complexity: O(1).
pub fn cql_value_kind_bytes() -> Int {
  return 0;
}

/// Value kind: the [value] is null (-1). Complexity: O(1).
pub fn cql_value_kind_null() -> Int {
  return 1;
}

/// Value kind: the [value] is not set (-2). Complexity: O(1).
pub fn cql_value_kind_not_set() -> Int {
  return 2;
}

/// Type option code for custom types (0x0000). Complexity: O(1).
pub fn cql_type_custom() -> Int {
  return 0;
}

/// Type option code for ascii (0x0001). Complexity: O(1).
pub fn cql_type_ascii() -> Int {
  return 1;
}

/// Type option code for bigint (0x0002). Complexity: O(1).
pub fn cql_type_bigint() -> Int {
  return 2;
}

/// Type option code for blob (0x0003). Complexity: O(1).
pub fn cql_type_blob() -> Int {
  return 3;
}

/// Type option code for boolean (0x0004). Complexity: O(1).
pub fn cql_type_boolean() -> Int {
  return 4;
}

/// Type option code for counter (0x0005). Complexity: O(1).
pub fn cql_type_counter() -> Int {
  return 5;
}

/// Type option code for decimal (0x0006). Complexity: O(1).
pub fn cql_type_decimal() -> Int {
  return 6;
}

/// Type option code for double (0x0007). Complexity: O(1).
pub fn cql_type_double() -> Int {
  return 7;
}

/// Type option code for float (0x0008). Complexity: O(1).
pub fn cql_type_float() -> Int {
  return 8;
}

/// Type option code for int (0x0009). Complexity: O(1).
pub fn cql_type_int() -> Int {
  return 9;
}

/// Type option code for timestamp (0x000A). Complexity: O(1).
pub fn cql_type_timestamp() -> Int {
  return 10;
}

/// Type option code for uuid (0x000B). Complexity: O(1).
pub fn cql_type_uuid() -> Int {
  return 11;
}

/// Type option code for varchar (0x000C), the wire name of "text".
/// Complexity: O(1).
pub fn cql_type_varchar() -> Int {
  return 12;
}

/// Type option code for varint (0x000D). Complexity: O(1).
pub fn cql_type_varint() -> Int {
  return 13;
}

/// Type option code for timeuuid (0x000E). Complexity: O(1).
pub fn cql_type_timeuuid() -> Int {
  return 14;
}

/// Type option code for inet (0x000F). Complexity: O(1).
pub fn cql_type_inet() -> Int {
  return 15;
}

/// Type option code for date (0x0010). Complexity: O(1).
pub fn cql_type_date() -> Int {
  return 16;
}

/// Type option code for time (0x0011). Complexity: O(1).
pub fn cql_type_time() -> Int {
  return 17;
}

/// Type option code for smallint (0x0012). Complexity: O(1).
pub fn cql_type_smallint() -> Int {
  return 18;
}

/// Type option code for tinyint (0x0013). Complexity: O(1).
pub fn cql_type_tinyint() -> Int {
  return 19;
}

/// Type option code for duration (0x0014). Complexity: O(1).
pub fn cql_type_duration() -> Int {
  return 20;
}

/// Type option code for list (0x0020). Complexity: O(1).
pub fn cql_type_list() -> Int {
  return 32;
}

/// Type option code for map (0x0021). Complexity: O(1).
pub fn cql_type_map() -> Int {
  return 33;
}

/// Type option code for set (0x0022). Complexity: O(1).
pub fn cql_type_set() -> Int {
  return 34;
}

/// Type option code for UDT (0x0030). Complexity: O(1).
pub fn cql_type_udt() -> Int {
  return 48;
}

/// Type option code for tuple (0x0031). Complexity: O(1).
pub fn cql_type_tuple() -> Int {
  return 49;
}

/// The canonical name for a simple (non-collection, non-custom) type option
/// code, or "UNKNOWN". Complexity: O(1).
pub fn cql_type_simple_name(code: Int) -> Str {
  if code == 1 { return "ascii"; }
  if code == 2 { return "bigint"; }
  if code == 3 { return "blob"; }
  if code == 4 { return "boolean"; }
  if code == 5 { return "counter"; }
  if code == 6 { return "decimal"; }
  if code == 7 { return "double"; }
  if code == 8 { return "float"; }
  if code == 9 { return "int"; }
  if code == 10 { return "timestamp"; }
  if code == 11 { return "uuid"; }
  if code == 12 { return "varchar"; }
  if code == 13 { return "varint"; }
  if code == 14 { return "timeuuid"; }
  if code == 15 { return "inet"; }
  if code == 16 { return "date"; }
  if code == 17 { return "time"; }
  if code == 18 { return "smallint"; }
  if code == 19 { return "tinyint"; }
  if code == 20 { return "duration"; }
  return "UNKNOWN";
}

/// True when `code` is a simple type option code (0x0001..0x0014).
/// Complexity: O(1).
pub fn cql_type_simple_known(code: Int) -> Bool {
  return code >= 1 && code <= 20;
}

/// ERROR code SERVER_ERROR (0x0000). Complexity: O(1).
pub fn cql_error_code_server_error() -> Int {
  return 0;
}

/// ERROR code PROTOCOL_ERROR (0x000A). Complexity: O(1).
pub fn cql_error_code_protocol_error() -> Int {
  return 10;
}

/// ERROR code BAD_CREDENTIALS (0x0100). Complexity: O(1).
pub fn cql_error_code_bad_credentials() -> Int {
  return 256;
}

/// ERROR code UNAVAILABLE (0x1000). Complexity: O(1).
pub fn cql_error_code_unavailable() -> Int {
  return 4096;
}

/// ERROR code OVERLOADED (0x1001). Complexity: O(1).
pub fn cql_error_code_overloaded() -> Int {
  return 4097;
}

/// ERROR code IS_BOOTSTRAPPING (0x1002). Complexity: O(1).
pub fn cql_error_code_is_bootstrapping() -> Int {
  return 4098;
}

/// ERROR code TRUNCATE_ERROR (0x1003). Complexity: O(1).
pub fn cql_error_code_truncate_error() -> Int {
  return 4099;
}

/// ERROR code WRITE_TIMEOUT (0x1100). Complexity: O(1).
pub fn cql_error_code_write_timeout() -> Int {
  return 4352;
}

/// ERROR code READ_TIMEOUT (0x1200). Complexity: O(1).
pub fn cql_error_code_read_timeout() -> Int {
  return 4608;
}

/// ERROR code READ_FAILURE (0x1300). Complexity: O(1).
pub fn cql_error_code_read_failure() -> Int {
  return 4864;
}

/// ERROR code FUNCTION_FAILURE (0x1400). Complexity: O(1).
pub fn cql_error_code_function_failure() -> Int {
  return 5120;
}

/// ERROR code WRITE_FAILURE (0x1500). Complexity: O(1).
pub fn cql_error_code_write_failure() -> Int {
  return 5376;
}

/// ERROR code SYNTAX_ERROR (0x2000). Complexity: O(1).
pub fn cql_error_code_syntax_error() -> Int {
  return 8192;
}

/// ERROR code UNAUTHORIZED (0x2100). Complexity: O(1).
pub fn cql_error_code_unauthorized() -> Int {
  return 8448;
}

/// ERROR code INVALID (0x2200). Complexity: O(1).
pub fn cql_error_code_invalid() -> Int {
  return 8704;
}

/// ERROR code CONFIG_ERROR (0x2300). Complexity: O(1).
pub fn cql_error_code_config_error() -> Int {
  return 8960;
}

/// ERROR code ALREADY_EXISTS (0x2400). Complexity: O(1).
pub fn cql_error_code_already_exists() -> Int {
  return 9216;
}

/// ERROR code UNPREPARED (0x2500). Complexity: O(1).
pub fn cql_error_code_unprepared() -> Int {
  return 9472;
}

/// True when `code` is one of the eighteen ERROR codes of the v4 table.
/// Complexity: O(1).
pub fn cql_error_code_known(code: Int) -> Bool {
  return _error_code_known(code);
}

/// The ERROR code name for `code` ("SERVER_ERROR" .. "UNPREPARED"), or
/// "UNKNOWN" for codes outside the table. Complexity: O(1).
pub fn cql_error_code_name(code: Int) -> Str {
  if code == 0 { return "SERVER_ERROR"; }
  if code == 10 { return "PROTOCOL_ERROR"; }
  if code == 256 { return "BAD_CREDENTIALS"; }
  if code == 4096 { return "UNAVAILABLE"; }
  if code == 4097 { return "OVERLOADED"; }
  if code == 4098 { return "IS_BOOTSTRAPPING"; }
  if code == 4099 { return "TRUNCATE_ERROR"; }
  if code == 4352 { return "WRITE_TIMEOUT"; }
  if code == 4608 { return "READ_TIMEOUT"; }
  if code == 4864 { return "READ_FAILURE"; }
  if code == 5120 { return "FUNCTION_FAILURE"; }
  if code == 5376 { return "WRITE_FAILURE"; }
  if code == 8192 { return "SYNTAX_ERROR"; }
  if code == 8448 { return "UNAUTHORIZED"; }
  if code == 8704 { return "INVALID"; }
  if code == 8960 { return "CONFIG_ERROR"; }
  if code == 9216 { return "ALREADY_EXISTS"; }
  if code == 9472 { return "UNPREPARED"; }
  return "UNKNOWN";
}

// --------------------------------------------------
//  Private predicates and byte helpers
// --------------------------------------------------

// True for the four recognized version bytes.
fn _version_known(v: Int) -> Bool {
  if v == 3 || v == 131 {
    return true;
  }
  return v == 4 || v == 132;
}

// True for the sixteen v4 opcodes (0x04 is unused).
fn _opcode_known(op: Int) -> Bool {
  if op == 0 || op == 1 || op == 2 || op == 3 {
    return true;
  }
  if op == 5 || op == 6 || op == 7 || op == 8 {
    return true;
  }
  if op == 9 || op == 10 || op == 11 || op == 12 {
    return true;
  }
  return op == 13 || op == 14 || op == 15 || op == 16;
}

// True for RESULT kinds VOID..SCHEMA_CHANGE.
fn _result_kind_known(k: Int) -> Bool {
  return k >= 1 && k <= 5;
}

// True for the eighteen ERROR codes of the v4 table.
fn _error_code_known(code: Int) -> Bool {
  if code == 0 || code == 10 || code == 256 {
    return true;
  }
  if code == 4096 || code == 4097 || code == 4098 || code == 4099 {
    return true;
  }
  if code == 4352 || code == 4608 || code == 4864 {
    return true;
  }
  if code == 5120 || code == 5376 {
    return true;
  }
  if code == 8192 || code == 8448 || code == 8704 {
    return true;
  }
  return code == 9216 || code == 9472;
}

// 2^k for 0 <= k <= 32 (the largest value is 2^32).
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Sign-extend the unsigned value `v` (0 <= v < 2^bits) to a signed Int.
// bits is 8, 16 or 32.
fn _sign_extend(v: Int, bits: Int) -> Int {
  let half = _pow2(bits - 1);
  if v >= half {
    let full = _pow2(bits);
    return v - full;
  }
  return v;
}

// Byte `shift_bytes` of `v` in big-endian order (0 = least significant
// byte), as the exact two's-complement bit pattern. Arithmetic only.
fn _be_byte(v: Int, shift_bytes: Int) -> UInt8 {
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
fn _w_push_byte(w: &mut CqlWriter, b: Int) {
  var q = b % 256;
  if q < 0 { q = q + 256; }
  w.data.push(q as UInt8);
}

// Append the low `size` bytes of `v` in big-endian order (size 1..8).
fn _w_push_be(w: &mut CqlWriter, v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    w.data.push(_be_byte(v, i));
    i = i - 1;
  }
}

// Append every UTF-8 byte of `s`.
fn _w_push_str(w: &mut CqlWriter, s: Str) {
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    w.data.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Append every byte of `v`.
fn _w_push_bytes(w: &mut CqlWriter, v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    w.data.push(v[i]);
    i = i + 1;
  }
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

// Byte at `pos` widened to 0..255. The caller guarantees the index is in
// bounds.
fn _r_byte(r: &CqlReader, pos: Int) -> Int {
  return (r.data[pos] as Int) & 0xFF;
}

// Same as _r_byte but takes &mut, so reader bodies never mix a `&` call
// before a `&mut` access on the same local (advisory E001).
fn _r_byte_mut(r: &mut CqlReader, pos: Int) -> Int {
  return _r_byte(r, pos);
}

// Read `size` (1..4) bytes big-endian into an unsigned Int, advancing the
// cursor. Err(truncation with the starting offset) when fewer bytes remain.
fn _read_unsigned(r: &mut CqlReader, size: Int) -> Result[Int, Str] {
  let total: Int = r.data.len();
  if r.pos + size > total {
    return _err_int(_trunc_at(r.pos));
  }
  var v: Int = 0;
  var i = 0;
  while i < size {
    let b: Int = _r_byte_mut(r, r.pos + i);
    v = v * 256 + b;
    i = i + 1;
  }
  r.pos = r.pos + size;
  return _ok_int(v);
}

// Read 8 bytes big-endian as the exact 64-bit two's-complement pattern. The
// low 63 bits are accumulated (never overflowing) and the top bit is applied
// as a sign afterwards, so every Int64 pattern round-trips.
fn _read64(r: &mut CqlReader) -> Result[Int, Str] {
  let total: Int = r.data.len();
  if r.pos + 8 > total {
    return _err_int(_trunc_at(r.pos));
  }
  let b0: Int = _r_byte_mut(r, r.pos);
  let neg = b0 >= 128;
  var v: Int = b0 % 128;
  var i = 1;
  while i < 8 {
    let b: Int = _r_byte_mut(r, r.pos + i);
    v = v * 256 + b;
    i = i + 1;
  }
  r.pos = r.pos + 8;
  if neg {
    v = v - 9223372036854775807 - 1;
  }
  return _ok_int(v);
}

// Read an unsigned 16-bit big-endian integer.
fn _read_u16(r: &mut CqlReader) -> Result[Int, Str] {
  return _read_unsigned(r, 2);
}

// Peek an unsigned 16-bit big-endian integer at `pos` without advancing.
fn _peek_u16(r: &CqlReader, pos: Int) -> Result[Int, Str] {
  let total: Int = r.data.len();
  if pos + 2 > total {
    return _err_int(_trunc_at(pos));
  }
  let b0: Int = _r_byte(r, pos);
  let b1: Int = _r_byte(r, pos + 1);
  return _ok_int(b0 * 256 + b1);
}

// Read a signed 16-bit big-endian integer.
fn _read_i16(r: &mut CqlReader) -> Result[Int, Str] {
  let ur = _read_u16(r);
  if !ur.is_ok {
    return _err_int(ur.error);
  }
  let v: Int = ur.value;
  return _ok_int(_sign_extend(v, 16));
}

// Read a signed 32-bit big-endian integer.
fn _read_i32(r: &mut CqlReader) -> Result[Int, Str] {
  let ur = _read_unsigned(r, 4);
  if !ur.is_ok {
    return _err_int(ur.error);
  }
  let v: Int = ur.value;
  return _ok_int(_sign_extend(v, 32));
}

// Read exactly `n` bytes into a fresh vector, advancing the cursor.
// Err(bad length) for n < 0 and Err(truncation) when `n` bytes are not
// available.
fn _read_n(r: &mut CqlReader, n: Int) -> Result[Vec[UInt8], Str] {
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

// --------------------------------------------------
//  Error message helpers
// --------------------------------------------------

// "cassandra: truncated input at offset N".
fn _trunc_at(off: Int) -> Str {
  return "cassandra: truncated input at offset " + convert.int_to_string(off);
}

// "cassandra: bad length N at offset M".
fn _bad_len_msg(n: Int, off: Int) -> Str {
  return "cassandra: bad length " + convert.int_to_string(n) + " at offset " + convert.int_to_string(off);
}

// "cassandra: bad <what> N at offset M".
fn _bad_num_msg(what: Str, n: Int, off: Int) -> Str {
  return "cassandra: bad " + what + " " + convert.int_to_string(n) + " at offset " + convert.int_to_string(off);
}

// "cassandra: oversized collection at offset N".
fn _oversized_msg(off: Int) -> Str {
  return "cassandra: oversized collection at offset " + convert.int_to_string(off);
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
      return "cassandra: string contains nul";
    }
    if b < 128 {
      i = i + 1;
    } elif b < 194 {
      return "cassandra: invalid utf-8";
    } elif b < 224 {
      if i + 1 >= n {
        return "cassandra: invalid utf-8";
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return "cassandra: invalid utf-8";
      }
      i = i + 2;
    } elif b < 240 {
      if i + 2 >= n {
        return "cassandra: invalid utf-8";
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      let c2: Int = (bytes[i + 2] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return "cassandra: invalid utf-8";
      }
      if c2 < 128 || c2 >= 192 {
        return "cassandra: invalid utf-8";
      }
      if b == 224 && c1 < 160 {
        return "cassandra: invalid utf-8";
      }
      if b == 237 && c1 >= 160 {
        return "cassandra: invalid utf-8";
      }
      i = i + 3;
    } else {
      if b >= 245 {
        return "cassandra: invalid utf-8";
      }
      if i + 3 >= n {
        return "cassandra: invalid utf-8";
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      let c2: Int = (bytes[i + 2] as Int) & 0xFF;
      let c3: Int = (bytes[i + 3] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return "cassandra: invalid utf-8";
      }
      if c2 < 128 || c2 >= 192 {
        return "cassandra: invalid utf-8";
      }
      if c3 < 128 || c3 >= 192 {
        return "cassandra: invalid utf-8";
      }
      if b == 240 && c1 < 144 {
        return "cassandra: invalid utf-8";
      }
      if b == 244 && c1 >= 144 {
        return "cassandra: invalid utf-8";
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
pub fn cql_writer_new() -> CqlWriter {
  return CqlWriter{ data: Vec[UInt8].new() };
}

/// Number of bytes written so far. Complexity: O(1).
pub fn cql_writer_len(w: &CqlWriter) -> Int {
  return w.data.len();
}

/// A copy of the bytes written so far. Complexity: O(written bytes).
pub fn cql_writer_bytes(w: &CqlWriter) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < w.data.len() {
    out.push(w.data[i]);
    i = i + 1;
  }
  return out;
}

/// A reader positioned at offset 0 of `data`. Complexity: O(1).
pub fn cql_reader_new(data: Vec[UInt8]) -> CqlReader {
  return CqlReader{ data: data; pos: 0; };
}

/// Current cursor offset. Complexity: O(1).
pub fn cql_reader_pos(r: &CqlReader) -> Int {
  return r.pos;
}

/// Current cursor offset, taking &mut so a caller that also mutates the
/// reader never mixes a `&` accessor before a `&mut` call on the same
/// local (advisory E001). Complexity: O(1).
pub fn cql_reader_pos_mut(r: &mut CqlReader) -> Int {
  return r.pos;
}

/// Bytes left before the end of the buffer. Complexity: O(1).
pub fn cql_reader_remaining(r: &CqlReader) -> Int {
  return r.data.len() - r.pos;
}

// --------------------------------------------------
//  Primitives
// --------------------------------------------------

/// Read one [int] (signed 32-bit big-endian).
/// Err(truncation) when fewer than 4 bytes remain. Complexity: O(1).
pub fn cql_read_int(r: &mut CqlReader) -> Result[Int, Str] {
  return _read_i32(r);
}

/// Read one [long] (signed 64-bit big-endian).
/// Err(truncation) when fewer than 8 bytes remain. Complexity: O(1).
pub fn cql_read_long(r: &mut CqlReader) -> Result[Int, Str] {
  return _read64(r);
}

/// Read one [byte] as an unsigned value 0..255. The v4 spec defines [byte]
/// as a single byte whose signedness does not matter (it carries flags and
/// opcodes, never arithmetic); the raw byte is returned. Err(truncation)
/// when empty. Complexity: O(1).
pub fn cql_read_byte(r: &mut CqlReader) -> Result[Int, Str] {
  return _read_unsigned(r, 1);
}

/// Read one [short] (unsigned 16-bit big-endian, 0..65535).
/// Err(truncation) when fewer than 2 bytes remain. Complexity: O(1).
pub fn cql_read_short(r: &mut CqlReader) -> Result[Int, Str] {
  return _read_u16(r);
}

/// Read one [string]: a u16 byte length then that many UTF-8 bytes. The
/// payload must be valid UTF-8 and contain no NUL byte. Complexity:
/// O(payload).
pub fn cql_read_string(r: &mut CqlReader) -> Result[Str, Str] {
  let lr = _read_u16(r);
  if !lr.is_ok {
    return _err_str(lr.error);
  }
  let n: Int = lr.value;
  let br = _read_n(r, n);
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

/// Read one [long string]: an i32 byte length then that many UTF-8 bytes.
/// Negative lengths are rejected. Complexity: O(payload).
pub fn cql_read_long_string(r: &mut CqlReader) -> Result[Str, Str] {
  let lstart: Int = r.pos;
  let lr = _read_i32(r);
  if !lr.is_ok {
    return _err_str(lr.error);
  }
  let n: Int = lr.value;
  if n < 0 {
    return _err_str(_bad_len_msg(n, lstart));
  }
  let br = _read_n(r, n);
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

/// Read one [bytes]: an i32 byte length then that many raw bytes. A null
/// (-1) is rejected with Err("cassandra: null bytes value at offset N") and
/// any other negative length with Err(bad length); use cql_read_value where
/// null must be represented. Complexity: O(payload).
pub fn cql_read_bytes(r: &mut CqlReader) -> Result[Vec[UInt8], Str] {
  let lstart: Int = r.pos;
  let lr = _read_i32(r);
  if !lr.is_ok {
    return _err_bytes(lr.error);
  }
  let n: Int = lr.value;
  if n == -1 {
    return _err_bytes("cassandra: null bytes value at offset " + convert.int_to_string(lstart));
  }
  if n < 0 {
    return _err_bytes(_bad_len_msg(n, lstart));
  }
  return _read_n(r, n);
}

/// Read one [value]: an i32 length then that many bytes, where -1 is null
/// and -2 is not set. The returned CqlValue records which of the three forms
/// was on the wire; any length below -2 is rejected as a bad length.
/// Complexity: O(payload).
pub fn cql_read_value(r: &mut CqlReader) -> Result[CqlValue, Str] {
  let lstart: Int = r.pos;
  let lr = _read_i32(r);
  if !lr.is_ok {
    return _err_value(lr.error);
  }
  let n: Int = lr.value;
  if n == -1 {
    return _ok_value(CqlValue{ kind: 1; data: Vec[UInt8].new() });
  }
  if n == -2 {
    return _ok_value(CqlValue{ kind: 2; data: Vec[UInt8].new() });
  }
  if n < 0 {
    return _err_value(_bad_len_msg(n, lstart));
  }
  let br = _read_n(r, n);
  if !br.is_ok {
    return _err_value(br.error);
  }
  let payload: Vec[UInt8] = br.value;
  return _ok_value(CqlValue{ kind: 0; data: payload });
}

/// Read one [short bytes]: a u16 byte length then that many raw bytes.
/// Complexity: O(payload).
pub fn cql_read_short_bytes(r: &mut CqlReader) -> Result[Vec[UInt8], Str] {
  let lr = _read_u16(r);
  if !lr.is_ok {
    return _err_bytes(lr.error);
  }
  let n: Int = lr.value;
  return _read_n(r, n);
}

/// Read one [string list]: a u16 count then that many [string]s. The count
/// is rejected when it cannot fit in the remaining bytes (2 per element).
/// Complexity: O(payload).
pub fn cql_read_string_list(r: &mut CqlReader) -> Result[CqlStringList, Str] {
  let start: Int = r.pos;
  let nr = _read_u16(r);
  if !nr.is_ok {
    return _err_strlist(nr.error);
  }
  let n: Int = nr.value;
  let remaining: Int = r.data.len() - r.pos;
  if n > remaining / 2 {
    return _err_strlist(_oversized_msg(start));
  }
  var items = Vec[Str].new();
  var i = 0;
  while i < n {
    let sr = cql_read_string(r);
    if !sr.is_ok {
      return _err_strlist(sr.error);
    }
    let s: Str = sr.value;
    items.push(s);
    i = i + 1;
  }
  return _ok_strlist(CqlStringList{ items: items });
}

/// Read one [string map]: a u16 count then that many [string] key/value
/// pairs. The count is rejected when it cannot fit in the remaining bytes
/// (4 per pair). Complexity: O(payload).
pub fn cql_read_string_map(r: &mut CqlReader) -> Result[CqlStringMap, Str] {
  let start: Int = r.pos;
  let nr = _read_u16(r);
  if !nr.is_ok {
    return _err_strmap(nr.error);
  }
  let n: Int = nr.value;
  let remaining: Int = r.data.len() - r.pos;
  if n > remaining / 4 {
    return _err_strmap(_oversized_msg(start));
  }
  var keys = Vec[Str].new();
  var vals = Vec[Str].new();
  var i = 0;
  while i < n {
    let kr = cql_read_string(r);
    if !kr.is_ok {
      return _err_strmap(kr.error);
    }
    let k: Str = kr.value;
    let vr = cql_read_string(r);
    if !vr.is_ok {
      return _err_strmap(vr.error);
    }
    let v: Str = vr.value;
    keys.push(k);
    vals.push(v);
    i = i + 1;
  }
  return _ok_strmap(CqlStringMap{ keys: keys; values: vals; });
}

/// Read one [string multimap] into the flat keys/values/offsets form: a u16
/// count of keys, then for each key a [string] and a [string list]. The
/// count is rejected when it cannot fit in the remaining bytes (4 per key).
/// Complexity: O(payload).
pub fn cql_read_string_multimap(r: &mut CqlReader) -> Result[CqlStringMultiMap, Str] {
  let start: Int = r.pos;
  let nr = _read_u16(r);
  if !nr.is_ok {
    return _err_multimap(nr.error);
  }
  let n: Int = nr.value;
  let remaining: Int = r.data.len() - r.pos;
  if n > remaining / 4 {
    return _err_multimap(_oversized_msg(start));
  }
  var keys = Vec[Str].new();
  var vals = Vec[Str].new();
  var offsets = Vec[Int].new();
  offsets.push(0);
  var i = 0;
  while i < n {
    let kr = cql_read_string(r);
    if !kr.is_ok {
      return _err_multimap(kr.error);
    }
    let k: Str = kr.value;
    let lr = cql_read_string_list(r);
    if !lr.is_ok {
      return _err_multimap(lr.error);
    }
    let lst: CqlStringList = lr.value;
    keys.push(k);
    var j = 0;
    while j < lst.items.len() {
      let s: Str = lst.items[j];
      vals.push(s);
      j = j + 1;
    }
    offsets.push(vals.len());
    i = i + 1;
  }
  return _ok_multimap(CqlStringMultiMap{ keys: keys; values: vals; offsets: offsets; });
}

/// Read one [bytes map]: a u16 count then that many [string] key / [bytes]
/// value pairs. Null [bytes] values are rejected (see cql_read_bytes). The
/// count is rejected when it cannot fit in the remaining bytes (6 per pair).
/// Complexity: O(payload).
pub fn cql_read_bytes_map(r: &mut CqlReader) -> Result[CqlBytesMap, Str> {
  let start: Int = r.pos;
  let nr = _read_u16(r);
  if !nr.is_ok {
    return _err_bytesmap(nr.error);
  }
  let n: Int = nr.value;
  let remaining: Int = r.data.len() - r.pos;
  if n > remaining / 6 {
    return _err_bytesmap(_oversized_msg(start));
  }
  var keys = Vec[Str].new();
  var vals = Vec[Vec[UInt8]].new();
  var i = 0;
  while i < n {
    let kr = cql_read_string(r);
    if !kr.is_ok {
      return _err_bytesmap(kr.error);
    }
    let k: Str = kr.value;
    let vr = cql_read_bytes(r);
    if !vr.is_ok {
      return _err_bytesmap(vr.error);
    }
    let v: Vec[UInt8] = vr.value;
    keys.push(k);
    vals.push(v);
    i = i + 1;
  }
  return _ok_bytesmap(CqlBytesMap{ keys: keys; values: vals; });
}

/// Write one [int]. Complexity: O(1).
pub fn cql_write_int(w: &mut CqlWriter, v: Int) {
  _w_push_be(w, v, 4);
}

/// Write one [long]. Complexity: O(1).
pub fn cql_write_long(w: &mut CqlWriter, v: Int) {
  _w_push_be(w, v, 8);
}

/// Write one [byte] (low 8 bits). Complexity: O(1).
pub fn cql_write_byte(w: &mut CqlWriter, v: Int) {
  _w_push_byte(w, v);
}

/// Write one [short] (low 16 bits). Complexity: O(1).
pub fn cql_write_short(w: &mut CqlWriter, v: Int) {
  _w_push_be(w, v & 65535, 2);
}

/// Write one [string]: a u16 byte length then the UTF-8 bytes. The caller
/// must keep the byte length <= 65535 (use cql_write_long_string above it).
/// Complexity: O(byte length).
pub fn cql_write_string(w: &mut CqlWriter, s: Str) {
  _w_push_be(w, string.str_len(s), 2);
  _w_push_str(w, s);
}

/// Write one [long string]: an i32 byte length then the UTF-8 bytes.
/// Complexity: O(byte length).
pub fn cql_write_long_string(w: &mut CqlWriter, s: Str) {
  _w_push_be(w, string.str_len(s), 4);
  _w_push_str(w, s);
}

/// Write one [bytes]: an i32 byte length then the bytes. Complexity:
/// O(payload).
pub fn cql_write_bytes(w: &mut CqlWriter, data: &Vec[UInt8]) {
  _w_push_be(w, data.len(), 4);
  _w_push_bytes(w, data);
}

/// Write one [value]: -1 for kind 1 (null), -2 for kind 2 (not set), and a
/// length-prefixed payload otherwise. Complexity: O(payload).
pub fn cql_write_value(w: &mut CqlWriter, kind: Int, data: &Vec[UInt8]) {
  if kind == 1 {
    _w_push_be(w, -1, 4);
    return;
  }
  if kind == 2 {
    _w_push_be(w, -2, 4);
    return;
  }
  _w_push_be(w, data.len(), 4);
  _w_push_bytes(w, data);
}

/// Write one [short bytes]: a u16 length then the bytes. The caller must
/// keep the length <= 65535. Complexity: O(payload).
pub fn cql_write_short_bytes(w: &mut CqlWriter, data: &Vec[UInt8]) {
  _w_push_be(w, data.len() & 65535, 2);
  _w_push_bytes(w, data);
}

/// Write one [string list]. The caller must keep the item count <= 65535.
/// Complexity: O(payload).
pub fn cql_write_string_list(w: &mut CqlWriter, list: &CqlStringList) {
  _w_push_be(w, list.items.len() & 65535, 2);
  var i = 0;
  while i < list.items.len() {
    let s: Str = list.items[i];
    cql_write_string(w, s);
    i = i + 1;
  }
}

/// Write one [string map]. The caller must keep the pair count <= 65535.
/// Complexity: O(payload).
pub fn cql_write_string_map(w: &mut CqlWriter, m: &CqlStringMap) {
  _w_push_be(w, m.keys.len() & 65535, 2);
  var i = 0;
  while i < m.keys.len() {
    let k: Str = m.keys[i];
    let v: Str = m.values[i];
    cql_write_string(w, k);
    cql_write_string(w, v);
    i = i + 1;
  }
}

/// Write one [string multimap] from the flat keys/values/offsets form. The
/// caller must keep the key count <= 65535 and offsets well formed.
/// Complexity: O(payload).
pub fn cql_write_string_multimap(w: &mut CqlWriter, m: &CqlStringMultiMap) {
  _w_push_be(w, m.keys.len() & 65535, 2);
  var i = 0;
  while i < m.keys.len() {
    let k: Str = m.keys[i];
    cql_write_string(w, k);
    let lo: Int = m.offsets[i];
    let hi: Int = m.offsets[i + 1];
    _w_push_be(w, (hi - lo) & 65535, 2);
    var j = lo;
    while j < hi {
      let s: Str = m.values[j];
      cql_write_string(w, s);
      j = j + 1;
    }
    i = i + 1;
  }
}

/// Write one [bytes map]. The caller must keep the pair count <= 65535.
/// Complexity: O(payload).
pub fn cql_write_bytes_map(w: &mut CqlWriter, m: &CqlBytesMap) {
  _w_push_be(w, m.keys.len() & 65535, 2);
  var i = 0;
  while i < m.keys.len() {
    let k: Str = m.keys[i];
    let v: Vec[UInt8] = m.values[i];
    cql_write_string(w, k);
    cql_write_bytes(w, &v);
    i = i + 1;
  }
}

// --------------------------------------------------
//  Primitive accessors
// --------------------------------------------------

/// Kind of a [value] (0 bytes, 1 null, 2 not set). Complexity: O(1).
pub fn cql_value_kind(v: &CqlValue) -> Int {
  return v.kind;
}

/// A copy of a [value]'s payload (empty for null and not set).
/// Complexity: O(payload).
pub fn cql_value_data(v: &CqlValue) -> Vec[UInt8] {
  let data: Vec[UInt8] = v.data;
  return _copy_bytes(&data);
}

/// True when the [value] was null (-1). Complexity: O(1).
pub fn cql_value_is_null(v: &CqlValue) -> Bool {
  return v.kind == 1;
}

/// True when the [value] was not set (-2). Complexity: O(1).
pub fn cql_value_is_not_set(v: &CqlValue) -> Bool {
  return v.kind == 2;
}

/// True when the [value] carried bytes. Complexity: O(1).
pub fn cql_value_is_bytes(v: &CqlValue) -> Bool {
  return v.kind == 0;
}

/// Item count of a [string list]. Complexity: O(1).
pub fn cql_string_list_len(l: &CqlStringList) -> Int {
  return l.items.len();
}

/// Item `i` of a [string list], or "" when `i` is out of range.
/// Complexity: O(1).
pub fn cql_string_list_get(l: &CqlStringList, i: Int) -> Str {
  if i < 0 || i >= l.items.len() {
    return "";
  }
  let s: Str = l.items[i];
  return s;
}

/// Pair count of a [string map]. Complexity: O(1).
pub fn cql_string_map_len(m: &CqlStringMap) -> Int {
  return m.keys.len();
}

/// Key `i` of a [string map], or "" when `i` is out of range.
/// Complexity: O(1).
pub fn cql_string_map_key(m: &CqlStringMap, i: Int) -> Str {
  if i < 0 || i >= m.keys.len() {
    return "";
  }
  let s: Str = m.keys[i];
  return s;
}

/// Value `i` of a [string map], or "" when `i` is out of range.
/// Complexity: O(1).
pub fn cql_string_map_value(m: &CqlStringMap, i: Int) -> Str {
  if i < 0 || i >= m.values.len() {
    return "";
  }
  let s: Str = m.values[i];
  return s;
}

/// Index of `key` in a [string map] (str_compare, case-sensitive), or -1.
/// Complexity: O(keys).
pub fn cql_string_map_get(m: &CqlStringMap, key: Str) -> Int {
  var i = 0;
  while i < m.keys.len() {
    let k: Str = m.keys[i];
    if compare.str_compare(k, key) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Key count of a [string multimap]. Complexity: O(1).
pub fn cql_string_multimap_len(m: &CqlStringMultiMap) -> Int {
  return m.keys.len();
}

/// Key `i` of a [string multimap], or "" when `i` is out of range.
/// Complexity: O(1).
pub fn cql_string_multimap_key(m: &CqlStringMultiMap, i: Int) -> Str {
  if i < 0 || i >= m.keys.len() {
    return "";
  }
  let s: Str = m.keys[i];
  return s;
}

/// Number of values stored for key `i` of a [string multimap], or 0 when
/// `i` is out of range. Complexity: O(1).
pub fn cql_string_multimap_value_count(m: &CqlStringMultiMap, i: Int) -> Int {
  if i < 0 || i >= m.keys.len() {
    return 0;
  }
  let lo: Int = m.offsets[i];
  let hi: Int = m.offsets[i + 1];
  return hi - lo;
}

/// Value `j` of key `i` of a [string multimap], or "" when out of range.
/// Complexity: O(1).
pub fn cql_string_multimap_value(m: &CqlStringMultiMap, i: Int, j: Int) -> Str {
  let c: Int = cql_string_multimap_value_count(m, i);
  if j < 0 || j >= c {
    return "";
  }
  let lo: Int = m.offsets[i];
  let s: Str = m.values[lo + j];
  return s;
}

/// Pair count of a [bytes map]. Complexity: O(1).
pub fn cql_bytes_map_len(m: &CqlBytesMap) -> Int {
  return m.keys.len();
}

/// Key `i` of a [bytes map], or "" when `i` is out of range.
/// Complexity: O(1).
pub fn cql_bytes_map_key(m: &CqlBytesMap, i: Int) -> Str {
  if i < 0 || i >= m.keys.len() {
    return "";
  }
  let s: Str = m.keys[i];
  return s;
}

/// A copy of value `i` of a [bytes map], or empty when `i` is out of range.
/// Complexity: O(payload).
pub fn cql_bytes_map_value(m: &CqlBytesMap, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= m.values.len() {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = m.values[i];
  return _copy_bytes(&v);
}

// --------------------------------------------------
//  Frame header
// --------------------------------------------------

/// Parse exactly one frame starting at the reader's cursor: version byte,
/// flags byte, signed int16 stream id, opcode byte and int32 body length,
/// then that many body bytes. The cursor advances by 9 + body length (see
/// cql_frame_consumed).
///
/// Err("cassandra: unsupported protocol version N at offset M") for a
/// version byte outside {0x03, 0x83, 0x04, 0x84} (checked only once the
/// full 9-byte header is available); Err("cassandra: bad length N at offset
/// M") for a negative body length; Err("cassandra: truncated input at
/// offset M") for a short header; Err("cassandra: truncated body at offset
/// M: need N bytes, have K") for a body that overruns the buffer. Unknown
/// flags and opcodes are preserved raw. Complexity: O(body bytes).
pub fn cql_read_frame(r: &mut CqlReader) -> Result[CqlFrame, Str] {
  let start: Int = r.pos;
  let total: Int = r.data.len();
  if start + _HEADER_LEN > total {
    return _err_frame(_trunc_at(start));
  }
  let version: Int = _r_byte_mut(r, start);
  let flags: Int = _r_byte_mut(r, start + 1);
  if !_version_known(version) {
    return _err_frame("cassandra: unsupported protocol version " + convert.int_to_string(version) + " at offset " + convert.int_to_string(start));
  }
  let b2: Int = _r_byte_mut(r, start + 2);
  let b3: Int = _r_byte_mut(r, start + 3);
  let stream: Int = _sign_extend(b2 * 256 + b3, 16);
  let opcode: Int = _r_byte_mut(r, start + 4);
  let l0: Int = _r_byte_mut(r, start + 5);
  let l1: Int = _r_byte_mut(r, start + 6);
  let l2: Int = _r_byte_mut(r, start + 7);
  let l3: Int = _r_byte_mut(r, start + 8);
  let raw_len: Int = l0 * 16777216 + l1 * 65536 + l2 * 256 + l3;
  let length: Int = _sign_extend(raw_len, 32);
  if length < 0 {
    return _err_frame(_bad_len_msg(length, start + 5));
  }
  let body_start: Int = start + _HEADER_LEN;
  if body_start + length > total {
    let have: Int = total - body_start;
    return _err_frame("cassandra: truncated body at offset " + convert.int_to_string(body_start) + ": need " + convert.int_to_string(length) + " bytes, have " + convert.int_to_string(have));
  }
  var body = Vec[UInt8].new();
  var i = 0;
  while i < length {
    body.push(r.data[body_start + i]);
    i = i + 1;
  }
  r.pos = body_start + length;
  return _ok_frame(CqlFrame{ version: version; flags: flags; stream: stream; opcode: opcode; length: length; body: body; });
}

/// Parse the first frame of `data` (trailing bytes are left unconsumed;
/// compare cql_frame_consumed with data.len()). Complexity: O(data bytes).
pub fn cql_parse_frame(data: Vec[UInt8]) -> Result[CqlFrame, Str] {
  var r = cql_reader_new(data);
  return cql_read_frame(&mut r);
}

/// Append a frame header (9 bytes): version, flags, signed int16 stream,
/// opcode and int32 body length. The caller must pass a non-negative
/// length and a recognized version byte. Complexity: O(1).
pub fn cql_write_frame_header(w: &mut CqlWriter, version: Int, flags: Int, stream: Int, opcode: Int, length: Int) {
  _w_push_byte(w, version);
  _w_push_byte(w, flags);
  _w_push_be(w, stream, 2);
  _w_push_byte(w, opcode);
  _w_push_be(w, length, 4);
}

/// Append a complete frame: the 9-byte header with `body.len()` and the
/// body bytes. Complexity: O(body bytes).
pub fn cql_write_frame(w: &mut CqlWriter, version: Int, flags: Int, stream: Int, opcode: Int, body: &Vec[UInt8]) {
  cql_write_frame_header(w, version, flags, stream, opcode, body.len());
  _w_push_bytes(w, body);
}

/// Version byte of a frame. Complexity: O(1).
pub fn cql_frame_version(f: &CqlFrame) -> Int {
  return f.version;
}

/// Flags byte of a frame. Complexity: O(1).
pub fn cql_frame_flags(f: &CqlFrame) -> Int {
  return f.flags;
}

/// Stream id of a frame (signed int16). Complexity: O(1).
pub fn cql_frame_stream(f: &CqlFrame) -> Int {
  return f.stream;
}

/// Opcode of a frame (raw byte). Complexity: O(1).
pub fn cql_frame_opcode(f: &CqlFrame) -> Int {
  return f.opcode;
}

/// Body length of a frame. Complexity: O(1).
pub fn cql_frame_length(f: &CqlFrame) -> Int {
  return f.length;
}

/// A copy of the frame's body bytes. Complexity: O(body bytes).
pub fn cql_frame_body(f: &CqlFrame) -> Vec[UInt8] {
  let b: Vec[UInt8] = f.body;
  return _copy_bytes(&b);
}

/// True when the frame's version byte has the response direction bit.
/// Complexity: O(1).
pub fn cql_frame_is_response(f: &CqlFrame) -> Bool {
  return (f.version & _DIR_MASK) != 0;
}

/// True when the frame's version byte has the request direction bit clear.
/// Complexity: O(1).
pub fn cql_frame_is_request(f: &CqlFrame) -> Bool {
  return (f.version & _DIR_MASK) == 0;
}

// --------------------------------------------------
//  STARTUP body
// --------------------------------------------------

/// Read a STARTUP body: a [string map] of startup options (CQL_VERSION is
/// mandatory on the wire; see cql_startup_has_cql_version). Complexity:
/// O(payload).
pub fn cql_read_startup(r: &mut CqlReader) -> Result[CqlStringMap, Str] {
  return cql_read_string_map(r);
}

/// Write a STARTUP body from a [string map]. Complexity: O(payload).
pub fn cql_write_startup(w: &mut CqlWriter, m: &CqlStringMap) {
  cql_write_string_map(w, m);
}

/// True when a STARTUP map carries a CQL_VERSION entry. Complexity:
/// O(keys).
pub fn cql_startup_has_cql_version(m: &CqlStringMap) -> Bool {
  return cql_string_map_get(m, "CQL_VERSION") >= 0;
}

// --------------------------------------------------
//  QUERY body
// --------------------------------------------------

/// Parse a QUERY body: [long string] query, [short] consistency, [byte]
/// flags, then the flagged optional sections in wire order: page size
/// [int], paging state [bytes], serial consistency [short], timestamp
/// [long], and the values section (u16 count of [value], each optionally
/// preceded by its [string] name when flag 0x40 is set). value_names always
/// has value_count entries ("" for positional values).
///
/// The consistency value and the flags byte are preserved raw (see
/// cql_consistency_known and cql_query_flags_known). Err(bad length) for a
/// negative value length below -2, Err(oversized collection) for a value
/// count that cannot fit the remaining bytes, plus the primitive readers'
/// errors. Complexity: O(payload).
pub fn cql_read_query(r: &mut CqlReader) -> Result[CqlQuery, Str] {
  let qr = cql_read_long_string(r);
  if !qr.is_ok {
    return _err_query(qr.error);
  }
  let q: Str = qr.value;
  let cr = _read_u16(r);
  if !cr.is_ok {
    return _err_query(cr.error);
  }
  let cons: Int = cr.value;
  let fr = _read_unsigned(r, 1);
  if !fr.is_ok {
    return _err_query(fr.error);
  }
  let flags: Int = fr.value;
  var has_page: Bool = false;
  var page_size: Int = 0;
  var has_paging: Bool = false;
  var paging = Vec[UInt8].new();
  var has_serial: Bool = false;
  var serial: Int = 0;
  var has_ts: Bool = false;
  var ts: Int = 0;
  if (flags & _QF_PAGE_SIZE) != 0 {
    let pstart: Int = r.pos;
    let pr = _read_i32(r);
    if !pr.is_ok {
      return _err_query(pr.error);
    }
    page_size = pr.value;
    has_page = true;
    if page_size < 0 {
      return _err_query(_bad_num_msg("page size", page_size, pstart));
    }
  }
  if (flags & _QF_PAGING_STATE) != 0 {
    let psr = cql_read_bytes(r);
    if !psr.is_ok {
      return _err_query(psr.error);
    }
    let ps: Vec[UInt8] = psr.value;
    paging = ps;
    has_paging = true;
  }
  if (flags & _QF_SERIAL) != 0 {
    let sr = _read_u16(r);
    if !sr.is_ok {
      return _err_query(sr.error);
    }
    serial = sr.value;
    has_serial = true;
  }
  if (flags & _QF_TIMESTAMP) != 0 {
    let tr = _read64(r);
    if !tr.is_ok {
      return _err_query(tr.error);
    }
    ts = tr.value;
    has_ts = true;
  }
  var has_values: Bool = false;
  var vcount: Int = 0;
  var names = Vec[Str].new();
  var kinds = Vec[Int].new();
  var vals = Vec[Vec[UInt8]].new();
  if (flags & _QF_VALUES) != 0 {
    has_values = true;
    let vstart: Int = r.pos;
    let nvr = _read_u16(r);
    if !nvr.is_ok {
      return _err_query(nvr.error);
    }
    vcount = nvr.value;
    let remaining: Int = r.data.len() - r.pos;
    if vcount > remaining / 4 {
      return _err_query(_oversized_msg(vstart));
    }
    var i = 0;
    while i < vcount {
      var nm: Str = "";
      if (flags & _QF_NAMES) != 0 {
        let nr = cql_read_string(r);
        if !nr.is_ok {
          return _err_query(nr.error);
        }
        nm = nr.value;
      }
      let vr = cql_read_value(r);
      if !vr.is_ok {
        return _err_query(vr.error);
      }
      let val: CqlValue = vr.value;
      let kd: Int = val.kind;
      let payload: Vec[UInt8] = val.data;
      names.push(nm);
      kinds.push(kd);
      vals.push(payload);
      i = i + 1;
    }
  }
  return _ok_query(CqlQuery{ query: q; consistency: cons; flags: flags; has_values: has_values; value_count: vcount; value_names: names; value_kinds: kinds; values: vals; has_page_size: has_page; page_size: page_size; has_paging_state: has_paging; paging_state: paging; has_serial_consistency: has_serial; serial_consistency: serial; has_timestamp: has_ts; timestamp: ts; });
}

/// Write a QUERY body from a CqlQuery. The has_* flags must agree with the
/// flag byte (both directions are checked) and, when the values flag is
/// set, value_count must equal the length of each parallel value vector and
/// be <= 65535.
///
/// Err("cassandra: query page size flag mismatch"),
/// Err("cassandra: query paging state flag mismatch"),
/// Err("cassandra: query serial consistency flag mismatch"),
/// Err("cassandra: query timestamp flag mismatch"),
/// Err("cassandra: query value count mismatch") and
/// Err("cassandra: query value count exceeds 65535") are the only failures.
/// Complexity: O(payload).
pub fn cql_write_query(w: &mut CqlWriter, q: &CqlQuery) -> Result[Bool, Str] {
  cql_write_long_string(w, q.query);
  _w_push_be(w, q.consistency & 65535, 2);
  _w_push_byte(w, q.flags);
  let f_page: Bool = (q.flags & _QF_PAGE_SIZE) != 0;
  if f_page {
    if !q.has_page_size {
      return _err_bool("cassandra: query page size flag mismatch");
    }
    _w_push_be(w, q.page_size, 4);
  } else {
    if q.has_page_size {
      return _err_bool("cassandra: query page size flag mismatch");
    }
  }
  let f_paging: Bool = (q.flags & _QF_PAGING_STATE) != 0;
  if f_paging {
    if !q.has_paging_state {
      return _err_bool("cassandra: query paging state flag mismatch");
    }
    let ps: Vec[UInt8] = q.paging_state;
    cql_write_bytes(w, &ps);
  } else {
    if q.has_paging_state {
      return _err_bool("cassandra: query paging state flag mismatch");
    }
  }
  let f_serial: Bool = (q.flags & _QF_SERIAL) != 0;
  if f_serial {
    if !q.has_serial_consistency {
      return _err_bool("cassandra: query serial consistency flag mismatch");
    }
    _w_push_be(w, q.serial_consistency & 65535, 2);
  } else {
    if q.has_serial_consistency {
      return _err_bool("cassandra: query serial consistency flag mismatch");
    }
  }
  let f_ts: Bool = (q.flags & _QF_TIMESTAMP) != 0;
  if f_ts {
    if !q.has_timestamp {
      return _err_bool("cassandra: query timestamp flag mismatch");
    }
    _w_push_be(w, q.timestamp, 8);
  } else {
    if q.has_timestamp {
      return _err_bool("cassandra: query timestamp flag mismatch");
    }
  }
  let f_values: Bool = (q.flags & _QF_VALUES) != 0;
  if f_values {
    if q.value_count != q.values.len() || q.value_count != q.value_kinds.len() || q.value_count != q.value_names.len() {
      return _err_bool("cassandra: query value count mismatch");
    }
    if q.value_count > 65535 {
      return _err_bool("cassandra: query value count exceeds 65535");
    }
    _w_push_be(w, q.value_count, 2);
    let f_names: Bool = (q.flags & _QF_NAMES) != 0;
    var i = 0;
    while i < q.value_count {
      if f_names {
        let nm: Str = q.value_names[i];
        cql_write_string(w, nm);
      }
      let kd: Int = q.value_kinds[i];
      let payload: Vec[UInt8] = q.values[i];
      cql_write_value(w, kd, &payload);
      i = i + 1;
    }
  } else {
    if q.value_count != 0 {
      return _err_bool("cassandra: query value count mismatch");
    }
  }
  return _ok_bool(true);
}

/// Query text of a parsed QUERY body. Complexity: O(1).
pub fn cql_query_text(q: &CqlQuery) -> Str {
  return q.query;
}

/// Consistency value of a parsed QUERY body (raw; see
/// cql_consistency_known). Complexity: O(1).
pub fn cql_query_consistency(q: &CqlQuery) -> Int {
  return q.consistency;
}

/// Flags byte of a parsed QUERY body (raw). Complexity: O(1).
pub fn cql_query_flags(q: &CqlQuery) -> Int {
  return q.flags;
}

/// Number of values in a parsed QUERY body. Complexity: O(1).
pub fn cql_query_value_count(q: &CqlQuery) -> Int {
  return q.value_count;
}

/// Name `i` of a parsed QUERY body's values, or "" when out of range or
/// positional. Complexity: O(1).
pub fn cql_query_value_name(q: &CqlQuery, i: Int) -> Str {
  if i < 0 || i >= q.value_names.len() {
    return "";
  }
  let s: Str = q.value_names[i];
  return s;
}

/// Kind `i` of a parsed QUERY body's values (-1 when out of range);
/// see cql_value_kind_bytes / null / not_set. Complexity: O(1).
pub fn cql_query_value_kind(q: &CqlQuery, i: Int) -> Int {
  if i < 0 || i >= q.value_kinds.len() {
    return -1;
  }
  let k: Int = q.value_kinds[i];
  return k;
}

/// A copy of payload `i` of a parsed QUERY body's values, or empty when out
/// of range. Complexity: O(payload).
pub fn cql_query_value_data(q: &CqlQuery, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= q.values.len() {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = q.values[i];
  return _copy_bytes(&v);
}

// --------------------------------------------------
//  Type options (metadata column types)
// --------------------------------------------------

/// Read one type [option] and return its top-level code plus a display
/// rendering: simple names ("ascii".."duration"), "custom(<class>)",
/// "list<T>", "set<T>", "map<K, V>", "tuple<...>" or "udt(<ks>.<name>)".
/// UDT field definitions are consumed but not retained. Nesting deeper than
/// 32 is rejected. Complexity: O(option bytes).
pub fn cql_read_type(r: &mut CqlReader) -> Result[CqlTypeInfo, Str] {
  let start: Int = r.pos;
  let cr = _peek_u16(r, start);
  if !cr.is_ok {
    return _err_typeinfo(cr.error);
  }
  let code: Int = cr.value;
  let dr = _read_option_display(r, 0);
  if !dr.is_ok {
    return _err_typeinfo(dr.error);
  }
  let display: Str = dr.value;
  return _ok_typeinfo(CqlTypeInfo{ code: code; display: display; });
}

// Read a type option's code plus payload, recursing for list/set/map/tuple
// and consuming (but not retaining) UDT field definitions.
fn _read_option_display(r: &mut CqlReader, depth: Int) -> Result[Str, Str] {
  if depth > _MAX_TYPE_DEPTH {
    return _err_str("cassandra: type nesting depth exceeds limit of 32");
  }
  let cstart: Int = r.pos;
  let cr = _read_u16(r);
  if !cr.is_ok {
    return _err_str(cr.error);
  }
  let code: Int = cr.value;
  if code == 0 {
    let sr = cql_read_string(r);
    if !sr.is_ok {
      return _err_str(sr.error);
    }
    let cls: Str = sr.value;
    return _ok_str("custom(" + cls + ")");
  }
  if cql_type_simple_known(code) {
    return _ok_str(cql_type_simple_name(code));
  }
  if code == 32 {
    let er = _read_option_display(r, depth + 1);
    if !er.is_ok {
      return _err_str(er.error);
    }
    let e: Str = er.value;
    return _ok_str("list<" + e + ">");
  }
  if code == 34 {
    let er = _read_option_display(r, depth + 1);
    if !er.is_ok {
      return _err_str(er.error);
    }
    let e: Str = er.value;
    return _ok_str("set<" + e + ">");
  }
  if code == 33 {
    let kr = _read_option_display(r, depth + 1);
    if !kr.is_ok {
      return _err_str(kr.error);
    }
    let k: Str = kr.value;
    let vr = _read_option_display(r, depth + 1);
    if !vr.is_ok {
      return _err_str(vr.error);
    }
    let v: Str = vr.value;
    return _ok_str("map<" + k + ", " + v + ">");
  }
  if code == 48 {
    let ksr = cql_read_string(r);
    if !ksr.is_ok {
      return _err_str(ksr.error);
    }
    let ks: Str = ksr.value;
    let nr = cql_read_string(r);
    if !nr.is_ok {
      return _err_str(nr.error);
    }
    let nm: Str = nr.value;
    let nstart: Int = r.pos;
    let fcr = _read_u16(r);
    if !fcr.is_ok {
      return _err_str(fcr.error);
    }
    let nf: Int = fcr.value;
    let remaining: Int = r.data.len() - r.pos;
    if nf > remaining / 4 {
      return _err_str(_oversized_msg(nstart));
    }
    var i = 0;
    while i < nf {
      let fnr = cql_read_string(r);
      if !fnr.is_ok {
        return _err_str(fnr.error);
      }
      let ft = _read_option_display(r, depth + 1);
      if !ft.is_ok {
        return _err_str(ft.error);
      }
      i = i + 1;
    }
    return _ok_str("udt(" + ks + "." + nm + ")");
  }
  if code == 49 {
    let nstart: Int = r.pos;
    let ntr = _read_u16(r);
    if !ntr.is_ok {
      return _err_str(ntr.error);
    }
    let n: Int = ntr.value;
    let remaining: Int = r.data.len() - r.pos;
    if n > remaining / 2 {
      return _err_str(_oversized_msg(nstart));
    }
    var disp = "tuple<";
    var i = 0;
    while i < n {
      let er = _read_option_display(r, depth + 1);
      if !er.is_ok {
        return _err_str(er.error);
      }
      let e: Str = er.value;
      if i > 0 { disp = disp + ", "; }
      disp = disp + e;
      i = i + 1;
    }
    return _ok_str(disp + ">");
  }
  return _err_str("cassandra: unknown type option " + convert.int_to_string(code) + " at offset " + convert.int_to_string(cstart));
}

/// Type option code of a decoded type. Complexity: O(1).
pub fn cql_type_info_code(t: &CqlTypeInfo) -> Int {
  return t.code;
}

/// Display rendering of a decoded type. Complexity: O(1).
pub fn cql_type_info_display(t: &CqlTypeInfo) -> Str {
  return t.display;
}

// --------------------------------------------------
//  RESULT metadata
// --------------------------------------------------

/// Parse a [metadata] block used by ROWS and (twice) by PREPARED: int32
/// flags, int32 column count, an optional paging state when HAS_MORE_PAGES
/// is set, then for each column its keyspace, table, name and type option
/// (with GLOBAL_TABLES_SPEC a single keyspace/table pair covers all
/// columns). With NO_METADATA set no column specs follow and column_count
/// is recorded alone.
///
/// Err(bad metadata flags) for a negative flags word, Err(bad column count)
/// for a negative count, Err(oversized collection) for a count that cannot
/// fit the remaining bytes, plus the paging state and type option errors.
/// Complexity: O(metadata bytes).
pub fn cql_read_rows_metadata(r: &mut CqlReader) -> Result[CqlRowsMetadata, Str> {
  let fstart: Int = r.pos;
  let fr = _read_i32(r);
  if !fr.is_ok {
    return _err_meta(fr.error);
  }
  let flags: Int = fr.value;
  if flags < 0 {
    return _err_meta(_bad_num_msg("metadata flags", flags, fstart));
  }
  let cstart: Int = r.pos;
  let cr = _read_i32(r);
  if !cr.is_ok {
    return _err_meta(cr.error);
  }
  let cc: Int = cr.value;
  if cc < 0 {
    return _err_meta(_bad_num_msg("column count", cc, cstart));
  }
  var has_more: Bool = false;
  var has_paging: Bool = false;
  var paging = Vec[UInt8].new();
  if (flags & _MF_MORE) != 0 {
    let psr = cql_read_bytes(r);
    if !psr.is_ok {
      return _err_meta(psr.error);
    }
    let ps: Vec[UInt8] = psr.value;
    paging = ps;
    has_paging = true;
    has_more = true;
  }
  var vks = Vec[Str].new();
  var vtb = Vec[Str].new();
  var vnm = Vec[Str].new();
  var vtc = Vec[Int].new();
  var vtn = Vec[Str].new();
  if (flags & _MF_NONE) == 0 {
    let remaining: Int = r.data.len() - r.pos;
    if cc > remaining / 2 {
      return _err_meta(_oversized_msg(r.pos));
    }
    var c = 0;
    if (flags & _MF_GLOBAL) != 0 && cc > 0 {
      let ksr = cql_read_string(r);
      if !ksr.is_ok {
        return _err_meta(ksr.error);
      }
      let gks: Str = ksr.value;
      let tbr = cql_read_string(r);
      if !tbr.is_ok {
        return _err_meta(tbr.error);
      }
      let gtb: Str = tbr.value;
      while c < cc {
        let nmr = cql_read_string(r);
        if !nmr.is_ok {
          return _err_meta(nmr.error);
        }
        let nm: Str = nmr.value;
        let tr = cql_read_type(r);
        if !tr.is_ok {
          return _err_meta(tr.error);
        }
        let ti: CqlTypeInfo = tr.value;
        let tcode: Int = ti.code;
        let tdisp: Str = ti.display;
        vks.push(gks);
        vtb.push(gtb);
        vnm.push(nm);
        vtc.push(tcode);
        vtn.push(tdisp);
        c = c + 1;
      }
    } else {
      while c < cc {
        let ksr = cql_read_string(r);
        if !ksr.is_ok {
          return _err_meta(ksr.error);
        }
        let ks: Str = ksr.value;
        let tbr = cql_read_string(r);
        if !tbr.is_ok {
          return _err_meta(tbr.error);
        }
        let tb: Str = tbr.value;
        let nmr = cql_read_string(r);
        if !nmr.is_ok {
          return _err_meta(nmr.error);
        }
        let nm: Str = nmr.value;
        let tr = cql_read_type(r);
        if !tr.is_ok {
          return _err_meta(tr.error);
        }
        let ti: CqlTypeInfo = tr.value;
        let tcode: Int = ti.code;
        let tdisp: Str = ti.display;
        vks.push(ks);
        vtb.push(tb);
        vnm.push(nm);
        vtc.push(tcode);
        vtn.push(tdisp);
        c = c + 1;
      }
    }
  }
  return _ok_meta(CqlRowsMetadata{ flags: flags; column_count: cc; has_more_pages: has_more; global_tables_spec: (flags & _MF_GLOBAL) != 0; no_metadata: (flags & _MF_NONE) != 0; has_paging_state: has_paging; paging_state: paging; keyspaces: vks; tables: vtb; names: vnm; type_codes: vtc; type_names: vtn; });
}

/// Metadata flags word. Complexity: O(1).
pub fn cql_meta_flags(m: &CqlRowsMetadata) -> Int {
  return m.flags;
}

/// Column count of metadata. Complexity: O(1).
pub fn cql_meta_column_count(m: &CqlRowsMetadata) -> Int {
  return m.column_count;
}

/// True when the metadata HAS_MORE_PAGES flag is set. Complexity: O(1).
pub fn cql_meta_has_more_pages(m: &CqlRowsMetadata) -> Bool {
  return m.has_more_pages;
}

/// True when the metadata GLOBAL_TABLES_SPEC flag is set. Complexity: O(1).
pub fn cql_meta_global_tables_spec(m: &CqlRowsMetadata) -> Bool {
  return m.global_tables_spec;
}

/// True when the metadata NO_METADATA flag is set. Complexity: O(1).
pub fn cql_meta_no_metadata(m: &CqlRowsMetadata) -> Bool {
  return m.no_metadata;
}

/// True when a paging state was present. Complexity: O(1).
pub fn cql_meta_has_paging_state(m: &CqlRowsMetadata) -> Bool {
  return m.has_paging_state;
}

/// A copy of the metadata paging state (empty when absent). Complexity:
/// O(paging state).
pub fn cql_meta_paging_state(m: &CqlRowsMetadata) -> Vec[UInt8] {
  let ps: Vec[UInt8] = m.paging_state;
  return _copy_bytes(&ps);
}

/// Keyspace of column `i`, or "" when out of range. Complexity: O(1).
pub fn cql_meta_column_keyspace(m: &CqlRowsMetadata, i: Int) -> Str {
  if i < 0 || i >= m.keyspaces.len() {
    return "";
  }
  let s: Str = m.keyspaces[i];
  return s;
}

/// Table of column `i`, or "" when out of range. Complexity: O(1).
pub fn cql_meta_column_table(m: &CqlRowsMetadata, i: Int) -> Str {
  if i < 0 || i >= m.tables.len() {
    return "";
  }
  let s: Str = m.tables[i];
  return s;
}

/// Name of column `i`, or "" when out of range. Complexity: O(1).
pub fn cql_meta_column_name(m: &CqlRowsMetadata, i: Int) -> Str {
  if i < 0 || i >= m.names.len() {
    return "";
  }
  let s: Str = m.names[i];
  return s;
}

/// Type option code of column `i`, or -1 when out of range. Complexity:
/// O(1).
pub fn cql_meta_column_type_code(m: &CqlRowsMetadata, i: Int) -> Int {
  if i < 0 || i >= m.type_codes.len() {
    return -1;
  }
  let v: Int = m.type_codes[i];
  return v;
}

/// Type display of column `i`, or "" when out of range. Complexity: O(1).
pub fn cql_meta_column_type_name(m: &CqlRowsMetadata, i: Int) -> Str {
  if i < 0 || i >= m.type_names.len() {
    return "";
  }
  let s: Str = m.type_names[i];
  return s;
}

// --------------------------------------------------
//  RESULT body
// --------------------------------------------------

/// Parse a RESULT body. The int32 kind selects the layout:
/// VOID (nothing), ROWS ([metadata], int32 row count, then row-major [value]
/// cells where -1 is null and -2 is rejected), SET_KEYSPACE ([string]),
/// PREPARED ([short bytes] id, prepared [metadata], result [metadata]) and
/// SCHEMA_CHANGE (change type, target, then keyspace / keyspace+name /
/// keyspace+name+[string list] for KEYSPACE / TABLE|TYPE / FUNCTION|
/// AGGREGATE). The flat CqlResult carries every branch's fields; unused
/// groups keep their defaults.
///
/// Err("cassandra: unknown result kind N at offset M") for a kind outside
/// 0x01..0x05, Err("cassandra: unknown schema change target T at offset
/// M") for an unknown target, plus the metadata, primitive and row errors.
/// Complexity: O(body bytes).
pub fn cql_read_result_body(r: &mut CqlReader) -> Result[CqlResult, Str> {
  let kstart: Int = r.pos;
  let kr = _read_i32(r);
  if !kr.is_ok {
    return _err_result(kr.error);
  }
  let kind: Int = kr.value;
  if !_result_kind_known(kind) {
    return _err_result("cassandra: unknown result kind " + convert.int_to_string(kind) + " at offset " + convert.int_to_string(kstart));
  }
  var keyspace: Str = "";
  var meta_flags: Int = 0;
  var meta_cc: Int = 0;
  var meta_more: Bool = false;
  var meta_global: Bool = false;
  var meta_none: Bool = false;
  var meta_paging_flag: Bool = false;
  var meta_paging = Vec[UInt8].new();
  var col_ks = Vec[Str].new();
  var col_tb = Vec[Str].new();
  var col_nm = Vec[Str].new();
  var col_tc = Vec[Int].new();
  var col_tn = Vec[Str].new();
  var rows_count: Int = 0;
  var cell_kinds = Vec[Int].new();
  var cells = Vec[Vec[UInt8]].new();
  var prepared_id = Vec[UInt8].new();
  var res_flags: Int = 0;
  var res_cc: Int = 0;
  var res_more: Bool = false;
  var res_global: Bool = false;
  var res_none: Bool = false;
  var res_paging_flag: Bool = false;
  var res_paging = Vec[UInt8].new();
  var res_ks = Vec[Str].new();
  var res_tb = Vec[Str].new();
  var res_nm = Vec[Str].new();
  var res_tc = Vec[Int].new();
  var res_tn = Vec[Str].new();
  var sc_type: Str = "";
  var sc_target: Str = "";
  var sc_ks: Str = "";
  var sc_name: Str = "";
  var sc_args = Vec[Str].new();
  if kind == 2 {
    let mrows = cql_read_rows_metadata(r);
    if !mrows.is_ok {
      return _err_result(mrows.error);
    }
    let m: CqlRowsMetadata = mrows.value;
    meta_flags = m.flags;
    meta_cc = m.column_count;
    meta_more = m.has_more_pages;
    meta_global = m.global_tables_spec;
    meta_none = m.no_metadata;
    meta_paging_flag = m.has_paging_state;
    meta_paging = m.paging_state;
    col_ks = m.keyspaces;
    col_tb = m.tables;
    col_nm = m.names;
    col_tc = m.type_codes;
    col_tn = m.type_names;
    let rstart: Int = r.pos;
    let rcr = _read_i32(r);
    if !rcr.is_ok {
      return _err_result(rcr.error);
    }
    rows_count = rcr.value;
    if rows_count < 0 {
      return _err_result(_bad_num_msg("row count", rows_count, rstart));
    }
    var i = 0;
    while i < rows_count {
      var j = 0;
      while j < meta_cc {
        let vr = cql_read_value(r);
        if !vr.is_ok {
          return _err_result(vr.error);
        }
        let cell: CqlValue = vr.value;
        let ck: Int = cell.kind;
        if ck == 2 {
          return _err_result("cassandra: not-set value in result row at offset " + convert.int_to_string(r.pos));
        }
        let payload: Vec[UInt8] = cell.data;
        cell_kinds.push(ck);
        cells.push(payload);
        j = j + 1;
      }
      i = i + 1;
    }
  } elif kind == 3 {
    let sr = cql_read_string(r);
    if !sr.is_ok {
      return _err_result(sr.error);
    }
    keyspace = sr.value;
  } elif kind == 4 {
    let ir = cql_read_short_bytes(r);
    if !ir.is_ok {
      return _err_result(ir.error);
    }
    let pid: Vec[UInt8] = ir.value;
    prepared_id = pid;
    let mprep = cql_read_rows_metadata(r);
    if !mprep.is_ok {
      return _err_result(mprep.error);
    }
    let m: CqlRowsMetadata = mprep.value;
    meta_flags = m.flags;
    meta_cc = m.column_count;
    meta_more = m.has_more_pages;
    meta_global = m.global_tables_spec;
    meta_none = m.no_metadata;
    meta_paging_flag = m.has_paging_state;
    meta_paging = m.paging_state;
    col_ks = m.keyspaces;
    col_tb = m.tables;
    col_nm = m.names;
    col_tc = m.type_codes;
    col_tn = m.type_names;
    let mres = cql_read_rows_metadata(r);
    if !mres.is_ok {
      return _err_result(mres.error);
    }
    let m2: CqlRowsMetadata = mres.value;
    res_flags = m2.flags;
    res_cc = m2.column_count;
    res_more = m2.has_more_pages;
    res_global = m2.global_tables_spec;
    res_none = m2.no_metadata;
    res_paging_flag = m2.has_paging_state;
    res_paging = m2.paging_state;
    res_ks = m2.keyspaces;
    res_tb = m2.tables;
    res_nm = m2.names;
    res_tc = m2.type_codes;
    res_tn = m2.type_names;
  } elif kind == 5 {
    let tr = cql_read_string(r);
    if !tr.is_ok {
      return _err_result(tr.error);
    }
    sc_type = tr.value;
    let gstart: Int = r.pos;
    let gr = cql_read_string(r);
    if !gr.is_ok {
      return _err_result(gr.error);
    }
    sc_target = gr.value;
    if compare.str_compare(sc_target, "KEYSPACE") == 0 {
      let kr2 = cql_read_string(r);
      if !kr2.is_ok {
        return _err_result(kr2.error);
      }
      sc_ks = kr2.value;
    } elif compare.str_compare(sc_target, "TABLE") == 0 || compare.str_compare(sc_target, "TYPE") == 0 {
      let kr3 = cql_read_string(r);
      if !kr3.is_ok {
        return _err_result(kr3.error);
      }
      sc_ks = kr3.value;
      let nr3 = cql_read_string(r);
      if !nr3.is_ok {
        return _err_result(nr3.error);
      }
      sc_name = nr3.value;
    } elif compare.str_compare(sc_target, "FUNCTION") == 0 || compare.str_compare(sc_target, "AGGREGATE") == 0 {
      let kr4 = cql_read_string(r);
      if !kr4.is_ok {
        return _err_result(kr4.error);
      }
      sc_ks = kr4.value;
      let nr4 = cql_read_string(r);
      if !nr4.is_ok {
        return _err_result(nr4.error);
      }
      sc_name = nr4.value;
      let ar4 = cql_read_string_list(r);
      if !ar4.is_ok {
        return _err_result(ar4.error);
      }
      let al: CqlStringList = ar4.value;
      sc_args = al.items;
    } else {
      return _err_result("cassandra: unknown schema change target " + sc_target + " at offset " + convert.int_to_string(gstart));
    }
  }
  return _ok_result(CqlResult{ kind: kind; keyspace: keyspace; meta_flags: meta_flags; meta_column_count: meta_cc; meta_has_more_pages: meta_more; meta_global_tables_spec: meta_global; meta_no_metadata: meta_none; meta_has_paging_state: meta_paging_flag; meta_paging_state: meta_paging; col_keyspaces: col_ks; col_tables: col_tb; col_names: col_nm; col_type_codes: col_tc; col_type_names: col_tn; rows_count: rows_count; cell_kinds: cell_kinds; cells: cells; prepared_id: prepared_id; res_flags: res_flags; res_column_count: res_cc; res_has_more_pages: res_more; res_global_tables_spec: res_global; res_no_metadata: res_none; res_has_paging_state: res_paging_flag; res_paging_state: res_paging; res_col_keyspaces: res_ks; res_col_tables: res_tb; res_col_names: res_nm; res_col_type_codes: res_tc; res_col_type_names: res_tn; schema_change_type: sc_type; schema_change_target: sc_target; schema_change_keyspace: sc_ks; schema_change_name: sc_name; schema_change_args: sc_args; });
}

/// Result kind (raw; see cql_result_kind_known). Complexity: O(1).
pub fn cql_result_kind(r: &CqlResult) -> Int {
  return r.kind;
}

/// SET_KEYSPACE keyspace ("" for other kinds). Complexity: O(1).
pub fn cql_result_keyspace(r: &CqlResult) -> Str {
  return r.keyspace;
}

/// ROWS row count. Complexity: O(1).
pub fn cql_result_rows_count(r: &CqlResult) -> Int {
  return r.rows_count;
}

/// ROWS (or prepared) column count. Complexity: O(1).
pub fn cql_result_column_count(r: &CqlResult) -> Int {
  return r.meta_column_count;
}

/// True when the ROWS metadata NO_METADATA flag was set. Complexity: O(1).
pub fn cql_result_no_metadata(r: &CqlResult) -> Bool {
  return r.meta_no_metadata;
}

/// Name of ROWS column `i`, or "" when out of range. Complexity: O(1).
pub fn cql_result_column_name(r: &CqlResult, i: Int) -> Str {
  if i < 0 || i >= r.col_names.len() {
    return "";
  }
  let s: Str = r.col_names[i];
  return s;
}

/// Type display of ROWS column `i`, or "" when out of range. Complexity:
/// O(1).
pub fn cql_result_column_type_name(r: &CqlResult, i: Int) -> Str {
  if i < 0 || i >= r.col_type_names.len() {
    return "";
  }
  let s: Str = r.col_type_names[i];
  return s;
}

/// Number of row-major cells decoded from a ROWS result. Complexity: O(1).
pub fn cql_result_cell_count(r: &CqlResult) -> Int {
  return r.cells.len();
}

/// Kind of cell `i` (0 bytes, 1 null), or -1 when out of range.
/// Complexity: O(1).
pub fn cql_result_cell_kind(r: &CqlResult, i: Int) -> Int {
  if i < 0 || i >= r.cell_kinds.len() {
    return -1;
  }
  let k: Int = r.cell_kinds[i];
  return k;
}

/// A copy of cell `i`, or empty when out of range. Complexity: O(cell).
pub fn cql_result_cell(r: &CqlResult, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= r.cells.len() {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = r.cells[i];
  return _copy_bytes(&v);
}

/// A copy of the PREPARED statement id (empty for other kinds). Complexity:
/// O(id).
pub fn cql_result_prepared_id(r: &CqlResult) -> Vec[UInt8] {
  let v: Vec[UInt8] = r.prepared_id;
  return _copy_bytes(&v);
}

/// Column count of a PREPARED result metadata. Complexity: O(1).
pub fn cql_result_result_column_count(r: &CqlResult) -> Int {
  return r.res_column_count;
}

/// Name of result metadata column `i`, or "" when out of range. Complexity:
/// O(1).
pub fn cql_result_result_column_name(r: &CqlResult, i: Int) -> Str {
  if i < 0 || i >= r.res_col_names.len() {
    return "";
  }
  let s: Str = r.res_col_names[i];
  return s;
}

/// Type display of result metadata column `i`, or "" when out of range.
/// Complexity: O(1).
pub fn cql_result_result_column_type_name(r: &CqlResult, i: Int) -> Str {
  if i < 0 || i >= r.res_col_type_names.len() {
    return "";
  }
  let s: Str = r.res_col_type_names[i];
  return s;
}

/// SCHEMA_CHANGE change type ("CREATED"/"UPDATED"/"DROPPED"), or "".
/// Complexity: O(1).
pub fn cql_result_schema_change_type(r: &CqlResult) -> Str {
  return r.schema_change_type;
}

/// SCHEMA_CHANGE target ("KEYSPACE"/"TABLE"/"TYPE"/"FUNCTION"/
/// "AGGREGATE"), or "". Complexity: O(1).
pub fn cql_result_schema_change_target(r: &CqlResult) -> Str {
  return r.schema_change_target;
}

/// SCHEMA_CHANGE keyspace, or "". Complexity: O(1).
pub fn cql_result_schema_change_keyspace(r: &CqlResult) -> Str {
  return r.schema_change_keyspace;
}

/// SCHEMA_CHANGE object name ("" for a KEYSPACE change). Complexity: O(1).
pub fn cql_result_schema_change_name(r: &CqlResult) -> Str {
  return r.schema_change_name;
}

/// Number of argument types of a FUNCTION/AGGREGATE schema change.
/// Complexity: O(1).
pub fn cql_result_schema_change_arg_count(r: &CqlResult) -> Int {
  return r.schema_change_args.len();
}

/// Argument type `i` of a FUNCTION/AGGREGATE schema change, or "".
/// Complexity: O(1).
pub fn cql_result_schema_change_arg(r: &CqlResult, i: Int) -> Str {
  if i < 0 || i >= r.schema_change_args.len() {
    return "";
  }
  let s: Str = r.schema_change_args[i];
  return s;
}

// --------------------------------------------------
//  ERROR body
// --------------------------------------------------

/// Parse an ERROR body: int32 code, [string] message, then the extras the
/// code defines: UNAVAILABLE(consistency, required, alive),
/// WRITE_TIMEOUT(consistency, received, blockfor, write type),
/// READ_TIMEOUT(consistency, received, blockfor, data present),
/// READ_FAILURE(consistency, received, blockfor, failures, data present),
/// FUNCTION_FAILURE(keyspace, function, argument types),
/// WRITE_FAILURE(consistency, received, blockfor, failures, write type),
/// ALREADY_EXISTS(keyspace, table) and UNPREPARED(id). Unknown codes keep
/// their message and no extras (the code is preserved raw; see
/// cql_error_code_known).
///
/// Complexity: O(body bytes).
pub fn cql_read_error_body(r: &mut CqlReader) -> Result[CqlErrorBody, Str> {
  let cr = _read_i32(r);
  if !cr.is_ok {
    return _err_errbody(cr.error);
  }
  let code: Int = cr.value;
  let mr = cql_read_string(r);
  if !mr.is_ok {
    return _err_errbody(mr.error);
  }
  let msg: Str = mr.value;
  var cons: Int = 0;
  var required: Int = 0;
  var alive: Int = 0;
  var received: Int = 0;
  var blockfor: Int = 0;
  var data_present: Bool = false;
  var num_failures: Int = 0;
  var write_type: Str = "";
  var keyspace: Str = "";
  var table: Str = "";
  var function: Str = "";
  var arg_types = Vec[Str].new();
  var prepared_id = Vec[UInt8].new();
  if code == 4096 {
    let c1 = _read_u16(r);
    if !c1.is_ok { return _err_errbody(c1.error); }
    cons = c1.value;
    let c2 = _read_i32(r);
    if !c2.is_ok { return _err_errbody(c2.error); }
    required = c2.value;
    let c3 = _read_i32(r);
    if !c3.is_ok { return _err_errbody(c3.error); }
    alive = c3.value;
  } elif code == 4352 {
    let c1 = _read_u16(r);
    if !c1.is_ok { return _err_errbody(c1.error); }
    cons = c1.value;
    let c2 = _read_i32(r);
    if !c2.is_ok { return _err_errbody(c2.error); }
    received = c2.value;
    let c3 = _read_i32(r);
    if !c3.is_ok { return _err_errbody(c3.error); }
    blockfor = c3.value;
    let s1 = cql_read_string(r);
    if !s1.is_ok { return _err_errbody(s1.error); }
    write_type = s1.value;
  } elif code == 4608 {
    let c1 = _read_u16(r);
    if !c1.is_ok { return _err_errbody(c1.error); }
    cons = c1.value;
    let c2 = _read_i32(r);
    if !c2.is_ok { return _err_errbody(c2.error); }
    received = c2.value;
    let c3 = _read_i32(r);
    if !c3.is_ok { return _err_errbody(c3.error); }
    blockfor = c3.value;
    let c4 = _read_unsigned(r, 1);
    if !c4.is_ok { return _err_errbody(c4.error); }
    let dv: Int = c4.value;
    data_present = dv != 0;
  } elif code == 4864 {
    let c1 = _read_u16(r);
    if !c1.is_ok { return _err_errbody(c1.error); }
    cons = c1.value;
    let c2 = _read_i32(r);
    if !c2.is_ok { return _err_errbody(c2.error); }
    received = c2.value;
    let c3 = _read_i32(r);
    if !c3.is_ok { return _err_errbody(c3.error); }
    blockfor = c3.value;
    let c4 = _read_i32(r);
    if !c4.is_ok { return _err_errbody(c4.error); }
    num_failures = c4.value;
    let c5 = _read_unsigned(r, 1);
    if !c5.is_ok { return _err_errbody(c5.error); }
    let dv: Int = c5.value;
    data_present = dv != 0;
  } elif code == 5120 {
    let s1 = cql_read_string(r);
    if !s1.is_ok { return _err_errbody(s1.error); }
    keyspace = s1.value;
    let s2 = cql_read_string(r);
    if !s2.is_ok { return _err_errbody(s2.error); }
    function = s2.value;
    let l1 = cql_read_string_list(r);
    if !l1.is_ok { return _err_errbody(l1.error); }
    let al: CqlStringList = l1.value;
    arg_types = al.items;
  } elif code == 5376 {
    let c1 = _read_u16(r);
    if !c1.is_ok { return _err_errbody(c1.error); }
    cons = c1.value;
    let c2 = _read_i32(r);
    if !c2.is_ok { return _err_errbody(c2.error); }
    received = c2.value;
    let c3 = _read_i32(r);
    if !c3.is_ok { return _err_errbody(c3.error); }
    blockfor = c3.value;
    let c4 = _read_i32(r);
    if !c4.is_ok { return _err_errbody(c4.error); }
    num_failures = c4.value;
    let s1 = cql_read_string(r);
    if !s1.is_ok { return _err_errbody(s1.error); }
    write_type = s1.value;
  } elif code == 9216 {
    let s1 = cql_read_string(r);
    if !s1.is_ok { return _err_errbody(s1.error); }
    keyspace = s1.value;
    let s2 = cql_read_string(r);
    if !s2.is_ok { return _err_errbody(s2.error); }
    table = s2.value;
  } elif code == 9472 {
    let b1 = cql_read_short_bytes(r);
    if !b1.is_ok { return _err_errbody(b1.error); }
    let pid: Vec[UInt8] = b1.value;
    prepared_id = pid;
  }
  return _ok_errbody(CqlErrorBody{ code: code; message: msg; consistency: cons; required: required; alive: alive; received: received; blockfor: blockfor; data_present: data_present; num_failures: num_failures; write_type: write_type; keyspace: keyspace; table: table; function: function; arg_types: arg_types; prepared_id: prepared_id; });
}

/// ERROR code (raw; unknown codes are preserved). Complexity: O(1).
pub fn cql_error_body_code(e: &CqlErrorBody) -> Int {
  return e.code;
}

/// ERROR message. Complexity: O(1).
pub fn cql_error_body_message(e: &CqlErrorBody) -> Str {
  return e.message;
}

/// UNAVAILABLE/WRITE_TIMEOUT/READ_TIMEOUT/READ_FAILURE/WRITE_FAILURE
/// consistency, or 0 when not defined for the code. Complexity: O(1).
pub fn cql_error_body_consistency(e: &CqlErrorBody) -> Int {
  return e.consistency;
}

/// UNAVAILABLE required replica count. Complexity: O(1).
pub fn cql_error_body_required(e: &CqlErrorBody) -> Int {
  return e.required;
}

/// UNAVAILABLE alive replica count. Complexity: O(1).
pub fn cql_error_body_alive(e: &CqlErrorBody) -> Int {
  return e.alive;
}

/// WRITE_TIMEOUT/READ_TIMEOUT/READ_FAILURE/WRITE_FAILURE received count.
/// Complexity: O(1).
pub fn cql_error_body_received(e: &CqlErrorBody) -> Int {
  return e.received;
}

/// WRITE_TIMEOUT/READ_TIMEOUT/READ_FAILURE/WRITE_FAILURE block-for count.
/// Complexity: O(1).
pub fn cql_error_body_blockfor(e: &CqlErrorBody) -> Int {
  return e.blockfor;
}

/// READ_TIMEOUT/READ_FAILURE data-present flag. Complexity: O(1).
pub fn cql_error_body_data_present(e: &CqlErrorBody) -> Bool {
  return e.data_present;
}

/// READ_FAILURE/WRITE_FAILURE per-replica failure count. Complexity: O(1).
pub fn cql_error_body_num_failures(e: &CqlErrorBody) -> Int {
  return e.num_failures;
}

/// WRITE_TIMEOUT/WRITE_FAILURE write type (e.g. "SIMPLE", "BATCH"),
/// or "". Complexity: O(1).
pub fn cql_error_body_write_type(e: &CqlErrorBody) -> Str {
  return e.write_type;
}

/// FUNCTION_FAILURE/ALREADY_EXISTS keyspace, or "". Complexity: O(1).
pub fn cql_error_body_keyspace(e: &CqlErrorBody) -> Str {
  return e.keyspace;
}

/// ALREADY_EXISTS table, or "". Complexity: O(1).
pub fn cql_error_body_table(e: &CqlErrorBody) -> Str {
  return e.table;
}

/// FUNCTION_FAILURE function name, or "". Complexity: O(1).
pub fn cql_error_body_function(e: &CqlErrorBody) -> Str {
  return e.function;
}

/// Number of FUNCTION_FAILURE argument types. Complexity: O(1).
pub fn cql_error_body_arg_count(e: &CqlErrorBody) -> Int {
  return e.arg_types.len();
}

/// FUNCTION_FAILURE argument type `i`, or "" when out of range.
/// Complexity: O(1).
pub fn cql_error_body_arg(e: &CqlErrorBody, i: Int) -> Str {
  if i < 0 || i >= e.arg_types.len() {
    return "";
  }
  let s: Str = e.arg_types[i];
  return s;
}

/// UNPREPARED statement id (empty otherwise). Complexity: O(id).
pub fn cql_error_body_prepared_id(e: &CqlErrorBody) -> Vec[UInt8] {
  let v: Vec[UInt8] = e.prepared_id;
  return _copy_bytes(&v);
}
