// XIOM -- libpq Conformance Test Suite
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Phase 1: Verifies SPEC-layer contract signatures and stub behaviour.
// All FFI calls return Err until the C bridge is linked.

module libpq_conformance_tests

// -- Inline test helpers ----------------------------------------------------

fn assert(condition: Bool, name: Str) -> Int
  requires: name.len() > 0
{
  if condition { return 0; };
  return 1;
}

fn assert_eq_int(a: Int, b: Int, name: Str) -> Int
  requires: name.len() > 0
{
  if a == b { return 0; };
  return 1;
}

fn assert_err(is_ok: Bool, name: Str) -> Int
  requires: name.len() > 0
{
  if !is_ok { return 0; };
  return 1;
}

// -- Type-level tests -------------------------------------------------------

fn test_type_constants_defined() -> Int {
  let ok = libpq.CONNECTION_OK == 0 && libpq.CONNECTION_BAD == 1 && libpq.PGRES_EMPTY_QUERY == 0 && libpq.PGRES_COMMAND_OK == 1 && libpq.PGRES_TUPLES_OK == 2 && libpq.PGRES_FATAL_ERROR == 7;
  return assert(ok, "all connection and result status constants are correct");
}

fn test_connection_ok_is_zero() -> Int {
  return assert_eq_int(libpq.CONNECTION_OK, 0, "CONNECTION_OK equals 0");
}

fn test_connection_bad_is_one() -> Int {
  return assert_eq_int(libpq.CONNECTION_BAD, 1, "CONNECTION_BAD equals 1");
}

fn test_pgres_tuples_ok_is_two() -> Int {
  return assert_eq_int(libpq.PGRES_TUPLES_OK, 2, "PGRES_TUPLES_OK equals 2");
}

// -- Connection error-path tests --------------------------------------------

fn test_connect_returns_err_in_stub_mode() -> Int {
  let result = libpq.connect("host=localhost dbname=test user=postgres");
  return assert_err(result.is_ok, "connect returns Err in SPEC stub mode");
}

fn test_connect_with_minimal_conninfo_returns_err() -> Int {
  let result = libpq.connect("dbname=postgres");
  return assert_err(result.is_ok, "connect with minimal conninfo returns Err in stub mode");
}

fn test_close_with_nonzero_conn_is_noop() -> Int {
  libpq.close(1);
  return 0;
}

fn test_status_returns_connection_bad_in_stub_mode() -> Int {
  let s = libpq.status(1);
  return assert_eq_int(s, libpq.CONNECTION_BAD, "status returns CONNECTION_BAD in stub mode");
}

fn test_error_message_returns_nonempty_str() -> Int {
  let msg = libpq.error_message(1);
  return assert(msg.len() > 0, "error_message returns non-empty string in stub mode");
}

// -- Query execution error-path tests ---------------------------------------

fn test_exec_returns_err_in_stub_mode() -> Int {
  let result = libpq.exec(1, "SELECT 1");
  return assert_err(result.is_ok, "exec returns Err in SPEC stub mode");
}

fn test_exec_with_complex_query_returns_err() -> Int {
  let result = libpq.exec(1, "SELECT id, name, email FROM users WHERE active = TRUE ORDER BY name");
  return assert_err(result.is_ok, "exec with complex query returns Err in stub mode");
}

fn test_exec_params_returns_err_in_stub_mode() -> Int {
  var params: Vec[Str] = Vec[Str].new();
  params.push("42");
  let result = libpq.exec_params(1, "SELECT $1::int", params);
  return assert_err(result.is_ok, "exec_params returns Err in SPEC stub mode");
}

fn test_exec_params_with_multiple_params_returns_err() -> Int {
  var params: Vec[Str] = Vec[Str].new();
  params.push("alice");
  params.push("active");
  let result = libpq.exec_params(1, "SELECT * FROM users WHERE name = $1 AND status = $2", params);
  return assert_err(result.is_ok, "exec_params with multiple params returns Err in stub mode");
}

// -- Result parsing stub tests ----------------------------------------------

fn test_ntuples_returns_zero_in_stub_mode() -> Int {
  return assert_eq_int(libpq.ntuples(1), 0, "ntuples returns 0 in stub mode");
}

fn test_nfields_returns_zero_in_stub_mode() -> Int {
  return assert_eq_int(libpq.nfields(1), 0, "nfields returns 0 in stub mode");
}

fn test_fname_returns_nonempty_stub_str() -> Int {
  let name = libpq.fname(1, 0);
  return assert(name.len() > 0, "fname returns non-empty stub string");
}

fn test_get_value_returns_nonempty_stub_str() -> Int {
  let val = libpq.get_value(1, 0, 0);
  return assert(val.len() > 0, "get_value returns non-empty stub string");
}

fn test_get_is_null_returns_true_in_stub_mode() -> Int {
  let isnull = libpq.get_is_null(1, 0, 0);
  return assert(isnull, "get_is_null returns true in stub mode");
}

fn test_clear_with_nonzero_res_is_noop() -> Int {
  libpq.clear(1);
  return 0;
}

// -- Async/non-blocking stub tests ------------------------------------------

fn test_send_query_returns_err_in_stub_mode() -> Int {
  let result = libpq.send_query(1, "SELECT 1");
  return assert_err(result.is_ok, "send_query returns Err in SPEC stub mode");
}

fn test_get_result_returns_err_in_stub_mode() -> Int {
  let result = libpq.get_result(1);
  return assert_err(result.is_ok, "get_result returns Err in SPEC stub mode");
}

fn test_consume_input_returns_err_in_stub_mode() -> Int {
  let result = libpq.consume_input(1);
  return assert_err(result.is_ok, "consume_input returns Err in SPEC stub mode");
}

fn test_is_busy_returns_false_in_stub_mode() -> Int {
  let busy = libpq.is_busy(1);
  return assert(!busy, "is_busy returns false in stub mode");
}

// -- Transaction helper stub tests ------------------------------------------

fn test_begin_returns_err_in_stub_mode() -> Int {
  let result = libpq.begin(1);
  return assert_err(result.is_ok, "begin returns Err (delegates to exec) in stub mode");
}

fn test_commit_returns_err_in_stub_mode() -> Int {
  let result = libpq.commit(1);
  return assert_err(result.is_ok, "commit returns Err (delegates to exec) in stub mode");
}

fn test_rollback_returns_err_in_stub_mode() -> Int {
  let result = libpq.rollback(1);
  return assert_err(result.is_ok, "rollback returns Err (delegates to exec) in stub mode");
}

// -- Transaction composition test -------------------------------------------

fn test_full_transaction_cycle_returns_err() -> Int {
  let begin_r = libpq.begin(1);
  let exec_r = libpq.exec(1, "INSERT INTO t VALUES (1)");
  let commit_r = libpq.commit(1);
  let all_err = !begin_r.is_ok && !exec_r.is_ok && !commit_r.is_ok;
  return assert(all_err, "full transaction cycle returns all Err in stub mode");
}

// -- Multiple-result round-trip test (stub path) ----------------------------

fn test_exec_to_parse_roundtrip_stub() -> Int {
  let res = libpq.exec(1, "SELECT 1");
  return assert(!res.is_ok, "exec->parse round-trip: exec returns Err in stub mode");
}

// -- Smoke: all non-result functions are callable ---------------------------

fn test_smoke_all_nonresult_callable() -> Int {
  libpq.close(1);
  let s = libpq.status(1);
  let msg = libpq.error_message(1);
  let n = libpq.ntuples(1);
  let f = libpq.nfields(1);
  let name = libpq.fname(1, 0);
  let val = libpq.get_value(1, 0, 0);
  let isnull = libpq.get_is_null(1, 0, 0);
  libpq.clear(1);
  let busy = libpq.is_busy(1);
  let ok = s == libpq.CONNECTION_BAD && msg.len() > 0 && n == 0 && f == 0 && name.len() > 0 && val.len() > 0 && isnull && !busy;
  return assert(ok, "all non-Result functions are callable and return defaults");
}

// -- Smoke: all Result-returning functions return Err -----------------------

fn test_smoke_all_result_funcs_return_err() -> Int {
  var params: Vec[Str] = Vec[Str].new();
  params.push("x");
  let r1 = libpq.connect("dbname=test");
  let r2 = libpq.exec(1, "SELECT 1");
  let r3 = libpq.exec_params(1, "SELECT $1", params);
  let r4 = libpq.send_query(1, "SELECT 1");
  let r5 = libpq.get_result(1);
  let r6 = libpq.consume_input(1);
  let r7 = libpq.begin(1);
  let r8 = libpq.commit(1);
  let r9 = libpq.rollback(1);
  let all_err = !r1.is_ok && !r2.is_ok && !r3.is_ok && !r4.is_ok && !r5.is_ok && !r6.is_ok && !r7.is_ok && !r8.is_ok && !r9.is_ok;
  return assert(all_err, "all 9 Result-returning functions return Err in stub mode");
}

// -- Test runner ------------------------------------------------------------

pub fn run_all_tests() -> Int {
  var failures: Int = 0;
  failures = failures + test_type_constants_defined();
  failures = failures + test_connection_ok_is_zero();
  failures = failures + test_connection_bad_is_one();
  failures = failures + test_pgres_tuples_ok_is_two();
  failures = failures + test_connect_returns_err_in_stub_mode();
  failures = failures + test_connect_with_minimal_conninfo_returns_err();
  failures = failures + test_close_with_nonzero_conn_is_noop();
  failures = failures + test_status_returns_connection_bad_in_stub_mode();
  failures = failures + test_error_message_returns_nonempty_str();
  failures = failures + test_exec_returns_err_in_stub_mode();
  failures = failures + test_exec_with_complex_query_returns_err();
  failures = failures + test_exec_params_returns_err_in_stub_mode();
  failures = failures + test_exec_params_with_multiple_params_returns_err();
  failures = failures + test_ntuples_returns_zero_in_stub_mode();
  failures = failures + test_nfields_returns_zero_in_stub_mode();
  failures = failures + test_fname_returns_nonempty_stub_str();
  failures = failures + test_get_value_returns_nonempty_stub_str();
  failures = failures + test_get_is_null_returns_true_in_stub_mode();
  failures = failures + test_clear_with_nonzero_res_is_noop();
  failures = failures + test_send_query_returns_err_in_stub_mode();
  failures = failures + test_get_result_returns_err_in_stub_mode();
  failures = failures + test_consume_input_returns_err_in_stub_mode();
  failures = failures + test_is_busy_returns_false_in_stub_mode();
  failures = failures + test_begin_returns_err_in_stub_mode();
  failures = failures + test_commit_returns_err_in_stub_mode();
  failures = failures + test_rollback_returns_err_in_stub_mode();
  failures = failures + test_full_transaction_cycle_returns_err();
  failures = failures + test_exec_to_parse_roundtrip_stub();
  failures = failures + test_smoke_all_nonresult_callable();
  failures = failures + test_smoke_all_result_funcs_return_err();
  return failures;
}
