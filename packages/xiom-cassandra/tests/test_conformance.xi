// XIOM -- xiom.cassandra conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the constant tables (versions, frame flags,
// opcodes, consistency levels, query flags, result kinds, metadata flags,
// value kinds, type codes, error codes), the frame header codec with
// consumed counts, the primitive codecs with their truncation/UTF-8/NUL/
// null/bad-length errors, the string containers with oversized-count
// guards, [value] null/not-set semantics, the QUERY flag matrix, the five
// RESULT kinds (VOID, ROWS, SET_KEYSPACE, PREPARED, SCHEMA_CHANGE), the
// type option renderer, the ERROR body extras, and accessor edge cases.
//
// Harness style mirrors xiom.thrift / xiom.snmp: one fn tN() -> TestResult
// per check, called directly from main; main prints [PASS]/[FAIL] and
// returns the failure count. Synthetic buffers are built in-test from hex
// literals (xiom.encoding.hex) and from the package's own writers; no
// external data files. Str payloads are compared with str_compare (BUG 17
// discipline: `==` on Str values read from a Vec lowers to a pointer
// comparison).

module cassandra_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.encoding.hex;
use xiom.cassandra;

// --------------------------------------------------
//  Test helpers
// --------------------------------------------------

// Bytes for a hex string ("" decodes to an empty vector).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if ((x as Int) & 0xFF) != ((y as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when both strings are byte-identical (BUG 17 discipline).
fn str_is(s: Str, want: Str) -> Bool {
  return str_compare(s, want) == 0;
}

fn err_is_i(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_b(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_s(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_bts(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_val(r: Result[CqlValue, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_sl(r: Result[CqlStringList, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_sm(r: Result[CqlStringMap, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_mm(r: Result[CqlStringMultiMap, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_bm(r: Result[CqlBytesMap, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_frame(r: Result[CqlFrame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_q(r: Result[CqlQuery, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_ti(r: Result[CqlTypeInfo, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_meta(r: Result[CqlRowsMetadata, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_res(r: Result[CqlResult, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

fn err_is_eb(r: Result[CqlErrorBody, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_compare(r.error, want) == 0;
}

// Build a normalized QUERY struct: the has_* fields are derived from the
// flag byte so writer and reader always agree. Unused field values must be
// passed as empty vectors/zeroes.
fn mkq(query: Str, consistency: Int, flags: Int, page_size: Int, paging_state: Vec[UInt8], serial: Int, ts: Int, names: Vec[Str], kinds: Vec[Int], vals: Vec[Vec[UInt8]]) -> CqlQuery {
  var vcount: Int = 0;
  let fv: Bool = (flags & cql_query_flag_values()) != 0;
  if fv { vcount = vals.len(); }
  let f_page: Bool = (flags & cql_query_flag_page_size()) != 0;
  let f_paging: Bool = (flags & cql_query_flag_paging_state()) != 0;
  let f_serial: Bool = (flags & cql_query_flag_serial_consistency()) != 0;
  let f_ts: Bool = (flags & cql_query_flag_default_timestamp()) != 0;
  return CqlQuery{ query: query; consistency: consistency; flags: flags; has_values: fv; value_count: vcount; value_names: names; value_kinds: kinds; values: vals; has_page_size: f_page; page_size: page_size; has_paging_state: f_paging; paging_state: paging_state; has_serial_consistency: f_serial; serial_consistency: serial; has_timestamp: f_ts; timestamp: ts; };
}

// A QUERY with the page-size flag set but no page size field (mismatch).
fn mkq_bad_page() -> CqlQuery {
  return CqlQuery{ query: "q"; consistency: 0; flags: 4; has_values: false; value_count: 0; value_names: Vec[Str].new(); value_kinds: Vec[Int].new(); values: Vec[Vec[UInt8]].new(); has_page_size: false; page_size: 0; has_paging_state: false; paging_state: Vec[UInt8].new(); has_serial_consistency: false; serial_consistency: 0; has_timestamp: false; timestamp: 0; };
}

// A QUERY whose value_count disagrees with its parallel vectors.
fn mkq_bad_count() -> CqlQuery {
  var names = Vec[Str].new();
  names.push("a");
  var kinds = Vec[Int].new();
  kinds.push(0);
  var vals = Vec[Vec[UInt8]].new();
  let e = Vec[UInt8].new();
  vals.push(e);
  return CqlQuery{ query: "q"; consistency: 0; flags: 1; has_values: true; value_count: 2; value_names: names; value_kinds: kinds; values: vals; has_page_size: false; page_size: 0; has_paging_state: false; paging_state: Vec[UInt8].new(); has_serial_consistency: false; serial_consistency: 0; has_timestamp: false; timestamp: 0; };
}

// Write a metadata block with GLOBAL_TABLES_SPEC and one global ks/table.
fn w_meta_global(w: &mut CqlWriter, ks: Str, tbl: Str, names: Vec[Str], codes: Vec[Int]) {
  cql_write_int(w, 1);
  cql_write_int(w, names.len());
  cql_write_string(w, ks);
  cql_write_string(w, tbl);
  var i = 0;
  while i < names.len() {
    let n: Str = names[i];
    let c: Int = codes[i];
    cql_write_string(w, n);
    cql_write_short(w, c);
    i = i + 1;
  }
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = true;
  if cql_protocol_version() != 4 { ok = false; }
  if cql_version_request_v4() != 4 { ok = false; }
  if cql_version_response_v4() != 132 { ok = false; }
  if cql_version_request_v3() != 3 { ok = false; }
  if cql_version_response_v3() != 131 { ok = false; }
  if cql_version_direction_mask() != 128 { ok = false; }
  if !cql_version_known(4) { ok = false; }
  if !cql_version_known(3) { ok = false; }
  if !cql_version_known(131) { ok = false; }
  if !cql_version_known(132) { ok = false; }
  if cql_version_known(5) { ok = false; }
  if cql_version_protocol(132) != 4 { ok = false; }
  if cql_version_protocol(131) != 3 { ok = false; }
  if !cql_version_is_response(132) { ok = false; }
  if cql_version_is_response(4) { ok = false; }
  if !cql_version_is_request(4) { ok = false; }
  if cql_frame_header_len() != 9 { ok = false; }
  if cql_flag_compression() != 1 { ok = false; }
  if cql_flag_tracing() != 2 { ok = false; }
  if cql_flag_custom_payload() != 4 { ok = false; }
  if cql_flag_warning() != 8 { ok = false; }
  if cql_flag_use_beta() != 16 { ok = false; }
  if !cql_flags_known(31) { ok = false; }
  if !cql_flags_known(0) { ok = false; }
  if cql_flags_known(32) { ok = false; }
  if cql_opcode_error() != 0 { ok = false; }
  if cql_opcode_startup() != 1 { ok = false; }
  if cql_opcode_ready() != 2 { ok = false; }
  if cql_opcode_authenticate() != 3 { ok = false; }
  if cql_opcode_options() != 5 { ok = false; }
  if cql_opcode_supported() != 6 { ok = false; }
  if cql_opcode_query() != 7 { ok = false; }
  if cql_opcode_result() != 8 { ok = false; }
  if cql_opcode_prepare() != 9 { ok = false; }
  if cql_opcode_execute() != 10 { ok = false; }
  if cql_opcode_register() != 11 { ok = false; }
  if cql_opcode_event() != 12 { ok = false; }
  if cql_opcode_batch() != 13 { ok = false; }
  if cql_opcode_auth_challenge() != 14 { ok = false; }
  if cql_opcode_auth_response() != 15 { ok = false; }
  if cql_opcode_auth_success() != 16 { ok = false; }
  if !cql_opcode_known(0) { ok = false; }
  if !cql_opcode_known(16) { ok = false; }
  if cql_opcode_known(4) { ok = false; }
  if cql_opcode_known(17) { ok = false; }
  if cql_opcode_known(127) { ok = false; }
  if !str_is(cql_opcode_name(0), "ERROR") { ok = false; }
  if !str_is(cql_opcode_name(2), "READY") { ok = false; }
  if !str_is(cql_opcode_name(7), "QUERY") { ok = false; }
  if !str_is(cql_opcode_name(16), "AUTH_SUCCESS") { ok = false; }
  if !str_is(cql_opcode_name(127), "UNKNOWN") { ok = false; }
  return assert(ok, "version bytes, frame flags and the 16-entry opcode table");
}

fn t2() -> TestResult {
  var ok = true;
  if cql_consistency_any() != 0 { ok = false; }
  if cql_consistency_one() != 1 { ok = false; }
  if cql_consistency_two() != 2 { ok = false; }
  if cql_consistency_three() != 3 { ok = false; }
  if cql_consistency_quorum() != 4 { ok = false; }
  if cql_consistency_all() != 5 { ok = false; }
  if cql_consistency_local_quorum() != 6 { ok = false; }
  if cql_consistency_each_quorum() != 7 { ok = false; }
  if cql_consistency_serial() != 8 { ok = false; }
  if cql_consistency_local_serial() != 9 { ok = false; }
  if cql_consistency_local_one() != 10 { ok = false; }
  if !cql_consistency_known(0) { ok = false; }
  if !cql_consistency_known(10) { ok = false; }
  if cql_consistency_known(11) { ok = false; }
  if cql_consistency_known(-1) { ok = false; }
  if !str_is(cql_consistency_name(0), "ANY") { ok = false; }
  if !str_is(cql_consistency_name(5), "ALL") { ok = false; }
  if !str_is(cql_consistency_name(8), "SERIAL") { ok = false; }
  if !str_is(cql_consistency_name(9), "LOCAL_SERIAL") { ok = false; }
  if !str_is(cql_consistency_name(11), "UNKNOWN") { ok = false; }
  if cql_query_flag_values() != 1 { ok = false; }
  if cql_query_flag_skip_metadata() != 2 { ok = false; }
  if cql_query_flag_page_size() != 4 { ok = false; }
  if cql_query_flag_paging_state() != 8 { ok = false; }
  if cql_query_flag_serial_consistency() != 16 { ok = false; }
  if cql_query_flag_default_timestamp() != 32 { ok = false; }
  if cql_query_flag_names_for_values() != 64 { ok = false; }
  if cql_query_flag_keyspace() != 128 { ok = false; }
  if !cql_query_flags_known(127) { ok = false; }
  if cql_query_flags_known(128) { ok = false; }
  if cql_result_void() != 1 { ok = false; }
  if cql_result_rows() != 2 { ok = false; }
  if cql_result_set_keyspace() != 3 { ok = false; }
  if cql_result_prepared() != 4 { ok = false; }
  if cql_result_schema_change() != 5 { ok = false; }
  if !cql_result_kind_known(5) { ok = false; }
  if cql_result_kind_known(0) { ok = false; }
  if cql_result_kind_known(6) { ok = false; }
  if cql_meta_flag_global_tables_spec() != 1 { ok = false; }
  if cql_meta_flag_has_more_pages() != 2 { ok = false; }
  if cql_meta_flag_no_metadata() != 4 { ok = false; }
  if !cql_meta_flags_known(7) { ok = false; }
  if cql_meta_flags_known(8) { ok = false; }
  if cql_meta_flags_known(-1) { ok = false; }
  if cql_value_kind_bytes() != 0 { ok = false; }
  if cql_value_kind_null() != 1 { ok = false; }
  if cql_value_kind_not_set() != 2 { ok = false; }
  if cql_type_custom() != 0 { ok = false; }
  if cql_type_ascii() != 1 { ok = false; }
  if cql_type_bigint() != 2 { ok = false; }
  if cql_type_blob() != 3 { ok = false; }
  if cql_type_boolean() != 4 { ok = false; }
  if cql_type_counter() != 5 { ok = false; }
  if cql_type_decimal() != 6 { ok = false; }
  if cql_type_double() != 7 { ok = false; }
  if cql_type_float() != 8 { ok = false; }
  if cql_type_int() != 9 { ok = false; }
  if cql_type_timestamp() != 10 { ok = false; }
  if cql_type_uuid() != 11 { ok = false; }
  if cql_type_varchar() != 12 { ok = false; }
  if cql_type_varint() != 13 { ok = false; }
  if cql_type_timeuuid() != 14 { ok = false; }
  if cql_type_inet() != 15 { ok = false; }
  if cql_type_date() != 16 { ok = false; }
  if cql_type_time() != 17 { ok = false; }
  if cql_type_smallint() != 18 { ok = false; }
  if cql_type_tinyint() != 19 { ok = false; }
  if cql_type_duration() != 20 { ok = false; }
  if cql_type_list() != 32 { ok = false; }
  if cql_type_map() != 33 { ok = false; }
  if cql_type_set() != 34 { ok = false; }
  if cql_type_udt() != 48 { ok = false; }
  if cql_type_tuple() != 49 { ok = false; }
  if !cql_type_simple_known(1) { ok = false; }
  if !cql_type_simple_known(20) { ok = false; }
  if cql_type_simple_known(0) { ok = false; }
  if cql_type_simple_known(21) { ok = false; }
  if !str_is(cql_type_simple_name(9), "int") { ok = false; }
  if !str_is(cql_type_simple_name(12), "varchar") { ok = false; }
  if !str_is(cql_type_simple_name(255), "UNKNOWN") { ok = false; }
  if cql_error_code_server_error() != 0 { ok = false; }
  if cql_error_code_protocol_error() != 10 { ok = false; }
  if cql_error_code_bad_credentials() != 256 { ok = false; }
  if cql_error_code_unavailable() != 4096 { ok = false; }
  if cql_error_code_overloaded() != 4097 { ok = false; }
  if cql_error_code_is_bootstrapping() != 4098 { ok = false; }
  if cql_error_code_truncate_error() != 4099 { ok = false; }
  if cql_error_code_write_timeout() != 4352 { ok = false; }
  if cql_error_code_read_timeout() != 4608 { ok = false; }
  if cql_error_code_read_failure() != 4864 { ok = false; }
  if cql_error_code_function_failure() != 5120 { ok = false; }
  if cql_error_code_write_failure() != 5376 { ok = false; }
  if cql_error_code_syntax_error() != 8192 { ok = false; }
  if cql_error_code_unauthorized() != 8448 { ok = false; }
  if cql_error_code_invalid() != 8704 { ok = false; }
  if cql_error_code_config_error() != 8960 { ok = false; }
  if cql_error_code_already_exists() != 9216 { ok = false; }
  if cql_error_code_unprepared() != 9472 { ok = false; }
  if !cql_error_code_known(0) { ok = false; }
  if !cql_error_code_known(4096) { ok = false; }
  if !cql_error_code_known(9472) { ok = false; }
  if cql_error_code_known(9) { ok = false; }
  if cql_error_code_known(9473) { ok = false; }
  if !str_is(cql_error_code_name(0), "SERVER_ERROR") { ok = false; }
  if !str_is(cql_error_code_name(4096), "UNAVAILABLE") { ok = false; }
  if !str_is(cql_error_code_name(4352), "WRITE_TIMEOUT") { ok = false; }
  if !str_is(cql_error_code_name(8704), "INVALID") { ok = false; }
  if !str_is(cql_error_code_name(9472), "UNPREPARED") { ok = false; }
  if !str_is(cql_error_code_name(123), "UNKNOWN") { ok = false; }
  return assert(ok, "consistency, query flags, result kinds, meta flags, value kinds, type codes and error codes");
}

fn t3() -> TestResult {
  var w = cql_writer_new();
  cql_write_frame_header(&mut w, 4, 0, 5, 7, 0);
  var ok = bytes_equal(cql_writer_bytes(&w), hb("040000050700000000"));
  if cql_writer_len(&w) != 9 { ok = false; }
  var r = cql_reader_new(hb("040000050700000000"));
  let fr = cql_read_frame(&mut r);
  if !fr.is_ok { ok = false; } else {
    let f: CqlFrame = fr.value;
    if cql_frame_version(&f) != 4 { ok = false; }
    if cql_frame_flags(&f) != 0 { ok = false; }
    if cql_frame_stream(&f) != 5 { ok = false; }
    if cql_frame_opcode(&f) != 7 { ok = false; }
    if cql_frame_length(&f) != 0 { ok = false; }
    if cql_frame_consumed(&f) != 9 { ok = false; }
    if cql_frame_body(&f).len() != 0 { ok = false; }
    if !cql_frame_is_request(&f) { ok = false; }
    if cql_frame_is_response(&f) { ok = false; }
  }
  if cql_reader_remaining(&r) != 0 { ok = false; }
  var w2 = cql_writer_new();
  let empty = Vec[UInt8].new();
  cql_write_frame(&mut w2, 132, 0, 1, 2, &empty);
  if !bytes_equal(cql_writer_bytes(&w2), hb("840000010200000000")) { ok = false; }
  return assert(ok, "frame header encodes/decodes exactly and reports consumed bytes");
}

fn t4() -> TestResult {
  var ok = true;
  let frame_hex = "0400000001000000280002000B43514C5F56455253494F4E0005332E302E30000B434F4D5052455353494F4E00036C7A34";
  let fr = cql_parse_frame(hb(frame_hex));
  if !fr.is_ok { ok = false; } else {
    let f: CqlFrame = fr.value;
    if cql_frame_version(&f) != cql_version_request_v4() { ok = false; }
    if cql_frame_opcode(&f) != cql_opcode_startup() { ok = false; }
    if cql_frame_length(&f) != 40 { ok = false; }
    if cql_frame_consumed(&f) != 49 { ok = false; }
    let body: Vec[UInt8] = cql_frame_body(&f);
    var br = cql_reader_new(body);
    let sr = cql_read_startup(&mut br);
    if !sr.is_ok { ok = false; } else {
      let m: CqlStringMap = sr.value;
      if cql_string_map_len(&m) != 2 { ok = false; }
      if !str_is(cql_string_map_key(&m, 0), "CQL_VERSION") { ok = false; }
      if !str_is(cql_string_map_value(&m, 0), "3.0.0") { ok = false; }
      if !str_is(cql_string_map_key(&m, 1), "COMPRESSION") { ok = false; }
      if !str_is(cql_string_map_value(&m, 1), "lz4") { ok = false; }
      if cql_string_map_get(&m, "COMPRESSION") != 1 { ok = false; }
      if cql_string_map_get(&m, "NOPE") != -1 { ok = false; }
      if !cql_startup_has_cql_version(&m) { ok = false; }
      if !str_is(cql_string_map_key(&m, 9), "") { ok = false; }
      if !str_is(cql_string_map_value(&m, -1), "") { ok = false; }
    }
    if cql_reader_remaining(&br) != 0 { ok = false; }
  }
  var w = cql_writer_new();
  var keys = Vec[Str].new();
  keys.push("CQL_VERSION");
  var vals = Vec[Str].new();
  vals.push("3.0.0");
  let m2 = CqlStringMap{ keys: keys; values: vals };
  cql_write_startup(&mut w, &m2);
  if !bytes_equal(cql_writer_bytes(&w), hb("0001000B43514C5F56455253494F4E0005332E302E30")) { ok = false; }
  return assert(ok, "STARTUP frame and string-map body round-trip (exact bytes)");
}

fn t5() -> TestResult {
  var ok = true;
  var r = cql_reader_new(hb("840000010200000000840000020200000000"));
  let f1r = cql_read_frame(&mut r);
  if !f1r.is_ok { ok = false; } else {
    let f1: CqlFrame = f1r.value;
    if !cql_frame_is_response(&f1) { ok = false; }
    if cql_frame_opcode(&f1) != cql_opcode_ready() { ok = false; }
    if cql_frame_stream(&f1) != 1 { ok = false; }
    if cql_frame_consumed(&f1) != 9 { ok = false; }
  }
  let pos1: Int = cql_reader_pos_mut(&mut r);
  if pos1 != 9 { ok = false; }
  let f2r = cql_read_frame(&mut r);
  if !f2r.is_ok { ok = false; } else {
    let f2: CqlFrame = f2r.value;
    if cql_frame_stream(&f2) != 2 { ok = false; }
    if cql_frame_length(&f2) != 0 { ok = false; }
  }
  let pos2: Int = cql_reader_pos_mut(&mut r);
  if pos2 != 18 { ok = false; }
  if cql_reader_remaining(&r) != 0 { ok = false; }
  return assert(ok, "two concatenated READY frames parse sequentially with consumed counts");
}

fn t6() -> TestResult {
  var ok = true;
  var r1 = cql_reader_new(hb("0400000001"));
  if !err_is_frame(cql_read_frame(&mut r1), "cassandra: truncated input at offset 0") { ok = false; }
  var r2 = cql_reader_new(hb("050000000100000000"));
  if !err_is_frame(cql_read_frame(&mut r2), "cassandra: unsupported protocol version 5 at offset 0") { ok = false; }
  var r3 = cql_reader_new(hb("0400000001FFFFFFFF"));
  if !err_is_frame(cql_read_frame(&mut r3), "cassandra: bad length -1 at offset 5") { ok = false; }
  var r4 = cql_reader_new(hb("040000000100000004AABB"));
  if !err_is_frame(cql_read_frame(&mut r4), "cassandra: truncated body at offset 9: need 4 bytes, have 2") { ok = false; }
  var r5 = cql_reader_new(hb("040000007F00000000"));
  let fr5 = cql_read_frame(&mut r5);
  if !fr5.is_ok { ok = false; } else {
    let f: CqlFrame = fr5.value;
    if cql_frame_opcode(&f) != 127 { ok = false; }
    if cql_opcode_known(cql_frame_opcode(&f)) { ok = false; }
    if !str_is(cql_opcode_name(cql_frame_opcode(&f)), "UNKNOWN") { ok = false; }
  }
  var r6 = cql_reader_new(hb("042000000100000000"));
  let fr6 = cql_read_frame(&mut r6);
  if !fr6.is_ok { ok = false; } else {
    let f: CqlFrame = fr6.value;
    if cql_frame_flags(&f) != 32 { ok = false; }
    if cql_flags_known(cql_frame_flags(&f)) { ok = false; }
  }
  var r7 = cql_reader_new(hb("830000000200000000"));
  let fr7 = cql_read_frame(&mut r7);
  if !fr7.is_ok { ok = false; } else {
    let f: CqlFrame = fr7.value;
    if cql_frame_version(&f) != cql_version_response_v3() { ok = false; }
    if cql_version_protocol(cql_frame_version(&f)) != 3 { ok = false; }
    if !cql_frame_is_response(&f) { ok = false; }
  }
  var r8 = cql_reader_new(hb("0400FFFF0100000000"));
  let fr8 = cql_read_frame(&mut r8);
  if !fr8.is_ok { ok = false; } else {
    let f: CqlFrame = fr8.value;
    if cql_frame_stream(&f) != -1 { ok = false; }
  }
  return assert(ok, "truncated, bad-version, bad-length and overrun frames are rejected; unknown opcodes/flags preserved");
}

fn t7() -> TestResult {
  var ok = true;
  var w = cql_writer_new();
  cql_write_int(&mut w, -2147483648);
  cql_write_int(&mut w, 2147483647);
  cql_write_long(&mut w, -9223372036854775807 - 1);
  cql_write_long(&mut w, 42);
  cql_write_byte(&mut w, -128);
  cql_write_byte(&mut w, 255);
  cql_write_short(&mut w, 65535);
  cql_write_short(&mut w, 0);
  if !bytes_equal(cql_writer_bytes(&w), hb("800000007FFFFFFF8000000000000000000000000000002A80FFFFFF0000")) { ok = false; }
  var r = cql_reader_new(cql_writer_bytes(&w));
  let a1 = cql_read_int(&mut r);
  if !a1.is_ok { ok = false; } else { if a1.value != -2147483648 { ok = false; } }
  let a2 = cql_read_int(&mut r);
  if !a2.is_ok { ok = false; } else { if a2.value != 2147483647 { ok = false; } }
  let a3 = cql_read_long(&mut r);
  if !a3.is_ok { ok = false; } else { if a3.value != -9223372036854775807 - 1 { ok = false; } }
  let a4 = cql_read_long(&mut r);
  if !a4.is_ok { ok = false; } else { if a4.value != 42 { ok = false; } }
  let a5 = cql_read_byte(&mut r);
  if !a5.is_ok { ok = false; } else { if a5.value != 128 { ok = false; } }
  let a6 = cql_read_byte(&mut r);
  if !a6.is_ok { ok = false; } else { if a6.value != 255 { ok = false; } }
  let a7 = cql_read_short(&mut r);
  if !a7.is_ok { ok = false; } else { if a7.value != 65535 { ok = false; } }
  let a8 = cql_read_short(&mut r);
  if !a8.is_ok { ok = false; } else { if a8.value != 0 { ok = false; } }
  if cql_reader_remaining(&r) != 0 { ok = false; }
  var r2 = cql_reader_new(hb("0000"));
  if !err_is_i(cql_read_int(&mut r2), "cassandra: truncated input at offset 0") { ok = false; }
  return assert(ok, "int/long sign extremes, unsigned byte and short round-trip");
}

fn t8() -> TestResult {
  var ok = true;
  var w = cql_writer_new();
  cql_write_string(&mut w, "héllo");
  cql_write_string(&mut w, "");
  cql_write_long_string(&mut w, "abc");
  let b1: Vec[UInt8] = hb("00FF10");
  cql_write_bytes(&mut w, &b1);
  let sb1: Vec[UInt8] = hb("AABB");
  cql_write_short_bytes(&mut w, &sb1);
  if !bytes_equal(cql_writer_bytes(&w), hb("000668C3A96C6C6F0000000000036162630000000300FF100002AABB")) { ok = false; }
  var r = cql_reader_new(cql_writer_bytes(&w));
  let s1 = cql_read_string(&mut r);
  if !s1.is_ok { ok = false; } else { if !str_is(s1.value, "héllo") { ok = false; } }
  let s2 = cql_read_string(&mut r);
  if !s2.is_ok { ok = false; } else { if !str_is(s2.value, "") { ok = false; } }
  let s3 = cql_read_long_string(&mut r);
  if !s3.is_ok { ok = false; } else { if !str_is(s3.value, "abc") { ok = false; } }
  let s4 = cql_read_bytes(&mut r);
  if !s4.is_ok { ok = false; } else { if !bytes_equal(s4.value, hb("00FF10")) { ok = false; } }
  let s5 = cql_read_short_bytes(&mut r);
  if !s5.is_ok { ok = false; } else { if !bytes_equal(s5.value, hb("AABB")) { ok = false; } }
  if cql_reader_remaining(&r) != 0 { ok = false; }
  var rn = cql_reader_new(hb("000100"));
  if !err_is_s(cql_read_string(&mut rn), "cassandra: string contains nul") { ok = false; }
  var ru = cql_reader_new(hb("0002C328"));
  if !err_is_s(cql_read_string(&mut ru), "cassandra: invalid utf-8") { ok = false; }
  var rt = cql_reader_new(hb("00046162"));
  if !err_is_s(cql_read_string(&mut rt), "cassandra: truncated input at offset 2") { ok = false; }
  var rb = cql_reader_new(hb("FFFFFFFF"));
  if !err_is_bts(cql_read_bytes(&mut rb), "cassandra: null bytes value at offset 0") { ok = false; }
  var rl = cql_reader_new(hb("FFFFFFD6"));
  if !err_is_bts(cql_read_bytes(&mut rl), "cassandra: bad length -42 at offset 0") { ok = false; }
  var rls = cql_reader_new(hb("FFFFFFFF"));
  if !err_is_s(cql_read_long_string(&mut rls), "cassandra: bad length -1 at offset 0") { ok = false; }
  return assert(ok, "string/long string/bytes/short bytes round-trip and validation errors");
}

fn t9() -> TestResult {
  var ok = true;
  var w = cql_writer_new();
  var items = Vec[Str].new();
  items.push("a");
  items.push("bb");
  items.push("");
  let l = CqlStringList{ items: items };
  cql_write_string_list(&mut w, &l);
  var keys = Vec[Str].new();
  keys.push("k1");
  keys.push("k2");
  var vals = Vec[Str].new();
  vals.push("v1");
  vals.push("v2");
  let m = CqlStringMap{ keys: keys; values: vals };
  cql_write_string_map(&mut w, &m);
  if !bytes_equal(cql_writer_bytes(&w), hb("0003000161000262620000000200026B310002763100026B3200027632")) { ok = false; }
  var r = cql_reader_new(cql_writer_bytes(&w));
  let lr = cql_read_string_list(&mut r);
  if !lr.is_ok { ok = false; } else {
    let l2: CqlStringList = lr.value;
    if cql_string_list_len(&l2) != 3 { ok = false; }
    if !str_is(cql_string_list_get(&l2, 0), "a") { ok = false; }
    if !str_is(cql_string_list_get(&l2, 1), "bb") { ok = false; }
    if !str_is(cql_string_list_get(&l2, 2), "") { ok = false; }
    if !str_is(cql_string_list_get(&l2, 3), "") { ok = false; }
    if !str_is(cql_string_list_get(&l2, -1), "") { ok = false; }
  }
  let mr = cql_read_string_map(&mut r);
  if !mr.is_ok { ok = false; } else {
    let m2: CqlStringMap = mr.value;
    if cql_string_map_len(&m2) != 2 { ok = false; }
    if !str_is(cql_string_map_key(&m2, 1), "k2") { ok = false; }
    if !str_is(cql_string_map_value(&m2, 1), "v2") { ok = false; }
    if cql_string_map_get(&m2, "k2") != 1 { ok = false; }
    if cql_string_map_get(&m2, "zz") != -1 { ok = false; }
    if !str_is(cql_string_map_key(&m2, 7), "") { ok = false; }
    if !str_is(cql_string_map_value(&m2, -3), "") { ok = false; }
  }
  if cql_reader_remaining(&r) != 0 { ok = false; }
  var ro = cql_reader_new(hb("FFFF00"));
  if !err_is_sl(cql_read_string_list(&mut ro), "cassandra: oversized collection at offset 0") { ok = false; }
  var rt = cql_reader_new(hb("000100046162"));
  if !err_is_sl(cql_read_string_list(&mut rt), "cassandra: truncated input at offset 4") { ok = false; }
  return assert(ok, "string list and string map round-trip plus oversized/truncated guards");
}

fn t10() -> TestResult {
  var ok = true;
  var w = cql_writer_new();
  var keys = Vec[Str].new();
  keys.push("a");
  keys.push("b");
  var vals = Vec[Str].new();
  vals.push("v1");
  vals.push("v2");
  vals.push("w");
  var offs = Vec[Int].new();
  offs.push(0);
  offs.push(2);
  offs.push(3);
  let mm = CqlStringMultiMap{ keys: keys; values: vals; offsets: offs };
  cql_write_string_multimap(&mut w, &mm);
  var bkeys = Vec[Str].new();
  bkeys.push("x");
  var bvals = Vec[Vec[UInt8]].new();
  let bv1: Vec[UInt8] = hb("0102");
  bvals.push(bv1);
  let bm = CqlBytesMap{ keys: bkeys; values: bvals };
  cql_write_bytes_map(&mut w, &bm);
  var r = cql_reader_new(cql_writer_bytes(&w));
  let mr = cql_read_string_multimap(&mut r);
  if !mr.is_ok { ok = false; } else {
    let m2: CqlStringMultiMap = mr.value;
    if cql_string_multimap_len(&m2) != 2 { ok = false; }
    if !str_is(cql_string_multimap_key(&m2, 0), "a") { ok = false; }
    if cql_string_multimap_value_count(&m2, 0) != 2 { ok = false; }
    if cql_string_multimap_value_count(&m2, 1) != 1 { ok = false; }
    if cql_string_multimap_value_count(&m2, 9) != 0 { ok = false; }
    if !str_is(cql_string_multimap_value(&m2, 0, 0), "v1") { ok = false; }
    if !str_is(cql_string_multimap_value(&m2, 0, 1), "v2") { ok = false; }
    if !str_is(cql_string_multimap_value(&m2, 1, 0), "w") { ok = false; }
    if !str_is(cql_string_multimap_value(&m2, 1, 1), "") { ok = false; }
    if !str_is(cql_string_multimap_key(&m2, 7), "") { ok = false; }
  }
  let br = cql_read_bytes_map(&mut r);
  if !br.is_ok { ok = false; } else {
    let b2: CqlBytesMap = br.value;
    if cql_bytes_map_len(&b2) != 1 { ok = false; }
    if !str_is(cql_bytes_map_key(&b2, 0), "x") { ok = false; }
    if !bytes_equal(cql_bytes_map_value(&b2, 0), hb("0102")) { ok = false; }
    if !str_is(cql_bytes_map_key(&b2, 4), "") { ok = false; }
    if cql_bytes_map_value(&b2, 4).len() != 0 { ok = false; }
  }
  if cql_reader_remaining(&r) != 0 { ok = false; }
  var ro = cql_reader_new(hb("FFFF"));
  if !err_is_mm(cql_read_string_multimap(&mut ro), "cassandra: oversized collection at offset 0") { ok = false; }
  var ro2 = cql_reader_new(hb("FFFF"));
  if !err_is_bm(cql_read_bytes_map(&mut ro2), "cassandra: oversized collection at offset 0") { ok = false; }
  return assert(ok, "string multimap and bytes map round-trip in the flat model");
}

fn t11() -> TestResult {
  var ok = true;
  var r1 = cql_reader_new(hb("FFFFFFFF"));
  let v1 = cql_read_value(&mut r1);
  if !v1.is_ok { ok = false; } else {
    let v: CqlValue = v1.value;
    if cql_value_kind(&v) != cql_value_kind_null() { ok = false; }
    if !cql_value_is_null(&v) { ok = false; }
    if cql_value_data(&v).len() != 0 { ok = false; }
  }
  var r2 = cql_reader_new(hb("FFFFFFFE"));
  let v2 = cql_read_value(&mut r2);
  if !v2.is_ok { ok = false; } else {
    let v: CqlValue = v2.value;
    if cql_value_kind(&v) != cql_value_kind_not_set() { ok = false; }
    if !cql_value_is_not_set(&v) { ok = false; }
  }
  var r3 = cql_reader_new(hb("00000002AABB"));
  let v3 = cql_read_value(&mut r3);
  if !v3.is_ok { ok = false; } else {
    let v: CqlValue = v3.value;
    if cql_value_kind(&v) != cql_value_kind_bytes() { ok = false; }
    if !cql_value_is_bytes(&v) { ok = false; }
    if !bytes_equal(cql_value_data(&v), hb("AABB")) { ok = false; }
  }
  var r4 = cql_reader_new(hb("FFFFFFFD"));
  if !err_is_val(cql_read_value(&mut r4), "cassandra: bad length -3 at offset 0") { ok = false; }
  var w = cql_writer_new();
  let e = Vec[UInt8].new();
  cql_write_value(&mut w, 1, &e);
  cql_write_value(&mut w, 2, &e);
  let p: Vec[UInt8] = hb("AA");
  cql_write_value(&mut w, 0, &p);
  if !bytes_equal(cql_writer_bytes(&w), hb("FFFFFFFFFFFFFFFE00000001AA")) { ok = false; }
  return assert(ok, "value null (-1) / not-set (-2) / bytes semantics and encoding");
}

fn t12() -> TestResult {
  var ok = true;
  var w = cql_writer_new();
  let q = mkq("SELECT * FROM t", 1, 0, 0, Vec[UInt8].new(), 0, 0, Vec[Str].new(), Vec[Int].new(), Vec[Vec[UInt8]].new());
  let wr = cql_write_query(&mut w, &q);
  if !wr.is_ok { ok = false; }
  if !bytes_equal(cql_writer_bytes(&w), hb("0000000F53454C454354202A2046524F4D2074000100")) { ok = false; }
  var r = cql_reader_new(cql_writer_bytes(&w));
  let qr = cql_read_query(&mut r);
  if !qr.is_ok { ok = false; } else {
    let q2: CqlQuery = qr.value;
    if !str_is(cql_query_text(&q2), "SELECT * FROM t") { ok = false; }
    if cql_query_consistency(&q2) != 1 { ok = false; }
    if cql_query_flags(&q2) != 0 { ok = false; }
    if q2.has_values { ok = false; }
    if cql_query_value_count(&q2) != 0 { ok = false; }
    if !cql_consistency_known(cql_query_consistency(&q2)) { ok = false; }
    if !str_is(cql_consistency_name(cql_query_consistency(&q2)), "ONE") { ok = false; }
  }
  if cql_reader_remaining(&r) != 0 { ok = false; }
  var w2 = cql_writer_new();
  let q3 = mkq("", 0, 0, 0, Vec[UInt8].new(), 0, 0, Vec[Str].new(), Vec[Int].new(), Vec[Vec[UInt8]].new());
  let wr3 = cql_write_query(&mut w2, &q3);
  if !wr3.is_ok { ok = false; }
  if !bytes_equal(cql_writer_bytes(&w2), hb("00000000000000")) { ok = false; }
  return assert(ok, "QUERY body with no flags round-trips and matches exact bytes");
}

fn t13() -> TestResult {
  var ok = true;
  // Positional values: one byte payload and one null.
  let flags_v = cql_query_flag_values();
  var names0 = Vec[Str].new();
  names0.push("");
  names0.push("");
  var kinds0 = Vec[Int].new();
  kinds0.push(0);
  kinds0.push(1);
  var vals0 = Vec[Vec[UInt8]].new();
  let p0: Vec[UInt8] = hb("AA");
  let e0 = Vec[UInt8].new();
  vals0.push(p0);
  vals0.push(e0);
  var w = cql_writer_new();
  let q = mkq("Q1", 4, flags_v, 0, Vec[UInt8].new(), 0, 0, names0, kinds0, vals0);
  let wr = cql_write_query(&mut w, &q);
  if !wr.is_ok { ok = false; }
  var r = cql_reader_new(cql_writer_bytes(&w));
  let qr = cql_read_query(&mut r);
  if !qr.is_ok { ok = false; } else {
    let q2: CqlQuery = qr.value;
    if !q2.has_values { ok = false; }
    if cql_query_value_count(&q2) != 2 { ok = false; }
    if !str_is(cql_query_value_name(&q2, 0), "") { ok = false; }
    if cql_query_value_kind(&q2, 0) != 0 { ok = false; }
    if cql_query_value_kind(&q2, 1) != 1 { ok = false; }
    if !bytes_equal(cql_query_value_data(&q2, 0), hb("AA")) { ok = false; }
    if cql_query_value_data(&q2, 1).len() != 0 { ok = false; }
    if !str_is(cql_query_value_name(&q2, 9), "") { ok = false; }
    if cql_query_value_kind(&q2, -1) != -1 { ok = false; }
    if cql_query_value_data(&q2, 9).len() != 0 { ok = false; }
  }
  if cql_reader_remaining(&r) != 0 { ok = false; }
  // Named values with a not-set entry.
  let flags_n = cql_query_flag_values() + cql_query_flag_names_for_values();
  var names1 = Vec[Str].new();
  names1.push("a");
  names1.push("b");
  var kinds1 = Vec[Int].new();
  kinds1.push(0);
  kinds1.push(2);
  var vals1 = Vec[Vec[UInt8]].new();
  let p1: Vec[UInt8] = hb("01");
  let e1 = Vec[UInt8].new();
  vals1.push(p1);
  vals1.push(e1);
  var w2 = cql_writer_new();
  let q4 = mkq("Q2", 8, flags_n, 0, Vec[UInt8].new(), 0, 0, names1, kinds1, vals1);
  let wr2 = cql_write_query(&mut w2, &q4);
  if !wr2.is_ok { ok = false; }
  var r2 = cql_reader_new(cql_writer_bytes(&w2));
  let qr2 = cql_read_query(&mut r2);
  if !qr2.is_ok { ok = false; } else {
    let q5: CqlQuery = qr2.value;
    if cql_query_value_count(&q5) != 2 { ok = false; }
    if !str_is(cql_query_value_name(&q5, 0), "a") { ok = false; }
    if !str_is(cql_query_value_name(&q5, 1), "b") { ok = false; }
    if cql_query_value_kind(&q5, 1) != 2 { ok = false; }
    if !bytes_equal(cql_query_value_data(&q5, 0), hb("01")) { ok = false; }
    if !cql_consistency_known(cql_query_consistency(&q5)) { ok = false; }
  }
  return assert(ok, "QUERY positional and named value sections round-trip");
}

fn t14() -> TestResult {
  var ok = true;
  // Page size only.
  var w1 = cql_writer_new();
  let q1 = mkq("P", 1, cql_query_flag_page_size(), 500, Vec[UInt8].new(), 0, 0, Vec[Str].new(), Vec[Int].new(), Vec[Vec[UInt8]].new());
  let w1r = cql_write_query(&mut w1, &q1);
  if !w1r.is_ok { ok = false; }
  var r1 = cql_reader_new(cql_writer_bytes(&w1));
  let q1r = cql_read_query(&mut r1);
  if !q1r.is_ok { ok = false; } else {
    let p: CqlQuery = q1r.value;
    if !p.has_page_size { ok = false; }
    if p.page_size != 500 { ok = false; }
    if p.has_paging_state { ok = false; }
    if p.has_serial_consistency { ok = false; }
    if p.has_timestamp { ok = false; }
  }
  // Paging state only.
  let ps: Vec[UInt8] = hb("DEADBEEF");
  var w2 = cql_writer_new();
  let q2 = mkq("P", 1, cql_query_flag_paging_state(), 0, ps, 0, 0, Vec[Str].new(), Vec[Int].new(), Vec[Vec[UInt8]].new());
  let w2r = cql_write_query(&mut w2, &q2);
  if !w2r.is_ok { ok = false; }
  var r2 = cql_reader_new(cql_writer_bytes(&w2));
  let q2r = cql_read_query(&mut r2);
  if !q2r.is_ok { ok = false; } else {
    let p: CqlQuery = q2r.value;
    if !p.has_paging_state { ok = false; }
    if !bytes_equal(p.paging_state, hb("DEADBEEF")) { ok = false; }
  }
  // Serial consistency only.
  var w3 = cql_writer_new();
  let q3 = mkq("P", 1, cql_query_flag_serial_consistency(), 0, Vec[UInt8].new(), 9, 0, Vec[Str].new(), Vec[Int].new(), Vec[Vec[UInt8]].new());
  let w3r = cql_write_query(&mut w3, &q3);
  if !w3r.is_ok { ok = false; }
  var r3 = cql_reader_new(cql_writer_bytes(&w3));
  let q3r = cql_read_query(&mut r3);
  if !q3r.is_ok { ok = false; } else {
    let p: CqlQuery = q3r.value;
    if !p.has_serial_consistency { ok = false; }
    if p.serial_consistency != 9 { ok = false; }
    if !str_is(cql_consistency_name(p.serial_consistency), "LOCAL_SERIAL") { ok = false; }
  }
  // Timestamp only.
  var w4 = cql_writer_new();
  let q4 = mkq("P", 1, cql_query_flag_default_timestamp(), 0, Vec[UInt8].new(), 0, 1234567890123, Vec[Str].new(), Vec[Int].new(), Vec[Vec[UInt8]].new());
  let w4r = cql_write_query(&mut w4, &q4);
  if !w4r.is_ok { ok = false; }
  var r4 = cql_reader_new(cql_writer_bytes(&w4));
  let q4r = cql_read_query(&mut r4);
  if !q4r.is_ok { ok = false; } else {
    let p: CqlQuery = q4r.value;
    if !p.has_timestamp { ok = false; }
    if p.timestamp != 1234567890123 { ok = false; }
  }
  // All optional sections together, with one named value.
  let all_flags = cql_query_flag_values() + cql_query_flag_page_size() + cql_query_flag_paging_state() + cql_query_flag_serial_consistency() + cql_query_flag_default_timestamp() + cql_query_flag_names_for_values();
  var names = Vec[Str].new();
  names.push("v1");
  var kinds = Vec[Int].new();
  kinds.push(0);
  var vals = Vec[Vec[UInt8]].new();
  let pv: Vec[UInt8] = hb("CAFE");
  vals.push(pv);
  var w5 = cql_writer_new();
  let pstate: Vec[UInt8] = hb("AA");
  let q5 = mkq("INSERT", 5, all_flags, 1000, pstate, 8, 99, names, kinds, vals);
  let w5r = cql_write_query(&mut w5, &q5);
  if !w5r.is_ok { ok = false; }
  var r5 = cql_reader_new(cql_writer_bytes(&w5));
  let q5r = cql_read_query(&mut r5);
  if !q5r.is_ok { ok = false; } else {
    let p: CqlQuery = q5r.value;
    if !str_is(cql_query_text(&p), "INSERT") { ok = false; }
    if cql_query_consistency(&p) != 5 { ok = false; }
    if cql_query_flags(&p) != all_flags { ok = false; }
    if !p.has_page_size { ok = false; }
    if p.page_size != 1000 { ok = false; }
    if !bytes_equal(p.paging_state, hb("AA")) { ok = false; }
    if p.serial_consistency != 8 { ok = false; }
    if p.timestamp != 99 { ok = false; }
    if cql_query_value_count(&p) != 1 { ok = false; }
    if !str_is(cql_query_value_name(&p, 0), "v1") { ok = false; }
    if !bytes_equal(cql_query_value_data(&p, 0), hb("CAFE")) { ok = false; }
  }
  if cql_reader_remaining(&r5) != 0 { ok = false; }
  return assert(ok, "QUERY page size, paging state, serial consistency, timestamp and combined sections");
}

fn t15() -> TestResult {
  var ok = true;
  // Unknown v5 keyspace flag bit is preserved raw.
  var r1 = cql_reader_new(hb("00000000000180"));
  let q1 = cql_read_query(&mut r1);
  if !q1.is_ok { ok = false; } else {
    let p: CqlQuery = q1.value;
    if cql_query_flags(&p) != 128 { ok = false; }
    if cql_query_flags_known(cql_query_flags(&p)) { ok = false; }
    if p.has_values { ok = false; }
  }
  // Unknown consistency value is preserved raw.
  var r2 = cql_reader_new(hb("00000000000B00"));
  let q2 = cql_read_query(&mut r2);
  if !q2.is_ok { ok = false; } else {
    let p: CqlQuery = q2.value;
    if cql_query_consistency(&p) != 11 { ok = false; }
    if cql_consistency_known(cql_query_consistency(&p)) { ok = false; }
    if !str_is(cql_consistency_name(cql_query_consistency(&p)), "UNKNOWN") { ok = false; }
  }
  // Value length below -2 is a bad length.
  var r3 = cql_reader_new(hb("000000000001010001FFFFFFFD"));
  if !err_is_q(cql_read_query(&mut r3), "cassandra: bad length -3 at offset 9") { ok = false; }
  // A hostile value count cannot fit the remaining bytes.
  var r4 = cql_reader_new(hb("00000000000101FFFF"));
  if !err_is_q(cql_read_query(&mut r4), "cassandra: oversized collection at offset 7") { ok = false; }
  // Truncated query text.
  var r5 = cql_reader_new(hb("00000010"));
  if !err_is_q(cql_read_query(&mut r5), "cassandra: truncated input at offset 4") { ok = false; }
  return assert(ok, "QUERY reader preserves unknown flags/consistency and rejects bad lengths and oversized counts");
}

fn t16() -> TestResult {
  var ok = true;
  var w = cql_writer_new();
  if !err_is_b(cql_write_query(&mut w, &mkq_bad_page()), "cassandra: query page size flag mismatch") { ok = false; }
  var w2 = cql_writer_new();
  if !err_is_b(cql_write_query(&mut w2, &mkq_bad_count()), "cassandra: query value count mismatch") { ok = false; }
  return assert(ok, "QUERY writer rejects flag/field and value-count mismatches");
}

fn t17() -> TestResult {
  var ok = true;
  var w = cql_writer_new();
  cql_write_int(&mut w, 1);
  var r = cql_reader_new(cql_writer_bytes(&w));
  let vr = cql_read_result_body(&mut r);
  if !vr.is_ok { ok = false; } else {
    let res: CqlResult = vr.value;
    if cql_result_kind(&res) != cql_result_void() { ok = false; }
    if cql_result_rows_count(&res) != 0 { ok = false; }
    if cql_result_cell_count(&res) != 0 { ok = false; }
    if cql_result_cell_kind(&res, 0) != -1 { ok = false; }
    if cql_result_cell(&res, 0).len() != 0 { ok = false; }
    if !str_is(cql_result_column_name(&res, 0), "") { ok = false; }
    if !str_is(cql_result_keyspace(&res), "") { ok = false; }
    if cql_result_result_column_count(&res) != 0 { ok = false; }
    if !str_is(cql_result_schema_change_arg(&res, 0), "") { ok = false; }
    if !str_is(cql_result_schema_change_target(&res), "") { ok = false; }
  }
  var w2 = cql_writer_new();
  cql_write_int(&mut w2, 3);
  cql_write_string(&mut w2, "my_ks");
  var r2 = cql_reader_new(cql_writer_bytes(&w2));
  let sr = cql_read_result_body(&mut r2);
  if !sr.is_ok { ok = false; } else {
    let res: CqlResult = sr.value;
    if cql_result_kind(&res) != cql_result_set_keyspace() { ok = false; }
    if !str_is(cql_result_keyspace(&res), "my_ks") { ok = false; }
  }
  var r3 = cql_reader_new(hb("00000006"));
  if !err_is_res(cql_read_result_body(&mut r3), "cassandra: unknown result kind 6 at offset 0") { ok = false; }
  var r4 = cql_reader_new(hb("00"));
  if !err_is_res(cql_read_result_body(&mut r4), "cassandra: truncated input at offset 0") { ok = false; }
  return assert(ok, "RESULT VOID and SET_KEYSPACE decode; unknown kinds are rejected");
}

fn t18() -> TestResult {
  var ok = true;
  var w = cql_writer_new();
  cql_write_int(&mut w, 2);
  var names = Vec[Str].new();
  names.push("c1");
  names.push("c2");
  var codes = Vec[Int].new();
  codes.push(cql_type_int());
  codes.push(cql_type_varchar());
  w_meta_global(&mut w, "ks", "tbl", names, codes);
  cql_write_int(&mut w, 2);
  let c1a: Vec[UInt8] = hb("0000002A");
  cql_write_value(&mut w, 0, &c1a);
  let c2a: Vec[UInt8] = hb("6869");
  cql_write_value(&mut w, 0, &c2a);
  let empty = Vec[UInt8].new();
  cql_write_value(&mut w, 1, &empty);
  let c2b: Vec[UInt8] = hb("796F");
  cql_write_value(&mut w, 0, &c2b);
  var r = cql_reader_new(cql_writer_bytes(&w));
  let rr = cql_read_result_body(&mut r);
  if !rr.is_ok { ok = false; } else {
    let res: CqlResult = rr.value;
    if cql_result_kind(&res) != cql_result_rows() { ok = false; }
    if cql_result_column_count(&res) != 2 { ok = false; }
    if cql_result_no_metadata(&res) { ok = false; }
    if !str_is(cql_result_column_name(&res, 0), "c1") { ok = false; }
    if !str_is(cql_result_column_name(&res, 1), "c2") { ok = false; }
    if !str_is(cql_result_column_type_name(&res, 0), "int") { ok = false; }
    if !str_is(cql_result_column_type_name(&res, 1), "varchar") { ok = false; }
    if cql_result_rows_count(&res) != 2 { ok = false; }
    if cql_result_cell_count(&res) != 4 { ok = false; }
    if cql_result_cell_kind(&res, 0) != 0 { ok = false; }
    if !bytes_equal(cql_result_cell(&res, 0), hb("0000002A")) { ok = false; }
    if !bytes_equal(cql_result_cell(&res, 1), hb("6869")) { ok = false; }
    if cql_result_cell_kind(&res, 2) != 1 { ok = false; }
    if cql_result_cell(&res, 2).len() != 0 { ok = false; }
    if !bytes_equal(cql_result_cell(&res, 3), hb("796F")) { ok = false; }
    if cql_result_cell_kind(&res, 9) != -1 { ok = false; }
  }
  if cql_reader_remaining(&r) != 0 { ok = false; }
  return assert(ok, "RESULT ROWS with global tables spec, bytes and null cells");
}

fn t19() -> TestResult {
  var ok = true;
  // Plain per-column metadata.
  var w = cql_writer_new();
  cql_write_int(&mut w, 0);
  cql_write_int(&mut w, 1);
  cql_write_string(&mut w, "ks2");
  cql_write_string(&mut w, "tbl2");
  cql_write_string(&mut w, "n");
  cql_write_short(&mut w, cql_type_ascii());
  var r = cql_reader_new(cql_writer_bytes(&w));
  let mr = cql_read_rows_metadata(&mut r);
  if !mr.is_ok { ok = false; } else {
    let m: CqlRowsMetadata = mr.value;
    if cql_meta_flags(&m) != 0 { ok = false; }
    if cql_meta_column_count(&m) != 1 { ok = false; }
    if cql_meta_global_tables_spec(&m) { ok = false; }
    if cql_meta_no_metadata(&m) { ok = false; }
    if !str_is(cql_meta_column_keyspace(&m, 0), "ks2") { ok = false; }
    if !str_is(cql_meta_column_table(&m, 0), "tbl2") { ok = false; }
    if !str_is(cql_meta_column_name(&m, 0), "n") { ok = false; }
    if cql_meta_column_type_code(&m, 0) != cql_type_ascii() { ok = false; }
    if !str_is(cql_meta_column_type_name(&m, 0), "ascii") { ok = false; }
    if !str_is(cql_meta_column_name(&m, 5), "") { ok = false; }
    if cql_meta_column_type_code(&m, 5) != -1 { ok = false; }
  }
  if cql_reader_remaining(&r) != 0 { ok = false; }
  // NO_METADATA keeps only the count.
  var w2 = cql_writer_new();
  cql_write_int(&mut w2, 4);
  cql_write_int(&mut w2, 3);
  var r2 = cql_reader_new(cql_writer_bytes(&w2));
  let mr2 = cql_read_rows_metadata(&mut r2);
  if !mr2.is_ok { ok = false; } else {
    let m: CqlRowsMetadata = mr2.value;
    if !cql_meta_no_metadata(&m) { ok = false; }
    if cql_meta_column_count(&m) != 3 { ok = false; }
    if cql_meta_column_name(&m, 0).len() != 0 { ok = false; }
  }
  // HAS_MORE_PAGES with a paging state.
  var w3 = cql_writer_new();
  cql_write_int(&mut w3, 2);
  cql_write_int(&mut w3, 0);
  let ps: Vec[UInt8] = hb("CAFE");
  cql_write_bytes(&mut w3, &ps);
  var r3 = cql_reader_new(cql_writer_bytes(&w3));
  let mr3 = cql_read_rows_metadata(&mut r3);
  if !mr3.is_ok { ok = false; } else {
    let m: CqlRowsMetadata = mr3.value;
    if !cql_meta_has_more_pages(&m) { ok = false; }
    if !cql_meta_has_paging_state(&m) { ok = false; }
    if !bytes_equal(cql_meta_paging_state(&m), hb("CAFE")) { ok = false; }
  }
  // Metadata errors.
  var e1 = cql_reader_new(hb("FFFFFFFF00000000"));
  if !err_is_meta(cql_read_rows_metadata(&mut e1), "cassandra: bad metadata flags -1 at offset 0") { ok = false; }
  var e2 = cql_reader_new(hb("00000000FFFFFFFE"));
  if !err_is_meta(cql_read_rows_metadata(&mut e2), "cassandra: bad column count -2 at offset 4") { ok = false; }
  var e3 = cql_reader_new(hb("0000000200000000FFFFFFFF"));
  if !err_is_meta(cql_read_rows_metadata(&mut e3), "cassandra: null bytes value at offset 8") { ok = false; }
  var e4 = cql_reader_new(hb("00000000000003E8"));
  if !err_is_meta(cql_read_rows_metadata(&mut e4), "cassandra: oversized collection at offset 8") { ok = false; }
  var e5 = cql_reader_new(hb("00000000"));
  if !err_is_meta(cql_read_rows_metadata(&mut e5), "cassandra: truncated input at offset 4") { ok = false; }
  return assert(ok, "ROWS metadata variants (plain, NO_METADATA, HAS_MORE_PAGES) and metadata errors");
}

fn t20() -> TestResult {
  var ok = true;
  var w = cql_writer_new();
  cql_write_short(&mut w, cql_type_int());
  cql_write_short(&mut w, cql_type_list());
  cql_write_short(&mut w, cql_type_varchar());
  cql_write_short(&mut w, cql_type_map());
  cql_write_short(&mut w, cql_type_varchar());
  cql_write_short(&mut w, cql_type_int());
  cql_write_short(&mut w, cql_type_set());
  cql_write_short(&mut w, cql_type_uuid());
  cql_write_short(&mut w, cql_type_custom());
  cql_write_string(&mut w, "com.example.T");
  cql_write_short(&mut w, cql_type_tuple());
  cql_write_short(&mut w, 2);
  cql_write_short(&mut w, cql_type_int());
  cql_write_short(&mut w, cql_type_varchar());
  cql_write_short(&mut w, cql_type_udt());
  cql_write_string(&mut w, "ks");
  cql_write_string(&mut w, "addr");
  cql_write_short(&mut w, 2);
  cql_write_string(&mut w, "street");
  cql_write_short(&mut w, cql_type_int());
  cql_write_string(&mut w, "zip");
  cql_write_short(&mut w, cql_type_varchar());
  cql_write_short(&mut w, cql_type_list());
  cql_write_short(&mut w, cql_type_list());
  cql_write_short(&mut w, cql_type_int());
  var r = cql_reader_new(cql_writer_bytes(&w));
  let t1r = cql_read_type(&mut r);
  if !t1r.is_ok { ok = false; } else {
    let t: CqlTypeInfo = t1r.value;
    if cql_type_info_code(&t) != 9 { ok = false; }
    if !str_is(cql_type_info_display(&t), "int") { ok = false; }
  }
  let t2r = cql_read_type(&mut r);
  if !t2r.is_ok { ok = false; } else {
    let t: CqlTypeInfo = t2r.value;
    if cql_type_info_code(&t) != 32 { ok = false; }
    if !str_is(cql_type_info_display(&t), "list<varchar>") { ok = false; }
  }
  let t3r = cql_read_type(&mut r);
  if !t3r.is_ok { ok = false; } else {
    let t: CqlTypeInfo = t3r.value;
    if cql_type_info_code(&t) != 33 { ok = false; }
    if !str_is(cql_type_info_display(&t), "map<varchar, int>") { ok = false; }
  }
  let t4r = cql_read_type(&mut r);
  if !t4r.is_ok { ok = false; } else {
    let t: CqlTypeInfo = t4r.value;
    if cql_type_info_code(&t) != 34 { ok = false; }
    if !str_is(cql_type_info_display(&t), "set<uuid>") { ok = false; }
  }
  let t5r = cql_read_type(&mut r);
  if !t5r.is_ok { ok = false; } else {
    let t: CqlTypeInfo = t5r.value;
    if cql_type_info_code(&t) != 0 { ok = false; }
    if !str_is(cql_type_info_display(&t), "custom(com.example.T)") { ok = false; }
  }
  let t6r = cql_read_type(&mut r);
  if !t6r.is_ok { ok = false; } else {
    let t: CqlTypeInfo = t6r.value;
    if cql_type_info_code(&t) != 49 { ok = false; }
    if !str_is(cql_type_info_display(&t), "tuple<int, varchar>") { ok = false; }
  }
  let t7r = cql_read_type(&mut r);
  if !t7r.is_ok { ok = false; } else {
    let t: CqlTypeInfo = t7r.value;
    if cql_type_info_code(&t) != 48 { ok = false; }
    if !str_is(cql_type_info_display(&t), "udt(ks.addr)") { ok = false; }
  }
  let t8r = cql_read_type(&mut r);
  if !t8r.is_ok { ok = false; } else {
    let t: CqlTypeInfo = t8r.value;
    if cql_type_info_code(&t) != 32 { ok = false; }
    if !str_is(cql_type_info_display(&t), "list<list<int>>") { ok = false; }
  }
  if cql_reader_remaining(&r) != 0 { ok = false; }
  var u = cql_reader_new(hb("00FF"));
  if !err_is_ti(cql_read_type(&mut u), "cassandra: unknown type option 255 at offset 0") { ok = false; }
  var tr = cql_reader_new(hb("00"));
  if !err_is_ti(cql_read_type(&mut tr), "cassandra: truncated input at offset 0") { ok = false; }
  let deep_hex = string.str_repeat("0020", 33) + "0009";
  var dr = cql_reader_new(hb(deep_hex));
  if !err_is_ti(cql_read_type(&mut dr), "cassandra: type nesting depth exceeds limit of 32") { ok = false; }
  return assert(ok, "type options: simple, list, map, set, custom, tuple, udt, nested, unknown, depth cap");
}

fn t21() -> TestResult {
  var ok = true;
  var w = cql_writer_new();
  cql_write_int(&mut w, 4);
  let pid: Vec[UInt8] = hb("0102030405060708");
  cql_write_short_bytes(&mut w, &pid);
  var pn = Vec[Str].new();
  pn.push("id");
  var pc = Vec[Int].new();
  pc.push(cql_type_int());
  w_meta_global(&mut w, "ks", "tbl", pn, pc);
  var rn = Vec[Str].new();
  rn.push("v");
  var rc = Vec[Int].new();
  rc.push(cql_type_varchar());
  w_meta_global(&mut w, "ks", "tbl", rn, rc);
  var r = cql_reader_new(cql_writer_bytes(&w));
  let rr = cql_read_result_body(&mut r);
  if !rr.is_ok { ok = false; } else {
    let res: CqlResult = rr.value;
    if cql_result_kind(&res) != cql_result_prepared() { ok = false; }
    if !bytes_equal(cql_result_prepared_id(&res), hb("0102030405060708")) { ok = false; }
    if cql_result_column_count(&res) != 1 { ok = false; }
    if !str_is(cql_result_column_name(&res, 0), "id") { ok = false; }
    if !str_is(cql_result_column_type_name(&res, 0), "int") { ok = false; }
    if cql_result_result_column_count(&res) != 1 { ok = false; }
    if !str_is(cql_result_result_column_name(&res, 0), "v") { ok = false; }
    if !str_is(cql_result_result_column_type_name(&res, 0), "varchar") { ok = false; }
  }
  if cql_reader_remaining(&r) != 0 { ok = false; }
  return assert(ok, "RESULT PREPARED with id, prepared metadata and result metadata");
}

fn t22() -> TestResult {
  var ok = true;
  // KEYSPACE change.
  var w = cql_writer_new();
  cql_write_int(&mut w, 5);
  cql_write_string(&mut w, "CREATED");
  cql_write_string(&mut w, "KEYSPACE");
  cql_write_string(&mut w, "ks1");
  var r = cql_reader_new(cql_writer_bytes(&w));
  let r1 = cql_read_result_body(&mut r);
  if !r1.is_ok { ok = false; } else {
    let res: CqlResult = r1.value;
    if cql_result_kind(&res) != cql_result_schema_change() { ok = false; }
    if !str_is(cql_result_schema_change_type(&res), "CREATED") { ok = false; }
    if !str_is(cql_result_schema_change_target(&res), "KEYSPACE") { ok = false; }
    if !str_is(cql_result_schema_change_keyspace(&res), "ks1") { ok = false; }
    if !str_is(cql_result_schema_change_name(&res), "") { ok = false; }
    if cql_result_schema_change_arg_count(&res) != 0 { ok = false; }
  }
  // TABLE change.
  var w2 = cql_writer_new();
  cql_write_int(&mut w2, 5);
  cql_write_string(&mut w2, "DROPPED");
  cql_write_string(&mut w2, "TABLE");
  cql_write_string(&mut w2, "ks");
  cql_write_string(&mut w2, "tbl");
  var r2 = cql_reader_new(cql_writer_bytes(&w2));
  let r2r = cql_read_result_body(&mut r2);
  if !r2r.is_ok { ok = false; } else {
    let res: CqlResult = r2r.value;
    if !str_is(cql_result_schema_change_type(&res), "DROPPED") { ok = false; }
    if !str_is(cql_result_schema_change_target(&res), "TABLE") { ok = false; }
    if !str_is(cql_result_schema_change_name(&res), "tbl") { ok = false; }
  }
  // FUNCTION change with argument types.
  var w3 = cql_writer_new();
  cql_write_int(&mut w3, 5);
  cql_write_string(&mut w3, "UPDATED");
  cql_write_string(&mut w3, "FUNCTION");
  cql_write_string(&mut w3, "ks");
  cql_write_string(&mut w3, "fn");
  var args = Vec[Str].new();
  args.push("int");
  args.push("varchar");
  let al = CqlStringList{ items: args };
  cql_write_string_list(&mut w3, &al);
  var r3 = cql_reader_new(cql_writer_bytes(&w3));
  let r3r = cql_read_result_body(&mut r3);
  if !r3r.is_ok { ok = false; } else {
    let res: CqlResult = r3r.value;
    if !str_is(cql_result_schema_change_target(&res), "FUNCTION") { ok = false; }
    if !str_is(cql_result_schema_change_name(&res), "fn") { ok = false; }
    if cql_result_schema_change_arg_count(&res) != 2 { ok = false; }
    if !str_is(cql_result_schema_change_arg(&res, 0), "int") { ok = false; }
    if !str_is(cql_result_schema_change_arg(&res, 1), "varchar") { ok = false; }
    if !str_is(cql_result_schema_change_arg(&res, 9), "") { ok = false; }
  }
  // Unknown target.
  var w4 = cql_writer_new();
  cql_write_int(&mut w4, 5);
  cql_write_string(&mut w4, "CREATED");
  cql_write_string(&mut w4, "X");
  var r4 = cql_reader_new(cql_writer_bytes(&w4));
  if !err_is_res(cql_read_result_body(&mut r4), "cassandra: unknown schema change target X at offset 13") { ok = false; }
  return assert(ok, "RESULT SCHEMA_CHANGE for KEYSPACE/TABLE/FUNCTION and unknown target");
}

// Parse an ERROR body from the bytes a writer holds.
fn parse_eb(w: &CqlWriter) -> Result[CqlErrorBody, Str] {
  var r = cql_reader_new(cql_writer_bytes(w));
  return cql_read_error_body(&mut r);
}

fn t23() -> TestResult {
  var ok = true;
  // SERVER_ERROR with message only.
  var w1 = cql_writer_new();
  cql_write_int(&mut w1, 0);
  cql_write_string(&mut w1, "boom");
  let e1r = parse_eb(&w1);
  if !e1r.is_ok { ok = false; } else {
    let e: CqlErrorBody = e1r.value;
    if cql_error_body_code(&e) != 0 { ok = false; }
    if !str_is(cql_error_body_message(&e), "boom") { ok = false; }
    if cql_error_body_consistency(&e) != 0 { ok = false; }
    if cql_error_body_arg_count(&e) != 0 { ok = false; }
    if cql_error_body_prepared_id(&e).len() != 0 { ok = false; }
    if cql_error_body_data_present(&e) { ok = false; }
    if !str_is(cql_error_body_table(&e), "") { ok = false; }
    if !str_is(cql_error_body_write_type(&e), "") { ok = false; }
  }
  // UNAVAILABLE.
  var w2 = cql_writer_new();
  cql_write_int(&mut w2, 4096);
  cql_write_string(&mut w2, "unavail");
  cql_write_short(&mut w2, 4);
  cql_write_int(&mut w2, 3);
  cql_write_int(&mut w2, 2);
  let e2r = parse_eb(&w2);
  if !e2r.is_ok { ok = false; } else {
    let e: CqlErrorBody = e2r.value;
    if cql_error_body_consistency(&e) != 4 { ok = false; }
    if !str_is(cql_consistency_name(cql_error_body_consistency(&e)), "QUORUM") { ok = false; }
    if cql_error_body_required(&e) != 3 { ok = false; }
    if cql_error_body_alive(&e) != 2 { ok = false; }
  }
  // WRITE_TIMEOUT.
  var w3 = cql_writer_new();
  cql_write_int(&mut w3, 4352);
  cql_write_string(&mut w3, "wt");
  cql_write_short(&mut w3, 1);
  cql_write_int(&mut w3, 2);
  cql_write_int(&mut w3, 3);
  cql_write_string(&mut w3, "SIMPLE");
  let e3r = parse_eb(&w3);
  if !e3r.is_ok { ok = false; } else {
    let e: CqlErrorBody = e3r.value;
    if cql_error_body_received(&e) != 2 { ok = false; }
    if cql_error_body_blockfor(&e) != 3 { ok = false; }
    if !str_is(cql_error_body_write_type(&e), "SIMPLE") { ok = false; }
  }
  // READ_TIMEOUT with data present.
  var w4 = cql_writer_new();
  cql_write_int(&mut w4, 4608);
  cql_write_string(&mut w4, "rt");
  cql_write_short(&mut w4, 5);
  cql_write_int(&mut w4, 1);
  cql_write_int(&mut w4, 2);
  cql_write_byte(&mut w4, 1);
  let e4r = parse_eb(&w4);
  if !e4r.is_ok { ok = false; } else {
    let e: CqlErrorBody = e4r.value;
    if cql_error_body_received(&e) != 1 { ok = false; }
    if cql_error_body_blockfor(&e) != 2 { ok = false; }
    if !cql_error_body_data_present(&e) { ok = false; }
  }
  // READ_FAILURE.
  var w5 = cql_writer_new();
  cql_write_int(&mut w5, 4864);
  cql_write_string(&mut w5, "rf");
  cql_write_short(&mut w5, 4);
  cql_write_int(&mut w5, 2);
  cql_write_int(&mut w5, 3);
  cql_write_int(&mut w5, 1);
  cql_write_byte(&mut w5, 0);
  let e5r = parse_eb(&w5);
  if !e5r.is_ok { ok = false; } else {
    let e: CqlErrorBody = e5r.value;
    if cql_error_body_num_failures(&e) != 1 { ok = false; }
    if cql_error_body_data_present(&e) { ok = false; }
  }
  // FUNCTION_FAILURE.
  var w6 = cql_writer_new();
  cql_write_int(&mut w6, 5120);
  cql_write_string(&mut w6, "ff");
  cql_write_string(&mut w6, "ks");
  cql_write_string(&mut w6, "f");
  var fargs = Vec[Str].new();
  fargs.push("int");
  fargs.push("text");
  let fl = CqlStringList{ items: fargs };
  cql_write_string_list(&mut w6, &fl);
  let e6r = parse_eb(&w6);
  if !e6r.is_ok { ok = false; } else {
    let e: CqlErrorBody = e6r.value;
    if !str_is(cql_error_body_keyspace(&e), "ks") { ok = false; }
    if !str_is(cql_error_body_function(&e), "f") { ok = false; }
    if cql_error_body_arg_count(&e) != 2 { ok = false; }
    if !str_is(cql_error_body_arg(&e, 0), "int") { ok = false; }
    if !str_is(cql_error_body_arg(&e, 1), "text") { ok = false; }
    if !str_is(cql_error_body_arg(&e, 9), "") { ok = false; }
  }
  // WRITE_FAILURE.
  var w7 = cql_writer_new();
  cql_write_int(&mut w7, 5376);
  cql_write_string(&mut w7, "wf");
  cql_write_short(&mut w7, 4);
  cql_write_int(&mut w7, 1);
  cql_write_int(&mut w7, 2);
  cql_write_int(&mut w7, 3);
  cql_write_string(&mut w7, "BATCH");
  let e7r = parse_eb(&w7);
  if !e7r.is_ok { ok = false; } else {
    let e: CqlErrorBody = e7r.value;
    if cql_error_body_num_failures(&e) != 3 { ok = false; }
    if !str_is(cql_error_body_write_type(&e), "BATCH") { ok = false; }
  }
  // ALREADY_EXISTS.
  var w8 = cql_writer_new();
  cql_write_int(&mut w8, 9216);
  cql_write_string(&mut w8, "ae");
  cql_write_string(&mut w8, "ks");
  cql_write_string(&mut w8, "tbl");
  let e8r = parse_eb(&w8);
  if !e8r.is_ok { ok = false; } else {
    let e: CqlErrorBody = e8r.value;
    if !str_is(cql_error_body_keyspace(&e), "ks") { ok = false; }
    if !str_is(cql_error_body_table(&e), "tbl") { ok = false; }
  }
  // UNPREPARED.
  var w9 = cql_writer_new();
  cql_write_int(&mut w9, 9472);
  cql_write_string(&mut w9, "up");
  let upid: Vec[UInt8] = hb("AABBCC");
  cql_write_short_bytes(&mut w9, &upid);
  let e9r = parse_eb(&w9);
  if !e9r.is_ok { ok = false; } else {
    let e: CqlErrorBody = e9r.value;
    if !bytes_equal(cql_error_body_prepared_id(&e), hb("AABBCC")) { ok = false; }
  }
  // Unknown code is preserved raw with no extras.
  var w10 = cql_writer_new();
  cql_write_int(&mut w10, 30583);
  cql_write_string(&mut w10, "weird");
  let e10r = parse_eb(&w10);
  if !e10r.is_ok { ok = false; } else {
    let e: CqlErrorBody = e10r.value;
    if cql_error_body_code(&e) != 30583 { ok = false; }
    if cql_error_code_known(cql_error_body_code(&e)) { ok = false; }
    if !str_is(cql_error_body_message(&e), "weird") { ok = false; }
  }
  // Truncated message length.
  var tr = cql_reader_new(hb("00000000"));
  if !err_is_eb(cql_read_error_body(&mut tr), "cassandra: truncated input at offset 4") { ok = false; }
  return assert(ok, "ERROR bodies: SERVER_ERROR, UNAVAILABLE, timeouts, failures, ALREADY_EXISTS, UNPREPARED, unknown code");
}

fn t24() -> TestResult {
  var ok = true;
  if !str_is(cql_error_code_name(10), "PROTOCOL_ERROR") { ok = false; }
  if !str_is(cql_error_code_name(256), "BAD_CREDENTIALS") { ok = false; }
  if !str_is(cql_error_code_name(4097), "OVERLOADED") { ok = false; }
  if !str_is(cql_error_code_name(4098), "IS_BOOTSTRAPPING") { ok = false; }
  if !str_is(cql_error_code_name(4099), "TRUNCATE_ERROR") { ok = false; }
  if !str_is(cql_error_code_name(4608), "READ_TIMEOUT") { ok = false; }
  if !str_is(cql_error_code_name(4864), "READ_FAILURE") { ok = false; }
  if !str_is(cql_error_code_name(5120), "FUNCTION_FAILURE") { ok = false; }
  if !str_is(cql_error_code_name(5376), "WRITE_FAILURE") { ok = false; }
  if !str_is(cql_error_code_name(8192), "SYNTAX_ERROR") { ok = false; }
  if !str_is(cql_error_code_name(8448), "UNAUTHORIZED") { ok = false; }
  if !str_is(cql_error_code_name(8960), "CONFIG_ERROR") { ok = false; }
  if !str_is(cql_error_code_name(9216), "ALREADY_EXISTS") { ok = false; }
  if !cql_error_code_known(5120) { ok = false; }
  if !cql_error_code_known(9216) { ok = false; }
  if !cql_error_code_known(256) { ok = false; }
  var r = cql_reader_new(hb("0009"));
  let tr = cql_read_type(&mut r);
  if !tr.is_ok { ok = false; } else {
    let ti: CqlTypeInfo = tr.value;
    if cql_type_info_code(&ti) != 9 { ok = false; }
    if !str_is(cql_type_info_display(&ti), "int") { ok = false; }
  }
  if cql_reader_remaining(&r) != 0 { ok = false; }
  return assert(ok, "error code name table and type-info accessor edges");
}

fn main() -> Int {
  io.println("=== xiom.cassandra conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.cassandra: all tests passed");
  } else {
    io.println("xiom.cassandra: tests failed");
  }
  return failed;
}


